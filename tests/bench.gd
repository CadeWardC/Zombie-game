extends Node
## Frame-time benchmark: a busy scene (a town, zombies, a base, animals,
## rain) with the frame cap off. Prints frame, script and physics times.
##   godot --headless res://tests/bench.tscn [-- --low]

var _main: Node3D


func _ready() -> void:
	if "--low" in OS.get_cmdline_user_args():
		GameState.quality = GameState.Quality.LOW
	GameState.delete_world("bench")
	GameState.start_world(GameState.create_world("Bench", 8192.0, 12345, 1, 0, "bench"))
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_run.call_deferred()


func _frames(n: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var phys := 0.0
	for k in n:
		await get_tree().process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return {"frame": (Time.get_ticks_usec() - t0) / 1000.0 / n, "process": proc * 1000.0 / n, "physics": phys * 1000.0 / n}


func _report(label: String, r: Dictionary) -> void:
	print("  %-28s frame %.2f ms  process %.2f ms  physics %.2f ms" % [label, r.frame, r.process, r.physics])


func _run() -> void:
	while not _main.world_ready or not _main.player.active:
		await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout
	Engine.max_fps = 0
	var player: Player = _main.player
	_report("town, ambient zombies", await _frames(300))
	var p := player.global_position
	for k in 20:
		_main.zombies._spawn(Vector3(p.x + cos(k) * 12.0, _main.gen.height(p.x + cos(k) * 12.0, p.z + sin(k) * 12.0), p.z + sin(k) * 12.0))
	for z in _main.zombies._active:
		z.see_player()
	_report("+20 zombies chasing", await _frames(300))
	_main.zombies.clear_all()
	for k in 12:
		_main.bases.add(["wall", "crate", "campfire", "workbench", "farm_plot", "rain_collector"][k % 6], p + Vector3(k * 2.5 - 15.0, 0, 8.0), 0.0)
	for k in 6:
		var a := Animal.new()
		_main.animals.add_child(a)
		a.setup(["deer", "rabbit", "turkey"][k % 3], p + Vector3(k * 3.0, 0, -15.0), _main.gen)
		_main.animals.animals.append(a)
	GameState.weather = {"k": "storm", "i": 1.0, "until": GameState.hours() + 50.0}
	_report("+base, animals, storm", await _frames(300))
	GameState.delete_world("bench")
	get_tree().quit()
