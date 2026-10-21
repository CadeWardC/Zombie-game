class_name Settlements
extends RefCounted
## Chooses where cities, towns, villages and special sites go.

enum Kind { CITY, TOWN, VILLAGE }

const COUNTS := { # map size -> [cities, towns, villages]
	8192: [2, 7, 14],
	16384: [4, 18, 40],
	32768: [9, 50, 120],
}
const SITE_COUNTS := { # map size -> [airports, research centers]
	8192: [1, 1],
	16384: [2, 2],
	32768: [3, 4],
}

## {id, kind, center: Vector2, radius, axis (radians), base (height), name}
var list: Array[Dictionary] = []
## {id, type, center: Vector2, rot, half: Vector2 (pad half size), base}
var sites: Array[Dictionary] = []

var _water_dist := PackedFloat32Array() # Metres to the nearest river/lake.
var _ocean_dist := PackedFloat32Array() # Metres to the ocean.
var _terrain: Terrain


func generate(terrain: Terrain, hydro: Hydrology, seed_value: int) -> void:
	_terrain = terrain
	_build_distance_fields(terrain, hydro)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 202
	var key := int(terrain.size)
	var counts: Array = COUNTS.get(key, COUNTS[8192])
	_place(Kind.CITY, counts[0], rng, 520.0, 700.0)
	_place(Kind.TOWN, counts[1], rng, 220.0, 320.0)
	_place(Kind.VILLAGE, counts[2], rng, 90.0, 130.0)
	var sc: Array = SITE_COUNTS.get(key, SITE_COUNTS[8192])
	for k in sc[0]:
		_place_airport(rng)
	for k in sc[1]:
		_place_research(rng)
	var names := TownNames.new(seed_value)
	for s in list:
		s.name = names.next(s.kind)


func _build_distance_fields(terrain: Terrain, hydro: Hydrology) -> void:
	var n := terrain.n + 1
	_water_dist.resize(n * n)
	_ocean_dist.resize(n * n)
	for k in n * n:
		_water_dist[k] = 1e9
		_ocean_dist[k] = 0.0 if terrain.heights[k] < 0.0 else 1e9
	for r in hydro.rivers:
		for p: Vector2 in r.pts:
			var i := clampi(roundi(p.x / Terrain.CELL), 0, n - 1)
			var j := clampi(roundi(p.y / Terrain.CELL), 0, n - 1)
			_water_dist[j * n + i] = 0.0
	for k in n * n:
		if hydro.lake_level[k] > -INF:
			_water_dist[k] = 0.0
	_chamfer(_water_dist, n)
	_chamfer(_ocean_dist, n)


## Two-pass distance transform (approximate Euclidean) in metres.
static func _chamfer(d: PackedFloat32Array, n: int) -> void:
	var c := Terrain.CELL
	var cd := c * 1.4142
	for j in n:
		for i in n:
			var k := j * n + i
			var v := d[k]
			if i > 0: v = minf(v, d[k - 1] + c)
			if j > 0:
				v = minf(v, d[k - n] + c)
				if i > 0: v = minf(v, d[k - n - 1] + cd)
				if i < n - 1: v = minf(v, d[k - n + 1] + cd)
			d[k] = v
	for j in range(n - 1, -1, -1):
		for i in range(n - 1, -1, -1):
			var k := j * n + i
			var v := d[k]
			if i < n - 1: v = minf(v, d[k + 1] + c)
			if j < n - 1:
				v = minf(v, d[k + n] + c)
				if i < n - 1: v = minf(v, d[k + n + 1] + cd)
				if i > 0: v = minf(v, d[k + n - 1] + cd)
			d[k] = v


func _field(f: PackedFloat32Array, p: Vector2) -> float:
	var n := _terrain.n + 1
	var i := clampi(roundi(p.x / Terrain.CELL), 0, n - 1)
	var j := clampi(roundi(p.y / Terrain.CELL), 0, n - 1)
	return f[j * n + i]


func water_distance(p: Vector2) -> float:
	return minf(_field(_water_dist, p), _field(_ocean_dist, p))


