class_name Assets
extends RefCounted
## Shared meshes, materials and collision shapes, built once at startup on
## the main thread and reused everywhere (chunks, zombies, pickups).

static var material: StandardMaterial3D # Vertex-coloured, back-face culled.
static var double_sided_material: StandardMaterial3D
static var terrain_material: StandardMaterial3D
static var building_material: StandardMaterial3D
static var road_material: StandardMaterial3D
static var glass_material: StandardMaterial3D
static var water_material: ShaderMaterial
static var door_material: StandardMaterial3D

static var props := {} # name -> ArrayMesh
static var cars: Array[ArrayMesh] = []
static var car_shape: BoxShape3D
static var door_mesh: ArrayMesh
static var tree_shape: CylinderShape3D
static var zombie_meshes: Array[ArrayMesh] = []
static var zombie_shape: CapsuleShape3D
static var item_meshes := {}
static var item_shape: SphereShape3D
static var weapon_mesh: ArrayMesh
static var _built := false

const PROP_NAMES := ["pine", "pine_far", "broadleaf", "broadleaf_far", "yard_tree", "dead_tree", "bush", "dry_bush",
	"cactus", "rock", "streetlight", "utility_pole", "hydrant", "mailbox", "fuel_pump", "road_sign"]
const AIRCRAFT := ["airliner", "prop_plane", "helicopter"]
const CAR_COUNT := 16 # 14 everyday cars + ambulance + school bus.


static func build() -> void:
	if _built:
		return
	_built = true
	material = _vc_material(BaseMaterial3D.CULL_BACK)
	double_sided_material = _vc_material(BaseMaterial3D.CULL_DISABLED)
	terrain_material = _vc_material(BaseMaterial3D.CULL_DISABLED)
	building_material = _vc_material(BaseMaterial3D.CULL_DISABLED)
	door_material = _vc_material(BaseMaterial3D.CULL_DISABLED)
	road_material = StandardMaterial3D.new()
	road_material.albedo_texture = Textures.road_atlas()
	road_material.roughness = 0.95
	road_material.metallic_specular = 0.2
	road_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	road_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	glass_material = StandardMaterial3D.new()
	glass_material.vertex_color_use_as_albedo = true
	glass_material.vertex_color_is_srgb = true
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.albedo_color = Color(1, 1, 1, 0.35)
	glass_material.roughness = 0.05
	glass_material.metallic_specular = 0.8
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_material = Textures.water_material()

	for p in PROP_NAMES:
		props[p] = PropModels.build(p).to_mesh(material)
	for a in AIRCRAFT:
		props[a] = CarModels.aircraft(a).to_mesh(material)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 14:
		var type: String = CarModels.TYPES[k % CarModels.TYPES.size()]
		var paint: Color = CarModels.PAINTS[rng.randi() % CarModels.PAINTS.size()]
		cars.append(CarModels.build(type, paint, rng.randf() * 0.6).to_mesh(material))
	for extra in ["ambulance", "school_bus"]:
		cars.append(CarModels.build(extra, Color.WHITE, 0.3).to_mesh(material))
	car_shape = BoxShape3D.new()
	car_shape.size = Vector3(1.9, 1.5, 4.7)

	var dm := MeshData.new()
	dm.box(Transform3D(Basis.IDENTITY, Vector3(0.5, 0.5, 0)), Vector3.ONE, Color.WHITE, false)
	door_mesh = dm.to_mesh(door_material)

	tree_shape = CylinderShape3D.new()
	tree_shape.radius = 0.3
	tree_shape.height = 4.0
	_build_zombies()
	ZombieModel.build_assets()
	_build_items()
	_build_weapon()


## Per-vertex lighting is much cheaper on weak GPUs and looks almost the same
## on flat-shaded low-poly geometry.
static func set_per_vertex_lighting(enabled: bool) -> void:
	var mode := BaseMaterial3D.SHADING_MODE_PER_VERTEX if enabled else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for m in [material, double_sided_material, terrain_material, building_material, door_material, road_material]:
		m.shading_mode = mode


static func _vc_material(cull: BaseMaterial3D.CullMode) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.cull_mode = cull
	return m


static func _build_zombies() -> void:
	var skin := Color(0.42, 0.5, 0.36)
	var pants := Color(0.2, 0.22, 0.28)
	var shirts := [Color(0.5, 0.18, 0.15), Color(0.25, 0.3, 0.4), Color(0.55, 0.52, 0.45)]
	for shirt in shirts:
		var st := MeshFactory.begin()
		for x: float in [-0.12, 0.12]:
			MeshFactory.box(st, Vector3(x, 0.425, 0), Vector3(0.2, 0.85, 0.22), pants)
			MeshFactory.box(st, Vector3(x * 2.65, 1.4, -0.25), Vector3(0.13, 0.13, 0.6), skin)
		MeshFactory.box(st, Vector3(0, 1.175, 0), Vector3(0.5, 0.65, 0.28), shirt)
		MeshFactory.box(st, Vector3(0, 1.68, -0.03), Vector3(0.3, 0.32, 0.3), skin)
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
