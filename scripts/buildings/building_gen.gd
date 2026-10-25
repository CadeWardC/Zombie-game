class_name BuildingGen
extends RefCounted
## Generates a building for a lot. Lot-local space: origin at the lot centre
## on the ground-floor level, +Z toward the street (front).
## Thread-safe: reads WorldGen (for ground heights) and writes BuildingData.

const STOREY := 2.8
const SIDINGS := [Color(0.9, 0.89, 0.84), Color(0.82, 0.77, 0.64), Color(0.86, 0.82, 0.58), Color(0.62, 0.7, 0.76),
	Color(0.6, 0.62, 0.6), Color(0.6, 0.66, 0.54), Color(0.55, 0.3, 0.25), Color(0.78, 0.7, 0.6)]
const ROOFS := [Color(0.25, 0.25, 0.27), Color(0.33, 0.24, 0.19), Color(0.16, 0.16, 0.17), Color(0.28, 0.32, 0.26), Color(0.42, 0.22, 0.18)]
const DOORS := [Color(0.55, 0.12, 0.1), Color(0.15, 0.22, 0.38), Color(0.1, 0.1, 0.1), Color(0.88, 0.88, 0.85), Color(0.25, 0.35, 0.25)]
const BRICK := Color(0.55, 0.3, 0.24)
const CONCRETE := Color(0.62, 0.61, 0.58)
const INTERIOR_WALL := Color(0.86, 0.83, 0.76)
const FLOOR_WOOD := Color(0.52, 0.38, 0.26)
const FLOOR_TILE := Color(0.7, 0.7, 0.68)
const CEILING := Color(0.9, 0.9, 0.88)
const SIGNS := {
	"pharmacy": "PHARMACY", "hardware": "HARDWARE", "grocery": "GROCERY", "diner": "DINER", "bar": "BAR",
	"post_office": "POST OFFICE", "gun_store": "GUNS & AMMO", "general_store": "GENERAL STORE",
	"police": "POLICE", "fire_station": "FIRE DEPT", "school": "SCHOOL", "city_hall": "CITY HALL",
	"hospital": "HOSPITAL", "mall": "MALL", "supermarket": "SUPERMARKET", "fast_food": "BURGERS",
	"car_dealer": "AUTO SALES", "motel": "MOTEL", "gas_station": "GAS", "gas_station_store": "GAS & GO",
	"terminal": "TERMINAL", "research_lab": "NOVAGEN RESEARCH",
}
const SHOP_NAMES := ["BOOKS", "BAKERY", "LAUNDRY", "BARBER", "THRIFT", "ELECTRONICS", "SHOES", "FLORIST", "PIZZA", "VIDEO", "TOYS", "CAFE"]

var bd := BuildingData.new()
var lot: Dictionary
var rng := RandomNumberGenerator.new()
var _gen: WorldGen
var _xf: Transform3D # Lot-local -> world.


static func build(gen: WorldGen, p_lot: Dictionary, with_interior: bool) -> BuildingData:
	var b := BuildingGen.new()
	b._gen = gen
	b.lot = p_lot
	b.bd.interior = with_interior
	b.bd.id = p_lot.id
	b.rng.seed = p_lot.seed
	var c: Vector2 = p_lot.center
	b._xf = Transform3D(Basis(Vector3.UP, p_lot.yaw), Vector3(c.x, p_lot.floor, c.y))
	b._dispatch()
	# Loot depends on the building as well as the container.
	for ct in b.bd.containers:
		ct.bld = p_lot.type
	return b.bd


## Ground height below a lot-local point, relative to the floor (negative).
func ground(local: Vector2) -> float:
	var w := _xf * Vector3(local.x, 0, local.y)
	return _gen.height(w.x, w.z) - lot.floor


func _id() -> String:
	return lot.id


func _dispatch() -> void:
	match lot.type:
		"ranch", "colonial", "bungalow", "farmhouse", "duplex":
			_house(lot.type)
		"trailer":
			_trailer()
		"shop", "diner", "pharmacy", "hardware", "grocery", "bar", "post_office", "gun_store", "general_store", "fast_food":
			_shop(lot.type)
		"apartments_small":
			_tower(3, BRICK, false)
		"apartments":
			_tower(rng.randi_range(5, 7), [BRICK, CONCRETE, Color(0.7, 0.66, 0.58)][rng.randi() % 3], false)
		"office_tower":
			_tower(rng.randi_range(8, 15), Color(0.5, 0.56, 0.6), true)
		"police", "fire_station", "city_hall", "post":
			_civic(lot.type)
		"school":
			_school()
		"church":
			_church()
		"hospital":
			_tower(4, Color(0.85, 0.85, 0.82), false, "hospital")
		"mall", "supermarket", "warehouse", "car_dealer", "hangar", "terminal":
			_big_box(lot.type)
		"motel":
			_motel()
		"gas_station":
			_gas_station_lot()
		"gas_station_store":
			_shop("gas_station_store")
		"gas_canopy":
			_canopy(Vector2.ZERO, lot.w, lot.d)
		"control_tower":
			_control_tower()
		"research_lab":
			_research_lab()
		"guard_booth":
			_small_hut(lot.w, lot.d, Color(0.85, 0.85, 0.82), true)
		"trader_hut":
			_small_hut(lot.w, lot.d, Color(0.55, 0.42, 0.3), true)
		"generator_shed":
			_small_hut(lot.w, lot.d, Color(0.5, 0.52, 0.5), false)
		_:
			_house("ranch")


# --- Houses ------------------------------------------------------------------

