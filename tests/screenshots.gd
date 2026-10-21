extends Node
## Renders a few gameplay screenshots into user://screenshots/ for quick
## visual checks. Needs a real renderer (not --headless), e.g.:
##   xvfb-run godot res://tests/screenshots.tscn -- --touch

var _main: Node3D


func _ready() -> void:
	GameState.new_world()
	GameState.world_seed = 12345
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var path := "user://screenshots/%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("saved %s  (draw calls: %d, objects: %d)" % [ProjectSettings.globalize_path(path),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])


func _go(pos: Vector3, yaw_deg: float, pitch_deg := -5.0) -> void:
	var player: Player = _main.player
	var gen: WorldGen = _main.gen
	pos.y = gen.height(pos.x, pos.z) + 0.2
	player.global_position = pos
	player.rotation.y = deg_to_rad(yaw_deg)
	player.head.rotation.x = deg_to_rad(pitch_deg)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		if _main.streamer._jobs.is_empty() and _main.streamer._done.is_empty() and Time.get_ticks_msec() - t0 > 1500:
			break


func _run() -> void:
	var player: Player = _main.player
	while not player.active:
		await get_tree().process_frame
	GameState.time_of_day = 10.0
	var spawn: Vector3 = _main.gen.spawn_point()
	await _go(spawn + Vector3(1.5, 0, 0), 0.0)
	await _shot("1_town_day")
	await _go(spawn + Vector3(0, 0, 300), 180.0, 2.0)
	await _shot("2_wilderness")
	# Zombies approaching at dusk.
	GameState.time_of_day = 19.6
	await _go(spawn + Vector3(0, 0, -20), 0.0)
	_main.zombies.clear_all()
	var fwd := -player.global_basis.z
	for i in 5:
		var p: Vector3 = player.global_position + fwd * (6.0 + i * 2.5) + player.global_basis.x * (i - 2) * 1.6
		p.y = _main.gen.height(p.x, p.z)
		_main.zombies._spawn(p)
		_main.zombies._active[-1].rotation.y = player.rotation.y + PI
	await get_tree().create_timer(0.3).timeout
	await _shot("3_dusk_zombies")
	GameState.time_of_day = 23.0
	player.flashlight.visible = true
	await get_tree().create_timer(0.3).timeout
	await _shot("4_night_flashlight")
	_main.pause_menu.open()
	await _shot("5_pause_menu")
	get_tree().paused = false
	get_tree().quit()
