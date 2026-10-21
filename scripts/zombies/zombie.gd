class_name Zombie
extends CharacterBody3D
## A single zombie. It has no _process/_physics_process of its own:
## ZombieManager drives every zombie so it can update far ones less often.
##
## Types (see TYPES): walkers, runners (fast, fragile), brutes (huge, tough,
## break doors), screamers (shriek to call every zombie around), crawlers
## (lie low, grab ankles) and soldiers (armoured, carry military gear).
## Zombies open unlocked doors, batter locked ones while they know you're
## inside, smash windows and crawl through, and climb low fences. Turned
## players carry their gear; friends can subdue them and give them the cure.

enum State { WANDER, INVESTIGATE, CHASE, DEAD, SUBDUED }

## hp, walk / chase / night (m/s), dmg, cd (attack cooldown), door (damage
## per second to locked doors), armor (body damage taken), scale
const TYPES := {
	"walker": {"hp": 60.0, "walk": 1.1, "chase": 3.4, "night": 4.4, "dmg": 12.0, "cd": 1.3, "door": 0.6},
	"runner": {"hp": 40.0, "walk": 1.3, "chase": 5.4, "night": 5.9, "dmg": 10.0, "cd": 1.0, "door": 0.8},
	"brute": {"hp": 320.0, "walk": 0.9, "chase": 2.7, "night": 3.1, "dmg": 26.0, "cd": 1.8, "door": 9.0, "scale": 1.22},
	"screamer": {"hp": 45.0, "walk": 1.0, "chase": 3.0, "night": 3.4, "dmg": 8.0, "cd": 1.3, "door": 0.3},
	"crawler": {"hp": 35.0, "walk": 0.45, "chase": 1.3, "night": 1.5, "dmg": 9.0, "cd": 1.4, "door": 0.0},
	"soldier": {"hp": 90.0, "walk": 1.1, "chase": 3.6, "night": 4.2, "dmg": 14.0, "cd": 1.2, "door": 1.0, "armor": 0.4},
}
const ATTACK_RANGE := 1.5
const GRAVITY := 14.0
const CORPSE_TIME := 10.0
const SCREAM_RADIUS := 90.0
const SUBDUE_TIME := 45.0

var type := "walker"
var state := State.WANDER
var health := 60.0
var max_health := 60.0
var target := Vector3.ZERO
var slot := 0
var accum := 0.0
var anim_accum := 0.0
var dead_timer := 0.0
var physics_active := false
## 0..1: how sure this zombie is that it has spotted the player (stealth).
var awareness := 0.0
var last_sight_check := 0
var mgr: ZombieManager
var spawn_id := "" # Interior spawn point it came from ("" if none).
## A turned player: their id, name, owner, and the gear they carried.
var turned_id := ""
var turned_name := ""
var turned_owner := ""
var turned_items: Array = []
var subdued := false

var _model: Node3D
var _body: MeshInstance3D
var _anim: AnimationPlayer
var _shape: CollisionShape3D
var _one_shot := 0.0 # Time left in an attack / hit animation.
var _attack_cd := 0.0
var _think_t := 0.0
var _lost_t := 0.0
var _search_t := 0.0 # Investigating: gives up after a while.
var _stuck_t := 0.0
var _detour_t := 0.0
var _detour_dir := Vector3.ZERO
var _speed_mul := 1.0
var _stagger_t := 0.0 # Shoved or hit hard: can't move or attack.
var _trap_t := 0.0 # Caught in a bear trap.
var _burn_t := 0.0
var _scream_cd := 0.0
var _entry: Node3D # Door or window it's heading for.
var _entry_t := 0.0
var _through_t := 0.0 # Walking through an opened doorway.
var _through := Vector3.ZERO
var _move_t := 0.0 # Climbing a fence or crawling through a window.
var _move_from := Vector3.ZERO
var _move_to := Vector3.ZERO
var _move_len := 1.0
var _subdue_t := 0.0
var _flames: MeshInstance3D


