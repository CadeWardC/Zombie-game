class_name VehicleMenu
extends CanvasLayer
## What you can do with a vehicle you're standing at: get in (driver or
## passenger), break into a locked car, open the trunk, refuel from a can or
## a nearby pump, swap a dead battery, change a flat, fix the engine, or
## hotwire it. Repairs are simple swaps of the part. Works with touch,
## mouse and gamepad (buttons take focus).

var player: Player
var streamer: WorldStreamer
var vehicle: Vehicle

var _bg: ColorRect
var _box: VBoxContainer
var _title: Label
var _info: Label


func _ready() -> void:
	layer = 9
	visible = false
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.55)
	add_child(_bg)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box = VBoxContainer.new()
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.anchor_top = 0.5
	_box.anchor_bottom = 0.5
	_box.offset_left = -230
	_box.offset_right = 230
	_box.offset_top = -280
	_box.offset_bottom = 280
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 10)
	_bg.add_child(_box)


func is_open() -> bool:
	return visible


func open(v: Vehicle) -> void:
	vehicle = v
	visible = true
	GameState.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild()


func close() -> void:
	visible = false
	GameState.ui_open = false
	if not GameState.uses_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()


func _process(_delta: float) -> void:
	# Walked away, or someone drove off with it.
	if visible and (vehicle == null or not is_instance_valid(vehicle) or player.dead
			or VehicleManager._dist_to(vehicle.global_transform, vehicle.def.size, player.global_position) > 4.0):
		close()


## The actions that make sense right now: [label, callable].
func actions() -> Array:
	var r := vehicle.rec
	var d := vehicle.def
	var out := []
	if r.locked:
		out.append(["Break in (could set off the alarm)", _break_in])
	elif float(r.hp) > 0.0 and vehicle.free_seat() >= 0:
		if not vehicle.seats.has(0):
			out.append(["Drive" if d.kind == "ground" or d.kind == "water" else "Fly", _enter.bind(0)])
		if int(d.seats) > 1:
			out.append(["Get in as a passenger", _enter.bind(-1)])
	if d.trunk and not r.locked and str(r.get("trunk", "")) != "":
		out.append(["Open the trunk", _trunk])
	if d.fuel != "" and float(r.fuel) < float(d.tank) - 0.5:
		if not _can(d.fuel).is_empty():
			out.append(["Refuel from a %s" % ItemDB.item_name(_can(d.fuel).id).to_lower(), _refuel_can])
		if not _pump(d.fuel).is_empty():
			out.append(["Refuel at the pump", _refuel_pump])
	if float(r.hp) > 0.0 and d.fuel != "":
		if d.kind == "ground" and float(r.bat) < 0.2 and GameState.item_count("car_battery") > 0:
			out.append(["Swap in a new battery", _swap.bind("car_battery")])
		if (not r.parts or float(r.eng) < 0.6) and GameState.item_count("engine_parts") > 0:
			out.append(["Fix the engine (engine parts)", _swap.bind("engine_parts")])
		if not r.keys and not r.hot and not r.locked:
			var mech := GameState.character.skill("mechanics")
			if GameState.item_count("screwdriver") > 0 or mech >= 2:
				out.append(["Hotwire it (%d%% chance)" % int(_hotwire_chance() * 100.0), _hotwire])
	if int(r.flat) > 0 and GameState.item_count("car_tire") > 0:
		out.append(["Change a flat tire", _swap.bind("car_tire")])
	return out


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	_title = Label.new()
	_title.text = str(vehicle.def.name).to_upper()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_box.add_child(_title)
	_info = Label.new()
	_info.text = VehicleDB.describe(vehicle.rec)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.custom_minimum_size.x = 460
	_info.add_theme_font_size_override("font_size", 17)
	_box.add_child(_info)
	var first: Button = null
	for a in actions():
		var b := _button(a[0], a[1])
		if first == null:
			first = b
	var back := _button("Back", close)
	(first if first else back).grab_focus.call_deferred()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(460, 58)
	b.add_theme_font_size_override("font_size", 21)
	b.pressed.connect(cb)
	_box.add_child(b)
	return b


func _changed() -> void:
	Net.vehicle_record(vehicle.rec)
	_rebuild()


