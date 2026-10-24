extends Node
## Global game state (autoload "GameState"): settings, the character and
## inventory, world clock, containers and dropped items, changes to the world
## (doors, windows, power, turned players), the explored map, save/load,
## input bindings and which input device is in use (for button prompts).

signal noise_made(position: Vector3, radius: float)
signal inventory_changed
signal message(text: String)
signal quality_changed
signal device_changed
signal drops_changed
signal containers_changed(id: String)
signal settings_changed

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
const SAVE_VERSION := 3
const STARTING_KIT := [["kitchen_knife", 1], ["canned_beans", 1], ["water_bottle", 1], ["bandage", 1]]
const EXPLORE_CELL := 64.0 # Metres per explored-map cell.
const SIZE_NAMES := {8192.0: "8 x 8 km", 16384.0: "16 x 16 km", 32768.0: "32 x 32 km"}

enum DeathRule { RESPAWN, NEW_CHARACTER, PERMADEATH }
const DEATH_RULE_NAMES := ["Respawn", "New character", "Permadeath"]
const ZOMBIE_SPEEDS := ["Shamblers", "Mixed", "Fast"]
const INFECTION_CHANCES := [0.0, 0.05, 0.15, 0.3, 0.5, 1.0]
const DIFFICULTIES := [
	{"name": "Casual", "zombies": 0.7, "loot": 1.6, "infection": 0.05},
	{"name": "Hardcore but fair", "zombies": 1.0, "loot": 1.0, "infection": 0.15},
	{"name": "Brutal", "zombies": 1.5, "loot": 0.6, "infection": 0.3},
]

var quality: int = Quality.MEDIUM
## Player options (Settings menu), saved in the settings file:
##   vol_*: volumes 0..1; sens: look sensitivity multiplier; invert_y;
##   fov: field of view; aim_assist: 0 off .. 1 normal .. 2 strong (gamepads);
##   hud: "bars" (always on) or "minimal" (only when something's wrong);
##   hints: first-time tips on/off; binds: remapped controls
##   {action: [keycode or -1, joypad button or -1]}.
const DEFAULT_SETTINGS := {"vol_master": 0.8, "vol_sfx": 0.9, "vol_ambience": 0.7, "vol_music": 0.5, "sens": 1.0,
	"invert_y": false, "fov": 75.0, "aim_assist": 1.0, "hud": "bars", "hints": true, "binds": {}}
var settings := DEFAULT_SETTINGS.duplicate(true)
## Tips already shown (so each appears once per device).
var hints_seen := {}
var world_seed := 20261021
var world_size := 8192.0
var time_of_day := 8.0
var day := 1
var kills := 0
var inventory := Inventory.new()
var character := Character.new()
## Set by the character creator before a world starts (or after a death in
## a "new character" world); used instead of the saved character.
var pending_character: Character
## Changes to the generated world, saved with it:
##   doors: id -> {o: open, l: locked, hp: health (0 = broken)}
##   windows: id -> 1 (smashed)
##   power: site -> [x, y, z] of its running generator
##   spawns: interior spawn id -> in-game hour its zombie was killed
##   turned: players who died infected and rose as zombies:
##           [{id, name, p: [x, y, z], items, look, owner}]
##   vehicles: id -> vehicle record (see VehicleDB); pumps: id -> litres left
##   structures: id -> built structure record (see BaseManager)
##   boards: window id -> hp of the boards nailed over it
##   chopped: tree id -> 1 (cut down); forage: bush id -> hour picked
##   fridges: container id -> 1 (fridges keep food fresh while there's power)
##   grid: {until: in-game hour the restarted power plant runs until}
##   dogs: id -> {id, owner (player id or "" for a stray), hp, p, stay}
##   traders: camp id -> {stock: [items], restock: hour}
##   hordes: id -> roaming horde {id, p, goal, size}; cleared: map square ->
##           {n: recent kills, h: hour} (see Hordes)
const WS_KEYS := ["doors", "windows", "power", "spawns", "vehicles", "pumps", "structures", "boards", "chopped", "forage",
	"fridges", "grid", "dogs", "traders", "hordes", "cleared"]
