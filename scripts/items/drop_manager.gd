class_name DropManager
extends Node3D
## Items lying in the world (dropped by the player, recovered arrows, placed
## bear traps). The data lives in GameState.drops so it's saved with the
## world; this node only shows the ones near the player and springs traps.

const SHOW_DIST := 70.0
const TRAP_RADIUS := 0.6

var player: Player
var zombies: ZombieManager
var _nodes := {} # _key(drop) -> MeshInstance3D
var _refresh_t := 0.0
var _trap_t := 0.0


func _ready() -> void:
	GameState.drops_changed.connect(_refresh)


## Drops an item at (or just below) `pos`, landing on whatever is underneath.
func drop(it: Dictionary, pos: Vector3, armed := false, snap := true) -> void:
	var p := pos
	if snap:
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -30, 0), 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			p = hit.position
	GameState.drop_item(it, p, armed)


## Drops near `pos` within `radius` (for the inventory's "Nearby" grid and
## the pick-up prompt).
func near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var r2 := radius * radius
	for d in GameState.drops:
		if _pos(d).distance_squared_to(pos) < r2:
			out.append(d)
	return out


static func _pos(d: Dictionary) -> Vector3:
	return Vector3(d.p[0], d.p[1], d.p[2])


func _refresh() -> void:
	if player == null:
		return
	var ppos := player.global_position
	var keep := {}
	for d in GameState.drops:
		if _pos(d).distance_to(ppos) > SHOW_DIST:
			continue
		var key := _key(d)
		while keep.has(key): # Identical drops in the same spot.
			key += "+"
		keep[key] = true
		if not _nodes.has(key):
			_nodes[key] = _make_node(d)
	for key in _nodes.keys():
		if not keep.has(key):
			(_nodes[key] as Node3D).queue_free()
			_nodes.erase(key)


## Drops are plain dictionaries; identify one by where it lies and what it is.
static func _key(d: Dictionary) -> String:
	return "%.2f_%.2f_%.2f_%s_%d_%s" % [d.p[0], d.p[1], d.p[2], d.it.id, int(d.it.get("n", 1)), str(d.get("armed", false))]


func _make_node(d: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.item_meshes.get(d.it.id)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var yaw := float(hash(_key(d)) % 628) / 100.0
	var basis := Basis(Vector3.UP, yaw)
	# Long things lie on their side.
	if ItemDB.get_def(d.it.id).get("cat", "") in ["melee", "gun", "bow"] or d.it.id in ["arrow", "bolt"]:
		basis = basis * Basis(Vector3.FORWARD, PI * 0.5)
		mi.position.y = 0.02
	mi.transform = Transform3D(basis, _pos(d) + Vector3(0, 0.02, 0))
	return mi


func _process(delta: float) -> void:
	if player == null:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 2.0
		_refresh()
	_trap_t -= delta
	if _trap_t <= 0.0:
		_trap_t = 0.1
		_check_traps()


func _check_traps() -> void:
	for d in GameState.drops:
		if not d.get("armed", false):
			continue
		var p := _pos(d)
		if zombies:
			for z in zombies.in_radius(p, TRAP_RADIUS):
				z.trap(7.0)
				z.take_damage(40.0, Vector3.ZERO)
				_spring(d)
				return
		if player and not player.dead and player.global_position.distance_to(p) < TRAP_RADIUS * 0.8:
			player.take_damage(30.0, p)
			GameState.notify("You stepped in a bear trap!")
			_spring(d)
			return


func _spring(d: Dictionary) -> void:
	GameState.make_noise(_pos(d), 12.0)
	d.armed = false
	GameState.drops_changed.emit()
