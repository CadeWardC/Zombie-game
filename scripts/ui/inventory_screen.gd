class_name InventoryScreen
extends CanvasLayer
## Tetris-style inventory: equipment slots, pockets / vest / backpack grids,
## and the open container or the ground nearby. A second tab ("Body") holds
## the clothing slots and your injuries, with treating, repairing clothes and
## ripping them into rags. Works three ways:
## - touch and mouse: drag and drop; tap to select, double-tap (or right
##   click) to quick-move; buttons for the rest.
## - gamepad: a cell cursor moved with the D-pad or stick. A picks up / puts
##   down, X quick-moves, Y uses or equips, RB rotates, LB drops, LT sorts,
##   RT takes everything, L3 switches tabs, R3 opens crafting, B cancels or
##   closes.
## The game keeps running while it's open (it's a survival game).

signal closed
signal craft_requested

const MARGIN := 24.0
const GAP := 1.0 # Cells between columns.
const BG := Color(0.025, 0.028, 0.032, 0.9)
const FRAME := Color(1, 1, 1, 0.1)
const CELL_BG := Color(0.1, 0.107, 0.115, 0.95)
const SLOT_ICONS := {"primary": "gun", "sidearm": "gun", "throw": "throw", "melee": "fist", "back": "bag", "vest": "bag",
	"head": "person", "torso": "person", "jacket": "person", "legs": "person", "feet": "person"}
const GOOD := Color(0.35, 0.8, 0.35, 0.5)
const BAD := Color(0.85, 0.25, 0.2, 0.5)
## Equipment slot boxes, in cells (x, y, w, h) inside the equipment column.
const SLOT_BOXES := {
	"primary": Rect2(0, 0, 5, 2), "sidearm": Rect2(0, 2.6, 3, 2), "throw": Rect2(3.2, 2.6, 1.8, 2),
	"melee": Rect2(0, 5.2, 5, 2), "back": Rect2(0, 7.8, 2.4, 2), "vest": Rect2(2.6, 7.8, 2.4, 2),
}
## Clothing slots on the Body tab.
const BODY_BOXES := {
	"head": Rect2(1.3, 0, 2.4, 2), "torso": Rect2(0, 2.3, 2.4, 2.4), "jacket": Rect2(2.6, 2.3, 2.4, 2.4),
	"legs": Rect2(0, 5.0, 2.4, 2.4), "feet": Rect2(2.6, 5.0, 2.4, 2.4),
}

var player: Player
var drops: DropManager

var _board: Control
var _info: Label
var _weight: Label
var _buttons := {}
var _container := {} # The container being looted (empty: none).
var _areas: Array = [] # {kind: "slot"/"grid", slot, grid, rect (screen px), cells (grid origin)}
var _cell := 46.0
var _ground_map: Array = [] # [[item, drop], ...] for the "Nearby" grid.
var _held := {} # {it, from_area_key, x, y, r, slot}
var _grab := Vector2i.ZERO # Cell of the held item under the pointer.
var _pointer := Vector2.ZERO
var _selected := {}
var _press := {}
var _last_tap := {"it": null, "t": 0}
var _cursor := {"area": 0, "x": 0, "y": 0}
var _pad_mode := false
var _repeat_t := 0.0
var _repeating := false
var _trigger_down := {}
var _opened_frame := -1
var _tab := "gear" # "gear" or "body".
var _health_rect := Rect2()
var _hy := 0.0 # Text cursor while drawing the health panel.
var _panel_box := MenuTheme.box(Color(0.06, 0.065, 0.07, 0.96), 10, MenuTheme.LINE, 1, 0.0)
var _slot_box := MenuTheme.box(Color(0.085, 0.09, 0.098, 0.95), 6, Color(1, 1, 1, 0.08), 1, 0.0)
var _item_box := MenuTheme.box(Color.BLACK, 4, Color.WHITE, 1, 0.0)


func _ready() -> void:
	layer = 8
	visible = false
	_board = Control.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_on_board_input)
	add_child(_board)

	var bar := VBoxContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = MARGIN
	bar.offset_right = -MARGIN
	bar.offset_top = -118
	bar.offset_bottom = -10
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 17)
	_info.add_theme_color_override("font_color", MenuTheme.TEXT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.custom_minimum_size.y = 44
	bar.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	for b in [["craft", "Craft"], ["tab", "Body"], ["use", "Use"], ["equip", "Equip"], ["treat", "Treat"], ["repair", "Repair"], ["rip", "Rip Up"],
			["rotate", "Rotate"], ["drop", "Drop"], ["unload", "Unload"], ["detach", "Detach"], ["sort", "Sort"],
			["take_all", "Take All"], ["close", "Close"]]:
		var btn := Button.new()
		btn.text = b[1]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(92, 52)
		btn.add_theme_font_size_override("font_size", 19)
		btn.pressed.connect(_on_button.bind(b[0]))
		row.add_child(btn)
		_buttons[b[0]] = btn
	_weight = Label.new()
	_weight.add_theme_font_size_override("font_size", 16)
	_weight.add_theme_color_override("font_outline_color", Color.BLACK)
	_weight.add_theme_constant_override("outline_size", 4)
	_weight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_weight)
	GameState.inventory_changed.connect(_refresh)
	# Another player looted the same container, or something hit the ground.
	GameState.containers_changed.connect(func(id: String) -> void:
		if visible and not _container.is_empty() and _container.id == id and _held.is_empty():
			_layout()
			_board.queue_redraw())
	GameState.drops_changed.connect(func() -> void:
		if visible and _held.is_empty():
			_layout()
			_board.queue_redraw())
	GameState.device_changed.connect(func() -> void: _board.queue_redraw())


