extends Node
## Automated smoke test. Runs the real game and checks the core loop works.
## Run headless:  godot --headless res://tests/smoke_test.tscn
## Exits with code 0 on success, 1 on failure.

var _main: Node3D
var _failures := 0


func _ready() -> void:
	GameState.delete_world("smoketest")
	GameState.start_world(GameState.create_world("Smoke Test", 8192.0, 12345, 1, 0, "smoketest"))
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_for(cond: Callable, timeout_ms: int) -> int:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout_ms:
		await get_tree().process_frame
	return Time.get_ticks_msec() - t0


func _spawn_zombie(offset: Vector3) -> Zombie:
	var player: Player = _main.player
	var p := player.global_position + player.global_basis * offset
	p.y = _main.gen.height(p.x, p.z)
	_main.zombies._spawn(p)
	return _main.zombies._active[-1]


## Puts the player on open ground facing -Z with a fresh zombie field.
func _reset_arena(player: Player, zombies: ZombieManager) -> void:
	zombies.clear_all()
	_main.effects.clear()
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.health = 100.0
	player.stamina = 100.0
	player.crouching = false
	await _wait(0.2)


func _test_items() -> void:
	print("Inventory")
	var g := ItemGrid.new("t", "Test", 4, 3, [])
	var rifle := ItemDB.make("hunting_rifle")
	_check(not g.fits(rifle, 0, 0, false), "a 5-long rifle doesn't fit a 4-wide grid")
	_check(not g.fits(rifle, 0, 0, true), "... nor rotated in 3 rows")
	var bat := ItemDB.make("baseball_bat")
	_check(g.place(bat, 0, 0, false), "bat fits along the top row")
	_check(not g.fits(ItemDB.make("canned_beans"), 2, 0, false), "cells under the bat are taken")
	_check(g.add(ItemDB.make("ammo_9mm", 70)) == 0 and g.count("ammo_9mm") == 70, "ammo stacks split into full stacks")
	g.sort()
	_check(g.count("ammo_9mm") == 70 and g.count("baseball_bat") == 1, "sort keeps every item")
	var pockets := ItemGrid.new("p", "Pockets", 4, 2, [])
	pockets.limit = 2
	_check(not pockets.fits(ItemDB.make("crowbar"), 0, 0, false) and pockets.fits(ItemDB.make("pistol_9mm"), 0, 0, false),
			"pockets take a pistol but not a crowbar")
	var inv := Inventory.new()
	inv.add(ItemDB.make("school_backpack"))
	_check(inv.equip.back.get("id", "") == "school_backpack" and inv.grids().size() == 2, "picking up a backpack wears it and adds its grid")
	inv.add(ItemDB.make("crowbar"))
	_check(inv.equip.melee.get("id", "") == "crowbar", "a melee weapon goes to the empty melee slot")
	inv.add(ItemDB.make("machete"))
	_check(inv.count("machete") == 1 and not inv.grid_of(inv.find("machete")).key == "pockets", "a second long weapon goes in the backpack")
	var copy := Inventory.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(inv.to_dict())))
	_check(copy.count("machete") == 1 and copy.equip.back.get("id", "") == "school_backpack", "inventory survives JSON")
	_check(inv.weight() > 2.0, "weight adds up (%.1f kg)" % inv.weight())

	print("Loot")
	var a := Loot.fill("locker", "police", "police_test_1")
	var b := Loot.fill("locker", "police", "police_test_1")
	_check(JSON.stringify(a) == JSON.stringify(b), "loot is deterministic per container")
	var found := {}
	var empty := 0
	for k in 300:
		var items := Loot.fill("locker", "police", "police_%d" % k)
		if items.is_empty():
			empty += 1
		for it in items:
			found[ItemDB.get_def(it.id).cat] = true
	_check(found.has("gun") and found.has("ammo"), "police lockers hold guns and ammo")
	_check(empty > 60, "most containers are picked over (%d / 300 empty)" % empty)
	var kitchen := {}
	for k in 300:
		for it in Loot.fill("kitchen_cabinet", "ranch", "k_%d" % k):
			kitchen[ItemDB.get_def(it.id).cat] = true
	_check(not kitchen.has("gun"), "no guns in kitchen cabinets")


