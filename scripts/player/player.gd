class_name Player
extends CharacterBody3D
## First-person survivor: movement (walk, sprint, crouch, swim), look (mouse,
## touch and gamepad, with aim assist on gamepads), survival stats, injuries
## and infection (in `body`), stealth visibility, using items and interacting
## with doors, windows, containers, generators and items on the ground.
## Weapons live in the Weapons child node. Traits and skills come from
## GameState.character.

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
var body := Health.new()
## What killed you, for the death screen and memorial.
var death_cause := ""
## True when the infection finished you (you rise as a zombie).
var turned := false
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
var vehicles: VehicleManager
var vehicle_menu: VehicleMenu
## The vehicle you're sitting in (null on foot) and which seat (0 drives).
var vehicle: Vehicle
var seat := -1
var swimming := false
## Text for the HUD's interaction prompt ("" when nothing is in reach), the
## action it's bound to, and what holding interact does ("" for nothing).
var prompt := ""
var prompt_action := "interact"
var hold_prompt := ""

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
var _focus: Variant = null # DoorBody, WindowBody, Zombie, container or drop dictionary in reach.
var _hold_t := 0.0 # How long interact has been held (locking doors, generators).
var _hold_done := false
var _air_speed := 0.0 # Fastest fall speed since leaving the ground.
var _cough_t := 30.0
var _grab_t := 0.0 # Held by a crawler.
var _climb_t := 0.0 # Climbing through a window.
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _crave_told := false
var _ping_t := -1.0
var _cam_yaw := 0.0 # Chase camera orbit, relative to the vehicle.
var _cam_pitch := -0.25
var _cam_idle := 0.0
var _bang_t := 0.0


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
	if vehicle:
		_cam_yaw -= delta.x
		_cam_pitch = clampf(_cam_pitch - delta.y, -1.2, 0.5)
		_cam_idle = 0.0
		return
	rotate_y(-delta.x)
	head.rotation.x = clampf(head.rotation.x - delta.y, deg_to_rad(-85), deg_to_rad(85))


func _physics_process(delta: float) -> void:
	if not active:
		return
	if dead:
		velocity = Vector3.ZERO
		return
	if vehicle:
		_in_vehicle(delta)
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
	sprinting = Input.is_action_pressed("sprint") and moving and input.y < 0.3 and not _exhausted and can_act and body.can_sprint()
	if sprinting:
		crouching = false
	var ch := GameState.character
	var speed := SPRINT_SPEED * ch.mod("sprint") if sprinting else (CROUCH_SPEED if crouching else WALK_SPEED)
	if weapons.aim_blend > 0.5:
		speed = minf(speed, AIM_SPEED)
	speed *= GameState.inventory.speed_factor() * body.speed_factor()
	if _grab_t > 0.0:
		_grab_t -= delta
		speed *= 0.15
	if _climb_t > 0.0:
		_update_climb(delta)
		return
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
		_air_speed = maxf(_air_speed, -velocity.y)
	var was_air := not is_on_floor()
	move_and_slide()
	if was_air and is_on_floor():
		_land(_air_speed)
		_air_speed = 0.0
	if swimming:
		_air_speed = 0.0
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
	# A weapon light throws a longer, tighter beam while that gun is out.
	var gun_light := weapons.has_part("light") != ""
	flashlight.spot_range = 42.0 if gun_light else 28.0
	flashlight.spot_angle = 20.0 if gun_light else 30.0
	if Input.is_action_just_pressed("inventory"):
		open_inventory.emit({})
	_prompt_t -= delta
	if _prompt_t <= 0.0:
		_prompt_t = 0.12
		_update_focus()
	_update_interact(delta)
	_update_ping(delta)


func _keep_in_world() -> void:
	var lim := gen.world_size - 20.0 if gen else 1e9
	position.x = clampf(position.x, 20.0, lim)
	position.z = clampf(position.z, 20.0, lim)
	# Safety net: if we ever fall through the ground, put us back on top.
	if gen and position.y < gen.height(position.x, position.z) - 5.0:
		position.y = gen.height(position.x, position.z) + 1.0
		velocity = Vector3.ZERO


