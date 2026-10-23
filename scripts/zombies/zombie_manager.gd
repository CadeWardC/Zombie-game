class_name ZombieManager
extends Node3D
## Spawns, updates and recycles zombies around the player.
##
## Performance tricks:
## - Object pool: zombies are reused, never freed mid-game.
## - AI level of detail: full physics every frame near the player, cheap
##   terrain-following movement every few frames farther away.
## - Line-of-sight raycasts are spread out: only a couple per physics frame.
##
## Also decides which type each zombie is (more runners at night, soldiers
## around research sites), fills buildings' interior spawn points, and keeps
## turned players walking the world with their gear.
##
## Multiplayer: the host simulates zombies around every player (each zombie
## goes after the nearest one) and sends each guest the zombies near them;
## on a guest this node only shows those as puppets.

signal screamed(pos: Vector3)
## A turned player was given the cure (multiplayer brings them back).
signal turned_cured(entry: Dictionary)

const DESPAWN_DIST := 150.0
const PHYSICS_DIST := 45.0
const MID_DIST := 90.0
const SPAWN_MIN := 55.0
const SPAWN_MAX := 110.0
const SIGHT_DAY := 26.0
const SIGHT_NIGHT := 12.0
const SIGHT_FLASHLIGHT := 22.0
const LOS_CHECKS_PER_FRAME := 3

var player: Player
var gen: WorldGen
var streamer: WorldStreamer
var drops: DropManager
var avatars: Avatars
var bases: BaseManager
var traders: TraderManager
var max_zombies := 28
var shadows := false
## 0..1: how close any zombie is to spotting the player (1 = being chased).
## Drives the HUD's stealth eye.
var detection := 0.0

var _active: Array[Zombie] = []
var _pool: Array[Zombie] = []
var _frame := 0
var _spawn_t := 1.0
var _los_cursor := 0
var _rng := RandomNumberGenerator.new()
var _special_t := 0.0
var _by_spawn := {} # Interior spawn id -> Zombie
var _by_turned := {} # Turned player id -> Zombie
var _by_net := {} # Net id -> Zombie
var _next_net_id := 1
var _spawn_cursor := 0


func _ready() -> void:
	_rng.randomize()
	GameState.noise_made.connect(_on_noise)


func active_count() -> int:
	return _active.size()


## Live zombies within `radius` of `pos`.
func in_radius(pos: Vector3, radius: float) -> Array[Zombie]:
	var out: Array[Zombie] = []
	var r2 := radius * radius
	for z in _active:
		if z.alive() and z.position.distance_squared_to(pos) < r2:
			out.append(z)
	return out


func clear_all() -> void:
	while not _active.is_empty():
		_recycle(_active.size() - 1)


func set_shadows(enabled: bool) -> void:
	shadows = enabled
	for z in _active:
		z.set_shadows(enabled)
	for z in _pool:
		z.set_shadows(enabled)


## Everyone zombies can go after: this device's player and, on a host, the
## other players' avatars.
func targets() -> Array:
	var out: Array = [player]
	if avatars and Net.is_host():
		out.append_array(avatars.targets())
	return out


func by_net_id(id: int) -> Zombie:
	return _by_net.get(id)