func _init() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.5
	_shape = CollisionShape3D.new()
	_shape.shape = Assets.zombie_shape
	_shape.position.y = 0.9
	add_child(_shape)
	_model = ZombieModel.instantiate(0)
	add_child(_model)
	_body = _model.get_node("Skeleton3D/Body")
	_anim = _model.get_node("AnimationPlayer")
	_flames = MeshInstance3D.new()
	_flames.mesh = Assets.flame_mesh
	_flames.position.y = 0.9
	_flames.visible = false
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flames)


func t() -> Dictionary:
	return TYPES[type]


## `mesh` overrides the type's look (turned players, scientists).
func reset(pos: Vector3, p_type: String, variant: int, speed_mul: float, mesh: Mesh = null) -> void:
	type = p_type if TYPES.has(p_type) else "walker"
	position = pos
	rotation = Vector3(0, randf() * TAU, 0)
	velocity = Vector3.ZERO
	var looks: Array = ZombieModel.type_meshes.get(type, ZombieModel.meshes)
	_body.mesh = mesh if mesh else looks[variant % looks.size()]
	var sc: float = t().get("scale", 1.0)
	_model.scale = Vector3.ONE * sc
	match type:
		"brute":
			_shape.shape = Assets.brute_shape
			_shape.position = Vector3(0, 1.12, 0)
		"crawler":
			_shape.shape = Assets.crawler_shape
			_shape.position = Vector3(0, 0.25, 0.2)
		_:
			_shape.shape = Assets.zombie_shape
			_shape.position = Vector3(0, 0.9, 0)
	_one_shot = 0.0
	_anim.play(_idle_anim())
	_anim.seek(randf() * 2.0, true)
	max_health = float(t().hp)
	health = max_health
	state = State.WANDER
	target = pos
	collision_layer = 4
	collision_mask = 1
	physics_active = false
	accum = 0.0
	_speed_mul = speed_mul
	_think_t = 0.0
	awareness = 0.0
	last_sight_check = Time.get_ticks_msec()
	_stagger_t = 0.0
	_trap_t = 0.0
	_burn_t = 0.0
	_scream_cd = 0.0
	_entry = null
	_through_t = 0.0
	_move_t = 0.0
	_search_t = 0.0
	spawn_id = ""
	turned_id = ""
	turned_name = ""
	turned_owner = ""
	turned_items = []
	subdued = false
	_flames.visible = false
	visible = true


## Makes this zombie a turned player carrying their gear.
func make_turned(entry: Dictionary) -> void:
	turned_id = str(entry.id)
	turned_name = str(entry.get("name", "Survivor"))
	turned_owner = str(entry.get("owner", ""))
	turned_items = entry.get("items", [])
	max_health = 110.0
	health = max_health


func set_shadows(enabled: bool) -> void:
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func alive() -> bool:
	return state != State.DEAD and state != State.SUBDUED


func hear(pos: Vector3) -> void:
	if state == State.WANDER or state == State.INVESTIGATE:
		# Crawlers lying in wait only react to things close by.
		if type == "crawler" and position.distance_to(pos) > 12.0 and state == State.WANDER:
			return
		state = State.INVESTIGATE
		target = pos
		_search_t = 0.0


func see_player() -> void:
	if not alive():
		return
	if state != State.CHASE and type == "screamer":
		_scream()
	state = State.CHASE
	awareness = 1.0
	_lost_t = 0.0


## Partial sighting: builds awareness; a suspicious zombie turns to look, a
## sure one gives chase.
func notice(amount: float, where: Vector3) -> void:
	if not alive() or state == State.CHASE:
		if state == State.CHASE:
			_lost_t = 0.0
		return
	awareness = minf(1.0, awareness + amount)
	if awareness >= 1.0:
		see_player()
	elif awareness >= 0.4:
		state = State.INVESTIGATE
		target = where
		_search_t = 0.0


func unaware() -> bool:
	return state != State.CHASE and alive()


