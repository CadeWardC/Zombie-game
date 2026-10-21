class_name DoorBody
extends StaticBody3D
## A hinged door. Drawn by its chunk's MultiMesh; this body handles
## collision and opening. Zombies can push open unlocked doors (later stage).

const OPEN_ANGLE := deg_to_rad(100.0)

var is_open := false
var _closed_xf: Transform3D
var _size: Vector3
var _mm: MultiMesh
var _index := 0
var _angle := 0.0
var _target := 0.0
var _swing := 1.0


func setup(d: Dictionary, mm: MultiMesh, index: int) -> void:
	_closed_xf = d.xf
	_size = Vector3(d.w, d.h, d.t)
	_mm = mm
	_index = index
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = _size
	cs.shape = shape
	cs.position = Vector3(_size.x * 0.5, _size.y * 0.5, 0)
	add_child(cs)
	mm.set_instance_color(index, d.color)
	_apply()
	set_process(false)


## Opens away from the player.
func interact(from: Vector3) -> void:
	if not is_open:
		var local := _closed_xf.affine_inverse() * from
		_swing = -1.0 if local.z > 0.0 else 1.0
	is_open = not is_open
	_target = OPEN_ANGLE * _swing if is_open else 0.0
	set_process(true)


func _process(delta: float) -> void:
	_angle = move_toward(_angle, _target, delta * 4.0)
	_apply()
	if is_equal_approx(_angle, _target):
		set_process(false)


func _apply() -> void:
	var xf := _closed_xf * Transform3D(Basis(Vector3.UP, _angle), Vector3.ZERO)
	transform = xf
	_mm.set_instance_transform(_index, xf * Transform3D(Basis.from_scale(_size), Vector3(0, 0, 0)))
