class_name Furniture
extends RefCounted
## Low-poly furniture built from boxes, plus loot containers.
## Each piece is placed with a transform whose origin is the centre of its
## footprint on the floor and whose local -Z faces the wall it backs onto
## (so +Z points into the room).

## Footprint [width (x), depth (z)] for wall-placement planning.
const SIZE := {
	"bed_double": Vector2(1.6, 2.1), "bed_single": Vector2(1.0, 2.0), "nightstand": Vector2(0.5, 0.45),
	"dresser": Vector2(1.2, 0.5), "wardrobe": Vector2(1.1, 0.6), "couch": Vector2(2.1, 0.9),
	"armchair": Vector2(0.9, 0.85), "tv_stand": Vector2(1.6, 0.45), "bookshelf": Vector2(1.0, 0.35),
	"counter": Vector2(0.6, 0.62), "sink_counter": Vector2(0.9, 0.62), "stove": Vector2(0.7, 0.62),
	"fridge": Vector2(0.8, 0.72), "toilet": Vector2(0.45, 0.7), "bathtub": Vector2(1.7, 0.75),
	"vanity": Vector2(0.8, 0.5), "desk": Vector2(1.3, 0.65), "store_shelf": Vector2(2.4, 0.5),
	"shop_counter": Vector2(2.4, 0.7), "locker": Vector2(0.9, 0.5), "hospital_bed": Vector2(1.0, 2.1),
	"medical_cabinet": Vector2(1.0, 0.45), "filing_cabinet": Vector2(0.5, 0.6), "cryo_fridge": Vector2(0.9, 0.7),
	"lab_bench": Vector2(2.4, 0.8), "generator": Vector2(1.6, 0.9),
}

const WOOD := Color(0.45, 0.31, 0.2)
const DARK_WOOD := Color(0.3, 0.2, 0.13)
const WHITE := Color(0.88, 0.88, 0.86)
const STEEL := Color(0.6, 0.62, 0.64)
const FABRICS := [Color(0.35, 0.4, 0.5), Color(0.5, 0.33, 0.28), Color(0.4, 0.45, 0.32), Color(0.55, 0.5, 0.42), Color(0.3, 0.3, 0.32)]


static func _b(bd: BuildingData, xf: Transform3D, center: Vector3, size: Vector3, col: Color) -> void:
	bd.ext.box(xf * Transform3D(Basis.IDENTITY, center), size, col)


static func _container(bd: BuildingData, xf: Transform3D, type: String, id_prefix: String) -> void:
	bd.containers.append({"pos": xf * Vector3(0, 0.6, 0.2), "type": type, "id": "%s_c%d" % [id_prefix, bd.containers.size()]})


static func _collide(bd: BuildingData, xf: Transform3D, size: Vector3) -> void:
	bd.boxes.append([xf * Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5, 0)), size])


