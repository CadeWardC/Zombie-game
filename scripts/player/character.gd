class_name Character
extends RefCounted
## Who the survivor is: name, appearance, background (past job), traits and
## skills. Pure data, saved with the world, so in multiplayer each player's
## character can be sent to the host.
##
## Traits and backgrounds change the game through modifiers: mod("melee")
## multiplies melee damage, mod("bleed") bleeding, and so on. Skills are
## levels 0..10; a few already matter (aiming, melee, first aid, stealth,
## fitness, strength), the rest wait for crafting and vehicles.

const POINTS := 0 # Starting trait points before the background.
const SKIN_TONES := [Color(0.96, 0.8, 0.69), Color(0.87, 0.67, 0.52), Color(0.76, 0.56, 0.42),
	Color(0.6, 0.42, 0.3), Color(0.45, 0.3, 0.2), Color(0.32, 0.21, 0.15)]
const HAIR_COLORS := [Color(0.08, 0.06, 0.05), Color(0.3, 0.19, 0.1), Color(0.55, 0.38, 0.2),
	Color(0.8, 0.68, 0.45), Color(0.6, 0.25, 0.12), Color(0.6, 0.6, 0.58)]
const HAIR_STYLES := ["Short", "Long", "Ponytail", "Buzz cut", "Bald"]
const BEARDS := ["None", "Stubble", "Beard"]
const BUILDS := ["Masculine", "Feminine"]
const SKILLS := ["aiming", "melee", "first_aid", "stealth", "fitness", "strength", "mechanics", "carpentry",
	"farming", "cooking", "foraging", "piloting"]

## Past jobs. points: trait points it gives (or costs); skills: starting
## levels; items: [[id, count]]; clothes: [[id, variant]].
const BACKGROUNDS := {
	"unemployed": {"name": "Unemployed", "points": 8, "skills": {},
		"desc": "No head start, but more points for traits.",
		"items": [], "clothes": [["hoodie", 0], ["jeans", 0], ["sneakers", 0]]},
	"nurse": {"name": "Nurse", "points": 0, "skills": {"first_aid": 3},
		"desc": "Treats wounds faster and better. Starts with medical supplies.",
		"items": [["bandage", 2], ["alcohol_wipes", 3], ["suture_kit", 1]],
		"clothes": [["scrubs_top", 0], ["scrubs_pants", 0], ["sneakers", 0]]},
	"police": {"name": "Police Officer", "points": -2, "skills": {"aiming": 3, "melee": 1},
		"desc": "Steadier aim with guns.",
		"items": [["ammo_9mm", 8]], "clothes": [["uniform_shirt", 0], ["cargo_pants", 2], ["work_boots", 0]]},
	"mechanic": {"name": "Mechanic", "points": 0, "skills": {"mechanics": 3, "strength": 1},
		"desc": "Knows engines (vehicles come later). Starts with a hammer.",
		"items": [["hammer", 1]], "clothes": [["t_shirt", 3], ["work_pants", 0], ["work_boots", 0]]},
	"farmer": {"name": "Farmer", "points": 0, "skills": {"farming": 3, "strength": 1, "foraging": 1},
		"desc": "Hardy and practical.",
		"items": [["canned_beans", 1]], "clothes": [["flannel_shirt", 0], ["jeans", 0], ["work_boots", 0], ["baseball_cap", 1]]},
	"carpenter": {"name": "Carpenter", "points": 0, "skills": {"carpentry": 3, "melee": 1},
		"desc": "Good with a hammer, in every sense.",
		"items": [["hammer", 1]], "clothes": [["t_shirt", 0], ["work_pants", 1], ["work_boots", 0]]},
	"hunter": {"name": "Hunter", "points": -2, "skills": {"aiming": 2, "stealth": 2, "foraging": 1},
		"desc": "Quiet on their feet and a good shot.",
		"items": [["hunting_knife", 1]], "clothes": [["flannel_shirt", 1], ["hunting_jacket", 0], ["cargo_pants", 1], ["work_boots", 0]]},
	"pilot": {"name": "Pilot", "points": 0, "skills": {"piloting": 4},
		"desc": "Can fly the planes at the airports (later stage).",
		"items": [], "clothes": [["uniform_shirt", 1], ["jeans", 1], ["sneakers", 1]]},
	"firefighter": {"name": "Firefighter", "points": -2, "skills": {"fitness": 2, "strength": 2},
		"desc": "Fit and strong.",
		"items": [], "clothes": [["t_shirt", 3], ["work_pants", 0], ["work_boots", 0]]},
	"chef": {"name": "Chef", "points": 0, "skills": {"cooking": 3, "melee": 1},
		"desc": "Handy with a knife. Starts with extra food.",
		"items": [["canned_soup", 2]], "clothes": [["t_shirt", 1], ["jeans", 1], ["sneakers", 1]]},
}

