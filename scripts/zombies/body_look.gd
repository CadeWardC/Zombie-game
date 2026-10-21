class_name BodyLook
extends RefCounted
## Describes how a body is drawn (living survivor or zombie): skin, hair,
## clothes and build. ZombieModel turns one of these dictionaries into a
## skinned mesh. Keys:
##   skin, hair (Color), hair_style (0 short, 1 long, 2 ponytail, 3 buzz,
##   4 bald), beard (0 none, 1 stubble, 2 beard), build (0 masculine,
##   1 feminine), shirt, pants, shoes (Color), sleeves (0 none, 1 short,
##   2 long), boots (bool), extra ("", "tie", "badge", "vest", "hood",
##   "coat", "armor"), head ("", "cap", "beanie", "helmet", "army_helmet"),
##   head_col (Color), zombie (bool), bulk (torso width scale), mouth (open
##   jaw, for screamers), torn (chance a zombie's sleeve is ripped off).


static func base(skin: Color, hair: Color, zombie := true) -> Dictionary:
	return {"skin": skin, "hair": hair, "hair_style": 0, "beard": 0, "build": 0,
		"shirt": Color(0.5, 0.5, 0.5), "pants": Color(0.25, 0.25, 0.27), "shoes": Color(0.1, 0.1, 0.1), "sleeves": 1,
		"boots": false, "extra": "", "head": "", "head_col": Color.BLACK, "zombie": zombie, "bulk": 1.0,
		"mouth": false, "torn": 0.3 if zombie else 0.0}


## A body wearing the clothes in an equipment dictionary (Inventory.equip).
static func from_clothes(equip: Dictionary, skin: Color, hair: Color, hair_style: int, beard: int, build: int, zombie: bool) -> Dictionary:
	var l := base(skin, hair, zombie)
	l.hair_style = hair_style
	l.beard = beard
	l.build = build
	l.sleeves = 0
	l.shirt = skin # Bare chest unless something is worn.
	l.pants = Color(0.75, 0.72, 0.68) # Underwear.
	l.shoes = skin.darkened(0.2)
	for slot in ItemDB.CLOTHING_SLOTS:
		var it: Dictionary = equip.get(slot, {})
		if it.is_empty():
			continue
		var d := ItemDB.get_def(it.id)
		var cols: Array = d.get("col", [Color.GRAY])
		var col: Color = cols[clampi(int(it.get("v", 0)), 0, cols.size() - 1)]
		var shape: String = d.get("look", "")
		match slot:
			"head":
				l.head = shape
				l.head_col = col
			"torso":
				l.shirt = col
				l.sleeves = 2 if shape == "long" else 1
				l.extra = d.get("extra", l.extra)
			"jacket":
				l.shirt = col
				l.sleeves = 2
				match shape:
					"hoodie":
						l.extra = "hood"
					"coat":
						l.extra = "coat"
					"armor":
						l.extra = "armor"
					_:
						l.extra = d.get("extra", "")
			"legs":
				l.pants = col
			"feet":
				l.shoes = col
				l.boots = shape == "boots"
	return l


## Stable key for caching meshes built from a look.
static func key(l: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in ["skin", "hair", "hair_style", "beard", "build", "shirt", "pants", "shoes", "sleeves", "boots",
			"extra", "head", "head_col", "zombie", "bulk", "mouth", "torn"]:
		var v: Variant = l.get(k)
		parts.append(v.to_html() if v is Color else str(v))
	return "|".join(parts)
