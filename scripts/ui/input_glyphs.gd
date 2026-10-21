class_name InputGlyphs
extends RefCounted
## Button prompts that match the input device in use: Xbox letters,
## PlayStation shapes, Nintendo letters, or keyboard keys. Drawn with
## primitives, so no icon fonts or images are needed.

## action -> gamepad button (JoyButton) or axis name; layout-independent.
const PAD := {
	"attack": "RT", "aim": "LT", "jump": JOY_BUTTON_A, "interact": JOY_BUTTON_B, "reload": JOY_BUTTON_X,
	"flashlight": JOY_BUTTON_Y, "shove": JOY_BUTTON_RIGHT_SHOULDER, "throw_quick": JOY_BUTTON_LEFT_SHOULDER,
	"sprint": JOY_BUTTON_LEFT_STICK, "crouch": JOY_BUTTON_RIGHT_STICK, "inventory": JOY_BUTTON_BACK,
	"pause": JOY_BUTTON_START, "quick_eat": JOY_BUTTON_DPAD_UP, "quick_heal": JOY_BUTTON_DPAD_DOWN,
	"weapon_next": JOY_BUTTON_DPAD_RIGHT, "weapon_prev": JOY_BUTTON_DPAD_LEFT,
	"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B,
}

const XBOX := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS", JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", "LT": "LT", "RT": "RT"}
const PS := {JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_BACK: "Create", JOY_BUTTON_START: "Options", "LT": "L2", "RT": "R2"}
# Nintendo prints A on the right and B on the bottom (positions stay the same).
const NINTENDO := {JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
	JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R", JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS", JOY_BUTTON_BACK: "-", JOY_BUTTON_START: "+", "LT": "ZL", "RT": "ZR"}
const XBOX_COLORS := {JOY_BUTTON_A: Color(0.3, 0.7, 0.25), JOY_BUTTON_B: Color(0.8, 0.2, 0.15),
	JOY_BUTTON_X: Color(0.2, 0.45, 0.85), JOY_BUTTON_Y: Color(0.9, 0.7, 0.1)}
const PS_COLORS := {JOY_BUTTON_A: Color(0.45, 0.6, 0.95), JOY_BUTTON_B: Color(0.95, 0.35, 0.4),
	JOY_BUTTON_X: Color(0.9, 0.5, 0.8), JOY_BUTTON_Y: Color(0.3, 0.85, 0.65)}


## Short text for an action's key or button on the current device ("E", "RT").
static func text(action: String) -> String:
	if GameState.using_gamepad():
		var b: Variant = PAD.get(action)
		if b == null:
			return ""
		if b is int and b >= JOY_BUTTON_DPAD_UP and b <= JOY_BUTTON_DPAD_RIGHT:
			return {JOY_BUTTON_DPAD_UP: "Up", JOY_BUTTON_DPAD_DOWN: "Down", JOY_BUTTON_DPAD_LEFT: "Left", JOY_BUTTON_DPAD_RIGHT: "Right"}[b]
		var table: Dictionary = {"ps": PS, "nintendo": NINTENDO}.get(GameState.device, XBOX)
		return table.get(b, XBOX.get(b, "?"))
	for e in (InputMap.action_get_events(action) if InputMap.has_action(action) else []):
		if e is InputEventKey:
			return OS.get_keycode_string(e.physical_keycode)
		if e is InputEventMouseButton:
			return {MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_WHEEL_UP: "Wheel", MOUSE_BUTTON_WHEEL_DOWN: "Wheel"}.get(e.button_index, "Mouse")
	return ""


## Width the glyph for `action` needs at height `h`.
static func width(action: String, font: Font, h: float) -> float:
	var t := text(action)
	if t == "":
		return 0.0
	var b: Variant = PAD.get(action)
	if GameState.using_gamepad() and b is int and b <= JOY_BUTTON_Y:
		return h
	return maxf(h, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.55)).x + h * 0.5)


## Draws the glyph for `action` on `ci` with its top-left at `pos`. Returns
## the width drawn (0 when the action has no binding on this device).
static func draw(ci: CanvasItem, action: String, pos: Vector2, h: float, font: Font) -> float:
	var t := text(action)
	if t == "":
		return 0.0
	var w := width(action, font, h)
	var b: Variant = PAD.get(action)
	var fs := int(h * 0.55)
	if GameState.using_gamepad() and b is int and b <= JOY_BUTTON_Y:
		var c := pos + Vector2(h, h) * 0.5
		if GameState.device == "ps":
			ci.draw_circle(c, h * 0.5, Color(0.1, 0.1, 0.12, 0.9))
			_ps_shape(ci, b, c, h * 0.26, PS_COLORS[b])
			return w
		ci.draw_circle(c, h * 0.5, XBOX_COLORS[b] if GameState.device == "xbox" else Color(0.15, 0.15, 0.17, 0.9))
		_centered(ci, font, t, c, fs, Color.WHITE)
		return w
	# Keys, shoulders, triggers, d-pad: a rounded key cap.
	var r := Rect2(pos, Vector2(w, h))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.92, 0.92, 0.9, 0.95) if not GameState.using_gamepad() else Color(0.15, 0.15, 0.17, 0.92)
	sb.set_corner_radius_all(int(h * 0.22))
	ci.draw_style_box(sb, r)
	_centered(ci, font, t, r.get_center(), fs, Color(0.1, 0.1, 0.1) if not GameState.using_gamepad() else Color.WHITE)
	return w


static func _centered(ci: CanvasItem, font: Font, t: String, c: Vector2, fs: int, col: Color) -> void:
	var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	ci.draw_string(font, Vector2(c.x - sz.x * 0.5, c.y + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func _ps_shape(ci: CanvasItem, b: int, c: Vector2, r: float, col: Color) -> void:
	match b:
		JOY_BUTTON_A: # Cross
			ci.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, 2.5)
			ci.draw_line(c + Vector2(-r, r), c + Vector2(r, -r), col, 2.5)
		JOY_BUTTON_B: # Circle
			ci.draw_arc(c, r, 0, TAU, 20, col, 2.5)
		JOY_BUTTON_X: # Square
			ci.draw_rect(Rect2(c - Vector2(r, r) * 0.9, Vector2(r, r) * 1.8), col, false, 2.5)
		JOY_BUTTON_Y: # Triangle
			var p := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.75), c + Vector2(-r, r * 0.75), c + Vector2(0, -r)])
			ci.draw_polyline(p, col, 2.5)
