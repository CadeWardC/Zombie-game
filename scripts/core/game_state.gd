extends Node
## Global game state (autoload "GameState"): settings, inventory, world clock,
## save/load and input bindings.

signal noise_made(position: Vector3, radius: float)
signal inventory_changed
signal message(text: String)
signal quality_changed

enum Quality { LOW, MEDIUM, HIGH }

const QUALITY_PRESETS := {
	Quality.LOW: {
		"name": "Low", "view_radius": 3, "shadows": false, "max_zombies": 16,
		"fps": 30, "per_vertex": true, "min_scale": 0.5,
	},
	Quality.MEDIUM: {
		"name": "Medium", "view_radius": 5, "shadows": false, "max_zombies": 28,
		"fps": 60, "per_vertex": false, "min_scale": 0.6,
	},
	Quality.HIGH: {
		"name": "High", "view_radius": 7, "shadows": true, "max_zombies": 45,
		"fps": 60, "per_vertex": false, "min_scale": 0.75,
	},
}

const DAY_LENGTH := 1200.0 # Real seconds per in-game day.
const WORLDS_DIR := "user://worlds"
const SETTINGS_PATH := "user://settings.cfg"
const SAVE_VERSION := 1
const ITEM_NAMES := {"food": "Canned Food", "water": "Water Bottle", "bandage": "Bandage"}
const SIZE_NAMES := {8192.0: "8 x 8 km", 16384.0: "16 x 16 km", 32768.0: "32 x 32 km"}

enum DeathRule { RESPAWN, NEW_CHARACTER, PERMADEATH }
const DEATH_RULE_NAMES := ["Respawn", "New character", "Permadeath"]
const DIFFICULTIES := [
	{"name": "Casual", "zombies": 0.7, "loot": 1.6, "infection": 0.05},
	{"name": "Hardcore but fair", "zombies": 1.0, "loot": 1.0, "infection": 0.15},
	{"name": "Brutal", "zombies": 1.5, "loot": 0.6, "infection": 0.3},
]

var quality: int = Quality.MEDIUM
var world_seed := 20261021
var world_size := 8192.0
var time_of_day := 8.0
var day := 1
var kills := 0
var inventory := {"food": 1, "water": 1, "bandage": 0}
var looted := {}
var force_touch_ui := false
var world := {} # Current world's settings and summary (see create_world).


func _ready() -> void:
	quality = Quality.MEDIUM if OS.has_feature("mobile") else Quality.HIGH
	_load_settings()
	_parse_args()
	_setup_input()


func _process(delta: float) -> void:
	time_of_day += delta * 24.0 / DAY_LENGTH
	if time_of_day >= 24.0:
		time_of_day -= 24.0
		day += 1


func is_night() -> bool:
	return time_of_day < 5.5 or time_of_day > 20.5


## 0 at full daylight, 1 at full night, smooth through dawn and dusk.
func darkness() -> float:
	var t := time_of_day
	if t >= 7.0 and t <= 19.0:
		return 0.0
	if t > 19.0 and t < 21.0:
		return smoothstep(19.0, 21.0, t)
	if t > 5.0 and t < 7.0:
		return 1.0 - smoothstep(5.0, 7.0, t)
	return 1.0


func uses_touch() -> bool:
	return force_touch_ui or DisplayServer.is_touchscreen_available()


func preset() -> Dictionary:
	return QUALITY_PRESETS[quality]


func set_quality(q: int) -> void:
	quality = clampi(q, Quality.LOW, Quality.HIGH)
	_save_settings()
	quality_changed.emit()


func make_noise(pos: Vector3, radius: float) -> void:
	noise_made.emit(pos, radius)


func notify(text: String) -> void:
	message.emit(text)


# --- Inventory -------------------------------------------------------------

func add_item(type: String, count := 1) -> void:
	inventory[type] = int(inventory.get(type, 0)) + count
	inventory_changed.emit()
	notify("Picked up %s" % ITEM_NAMES.get(type, type))


func take_item(type: String) -> bool:
	var have := int(inventory.get(type, 0))
	if have <= 0:
		return false
	inventory[type] = have - 1
	inventory_changed.emit()
	return true


func item_count(type: String) -> int:
	return int(inventory.get(type, 0))


# --- Worlds and saves ----------------------------------------------------------
# Each world lives in user://worlds/<id>/: world.json holds its settings and
# summary (for the menu), save.json the game state.

func difficulty() -> Dictionary:
	return DIFFICULTIES[int(world.get("difficulty", 1))]


func death_rule() -> int:
	return int(world.get("death_rule", DeathRule.RESPAWN))


func list_worlds() -> Array:
	var out := []
	var dir := DirAccess.open(WORLDS_DIR)
	if dir == null:
		return out
	for id in dir.get_directories():
		var meta := _read_json(WORLDS_DIR + "/" + id + "/world.json")
		if not meta.is_empty():
			out.append(meta)
	out.sort_custom(func(a, b): return float(a.get("last_played", 0)) > float(b.get("last_played", 0)))
	return out


