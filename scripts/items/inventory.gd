class_name Inventory
extends RefCounted
## What the survivor carries: pocket grid, equipment slots (weapons, backpack,
## vest) and the grids the backpack and vest add. Pure data plus rules, so it
## saves as JSON and could later be synced in multiplayer.

signal changed

const POCKETS := Vector2i(4, 2)
const CARRY_KG := 20.0 # Comfortable load; more slows you down.
const MAX_KG := 45.0

var pockets: ItemGrid
var equip := {}


func _init() -> void:
	pockets = ItemGrid.new("pockets", "Pockets", POCKETS.x, POCKETS.y, [])
	pockets.limit = 2
	for s in ItemDB.SLOTS:
		equip[s] = {}


## The grids you carry, in display order: pockets, vest, backpack.
func grids() -> Array[ItemGrid]:
	var out: Array[ItemGrid] = [pockets]
	for s in ["vest", "back"]:
		var bag: Dictionary = equip[s]
		if not bag.is_empty():
			var d := ItemDB.get_def(bag.id)
			var g := ItemGrid.new(s, d.name, int(d.gw), int(d.gh), bag.items)
			g.limit = 2 if s == "vest" else 0
			out.append(g)
	return out


func notify() -> void:
	changed.emit()


## Picks up an item: fills an empty matching slot first (a gun, a bag), then
## the grids. Returns how many didn't fit.
func add(it: Dictionary, auto_equip := true) -> int:
	var slot := ItemDB.slot_for(it.id)
	if auto_equip and slot != "" and equip[slot].is_empty() and int(it.get("n", 1)) <= int(ItemDB.get_def(it.id).get("stack", 1)):
		equip[slot] = it
		it.erase("x")
		it.erase("y")
		it.erase("r")
		notify()
		return 0
	# Throwables top up the equipped stack.
	var th: Dictionary = equip.throw
	var left := int(it.get("n", 1))
	if not th.is_empty() and th.id == it.id:
		var room := int(ItemDB.get_def(it.id).get("stack", 1)) - int(th.n)
		var moved := mini(room, left)
		th.n = int(th.n) + moved
		left -= moved
	if left > 0:
		var rest := it.duplicate(true)
		rest.n = left
		for g in grids():
			left = g.add(rest)
			if left == 0:
				break
			rest.n = left
	notify()
	return left


func count(id: String) -> int:
	var n := 0
	for g in grids():
		n += g.count(id)
	var th: Dictionary = equip.throw
	if not th.is_empty() and th.id == id:
		n += int(th.n)
	return n


## Removes up to `n` of an item from the grids; returns how many were taken.
func take(id: String, n: int) -> int:
	var taken := 0
	for g in grids():
		taken += g.take(id, n - taken)
		if taken >= n:
			break
	if taken > 0:
		notify()
	return taken


## The first item with this id in the grids (empty if none).
func find(id: String) -> Dictionary:
	for g in grids():
		for o in g.items:
			if o.id == id:
				return o
	return {}


## The grid holding an item, by identity (null if it's in a slot or nowhere).
func grid_of(it: Dictionary) -> ItemGrid:
	for g in grids():
		if g.index_of(it) >= 0:
			return g
	return null


func slot_of(it: Dictionary) -> String:
	for s in equip:
		if is_same(equip[s], it):
			return s
	return ""


## Removes an item from wherever it is (grid or slot).
func detach(it: Dictionary) -> void:
	var g := grid_of(it)
	if g:
		g.remove(it)
	var s := slot_of(it)
	if s != "":
		equip[s] = {}


## Can `it` go in equipment slot `slot`?
func slot_accepts(slot: String, it: Dictionary) -> bool:
	if ItemDB.slot_for(it.id) != slot:
		return false
	# A bag can't be worn inside itself, and can't hold the bag it replaces.
	return int(it.get("n", 1)) <= int(ItemDB.get_def(it.id).get("stack", 1))


func weight() -> float:
	var kg := 0.0
	for s in equip:
		if not equip[s].is_empty():
			kg += ItemDB.weight(equip[s])
	kg += pockets.weight()
	return kg


## 1.0 when lightly loaded, down to 0.5 at MAX_KG.
func speed_factor() -> float:
	var kg := weight()
	if kg <= CARRY_KG:
		return 1.0
	return lerpf(1.0, 0.5, clampf((kg - CARRY_KG) / (MAX_KG - CARRY_KG), 0.0, 1.0))


func clear() -> void:
	pockets.items.clear()
	for s in equip:
		equip[s] = {}
	notify()


## Every item carried, flattened (used when dropping everything on death).
func all_items() -> Array:
	var out: Array = []
	for s in equip:
		if not equip[s].is_empty():
			out.append(equip[s])
	out.append_array(pockets.items)
	return out


func to_dict() -> Dictionary:
	return {"pockets": pockets.items.duplicate(true), "equip": equip.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	clear()
	for it in d.get("pockets", []):
		pockets.items.append(_clean(it))
	var eq: Dictionary = d.get("equip", {})
	for s in ItemDB.SLOTS:
		var it: Dictionary = eq.get(s, {})
		equip[s] = _clean(it) if not it.is_empty() else {}
	# Drop anything whose definition no longer exists (old saves).
	pockets.items = pockets.items.filter(func(o: Dictionary) -> bool: return ItemDB.ITEMS.has(o.id))
	for s in equip:
		if not equip[s].is_empty() and not ItemDB.ITEMS.has(equip[s].id):
			equip[s] = {}
	notify()


## JSON turns ints into floats; put the integer fields back.
static func _clean(it: Dictionary) -> Dictionary:
	var o := it.duplicate(true)
	for k in ["n", "x", "y", "a"]:
		if o.has(k):
			o[k] = int(o[k])
	if o.has("r"):
		o.r = bool(o.r)
	if o.has("items"):
		var sub: Array = []
		for s in o.items:
			sub.append(_clean(s))
		o.items = sub
	return o
