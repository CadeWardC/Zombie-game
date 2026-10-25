class_name Loot
extends RefCounted
## What's inside searchable containers. Rolled once, the first time a
## container is opened, from a pool that depends on the container and the
## building it's in (a locker in a police station holds different things than
## one in a school). Deterministic per container id, so everyone in a world
## finds the same thing. Most containers hold something; guns are uncommon.

const NAMES := {
	"fuel_pump": "Gas Pump", "jet_pump": "Jet Fuel Pump",
	"fridge": "Fridge", "kitchen_cabinet": "Cabinet", "medicine_cabinet": "Medicine Cabinet",
	"nightstand": "Nightstand", "dresser": "Dresser", "wardrobe": "Wardrobe", "desk": "Desk",
	"store_shelf": "Shelf", "register": "Register", "locker": "Locker", "medical": "Medical Cabinet",
	"car_trunk": "Car Trunk", "corpse": "Body", "cryo_fridge": "Cryo Storage", "generator": "Generator", "crate": "Storage Crate",
}

## Grid size of each container type.
const SIZES := {
	"fridge": Vector2i(4, 4), "kitchen_cabinet": Vector2i(4, 3), "medicine_cabinet": Vector2i(3, 2),
	"nightstand": Vector2i(3, 2), "dresser": Vector2i(5, 3), "wardrobe": Vector2i(5, 5), "desk": Vector2i(4, 3),
	"store_shelf": Vector2i(6, 4), "register": Vector2i(3, 2), "locker": Vector2i(4, 6), "medical": Vector2i(5, 4),
	"car_trunk": Vector2i(7, 4), "corpse": Vector2i(5, 4), "cryo_fridge": Vector2i(4, 3), "crate": Vector2i(8, 6),
}

