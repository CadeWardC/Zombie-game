class_name Vehicle
extends CharacterBody3D
## A vehicle in the world: bicycle, motorbike, car or truck, boat,
## helicopter or plane. Its state lives in a record in GameState.ws.vehicles
## (fuel, engine, battery, tires, keys...), so it's saved and shared; this
## node drives it.
##
## Handling is arcade and forgiving: ground vehicles roll along the terrain
## (kinematic, tilted to the slope), boats glide on the water and stop at the
## shore, helicopters hover and climb, planes need a run-up to take off and a
## gentle touch-down to land. Engines burn fuel and are loud; hitting zombies
## hurts them and the vehicle; hard crashes hurt the people inside.
##
## Vehicle space: +Z is the front (like CarModels).

signal crashed(impact: float)

const GRAVITY := 14.0

var rec: Dictionary
var def: Dictionary
var kind := "ground"
var size := Vector3.ONE
## Seated players: seat index -> Player (local) or peer id (others).
var seats := {}
var running := false
var speed := 0.0 # Along the vehicle's forward axis (m/s, negative reversing).
var vy := 0.0
var throttle := 0.0 # Planes: lever position 0..1.
var airborne := false
var pitch := 0.0
var bank := 0.0
## Controls for this frame (set by the driver): move (x steer, y forward),
## up (+1 / -1: climb / descend, throttle up / down; brake on the ground).
var ctl_move := Vector2.ZERO
var ctl_up := 0.0
var gen: WorldGen
var zombies: ZombieManager
var remote := false # Multiplayer: someone else drives it; follow their updates.
var lights_on := false

var _model: Node3D
var _mesh: MeshInstance3D
var _spinner: MeshInstance3D # Rotor or propeller.
var _spin := 0.0
var _lights: Array[SpotLight3D] = []
var _noise_t := 0.0
var _alarm_t := 0.0
var _hit_cd := {} # Zombie -> time until it can be hit again.
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0


func setup(r: Dictionary) -> void:
	rec = r
	def = VehicleDB.get_def(r.t)
	kind = def.kind
	collision_layer = 1
	collision_mask = 1
	floor_max_angle = deg_to_rad(40.0)
	floor_snap_length = 0.6
	safe_margin = 0.04
	size = def.size
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Planes collide by the fuselage; the wings would snag on everything.
	box.size = Vector3(1.6, 1.6, size.z) if kind == "plane" else Vector3(size.x, size.y * 0.7, size.z)
	cs.shape = box
	# The box rides a little above the ground (clearance for kerbs and
	# bumps); the model is lifted by the same amount so its wheels touch.
	var clear := 0.6 if kind == "plane" else (0.0 if kind == "water" else 0.25)
	cs.position.y = box.size.y * 0.5 + clear
	add_child(cs)
	_model = Node3D.new()
	_model.position.y = clear
	add_child(_model)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = Assets.cars[int(r.m) % Assets.cars.size()] if int(r.m) >= 0 else Assets.vehicle_meshes.get(r.t)
	_model.add_child(_mesh)
	if r.t == "helicopter":
		_spinner = MeshInstance3D.new()
		_spinner.mesh = Assets.vehicle_meshes.rotor
		_spinner.position = Vector3(0, 2.72, 0.3)
		_model.add_child(_spinner)
	elif r.t == "prop_plane":
		_spinner = MeshInstance3D.new()
		_spinner.mesh = Assets.vehicle_meshes.propeller
		_spinner.position = Vector3(0, 1.0, 4.15)
		_model.add_child(_spinner)
	if def.fuel != "" or r.t == "bicycle":
		for x: float in ([0.0] if size.x < 1.0 else [-size.x * 0.3, size.x * 0.3]):
			var l := SpotLight3D.new()
			l.spot_range = 40.0
			l.spot_angle = 32.0
			l.light_energy = 2.0
			l.light_color = Color(1.0, 0.95, 0.8)
			l.position = Vector3(x, 0.8, size.z * 0.5)
			l.rotation_degrees = Vector3(-8, 180, 0) # Lights look along -Z; the front is +Z.
			l.visible = false
			_model.add_child(l)
			_lights.append(l)
	var p: Array = r.p
	position = Vector3(p[0], p[1], p[2])
	rotation.y = float(r.yaw)
	_net_pos = position
	_net_yaw = rotation.y
	airborne = kind in ["heli", "plane"] and bool(r.get("air", false))


func forward() -> Vector3:
	return global_basis.z


func driver() -> Variant:
	return seats.get(0)


func occupied() -> bool:
	return not seats.is_empty()


