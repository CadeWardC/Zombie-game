class_name WindowBody
extends StaticBody3D
## A ground-floor window pane. Drawn by its chunk's MultiMesh; this body
## blocks the opening until the glass is smashed (by a swing or a zombie).
## A smashed window stays open for good: zombies crawl in through it and
## survivors can climb through (interact). Saved in GameState.ws.

const SMASHED_LAYER := 8 # Not in anyone's movement mask; interaction rays see it.

## Loaded windows by id (for changes arriving from other players).
static var by_id := {}

var id := ""
var smashed := false
var size := Vector2.ONE
var _mm: MultiMesh
var _index := 0


func setup(d: Dictionary, mm: MultiMesh, index: int) -> void:
	transform = d.xf
	size = Vector2(d.w, d.h)
	id = str(d.id)
	by_id[id] = self
	tree_exiting.connect(func() -> void:
		if by_id.get(id) == self:
			by_id.erase(id))
	_mm = mm
	_index = index
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.12)
	cs.shape = shape
	add_child(cs)
	mm.set_instance_transform(index, transform * Transform3D(Basis.from_scale(Vector3(size.x, size.y, 1.0)), Vector3.ZERO))
	if GameState.window_smashed(id):
		_set_smashed()


func smash() -> void:
	if smashed:
		return
	GameState.smash_window(id)
	GameState.make_noise(global_position, 28.0)
	if Effects.current:
		Effects.current.burst(global_position, global_basis.z, Color(0.7, 0.8, 0.85), 22, 3.0)
		Effects.current.burst(global_position, -global_basis.z, Color(0.7, 0.8, 0.85), 14, 2.0)
	_set_smashed()


## Another player smashed it.
func smash_quiet() -> void:
	if smashed:
		return
	if Effects.current:
		Effects.current.burst(global_position, global_basis.z, Color(0.7, 0.8, 0.85), 16, 3.0)
	_set_smashed()


func _set_smashed() -> void:
	smashed = true
	collision_layer = SMASHED_LAYER
	_mm.set_instance_transform(_index, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), transform.origin))
