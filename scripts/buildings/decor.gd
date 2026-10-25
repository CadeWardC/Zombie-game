class_name Decor
extends RefCounted
## Set dressing: the small things that make a place look lived in, and then
## abandoned. Clutter on floors and tables, pictures on walls, lights, yard
## things, litter, roadblocks and the dead. Everything is plain geometry
## added to a building's (or a chunk's) merged mesh, so it costs no extra
## draw calls. Each piece is placed by a transform whose origin is on the
## floor / ground and whose +Z faces into the room (or out from a wall).

const PAPER := Color(0.86, 0.85, 0.8)
const BLOOD := Color(0.32, 0.03, 0.03)
const BLOOD_DRY := Color(0.24, 0.06, 0.05)
const CARDBOARD := Color(0.62, 0.48, 0.3)
const TRASH := Color(0.08, 0.09, 0.08)
const METAL := Color(0.55, 0.57, 0.58)
const RUST := Color(0.42, 0.25, 0.15)
const CLOTH := [Color(0.3, 0.33, 0.45), Color(0.55, 0.2, 0.18), Color(0.75, 0.72, 0.65), Color(0.25, 0.3, 0.22),
	Color(0.15, 0.15, 0.16), Color(0.6, 0.5, 0.3)]
const FRAMES := [Color(0.25, 0.17, 0.1), Color(0.85, 0.83, 0.78), Color(0.1, 0.1, 0.1), Color(0.6, 0.5, 0.25)]
const ART := [Color(0.35, 0.5, 0.6), Color(0.6, 0.45, 0.3), Color(0.3, 0.45, 0.3), Color(0.7, 0.6, 0.45),
	Color(0.5, 0.35, 0.45), Color(0.8, 0.75, 0.6)]


static func _b(m: MeshData, xf: Transform3D, center: Vector3, size: Vector3, col: Color) -> void:
	m.box(xf * Transform3D(Basis.IDENTITY, center), size, col)


## A flat shape lying on the floor (a stain, a sheet of paper, a rug).
static func flat(m: MeshData, xf: Transform3D, size: Vector2, col: Color, lift := 0.008) -> void:
	var h := size * 0.5
	m.quad(xf * Vector3(-h.x, lift, -h.y), xf * Vector3(h.x, lift, -h.y), xf * Vector3(h.x, lift, h.y), xf * Vector3(-h.x, lift, h.y),
		col, xf.basis.y)


## A ragged pool of blood (older ones are darker and browner).
static func blood(m: MeshData, xf: Transform3D, radius: float, rng: RandomNumberGenerator) -> void:
	var col := BLOOD.lerp(BLOOD_DRY, rng.randf())
	var c := xf * Vector3(0, 0.009, 0)
	var n := 9
	var prev := Vector3.ZERO
	var first := Vector3.ZERO
	for k in n + 1:
		var a := TAU * k / n
		var r := radius * rng.randf_range(0.55, 1.0) if k < n else 0.0
		var p := xf * Vector3(cos(a) * r, 0.009, sin(a) * r) if k < n else first
		if k == 0:
			first = p
		else:
			m.tri(c, prev, p, col, xf.basis.y)
		prev = p
	# A few drops around it.
	for k in rng.randi_range(2, 5):
		var a := rng.randf() * TAU
		var d := radius * rng.randf_range(1.1, 2.2)
		flat(m, xf * Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * d, 0, sin(a) * d)), Vector2.ONE * radius * 0.15, col, 0.009)


## A drag mark: a smeared trail of blood from A to B (local XZ).
static func blood_trail(m: MeshData, xf: Transform3D, length: float, rng: RandomNumberGenerator) -> void:
	var col := BLOOD_DRY.lerp(BLOOD, rng.randf() * 0.5)
	var steps := int(length / 0.4)
	for k in steps:
		var z := k * 0.4
		var w := rng.randf_range(0.12, 0.3)
		flat(m, xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), Vector3(rng.randf_range(-0.05, 0.05), 0, z)), Vector2(w, 0.35), col, 0.009)


## Loose sheets of paper.
static func papers(m: MeshData, xf: Transform3D, rng: RandomNumberGenerator, count := 4) -> void:
	for k in count:
		var p := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
		flat(m, xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), Vector2(0.21, 0.29), PAPER.darkened(rng.randf() * 0.2), 0.006 + k * 0.001)