## Did a hit at world point `p` strike the head?
func head_hit(p: Vector3) -> bool:
	if type == "crawler":
		var head := global_position - global_basis.z * 0.8 + Vector3(0, 0.3, 0)
		return p.distance_to(head) < 0.3
	return p.y - global_position.y > 1.5 * float(t().get("scale", 1.0))


## True when `from` is behind this zombie (for silent takedowns).
func is_behind(from: Vector3) -> bool:
	var to := from - position
	to.y = 0.0
	return (-global_basis.z).dot(to.normalized()) < -0.25


func stagger(push: Vector3, time: float) -> void:
	if not alive():
		return
	# Brutes barely notice a shove.
	if type == "brute":
		time *= 0.15
		push *= 0.2
	_stagger_t = maxf(_stagger_t, time)
	velocity += push * 5.0
	position += push * 0.35
	if type != "crawler":
		_play_once("hit", minf(time, 0.6))


func ignite(time: float) -> void:
	if not alive():
		return
	_burn_t = maxf(_burn_t, time)
	_flames.visible = true


func trap(time: float) -> void:
	if alive():
		_trap_t = time


## Shriek: every zombie within earshot comes running.
func _scream() -> void:
	if _scream_cd > 0.0:
		return
	_scream_cd = 9.0
	GameState.make_noise(position, SCREAM_RADIUS)
	_play_once("scream", 1.4)
	_stagger_t = maxf(_stagger_t, 1.3)
	if mgr:
		mgr.screamed.emit(position)


## `use_physics` is true only close to the player, where collision matters.
## Farther away zombies just slide along the terrain height, which is far
## cheaper than move_and_slide.
func update_ai(dt: float, player: Player, dist: float, use_physics: bool, night: bool, gen: WorldGen) -> void:
	if state == State.DEAD:
		dead_timer -= dt
		return
	if state == State.SUBDUED:
		_subdue_t -= dt
		if _subdue_t <= 0.0:
			# Gets back up, angrier.
			subdued = false
			state = State.WANDER
			health = max_health * 0.4
			collision_layer = 4
			_anim.play(_idle_anim(), 0.3)
		return
	_attack_cd -= dt
	_think_t -= dt
	_scream_cd -= dt
	if state != State.CHASE:
		awareness = maxf(0.0, awareness - 0.1 * dt)
	if _burn_t > 0.0:
		_burn_t -= dt
		_flames.visible = _burn_t > 0.0
		take_damage(14.0 * dt, Vector3.ZERO, true, false)
		if not alive():
			_flames.visible = false
			return
	if _move_t > 0.0:
		_update_move(dt)
		return

	var speed := 0.0
	var ty := t()
	match state:
		State.WANDER:
			speed = float(ty.walk) * 0.6
			if _think_t <= 0.0 or _flat_dist(target) < 1.0:
				_think_t = randf_range(4.0, 9.0)
				# Zombies waiting indoors (and crawlers) don't stray far.
				var r := 3.0 if spawn_id != "" or type == "crawler" else 12.0
				target = position + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
		State.INVESTIGATE:
			speed = float(ty.walk) * 1.6
			_search_t += dt
			if _flat_dist(target) < 1.5 or _search_t > 25.0:
				state = State.WANDER
				_entry = null
				_think_t = randf_range(2.0, 5.0)
		State.CHASE:
			speed = float(ty.night if night else ty.chase)
			_lost_t += dt
			if player.dead:
				state = State.WANDER
			elif _lost_t < 6.0 or dist < 4.0:
				target = player.global_position
			else:
				# Lost you: search where you were last seen, then give up.
				state = State.INVESTIGATE
				_search_t = 0.0
	if GameState.zombie_speed() == 0:
		speed *= 0.8
	# Screamers keep their distance and keep shrieking.
	if type == "screamer" and state == State.CHASE:
		if _lost_t < 1.0:
			_scream()
		if dist < 10.0:
			target = position + (position - player.global_position).normalized() * 4.0

	var goal := target
	if _through_t > 0.0:
		_through_t -= dt
		goal = _through
	elif _entry != null and is_instance_valid(_entry):
		goal = _entry_goal()
	var to := goal - position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.05 else Vector3.ZERO
	if state == State.CHASE and dist < (1.3 if type == "crawler" else ATTACK_RANGE) * float(ty.get("scale", 1.0)) and type != "screamer":
		dir = Vector3.ZERO
		if _stagger_t <= 0.0:
			_try_attack(player)
	if _entry != null and _through_t <= 0.0:
		dir = _use_entry(dt, dir)
	if _stagger_t > 0.0:
		_stagger_t -= dt
		dir = Vector3.ZERO
	if _trap_t > 0.0:
		_trap_t -= dt
		dir = Vector3.ZERO
	if _detour_t > 0.0:
		_detour_t -= dt
		dir = (dir + _detour_dir * 1.5).normalized()
	speed *= _speed_mul

	# Zombies can't swim: they stop at deep water.
	if dir != Vector3.ZERO and gen.water_level(position.x + dir.x * 1.2, position.z + dir.z * 1.2) > position.y + 0.9:
		dir = Vector3.ZERO
	if dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, dt * 6.0))

	if use_physics:
		if not physics_active:
			physics_active = true
			position.y += 0.3
			velocity = Vector3.ZERO
		var before := position
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		velocity.y = -1.0 if is_on_floor() else velocity.y - GRAVITY * dt
		move_and_slide()
		_check_stuck(dt, before, speed if dir != Vector3.ZERO else 0.0, player)
	else:
		physics_active = false
		_entry = null
		position += dir * speed * dt
		position.y = gen.height(position.x, position.z)
	_choose_anim(dt, speed if dir != Vector3.ZERO else 0.0)


