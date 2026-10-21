class_name Loot
extends RefCounted
## What's inside searchable containers. Deterministic per container id, so
## everyone in a world finds the same thing; scarce by design.

## type -> [[item, chance], ...]
const TABLES := {
	"fridge": [["food", 0.45], ["water", 0.4], ["food", 0.15]],
	"kitchen_cabinet": [["food", 0.3], ["water", 0.12]],
	"medicine_cabinet": [["bandage", 0.45]],
	"nightstand": [["bandage", 0.12], ["water", 0.08]],
	"dresser": [["bandage", 0.08]],
	"wardrobe": [["bandage", 0.06]],
	"desk": [["food", 0.06]],
	"store_shelf": [["food", 0.35], ["water", 0.25]],
	"register": [],
	"locker": [["bandage", 0.25], ["food", 0.1]],
	"medical": [["bandage", 0.6], ["bandage", 0.25]],
}
const NAMES := {
	"fridge": "Fridge", "kitchen_cabinet": "Cabinet", "medicine_cabinet": "Medicine Cabinet",
	"nightstand": "Nightstand", "dresser": "Dresser", "wardrobe": "Wardrobe", "desk": "Desk",
	"store_shelf": "Shelf", "register": "Register", "locker": "Locker", "medical": "Medical Cabinet",
}


static func roll(type: String, id: String) -> Array[String]:
	var out: Array[String] = []
	var table: Array = TABLES.get(type, [])
	var h := id.hash()
	for k in table.size():
		var chance: float = table[k][1] * GameState.difficulty().loot
		var r := float(WorldGen.hash3(h, k, 31) % 10000) / 10000.0
		if r < chance:
			out.append(table[k][0])
	return out


static func label(type: String) -> String:
	return NAMES.get(type, "Container")
