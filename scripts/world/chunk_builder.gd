class_name ChunkBuilder
extends RefCounted
## Builds all the data for one chunk: terrain mesh arrays, collision heights and
## prop placements. Runs on WorkerThreadPool threads, so it must never touch the
## scene tree or create physics/rendering resources. Chunk.gd does that part on
## the main thread.

const NEAR_RES := 32 # 2 m terrain quads near the player.
const FAR_RES := 8 # 8 m terrain quads in the distance.
const SKIRT := 4.0 # Hides cracks between chunks of different detail.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()


func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color, facing: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.dot(facing) < 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	n = n.normalized()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	colors.append(color)
	colors.append(color)
	colors.append(color)


static func build(gen: WorldGen, cx: int, cz: int, lod: int) -> Dictionary:
	return ChunkBuilder.new()._build(gen, cx, cz, lod)


func _build(gen: WorldGen, cx: int, cz: int, lod: int) -> Dictionary:
	var res := NEAR_RES if lod == 0 else FAR_RES
	var size := WorldGen.CHUNK_SIZE
	var step := size / res
	var ox := cx * size
	var oz := cz * size
	var towns := gen.towns_near_chunk(cx, cz)
	var n := res + 1

	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			heights[j * n + i] = gen.height_at(ox + i * step, oz + j * step, towns)

	# Terrain surface: two flat-shaded triangles per grid cell.
	for j in res:
		for i in res:
			var a := Vector3(i * step, heights[j * n + i], j * step)
			var b := Vector3((i + 1) * step, heights[j * n + i + 1], j * step)
			var c := Vector3(i * step, heights[(j + 1) * n + i], (j + 1) * step)
			var d := Vector3((i + 1) * step, heights[(j + 1) * n + i + 1], (j + 1) * step)
			_ground_tri(gen, ox, oz, a, b, c, towns)
			_ground_tri(gen, ox, oz, b, d, c, towns)

	# Skirts: short walls hanging below each edge.
	for k in res:
		_skirt(Vector3(k * step, heights[k], 0), Vector3((k + 1) * step, heights[k + 1], 0), Vector3.FORWARD)
		_skirt(Vector3(k * step, heights[res * n + k], size), Vector3((k + 1) * step, heights[res * n + k + 1], size), Vector3.BACK)
		_skirt(Vector3(0, heights[k * n], k * step), Vector3(0, heights[(k + 1) * n], (k + 1) * step), Vector3.LEFT)
		_skirt(Vector3(size, heights[k * n + res], k * step), Vector3(size, heights[(k + 1) * n + res], (k + 1) * step), Vector3.RIGHT)

	var result := {
		"key": Vector2i(cx, cz),
		"lod": lod,
		"verts": verts,
		"normals": normals,
		"colors": colors,
		"res": res,
		"step": step,
	}
	if lod == 0:
		result["heights"] = heights

	_place_props(gen, cx, cz, lod, towns, heights, res, step, result)

	var houses := []
	for house in gen.houses_in_chunk(cx, cz, towns):
		var xf := gen.house_transform(house)
		xf.origin -= Vector3(ox, 0, oz)
		var loot := []
		if lod == 0:
			for item in gen.house_loot(house):
				item.pos -= Vector3(ox, 0, oz)
				loot.append(item)
		houses.append({"xform": xf, "variant": house.variant, "loot": loot})
	result["houses"] = houses

	var cars := []
	for xf in gen.cars_in_chunk(cx, cz, towns):
		var local: Transform3D = xf
		local.origin -= Vector3(ox, 0, oz)
		cars.append(local)
	result["cars"] = cars
	return result


func _ground_tri(gen: WorldGen, ox: float, oz: float, p0: Vector3, p1: Vector3, p2: Vector3, towns: Array) -> void:
	var mid := (p0 + p1 + p2) / 3.0
	var ny := absf((p2 - p0).cross(p1 - p0).normalized().y)
	_tri(p0, p1, p2, gen.ground_color(ox + mid.x, oz + mid.z, mid.y, ny, towns), Vector3.UP)


