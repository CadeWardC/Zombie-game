extends Control
## Main menu: continue, create a world, load / delete worlds, settings.
## Built in code; fully usable with touch, mouse or gamepad (focus follows
## the D-pad / stick).

const BG := Color(0.06, 0.07, 0.07)
const ACCENT := Color(0.62, 0.12, 0.1)

var _screens := {}
var _name_edit: LineEdit
var _seed_edit: LineEdit
var _size_opt: OptionButton
var _diff_opt: OptionButton
var _rule_opt: OptionButton
var _world_list: VBoxContainer
var _quality_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stripe := ColorRect.new()
	stripe.color = ACCENT.darkened(0.5)
	add_child(stripe)
	stripe.anchor_right = 1.0
	stripe.offset_top = 0
	stripe.offset_bottom = 6
	_build_home()
	_build_new_world()
	_build_load()
	_build_settings()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show("home")


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.15, 0.15)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(12)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.22, 0.23, 0.23)
	var focus := normal.duplicate()
	focus.bg_color = Color(0.22, 0.23, 0.23)
	focus.border_color = ACCENT.lightened(0.2)
	focus.set_border_width_all(3)
	var pressed := normal.duplicate()
	pressed.bg_color = ACCENT
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("focus", cls, focus)
		t.set_stylebox("pressed", cls, pressed)
	t.set_stylebox("normal", "LineEdit", normal)
	t.set_stylebox("focus", "LineEdit", focus)
	return t


func _screen(screen_name: String, title: String) -> VBoxContainer:
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 56 if screen_name == "home" else 38)
	l.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	box.add_child(l)
	_screens[screen_name] = center
	return box


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 66)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _row(parent: Node, label: String, control: Control) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.y = 56
	h.add_child(control)
	parent.add_child(h)


func _show(screen_name: String) -> void:
	for k in _screens:
		_screens[k].visible = k == screen_name
	if screen_name == "load":
		_refresh_worlds()
	# Give focus to the first button so gamepads work immediately.
	var first := _first_focusable(_screens[screen_name])
	if first:
		first.grab_focus.call_deferred()


func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL and c.visible:
			return c
		var f := _first_focusable(c)
		if f:
			return f
	return null


# --- Home ----------------------------------------------------------------------

func _build_home() -> void:
	var box := _screen("home", "ZOMBIE SURVIVAL")
	var sub := Label.new()
	sub.text = "How long will you last?"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
	box.add_child(sub)
	var latest := _latest_playable()
	if not latest.is_empty():
		_button(box, "Continue  -  %s (day %d)" % [latest.name, int(latest.get("day", 1))], func() -> void: _play(latest))
	_button(box, "New World", func() -> void: _show("new"))
	_button(box, "Load World", func() -> void: _show("load"))
	_button(box, "Settings", func() -> void: _show("settings"))
	if not OS.has_feature("ios"):
		_button(box, "Quit", func() -> void: get_tree().quit())


func _latest_playable() -> Dictionary:
	for w in GameState.list_worlds():
		if not w.get("lost", false) and w.id != "quickplay":
			return w
	return {}


# --- New world -----------------------------------------------------------------

func _build_new_world() -> void:
	var box := _screen("new", "NEW WORLD")
	_name_edit = LineEdit.new()
	_name_edit.text = "World %d" % (GameState.list_worlds().size() + 1)
	_row(box, "Name", _name_edit)
	_size_opt = OptionButton.new()
	for s in [8192.0, 16384.0, 32768.0]:
		_size_opt.add_item(GameState.SIZE_NAMES[s])
	_row(box, "Map size", _size_opt)
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(randi() % 1000000)
	_seed_edit.placeholder_text = "Random"
	_row(box, "Seed", _seed_edit)
	_diff_opt = OptionButton.new()
	for d in GameState.DIFFICULTIES:
		_diff_opt.add_item(d.name)
	_diff_opt.select(1)
	_row(box, "Difficulty", _diff_opt)
	_rule_opt = OptionButton.new()
	for r in GameState.DEATH_RULE_NAMES:
		_rule_opt.add_item(r)
	_row(box, "When you die", _rule_opt)
	var hint := Label.new()
	hint.text = "Death rule can't be changed later. Permadeath: the cure is the only way back."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
	box.add_child(hint)
	_button(box, "Create World", _create)
	_button(box, "Back", func() -> void: _show("home"))


func _create() -> void:
	var sizes := [8192.0, 16384.0, 32768.0]
	var seed_text := _seed_edit.text.strip_edges()
	var seed_value := int(seed_text) if seed_text.is_valid_int() else (seed_text.hash() if seed_text != "" else randi())
	var meta := GameState.create_world(_name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "World",
			sizes[_size_opt.selected], seed_value, _diff_opt.selected, _rule_opt.selected)
	_play(meta)


# --- Load ----------------------------------------------------------------------

func _build_load() -> void:
	var box := _screen("load", "YOUR WORLDS")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_world_list = VBoxContainer.new()
	_world_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_world_list)
	_button(box, "Back", func() -> void: _show("home"))


func _refresh_worlds() -> void:
	for c in _world_list.get_children():
		c.queue_free()
	var worlds := GameState.list_worlds()
	if worlds.is_empty():
		var l := Label.new()
		l.text = "No worlds yet."
		_world_list.add_child(l)
		return
	for w in worlds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var info := Label.new()
		var lost: bool = w.get("lost", false)
		info.text = "%s%s\n%s  -  %s  -  %s  -  day %d, %d kills" % [w.name, "  (LOST)" if lost else "",
				GameState.SIZE_NAMES.get(float(w.size), "?"), GameState.DIFFICULTIES[int(w.get("difficulty", 1))].name,
				GameState.DEATH_RULE_NAMES[int(w.get("death_rule", 0))], int(w.get("day", 1)), int(w.get("kills", 0))]
		info.add_theme_font_size_override("font_size", 18)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if lost:
			info.add_theme_color_override("font_color", Color(0.7, 0.45, 0.4))
		row.add_child(info)
		if not lost:
			var play := Button.new()
			play.text = "Play"
			play.pressed.connect(func() -> void: _play(w))
			row.add_child(play)
		var del := Button.new()
		del.text = "Delete"
		del.pressed.connect(func() -> void:
			GameState.delete_world(w.id)
			_refresh_worlds())
		row.add_child(del)
		_world_list.add_child(row)


# --- Settings ------------------------------------------------------------------

func _build_settings() -> void:
	var box := _screen("settings", "SETTINGS")
	_quality_btn = _button(box, "", func() -> void:
		GameState.set_quality((GameState.quality + 1) % 3)
		_update_quality())
	_update_quality()
	_button(box, "Back", func() -> void: _show("home"))


func _update_quality() -> void:
	_quality_btn.text = "Graphics: %s" % GameState.preset().name


func _play(meta: Dictionary) -> void:
	GameState.start_world(meta)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
