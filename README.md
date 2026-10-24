# Zombie Survival

An open-world, first-person zombie survival sandbox for **Android and iOS**,
built with **Godot 4.7** and designed to run well on phones and tablets
(minimum target: Samsung Galaxy Tab S6 Lite). The full plan is in
[docs/DESIGN.md](docs/DESIGN.md).

**What's in the game now (stages 1 to 7):**

- **Random worlds of 8, 16 or 32 km**: coastlines, mountains, forests,
  farmland, deserts, beaches, and river networks with lakes from a drainage
  simulation.
- **A real road network**: interstates between cities, two-lane roads to
  towns, bridges over rivers, gas stations along the way.
- **American towns and cities**:
  - villages at crossroads
  - towns with a Main Street of shops
  - city downtowns with towers
  - suburbs with cul-de-sacs
  - police and fire stations, churches with graveyards, schools,
    hospitals, malls and motels
- **Special sites**: airports (runway, terminal, tower, hangars, planes and
  helicopters) and remote research centers.
- **Houses you can enter**: five house styles plus trailers, with rooms,
  stairs, doors that open, and furniture.
- **Tetris inventory**: pockets, a vest and a backpack, each with its own
  grid; weapon, bag and vest slots. Items have shapes (a rifle is 5 x 1),
  weight slows you down, long things don't fit in pockets. Drag and drop,
  rotate, double-tap to move, auto-sort, take all. Fully playable with a
  gamepad.
- **Loot that makes sense**: about 50 items. Fridges, cabinets, dressers,
  shelves, lockers and car trunks are rolled once per world, from pools
  that depend on the building (a police locker vs. a school locker).
  Containers stay as you left them. Guns are uncommon.
- **Weapons**:
  - melee: knives, hammer, crowbar, machete, bat, fire axe and
    sledgehammer. Each one wears out.
  - guns: pistol, revolver, pump shotgun, hunting rifle and assault rifle.
    You can aim down the sights. They have recoil, reload from loose ammo
    and jam when worn.
  - attachments: scope, red dot, suppressor and weapon light.
  - bows: a compound bow and a crossbow, with arrows you can recover.
  - throwables: bottles and alarm clocks to distract, molotovs, grenades,
    and bear traps.
  - a shove for when you're surrounded.
- **Stealth**: zombies grow suspicious before they chase you (the eye on
  the HUD shows it). Crouch, hide in bushes or dark rooms, and do silent
  takedowns from behind. Gunshots carry for a hundred metres.
- **Your survivor**: a name, a look (body, skin, hair, beard, shown on a
  turning 3D preview), one of ten backgrounds (nurse, police officer,
  mechanic, hunter...) with skills and starting gear, and traits: good
  ones cost points, bad ones give them (athletic, strong, keen hearing,
  short-sighted, smoker, hemophiliac...).
- **Injuries**: scratches, lacerations, deep wounds, bites, broken bones,
  sprains and burns, each with its own effect. Bandages and rags stop
  bleeding, deep wounds need stitches, broken bones a splint; dirty wounds
  get infected and bring on a fever unless cleaned. Hard falls hurt. Quick
  heal picks the right treatment.
- **Clothes**: hats and helmets, shirts, jackets, armour, pants and boots.
  They decide whether a bite breaks the skin, wear out as zombies tear at
  them, add pockets, and can be mended with a sewing kit or ripped into
  rags.
- **The infection**: a bite that breaks the skin can infect you (15% by
  default). Over a day or two your sight blurs and fades, your heart
  pounds, you cough (zombies hear it) and weaken. Antibiotics slow it; only
  a cure vial stops it. If it wins, you rise as a zombie carrying your
  gear.
- **Research centres**: the only source of the cure. A small dungeon:
  start the generator outside (loud), find the blue keycard in the
  security room and the red one in the director's office, and fight
  through labs and containment to the vault.
- **Zombie types**: walkers, runners (fast, more at night), brutes (huge,
  break doors), screamers (shriek to call every zombie around), crawlers
  (lie low, grab ankles) and armoured soldiers around the labs. Some wait
  inside buildings. Zombies open unlocked doors, batter locked ones while
  they know you're inside, smash windows and crawl through, and climb low
  fences. They can't swim.