func _update_stats(delta: float, moving: bool) -> void:
	var ch := GameState.character
	hunger = maxf(0.0, hunger - HUNGER_RATE * ch.mod("hunger") * delta * (1.5 if sprinting else 1.0))
	thirst = maxf(0.0, thirst - THIRST_RATE * delta * (1.5 if sprinting else 1.0))
	if sprinting:
		use_stamina(18.0 * delta)
	else:
		_stamina_delay -= delta
		if _stamina_delay <= 0.0:
			var regen := (14.0 if not moving else 9.0) * (0.7 if craving() else 1.0) * (1.0 - body.symptoms() * 0.5)
			stamina = minf(max_stamina(), stamina + regen * delta)
	stamina = minf(stamina, max_stamina())
	if _exhausted and stamina > 30.0:
		_exhausted = false
	if hunger <= 0.0 or thirst <= 0.0:
		death_cause = "Starved" if hunger <= 0.0 else "Died of thirst"
		take_damage(STARVE_DAMAGE * delta, Vector3.ZERO, false)
	elif hunger > 50.0 and thirst > 50.0:
		health = minf(100.0, health + REGEN_RATE * body.regen_factor() * delta)
	# Wounds, illness and the infection.
	var dh := body.tick(delta, ch)
	if dh < 0.0:
		death_cause = "Bled out" if body.bleeding() else "Died of a wound infection"
		take_damage(-dh, Vector3.ZERO, false)
	if body.infected and body.infection >= 1.0 and not dead:
		death_cause = "Turned into a zombie"
		turned = true
		take_damage(health + 1.0, Vector3.ZERO, false)
		return
	_update_symptoms(delta)
	if ch.has_trait("smoker") and craving() and not _crave_told:
		_crave_told = true
		GameState.notify("You're craving a cigarette")


## The infection makes you cough (zombies hear it) and saps your strength.
func _update_symptoms(delta: float) -> void:
	var sym := body.symptoms()
	if sym <= 0.0:
		return
	_cough_t -= delta
	if _cough_t <= 0.0:
		_cough_t = randf_range(18.0, 50.0) * (1.2 - sym)
		GameState.make_noise(global_position, 14.0 + sym * 10.0)
		_shake = maxf(_shake, 0.4 + sym * 0.5)
		GameState.notify("*cough*" if sym < 0.6 else "You cough up blood")


func max_stamina() -> float:
	return 100.0 * (1.0 - body.symptoms() * 0.45) * (1.0 - body.pain() * 0.25)


func craving() -> bool:
	return GameState.character.has_trait("smoker") and body.since_smoke > 6.0


## Hard landings sprain or break legs.
func _land(speed: float) -> void:
	if speed < 9.5 or dead:
		return
	var leg := "leg_l" if randf() < 0.5 else "leg_r"
	death_cause = "Fell to their death"
	take_damage((speed - 9.5) * 9.0, global_position)
	if speed > 14.0 and randf() < 0.7:
		body.add("fracture", leg)
		GameState.notify("You hear a crack. Your %s is broken." % ItemDB.PART_NAMES[leg].to_lower())
	elif speed > 11.0:
		body.add("sprain", leg)
		GameState.notify("You sprained your %s" % ItemDB.PART_NAMES[leg].to_lower())


func use_stamina(amount: float) -> void:
	var ch := GameState.character
	amount *= ch.mod("stamina") * (1.0 - ch.skill("fitness") * 0.04)
	stamina = maxf(0.0, stamina - amount)
	_stamina_delay = 1.0
	if stamina <= 0.0:
		_exhausted = true


