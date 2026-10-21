class_name RoadMesher
extends RefCounted
## Builds the road meshes for one chunk: ribbons with lane markings (from the
## road texture atlas), raised sidewalks with curbs on town streets,
## intersection patches, and bridges (deck, railings, pillars).
## Thread-safe: only reads WorldGen and writes MeshData.

const LIFT := 0.06 # Road surface sits just above the graded terrain.
const CURB := 0.16
const CONCRETE := Color(0.58, 0.57, 0.54)
const RAIL := Color(0.5, 0.5, 0.52)


## Returns {road: MeshData (UV), solid: MeshData, boxes: [[Transform3D, Vector3]]}
## `boxes` are collision boxes for bridges, in chunk-local space.
static func build(gen: WorldGen, key: Vector2i, ctx: WorldGen.ChunkContext, with_collision: bool) -> Dictionary:
	var road := MeshData.new(true)
	var solid := MeshData.new()
	var boxes := []
	var origin := Vector2(key) * WorldGen.CHUNK_SIZE
	var rect := Rect2(origin, Vector2.ONE * WorldGen.CHUNK_SIZE)
	var net := gen.roads
	# Group this chunk's segments by road; a segment belongs to the chunk
	# holding its start point, so neighbours never draw it twice.
	var by_road := {}
	for s in ctx.road_segs:
		if rect.has_point(net.index.a[s]):
			by_road.get_or_add(net.index.owner[s], []).append(net.index.index[s])
	for id in by_road:
		var ks: Array = by_road[id]
		ks.sort()
		for k in ks:
			_segment(net.roads[id], k, origin, road, solid, boxes, with_collision, gen)
	for nid in net.nodes_in_chunk(key):
		_node(net.nodes[nid], origin, road)
	return {"road": road, "solid": solid, "boxes": boxes}


static func _frame(pts: PackedVector2Array, k: int) -> Vector2:
	var a := pts[maxi(k - 1, 0)]
	var b := pts[mini(k + 1, pts.size() - 1)]
	var t := (b - a).normalized()
	return Vector2(-t.y, t.x)


static func _segment(r: Dictionary, k: int, origin: Vector2, road: MeshData, solid: MeshData,
		boxes: Array, with_collision: bool, gen: WorldGen) -> void:
	var pts: PackedVector2Array = r.pts
	var hs: PackedFloat32Array = r.h
	var type: int = r.type
	var hw: float = RoadNetwork.HALF_WIDTH[type]
	var p0 := pts[k] - origin
	var p1 := pts[k + 1] - origin
	var s0 := _frame(pts, k)
	var s1 := _frame(pts, k + 1)
	var y0 := hs[k] + LIFT
	var y1 := hs[k + 1] + LIFT
	var v0 := k * RoadNetwork.STEP / Textures.ROAD_V_METRES
	var v1 := (k + 1) * RoadNetwork.STEP / Textures.ROAD_V_METRES
	var urange: Vector2 = Textures.U_STREET
	match type:
		RoadNetwork.Type.HIGHWAY: urange = Textures.U_HIGHWAY
		RoadNetwork.Type.ROAD: urange = Textures.U_ROAD
		RoadNetwork.Type.DIRT: urange = Textures.U_DIRT
	var l0 := _v3(p0 - s0 * hw, y0)
	var r0 := _v3(p0 + s0 * hw, y0)
	var l1 := _v3(p1 - s1 * hw, y1)
	var r1 := _v3(p1 + s1 * hw, y1)
	road.quad(l0, r0, r1, l1, Color.WHITE, Vector3.UP,
			Vector2(urange.x, v0), Vector2(urange.y, v0), Vector2(urange.y, v1), Vector2(urange.x, v1))

	if type == RoadNetwork.Type.STREET:
		var sw := RoadNetwork.SIDEWALK
		for side: float in [-1.0, 1.0]:
			var e0 := _v3(p0 + s0 * hw * side, y0)
			var e1 := _v3(p1 + s1 * hw * side, y1)
			var c0 := e0 + Vector3(0, CURB, 0)
			var c1 := e1 + Vector3(0, CURB, 0)
			var o0 := _v3(p0 + s0 * (hw + sw) * side, y0 + CURB)
			var o1 := _v3(p1 + s1 * (hw + sw) * side, y1 + CURB)
			var us := Textures.U_SIDEWALK
			road.quad(c0, o0, o1, c1, Color.WHITE, Vector3.UP,
					Vector2(us.x, v0), Vector2(us.y, v0), Vector2(us.y, v1), Vector2(us.x, v1))
			var outward := Vector3(-s0.x * side, 0, -s0.y * side)
			road.quad(e0, e1, c1, c0, Color.WHITE, outward,
					Vector2(us.x, v0), Vector2(us.x, v1), Vector2(us.x + 0.01, v1), Vector2(us.x + 0.01, v0))
			# Sidewalk outer edge down to the ground.
			var g0 := o0 - Vector3(0, CURB + 0.3, 0)
			var g1 := o1 - Vector3(0, CURB + 0.3, 0)
			road.quad(o0, o1, g1, g0, Color.WHITE, -outward,
					Vector2(us.x, v0), Vector2(us.x, v1), Vector2(us.x + 0.01, v1), Vector2(us.x + 0.01, v0))

	var br: PackedByteArray = r.bridge
	if br[k] or br[k + 1]:
		_bridge(p0, p1, s0, s1, y0, y1, hw, k, solid, boxes, with_collision, origin, gen)
	else:
		# Road edge skirt so the ribbon never shows a gap above the terrain.
		for side: float in [-1.0, 1.0]:
			var e0 := _v3(p0 + s0 * hw * side, y0)
			var e1 := _v3(p1 + s1 * hw * side, y1)
			if type != RoadNetwork.Type.STREET:
				road.quad(e0, e1, e1 - Vector3(0, 0.6, 0), e0 - Vector3(0, 0.6, 0), Color.WHITE,
						Vector3(s0.x * side, 0, s0.y * side),
						Vector2(urange.x, v0), Vector2(urange.x, v1), Vector2(urange.x, v1), Vector2(urange.x, v0))


