class_name CarModels
extends RefCounted
## Realistic low-poly vehicles, built by extruding side profiles.
## Vehicle local space: +Z is the front, Y up, origin on the ground at the
## centre of the wheelbase.

const GLASS := Color(0.1, 0.13, 0.16)
const TIRE := Color(0.07, 0.07, 0.07)
const RIM := Color(0.62, 0.63, 0.64)
const CHROME := Color(0.7, 0.7, 0.72)
const HEAD := Color(0.92, 0.9, 0.78)
const TAIL := Color(0.6, 0.06, 0.05)
const PAINTS := [Color(0.62, 0.1, 0.08), Color(0.12, 0.2, 0.42), Color(0.8, 0.8, 0.78), Color(0.1, 0.1, 0.11),
	Color(0.45, 0.46, 0.47), Color(0.22, 0.32, 0.22), Color(0.55, 0.45, 0.28), Color(0.3, 0.16, 0.12)]
const TYPES := ["sedan", "hatchback", "suv", "pickup", "van", "sedan", "suv", "police", "wreck"]


## Builds a vehicle. `dirt` (0..1) darkens and muddies the paint.
static func build(type: String, paint: Color, dirt := 0.3) -> MeshData:
	var m := MeshData.new()
	paint = paint.lerp(Color(0.35, 0.3, 0.24), dirt * 0.35)
	match type:
		"sedan", "police", "wreck":
			var lower := [Vector2(2.35, 0.32), Vector2(2.4, 0.6), Vector2(2.15, 0.82), Vector2(1.0, 0.95), Vector2(-1.55, 0.98),
					Vector2(-2.3, 0.93), Vector2(-2.38, 0.62), Vector2(-2.3, 0.32)]
			var cabin := [Vector2(1.0, 0.95), Vector2(0.25, 1.42), Vector2(-0.95, 1.42), Vector2(-1.6, 0.98)]
			var body := paint
			if type == "wreck":
				body = Color(0.24, 0.18, 0.15).lerp(paint, 0.15)
			_vehicle(m, lower, cabin, 0.9, 0.78, body, type == "wreck")
			_wheels(m, [1.35, -1.4], 0.86, 0.33, type == "wreck")
			if type == "police":
				# Black and white doors, light bar.
				_side_panel(m, Vector2(0.9, -1.1), 0.5, 0.92, 0.905, Color(0.92, 0.92, 0.9))
				_lightbar(m, Vector3(0, 1.44, -0.35), 1.1)
		"hatchback":
			var lower := [Vector2(2.0, 0.32), Vector2(2.05, 0.6), Vector2(1.8, 0.8), Vector2(0.8, 0.93), Vector2(-1.85, 0.97),
					Vector2(-2.0, 0.9), Vector2(-2.0, 0.32)]
			var cabin := [Vector2(0.8, 0.93), Vector2(0.05, 1.4), Vector2(-1.6, 1.38), Vector2(-1.9, 0.97)]
			_vehicle(m, lower, cabin, 0.86, 0.76, paint, false)
			_wheels(m, [1.2, -1.25], 0.82, 0.31, false)
		"suv":
			var lower := [Vector2(2.4, 0.42), Vector2(2.45, 0.78), Vector2(2.2, 1.02), Vector2(1.15, 1.12), Vector2(-2.3, 1.15),
					Vector2(-2.42, 1.05), Vector2(-2.42, 0.42)]
			var cabin := [Vector2(1.15, 1.12), Vector2(0.4, 1.78), Vector2(-2.2, 1.78), Vector2(-2.35, 1.15)]
			_vehicle(m, lower, cabin, 0.95, 0.86, paint, false)
			_wheels(m, [1.45, -1.5], 0.92, 0.4, false)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.82, -0.8)), Vector3(1.4, 0.05, 2.0), CHROME.darkened(0.3))
		"pickup":
			var lower := [Vector2(2.75, 0.45), Vector2(2.8, 0.8), Vector2(2.5, 1.05), Vector2(1.3, 1.12), Vector2(-2.7, 1.12),
					Vector2(-2.75, 0.45)]
			var cabin := [Vector2(1.3, 1.12), Vector2(0.65, 1.8), Vector2(-0.6, 1.8), Vector2(-0.7, 1.12)]
			_vehicle(m, lower, cabin, 0.97, 0.88, paint, false)
			_wheels(m, [1.75, -1.75], 0.95, 0.42, false)
			# Open bed.
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.13, -1.75)), Vector3(1.75, 0.04, 1.85), paint.darkened(0.4))
			for x: float in [-0.92, 0.92]:
				m.box(Transform3D(Basis.IDENTITY, Vector3(x, 1.32, -1.72)), Vector3(0.07, 0.4, 1.95), paint)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.32, -2.68)), Vector3(1.9, 0.4, 0.07), paint)
		"van", "ambulance":
			var lower := [Vector2(2.5, 0.42), Vector2(2.55, 0.85), Vector2(2.2, 1.1), Vector2(1.6, 1.15), Vector2(-2.5, 1.15),
					Vector2(-2.55, 0.42)]
			var cabin := [Vector2(1.6, 1.15), Vector2(0.9, 2.05), Vector2(-2.5, 2.08), Vector2(-2.55, 1.15)]
			var body := Color(0.92, 0.92, 0.9) if type == "ambulance" else paint
			_vehicle(m, lower, cabin, 1.0, 0.98, body, false, type == "ambulance")
			_wheels(m, [1.6, -1.7], 0.95, 0.4, false)
			if type == "ambulance":
				_side_panel(m, Vector2(1.4, -2.4), 0.95, 1.0, 1.005, Color(0.75, 0.1, 0.08), 0.18)
				_lightbar(m, Vector3(0, 2.1, 0.7), 1.3)
		"school_bus":
			var lower := [Vector2(5.2, 0.5), Vector2(5.25, 1.0), Vector2(4.6, 1.3), Vector2(4.0, 1.35), Vector2(-5.2, 1.35), Vector2(-5.25, 0.5)]
			var cabin := [Vector2(4.0, 1.35), Vector2(3.7, 2.7), Vector2(-5.15, 2.75), Vector2(-5.2, 1.35)]
			_vehicle(m, lower, cabin, 1.2, 1.2, Color(0.9, 0.68, 0.1), false)
			_wheels(m, [3.4, -3.2], 1.1, 0.5, false)
		_:
			return build("sedan", paint, dirt)
	return m