## A heap of dropped clothes.
static func clothes(m: MeshData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	for k in rng.randi_range(2, 4):
		var col: Color = CLOTH[rng.randi() % CLOTH.size()]
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		m.box(xf * Transform3D(b, Vector3(rng.randf_range(-0.2, 0.2), 0.03 + k * 0.03, rng.randf_range(-0.2, 0.2))),
			Vector3(rng.randf_range(0.35, 0.55), 0.05, rng.randf_range(0.25, 0.4)), col)


## A few books, stacked or knocked over.
static func books(m: MeshData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var y := 0.0
	for k in rng.randi_range(1, 4):
		var col := Color.from_hsv(rng.randf(), 0.5, 0.45)
		var lying := rng.randf() < 0.7
		var b := Basis(Vector3.UP, rng.randf_range(-0.5, 0.5))
		if lying:
			m.box(xf * Transform3D(b, Vector3(rng.randf_range(-0.05, 0.05), y + 0.02, 0)), Vector3(0.16, 0.035, 0.23), col)
			y += 0.035
		else:
			m.box(xf * Transform3D(b, Vector3(rng.randf_range(-0.3, 0.3), 0.115, rng.randf_range(-0.2, 0.2))), Vector3(0.035, 0.23, 0.16), col)


static func bottle(m: MeshData, xf: Transform3D, col: Color, fallen := false) -> void:
	if fallen:
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.035, 0)), Vector3(0.07, 0.07, 0.24), col)
	else:
		m.cylinder(xf * Vector3.ZERO, 0.035, 0.035, 0.18, 6, col)
		m.cylinder(xf * Vector3(0, 0.18, 0), 0.035, 0.012, 0.07, 6, col)


static func can(m: MeshData, xf: Transform3D, col: Color) -> void:
	m.cylinder(xf * Vector3.ZERO, 0.033, 0.033, 0.12, 6, col)


static func plate(m: MeshData, xf: Transform3D) -> void:
	m.cylinder(xf * Vector3.ZERO, 0.12, 0.13, 0.02, 8, Color(0.92, 0.92, 0.9))


static func cup(m: MeshData, xf: Transform3D, col: Color) -> void:
	m.cylinder(xf * Vector3.ZERO, 0.04, 0.045, 0.1, 6, col)


## Broken plates and glass.
static func shards(m: MeshData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	for k in rng.randi_range(4, 8):
		var p := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
		flat(m, xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), Vector2(rng.randf_range(0.04, 0.12), rng.randf_range(0.04, 0.1)),
			Color(0.9, 0.9, 0.88) if k % 2 == 0 else Color(0.6, 0.7, 0.72), 0.007)


static func cardboard_box(m: MeshData, xf: Transform3D, size: Vector3, open := false) -> void:
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5, 0)), size, CARDBOARD)
	if open:
		m.box(xf * Transform3D(Basis(Vector3.RIGHT, 0.9), Vector3(0, size.y, size.z * 0.5)), Vector3(size.x, size.z * 0.5, 0.01), CARDBOARD.darkened(0.1))
	else:
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, size.y + 0.002, 0)), Vector3(0.05, 0.004, size.z), Color(0.75, 0.68, 0.5))


## A black bin bag, knotted at the top.
static func trash_bag(m: MeshData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.8, 1.1)
	var col := TRASH if rng.randf() < 0.7 else Color(0.18, 0.25, 0.16)
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.2 * s, 0)), Vector3(0.5, 0.4, 0.45) * s, col)
	m.box(xf * Transform3D(Basis(Vector3.UP, 0.7), Vector3(0, 0.38 * s, 0)), Vector3(0.36, 0.14, 0.32) * s, col.lightened(0.05))
	m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.5 * s, 0)), Vector3(0.08, 0.1, 0.08) * s, col)