## Height spread of the macro terrain over a disc: a flatness measure.
func _relief(c: Vector2, r: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for ring: float in [0.0, 0.5, 1.0]:
		var count := 1 if ring == 0.0 else 8
		for a in count:
			var p: Vector2 = c + Vector2.from_angle(a * TAU / count) * r * ring
			var h := _terrain.macro_height(p.x, p.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo, hi)


func _too_close(c: Vector2, r: float, gap: float) -> bool:
	for s in list:
		if c.distance_to(s.center) < r + s.radius + gap:
			return true
	for s in sites:
		if c.distance_to(s.center) < r + s.half.length() + gap * 0.5:
			return true
	return false


func _place(kind: int, count: int, rng: RandomNumberGenerator, r_min: float, r_max: float) -> void:
	var gap: float = [2200.0, 700.0, 380.0][kind]
	var max_relief: float = [40.0, 26.0, 18.0][kind]
	var placed := 0
	for attempt in count * 120:
		if placed >= count:
			break
		var r := rng.randf_range(r_min, r_max)
		var margin := Terrain.BORDER + r + 100.0
		var c := Vector2(rng.randf_range(margin, _terrain.size - margin), rng.randf_range(margin, _terrain.size - margin))
		var rel := _relief(c, r)
		if rel.x < 3.0 or rel.y > 150.0 or rel.y - rel.x > max_relief:
			continue
		if _field(_water_dist, c) < r + 60.0 or _field(_ocean_dist, c) < r * 0.7:
			continue
		if _too_close(c, r, gap):
			continue
		# Cities prefer coasts and rivers: reject far-inland spots half the time.
		if kind == Kind.CITY and water_distance(c) > r + 1500.0 and rng.randf() < 0.5:
			continue
		var t := _terrain.temperature_at(c.x, c.y)
		var m := _terrain.moisture_at(c.x, c.y)
		if kind != Kind.VILLAGE and t > 0.63 and m < 0.45 and rng.randf() < 0.6:
			continue # Fewer big settlements in the desert.
		list.append({
			"id": list.size(), "kind": kind, "center": c, "radius": r,
			"axis": rng.randf() * PI, "base": _terrain.macro_height(c.x, c.y), "name": "",
		})
		placed += 1


func _pad_ok(c: Vector2, rot: float, half: Vector2, max_relief: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var u := Vector2.from_angle(rot)
	var v := Vector2(-u.y, u.x)
	for a in range(-2, 3):
		for b in range(-2, 3):
			var p := c + u * half.x * a * 0.5 + v * half.y * b * 0.5
			var h := _terrain.macro_height(p.x, p.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			if _field(_water_dist, p) < 60.0 or _field(_ocean_dist, p) < 60.0:
				return Vector2(INF, INF)
	if lo < 3.0 or hi - lo > max_relief:
		return Vector2(INF, INF)
	return Vector2(lo, hi)


func _place_airport(rng: RandomNumberGenerator) -> void:
	var half := Vector2(650.0, 220.0)
	for attempt in 900:
		var near: Dictionary = list[rng.randi() % maxi(1, mini(list.size(), 4))] if not list.is_empty() else {}
		var c: Vector2
		if not near.is_empty() and attempt < 400:
			c = near.center + Vector2.from_angle(rng.randf() * TAU) * (near.radius + rng.randf_range(1200.0, 3000.0))
		else:
			c = Vector2(rng.randf_range(1500.0, _terrain.size - 1500.0), rng.randf_range(1500.0, _terrain.size - 1500.0))
		var rot := rng.randf() * PI
		var margin := Terrain.BORDER + half.x + 100.0
		if c.x < margin or c.y < margin or c.x > _terrain.size - margin or c.y > _terrain.size - margin:
			continue
		var rel := _pad_ok(c, rot, half, 30.0 + attempt * 0.05)
		if rel.x == INF or _too_close(c, half.x, 300.0):
			continue
		sites.append({"id": sites.size(), "type": "airport", "center": c, "rot": rot, "half": half,
				"base": (rel.x + rel.y) * 0.5 + 1.0})
		return


func _place_research(rng: RandomNumberGenerator) -> void:
	var half := Vector2(110.0, 90.0)
	for attempt in 800:
		var margin := Terrain.BORDER + 300.0
		var c := Vector2(rng.randf_range(margin, _terrain.size - margin), rng.randf_range(margin, _terrain.size - margin))
		var rot := rng.randf() * PI
		var rel := _pad_ok(c, rot, half, 45.0)
		if rel.x == INF:
			continue
		# Remote: well away from towns, preferably up in forest or hills.
		var remote := true
		for s in list:
			if c.distance_to(s.center) < s.radius + 1200.0:
				remote = false
				break
		if not remote or _too_close(c, 200.0, 800.0):
			continue
		sites.append({"id": sites.size(), "type": "research", "center": c, "rot": rot, "half": half,
				"base": (rel.x + rel.y) * 0.5 + 0.5})
		return


## Adds a small roadside site (e.g. a gas station) if the spot is free.
func add_roadside_site(type: String, c: Vector2, rot: float, half: Vector2, base: float) -> bool:
	if _too_close(c, half.length(), 120.0) or water_distance(c) < 40.0:
		return false
	sites.append({"id": sites.size(), "type": type, "center": c, "rot": rot, "half": half, "base": base})
	return true


func near(p: Vector2, margin: float) -> Array:
	var out := []
	for s in list:
		if p.distance_to(s.center) < s.radius + margin:
			out.append(s)
	return out


func sites_near(p: Vector2, margin: float) -> Array:
	var out := []
	for s in sites:
		if p.distance_to(s.center) < s.half.length() + margin:
			out.append(s)
	return out
