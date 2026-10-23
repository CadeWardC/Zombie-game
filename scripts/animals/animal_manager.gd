class_name AnimalManager
extends Node3D
## Wildlife around the player: deer in forests and on hills, rabbits and wild
## turkeys in fields and woods. A few at a time, spawned out of sight and
## removed when far away. Each device runs its own wildlife (it isn't shared
## in multiplayer); the meat you take is real.
##
## Also keeps the world's dogs (GameState.ws.dogs): a stray now and then in
## towns, and your own dog, which follows you everywhere.

const MAX_WILD := 6
const SPAWN_MIN := 60.0
const SPAWN_MAX := 140.0
const DESPAWN := 220.0

var gen: WorldGen
var player: Player
var zombies: ZombieManager
var animals: Array[Animal] = []
var dogs := {} # id -> Dog

var _spawn_t := 2.0
var _sight_t := 0.0


func _ready() -> void:
	GameState.noise_made.connect(func(pos: Vector3, radius: float) -> void:
		for a in animals:
			a.hear(pos, radius))


func _process(delta: float) -> void:
	if player == null or not player.active:
		return
	var pp := player.global_position
	# Wild animals see you coming (less when you crouch in cover).
	_sight_t -= delta
	if _sight_t <= 0.0:
		_sight_t = 0.25
		for a in animals:
			if a.alive() and a.state != Animal.State.FLEE:
				var d := a.global_position.distance_to(pp)
				if d < float(a.def.sight) * player.visibility() * (0.7 if player.crouching else 1.0):
					a.scare(pp)
	for k in range(animals.size() - 1, -1, -1):
		var a := animals[k]
		if a.global_position.distance_to(pp) > DESPAWN or a.dead_t > 400.0 or a.butchered and a.dead_t > 5.0:
			animals.remove_at(k)
			a.queue_free()
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 4.0
		_spawn_wild(pp)
		_update_dogs(pp)


func _spawn_wild(pp: Vector3) -> void:
	var alive := 0
	for a in animals:
		if a.alive():
			alive += 1
	if alive >= MAX_WILD or gen == null:
		return
	var ang := randf() * TAU
	var p := pp + Vector3(cos(ang), 0, sin(ang)) * randf_range(SPAWN_MIN, SPAWN_MAX)
	if gen.town_weight(p.x, p.z) > 0.0 or gen.water_level(p.x, p.z) > -INF or gen.is_inside_building(p.x, p.z):
		return
	var tr := gen.terrain
	var biome := tr.biome_at(p.x, p.z, tr.macro_height(p.x, p.z))
	var pick := ""
	var r := randf()
	match biome:
		Terrain.Biome.FOREST:
			pick = "deer" if r < 0.45 else ("turkey" if r < 0.75 else "rabbit")
		Terrain.Biome.PLAINS, Terrain.Biome.FARMLAND:
			pick = "rabbit" if r < 0.5 else ("deer" if r < 0.75 else "turkey")
		Terrain.Biome.MOUNTAIN:
			pick = "deer" if r < 0.7 else "rabbit"
		Terrain.Biome.DESERT:
			pick = "rabbit" if r < 0.5 else ""
	if pick == "":
		return
	# Deer come in small groups.
	var count := 1 + (randi() % 3 if pick == "deer" else 0)
	for k in count:
		var off := Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)) if k > 0 else Vector3.ZERO
		var a := Animal.new()
		add_child(a)
		var q := p + off
		q.y = gen.height(q.x, q.z)
		a.setup(pick, q, gen)
		animals.append(a)


## Dogs: your own follows you; strays turn up in towns once in a while.
func _update_dogs(pp: Vector3) -> void:
	for id in GameState.ws.dogs:
		var r: Dictionary = GameState.ws.dogs[id]
		var mine := str(r.get("owner", "")) == GameState.player_id
		var p: Array = r.p
		var near := Vector3(p[0], p[1], p[2]).distance_to(pp) < DESPAWN
		if (mine or (near and str(r.get("owner", "")) == "")) and not dogs.has(id):
			if mine and not near:
				r.p = [pp.x + 2.0, pp.y, pp.z + 2.0]
			_spawn_dog(r)
	for id in dogs.keys():
		var d: Dog = dogs[id]
		if not GameState.ws.dogs.has(id) and d.alive():
			d.queue_free()
			dogs.erase(id)
		elif not d.mine() and d.global_position.distance_to(pp) > DESPAWN:
			d.queue_free()
			dogs.erase(id)
		elif not d.alive() and d.dead_t > 300.0:
			d.queue_free()
			dogs.erase(id)
	# A stray, now and then, in a town (only one wandering the world at a time).
	var strays := 0
	for id in GameState.ws.dogs:
		if str(GameState.ws.dogs[id].get("owner", "")) == "":
			strays += 1
	if strays == 0 and gen and gen.town_weight(pp.x, pp.z) > 0.0 and randf() < 0.04:
		var ang := randf() * TAU
		var q := pp + Vector3(cos(ang), 0, sin(ang)) * 35.0
		if not gen.is_inside_building(q.x, q.z) and gen.water_level(q.x, q.z) == -INF:
			q.y = gen.height(q.x, q.z)
			var id := "dog_%d" % int(GameState.hours() * 100.0)
			GameState.ws.dogs[id] = {"id": id, "owner": "", "hp": 80.0, "p": [q.x, q.y, q.z], "home": [q.x, q.y, q.z], "stay": false}


func _spawn_dog(r: Dictionary) -> Dog:
	var d := Dog.new()
	d.owner_player = player
	d.zombies = zombies
	add_child(d)
	d.setup_dog(r, gen)
	dogs[r.id] = d
	return d


## The live dog that's yours (or null).
func my_dog() -> Dog:
	for d: Dog in dogs.values():
		if d.mine() and d.alive():
			return d
	return null