## A kitchen chair, standing or knocked over.
static func chair(m: MeshData, xf: Transform3D, col: Color, fallen := false) -> void:
	var c := xf
	if fallen:
		c = xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.22, -0.4))
	_b(m, c, Vector3(0, 0.45, 0), Vector3(0.42, 0.05, 0.42), col)
	_b(m, c, Vector3(0, 0.75, -0.19), Vector3(0.42, 0.55, 0.05), col)
	for x: float in [-0.18, 0.18]:
		for z: float in [-0.18, 0.18]:
			_b(m, c, Vector3(x, 0.22, z), Vector3(0.04, 0.44, 0.04), col.darkened(0.2))


## Someone who didn't make it, lying where they fell, in a pool of blood.
static func corpse(m: MeshData, xf: Transform3D, rng: RandomNumberGenerator, with_blood := true) -> void:
	if with_blood:
		blood(m, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.1)), rng.randf_range(0.5, 0.8), rng)
	var shirt: Color = CLOTH[rng.randi() % CLOTH.size()]
	var pants: Color = CLOTH[rng.randi() % CLOTH.size()].darkened(0.3)
	var skin := Color(0.62, 0.5, 0.42).lerp(Color(0.3, 0.22, 0.17), rng.randf()).lerp(Color(0.45, 0.5, 0.4), 0.3)
	var y := 0.11
	_b(m, xf, Vector3(0, y, 0.15), Vector3(0.42, 0.2, 0.62), shirt)
	_b(m, xf, Vector3(0, y + 0.02, 0.62), Vector3(0.22, 0.22, 0.24), skin)
	var arm := rng.randf_range(0.2, 1.3)
	for sgn: float in [-1.0, 1.0]:
		var b := Basis(Vector3.UP, sgn * arm * rng.randf_range(0.6, 1.0))
		m.box(xf * Transform3D(b, Vector3(sgn * 0.3, y - 0.02, 0.3) + b * Vector3(sgn * 0.05, 0, 0.22)), Vector3(0.12, 0.12, 0.55), shirt.darkened(0.1))
		var lb := Basis(Vector3.UP, sgn * rng.randf_range(0.0, 0.4))
		m.box(xf * Transform3D(lb, Vector3(sgn * 0.12, y - 0.01, -0.45)), Vector3(0.16, 0.16, 0.75), pants)


## A row of sandbags.
static func sandbags(m: MeshData, xf: Transform3D, length: float, rng: RandomNumberGenerator) -> void:
	var n := int(length / 0.55)
	for row in 2:
		for k in n - row:
			var x := -length * 0.5 + (k + 0.5 + row * 0.5) * 0.55
			m.box(xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)), Vector3(x, 0.09 + row * 0.17, 0)),
				Vector3(0.52, 0.18, 0.32), Color(0.55, 0.5, 0.36).darkened(rng.randf() * 0.15))


## A striped road barrier (sawhorse).
static func barrier(m: MeshData, xf: Transform3D) -> void:
	for x: float in [-0.8, 0.8]:
		_b(m, xf, Vector3(x, 0.45, 0), Vector3(0.06, 0.9, 0.5), Color(0.85, 0.85, 0.82))
	for k in 5:
		_b(m, xf, Vector3(-0.8 + k * 0.4, 0.8, 0.02), Vector3(0.4, 0.2, 0.04), Color(0.9, 0.45, 0.1) if k % 2 == 0 else Color(0.92, 0.92, 0.9))


static func cone(m: MeshData, xf: Transform3D) -> void:
	_b(m, xf, Vector3(0, 0.015, 0), Vector3(0.36, 0.03, 0.36), Color(0.85, 0.35, 0.08))
	m.cylinder(xf * Vector3(0, 0.03, 0), 0.14, 0.02, 0.5, 6, Color(0.92, 0.4, 0.08))
	m.cylinder(xf * Vector3(0, 0.25, 0), 0.085, 0.07, 0.07, 6, Color(0.92, 0.92, 0.9), false)


static func tire(m: MeshData, xf: Transform3D) -> void:
	m.cylinder(xf * Vector3.ZERO, 0.33, 0.33, 0.22, 10, Color(0.07, 0.07, 0.07))
	m.cylinder(xf * Vector3(0, 0.221, 0), 0.17, 0.17, 0.002, 8, Color(0.02, 0.02, 0.02))


