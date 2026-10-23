class_name Weapons
extends Node3D
## The survivor's hands: the first-person weapon model, and everything you do
## with it: melee swings (with wear and silent takedowns), the shove, guns
## (aim down sights, recoil, reloading from loose ammo, jams), bows and
## crossbows, and throwing or placing items. Lives under the camera.

signal hit_zombie(killed: bool)

const SLOT_ORDER := ["primary", "sidearm", "melee", "throw"]
const SHOVE_COST := 12.0
const SHOVE_COOLDOWN := 0.8
const SWITCH_TIME := 0.3

var player: Player
var effects: Effects
var drops: DropManager
var current := "melee"
var aiming := false
var aim_blend := 0.0
## 0..1 while drawing a bow or winding up a throw.
var charge := 0.0
var reloading := false

var _view: Node3D # Holds the weapon model; animated with offsets.
var _mesh: MeshInstance3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_t := 0.0
var _signature := ""
var _cd := 0.0
var _shove_cd := 0.0
var _switch_t := 0.0
var _reload_t := 0.0
var _kick := 0.0
var _swing_t := 0.0
var _charging := false
var _empty_warned := false
var _sway_t := 0.0


func _ready() -> void:
	_view = Node3D.new()
	add_child(_view)
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_view.add_child(_mesh)
	_flash = MeshInstance3D.new()
	_flash.mesh = Assets.muzzle_flash_mesh
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_view.add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.8, 0.5)
	_flash_light.light_energy = 3.0
	_flash_light.omni_range = 7.0
	_flash_light.visible = false
	_view.add_child(_flash_light)
	GameState.inventory_changed.connect(_refresh_model)
	_refresh_model()


func inv() -> Inventory:
	return GameState.inventory


## The equipped item in the current slot (empty = bare hands).
func item() -> Dictionary:
	return inv().equip.get(current, {})


func def() -> Dictionary:
	var it := item()
	if it.is_empty():
		return ItemDB.FISTS if current == "melee" or current == "" else {}
	return ItemDB.get_def(it.id)


func is_ranged() -> bool:
	return def().get("cat", "") in ["gun", "bow"]


func is_gun() -> bool:
	return def().get("cat", "") == "gun"


func has_part(part: String) -> String:
	return item().get("att", {}).get(part, "")


## Field of view to use (zoomed while aiming).
func target_fov(base: float) -> float:
	if not is_ranged():
		return base
	var zoom: float = def().get("zoom", base)
	var scope := has_part("scope")
	if scope != "":
		zoom = ItemDB.get_def(scope).zoom
	return lerpf(base, zoom, aim_blend)


## Full-screen scope overlay (when aiming through a magnified scope).
func scoped() -> bool:
	return aim_blend > 0.9 and has_part("scope") == "scope"


## Aiming through a red dot sight (the HUD draws the dot).
func red_dot() -> bool:
	return aim_blend > 0.8 and has_part("scope") == "red_dot"


func _refresh_model() -> void:
	var it := item()
	var sig := "%s|%s|%s" % [current, it.get("id", ""), str(it.get("att", {}))]
	if sig == _signature:
		return
	_signature = sig
	for c in _mesh.get_children():
		c.queue_free()
	_mesh.mesh = Assets.item_meshes.get(it.id) if not it.is_empty() else null
	for part in it.get("att", {}):
		var a := MeshInstance3D.new()
		a.mesh = Assets.item_meshes.get(it.att[part])
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.position = ItemModels.mount(it.id, part)
		_mesh.add_child(a)
	if not it.is_empty():
		var muzzle := ItemModels.muzzle(it.id)
		if has_part("muzzle") != "":
			muzzle += Vector3(0, 0, -0.16)
		_flash.position = muzzle
		_flash_light.position = muzzle
	# A changed weapon can't still be mid-action.
	reloading = false
	charge = 0.0
	_charging = false


# --- Selecting weapons -------------------------------------------------------

