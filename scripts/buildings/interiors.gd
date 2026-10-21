class_name Interiors
extends RefCounted
## Room planning and furnishing.

const INNER_T := 0.12 # Interior wall thickness.
const DOOR_CLEAR := 1.5 # Kept free in front of every door.

const PLANS := {
	"living": [["couch", "wall"], ["tv_stand", "wall"], ["armchair", "wall"], ["bookshelf", "wall"], ["rug", "center"], ["coffee_table", "center"]],
	"kitchen": [["fridge", "wall"], ["stove", "wall"], ["sink_counter", "wall"], ["counter", "wall"], ["counter", "wall"], ["counter", "wall"], ["dining_set", "center"]],
	"dining": [["dining_set", "center"], ["dresser", "wall"], ["bookshelf", "wall"]],
	"bedroom": [["bed_double", "wall"], ["nightstand", "wall"], ["dresser", "wall"], ["wardrobe", "wall"], ["rug", "center"]],
	"kids": [["bed_single", "wall"], ["nightstand", "wall"], ["desk", "wall"], ["wardrobe", "wall"], ["bookshelf", "wall"]],
	"bathroom": [["bathtub", "wall"], ["toilet", "wall"], ["vanity", "wall"]],
	"office": [["desk", "wall"], ["bookshelf", "wall"], ["filing_cabinet", "wall"], ["armchair", "wall"]],
	"garage": [["store_shelf", "wall"], ["desk", "wall"]],
	"hall": [],
}


## Recursively splits `rect` into about `count` rooms.
## Returns {rooms: Array[Rect2], walls: Array[[Vector2, Vector2]]}.
static func split(rect: Rect2, count: int, rng: RandomNumberGenerator, min_size := 2.6) -> Dictionary:
	var rooms: Array[Rect2] = [rect]
	var walls: Array = []
	var guard := 0
	while rooms.size() < count and guard < 40:
		guard += 1
		rooms.sort_custom(func(a, b): return a.get_area() > b.get_area())
		var r: Rect2 = rooms[0]
		var along_x := r.size.x >= r.size.y
		var length := r.size.x if along_x else r.size.y
		if length < min_size * 2.0:
			break
		var t := rng.randf_range(0.4, 0.6)
		var cut := length * t
		rooms.remove_at(0)
		if along_x:
			var x := r.position.x + cut
			rooms.append(Rect2(r.position, Vector2(cut, r.size.y)))
			rooms.append(Rect2(Vector2(x, r.position.y), Vector2(r.size.x - cut, r.size.y)))
			walls.append([Vector2(x, r.position.y), Vector2(x, r.end.y)])
		else:
			var z := r.position.y + cut
			rooms.append(Rect2(r.position, Vector2(r.size.x, cut)))
			rooms.append(Rect2(Vector2(r.position.x, z), Vector2(r.size.x, r.size.y - cut)))
			walls.append([Vector2(r.position.x, z), Vector2(r.end.x, z)])
	return {"rooms": rooms, "walls": walls}


## Builds interior walls with a door in every stretch between junctions, so
## all rooms connect. Returns the door positions (for keeping them clear).
static func build_walls(bd: BuildingData, walls: Array, y0: float, height: float, col: Color, id_prefix: String) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for w in walls:
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var cuts: Array[float] = [0.0, length]
		for o in walls:
			if o == w:
				continue
			for p: Vector2 in [o[0], o[1]]:
				var t := (p - a).dot(dir)
				if t > 0.3 and t < length - 0.3 and Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < 0.05:
					cuts.append(t)
		cuts.sort()
		var openings := []
		for k in cuts.size() - 1:
			var span := cuts[k + 1] - cuts[k]
			if span >= 1.4:
				var at := (cuts[k] + cuts[k + 1]) * 0.5
				openings.append({"at": at, "w": 0.85, "bottom": 0.0, "top": 2.05, "kind": "door"})
				spots.append(a + dir * at)
		var nrm := Vector2(-dir.y, dir.x)
		BuildingParts.wall(bd, a, b, y0, height, col, col, nrm, openings, INNER_T, Color(0.6, 0.5, 0.38), id_prefix)
	return spots


