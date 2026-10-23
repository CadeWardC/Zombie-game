class_name TraderNPC
extends StaticBody3D
## The trader standing in a camp: a survivor in work clothes who barters
## (see TradeMenu). Idles, and turns to face you when you come close.

var camp := ""
var trader_name := "Trader"
var _model: Node3D
var _anim: AnimationPlayer


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_model = ZombieModel.instantiate(0)
	add_child(_model)
	var body: MeshInstance3D = _model.get_node("Skeleton3D/Body")
	var ch := Character.random(camp.hash())
	var equip := {"head": ItemDB.make("baseball_cap"), "torso": ItemDB.make("flannel_shirt"), "jacket": ItemDB.make("hunting_jacket"),
		"legs": ItemDB.make("work_pants"), "feet": ItemDB.make("work_boots")}
	body.mesh = ZombieModel.mesh_for(ch.body_look(equip, false))
	_anim = _model.get_node("AnimationPlayer")
	_anim.play("h_idle")
	var label := Label3D.new()
	label.text = trader_name + " (trader)"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.15
	label.pixel_size = 0.004
	label.font_size = 44
	label.outline_size = 10
	label.modulate = Color(0.95, 0.85, 0.5)
	add_child(label)


func _process(delta: float) -> void:
	_anim.advance(delta)
	var p := get_viewport().get_camera_3d()
	if p and p.global_position.distance_to(global_position) < 8.0:
		var to := p.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 3.0))
