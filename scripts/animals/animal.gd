class_name Animal
extends CharacterBody3D
## A deer, rabbit or wild turkey (or a dog, see Dog). Low-poly body built
## from boxes, with legs that swing as it moves. Wild animals graze and
## wander, and bolt when they see or hear you (crouch and approach slowly).
## Shoot or hit one, then butcher it with a knife for meat, a hide or
## feathers.
##
## Animals move along the terrain without physics (cheap) and sit on the
## zombie collision layer, so the same shots and swings that hit zombies hit
## them.

const KINDS := {
	"deer": {"name": "Deer", "hp": 70.0, "walk": 1.2, "run": 9.0, "sight": 32.0, "hear": 1.0, "size": Vector3(0.45, 1.3, 1.5),
		"col": Color(0.55, 0.38, 0.22), "meat": 6, "hide": 1, "feathers": 0},
	"rabbit": {"name": "Rabbit", "hp": 12.0, "walk": 0.8, "run": 7.0, "sight": 13.0, "hear": 0.6, "size": Vector3(0.2, 0.3, 0.38),
		"col": Color(0.55, 0.5, 0.42), "meat": 2, "hide": 0, "feathers": 0},
	"turkey": {"name": "Wild Turkey", "hp": 18.0, "walk": 0.9, "run": 5.5, "sight": 17.0, "hear": 0.8, "size": Vector3(0.3, 0.75, 0.6),
		"col": Color(0.3, 0.24, 0.18), "meat": 3, "hide": 0, "feathers": 12},
	"dog": {"name": "Dog", "hp": 80.0, "walk": 1.5, "run": 7.5, "sight": 0.0, "hear": 0.0, "size": Vector3(0.3, 0.7, 0.9),
		"col": Color(0.42, 0.3, 0.2), "meat": 0, "hide": 0, "feathers": 0},
}

enum State { GRAZE, WANDER, FLEE, DEAD }

var kind := "deer"
var def: Dictionary
var state := State.GRAZE
var health := 50.0
var gen: WorldGen
var target := Vector3.ZERO
var butchered := false

var _think := 0.0
var _flee_from := Vector3.ZERO
var _flee_t := 0.0
var _legs: Array[Node3D] = []
var _head: Node3D
var _model: Node3D
var _gait := 0.0
var _speed := 0.0
var dead_t := 0.0
var _parts := {} # Part node -> MeshData (merged into one mesh per part: few draw calls).


func setup(k: String, pos: Vector3, g: WorldGen) -> void:
	kind = k
	def = KINDS[k]
	gen = g
	health = float(def.hp)
	collision_layer = 4
	collision_mask = 0
	var s: Vector3 = def.size
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(s.x, 0.25), s.y * 0.7, s.z)
	cs.shape = box
	cs.position.y = s.y * 0.55
	add_child(cs)
	_build_model()
	position = pos
	rotation.y = randf() * TAU
	target = pos


## Boxes for the body, head and four legs (two for the turkey), each leg on
## its own pivot so it can swing.
func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	var s: Vector3 = def.size
	var col: Color = def.col
	var leg_h := s.y * (0.5 if kind != "rabbit" else 0.3)
	var body_h := s.y * (0.35 if kind != "turkey" else 0.45)
	_box(_model, Vector3(0, leg_h + body_h * 0.5, 0), Vector3(s.x, body_h, s.z * 0.75), col)
	_head = Node3D.new()
	_head.position = Vector3(0, leg_h + body_h * 0.9, s.z * 0.42)
	_model.add_child(_head)
	match kind:
		"deer":
			_box(_head, Vector3(0, 0.25, 0.05), Vector3(0.12, 0.45, 0.14), col) # neck
			_box(_head, Vector3(0, 0.5, 0.15), Vector3(0.15, 0.16, 0.28), col.darkened(0.05))
			_box(_head, Vector3(0, 0.46, 0.3), Vector3(0.08, 0.08, 0.06), Color(0.1, 0.08, 0.07))
			for x: float in [-0.08, 0.08]:
				_box(_head, Vector3(x, 0.68, 0.08), Vector3(0.03, 0.22, 0.03), Color(0.75, 0.68, 0.55)) # antlers
			_box(_model, Vector3(0, leg_h + body_h * 0.8, -s.z * 0.38), Vector3(0.08, 0.12, 0.05), Color(0.95, 0.93, 0.9)) # tail
		"rabbit":
			_box(_head, Vector3(0, 0.05, 0.02), Vector3(0.12, 0.12, 0.13), col)
			for x: float in [-0.03, 0.03]:
				_box(_head, Vector3(x, 0.17, -0.01), Vector3(0.025, 0.14, 0.04), col.lightened(0.1))
			_box(_model, Vector3(0, leg_h + body_h * 0.6, -s.z * 0.4), Vector3(0.07, 0.07, 0.06), Color(0.95, 0.95, 0.95))
		"turkey":
			_box(_head, Vector3(0, 0.15, 0.05), Vector3(0.06, 0.3, 0.06), Color(0.55, 0.4, 0.38))
			_box(_head, Vector3(0, 0.3, 0.08), Vector3(0.07, 0.07, 0.1), Color(0.75, 0.25, 0.2))
			_box(_model, Vector3(0, leg_h + body_h * 0.9, -s.z * 0.42), Vector3(0.45, 0.4, 0.06), col.lightened(0.15)) # fan
		"dog":
			_box(_head, Vector3(0, 0.12, 0.08), Vector3(0.18, 0.18, 0.2), col)
			_box(_head, Vector3(0, 0.08, 0.22), Vector3(0.1, 0.09, 0.12), col.darkened(0.15))
			for x: float in [-0.07, 0.07]:
				_box(_head, Vector3(x, 0.24, 0.02), Vector3(0.05, 0.08, 0.04), col.darkened(0.25))
			_box(_model, Vector3(0, leg_h + body_h * 0.9, -s.z * 0.42), Vector3(0.05, 0.05, 0.22), col)
	var legs := 2 if kind == "turkey" else 4
	for k in legs:
		var pivot := Node3D.new()
		var lx := (s.x * 0.35) * (1.0 if k % 2 == 0 else -1.0)
		var lz := 0.0 if legs == 2 else (s.z * 0.28 if k < 2 else -s.z * 0.28)
		pivot.position = Vector3(lx, leg_h, lz)
		_model.add_child(pivot)
		_box(pivot, Vector3(0, -leg_h * 0.5, 0), Vector3(maxf(0.035, s.x * 0.16), leg_h, maxf(0.035, s.x * 0.16)),
			col.darkened(0.15) if kind != "turkey" else Color(0.6, 0.45, 0.3))
		_legs.append(pivot)
	for node: Node3D in _parts:
		var mi := MeshInstance3D.new()
		mi.mesh = (_parts[node] as MeshData).to_mesh(Assets.material)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 120.0
		node.add_child(mi)
	_parts.clear()


