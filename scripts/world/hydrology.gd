class_name Hydrology
extends RefCounted
## Rivers and lakes from a drainage simulation on the macro terrain:
##
## 1. Priority-flood from the ocean fills every basin up to its spill point.
##    This gives each cell a "receiver" downstream, so all water reaches the
##    sea, and the filled height is a water level that only falls downstream.
## 2. Flow accumulation counts how much land drains through each cell.
##    Cells draining enough land become rivers, with tributaries joining.
## 3. Basins that had to be filled more than a little become lakes, with
##    their natural shape.

const BED_DEPTH := 2.6
const BANK := 10.0
const SAMPLE_STEP := 12.0
const RIVER_THRESHOLD := 320 # Cells of drainage area (64 m cells, ~1.3 km²).
const MIN_LAKE_CELLS := 3
const MAX_LAKE_CELLS := 160 # Bigger basins become flat valley plains instead.
const MAX_LAKE_DEPTH := 14.0

## Each river: {pts: PackedVector2Array, water: PackedFloat32Array,
## half_width: PackedFloat32Array}
var rivers: Array[Dictionary] = []
var index := SegmentIndex.new()
## Lake water level per macro cell, or -INF where there's no lake.
var lake_level := PackedFloat32Array()
var lake_cell_count := 0

var _terrain: Terrain
var _n1 := 0
var filled_terrain := PackedFloat32Array() # Terrain with big basins filled in.


func generate(terrain: Terrain, seed_value: int) -> void:
	_terrain = terrain
	_n1 = terrain.n + 1
	var total := _n1 * _n1
	var filled := terrain.heights.duplicate()
	var receiver := PackedInt32Array()
	receiver.resize(total)
	receiver.fill(-1)
	var order := _priority_flood(terrain.heights, filled, receiver)

	# Flow accumulation: visit cells from upstream to downstream.
	var acc := PackedInt32Array()
	acc.resize(total)
	acc.fill(1)
	for k in range(order.size() - 1, -1, -1):
		var c := order[k]
		var r := receiver[c]
		if r >= 0:
			acc[r] += acc[c]

	_find_lakes(terrain.heights, filled)
	terrain.heights = filled_terrain
	_trace_rivers(terrain.heights, filled, receiver, acc, seed_value)
	for r in rivers.size():
		var pts: PackedVector2Array = rivers[r].pts
		var hw: PackedFloat32Array = rivers[r].half_width
		for k in pts.size() - 1:
			index.add(pts[k], pts[k + 1], hw[k] + BANK + 4.0, r, k)


## Returns cells in the order they were reached from the sea.
func _priority_flood(h: PackedFloat32Array, filled: PackedFloat32Array, receiver: PackedInt32Array) -> PackedInt32Array:
	var total := _n1 * _n1
	var closed := PackedByteArray()
	closed.resize(total)
	var heap := MinHeap.new()
	var order := PackedInt32Array()
	for c in total:
		if h[c] < 0.0:
			closed[c] = 1
			heap.push(h[c], c)
	if heap.size() == 0:
		# No ocean: drain to the map edge instead.
		for c in total:
			var i := c % _n1
			var j := c / _n1
			if i == 0 or j == 0 or i == _n1 - 1 or j == _n1 - 1:
				closed[c] = 1
				heap.push(h[c], c)
	while heap.size() > 0:
		var c := heap.pop()
		order.append(c)
		var ci := c % _n1
		var cj := c / _n1
		for dj in range(-1, 2):
			for di in range(-1, 2):
				var i := ci + di
				var j := cj + dj
				if (di == 0 and dj == 0) or i < 0 or j < 0 or i >= _n1 or j >= _n1:
					continue
				var nb := j * _n1 + i
				if closed[nb]:
					continue
				closed[nb] = 1
				filled[nb] = maxf(h[nb], filled[c] + 0.01)
				receiver[nb] = c
				heap.push(filled[nb], nb)
	return order


