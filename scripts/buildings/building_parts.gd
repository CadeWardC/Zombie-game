class_name BuildingParts
extends RefCounted
## Construction helpers shared by all building types: walls with door and
## window openings, floors, roofs, stairs, porches. All coordinates are in
## lot-local space; Vector2 arguments are (x, z) on the ground plane.

const TRIM := Color(0.92, 0.91, 0.87)
const GLASS := Color(0.55, 0.68, 0.75)
const DOOR_W := 0.95
const DOOR_H := 2.1
const WALL_T := 0.22


static func v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## A box with different colours on its two big faces (+Z / -Z of its basis).
## Used for walls: outside paint on one side, inside paint on the other.
static func panel(bd: BuildingData, xf: Transform3D, size: Vector3, col_pos_z: Color, col_neg_z: Color, col_edge: Color, collide := true) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for k in 8:
		p.append(xf * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
	var o := xf.origin
	var m := bd.ext
	m.quad(p[4], p[5], p[7], p[6], col_pos_z, (p[4] + p[7]) * 0.5 - o)
	m.quad(p[0], p[1], p[3], p[2], col_neg_z, (p[0] + p[3]) * 0.5 - o)
	m.quad(p[2], p[3], p[7], p[6], col_edge, (p[2] + p[7]) * 0.5 - o)
	m.quad(p[0], p[1], p[5], p[4], col_edge, (p[0] + p[5]) * 0.5 - o)
	m.quad(p[0], p[4], p[6], p[2], col_edge, (p[0] + p[6]) * 0.5 - o)
	m.quad(p[1], p[5], p[7], p[3], col_edge, (p[1] + p[7]) * 0.5 - o)
	if collide:
		bd.boxes.append([xf, size])


## A straight wall from a to b with openings. `outside` points away from the
## room (for colouring). Openings: {at (metres from a to the centre), w,
## bottom, top, kind: "door" | "window" | "open" | "garage"}.
static func wall(bd: BuildingData, a: Vector2, b: Vector2, y0: float, height: float,
		col_out: Color, col_in: Color, outside: Vector2, openings: Array = [], t := WALL_T, door_color := Color(0.45, 0.28, 0.18), id_prefix := "") -> void:
	var dir := (b - a)
	var length := dir.length()
	if length < 0.05:
		return
	dir /= length
	var x3 := Vector3(dir.x, 0, dir.y)
	var z3 := x3.cross(Vector3.UP) # Always right-handed.
	var basis := Basis(x3, Vector3.UP, z3)
	var pos_is_out := Vector2(z3.x, z3.z).dot(outside) >= 0.0
	var c_pos := col_out if pos_is_out else col_in
	var c_neg := col_in if pos_is_out else col_out
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return p.at < q.at)
	var cursor := 0.0
	for op in ops:
		var left: float = op.at - op.w * 0.5
		var right: float = op.at + op.w * 0.5
		if left < cursor + 0.05 or right > length - 0.05:
			continue
		_piece(bd, a, dir, basis, cursor, left, y0, y0 + height, t, c_pos, c_neg)
		if op.bottom > 0.01:
			_piece(bd, a, dir, basis, left, right, y0, y0 + op.bottom, t, c_pos, c_neg)
		if op.top < height - 0.01:
			_piece(bd, a, dir, basis, left, right, y0 + op.top, y0 + height, t, c_pos, c_neg)
		var mid: Vector2 = a + dir * op.at
		var out3 := v3(outside.normalized(), 0.0)
		match op.kind:
			"window":
				_window(bd, mid, basis, y0 + op.bottom, op.w, op.top - op.bottom, t, out3)
			"door":
				var hinge := a + dir * left
				bd.doors.append({
					"xf": Transform3D(basis, v3(hinge, y0)), "w": op.w, "h": op.top, "t": 0.06,
					"color": door_color, "id": "%s_d%d" % [id_prefix, bd.doors.size()],
					"out": 0 if t <= Interiors.INNER_T + 0.01 else (1 if pos_is_out else -1),
				})
				_frame(bd, mid, basis, y0, op.w, op.top, t)
			"garage":
				var gxf := Transform3D(basis, v3(mid, y0 + op.top * 0.5) + out3 * (t * 0.3))
				bd.ext.box(gxf, Vector3(op.w, op.top, 0.08), Color(0.85, 0.85, 0.82))
				for k in 4:
					bd.ext.box(Transform3D(basis, v3(mid, y0 + op.top * (k + 0.5) / 4.0) + out3 * (t * 0.3 + 0.05)),
							Vector3(op.w, 0.03, 0.03), Color(0.7, 0.7, 0.68))
				bd.boxes.append([gxf, Vector3(op.w, op.top, 0.2)])
		cursor = right
	_piece(bd, a, dir, basis, cursor, length, y0, y0 + height, t, c_pos, c_neg)


