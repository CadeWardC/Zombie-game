class_name StructureBody
extends StaticBody3D
## A built structure in the world (a wall, a crate, a campfire...). Its state
## is the record in GameState.ws.structures; this node draws it, collides,
## and takes damage. Zombies that get stuck against one batter it.

const INTERACT_LAYER := 8 # Non-solid structures: seen by interaction rays only.

var rec: Dictionary
var def: Dictionary
var t := ""
var _mesh: MeshInstance3D
var _crop: MeshInstance3D
var _crop_key := ""
var _flame: MeshInstance3D
var _light: OmniLight3D
var _shake_t := 0.0
var _water: MeshInstance3D


func setup(r: Dictionary) -> void:
	rec = r
	t = str(r.t)
	def = Structures.get_def(t)
	name = "Structure_%s" % r.id
	var p: Array = r.p
	position = Vector3(p[0], p[1], p[2])
	rotation.y = float(r.yaw)
	collision_layer = 1 if def.solid else INTERACT_LAYER
	collision_mask = 0
	_mesh = MeshInstance3D.new()
	_mesh.mesh = Assets.structure_meshes[t]
	add_child(_mesh)
	var s: Vector3 = def.size
	if t == "watchtower":
		# Legs, the platform and its railing; the space under it stays open.
		for x: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				_box(Vector3(x * (s.x * 0.5 - 0.15), s.y * 0.5, z * (s.z * 0.5 - 0.15)), Vector3(0.25, s.y, 0.25))
		_box(Vector3(0, 3.0, 0), Vector3(s.x, 0.14, s.z))
		_box(Vector3(0, 3.5, -s.z * 0.5 + 0.05), Vector3(s.x, 1.0, 0.1))
		_box(Vector3(s.x * 0.5 - 0.05, 3.5, 0), Vector3(0.1, 1.0, s.z))
		_box(Vector3(-s.x * 0.5 + 0.05, 3.5, 0), Vector3(0.1, 1.0, s.z))
	else:
		_box(Vector3(0, s.y * 0.5, 0), s)
	if t == "campfire":
		_flame = MeshInstance3D.new()
		_flame.mesh = Assets.flame_mesh
		_flame.position.y = 0.25
		_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_flame)
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.6, 0.3)
		_light.omni_range = 9.0
		_light.light_energy = 1.6
		_light.position.y = 0.6
		add_child(_light)
	if t == "rain_collector":
		_water = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 0.02
		cyl.radial_segments = 10
		_water.mesh = cyl
		_water.material_override = Assets.water_material
		add_child(_water)
	refresh()


func _box(pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	add_child(cs)


## Redraws from the record (lit fire, crop growth, gate open, water level).
func refresh() -> void:
	if _flame:
		var lit := burning()
		_flame.visible = lit
		_light.visible = lit
	if t == "gate":
		var open := bool(rec.get("open", false))
		var hinge := Vector3(-float(def.size.x) * 0.5, 0, 0)
		var xf := Transform3D(Basis(Vector3.UP, -PI * 0.5 if open else 0.0), Vector3.ZERO)
		xf.origin = hinge - xf.basis * hinge
		_mesh.transform = xf
		for c in get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, float(def.size.y) * 0.5, 0))
	if _water:
		var l := float(rec.get("water", 0.0)) / Structures.COLLECTOR_L
		_water.visible = l > 0.02
		_water.position.y = 0.05 + l * 0.8
	if t == "farm_plot":
		var c: Dictionary = rec.get("crop", {})
		var key := "" if c.is_empty() else "%s_%d" % [c.k, int(Farming.growth(c) * 4.0)]
		if key != _crop_key:
			_crop_key = key
			if _crop:
				_crop.queue_free()
				_crop = null
			if not c.is_empty():
				_crop = MeshInstance3D.new()
				_crop.mesh = StructureModels.crop(str(c.k), minf(1.0, floorf(Farming.growth(c) * 4.0) / 4.0)).to_mesh(Assets.material)
				_crop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(_crop)


func burning() -> bool:
	return t == "campfire" and float(rec.get("lit", 0.0)) > GameState.hours()


func damaged() -> bool:
	return float(rec.hp) < float(rec.get("mhp", def.hp)) * 0.95


## Hit by a zombie (or a blast). Returns true if it broke.
func damage(amount: float) -> bool:
	rec.hp = float(rec.hp) - amount
	_shake_t = 0.2
	GameState.make_noise(global_position, 18.0)
	if Effects.current:
		Effects.current.burst(global_position + Vector3(0, 1.0, 0), Vector3.UP, Color(0.5, 0.36, 0.22), 6, 2.0)
	return float(rec.hp) <= 0.0


func _process(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		_mesh.position.x = sin(_shake_t * 80.0) * 0.03
	if _flame and _flame.visible:
		var f := 1.0 + sin(Time.get_ticks_msec() * 0.023) * 0.12 + sin(Time.get_ticks_msec() * 0.041) * 0.08
		_flame.scale = Vector3(1.0, f, 1.0)
		_light.light_energy = 1.4 + (f - 1.0) * 2.0
