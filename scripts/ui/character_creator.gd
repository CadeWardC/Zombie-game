class_name CharacterCreator
extends Control
## Character creation: name, appearance (with a turning 3D preview wearing
## the background's clothes), background and traits. Good traits cost
## points, bad traits give them; the total can't go below zero. Works with
## touch, mouse and gamepad (every control is a focusable button).
## Used by the main menu (new worlds) and in game ("new character" worlds).

signal done(character: Character)
signal back

var title := "YOUR SURVIVOR"
var show_back := false
var character := Character.new()

var _name: LineEdit
var _look_labels := {}
var _bg_buttons := {}
var _trait_buttons := {}
var _bg_info: Label
var _trait_info: Label
var _points: Label
var _start: Button
var _model: Node3D
var _body: MeshInstance3D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MenuTheme.make(18)
	character = Character.random(randi())
	var bg := ColorRect.new()
	bg.color = MenuTheme.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 28)
	head.add_theme_color_override("font_color", MenuTheme.TEXT)
	outer.add_child(head)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	outer.add_child(cols)
	_build_look(cols)
	_build_backgrounds(cols)
	_build_traits(cols)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	outer.add_child(bottom)
	if show_back:
		_btn(bottom, "Back", func() -> void: back.emit())
	_btn(bottom, "Randomise", func() -> void:
		character = Character.random(randi())
		_name.text = character.name
		_refresh())
	_points = Label.new()
	_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_points.add_theme_font_size_override("font_size", 22)
	bottom.add_child(_points)
	_start = _btn(bottom, "Start Surviving", _finish)
	_start.custom_minimum_size.x = 260
	_refresh()
	_start.grab_focus.call_deferred()


func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _column(parent: Node, heading: String, width: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size.x = width
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var l := Label.new()
	l.text = heading
	l.add_theme_color_override("font_color", MenuTheme.TEXT)
	l.add_theme_font_size_override("font_size", 22)
	v.add_child(l)
	return v


# --- Appearance ------------------------------------------------------------------

func _build_look(cols: HBoxContainer) -> void:
	var v := _column(cols, "Appearance", 300)
	_name = LineEdit.new()
	_name.text = character.name
	_name.placeholder_text = "Name"
	_name.max_length = 20
	_name.custom_minimum_size.y = 40
	_name.text_changed.connect(func(t: String) -> void: character.name = t.strip_edges())
	v.add_child(_name)
	for row: Array in [["build", "Body", Character.BUILDS.size()], ["skin", "Skin", Character.SKIN_TONES.size()],
			["hair", "Hair", Character.HAIR_STYLES.size()], ["hair_col", "Hair colour", Character.HAIR_COLORS.size()],
			["beard", "Facial hair", Character.BEARDS.size()]]:
		var h := HBoxContainer.new()
		var key: String = row[0]
		var n: int = row[2]
		var l := Label.new()
		l.text = row[1]
		l.custom_minimum_size.x = 100
		h.add_child(l)
		h.add_theme_constant_override("separation", 4)
		_small(h, "<", func() -> void: _cycle(key, -1, n))
		var val := Label.new()
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(val)
		_look_labels[key] = val
		_small(h, ">", func() -> void: _cycle(key, 1, n))
		v.add_child(h)
	# Turning 3D preview in its own little world.
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(240, 150)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	svc.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 0.98, 4.2)
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 25, 0)
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
	vp.add_child(env)
	_model = ZombieModel.instantiate(0)
	vp.add_child(_model)
	_body = _model.get_node("Skeleton3D/Body")


func _small(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(44, 36)
	b.pressed.connect(cb)
	parent.add_child(b)


func _cycle(key: String, step: int, n: int) -> void:
	character.look[key] = posmod(int(character.look[key]) + step, n)
	_refresh()


# --- Background -------------------------------------------------------------------

func _build_backgrounds(cols: HBoxContainer) -> void:
	var v := _column(cols, "Background", 330)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for id: String in Character.BACKGROUNDS:
		var b := Button.new()
		b.text = Character.BACKGROUNDS[id].name
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			character.background = id
			character.apply_background()
			_refresh())
		grid.add_child(b)
		_bg_buttons[id] = b
	_bg_info = Label.new()
	_bg_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_bg_info.custom_minimum_size.x = 290
	_bg_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bg_info.add_theme_color_override("font_color", MenuTheme.DIM)
	v.add_child(_bg_info)


