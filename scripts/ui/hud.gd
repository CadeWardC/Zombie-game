class_name Hud
extends CanvasLayer
## Heads-up display: survival bars, clock, crosshair, messages, damage flash,
## loading screen and death screen. Built in code to keep scenes minimal.

signal respawn_requested

var player: Player
var zombies: ZombieManager

var _bars := {}
var _clock: Label
var _inventory: Label
var _toast: Label
var _debug: Label
var _prompt: Label
var _flash: ColorRect
var _loading: ColorRect
var _death: ColorRect
var _death_info: Label
var _toast_t := 0.0
var _show_debug := false


func _ready() -> void:
	layer = 1
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_flash = _fullscreen(root, Color(0.7, 0.0, 0.0, 0.0))
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := VBoxContainer.new()
	box.position = Vector2(20, 20)
	box.add_theme_constant_override("separation", 6)
	root.add_child(box)
	_add_bar(box, "health", "HP", Color(0.8, 0.15, 0.15))
	_add_bar(box, "hunger", "FOOD", Color(0.85, 0.55, 0.15))
	_add_bar(box, "thirst", "WATER", Color(0.2, 0.5, 0.9))
	_add_bar(box, "stamina", "STAM", Color(0.85, 0.8, 0.25))

	_inventory = _label(root, 16)
	_inventory.position = Vector2(20, 120)
	_inventory.visible = not GameState.uses_touch()

	_clock = _label(root, 20)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var clock_y := 80.0 if GameState.uses_touch() else 16.0
	_place(_clock, Vector2(0.5, 0), Rect2(-150, clock_y, 300, 30))

	_toast = _label(root, 22)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_toast, Vector2(0.5, 1), Rect2(-300, -130, 600, 40))

	_prompt = _label(root, 20)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, Vector2(0.5, 0.5), Rect2(-250, 40, 500, 30))

	_debug = _label(root, 14)
	_place(_debug, Vector2(0, 1), Rect2(20, -40, 900, 24))
	_debug.visible = false

	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.8)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	_place(cross, Vector2(0.5, 0.5), Rect2(-2, -2, 4, 4))

	_loading = _fullscreen(root, Color(0.05, 0.06, 0.06, 1.0))
	var lt := _label(_loading, 28)
	lt.text = "Generating world..."
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(lt, Vector2(0.5, 0.5), Rect2(-200, -20, 400, 40))

	_death = _fullscreen(root, Color(0.15, 0.0, 0.0, 0.75))
	_death.visible = false
	var dv := VBoxContainer.new()
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.add_theme_constant_override("separation", 20)
	_death.add_child(dv)
	_place(dv, Vector2(0.5, 0.5), Rect2(-250, -140, 500, 280))
	var title := _label(dv, 56)
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_info = _label(dv, 20)
	_death_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var btn := Button.new()
	btn.text = "Respawn"
	btn.custom_minimum_size = Vector2(240, 70)
	btn.add_theme_font_size_override("font_size", 26)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func() -> void: respawn_requested.emit())
	dv.add_child(btn)

	GameState.message.connect(show_message)
	GameState.inventory_changed.connect(_update_inventory)
	_update_inventory()


func _add_bar(parent: Node, key: String, text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(64, 0)
	l.add_theme_font_size_override("font_size", 14)
	_outline(l)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 16)
	bar.show_percentage = false
	bar.max_value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	parent.add_child(row)
	_bars[key] = bar


func _label(parent: Node, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline(l)
	parent.add_child(l)
	return l


func _outline(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)


func _fullscreen(parent: Node, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	parent.add_child(r)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r


## Anchors a control to a point on screen (fractions of the screen size) with
## a pixel rect relative to that point, so it stays put on any aspect ratio.
static func _place(c: Control, anchor: Vector2, rect: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = rect.position.x
	c.offset_top = rect.position.y
	c.offset_right = rect.end.x
	c.offset_bottom = rect.end.y


func show_message(text: String) -> void:
	_toast.text = text
	_toast_t = 2.5


func set_loading(on: bool) -> void:
	_loading.visible = on


func show_death(on: bool) -> void:
	_death.visible = on
	_death_info.text = "Survived %d days  -  %d zombies killed" % [GameState.day, GameState.kills]


func flash_damage() -> void:
	_flash.color.a = 0.35


func toggle_debug() -> void:
	_show_debug = not _show_debug
	_debug.visible = _show_debug


func _update_inventory() -> void:
	_inventory.text = "[1] Food x%d   [2] Water x%d   [3] Bandage x%d   [F] Light" % [
		GameState.item_count("food"), GameState.item_count("water"), GameState.item_count("bandage")]


func _process(delta: float) -> void:
	if player:
		var key_hint := "" if GameState.uses_touch() else "[E] "
		_prompt.text = (key_hint + player.prompt) if player.prompt != "" else ""
		_bars.health.value = player.health
		_bars.hunger.value = player.hunger
		_bars.thirst.value = player.thirst
		_bars.stamina.value = player.stamina
	var hours := int(GameState.time_of_day)
	var minutes := int((GameState.time_of_day - hours) * 60.0)
	_clock.text = "Day %d   %02d:%02d%s" % [GameState.day, hours, minutes, "  (night)" if GameState.is_night() else ""]
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 0.8)
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if _show_debug:
		var vp := get_viewport()
		_debug.text = "FPS %d  |  3D scale %.2f  |  zombies %d  |  draw calls %d  |  pos %s" % [
			Engine.get_frames_per_second(), vp.scaling_3d_scale,
			zombies.active_count() if zombies else 0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			str(Vector3i(player.global_position)) if player else ""]
