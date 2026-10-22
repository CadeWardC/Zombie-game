class_name Hud
extends CanvasLayer
## Heads-up display: survival bars, health warnings (bleeding, broken bones,
## fever, infection), the infection's screen effects, clock, crosshair
## (spreads with gun accuracy), hit markers, scope view, stealth eye, nearby
## zombie hints, weapon panel, prompts with the right button glyph (and a
## ring while holding), messages, damage flash, loading screen and the death
## screen for each death rule. Built in code to keep scenes minimal.

signal respawn_requested
signal new_character_requested
signal menu_requested

const SICK_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
uniform float pulse = 0.0;
uniform float hurt = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = textureLod(screen_tex, uv, amount * (1.0 + pulse * 2.5)).rgb;
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey) * vec3(1.0, 0.96, 0.9), amount * 0.85);
	float v = smoothstep(0.3, 0.85, length(uv - 0.5) * (1.0 + pulse * amount * 0.35));
	col = mix(col, vec3(0.22, 0.0, 0.0), v * max(amount * 0.8, hurt * 0.75));
	COLOR = vec4(col, 1.0);
}
"""

var player: Player
var zombies: ZombieManager

var _bars := {}
var _clock: Label
var _toast: Label
var _debug: Label
var _overlay: Control
var _flash: ColorRect
var _loading: ColorRect
var _death: ColorRect
var _death_info: Label
var _death_title: Label
var _respawn_btn: Button
var _menu_btn: Button
var _loading_label: Label
var _loading_bar: ProgressBar
var _status: Label
var _sick: ColorRect
var _sick_mat: ShaderMaterial
var _beat_t := 0.0
var _new_char_btn: Button
var _watch_btn: Button
var _players: Label
var _death_panel: VBoxContainer
var _death_full := true
## The running game (pings, spectating), and who you're watching.
var game: Node
var spectating := ""
var _toast_t := 0.0
var _hit_t := 0.0
var _hit_kill := false
var _show_debug := false


func _ready() -> void:
	layer = 1
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Infection and low-health screen effect (only drawn when needed).
	_sick = _fullscreen(root, Color.WHITE)
	_sick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SICK_SHADER
	_sick_mat = ShaderMaterial.new()
	_sick_mat.shader = sh
	_sick.material = _sick_mat
	_sick.visible = false
	_flash = _fullscreen(root, Color(0.7, 0.0, 0.0, 0.0))
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	root.add_child(_overlay)

	var box := VBoxContainer.new()
	box.position = Vector2(20, 20)
	box.add_theme_constant_override("separation", 6)
	root.add_child(box)
	_add_bar(box, "health", "HP", Color(0.8, 0.15, 0.15))
	_add_bar(box, "hunger", "FOOD", Color(0.85, 0.55, 0.15))
	_add_bar(box, "thirst", "WATER", Color(0.2, 0.5, 0.9))
	_add_bar(box, "stamina", "STAM", Color(0.85, 0.8, 0.25))
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_outline(_status)
	box.add_child(_status)

	_clock = _label(root, 20)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var clock_y := 80.0 if GameState.uses_touch() else 16.0
	_place(_clock, Vector2(0.5, 0), Rect2(-150, clock_y, 300, 30))

	# Who else is playing (multiplayer), under the clock.
	_players = _label(root, 15)
	_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_players, Vector2(0.5, 0), Rect2(-300, clock_y + 30, 600, 24))

	_toast = _label(root, 22)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_toast, Vector2(0.5, 1), Rect2(-300, -130, 600, 40))

	_debug = _label(root, 14)
	_place(_debug, Vector2(0, 1), Rect2(20, -40, 900, 24))
	_debug.visible = false

	_loading = _fullscreen(root, Color(0.05, 0.06, 0.06, 1.0))
	_loading_label = _label(_loading, 28)
	_loading_label.text = "Generating world..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_loading_label, Vector2(0.5, 0.5), Rect2(-300, -40, 600, 40))
	_loading_bar = ProgressBar.new()
	_loading_bar.max_value = 1.0
	_loading_bar.show_percentage = false
	_loading.add_child(_loading_bar)
	_place(_loading_bar, Vector2(0.5, 0.5), Rect2(-220, 20, 440, 14))

	_death = _fullscreen(root, Color(0.15, 0.0, 0.0, 0.75))
	_death.visible = false
	var dv := VBoxContainer.new()
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.add_theme_constant_override("separation", 20)
	_death.add_child(dv)
	_place(dv, Vector2(0.5, 0.5), Rect2(-300, -170, 600, 340))
	_death_panel = dv
	_death_title = _label(dv, 56)
	_death_title.text = "YOU DIED"
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_info = _label(dv, 20)
	_death_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_btn = Button.new()
	_respawn_btn.text = "Respawn"
	_respawn_btn.custom_minimum_size = Vector2(260, 70)
	_respawn_btn.add_theme_font_size_override("font_size", 26)
	_respawn_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_respawn_btn.pressed.connect(func() -> void: respawn_requested.emit())
	dv.add_child(_respawn_btn)
	_new_char_btn = Button.new()
	_new_char_btn.text = "New Character"
	_new_char_btn.custom_minimum_size = Vector2(260, 70)
	_new_char_btn.add_theme_font_size_override("font_size", 26)
	_new_char_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_new_char_btn.pressed.connect(func() -> void: new_character_requested.emit())
	dv.add_child(_new_char_btn)
	_watch_btn = Button.new()
	_watch_btn.text = "Watch Next Player"
	_watch_btn.custom_minimum_size = Vector2(260, 60)
	_watch_btn.add_theme_font_size_override("font_size", 22)
	_watch_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_watch_btn.pressed.connect(func() -> void:
		if game:
			game.next_spectated())
	dv.add_child(_watch_btn)
	_menu_btn = Button.new()
	_menu_btn.text = "Main Menu"
	_menu_btn.custom_minimum_size = Vector2(260, 60)
	_menu_btn.add_theme_font_size_override("font_size", 22)
	_menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_btn.pressed.connect(func() -> void: menu_requested.emit())
	dv.add_child(_menu_btn)

	GameState.message.connect(show_message)


## Wires up the player's hit feedback (call once the player exists).
func connect_player(p: Player) -> void:
	player = p
	p.weapons.hit_zombie.connect(func(killed: bool) -> void:
		_hit_t = 0.25
		_hit_kill = killed)


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


func set_loading_progress(f: float, text: String) -> void:
	_loading_bar.value = f
	_loading_label.text = text + "..."


## The death screen. `rule` is the world's death rule; `turned` when the
## infection got you (your body walks on with your gear). In a multiplayer
## game (`multi`) the screen is see-through, so you can watch your friends,
## and a turned survivor can still be cured.
func show_death(on: bool, rule := 0, cause := "", turned := false, multi := false) -> void:
	_death.visible = on
	_death_full = not multi
	_death.color.a = 0.25 if multi else 0.75
	_place(_death_panel, Vector2(0.5, 1.0 if multi else 0.5), Rect2(-300, -360, 600, 340) if multi else Rect2(-300, -170, 600, 340))
	var lost := rule == GameState.DeathRule.PERMADEATH and not multi
	var out := multi and rule == GameState.DeathRule.PERMADEATH and not turned
	_death_title.text = "WORLD LOST" if lost else ("YOU'RE OUT" if out else ("YOU TURNED" if turned else "YOU DIED"))
	_respawn_btn.visible = rule == GameState.DeathRule.RESPAWN
	_new_char_btn.visible = rule == GameState.DeathRule.NEW_CHARACTER
	_watch_btn.visible = multi and (out or turned or rule == GameState.DeathRule.PERMADEATH)
	var ch := GameState.character
	var lines: PackedStringArray = ["%s, %s" % [ch.name, Character.BACKGROUNDS[ch.background].name]]
	if cause != "":
		lines.append(cause)
	lines.append("Survived %d day%s  -  %d zombies killed" % [GameState.day, "" if GameState.day == 1 else "s", GameState.kills])
	if turned and multi:
		lines.append("Your friends can still save you: beat your body down and give it a cure vial.")
	elif out:
		lines.append("You can watch your friends. The world ends when everyone is out.")
	elif turned and not lost:
		lines.append("Your body walks on, carrying your gear.")
	elif not lost:
		lines.append("Your gear lies where you fell.")
	match rule:
		GameState.DeathRule.RESPAWN:
			lines.append("You keep your skills and traits.")
		GameState.DeathRule.NEW_CHARACTER:
			lines.append("Someone new takes up the fight.")
		_:
			if not multi:
				lines.append("This world is kept as a memorial.")
	_death_info.text = "\n".join(lines)
	if on:
		# Focus a button so gamepads can pick it without touching the screen.
		var b: Button = _menu_btn if lost or (rule == GameState.DeathRule.PERMADEATH and not _watch_btn.visible) else \
				(_watch_btn if rule == GameState.DeathRule.PERMADEATH else (_respawn_btn if rule == GameState.DeathRule.RESPAWN else _new_char_btn))
		b.grab_focus.call_deferred()


## True when the death screen covers everything (no watching friends).
func death_full() -> bool:
	return _death.visible and _death_full


func flash_damage() -> void:
	_flash.color.a = 0.35


func toggle_debug() -> void:
	_show_debug = not _show_debug
	_debug.visible = _show_debug


func _process(delta: float) -> void:
	if player:
		_bars.health.value = player.health
		_bars.hunger.value = player.hunger
		_bars.thirst.value = player.thirst
		_bars.stamina.value = player.stamina
		_bars.stamina.max_value = maxf(1.0, player.max_stamina())
		_status.text = status_text(player)
		_update_sick(delta)
	var hours := int(GameState.time_of_day)
	var minutes := int((GameState.time_of_day - hours) * 60.0)
	_clock.text = "Day %d   %02d:%02d%s" % [GameState.day, hours, minutes, "  (night)" if GameState.is_night() else ""]
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 0.8)
	_hit_t = maxf(0.0, _hit_t - delta)
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
	_overlay.visible = player != null and player.active and not GameState.ui_open and (not player.dead or spectating != "")
	_overlay.queue_redraw()
	_players.text = _players_text()
	if spectating != "" and _death.visible:
		_death_info.text = _death_info.text.get_slice("\n\nWatching", 0) + "\n\nWatching %s" % spectating


## "Sam 80  -  Alex (down)": the other players and how they're doing.
func _players_text() -> String:
	if not Net.active():
		return ""
	var parts: PackedStringArray = []
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		var st: Dictionary = p.state
		if st.is_empty():
			parts.append("%s (joining)" % p.name)
		elif p.get("out", false):
			parts.append("%s (out)" % p.name)
		elif st.turned:
			parts.append("%s (turned!)" % p.name)
		elif st.dead:
			parts.append("%s (down)" % p.name)
		else:
			parts.append("%s %d" % [p.name, int(st.get("hp", 100))])
	return "  -  ".join(parts)


## Short warnings under the bars ("BLEEDING  BROKEN LEG  FEVER").
static func status_text(p: Player) -> String:
	var b := p.body
	var out: PackedStringArray = []
	if b.bleeding():
		out.append("BLEEDING")
	for inj in b.injuries:
		if inj.k == "fracture":
			out.append("BROKEN %s" % ("LEG" if str(inj.p).begins_with("leg") else "ARM"))
		elif inj.k == "deep_wound" and not inj.s:
			out.append("DEEP WOUND")
	if b.fever():
		out.append("FEVER")
	if b.symptoms() > 0.0:
		out.append("SICK" if b.symptoms() < 0.5 else "TURNING")
	if b.pain() > 0.4:
		out.append("PAIN")
	if p.craving():
		out.append("CRAVING")
	if p._grab_t > 0.0:
		out.append("GRABBED")
	var uniq: PackedStringArray = []
	for st in out:
		if not st in uniq:
			uniq.append(st)
	return "  ".join(uniq)


## Blur, fading colour and a heartbeat vignette as the infection takes
## hold; a red vignette when badly hurt.
func _update_sick(delta: float) -> void:
	var amount := player.body.symptoms() if not player.dead else 0.0
	var hurt := clampf((35.0 - player.health) / 35.0, 0.0, 1.0) if not player.dead else 0.0
	_sick.visible = (amount > 0.01 or hurt > 0.01) and player.active
	if not _sick.visible:
		return
	var bpm := lerpf(70.0, 150.0, maxf(amount, hurt))
	_beat_t += delta * bpm / 60.0
	var ph := fmod(_beat_t, 1.0)
	var pulse := maxf(exp(-ph * 14.0), exp(-absf(ph - 0.25) * 14.0) * 0.6)
	_sick_mat.set_shader_parameter("amount", amount)
	_sick_mat.set_shader_parameter("pulse", pulse)
	_sick_mat.set_shader_parameter("hurt", hurt)


# --- Overlay ---------------------------------------------------------------

func _draw_overlay() -> void:
	if player == null:
		return
	var ci := _overlay
	var size := ci.size
	var c := size * 0.5
	var font := ci.get_theme_default_font()
	var w := player.weapons
	if player.dead:
		_draw_pings(ci, size, font) # Watching friends.
		return
	if player.vehicle:
		_draw_pings(ci, size, font)
		_draw_prompt(ci, Vector2(c.x, size.y - 150.0), font)
		_draw_vehicle_panel(ci, size, font, player.vehicle)
		return
	if w.scoped():
		_draw_scope(ci, size)
	else:
		_draw_crosshair(ci, c, w)
	# Hit marker.
	if _hit_t > 0.0:
		var col := Color(1.0, 0.25, 0.2, _hit_t * 4.0) if _hit_kill else Color(1, 1, 1, _hit_t * 4.0)
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			ci.draw_line(c + d * 7.0, c + d * 14.0, col, 2.5)
	_draw_pings(ci, size, font)
	_draw_stealth(ci, c, font)
	_draw_senses(ci, c)
	_draw_prompt(ci, c, font)
	_draw_weapon_panel(ci, size, font, w)


func _draw_crosshair(ci: Control, c: Vector2, w: Weapons) -> void:
	var col := Color(1, 1, 1, 0.85)
	if w.red_dot():
		ci.draw_circle(c, 2.5, Color(1.0, 0.1, 0.05))
		return
	if not w.is_ranged():
		ci.draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), col)
		return
	# Four ticks that open up with the current spread.
	var d := w.def()
	var spread := lerpf(float(d.get("spread", 2.0)), float(d.get("ads_spread", 0.5)), w.aim_blend)
	if player.velocity.length() > 1.0:
		spread *= 1.5
	var gap := 4.0 + spread * 5.0 * (1.0 + w.charge)
	if d.get("cat", "") == "bow" and d.get("draw", 0.0) > 0.0:
		gap = lerpf(26.0, 5.0, w.charge)
	for v: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		ci.draw_line(c + v * gap, c + v * (gap + 8.0), col, 2.0)
	ci.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), col)


func _draw_scope(ci: Control, size: Vector2) -> void:
	var c := size * 0.5
	var r := size.y * 0.46
	# Black everywhere outside the lens.
	var pts := PackedVector2Array()
	for k in 49:
		pts.append(c + Vector2.from_angle(k * TAU / 48.0) * r)
	ci.draw_rect(Rect2(0, 0, c.x - r, size.y), Color.BLACK)
	ci.draw_rect(Rect2(c.x + r, 0, size.x - c.x - r, size.y), Color.BLACK)
	for k in 48:
		var a := pts[k]
		var b := pts[k + 1]
		var edge := Vector2(a.x, 0.0 if a.y < c.y else size.y)
		var edge2 := Vector2(b.x, edge.y)
		ci.draw_colored_polygon(PackedVector2Array([a, b, edge2, edge]), Color.BLACK)
	ci.draw_arc(c, r, 0, TAU, 64, Color(0.1, 0.1, 0.1), 6.0)
	var line := Color(0, 0, 0, 0.9)
	ci.draw_line(c - Vector2(r, 0), c - Vector2(8, 0), line, 2.0)
	ci.draw_line(c + Vector2(8, 0), c + Vector2(r, 0), line, 2.0)
	ci.draw_line(c - Vector2(0, r), c - Vector2(0, 8), line, 2.0)
	ci.draw_line(c + Vector2(0, 8), c + Vector2(0, r), line, 2.0)
	ci.draw_circle(c, 1.5, Color(0.9, 0.1, 0.1))


## Stealth eye above the crosshair: grey = unseen, yellow = a zombie is
## suspicious, red = spotted. "HIDDEN" when crouched in cover or darkness.
func _draw_stealth(ci: Control, c: Vector2, font: Font) -> void:
	var det := zombies.detection if zombies else 0.0
	if det < 0.05 and not player.crouching:
		return
	var p := c + Vector2(0, -96)
	var col := Color(0.75, 0.75, 0.75, 0.7)
	if det >= 1.0:
		col = Color(0.95, 0.2, 0.15, 0.95)
	elif det > 0.05:
		col = Color(1.0, 0.8, 0.2, 0.6 + det * 0.4)
	var pts := PackedVector2Array()
	for k in 13:
		var t := k / 12.0
		pts.append(p + Vector2(lerpf(-18, 18, t), -sin(t * PI) * 9.0))
	for k in range(12, -1, -1):
		var t := k / 12.0
		pts.append(p + Vector2(lerpf(-18, 18, t), sin(t * PI) * 9.0))
	ci.draw_polyline(pts, col, 2.0)
	ci.draw_circle(p, 4.5 + det * 1.5, col)
	if det > 0.05 and det < 1.0:
		ci.draw_arc(p, 24.0, -PI * 0.5, -PI * 0.5 + TAU * det, 32, col, 3.0)
	if player.hidden():
		var t := "HIDDEN"
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		ci.draw_string_outline(font, p + Vector2(-tw * 0.5, 30), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
		ci.draw_string(font, p + Vector2(-tw * 0.5, 30), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.9, 0.7))


## Pings from you and your friends: a marker in the world with who sent it
## and how far it is, or an arrow at the screen edge when it's behind you.
func _draw_pings(ci: Control, size: Vector2, font: Font) -> void:
	if game == null or game.pings.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cols := {"go": Color(0.35, 0.8, 1.0), "zombie": Color(1.0, 0.3, 0.25), "loot": Color(1.0, 0.85, 0.3),
		"help": Color(1.0, 0.5, 0.1)}
	var labels := {"go": "Here", "zombie": "Zombie", "loot": "Loot", "help": "HELP"}
	for pg in game.pings:
		var pos: Vector3 = pg.pos + Vector3(0, 0.6, 0)
		var col: Color = cols.get(pg.kind, Color.WHITE)
		var age := (Time.get_ticks_msec() - int(pg.t)) / 1000.0
		col.a = clampf(2.0 - age / 10.0, 0.3, 1.0)
		var d := cam.global_position.distance_to(pos)
		var text := "%s: %s  %dm" % [pg.name, labels.get(pg.kind, ""), int(d)]
		if cam.is_position_behind(pos):
			var dir := (pos - cam.global_position)
			var side := signf(dir.dot(cam.global_basis.x))
			var e := Vector2(size.x * 0.5 + side * (size.x * 0.5 - 30.0), size.y * 0.5)
			ci.draw_colored_polygon(PackedVector2Array([e + Vector2(14 * side, 0), e + Vector2(-6 * side, -12), e + Vector2(-6 * side, 12)]), col)
			continue
		var sp := cam.unproject_position(pos)
		sp = sp.clamp(Vector2(30, 30), size - Vector2(30, 30))
		var r := 9.0 + (sin(age * 8.0) * 2.0 if pg.kind == "help" else 0.0)
		ci.draw_circle(sp, r, Color(col, col.a * 0.35))
		ci.draw_arc(sp, r, 0, TAU, 20, col, 2.5)
		ci.draw_line(sp + Vector2(0, r), sp + Vector2(0, r + 10), col, 2.0)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		ci.draw_string_outline(font, sp + Vector2(-tw * 0.5, -r - 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
		ci.draw_string(font, sp + Vector2(-tw * 0.5, -r - 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


## Zombies you sense but haven't seen (close by, off to the side or
## behind): red arcs around the crosshair. Keen hearing widens the range.
func _draw_senses(ci: Control, c: Vector2) -> void:
	if zombies == null:
		return
	var radius := 7.0 * GameState.character.mod("hearing")
	var fwd := -player.global_basis.z
	for z in zombies.in_radius(player.global_position, radius):
		var to := z.global_position - player.global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.5:
			continue
		to /= d
		if fwd.dot(to) > 0.75:
			continue # In plain view.
		var ang := atan2(to.dot(player.global_basis.x), fwd.dot(to)) - PI * 0.5
		var a := clampf(1.0 - d / radius, 0.15, 1.0)
		ci.draw_arc(c, 70.0, ang - 0.22, ang + 0.22, 12, Color(0.95, 0.15, 0.1, a * 0.8), 5.0)


## "[E] Open door" with the right glyph for the device in use; while
## interact is held on something holdable, a ring fills around the glyph.
func _draw_prompt(ci: Control, c: Vector2, font: Font) -> void:
	if player.prompt == "":
		return
	var fs := 20
	var action := player.prompt_action
	var tw := font.get_string_size(player.prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var gw := 0.0 if GameState.uses_touch() and not GameState.using_gamepad() else InputGlyphs.width(action, font, 28.0)
	var x := c.x - (tw + gw + (8.0 if gw > 0.0 else 0.0)) * 0.5
	var y := c.y + 44.0
	if gw > 0.0:
		InputGlyphs.draw(ci, action, Vector2(x, y), 28.0, font)
		x += gw + 8.0
	ci.draw_string_outline(font, Vector2(x, y + 21), player.prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
	ci.draw_string(font, Vector2(x, y + 21), player.prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if player.hold_prompt != "":
		var hint := "Hold to %s" % player.hold_prompt
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		ci.draw_string_outline(font, Vector2(c.x - hw * 0.5, y + 44), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
		ci.draw_string(font, Vector2(c.x - hw * 0.5, y + 44), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.85, 0.8))
	var hold := player.hold_progress()
	if hold > 0.0:
		ci.draw_arc(Vector2(c.x, y + 14), 26.0, -PI * 0.5, -PI * 0.5 + TAU * hold, 32, Color(0.95, 0.85, 0.3), 4.0)


## Driving: speed, fuel, condition and warnings (bottom-right, or top-left
## on touch like the weapon panel).
func _draw_vehicle_panel(ci: Control, size: Vector2, font: Font, v: Vehicle) -> void:
	var touch := GameState.uses_touch() and not GameState.using_gamepad()
	var pos := Vector2(20, 156) if touch else Vector2(size.x - 300, size.y - 132)
	ci.draw_rect(Rect2(pos, Vector2(280, 112)), Color(0, 0, 0, 0.45))
	var white := Color.WHITE
	var lines: Array = []
	var kmh := int(absf(v.speed) * 3.6)
	lines.append(["%s   %d km/h" % [v.def.name, kmh], 20, white])
	var info: PackedStringArray = []
	if v.def.fuel != "":
		info.append("Fuel %d / %d L" % [int(v.rec.fuel), int(v.def.tank)])
	info.append("Condition %d%%" % int(100.0 * float(v.rec.hp) / float(v.def.hp)))
	lines.append(["   ".join(info), 16, Color(0.85, 0.9, 0.85)])
	var warn := ""
	if float(v.rec.hp) <= 0.0:
		warn = "Wrecked"
	elif v.def.fuel != "" and not v.running and player.seat == 0:
		warn = "Engine off - %s" % ("press reload to start" if not GameState.uses_touch() else "tap RELOAD to start")
	elif v.def.fuel != "" and float(v.rec.fuel) < float(v.def.tank) * 0.1:
		warn = "Low fuel"
	elif v.kind == "plane":
		warn = ("Throttle %d%%" % int(v.throttle * 100.0)) + ("" if v.airborne else ("   take off at %d km/h" % int(float(v.def.takeoff) * 3.6)))
	elif v.kind == "heli":
		warn = "Altitude %d m" % int(v.global_position.y - gen_height(v.global_position))
	if warn != "":
		lines.append([warn, 16, Color(1, 0.75, 0.35)])
	var y := pos.y + 28
	for l in lines:
		ci.draw_string_outline(font, Vector2(pos.x + 12, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, 260, l[1], 4, Color.BLACK)
		ci.draw_string(font, Vector2(pos.x + 12, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, 260, l[1], l[2])
		y += 30


func gen_height(p: Vector3) -> float:
	return player.gen.height(p.x, p.z) if player.gen else 0.0


## Current weapon, rounds and condition. Bottom-right on desktop and gamepad;
## top-left under the bars on touch (the buttons own the bottom-right).
func _draw_weapon_panel(ci: Control, size: Vector2, font: Font, w: Weapons) -> void:
	var st := w.status()
	if st.name == "":
		return
	var touch := GameState.uses_touch() and not GameState.using_gamepad()
	var pos := Vector2(20, 156) if touch else Vector2(size.x - 280, size.y - 92)
	var panel := Rect2(pos, Vector2(260, 72))
	ci.draw_rect(panel, Color(0, 0, 0, 0.4))
	var name_text: String = st.name
	ci.draw_string_outline(font, pos + Vector2(10, 24), name_text, HORIZONTAL_ALIGNMENT_LEFT, 240, 18, 4, Color.BLACK)
	ci.draw_string(font, pos + Vector2(10, 24), name_text, HORIZONTAL_ALIGNMENT_LEFT, 240, 18, Color.WHITE)
	if st.ammo != "":
		ci.draw_string_outline(font, pos + Vector2(10, 52), st.ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 4, Color.BLACK)
		ci.draw_string(font, pos + Vector2(10, 52), st.ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.95, 0.75))
	if st.state != "":
		ci.draw_string_outline(font, pos + Vector2(130, 52), st.state, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
		ci.draw_string(font, pos + Vector2(130, 52), st.state, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.5, 0.35))
	if float(st.cond) >= 0.0:
		var c := float(st.cond)
		ci.draw_rect(Rect2(pos + Vector2(10, 62), Vector2(240, 4)), Color(0, 0, 0, 0.5))
		ci.draw_rect(Rect2(pos + Vector2(10, 62), Vector2(240 * c, 4)), Color(0.3, 0.8, 0.3) if c > 0.5 else (Color(0.9, 0.7, 0.2) if c > 0.25 else Color(0.9, 0.25, 0.2)))
	# Slot hints for keyboard / gamepad.
	if not touch:
		var hint := "1-4 / wheel" if not GameState.using_gamepad() else ""
		if GameState.using_gamepad():
			var gx := pos.x + panel.size.x - 60
			InputGlyphs.draw(ci, "weapon_prev", Vector2(gx - 2, pos.y - 30), 24.0, font)
		elif hint != "":
			ci.draw_string(font, pos + Vector2(180, 24), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
