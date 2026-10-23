extends Node
## Multiplayer (autoload "Net"): 2-4 players on the same Wi-Fi, one of them
## hosting on their device. Godot's high-level multiplayer over ENet.
##
## - The host owns the world: it simulates every zombie (around every
##   player), keeps containers, dropped items, doors, windows, power and the
##   clock, and saves everything, including each guest's character.
## - Each player owns their own survivor: movement, health and inventory
##   run on their device, which reports its state ~15 times a second.
## - Guests find hosts on the local network by probing it (broadcast, plus
##   every address in the subnet, which also works where broadcasts are
##   blocked, as on iOS without the multicast entitlement).
##
## Every message is an RPC on this node, which exists at the same path on
## every device, so game scenes never need matching node paths.

signal state_changed # Hosting / joined / offline.
signal games_changed # The list of games found on the network.
signal player_joined(info: Dictionary)
signal player_left(info: Dictionary)
## A guest got the world from the host; the menu starts the game.
signal welcomed(needs_character: bool)
signal join_failed(reason: String)
## The host left or the connection dropped (guests).
signal disconnected(reason: String)
signal ping_received(ping: Dictionary)
signal chat_notice(text: String)

enum Mode { OFFLINE, HOST, CLIENT }

const PORT := 47810
const DISCOVERY_PORT := 47811
const MAX_PLAYERS := 4
const PROTOCOL := 1
const STATE_RATE := 1.0 / 15.0
const ZOMBIE_RATE := 1.0 / 10.0
const RECORD_INTERVAL := 30.0
## Zombie animations by index, for compact snapshots.
const ANIMS := ["idle", "walk", "run", "attack", "hit", "death", "crawl", "crawl_idle", "crawl_attack",
	"crawl_death", "scream", "subdued"]

var mode := Mode.OFFLINE
## peer id -> {id, uid, name, char (Character dict), look (equip summary),
##   state: {p, yaw, pitch, flags, vis, eye, sym}, dead, turned, out}
var players := {}
## Games found on the network: ip -> {ip, port, name, world, players, max, t}
var games := {}
var host_name := ""
var _session := "" # Random id of this hosting session (one entry per host in Join lists).

var _peer: ENetMultiplayerPeer
var _disc: PacketPeerUDP # Host: answers probes. Guest: sends them.
var _probe_t := 0.0
var _state_t := 0.0
var _zombie_t := 0.0
var _record_t := RECORD_INTERVAL
var _time_t := 0.0
var _drop_seq := 0
var _container_dirty := {} # Guest: container ids changed locally, to send.
var _container_t := 0.0
var _game: Node # The running game (main.gd), when there is one.
## Who sits where: vehicle id -> {seat: peer id}.
var vehicle_seats := {}
## How fast time runs (the host speeds it up while everyone sleeps).
var time_mult := 1.0
var _my_sleep := false
var _weather_json := ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("Couldn't reach the host"))
	multiplayer.server_disconnected.connect(func() -> void: _drop_connection("The host left the game"))
	# Guests only ever talk to the host, which passes things on itself.
	(multiplayer as SceneMultiplayer).server_relay = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func active() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


## True where world simulation (zombies, loot rolls, damage) runs: offline
## or on the host.
func authority() -> bool:
	return mode != Mode.CLIENT


func my_id() -> int:
	return multiplayer.get_unique_id() if active() else 1


func attach_game(game: Node) -> void:
	_game = game


func player_count() -> int:
	return players.size() + 1 if active() else 1


func name_of(peer: int) -> String:
	if peer == my_id():
		return GameState.character.name
	return str(players.get(peer, {}).get("name", "Survivor"))


# --- Hosting -------------------------------------------------------------------------

## Opens the current world to players on the same Wi-Fi.
func host() -> bool:
	if active():
		return true
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		GameState.notify("Couldn't open the game to Wi-Fi (error %d)" % err)
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	mode = Mode.HOST
	host_name = GameState.character.name
	_session = "%08x" % randi()
	_disc = PacketPeerUDP.new()
	_disc.set_broadcast_enabled(true)
	if _disc.bind(DISCOVERY_PORT) != OK:
		push_warning("Discovery port busy; guests on this device can still join by probing")
	players.clear()
	state_changed.emit()
	return true