## Zombies hear footsteps: sprinting is loud, sneaking almost silent.
func _update_noise(delta: float, moving: bool) -> void:
	_noise_t -= delta
	if moving and is_on_floor() and _noise_t <= 0.0:
		_noise_t = 0.5
		var ch := GameState.character
		var loud := ch.mod("noise") * (1.0 - ch.skill("stealth") * 0.05)
		GameState.make_noise(global_position, (16.0 if sprinting else (1.2 if crouching else 6.0)) * loud)


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
	return v * (1.0 - GameState.character.skill("stealth") * 0.04)


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
	if z == null or not z.alive() or weapons.aim_blend < 0.5:
		return
	if pad_look == Vector2.ZERO and velocity.length() < 0.5:
		return
	var to := z.global_position + Vector3(0, 1.35, 0) - camera.global_position
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	rotation.y = lerp_angle(rotation.y, want_yaw, minf(1.0, delta * 2.5))
	head.rotation.x = lerpf(head.rotation.x, want_pitch, minf(1.0, delta * 2.5))


# --- Interaction -------------------------------------------------------------

## Finds what the player is looking at: a door or window (raycast), a
## subdued turned player, a container or an item on the ground (nearest one
## in front, within reach).
func _update_focus() -> void:
	_focus = null
	prompt = ""
	prompt_action = "interact"
	hold_prompt = ""
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + fwd * REACH, 1 | 4 | WindowBody.SMASHED_LAYER, [get_rid()]))
	if not hit.is_empty():
		var c: Object = hit.collider
		if c is DoorBody:
			_focus = c
			prompt = c.prompt(global_position)
			hold_prompt = "lock" if c.can_lock(global_position) and not c.locked else ("unlock" if c.can_lock(global_position) else "")
			return
		if c is WindowBody:
			_focus = c
			if c.smashed:
				prompt = "Climb through window"
			elif weapons.current == "melee" or weapons.current == "":
				prompt = "Smash window"
				prompt_action = "attack"
			return
		if c is Zombie and c.subdued:
			_focus = c
			prompt = "Give the cure (%s)" % c.turned_name if GameState.item_count("cure_vial") > 0 else "%s needs a cure vial" % c.turned_name
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
	if _focus == null and vehicles:
		var near := vehicles.near(global_position, 1.3)
		if not near.is_empty():
			var e: Dictionary = near[0]
			var to: Vector3 = (e.pos as Vector3) - global_position
			to.y = 0.0
			if e.d < 0.2 or fwd.dot(to.normalized()) > 0.2:
				_focus = e.v if e.v else e.sp
				var t: String = e.v.rec.t if e.v else e.sp.t
				prompt = "%s" % VehicleDB.get_def(t).name
				return
	if _focus == null:
		if weapons.current == "melee" and crouching and _takedown_ready():
			prompt = "Silent takedown"
			prompt_action = "attack"
		return
	if _focus.has("pos"):
		if _focus.type == "generator":
			prompt = "Generator running" if GameState.has_power(_focus.site) else "Start generator"
			hold_prompt = "" if GameState.has_power(_focus.site) else "start"
			return
		if _focus.type == "fuel_pump" or _focus.type == "jet_pump":
			var left := VehicleMenu.pump_left(_focus)
			var can := _fuel_can(_focus.type)
			prompt = "%s (%d L left)" % [Loot.label(_focus.type), int(left)]
			if left > 0.0 and not can.is_empty():
				prompt = "Fill %s (%d L left in the pump)" % [ItemDB.item_name(can.id).to_lower(), int(left)]
			return
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


## Pings: tap to mark what you're looking at (a zombie, loot, or just a
## spot); hold to call for help where you stand.
func _update_ping(delta: float) -> void:
	if Input.is_action_just_pressed("ping"):
		_ping_t = 0.0
	elif _ping_t >= 0.0 and Input.is_action_pressed("ping"):
		_ping_t += delta
		if _ping_t > 0.45:
			_ping_t = -1.0
			Net.ping(global_position + Vector3(0, 1.8, 0), "help")
	elif _ping_t >= 0.0:
		_ping_t = -1.0
		var from := camera.global_position
		var hit := get_world_3d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * 150.0, 1 | 4, [get_rid()]))
		if hit.is_empty():
			return
		var pos: Vector3 = hit.position
		var kind := "go"
		if hit.collider is Zombie:
			kind = "zombie"
			pos = (hit.collider as Zombie).global_position + Vector3(0, 1.8, 0)
		elif (drops and not drops.near(pos, 2.0).is_empty()) or (streamer and not streamer.containers_near(pos, 2.0).is_empty()):
			kind = "loot"
		Net.ping(pos, kind)