## pool -> [[item, weight], ...]
const POOLS := {
	"pantry": [["canned_beans", 3.0], ["canned_soup", 3.0], ["crackers", 2.0], ["chips", 1.5], ["energy_bar", 1.0],
		["soda", 1.0], ["water_bottle", 2.0], ["glass_bottle", 1.5], ["kitchen_knife", 0.8], ["bread", 1.0], ["potato", 0.8],
		["matches", 0.8], ["cooking_pot", 0.5], ["dog_food", 0.4], ["purification_tablets", 0.15], ["canned_tuna", 2.0], ["canned_peaches", 1.5], ["canned_corn", 1.5], ["peanut_butter", 1.0], ["instant_noodles", 2.0], ["cereal", 1.5], ["candy_bar", 1.0], ["coffee", 0.8], ["juice", 1.0], ["frying_pan", 0.5], ["meat_cleaver", 0.3], ["batteries", 0.6], ["glue", 0.3]],
	"fridge": [["soda", 3.0], ["water_bottle", 3.0], ["canned_soup", 0.8], ["glass_bottle", 1.0], ["milk", 1.5], ["raw_meat", 1.2],
		["carrot", 0.8], ["tomato", 0.8], ["potato", 0.5], ["juice", 2.0], ["sports_drink", 1.0], ["coffee", 0.8], ["canned_peaches", 0.5]],
	"medicine": [["bandage", 4.0], ["painkillers", 3.0], ["first_aid_kit", 0.4], ["alcohol_wipes", 2.0], ["suture_kit", 0.4],
		["antibiotics", 0.25], ["splint", 0.15], ["rag", 1.0], ["vitamins", 2.0]],
	"clothes": [["t_shirt", 3.0], ["flannel_shirt", 2.0], ["hoodie", 2.0], ["jeans", 3.0], ["cargo_pants", 1.0],
		["work_pants", 0.8], ["sneakers", 2.0], ["work_boots", 0.8], ["baseball_cap", 1.5], ["beanie", 1.2],
		["leather_jacket", 0.5], ["hunting_jacket", 0.4], ["motorcycle_helmet", 0.15], ["sewing_kit", 0.6],
		["cigarettes", 0.6], ["rag", 1.0], ["school_backpack", 0.3], ["winter_coat", 0.4], ["raincoat", 0.4], ["lighter", 0.3], ["cloth", 1.5], ["watch", 0.4], ["wallet", 0.4]],
	"bedroom": [["bandage", 2.0], ["painkillers", 1.5], ["noise_maker", 2.0], ["energy_bar", 1.0],
		["pistol_9mm", 0.25], ["ammo_9mm", 0.8], ["revolver", 0.12], ["ammo_357", 0.4], ["hunting_knife", 0.25],
		["baseball_bat", 0.35], ["school_backpack", 0.5], ["hiking_backpack", 0.15], ["wallet", 1.0], ["watch", 0.6], ["batteries", 1.0], ["candy_bar", 1.0], ["vitamins", 0.6], ["car_keys", 0.6], ["golf_club", 0.2], ["binoculars", 0.15], ["cigarettes", 0.8], ["lighter", 0.5]],
	"office": [["energy_bar", 2.0], ["chips", 1.5], ["soda", 1.5], ["painkillers", 1.0], ["noise_maker", 1.0],
		["bandage", 0.8], ["pistol_9mm", 0.08], ["ammo_9mm", 0.2], ["candy_bar", 1.5], ["coffee", 1.5], ["batteries", 1.0], ["glue", 0.8], ["wire", 0.6], ["car_keys", 0.5], ["wallet", 0.5]],
	"grocery": [["canned_beans", 3.0], ["canned_soup", 3.0], ["crackers", 2.0], ["chips", 2.0], ["energy_bar", 1.5],
		["water_bottle", 2.5], ["soda", 2.5], ["glass_bottle", 1.0], ["bandage", 0.5], ["bread", 1.0], ["dog_food", 0.8],
		["matches", 0.6], ["seeds_potato", 0.3], ["seeds_tomato", 0.3], ["purification_tablets", 0.2], ["canned_tuna", 2.5], ["canned_peaches", 2.0], ["canned_corn", 2.0], ["peanut_butter", 1.2], ["instant_noodles", 2.0], ["cereal", 1.5], ["candy_bar", 2.0], ["juice", 2.0], ["sports_drink", 1.5], ["coffee", 1.2], ["batteries", 1.0], ["vitamins", 0.4]],
	"pharmacy": [["bandage", 4.0], ["painkillers", 3.5], ["first_aid_kit", 0.8], ["energy_bar", 1.0], ["water_bottle", 1.0],
		["alcohol_wipes", 3.0], ["antibiotics", 1.2], ["suture_kit", 0.6], ["splint", 0.6], ["cigarettes", 1.0],
		["purification_tablets", 1.0], ["vitamins", 3.0], ["candy_bar", 1.0], ["sports_drink", 0.8]],
	"hardware": [["hammer", 2.0], ["crowbar", 1.5], ["fire_axe", 0.6], ["sledgehammer", 0.4], ["machete", 0.5],
		["bear_trap", 0.7], ["weapon_light", 0.4], ["glass_bottle", 1.0], ["noise_maker", 0.8], ["work_pants", 0.6],
		["work_boots", 0.5], ["splint", 0.3], ["sewing_kit", 0.4], ["gas_can", 0.8], ["car_battery", 0.5],
		["engine_parts", 0.6], ["screwdriver", 1.0], ["nails", 2.0], ["saw", 0.8], ["duct_tape", 1.0], ["rope", 0.8],
		["shovel", 0.6], ["hatchet", 0.5], ["watering_can", 0.5], ["seeds_potato", 0.5], ["seeds_carrot", 0.5],
		["seeds_tomato", 0.4], ["seeds_corn", 0.4], ["plank", 0.6], ["scrap_metal", 0.5], ["matches", 0.5], ["pipe_wrench", 0.6], ["wrench", 1.0], ["pickaxe", 0.3], ["lead_pipe", 0.5], ["tire_iron", 0.4], ["wire", 1.2], ["glue", 0.8], ["tarp", 0.8], ["batteries", 1.0]],
	"gun_store": [["ammo_9mm", 3.0], ["ammo_357", 2.0], ["ammo_12g", 2.5], ["ammo_308", 2.0], ["arrow", 1.5],
		["bolt", 1.0], ["red_dot", 0.5], ["scope", 0.5], ["weapon_light", 0.6], ["suppressor", 0.12], ["hunting_knife", 0.8]],
	"gun_locker": [["pistol_9mm", 1.0], ["revolver", 0.7], ["pump_shotgun", 0.8], ["hunting_rifle", 0.7],
		["compound_bow", 0.5], ["crossbow", 0.35], ["ammo_9mm", 1.0], ["ammo_12g", 0.8], ["ammo_308", 0.6]],
	"mall": [["school_backpack", 1.5], ["hiking_backpack", 0.6], ["baseball_bat", 1.0], ["compound_bow", 0.2],
		["arrow", 0.6], ["hunting_knife", 0.6], ["energy_bar", 1.5], ["soda", 1.5], ["chips", 1.5], ["noise_maker", 1.0],
		["leather_jacket", 0.5], ["hoodie", 1.0], ["jeans", 1.0], ["sneakers", 1.0], ["beanie", 0.6], ["hunting_jacket", 0.3],
		["sleeping_bag", 0.5], ["fishing_rod", 0.5], ["winter_coat", 0.5], ["raincoat", 0.5], ["lighter", 0.6],
		["purification_tablets", 0.4], ["cooking_pot", 0.4], ["golf_club", 0.6], ["binoculars", 0.4], ["watch", 0.6], ["batteries", 0.8], ["candy_bar", 1.0], ["juice", 0.8], ["cloth", 0.8]],
	"warehouse": [["crowbar", 1.0], ["hammer", 1.0], ["glass_bottle", 1.0], ["school_backpack", 0.6],
		["hiking_backpack", 0.4], ["water_bottle", 1.0], ["canned_beans", 1.0], ["bear_trap", 0.3], ["work_pants", 0.6],
		["work_boots", 0.5], ["rag", 1.0], ["gas_can", 0.8], ["car_tire", 0.6], ["car_battery", 0.4],
		["engine_parts", 0.5], ["screwdriver", 0.6], ["plank", 1.5], ["nails", 1.5], ["scrap_metal", 1.5], ["rope", 0.8],
		["duct_tape", 0.8], ["saw", 0.5], ["shovel", 0.4], ["fishing_rod", 0.4], ["watering_can", 0.3],
		["seeds_corn", 0.3], ["seeds_carrot", 0.3], ["pipe_wrench", 0.4], ["wrench", 0.8], ["lead_pipe", 0.8], ["tire_iron", 0.5], ["pickaxe", 0.3], ["wire", 1.0], ["tarp", 1.0], ["batteries", 0.5], ["cloth", 0.8]],
	"gas_store": [["gas_can", 2.0], ["energy_bar", 2.0], ["chips", 2.0], ["soda", 2.0], ["water_bottle", 1.5],
		["cigarettes", 1.5], ["screwdriver", 0.4], ["car_battery", 0.3], ["painkillers", 0.5], ["lighter", 1.0], ["duct_tape", 0.6],
		["dog_food", 0.4], ["candy_bar", 2.0], ["sports_drink", 1.2], ["coffee", 1.2], ["batteries", 1.0], ["tire_iron", 0.4], ["wrench", 0.3], ["instant_noodles", 1.0]],
	"hangar": [["jet_fuel_can", 3.0], ["engine_parts", 1.0], ["screwdriver", 0.6], ["car_battery", 0.5], ["gas_can", 0.5]],
	"police": [["pistol_9mm", 1.5], ["ammo_9mm", 4.0], ["pump_shotgun", 0.6], ["ammo_12g", 2.0], ["tactical_vest", 0.6],
		["weapon_light", 0.6], ["red_dot", 0.3], ["first_aid_kit", 0.4], ["bandage", 1.5], ["energy_bar", 0.8],
		["riot_helmet", 0.4], ["riot_armor", 0.25], ["uniform_shirt", 0.5], ["work_boots", 0.4], ["binoculars", 0.3], ["batteries", 1.0], ["coffee", 1.0]],
	"fire_station": [["fire_axe", 1.5], ["crowbar", 1.0], ["first_aid_kit", 1.0], ["bandage", 1.5], ["water_bottle", 1.0],
		["firefighter_jacket", 0.8], ["work_boots", 0.6], ["splint", 0.5], ["pickaxe", 0.4], ["coffee", 0.8], ["sports_drink", 0.6]],
	"school": [["school_backpack", 2.0], ["chips", 2.0], ["energy_bar", 1.5], ["soda", 1.5], ["baseball_bat", 0.6], ["candy_bar", 1.5], ["juice", 1.5], ["glue", 1.0], ["batteries", 0.5], ["cloth", 0.6]],
	"hospital": [["bandage", 4.0], ["first_aid_kit", 1.5], ["painkillers", 3.0], ["suture_kit", 2.0], ["alcohol_wipes", 3.0],
		["antibiotics", 1.5], ["splint", 1.5], ["scrubs_top", 0.6], ["scrubs_pants", 0.6], ["lab_coat", 0.3]],
	"diner": [["canned_soup", 2.0], ["soda", 3.0], ["water_bottle", 2.0], ["glass_bottle", 2.0], ["kitchen_knife", 1.0], ["frying_pan", 0.8], ["meat_cleaver", 0.6], ["coffee", 1.5], ["juice", 1.0], ["instant_noodles", 0.8], ["canned_corn", 1.0]],
	"register": [["energy_bar", 2.0], ["chips", 1.0], ["soda", 1.0], ["noise_maker", 0.5], ["cigarettes", 2.0], ["batteries", 0.6], ["candy_bar", 1.5], ["wallet", 0.5], ["car_keys", 0.4]],
	"military": [["assault_rifle", 0.8], ["ammo_556", 3.0], ["grenade", 1.0], ["military_backpack", 0.5],
		["tactical_vest", 0.8], ["mre", 2.0], ["first_aid_kit", 1.0], ["scope", 0.4], ["suppressor", 0.3],
		["military_helmet", 0.8], ["military_armor", 0.5], ["military_pants", 0.8], ["military_boots", 0.8],
		["purification_tablets", 1.0], ["sleeping_bag", 0.4]],
	"lab": [["antibiotics", 2.0], ["alcohol_wipes", 2.0], ["suture_kit", 1.0], ["painkillers", 1.5], ["first_aid_kit", 0.5],
		["lab_coat", 0.5], ["bandage", 1.5], ["splint", 0.4]],
	"lab_security": [["pistol_9mm", 0.6], ["ammo_9mm", 2.0], ["riot_helmet", 0.4], ["first_aid_kit", 0.5],
		["energy_bar", 1.0], ["weapon_light", 0.4], ["uniform_shirt", 0.4]],
	"vault": [["antibiotics", 2.0], ["first_aid_kit", 0.6], ["suture_kit", 0.6]],
	"car_trunk": [["water_bottle", 2.0], ["canned_beans", 1.5], ["crowbar", 0.7], ["bandage", 1.0], ["first_aid_kit", 0.3],
		["school_backpack", 0.5], ["hiking_backpack", 0.25], ["glass_bottle", 1.5], ["molotov", 0.35], ["baseball_bat", 0.5],
		["ammo_12g", 0.4], ["ammo_308", 0.3], ["pump_shotgun", 0.08], ["hunting_rifle", 0.06], ["bear_trap", 0.2],
		["noise_maker", 0.5], ["rag", 1.0], ["motorcycle_helmet", 0.2], ["leather_jacket", 0.15], ["gas_can", 0.5],
		["car_tire", 0.4], ["screwdriver", 0.3], ["tire_iron", 1.0], ["wrench", 0.5], ["tarp", 0.4], ["sports_drink", 0.6], ["batteries", 0.5], ["golf_club", 0.3], ["binoculars", 0.15]],
	"zombie": [["wallet", 3.0], ["watch", 1.5], ["car_keys", 1.5], ["cigarettes", 2.0], ["lighter", 1.2], ["matches", 0.8],
		["bandage", 1.5], ["painkillers", 1.2], ["candy_bar", 2.0], ["energy_bar", 1.0], ["soda", 1.2], ["water_bottle", 1.0],
		["juice", 0.8], ["batteries", 1.0], ["rag", 1.5], ["kitchen_knife", 0.4], ["screwdriver", 0.5], ["ammo_9mm", 0.5],
		["pistol_9mm", 0.06], ["vitamins", 0.4], ["noise_maker", 0.4], ["canned_tuna", 0.5], ["school_backpack", 0.2]],
}

