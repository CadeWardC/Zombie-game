class_name PlayerActions
extends RefCounted
## The player's survival interactions, kept apart from Player to keep it
## readable: using built structures (crates, workbenches, campfires, beds,
## rain collectors, farm plots, gates, the watchtower ladder), dismantling
## and repairing them, boarding up windows, barricading doors, drinking and
## filling bottles at rivers and lakes, searching bushes for berries and
## mushrooms, fishing, and chopping trees for logs.
##
## Focus targets it adds: a StructureBody, {"wpos": water point},
## {"bpos": bush, "bid": id}.

const BUSH_REGROW := 72.0 # In-game hours before a bush has more to find.
const TREE_HP := 8.0 # Chop strength to fell a tree.

var p: Player
var _chops := {} # Tree id -> chop damage so far.
var _fish_t := -1.0 # Waiting for a bite (seconds), -1 when not fishing.
var _bite_t := 0.0 # A fish is on the hook: reel in before this runs out.
var _fish_spot := Vector3.ZERO


func _init(player: Player) -> void:
	p = player


func fishing() -> bool:
	return _fish_t >= 0.0 or _bite_t > 0.0


# --- Focus -------------------------------------------------------------------------------

func focus_structure(n: StructureBody) -> void:
	p._focus = n
	var r := n.rec
	var hp_note := "" if not n.damaged() else " (%d%%)" % int(100.0 * float(r.hp) / float(r.get("mhp", n.def.hp)))
	p.prompt = str(n.def.name) + hp_note
	match n.t:
		"crate":
			p.prompt = "Open crate" + hp_note
		"workbench":
			p.prompt = "Use workbench" + hp_note
		"bed":
			p.prompt = "Sleep" if p.can_sleep() else "Bed (not tired)"
		"campfire":
			if n.burning():
				p.prompt = "Cook (fire: %d h left)" % ceili(float(r.lit) - GameState.hours())
			elif float(r.get("wood", 0.0)) > 0.0:
				p.prompt = "Light the fire" if Recipes.has_tool("fire_starter") else "Campfire (need matches or a lighter)"
			else:
				p.prompt = "Campfire (out of wood)"
			if GameState.item_count("log") > 0:
				p.alt_prompt = "Add a log"
		"rain_collector":
			p.prompt = "Rain collector: %d L%s" % [int(r.get("water", 0.0)), "" if float(r.get("water", 0.0)) < 1.0 else " - drink or fill"]
		"gate":
			p.prompt = "Close gate" if r.get("open", false) else "Open gate"
		"watchtower":
			p.prompt = "Climb down" if p.global_position.y > n.global_position.y + 2.0 else "Climb up"
		"farm_plot":
			_focus_plot(n)
	# Take it apart (half the materials back), or patch it up.
	if n.t in ["campfire", "farm_plot"] or Recipes.has_tool("hammer"):
		p.hold_prompt = "take apart"
	if p.alt_prompt == "" and n.damaged() and Recipes.has_tool("hammer") and GameState.item_count("plank") >= 1 and GameState.item_count("nails") >= 2:
		p.alt_prompt = "Repair (plank, 2 nails)"


func _focus_plot(n: StructureBody) -> void:
	var c: Dictionary = n.rec.get("crop", {})
	if c.is_empty():
		var seeds := _seeds()
		if not Farming.can_plant():
			p.prompt = "Farm plot (too cold to plant)"
		elif seeds.is_empty():
			p.prompt = "Farm plot (needs seeds)"
		else:
			p.prompt = "Plant %s" % ItemDB.item_name(seeds.id).to_lower()
		return
	if c.k == "dead":
		p.prompt = "Clear the dead plants"
		return
	if Farming.ripe(c):
		p.prompt = "Harvest %s" % ItemDB.item_name(str(c.k)).to_lower()
		return
	p.prompt = "%s growing (%d%%%s)" % [ItemDB.item_name(str(c.k)), int(Farming.growth(c) * 100.0), "" if Farming.watered(c) else ", needs water"]
	if not Farming.watered(c) and not _water_source().is_empty():
		p.alt_prompt = "Water the crop"


## A carcass to butcher, or a dog (a stray to win over, or your own).
func focus_animal(a: Animal) -> bool:
	if a is Dog:
		var d := a as Dog
		if not d.alive():
			return false
		p._focus = d
		var food := _dog_food()
		if not d.tame():
			p.prompt = "Stray dog - give it %s" % ItemDB.item_name(food.id).to_lower() if not food.is_empty() else "Stray dog (it's hungry)"
		elif d.mine():
			p.prompt = "Tell your dog to %s" % ("follow" if d.rec.get("stay", false) else "stay")
			if not food.is_empty():
				p.alt_prompt = "Feed it"
		else:
			p.prompt = "A friend's dog"
		return true
	if a.alive() or a.butchered:
		return false
	p._focus = a
	p.prompt = "Butcher the %s" % str(a.def.name).to_lower() if Recipes.has_tool("knife") else "%s (you need a knife)" % a.def.name
	return true


