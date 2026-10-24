extends Node3D
## Builds and wires up the game for the current world: generates it on a
## background thread (with a loading screen), then sets up the environment,
## world streaming, player, zombies, UI, day/night cycle and autosave.
## Also runs the death rules (respawn, new character, permadeath; turning
## into a zombie when infected), tracks the explored map and keeps running
## generators loud.
##
## Multiplayer (see Net): the other players' avatars, sharing clothes,
## pings, curing a turned friend back to life, watching friends after a
## permadeath, and the world being lost only when everyone is out.
##
## Survival (stage 6): bases (BaseManager), the crafting menu, the weather
## (picked here on the host, drawn by WeatherFX) and sleeping.

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
var avatars: Avatars
var vehicles: VehicleManager
var vehicle_menu: VehicleMenu
var bases: BaseManager
var craft_menu: CraftMenu
var weather_fx: WeatherFX
var animals: AnimalManager
var traders: TraderManager
var trade_menu: TradeMenu
var pings: Array = [] # {pos, kind, name, t}
var _look_json := ""
var _spec_cam: Camera3D
var _spec_index := 0
var ocean: MeshInstance3D
var world_ready := false
var _saved_player := {}
var _gen_task := -1
var _autosave_t := AUTOSAVE_INTERVAL
var _night_hint_shown := false
var _explore_t := 0.0
var _generator_t := 0.0
var _creator: CanvasLayer


func _ready() -> void:
	Assets.build()
	if GameState.world.is_empty():
		# Launched straight into the game (editor, tests): use a quick-play world.
		GameState.start_world(GameState.create_world("Quick Play", GameState.world_size, GameState.world_seed, 1, 0, "quickplay"))
	if Net.is_client():
		# A guest plays the host's world; the host keeps their save.
		_saved_player = GameState.net_player
	else:
		_saved_player = GameState.load_game()
	Net.attach_game(self)
	Sound.game = self
	Sound.music(false)
	Net.disconnected.connect(_on_disconnected)
	Net.ping_received.connect(func(pg: Dictionary) -> void:
		pg.t = Time.get_ticks_msec()
		pings.append(pg)
		if pg.id != Net.my_id():
			GameState.notify("%s: %s" % [pg.name, {"go": "Over here", "zombie": "Zombie!", "loot": "Loot here",
				"help": "Help!"}.get(pg.kind, "Look")]))
	Net.chat_notice.connect(func(t: String) -> void: GameState.notify(t))
	gen = WorldGen.new(GameState.world_seed, GameState.world_size)
	_setup_environment()
	hud = Hud.new()
	hud.respawn_requested.connect(_respawn)
	hud.new_character_requested.connect(_new_character)
	hud.menu_requested.connect(_quit_to_menu)
	add_child(hud)
	hud.set_loading(true)
	_gen_task = WorkerThreadPool.add_task(_generate, true, "world generation")