func _skirt(a: Vector3, b: Vector3, facing: Vector3) -> void:
	var a2 := a - Vector3(0, SKIRT, 0)
	var b2 := b - Vector3(0, SKIRT, 0)
	var col := WorldGen.COLOR_DIRT
	_tri(a, b, b2, col, facing)
	_tri(a, b2, a2, col, facing)


## Trees, dead trees and rocks as MultiMesh transform buffers. Random numbers are
## always drawn in the same order so both detail levels agree on placement.
func _place_props(gen: WorldGen, cx: int, cz: int, lod: int, towns: Array, heights: PackedFloat32Array, res: int, step: float, result: Dictionary) -> void:
	var size := WorldGen.CHUNK_SIZE
	var ox := cx * size
	var oz := cz * size
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.hash3(cx, cz, gen.seed_value)

	var trees := PackedFloat32Array()
	var tree_points := PackedVector3Array()
	var tree_count := 0
	for k in 90:
		var lx := rng.randf() * size
		var lz := rng.randf() * size
		var roll := rng.randf()
		var s := 0.8 + rng.randf() * 0.6
		var yaw := rng.randf() * TAU
		if lod == 1 and k % 2 == 1:
			continue
		var f := gen.forest_value(ox + lx, oz + lz)
		var density := clampf((f - 0.05) * 2.2, 0.0, 1.0) * 0.9 + 0.03
		if roll > density or _in_town(ox + lx, oz + lz, towns, 6.0):
			continue
		var y := _sample(heights, res, step, lx, lz) - 0.3
		_append_xform(trees, Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(lx, y, lz))
		tree_points.append(Vector3(lx, y, lz))
		tree_count += 1
	result["trees"] = trees
	result["tree_count"] = tree_count
	result["tree_points"] = tree_points

	var dead := PackedFloat32Array()
	var dead_count := 0
	var rocks := PackedFloat32Array()
	var rock_count := 0
	for k in 10:
		var lx := rng.randf() * size
		var lz := rng.randf() * size
		var roll := rng.randf()
		var s := 0.5 + rng.randf() * 1.1
		var yaw := rng.randf() * TAU
		if lod == 1 or _in_town(ox + lx, oz + lz, towns, 4.0):
			continue
		var y := _sample(heights, res, step, lx, lz)
		if k < 4:
			if gen.forest_value(ox + lx, oz + lz) < -0.05 and roll < 0.6:
				_append_xform(dead, Basis(Vector3.UP, yaw), Vector3(lx, y - 0.2, lz))
				tree_points.append(Vector3(lx, y - 0.2, lz))
				dead_count += 1
		elif roll < 0.45:
			_append_xform(rocks, Basis(Vector3.UP, yaw).scaled(Vector3(s, s * 0.8, s)), Vector3(lx, y, lz))
			rock_count += 1
	result["dead_trees"] = dead
	result["dead_count"] = dead_count
	result["rocks"] = rocks
	result["rock_count"] = rock_count


func _in_town(x: float, z: float, towns: Array, margin: float) -> bool:
	for t in towns:
		if Vector2(x, z).distance_to(t.center) < t.radius + margin:
			return true
	return false


## Bilinear height lookup in the chunk's own grid (matches the rendered mesh).
static func _sample(heights: PackedFloat32Array, res: int, step: float, lx: float, lz: float) -> float:
	var n := res + 1
	var fx := clampf(lx / step, 0.0, res - 0.001)
	var fz := clampf(lz / step, 0.0, res - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h0 := lerpf(heights[j * n + i], heights[j * n + i + 1], tx)
	var h1 := lerpf(heights[(j + 1) * n + i], heights[(j + 1) * n + i + 1], tx)
	return lerpf(h0, h1, tz)


## MultiMesh buffer layout: a 3x4 row-major transform per instance.
static func _append_xform(buf: PackedFloat32Array, b: Basis, o: Vector3) -> void:
	buf.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z])