func _house(style: String) -> void:
	var floors := 2 if style in ["colonial", "farmhouse"] else 1
	var W: float
	var D: float
	match style:
		"ranch": W = rng.randf_range(12.0, 15.0); D = rng.randf_range(8.5, 10.0)
		"colonial": W = rng.randf_range(10.0, 12.5); D = rng.randf_range(8.0, 9.5)
		"bungalow": W = rng.randf_range(8.0, 10.0); D = rng.randf_range(9.0, 11.0)
		"farmhouse": W = rng.randf_range(10.0, 12.5); D = rng.randf_range(9.0, 10.5)
		_: W = rng.randf_range(13.0, 15.5); D = rng.randf_range(8.5, 9.5)
	var has_garage: bool = style in ["ranch", "colonial"] and lot.w >= W + 8.0 and rng.randf() < 0.75
	var max_w: float = lot.w - (8.5 if has_garage else 3.0)
	W = minf(W, max_w)
	D = minf(D, lot.d - 13.0)
	var setback := rng.randf_range(6.0, 8.0)
	var zf: float = lot.d * 0.5 - setback
	var shift := -3.2 if has_garage else 0.0
	var r := Rect2(-W * 0.5 + shift, zf - D, W, D)
	var siding: Color = SIDINGS[rng.randi() % SIDINGS.size()]
	var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
	var door_col: Color = DOORS[rng.randi() % DOORS.size()]
	var id := _id()

	# Foundation (visible on slopes) and floors.
	var lowest := minf(minf(ground(r.position), ground(r.end)), minf(ground(Vector2(r.position.x, r.end.y)), ground(Vector2(r.end.x, r.position.y))))
	var found_h := 0.3 - lowest
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(r.get_center().x, 0.0 - found_h * 0.5, r.get_center().y)), Vector3(W, found_h, D), CONCRETE.darkened(0.15))

	# Floor plan. Two-storey houses use a centre hall with the stairs.
	var hall := Rect2()
	var plans: Array = []
	if floors == 2:
		hall = Rect2(r.get_center().x - 1.1, r.position.y, 2.2, D)
		for f in floors:
			var left := Rect2(r.position.x, r.position.y, hall.position.x - r.position.x, D)
			var right := Rect2(hall.end.x, r.position.y, r.end.x - hall.end.x, D)
			var rooms: Array[Rect2] = []
			var walls: Array = []
			for side in [left, right]:
				var zc: float = side.position.y + D * rng.randf_range(0.45, 0.55)
				rooms.append(Rect2(side.position.x, zc, side.size.x, side.end.y - zc)) # front
				rooms.append(Rect2(side.position.x, side.position.y, side.size.x, zc - side.position.y)) # back
				walls.append([Vector2(side.position.x, zc), Vector2(side.end.x, zc)])
			walls.append([Vector2(hall.position.x, r.position.y), Vector2(hall.position.x, r.end.y)])
			walls.append([Vector2(hall.end.x, r.position.y), Vector2(hall.end.x, r.end.y)])
			var types: Array = ["living", "dining", "office", "kitchen"] if f == 0 else ["bedroom", "bathroom", "bedroom", "bedroom"]
			plans.append({"rooms": rooms, "walls": walls, "types": types})
	else:
		var count := 5 if W * D > 110.0 else 4
		var plan := Interiors.split(r, count, rng)
		var rooms: Array = plan.rooms
		rooms.sort_custom(func(a, b): return a.get_area() > b.get_area())
		var types: Array = []
		for k in rooms.size():
			types.append("bedroom")
		# The largest front room is the living room; the smallest a bathroom.
		var best_front := 0
		for k in rooms.size():
			if rooms[k].end.y > rooms[best_front].end.y - 0.1 and rooms[k].get_area() > rooms[best_front].get_area() * 0.7:
				best_front = k
				break
		types[best_front] = "living"
		types[rooms.size() - 1] = "bathroom"
		for k in rooms.size():
			if types[k] == "bedroom":
				types[k] = "kitchen"
				break
		plan.rooms = rooms
		plan.types = types
		plans.append(plan)

	# Front door: in the hall, or in the living room.
	var door_x := r.get_center().x
	if floors == 1:
		var living: Rect2 = plans[0].rooms[plans[0].types.find("living")]
		if living.end.y > zf - 0.2:
			door_x = living.get_center().x + rng.randf_range(-0.5, 0.5)
	var door_points: Array[Vector2] = [Vector2(door_x, zf)]

	for f in floors:
		var y0 := f * STOREY
		var front_ops := _window_row(r.size.x, door_x - r.position.x if f == 0 else -100.0, 1.0)
		BuildingParts.wall(bd, Vector2(r.position.x, zf), Vector2(r.end.x, zf), y0, STOREY, siding, INTERIOR_WALL, Vector2(0, 1), front_ops, BuildingParts.WALL_T, door_col, id)
		var back_door := r.get_center().x + W * 0.25 if f == 0 else -100.0
		BuildingParts.wall(bd, Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), y0, STOREY, siding, INTERIOR_WALL, Vector2(0, -1),
				_window_row(r.size.x, back_door - r.position.x, 1.0), BuildingParts.WALL_T, door_col.darkened(0.2), id)
		BuildingParts.wall(bd, Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), y0, STOREY, siding, INTERIOR_WALL, Vector2(-1, 0), _window_row(D, -100.0, 1.0))
		BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), y0, STOREY, siding, INTERIOR_WALL, Vector2(1, 0), _window_row(D, -100.0, 1.0))
		if f == 0:
			door_points.append(Vector2(back_door, r.position.y))
		# Floor and ceiling.
		var stair_hole := Rect2()
		if floors == 2 and f == 1:
			stair_hole = Rect2(hall.position.x + 0.1, r.position.y + 1.0, 1.1, 4.4)
		BuildingParts.slab(bd, r, y0 + 0.02, 0.1, FLOOR_WOOD, CEILING, stair_hole)
		if bd.interior:
			var plan: Dictionary = plans[f]
			var spots := Interiors.build_walls(bd, plan.walls, y0, STOREY, INTERIOR_WALL, id)
			spots.append_array(door_points)
			for k in plan.rooms.size():
				var type: String = plan.types[k]
				Interiors.furnish(bd, plan.rooms[k], type, y0 + 0.07, spots, rng, id + "_%d_%d" % [f, k])
	if floors == 2 and bd.interior:
		BuildingParts.stairs(bd, Vector2(hall.position.x + 0.1, r.position.y + 1.0), 1.0, STOREY)
	# Some houses still have someone home.
	var h := absi(("%s_z" % id).hash())
	if bd.interior and h % 100 < 35:
		var rooms: Array = plans[0].rooms
		var room: Rect2 = rooms[h % rooms.size()]
		bd.spawns.append({"pos": Vector3(room.get_center().x + 0.4, 0.1, room.get_center().y + 0.4), "id": id + "_z0",
			"kind": "crawler" if h % 5 == 0 else ""})
	var top := floors * STOREY
	BuildingParts.slab(bd, r, top, 0.12, CEILING, CEILING)
	var rise := rng.randf_range(1.6, 2.4)
	if style == "ranch" and rng.randf() < 0.5:
		BuildingParts.hip_roof(bd, r, top, rise * 0.8, 0.5, roof)
	else:
		BuildingParts.gable_roof(bd, r, top, rise, 0.45, roof, siding, style != "bungalow")
	if rng.randf() < 0.6:
		var cx := r.position.x + 1.0 if rng.randf() < 0.5 else r.end.x - 1.0
		bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(cx, top + rise * 0.6, r.get_center().y)), Vector3(0.7, rise * 1.4, 0.7), BRICK)

	if style in ["bungalow", "farmhouse"]:
		BuildingParts.porch(bd, Rect2(r.position.x, r.position.y, W, D), 2.4, STOREY - 0.1, Color(0.5, 0.42, 0.34), BuildingParts.TRIM, roof)
		BuildingParts.front_steps(bd, Vector2(door_x, zf + 2.4), Vector2(0, 1), 1.6, -ground(Vector2(door_x, zf + 3.0)))
	else:
		BuildingParts.front_steps(bd, Vector2(door_x, zf), Vector2(0, 1), 1.4, -ground(Vector2(door_x, zf + 1.2)))
	BuildingParts.front_steps(bd, Vector2(back_door_x(r, W), r.position.y), Vector2(0, -1), 1.2, -ground(Vector2(back_door_x(r, W), r.position.y - 1.0)))

	if has_garage:
		_garage(Rect2(r.end.x, zf - 7.0, 6.2, 7.0), siding, roof)
	_yard(r, zf, has_garage)


func back_door_x(r: Rect2, W: float) -> float:
	return r.get_center().x + W * 0.25


## Evenly spaced windows along a facade, with a door at `door_at` (metres
## from the wall start; negative for none).
func _window_row(length: float, door_at: float, bottom: float, w := 1.1, h := 1.3) -> Array:
	var ops := []
	if door_at >= 0.0:
		ops.append({"at": door_at, "w": BuildingParts.DOOR_W, "bottom": 0.0, "top": BuildingParts.DOOR_H, "kind": "door"})
	var count := int((length - 1.5) / 2.8)
	for k in count:
		var at := (k + 0.5) * length / count
		if door_at >= 0.0 and absf(at - door_at) < 1.5:
			continue
		ops.append({"at": at, "w": w, "bottom": bottom, "top": bottom + h, "kind": "window"})
	return ops


func _garage(r: Rect2, siding: Color, roof: Color) -> void:
	var h := 2.7
	var id := _id() + "g"
	BuildingParts.wall(bd, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), 0.0, h, siding, INTERIOR_WALL, Vector2(0, 1),
			[{"at": r.size.x * 0.5, "w": 4.6, "bottom": 0.0, "top": 2.2, "kind": "garage"}])
	BuildingParts.wall(bd, r.position, Vector2(r.end.x, r.position.y), 0.0, h, siding, INTERIOR_WALL, Vector2(0, -1))
	BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), r.end, 0.0, h, siding, INTERIOR_WALL, Vector2(1, 0),
			[{"at": 2.0, "w": BuildingParts.DOOR_W, "bottom": 0.0, "top": BuildingParts.DOOR_H, "kind": "door"}], BuildingParts.WALL_T, Color(0.4, 0.4, 0.42), id)
	BuildingParts.slab(bd, r, 0.02, 0.1, CONCRETE, CONCRETE)
	BuildingParts.slab(bd, r, h, 0.1, CEILING, CEILING)
	BuildingParts.gable_roof(bd, r, h, 1.0, 0.3, roof, siding, true)
	if bd.interior:
		Interiors.furnish(bd, r, "garage", 0.07, [Vector2(r.get_center().x, r.end.y), Vector2(r.end.x, r.position.y + 2.0)], rng, id)
	# Driveway.
	var dz0 := r.end.y
	var dz1: float = lot.d * 0.5
	var dx := r.get_center().x
	var gy := ground(Vector2(dx, (dz0 + dz1) * 0.5))
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(dx, gy + 0.04, (dz0 + dz1) * 0.5)), Vector3(4.0, 0.1, dz1 - dz0), CONCRETE)
	if rng.randf() < 0.5:
		bd.props.append({"type": "car", "xf": Transform3D(Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)), Vector3(dx, gy + 0.08, dz0 + 3.2))})


func _yard(r: Rect2, zf: float, has_garage: bool) -> void:
	var front: float = lot.d * 0.5
	var mx: float = lot.w * 0.5 - 1.0
	var mail_x := (r.end.x + 3.1) if has_garage else (r.get_center().x + 2.0)
	bd.props.append({"type": "mailbox", "xf": Transform3D(Basis.IDENTITY, Vector3(clampf(mail_x - 2.4, -mx, mx), ground(Vector2(mail_x - 2.4, front - 0.6)), front - 0.6))})
	if not has_garage and rng.randf() < 0.35:
		var gy := ground(Vector2(r.end.x + 1.8, front - 3.0))
		bd.props.append({"type": "car", "xf": Transform3D(Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)), Vector3(minf(r.end.x + 1.8, mx - 1.0), gy + 0.05, front - 3.5))})
	for k in rng.randi_range(0, 2):
		var p := Vector2(rng.randf_range(-mx, mx), rng.randf_range(-lot.d * 0.5 + 2.0, r.position.y - 2.0))
		if p.y < r.position.y - 1.5:
			bd.props.append({"type": "yard_tree", "xf": Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, ground(p) - 0.1, p.y))})
	# A bicycle leaning by the front of some houses.
	if absi(("%s_bike" % _id()).hash()) % 100 < 18:
		var bp := Vector2(r.position.x - 0.8, zf - 1.2)
		bd.props.append({"type": "bicycle", "xf": Transform3D(Basis.IDENTITY, Vector3(bp.x, ground(bp) + 0.02, bp.y))})
	if rng.randf() < 0.45:
		# Picket fence around the back yard.
		var zb: float = -lot.d * 0.5 + 0.4
		var fence_col := Color(0.85, 0.84, 0.8) if rng.randf() < 0.6 else Color(0.45, 0.35, 0.25)
		for seg in [[Vector2(-mx, zb), Vector2(mx, zb)], [Vector2(-mx, zb), Vector2(-mx, r.position.y)], [Vector2(mx, zb), Vector2(mx, r.position.y)]]:
			_fence(seg[0], seg[1], fence_col)