func _generate() -> void:
	gen.generate(func(f: float, text: String) -> void:
		hud.call_deferred("set_loading_progress", f, text))
	# The map image, for the in-game map and the memorial (once per world).
	var map_path := GameState.world_file(GameState.world, "map.png")
	if not FileAccess.file_exists(map_path):
		hud.call_deferred("set_loading_progress", 1.0, "Drawing the map")
		MapRenderer.render(gen, 320).save_png(map_path)


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
		# New guests start in a random small town, like any new survivor.
		player.global_position = gen.spawn_point(randi() if Net.is_client() else GameState.world_seed)
	else:
		player.from_dict(_saved_player)
	player.damaged.connect(func() -> void: hud.flash_damage())
	player.died.connect(_on_player_died)
	streamer.player = player
	player.streamer = streamer

	avatars = Avatars.new()
	add_child(avatars)
	zombies = ZombieManager.new()
	zombies.gen = gen
	zombies.player = player
	zombies.streamer = streamer
	zombies.avatars = avatars
	zombies.turned_cured.connect(_on_turned_cured)
	add_child(zombies)
	player.zombies = zombies
	hud.connect_player(player)
	hud.zombies = zombies
	hud.game = self

	drops = DropManager.new()
	drops.player = player
	drops.zombies = zombies
	add_child(drops)
	zombies.drops = drops
	player.drops = drops
	effects = Effects.new()
	effects.player = player
	effects.zombies = zombies
	effects.drops = drops
	effects.gen = gen
	add_child(effects)
	player.weapons.effects = effects
	player.weapons.drops = drops

	vehicles = VehicleManager.new()
	vehicles.gen = gen
	vehicles.streamer = streamer
	vehicles.player = player
	vehicles.zombies = zombies
	vehicles.avatars = avatars
	add_child(vehicles)
	streamer.vehicles = vehicles
	player.vehicles = vehicles
	bases = BaseManager.new()
	bases.gen = gen
	bases.player = player
	bases.avatars = avatars
	bases.zombies = zombies
	add_child(bases)
	player.bases = bases
	zombies.bases = bases
	craft_menu = CraftMenu.new()
	craft_menu.player = player
	craft_menu.game = self
	add_child(craft_menu)
	traders = TraderManager.new()
	traders.gen = gen
	traders.player = player
	traders.zombies = zombies
	add_child(traders)
	zombies.traders = traders
	trade_menu = TradeMenu.new()
	trade_menu.player = player
	add_child(trade_menu)
	player.open_trade.connect(trade_menu.open)
	animals = AnimalManager.new()
	animals.gen = gen
	animals.player = player
	animals.zombies = zombies
	add_child(animals)
	weather_fx = WeatherFX.new()
	weather_fx.camera = player.camera
	add_child(weather_fx)

	vehicle_menu = VehicleMenu.new()
	vehicle_menu.player = player
	vehicle_menu.streamer = streamer
	add_child(vehicle_menu)
	player.vehicle_menu = vehicle_menu

	inventory_ui = InventoryScreen.new()
	inventory_ui.player = player
	inventory_ui.drops = drops
	add_child(inventory_ui)
	player.open_inventory.connect(inventory_ui.open)
	player.open_crafting.connect(func(tab: String) -> void:
		if inventory_ui.is_open():
			inventory_ui.close()
		craft_menu.open(tab))
	inventory_ui.craft_requested.connect(func() -> void:
		inventory_ui.close()
		craft_menu.open(""))
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
	pause_menu.player = player
	pause_menu.save_requested.connect(save_game)
	pause_menu.menu_requested.connect(_quit_to_menu)
	add_child(pause_menu)

	perf = PerformanceMonitor.new()
	add_child(perf)

	GameState.quality_changed.connect(apply_quality)
	GameState.inventory_changed.connect(_check_look)
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
	# Short-sighted survivors see the distance fade into fog much sooner.
	var sight := GameState.character.mod("view")
	env.fog_depth_begin = far * 0.3 * sight
	env.fog_depth_end = far * 0.95 * sight
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
	if Net.is_client():
		Net.client_ready()
		Net.send_look()
		if GameState.net_out:
			# Out of a permadeath world: you can only watch your friends.
			player.health = 0.0
			player.dead = true
			hud.show_death(true, GameState.DeathRule.PERMADEATH, "Out of the game", false, true)


func _process(delta: float) -> void:
	if not world_ready:
		if _gen_task >= 0 and WorkerThreadPool.is_task_completed(_gen_task):
			WorkerThreadPool.wait_for_task_completion(_gen_task)
			_gen_task = -1
			_setup_world()
		return
	_update_day_night()
	var p := player.global_position
	if Net.is_host():
		streamer.extra_centers = avatars.targets().map(func(a: Node3D) -> Vector3: return a.global_position)
	_update_spectator()
	var now := Time.get_ticks_msec()
	pings = pings.filter(func(pg: Dictionary) -> bool: return now - int(pg.t) < (30000 if pg.kind == "help" else 20000))
	ocean.global_position = Vector3(snappedf(p.x, 64.0), -0.05, snappedf(p.z, 64.0))
	if not player.active:
		return
	if Input.is_action_just_pressed("pause") and not player.dead and not inventory_ui.is_open() and not vehicle_menu.is_open() \
			and not craft_menu.is_open() and not trade_menu.is_open() and not player.build.active() and not player.sleeping:
		pause_menu.open()
	if Input.is_action_just_pressed("toggle_fps"):
		hud.toggle_debug()
	_autosave_t -= delta
	if _autosave_t <= 0.0:
		_autosave_t = AUTOSAVE_INTERVAL
		save_game()
	_explore_t -= delta
	if _explore_t <= 0.0:
		_explore_t = 1.0
		GameState.explore(player.global_position)
	# A running generator keeps drawing zombies in.
	_generator_t -= delta
	if _generator_t <= 0.0:
		_generator_t = 8.0
		for site in GameState.ws.power:
			var g: Array = GameState.ws.power[site]
			var gp := Vector3(g[0], g[1], g[2])
			if gp.distance_to(p) < 400.0:
				GameState.make_noise(gp, 60.0)
	# The host (or a single player) decides the weather.
	if Net.authority() and Weather.update():
		Net.weather_changed()
		if player.active:
			GameState.notify({"rain": "It starts to rain", "storm": "A storm rolls in", "fog": "Fog creeps in",
				"snow": "It's snowing", "clear": "The sky clears", "cloudy": "Clouds gather"}.get(Weather.kind(), ""))
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
	weather_fx.update(get_process_delta_time(), player.sheltered)
	sky = sky * weather_fx.sky_tint
	sky = sky.lerp(Color(0.85, 0.88, 1.0), weather_fx.lightning * 0.8)
	var q := GameState.preset()
	var far: float = (q.view_radius + 0.5) * WorldGen.CHUNK_SIZE * GameState.character.mod("view")
	env.fog_depth_begin = far * 0.3 * weather_fx.fog_factor * (0.4 if Weather.kind() == "fog" else 1.0)
	env.fog_depth_end = far * 0.95 * weather_fx.fog_factor
	# Warm tint around sunrise and sunset.
	var dusk := maxf(0.0, 1.0 - absf(dark - 0.5) * 2.0)
	sky = sky.lerp(DUSK_SKY * (1.0 - dark * 0.6), dusk * 0.5)
	env.background_color = sky
	env.fog_light_color = sky
	env.ambient_light_color = Color(0.6, 0.62, 0.65).lerp(Color(0.12, 0.15, 0.25), dark)
	# Cat's eyes: nights look less dark.
	env.ambient_light_energy = lerpf(0.9, 0.35 * GameState.character.mod("night_vision"), dark)
	if dark < 1.0:
		# The sun travels east to west between 06:00 and 18:00.
		var a := clampf((t - 6.0) / 12.0 * PI, 0.15, PI - 0.15)
		sun.basis = Basis.looking_at(Vector3(-cos(a), -sin(a), 0.35).normalized())
		sun.light_energy = 1.25 * (1.0 - dark) * (weather_fx.sky_tint.v * 0.8 + 0.2) + weather_fx.lightning * 2.0
		sun.light_color = Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.6, 0.4), dusk)
	else:
		# Moonlight.
		sun.basis = Basis.looking_at(Vector3(0.4, -0.8, 0.45).normalized())
		sun.light_energy = 0.12 + weather_fx.lightning * 2.0
		sun.light_color = Color(0.6, 0.7, 1.0)


