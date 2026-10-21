class_name TownLayout
extends RefCounted
## Lays out an American settlement: streets, intersections and building lots.
##
## - Village: a crossroads with a few houses, a store, a church.
## - Town: a Main Street of shops through the middle and a residential grid.
## - City: a dense downtown grid, a suburban ring road with cul-de-sacs, and
##   a commercial strip where highways come in.
##
## Lots face their street. Building types are assigned per zone, with a list
## of buildings every settlement must have (police, church, gas station...).

enum Zone { DOWNTOWN, MAIN_STREET, RESIDENTIAL, SUBURB, STRIP, RURAL }

const LOT_SIZE := { # zone -> [width along street, depth]
	Zone.DOWNTOWN: [36.0, 36.0],
	Zone.MAIN_STREET: [15.0, 26.0],
	Zone.RESIDENTIAL: [22.0, 32.0],
	Zone.SUBURB: [24.0, 34.0],
	Zone.STRIP: [44.0, 46.0],
	Zone.RURAL: [34.0, 40.0],
}
const STREET_CLEAR := 4.5 + 2.2 # Street half width + sidewalk.

var settlement: Dictionary
var lots: Array[Dictionary] = []
var streets: Array[PackedVector2Array] = [] # For overlap tests.

var _terrain: Terrain
var _roads: RoadNetwork
var _st: Settlements
var _rng := RandomNumberGenerator.new()
var _lot_hash := {} # Vector2i (16 m cells) -> [lot indices]


static func build(s: Dictionary, terrain: Terrain, roads: RoadNetwork, st: Settlements, seed_value: int) -> TownLayout:
	var t := TownLayout.new()
	t.settlement = s
	t._terrain = terrain
	t._roads = roads
	t._st = st
	t._rng.seed = seed_value + 505 + s.id * 7919
	t._generate()
	return t


func _height(p: Vector2) -> float:
	return _terrain.macro_height(p.x, p.y)


func _generate() -> void:
	var s := settlement
	var c: Vector2 = s.center
	var r: float = s.radius
	var u := Vector2.from_angle(s.axis)
	var v := Vector2(-u.y, u.x)
	var entries: Array = _roads.entries.get(s.id, [])

	match s.kind:
		Settlements.Kind.VILLAGE:
			var grid := _grid(c, u, v, r * 0.5, r * 0.6, r * 0.98, 1)
			_connect_entries(entries, grid)
		Settlements.Kind.TOWN:
			var grid := _grid(c, u, v, 100.0, 78.0, r * 0.94, 0)
			_connect_entries(entries, grid)
		Settlements.Kind.CITY:
			var grid := _grid(c, u, v, 105.0, 85.0, r * 0.6, 0)
			var ring := _ring(c, r * 0.83)
			_link_grid_to_ring(grid, ring)
			for e: Vector2 in entries:
				var inner := c + (e - c).normalized() * r * 0.83
				_add_street(PackedVector2Array([e, inner]), Zone.STRIP)
			_cul_de_sacs(ring, c, r)
	_assign_buildings()


# --- Streets -----------------------------------------------------------------

## A street grid; returns its nodes as {Vector2i(a, b): Vector2}.
func _grid(c: Vector2, u: Vector2, v: Vector2, bu: float, bv: float, max_r: float, cross_only: int) -> Dictionary:
	var nodes := {}
	var na := int(max_r / bu) + 1
	var nb := int(max_r / bv) + 1
	for b in range(-nb, nb + 1):
		for a in range(-na, na + 1):
			if cross_only == 1 and a != 0 and b != 0:
				continue
			var p := c + u * a * bu + v * b * bv
			var limit := max_r * (0.88 + 0.12 * _rng.randf())
			if p.distance_to(c) <= limit:
				nodes[Vector2i(a, b)] = p
	var deg := {}
	for k: Vector2i in nodes:
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var k2: Vector2i = k + d
			if not nodes.has(k2):
				continue
			# Thin out some outer blocks for a less rigid edge.
			var outer: bool = nodes[k].distance_to(c) > max_r * 0.7
			if outer and k.y != 0 and k.x != 0 and _rng.randf() < 0.18:
				continue
			var zone := Zone.MAIN_STREET if k.y == 0 and k2.y == 0 else Zone.RESIDENTIAL
			if settlement.kind == Settlements.Kind.CITY:
				zone = Zone.DOWNTOWN if (nodes[k].distance_to(c) < settlement.radius * 0.33) else Zone.RESIDENTIAL
			var p0: Vector2 = nodes[k]
			var p1: Vector2 = nodes[k2]
			var dir := (p1 - p0).normalized()
			_add_street(PackedVector2Array([p0 + dir * STREET_CLEAR, p1 - dir * STREET_CLEAR]), zone)
			deg[k] = deg.get(k, 0) + 1
			deg[k2] = deg.get(k2, 0) + 1
	for k: Vector2i in nodes:
		if deg.get(k, 0) > 0:
			_roads.add_node(nodes[k], _height(nodes[k]), STREET_CLEAR, settlement.axis)
	return nodes