func select(slot: String) -> void:
	if slot == current:
		return
	current = slot
	_switch_t = SWITCH_TIME
	_refresh_model()
	var n: String = ItemDB.SLOT_NAMES.get(slot, "")
	var it := item()
	GameState.notify(ItemDB.item_name(it.id) if not it.is_empty() else ("Bare hands" if slot == "melee" else "%s: empty" % n))


func cycle(step: int) -> void:
	# Skip empty slots (bare hands count as the melee slot).
	var k := SLOT_ORDER.find(current)
	for i in SLOT_ORDER.size():
		k = (k + step + SLOT_ORDER.size()) % SLOT_ORDER.size()
		var s: String = SLOT_ORDER[k]
		if s == "melee" or not inv().equip[s].is_empty():
			select(s)
			return


# --- Per-frame -------------------------------------------------------------

## Called by Player every physics frame while it can act.
func update(delta: float, moving: bool) -> void:
	_cd -= delta
	_shove_cd -= delta
	_switch_t -= delta
	_kick = maxf(0.0, _kick - delta * 6.0)
	_swing_t = maxf(0.0, _swing_t - delta)
	_flash_t -= delta
	_flash.visible = _flash_t > 0.0
	_flash_light.visible = _flash_t > 0.0

	if Input.is_action_just_pressed("weapon_next"):
		cycle(1)
	if Input.is_action_just_pressed("weapon_prev"):
		cycle(-1)
	for k in 4:
		if Input.is_action_just_pressed("slot_%d" % (k + 1)):
			select(SLOT_ORDER[k])
	if current != "melee" and item().is_empty():
		# The weapon in this slot was dropped or moved away.
		select("melee")

	var d := def()
	aiming = Input.is_action_pressed("aim") and is_ranged() and not player.sprinting and _switch_t <= 0.0
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, delta * 6.0)

	if Input.is_action_just_pressed("shove"):
		shove()
	if Input.is_action_just_pressed("throw_quick") and current != "throw":
		_throw(0.7)
	if Input.is_action_just_pressed("reload") and player.alt_prompt == "":
		start_reload()
	_update_reload(delta)

	if _switch_t <= 0.0:
		match d.get("cat", ""):
			"gun":
				var want: bool = Input.is_action_pressed("attack") if d.get("auto", false) else Input.is_action_just_pressed("attack")
				if want and _cd <= 0.0:
					fire()
				if not Input.is_action_pressed("attack"):
					_empty_warned = false
			"bow":
				_update_bow(delta, d)
			"throw":
				_update_throw(delta)
			_:
				if Input.is_action_pressed("attack") and _cd <= 0.0:
					melee()
	_update_view(delta, moving)


func _update_view(delta: float, moving: bool) -> void:
	var d := def()
	var cat: String = d.get("cat", "")
	var hip := Vector3(0.3, -0.3, -0.45)
	var hip_rot := Vector3(-55, 10, -20)
	match cat:
		"gun", "bow":
			var long: bool = d.get("slot", "") == "primary"
			hip = Vector3(0.17, -0.19, -0.32 if long else -0.42)
			hip_rot = Vector3(0, 0, 0)
			if current == "primary" and d.cat == "bow" and item().id == "compound_bow":
				# Held to the left and canted, so the crosshair stays clear.
				hip = Vector3(-0.14, -0.08, -0.6)
				hip_rot = Vector3(0, 0, 18)
		"throw":
			hip = Vector3(0.25, -0.25, -0.4)
			hip_rot = Vector3(-10, 0, 0)
		"melee":
			if d.get("reach", 2.0) < 2.1:
				hip = Vector3(0.26, -0.26, -0.4)
				hip_rot = Vector3(-20, 15, -10)
	# Aiming down sights puts the sight line (iron sights or an optic) on the
	# centre of the screen.
	var sight := float(d.get("sight", 0.1))
	var optic := has_part("scope")
	if optic != "":
		sight = ItemModels.mount(item().id, "scope").y + (0.03 if optic == "scope" else 0.036)
	var ads := Vector3(0, -sight, -0.3)
	var pos := hip.lerp(ads, aim_blend)
	var rot := hip_rot.lerp(Vector3.ZERO, aim_blend)
	# Sway while walking, a kick when firing, a dip when switching or reloading.
	_sway_t += delta * (8.0 if moving else 1.5)
	var sway := (0.012 if moving else 0.004) * (1.0 - aim_blend * 0.8)
	pos += Vector3(sin(_sway_t * 0.5) * sway, sin(_sway_t) * sway * 0.6, 0)
	pos.z += _kick * 0.06
	rot.x += _kick * 6.0
	if _switch_t > 0.0:
		pos.y -= _switch_t / SWITCH_TIME * 0.3
	if reloading:
		pos.y -= 0.08
		rot.x -= 25.0
		rot.z += 20.0
	if _charging and def().get("cat", "") == "throw":
		pos += Vector3(0.05, 0.08, 0.15) * charge
	if _swing_t > 0.0:
		var f := _swing_t / 0.3
		rot += Vector3(45, -50, -50) * sin(f * PI)
	_view.position = _view.position.lerp(pos, minf(1.0, delta * 18.0))
	_view.rotation_degrees = _view.rotation_degrees.lerp(rot, minf(1.0, delta * 18.0))
	_mesh.visible = not scoped()


