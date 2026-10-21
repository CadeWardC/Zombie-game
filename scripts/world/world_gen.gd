class_name WorldGen
extends RefCounted
## The whole generated world. generate() builds, in order: terrain, rivers
## and lakes, settlements and special sites, the road network, and town
## layouts. After that everything is read-only, so chunk worker threads can
## query it freely.
##
## Final terrain height = natural terrain, smoothed in towns, flattened under
## site pads, carved by rivers and lakes, and graded under roads.

const CHUNK_SIZE := 64.0
const TOWN_BLEND := 60.0
const PAD_BLEND := 50.0
const SIZES := [8192, 16384, 32768]

var seed_value: int
var world_size: float
var chunks: int
var terrain: Terrain
var hydro := Hydrology.new()
var settlements := Settlements.new()
var roads := RoadNetwork.new()
var towns: Array[TownLayout] = []
var site_layouts := {} # site id -> SiteLayout

var _lots_by_chunk := {} # Vector2i -> [lot]
var _ctx_cache := {}
var _ctx_mutex := Mutex.new()
var _surface_noise := FastNoiseLite.new()


class ChunkContext:
	extends RefCounted
	var river_segs: PackedInt32Array
	var road_segs: PackedInt32Array
	var towns: Array
	var sites: Array


func _init(p_seed: int, p_size: float = 8192.0) -> void:
	seed_value = p_seed
	world_size = p_size
	chunks = int(world_size / CHUNK_SIZE)
	terrain = Terrain.new(p_seed, p_size)
	_surface_noise.seed = p_seed + 9
	_surface_noise.frequency = 1.0 / 7.0


## Heavy: run on a thread with a loading screen. `progress` gets (0..1, text).
func generate(progress: Callable = Callable()) -> void:
	var report := func(f: float, text: String) -> void:
		if progress.is_valid():
			progress.call(f, text)
	report.call(0.0, "Shaping the land")
	terrain.generate()
	report.call(0.3, "Carving rivers")
	hydro.generate(terrain, seed_value)
	terrain.finalize()
	report.call(0.45, "Founding towns")
	settlements.generate(terrain, hydro, seed_value)
	report.call(0.55, "Building roads")
	roads.generate_arterials(terrain, hydro, settlements, seed_value)
	report.call(0.75, "Laying out streets")
	for s in settlements.list:
		var t := TownLayout.build(s, terrain, roads, settlements, seed_value)
		towns.append(t)
		for lot in t.lots:
			_bucket_lot(lot)
	for site in settlements.sites:
		var sl := SiteLayout.build(site, self)
		site_layouts[site.id] = sl
		for lot in sl.lots:
			_bucket_lot(lot)
	report.call(1.0, "Done")


func _bucket_lot(lot: Dictionary) -> void:
	var c: Vector2 = lot.center
	var key := Vector2i(floori(c.x / CHUNK_SIZE), floori(c.y / CHUNK_SIZE))
	_lots_by_chunk.get_or_add(key, []).append(lot)


static func hash3(a: int, b: int, c: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF


func rand01(a: int, b: int, c: int) -> float:
	return float(hash3(a, b, c ^ seed_value) % 100000) / 100000.0


static func chunk_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CHUNK_SIZE), floori(z / CHUNK_SIZE))


# --- Per-chunk context -------------------------------------------------------