## Tap interact to use things; hold it to lock or unlock a door or to start
## a generator.
func _update_interact(delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		_hold_t = 0.0
		_hold_done = hold_prompt == ""
		if _hold_done:
			_interact()
	elif Input.is_action_pressed("interact") and not _hold_done:
		_hold_t += delta
		if _hold_t >= _hold_needed():
			_hold_done = true
			_interact_hold()
	elif not Input.is_action_pressed("interact") and not _hold_done:
		_hold_done = true
		_interact()
	if not Input.is_action_pressed("interact"):
		_hold_t = 0.0


func _hold_needed() -> float:
	return 2.5 if hold_prompt == "start" else 0.5


## 0..1 while interact is held on something holdable (for the HUD ring).
func hold_progress() -> float:
	if _hold_done or hold_prompt == "" or _hold_t < 0.12:
		return 0.0
	return clampf(_hold_t / _hold_needed(), 0.0, 1.0)


func _interact() -> void:
	if _focus == null:
		return
	if _focus is Vehicle:
		vehicle_menu.open(_focus)
	elif _focus is Dictionary and _focus.has("xf"):
		vehicle_menu.open(vehicles.activate(_focus))
	elif _focus is DoorBody:
		_focus.interact(global_position)
	elif _focus is WindowBody:
		if _focus.smashed:
			_start_climb(_focus)
	elif _focus is Zombie:
		if GameState.item_count("cure_vial") > 0:
			GameState.inventory.take("cure_vial", 1)
			_focus.cure()
			GameState.notify("You inject the cure. %s is coming back..." % _focus.turned_name)
	elif _focus.has("pos"):
		if _focus.type == "generator":
			if not GameState.has_power(_focus.site):
				GameState.notify("Hold to start the generator (it's loud)")
			return
		if _focus.type == "fuel_pump" or _focus.type == "jet_pump":
			_fill_can(_focus)
			return
		GameState.container_items(_focus)
		GameState.make_noise(global_position, 2.0)
		open_inventory.emit(_focus)
	else:
		pick_up(_focus)
	_prompt_t = 0.0


func _interact_hold() -> void:
	if _focus is DoorBody:
		_focus.toggle_lock(global_position)
	elif _focus is Dictionary and _focus.has("pos") and _focus.type == "generator":
		GameState.set_power(_focus.site, _focus.pos)
		GameState.make_noise(_focus.pos, 120.0)
		GameState.notify("The generator roars to life. Power is on - and every zombie heard it.")
	_prompt_t = 0.0


## Climbing through a smashed window takes a moment and leaves you exposed.
func _start_climb(w: WindowBody) -> void:
	var n := w.global_basis.z
	var side := 1.0 if (global_position - w.global_position).dot(n) < 0.0 else -1.0
	_climb_from = global_position
	_climb_to = w.global_position + n * side * 0.75
	# Land on whatever floor is on the far side.
	var down := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			_climb_to + Vector3(0, 0.5, 0), _climb_to - Vector3(0, 4.0, 0), 1, [get_rid()]))
	_climb_to.y = (down.position.y if not down.is_empty() else global_position.y) + 0.05
	_climb_t = 1.0
	crouching = false
	collision_mask = 0
	velocity = Vector3.ZERO
	GameState.make_noise(global_position, 6.0)


func _update_climb(delta: float) -> void:
	_climb_t -= delta
	var t := 1.0 - maxf(_climb_t, 0.0)
	var p := _climb_from.lerp(_climb_to, t)
	p.y = lerpf(_climb_from.y, _climb_to.y, t) + sin(t * PI) * 0.9
	global_position = p
	if _climb_t <= 0.0:
		_climb_t = 0.0
		collision_mask = 1 | 4
	_update_camera(delta, false)


