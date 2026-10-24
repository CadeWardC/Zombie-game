class_name MenuTheme
extends RefCounted
## The look shared by the menus (main menu, character creator, map).

const BG := Color(0.06, 0.07, 0.07)
const ACCENT := Color(0.62, 0.12, 0.1)
const TEXT := Color(0.85, 0.82, 0.75)
const DIM := Color(0.6, 0.58, 0.55)


static func make(font_size := 24) -> Theme:
	var t := Theme.new()
	t.default_font_size = font_size
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.15, 0.15)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.22, 0.23, 0.23)
	var focus := normal.duplicate()
	focus.bg_color = Color(0.22, 0.23, 0.23)
	focus.border_color = ACCENT.lightened(0.2)
	focus.set_border_width_all(3)
	var pressed := normal.duplicate()
	pressed.bg_color = ACCENT
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.1, 0.1, 0.1)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("focus", cls, focus)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.4, 0.4))
	t.set_stylebox("normal", "LineEdit", normal)
	t.set_stylebox("focus", "LineEdit", focus)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.1, 0.1, 0.96)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(14)
	t.set_stylebox("panel", "PanelContainer", panel)
	return t


## Focus a control on the next frame, if it's still there (menus that
## rebuild their lists quickly free the old buttons).
static func focus_later(c: Control) -> void:
	if c == null:
		return
	(func() -> void:
		if is_instance_valid(c) and c.is_inside_tree():
			c.grab_focus()).call_deferred()
