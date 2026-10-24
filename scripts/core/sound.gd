extends Node
## Sound (autoload "Sound"): plays the synthesized sounds (see Synth).
## - one-shots: Sound.play("pistol") for the player's own sounds, or
##   Sound.play_at("groan", pos) for positional ones (zombies, doors,
##   gunfire), from small pools of players;
## - ambience: wind, birds by day, crickets at night, rain, picked from the
##   weather and time and faded in and out;
## - menu music: a quiet pad, only on the menus.
## Buses: Master / SFX / Ambience / Music, with volumes from the settings.
## Zombies near the player groan now and then, so you hear where they are.

const POOL_3D := 16
const POOL_2D := 8

var _cache := {} # name -> AudioStreamWAV
var _p3d: Array[AudioStreamPlayer3D] = []
var _p2d: Array[AudioStreamPlayer] = []
var _amb := {} # loop name -> AudioStreamPlayer
var _music: AudioStreamPlayer
var _groan_t := 2.0
var _heart: AudioStreamPlayer
var _heart_t := 0.0
## The game (main.gd) while one is running: for the player and zombies.
var game: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in ["SFX", "Ambience", "Music"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	apply_volumes()
	for k in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 140.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_p3d.append(p)
	for k in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_p2d.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_heart = AudioStreamPlayer.new()
	_heart.bus = "SFX"
	add_child(_heart)
	# Every button clicks.
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is BaseButton:
			(n as BaseButton).pressed.connect(func() -> void: play("click", -8.0)))


## Volume settings (0..1 each), from GameState.settings.
func apply_volumes() -> void:
	var v: Dictionary = GameState.settings
	for pair in [["Master", "vol_master"], ["SFX", "vol_sfx"], ["Ambience", "vol_ambience"], ["Music", "vol_music"]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			var x := clampf(float(v.get(pair[1], 0.8)), 0.0, 1.0)
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(x, 0.0001)))
			AudioServer.set_bus_mute(i, x <= 0.001)


func stream(name: String) -> AudioStreamWAV:
	if not _cache.has(name):
		_cache[name] = Synth.make(name)
	return _cache[name]


## A sound that isn't anywhere in particular (your own gun, UI clicks).
func play(name: String, db := 0.0, pitch := 1.0) -> void:
	if not _enabled():
		return
	for p in _p2d:
		if not p.playing:
			p.stream = stream(name)
			p.volume_db = db
			p.pitch_scale = pitch * randf_range(0.95, 1.05)
			p.play()
			return


## A sound somewhere in the world.
func play_at(name: String, pos: Vector3, db := 0.0, pitch := 1.0, range_m := 140.0) -> void:
	if not _enabled():
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > range_m:
		return
	var pick: AudioStreamPlayer3D = null
	for p in _p3d:
		if not p.playing:
			pick = p
			break
	if pick == null:
		return
	pick.global_position = pos
	pick.stream = stream(name)
	pick.volume_db = db
	pick.max_distance = range_m
	pick.pitch_scale = pitch * randf_range(0.92, 1.08)
	pick.play()


func _enabled() -> bool:
	# Headless runs (tests, servers) have no audio worth making.
	return DisplayServer.get_name() != "headless"


func music(on: bool) -> void:
	if not _enabled():
		return
	if on and not _music.playing:
		_music.stream = stream("music")
		_music.play()
	elif not on and _music.playing:
		_music.stop()


func _process(delta: float) -> void:
	if not _enabled():
		return
	var p: Player = game.player if game and is_instance_valid(game) and game.get("player") else null
	_update_ambience(p, delta)
	if p == null or not p.active:
		return
	_update_groans(p, delta)
	_update_heartbeat(p, delta)


## Wind always, birds by day, crickets at night, rain when it rains, quieter
## indoors.
func _update_ambience(p: Player, delta: float) -> void:
	var want := {}
	if p and p.active:
		var night := GameState.is_night()
		var inside := p.sheltered
		var k := Weather.kind()
		want.wind = (0.6 if not inside else 0.25) * (1.6 if k == "storm" else 1.0)
		want.birds = 0.5 if not night and not Weather.wet() and not inside and Weather.season() != "Winter" else 0.0
		want.crickets = 0.45 if night and not Weather.wet() and Weather.season() in ["Summer", "Autumn"] else 0.0
		want.rain = (1.0 if not inside else 0.45) * Weather.intensity() if Weather.raining() else 0.0
		if p.bases:
			want.fire = clampf(p.bases.warmth_at(p.global_position), 0.0, 1.0)
	for name in ["wind", "birds", "crickets", "rain", "fire"]:
		var target: float = want.get(name, 0.0)
		var pl: AudioStreamPlayer = _amb.get(name)
		if pl == null:
			if target <= 0.01:
				continue
			pl = AudioStreamPlayer.new()
			pl.bus = "Ambience"
			pl.stream = stream(name)
			pl.volume_db = -60.0
			add_child(pl)
			pl.play()
			_amb[name] = pl
		var cur := db_to_linear(pl.volume_db)
		cur = move_toward(cur, target, delta * 0.5)
		pl.volume_db = linear_to_db(maxf(cur, 0.0001))
		if cur <= 0.001 and target <= 0.0:
			pl.queue_free()
			_amb.erase(name)


## Now and then a zombie nearby groans: positional, so you hear where.
func _update_groans(p: Player, delta: float) -> void:
	_groan_t -= delta
	if _groan_t > 0.0 or game.zombies == null:
		return
	_groan_t = randf_range(1.5, 4.0)
	var near: Array = game.zombies.in_radius(p.global_position, 35.0)
	if near.is_empty():
		return
	var z: Zombie = near[randi() % near.size()]
	if not z.alive():
		return
	var chasing := z.state == Zombie.State.CHASE
	play_at("groan" if randf() < 0.5 else "groan2", z.global_position + Vector3(0, 1.6, 0),
		-2.0 if chasing else -8.0, 1.15 if z.type == "runner" else (0.75 if z.type == "brute" else 1.0), 40.0)


## Badly hurt or turning: your heart pounds.
func _update_heartbeat(p: Player, delta: float) -> void:
	var stress := maxf(p.body.symptoms(), clampf((30.0 - p.health) / 30.0, 0.0, 1.0)) if not p.dead else 0.0
	if stress <= 0.05:
		return
	_heart_t -= delta
	if _heart_t <= 0.0:
		_heart_t = 60.0 / lerpf(70.0, 140.0, stress)
		_heart.stream = stream("heartbeat")
		_heart.volume_db = lerpf(-14.0, -2.0, stress)
		_heart.play()
