class_name MenuTheme
extends RefCounted
## The game's look: colours, fonts and the styles every menu and panel uses.
## apply_global() restyles Godot's default theme at startup, so every control
## in the game (menus, inventory, settings, the HUD) shares it without each
## screen setting its own.

const BG := Color(0.055, 0.06, 0.065)
const PANEL := Color(0.08, 0.087, 0.092, 0.95)
const CARD := Color(0.11, 0.118, 0.125, 0.96)
const LINE := Color(1, 1, 1, 0.07)
const ACCENT := Color(0.78, 0.27, 0.17) # Rust red.
const ACCENT_HI := Color(0.92, 0.4, 0.26)
const TEXT := Color(0.91, 0.89, 0.84)
const DIM := Color(0.6, 0.59, 0.56)
const WARN := Color(0.93, 0.66, 0.24)
const GOOD := Color(0.5, 0.74, 0.42)
const BAD := Color(0.9, 0.3, 0.25)
const COLD := Color(0.45, 0.7, 0.95)
## Translucent HUD panels over the game view.
const HUD_PANEL := Color(0.04, 0.045, 0.05, 0.62)

static var _heading: FontVariation
static var _bold: FontVariation
static var _applied := false


## Bold, letter-spaced font for titles and section headings.
static func heading_font() -> Font:
	if _heading == null:
		_heading = FontVariation.new()
		_heading.base_font = ThemeDB.fallback_font
		_heading.variation_embolden = 0.9
		_heading.spacing_glyph = 2
	return _heading


## Bold body font (names, numbers on the HUD).
static func bold_font() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.6
	return _bold


static func box(bg: Color, radius := 6, border := LINE, border_w := 1, margin := 12.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.content_margin_left = margin + 2.0
	sb.content_margin_right = margin + 2.0
	sb.content_margin_top = margin * 0.7
	sb.content_margin_bottom = margin * 0.7
	sb.anti_aliasing = true
	return sb


## A panel with a coloured stripe down its left edge (tips, notices).
static func stripe_box(bg: Color, stripe: Color, radius := 8) -> StyleBoxFlat:
	var sb := box(bg, radius, stripe, 0, 12.0)
	sb.border_width_left = 4
	return sb


## Restyles Godot's default theme (call once at startup).
static func apply_global() -> void:
	if _applied:
		return
	_applied = true
	fill(ThemeDB.get_default_theme())


static func make(font_size := 24) -> Theme:
	var t := Theme.new()
	fill(t)
	t.default_font_size = font_size
	return t


static func fill(t: Theme) -> void:
	t.default_font_size = 18
	var normal := box(Color(0.12, 0.128, 0.135, 0.95))
	normal.border_color = Color(1, 1, 1, 0.06)
	normal.border_width_bottom = 2
	normal.border_color = Color(0, 0, 0, 0.35)
	var hover := box(Color(0.17, 0.178, 0.185, 0.97), 6, Color(1, 1, 1, 0.12))
	var pressed := box(Color(ACCENT.darkened(0.35), 0.75), 6, ACCENT_HI, 2)
	var disabled := box(Color(0.085, 0.09, 0.095, 0.9), 6, Color(1, 1, 1, 0.03))
	# Focus is drawn over the normal style: just a bright outline.
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = ACCENT_HI
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(7)
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	for cls in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_hover_pressed_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, Color(0.42, 0.42, 0.42))
	for cls in ["CheckBox", "CheckButton"]:
		var clear := StyleBoxEmpty.new()
		t.set_stylebox("normal", cls, clear)
		t.set_stylebox("pressed", cls, clear)
	t.set_stylebox("normal", "LineEdit", box(Color(0.06, 0.065, 0.07, 0.95), 6, Color(1, 1, 1, 0.1)))
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT_HI)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.5))
	var panel := box(PANEL, 10, LINE, 1, 14.0)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PopupPanel", panel)
	var popup := box(Color(0.1, 0.105, 0.11, 0.99), 6, Color(1, 1, 1, 0.1), 1, 6.0)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.6), 4, Color(0, 0, 0, 0), 0, 6.0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 10)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("tooltip", "TooltipPanel", popup)
	# Bars.
	var bar_bg := box(Color(0, 0, 0, 0.45), 3, Color(0, 0, 0, 0), 0, 0.0)
	var bar_fill := box(ACCENT, 3, Color(0, 0, 0, 0), 0, 0.0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	# Sliders.
	var track := box(Color(0, 0, 0, 0.5), 3, Color(0, 0, 0, 0), 0, 0.0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var track_fill := box(ACCENT, 3, Color(0, 0, 0, 0), 0, 0.0)
	track_fill.content_margin_top = 3
	track_fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", track_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", track_fill)
	t.set_icon("grabber", "HSlider", _knob(18, TEXT))
	t.set_icon("grabber_highlight", "HSlider", _knob(18, Color.WHITE))
	# Thin scroll bars.
	for cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, box(Color(0, 0, 0, 0.25), 4, Color(0, 0, 0, 0), 0, 3.0))
		t.set_stylebox("grabber", cls, box(Color(1, 1, 1, 0.22), 4, Color(0, 0, 0, 0), 0, 3.0))
		t.set_stylebox("grabber_highlight", cls, box(Color(1, 1, 1, 0.35), 4, Color(0, 0, 0, 0), 0, 3.0))
		t.set_stylebox("grabber_pressed", cls, box(ACCENT, 4, Color(0, 0, 0, 0), 0, 3.0))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.0))


## A round slider knob, drawn into a small image.
static func _knob(px: int, col: Color) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var r := px * 0.5
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(col, a) if d < r - 2.5 else Color(0.1, 0.1, 0.1, a))
	return ImageTexture.create_from_image(img)


## The main action on a screen: a solid accent button.
static func primary(b: Button) -> void:
	var n := box(ACCENT, 6, ACCENT_HI.darkened(0.1), 1)
	n.border_width_bottom = 3
	n.border_color = ACCENT.darkened(0.45)
	var h := box(ACCENT_HI, 6, ACCENT_HI.lightened(0.2), 1)
	h.border_width_bottom = 3
	h.border_color = ACCENT.darkened(0.4)
	var d := box(Color(ACCENT.darkened(0.6), 0.6), 6, Color(0, 0, 0, 0), 0)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.add_theme_font_override("font", heading_font())


## A card inside a panel (slightly lighter than the panel).
static func card() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(CARD, 10, LINE, 1, 16.0))
	return p


## A small rounded tag ("Aiming 2", "-4").
static func tag(text: String, col: Color, size := 13) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(col.darkened(0.65), 0.85), 10, Color(col, 0.5), 1, 5.0)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", bold_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col.lightened(0.3))
	p.add_child(l)
	return p


## A heading label: bold, spaced, in capitals.
static func heading(text: String, size := 20, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", heading_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## A heading with a short accent underline (section titles in panels).
static func section(text: String, size := 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(heading(text, size, DIM.lightened(0.25)))
	var bar := ColorRect.new()
	bar.color = ACCENT
	bar.custom_minimum_size = Vector2(36, 2)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(bar)
	return v


## Focus a control on the next frame, if it's still there (menus that
## rebuild their lists quickly free the old buttons).
static func focus_later(c: Control) -> void:
	if c == null:
		return
	(func() -> void:
		if is_instance_valid(c) and c.is_inside_tree():
			c.grab_focus()).call_deferred()
