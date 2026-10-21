# Zombie Survival: Game Design

This is the agreed design, built from the Q&A with the project owner. It's the
plan of record: change this file when a decision changes.

## 1. Vision

An **endless, first-person, open-world zombie survival sandbox** for phones,
playable **alone or in 2–4 player co-op**. Each new world is a **random,
procedurally generated American region**: coast, rivers, mountains, forests,
farmland, desert, highways, towns and cities. **Special locations** (research
centers, airports, military bases...) give players reasons to explore.
Difficulty is **hardcore but fair**: scarce supplies, dangerous zombies, but
deaths should feel like your fault.

No ending: survive, loot, build, explore. Free, no ads.

## 2. Platforms and performance

| Target | Notes |
|---|---|
| **Android** | APK built automatically by GitHub Actions. |
| **iOS** | GitHub's Mac runners build an **unsigned .ipa**. Install it with Sideloadly or AltStore using a free Apple ID; apps installed that way must be re-signed every 7 days. A paid Apple Developer account ($99/yr) would remove that limit and allow TestFlight. |
| **PC** | Maybe later. Keep the code free of mobile-only assumptions. |

**Minimum target device: Samsung Galaxy Tab S6 Lite** (Exynos 9611, Mali-G72
MP3 GPU, 4 GB RAM, 2000×1200). The game must hold **30 FPS on Low** there.
Every feature is checked against this budget:

- ≤ 150 draw calls, ≤ ~300k triangles on screen at Low.
- ≤ 1.5 GB RAM.
- Compatibility (OpenGL) renderer as a fallback if Vulkan misbehaves on Mali.
- An iPhone (owner has one) is the second test device.

## 3. Multiplayer

- **2–4 players**, **one player hosts** on their device; friends join over the
  internet or local network. No paid servers.
- The world exists while the host plays; the host's device stores the save.
- **PvP is a world setting** (off / on) picked by the host.
- The host's device simulates zombies around **every** player, so the host
  pays ~N× the zombie/chunk cost. Zombie caps scale per player to stay
  within budget on a host like the Tab S6 Lite.
- Built on Godot's high-level multiplayer (ENet). Server-authoritative for
  zombies, loot and damage; clients predict their own movement.
- Joining over the internet needs a relay or NAT punch-through (to be
  decided: a free relay service, or join codes via a tiny matchmaking server).

## 4. Death and respawn

When you die you pick one of three modes:

1. **Respawn**: same character, same world. **Keeps your skills and stats.**
   Your gear drops where you died.
2. **New character, same world**: skills and stats are wiped.
3. **New character, new world**: a fresh start.

**Revive:** in a hosted game, if you **died from infection**, friends can bring
you back (for example with a cure) **as long as you haven't respawned yet**.
Deaths from other causes (bites, starvation, falls) can't be revived.
Choosing mode 2 or 3 makes that character permanently gone.

## 5. Infection and the cure

- Each zombie bite has a **chance to infect** (default ~15%, a world setting).
- Infection progresses over ~1–2 in-game days: fever, blurred vision, slower
  stamina, then death. A player who dies infected rises as a zombie carrying
  their gear.
- **Research centers** are the only source of the **cure**: a **carryable
  vial** that cures one person and can be given to a friend. They're rare,
  guarded, and the deepest loot runs on the map.
- Antibiotics or medicine from hospitals **slow** the infection but never cure
  it.

## 6. The world

### 6.1 Size and seed

The player picks a size when creating a world. Every world is random; the
**seed code** can be shared to replay a map.

| Size | Cities | Towns | Villages | Notes |
|---|---|---|---|---|
| **8 × 8 km** | 1–2 | 6–8 | ~15 | Dense. Best for 2–4 players. |
| **16 × 16 km** | 3–4 | 15–20 | ~40 | Vehicles strongly recommended. |
| **32 × 32 km** | 8–10 | 40–60 | ~120 | Epic. Needs floating-origin shifting for precision. |

### 6.2 Generation order

The order matters, because each step constrains the next:

1. **Landmass and ocean**: at least one coastline; the map edge is ocean
   or impassable mountains.
2. **Elevation**: mountain ranges, hills, valleys.
3. **Rivers**: flow downhill from mountains to the ocean, with lakes in
   basins.
4. **Biomes** from elevation, moisture and latitude: forest, farmland /
   plains, desert, mountains, coast / beach.
5. **Settlements**: cities on coasts and rivers, towns spaced along valleys,
   villages and farms in between.
6. **Special locations**: placed by rules (see 6.5).
7. **Road network**: connect everything (see 6.3).
8. **Town layouts**: streets, lots and buildings (see 6.4).
9. **Props and loot**: trees, wrecks, containers.

### 6.3 Roads

Roads become **real meshes** instead of painted terrain. That fixes "the roads
look bad".

| Type | Connects | Look |
|---|---|---|
| **Interstate highway** | Cities, airports | 4 lanes, median, guardrails, overpasses, exits |
| **State road** | Towns | 2 lanes, painted center line, shoulders |
| **Town streets** | Within settlements | Curbs, sidewalks, crosswalks, stop signs |
| **Dirt roads** | Farms, cabins, ranger stations | Narrow, rutted |

