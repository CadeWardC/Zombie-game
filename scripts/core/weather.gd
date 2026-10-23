class_name Weather
extends RefCounted
## Weather, seasons and the outdoor temperature. The state lives in
## GameState.weather (saved with the world; the host decides it and sends
## it to guests): {k: kind, i: intensity 0..1, until: in-game hour it
## changes}. Kinds: clear, cloudy, rain, storm, fog, snow.
##
## Seasons change every few in-game weeks (a world setting): spring, summer,
## autumn, winter. Winter is cold, snows instead of raining, and kills crops.

const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
## Degrees C: season base and how much colder it gets at night.
const SEASON_TEMP := {"Spring": 14.0, "Summer": 25.0, "Autumn": 11.0, "Winter": -4.0}
## Chance of each kind starting, per season.
const ODDS := {
	"Spring": {"clear": 3.0, "cloudy": 2.5, "rain": 2.5, "storm": 0.6, "fog": 1.2},
	"Summer": {"clear": 5.0, "cloudy": 2.0, "rain": 1.2, "storm": 0.9, "fog": 0.3},
	"Autumn": {"clear": 2.5, "cloudy": 3.0, "rain": 3.0, "storm": 0.7, "fog": 1.8},
	"Winter": {"clear": 2.5, "cloudy": 3.0, "snow": 3.0, "storm": 0.3, "fog": 1.2},
}
const NAMES := {"clear": "Clear", "cloudy": "Overcast", "rain": "Rain", "storm": "Thunderstorm", "fog": "Fog", "snow": "Snow"}


static func season_days() -> int:
	return int(GameState.world.get("season_days", 14))


static func season() -> String:
	return SEASONS[int((GameState.day - 1) / season_days()) % 4]


static func kind() -> String:
	return str(GameState.weather.get("k", "clear"))


static func intensity() -> float:
	return float(GameState.weather.get("i", 0.0))


static func raining() -> bool:
	return kind() in ["rain", "storm"]


static func wet() -> bool:
	return kind() in ["rain", "storm", "snow"]


## How much rain and storms dull zombies' senses (1 = normal).
static func sense_factor() -> float:
	match kind():
		"rain":
			return lerpf(0.85, 0.7, intensity())
		"storm":
			return 0.6
		"fog":
			return 0.8
	return 1.0


## Outdoor air temperature (C) at a place and time.
static func temperature(gen: WorldGen, pos: Vector3) -> float:
	var t: float = SEASON_TEMP[season()]
	# Warmest mid-afternoon, coldest before dawn.
	var hour := GameState.time_of_day
	t += cos((hour - 15.0) / 24.0 * TAU) * 5.0
	if gen and gen.terrain:
		var tr := gen.terrain
		# Some regions of the map run warmer than others (the climate field).
		t += (tr.temperature_at(pos.x, pos.z) - 0.5) * 10.0
		if tr.biome_at(pos.x, pos.z, tr.macro_height(pos.x, pos.z)) == Terrain.Biome.DESERT:
			t += cos((hour - 15.0) / 24.0 * TAU) * 7.0 + 4.0
		# Thinner, colder air up the mountains.
		t -= maxf(0.0, pos.y - 60.0) * 0.0065
	match kind():
		"rain":
			t -= 3.0
		"storm":
			t -= 5.0
		"snow":
			t -= 2.0
		"cloudy":
			t -= 1.0
	return t


## Host (or single player): picks the next weather when the current spell
## runs out. Returns true if it changed.
static func update() -> bool:
	var now := GameState.hours()
	if now < float(GameState.weather.get("until", 0.0)):
		return false
	var odds: Dictionary = ODDS[season()]
	var total := 0.0
	for k in odds:
		total += float(odds[k])
	var pick := randf() * total
	var k2 := "clear"
	for k in odds:
		pick -= float(odds[k])
		if pick <= 0.0:
			k2 = k
			break
	GameState.weather = {"k": k2, "i": randf_range(0.4, 1.0), "until": now + randf_range(2.0, 9.0)}
	return true