func _find_lakes(h: PackedFloat32Array, filled: PackedFloat32Array) -> void:
	var total := _n1 * _n1
	lake_level.resize(total)
	lake_level.fill(-INF)
	filled_terrain = h.duplicate()
	var seen := PackedByteArray()
	seen.resize(total)
	for c in total:
		if seen[c] or h[c] < 0.0 or filled[c] - h[c] < 1.0:
			continue
		# Flood-fill one basin.
		var cells := PackedInt32Array([c])
		seen[c] = 1
		var k := 0
		var level := filled[c]
		while k < cells.size():
			var cur := cells[k]
			k += 1
			level = maxf(level, filled[cur])
			var ci := cur % _n1
			var cj := cur / _n1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var i: int = ci + d.x
				var j: int = cj + d.y
				if i < 0 or j < 0 or i >= _n1 or j >= _n1:
					continue
				var nb := j * _n1 + i
				if not seen[nb] and h[nb] >= 0.0 and filled[nb] - h[nb] >= 1.0:
					seen[nb] = 1
					cells.append(nb)
		var depth := 0.0
		for cc in cells:
			depth = maxf(depth, level - h[cc])
		if cells.size() > MAX_LAKE_CELLS or depth > MAX_LAKE_DEPTH:
			# Too big for a lake: silt it up into a flat valley floor.
			for cc in cells:
				filled_terrain[cc] = filled[cc] - 0.4
		elif cells.size() >= MIN_LAKE_CELLS:
			for cc in cells:
				lake_level[cc] = level
			lake_cell_count += cells.size()


func _trace_rivers(h: PackedFloat32Array, filled: PackedFloat32Array, receiver: PackedInt32Array, acc: PackedInt32Array, seed_value: int) -> void:
	var total := _n1 * _n1
	var is_river := PackedByteArray()
	is_river.resize(total)
	var has_big_upstream := PackedByteArray()
	has_big_upstream.resize(total)
	for c in total:
		if acc[c] >= RIVER_THRESHOLD and h[c] >= 0.0 and receiver[c] >= 0:
			has_big_upstream[receiver[c]] = 1
	# Heads: river-sized cells with no river-sized cell upstream.
	var heads: Array[int] = []
	for c in total:
		if acc[c] >= RIVER_THRESHOLD and h[c] >= 0.0 and not has_big_upstream[c]:
			heads.append(c)
	# Longest rivers first, so tributaries end where they join a main river.
	heads.sort_custom(func(a, b): return filled[a] > filled[b])
	var meander := FastNoiseLite.new()
	meander.seed = seed_value + 707
	meander.frequency = 1.0 / 350.0
	for head in heads:
		var cells := PackedInt32Array()
		var c := head
		var joined := -1
		while c >= 0:
			if is_river[c]:
				joined = c
				break
			cells.append(c)
			if h[c] < 0.0:
				break
			c = receiver[c]
		if cells.size() < 6:
			continue
		for cc in cells:
			is_river[cc] = 1
		var raw := PackedVector2Array()
		for cc in cells:
			raw.append(_cell_pos(cc))
		if joined >= 0:
			raw.append(_cell_pos(joined))
		var pts := raw
		for it in 3:
			pts = _chaikin(pts)
		pts = _resample(pts, SAMPLE_STEP)
		var wiggled := PackedVector2Array()
		for k in pts.size():
			var dir := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
			var fade := minf(1.0, minf(k, pts.size() - 1 - k) / 8.0)
			wiggled.append(pts[k] + Vector2(-dir.y, dir.x) * meander.get_noise_2d(pts[k].x, pts[k].y) * 22.0 * fade)
		pts = wiggled
		var water := PackedFloat32Array()
		var half_width := PackedFloat32Array()
		var level := INF
		for k in pts.size():
			var cell := _cell_at(pts[k])
			var ground := _terrain.macro_height(pts[k].x, pts[k].y)
			var target := minf(filled[cell] - 0.6, ground - 1.0)
			if lake_level[cell] > -INF:
				target = lake_level[cell]
			level = minf(level, target)
			level = maxf(level, 0.1) if ground > 0.5 else 0.0
			water.append(level)
			var a := acc[cell]
			half_width.append(clampf(2.5 + sqrt(float(a)) * 0.28, 3.0, 18.0))
		rivers.append({"pts": pts, "water": water, "half_width": half_width})


