class_name WorldGen
extends RefCounted
## Deterministic world description. Everything (terrain height, biomes, towns,
## houses, loot) is computed from the seed on demand, so a 16 km map costs no
## storage and any chunk can be generated on any thread at any time.

const CHUNK_SIZE := 64.0
const WORLD_CHUNKS := 256 # 256 * 64 m = 16.4 km per side.
const WORLD_SIZE := CHUNK_SIZE * WORLD_CHUNKS
const BORDER := 400.0 # Mountains rise near the map edge.
const REGION_SIZE := 384.0 # At most one town per region.
const TOWN_CHANCE := 0.4
const TOWN_BLEND := 40.0
const LOT := 28.0 # Town grid spacing (road to road).
const ROAD_HALF := 4.0 # Multiple of the 2 m terrain grid so road edges stay straight.

const COLOR_GRASS := Color(0.33, 0.43, 0.22)
const COLOR_FOREST := Color(0.24, 0.33, 0.17)
const COLOR_DIRT := Color(0.4, 0.35, 0.25)
const COLOR_ROCK := Color(0.44, 0.43, 0.41)
const COLOR_SNOW := Color(0.86, 0.87, 0.9)
const COLOR_ROAD := Color(0.2, 0.2, 0.21)
const COLOR_TOWN := Color(0.36, 0.39, 0.27)

const LOOT_SPOTS := [
	Vector3(-3.6, 0.08, -2.7), Vector3(3.6, 0.08, -2.7), Vector3(0.0, 0.08, -3.0),
	Vector3(-3.6, 0.08, 1.8), Vector3(3.6, 0.08, 1.8),
]

var seed_value: int
var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _town_cache := {}
var _town_mutex := Mutex.new()


func _init(p_seed: int) -> void:
	seed_value = p_seed
	_setup_noise(_continent, p_seed, 0.0006, 4)
	_setup_noise(_hills, p_seed + 1, 0.004, 3)
	_setup_noise(_detail, p_seed + 2, 0.03, 1)
	_setup_noise(_forest, p_seed + 3, 0.0025, 2)


