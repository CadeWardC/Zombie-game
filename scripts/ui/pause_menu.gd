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


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -160
	box.offset_right = 160
	box.offset_top = -300
	box.offset_bottom = 300
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	bg.add_child(box)
	_box = box

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)

	_first_btn = _button(box, "Resume", close)
	_button(box, "Map", _open_map)
	_invite_btn = _button(box, "Invite Friends (Wi-Fi)", func() -> void:
		if Net.host():
			GameState.notify("Friends on your Wi-Fi can join from Join Game")
		_update_net())
	_players_label = Label.new()
	_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_players_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_players_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_players_label)
	_quality_btn = _button(box, "", _cycle_quality)
	_save_btn = _button(box, "Save Game", func() -> void:
		save_requested.emit()
		GameState.notify("Game saved"))
	_quit_btn = _button(box, "Quit to Menu", func() -> void:
		visible = false
		menu_requested.emit())
	if not OS.has_feature("ios"): # iOS apps must not quit themselves.
		_button(box, "Save & Quit", func() -> void:
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
	_map_info = Label.new()
	_map_info.position = Vector2(20, 16)
	_map_info.add_theme_font_size_override("font_size", 18)
	_map_info.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	_map_layer.add_child(_map_info)
	var back := _button(_map_layer, "Back", _close_map)
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = -160
	back.offset_right = 160
	back.offset_top = -80
	back.offset_bottom = -16


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
	_map_info.text = "MAP\nDay %d\nExplored %.1f%%\n\nYou: yellow arrow\nResearch centres: purple\nAirports: blue" % [
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
	b.custom_minimum_size = Vector2(320, 64)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _cycle_quality() -> void:
	GameState.set_quality((GameState.quality + 1) % 3)
	_update_quality_text()


func _update_quality_text() -> void:
	_quality_btn.text = "Graphics: %s" % GameState.preset().name


func open() -> void:
	visible = true
	_opened_frame = Engine.get_process_frames()
	_update_net()
	# With friends playing, the world can't stop for one player.
	get_tree().paused = not Net.active()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_first_btn.grab_focus()


func close() -> void:
	visible = false
	_map_layer.visible = false
	_box.visible = true
	get_tree().paused = false
	if not GameState.uses_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_net() -> void:
	_invite_btn.visible = not Net.is_client()
	_invite_btn.disabled = Net.is_host()
	_invite_btn.text = "Hosting on Wi-Fi" if Net.is_host() else "Invite Friends (Wi-Fi)"
	_save_btn.visible = not Net.is_client()
	_quit_btn.text = "Leave Game" if Net.is_client() else ("Close Game and Quit to Menu" if Net.is_host() else "Quit to Menu")
	var names: PackedStringArray = [GameState.character.name + " (you)"]
	for id in Net.players:
		names.append(str(Net.players[id].name))
	var pvp := "PvP on" if GameState.world.get("pvp", false) else "PvP off"
	_players_label.text = ("Playing: %s  -  %s" % [", ".join(names), pvp]) if Net.active() else ""


func _process(_delta: float) -> void:
	if visible and Engine.get_process_frames() % 30 == 0:
		_update_net()
	if visible and Engine.get_process_frames() != _opened_frame and Input.is_action_just_pressed("pause"):
		close()