func pick_up(drop: Dictionary) -> void:
	# A guest asks the host, in case someone else just grabbed it.
	if Net.is_client():
		Net.request_pickup(str(drop.get("id", "")))
		return
	var it: Dictionary = (drop.it as Dictionary).duplicate(true)
	GameState.remove_drop(drop)
	GameState.add_item(it, DropManager._pos(drop))


# --- Items -------------------------------------------------------------------

## Eats, drinks, smokes or applies an item from the inventory. Returns
## true if it was used.
func consume(it: Dictionary) -> bool:
	if dead or not ItemDB.is_consumable(it.id):
		return false
	var d := ItemDB.get_def(it.id)
	if it.id == "cigarettes":
		body.since_smoke = 0.0
		_crave_told = false
		stamina = minf(max_stamina(), stamina + 10.0)
		it.u = int(it.get("u", 1)) - 1
		if int(it.u) <= 0:
			GameState.inventory.detach(it)
		GameState.inventory.notify()
		GameState.notify("You smoke a cigarette")
		return true
	var msg := ""
	if d.get("cat", "") == "medical":
		msg = body.treat(it.id)
		if msg == "" and (health >= 99.0 or float(d.get("health", 0.0)) <= 0.0):
			GameState.notify("You don't need %s right now" % ItemDB.item_name(it.id))
			return false
	hunger = clampf(hunger + float(d.get("hunger", 0.0)), 0.0, 100.0)
	thirst = clampf(thirst + float(d.get("thirst", 0.0)), 0.0, 100.0)
	health = minf(100.0, health + float(d.get("health", 0.0)))
	stamina = minf(max_stamina(), stamina + float(d.get("stamina", 0.0)))
	it.n = int(it.get("n", 1)) - 1
	if int(it.n) <= 0:
		GameState.inventory.detach(it)
	GameState.inventory.notify()
	GameState.notify(msg if msg != "" else "Used %s" % ItemDB.item_name(it.id))
	if it.id == "water_bottle":
		# Keep the empty bottle: it's a throwable distraction.
		GameState.add_item(ItemDB.make("glass_bottle"), global_position)
	return true


## Uses the first carried item in one of the categories (`first`, then
## `fallback`). Bound to the quick-use buttons. Quick heal picks the
## treatment for your most urgent problem (stitches before bandages, etc.).
func quick_use(first: Array, fallback: Array) -> void:
	if "medical" in first:
		for need in body.needs():
			var it := _find_treatment(need)
			if not it.is_empty() and consume(it):
				return
		if health < 99.0:
			for g in GameState.inventory.grids():
				for it in g.items:
					var d := ItemDB.get_def(it.id)
					if d.get("cat", "") == "medical" and float(d.get("health", 0.0)) > 0.0 and it.id != "cure_vial":
						consume(it)
						return
		GameState.notify("Nothing to treat" if body.needs().is_empty() and health >= 99.0 else "No medical supplies for that")
		return
	for cats in [first, fallback]:
		for g in GameState.inventory.grids():
			for it in g.items:
				if ItemDB.get_def(it.id).get("cat", "") in cats:
					consume(it)
					return
	GameState.notify("Nothing to eat or drink")


## The carried item that best treats a need (cheapest first: bandages
## before first aid kits).
func _find_treatment(need: String) -> Dictionary:
	var order := {"bleed": ["bandage", "rag", "first_aid_kit"], "deep": ["suture_kit", "first_aid_kit"],
		"fracture": ["splint"], "wound_infection": ["alcohol_wipes", "antibiotics", "first_aid_kit"],
		"infection": ["cure_vial", "antibiotics"], "pain": ["painkillers"]}
	for id: String in order.get(need, []):
		if need == "infection" and id == "antibiotics" and body.antibiotics > 0.0:
			continue
		var it := GameState.inventory.find(id)
		if not it.is_empty():
			return it
	return {}


