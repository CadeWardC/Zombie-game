class_name TraderManager
extends Node3D
## Trader camps: tiny fenced safe zones (no zombies get in, no PvP) with a
## trader who barters. Spawns the trader near the camp, keeps zombies out
## (the guards shoot any that wander in), and answers "is this spot safe?".

const NAMES := ["Old Hank", "Marisol", "Dutch", "Big Lou", "Rosa", "Pete the Fixer", "Granny May", "Tex"]

var gen: WorldGen
var player: Player
var zombies: ZombieManager
var traders := {} # site id -> TraderNPC
var _t := 0.0


## Trader camp sites, as [{id, center: Vector3, radius}].
func camps() -> Array:
	var out := []
	if gen == null:
		return out
	for s in gen.settlements.sites:
		if s.type == "trader":
			var c: Vector2 = s.center
			out.append({"id": "camp%d" % int(s.id), "site": s, "center": Vector3(c.x, float(s.base), c.y),
				"radius": maxf(float(s.half.x), float(s.half.y)) + 6.0})
	return out


func in_safe_zone(pos: Vector3) -> bool:
	for c in camps():
		var cc: Vector3 = c.center
		if Vector2(pos.x - cc.x, pos.z - cc.z).length() < float(c.radius):
			return true
	return false


func trader_name(camp: String) -> String:
	return NAMES[absi(camp.hash()) % NAMES.size()]


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or player == null:
		return
	_t = 0.5
	var pp := player.global_position
	for c in camps():
		var cc: Vector3 = c.center
		var near := cc.distance_to(pp) < 200.0
		var npc: TraderNPC = traders.get(c.id)
		if near and npc == null:
			npc = TraderNPC.new()
			npc.camp = c.id
			npc.trader_name = trader_name(c.id)
			add_child(npc)
			var site: Dictionary = c.site
			var at := (site.center as Vector2) + Vector2(0, -8).rotated(float(site.rot))
			npc.global_position = Vector3(at.x, float(site.base) + 0.15, at.y)
			npc.rotation.y = -float(site.rot)
			traders[c.id] = npc
		elif not near and npc != null:
			npc.queue_free()
			traders.erase(c.id)
		# Guards: zombies that get inside the fence are shot.
		if near and zombies and Net.authority():
			for z in zombies.in_radius(cc, float(c.radius)):
				if z.alive() and z.turned_id == "":
					z.take_damage(9999.0, Vector3.ZERO, false, false, true)
					GameState.make_noise(cc, 15.0)