func _physics_process(delta: float) -> void:
	if player == null or not player.active:
		return
	_frame += 1
	if Net.is_client():
		_update_puppets(delta)
		return
	var ppos := player.global_position
	var night := GameState.is_night()
	var tgts := targets()

	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 0.7 / tgts.size()
		_spawn_cursor = (_spawn_cursor + 1) % tgts.size()
		_try_spawn((tgts[_spawn_cursor] as Node3D).global_position, night)
	_special_t -= delta
	if _special_t <= 0.0:
		_special_t = 1.0
		for t: Node3D in tgts:
			_spawn_interiors(t.global_position, night)
			_spawn_turned(t.global_position)

	var i := _active.size() - 1
	while i >= 0:
		var z := _active[i]
		# Each zombie deals with the nearest player.
		var tgt: Node3D = player
		var dist := INF
		for t: Node3D in tgts:
			var d := z.position.distance_to(t.global_position)
			if d < dist and not (t != player and t.dead):
				dist = d
				tgt = t
		if dist > DESPAWN_DIST or (z.state == Zombie.State.DEAD and z.dead_timer <= 0.0):
			_recycle(i)
			i -= 1
			continue
		z.accum += delta
		var interval := 1 if dist < PHYSICS_DIST else (4 if dist < MID_DIST else 10)
		if interval == 1 or (_frame + z.slot) % interval == 0:
			# Real collision needs the ground built there (near a guest far
			# from the host it may not be yet).
			var physics := dist < PHYSICS_DIST and (tgt == player or streamer == null or streamer.is_ready_at(z.position))
			z.update_ai(z.accum, tgt, dist, physics, night, gen)
			z.accum = 0.0
		# Animation level of detail: smooth up close, choppier (and much
		# cheaper) farther away.
		z.anim_accum += delta
		var anim_interval := 1 if dist < 25.0 else (3 if dist < 60.0 else 8)
		if anim_interval == 1 or (_frame + z.slot) % anim_interval == 0:
			z.advance_anim(z.anim_accum)
			z.anim_accum = 0.0
		i -= 1

	for t: Node3D in tgts:
		_separate(t.global_position)
	for t: Node3D in tgts:
		_check_sight(t, night)
	var det := 0.0
	for z in _active:
		if z.alive() and z.position.distance_squared_to(ppos) < 1600.0:
			det = maxf(det, 1.0 if z.state == Zombie.State.CHASE else z.awareness)
	detection = det


func _try_spawn(ppos: Vector3, night: bool) -> void:
	var in_town := gen.town_weight(ppos.x, ppos.z) > 0.5
	var wanted := int((8 + (10 if night else 0) + (12 if in_town else 0)) * GameState.difficulty().zombies)
	wanted = mini(wanted, max_zombies)
	# Count the zombies around this player; the overall cap grows a little
	# with each extra player.
	var near := 0
	for z in _active:
		if z.position.distance_squared_to(ppos) < DESPAWN_DIST * DESPAWN_DIST:
			near += 1
	if near >= wanted or _active.size() >= cap():
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
		if traders and traders.in_safe_zone(Vector3(x, 0, z)):
			continue
		# Small groups, bigger at night.
		var group := _rng.randi_range(1, 4 if night else 2)
		for g in group:
			if _active.size() >= cap():
				return
			var gx := x + _rng.randf_range(-3, 3)
			var gz := z + _rng.randf_range(-3, 3)
			_spawn(Vector3(gx, gen.height(gx, gz), gz), pick_type(night, Vector3(x, 0, z)))
		return


## Which kind of zombie spawns: mostly walkers; runners at night (more with
## the "fast" setting, none with "shamblers"); soldiers guard research sites.
func pick_type(night: bool, pos: Vector3) -> String:
	var speed := GameState.zombie_speed()
	var w := {"walker": 1.0, "brute": 0.035, "screamer": 0.035, "crawler": 0.07,
		"runner": (0.22 if night else 0.04) * [0.0, 1.0, 2.5][speed]}
	if gen and gen.settlements:
		for s in gen.settlements.sites_near(Vector2(pos.x, pos.z), 160.0):
			if s.type == "research":
				w.soldier = 0.6
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := _rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "walker"


## Most zombies at once: grows by 60% of the single-player cap per extra
## player, so a host like the Tab S6 Lite stays within budget.
func cap() -> int:
	return int(max_zombies * (1.0 + 0.6 * (targets().size() - 1)))


## A zombie shambling in from `dist` metres away, already onto the player
## (e.g. finding someone asleep in the open). Host only.
func spawn_near(pos: Vector3, dist: float) -> void:
	if not Net.authority() or _active.size() >= cap():
		return
	var a := _rng.randf() * TAU
	var p := pos + Vector3(cos(a), 0, sin(a)) * dist
	p.y = gen.height(p.x, p.z)
	var z := _spawn(p)
	z.hear(pos)


func _spawn(pos: Vector3, type := "walker", mesh: Mesh = null) -> Zombie:
	var z: Zombie
	if _pool.is_empty():
		z = Zombie.new()
		add_child(z)
	else:
		z = _pool.pop_back()
	z.slot = _rng.randi() % 10
	z.mgr = self
	z.reset(pos, type, _rng.randi() % 8, _rng.randf_range(0.85, 1.15), mesh)
	z.set_shadows(shadows)
	z.net_id = _next_net_id
	_next_net_id += 1
	_by_net[z.net_id] = z
	_active.append(z)
	return z


