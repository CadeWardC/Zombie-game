class_name VehicleDB
extends RefCounted
## Every kind of vehicle and its handling, plus the state a vehicle starts
## with when it's first found (most are in bad shape). Plain data.
##
## kind: ground / water / heli / plane. speed (m/s top speed), accel, steer
## (turn rate scale), fuel ("gas", "jet" or "" for none), tank (litres), use
## (litres per second at full throttle), noise (metres zombies hear the
## engine), seats, closed (occupants are safe from bites while it holds),
## trunk, hp, size (x, y, z metres: width, height, length), cam (chase
## camera distance), takeoff (planes: speed needed to lift off).

const TYPES := {
	"bicycle": {"name": "Bicycle", "kind": "ground", "speed": 9.0, "accel": 3.5, "steer": 1.5, "fuel": "", "tank": 0.0,
		"use": 0.0, "noise": 0.0, "seats": 1, "closed": false, "trunk": false, "hp": 60.0, "size": Vector3(0.6, 1.1, 1.8), "cam": 4.0},
	"motorbike": {"name": "Motorbike", "kind": "ground", "speed": 30.0, "accel": 9.0, "steer": 1.4, "fuel": "gas", "tank": 12.0,
		"use": 0.012, "noise": 40.0, "seats": 2, "closed": false, "trunk": false, "hp": 120.0, "size": Vector3(0.8, 1.2, 2.1), "cam": 4.5},
	"sedan": {"name": "Sedan", "kind": "ground", "speed": 34.0, "accel": 7.0, "steer": 1.0, "fuel": "gas", "tank": 50.0,
		"use": 0.03, "noise": 32.0, "seats": 4, "closed": true, "trunk": true, "hp": 300.0, "size": Vector3(1.9, 1.5, 4.6), "cam": 7.0},
	"hatchback": {"name": "Hatchback", "kind": "ground", "speed": 32.0, "accel": 7.0, "steer": 1.1, "fuel": "gas", "tank": 45.0,
		"use": 0.026, "noise": 30.0, "seats": 4, "closed": true, "trunk": true, "hp": 260.0, "size": Vector3(1.8, 1.5, 4.0), "cam": 6.5},
	"suv": {"name": "SUV", "kind": "ground", "speed": 31.0, "accel": 6.5, "steer": 0.95, "fuel": "gas", "tank": 65.0,
		"use": 0.04, "noise": 34.0, "seats": 5, "closed": true, "trunk": true, "hp": 380.0, "size": Vector3(2.0, 1.8, 4.8), "cam": 7.5},
	"pickup": {"name": "Pickup Truck", "kind": "ground", "speed": 31.0, "accel": 6.5, "steer": 0.9, "fuel": "gas", "tank": 70.0,
		"use": 0.042, "noise": 36.0, "seats": 2, "closed": true, "trunk": true, "hp": 400.0, "size": Vector3(2.0, 1.8, 5.2), "cam": 7.5},
	"van": {"name": "Van", "kind": "ground", "speed": 27.0, "accel": 5.0, "steer": 0.85, "fuel": "gas", "tank": 70.0,
		"use": 0.042, "noise": 34.0, "seats": 2, "closed": true, "trunk": true, "hp": 380.0, "size": Vector3(2.0, 2.2, 5.0), "cam": 8.0},
	"police": {"name": "Police Car", "kind": "ground", "speed": 40.0, "accel": 8.5, "steer": 1.05, "fuel": "gas", "tank": 55.0,
		"use": 0.035, "noise": 34.0, "seats": 4, "closed": true, "trunk": true, "hp": 340.0, "size": Vector3(1.9, 1.5, 4.8), "cam": 7.0},
	"ambulance": {"name": "Ambulance", "kind": "ground", "speed": 30.0, "accel": 5.0, "steer": 0.8, "fuel": "gas", "tank": 80.0,
		"use": 0.045, "noise": 36.0, "seats": 2, "closed": true, "trunk": true, "hp": 420.0, "size": Vector3(2.2, 2.6, 5.8), "cam": 9.0},
	"school_bus": {"name": "School Bus", "kind": "ground", "speed": 22.0, "accel": 3.5, "steer": 0.6, "fuel": "gas", "tank": 150.0,
		"use": 0.06, "noise": 40.0, "seats": 8, "closed": true, "trunk": true, "hp": 700.0, "size": Vector3(2.5, 3.0, 10.0), "cam": 12.0},
	"rowboat": {"name": "Rowboat", "kind": "water", "speed": 3.5, "accel": 1.2, "steer": 0.8, "fuel": "", "tank": 0.0,
		"use": 0.0, "noise": 0.0, "seats": 2, "closed": false, "trunk": false, "hp": 150.0, "size": Vector3(1.4, 0.7, 3.6), "cam": 6.0},
	"motorboat": {"name": "Motorboat", "kind": "water", "speed": 16.0, "accel": 4.0, "steer": 0.8, "fuel": "gas", "tank": 40.0,
		"use": 0.03, "noise": 35.0, "seats": 4, "closed": false, "trunk": false, "hp": 250.0, "size": Vector3(2.0, 1.2, 5.0), "cam": 8.0},
	"helicopter": {"name": "Helicopter", "kind": "heli", "speed": 45.0, "accel": 8.0, "steer": 1.0, "fuel": "jet", "tank": 250.0,
		"use": 0.12, "noise": 130.0, "seats": 4, "closed": true, "trunk": false, "hp": 300.0, "size": Vector3(2.0, 2.6, 6.0), "cam": 14.0},
	"prop_plane": {"name": "Light Aircraft", "kind": "plane", "speed": 65.0, "accel": 7.0, "steer": 0.7, "fuel": "jet", "tank": 200.0,
		"use": 0.1, "noise": 120.0, "seats": 2, "closed": true, "trunk": false, "hp": 260.0, "size": Vector3(10.0, 2.5, 8.0), "cam": 16.0,
		"takeoff": 28.0},
}