static func dumpster(m: MeshData, xf: Transform3D, col: Color) -> void:
	_b(m, xf, Vector3(0, 0.65, 0), Vector3(1.9, 1.1, 1.1), col)
	_b(m, xf, Vector3(0, 1.22, -0.05), Vector3(1.95, 0.06, 1.2), col.darkened(0.25))
	for x: float in [-0.8, 0.8]:
		for z: float in [-0.45, 0.45]:
			m.cylinder(xf * Vector3(x, 0.0, z), 0.06, 0.06, 0.12, 6, Color(0.1, 0.1, 0.1))


static func bench(m: MeshData, xf: Transform3D) -> void:
	for k in 3:
		_b(m, xf, Vector3(0, 0.45, -0.15 + k * 0.15), Vector3(1.6, 0.04, 0.12), Color(0.45, 0.3, 0.18))
	_b(m, xf, Vector3(0, 0.75, -0.25), Vector3(1.6, 0.3, 0.04), Color(0.45, 0.3, 0.18))
	for x: float in [-0.7, 0.7]:
		_b(m, xf, Vector3(x, 0.22, 0), Vector3(0.06, 0.44, 0.5), Color(0.15, 0.15, 0.15))


## A wheelie bin, upright or tipped over with its trash spilled.
static func bin(m: MeshData, xf: Transform3D, col: Color, rng: RandomNumberGenerator, tipped := false) -> void:
	var c := xf if not tipped else xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.3, 0))
	_b(m, c, Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 0.7), col)
	_b(m, c, Vector3(0, 1.02, 0), Vector3(0.64, 0.05, 0.74), col.darkened(0.2))
	if tipped:
		trash_bag(m, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 1.0)), rng)
		papers(m, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 1.4)), rng, 3)


static func grill(m: MeshData, xf: Transform3D) -> void:
	for k in 3:
		var a := TAU * k / 3.0
		_b(m, xf, Vector3(cos(a) * 0.2, 0.35, sin(a) * 0.2), Vector3(0.03, 0.7, 0.03), Color(0.1, 0.1, 0.1))
	m.cylinder(xf * Vector3(0, 0.65, 0), 0.25, 0.3, 0.2, 8, Color(0.12, 0.12, 0.12))
	m.cylinder(xf * Vector3(0, 0.85, 0), 0.3, 0.15, 0.12, 8, Color(0.14, 0.14, 0.14))


static func lawn_chair(m: MeshData, xf: Transform3D, col: Color, fallen := false) -> void:
	var c := xf if not fallen else xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.25, 0.25, 0))
	_b(m, c, Vector3(0, 0.3, 0), Vector3(0.5, 0.04, 0.5), col)
	_b(m, c, Vector3(0, 0.55, -0.27), Vector3(0.5, 0.5, 0.04), col)
	for x: float in [-0.23, 0.23]:
		_b(m, c, Vector3(x, 0.15, 0), Vector3(0.03, 0.3, 0.5), METAL)


static func doghouse(m: MeshData, xf: Transform3D) -> void:
	var w := Color(0.6, 0.42, 0.28)
	_b(m, xf, Vector3(0, 0.4, 0), Vector3(0.9, 0.8, 1.1), w)
	for s: float in [-1.0, 1.0]:
		m.box(xf * Transform3D(Basis(Vector3.FORWARD, s * 0.65), Vector3(s * 0.25, 0.95, 0)), Vector3(0.65, 0.05, 1.2), Color(0.4, 0.2, 0.15))
	_b(m, xf, Vector3(0, 0.3, 0.551), Vector3(0.4, 0.5, 0.01), Color(0.05, 0.05, 0.05))


static func pallet(m: MeshData, xf: Transform3D) -> void:
	var w := Color(0.62, 0.5, 0.34)
	for k in 5:
		_b(m, xf, Vector3(-0.48 + k * 0.24, 0.13, 0), Vector3(0.14, 0.02, 1.2), w)
	for z: float in [-0.5, 0.0, 0.5]:
		_b(m, xf, Vector3(0, 0.06, z), Vector3(1.0, 0.1, 0.12), w.darkened(0.15))


