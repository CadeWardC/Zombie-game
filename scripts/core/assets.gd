class_name Assets
extends RefCounted
## Shared meshes, materials and collision shapes. Built once on the main thread
## at startup and reused by every chunk, zombie and pickup.

const HOUSE_W := 10.0
const HOUSE_D := 8.0
const HOUSE_H := 3.0
const WALL_T := 0.25
const DOOR_W := 1.6
const DOOR_H := 2.3

static var material: StandardMaterial3D
static var double_sided_material: StandardMaterial3D
static var terrain_material: StandardMaterial3D
static var tree_mesh: ArrayMesh
static var tree_far_mesh: ArrayMesh
static var dead_tree_mesh: ArrayMesh
static var rock_mesh: ArrayMesh
static var car_mesh: ArrayMesh
static var house_meshes: Array[ArrayMesh] = []
static var zombie_meshes: Array[ArrayMesh] = []
static var item_meshes := {}
static var weapon_mesh: ArrayMesh
## Array of [Transform3D, Shape3D] pairs in house-local space.
static var house_shapes: Array = []
static var car_shape: BoxShape3D
static var tree_shape: CylinderShape3D
static var zombie_shape: CapsuleShape3D
static var item_shape: SphereShape3D
static var _built := false


static func build() -> void:
	if _built:
		return
	_built = true
	material = _make_material(BaseMaterial3D.CULL_BACK)
	double_sided_material = _make_material(BaseMaterial3D.CULL_DISABLED)
	terrain_material = _make_material(BaseMaterial3D.CULL_DISABLED)
	_build_trees()
	_build_rock()
	_build_car()
	_build_houses()
	_build_zombies()
	_build_items()
	_build_weapon()


## Per-vertex lighting is much cheaper on weak GPUs and looks almost the same
## on flat-shaded low-poly geometry.
static func set_per_vertex_lighting(enabled: bool) -> void:
	var mode := BaseMaterial3D.SHADING_MODE_PER_VERTEX if enabled else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for m in [material, double_sided_material, terrain_material]:
		m.shading_mode = mode


static func _make_material(cull: BaseMaterial3D.CullMode) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.cull_mode = cull
	return m


static func _build_trees() -> void:
	var trunk := Color(0.3, 0.22, 0.15)
	var st := MeshFactory.begin()
	MeshFactory.cylinder(st, Vector3.ZERO, 0.22, 0.15, 1.5, 5, trunk)
	MeshFactory.cylinder(st, Vector3(0, 1.0, 0), 1.5, 0.0, 2.4, 6, Color(0.16, 0.27, 0.15))
	MeshFactory.cylinder(st, Vector3(0, 2.2, 0), 1.15, 0.0, 2.0, 6, Color(0.18, 0.3, 0.16), 0.5)
	MeshFactory.cylinder(st, Vector3(0, 3.3, 0), 0.8, 0.0, 1.6, 6, Color(0.2, 0.33, 0.18))
	tree_mesh = MeshFactory.finish(st, material)

	st = MeshFactory.begin()
	MeshFactory.cylinder(st, Vector3(0, 0.4, 0), 1.4, 0.0, 4.6, 4, Color(0.17, 0.28, 0.16))
	tree_far_mesh = MeshFactory.finish(st, material)

	var dead := Color(0.33, 0.29, 0.25)
	st = MeshFactory.begin()
	MeshFactory.cylinder(st, Vector3.ZERO, 0.2, 0.07, 4.2, 4, dead)
	MeshFactory.box(st, Vector3(0.45, 2.4, 0), Vector3(0.9, 0.1, 0.1), dead)
	MeshFactory.box(st, Vector3(-0.35, 3.1, 0.1), Vector3(0.7, 0.08, 0.08), dead)
	MeshFactory.box(st, Vector3(0, 1.8, -0.4), Vector3(0.08, 0.08, 0.8), dead)
	dead_tree_mesh = MeshFactory.finish(st, material)

	tree_shape = CylinderShape3D.new()
	tree_shape.radius = 0.3
	tree_shape.height = 4.0


