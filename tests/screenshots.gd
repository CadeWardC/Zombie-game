extends Node
## Renders gameplay screenshots into user://screenshots/ for quick visual
## checks. Needs a real renderer (not --headless), e.g.:
##   xvfb-run godot res://tests/screenshots.tscn -- --touch
## Add --items for just the stage 2 shots (inventory, weapons, stealth), or
## --stage3 for the stage 3 ones (character, health, zombie types, the lab),
## --stage5 for vehicles, or --stage6 for survival (crafting, bases,
## weather, animals, traders).

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
	if "--stage6" in OS.get_cmdline_user_args():
		await _stage6_shots()
		GameState.delete_world("screenshots")
		get_tree().quit()
		return
	if "--stage5" in OS.get_cmdline_user_args():
		await _stage5_shots()
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


## A vehicle record placed at `pos` (fuelled, keys in it) with its node.
func _vehicle(id: String, type: String, pos: Vector3, yaw: float, model := -1) -> Vehicle:
	var r := VehicleDB.roll(id, type, model)
	r.merge({"fuel": float(VehicleDB.get_def(type).tank) * 0.6, "keys": true, "bat": 1.0, "eng": 1.0, "parts": true,
		"locked": false, "flat": 0, "p": [pos.x, pos.y, pos.z], "yaw": yaw}, true)
	GameState.ws.vehicles[id] = r
	return _main.vehicles._spawn(r)


func _drive(v: Vehicle, seconds: float) -> void:
	_cam.current = false
	_main.player.enter_vehicle(v, 0)
	_main.player.camera.current = true
	Input.action_press("move_forward")
	await get_tree().create_timer(seconds).timeout
	Input.action_release("move_forward")


func _stage5_shots() -> void:
	var gen: WorldGen = _main.gen
	var player: Player = _main.player
	var spawn: Vector3 = gen.spawn_point()
	# Parked cars in town become drivable.
	await _go(Vector2(spawn.x, spawn.z), player.rotation.y, -4.0)
	var spots := []
	for c in _main.streamer.chunks():
		if c.lod == 0:
			for sp in c.vehicle_spots:
				if int(sp.m) >= 0:
					spots.append(sp)
	spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.xf as Transform3D).origin.distance_to(spawn) < (b.xf as Transform3D).origin.distance_to(spawn))
	if not spots.is_empty():
		var sp: Dictionary = spots[0]
		var xf: Transform3D = sp.xf
		var v: Vehicle = _main.vehicles.activate(sp)
		v.rec.merge({"fuel": 30.0, "keys": true, "bat": 1.0, "eng": 1.0, "parts": true, "locked": false, "flat": 1}, true)
		var side := xf * Vector3(2.6, 0, 0.5)
		player.global_position = side + Vector3(0, 0.2, 0)
		player.look_at(Vector3(xf.origin.x, player.global_position.y, xf.origin.z))
		player.rotation.x = 0.0
		player.head.rotation.x = deg_to_rad(-20.0)
		await get_tree().create_timer(0.4).timeout
		player._update_focus()
		await _shot("45_vehicle_prompt")
		_main.vehicle_menu.open(v)
		await get_tree().create_timer(0.3).timeout
		await _shot("46_vehicle_menu")
		_main.vehicle_menu.close()
		await _drive(v, 1.6)
		await _shot("47_driving")
		GameState.time_of_day = 22.5
		v.set_lights(true)
		Input.action_press("jump")
		await get_tree().create_timer(1.5).timeout
		Input.action_release("jump")
		await _shot("48_headlights_night")
		GameState.time_of_day = 10.0
		player.exit_vehicle(true)
	# Bikes.
	var bp := Vector3(spawn.x + 3.0, 0, spawn.z + 3.0)
	bp.y = gen.height(bp.x, bp.z)
	_vehicle("shot_bike", "bicycle", bp, 0.4)
	var mp := bp + Vector3(1.6, 0, 0.4)
	mp.y = gen.height(mp.x, mp.z)
	_vehicle("shot_moto", "motorbike", mp, 0.9)
	await get_tree().create_timer(0.5).timeout
	_cam.global_position = bp + Vector3(-2.5, 1.5, 3.2)
	_cam.look_at(bp + Vector3(0.8, 0.5, 0))
	_cam.current = true
	await get_tree().create_timer(0.3).timeout
	await _shot("49_bicycle_motorbike")
	# A helicopter over town.
	var hp := Vector3(spawn.x - 20.0, 0, spawn.z)
	for k in 30:
		var c := Vector2(spawn.x, spawn.z) + Vector2.from_angle(k * 0.9) * (25.0 + k * 3.0)
		if not gen.is_inside_building(c.x, c.y) and not gen.is_inside_building(c.x + 6.0, c.y) and not gen.is_inside_building(c.x - 6.0, c.y):
			hp = Vector3(c.x, 0, c.y)
			break
	hp.y = gen.height(hp.x, hp.z) + 0.2
	var heli := _vehicle("shot_heli", "helicopter", hp, 0.0)
	await get_tree().create_timer(0.3).timeout
	_main.player.enter_vehicle(heli, 0)
	_cam.current = false
	player.camera.current = true
	Input.action_press("jump")
	await get_tree().create_timer(3.0).timeout
	Input.action_release("jump")
	Input.action_press("move_forward")
	await get_tree().create_timer(1.5).timeout
	Input.action_release("move_forward")
	await _wait_streaming()
	await _shot("50_helicopter")
	heli.global_position.y = gen.height(heli.global_position.x, heli.global_position.z) + 0.3
	heli.airborne = false
	player.exit_vehicle(true)
	# A light aircraft taking off from the airport.
	for site in gen.settlements.sites:
		if site.type == "airport":
			var sc: Vector2 = site.center
			var pp := Vector3(sc.x - 200.0, site.base + 0.3, sc.y)
			await _go(Vector2(pp.x, pp.z + 8.0), 0.0)
			var plane := _vehicle("shot_plane", "prop_plane", pp, PI * 0.5)
			await get_tree().create_timer(0.3).timeout
			_main.player.enter_vehicle(plane, 0)
			player.camera.current = true
			plane.throttle = 1.0
			plane.speed = 32.0
			Input.action_press("move_back")
			await get_tree().create_timer(1.6).timeout
			Input.action_release("move_back")
			await _shot("51_plane_takeoff")
			plane.speed = 0.0
			plane.airborne = false
			plane.global_position = pp
			player.exit_vehicle(true)
			break
	# A boat at its dock.
	if not gen.boat_spots.is_empty():
		var b: Dictionary = gen.boat_spots[0]
		var shore: Vector2 = b.shore
		await _go(shore, _yaw_to(shore, Vector2(b.p.x, b.p.z)), -8.0, 0.5)
		await get_tree().create_timer(1.2).timeout
		await _shot("52_boat_dock")
		var boat: Vehicle = _main.vehicles.nodes.get(b.id)
		if boat:
			boat.rec.merge({"fuel": 20.0, "keys": true}, true)
			await _drive(boat, 2.5)
			await _shot("53_boating")
			player.exit_vehicle(true)