## A child's toy: a ball, a tricycle or a wagon.
static func toy(m: MeshData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var col := Color.from_hsv(rng.randf(), 0.7, 0.8)
	match rng.randi() % 3:
		0:
			m.cylinder(xf * Vector3.ZERO, 0.12, 0.12, 0.24, 8, col)
		1:
			_b(m, xf, Vector3(0, 0.3, 0), Vector3(0.08, 0.06, 0.5), col)
			m.cylinder(xf * Vector3(0, 0.0, 0.25), 0.15, 0.15, 0.05, 8, Color(0.1, 0.1, 0.1))
			_b(m, xf, Vector3(0, 0.4, -0.15), Vector3(0.2, 0.05, 0.2), Color(0.1, 0.1, 0.1))
		_:
			_b(m, xf, Vector3(0, 0.25, 0), Vector3(0.45, 0.18, 0.75), col)
			for x: float in [-0.2, 0.2]:
				for z: float in [-0.3, 0.3]:
					_b(m, xf, Vector3(x, 0.08, z), Vector3(0.05, 0.16, 0.16), Color(0.1, 0.1, 0.1))


## A clump of tall grass or weeds: thin pointed blades leaning outwards.
static func grass(m: MeshData, xf: Transform3D, col: Color, height := 0.5) -> void:
	for k in 7:
		var a := k * 2.4
		var r := 0.06 + 0.035 * (k % 3)
		var base := Vector3(cos(a), 0, sin(a)) * r
		var side := Vector3(-sin(a), 0, cos(a)) * 0.035
		var h := height * (0.65 + 0.35 * ((k * 37) % 10) / 10.0)
		var tip := base * 2.6 + Vector3(0, h, 0)
		m.tri(xf * (base - side), xf * (base + side), xf * tip, col.darkened(0.04 * (k % 4)), xf.basis * (base + Vector3(0, 0.2, 0)))


## A burnt-out car: a charred shell with no glass.
static func burnt_car(m: MeshData, xf: Transform3D) -> void:
	var char_col := Color(0.12, 0.1, 0.09)
	_b(m, xf, Vector3(0, 0.55, 0), Vector3(1.8, 0.6, 4.3), char_col)
	_b(m, xf, Vector3(0, 1.05, -0.2), Vector3(1.6, 0.04, 2.0), RUST.darkened(0.4))
	for x: float in [-0.78, 0.78]:
		for z: float in [-0.9, 0.5]:
			_b(m, xf, Vector3(x, 0.85, z), Vector3(0.06, 0.5, 0.06), char_col)
	for x: float in [-0.8, 0.8]:
		for z: float in [-1.35, 1.35]:
			_b(m, xf, Vector3(x, 0.18, z), Vector3(0.18, 0.3, 0.5), Color(0.05, 0.05, 0.05))
	_b(m, xf, Vector3(0, 0.86, 1.6), Vector3(1.7, 0.03, 1.0), RUST.darkened(0.2))


# --- Inside ------------------------------------------------------------------------

## A framed picture on a wall (xf: on the wall surface, +Z into the room).
static func picture(m: MeshData, xf: Transform3D, size: Vector2, rng: RandomNumberGenerator, crooked := false) -> void:
	var b := Basis(Vector3.BACK, rng.randf_range(-0.25, 0.25)) if crooked else Basis.IDENTITY
	var c := xf * Transform3D(b, Vector3.ZERO)
	_b(m, c, Vector3(0, 0, 0.015), Vector3(size.x, size.y, 0.03), FRAMES[rng.randi() % FRAMES.size()])
	_b(m, c, Vector3(0, 0, 0.032), Vector3(size.x - 0.08, size.y - 0.08, 0.005), ART[rng.randi() % ART.size()])
	_b(m, c, Vector3(rng.randf_range(-0.1, 0.1) * size.x, rng.randf_range(-0.15, 0.05) * size.y, 0.036),
		Vector3(size.x * 0.35, size.y * 0.3, 0.003), ART[rng.randi() % ART.size()].darkened(0.3))


static func clock(m: MeshData, xf: Transform3D) -> void:
	m.append(_disc(0.16, Color(0.15, 0.15, 0.15), 0.03), xf)
	m.append(_disc(0.14, Color(0.92, 0.9, 0.85), 0.035), xf)
	_b(m, xf, Vector3(0, 0.04, 0.04), Vector3(0.012, 0.09, 0.004), Color.BLACK)
	_b(m, xf, Vector3(0.03, 0, 0.04), Vector3(0.07, 0.012, 0.004), Color.BLACK)


## A flat disc facing +Z, `depth` out from the wall.
static func _disc(r: float, col: Color, depth: float) -> MeshData:
	var d := MeshData.new()
	var n := 10
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		d.tri(Vector3(0, 0, depth), Vector3(cos(a0) * r, sin(a0) * r, depth), Vector3(cos(a1) * r, sin(a1) * r, depth), col, Vector3.BACK)
	return d


## A wall shelf with a few things on it.
static func wall_shelf(m: MeshData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	_b(m, xf, Vector3(0, 0, 0.11), Vector3(0.9, 0.03, 0.22), Color(0.4, 0.28, 0.18))
	var x := -0.38
	while x < 0.38:
		var w := rng.randf_range(0.04, 0.12)
		var h := rng.randf_range(0.1, 0.24)
		_b(m, xf, Vector3(x + w * 0.5, 0.015 + h * 0.5, 0.1), Vector3(w, h, 0.15), Color.from_hsv(rng.randf(), 0.45, 0.5))
		x += w + rng.randf_range(0.0, 0.1)


## Curtains either side of a window (xf: window centre on the inner face).
static func curtains(m: MeshData, xf: Transform3D, w: float, h: float, col: Color) -> void:
	for s: float in [-1.0, 1.0]:
		_b(m, xf, Vector3(s * (w * 0.5 + 0.12), 0.05, 0.06), Vector3(0.3, h + 0.35, 0.05), col)
	_b(m, xf, Vector3(0, h * 0.5 + 0.25, 0.07), Vector3(w + 0.7, 0.03, 0.03), Color(0.3, 0.3, 0.3))


## A ceiling light (xf: on the ceiling).
static func ceiling_light(m: MeshData, xf: Transform3D, broken := false) -> void:
	if broken:
		_b(m, xf, Vector3(0, -0.02, 0), Vector3(0.12, 0.04, 0.12), Color(0.85, 0.85, 0.82))
		_b(m, xf, Vector3(0, -0.25, 0), Vector3(0.01, 0.45, 0.01), Color(0.1, 0.1, 0.1))
		_b(m, xf, Vector3(0, -0.5, 0), Vector3(0.08, 0.08, 0.08), Color(0.9, 0.88, 0.75))
	else:
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0)), Vector3(0.42, 0.08, 0.42), Color(0.94, 0.93, 0.86), false)
		m.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.085, 0)), Vector3(0.3, 0.02, 0.3), Color(0.98, 0.96, 0.85), false)