func _connect_entries(entries: Array, grid: Dictionary) -> void:
	for e: Vector2 in entries:
		var best := Vector2.ZERO
		var bd := INF
		for p: Vector2 in grid.values():
			var d := p.distance_to(e)
			if d < bd:
				bd = d
				best = p
		if bd > STREET_CLEAR * 2.0:
			var dir := (e - best).normalized()
			_add_street(PackedVector2Array([best + dir * STREET_CLEAR, e]), Zone.RURAL)


func _ring(c: Vector2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var count := int(TAU * rad / 20.0)
	var wobble := _rng.randf() * TAU
	for k in count + 1:
		var a := TAU * k / count
		var rr := rad * (1.0 + 0.06 * sin(a * 3.0 + wobble))
		pts.append(c + Vector2.from_angle(a) * rr)
	pts = Hydrology._resample(pts, RoadNetwork.STEP)
	_add_street(pts, Zone.SUBURB)
	return pts


func _link_grid_to_ring(grid: Dictionary, ring: PackedVector2Array) -> void:
	var c: Vector2 = settlement.center
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var k := Vector2i.ZERO
		while grid.has(k + dir):
			k += dir
		var from: Vector2 = grid[k]
		var out := (from - c).normalized()
		var to := _closest_on(ring, from + out * 400.0)
		_add_street(PackedVector2Array([from + out * STREET_CLEAR, to]), Zone.RESIDENTIAL)


func _cul_de_sacs(ring: PackedVector2Array, c: Vector2, r: float) -> void:
	var k := 6
	while k < ring.size() - 6:
		var p := ring[k]
		var dir := (ring[k + 1] - ring[k - 1]).normalized()
		var out := (p - c).normalized()
		var sgn := 1.0 if _rng.randf() < 0.55 else -1.0
		var length := _rng.randf_range(70.0, 110.0)
		var start := p + out * sgn * STREET_CLEAR
		var end := p + out * sgn * length
		if end.distance_to(c) < r * 0.98 and end.distance_to(c) > r * 0.64 and not _hits_street(start, end):
			var pts := Hydrology._resample(PackedVector2Array([start, end]), RoadNetwork.STEP)
			_add_street(pts, Zone.SUBURB)
			_roads.add_node(end, _height(end), 11.0, out.angle(), true)
			_bulb_lots(end, out * sgn)
		k += _rng.randi_range(9, 14)


func _closest_on(pts: PackedVector2Array, p: Vector2) -> Vector2:
	var best := pts[0]
	var bd := INF
	for q in pts:
		var d := q.distance_squared_to(p)
		if d < bd:
			bd = d
			best = q
	return best


func _hits_street(a: Vector2, b: Vector2) -> bool:
	for s in streets:
		for k in s.size() - 1:
			if Geometry2D.segment_intersects_segment(a, b, s[k], s[k + 1]) != null:
				return true
	return false


func _add_street(pts: PackedVector2Array, zone: int) -> void:
	if pts.size() < 2:
		return
	pts = Hydrology._resample(pts, RoadNetwork.STEP)
	var h := PackedFloat32Array()
	for p in pts:
		h.append(_height(p))
	_roads.add_road(RoadNetwork.Type.STREET, pts, h)
	streets.append(pts)
	_pending_streets.append([pts, zone])


# --- Lots --------------------------------------------------------------------

var _pending_streets: Array = []


func _assign_buildings() -> void:
	# Lots are placed after all streets exist, so they can avoid every street.
	for ps in _pending_streets:
		_lots_along(ps[0], ps[1])
	var required: Array
	match settlement.kind:
		Settlements.Kind.VILLAGE:
			required = ["general_store", "church", "gas_station"]
		Settlements.Kind.TOWN:
			required = ["police", "gas_station", "church", "diner", "pharmacy", "hardware", "grocery",
					"bar", "post_office", "school", "fire_station", "gun_store", "gas_station"]
		Settlements.Kind.CITY:
			required = ["hospital", "police", "fire_station", "city_hall", "mall", "supermarket",
					"school", "church", "church", "gas_station", "gas_station", "diner", "pharmacy",
					"hardware", "bar", "gun_store", "police"]
	var commercial := lots.filter(func(l): return l.zone in [Zone.MAIN_STREET, Zone.DOWNTOWN, Zone.STRIP])
	if commercial.is_empty():
		commercial = lots.duplicate()
	commercial.sort_custom(func(a, b): return a.center.distance_to(settlement.center) < b.center.distance_to(settlement.center))
	for type in required:
		for l in commercial:
			if l.type == "" and _fits(type, l):
				l.type = type
				break
	for l in lots:
		if l.type == "":
			l.type = _filler(l)


func _fits(type: String, l: Dictionary) -> bool:
	match type:
		"mall", "supermarket", "hospital", "school":
			return l.w >= 34.0
		"gas_station":
			return l.zone != Zone.DOWNTOWN
	return true


func _filler(l: Dictionary) -> String:
	var roll := _rng.randf()
	match l.zone:
		Zone.DOWNTOWN:
			return "office_tower" if roll < 0.45 else ("apartments" if roll < 0.8 else "shop")
		Zone.MAIN_STREET:
			return "shop" if roll < 0.75 else "apartments_small"
		Zone.STRIP:
			return ["fast_food", "car_dealer", "warehouse", "shop", "motel"][_rng.randi() % 5]
		Zone.SUBURB:
			return "colonial" if roll < 0.5 else ("ranch" if roll < 0.9 else "duplex")
		Zone.RURAL:
			return "farmhouse" if roll < 0.4 else ("trailer" if roll < 0.75 else "ranch")
	# Residential grid.
	if settlement.kind == Settlements.Kind.CITY:
		return "colonial" if roll < 0.35 else ("duplex" if roll < 0.55 else ("apartments_small" if roll < 0.75 else "bungalow"))
	return ["ranch", "colonial", "bungalow", "bungalow", "ranch", "trailer", "farmhouse"][_rng.randi() % 7]


func _lots_along(pts: PackedVector2Array, zone: int) -> void:
	var size: Array = LOT_SIZE[zone]
	var w: float = size[0]
	var d: float = size[1]
	var c: Vector2 = settlement.center
	var r: float = settlement.radius
	var total := 0.0
	var seg_len := PackedFloat32Array([0.0])
	for k in pts.size() - 1:
		total += pts[k].distance_to(pts[k + 1])
		seg_len.append(total)
	var s := w * 0.5 + 2.0
	var k := 0
	while s < total - w * 0.5:
		while k < pts.size() - 2 and seg_len[k + 1] < s:
			k += 1
		var t := (s - seg_len[k]) / maxf(seg_len[k + 1] - seg_len[k], 0.001)
		var p := pts[k].lerp(pts[k + 1], t)
		var dir := (pts[k + 1] - pts[k]).normalized()
		for side: float in [-1.0, 1.0]:
			var nrm: Vector2 = Vector2(-dir.y, dir.x) * side
			var lot_zone := zone
			if zone == Zone.RESIDENTIAL and p.distance_to(c) > r * 0.8 and settlement.kind != Settlements.Kind.CITY:
				lot_zone = Zone.RURAL
			var lw: float = LOT_SIZE[lot_zone][0] if lot_zone != zone else w
			var ld: float = LOT_SIZE[lot_zone][1] if lot_zone != zone else d
			var center: Vector2 = p + nrm * (STREET_CLEAR + 0.5 + ld * 0.5)
			_try_lot(center, -nrm, lw, ld, lot_zone)
		s += w + 1.0


func _bulb_lots(center: Vector2, out: Vector2) -> void:
	var size: Array = LOT_SIZE[Zone.SUBURB]
	for a: float in [-1.2, -0.6, 0.0, 0.6, 1.2]:
		var dir := out.rotated(a)
		var c: Vector2 = center + dir * (11.0 + 1.0 + size[1] * 0.5)
		_try_lot(c, -dir, size[0], size[1], Zone.SUBURB)


func _try_lot(center: Vector2, front: Vector2, w: float, d: float, zone: int) -> void:
	var c: Vector2 = settlement.center
	if center.distance_to(c) > settlement.radius - d * 0.4:
		return
	if _st.water_distance(center) < d:
		return
	var rad := 0.5 * Vector2(w, d).length()
	var corners := _corners(center, front, w, d)
	# Clear of every street (including the sidewalk).
	var probes := corners.duplicate()
	probes.append(center)
	for st in streets:
		for k in st.size() - 1:
			for q in probes:
				if Geometry2D.get_closest_point_to_segment(q, st[k], st[k + 1]).distance_to(q) < STREET_CLEAR - 0.3:
					return
	var cell := Vector2i(floori(center.x / 16.0), floori(center.y / 16.0))
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			for li in _lot_hash.get(cell + Vector2i(dx, dz), []):
				var o: Dictionary = lots[li]
				if o.center.distance_to(center) < (rad + o.rad) * 0.98:
					if not Geometry2D.intersect_polygons(corners, o.corners).is_empty():
						return
	# Too steep for a building pad.
	var hs := PackedFloat32Array()
	for q in corners:
		hs.append(_height(q))
	if hs[0] - hs[2] > 6.0 or hs[2] - hs[0] > 6.0 or hs[1] - hs[3] > 6.0 or hs[3] - hs[1] > 6.0:
		return
	var idx := lots.size()
	lots.append({
		"id": "%d_%d" % [settlement.id, idx], "center": center, "yaw": atan2(front.x, front.y),
		"w": w, "d": d, "zone": zone, "type": "", "rad": rad, "corners": corners,
		"seed": WorldGen.hash3(settlement.id, idx, 77), "settlement": settlement.id,
		"floor": maxf(maxf(hs[0], hs[1]), maxf(hs[2], hs[3])) + 0.15,
	})
	_lot_hash.get_or_add(cell, []).append(idx)


static func _corners(center: Vector2, front: Vector2, w: float, d: float) -> PackedVector2Array:
	var side := Vector2(front.y, -front.x)
	var hw := side * w * 0.5
	var hd := front * d * 0.5
	return PackedVector2Array([center - hw - hd, center + hw - hd, center + hw + hd, center - hw + hd])
