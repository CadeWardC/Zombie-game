class_name RoadNetwork
extends RefCounted
## All roads: interstates and two-lane roads between settlements (pathfound
## over the terrain), dirt roads, and town streets (added by TownLayout).
## Each road has a smoothed height profile; the terrain is flattened to it,
## except over bridges.

enum Type { HIGHWAY, ROAD, STREET, DIRT }

const HALF_WIDTH := {Type.HIGHWAY: 8.0, Type.ROAD: 4.0, Type.STREET: 4.5, Type.DIRT: 2.4}
const SIDEWALK := 2.2 # Streets only.
const SHOULDER := 7.0 # Terrain blend zone beside the road.
const STEP := 10.0
const MAX_GRADE := 0.07

## {type, pts: PackedVector2Array, h: PackedFloat32Array, bridge: PackedByteArray}
var roads: Array[Dictionary] = []
var index := SegmentIndex.new()
## Street intersections: {pos: Vector2, h, half, rot, round}
var nodes: Array[Dictionary] = []
var _node_buckets := {}
## Entry points where arterial roads reach each settlement: id -> [Vector2]
var entries := {}

var _terrain: Terrain
var _hydro: Hydrology
var _cells := {} # Grid cell -> road id, for merging roads at junctions.


static func edge_half(type: int) -> float:
	return HALF_WIDTH[type] + (SIDEWALK if type == Type.STREET else 0.0)


func generate_arterials(terrain: Terrain, hydro: Hydrology, st: Settlements, seed_value: int) -> void:
	_terrain = terrain
	_hydro = hydro
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 404
	var astar := _build_grid(terrain, hydro, st)

	var hubs: Array = st.list.filter(func(s): return s.kind != Settlements.Kind.VILLAGE)
	var edges: Array = [] # [a: Dictionary, b: Dictionary, type]
	# Interstates join every city to its nearest city in a spanning tree.
	var cities: Array = st.list.filter(func(s): return s.kind == Settlements.Kind.CITY)
	var highway_edges := _spanning_tree(cities)
	for e in highway_edges:
		e.append(Type.HIGHWAY)
	# Two-lane roads: spanning tree over cities and towns.
	if not hubs.is_empty():
		edges = _spanning_tree(hubs).filter(func(e): return not (e[0].kind == Settlements.Kind.CITY and e[1].kind == Settlements.Kind.CITY))
		# A few extra links make loops so there's more than one way around.
		for a in hubs:
			var nearest: Dictionary = {}
			var nd := INF
			for b in hubs:
				if b == a or _has_edge(edges, a, b):
					continue
				var d: float = a.center.distance_to(b.center)
				if d < nd:
					nd = d
					nearest = b
			if not nearest.is_empty() and nd < 4500.0 and rng.randf() < 0.45:
				edges.append([a, nearest])
	for e in edges:
		e.append(Type.ROAD)
	# Highways first, so smaller roads join them rather than run alongside.
	edges = highway_edges + edges
	for v in st.list.filter(func(s): return s.kind == Settlements.Kind.VILLAGE):
		var best: Dictionary = {}
		var bd := INF
		for o in st.list:
			if o == v:
				continue
			var d: float = v.center.distance_to(o.center)
			if d < bd and (o.kind != Settlements.Kind.VILLAGE or o.id < v.id):
				bd = d
				best = o
		if not best.is_empty():
			edges.append([v, best, Type.ROAD])
	for site in st.sites:
		var best: Dictionary = {}
		var bd := INF
		for o in st.list:
			if site.type == "airport" and o.kind != Settlements.Kind.CITY:
				continue
			var d: float = site.center.distance_to(o.center)
			if d < bd:
				bd = d
				best = o
		if not best.is_empty():
			edges.append([site, best, Type.HIGHWAY if site.type == "airport" else Type.ROAD])

	for e in edges:
		_connect(astar, st, e[0], e[1], e[2])
	_place_gas_stations(st, rng)


## Prim's minimum spanning tree over places; returns [[a, b], ...].
func _spanning_tree(places: Array) -> Array:
	var out := []
	if places.size() < 2:
		return out
	var in_tree := [places[0]]
	var rest := places.slice(1)
	while not rest.is_empty():
		var best := [INF, null, null]
		for a in in_tree:
			for b in rest:
				var d: float = a.center.distance_to(b.center)
				if d < best[0]:
					best = [d, a, b]
		out.append([best[1], best[2]])
		in_tree.append(best[2])
		rest.erase(best[2])
	return out


func _has_edge(edges: Array, a, b) -> bool:
	for e in edges:
		if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
			return true
	return false


