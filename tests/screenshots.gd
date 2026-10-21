extends Node
## Renders gameplay screenshots into user://screenshots/ for quick visual
## checks. Needs a real renderer (not --headless), e.g.:
##   xvfb-run godot res://tests/screenshots.tscn -- --touch
## Add --items for just the stage 2 shots (inventory, weapons, stealth), or
## --stage3 for the stage 3 ones (character, health, zombie types, the lab).

var _main: Node3D
var _cam: Camera3D


func _ready() -> void:
	GameState.start_world(GameState.create_world("Screenshots", 8192.0, 12345, 1, 0, "screenshots"))
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_run.call_deferred()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var path := "user://screenshots/%s.png" % shot_name
	get_viewport().get_texture().get_image().save_png(path)
	print("saved %s  (draw calls: %d, objects: %d)" % [ProjectSettings.globalize_path(path),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])


func _wait_streaming() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
		if _main.streamer._jobs.is_empty() and _main.streamer._done.is_empty() and Time.get_ticks_msec() - t0 > 1500:
			break


## First-person view from the player at a world position.
func _go(pos: Vector2, yaw: float, pitch_deg := -5.0, lift := 0.2) -> void:
	_cam.current = false
	_main.player.camera.current = true
	var gen: WorldGen = _main.gen
	_main.player.global_position = Vector3(pos.x, gen.height(pos.x, pos.y) + lift, pos.y)
	_main.player.rotation.y = yaw
	_main.player.head.rotation.x = deg_to_rad(pitch_deg)
	await _wait_streaming()


## Free camera (for aerial views). The player is moved there so it streams.
func _fly(pos: Vector3, look_at: Vector3) -> void:
	_main.player.global_position = Vector3(look_at.x, _main.gen.height(look_at.x, look_at.z) + 1.0, look_at.z)
	await _wait_streaming()
	_cam.global_position = pos
	_cam.look_at(look_at)
	_cam.current = true
	await get_tree().create_timer(0.3).timeout


func _yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(-d.x, -d.y)


func _run() -> void:
	while not _main.world_ready or not _main.player.active:
		await get_tree().process_frame
	var player: Player = _main.player
	_cam = Camera3D.new()
	_cam.far = 1500.0
	add_child(_cam)
	GameState.time_of_day = 10.0
	var gen: WorldGen = _main.gen
	if "--items" in OS.get_cmdline_user_args():
		await _items_shots()
		GameState.delete_world("screenshots")
		get_tree().quit()
		return
	if "--stage3" in OS.get_cmdline_user_args():
		await _stage3_shots()
		GameState.delete_world("screenshots")
		get_tree().quit()
		return

	# A street corner in the spawn town.
	var spawn: Vector3 = gen.spawn_point()
	await _go(Vector2(spawn.x, spawn.z), player.rotation.y, -4.0)
	await _shot("01_spawn_street")

	# Find a two-storey house and a shop.
	var house: Dictionary = {}
	var shop: Dictionary = {}
	for t in gen.towns:
		for lot in t.lots:
			if house.is_empty() and lot.type == "colonial":
				house = lot
			if shop.is_empty() and lot.type in ["diner", "pharmacy", "hardware", "grocery"]:
				shop = lot
	if not house.is_empty():
		var c: Vector2 = house.center
		var front := Vector2(sin(house.yaw), cos(house.yaw))
		var view: Vector2 = c + front * (house.d * 0.5 + 6.0) + Vector2(front.y, -front.x) * 6.0
		await _go(view, _yaw_to(view, c), -6.0)
		await _shot("02_house_front")
		# Inside: stand in the middle of the house, looking at the back.
		var inside: Vector2 = c + front * (house.d * 0.5 - 10.0)
		_main.player.global_position = Vector3(inside.x, house.floor + 0.2, inside.y)
		_main.player.rotation.y = _yaw_to(inside, c - front * 20.0) + 0.6
		_main.player.head.rotation.x = deg_to_rad(-12.0)
		await get_tree().create_timer(0.4).timeout
		await _shot("03_house_inside")
	if not shop.is_empty():
		var c: Vector2 = shop.center
		var front := Vector2(sin(shop.yaw), cos(shop.yaw))
		var view: Vector2 = c + front * (shop.d * 0.5 + 10.0) + Vector2(front.y, -front.x) * 14.0
		await _go(view, _yaw_to(view, c), -3.0)
		await _shot("04_main_street")

	# Aerial view over a town.
	var town: Dictionary = gen.settlements.list.filter(func(s): return s.kind == Settlements.Kind.TOWN)[0]
	var tc: Vector2 = town.center
	await _fly(Vector3(tc.x + 160, gen.height(tc.x, tc.y) + 120, tc.y + 160), Vector3(tc.x, gen.height(tc.x, tc.y), tc.y))
	await _shot("05_town_aerial")

	for site in gen.settlements.sites:
		if site.type == "airport":
			var sc: Vector2 = site.center
			await _fly(Vector3(sc.x + 300, site.base + 140, sc.y + 260), Vector3(sc.x, site.base, sc.y))
			await _shot("06_airport")
			break
	for site in gen.settlements.sites:
		if site.type == "research":
			var sc: Vector2 = site.center
			await _fly(Vector3(sc.x + 90, site.base + 50, sc.y + 110), Vector3(sc.x, site.base, sc.y))
			await _shot("07_research_center")
			break

	# A river.
	if not gen.hydro.rivers.is_empty():
		var r: Dictionary = gen.hydro.rivers[0]
		var pts: PackedVector2Array = r.pts
		var p := pts[pts.size() / 2]
		var side := (pts[pts.size() / 2 + 1] - p).normalized().orthogonal()
		var view := p + side * 30.0
		await _go(view, _yaw_to(view, p), -8.0, 1.0)
		await _shot("08_river")

	# Dusk zombies on a street.
	GameState.time_of_day = 19.6
	await _go(Vector2(spawn.x, spawn.z), player.rotation.y, -4.0)
	_main.zombies.clear_all()
	var fwd := -player.global_basis.z
	for i in 5:
		var zp: Vector3 = player.global_position + fwd * (6.0 + i * 2.5) + player.global_basis.x * (i - 2) * 1.6
		zp.y = gen.height(zp.x, zp.z)
		_main.zombies._spawn(zp)
		_main.zombies._active[-1].rotation.y = player.rotation.y + PI
	await get_tree().create_timer(0.3).timeout
	await _shot("09_dusk_zombies")
	# Close-up of a zombie.
	GameState.time_of_day = 11.0
	var zc: Zombie = _main.zombies._active[0]
	var zp: Vector3 = zc.global_position
	_cam.global_position = zp + Vector3(1.6, 1.6, -2.2).rotated(Vector3.UP, zc.rotation.y)
	_cam.look_at(zp + Vector3(0, 1.2, 0))
	_cam.current = true
	await get_tree().create_timer(0.4).timeout
	await _shot("10_zombie_closeup")
	# Main menu.
	_main.queue_free()
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(0.4).timeout
	await _shot("11_main_menu")
	GameState.delete_world("screenshots")
	get_tree().quit()