- **Doors and windows**: lock doors from the inside, break locked ones
  down, smash windows and climb through.
- **Survival**: health, hunger, thirst, stamina, a day/night cycle and
  swimming.
- **Death rules**, fixed when the world is made: respawn (keep your
  character), new character, or permadeath. Lost worlds stay in the menu as
  memorials with the survivor's story and the map they explored. The pause
  menu has a map of everywhere you've been.
- **Main menu with multiple saved worlds**: choose map size, seed,
  difficulty, death rule, zombie speed, infection chance and PvP, then your
  survivor.
- **Multiplayer on the same Wi-Fi, 2–4 players**: pause and tap **Invite
  Friends**; on the other phones, **Join Game** lists the games nearby by
  themselves. The host's device runs the world (zombies around everyone,
  loot, doors, windows, the generator, the clock) and saves it, including
  each guest's survivor for next time. You see each other's survivors in
  their clothes (paler when infected), share containers and dropped items,
  and can **ping** a spot, a zombie, loot, or call for help. A friend who
  dies infected rises as a zombie: beat them down and give them a cure vial
  to bring them back. In permadeath worlds the dead watch the living, and
  the world is lost only when everyone is out. PvP is a world setting.
  (Playing over the internet with join codes needs a relay server and is
  left for later.)

