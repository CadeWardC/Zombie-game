class_name SegmentIndex
extends RefCounted
## Buckets line segments (rivers, roads) by chunk so a chunk can quickly find
## the few segments that affect it. Read-only after building, so it can be
## shared by worker threads.

var cell := 64.0
var a := PackedVector2Array()
var b := PackedVector2Array()
var owner := PackedInt32Array() # e.g. river or road id
var index := PackedInt32Array() # point index within the owner
var _buckets := {} # Vector2i -> PackedInt32Array


func add(p0: Vector2, p1: Vector2, margin: float, owner_id: int, point_index: int) -> void:
	var id := a.size()
	a.append(p0)
	b.append(p1)
	owner.append(owner_id)
	index.append(point_index)
	var lo := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)) - Vector2(margin, margin)
	var hi := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y)) + Vector2(margin, margin)
	for cz in range(floori(lo.y / cell), floori(hi.y / cell) + 1):
		for cx in range(floori(lo.x / cell), floori(hi.x / cell) + 1):
			var k := Vector2i(cx, cz)
			var arr: PackedInt32Array = _buckets.get(k, PackedInt32Array())
			arr.append(id)
			_buckets[k] = arr


func query_chunk(key: Vector2i) -> PackedInt32Array:
	return _buckets.get(key, PackedInt32Array())


## Distance from p to segment s, and the 0..1 position along it.
func closest(s: int, p: Vector2) -> Vector2:
	var ab := b[s] - a[s]
	var len2 := ab.length_squared()
	var t := 0.0 if len2 < 0.0001 else clampf((p - a[s]).dot(ab) / len2, 0.0, 1.0)
	return Vector2(p.distance_to(a[s] + ab * t), t)