static func place(bd: BuildingData, kind: String, xf: Transform3D, rng: RandomNumberGenerator, id_prefix: String) -> void:
	var fabric: Color = FABRICS[rng.randi() % FABRICS.size()]
	match kind:
		"bed_double", "bed_single", "hospital_bed":
			var s: Vector2 = SIZE[kind]
			var frame := STEEL if kind == "hospital_bed" else DARK_WOOD
			_b(bd, xf, Vector3(0, 0.2, 0), Vector3(s.x, 0.25, s.y), frame)
			_b(bd, xf, Vector3(0, 0.42, 0.05), Vector3(s.x - 0.08, 0.2, s.y - 0.12), WHITE)
			_b(bd, xf, Vector3(0, 0.54, 0.25), Vector3(s.x - 0.04, 0.06, s.y * 0.7), fabric)
			_b(bd, xf, Vector3(0, 0.55, -s.y * 0.5 + 0.3), Vector3(s.x * 0.8, 0.12, 0.35), WHITE.darkened(0.05))
			_b(bd, xf, Vector3(0, 0.55, -s.y * 0.5 + 0.03), Vector3(s.x, 1.0, 0.06), frame)
			_collide(bd, xf, Vector3(s.x, 0.6, s.y))
		"nightstand":
			_b(bd, xf, Vector3(0, 0.28, 0), Vector3(0.5, 0.55, 0.45), WOOD)
			_b(bd, xf, Vector3(0, 0.62, 0), Vector3(0.12, 0.14, 0.12), Color(0.9, 0.85, 0.6))
			_container(bd, xf, "nightstand", id_prefix)
		"dresser":
			_b(bd, xf, Vector3(0, 0.45, 0), Vector3(1.2, 0.9, 0.5), WOOD)
			for k in 3:
				_b(bd, xf, Vector3(0, 0.18 + k * 0.27, 0.26), Vector3(1.05, 0.2, 0.02), WOOD.lightened(0.1))
			_collide(bd, xf, Vector3(1.2, 0.9, 0.5))
			_container(bd, xf, "dresser", id_prefix)
		"wardrobe":
			_b(bd, xf, Vector3(0, 1.0, 0), Vector3(1.1, 2.0, 0.6), WOOD.darkened(0.1))
			_b(bd, xf, Vector3(0, 1.0, 0.305), Vector3(0.02, 1.8, 0.01), DARK_WOOD)
			_collide(bd, xf, Vector3(1.1, 2.0, 0.6))
			_container(bd, xf, "wardrobe", id_prefix)
		"couch":
			_b(bd, xf, Vector3(0, 0.22, 0.05), Vector3(2.1, 0.44, 0.8), fabric)
			_b(bd, xf, Vector3(0, 0.6, -0.33), Vector3(2.1, 0.55, 0.22), fabric.darkened(0.1))
			for x: float in [-0.98, 0.98]:
				_b(bd, xf, Vector3(x, 0.4, 0.05), Vector3(0.18, 0.4, 0.8), fabric.darkened(0.15))
			_collide(bd, xf, Vector3(2.1, 0.8, 0.9))
		"armchair":
			_b(bd, xf, Vector3(0, 0.22, 0.05), Vector3(0.85, 0.44, 0.75), fabric)
			_b(bd, xf, Vector3(0, 0.6, -0.32), Vector3(0.85, 0.55, 0.2), fabric.darkened(0.1))
			_collide(bd, xf, Vector3(0.9, 0.8, 0.85))
		"coffee_table":
			_b(bd, xf, Vector3(0, 0.4, 0), Vector3(1.1, 0.06, 0.6), WOOD)
			for x: float in [-0.5, 0.5]:
				for z: float in [-0.25, 0.25]:
					_b(bd, xf, Vector3(x, 0.19, z), Vector3(0.05, 0.38, 0.05), WOOD.darkened(0.2))
		"tv_stand":
			_b(bd, xf, Vector3(0, 0.25, 0), Vector3(1.6, 0.5, 0.45), DARK_WOOD)
			_b(bd, xf, Vector3(0, 0.88, -0.05), Vector3(1.2, 0.7, 0.06), Color(0.08, 0.08, 0.09))
			_collide(bd, xf, Vector3(1.6, 0.5, 0.45))
		"bookshelf":
			_b(bd, xf, Vector3(0, 0.95, 0), Vector3(1.0, 1.9, 0.35), WOOD)
			for k in 4:
				for b in 5:
					var col := Color.from_hsv(rng.randf(), 0.5, 0.5)
					_b(bd, xf, Vector3(-0.4 + b * 0.18, 0.35 + k * 0.44, 0.04), Vector3(0.14, 0.3, 0.25), col)
			_collide(bd, xf, Vector3(1.0, 1.9, 0.35))
		"counter", "sink_counter", "stove":
			var w: float = SIZE[kind].x
			_b(bd, xf, Vector3(0, 0.43, 0), Vector3(w, 0.86, 0.6), WHITE if kind != "stove" else STEEL.darkened(0.3))
			_b(bd, xf, Vector3(0, 0.88, 0.01), Vector3(w + 0.02, 0.04, 0.62), Color(0.35, 0.33, 0.3))
			_b(bd, xf, Vector3(0, 1.75, -0.12), Vector3(w, 0.7, 0.35), WHITE.darkened(0.04))
			if kind == "sink_counter":
				_b(bd, xf, Vector3(0, 0.9, 0.05), Vector3(0.5, 0.02, 0.38), STEEL)
			elif kind == "stove":
				for x: float in [-0.17, 0.17]:
					for z: float in [-0.12, 0.14]:
						_b(bd, xf, Vector3(x, 0.91, z), Vector3(0.18, 0.01, 0.18), Color(0.1, 0.1, 0.1))
			_collide(bd, xf, Vector3(w, 0.9, 0.6))
			if kind == "counter":
				_container(bd, xf, "kitchen_cabinet", id_prefix)
		"fridge":
			_b(bd, xf, Vector3(0, 0.9, 0), Vector3(0.8, 1.8, 0.7), WHITE.lightened(0.05))
			_b(bd, xf, Vector3(0.3, 1.1, 0.36), Vector3(0.03, 0.5, 0.03), STEEL)
			_collide(bd, xf, Vector3(0.8, 1.8, 0.7))
			_container(bd, xf, "fridge", id_prefix)
		"toilet":
			_b(bd, xf, Vector3(0, 0.2, 0.08), Vector3(0.38, 0.4, 0.5), WHITE)
			_b(bd, xf, Vector3(0, 0.6, -0.25), Vector3(0.42, 0.45, 0.18), WHITE)
		"bathtub":
			_b(bd, xf, Vector3(0, 0.28, 0), Vector3(1.7, 0.56, 0.75), WHITE)
			_b(bd, xf, Vector3(0, 0.5, 0), Vector3(1.5, 0.08, 0.55), Color(0.75, 0.8, 0.82))
			_collide(bd, xf, Vector3(1.7, 0.56, 0.75))
		"vanity":
			_b(bd, xf, Vector3(0, 0.42, 0), Vector3(0.8, 0.84, 0.5), WOOD.lightened(0.2))
			_b(bd, xf, Vector3(0, 0.87, 0.02), Vector3(0.82, 0.04, 0.52), WHITE)
			_b(bd, xf, Vector3(0, 1.5, -0.22), Vector3(0.6, 0.7, 0.05), Color(0.7, 0.78, 0.82))
			_container(bd, xf, "medicine_cabinet", id_prefix)
		"desk":
			_b(bd, xf, Vector3(0, 0.74, 0), Vector3(1.3, 0.05, 0.65), WOOD)
			_b(bd, xf, Vector3(0.45, 0.36, 0), Vector3(0.38, 0.72, 0.6), WOOD.darkened(0.1))
			_b(bd, xf, Vector3(-0.6, 0.36, 0), Vector3(0.05, 0.72, 0.6), WOOD.darkened(0.1))
			_b(bd, xf, Vector3(0, 0.45, 0.55), Vector3(0.45, 0.06, 0.45), Color(0.15, 0.15, 0.17))
			_b(bd, xf, Vector3(0, 0.75, 0.76), Vector3(0.45, 0.55, 0.06), Color(0.15, 0.15, 0.17))
			_collide(bd, xf, Vector3(1.3, 0.76, 0.65))
			_container(bd, xf, "desk", id_prefix)
		"dining_set":
			_b(bd, xf, Vector3(0, 0.74, 0), Vector3(1.6, 0.05, 0.9), WOOD)
			for x: float in [-0.72, 0.72]:
				for z: float in [-0.38, 0.38]:
					_b(bd, xf, Vector3(x, 0.36, z), Vector3(0.06, 0.72, 0.06), WOOD.darkened(0.2))
			for x: float in [-0.45, 0.45]:
				for z: float in [-0.75, 0.75]:
					_b(bd, xf, Vector3(x, 0.45, z), Vector3(0.42, 0.05, 0.42), WOOD.darkened(0.1))
					_b(bd, xf, Vector3(x, 0.75, z + signf(z) * 0.19), Vector3(0.42, 0.55, 0.05), WOOD.darkened(0.1))
			_collide(bd, xf, Vector3(1.6, 0.76, 0.9))
		"rug":
			var c := Color.from_hsv(rng.randf(), 0.35, 0.45)
			var p0 := xf * Vector3(-1.1, 0.012, -0.8)
			var p1 := xf * Vector3(1.1, 0.012, -0.8)
			var p2 := xf * Vector3(1.1, 0.012, 0.8)
			var p3 := xf * Vector3(-1.1, 0.012, 0.8)
			bd.ext.quad(p0, p1, p2, p3, c, Vector3.UP)
		"store_shelf":
			_b(bd, xf, Vector3(0, 0.8, 0), Vector3(2.4, 1.6, 0.5), STEEL)
			for k in 4:
				for b in 6:
					var col := Color.from_hsv(rng.randf(), 0.6, 0.7)
					_b(bd, xf, Vector3(-1.0 + b * 0.4, 0.3 + k * 0.38, 0.15), Vector3(0.3, 0.25, 0.2), col)
			_collide(bd, xf, Vector3(2.4, 1.6, 0.5))
			_container(bd, xf, "store_shelf", id_prefix)
		"shop_counter":
			_b(bd, xf, Vector3(0, 0.5, 0), Vector3(2.4, 1.0, 0.7), WOOD.darkened(0.15))
			_b(bd, xf, Vector3(0.6, 1.15, 0), Vector3(0.4, 0.3, 0.35), Color(0.15, 0.15, 0.17))
			_collide(bd, xf, Vector3(2.4, 1.0, 0.7))
			_container(bd, xf, "register", id_prefix)
		"locker":
			_b(bd, xf, Vector3(0, 0.95, 0), Vector3(0.9, 1.9, 0.5), Color(0.35, 0.42, 0.5))
			_collide(bd, xf, Vector3(0.9, 1.9, 0.5))
			_container(bd, xf, "locker", id_prefix)
		"medical_cabinet":
			_b(bd, xf, Vector3(0, 0.9, 0), Vector3(1.0, 1.8, 0.45), WHITE)
			_b(bd, xf, Vector3(0, 1.4, 0.23), Vector3(0.25, 0.06, 0.01), Color(0.8, 0.1, 0.1))
			_b(bd, xf, Vector3(0, 1.4, 0.23), Vector3(0.06, 0.25, 0.01), Color(0.8, 0.1, 0.1))
			_collide(bd, xf, Vector3(1.0, 1.8, 0.45))
			_container(bd, xf, "medical", id_prefix)
		"filing_cabinet":
			_b(bd, xf, Vector3(0, 0.65, 0), Vector3(0.5, 1.3, 0.6), STEEL.darkened(0.15))
			_collide(bd, xf, Vector3(0.5, 1.3, 0.6))
			_container(bd, xf, "desk", id_prefix)
		"cryo_fridge":
			_b(bd, xf, Vector3(0, 0.95, 0), Vector3(0.9, 1.9, 0.7), Color(0.8, 0.82, 0.85))
			_b(bd, xf, Vector3(0, 1.1, 0.355), Vector3(0.6, 1.1, 0.01), Color(0.55, 0.7, 0.8))
			_b(bd, xf, Vector3(0.3, 1.75, 0.36), Vector3(0.12, 0.08, 0.01), Color(0.2, 0.8, 0.4))
			_collide(bd, xf, Vector3(0.9, 1.9, 0.7))
			_container(bd, xf, "cryo_fridge", id_prefix)
		"lab_bench":
			_b(bd, xf, Vector3(0, 0.88, 0), Vector3(2.4, 0.06, 0.8), Color(0.2, 0.22, 0.24))
			_b(bd, xf, Vector3(0, 0.43, 0), Vector3(2.3, 0.85, 0.7), WHITE.darkened(0.05))
			for k in 3:
				_b(bd, xf, Vector3(-0.7 + k * 0.7, 0.98, 0.1), Vector3(0.08, 0.14 + k * 0.04, 0.08), Color(0.5, 0.75, 0.6).lerp(Color(0.8, 0.3, 0.3), k * 0.4))
			_collide(bd, xf, Vector3(2.4, 0.9, 0.8))
		"generator":
			_b(bd, xf, Vector3(0, 0.15, 0), Vector3(1.7, 0.3, 1.0), Color(0.2, 0.2, 0.2))
			_b(bd, xf, Vector3(0, 0.75, 0), Vector3(1.5, 0.9, 0.85), Color(0.75, 0.6, 0.15))
			_b(bd, xf, Vector3(0.45, 1.3, 0), Vector3(0.12, 0.2, 0.12), Color(0.15, 0.15, 0.15))
			_b(bd, xf, Vector3(-0.4, 0.85, 0.43), Vector3(0.4, 0.3, 0.02), Color(0.12, 0.12, 0.12))
			_collide(bd, xf, Vector3(1.7, 1.2, 1.0))