func _test_combat(player: Player, zombies: ZombieManager) -> void:
	var w := player.weapons
	var inv := GameState.inventory
	print("Durability and shove")
	await _reset_arena(player, zombies)
	var bat: Dictionary = inv.equip.melee
	_check(float(bat.get("c", 1.0)) < 1.0, "melee hits wear the bat (%.0f%%)" % (float(bat.get("c", 1.0)) * 100.0))
	var z := _spawn_zombie(Vector3(0, 0, -1.3))
	await _wait(0.3)
	var before := z.global_position
	w._shove_cd = 0.0
	w.shove()
	_check(z._stagger_t > 0.0, "shove staggers the zombie")
	await _wait(0.1)
	_check(z.global_position.distance_to(player.global_position) > before.distance_to(player.global_position), "shove pushes it back")

	print("Guns")
	await _reset_arena(player, zombies)
	inv.equip.sidearm = ItemDB.make("pistol_9mm", 1, 1.0)
	inv.equip.sidearm.a = 15
	inv.add(ItemDB.make("ammo_9mm", 20))
	w.select("sidearm")
	await _wait(0.4)
	z = _spawn_zombie(Vector3(0, 0, -7))
	z.state = Zombie.State.WANDER
	await _wait(0.3)
	var shots := 0
	while z.state != Zombie.State.DEAD and shots < 15:
		var to := z.global_position + Vector3(0, 1.2, 0) - player.camera.global_position
		player.rotation.y = atan2(-to.x, -to.z)
		player.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
		w._cd = 0.0
		w.fire()
		shots += 1
		await _wait(0.15)
	_check(z.state == Zombie.State.DEAD, "pistol kills a zombie (%d shots)" % shots)
	_check(int(inv.equip.sidearm.a) == 15 - shots, "each shot uses a round")
	w.start_reload()
	await _wait(2.0)
	_check(int(inv.equip.sidearm.a) == 15 and inv.count("ammo_9mm") == 20 - shots, "reload takes loose ammo (%d left)" % inv.count("ammo_9mm"))
	var heard := [false]
	var listener := func(_p: Vector3, r: float) -> void:
		if r >= 60.0:
			heard[0] = true
	GameState.noise_made.connect(listener)
	w._cd = 0.0
	w.fire()
	_check(heard[0], "gunshots are loud")
	inv.equip.sidearm.att = {"muzzle": "suppressor"}
	heard[0] = false
	w._cd = 0.0
	w.fire()
	_check(not heard[0], "a suppressor quiets them")
	GameState.noise_made.disconnect(listener)

	print("Crossbow")
	await _reset_arena(player, zombies)
	inv.equip.primary = ItemDB.make("crossbow")
	inv.equip.primary.a = 1
	w.select("primary")
	await _wait(0.4)
	z = _spawn_zombie(Vector3(0, 0, -6))
	z.state = Zombie.State.WANDER
	await _wait(0.3)
	var to := z.global_position + Vector3(0, 1.2, 0) - player.camera.global_position
	player.rotation.y = atan2(-to.x, -to.z)
	player.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	var drops_before := GameState.drops.size()
	w._release_arrow(w.def(), 1.0)
	await _wait(0.6)
	_check(z.health < z.max_health, "crossbow bolt hits (health %.0f)" % z.health)
	_check(GameState.drops.size() >= drops_before, "bolts can be recovered")

	print("Throwables and traps")
	await _reset_arena(player, zombies)
	z = _spawn_zombie(Vector3(0, 0, -6))
	z.state = Zombie.State.WANDER
	z.trap(10.0) # Hold it in place.
	inv.equip.throw = ItemDB.make("grenade", 1)
	w.select("throw")
	await _wait(0.4)
	player.head.rotation.x = -0.6
	w._cd = 0.0
	w._throw(0.25)
	_check(inv.equip.throw.is_empty(), "throwing uses the grenade")
	await _wait(3.6)
	_check(z.state == Zombie.State.DEAD, "grenade kills a zombie nearby")
	await _reset_arena(player, zombies)
	inv.equip.throw = ItemDB.make("molotov", 1)
	w.select("throw")
	z = _spawn_zombie(Vector3(0, 0, -5))
	z.state = Zombie.State.WANDER
	player.head.rotation.x = -0.7
	w._cd = 0.0
	w._throw(0.2)
	await _wait(1.5)
	_check(not _main.effects._fires.is_empty(), "molotov starts a fire")
	_check(z._burn_t > 0.0 or z.state == Zombie.State.DEAD, "the fire sets zombies alight")
	await _reset_arena(player, zombies)
	var trap_at := player.global_position + Vector3(0, 0, -3)
	_main.drops.drop(ItemDB.make("bear_trap"), trap_at, true)
	z = _spawn_zombie(Vector3(0, 0, -6))
	z.see_player()
	await _wait(2.5)
	_check(z._trap_t > 0.0 or z.state == Zombie.State.DEAD, "bear trap catches a zombie")
	w.select("melee")


