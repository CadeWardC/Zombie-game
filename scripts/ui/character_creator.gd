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
var _bg_title: Label
var _bg_info: Label
var _bg_tags: HFlowContainer
var _trait_info: Label
var _points: Label
var _start: Button
var _model: Node3D
var _body: MeshInstance3D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MenuTheme.make(17)
	character = Character.random(randi())
	var bg := ColorRect.new()
	bg.color = MenuTheme.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)
	# Header: title on the left, points on the right.
	var head := HBoxContainer.new()
	outer.add_child(head)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(MenuTheme.heading("New survivor", 13, MenuTheme.ACCENT_HI))
	tv.add_child(MenuTheme.heading(title, 30))
	var pts_box := VBoxContainer.new()
	pts_box.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(pts_box)
	pts_box.add_child(MenuTheme.heading("Trait points", 12, MenuTheme.DIM))
	_points = MenuTheme.heading("0", 30)
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pts_box.add_child(_points)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	outer.add_child(cols)
	_build_look(cols)
	_build_backgrounds(cols)
	_build_traits(cols)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	outer.add_child(bottom)
	if show_back:
		_btn(bottom, "Back", func() -> void: back.emit())
	_btn(bottom, "Randomise", func() -> void:
		character = Character.random(randi())
		_name.text = character.name
		_refresh())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	_start = _btn(bottom, "Start surviving", _finish)
	_start.custom_minimum_size.x = 280
	MenuTheme.primary(_start)
	_refresh()
	_start.grab_focus.call_deferred()


func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 52)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _column(parent: Node, heading: String, ratio: float) -> VBoxContainer:
	var p := MenuTheme.card()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = ratio
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(MenuTheme.section(heading))
	return v


# --- Appearance ------------------------------------------------------------------

