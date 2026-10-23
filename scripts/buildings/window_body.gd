class_name WindowBody
extends StaticBody3D
## A ground-floor window pane. Drawn by its chunk's MultiMesh; this body
## blocks the opening until the glass is smashed (by a swing or a zombie).
## A smashed window stays open for good: zombies crawl in through it and
## survivors can climb through (interact). Saved in GameState.ws.
##
## Boarding a window up (planks, nails and a hammer) blocks it, smashed or
## not, until zombies batter the boards apart.

const SMASHED_LAYER := 8 # Not in anyone's movement mask; interaction rays see it.
const BOARD_HP := 160.0

## Loaded windows by id (for changes arriving from other players).
static var by_id := {}

var id := ""
var smashed := false
var boards := 0.0
var size := Vector2.ONE
var _boards_mesh: MeshInstance3D
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
	boards = GameState.window_boards(id)
	_update_boards()


func boarded() -> bool:
	return boards > 0.0


## Nails boards over it.
func board_up(carpentry: int) -> void:
	boards = BOARD_HP * (1.0 + carpentry * 0.1)
	GameState.set_window_boards(id, boards)
	GameState.make_noise(global_position, 15.0)
	_update_boards()


## Zombies (or a melee weapon) battering the boards. Returns true when they
## break.
func hit_boards(amount: float) -> bool:
	if not boarded():
		return false
	boards = maxf(0.0, boards - amount)
	GameState.make_noise(global_position, 20.0)
	if Effects.current:
		Effects.current.burst(global_position, global_basis.z, Color(0.5, 0.36, 0.22), 6, 2.0)
	GameState.set_window_boards(id, boards)
	_update_boards()
	return boards <= 0.0


## Pried off from the inside: the planks come back.
func remove_boards() -> void:
	boards = 0.0
	GameState.set_window_boards(id, 0.0)
	_update_boards()


## Another player changed the boards.
func apply_boards(hp: float) -> void:
	boards = hp
	_update_boards()


func _update_boards() -> void:
	if boarded() and _boards_mesh == null:
		_boards_mesh = MeshInstance3D.new()
		var m := MeshData.new()
		var col := Color(0.5, 0.36, 0.22)
		for k in 3:
			var y := (k - 1) * size.y * 0.32
			var rot := (0.12 if k % 2 == 0 else -0.1)
			for z: float in [0.09, -0.09]:
				m.box(Transform3D(Basis(Vector3.FORWARD, rot), Vector3(0, y, z)), Vector3(size.x + 0.25, 0.16, 0.035), col.darkened(0.06 * k), false)
		_boards_mesh.mesh = m.to_mesh(Assets.material)
		add_child(_boards_mesh)
	if _boards_mesh:
		_boards_mesh.visible = boarded()
	# Boards block the opening even after the glass is gone.
	collision_layer = 1 if boarded() or not smashed else SMASHED_LAYER


func smash() -> void:
	if boarded():
		hit_boards(25.0)
		return
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
	collision_layer = 1 if boarded() else SMASHED_LAYER
	_mm.set_instance_transform(_index, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), transform.origin))
