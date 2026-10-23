class_name DoorBody
extends StaticBody3D
## A hinged door. Drawn by its chunk's MultiMesh; this body handles
## collision, opening, locking and breaking. State is saved in GameState.ws.
##
## - Unlocked doors open for anyone, zombies included.
## - Survivors lock and unlock doors from the inside (hold interact); some
##   outside doors start locked. Locked doors can be battered down: by you
##   with a melee weapon, or by zombies that know you're inside (very slowly,
##   unless it's a brute).
## - Security doors (research labs) open with a keycard, and only while the
##   site's generator is running. They can't be broken.
## - Barricades (planks nailed across from the inside) hold a closed door
##   shut: nobody opens it until they're pried off or battered apart.

const OPEN_ANGLE := deg_to_rad(100.0)
const MAX_HP := 100.0
const BAR_HP := 260.0

## Loaded doors by id (for changes arriving from other players).
static var by_id := {}

var id := ""
var is_open := false
var locked := false
var hp := MAX_HP
var bar := 0.0 # Barricade hp (0: none).
var _bar_mesh: MeshInstance3D
var key := "" # Keycard item id for security doors.
var power := "" # Site whose generator powers the keycard reader.
var out := 0 # +1 / -1: which local Z side is outdoors (0: an inside door).
var _closed_xf: Transform3D
var _size: Vector3
var _mm: MultiMesh
var _index := 0
var _angle := 0.0
var _target := 0.0
var _swing := 1.0
var _shake_t := 0.0


func setup(d: Dictionary, mm: MultiMesh, index: int) -> void:
	_closed_xf = d.xf
	_size = Vector3(d.w, d.h, d.t)
	_mm = mm
	_index = index
	id = str(d.get("id", ""))
	by_id[id] = self
	tree_exiting.connect(func() -> void:
		if by_id.get(id) == self:
			by_id.erase(id))
	key = str(d.get("key", ""))
	power = str(d.get("power", ""))
	out = int(d.get("out", 0))
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = _size
	cs.shape = shape
	cs.position = Vector3(_size.x * 0.5, _size.y * 0.5, 0)
	add_child(cs)
	mm.set_instance_color(index, d.color)
	# Security doors start locked; so do about a quarter of outside doors.
	locked = key != "" or (out != 0 and absi(id.hash()) % 100 < 25)
	var st := GameState.door_state(id)
	if not st.is_empty():
		is_open = bool(st.get("o", false))
		locked = bool(st.get("l", locked))
		hp = float(st.get("hp", MAX_HP))
		bar = float(st.get("bar", 0.0))
	if is_open:
		_target = OPEN_ANGLE
		_angle = _target
	if hp <= 0.0:
		_break_apart()
	_apply()
	_update_bar()
	set_process(false)


func barricaded() -> bool:
	return bar > 0.0


## Can a barricade go up (or come down) from here? Only from the inside of
## a closed, unbroken, ordinary door.
func can_barricade(from: Vector3) -> bool:
	return key == "" and not broken() and not is_open and inside(from)


func barricade(carpentry: int) -> void:
	bar = BAR_HP * (1.0 + carpentry * 0.1)
	GameState.make_noise(global_position, 15.0)
	_save()
	_update_bar()


func remove_barricade() -> void:
	bar = 0.0
	_save()
	_update_bar()


func _update_bar() -> void:
	if barricaded() and _bar_mesh == null:
		_bar_mesh = MeshInstance3D.new()
		var m := MeshData.new()
		var col := Color(0.5, 0.36, 0.22)
		for k in 3:
			var y := _size.y * (0.25 + k * 0.25)
			for z: float in [_size.z * 0.5 + 0.03, -_size.z * 0.5 - 0.03]:
				m.box(Transform3D(Basis(Vector3.FORWARD, 0.1 * (1 - k)), Vector3(_size.x * 0.5, y, z)), Vector3(_size.x + 0.4, 0.16, 0.035), col.darkened(0.05 * k), false)
		_bar_mesh.mesh = m.to_mesh(Assets.material)
		get_parent().add_child.call_deferred(_bar_mesh)
		_bar_mesh.transform = _closed_xf
	if _bar_mesh:
		_bar_mesh.visible = barricaded()


func broken() -> bool:
	return hp <= 0.0


## `from` (a world position) in the closed door's frame.
func _local(from: Vector3) -> Vector3:
	var parent := get_parent() as Node3D
	var xf := parent.global_transform * _closed_xf if parent else _closed_xf
	return xf.affine_inverse() * from


## Is `from` on the inside of this door (where the lock is)?
func inside(from: Vector3) -> bool:
	if out == 0:
		return true
	var local := _local(from)
	return signf(local.z) != float(out)


