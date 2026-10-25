class_name TouchControls
extends Control
## Multitouch on-screen controls: floating joystick on the left, drag-to-look
## on the right, and action buttons. Each finger is tracked by its touch index,
## so you can move, look and attack at the same time (built-in GUI buttons only
## follow one finger). Buttons that don't apply right now (AIM and RELOAD with
## a melee weapon) are hidden.

const JOY_RADIUS := 90.0
const LOOK_ZONE := 0.45 # Left 45% of the screen is the joystick zone.

var move_vector := Vector2.ZERO
var player: Player

var _look_delta := Vector2.ZERO
var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_index := -1
var _texts: Array = [] # Text queued while drawing (see _draw_buttons).
var _vp: SubViewport
var _art: Control
var _key := ""
var _toggled := {} # action -> bool, for toggle buttons (RUN, AIM).
# anchor: fraction of the screen size; offset: pixels from that anchor.
# show: "ranged" = only with a gun or bow.
var _buttons := [
	{"action": "attack", "label": "HIT", "icon": "fist", "anchor": Vector2(1, 1), "offset": Vector2(-130, -150), "radius": 68.0},
	{"action": "aim", "label": "AIM", "icon": "aim", "anchor": Vector2(1, 1), "offset": Vector2(-120, -292), "radius": 42.0, "toggle": true, "show": "ranged"},
	{"action": "reload", "label": "RELOAD", "icon": "reload", "anchor": Vector2(1, 1), "offset": Vector2(-238, -350), "radius": 34.0, "show": "ranged"},
	{"action": "shove", "label": "SHOVE", "icon": "shove", "anchor": Vector2(1, 1), "offset": Vector2(-264, -232), "radius": 40.0},
	{"action": "jump", "label": "JUMP", "icon": "jump", "anchor": Vector2(1, 1), "offset": Vector2(-270, -92), "radius": 42.0},
	{"action": "interact", "label": "USE", "icon": "hand", "anchor": Vector2(1, 1), "offset": Vector2(-396, -142), "radius": 46.0},
	{"action": "crouch", "label": "CROUCH", "icon": "crouch", "anchor": Vector2(1, 1), "offset": Vector2(-398, -278), "radius": 38.0},
	{"action": "sprint", "label": "RUN", "icon": "run", "anchor": Vector2(1, 1), "offset": Vector2(-56, -396), "radius": 40.0, "toggle": true},
	{"action": "pause", "label": "", "icon": "pause", "anchor": Vector2(1, 0), "offset": Vector2(-42, 42), "radius": 26.0},
	{"action": "inventory", "label": "BAG", "icon": "bag", "anchor": Vector2(1, 0), "offset": Vector2(-118, 52), "radius": 34.0},
	{"action": "weapon_next", "label": "SWAP", "icon": "swap", "anchor": Vector2(1, 0), "offset": Vector2(-198, 52), "radius": 34.0},
	{"action": "quick_heal", "label": "HEAL", "icon": "heal", "anchor": Vector2(1, 0), "offset": Vector2(-278, 52), "radius": 34.0, "item": "medical"},
	{"action": "quick_eat", "label": "EAT", "icon": "eat", "anchor": Vector2(1, 0), "offset": Vector2(-358, 52), "radius": 34.0, "item": "food"},
	{"action": "flashlight", "label": "LIGHT", "icon": "light", "anchor": Vector2(1, 0), "offset": Vector2(-438, 52), "radius": 34.0},
	{"action": "ping", "label": "PING", "icon": "ping", "anchor": Vector2(1, 0), "offset": Vector2(-518, 52), "radius": 34.0, "show": "net"},
]


func _init() -> void:
	for b in _buttons:
		b["index"] = -1 # Touch index currently holding this button.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The buttons are drawn into an off-screen texture, redrawn only when
	# one changes, and shown as a single picture: dozens of shapes and
	# labels every frame would cost the Tab S6 Lite ~80 draw calls.
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_buttons)
	_vp.add_child(_art)
	GameState.inventory_changed.connect(func() -> void: _key = "")


func consume_look() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d


func _notification(what: int) -> void:
	# If the game pauses mid-touch we never see the release, so let go of
	# everything to avoid stuck inputs.
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_release_all()


func _release_all() -> void:
	for b in _buttons:
		if b.index != -1:
			b.index = -1
			if not b.get("toggle", false):
				Input.action_release(b.action)
	_joy_index = -1
	_look_index = -1
	move_vector = Vector2.ZERO
	queue_redraw()