func is_open() -> bool:
	return visible


## Opens the inventory, with a container to loot (or {} for none).
func open(container: Dictionary) -> void:
	_container = container
	if not container.is_empty():
		_tab = "gear"
	_held = {}
	_selected = {}
	_press = {}
	visible = true
	GameState.ui_open = true
	_opened_frame = Engine.get_process_frames()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pad_mode = GameState.using_gamepad()
	if not ItemIcons.texture:
		ItemIcons.build(self)
	_layout()
	# Start the cursor on the container if there is one, else the pockets.
	_cursor = {"area": _area_index("container" if not container.is_empty() else "pockets"), "x": 0, "y": 0}
	_refresh()


func close() -> void:
	if not _held.is_empty():
		_return_held()
	visible = false
	GameState.ui_open = false
	if not GameState.uses_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


# --- Layout ------------------------------------------------------------------

func _layout() -> void:
	var size := _board.get_viewport_rect().size
	var grids := GameState.inventory.grids()
	var mid_cells := 0.0
	var mid_w := 4.0
	for g in grids:
		mid_cells += g.h + 0.8
		mid_w = maxf(mid_w, g.w)
	var right := _right_grids() if _tab == "gear" else ([] as Array[ItemGrid])
	var right_cells := 0.0
	var right_w := 5.0 if _tab == "gear" else 8.0
	for g in right:
		right_cells += g.h + 0.8
		right_w = maxf(right_w, g.w)
	var need_w := 5.0 + mid_w + right_w + GAP * 2.0
	var need_h := maxf(maxf(10.4, mid_cells), right_cells) + 1.0
	_cell = clampf(minf((size.x - MARGIN * 2.0 - 48.0) / need_w, (size.y - 228.0) / need_h), 28.0, 58.0)
	var total_w := need_w * _cell
	var x0 := (size.x - total_w) * 0.5
	var y0 := 76.0
	_areas.clear()
	var boxes: Dictionary = SLOT_BOXES if _tab == "gear" else BODY_BOXES
	for s in boxes:
		var b: Rect2 = boxes[s]
		_areas.append({"kind": "slot", "key": s, "slot": s, "rect": Rect2(x0 + b.position.x * _cell, y0 + 18 + b.position.y * _cell, b.size.x * _cell, b.size.y * _cell)})
	var x := x0 + (5.0 + GAP) * _cell
	var y := y0
	for g in grids:
		_areas.append({"kind": "grid", "key": g.key, "grid": g, "rect": Rect2(x, y + 22, g.w * _cell, g.h * _cell)})
		y += 22 + g.h * _cell + _cell * 0.5
	x += (mid_w + GAP) * _cell
	y = y0
	_health_rect = Rect2(x, y0 + 22, right_w * _cell, minf(size.y - 200.0 - y0, 12.0 * _cell))
	for g in right:
		_areas.append({"kind": "grid", "key": g.key, "grid": g, "rect": Rect2(x, y + 22, g.w * _cell, g.h * _cell)})
		y += 22 + g.h * _cell + _cell * 0.5


## The container being looted (if any) and the ground nearby.
func _right_grids() -> Array[ItemGrid]:
	var out: Array[ItemGrid] = []
	if not _container.is_empty():
		var size: Vector2i = Loot.SIZES.get(_container.type, Vector2i(4, 3))
		out.append(ItemGrid.new("container", Loot.label(_container.type), size.x, size.y, GameState.container_items(_container)))
	var ground := ItemGrid.new("ground", "Nearby", 6, 3 if not _container.is_empty() else 5, [])
	_ground_map.clear()
	if drops and player:
		for d in drops.near(player.global_position, 2.5):
			var it: Dictionary = d.it
			var spot := ground.find_spot(it)
			if spot.x < 0:
				continue
			ground.place(it, spot.x, spot.y, spot.z == 1)
			_ground_map.append([it, d])
	out.append(ground)
	return out


func _area_index(key: String) -> int:
	for k in _areas.size():
		if _areas[k].key == key:
			return k
	return 0


func _area(key: String) -> Dictionary:
	for a in _areas:
		if a.key == key:
			return a
	return {}


func _refresh() -> void:
	if not visible:
		return
	# Looting changes the container for everyone in a multiplayer game.
	if not _container.is_empty():
		GameState.container_changed(_container.id)
	_layout()
	_cursor.area = clampi(_cursor.area, 0, _areas.size() - 1)
	_update_info()
	_board.queue_redraw()


# --- Item helpers -----------------------------------------------------------

func _inv() -> Inventory:
	return GameState.inventory


## Where an item is: [area dict, item] or [] if not found.
func _locate(it: Dictionary) -> Dictionary:
	for a in _areas:
		if a.kind == "slot" and is_same(_inv().equip[a.slot], it):
			return a
		if a.kind == "grid" and (a.grid as ItemGrid).index_of(it) >= 0:
			return a
	return {}


## Takes an item out of wherever it is. Returns false if it can't move.
func _lift(it: Dictionary) -> bool:
	var a := _locate(it)
	if a.is_empty():
		return false
	if a.kind == "slot":
		_inv().equip[a.slot] = {}
	elif a.key == "ground":
		for pair in _ground_map:
			if is_same(pair[0], it):
				GameState.remove_drop(pair[1])
				break
	else:
		(a.grid as ItemGrid).remove(it)
	return true