func _equip(slot: String, id: String, ammo := 0, parts := {}) -> void:
	var it := ItemDB.make(id, 1, 0.8)
	if ammo > 0:
		it.a = ammo
	if not parts.is_empty():
		it.att = parts
	GameState.inventory.equip[slot] = it
	GameState.inventory.notify()
	_main.player.weapons.current = ""
	_main.player.weapons.select(slot)


## Stage 2: inventory, weapons in hand, scope, stealth eye, fire.
func _items_shots() -> void:
	var player: Player = _main.player
	var gen: WorldGen = _main.gen
	var w := player.weapons
	var inv := GameState.inventory
	var spawn: Vector3 = gen.spawn_point()
	await _go(Vector2(spawn.x, spawn.z), player.rotation.y, -4.0)
	_main.zombies.clear_all()
	_main.zombies.max_zombies = 0
	# Wait for the icon atlas.
	var t0 := Time.get_ticks_msec()
	while ItemIcons.texture == null and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	if ItemIcons.texture:
		ItemIcons.texture.get_image().save_png("user://screenshots/20_item_icons.png")

	# A loaded-out survivor looting a police locker.
	inv.add(ItemDB.make("hiking_backpack"))
	inv.add(ItemDB.make("tactical_vest"))
	_equip("primary", "assault_rifle", 22, {"scope": "red_dot"})
	_equip("sidearm", "pistol_9mm", 9)
	_equip("melee", "fire_axe")
	inv.equip.throw = ItemDB.make("molotov", 1)
	for id in ["ammo_556", "ammo_9mm", "bandage", "canned_beans", "water_bottle", "first_aid_kit", "painkillers",
			"crowbar", "energy_bar", "hunting_knife", "grenade", "noise_maker", "suppressor"]:
		inv.add(ItemDB.make(id, 30 if id.begins_with("ammo") else 1, 0.7))
	var locker := {"id": "shot_locker", "type": "locker", "bld": "police", "pos": player.global_position}
	var items: Array = []
	var g := ItemGrid.new("c", "", 4, 6, items)
	for id in ["pump_shotgun", "ammo_12g", "ammo_12g", "weapon_light", "bandage", "school_backpack"]:
		g.add(ItemDB.make(id, 8 if id.begins_with("ammo") else 1, 0.6))
	GameState.containers[locker.id] = items
	_main.inventory_ui.open(locker)
	await get_tree().create_timer(0.3).timeout
	_main.inventory_ui._selected = inv.equip.primary
	_main.inventory_ui._update_info()
	_main.inventory_ui._board.queue_redraw()
	await _shot("12_inventory_touch")
	GameState.device = "xbox"
	_main.inventory_ui._pad_mode = true
	_main.inventory_ui._cursor = {"area": _main.inventory_ui._area_index("container"), "x": 0, "y": 0}
	_main.inventory_ui._update_info()
	_main.inventory_ui._board.queue_redraw()
	await _shot("13_inventory_gamepad")
	_main.inventory_ui.close()
	GameState.device = "kbm"

	# Weapons in hand.
	player.head.rotation.x = deg_to_rad(-3.0)
	w.select("sidearm")
	await get_tree().create_timer(0.6).timeout
	await _shot("14_pistol")
	w.select("primary")
	Input.action_press("aim")
	await get_tree().create_timer(0.8).timeout
	await _shot("15_rifle_red_dot_ads")
	Input.action_release("aim")
	_equip("primary", "hunting_rifle", 5, {"scope": "scope"})
	Input.action_press("aim")
	await get_tree().create_timer(0.8).timeout
	await _shot("16_scope")
	Input.action_release("aim")
	_equip("primary", "compound_bow")
	inv.add(ItemDB.make("arrow", 6))
	Input.action_press("attack")
	await get_tree().create_timer(0.8).timeout
	await _shot("17_bow_drawn")
	Input.action_release("attack")
	await get_tree().create_timer(0.3).timeout
	w.select("melee")
	await get_tree().create_timer(0.6).timeout
	await _shot("18_fire_axe")

	# Sneaking up on a zombie: the stealth eye fills.
	player.crouching = true
	_main.zombies.max_zombies = 0
	var fwd := -player.global_basis.z
	var zp: Vector3 = player.global_position + fwd * 9.0
	zp.y = gen.height(zp.x, zp.z)
	_main.zombies._spawn(zp)
	var z: Zombie = _main.zombies._active[-1]
	z.rotation.y = player.rotation.y + PI
	z.awareness = 0.6
	z.state = Zombie.State.INVESTIGATE
	z.target = z.position
	w.select("throw")
	# Software rendering is slow, so hold the zombie at "suspicious".
	for k in 4:
		await get_tree().process_frame
		z.awareness = 0.6
		z.state = Zombie.State.INVESTIGATE
	await _shot("19_stealth")
	player.head.rotation.x = deg_to_rad(-25.0)
	w._throw(0.4)
	await get_tree().create_timer(1.6).timeout
	player.head.rotation.x = deg_to_rad(-12.0)
	await get_tree().create_timer(0.3).timeout
	await _shot("21_molotov_fire")