func _fence(a: Vector2, b: Vector2, col: Color) -> void:
	var length := a.distance_to(b)
	var steps := maxi(1, int(length / 2.5))
	for k in steps:
		var p0 := a.lerp(b, float(k) / steps)
		var p1 := a.lerp(b, float(k + 1) / steps)
		var mid := (p0 + p1) * 0.5
		var gy := ground(mid)
		var yaw := atan2(p1.x - p0.x, p1.y - p0.y)
		var basis := Basis(Vector3.UP, yaw)
		bd.ext.box(Transform3D(basis, Vector3(mid.x, gy + 0.55, mid.y)), Vector3(0.05, 0.1, p0.distance_to(p1)), col)
		bd.ext.box(Transform3D(basis, Vector3(mid.x, gy + 0.25, mid.y)), Vector3(0.05, 0.1, p0.distance_to(p1)), col)
		bd.ext.box(Transform3D(basis, Vector3(p0.x, gy + 0.45, p0.y)), Vector3(0.1, 0.9, 0.1), col)
		bd.boxes.append([Transform3D(basis, Vector3(mid.x, gy + 0.45, mid.y)), Vector3(0.1, 0.9, p0.distance_to(p1))])


func _trailer() -> void:
	var W := 4.4
	var D := rng.randf_range(14.0, 18.0)
	# Trailers sit sideways to the street: long side faces it.
	var r := Rect2(-D * 0.5, lot.d * 0.5 - 8.0 - W, D, W)
	var siding: Color = [Color(0.85, 0.85, 0.8), Color(0.75, 0.78, 0.7), Color(0.7, 0.75, 0.8)][rng.randi() % 3]
	var id := _id()
	var floor_y := 0.5
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(r.get_center().x, floor_y * 0.5 - 0.3, r.get_center().y)), Vector3(D - 0.4, floor_y + 0.6, W - 0.4), Color(0.4, 0.4, 0.4))
	var door_at := D * 0.3
	BuildingParts.wall(bd, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), floor_y, 2.3, siding, INTERIOR_WALL, Vector2(0, 1),
			_window_row(D, door_at, 0.9, 1.0, 0.9), 0.12, Color(0.5, 0.5, 0.5), id)
	BuildingParts.wall(bd, r.position, Vector2(r.end.x, r.position.y), floor_y, 2.3, siding, INTERIOR_WALL, Vector2(0, -1), _window_row(D, -1.0, 0.9, 1.0, 0.9), 0.12)
	BuildingParts.wall(bd, r.position, Vector2(r.position.x, r.end.y), floor_y, 2.3, siding, INTERIOR_WALL, Vector2(-1, 0), [], 0.12)
	BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), r.end, floor_y, 2.3, siding, INTERIOR_WALL, Vector2(1, 0), [], 0.12)
	BuildingParts.slab(bd, r, floor_y + 0.02, 0.1, Color(0.5, 0.45, 0.38), CEILING)
	BuildingParts.slab(bd, r, floor_y + 2.3, 0.15, CEILING, siding.darkened(0.1))
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(r.get_center().x, floor_y + 2.45, r.get_center().y)), Vector3(D, 0.08, W + 0.2), siding.darkened(0.2))
	BuildingParts.front_steps(bd, Vector2(r.position.x + door_at, r.end.y), Vector2(0, 1), 1.2, floor_y - ground(Vector2(r.position.x + door_at, r.end.y + 1.0)))
	if bd.interior:
		var split_x := r.position.x + D * 0.55
		var spots := Interiors.build_walls(bd, [[Vector2(split_x, r.position.y), Vector2(split_x, r.end.y)]], floor_y, 2.3, INTERIOR_WALL, id)
		spots.append(Vector2(r.position.x + door_at, r.end.y))
		Interiors.furnish(bd, Rect2(r.position, Vector2(split_x - r.position.x, W)), "kitchen", floor_y + 0.07, spots, rng, id + "a")
		Interiors.furnish(bd, Rect2(Vector2(split_x, r.position.y), Vector2(r.end.x - split_x, W)), "bedroom", floor_y + 0.07, spots, rng, id + "b")
	_yard(Rect2(r.position.x, r.position.y, D, W), r.end.y, false)


# --- Commercial --------------------------------------------------------------

func _shop(type: String) -> void:
	var W: float = minf(lot.w - 1.0, 24.0)
	var D: float = minf(lot.d - 3.0, 20.0)
	var two_storey: bool = type == "shop" and rng.randf() < 0.4
	var H := 4.2
	var zf: float = lot.d * 0.5 - 0.4
	if type in ["gas_station_store", "fast_food"]:
		zf = lot.d * 0.5 - 0.5
	var r := Rect2(-W * 0.5, zf - D, W, D)
	var wall_col: Color = [BRICK, Color(0.72, 0.68, 0.6), Color(0.6, 0.55, 0.5), Color(0.5, 0.52, 0.55), Color(0.78, 0.74, 0.66)][rng.randi() % 5]
	var accent := Color.from_hsv(rng.randf(), 0.55, 0.6)
	var id := _id()
	BuildingParts.slab(bd, r, 0.02, 0.15, FLOOR_TILE, CEILING)
	var lowest := minf(ground(r.position), ground(Vector2(r.end.x, r.end.y)))
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, -0.5 * (0.2 - lowest), r.get_center().y)), Vector3(W, 0.2 - lowest, D), CONCRETE.darkened(0.2))
	# Storefront: big windows either side of a glass door.
	var front_ops := [{"at": W * 0.5, "w": 1.6, "bottom": 0.0, "top": 2.4, "kind": "door"}]
	var pane_w := (W - 2.8) * 0.5 - 0.8
	if pane_w > 1.0:
		front_ops.append({"at": W * 0.25 - 0.3, "w": pane_w, "bottom": 0.5, "top": 2.9, "kind": "window"})
		front_ops.append({"at": W * 0.75 + 0.3, "w": pane_w, "bottom": 0.5, "top": 2.9, "kind": "window"})
	BuildingParts.wall(bd, Vector2(r.position.x, zf), Vector2(r.end.x, zf), 0.0, H, wall_col, INTERIOR_WALL, Vector2(0, 1), front_ops, 0.25, Color(0.3, 0.3, 0.32), id)
	BuildingParts.wall(bd, r.position, Vector2(r.end.x, r.position.y), 0.0, H, wall_col, INTERIOR_WALL, Vector2(0, -1),
			[{"at": W * 0.8, "w": BuildingParts.DOOR_W, "bottom": 0.0, "top": BuildingParts.DOOR_H, "kind": "door"}], 0.25, Color(0.35, 0.35, 0.36), id)
	BuildingParts.wall(bd, r.position, Vector2(r.position.x, zf), 0.0, H, wall_col, INTERIOR_WALL, Vector2(-1, 0), [], 0.25)
	BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), Vector2(r.end.x, zf), 0.0, H, wall_col, INTERIOR_WALL, Vector2(1, 0), [], 0.25)
	var top := H
	if two_storey:
		BuildingParts.slab(bd, r, H, 0.2, FLOOR_WOOD, CEILING)
		for side in [[Vector2(r.position.x, zf), Vector2(r.end.x, zf), Vector2(0, 1)], [r.position, Vector2(r.end.x, r.position.y), Vector2(0, -1)],
				[r.position, Vector2(r.position.x, zf), Vector2(-1, 0)], [Vector2(r.end.x, r.position.y), Vector2(r.end.x, zf), Vector2(1, 0)]]:
			var len: float = side[0].distance_to(side[1])
			BuildingParts.wall(bd, side[0], side[1], H, STOREY, wall_col, INTERIOR_WALL, side[2], _window_row(len, -1.0, 1.0) if side[2].y != 0 else [], 0.25)
		top = H + STOREY
	BuildingParts.flat_roof(bd, r, top, Color(0.3, 0.3, 0.3), 0.7, wall_col.darkened(0.1))
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(r.position.x + 3.0, top + 0.8, r.get_center().y)), Vector3(1.6, 1.0, 1.2), Color(0.6, 0.6, 0.6))
	# Sign band and awning.
	var text: String = SIGNS.get(type, SHOP_NAMES[rng.randi() % SHOP_NAMES.size()])
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.55, zf + 0.2)), Vector3(W - 0.4, 0.9, 0.15), accent)
	bd.signs.append({"xf": Transform3D(Basis.IDENTITY, Vector3(0, 3.55, zf + 0.3)), "text": text, "size": 0.7, "color": Color(0.95, 0.93, 0.85)})
	var aw := Vector3(W - 1.0, 0.0, 1.4)
	var a0 := Vector3(-aw.x * 0.5, 3.0, zf + 0.15)
	var a1 := Vector3(aw.x * 0.5, 3.0, zf + 0.15)
	bd.ext.quad(a0, a1, a1 + Vector3(0, -0.5, 1.4), a0 + Vector3(0, -0.5, 1.4), accent.darkened(0.15), Vector3(0, 1, 0.3))
	bd.ext.quad(a0, a1, a1 + Vector3(0, -0.5, 1.4), a0 + Vector3(0, -0.5, 1.4), accent.darkened(0.5), Vector3(0, -1, -0.3))
	BuildingParts.front_steps(bd, Vector2(0, zf), Vector2(0, 1), 2.0, -ground(Vector2(0, zf + 1.0)))
	if bd.interior:
		var back_z := r.position.y + 4.0
		var spots := Interiors.build_walls(bd, [[Vector2(r.position.x, back_z), Vector2(r.end.x, back_z)]], 0.0, H, INTERIOR_WALL, id)
		spots.append(Vector2(0, zf))
		spots.append(Vector2(r.position.x + W * 0.8, r.position.y))
		var main := Rect2(r.position.x, back_z, W, zf - back_z)
		_shop_fixtures(type, main, spots)
		Interiors.furnish(bd, Rect2(r.position.x, r.position.y, W, 4.0), "garage", 0.1, spots, rng, id + "_back")


