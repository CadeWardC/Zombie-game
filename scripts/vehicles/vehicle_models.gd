class_name VehicleModels
extends RefCounted
## Low-poly models for the vehicles that aren't cars: bicycle, motorbike,
## rowboat, motorboat, plus the spinning parts of aircraft. Same space as
## CarModels: +Z is the front, Y up, origin on the ground (or waterline).

const DARK := Color(0.1, 0.1, 0.11)
const STEEL := Color(0.55, 0.56, 0.58)
const TIRE := Color(0.07, 0.07, 0.07)


static func build(type: String) -> MeshData:
	var m := MeshData.new()
	match type:
		"bicycle":
			var frame := Color(0.15, 0.35, 0.6)
			for z: float in [-0.52, 0.52]:
				_wheel(m, Vector3(0, 0.34, z), 0.34, 0.04)
			_bar(m, Vector3(0, 0.34, -0.52), Vector3(0, 0.75, -0.05), 0.025, frame)
			_bar(m, Vector3(0, 0.75, -0.05), Vector3(0, 0.78, 0.4), 0.025, frame)
			_bar(m, Vector3(0, 0.34, -0.05), Vector3(0, 0.75, -0.05), 0.025, frame)
			_bar(m, Vector3(0, 0.34, -0.05), Vector3(0, 0.78, 0.4), 0.025, frame)
			_bar(m, Vector3(0, 0.34, 0.52), Vector3(0, 0.95, 0.45), 0.02, STEEL)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.97, 0.45)), Vector3(0.5, 0.03, 0.03), DARK, false)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.84, -0.1)), Vector3(0.1, 0.05, 0.24), DARK, false)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.34, -0.05)), Vector3(0.16, 0.05, 0.05), STEEL, false)
		"motorbike":
			var paint := Color(0.6, 0.1, 0.08)
			for z: float in [-0.7, 0.72]:
				_wheel(m, Vector3(0, 0.32, z), 0.32, 0.1)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0.0)), Vector3(0.3, 0.32, 0.7), DARK, false) # engine
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.85, 0.18)), Vector3(0.32, 0.22, 0.5), paint, false) # tank
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.82, -0.35)), Vector3(0.28, 0.1, 0.6), DARK, false) # seat
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.72, -0.72)), Vector3(0.22, 0.08, 0.4), paint, false) # fender
			_bar(m, Vector3(0, 0.32, 0.72), Vector3(0, 1.0, 0.5), 0.03, STEEL)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.02, 0.5)), Vector3(0.7, 0.035, 0.035), DARK, false)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0.62)), Vector3(0.16, 0.14, 0.08), Color(0.92, 0.9, 0.78), false)
			_bar(m, Vector3(0.15, 0.35, -0.1), Vector3(0.15, 0.45, -0.75), 0.03, STEEL) # exhaust
		"rowboat":
			var wood := Color(0.48, 0.33, 0.2)
			_hull(m, 3.6, 1.3, 0.55, wood, wood.darkened(0.25))
			for z: float in [-0.7, 0.5]:
				m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, z)), Vector3(1.1, 0.05, 0.3), wood.lightened(0.1), false)
			for s: float in [-1.0, 1.0]:
				m.box(Transform3D(Basis(Vector3.UP, 0.3 * s), Vector3(0.95 * s, 0.4, -0.1)), Vector3(0.05, 0.05, 1.8), wood.darkened(0.1), false)
		"motorboat":
			var white := Color(0.88, 0.88, 0.86)
			_hull(m, 5.0, 1.9, 0.8, white, Color(0.2, 0.3, 0.5))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0.4)), Vector3(1.4, 0.5, 1.0), white, false)
			m.box(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 1.05, 0.9)), Vector3(1.3, 0.04, 0.5), Color(0.25, 0.35, 0.4), false)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.45, -0.6)), Vector3(1.4, 0.15, 1.2), Color(0.7, 0.62, 0.5), false)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.4, -2.6)), Vector3(0.4, 0.6, 0.4), DARK, false) # outboard
		"rotor":
			for a in 2:
				var basis := Basis(Vector3.UP, a * PI * 0.5)
				m.box(Transform3D(basis, Vector3.ZERO), Vector3(0.3, 0.05, 13.6), Color(0.12, 0.12, 0.12), false)
		"propeller":
			m.box(Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3(1.8, 0.12, 0.06), Color(0.15, 0.15, 0.15), false)
	return m