func stop() -> void:
	if mode == Mode.HOST:
		for id in players:
			rpc_id(id, "_kicked", "The host closed the game")
	if is_client():
		send_record()
	_close()


func _close() -> void:
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	if _disc:
		_disc.close()
	_disc = null
	mode = Mode.OFFLINE
	players.clear()
	vehicle_seats.clear()
	time_mult = 1.0
	_my_sleep = false
	state_changed.emit()


func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	# Wait for the guest's hello before treating them as a player.
	pass


func _on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	var info: Dictionary = players[id]
	players.erase(id)
	_clear_seats(id)
	if is_host():
		_update_time_mult()
		rpc("_player_gone", id)
		chat_notice.emit("%s left" % info.name)
	player_left.emit(info)


# --- Discovery ------------------------------------------------------------------------

## Guests: start looking for games on the local network.
func start_discovery() -> void:
	if is_host():
		return
	if _disc == null:
		_disc = PacketPeerUDP.new()
		_disc.set_broadcast_enabled(true)
		_disc.bind(0)
	_probe_t = 0.0
	games.clear()
	games_changed.emit()


func stop_discovery() -> void:
	if mode == Mode.OFFLINE and _disc:
		_disc.close()
		_disc = null


func _probe() -> void:
	var msg := ("ZS_PROBE %d" % PROTOCOL).to_utf8_buffer()
	_send_to(msg, "255.255.255.255")
	_send_to(msg, "127.0.0.1")
	for ip in IP.get_local_addresses():
		if not _private_ipv4(ip):
			continue
		var parts := ip.split(".")
		var base := "%s.%s.%s." % [parts[0], parts[1], parts[2]]
		_send_to(msg, base + "255")
		for k in range(1, 255):
			_send_to(msg, base + str(k))


func _send_to(msg: PackedByteArray, ip: String) -> void:
	_disc.set_dest_address(ip, DISCOVERY_PORT)
	_disc.put_packet(msg)


static func _private_ipv4(ip: String) -> bool:
	if ip.count(".") != 3:
		return false
	if ip.begins_with("192.168.") or ip.begins_with("10."):
		return true
	if ip.begins_with("172."):
		var b := int(ip.split(".")[1])
		return b >= 16 and b <= 31
	return false


func _poll_discovery(delta: float) -> void:
	if _disc == null:
		return
	if is_host():
		while _disc.get_available_packet_count() > 0:
			var pkt := _disc.get_packet().get_string_from_utf8()
			var ip := _disc.get_packet_ip()
			var port := _disc.get_packet_port()
			if pkt.begins_with("ZS_PROBE"):
				var reply := {"sid": _session, "name": host_name, "world": str(GameState.world.get("name", "")), "players": player_count(),
					"max": MAX_PLAYERS, "port": PORT, "protocol": PROTOCOL, "pvp": bool(GameState.world.get("pvp", false)),
					"rule": GameState.death_rule()}
				_disc.set_dest_address(ip, port)
				_disc.put_packet(("ZS_GAME " + JSON.stringify(reply)).to_utf8_buffer())
		return
	if mode == Mode.CLIENT:
		return
	_probe_t -= delta
	if _probe_t <= 0.0:
		_probe_t = 2.0
		_probe()
	var changed := false
	while _disc.get_available_packet_count() > 0:
		var pkt := _disc.get_packet().get_string_from_utf8()
		var ip := _disc.get_packet_ip()
		if not pkt.begins_with("ZS_GAME "):
			continue
		var info: Variant = JSON.parse_string(pkt.substr(8))
		if typeof(info) != TYPE_DICTIONARY or int(info.get("protocol", 0)) != PROTOCOL:
			continue
		# The same host answers on several addresses (loopback, LAN): keep one,
		# preferring its network address.
		var key := str(info.get("sid", ip))
		if games.has(key) and ip == "127.0.0.1" and str(games[key].ip) != "127.0.0.1":
			ip = str(games[key].ip)
		info.ip = ip
		info.t = Time.get_ticks_msec()
		games[key] = info
		changed = true
	for k in games.keys():
		if Time.get_ticks_msec() - int(games[k].t) > 7000:
			games.erase(k)
			changed = true
	if changed:
		games_changed.emit()


