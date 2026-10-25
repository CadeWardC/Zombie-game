class_name Icons
extends RefCounted
## Small vector icons for the HUD, the touch buttons and the menus, drawn
## with canvas primitives (no image files). Each icon is designed in a box
## from -1 to 1 and scaled to the size asked for.
##
## Icons.draw(canvas_item, "heart", centre, 24.0, colour)


static func draw(ci: CanvasItem, kind: String, c: Vector2, size: float, col: Color) -> void:
	var s := size * 0.5
	var w := maxf(1.5, size * 0.09) # Stroke width.
	var p := func(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for v: Vector2 in pts:
			out.append(c + v * s)
		return out
	match kind:
		"heart":
			var pts := []
			for k in 33:
				var t := k / 32.0 * TAU
				pts.append(Vector2(16.0 * pow(sin(t), 3), -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))) / 17.0 + Vector2(0, -0.05))
			ci.draw_colored_polygon(p.call(pts), col)
		"food":
			# Fork and knife.
			ci.draw_line(c + Vector2(-0.45, -0.85) * s, c + Vector2(-0.45, 0.9) * s, col, w * 1.2)
			for x: float in [-0.7, -0.45, -0.2]:
				ci.draw_line(c + Vector2(x, -0.9) * s, c + Vector2(x, -0.35) * s, col, w * 0.8)
			ci.draw_line(c + Vector2(-0.7, -0.35) * s, c + Vector2(-0.2, -0.35) * s, col, w * 0.8)
			ci.draw_colored_polygon(p.call([Vector2(0.35, -0.9), Vector2(0.7, -0.5), Vector2(0.62, 0.05), Vector2(0.45, 0.05), Vector2(0.45, 0.9), Vector2(0.3, 0.9)]), col)
		"water", "blood":
			var pts := [Vector2(0, -0.95)]
			for k in 17:
				var a := PI * (-0.15 + 1.3 * k / 16.0)
				pts.append(Vector2(cos(a) * 0.6, 0.3 + sin(a) * 0.6))
			ci.draw_colored_polygon(p.call(pts), col)
		"stamina":
			ci.draw_colored_polygon(p.call([Vector2(0.15, -0.95), Vector2(-0.55, 0.12), Vector2(-0.05, 0.12), Vector2(-0.2, 0.95), Vector2(0.55, -0.15), Vector2(0.05, -0.15)]), col)
		"bone":
			ci.draw_line(c + Vector2(-0.5, 0.5) * s, c + Vector2(0.5, -0.5) * s, col, w * 2.2)
			for v: Vector2 in [Vector2(-0.55, 0.75), Vector2(-0.75, 0.55), Vector2(0.55, -0.75), Vector2(0.75, -0.55)]:
				ci.draw_circle(c + v * s, s * 0.22, col)
		"virus":
			ci.draw_circle(c, s * 0.45, col)
			for k in 8:
				var d := Vector2.from_angle(k * TAU / 8.0)
				ci.draw_line(c + d * s * 0.4, c + d * s * 0.8, col, w)
				ci.draw_circle(c + d * s * 0.82, s * 0.12, col)
		"thermo":
			ci.draw_line(c + Vector2(0, -0.8) * s, c + Vector2(0, 0.35) * s, col, w * 2.2)
			ci.draw_circle(c + Vector2(0, 0.6) * s, s * 0.32, col)
			for y: float in [-0.5, -0.2, 0.1]:
				ci.draw_line(c + Vector2(0.22, y) * s, c + Vector2(0.45, y) * s, col, w * 0.7)
		"snow":
			for k in 3:
				var d := Vector2.from_angle(k * PI / 3.0 + PI * 0.5)
				ci.draw_line(c - d * s * 0.9, c + d * s * 0.9, col, w)
				for sgn: float in [-1.0, 1.0]:
					var e := c + d * s * 0.55 * sgn
					ci.draw_line(e, e + d.rotated(0.7) * s * 0.28 * sgn, col, w * 0.8)
					ci.draw_line(e, e + d.rotated(-0.7) * s * 0.28 * sgn, col, w * 0.8)
		"wet":
			for v: Vector2 in [Vector2(-0.45, -0.25), Vector2(0.4, -0.45), Vector2(0.05, 0.4)]:
				var pts := [v + Vector2(0, -0.45)]
				for k in 9:
					var a := PI * (-0.15 + 1.3 * k / 8.0)
					pts.append(v + Vector2(cos(a), sin(a)) * 0.28 + Vector2(0, 0.05))
				ci.draw_colored_polygon(p.call(pts), col)
		"moon", "tired":
			var pts := []
			for k in 25:
				var a := PI * (0.35 + 1.3 * k / 24.0)
				pts.append(Vector2(cos(a), sin(a)) * 0.85)
			for k in 25:
				var a := PI * (1.65 - 1.3 * k / 24.0)
				pts.append(Vector2(0.38, -0.15) + Vector2(cos(a), sin(a)) * 0.7)
			ci.draw_colored_polygon(p.call(pts), col)
			if kind == "tired":
				_text_z(ci, c + Vector2(0.55, -0.55) * s, s * 0.45, col, w * 0.6)
		"sun":
			ci.draw_circle(c, s * 0.42, col)
			for k in 8:
				var d := Vector2.from_angle(k * TAU / 8.0)
				ci.draw_line(c + d * s * 0.6, c + d * s * 0.92, col, w)
		"cloud", "rain", "storm", "fog_icon":
			var cc := c + Vector2(0, -0.12) * s
			ci.draw_circle(cc + Vector2(-0.38, 0.12) * s, s * 0.32, col)
			ci.draw_circle(cc + Vector2(0.05, -0.12) * s, s * 0.42, col)
			ci.draw_circle(cc + Vector2(0.45, 0.12) * s, s * 0.3, col)
			ci.draw_rect(Rect2(cc + Vector2(-0.38, 0.1) * s, Vector2(0.83, 0.34) * s), col)
			if kind == "rain":
				for x: float in [-0.4, 0.0, 0.4]:
					ci.draw_line(c + Vector2(x, 0.5) * s, c + Vector2(x - 0.15, 0.9) * s, col, w * 0.8)
			elif kind == "storm":
				ci.draw_colored_polygon(p.call([Vector2(0.05, 0.35), Vector2(-0.25, 0.7), Vector2(0.0, 0.7), Vector2(-0.12, 1.0), Vector2(0.28, 0.6), Vector2(0.02, 0.6)]), col)
			elif kind == "fog_icon":
				for y: float in [0.55, 0.8]:
					ci.draw_line(c + Vector2(-0.8, y) * s, c + Vector2(0.8, y) * s, col, w * 0.8)
		"pain":
			var pts := []
			for k in 16:
				pts.append(Vector2.from_angle(k * TAU / 16.0 - PI * 0.5) * (0.95 if k % 2 == 0 else 0.45))
			ci.draw_colored_polygon(p.call(pts), col)
		"nausea":
			var last := c
			for k in 40:
				var a := k * 0.42
				var pt := c + Vector2(cos(a), sin(a)) * (k / 40.0 * 0.85) * s
				if k > 0:
					ci.draw_line(last, pt, col, w)
				last = pt
		"hand", "grab":
			# An open hand: palm, four fingers and a thumb, all rounded.
			var fw := s * 0.2
			var palm := Rect2(c + Vector2(-0.48, -0.05) * s, Vector2(0.86, 0.75) * s)
			ci.draw_rect(palm.grow_individual(0, -fw * 0.5, 0, -fw * 0.5), col)
			ci.draw_rect(palm.grow_individual(-fw * 0.5, 0, -fw * 0.5, 0), col)
			for v: Vector2 in [palm.position, Vector2(palm.end.x, palm.position.y), palm.end, Vector2(palm.position.x, palm.end.y)]:
				ci.draw_circle(v + (palm.get_center() - v).sign() * fw * 0.5, fw * 0.5, col)
			for k in 4:
				var x := -0.38 + k * 0.22
				var top := -0.62 - (0.18 if k == 1 or k == 2 else 0.0) + (0.1 if k == 3 else 0.0)
				var a := c + Vector2(x, 0.05) * s
				var b := c + Vector2(x, top) * s
				ci.draw_line(a, b, col, fw * 0.9)
				ci.draw_circle(b, fw * 0.45, col)
			var ta := c + Vector2(-0.4, 0.4) * s
			var tb := c + Vector2(-0.82, -0.05) * s
			ci.draw_line(ta, tb, col, fw * 0.9)
			ci.draw_circle(tb, fw * 0.45, col)
		"fist":
			# A blade: melee attack.
			ci.draw_colored_polygon(p.call([Vector2(0.85, -0.85), Vector2(0.95, -0.95), Vector2(0.5, -0.2), Vector2(-0.1, 0.4), Vector2(-0.3, 0.2), Vector2(0.3, -0.4)]), col)
			ci.draw_line(c + Vector2(-0.45, 0.05) * s, c + Vector2(0.05, 0.55) * s, col, w * 1.3)
			ci.draw_line(c + Vector2(-0.2, 0.3) * s, c + Vector2(-0.75, 0.85) * s, col, w * 1.8)
		"crosshair", "aim":
			ci.draw_arc(c, s * 0.6, 0, TAU, 28, col, w)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * s * 0.3, c + d * s * 0.95, col, w)
			ci.draw_circle(c, s * 0.1, col)
		"reload":
			ci.draw_arc(c, s * 0.62, -PI * 0.35, PI * 1.35, 24, col, w * 1.2)
			var tip := c + Vector2.from_angle(-PI * 0.35) * s * 0.62
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(0.35, 0.05) * s, tip + Vector2(-0.15, -0.35) * s, tip + Vector2(-0.12, 0.25) * s]), col)
		"shove":
			ci.draw_line(c + Vector2(-0.8, 0) * s, c + Vector2(0.2, 0) * s, col, w * 1.4)
			ci.draw_colored_polygon(p.call([Vector2(0.15, -0.45), Vector2(0.65, 0), Vector2(0.15, 0.45)]), col)
			ci.draw_line(c + Vector2(0.85, -0.7) * s, c + Vector2(0.85, 0.7) * s, col, w * 1.4)
		"jump":
			ci.draw_polyline(p.call([Vector2(-0.65, 0.1), Vector2(0, -0.55), Vector2(0.65, 0.1)]), col, w * 1.4)
			ci.draw_line(c + Vector2(-0.6, 0.7) * s, c + Vector2(0.6, 0.7) * s, col, w * 1.2)
		"crouch":
			ci.draw_polyline(p.call([Vector2(-0.65, -0.35), Vector2(0, 0.3), Vector2(0.65, -0.35)]), col, w * 1.4)
			ci.draw_line(c + Vector2(-0.6, 0.75) * s, c + Vector2(0.6, 0.75) * s, col, w * 1.2)
		"stand":
			ci.draw_polyline(p.call([Vector2(-0.65, 0.35), Vector2(0, -0.3), Vector2(0.65, 0.35)]), col, w * 1.4)
			ci.draw_line(c + Vector2(-0.6, -0.75) * s, c + Vector2(0.6, -0.75) * s, col, w * 1.2)
		"run":
			for x: float in [-0.35, 0.25]:
				ci.draw_polyline(p.call([Vector2(x - 0.3, -0.6), Vector2(x + 0.3, 0), Vector2(x - 0.3, 0.6)]), col, w * 1.4)
		"bag":
			ci.draw_rect(Rect2(c + Vector2(-0.6, -0.45) * s, Vector2(1.2, 1.35) * s), col)
			ci.draw_arc(c + Vector2(0, -0.45) * s, s * 0.32, PI, TAU, 12, col, w)
			ci.draw_rect(Rect2(c + Vector2(-0.38, 0.2) * s, Vector2(0.76, 0.45) * s), Color(0, 0, 0, 0.35))
		"swap":
			ci.draw_line(c + Vector2(-0.75, -0.35) * s, c + Vector2(0.5, -0.35) * s, col, w * 1.2)
			ci.draw_colored_polygon(p.call([Vector2(0.4, -0.65), Vector2(0.85, -0.35), Vector2(0.4, -0.05)]), col)
			ci.draw_line(c + Vector2(0.75, 0.35) * s, c + Vector2(-0.5, 0.35) * s, col, w * 1.2)
			ci.draw_colored_polygon(p.call([Vector2(-0.4, 0.05), Vector2(-0.85, 0.35), Vector2(-0.4, 0.65)]), col)
		"cross", "heal":
			ci.draw_rect(Rect2(c + Vector2(-0.25, -0.8) * s, Vector2(0.5, 1.6) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-0.8, -0.25) * s, Vector2(1.6, 0.5) * s), col)
		"can", "eat":
			ci.draw_rect(Rect2(c + Vector2(-0.5, -0.65) * s, Vector2(1.0, 1.4) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-0.5, -0.3) * s, Vector2(1.0, 0.6) * s), Color(0, 0, 0, 0.35))
			ci.draw_line(c + Vector2(-0.5, -0.65) * s, c + Vector2(0.5, -0.65) * s, col.lightened(0.3), w)
		"torch", "light":
			ci.draw_colored_polygon(p.call([Vector2(-0.25, 0.9), Vector2(0.25, 0.9), Vector2(0.25, -0.05), Vector2(0.5, -0.4), Vector2(-0.5, -0.4), Vector2(-0.25, -0.05)]), col)
			for k in 3:
				var a := -PI * 0.5 + (k - 1) * 0.5
				ci.draw_line(c + Vector2(0, -0.55) * s + Vector2.from_angle(a) * s * 0.1, c + Vector2(0, -0.55) * s + Vector2.from_angle(a) * s * 0.45, col, w * 0.8)
		"pause":
			ci.draw_rect(Rect2(c + Vector2(-0.5, -0.6) * s, Vector2(0.32, 1.2) * s), col)
			ci.draw_rect(Rect2(c + Vector2(0.18, -0.6) * s, Vector2(0.32, 1.2) * s), col)
		"ping":
			var pts := [Vector2(0, 0.95)]
			for k in 17:
				var a := PI * (0.8 - 1.6 * k / 16.0) - PI * 0.5 + PI
				pts.append(Vector2(0, -0.25) + Vector2(cos(a), sin(a)) * 0.6)
			ci.draw_colored_polygon(p.call(pts), col)
			ci.draw_circle(c + Vector2(0, -0.25) * s, s * 0.22, Color(0, 0, 0, 0.45))
		"gun":
			ci.draw_rect(Rect2(c + Vector2(-0.85, -0.45) * s, Vector2(1.7, 0.42) * s), col)
			ci.draw_colored_polygon(p.call([Vector2(-0.55, -0.05), Vector2(-0.15, -0.05), Vector2(-0.3, 0.8), Vector2(-0.7, 0.8)]), col)
		"bow":
			ci.draw_arc(c + Vector2(0.45, 0) * s, s * 0.95, PI * 0.62, PI * 1.38, 16, col, w * 1.2)
			ci.draw_line(c + Vector2(-0.3, -0.85) * s, c + Vector2(-0.3, 0.85) * s, col, w * 0.6)
			ci.draw_line(c + Vector2(-0.3, 0) * s, c + Vector2(0.9, 0) * s, col, w * 0.9)
		"throw":
			ci.draw_circle(c + Vector2(0.25, 0.25) * s, s * 0.45, col)
			ci.draw_arc(c + Vector2(0.25, 0.25) * s, s * 0.85, PI * 1.05, PI * 1.45, 10, col, w)
		"horn":
			ci.draw_colored_polygon(p.call([Vector2(-0.8, -0.25), Vector2(-0.35, -0.25), Vector2(0.4, -0.75), Vector2(0.4, 0.75), Vector2(-0.35, 0.25), Vector2(-0.8, 0.25)]), col)
			ci.draw_arc(c + Vector2(0.45, 0) * s, s * 0.45, -0.7, 0.7, 8, col, w * 0.8)
		"exit":
			ci.draw_rect(Rect2(c + Vector2(-0.75, -0.8) * s, Vector2(0.9, 1.6) * s), col, false, w)
			ci.draw_line(c + Vector2(-0.1, 0) * s, c + Vector2(0.85, 0) * s, col, w * 1.2)
			ci.draw_colored_polygon(p.call([Vector2(0.5, -0.32), Vector2(0.95, 0), Vector2(0.5, 0.32)]), col)
		"up":
			ci.draw_colored_polygon(p.call([Vector2(0, -0.8), Vector2(0.7, 0.3), Vector2(-0.7, 0.3)]), col)
		"down":
			ci.draw_colored_polygon(p.call([Vector2(0, 0.8), Vector2(0.7, -0.3), Vector2(-0.7, -0.3)]), col)
		"brake":
			ci.draw_arc(c, s * 0.75, 0, TAU, 24, col, w * 1.2)
			ci.draw_rect(Rect2(c + Vector2(-0.12, -0.45) * s, Vector2(0.24, 0.6) * s), col)
			ci.draw_circle(c + Vector2(0, 0.4) * s, s * 0.12, col)
		"key":
			ci.draw_arc(c + Vector2(-0.4, 0) * s, s * 0.35, 0, TAU, 16, col, w * 1.2)
			ci.draw_line(c + Vector2(-0.05, 0) * s, c + Vector2(0.85, 0) * s, col, w * 1.2)
			ci.draw_line(c + Vector2(0.6, 0) * s, c + Vector2(0.6, 0.35) * s, col, w * 1.2)
		"place":
			ci.draw_rect(Rect2(c + Vector2(-0.7, -0.7) * s, Vector2(1.4, 1.4) * s), col, false, w)
			ci.draw_line(c + Vector2(0, -0.4) * s, c + Vector2(0, 0.4) * s, col, w)
			ci.draw_line(c + Vector2(-0.4, 0) * s, c + Vector2(0.4, 0) * s, col, w)
		"close":
			ci.draw_line(c + Vector2(-0.6, -0.6) * s, c + Vector2(0.6, 0.6) * s, col, w * 1.4)
			ci.draw_line(c + Vector2(0.6, -0.6) * s, c + Vector2(-0.6, 0.6) * s, col, w * 1.4)
		"check":
			ci.draw_polyline(p.call([Vector2(-0.7, 0.05), Vector2(-0.2, 0.55), Vector2(0.75, -0.5)]), col, w * 1.4)
		"eye":
			var pts := []
			for k in 13:
				var t := k / 12.0
				pts.append(Vector2(lerpf(-0.95, 0.95, t), -sin(t * PI) * 0.55))
			for k in range(12, -1, -1):
				var t := k / 12.0
				pts.append(Vector2(lerpf(-0.95, 0.95, t), sin(t * PI) * 0.55))
			ci.draw_polyline(p.call(pts), col, w)
			ci.draw_circle(c, s * 0.28, col)
		"skull":
			ci.draw_circle(c + Vector2(0, -0.15) * s, s * 0.65, col)
			ci.draw_rect(Rect2(c + Vector2(-0.38, 0.3) * s, Vector2(0.76, 0.5) * s), col)
			for x: float in [-0.25, 0.25]:
				ci.draw_circle(c + Vector2(x, -0.1) * s, s * 0.17, Color(0, 0, 0, 0.75))
		"hammer", "craft":
			ci.draw_line(c + Vector2(-0.6, 0.75) * s, c + Vector2(0.25, -0.2) * s, col, w * 1.6)
			ci.draw_colored_polygon(p.call([Vector2(-0.05, -0.65), Vector2(0.35, -0.95), Vector2(0.95, -0.35), Vector2(0.65, -0.05), Vector2(0.4, -0.3), Vector2(0.15, -0.3)]), col)
		"map":
			ci.draw_colored_polygon(p.call([Vector2(-0.85, -0.6), Vector2(-0.3, -0.8), Vector2(0.3, -0.6), Vector2(0.85, -0.8), Vector2(0.85, 0.6), Vector2(0.3, 0.8), Vector2(-0.3, 0.6), Vector2(-0.85, 0.8)]), col)
			ci.draw_line(c + Vector2(-0.3, -0.8) * s, c + Vector2(-0.3, 0.6) * s, Color(0, 0, 0, 0.35), w * 0.6)
			ci.draw_line(c + Vector2(0.3, -0.6) * s, c + Vector2(0.3, 0.8) * s, Color(0, 0, 0, 0.35), w * 0.6)
		"gear":
			ci.draw_circle(c, s * 0.55, col)
			for k in 8:
				var d := Vector2.from_angle(k * TAU / 8.0)
				ci.draw_line(c + d * s * 0.5, c + d * s * 0.9, col, w * 2.0)
			ci.draw_circle(c, s * 0.22, Color(0, 0, 0, 0.5))
		"house":
			ci.draw_colored_polygon(p.call([Vector2(0, -0.9), Vector2(0.9, -0.05), Vector2(0.65, -0.05), Vector2(0.65, 0.85), Vector2(-0.65, 0.85), Vector2(-0.65, -0.05), Vector2(-0.9, -0.05)]), col)
		"person":
			ci.draw_circle(c + Vector2(0, -0.5) * s, s * 0.32, col)
			ci.draw_colored_polygon(p.call([Vector2(-0.65, 0.9), Vector2(-0.55, 0.15), Vector2(0, -0.1), Vector2(0.55, 0.15), Vector2(0.65, 0.9)]), col)
		_:
			ci.draw_circle(c, s * 0.4, col)


## A small "z" for the tired icon.
static func _text_z(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	ci.draw_polyline(PackedVector2Array([c + Vector2(-0.5, -0.5) * s, c + Vector2(0.5, -0.5) * s, c + Vector2(-0.5, 0.5) * s, c + Vector2(0.5, 0.5) * s]), col, w)


## A control that shows one icon (for menus built from containers).
class IconRect extends Control:
	var kind := ""
	var color := Color.WHITE

	func _init(p_kind := "", p_color := Color.WHITE, p_size := 24.0) -> void:
		kind = p_kind
		color = p_color
		custom_minimum_size = Vector2(p_size, p_size)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Icons.draw(self, kind, size * 0.5, minf(size.x, size.y), color)
