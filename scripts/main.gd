extends Node3D
## Builds and wires up the game for the current world: generates it on a
## background thread (with a loading screen), then sets up the environment,
## world streaming, player, zombies, UI, day/night cycle and autosave.

const AUTOSAVE_INTERVAL := 60.0
const DAY_SKY := Color(0.58, 0.63, 0.66)
const DUSK_SKY := Color(0.55, 0.4, 0.33)
const NIGHT_SKY := Color(0.03, 0.04, 0.06)

var gen: WorldGen
var env: Environment
var sun: DirectionalLight3D
var streamer: WorldStreamer
var player: Player
var zombies: ZombieManager
var hud: Hud
var touch: TouchControls
var pause_menu: PauseMenu
var inventory_ui: InventoryScreen
var effects: Effects
var drops: DropManager
var perf: PerformanceMonitor
var ocean: MeshInstance3D
var world_ready := false
var _saved_player := {}
var _gen_task := -1
var _autosave_t := AUTOSAVE_INTERVAL
var _night_hint_shown := false


func _ready() -> void:
	Assets.build()
	if GameState.world.is_empty():
		# Launched straight into the game (editor, tests): use a quick-play world.
		GameState.start_world(GameState.create_world("Quick Play", GameState.world_size, GameState.world_seed, 1, 0, "quickplay"))
	_saved_player = GameState.load_game()
	gen = WorldGen.new(GameState.world_seed, GameState.world_size)
	_setup_environment()
	hud = Hud.new()
	hud.respawn_requested.connect(_respawn)
	hud.menu_requested.connect(_quit_to_menu)
	add_child(hud)
	hud.set_loading(true)
	_gen_task = WorkerThreadPool.add_task(_generate, true, "world generation")


func _generate() -> void:
	gen.generate(func(f: float, text: String) -> void:
		hud.call_deferred("set_loading_progress", f, text))


func _exit_tree() -> void:
	if _gen_task >= 0 and not world_ready:
		WorkerThreadPool.wait_for_task_completion(_gen_task)


func _setup_world() -> void:
	streamer = WorldStreamer.new()
	streamer.gen = gen
	add_child(streamer)

	player = Player.new()
	player.gen = gen
	add_child(player)
	if _saved_player.is_empty():
		player.global_position = gen.spawn_point(GameState.world_seed)
	else:
		player.from_dict(_saved_player)
	player.damaged.connect(func() -> void: hud.flash_damage())
	player.died.connect(_on_player_died)
	streamer.player = player
	player.streamer = streamer

	zombies = ZombieManager.new()
	zombies.gen = gen
	zombies.player = player
	add_child(zombies)
	player.zombies = zombies
	hud.connect_player(player)
	hud.zombies = zombies

	drops = DropManager.new()
	drops.player = player
	drops.zombies = zombies
	add_child(drops)
	player.drops = drops
	effects = Effects.new()
	effects.player = player
	effects.zombies = zombies
	effects.drops = drops
	effects.gen = gen
	add_child(effects)
	player.weapons.effects = effects
	player.weapons.drops = drops

	inventory_ui = InventoryScreen.new()
	inventory_ui.player = player
	inventory_ui.drops = drops
	add_child(inventory_ui)
	player.open_inventory.connect(inventory_ui.open)
	ItemIcons.build(self)

	touch = TouchControls.new()
	touch.visible = GameState.uses_touch()
	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 2
	add_child(touch_layer)
	touch_layer.add_child(touch)
	touch.player = player
	if touch.visible:
		player.touch = touch

	pause_menu = PauseMenu.new()
	pause_menu.save_requested.connect(save_game)
	pause_menu.menu_requested.connect(_quit_to_menu)
	add_child(pause_menu)

	perf = PerformanceMonitor.new()
	add_child(perf)

	GameState.quality_changed.connect(apply_quality)
	apply_quality()
	streamer.spawn_area_ready.connect(_on_spawn_ready, CONNECT_ONE_SHOT)
	world_ready = true


func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = DAY_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.65)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_light_color = DAY_SKY
	env.fog_depth_curve = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_energy = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)

	# One big water plane at sea level follows the player; land hides it.
	ocean = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5000, 5000)
	ocean.mesh = plane
	ocean.material_override = Assets.water_material
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)


func apply_quality() -> void:
	var q := GameState.preset()
	var far: float = (q.view_radius + 0.5) * WorldGen.CHUNK_SIZE
	streamer.view_radius = q.view_radius
	streamer.shadows = q.shadows
	streamer.rebuild_all()
	player.camera.far = far
	env.fog_depth_begin = far * 0.3
	env.fog_depth_end = far * 0.95
	sun.shadow_enabled = q.shadows
	zombies.max_zombies = int(q.max_zombies * GameState.difficulty().zombies)
	zombies.set_shadows(q.shadows)
	Assets.set_per_vertex_lighting(q.per_vertex)
	perf.configure(q.fps, q.min_scale)