## Advances the skeleton animation. Called by ZombieManager, less often for
## distant zombies (animation level of detail).
func advance_anim(dt: float) -> void:
	_anim.advance(dt)


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - position.x, p.z - position.z).length()


## Steering straight at a target gets zombies stuck on walls, so when one stops
## making progress it looks for a way in (a door or window), climbs a low
## fence, or sidesteps for a moment.
func _check_stuck(dt: float, before: Vector3, speed: float, player: Player) -> void:
	if speed < 0.3 or _detour_t > 0.0:
		_stuck_t = 0.0
		return
	var moved := Vector2(position.x - before.x, position.z - before.z).length()
	if moved < speed * dt * 0.3:
		_stuck_t += dt
		if _stuck_t > 0.6:
			_stuck_t = 0.0
			if _entry == null and state != State.WANDER and _find_entry(player):
				return
			if _try_climb():
				return
			_detour_t = randf_range(0.8, 1.6)
			var side := 1.0 if randf() < 0.5 else -1.0
			_detour_dir = global_basis.x * side
	else:
		_stuck_t = 0.0


## Picks the door or window that best leads toward the target.
func _find_entry(player: Player) -> bool:
	if mgr == null or mgr.streamer == null:
		return false
	var best: Node3D = null
	var best_cost := INF
	for e: Node3D in mgr.streamer.entries_near(position, 16.0):
		if e is WindowBody and (type == "crawler" or type == "brute"):
			continue
		var cost := position.distance_to(e.global_position) + e.global_position.distance_to(target) * 1.2
		if e is WindowBody and not (e as WindowBody).smashed:
			cost += 4.0 # Smashing takes time; prefer doors.
		if cost < best_cost:
			best_cost = cost
			best = e
	if best == null or best_cost > position.distance_to(target) + 30.0:
		return false
	_entry = best
	_entry_t = 0.0
	return true


## The middle of the doorway or window.
func _entry_center() -> Vector3:
	var c := _entry.global_position
	if _entry is DoorBody:
		c += _entry.global_basis.x * 0.45 # Door transform is at the hinge.
	return c


## Which side of the entry this zombie is on (+1 / -1 along its normal).
func _entry_side() -> float:
	return 1.0 if (position - _entry_center()).dot(_entry.global_basis.z) >= 0.0 else -1.0


## Where to stand to use the entry: just in front of it, on this side.
func _entry_goal() -> Vector3:
	return _entry_center() + _entry.global_basis.z * _entry_side() * 0.7