## World position of a seat (where its occupant sits).
func seat_pos(i: int) -> Vector3:
	var off := Vector3.ZERO
	match kind:
		"ground":
			if size.x < 1.0:
				off = Vector3(0, 0.85, -0.2 - i * 0.5)
			else:
				off = Vector3(0.45 if i % 2 == 0 else -0.45, 0.45, 0.3 - int(i / 2) * 1.1)
		"water":
			off = Vector3(0.35 if i % 2 == 0 else -0.35, 0.25, -0.9 + int(i / 2) * 1.0)
		"heli":
			off = Vector3(0.45 if i % 2 == 0 else -0.45, 1.0, 1.4 - int(i / 2) * 1.2)
		"plane":
			off = Vector3(0.3 if i % 2 == 0 else -0.3, 1.25, 1.2)
	return global_transform * (off + _model.position)


func free_seat() -> int:
	for i in int(def.seats):
		if not seats.has(i):
			return i
	return -1


## Where to step out: beside the driver's door, or wherever there's room.
func exit_point(i: int) -> Vector3:
	var space := get_world_3d().direct_space_state
	var w: float = size.x * 0.5 + 0.9
	for off: Vector3 in [Vector3(w if i % 2 == 0 else -w, 0, 0), Vector3(-w if i % 2 == 0 else w, 0, 0),
			Vector3(0, 0, -size.z * 0.5 - 1.0), Vector3(0, 0, size.z * 0.5 + 1.0)]:
		var p := global_transform * off + Vector3(0, 1.2, 0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.0, 0), p - Vector3(0, 6.0, 0), 1, [get_rid()]))
		if not hit.is_empty():
			var free := space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), hit.position + Vector3(0, 1.0, 0), 1, [get_rid()]))
			if free.is_empty():
				return hit.position + Vector3(0, 0.1, 0)
	return global_position + Vector3(0, size.y + 0.3, 0)


func set_lights(on: bool) -> void:
	lights_on = on
	for l in _lights:
		l.visible = on and (running or def.fuel == "")


## Tries to start the engine. Returns "" or why it won't start.
func start_engine() -> String:
	if def.fuel == "":
		running = true
		return ""
	var why := VehicleDB.cant_start(rec)
	if why != "":
		return why
	running = true
	rec.bat = maxf(0.0, float(rec.bat) - 0.02)
	GameState.make_noise(global_position, float(def.noise) * 0.8)
	return ""


func stop_engine() -> void:
	running = false
	set_lights(lights_on)


func sound_alarm(time := 20.0) -> void:
	_alarm_t = time
	GameState.notify("The car alarm goes off!")


## A zombie beating on it with someone inside.
func zombie_bang(dmg: float) -> void:
	_damage(dmg * 0.4)
	if float(rec.hp) <= 0.0:
		GameState.notify("They're breaking in!")


func honk() -> void:
	if def.fuel != "" and kind == "ground":
		GameState.make_noise(global_position, 60.0)


# --- Simulation -------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if remote:
		var k := 1.0 - exp(-dt * 12.0)
		global_position = global_position.lerp(_net_pos, k) if global_position.distance_to(_net_pos) < 10.0 else _net_pos
		rotation.y = lerp_angle(rotation.y, _net_yaw, k)
		_model.rotation.x = lerp_angle(_model.rotation.x, -pitch, k)
		_model.rotation.z = lerp_angle(_model.rotation.z, bank, k)
		_animate(dt)
		return
	if float(rec.hp) <= 0.0:
		running = false
	match kind:
		"ground":
			_ground(dt)
		"water":
			_water(dt)
		"heli":
			_heli(dt)
		"plane":
			_plane(dt)
	_use_fuel(dt)
	if airborne and running and driver() is Player:
		GameState.practice("piloting", dt * 0.4)
	_hit_zombies(dt)
	_alarm(dt)
	_animate(dt)
	rec.p = [global_position.x, global_position.y, global_position.z]
	rec.yaw = rotation.y
	rec.air = airborne


func _top_speed() -> float:
	var s: float = def.speed
	s *= 1.0 - 0.18 * int(rec.flat)
	if def.fuel != "":
		s *= lerpf(0.55, 1.0, clampf(float(rec.eng), 0.0, 1.0))
	return s


func _drive_input() -> float:
	if not running:
		return 0.0
	var t := ctl_move.y
	# Pedal and row power comes from the rider.
	if def.fuel == "" and driver() is Player:
		var p: Player = driver()
		if absf(t) > 0.05:
			p.use_stamina(5.0 * absf(t) * get_physics_process_delta_time())
		if p.stamina < 5.0:
			t *= 0.3
	return t


