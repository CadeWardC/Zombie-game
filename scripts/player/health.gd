class_name Health
extends RefCounted
## Injuries and illness on top of the single health bar: bleeding wounds,
## broken bones, sprains, burns, wound infection (from dirty wounds) and the
## zombie infection. Pure data plus rules, so it saves as JSON and can later
## be synced to the host in multiplayer.
##
## Time here is in in-game hours (GameState.DAY_LENGTH real seconds = 24 h).

## kind -> name, bleed (health per second, unbandaged), heal (in-game hours
## to heal; deep wounds only heal once stitched), pain, dirty (chance a
## zombie-made wound is dirty and can get infected).
const KINDS := {
	"scratch": {"name": "Scratch", "bleed": 0.05, "heal": 2.0, "pain": 0.05, "dirty": 0.2},
	"laceration": {"name": "Laceration", "bleed": 0.16, "heal": 8.0, "pain": 0.15, "dirty": 0.4},
	"deep_wound": {"name": "Deep wound", "bleed": 0.45, "heal": 24.0, "pain": 0.3, "dirty": 0.5},
	"bite": {"name": "Bite", "bleed": 0.22, "heal": 16.0, "pain": 0.3, "dirty": 0.6},
	"fracture": {"name": "Broken bone", "bleed": 0.0, "heal": 72.0, "pain": 0.5, "dirty": 0.0},
	"sprain": {"name": "Sprain", "bleed": 0.0, "heal": 8.0, "pain": 0.2, "dirty": 0.0},
	"burn": {"name": "Burn", "bleed": 0.0, "heal": 12.0, "pain": 0.3, "dirty": 0.3},
}
const WOUNDS := ["scratch", "laceration", "deep_wound", "bite", "burn"]
const FEVER_AT := 0.4 # Wound infection level where fever sets in.
const SYMPTOMS_AT := 0.15 # Zombie infection level where symptoms show.

## {k: kind, p: body part, t: hours healed, b: bandaged, s: stitched /
## splinted, dirty: can get infected, inf: wound infection 0..1}
var injuries: Array = []
## Zombie infection: 0..1; at 1 you die and turn.
var infection := 0.0
var infected := false
var turn_hours := 36.0 # How long this infection takes to turn you.
var antibiotics := 0.0 # Hours of antibiotics left in the blood.
var painkillers := 0.0
var since_smoke := 0.0 # Hours since the last cigarette (smokers).
## Food poisoning (rotten or raw food, dirty water, bad mushrooms): 0..1.
## It wears off over a day or so; while it lasts you throw up and feel weak.
var sick := 0.0


func clear() -> void:
	injuries.clear()
	infection = 0.0
	infected = false
	antibiotics = 0.0
	painkillers = 0.0
	since_smoke = 0.0
	sick = 0.0


func add(kind: String, part: String, dirty := false) -> Dictionary:
	var inj := {"k": kind, "p": part, "t": 0.0, "b": false, "s": false, "dirty": dirty, "inf": 0.0}
	injuries.append(inj)
	return inj


func has(kind: String, part_prefix := "") -> bool:
	for inj in injuries:
		if inj.k == kind and str(inj.p).begins_with(part_prefix):
			return true
	return false


## Starts the zombie infection (from a bite that broke the skin).
func infect(rng_value: float) -> void:
	if infected:
		return
	infected = true
	infection = 0.001
	turn_hours = lerpf(24.0, 48.0, rng_value)


func symptoms() -> float:
	return clampf((infection - SYMPTOMS_AT) / (1.0 - SYMPTOMS_AT), 0.0, 1.0) if infected else 0.0


## Health lost per second from every wound. `ch` gives trait modifiers.
func bleed_rate(ch: Character = null) -> float:
	var r := 0.0
	var first_aid := ch.skill("first_aid") if ch else 0
	for inj in injuries:
		var b: float = KINDS[inj.k].bleed
		if b <= 0.0:
			continue
		if inj.s:
			continue
		if inj.b:
			b *= (0.3 if inj.k == "deep_wound" else 0.0) * (1.0 - first_aid * 0.06)
		r += b
	return r * (ch.mod("bleed") if ch else 1.0)


func bleeding() -> bool:
	return bleed_rate() > 0.001


func worst_wound_infection() -> float:
	var w := 0.0
	for inj in injuries:
		w = maxf(w, float(inj.inf))
	return w


func fever() -> bool:
	return worst_wound_infection() >= FEVER_AT


