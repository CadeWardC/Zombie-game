class_name Barter
extends RefCounted
## Trading at trader camps: what things are worth (barter only, no money)
## and what each trader has. Traders restock every few days and carry rare
## goods you can hardly find anywhere else: engine parts for aircraft,
## antibiotics, military ammo, seeds.

const RESTOCK_HOURS := 72.0

## Value of one item by category; specific items override it.
const CAT_VALUE := {"food": 6, "drink": 5, "medical": 10, "melee": 14, "gun": 60, "bow": 40, "ammo": 1,
	"throw": 8, "attachment": 25, "bag": 20, "clothing": 10, "misc": 6, "part": 25, "material": 3, "tool": 12,
	"seed": 4, "key": 0}
const VALUE := {
	"canned_beans": 8, "canned_soup": 8, "mre": 16, "water_bottle": 7, "energy_bar": 5, "stew": 12,
	"antibiotics": 45, "first_aid_kit": 30, "suture_kit": 14, "painkillers": 9, "bandage": 5, "cure_vial": 400,
	"ammo_9mm": 1, "ammo_357": 2, "ammo_12g": 2, "ammo_308": 3, "ammo_556": 2, "arrow": 2, "bolt": 2,
	"pistol_9mm": 55, "revolver": 60, "pump_shotgun": 75, "hunting_rifle": 90, "assault_rifle": 140,
	"compound_bow": 45, "crossbow": 55, "suppressor": 60, "scope": 35, "grenade": 25, "molotov": 10,
	"engine_parts": 40, "car_battery": 25, "car_tire": 18, "gas_can": 12, "jet_fuel_can": 18, "screwdriver": 6,
	"military_armor": 80, "riot_armor": 55, "military_helmet": 40, "military_backpack": 45, "hiking_backpack": 28,
	"tactical_vest": 35, "nails": 0, "plank": 3, "log": 4, "scrap_metal": 4, "duct_tape": 8, "rope": 5,
	"purification_tablets": 12, "sleeping_bag": 18, "fishing_rod": 14, "saw": 14, "cooking_pot": 10, "lighter": 8,
	"matches": 5, "cigarettes": 9, "raw_meat": 6, "cooked_meat": 9, "animal_hide": 10, "feathers": 0,
	"winter_coat": 22, "raincoat": 12, "dog_food": 6,
	"peanut_butter": 12, "coffee": 8, "vitamins": 12, "batteries": 3, "binoculars": 18, "wallet": 2, "watch": 10,
	"car_keys": 4, "pickaxe": 20, "pipe_wrench": 16, "wire": 3, "glue": 5, "tarp": 8, "cloth": 2,
}

## What traders sell: [id, count, weight]. Rare goods first.
const STOCK := [
	["engine_parts", 1, 2.0], ["antibiotics", 1, 2.0], ["ammo_556", 30, 1.5], ["ammo_308", 10, 1.5],
	["purification_tablets", 1, 1.5], ["seeds_potato", 6, 1.5], ["seeds_carrot", 6, 1.2], ["seeds_tomato", 6, 1.2],
	["seeds_corn", 6, 1.2], ["first_aid_kit", 1, 1.0], ["suture_kit", 2, 1.0], ["mre", 1, 1.5], ["water_bottle", 1, 1.5],
	["jet_fuel_can", 1, 1.0], ["gas_can", 1, 1.2], ["car_battery", 1, 0.8], ["car_tire", 1, 0.6], ["nails", 40, 1.5],
	["duct_tape", 1, 1.0], ["rope", 2, 0.8], ["saw", 1, 0.6], ["fishing_rod", 1, 0.6], ["sleeping_bag", 1, 0.5],
	["winter_coat", 1, 0.5], ["hunting_rifle", 1, 0.3], ["crossbow", 1, 0.25], ["military_armor", 1, 0.15],
	["suppressor", 1, 0.1], ["cure_vial", 1, 0.04], ["lighter", 1, 1.0], ["cooking_pot", 1, 0.6],
	["military_backpack", 1, 0.2], ["scope", 1, 0.3], ["dog_food", 2, 0.8],
]


static func value(it: Dictionary) -> int:
	var d := ItemDB.get_def(it.id)
	var v: float = VALUE.get(it.id, CAT_VALUE.get(d.get("cat", ""), 5))
	if it.id == "nails":
		v = 0.25
	elif it.id == "feathers":
		v = 0.2
	# Worn things are worth less; spoiled food nothing; charges count.
	if it.has("c"):
		v *= lerpf(0.3, 1.0, float(it.c))
	if ItemDB.is_rotten(it):
		v = 0.0
	if d.has("uses") and int(d.uses) > 0:
		v *= clampf(float(it.get("u", d.uses)) / float(d.uses), 0.1, 1.0)
	return int(ceilf(v * int(it.get("n", 1)))) if v > 0.0 else 0


## A camp's goods, restocked when due.
static func stock(camp: String) -> Array:
	var rec: Dictionary = GameState.ws.traders.get(camp, {})
	if rec.is_empty() or GameState.hours() >= float(rec.get("restock", 0.0)):
		var rng := RandomNumberGenerator.new()
		rng.seed = camp.hash() + int(GameState.hours() / RESTOCK_HOURS) * 7919
		var items := []
		var total := 0.0
		for e in STOCK:
			total += float(e[2])
		for k in 12:
			var pick := rng.randf() * total
			for e in STOCK:
				pick -= float(e[2])
				if pick <= 0.0:
					var it := ItemDB.make(e[0], int(e[1]))
					var merged := false
					for o in items:
						if o.id == it.id and int(ItemDB.get_def(it.id).get("stack", 1)) > 1:
							o.n = int(o.n) + int(it.n)
							merged = true
					if not merged:
						items.append(it)
					break
		rec = {"stock": items, "restock": GameState.hours() + RESTOCK_HOURS}
		GameState.ws.traders[camp] = rec
	return rec.stock