- **Vehicles**: every parked car, bike and aircraft can be used, though
  most cars need work first: fuel, a battery, a spare tire, engine parts,
  keys or hotwiring (a screwdriver, or a mechanic's skill), and breaking in
  can set off the alarm. Bicycles (silent), motorbikes, cars, vans,
  pickups, ambulances and school buses; rowboats and motorboats at docks
  (zombies can't swim after you); helicopters and light aircraft at
  airports. Fill gas cans at gas station pumps and jet fuel at airports.
  Engines, horns and alarms are loud; run zombies over (it dents the car);
  closed cars keep them out until they batter their way in. Trunks travel
  with their car. Friends ride along in multiplayer.

- **Survival depth**:
  - skills that grow as you use them;
  - crafting from materials and tools (all recipes known; a workbench for
    the bigger ones, a fire for cooking);
  - building walls, gates, spikes, watchtowers, crates, beds, workbenches,
    campfires, rain collectors and farm plots, and boarding up windows and
    barricading doors;
  - food that spoils, cooking, dirty water to boil or purify, and food
    poisoning;
  - sleep and fatigue, body temperature, getting wet;
  - weather (rain, storms, fog, snow) and seasons;
  - power that fails after a couple of weeks, and a power plant to restart;
  - farming, foraging, fishing, hunting deer, rabbits and turkeys, chopping
    trees;
  - trader camps to barter at (safe zones);
  - a dog to tame that follows you and fights for you.

- **Polish**: sound everywhere (synthesized in code: guns, footsteps,
  zombies you can locate by their groans, doors, glass, weather, engines,
  wind, birds and crickets, menu music); roaming hordes drawn to noise,
  and cleared areas that slowly fill back up; first-time tips and a short
  tutorial; a settings screen (graphics, field of view, volumes,
  sensitivity, invert look, aim assist, minimal HUD, tips, remappable
  keys and gamepad buttons).

All art (terrain, buildings, furniture, cars, aircraft, zombies, items and
their inventory icons) is generated in code as realistic low-poly geometry,
so the app stays small and needs no art files. Every sound is synthesized in
code too.

## Controls

| Action       | Touch                     | Keyboard / mouse | Gamepad       |
|--------------|---------------------------|------------------|---------------|
| Move         | Left side: floating stick | WASD / arrows    | Left stick    |
| Look         | Drag on the right side    | Mouse            | Right stick   |
| Attack / fire / throw (hold to draw a bow or wind up a throw) | FIRE / HIT | Left click | RT |
| Aim down sights | AIM (toggle)           | Right click      | LT            |
| Reload / clear a jam | RELOAD            | R                | X             |
| Shove        | SHOVE                     | V                | RB            |
| Quick throw  | –                         | G                | LB            |
| Use (doors, search, pick up, climb through a smashed window) | USE | E | B |
| Lock / unlock a door (from inside), start a generator | hold USE | hold E | hold B |
| Crouch / sneak | CROUCH                  | C / Ctrl         | R3            |
| Sprint       | RUN (toggle)              | Shift            | L3            |
| Jump / swim up | JUMP                    | Space            | A             |
| Switch weapon | WEAPON                   | 1-4 / wheel      | D-pad left / right |
| Eat or drink / heal | EAT / HEAL         | Z / H            | D-pad up / down |
| Inventory    | BAG                       | Tab / I          | View / Select |
| Flashlight   | LIGHT                     | F                | Y             |
| Pause (map, invite friends) | II         | Esc / P          | Start         |
| Ping (tap: mark what you look at; hold: call for help) | PING (multiplayer) | Q | Share / Capture |
| Crafting, building, skills | Inventory → CRAFT | K | R3 in the inventory |
| Second action (board up, add a log, water, feed the dog...) | the reload button (relabelled) | R | X |
| Debug stats  | –                         | F3               | –             |

**Driving** (walk up to a vehicle and press Use for its menu):

| Action | Touch | Keyboard / mouse | Gamepad |
|---|---|---|---|
| Steer, throttle, reverse (planes: pull back to climb) | Stick | WASD | Left stick |
| Brake / handbrake; helicopter up; plane throttle up | BRAKE / UP / THROTTLE+ | Space | A |
| Helicopter down; plane throttle down | DOWN / THROTTLE- | C / Ctrl | R3 |
| Look around (chase camera) | Drag | Mouse | Right stick |
| Start the engine again | START | R | X |
| Horn | HORN | Left click | RT |
| Headlights | LIGHTS | F | Y |
| Get out | EXIT | E | B |

On screen, button prompts match the controller you're using: Xbox
letters, PlayStation shapes, Nintendo letters, or keyboard keys. Menus work
with the gamepad too. In the inventory:
- A picks up and puts down; X quick-moves; Y uses or equips;
- RB rotates; LB drops;
- LT sorts; RT takes everything;
- L3 switches between the Gear and Body tabs (clothes, injuries);
- B cancels or closes.

On gamepads, aim assist slows your aim and pulls it gently toward a zombie
near the crosshair while you aim down sights.

## How it stays fast on phones

A huge world only works on mobile if the game only does work near the
player.

| Technique | Where |
|---|---|
| **World plan once, chunks on demand**: terrain, rivers, towns and roads are planned when the world is created (seconds); 64 m chunks are built from that plan as you move | `world/world_gen.gd` |
| **Background threads**: chunks are built on `WorkerThreadPool`; world generation runs on a thread behind a progress screen | `world/world_streamer.gd`, `main.gd` |
| **Frame budget**: turning chunk data into nodes, collision and doors is spread across frames within 3 ms each | `world_streamer.gd`, `chunk.gd` |
| **Level of detail**: near chunks have 2 m terrain, interiors, doors, collision; far chunks have 8 m terrain, building shells, half the trees and simpler tree meshes | `chunk_builder.gd` |
| **Batching**: all buildings in a chunk are one mesh; trees, cars and props are MultiMeshes; all doors in a chunk are one MultiMesh | `chunk.gd` |
| **Cheap collision**: each building's walls and furniture are baked into one concave shape on the worker thread | `chunk_builder.gd` |
| **Zombie LOD**: full physics and smooth animation up close; cheap terrain-following movement and choppier animation farther away; pooling; spread-out raycasts | `zombies/` |
| **Dynamic resolution** and **quality presets** (view distance, shadows, zombie cap, FPS target, per-vertex lighting) | `core/performance_monitor.gd`, `core/game_state.gd` |
| **Fog-hidden draw distance**, Mobile renderer, colour background instead of a sky shader | `main.gd`, `project.godot` |

Typical numbers from the smoke test on a desktop CPU: an 8 km world plans in
~1 s; a busy town-center chunk builds in ~90 ms on a worker thread, and its
main-thread work is split into steps of under ~4 ms. A phone is roughly 3–5×
slower.

## Project layout

```
scenes/menu.tscn, main.tscn   Main menu (start scene) and the game
scripts/
  main.gd                     Game setup, day/night, autosave, death
  core/                       GameState (settings, saves, input), Net
                              (multiplayer), assets, mesh helpers,
                              procedural cars/props, textures
  world/                      World generation and streaming:
    terrain.gd                  coast, mountains, biomes
    hydrology.gd                rivers and lakes (drainage simulation)
    settlements.gd              cities, towns, villages, special sites
    road_network.gd             roads, bridges, junctions
    town_layout.gd              streets and lots of a settlement
    site_layout.gd              airport, research center, gas station
    world_gen.gd                ties it together; final terrain height
    chunk_builder.gd, chunk.gd  per-chunk geometry and nodes
    road_mesher.gd              road, sidewalk and bridge meshes
    world_streamer.gd           loads chunks around the player
    map_renderer.gd             top-down map image
  buildings/                  Procedural buildings, interiors, furniture,
                              doors and windows
  zombies/                    Zombie model (rig + animations), AI, manager
  items/                      Item database, models, grid inventory, loot,
                              dropped items
  combat/effects.gd           Arrows, thrown items, fire, explosions, blood
  player/                     Player (movement, stealth, items), weapons,
                              character (traits, backgrounds), health
                              (injuries, infection) and other players'
                              avatars
  base/                       Buildable structures (data, models, the
                              in-world body), base manager, farming
  animals/                    Wildlife (deer, rabbits, turkeys) and dogs
  traders/                    Trader camps and the trader
  vehicles/                   Vehicle types and condition (vehicle_db),
                              bike and boat models, the vehicle node
                              (driving, flying, boating), manager
                              (parked props to vehicles, boats, trunks)
  ui/                         HUD, inventory screen, item icons, button
                              glyphs, touch controls, menus, character
                              creator, map, vehicle menu, crafting and
                              trade menus
tests/smoke_test.tscn         Automated gameplay test (runs in CI)
tests/net_test.tscn           Two-device multiplayer test: a host and a
                              guest on one machine (run_net_test.sh, in CI)
tests/screenshots.tscn        Renders gameplay screenshots
tools/map_preview.gd          Renders a world map PNG
```

## Running it

1. Install [Godot 4.7](https://godotengine.org/download) (standard build).
2. Open Godot, **Import** this folder's `project.godot`, press **F5**.
3. To try touch controls on desktop, add `--touch` under *Project → Project
   Settings → Editor → Run → Main Run Args*.

**Automated test** (plays the real game and exits non-zero on failure):

```
godot --headless --import
godot --headless res://tests/smoke_test.tscn
```

**Frame-time benchmark** (a busy scene, frame cap off; add `-- --low` for the Low preset):

```
godot --headless res://tests/bench.tscn
```

**Compile check** (loads every script; seconds instead of minutes):

```
godot --headless res://tests/compile_check.tscn
```

**Multiplayer test** (starts a host and a guest and plays them together):

```
tests/run_net_test.sh path/to/godot
```

**Preview a world map:**

```
godot --headless -s tools/map_preview.gd -- --seed=777 --size=16384 --out=/tmp/map.png
```

## Getting the app on your devices

Every push runs `.github/workflows/build.yml`: the smoke test, then an
Android build and an iOS build. Download them from the run's **Artifacts**
on the repository's **Actions** tab.

**Android**: download `ZombieSurvival-debug-apk`, unzip, and install the APK
(allow "install unknown apps").

**iPhone**: download `ZombieSurvival-unsigned-ipa`. Apple only runs signed
apps, so sign and install it from a computer with
[Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io) using
your Apple ID. With a free Apple ID the app must be re-signed every 7 days;
a paid Apple Developer account ($99/yr) removes that limit and allows
TestFlight.

**Locally**: install export templates (*Editor → Manage Export
Templates*), set the Android SDK / Java paths in Editor Settings, then
*Project → Export*. iOS builds need a Mac with Xcode.
