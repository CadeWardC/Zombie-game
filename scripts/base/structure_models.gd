class_name StructureModels
extends RefCounted
## Low-poly models of buildable structures, made in code. Origin on the
## ground at the middle of the footprint; the front faces +Z.

const WOOD := Color(0.5, 0.36, 0.22)
const WOOD_DARK := Color(0.36, 0.25, 0.15)
const METAL := Color(0.42, 0.43, 0.44)
const STONE := Color(0.45, 0.44, 0.42)
const DIRT := Color(0.3, 0.21, 0.13)


static func build(t: String) -> MeshData:
	var m := MeshData.new()
	var d := Structures.get_def(t)
	var s: Vector3 = d.size
	match t:
		"wall", "gate":
			var n := 9
			for i in n:
				var x := -s.x * 0.5 + (i + 0.5) * s.x / n
				var h := s.y - (0.08 if i % 2 == 0 else 0.0)
				var col := WOOD if i % 3 != 1 else WOOD.darkened(0.08)
				_b(m, Vector3(x, h * 0.5, 0), Vector3(s.x / n - 0.012, h, 0.06), col)
				# Pointed tops.
				m.box(Transform3D(Basis(Vector3.FORWARD, PI * 0.25), Vector3(x, h, 0)), Vector3(0.11, 0.11, 0.06), col, false)
			for y: float in [0.45, s.y - 0.5]:
				_b(m, Vector3(0, y, 0.06), Vector3(s.x, 0.14, 0.05), WOOD_DARK)
				_b(m, Vector3(0, y, -0.06), Vector3(s.x, 0.14, 0.05), WOOD_DARK)
			if t == "gate":
				# Diagonal brace and hinges.
				var len := sqrt(s.x * s.x + (s.y - 1.0) * (s.y - 1.0))
				m.box(Transform3D(Basis(Vector3.FORWARD, atan2(s.y - 1.0, s.x)), Vector3(0, s.y * 0.5, 0.07)), Vector3(len, 0.12, 0.05), WOOD_DARK, false)
				for y: float in [0.45, s.y - 0.5]:
					_b(m, Vector3(-s.x * 0.5 + 0.08, y, 0.09), Vector3(0.18, 0.06, 0.02), METAL)
				_b(m, Vector3(s.x * 0.5 - 0.15, 1.1, 0.1), Vector3(0.05, 0.18, 0.04), METAL)
		"spikes":
			for z: float in [-0.25, 0.25]:
				_b(m, Vector3(0, 0.35, z), Vector3(s.x, 0.12, 0.12), WOOD_DARK)
			for i in 7:
				var x := -s.x * 0.5 + 0.15 + i * (s.x - 0.3) / 6.0
				var basis := Basis(Vector3.RIGHT, -0.55 if i % 2 == 0 else 0.55)
				m.append(_stake(1.15), Transform3D(basis, Vector3(x, 0.05, 0)))
		"watchtower":
			var h := 3.0
			for x: float in [-1.0, 1.0]:
				for z: float in [-1.0, 1.0]:
					m.cylinder(Vector3(x * (s.x * 0.5 - 0.15), 0, z * (s.z * 0.5 - 0.15)), 0.13, 0.11, s.y, 6, WOOD_DARK)
			_b(m, Vector3(0, h, 0), Vector3(s.x, 0.12, s.z), WOOD)
			for i in 6:
				_b(m, Vector3(-s.x * 0.5 + 0.2 + i * (s.x - 0.4) / 5.0, h + 0.07, 0), Vector3(0.02, 0.02, s.z), WOOD_DARK)
			# Railing on three sides; the ladder side (+Z) has a gap.
			for side: Vector3 in [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
				var along := Vector3(absf(side.z), 0, absf(side.x))
				var c := side * (s.x * 0.5 - 0.05) + Vector3(0, h + 0.55, 0)
				_b(m, c, along * s.x + Vector3(0.06, 0.08, 0.06) - along * 0.06, WOOD)
				_b(m, c - Vector3(0, 0.3, 0), along * s.x + Vector3(0.06, 0.06, 0.06) - along * 0.06, WOOD)
			for x: float in [-0.3, 0.3]:
				_b(m, Vector3(x, h * 0.5, s.z * 0.5 + 0.1), Vector3(0.07, h, 0.07), WOOD_DARK)
			for k in 8:
				_b(m, Vector3(0, 0.3 + k * 0.38, s.z * 0.5 + 0.1), Vector3(0.6, 0.05, 0.06), WOOD)
			# Cross bracing.
			for z: float in [-1.0, 1.0]:
				m.box(Transform3D(Basis(Vector3.FORWARD, 0.9), Vector3(0, h * 0.45, z * (s.z * 0.5 - 0.15))), Vector3(3.0, 0.1, 0.06), WOOD_DARK, false)
		"crate":
			_b(m, Vector3(0, s.y * 0.5, 0), s - Vector3(0.04, 0.02, 0.04), WOOD.darkened(0.15))
			for y: float in [0.12, s.y * 0.5, s.y - 0.12]:
				_b(m, Vector3(0, y, 0), Vector3(s.x, 0.1, s.z), WOOD)
			for x: float in [-1.0, 1.0]:
				_b(m, Vector3(x * (s.x * 0.5 - 0.04), s.y * 0.5, 0), Vector3(0.09, s.y, s.z + 0.01), WOOD_DARK)
		"bed":
			_b(m, Vector3(0, 0.2, 0), Vector3(s.x, 0.18, s.z), WOOD_DARK)
			for x: float in [-1.0, 1.0]:
				for z: float in [-1.0, 1.0]:
					_b(m, Vector3(x * (s.x * 0.5 - 0.05), 0.1, z * (s.z * 0.5 - 0.05)), Vector3(0.08, 0.2, 0.08), WOOD_DARK)
			_b(m, Vector3(0, 0.36, 0), Vector3(s.x - 0.08, 0.14, s.z - 0.08), Color(0.65, 0.62, 0.55))
			_b(m, Vector3(0, 0.47, -s.z * 0.5 + 0.25), Vector3(s.x - 0.25, 0.1, 0.32), Color(0.85, 0.85, 0.82))
			_b(m, Vector3(0, 0.45, 0.2), Vector3(s.x - 0.06, 0.06, s.z * 0.6), Color(0.3, 0.38, 0.5))
			_b(m, Vector3(0, 0.45, -s.z * 0.5 + 0.03), Vector3(s.x, 0.5, 0.06), WOOD)
		"workbench":
			_b(m, Vector3(0, s.y - 0.05, 0), Vector3(s.x, 0.1, s.z), WOOD)
			for x: float in [-1.0, 1.0]:
				for z: float in [-1.0, 1.0]:
					_b(m, Vector3(x * (s.x * 0.5 - 0.08), (s.y - 0.1) * 0.5, z * (s.z * 0.5 - 0.08)), Vector3(0.09, s.y - 0.1, 0.09), WOOD_DARK)
			_b(m, Vector3(0, 0.25, 0), Vector3(s.x - 0.2, 0.06, s.z - 0.2), WOOD_DARK)
			_b(m, Vector3(s.x * 0.5 - 0.15, s.y + 0.06, s.z * 0.5 - 0.1), Vector3(0.18, 0.12, 0.1), METAL) # vise
			_b(m, Vector3(-0.3, s.y + 0.02, 0), Vector3(0.3, 0.03, 0.05), Color(0.6, 0.1, 0.08)) # tools lying on it
			_b(m, Vector3(-0.2, s.y + 0.02, -0.15), Vector3(0.05, 0.03, 0.28), METAL)
			_b(m, Vector3(0, s.y * 0.5 + 0.2, -s.z * 0.5 + 0.02), Vector3(s.x, 0.6, 0.03), WOOD.darkened(0.2)) # pegboard
		"campfire":
			for i in 9:
				var a := TAU * i / 9.0
				_b(m, Vector3(cos(a) * 0.42, 0.08, sin(a) * 0.42), Vector3(0.2, 0.16, 0.16), STONE.darkened(0.1 * (i % 3)))
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				m.box(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.5), Vector3(cos(a) * 0.12, 0.15, sin(a) * 0.12)), Vector3(0.09, 0.09, 0.5), WOOD_DARK, false)
			_b(m, Vector3(0, 0.02, 0), Vector3(0.55, 0.03, 0.55), Color(0.12, 0.11, 0.1))
		"rain_collector":
			m.cylinder(Vector3(0, 0, 0), 0.32, 0.32, 0.9, 10, Color(0.2, 0.35, 0.55))
			for y: float in [0.2, 0.7]:
				m.cylinder(Vector3(0, y, 0), 0.335, 0.335, 0.04, 10, Color(0.15, 0.25, 0.4), false)
			for x: float in [-1.0, 1.0]:
				for z: float in [-1.0, 1.0]:
					_b(m, Vector3(x * 0.48, 0.65, z * 0.48), Vector3(0.06, 1.3, 0.06), WOOD_DARK)
			m.cylinder(Vector3(0, 0.95, 0), 0.08, 0.55, 0.3, 8, Color(0.25, 0.4, 0.3)) # tarp funnel
		"farm_plot":
			_b(m, Vector3(0, 0.08, 0), Vector3(s.x - 0.1, 0.14, s.z - 0.1), DIRT)
			for k in 4:
				_b(m, Vector3(0, 0.16, -s.z * 0.5 + 0.3 + k * (s.z - 0.6) / 3.0), Vector3(s.x - 0.3, 0.05, 0.18), DIRT.darkened(0.15))
			for side: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
				var along := Vector3(absf(side.z), 0, absf(side.x))
				_b(m, side * (s.x * 0.5 - 0.04) + Vector3(0, 0.1, 0), along * s.x + Vector3(0.08, 0.2, 0.08) - along * 0.08, WOOD)
	return m


