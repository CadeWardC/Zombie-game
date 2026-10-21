class_name Player
extends CharacterBody3D
## First-person survivor: movement, look (mouse, touch and gamepad), melee
## combat, survival stats and item use.

signal damaged
signal died

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.0
const JUMP_VELOCITY := 4.8
const GRAVITY := 14.0
const MOUSE_SENS := 0.0025
const TOUCH_SENS := 0.006
const PAD_SENS := 3.0
const ATTACK_RANGE := 2.6
const ATTACK_COOLDOWN := 0.55
const ATTACK_DAMAGE := 34.0
const EYE_HEIGHT := 1.65

# Survival tuning: hunger empties in ~16 minutes, thirst in ~11.
const HUNGER_RATE := 100.0 / 960.0
const THIRST_RATE := 100.0 / 660.0
const STARVE_DAMAGE := 1.0
const REGEN_RATE := 0.4

var health := 100.0
var hunger := 100.0
var thirst := 100.0
var stamina := 100.0
var dead := false
var active := false # False while the world is still loading.
var sprinting := false
var touch: TouchControls
var gen: WorldGen

var head: Node3D
var camera: Camera3D
var flashlight: SpotLight3D
var _weapon: Node3D
var _attack_cd := 0.0
var _stamina_delay := 0.0
var _exhausted := false
var _noise_t := 0.0
var _bob_t := 0.0
var _shake := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)

	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)

	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	head.add_child(camera)

	_weapon = Node3D.new()
	_weapon.position = Vector3(0.32, -0.32, -0.45)
	_weapon.rotation_degrees = Vector3(-60, 10, -20)
	camera.add_child(_weapon)
	var bat := MeshInstance3D.new()
	bat.mesh = Assets.weapon_mesh
	bat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_weapon.add_child(bat)

	flashlight = SpotLight3D.new()
	flashlight.spot_range = 28.0
	flashlight.spot_angle = 30.0
	flashlight.light_energy = 2.5
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.shadow_enabled = false
	flashlight.visible = false
	flashlight.position = Vector3(0.2, -0.1, 0)
	camera.add_child(flashlight)


func _unhandled_input(event: InputEvent) -> void:
	if dead or not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * MOUSE_SENS)


func _look(delta: Vector2) -> void:
	rotate_y(-delta.x)
	head.rotation.x = clampf(head.rotation.x - delta.y, deg_to_rad(-85), deg_to_rad(85))


func _physics_process(delta: float) -> void:
	if not active:
		return
	if dead:
		velocity = Vector3.ZERO
		return

	# Look from touch and gamepad.
	if touch:
		_look(touch.consume_look() * TOUCH_SENS)
	var pad_look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if pad_look != Vector2.ZERO:
		_look(pad_look * PAD_SENS * delta)

	# Movement.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch:
		input += touch.move_vector
	input = input.limit_length(1.0)
	var dir := transform.basis * Vector3(input.x, 0, input.y)
	var moving := input.length() > 0.1
	sprinting = Input.is_action_pressed("sprint") and moving and input.y < 0.3 and not _exhausted
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = lerpf(velocity.x, dir.x * speed, minf(1.0, accel * delta))
	velocity.z = lerpf(velocity.z, dir.z * speed, minf(1.0, accel * delta))
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and stamina > 10.0:
			velocity.y = JUMP_VELOCITY
			_use_stamina(10.0)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	_keep_in_world()

	_update_stats(delta, moving)
	_update_noise(delta, moving)
	_update_camera(delta, moving)

	_attack_cd -= delta
	if Input.is_action_pressed("attack") and _attack_cd <= 0.0:
		_attack()
	if Input.is_action_just_pressed("use_food"):
		use_item("food")
	if Input.is_action_just_pressed("use_water"):
		use_item("water")
	if Input.is_action_just_pressed("use_bandage"):
		use_item("bandage")
	if Input.is_action_just_pressed("flashlight"):
		flashlight.visible = not flashlight.visible


func _keep_in_world() -> void:
	var lim := WorldGen.WORLD_SIZE - 20.0
	position.x = clampf(position.x, 20.0, lim)
	position.z = clampf(position.z, 20.0, lim)
	# Safety net: if we ever fall through the ground, put us back on top.
	if gen and position.y < gen.height(position.x, position.z) - 5.0:
		position.y = gen.height(position.x, position.z) + 1.0
		velocity = Vector3.ZERO


