class_name Loot
extends RefCounted
## What's inside searchable containers. Rolled once, the first time a
## container is opened, from a pool that depends on the container and the
## building it's in (a locker in a police station holds different things than
## one in a school). Deterministic per container id, so everyone in a world
## finds the same thing. Scarce by design; guns are uncommon.

const NAMES := {
	"fridge": "Fridge", "kitchen_cabinet": "Cabinet", "medicine_cabinet": "Medicine Cabinet",
	"nightstand": "Nightstand", "dresser": "Dresser", "wardrobe": "Wardrobe", "desk": "Desk",
	"store_shelf": "Shelf", "register": "Register", "locker": "Locker", "medical": "Medical Cabinet",
	"car_trunk": "Car Trunk",
}

## Grid size of each container type.
const SIZES := {
	"fridge": Vector2i(4, 4), "kitchen_cabinet": Vector2i(4, 3), "medicine_cabinet": Vector2i(3, 2),
	"nightstand": Vector2i(3, 2), "dresser": Vector2i(5, 3), "wardrobe": Vector2i(5, 5), "desk": Vector2i(4, 3),
	"store_shelf": Vector2i(6, 4), "register": Vector2i(3, 2), "locker": Vector2i(4, 6), "medical": Vector2i(5, 4),
	"car_trunk": Vector2i(7, 4),
}

## pool -> [[item, weight], ...]
const POOLS := {
	"pantry": [["canned_beans", 3.0], ["canned_soup", 3.0], ["crackers", 2.0], ["chips", 1.5], ["energy_bar", 1.0],
		["soda", 1.0], ["water_bottle", 2.0], ["glass_bottle", 1.5], ["kitchen_knife", 0.8]],
	"fridge": [["soda", 3.0], ["water_bottle", 3.0], ["canned_soup", 0.8], ["glass_bottle", 1.0]],
	"medicine": [["bandage", 4.0], ["painkillers", 3.0], ["first_aid_kit", 0.4]],
	"bedroom": [["bandage", 2.0], ["painkillers", 1.5], ["noise_maker", 2.0], ["energy_bar", 1.0],
		["pistol_9mm", 0.25], ["ammo_9mm", 0.8], ["revolver", 0.12], ["ammo_357", 0.4], ["hunting_knife", 0.25],
		["baseball_bat", 0.35], ["school_backpack", 0.5], ["hiking_backpack", 0.15]],
	"office": [["energy_bar", 2.0], ["chips", 1.5], ["soda", 1.5], ["painkillers", 1.0], ["noise_maker", 1.0],
		["bandage", 0.8], ["pistol_9mm", 0.08], ["ammo_9mm", 0.2]],
	"grocery": [["canned_beans", 3.0], ["canned_soup", 3.0], ["crackers", 2.0], ["chips", 2.0], ["energy_bar", 1.5],
		["water_bottle", 2.5], ["soda", 2.5], ["glass_bottle", 1.0], ["bandage", 0.5]],
	"pharmacy": [["bandage", 4.0], ["painkillers", 3.5], ["first_aid_kit", 0.8], ["energy_bar", 1.0], ["water_bottle", 1.0]],
	"hardware": [["hammer", 2.0], ["crowbar", 1.5], ["fire_axe", 0.6], ["sledgehammer", 0.4], ["machete", 0.5],
		["bear_trap", 0.7], ["weapon_light", 0.4], ["glass_bottle", 1.0], ["noise_maker", 0.8]],
	"gun_store": [["ammo_9mm", 3.0], ["ammo_357", 2.0], ["ammo_12g", 2.5], ["ammo_308", 2.0], ["arrow", 1.5],
		["bolt", 1.0], ["red_dot", 0.5], ["scope", 0.5], ["weapon_light", 0.6], ["suppressor", 0.12], ["hunting_knife", 0.8]],
	"gun_locker": [["pistol_9mm", 1.0], ["revolver", 0.7], ["pump_shotgun", 0.8], ["hunting_rifle", 0.7],
		["compound_bow", 0.5], ["crossbow", 0.35], ["ammo_9mm", 1.0], ["ammo_12g", 0.8], ["ammo_308", 0.6]],
	"mall": [["school_backpack", 1.5], ["hiking_backpack", 0.6], ["baseball_bat", 1.0], ["compound_bow", 0.2],
		["arrow", 0.6], ["hunting_knife", 0.6], ["energy_bar", 1.5], ["soda", 1.5], ["chips", 1.5], ["noise_maker", 1.0]],
	"warehouse": [["crowbar", 1.0], ["hammer", 1.0], ["glass_bottle", 1.0], ["school_backpack", 0.6],
		["hiking_backpack", 0.4], ["water_bottle", 1.0], ["canned_beans", 1.0], ["bear_trap", 0.3]],
	"police": [["pistol_9mm", 1.5], ["ammo_9mm", 4.0], ["pump_shotgun", 0.6], ["ammo_12g", 2.0], ["tactical_vest", 0.6],
		["weapon_light", 0.6], ["red_dot", 0.3], ["first_aid_kit", 0.4], ["bandage", 1.5], ["energy_bar", 0.8]],
	"fire_station": [["fire_axe", 1.5], ["crowbar", 1.0], ["first_aid_kit", 1.0], ["bandage", 1.5], ["water_bottle", 1.0]],
	"school": [["school_backpack", 2.0], ["chips", 2.0], ["energy_bar", 1.5], ["soda", 1.5], ["baseball_bat", 0.6]],
	"hospital": [["bandage", 4.0], ["first_aid_kit", 1.5], ["painkillers", 3.0]],
	"diner": [["canned_soup", 2.0], ["soda", 3.0], ["water_bottle", 2.0], ["glass_bottle", 2.0], ["kitchen_knife", 1.0]],
	"register": [["energy_bar", 2.0], ["chips", 1.0], ["soda", 1.0], ["noise_maker", 0.5]],
	"military": [["assault_rifle", 0.8], ["ammo_556", 3.0], ["grenade", 1.0], ["military_backpack", 0.5],
		["tactical_vest", 0.8], ["mre", 2.0], ["first_aid_kit", 1.0], ["scope", 0.4], ["suppressor", 0.3]],
	"car_trunk": [["water_bottle", 2.0], ["canned_beans", 1.5], ["crowbar", 0.7], ["bandage", 1.0], ["first_aid_kit", 0.3],
		["school_backpack", 0.5], ["hiking_backpack", 0.25], ["glass_bottle", 1.5], ["molotov", 0.35], ["baseball_bat", 0.5],
		["ammo_12g", 0.4], ["ammo_308", 0.3], ["pump_shotgun", 0.08], ["hunting_rifle", 0.06], ["bear_trap", 0.2],
		["noise_maker", 0.5]],
}

