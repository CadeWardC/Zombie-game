class_name Chunk
extends Node3D
## Scene nodes for one chunk, created on the main thread from ChunkBuilder
## data. Near chunks (lod 0) get collision, doors, loot containers and signs;
## far chunks are visuals only.

var key: Vector2i
var lod := 0
## Searchable containers: {pos: Vector3 (world), type, id}
var containers: Array = []
## Bushes to hide in (world positions).
var cover := PackedVector3Array()
## Interior zombie spawn points: {pos: Vector3 (world), id, kind}
var spawns: Array = []
## Parked vehicles drawn as props here: {id, t, m, xf (world), mm, i, box,
## trunk}. See VehicleManager.
var vehicle_spots: Array = []
## Trees: {id, pos (world), mm, i, shape (near chunks)}. See Forest.
var trees: Array = []
var doors: Array[DoorBody] = []
var windows: Array[WindowBody] = []
## Work deferred to later frames so a big town chunk never causes a hitch.
var _pending: Array[Callable] = []

var _door_mm: MultiMesh
var _mms := {} # Prop name -> MultiMesh (to hide parked vehicles that were taken).
var _car_shapes: Array[CollisionShape3D] = []
var _window_mm: MultiMesh


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
	_pending.append(_mesh.bind(data.building, Assets.building_material, cast))
	_pending.append(_mesh.bind(data.glass, Assets.glass_material, false))

	for prop_name in data.props:
		var mesh: Mesh = _prop_mesh(prop_name)
		if mesh:
			var mmi := _multimesh(mesh, data.props[prop_name], data.prop_counts[prop_name], cast and not prop_name.begins_with("car"))
			_mms[prop_name] = mmi.multimesh
			if prop_name.begins_with("car") or prop_name in ["hydrant", "mailbox", "fuel_pump"]:
				mmi.visibility_range_end = 260.0

	for tr in data.get("trees", []):
		var td: Dictionary = tr.duplicate()
		td.pos = position + (tr.pos as Vector3)
		trees.append(td)
		if GameState.ws.chopped.has(td.id):
			hide_tree(td)
	for sp in data.vehicle_spots:
		var vs: Dictionary = sp.duplicate()
		vs.xf = Transform3D(Basis.IDENTITY, position) * (sp.xf as Transform3D)
		vehicle_spots.append(vs)
	if not near:
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	_add_heightmap(body, data)
	for tr in trees:
		if not GameState.ws.chopped.has(tr.id):
			tr.shape = _add_shape(body, Assets.tree_shape, Transform3D(Basis.IDENTITY, (tr.pos as Vector3) - position + Vector3(0, 2.0, 0)))
	for xf in data.car_boxes:
		_car_shapes.append(_add_shape(body, Assets.car_shape, xf))
	# Walls, floors, furniture: one concave shape per building, baked on the
	# worker thread and created over the next few frames.
	for faces: PackedVector3Array in data.collision_batches:
		_pending.append(_add_concave.bind(body, faces))
	_pending.append(_build_doors.bind(data.doors))
	_pending.append(_build_windows.bind(data.windows))
	for sp in data.spawns:
		var ss: Dictionary = sp.duplicate()
		ss.pos = position + (sp.pos as Vector3)
		spawns.append(ss)
	for p: Vector3 in data.cover_points:
		cover.append(position + p)
	for c in data.containers:
		var cc: Dictionary = c.duplicate()
		cc.pos = position + (c.pos as Vector3)
		containers.append(cc)
	for s in data.signs:
		_pending.append(_sign.bind(s))


func has_pending() -> bool:
	return not _pending.is_empty()


## Runs deferred setup work until `deadline_usec` (Time.get_ticks_usec()).
func run_pending(deadline_usec: int) -> void:
	while not _pending.is_empty() and Time.get_ticks_usec() < deadline_usec:
		_pending.pop_front().call()


func _add_concave(body: StaticBody3D, faces: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	_add_shape(body, shape, Transform3D.IDENTITY)


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


func _add_shape(body: StaticBody3D, shape: Shape3D, xf: Transform3D) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)
	return cs


## A tree was cut down: stop drawing it, and walk through where it stood.
func hide_tree(tr: Dictionary) -> void:
	var mm: MultiMesh = _mms.get(tr.mm)
	if mm and int(tr.i) < mm.instance_count:
		mm.set_instance_transform(int(tr.i), Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -500, 0)))
	var cs: CollisionShape3D = tr.get("shape")
	if cs and is_instance_valid(cs):
		cs.disabled = true


## A parked vehicle was taken (or moved before): stop drawing it here.
func hide_spot(sp: Dictionary) -> void:
	var mm: MultiMesh = _mms.get(sp.mm)
	if mm and int(sp.i) < mm.instance_count:
		mm.set_instance_transform(int(sp.i), Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -500, 0)))
	if int(sp.box) >= 0 and int(sp.box) < _car_shapes.size():
		_car_shapes[int(sp.box)].disabled = true
	sp.hidden = true


## All doors in the chunk are drawn by one MultiMesh (one draw call); each
## has its own small physics body for collision and interaction.
func _build_doors(list: Array) -> void:
	if list.is_empty():
		return
	_door_mm = MultiMesh.new()
	_door_mm.transform_format = MultiMesh.TRANSFORM_3D
	_door_mm.use_colors = true
	_door_mm.mesh = Assets.door_mesh
	_door_mm.instance_count = list.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _door_mm
	add_child(mmi)
	for i in list.size():
		var d: Dictionary = list[i]
		var door := DoorBody.new()
		add_child(door)
		door.setup(d, _door_mm, i)
		doors.append(door)


## Windows work like doors: one MultiMesh for the glass, a body each.
func _build_windows(list: Array) -> void:
	if list.is_empty():
		return
	_window_mm = MultiMesh.new()
	_window_mm.transform_format = MultiMesh.TRANSFORM_3D
	_window_mm.mesh = Assets.window_mesh
	_window_mm.instance_count = list.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _window_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for i in list.size():
		var w := WindowBody.new()
		add_child(w)
		w.setup(list[i], _window_mm, i)
		windows.append(w)


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
