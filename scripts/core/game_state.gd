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
const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.cfg"
const SAVE_VERSION := 1
const ITEM_NAMES := {"food": "Canned Food", "water": "Water Bottle", "bandage": "Bandage"}

var quality: int = Quality.MEDIUM
var world_seed := 20261021
var time_of_day := 8.0
var day := 1
var kills := 0
var inventory := {"food": 1, "water": 1, "bandage": 0}
var looted := {}
var force_touch_ui := false


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


# --- Save / load -----------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(player_data: Dictionary) -> void:
	var data := {
		"version": SAVE_VERSION,
		"seed": world_seed,
		"time": time_of_day,
		"day": day,
		"kills": kills,
		"inventory": inventory,
		"looted": looted.keys(),
		"player": player_data,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(data))


## Loads world state and returns the saved player data (empty if no save).
func load_game() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != SAVE_VERSION:
		return {}
	var data: Dictionary = parsed
	world_seed = int(data.get("seed", world_seed))
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


func new_world() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	world_seed = randi()
	time_of_day = 8.0
	day = 1
	kills = 0
	inventory = {"food": 1, "water": 1, "bandage": 0}
	looted.clear()


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