func _build_look(cols: HBoxContainer) -> void:
	var v := _column(cols, "Appearance", 0.9)
	_name = LineEdit.new()
	_name.text = character.name
	_name.placeholder_text = "Name"
	_name.max_length = 20
	_name.custom_minimum_size.y = 42
	_name.add_theme_font_override("font", MenuTheme.bold_font())
	_name.text_changed.connect(func(t: String) -> void: character.name = t.strip_edges())
	v.add_child(_name)
	# Turning 3D preview in its own little world, on a lit floor disc.
	var stage := Panel.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(0, 150)
	var sb := MenuTheme.box(Color(0.05, 0.055, 0.06), 8, MenuTheme.LINE, 1, 0.0)
	stage.add_theme_stylebox_override("panel", sb)
	v.add_child(stage)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 26.0
	cam.position = Vector3(0, 0.95, 5.4)
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 2.2, -1.5)
	rim.light_color = Color(0.95, 0.55, 0.4)
	rim.light_energy = 1.5
	rim.omni_range = 5.0
	vp.add_child(rim)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.56, 0.6)
	vp.add_child(env)
	var floor_disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.7
	cyl.height = 0.04
	floor_disc.mesh = cyl
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.16, 0.17, 0.18)
	floor_disc.material_override = fm
	floor_disc.position.y = -0.02
	vp.add_child(floor_disc)
	_model = ZombieModel.instantiate(0)
	vp.add_child(_model)
	_body = _model.get_node("Skeleton3D/Body")
	# The shared vertex-colour material may not exist yet on the main menu.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	_body.material_override = mat
	var ap: AnimationPlayer = _model.get_node("AnimationPlayer")
	if ap.has_animation("h_idle"):
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		ap.play("h_idle")
	for row: Array in [["build", "Body", Character.BUILDS.size()], ["skin", "Skin", Character.SKIN_TONES.size()],
			["hair", "Hair", Character.HAIR_STYLES.size()], ["hair_col", "Hair colour", Character.HAIR_COLORS.size()],
			["beard", "Facial hair", Character.BEARDS.size()]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		var key: String = row[0]
		var n: int = row[2]
		var l := Label.new()
		l.text = row[1]
		l.custom_minimum_size.x = 96
		l.add_theme_color_override("font_color", MenuTheme.DIM.lightened(0.15))
		l.add_theme_font_size_override("font_size", 15)
		h.add_child(l)
		_small(h, "<", func() -> void: _cycle(key, -1, n))
		var val := Label.new()
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.add_theme_font_override("font", MenuTheme.bold_font())
		val.add_theme_font_size_override("font_size", 15)
		h.add_child(val)
		_look_labels[key] = val
		_small(h, ">", func() -> void: _cycle(key, 1, n))
		v.add_child(h)


func _small(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(40, 34)
	b.pressed.connect(cb)
	parent.add_child(b)


func _cycle(key: String, step: int, n: int) -> void:
	character.look[key] = posmod(int(character.look[key]) + step, n)
	_refresh()


# --- Background -------------------------------------------------------------------

func _build_backgrounds(cols: HBoxContainer) -> void:
	var v := _column(cols, "Background", 1.0)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for id: String in Character.BACKGROUNDS:
		var b := Button.new()
		b.text = Character.BACKGROUNDS[id].name
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(140, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			character.background = id
			character.apply_background()
			_refresh())
		grid.add_child(b)
		_bg_buttons[id] = b
	# What the chosen background brings.
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", MenuTheme.stripe_box(Color(0.07, 0.075, 0.08), MenuTheme.ACCENT, 6))
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(info)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 8)
	info.add_child(iv)
	_bg_title = MenuTheme.heading("", 17)
	iv.add_child(_bg_title)
	_bg_info = Label.new()
	_bg_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_bg_info.custom_minimum_size.x = 240
	_bg_info.add_theme_color_override("font_color", MenuTheme.DIM.lightened(0.2))
	_bg_info.add_theme_font_size_override("font_size", 15)
	iv.add_child(_bg_info)
	_bg_tags = HFlowContainer.new()
	_bg_tags.add_theme_constant_override("h_separation", 6)
	_bg_tags.add_theme_constant_override("v_separation", 6)
	iv.add_child(_bg_tags)


# --- Traits -------------------------------------------------------------------------

func _build_traits(cols: HBoxContainer) -> void:
	var v := _column(cols, "Traits", 1.3)
	var ids := Character.TRAITS.keys()
	# Good traits first, then bad ones.
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(Character.TRAITS[a].cost) > int(Character.TRAITS[b].cost))
	var grids := {}
	for good in [true, false]:
		var l := MenuTheme.heading("Strengths" if good else "Weaknesses", 12, MenuTheme.GOOD if good else MenuTheme.BAD)
		v.add_child(l)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 5)
		v.add_child(grid)
		grids[good] = grid
	for id: String in ids:
		var tr: Dictionary = Character.TRAITS[id]
		var good := int(tr.cost) > 0
		var b := Button.new()
		b.toggle_mode = true
		b.text = tr.name
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(170, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		var cost := Label.new()
		cost.text = "%s%d" % ["-" if good else "+", absi(int(tr.cost))]
		cost.add_theme_font_override("font", MenuTheme.bold_font())
		cost.add_theme_font_size_override("font_size", 14)
		cost.add_theme_color_override("font_color", MenuTheme.GOOD.lightened(0.2) if good else MenuTheme.BAD.lightened(0.2))
		cost.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		cost.offset_left = -34
		cost.offset_right = -10
		cost.offset_top = -10
		cost.offset_bottom = 10
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cost)
		var info := "%s: %s" % [tr.name, tr.desc]
		b.pressed.connect(func() -> void:
			character.toggle_trait(id)
			_trait_info.text = info
			_refresh())
		b.focus_entered.connect(func() -> void: _trait_info.text = info)
		b.mouse_entered.connect(func() -> void: _trait_info.text = info)
		(grids[good] as GridContainer).add_child(b)
		_trait_buttons[id] = b
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	_trait_info = Label.new()
	_trait_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_trait_info.custom_minimum_size.x = 300
	_trait_info.custom_minimum_size.y = 40
	_trait_info.add_theme_color_override("font_color", MenuTheme.DIM.lightened(0.15))
	_trait_info.add_theme_font_size_override("font_size", 14)
	_trait_info.text = "Strengths cost points; weaknesses give you more."
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
	_bg_title.text = str(b.name).to_upper()
	_bg_info.text = b.desc
	for c in _bg_tags.get_children():
		c.queue_free()
	for s in b.skills:
		_bg_tags.add_child(MenuTheme.tag("%s %d" % [str(s).capitalize(), int(b.skills[s])], MenuTheme.COLD))
	var pts := int(b.points)
	_bg_tags.add_child(MenuTheme.tag("%s%d trait points" % ["+" if pts >= 0 else "", pts], MenuTheme.WARN))
	for id in _trait_buttons:
		var btn: Button = _trait_buttons[id]
		btn.button_pressed = id in character.traits
		btn.disabled = not (id in character.traits) and not character.can_add_trait(id)
	var left := character.points_left()
	_points.text = "%d" % left
	_points.add_theme_color_override("font_color", MenuTheme.BAD if left < 0 else (MenuTheme.GOOD if left > 0 else MenuTheme.TEXT))
	_start.disabled = left < 0
	_start.text = "Start surviving" if left >= 0 else "Too many strengths"
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