## Extrudes a side profile (z, y) to half-width `hw`.
static func _extrude(m: MeshData, profile: Array, hw: float, col: Color, cap_col: Color, z_offset := 0.0) -> void:
	var poly := PackedVector2Array()
	for p: Vector2 in profile:
		poly.append(p)
	var tris := Geometry2D.triangulate_polygon(poly)
	for side: float in [-1.0, 1.0]:
		for k in range(0, tris.size(), 3):
			var a := Vector3(side * hw, poly[tris[k]].y, poly[tris[k]].x + z_offset)
			var b := Vector3(side * hw, poly[tris[k + 1]].y, poly[tris[k + 1]].x + z_offset)
			var c := Vector3(side * hw, poly[tris[k + 2]].y, poly[tris[k + 2]].x + z_offset)
			m.tri(a, b, c, cap_col, Vector3(side, 0, 0))
	var center := Vector2.ZERO
	for p in poly:
		center += p
	center /= poly.size()
	for k in poly.size():
		var p0 := poly[k]
		var p1 := poly[(k + 1) % poly.size()]
		var mid := (p0 + p1) * 0.5
		var out := mid - center
		m.quad(Vector3(-hw, p0.y, p0.x + z_offset), Vector3(hw, p0.y, p0.x + z_offset), Vector3(hw, p1.y, p1.x + z_offset), Vector3(-hw, p1.y, p1.x + z_offset),
				col, Vector3(0, out.y, out.x))


