class_name BuildMode
extends RefCounted
## Placing a structure: a see-through preview follows where you look (green
## where it fits, red where it doesn't), snaps to a grid, and rotates in 45°
## steps. Attack places it (taking the materials), the second action button
## rotates, Use cancels.

const MAX_DIST := 6.0

var p: Player
var type := ""
var ghost: MeshInstance3D
var _rot := 0.0
var _ok := false
var _why := ""
var _xf := Transform3D.IDENTITY
var _mat: StandardMaterial3D


func _init(player: Player) -> void:
	p = player
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = false
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func active() -> bool:
	return type != ""


func start(t: String) -> void:
	stop()
	type = t
	ghost = MeshInstance3D.new()
	ghost.mesh = Assets.structure_meshes[t]
	ghost.material_override = _mat
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.get_parent().add_child(ghost)
	_rot = 0.0
	GameState.notify("Place the %s" % str(Structures.get_def(t).name).to_lower())


func stop() -> void:
	type = ""
	if ghost and is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null


## Every frame: move the preview, read place / rotate / cancel.
func update(_delta: float) -> void:
	if not active():
		return
	var d := Structures.get_def(type)
	var s: Vector3 = d.size
	var cam := p.camera
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	var space := p.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + fwd * MAX_DIST, 1, [p.get_rid()]))
	var pos: Vector3
	if not hit.is_empty() and (hit.normal as Vector3).y > 0.6:
		pos = hit.position
	else:
		var flat := Vector3(fwd.x, 0, fwd.z).normalized()
		pos = p.global_position + flat * (2.0 + s.z * 0.5)
		pos.y = p.gen.height(pos.x, pos.z) if p.gen else p.global_position.y
		# On a floor (inside a building): drop onto it.
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.5, 0), pos - Vector3(0, 3.0, 0), 1, [p.get_rid()]))
		if not down.is_empty():
			pos.y = down.position.y
	var snap: float = d.snap
	pos.x = snappedf(pos.x, snap)
	pos.z = snappedf(pos.z, snap)
	var yaw := snappedf(p.rotation.y, PI * 0.5) + PI + _rot
	_xf = Transform3D(Basis(Vector3.UP, yaw), pos)
	_check(d, space)
	ghost.global_transform = _xf
	_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if _ok else Color(1.0, 0.3, 0.25, 0.45)
	p.prompt = ("Place " + str(d.name)) if _ok else _why
	p.prompt_action = "attack"
	p.alt_prompt = "Rotate"
	p.hold_prompt = ""
	if GameState.ui_open:
		return
	if Input.is_action_just_pressed("reload"):
		_rot += PI * 0.25
	elif Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("pause"):
		stop()
		GameState.notify("Building cancelled")
	elif Input.is_action_just_pressed("attack") and _ok:
		place()


## Does it fit here? Sets _ok and _why.
func _check(d: Dictionary, space: PhysicsDirectSpaceState3D) -> void:
	_ok = false
	var s: Vector3 = d.size
	var pos := _xf.origin
	if pos.distance_to(p.global_position) > MAX_DIST + 1.0:
		_why = "Too far away"
		return
	if p.gen and p.gen.water_level(pos.x, pos.z) > pos.y - 0.2:
		_why = "Can't build in water"
		return
	if not Structures.missing(d).is_empty():
		_why = "Need: " + ", ".join(Structures.missing(d))
		return
	# Uneven ground: compare the corners.
	var lo := INF
	var hi := -INF
	for c: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		var w := _xf * Vector3(c.x * s.x * 0.5, 0, c.z * s.z * 0.5)
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(w + Vector3(0, 1.0, 0), w - Vector3(0, 2.0, 0), 1, [p.get_rid()]))
		var y: float = down.position.y if not down.is_empty() else (p.gen.height(w.x, w.z) if p.gen else pos.y)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	if hi - lo > 0.7:
		_why = "The ground is too uneven"
		return
	# Something in the way (a wall, a car, another structure, a person).
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(s.x * 0.92, maxf(0.1, s.y - (hi - pos.y) - 0.15), s.z * 0.92)
	q.shape = box
	q.transform = Transform3D(_xf.basis, pos + Vector3(0, (hi - pos.y) + 0.1 + box.size.y * 0.5, 0))
	q.collision_mask = 1 | 2 | 4
	q.exclude = [p.get_rid()]
	if not space.intersect_shape(q, 1).is_empty():
		_why = "Something's in the way"
		return
	if not d.get("inside", false):
		var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, 12.0, 0), 1, [p.get_rid()]))
		if not up.is_empty():
			_why = "Build this outdoors"
			return
	_ok = true
	_why = ""


func place() -> void:
	if not Structures.pay(type):
		return
	p.bases.add(type, _xf.origin, _xf.basis.get_euler().y)
	var d := Structures.get_def(type)
	GameState.practice(str(d.get("skill", "carpentry")), float(d.xp))
	GameState.make_noise(_xf.origin, 14.0)
	GameState.notify("Built a %s" % str(d.name).to_lower())
	# Keep building the same thing while there's material for it.
	if not Structures.missing(d).is_empty():
		stop()