func _setup_noise(n: FastNoiseLite, s: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves


static func hash3(a: int, b: int, c: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF


func rand01(a: int, b: int, c: int) -> float:
	return float(hash3(a, b, c ^ seed_value) % 100000) / 100000.0


# --- Terrain ---------------------------------------------------------------

## Natural terrain height, ignoring towns.
func raw_height(x: float, z: float) -> float:
	var h := _continent.get_noise_2d(x, z) * 45.0 + _hills.get_noise_2d(x, z) * 10.0 + _detail.get_noise_2d(x, z) * 0.8
	var edge := minf(minf(x, z), minf(WORLD_SIZE - x, WORLD_SIZE - z))
	if edge < BORDER:
		var t := 1.0 - maxf(edge, 0.0) / BORDER
		h += t * t * 120.0
	return h


## Height including flattened town areas. Pass towns from towns_near_chunk()
## when sampling many points in one chunk.
func height_at(x: float, z: float, towns: Array) -> float:
	var h := raw_height(x, z)
	for t in towns:
		var d := Vector2(x, z).distance_to(t.center)
		var w := 1.0 - smoothstep(t.radius, t.radius + TOWN_BLEND, d)
		if w > 0.0:
			h = lerpf(h, t.base, w)
	return h


func height(x: float, z: float) -> float:
	return height_at(x, z, towns_near_point(x, z))


func forest_value(x: float, z: float) -> float:
	return _forest.get_noise_2d(x, z)


func ground_color(x: float, z: float, h: float, normal_y: float, towns: Array) -> Color:
	var jitter := (float(hash3(int(x * 3.0), int(z * 3.0), 7) % 1000) / 1000.0 - 0.5) * 0.04
	for t in towns:
		var d := Vector2(x, z).distance_to(t.center)
		if d < t.radius:
			if is_road_local(x - t.center.x, z - t.center.y):
				return COLOR_ROAD.lightened(jitter + 0.02)
			return COLOR_TOWN.lightened(jitter)
	if normal_y < 0.78:
		return COLOR_ROCK.lightened(jitter)
	if h > 72.0 and normal_y > 0.85:
		return COLOR_SNOW
	var f := clampf(forest_value(x, z) * 2.5 + 0.5, 0.0, 1.0)
	var c := COLOR_GRASS.lerp(COLOR_FOREST, f)
	if normal_y < 0.9:
		c = c.lerp(COLOR_DIRT, 0.5)
	return c.lightened(jitter)


func is_road_local(lx: float, lz: float) -> bool:
	var mx := fposmod(lx, LOT)
	var mz := fposmod(lz, LOT)
	return mx < ROAD_HALF or mx > LOT - ROAD_HALF or mz < ROAD_HALF or mz > LOT - ROAD_HALF


# --- Towns -----------------------------------------------------------------

## Returns {} or {center: Vector2, radius, base, rx, rz} for a region.
func town_for_region(rx: int, rz: int) -> Dictionary:
	var key := Vector2i(rx, rz)
	_town_mutex.lock()
	var cached: Variant = _town_cache.get(key)
	_town_mutex.unlock()
	if cached != null:
		return cached
	var town := _compute_town(rx, rz)
	_town_mutex.lock()
	_town_cache[key] = town
	_town_mutex.unlock()
	return town


func _start_region() -> Vector2i:
	var c := WORLD_SIZE * 0.5
	return Vector2i(int(floor(c / REGION_SIZE)), int(floor(c / REGION_SIZE)))


func _compute_town(rx: int, rz: int) -> Dictionary:
	var start := _start_region()
	var is_start := Vector2i(rx, rz) == start
	if not is_start and rand01(rx, rz, 1) > TOWN_CHANCE:
		return {}
	var center := Vector2(
		(rx + 0.3 + 0.4 * rand01(rx, rz, 2)) * REGION_SIZE,
		(rz + 0.3 + 0.4 * rand01(rx, rz, 3)) * REGION_SIZE)
	var radius := 60.0 + 35.0 * rand01(rx, rz, 4)
	if is_start:
		# The starting town is a bigger city, centred in its region.
		center = Vector2((rx + 0.5) * REGION_SIZE, (rz + 0.5) * REGION_SIZE)
		radius = 135.0
	# Snap to the near-terrain grid so roads line up with triangle edges.
	center = (center / 2.0).round() * 2.0
	var edge := minf(minf(center.x, center.y), minf(WORLD_SIZE - center.x, WORLD_SIZE - center.y))
	if edge < BORDER + radius:
		return {}
	if not is_start:
		var sc := Vector2((start.x + 0.5) * REGION_SIZE, (start.y + 0.5) * REGION_SIZE)
		if center.distance_to(sc) < radius + 135.0 + TOWN_BLEND * 2.0:
			return {}
	return {"center": center, "radius": radius, "base": raw_height(center.x, center.y), "rx": rx, "rz": rz}


func _towns_around(x: float, z: float, margin: float) -> Array:
	var result := []
	var rx := int(floor(x / REGION_SIZE))
	var rz := int(floor(z / REGION_SIZE))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t := town_for_region(rx + dx, rz + dz)
			if t.is_empty():
				continue
			if Vector2(x, z).distance_to(t.center) < t.radius + TOWN_BLEND + margin:
				result.append(t)
	return result


func towns_near_chunk(cx: int, cz: int) -> Array:
	return _towns_around((cx + 0.5) * CHUNK_SIZE, (cz + 0.5) * CHUNK_SIZE, CHUNK_SIZE)


func towns_near_point(x: float, z: float) -> Array:
	return _towns_around(x, z, 0.0)


## 1 inside a town, fading to 0 across the blend ring.
func town_weight(x: float, z: float) -> float:
	var w := 0.0
	for t in towns_near_point(x, z):
		var d := Vector2(x, z).distance_to(t.center)
		w = maxf(w, 1.0 - smoothstep(t.radius, t.radius + TOWN_BLEND, d))
	return w


func spawn_point() -> Vector3:
	var s := _start_region()
	var t := town_for_region(s.x, s.y)
	return Vector3(t.center.x, t.base + 1.0, t.center.y)


# --- Buildings -------------------------------------------------------------

## Houses whose centre lies in the chunk. Positions are in world space.
func houses_in_chunk(cx: int, cz: int, towns: Array) -> Array:
	var out := []
	var x0 := cx * CHUNK_SIZE
	var z0 := cz * CHUNK_SIZE
	for t in towns:
		var c: Vector2 = t.center
		for j in range(int(floor((z0 - c.y) / LOT)) - 1, int(floor((z0 + CHUNK_SIZE - c.y) / LOT)) + 1):
			for i in range(int(floor((x0 - c.x) / LOT)) - 1, int(floor((x0 + CHUNK_SIZE - c.x) / LOT)) + 1):
				var p := c + Vector2((i + 0.5) * LOT, (j + 0.5) * LOT)
				if p.x < x0 or p.x >= x0 + CHUNK_SIZE or p.y < z0 or p.y >= z0 + CHUNK_SIZE:
					continue
				if p.distance_to(c) > t.radius - 10.0:
					continue
				var hsh := hash3(t.rx * 4096 + i, t.rz * 4096 + j, seed_value)
				if hsh % 100 >= 78:
					continue
				out.append({
					"pos": Vector3(p.x, t.base, p.y),
					"rot": (hsh >> 8) % 4,
					"variant": (hsh >> 4) % 3,
					"id": "%d_%d_%d_%d" % [t.rx, t.rz, i, j],
					"seed": hsh,
				})
	return out


## Abandoned cars parked along town roads, as world-space transforms.
func cars_in_chunk(cx: int, cz: int, towns: Array) -> Array:
	var out := []
	var x0 := cx * CHUNK_SIZE
	var z0 := cz * CHUNK_SIZE
	for t in towns:
		var c: Vector2 = t.center
		for j in range(int(floor((z0 - c.y) / LOT)) - 1, int(floor((z0 + CHUNK_SIZE - c.y) / LOT)) + 1):
			for i in range(int(floor((x0 - c.x) / LOT)) - 1, int(floor((x0 + CHUNK_SIZE - c.x) / LOT)) + 1):
				var hsh := hash3(t.rx * 4096 + i, t.rz * 4096 + j, seed_value + 99)
				if hsh % 100 >= 30:
					continue
				var side := 2.0 if (hsh >> 3) % 2 == 0 else -2.0
				var along := (float((hsh >> 5) % 1000) / 1000.0 - 0.5) * 16.0
				var p := c + Vector2(i * LOT + side, (j + 0.5) * LOT + along)
				if p.x < x0 or p.x >= x0 + CHUNK_SIZE or p.y < z0 or p.y >= z0 + CHUNK_SIZE:
					continue
				if p.distance_to(c) > t.radius - 4.0:
					continue
				var yaw := (PI if side < 0.0 else 0.0) + (float((hsh >> 9) % 100) / 100.0 - 0.5) * 0.5
				out.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, t.base, p.y)))
	return out