## Puts an item into the player's grids / slots, or failing that on the ground.
func _give_to_player(it: Dictionary) -> void:
	var left := _inv().add(it)
	if left > 0:
		var rest := it.duplicate(true)
		rest.n = left
		_drop(rest)


func _drop(it: Dictionary) -> void:
	if drops and player:
		drops.drop(it, player.global_position + (-player.global_basis.z) * 0.6)
	else:
		GameState.drop_item(it, Vector3.ZERO)


## Tries to put `it` into area `a` with its top-left at cell (x, y).
## Returns true if it went in (merged, loaded, attached or placed).
func _put(it: Dictionary, a: Dictionary, x: int, y: int, rotated: bool) -> bool:
	if a.is_empty():
		return false
	if a.kind == "slot":
		if not _inv().slot_accepts(a.slot, it) or not _inv().equip[a.slot].is_empty():
			return false
		it.erase("x")
		it.erase("y")
		it.erase("r")
		_inv().equip[a.slot] = it
		return true
	if a.key == "ground":
		_drop(it)
		return true
	var g: ItemGrid = a.grid
	# A bag can't go inside itself.
	if it.has("items") and is_same(it.items, g.items):
		return false
	var target := g.item_at(x, y)
	if not target.is_empty() and not is_same(target, it):
		return _combine(it, target)
	return g.place(it, x, y, rotated)


## Dropping one item onto another: stack, load ammo, or fit an attachment.
func _combine(it: Dictionary, target: Dictionary) -> bool:
	var d := ItemDB.get_def(it.id)
	var td := ItemDB.get_def(target.id)
	if it.id == target.id and int(d.get("stack", 1)) > 1:
		var room := int(d.stack) - int(target.n)
		if room <= 0:
			return false
		var moved := mini(room, int(it.n))
		target.n = int(target.n) + moved
		it.n = int(it.n) - moved
		if int(it.n) > 0:
			_give_to_player(it)
		return true
	if td.get("cat", "") == "gun" and td.ammo == it.id:
		var need := int(td.mag) - int(target.a)
		var moved := mini(need, int(it.n))
		if moved <= 0:
			return false
		target.a = int(target.a) + moved
		it.n = int(it.n) - moved
		if int(it.n) > 0:
			_give_to_player(it)
		GameState.notify("Loaded %d rounds" % moved)
		return true
	if d.get("cat", "") == "attachment" and target.id in d.fits:
		var att: Dictionary = target.att
		var old: String = att.get(d.part, "")
		att[d.part] = it.id
		if old != "":
			_give_to_player(ItemDB.make(old))
		GameState.notify("Attached %s" % d.name)
		return true
	return false


func _return_held() -> void:
	var h := _held
	_held = {}
	var it: Dictionary = h.it
	var a := _area(h.from)
	if a.is_empty() or not _put(it, a, h.x, h.y, h.r):
		_give_to_player(it)
	_inv().notify()


func _pick(it: Dictionary, grab := Vector2i.ZERO) -> void:
	var a := _locate(it)
	if a.is_empty() or not _lift(it):
		return
	_held = {"it": it, "from": a.key, "x": int(it.get("x", 0)), "y": int(it.get("y", 0)), "r": bool(it.get("r", false))}
	_grab = grab
	_selected = it
	_inv().notify()


## Puts the held item down with its grabbed cell at (cx, cy) of area `a`.
func _place_held(a: Dictionary, cx: int, cy: int) -> bool:
	var it: Dictionary = _held.it
	var x := cx - _grab.x
	var y := cy - _grab.y
	if a.kind == "slot" and not _inv().equip[a.slot].is_empty() and _inv().slot_accepts(a.slot, it):
		# Swap with what's in the slot.
		var old: Dictionary = _inv().equip[a.slot]
		_inv().equip[a.slot] = {}
		_put(it, a, 0, 0, false)
		_held = {"it": old, "from": _held.from, "x": _held.x, "y": _held.y, "r": false}
		_grab = Vector2i.ZERO
		_inv().notify()
		return true
	if _put(it, a, x, y, bool(it.get("r", false))):
		_held = {}
		_inv().notify()
		return true
	return false


func _rotate(it: Dictionary) -> void:
	if it.is_empty():
		return
	if not _held.is_empty() and is_same(_held.it, it):
		it.r = not bool(it.get("r", false))
		_grab = Vector2i(_grab.y, _grab.x)
		_board.queue_redraw()
		return
	var a := _locate(it)
	if a.is_empty() or a.kind != "grid":
		return
	var g: ItemGrid = a.grid
	var r := not bool(it.get("r", false))
	if g.fits(it, int(it.x), int(it.y), r):
		it.r = r
		_inv().notify()


## Container <-> player in one go.
func _quick_move(it: Dictionary) -> void:
	var a := _locate(it)
	if a.is_empty():
		return
	if a.key == "container" or a.key == "ground":
		_lift(it)
		var left := _inv().add(it)
		if left > 0:
			it.n = left
			if not _put(it, a, int(it.get("x", 0)), int(it.get("y", 0)), bool(it.get("r", false))):
				_drop(it)
			GameState.notify("No room")
	else:
		_lift(it)
		var dest := _area("container")
		if not dest.is_empty():
			var g: ItemGrid = dest.grid
			var left := g.add(it)
			if left > 0:
				it.n = left
				_give_to_player(it)
				GameState.notify("No room")
		else:
			_drop(it)
	_selected = {}
	_inv().notify()


