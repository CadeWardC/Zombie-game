class_name MenuBackdrop
extends Control
## The menus' background: a dead town at dusk, drawn in code. A dark sky
## with a low red glow, a pale moon, two layers of skyline with a few lit
## windows, power lines and drifting fog. Cheap: a handful of polygons.

var _t := 0.0
var _far: Array = [] # [x, width, height] in fractions of the screen.
var _near: Array = []
var _windows: Array = [] # [layer, building index, fx, fy] lit windows.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var x := -0.02
	while x < 1.05:
		var w := rng.randf_range(0.03, 0.08)
		_far.append([x, w, rng.randf_range(0.08, 0.24)])
		x += w + rng.randf_range(0.0, 0.01)
	x = -0.03
	while x < 1.05:
		var w := rng.randf_range(0.05, 0.12)
		var h := rng.randf_range(0.1, 0.3)
		if rng.randf() < 0.12:
			h = rng.randf_range(0.34, 0.42) # A tower.
		_near.append([x, w, h, rng.randf() < 0.3])
		x += w + rng.randf_range(0.005, 0.03)
	for k in 26:
		var b := rng.randi() % _near.size()
		_windows.append([b, rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.8), rng.randf()])


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	# Sky: dark blue-grey at the top to a dirty red glow at the horizon.
	var horizon := s.y * 0.72
	var bands := 24
	for k in bands:
		var f0 := float(k) / bands
		var top := Color(0.045, 0.055, 0.07)
		var low := Color(0.22, 0.09, 0.07)
		var col := top.lerp(low, pow(f0, 2.2))
		draw_rect(Rect2(0, horizon * f0, s.x, horizon / bands + 1.0), col)
	draw_rect(Rect2(0, horizon, s.x, s.y - horizon), Color(0.03, 0.03, 0.035))
	# Moon with a soft halo.
	var moon := Vector2(s.x * 0.78, s.y * 0.2)
	for k in 16:
		draw_circle(moon, s.y * (0.18 - k * 0.008), Color(0.85, 0.82, 0.75, 0.008))
	draw_circle(moon, s.y * 0.05, Color(0.86, 0.84, 0.78))
	draw_circle(moon + Vector2(-0.012, -0.01) * s.y, s.y * 0.012, Color(0.76, 0.74, 0.69))
	draw_circle(moon + Vector2(0.018, 0.014) * s.y, s.y * 0.008, Color(0.78, 0.76, 0.7))
	# Far skyline.
	for b in _far:
		var r := Rect2(b[0] * s.x, horizon - b[2] * s.y, b[1] * s.x, b[2] * s.y + 2)
		draw_rect(r, Color(0.09, 0.075, 0.08))
	# Power lines along the horizon.
	var pole_col := Color(0.04, 0.04, 0.045)
	var poles := []
	for k in 7:
		poles.append(Vector2(s.x * (k * 0.18 - 0.04), horizon - s.y * 0.13))
	for k in poles.size():
		var p: Vector2 = poles[k]
		draw_line(p, Vector2(p.x, horizon + 4), pole_col, 3.0)
		draw_line(p + Vector2(-14, 6), p + Vector2(14, 6), pole_col, 2.0)
		if k > 0:
			var a: Vector2 = poles[k - 1]
			for off in [6.0, 10.0]:
				var pts := PackedVector2Array()
				for j in 13:
					var t := j / 12.0
					pts.append(a.lerp(p, t) + Vector2(0, off + sin(t * PI) * 18.0))
				draw_polyline(pts, pole_col, 1.2)
	# Near skyline with lit windows (a few flicker).
	for i in _near.size():
		var b: Array = _near[i]
		var r := Rect2(b[0] * s.x, horizon - b[2] * s.y, b[1] * s.x, b[2] * s.y + 2)
		draw_rect(r, Color(0.035, 0.035, 0.04))
		if b[3]:
			# Flat roof clutter: a water tank.
			draw_rect(Rect2(r.position + Vector2(r.size.x * 0.6, -14), Vector2(18, 14)), Color(0.035, 0.035, 0.04))
	for wdw in _windows:
		var b: Array = _near[wdw[0]]
		var r := Rect2(b[0] * s.x, horizon - b[2] * s.y, b[1] * s.x, b[2] * s.y)
		var on := 1.0 if wdw[3] > 0.2 else (0.4 + 0.6 * float(sin(_t * 9.0 + wdw[3] * 40.0) > 0.0))
		draw_rect(Rect2(r.position + Vector2(r.size.x * wdw[1], r.size.y * wdw[2]), Vector2(5, 7)), Color(0.95, 0.72, 0.35, 0.75 * on))
	# Drifting fog: long, faint bands with soft ends, low over the town.
	for k in 5:
		var y := horizon - s.y * 0.08 + k * s.y * 0.04
		var drift := fmod(_t * (5.0 + k * 2.5) + k * 170.0, s.x * 0.7)
		for j in 3:
			var x0 := -s.x * 0.4 + drift + j * s.x * 0.7
			_fog(Rect2(x0, y, s.x * 0.6, s.y * 0.05), 0.05)
	# Vignette.
	for k in 10:
		var a := 0.06 * k / 10.0
		var m := k * 0.012
		draw_rect(Rect2(0, 0, s.x * (0.05 + m), s.y), Color(0, 0, 0, a * 0.5))
		draw_rect(Rect2(s.x * (0.95 - m), 0, s.x * (0.05 + m), s.y), Color(0, 0, 0, a * 0.5))
	draw_rect(Rect2(0, 0, s.x * 0.5, s.y), Color(0, 0, 0, 0.0))


## A soft fog band: clear at the ends and edges, densest in the middle.
func _fog(r: Rect2, a: float) -> void:
	var mid := r.position.y + r.size.y * 0.5
	var c0 := Color(0.6, 0.55, 0.55, 0.0)
	var c1 := Color(0.6, 0.55, 0.55, a)
	for half in [[r.position.y, mid], [mid, r.end.y]]:
		var top: float = half[0]
		var bot: float = half[1]
		var top_a := top == mid
		var pts := PackedVector2Array([Vector2(r.position.x, top), Vector2(r.position.x + r.size.x * 0.5, top), Vector2(r.end.x, top),
			Vector2(r.end.x, bot), Vector2(r.position.x + r.size.x * 0.5, bot), Vector2(r.position.x, bot)])
		var cols := PackedColorArray([c0, c1 if top_a else c0, c0, c0, c0 if top_a else c1, c0])
		draw_polygon(pts, cols)
