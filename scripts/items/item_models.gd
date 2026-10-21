class_name ItemModels
extends RefCounted
## Low-poly 3D models of every item, built in code. Used for the first-person
## weapon, items lying on the ground and inventory icons.
## Item space: -Z is forward (the muzzle / blade / top of a can lying down),
## +Y up. Weapons have their origin at the grip, other items at the base.

const STEEL := Color(0.2, 0.21, 0.22)
const DARK := Color(0.09, 0.09, 0.1)
const WOOD := Color(0.45, 0.3, 0.17)
const SILVER := Color(0.66, 0.67, 0.68)
const OLIVE := Color(0.3, 0.33, 0.22)
const TAN := Color(0.62, 0.55, 0.4)


static func build(id: String) -> MeshData:
	var m := MeshData.new()
	match id:
		"canned_beans", "canned_soup", "soda":
			var col: Color = {"canned_beans": Color(0.7, 0.2, 0.12), "canned_soup": Color(0.85, 0.75, 0.3), "soda": Color(0.15, 0.35, 0.75)}[id]
			var r := 0.033 if id == "soda" else 0.042
			m.cylinder(Vector3.ZERO, r, r, 0.115, 10, SILVER)
			m.cylinder(Vector3(0, 0.015, 0), r + 0.002, r + 0.002, 0.085, 10, col, false)
		"crackers":
			_b(m, Vector3(0, 0.03, 0), Vector3(0.2, 0.06, 0.1), Color(0.85, 0.6, 0.2))
			_b(m, Vector3(0, 0.061, 0), Vector3(0.12, 0.002, 0.06), Color(0.9, 0.85, 0.7))
		"chips":
			_b(m, Vector3(0, 0.015, 0), Vector3(0.14, 0.03, 0.22), Color(0.9, 0.75, 0.1))
			_b(m, Vector3(0, 0.031, 0.02), Vector3(0.08, 0.002, 0.1), Color(0.8, 0.15, 0.1))
		"energy_bar":
			_b(m, Vector3(0, 0.012, 0), Vector3(0.12, 0.024, 0.04), Color(0.25, 0.5, 0.2))
		"mre":
			_b(m, Vector3(0, 0.02, 0), Vector3(0.14, 0.04, 0.26), Color(0.45, 0.38, 0.25))
		"water_bottle", "glass_bottle", "molotov":
			var col := Color(0.55, 0.75, 0.9) if id == "water_bottle" else Color(0.2, 0.42, 0.22)
			m.cylinder(Vector3.ZERO, 0.035, 0.035, 0.17, 8, col)
			m.cylinder(Vector3(0, 0.17, 0), 0.035, 0.014, 0.05, 8, col, false)
			m.cylinder(Vector3(0, 0.22, 0), 0.014, 0.014, 0.03, 6, Color(0.9, 0.9, 0.95) if id == "water_bottle" else col)
			if id == "water_bottle":
				m.cylinder(Vector3(0, 0.05, 0), 0.037, 0.037, 0.07, 8, Color(0.15, 0.35, 0.8), false)
			if id == "molotov":
				m.cylinder(Vector3(0, 0.25, 0), 0.012, 0.004, 0.06, 5, Color(0.85, 0.8, 0.7))
				m.cylinder(Vector3(0, 0.02, 0), 0.036, 0.036, 0.1, 8, Color(0.5, 0.3, 0.12), false)
		"bandage":
			m.cylinder(Vector3.ZERO, 0.035, 0.035, 0.06, 10, Color(0.95, 0.95, 0.92))
		"painkillers":
			m.cylinder(Vector3.ZERO, 0.022, 0.022, 0.07, 8, Color(0.85, 0.5, 0.15))
			m.cylinder(Vector3(0, 0.07, 0), 0.024, 0.024, 0.02, 8, Color(0.95, 0.95, 0.95))
		"first_aid_kit":
			_b(m, Vector3(0, 0.05, 0), Vector3(0.26, 0.1, 0.2), Color(0.85, 0.15, 0.12))
			_b(m, Vector3(0, 0.101, 0), Vector3(0.1, 0.002, 0.03), Color.WHITE)
			_b(m, Vector3(0, 0.101, 0), Vector3(0.03, 0.002, 0.1), Color.WHITE)
		# --- Melee (origin at the hand, pointing -Z) ---------------------------
		"kitchen_knife", "hunting_knife":
			var hunting := id == "hunting_knife"
			_b(m, Vector3(0, 0, 0.02), Vector3(0.022, 0.03, 0.11), DARK if hunting else Color(0.15, 0.12, 0.1))
			_b(m, Vector3(0, 0, -0.035), Vector3(0.05 if hunting else 0.024, 0.03, 0.01), SILVER.darkened(0.3))
			_wedge(m, Vector3(0, 0.002, -0.04), 0.004, 0.035 if hunting else 0.03, 0.15 if hunting else 0.17, SILVER)
		"hammer":
			_b(m, Vector3(0, 0, -0.1), Vector3(0.025, 0.03, 0.3), WOOD)
			_b(m, Vector3(0, 0.0, -0.26), Vector3(0.12, 0.03, 0.035), STEEL)
		"crowbar":
			_b(m, Vector3(0, 0, -0.25), Vector3(0.022, 0.022, 0.62), Color(0.55, 0.12, 0.1))
			_b(m, Vector3(0, 0.04, -0.57), Vector3(0.022, 0.1, 0.022), Color(0.55, 0.12, 0.1))
		"machete":
			_b(m, Vector3(0, 0, 0.03), Vector3(0.026, 0.032, 0.13), DARK)
			_wedge(m, Vector3(0, 0.005, -0.04), 0.004, 0.05, 0.45, SILVER.darkened(0.1))
		"baseball_bat":
			m.append(_cyl(0.017, 0.017, 0.16, DARK), Transform3D(_FWD, Vector3(0, 0, 0.08)))
			m.append(_cyl(0.019, 0.034, 0.62, WOOD.lightened(0.25)), Transform3D(_FWD, Vector3(0, 0, -0.08)))
		"fire_axe":
			_b(m, Vector3(0, 0, -0.25), Vector3(0.03, 0.035, 0.75), Color(0.75, 0.1, 0.08))
			_b(m, Vector3(0, 0.05, -0.58), Vector3(0.02, 0.18, 0.08), SILVER.darkened(0.2))
			_b(m, Vector3(0, -0.06, -0.58), Vector3(0.02, 0.07, 0.04), SILVER.darkened(0.2))
		"sledgehammer":
			_b(m, Vector3(0, 0, -0.3), Vector3(0.032, 0.036, 0.85), WOOD)
			_b(m, Vector3(0, 0, -0.72), Vector3(0.09, 0.09, 0.2), STEEL)
		# --- Guns (origin at the grip, muzzle toward -Z) -----------------------
		"pistol_9mm":
			_b(m, Vector3(0, -0.04, 0.005), Vector3(0.03, 0.1, 0.045), DARK) # grip
			_b(m, Vector3(0, 0.035, -0.05), Vector3(0.03, 0.035, 0.19), STEEL) # slide
			_b(m, Vector3(0, 0.005, -0.03), Vector3(0.028, 0.03, 0.13), DARK) # frame
			_b(m, Vector3(0, -0.012, -0.02), Vector3(0.006, 0.02, 0.04), DARK) # trigger guard
			_b(m, Vector3(0, 0.058, -0.13), Vector3(0.006, 0.01, 0.008), DARK) # front sight
		"revolver":
			_b(m, Vector3(0, -0.045, 0.015), Vector3(0.032, 0.1, 0.045), WOOD)
			m.append(_cyl(0.022, 0.022, 0.045, SILVER.darkened(0.2), 8), Transform3D(_FWD, Vector3(0, 0.025, -0.01)))
			m.append(_cyl(0.009, 0.009, 0.16, SILVER.darkened(0.2), 6), Transform3D(_FWD, Vector3(0, 0.035, -0.035)))
			_b(m, Vector3(0, 0.012, -0.02), Vector3(0.026, 0.03, 0.06), SILVER.darkened(0.3))
			_b(m, Vector3(0, 0.05, -0.18), Vector3(0.005, 0.012, 0.01), DARK)
		"pump_shotgun":
			_b(m, Vector3(0, -0.02, 0.22), Vector3(0.04, 0.09, 0.3), WOOD) # stock
			_b(m, Vector3(0, 0.0, -0.02), Vector3(0.045, 0.06, 0.2), DARK) # receiver
			m.append(_cyl(0.012, 0.012, 0.55, STEEL, 6), Transform3D(_FWD, Vector3(0, 0.022, -0.1))) # barrel
			m.append(_cyl(0.012, 0.012, 0.45, DARK, 6), Transform3D(_FWD, Vector3(0, -0.005, -0.1))) # tube
			_b(m, Vector3(0, -0.005, -0.3), Vector3(0.045, 0.04, 0.16), WOOD) # pump
		"hunting_rifle":
			_b(m, Vector3(0, -0.025, 0.24), Vector3(0.04, 0.09, 0.32), WOOD) # stock
			_b(m, Vector3(0, -0.01, -0.12), Vector3(0.04, 0.045, 0.5), WOOD) # fore-end
			_b(m, Vector3(0, 0.02, 0.0), Vector3(0.032, 0.035, 0.2), STEEL) # receiver
			m.append(_cyl(0.009, 0.008, 0.72, STEEL, 6), Transform3D(_FWD, Vector3(0, 0.025, -0.08)))
			_b(m, Vector3(0.03, 0.025, 0.04), Vector3(0.03, 0.01, 0.01), STEEL) # bolt handle
		"assault_rifle":
			_b(m, Vector3(0, -0.01, 0.22), Vector3(0.04, 0.07, 0.24), DARK) # stock
			_b(m, Vector3(0, 0.0, 0.0), Vector3(0.042, 0.07, 0.24), DARK) # receiver
			_b(m, Vector3(0, -0.07, -0.05), Vector3(0.03, 0.12, 0.06), DARK) # magazine
			_b(m, Vector3(0, -0.055, 0.04), Vector3(0.028, 0.08, 0.035), DARK) # grip
			_b(m, Vector3(0, 0.0, -0.22), Vector3(0.046, 0.055, 0.22), Color(0.16, 0.16, 0.15)) # handguard
			m.append(_cyl(0.008, 0.008, 0.2, STEEL, 6), Transform3D(_FWD, Vector3(0, 0.005, -0.33)))
			_b(m, Vector3(0, 0.05, 0.05), Vector3(0.02, 0.02, 0.06), DARK) # carry rail
		"compound_bow":
			_b(m, Vector3(0, 0, 0), Vector3(0.035, 0.12, 0.04), DARK) # riser grip
			for s: float in [-1.0, 1.0]:
				_b(m, Vector3(0, 0.17 * s, -0.04), Vector3(0.025, 0.26, 0.03), OLIVE)
				_b(m, Vector3(0, 0.38 * s, -0.01), Vector3(0.02, 0.18, 0.03), OLIVE.darkened(0.2))
				m.append(_cyl(0.025, 0.025, 0.01, DARK, 8), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.47 * s, 0.0)))
			_b(m, Vector3(0, 0, 0.12), Vector3(0.002, 0.9, 0.002), Color(0.85, 0.85, 0.8)) # string
		"crossbow":
			_b(m, Vector3(0, -0.02, 0.15), Vector3(0.04, 0.07, 0.3), DARK) # stock
			_b(m, Vector3(0, 0.0, -0.18), Vector3(0.035, 0.035, 0.4), DARK) # rail
			_b(m, Vector3(0, -0.01, -0.36), Vector3(0.56, 0.025, 0.03), OLIVE) # limbs
			_b(m, Vector3(0, 0.01, -0.2), Vector3(0.5, 0.002, 0.002), Color(0.85, 0.85, 0.8)) # string
		# --- Ammo --------------------------------------------------------------
		"ammo_9mm", "ammo_357", "ammo_308", "ammo_556":
			var col: Color = {"ammo_9mm": Color(0.75, 0.6, 0.2), "ammo_357": Color(0.3, 0.35, 0.6), "ammo_308": Color(0.3, 0.45, 0.25), "ammo_556": Color(0.55, 0.5, 0.3)}[id]
			_b(m, Vector3(0, 0.03, 0), Vector3(0.1, 0.06, 0.07), col)
			_b(m, Vector3(0, 0.061, 0), Vector3(0.06, 0.002, 0.04), Color(0.9, 0.88, 0.8))
		"ammo_12g":
			_b(m, Vector3(0, 0.035, 0), Vector3(0.11, 0.07, 0.08), Color(0.7, 0.15, 0.1))
			_b(m, Vector3(0, 0.071, 0), Vector3(0.07, 0.002, 0.05), Color(0.9, 0.88, 0.8))
		"arrow", "bolt":
			var ln := 0.75 if id == "arrow" else 0.4
			m.append(_cyl(0.004, 0.004, ln, Color(0.15, 0.15, 0.15) if id == "bolt" else WOOD.lightened(0.2), 4), Transform3D(_FWD, Vector3.ZERO))
			m.append(_cyl(0.008, 0.0, 0.03, SILVER, 4), Transform3D(_FWD, Vector3(0, 0, -ln * 0.5)))
			for s: float in [-1.0, 1.0]:
				_b(m, Vector3(0.008 * s, 0, ln * 0.5 - 0.04), Vector3(0.012, 0.002, 0.06), Color(0.8, 0.2, 0.15))
		# --- Throwables --------------------------------------------------------
		"noise_maker":
			m.append(_cyl(0.05, 0.05, 0.03, Color(0.75, 0.15, 0.12), 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.05, 0.015)))
			_b(m, Vector3(0, 0.05, -0.016), Vector3(0.07, 0.07, 0.002), Color(0.95, 0.95, 0.9))
			for s: float in [-1.0, 1.0]:
				m.cylinder(Vector3(0.03 * s, 0.095, 0), 0.018, 0.018, 0.012, 6, SILVER)
		"grenade":
			m.cylinder(Vector3.ZERO, 0.03, 0.033, 0.07, 8, OLIVE)
			m.cylinder(Vector3(0, 0.07, 0), 0.012, 0.012, 0.025, 6, SILVER)
			_b(m, Vector3(0.015, 0.075, 0), Vector3(0.01, 0.04, 0.012), SILVER)
		"bear_trap":
			m.cylinder(Vector3.ZERO, 0.2, 0.2, 0.012, 10, STEEL)
			for s: float in [-1.0, 1.0]:
				_b(m, Vector3(0, 0.04, 0.13 * s), Vector3(0.3, 0.06, 0.012), STEEL.lightened(0.15))
			_b(m, Vector3(0, 0.02, 0), Vector3(0.07, 0.02, 0.07), Color(0.5, 0.45, 0.3))
		# --- Attachments -------------------------------------------------------
		"scope":
			m.append(_cyl(0.02, 0.02, 0.24, DARK, 8), Transform3D(_FWD, Vector3(0, 0.03, 0.12)))
			m.append(_cyl(0.026, 0.026, 0.05, DARK, 8), Transform3D(_FWD, Vector3(0, 0.03, -0.1)))
			_b(m, Vector3(0, 0.005, 0), Vector3(0.02, 0.02, 0.06), DARK)
		"red_dot":
			_b(m, Vector3(0, 0.01, 0), Vector3(0.028, 0.02, 0.05), DARK)
			_b(m, Vector3(0, 0.035, 0), Vector3(0.03, 0.03, 0.006), Color(0.4, 0.5, 0.6))
		"suppressor":
			m.append(_cyl(0.017, 0.017, 0.16, DARK, 8), Transform3D(_FWD, Vector3(0, 0.017, 0.08)))
		"weapon_light":
			m.append(_cyl(0.015, 0.018, 0.08, DARK, 8), Transform3D(_FWD, Vector3(0, 0.018, 0.04)))
			_b(m, Vector3(0, 0.018, -0.041), Vector3(0.026, 0.026, 0.002), Color(0.95, 0.95, 0.8))
		# --- Bags --------------------------------------------------------------
		"school_backpack", "hiking_backpack", "military_backpack":
			var col: Color = {"school_backpack": Color(0.2, 0.3, 0.6), "hiking_backpack": Color(0.65, 0.3, 0.15), "military_backpack": OLIVE}[id]
			var big := id != "school_backpack"
			var hgt := 0.6 if big else 0.42
			_b(m, Vector3(0, hgt * 0.5, 0), Vector3(0.32 if big else 0.3, hgt, 0.2 if big else 0.15), col)
			_b(m, Vector3(0, hgt * 0.32, -0.12 if big else -0.09), Vector3(0.24, hgt * 0.4, 0.06), col.darkened(0.2))
			_b(m, Vector3(0, hgt + 0.02, 0), Vector3(0.28, 0.06, 0.18), col.darkened(0.1))
		"tactical_vest":
			_b(m, Vector3(0, 0.25, 0), Vector3(0.4, 0.5, 0.08), Color(0.18, 0.2, 0.17))
			for k in 3:
				_b(m, Vector3(-0.12 + k * 0.12, 0.15, -0.06), Vector3(0.1, 0.13, 0.05), Color(0.22, 0.24, 0.2))
		_:
			_b(m, Vector3(0, 0.05, 0), Vector3(0.1, 0.1, 0.1), Color(0.6, 0.6, 0.6))
	return m


