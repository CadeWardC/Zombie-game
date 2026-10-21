class_name Terrain
extends RefCounted
## Large-scale landscape: coastline, mountains, hills, moisture, temperature
## and biomes. The macro shape lives on a coarse grid (CELL metres) computed
## once per world; fine detail is added from noise when a chunk is built.
## Everything is read-only after generate(), so chunk threads can share it.

const CELL := 64.0
const BORDER := 500.0 # Map edges that aren't ocean rise into mountains.

enum Biome { OCEAN, BEACH, PLAINS, FARMLAND, FOREST, DESERT, MOUNTAIN }

var size: float
var n: int # Grid cells per side; samples per side = n + 1.
var heights := PackedFloat32Array()
var moisture := PackedFloat32Array()
var temperature := PackedFloat32Array()
var slope := PackedFloat32Array() # Filled in by finalize() after rivers reshape the land.
var coast_dir := Vector2.RIGHT # Points from land toward the ocean.

var _seed: int
var _continent := FastNoiseLite.new()
var _mountain_mask := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _fine := FastNoiseLite.new()
var _moist := FastNoiseLite.new()
var _temp := FastNoiseLite.new()
var _temp_dir := Vector2.DOWN


func _init(p_seed: int, p_size: float) -> void:
	_seed = p_seed
	size = p_size
	n = int(size / CELL)
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	coast_dir = Vector2.from_angle(rng.randf() * TAU)
	_temp_dir = Vector2.from_angle(rng.randf() * TAU)
	# Feature sizes stay in metres regardless of map size, so a bigger map
	# means more mountains and coastline rather than stretched ones.
	_noise(_continent, p_seed, 1.0 / 5000.0, 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_noise(_mountain_mask, p_seed + 1, 1.0 / 3500.0, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_noise(_ridge, p_seed + 2, 1.0 / 1400.0, 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise(_hills, p_seed + 3, 1.0 / 600.0, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_noise(_detail, p_seed + 4, 1.0 / 90.0, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_noise(_fine, p_seed + 5, 1.0 / 22.0, 1, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_noise(_moist, p_seed + 6, 1.0 / 3000.0, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_noise(_temp, p_seed + 7, 1.0 / 4000.0, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)


func _noise(nz: FastNoiseLite, s: int, freq: float, octaves: int, type: FastNoiseLite.NoiseType) -> void:
	nz.seed = s
	nz.noise_type = type
	nz.frequency = freq
	nz.fractal_octaves = octaves
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE


func generate() -> void:
	var count := (n + 1) * (n + 1)
	heights.resize(count)
	moisture.resize(count)
	temperature.resize(count)
	for j in n + 1:
		for i in n + 1:
			var x := i * CELL
			var z := j * CELL
			var h := _macro_sample(x, z)
			var k := j * (n + 1) + i
			heights[k] = h
			var uv := Vector2(x / size - 0.5, z / size - 0.5)
			moisture[k] = clampf(_moist.get_noise_2d(x, z) * 0.7 + 0.5, 0.0, 1.0)
			temperature[k] = clampf(0.5 + uv.dot(_temp_dir) * 0.9 + _temp.get_noise_2d(x, z) * 0.25 - maxf(h, 0.0) / 260.0, 0.0, 1.0)


func _macro_sample(x: float, z: float) -> float:
	var uv := Vector2(x / size - 0.5, z / size - 0.5)
	var land := 0.42 - uv.dot(coast_dir) * 1.5 + _continent.get_noise_2d(x, z) * 0.45
	var edge := minf(minf(x, z), minf(size - x, size - z))
	if land < 0.0:
		# Ocean floor slopes away from the shore.
		return maxf(land * 140.0 - 2.0, -60.0)
	var mmask := smoothstep(0.1, 0.55, _mountain_mask.get_noise_2d(x, z) * 0.5 + 0.5 + land * 0.25 - 0.15)
	var ridge := _ridge.get_noise_2d(x, z) * 0.5 + 0.5
	# Tilt the land up away from the coast so valleys drain to the sea.
	var inland := maxf(0.0, 0.3 - uv.dot(coast_dir)) * size
	var h := 1.0 + minf(land, 0.6) * 35.0 + minf(inland * 0.0045, 70.0)
	h += ridge * ridge * 170.0 * mmask
	h += _hills.get_noise_2d(x, z) * 16.0 * (0.35 + mmask)
	# Gentle coastal plain: flatten the first stretch inland so beaches form.
	h *= smoothstep(0.0, 0.12, land)
	if edge < BORDER:
		var t := 1.0 - maxf(edge, 0.0) / BORDER
		h += t * t * 160.0
	return h


## Smooth large-scale height (Catmull-Rom over the macro grid).
func macro_height(x: float, z: float) -> float:
	var fx := clampf(x / CELL, 0.0, n - 0.0001)
	var fz := clampf(z / CELL, 0.0, n - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var rows: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for r in 4:
		var jj := clampi(j - 1 + r, 0, n)
		var base := jj * (n + 1)
		rows[r] = _cubic(heights[base + clampi(i - 1, 0, n)], heights[base + i],
				heights[base + mini(i + 1, n)], heights[base + mini(i + 2, n)], tx)
	return _cubic(rows[0], rows[1], rows[2], rows[3], tz)


static func _cubic(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)))


func _bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf(x / CELL, 0.0, n - 0.0001)
	var fz := clampf(z / CELL, 0.0, n - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * (n + 1) + i
	return lerpf(lerpf(arr[k], arr[k + 1], tx), lerpf(arr[k + n + 1], arr[k + n + 2], tx), tz)


func moisture_at(x: float, z: float) -> float:
	return _bilinear(moisture, x, z)


func temperature_at(x: float, z: float) -> float:
	return _bilinear(temperature, x, z)


func cell_height(i: int, j: int) -> float:
	return heights[clampi(j, 0, n) * (n + 1) + clampi(i, 0, n)]


## Natural height including small-scale detail, before rivers, roads and
## towns reshape it. `calm` (0..1) suppresses the detail, e.g. inside towns.
func natural_height(x: float, z: float, calm := 0.0) -> float:
	var h := macro_height(x, z)
	if h < -1.0:
		return h
	return natural_height_with(x, z, calm, h, biome_at(x, z, h))


## natural_height() for when the macro height and biome are already known.
func natural_height_with(x: float, z: float, calm: float, h: float, b: int) -> float:
	if h < -1.0:
		return h
	var rough := 1.0
	match b:
		Biome.MOUNTAIN:
			rough = 2.6
		Biome.FOREST:
			rough = 1.1
		Biome.PLAINS:
			rough = 0.7
		Biome.FARMLAND:
			rough = 0.35
		Biome.DESERT:
			rough = 1.0
		Biome.BEACH:
			rough = 0.2
	var d := _detail.get_noise_2d(x, z) * 2.6 + _fine.get_noise_2d(x, z) * 0.45
	if b == Biome.DESERT:
		d = absf(_detail.get_noise_2d(x, z)) * 3.5 # Dune-like ridges.
	return h + d * rough * (1.0 - calm) * smoothstep(-1.0, 3.0, h)


func biome_at(x: float, z: float, h: float) -> int:
	if h < 0.0:
		return Biome.OCEAN
	if h < 2.2:
		return Biome.BEACH
	if h > 175.0:
		return Biome.MOUNTAIN
	if h > 70.0:
		# High ground is only "mountain" where it's steep; plateaus stay green.
		if slope_at(x, z) > 0.22:
			return Biome.MOUNTAIN
	var m := moisture_at(x, z) + _fine.get_noise_2d(x * 0.3, z * 0.3) * 0.04
	var t := temperature_at(x, z)
	if t > 0.63 and m < 0.45:
		return Biome.DESERT
	if m > 0.56:
		return Biome.FOREST
	if m > 0.38 and h < 110.0:
		return Biome.FARMLAND
	return Biome.PLAINS


## Call after anything modifies `heights` (the river step fills basins).
func finalize() -> void:
	slope.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			slope[j * (n + 1) + i] = cell_slope(i, j)


func slope_at(x: float, z: float) -> float:
	return _bilinear(slope, x, z)


## Slope (rise over run) of the macro terrain around a grid sample.
func cell_slope(i: int, j: int) -> float:
	var dx := cell_height(i + 1, j) - cell_height(i - 1, j)
	var dz := cell_height(i, j + 1) - cell_height(i, j - 1)
	return Vector2(dx, dz).length() / (2.0 * CELL)