## Stack sizes rolled for ammo and other stackables: id -> [min, max].
const COUNTS := {
	"ammo_9mm": [6, 24], "ammo_357": [4, 12], "ammo_12g": [3, 10], "ammo_308": [3, 10], "ammo_556": [10, 40],
	"arrow": [2, 6], "bolt": [2, 5], "bandage": [1, 3], "energy_bar": [1, 2], "grenade": [1, 2],
	"alcohol_wipes": [1, 4], "suture_kit": [1, 2], "rag": [1, 3], "nails": [10, 40], "plank": [1, 3], "scrap_metal": [1, 3],
	"seeds_potato": [3, 8], "seeds_carrot": [3, 8], "seeds_tomato": [3, 8], "seeds_corn": [3, 8], "potato": [1, 3],
	"carrot": [1, 3], "raw_meat": [1, 2], "rope": [1, 2],
	"batteries": [2, 6], "candy_bar": [1, 3], "instant_noodles": [1, 3], "canned_tuna": [1, 2], "wire": [1, 3], "cloth": [1, 4], "juice": [1, 2],
}


## Which pool and how many rolls a container gets: [pool, min rolls, max rolls].
static func _plan(type: String, building: String) -> Array:
	match type:
		"corpse":
			match building:
				"soldier":
					return ["military", 1, 3]
				"scientist":
					return ["lab", 1, 2]
			return ["zombie", 0, 3]
		"fridge":
			return ["fridge", 1, 4]
		"kitchen_cabinet":
			return ["pantry", 1, 4]
		"medicine_cabinet":
			return ["medicine", 1, 4]
		"nightstand":
			return ["bedroom", 1, 3]
		"dresser", "wardrobe":
			return ["clothes", 1, 4]
		"cryo_fridge":
			return ["vault", 1, 4]
		"desk":
			return ["office", 1, 3]
		"register":
			return ["register", 1, 3]
		"medical":
			return ["lab", 2, 5] if building == "research_lab" else ["hospital", 2, 5]
		"car_trunk":
			return ["car_trunk", 1, 4]
		"locker":
			match building:
				"police":
					return ["police", 1, 4]
				"fire_station":
					return ["fire_station", 1, 4]
				"school":
					return ["school", 1, 3]
				"gun_store":
					return ["gun_locker", 2, 4]
				"guard_booth":
					return ["military", 2, 5]
				"research_lab":
					return ["lab_security", 2, 4]
			return ["warehouse", 1, 4]
		"store_shelf":
			match building:
				"pharmacy":
					return ["pharmacy", 1, 4]
				"hardware":
					return ["hardware", 1, 4]
				"gun_store":
					return ["gun_store", 1, 4]
				"mall":
					return ["mall", 1, 4]
				"hangar":
					return ["hangar", 2, 4]
				"gas_station_store":
					return ["gas_store", 1, 4]
				"warehouse", "generator_shed":
					return ["warehouse", 1, 4]
				"diner", "bar", "fast_food":
					return ["diner", 1, 4]
				"school":
					return ["school", 1, 3]
			if building in ["ranch", "colonial", "bungalow", "farmhouse", "duplex", "trailer"]:
				return ["warehouse", 1, 3] # Garage shelves.
			return ["grocery", 1, 4]
	return ["pantry", 1, 3]


