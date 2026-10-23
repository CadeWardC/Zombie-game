class_name SiteLayout
extends RefCounted
## Layout of a special site: buildings (as lots, built like any other
## building), paved surfaces (runways, aprons, parking), props (aircraft,
## pumps) and an optional perimeter fence. Positions are in world space.
##
## Local site frame: x along the site's rotation, y perpendicular.

var site: Dictionary
var lots: Array[Dictionary] = []
## {center: Vector2, rot, half: Vector2, kind: "runway"|"taxiway"|"apron"|"parking"|"helipad"|"concrete"}
var surfaces: Array[Dictionary] = []
## {type: "airliner"|"prop_plane"|"helicopter"|"fuel_pump"|..., pos: Vector2, yaw}
var props: Array[Dictionary] = []
var fence: PackedVector2Array


static func build(s: Dictionary, gen: WorldGen) -> SiteLayout:
	var sl := SiteLayout.new()
	sl.site = s
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_value + 606 + s.id * 31
	match s.type:
		"airport":
			sl._airport(rng)
		"research":
			sl._research(rng)
		"gas_station":
			sl._gas_station()
		"power_plant":
			sl._power_plant()
		"trader":
			sl._trader_camp()
	return sl


func _world(local: Vector2) -> Vector2:
	return site.center + local.rotated(site.rot)


func _surface(kind: String, local_center: Vector2, half: Vector2, local_rot := 0.0) -> void:
	surfaces.append({"kind": kind, "center": _world(local_center), "rot": site.rot + local_rot, "half": half})


## A building lot. `front` is the local direction the entrance faces.
func _lot(type: String, local_center: Vector2, w: float, d: float, front: Vector2) -> void:
	var c := _world(local_center)
	var f := front.rotated(site.rot).normalized()
	lots.append({
		"id": "site%d_%d" % [site.id, lots.size()], "center": c, "yaw": atan2(f.x, f.y),
		"w": w, "d": d, "zone": TownLayout.Zone.STRIP, "type": type,
		"rad": 0.5 * Vector2(w, d).length(), "corners": TownLayout._corners(c, f, w, d),
		"seed": WorldGen.hash3(site.id, lots.size(), 91), "settlement": -1, "floor": site.base + 0.15,
	})


func _prop(type: String, local: Vector2, local_yaw: float) -> void:
	props.append({"type": type, "pos": _world(local), "yaw": local_yaw - site.rot})


func _perimeter(margin: float) -> void:
	var h: Vector2 = site.half - Vector2(margin, margin)
	fence = PackedVector2Array([_world(Vector2(-h.x, -h.y)), _world(Vector2(h.x, -h.y)),
			_world(Vector2(h.x, h.y)), _world(Vector2(-h.x, h.y)), _world(Vector2(-h.x, -h.y))])


func _airport(rng: RandomNumberGenerator) -> void:
	var hx: float = site.half.x
	_surface("runway", Vector2(0, -100), Vector2(hx - 60.0, 24.0))
	_surface("taxiway", Vector2(0, -30), Vector2(hx - 140.0, 9.0))
	for x in [-hx + 160.0, 0.0, hx - 160.0]:
		_surface("taxiway", Vector2(x, -65), Vector2(9.0, 30.0))
	_surface("apron", Vector2(-120, 60), Vector2(260.0, 60.0))
	_surface("parking", Vector2(-120, 200), Vector2(110.0, 24.0))
	_lot("terminal", Vector2(-120, 150), 150.0, 36.0, Vector2(0, -1))
	_lot("control_tower", Vector2(90, 150), 12.0, 12.0, Vector2(0, -1))
	for k in 3:
		var x := 200.0 + k * 85.0
		_surface("apron", Vector2(x, 60), Vector2(38.0, 60.0))
		_lot("hangar", Vector2(x, 145), 64.0, 52.0, Vector2(0, -1))
		_prop("jet_pump", Vector2(x + 24.0, 104), 0.0)
	# Aircraft: most can fly with fuel; some sit broken (decided in stage 5).
	for k in 3:
		_prop("airliner" if k == 0 else "prop_plane", Vector2(-300 + k * 110, 60), PI * 0.5)
	for k in 3:
		var x := 200.0 + k * 85.0
		_prop("prop_plane" if rng.randf() < 0.6 else "helicopter", Vector2(x, 70), PI * 0.5)
	for k in 2:
		_surface("helipad", Vector2(hx - 90.0 - k * 50.0, 190), Vector2(14.0, 14.0))
		_prop("helicopter", Vector2(hx - 90.0 - k * 50.0, 190), PI * 0.5)
	_perimeter(6.0)


## Turbine hall, control room (its generator restarts the grid), cooling
## towers and a fenced yard.
func _power_plant() -> void:
	_surface("concrete", Vector2(0, 0), site.half - Vector2(12.0, 12.0))
	_lot("warehouse", Vector2(-40, 10), 70.0, 36.0, Vector2(0, -1))
	_lot("generator_shed", Vector2(30, -35), 16.0, 12.0, Vector2(0, -1))
	_lot("warehouse", Vector2(45, 30), 36.0, 24.0, Vector2(-1, 0))
	for k in 2:
		_prop("cooling_tower", Vector2(-70.0 + k * 40.0, 60.0), 0.0)
	_surface("parking", Vector2(60, -60), Vector2(26.0, 14.0))
	_perimeter(5.0)


## A trader's compound: a hut, tents, a fence all round.
func _trader_camp() -> void:
	_surface("concrete", Vector2(0, -8), Vector2(6.0, 4.0))
	_lot("trader_hut", Vector2(0, 8), 8.0, 6.0, Vector2(0, -1))
	_prop("tent", Vector2(-14, -4), 0.4)
	_prop("tent", Vector2(14, -2), -0.5)
	_prop("tent", Vector2(-12, 10), 1.6)
	_prop("rock", Vector2(18, 12), 0.0)
	_perimeter(2.0)


func _research(rng: RandomNumberGenerator) -> void:
	_lot("research_lab", Vector2(0, 15), 72.0, 40.0, Vector2(0, -1))
	_lot("guard_booth", Vector2(0, -site.half.y + 14.0), 5.0, 5.0, Vector2(0, -1))
	_lot("generator_shed", Vector2(-site.half.x + 25.0, 45), 14.0, 10.0, Vector2(1, 0))
	_surface("parking", Vector2(-50, -45), Vector2(32.0, 18.0))
	_surface("concrete", Vector2(0, -40), Vector2(6.0, site.half.y - 40.0))
	_surface("helipad", Vector2(60, -48), Vector2(13.0, 13.0))
	if rng.randf() < 0.7:
		_prop("helicopter", Vector2(60, -48), PI * 0.5)
	_perimeter(4.0)


func _gas_station() -> void:
	_surface("concrete", Vector2(0, 0), site.half - Vector2(1.0, 1.0))
	_lot("gas_station_store", Vector2(0, 9), 16.0, 10.0, Vector2(0, -1))
	_lot("gas_canopy", Vector2(0, -6), 18.0, 9.0, Vector2(0, -1))
	for x: float in [-5.0, 0.0, 5.0]:
		_prop("fuel_pump", Vector2(x, -6), 0.0)