static func _piece(bd: BuildingData, a: Vector2, dir: Vector2, basis: Basis, s0: float, s1: float, y0: float, y1: float, t: float, c_pos: Color, c_neg: Color) -> void:
	if s1 - s0 < 0.01 or y1 - y0 < 0.01:
		return
	var mid := a + dir * ((s0 + s1) * 0.5)
	panel(bd, Transform3D(basis, v3(mid, (y0 + y1) * 0.5)), Vector3(s1 - s0, y1 - y0, t), c_pos, c_neg, c_neg)


static func _window(bd: BuildingData, mid: Vector2, basis: Basis, bottom: float, w: float, h: float, t: float, out3: Vector3) -> void:
	var c := v3(mid, bottom + h * 0.5)
	var n := basis.z
	_frame(bd, mid, basis, bottom, w, h, t)
	bd.ext.box(Transform3D(basis, c - Vector3(0, h * 0.5 + 0.04, 0) + out3 * (t * 0.5 + 0.06)), Vector3(w + 0.2, 0.06, 0.14), TRIM)
	# Ground-floor windows of enterable buildings can be smashed: they're
	# separate bodies, drawn by the chunk.
	if bd.interior and bottom < 1.7 and h > 0.6:
		bd.windows.append({"xf": Transform3D(basis, c), "w": w, "h": h, "id": "%s_w%d" % [bd.id, bd.windows.size()]})
		return
	bd.glass.quad(c - basis.x * w * 0.5 - Vector3(0, h * 0.5, 0), c + basis.x * w * 0.5 - Vector3(0, h * 0.5, 0),
			c + basis.x * w * 0.5 + Vector3(0, h * 0.5, 0), c - basis.x * w * 0.5 + Vector3(0, h * 0.5, 0), GLASS, n)
	# Window still blocks movement.
	bd.boxes.append([Transform3D(basis, c), Vector3(w, h, 0.1)])


## Trim around an opening, proud of both wall faces.
static func _frame(bd: BuildingData, mid: Vector2, basis: Basis, bottom: float, w: float, h: float, t: float) -> void:
	var c := v3(mid, bottom)
	var ft := t + 0.06
	bd.ext.box(Transform3D(basis, c + basis.x * (w * 0.5 + 0.05) + Vector3(0, h * 0.5, 0)), Vector3(0.1, h, ft), TRIM)
	bd.ext.box(Transform3D(basis, c - basis.x * (w * 0.5 + 0.05) + Vector3(0, h * 0.5, 0)), Vector3(0.1, h, ft), TRIM)
	bd.ext.box(Transform3D(basis, c + Vector3(0, h + 0.05, 0)), Vector3(w + 0.2, 0.1, ft), TRIM)


## Horizontal slab (floor / ceiling) covering a rectangle, minus an optional
## hole (for stairs). Rects are Rect2 in (x, z).
static func slab(bd: BuildingData, r: Rect2, y: float, thickness: float, top: Color, bottom: Color, hole := Rect2()) -> void:
	var pieces: Array[Rect2] = [r]
	if hole.has_area():
		pieces = []
		var h := hole.intersection(r)
		if h.position.y > r.position.y:
			pieces.append(Rect2(r.position.x, r.position.y, r.size.x, h.position.y - r.position.y))
		if h.end.y < r.end.y:
			pieces.append(Rect2(r.position.x, h.end.y, r.size.x, r.end.y - h.end.y))
		if h.position.x > r.position.x:
			pieces.append(Rect2(r.position.x, h.position.y, h.position.x - r.position.x, h.size.y))
		if h.end.x < r.end.x:
			pieces.append(Rect2(h.end.x, h.position.y, r.end.x - h.end.x, h.size.y))
	for p in pieces:
		if p.size.x < 0.05 or p.size.y < 0.05:
			continue
		var c := p.get_center()
		panel(bd, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), v3(c, y - thickness * 0.5)),
				Vector3(p.size.x, p.size.y, thickness), top, bottom, bottom)


