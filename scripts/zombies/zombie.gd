class_name Zombie
extends CharacterBody3D
## A single zombie. It has no _process/_physics_process of its own:
## ZombieManager drives every zombie so it can update far ones less often.

enum State { WANDER, INVESTIGATE, CHASE, DEAD }

const MAX_HEALTH := 60.0
const WALK_SPEED := 1.1
const CHASE_SPEED := 3.4
const NIGHT_CHASE_SPEED := 4.4
const ATTACK_RANGE := 1.5
const ATTACK_DAMAGE := 12.0
const ATTACK_COOLDOWN := 1.3
const GRAVITY := 14.0
const CORPSE_TIME := 10.0

var state := State.WANDER
var health := MAX_HEALTH
var target := Vector3.ZERO
var slot := 0
var accum := 0.0
var anim_accum := 0.0
var dead_timer := 0.0
var physics_active := false
## 0..1: how sure this zombie is that it has spotted the player (stealth).
var awareness := 0.0
var last_sight_check := 0

var _model: Node3D
var _body: MeshInstance3D
var _anim: AnimationPlayer
var _one_shot := 0.0 # Time left in an attack / hit animation.
var _attack_cd := 0.0
var _think_t := 0.0
var _lost_t := 0.0
var _stuck_t := 0.0
var _detour_t := 0.0
var _detour_dir := Vector3.ZERO
var _speed_mul := 1.0
var _stagger_t := 0.0 # Shoved or hit hard: can't move or attack.
var _trap_t := 0.0 # Caught in a bear trap.
var _burn_t := 0.0
var _flames: MeshInstance3D


func _init() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.5
	var cs := CollisionShape3D.new()
	cs.shape = Assets.zombie_shape
	cs.position.y = 0.9
	add_child(cs)
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


func reset(pos: Vector3, variant: int, speed_mul: float) -> void:
	position = pos
	rotation = Vector3(0, randf() * TAU, 0)
	velocity = Vector3.ZERO
	_body.mesh = ZombieModel.meshes[variant % ZombieModel.meshes.size()]
	_one_shot = 0.0
	_anim.play("idle")
	_anim.seek(randf() * 2.0, true)
	health = MAX_HEALTH
	state = State.WANDER
	target = pos
	collision_layer = 4
	physics_active = false
	accum = 0.0
	_speed_mul = speed_mul
	_think_t = 0.0
	awareness = 0.0
	last_sight_check = Time.get_ticks_msec()
	_stagger_t = 0.0
	_trap_t = 0.0
	_burn_t = 0.0
	_flames.visible = false
	visible = true


func set_shadows(enabled: bool) -> void:
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func hear(pos: Vector3) -> void:
	if state == State.WANDER or state == State.INVESTIGATE:
		state = State.INVESTIGATE
		target = pos


func see_player() -> void:
	if state != State.DEAD:
		state = State.CHASE
		awareness = 1.0
		_lost_t = 0.0


## Partial sighting: builds awareness; a suspicious zombie turns to look, a
## sure one gives chase.
func notice(amount: float, where: Vector3) -> void:
	if state == State.DEAD or state == State.CHASE:
		if state == State.CHASE:
			_lost_t = 0.0
		return
	awareness = minf(1.0, awareness + amount)
	if awareness >= 1.0:
		see_player()
	elif awareness >= 0.4:
		state = State.INVESTIGATE
		target = where


func unaware() -> bool:
	return state != State.CHASE and state != State.DEAD


## True when `from` is behind this zombie (for silent takedowns).
func is_behind(from: Vector3) -> bool:
	var to := from - position
	to.y = 0.0
	return (-global_basis.z).dot(to.normalized()) < -0.25


func stagger(push: Vector3, time: float) -> void:
	if state == State.DEAD:
		return
	_stagger_t = maxf(_stagger_t, time)
	velocity += push * 5.0
	position += push * 0.35
	_play_once("hit", minf(time, 0.6))


func ignite(time: float) -> void:
	if state == State.DEAD:
		return
	_burn_t = maxf(_burn_t, time)
	_flames.visible = true