func create_world(world_name: String, size: float, seed_value: int, diff: int, rule: int, id := "") -> Dictionary:
	if id == "":
		id = "%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
	else:
		var existing := _read_json(WORLDS_DIR + "/" + id + "/world.json")
		if not existing.is_empty() and int(existing.seed) == seed_value and float(existing.size) == size:
			return existing
		# Same id, different world: the old save no longer applies.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WORLDS_DIR + "/" + id + "/save.json"))
	var meta := {
		"id": id, "name": world_name, "seed": seed_value, "size": size, "difficulty": diff,
		"death_rule": rule, "created": Time.get_unix_time_from_system(),
		"last_played": Time.get_unix_time_from_system(), "day": 1, "kills": 0, "lost": false,
	}
	DirAccess.make_dir_recursive_absolute(WORLDS_DIR + "/" + id)
	_write_json(WORLDS_DIR + "/" + id + "/world.json", meta)
	return meta


func delete_world(id: String) -> void:
	var path := ProjectSettings.globalize_path(WORLDS_DIR + "/" + id)
	for f in ["save.json", "world.json"]:
		DirAccess.remove_absolute(path + "/" + f)
	DirAccess.remove_absolute(path)


## Makes `meta` the current world and resets the runtime state for it.
func start_world(meta: Dictionary) -> void:
	world = meta
	world_seed = int(meta.seed)
	world_size = float(meta.size)
	time_of_day = 8.0
	day = 1
	kills = 0
	inventory = {"food": 1, "water": 1, "bandage": 0}
	looted.clear()


func has_save() -> bool:
	return not world.is_empty() and FileAccess.file_exists(_world_path("save.json"))


func _world_path(file: String) -> String:
	return WORLDS_DIR + "/" + str(world.id) + "/" + file


func save_game(player_data: Dictionary) -> void:
	if world.is_empty():
		return
	var data := {
		"version": SAVE_VERSION,
		"time": time_of_day,
		"day": day,
		"kills": kills,
		"inventory": inventory,
		"looted": looted.keys(),
		"player": player_data,
	}
	_write_json(_world_path("save.json"), data)
	world.last_played = Time.get_unix_time_from_system()
	world.day = day
	world.kills = kills
	_write_json(_world_path("world.json"), world)


## Loads the current world's save and returns the saved player data
## (empty if this world has never been played).
func load_game() -> Dictionary:
	if not has_save():
		return {}
	var data := _read_json(_world_path("save.json"))
	if data.is_empty() or int(data.get("version", 0)) != SAVE_VERSION:
		return {}
	time_of_day = float(data.get("time", 8.0))
	day = int(data.get("day", 1))
	kills = int(data.get("kills", 0))
	var inv: Dictionary = data.get("inventory", {})
	for k in inv:
		inventory[k] = int(inv[k])
	looted.clear()
	for id in data.get("looted", []):
		looted[str(id)] = true
	return data.get("player", {})


## Marks a permadeath world as lost; it stays in the list as a memorial.
func mark_world_lost(cause: String) -> void:
	if world.is_empty():
		return
	world.lost = true
	world.cause = cause
	world.day = day
	world.kills = kills
	_write_json(_world_path("world.json"), world)


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write %s: %s" % [path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data))


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		quality = clampi(int(cfg.get_value("graphics", "quality", quality)), Quality.LOW, Quality.HIGH)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.save(SETTINGS_PATH)


## Debug flags, passed after "--" on the command line:
##   --touch        show touch controls on desktop
##   --seed=N       use a specific world seed (ignored when a save exists)
##   --quality=0..2 override the quality preset
func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--touch":
			force_touch_ui = true
		elif arg.begins_with("--seed="):
			world_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--quality="):
			quality = clampi(int(arg.get_slice("=", 1)), Quality.LOW, Quality.HIGH)


# --- Input -----------------------------------------------------------------

func _setup_input() -> void:
	_action("move_forward", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action("move_back", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action("move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("look_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_action("look_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_action("look_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_action("look_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_action("jump", [_key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_action("sprint", [_key(KEY_SHIFT), _button(JOY_BUTTON_LEFT_STICK)])
	var attack_events: Array = [_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), _button(JOY_BUTTON_X)]
	# On phones every touch is also emulated as a mouse click, so only bind the
	# mouse button on desktop.
	if not OS.has_feature("mobile"):
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		attack_events.append(mb)
	_action("attack", attack_events)
	_action("use_food", [_key(KEY_1), _button(JOY_BUTTON_DPAD_LEFT)])
	_action("use_water", [_key(KEY_2), _button(JOY_BUTTON_DPAD_UP)])
	_action("use_bandage", [_key(KEY_3), _button(JOY_BUTTON_DPAD_RIGHT)])
	_action("flashlight", [_key(KEY_F), _button(JOY_BUTTON_Y)])
	_action("interact", [_key(KEY_E), _button(JOY_BUTTON_B)])
	_action("pause", [_key(KEY_ESCAPE), _key(KEY_P), _button(JOY_BUTTON_START)])
	_action("toggle_fps", [_key(KEY_F3)])


func _action(action_name: String, events: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, 0.2)
	for e in events:
		InputMap.action_add_event(action_name, e)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _button(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