func _dog_food() -> Dictionary:
	for id in ["dog_food", "raw_meat", "cooked_meat"]:
		var it := GameState.inventory.find(id)
		if not it.is_empty():
			return it
	return {}


func _feed_dog(d: Dog) -> void:
	var food := _dog_food()
	if food.is_empty():
		GameState.notify("You have nothing it wants to eat")
		return
	GameState.inventory.take(food.id, 1)
	GameState.notify(d.feed())


func focus_window(w: WindowBody) -> void:
	if w.boarded():
		p.prompt = "Boarded up"
		if _inside(w.global_position, w.global_basis.z) and _has_pry_tool():
			p.alt_prompt = "Pry the boards off"
		return
	if Recipes.has_tool("hammer") and GameState.item_count("plank") >= 2 and GameState.item_count("nails") >= 4:
		p.alt_prompt = "Board up (2 planks, 4 nails)"


func focus_door(d: DoorBody) -> void:
	if not d.can_barricade(p.global_position):
		return
	if d.barricaded():
		if _has_pry_tool():
			p.alt_prompt = "Pry the barricade off"
	elif Recipes.has_tool("hammer") and GameState.item_count("plank") >= 3 and GameState.item_count("nails") >= 6:
		p.alt_prompt = "Barricade (3 planks, 6 nails)"


## Nothing else in reach: water to drink or fish in, or a bush to search.
func focus_nature(from: Vector3, fwd: Vector3) -> bool:
	if p.gen == null:
		return false
	# Water: the look ray dipping under a river or lake surface nearby.
	for k in 8:
		var d := 0.8 + k * 0.5
		var pt := from + fwd * d
		var wl := p.gen.water_level(pt.x, pt.z)
		if wl > -INF and pt.y < wl + 0.25 and from.y - wl < 2.4:
			p._focus = {"wpos": Vector3(pt.x, wl, pt.z)}
			p.prompt = "Drink (unsafe water)"
			if not _fill_target().is_empty():
				p.alt_prompt = "Fill %s" % ItemDB.item_name(_fill_target().id).to_lower()
			if Recipes.has_tool("rod"):
				p.hold_prompt = "fish"
			return true
	# Fishing reaches farther than drinking.
	if Recipes.has_tool("rod"):
		for k in 6:
			var pt := from + fwd * (4.0 + k * 1.2)
			var wl := p.gen.water_level(pt.x, pt.z)
			if wl > -INF and pt.y < wl + 0.5:
				p._focus = {"wpos": Vector3(pt.x, wl, pt.z), "far": true}
				p.prompt = "Water"
				p.hold_prompt = "fish"
				return true
	if p.streamer:
		var bush := p.streamer.bush_near(from + fwd * 1.6, 1.4)
		if bush != Vector3.INF and bush.distance_to(p.global_position) < 2.8:
			var id := "b_%d_%d" % [int(bush.x * 2.0), int(bush.z * 2.0)]
			p._focus = {"bpos": bush, "bid": id}
			var picked := GameState.hours() - float(GameState.ws.forage.get(id, -999.0)) < BUSH_REGROW
			p.prompt = "Bush (picked clean)" if picked else "Search the bush"
			return true
	return false


# --- Actions -------------------------------------------------------------------------------

## Tap interact. Returns true if this handled it.
func interact(f: Variant) -> bool:
	if f is StructureBody:
		_use_structure(f)
		return true
	if f is Dog:
		var d := f as Dog
		if not d.tame():
			_feed_dog(d)
		elif d.mine():
			d.rec.stay = not bool(d.rec.get("stay", false))
			GameState.notify("Stay." if d.rec.stay else "Come on, let's go.")
		return true
	if f is Animal:
		if not Recipes.has_tool("knife"):
			GameState.notify("You need a knife to butcher it")
			return true
		var got := (f as Animal).butcher((f as Animal).global_position + Vector3(0, 0.5, 0))
		GameState.practice("foraging", 6.0)
		GameState.make_noise(p.global_position, 4.0)
		GameState.notify("You butcher the %s" % str((f as Animal).def.name).to_lower() if not got.is_empty() else "Nothing worth taking")
		return true
	if f is Dictionary and f.has("wpos"):
		if f.get("far", false):
			return true
		p.thirst = minf(100.0, p.thirst + 25.0)
		if randf() < 0.45:
			p.body.sick = minf(1.0, p.body.sick + 0.4)
			GameState.notify("You drink the murky water. It tastes wrong.")
		else:
			GameState.notify("You drink from the water")
		GameState.make_noise(p.global_position, 3.0)
		return true
	if f is Dictionary and f.has("bpos"):
		_forage(f)
		return true
	return false