func save_game() -> void:
	if world_ready and player.active and not player.dead and not GameState.world.get("lost", false):
		GameState.save_game(player.to_dict())
	if world_ready and Net.is_client():
		Net.send_record()


func _on_player_died() -> void:
	if inventory_ui.is_open():
		inventory_ui.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var at := player.global_position
	var rule := GameState.death_rule()
	var cause := player.death_cause
	if player.turned:
		# The infected rise again, carrying everything they had. In a
		# multiplayer game friends can subdue and cure them.
		cause = "Turned into a zombie"
		var equip := {}
		for slot in ItemDB.CLOTHING_SLOTS:
			var it: Dictionary = GameState.inventory.equip[slot]
			if not it.is_empty():
				equip[slot] = {"id": it.id, "v": it.get("v", 0), "c": it.get("c", 1.0)}
		GameState.add_turned({"id": "%s_%d" % [GameState.player_id, int(GameState.hours() * 100.0) + randi() % 100],
			"name": GameState.character.name, "owner": GameState.player_id, "p": [at.x, at.y, at.z],
			"items": GameState.inventory.all_items().duplicate(true), "char": GameState.character.to_dict(), "equip": equip})
	else:
		# Everything you carried stays where you fell, for your next life.
		var items := GameState.inventory.all_items()
		for k in items.size():
			drops.drop(items[k], at + Vector3(cos(k * 2.4), 0.3, sin(k * 2.4)) * 0.6)
	GameState.inventory.clear()
	if Net.active():
		# With friends around, a turned survivor can still be cured, and a
		# permadeath only ends the world when everyone is out.
		if rule == GameState.DeathRule.PERMADEATH and not player.turned:
			GameState.net_out = true
			Net.mark_out()
			if Net.is_host():
				check_world_lost()
		hud.show_death(true, rule, cause, player.turned, true)
		return
	if rule == GameState.DeathRule.PERMADEATH:
		GameState.mark_world_lost(cause)
	hud.show_death(true, rule, cause, player.turned)


## "New character" worlds: make someone new, then start again.
func _new_character() -> void:
	hud.show_death(false)
	_creator = CanvasLayer.new()
	_creator.layer = 12
	add_child(_creator)
	var cc := CharacterCreator.new()
	cc.title = "A NEW SURVIVOR"
	_creator.add_child(cc)
	cc.done.connect(func(c: Character) -> void:
		GameState.character = c
		_creator.queue_free()
		_creator = null
		apply_quality()
		_respawn())


