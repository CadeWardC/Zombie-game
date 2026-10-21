class_name Player
extends CharacterBody3D
## First-person survivor: movement (walk, sprint, crouch, swim), look (mouse,
## touch and gamepad, with aim assist on gamepads), survival stats, stealth
## visibility, using items and interacting with doors, containers and items
## on the ground. Weapons live in the Weapons child node.

signal damaged
signal died
## Ask the game to open the inventory; `container` is empty for just the bag.
signal open_inventory(container: Dictionary)

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.0
const CROUCH_SPEED := 2.0
const AIM_SPEED := 2.6
const JUMP_VELOCITY := 4.8
const GRAVITY := 14.0
const MOUSE_SENS := 0.0025
const TOUCH_SENS := 0.006
const PAD_SENS := 3.0
const EYE_HEIGHT := 1.65
const CROUCH_EYE := 1.05
const REACH := 2.6

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
var crouching := false
var in_cover := false
var touch: TouchControls
var gen: WorldGen
var streamer: WorldStreamer
var zombies: ZombieManager
var drops: DropManager
var swimming := false
## Text for the HUD's interaction prompt ("" when nothing is in reach).
var prompt := ""

var head: Node3D
var camera: Camera3D
var flashlight: SpotLight3D
var weapons: Weapons
var _stamina_delay := 0.0
var _exhausted := false
var _noise_t := 0.0
var _bob_t := 0.0
var _last_bob := 0.0
var _shake := 0.0
var _prompt_t := 0.0
var _cover_t := 0.0
var _recoil := 0.0 # Pitch still to recover from recoil (radians).
var _assist_t := 0.0
var _assist_target: Zombie
var _focus: Variant = null # DoorBody, container dictionary or drop dictionary in reach.


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

	weapons = Weapons.new()
	weapons.player = self
	camera.add_child(weapons)

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
	if dead or not active or GameState.ui_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * MOUSE_SENS * (0.6 if weapons.aim_blend > 0.5 else 1.0))


func _look(delta: Vector2) -> void:
	rotate_y(-delta.x)
	head.rotation.x = clampf(head.rotation.x - delta.y, deg_to_rad(-85), deg_to_rad(85))


func _physics_process(delta: float) -> void:
	if not active:
		return
	if dead:
		velocity = Vector3.ZERO
		return
	var can_act := not GameState.ui_open

	# Look from touch and gamepad.
	if touch and can_act:
		_look(touch.consume_look() * TOUCH_SENS * (0.6 if weapons.aim_blend > 0.5 else 1.0))
	var pad_look := Input.get_vector("look_left", "look_right", "look_up", "look_down") if can_act else Vector2.ZERO
	if pad_look != Vector2.ZERO:
		_look(pad_look * PAD_SENS * delta * _aim_assist_slowdown())
	_aim_assist(delta, pad_look)
	_recover_recoil(delta)

	# Movement.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if can_act else Vector2.ZERO
	if touch and can_act:
		input += touch.move_vector
	input = input.limit_length(1.0)
	var dir := transform.basis * Vector3(input.x, 0, input.y)
	var moving := input.length() > 0.1
	if can_act and Input.is_action_just_pressed("crouch"):
		crouching = not crouching
	sprinting = Input.is_action_pressed("sprint") and moving and input.y < 0.3 and not _exhausted and can_act
	if sprinting:
		crouching = false
	var speed := SPRINT_SPEED if sprinting else (CROUCH_SPEED if crouching else WALK_SPEED)
	if weapons.aim_blend > 0.5:
		speed = minf(speed, AIM_SPEED)
	speed *= GameState.inventory.speed_factor()
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = lerpf(velocity.x, dir.x * speed, minf(1.0, accel * delta))
	velocity.z = lerpf(velocity.z, dir.z * speed, minf(1.0, accel * delta))
	var water := gen.water_level(position.x, position.z) if gen else -INF
	swimming = water > -INF and position.y < water - 1.1
	if swimming:
		# Float with the head just above the surface; jump swims up.
		var target := water - 1.35
		velocity.y = lerpf(velocity.y, (target - position.y) * 3.0, minf(1.0, delta * 4.0))
		if Input.is_action_pressed("jump") and can_act:
			velocity.y = 1.5
		velocity.x *= 0.55
		velocity.z *= 0.55
		sprinting = false
		crouching = false
	elif is_on_floor():
		if can_act and Input.is_action_just_pressed("jump") and stamina > 10.0:
			velocity.y = JUMP_VELOCITY
			crouching = false
			use_stamina(10.0)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	_keep_in_world()

	_update_stats(delta, moving)
	_update_noise(delta, moving)
	_update_camera(delta, moving)
	_update_cover(delta)

	if not can_act:
		return
	if not swimming:
		weapons.update(delta, moving)
	if Input.is_action_just_pressed("quick_eat"):
		quick_use(["drink"] if thirst < hunger else ["food"], ["food", "drink"])
	if Input.is_action_just_pressed("quick_heal"):
		quick_use(["medical"], [])
	if Input.is_action_just_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	if Input.is_action_just_pressed("inventory"):
		open_inventory.emit({})
	_prompt_t -= delta
	if _prompt_t <= 0.0:
		_prompt_t = 0.12
		_update_focus()
	if Input.is_action_just_pressed("interact"):
		_interact()