func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> void:
	if not _parts.has(parent):
		_parts[parent] = MeshData.new()
	(_parts[parent] as MeshData).box(Transform3D(Basis.IDENTITY, pos), size, col, false)


func alive() -> bool:
	return state != State.DEAD


## Hit by a shot, arrow or swing.
func take_damage(amount: float, from: Vector3) -> void:
	if not alive():
		return
	health -= amount
	if Effects.current:
		Effects.current.blood(global_position + Vector3(0, float(def.size.y) * 0.6, 0), (global_position - from).normalized())
	if health <= 0.0:
		_die()
	else:
		scare(from)


func _die() -> void:
	state = State.DEAD
	collision_layer = WindowBody.SMASHED_LAYER # Still seen by interaction rays (butchering).
	_model.rotation.z = PI * 0.5
	_model.position.y = float(def.size.x) * 0.5
	for l in _legs:
		l.rotation.x = 0.0


## Something frightening at `from`: run the other way.
func scare(from: Vector3) -> void:
	if not alive() or kind == "dog":
		return
	state = State.FLEE
	_flee_from = from
	_flee_t = randf_range(6.0, 10.0)


## Heard a noise (from GameState.noise_made).
func hear(pos: Vector3, radius: float) -> void:
	if alive() and kind != "dog" and pos.distance_to(global_position) < radius * float(def.hear) * 1.6:
		scare(pos)


func _physics_process(dt: float) -> void:
	if not alive():
		dead_t += dt
		return
	update(dt)


## Grazing, wandering and fleeing. Dogs override this.
func update(dt: float) -> void:
	_think -= dt
	var speed := 0.0
	match state:
		State.GRAZE:
			if _think <= 0.0:
				_think = randf_range(3.0, 8.0)
				state = State.WANDER
				target = global_position + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		State.WANDER:
			speed = float(def.walk)
			if _think <= 0.0 or _flat(target) < 0.6:
				_think = randf_range(2.0, 6.0)
				state = State.GRAZE
		State.FLEE:
			speed = float(def.run)
			_flee_t -= dt
			var away := global_position - _flee_from
			away.y = 0.0
			target = global_position + away.normalized() * 10.0
			if _flee_t <= 0.0:
				state = State.GRAZE
				_think = 2.0
	move(target, speed, dt)


func _flat(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## Steps toward `to` on the terrain (turning back from deep water).
func move(to: Vector3, speed: float, dt: float) -> void:
	var dir := to - global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		speed = 0.0
	dir = dir.normalized()
	var next := global_position + dir * speed * dt
	if speed > 0.0 and gen and gen.water_level(next.x, next.z) > gen.height(next.x, next.z) + 0.3:
		if state == State.FLEE:
			_flee_from = next # Turn along the shore instead.
		target = global_position - dir * 5.0
		speed = 0.0
	if speed > 0.0:
		global_position = next
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, dt * 8.0))
	if gen:
		global_position.y = ground_y(global_position)
	_speed = speed
	_animate(dt, speed)


## Ground height under a point: the terrain, or a floor / roof if it's on one.
func ground_y(p: Vector3) -> float:
	return gen.height(p.x, p.z) if gen else p.y


func _animate(dt: float, speed: float) -> void:
	_gait += dt * (4.0 + speed * 2.2)
	var amp := clampf(speed / maxf(float(def.run), 0.1), 0.0, 1.0) * 0.8 if speed > 0.05 else 0.0
	for k in _legs.size():
		var phase := 0.0 if k % 2 == (0 if k < 2 else 1) else PI
		_legs[k].rotation.x = sin(_gait + phase) * amp
	if _head:
		# Head down while grazing.
		var down := 0.6 if state == State.GRAZE and kind == "deer" else 0.0
		_head.rotation.x = lerpf(_head.rotation.x, down, minf(1.0, dt * 3.0))
	if kind == "rabbit" and speed > 0.5:
		_model.position.y = absf(sin(_gait * 0.5)) * 0.15


## A knife turns a carcass into meat (and a hide or feathers).
func butcher(drop_pos: Vector3) -> Array:
	butchered = true
	var out := []
	var skill := GameState.character.skill("foraging")
	if int(def.meat) > 0:
		out.append(ItemDB.make("raw_meat", int(def.meat) + skill / 3))
	if int(def.hide) > 0:
		out.append(ItemDB.make("animal_hide", int(def.hide)))
	if int(def.feathers) > 0:
		out.append(ItemDB.make("feathers", int(def.feathers)))
	for it in out:
		GameState.add_item(it, drop_pos)
	return out
