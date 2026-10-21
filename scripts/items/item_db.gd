class_name ItemDB
extends RefCounted
## Every item in the game. Plain data, so the same definitions can later be
## sent over the network or modded.
##
## Common fields: name, cat (category), w x h (grid cells, unrotated), kg
## (weight), stack (max per cell). Category fields:
##   food / drink / medical: hunger, thirst, health
##   melee: dmg, cd (seconds between swings), reach, stam, wear (condition lost
##          per hit), heavy (knocks zombies down)
##   gun:   slot, ammo, mag, dmg, cd, auto, pellets, spread / ads_spread
##          (degrees), recoil (degrees), noise (metres), reload (seconds; per
##          round if per_round), reach, sight (height of the sights above the
##          grip, for aiming down sights)
##   bow:   ammo, dmg, draw (full draw time) or reload (crossbow), speed
##   throw: effect (noise / bottle / fire / explode / trap)
##   attachment: part (scope / sight / muzzle / light), fits (gun ids)
##   bag:   slot (back / vest), gw x gh (the grid it adds)
##   clothing: slot (head / torso / jacket / legs / feet), covers (body areas:
##          head, torso, arms, legs, feet), bite / scratch (chance 0..1 that it
##          stops a bite / scratch breaking the skin, at full condition),
##          warmth, look (how it's drawn on a body), col (colour variants),
##          gw x gh (pockets it adds, optional)
##   medical: treats (injury kinds it treats: bleed, deep, fracture,
##          wound_infection, infection, pain), uses (charges, for kits)

const CAT_COLORS := {
	"food": Color(0.55, 0.42, 0.22), "drink": Color(0.22, 0.42, 0.6), "medical": Color(0.62, 0.22, 0.22),
	"melee": Color(0.42, 0.36, 0.3), "gun": Color(0.3, 0.32, 0.34), "bow": Color(0.36, 0.4, 0.28),
	"ammo": Color(0.5, 0.45, 0.25), "throw": Color(0.45, 0.3, 0.2), "attachment": Color(0.3, 0.3, 0.4),
	"bag": Color(0.3, 0.38, 0.3), "clothing": Color(0.34, 0.3, 0.38), "key": Color(0.25, 0.42, 0.45),
	"misc": Color(0.4, 0.38, 0.32),
}

