extends Node
## Automated smoke test. Runs the real game and checks the core loop works.
## Run headless:  godot --headless res://tests/smoke_test.tscn
## Exits with code 0 on success, 1 on failure.

var _main: Node3D
var _failures := 0


func _ready() -> void:
	GameState.new_world()
	GameState.world_seed = 12345
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	var player: Player = _main.player
	var streamer: WorldStreamer = _main.streamer
	var zombies: ZombieManager = _main.zombies
	var gen: WorldGen = _main.gen

	print("World streaming")
	var t0 := Time.get_ticks_msec()
	while not player.active and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	_check(player.active, "spawn area loaded in %d ms" % (Time.get_ticks_msec() - t0))
	await _wait(3.0)
	var chunks := streamer.get_children().filter(func(c: Node) -> bool: return c is Chunk)
	_check(chunks.size() > 20, "%d chunks streamed in" % chunks.size())
	var trees := 0
	var houses := 0
	var pickups: Array[Pickup] = []
	for c: Chunk in chunks:
		for n in c.get_children():
			if n is MultiMeshInstance3D and n.multimesh.mesh in Assets.house_meshes:
				houses += n.multimesh.instance_count
			elif n is MultiMeshInstance3D:
				trees += n.multimesh.instance_count
			elif n is Pickup:
				pickups.append(n)
	_check(trees > 100, "%d trees/rocks/cars instanced" % trees)
	_check(houses > 5, "%d houses visible" % houses)
	_check(pickups.size() > 0, "%d loot items nearby" % pickups.size())

	print("Player")
	var ground := gen.height(player.position.x, player.position.z)
	_check(player.is_on_floor(), "standing on the ground")
	_check(absf(player.position.y - ground) < 1.0, "at terrain height (%.2f vs %.2f)" % [player.position.y, ground])
	var start := player.position
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	var moved := Vector2(player.position.x - start.x, player.position.z - start.z).length()
	_check(moved > 3.0, "walked %.1f m forward" % moved)

	print("Loot")
	var food_before := GameState.item_count("food") + GameState.item_count("water") + GameState.item_count("bandage")
	var item: Pickup = pickups[0]
	var item_type := item.item_type
	var loot_id := item.loot_id
	player.global_position = item.global_position + Vector3(0, 0.2, 0)
	await _wait(0.5)
	var food_after := GameState.item_count("food") + GameState.item_count("water") + GameState.item_count("bandage")
	_check(food_after == food_before + 1, "picked up %s" % item_type)
	_check(GameState.looted.has(loot_id), "loot remembered as taken")

	print("Zombies")
	# Move to open ground outside town for a clean combat test.
	var spot := player.global_position + Vector3(0, 0, 400)
	spot.y = gen.height(spot.x, spot.z) + 0.5
	player.global_position = spot
	streamer.refresh()
	t0 = Time.get_ticks_msec()
	while not streamer.is_ready_at(spot) and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
	await _wait(0.5)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.health = 100.0
	zombies.clear_all()
	var zpos := player.global_position + Vector3(0, 0, -8)
	zpos.y = gen.height(zpos.x, zpos.z)
	zombies._spawn(zpos)
	var z: Zombie = zombies._active[0]
	z.see_player()
	await _wait(3.0)
	_check(player.health < 100.0, "zombie chased and attacked (health %.0f)" % player.health)
	_check(z.global_position.distance_to(player.global_position) < 3.0, "zombie reached the player")

	# Face the zombie and hit it, re-aiming each swing like a player would.
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
	var hunger := player.hunger
	GameState.add_item("food")
	player.hunger = 50.0
	player.use_item("food")
	_check(player.hunger > 80.0, "eating restores hunger")
	_check(hunger <= 100.0, "hunger tracked")

	print("Save / load")
	_main.save_game()
	_check(GameState.has_save(), "save file written")
	var kills := GameState.kills
	GameState.kills = 0
	var data := GameState.load_game()
	_check(GameState.kills == kills and data.has("pos"), "save restores state")

	print("Performance (headless, CPU only)")
	for lod in [0, 1]:
		var tb := Time.get_ticks_usec()
		for k in 5:
			ChunkBuilder.build(gen, 128 + k, 130, lod)
		print("  chunk generation (lod %d, one thread): %.1f ms" % [lod, (Time.get_ticks_usec() - tb) / 5000.0])
	var spawn_key := WorldStreamer.chunk_of(gen.spawn_point())
	for lod in [0, 1]:
		var cdata := ChunkBuilder.build(gen, spawn_key.x + 1, spawn_key.y, lod)
		var tb := Time.get_ticks_usec()
		var chunk := Chunk.new()
		chunk.setup(cdata, false)
		add_child(chunk)
		print("  chunk node setup on main thread (lod %d, town): %.2f ms" % [lod, (Time.get_ticks_usec() - tb) / 1000.0])
		chunk.queue_free()
	var frames := 0
	var t := Time.get_ticks_usec()
	while frames < 120:
		await get_tree().process_frame
		frames += 1
	var ms := (Time.get_ticks_usec() - t) / 1000.0 / frames
	print("  avg frame time: %.2f ms" % ms)

	GameState.new_world()
	print("\n%s (%d failures)" % ["ALL PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