func _update_stats(delta: float, moving: bool) -> void:
	hunger = maxf(0.0, hunger - HUNGER_RATE * delta * (1.5 if sprinting else 1.0))
	thirst = maxf(0.0, thirst - THIRST_RATE * delta * (1.5 if sprinting else 1.0))
	if sprinting:
		_use_stamina(18.0 * delta)
	else:
		_stamina_delay -= delta
		if _stamina_delay <= 0.0:
			stamina = minf(100.0, stamina + (14.0 if not moving else 9.0) * delta)
	if _exhausted and stamina > 30.0:
		_exhausted = false
	if hunger <= 0.0 or thirst <= 0.0:
		take_damage(STARVE_DAMAGE * delta, Vector3.ZERO, false)
	elif hunger > 50.0 and thirst > 50.0:
		health = minf(100.0, health + REGEN_RATE * delta)


func _use_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_stamina_delay = 1.0
	if stamina <= 0.0:
		_exhausted = true


## Zombies hear footsteps; sprinting is much louder than walking.
func _update_noise(delta: float, moving: bool) -> void:
	_noise_t -= delta
	if moving and is_on_floor() and _noise_t <= 0.0:
		_noise_t = 0.5
		GameState.make_noise(global_position, 16.0 if sprinting else 6.0)


func _update_camera(delta: float, moving: bool) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if moving and is_on_floor():
		_bob_t += delta * hspeed * 1.8
	var bob := sin(_bob_t) * 0.04 * minf(hspeed / WALK_SPEED, 1.5)
	_shake = maxf(0.0, _shake - delta * 2.0)
	head.position.y = EYE_HEIGHT + bob
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.05
	camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.05
	camera.fov = lerpf(camera.fov, 82.0 if sprinting else 75.0, minf(1.0, delta * 6.0))


func _attack() -> void:
	if stamina < 5.0:
		return
	_attack_cd = ATTACK_COOLDOWN
	_use_stamina(6.0)
	var tw := create_tween()
	tw.tween_property(_weapon, "rotation_degrees", Vector3(-10, -40, -70), 0.08)
	tw.tween_property(_weapon, "rotation_degrees", Vector3(-60, 10, -20), 0.25)
	GameState.make_noise(global_position, 10.0)

	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var forward := -camera.global_basis.z
	var push := Vector3(forward.x, 0, forward.z).normalized()

	# A precise ray first, so aiming at the head pays off...
	var ray := PhysicsRayQueryParameters3D.create(from, from + forward * ATTACK_RANGE, 1 | 4, [get_rid()])
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and hit.collider is Zombie:
		var z: Zombie = hit.collider
		var headshot: bool = hit.position.y - z.global_position.y > 1.45
		z.take_damage(ATTACK_DAMAGE * (2.0 if headshot else 1.0), push)
		return
	# ...then a forgiving sweep in front of the player, because pixel-precise
	# aiming is frustrating on a touchscreen.
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = 4
	q.transform = Transform3D(Basis.IDENTITY, from + forward * (ATTACK_RANGE * 0.55))
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
		return
	# Don't hit through walls.
	var wall := PhysicsRayQueryParameters3D.create(from, best.global_position + Vector3(0, 1.2, 0), 1)
	if space.intersect_ray(wall).is_empty():
		best.take_damage(ATTACK_DAMAGE, push)


func use_item(type: String) -> void:
	if dead:
		return
	if not GameState.take_item(type):
		GameState.notify("No %s left" % GameState.ITEM_NAMES[type])
		return
	match type:
		"food":
			hunger = minf(100.0, hunger + 35.0)
		"water":
			thirst = minf(100.0, thirst + 40.0)
		"bandage":
			health = minf(100.0, health + 30.0)
	GameState.notify("Used %s" % GameState.ITEM_NAMES[type])


func take_damage(amount: float, _from: Vector3, feedback := true) -> void:
	if dead:
		return
	health -= amount
	if feedback:
		_shake = 1.0
		damaged.emit()
	if health <= 0.0:
		health = 0.0
		dead = true
		flashlight.visible = false
		var tw := create_tween()
		tw.tween_property(head, "position:y", 0.3, 0.6)
		tw.parallel().tween_property(head, "rotation:z", deg_to_rad(70), 0.6)
		died.emit()


func respawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	health = 100.0
	hunger = 80.0
	thirst = 80.0
	stamina = 100.0
	dead = false
	_exhausted = false
	head.rotation = Vector3.ZERO
	head.position.y = EYE_HEIGHT


func to_dict() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"health": health, "hunger": hunger, "thirst": thirst,
	}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		global_position = Vector3(p[0], p[1] + 0.5, p[2])
	rotation.y = float(d.get("yaw", 0.0))
	health = maxf(1.0, float(d.get("health", 100.0)))
	hunger = float(d.get("hunger", 100.0))
	thirst = float(d.get("thirst", 100.0))