# --- Melee -----------------------------------------------------------------

func melee() -> void:
	var d := def()
	if player.stamina < d.stam * 0.5:
		return
	_cd = d.cd
	_swing_t = 0.3
	player.use_stamina(d.stam)
	GameState.make_noise(player.global_position, 5.0)
	if _hit_player(d.reach, float(d.dmg) * GameState.character.mod("melee")):
		return
	var z := _melee_target(d.reach)
	if z == null:
		_hit_structure(d)
		return
	var it := item()
	var push := _flat_forward()
	# Silent takedown: sneaking up on a zombie that hasn't noticed you.
	if player.crouching and z.unaware() and z.is_behind(player.global_position) and current == "melee":
		z.takedown()
		GameState.make_noise(player.global_position, 1.5)
		GameState.notify("Silent takedown")
		GameState.practice("stealth", 12.0)
		GameState.practice("melee", 4.0)
		_wear(it, d.wear * 2.0)
		hit_zombie.emit(true)
		return
	var head := z.head_hit(z.get_meta("last_hit", z.global_position))
	var ch := GameState.character
	var dmg: float = d.dmg * (2.0 if head else 1.0) * lerpf(0.6, 1.0, float(it.get("c", 1.0)))
	dmg *= ch.mod("melee") * (1.0 + ch.skill("melee") * 0.05) * player.body.arm_factor()
	z.take_damage(dmg, push, true, true, head)
	GameState.practice("melee", 4.0)
	if d.get("heavy", false) or float(ItemDB.get_def(it.get("id", "")).get("kg", 0.0)) >= 2.5:
		GameState.practice("strength", 2.5)
	if d.get("heavy", false):
		z.stagger(push, 0.9)
	if effects:
		effects.blood(z.global_position + Vector3(0, 1.3, 0), push)
	hit_zombie.emit(z.state == Zombie.State.DEAD)
	_wear(it, d.wear)


## PvP worlds: is another player right in front of us? Then hit them.
func _hit_player(reach: float, dmg: float) -> bool:
	if not Net.active() or not GameState.world.get("pvp", false):
		return false
	var cam := player.camera
	var from := cam.global_position
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * reach, 1 | 2, [player.get_rid()]))
	if hit.is_empty() or not hit.collider is Avatars.RemoteAvatar:
		return false
	Net.pvp_hit((hit.collider as Avatars.RemoteAvatar).peer, dmg, player.global_position)
	if effects:
		effects.blood(hit.position, -cam.global_basis.z)
	hit_zombie.emit(false)
	return true


