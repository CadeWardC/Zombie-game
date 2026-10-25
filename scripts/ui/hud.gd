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
uniform float blur = 0.0;
uniform float chill = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = textureLod(screen_tex, uv, amount * (1.0 + pulse * 2.5) + blur * 1.8).rgb;
	col = mix(col, col * vec3(0.8, 0.9, 1.15), chill * 0.5);
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey) * vec3(1.0, 0.96, 0.9), amount * 0.85);
	float v = smoothstep(0.3, 0.85, length(uv - 0.5) * (1.0 + pulse * amount * 0.35));
	col = mix(col, vec3(0.22, 0.0, 0.0), v * max(amount * 0.8, hurt * 0.75));
	COLOR = vec4(col, 1.0);
}
"""

var player: Player
var zombies: ZombieManager

var _top: Control
var _toast_text := ""
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
var _sick: ColorRect
var _sick_mat: ShaderMaterial
var _beat_t := 0.0
var _new_char_btn: Button
var _watch_btn: Button
var _death_panel: Control
var _death_full := true
## The running game (pings, spectating), and who you're watching.
var game: Node
var spectating := ""
var _toast_t := 0.0
var _hit_t := 0.0
var _hit_kill := false
var _show_debug := false
var _sleep: ColorRect
var _sleep_label: Label
var _tip: PanelContainer
var _tip_title: Label
var _tip_text: Label
var _tip_t := 0.0
var _tips: Array = [] # Queued [title, text].
var _step: PanelContainer
var _step_label: Label
var _weapon_y := 0.0 # Where the weapon card goes on touch (under the warnings).
var _time := 0.0
var _hud_box := MenuTheme.box(MenuTheme.HUD_PANEL, 8, Color(1, 1, 1, 0.06), 1, 0.0)
var _chip_box := MenuTheme.box(Color.BLACK, 13, Color.WHITE, 1, 0.0)
var _pill_box := MenuTheme.box(Color.BLACK, 19, Color.WHITE, 1, 0.0)
var _prompt_box := MenuTheme.box(Color(0.04, 0.045, 0.05, 0.78), 20, Color(1, 1, 1, 0.12), 1, 0.0)


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

	# Vitals, warnings, clock and the other players: drawn in one pass.
	_top = Control.new()
	_top.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.draw.connect(_draw_top)
	root.add_child(_top)

	_debug = _label(root, 14)
	_place(_debug, Vector2(0, 1), Rect2(20, -40, 900, 24))
	_debug.visible = false

	_loading = _fullscreen(root, MenuTheme.BG)
	_loading.add_child(MenuBackdrop.new())
	var lshade := ColorRect.new()
	lshade.color = Color(0, 0, 0, 0.45)
	_loading.add_child(lshade)
	lshade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lt := MenuTheme.heading("Zombie survival", 34)
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(lt)
	_place(lt, Vector2(0.5, 0.5), Rect2(-300, -90, 600, 50))
	_loading_label = Label.new()
	_loading_label.add_theme_font_size_override("font_size", 17)
	_loading_label.add_theme_color_override("font_color", MenuTheme.DIM.lightened(0.2))
	_loading_label.text = "Generating world..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(_loading_label)
	_place(_loading_label, Vector2(0.5, 0.5), Rect2(-300, -30, 600, 30))
	_loading_bar = ProgressBar.new()
	_loading_bar.max_value = 1.0
	_loading_bar.show_percentage = false
	_loading.add_child(_loading_bar)
	_place(_loading_bar, Vector2(0.5, 0.5), Rect2(-220, 12, 440, 6))

	_death = _fullscreen(root, Color(0.08, 0.0, 0.0, 0.8))
	_death.visible = false
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.04, 0.035, 0.035, 0.9), 12, Color(MenuTheme.BAD, 0.35), 1, 26.0))
	_death.add_child(card)
	_place(card, Vector2(0.5, 0.5), Rect2(-300, -190, 600, 380))
	var dv := VBoxContainer.new()
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.add_theme_constant_override("separation", 12)
	card.add_child(dv)
	_death_panel = card
	_death_title = MenuTheme.heading("You died", 48, MenuTheme.BAD.lightened(0.15))
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(_death_title)
	_death_info = Label.new()
	_death_info.add_theme_font_size_override("font_size", 17)
	_death_info.add_theme_color_override("font_color", MenuTheme.TEXT.darkened(0.1))
	_death_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_death_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(_death_info)
	_respawn_btn = Button.new()
	_respawn_btn.text = "Respawn"
	_respawn_btn.custom_minimum_size = Vector2(280, 56)
	_respawn_btn.add_theme_font_size_override("font_size", 20)
	MenuTheme.primary(_respawn_btn)
	_respawn_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_respawn_btn.pressed.connect(func() -> void: respawn_requested.emit())
	dv.add_child(_respawn_btn)
	_new_char_btn = Button.new()
	_new_char_btn.text = "New Character"
	_new_char_btn.custom_minimum_size = Vector2(280, 56)
	_new_char_btn.add_theme_font_size_override("font_size", 20)
	MenuTheme.primary(_new_char_btn)
	_new_char_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_new_char_btn.pressed.connect(func() -> void: new_character_requested.emit())
	dv.add_child(_new_char_btn)
	_watch_btn = Button.new()
	_watch_btn.text = "Watch Next Player"
	_watch_btn.custom_minimum_size = Vector2(280, 50)
	_watch_btn.add_theme_font_size_override("font_size", 18)
	_watch_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_watch_btn.pressed.connect(func() -> void:
		if game:
			game.next_spectated())
	dv.add_child(_watch_btn)
	_menu_btn = Button.new()
	_menu_btn.text = "Main Menu"
	_menu_btn.custom_minimum_size = Vector2(280, 50)
	_menu_btn.add_theme_font_size_override("font_size", 18)
	_menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_btn.pressed.connect(func() -> void: menu_requested.emit())
	dv.add_child(_menu_btn)

	# Sleeping: the screen fades to black while time flies.
	_sleep = _fullscreen(root, Color(0.0, 0.0, 0.02, 0.0))
	_sleep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sleep_label = _label(_sleep, 26)
	_sleep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_sleep_label, Vector2(0.5, 0.5), Rect2(-300, -20, 600, 80))

	# Tips (first-time hints) in a panel on the right; the tutorial's current
	# step under the clock.
	_tip = PanelContainer.new()
	_tip.add_theme_stylebox_override("panel", MenuTheme.stripe_box(Color(0.05, 0.055, 0.06, 0.88), MenuTheme.WARN))
	root.add_child(_tip)
	_place(_tip, Vector2(1, 0), Rect2(-396, 124 if GameState.uses_touch() else 20, 380, 110))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	_tip.add_child(tv)
	_tip_title = MenuTheme.heading("", 15, MenuTheme.WARN)
	tv.add_child(_tip_title)
	_tip_text = Label.new()
	_tip_text.add_theme_font_size_override("font_size", 15)
	_tip_text.add_theme_color_override("font_color", MenuTheme.TEXT)
	_tip_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tip_text.custom_minimum_size.x = 350
	tv.add_child(_tip_text)
	_tip.visible = false
	_step = PanelContainer.new()
	_step.add_theme_stylebox_override("panel", MenuTheme.stripe_box(Color(0.05, 0.055, 0.06, 0.85), MenuTheme.ACCENT))
	root.add_child(_step)
	_place(_step, Vector2(0.5, 0), Rect2(-300, 96 if GameState.uses_touch() else 76, 600, 40))
	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 16)
	_step_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step.add_child(_step_label)
	_step.visible = false

	GameState.message.connect(show_message)


## Wires up the player's hit feedback (call once the player exists).
func connect_player(p: Player) -> void:
	player = p
	p.weapons.hit_zombie.connect(func(killed: bool) -> void:
		_hit_t = 0.25
		_hit_kill = killed)


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


func show_tip(title: String, text: String) -> void:
	_tips.append([title, text])


func _update_tips(delta: float) -> void:
	if _tip_t > 0.0:
		_tip_t -= delta
		_tip.modulate.a = clampf(_tip_t, 0.0, 1.0)
		if _tip_t <= 0.0:
			_tip.visible = false
	elif not _tips.is_empty():
		var t: Array = _tips.pop_front()
		_tip_title.text = "TIP  ·  " + str(t[0]).to_upper()
		_tip_text.text = str(t[1])
		_tip.visible = true
		_tip_t = 9.0
	var step: String = game.hints.current_step() if game and game.get("hints") else ""
	_step_label.text = step
	_step.visible = step != "" and not GameState.ui_open


func show_message(text: String) -> void:
	_toast_text = text
	_toast_t = 2.8


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
	_death.color.a = 0.25 if multi else 0.8
	_place(_death_panel, Vector2(0.5, 1.0 if multi else 0.5), Rect2(-300, -400, 600, 380) if multi else Rect2(-300, -190, 600, 380))
	var lost := rule == GameState.DeathRule.PERMADEATH and not multi
	var out := multi and rule == GameState.DeathRule.PERMADEATH and not turned
	_death_title.text = "WORLD LOST" if lost else ("YOU'RE OUT" if out else ("YOU TURNED" if turned else "YOU DIED"))
	_death_info.custom_minimum_size.x = 540
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
	_time += delta
	if player:
		_update_sick(delta)
	var hours := int(GameState.time_of_day)
	var minutes := int((GameState.time_of_day - hours) * 60.0)
	if player:
		var asleep := player.sleeping
		_sleep.color.a = move_toward(_sleep.color.a, 0.92 if asleep else 0.0, delta * 1.5)
		_sleep.visible = _sleep.color.a > 0.01
		_sleep_label.text = "Sleeping...  %02d:%02d\n(Use to get up)" % [hours, minutes] if asleep else ""
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 0.8)
	_update_tips(delta)
	if _tip_t > 0.0:
		_tip.visible = not GameState.ui_open and not (player and player.dead)
	_hit_t = maxf(0.0, _hit_t - delta)
	_toast_t = maxf(0.0, _toast_t - delta)
	if _show_debug:
		var vp := get_viewport()
		_debug.text = "FPS %d  |  3D scale %.2f  |  zombies %d  |  draw calls %d  |  pos %s" % [
			Engine.get_frames_per_second(), vp.scaling_3d_scale,
			zombies.active_count() if zombies else 0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			str(Vector3i(player.global_position)) if player else ""]
	_overlay.visible = player != null and player.active and not GameState.ui_open and (not player.dead or spectating != "")
	_overlay.queue_redraw()
	_top.visible = player != null and player.active and not GameState.ui_open
	_top.queue_redraw()
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
	return "  ".join(status_list(p).map(func(e: Array) -> String: return e[0]))


## The same warnings with an icon and a colour each: [text, icon, colour].
static func status_list(p: Player) -> Array:
	var b := p.body
	var out: Array = []
	var bad := MenuTheme.BAD
	var warn := MenuTheme.WARN
	if b.bleeding():
		out.append(["BLEEDING", "blood", bad])
	for inj in b.injuries:
		if inj.k == "fracture":
			out.append(["BROKEN %s" % ("LEG" if str(inj.p).begins_with("leg") else "ARM"), "bone", bad])
		elif inj.k == "deep_wound" and not inj.s:
			out.append(["DEEP WOUND", "blood", bad])
	if b.fever():
		out.append(["FEVER", "thermo", bad])
	if b.symptoms() > 0.0:
		out.append(["SICK" if b.symptoms() < 0.5 else "TURNING", "virus", Color(0.6, 0.85, 0.3)])
	if b.pain() > 0.4:
		out.append(["PAIN", "pain", warn])
	if p.craving():
		out.append(["CRAVING", "pain", warn])
	if b.sick > 0.25:
		out.append(["NAUSEOUS", "nausea", Color(0.6, 0.85, 0.3)])
	if p.fatigue > 90.0:
		out.append(["EXHAUSTED", "tired", bad])
	elif p.fatigue > 70.0:
		out.append(["TIRED", "tired", warn])
	if p.cold > 85.0:
		out.append(["FREEZING", "snow", bad])
	elif p.cold > 50.0:
		out.append(["COLD", "snow", MenuTheme.COLD])
	elif p.feels_like > 32.0:
		out.append(["HOT", "thermo", warn])
	if p.wet > 60.0:
		out.append(["SOAKED", "wet", MenuTheme.COLD])
	elif p.wet > 25.0:
		out.append(["WET", "wet", MenuTheme.COLD])
	if p._grab_t > 0.0:
		out.append(["GRABBED", "grab", bad])
	var seen := {}
	var uniq: Array = []
	for e in out:
		if not seen.has(e[0]):
			seen[e[0]] = true
			uniq.append(e)
	return uniq


## Which survival bars are on screen (the minimal HUD only shows the ones
## that need attention).
func vital_rows() -> Array:
	if player == null:
		return []
	var minimal: bool = GameState.settings.get("hud", "bars") == "minimal"
	var rows := []
	for r in _vitals():
		if not minimal or float(r[1]) < 0.5:
			rows.append(r[0])
	return rows


## [key, fraction, icon, colour] for each survival bar.
func _vitals() -> Array:
	return [
		["health", player.health / 100.0, "heart", Color(0.86, 0.24, 0.22)],
		["hunger", player.hunger / 100.0, "food", Color(0.88, 0.6, 0.22)],
		["thirst", player.thirst / 100.0, "water", Color(0.3, 0.6, 0.95)],
		["stamina", player.stamina / maxf(1.0, player.max_stamina()), "stamina", Color(0.88, 0.82, 0.32)],
	]


## Top of the screen: survival bars and warnings (top-left), the clock and
## weather (top-centre), the other players, and messages.
func _draw_top() -> void:
	if player == null:
		return
	var ci := _top
	var size := ci.size
	var font := MenuTheme.bold_font()
	var plain := ci.get_theme_default_font()
	var touch := GameState.uses_touch() and not GameState.using_gamepad()
	var pos := Vector2(16, 16)
	# Survival bars.
	var shown := vital_rows()
	var y := pos.y
	if not shown.is_empty() and not player.dead:
		var rows := _vitals().filter(func(r: Array) -> bool: return r[0] in shown)
		var card := Rect2(pos, Vector2(228, 14 + rows.size() * 24))
		ci.draw_style_box(_hud_box, card)
		var ry := pos.y + 7
		for r in rows:
			var f := clampf(float(r[1]), 0.0, 1.0)
			var col: Color = r[3]
			var low := f < 0.25
			if low:
				col = MenuTheme.BAD.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(_time * 7.0)))
			Icons.draw(ci, r[2], Vector2(pos.x + 19, ry + 12), 16.0, col if low else Color(col, 0.95))
			var bar := Rect2(pos.x + 36, ry + 8, 150, 8)
			ci.draw_rect(bar, Color(0, 0, 0, 0.5))
			ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), col)
			# Quarter ticks.
			for k in range(1, 4):
				ci.draw_line(bar.position + Vector2(bar.size.x * k / 4.0, 0), bar.position + Vector2(bar.size.x * k / 4.0, bar.size.y), Color(0, 0, 0, 0.45), 1.0)
			var pct := "%d" % int(round(f * 100.0))
			ci.draw_string(plain, Vector2(pos.x + 192, ry + 17), pct, HORIZONTAL_ALIGNMENT_RIGHT, 28, 13, Color(MenuTheme.TEXT, 0.85))
			ry += 24
		y = card.end.y + 8
	# Warnings as chips.
	var x := pos.x
	var chip_h := 26.0
	for e in status_list(player) if not player.dead else []:
		var t: String = e[0]
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var wdt := tw + 38.0
		if x + wdt > pos.x + 380.0:
			x = pos.x
			y += chip_h + 6
		var col: Color = e[2]
		var r := Rect2(x, y, wdt, chip_h)
		var sb: StyleBoxFlat = _chip_box
		sb.bg_color = Color(col.darkened(0.7), 0.82)
		sb.border_color = Color(col, 0.7)
		ci.draw_style_box(sb, r)
		Icons.draw(ci, e[1], Vector2(x + 15, y + chip_h * 0.5), 14.0, col)
		ci.draw_string(font, Vector2(x + 28, y + 18), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lightened(0.35))
		x += wdt + 6
	if x > pos.x:
		y += chip_h + 8
	_weapon_y = y
	# Clock and weather.
	var hours := int(GameState.time_of_day)
	var minutes := int((GameState.time_of_day - hours) * 60.0)
	var night := GameState.is_night()
	var line1 := "DAY %d   %02d:%02d" % [GameState.day, hours, minutes]
	var wk := Weather.kind()
	var line2 := "%s  ·  %s  ·  %d°C" % [Weather.NAMES.get(wk, ""), Weather.season(), roundi(player.feels_like)]
	var w1 := font.get_string_size(line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var w2 := plain.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var cw := maxf(w1 + 34.0, w2 + 34.0) + 20.0
	var cy := 14.0
	var crect := Rect2(size.x * 0.5 - cw * 0.5, cy, cw, 50)
	ci.draw_style_box(_hud_box, crect)
	Icons.draw(ci, "moon" if night else "sun", Vector2(crect.position.x + 22, cy + 17), 16.0, Color(0.75, 0.82, 1.0) if night else MenuTheme.WARN)
	ci.draw_string(font, Vector2(crect.position.x + 38, cy + 23), line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuTheme.TEXT)
	var wicon: String = {"rain": "rain", "storm": "storm", "snow": "snow", "fog": "fog_icon", "cloudy": "cloud"}.get(wk, "sun" if not night else "moon")
	Icons.draw(ci, wicon, Vector2(crect.position.x + 22, cy + 37), 13.0, MenuTheme.DIM.lightened(0.2))
	ci.draw_string(plain, Vector2(crect.position.x + 38, cy + 42), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MenuTheme.DIM.lightened(0.2))
	# The other players.
	var pt := _players_text()
	if pt != "":
		var pw := plain.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var prect := Rect2(size.x * 0.5 - pw * 0.5 - 24, crect.end.y + 6, pw + 44, 26)
		ci.draw_style_box(_hud_box, prect)
		Icons.draw(ci, "person", Vector2(prect.position.x + 16, prect.position.y + 13), 13.0, MenuTheme.DIM.lightened(0.2))
		ci.draw_string(plain, Vector2(prect.position.x + 30, prect.position.y + 18), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MenuTheme.TEXT)
	# Messages: a pill near the bottom.
	if _toast_t > 0.0 and _toast_text != "":
		var a := clampf(_toast_t * 2.0, 0.0, 1.0)
		var tw := font.get_string_size(_toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var tr := Rect2(size.x * 0.5 - tw * 0.5 - 20, size.y - (200.0 if touch else 150.0), tw + 40, 38)
		var sb: StyleBoxFlat = _pill_box
		sb.bg_color = Color(0.04, 0.045, 0.05, 0.8 * a)
		sb.border_color = Color(1, 1, 1, 0.1 * a)
		ci.draw_style_box(sb, tr)
		ci.draw_string(font, Vector2(tr.position.x + 20, tr.position.y + 25), _toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(MenuTheme.TEXT, a))


## Blur, fading colour and a heartbeat vignette as the infection takes
## hold; a red vignette when badly hurt.
func _update_sick(delta: float) -> void:
	var amount := player.body.symptoms() if not player.dead else 0.0
	var hurt := clampf((35.0 - player.health) / 35.0, 0.0, 1.0) if not player.dead else 0.0
	var blur := clampf((player.fatigue - 75.0) / 25.0, 0.0, 1.0) + player.body.sick * 0.4
	var chill := clampf((player.cold - 40.0) / 60.0, 0.0, 1.0)
	_sick_mat.set_shader_parameter("blur", blur)
	_sick_mat.set_shader_parameter("chill", chill)
	_sick.visible = (amount > 0.01 or hurt > 0.01 or blur > 0.01 or chill > 0.01) and player.active
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
		_draw_prompt(ci, Vector2(c.x, size.y - 210.0), font)
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


## "[E] Open door" in a pill under the crosshair, with the right glyph for
## the device in use; while interact is held on something holdable, a ring
## fills around the glyph.
func _draw_prompt(ci: Control, c: Vector2, font: Font) -> void:
	if player.prompt == "":
		return
	var bold := MenuTheme.bold_font()
	var fs := 17
	var action := player.prompt_action
	var tw := bold.get_string_size(player.prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var gw := 0.0 if GameState.uses_touch() and not GameState.using_gamepad() else InputGlyphs.width(action, font, 26.0)
	var inner := tw + (gw + 10.0 if gw > 0.0 else 0.0)
	var y := c.y + 54.0
	var r := Rect2(c.x - inner * 0.5 - 16.0, y, inner + 32.0, 40.0)
	ci.draw_style_box(_prompt_box, r)
	var x := r.position.x + 16.0
	if gw > 0.0:
		InputGlyphs.draw(ci, action, Vector2(x, y + 7), 26.0, font)
		x += gw + 10.0
	ci.draw_string(bold, Vector2(x, y + 26), player.prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	var hold := player.hold_progress()
	if hold > 0.0:
		var rr := Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x * hold, 4))
		ci.draw_rect(rr, MenuTheme.WARN)
	var ny := r.end.y + 6.0
	if player.hold_prompt != "":
		var hint := "Hold to %s" % player.hold_prompt
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		ci.draw_string_outline(font, Vector2(c.x - hw * 0.5, ny + 14), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.7))
		ci.draw_string(font, Vector2(c.x - hw * 0.5, ny + 14), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MenuTheme.WARN.lightened(0.3))
		ny += 22.0
	# The second action (reload button), with its own glyph.
	if player.alt_prompt != "":
		var aw := font.get_string_size(player.alt_prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var agw := 0.0 if GameState.uses_touch() and not GameState.using_gamepad() else InputGlyphs.width("reload", font, 22.0)
		var ainner := aw + (agw + 8.0 if agw > 0.0 else 0.0)
		var ar := Rect2(c.x - ainner * 0.5 - 12.0, ny, ainner + 24.0, 32.0)
		ci.draw_style_box(_prompt_box, ar)
		var ax := ar.position.x + 12.0
		if agw > 0.0:
			InputGlyphs.draw(ci, "reload", Vector2(ax, ny + 5), 22.0, font)
			ax += agw + 8.0
		ci.draw_string(font, Vector2(ax, ny + 21), player.alt_prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MenuTheme.TEXT)


## Driving: speed, fuel, condition and warnings (bottom-right, or top-left
## on touch like the weapon panel).
func _draw_vehicle_panel(ci: Control, size: Vector2, font: Font, v: Vehicle) -> void:
	var touch := GameState.uses_touch() and not GameState.using_gamepad()
	var card := Rect2(Vector2(16, _weapon_y) if touch else Vector2(size.x - 316, size.y - 136), Vector2(300, 120))
	ci.draw_style_box(_hud_box, card)
	var bold := MenuTheme.bold_font()
	var pos := card.position
	ci.draw_string(bold, pos + Vector2(14, 26), str(v.def.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 180, 15, MenuTheme.DIM.lightened(0.3))
	var kmh := int(absf(v.speed) * 3.6)
	var sp := "%d" % kmh
	ci.draw_string(bold, pos + Vector2(14, 70), sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.WHITE)
	var spw := bold.get_string_size(sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	ci.draw_string(font, pos + Vector2(20 + spw, 70), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MenuTheme.DIM)
	# Fuel and condition gauges on the right.
	var gx := pos.x + 160
	var rows := []
	if v.def.fuel != "":
		rows.append(["Fuel", float(v.rec.fuel) / maxf(1.0, float(v.def.tank)), MenuTheme.WARN])
	rows.append(["Condition", float(v.rec.hp) / maxf(1.0, float(v.def.hp)), MenuTheme.GOOD])
	var gy := pos.y + 44
	for r in rows:
		var f := clampf(float(r[1]), 0.0, 1.0)
		var col: Color = r[2] if f > 0.15 else MenuTheme.BAD
		ci.draw_string(font, Vector2(gx, gy), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MenuTheme.DIM)
		ci.draw_rect(Rect2(gx, gy + 5, 124, 6), Color(0, 0, 0, 0.5))
		ci.draw_rect(Rect2(gx, gy + 5, 124 * f, 6), col)
		gy += 30
	var warn := ""
	if float(v.rec.hp) <= 0.0:
		warn = "Wrecked"
	elif v.def.fuel != "" and not v.running and player.seat == 0:
		warn = "Engine off - %s" % ("press reload to start" if not GameState.uses_touch() else "tap START")
	elif v.def.fuel != "" and float(v.rec.fuel) < float(v.def.tank) * 0.1:
		warn = "Low fuel"
	elif v.kind == "plane":
		warn = ("Throttle %d%%" % int(v.throttle * 100.0)) + ("" if v.airborne else ("   take off at %d km/h" % int(float(v.def.takeoff) * 3.6)))
	elif v.kind == "heli":
		warn = "Altitude %d m" % int(v.global_position.y - gen_height(v.global_position))
	if warn != "":
		ci.draw_string(bold, pos + Vector2(14, 104), warn, HORIZONTAL_ALIGNMENT_LEFT, 280, 13, MenuTheme.WARN)


func gen_height(p: Vector3) -> float:
	return player.gen.height(p.x, p.z) if player.gen else 0.0


## Current weapon, rounds and condition, with the item's picture.
## Bottom-right on desktop and gamepad; top-left under the bars on touch
## (the buttons own the bottom-right).
func _draw_weapon_panel(ci: Control, size: Vector2, font: Font, w: Weapons) -> void:
	var st := w.status()
	if st.name == "":
		return
	var touch := GameState.uses_touch() and not GameState.using_gamepad()
	var card := Rect2(Vector2(16, _weapon_y) if touch else Vector2(size.x - 296, size.y - 92), Vector2(280, 76))
	ci.draw_style_box(_hud_box, card)
	var pos := card.position
	var bold := MenuTheme.bold_font()
	# Picture.
	var pic := Rect2(pos + Vector2(8, 8), Vector2(92, 60))
	ci.draw_rect(pic, Color(1, 1, 1, 0.04))
	var it := w.item()
	var id: String = it.get("id", "")
	if ItemIcons.texture and ItemIcons.regions.has(id):
		var reg: Rect2 = ItemIcons.regions[id]
		var k := minf(pic.size.x / reg.size.x, pic.size.y / reg.size.y) * 0.95
		var dsz := reg.size * k
		ci.draw_texture_rect_region(ItemIcons.texture, Rect2(pic.get_center() - dsz * 0.5, dsz), reg)
	else:
		Icons.draw(ci, {"gun": "gun", "bow": "bow", "throw": "throw"}.get(w.def().get("cat", ""), "fist"), pic.get_center(), 34.0, MenuTheme.DIM)
	var tx := pos.x + 110
	ci.draw_string(bold, Vector2(tx, pos.y + 26), str(st.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 160, 14, MenuTheme.TEXT)
	if st.ammo != "":
		var parts := str(st.ammo).split(" / ")
		ci.draw_string(bold, Vector2(tx, pos.y + 56), parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
		if parts.size() > 1:
			var aw := bold.get_string_size(parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
			ci.draw_string(font, Vector2(tx + aw + 6, pos.y + 56), "/ " + parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MenuTheme.DIM)
	if st.state != "":
		ci.draw_string(bold, Vector2(tx + 70, pos.y + 54), st.state, HORIZONTAL_ALIGNMENT_LEFT, 100, 12, MenuTheme.BAD.lightened(0.2))
	if float(st.cond) >= 0.0:
		var c := float(st.cond)
		var bar := Rect2(tx, pos.y + 64, 158, 4)
		ci.draw_rect(bar, Color(0, 0, 0, 0.5))
		ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * c, bar.size.y)), MenuTheme.GOOD if c > 0.5 else (MenuTheme.WARN if c > 0.25 else MenuTheme.BAD))
	# Slot hints for keyboard / gamepad.
	if not touch:
		if GameState.using_gamepad():
			InputGlyphs.draw(ci, "weapon_prev", Vector2(card.end.x - 34, pos.y - 30), 24.0, font)
		else:
			ci.draw_string(font, Vector2(card.end.x - 80, pos.y - 8), "1-4 / wheel", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.45))
