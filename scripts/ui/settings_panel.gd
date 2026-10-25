class_name SettingsPanel
extends CanvasLayer
## Settings, from the main menu or the pause menu: graphics, field of view,
## volumes, look sensitivity, inverted look, aim assist, the HUD style,
## tips, and remapping every control (a key and a gamepad button each).
## Saved at once (GameState.settings).

signal closed

var _bg: ColorRect
var _list: VBoxContainer
var _tab := "Game"
var _tabs: HBoxContainer
var _waiting := "" # Action waiting for a key / button to bind.
var _wait_label: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_bg = ColorRect.new()
	_bg.color = Color(0.025, 0.028, 0.032, 0.97)
	add_child(_bg)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 20
	root.offset_bottom = -20
	root.add_theme_constant_override("separation", 10)
	_bg.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := MenuTheme.heading("Settings", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var done_btn := _button("Done", close, 140)
	MenuTheme.primary(done_btn)
	top.add_child(done_btn)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	root.add_child(_tabs)
	for t in ["Game", "Video", "Audio", "Controls"]:
		_tabs.add_child(_button(t, func() -> void:
			_tab = t
			_rebuild(), 150))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_wait_label = Label.new()
	_wait_label.add_theme_font_size_override("font_size", 18)
	_wait_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	root.add_child(_wait_label)


func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	visible = false
	_waiting = ""
	closed.emit()


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for b: Button in _tabs.get_children():
		b.toggle_mode = true
		b.set_pressed_no_signal(b.text == _tab)
	var st := GameState.settings
	match _tab:
		"Game":
			_choice("Aim assist (gamepad)", ["Off", "Normal", "Strong"], int(float(st.aim_assist)), func(i: int) -> void: _set_opt("aim_assist", float(i)))
			_choice("HUD", ["Always show bars", "Minimal (only when something's wrong)"], 0 if st.hud == "bars" else 1,
				func(i: int) -> void: _set_opt("hud", "bars" if i == 0 else "minimal"))
			_choice("Tips", ["On", "Off"], 0 if st.hints else 1, func(i: int) -> void: _set_opt("hints", i == 0))
			var reset := _button("Show all tips again", func() -> void:
				GameState.hints_seen = {}
				GameState.save_settings()
				GameState.notify("Tips will show again"), 320)
			_list.add_child(reset)
		"Video":
			_choice("Graphics", ["Low", "Medium", "High"], GameState.quality, func(i: int) -> void: GameState.set_quality(i))
			_slider("Field of view", 60.0, 100.0, float(st.fov), func(v: float) -> void: _set_opt("fov", v), "%d°")
		"Audio":
			for pair in [["Master volume", "vol_master"], ["Effects", "vol_sfx"], ["Ambience", "vol_ambience"], ["Music", "vol_music"]]:
				var key: String = pair[1]
				_slider(pair[0], 0.0, 1.0, float(st[key]), func(v: float) -> void:
					_set_opt(key, v)
					Sound.apply_volumes(), "%d%%", 100.0)
		"Controls":
			_slider("Look sensitivity", 0.3, 2.5, float(st.sens), func(v: float) -> void: _set_opt("sens", v), "%.1fx", 1.0)
			_choice("Invert look up/down", ["No", "Yes"], 1 if st.invert_y else 0, func(i: int) -> void: _set_opt("invert_y", i == 1))
			for a in GameState.REMAPPABLE:
				_bind_row(a)
			_list.add_child(_button("Reset all controls", func() -> void:
				GameState.reset_binds()
				_rebuild(), 320))
	var first := _first_button(_list)
	if first:
		MenuTheme.focus_later(first)


func _first_button(n: Node) -> Control:
	for c in n.get_children():
		if c is Button or c is HSlider or c is OptionButton:
			return c
		var f := _first_button(c)
		if f:
			return f
	return null


func _set_opt(key: String, value: Variant) -> void:
	GameState.settings[key] = value
	GameState.save_settings()


func _row(label_text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 340
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", MenuTheme.TEXT.darkened(0.08))
	h.add_child(l)
	_list.add_child(h)
	return h


func _choice(label_text: String, options: Array, selected: int, cb: Callable) -> void:
	var h := _row(label_text)
	var o := OptionButton.new()
	for t in options:
		o.add_item(t)
	o.select(clampi(selected, 0, options.size() - 1))
	o.custom_minimum_size = Vector2(420, 48)
	o.add_theme_font_size_override("font_size", 18)
	o.item_selected.connect(cb)
	h.add_child(o)


func _slider(label_text: String, lo: float, hi: float, value: float, cb: Callable, fmt: String, scale := 1.0) -> void:
	var h := _row(label_text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 50.0
	s.value = value
	s.custom_minimum_size = Vector2(320, 40)
	h.add_child(s)
	var v := Label.new()
	v.text = fmt % (value * scale)
	v.add_theme_font_size_override("font_size", 18)
	h.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % (x * scale)
		cb.call(x))


func _bind_row(action: String) -> void:
	var h := _row(GameState.REMAPPABLE[action])
	var key := ""
	var pad := ""
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and key == "":
			key = OS.get_keycode_string((e as InputEventKey).keycode if (e as InputEventKey).keycode != 0 else (e as InputEventKey).physical_keycode)
		elif e is InputEventMouseButton and key == "":
			key = "Mouse %d" % (e as InputEventMouseButton).button_index
		elif e is InputEventJoypadButton and pad == "":
			var bi := (e as InputEventJoypadButton).button_index
			pad = ["A", "B", "X", "Y", "View / Back", "Guide", "Start / Menu", "L3", "R3", "LB", "RB", "D-pad up", "D-pad down",
				"D-pad left", "D-pad right", "Share"][bi] if bi < 16 else "Button %d" % bi
		elif e is InputEventJoypadMotion and pad == "":
			pad = "Stick / trigger"
	var b := _button(key if key != "" else "-", func() -> void: _start_wait(action, "key"), 200)
	h.add_child(b)
	var p := _button(pad if pad != "" else "-", func() -> void: _start_wait(action, "pad"), 200)
	h.add_child(p)


func _start_wait(action: String, _kind: String) -> void:
	_waiting = action
	_wait_label.text = "Press a key or gamepad button for \"%s\" (Esc cancels)" % GameState.REMAPPABLE[action]


func _input(event: InputEvent) -> void:
	if not visible or _waiting == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if (event as InputEventKey).keycode != KEY_ESCAPE:
			GameState.bind(_waiting, event)
		_waiting = ""
		_wait_label.text = ""
		_rebuild.call_deferred()
	elif event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		GameState.bind(_waiting, event)
		_waiting = ""
		_wait_label.text = ""
		_rebuild.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if visible and _waiting == "" and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()


func _button(text: String, cb: Callable, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 48)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b