func _ground(dt: float) -> void:
	var t := _drive_input()
	var top := _top_speed()
	var target := top * t if t >= 0.0 else top * 0.3 * t
	var rate: float = def.accel
	if absf(speed) > 0.5 and signf(target) != signf(speed) and target != 0.0:
		rate = 14.0 # Braking.
	elif absf(target) < 0.01:
		rate = 3.0 # Coasting.
	if ctl_up > 0.5:
		target = 0.0
		rate = 16.0 # Handbrake.
	speed = move_toward(speed, target, rate * dt)
	# Steering: sharper at low speed, gentler when fast.
	var steer := ctl_move.x * float(def.steer)
	if int(rec.flat) > 0:
		steer += 0.08 * int(rec.flat) * signf(speed) # A flat pulls to one side.
	var turn := steer * 1.7 * clampf(absf(speed) / 5.0, 0.0, 1.0) / (1.0 + absf(speed) * 0.035)
	rotation.y -= turn * signf(speed) * dt
	velocity = forward() * speed
	velocity.y = -2.0 if is_on_floor() else vy
	vy = 0.0 if is_on_floor() else vy - GRAVITY * dt
	var before := speed
	move_and_slide()
	_check_crash(before)
	# Driving into deep water floods the engine.
	var wl := gen.water_level(global_position.x, global_position.z) if gen else -INF
	if wl > global_position.y + 0.7 and def.fuel != "":
		if running:
			GameState.notify("Water floods the engine!")
			rec.eng = maxf(0.0, float(rec.eng) - 0.3)
		running = false
		speed *= 0.9
	# Tilt the body to the slope (and lean bikes into turns).
	var target_pitch := 0.0
	var target_roll := 0.0
	if gen:
		var half: float = size.z * 0.4
		var f := global_position + forward() * half
		var b := global_position - forward() * half
		target_pitch = atan2(gen.height(f.x, f.z) - gen.height(b.x, b.z), half * 2.0)
		var side := global_basis.x * size.x * 0.4
		var l := global_position + side
		var r := global_position - side
		target_roll = atan2(gen.height(l.x, l.z) - gen.height(r.x, r.z), size.x * 0.8) * 0.5
	if size.x < 1.0:
		target_roll = ctl_move.x * clampf(absf(speed) / 8.0, 0.0, 1.0) * 0.35
	pitch = lerpf(pitch, clampf(target_pitch, -0.5, 0.5), minf(1.0, dt * 8.0))
	bank = lerpf(bank, target_roll, minf(1.0, dt * 8.0))
	_model.rotation = Vector3(-pitch, 0.0, bank)


func _water(dt: float) -> void:
	var t := _drive_input()
	var top := _top_speed()
	var target := top * t if t >= 0.0 else top * 0.4 * t
	speed = move_toward(speed, target, float(def.accel) * (1.0 if absf(target) > 0.01 else 0.5) * dt)
	rotation.y -= ctl_move.x * float(def.steer) * clampf(absf(speed) / 2.0 + 0.3, 0.0, 1.2) * signf(speed if absf(speed) > 0.1 else 1.0) * dt
	var next := global_position + forward() * speed * dt
	var wl := gen.water_level(next.x, next.z) if gen else -INF
	if wl == -INF or wl - gen.height(next.x, next.z) < 0.4:
		# Ran aground at the shore.
		if absf(speed) > 4.0:
			_damage(absf(speed) * 2.0)
		speed = 0.0
		wl = gen.water_level(global_position.x, global_position.z) if gen else global_position.y
		if wl == -INF:
			wl = global_position.y
	else:
		global_position = next
	var bob := sin(Time.get_ticks_msec() / 600.0) * 0.04
	global_position.y = wl - 0.05 + bob
	pitch = lerpf(pitch, speed * 0.008, minf(1.0, dt * 3.0))
	bank = lerpf(bank, ctl_move.x * absf(speed) * 0.01, minf(1.0, dt * 3.0))
	_model.rotation = Vector3(-pitch, 0.0, bank)


