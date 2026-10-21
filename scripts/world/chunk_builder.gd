class_name ChunkBuilder
extends RefCounted
## Builds all the data for one chunk on a worker thread: terrain, water,
## roads, site surfaces, buildings (merged into a few meshes), nature and
## street props. Never touches the scene tree; Chunk.gd turns the result
## into nodes on the main thread.

const NEAR_RES := 32 # 2 m terrain quads near the player.
const FAR_RES := 8 # 8 m terrain quads in the distance.
const SKIRT := 4.0

var gen: WorldGen
var key: Vector2i
var lod: int
var origin: Vector2
var ctx: WorldGen.ChunkContext
var terrain := MeshData.new()
var water := MeshData.new()
var road := MeshData.new(true)
var solid := MeshData.new() # Bridges, markings, fences, props merged in.
var building := MeshData.new()
var glass := MeshData.new()
var boxes: Array = [] # [Transform3D, Vector3] collision, chunk-local
var _box_batch_ends: Array[int] = [] # Where each building's boxes end.
var doors: Array = []
var containers: Array = []
var signs: Array = []
var props := {} # mesh name -> PackedFloat32Array (MultiMesh buffer)
var prop_counts := {}
var tree_points := PackedVector3Array()
var car_boxes: Array = []
var heights := PackedFloat32Array()
var _cols := PackedColorArray()
var res := NEAR_RES
var step := 2.0


static func build(p_gen: WorldGen, cx: int, cz: int, p_lod: int) -> Dictionary:
	var b := ChunkBuilder.new()
	b.gen = p_gen
	b.key = Vector2i(cx, cz)
	b.lod = p_lod
	b.origin = Vector2(b.key) * WorldGen.CHUNK_SIZE
	b.ctx = p_gen.context(b.key)
	b._build()
	return b._result()


func _build() -> void:
	res = NEAR_RES if lod == 0 else FAR_RES
	step = WorldGen.CHUNK_SIZE / res
	_terrain()
	_water()
	var rm := RoadMesher.build(gen, key, ctx, lod == 0)
	road = rm.road
	solid = rm.solid
	boxes.append_array(rm.boxes)
	_sites()
	_buildings()
	_nature()
	_street_props()


func _result() -> Dictionary:
	var r := {
		"key": key, "lod": lod, "res": res, "step": step,
		"terrain": terrain, "water": water, "road": road, "solid": solid,
		"building": building, "glass": glass, "boxes": boxes, "doors": doors,
		"containers": containers, "signs": signs, "props": props, "prop_counts": prop_counts,
		"tree_points": tree_points, "car_boxes": car_boxes,
		"collision_batches": _collision_batches(),
	}
	if lod == 0:
		r["heights"] = heights
	return r


## Static collision boxes baked into triangle soups, one per building (plus
## one for bridges and fences), each becoming a single concave shape.
## Adding hundreds of separate boxes to one physics body is slow, and
## batching per building lets the chunk create them over several frames.
func _collision_batches() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	if lod != 0:
		return out
	var start := 0
	for end in _box_batch_ends + [boxes.size()]:
		if end > start:
			out.append(_faces(start, end))
		start = end
	return out


