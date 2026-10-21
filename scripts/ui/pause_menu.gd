class_name PauseMenu
extends CanvasLayer
## Pause menu: resume, graphics quality, save, new world, quit.

signal save_requested
signal menu_requested

var _quality_btn: Button
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
	box.offset_top = -230
	box.offset_bottom = 230
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	bg.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)

	_first_btn = _button(box, "Resume", close)
	_quality_btn = _button(box, "", _cycle_quality)
	_button(box, "Save Game", func() -> void:
		save_requested.emit()
		GameState.notify("Game saved"))
	_button(box, "Quit to Menu", func() -> void:
		visible = false
		menu_requested.emit())
	if not OS.has_feature("ios"): # iOS apps must not quit themselves.
		_button(box, "Save & Quit", func() -> void:
			save_requested.emit()
			get_tree().quit())
	_update_quality_text()


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
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_first_btn.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false
	if not GameState.uses_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if visible and Engine.get_process_frames() != _opened_frame and Input.is_action_just_pressed("pause"):
		close()