## Close to the entry: open, batter, smash or climb through it.
func _use_entry(dt: float, dir: Vector3) -> Vector3:
	if not is_instance_valid(_entry):
		_entry = null
		return dir
	_entry_t += dt
	if _entry_t > 40.0 or state == State.WANDER:
		_entry = null
		return dir
	var goal := _entry_goal()
	if _flat_dist(goal) > 0.6:
		return dir
	var n := _entry.global_basis.z
	var side := _entry_side()
	if _entry is DoorBody:
		var door := _entry as DoorBody
		if door.zombie_push(position):
			_through = goal - n * side * 2.4
			_through_t = 1.6
			_entry = null
			return dir
		# Locked: batter it, but only while it knows you're there.
		if state == State.CHASE or (state == State.INVESTIGATE and _search_t < 20.0):
			if _attack_cd <= 0.0:
				_attack_cd = float(t().cd)
				door.damage(float(t().door) * float(t().cd), position)
				_play_once("attack" if type != "crawler" else "crawl_attack", 0.85)
				_face(door.global_position)
		return Vector3.ZERO
	var w := _entry as WindowBody
	if not w.smashed:
		if state == State.CHASE or state == State.INVESTIGATE:
			if _attack_cd <= 0.0:
				_attack_cd = float(t().cd) * 1.5
				_play_once("attack", 0.85)
				_face(w.global_position)
				if randf() < 0.5:
					w.smash()
		return Vector3.ZERO
	# Crawl through: over the sill, out the other side.
	var far := goal - n * side * 1.5
	_start_move(Vector3(far.x, _ground_at(far, position.y), far.z), 1.8)
	_entry = null
	return Vector3.ZERO


func _ground_at(p: Vector3, fallback: float) -> float:
	var down := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(p.x, p.y + 1.6, p.z), Vector3(p.x, p.y - 2.5, p.z), 1))
	return down.position.y if not down.is_empty() else fallback


func _face(p: Vector3) -> void:
	var d := p - position
	rotation.y = atan2(-d.x, -d.z)


## Low obstacle ahead (a fence, a car bonnet): clamber over it.
func _try_climb() -> bool:
	if type == "crawler" or type == "brute":
		return false
	var space := get_world_3d().direct_space_state
	var fwd := -global_basis.z
	var low := space.intersect_ray(PhysicsRayQueryParameters3D.create(position + Vector3(0, 0.45, 0), position + Vector3(0, 0.45, 0) + fwd * 0.9, 1))
	# Only upright obstacles (fences, walls), not a slope in the ground.
	if low.is_empty() or low.collider is DoorBody or low.collider is WindowBody or absf((low.normal as Vector3).y) > 0.5:
		return false
	var high := space.intersect_ray(PhysicsRayQueryParameters3D.create(position + Vector3(0, 1.45, 0), position + Vector3(0, 1.45, 0) + fwd * 1.6, 1))
	if not high.is_empty():
		return false
	# Find the ground on the far side.
	var over := position + fwd * 1.3
	var y := _ground_at(over, INF)
	if y == INF:
		return false
	_start_move(Vector3(over.x, y, over.z), 1.1)
	return true


func _start_move(to: Vector3, length: float) -> void:
	_move_from = position
	_move_to = to
	_move_len = length
	_move_t = length
	collision_mask = 0
	_play_once("crawl" if type == "crawler" else "attack", length)


func _update_move(dt: float) -> void:
	_move_t -= dt
	var k := 1.0 - clampf(_move_t / _move_len, 0.0, 1.0)
	var p := _move_from.lerp(_move_to, k)
	p.y = lerpf(_move_from.y, _move_to.y, k) + sin(k * PI) * 0.9
	position = p
	if _move_t <= 0.0:
		collision_mask = 1
		velocity = Vector3.ZERO
	_choose_anim(dt, 0.0)


func _idle_anim() -> String:
	return "crawl_idle" if type == "crawler" else "idle"