func _keep_in_world() -> void:
	var lim := gen.world_size - 20.0 if gen else 1e9
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
		use_stamina(18.0 * delta)
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


func use_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_stamina_delay = 1.0
	if stamina <= 0.0:
		_exhausted = true


## Zombies hear footsteps: sprinting is loud, sneaking almost silent.
func _update_noise(delta: float, moving: bool) -> void:
	_noise_t -= delta
	if moving and is_on_floor() and _noise_t <= 0.0:
		_noise_t = 0.5
		GameState.make_noise(global_position, 16.0 if sprinting else (1.2 if crouching else 6.0))


func _update_camera(delta: float, moving: bool) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if moving and is_on_floor():
		_bob_t += delta * hspeed * 1.8
	var bob := sin(_bob_t) * 0.04 * minf(hspeed / WALK_SPEED, 1.5) * (1.0 - weapons.aim_blend * 0.8)
	_shake = maxf(0.0, _shake - delta * 2.0)
	# Ease the eye height (crouching) separately from the head bob.
	var eye := CROUCH_EYE if crouching else EYE_HEIGHT
	var base := head.position.y - _last_bob
	head.position.y = lerpf(base, eye, minf(1.0, delta * 10.0)) + bob
	_last_bob = bob
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.05
	camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.05
	var fov := weapons.target_fov(82.0 if sprinting else 75.0)
	camera.fov = lerpf(camera.fov, fov, minf(1.0, delta * 10.0))


## Bushes hide you (checked a few times a second).
func _update_cover(delta: float) -> void:
	_cover_t -= delta
	if _cover_t > 0.0 or streamer == null:
		return
	_cover_t = 0.25
	in_cover = streamer.cover_distance(global_position, 1.7) < INF


## How visible you are to zombies (scales how far they can see you).
func visibility() -> float:
	var v := 1.0
	if crouching:
		v *= 0.55
	if sprinting:
		v *= 1.25
	if in_cover:
		v *= 0.35 if crouching else 0.65
	if gen and gen.is_inside_building(global_position.x, global_position.z):
		v *= 0.8
		if GameState.is_night() and not flashlight.visible:
			v *= 0.6
	return v


func hidden() -> bool:
	return visibility() < 0.4


# --- Recoil and aim assist --------------------------------------------------

func add_recoil(degrees: float) -> void:
	var kick := deg_to_rad(degrees) * randf_range(0.8, 1.2)
	head.rotation.x = clampf(head.rotation.x + kick, deg_to_rad(-85), deg_to_rad(85))
	rotate_y(deg_to_rad(degrees) * randf_range(-0.25, 0.25))
	_recoil += kick * 0.6 # Most of the kick settles back on its own.
	_shake = maxf(_shake, degrees * 0.05)


func _recover_recoil(delta: float) -> void:
	if _recoil <= 0.0:
		return
	var step := minf(_recoil, delta * 0.35)
	_recoil -= step
	head.rotation.x -= step


## The zombie nearest the crosshair, if close to it (refreshed 10x a second).
func _assist_candidate() -> Zombie:
	if zombies == null or not weapons.is_ranged():
		return null
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var best: Zombie = null
	var best_dot := cos(deg_to_rad(6.0))
	for z in zombies.in_radius(global_position, 60.0):
		var to := (z.global_position + Vector3(0, 1.3, 0) - from).normalized()
		var dot := fwd.dot(to)
		if dot > best_dot:
			best_dot = dot
			best = z
	return best


func _aim_assist_slowdown() -> float:
	return 0.5 if _assist_target != null and GameState.using_gamepad() else 1.0


## Gamepad aim assist: gentle pull toward a zombie near the crosshair while
## aiming. Off for touch and mouse.
func _aim_assist(delta: float, pad_look: Vector2) -> void:
	_assist_t -= delta
	if _assist_t <= 0.0:
		_assist_t = 0.1
		_assist_target = _assist_candidate() if GameState.using_gamepad() else null
	var z := _assist_target
	if z == null or z.state == Zombie.State.DEAD or weapons.aim_blend < 0.5:
		return
	if pad_look == Vector2.ZERO and velocity.length() < 0.5:
		return
	var to := z.global_position + Vector3(0, 1.35, 0) - camera.global_position
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	rotation.y = lerp_angle(rotation.y, want_yaw, minf(1.0, delta * 2.5))
	head.rotation.x = lerpf(head.rotation.x, want_pitch, minf(1.0, delta * 2.5))


# --- Interaction -------------------------------------------------------------

