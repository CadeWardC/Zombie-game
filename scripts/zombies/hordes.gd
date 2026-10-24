class_name Hordes
extends RefCounted
## Roaming hordes and the slow return of the dead. Host only.
##
## A horde is a record in GameState.ws.hordes: {id, p: [x, z], goal: [x, z],
## size}. Out of sight it's just a point drifting from town to town at a
## shamble; loud noises (gunfire, generators, alarms, explosions) pull it
## off course. When a player comes within reach its zombies appear around
## that point and walk together toward its goal; when everyone is gone they
## fold back into the record (the living ones).
##
## Clearing an area thins it out: kills are counted per square of the map
## (GameState.ws.cleared) and spawning there drops, recovering over a few
## in-game days or at once when a horde passes through.

const SPEED := 0.6 # Metres per second while drifting (out of sight).
const WAKE := 170.0 # A horde appears this close to a player...
const SLEEP := 260.0 # ...and folds away again beyond this.
const NOISE_PULL := 700.0 # Loud noises within this distance draw hordes.
const CELL := 256.0
const RECOVER_HOURS := 96.0 # A cleared area fills back up over this long.

var mgr: ZombieManager
var gen: WorldGen
var active := {} # Horde id -> Array[Zombie] while it's out in the world.
var _tick_t := 0.0


func _init(manager: ZombieManager, g: WorldGen) -> void:
	mgr = manager
	gen = g


## First time in a world: a few hordes, more on bigger maps.
func ensure() -> void:
	if not GameState.ws.hordes.is_empty() or gen == null or gen.settlements.list.is_empty():
		return
	var n := {8192: 3, 16384: 6, 32768: 12}.get(int(gen.world_size), 3) as int
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_value + 4242
	for k in n:
		var s: Dictionary = gen.settlements.list[rng.randi() % gen.settlements.list.size()]
		var c: Vector2 = s.center + Vector2.from_angle(rng.randf() * TAU) * (float(s.radius) + 400.0)
		var id := "h%d" % k
		GameState.ws.hordes[id] = {"id": id, "p": [c.x, c.y], "goal": [c.x, c.y], "size": rng.randi_range(18, 35)}
		_new_goal(GameState.ws.hordes[id], rng.randi())


func _new_goal(h: Dictionary, r: int) -> void:
	var list: Array = gen.settlements.list
	var s: Dictionary = list[absi(r) % list.size()]
	var c: Vector2 = s.center
	h.goal = [c.x, c.y]


func pos(h: Dictionary) -> Vector2:
	return Vector2(float(h.p[0]), float(h.p[1]))


func goal(h: Dictionary) -> Vector2:
	return Vector2(float(h.goal[0]), float(h.goal[1]))


## Where a horde's zombies are heading (with a spread so they don't stack).
func goal_for(id: String, slot: int) -> Vector3:
	var h: Dictionary = GameState.ws.hordes.get(id, {})
	if h.is_empty():
		return Vector3.INF
	var g := goal(h) + Vector2.from_angle(slot * 0.63) * (4.0 + slot % 5 * 2.0)
	return Vector3(g.x, 0, g.y)


## A big noise: nearby hordes turn toward it.
func hear(p: Vector3, radius: float) -> void:
	if radius < 60.0:
		return
	for id in GameState.ws.hordes:
		var h: Dictionary = GameState.ws.hordes[id]
		if pos(h).distance_to(Vector2(p.x, p.z)) < minf(NOISE_PULL, radius * 6.0):
			h.goal = [p.x, p.z]


## A zombie from a horde died: the horde is smaller.
func died(z: Zombie) -> void:
	var h: Dictionary = GameState.ws.hordes.get(z.horde_id, {})
	if not h.is_empty():
		h.size = maxi(0, int(h.size) - 1)


## Kills thin an area out.
func record_kill(p: Vector3) -> void:
	var key := "%d_%d" % [int(p.x / CELL), int(p.z / CELL)]
	var c: Dictionary = GameState.ws.cleared.get(key, {"n": 0.0, "h": GameState.hours()})
	c.n = _decayed(c) + 1.0
	c.h = GameState.hours()
	GameState.ws.cleared[key] = c


func _decayed(c: Dictionary) -> float:
	var hours := GameState.hours() - float(c.get("h", 0.0))
	return maxf(0.0, float(c.get("n", 0.0)) * (1.0 - hours / RECOVER_HOURS))


## 0.25..1: how much of its usual population an area has (for spawning).
func density(p: Vector3) -> float:
	var c: Dictionary = GameState.ws.cleared.get("%d_%d" % [int(p.x / CELL), int(p.z / CELL)], {})
	if c.is_empty():
		return 1.0
	return clampf(1.0 - _decayed(c) / 40.0, 0.25, 1.0)


## Every few seconds: drift, wake near players, sleep when they're gone.
func update(delta: float, targets: Array) -> void:
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	var dt := 2.0 - _tick_t
	_tick_t = 2.0
	for id in GameState.ws.hordes.keys():
		var h: Dictionary = GameState.ws.hordes[id]
		if int(h.size) <= 0:
			_sleep(id)
			GameState.ws.hordes.erase(id)
			continue
		var near := INF
		for t: Node3D in targets:
			near = minf(near, pos(h).distance_to(Vector2(t.global_position.x, t.global_position.z)))
		if active.has(id):
			# Out in the world: the horde is where its zombies are.
			var zs: Array = active[id].filter(func(z: Zombie) -> bool: return is_instance_valid(z) and z.alive() and z.horde_id == id)
			active[id] = zs
			if zs.is_empty():
				active.erase(id)
				continue
			var c := Vector2.ZERO
			for z: Zombie in zs:
				c += Vector2(z.position.x, z.position.z)
			c /= zs.size()
			h.p = [c.x, c.y]
			if near > SLEEP:
				_sleep(id)
		else:
			# Drifting: shamble toward the goal; pick a new town on arrival.
			var p := pos(h)
			var to := goal(h) - p
			if to.length() < 30.0:
				_new_goal(h, randi())
			else:
				p += to.normalized() * minf(SPEED * dt * GameState.time_mult(), to.length())
				h.p = [p.x, p.y]
				# Passing through refills an area.
				GameState.ws.cleared.erase("%d_%d" % [int(p.x / CELL), int(p.y / CELL)])
			if near < WAKE:
				_wake(id)


func _wake(id: String) -> void:
	var h: Dictionary = GameState.ws.hordes[id]
	var c := pos(h)
	var zs: Array = []
	var n := mini(int(h.size), 30)
	for k in n:
		var q := c + Vector2.from_angle(k * 2.4) * (2.0 + sqrt(float(k)) * 2.2)
		if gen.water_level(q.x, q.y) > -INF:
			continue
		var z := mgr.spawn_horde_zombie(Vector3(q.x, gen.height(q.x, q.y), q.y))
		if z == null:
			break
		z.horde_id = id
		zs.append(z)
	active[id] = zs


func _sleep(id: String) -> void:
	# The living go back into the record (deaths were already counted).
	for z in active.get(id, []):
		if is_instance_valid(z) and z.alive() and z.horde_id == id:
			mgr.despawn(z)
	active.erase(id)
