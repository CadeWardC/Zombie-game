class_name WorldStreamer
extends Node3D
## Streams chunks in and out around the player. Chunk data is generated on
## worker threads; the main thread only turns finished data into nodes, within
## a small per-frame time budget so streaming never causes a hitch.

signal spawn_area_ready
## A chunk was added (VehicleManager hides parked cars that were moved).
signal chunk_added(chunk: Chunk)

const NEAR_RADIUS := 1 # Chunks within this ring get full detail + collision.
const FRAME_BUDGET_USEC := 3000
const LOADING_BUDGET_USEC := 50000

var gen: WorldGen
var player: Node3D
var view_radius := 5
var shadows := false
## Host: other players' positions. The chunks right around them are loaded
## with collision too, so zombies chasing them have walls and floors.
var extra_centers: Array = []
var vehicles: VehicleManager

var _chunks := {} # Vector2i -> Chunk
var _jobs := {} # Vector2i -> Job
var _done: Array[Dictionary] = []
var _wanted := {} # Vector2i -> lod
var _order: Array[Vector2i] = [] # Wanted keys, nearest first.
var _max_jobs := 2
var _center := Vector2i(1 << 30, 1 << 30)
var _extra_keys: Array = []
var _spawn_ready := false


class Job:
	extends RefCounted
	var gen: WorldGen
	var key: Vector2i
	var lod: int
	var task_id := -1
	var result: Dictionary

	func run() -> void:
		result = ChunkBuilder.build(gen, key.x, key.y, lod)


func _ready() -> void:
	_max_jobs = clampi(OS.get_processor_count() - 1, 1, 4)


func _exit_tree() -> void:
	for job: Job in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_jobs.clear()


static func chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / WorldGen.CHUNK_SIZE), floori(pos.z / WorldGen.CHUNK_SIZE))


func is_ready_at(pos: Vector3) -> bool:
	var c: Chunk = _chunks.get(chunk_of(pos))
	return c != null and c.lod == 0


## Loot containers in loaded near chunks within `radius` of `pos`.
func containers_near(pos: Vector3, radius: float) -> Array:
	var out := []
	var center := chunk_of(pos)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c: Chunk = _chunks.get(center + Vector2i(dx, dz))
			if c == null or c.lod != 0:
				continue
			for ct in c.containers:
				# A car's trunk goes with the car once it's been moved.
				if ct.pos.distance_to(pos) < radius and not GameState.ws.vehicles.has(ct.get("veh", "")):
					out.append(ct)
	if vehicles:
		out.append_array(vehicles.trunks_near(pos, radius))
	return out


## Doors and windows (ways into buildings) in loaded near chunks within
## `radius` of `pos`, for zombies finding a way in.
func entries_near(pos: Vector3, radius: float) -> Array:
	var out := []
	var center := chunk_of(pos)
	var r2 := radius * radius
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c: Chunk = _chunks.get(center + Vector2i(dx, dz))
			if c == null or c.lod != 0:
				continue
			for d in c.doors:
				if d.global_position.distance_squared_to(pos) < r2:
					out.append(d)
			for w in c.windows:
				if w.global_position.distance_squared_to(pos) < r2:
					out.append(w)
	return out


## Interior zombie spawn points in loaded near chunks within `radius`.
func spawns_near(pos: Vector3, radius: float) -> Array:
	var out := []
	var center := chunk_of(pos)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c: Chunk = _chunks.get(center + Vector2i(dx, dz))
			if c == null or c.lod != 0:
				continue
			for sp in c.spawns:
				if (sp.pos as Vector3).distance_to(pos) < radius:
					out.append(sp)
	return out


## The standing tree nearest `pos` (within `radius`), or {}.
func tree_near(pos: Vector3, radius: float) -> Dictionary:
	var best := {}
	var bd := radius
	var c: Chunk = _chunks.get(chunk_of(pos))
	if c == null:
		return best
	for tr in c.trees:
		if GameState.ws.chopped.has(tr.id):
			continue
		var d := Vector2(tr.pos.x - pos.x, tr.pos.z - pos.z).length()
		if d < bd:
			bd = d
			best = tr
	return best


## A tree was felled (here or by another player): hide it everywhere.
func fell_tree(id: String) -> void:
	GameState.ws.chopped[id] = 1
	for c: Chunk in _chunks.values():
		for tr in c.trees:
			if tr.id == id:
				c.hide_tree(tr)