func house_transform(house: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, house.rot * PI * 0.5), house.pos)


## Loot inside a house: [{id, type, pos (world)}].
func house_loot(house: Dictionary) -> Array:
	var out := []
	var hsh: int = house.seed
	var xf := house_transform(house)
	var count := 1 + (hsh >> 12) % 3
	var first := (hsh >> 3) % LOOT_SPOTS.size()
	for k in count:
		var roll := hash3(hsh, k, 77) % 100
		var type := "food" if roll < 40 else ("water" if roll < 80 else "bandage")
		out.append({
			"id": "%s_%d" % [house.id, k],
			"type": type,
			"pos": xf * LOOT_SPOTS[(first + k * 2) % LOOT_SPOTS.size()],
		})
	return out


func is_inside_building(x: float, z: float) -> bool:
	var cx := int(floor(x / CHUNK_SIZE))
	var cz := int(floor(z / CHUNK_SIZE))
	var towns := towns_near_chunk(cx, cz)
	if towns.is_empty():
		return false
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for house in houses_in_chunk(cx + dx, cz + dz, towns):
				var local := house_transform(house).affine_inverse() * Vector3(x, house.pos.y, z)
				if absf(local.x) < Assets.HOUSE_W * 0.5 + 1.0 and absf(local.z) < Assets.HOUSE_D * 0.5 + 1.0:
					return true
	return false
