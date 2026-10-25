class_name Recipes
extends RefCounted
## Everything you can make. All recipes are known from the start: what holds
## you back is materials, tools and where you are (a workbench for the
## bigger jobs, a lit fire for cooking). Plain data plus the rules for
## checking and crafting, using what you carry.
##
## Recipe fields: name, cat (tab), out [id, count], in [[id, count], ...]
## (an entry [id, n, "u"] uses n charges of a tool or container instead,
## like litres from a gas can), tools (tool kinds needed, kept), station
## ("" / "workbench" / "fire"), skill (what it trains), xp, min (skill level
## needed, optional).
##
## Tool kinds: an item's "tool" field, or one of the groups below.

const TOOL_GROUPS := {
	"knife": ["kitchen_knife", "hunting_knife", "machete", "meat_cleaver"],
	"hammer": ["hammer"],
	"saw": ["saw"],
	"pot": ["cooking_pot"],
	"needle": ["sewing_kit"],
}

const CATS := ["Weapons", "Medical", "Food", "Materials", "Tools", "Clothing"]

const LIST := {
	# --- Materials ---------------------------------------------------------------
	"planks": {"name": "Saw a log into planks", "cat": "Materials", "out": ["plank", 3], "in": [["log", 1]],
		"tools": ["saw"], "station": "", "skill": "carpentry", "xp": 6.0},
	"rope": {"name": "Twist rags into rope", "cat": "Materials", "out": ["rope", 1], "in": [["rag", 3]],
		"tools": [], "station": "", "skill": "", "xp": 0.0},
	"rags_hide": {"name": "Cut a hide into leather strips", "cat": "Materials", "out": ["rag", 4], "in": [["animal_hide", 1]],
		"tools": ["knife"], "station": "", "skill": "", "xp": 0.0},
	# --- Weapons -----------------------------------------------------------------
	"spear": {"name": "Spear", "cat": "Weapons", "out": ["spear", 1], "in": [["plank", 1], ["kitchen_knife", 1], ["duct_tape", 1, "u"]],
		"tools": [], "station": "", "skill": "carpentry", "xp": 8.0},
	"nail_bat": {"name": "Nail Bat", "cat": "Weapons", "out": ["nail_bat", 1], "in": [["baseball_bat", 1], ["nails", 8]],
		"tools": ["hammer"], "station": "", "skill": "carpentry", "xp": 8.0},
	"arrows": {"name": "Arrows (6)", "cat": "Weapons", "out": ["arrow", 6], "in": [["plank", 1], ["feathers", 6], ["scrap_metal", 1]],
		"tools": ["knife"], "station": "", "skill": "carpentry", "xp": 6.0},
	"bolts": {"name": "Crossbow Bolts (6)", "cat": "Weapons", "out": ["bolt", 6], "in": [["plank", 1], ["scrap_metal", 1]],
		"tools": ["knife"], "station": "workbench", "skill": "carpentry", "xp": 6.0},
	"molotov": {"name": "Molotov", "cat": "Weapons", "out": ["molotov", 1], "in": [["glass_bottle", 1], ["rag", 1], ["gas_can", 1, "u"]],
		"tools": [], "station": "", "skill": "", "xp": 0.0},
	"noise_maker": {"name": "Noise Maker (alarm)", "cat": "Weapons", "out": ["noise_maker", 1], "in": [["scrap_metal", 1], ["duct_tape", 1, "u"]],
		"tools": ["screwdriver"], "station": "workbench", "skill": "mechanics", "xp": 6.0},
	"bear_trap": {"name": "Bear Trap", "cat": "Weapons", "out": ["bear_trap", 1], "in": [["scrap_metal", 4], ["nails", 10]],
		"tools": ["hammer"], "station": "workbench", "skill": "mechanics", "xp": 12.0, "min": 2},
	# --- Medical -----------------------------------------------------------------
	"splint": {"name": "Splint", "cat": "Medical", "out": ["splint", 1], "in": [["plank", 1], ["rag", 2]],
		"tools": [], "station": "", "skill": "first_aid", "xp": 4.0},
	"bandages": {"name": "Boil rags into bandages", "cat": "Medical", "out": ["bandage", 2], "in": [["rag", 2]],
		"tools": ["pot"], "station": "fire", "skill": "first_aid", "xp": 4.0},
	# --- Food --------------------------------------------------------------------
	"cooked_meat": {"name": "Cook meat", "cat": "Food", "out": ["cooked_meat", 1], "in": [["raw_meat", 1]],
		"tools": [], "station": "fire", "skill": "cooking", "xp": 5.0},
	"cooked_fish": {"name": "Cook fish", "cat": "Food", "out": ["cooked_fish", 1], "in": [["raw_fish", 1]],
		"tools": [], "station": "fire", "skill": "cooking", "xp": 5.0},
	"baked_potato": {"name": "Bake a potato", "cat": "Food", "out": ["baked_potato", 1], "in": [["potato", 1]],
		"tools": [], "station": "fire", "skill": "cooking", "xp": 3.0},
	"boil_water": {"name": "Boil water", "cat": "Food", "out": ["water_bottle", 1], "in": [["dirty_water", 1]],
		"tools": ["pot"], "station": "fire", "skill": "cooking", "xp": 2.0},
	"purify_water": {"name": "Purify water (tablet)", "cat": "Food", "out": ["water_bottle", 1], "in": [["dirty_water", 1], ["purification_tablets", 1, "u"]],
		"tools": [], "station": "", "skill": "", "xp": 0.0},
	"stew": {"name": "Stew", "cat": "Food", "out": ["stew", 1], "in": [["raw_meat", 1], ["potato", 1], ["carrot", 1], ["water_bottle", 1]],
		"tools": ["pot"], "station": "fire", "skill": "cooking", "xp": 12.0},
	"veg_stew": {"name": "Vegetable stew", "cat": "Food", "out": ["stew", 1], "in": [["potato", 1], ["carrot", 1], ["tomato", 1], ["water_bottle", 1]],
		"tools": ["pot"], "station": "fire", "skill": "cooking", "xp": 12.0, "min": 1},
	"fish_stew": {"name": "Fish stew", "cat": "Food", "out": ["stew", 1], "in": [["raw_fish", 1], ["corn", 1], ["water_bottle", 1]],
		"tools": ["pot"], "station": "fire", "skill": "cooking", "xp": 12.0, "min": 2},
	# --- Tools -------------------------------------------------------------------
	"fishing_rod": {"name": "Fishing Rod", "cat": "Tools", "out": ["fishing_rod", 1], "in": [["plank", 1], ["rope", 1], ["nails", 1]],
		"tools": ["knife"], "station": "", "skill": "carpentry", "xp": 6.0},
	"hatchet": {"name": "Hatchet", "cat": "Tools", "out": ["hatchet", 1], "in": [["plank", 1], ["scrap_metal", 2], ["duct_tape", 1, "u"]],
		"tools": ["hammer"], "station": "workbench", "skill": "carpentry", "xp": 10.0},
	"shovel": {"name": "Shovel", "cat": "Tools", "out": ["shovel", 1], "in": [["plank", 2], ["scrap_metal", 2], ["nails", 4]],
		"tools": ["hammer"], "station": "workbench", "skill": "carpentry", "xp": 10.0},
	"watering_can": {"name": "Watering Can", "cat": "Tools", "out": ["watering_can", 1], "in": [["scrap_metal", 2], ["duct_tape", 1, "u"]],
		"tools": ["hammer"], "station": "workbench", "skill": "mechanics", "xp": 6.0},
	"cooking_pot": {"name": "Cooking Pot", "cat": "Tools", "out": ["cooking_pot", 1], "in": [["scrap_metal", 3]],
		"tools": ["hammer"], "station": "workbench", "skill": "mechanics", "xp": 8.0},
	"sleeping_bag": {"name": "Sleeping Bag", "cat": "Tools", "out": ["sleeping_bag", 1], "in": [["rag", 6], ["rope", 1]],
		"tools": ["needle"], "station": "", "skill": "", "xp": 0.0},
	# --- Clothing ----------------------------------------------------------------
	"scrap_armor": {"name": "Scrap Armor", "cat": "Clothing", "out": ["scrap_armor", 1], "in": [["scrap_metal", 4], ["duct_tape", 2, "u"], ["rope", 1]],
		"tools": ["hammer"], "station": "workbench", "skill": "mechanics", "xp": 15.0, "min": 2},
	"hide_jacket": {"name": "Hide Jacket", "cat": "Clothing", "out": ["leather_jacket", 1], "in": [["animal_hide", 2], ["rope", 1]],
		"tools": ["needle", "knife"], "station": "workbench", "skill": "", "xp": 0.0},
}


