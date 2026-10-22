class_name VehicleManager
extends Node3D
## Keeps track of every vehicle in the world.
##
## Parked cars, bikes and aircraft start as plain props drawn by their chunk
## (cheap: thousands of them). The first time someone uses one it becomes
## "active": it gets a record in GameState.ws.vehicles (saved with the world,
## shared in multiplayer), its prop is hidden wherever it's drawn, and a
## Vehicle node takes over while it's near a player. Boats moored at docks
## become active as soon as someone comes close (there's no prop for them).

const NODE_RANGE := 260.0
const BOAT_RANGE := 200.0

var gen: WorldGen
var streamer: WorldStreamer
var player: Player
var zombies: ZombieManager
var avatars: Avatars
var nodes := {} # Vehicle id -> Vehicle

var _scan_t := 0.0


func _ready() -> void:
	streamer.chunk_added.connect(_on_chunk_added)
	for c: Chunk in streamer.chunks():
		_on_chunk_added(c)


func _on_chunk_added(c: Chunk) -> void:
	for sp in c.vehicle_spots:
		if GameState.ws.vehicles.has(sp.id):
			c.hide_spot(sp)


func record(id: String) -> Dictionary:
	return GameState.ws.vehicles.get(id, {})


## A parked prop becomes a real vehicle: record, hidden prop, node.
func activate(sp: Dictionary) -> Vehicle:
	if not GameState.ws.vehicles.has(sp.id):
		var r := VehicleDB.roll(sp.id, sp.t, int(sp.m))
		var xf: Transform3D = sp.xf
		r.p = [xf.origin.x, xf.origin.y + 0.05, xf.origin.z]
		# Props face +Z like the vehicle models; keep their heading.
		r.yaw = xf.basis.get_euler().y
		r.trunk = sp.get("trunk", "")
		GameState.ws.vehicles[sp.id] = r
		Net.vehicle_record(r)
	_hide_everywhere(sp.id)
	return _spawn(GameState.ws.vehicles[sp.id])


## Multiplayer: someone else activated (or changed) a vehicle.
func apply_record(r: Dictionary) -> void:
	var known: Dictionary = GameState.ws.vehicles.get(r.id, {})
	if known.is_empty():
		GameState.ws.vehicles[r.id] = r
		_hide_everywhere(r.id)
	else:
		known.merge(r, true)
	var v: Vehicle = nodes.get(r.id)
	if v:
		v.rec = GameState.ws.vehicles[r.id]


func _hide_everywhere(id: String) -> void:
	for c: Chunk in streamer.chunks():
		for sp in c.vehicle_spots:
			if sp.id == id and not sp.get("hidden", false):
				c.hide_spot(sp)


func _spawn(r: Dictionary) -> Vehicle:
	var v: Vehicle = nodes.get(r.id)
	if v:
		return v
	v = Vehicle.new()
	v.gen = gen
	v.zombies = zombies
	v.name = "Vehicle_%s" % r.id
	add_child(v)
	v.setup(r)
	nodes[r.id] = v
	if Net.vehicle_seats.has(r.id):
		v.sync_seats(Net.vehicle_seats[r.id])
	return v


## Parked props (not yet active) and vehicle nodes within `radius`, nearest
## first: [{v: Vehicle or null, sp: spot or {}, pos, d}].
func near(pos: Vector3, radius: float) -> Array:
	var out := []
	for v: Vehicle in nodes.values():
		var d := _dist_to(v.global_transform, v.def.size, pos)
		if d < radius:
			out.append({"v": v, "sp": {}, "pos": v.global_position, "d": d})
	var key := WorldStreamer.chunk_of(pos)
	for c: Chunk in streamer.chunks():
		if c.lod != 0 or absi(c.key.x - key.x) > 1 or absi(c.key.y - key.y) > 1:
			continue
		for sp in c.vehicle_spots:
			if sp.get("hidden", false) or GameState.ws.vehicles.has(sp.id):
				continue
			var xf: Transform3D = sp.xf
			var d := _dist_to(xf, VehicleDB.get_def(sp.t).size, pos)
			if d < radius:
				out.append({"v": null, "sp": sp, "pos": xf.origin, "d": d})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return out


## Distance from `pos` to the vehicle's footprint (0 inside it).
static func _dist_to(xf: Transform3D, size: Vector3, pos: Vector3) -> float:
	var l := xf.affine_inverse() * pos
	var dx := maxf(absf(l.x) - size.x * 0.5, 0.0)
	var dz := maxf(absf(l.z) - size.z * 0.5, 0.0)
	var dy := maxf(absf(l.y - size.y * 0.5) - size.y * 0.5, 0.0)
	return Vector3(dx, dy, dz).length()


## Trunks of moved vehicles, as containers that travel with them.
func trunks_near(pos: Vector3, radius: float) -> Array:
	var out := []
	for v: Vehicle in nodes.values():
		var id: String = v.rec.get("trunk", "")
		if id == "" or v.rec.get("locked", false):
			continue
		var tp := v.global_transform * Vector3(0, 0.9, -v.def.size.z * 0.5 - 0.1)
		if tp.distance_to(pos) < radius:
			out.append({"pos": tp, "type": "car_trunk", "bld": "", "id": id, "veh": v.rec.id})
	return out


func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 0.5
	var centers: Array = [player.global_position]
	if avatars:
		for a in avatars.all():
			centers.append((a as Node3D).global_position)
	# Boats at their moorings.
	for b in gen.boat_spots:
		if GameState.ws.vehicles.has(b.id):
			continue
		var bp: Vector3 = b.p
		if bp.distance_to(player.global_position) < BOAT_RANGE:
			var r := VehicleDB.roll(b.id, b.t)
			r.p = [bp.x, bp.y, bp.z]
			r.yaw = float(b.yaw)
			GameState.ws.vehicles[b.id] = r
			Net.vehicle_record(r)
	# Nodes for active vehicles near anyone; free the far ones.
	for id in GameState.ws.vehicles:
		var r: Dictionary = GameState.ws.vehicles[id]
		var p: Array = r.p
		var rp := Vector3(p[0], p[1], p[2])
		var close := false
		for c: Vector3 in centers:
			if c.distance_to(rp) < NODE_RANGE:
				close = true
				break
		var v: Vehicle = nodes.get(id)
		if close and v == null and streamer.is_ready_at(rp):
			_spawn(r)
		elif not close and v != null and not v.occupied():
			nodes.erase(id)
			v.queue_free()


## The vehicle a player is sitting in (by peer id), if any.
func vehicle_of(peer: int) -> Vehicle:
	for v: Vehicle in nodes.values():
		if peer in v.seats.values():
			return v
	return null