## Finds what the player is looking at: a door (raycast), a container or an
## item on the ground (nearest one in front, within reach).
func _update_focus() -> void:
	_focus = null
	prompt = ""
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + fwd * REACH, 1, [get_rid()]))
	if not hit.is_empty() and hit.collider is DoorBody:
		_focus = hit.collider
		prompt = "Close door" if hit.collider.is_open else "Open door"
		return
	var best_score := 0.0
	var candidates: Array = []
	if streamer:
		candidates.append_array(streamer.containers_near(from, 2.4))
	if drops:
		candidates.append_array(drops.near(global_position, 2.6))
	for c in candidates:
		var is_container: bool = c.has("pos")
		var pos: Vector3 = c.pos if is_container else DropManager._pos(c) + Vector3(0, 0.15, 0)
		var to: Vector3 = pos - from
		var score := fwd.dot(to.normalized())
		if score > (0.75 if is_container else 0.82) and score > best_score:
			# Something solid in between (a wall) means it's out of reach.
			var block := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, pos - to.normalized() * 0.25, 1, [get_rid()]))
			if block.is_empty():
				best_score = score
				_focus = c
	if _focus == null:
		if weapons.current == "melee" and crouching and _takedown_ready():
			prompt = "Silent takedown"
		return
	if _focus.has("pos"):
		var opened := GameState.containers.has(_focus.id)
		var empty := opened and (GameState.containers[_focus.id] as Array).is_empty()
		prompt = ("%s (empty)" if empty else "Search %s") % Loot.label(_focus.type)
	else:
		var it: Dictionary = _focus.it
		var n := int(it.get("n", 1))
		prompt = "Pick up %s%s" % [ItemDB.item_name(it.id), " x%d" % n if n > 1 else ""]
		if _focus.get("armed", false):
			prompt = "Disarm bear trap"


func _takedown_ready() -> bool:
	if zombies == null:
		return false
	for z in zombies.in_radius(global_position, 1.9):
		if z.unaware() and z.is_behind(global_position):
			var to := (z.global_position - global_position).normalized()
			if (-global_basis.z).dot(to) > 0.6:
				return true
	return false


func _interact() -> void:
	if _focus == null:
		return
	if _focus is DoorBody:
		_focus.interact(global_position)
		GameState.make_noise(global_position, 4.0)
	elif _focus.has("pos"):
		GameState.container_items(_focus)
		GameState.make_noise(global_position, 2.0)
		open_inventory.emit(_focus)
	else:
		pick_up(_focus)
	_prompt_t = 0.0


func pick_up(drop: Dictionary) -> void:
	var it: Dictionary = (drop.it as Dictionary).duplicate(true)
	GameState.remove_drop(drop)
	GameState.add_item(it, DropManager._pos(drop))


# --- Items -------------------------------------------------------------------

## Eats, drinks or applies an item from the inventory. Returns true if used.
func consume(it: Dictionary) -> bool:
	if dead or not ItemDB.is_consumable(it.id):
		return false
	var d := ItemDB.get_def(it.id)
	hunger = clampf(hunger + float(d.get("hunger", 0.0)), 0.0, 100.0)
	thirst = clampf(thirst + float(d.get("thirst", 0.0)), 0.0, 100.0)
	health = minf(100.0, health + float(d.get("health", 0.0)))
	stamina = minf(100.0, stamina + float(d.get("stamina", 0.0)))
	it.n = int(it.get("n", 1)) - 1
	if int(it.n) <= 0:
		GameState.inventory.detach(it)
	GameState.inventory.notify()
	GameState.notify("Used %s" % ItemDB.item_name(it.id))
	if it.id == "water_bottle":
		# Keep the empty bottle: it's a throwable distraction.
		GameState.add_item(ItemDB.make("glass_bottle"), global_position)
	return true


## Uses the first carried item in one of the categories (`first`, then
## `fallback`). Bound to the quick-use buttons.
func quick_use(first: Array, fallback: Array) -> void:
	for cats in [first, fallback]:
		for g in GameState.inventory.grids():
			for it in g.items:
				if ItemDB.get_def(it.id).get("cat", "") in cats:
					consume(it)
					return
	GameState.notify("Nothing to %s" % ("heal with" if "medical" in first else "eat or drink"))


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
		crouching = false
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
	crouching = false
	_exhausted = false
	_last_bob = 0.0
	head.rotation = Vector3.ZERO
	head.position.y = EYE_HEIGHT
	weapons.select("melee")


func to_dict() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"health": health, "hunger": hunger, "thirst": thirst,
		"weapon": weapons.current,
	}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		global_position = Vector3(p[0], p[1] + 0.5, p[2])
	rotation.y = float(d.get("yaw", 0.0))
	health = maxf(1.0, float(d.get("health", 100.0)))
	hunger = float(d.get("hunger", 100.0))
	thirst = float(d.get("thirst", 100.0))
	weapons.select(str(d.get("weapon", "melee")))
