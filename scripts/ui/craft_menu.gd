class_name CraftMenu
extends CanvasLayer
## Crafting, building and skills in one menu (opened from the inventory, or
## with K / R3). Tabs along the top; each recipe is a row with what it needs,
## greyed out until you have it. Buttons take focus, so the D-pad / stick and
## A work, as do touch and the mouse.
##
## Build: pick a structure, then place it in the world (see Player build mode).

var player: Player
var game: Node # main.gd, for stations_near().

var _bg: ColorRect
var _tabs: HBoxContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _tab := "Weapons"
var _opened_frame := -1


func _ready() -> void:
	layer = 9
	visible = false
	_bg = ColorRect.new()
	_bg.color = Color(0.03, 0.035, 0.035, 0.94)
	add_child(_bg)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 10)
	_bg.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var close_btn := _button("Close", close, 140)
	top.add_child(close_btn)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	root.add_child(_tabs)
	for t in Recipes.CATS + ["Build", "Skills"]:
		_tabs.add_child(_button(t, _set_tab.bind(t), 0))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	GameState.inventory_changed.connect(func() -> void:
		if visible:
			_rebuild(false))


func is_open() -> bool:
	return visible


func open(tab := "") -> void:
	if tab != "":
		_tab = tab
	visible = true
	GameState.ui_open = true
	_opened_frame = Engine.get_process_frames()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild(true)


func close() -> void:
	visible = false
	GameState.ui_open = false
	if not GameState.uses_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("craft"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("shove") or event.is_action_pressed("throw_quick"):
		# RB / LB switch tabs.
		var all: Array = Recipes.CATS + ["Build", "Skills"]
		var i := all.find(_tab) + (1 if event.is_action_pressed("shove") else -1)
		get_viewport().set_input_as_handled()
		_set_tab(all[posmod(i, all.size())])


func _set_tab(t: String) -> void:
	_tab = t
	_rebuild(true)


func _stations() -> Array:
	return game.stations_near(player.global_position) if game and player else []


func _rebuild(focus: bool) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var focus_name: String = str(focused.name) if focused and _list.is_ancestor_of(focused) else ""
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for b: Button in _tabs.get_children():
		b.modulate = Color(1, 0.85, 0.5) if b.text == _tab else Color(1, 1, 1, 0.75)
	var st := _stations()
	_title.text = "CRAFTING" if _tab != "Build" and _tab != "Skills" else _tab.to_upper()
	if _tab in Recipes.CATS:
		var where: PackedStringArray = []
		if "workbench" in st:
			where.append("at a workbench")
		if "fire" in st:
			where.append("by a fire")
		_title.text += ("   (%s)" % ", ".join(where)) if not where.is_empty() else ""
	var first: Control = null
	match _tab:
		"Skills":
			for s in Character.SKILLS:
				var ch := GameState.character
				var row := _row("%s   level %d%s" % [Character.SKILL_NAMES[s], ch.skill(s), "" if ch.skill(s) < Character.MAX_LEVEL else " (max)"],
					_skill_hint(s), "", Callable(), true, ch.xp_progress(s))
				row.name = s
				first = first if first else row
		"Build":
			for id in Structures.LIST:
				var d: Dictionary = Structures.LIST[id]
				var miss := Structures.missing(d)
				var row := _row(d.name, Structures.needs_text(d) + ("\n" + d.desc if d.has("desc") else ""),
					"Build" if miss.is_empty() else "Need: " + ", ".join(miss), _build.bind(id), miss.is_empty())
				row.name = id
				first = first if first else row
		_:
			for id in Recipes.LIST:
				var r: Dictionary = Recipes.LIST[id]
				if r.cat != _tab:
					continue
				var miss := Recipes.missing(r, st)
				var out_name := ItemDB.item_name(r.out[0]) + (" x%d" % int(r.out[1]) if int(r.out[1]) > 1 else "")
				var row := _row("%s  ->  %s" % [r.name, out_name], Recipes.needs_text(r),
					"Craft" if miss.is_empty() else "Need: " + ", ".join(miss), _craft.bind(id), miss.is_empty())
				row.name = id
				first = first if first else row
	if focus or focus_name != "":
		var target: Control = _list.get_node_or_null(NodePath(focus_name)) if focus_name != "" else null
		var btn := _row_button(target if target else first)
		if btn:
			btn.grab_focus.call_deferred()


func _row_button(row: Control) -> Button:
	if row == null:
		return null
	for c in row.find_children("*", "Button", true, false):
		return c
	return null


func _skill_hint(s: String) -> String:
	return {"aiming": "Shoot zombies. Steadier aim.", "melee": "Hit zombies. Harder hits.",
		"first_aid": "Treat wounds. Faster healing, less bleeding.", "stealth": "Sneak past zombies, silent takedowns. Quieter.",
		"fitness": "Sprint. More stamina.", "strength": "Heavy weapons and loads. Carry more.",
		"mechanics": "Repair and hotwire vehicles, metal crafting.", "carpentry": "Build and craft with wood. Sturdier structures.",
		"farming": "Plant and harvest. Bigger crops, faster growth.", "cooking": "Cook meals. More filling food.",
		"foraging": "Gather berries and mushrooms. Find more, spot poisonous ones.",
		"piloting": "Fly. Safer landings."}.get(s, "")


## One recipe / structure / skill row: a title, details, and an action
## button (or a progress bar for skills).
func _row(title: String, details: String, action: String, cb: Callable, ok: bool, progress := -1.0) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.11, 0.95)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	_list.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 20)
	t.modulate = Color.WHITE if ok else Color(0.7, 0.7, 0.68)
	v.add_child(t)
	var dl := Label.new()
	dl.text = details
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD
	dl.add_theme_font_size_override("font_size", 14)
	dl.modulate = Color(0.75, 0.78, 0.74)
	v.add_child(dl)
	if progress >= 0.0:
		var bar := ProgressBar.new()
		bar.value = progress * 100.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(220, 14)
		v.add_child(bar)
		# A focusable (do-nothing) button so the pad can scroll the list.
		var b := _button("", func() -> void: pass, 1)
		b.flat = true
		h.add_child(b)
	elif action != "":
		var b := _button(action, cb, 200)
		b.disabled = not ok
		b.focus_mode = Control.FOCUS_ALL # Missing things still get focus, to read what's needed.
		b.clip_text = true
		h.add_child(b)
	return panel


func _button(text: String, cb: Callable, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 50)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b


func _craft(id: String) -> void:
	var made := Recipes.craft(id, _stations(), player.global_position)
	if made.is_empty():
		return
	GameState.make_noise(player.global_position, 3.0)
	GameState.notify("Made %s" % ItemDB.item_name(made.id))


func _build(id: String) -> void:
	close()
	player.start_build(id)