var ws := {}
## Weather (see Weather): {k: kind, i: intensity, until: hour}.
var weather := {"k": "clear", "i": 0.5, "until": 0.0}
## Which parts of the map have been seen (one byte per EXPLORE_CELL square).
var explored: Image
## Opened containers: id -> Array of items (each with grid x, y, r).
var containers := {}
## Items on the ground: [{p: [x, y, z], it: item, armed: bool (traps)}].
var drops: Array = []
var ui_open := false # Inventory (or another full-screen menu) is open.
## Time speed-up while sleeping (1 = normal).
var sleep_mult := 1.0
var _fridge_t := 0.0
var _fridge_hours := -1.0
## Last input device used: "kbm", "touch", "xbox", "ps" or "nintendo".
var device := "kbm"
var force_touch_ui := false
## Shown on the main menu after returning to it (e.g. "The host left").
var menu_message := ""
## This device's player id (saved in the settings, so a host recognises a
## returning guest). A guest gets it confirmed by the host.
var player_id := "p1"
## Host: everything about each guest who has played in this world, by
## player id: {char, inv, player, explored (PNG bytes), out}.
var net_records := {}
var world := {} # Current world's settings and summary (see create_world).


func _ready() -> void:
	quality = Quality.MEDIUM if OS.has_feature("mobile") else Quality.HIGH
	_reset_ws()
	_load_settings()
	_parse_args()
	_setup_input()
	apply_binds()
	inventory.changed.connect(func() -> void: inventory_changed.emit())
	if OS.has_feature("mobile"):
		device = "touch"


func _input(event: InputEvent) -> void:
	var d := device
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		var joy := Input.get_joy_name(event.device).to_lower()
		d = "xbox"
		for k in ["ps", "sony", "dualsense", "dualshock", "playstation"]:
			if k in joy:
				d = "ps"
		for k in ["nintendo", "switch", "joy-con", "pro controller"]:
			if k in joy:
				d = "nintendo"
	elif event is InputEventScreenTouch:
		d = "touch"
	elif event is InputEventKey or (event is InputEventMouseButton and not OS.has_feature("mobile")):
		d = "kbm"
	if d != device:
		device = d
		device_changed.emit()


func using_gamepad() -> bool:
	return device in ["xbox", "ps", "nintendo"]


func _process(delta: float) -> void:
	time_of_day += delta * 24.0 / DAY_LENGTH * time_mult()
	if time_of_day >= 24.0:
		time_of_day -= 24.0
		day += 1
	_fridge_t -= delta
	if _fridge_t <= 0.0:
		_fridge_t = 5.0
		_chill_fridges()


## How fast time runs now: faster while sleeping (in multiplayer only when
## everyone sleeps; the host decides).
func time_mult() -> float:
	return Net.time_mult if Net.active() else sleep_mult


## Is there mains power (and running water)? For the first couple of weeks
## after the outbreak; later only while a restarted power plant runs.
func grid_on() -> bool:
	var days := int(world.get("utilities", 14))
	if days < 0 or day <= days:
		return true
	return hours() < float(ws.grid.get("until", 0.0))


## Fridges with power keep food fresh: push back its spoil time.
func _chill_fridges() -> void:
	var now := hours()
	var elapsed := now - _fridge_hours if _fridge_hours >= 0.0 else 0.0
	_fridge_hours = now
	if elapsed <= 0.0 or not grid_on():
		return
	for id in ws.fridges:
		for it in containers.get(id, []):
			if it.has("exp"):
				it.exp = float(it.exp) + elapsed * 0.8


## In-game hours since the world began (for timers that outlast a day).
func hours() -> float:
	return day * 24.0 + time_of_day


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
	# Zombies live on the host.
	if Net.is_client():
		Net.noise(pos, radius)


func notify(text: String) -> void:
	message.emit(text)


## Doing something trains the skill behind it.
func practice(skill: String, amount: float) -> void:
	var lvl := character.add_xp(skill, amount)
	if lvl > 0:
		notify("%s improved to level %d" % [Character.SKILL_NAMES.get(skill, skill), lvl])
		if skill == "strength":
			inventory.carry_mult = character.mod("carry") * (1.0 + character.skill("strength") * 0.05)


# --- Inventory -------------------------------------------------------------

## Picks up an item (grids, or an empty matching slot). Returns how many
## didn't fit; those are dropped at `drop_pos` when one is given.
func add_item(it: Dictionary, drop_pos: Variant = null) -> int:
	var left := inventory.add(it)
	if left < int(it.get("n", 1)):
		notify("Picked up %s" % ItemDB.item_name(it.id))
	if left > 0 and drop_pos != null:
		var rest := it.duplicate(true)
		rest.n = left
		drop_item(rest, drop_pos)
		notify("No room: dropped %s" % ItemDB.item_name(it.id))
	return left


func item_count(id: String) -> int:
	return inventory.count(id)