func _shop_fixtures(type: String, room: Rect2, doors: Array[Vector2]) -> void:
	var id := _id()
	var inner := room.grow(-0.4)
	# Counter near the entrance.
	Furniture.place(bd, "shop_counter", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(inner.position.x + 0.5, 0.1, inner.end.y - 2.6)), rng, id)
	match type:
		"diner", "bar", "fast_food":
			for k in int(inner.size.x / 2.8):
				for j in 2:
					var c := Vector3(inner.position.x + 2.2 + k * 2.8, 0.1, inner.position.y + 1.5 + j * 2.4)
					if c.x < inner.end.x - 1.0:
						Furniture.place(bd, "dining_set", Transform3D(Basis(Vector3.UP, PI * 0.5), c), rng, id)
			Furniture.place(bd, "fridge", Transform3D(Basis.IDENTITY, Vector3(inner.end.x - 0.6, 0.1, inner.position.y + 0.4)), rng, id)
		_:
			# Aisles of shelving.
			var rows := int((inner.size.y - 3.0) / 2.2)
			for j in rows:
				var z := inner.position.y + 1.2 + j * 2.2
				var x := inner.position.x + 2.5
				while x < inner.end.x - 1.6:
					Furniture.place(bd, "store_shelf", Transform3D(Basis.IDENTITY, Vector3(x, 0.1, z)), rng, id)
					x += 2.6
	if type == "pharmacy":
		Furniture.place(bd, "medical_cabinet", Transform3D(Basis.IDENTITY, Vector3(inner.end.x - 0.6, 0.1, inner.position.y + 0.3)), rng, id)
	elif type == "gun_store":
		Furniture.place(bd, "locker", Transform3D(Basis.IDENTITY, Vector3(inner.end.x - 0.6, 0.1, inner.position.y + 0.3)), rng, id)


func _civic(type: String) -> void:
	var W: float = minf(lot.w - 3.0, 26.0)
	var D: float = minf(lot.d - 8.0, 16.0)
	var floors := 2
	var zf: float = lot.d * 0.5 - 5.0
	var r := Rect2(-W * 0.5, zf - D, W, D)
	var col := BRICK if type != "city_hall" else Color(0.82, 0.8, 0.74)
	if type == "fire_station":
		col = Color(0.65, 0.25, 0.2)
	var id := _id()
	BuildingParts.slab(bd, r, 0.02, 0.4, FLOOR_TILE, CEILING)
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, -0.6, r.get_center().y)), Vector3(W, 1.2, D), CONCRETE.darkened(0.1))
	for f in floors:
		var y0 := f * 3.4
		var front_ops: Array
		if type == "fire_station" and f == 0:
			front_ops = [{"at": W * 0.25, "w": 4.2, "bottom": 0.0, "top": 3.6, "kind": "garage"},
					{"at": W * 0.55, "w": 4.2, "bottom": 0.0, "top": 3.6, "kind": "garage"},
					{"at": W * 0.85, "w": BuildingParts.DOOR_W, "bottom": 0.0, "top": BuildingParts.DOOR_H, "kind": "door"}]
		else:
			front_ops = _window_row(W, W * 0.5 if f == 0 else -1.0, 1.0, 1.3, 1.6)
			if f == 0:
				front_ops[0].w = 1.8
		BuildingParts.wall(bd, Vector2(r.position.x, zf), Vector2(r.end.x, zf), y0, 3.4, col, INTERIOR_WALL, Vector2(0, 1), front_ops, 0.3, Color(0.3, 0.25, 0.2), id)
		BuildingParts.wall(bd, r.position, Vector2(r.end.x, r.position.y), y0, 3.4, col, INTERIOR_WALL, Vector2(0, -1), _window_row(W, -1.0, 1.0, 1.3, 1.6), 0.3)
		BuildingParts.wall(bd, r.position, Vector2(r.position.x, zf), y0, 3.4, col, INTERIOR_WALL, Vector2(-1, 0), _window_row(D, -1.0, 1.0, 1.3, 1.6), 0.3)
		BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), Vector2(r.end.x, zf), y0, 3.4, col, INTERIOR_WALL, Vector2(1, 0), _window_row(D, -1.0, 1.0, 1.3, 1.6), 0.3)
		if f > 0:
			BuildingParts.slab(bd, r, y0, 0.25, FLOOR_TILE, CEILING)
	BuildingParts.flat_roof(bd, r, floors * 3.4, Color(0.32, 0.32, 0.32), 0.8, col.darkened(0.1))
	var text: String = SIGNS.get(type, "")
	bd.signs.append({"xf": Transform3D(Basis.IDENTITY, Vector3(0, 3.0, zf + 0.2)), "text": text, "size": 0.9, "color": Color(0.95, 0.95, 0.9)})
	if type == "city_hall":
		for k in 6:
			var x := lerpf(-W * 0.35, W * 0.35, k / 5.0)
			bd.ext.cylinder(Vector3(x, 0.0, zf + 2.2), 0.35, 0.32, 6.4, 8, Color(0.9, 0.89, 0.85))
			bd.boxes.append([Transform3D(Basis.IDENTITY, Vector3(x, 3.2, zf + 2.2)), Vector3(0.7, 6.4, 0.7)])
		bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, 6.6, zf + 1.6)), Vector3(W * 0.8, 0.5, 3.6), Color(0.88, 0.87, 0.83))
	# Flag pole.
	bd.ext.cylinder(Vector3(W * 0.5 + 1.5, -0.3, zf + 3.5), 0.06, 0.04, 8.0, 5, Color(0.8, 0.8, 0.8))
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(W * 0.5 + 2.1, 7.2, zf + 3.5)), Vector3(1.1, 0.7, 0.02), Color(0.7, 0.15, 0.15))
	BuildingParts.front_steps(bd, Vector2(0, zf), Vector2(0, 1), 3.0, -ground(Vector2(0, zf + 1.5)))
	if bd.interior:
		var spots: Array[Vector2] = [Vector2(0, zf), Vector2(W * 0.85 - W * 0.5, zf)]
		var plan := Interiors.split(r, 4, rng, 3.5)
		spots.append_array(Interiors.build_walls(bd, plan.walls, 0.0, 3.4, INTERIOR_WALL, id))
		for k in plan.rooms.size():
			var room: Rect2 = plan.rooms[k]
			var kind := "office"
			if type == "police" and k % 2 == 0:
				for j in int(room.size.x / 1.0) - 1:
					Furniture.place(bd, "locker", Transform3D(Basis.IDENTITY, Vector3(room.position.x + 0.8 + j, 0.4, room.position.y + 0.4)), rng, id + "L%d" % k)
				continue
			Interiors.furnish(bd, room, kind, 0.4, spots, rng, id + "_%d" % k)