## Gable roof over rect r. Ridge runs along X if `ridge_x`.
static func gable_roof(bd: BuildingData, r: Rect2, y: float, rise: float, overhang: float, roof: Color, gable: Color, ridge_x := true) -> void:
	var o := overhang
	var x0 := r.position.x - o
	var x1 := r.end.x + o
	var z0 := r.position.y - o
	var z1 := r.end.y + o
	var m := bd.ext
	var under := roof.darkened(0.45)
	if ridge_x:
		var zc := r.get_center().y
		var top := y + rise
		var e := y - o * rise / (r.size.y * 0.5)
		for side in [[z0, 1.0], [z1, -1.0]]:
			var zz: float = side[0]
			var a := Vector3(x0, e, zz)
			var b := Vector3(x1, e, zz)
			var c := Vector3(x1, top, zc)
			var d := Vector3(x0, top, zc)
			var up := (c - b).cross(a - b).normalized()
			if up.y < 0.0:
				up = -up
			m.quad(a, b, c, d, roof, up)
			m.quad(a + Vector3(0, -0.12, 0), b + Vector3(0, -0.12, 0), c + Vector3(0, -0.12, 0), d + Vector3(0, -0.12, 0), under, -up)
		for x in [r.position.x, r.end.x]:
			m.tri(Vector3(x, y, r.position.y), Vector3(x, y, r.end.y), Vector3(x, top, zc), gable, Vector3(signf(x - r.get_center().x), 0, 0))
			m.tri(Vector3(x, y, r.position.y), Vector3(x, y, r.end.y), Vector3(x, top, zc), gable.darkened(0.2), Vector3(-signf(x - r.get_center().x), 0, 0))
	else:
		var xc := r.get_center().x
		var top := y + rise
		var e := y - o * rise / (r.size.x * 0.5)
		for side in [x0, x1]:
			var a := Vector3(side, e, z0)
			var b := Vector3(side, e, z1)
			var c := Vector3(xc, top, z1)
			var d := Vector3(xc, top, z0)
			var up := (c - b).cross(a - b).normalized()
			if up.y < 0.0:
				up = -up
			m.quad(a, b, c, d, roof, up)
			m.quad(a + Vector3(0, -0.12, 0), b + Vector3(0, -0.12, 0), c + Vector3(0, -0.12, 0), d + Vector3(0, -0.12, 0), under, -up)
		for z in [r.position.y, r.end.y]:
			m.tri(Vector3(r.position.x, y, z), Vector3(r.end.x, y, z), Vector3(xc, top, z), gable, Vector3(0, 0, signf(z - r.get_center().y)))
			m.tri(Vector3(r.position.x, y, z), Vector3(r.end.x, y, z), Vector3(xc, top, z), gable.darkened(0.2), Vector3(0, 0, -signf(z - r.get_center().y)))
	bd.boxes.append([Transform3D(Basis.IDENTITY, v3(r.get_center(), y + 0.15)), Vector3(r.size.x, 0.3, r.size.y)])


## Hip roof: slopes on all four sides.
static func hip_roof(bd: BuildingData, r: Rect2, y: float, rise: float, overhang: float, roof: Color) -> void:
	var rr := r.grow(overhang)
	var e := y - 0.15
	var inset := minf(rr.size.x, rr.size.y) * 0.5
	var c := rr.get_center()
	var ra := Vector3(rr.position.x, e, rr.position.y)
	var rb := Vector3(rr.end.x, e, rr.position.y)
	var rc := Vector3(rr.end.x, e, rr.end.y)
	var rd := Vector3(rr.position.x, e, rr.end.y)
	var long_x := rr.size.x >= rr.size.y
	var r0: Vector3
	var r1: Vector3
	if long_x:
		r0 = Vector3(rr.position.x + inset, y + rise, c.y)
		r1 = Vector3(rr.end.x - inset, y + rise, c.y)
		bd.ext.quad(ra, rb, r1, r0, roof, Vector3(0, 1, -1))
		bd.ext.quad(rd, rc, r1, r0, roof.darkened(0.06), Vector3(0, 1, 1))
		bd.ext.tri(ra, rd, r0, roof.darkened(0.03), Vector3(-1, 1, 0))
		bd.ext.tri(rb, rc, r1, roof.darkened(0.03), Vector3(1, 1, 0))
	else:
		r0 = Vector3(c.x, y + rise, rr.position.y + inset)
		r1 = Vector3(c.x, y + rise, rr.end.y - inset)
		bd.ext.quad(ra, rd, r1, r0, roof, Vector3(-1, 1, 0))
		bd.ext.quad(rb, rc, r1, r0, roof.darkened(0.06), Vector3(1, 1, 0))
		bd.ext.tri(ra, rb, r0, roof.darkened(0.03), Vector3(0, 1, -1))
		bd.ext.tri(rd, rc, r1, roof.darkened(0.03), Vector3(0, 1, 1))
	# Soffit under the overhang.
	bd.ext.quad(ra, rb, rc, rd, roof.darkened(0.5), Vector3.DOWN)
	bd.boxes.append([Transform3D(Basis.IDENTITY, v3(r.get_center(), y + 0.15)), Vector3(r.size.x, 0.3, r.size.y)])