func _enter(seat: int) -> void:
	close()
	player.enter_vehicle(vehicle, seat)


func _break_in() -> void:
	var r := vehicle.rec
	r.locked = false
	GameState.make_noise(vehicle.global_position, 12.0)
	if vehicle.def.closed and randf() < 0.5 and float(r.bat) >= 0.2:
		vehicle.sound_alarm()
		Net.vehicle_alarm(r.id)
	else:
		GameState.notify("You smash the window and pop the lock")
	_changed()


func _trunk() -> void:
	var ct := {"pos": vehicle.global_position, "type": "car_trunk", "bld": "", "id": vehicle.rec.trunk, "veh": vehicle.rec.id}
	close()
	GameState.container_items(ct)
	player.open_inventory.emit(ct)


func _can(fuel: String) -> Dictionary:
	for g in GameState.inventory.grids():
		for it in g.items:
			if ItemDB.get_def(it.id).get("fuel", "") == fuel and int(it.get("u", 0)) > 0:
				return it
	return {}


func _pump(fuel: String) -> Dictionary:
	if streamer == null:
		return {}
	for ct in streamer.containers_near(vehicle.global_position, 9.0):
		if ct.type == ("fuel_pump" if fuel == "gas" else "jet_pump") and pump_left(ct) > 0.0:
			return ct
	return {}


## Litres left in a pump (each one starts with its own amount).
static func pump_left(ct: Dictionary) -> float:
	if GameState.ws.pumps.has(ct.id):
		return float(GameState.ws.pumps[ct.id])
	var h := str(ct.id).hash()
	return float((80 + absi(h) % 220) * (3 if ct.type == "jet_pump" else 1))


static func take_from_pump(ct: Dictionary, litres: float) -> float:
	var got := minf(litres, pump_left(ct))
	GameState.ws.pumps[ct.id] = pump_left(ct) - got
	Net.pump_state(str(ct.id), float(GameState.ws.pumps[ct.id]))
	return got


func _refuel_can() -> void:
	var r := vehicle.rec
	var it := _can(vehicle.def.fuel)
	var room := float(vehicle.def.tank) - float(r.fuel)
	var pour := minf(room, float(it.u))
	r.fuel = float(r.fuel) + pour
	it.u = int(it.u) - int(ceilf(pour))
	GameState.inventory.notify()
	GameState.notify("Poured in %d L" % int(pour))
	_changed()


func _refuel_pump() -> void:
	var r := vehicle.rec
	var ct := _pump(vehicle.def.fuel)
	var got := take_from_pump(ct, float(vehicle.def.tank) - float(r.fuel))
	r.fuel = float(r.fuel) + got
	GameState.make_noise(vehicle.global_position, 6.0)
	GameState.notify("Pumped %d L%s" % [int(got), " - the pump is dry now" if pump_left(ct) <= 0.0 else ""])
	_changed()


func _swap(item: String) -> void:
	var r := vehicle.rec
	GameState.inventory.take(item, 1)
	match item:
		"car_battery":
			r.bat = 1.0
			GameState.notify("New battery in")
		"car_tire":
			r.flat = maxi(0, int(r.flat) - 1)
			GameState.notify("Tire changed")
		"engine_parts":
			r.parts = true
			r.eng = minf(1.0, maxf(float(r.eng), 0.6) + 0.3)
			GameState.notify("Engine fixed up")
	GameState.make_noise(vehicle.global_position, 8.0)
	GameState.practice("mechanics", 15.0)
	_changed()


func _hotwire_chance() -> float:
	var mech := GameState.character.skill("mechanics")
	var tool := GameState.item_count("screwdriver") > 0
	return clampf((0.3 if tool else 0.0) + 0.17 * mech, 0.1, 0.95)


func _hotwire() -> void:
	var r := vehicle.rec
	GameState.make_noise(vehicle.global_position, 10.0)
	if randf() < _hotwire_chance():
		r.hot = true
		GameState.notify("The engine wires spark - it's hotwired")
		GameState.practice("mechanics", 20.0)
	else:
		GameState.notify("You fumble with the wires... try again")
		if vehicle.def.closed and randf() < 0.15 and float(r.bat) >= 0.2:
			vehicle.sound_alarm()
			Net.vehicle_alarm(r.id)
	_changed()