func _build_grid(terrain: Terrain, hydro: Hydrology, st: Settlements) -> AStarGrid2D:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, terrain.n + 1, terrain.n + 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.update()
	var river_cells := {}
	for r in hydro.rivers:
		for p: Vector2 in r.pts:
			river_cells[Vector2i(roundi(p.x / Terrain.CELL), roundi(p.y / Terrain.CELL))] = true
	for j in terrain.n + 1:
		for i in terrain.n + 1:
			var h := terrain.cell_height(i, j)
			if h < 1.0:
				astar.set_point_solid(Vector2i(i, j))
				continue
			var slope := terrain.cell_slope(i, j)
			var w := 1.0 + slope * slope * 900.0 + maxf(0.0, h - 90.0) * 0.05
			if river_cells.has(Vector2i(i, j)):
				w += 30.0 # Bridges are expensive: cross rivers rarely.
			astar.set_point_weight_scale(Vector2i(i, j), w)
			if hydro.lake_level[j * (terrain.n + 1) + i] > -INF:
				astar.set_point_solid(Vector2i(i, j))
	return astar


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(roundi(p.x / Terrain.CELL), 0, _terrain.n), clampi(roundi(p.y / Terrain.CELL), 0, _terrain.n))


## What occupies a grid cell for road-cutting purposes: a settlement or site
## dictionary, an existing road id, or null.
func _occupant(st: Settlements, c: Vector2i) -> Variant:
	var p := Vector2(c) * Terrain.CELL
	for s in st.list:
		if p.distance_to(s.center) < s.radius - 5.0:
			return s
	for s in st.sites:
		if _in_pad(s, p, 0.0):
			return s
	if _cells.has(c):
		return _cells[c]
	return null


static func _in_pad(site: Dictionary, p: Vector2, margin: float) -> bool:
	var local: Vector2 = (p - site.center).rotated(-site.rot)
	return absf(local.x) < site.half.x + margin and absf(local.y) < site.half.y + margin


func _connect(astar: AStarGrid2D, st: Settlements, a: Dictionary, b: Dictionary, type: int) -> void:
	var ca := _cell_of(a.center)
	var cb := _cell_of(b.center)
	var sa := astar.is_point_solid(ca)
	var sb := astar.is_point_solid(cb)
	astar.set_point_solid(ca, false)
	astar.set_point_solid(cb, false)
	var path := astar.get_id_path(ca, cb)
	astar.set_point_solid(ca, sa)
	astar.set_point_solid(cb, sb)
	if path.size() < 2:
		return
	# Split the path into runs of open country. Each run starts and ends at
	# a settlement edge, a site edge, or a junction with an existing road.
	var run: Array[Vector2i] = []
	var start_owner: Variant = null
	var prev_owner: Variant = _occupant(st, path[0])
	for k in range(1, path.size()):
		var occ: Variant = _occupant(st, path[k])
		if occ == null:
			if run.is_empty():
				start_owner = prev_owner
			run.append(path[k])
		elif not run.is_empty():
			_make_run(st, run, start_owner, occ, type)
			run = []
		prev_owner = occ
	if not run.is_empty():
		_make_run(st, run, start_owner, prev_owner, type)


func _make_run(st: Settlements, run: Array[Vector2i], from: Variant, to: Variant, type: int) -> void:
	var pts := PackedVector2Array()
	for c in run:
		pts.append(Vector2(c) * Terrain.CELL)
	var start: Variant = _endpoint(st, from, pts[0], pts[mini(1, pts.size() - 1)])
	var end: Variant = _endpoint(st, to, pts[pts.size() - 1], pts[maxi(pts.size() - 2, 0)])
	if start != null:
		pts.insert(0, start)
	if end != null:
		pts.append(end)
	if pts.size() < 2 or (pts[0].distance_to(pts[pts.size() - 1]) < 40.0 and pts.size() < 4):
		return
	for it in 2:
		pts = Hydrology._chaikin(pts)
	pts = Hydrology._resample(pts, STEP)
	var id := add_road(type, pts)
	for c in run:
		_cells[c] = id


## Where a run attaches at one end: a point on a settlement's edge (and it's
## recorded as an entry), a site's edge, or the nearest point on a road.
func _endpoint(st: Settlements, owner: Variant, edge_cell_pt: Vector2, inward_pt: Vector2) -> Variant:
	if owner == null:
		return null
	if owner is int:
		return _nearest_on_road(owner, edge_cell_pt)
	var s: Dictionary = owner
	if s.has("kind"):
		var dir: Vector2 = (edge_cell_pt - s.center).normalized()
		var p: Vector2 = s.center + dir * s.radius
		entries.get_or_add(s.id, []).append(p)
		return p
	# Site: stop at the pad edge, on the side facing the road.
	var local: Vector2 = (edge_cell_pt - s.center).rotated(-s.rot)
	local.x = clampf(local.x, -s.half.x, s.half.x)
	local.y = clampf(local.y, -s.half.y, s.half.y)
	if absf(local.x) / s.half.x > absf(local.y) / s.half.y:
		local.x = signf(local.x) * s.half.x
	else:
		local.y = signf(local.y) * s.half.y
	var p2: Vector2 = s.center + local.rotated(s.rot)
	s.get_or_add("entries", []).append(p2)
	return p2


func _nearest_on_road(id: int, p: Vector2) -> Vector2:
	var pts: PackedVector2Array = roads[id].pts
	var best := pts[0]
	var bd := INF
	for k in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])
		var d := q.distance_squared_to(p)
		if d < bd:
			bd = d
			best = q
	return best


