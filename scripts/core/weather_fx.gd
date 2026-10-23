class_name WeatherFX
extends Node3D
## What the weather looks like: rain and snow falling around the camera,
## lightning in storms, and (via fog_factor / sky_tint, read by main.gd)
## heavier fog and a darker sky. Cheap CPU particles so it runs on low-end
## tablets.

var camera: Camera3D
var _rain: CPUParticles3D
var _snow: CPUParticles3D
var _flash := 0.0
var _flash_t := 8.0
var _thunder_at := -1.0
var _thunder_pos := Vector3.ZERO
## Read by main.gd each frame.
var fog_factor := 1.0
var sky_tint := Color.WHITE
var lightning := 0.0


func _ready() -> void:
	_rain = _particles(Color(0.7, 0.75, 0.85, 0.55), Vector3(0.012, 0.45, 0.012), Vector3(0, -24.0, 0), 700)
	_snow = _particles(Color(0.95, 0.95, 1.0, 0.9), Vector3(0.05, 0.05, 0.05), Vector3(0, -1.6, 0), 600)
	_snow.direction = Vector3(0.3, -1, 0.1)
	_snow.spread = 25.0
	_snow.initial_velocity_min = 0.6
	_snow.initial_velocity_max = 1.4
	_snow.lifetime = 6.0


func _particles(col: Color, size: Vector3, gravity: Vector3, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mesh.material = mat
	p.mesh = mesh
	p.amount = amount
	p.lifetime = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14, 0.5, 14)
	p.gravity = gravity
	p.direction = Vector3.DOWN
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.local_coords = false
	p.emitting = false
	add_child(p)
	return p


## `sheltered`: under a roof (no rain falling on the camera).
func update(delta: float, sheltered: bool) -> void:
	if camera == null:
		return
	var k := Weather.kind()
	var i := Weather.intensity()
	var at := camera.global_position + Vector3(0, 9.0, 0) - camera.global_basis.z * 4.0
	_rain.global_position = at
	_snow.global_position = at
	var raining := (k == "rain" or k == "storm") and not sheltered
	_rain.emitting = raining
	_snow.emitting = k == "snow" and not sheltered
	match k:
		"fog":
			fog_factor = lerpf(0.45, 0.2, i)
			sky_tint = Color(0.85, 0.87, 0.88)
		"rain":
			fog_factor = lerpf(0.8, 0.55, i)
			sky_tint = Color(0.72, 0.74, 0.78)
		"storm":
			fog_factor = 0.5
			sky_tint = Color(0.5, 0.52, 0.58)
		"snow":
			fog_factor = lerpf(0.75, 0.45, i)
			sky_tint = Color(0.9, 0.92, 0.95)
		"cloudy":
			fog_factor = 0.9
			sky_tint = Color(0.82, 0.83, 0.85)
		_:
			fog_factor = 1.0
			sky_tint = Color.WHITE
	# Lightning, then thunder a moment later (zombies hear it too, but it
	# tells them nothing about where you are).
	_flash = maxf(0.0, _flash - delta * 6.0)
	if k == "storm":
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash_t = randf_range(6.0, 20.0)
			_flash = 1.0
			_thunder_at = randf_range(0.5, 2.5)
			_thunder_pos = camera.global_position + Vector3(randf_range(-300, 300), 0, randf_range(-300, 300))
	if _thunder_at > 0.0:
		_thunder_at -= delta
		if _thunder_at <= 0.0:
			GameState.notify("*thunder*")
	lightning = _flash
