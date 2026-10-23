class_name Dog
extends Animal
## A dog. Strays keep their distance until you give them food (dog food or
## meat); then they're yours: they follow you, growl when zombies are near,
## and fight the ones that come for you. They can be hurt and killed.
## Saved in GameState.ws.dogs: {id, owner (player id, "" for a stray),
## hp, p, stay}.

const GROWL_RANGE := 22.0
const BITE := 18.0

var rec: Dictionary
var owner_player: Player # The local player, if this dog is theirs.
var zombies: ZombieManager
var _bite_cd := 0.0
var _growl_t := 0.0
var _hurt_cd := 0.0
var _foe: Zombie


func setup_dog(r: Dictionary, g: WorldGen) -> void:
	rec = r
	var p: Array = r.p
	setup("dog", Vector3(p[0], p[1], p[2]), g)
	health = float(r.get("hp", def.hp))


func tame() -> bool:
	return str(rec.get("owner", "")) != ""


func mine() -> bool:
	return str(rec.get("owner", "")) == GameState.player_id


func take_damage(amount: float, from: Vector3) -> void:
	if not alive():
		return
	health -= amount
	rec.hp = health
	if Effects.current:
		Effects.current.blood(global_position + Vector3(0, 0.5, 0), (global_position - from).normalized())
	if health <= 0.0:
		_die()
		GameState.ws.dogs.erase(rec.id)
		GameState.notify("Your dog is dead." if mine() else "The dog is dead.")


func update(dt: float) -> void:
	_bite_cd -= dt
	_growl_t -= dt
	_hurt_cd -= dt
	if not tame():
		_stray(dt)
		return
	var p := owner_player
	if p == null or p.dead:
		move(global_position, 0.0, dt)
		return
	# Danger nearby: growl, and go for zombies chasing your person.
	_foe = null
	if zombies:
		var near := zombies.in_radius(global_position, GROWL_RANGE)
		var best := 999.0
		for z in near:
			if not z.alive():
				continue
			var d := z.global_position.distance_to(p.global_position)
			if z.state == Zombie.State.CHASE and d < 10.0 and d < best:
				best = d
				_foe = z
		if not near.is_empty() and _growl_t <= 0.0:
			_growl_t = 25.0
			GameState.notify("Your dog growls - zombies nearby")
	if _foe:
		var d := _flat(_foe.global_position)
		if d > 1.3:
			move(_foe.global_position, float(def.run), dt)
		else:
			move(global_position, 0.0, dt)
			look_at(Vector3(_foe.global_position.x, global_position.y, _foe.global_position.z), Vector3.UP, true)
			if _bite_cd <= 0.0:
				_bite_cd = 1.0
				_foe.take_damage(BITE, (_foe.global_position - global_position).normalized() * 0.3, true, true)
				GameState.make_noise(global_position, 12.0)
			# Fighting zombies is dangerous.
			if _hurt_cd <= 0.0 and _foe.alive():
				_hurt_cd = 1.5
				if randf() < 0.3:
					take_damage(10.0, _foe.global_position)
		return
	if rec.get("stay", false):
		move(global_position, 0.0, dt)
		return
	# Heel: trot after your person, keeping a couple of metres back.
	var behind := p.global_position + p.global_basis.z * 2.2 + p.global_basis.x * 0.8
	var dist := _flat(behind)
	if dist > 60.0:
		global_position = behind # Lost: catches up (off-screen).
	var speed := 0.0 if dist < 0.8 else (float(def.walk) * 2.0 if dist < 6.0 else float(def.run))
	speed = minf(speed, maxf(float(def.walk), p.velocity.length() * 1.4 + 1.0)) if dist < 6.0 else speed
	move(behind, speed, dt)
	rec.p = [global_position.x, global_position.y, global_position.z]


## Strays wander, and back away from people who come too close.
func _stray(dt: float) -> void:
	_think -= dt
	var p := owner_player
	if p and _flat(p.global_position) < 4.0:
		var away := global_position - p.global_position
		away.y = 0.0
		move(global_position + away.normalized() * 3.0, float(def.walk) * 2.0, dt)
		return
	if _think <= 0.0:
		_think = randf_range(3.0, 7.0)
		var home: Array = rec.get("home", rec.p)
		target = Vector3(home[0], 0, home[2]) + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
	move(target, float(def.walk), dt)
	rec.p = [global_position.x, global_position.y, global_position.z]


## Food wins it over (or feeds your own dog, healing it).
func feed() -> String:
	if tame():
		health = minf(float(def.hp), health + 30.0)
		rec.hp = health
		return "Your dog wolfs it down"
	rec.owner = GameState.player_id
	rec.stay = false
	return "The dog eats, wags its tail, and decides you're its person"