static func _build_rock() -> void:
	var st := MeshFactory.begin()
	MeshFactory.cylinder(st, Vector3(0, -0.2, 0), 1.0, 0.55, 1.0, 5, Color(0.42, 0.41, 0.39))
	rock_mesh = MeshFactory.finish(st, material)


static func _build_car() -> void:
	var st := MeshFactory.begin()
	MeshFactory.box(st, Vector3(0, 0.65, 0), Vector3(1.8, 0.75, 4.2), Color(0.45, 0.26, 0.18))
	MeshFactory.box(st, Vector3(0, 1.3, 0.2), Vector3(1.6, 0.6, 2.0), Color(0.16, 0.19, 0.21))
	for x in [-0.85, 0.85]:
		for z in [-1.3, 1.3]:
			MeshFactory.box(st, Vector3(x, 0.3, z), Vector3(0.25, 0.6, 0.6), Color(0.08, 0.08, 0.08))
	car_mesh = MeshFactory.finish(st, material)
	car_shape = BoxShape3D.new()
	car_shape.size = Vector3(1.8, 1.6, 4.2)


static func _build_houses() -> void:
	var walls := [Color(0.62, 0.58, 0.5), Color(0.5, 0.55, 0.6), Color(0.58, 0.42, 0.37)]
	var roofs := [Color(0.3, 0.2, 0.18), Color(0.24, 0.26, 0.3), Color(0.28, 0.28, 0.25)]
	var w := HOUSE_W
	var d := HOUSE_D
	var h := HOUSE_H
	var t := WALL_T
	var side_w := (w - DOOR_W) * 0.5
	# [center, size] for each solid wall piece; shared by mesh and collision.
	var pieces := [
		[Vector3(0, h * 0.5, -d * 0.5 + t * 0.5), Vector3(w, h, t)],
		[Vector3(-w * 0.5 + t * 0.5, h * 0.5, 0), Vector3(t, h, d)],
		[Vector3(w * 0.5 - t * 0.5, h * 0.5, 0), Vector3(t, h, d)],
		[Vector3(-w * 0.5 + side_w * 0.5, h * 0.5, d * 0.5 - t * 0.5), Vector3(side_w, h, t)],
		[Vector3(w * 0.5 - side_w * 0.5, h * 0.5, d * 0.5 - t * 0.5), Vector3(side_w, h, t)],
		[Vector3(0, (DOOR_H + h) * 0.5, d * 0.5 - t * 0.5), Vector3(DOOR_W, h - DOOR_H, t)],
	]
	for v in walls.size():
		var st := MeshFactory.begin()
		for p in pieces:
			MeshFactory.box(st, p[0], p[1], walls[v])
		# Floor and dark windows.
		MeshFactory.box(st, Vector3(0, 0.03, 0), Vector3(w - t * 2.0, 0.06, d - t * 2.0), Color(0.36, 0.27, 0.2))
		for x in [-w * 0.5 - 0.02, w * 0.5 + 0.02]:
			MeshFactory.box(st, Vector3(x, 1.6, -1.5), Vector3(0.05, 1.0, 1.2), Color(0.1, 0.12, 0.14))
		MeshFactory.box(st, Vector3(-3.0, 1.6, -d * 0.5 - 0.02), Vector3(1.2, 1.0, 0.05), Color(0.1, 0.12, 0.14))
		MeshFactory.box(st, Vector3(3.0, 1.6, -d * 0.5 - 0.02), Vector3(1.2, 1.0, 0.05), Color(0.1, 0.12, 0.14))
		# Gabled roof (double-sided material so it also hides the sky from inside).
		var o := 0.4
		var ridge := h + 1.8
		var center := Vector3(0, h, 0)
		MeshFactory.quad_out(st, Vector3(-w * 0.5 - o, h - 0.1, d * 0.5 + o), Vector3(w * 0.5 + o, h - 0.1, d * 0.5 + o),
				Vector3(w * 0.5 + o, ridge, 0), Vector3(-w * 0.5 - o, ridge, 0), center, roofs[v])
		MeshFactory.quad_out(st, Vector3(-w * 0.5 - o, h - 0.1, -d * 0.5 - o), Vector3(w * 0.5 + o, h - 0.1, -d * 0.5 - o),
				Vector3(w * 0.5 + o, ridge, 0), Vector3(-w * 0.5 - o, ridge, 0), center, roofs[v])
		for x in [-w * 0.5, w * 0.5]:
			MeshFactory.tri_out(st, Vector3(x, h, -d * 0.5), Vector3(x, h, d * 0.5), Vector3(x, ridge - 0.15, 0), center, walls[v])
		house_meshes.append(MeshFactory.finish(st, double_sided_material))

	for p in pieces:
		var shape := BoxShape3D.new()
		shape.size = p[1]
		house_shapes.append([Transform3D(Basis.IDENTITY, p[0]), shape])
	var roof := BoxShape3D.new()
	roof.size = Vector3(w, 0.3, d)
	house_shapes.append([Transform3D(Basis.IDENTITY, Vector3(0, h + 0.15, 0)), roof])