## Flat roof with a parapet.
static func flat_roof(bd: BuildingData, r: Rect2, y: float, col: Color, parapet := 0.8, parapet_col := Color(0.6, 0.6, 0.58)) -> void:
	slab(bd, r, y + 0.25, 0.25, col, Color(0.82, 0.82, 0.8))
	if parapet > 0.0:
		var t := 0.25
		var c := r.get_center()
		for side in 4:
			var horizontal := side < 2
			var size := Vector3(r.size.x + t, parapet, t) if horizontal else Vector3(t, parapet, r.size.y + t)
			var pos := Vector2(c.x, r.position.y if side == 0 else r.end.y) if horizontal else Vector2(r.position.x if side == 2 else r.end.x, c.y)
			panel(bd, Transform3D(Basis.IDENTITY, v3(pos, y + 0.25 + parapet * 0.5)), size, parapet_col, parapet_col, parapet_col.lightened(0.1))


## Straight staircase rising along +Z from `start` (bottom step front edge).
static func stairs(bd: BuildingData, start: Vector2, width: float, rise: float, along_x := false, col := Color(0.5, 0.36, 0.24)) -> void:
	var steps := int(ceil(rise / 0.19))
	var step_h := rise / steps
	var step_d := 0.27
	var dir := Vector2(1, 0) if along_x else Vector2(0, 1)
	var side := Vector2(0, 1) if along_x else Vector2(1, 0)
	for k in steps:
		var c := start + dir * (step_d * (k + 0.5)) + side * width * 0.5
		var size := Vector3(step_d, step_h * (k + 1), width) if along_x else Vector3(width, step_h * (k + 1), step_d)
		bd.ext.box(Transform3D(Basis.IDENTITY, v3(c, step_h * (k + 1) * 0.5)), size, col)
	# Collision as one smooth ramp so walking up feels natural.
	var length := steps * step_d
	var mid := start + dir * length * 0.5 + side * width * 0.5
	bd.boxes.append([Transform3D(_ramp_basis(v3(dir * length, rise)), v3(mid, rise * 0.5)),
			Vector3(width, 0.2, sqrt(length * length + rise * rise))])


## Basis whose -Z runs along `d` (a ramp's slope) and whose X stays level.
static func _ramp_basis(d: Vector3) -> Basis:
	return Basis.looking_at(d.normalized(), Vector3.UP)


## Simple porch: deck, posts and a sloped roof along the front (+Z) of rect r.
static func porch(bd: BuildingData, r: Rect2, depth: float, y_roof: float, deck: Color, post: Color, roof: Color) -> void:
	var z0 := r.end.y
	var z1 := r.end.y + depth
	var deck_r := Rect2(r.position.x, z0, r.size.x, depth)
	slab(bd, deck_r, 0.0, 0.3, deck, deck.darkened(0.3))
	var posts := maxi(2, int(r.size.x / 3.0) + 1)
	for k in posts:
		var x := lerpf(r.position.x + 0.2, r.end.x - 0.2, float(k) / (posts - 1))
		bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(x, y_roof * 0.5, z1 - 0.2)), Vector3(0.18, y_roof, 0.18), post)
		bd.boxes.append([Transform3D(Basis.IDENTITY, Vector3(x, y_roof * 0.5, z1 - 0.2)), Vector3(0.18, y_roof, 0.18)])
	var a := Vector3(r.position.x - 0.2, y_roof + 0.35, z0)
	var b := Vector3(r.end.x + 0.2, y_roof + 0.35, z0)
	var c := Vector3(r.end.x + 0.2, y_roof, z1 + 0.3)
	var d := Vector3(r.position.x - 0.2, y_roof, z1 + 0.3)
	bd.ext.quad(a, b, c, d, roof, Vector3(0, 1, 0.3))
	bd.ext.quad(a, b, c, d, roof.darkened(0.5), Vector3(0, -1, -0.3))
	# Railing.
	for x in [r.position.x + 0.2, r.end.x - 0.2]:
		bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.55, (z0 + z1) * 0.5)), Vector3(0.08, 0.08, depth), post)


## Steps from a door sill down to the ground in front of it (+Z of `front`).
static func front_steps(bd: BuildingData, at: Vector2, front: Vector2, width: float, drop: float, col := Color(0.6, 0.59, 0.56)) -> void:
	if drop < 0.12:
		return
	var steps := int(ceil(drop / 0.18))
	var sh := drop / steps
	for k in steps:
		var c := at + front * (0.15 + 0.3 * (k + 0.5))
		var h := drop - sh * k
		var basis := Basis(Vector3.UP, atan2(front.x, front.y))
		bd.ext.box(Transform3D(basis, v3(c, -drop + h * 0.5)), Vector3(width, h, 0.3), col)
	var length := 0.3 * steps
	var mid := at + front * (0.15 + length * 0.5)
	bd.boxes.append([Transform3D(_ramp_basis(v3(-front * length, drop)), v3(mid, -drop * 0.5)),
			Vector3(width, 0.15, sqrt(length * length + drop * drop))])