## Hold interact. Returns true if handled.
func hold(f: Variant) -> bool:
	if f is StructureBody:
		_dismantle(f)
		return true
	if f is Dictionary and f.has("wpos"):
		_start_fishing(f.wpos)
		return true
	return false


## The second action button (R / X). Returns true if handled.
func alt(f: Variant) -> bool:
	if f is Dog:
		_feed_dog(f)
		return true
	if f is StructureBody:
		var n: StructureBody = f
		if n.t == "campfire" and GameState.item_count("log") > 0:
			GameState.inventory.take("log", 1)
			if n.burning():
				n.rec.lit = float(n.rec.lit) + Structures.LOG_HOURS
			else:
				n.rec.wood = float(n.rec.get("wood", 0.0)) + Structures.LOG_HOURS
			GameState.notify("Added a log to the fire")
			p.bases.changed(n.rec)
			return true
		if n.t == "farm_plot" and not n.rec.get("crop", {}).is_empty():
			if _use_water(1):
				Farming.water(n.rec)
				GameState.practice("farming", 2.0)
				GameState.notify("Watered the crop")
				p.bases.changed(n.rec)
			return true
		if n.damaged() and GameState.inventory.take("plank", 1) == 1:
			GameState.inventory.take("nails", 2)
			n.rec.hp = minf(float(n.rec.get("mhp", n.def.hp)), float(n.rec.hp) + float(n.def.hp) * 0.4)
			GameState.make_noise(n.global_position, 12.0)
			GameState.practice("carpentry", 4.0)
			GameState.notify("Patched up the %s" % str(n.def.name).to_lower())
			p.bases.changed(n.rec)
			return true
		return false
	if f is WindowBody:
		var w: WindowBody = f
		if w.boarded():
			w.remove_boards()
			GameState.add_item(ItemDB.make("plank", 1), p.global_position)
			GameState.notify("Pried the boards off")
		else:
			GameState.inventory.take("plank", 2)
			GameState.inventory.take("nails", 4)
			w.board_up(GameState.character.skill("carpentry"))
			GameState.practice("carpentry", 6.0)
			GameState.notify("Window boarded up")
		return true
	if f is DoorBody:
		var d: DoorBody = f
		if d.barricaded():
			d.remove_barricade()
			GameState.add_item(ItemDB.make("plank", 2), p.global_position)
			GameState.notify("Pried the barricade off")
		else:
			GameState.inventory.take("plank", 3)
			GameState.inventory.take("nails", 6)
			d.barricade(GameState.character.skill("carpentry"))
			GameState.practice("carpentry", 8.0)
			GameState.notify("Door barricaded")
		return true
	if f is Dictionary and f.has("wpos"):
		var it := _fill_target()
		if it.is_empty():
			return false
		if it.id == "glass_bottle":
			GameState.inventory.detach(it)
			GameState.add_item(ItemDB.make("dirty_water"), p.global_position)
			GameState.notify("Filled the bottle (boil or purify it before drinking)")
		else:
			it.u = int(ItemDB.get_def(it.id).get("uses", 1))
			GameState.inventory.notify()
			GameState.notify("Filled the %s" % ItemDB.item_name(it.id).to_lower())
		return true
	return false