## Stack sizes rolled for ammo and other stackables: id -> [min, max].
const COUNTS := {
	"ammo_9mm": [6, 24], "ammo_357": [4, 12], "ammo_12g": [3, 10], "ammo_308": [3, 10], "ammo_556": [10, 40],
	"arrow": [2, 6], "bolt": [2, 5], "bandage": [1, 3], "energy_bar": [1, 2], "grenade": [1, 2],
}


## Which pool and how many rolls a container gets: [pool, min rolls, max rolls].
static func _plan(type: String, building: String) -> Array:
	match type:
		"fridge":
			return ["fridge", 0, 2]
		"kitchen_cabinet":
			return ["pantry", 0, 2]
		"medicine_cabinet":
			return ["medicine", 0, 2]
		"nightstand", "dresser", "wardrobe":
			return ["bedroom", 0, 1 if type == "nightstand" else 2]
		"desk":
			return ["office", 0, 1]
		"register":
			return ["register", 0, 1]
		"medical":
			return ["hospital", 1, 3]
		"car_trunk":
			return ["car_trunk", 0, 2]
		"locker":
			match building:
				"police":
					return ["police", 0, 2]
				"fire_station":
					return ["fire_station", 0, 2]
				"school":
					return ["school", 0, 1]
				"gun_store":
					return ["gun_locker", 1, 2]
				"guard_booth":
					return ["military", 1, 3]
			return ["warehouse", 0, 2]
		"store_shelf":
			match building:
				"pharmacy":
					return ["pharmacy", 0, 2]
				"hardware":
					return ["hardware", 0, 2]
				"gun_store":
					return ["gun_store", 0, 2]
				"mall":
					return ["mall", 0, 2]
				"warehouse", "hangar", "generator_shed":
					return ["warehouse", 0, 2]
				"diner", "bar", "fast_food":
					return ["diner", 0, 2]
				"school":
					return ["school", 0, 1]
			if building in ["ranch", "colonial", "bungalow", "farmhouse", "duplex", "trailer"]:
				return ["warehouse", 0, 1] # Garage shelves.
			return ["grocery", 0, 2]
	return ["pantry", 0, 1]


static func _rand(h: int, k: int) -> float:
	return float(WorldGen.hash3(h, k, 977) % 100000) / 100000.0


## Rolls the contents of a container into a list of placed items.
static func fill(type: String, building: String, id: String) -> Array:
	var size: Vector2i = SIZES.get(type, Vector2i(4, 3))
	var grid := ItemGrid.new(id, "", size.x, size.y, [])
	var plan := _plan(type, building)
	var pool: Array = POOLS[plan[0]]
	var total := 0.0
	for e in pool:
		total += e[1]
	var h := id.hash()
	var loot: float = GameState.difficulty().loot
	var rolls := int(plan[1]) + int(_rand(h, 0) * (int(plan[2]) - int(plan[1]) + 1) * minf(loot, 1.5))
	# Most containers have been picked over in the weeks since the outbreak.
	if _rand(h, 1) > 0.55 * loot:
		rolls = mini(rolls, int(plan[1]))
	for r in rolls:
		var pick := _rand(h, 10 + r) * total
		var id_pick := ""
		for e in pool:
			pick -= e[1]
			if pick <= 0.0:
				id_pick = e[0]
				break
		if id_pick == "":
			id_pick = pool[-1][0]
		grid.add(roll_item(id_pick, h + r * 7919))
	return grid.items


## A found item with believable condition, ammo and stack size.
static func roll_item(id: String, h: int) -> Dictionary:
	var d := ItemDB.get_def(id)
	var n := 1
	if COUNTS.has(id):
		var c: Array = COUNTS[id]
		n = int(c[0]) + int(_rand(h, 3) * (int(c[1]) - int(c[0]) + 1))
	var it := ItemDB.make(id, n, 0.35 + _rand(h, 4) * 0.6)
	if d.get("cat", "") == "gun":
		it.a = int(_rand(h, 5) * 0.7 * int(d.mag))
	return it


static func label(type: String) -> String:
	return NAMES.get(type, "Container")