## Where a weapon's muzzle is, relative to its grip (for muzzle flashes).
static func muzzle(id: String) -> Vector3:
	match id:
		"pistol_9mm":
			return Vector3(0, 0.035, -0.15)
		"revolver":
			return Vector3(0, 0.035, -0.2)
		"pump_shotgun":
			return Vector3(0, 0.022, -0.66)
		"hunting_rifle":
			return Vector3(0, 0.025, -0.8)
		"assault_rifle":
			return Vector3(0, 0.005, -0.54)
	return Vector3(0, 0, -0.4)


## Where attachments sit on a gun: part -> position relative to the grip.
static func mount(id: String, part: String) -> Vector3:
	var top := {"pistol_9mm": Vector3(0, 0.053, -0.03), "pump_shotgun": Vector3(0, 0.032, -0.02),
		"hunting_rifle": Vector3(0, 0.04, -0.02), "assault_rifle": Vector3(0, 0.06, -0.06), "crossbow": Vector3(0, 0.02, 0.0),
		"revolver": Vector3(0, 0.045, -0.04)}
	match part:
		"scope":
			return top.get(id, Vector3(0, 0.05, 0))
		"muzzle":
			return muzzle(id)
		"light":
			return muzzle(id) * Vector3(1, 0, 0.75) + Vector3(0, -0.03, 0)
	return Vector3.ZERO