func _respawn() -> void:
	if not Net.active():
		zombies.clear_all()
		effects.clear()
	var p := gen.spawn_point(randi())
	player.respawn(Vector3(p.x, gen.height(p.x, p.z) + 1.0, p.z))
	GameState.give_starting_kit()
	GameState.character.stats.days = GameState.day
	hud.show_death(false)
	# The spawn town may be far away; wait for its chunks before resuming.
	player.active = false
	hud.set_loading(true)
	streamer.wait_for_spawn_area()
	streamer.spawn_area_ready.connect(_on_spawn_ready, CONNECT_ONE_SHOT)


func _quit_to_menu() -> void:
	save_game()
	Net.stop()
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


# --- Multiplayer ----------------------------------------------------------------------

## Workbenches and lit fires within reach (for crafting and cooking).
func stations_near(pos: Vector3) -> Array:
	var out := bases.stations_near(pos) if bases else []
	# A burning molotov puddle works as a cooking fire too.
	if effects and not "fire" in out and effects.fire_near(pos, 2.5):
		out.append("fire")
	return out


## Clothes changed: the other players redraw you.
func _check_look() -> void:
	if not Net.active():
		return
	var j := JSON.stringify(Net._my_look())
	if j != _look_json:
		_look_json = j
		Net.send_look()


## Host: someone gave a turned survivor the cure.
func _on_turned_cured(entry: Dictionary) -> void:
	var p: Array = entry.p
	var pos := Vector3(p[0], p[1], p[2])
	if entry.owner == GameState.player_id:
		revive(pos, entry.items)
	elif not Net.revive(str(entry.owner), pos, entry.items):
		# Their player isn't here: leave the gear where the body stood.
		for k in entry.items.size():
			drops.drop(entry.items[k], pos + Vector3(cos(k * 2.4), 0.4, sin(k * 2.4)) * 0.6)
		GameState.notify("%s is cured, but they aren't here to come back" % entry.name)


## Back to life after a friend's cure, with everything you carried.
func revive(pos: Vector3, items: Array) -> void:
	if not player.dead:
		for it in items:
			GameState.drop_item(Inventory._clean(it), pos)
		GameState.notify("A friend cured your old body. Your gear is there.")
		return
	player.respawn(pos)
	GameState.inventory.clear()
	for it in items:
		GameState.inventory.add(Inventory._clean(it))
	GameState.net_out = false
	hud.show_death(false)
	_stop_spectating()
	if not GameState.uses_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameState.notify("You're cured. Your friends brought you back!")


## Permadeath with friends: the world is lost once nobody is left playing.
func check_world_lost() -> void:
	if not Net.is_host() or GameState.death_rule() != GameState.DeathRule.PERMADEATH:
		return
	if not GameState.net_out:
		return
	for id in Net.players:
		if not Net.players[id].out:
			return
	GameState.mark_world_lost("Everyone died")
	Net.world_lost("Everyone died")
	on_world_lost("Everyone died")


## Your turned body was killed: no cure can bring you back now.
func on_body_gone() -> void:
	if not player.dead:
		return
	GameState.notify("Your turned body was put down. There's no cure for you now.")
	var rule := GameState.death_rule()
	if rule == GameState.DeathRule.PERMADEATH:
		GameState.net_out = true
		Net.mark_out()
		if Net.is_host():
			check_world_lost()
	hud.show_death(true, rule, "Your turned body was put down", false, true)


func on_world_lost(cause: String) -> void:
	_stop_spectating()
	hud.show_death(true, GameState.DeathRule.PERMADEATH, cause, false)


## While dead in a multiplayer game, follow a friend's survivor.
func _update_spectator() -> void:
	if not player.dead or not Net.active() or hud.death_full():
		_stop_spectating()
		return
	var alive := avatars.targets()
	if alive.is_empty():
		_stop_spectating()
		return
	if _spec_cam == null:
		_spec_cam = Camera3D.new()
		_spec_cam.far = player.camera.far
		add_child(_spec_cam)
	_spec_index = posmod(_spec_index, alive.size())
	var a: Node3D = alive[_spec_index]
	var behind := a.global_position + a.global_basis.z * 3.2 + Vector3(0, 2.4, 0)
	_spec_cam.global_position = _spec_cam.global_position.lerp(behind, 0.1) if _spec_cam.current else behind
	_spec_cam.look_at(a.global_position + Vector3(0, 1.4, 0))
	_spec_cam.current = true
	hud.spectating = str(a.player_name)


func next_spectated() -> void:
	_spec_index += 1


func _stop_spectating() -> void:
	if _spec_cam and _spec_cam.current:
		_spec_cam.current = false
		player.camera.current = true
	if hud:
		hud.spectating = ""


func _on_disconnected(reason: String) -> void:
	GameState.menu_message = reason
	get_tree().paused = false
	GameState.ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.world = {}
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