func can_lock(from: Vector3) -> bool:
	return key == "" and not broken() and not is_open and inside(from)


func prompt(from: Vector3) -> String:
	if broken():
		return ""
	if key != "" and locked:
		if not GameState.has_power(power):
			return "Security door (no power)"
		if GameState.item_count(key) <= 0:
			return "Needs a %s" % ItemDB.item_name(key)
		return "Swipe %s" % ItemDB.item_name(key)
	if barricaded():
		return "Barricaded"
	if locked:
		return "Unlock and open" if inside(from) else "Locked"
	return "Close door" if is_open else "Open door"


func interact(from: Vector3) -> void:
	if broken():
		return
	if key != "" and locked:
		if not GameState.has_power(power):
			GameState.notify("The keycard reader is dead. The site needs power.")
		elif GameState.item_count(key) <= 0:
			GameState.notify("You need a %s" % ItemDB.item_name(key))
		else:
			locked = false
			GameState.notify("Access granted")
			_open_from(from)
		return
	if barricaded():
		GameState.notify("It's barricaded" + (". Pry the boards off to open it." if inside(from) else "."))
		_shake_t = 0.25
		set_process(true)
		return
	if locked:
		if inside(from):
			locked = false
			_open_from(from)
		else:
			GameState.notify("It's locked. Break it down, or find another way in.")
			GameState.make_noise(global_position, 5.0)
			_shake_t = 0.25
			set_process(true)
		return
	if is_open:
		is_open = false
		_target = 0.0
		set_process(true)
		_save()
	else:
		_open_from(from)
	GameState.make_noise(global_position, 4.0)


func toggle_lock(from: Vector3) -> void:
	if not can_lock(from):
		return
	locked = not locked
	GameState.notify("Door locked" if locked else "Door unlocked")
	GameState.make_noise(global_position, 2.0)
	_save()


## Opens away from `from`.
func _open_from(from: Vector3) -> void:
	var local := _local(from)
	_swing = -1.0 if local.z > 0.0 else 1.0
	is_open = true
	_target = OPEN_ANGLE * _swing
	set_process(true)
	_save()


## A zombie walks into the door: unlocked doors swing open. Returns true if
## the way is clear.
func zombie_push(from: Vector3) -> bool:
	if broken() or is_open:
		return true
	if locked or barricaded():
		return false
	_open_from(from)
	GameState.make_noise(global_position, 3.0)
	return true


## Battering the door (melee or zombies). Security doors don't budge.
func damage(amount: float, _from: Vector3) -> void:
	if broken() or is_open:
		return
	if key != "":
		GameState.notify("The steel door doesn't budge")
		return
	if barricaded():
		bar = maxf(0.0, bar - amount * 2.0)
		_shake_t = 0.2
		set_process(true)
		GameState.make_noise(global_position, 22.0)
		_update_bar()
		_save()
		return
	hp -= amount
	_shake_t = 0.2
	set_process(true)
	GameState.make_noise(global_position, 22.0)
	if hp <= 0.0:
		hp = 0.0
		locked = false
		is_open = true
		_break_apart()
		GameState.make_noise(global_position, 35.0)
	_save()


func _break_apart() -> void:
	collision_layer = 0
	_mm.set_instance_transform(_index, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), _closed_xf.origin))
	set_process(false)


func _save() -> void:
	GameState.set_door_state(id, {"o": is_open, "l": locked, "hp": hp, "bar": bar})


## Another player changed this door.
func apply_state(st: Dictionary) -> void:
	if broken():
		return
	locked = bool(st.get("l", locked))
	hp = float(st.get("hp", hp))
	bar = float(st.get("bar", bar))
	_update_bar()
	var open := bool(st.get("o", is_open))
	if hp <= 0.0:
		is_open = true
		_break_apart()
		return
	if open != is_open:
		is_open = open
		_target = OPEN_ANGLE * _swing if open else 0.0
		set_process(true)


func _process(delta: float) -> void:
	_angle = move_toward(_angle, _target, delta * 4.0)
	_shake_t = maxf(0.0, _shake_t - delta)
	_apply()
	if is_equal_approx(_angle, _target) and _shake_t <= 0.0:
		set_process(false)


func _apply() -> void:
	if broken():
		return
	var jiggle := sin(_shake_t * 90.0) * 0.03 if _shake_t > 0.0 else 0.0
	var xf := _closed_xf * Transform3D(Basis(Vector3.UP, _angle + jiggle), Vector3.ZERO)
	transform = xf
	_mm.set_instance_transform(_index, xf * Transform3D(Basis.from_scale(_size), Vector3(0, 0, 0)))