static func _bridge(p0: Vector2, p1: Vector2, s0: Vector2, s1: Vector2, y0: float, y1: float, hw: float,
		k: int, solid: MeshData, boxes: Array, with_collision: bool, origin: Vector2, gen: WorldGen) -> void:
	var depth := 1.3
	for side: float in [-1.0, 1.0]:
		var e0 := _v3(p0 + s0 * hw * side, y0)
		var e1 := _v3(p1 + s1 * hw * side, y1)
		var out := Vector3(s0.x * side, 0, s0.y * side)
		solid.quad(e0, e1, e1 - Vector3(0, depth, 0), e0 - Vector3(0, depth, 0), CONCRETE, out)
		# Railing: posts and a top rail.
		var mid := (e0 + e1) * 0.5
		var dir := (e1 - e0)
		var len := dir.length()
		var yaw := atan2(dir.x, dir.z)
		var rail_xf := Transform3D(Basis(Vector3.UP, yaw), mid + Vector3(0, 0.95, 0) - out * 0.15)
		solid.box(rail_xf, Vector3(0.12, 0.12, len + 0.05), RAIL)
		solid.box(Transform3D(Basis(Vector3.UP, yaw), e0 + Vector3(0, 0.5, 0) - out * 0.15), Vector3(0.12, 1.0, 0.12), RAIL)
		solid.box(Transform3D(Basis(Vector3.UP, yaw), mid + Vector3(0, 0.25, 0) - out * 0.15), Vector3(0.3, 0.5, len), CONCRETE)
		if with_collision:
			boxes.append([Transform3D(Basis(Vector3.UP, yaw), mid + Vector3(0, 0.55, 0) - out * 0.15), Vector3(0.3, 1.1, len)])
	# Underside.
	var b0l := _v3(p0 - s0 * hw, y0 - depth)
	var b0r := _v3(p0 + s0 * hw, y0 - depth)
	var b1l := _v3(p1 - s1 * hw, y1 - depth)
	var b1r := _v3(p1 + s1 * hw, y1 - depth)
	solid.quad(b0l, b0r, b1r, b1l, CONCRETE.darkened(0.3), Vector3.DOWN)
	if k % 3 == 0:
		var w := origin + p0
		var ground := gen.terrain.macro_height(w.x, w.y) - 6.0
		var top := y0 - depth
		if top - ground > 1.0:
			var c := _v3(p0, (top + ground) * 0.5)
			solid.box(Transform3D(Basis(Vector3.UP, atan2(s0.x, s0.y)), c), Vector3(hw * 1.4, top - ground, 1.4), CONCRETE.darkened(0.1))
	if with_collision:
		var mid := (_v3(p0, y0) + _v3(p1, y1)) * 0.5
		var d := _v3(p1, y1) - _v3(p0, y0)
		var basis := Basis.looking_at(d.normalized(), Vector3.UP)
		boxes.append([Transform3D(basis, mid - basis.y * 0.25), Vector3(hw * 2.0, 0.5, d.length() + 0.2)])


static func _node(nd: Dictionary, origin: Vector2, road: MeshData) -> void:
	var c: Vector2 = nd.pos - origin
	var y: float = nd.h + LIFT + 0.002
	var half: float = nd.half
	var u := Textures.U_PLAIN
	if nd.round:
		var sides := 14
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			road.tri(_v3(c, y), _v3(c + Vector2.from_angle(a0) * half, y), _v3(c + Vector2.from_angle(a1) * half, y),
					Color.WHITE, Vector3.UP, Vector2(u, 0.1), Vector2(u, 0.2), Vector2(u, 0.3))
		return
	var a := Vector2.from_angle(nd.rot) * half
	var b := Vector2(-a.y, a.x)
	road.quad(_v3(c - a - b, y), _v3(c + a - b, y), _v3(c + a + b, y), _v3(c - a + b, y), Color.WHITE, Vector3.UP,
			Vector2(u, 0.1), Vector2(u + 0.02, 0.1), Vector2(u + 0.02, 0.3), Vector2(u, 0.3))


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)