func trap(time: float) -> void:
	if state != State.DEAD:
		_trap_t = time


## `use_physics` is true only close to the player, where collision matters.
## Farther away zombies just slide along the terrain height, which is far
## cheaper than move_and_slide.
func update_ai(dt: float, player: Player, dist: float, use_physics: bool, night: bool, gen: WorldGen) -> void:
	if state == State.DEAD:
		dead_timer -= dt
		return
	_attack_cd -= dt
	_think_t -= dt
	if state != State.CHASE:
		awareness = maxf(0.0, awareness - 0.1 * dt)
	if _burn_t > 0.0:
		_burn_t -= dt
		_flames.visible = _burn_t > 0.0
		take_damage(14.0 * dt, Vector3.ZERO, true, false)
		if state == State.DEAD:
			_flames.visible = false
			return

	var speed := 0.0
	match state:
		State.WANDER:
			speed = WALK_SPEED * 0.6
			if _think_t <= 0.0 or _flat_dist(target) < 1.0:
				_think_t = randf_range(4.0, 9.0)
				target = position + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
		State.INVESTIGATE:
			speed = WALK_SPEED * 1.6
			if _flat_dist(target) < 1.5:
				state = State.WANDER
				_think_t = randf_range(2.0, 5.0)
		State.CHASE:
			speed = NIGHT_CHASE_SPEED if night else CHASE_SPEED
			_lost_t += dt
			if player.dead:
				state = State.WANDER
			elif dist < 25.0 or _lost_t < 6.0:
				target = player.global_position
			else:
				state = State.INVESTIGATE

	var to := target - position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.05 else Vector3.ZERO
	if state == State.CHASE and dist < ATTACK_RANGE:
		dir = Vector3.ZERO
		if _stagger_t <= 0.0:
			_try_attack(player)
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
		_check_stuck(dt, before, speed if dir != Vector3.ZERO else 0.0)
	else:
		physics_active = false
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
## making progress it sidesteps for a moment.
func _check_stuck(dt: float, before: Vector3, speed: float) -> void:
	if speed < 0.5 or _detour_t > 0.0:
		_stuck_t = 0.0
		return
	var moved := Vector2(position.x - before.x, position.z - before.z).length()
	if moved < speed * dt * 0.3:
		_stuck_t += dt
		if _stuck_t > 0.6:
			_stuck_t = 0.0
			_detour_t = randf_range(0.8, 1.6)
			var side := 1.0 if randf() < 0.5 else -1.0
			_detour_dir = global_basis.x * side
	else:
		_stuck_t = 0.0


func _choose_anim(dt: float, speed: float) -> void:
	if _one_shot > 0.0:
		_one_shot -= dt
		return
	var want := "idle"
	if speed > 2.4:
		want = "run"
	elif speed > 0.2:
		want = "walk"
	if _anim.current_animation != want:
		_anim.play(want, 0.25)
	# Match the leg cycle to the ground speed so feet don't slide much.
	_anim.speed_scale = clampf(speed / (1.0 if want == "walk" else 3.6), 0.5, 1.6) if want != "idle" else 1.0


func _play_once(anim_name: String, length: float) -> void:
	_anim.play(anim_name, 0.08)
	_anim.speed_scale = 1.0
	_one_shot = length


func _try_attack(player: Player) -> void:
	if _attack_cd > 0.0 or player.dead:
		return
	_attack_cd = ATTACK_COOLDOWN
	player.take_damage(ATTACK_DAMAGE, position)
	_play_once("attack", 0.85)


func take_damage(amount: float, push: Vector3, alert := true, flinch := true) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if alert:
		see_player()
	velocity += push * 4.0
	position += push * 0.25
	if health <= 0.0:
		_die()
		return
	if flinch:
		_play_once("hit", 0.38)


## Silent kill from behind.
func takedown() -> void:
	if state != State.DEAD:
		health = 0.0
		_die()


func _die() -> void:
	state = State.DEAD
	dead_timer = CORPSE_TIME
	collision_layer = 0
	_flames.visible = false
	GameState.kills += 1
	_anim.play("death", 0.1)
	_anim.speed_scale = 1.0
