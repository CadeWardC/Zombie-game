class_name TouchControls
extends Control
## Multitouch on-screen controls: floating joystick on the left, drag-to-look
## on the right, and action buttons. Each finger is tracked by its touch index,
## so you can move, look and attack at the same time (built-in GUI buttons only
## follow one finger).

const JOY_RADIUS := 90.0
const LOOK_ZONE := 0.45 # Left 45% of the screen is the joystick zone.

var move_vector := Vector2.ZERO

var _look_delta := Vector2.ZERO
var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_index := -1
var _sprint_on := false
# anchor: fraction of the screen size; offset: pixels from that anchor.
var _buttons := [
	{"action": "attack", "label": "HIT", "anchor": Vector2(1, 1), "offset": Vector2(-140, -160), "radius": 72.0},
	{"action": "jump", "label": "JUMP", "anchor": Vector2(1, 1), "offset": Vector2(-290, -90), "radius": 50.0},
	{"action": "sprint", "label": "RUN", "anchor": Vector2(1, 1), "offset": Vector2(-110, -320), "radius": 50.0, "toggle": true},
	{"action": "flashlight", "label": "LIGHT", "anchor": Vector2(1, 1), "offset": Vector2(-260, -260), "radius": 40.0},
	{"action": "interact", "label": "USE", "anchor": Vector2(1, 1), "offset": Vector2(-400, -160), "radius": 48.0},
	{"action": "use_food", "label": "EAT", "anchor": Vector2(1, 0), "offset": Vector2(-250, 60), "radius": 38.0, "item": "food"},
	{"action": "use_water", "label": "DRINK", "anchor": Vector2(1, 0), "offset": Vector2(-160, 60), "radius": 38.0, "item": "water"},
	{"action": "use_bandage", "label": "HEAL", "anchor": Vector2(1, 0), "offset": Vector2(-70, 60), "radius": 38.0, "item": "bandage"},
	{"action": "pause", "label": "II", "anchor": Vector2(0.5, 0), "offset": Vector2(0, 40), "radius": 30.0},
]


func _init() -> void:
	for b in _buttons:
		b["index"] = -1 # Touch index currently holding this button.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.inventory_changed.connect(queue_redraw)


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


func _button_center(b: Dictionary) -> Vector2:
	return size * (b.anchor as Vector2) + (b.offset as Vector2)


func _input(event: InputEvent) -> void:
	if not visible:
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
			queue_redraw()
		elif event.index == _look_index:
			_look_delta += event.relative


func _on_press(index: int, pos: Vector2) -> void:
	for b in _buttons:
		if pos.distance_to(_button_center(b)) <= b.radius * 1.15:
			b.index = index
			if b.get("toggle", false):
				_sprint_on = not _sprint_on
				if _sprint_on:
					Input.action_press(b.action)
				else:
					Input.action_release(b.action)
			else:
				Input.action_press(b.action)
			queue_redraw()
			return
	if pos.x < size.x * LOOK_ZONE and _joy_index == -1:
		_joy_index = index
		_joy_origin = pos
		_joy_pos = pos
		queue_redraw()
	elif _look_index == -1:
		_look_index = index


func _on_release(index: int) -> void:
	for b in _buttons:
		if b.index == index:
			b.index = -1
			if not b.get("toggle", false):
				Input.action_release(b.action)
			queue_redraw()
			return
	if index == _joy_index:
		_joy_index = -1
		move_vector = Vector2.ZERO
		# Releasing the stick also ends a sprint, like most mobile shooters.
		if _sprint_on:
			_sprint_on = false
			Input.action_release("sprint")
		queue_redraw()
	elif index == _look_index:
		_look_index = -1


func _draw() -> void:
	var font := get_theme_default_font()
	if _joy_index != -1:
		draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
		draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		draw_circle(_joy_origin + move_vector * JOY_RADIUS, 38.0, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(170, size.y - 170)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.15), 2.0)
	for b in _buttons:
		var c := _button_center(b)
		var pressed: bool = b.index != -1 or (b.get("toggle", false) and _sprint_on)
		draw_circle(c, b.radius, Color(1, 1, 1, 0.35 if pressed else 0.16))
		draw_arc(c, b.radius, 0, TAU, 40, Color(1, 1, 1, 0.5), 2.0)
		var label: String = b.label
		if b.has("item"):
			label += "\n%d" % GameState.item_count(b.item)
		var fs := 18 if b.radius > 45.0 else 14
		var lines := label.split("\n")
		for l in lines.size():
			var w := font.get_string_size(lines[l], HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			var y := c.y + fs * 0.35 + (l - (lines.size() - 1) * 0.5) * fs * 1.1
			draw_string(font, Vector2(c.x - w * 0.5, y), lines[l], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