func _holding_anything() -> bool:
	if _joy_index != -1 or _look_index != -1:
		return true
	for b in _buttons:
		if b.index != -1:
			return true
	return false


func _shown(b: Dictionary) -> bool:
	# The reload button doubles as the second action (board up, rotate...).
	if b.action == "reload" and player != null and player.alt_prompt != "" and not player.vehicle:
		return true
	if player != null and player.vehicle:
		# Driving: no aiming, shoving or switching weapons.
		if b.action in ["aim", "shove", "weapon_next"]:
			return false
		if b.action == "reload":
			return player.seat == 0
	match b.get("show", ""):
		"ranged":
			return player != null and player.weapons.is_ranged()
		"net":
			return Net.active()
	return true


func _button_center(b: Dictionary) -> Vector2:
	return size * (b.anchor as Vector2) + (b.offset as Vector2)


func _process(_delta: float) -> void:
	# A toggled AIM shouldn't outlive the gun (switching to a bat).
	if _toggled.get("aim", false) and not _shown(_buttons[1]):
		_set_toggle("aim", false)
	# Re-render the buttons only when something about them changed.
	var k := _state_key()
	if k != _key:
		_key = k
		var sc := get_viewport().get_final_transform().get_scale().x if get_viewport() else 1.0
		_vp.size = Vector2i(maxi(1, int(size.x * sc)), maxi(1, int(size.y * sc)))
		_vp.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(sc, sc))
		_art.size = size
		_art.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


## Everything the buttons' look depends on.
func _state_key() -> String:
	var parts: PackedStringArray = [str(size), str(GameState.ui_open), str(player != null and player.dead), str(_joy_index != -1)]
	for b in _buttons:
		if not _shown(b):
			parts.append("-")
			continue
		var pressed: bool = b.index != -1 or _toggled.get(b.action, false) or (b.action == "crouch" and player and player.crouching)
		parts.append("%s%d%s%s%d" % [b.action, int(pressed), _label(b), _icon(b), _count(b) if b.has("item") else 0])
	return "|".join(parts)


func _set_toggle(action: String, on: bool) -> void:
	_toggled[action] = on
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if GameState.ui_open:
		if _holding_anything():
			_release_all()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _joy_index:
			_joy_pos = event.position
			var v: Vector2 = (_joy_pos - _joy_origin) / JOY_RADIUS
			move_vector = v.limit_length(1.0)
		elif event.index == _look_index:
			_look_delta += event.relative


func _on_press(index: int, pos: Vector2) -> void:
	for b in _buttons:
		if _shown(b) and pos.distance_to(_button_center(b)) <= b.radius * 1.15:
			b.index = index
			if b.get("toggle", false):
				_set_toggle(b.action, not _toggled.get(b.action, false))
			else:
				Input.action_press(b.action)
			return
	if pos.x < size.x * LOOK_ZONE and _joy_index == -1:
		_joy_index = index
		_joy_origin = pos
		_joy_pos = pos
	elif _look_index == -1:
		_look_index = index


func _on_release(index: int) -> void:
	for b in _buttons:
		if b.index == index:
			b.index = -1
			if not b.get("toggle", false):
				Input.action_release(b.action)
			return
	if index == _joy_index:
		_joy_index = -1
		move_vector = Vector2.ZERO
		# Releasing the stick also ends a sprint, like most mobile shooters.
		if _toggled.get("sprint", false):
			_set_toggle("sprint", false)
	elif index == _look_index:
		_look_index = -1


func _label(b: Dictionary) -> String:
	if player == null:
		return b.label
	if player.build.active():
		match b.action:
			"attack":
				return "PLACE"
			"reload":
				return "ROTATE"
			"interact":
				return "CANCEL"
	elif b.action == "reload" and player.alt_prompt != "" and not player.vehicle:
		return player.alt_prompt.get_slice(" (", 0).to_upper().substr(0, 10)
	if player.vehicle:
		match b.action:
			"attack":
				return "HORN"
			"jump":
				return {"plane": "THROTTLE+", "heli": "UP"}.get(player.vehicle.kind, "BRAKE")
			"crouch":
				return {"plane": "THROTTLE-", "heli": "DOWN"}.get(player.vehicle.kind, "-")
			"interact":
				return "EXIT"
			"flashlight":
				return "LIGHTS"
			"reload":
				return "START"
	match b.action:
		"attack":
			var cat: String = player.weapons.def().get("cat", "")
			return {"gun": "FIRE", "bow": "SHOOT", "throw": "THROW"}.get(cat, "HIT")
		"crouch":
			return "STAND" if player.crouching else "CROUCH"
	return b.label