## Stage 3: character creation, the Body tab, zombie types, infection, the
## research lab, the map, death and memorials.
func _stage3_shots() -> void:
	var player: Player = _main.player
	var gen: WorldGen = _main.gen
	var inv := GameState.inventory
	var spawn: Vector3 = gen.spawn_point()
	_main.zombies.max_zombies = 0
	_main.zombies.clear_all()
	await _go(Vector2(spawn.x, spawn.z), player.rotation.y, -4.0)
	var t0 := Time.get_ticks_msec()
	while ItemIcons.texture == null and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	if ItemIcons.texture:
		ItemIcons.texture.get_image().save_png("user://screenshots/31_item_icons.png")

	# Character creator over the game.
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var cc := CharacterCreator.new()
	layer.add_child(cc)
	await get_tree().create_timer(0.5).timeout
	cc.character.background = "hunter"
	cc.character.apply_background()
	cc.character.traits = ["athletic", "smoker", "clumsy", "short_sighted"]
	cc.character.look = {"build": 1, "skin": 2, "hair": 2, "hair_col": 4, "beard": 0}
	cc.character.name = "Robin"
	cc._name.text = "Robin"
	cc._refresh()
	await get_tree().create_timer(0.6).timeout
	await _shot("22_character_creator")
	layer.queue_free()
	GameState.character = cc.character
	GameState.give_starting_kit()

	# Body tab: clothes, injuries, protection.
	var b := player.body
	b.add("bite", "arm_l", true).b = true
	b.add("deep_wound", "leg_r")
	b.add("fracture", "arm_r").s = true
	b.injuries[0].inf = 0.25
	inv.add(ItemDB.make("bandage", 2))
	inv.add(ItemDB.make("suture_kit"))
	inv.add(ItemDB.make("sewing_kit"))
	inv.add(ItemDB.make("antibiotics"))
	inv.add(ItemDB.make("motorcycle_helmet"))
	inv.equip.jacket.c = 0.55
	player.health = 62.0
	_main.inventory_ui.open({})
	_main.inventory_ui._set_tab("body")
	await get_tree().create_timer(0.3).timeout
	_main.inventory_ui._selected = inv.equip.jacket
	_main.inventory_ui._update_info()
	_main.inventory_ui._board.queue_redraw()
	await _shot("23_body_tab")
	_main.inventory_ui.close()

	# Infected and bleeding: the screen fades and pulses.
	b.infect(0.5)
	b.infection = 0.62
	player.head.rotation.x = deg_to_rad(-3.0)
	player.weapons.select("melee")
	await get_tree().create_timer(0.8).timeout
	await _shot("24_infected_view")
	b.clear()
	player.health = 100.0

	# Every zombie type in a row.
	var fwd := -player.global_basis.z
	var side := player.global_basis.x
	var types := ["walker", "runner", "brute", "screamer", "crawler", "soldier", "scientist"]
	for k in types.size():
		var zp: Vector3 = player.global_position + fwd * 7.0 + side * (k - 3) * 1.7
		zp.y = gen.height(zp.x, zp.z)
		var z: Zombie
		if types[k] == "scientist":
			z = _main.zombies._spawn(zp, "walker", ZombieModel.type_meshes.scientist[0])
		else:
			z = _main.zombies._spawn(zp, types[k])
		z.rotation.y = player.rotation.y + PI
		z.trap(30.0)
		if types[k] == "screamer":
			z._play_once("scream", 30.0)
			z._anim.seek(0.6, true)
	var mid: Vector3 = player.global_position + fwd * 7.0
	_cam.global_position = mid - fwd * 6.5 + Vector3(0, 2.2, 0)
	_cam.look_at(mid + Vector3(0, 0.9, 0))
	_cam.current = true
	await get_tree().create_timer(0.6).timeout
	await _shot("25_zombie_types")
	_main.zombies.clear_all()

	# The research lab: outside, then the corridor inside by flashlight.
	var site: Dictionary = gen.settlements.sites.filter(func(st): return st.type == "research")[0]
	var lab_lot: Dictionary = SiteLayout.build(site, gen).lots.filter(func(l): return l.type == "research_lab")[0]
	var c: Vector2 = lab_lot.center
	var xf := Transform3D(Basis(Vector3.UP, lab_lot.yaw), Vector3(c.x, lab_lot.floor, c.y))
	var front := xf * Vector3(0, 0, 45)
	await _fly(front + Vector3(0, 28, 0), xf * Vector3(0, 2, 0))
	await get_tree().create_timer(0.5).timeout
	await _shot("26_research_site")
	GameState.time_of_day = 22.0
	var lobby := xf * Vector3(0, 0.1, 9.0)
	_cam.current = false
	player.camera.current = true
	player.global_position = lobby
	player.rotation.y = lab_lot.yaw
	player.head.rotation.x = deg_to_rad(-6.0)
	player.flashlight.visible = true
	await _wait_streaming()
	player.global_position = lobby
	await get_tree().create_timer(0.8).timeout
	player._update_focus()
	await _shot("27_lab_corridor")
	player.flashlight.visible = false
	GameState.time_of_day = 11.0

	# The map.
	await _go(Vector2(spawn.x, spawn.z), player.rotation.y, -4.0)
	for k in 30:
		GameState.explore(spawn + Vector3(k * 40.0, 0, sin(k * 0.3) * 200.0), 160.0)
	_main.pause_menu.open()
	_main.pause_menu._open_map()
	await get_tree().create_timer(0.4).timeout
	await _shot("28_map")
	_main.pause_menu.close()

	# Turned: the death screen.
	player.body.infect(0.0)
	player.body.infection = 0.9999
	player.body.turn_hours = 0.001
	await get_tree().create_timer(0.6).timeout
	await _shot("29_turned")

	# A memorial in the menu.
	GameState.world.death_rule = GameState.DeathRule.PERMADEATH
	GameState.mark_world_lost("Turned into a zombie")
	var meta := GameState.world.duplicate()
	_main.queue_free()
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(0.3).timeout
	menu._show_memorial(meta)
	await get_tree().create_timer(0.4).timeout
	await _shot("30_memorial")