## Places furniture for a room type along the walls, keeping doors clear.
static func furnish(bd: BuildingData, room: Rect2, type: String, y0: float, doors: Array[Vector2],
		rng: RandomNumberGenerator, id_prefix: String) -> void:
	if not bd.interior:
		return
	var inner := room.grow(-BuildingParts.WALL_T * 0.5 - 0.03)
	var blocked: Array[Rect2] = []
	for d in doors:
		if inner.grow(0.5).has_point(d):
			blocked.append(Rect2(d - Vector2.ONE * DOOR_CLEAR * 0.5, Vector2.ONE * DOOR_CLEAR))
	var plan: Array = PLANS.get(type, [])
	if type == "bedroom" and inner.get_area() < 9.0:
		plan = PLANS["kids"]
	for item in plan:
		var kind: String = item[0]
		if item[1] == "center":
			_center(bd, inner, kind, y0, blocked, rng, id_prefix)
		else:
			_against_wall(bd, inner, kind, y0, blocked, rng, id_prefix)


static func _center(bd: BuildingData, inner: Rect2, kind: String, y0: float, blocked: Array[Rect2], rng: RandomNumberGenerator, id_prefix: String) -> void:
	var size := Vector2(2.2, 1.6) if kind == "rug" else (Vector2(1.6, 2.2) if kind == "dining_set" else Vector2(1.1, 0.6))
	if inner.size.x < size.x + 1.4 or inner.size.y < size.y + 1.4:
		return
	var c := inner.get_center()
	var fp := Rect2(c - size * 0.5, size)
	if kind != "rug":
		for b in blocked:
			if b.intersects(fp):
				return
		blocked.append(fp)
	Furniture.place(bd, kind, Transform3D(Basis.IDENTITY, Vector3(c.x, y0, c.y)), rng, id_prefix)


static func _against_wall(bd: BuildingData, inner: Rect2, kind: String, y0: float, blocked: Array[Rect2], rng: RandomNumberGenerator, id_prefix: String) -> void:
	var s: Vector2 = Furniture.SIZE.get(kind, Vector2(1, 0.5))
	var sides := [0, 1, 2, 3]
	# Shuffle deterministically so rooms don't all look the same.
	for k in range(sides.size() - 1, 0, -1):
		var j := rng.randi() % (k + 1)
		var t: int = sides[k]
		sides[k] = sides[j]
		sides[j] = t
	for side in sides:
		var along_x: bool = side < 2
		var span := inner.size.x if along_x else inner.size.y
		if span < s.x + 0.1 or (inner.size.y if along_x else inner.size.x) < s.y + 1.0:
			continue
		var pos := s.x * 0.5 + 0.05
		while pos <= span - s.x * 0.5 - 0.05:
			var fp: Rect2
			var xf: Transform3D
			match side:
				0:
					var c := Vector2(inner.position.x + pos, inner.position.y + s.y * 0.5)
					fp = Rect2(c - s * 0.5, s)
					xf = Transform3D(Basis.IDENTITY, Vector3(c.x, y0, c.y))
				1:
					var c := Vector2(inner.position.x + pos, inner.end.y - s.y * 0.5)
					fp = Rect2(c - s * 0.5, s)
					xf = Transform3D(Basis(Vector3.UP, PI), Vector3(c.x, y0, c.y))
				2:
					var c := Vector2(inner.position.x + s.y * 0.5, inner.position.y + pos)
					fp = Rect2(c - Vector2(s.y, s.x) * 0.5, Vector2(s.y, s.x))
					xf = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(c.x, y0, c.y))
				_:
					var c := Vector2(inner.end.x - s.y * 0.5, inner.position.y + pos)
					fp = Rect2(c - Vector2(s.y, s.x) * 0.5, Vector2(s.y, s.x))
					xf = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(c.x, y0, c.y))
			var free := true
			for b in blocked:
				if b.intersects(fp):
					free = false
					break
			if free:
				blocked.append(fp.grow(0.05))
				Furniture.place(bd, kind, xf, rng, id_prefix)
				return
			pos += 0.25