static func _wheel(m: MeshData, c: Vector3, r: float, w: float) -> void:
	var n := 10
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := c + Vector3(0, sin(a0) * r, cos(a0) * r)
		var p1 := c + Vector3(0, sin(a1) * r, cos(a1) * r)
		var out := Vector3(0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
		m.quad(p0 + Vector3(-w, 0, 0), p1 + Vector3(-w, 0, 0), p1 + Vector3(w, 0, 0), p0 + Vector3(w, 0, 0), TIRE, out)
		if w >= 0.06:
			m.tri(c + Vector3(w, 0, 0), p0 + Vector3(w, 0, 0), p1 + Vector3(w, 0, 0), STEEL.darkened(0.3), Vector3.RIGHT)
			m.tri(c - Vector3(w, 0, 0), p0 - Vector3(w, 0, 0), p1 - Vector3(w, 0, 0), STEEL.darkened(0.3), Vector3.LEFT)
		else:
			# Thin bicycle wheel: an open rim with spokes and a hub.
			var ri := r * 0.88
			var q0 := c + Vector3(0, sin(a0) * ri, cos(a0) * ri)
			var q1 := c + Vector3(0, sin(a1) * ri, cos(a1) * ri)
			for sd: float in [-1.0, 1.0]:
				m.quad(p0 + Vector3(w * sd, 0, 0), p1 + Vector3(w * sd, 0, 0), q1 + Vector3(w * sd, 0, 0), q0 + Vector3(w * sd, 0, 0), TIRE, Vector3(sd, 0, 0))
	if w < 0.06:
		for k in 4:
			var a := PI * 0.25 * k
			m.box(Transform3D(Basis(Vector3.RIGHT, a), c), Vector3(0.012, 0.012, r * 1.8), STEEL, false)
		m.box(Transform3D(Basis.IDENTITY, c), Vector3(w * 2.5, 0.05, 0.05), STEEL.darkened(0.2), false)


static func _bar(m: MeshData, a: Vector3, b: Vector3, t: float, col: Color) -> void:
	var mid := (a + b) * 0.5
	var d := b - a
	var basis := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
	m.box(Transform3D(basis, mid), Vector3(t, t, d.length()), col, false)


## A simple boat hull: flat bottom, sloped sides, pointed bow (+Z).
static func _hull(m: MeshData, length: float, width: float, depth: float, top: Color, bottom: Color) -> void:
	var hl := length * 0.5
	var hw := width * 0.5
	var y0 := -depth * 0.35
	var y1 := depth * 0.65
	var stern_l := Vector3(-hw, y1, -hl)
	var stern_r := Vector3(hw, y1, -hl)
	var mid_l := Vector3(-hw, y1, hl * 0.3)
	var mid_r := Vector3(hw, y1, hl * 0.3)
	var bow := Vector3(0, y1 + 0.1, hl)
	var b_stern_l := Vector3(-hw * 0.7, y0, -hl)
	var b_stern_r := Vector3(hw * 0.7, y0, -hl)
	var b_mid_l := Vector3(-hw * 0.7, y0, hl * 0.3)
	var b_mid_r := Vector3(hw * 0.7, y0, hl * 0.3)
	var b_bow := Vector3(0, y0 + depth * 0.3, hl * 0.95)
	m.quad(stern_l, mid_l, b_mid_l, b_stern_l, top, Vector3.LEFT)
	m.quad(stern_r, mid_r, b_mid_r, b_stern_r, top, Vector3.RIGHT)
	m.quad(mid_l, bow, b_bow, b_mid_l, top, Vector3(-1, 0, 1))
	m.quad(mid_r, bow, b_bow, b_mid_r, top, Vector3(1, 0, 1))
	m.quad(b_stern_l, b_mid_l, b_mid_r, b_stern_r, bottom, Vector3.DOWN)
	m.tri(b_mid_l, b_bow, b_mid_r, bottom, Vector3.DOWN)
	m.quad(stern_l, stern_r, b_stern_r, b_stern_l, top.darkened(0.1), Vector3.BACK)
	# Gunwale and floor inside.
	m.quad(Vector3(-hw * 0.85, y0 + 0.08, -hl + 0.1), Vector3(hw * 0.85, y0 + 0.08, -hl + 0.1),
			Vector3(hw * 0.75, y0 + 0.08, hl * 0.4), Vector3(-hw * 0.75, y0 + 0.08, hl * 0.4), bottom.lightened(0.2), Vector3.UP)
	for s: float in [-1.0, 1.0]:
		m.box(Transform3D(Basis.IDENTITY, Vector3(hw * s, y1, -hl * 0.35)), Vector3(0.08, 0.06, length * 0.65), top.darkened(0.2), false)