func _cell_pos(c: int) -> Vector2:
	return Vector2(c % _n1, c / _n1) * Terrain.CELL


func _cell_at(p: Vector2) -> int:
	var i := clampi(roundi(p.x / Terrain.CELL), 0, _n1 - 1)
	var j := clampi(roundi(p.y / Terrain.CELL), 0, _n1 - 1)
	return j * _n1 + i


static func _chaikin(p: PackedVector2Array) -> PackedVector2Array:
	if p.size() < 3:
		return p
	var out := PackedVector2Array([p[0]])
	for k in p.size() - 1:
		out.append(p[k].lerp(p[k + 1], 0.25))
		out.append(p[k].lerp(p[k + 1], 0.75))
	out.append(p[p.size() - 1])
	return out


static func _resample(p: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([p[0]])
	var carry := 0.0
	for k in p.size() - 1:
		var seg := p[k + 1] - p[k]
		var len := seg.length()
		if len < 0.0001:
			continue
		var d := step - carry
		while d <= len:
			out.append(p[k] + seg * (d / len))
			d += step
		carry = len - (d - step)
	if out[out.size() - 1].distance_to(p[p.size() - 1]) > step * 0.3:
		out.append(p[p.size() - 1])
	return out


## Lake level at a point (nearest macro cell), or -INF.
func lake_at(p: Vector2) -> float:
	if lake_cell_count == 0:
		return -INF
	return lake_level[_cell_at(p)]


## True if any lake cell is within `margin` metres of the rectangle.
func lake_near(rect: Rect2) -> bool:
	if lake_cell_count == 0:
		return false
	var r := rect.grow(Terrain.CELL)
	for j in range(maxi(0, floori(r.position.y / Terrain.CELL)), mini(_n1, ceili(r.end.y / Terrain.CELL) + 1)):
		for i in range(maxi(0, floori(r.position.x / Terrain.CELL)), mini(_n1, ceili(r.end.x / Terrain.CELL) + 1)):
			if lake_level[j * _n1 + i] > -INF:
				return true
	return false


## Nearest river within the given segments: Vector3(distance, water height,
## half width), or distance INF if none.
func river_at(p: Vector2, segs: PackedInt32Array) -> Vector3:
	var best := Vector3(INF, 0, 0)
	for s in segs:
		var c := index.closest(s, p)
		if c.x < best.x:
			var r: Dictionary = rivers[index.owner[s]]
			var k := index.index[s]
			var w: PackedFloat32Array = r.water
			var hw: PackedFloat32Array = r.half_width
			best = Vector3(c.x, lerpf(w[k], w[k + 1], c.y), lerpf(hw[k], hw[k + 1], c.y))
	return best


## Carves river channels into a terrain height. Lakes need no carving: they
## sit in natural basins.
func carve(p: Vector2, h: float, segs: PackedInt32Array) -> float:
	if segs.is_empty():
		return h
	var r := river_at(p, segs)
	if r.x < r.z + BANK:
		if r.x < r.z:
			var t := r.x / r.z
			h = minf(h, r.y - BED_DEPTH * (1.0 - t * t) - 0.3)
		else:
			var bank := smoothstep(r.z, r.z + BANK, r.x)
			h = minf(h, lerpf(r.y + 0.35, maxf(h, r.y + 0.35), bank))
	return h


## Water surface height at a point, or -INF if it's dry (ignores the ocean).
func water_level(p: Vector2, segs: PackedInt32Array) -> float:
	var level := lake_at(p)
	if not segs.is_empty():
		var r := river_at(p, segs)
		if r.x < r.z:
			level = maxf(level, r.y)
	return level
