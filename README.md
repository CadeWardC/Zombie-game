# Zombie Survival

An open-world, first-person zombie survival sandbox for **Android and iOS**,
built with **Godot 4.7** and designed to run well on phones and tablets
(minimum target: Samsung Galaxy Tab S6 Lite). The full plan is in
[docs/DESIGN.md](docs/DESIGN.md).

**What's in the game now (stages 1 and 2):**

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
- **Animated zombies** in eight outfits that shamble, sprint, grab, flinch,
  stagger, burn and fall. They hear you, see you, and can't swim.
- **Survival**: health, hunger, thirst, stamina, a day/night cycle and
  swimming.
- **Main menu with multiple saved worlds**: choose map size, seed,
  difficulty and death rule (respawn, new character, permadeath; lost
  permadeath worlds stay as memorials). When you die, your gear stays where
  you fell.

All art (terrain, buildings, furniture, cars, aircraft, zombies, items and
their inventory icons) is generated in code as realistic low-poly geometry,
so the app stays small and needs no art files.

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
| Use (doors, search, pick up) | USE       | E                | B             |
| Crouch / sneak | CROUCH                  | C / Ctrl         | R3            |
| Sprint       | RUN (toggle)              | Shift            | L3            |
| Jump / swim up | JUMP                    | Space            | A             |
| Switch weapon | WEAPON                   | 1-4 / wheel      | D-pad left / right |
| Eat or drink / heal | EAT / HEAL         | Z / H            | D-pad up / down |
| Inventory    | BAG                       | Tab / I          | View / Select |
| Flashlight   | LIGHT                     | F                | Y             |
| Pause        | II                        | Esc / P          | Start         |
| Debug stats  | –                         | F3               | –             |

On screen, button prompts match the controller you're using: Xbox
letters, PlayStation shapes, Nintendo letters, or keyboard keys. Menus work
with the gamepad too. In the inventory:
- A picks up and puts down; X quick-moves; Y uses or equips;
- RB rotates; LB drops;
- LT sorts; RT takes everything;
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
  core/                       GameState (settings, saves, input), assets,
                              mesh helpers, procedural cars/props, textures
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
  buildings/                  Procedural buildings, interiors, furniture, doors
  zombies/                    Zombie model (rig + animations), AI, manager
  items/                      Item database, models, grid inventory, loot,
                              dropped items
  combat/effects.gd           Arrows, thrown items, fire, explosions, blood
  player/                     Player (movement, stealth, items) and weapons
  ui/                         HUD, inventory screen, item icons, button
                              glyphs, touch controls, menus
tests/smoke_test.tscn         Automated gameplay test (runs in CI)
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