const ITEMS := {
	# --- Food and drink --------------------------------------------------------
	"canned_beans": {"name": "Canned Beans", "cat": "food", "w": 1, "h": 1, "kg": 0.45, "stack": 1, "hunger": 35.0, "thirst": -4.0},
	"canned_soup": {"name": "Canned Soup", "cat": "food", "w": 1, "h": 1, "kg": 0.45, "stack": 1, "hunger": 25.0, "thirst": 10.0},
	"crackers": {"name": "Crackers", "cat": "food", "w": 2, "h": 1, "kg": 0.25, "stack": 1, "hunger": 20.0, "thirst": -6.0},
	"chips": {"name": "Potato Chips", "cat": "food", "w": 1, "h": 2, "kg": 0.15, "stack": 1, "hunger": 15.0, "thirst": -8.0},
	"energy_bar": {"name": "Energy Bar", "cat": "food", "w": 1, "h": 1, "kg": 0.08, "stack": 3, "hunger": 18.0, "stamina": 30.0},
	"mre": {"name": "MRE Ration", "cat": "food", "w": 1, "h": 2, "kg": 0.6, "stack": 1, "hunger": 60.0, "thirst": 5.0},
	"water_bottle": {"name": "Water Bottle", "cat": "drink", "w": 1, "h": 2, "kg": 0.55, "stack": 1, "thirst": 40.0},
	"soda": {"name": "Soda Can", "cat": "drink", "w": 1, "h": 1, "kg": 0.36, "stack": 1, "thirst": 25.0, "hunger": 4.0},
	# --- Medical ---------------------------------------------------------------
	"bandage": {"name": "Bandage", "cat": "medical", "w": 1, "h": 1, "kg": 0.05, "stack": 4, "health": 5.0, "treats": ["bleed"]},
	"rag": {"name": "Rag", "cat": "medical", "w": 1, "h": 1, "kg": 0.05, "stack": 6, "health": 2.0, "treats": ["bleed"], "dirty": true},
	"painkillers": {"name": "Painkillers", "cat": "medical", "w": 1, "h": 1, "kg": 0.05, "stack": 1, "health": 5.0, "stamina": 40.0, "treats": ["pain"]},
	"first_aid_kit": {"name": "First Aid Kit", "cat": "medical", "w": 2, "h": 2, "kg": 0.8, "stack": 1, "health": 40.0,
		"treats": ["bleed", "deep", "wound_infection"]},
	"alcohol_wipes": {"name": "Alcohol Wipes", "cat": "medical", "w": 1, "h": 1, "kg": 0.03, "stack": 5, "treats": ["wound_infection"]},
	"suture_kit": {"name": "Suture Kit", "cat": "medical", "w": 1, "h": 1, "kg": 0.1, "stack": 3, "treats": ["deep"]},
	"splint": {"name": "Splint", "cat": "medical", "w": 1, "h": 2, "kg": 0.3, "stack": 1, "treats": ["fracture"]},
	"antibiotics": {"name": "Antibiotics", "cat": "medical", "w": 1, "h": 1, "kg": 0.05, "stack": 1, "treats": ["wound_infection", "infection"]},
	"cure_vial": {"name": "Cure Vial", "cat": "medical", "w": 1, "h": 1, "kg": 0.1, "stack": 1, "treats": ["cure"]},
	# --- Misc --------------------------------------------------------------------
	"cigarettes": {"name": "Cigarettes", "cat": "misc", "w": 1, "h": 1, "kg": 0.03, "stack": 1, "uses": 10},
	"sewing_kit": {"name": "Sewing Kit", "cat": "misc", "w": 1, "h": 1, "kg": 0.15, "stack": 1, "uses": 5},
	"keycard_blue": {"name": "Blue Keycard", "cat": "key", "w": 1, "h": 1, "kg": 0.01, "stack": 1},
	"keycard_red": {"name": "Red Keycard", "cat": "key", "w": 1, "h": 1, "kg": 0.01, "stack": 1},
	# --- Melee -----------------------------------------------------------------
	"kitchen_knife": {"name": "Kitchen Knife", "cat": "melee", "w": 2, "h": 1, "kg": 0.2, "stack": 1,
		"dmg": 22.0, "cd": 0.4, "reach": 1.8, "stam": 4.0, "wear": 0.015},
	"hunting_knife": {"name": "Hunting Knife", "cat": "melee", "w": 2, "h": 1, "kg": 0.3, "stack": 1,
		"dmg": 30.0, "cd": 0.42, "reach": 1.9, "stam": 4.5, "wear": 0.007},
	"hammer": {"name": "Claw Hammer", "cat": "melee", "w": 2, "h": 1, "kg": 0.7, "stack": 1,
		"dmg": 28.0, "cd": 0.5, "reach": 2.0, "stam": 5.0, "wear": 0.006},
	"crowbar": {"name": "Crowbar", "cat": "melee", "w": 3, "h": 1, "kg": 1.5, "stack": 1,
		"dmg": 34.0, "cd": 0.6, "reach": 2.4, "stam": 6.0, "wear": 0.003},
	"machete": {"name": "Machete", "cat": "melee", "w": 3, "h": 1, "kg": 0.7, "stack": 1,
		"dmg": 42.0, "cd": 0.58, "reach": 2.4, "stam": 6.0, "wear": 0.008},
	"baseball_bat": {"name": "Baseball Bat", "cat": "melee", "w": 4, "h": 1, "kg": 1.0, "stack": 1,
		"dmg": 36.0, "cd": 0.6, "reach": 2.6, "stam": 6.5, "wear": 0.01},
	"fire_axe": {"name": "Fire Axe", "cat": "melee", "w": 4, "h": 1, "kg": 2.5, "stack": 1,
		"dmg": 55.0, "cd": 0.85, "reach": 2.6, "stam": 10.0, "wear": 0.005},
	"sledgehammer": {"name": "Sledgehammer", "cat": "melee", "w": 4, "h": 2, "kg": 5.0, "stack": 1,
		"dmg": 75.0, "cd": 1.2, "reach": 2.7, "stam": 15.0, "wear": 0.003, "heavy": true},
	# --- Guns ------------------------------------------------------------------
	"pistol_9mm": {"name": "9mm Pistol", "cat": "gun", "slot": "sidearm", "w": 2, "h": 2, "kg": 0.9, "stack": 1,
		"ammo": "ammo_9mm", "mag": 15, "dmg": 28.0, "cd": 0.16, "spread": 3.0, "ads_spread": 0.7, "recoil": 2.2,
		"noise": 70.0, "reload": 1.6, "reach": 60.0, "sight": 0.063, "zoom": 60.0},
	"revolver": {"name": ".357 Revolver", "cat": "gun", "slot": "sidearm", "w": 2, "h": 2, "kg": 1.1, "stack": 1,
		"ammo": "ammo_357", "mag": 6, "dmg": 55.0, "cd": 0.42, "spread": 3.5, "ads_spread": 0.5, "recoil": 5.0,
		"noise": 85.0, "reload": 0.45, "per_round": true, "reach": 70.0, "sight": 0.06, "zoom": 58.0},
	"pump_shotgun": {"name": "Pump Shotgun", "cat": "gun", "slot": "primary", "w": 4, "h": 1, "kg": 3.4, "stack": 1,
		"ammo": "ammo_12g", "mag": 5, "dmg": 14.0, "pellets": 8, "cd": 0.85, "spread": 5.0, "ads_spread": 3.5,
		"recoil": 7.0, "noise": 95.0, "reload": 0.55, "per_round": true, "reach": 30.0, "sight": 0.04, "zoom": 62.0},
	"hunting_rifle": {"name": "Hunting Rifle", "cat": "gun", "slot": "primary", "w": 5, "h": 1, "kg": 3.8, "stack": 1,
		"ammo": "ammo_308", "mag": 5, "dmg": 95.0, "cd": 1.15, "spread": 4.0, "ads_spread": 0.15, "recoil": 8.0,
		"noise": 120.0, "reload": 0.6, "per_round": true, "reach": 250.0, "sight": 0.045, "zoom": 50.0},
	"assault_rifle": {"name": "Assault Rifle", "cat": "gun", "slot": "primary", "w": 4, "h": 2, "kg": 3.5, "stack": 1,
		"ammo": "ammo_556", "mag": 30, "dmg": 34.0, "cd": 0.1, "auto": true, "spread": 4.0, "ads_spread": 0.9,
		"recoil": 1.8, "noise": 110.0, "reload": 2.2, "reach": 150.0, "sight": 0.07, "zoom": 52.0},
	# --- Bows ------------------------------------------------------------------
	"compound_bow": {"name": "Compound Bow", "cat": "bow", "slot": "primary", "w": 2, "h": 4, "kg": 1.8, "stack": 1,
		"ammo": "arrow", "mag": 1, "dmg": 85.0, "draw": 0.7, "speed": 55.0, "noise": 3.0, "sight": 0.0, "zoom": 60.0},
	"crossbow": {"name": "Crossbow", "cat": "bow", "slot": "primary", "w": 3, "h": 2, "kg": 3.0, "stack": 1,
		"ammo": "bolt", "mag": 1, "dmg": 110.0, "reload": 2.2, "per_round": true, "speed": 75.0, "noise": 4.0,
		"sight": 0.045, "zoom": 55.0},
	# --- Ammo ------------------------------------------------------------------
	"ammo_9mm": {"name": "9mm Rounds", "cat": "ammo", "w": 1, "h": 1, "kg": 0.012, "stack": 50},
	"ammo_357": {"name": ".357 Rounds", "cat": "ammo", "w": 1, "h": 1, "kg": 0.016, "stack": 36},
	"ammo_12g": {"name": "12ga Shells", "cat": "ammo", "w": 1, "h": 1, "kg": 0.04, "stack": 20},
	"ammo_308": {"name": ".308 Rounds", "cat": "ammo", "w": 1, "h": 1, "kg": 0.025, "stack": 30},
	"ammo_556": {"name": "5.56 Rounds", "cat": "ammo", "w": 1, "h": 1, "kg": 0.012, "stack": 60},
	"arrow": {"name": "Arrows", "cat": "ammo", "w": 3, "h": 1, "kg": 0.03, "stack": 12},
	"bolt": {"name": "Crossbow Bolts", "cat": "ammo", "w": 2, "h": 1, "kg": 0.03, "stack": 12},
	# --- Throwables and traps --------------------------------------------------
	"glass_bottle": {"name": "Empty Bottle", "cat": "throw", "w": 1, "h": 2, "kg": 0.3, "stack": 1, "effect": "bottle"},
	"noise_maker": {"name": "Alarm Clock", "cat": "throw", "w": 1, "h": 1, "kg": 0.3, "stack": 1, "effect": "noise"},
	"molotov": {"name": "Molotov", "cat": "throw", "w": 1, "h": 2, "kg": 0.6, "stack": 1, "effect": "fire"},
	"grenade": {"name": "Grenade", "cat": "throw", "w": 1, "h": 1, "kg": 0.4, "stack": 2, "effect": "explode"},
	"bear_trap": {"name": "Bear Trap", "cat": "throw", "w": 2, "h": 2, "kg": 3.0, "stack": 1, "effect": "trap"},
	# --- Attachments -----------------------------------------------------------
	"scope": {"name": "Rifle Scope", "cat": "attachment", "w": 2, "h": 1, "kg": 0.4, "stack": 1, "part": "scope",
		"fits": ["hunting_rifle", "assault_rifle", "crossbow"], "zoom": 22.0},
	"red_dot": {"name": "Red Dot Sight", "cat": "attachment", "w": 1, "h": 1, "kg": 0.15, "stack": 1, "part": "scope",
		"fits": ["pistol_9mm", "pump_shotgun", "assault_rifle", "crossbow"], "zoom": 50.0},
	"suppressor": {"name": "Suppressor", "cat": "attachment", "w": 2, "h": 1, "kg": 0.3, "stack": 1, "part": "muzzle",
		"fits": ["pistol_9mm", "assault_rifle", "hunting_rifle"]},
	"weapon_light": {"name": "Weapon Light", "cat": "attachment", "w": 1, "h": 1, "kg": 0.12, "stack": 1, "part": "light",
		"fits": ["pistol_9mm", "revolver", "pump_shotgun", "assault_rifle", "hunting_rifle"]},
	# --- Bags ------------------------------------------------------------------
	"school_backpack": {"name": "School Backpack", "cat": "bag", "slot": "back", "w": 2, "h": 2, "kg": 0.5, "stack": 1, "gw": 4, "gh": 4},
	"hiking_backpack": {"name": "Hiking Backpack", "cat": "bag", "slot": "back", "w": 3, "h": 3, "kg": 1.2, "stack": 1, "gw": 6, "gh": 5},
	"military_backpack": {"name": "Military Backpack", "cat": "bag", "slot": "back", "w": 3, "h": 3, "kg": 1.6, "stack": 1, "gw": 7, "gh": 6},
	"tactical_vest": {"name": "Tactical Vest", "cat": "bag", "slot": "vest", "w": 2, "h": 3, "kg": 1.4, "stack": 1, "gw": 5, "gh": 2},
	# --- Clothing ----------------------------------------------------------------
	"baseball_cap": {"name": "Baseball Cap", "cat": "clothing", "slot": "head", "w": 1, "h": 1, "kg": 0.1, "stack": 1,
		"covers": ["head"], "bite": 0.0, "scratch": 0.1, "warmth": 0.5, "look": "cap",
		"col": [Color(0.15, 0.2, 0.45), Color(0.6, 0.12, 0.1), Color(0.15, 0.15, 0.15)]},
	"beanie": {"name": "Beanie", "cat": "clothing", "slot": "head", "w": 1, "h": 1, "kg": 0.1, "stack": 1,
		"covers": ["head"], "bite": 0.05, "scratch": 0.15, "warmth": 2.0, "look": "beanie",
		"col": [Color(0.2, 0.2, 0.22), Color(0.5, 0.15, 0.12), Color(0.3, 0.35, 0.25)]},
	"motorcycle_helmet": {"name": "Motorcycle Helmet", "cat": "clothing", "slot": "head", "w": 2, "h": 2, "kg": 1.4, "stack": 1,
		"covers": ["head"], "bite": 0.7, "scratch": 0.9, "warmth": 1.0, "look": "helmet",
		"col": [Color(0.1, 0.1, 0.1), Color(0.75, 0.1, 0.08), Color(0.85, 0.85, 0.85)]},
	"riot_helmet": {"name": "Riot Helmet", "cat": "clothing", "slot": "head", "w": 2, "h": 2, "kg": 1.2, "stack": 1,
		"covers": ["head"], "bite": 0.8, "scratch": 0.9, "warmth": 1.0, "look": "helmet", "col": [Color(0.12, 0.13, 0.16)]},
	"military_helmet": {"name": "Military Helmet", "cat": "clothing", "slot": "head", "w": 2, "h": 2, "kg": 1.5, "stack": 1,
		"covers": ["head"], "bite": 0.7, "scratch": 0.85, "warmth": 1.0, "look": "army_helmet", "col": [Color(0.3, 0.33, 0.22)]},
	"t_shirt": {"name": "T-Shirt", "cat": "clothing", "slot": "torso", "w": 2, "h": 2, "kg": 0.2, "stack": 1,
		"covers": ["torso"], "bite": 0.02, "scratch": 0.1, "warmth": 1.0, "look": "tee",
		"col": [Color(0.55, 0.22, 0.18), Color(0.85, 0.85, 0.82), Color(0.2, 0.3, 0.5), Color(0.25, 0.25, 0.25), Color(0.4, 0.5, 0.3)]},
	"flannel_shirt": {"name": "Flannel Shirt", "cat": "clothing", "slot": "torso", "w": 2, "h": 2, "kg": 0.4, "stack": 1,
		"covers": ["torso", "arms"], "bite": 0.05, "scratch": 0.2, "warmth": 2.0, "look": "long",
		"col": [Color(0.6, 0.15, 0.12), Color(0.2, 0.35, 0.25), Color(0.25, 0.3, 0.5)]},
	"uniform_shirt": {"name": "Uniform Shirt", "cat": "clothing", "slot": "torso", "w": 2, "h": 2, "kg": 0.35, "stack": 1,
		"covers": ["torso", "arms"], "bite": 0.05, "scratch": 0.2, "warmth": 1.5, "look": "long", "extra": "badge",
		"col": [Color(0.12, 0.16, 0.3), Color(0.5, 0.48, 0.38)]},
	"scrubs_top": {"name": "Scrubs Top", "cat": "clothing", "slot": "torso", "w": 2, "h": 2, "kg": 0.2, "stack": 1,
		"covers": ["torso"], "bite": 0.02, "scratch": 0.1, "warmth": 0.8, "look": "tee",
		"col": [Color(0.45, 0.65, 0.68), Color(0.35, 0.45, 0.6)]},
	"lab_coat": {"name": "Lab Coat", "cat": "clothing", "slot": "jacket", "w": 2, "h": 3, "kg": 0.6, "stack": 1,
		"covers": ["torso", "arms"], "bite": 0.08, "scratch": 0.25, "warmth": 1.0, "look": "coat", "gw": 2, "gh": 1,
		"col": [Color(0.88, 0.89, 0.88)]},
	"hoodie": {"name": "Hoodie", "cat": "clothing", "slot": "jacket", "w": 2, "h": 2, "kg": 0.6, "stack": 1,
		"covers": ["torso", "arms"], "bite": 0.1, "scratch": 0.3, "warmth": 3.0, "look": "hoodie", "gw": 2, "gh": 1,
		"col": [Color(0.3, 0.32, 0.3), Color(0.15, 0.15, 0.17), Color(0.45, 0.12, 0.12), Color(0.2, 0.28, 0.45)]},
	"leather_jacket": {"name": "Leather Jacket", "cat": "clothing", "slot": "jacket", "w": 2, "h": 3, "kg": 1.6, "stack": 1,
		"covers": ["torso", "arms"], "bite": 0.45, "scratch": 0.7, "warmth": 3.0, "look": "jacket", "gw": 2, "gh": 1,
		"col": [Color(0.12, 0.1, 0.09), Color(0.32, 0.2, 0.12)]},
	"hunting_jacket": {"name": "Hunting Jacket", "cat": "clothing", "slot": "jacket", "w": 2, "h": 3, "kg": 1.3, "stack": 1,
		"covers": ["torso", "arms"], "bite": 0.25, "scratch": 0.55, "warmth": 4.0, "look": "jacket", "gw": 3, "gh": 2,
		"col": [Color(0.32, 0.3, 0.2), Color(0.85, 0.4, 0.1)]},
	"firefighter_jacket": {"name": "Firefighter Jacket", "cat": "clothing", "slot": "jacket", "w": 2, "h": 3, "kg": 2.2, "stack": 1,
		"covers": ["torso", "arms"], "bite": 0.4, "scratch": 0.7, "warmth": 4.0, "look": "jacket", "extra": "vest", "fire": 0.7,
		"col": [Color(0.55, 0.48, 0.3)]},
	"riot_armor": {"name": "Riot Armor", "cat": "clothing", "slot": "jacket", "w": 3, "h": 3, "kg": 6.0, "stack": 1,
		"covers": ["torso", "arms"], "bite": 0.75, "scratch": 0.9, "warmth": 2.0, "look": "armor", "col": [Color(0.12, 0.13, 0.16)]},
	"military_armor": {"name": "Military Armor", "cat": "clothing", "slot": "jacket", "w": 3, "h": 3, "kg": 8.0, "stack": 1,
		"covers": ["torso", "arms"], "bite": 0.85, "scratch": 0.95, "warmth": 2.0, "look": "armor", "gw": 4, "gh": 1,
		"col": [Color(0.3, 0.33, 0.22)]},
	"jeans": {"name": "Jeans", "cat": "clothing", "slot": "legs", "w": 2, "h": 2, "kg": 0.7, "stack": 1,
		"covers": ["legs"], "bite": 0.15, "scratch": 0.4, "warmth": 2.0, "look": "pants",
		"col": [Color(0.2, 0.26, 0.4), Color(0.12, 0.13, 0.17), Color(0.4, 0.45, 0.55)]},
	"cargo_pants": {"name": "Cargo Pants", "cat": "clothing", "slot": "legs", "w": 2, "h": 2, "kg": 0.8, "stack": 1,
		"covers": ["legs"], "bite": 0.15, "scratch": 0.45, "warmth": 2.0, "look": "pants", "gw": 4, "gh": 1,
		"col": [Color(0.42, 0.4, 0.3), Color(0.25, 0.27, 0.2), Color(0.18, 0.18, 0.2)]},
	"work_pants": {"name": "Work Pants", "cat": "clothing", "slot": "legs", "w": 2, "h": 2, "kg": 1.0, "stack": 1,
		"covers": ["legs"], "bite": 0.3, "scratch": 0.6, "warmth": 2.5, "look": "pants",
		"col": [Color(0.3, 0.3, 0.28), Color(0.45, 0.35, 0.2)]},
	"scrubs_pants": {"name": "Scrubs Pants", "cat": "clothing", "slot": "legs", "w": 2, "h": 2, "kg": 0.2, "stack": 1,
		"covers": ["legs"], "bite": 0.02, "scratch": 0.1, "warmth": 0.8, "look": "pants",
		"col": [Color(0.45, 0.65, 0.68), Color(0.35, 0.45, 0.6)]},
	"military_pants": {"name": "Military Pants", "cat": "clothing", "slot": "legs", "w": 2, "h": 2, "kg": 1.0, "stack": 1,
		"covers": ["legs"], "bite": 0.3, "scratch": 0.6, "warmth": 2.5, "look": "pants", "gw": 2, "gh": 1,
		"col": [Color(0.28, 0.3, 0.2)]},
	"sneakers": {"name": "Sneakers", "cat": "clothing", "slot": "feet", "w": 2, "h": 1, "kg": 0.6, "stack": 1,
		"covers": ["feet"], "bite": 0.05, "scratch": 0.2, "warmth": 0.5, "look": "shoes",
		"col": [Color(0.85, 0.85, 0.85), Color(0.15, 0.15, 0.15), Color(0.6, 0.15, 0.1)]},
	"work_boots": {"name": "Work Boots", "cat": "clothing", "slot": "feet", "w": 2, "h": 1, "kg": 1.4, "stack": 1,
		"covers": ["feet"], "bite": 0.45, "scratch": 0.8, "warmth": 1.5, "look": "boots", "col": [Color(0.35, 0.22, 0.12)]},
	"military_boots": {"name": "Military Boots", "cat": "clothing", "slot": "feet", "w": 2, "h": 1, "kg": 1.5, "stack": 1,
		"covers": ["feet"], "bite": 0.5, "scratch": 0.85, "warmth": 2.0, "look": "boots", "col": [Color(0.1, 0.09, 0.08)]},
}