func drop_item(it: Dictionary, pos: Vector3, armed := false) -> void:
	var d := it.duplicate(true)
	d.erase("x")
	d.erase("y")
	d.erase("r")
	var drop := {"p": [pos.x, pos.y, pos.z], "it": d, "armed": armed, "id": Net.new_drop_id()}
	drops.append(drop)
	drops_changed.emit()
	Net.drop_added(drop)


func remove_drop(drop: Dictionary) -> void:
	for k in drops.size():
		if is_same(drops[k], drop):
			drops.remove_at(k)
			drops_changed.emit()
			Net.drop_removed(str(drop.get("id", "")))
			return


## A drop changed in place (a sprung trap).
func drop_updated(drop: Dictionary) -> void:
	drops_changed.emit()
	Net.drop_changed(drop)


func drop_by_id(id: String) -> Dictionary:
	for d in drops:
		if str(d.get("id", "")) == id:
			return d
	return {}


func apply_drop_add(d: Dictionary) -> void:
	if not drop_by_id(str(d.id)).is_empty():
		return
	drops.append({"p": d.p, "it": Inventory._clean(d.it), "armed": bool(d.get("armed", false)), "id": str(d.id)})
	drops_changed.emit()


func apply_drop_remove(id: String) -> void:
	for k in drops.size():
		if str(drops[k].get("id", "")) == id:
			drops.remove_at(k)
			drops_changed.emit()
			return


func apply_drop_set(d: Dictionary) -> void:
	var old := drop_by_id(str(d.id))
	if old.is_empty():
		apply_drop_add(d)
		return
	old.armed = bool(d.get("armed", false))
	old.it = Inventory._clean(d.it)
	drops_changed.emit()


## A container's contents changed here (looting): tell the other players.
func container_changed(id: String) -> void:
	Net.container_changed(id)


## Contents of a container, rolled the first time it's opened.
func container_items(ct: Dictionary) -> Array:
	if ct.get("type", "") in ["fridge", "cryo_fridge"]:
		ws.fridges[ct.id] = 1
	if not containers.has(ct.id):
		containers[ct.id] = Loot.fill(ct.type, ct.get("bld", ""), ct.id, ct.get("must", []))
	return containers[ct.id]


## The basic kit plus the character's background items and clothes.
func give_starting_kit() -> void:
	inventory.clear()
	var gear := character.starting_gear()
	for c in gear.clothes:
		var it := ItemDB.make(c[0], 1, 0.9)
		it.v = int(c[1])
		inventory.equip[ItemDB.slot_for(c[0])] = it
	for k in STARTING_KIT:
		inventory.add(ItemDB.make(k[0], k[1], 0.8))
	for k in gear.items:
		inventory.add(ItemDB.make(k[0], k[1], 0.85))
	if character.has_trait("smoker"):
		inventory.add(ItemDB.make("cigarettes"))
	inventory.carry_mult = character.mod("carry") * (1.0 + character.skill("strength") * 0.05)
	inventory.notify()


func infection_chance() -> float:
	return float(world.get("infection", difficulty().infection))


## 0 shamblers (no runners, slower), 1 mixed, 2 fast (many runners).
func zombie_speed() -> int:
	return int(world.get("zspeed", 1))


# --- World changes ---------------------------------------------------------------

func door_state(id: String) -> Dictionary:
	return ws.doors.get(id, {})


func set_door_state(id: String, st: Dictionary) -> void:
	ws.doors[id] = st
	Net.door_changed(id, st)


func window_smashed(id: String) -> bool:
	return ws.windows.has(id)


func smash_window(id: String) -> void:
	ws.windows[id] = 1
	Net.window_smashed(id)


## Boards nailed over a window: their hp (0: none).
func window_boards(id: String) -> float:
	return float(ws.boards.get(id, 0.0))


func set_window_boards(id: String, hp: float) -> void:
	if hp <= 0.0:
		ws.boards.erase(id)
	else:
		ws.boards[id] = hp
	Net.window_boards(id, hp)


func has_power(site: String) -> bool:
	return ws.power.has(site)


func set_power(site: String, pos: Vector3) -> void:
	ws.power[site] = [pos.x, pos.y, pos.z]
	Net.power_on(site, pos)


## Can an interior spawn point hold a zombie again? (Killed ones come back
## after two in-game days.)
func spawn_ready(id: String) -> bool:
	return not ws.spawns.has(id) or hours() - float(ws.spawns[id]) > 48.0