func context(key: Vector2i) -> ChunkContext:
	_ctx_mutex.lock()
	var cached: ChunkContext = _ctx_cache.get(key)
	_ctx_mutex.unlock()
	if cached != null:
		return cached
	var ctx := ChunkContext.new()
	var center := (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK_SIZE
	var reach := CHUNK_SIZE * 0.75
	ctx.river_segs = hydro.index.query_chunk(key)
	ctx.road_segs = roads.index.query_chunk(key)
	ctx.towns = settlements.near(center, TOWN_BLEND + reach)
	ctx.sites = settlements.sites_near(center, PAD_BLEND + reach)
	_ctx_mutex.lock()
	if _ctx_cache.size() > 600:
		_ctx_cache.clear()
	_ctx_cache[key] = ctx
	_ctx_mutex.unlock()
	return ctx


func height(x: float, z: float) -> float:
	return height_ctx(x, z, context(chunk_key(x, z)))


func height_ctx(x: float, z: float, ctx: ChunkContext) -> float:
	return _height(x, z, ctx, terrain.macro_height(x, z), -1)


## Height and base ground colour of a point in one pass (shares the biome
## lookup). The colour is written to cols[idx].
func height_color(x: float, z: float, ctx: ChunkContext, cols: PackedColorArray, idx: int) -> float:
	var macro := terrain.macro_height(x, z)
	var b := terrain.biome_at(x, z, macro)
	var h := _height(x, z, ctx, macro, b)
	cols[idx] = _color(x, z, h, macro, b, ctx)
	return h


func _height(x: float, z: float, ctx: ChunkContext, macro: float, biome: int) -> float:
	var p := Vector2(x, z)
	var calm := 0.0
	for t in ctx.towns:
		var w := 1.0 - smoothstep(t.radius, t.radius + TOWN_BLEND, p.distance_to(t.center))
		calm = maxf(calm, w)
	var h := terrain.natural_height_with(x, z, calm, macro, biome if biome >= 0 else terrain.biome_at(x, z, macro))
	for s in ctx.sites:
		var local: Vector2 = (p - s.center).rotated(-s.rot)
		var out := Vector2(maxf(absf(local.x) - s.half.x, 0.0), maxf(absf(local.y) - s.half.y, 0.0)).length()
		var w := 1.0 - smoothstep(0.0, PAD_BLEND, out)
		if w > 0.0:
			h = lerpf(h, s.base, w)
	h = hydro.carve(p, h, ctx.river_segs)
	h = roads.flatten(p, h, ctx.road_segs)
	return h


## Water surface height (sea level 0 for the ocean), or -INF where dry.
func water_level(x: float, z: float) -> float:
	var ctx := context(chunk_key(x, z))
	var level := hydro.water_level(Vector2(x, z), ctx.river_segs)
	if terrain.macro_height(x, z) < 1.0:
		level = maxf(level, 0.0)
	return level


func lots_in_chunk(key: Vector2i) -> Array:
	return _lots_by_chunk.get(key, [])


# --- Gameplay queries --------------------------------------------------------

## 1 inside a settlement, fading to 0 just outside.
func town_weight(x: float, z: float) -> float:
	var w := 0.0
	for t in settlements.near(Vector2(x, z), TOWN_BLEND):
		w = maxf(w, 1.0 - smoothstep(t.radius * 0.9, t.radius + TOWN_BLEND, Vector2(x, z).distance_to(t.center)))
	return w


func is_inside_building(x: float, z: float) -> bool:
	var key := chunk_key(x, z)
	var p := Vector2(x, z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for lot in lots_in_chunk(key + Vector2i(dx, dz)):
				if Geometry2D.is_point_in_polygon(p, lot.corners):
					return true
	return false


## A street corner in a random small town (or village). `pick` chooses which.
func spawn_point(pick := 0) -> Vector3:
	var small := settlements.list.filter(func(s): return s.kind != Settlements.Kind.CITY)
	if small.is_empty():
		small = settlements.list
	if small.is_empty():
		var mid := world_size * 0.5
		return Vector3(mid, height(mid, mid) + 1.0, mid)
	var s: Dictionary = small[(hash3(seed_value, pick, 5) % small.size())]
	var best: Vector2 = s.center
	var bd := INF
	for nd in roads.nodes:
		var d: float = nd.pos.distance_to(s.center)
		if d < bd:
			bd = d
			best = nd.pos
	return Vector3(best.x, height(best.x, best.y) + 1.0, best.y)


# --- Ground colours ------------------------------------------------------------

const COLOR_GRASS := Color(0.32, 0.41, 0.21)
const COLOR_DRY_GRASS := Color(0.5, 0.48, 0.28)
const COLOR_FOREST := Color(0.22, 0.31, 0.16)
const COLOR_SAND := Color(0.76, 0.68, 0.48)
const COLOR_DESERT := Color(0.72, 0.56, 0.38)
const COLOR_ROCK := Color(0.45, 0.43, 0.41)
const COLOR_SNOW := Color(0.88, 0.89, 0.92)
const COLOR_MUD := Color(0.3, 0.26, 0.2)
const COLOR_LAWN := Color(0.3, 0.4, 0.2)
const FIELD_COLORS := [Color(0.62, 0.55, 0.3), Color(0.42, 0.5, 0.22), Color(0.36, 0.29, 0.2), Color(0.55, 0.52, 0.26)]


## Colour for a steep slope (overrides the base colour per triangle).
func rock_color(x: float, z: float) -> Color:
	return COLOR_ROCK.lightened(_surface_noise.get_noise_2d(x, z) * 0.04 + 0.02)


func _color(x: float, z: float, h: float, macro: float, b: int, ctx: ChunkContext) -> Color:
	var jitter := _surface_noise.get_noise_2d(x, z) * 0.035
	var c: Color
	if h < 0.6 and macro < 3.0:
		c = COLOR_SAND
	elif h > 190.0:
		c = COLOR_SNOW
	else:
		match b:
			Terrain.Biome.BEACH:
				c = COLOR_SAND
			Terrain.Biome.DESERT:
				c = COLOR_DESERT
			Terrain.Biome.FOREST:
				c = COLOR_FOREST
			Terrain.Biome.MOUNTAIN:
				c = COLOR_ROCK.lerp(COLOR_GRASS, 0.35)
			Terrain.Biome.FARMLAND:
				c = _field_color(x, z)
			_:
				c = COLOR_GRASS.lerp(COLOR_DRY_GRASS, clampf(terrain.temperature_at(x, z) * 1.5 - 0.6, 0.0, 1.0))
	for t in ctx.towns:
		var d: float = Vector2(x, z).distance_to(t.center)
		if d < t.radius:
			c = COLOR_LAWN
	if not ctx.river_segs.is_empty() or hydro.lake_cell_count > 0:
		var wl := hydro.water_level(Vector2(x, z), ctx.river_segs)
		if wl > -INF and h < wl + 0.3:
			c = COLOR_MUD
	return c.lightened(jitter) if jitter > 0.0 else c.darkened(-jitter)


## Farmland is a patchwork of rectangular fields in different crops.
func _field_color(x: float, z: float) -> Color:
	var region := Vector2i(floori(x / 900.0), floori(z / 900.0))
	var a := rand01(region.x, region.y, 11) * PI
	var p := Vector2(x, z).rotated(-a)
	var cell := Vector2i(floori(p.x / 140.0), floori(p.y / 95.0))
	var crop: Color = FIELD_COLORS[hash3(cell.x, cell.y, seed_value) % FIELD_COLORS.size()]
	# Grass strips between fields.
	if fposmod(p.x, 140.0) < 4.0 or fposmod(p.y, 95.0) < 4.0:
		crop = COLOR_GRASS
	return crop