## cost > 0: a good trait that costs points; cost < 0: a bad one that gives
## points. mods multiply game values (see the class comment).
const TRAITS := {
	"athletic": {"name": "Athletic", "cost": 4, "desc": "Sprint faster and tire less.", "mods": {"stamina": 0.75, "sprint": 1.08}, "not": "unfit"},
	"strong": {"name": "Strong", "cost": 4, "desc": "Hit harder and carry more.", "mods": {"melee": 1.25, "carry": 1.4}, "not": "weak"},
	"keen_hearing": {"name": "Keen Hearing", "cost": 3, "desc": "Sense zombies around you from farther away.", "mods": {"hearing": 1.8}},
	"thick_skinned": {"name": "Thick Skinned", "cost": 3, "desc": "Bites and scratches break the skin less often.", "mods": {"skin": 0.7}},
	"fast_healer": {"name": "Fast Healer", "cost": 3, "desc": "Wounds heal faster.", "mods": {"heal": 1.5}, "not": "slow_healer"},
	"fast_learner": {"name": "Fast Learner", "cost": 3, "desc": "Skills improve faster (skills grow in a later stage).", "mods": {"xp": 1.3}},
	"light_eater": {"name": "Light Eater", "cost": 2, "desc": "Gets hungry more slowly.", "mods": {"hunger": 0.75}, "not": "hearty_appetite"},
	"cat_eyes": {"name": "Cat's Eyes", "cost": 2, "desc": "See better at night.", "mods": {"night_vision": 1.8}},
	"short_sighted": {"name": "Short-Sighted", "cost": -2, "desc": "Far things fade into a blur.", "mods": {"view": 0.6}},
	"smoker": {"name": "Smoker", "cost": -2, "desc": "Craves cigarettes; tires faster while craving.", "mods": {}},
	"clumsy": {"name": "Clumsy", "cost": -2, "desc": "Louder footsteps.", "mods": {"noise": 1.5}},
	"heavy_sleeper": {"name": "Heavy Sleeper", "cost": -1, "desc": "Sleeps longer and wakes late (sleep comes in a later stage).", "mods": {}},
	"weak": {"name": "Weak", "cost": -3, "desc": "Hits softer and carries less.", "mods": {"melee": 0.8, "carry": 0.75}, "not": "strong"},
	"unfit": {"name": "Out of Shape", "cost": -3, "desc": "Runs out of breath quickly.", "mods": {"stamina": 1.35}, "not": "athletic"},
	"slow_healer": {"name": "Slow Healer", "cost": -2, "desc": "Wounds heal slowly.", "mods": {"heal": 0.6}, "not": "fast_healer"},
	"hemophiliac": {"name": "Hemophiliac", "cost": -3, "desc": "Bleeds much more.", "mods": {"bleed": 1.6}},
	"prone_to_illness": {"name": "Prone to Illness", "cost": -2, "desc": "Wound infections spread faster, and so does the zombie virus.", "mods": {"illness": 1.5, "infection": 1.2}},
	"hearty_appetite": {"name": "Hearty Appetite", "cost": -2, "desc": "Gets hungry faster.", "mods": {"hunger": 1.3}, "not": "light_eater"},
}

