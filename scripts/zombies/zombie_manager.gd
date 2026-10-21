class_name ZombieManager
extends Node3D
## Spawns, updates and recycles zombies around the player.
##
## Performance tricks:
## - Object pool: zombies are reused, never freed mid-game.
## - AI level of detail: full physics every frame near the player, cheap
##   terrain-following movement every few frames farther away.
## - Line-of-sight raycasts are spread out: only a couple per physics frame.

const DESPAWN_DIST := 150.0
const PHYSICS_DIST := 45.0
const MID_DIST := 90.0
const SPAWN_MIN := 55.0
const SPAWN_MAX := 110.0
const SIGHT_DAY := 26.0
const SIGHT_NIGHT := 12.0
const SIGHT_FLASHLIGHT := 22.0
const LOS_CHECKS_PER_FRAME := 2

var player: Player
var gen: WorldGen
var max_zombies := 28
var shadows := false

var _active: Array[Zombie] = []
var _pool: Array[Zombie] = []
var _frame := 0
var _spawn_t := 1.0
var _los_cursor := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	GameState.noise_made.connect(_on_noise)


func active_count() -> int:
	return _active.size()


func clear_all() -> void:
	while not _active.is_empty():
		_recycle(_active.size() - 1)


func set_shadows(enabled: bool) -> void:
	shadows = enabled
	for z in _active:
		z.set_shadows(enabled)
	for z in _pool:
		z.set_shadows(enabled)


func _physics_process(delta: float) -> void:
	if player == null or not player.active:
		return
	_frame += 1
	var ppos := player.global_position
	var night := GameState.is_night()

	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 0.7
		_try_spawn(ppos, night)

	var i := _active.size() - 1
	while i >= 0:
		var z := _active[i]
		var dist := z.position.distance_to(ppos)
		if dist > DESPAWN_DIST or (z.state == Zombie.State.DEAD and z.dead_timer <= 0.0):
			_recycle(i)
			i -= 1
			continue
		z.accum += delta
		var interval := 1 if dist < PHYSICS_DIST else (4 if dist < MID_DIST else 10)
		if interval == 1 or (_frame + z.slot) % interval == 0:
			z.update_ai(z.accum, player, dist, dist < PHYSICS_DIST, night, gen)
			z.accum = 0.0
		i -= 1

	_separate(ppos)
	_check_sight(ppos, night)


func _try_spawn(ppos: Vector3, night: bool) -> void:
	var in_town := gen.town_weight(ppos.x, ppos.z) > 0.5
	var wanted := 8 + (10 if night else 0) + (12 if in_town else 0)
	wanted = mini(wanted, max_zombies)
	if _active.size() >= wanted:
		return
	for attempt in 4:
		var ang := _rng.randf() * TAU
		var d := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var x := ppos.x + cos(ang) * d
		var z := ppos.z + sin(ang) * d
		if x < 50.0 or z < 50.0 or x > gen.world_size - 50.0 or z > gen.world_size - 50.0:
			continue
		if gen.is_inside_building(x, z):
			continue
		# Small groups, bigger at night.
		var group := _rng.randi_range(1, 4 if night else 2)
		for g in group:
			if _active.size() >= max_zombies:
				return
			var gx := x + _rng.randf_range(-3, 3)
			var gz := z + _rng.randf_range(-3, 3)
			_spawn(Vector3(gx, gen.height(gx, gz), gz))
		return


func _spawn(pos: Vector3) -> void:
	var z: Zombie
	if _pool.is_empty():
		z = Zombie.new()
		add_child(z)
	else:
		z = _pool.pop_back()
	z.slot = _rng.randi() % 10
	z.reset(pos, _rng.randi() % Assets.zombie_meshes.size(), _rng.randf_range(0.85, 1.15))
	z.set_shadows(shadows)
	_active.append(z)


func _recycle(index: int) -> void:
	var z := _active[index]
	_active.remove_at(index)
	z.visible = false
	z.collision_layer = 0
	z.velocity = Vector3.ZERO
	z.position = Vector3(0, -1000, 0)
	_pool.append(z)


func _on_noise(pos: Vector3, radius: float) -> void:
	var r2 := radius * radius
	for z in _active:
		if z.position.distance_squared_to(pos) < r2:
			z.hear(pos)


## Cheap crowd separation so zombies don't merge into one blob. Zombies don't
## collide with each other in the physics engine, which saves a lot of CPU.
func _separate(ppos: Vector3) -> void:
	var near: Array[Zombie] = []
	for z in _active:
		if z.state != Zombie.State.DEAD and z.position.distance_squared_to(ppos) < 900.0:
			near.append(z)
	for a in near.size():
		for b in range(a + 1, near.size()):
			var za := near[a]
			var zb := near[b]
			var diff := za.position - zb.position
			diff.y = 0.0
			var d := diff.length()
			if d < 0.7 and d > 0.001:
				var push := diff / d * (0.7 - d) * 0.5
				za.position += push
				zb.position -= push


func _check_sight(ppos: Vector3, night: bool) -> void:
	if _active.is_empty() or player.dead:
		return
	var range_ := SIGHT_DAY
	if night:
		range_ = SIGHT_FLASHLIGHT if player.flashlight.visible else SIGHT_NIGHT
	if player.sprinting:
		range_ *= 1.2
	var space := get_world_3d().direct_space_state
	var eye := ppos + Vector3(0, Player.EYE_HEIGHT, 0)
	for k in mini(LOS_CHECKS_PER_FRAME, _active.size()):
		_los_cursor = (_los_cursor + 1) % _active.size()
		var z := _active[_los_cursor]
		if z.state == Zombie.State.DEAD:
			continue
		var to := ppos - z.position
		var dist := to.length()
		if dist > range_:
			continue
		var forward := -z.global_basis.z
		if dist > 4.0 and forward.dot(to / dist) < 0.35:
			continue
		var query := PhysicsRayQueryParameters3D.create(z.position + Vector3(0, 1.6, 0), eye, 1)
		if space.intersect_ray(query).is_empty():
			z.see_player()