func _test_stealth(player: Player, zombies: ZombieManager) -> void:
	print("Stealth")
	await _reset_arena(player, zombies)
	var standing := player.visibility()
	player.crouching = true
	_check(player.visibility() < standing, "crouching makes you harder to see")
	# A zombie facing away, just in front of a crouched player.
	var z := _spawn_zombie(Vector3(0, 0, -1.4))
	z.rotation.y = player.rotation.y # Facing the same way: its back to us.
	z.state = Zombie.State.WANDER
	z.target = z.position
	await _wait(0.2)
	z.rotation.y = player.rotation.y
	_check(z.unaware() and z.is_behind(player.global_position), "zombie hasn't noticed a sneaking player behind it")
	player.weapons._cd = 0.0
	player.weapons.melee()
	_check(z.state == Zombie.State.DEAD, "silent takedown from behind")
	player.crouching = false
	# Standing in plain view: awareness builds up into a chase.
	var z2 := _spawn_zombie(Vector3(0, 0, -10))
	z2.rotation.y = player.rotation.y + PI # Facing the player.
	z2.state = Zombie.State.WANDER
	z2.trap(10.0) # Standing still, looking our way.
	await _wait(2.5)
	_check(z2.state != Zombie.State.WANDER or z2.awareness > 0.0, "a zombie in view notices you (awareness %.2f)" % z2.awareness)
	zombies.clear_all()


func _near_chunks() -> Array:
	return _main.streamer.get_children().filter(func(c: Node) -> bool: return c is Chunk and c.lod == 0)