func _faces(from: int, to: int) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var quads := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for bi in range(from, to):
		var bx: Array = boxes[bi]
		var xf: Transform3D = bx[0]
		var h: Vector3 = (bx[1] as Vector3) * 0.5
		var p: Array[Vector3] = []
		for k in 8:
			p.append(xf * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
		for q in quads:
			faces.append_array([p[q[0]], p[q[1]], p[q[2]], p[q[0]], p[q[2]], p[q[3]]])
	return faces


# --- Terrain -----------------------------------------------------------------

func _terrain() -> void:
	var n := res + 1
	heights.resize(n * n)
	_cols.resize(n * n)
	for j in n:
		for i in n:
			heights[j * n + i] = gen.height_color(origin.x + i * step, origin.y + j * step, ctx, _cols, j * n + i)
	for j in res:
		for i in res:
			var k := j * n + i
			var a := Vector3(i * step, heights[k], j * step)
			var b := Vector3((i + 1) * step, heights[k + 1], j * step)
			var c := Vector3(i * step, heights[k + n], (j + 1) * step)
			var d := Vector3((i + 1) * step, heights[k + n + 1], (j + 1) * step)
			_ground_tri(a, b, c, _cols[k], _cols[k + 1], _cols[k + n])
			_ground_tri(b, d, c, _cols[k + 1], _cols[k + n + 1], _cols[k + n])
	var size := WorldGen.CHUNK_SIZE
	var dirt := WorldGen.COLOR_MUD
	for k in res:
		_skirt(Vector3(k * step, heights[k], 0), Vector3((k + 1) * step, heights[k + 1], 0), Vector3.FORWARD, dirt)
		_skirt(Vector3(k * step, heights[res * n + k], size), Vector3((k + 1) * step, heights[res * n + k + 1], size), Vector3.BACK, dirt)
		_skirt(Vector3(0, heights[k * n], k * step), Vector3(0, heights[(k + 1) * n], (k + 1) * step), Vector3.LEFT, dirt)
		_skirt(Vector3(size, heights[k * n + res], k * step), Vector3(size, heights[(k + 1) * n + res], (k + 1) * step), Vector3.RIGHT, dirt)


func _ground_tri(p0: Vector3, p1: Vector3, p2: Vector3, c0: Color, c1: Color, c2: Color) -> void:
	var ny := absf((p2 - p0).cross(p1 - p0).normalized().y)
	var col := gen.rock_color(origin.x + p0.x, origin.y + p0.z) if ny < 0.72 else Color((c0.r + c1.r + c2.r) / 3.0, (c0.g + c1.g + c2.g) / 3.0, (c0.b + c1.b + c2.b) / 3.0)
	terrain.tri(p0, p1, p2, col, Vector3.UP)


func _skirt(a: Vector3, b: Vector3, facing: Vector3, col: Color) -> void:
	terrain.quad(a, b, b - Vector3(0, SKIRT, 0), a - Vector3(0, SKIRT, 0), col, facing)


func _sample(lx: float, lz: float) -> float:
	var n := res + 1
	var fx := clampf(lx / step, 0.0, res - 0.001)
	var fz := clampf(lz / step, 0.0, res - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	return lerpf(lerpf(heights[j * n + i], heights[j * n + i + 1], tx), lerpf(heights[(j + 1) * n + i], heights[(j + 1) * n + i + 1], tx), tz)


# --- Water -------------------------------------------------------------------

func _water() -> void:
	var rect := Rect2(origin, Vector2.ONE * WorldGen.CHUNK_SIZE)
	var idx := gen.hydro.index
	for s in ctx.river_segs:
		if not rect.has_point(idx.a[s]):
			continue
		var r: Dictionary = gen.hydro.rivers[idx.owner[s]]
		var k := idx.index[s]
		var pts: PackedVector2Array = r.pts
		var lv: PackedFloat32Array = r.water
		var hw: PackedFloat32Array = r.half_width
		var s0 := RoadMesher._frame(pts, k)
		var s1 := RoadMesher._frame(pts, k + 1)
		var p0 := pts[k] - origin
		var p1 := pts[k + 1] - origin
		var w0 := hw[k] + 2.0
		var w1 := hw[k + 1] + 2.0
		water.quad(_v3(p0 - s0 * w0, lv[k]), _v3(p0 + s0 * w0, lv[k]), _v3(p1 + s1 * w1, lv[k + 1]), _v3(p1 - s1 * w1, lv[k + 1]), Color.WHITE, Vector3.UP)
	if gen.hydro.lake_cell_count > 0:
		var c := Terrain.CELL
		for j in range(ceili(origin.y / c), ceili((origin.y + WorldGen.CHUNK_SIZE) / c)):
			for i in range(ceili(origin.x / c), ceili((origin.x + WorldGen.CHUNK_SIZE) / c)):
				var p := Vector2(i, j) * c
				var level := gen.hydro.lake_at(p)
				if level == -INF:
					continue
				var lp := p - origin
				var h := c * 0.5 + 1.0
				water.quad(_v3(lp + Vector2(-h, -h), level), _v3(lp + Vector2(h, -h), level), _v3(lp + Vector2(h, h), level), _v3(lp + Vector2(-h, h), level), Color.WHITE, Vector3.UP)


# --- Sites (airport, research centre, gas stations) -----------------------------

func _sites() -> void:
	var rect := Rect2(origin, Vector2.ONE * WorldGen.CHUNK_SIZE)
	var chunk_poly := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	for site in ctx.sites:
		var sl: SiteLayout = gen.site_layouts.get(site.id)
		if sl == null:
			continue
		var y: float = site.base + 0.07
		for s in sl.surfaces:
			var poly := _rect_poly(s.center, s.rot, s.half)
			for clipped in Geometry2D.intersect_polygons(poly, chunk_poly):
				var u := Textures.U_SIDEWALK.x + 0.05 if s.kind in ["apron", "concrete", "helipad"] else Textures.U_PLAIN
				var yy := y + (0.02 if s.kind in ["taxiway", "helipad"] else 0.0)
				for t in range(1, clipped.size() - 1):
					road.tri(_v3(clipped[0] - origin, yy), _v3(clipped[t] - origin, yy), _v3(clipped[t + 1] - origin, yy),
							Color.WHITE, Vector3.UP, Vector2(u, 0.1), Vector2(u + 0.01, 0.2), Vector2(u, 0.3))
			_markings(s, y + 0.06, rect)
		for p in sl.props:
			if rect.has_point(p.pos):
				var lp: Vector2 = p.pos - origin
				_add_prop(p.type, Transform3D(Basis(Vector3.UP, p.yaw), _v3(lp, site.base + 0.05)))
		if sl.fence.size() > 1:
			_fence_line(sl.fence, site.base, rect)


func _rect_poly(c: Vector2, rot: float, half: Vector2) -> PackedVector2Array:
	var u := Vector2.from_angle(rot)
	var v := Vector2(-u.y, u.x)
	return PackedVector2Array([c - u * half.x - v * half.y, c + u * half.x - v * half.y, c + u * half.x + v * half.y, c - u * half.x + v * half.y])


## White and yellow paint on runways, taxiways, parking and helipads.
func _markings(s: Dictionary, y: float, rect: Rect2) -> void:
	var u := Vector2.from_angle(s.rot)
	var v := Vector2(-u.y, u.x)
	var white := Color(0.9, 0.9, 0.86)
	var yellow := Color(0.85, 0.7, 0.15)
	var c: Vector2 = s.center
	var half: Vector2 = s.half
	match s.kind:
		"runway":
			var t := -half.x + 40.0
			while t < half.x - 40.0:
				_paint(c + u * t, u, v, Vector2(15.0, 0.5), y, white, rect)
				t += 45.0
			for e: float in [-1.0, 1.0]:
				for k in 8:
					_paint(c + u * e * (half.x - 18.0) + v * (-half.y + 3.0 + k * (half.y * 2.0 - 6.0) / 7.0), u, v, Vector2(14.0, 0.8), y, white, rect)
			for e: float in [-1.0, 1.0]:
				var t2 := -half.x
				while t2 < half.x:
					_paint(c + u * t2 + v * e * (half.y - 1.0), u, v, Vector2(20.0, 0.3), y, white, rect)
					t2 += 20.0
		"taxiway":
			var long_x := half.x > half.y
			var axis := u if long_x else v
			var side := v if long_x else u
			var len := maxf(half.x, half.y)
			var t := -len
			while t < len:
				_paint(c + axis * t, axis, side, Vector2(10.0, 0.25), y, yellow, rect)
				t += 10.0
		"parking":
			var t := -half.x + 1.5
			while t < half.x:
				for e: float in [-1.0, 1.0]:
					_paint(c + u * t + v * e * (half.y * 0.5), v, u, Vector2(half.y * 0.9, 0.12), y, white, rect)
				t += 3.0
		"helipad":
			_paint(c, v, u, Vector2(6.0, 0.6), y + 0.01, white, rect)
			_paint(c + u * 2.0, v, u, Vector2(0.6, 6.0), y + 0.01, white, rect)
			_paint(c - u * 2.0, v, u, Vector2(0.6, 6.0), y + 0.01, white, rect)


## A painted rectangle centred at c, `size.x` along `axis`.
func _paint(c: Vector2, axis: Vector2, side: Vector2, size: Vector2, y: float, col: Color, rect: Rect2) -> void:
	if not rect.has_point(c):
		return
	var a := axis * size.x * 0.5
	var b := side * size.y * 0.5
	var lc := c - origin
	solid.quad(_v3(lc - a - b, y), _v3(lc + a - b, y), _v3(lc + a + b, y), _v3(lc - a + b, y), col, Vector3.UP)


func _fence_line(pts: PackedVector2Array, base: float, rect: Rect2) -> void:
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var length := a.distance_to(b)
		var steps := int(length / 3.0)
		for s in steps:
			var p0 := a.lerp(b, float(s) / steps)
			var p1 := a.lerp(b, float(s + 1) / steps)
			var mid := (p0 + p1) * 0.5
			if not rect.has_point(mid):
				continue
			var lp := mid - origin
			var y := _sample(lp.x, lp.y)
			var yaw := atan2(p1.x - p0.x, p1.y - p0.y)
			var basis := Basis(Vector3.UP, yaw)
			solid.box(Transform3D(basis, _v3(p0 - origin, y + 1.2)), Vector3(0.08, 2.4, 0.08), Color(0.45, 0.46, 0.47))
			solid.box(Transform3D(basis, _v3(lp, y + 1.25)), Vector3(0.02, 2.1, p0.distance_to(p1)), Color(0.32, 0.34, 0.35))
			solid.box(Transform3D(basis, _v3(lp, y + 2.35)), Vector3(0.05, 0.05, p0.distance_to(p1)), Color(0.45, 0.46, 0.47))
			if lod == 0:
				boxes.append([Transform3D(basis, _v3(lp, y + 1.2)), Vector3(0.1, 2.4, p0.distance_to(p1))])


# --- Buildings ---------------------------------------------------------------

func _buildings() -> void:
	for lot in gen.lots_in_chunk(key):
		var bd := BuildingGen.build(gen, lot, lod == 0)
		var c: Vector2 = lot.center - origin
		var xf := Transform3D(Basis(Vector3.UP, lot.yaw), Vector3(c.x, lot.floor, c.y))
		building.append(bd.ext, xf)
		glass.append(bd.glass, xf)
		if lod == 0:
			_box_batch_ends.append(boxes.size())
			for bx in bd.boxes:
				boxes.append([xf * (bx[0] as Transform3D), bx[1]])
			for d in bd.doors:
				var dd: Dictionary = d.duplicate()
				dd.xf = xf * (d.xf as Transform3D)
				doors.append(dd)
			for ct in bd.containers:
				var cc: Dictionary = ct.duplicate()
				cc.pos = xf * (ct.pos as Vector3)
				containers.append(cc)
			for s in bd.signs:
				var ss: Dictionary = s.duplicate()
				ss.xf = xf * (s.xf as Transform3D)
				signs.append(ss)
		for p in bd.props:
			_add_prop(p.type, xf * (p.xf as Transform3D))


# --- Props -------------------------------------------------------------------

func _add_prop(type: String, xf: Transform3D) -> void:
	var name := type
	if type == "car":
		name = "car_%d" % (absi(int(xf.origin.x * 13.0 + xf.origin.z * 7.0)) % Assets.CAR_COUNT)
		if lod == 0:
			car_boxes.append(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)))
	elif type.begins_with("car_") and lod == 0:
		car_boxes.append(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)))
	if lod == 1:
		if type == "pine":
			name = "pine_far"
		elif type in ["broadleaf", "yard_tree"]:
			name = "broadleaf_far"
	var buf: PackedFloat32Array = props.get(name, PackedFloat32Array())
	var b := xf.basis
	var o := xf.origin
	buf.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z])
	props[name] = buf
	prop_counts[name] = prop_counts.get(name, 0) + 1
	if lod == 0 and type in ["pine", "broadleaf", "yard_tree", "dead_tree", "cactus"]:
		tree_points.append(o)