func pain() -> float:
	var p := 0.0
	for inj in injuries:
		var k: float = KINDS[inj.k].pain
		p += k * (0.5 if inj.s else 1.0) * (1.0 - clampf(float(inj.t) / float(KINDS[inj.k].heal), 0.0, 0.8))
	if painkillers > 0.0:
		p *= 0.3
	return clampf(p, 0.0, 1.0)


## Advances healing and illness by `dt` real seconds. Returns the change to
## the health bar (negative: damage).
func tick(dt: float, ch: Character) -> float:
	var hours := dt * 24.0 / GameState.DAY_LENGTH
	var heal_mul := (ch.mod("heal") if ch else 1.0) * (1.0 + (ch.skill("first_aid") if ch else 0) * 0.05)
	heal_mul *= 1.0 - symptoms() * 0.7
	var delta := -bleed_rate(ch) * dt
	var illness := ch.mod("illness") if ch else 1.0
	var k := injuries.size() - 1
	while k >= 0:
		var inj: Dictionary = injuries[k]
		var kind: Dictionary = KINDS[inj.k]
		var rate := heal_mul
		if inj.k == "deep_wound" and not inj.s:
			rate = 0.0 # Needs stitches.
		elif inj.k == "fracture":
			rate *= 2.0 if inj.s else 0.5
		elif inj.b or inj.s:
			rate *= 1.5
		if float(inj.inf) > 0.2:
			rate *= 0.3
		# Dirty open wounds can get infected; antibiotics fight it.
		if inj.dirty and inj.k in WOUNDS:
			inj.inf = minf(1.0, float(inj.inf) + hours * 0.06 * illness)
		if antibiotics > 0.0:
			inj.inf = maxf(0.0, float(inj.inf) - hours * 0.15)
			if float(inj.inf) <= 0.0:
				inj.dirty = false
		inj.t = float(inj.t) + hours * rate
		if float(inj.t) >= float(kind.heal) and float(inj.inf) < 0.05:
			injuries.remove_at(k)
		k -= 1
	var wi := worst_wound_infection()
	if wi >= FEVER_AT:
		delta -= lerpf(0.02, 0.08, (wi - FEVER_AT) / (1.0 - FEVER_AT)) * dt
	if infected:
		var speed := (0.35 if antibiotics > 0.0 else 1.0) * (ch.mod("infection") if ch else 1.0)
		infection = minf(1.0, infection + hours / turn_hours * speed)
	if sick > 0.0:
		if sick > 0.6:
			delta -= (sick - 0.6) * 0.12 * dt
		sick = maxf(0.0, sick - hours * (0.08 if antibiotics <= 0.0 else 0.2))
	antibiotics = maxf(0.0, antibiotics - hours)
	painkillers = maxf(0.0, painkillers - hours)
	since_smoke += hours
	return delta


## Multiplies the health bar's slow natural regeneration.
func regen_factor() -> float:
	if fever() or bleeding() or sick > 0.3:
		return 0.0
	return 1.0 - symptoms() * 0.9


## Walking speed multiplier from leg injuries.
func speed_factor() -> float:
	var f := 1.0
	for inj in injuries:
		if not str(inj.p).begins_with("leg"):
			continue
		match inj.k:
			"fracture":
				f = minf(f, 0.75 if inj.s else 0.5)
			"sprain":
				f = minf(f, 0.8)
			"deep_wound":
				f = minf(f, 0.85)
	if painkillers > 0.0:
		f = lerpf(f, 1.0, 0.4)
	return f


func can_sprint() -> bool:
	for inj in injuries:
		if inj.k == "fracture" and str(inj.p).begins_with("leg"):
			return false
	return true


## Melee damage and aim steadiness multiplier from arm injuries.
func arm_factor() -> float:
	var f := 1.0
	for inj in injuries:
		if not str(inj.p).begins_with("arm"):
			continue
		match inj.k:
			"fracture":
				f = minf(f, 0.8 if inj.s else 0.55)
			"sprain", "deep_wound", "burn":
				f = minf(f, 0.85)
	return f


## What each carried treatment would do now: kind of treatment -> the
## injury it would go on (or {} if nothing needs it).
func target_for(treat: String) -> Dictionary:
	var best := {}
	var best_score := 0.0
	for inj in injuries:
		var score := 0.0
		match treat:
			"bleed":
				if not inj.b and not inj.s and float(KINDS[inj.k].bleed) > 0.0:
					score = float(KINDS[inj.k].bleed)
			"deep":
				if inj.k == "deep_wound" and not inj.s:
					score = 1.0
			"fracture":
				if inj.k == "fracture" and not inj.s:
					score = 1.0
			"wound_infection":
				if inj.dirty or float(inj.inf) > 0.0:
					score = 0.1 + float(inj.inf)
		if score > best_score:
			best_score = score
			best = inj
	return best