func _school() -> void:
	var W: float = lot.w - 3.0
	var D: float = minf(lot.d - 8.0, 14.0)
	var zf: float = lot.d * 0.5 - 5.0
	var r := Rect2(-W * 0.5, zf - D, W, D)
	var col := Color(0.62, 0.38, 0.3)
	var id := _id()
	BuildingParts.slab(bd, r, 0.02, 0.3, FLOOR_TILE, CEILING)
	BuildingParts.wall(bd, Vector2(r.position.x, zf), Vector2(r.end.x, zf), 0.0, 3.6, col, INTERIOR_WALL, Vector2(0, 1), _window_row(W, W * 0.5, 0.9, 1.6, 1.8), 0.3, Color(0.25, 0.35, 0.55), id)
	BuildingParts.wall(bd, r.position, Vector2(r.end.x, r.position.y), 0.0, 3.6, col, INTERIOR_WALL, Vector2(0, -1), _window_row(W, -1.0, 0.9, 1.6, 1.8), 0.3)
	BuildingParts.wall(bd, r.position, Vector2(r.position.x, zf), 0.0, 3.6, col, INTERIOR_WALL, Vector2(-1, 0), [], 0.3)
	BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), Vector2(r.end.x, zf), 0.0, 3.6, col, INTERIOR_WALL, Vector2(1, 0), [], 0.3)
	BuildingParts.flat_roof(bd, r, 3.6, Color(0.3, 0.3, 0.3), 0.6, col.darkened(0.1))
	bd.signs.append({"xf": Transform3D(Basis.IDENTITY, Vector3(0, 3.0, zf + 0.2)), "text": "SCHOOL", "size": 0.9, "color": Color(0.95, 0.95, 0.9)})
	if bd.interior:
		var walls := []
		var rooms: Array[Rect2] = []
		var hall_z := r.position.y + D * 0.4
		walls.append([Vector2(r.position.x, hall_z), Vector2(r.end.x, hall_z)])
		var n := maxi(2, int(W / 8.0))
		for k in range(1, n):
			var x := r.position.x + W * k / n
			walls.append([Vector2(x, r.position.y), Vector2(x, hall_z)])
		for k in n:
			rooms.append(Rect2(r.position.x + W * k / n, r.position.y, W / n, hall_z - r.position.y))
		var spots := Interiors.build_walls(bd, walls, 0.0, 3.6, INTERIOR_WALL, id)
		for k in rooms.size():
			var room := rooms[k]
			for row in int(room.size.y / 1.6) - 1:
				for col_i in int(room.size.x / 1.8) - 1:
					var p := Vector3(room.position.x + 1.2 + col_i * 1.8, 0.1, room.position.y + 1.4 + row * 1.6)
					Furniture.place(bd, "desk", Transform3D(Basis(Vector3.UP, PI), p), rng, id + "_%d" % k)


func _church() -> void:
	var W := 10.0
	var D: float = minf(lot.d - 8.0, 22.0)
	var zf: float = lot.d * 0.5 - 6.0
	var r := Rect2(-W * 0.5, zf - D, W, D)
	var col := Color(0.9, 0.89, 0.85) if rng.randf() < 0.6 else Color(0.62, 0.6, 0.56)
	var roof := Color(0.22, 0.22, 0.25)
	var id := _id()
	BuildingParts.slab(bd, r, 0.02, 0.4, FLOOR_WOOD, CEILING)
	var side_ops := []
	for k in int(D / 3.5):
		side_ops.append({"at": (k + 0.5) * D / int(D / 3.5), "w": 0.9, "bottom": 1.2, "top": 3.8, "kind": "window"})
	BuildingParts.wall(bd, Vector2(r.position.x, zf), Vector2(r.end.x, zf), 0.0, 5.0, col, INTERIOR_WALL, Vector2(0, 1),
			[{"at": W * 0.5, "w": 1.8, "bottom": 0.0, "top": 2.6, "kind": "door"}], 0.3, Color(0.4, 0.22, 0.14), id)
	BuildingParts.wall(bd, r.position, Vector2(r.end.x, r.position.y), 0.0, 5.0, col, INTERIOR_WALL, Vector2(0, -1), [], 0.3)
	BuildingParts.wall(bd, r.position, Vector2(r.position.x, zf), 0.0, 5.0, col, INTERIOR_WALL, Vector2(-1, 0), side_ops, 0.3)
	BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), Vector2(r.end.x, zf), 0.0, 5.0, col, INTERIOR_WALL, Vector2(1, 0), side_ops, 0.3)
	BuildingParts.gable_roof(bd, r, 5.0, 4.0, 0.4, roof, col, false)
	# Steeple.
	var t := Rect2(-1.8, zf - 1.0, 3.6, 3.6)
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, 5.0 + 4.0, zf + 0.8)), Vector3(3.6, 8.0, 3.6), col)
	bd.boxes.append([Transform3D(Basis.IDENTITY, Vector3(0, 9.0, zf + 0.8)), Vector3(3.6, 8.0, 3.6)])
	bd.ext.cylinder(Vector3(0, 13.0, zf + 0.8), 2.0, 0.0, 6.0, 4, roof)
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, 19.5, zf + 0.8)), Vector3(0.12, 1.4, 0.12), Color(0.85, 0.75, 0.3))
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, 19.7, zf + 0.8)), Vector3(0.7, 0.12, 0.12), Color(0.85, 0.75, 0.3))
	BuildingParts.front_steps(bd, Vector2(0, zf), Vector2(0, 1), 3.0, -ground(Vector2(0, zf + 1.5)))
	if bd.interior:
		for k in int((D - 5.0) / 1.2):
			for x: float in [-2.6, 2.6]:
				var z := zf - 3.0 - k * 1.2
				bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.45, z)), Vector3(3.2, 0.08, 0.45), Furniture.WOOD)
				bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.75, z - 0.22)), Vector3(3.2, 0.6, 0.06), Furniture.WOOD)
				bd.boxes.append([Transform3D(Basis.IDENTITY, Vector3(x, 0.45, z)), Vector3(3.2, 0.9, 0.5)])
		bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, r.position.y + 1.5)), Vector3(2.0, 1.0, 0.8), Color(0.85, 0.84, 0.8))
	_graveyard(r)


func _graveyard(r: Rect2) -> void:
	var zb: float = -lot.d * 0.5 + 2.0
	if r.position.y - zb < 3.0:
		return
	for k in rng.randi_range(6, 14):
		var p := Vector2(rng.randf_range(-lot.w * 0.4, lot.w * 0.4), rng.randf_range(zb, r.position.y - 1.5))
		var gy := ground(p)
		bd.ext.box(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.15, 0.15)), Vector3(p.x, gy + 0.4, p.y)), Vector3(0.6, 0.8, 0.15), Color(0.55, 0.55, 0.55))