# --- Traits -------------------------------------------------------------------------

func _build_traits(cols: HBoxContainer) -> void:
	var v := _column(cols, "Traits", 420)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 5)
	v.add_child(grid)
	var ids := Character.TRAITS.keys()
	# Good traits first, then bad ones.
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(Character.TRAITS[a].cost) > int(Character.TRAITS[b].cost))
	for id: String in ids:
		var tr: Dictionary = Character.TRAITS[id]
		var b := Button.new()
		b.toggle_mode = true
		b.text = "%s  %s%d" % [tr.name, "-" if int(tr.cost) > 0 else "+", absi(int(tr.cost))]
		b.custom_minimum_size = Vector2(186, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", Color(0.65, 0.9, 0.65) if int(tr.cost) > 0 else Color(0.95, 0.6, 0.55))
		b.pressed.connect(func() -> void:
			character.toggle_trait(id)
			_trait_info.text = "%s: %s" % [tr.name, tr.desc]
			_refresh())
		b.focus_entered.connect(func() -> void: _trait_info.text = "%s: %s" % [tr.name, tr.desc])
		b.mouse_entered.connect(func() -> void: _trait_info.text = "%s: %s" % [tr.name, tr.desc])
		grid.add_child(b)
		_trait_buttons[id] = b
	_trait_info = Label.new()
	_trait_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_trait_info.custom_minimum_size.x = 380
	_trait_info.custom_minimum_size.y = 44
	_trait_info.add_theme_color_override("font_color", MenuTheme.DIM)
	_trait_info.text = "Good traits cost points; bad traits give points."
	v.add_child(_trait_info)


# --- State ------------------------------------------------------------------------------

func _refresh() -> void:
	for key in _look_labels:
		var i := int(character.look[key])
		match key:
			"build":
				_look_labels[key].text = Character.BUILDS[i]
			"hair":
				_look_labels[key].text = Character.HAIR_STYLES[i]
			"beard":
				_look_labels[key].text = Character.BEARDS[i]
			_:
				_look_labels[key].text = "%d" % (i + 1)
	for id in _bg_buttons:
		_bg_buttons[id].button_pressed = id == character.background
	var b: Dictionary = Character.BACKGROUNDS[character.background]
	var skills: PackedStringArray = []
	for s in b.skills:
		skills.append("%s %d" % [str(s).capitalize(), int(b.skills[s])])
	var pts := int(b.points)
	_bg_info.text = "%s\n\nSkills: %s\nTrait points: %s%d" % [b.desc, ", ".join(skills) if not skills.is_empty() else "none",
			"+" if pts >= 0 else "", pts]
	for id in _trait_buttons:
		var btn: Button = _trait_buttons[id]
		btn.button_pressed = id in character.traits
		btn.disabled = not (id in character.traits) and not character.can_add_trait(id)
	var left := character.points_left()
	_points.text = "Points left: %d" % left
	_points.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3) if left < 0 else MenuTheme.TEXT)
	_start.disabled = left < 0
	# Dress the preview in the background's clothes.
	var equip := {}
	for c in b.clothes:
		var it := ItemDB.make(c[0])
		it.v = int(c[1])
		equip[ItemDB.slot_for(c[0])] = it
	_body.mesh = ZombieModel.mesh_for(character.body_look(equip, false))


func _process(delta: float) -> void:
	if _model:
		_model.rotate_y(delta * 0.5)


func _finish() -> void:
	if character.points_left() < 0:
		return
	if character.name.strip_edges() == "":
		character.name = "Survivor"
	done.emit(character)
