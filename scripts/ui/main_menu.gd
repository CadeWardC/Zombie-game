extends Control
## Main menu: continue, create a world (then its survivor), load / delete
## worlds, join a friend's game on the same Wi-Fi, memorials of lost worlds,
## settings. Built in code; fully usable
## with touch, mouse or gamepad (focus follows the D-pad / stick).

const BG := MenuTheme.BG
const ACCENT := MenuTheme.ACCENT

var _screens := {}
var _name_edit: LineEdit
var _seed_edit: LineEdit
var _size_opt: OptionButton
var _diff_opt: OptionButton
var _rule_opt: OptionButton
var _speed_opt: OptionButton
var _infect_opt: OptionButton
var _memorial_title: Label
var _memorial_info: Label
var _memorial_map: MapView
var _pending_world := {}
var _pvp_opt: OptionButton
var _season_opt: OptionButton
var _util_opt: OptionButton
var _games_list: VBoxContainer
var _join_status: Label
var _home_note: Label
var _world_list: VBoxContainer
var _quality_btn: Button
var _shade: ColorRect


func _ready() -> void:
	Sound.game = null
	Sound.music(true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MenuTheme.make()
	var bg := ColorRect.new()
	bg.color = BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	# A dark band behind the menu column on the left keeps text readable.
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.022, 0.025, 0.55)
	shade.anchor_bottom = 1.0
	shade.offset_right = 500
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_shade = shade
	_build_home()
	_build_new_world()
	_build_load()
	_build_memorial()
	_build_join()
	_build_settings()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show("home")


