class_name PauseMenu
extends CanvasLayer
## Pause menu: resume, map, inviting friends on the same Wi-Fi (who's
## playing), graphics quality, save, quit. In a multiplayer game the world
## keeps running while it's open.

signal save_requested
signal menu_requested

var player: Player
var _quality_btn: Button
var _map_layer: Control
var _map: MapView
var _map_info: Label
var _box: VBoxContainer
var _invite_btn: Button
var _save_btn: Button
var _quit_btn: Button
var _players_label: Label
var _first_btn: Button
var _opened_frame := -1
var _title: Label
var _sub: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.012, 0.015, 0.72)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# A column on the left, like the title screen.
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.05, 0.055, 0.06, 0.96), 0, MenuTheme.LINE, 0, 0.0))
	side.anchor_bottom = 1.0
	side.offset_right = 420
	bg.add_child(side)
	var m := MarginContainer.new()
	for k in ["left", "right"]:
		m.add_theme_constant_override("margin_" + k, 40)
	for k in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + k, 24)
	side.add_child(m)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	m.add_child(box)
	_box = box

	box.add_child(MenuTheme.heading("Game paused", 13, MenuTheme.ACCENT_HI))
	_title = MenuTheme.heading("", 30)
	box.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_color_override("font_color", MenuTheme.DIM)
	_sub.add_theme_font_size_override("font_size", 15)
	box.add_child(_sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	box.add_child(gap)

	_first_btn = _button(box, "Resume", close)
	MenuTheme.primary(_first_btn)
	_button(box, "Map", _open_map)
	_invite_btn = _button(box, "Invite friends (Wi-Fi)", func() -> void:
		if Net.host():
			GameState.notify("Friends on your Wi-Fi can join from Join Game")
		_update_net())
	_players_label = Label.new()
	_players_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_players_label.custom_minimum_size.x = 330
	_players_label.add_theme_font_size_override("font_size", 14)
	_players_label.add_theme_color_override("font_color", MenuTheme.COLD)
	box.add_child(_players_label)
	_quality_btn = _button(box, "", _cycle_quality)
	_button(box, "Settings", func() -> void:
		var sp := SettingsPanel.new()
		add_child(sp)
		_box.visible = false
		sp.closed.connect(func() -> void:
			sp.queue_free()
			_box.visible = true
			_update_quality_text()
			_first_btn.grab_focus())
		sp.open())
	_save_btn = _button(box, "Save game", func() -> void:
		save_requested.emit()
		GameState.notify("Game saved"))
	_quit_btn = _button(box, "Quit to menu", func() -> void:
		visible = false
		menu_requested.emit())
	if not OS.has_feature("ios"): # iOS apps must not quit themselves.
		_button(box, "Save and quit", func() -> void:
			save_requested.emit()
			get_tree().quit())
	_update_quality_text()
	# The map page.
	_map_layer = ColorRect.new()
	(_map_layer as ColorRect).color = Color(0.03, 0.035, 0.035, 0.97)
	_map_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_layer.visible = false
	add_child(_map_layer)
	_map = MapView.new()
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.offset_top = 20
	_map.offset_bottom = -90
	_map_layer.add_child(_map)
	var legend := PanelContainer.new()
	legend.position = Vector2(20, 20)
	_map_layer.add_child(legend)
	_map_info = Label.new()
	_map_info.add_theme_font_size_override("font_size", 15)
	_map_info.add_theme_color_override("font_color", MenuTheme.TEXT)
	legend.add_child(_map_info)
	var back := _button(_map_layer, "Back", _close_map)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = -140
	back.offset_right = 140
	back.offset_top = -70
	back.offset_bottom = -18


func _open_map() -> void:
	_map.load_world(GameState.world, GameState.explored)
	if player:
		_map.player_pos = player.global_position
		_map.player_yaw = player.rotation.y
	_map.markers.clear()
	for id in Net.players:
		var st: Dictionary = Net.players[id].state
		if not st.is_empty():
			_map.markers.append({"pos": st.p, "color": Color(0.4, 0.85, 1.0), "label": str(Net.players[id].name)})
	var game := get_parent()
	if game and "pings" in game:
		for pg in game.pings:
			_map.markers.append({"pos": pg.pos, "color": Color(1.0, 0.55, 0.2), "label": "%s's ping" % pg.name})
	_map_info.text = "MAP  ·  DAY %d\nExplored %.1f%%\n\nYou: yellow arrow\nResearch centres: purple\nAirports: blue" % [
		GameState.day, GameState.explored_fraction() * 100.0]
	_map_layer.visible = true
	_box.visible = false
	(_map_layer.get_child(2) as Button).grab_focus()



func _close_map() -> void:
	_map_layer.visible = false
	_box.visible = true
	_first_btn.grab_focus()


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(330, 48)
	b.add_theme_font_override("font", MenuTheme.bold_font())
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _cycle_quality() -> void:
	GameState.set_quality((GameState.quality + 1) % 3)
	_update_quality_text()


func _update_quality_text() -> void:
	_quality_btn.text = "Graphics:  %s" % GameState.preset().name


func open() -> void:
	visible = true
	GameState.ui_open = true
	var ch := GameState.character
	_title.text = ch.name.to_upper() if ch else "PAUSED"
	_sub.text = "Day %d  ·  %d zombies killed  ·  %.1f%% explored" % [GameState.day, GameState.kills, GameState.explored_fraction() * 100.0]
	_opened_frame = Engine.get_process_frames()
	_update_net()
	# With friends playing, the world can't stop for one player.
	get_tree().paused = not Net.active()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_first_btn.grab_focus()


func close() -> void:
	visible = false
	GameState.ui_open = false
	_map_layer.visible = false
	_box.visible = true
	get_tree().paused = false
	if not GameState.uses_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_net() -> void:
	_invite_btn.visible = not Net.is_client()
	_invite_btn.disabled = Net.is_host()
	_invite_btn.text = "Hosting on Wi-Fi" if Net.is_host() else "Invite friends (Wi-Fi)"
	_save_btn.visible = not Net.is_client()
	_quit_btn.text = "Leave game" if Net.is_client() else ("End game and quit to menu" if Net.is_host() else "Quit to menu")
	var names: PackedStringArray = [GameState.character.name + " (you)"]
	for id in Net.players:
		names.append(str(Net.players[id].name))
	var pvp := "PvP on" if GameState.world.get("pvp", false) else "PvP off"
	_players_label.text = ("Playing: %s  ·  %s" % [", ".join(names), pvp]) if Net.active() else ""
	_players_label.visible = Net.active()


func _process(_delta: float) -> void:
	if visible and Engine.get_process_frames() % 30 == 0:
		_update_net()
	if visible and Engine.get_process_frames() != _opened_frame and Input.is_action_just_pressed("pause"):
		close()