## Open ground near a town for a small base.
func _open_ground(around: Vector3) -> Vector3:
	var gen: WorldGen = _main.gen
	for k in 60:
		var p := Vector2(around.x, around.z) + Vector2.from_angle(k * 0.7) * (120.0 + k * 8.0)
		if gen.town_weight(p.x, p.y) == 0.0 and gen.water_level(p.x, p.y) == -INF and not gen.is_inside_building(p.x, p.y) \
				and gen.terrain.slope_at(p.x, p.y) < 0.08:
			return Vector3(p.x, gen.height(p.x, p.y), p.y)
	return around


func _stage6_shots() -> void:
	var gen: WorldGen = _main.gen
	var player: Player = _main.player
	var spawn: Vector3 = gen.spawn_point()
	var bases: BaseManager = _main.bases
	var c := _open_ground(spawn)
	await _go(Vector2(c.x, c.z + 9.0), 0.0, -12.0)
	# A small base: walls, a gate, a watchtower, a fire, crafting and a garden.
	var y := func(x: float, z: float) -> Vector3: return Vector3(x, gen.height(x, z), z)
	for k in 4:
		bases.add("wall", y.call(c.x - 5.0 + k * 2.0, c.z - 6.0), 0.0)
	bases.add("gate", y.call(c.x + 3.0, c.z - 6.0), 0.0)
	for k in 3:
		bases.add("wall", y.call(c.x - 6.0, c.z - 5.0 + k * 2.0), PI * 0.5)
	bases.add("watchtower", y.call(c.x + 6.0, c.z - 3.0), 0.0)
	var fire := bases.add("campfire", y.call(c.x - 1.0, c.z + 1.0), 0.0)
	fire.rec.lit = GameState.hours() + 5.0
	fire.refresh()
	bases.add("workbench", y.call(c.x - 3.5, c.z - 2.5), 0.0)
	bases.add("crate", y.call(c.x - 1.5, c.z - 3.0), 0.0)
	bases.add("bed", y.call(c.x + 2.0, c.z - 3.0), PI * 0.5)
	bases.add("rain_collector", y.call(c.x - 4.5, c.z + 2.5), 0.0)
	var plot := bases.add("farm_plot", y.call(c.x + 2.5, c.z + 2.0), 0.0)
	plot.rec.crop = {"k": "corn", "g": 1.0, "w": GameState.hours(), "u": GameState.hours()}
	plot.refresh()
	var plot2 := bases.add("farm_plot", y.call(c.x + 2.5, c.z + 4.5), 0.0)
	plot2.rec.crop = {"k": "tomato", "g": 0.6, "w": GameState.hours(), "u": GameState.hours()}
	plot2.refresh()
	bases.add("spikes", y.call(c.x - 2.0, c.z - 8.0), 0.0)
	await get_tree().create_timer(0.6).timeout
	_cam.global_position = c + Vector3(9.0, 7.0, 11.0)
	_cam.look_at(c + Vector3(0, 1.0, -1.5))
	_cam.current = true
	await get_tree().create_timer(0.3).timeout
	await _shot("54_base_day")
	GameState.time_of_day = 20.8
	await get_tree().create_timer(0.5).timeout
	_cam.global_position = c + Vector3(3.0, 2.2, 5.0)
	_cam.look_at(c + Vector3(-1.0, 0.5, 0.5))
	await _shot("55_campfire_dusk")
	GameState.time_of_day = 10.0
	# Crafting menu and the build preview.
	_cam.current = false
	player.camera.current = true
	player.global_position = c + Vector3(0, 0.3, 4.0)
	player.rotation.y = 0.0
	player.head.rotation.x = deg_to_rad(-15.0)
	for id in ["plank", "nails", "hammer", "log", "saw", "rag", "scrap_metal"]:
		GameState.inventory.add(ItemDB.make(id, 10 if id in ["plank", "nails", "rag"] else 2))
	_main.craft_menu.open("Weapons")
	await get_tree().create_timer(0.4).timeout
	await _shot("56_crafting")
	_main.craft_menu.open("Build")
	await get_tree().create_timer(0.3).timeout
	await _shot("57_build_tab")
	_main.craft_menu.close()
	player.global_position = c + Vector3(-9.0, 0.3, 6.0)
	player.rotation.y = 0.4
	player.head.rotation.x = deg_to_rad(-25.0)
	player.start_build("wall")
	for k in 3:
		player.build.update(0.016)
		await get_tree().process_frame
	await _shot("58_build_preview")
	player.build.stop()
	# Weather.
	for w in [["rain", "59_rain"], ["snow", "60_snow"], ["fog", "61_fog"], ["storm", "62_storm"]]:
		GameState.weather = {"k": w[0], "i": 1.0, "until": GameState.hours() + 50.0}
		if w[0] == "snow":
			GameState.day = 1 + Weather.season_days() * 3
		player.global_position = c + Vector3(8.0, 0.3, 14.0)
		player.rotation.y = 0.5
		player.head.rotation.x = deg_to_rad(-6.0)
		await get_tree().create_timer(1.5).timeout
		await _shot(w[1])
	GameState.day = 1
	GameState.weather = {"k": "clear", "i": 0.5, "until": GameState.hours() + 50.0}
	# Wildlife and a dog.
	var am: AnimalManager = _main.animals
	var wild := _open_ground(c + Vector3(150, 0, 0))
	await _go(Vector2(wild.x, wild.z + 10.0), 0.0, -5.0)
	for k in 3:
		var a := Animal.new()
		am.add_child(a)
		var q := wild + Vector3(k * 2.2 - 2.0, 0, -k * 1.5)
		q.y = gen.height(q.x, q.z)
		a.setup(["deer", "deer", "turkey"][k], q, gen)
		a.rotation.y = 1.2 + k * 0.4
		a.set_physics_process(false)
		am.animals.append(a)
	var rab := Animal.new()
	am.add_child(rab)
	rab.setup("rabbit", Vector3(wild.x + 2.0, gen.height(wild.x + 2.0, wild.z + 5.0), wild.z + 5.0), gen)
	rab.set_physics_process(false)
	var dp := wild + Vector3(-1.5, 0, 6.5)
	GameState.ws.dogs["shot_dog"] = {"id": "shot_dog", "owner": GameState.player_id, "hp": 80.0, "p": [dp.x, gen.height(dp.x, dp.z), dp.z], "stay": true}
	am._update_dogs(player.global_position)
	await get_tree().create_timer(0.6).timeout
	await _shot("63_wildlife_dog")
	# A trader camp and the power plant.
	for site in gen.settlements.sites:
		if site.type == "trader":
			var sc: Vector2 = site.center
			var front := sc + Vector2(0, -16).rotated(float(site.rot))
			await _go(front, _yaw_to(front, sc), -6.0, 0.3)
			await get_tree().create_timer(1.0).timeout
			await _shot("64_trader_camp")
			_main.trade_menu.open("camp%d" % int(site.id), _main.traders.trader_name("camp%d" % int(site.id)))
			await get_tree().create_timer(0.3).timeout
			await _shot("65_trading")
			_main.trade_menu.close()
			break
	for site in gen.settlements.sites:
		if site.type == "power_plant":
			var sc: Vector2 = site.center
			await _fly(Vector3(sc.x + 160, site.base + 90, sc.y + 140), Vector3(sc.x, site.base, sc.y))
			await _shot("66_power_plant")
			break