## Does the player carry an item that counts as this tool kind?
static func has_tool(kind: String) -> bool:
	return not find_tool(kind).is_empty()


static func find_tool(kind: String) -> Dictionary:
	var ids: Array = TOOL_GROUPS.get(kind, [kind])
	for g in GameState.inventory.grids():
		for it in g.items:
			if it.id in ids or ItemDB.get_def(it.id).get("tool", "") == kind:
				if not ItemDB.get_def(it.id).has("uses") or int(it.get("u", 0)) > 0:
					return it
	for it in GameState.inventory.equip.values():
		if not it.is_empty() and (it.id in ids or ItemDB.get_def(it.id).get("tool", "") == kind):
			return it
	return {}


## Charges left across every carried item of this id (for [id, n, "u"]).
static func uses_of(id: String) -> int:
	var n := 0
	for g in GameState.inventory.grids():
		for it in g.items:
			if it.id == id:
				n += int(it.get("u", 0))
	return n


## How many of an item you carry, counting what's in your hands and slots
## (an equipped knife can go into a spear).
static func carried(id: String) -> int:
	var n := GameState.item_count(id)
	for s in GameState.inventory.equip:
		var it: Dictionary = GameState.inventory.equip[s]
		if s != "throw" and not it.is_empty() and it.id == id:
			n += int(it.get("n", 1))
	return n