func spawn_killed(id: String) -> void:
	ws.spawns[id] = hours()


func add_turned(entry: Dictionary) -> void:
	if Net.is_client():
		Net.add_turned(entry)
		return
	ws.turned.append(entry)
	Net.turned_changed()


func remove_turned(id: String) -> void:
	ws.turned = ws.turned.filter(func(t: Dictionary) -> bool: return t.id != id)
	Net.turned_changed()


func _reset_ws() -> void:
	ws = {"turned": []}
	for k in WS_KEYS:
		ws[k] = {}
	weather = {"k": "clear", "i": 0.5, "until": 0.0}


# --- Explored map ------------------------------------------------------------------

func _reset_explored() -> void:
	var n := maxi(1, int(world_size / EXPLORE_CELL))
	explored = Image.create(n, n, false, Image.FORMAT_L8)


## Marks the area around a point as seen.
func explore(pos: Vector3, radius := 120.0) -> void:
	if explored == null:
		return
	var n := explored.get_width()
	var c := Vector2(pos.x, pos.z) / EXPLORE_CELL
	var r := radius / EXPLORE_CELL
	for y in range(int(c.y - r), int(c.y + r) + 1):
		for x in range(int(c.x - r), int(c.x + r) + 1):
			if x >= 0 and y >= 0 and x < n and y < n and Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				explored.set_pixel(x, y, Color.WHITE)


func explored_fraction() -> float:
	if explored == null:
		return 0.0
	var data := explored.get_data()
	var seen := 0
	for b in data:
		if b > 0:
			seen += 1
	return float(seen) / maxf(1.0, data.size())


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


func create_world(world_name: String, size: float, seed_value: int, diff: int, rule: int, id := "", extra := {}) -> Dictionary:
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
		"zspeed": 1, "infection": DIFFICULTIES[diff].infection,
	}
	meta.merge(extra, true)
	DirAccess.make_dir_recursive_absolute(WORLDS_DIR + "/" + id)
	_write_json(WORLDS_DIR + "/" + id + "/world.json", meta)
	return meta


func delete_world(id: String) -> void:
	var path := ProjectSettings.globalize_path(WORLDS_DIR + "/" + id)
	for f in ["save.json", "world.json", "map.png", "explored.png"]:
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
	character = pending_character if pending_character else Character.random(world_seed)
	pending_character = null
	give_starting_kit()
	containers.clear()
	drops.clear()
	_reset_ws()
	_reset_explored()


func has_save() -> bool:
	return not world.is_empty() and FileAccess.file_exists(_world_path("save.json"))


func _world_path(file: String) -> String:
	return WORLDS_DIR + "/" + str(world.id) + "/" + file


func save_game(player_data: Dictionary) -> void:
	if world.is_empty() or Net.is_client():
		return
	var data := {
		"version": SAVE_VERSION,
		"time": time_of_day,
		"day": day,
		"kills": kills,
		"inventory": inventory.to_dict(),
		"containers": containers,
		"drops": drops,
		"player": player_data,
		"character": character.to_dict(),
		"world": ws,
		"weather": weather,
		"players": net_records,
	}
	_write_json(_world_path("save.json"), data)
	if explored:
		explored.save_png(_world_path("explored.png"))
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
	var version := int(data.get("version", 0))
	if data.is_empty() or version < 1 or version > SAVE_VERSION:
		return {}
	time_of_day = float(data.get("time", 8.0))
	day = int(data.get("day", 1))
	kills = int(data.get("kills", 0))
	containers.clear()
	drops.clear()
	_reset_ws()
	net_records = data.get("players", {})
	if version >= 3:
		character = Character.from_dict(data.get("character", {}))
		var w: Dictionary = data.get("world", {})
		for k in WS_KEYS:
			ws[k] = w.get(k, {})
		weather = data.get("weather", weather)
		ws.turned = w.get("turned", [])
		for t in ws.turned:
			t.items = (t.get("items", []) as Array).map(func(o: Dictionary) -> Dictionary: return Inventory._clean(o))
	# A character made for this world after a death replaces the saved one.
	if pending_character:
		character = pending_character
		pending_character = null
	var ex := Image.load_from_file(ProjectSettings.globalize_path(_world_path("explored.png"))) if FileAccess.file_exists(_world_path("explored.png")) else null
	if ex and ex.get_width() == explored.get_width():
		ex.convert(Image.FORMAT_L8)
		explored = ex
	if version == 1:
		# Stage 1 saves had simple item counts; keep the world, give a fresh kit.
		give_starting_kit()
		for id in data.get("looted", []):
			containers[str(id)] = []
	else:
		inventory.from_dict(data.get("inventory", {}))
		if version == 2:
			# Stage 2 saves had no clothes: dress the survivor.
			var gear := character.starting_gear()
			for c in gear.clothes:
				var it := ItemDB.make(c[0], 1, 0.9)
				it.v = int(c[1])
				inventory.equip[ItemDB.slot_for(c[0])] = it
		var saved: Dictionary = data.get("containers", {})
		for id in saved:
			containers[id] = (saved[id] as Array).map(func(o: Dictionary) -> Dictionary: return Inventory._clean(o))
		for d in data.get("drops", []):
			drops.append({"p": d.p, "it": Inventory._clean(d.it), "armed": bool(d.get("armed", false)),
				"id": str(d.get("id", Net.new_drop_id()))})
	inventory.carry_mult = character.mod("carry") * (1.0 + character.skill("strength") * 0.05)
	drops_changed.emit()
	return data.get("player", {})


