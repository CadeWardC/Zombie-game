class_name Farming
extends RefCounted
## Crops on farm plots. A plot's record holds crop = {k: kind, g: growth
## 0..1, w: in-game hour last watered, u: hour last updated}. Crops grow
## while watered (by hand or by rain) from spring to autumn; winter frost or
## three dry days kill them. Pure rules; BaseManager ticks them.

## kind -> in-game hours to ripen, seeds item.
const CROPS := {
	"potato": {"hours": 72.0, "seeds": "seeds_potato"},
	"carrot": {"hours": 60.0, "seeds": "seeds_carrot"},
	"tomato": {"hours": 84.0, "seeds": "seeds_tomato"},
	"corn": {"hours": 96.0, "seeds": "seeds_corn"},
}
const DRY_HOURS := 30.0 # Watered within this long counts as watered.
const DIE_HOURS := 72.0


static func growth(c: Dictionary) -> float:
	return clampf(float(c.get("g", 0.0)), 0.0, 1.0) if not c.is_empty() else 0.0


static func ripe(c: Dictionary) -> bool:
	return not c.is_empty() and c.k != "dead" and growth(c) >= 1.0


static func watered(c: Dictionary) -> bool:
	return GameState.hours() - float(c.get("w", -999.0)) < DRY_HOURS


static func can_plant() -> bool:
	return Weather.season() != "Winter"


static func plant(rec: Dictionary, kind: String) -> void:
	var now := GameState.hours()
	rec.crop = {"k": kind, "g": 0.0, "w": now if Weather.raining() else -999.0, "u": now}


static func water(rec: Dictionary) -> void:
	if not rec.get("crop", {}).is_empty():
		rec.crop.w = GameState.hours()


## Advances growth to now. Returns true if something visible changed.
static func tick(rec: Dictionary, farming_skill: int) -> bool:
	var c: Dictionary = rec.get("crop", {})
	if c.is_empty() or c.k == "dead":
		return false
	var now := GameState.hours()
	var dt := now - float(c.get("u", now))
	c.u = now
	if dt <= 0.0:
		return false
	var before := int(growth(c) * 4.0)
	if Weather.raining():
		c.w = now
	if Weather.season() == "Winter" or now - float(c.w) > DIE_HOURS and float(c.w) > 0.0:
		c.k = "dead"
		return true
	if watered(c) and growth(c) < 1.0:
		c.g = float(c.g) + dt / float(CROPS[c.k].hours) * (1.0 + farming_skill * 0.06)
	return int(growth(c) * 4.0) != before


## Picks a ripe crop: returns the items (food and a few seeds).
static func harvest(rec: Dictionary, farming_skill: int) -> Array:
	var c: Dictionary = rec.get("crop", {})
	rec.crop = {}
	if c.is_empty() or c.k == "dead" or growth(c) < 1.0:
		return []
	var n := 4 + farming_skill / 2 + randi() % 3
	return [ItemDB.make(str(c.k), n), ItemDB.make(str(CROPS[c.k].seeds), 1 + randi() % 2)]