## Parked car models (Assets.cars index) -> type. Model 8 is a burned-out
## wreck and never drives.
const CAR_MODELS := ["sedan", "hatchback", "suv", "pickup", "van", "sedan", "suv", "police", "", "sedan", "hatchback",
	"suv", "pickup", "van", "ambulance", "school_bus"]


static func get_def(type: String) -> Dictionary:
	return TYPES.get(type, TYPES.sedan)


static func car_type(model: int) -> String:
	return CAR_MODELS[model] if model >= 0 and model < CAR_MODELS.size() else ""


static func _rand(h: int, k: int) -> float:
	return float(WorldGen.hash3(h, k, 1777) % 100000) / 100000.0


## The state of a vehicle when first found, rolled from its id so everyone
## in a world finds it the same way. Most cars won't start without work.
static func roll(id: String, type: String, model := -1) -> Dictionary:
	var h := id.hash()
	var d := get_def(type)
	var r := {"id": id, "t": type, "m": model, "p": [0.0, 0.0, 0.0], "yaw": 0.0, "fuel": 0.0, "eng": 1.0, "bat": 1.0,
		"flat": 0, "keys": false, "hot": false, "locked": false, "hp": float(d.hp), "parts": true, "trunk": ""}
	if d.fuel != "":
		var f := _rand(h, 1)
		r.fuel = 0.0 if f < 0.35 else float(d.tank) * _rand(h, 2) * 0.4
	match d.kind:
		"ground":
			if type != "bicycle":
				r.keys = _rand(h, 3) < (0.1 if type == "police" else 0.25)
				r.bat = 0.1 if _rand(h, 4) < 0.5 else 0.5 + _rand(h, 5) * 0.5
				r.eng = 0.05 if _rand(h, 6) < 0.25 else 0.4 + _rand(h, 7) * 0.6
				r.locked = not r.keys and _rand(h, 8) < 0.5
			if _rand(h, 9) < 0.3:
				r.flat = 1 + int(_rand(h, 10) * 2.0)
		"water":
			r.keys = true
			r.eng = 0.6 + _rand(h, 7) * 0.4
		"heli", "plane":
			r.fuel = float(d.tank) * _rand(h, 2) * 0.1
			r.keys = _rand(h, 3) < 0.5
			r.parts = _rand(h, 11) > 0.3
	return r


## Can this vehicle's engine run? Returns "" if so, or why not.
static func cant_start(r: Dictionary) -> String:
	var d := get_def(r.t)
	if float(r.hp) <= 0.0:
		return "It's wrecked"
	if d.fuel == "":
		return ""
	if not r.parts:
		return "It needs engine parts"
	if float(r.eng) < 0.1:
		return "The engine is shot (engine parts would fix it)"
	if not r.keys and not r.hot:
		return "No keys (hotwire it with a screwdriver)"
	if float(r.bat) < 0.2 and d.kind == "ground":
		return "The battery is dead"
	if float(r.fuel) <= 0.01:
		return "Out of %s" % ("gas" if d.fuel == "gas" else "jet fuel")
	return ""


## One line about its condition (for the vehicle menu).
static func describe(r: Dictionary) -> String:
	var d := get_def(r.t)
	var parts: PackedStringArray = []
	if d.fuel != "":
		parts.append("Fuel %d / %d L" % [int(r.fuel), int(d.tank)])
	if float(r.hp) <= 0.0:
		parts.append("Wrecked")
	elif d.fuel != "":
		parts.append("Engine %d%%" % int(float(r.eng) * 100.0))
		if d.kind == "ground":
			parts.append("Battery %s" % ("dead" if float(r.bat) < 0.2 else "OK"))
		parts.append("Keys in it" if r.keys else ("Hotwired" if r.hot else "No keys"))
		if not r.parts:
			parts.append("Needs engine parts")
	if int(r.flat) > 0:
		parts.append("%d flat tire%s" % [int(r.flat), "" if int(r.flat) == 1 else "s"])
	if r.locked:
		parts.append("Locked")
	return "  -  ".join(parts)