- The network is a spanning tree between settlements plus a few extra links
  for loops. Routes are pathfound over the terrain to avoid steep slopes, and
  the terrain is graded under each road.
- **Bridges** where roads cross rivers. These are natural chokepoints.
- Abandoned car wrecks, traffic jams and military roadblocks on highways.
- Rendered as spline ribbons, with lane markings in the texture and
  intersections as special pieces.

### 6.4 American settlements

**Village** (population "~200")
: A crossroads with a gas station, a church, a general store and a handful
  of houses and trailers.

**Town** (~2,000)
: A **Main Street** where the state road passes through: diner, pharmacy,
  hardware store, bar, post office, police station, fire station. A
  residential grid of 1–2 story houses behind it. A school, churches, a
  ballfield. Gas stations at the town edges.

**City** (~50,000+)
: A **downtown grid** of office towers, apartments, a hospital and city hall.
  **Suburbs** with curving streets, cul-de-sacs, two-story houses, driveways,
  fences and backyards. A **commercial strip** with a mall, a supermarket,
  fast food and car dealerships. An **industrial zone** with a rail yard,
  warehouses and factories, usually by the river or coast.

**Lots and buildings**
: Every house sits on a lot with a yard, driveway, mailbox and often a fence
  or garage. Several **house types**, each with variations and furnished,
  enterable interiors whose furniture holds loot:
  - ranch house
  - two-story colonial
  - bungalow
  - farmhouse
  - mobile home / trailer
  - duplex
  - apartment block

### 6.5 Special locations

Guns are **uncommon but not terrible**: you'll find a pistol in a few houses,
but real firepower is at police stations and the military base.

| Location | Count (8 / 16 / 32 km) | Placement | Loot and purpose | Danger |
|---|---|---|---|---|
| **Research center** | 1 / 2 / 4 | Remote: mountains or a fenced campus | **Cure vials**, lab gear | Very high |
| **Airport** | 1 / 2 / 3 (+ small airfields) | Flat land near a city | **Only source of planes and helicopters**; fuel | High |
| **Military base** | 1 / 1–2 / 3 | Remote, fenced | Best guns, armor, ammo | Very high (soldier zombies) |
| **Hospital** | 1 per city | City | Medicine, antibiotics, bandages | High |
| **Police station** | 1 per town / city | Main Street or downtown | Pistols, shotguns, ammo, body armor | Medium |
| **Prison** | 1 / 1 / 2 | Remote | Fortified walls (base spot), guards' guns | High |
| **Mall / supermarket** | 1 per city / most towns | Commercial strip | Lots of food, clothing, bags | High (crowds) |
| **Gas station / car shop** | Many | Roads, town edges | Fuel, car parts, snacks | Low |
| **Factory / power plant** | 1–2 / 3 / 6 | Industrial zones | Tools, materials; restoring power is a late-game goal | Medium |
| **Farm** | Many | Farmland | Seeds, tools, food; good base spots | Low |
| **Cabin / ranger station** | Many | Forests, mountains | Hunting gear, bows, quiet | Low |
| **Harbor / marina** | Coast cities | Coast | Boats (future), fishing gear | Medium |
| **Gun store** | Some towns | Main Street | Guns and ammo, usually looted | Medium |
| **Camps and wrecks** | Scattered | Anywhere | Small "story" spots: crashed helicopter, abandoned camp, military roadblock | Varies |

Loot quality rises with danger, so the safest areas have the worst loot.

## 7. Zombies

| Type | Behavior |
|---|---|
| **Walker** | Slow, most common, deadly in groups. |
| **Runner** | Fast and fragile; can't be outwalked. More common at night. |
| **Brute** | Big, slow, very tough, breaks doors and barricades. |
| **Screamer** | Shrieks when it sees you, calling every zombie nearby. Kill it first. |
| **Crawler** | Hides in tall grass and rubble; grabs ankles. |
| **Soldier** | Armored, at the military base; drops military loot. |

- **Senses**: sound (gunshots carry far, sprinting is loud, crouching is
  quiet), sight (reduced at night and in rain), and a smell range.
- **Hordes**: large groups roam between towns and are drawn to noise.
- **Density** follows population: cities are packed, wilderness is sparse.
- **Performance**: AI level of detail, pooling, and animation detail that
  drops with distance (already built for basic zombies).

## 8. Items and inventory

- **Tetris-style inventory**: each item has a shape and size (a rifle is
  1×4, a can is 1×1). Backpacks, vests and pockets each add their own grid.
  Weight slows you down.
- Built **for touch and gamepad**: drag and drop, tap to rotate, an
  auto-sort button, a quick-transfer button for looting containers, and full
  D-pad / stick navigation.
- **Weapons**:
  - melee (bat, axe, machete, crowbar), with durability
  - guns (pistols, shotguns, rifles), uncommon and loud
  - bows and crossbows, quiet, with recoverable arrows
  - throwables and traps: Molotovs, grenades, noise-makers, bear traps