## Marks a world as lost; it stays in the list as a memorial with the
## survivor's story and the map they explored.
func mark_world_lost(cause: String) -> void:
	if world.is_empty():
		return
	world.lost = true
	world.cause = cause
	world.day = day
	world.kills = kills
	world.survivor = character.name
	world.background = Character.BACKGROUNDS[character.background].name
	world.explored = explored_fraction()
	world.lost_at = Time.get_unix_time_from_system()
	_write_json(_world_path("world.json"), world)
	if explored:
		explored.save_png(_world_path("explored.png"))


## Path of a file in a world's folder (for the memorial screen).
func world_file(meta: Dictionary, file: String) -> String:
	return WORLDS_DIR + "/" + str(meta.id) + "/" + file


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
		player_id = str(cfg.get_value("player", "id", ""))
		var opts: Dictionary = cfg.get_value("options", "values", {})
		for k in opts:
			if DEFAULT_SETTINGS.has(k):
				settings[k] = opts[k]
		hints_seen = cfg.get_value("options", "hints_seen", {})
	if player_id == "" or player_id == "p1":
		player_id = "p%08x" % (randi() ^ int(Time.get_unix_time_from_system()))
		_save_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("player", "id", player_id)
	cfg.set_value("options", "values", settings)
	cfg.set_value("options", "hints_seen", hints_seen)
	cfg.save(SETTINGS_PATH)


## Saves the options and applies what can change live.
func save_settings() -> void:
	_save_settings()
	apply_binds()
	settings_changed.emit()


# --- Multiplayer worlds -----------------------------------------------------------

## Host: the shared world state a joining guest needs.
func net_state() -> Dictionary:
	return {"time": time_of_day, "day": day, "containers": containers, "drops": drops, "ws": ws, "weather": weather}


## Guest: starts the host's world. `record` is this player's saved data on
## the host (empty the first time: they make a character).
func start_net_world(meta: Dictionary, state: Dictionary, record: Dictionary) -> void:
	var m := meta.duplicate()
	m.id = "net_" + str(meta.id)
	DirAccess.make_dir_recursive_absolute(WORLDS_DIR + "/" + m.id)
	start_world(m)
	time_of_day = float(state.get("time", 8.0))
	day = int(state.get("day", 1))
	var saved: Dictionary = state.get("containers", {})
	for id in saved:
		containers[id] = (saved[id] as Array).map(func(o: Dictionary) -> Dictionary: return Inventory._clean(o))
	for d in state.get("drops", []):
		apply_drop_add(d)
	var w: Dictionary = state.get("ws", {})
	for k in WS_KEYS:
		ws[k] = w.get(k, {})
	weather = state.get("weather", weather)
	ws.turned = w.get("turned", [])
	net_records = {}
	net_player = record.get("player", {})
	if not record.get("char", {}).is_empty():
		character = Character.from_dict(record.char)
		inventory.from_dict(record.get("inv", {}))
		inventory.carry_mult = character.mod("carry") * (1.0 + character.skill("strength") * 0.05)
		var png: PackedByteArray = record.get("explored", PackedByteArray())
		if not png.is_empty():
			var img := Image.new()
			if img.load_png_from_buffer(png) == OK and img.get_width() == explored.get_width():
				img.convert(Image.FORMAT_L8)
				explored = img
	net_out = bool(record.get("out", false))


## The saved player data a guest resumes with (empty: a new spawn).
var net_player := {}
## Permadeath: this guest is out of the game and can only watch.
var net_out := false