## Use / equip / unequip, depending on the item.
func _use(it: Dictionary) -> void:
	if it.is_empty():
		return
	if ItemDB.is_consumable(it.id):
		if _locate(it).key in ["container", "ground"]:
			_quick_move(it) # Take it first.
			return
		player.consume(it)
		return
	var slot := ItemDB.slot_for(it.id)
	if slot == "":
		return
	var a := _locate(it)
	if a.kind == "slot":
		_lift(it)
		var left := 0
		for g in _inv().grids():
			left = g.add(it)
			if left == 0:
				break
		if left > 0:
			_drop(it)
	else:
		var old: Dictionary = _inv().equip[slot]
		_lift(it)
		_inv().equip[slot] = {}
		_put(it, {"kind": "slot", "slot": slot, "key": slot}, 0, 0, false)
		if not old.is_empty():
			_give_to_player(old)
		if slot in Weapons.SLOT_ORDER:
			player.weapons.select(slot)
	_inv().notify()


func _unload(it: Dictionary) -> void:
	if it.is_empty() or int(it.get("a", 0)) <= 0 or ItemDB.get_def(it.id).get("cat", "") != "gun":
		return
	var n := int(it.a)
	it.a = 0
	_give_to_player(ItemDB.make(ItemDB.get_def(it.id).ammo, n))
	GameState.notify("Unloaded %d rounds" % n)
	_inv().notify()


func _detach(it: Dictionary) -> void:
	var att: Dictionary = it.get("att", {})
	if att.is_empty():
		return
	var part: String = att.keys()[0]
	var id: String = att[part]
	att.erase(part)
	_give_to_player(ItemDB.make(id))
	GameState.notify("Removed %s" % ItemDB.item_name(id))
	_inv().notify()


func _take_all() -> void:
	var a := _area("container")
	if a.is_empty():
		a = _area("ground")
	if a.is_empty():
		return
	var items: Array = (a.grid as ItemGrid).items.duplicate()
	for it in items:
		_quick_move(it)


func _sort(a: Dictionary) -> void:
	if a.is_empty() or a.kind != "grid" or a.key == "ground":
		return
	(a.grid as ItemGrid).sort()
	_inv().notify()


func _on_button(id: String) -> void:
	var it := _selected
	match id:
		"use", "equip":
			_use(it)
		"rotate":
			_rotate(_held.it if not _held.is_empty() else it)
		"drop":
			if not it.is_empty() and not _locate(it).is_empty():
				_lift(it)
				_drop(it)
				_selected = {}
				_inv().notify()
		"unload":
			_unload(it)
		"detach":
			_detach(it)
		"sort":
			var a := _locate(it) if not it.is_empty() else _area("pockets")
			_sort(a if a.kind == "grid" else _area("pockets"))
		"take_all":
			_take_all()
		"close":
			close()
		"craft":
			craft_requested.emit()
		"tab":
			_set_tab("body" if _tab == "gear" else "gear")
		"treat":
			player.quick_use(["medical"], [])
			_inv().notify()
		"repair":
			_repair(it)
		"rip":
			_rip(it)


func _set_tab(t: String) -> void:
	if not _held.is_empty():
		_return_held()
	_tab = t
	_selected = {}
	_cursor = {"area": _area_index("pockets"), "x": 0, "y": 0}
	_refresh()
	_cursor = {"area": _area_index("pockets"), "x": 0, "y": 0}


## Sewing kit: patches up a worn piece of clothing.
func _repair(it: Dictionary) -> void:
	if it.is_empty() or ItemDB.get_def(it.id).get("cat", "") != "clothing":
		return
	var kit := _inv().find("sewing_kit")
	if kit.is_empty():
		GameState.notify("You need a sewing kit")
		return
	if float(it.get("c", 1.0)) >= 0.99:
		GameState.notify("It doesn't need mending")
		return
	it.c = minf(1.0, float(it.get("c", 1.0)) + 0.35)
	kit.u = int(kit.get("u", 1)) - 1
	if int(kit.u) <= 0:
		_inv().detach(kit)
		GameState.notify("Mended your %s. The sewing kit is used up." % ItemDB.item_name(it.id))
	else:
		GameState.notify("Mended your %s" % ItemDB.item_name(it.id))
	_inv().notify()


## Tears a piece of clothing into rags (makeshift bandages).
func _rip(it: Dictionary) -> void:
	if it.is_empty() or ItemDB.get_def(it.id).get("cat", "") != "clothing":
		return
	var d := ItemDB.get_def(it.id)
	if d.look in ["helmet", "army_helmet", "armor", "boots"]:
		GameState.notify("You can't tear that up")
		return
	var n := clampi(int(d.w) * int(d.h) - 1, 1, 4)
	_lift(it)
	for sub in it.get("items", []):
		_give_to_player(sub)
	_give_to_player(ItemDB.make("rag", n))
	GameState.notify("Ripped the %s into %d rags" % [ItemDB.item_name(it.id), n])
	_selected = {}
	_inv().notify()


# --- Pointer (mouse and touch) -----------------------------------------------

