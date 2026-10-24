class_name Hints
extends Node
## Contextual tips, each shown the first time it matters (first zombie
## nearby, first night, first bite, first car...), once per device. They
## can be turned off in Settings. Shown by the HUD's tip panel.
##
## Also runs the optional tutorial: a short checklist of the basics, in a
## world made for it (main menu → Tutorial).

signal show_tip(title: String, text: String)

const TIPS := {
	"start": ["Survive", "Find food, water and shelter. Search fridges, cabinets and car trunks. Your bars are top-left; trouble shows under them."],
	"zombie_near": ["Zombies", "They hear noise and see movement. Crouch to sneak; the eye on screen fills as one notices you. Gunshots carry for a hundred metres."],
	"night": ["Night", "Night is dark and zombies are faster. Use your flashlight sparingly - they see it - or hole up somewhere safe."],
	"bitten": ["Bitten", "A bite that breaks the skin can infect you. Bandage the wound (quick heal). Only a cure vial from a research centre stops the infection."],
	"bleeding": ["Bleeding", "You're losing blood. Use a bandage or a rag (quick heal picks the right treatment)."],
	"hungry": ["Hungry", "Eat something (quick eat). Fresh food spoils; canned food lasts."],
	"thirsty": ["Thirsty", "Drink something. River water makes you sick unless you boil it or use purification tablets."],
	"tired": ["Tired", "Sleep in a bed, a sleeping bag or, if you must, on the ground. Time passes fast while you sleep."],
	"cold": ["Cold", "Get inside, dry off, wear warmer clothes or sit by a fire. Freezing will kill you."],
	"vehicle": ["Vehicles", "Walk up to a car and press Use for its menu. Most need fuel, a battery, keys or hotwiring. Engines are loud."],
	"loot": ["Looting", "Drag items between your bag and the container, or double-tap to move them. Heavy loads slow you down."],
	"crafting": ["Crafting", "All recipes are known; you need the materials and tools. A workbench unlocks bigger ones, a fire lets you cook. Build from the Build tab."],
	"rain": ["Rain", "Rain soaks you and chills you, but it also dulls zombies' hearing and sight. Rain collectors catch clean water."],
	"gun": ["Guns", "Aim down the sights for accuracy. Every shot is heard far away - zombies (and hordes) come running."],
	"horde": ["Horde", "A horde is close. Dozens of zombies moving together. Don't fight it in the open: hide, or get away."],
	"trader": ["Traders", "A trader camp: no zombies get in, no fighting. Barter what you carry for what you need."],
	"dog": ["A dog", "Strays can be won over with dog food or meat. A dog follows you, warns you of zombies and fights them."],
	"fever": ["Infected wound", "A dirty wound got infected. Clean it with alcohol wipes or a first aid kit, or take antibiotics."],
	"turning": ["Turning", "The zombie infection is taking hold. Antibiotics slow it; only the cure stops it."],
}

## Tutorial steps: [text, check].
const STEPS := [
	["Look around and walk (left side of the screen / WASD / left stick).", "moved"],
	["Search a container: walk up to a cabinet or fridge and press Use.", "looted"],
	["Open your inventory and equip the hammer in your bag.", "armed"],
	["A zombie is coming. Hit it until it stays down.", "killed"],
	["Eat or drink something (quick eat).", "ate"],
	["Open crafting (Craft in the inventory / K) and build a campfire from the Build tab.", "built"],
	["That's the basics. Explore, scavenge, and stay alive. (Leave from the pause menu.)", ""],
]

var game: Node
var player: Player
var tutorial := false
var step := 0
var _t := 0.0
var _start := Vector3.ZERO
var _kills0 := 0
var _hunger0 := 0.0


func _ready() -> void:
	tutorial = GameState.world.get("tutorial", false)


func tip(id: String) -> void:
	if not GameState.settings.get("hints", true) or GameState.hints_seen.has(id) or not TIPS.has(id):
		return
	GameState.hints_seen[id] = true
	GameState.save_settings()
	show_tip.emit(TIPS[id][0], TIPS[id][1])


func _process(delta: float) -> void:
	if player == null or not player.active or player.dead:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var p := player
	tip("start")
	if game.zombies and not game.zombies.in_radius(p.global_position, 22.0).is_empty():
		tip("zombie_near")
	if GameState.is_night():
		tip("night")
	if p.body.has("bite"):
		tip("bitten")
	if p.body.bleeding():
		tip("bleeding")
	if p.hunger < 40.0:
		tip("hungry")
	if p.thirst < 40.0:
		tip("thirsty")
	if p.fatigue > 70.0:
		tip("tired")
	if p.cold > 40.0:
		tip("cold")
	if Weather.raining() and not p.sheltered:
		tip("rain")
	if p.weapons.is_ranged():
		tip("gun")
	if p.body.fever():
		tip("fever")
	if p.body.symptoms() > 0.0:
		tip("turning")
	if game.vehicles and not game.vehicles.near(p.global_position, 6.0).is_empty():
		tip("vehicle")
	if game.traders and game.traders.in_safe_zone(p.global_position):
		tip("trader")
	if game.animals:
		for d in game.animals.dogs.values():
			if d.global_position.distance_to(p.global_position) < 15.0:
				tip("dog")
	if game.zombies and game.zombies.hordes:
		for id in game.zombies.hordes.active:
			tip("horde")
	if tutorial:
		_tutorial()


func current_step() -> String:
	return STEPS[step][0] if tutorial and step < STEPS.size() else ""


func _tutorial() -> void:
	if step == 0 and _start == Vector3.ZERO:
		_start = player.global_position
		_kills0 = GameState.kills
	var done := false
	match STEPS[step][1]:
		"moved":
			done = player.global_position.distance_to(_start) > 4.0
		"looted":
			done = not GameState.containers.is_empty()
		"armed":
			done = GameState.inventory.equip.melee.get("id", "") == "hammer"
		"killed":
			if game.zombies.active_count() == 0 or game.zombies.in_radius(player.global_position, 40.0).is_empty():
				var p := player.global_position + (-player.global_basis.z) * 12.0
				game.zombies._spawn(Vector3(p.x, game.gen.height(p.x, p.z), p.z), "walker")
				game.zombies._active[-1].see_player()
			done = GameState.kills > _kills0
		"ate":
			done = player.hunger > _hunger0 + 5.0 or player.thirst > 95.0
		"built":
			done = not GameState.ws.structures.is_empty()
	if done:
		step += 1
		GameState.notify("Done!")
		if step < STEPS.size() and STEPS[step][1] == "ate":
			player.hunger = minf(player.hunger, 55.0)
			_hunger0 = player.hunger