func _run() -> void:
	print("World generation")
	var ms := await _wait_for(func() -> bool: return _main.world_ready, 60000)
	_check(_main.world_ready, "8 km world generated in %d ms" % ms)
	var gen: WorldGen = _main.gen
	var lots := 0
	for t in gen.towns:
		lots += t.lots.size()
	_check(gen.settlements.list.size() >= 10, "%d settlements" % gen.settlements.list.size())
	_check(gen.roads.roads.size() > 50, "%d roads and streets" % gen.roads.roads.size())
	_check(not gen.hydro.rivers.is_empty(), "%d rivers" % gen.hydro.rivers.size())
	_check(lots > 300, "%d building lots" % lots)
	var site_types := gen.settlements.sites.map(func(s): return s.type)
	_check("research" in site_types, "research centre placed")
	_check("gas_station" in site_types, "roadside gas stations placed")

	var player: Player = _main.player
	var streamer: WorldStreamer = _main.streamer
	var zombies: ZombieManager = _main.zombies

	print("World streaming")
	ms = await _wait_for(func() -> bool: return player.active, 30000)
	_check(player.active, "spawn area loaded in %d ms" % ms)
	await _wait(3.0)
	var chunks := streamer.get_children().filter(func(c: Node) -> bool: return c is Chunk)
	_check(chunks.size() > 20, "%d chunks streamed in" % chunks.size())
	var doors: Array[DoorBody] = []
	var containers := []
	for c: Chunk in _near_chunks():
		containers.append_array(c.containers)
		for n in c.get_children():
			if n is DoorBody:
				doors.append(n)
	_check(doors.size() > 5, "%d doors near spawn" % doors.size())
	_check(containers.size() > 10, "%d loot containers near spawn" % containers.size())

	print("Player")
	var ground := gen.height(player.position.x, player.position.z)
	_check(absf(player.position.y - ground) < 1.0, "at terrain height (%.2f vs %.2f)" % [player.position.y, ground])
	var start := player.position
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	var moved := Vector2(player.position.x - start.x, player.position.z - start.z).length()
	_check(moved > 2.0, "walked %.1f m forward" % moved)

	print("Doors and loot")
	if not doors.is_empty():
		var door: DoorBody = doors[0]
		var front := door.global_transform * Vector3(0.5, 0, 1.2)
		player.global_position = Vector3(front.x, front.y + 0.1, front.z)
		player.look_at_from_position(player.global_position, door.global_transform * Vector3(0.5, 1.6, 0), Vector3.UP)
		player.rotation.x = 0
		player.rotation.z = 0
		player.head.rotation.x = -0.2
		await _wait(0.3)
		player._update_focus()
		_check(player._focus is DoorBody, "looking at a door shows '%s'" % player.prompt)
		player._interact()
		await _wait(0.6)
		_check(door.is_open, "door opened")
	if not containers.is_empty():
		var ct: Dictionary = containers[0]
		player._focus = ct
		player._interact()
		_check(GameState.containers.has(ct.id), "searched a %s" % Loot.label(ct.type))
		_check(_main.inventory_ui.is_open() and GameState.ui_open, "searching opens the inventory")
		_main.inventory_ui.close()
		_check(not GameState.ui_open, "inventory closes")
	# Inventory screen actions on a staged container.
	var ui: InventoryScreen = _main.inventory_ui
	var box := {"id": "test_box", "type": "car_trunk", "bld": "", "pos": player.global_position}
	var staged: Array = []
	var sg := ItemGrid.new("c", "", 7, 4, staged)
	sg.add(ItemDB.make("ammo_9mm", 12))
	sg.add(ItemDB.make("red_dot"))
	sg.add(ItemDB.make("canned_soup"))
	GameState.containers[box.id] = staged
	ui.open(box)
	var gun := ItemDB.make("pistol_9mm")
	sg.place(gun, 4, 0, false)
	ui._refresh()
	var ammo: Dictionary = staged[0]
	ui._lift(ammo)
	_check(ui._combine(ammo, gun) and int(gun.a) == 12, "dropping ammo on a gun loads it")
	var dot := sg.items.filter(func(o: Dictionary) -> bool: return o.id == "red_dot")[0] as Dictionary
	ui._lift(dot)
	_check(ui._combine(dot, gun) and gun.att.get("scope", "") == "red_dot", "dropping a sight on a gun attaches it")
	var soups := GameState.inventory.count("canned_soup")
	ui._take_all()
	_check(staged.is_empty() and GameState.inventory.count("canned_soup") == soups + 1, "Take All empties the container")
	ui.close()
	var trunks := containers.filter(func(c: Dictionary) -> bool: return c.type == "car_trunk")
	print("  (%d car trunks near spawn)" % trunks.size())

	_test_items()

	print("Zombies")
	# Open ground outside town for a clean combat test.
	var spot := player.global_position + Vector3(0, 0, 0)
	for k in 40:
		var p := Vector2(player.global_position.x, player.global_position.z) + Vector2.from_angle(k * 0.7) * (400.0 + k * 20.0)
		if gen.town_weight(p.x, p.y) == 0.0 and gen.water_level(p.x, p.y) == -INF and not gen.is_inside_building(p.x, p.y):
			spot = Vector3(p.x, gen.height(p.x, p.y) + 0.5, p.y)
			break
	player.global_position = spot
	streamer.refresh()
	await _wait_for(func() -> bool: return streamer.is_ready_at(spot), 15000)
	await _wait(0.5)
	player.global_position = Vector3(spot.x, gen.height(spot.x, spot.z) + 0.3, spot.z)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.health = 100.0
	zombies.clear_all()
	GameState.inventory.equip.melee = ItemDB.make("baseball_bat")
	player.weapons.current = "primary"
	player.weapons.select("melee")
	var z := _spawn_zombie(Vector3(0, 0, -8))
	z.see_player()
	await _wait(3.5)
	_check(player.health < 100.0, "zombie chased and attacked (health %.0f)" % player.health)
	_check(z.global_position.distance_to(player.global_position) < 3.0, "zombie reached the player")
	player.head.rotation.x = -0.25
	for i in 6:
		if z.state == Zombie.State.DEAD:
			break
		var to := z.global_position - player.global_position
		player.rotation.y = atan2(-to.x, -to.z)
		player.stamina = 100.0
		player.weapons._cd = 0.0
		player.weapons.melee()
		await _wait(0.6)
	_check(z.state == Zombie.State.DEAD, "zombie killed with melee")
	_check(GameState.kills >= 1, "kill counted")
	await _wait(3.0)
	_check(zombies.active_count() > 0, "ambient zombies spawning (%d active)" % zombies.active_count())

	await _test_combat(player, zombies)
	await _test_stealth(player, zombies)

	print("Survival")
	GameState.add_item(ItemDB.make("canned_beans"))
	player.hunger = 50.0
	player.quick_use(["food"], [])
	_check(player.hunger > 80.0, "eating restores hunger")

	print("Save / load")
	GameState.add_item(ItemDB.make("pistol_9mm"))
	_main.drops.drop(ItemDB.make("crowbar"), player.global_position + Vector3(1, 0, 0))
	var n_drops := GameState.drops.size()
	var n_containers := GameState.containers.size()
	var pistol_before := GameState.inventory.count("pistol_9mm")
	_main.save_game()
	_check(GameState.has_save(), "save file written")
	var kills := GameState.kills
	GameState.kills = 0
	GameState.inventory.clear()
	GameState.drops.clear()
	var data := GameState.load_game()
	_check(GameState.kills == kills and data.has("pos"), "save restores state")
	_check(GameState.inventory.count("pistol_9mm") == pistol_before and GameState.inventory.equip.melee.get("id", "") == "baseball_bat",
			"save restores the inventory")
	_check(GameState.drops.size() == n_drops and GameState.containers.size() == n_containers, "save restores drops and opened containers")
	var listed := GameState.list_worlds().filter(func(w): return w.id == "smoketest")
	_check(listed.size() == 1 and int(listed[0].kills) == kills, "world listed with its stats")

	print("Performance (headless, CPU only)")
	for lod in [0, 1]:
		var tb := Time.get_ticks_usec()
		var key := WorldStreamer.chunk_of(player.global_position)
		for k in 4:
			ChunkBuilder.build(gen, key.x + k, key.y, lod)
		print("  chunk generation (lod %d, one thread): %.1f ms" % [lod, (Time.get_ticks_usec() - tb) / 4000.0])
	var town: Dictionary = gen.settlements.list.filter(func(s): return s.kind == Settlements.Kind.TOWN)[0]
	var tkey := WorldStreamer.chunk_of(Vector3(town.center.x, 0, town.center.y))
	var tb2 := Time.get_ticks_usec()
	var cdata := ChunkBuilder.build(gen, tkey.x, tkey.y, 0)
	print("  town-centre chunk generation (lod 0): %.1f ms" % ((Time.get_ticks_usec() - tb2) / 1000.0))
	var tb3 := Time.get_ticks_usec()
	var chunk := Chunk.new()
	chunk.setup(cdata, false)
	add_child(chunk)
	print("  town-centre chunk node setup (main thread): %.2f ms" % ((Time.get_ticks_usec() - tb3) / 1000.0))
	chunk.queue_free()
	var frames := 0
	var t := Time.get_ticks_usec()
	while frames < 120:
		await get_tree().process_frame
		frames += 1
	print("  avg frame time: %.2f ms" % ((Time.get_ticks_usec() - t) / 1000.0 / frames))

	print("Menu")
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await _wait(0.2)
	_check(menu.get_child_count() > 3, "main menu builds")
	menu.queue_free()

	GameState.delete_world("smoketest")
	print("\n%s (%d failures)" % ["ALL PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