func _use_structure(n: StructureBody) -> void:
	var r := n.rec
	match n.t:
		"crate":
			var ct := {"pos": n.global_position, "type": "crate", "bld": "", "id": "crate_" + str(r.id)}
			GameState.container_items(ct)
			p.open_inventory.emit(ct)
		"workbench":
			p.open_crafting.emit("")
		"bed":
			p.start_sleep(n)
		"campfire":
			if n.burning():
				p.open_crafting.emit("Food")
			elif float(r.get("wood", 0.0)) > 0.0:
				var fs := Recipes.find_tool("fire_starter")
				if fs.is_empty():
					GameState.notify("You need matches or a lighter")
					return
				fs.u = int(fs.get("u", 1)) - 1
				if int(fs.u) <= 0:
					GameState.inventory.detach(fs)
				GameState.inventory.notify()
				r.lit = GameState.hours() + float(r.wood)
				r.wood = 0.0
				GameState.notify("The fire catches")
				p.bases.changed(r)
			else:
				GameState.notify("Add a log first")
		"rain_collector":
			var water := float(r.get("water", 0.0))
			if water < 1.0:
				GameState.notify("It's empty. It fills when it rains.")
				return
			var filled := 0
			for g in GameState.inventory.grids():
				for it in g.items.duplicate():
					if it.id == "glass_bottle" and water >= 1.0:
						g.remove(it)
						GameState.add_item(ItemDB.make("water_bottle"), p.global_position)
						water -= 1.0
						filled += 1
			if filled == 0:
				p.thirst = minf(100.0, p.thirst + 30.0)
				water -= 1.0
				GameState.notify("You drink the clean rainwater")
			else:
				GameState.notify("Filled %d bottle%s with clean water" % [filled, "" if filled == 1 else "s"])
			r.water = water
			p.bases.changed(r)
		"gate":
			r.open = not bool(r.get("open", false))
			GameState.make_noise(n.global_position, 6.0)
			p.bases.changed(r)
		"watchtower":
			var s: Vector3 = n.def.size
			if p.global_position.y > n.global_position.y + 2.0:
				p.global_position = n.global_transform * Vector3(0, 0.1, s.z * 0.5 + 0.8)
			else:
				p.global_position = n.global_transform * Vector3(0, 3.15, 0)
			p.velocity = Vector3.ZERO
		"farm_plot":
			_use_plot(n)


func _use_plot(n: StructureBody) -> void:
	var r := n.rec
	var c: Dictionary = r.get("crop", {})
	if c.is_empty():
		var seeds := _seeds()
		if seeds.is_empty() or not Farming.can_plant():
			GameState.notify("Too cold to plant until spring" if not Farming.can_plant() else "You need seeds")
			return
		GameState.inventory.take(seeds.id, 1)
		Farming.plant(r, str(ItemDB.get_def(seeds.id).crop))
		GameState.practice("farming", 4.0)
		GameState.notify("Planted %s. Keep it watered." % ItemDB.item_name(seeds.id).to_lower())
	elif c.k == "dead":
		r.crop = {}
		GameState.notify("Cleared the plot")
	elif Farming.ripe(c):
		for it in Farming.harvest(r, GameState.character.skill("farming")):
			GameState.add_item(it, n.global_position + Vector3(0, 0.5, 0))
		GameState.practice("farming", 15.0)
		GameState.notify("Harvested the crop")
	else:
		return
	p.bases.changed(r)


func _dismantle(n: StructureBody) -> void:
	for it in Structures.refund(n.t):
		GameState.add_item(it, n.global_position + Vector3(0, 0.5, 0))
	GameState.make_noise(n.global_position, 10.0)
	GameState.notify("Took the %s apart" % str(n.def.name).to_lower())
	p.bases.remove(str(n.rec.id))


func _forage(f: Dictionary) -> void:
	var id: String = f.bid
	if GameState.hours() - float(GameState.ws.forage.get(id, -999.0)) < BUSH_REGROW:
		GameState.notify("Nothing left here")
		return
	GameState.ws.forage[id] = GameState.hours()
	Net.foraged(id)
	var skill := GameState.character.skill("foraging")
	var season := Weather.season()
	var pos: Vector3 = f.bpos
	var forest := p.gen.terrain.biome_at(pos.x, pos.z, p.gen.terrain.macro_height(pos.x, pos.z)) == Terrain.Biome.FOREST
	var found: Array = []
	if season in ["Summer", "Autumn"] and randf() < 0.5 + skill * 0.05:
		found.append(ItemDB.make("berries", 1 + randi() % (2 + skill / 3)))
	if season in ["Spring", "Autumn"] and randf() < (0.45 if forest else 0.2) + skill * 0.04:
		var m := ItemDB.make("mushrooms")
		if randf() < maxf(0.05, 0.35 - skill * 0.04):
			m.poison = true
		found.append(m)
	if season == "Winter":
		GameState.notify("Nothing grows in winter")
		return
	if found.is_empty():
		GameState.notify("You find nothing useful")
		GameState.practice("foraging", 1.0)
		return
	for it in found:
		GameState.add_item(it, pos + Vector3(0, 0.4, 0))
	GameState.practice("foraging", 6.0)
	GameState.make_noise(pos, 3.0)


func _start_fishing(spot: Vector3) -> void:
	_fish_spot = spot
	_fish_t = randf_range(6.0, 20.0) * (0.7 if Weather.raining() else 1.0)
	_bite_t = 0.0
	GameState.notify("You cast the line... wait for a bite")