## The bush nearest `pos` within `radius` (Vector3.INF if none).
func bush_near(pos: Vector3, radius: float) -> Vector3:
	var best := Vector3.INF
	var bd := radius
	var c: Chunk = _chunks.get(chunk_of(pos))
	if c == null:
		return best
	for p in c.cover:
		var d := p.distance_to(pos)
		if d < bd:
			bd = d
			best = p
	return best


## Distance to the nearest bush (cover) around `pos`, up to `radius`.
func cover_distance(pos: Vector3, radius: float) -> float:
	var best := INF
	var c: Chunk = _chunks.get(chunk_of(pos))
	if c == null:
		return best
	for p in c.cover:
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d < best:
			best = d
	return best if best < radius else INF


func chunks() -> Array:
	return _chunks.values()


## Emits spawn_area_ready again once the chunk under the player is ready.
func wait_for_spawn_area() -> void:
	_spawn_ready = false


## Forces a full refresh, e.g. after the view distance changes.
func refresh() -> void:
	_center = Vector2i(1 << 30, 1 << 30)


## Rebuilds every chunk (used when settings like shadows change).
func rebuild_all() -> void:
	for c: Chunk in _chunks.values():
		c.queue_free()
	_chunks.clear()
	refresh()


func _process(_delta: float) -> void:
	if player == null:
		return
	var center := chunk_of(player.global_position)
	var extra: Array = extra_centers.map(func(p: Vector3) -> Vector2i: return chunk_of(p))
	if center != _center or extra != _extra_keys:
		_center = center
		_extra_keys = extra
		_update_wanted(center)
	_poll_jobs()
	_start_jobs()
	_finalize()
	if not _spawn_ready and is_ready_at(player.global_position):
		_spawn_ready = true
		spawn_area_ready.emit()


func _update_wanted(center: Vector2i) -> void:
	_wanted.clear()
	_order.clear()
	var r := view_radius
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r * r + r:
				continue
			var key := center + Vector2i(dx, dz)
			if key.x < -1 or key.y < -1 or key.x > gen.chunks or key.y > gen.chunks:
				continue
			_wanted[key] = 0 if maxi(absi(dx), absi(dz)) <= NEAR_RADIUS else 1
			_order.append(key)
	for ec: Vector2i in _extra_keys:
		for dz in range(-NEAR_RADIUS, NEAR_RADIUS + 1):
			for dx in range(-NEAR_RADIUS, NEAR_RADIUS + 1):
				var key := ec + Vector2i(dx, dz)
				if key.x < -1 or key.y < -1 or key.x > gen.chunks or key.y > gen.chunks:
					continue
				if not _wanted.has(key):
					_order.append(key)
				_wanted[key] = 0
	_order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())
	for key: Vector2i in _chunks.keys():
		if not _wanted.has(key):
			_chunks[key].queue_free()
			_chunks.erase(key)


func _start_jobs() -> void:
	if _jobs.size() >= _max_jobs:
		return
	for key in _order:
		if _jobs.has(key):
			continue
		var lod: int = _wanted[key]
		var existing: Chunk = _chunks.get(key)
		if existing != null and existing.lod == lod:
			continue
		var job := Job.new()
		job.gen = gen
		job.key = key
		job.lod = lod
		job.task_id = WorkerThreadPool.add_task(job.run, false, "chunk")
		_jobs[key] = job
		if _jobs.size() >= _max_jobs:
			return


func _poll_jobs() -> void:
	for key: Vector2i in _jobs.keys():
		var job: Job = _jobs[key]
		if not WorkerThreadPool.is_task_completed(job.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_jobs.erase(key)
		if _wanted.get(key, -1) == job.lod:
			_done.append(job.result)


func _finalize() -> void:
	var budget := FRAME_BUDGET_USEC if _spawn_ready else LOADING_BUDGET_USEC
	var start := Time.get_ticks_usec()
	# Nearest chunks first, so the area around the player fills in first.
	_done.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.lod < b.lod)
	# Finish deferred work of recently built chunks first (nearest first).
	for key in _order:
		var c: Chunk = _chunks.get(key)
		if c != null and c.has_pending():
			c.run_pending(start + budget)
			if Time.get_ticks_usec() - start >= budget:
				return
	while not _done.is_empty() and Time.get_ticks_usec() - start < budget:
		var data: Dictionary = _done.pop_front()
		var key: Vector2i = data.key
		if _wanted.get(key, -1) != data.lod:
			continue
		var chunk := Chunk.new()
		chunk.setup(data, shadows)
		add_child(chunk)
		var old: Chunk = _chunks.get(key)
		if old != null:
			old.queue_free()
		_chunks[key] = chunk
		chunk_added.emit(chunk)