static func _vehicle(m: MeshData, lower: Array, cabin: Array, hw: float, cabin_hw: float, paint: Color, burned: bool, boxy := false) -> void:
	_extrude(m, lower, hw, paint, paint)
	# Cabin: painted pillars/roof as the extrusion, glass slightly proud of it.
	var glass := Color(0.05, 0.05, 0.05) if burned else GLASS
	_extrude(m, cabin, cabin_hw, paint, paint)
	var inset := []
	var c := Vector2.ZERO
	for p: Vector2 in cabin:
		c += p
	c /= cabin.size()
	for p: Vector2 in cabin:
		inset.append(c + (p - c) * 0.86)
	_extrude(m, inset, cabin_hw + 0.012, glass, glass)
	if not boxy:
		# Windshield and rear window: re-skin the sloped faces in glass.
		var ws0: Vector2 = cabin[0]
		var ws1: Vector2 = cabin[1]
		var rw0: Vector2 = cabin[cabin.size() - 2]
		var rw1: Vector2 = cabin[cabin.size() - 1]
		for pair in [[ws0, ws1], [rw0, rw1]]:
			var a: Vector2 = pair[0].lerp(pair[1], 0.08)
			var b: Vector2 = pair[0].lerp(pair[1], 0.92)
			var out := Vector2(pair[1].y - pair[0].y, -(pair[1].x - pair[0].x)).normalized()
			if out.dot(((pair[0] + pair[1]) * 0.5) - c) < 0.0:
				out = -out
			var off := out * 0.01
			var w := cabin_hw * 0.92
			m.quad(Vector3(-w, a.y + off.y, a.x + off.x), Vector3(w, a.y + off.y, a.x + off.x), Vector3(w, b.y + off.y, b.x + off.x), Vector3(-w, b.y + off.y, b.x + off.x),
					glass, Vector3(0, out.y, out.x))
	# Lights, grille, bumpers, mirrors, plates.
	var front: Vector2 = lower[0]
	var front_top: Vector2 = lower[1]
	var rear: Vector2 = lower[lower.size() - 1]
	var rear_top: Vector2 = lower[lower.size() - 2]
	var fz := maxf(front.x, front_top.x) + 0.01
	var rz := minf(rear.x, rear_top.x) - 0.01
	var ly := (front.y + front_top.y) * 0.5 + 0.08
	for x in [-hw * 0.7, hw * 0.7]:
		m.box(Transform3D(Basis.IDENTITY, Vector3(x, ly, fz)), Vector3(0.32, 0.14, 0.04), Color(0.2, 0.2, 0.2) if burned else HEAD)
		m.box(Transform3D(Basis.IDENTITY, Vector3(x, (rear.y + rear_top.y) * 0.5 + 0.1, rz)), Vector3(0.3, 0.14, 0.04), Color(0.15, 0.05, 0.05) if burned else TAIL)
	m.box(Transform3D(Basis.IDENTITY, Vector3(0, ly, fz)), Vector3(hw * 0.8, 0.16, 0.03), Color(0.12, 0.12, 0.13))
	m.box(Transform3D(Basis.IDENTITY, Vector3(0, front.y + 0.06, fz + 0.04)), Vector3(hw * 2.0 + 0.04, 0.14, 0.12), CHROME.darkened(0.5))
	m.box(Transform3D(Basis.IDENTITY, Vector3(0, rear.y + 0.06, rz - 0.04)), Vector3(hw * 2.0 + 0.04, 0.14, 0.12), CHROME.darkened(0.5))
	m.box(Transform3D(Basis.IDENTITY, Vector3(0, rear.y + 0.28, rz - 0.02)), Vector3(0.4, 0.12, 0.02), Color(0.85, 0.85, 0.75))
	var mirror_z: float = cabin[0].x - 0.15
	var mirror_y: float = cabin[0].y + 0.15
	for x in [-hw - 0.1, hw + 0.1]:
		m.box(Transform3D(Basis.IDENTITY, Vector3(x, mirror_y, mirror_z)), Vector3(0.18, 0.12, 0.08), paint.darkened(0.2))


static func _wheels(m: MeshData, axles: Array, hw: float, r: float, flat: bool) -> void:
	var y := r * (0.75 if flat else 1.0)
	for z in axles:
		for side: float in [-1.0, 1.0]:
			_wheel(m, Vector3(side * (hw - 0.08), y, z), r, 0.24, side)
			# Dark wheel arch behind the tyre.
			m.box(Transform3D(Basis.IDENTITY, Vector3(side * (hw - 0.02), y + 0.05, z)), Vector3(0.02, r * 2.1, r * 2.3), Color(0.04, 0.04, 0.04))


static func _wheel(m: MeshData, c: Vector3, r: float, w: float, side: float) -> void:
	var n := 10
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(0, cos(a0) * r, sin(a0) * r)
		var p1 := Vector3(0, cos(a1) * r, sin(a1) * r)
		var out := Vector3(0, cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5))
		var o := Vector3(w * 0.5, 0, 0)
		m.quad(c + p0 - o, c + p0 + o, c + p1 + o, c + p1 - o, TIRE, out)
		for s: float in [-1.0, 1.0]:
			var face := c + o * s
			var col := RIM if s == side else TIRE
			m.tri(face, face + p0 * (0.6 if s == side else 1.0), face + p1 * (0.6 if s == side else 1.0), col, Vector3(s, 0, 0))
			if s == side:
				m.quad(face + p0 * 0.6, face + p0, face + p1, face + p1 * 0.6, TIRE.lightened(0.05), Vector3(s, 0, 0))


## Coloured band on both sides (police doors, ambulance stripe).
static func _side_panel(m: MeshData, z_range: Vector2, y_center: float, height: float, x: float, col: Color, band := 0.0) -> void:
	var h := band if band > 0.0 else height * 0.5
	for side: float in [-1.0, 1.0]:
		var zc := (z_range.x + z_range.y) * 0.5
		m.box(Transform3D(Basis.IDENTITY, Vector3(side * x, y_center if band > 0.0 else 0.62, zc)), Vector3(0.01, h, absf(z_range.x - z_range.y)), col)