## Multi-storey block. Ground floor is enterable (a lobby); upper floors are
## a shell with window bands.
func _tower(floors: int, col: Color, glass_tower: bool, special := "") -> void:
	var W: float = minf(lot.w - 3.0, 30.0)
	var D: float = minf(lot.d - 4.0, 30.0)
	var zf: float = lot.d * 0.5 - 1.5
	var r := Rect2(-W * 0.5, zf - D, W, D)
	var fh := 3.3
	var id := _id()
	var dark := Color(0.16, 0.2, 0.24)
	BuildingParts.slab(bd, r, 0.02, 0.4, FLOOR_TILE, CEILING)
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, -0.8, r.get_center().y)), Vector3(W, 1.6, D), CONCRETE.darkened(0.15))
	# Lobby floor with real walls and an entrance.
	var front_ops := _window_row(W, W * 0.5, 0.4, 2.0, 2.4)
	front_ops[0].w = 2.0
	BuildingParts.wall(bd, Vector2(r.position.x, zf), Vector2(r.end.x, zf), 0.0, fh, col, INTERIOR_WALL, Vector2(0, 1), front_ops, 0.3, Color(0.25, 0.25, 0.27), id)
	BuildingParts.wall(bd, r.position, Vector2(r.end.x, r.position.y), 0.0, fh, col, INTERIOR_WALL, Vector2(0, -1), [], 0.3)
	BuildingParts.wall(bd, r.position, Vector2(r.position.x, zf), 0.0, fh, col, INTERIOR_WALL, Vector2(-1, 0), [], 0.3)
	BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), Vector2(r.end.x, zf), 0.0, fh, col, INTERIOR_WALL, Vector2(1, 0), [], 0.3)
	BuildingParts.slab(bd, r, fh, 0.3, CEILING, CEILING)
	# Upper floors: solid shell with window bands (opaque, cheap).
	var shell := Rect2(r.position, r.size)
	var h_up := (floors - 1) * fh
	var cen := Vector3(shell.get_center().x, fh + h_up * 0.5, shell.get_center().y)
	bd.ext.box(Transform3D(Basis.IDENTITY, cen), Vector3(W, h_up, D), col)
	bd.boxes.append([Transform3D(Basis.IDENTITY, cen), Vector3(W, h_up, D)])
	for f in range(1, floors):
		var y := f * fh + 1.6
		var band_h := 2.2 if glass_tower else 1.3
		for side in 4:
			var horizontal := side < 2
			var size := Vector3(W - 0.6, band_h, 0.05) if horizontal else Vector3(0.05, band_h, D - 0.6)
			var off := D * 0.5 + 0.03 if horizontal else W * 0.5 + 0.03
			var pos := Vector3(0, y, shell.get_center().y + (off if side == 0 else -off)) if horizontal else Vector3(off if side == 2 else -off, y, shell.get_center().y)
			if glass_tower:
				bd.ext.box(Transform3D(Basis.IDENTITY, pos), size, dark.lightened(0.1 * (f % 2)))
			else:
				# Individual windows.
				var length := W if horizontal else D
				var count := int(length / 3.2)
				for k in count:
					var t := (k + 0.5) / count - 0.5
					var p := pos + (Vector3(t * length, 0, 0) if horizontal else Vector3(0, 0, t * length))
					bd.ext.box(Transform3D(Basis.IDENTITY, p), Vector3(1.4, band_h, 0.06) if horizontal else Vector3(0.06, band_h, 1.4), dark)
	var top := floors * fh
	BuildingParts.flat_roof(bd, r, top - 0.25, Color(0.3, 0.3, 0.3), 1.0, col.darkened(0.1))
	for k in rng.randi_range(1, 3):
		bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-W * 0.3, W * 0.3), top + 0.8, r.get_center().y + rng.randf_range(-D * 0.3, D * 0.3))), Vector3(2.0, 1.4, 1.6), Color(0.62, 0.62, 0.6))
	if special == "hospital":
		bd.signs.append({"xf": Transform3D(Basis.IDENTITY, Vector3(0, fh + 0.8, zf + 0.12)), "text": "HOSPITAL", "size": 1.4, "color": Color(0.85, 0.1, 0.1)})
		bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.0, zf + 2.5)), Vector3(8.0, 0.3, 5.0), Color(0.85, 0.85, 0.83))
		for x: float in [-3.6, 3.6]:
			bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(x, 1.5, zf + 4.7)), Vector3(0.3, 3.0, 0.3), Color(0.85, 0.85, 0.83))
	BuildingParts.front_steps(bd, Vector2(0, zf), Vector2(0, 1), 2.4, -ground(Vector2(0, zf + 1.2)))
	if bd.interior:
		var lobby := r.grow(-0.4)
		var spots: Array[Vector2] = [Vector2(0, zf)]
		if special == "hospital":
			var plan := Interiors.split(r, 5, rng, 4.0)
			spots.append_array(Interiors.build_walls(bd, plan.walls, 0.0, fh, INTERIOR_WALL, id))
			for k in plan.rooms.size():
				var room: Rect2 = plan.rooms[k]
				var inner := room.grow(-0.6)
				for j in int(inner.size.x / 1.8):
					Furniture.place(bd, "hospital_bed", Transform3D(Basis.IDENTITY, Vector3(inner.position.x + 0.9 + j * 1.8, 0.4, inner.position.y + 1.2)), rng, id + "_%d" % k)
				Furniture.place(bd, "medical_cabinet", Transform3D(Basis(Vector3.UP, PI), Vector3(inner.get_center().x, 0.4, inner.end.y - 0.3)), rng, id + "_m%d" % k)
		else:
			Furniture.place(bd, "shop_counter", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.4, lobby.get_center().y)), rng, id)
			Furniture.place(bd, "couch", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(lobby.position.x + 0.5, 0.4, lobby.end.y - 3.0)), rng, id)
			Furniture.place(bd, "filing_cabinet", Transform3D(Basis.IDENTITY, Vector3(lobby.end.x - 1.0, 0.4, lobby.position.y + 0.4)), rng, id)


func _big_box(type: String) -> void:
	var W: float = lot.w - 4.0
	var D: float = lot.d - 8.0
	var H := 6.0
	if type == "hangar":
		W = lot.w
		D = lot.d
		H = 12.0
	elif type == "terminal":
		W = lot.w
		D = lot.d
		H = 8.0
	var zf: float = lot.d * 0.5 - (8.0 if type in ["mall", "supermarket", "car_dealer"] else 1.0)
	if type in ["hangar", "terminal"]:
		zf = lot.d * 0.5
	var r := Rect2(-W * 0.5, zf - D, W, D)
	var col: Color = {"mall": Color(0.78, 0.74, 0.66), "supermarket": Color(0.82, 0.8, 0.74), "warehouse": Color(0.55, 0.57, 0.58),
			"car_dealer": Color(0.85, 0.85, 0.86), "hangar": Color(0.6, 0.62, 0.62), "terminal": Color(0.82, 0.82, 0.8)}.get(type, CONCRETE)
	var id := _id()
	BuildingParts.slab(bd, r, 0.02, 0.3, FLOOR_TILE if type != "hangar" else CONCRETE, CEILING)
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, -0.8, r.get_center().y)), Vector3(W, 1.6, D), CONCRETE.darkened(0.15))
	var front_ops: Array
	match type:
		"hangar":
			front_ops = [{"at": W * 0.5, "w": W - 6.0, "bottom": 0.0, "top": H - 2.0, "kind": "open"}]
		"warehouse":
			front_ops = [{"at": W * 0.3, "w": 4.0, "bottom": 0.0, "top": 4.0, "kind": "garage"}, {"at": W * 0.6, "w": 4.0, "bottom": 0.0, "top": 4.0, "kind": "garage"},
					{"at": W * 0.85, "w": BuildingParts.DOOR_W, "bottom": 0.0, "top": BuildingParts.DOOR_H, "kind": "door"}]
		_:
			front_ops = [{"at": W * 0.5, "w": 3.0, "bottom": 0.0, "top": 2.6, "kind": "door"}]
			var count := int(W / 6.0)
			for k in count:
				var at := (k + 0.5) * W / count
				if absf(at - W * 0.5) > 3.0:
					front_ops.append({"at": at, "w": 4.0, "bottom": 0.3, "top": 3.4, "kind": "window"})
	BuildingParts.wall(bd, Vector2(r.position.x, zf), Vector2(r.end.x, zf), 0.0, H, col, INTERIOR_WALL, Vector2(0, 1), front_ops, 0.3, Color(0.3, 0.32, 0.34), id)
	BuildingParts.wall(bd, r.position, Vector2(r.end.x, r.position.y), 0.0, H, col, INTERIOR_WALL, Vector2(0, -1),
			[{"at": W * 0.2, "w": BuildingParts.DOOR_W, "bottom": 0.0, "top": BuildingParts.DOOR_H, "kind": "door"}], 0.3, Color(0.35, 0.35, 0.36), id)
	BuildingParts.wall(bd, r.position, Vector2(r.position.x, zf), 0.0, H, col, INTERIOR_WALL, Vector2(-1, 0), [], 0.3)
	BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), Vector2(r.end.x, zf), 0.0, H, col, INTERIOR_WALL, Vector2(1, 0), [], 0.3)
	BuildingParts.flat_roof(bd, r, H, Color(0.32, 0.32, 0.32), 0.8, col.darkened(0.1))
	var text: String = SIGNS.get(type, "")
	if text != "":
		bd.signs.append({"xf": Transform3D(Basis.IDENTITY, Vector3(0, H - 1.0, zf + 0.2)), "text": text, "size": 1.6, "color": Color(0.9, 0.2, 0.15) if type == "supermarket" else Color(0.95, 0.95, 0.9)})
	if type in ["mall", "supermarket", "car_dealer"]:
		# Parking lot in front.
		var pz0 := zf
		var pz1: float = lot.d * 0.5
		var gy := ground(Vector2(0, (pz0 + pz1) * 0.5))
		bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, gy + 0.05, (pz0 + pz1) * 0.5)), Vector3(W, 0.1, pz1 - pz0), Color(0.22, 0.22, 0.23))
		for k in int(W / 3.0):
			bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(-W * 0.5 + 1.5 + k * 3.0, gy + 0.11, (pz0 + pz1) * 0.5)), Vector3(0.1, 0.01, 4.5), Color(0.85, 0.85, 0.8))
			if rng.randf() < 0.35:
				bd.props.append({"type": "car", "xf": Transform3D(Basis(Vector3.UP, rng.randf_range(-0.05, 0.05) + (PI if rng.randf() < 0.5 else 0.0)), Vector3(-W * 0.5 + 3.0 + k * 3.0, gy + 0.1, (pz0 + pz1) * 0.5))})
	if bd.interior:
		var inner := r.grow(-1.5)
		match type:
			"mall", "supermarket":
				var z := inner.position.y + 1.0
				while z < inner.end.y - 5.0:
					var x := inner.position.x + 1.5
					while x < inner.end.x - 1.5:
						Furniture.place(bd, "store_shelf", Transform3D(Basis.IDENTITY, Vector3(x, 0.32, z)), rng, id)
						x += 2.6
					z += 2.6
				Furniture.place(bd, "shop_counter", Transform3D(Basis.IDENTITY, Vector3(-3.0, 0.32, inner.end.y - 2.5)), rng, id)
				Furniture.place(bd, "shop_counter", Transform3D(Basis.IDENTITY, Vector3(3.0, 0.32, inner.end.y - 2.5)), rng, id)
			"warehouse":
				for k in int(inner.size.x / 3.0):
					Furniture.place(bd, "store_shelf", Transform3D(Basis.IDENTITY, Vector3(inner.position.x + 1.5 + k * 3.0, 0.32, inner.position.y + 0.5)), rng, id)
			"terminal":
				for row in int(inner.size.y / 3.0):
					for k in int(inner.size.x / 4.0):
						Furniture.place(bd, "couch", Transform3D(Basis.IDENTITY, Vector3(inner.position.x + 2.0 + k * 4.0, 0.32, inner.position.y + 1.5 + row * 3.0)), rng, id)
				Furniture.place(bd, "shop_counter", Transform3D(Basis.IDENTITY, Vector3(0, 0.32, inner.end.y - 3.0)), rng, id)
			"car_dealer":
				bd.props.append({"type": "car", "xf": Transform3D(Basis(Vector3.UP, 0.6), Vector3(-W * 0.2, 0.35, r.get_center().y))})
				bd.props.append({"type": "car", "xf": Transform3D(Basis(Vector3.UP, -0.6), Vector3(W * 0.2, 0.35, r.get_center().y))})
				Furniture.place(bd, "desk", Transform3D(Basis.IDENTITY, Vector3(0, 0.32, inner.position.y + 0.5)), rng, id)
			"hangar":
				Furniture.place(bd, "store_shelf", Transform3D(Basis.IDENTITY, Vector3(inner.position.x + 2.0, 0.32, inner.position.y + 0.5)), rng, id)
				Furniture.place(bd, "locker", Transform3D(Basis.IDENTITY, Vector3(inner.end.x - 2.0, 0.32, inner.position.y + 0.5)), rng, id)


