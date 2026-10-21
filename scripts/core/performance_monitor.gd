class_name PerformanceMonitor
extends Node
## Dynamic resolution: renders the 3D world at a lower resolution when the
## frame rate drops below target and raises it back when there's headroom.
## The HUD stays at full resolution, so text remains sharp.

const STEP := 0.05
const CHECK_INTERVAL := 1.0

var target_fps := 60
var min_scale := 0.6
var _scale := 1.0
var _timer := 0.0
var _good_checks := 0


func configure(fps: int, min_render_scale: float) -> void:
	target_fps = fps
	min_scale = min_render_scale
	Engine.max_fps = fps
	_scale = clampf(_scale, min_scale, 1.0)
	_apply()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	var fps := Engine.get_frames_per_second()
	if fps < target_fps * 0.9 and _scale > min_scale:
		_scale = maxf(min_scale, _scale - STEP)
		_good_checks = 0
		_apply()
	elif fps >= target_fps - 2:
		_good_checks += 1
		# Wait a few seconds of stable frame rate before stepping back up,
		# so the resolution doesn't oscillate.
		if _good_checks >= 4 and _scale < 1.0:
			_scale = minf(1.0, _scale + STEP)
			_good_checks = 0
			_apply()


func _apply() -> void:
	get_viewport().scaling_3d_scale = _scale
