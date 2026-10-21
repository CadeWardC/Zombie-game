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
		_check(GameState.looted.has(ct.id), "searched a %s" % Loot.label(ct.type))

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
	var zpos := player.global_position + Vector3(0, 0, -8)
	zpos.y = gen.height(zpos.x, zpos.z)
	zombies._spawn(zpos)
	var z: Zombie = zombies._active[0]
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
		player._attack_cd = 0.0
		player._attack()
		await _wait(0.6)
	_check(z.state == Zombie.State.DEAD, "zombie killed with melee")
	_check(GameState.kills >= 1, "kill counted")
	await _wait(3.0)
	_check(zombies.active_count() > 0, "ambient zombies spawning (%d active)" % zombies.active_count())

	print("Survival")
	GameState.add_item("food")
	player.hunger = 50.0
	player.use_item("food")
	_check(player.hunger > 80.0, "eating restores hunger")

	print("Save / load")
	_main.save_game()
	_check(GameState.has_save(), "save file written")
	var kills := GameState.kills
	GameState.kills = 0
	var data := GameState.load_game()
	_check(GameState.kills == kills and data.has("pos"), "save restores state")
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