var name := "Survivor"
## build (0/1), skin, hair (style), hair_col, beard: indices into the lists above.
var look := {"build": 0, "skin": 1, "hair": 0, "hair_col": 1, "beard": 0}
var background := "unemployed"
var traits: Array = []
var skills := {}
## Lifetime stats for this character (kept across respawns).
var stats := {"kills": 0, "days": 0}


static func random(seed_value: int) -> Character:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var c := Character.new()
	c.look = {"build": rng.randi() % 2, "skin": rng.randi() % SKIN_TONES.size(), "hair": rng.randi() % 4,
		"hair_col": rng.randi() % HAIR_COLORS.size(), "beard": 0}
	if c.look.build == 0:
		c.look.beard = rng.randi() % 3
	c.name = ["Alex", "Sam", "Jordan", "Casey", "Riley", "Morgan", "Taylor", "Jamie"][rng.randi() % 8]
	c.background = BACKGROUNDS.keys()[rng.randi() % BACKGROUNDS.size()]
	c.apply_background()
	return c


## Points left to spend: positive is fine, negative can't be confirmed.
func points_left() -> int:
	var p: int = POINTS + int(BACKGROUNDS[background].points)
	for t in traits:
		p -= int(TRAITS[t].cost)
	return p


func can_add_trait(t: String) -> bool:
	if t in traits:
		return false
	var other: String = TRAITS[t].get("not", "")
	return other == "" or not other in traits


func toggle_trait(t: String) -> void:
	if t in traits:
		traits.erase(t)
	elif can_add_trait(t):
		traits.append(t)


func apply_background() -> void:
	skills = {}
	for s in SKILLS:
		skills[s] = 0
	var b: Dictionary = BACKGROUNDS[background]
	for s in b.skills:
		skills[s] = int(b.skills[s])


func skill(s: String) -> int:
	return int(skills.get(s, 0))


## Product of every trait's modifier for `key` (1.0 when none apply).
func mod(key: String) -> float:
	var m := 1.0
	for t in traits:
		m *= float(TRAITS.get(t, {}).get("mods", {}).get(key, 1.0))
	return m


func has_trait(t: String) -> bool:
	return t in traits


## Starting items and worn clothes for this background (also on respawn
## with a new character).
func starting_gear() -> Dictionary:
	var b: Dictionary = BACKGROUNDS[background]
	return {"items": b.items, "clothes": b.clothes}


func to_dict() -> Dictionary:
	return {"name": name, "look": look.duplicate(), "background": background, "traits": traits.duplicate(),
		"skills": skills.duplicate(), "stats": stats.duplicate()}


static func from_dict(d: Dictionary) -> Character:
	var c := Character.new()
	if d.is_empty():
		c.apply_background()
		return c
	c.name = str(d.get("name", "Survivor"))
	var l: Dictionary = d.get("look", {})
	for k in c.look:
		c.look[k] = int(l.get(k, c.look[k]))
	c.background = str(d.get("background", "unemployed"))
	if not BACKGROUNDS.has(c.background):
		c.background = "unemployed"
	c.traits = (d.get("traits", []) as Array).filter(func(t: Variant) -> bool: return TRAITS.has(str(t))).map(func(t: Variant) -> String: return str(t))
	c.apply_background()
	var sk: Dictionary = d.get("skills", {})
	for s in sk:
		c.skills[s] = int(sk[s])
	var st: Dictionary = d.get("stats", {})
	for k in st:
		c.stats[k] = int(st[k])
	return c


## Colours and shapes for drawing this character's body (living or turned),
## wearing the clothes in `equip` (Inventory.equip, or {} for none).
func body_look(equip: Dictionary, zombie := false) -> Dictionary:
	var skin: Color = SKIN_TONES[clampi(int(look.skin), 0, SKIN_TONES.size() - 1)]
	if zombie:
		skin = skin.lerp(Color(0.5, 0.56, 0.45), 0.55).darkened(0.1)
	return BodyLook.from_clothes(equip, skin, HAIR_COLORS[clampi(int(look.hair_col), 0, HAIR_COLORS.size() - 1)],
			int(look.hair), int(look.beard), int(look.build), zombie)
