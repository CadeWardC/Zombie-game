class_name Interiors
extends RefCounted
## Room planning and furnishing.

const INNER_T := 0.12 # Interior wall thickness.
const DOOR_CLEAR := 1.7 # Kept free in front of every door.
## Furniture too tall to stand in front of a window.
const TALL := ["wardrobe", "bookshelf", "fridge", "store_shelf", "locker", "medical_cabinet", "filing_cabinet",
	"cryo_fridge", "vanity", "tv_stand", "generator"]

const PLANS := {
	"living": [["couch", "wall"], ["tv_stand", "wall"], ["armchair", "wall"], ["armchair", "wall"], ["bookshelf", "wall"],
		["side_table", "wall"], ["floor_lamp", "wall"], ["plant", "wall"], ["rug", "center"], ["coffee_table", "center"]],
	"kitchen": [["fridge", "wall"], ["stove", "wall"], ["sink_counter", "wall"], ["counter", "wall"], ["counter", "wall"],
		["counter", "wall"], ["counter", "wall"], ["trash_can", "wall"], ["dining_set", "center"]],
	"dining": [["dining_set", "center"], ["dresser", "wall"], ["bookshelf", "wall"], ["plant", "wall"], ["side_table", "wall"]],
	"bedroom": [["bed_double", "wall"], ["nightstand", "wall"], ["nightstand", "wall"], ["dresser", "wall"], ["wardrobe", "wall"],
		["laundry", "wall"], ["floor_lamp", "wall"], ["rug", "center"]],
	"kids": [["bed_single", "wall"], ["nightstand", "wall"], ["desk", "wall"], ["wardrobe", "wall"], ["bookshelf", "wall"],
		["toy_box", "wall"], ["rug", "center"]],
	"bathroom": [["bathtub", "wall"], ["toilet", "wall"], ["vanity", "wall"], ["trash_can", "wall"]],
	"office": [["desk", "wall"], ["bookshelf", "wall"], ["filing_cabinet", "wall"], ["armchair", "wall"], ["plant", "wall"],
		["boxes", "wall"]],
	"garage": [["store_shelf", "wall"], ["desk", "wall"], ["washer", "wall"], ["dryer", "wall"], ["boxes", "wall"], ["boxes", "wall"]],
	"hall": [["coat_rack", "wall"], ["shoe_rack", "wall"], ["plant", "wall"], ["side_table", "wall"]],
}
## Floors by room type: [colour, colour] (two tones make tiles).
const FLOORS := {
	"kitchen": [Color(0.78, 0.77, 0.73), Color(0.62, 0.6, 0.56)], "bathroom": [Color(0.85, 0.86, 0.86), Color(0.55, 0.62, 0.66)],
}
const CARPETS := [Color(0.42, 0.38, 0.33), Color(0.36, 0.4, 0.44), Color(0.5, 0.45, 0.36), Color(0.4, 0.3, 0.3), Color(0.33, 0.38, 0.32)]
const CURTAINS := [Color(0.55, 0.45, 0.35), Color(0.35, 0.4, 0.5), Color(0.6, 0.55, 0.5), Color(0.45, 0.25, 0.22), Color(0.3, 0.38, 0.3)]
## Floor clutter by room type (see _clutter).
const CLUTTER := {
	"kitchen": ["shards", "can", "bottle", "papers", "trash_bag", "chair", "shards"],
	"living": ["papers", "books", "bottle", "chair", "clothes", "box", "can"],
	"dining": ["shards", "chair", "chair", "papers", "bottle"],
	"bedroom": ["clothes", "clothes", "books", "papers", "box", "bottle"],
	"kids": ["toy", "toy", "clothes", "books", "papers"],
	"bathroom": ["clothes", "shards", "bottle"],
	"office": ["papers", "papers", "books", "box", "chair"],
	"garage": ["tire", "box", "box", "can", "pallet", "trash_bag"],
	"hall": ["papers", "clothes", "box", "trash_bag"],
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
				openings.append({"at": at, "w": minf(1.1, span - 0.3), "bottom": 0.0, "top": 2.1, "kind": "door"})
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
	var windows: Array[Rect2] = []
	for w in bd.window_spots:
		if absf(float(w.y) - y0) < 1.0 and inner.grow(0.5).intersects(w.rect):
			windows.append(w.rect)
	var plan: Array = PLANS.get(type, [])
	if type == "bedroom" and inner.get_area() < 9.0:
		plan = PLANS["kids"]
		type = "kids"
	_dress_room(bd, inner, type, y0, doors, windows, rng)
	for item in plan:
		var kind: String = item[0]
		if item[1] == "center":
			_center(bd, inner, kind, y0, blocked, rng, id_prefix)
		else:
			_against_wall(bd, inner, kind, y0, blocked, windows, rng, id_prefix)
	_clutter(bd, inner, type, y0, blocked, rng)


## Floor finish, skirting boards, a ceiling light, curtains and pictures.
static func _dress_room(bd: BuildingData, inner: Rect2, type: String, y0: float, doors: Array[Vector2], windows: Array[Rect2], rng: RandomNumberGenerator) -> void:
	var m := bd.ext
	var fy := y0 # Top of the floor slab.
	# Tiles in kitchens and bathrooms, carpet in bedrooms.
	if FLOORS.has(type):
		var cols: Array = FLOORS[type]
		var tile := 0.6 if type == "kitchen" else 0.4
		var nx := int(ceil(inner.size.x / tile))
		var nz := int(ceil(inner.size.y / tile))
		for ix in nx:
			for iz in nz:
				var r := Rect2(inner.position + Vector2(ix, iz) * tile, Vector2(tile, tile)).intersection(inner)
				var c := r.get_center()
				Decor.flat(m, Transform3D(Basis.IDENTITY, Vector3(c.x, fy, c.y)), r.size, cols[(ix + iz) % 2], 0.004)
	elif type in ["bedroom", "kids"]:
		var c := inner.get_center()
		Decor.flat(m, Transform3D(Basis.IDENTITY, Vector3(c.x, fy, c.y)), inner.size, CARPETS[rng.randi() % CARPETS.size()], 0.004)
	# Skirting boards, broken at doorways.
	var corners := [Vector2(inner.position.x, inner.position.y), Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	var trim := Color(0.93, 0.92, 0.88) if rng.randf() < 0.6 else Color(0.35, 0.25, 0.17)
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var inward := (inner.get_center() - (a + b) * 0.5)
		inward = Vector2(signf(inward.x) if absf(b.x - a.x) < 0.01 else 0.0, signf(inward.y) if absf(b.y - a.y) < 0.01 else 0.0)
		var dir := (b - a).normalized()
		var len := a.distance_to(b)
		var cuts: Array = [[0.0, len]]
		for d in doors:
			if Geometry2D.get_closest_point_to_segment(d, a, b).distance_to(d) < 0.5:
				var t := (d - a).dot(dir)
				var out: Array = []
				for cu in cuts:
					if t + 0.65 < cu[0] or t - 0.65 > cu[1]:
						out.append(cu)
						continue
					if t - 0.65 > cu[0]:
						out.append([cu[0], t - 0.65])
					if t + 0.65 < cu[1]:
						out.append([t + 0.65, cu[1]])
				cuts = out
		for cu in cuts:
			var p0: Vector2 = a + dir * float(cu[0])
			var p1: Vector2 = a + dir * float(cu[1])
			Decor.baseboard(m, Vector3(p0.x, fy, p0.y), Vector3(p1.x, fy, p1.y), Vector3(inward.x, 0, inward.y), trim)
	# A light in the middle of the ceiling (some hang loose).
	var cc := inner.get_center()
	Decor.ceiling_light(m, Transform3D(Basis.IDENTITY, Vector3(cc.x, y0 - 0.07 + BuildingGen.STOREY - 0.1, cc.y)), rng.randf() < 0.15)
	# Curtains by the windows of living rooms and bedrooms.
	if type in ["living", "bedroom", "kids", "dining", "office"]:
		var curtain: Color = CURTAINS[rng.randi() % CURTAINS.size()]
		for w in bd.window_spots:
			if absf(float(w.y) - (y0 - 0.07)) > 1.0 or not inner.grow(0.4).has_point(w.mid):
				continue
			var out: Vector2 = w.out
			var inside: Vector2 = (w.mid as Vector2) - out * (float(w.t) * 0.5 + 0.01)
			var xf := Transform3D(Basis(Vector3(out.y, 0, -out.x) * -1.0, Vector3.UP, Vector3(-out.x, 0, -out.y)),
				Vector3(inside.x, y0 - 0.07 + float(w.sill) + float(w.h) * 0.5, inside.y))
			Decor.curtains(m, xf, float(w.w), float(w.h), curtain)
	# Pictures (and a clock, a shelf) on clear stretches of wall.
	for side in 4:
		if rng.randf() > (0.55 if type != "bathroom" else 0.25):
			continue
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var t := rng.randf_range(0.3, 0.7)
		var p := a.lerp(b, t)
		var ok := a.distance_to(b) > 1.4
		for d in doors:
			if d.distance_to(p) < 1.0:
				ok = false
		for w in windows:
			if w.grow(0.3).has_point(p):
				ok = false
		if not ok:
			continue
		var inward := (inner.get_center() - (a + b) * 0.5)
		inward = Vector2(signf(inward.x) if absf(b.x - a.x) < 0.01 else 0.0, signf(inward.y) if absf(b.y - a.y) < 0.01 else 0.0)
		var basis := Basis(Vector3(inward.y, 0, -inward.x), Vector3.UP, Vector3(inward.x, 0, inward.y))
		var xf := Transform3D(basis, Vector3(p.x, y0 + 1.55, p.y))
		var roll := rng.randf()
		if type == "kitchen" and roll < 0.5:
			Decor.clock(m, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)))
		elif type in ["kids", "office", "garage"] and roll < 0.4:
			Decor.wall_shelf(m, xf, rng)
		else:
			Decor.picture(m, xf, Vector2(rng.randf_range(0.4, 0.9), rng.randf_range(0.35, 0.7)), rng, rng.randf() < 0.25)