const _FWD := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)) # Turns +Y (cylinder axis) into -Z.


static func _b(m: MeshData, pos: Vector3, size: Vector3, col: Color) -> void:
	m.box(Transform3D(Basis.IDENTITY, pos), size, col, false)


## A cylinder along +Y, centred on its length (for laying along -Z with _FWD).
static func _cyl(r0: float, r1: float, length: float, col: Color, sides := 8) -> MeshData:
	var c := MeshData.new()
	c.cylinder(Vector3(0, -length * 0.5, 0), r0, r1, length, sides, col)
	# Bottom cap (MeshData.cylinder only caps the top).
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		c.tri(Vector3(0, -length * 0.5, 0), Vector3(cos(a0) * r0, -length * 0.5, sin(a0) * r0),
				Vector3(cos(a1) * r0, -length * 0.5, sin(a1) * r0), col, Vector3.DOWN)
	return c


## A flat blade: thick at the spine, tapering to a point toward -Z.
static func _wedge(m: MeshData, base: Vector3, thick: float, width: float, length: float, col: Color) -> void:
	var t := thick * 0.5
	var p0 := base + Vector3(-t, width * 0.5, 0)
	var p1 := base + Vector3(-t, -width * 0.5, 0)
	var p2 := base + Vector3(0, width * 0.3, -length)
	var q0 := base + Vector3(t, width * 0.5, 0)
	var q1 := base + Vector3(t, -width * 0.5, 0)
	m.tri(p0, p1, p2, col, Vector3.LEFT)
	m.tri(q0, q1, p2, col, Vector3.RIGHT)
	m.tri(p0, q0, p2, col.lightened(0.1), Vector3.UP)
	m.tri(p1, q1, p2, col.lightened(0.2), Vector3.DOWN)