## A dark skirting board along a wall (from a to b, local XZ, at floor y).
static func baseboard(m: MeshData, a: Vector3, b: Vector3, inward: Vector3, col: Color) -> void:
	var mid := (a + b) * 0.5 + inward * 0.012 + Vector3(0, 0.05, 0)
	var dir := (b - a)
	var len := dir.length()
	if len < 0.1:
		return
	var basis := Basis(dir / len, Vector3.UP, (dir / len).cross(Vector3.UP))
	m.box(Transform3D(basis, mid), Vector3(len, 0.1, 0.024), col)


## Small things left on a surface `top` metres up (a counter, a table).
static func table_clutter(m: MeshData, xf: Transform3D, top: float, area: Vector2, rng: RandomNumberGenerator, kitchen := false) -> void:
	for k in rng.randi_range(1, 4):
		var p := Vector3(rng.randf_range(-area.x, area.x) * 0.4, top, rng.randf_range(-area.y, area.y) * 0.35)
		var t := xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		match rng.randi() % (6 if kitchen else 5):
			0:
				cup(m, t, Color.from_hsv(rng.randf(), 0.4, 0.8))
			1:
				bottle(m, t, [Color(0.2, 0.4, 0.2), Color(0.45, 0.3, 0.15), Color(0.7, 0.8, 0.85)][rng.randi() % 3], rng.randf() < 0.4)
			2:
				books(m, t, rng)
			3:
				flat(m, t, Vector2(0.21, 0.29), PAPER, 0.004)
			4:
				can(m, t, Color.from_hsv(rng.randf(), 0.6, 0.6))
			_:
				plate(m, t)