## Area and cell under a screen point: [area, Vector2i cell] or [].
func _hit(pos: Vector2) -> Array:
	for a in _areas:
		var r: Rect2 = a.rect
		if r.grow(2).has_point(pos):
			if a.kind == "slot":
				return [a, Vector2i.ZERO]
			var c := Vector2i(floori((pos.x - r.position.x) / _cell), floori((pos.y - r.position.y) / _cell))
			return [a, c.clamp(Vector2i.ZERO, Vector2i(a.grid.w - 1, a.grid.h - 1))]
	return []


func _item_at_hit(h: Array) -> Dictionary:
	if h.is_empty():
		return {}
	var a: Dictionary = h[0]
	if a.kind == "slot":
		return _inv().equip[a.slot]
	return (a.grid as ItemGrid).item_at(h[1].x, h[1].y)


func _on_board_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_pad_mode = false
		_pointer = event.position
		var h := _hit(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var it := _item_at_hit(h)
				_press = {"it": it, "pos": event.position, "hit": h}
			else:
				if not _held.is_empty():
					var placed := false
					if not h.is_empty():
						placed = _place_held(h[0], h[1].x, h[1].y)
					if not placed and not _held.is_empty():
						_return_held()
				elif not _press.is_empty():
					var it: Dictionary = _press.it
					if not it.is_empty():
						var now := Time.get_ticks_msec()
						if is_same(_last_tap.it, it) and now - int(_last_tap.t) < 350:
							_quick_move(it)
							_last_tap = {"it": null, "t": 0}
						else:
							_selected = it
							_last_tap = {"it": it, "t": now}
					else:
						_selected = {}
				_press = {}
				_update_info()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var it := _item_at_hit(h)
			if _held.is_empty() and not it.is_empty():
				_quick_move(it)
			elif not _held.is_empty():
				_rotate(_held.it)
		_board.queue_redraw()
	elif event is InputEventMouseMotion:
		_pointer = event.position
		if not _press.is_empty() and _held.is_empty() and not (_press.it as Dictionary).is_empty() \
				and event.position.distance_to(_press.pos) > 10.0:
			var it: Dictionary = _press.it
			var h: Array = _press.hit
			var grab := Vector2i.ZERO
			if h[0].kind == "grid":
				grab = (h[1] as Vector2i) - Vector2i(int(it.x), int(it.y))
			_pick(it, grab)
			_press = {}
		if not _held.is_empty():
			_board.queue_redraw()


# --- Gamepad and keys -------------------------------------------------------

func _process(delta: float) -> void:
	if not visible:
		return
	if Engine.get_process_frames() != _opened_frame and (Input.is_action_just_pressed("inventory") or Input.is_action_just_pressed("pause")):
		close()
		return
	if Engine.get_process_frames() != _opened_frame and Input.is_action_just_pressed("craft") and _held.is_empty():
		craft_requested.emit()
		return
	if Input.is_action_just_pressed("ui_rotate") and not _held.is_empty():
		_rotate(_held.it)
	if player and player.dead:
		close()
		return
	# Cursor movement with repeat.
	var v := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var pv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if GameState.using_gamepad() else Vector2.ZERO
	if pv.length() > v.length():
		v = pv
	if v.length() > 0.5:
		_repeat_t -= delta
		if not _repeating or _repeat_t <= 0.0:
			_repeat_t = 0.1 if _repeating else 0.3
			_repeating = true
			_pad_mode = true
			_move_cursor(v)
	else:
		_repeating = false


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	_pad_mode = true
	if event is InputEventJoypadMotion:
		if event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and event.axis_value > 0.6 and not _trigger_down.get(event.axis, false):
			_trigger_down[event.axis] = true
			if event.axis == JOY_AXIS_TRIGGER_LEFT:
				_sort(_areas[_cursor.area])
			else:
				_take_all()
		elif event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and event.axis_value < 0.3:
			_trigger_down[event.axis] = false
		return
	if not event.pressed:
		return
	var a: Dictionary = _areas[_cursor.area]
	var under := _item_at_hit([a, Vector2i(_cursor.x, _cursor.y)])
	match event.button_index:
		JOY_BUTTON_A:
			if _held.is_empty():
				if not under.is_empty():
					var grab := Vector2i.ZERO
					if a.kind == "grid":
						grab = Vector2i(_cursor.x - int(under.x), _cursor.y - int(under.y))
					_pick(under, grab)
			elif not _place_held(a, _cursor.x, _cursor.y):
				GameState.notify("Doesn't fit there")
		JOY_BUTTON_B:
			if not _held.is_empty():
				_return_held()
			else:
				close()
		JOY_BUTTON_X:
			if _held.is_empty() and not under.is_empty():
				_quick_move(under)
		JOY_BUTTON_Y:
			_use(_held.it if not _held.is_empty() else under)
		JOY_BUTTON_RIGHT_SHOULDER:
			_rotate(_held.it if not _held.is_empty() else under)
		JOY_BUTTON_LEFT_SHOULDER:
			if _held.is_empty() and not under.is_empty():
				_lift(under)
				_drop(under)
				_inv().notify()
		JOY_BUTTON_LEFT_STICK:
			_set_tab("body" if _tab == "gear" else "gear")
		JOY_BUTTON_RIGHT_STICK:
			if _held.is_empty():
				craft_requested.emit()
				return
	get_viewport().set_input_as_handled()
	_update_info()
	_board.queue_redraw()


## Moves the gamepad cursor to the nearest cell in direction `v`, across
## grids and slots.
func _move_cursor(v: Vector2) -> void:
	var dir := v.normalized()
	var here := _cursor_center()
	var best := {}
	var best_score := INF
	for k in _areas.size():
		var a: Dictionary = _areas[k]
		var cells: Array = []
		if a.kind == "slot":
			cells.append([Vector2i.ZERO, (a.rect as Rect2).get_center()])
		else:
			var g: ItemGrid = a.grid
			for y in g.h:
				for x in g.w:
					cells.append([Vector2i(x, y), (a.rect as Rect2).position + (Vector2(x, y) + Vector2(0.5, 0.5)) * _cell])
		for c in cells:
			var to: Vector2 = c[1] - here
			var along := to.dot(dir)
			if along < _cell * 0.4:
				continue
			var across := absf(to.cross(dir))
			var score := along + across * 2.5
			if score < best_score:
				best_score = score
				best = {"area": k, "x": c[0].x, "y": c[0].y}
	if not best.is_empty():
		_cursor = best
		_update_info()
		_board.queue_redraw()


func _cursor_center() -> Vector2:
	var a: Dictionary = _areas[clampi(_cursor.area, 0, _areas.size() - 1)]
	if a.kind == "slot":
		return (a.rect as Rect2).get_center()
	return (a.rect as Rect2).position + (Vector2(_cursor.x, _cursor.y) + Vector2(0.5, 0.5)) * _cell


# --- Info bar ------------------------------------------------------------------

func _focus_item() -> Dictionary:
	if not _held.is_empty():
		return _held.it
	if _pad_mode and not _areas.is_empty():
		return _item_at_hit([_areas[_cursor.area], Vector2i(_cursor.x, _cursor.y)])
	return _selected


func _update_info() -> void:
	var it := _focus_item()
	if not _pad_mode and not _selected.is_empty() and _locate(_selected).is_empty() and _held.is_empty():
		_selected = {}
		it = {}
	if it.is_empty():
		_info.text = "Drag items to move them. Double-tap to move between your bag and a container." if not _pad_mode else ""
	else:
		_info.text = "%s%s\n%s" % [ItemDB.item_name(it.id), " x%d" % int(it.n) if int(it.get("n", 1)) > 1 else "", ItemDB.describe(it)]
	var where: String = _locate(it).get("key", "") if not it.is_empty() else ""
	var cat: String = ItemDB.get_def(it.get("id", "")).get("cat", "")
	_buttons.use.visible = ItemDB.is_consumable(it.get("id", ""))
	_buttons.equip.visible = ItemDB.slot_for(it.get("id", "")) != ""
	_buttons.equip.text = "Unequip" if where in ItemDB.SLOTS else "Equip"
	_buttons.rotate.visible = not it.is_empty()
	_buttons.drop.visible = not it.is_empty() and where != "ground"
	_buttons.unload.visible = cat == "gun" and int(it.get("a", 0)) > 0
	_buttons.detach.visible = not it.get("att", {}).is_empty()
	_buttons.take_all.visible = _tab == "gear" and (not _container.is_empty() or not _ground_map.is_empty())
	_buttons.tab.text = "Gear" if _tab == "body" else "Body"
	_buttons.tab.visible = true
	_buttons.treat.visible = _tab == "body"
	_buttons.repair.visible = cat == "clothing" and float(it.get("c", 1.0)) < 0.99 and _inv().count("sewing_kit") > 0
	_buttons.rip.visible = cat == "clothing" and _tab == "body"
	_buttons.unload.visible = _buttons.unload.visible and _tab == "gear"
	_buttons.detach.visible = _buttons.detach.visible and _tab == "gear"
	_buttons.close.visible = true
	_buttons.craft.visible = true
	for b in _buttons.values():
		if _pad_mode:
			b.visible = false # Gamepad hints are drawn instead.
	var inv := _inv()
	_weight.text = "Carrying %.1f / %.0f kg%s" % [inv.weight(), Inventory.CARRY_KG * inv.carry_mult, "  (slowed)" if inv.speed_factor() < 1.0 else ""]


# --- Drawing -------------------------------------------------------------------

func _draw_board() -> void:
	var size := _board.size
	_board.draw_rect(Rect2(Vector2.ZERO, size), BG)
	var font := _board.get_theme_default_font()
	var head := MenuTheme.heading_font()
	# A panel behind each column, with its heading.
	var cols := {}
	for a in _areas:
		var r: Rect2 = a.rect
		var key := "slots" if a.kind == "slot" else ("right" if a.key in ["container", "ground"] else "bag")
		cols[key] = (cols[key] as Rect2).merge(r) if cols.has(key) else r
	if _tab == "body":
		cols["right"] = _health_rect
	var titles := {"slots": "Equipment" if _tab == "gear" else "Clothes", "bag": "Your bag",
		"right": ("Body" if _tab == "body" else (Loot.label(_container.type) if not _container.is_empty() else "Nearby"))}
	for key in cols:
		var pr: Rect2 = (cols[key] as Rect2).grow_individual(14, 58, 14, 14)
		_board.draw_style_box(_panel_box, pr)
		_board.draw_string(head, pr.position + Vector2(14, 26), str(titles[key]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MenuTheme.TEXT)
		_board.draw_rect(Rect2(pr.position + Vector2(14, 33), Vector2(28, 2)), MenuTheme.ACCENT)
	if _tab == "body":
		_draw_health(font)
	for a in _areas:
		var r: Rect2 = a.rect
		if a.kind == "slot":
			_board.draw_style_box(_slot_box, r)
			var lbl: String = ItemDB.SLOT_NAMES[a.slot]
			_board.draw_string(font, r.position + Vector2(2, -5), lbl.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MenuTheme.DIM)
			var it: Dictionary = _inv().equip[a.slot]
			if not it.is_empty():
				_draw_item(font, it, _fit_rect(it, r.grow(-5)), false)
			else:
				Icons.draw(_board, SLOT_ICONS.get(a.slot, ""), r.get_center(), minf(r.size.x, r.size.y) * 0.45, Color(1, 1, 1, 0.07))
		else:
			var g: ItemGrid = a.grid
			if g.title.to_upper() != str(titles.get("right", "")).to_upper():
				var title := g.title
				if a.key == "ground" and g.items.is_empty():
					title += "  (nothing)"
				_board.draw_string(font, r.position + Vector2(0, -6), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MenuTheme.DIM.lightened(0.15))
			for y in g.h:
				for x in g.w:
					_board.draw_rect(Rect2(r.position + Vector2(x, y) * _cell, Vector2(_cell, _cell)).grow(-1.5), CELL_BG)
			for it in g.items:
				var sz := ItemGrid.dims(it)
				var ir := Rect2(r.position + Vector2(int(it.x), int(it.y)) * _cell, Vector2(sz) * _cell).grow(-2)
				_draw_item(font, it, ir, bool(it.get("r", false)))
	# Selection / cursor.
	if _pad_mode and not _areas.is_empty():
		var a: Dictionary = _areas[_cursor.area]
		var cr: Rect2
		if a.kind == "slot":
			cr = a.rect
		else:
			cr = Rect2((a.rect as Rect2).position + Vector2(_cursor.x, _cursor.y) * _cell, Vector2(_cell, _cell))
		_board.draw_rect(cr.grow(1), Color(1.0, 0.85, 0.3), false, 3.0)
	elif not _selected.is_empty() and _held.is_empty():
		var a := _locate(_selected)
		if not a.is_empty():
			var sr: Rect2 = a.rect if a.kind == "slot" else Rect2((a.rect as Rect2).position + Vector2(int(_selected.x), int(_selected.y)) * _cell, Vector2(ItemGrid.dims(_selected)) * _cell)
			_board.draw_rect(sr.grow(1), Color(1.0, 0.85, 0.3), false, 2.5)
	# The held item follows the pointer or cursor, tinted by whether it fits.
	if not _held.is_empty():
		var it: Dictionary = _held.it
		var s := ItemGrid.dims(it)
		var anchor := _cursor_center() if _pad_mode else _pointer
		var top_left := anchor - (Vector2(_grab) + Vector2(0.5, 0.5)) * _cell
		var hr := Rect2(top_left, Vector2(s) * _cell)
		var h := _hit(anchor)
		var ok := false
		if not h.is_empty():
			var a: Dictionary = h[0]
			if a.kind == "slot":
				ok = _inv().slot_accepts(a.slot, it)
				hr = _fit_rect(it, (a.rect as Rect2).grow(-4))
			elif a.key == "ground":
				ok = true
			else:
				var g: ItemGrid = a.grid
				var c: Vector2i = h[1] - _grab
				var tgt := g.item_at(h[1].x, h[1].y)
				ok = g.fits(it, c.x, c.y, bool(it.get("r", false))) or (not tgt.is_empty() and _can_combine(it, tgt))
				hr.position = (a.rect as Rect2).position + Vector2(c) * _cell
		_board.draw_rect(hr, GOOD if ok else BAD)
		_draw_item(font, it, hr.grow(-2), bool(it.get("r", false)))
	if _pad_mode:
		_draw_pad_hints(font)


func _can_combine(it: Dictionary, target: Dictionary) -> bool:
	var d := ItemDB.get_def(it.id)
	var td := ItemDB.get_def(target.id)
	if it.id == target.id and int(d.get("stack", 1)) > int(target.n):
		return true
	if td.get("cat", "") == "gun" and td.ammo == it.id and int(target.a) < int(td.mag):
		return true
	return d.get("cat", "") == "attachment" and target.id in d.fits


## Fits an item's footprint inside a slot box, centred.
func _fit_rect(it: Dictionary, box: Rect2) -> Rect2:
	var s := Vector2(ItemGrid.dims(it, false))
	var k := minf(box.size.x / s.x, box.size.y / s.y)
	k = minf(k, _cell)
	var sz := s * k
	return Rect2(box.get_center() - sz * 0.5, sz)


func _draw_item(font: Font, it: Dictionary, r: Rect2, rotated: bool) -> void:
	var d := ItemDB.get_def(it.id)
	var col: Color = ItemDB.CAT_COLORS.get(d.get("cat", ""), Color(0.4, 0.4, 0.4))
	var sb: StyleBoxFlat = _item_box
	sb.bg_color = Color(col.darkened(0.25), 0.55)
	sb.border_color = Color(col.lightened(0.35), 0.55)
	_board.draw_style_box(sb, r)
	var tex := ItemIcons.texture
	if tex and ItemIcons.regions.has(it.id):
		var src: Rect2 = ItemIcons.regions[it.id]
		if rotated:
			# Draw rotated 90 degrees about the rect's centre.
			var c := r.get_center()
			_board.draw_set_transform(c, PI * 0.5, Vector2.ONE)
			var rs := Vector2(r.size.y, r.size.x)
			_board.draw_texture_rect_region(tex, Rect2(-rs * 0.5, rs), src)
			_board.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			_board.draw_texture_rect_region(tex, r, src)
	else:
		var label: String = d.get("name", it.id)
		_text(font, r.position + Vector2(4, 14), label.left(int(r.size.x / 7.5)), 11, Color(0.95, 0.95, 0.9))
	var fs := 13
	if int(it.get("n", 1)) > 1:
		var t := "x%d" % int(it.n)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_text(font, r.end - Vector2(w + 4, 4), t, fs, Color.WHITE)
	if d.get("cat", "") == "gun":
		_text(font, Vector2(r.position.x + 4, r.end.y - 4), "%d/%d" % [int(it.get("a", 0)), int(d.mag)], fs, Color(1, 0.95, 0.7))
	if it.has("c"):
		var c := float(it.c)
		var bar := Rect2(r.position.x + 4, r.position.y + 4, (r.size.x - 8) * c, 3)
		_board.draw_rect(Rect2(bar.position, Vector2(r.size.x - 8, 3)), Color(0, 0, 0, 0.5))
		_board.draw_rect(bar, Color(0.3, 0.8, 0.3) if c > 0.5 else (Color(0.9, 0.7, 0.2) if c > 0.25 else Color(0.9, 0.25, 0.2)))
	if it.get("j", false):
		_text(font, r.position + Vector2(4, 28), "JAMMED", 11, Color(1, 0.4, 0.3))


func _text(font: Font, pos: Vector2, t: String, fs: int, col: Color) -> void:
	_board.draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	_board.draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Gamepad button hints along the bottom.
func _draw_pad_hints(font: Font) -> void:
	var hints := [["ui_accept", "Put down" if not _held.is_empty() else "Pick up"], ["reload", "Quick move"],
		["flashlight", "Use / equip"], ["shove", "Rotate"], ["throw_quick", "Drop"], ["aim", "Sort"],
		["attack", "Take all"], ["sprint", "Gear" if _tab == "body" else "Body"], ["crouch", "Craft"],
		["ui_cancel", "Cancel" if not _held.is_empty() else "Close"]]
	var x := MARGIN
	var y := _board.size.y - 52.0
	for h in hints:
		var w := InputGlyphs.draw(_board, h[0], Vector2(x, y), 30.0, font)
		if w == 0.0:
			continue
		_text(font, Vector2(x + w + 6, y + 21), h[1], 16, Color(0.9, 0.9, 0.88))
		x += w + 18 + font.get_string_size(h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x


## The Body tab's right side: who you are, your injuries and how well your
## clothes protect each part of you.
func _draw_health(font: Font) -> void:
	var r := _health_rect
	if r.size.x <= 0.0 or player == null:
		return
	var ch := GameState.character
	var b := player.body
	_hy = r.position.y + 10.0
	_health_line(font, "%s - %s" % [ch.name, Character.BACKGROUNDS[ch.background].name], Color(0.9, 0.88, 0.8), 18)
	if not ch.traits.is_empty():
		_health_line(font, ", ".join(ch.traits.map(func(t: String) -> String: return Character.TRAITS[t].name)), Color(0.6, 0.6, 0.58), 13)
	_health_line(font, "Health %d%%" % int(player.health), Color(0.9, 0.4, 0.35) if player.health < 40.0 else Color(0.8, 0.85, 0.8), 16)
	if b.injuries.is_empty():
		_health_line(font, "No injuries", Color(0.6, 0.8, 0.6), 15)
	for inj in b.injuries:
		var bad: bool = float(inj.inf) >= Health.FEVER_AT or (not inj.b and not inj.s and float(Health.KINDS[inj.k].bleed) > 0.0)
		_health_line(font, Health.describe(inj), Color(1.0, 0.55, 0.45) if bad else Color(0.85, 0.82, 0.75), 13)
	if b.fever():
		_health_line(font, "Fever: an infected wound. Clean it or take antibiotics.", Color(1.0, 0.6, 0.3), 14)
	var sym := b.symptoms()
	if sym > 0.0:
		var msg := "You feel feverish and weak." if sym < 0.35 else ("Your veins are dark. You're turning." if sym < 0.75 else "Not much time left...")
		_health_line(font, msg + " Only the cure can stop it.", Color(0.95, 0.35, 0.3), 14)
	if b.antibiotics > 0.0:
		_health_line(font, "Antibiotics: %d h left" % ceili(b.antibiotics), Color(0.6, 0.8, 0.9), 13)
	if b.painkillers > 0.0:
		_health_line(font, "Painkillers: %d h left" % ceili(b.painkillers), Color(0.6, 0.8, 0.9), 13)
	_hy += 6.0
	_health_line(font, "Bite protection", Color(0.85, 0.82, 0.75), 15)
	for part in ["head", "torso", "arm_l", "leg_l"]:
		var area: String = {"head": "Head", "torso": "Torso", "arm_l": "Arms", "leg_l": "Legs"}[part]
		var p := _inv().protection(part, "bite")
		_health_line(font, "%s  %d%%" % [area, int(p * 100.0)], Color(0.7, 0.75, 0.7), 13)
	_health_line(font, "Warmth %.1f" % _inv().warmth(), Color(0.7, 0.75, 0.7), 13)


func _health_line(font: Font, t: String, col: Color, fs: int) -> void:
	var r := _health_rect
	if _hy < r.end.y - 8.0:
		_board.draw_string(font, Vector2(r.position.x + 12.0, _hy), t, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24.0, fs, col)
	_hy += fs + 7.0