## A zombie's attack lands. Clothing on the body part it hits may stop it
## breaking the skin; otherwise it leaves a wound, and a bite can infect.
## `kind`: "claw" (most attacks), "bite", "heavy" (brutes) or "ankle"
## (crawlers grabbing your legs).
func zombie_hit(dmg: float, from: Vector3, kind := "claw") -> void:
	if dead:
		return
	# Inside a closed vehicle the zombies pound on it instead of you.
	if vehicle and vehicle.def.closed and float(vehicle.rec.hp) > 0.0:
		vehicle.zombie_bang(dmg)
		_bang_t -= 1.0
		if _bang_t <= 0.0:
			_bang_t = 6.0
			GameState.notify("Zombies are pounding on the %s!" % str(vehicle.def.name).to_lower())
		return
	var ch := GameState.character
	var parts := ["arm_l", "arm_r", "torso", "torso", "arm_l", "arm_r", "head", "leg_l", "leg_r"]
	var part: String = ("leg_l" if randf() < 0.5 else "leg_r") if kind == "ankle" else parts[randi() % parts.size()]
	var bite := kind == "bite" or kind == "ankle" or randf() < 0.35
	var guard := GameState.inventory.protection(part, "bite" if bite else "scratch", kind == "ankle")
	GameState.inventory.tear(part, randf_range(0.03, 0.08))
	var where: String = str(ItemDB.PART_NAMES[part]).to_lower()
	# Thick skin (mod below 1) sometimes holds even when the clothes don't.
	if randf() < guard or randf() > ch.mod("skin"):
		# Bruised, but the skin held.
		take_damage(dmg * 0.35, from)
		GameState.notify("Your clothes stopped the %s on your %s" % ["bite" if bite else "scratch", where])
		return
	death_cause = "Killed by zombies"
	take_damage(dmg, from)
	if kind == "heavy" and randf() < 0.25:
		body.add("fracture", part if part != "head" and part != "torso" else "arm_l")
		GameState.notify("The blow breaks a bone!")
		return
	var dirty := randf() < float(Health.KINDS["bite" if bite else "scratch"].dirty)
	if bite:
		body.add("bite", part, dirty)
		GameState.notify("You've been bitten on the %s!" % where)
		if randf() < GameState.infection_chance():
			body.infect(randf())
	else:
		var deep := kind == "heavy" or randf() < 0.12
		body.add("deep_wound" if deep else ("laceration" if randf() < 0.4 else "scratch"), part, dirty)
		GameState.notify("%s on your %s" % ["Deep wound" if deep else "Scratched", where])


## Fire and explosions leave burns and wounds as well as damage.
func hurt(amount: float, from: Vector3, kind: String) -> void:
	if dead:
		return
	match kind:
		"fire":
			death_cause = "Burned to death"
			if not body.has("burn") or randf() < 0.1:
				var part: String = ["arm_l", "arm_r", "leg_l", "leg_r", "torso"][randi() % 5]
				body.add("burn", part)
		"blast":
			death_cause = "Blown up"
			if amount > 25.0:
				body.add("deep_wound" if amount > 50.0 else "laceration", ["arm_l", "arm_r", "leg_l", "leg_r", "torso"][randi() % 5], false)
	take_damage(amount, from)


## A crawler has you by the ankle: you can barely move.
func grab(time: float, msg := "Something grabs your ankle!") -> void:
	if vehicle:
		return
	_grab_t = maxf(_grab_t, time)
	if msg != "":
		GameState.notify(msg)


func take_damage(amount: float, _from: Vector3, feedback := true) -> void:
	if dead:
		return
	health -= amount
	if feedback:
		_shake = 1.0
		damaged.emit()
	if health <= 0.0:
		health = 0.0
		if vehicle:
			exit_vehicle(true)
		dead = true
		crouching = false
		flashlight.visible = false
		if death_cause == "":
			death_cause = "Killed by zombies"
		# An infected survivor rises again, whatever killed them.
		if body.infected:
			turned = true
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
	turned = false
	death_cause = ""
	body.clear()
	crouching = false
	_exhausted = false
	_grab_t = 0.0
	_climb_t = 0.0
	collision_mask = 1 | 4
	_last_bob = 0.0
	head.rotation = Vector3.ZERO
	head.position.y = EYE_HEIGHT
	weapons.select("melee")