## 9. Survival systems

- **Needs**: health, hunger, thirst, stamina (built), plus infection,
  temperature and sleep / fatigue.
- **Crafting**: bandages, improvised weapons, arrows, Molotovs, simple tools,
  barricade planks.
- **Base building**: board up doors and windows of existing buildings, build
  walls, gates, storage, beds (a respawn point) and rain collectors. Brutes
  and hordes can break in.
- **Skills** improve by doing: shooting, melee, medicine, mechanics (cars),
  carpentry, farming, cooking, stealth. Skills are what death mode 1 keeps.
- **Farming and cooking**: plant seeds, water crops, cook raw food. Store
  food **spoils** over time, which pushes players toward farming in the long
  run.

## 10. Vehicles

| Vehicle | Where | Needs |
|---|---|---|
| Bicycle | Houses, garages | Nothing; quiet |
| Motorbike | Towns | Fuel |
| Cars and trucks | Everywhere (most broken) | Fuel, keys or hotwiring, parts (battery, tires) |
| **Helicopter** | **Airports only** | Fuel, possibly parts; can land anywhere |
| **Plane** | **Airports only** | Fuel, needs a runway or long straight road |

Engines are loud and attract zombies. Vehicles take damage when they hit
zombies.

## 11. Difficulty and world settings

The default preset is **"Hardcore but fair"**: scarce loot, dangerous
zombies, but clear warnings and readable threats. When creating a world, the
host can pick a preset or tweak any setting.

| Setting | Options |
|---|---|
| Preset | Casual / **Hardcore but fair** (default) / Brutal |
| Map size | 8 / 16 / 32 km |
| Zombie population | Low → Extreme |
| Zombie speed | Shamblers / Mixed (default) / Fast |
| Loot amount | Abundant → Scarce |
| Bite infection chance | 0–100% (default 15%) |
| Day length | 20 / 40 / 60 minutes |
| PvP | Off / On |
| Death modes allowed | Which of modes 1–3 are available |

## 12. Art direction

**Detailed low-poly**: a cohesive, stylized look that stays cheap on the Tab
S6 Lite.

- Use **free CC0 asset packs** (e.g. Quaternius and Kenney: animated
  characters and zombies, cars, suburban and city buildings, props), which
  can live in the public repo. Exact packs will be chosen after checking
  their contents and licenses.
- Zombies are rigged and animated (walk, run, attack, hit, death) and look
  varied through mixed body parts, clothes and colors.
- Cars come in several body types: sedan, pickup, SUV, van, police car,
  ambulance, bus.
- Buildings use a modular kit (walls, doors, windows, roofs) so houses can be
  assembled procedurally into many variations with real interiors.
- Polygon budgets: zombie ≤ 3k triangles (LODs below that), car ≤ 4k,
  house exterior ≤ 3k plus interior, with an imposter or simplified mesh far
  away.

## 13. Controls

- **Touch**: built (joystick, drag-to-look, action buttons).
- **Gamepad** (Xbox / PlayStation / Bluetooth):
  - **aim assist**: slowdown and gentle magnetism on zombies, adjustable,
    off for PvP
  - **button prompts** that match the connected controller
  - **remappable controls** in settings
  - **full menu navigation**: inventory, crafting and menus work without
    touching the screen
- Keyboard and mouse for development and a possible PC version.

## 14. Build stages

Each stage ends with a playable build on the Tab S6 Lite and iPhone.

| Stage | Contents |
|---|---|
| **0. Prototype** ✅ | Streaming world, towns, zombies, survival needs, touch and gamepad, APK CI |
| **1. Map and art** ← next | New world generator (sizes, coast, rivers, biomes), road network, American towns, cities and suburbs, special-location framework (research center and airport first), CC0 asset packs for houses, cars and animated zombies, interiors with loot containers, world-creation screen, unsigned iOS CI |
| **2. Items** | Tetris inventory, loot tables, guns, bows, throwables, melee durability, gamepad menu navigation and prompts |
| **3. Infection and death** | Infection, cure vials, the three death modes, revive, zombie types |
| **4. Multiplayer** | 2–4 player hosting, join codes, PvP setting, sync of zombies, loot and vehicles |
| **5. Vehicles** | Cars, bikes, fuel, then helicopters and planes at airports |
| **6. Survival depth** | Crafting, base building, skills, farming, cooking, spoilage, temperature |
| **7. Polish** | Sound, weather, hordes, aim assist and remapping, settings, performance pass |

Multiplayer comes at stage 4 by request, after the map. To avoid rework,
stages 1–3 are written **multiplayer-ready**: world state lives in data
(not in scene nodes), every gameplay change goes through functions that can
later become network calls, and randomness is seeded.

## 15. Open questions

- Internet play: free relay vs. a small matchmaking server for join codes.
- Do boats belong in the game (the coast and harbors suggest it)?
- Restoring power at power plants: what does it unlock (lights, fuel pumps,
  radios)?
- Any NPC survivors or traders, or only players?