## A swing that hits no zombie can smash a window or batter a door.
func _hit_structure(d: Dictionary) -> void:
	var cam := player.camera
	var from := cam.global_position
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * float(d.reach), 1, [player.get_rid()]))
	if hit.is_empty():
		return
	# An axe on a tree: chop it down for logs.
	if float(d.get("chop", 0.0)) > 0.0 and not (hit.collider is DoorBody or hit.collider is WindowBody or hit.collider is StructureBody):
		if player.actions.chop(hit.position, float(d.chop)):
			_wear(item(), float(d.wear) * 0.5)
			return
	if hit.collider is WindowBody:
		(hit.collider as WindowBody).smash()
		_wear(item(), float(d.wear))
	elif hit.collider is DoorBody:
		var door := hit.collider as DoorBody
		var heavy: float = 2.5 if d.get("heavy", false) or item().get("id", "") in ["fire_axe", "crowbar"] else 1.0
		door.damage(float(d.dmg) * 0.35 * heavy * GameState.character.mod("melee"), player.global_position)
		_wear(item(), float(d.wear) * 2.0)
		if effects:
			effects.impact(hit.position, hit.normal)


## Finds the zombie a swing hits: a precise ray first (so aiming at the head
## pays off), then a forgiving sweep in front, because pixel-precise aiming is
## frustrating on a touchscreen.
func _melee_target(reach: float) -> Zombie:
	var cam := player.camera
	var space := get_world_3d().direct_space_state
	var from := cam.global_position
	var forward := -cam.global_basis.z
	var ray := PhysicsRayQueryParameters3D.create(from, from + forward * reach, 1 | 4, [player.get_rid()])
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and hit.collider is Zombie:
		(hit.collider as Zombie).set_meta("last_hit", hit.position)
		return hit.collider
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = 4
	q.transform = Transform3D(Basis.IDENTITY, from + forward * (reach * 0.55))
	var best: Zombie = null
	var best_d := INF
	for r in space.intersect_shape(q, 8):
		var z := r.collider as Zombie
		if z == null:
			continue
		var d := from.distance_to(z.global_position)
		if d < best_d:
			best = z
			best_d = d
	if best == null:
		return null
	# Don't hit through walls.
	var wall := PhysicsRayQueryParameters3D.create(from, best.global_position + Vector3(0, 1.2, 0), 1)
	if not space.intersect_ray(wall).is_empty():
		return null
	best.set_meta("last_hit", best.global_position + Vector3(0, 1.2, 0))
	return best


func _wear(it: Dictionary, amount: float) -> void:
	if it.is_empty() or not it.has("c"):
		return
	it.c = maxf(0.0, float(it.c) - amount)
	if it.c <= 0.0:
		GameState.notify("Your %s broke!" % ItemDB.item_name(it.id))
		inv().detach(it)
		inv().notify()


func _flat_forward() -> Vector3:
	var f := -player.global_basis.z
	return Vector3(f.x, 0, f.z).normalized()


## Shove: knocks back every zombie in front. The lifesaver when surrounded.
func shove() -> void:
	if _shove_cd > 0.0 or player.stamina < 5.0:
		return
	_shove_cd = SHOVE_COOLDOWN
	_kick = 1.0
	player.use_stamina(SHOVE_COST)
	GameState.make_noise(player.global_position, 4.0)
	var sphere := SphereShape3D.new()
	sphere.radius = 1.15
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = 4
	q.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3(0, 1.0, 0) + _flat_forward() * 1.0)
	for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var z := r.collider as Zombie
		if z:
			var push := (z.global_position - player.global_position)
			push.y = 0.0
			z.stagger(push.normalized(), 1.1)


# --- Guns ------------------------------------------------------------------

