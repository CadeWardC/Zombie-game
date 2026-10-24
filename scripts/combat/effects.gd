class_name Effects
extends Node3D
## Projectiles (arrows, bolts, thrown items), what thrown items do when they
## land (shatter, ring, burn, explode), and small hit effects (blood, dust,
## sparks). One node for the whole game; projectiles are stepped with
## raycasts, which is cheaper than rigid bodies and never tunnels.
##
## Multiplayer: every device flies every projectile (so everyone sees it);
## only the host hurts zombies, makes noise and leaves recoverable arrows.
## Each device hurts only its own player.

const GRAVITY := 9.8
const LIFETIME := 8.0
const PARTICLE_POOL := 10

static var current: Effects # The game's effects node (for windows, doors...).

var zombies: ZombieManager
var player: Player
var drops: DropManager
var gen: WorldGen

var _shots: Array = [] # {node, vel, item, dmg, kind, age, fuse, resting}
var _fires: Array = [] # {pos, t, tick, node}
var _alarms: Array = [] # {pos, t, tick, node}
var _particles: Array[CPUParticles3D] = []
var _particle_cursor := 0


func _ready() -> void:
	current = self
	for k in PARTICLE_POOL:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.95
		p.lifetime = 0.6
		p.amount = 14
		var box := BoxMesh.new()
		box.size = Vector3(0.035, 0.035, 0.035)
		box.material = Assets.particle_material
		p.mesh = box
		p.direction = Vector3.UP
		p.spread = 60.0
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 3.5
		p.gravity = Vector3(0, -9.8, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.3
		add_child(p)
		_particles.append(p)


## Removes every projectile, fire and alarm (respawn, tests).
func clear() -> void:
	for list in [_shots, _fires, _alarms]:
		for e in list:
			(e.node as Node).queue_free()
		list.clear()


# --- Hit effects -----------------------------------------------------------

func burst(pos: Vector3, normal: Vector3, col: Color, amount := 14, speed := 3.0) -> void:
	var p := _particles[_particle_cursor]
	_particle_cursor = (_particle_cursor + 1) % _particles.size()
	p.global_position = pos
	p.direction = normal if normal != Vector3.ZERO else Vector3.UP
	p.color = col
	p.amount = amount
	p.initial_velocity_max = speed
	p.initial_velocity_min = speed * 0.4
	p.restart()


func blood(pos: Vector3, dir: Vector3) -> void:
	burst(pos, (-dir + Vector3.UP * 0.5).normalized(), Color(0.45, 0.03, 0.02), 16, 3.0)


func impact(pos: Vector3, normal: Vector3) -> void:
	burst(pos + normal * 0.02, normal, Color(0.55, 0.52, 0.47), 8, 2.0)


# --- Projectiles -----------------------------------------------------------

## Launches an arrow / bolt ("arrow") or a thrown item ("throw").
func launch(kind: String, item_id: String, from: Vector3, vel: Vector3, dmg := 0.0, remote := false) -> void:
	if not remote and Net.active():
		Net.launch(kind, item_id, from, vel, dmg)
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.item_meshes.get(item_id)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = from
	var shot := {"node": mi, "vel": vel, "item": item_id, "dmg": dmg, "kind": kind, "age": 0.0, "resting": false, "mine": not remote,
		"fuse": 3.0 if ItemDB.get_def(item_id).get("effect", "") == "explode" else -1.0}
	_orient(shot)
	_shots.append(shot)


func _orient(shot: Dictionary) -> void:
	var mi: MeshInstance3D = shot.node
	var v: Vector3 = shot.vel
	if shot.kind == "arrow" and v.length() > 0.5:
		mi.look_at(mi.global_position + v, Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var k := _shots.size() - 1
	while k >= 0:
		var s: Dictionary = _shots[k]
		s.age += delta
		var mi: MeshInstance3D = s.node
		if s.fuse > 0.0:
			s.fuse -= delta
			if s.fuse <= 0.0:
				_explode(mi.global_position)
				mi.queue_free()
				_shots.remove_at(k)
				k -= 1
				continue
		if s.resting:
			k -= 1
			continue
		if s.age > LIFETIME:
			mi.queue_free()
			_shots.remove_at(k)
			k -= 1
			continue
		s.vel.y -= GRAVITY * (0.5 if s.kind == "arrow" else 1.0) * delta
		var from := mi.global_position
		var to := from + (s.vel as Vector3) * delta
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [player.get_rid()] if player else [])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			mi.global_position = to
			if s.kind == "arrow":
				_orient(s)
			else:
				mi.rotate_object_local(Vector3.RIGHT, delta * 9.0)
			k -= 1
			continue
		if _land(s, hit):
			mi.queue_free()
			_shots.remove_at(k)
		k -= 1
	_update_fires(delta)
	_update_alarms(delta)


## A projectile hit something. Returns true when it's used up.
func _land(s: Dictionary, hit: Dictionary) -> bool:
	var pos: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var mi: MeshInstance3D = s.node
	if s.kind == "arrow" and hit.collider is Animal:
		(hit.collider as Animal).take_damage(float(s.dmg), pos - (s.vel as Vector3).normalized())
		if drops and Net.authority() and randf() < 0.85:
			drops.drop(ItemDB.make(s.item), (hit.collider as Animal).global_position + Vector3(0, 0.4, 0))
		return true
	if s.kind == "arrow":
		var z := hit.collider as Zombie
		if z:
			var head := z.head_hit(pos)
			if Net.authority():
				z.take_damage(float(s.dmg) * (2.0 if head else 1.0), (s.vel as Vector3).normalized() * 0.3, true, true, head)
			blood(pos, (s.vel as Vector3).normalized())
			if s.get("mine", false):
				GameState.practice("aiming", 6.0)
			# Usually recoverable from the body.
			if randf() < 0.8 and drops and Net.authority():
				drops.drop(ItemDB.make(s.item), z.global_position + Vector3(0, 0.5, 0))
		else:
			impact(pos, normal)
			if randf() < 0.85 and drops and Net.authority():
				drops.drop(ItemDB.make(s.item), pos, false, false)
		_noise(pos, 4.0)
		return true
	# Thrown items.
	var effect: String = ItemDB.get_def(s.item).get("effect", "")
	match effect:
		"bottle":
			burst(pos, normal, Color(0.3, 0.55, 0.32), 18, 3.0)
			_noise(pos, 30.0)
			return true
		"fire":
			burst(pos, normal, Color(1.0, 0.55, 0.1), 20, 4.0)
			_noise(pos, 22.0)
			_start_fire(pos)
			return true
		"noise":
			_start_alarm(pos)
			return true
		"explode":
			# Bounce once or twice, then rest until the fuse runs out.
			var v: Vector3 = s.vel
			s.vel = v.bounce(normal) * 0.3
			mi.global_position = pos + normal * 0.05
			if (s.vel as Vector3).length() < 1.5:
				s.resting = true
			return false
	if drops and Net.authority():
		drops.drop(ItemDB.make(s.item), pos)
	return true


# --- Fire ------------------------------------------------------------------

func _start_fire(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	for k in 5:
		var f := MeshInstance3D.new()
		f.mesh = Assets.flame_mesh
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := k * TAU / 5.0
		f.position = Vector3(cos(a), 0.0, sin(a)) * (0.0 if k == 0 else 1.3)
		f.scale = Vector3(1.0, 0.9, 1.0) * (1.0 if k == 0 else 0.65)
		root.add_child(f)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.5
	light.omni_range = 9.0
	light.position.y = 1.0
	root.add_child(light)
	_fires.append({"pos": pos, "t": 10.0, "tick": 0.0, "node": root, "light": light})


func fire_near(pos: Vector3, radius: float) -> bool:
	for f in _fires:
		if (f.pos as Vector3).distance_to(pos) < radius:
			return true
	return false


func _update_fires(delta: float) -> void:
	var k := _fires.size() - 1
	while k >= 0:
		var f: Dictionary = _fires[k]
		f.t -= delta
		f.tick -= delta
		(f.light as OmniLight3D).light_energy = 2.0 + sin(f.t * 23.0) * 0.4 + sin(f.t * 7.0) * 0.3
		if f.tick <= 0.0:
			f.tick = 0.25
			if zombies and Net.authority():
				for z in zombies.in_radius(f.pos, 3.2):
					z.ignite(6.0)
			if player and not player.dead and player.global_position.distance_to(f.pos) < 2.8:
				player.hurt(3.0, f.pos, "fire")
		if f.t <= 0.0:
			(f.node as Node3D).queue_free()
			_fires.remove_at(k)
		k -= 1


# --- Alarm clocks ----------------------------------------------------------

func _start_alarm(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.item_meshes.noise_maker
	add_child(mi)
	mi.global_position = pos
	_alarms.append({"pos": pos, "t": 15.0, "tick": 0.0, "node": mi})


func _update_alarms(delta: float) -> void:
	var k := _alarms.size() - 1
	while k >= 0:
		var a: Dictionary = _alarms[k]
		a.t -= delta
		a.tick -= delta
		var mi: MeshInstance3D = a.node
		mi.rotation.z = sin(a.t * 60.0) * 0.12 # Rattling.
		if a.tick <= 0.0:
			a.tick = 1.0
			_noise(a.pos, 38.0)
		if a.t <= 0.0:
			mi.queue_free()
			_alarms.remove_at(k)
		k -= 1


# --- Explosions ------------------------------------------------------------

func _explode(pos: Vector3) -> void:
	const RADIUS := 7.0
	_noise(pos, 160.0)
	Sound.play_at("boom", pos, 6.0, 1.0, 400.0)
	burst(pos, Vector3.UP, Color(1.0, 0.6, 0.2), 24, 8.0)
	burst(pos, Vector3.UP, Color(0.25, 0.23, 0.2), 20, 5.0)
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	sphere.material = Assets.flash_material
	flash.mesh = sphere
	add_child(flash)
	flash.global_position = pos
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.4)
	light.light_energy = 8.0
	light.omni_range = 18.0
	flash.add_child(light)
	var tw := flash.create_tween()
	tw.tween_property(flash, "scale", Vector3.ONE * 4.0, 0.25)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)
	if zombies and Net.authority():
		for z in zombies.in_radius(pos, RADIUS):
			var d := z.global_position.distance_to(pos)
			var push := (z.global_position - pos).normalized()
			z.take_damage(220.0 * (1.0 - d / RADIUS) + 20.0, push, true, true, false, true)
	if player and not player.dead:
		var d := player.global_position.distance_to(pos)
		if d < RADIUS:
			player.hurt(110.0 * (1.0 - d / RADIUS), pos, "blast")


## Zombies live on the host, so only the host makes these noises (every
## device is simulating the same projectile).
func _noise(pos: Vector3, radius: float) -> void:
	if Net.authority():
		GameState.make_noise(pos, radius)