func _blocked(p: Vector2, margin: float) -> bool:
	for t in ctx.towns:
		if p.distance_to(t.center) < t.radius + margin:
			return true
	for s in ctx.sites:
		if RoadNetwork._in_pad(s, p, margin + 10.0):
			return true
	var net := gen.roads
	for s in ctx.road_segs:
		var road_type: int = net.roads[net.index.owner[s]].type
		if net.index.closest(s, p).x < RoadNetwork.edge_half(road_type) + margin:
			return true
	if not ctx.river_segs.is_empty() or gen.hydro.lake_cell_count > 0:
		if gen.hydro.water_level(p, ctx.river_segs) > -INF:
			return true
		var r := gen.hydro.river_at(p, ctx.river_segs)
		if r.x < r.z + 4.0:
			return true
	return false


func _nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.hash3(key.x, key.y, gen.seed_value)
	var size := WorldGen.CHUNK_SIZE
	for k in 120:
		var lx := rng.randf() * size
		var lz := rng.randf() * size
		var roll := rng.randf()
		var s := 0.8 + rng.randf() * 0.6
		var yaw := rng.randf() * TAU
		var pick := rng.randf()
		if lod == 1 and k % 2 == 1:
			continue
		var p := origin + Vector2(lx, lz)
		var h := _sample(lx, lz)
		if h < 0.5:
			continue
		var type := ""
		var density := 0.0
		match gen.terrain.biome_at(p.x, p.y, h):
			Terrain.Biome.FOREST:
				density = 0.75
				type = "pine" if pick < 0.6 else "broadleaf"
			Terrain.Biome.PLAINS:
				density = 0.1
				type = "broadleaf" if pick < 0.55 else "bush"
			Terrain.Biome.FARMLAND:
				density = 0.035
				type = "broadleaf" if pick < 0.5 else "bush"
			Terrain.Biome.DESERT:
				density = 0.09
				type = "cactus" if pick < 0.4 else ("dry_bush" if pick < 0.85 else "rock")
			Terrain.Biome.MOUNTAIN:
				density = 0.14
				type = "pine" if pick < 0.6 else ("rock" if pick < 0.85 else "dead_tree")
		if type == "" or roll > density:
			continue
		if _blocked(p, 3.0):
			continue
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
		_add_prop(type, Transform3D(basis, Vector3(lx, h - 0.25, lz)))