## Called every frame while fishing (from Player). Moving away cancels.
func update_fishing(delta: float) -> void:
	if not fishing():
		return
	if p.global_position.distance_to(_fish_spot) > 14.0 or p.velocity.length() > 2.5:
		_fish_t = -1.0
		_bite_t = 0.0
		GameState.notify("You reel the line in")
		return
	if _bite_t > 0.0:
		_bite_t -= delta
		p.prompt = "Reel it in!"
		p.prompt_action = "interact"
		if Input.is_action_just_pressed("interact"):
			_bite_t = 0.0
			_fish_t = -1.0
			if randf() < 0.65 + GameState.character.skill("foraging") * 0.03:
				GameState.add_item(ItemDB.make("raw_fish"), p.global_position)
				GameState.practice("foraging", 8.0)
				GameState.notify("You caught a fish!")
			else:
				GameState.notify("It got away")
		elif _bite_t <= 0.0:
			_fish_t = -1.0
			GameState.notify("It got away")
		return
	_fish_t -= delta
	p.prompt = "Fishing..."
	if _fish_t <= 0.0:
		_fish_t = -1.0
		_bite_t = 1.8
		GameState.notify("Something's biting!")


## A swing with an axe hit near `pos`: chop the nearest tree.
func chop(pos: Vector3, power: float) -> bool:
	if p.streamer == null:
		return false
	var tr := p.streamer.tree_near(pos, 1.3)
	if tr.is_empty():
		return false
	var hits := float(_chops.get(tr.id, 0.0)) + power * (1.0 + GameState.character.skill("strength") * 0.05)
	_chops[tr.id] = hits
	GameState.make_noise(pos, 20.0)
	if Effects.current:
		Effects.current.burst(pos, (p.global_position - pos).normalized(), Color(0.55, 0.4, 0.25), 8, 2.5)
	if hits < TREE_HP:
		return true
	_chops.erase(tr.id)
	p.streamer.fell_tree(tr.id)
	Net.tree_felled(tr.id)
	var logs := 0 if tr.mm == "cactus" else (1 if tr.mm == "dead_tree" else 2 + randi() % 2)
	var at: Vector3 = tr.pos
	for k in logs:
		GameState.drop_item(ItemDB.make("log"), at + Vector3(cos(k * 2.1) * 0.8, 0.4, sin(k * 2.1) * 0.8))
	GameState.make_noise(at, 35.0)
	GameState.practice("strength", 5.0)
	GameState.notify("Timber!" if logs > 0 else "You cut it down")
	return true


# --- Helpers -----------------------------------------------------------------------------

func _inside(at: Vector3, normal: Vector3) -> bool:
	# Indoors is the side with a roof over it.
	var side := 1.0 if (p.global_position - at).dot(normal) > 0.0 else -1.0
	var probe := at + normal * side * 1.0 + Vector3(0, 0.5, 0)
	var up := p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(probe, probe + Vector3(0, 8.0, 0), 1, [p.get_rid()]))
	return not up.is_empty()


func _has_pry_tool() -> bool:
	return Recipes.has_tool("hammer") or GameState.inventory.equip.melee.get("id", "") == "crowbar" or GameState.item_count("crowbar") > 0


func _seeds() -> Dictionary:
	for g in GameState.inventory.grids():
		for it in g.items:
			if ItemDB.get_def(it.id).get("cat", "") == "seed":
				return it
	return {}


## An empty bottle to fill with river water, or a watering can that isn't full.
func _fill_target() -> Dictionary:
	for g in GameState.inventory.grids():
		for it in g.items:
			if it.id == "glass_bottle":
				return it
			if it.id == "watering_can" and int(it.get("u", 0)) < int(ItemDB.get_def("watering_can").uses):
				return it
	return {}


## Something to water crops with: a watering can with water, or a bottle.
func _water_source() -> Dictionary:
	for g in GameState.inventory.grids():
		for it in g.items:
			if it.id == "watering_can" and int(it.get("u", 0)) > 0:
				return it
	for id in ["dirty_water", "water_bottle"]:
		var it := GameState.inventory.find(id)
		if not it.is_empty():
			return it
	return {}


func _use_water(n: int) -> bool:
	var it := _water_source()
	if it.is_empty():
		GameState.notify("You need a watering can or a bottle of water")
		return false
	if it.id == "watering_can":
		it.u = int(it.u) - n
	else:
		GameState.inventory.detach(it)
		GameState.add_item(ItemDB.make("glass_bottle"), p.global_position)
	GameState.inventory.notify()
	return true
