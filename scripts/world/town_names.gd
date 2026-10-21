class_name TownNames
extends RefCounted
## Generates unique American-sounding place names.

const FIRST := ["Oak", "Pine", "Cedar", "Maple", "Willow", "Spring", "River", "Lake", "Fair",
	"Green", "Red", "Clear", "Mill", "Rock", "Ash", "Elm", "Bridge", "Glen", "Stone", "Silver",
	"Hazel", "Brook", "Fox", "Deer", "Eagle", "Hawk", "Iron", "Copper", "Sand", "Wolf", "Bear",
	"Crow", "Harmon", "Mason", "Carter", "Franklin", "Clinton", "Marion", "Jackson", "Salem",
	"Bristol", "Dover", "Milton", "Ashland", "Lincoln", "Monroe", "Warren", "Hudson", "Dayton"]
const SUFFIX := ["ville", "field", "wood", "ton", " Falls", " Creek", " Springs", "burg", "dale",
	" Ridge", " Hollow", " Junction", "port", " Valley", " Hills", "ford", " Grove", " Point", ""]

var _rng := RandomNumberGenerator.new()
var _used := {}


func _init(seed_value: int) -> void:
	_rng.seed = seed_value + 303


func next(kind: int) -> String:
	for attempt in 50:
		var name: String = FIRST[_rng.randi() % FIRST.size()] + SUFFIX[_rng.randi() % SUFFIX.size()]
		if kind == Settlements.Kind.CITY and _rng.randf() < 0.3:
			name = "Port " + name if _rng.randf() < 0.3 else name + " City"
		if not _used.has(name):
			_used[name] = true
			return name
	return "Settlement %d" % _used.size()