func _heli(dt: float) -> void:
	var lift := ctl_up if running else 0.0
	var target_vy := lift * 7.0
	if not running and airborne:
		target_vy = -11.0 # Autorotating down.
	elif not running:
		target_vy = -2.0
	vy = move_toward(vy, target_vy, 6.0 * dt)
	var fwd := ctl_move.y * float(def.speed) if running and airborne else 0.0
	speed = move_toward(speed, fwd, float(def.accel) * dt)
	if running and airborne:
		rotation.y -= ctl_move.x * 1.1 * dt
	velocity = forward() * speed + Vector3(0, vy, 0)
	var was_air := airborne
	var impact := velocity.length()
	move_and_slide()
	if is_on_floor():
		if was_air and (vy < -8.0 or absf(speed) > 15.0):
			_crash(impact)
		airborne = false
		vy = maxf(vy, 0.0) if lift > 0.1 else 0.0
		speed = move_toward(speed, 0.0, 10.0 * dt)
		if lift > 0.1:
			airborne = true
	else:
		airborne = global_position.y > (gen.height(global_position.x, global_position.z) if gen else 0.0) + 0.6
		if get_slide_collision_count() > 0 and impact > 14.0:
			_crash(impact)
	pitch = lerpf(pitch, -speed * 0.006, minf(1.0, dt * 3.0))
	bank = lerpf(bank, ctl_move.x * 0.25 if airborne else 0.0, minf(1.0, dt * 3.0))
	_model.rotation = Vector3(-pitch, 0.0, bank)


func _plane(dt: float) -> void:
	if running:
		throttle = clampf(throttle + ctl_up * 0.5 * dt, 0.0, 1.0)
	else:
		throttle = 0.0
	var top: float = def.speed
	var takeoff: float = def.takeoff
	speed = move_toward(speed, throttle * top, (float(def.accel) if running else 4.0) * dt)
	var nose_up := -ctl_move.y # Pull back to climb.
	if not airborne:
		rotation.y -= ctl_move.x * 0.8 * clampf(absf(speed) / 8.0, 0.0, 1.0) * dt
		pitch = lerpf(pitch, 0.0, minf(1.0, dt * 4.0))
		bank = lerpf(bank, 0.0, minf(1.0, dt * 4.0))
		if speed > takeoff and nose_up > 0.3:
			airborne = true
			pitch = 0.12
			GameState.notify("Airborne!")
		velocity = forward() * speed
		velocity.y = -2.0 if is_on_floor() else vy
		vy = 0.0 if is_on_floor() else vy - GRAVITY * dt
		var before := speed
		move_and_slide()
		_check_crash(before)
	else:
		pitch = move_toward(pitch, nose_up * 0.35, dt * 0.6)
		bank = move_toward(bank, ctl_move.x * 0.6, dt * 0.9)
		rotation.y -= bank * 0.6 * dt
		# Too slow: it stalls and the nose drops.
		if speed < takeoff * 0.8:
			pitch = move_toward(pitch, -0.4, dt * 0.5)
		var impact := speed
		velocity = forward() * cos(pitch) * speed + Vector3(0, sin(pitch) * speed, 0)
		move_and_slide()
		if is_on_floor():
			var sink := sin(pitch) * speed
			# Practised pilots get away with firmer landings.
			var skill := GameState.character.skill("piloting") if driver() is Player else 0
			if sink < -5.0 - skill * 0.5 or absf(bank) > 0.35 + skill * 0.03 or speed > top * 0.9:
				_crash(impact)
			else:
				airborne = false
				pitch = 0.0
				GameState.notify("Touchdown")
		elif get_slide_collision_count() > 0:
			_crash(impact)
	_model.rotation = Vector3(-pitch, 0.0, -bank)


## A wall or tree: lose speed, take damage; hard enough and it hurts.
func _check_crash(before: float) -> void:
	if get_slide_collision_count() == 0 or absf(before) < 4.0:
		return
	var worst := 0.0
	for k in get_slide_collision_count():
		var c := get_slide_collision(k)
		var n := c.get_normal()
		if absf(n.y) > 0.6:
			continue # Ground.
		worst = maxf(worst, absf(before) * absf(n.dot(forward())))
	if worst < 5.0:
		return
	speed = -signf(before) * minf(absf(before) * 0.2, 2.0)
	_damage(worst * worst * 0.6)
	crashed.emit(worst)
	if worst > 12.0:
		for s in seats.values():
			if s is Player:
				(s as Player).death_cause = "Died in a crash"
				(s as Player).take_damage((worst - 12.0) * 5.0, global_position)
		GameState.notify("Crash!")
	GameState.make_noise(global_position, 25.0 + worst * 2.0)


## A helicopter or plane coming down too hard: destroyed, and anyone inside
## is badly hurt.
func _crash(impact: float) -> void:
	rec.hp = 0.0
	running = false
	airborne = false
	speed = 0.0
	vy = 0.0
	if Effects.current:
		Effects.current.burst(global_position + Vector3(0, 1.0, 0), Vector3.UP, Color(1.0, 0.55, 0.2), 30, 8.0)
		Effects.current.burst(global_position + Vector3(0, 1.0, 0), Vector3.UP, Color(0.2, 0.2, 0.2), 30, 5.0)
	GameState.make_noise(global_position, 150.0)
	GameState.notify("CRASH!")
	for s in seats.values():
		if s is Player:
			(s as Player).death_cause = "Died in a crash"
			(s as Player).take_damage(40.0 + impact * 2.0, global_position)
	crashed.emit(impact)