func _choose_anim(dt: float, speed: float) -> void:
	if _one_shot > 0.0:
		_one_shot -= dt
		return
	var want := _idle_anim()
	if type == "crawler":
		if speed > 0.1:
			want = "crawl"
	elif speed > 2.4:
		want = "run"
	elif speed > 0.2:
		want = "walk"
	if _anim.current_animation != want:
		_anim.play(want, 0.25)
	# Match the leg cycle to the ground speed so feet don't slide much.
	if want == "walk" or want == "run":
		_anim.speed_scale = clampf(speed / (1.0 if want == "walk" else 3.6), 0.5, 1.6)
	elif want == "crawl":
		_anim.speed_scale = clampf(speed / 0.6, 0.6, 2.0)
	else:
		_anim.speed_scale = 1.0


func _play_once(anim_name: String, length: float) -> void:
	if type == "crawler" and anim_name in ["attack", "hit"]:
		anim_name = "crawl_attack"
	_anim.play(anim_name, 0.08)
	_anim.speed_scale = 1.0
	_one_shot = length


func _try_attack(player: Player) -> void:
	if _attack_cd > 0.0 or player.dead:
		return
	_attack_cd = float(t().cd)
	var kind := "claw"
	match type:
		"brute":
			kind = "heavy"
			var push := (player.global_position - position).normalized()
			player.velocity += Vector3(push.x, 0.3, push.z) * 6.0
		"crawler":
			kind = "ankle"
			player.grab(1.2)
	player.zombie_hit(float(t().dmg), position, kind)
	_play_once("attack", 0.85)


## `head`: the hit was to the head (helmets and armour aside, soldiers only
## take full damage there). `blast`: explosions kill turned players outright.
func take_damage(amount: float, push: Vector3, alert := true, flinch := true, head := false, blast := false) -> void:
	if state == State.DEAD:
		return
	if state == State.SUBDUED:
		# Killing a subdued friend ends them for good.
		_die()
		return
	if t().has("armor") and not head:
		amount *= float(t().armor)
	health -= amount
	if alert:
		see_player()
	velocity += push * 4.0
	position += push * 0.25
	if health <= 0.0:
		# A turned player can be beaten down instead of killed, so friends
		# can give them the cure (not in a solo game, where you're the
		# only survivor).
		if turned_id != "" and turned_owner != GameState.player_id and not head and not blast:
			_subdue()
			return
		_die()
		return
	if flinch:
		_play_once("hit", 0.38)


## Silent kill from behind.
func takedown() -> void:
	if alive():
		health = 0.0
		_die()


func _subdue() -> void:
	health = 1.0
	state = State.SUBDUED
	subdued = true
	_subdue_t = SUBDUE_TIME
	_burn_t = 0.0
	_flames.visible = false
	_entry = null
	_anim.play("subdued", 0.2)
	_anim.speed_scale = 1.0
	GameState.notify("%s is down. Give them the cure!" % turned_name)


## The cure: a subdued turned player comes back.
func cure() -> void:
	if state != State.SUBDUED:
		return
	GameState.remove_turned(turned_id)
	if mgr:
		mgr.turned_cured.emit({"id": turned_id, "name": turned_name, "owner": turned_owner,
			"items": turned_items, "p": [position.x, position.y, position.z]})
	turned_id = ""
	turned_items = []
	subdued = false
	state = State.DEAD
	dead_timer = 0.0
	collision_layer = 0
	visible = false


func _die() -> void:
	var was_subdued := state == State.SUBDUED
	state = State.DEAD
	subdued = false
	dead_timer = CORPSE_TIME
	collision_layer = 0
	_flames.visible = false
	_entry = null
	_move_t = 0.0
	collision_mask = 1
	GameState.kills += 1
	GameState.character.stats.kills = int(GameState.character.stats.get("kills", 0)) + 1
	if mgr:
		mgr.zombie_died(self)
	_anim.play("crawl_death" if type == "crawler" else "death", 0.1)
	_anim.speed_scale = 1.0
	if was_subdued:
		_anim.seek(0.9, true)