func _on_spawn_ready() -> void:
	# Snap onto the ground now that collision exists under the player.
	var p := player.global_position
	player.global_position = Vector3(p.x, maxf(p.y, gen.height(p.x, p.z) + 0.5), p.z)
	player.active = true
	hud.set_loading(false)
	if not GameState.uses_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameState.notify("Find food, water and shelter. Survive.")
	save_game()


func _process(delta: float) -> void:
	if not world_ready:
		if _gen_task >= 0 and WorkerThreadPool.is_task_completed(_gen_task):
			WorkerThreadPool.wait_for_task_completion(_gen_task)
			_gen_task = -1
			_setup_world()
		return
	_update_day_night()
	var p := player.global_position
	ocean.global_position = Vector3(snappedf(p.x, 64.0), -0.05, snappedf(p.z, 64.0))
	if not player.active:
		return
	if Input.is_action_just_pressed("pause") and not player.dead and not inventory_ui.is_open():
		pause_menu.open()
	if Input.is_action_just_pressed("toggle_fps"):
		hud.toggle_debug()
	_autosave_t -= delta
	if _autosave_t <= 0.0:
		_autosave_t = AUTOSAVE_INTERVAL
		save_game()
	if GameState.is_night() and not _night_hint_shown:
		_night_hint_shown = true
		GameState.notify("Night falls. Zombies are faster - use your flashlight.")


func _unhandled_input(event: InputEvent) -> void:
	# Desktop: click to recapture the mouse after alt-tabbing.
	if world_ready and event is InputEventMouseButton and event.pressed and not GameState.uses_touch() \
			and player.active and not player.dead and not GameState.ui_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_day_night() -> void:
	var t := GameState.time_of_day
	var dark := GameState.darkness()
	var sky := DAY_SKY.lerp(NIGHT_SKY, dark)
	# Warm tint around sunrise and sunset.
	var dusk := maxf(0.0, 1.0 - absf(dark - 0.5) * 2.0)
	sky = sky.lerp(DUSK_SKY * (1.0 - dark * 0.6), dusk * 0.5)
	env.background_color = sky
	env.fog_light_color = sky
	env.ambient_light_color = Color(0.6, 0.62, 0.65).lerp(Color(0.12, 0.15, 0.25), dark)
	env.ambient_light_energy = lerpf(0.9, 0.35, dark)
	if dark < 1.0:
		# The sun travels east to west between 06:00 and 18:00.
		var a := clampf((t - 6.0) / 12.0 * PI, 0.15, PI - 0.15)
		sun.basis = Basis.looking_at(Vector3(-cos(a), -sin(a), 0.35).normalized())
		sun.light_energy = 1.25 * (1.0 - dark)
		sun.light_color = Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.6, 0.4), dusk)
	else:
		# Moonlight.
		sun.basis = Basis.looking_at(Vector3(0.4, -0.8, 0.45).normalized())
		sun.light_energy = 0.12
		sun.light_color = Color(0.6, 0.7, 1.0)


func save_game() -> void:
	if world_ready and player.active and not player.dead and not GameState.world.get("lost", false):
		GameState.save_game(player.to_dict())


func _on_player_died() -> void:
	if inventory_ui.is_open():
		inventory_ui.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Everything you carried stays where you fell, for your next life.
	var at := player.global_position
	var items := GameState.inventory.all_items()
	for k in items.size():
		drops.drop(items[k], at + Vector3(cos(k * 2.4), 0.3, sin(k * 2.4)) * 0.6)
	GameState.inventory.clear()
	var permadeath := GameState.death_rule() == GameState.DeathRule.PERMADEATH
	if permadeath:
		# Stage 3 adds the infection cure, the only way back.
		GameState.mark_world_lost("Killed by zombies")
	hud.show_death(true, permadeath)


func _respawn() -> void:
	zombies.clear_all()
	effects.clear()
	var p := gen.spawn_point(randi())
	player.respawn(Vector3(p.x, gen.height(p.x, p.z) + 1.0, p.z))
	GameState.give_starting_kit()
	hud.show_death(false)
	# The spawn town may be far away; wait for its chunks before resuming.
	player.active = false
	hud.set_loading(true)
	streamer.wait_for_spawn_area()
	streamer.spawn_area_ready.connect(_on_spawn_ready, CONNECT_ONE_SHOT)


func _quit_to_menu() -> void:
	save_game()
	get_tree().paused = false
	GameState.ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.world = {}
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _notification(what: int) -> void:
	# Mobile OSes can kill a backgrounded app at any time, so save on pause.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()
