class_name BaseManager
extends Node3D
## Everything players have built: walls, gates, crates, beds, workbenches,
## campfires, rain collectors, farm plots. Records live in
## GameState.ws.structures (saved with the world, shared in multiplayer);
## nodes exist near players. Also ticks what changes with time: fires burn
## down, rain fills collectors, crops grow, spikes hurt zombies.

const NODE_RANGE := 220.0

var gen: WorldGen
var player: Player
var avatars: Avatars
var zombies: ZombieManager
var nodes := {} # id -> StructureBody

var _scan_t := 0.0
var _tick_t := 0.0
var _seq := 0


func record(id: String) -> Dictionary:
	return GameState.ws.structures.get(id, {})


## Builds a structure (materials already paid). Returns its node.
func add(t: String, pos: Vector3, yaw: float) -> StructureBody:
	_seq += 1
	var id := "s_%s_%d_%d" % [GameState.player_id, int(GameState.hours() * 100.0), _seq]
	var mhp := Structures.max_hp(t, GameState.character.skill("carpentry"))
	var r := {"id": id, "t": t, "p": [pos.x, pos.y, pos.z], "yaw": yaw, "hp": mhp, "mhp": mhp}
	if t == "crate":
		GameState.containers["crate_" + id] = []
	if t == "rain_collector":
		r.water = 0.0
	if t == "campfire":
		r.wood = Structures.LOG_HOURS
	GameState.ws.structures[id] = r
	Net.structure(r)
	return _spawn(r)


func remove(id: String, net := true) -> void:
	var r: Dictionary = GameState.ws.structures.get(id, {})
	GameState.ws.structures.erase(id)
	var n: StructureBody = nodes.get(id)
	if n:
		nodes.erase(id)
		n.queue_free()
	if not r.is_empty() and r.t == "crate":
		# What was inside spills on the ground.
		var items: Array = GameState.containers.get("crate_" + id, [])
		var p: Array = r.p
		if Net.authority():
			for it in items:
				GameState.drop_item(Inventory._clean(it), Vector3(p[0], p[1] + 0.3, p[2]))
		GameState.containers.erase("crate_" + id)
	if net:
		Net.structure_gone(id)


## A change made here (lit, watered, opened, damaged): share it.
func changed(r: Dictionary) -> void:
	Net.structure(r)
	var n: StructureBody = nodes.get(r.id)
	if n:
		n.refresh()


## From another player.
func apply_record(r: Dictionary) -> void:
	var known: Dictionary = GameState.ws.structures.get(r.id, {})
	if known.is_empty():
		GameState.ws.structures[r.id] = r
		if r.t == "crate" and not GameState.containers.has("crate_" + str(r.id)):
			GameState.containers["crate_" + str(r.id)] = []
	else:
		known.merge(r, true)
	var n: StructureBody = nodes.get(r.id)
	if n:
		n.rec = GameState.ws.structures[r.id]
		n.refresh()


func _spawn(r: Dictionary) -> StructureBody:
	var n: StructureBody = nodes.get(r.id)
	if n:
		return n
	n = StructureBody.new()
	add_child(n)
	n.setup(r)
	nodes[r.id] = n
	return n


## Damage from zombies (host) or blasts.
func hit(n: StructureBody, amount: float) -> void:
	if not is_instance_valid(n) or not GameState.ws.structures.has(n.rec.id):
		return
	if n.damage(amount):
		GameState.make_noise(n.global_position, 30.0)
		if player.global_position.distance_to(n.global_position) < 60.0:
			GameState.notify("A %s was broken down!" % str(n.def.name).to_lower())
		remove(str(n.rec.id))
	else:
		_dirty[n.rec.id] = true


var _dirty := {} # Damaged records to share (batched, hits come often).


## Stations within reach: "workbench" and/or "fire".
func stations_near(pos: Vector3) -> Array:
	var out := []
	for n: StructureBody in nodes.values():
		if n.global_position.distance_to(pos) > 3.2:
			continue
		if n.t == "workbench" and not "workbench" in out:
			out.append("workbench")
		if n.burning() and not "fire" in out:
			out.append("fire")
	return out


## Lit fires near a point (warmth): sum of closeness 0..1 each.
func warmth_at(pos: Vector3) -> float:
	var w := 0.0
	for n: StructureBody in nodes.values():
		if n.burning():
			w += clampf(1.0 - n.global_position.distance_to(pos) / 6.0, 0.0, 1.0)
	return w


func nearest(t: String, pos: Vector3, radius: float) -> StructureBody:
	var best: StructureBody = null
	var bd := radius
	for n: StructureBody in nodes.values():
		var d := n.global_position.distance_to(pos)
		if n.t == t and d < bd:
			bd = d
			best = n
	return best


func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.7
		_stream()
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = 1.0
		_tick()


func _stream() -> void:
	var centers: Array = [player.global_position]
	if avatars:
		for a in avatars.all():
			centers.append((a as Node3D).global_position)
	for id in GameState.ws.structures:
		var r: Dictionary = GameState.ws.structures[id]
		var p: Array = r.p
		var rp := Vector3(p[0], p[1], p[2])
		var close := false
		for c: Vector3 in centers:
			if c.distance_to(rp) < NODE_RANGE:
				close = true
				break
		var n: StructureBody = nodes.get(id)
		if close and n == null:
			_spawn(r)
		elif not close and n != null:
			nodes.erase(id)
			n.queue_free()
	for id in nodes.keys():
		if not GameState.ws.structures.has(id):
			nodes[id].queue_free()
			nodes.erase(id)


func _tick() -> void:
	var skill := GameState.character.skill("farming")
	var authority := Net.authority()
	for n: StructureBody in nodes.values():
		var r := n.rec
		match n.t:
			"campfire":
				if n._flame and n._flame.visible != n.burning():
					n.refresh()
				if n.burning():
					GameState.make_noise(n.global_position, 4.0)
			"rain_collector":
				if Weather.raining() and authority:
					var before := float(r.get("water", 0.0))
					# A few litres per in-game hour of rain (one tick is 1 s).
					var lph := Weather.intensity() * (8.0 if Weather.kind() == "storm" else 4.0)
					r.water = minf(Structures.COLLECTOR_L, before + lph * 24.0 / GameState.DAY_LENGTH)
					if int(before) != int(r.water):
						changed(r)
			"farm_plot":
				if authority and Farming.tick(r, skill):
					changed(r)
				elif n._crop_key == "" and not r.get("crop", {}).is_empty():
					n.refresh()
			"spikes":
				if authority and zombies:
					for z in zombies.in_radius(n.global_position, 1.6):
						z.take_damage(10.0, (z.global_position - n.global_position).normalized() * 0.3, true, true)
	for id in _dirty:
		var r: Dictionary = GameState.ws.structures.get(id, {})
		if not r.is_empty():
			Net.structure(r)
	_dirty.clear()
