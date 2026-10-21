class_name MeshData
extends RefCounted
## Accumulates flat-shaded triangles (with colour and optional UV) on worker
## threads. Turned into an ArrayMesh on the main thread via arrays().

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var use_uv := false


func _init(with_uv := false) -> void:
	use_uv = with_uv


func is_empty() -> bool:
	return verts.is_empty()


## Adds a triangle; the winding is flipped if needed so it faces `facing`.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, facing: Vector3,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	var n := (c - a).cross(b - a)
	if n.dot(facing) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
		n = -n
	n = n.normalized()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	colors.append(col)
	colors.append(col)
	colors.append(col)
	if use_uv:
		uvs.append(ua)
		uvs.append(ub)
		uvs.append(uc)


## Quad a-b-c-d (in order around the edge).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, facing: Vector3,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO) -> void:
	tri(a, b, c, col, facing, ua, ub, uc)
	tri(a, c, d, col, facing, ua, uc, ud)


## Box of `size` centred on xf.origin, oriented by xf.basis.
## `skip_bottom` drops the underside (invisible on things standing on ground).
func box(xf: Transform3D, size: Vector3, col: Color, skip_bottom := true) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for k in 8:
		p.append(xf * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
	var o := xf.origin
	_face(p[2], p[3], p[7], p[6], col, o) # top
	if not skip_bottom:
		_face(p[0], p[1], p[5], p[4], col, o)
	_face(p[0], p[1], p[3], p[2], col, o) # -z
	_face(p[4], p[5], p[7], p[6], col, o) # +z
	_face(p[0], p[4], p[6], p[2], col, o) # -x
	_face(p[1], p[5], p[7], p[3], col, o) # +x


func _face(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, center: Vector3) -> void:
	quad(a, b, c, d, col, (a + c) * 0.5 - center)


## Vertical cylinder / cone (r_top == 0) standing at `base`.
func cylinder(base: Vector3, r_bottom: float, r_top: float, height: float, sides: int, col: Color, cap := true) -> void:
	var top := base + Vector3(0, height, 0)
	var mid := base + Vector3(0, height * 0.5, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var b0 := base + Vector3(cos(a0) * r_bottom, 0, sin(a0) * r_bottom)
		var b1 := base + Vector3(cos(a1) * r_bottom, 0, sin(a1) * r_bottom)
		var out := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		if r_top <= 0.0:
			tri(b0, b1, top, col, out + Vector3(0, r_bottom / height, 0))
		else:
			var t0 := top + Vector3(cos(a0) * r_top, 0, sin(a0) * r_top)
			var t1 := top + Vector3(cos(a1) * r_top, 0, sin(a1) * r_top)
			quad(b0, b1, t1, t0, col, out)
			if cap:
				tri(top, t0, t1, col, Vector3.UP)


## Appends another MeshData transformed by xf.
func append(other: MeshData, xf: Transform3D) -> void:
	var basis := xf.basis
	for k in other.verts.size():
		verts.append(xf * other.verts[k])
		normals.append((basis * other.normals[k]).normalized())
		colors.append(other.colors[k])
		if use_uv:
			uvs.append(other.uvs[k] if other.use_uv else Vector2.ZERO)


func arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	if use_uv:
		arr[Mesh.ARRAY_TEX_UV] = uvs
	return arr


func to_mesh(material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays())
	mesh.surface_set_material(0, material)
	return mesh
