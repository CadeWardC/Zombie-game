class_name MeshFactory
extends RefCounted
## Helpers for building flat-shaded, vertex-coloured low-poly meshes in code.
## Every face gets its own vertices so normals stay flat (the low-poly look).
## Faces are oriented automatically so they point away from a given centre,
## which keeps convex primitives correct without hand-ordering vertices.


static func tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3, color: Color) -> void:
	# Godot treats clockwise triangles as front-facing; this normal matches that.
	var n := (c - a).cross(b - a)
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	n = n.normalized()
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func quad_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, center: Vector3, color: Color) -> void:
	tri_out(st, a, b, c, center, color)
	tri_out(st, a, c, d, center, color)


## Axis-aligned box centred on `center`.
static func box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var p := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z), center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z), center + Vector3(h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	quad_out(st, p[0], p[1], p[2], p[3], center, color) # bottom
	quad_out(st, p[4], p[5], p[6], p[7], center, color) # top
	quad_out(st, p[0], p[1], p[5], p[4], center, color) # -z
	quad_out(st, p[3], p[2], p[6], p[7], center, color) # +z
	quad_out(st, p[0], p[3], p[7], p[4], center, color) # -x
	quad_out(st, p[1], p[2], p[6], p[5], center, color) # +x


## Cylinder (or cone when r_top == 0) standing on `base`.
static func cylinder(st: SurfaceTool, base: Vector3, r_bottom: float, r_top: float, height: float, sides: int, color: Color, angle_offset := 0.0) -> void:
	var center := base + Vector3(0, height * 0.5, 0)
	var top := base + Vector3(0, height, 0)
	for i in sides:
		var a0 := angle_offset + TAU * i / sides
		var a1 := angle_offset + TAU * (i + 1) / sides
		var b0 := base + Vector3(cos(a0) * r_bottom, 0, sin(a0) * r_bottom)
		var b1 := base + Vector3(cos(a1) * r_bottom, 0, sin(a1) * r_bottom)
		if r_top <= 0.0:
			tri_out(st, b0, b1, top, center, color)
		else:
			var t0 := top + Vector3(cos(a0) * r_top, 0, sin(a0) * r_top)
			var t1 := top + Vector3(cos(a1) * r_top, 0, sin(a1) * r_top)
			quad_out(st, b0, b1, t1, t0, center, color)
			tri_out(st, top, t0, t1, center, color)
		tri_out(st, base, b1, b0, center, color)


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func finish(st: SurfaceTool, material: Material) -> ArrayMesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	return mesh
