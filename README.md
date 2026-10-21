# Zombie Survival

An open-world, first-person zombie survival game for **Android and iOS**, built
with **Godot 4.7** and designed from the ground up to run well on phones.

- **16 km × 16 km world**, generated from a seed: forests, hills, snowy
  mountains, and towns with streets, houses and abandoned cars.
- **Survival**: health, hunger, thirst and stamina. Search houses for canned
  food, water and bandages.
- **Zombies** wander, hear your footsteps (sprinting is loud), spot you by
  sight, and hunt you down. At night they're faster, and you'll need your
  flashlight.
- **Day/night cycle** (20 minutes per day), **autosave**, melee combat with
  headshots, touch, keyboard/mouse and gamepad controls.

Almost all art is generated in code as flat-shaded low-poly meshes, so the
app stays tiny and needs no art pipeline to get started.

## Controls

| Action      | Touch                     | Keyboard / mouse | Gamepad       |
|-------------|---------------------------|------------------|---------------|
| Move        | Left side: floating stick | WASD / arrows    | Left stick    |
| Look        | Drag on the right side    | Mouse            | Right stick   |
| Attack      | HIT                       | Left click       | RT / X        |
| Sprint      | RUN (toggle)              | Shift            | L3            |
| Jump        | JUMP                      | Space            | A             |
| Flashlight  | LIGHT                     | F                | Y             |
| Eat / drink / bandage | EAT / DRINK / HEAL | 1 / 2 / 3      | D-pad         |
| Pause       | II                        | Esc / P          | Start         |
| Debug stats | –                         | F3               | –             |

Loot is picked up automatically when you walk over it.

## How it stays fast on phones

A huge world only works on mobile if the game only ever does work near the
player. The main techniques:

| Technique | Where |
|---|---|
| **Chunk streaming**: the world is split into 64 m chunks, loaded around the player and freed behind them | `scripts/world/world_streamer.gd` |
| **Background threads**: terrain and props are generated on `WorkerThreadPool`; the main thread only spends ≤3 ms/frame turning results into nodes | `world_streamer.gd`, `chunk_builder.gd` |
| **Level of detail**: near chunks use 2 m terrain quads with collision and loot; far chunks use 8 m quads, half the trees, a 4-sided tree mesh, and no collision | `chunk_builder.gd`, `chunk.gd` |
| **Instancing**: all trees or rocks in a chunk are one `MultiMesh` draw call, with transforms pre-packed on the worker thread | `chunk.gd` |
| **Fog-hidden draw distance**: depth fog fades the world out before the camera's far plane, hiding chunk pop-in | `main.gd` |
| **Zombie AI LOD**: full physics within 45 m; beyond that, cheap terrain-following movement updated every 4–10 frames | `zombie_manager.gd` |
| **Object pooling**: zombies are recycled, never freed during play | `zombie_manager.gd` |
| **Cheap crowds**: zombies don't physically collide with each other; a simple separation pass keeps them apart | `zombie_manager.gd` |
| **Spread-out raycasts**: only 2 line-of-sight checks per physics frame | `zombie_manager.gd` |
| **Dynamic resolution**: the 3D view renders at lower resolution when FPS drops (HUD stays sharp) | `performance_monitor.gd` |
| **Quality presets**: Low / Medium / High change view distance, shadows, zombie cap, FPS target, per-vertex lighting | `game_state.gd` |
| **Mobile renderer**, MSAA off, small shadow maps, single directional light, color background instead of a sky shader | `project.godot`, `main.gd` |
| **Deterministic world**: everything comes from the seed, so the whole map needs no storage; saves only record what changed (looted items) | `world_gen.gd` |

Measured on a desktop CPU (in the smoke test): near chunk generation ~5 ms on
a worker thread, ~1.4 ms on the main thread to create nodes. Phones are
roughly 3–5× slower, which still fits comfortably in the streaming budget.

## Project layout

```
project.godot              Engine settings (Mobile renderer, Jolt physics)
export_presets.cfg         Android + iOS export presets
scenes/main.tscn           Entry scene (everything else is built in code)
scripts/
  main.gd                  Wires the game together, day/night, autosave
  core/game_state.gd       Autoload: settings, inventory, clock, save/load, input map
  core/assets.gd           Shared meshes/materials/shapes, built once
  core/mesh_factory.gd     Low-poly mesh building helpers
  core/performance_monitor.gd  Dynamic resolution
  world/world_gen.gd       Seeded terrain, biomes, towns, houses, loot
  world/chunk_builder.gd   Thread-safe chunk data generation
  world/chunk.gd           Turns chunk data into nodes
  world/world_streamer.gd  Loads/unloads chunks around the player
  player/player.gd         First-person controller, combat, survival stats
  zombies/zombie.gd        Zombie behavior
  zombies/zombie_manager.gd  Spawning, pooling, AI LOD, senses
  items/pickup.gd          Loot pickups
  ui/hud.gd, ui/touch_controls.gd, ui/pause_menu.gd
tests/smoke_test.tscn      Automated gameplay test (runs in CI)
tests/screenshots.tscn     Renders gameplay screenshots
```

## Running it

1. Install [Godot 4.7](https://godotengine.org/download) (standard build).
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** to play on desktop. To try the touch controls on desktop, add
   `--touch` under *Project → Project Settings → Editor → Run → Main Run Args*
   (or run `godot -- --touch`).

### Automated test

```
godot --headless --import
godot --headless res://tests/smoke_test.tscn
```

It plays the real game: streams the world, walks, picks up loot, gets
attacked by a zombie, kills it, eats, saves and loads, and exits with a
non-zero code on failure.

## Building for Android (APK)

**Easiest: let GitHub build it.** Every push runs `.github/workflows/build.yml`,
which runs the smoke test and builds a debug APK. Open the run on the
repository's **Actions** tab and download `ZombieSurvival-debug-apk`. Install it
on your phone (allow "install unknown apps").

**Locally:**
1. In Godot: *Editor → Manage Export Templates → Download and Install*.
2. Install Android Studio (or just the command-line SDK) and JDK 17.
3. *Editor → Editor Settings → Export → Android*: set the Android SDK path
   and Java SDK path.
4. *Project → Export → Android → Export Project*.

For the **Google Play Store**, create a release keystore (never commit it), set
it in the Android export preset, and export an AAB (enable
*Gradle Build* and set *Export Format* to AAB).

## Building for iOS

iOS builds need a **Mac with Xcode** and an **Apple Developer account**
(Apple doesn't allow building iOS apps elsewhere).

1. On the Mac, open the project in Godot and install the export templates.
2. *Project → Export → iOS*: set your **App Store Team ID** and bundle
   identifier.
3. Export, then open the generated Xcode project to run on a device or
   upload to TestFlight / the App Store.

## Roadmap ideas

- Roads connecting towns, more building types (stores, gas stations,
  police station with weapons)
- Ranged weapons with ammo, crafting, barricading doors
- Inventory screen, weight limit, item durability
- Zombie variants (runners, tanks), hordes that roam the map
- Sound: footsteps, zombie groans, ambient wind (positional audio is cheap)
- Weather (rain, thick fog nights)
- Vehicles
- Real art: swap the generated meshes in `assets.gd` for imported low-poly
  models (keep them under ~1–3k triangles for zombies)