## Adds a road and computes its height profile. Returns its id.
func add_road(type: int, pts: PackedVector2Array, fixed_heights := PackedFloat32Array()) -> int:
	var count := pts.size()
	var h := PackedFloat32Array()
	h.resize(count)
	var bridge := PackedByteArray()
	bridge.resize(count)
	var wet := PackedByteArray()
	wet.resize(count)
	for k in count:
		var p := pts[k]
		if not fixed_heights.is_empty():
			h[k] = fixed_heights[k]
			continue
		h[k] = _terrain.macro_height(p.x, p.y)
		var key := Vector2i(floori(p.x / WorldGen.CHUNK_SIZE), floori(p.y / WorldGen.CHUNK_SIZE))
		var wl := _hydro.water_level(p, _hydro.index.query_chunk(key))
		if wl > -INF:
			wet[k] = 1
			h[k] = maxf(h[k], wl + 4.5)
	if fixed_heights.is_empty():
		var ends := [h[0], h[count - 1]]
		for pass_i in 2:
			var sm := h.duplicate()
			for k in range(1, count - 1):
				var acc := 0.0
				var wsum := 0.0
				for o in range(-3, 4):
					var kk := clampi(k + o, 0, count - 1)
					acc += h[kk]
					wsum += 1.0
				sm[k] = maxf(acc / wsum, h[k] - 6.0) if wet[k] == 0 else h[k]
			h = sm
		h[0] = ends[0]
		h[count - 1] = ends[1]
		for k in range(1, count):
			var g := MAX_GRADE * pts[k].distance_to(pts[k - 1])
			h[k] = clampf(h[k], h[k - 1] - g, h[k - 1] + g)
		for k in range(count - 2, -1, -1):
			var g := MAX_GRADE * pts[k].distance_to(pts[k + 1])
			h[k] = clampf(h[k], h[k + 1] - g, h[k + 1] + g)
		for k in count:
			if wet[maxi(k - 1, 0)] or wet[k] or wet[mini(k + 1, count - 1)]:
				bridge[k] = 1
	var id := roads.size()
	roads.append({"type": type, "pts": pts, "h": h, "bridge": bridge})
	var margin := edge_half(type) + SHOULDER + 1.0
	for k in count - 1:
		index.add(pts[k], pts[k + 1], margin, id, k)
	return id


func add_node(pos: Vector2, height: float, half: float, rot: float, round := false) -> void:
	var id := nodes.size()
	nodes.append({"pos": pos, "h": height, "half": half, "rot": rot, "round": round})
	var key := Vector2i(floori(pos.x / WorldGen.CHUNK_SIZE), floori(pos.y / WorldGen.CHUNK_SIZE))
	_node_buckets.get_or_add(key, []).append(id)


func nodes_in_chunk(key: Vector2i) -> Array:
	return _node_buckets.get(key, [])


func _place_gas_stations(st: Settlements, rng: RandomNumberGenerator) -> void:
	for id in roads.size():
		var r: Dictionary = roads[id]
		if r.type == Type.STREET:
			continue
		var pts: PackedVector2Array = r.pts
		if pts.size() * STEP < 1500.0:
			continue
		var k := pts.size() / 2 + rng.randi_range(-pts.size() / 6, pts.size() / 6)
		if r.bridge[k]:
			continue
		var dir := (pts[k + 1] - pts[k - 1]).normalized()
		var side := Vector2(-dir.y, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var half := Vector2(24.0, 18.0)
		var c := pts[k] + side * (edge_half(r.type) + half.y + 3.0)
		st.add_roadside_site("gas_station", c, dir.angle(), half, r.h[k])


## Flattens terrain under and beside roads. `segs` are road segments that
## touch the current chunk.
func flatten(p: Vector2, h: float, segs: PackedInt32Array) -> float:
	for s in segs:
		var road: Dictionary = roads[index.owner[s]]
		var k := index.index[s]
		var br: PackedByteArray = road.bridge
		if br[k] and br[k + 1]:
			continue
		var c := index.closest(s, p)
		var half := edge_half(road.type) + 0.5
		if c.x > half + SHOULDER:
			continue
		var rh: PackedFloat32Array = road.h
		var target := lerpf(rh[k], rh[k + 1], c.y) - 0.08
		var w := 1.0 - smoothstep(half, half + SHOULDER, c.x)
		h = lerpf(h, target, w)
	return h


## Height of the nearest road surface if p is on a road, else -INF.
func surface_at(p: Vector2, segs: PackedInt32Array) -> float:
	var best := INF
	var height := -INF
	for s in segs:
		var road: Dictionary = roads[index.owner[s]]
		var c := index.closest(s, p)
		if c.x < edge_half(road.type) and c.x < best:
			best = c.x
			var rh: PackedFloat32Array = road.h
			height = lerpf(rh[index.index[s]], rh[index.index[s] + 1], c.y)
	return height