static func _lightbar(m: MeshData, at: Vector3, width: float) -> void:
	m.box(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.06, 0)), Vector3(width, 0.12, 0.25), Color(0.15, 0.15, 0.15))
	m.box(Transform3D(Basis.IDENTITY, at + Vector3(-width * 0.25, 0.13, 0)), Vector3(width * 0.45, 0.1, 0.22), Color(0.8, 0.1, 0.1))
	m.box(Transform3D(Basis.IDENTITY, at + Vector3(width * 0.25, 0.13, 0)), Vector3(width * 0.45, 0.1, 0.22), Color(0.1, 0.25, 0.85))


## Static aircraft props.
static func aircraft(type: String) -> MeshData:
	var m := MeshData.new()
	var white := Color(0.9, 0.9, 0.9)
	var stripe := Color(0.15, 0.3, 0.6)
	match type:
		"airliner":
			_fuselage(m, 28.0, 1.9, white)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 1.0)), Vector3(28.0, 0.3, 4.0), white.darkened(0.08))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 2.3, -12.5)), Vector3(9.0, 0.2, 2.0), white.darkened(0.08))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 4.6, -12.8)), Vector3(0.3, 4.5, 3.0), stripe)
			for x: float in [-6.0, 6.0]:
				m.cylinder(Vector3(x, 0.4, 0.5), 0.9, 0.9, 0.1, 10, Color(0.6, 0.6, 0.62))
				m.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.8, 1.5)), Vector3(1.6, 1.4, 3.6), Color(0.6, 0.6, 0.62))
			_gear(m, [Vector3(0, 0, 9.0), Vector3(-2.5, 0, -0.5), Vector3(2.5, 0, -0.5)])
		"prop_plane":
			_fuselage(m, 8.0, 0.65, white, 1.0)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 2.0, 0.6)), Vector3(10.5, 0.12, 1.5), white.darkened(0.05))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.3, -3.4)), Vector3(3.2, 0.1, 0.9), white.darkened(0.05))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.9, -3.5)), Vector3(0.1, 1.2, 0.9), Color(0.7, 0.15, 0.1))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 4.1)), Vector3(1.8, 0.12, 0.06), Color(0.15, 0.15, 0.15))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.55, 1.3)), Vector3(1.32, 0.5, 1.2), GLASS)
			_gear(m, [Vector3(0, 0, 2.8), Vector3(-1.1, 0, 0.3), Vector3(1.1, 0, 0.3)])
		"helicopter":
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 0.4)), Vector3(1.8, 1.7, 3.6), Color(0.2, 0.25, 0.22))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.55, 1.9)), Vector3(1.6, 1.2, 0.9), GLASS)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.7, -3.2)), Vector3(0.35, 0.35, 4.6), Color(0.2, 0.25, 0.22))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 2.3, -5.3)), Vector3(0.1, 1.1, 0.7), Color(0.2, 0.25, 0.22))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 2.45, 0.3)), Vector3(0.3, 0.4, 0.3), Color(0.15, 0.15, 0.15))
			for a in 4:
				var basis := Basis(Vector3.UP, a * PI * 0.5 + 0.3)
				m.box(Transform3D(basis, Vector3(0, 2.7, 0.3) + basis.z * 3.4), Vector3(0.3, 0.05, 6.8), Color(0.12, 0.12, 0.12))
			for x: float in [-0.9, 0.9]:
				m.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.08, 0.3)), Vector3(0.08, 0.08, 3.4), Color(0.15, 0.15, 0.15))
				m.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.35, 0.3)), Vector3(0.06, 0.5, 0.06), Color(0.15, 0.15, 0.15))
	return m


static func _fuselage(m: MeshData, length: float, r: float, col: Color, y_offset := 0.0) -> void:
	var n := 10
	var y := r + 0.9 + y_offset
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0) * r, sin(a0) * r + y, 0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r + y, 0)
		var out := Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0)
		var half := length * 0.5
		m.quad(p0 + Vector3(0, 0, -half * 0.7), p1 + Vector3(0, 0, -half * 0.7), p1 + Vector3(0, 0, half * 0.8), p0 + Vector3(0, 0, half * 0.8), col, out)
		m.tri(p0 + Vector3(0, 0, half * 0.8), p1 + Vector3(0, 0, half * 0.8), Vector3(0, y - r * 0.2, half), col, out + Vector3(0, 0, 1))
		var tail := Vector3(0, y + r * 0.6, -half)
		m.tri(p0 + Vector3(0, 0, -half * 0.7), p1 + Vector3(0, 0, -half * 0.7), tail, col, out + Vector3(0, 0, -1))


static func _gear(m: MeshData, points: Array) -> void:
	for p: Vector3 in points:
		m.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.6, 0)), Vector3(0.12, 1.0, 0.12), Color(0.3, 0.3, 0.3))
		m.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.25, 0)), Vector3(0.3, 0.5, 0.5), TIRE)
