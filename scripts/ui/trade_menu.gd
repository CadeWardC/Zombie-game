class_name TradeMenu
extends CanvasLayer
## Bartering with a trader. Left: what the trader has; right: what you
## carry. Tap (or press A on) items to put them on the table; the deal goes
## through when what you offer is worth at least what you ask for. No money:
## items for items.

var player: Player
var camp := ""
var trader_name := ""

var _bg: ColorRect
var _title: Label
var _theirs: VBoxContainer
var _mine: VBoxContainer
var _summary: Label
var _deal_btn: Button
var _ask := [] # Trader items you want (references into the stock).
var _give := [] # Your items on offer.


func _ready() -> void:
	layer = 9
	visible = false
	_bg = ColorRect.new()
	_bg.color = Color(0.03, 0.035, 0.035, 0.95)
	add_child(_bg)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 10)
	_bg.add_child(root)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	root.add_child(_title)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 20)
	root.add_child(cols)
	_theirs = _column(cols, "THEY HAVE")
	_mine = _column(cols, "YOU HAVE")
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	root.add_child(bottom)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.add_theme_font_size_override("font_size", 19)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	bottom.add_child(_summary)
	_deal_btn = _button("Trade", _deal, 180)
	bottom.add_child(_deal_btn)
	bottom.add_child(_button("Leave", close, 140))


func _column(parent: Node, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 18)
	t.modulate = Color(0.85, 0.82, 0.75)
	v.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list


func _button(text: String, cb: Callable, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 50)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b


func is_open() -> bool:
	return visible


func open(p_camp: String, p_name: String) -> void:
	camp = p_camp
	trader_name = p_name
	_ask.clear()
	_give.clear()
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


func _mine_items() -> Array:
	var out := []
	for g in GameState.inventory.grids():
		for it in g.items:
			if Barter.value(it) > 0 or it in _give:
				out.append(it)
	return out


func ask_value() -> int:
	var v := 0
	for it in _ask:
		v += Barter.value(it)
	return v


func give_value() -> int:
	var v := 0
	for it in _give:
		v += Barter.value(it)
	# A fair trader, but they take a cut.
	return int(v * 0.8)


func _rebuild() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var fname: String = str(focused.name) if focused else ""
	for list in [_theirs, _mine]:
		for c in list.get_children():
			list.remove_child(c)
			c.queue_free()
	_title.text = "TRADING WITH %s" % trader_name.to_upper()
	var k := 0
	for it in Barter.stock(camp):
		var b := _item_button(it, it in _ask)
		b.name = "t%d" % k
		b.pressed.connect(func() -> void: _toggle(_ask, it))
		_theirs.add_child(b)
		k += 1
	k = 0
	for it in _mine_items():
		var b := _item_button(it, it in _give)
		b.name = "m%d" % k
		b.pressed.connect(func() -> void: _toggle(_give, it))
		_mine.add_child(b)
		k += 1
	var a := ask_value()
	var g := give_value()
	_summary.text = "You ask for: %d   You offer: %d%s" % [a, g, "" if a == 0 or g >= a else "   (offer more)"]
	_deal_btn.disabled = a == 0 and g == 0 or g < a
	var target: Control = null
	if fname != "":
		target = _theirs.get_node_or_null(NodePath(fname))
		if target == null:
			target = _mine.get_node_or_null(NodePath(fname))
	if target == null and _theirs.get_child_count() > 0:
		target = _theirs.get_child(0)
	if target:
		target.grab_focus.call_deferred()


func _item_button(it: Dictionary, chosen: bool) -> Button:
	var n := int(it.get("n", 1))
	var b := _button("%s%s%s   (%d)" % ["> " if chosen else "", ItemDB.item_name(it.id), " x%d" % n if n > 1 else "", Barter.value(it)], func() -> void: pass, 0)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.modulate = Color(1.0, 0.85, 0.45) if chosen else Color.WHITE
	return b


func _toggle(list: Array, it: Dictionary) -> void:
	if it in list:
		list.erase(it)
	else:
		list.append(it)
	_rebuild()


## Swap the goods: yours go to the trader's stock (they'll sell them on).
func _deal() -> void:
	if give_value() < ask_value() or (_ask.is_empty() and _give.is_empty()):
		return
	var stock := Barter.stock(camp)
	for it in _give:
		GameState.inventory.detach(it)
		stock.append(Inventory._clean(it))
	for it in _ask:
		stock.erase(it)
		GameState.add_item(it, player.global_position)
	GameState.inventory.notify()
	GameState.notify("Deal. %s nods." % trader_name)
	Net.trader_stock(camp, stock)
	_ask.clear()
	_give.clear()
	_rebuild()
