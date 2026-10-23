extends Node
## Two-device multiplayer test: run one copy as the host and one as the
## guest, on the same machine (see tests/run_net_test.sh):
##   godot --headless res://tests/net_test.tscn -- --role=host
##   godot --headless res://tests/net_test.tscn -- --role=client
## The two sides take turns through flag files in user://net_test/ and each
## exits 0 if all of its checks passed.

const DIR := "user://net_test"
const WORLD := "nettest"

var role := "host"
var shots := false # --shots: save screenshots (needs a real display).
var _main: Node3D
var _failures := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.get_slice("=", 1)
		if a == "--shots":
			shots = true
	DirAccess.make_dir_recursive_absolute(DIR)
	if role == "host":
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
		_host.call_deferred()
	else:
		_client.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("[%s] %s  %s" % [role, "PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _flag(n: String) -> void:
	var f := FileAccess.open(DIR + "/" + n, FileAccess.WRITE)
	f.store_string("1")


func _has_flag(n: String) -> bool:
	return FileAccess.file_exists(DIR + "/" + n)


func _wait_flag(n: String, timeout_ms := 120000) -> bool:
	var t0 := Time.get_ticks_msec()
	while not _has_flag(n) and Time.get_ticks_msec() - t0 < timeout_ms:
		await get_tree().create_timer(0.1).timeout
	return _has_flag(n)


func _wait_for(cond: Callable, timeout_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout_ms:
		await get_tree().process_frame
	return cond.call()


func _start_game() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _wait_for(func() -> bool: return _main.world_ready and _main.player.active, 90000)


func _shot(n: String) -> void:
	if not shots:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % n)
	print("[%s] saved screenshot %s" % [role, n])


## Turns this player to look at another player's survivor.
func _face(target: Node3D) -> void:
	var to: Vector3 = target.global_position - _main.player.global_position
	_main.player.rotation.y = atan2(-to.x, -to.z)
	_main.player.head.rotation.x = deg_to_rad(-4.0)


func _finish() -> void:
	print("[%s] %s (%d failures)" % [role, "ALL PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- Host ------------------------------------------------------------------------------

func _host() -> void:
	GameState.delete_world(WORLD)
	GameState.start_world(GameState.create_world("Net Test", 8192.0, 12345, 1, 0, WORLD, {"pvp": true}))
	await _start_game()
	_check(_main.player.active, "host world loaded")
	_main.zombies.max_zombies = 6
	_check(Net.host(), "hosting on Wi-Fi")
	_flag("host_ready")

	# The guest joins and appears.
	var joined := await _wait_for(func() -> bool:
		for id in Net.players:
			if not Net.players[id].state.is_empty():
				return true
		return false, 120000)
	_check(joined, "the guest joined and reports its position")
	if not joined:
		_finish()
		return
	var gid: int = Net.players.keys()[0]
	await get_tree().create_timer(1.0).timeout
	var av: Avatars.RemoteAvatar = _main.avatars.avatar(gid)
	_check(av != null and av.global_position.distance_to(Net.players[gid].state.p) < 3.0, "the guest's survivor is shown where they are")
	_check(Net.players[gid].name == "Guest", "the guest's character arrived (%s)" % Net.players[gid].name)
	# Zombies come for the guest too.
	var near_guest := await _wait_for(func() -> bool:
		return not _main.zombies.in_radius(av.global_position, ZombieManager.DESPAWN_DIST).is_empty(), 20000)
	_check(near_guest, "the host spawns zombies around the guest")
	_check(not _main.streamer.extra_centers.is_empty(), "the host loads ground around the guest")
	if shots:
		# Walk over to the guest and look at them.
		_main.player.global_position = av.global_position + Vector3(0, 0.5, 5.0)
		await get_tree().create_timer(1.0).timeout
		_face(av)
		Net.ping(av.global_position + Vector3(3, 0, -6), "loot")
		await get_tree().create_timer(1.0).timeout
		await _shot("40_host_sees_guest")
		_main.pause_menu.open()
		await get_tree().create_timer(0.4).timeout
		await _shot("41_pause_hosting")
		_main.pause_menu._open_map()
		await get_tree().create_timer(0.4).timeout
		await _shot("42_map_friends")
		_main.pause_menu.close()
		_flag("host_posed")
	_flag("host_seen_guest")

	# A dropped item reaches the guest.
	_main.drops.drop(ItemDB.make("crowbar"), av.global_position + Vector3(1, 0, 0))
	_flag("host_dropped")
	# The guest's loot, door and ping arrive here.
	await _wait_flag("guest_acted")
	await get_tree().create_timer(1.0).timeout
	_check(GameState.containers.has("nettest_box") and (GameState.containers["nettest_box"] as Array).size() == 1,
			"the guest's looting reached the host")
	_check(GameState.ws.doors.has("nettest_door") and GameState.ws.doors["nettest_door"].get("l", false), "the guest's door change reached the host")
	_check(_main.pings.any(func(p: Dictionary) -> bool: return p.kind == "help"), "the guest's ping reached the host")
	_check(_main.player.health < 100.0, "PvP: the guest can hurt the host (%.0f)" % _main.player.health)
	var hit_zombie: Zombie = _main.zombies.by_net_id(int(FileAccess.get_file_as_string(DIR + "/guest_hit_id")))
	_check(hit_zombie == null or hit_zombie.health < hit_zombie.max_health, "the guest's hit on a zombie counted")

	# The guest dies infected and rises; the host cures them.
	var turned := await _wait_for(func() -> bool: return not GameState.ws.turned.is_empty(), 30000)
	_check(turned, "the guest's turned body is in the host's world")
	if turned:
		var entry: Dictionary = GameState.ws.turned[0]
		var p: Array = entry.p
		var pos := Vector3(p[0], p[1], p[2])
		_main.player.global_position = pos + Vector3(15, 1, 0)
		await get_tree().create_timer(0.5).timeout
		_main.zombies._spawn_turned(_main.player.global_position)
		var tz: Zombie = _main.zombies._by_turned.get(entry.id)
		_check(tz != null, "the turned guest walks as a zombie")
		if tz:
			tz.take_damage(500.0, Vector3.ZERO)
			_check(tz.subdued, "the turned guest can be subdued")
			tz.cure()
			_check(GameState.ws.turned.is_empty(), "the cure lifts the infection")
	await _wait_flag("guest_revived", 30000)
	_check(_has_flag("guest_revived"), "the cured guest came back to life")

	# A car for the guest: they drive it, everyone sees it move.
	var gav: Node3D = _main.avatars.avatar(gid)
	var cp := gav.global_position + Vector3(4, 0, 0)
	var car := VehicleDB.roll("net_car", "sedan", 0)
	car.merge({"fuel": 40.0, "keys": true, "bat": 1.0, "eng": 1.0, "parts": true, "locked": false, "flat": 0,
		"p": [cp.x, _main.gen.height(cp.x, cp.z) + 0.3, cp.z]}, true)
	GameState.ws.vehicles[car.id] = car
	Net.vehicle_record(car)
	var cstart := Vector3(car.p[0], car.p[1], car.p[2])
	_flag("host_car")
	await _wait_flag("guest_driving", 30000)
	await get_tree().create_timer(3.0).timeout
	var hv: Vehicle = _main.vehicles.nodes.get("net_car")
	_check(hv != null and hv.remote and hv.seats.get(0) == gid, "the host sees the guest at the wheel")
	if hv:
		_check(hv.global_position.distance_to(cstart) > 3.0, "and the car moving (%.0f m)" % hv.global_position.distance_to(cstart))
		_check(float(hv.rec.fuel) < 40.0, "its fuel is shared")
	_flag("host_saw_car")
	await _wait_flag("guest_out", 20000)
	await get_tree().create_timer(1.0).timeout
	_check(hv != null and hv.seats.is_empty() and not hv.remote, "the guest got out")

	# Bases, weather and sleep are shared.
	var gp := gav.global_position
	var wall: StructureBody = _main.bases.add("wall", gp + Vector3(5, 0, 0), 0.0)
	GameState.weather = {"k": "fog", "i": 0.9, "until": GameState.hours() + 20.0}
	Net.weather_changed()
	_flag("host_built")
	await _wait_flag("guest_built", 30000)
	await get_tree().create_timer(1.0).timeout
	var crates: Array = GameState.ws.structures.values().filter(func(r: Dictionary) -> bool: return r.t == "crate")
	_check(not crates.is_empty(), "the guest's crate is in the host's world")
	_check(float(wall.rec.hp) < float(wall.rec.mhp), "the guest's damage to the wall reached the host")
	Net.sleeping(true)
	await _wait_flag("guest_sleeping", 30000)
	await get_tree().create_timer(0.5).timeout
	_check(Net.time_mult > 1.0, "time flies when everyone sleeps")
	Net.sleeping(false)
	_flag("host_awake")

	# Saving keeps the guest's survivor for next time.
	await get_tree().create_timer(1.0).timeout
	_main.save_game()
	var saved := FileAccess.get_file_as_string(GameState.world_file(GameState.world, "save.json"))
	_check(saved.contains("Guest"), "the host's save keeps the guest's character")
	Net.stop()
	_flag("host_done")
	await get_tree().create_timer(0.5).timeout
	GameState.delete_world(WORLD)
	_finish()


# --- Guest -----------------------------------------------------------------------------

func _client() -> void:
	_check(await _wait_flag("host_ready", 120000), "the host is up")
	var c := Character.random(42)
	c.name = "Guest"
	GameState.character = c
	Net.start_discovery()
	var menu: Control = null
	if shots:
		menu = load("res://scenes/menu.tscn").instantiate()
		add_child(menu)
		await get_tree().create_timer(0.3).timeout
		menu._show("join")
	var found := await _wait_for(func() -> bool: return not Net.games.is_empty(), 15000)
	if menu:
		await get_tree().create_timer(2.5).timeout
		menu._refresh_games()
		await get_tree().create_timer(0.3).timeout
		await _shot("43_join_screen")
		Net.welcomed.disconnect(menu._on_welcomed)
		menu.queue_free()
	_check(found, "the game shows up on the network (%d found)" % Net.games.size())
	if not found:
		_finish()
		return
	var g: Dictionary = Net.games.values()[0]
	_check(g.world == "Net Test" and g.get("pvp", false), "it shows the world's name and settings")
	var welcomed := []
	Net.welcomed.connect(func(needs: bool) -> void: welcomed.append(needs))
	Net.join(str(g.ip), int(g.port))
	var ok := await _wait_for(func() -> bool: return not welcomed.is_empty(), 20000)
	_check(ok and welcomed[0] == true, "the host welcomes a new guest (needs a character)")
	if not ok:
		_finish()
		return
	_check(GameState.world_seed == 12345 and GameState.world.get("pvp", false), "the guest got the host's world")
	GameState.character = c
	GameState.give_starting_kit()
	await _start_game()
	_check(_main.player.active, "the guest is playing in the host's world")
	var host_av := await _wait_for(func() -> bool: return _main.avatars.avatar(1) != null, 10000)
	_check(host_av, "the host's survivor is shown")
	await _wait_flag("host_seen_guest", 60000)
	var puppets := await _wait_for(func() -> bool: return _main.zombies.active_count() > 0, 15000)
	_check(puppets, "zombies from the host appear (%d)" % _main.zombies.active_count())
	_check(_main.zombies._active.all(func(z: Zombie) -> bool: return z.puppet), "they're puppets driven by the host")
	if shots:
		await _wait_flag("host_posed", 30000)
		var hav: Node3D = _main.avatars.avatar(1)
		if hav:
			_face(hav)
			await get_tree().create_timer(1.0).timeout
			await _shot("44_guest_sees_host")
	await _wait_flag("host_dropped")
	var got_drop := await _wait_for(func() -> bool:
		return GameState.drops.any(func(d: Dictionary) -> bool: return d.it.id == "crowbar"), 5000)
	_check(got_drop, "the host's dropped item shows up")

	# Loot a container, lock a door, ping, hit the host (PvP) and a zombie.
	GameState.containers["nettest_box"] = [ItemDB.make("bandage")]
	GameState.container_changed("nettest_box")
	GameState.set_door_state("nettest_door", {"o": false, "l": true, "hp": 100.0})
	Net.ping(_main.player.global_position, "help")
	Net.pvp_hit(1, 15.0, _main.player.global_position)
	var z: Zombie = _main.zombies._active[0] if _main.zombies.active_count() > 0 else null
	if z:
		var f := FileAccess.open(DIR + "/guest_hit_id", FileAccess.WRITE)
		f.store_string(str(z.net_id))
		f.close()
		z.take_damage(20.0, Vector3.ZERO)
	else:
		var f := FileAccess.open(DIR + "/guest_hit_id", FileAccess.WRITE)
		f.store_string("0")
		f.close()
	await get_tree().create_timer(0.5).timeout
	_flag("guest_acted")

	# Die infected, carrying a hammer, and wait for the host's cure.
	GameState.inventory.add(ItemDB.make("hammer"))
	_main.player.body.infect(0.0)
	_main.player.body.infection = 0.9999
	_main.player.body.turn_hours = 0.001
	var died := await _wait_for(func() -> bool: return _main.player.dead and _main.player.turned, 5000)
	_check(died, "the guest turned")
	var back := await _wait_for(func() -> bool: return not _main.player.dead, 40000)
	_check(back, "a friend's cure brought the guest back")
	_check(GameState.inventory.count("hammer") == 1, "with the gear they carried")
	_check(not _main.player.body.infected, "and no infection")
	_flag("guest_revived")

	# Drive the host's car.
	await _wait_flag("host_car", 30000)
	var has_car := await _wait_for(func() -> bool: return _main.vehicles.nodes.has("net_car"), 15000)
	_check(has_car, "the host's car shows up")
	if has_car:
		var gv: Vehicle = _main.vehicles.nodes["net_car"]
		await get_tree().create_timer(0.5).timeout
		_main.player.enter_vehicle(gv, 0)
		_check(gv.running, "the guest starts it")
		_flag("guest_driving")
		Input.action_press("move_forward")
		await get_tree().create_timer(2.5).timeout
		Input.action_release("move_forward")
		Input.action_press("jump")
		await _wait_flag("host_saw_car", 20000)
		Input.action_release("jump")
		gv.speed = 0.0
		_main.player.exit_vehicle(true)
	_flag("guest_out")

	await _wait_flag("host_built", 30000)
	var got_wall := await _wait_for(func() -> bool:
		return GameState.ws.structures.values().any(func(r: Dictionary) -> bool: return r.t == "wall"), 10000)
	_check(got_wall, "the host's wall shows up for the guest")
	var got_fog := await _wait_for(func() -> bool: return Weather.kind() == "fog", 10000)
	_check(got_fog, "the guest has the host's weather")
	for id in GameState.ws.structures:
		var r: Dictionary = GameState.ws.structures[id]
		if r.t == "wall":
			r.hp = float(r.hp) - 50.0
			Net.structure(r)
	var me: Vector3 = _main.player.global_position
	_main.bases.add("crate", me + Vector3(-3, 0, 0), 0.0)
	_flag("guest_built")
	Net.sleeping(true)
	_flag("guest_sleeping")
	await _wait_flag("host_awake", 30000)
	Net.sleeping(false)

	# The host closes the game: back to the menu.
	var gone := []
	# Stay in this test scene instead of going back to the menu.
	Net.disconnected.disconnect(_main._on_disconnected)
	Net.disconnected.connect(func(r: String) -> void: gone.append(r))
	await _wait_flag("host_done", 60000)
	var left := await _wait_for(func() -> bool: return not gone.is_empty() or not Net.active(), 10000)
	_check(left, "the guest is told when the host leaves")
	_finish()