## Problems that a treatment would help, most urgent first (for quick heal).
func needs() -> Array[String]:
	var out: Array[String] = []
	if not target_for("deep").is_empty():
		out.append("deep")
	if not target_for("bleed").is_empty():
		out.append("bleed")
	if worst_wound_infection() > 0.15:
		out.append("wound_infection")
	if not target_for("fracture").is_empty():
		out.append("fracture")
	if infected and symptoms() > 0.0:
		out.append("infection")
	if pain() > 0.3 and painkillers <= 0.0:
		out.append("pain")
	return out


## Applies a medical item. Returns a message, or "" if it wouldn't help.
func treat(id: String) -> String:
	var d := ItemDB.get_def(id)
	var used := ""
	for t: String in d.get("treats", []):
		match t:
			"bleed":
				var inj := target_for("bleed")
				if not inj.is_empty():
					inj.b = true
					if d.get("dirty", false):
						inj.dirty = true
					used = "Bandaged the %s" % _where(inj)
					if id == "first_aid_kit":
						for o in injuries:
							if float(KINDS[o.k].bleed) > 0.0:
								o.b = true
			"deep":
				var inj := target_for("deep")
				if not inj.is_empty():
					inj.s = true
					inj.b = true
					used = "Stitched the deep wound on your %s" % _where(inj)
			"fracture":
				var inj := target_for("fracture")
				if not inj.is_empty():
					inj.s = true
					used = "Splinted your %s" % _where(inj)
			"wound_infection":
				if id == "antibiotics":
					continue
				var inj := target_for("wound_infection")
				if not inj.is_empty():
					for o in (injuries if id == "first_aid_kit" else [inj]):
						o.dirty = false
						o.inf = maxf(0.0, float(o.inf) - 0.5)
					used = used if used != "" else "Cleaned the wound on your %s" % _where(inj)
			"infection":
				antibiotics = 12.0
				used = "Took antibiotics"
			"pain":
				if painkillers <= 0.0 or pain() > 0.0:
					painkillers = 4.0
					used = "Took painkillers"
			"cure":
				if infected:
					infected = false
					infection = 0.0
					used = "The cure burns through your veins. The infection is gone."
	return used


func _where(inj: Dictionary) -> String:
	return str(ItemDB.PART_NAMES.get(inj.p, inj.p)).to_lower()


static func describe(inj: Dictionary) -> String:
	var kind: Dictionary = KINDS[inj.k]
	var s: String = "%s - %s" % [ItemDB.PART_NAMES.get(inj.p, inj.p), kind.name]
	var notes: PackedStringArray = []
	if float(kind.bleed) > 0.0 and not inj.b and not inj.s:
		notes.append("bleeding")
	if inj.b:
		notes.append("bandaged")
	if inj.s:
		notes.append("splinted" if inj.k == "fracture" else "stitched")
	if inj.k == "deep_wound" and not inj.s:
		notes.append("needs stitches")
	if inj.k == "fracture" and not inj.s:
		notes.append("needs a splint")
	if float(inj.inf) >= FEVER_AT:
		notes.append("infected!")
	elif float(inj.inf) > 0.1:
		notes.append("inflamed")
	elif inj.dirty:
		notes.append("dirty")
	if not notes.is_empty():
		s += " (" + ", ".join(notes) + ")"
	return s


func to_dict() -> Dictionary:
	return {"injuries": injuries.duplicate(true), "infection": infection, "infected": infected, "turn_hours": turn_hours,
		"antibiotics": antibiotics, "painkillers": painkillers, "since_smoke": since_smoke, "sick": sick}


func from_dict(d: Dictionary) -> void:
	clear()
	for inj in d.get("injuries", []):
		if KINDS.has(str(inj.get("k", ""))):
			injuries.append({"k": str(inj.k), "p": str(inj.get("p", "torso")), "t": float(inj.get("t", 0.0)),
				"b": bool(inj.get("b", false)), "s": bool(inj.get("s", false)), "dirty": bool(inj.get("dirty", false)),
				"inf": float(inj.get("inf", 0.0))})
	infection = float(d.get("infection", 0.0))
	infected = bool(d.get("infected", false))
	turn_hours = float(d.get("turn_hours", 36.0))
	antibiotics = float(d.get("antibiotics", 0.0))
	painkillers = float(d.get("painkillers", 0.0))
	since_smoke = float(d.get("since_smoke", 0.0))
	sick = float(d.get("sick", 0.0))