## Guest: everything the host keeps for this survivor.
func local_record(p: Player) -> Dictionary:
	return {"char": character.to_dict(), "inv": inventory.to_dict(), "player": p.to_dict(),
		"explored": explored.save_png_to_buffer() if explored else PackedByteArray(), "out": net_out}


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
	var aim_events: Array = [_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]
	if not OS.has_feature("mobile"):
		var rmb := InputEventMouseButton.new()
		rmb.button_index = MOUSE_BUTTON_RIGHT
		aim_events.append(rmb)
	_action("aim", aim_events)
	_action("reload", [_key(KEY_R), _button(JOY_BUTTON_X)])
	_action("shove", [_key(KEY_V), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_action("crouch", [_key(KEY_C), _key(KEY_CTRL), _button(JOY_BUTTON_RIGHT_STICK)])
	_action("inventory", [_key(KEY_TAB), _key(KEY_I), _button(JOY_BUTTON_BACK)])
	_action("weapon_next", [_wheel(MOUSE_BUTTON_WHEEL_DOWN), _button(JOY_BUTTON_DPAD_RIGHT)])
	_action("weapon_prev", [_wheel(MOUSE_BUTTON_WHEEL_UP), _button(JOY_BUTTON_DPAD_LEFT)])
	for k in 4:
		_action("slot_%d" % (k + 1), [_key(KEY_1 + k)])
	_action("quick_eat", [_key(KEY_Z), _button(JOY_BUTTON_DPAD_UP)])
	_action("quick_heal", [_key(KEY_H), _button(JOY_BUTTON_DPAD_DOWN)])
	_action("flashlight", [_key(KEY_F), _button(JOY_BUTTON_Y)])
	_action("interact", [_key(KEY_E), _button(JOY_BUTTON_B)])
	_action("throw_quick", [_key(KEY_G), _button(JOY_BUTTON_LEFT_SHOULDER)])
	_action("pause", [_key(KEY_ESCAPE), _key(KEY_P), _button(JOY_BUTTON_START)])
	_action("ping", [_key(KEY_Q), _button(JOY_BUTTON_MISC1)])
	_action("craft", [_key(KEY_K)])
	# Inventory screen (gamepad face buttons are read directly there).
	_action("ui_rotate", [_key(KEY_R)])
	_action("toggle_fps", [_key(KEY_F3)])


## Actions players can remap (Settings → Controls), with readable names.
const REMAPPABLE := {"move_forward": "Move forward", "move_back": "Move back", "move_left": "Move left",
	"move_right": "Move right", "jump": "Jump", "sprint": "Sprint", "crouch": "Crouch", "attack": "Attack",
	"aim": "Aim", "reload": "Reload / second action", "shove": "Shove", "interact": "Use", "inventory": "Inventory",
	"flashlight": "Flashlight", "quick_eat": "Eat / drink", "quick_heal": "Heal", "throw_quick": "Quick throw",
	"craft": "Crafting", "ping": "Ping", "weapon_next": "Next weapon", "weapon_prev": "Previous weapon"}


## Default controls, then the player's remapped keys and buttons on top.
func apply_binds() -> void:
	for a in REMAPPABLE:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
	_setup_input()
	var binds: Dictionary = settings.get("binds", {})
	for a in binds:
		if not InputMap.has_action(a):
			continue
		var b: Array = binds[a]
		var key := int(b[0]) if b.size() > 0 else -1
		var joy := int(b[1]) if b.size() > 1 else -1
		for e in InputMap.action_get_events(a):
			if (key >= 0 and (e is InputEventKey or e is InputEventMouseButton)) or (joy >= 0 and e is InputEventJoypadButton):
				InputMap.action_erase_event(a, e)
		if key >= 0:
			InputMap.action_add_event(a, _key(key as Key))
		if joy >= 0:
			InputMap.action_add_event(a, _button(joy as JoyButton))


## Remaps one action (from the Settings screen): a key, or a gamepad button.
func bind(action: String, event: InputEvent) -> void:
	var binds: Dictionary = settings.binds
	var b: Array = binds.get(action, [-1, -1])
	if event is InputEventKey:
		b[0] = int((event as InputEventKey).physical_keycode if (event as InputEventKey).keycode == 0 else (event as InputEventKey).keycode)
	elif event is InputEventJoypadButton:
		b[1] = int((event as InputEventJoypadButton).button_index)
	binds[action] = b
	save_settings()


func reset_binds() -> void:
	settings.binds = {}
	save_settings()


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


func _wheel(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