func to_dict() -> Dictionary:
	# Saved inside a vehicle: you'll be standing next to it.
	var at := vehicle.exit_point(seat) if vehicle else global_position
	return {
		"pos": [at.x, at.y, at.z],
		"yaw": rotation.y,
		"health": health, "hunger": hunger, "thirst": thirst, "stamina": stamina,
		"weapon": weapons.current, "body": body.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		global_position = Vector3(p[0], p[1] + 0.5, p[2])
	rotation.y = float(d.get("yaw", 0.0))
	health = maxf(1.0, float(d.get("health", 100.0)))
	hunger = float(d.get("hunger", 100.0))
	thirst = float(d.get("thirst", 100.0))
	stamina = float(d.get("stamina", 100.0))
	body.from_dict(d.get("body", {}))
	weapons.select(str(d.get("weapon", "melee")))


# --- Vehicles ---------------------------------------------------------------------------

## Gets in (seat 0 drives; -1 takes any free passenger seat).
func enter_vehicle(v: Vehicle, want: int) -> void:
	var s := want
	if s < 0:
		for i in range(1, int(v.def.seats)):
			if not v.seats.has(i):
				s = i
				break
	if s < 0 or v.seats.has(s):
		GameState.notify("No free seat")
		return
	vehicle = v
	seat = s
	v.seats[s] = self
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	crouching = false
	sprinting = false
	flashlight.visible = false
	weapons.visible = false
	_cam_yaw = 0.0
	_cam_pitch = -0.25
	camera.top_level = true
	_update_chase_camera(1.0)
	if s == 0:
		v.remote = false
		var why := v.start_engine()
		if why != "":
			GameState.notify(why)
		elif v.def.fuel != "":
			GameState.notify("The engine starts" if v.kind != "heli" and v.kind != "plane" else "The engine whines up to speed")
	Net.vehicle_seat(v.rec.id, s, true)


## Gets out beside the vehicle. `forced` (dying, the vehicle going away)
## skips the checks.
func exit_vehicle(forced := false) -> void:
	if vehicle == null:
		return
	var v := vehicle
	if not forced and v.airborne:
		GameState.notify("Not up here!")
		return
	if not forced and absf(v.speed) > 6.0:
		GameState.notify("Slow down first")
		return
	var at := v.exit_point(seat) if is_instance_valid(v) else global_position
	v.seats.erase(seat)
	if seat == 0:
		v.ctl_move = Vector2.ZERO
		v.ctl_up = 0.0
		if v.kind != "plane" or not v.airborne:
			v.stop_engine()
	Net.vehicle_seat(v.rec.id, seat, false)
	Net.vehicle_record(v.rec)
	vehicle = null
	seat = -1
	camera.top_level = false
	camera.transform = Transform3D.IDENTITY
	collision_layer = 2
	collision_mask = 1 | 4
	global_position = at
	rotation.y = v.rotation.y + PI + _cam_yaw
	head.rotation.x = 0.0
	weapons.visible = true


func _in_vehicle(delta: float) -> void:
	var v := vehicle
	if not is_instance_valid(v):
		vehicle = null
		camera.top_level = false
		camera.transform = Transform3D.IDENTITY
		collision_layer = 2
		collision_mask = 1 | 4
		weapons.visible = true
		return
	var can_act := not GameState.ui_open
	if touch and can_act:
		_look(touch.consume_look() * TOUCH_SENS)
	var pad_look := Input.get_vector("look_left", "look_right", "look_up", "look_down") if can_act else Vector2.ZERO
	if pad_look != Vector2.ZERO:
		_look(pad_look * PAD_SENS * delta)
	velocity = Vector3.ZERO
	global_position = v.seat_pos(seat) - Vector3(0, 0.6, 0)
	if seat == 0:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if can_act else Vector2.ZERO
		if touch and can_act:
			input += touch.move_vector
		input = input.limit_length(1.0)
		v.ctl_move = Vector2(input.x, -input.y)
		var up := 0.0
		if can_act and Input.is_action_pressed("jump"):
			up += 1.0
		if can_act and Input.is_action_pressed("crouch"):
			up -= 1.0
		v.ctl_up = up
		if can_act and Input.is_action_just_pressed("reload") and not v.running:
			var why := v.start_engine()
			GameState.notify(why if why != "" else "The engine starts")
	_cam_idle += delta
	_update_chase_camera(delta)
	_update_stats(delta, false)
	if not can_act:
		return
	prompt = "Get out"
	prompt_action = "interact"
	hold_prompt = ""
	_focus = null
	if Input.is_action_just_pressed("interact"):
		exit_vehicle()
		return
	if Input.is_action_just_pressed("flashlight") and seat == 0:
		v.set_lights(not v.lights_on)
	if Input.is_action_just_pressed("attack") and seat == 0:
		v.honk()
	if Input.is_action_just_pressed("inventory"):
		open_inventory.emit({})
	if Input.is_action_just_pressed("quick_eat"):
		quick_use(["drink"] if thirst < hunger else ["food"], ["food", "drink"])
	if Input.is_action_just_pressed("quick_heal"):
		quick_use(["medical"], [])
	_update_ping(delta)


## Third-person camera behind the vehicle; look input orbits it, and it
## swings back behind after a moment of driving.
func _update_chase_camera(delta: float) -> void:
	var v := vehicle
	if _cam_idle > 1.5 and absf(v.speed) > 3.0:
		_cam_yaw = lerp_angle(_cam_yaw, 0.0, minf(1.0, delta * 2.0))
	var dist: float = v.def.cam
	var pivot := v.global_position + Vector3(0, float(v.def.size.y) * 0.9 + 0.6, 0)
	var yaw := v.rotation.y + _cam_yaw
	var dir := Vector3(sin(yaw) * cos(_cam_pitch), sin(_cam_pitch), cos(yaw) * cos(_cam_pitch))
	var want := pivot - dir * dist
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pivot, want, 1, [v.get_rid()]))
	if not hit.is_empty():
		want = (hit.position as Vector3) + dir * 0.3
	if gen:
		want.y = maxf(want.y, gen.height(want.x, want.z) + 0.5)
	camera.global_position = want if delta >= 1.0 else camera.global_position.lerp(want, minf(1.0, delta * 10.0))
	if camera.global_position.distance_squared_to(pivot) > 0.01:
		camera.look_at(pivot + dir * 2.0)


func _fuel_can(pump_type: String) -> Dictionary:
	var fuel := "jet" if pump_type == "jet_pump" else "gas"
	var best := {}
	for g in GameState.inventory.grids():
		for it in g.items:
			var d := ItemDB.get_def(it.id)
			if d.get("fuel", "") == fuel and int(it.get("u", 0)) < int(d.uses):
				if best.is_empty() or int(it.get("u", 0)) < int(best.get("u", 0)):
					best = it
	return best


func _fill_can(ct: Dictionary) -> void:
	var can := _fuel_can(ct.type)
	if can.is_empty():
		GameState.notify("You need an empty %s" % ("jet fuel can" if ct.type == "jet_pump" else "gas can"))
		return
	var room := float(ItemDB.get_def(can.id).uses) - float(can.get("u", 0))
	var got := VehicleMenu.take_from_pump(ct, room)
	if got <= 0.0:
		GameState.notify("The pump is dry")
		return
	can.u = int(can.get("u", 0)) + int(got)
	GameState.inventory.notify()
	GameState.make_noise(global_position, 5.0)
	GameState.notify("Filled the can (%d L)" % int(got))