## A crop at growth stage 0..1 (drawn on a farm plot, 4 plants).
static func crop(kind: String, growth: float) -> MeshData:
	var m := MeshData.new()
	var leaf := Color(0.25, 0.5, 0.18).lerp(Color(0.35, 0.55, 0.2), growth)
	var h := lerpf(0.1, {"corn": 1.6, "tomato": 0.8, "potato": 0.45, "carrot": 0.35}.get(kind, 0.5), growth)
	for i in 4:
		var p := Vector3(-0.5 + (i % 2) * 1.0, 0.15, -0.5 + int(i / 2) * 1.0)
		m.box(Transform3D(Basis(Vector3.UP, i * 0.8), p + Vector3(0, h * 0.5, 0)), Vector3(0.05, h, 0.05), leaf.darkened(0.2), false)
		for k in 3:
			var a := i * 0.8 + k * TAU / 3.0
			m.box(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.6), p + Vector3(cos(a) * 0.08, h * (0.4 + k * 0.2), sin(a) * 0.08)),
				Vector3(0.12 + growth * 0.1, 0.02, 0.22 + growth * 0.15), leaf, false)
		if growth >= 1.0:
			var fruit: Color = {"tomato": Color(0.8, 0.12, 0.08), "corn": Color(0.9, 0.78, 0.25), "carrot": Color(0.9, 0.45, 0.1), "potato": Color(0.6, 0.48, 0.3)}.get(kind, Color.WHITE)
			_b(m, p + Vector3(0.08, h * 0.6 if kind in ["tomato", "corn"] else 0.05, 0.05), Vector3(0.1, 0.12 if kind != "corn" else 0.25, 0.1), fruit)
	return m


static func _b(m: MeshData, pos: Vector3, size: Vector3, col: Color) -> void:
	m.box(Transform3D(Basis.IDENTITY, pos), size, col, false)


static func _stake(length: float) -> MeshData:
	var m := MeshData.new()
	m.cylinder(Vector3.ZERO, 0.06, 0.06, length * 0.8, 5, WOOD)
	m.cylinder(Vector3(0, length * 0.8, 0), 0.06, 0.005, length * 0.2, 5, Color(0.75, 0.62, 0.45))
	return m