# --- Joining ------------------------------------------------------------------------------

func join(ip: String, port := PORT) -> void:
	if active():
		_close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port)
	if err != OK:
		_fail("Couldn't connect (error %d)" % err)
		return
	multiplayer.multiplayer_peer = _peer
	mode = Mode.CLIENT
	state_changed.emit()


func _on_connected() -> void:
	rpc_id(1, "_hello", GameState.player_id, GameState.character.name, PROTOCOL)


func _fail(reason: String) -> void:
	_close()
	join_failed.emit(reason)


func _drop_connection(reason: String) -> void:
	var was_client := is_client()
	_close()
	if was_client:
		disconnected.emit(reason)


@rpc("any_peer", "reliable")
func _hello(uid: String, pname: String, protocol: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		rpc_id(id, "_kicked", "This game is a different version")
		return
	if players.size() >= MAX_PLAYERS - 1:
		rpc_id(id, "_kicked", "The game is full")
		return
	if uid == GameState.player_id:
		uid += "_2" # Two copies of the game on one device (testing).
	var record: Dictionary = GameState.net_records.get(uid, {})
	players[id] = {"id": id, "uid": uid, "name": record.get("char", {}).get("name", pname), "char": record.get("char", {}),
		"look": {}, "state": {}, "dead": false, "turned": false, "out": bool(record.get("out", false))}
	var others := []
	for pid in players:
		if pid != id:
			others.append(_public(players[pid]))
	others.append({"id": 1, "uid": GameState.player_id, "name": GameState.character.name,
		"char": GameState.character.to_dict(), "look": _my_look()})
	rpc_id(id, "_welcome", uid, GameState.world, GameState.net_state(), record, others)


## What other players need to know about a player.
func _public(p: Dictionary) -> Dictionary:
	return {"id": p.id, "uid": p.uid, "name": p.name, "char": p.char, "look": p.look}


@rpc("authority", "reliable")
func _welcome(uid: String, meta: Dictionary, state: Dictionary, record: Dictionary, others: Array) -> void:
	GameState.player_id = uid
	players.clear()
	for o in others:
		players[int(o.id)] = {"id": int(o.id), "uid": o.uid, "name": o.name, "char": o.char, "look": o.look,
			"state": {}, "dead": false, "turned": false, "out": false}
	GameState.start_net_world(meta, state, record)
	welcomed.emit(record.get("char", {}).is_empty())


## A guest is in the game (after making a character if they needed one).
func client_ready() -> void:
	rpc_id(1, "_ready_to_play", GameState.character.to_dict(), _my_look())


@rpc("any_peer", "reliable")
func _ready_to_play(char_dict: Dictionary, look: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	players[id].char = char_dict
	players[id].name = str(char_dict.get("name", "Survivor"))
	players[id].look = look
	rpc("_player_in", _public(players[id]))
	chat_notice.emit("%s joined" % players[id].name)
	player_joined.emit(players[id])


@rpc("authority", "reliable", "call_local")
func _player_in(info: Dictionary) -> void:
	var id := int(info.id)
	if id == my_id():
		return
	if not players.has(id):
		players[id] = {"id": id, "uid": info.uid, "name": info.name, "char": info.char, "look": info.look,
			"state": {}, "dead": false, "turned": false, "out": false}
	else:
		players[id].merge(info, true)
	if is_client():
		chat_notice.emit("%s joined" % info.name)
		player_joined.emit(players[id])


@rpc("authority", "reliable")
func _player_gone(id: int) -> void:
	if players.has(id):
		var info: Dictionary = players[id]
		players.erase(id)
		_clear_seats(id)
		chat_notice.emit("%s left" % info.name)
		player_left.emit(info)


@rpc("authority", "reliable")
func _kicked(reason: String) -> void:
	_drop_connection(reason)
	if not is_client():
		join_failed.emit(reason)


# --- Player state -----------------------------------------------------------------------

func _my_look() -> Dictionary:
	var equip := {}
	for slot in ItemDB.CLOTHING_SLOTS:
		var it: Dictionary = GameState.inventory.equip[slot]
		if not it.is_empty():
			equip[slot] = {"id": it.id, "v": int(it.get("v", 0))}
	return equip


## Clothes changed: everyone redraws this survivor.
func send_look() -> void:
	if not active():
		return
	_broadcast("_look", [my_id(), _my_look(), GameState.character.to_dict()])


@rpc("any_peer", "reliable")
func _look(id: int, look: Dictionary, char_dict: Dictionary) -> void:
	if is_host():
		if id != multiplayer.get_remote_sender_id():
			return
		_relay("_look", [id, look, char_dict])
	if players.has(id):
		players[id].look = look
		players[id].char = char_dict
		players[id].name = str(char_dict.get("name", players[id].name))


func _send_state() -> void:
	var p: Player = _game.player if _game else null
	if p == null or not p.active:
		return
	var flags := 0
	flags |= 1 if p.crouching else 0
	flags |= 2 if p.sprinting else 0
	flags |= 4 if p.dead else 0
	flags |= 8 if p.flashlight.visible else 0
	flags |= 16 if p.weapons.aim_blend > 0.5 else 0
	flags |= 32 if p.turned else 0
	flags |= 64 if p.swimming else 0
	flags |= 128 if p.vehicle else 0
	var st := [p.global_position, p.rotation.y, p.head.rotation.x, flags, p.visibility(), p.head.position.y,
		snappedf(p.body.symptoms(), 0.25), Vector2(p.velocity.x, p.velocity.z).length(), int(p.health)]
	if is_host():
		var all := {1: st}
		for id in players:
			if not players[id].state.is_empty():
				all[id] = players[id].state.raw
		rpc("_states", all)
	else:
		rpc_id(1, "_state", st)


@rpc("any_peer", "unreliable_ordered")
func _state(st: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		_apply_state(id, st)


@rpc("authority", "unreliable_ordered")
func _states(all: Dictionary) -> void:
	for id in all:
		if int(id) != my_id() and players.has(int(id)):
			_apply_state(int(id), all[id])


func _apply_state(id: int, st: Array) -> void:
	var p: Dictionary = players[id]
	var flags := int(st[3])
	p.state = {"raw": st, "p": st[0], "yaw": st[1], "pitch": st[2], "crouch": flags & 1 != 0, "sprint": flags & 2 != 0,
		"dead": flags & 4 != 0, "light": flags & 8 != 0, "aim": flags & 16 != 0, "turned": flags & 32 != 0,
		"swim": flags & 64 != 0, "veh": flags & 128 != 0, "vis": st[4], "eye": st[5], "sym": st[6], "speed": st[7], "hp": st[8],
		"t": Time.get_ticks_msec()}
	p.dead = p.state.dead
	p.turned = p.state.turned


# --- Zombies ----------------------------------------------------------------------------------

## Host: every client gets the zombies near them.
func _send_zombies() -> void:
	if _game == null or _game.zombies == null:
		return
	for id in players:
		var st: Dictionary = players[id].state
		if st.is_empty():
			continue
		rpc_id(id, "_zombies", _game.zombies.snapshot(st.p, id))


@rpc("authority", "unreliable_ordered")
func _zombies(snap: Array) -> void:
	if _game and _game.zombies:
		_game.zombies.apply_snapshot(snap)


## Guest hits a zombie (melee, bullet, arrow...): the host applies it.
func zombie_hit(net_id: int, amount: float, push: Vector3, alert: bool, flinch: bool, head: bool, blast: bool) -> void:
	rpc_id(1, "_zombie_hit", net_id, amount, push, alert, flinch, head, blast)


@rpc("any_peer", "reliable")
func _zombie_hit(net_id: int, amount: float, push: Vector3, alert: bool, flinch: bool, head: bool, blast: bool) -> void:
	var z: Zombie = _game.zombies.by_net_id(net_id) if _game else null
	if z:
		z.take_damage(amount, push, alert, flinch, head, blast)


## Guest actions on zombies other than damage: "stagger", "ignite", "trap",
## "takedown", "cure".
func zombie_action(net_id: int, action: String, a: Variant = null) -> void:
	rpc_id(1, "_zombie_action", net_id, action, a)


@rpc("any_peer", "reliable")
func _zombie_action(net_id: int, action: String, a: Variant) -> void:
	var z: Zombie = _game.zombies.by_net_id(net_id) if _game else null
	if z == null:
		return
	match action:
		"stagger":
			z.stagger(a[0], a[1])
		"ignite":
			z.ignite(a)
		"trap":
			z.trap(a)
		"takedown":
			z.takedown()
		"cure":
			z.cure()


## Host: a zombie attacks a guest.
func hit_player(peer: int, dmg: float, from: Vector3, kind: String) -> void:
	rpc_id(peer, "_hit_me", dmg, from, kind)


@rpc("authority", "reliable")
func _hit_me(dmg: float, from: Vector3, kind: String) -> void:
	if _game and _game.player:
		_game.player.zombie_hit(dmg, from, kind)


func push_player(peer: int, v: Vector3, grab: float) -> void:
	rpc_id(peer, "_push_me", v, grab)


@rpc("authority", "reliable")
func _push_me(v: Vector3, grab: float) -> void:
	if _game and _game.player:
		_game.player.velocity += v
		if grab > 0.0:
			_game.player.grab(grab)


## PvP: a player shoots or hits another.
func pvp_hit(peer: int, dmg: float, from: Vector3) -> void:
	if peer == my_id():
		return
	if peer == 1 and is_host():
		return
	rpc_id(peer, "_pvp_hit", dmg, from, GameState.character.name)


@rpc("any_peer", "reliable")
func _pvp_hit(dmg: float, from: Vector3, attacker: String) -> void:
	if not GameState.world.get("pvp", false) or _game == null or _game.player == null:
		return
	_game.player.death_cause = "Killed by %s" % attacker
	_game.player.take_damage(dmg, from)
	if randf() < 0.4:
		_game.player.body.add("laceration", ["arm_l", "arm_r", "torso", "leg_l", "leg_r"][randi() % 5])


# --- Noise, effects ------------------------------------------------------------------------------

func noise(pos: Vector3, radius: float) -> void:
	rpc_id(1, "_noise", pos, radius)


@rpc("any_peer", "unreliable")
func _noise(pos: Vector3, radius: float) -> void:
	GameState.noise_made.emit(pos, radius)


## A projectile or throwable: every device simulates its flight; only the
## host applies damage to zombies.
func launch(kind: String, item_id: String, from: Vector3, vel: Vector3, dmg: float) -> void:
	_broadcast("_launch", [kind, item_id, from, vel, dmg])


@rpc("any_peer", "reliable")
func _launch(kind: String, item_id: String, from: Vector3, vel: Vector3, dmg: float) -> void:
	if is_host():
		_relay("_launch", [kind, item_id, from, vel, dmg])
	if _game and _game.effects:
		_game.effects.launch(kind, item_id, from, vel, dmg, true)


## A gunshot: a muzzle flash on that survivor for everyone else.
func shot(pos: Vector3) -> void:
	_broadcast("_shot", [my_id(), pos])


@rpc("any_peer", "unreliable")
func _shot(id: int, pos: Vector3) -> void:
	if is_host():
		_relay("_shot", [id, pos])
	if _game and _game.avatars:
		_game.avatars.flash(id, pos)


# --- World state: drops, containers, doors, windows, power, turned, clock ---------------------------

func new_drop_id() -> String:
	_drop_seq += 1
	return "%s_%d_%d" % [GameState.player_id, int(Time.get_unix_time_from_system()) % 100000, _drop_seq]


func drop_added(d: Dictionary) -> void:
	if active():
		_broadcast("_drop_add", [d])


@rpc("any_peer", "reliable")
func _drop_add(d: Dictionary) -> void:
	if is_host():
		_relay("_drop_add", [d])
	GameState.apply_drop_add(d)


func drop_removed(id: String) -> void:
	if active():
		_broadcast("_drop_remove", [id])


@rpc("any_peer", "reliable")
func _drop_remove(id: String) -> void:
	if is_host():
		_relay("_drop_remove", [id])
	GameState.apply_drop_remove(id)


func drop_changed(d: Dictionary) -> void:
	if active():
		_broadcast("_drop_set", [d])


@rpc("any_peer", "reliable")
func _drop_set(d: Dictionary) -> void:
	if is_host():
		_relay("_drop_set", [d])
	GameState.apply_drop_set(d)


## Guest picks something up: the host checks nobody got there first.
func request_pickup(id: String) -> void:
	rpc_id(1, "_pickup", id)


@rpc("any_peer", "reliable")
func _pickup(id: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var d := GameState.drop_by_id(id)
	if d.is_empty():
		return
	GameState.apply_drop_remove(id)
	rpc("_drop_remove", id)
	rpc_id(sender, "_granted", d.it)


@rpc("authority", "reliable")
func _granted(it: Dictionary) -> void:
	var pos: Vector3 = _game.player.global_position if _game and _game.player else Vector3.ZERO
	GameState.add_item(Inventory._clean(it), pos)


## Someone changed a container's contents.
func container_changed(id: String) -> void:
	if not active():
		return
	_container_dirty[id] = true


func _flush_containers() -> void:
	for id in _container_dirty:
		var items: Array = GameState.containers.get(id, [])
		_broadcast("_container", [id, items])
	_container_dirty.clear()


@rpc("any_peer", "reliable")
func _container(id: String, items: Array) -> void:
	if is_host():
		_relay("_container", [id, items])
	GameState.containers[id] = items.map(func(o: Dictionary) -> Dictionary: return Inventory._clean(o))
	GameState.containers_changed.emit(id)


func door_changed(id: String, st: Dictionary) -> void:
	if active():
		_broadcast("_door", [id, st])


@rpc("any_peer", "reliable")
func _door(id: String, st: Dictionary) -> void:
	if is_host():
		_relay("_door", [id, st])
	GameState.ws.doors[id] = st
	var door: DoorBody = DoorBody.by_id.get(id)
	if door and is_instance_valid(door):
		door.apply_state(st)


func window_smashed(id: String) -> void:
	if active():
		_broadcast("_window", [id])


@rpc("any_peer", "reliable")
func _window(id: String) -> void:
	if is_host():
		_relay("_window", [id])
	GameState.ws.windows[id] = 1
	var w: WindowBody = WindowBody.by_id.get(id)
	if w and is_instance_valid(w):
		w.smash_quiet()


func power_on(site: String, pos: Vector3) -> void:
	if active():
		_broadcast("_power", [site, pos])


@rpc("any_peer", "reliable")
func _power(site: String, pos: Vector3) -> void:
	if is_host():
		_relay("_power", [site, pos])
	GameState.ws.power[site] = [pos.x, pos.y, pos.z]


func turned_changed() -> void:
	if is_host():
		rpc("_turned", GameState.ws.turned)


## A guest died infected: the host adds their walking body to the world.
func add_turned(entry: Dictionary) -> void:
	rpc_id(1, "_add_turned", entry)


@rpc("any_peer", "reliable")
func _add_turned(entry: Dictionary) -> void:
	if is_host():
		GameState.add_turned(entry)


@rpc("authority", "reliable")
func _turned(list: Array) -> void:
	GameState.ws.turned = list


## Host: a cured friend comes back to life where their body stood.
func revive(owner_uid: String, pos: Vector3, items: Array) -> bool:
	for id in players:
		if players[id].uid == owner_uid:
			rpc_id(id, "_revive", pos, items)
			return true
	return false


@rpc("authority", "reliable")
func _revive(pos: Vector3, items: Array) -> void:
	if _game:
		_game.revive(pos, items)


## Host: a turned survivor's body was killed, so the cure can't save them.
func body_gone(owner_uid: String) -> void:
	for id in players:
		if players[id].uid == owner_uid:
			rpc_id(id, "_body_gone")


@rpc("authority", "reliable")
func _body_gone() -> void:
	if _game:
		_game.on_body_gone()


func _send_clock() -> void:
	rpc("_clock", GameState.time_of_day, GameState.day, time_mult, GameState.weather)


@rpc("authority", "unreliable")
func _clock(t: float, d: int, mult: float, weather: Dictionary) -> void:
	GameState.time_of_day = t
	GameState.day = d
	time_mult = mult
	GameState.weather = weather


## Host: time flies only while every player sleeps.
func _update_time_mult() -> void:
	var all := _my_sleep
	for id in players:
		if not players[id].get("sleep", false) and not players[id].get("out", false):
			all = false
	var want := Player.SLEEP_SPEED if all else 1.0
	if want != time_mult:
		time_mult = want
		_send_clock()


func sleeping(on: bool) -> void:
	_my_sleep = on
	if is_host():
		_update_time_mult()
	elif is_client():
		rpc_id(1, "_sleep", on)


@rpc("any_peer", "reliable")
func _sleep(on: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].sleep = on
		_update_time_mult()


## Host: the weather changed; tell everyone now (not just with the clock).
func weather_changed() -> void:
	if is_host():
		_send_clock()


# --- Bases and the land -------------------------------------------------------------------

func structure(r: Dictionary) -> void:
	if active():
		_broadcast("_structure", [r])


@rpc("any_peer", "reliable")
func _structure(r: Dictionary) -> void:
	if is_host():
		_relay("_structure", [r])
	if _game and _game.bases:
		_game.bases.apply_record(r)
	else:
		GameState.ws.structures[r.id] = r


func structure_gone(id: String) -> void:
	if active():
		_broadcast("_structure_gone", [id])


@rpc("any_peer", "reliable")
func _structure_gone(id: String) -> void:
	if is_host():
		_relay("_structure_gone", [id])
	if _game and _game.bases:
		_game.bases.remove(id, false)
	else:
		GameState.ws.structures.erase(id)


func window_boards(id: String, hp: float) -> void:
	if active():
		_broadcast("_boards", [id, hp])


@rpc("any_peer", "reliable")
func _boards(id: String, hp: float) -> void:
	if is_host():
		_relay("_boards", [id, hp])
	if hp <= 0.0:
		GameState.ws.boards.erase(id)
	else:
		GameState.ws.boards[id] = hp
	var w: WindowBody = WindowBody.by_id.get(id)
	if w and is_instance_valid(w):
		w.apply_boards(hp)


func tree_felled(id: String) -> void:
	if active():
		_broadcast("_tree", [id])


@rpc("any_peer", "reliable")
func _tree(id: String) -> void:
	if is_host():
		_relay("_tree", [id])
	if _game and _game.streamer:
		_game.streamer.fell_tree(id)
	else:
		GameState.ws.chopped[id] = 1


func grid_restarted(until: float) -> void:
	if active():
		_broadcast("_grid", [until])


@rpc("any_peer", "reliable")
func _grid(until: float) -> void:
	if is_host():
		_relay("_grid", [until])
	GameState.ws.grid = {"until": until}


func foraged(id: String) -> void:
	if active():
		_broadcast("_forage", [id, GameState.hours()])


@rpc("any_peer", "reliable")
func _forage(id: String, h: float) -> void:
	if is_host():
		_relay("_forage", [id, h])
	GameState.ws.forage[id] = h


## Sends a world change to everyone: the host tells every guest; a guest
## tells the host, which passes it on.
# --- Vehicles --------------------------------------------------------------------------------
# A vehicle's record (fuel, parts, keys...) is shared whenever it changes.
# Whoever drives it simulates it and sends its motion; everyone else follows.

func vehicle_record(r: Dictionary) -> void:
	if active():
		_broadcast("_vrec", [r])


@rpc("any_peer", "reliable")
func _vrec(r: Dictionary) -> void:
	if is_host():
		_relay("_vrec", [r])
	if _game and _game.vehicles:
		_game.vehicles.apply_record(r)
	else:
		GameState.ws.vehicles[r.id] = r


func vehicle_seat(id: String, seat: int, on: bool) -> void:
	_set_seat(my_id(), id, seat, on)
	if active():
		_broadcast("_vseat", [my_id(), id, seat, on])


@rpc("any_peer", "reliable")
func _vseat(peer: int, id: String, seat: int, on: bool) -> void:
	if is_host():
		_relay("_vseat", [peer, id, seat, on])
	_set_seat(peer, id, seat, on)


func _set_seat(peer: int, id: String, seat: int, on: bool) -> void:
	var seats: Dictionary = vehicle_seats.get(id, {})
	if on:
		seats[seat] = peer
	else:
		seats.erase(seat)
	vehicle_seats[id] = seats
	if peer == my_id() or _game == null or _game.vehicles == null:
		return
	var v: Vehicle = _game.vehicles.nodes.get(id)
	if v:
		v.sync_seats(seats)


func _clear_seats(peer: int) -> void:
	for id in vehicle_seats:
		var seats: Dictionary = vehicle_seats[id]
		for s in seats.keys():
			if seats[s] == peer:
				_set_seat(peer, id, s, false)


func _send_vehicle() -> void:
	var p: Player = _game.player if _game else null
	if p == null or p.vehicle == null or p.seat != 0:
		return
	_broadcast("_vstate", [p.vehicle.rec.id, p.vehicle.net_state()])


@rpc("any_peer", "unreliable_ordered")
func _vstate(id: String, st: Array) -> void:
	if is_host():
		_relay("_vstate", [id, st])
	if _game and _game.vehicles:
		var v: Vehicle = _game.vehicles.nodes.get(id)
		if v:
			v.net_apply(st)
		elif GameState.ws.vehicles.has(id):
			var r: Dictionary = GameState.ws.vehicles[id]
			var pos: Vector3 = st[0]
			r.p = [pos.x, pos.y, pos.z]
			r.yaw = st[1]


func vehicle_alarm(id: String) -> void:
	if active():
		_broadcast("_valarm", [id])


@rpc("any_peer", "reliable")
func _valarm(id: String) -> void:
	if is_host():
		_relay("_valarm", [id])
	if _game and _game.vehicles:
		var v: Vehicle = _game.vehicles.nodes.get(id)
		if v:
			v.sound_alarm()


func pump_state(id: String, left: float) -> void:
	if active():
		_broadcast("_pump", [id, left])


@rpc("any_peer", "reliable")
func _pump(id: String, left: float) -> void:
	if is_host():
		_relay("_pump", [id, left])
	GameState.ws.pumps[id] = left


func _broadcast(method: String, args: Array) -> void:
	if is_host():
		callv("rpc", [method] + args)
	elif is_client():
		callv("rpc_id", [1, method] + args)


## Host: send a message on to every guest except the one it came from.
func _relay(method: String, args: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	for id in players:
		if id != sender:
			callv("rpc_id", [id, method] + args)


# --- Guests' saves ---------------------------------------------------------------------------------

## Guest: hand the host everything about this survivor, for its save.
func send_record() -> void:
	if not is_client() or _game == null or _game.player == null:
		return
	rpc_id(1, "_record", GameState.local_record(_game.player))


@rpc("any_peer", "reliable")
func _record(rec: Dictionary) -> void:
	if not is_host() or not players.has(multiplayer.get_remote_sender_id()):
		return
	var uid: String = players[multiplayer.get_remote_sender_id()].uid
	GameState.net_records[uid] = rec


## Permadeath: a guest is out of the game for good.
func mark_out() -> void:
	if is_client():
		rpc_id(1, "_out")


@rpc("any_peer", "reliable")
func _out() -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].out = true
		var uid: String = players[id].uid
		var rec: Dictionary = GameState.net_records.get(uid, {})
		rec.out = true
		GameState.net_records[uid] = rec
		if _game:
			_game.check_world_lost()


func world_lost(cause: String) -> void:
	rpc("_world_lost", cause)


@rpc("authority", "reliable")
func _world_lost(cause: String) -> void:
	if _game:
		_game.on_world_lost(cause)


# --- Pings ----------------------------------------------------------------------------------------

## kind: "go", "zombie", "loot", "help".
func ping(pos: Vector3, kind: String) -> void:
	var p := {"pos": pos, "kind": kind, "name": GameState.character.name, "id": my_id()}
	ping_received.emit(p)
	if active():
		_broadcast("_ping", [p])


@rpc("any_peer", "reliable")
func _ping(p: Dictionary) -> void:
	if is_host():
		_relay("_ping", [p])
	ping_received.emit(p)


# --- Loop ------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_poll_discovery(delta)
	if not active() or _game == null or not is_instance_valid(_game):
		return
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = STATE_RATE
		_send_state()
		_send_vehicle()
	_container_t -= delta
	if _container_t <= 0.0:
		_container_t = 0.3
		if not _container_dirty.is_empty():
			_flush_containers()
	if is_host():
		_zombie_t -= delta
		if _zombie_t <= 0.0:
			_zombie_t = ZOMBIE_RATE
			_send_zombies()
		_time_t -= delta
		if _time_t <= 0.0:
			_time_t = 5.0
			_send_clock()
	else:
		_record_t -= delta
		if _record_t <= 0.0:
			_record_t = RECORD_INTERVAL
			send_record()