func _street_props() -> void:
	var rect := Rect2(origin, Vector2.ONE * WorldGen.CHUNK_SIZE)
	var net := gen.roads
	for s in ctx.road_segs:
		if not rect.has_point(net.index.a[s]):
			continue
		var id := net.index.owner[s]
		var k := net.index.index[s]
		var r: Dictionary = net.roads[id]
		var pts: PackedVector2Array = r.pts
		var hs: PackedFloat32Array = r.h
		var br: PackedByteArray = r.bridge
		if br[k]:
			continue
		var side_v := RoadMesher._frame(pts, k)
		var dir := (pts[k + 1] - pts[k]).normalized()
		var hsh := WorldGen.hash3(id, k, gen.seed_value)
		var hw: float = RoadNetwork.HALF_WIDTH[r.type]
		var yaw := atan2(dir.x, dir.y)
		match r.type:
			RoadNetwork.Type.STREET:
				var side := 1.0 if k % 2 == 0 else -1.0
				if k % 3 == 0:
					var p := pts[k] + side_v * side * (hw + RoadNetwork.SIDEWALK - 0.4) - origin
					_add_prop("streetlight", Transform3D(Basis(Vector3.UP, yaw + (PI * 0.5 if side < 0 else -PI * 0.5)), _v3(p, hs[k] + 0.2)))
				if hsh % 9 == 0:
					var p := pts[k] + side_v * -side * (hw + 0.6) - origin
					_add_prop("hydrant", Transform3D(Basis.IDENTITY, _v3(p, hs[k] + 0.2)))
				if hsh % 100 < 14:
					var p := pts[k] + dir * 4.0 + side_v * side * (hw - 1.2) - origin
					_add_prop("car", Transform3D(Basis(Vector3.UP, yaw + (0.0 if side > 0 else PI)), _v3(p, hs[k] + 0.06)))
			RoadNetwork.Type.ROAD, RoadNetwork.Type.HIGHWAY:
				if k % 5 == 0:
					var p := pts[k] + side_v * (hw + 2.5) - origin
					_add_prop("utility_pole", Transform3D(Basis(Vector3.UP, yaw), _v3(p, _sample(clampf(p.x, 0, 63.9), clampf(p.y, 0, 63.9)))))
				if hsh % 100 < 3:
					# Abandoned or crashed car on the road.
					var lane := (hsh >> 8) % 2 * 2 - 1
					var p := pts[k] + side_v * lane * hw * 0.45 - origin
					var crash := float((hsh >> 10) % 100) / 100.0 - 0.5
					_add_prop("car", Transform3D(Basis(Vector3.UP, yaw + crash * 1.5), _v3(p, hs[k] + 0.06)))


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)