static func _build_zombies() -> void:
	var skin := Color(0.42, 0.5, 0.36)
	var pants := Color(0.2, 0.22, 0.28)
	var shirts := [Color(0.5, 0.18, 0.15), Color(0.25, 0.3, 0.4), Color(0.55, 0.52, 0.45)]
	for shirt in shirts:
		var st := MeshFactory.begin()
		for x in [-0.12, 0.12]:
			MeshFactory.box(st, Vector3(x, 0.425, 0), Vector3(0.2, 0.85, 0.22), pants)
			MeshFactory.box(st, Vector3(x * 2.65, 1.4, -0.25), Vector3(0.13, 0.13, 0.6), skin)
		MeshFactory.box(st, Vector3(0, 1.175, 0), Vector3(0.5, 0.65, 0.28), shirt)
		MeshFactory.box(st, Vector3(0, 1.68, -0.03), Vector3(0.3, 0.32, 0.3), skin)
		for x in [-0.07, 0.07]:
			MeshFactory.box(st, Vector3(x, 1.72, -0.185), Vector3(0.06, 0.04, 0.02), Color(0.9, 0.1, 0.05))
		zombie_meshes.append(MeshFactory.finish(st, material))
	zombie_shape = CapsuleShape3D.new()
	zombie_shape.radius = 0.3
	zombie_shape.height = 1.8


static func _build_items() -> void:
	var st := MeshFactory.begin()
	MeshFactory.cylinder(st, Vector3.ZERO, 0.14, 0.14, 0.22, 8, Color(0.75, 0.15, 0.1))
	MeshFactory.cylinder(st, Vector3(0, 0.22, 0), 0.13, 0.13, 0.02, 8, Color(0.75, 0.75, 0.75))
	item_meshes["food"] = MeshFactory.finish(st, material)

	st = MeshFactory.begin()
	MeshFactory.cylinder(st, Vector3.ZERO, 0.1, 0.1, 0.38, 8, Color(0.2, 0.45, 0.85))
	MeshFactory.cylinder(st, Vector3(0, 0.38, 0), 0.05, 0.05, 0.06, 6, Color(0.9, 0.9, 0.95))
	item_meshes["water"] = MeshFactory.finish(st, material)

	st = MeshFactory.begin()
	MeshFactory.box(st, Vector3(0, 0.08, 0), Vector3(0.32, 0.16, 0.24), Color(0.92, 0.92, 0.9))
	MeshFactory.box(st, Vector3(0, 0.165, 0), Vector3(0.18, 0.01, 0.05), Color(0.85, 0.1, 0.1))
	MeshFactory.box(st, Vector3(0, 0.165, 0), Vector3(0.05, 0.01, 0.16), Color(0.85, 0.1, 0.1))
	item_meshes["bandage"] = MeshFactory.finish(st, material)

	item_shape = SphereShape3D.new()
	item_shape.radius = 0.9


static func _build_weapon() -> void:
	var st := MeshFactory.begin()
	MeshFactory.cylinder(st, Vector3.ZERO, 0.022, 0.022, 0.2, 6, Color(0.1, 0.1, 0.1))
	MeshFactory.cylinder(st, Vector3(0, 0.2, 0), 0.024, 0.045, 0.6, 6, Color(0.5, 0.34, 0.18))
	weapon_mesh = MeshFactory.finish(st, material)