func fire() -> void:
	var it := item()
	var d := def()
	if reloading:
		if d.get("per_round", false) and int(it.a) > 0:
			reloading = false # Shotguns and revolvers can fire mid-reload.
		else:
			return
	if it.get("j", false):
		_cd = 0.3
		GameState.notify("Jammed! Reload to clear it")
		return
	if int(it.a) <= 0:
		_cd = 0.25
		if not _empty_warned:
			_empty_warned = true
			GameState.notify("Empty - reload")
		return
	it.a = int(it.a) - 1
	_cd = d.cd
	_kick = 1.0
	# Worn guns jam.
	var cond := float(it.c)
	if cond < 0.6 and randf() < (0.6 - cond) * 0.12:
		it.j = true
	it.c = maxf(0.05, cond - 0.002)
	var suppressed := has_part("muzzle") != ""
	_flash_t = 0.05
	_flash.scale = Vector3.ONE * (0.4 if suppressed else 1.0)
	_flash_light.light_energy = 1.0 if suppressed else 3.0
	GameState.make_noise(player.global_position, float(d.noise) * (0.3 if suppressed else 1.0))
	if Net.active():
		Net.shot(player.global_position)
	var spread := lerpf(float(d.spread), float(d.ads_spread), aim_blend)
	spread *= (1.0 - GameState.character.skill("aiming") * 0.06) / player.body.arm_factor()
	if player.velocity.length() > 1.0:
		spread *= 1.5
	if player.crouching:
		spread *= 0.8
	var killed := false
	var hit_any := false
	for p in int(d.get("pellets", 1)):
		var r := _shoot_ray(spread, float(d.reach), float(d.dmg))
		hit_any = hit_any or r >= 0
		killed = killed or r == 1
	if hit_any:
		hit_zombie.emit(killed)
		GameState.practice("aiming", 5.0)
	player.add_recoil(float(d.recoil) * (0.6 if aiming else 1.0))
	inv().notify()