static func _rand(h: int, k: int) -> float:
	return float(WorldGen.hash3(h, k, 977) % 100000) / 100000.0


## Rolls the contents of a container into a list of placed items.
## `must`: items it always holds ([[id, count], ...]: keycards, the cure).
static func fill(type: String, building: String, id: String, must: Array = []) -> Array:
	var size: Vector2i = SIZES.get(type, Vector2i(4, 3))
	var grid := ItemGrid.new(id, "", size.x, size.y, [])
	for m in must:
		grid.add(ItemDB.make(m[0], int(m[1])))
	var plan := _plan(type, building)
	var pool: Array = POOLS[plan[0]]
	var total := 0.0
	for e in pool:
		total += e[1]
	var h := id.hash()
	var loot: float = GameState.difficulty().loot
	var rolls := int(plan[1]) + int(_rand(h, 0) * (int(plan[2]) - int(plan[1]) + 1) * minf(loot, 1.5))
	# Some containers have been picked over in the weeks since the outbreak.
	if _rand(h, 1) > 0.8 * loot:
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


## One item rolled from a pool (e.g. what a dead soldier carried).
static func roll_from(pool_name: String, h: int) -> Dictionary:
	var pool: Array = POOLS[pool_name]
	var total := 0.0
	for e in pool:
		total += e[1]
	var pick := _rand(h, 1) * total
	for e in pool:
		pick -= e[1]
		if pick <= 0.0:
			return roll_item(e[0], h)
	return roll_item(pool[-1][0], h)


## A found item with believable condition, ammo and stack size.
static func roll_item(id: String, h: int) -> Dictionary:
	var d := ItemDB.get_def(id)
	var n := 1
	if COUNTS.has(id):
		var c: Array = COUNTS[id]
		n = int(c[0]) + int(_rand(h, 3) * (int(c[1]) - int(c[0]) + 1))
	var it := ItemDB.make(id, n, 0.35 + _rand(h, 4) * 0.6)
	if d.has("col"):
		it.v = int(_rand(h, 6) * (d.col as Array).size()) % (d.col as Array).size()
	if d.has("uses"):
		it.u = 1 + int(_rand(h, 7) * int(d.uses))
	if d.get("cat", "") == "gun":
		it.a = int(_rand(h, 5) * 0.7 * int(d.mag))
	# With the power off for a while, fresh food found now has mostly gone off.
	if d.has("life") and not GameState.grid_on() and _rand(h, 8) < 0.8:
		it.exp = GameState.hours() - 1.0
	return it


static func label(type: String) -> String:
	return NAMES.get(type, "Container")
