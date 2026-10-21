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
static var window_mesh: BoxMesh # Unit pane, scaled per window.
static var tree_shape: CylinderShape3D
static var zombie_shape: CapsuleShape3D
static var brute_shape: CapsuleShape3D
static var crawler_shape: BoxShape3D
static var item_meshes := {} # item id -> ArrayMesh (see ItemModels)
static var particle_material: StandardMaterial3D
static var flash_material: StandardMaterial3D # Additive glow (muzzle flash, explosions).
static var flame_mesh: ArrayMesh
static var muzzle_flash_mesh: ArrayMesh
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
	window_mesh = BoxMesh.new()
	window_mesh.size = Vector3(1.0, 1.0, 0.02)
	var wm := glass_material.duplicate() as StandardMaterial3D
	wm.vertex_color_use_as_albedo = false
	wm.albedo_color = Color(BuildingParts.GLASS, 0.35)
	window_mesh.material = wm

	tree_shape = CylinderShape3D.new()
	tree_shape.radius = 0.3
	tree_shape.height = 4.0
	zombie_shape = CapsuleShape3D.new()
	zombie_shape.radius = 0.3
	zombie_shape.height = 1.8
	brute_shape = CapsuleShape3D.new()
	brute_shape.radius = 0.42
	brute_shape.height = 2.25
	crawler_shape = BoxShape3D.new()
	crawler_shape.size = Vector3(0.6, 0.45, 1.5)
	ZombieModel.build_assets()
	_build_items()


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


static func _build_items() -> void:
	for id in ItemDB.ITEMS:
		item_meshes[id] = ItemModels.build(id).to_mesh(material)
	particle_material = StandardMaterial3D.new()
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	flash_material = StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.vertex_color_use_as_albedo = true
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash_material.albedo_color = Color(1.0, 0.75, 0.4, 0.9)
	# Flames: three crossed tongues of fire.
	var fm := MeshData.new()
	for k in 3:
		var a := k * PI / 3.0
		var side := Vector3(cos(a), 0, sin(a)) * 0.35
		var n := Vector3(-sin(a), 0, cos(a))
		var base_col := Color(1.0, 0.35, 0.05)
		var top := Vector3(0, 1.1, 0)
		fm.tri(-side, side, top, base_col, n)
		fm.tri(-side * 0.6 + Vector3(0, 0.05, 0), side * 0.6 + Vector3(0, 0.05, 0), Vector3(0, 0.7, 0), Color(1.0, 0.8, 0.3), n)
	flame_mesh = fm.to_mesh(flash_material)
	# Muzzle flash: a small star of quads facing forward (-Z).
	var mf := MeshData.new()
	for k in 4:
		var a := k * PI / 4.0
		var d := Vector3(cos(a), sin(a), 0) * 0.07
		mf.tri(-d, d, Vector3(0, 0, -0.16), Color(1.0, 0.8, 0.4), Vector3(-d.y, d.x, 0))
	for k in 6:
		var a0 := k * TAU / 6.0
		var a1 := (k + 1) * TAU / 6.0
		mf.tri(Vector3.ZERO, Vector3(cos(a0), sin(a0), 0) * 0.06, Vector3(cos(a1), sin(a1), 0) * 0.06, Color(1.0, 0.9, 0.6), Vector3.BACK)
	muzzle_flash_mesh = mf.to_mesh(flash_material)