## Things left lying around: by room type, plus now and then blood, or a
## body. Kept off doorways and furniture.
static func _clutter(bd: BuildingData, inner: Rect2, type: String, y0: float, blocked: Array[Rect2], rng: RandomNumberGenerator) -> void:
	var m := bd.ext
	var kinds: Array = CLUTTER.get(type, ["papers"])
	var fy := y0
	var n := int(inner.get_area() / 5.0) + rng.randi_range(1, 3)
	var placed := 0
	for attempt in n * 4:
		if placed >= n:
			break
		var p := Vector2(rng.randf_range(inner.position.x + 0.4, inner.end.x - 0.4), rng.randf_range(inner.position.y + 0.4, inner.end.y - 0.4))
		var fp := Rect2(p - Vector2(0.35, 0.35), Vector2(0.7, 0.7))
		var free := true
		for bl in blocked:
			if bl.intersects(fp):
				free = false
				break
		if not free:
			continue
		blocked.append(fp)
		placed += 1
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, fy, p.y))
		match kinds[rng.randi() % kinds.size()]:
			"shards":
				Decor.shards(m, xf, rng)
			"can":
				Decor.can(m, xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.033, 0)), Color.from_hsv(rng.randf(), 0.6, 0.6))
			"bottle":
				Decor.bottle(m, xf, Color(0.2, 0.4, 0.2), true)
			"papers":
				Decor.papers(m, xf, rng)
			"trash_bag":
				Decor.trash_bag(m, xf, rng)
			"chair":
				Decor.chair(m, xf, Color(0.4, 0.28, 0.18), true)
			"clothes":
				Decor.clothes(m, xf, rng)
			"books":
				Decor.books(m, xf, rng)
			"box":
				Decor.cardboard_box(m, xf, Vector3(0.45, 0.35, 0.4), rng.randf() < 0.5)
			"toy":
				Decor.toy(m, xf, rng)
			"tire":
				Decor.tire(m, xf)
			"pallet":
				Decor.pallet(m, xf)
	# Signs of what happened here.
	var roll := rng.randf()
	if roll < 0.04 and inner.get_area() > 7.0:
		var c := inner.get_center() + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
		Decor.corpse(m, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(c.x, fy, c.y)), rng)
	elif roll < 0.16:
		var c := Vector2(rng.randf_range(inner.position.x + 0.6, inner.end.x - 0.6), rng.randf_range(inner.position.y + 0.6, inner.end.y - 0.6))
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(c.x, fy, c.y))
		Decor.blood(m, xf, rng.randf_range(0.3, 0.6), rng)
		if rng.randf() < 0.5:
			Decor.blood_trail(m, xf, rng.randf_range(1.0, 2.5), rng)


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


static func _against_wall(bd: BuildingData, inner: Rect2, kind: String, y0: float, blocked: Array[Rect2], windows: Array[Rect2], rng: RandomNumberGenerator, id_prefix: String) -> void:
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
			var under_window := false
			for w in windows:
				if w.intersects(fp):
					under_window = true
					break
			if under_window and kind in TALL:
				free = false
			if free:
				blocked.append(fp.grow(0.05))
				Furniture.place(bd, kind, xf, rng, id_prefix, under_window)
				return
			pos += 0.25