## Zombies waiting inside buildings (labs, some houses). A killed one stays
## dead for two in-game days.
func _spawn_interiors(ppos: Vector3, night: bool) -> void:
	if streamer == null:
		return
	for sp in streamer.spawns_near(ppos, 55.0):
		if _by_spawn.has(sp.id) or not GameState.spawn_ready(sp.id):
			continue
		if _active.size() >= max_zombies + 14:
			return
		var pos: Vector3 = sp.pos
		if pos.distance_to(ppos) < 10.0:
			continue # Never pop in right next to the player.
		var kind: String = sp.get("kind", "")
		var z: Zombie
		if kind == "scientist":
			var looks: Array = ZombieModel.type_meshes.scientist
			var v := _rng.randi() % looks.size()
			z = _spawn(pos, "walker", looks[v])
			z.variant = v
			z.look_kind = "scientist"
		else:
			z = _spawn(pos, kind if kind != "" else pick_type(night, pos))
		z.spawn_id = sp.id
		_by_spawn[sp.id] = z


## Turned players roam near where they fell, wearing their clothes.
func _spawn_turned(ppos: Vector3) -> void:
	for entry in GameState.ws.get("turned", []):
		if _by_turned.has(entry.id):
			continue
		var p: Array = entry.p
		var pos := Vector3(p[0], p[1], p[2])
		if pos.distance_to(ppos) > 110.0 or pos.distance_to(ppos) < 8.0:
			continue
		var ch := Character.from_dict(entry.get("char", {}))
		var z := _spawn(pos, "walker", ZombieModel.mesh_for(ch.body_look(entry.get("equip", {}), true)))
		z.look_kind = "turned"
		z.make_turned(entry)
		_by_turned[entry.id] = z


## Called by a zombie as it dies: loot, spawn timers, turned players' gear.
func zombie_died(z: Zombie) -> void:
	if z.spawn_id != "":
		GameState.spawn_killed(z.spawn_id)
	if z.turned_id != "":
		GameState.remove_turned(z.turned_id)
		if Net.active():
			if z.turned_owner == GameState.player_id:
				get_parent().on_body_gone()
			else:
				Net.body_gone(z.turned_owner)
		if drops:
			for k in z.turned_items.size():
				drops.drop(z.turned_items[k], z.global_position + Vector3(cos(k * 2.4), 0.4, sin(k * 2.4)) * 0.6)
		GameState.notify("%s is at rest now" % z.turned_name)
		z.turned_items = []
	elif z.type == "soldier" and drops and _rng.randf() < 0.5:
		drops.drop(Loot.roll_from("military", _rng.randi()), z.global_position + Vector3(0, 0.4, 0))


func _recycle(index: int) -> void:
	var z := _active[index]
	_active.remove_at(index)
	if _by_net.get(z.net_id) == z:
		_by_net.erase(z.net_id)
	if z.spawn_id != "" and _by_spawn.get(z.spawn_id) == z:
		_by_spawn.erase(z.spawn_id)
	if z.turned_id != "":
		_by_turned.erase(z.turned_id)
		# Remember where they wandered to.
		for entry in GameState.ws.turned:
			if entry.id == z.turned_id:
				entry.p = [z.position.x, z.position.y, z.position.z]
	z.spawn_id = ""
	z.turned_id = ""
	z.visible = false
	z.collision_layer = 0
	z.velocity = Vector3.ZERO
	z.position = Vector3(0, -1000, 0)
	_pool.append(z)


func _on_noise(pos: Vector3, radius: float) -> void:
	# Rain and storms drown sounds out.
	radius *= Weather.sense_factor()
	var r2 := radius * radius
	for z in _active:
		if z.position.distance_squared_to(pos) < r2:
			z.hear(pos)


## Cheap crowd separation so zombies don't merge into one blob. Zombies don't
## collide with each other in the physics engine, which saves a lot of CPU.
func _separate(ppos: Vector3) -> void:
	var near: Array[Zombie] = []
	for z in _active:
		if z.alive() and z.position.distance_squared_to(ppos) < 900.0:
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


