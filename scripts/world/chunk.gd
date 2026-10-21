class_name Chunk
extends Node3D
## Scene nodes for one chunk, created on the main thread from ChunkBuilder data.
## Near chunks (lod 0) get collision and loot; far chunks are visuals only.

var key: Vector2i
var lod := 0


func setup(data: Dictionary, shadows: bool) -> void:
	key = data.key
	lod = data.lod
	name = "Chunk_%d_%d_%d" % [key.x, key.y, lod]
	position = Vector3(key.x * WorldGen.CHUNK_SIZE, 0, key.y * WorldGen.CHUNK_SIZE)
	var near := lod == 0

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.verts
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_COLOR] = data.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var terrain := MeshInstance3D.new()
	terrain.mesh = mesh
	terrain.material_override = Assets.terrain_material
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(terrain)

	var body: StaticBody3D = null
	if near:
		body = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		_add_heightmap(body, data)
		for p in data.tree_points:
			_add_shape(body, Assets.tree_shape, Transform3D(Basis.IDENTITY, p + Vector3(0, 2.0, 0)))

	var cast := shadows and near
	_add_multimesh(Assets.tree_mesh if near else Assets.tree_far_mesh, data.trees, data.tree_count, cast)
	_add_multimesh(Assets.dead_tree_mesh, data.dead_trees, data.dead_count, cast)
	_add_multimesh(Assets.rock_mesh, data.rocks, data.rock_count, cast)

	# Houses and cars are batched per mesh into MultiMeshes: one draw call
	# per house style per chunk instead of one per building.
	var house_xforms := {}
	for house in data.houses:
		var xf: Transform3D = house.xform
		house_xforms.get_or_add(house.variant, []).append(xf)
		if body:
			for pair in Assets.house_shapes:
				_add_shape(body, pair[1], xf * pair[0])
		for item in house.loot:
			if GameState.looted.has(item.id):
				continue
			var pickup := Pickup.new()
			pickup.setup(item.type, item.id)
			pickup.position = item.pos
			add_child(pickup)
	for variant in house_xforms:
		_add_multimesh_xforms(Assets.house_meshes[variant], house_xforms[variant], cast)

	if not data.cars.is_empty():
		var cars := _add_multimesh_xforms(Assets.car_mesh, data.cars, false)
		cars.visibility_range_end = 220.0
		if body:
			for xf: Transform3D in data.cars:
				_add_shape(body, Assets.car_shape, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)))


## The heightmap shape is scaled uniformly by the grid step (Jolt handles that
## well), so heights are divided by the same factor.
func _add_heightmap(body: StaticBody3D, data: Dictionary) -> void:
	var step: float = data.step
	var n: int = data.res + 1
	var src: PackedFloat32Array = data.heights
	var scaled := PackedFloat32Array()
	scaled.resize(src.size())
	for i in src.size():
		scaled[i] = src[i] / step
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = scaled
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(step, step, step)
	cs.position = Vector3(WorldGen.CHUNK_SIZE * 0.5, 0, WorldGen.CHUNK_SIZE * 0.5)
	body.add_child(cs)


func _add_shape(body: StaticBody3D, shape: Shape3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


func _add_multimesh(mesh: Mesh, buffer: PackedFloat32Array, count: int, cast: bool) -> void:
	if count == 0:
		return
	var mmi := _new_multimesh(mesh, count, cast)
	mmi.multimesh.buffer = buffer


func _add_multimesh_xforms(mesh: Mesh, xforms: Array, cast: bool) -> MultiMeshInstance3D:
	var mmi := _new_multimesh(mesh, xforms.size(), cast)
	for i in xforms.size():
		mmi.multimesh.set_instance_transform(i, xforms[i])
	return mmi


func _new_multimesh(mesh: Mesh, count: int, cast: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi
