class_name ItemGrid
extends RefCounted
## A Tetris-style grid of items (pockets, a bag, a container). Wraps an Array
## of item dictionaries by reference, so a bag's grid edits the bag's own
## "items" list and a container's grid edits GameState's saved list.

var key: String
var title: String
var w: int
var h: int
var items: Array
## Longest item side this grid accepts (0 = any). Pockets and vests only take
## small things; long guns and bats need a backpack or a slot.
var limit := 0


func _init(p_key: String, p_title: String, p_w: int, p_h: int, p_items: Array) -> void:
	key = p_key
	title = p_title
	w = p_w
	h = p_h
	items = p_items


## Footprint of an item, taking its rotation into account.
static func dims(it: Dictionary, rotated: Variant = null) -> Vector2i:
	var d := ItemDB.get_def(it.id)
	var r: bool = it.get("r", false) if rotated == null else rotated
	return Vector2i(int(d.get("h", 1)), int(d.get("w", 1))) if r else Vector2i(int(d.get("w", 1)), int(d.get("h", 1)))


func fits(it: Dictionary, x: int, y: int, rotated: bool, ignore: Dictionary = {}) -> bool:
	var s := dims(it, rotated)
	if x < 0 or y < 0 or x + s.x > w or y + s.y > h:
		return false
	if limit > 0 and maxi(s.x, s.y) > limit:
		return false
	var r := Rect2i(x, y, s.x, s.y)
	for o in items:
		if is_same(o, ignore) or is_same(o, it):
			continue
		if r.intersects(Rect2i(int(o.x), int(o.y), dims(o).x, dims(o).y)):
			return false
	return true


func item_at(x: int, y: int) -> Dictionary:
	for o in items:
		if Rect2i(int(o.x), int(o.y), dims(o).x, dims(o).y).has_point(Vector2i(x, y)):
			return o
	return {}


func place(it: Dictionary, x: int, y: int, rotated: bool) -> bool:
	if not fits(it, x, y, rotated):
		return false
	it.x = x
	it.y = y
	it.r = rotated
	if index_of(it) < 0:
		items.append(it)
	return true


## Position of this exact item (by identity, not by value) in the list.
func index_of(it: Dictionary) -> int:
	for k in items.size():
		if is_same(items[k], it):
			return k
	return -1


func remove(it: Dictionary) -> void:
	var k := index_of(it)
	if k >= 0:
		items.remove_at(k)


## First free spot for an item, trying both rotations. (-1, -1) if full.
func find_spot(it: Dictionary) -> Vector3i:
	for rot in [false, true]:
		var s := dims(it, rot)
		for y in h - s.y + 1:
			for x in w - s.x + 1:
				if fits(it, x, y, rot):
					return Vector3i(x, y, 1 if rot else 0)
	return Vector3i(-1, -1, 0)


## Adds as much of a stack as fits: tops up existing stacks first, then uses
## free space. Returns how many didn't fit (0 = all added).
func add(it: Dictionary) -> int:
	var d := ItemDB.get_def(it.id)
	var max_stack := int(d.get("stack", 1))
	var left := int(it.get("n", 1))
	if max_stack > 1:
		for o in items:
			if o.id == it.id and int(o.n) < max_stack:
				var moved := mini(max_stack - int(o.n), left)
				o.n = int(o.n) + moved
				# A mixed stack of fresh food goes off with its oldest piece.
				if it.has("exp"):
					o.exp = minf(float(o.get("exp", it.exp)), float(it.exp))
				left -= moved
				if left == 0:
					return 0
	while left > 0:
		var piece := it.duplicate(true)
		piece.n = mini(left, max_stack)
		var spot := find_spot(piece)
		if spot.x < 0:
			break
		place(piece, spot.x, spot.y, spot.z == 1)
		left -= int(piece.n)
	return left


func count(id: String) -> int:
	var n := 0
	for o in items:
		if o.id == id:
			n += int(o.n)
	return n


## Removes up to `n` of an item; returns how many were taken.
func take(id: String, n: int) -> int:
	var taken := 0
	for o in items.duplicate():
		if taken >= n:
			break
		if o.id != id:
			continue
		var t := mini(int(o.n), n - taken)
		o.n = int(o.n) - t
		taken += t
		if int(o.n) <= 0:
			remove(o)
	return taken


## Re-packs the grid, biggest items first, merging partial stacks.
func sort() -> void:
	var old := items.duplicate()
	var pool: Array = []
	for o in old:
		var merged := false
		for p in pool:
			if p.id == o.id and int(p.n) < int(ItemDB.get_def(o.id).get("stack", 1)):
				merged = true
				p.n = int(p.n) + int(o.n)
				if o.has("exp"):
					p.exp = minf(float(p.get("exp", o.exp)), float(o.exp))
				break
		if not merged:
			pool.append(o.duplicate(true))
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := dims(a, false)
		var sb := dims(b, false)
		if sa.x * sa.y != sb.x * sb.y:
			return sa.x * sa.y > sb.x * sb.y
		return str(a.id) < str(b.id))
	items.clear()
	for p in pool:
		if add(p) > 0:
			# Couldn't re-pack (shouldn't happen): put everything back.
			items.clear()
			items.append_array(old)
			return


func weight() -> float:
	var kg := 0.0
	for o in items:
		kg += ItemDB.weight(o)
	return kg