## Stealth: zombies that can see a player build up awareness, faster when
## close; crouching, cover and darkness shrink how far they can see.
func _check_sight(who: Node3D, night: bool) -> void:
	if _active.is_empty() or who.dead:
		return
	var ppos := who.global_position
	var range_ := SIGHT_DAY
	if night:
		range_ = SIGHT_FLASHLIGHT if who.flashlight.visible else SIGHT_NIGHT
	range_ *= who.visibility() * Weather.sense_factor()
	var space := get_world_3d().direct_space_state
	var eye := ppos + Vector3(0, who.head.position.y, 0)
	var now := Time.get_ticks_msec()
	for k in mini(LOS_CHECKS_PER_FRAME, _active.size()):
		_los_cursor = (_los_cursor + 1) % _active.size()
		var z := _active[_los_cursor]
		var dt := minf((now - z.last_sight_check) / 1000.0, 0.5)
		z.last_sight_check = now
		if not z.alive():
			continue
		var to := ppos - z.position
		var dist := to.length()
		# Crawlers lie low: they only spot you close up.
		if dist > (minf(range_, 8.0) if z.type == "crawler" else range_):
			continue
		var forward := -z.global_basis.z
		# Right next to a zombie it senses you anyway, unless you're sneaking.
		var close: bool = dist < 2.5 and not who.crouching
		if not close and forward.dot(to / maxf(dist, 0.01)) < 0.35:
			continue
		var query := PhysicsRayQueryParameters3D.create(z.position + Vector3(0, 1.6, 0), eye, 1)
		if not space.intersect_ray(query).is_empty():
			continue
		if close or z.state == Zombie.State.CHASE:
			z.see_player()
		else:
			var near := 1.0 - dist / range_
			z.notice(dt * (0.25 + 1.8 * near * near), ppos)


# --- Multiplayer -----------------------------------------------------------------------

## Host: the zombies near a guest, for their device to show.
func snapshot(pos: Vector3, _peer: int) -> Array:
	var out := []
	var r2 := DESPAWN_DIST * DESPAWN_DIST
	for z in _active:
		if z.position.distance_squared_to(pos) < r2:
			out.append(z.net_line())
	return out


## Guest: create, move or remove puppets to match the host.
func apply_snapshot(snap: Array) -> void:
	for line in snap:
		var id: int = line[0]
		var z: Zombie = _by_net.get(id)
		if z == null:
			z = _spawn_puppet(line)
		z.net_apply(line)


func _spawn_puppet(line: Array) -> Zombie:
	var z: Zombie
	if _pool.is_empty():
		z = Zombie.new()
		add_child(z)
	else:
		z = _pool.pop_back()
	var mesh: Mesh = null
	match str(line[3]):
		"scientist":
			var looks: Array = ZombieModel.type_meshes.scientist
			mesh = looks[int(line[2]) % looks.size()]
		"turned":
			for entry in GameState.ws.turned:
				if entry.id == str(line[4]):
					mesh = ZombieModel.mesh_for(Character.from_dict(entry.get("char", {})).body_look(entry.get("equip", {}), true))
					z.turned_name = str(entry.get("name", "Survivor"))
	z.mgr = self
	z.slot = _rng.randi() % 10
	var name_kept := z.turned_name
	z.reset(line[5], str(line[1]), int(line[2]), 1.0, mesh)
	z.position = line[5]
	z.rotation.y = line[6]
	z.puppet = true
	z.look_kind = str(line[3])
	z.turned_id = str(line[4])
	z.turned_name = name_kept
	z.net_id = int(line[0])
	z.set_shadows(shadows)
	_by_net[z.net_id] = z
	_active.append(z)
	return z


func _update_puppets(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var ppos := player.global_position
	var det := 0.0
	var i := _active.size() - 1
	while i >= 0:
		var z := _active[i]
		# Gone from the host's updates: despawned or out of range.
		if now - z._net_seen > 1500:
			_recycle(i)
			i -= 1
			continue
		z.update_puppet(delta)
		var dist := z.position.distance_to(ppos)
		z.anim_accum += delta
		var anim_interval := 1 if dist < 25.0 else (3 if dist < 60.0 else 8)
		if anim_interval == 1 or (_frame + z.slot) % anim_interval == 0:
			z.advance_anim(z.anim_accum)
			z.anim_accum = 0.0
		if z.alive() and dist < 40.0:
			det = maxf(det, 1.0 if z.state == Zombie.State.CHASE and dist < 25.0 else z.awareness)
		i -= 1
	detection = det
