class_name Avatars
extends Node3D
## The other players' survivors, as seen on this device: a body wearing
## their clothes (paler as the infection takes them), a name tag, smooth
## movement between network updates and walk / run / crouch animations.
##
## On the host each avatar also stands in for its player as far as zombies
## are concerned (see RemoteAvatar): zombies see it, chase it and bite it,
## and the bites are sent to that player's device.

var _by_id := {} # peer id -> RemoteAvatar


func _ready() -> void:
	Net.player_left.connect(func(info: Dictionary) -> void: _remove(int(info.id)))


func avatar(id: int) -> RemoteAvatar:
	return _by_id.get(id)


## Living avatars (zombie targets on the host).
func targets() -> Array:
	var out := []
	for a: RemoteAvatar in _by_id.values():
		if a.ready_to_play() and not a.dead:
			out.append(a)
	return out


func all() -> Array:
	return _by_id.values()


func _remove(id: int) -> void:
	if _by_id.has(id):
		(_by_id[id] as Node).queue_free()
		_by_id.erase(id)


func flash(id: int, _pos: Vector3) -> void:
	var a := avatar(id)
	if a:
		a.flash()


func _process(delta: float) -> void:
	for id in Net.players:
		var info: Dictionary = Net.players[id]
		if info.state.is_empty():
			continue
		var a: RemoteAvatar = _by_id.get(id)
		if a == null:
			a = RemoteAvatar.new()
			a.peer = id
			add_child(a)
			a.global_position = info.state.p
			_by_id[id] = a
		a.update(info, delta)
	for id in _by_id.keys():
		if not Net.players.has(id):
			_remove(id)


class RemoteAvatar:
	extends AnimatableBody3D
	## Another player. Duck-types the parts of Player that zombies use.

	var peer := 0
	var dead := false
	var crouching := false
	var turned := false
	var player_name := ""
	var head := Node3D.new() # Eye height (zombie sight checks).
	var flashlight := Node3D.new() # .visible: their flashlight is on.
	var vis := 1.0
	## Setting this pushes the real player (brutes knock you back).
	var velocity: Vector3:
		get:
			return Vector3.ZERO
		set(v):
			if Net.is_host():
				Net.push_player(peer, v, 0.0)

	var _model: Node3D
	var _body: MeshInstance3D
	var _anim: AnimationPlayer
	var _label: Label3D
	var _light: SpotLight3D
	var _flash: OmniLight3D
	var _flash_t := 0.0
	var _look_key := ""
	var _target := Vector3.ZERO
	var _yaw := 0.0
	var _speed := 0.0

	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		sync_to_physics = false
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.8
		cs.shape = cap
		cs.position.y = 0.9
		add_child(cs)
		head.position.y = 1.65
		add_child(head)
		flashlight.visible = false
		add_child(flashlight)
		_model = ZombieModel.instantiate(0)
		add_child(_model)
		_body = _model.get_node("Skeleton3D/Body")
		_anim = _model.get_node("AnimationPlayer")
		_anim.play("h_idle")
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.position.y = 2.2
		_label.pixel_size = 0.004
		_label.font_size = 48
		_label.outline_size = 10
		_label.no_depth_test = true
		_label.fixed_size = false
		add_child(_label)
		_light = SpotLight3D.new()
		_light.spot_range = 22.0
		_light.spot_angle = 28.0
		_light.light_energy = 2.0
		_light.position = Vector3(0.2, 1.45, -0.2)
		_light.visible = false
		add_child(_light)
		_flash = OmniLight3D.new()
		_flash.light_color = Color(1.0, 0.8, 0.5)
		_flash.omni_range = 6.0
		_flash.position = Vector3(0.2, 1.4, -0.6)
		_flash.visible = false
		add_child(_flash)

	func ready_to_play() -> bool:
		return not Net.players.get(peer, {}).get("state", {}).is_empty()

	func visibility() -> float:
		return vis

	## Host: a zombie's attack lands on this player.
	func zombie_hit(dmg: float, from: Vector3, kind := "claw") -> void:
		if Net.is_host() and not dead:
			Net.hit_player(peer, dmg, from, kind)

	func grab(time: float, _msg := "") -> void:
		if Net.is_host():
			Net.push_player(peer, Vector3.ZERO, time)

	func flash() -> void:
		_flash.visible = true
		_flash_t = 0.06

	func update(info: Dictionary, delta: float) -> void:
		var st: Dictionary = info.state
		_target = st.p
		_yaw = st.yaw
		dead = st.dead
		turned = st.turned
		crouching = st.crouch
		vis = st.vis
		head.position.y = st.eye
		flashlight.visible = st.light
		_light.visible = st.light and not dead
		_speed = st.speed
		# Smoothly follow the reported position (it arrives ~15 times a second).
		var k := 1.0 - exp(-delta * 14.0)
		global_position = global_position.lerp(_target, k)
		if global_position.distance_to(_target) > 6.0:
			global_position = _target
		rotation.y = lerp_angle(rotation.y, _yaw, k)
		_light.rotation.x = st.pitch
		player_name = str(info.name)
		_label.text = player_name + (" (turned)" if turned else (" (down)" if dead else ""))
		_label.modulate = Color(1.0, 0.45, 0.4) if dead or st.sym > 0.4 else Color(0.95, 0.95, 0.9)
		_label.outline_modulate = Color(0, 0, 0, 0.8)
		# A turned body walks as a zombie (the host's zombie); hide this one.
		visible = not turned
		collision_layer = 0 if dead else 2
		_dress(info, float(st.sym))
		_animate(delta)
		if _flash_t > 0.0:
			_flash_t -= delta
			_flash.visible = _flash_t > 0.0

	func _dress(info: Dictionary, sym: float) -> void:
		var key := "%s|%s|%.2f" % [JSON.stringify(info.look), JSON.stringify(info.char.get("look", {})), sym]
		if key == _look_key:
			return
		_look_key = key
		var ch := Character.from_dict(info.char)
		var equip := {}
		for slot in info.look:
			equip[slot] = info.look[slot]
		var look := ch.body_look(equip, false)
		# Friends can see the infection: the skin goes grey-green.
		look.skin = (look.skin as Color).lerp(Color(0.55, 0.62, 0.5), sym * 0.7)
		_body.mesh = ZombieModel.mesh_for(look)

	func _animate(delta: float) -> void:
		var want := "h_idle"
		if dead:
			want = "death"
		elif crouching:
			want = "h_crouch"
		elif _speed > 5.0:
			want = "h_run"
		elif _speed > 0.4:
			want = "h_walk"
		if _anim.current_animation != want:
			_anim.play(want, 0.2)
		if want == "h_crouch":
			_anim.speed_scale = clampf(_speed / 1.5, 0.0, 1.5)
		elif want in ["h_walk", "h_run"]:
			_anim.speed_scale = clampf(_speed / (1.6 if want == "h_walk" else 5.5), 0.6, 1.6)
		else:
			_anim.speed_scale = 1.0
		_anim.advance(delta)
