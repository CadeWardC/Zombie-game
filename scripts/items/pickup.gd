class_name Pickup
extends Area3D
## A loot item lying in the world. Walking over it picks it up automatically,
## which is far friendlier on a touchscreen than aiming at it to interact.

var item_type := "food"
var loot_id := ""


func setup(type: String, id: String) -> void:
	item_type = type
	loot_id = id
	collision_layer = 8
	collision_mask = 2
	monitorable = false
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.item_meshes[type]
	mi.scale = Vector3(1.5, 1.5, 1.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = Assets.item_shape
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Player and not body.dead:
		GameState.looted[loot_id] = true
		GameState.add_item(item_type)
		queue_free()