## Body areas clothing covers, for each injury location.
const PART_AREA := {"head": "head", "torso": "torso", "arm_l": "arms", "arm_r": "arms", "leg_l": "legs", "leg_r": "legs"}
const PART_NAMES := {"head": "Head", "torso": "Torso", "arm_l": "Left arm", "arm_r": "Right arm", "leg_l": "Left leg", "leg_r": "Right leg"}
const CLOTHING_SLOTS := ["head", "torso", "jacket", "legs", "feet"]

## Bare hands: what you fight with when no melee weapon is equipped.
const FISTS := {"name": "Fists", "cat": "melee", "dmg": 9.0, "cd": 0.45, "reach": 1.8, "stam": 4.0, "wear": 0.0}

## Equipment slots and the categories they take.
const SLOTS := ["primary", "sidearm", "melee", "throw", "back", "vest", "head", "torso", "jacket", "legs", "feet"]
const SLOT_NAMES := {"primary": "Primary", "sidearm": "Sidearm", "melee": "Melee", "throw": "Throwable",
	"back": "Backpack", "vest": "Vest", "head": "Head", "torso": "Shirt", "jacket": "Jacket", "legs": "Pants",
	"feet": "Shoes"}


static func get_def(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func item_name(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id)


## Which equipment slot an item goes in ("" if none).
static func slot_for(id: String) -> String:
	var d := get_def(id)
	match d.get("cat", ""):
		"gun", "bow", "bag", "clothing":
			return d.slot
		"melee":
			return "melee"
		"throw":
			return "throw"
	return ""


static func is_ranged(id: String) -> bool:
	return get_def(id).get("cat", "") in ["gun", "bow"]


static func is_consumable(id: String) -> bool:
	return get_def(id).get("cat", "") in ["food", "drink", "medical"] or id == "cigarettes"


## A fresh item instance (the data that lives in grids, slots and saves):
##   id, n (count), c (condition 0..1), a (rounds loaded), att (part -> id),
##   items (contents of bags and pockets), u (uses left), v (colour variant),
##   x, y, r (grid position and rotation).
static func make(id: String, count := 1, condition := 1.0) -> Dictionary:
	var it := {"id": id, "n": count}
	var d := get_def(id)
	if d.get("cat", "") in ["melee", "gun", "bow", "clothing"]:
		it.c = condition
	if d.has("uses"):
		it.u = int(d.uses)
	if d.has("col"):
		it.v = 0
	if d.get("cat", "") in ["gun", "bow"]:
		it.a = 0
		it.att = {}
	if d.get("cat", "") == "bag" or d.has("gw"):
		it.items = []
	return it


## Total weight of an item, including bag contents and loaded rounds.
static func weight(it: Dictionary) -> float:
	var d := get_def(it.id)
	var kg: float = d.get("kg", 0.1) * int(it.get("n", 1))
	for sub in it.get("items", []):
		kg += weight(sub)
	for part in it.get("att", {}).values():
		kg += get_def(part).get("kg", 0.1)
	return kg


## One-line summary for the inventory's detail panel.
static func describe(it: Dictionary) -> String:
	var d := get_def(it.id)
	var parts: Array[String] = []
	match d.get("cat", ""):
		"food", "drink", "medical":
			for k: String in ["hunger", "thirst", "health", "stamina"]:
				if d.has(k):
					parts.append("%s %+d" % [k.capitalize(), int(d[k])])
			for t: String in d.get("treats", []):
				parts.append({"bleed": "Stops bleeding", "deep": "Closes deep wounds", "fracture": "Sets broken bones",
					"wound_infection": "Treats wound infection", "infection": "Slows zombie infection",
					"pain": "Eases pain", "cure": "Cures zombie infection"}[t])
		"melee":
			parts.append("Damage %d" % int(d.dmg))
			parts.append("Speed %.1f/s" % (1.0 / float(d.cd)))
		"gun":
			parts.append("Damage %d%s" % [int(d.dmg), " x%d" % int(d.pellets) if d.has("pellets") else ""])
			parts.append("%d / %d %s" % [int(it.get("a", 0)), int(d.mag), item_name(d.ammo)])
			for part in it.get("att", {}).values():
				parts.append(item_name(part))
		"bow":
			parts.append("Damage %d" % int(d.dmg))
			parts.append("Uses %s" % item_name(d.ammo))
		"ammo":
			parts.append("%d rounds" % int(it.get("n", 1)))
		"attachment":
			parts.append("Fits: " + ", ".join(d.fits.map(func(g: String) -> String: return item_name(g))))
		"bag":
			parts.append("Adds %d x %d slots" % [int(d.gw), int(d.gh)])
		"clothing":
			parts.append("Bite %d%%" % int(float(d.bite) * 100.0 * float(it.get("c", 1.0))))
			parts.append("Scratch %d%%" % int(float(d.scratch) * 100.0 * float(it.get("c", 1.0))))
			parts.append("Warmth %.1f" % float(d.warmth))
			if d.has("gw"):
				parts.append("Pockets %d x %d" % [int(d.gw), int(d.gh)])
		"key":
			parts.append("Opens security doors (needs power)")
		"misc":
			parts.append("%d uses left" % int(it.get("u", 1)))
		"throw":
			parts.append({"bottle": "Shatters loudly: distracts zombies", "noise": "Rings for 15 s: lures zombies",
				"fire": "Sets an area on fire", "explode": "Explodes after 3 s", "trap": "Place on the ground; holds and hurts"}[d.effect])
	if it.has("c"):
		parts.append("Condition %d%%" % int(float(it.c) * 100.0))
	parts.append("%.1f kg" % weight(it))
	return "  -  ".join(parts)