func _damage(amount: float) -> void:
	rec.hp = maxf(0.0, float(rec.hp) - amount)
	if def.fuel != "":
		rec.eng = maxf(0.0, float(rec.eng) - amount / float(def.hp) * 0.5)
	if float(rec.hp) <= 0.0:
		running = false
		GameState.notify("The %s is wrecked" % str(def.name).to_lower())


func _use_fuel(dt: float) -> void:
	if not running or def.fuel == "":
		return
	var load := absf(ctl_move.y)
	if kind == "plane":
		load = throttle
	elif kind == "heli":
		load = maxf(absf(ctl_move.y), absf(ctl_up))
	rec.fuel = maxf(0.0, float(rec.fuel) - float(def.use) * (0.25 + 0.75 * load) * dt)
	rec.bat = minf(1.0, float(rec.bat) + 0.01 * dt)
	if float(rec.fuel) <= 0.0:
		running = false
		GameState.notify("Out of fuel!")
	_noise_t -= dt
	if _noise_t <= 0.0:
		_noise_t = 1.0
		GameState.make_noise(global_position, float(def.noise) * (0.6 + 0.4 * load))


## Running zombies over: they go flying, the vehicle takes a beating.
func _hit_zombies(dt: float) -> void:
	for z in _hit_cd.keys():
		_hit_cd[z] -= dt
		if _hit_cd[z] <= 0.0:
			_hit_cd.erase(z)
	if zombies == null or absf(speed) < 3.0 or kind in ["water", "heli"] or airborne:
		return
	var front := global_position + forward() * signf(speed) * size.z * 0.4
	for z in zombies.in_radius(front, size.x * 0.6 + 0.8):
		if _hit_cd.has(z):
			continue
		_hit_cd[z] = 0.8
		var push := forward() * signf(speed) * 0.8 + Vector3(0, 0.2, 0)
		z.take_damage(absf(speed) * 7.0, push)
		z.stagger(push, 1.2)
		if Effects.current:
			Effects.current.blood(z.global_position + Vector3(0, 1.0, 0), forward())
		_damage(2.0 + absf(speed) * 0.15)
		speed *= 0.9 if size.x > 1.0 else 0.5
		# Bikes: the rider takes a knock too.
		if size.x < 1.0 and absf(speed) > 6.0:
			for s in seats.values():
				if s is Player:
					(s as Player).take_damage(4.0, global_position)


func _alarm(dt: float) -> void:
	if _alarm_t <= 0.0:
		return
	var before := _alarm_t
	_alarm_t -= dt
	if int(before / 1.5) != int(_alarm_t / 1.5):
		GameState.make_noise(global_position, 70.0)
	var flash := int(_alarm_t * 3.0) % 2 == 0
	for l in _lights:
		l.visible = flash or (lights_on and running)


func _animate(dt: float) -> void:
	if _spinner:
		var target := 28.0 if running else 0.0
		_spin = move_toward(_spin, target, dt * 6.0)
		if rec.t == "helicopter":
			_spinner.rotate_y(_spin * dt)
		else:
			_spinner.rotate_z(_spin * dt * 1.5)
	for l in _lights:
		if _alarm_t <= 0.0:
			l.visible = lights_on and (running or def.fuel == "")


# --- Multiplayer ---

## Other players' seats changed (ours stay as they are).
func sync_seats(shared: Dictionary) -> void:
	for k in seats.keys():
		if not seats[k] is Player:
			seats.erase(k)
	for k in shared:
		if not seats.has(int(k)) and int(shared[k]) != Net.my_id():
			seats[int(k)] = int(shared[k])
	remote = seats.has(0) and not seats[0] is Player
	if remote:
		_net_pos = global_position
		_net_yaw = rotation.y


# ---------------------------------------------------------------------------

func net_state() -> Array:
	return [global_position, rotation.y, pitch, bank, running, speed, airborne, float(rec.fuel), float(rec.hp)]


func net_apply(st: Array) -> void:
	if not remote:
		return
	_net_pos = st[0]
	_net_yaw = st[1]
	pitch = st[2]
	bank = st[3]
	running = st[4]
	speed = st[5]
	airborne = st[6]
	rec.fuel = st[7]
	rec.hp = st[8]
	rec.p = [_net_pos.x, _net_pos.y, _net_pos.z]
	rec.yaw = _net_yaw
