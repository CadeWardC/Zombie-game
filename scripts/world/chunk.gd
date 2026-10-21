class_name Chunk
extends Node3D
## Scene nodes for one chunk, created on the main thread from ChunkBuilder
## data. Near chunks (lod 0) get collision, doors, loot containers and signs;
## far chunks are visuals only.

var key: Vector2i
var lod := 0
## Searchable containers: {pos: Vector3 (world), type, id}
var containers: Array = []
var _doors: Array[DoorBody] = []
var _door_mm: MultiMesh


func setup(data: Dictionary, shadows: bool) -> void:
	key = data.key
	lod = data.lod
	name = "Chunk_%d_%d_%d" % [key.x, key.y, lod]
	position = Vector3(key.x * WorldGen.CHUNK_SIZE, 0, key.y * WorldGen.CHUNK_SIZE)
	var near := lod == 0
	var cast := shadows and near

	_mesh(data.terrain, Assets.terrain_material, false)
	_mesh(data.water, Assets.water_material, false)
	_mesh(data.road, Assets.road_material, false)
	_mesh(data.solid, Assets.material, cast)
	_mesh(data.building, Assets.building_material, cast)
	_mesh(data.glass, Assets.glass_material, false)

	for prop_name in data.props:
		var mesh: Mesh = _prop_mesh(prop_name)
		if mesh:
			var mmi := _multimesh(mesh, data.props[prop_name], data.prop_counts[prop_name], cast and not prop_name.begins_with("car"))
			if prop_name.begins_with("car") or prop_name in ["hydrant", "mailbox", "fuel_pump"]:
				mmi.visibility_range_end = 260.0

	if not near:
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	_add_heightmap(body, data)
	for p in data.tree_points:
		_add_shape(body, Assets.tree_shape, Transform3D(Basis.IDENTITY, p + Vector3(0, 2.0, 0)))
	for xf in data.car_boxes:
		_add_shape(body, Assets.car_shape, xf)
	for bx in data.boxes:
		var shape := BoxShape3D.new()
		shape.size = bx[1]
		_add_shape(body, shape, bx[0])
	_build_doors(data.doors)
	for c in data.containers:
		var cc: Dictionary = c.duplicate()
		cc.pos = position + (c.pos as Vector3)
		containers.append(cc)
	for s in data.signs:
		_sign(s)


func _mesh(md: MeshData, mat: Material, cast: bool) -> void:
	if md.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = md.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _prop_mesh(prop_name: String) -> Mesh:
	if prop_name.begins_with("car_"):
		return Assets.cars[int(prop_name.substr(4)) % Assets.cars.size()]
	return Assets.props.get(prop_name)


func _multimesh(mesh: Mesh, buffer: PackedFloat32Array, count: int, cast: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	mm.buffer = buffer
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


## The heightmap shape is scaled uniformly by the grid step (Jolt handles
## that well), so heights are divided by the same factor.
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


## All doors in the chunk are drawn by one MultiMesh (one draw call); each
## has its own small physics body for collision and interaction.
func _build_doors(doors: Array) -> void:
	if doors.is_empty():
		return
	_door_mm = MultiMesh.new()
	_door_mm.transform_format = MultiMesh.TRANSFORM_3D
	_door_mm.use_colors = true
	_door_mm.mesh = Assets.door_mesh
	_door_mm.instance_count = doors.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _door_mm
	add_child(mmi)
	for i in doors.size():
		var d: Dictionary = doors[i]
		var door := DoorBody.new()
		add_child(door)
		door.setup(d, _door_mm, i)
		_doors.append(door)


func _sign(s: Dictionary) -> void:
	var label := Label3D.new()
	label.text = s.text
	label.transform = s.xf
	label.pixel_size = 0.01
	label.font_size = int(96 * s.size)
	label.outline_size = 8
	label.modulate = s.color
	label.outline_modulate = Color(0, 0, 0, 0.6)
	label.double_sided = false
	label.position += label.transform.basis.z * 0.12
	add_child(label)