func _motel() -> void:
	var W: float = lot.w - 4.0
	var D := 9.0
	var zf: float = lot.d * 0.5 - 12.0
	var r := Rect2(-W * 0.5, zf - D, W, D)
	var col := Color(0.86, 0.78, 0.62)
	var id := _id()
	BuildingParts.slab(bd, r, 0.02, 0.3, FLOOR_TILE, CEILING)
	var rooms := int(W / 4.0)
	for f in 2:
		var ops := []
		for k in rooms:
			var at := (k + 0.5) * W / rooms
			ops.append({"at": at - 0.9, "w": BuildingParts.DOOR_W, "bottom": 0.0, "top": BuildingParts.DOOR_H, "kind": "door" if f == 0 else "window"})
			ops.append({"at": at + 0.8, "w": 1.0, "bottom": 1.0, "top": 2.1, "kind": "window"})
		BuildingParts.wall(bd, Vector2(r.position.x, zf), Vector2(r.end.x, zf), f * STOREY, STOREY, col, INTERIOR_WALL, Vector2(0, 1), ops, 0.25, Color(0.5, 0.25, 0.2), id)
		BuildingParts.wall(bd, r.position, Vector2(r.end.x, r.position.y), f * STOREY, STOREY, col, INTERIOR_WALL, Vector2(0, -1), [], 0.25)
		BuildingParts.wall(bd, r.position, Vector2(r.position.x, zf), f * STOREY, STOREY, col, INTERIOR_WALL, Vector2(-1, 0), [], 0.25)
		BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), Vector2(r.end.x, zf), f * STOREY, STOREY, col, INTERIOR_WALL, Vector2(1, 0), [], 0.25)
		if f == 1:
			BuildingParts.slab(bd, r, STOREY, 0.2, FLOOR_TILE, CEILING)
	BuildingParts.flat_roof(bd, r, STOREY * 2, Color(0.32, 0.3, 0.3), 0.5, col.darkened(0.1))
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(r.end.x + 1.5, 4.0, lot.d * 0.5 - 2.0)), Vector3(0.3, 8.0, 0.3), Color(0.5, 0.5, 0.5))
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(r.end.x + 1.5, 7.0, lot.d * 0.5 - 2.0)), Vector3(3.5, 1.6, 0.3), Color(0.75, 0.2, 0.2))
	bd.signs.append({"xf": Transform3D(Basis.IDENTITY, Vector3(r.end.x + 1.5, 7.0, lot.d * 0.5 - 1.8)), "text": "MOTEL", "size": 0.9, "color": Color(0.98, 0.95, 0.8)})
	if bd.interior:
		var walls := []
		for k in range(1, rooms):
			var x := r.position.x + k * W / rooms
			walls.append([Vector2(x, r.position.y), Vector2(x, zf)])
		for w in walls:
			BuildingParts.wall(bd, w[0], w[1], 0.0, STOREY, INTERIOR_WALL, INTERIOR_WALL, Vector2.RIGHT, [], 0.12)
		for k in rooms:
			var room := Rect2(r.position.x + k * W / rooms, r.position.y, W / rooms, D)
			var door := Vector2(room.get_center().x - 0.9, zf)
			var spots: Array[Vector2] = [door]
			Interiors.furnish(bd, room, "bedroom", 0.07, spots, rng, id + "_%d" % k)


func _gas_station_lot() -> void:
	# Store at the back of the lot, canopy with pumps in front.
	_shop("gas_station_store")
	_canopy(Vector2(0, lot.d * 0.5 - 7.0), minf(lot.w - 4.0, 16.0), 8.0)
	for x: float in [-4.0, 0.0, 4.0]:
		bd.props.append({"type": "fuel_pump", "xf": Transform3D(Basis.IDENTITY, Vector3(x, ground(Vector2(x, lot.d * 0.5 - 7.0)), lot.d * 0.5 - 7.0))})


func _canopy(c: Vector2, w: float, d: float) -> void:
	var gy := ground(c)
	var h := 5.0
	for x in [-w * 0.4, w * 0.4]:
		for z in [-d * 0.3, d * 0.3]:
			var p := Vector3(c.x + x, gy + h * 0.5, c.y + z)
			bd.ext.box(Transform3D(Basis.IDENTITY, p), Vector3(0.4, h, 0.4), Color(0.85, 0.85, 0.85))
			bd.boxes.append([Transform3D(Basis.IDENTITY, p), Vector3(0.4, h, 0.4)])
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(c.x, gy + h + 0.4, c.y)), Vector3(w, 0.8, d), Color(0.9, 0.9, 0.9))
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(c.x, gy + h + 0.4, c.y + d * 0.5 + 0.02)), Vector3(w, 0.5, 0.02), Color(0.75, 0.15, 0.12))
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(c.x, gy + 0.08, c.y)), Vector3(w + 2.0, 0.16, d + 3.0), CONCRETE)


func _control_tower() -> void:
	var h := 26.0
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(5.0, h, 5.0), Color(0.82, 0.82, 0.8))
	bd.boxes.append([Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(5.0, h, 5.0)])
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, h + 0.2, 0)), Vector3(9.0, 0.4, 9.0), Color(0.75, 0.75, 0.74))
	for side in 4:
		var a := Vector2.from_angle(side * PI * 0.5) * 4.3
		var p := Vector3(a.x, h + 1.7, a.y)
		bd.glass.box(Transform3D(Basis(Vector3.UP, side * PI * 0.5), p), Vector3(0.05, 2.6, 8.6), BuildingParts.GLASS)
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, h + 3.2, 0)), Vector3(9.4, 0.4, 9.4), Color(0.75, 0.75, 0.74))


func _research_lab() -> void:
	var W: float = lot.w
	var D: float = lot.d
	var zf: float = D * 0.5
	var r := Rect2(-W * 0.5, zf - D, W, D)
	var col := Color(0.74, 0.74, 0.72)
	var id := _id()
	BuildingParts.slab(bd, r, 0.02, 0.3, FLOOR_TILE, CEILING)
	for f in 2:
		var y0 := f * 4.0
		var front_ops := _window_row(W, W * 0.5 if f == 0 else -1.0, 0.6, 2.4, 2.6)
		if f == 0:
			front_ops[0].w = 2.4
		BuildingParts.wall(bd, Vector2(r.position.x, zf), Vector2(r.end.x, zf), y0, 4.0, col, INTERIOR_WALL, Vector2(0, 1), front_ops, 0.35, Color(0.4, 0.42, 0.45), id)
		BuildingParts.wall(bd, r.position, Vector2(r.end.x, r.position.y), y0, 4.0, col, INTERIOR_WALL, Vector2(0, -1), _window_row(W, -1.0, 1.0, 1.6, 1.4), 0.35)
		BuildingParts.wall(bd, r.position, Vector2(r.position.x, zf), y0, 4.0, col, INTERIOR_WALL, Vector2(-1, 0), [], 0.35)
		BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), Vector2(r.end.x, zf), y0, 4.0, col, INTERIOR_WALL, Vector2(1, 0), [], 0.35)
		if f == 1:
			BuildingParts.slab(bd, r, 4.0, 0.3, FLOOR_TILE, CEILING)
	BuildingParts.flat_roof(bd, r, 8.0, Color(0.3, 0.3, 0.3), 0.8, col.darkened(0.1))
	bd.ext.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.6, zf + 2.0)), Vector3(9.0, 0.35, 4.0), Color(0.3, 0.32, 0.35))
	bd.signs.append({"xf": Transform3D(Basis.IDENTITY, Vector3(0, 4.6, zf + 0.2)), "text": SIGNS["research_lab"], "size": 1.1, "color": Color(0.85, 0.9, 0.95)})
	if bd.interior:
		_lab_interior(r, id)


