extends Node
## Renders gameplay screenshots into user://screenshots/ for quick visual
## checks. Needs a real renderer (not --headless), e.g.:
##   xvfb-run godot res://tests/screenshots.tscn -- --touch

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