## Takes `n` of an item: from the bags first, then from equipment slots.
static func take(id: String, n: int) -> void:
	var left := n - GameState.inventory.take(id, n)
	for s in GameState.inventory.equip:
		var it: Dictionary = GameState.inventory.equip[s]
		if left > 0 and s != "throw" and not it.is_empty() and it.id == id:
			GameState.inventory.equip[s] = {}
			left -= 1


## What's missing to craft this here, or [] if it can be made.
## `stations`: the stations within reach ("workbench", "fire").
static func missing(r: Dictionary, stations: Array) -> Array[String]:
	var out: Array[String] = []
	for e in r.in:
		if e.size() > 2:
			if uses_of(e[0]) < int(e[1]):
				out.append(ItemDB.item_name(e[0]))
		elif carried(e[0]) < int(e[1]):
			out.append("%s x%d" % [ItemDB.item_name(e[0]), int(e[1])])
	for t in r.tools:
		if not has_tool(t):
			out.append(tool_name(t))
	if r.station != "" and not r.station in stations:
		out.append("a workbench" if r.station == "workbench" else "a lit fire")
	if GameState.character.skill(r.skill) < int(r.get("min", 0)) and r.skill != "":
		out.append("%s %d" % [Character.SKILL_NAMES[r.skill], int(r.min)])
	return out


static func tool_name(kind: String) -> String:
	return {"knife": "a knife", "hammer": "a hammer", "saw": "a saw", "pot": "a cooking pot", "needle": "a sewing kit",
		"screwdriver": "a screwdriver", "fire_starter": "matches or a lighter"}.get(kind, kind)


## Ingredient list for the menu: "Log, Saw" etc.
static func needs_text(r: Dictionary) -> String:
	var parts: PackedStringArray = []
	for e in r.in:
		parts.append(("%s (%d uses)" if e.size() > 2 else "%s x%d") % [ItemDB.item_name(e[0]), int(e[1])])
	for t in r.tools:
		parts.append("tool: " + tool_name(t))
	if r.station != "":
		parts.append("at " + ("a workbench" if r.station == "workbench" else "a fire"))
	return ", ".join(parts)


## Takes the ingredients and gives the result. Returns the made item, or {}
## if something's missing.
static func craft(id: String, stations: Array, drop_pos: Vector3) -> Dictionary:
	var r: Dictionary = LIST[id]
	if not missing(r, stations).is_empty():
		return {}
	for e in r.in:
		if e.size() > 2:
			var left := int(e[1])
			for g in GameState.inventory.grids():
				for it in g.items:
					if it.id == e[0] and left > 0:
						var t := mini(left, int(it.get("u", 0)))
						it.u = int(it.get("u", 0)) - t
						left -= t
			# An empty roll of tape is gone; an empty gas can stays.
			if ItemDB.get_def(e[0]).get("cat", "") != "misc" or e[0] == "purification_tablets":
				for g in GameState.inventory.grids():
					for it in g.items.duplicate():
						if it.id == e[0] and int(it.get("u", 0)) <= 0:
							g.remove(it)
		else:
			take(e[0], int(e[1]))
	var out := ItemDB.make(r.out[0], int(r.out[1]))
	# Good cooks make more filling meals.
	if r.skill == "cooking":
		out.q = 1.0 + GameState.character.skill("cooking") * 0.05
	GameState.add_item(out.duplicate(true), drop_pos)
	if r.skill != "":
		GameState.practice(r.skill, float(r.xp))
	GameState.inventory.notify()
	return out