## One bullet or pellet. Returns -1 for a miss, 0 for a hit, 1 for a kill.
func _shoot_ray(spread_deg: float, reach: float, dmg: float) -> int:
	var cam := player.camera
	var basis := cam.global_basis
	var a := randf() * TAU
	var r := deg_to_rad(spread_deg) * sqrt(randf()) * 0.5
	var dir := (-basis.z + basis.x * cos(a) * tan(r) + basis.y * sin(a) * tan(r)).normalized()
	var from := cam.global_position
	var pvp: bool = Net.active() and GameState.world.get("pvp", false)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 1 | 4 | (2 if pvp else 0), [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -1
	if hit.collider is Avatars.RemoteAvatar:
		Net.pvp_hit((hit.collider as Avatars.RemoteAvatar).peer, dmg, player.global_position)
		if effects:
			effects.blood(hit.position, dir)
		return 0
	var z := hit.collider as Zombie
	if z == null:
		if hit.collider is WindowBody:
			(hit.collider as WindowBody).smash()
		if effects:
			effects.impact(hit.position, hit.normal)
		return -1
	var dist := from.distance_to(hit.position)
	var falloff := clampf(1.2 - dist / reach, 0.4, 1.0)
	var head := z.head_hit(hit.position)
	z.take_damage(dmg * falloff * (3.0 if head else 1.0), dir * 0.15, true, true, head)
	if effects:
		effects.blood(hit.position, dir)
	return 1 if z.state == Zombie.State.DEAD else 0


func start_reload() -> void:
	var it := item()
	var d := def()
	if it.is_empty() or not is_ranged() or reloading:
		return
	if it.get("j", false):
		reloading = true
		_reload_t = 0.9
		return
	if d.cat == "bow" and not d.get("per_round", false):
		return # Bows nock an arrow as you draw.
	if int(it.a) >= int(d.mag):
		return
	if inv().count(d.ammo) <= 0:
		GameState.notify("No %s" % ItemDB.item_name(d.ammo))
		return
	reloading = true
	_reload_t = float(d.reload)


func _update_reload(delta: float) -> void:
	if not reloading:
		return
	_reload_t -= delta
	if _reload_t > 0.0:
		return
	var it := item()
	var d := def()
	reloading = false
	if it.is_empty():
		return
	if it.get("j", false):
		it.erase("j")
		GameState.notify("Cleared the jam")
		return
	var need := int(d.mag) - int(it.a)
	if d.get("per_round", false):
		if inv().take(d.ammo, 1) == 1:
			it.a = int(it.a) + 1
			if int(it.a) < int(d.mag) and inv().count(d.ammo) > 0:
				reloading = true
				_reload_t = float(d.reload)
	else:
		it.a = int(it.a) + inv().take(d.ammo, need)
	inv().notify()


# --- Bows ------------------------------------------------------------------

func _update_bow(delta: float, d: Dictionary) -> void:
	var it := item()
	if d.get("per_round", false):
		# Crossbow: fires like a single-shot gun.
		if Input.is_action_just_pressed("attack") and _cd <= 0.0 and not reloading:
			if int(it.a) <= 0:
				GameState.notify("Reload a bolt first")
				_cd = 0.3
				return
			it.a = 0
			_cd = 0.4
			_release_arrow(d, 1.0)
		return
	if Input.is_action_pressed("attack") and _cd <= 0.0:
		if not _charging:
			if inv().count(d.ammo) <= 0:
				GameState.notify("No arrows")
				_cd = 0.5
				return
			_charging = true
		charge = minf(1.0, charge + delta / float(d.draw))
		if charge >= 1.0:
			player.use_stamina(6.0 * delta) # Holding a full draw is tiring.
	elif _charging:
		_charging = false
		if charge > 0.25 and inv().take(d.ammo, 1) == 1:
			_release_arrow(d, charge)
			_cd = 0.35
		charge = 0.0


func _release_arrow(d: Dictionary, power: float) -> void:
	var cam := player.camera
	var spread := deg_to_rad(lerpf(2.5, 0.3, aim_blend))
	var dir := (-cam.global_basis.z).rotated(cam.global_basis.x, randf_range(-spread, spread) * 0.5) \
			.rotated(Vector3.UP, randf_range(-spread, spread) * 0.5)
	if effects:
		effects.launch("arrow", d.ammo, cam.global_position + dir * 0.6, dir * float(d.speed) * lerpf(0.5, 1.0, power), float(d.dmg) * power)
	GameState.make_noise(player.global_position, float(d.noise))
	_kick = 0.6
	inv().notify()


# --- Throwing --------------------------------------------------------------

func _update_throw(delta: float) -> void:
	var th: Dictionary = inv().equip.throw
	if th.is_empty():
		return
	if Input.is_action_pressed("attack") and _cd <= 0.0:
		_charging = true
		charge = minf(1.0, charge + delta / 0.8)
	elif _charging:
		_charging = false
		_throw(maxf(charge, 0.3))
		charge = 0.0


## Throws (or, for a bear trap, places) one of the equipped throwables.
func _throw(power: float) -> void:
	var th: Dictionary = inv().equip.throw
	if th.is_empty() or _cd > 0.0:
		return
	_cd = 0.6
	var id: String = th.id
	th.n = int(th.n) - 1
	if int(th.n) <= 0:
		inv().equip.throw = {}
		# Refill from the bag with the same kind, if there's more.
		var more := inv().find(id)
		if not more.is_empty():
			inv().detach(more)
			more.erase("x")
			more.erase("y")
			more.erase("r")
			inv().equip.throw = more
	inv().notify()
	var cam := player.camera
	var forward := -cam.global_basis.z
	if ItemDB.get_def(id).effect == "trap":
		var at := player.global_position + _flat_forward() * 1.3
		if drops:
			drops.drop(ItemDB.make(id), at, true)
		GameState.notify("Bear trap set")
		return
	if effects:
		var vel := forward * lerpf(7.0, 19.0, power) + Vector3.UP * 2.5 + player.velocity * 0.5
		effects.launch("throw", id, cam.global_position + forward * 0.5 + cam.global_basis.x * 0.2, vel)
	_kick = 1.0


## HUD text for the current weapon: name, rounds, condition.
func status() -> Dictionary:
	var it := item()
	var d := def()
	var out := {"name": d.get("name", ""), "ammo": "", "cond": float(it.get("c", -1.0)), "state": ""}
	if it.is_empty() and current != "melee":
		out.name = ""
	match d.get("cat", ""):
		"gun":
			out.ammo = "%d / %d" % [int(it.a), inv().count(d.ammo)]
		"bow":
			out.ammo = "%d" % (inv().count(d.ammo) + int(it.get("a", 0)))
		"throw":
			out.ammo = "x%d" % int(it.get("n", 1))
	if it.get("j", false):
		out.state = "JAMMED"
	elif reloading:
		out.state = "RELOADING"
	return out
