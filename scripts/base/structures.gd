class_name Structures
extends RefCounted
## What you can build outside (and inside) buildings: limited building, no
## free-form houses. Plain data plus the material checks. Records of built
## structures live in GameState.ws.structures (see BaseManager).
##
## Fields: name, desc, size (x, y, z metres; z is depth, the front is +Z),
## cost [[id, n], ...], tools, hp, skill / xp (carpentry by default),
## snap (grid step for placing), solid (blocks movement), inside (can be
## built indoors).

const LIST := {
	"wall": {"name": "Wooden Wall", "desc": "Keeps zombies out until they batter it down.", "size": Vector3(2.0, 2.4, 0.22),
		"cost": [["plank", 4], ["nails", 8]], "tools": ["hammer"], "hp": 450.0, "xp": 10.0, "snap": 1.0, "solid": true},
	"gate": {"name": "Wooden Gate", "desc": "A wall section that opens.", "size": Vector3(2.0, 2.4, 0.22),
		"cost": [["plank", 6], ["nails", 10], ["scrap_metal", 1]], "tools": ["hammer"], "hp": 380.0, "xp": 12.0, "snap": 1.0, "solid": true},
	"spikes": {"name": "Spike Barricade", "desc": "Sharpened stakes that hurt zombies pushing through.", "size": Vector3(2.0, 1.0, 0.9),
		"cost": [["plank", 3], ["nails", 6]], "tools": ["hammer"], "hp": 220.0, "xp": 8.0, "snap": 1.0, "solid": true},
	"watchtower": {"name": "Watchtower", "desc": "A platform 3 m up. Zombies can't climb it.", "size": Vector3(2.4, 4.2, 2.4),
		"cost": [["log", 4], ["plank", 8], ["nails", 16]], "tools": ["hammer"], "hp": 600.0, "xp": 25.0, "snap": 1.0, "solid": true, "min": 2},
	"crate": {"name": "Storage Crate", "desc": "Big shared storage.", "size": Vector3(1.1, 0.75, 0.7),
		"cost": [["plank", 4], ["nails", 6]], "tools": ["hammer"], "hp": 150.0, "xp": 6.0, "snap": 0.25, "solid": true, "inside": true},
	"bed": {"name": "Bed", "desc": "Sleep safely. In co-op, friends can spawn here.", "size": Vector3(1.0, 0.55, 2.0),
		"cost": [["plank", 4], ["rag", 4], ["nails", 6]], "tools": ["hammer"], "hp": 120.0, "xp": 8.0, "snap": 0.25, "solid": true, "inside": true},
	"workbench": {"name": "Workbench", "desc": "Needed for bigger recipes.", "size": Vector3(1.6, 0.95, 0.8),
		"cost": [["plank", 5], ["nails", 8], ["scrap_metal", 2]], "tools": ["hammer"], "hp": 200.0, "xp": 12.0, "snap": 0.25, "solid": true, "inside": true},
	"campfire": {"name": "Campfire", "desc": "Cook, boil water and keep warm. Light it with matches; add logs.", "size": Vector3(1.0, 0.4, 1.0),
		"cost": [["log", 1]], "tools": [], "hp": 60.0, "xp": 2.0, "snap": 0.25, "solid": false},
	"rain_collector": {"name": "Rain Collector", "desc": "Collects clean water when it rains.", "size": Vector3(1.1, 1.3, 1.1),
		"cost": [["plank", 3], ["scrap_metal", 2], ["duct_tape", 1, "u"]], "tools": ["hammer"], "hp": 120.0, "xp": 8.0, "snap": 0.25, "solid": true},
	"farm_plot": {"name": "Farm Plot", "desc": "Dig a bed for seeds (spring to autumn).", "size": Vector3(2.0, 0.25, 2.0),
		"cost": [["plank", 2]], "tools": ["shovel"], "hp": 80.0, "skill": "farming", "xp": 6.0, "snap": 1.0, "solid": false},
}

## Litres a rain collector holds; hours a log burns.
const COLLECTOR_L := 40.0
const LOG_HOURS := 3.0


static func get_def(t: String) -> Dictionary:
	return LIST.get(t, LIST.wall)


static func missing(d: Dictionary) -> Array[String]:
	var r := {"in": d.cost, "tools": d.tools, "station": "", "skill": d.get("skill", "carpentry"), "min": d.get("min", 0)}
	return Recipes.missing(r, [])


static func needs_text(d: Dictionary) -> String:
	return Recipes.needs_text({"in": d.cost, "tools": d.tools, "station": ""})


## Takes the materials for one structure. Returns false if they're missing.
static func pay(t: String) -> bool:
	var d := get_def(t)
	if not missing(d).is_empty():
		return false
	for e in d.cost:
		if e.size() > 2:
			var left := int(e[1])
			for g in GameState.inventory.grids():
				for it in g.items.duplicate():
					if it.id == e[0] and left > 0:
						var take := mini(left, int(it.get("u", 0)))
						it.u = int(it.get("u", 0)) - take
						left -= take
						if int(it.u) <= 0:
							g.remove(it)
		else:
			GameState.inventory.take(e[0], int(e[1]))
	GameState.inventory.notify()
	return true


## Half the materials back when taking a structure apart.
static func refund(t: String) -> Array:
	var out := []
	for e in get_def(t).cost:
		if e.size() > 2:
			continue
		var n := int(e[1]) / 2
		if n > 0:
			out.append(ItemDB.make(e[0], n))
	return out


## Max hp for a structure built at the builder's carpentry level.
static func max_hp(t: String, carpentry: int) -> float:
	return float(get_def(t).hp) * (1.0 + carpentry * 0.08)