## How many usable items an EAT / HEAL button has to work with.
func _count(b: Dictionary) -> int:
	var n := 0
	for g in GameState.inventory.grids():
		for it in g.items:
			var cat: String = ItemDB.get_def(it.id).get("cat", "")
			if cat == b.item or (b.item == "food" and cat == "drink"):
				n += int(it.get("n", 1))
	return n


func _icon(b: Dictionary) -> String:
	if player == null:
		return b.icon
	if player.build.active():
		match b.action:
			"attack":
				return "place"
			"interact":
				return "close"
	elif b.action == "reload" and player.alt_prompt != "" and not player.vehicle:
		return "hand"
	if player.vehicle:
		match b.action:
			"attack":
				return "horn"
			"jump":
				return "up" if player.vehicle.kind in ["plane", "heli"] else "brake"
			"crouch":
				return "down"
			"interact":
				return "exit"
			"reload":
				return "key"
	match b.action:
		"attack":
			return {"gun": "gun", "bow": "bow", "throw": "throw"}.get(player.weapons.def().get("cat", ""), "fist")
		"crouch":
			return "stand" if player.crouching else "crouch"
	return b.icon


func _draw() -> void:
	if GameState.ui_open or (player and player.dead):
		return
	draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, size), false)
	if _joy_index != -1:
		draw_circle(_joy_origin, JOY_RADIUS, Color(0.04, 0.045, 0.05, 0.35))
		draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.3), 2.0)
		var knob := _joy_origin + move_vector * JOY_RADIUS
		draw_circle(knob, 36.0, Color(0.9, 0.9, 0.88, 0.35))
		draw_arc(knob, 36.0, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0)


func _draw_buttons() -> void:
	if GameState.ui_open or (player and player.dead):
		return
	var ci := _art
	_texts.clear()
	var font := MenuTheme.bold_font()
	if _joy_index == -1:
		var hint := Vector2(170, size.y - 170)
		ci.draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.14), 2.0)
		ci.draw_circle(hint, 30.0, Color(1, 1, 1, 0.06))
	for b in _buttons:
		if not _shown(b):
			continue
		var c := _button_center(b)
		var r: float = b.radius
		var pressed: bool = b.index != -1 or _toggled.get(b.action, false) or (b.action == "crouch" and player and player.crouching)
		var main: bool = b.action == "attack"
		ci.draw_circle(c, r, Color(MenuTheme.ACCENT, 0.62) if pressed else Color(0.04, 0.045, 0.05, 0.42))
		ci.draw_arc(c, r - 1.0, 0, TAU, 48, Color(MenuTheme.ACCENT_HI, 0.85) if main or pressed else Color(1, 1, 1, 0.3), 2.5 if main else 2.0)
		var caption := _label(b)
		var has_caption := caption != "" and r >= 38.0
		var icon_c := c + Vector2(0, -r * 0.14 if has_caption else 0.0)
		Icons.draw(ci, _icon(b), icon_c, r * (0.62 if has_caption else 0.8), Color(1, 1, 1, 0.92))
		if has_caption:
			var fs := 12 if r > 50.0 else 10
			var w := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_texts.append([false, font, Vector2(c.x - w * 0.5, c.y + r * 0.58), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.8)])
		elif caption != "" and b.anchor.y == 0.0:
			var fs := 10
			var w := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_texts.append([true, font, Vector2(c.x - w * 0.5, c.y + r + 13), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.6)])
			_texts.append([false, font, Vector2(c.x - w * 0.5, c.y + r + 13), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75)])
		if b.has("item"):
			var n := _count(b)
			var bc := c + Vector2(r * 0.72, -r * 0.72)
			ci.draw_circle(bc, 11.0, MenuTheme.ACCENT if n > 0 else Color(0.25, 0.25, 0.25, 0.9))
			var t := str(n)
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			_texts.append([false, font, Vector2(bc.x - tw * 0.5, bc.y + 4.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE])
	for t in _texts:
		if t[0]:
			ci.draw_string_outline(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
		else:
			ci.draw_string(t[1], t[2], t[3], t[4], t[5], t[6], t[7])