func _screen(screen_name: String, title: String) -> VBoxContainer:
	if screen_name == "home":
		# The title screen: a column on the left over the backdrop.
		var m := MarginContainer.new()
		add_child(m)
		m.anchor_bottom = 1.0
		m.offset_right = 500
		m.add_theme_constant_override("margin_left", 64)
		m.add_theme_constant_override("margin_right", 40)
		m.add_theme_constant_override("margin_top", 20)
		m.add_theme_constant_override("margin_bottom", 20)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 7)
		m.add_child(col)
		col.add_child(MenuTheme.heading("A survival game", 14, MenuTheme.ACCENT_HI))
		var t1 := MenuTheme.heading("Zombie", 54)
		col.add_child(t1)
		var t2 := MenuTheme.heading("Survival", 54, MenuTheme.ACCENT_HI)
		t2.offset_top = -10
		col.add_child(t2)
		_screens[screen_name] = m
		return col
	# Other screens: a card in the middle.
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.06, 0.065, 0.07, 0.94), 12, MenuTheme.LINE, 1, 24.0))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(MenuTheme.heading(title, 30))
	var bar := ColorRect.new()
	bar.color = MenuTheme.ACCENT
	bar.custom_minimum_size = Vector2(48, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(bar)
	_screens[screen_name] = center
	return box


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## A title-screen button: left-aligned, bold.
func _home_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := _button(parent, text, cb)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", MenuTheme.bold_font())
	b.custom_minimum_size = Vector2(380, 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return b


func _row(parent: Node, label: String, control: Control) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(170, 0)
	l.add_theme_color_override("font_color", MenuTheme.DIM.lightened(0.2))
	l.add_theme_font_size_override("font_size", 17)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.y = 48
	h.add_child(control)
	parent.add_child(h)


func _show(screen_name: String) -> void:
	for k in _screens:
		_screens[k].visible = k == screen_name
	_shade.visible = screen_name == "home"
	if screen_name == "load":
		_refresh_worlds()
	if screen_name == "join":
		_refresh_games.call_deferred()
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
	sub.add_theme_color_override("font_color", MenuTheme.DIM)
	sub.add_theme_font_size_override("font_size", 17)
	box.add_child(sub)
	_home_note = Label.new()
	_home_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_home_note.custom_minimum_size.x = 380
	_home_note.add_theme_color_override("font_color", MenuTheme.BAD.lightened(0.2))
	_home_note.text = GameState.menu_message
	_home_note.visible = GameState.menu_message != ""
	GameState.menu_message = ""
	box.add_child(_home_note)
	var latest := _latest_playable()
	if not latest.is_empty():
		var c := _home_button(box, "Continue   %s  ·  day %d" % [latest.name, int(latest.get("day", 1))], func() -> void: _play(latest))
		MenuTheme.primary(c)
		c.add_theme_font_override("font", MenuTheme.bold_font())
	var nw := _home_button(box, "New world", func() -> void: _show("new"))
	if latest.is_empty():
		MenuTheme.primary(nw)
	_home_button(box, "Load world", func() -> void: _show("load"))
	_home_button(box, "Join a game on Wi-Fi", func() -> void:
		Net.start_discovery()
		_show("join"))
	_home_button(box, "Tutorial", _start_tutorial)
	_home_button(box, "Settings", func() -> void:
		var sp := SettingsPanel.new()
		add_child(sp)
		sp.closed.connect(func() -> void:
			sp.queue_free()
			_show("home"))
		sp.open())
	if not OS.has_feature("ios"):
		_home_button(box, "Quit", func() -> void: get_tree().quit())


func _latest_playable() -> Dictionary:
	for w in GameState.list_worlds():
		if not w.get("lost", false) and not w.id in ["quickplay", "tutorial"]:
			return w
	return {}


# --- New world -----------------------------------------------------------------

func _build_new_world() -> void:
	var outer := _screen("new", "NEW WORLD")
	outer.custom_minimum_size = Vector2(980, 0)
	var box := GridContainer.new()
	box.columns = 2
	box.add_theme_constant_override("h_separation", 24)
	box.add_theme_constant_override("v_separation", 10)
	outer.add_child(box)
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
	_speed_opt = OptionButton.new()
	for n in GameState.ZOMBIE_SPEEDS:
		_speed_opt.add_item(n)
	_speed_opt.select(1)
	_row(box, "Zombie speed", _speed_opt)
	_infect_opt = OptionButton.new()
	for c in GameState.INFECTION_CHANCES:
		_infect_opt.add_item("%d%% per bite" % int(c * 100.0))
	_infect_opt.select(2)
	_row(box, "Infection", _infect_opt)
	_pvp_opt = OptionButton.new()
	_pvp_opt.add_item("Off")
	_pvp_opt.add_item("On")
	_row(box, "Player vs player", _pvp_opt)
	_season_opt = OptionButton.new()
	for n in ["1 week", "2 weeks", "4 weeks"]:
		_season_opt.add_item(n)
	_season_opt.select(1)
	_row(box, "Season length", _season_opt)
	_util_opt = OptionButton.new()
	for n in ["Day 1", "After ~2 weeks", "Never"]:
		_util_opt.add_item(n)
	_util_opt.select(1)
	_row(box, "Power and water shut off", _util_opt)
	_diff_opt.item_selected.connect(func(i: int) -> void:
		_infect_opt.select(GameState.INFECTION_CHANCES.find(GameState.DIFFICULTIES[i].infection)))
	var hint := Label.new()
	hint.text = "Death rule can't be changed later. Permadeath: the cure is the only way back."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
	outer.add_child(hint)
	MenuTheme.primary(_button(outer, "Create world", _create))
	_button(outer, "Back", func() -> void: _show("home"))


func _create() -> void:
	var sizes := [8192.0, 16384.0, 32768.0]
	var seed_text := _seed_edit.text.strip_edges()
	var seed_value := int(seed_text) if seed_text.is_valid_int() else (seed_text.hash() if seed_text != "" else randi())
	var meta := GameState.create_world(_name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "World",
			sizes[_size_opt.selected], seed_value, _diff_opt.selected, _rule_opt.selected, "",
			{"zspeed": _speed_opt.selected, "infection": GameState.INFECTION_CHANCES[_infect_opt.selected],
			"pvp": _pvp_opt.selected == 1, "season_days": [7, 14, 28][_season_opt.selected],
			"utilities": [0, 14, -1][_util_opt.selected]})
	# Next: who survives in it.
	_pending_world = meta
	for k in _screens:
		_screens[k].visible = false
	var cc := CharacterCreator.new()
	cc.show_back = true
	add_child(cc)
	cc.done.connect(func(c: Character) -> void:
		GameState.pending_character = c
		_play(_pending_world))
	cc.back.connect(func() -> void:
		GameState.delete_world(_pending_world.id)
		cc.queue_free()
		_show("new"))


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
		var card := MenuTheme.card()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
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
		else:
			var mem := Button.new()
			mem.text = "Memorial"
			mem.pressed.connect(func() -> void: _show_memorial(w))
			row.add_child(mem)
		var del := Button.new()
		del.text = "Delete"
		del.pressed.connect(func() -> void:
			GameState.delete_world(w.id)
			_refresh_worlds())
		row.add_child(del)
		_world_list.add_child(card)


# --- Memorial ------------------------------------------------------------------
# A lost world can't be played again; it's kept as a record of the survivor.

func _build_memorial() -> void:
	var box := _screen("memorial", "IN MEMORIAM")
	box.custom_minimum_size = Vector2(760, 0)
	_memorial_title = Label.new()
	_memorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_memorial_title.add_theme_font_size_override("font_size", 28)
	box.add_child(_memorial_title)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	box.add_child(h)
	_memorial_map = MapView.new()
	_memorial_map.custom_minimum_size = Vector2(360, 360)
	h.add_child(_memorial_map)
	_memorial_info = Label.new()
	_memorial_info.custom_minimum_size = Vector2(360, 0)
	_memorial_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_memorial_info.add_theme_font_size_override("font_size", 20)
	_memorial_info.add_theme_color_override("font_color", MenuTheme.DIM)
	h.add_child(_memorial_info)
	_button(box, "Back", func() -> void: _show("load"))


func _show_memorial(w: Dictionary) -> void:
	_memorial_title.text = "%s  -  %s" % [w.get("survivor", "A survivor"), w.name]
	var lines: PackedStringArray = []
	if w.has("background"):
		lines.append(str(w.background))
	lines.append("Survived %d day%s" % [int(w.get("day", 1)), "" if int(w.get("day", 1)) == 1 else "s"])
	lines.append("%d zombies killed" % int(w.get("kills", 0)))
	lines.append("Cause of death: %s" % w.get("cause", "unknown"))
	lines.append("Explored %.1f%% of the map" % (float(w.get("explored", 0.0)) * 100.0))
	lines.append("")
	lines.append("%s  -  %s" % [GameState.SIZE_NAMES.get(float(w.size), "?"), GameState.DIFFICULTIES[int(w.get("difficulty", 1))].name])
	if w.has("lost_at"):
		lines.append("Lost on %s" % Time.get_date_string_from_unix_time(int(w.lost_at)))
	_memorial_info.text = "\n".join(lines)
	_memorial_map.load_world(w)
	_show("memorial")


# --- Join ----------------------------------------------------------------------
# Games hosted by friends on the same Wi-Fi show up here by themselves.

func _build_join() -> void:
	var box := _screen("join", "JOIN A GAME")
	box.custom_minimum_size = Vector2(640, 0)
	_join_status = Label.new()
	_join_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_join_status.add_theme_color_override("font_color", MenuTheme.DIM)
	box.add_child(_join_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_games_list = VBoxContainer.new()
	_games_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_games_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_games_list)
	_button(box, "Back", func() -> void:
		Net.stop_discovery()
		if Net.is_client():
			Net.stop()
		_show("home"))
	Net.games_changed.connect(_refresh_games)
	Net.join_failed.connect(func(reason: String) -> void:
		_join_status.text = reason
		Net.start_discovery())
	Net.welcomed.connect(_on_welcomed)


func _refresh_games() -> void:
	if not _screens.join.visible:
		return
	for c in _games_list.get_children():
		c.queue_free()
	if Net.games.is_empty():
		_join_status.text = "Looking for games on your Wi-Fi...\nOn the host's device: pause, then Invite Friends."
		return
	_join_status.text = "Pick a game to join."
	for key in Net.games:
		var g: Dictionary = Net.games[key]
		var b := Button.new()
		b.text = "%s's game  -  %s\n%d / %d players  -  %s  -  PvP %s" % [g.name, g.world, int(g.players), int(g.max),
			GameState.DEATH_RULE_NAMES[int(g.get("rule", 0))], "on" if g.get("pvp", false) else "off"]
		b.custom_minimum_size = Vector2(0, 76)
		b.disabled = int(g.players) >= int(g.max)
		b.pressed.connect(func() -> void:
			_join_status.text = "Joining %s's game..." % g.name
			Net.join(str(g.ip), int(g.get("port", Net.PORT))))
		_games_list.add_child(b)


## The host sent its world. New to this world: make a survivor first.
func _on_welcomed(needs_character: bool) -> void:
	Net.stop_discovery()
	if not needs_character:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	for k in _screens:
		_screens[k].visible = false
	var cc := CharacterCreator.new()
	cc.title = "JOINING %s" % str(GameState.world.get("name", "")).to_upper()
	cc.show_back = true
	add_child(cc)
	cc.done.connect(func(c: Character) -> void:
		GameState.character = c
		GameState.give_starting_kit()
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	cc.back.connect(func() -> void:
		Net.stop()
		cc.queue_free()
		Net.start_discovery()
		_show("join"))


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


## A small guided start: a fixed world, a ready-made survivor, a checklist.
func _start_tutorial() -> void:
	GameState.delete_world("tutorial") # Always a fresh start.
	var meta := GameState.create_world("Tutorial", 8192.0, 777, 0, 0, "tutorial", {"tutorial": true})
	GameState.pending_character = Character.random(777)
	GameState.pending_character.name = "Rookie"
	_play(meta)


func _play(meta: Dictionary) -> void:
	GameState.start_world(meta)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
