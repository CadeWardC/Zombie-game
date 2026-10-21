class_name PropModels
extends RefCounted
## Nature and street props as MeshData (origin on the ground).

static func build(type: String) -> MeshData:
	var m := MeshData.new()
	match type:
		"pine":
			m.cylinder(Vector3.ZERO, 0.24, 0.12, 2.2, 6, Color(0.3, 0.22, 0.15), false)
			var layers := 5
			for k in layers:
				var t := float(k) / layers
				var col := Color(0.14, 0.25, 0.14).lightened(t * 0.12)
				m.cylinder(Vector3(0, 1.2 + k * 1.15, 0), lerpf(2.1, 0.7, t), 0.0, 2.2 - t * 0.6, 7, col)
		"pine_far":
			m.cylinder(Vector3(0, 0.6, 0), 1.9, 0.0, 6.6, 5, Color(0.15, 0.26, 0.15))
		"broadleaf", "yard_tree":
			var s := 1.0 if type == "broadleaf" else 0.75
			m.cylinder(Vector3.ZERO, 0.25 * s, 0.17 * s, 3.0 * s, 6, Color(0.33, 0.25, 0.17), false)
			var greens := [Color(0.22, 0.34, 0.15), Color(0.26, 0.38, 0.17), Color(0.2, 0.3, 0.14)]
			for blob in [Vector3(0, 3.8, 0), Vector3(1.0, 3.3, 0.4), Vector3(-0.9, 3.4, -0.3), Vector3(0.2, 4.6, -0.6), Vector3(-0.3, 3.2, 0.9)]:
				_blob(m, blob * s, 1.5 * s, greens[absi(int(blob.x * 10)) % 3])
		"broadleaf_far":
			m.cylinder(Vector3.ZERO, 0.2, 0.15, 2.8, 4, Color(0.33, 0.25, 0.17), false)
			_blob(m, Vector3(0, 3.9, 0), 2.3, Color(0.23, 0.34, 0.16))
		"dead_tree":
			var c := Color(0.33, 0.29, 0.25)
			m.cylinder(Vector3.ZERO, 0.22, 0.08, 4.5, 5, c, false)
			for b in [[Vector3(0, 2.4, 0), Vector3(1.0, 0.7, 0.2)], [Vector3(0, 3.2, 0), Vector3(-0.8, 0.6, -0.3)], [Vector3(0, 1.8, 0), Vector3(0.1, 0.5, -0.9)]]:
				var dir: Vector3 = b[1]
				var basis := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.9 else Vector3.RIGHT)
				m.box(Transform3D(basis, b[0] + dir * 0.5), Vector3(0.08, 0.08, dir.length()), c)
		"bush":
			_blob(m, Vector3(0, 0.45, 0), 0.75, Color(0.24, 0.34, 0.16))
			_blob(m, Vector3(0.5, 0.35, 0.2), 0.5, Color(0.27, 0.37, 0.18))
		"dry_bush":
			_blob(m, Vector3(0, 0.35, 0), 0.55, Color(0.48, 0.42, 0.26))
		"cactus":
			var g := Color(0.3, 0.42, 0.22)
			m.cylinder(Vector3.ZERO, 0.28, 0.24, 4.0, 8, g)
			m.cylinder(Vector3(0.65, 1.6, 0), 0.18, 0.16, 1.4, 6, g)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0.38, 1.6, 0)), Vector3(0.6, 0.3, 0.3), g)
			m.cylinder(Vector3(-0.6, 2.2, 0), 0.16, 0.14, 1.1, 6, g)
			m.box(Transform3D(Basis.IDENTITY, Vector3(-0.35, 2.2, 0)), Vector3(0.55, 0.28, 0.28), g)
		"rock":
			var c := Color(0.43, 0.42, 0.4)
			m.cylinder(Vector3(0, -0.3, 0), 1.1, 0.5, 1.2, 6, c)
			m.cylinder(Vector3(0.5, -0.2, 0.3), 0.6, 0.25, 0.8, 5, c.darkened(0.1))
		"streetlight":
			var c := Color(0.35, 0.36, 0.38)
			m.cylinder(Vector3.ZERO, 0.12, 0.08, 7.0, 6, c)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 6.9, 0.9)), Vector3(0.1, 0.1, 1.8), c)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 6.8, 1.8)), Vector3(0.35, 0.15, 0.6), c)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 6.71, 1.8)), Vector3(0.3, 0.02, 0.5), Color(0.9, 0.88, 0.75))
		"utility_pole":
			var w := Color(0.36, 0.28, 0.2)
			m.cylinder(Vector3.ZERO, 0.16, 0.12, 9.0, 6, w)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 8.4, 0)), Vector3(2.2, 0.12, 0.12), w)
		"hydrant":
			var r := Color(0.75, 0.12, 0.08)
			m.cylinder(Vector3.ZERO, 0.16, 0.14, 0.65, 8, r)
			m.cylinder(Vector3(0, 0.65, 0), 0.14, 0.05, 0.15, 8, r)
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.42, 0)), Vector3(0.45, 0.1, 0.1), r)
		"mailbox":
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)), Vector3(0.08, 1.1, 0.08), Color(0.35, 0.26, 0.18))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.15, 0)), Vector3(0.24, 0.24, 0.5), Color(0.25, 0.27, 0.3))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0.13, 1.25, -0.1)), Vector3(0.02, 0.18, 0.06), Color(0.8, 0.1, 0.1))
		"fuel_pump":
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), Vector3(1.4, 0.2, 0.9), Color(0.6, 0.6, 0.58))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)), Vector3(0.8, 1.6, 0.5), Color(0.85, 0.85, 0.85))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.85, 0)), Vector3(0.85, 0.25, 0.55), Color(0.75, 0.15, 0.12))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0.26)), Vector3(0.4, 0.3, 0.02), Color(0.1, 0.12, 0.1))
		"road_sign":
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0)), Vector3(0.07, 2.4, 0.07), Color(0.6, 0.6, 0.62))
			m.box(Transform3D(Basis.IDENTITY, Vector3(0, 2.4, 0.04)), Vector3(1.6, 0.9, 0.04), Color(0.1, 0.35, 0.2))
	return m


## A rough low-poly sphere (octahedron-ish with a ring), cheap and blobby.
static func _blob(m: MeshData, c: Vector3, r: float, col: Color) -> void:
	var top := c + Vector3(0, r * 0.9, 0)
	var bottom := c - Vector3(0, r * 0.7, 0)
	var ring: Array[Vector3] = []
	var n := 6
	for i in n:
		var a := TAU * i / n + c.x
		ring.append(c + Vector3(cos(a) * r, (0.15 if i % 2 == 0 else -0.1) * r, sin(a) * r))
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		m.tri(a, b, top, col.lightened(0.05), ((a + b + top) / 3.0) - c)
		m.tri(a, b, bottom, col.darkened(0.1), ((a + b + bottom) / 3.0) - c)