## The lab is a small dungeon. Offices, a lobby, a security room and a
## break room line the front; a corridor runs across; behind it, security
## doors lead to the labs, the containment wing (with the director's office)
## and the vault where the cure is kept. Security doors need the site's
## generator running and a keycard: blue from the security room, red from
## the director's desk (behind a blue door).
func _lab_interior(r: Rect2, id: String) -> void:
	var site: String = id.get_slice("_", 0)
	var wall := func(a: Vector2, b: Vector2, ops: Array, key: String) -> void:
		var first := bd.doors.size()
		var dir := (b - a).normalized()
		BuildingParts.wall(bd, a, b, 0.0, 4.0, INTERIOR_WALL, INTERIOR_WALL, Vector2(-dir.y, dir.x), ops, Interiors.INNER_T, Color(0.55, 0.58, 0.6), id + "_l")
		if key != "":
			for k in range(first, bd.doors.size()):
				bd.doors[k].key = key
				bd.doors[k].power = site
				bd.doors[k].color = Color(0.25, 0.4, 0.75) if key == "keycard_blue" else Color(0.7, 0.18, 0.15)
	var door := func(at: float) -> Dictionary:
		return {"at": at, "w": 1.1, "bottom": 0.0, "top": 2.2, "kind": "door"}
	var x0 := r.position.x
	var z0 := r.position.y
	# Front rooms and the corridor (z 2..6).
	wall.call(Vector2(x0, 6.0), Vector2(r.end.x, 6.0), [door.call(7.0), door.call(20.5),
			{"at": 36.0, "w": 4.0, "bottom": 0.0, "top": 3.0, "kind": "open"}, door.call(51.5), door.call(65.0)], "")
	for x: float in [-22.0, -9.0, 9.0, 22.0]:
		wall.call(Vector2(x, 6.0), Vector2(x, r.end.y), [], "")
	# Back: labs (west), vestibule + vault (middle), containment (east).
	wall.call(Vector2(x0, 2.0), Vector2(-10.0, 2.0), [door.call(13.0)], "keycard_blue")
	wall.call(Vector2(-10.0, 2.0), Vector2(10.0, 2.0), [door.call(10.0)], "keycard_blue")
	wall.call(Vector2(10.0, 2.0), Vector2(r.end.x, 2.0), [door.call(7.0)], "keycard_blue")
	wall.call(Vector2(-10.0, z0), Vector2(-10.0, 2.0), [], "")
	wall.call(Vector2(10.0, z0), Vector2(10.0, 2.0), [], "")
	wall.call(Vector2(x0, -9.0), Vector2(-10.0, -9.0), [door.call(13.0)], "")
	wall.call(Vector2(-10.0, -6.0), Vector2(10.0, -6.0), [door.call(10.0)], "keycard_red")
	wall.call(Vector2(10.0, -8.0), Vector2(r.end.x, -8.0), [door.call(7.0)], "")
	wall.call(Vector2(24.0, -8.0), Vector2(24.0, 2.0), [door.call(5.0)], "")
	var put := func(kind: String, p: Vector2, yaw: float, must: Array) -> void:
		var before := bd.containers.size()
		Furniture.place(bd, kind, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.07, p.y)), rng, id + "_f%d" % bd.containers.size())
		if not must.is_empty() and bd.containers.size() > before:
			bd.containers[-1].must = must
	var spawn := func(p: Vector2, kind: String) -> void:
		bd.spawns.append({"pos": Vector3(p.x, 0.1, p.y), "id": "%s_z%d" % [id, bd.spawns.size()], "kind": kind})
	# Offices.
	for cx: float in [-29.0, -15.5]:
		put.call("desk", Vector2(cx, 19.0), PI, [])
		put.call("filing_cabinet", Vector2(cx - 4.5, 19.3), PI, [])
		put.call("bookshelf", Vector2(cx + 4.0, 7.0), 0.0, [])
		spawn.call(Vector2(cx, 12.0), "scientist")
	# Lobby: reception and seating.
	put.call("shop_counter", Vector2(0.0, 11.5), 0.0, [])
	put.call("couch", Vector2(-6.5, 17.0), PI * 0.5, [])
	put.call("couch", Vector2(6.5, 17.0), -PI * 0.5, [])
	spawn.call(Vector2(-3.0, 14.0), "scientist")
	spawn.call(Vector2(3.5, 9.0), "")
	# Security room: the blue keycard is in a locker.
	put.call("locker", Vector2(12.0, 19.3), PI, [["keycard_blue", 1]])
	put.call("locker", Vector2(13.2, 19.3), PI, [])
	put.call("locker", Vector2(14.4, 19.3), PI, [])
	put.call("desk", Vector2(18.5, 7.0), 0.0, [])
	spawn.call(Vector2(15.5, 13.0), "soldier")
	# Break room.
	put.call("fridge", Vector2(34.5, 19.3), PI, [])
	put.call("counter", Vector2(33.5, 19.3), PI, [])
	put.call("dining_set", Vector2(29.0, 12.0), 0.0, [])
	spawn.call(Vector2(27.0, 15.0), "")
	# Corridor.
	spawn.call(Vector2(-25.0, 4.0), "")
	spawn.call(Vector2(28.0, 4.0), "")
	# Labs.
	for cz: float in [-3.5, -14.5]:
		put.call("lab_bench", Vector2(-23.0, cz), 0.0, [])
		put.call("medical_cabinet", Vector2(-35.0 + 0.3, cz), PI * 0.5, [])
		put.call("medical_cabinet", Vector2(-11.0 - 0.3, cz), -PI * 0.5, [])
		spawn.call(Vector2(-29.0, cz + 2.0), "scientist")
		spawn.call(Vector2(-17.0, cz - 2.0), "scientist")
	# Vault: the cure.
	var vials := 1 + absi(id.hash()) % 2
	put.call("cryo_fridge", Vector2(-4.0, -19.4), 0.0, [["cure_vial", vials]])
	put.call("cryo_fridge", Vector2(4.0, -19.4), 0.0, [])
	put.call("store_shelf", Vector2(0.0, -1.0 + 0.0), PI, [])
	spawn.call(Vector2(0.0, -12.0), "scientist")
	# Director's office (red keycard) and containment.
	put.call("desk", Vector2(30.0, 1.3), PI, [["keycard_red", 1]])
	put.call("bookshelf", Vector2(35.6, -3.0), -PI * 0.5, [])
	spawn.call(Vector2(30.0, -4.0), "scientist")
	for p: Vector2 in [Vector2(14.0, -16.0), Vector2(22.0, -12.0), Vector2(30.0, -17.0), Vector2(34.0, -11.0)]:
		spawn.call(p, ["brute", "runner", "crawler", ""][bd.spawns.size() % 4])
	put.call("hospital_bed", Vector2(18.0, -18.5), 0.0, [])
	put.call("hospital_bed", Vector2(26.0, -18.5), 0.0, [])


func _small_hut(w: float, d: float, col: Color, windows: bool) -> void:
	var r := Rect2(-w * 0.5, -d * 0.5, w, d)
	var id := _id()
	BuildingParts.slab(bd, r, 0.02, 0.2, CONCRETE, CEILING)
	var ops := [{"at": w * 0.5, "w": BuildingParts.DOOR_W, "bottom": 0.0, "top": BuildingParts.DOOR_H, "kind": "door"}]
	BuildingParts.wall(bd, Vector2(r.position.x, r.end.y), r.end, 0.0, 2.6, col, INTERIOR_WALL, Vector2(0, 1), ops, 0.2, Color(0.35, 0.35, 0.37), id)
	var side_ops := [{"at": d * 0.5, "w": d * 0.6, "bottom": 1.0, "top": 2.1, "kind": "window"}] if windows else []
	BuildingParts.wall(bd, r.position, Vector2(r.end.x, r.position.y), 0.0, 2.6, col, INTERIOR_WALL, Vector2(0, -1), [], 0.2)
	BuildingParts.wall(bd, r.position, Vector2(r.position.x, r.end.y), 0.0, 2.6, col, INTERIOR_WALL, Vector2(-1, 0), side_ops, 0.2)
	BuildingParts.wall(bd, Vector2(r.end.x, r.position.y), r.end, 0.0, 2.6, col, INTERIOR_WALL, Vector2(1, 0), side_ops, 0.2)
	BuildingParts.flat_roof(bd, r, 2.6, Color(0.3, 0.3, 0.3), 0.2, col)
	if bd.interior:
		# Guard booths keep an equipment locker; sheds have shelves.
		Furniture.place(bd, "locker" if windows else "store_shelf", Transform3D(Basis.IDENTITY, Vector3(0, 0.07, r.position.y + 0.5)), rng, id)
		if lot.type == "generator_shed" and id.begins_with("site"):
			# The research site's generator: powers the lab's security doors.
			var gxf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(r.position.x + 1.2, 0.07, 0.6))
			Furniture.place(bd, "generator", gxf, rng, id)
			bd.containers.append({"pos": gxf * Vector3(0, 0.9, 0.0), "type": "generator", "id": id + "_gen",
				"site": id.get_slice("_", 0)})
