# Zombie Survival: Game Design

This is the agreed design, built from two rounds of Q&A with the project
owner. It's the plan of record: change this file when a decision changes.

## 1. Vision

An **endless, first-person, open-world zombie survival sandbox** for phones,
playable **alone or in 2–4 player co-op**. Each new world is a **random,
procedurally generated American region**: coast, rivers, mountains, forests,
farmland, desert, highways, towns and cities. **Special locations** (research
centers, airports, military bases...) give players reasons to explore.

The game starts **weeks after the outbreak**: the world is abandoned and
overgrown, and nothing comes back once it's gone. Looted places stay empty,
food spoils, and eventually you have to farm, craft and build to survive.
Difficulty is **hardcore but fair**: scarce supplies, dangerous zombies, but
deaths should feel like your fault.

No ending. Free, no ads.

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
- The owner's iPhone is the second test device.

## 3. Multiplayer

- **2–4 players**, **one player hosts** on their device. No paid servers.
- **Joining**: a short **join code** for internet play (via a small free relay
  service, to be chosen), plus **automatic discovery on the same Wi-Fi**.
- The world exists while the host plays; the host's device stores the save.
- **PvP is a world setting** (off / on) picked by the host.
- **Co-op shares everything**: bases, storage and vehicles.
- **Communication**: **quick pings** (tap to mark loot, a zombie, "help!", "go
  here", shown on screen and on the map). No in-game voice or text; players
  use Discord or similar.
- Joining players spawn in a random small town (see 12) or near a friend's
  base bed if they own one.
- The host's device simulates zombies around **every** player, so the host
  pays ~N× the zombie/chunk cost. Zombie caps scale per player to stay
  within budget on a host like the Tab S6 Lite.
- Built on Godot's high-level multiplayer (ENet). Server-authoritative for
  zombies, loot and damage; clients predict their own movement.

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

## 5. Character, health and needs

### 5.1 Character creation

The game uses a **full traits system**, like Project Zomboid:

- **Appearance**: body, face, hair, clothes.
- **Background**, a past job that gives starting skill bonuses and a few items:
  nurse, mechanic, police officer, farmer, carpenter, hunter, pilot,
  firefighter, chef, unemployed.
- **Traits**: good traits cost points, bad traits give points. Examples:
  - good: fast learner, strong, keen hearing, athletic
  - bad: short-sighted, smoker, clumsy, heavy sleeper

### 5.2 Health and injuries

There's **one health bar**, but injuries add **specific problems**:

| Injury | Effect | Treatment |
|---|---|---|
| Bleeding | Health drains | Bandage (or rag) |
| Deep wound | Bleeds badly, can get infected (normal infection, not zombie) | Stitches, disinfectant |
| Broken bone | Slow movement or weak arm | Splint, rest |
| Zombie bite | Bleeding + chance of zombie infection (see 6) | Bandage; only the cure stops infection |
| Burn, sprain | Minor slowdowns | Time, painkillers |

### 5.3 Needs

The needs are **health, hunger, thirst, stamina, sleep / fatigue,
temperature** and **infection**.

**Sleep**
: Tired means slower actions and blurry vision. Sleeping in the open is
  dangerous; a bed in a fortified base is safe. In co-op, sleeping speeds up
  time only if all players sleep.

**Temperature**
: Cold nights, mountain snow, winter and desert heat. Clothing layers,
  fires, shelter and being wet or dry all matter.

## 6. Infection and the cure

- Each zombie bite has a **chance to infect** (default ~15%, a world setting).
- Infection progresses over ~1–2 in-game days, then you die and rise as a
  zombie carrying your gear.
- **Symptoms**, which get stronger with time:
  - **screen effects**: pulsing blur, draining color, heartbeat sound
  - **body effects**: coughing (noise zombies hear), less stamina, slower
    healing
  - **friends can tell**: other players see you turn pale and sick, so a
    bite can't be hidden
- **Research centers** are the only source of the **cure**: a **carryable
  vial** that cures one person and can be given to a friend (see 7.5).
- Antibiotics and medicine from hospitals **slow** the infection but never
  cure it.

## 7. The world

### 7.1 Size, seed and saves

- The player picks a size when creating a world. Every world is random; the
  **seed code** can be shared to replay a map.
- **Multiple saved worlds**, chosen from the main menu.

| Size | Cities | Towns | Villages | Notes |
|---|---|---|---|---|
| **8 × 8 km** | 1–2 | 6–8 | ~15 | Dense. Best for 2–4 players. |
| **16 × 16 km** | 3–4 | 15–20 | ~40 | Vehicles strongly recommended. |
| **32 × 32 km** | 8–10 | 40–60 | ~120 | Epic. Needs floating-origin shifting for precision. |

### 7.2 Persistence

- **Loot never respawns.** Once a place is looted, it stays empty.
- **Zombies migrate back slowly.** Cleared areas stay mostly clear, but
  wandering hordes drift back in over in-game days, so bases need defending.
- **Utilities**: power and running water **still work for about the first two
  in-game weeks**, then shut off. After that:
  - **Solar panels and generators** (found or crafted) power a base.
  - Players can **restart the power plant** to bring a region's grid back
    **for a limited time**. This is a big expedition: fuel, repairs and
    zombies inside.
- **Weather and seasons**: rain, fog, storms and snow. Seasons change every
  ~2 in-game weeks. Winter is cold, snowy and has no farming; rain lowers
  zombie sight and hearing range; fog makes everything tense.

### 7.3 Generation order

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
6. **Special locations**: placed by rules (see 7.6).
7. **Road network**: connect everything (see 7.4).
8. **Town layouts**: streets, lots and buildings (see 7.5).
9. **Props and loot**: trees, wrecks, containers.

### 7.4 Roads

Roads become **real meshes** instead of painted terrain.

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

### 7.5 American settlements

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

  Doors can be opened, closed, locked and barricaded; windows can be broken
  and boarded up.

### 7.6 Special locations

Guns are **uncommon but not terrible**: you'll find a pistol in a few houses,
but real firepower is at police stations and the military base. Loot quality
rises with danger, so the safest areas have the worst loot.

| Location | Count (8 / 16 / 32 km) | Placement | Loot and purpose | Danger |
|---|---|---|---|---|
| **Research center** | 1 / 2 / 4 | Remote: mountains or a fenced campus | **Cure vials**, lab gear | Very high |
| **Airport** | 1 / 2 / 3 (+ small airfields) | Flat land near a city | **Only source of planes and helicopters**; jet fuel | High |
| **Military base** | 1 / 1–2 / 3 | Remote, fenced | Best guns, armor, ammo | Very high (soldier zombies) |
| **Hospital** | 1 per city | City | Medicine, antibiotics, bandages, splints | High |
| **Police station** | 1 per town / city | Main Street or downtown | Pistols, shotguns, ammo, body armor | Medium |
| **Prison** | 1 / 1 / 2 | Remote | Fortified walls (base spot), guards' guns | High |
| **Power plant** | 1 / 1–2 / 3 | Industrial edge, river or coast | Restart to bring power back for a while | High |
| **Mall / supermarket** | 1 per city / most towns | Commercial strip | Lots of food, clothing, bags | High (crowds) |
| **Gas station / car shop** | Many | Roads, town edges | Fuel, car parts, snacks | Low |
| **Factory** | 1–2 / 3 / 6 | Industrial zones | Tools, materials, solar panels | Medium |
| **Farm** | Many | Farmland | Seeds, tools, food; good base spots | Low |
| **Cabin / ranger station** | Many | Forests, mountains | Hunting gear, bows; quiet | Low |
| **Harbor / marina** | Coast cities, big lakes | Coast, lakes | **Boats**, fishing gear | Medium |
| **Gun store** | Some towns | Main Street | Guns and ammo, usually looted | Medium |
| **Trader camp** | 1 / 1–2 / 3 | Defensible spot (island, fenced farm) | Barter and rare goods (see 13) | Safe zone |
| **Camps and wrecks** | Scattered | Anywhere | Small "story" spots: crashed helicopter, abandoned camp, military roadblock | Varies |

**Research center: a dungeon run**
: A multi-floor lab complex, partly underground. Doors need **keycards**
  carried by dead scientists and guards, and the backup **generator** must be
  restarted to open the lower floors and elevators. It's dark, cramped and
  packed with zombies. **Cure vials** sit in a vault at the bottom; each center
  holds only a few.

**Airport: aircraft**
: A **mix**. Most planes and helicopters are **flyable once fueled** (find
  jet fuel), but they sit in hangars and on aprons full of zombies, and you
  need the keys from the control tower or offices. Some are **broken** and
  need parts found around the airport or bought from traders.

## 8. Zombies

| Type | Behavior |
|---|---|
| **Walker** | Slow, most common, deadly in groups. |
| **Runner** | Fast and fragile; can't be outwalked. More common at night. |
| **Brute** | Big, slow, very tough, breaks doors and barricades much faster. |
| **Screamer** | Shrieks when it sees you, calling every zombie nearby. Kill it first. |
| **Crawler** | Hides in tall grass and rubble; grabs ankles. |
| **Soldier** | Armored, at the military base; drops military loot. |

- **Senses**:
  - sound: gunshots carry far, sprinting and coughing are loud, crouching is
    quiet
  - sight: reduced at night and in rain or fog
  - a short smell range
- **Physical abilities**: zombies **open unlocked doors** (lock them!),
  **climb low fences and walls** (tall ones stop them) and **smash windows**
  and crawl through. **They can't swim**, so water is a refuge.
- **Barricades**: zombies break doors and barricades **extremely slowly**, but
  **only while they know you're there**. If you hide and stay quiet, they lose
  interest and wander off. Brutes break through much faster.
- **Hordes**: large groups roam between towns, are drawn to noise, and slowly
  re-fill cleared areas (see 7.2).
- **Density** follows population: cities are packed, wilderness is sparse.
- **Performance**: AI level of detail, pooling, and animation detail that
  drops with distance (already built for basic zombies).

## 9. Combat and stealth

**Guns: semi-realistic**
: Recoil, aim down sights, magazines you load from loose ammo, jams on worn
  guns, attachments (scopes, suppressors, flashlights). Gunshots are very
  loud. Touch players get a fire button and an aim button; gamepads get aim
  assist (see 15).

**Melee: swings and shove**
: Swing to attack, **shove** to knock zombies back when surrounded. Both cost
  stamina, so managing stamina is the core skill. Weapons wear out.

**Full stealth**
: - **crouch** to be quieter and harder to see
  - **hide** in bushes, tall grass and dark rooms
  - **silent takedowns** from behind
  - **distract** zombies by throwing bottles or noise-makers

**Weapons**
: - melee: bat, axe, machete, crowbar, knife, sledgehammer
  - guns: pistols, revolvers, shotguns, hunting rifles, assault rifles
    (military only)
  - bows and crossbows: quiet, with recoverable arrows
  - throwables and traps: Molotovs, grenades, noise-makers, bear traps

## 10. Items and inventory

- **Tetris-style inventory**: each item has a shape and size (a rifle is
  1×4, a can is 1×1). Backpacks, vests and pockets each add their own grid.
  Weight slows you down.
- Built **for touch and gamepad**: drag and drop, tap to rotate, an
  auto-sort button, a quick-transfer button for looting containers, and full
  D-pad / stick navigation.
- Loot lives in **containers** (fridges, cabinets, lockers, car trunks), not
  on the floor.

## 11. Building, crafting and skills

**Base building: fortify, plus limited building**
: - **Fortify existing buildings**: board up windows, reinforce and lock
    doors, move furniture to block entrances, add beds, storage and
    workbenches.
  - **Limited outside building**: walls, gates, watchtowers, rain collectors,
    farm plots, sheds.
  - No free-form house building.

**Crafting**
: **All recipes are known from the start**; what limits you is materials and
  tools. Workbenches unlock bigger recipes. Examples: bandages, splints,
  improvised weapons, arrows, Molotovs, barricade planks, campfires, simple
  traps.

**Skills: medium speed**
: You make noticeable progress every play session. Skills improve by doing:
  shooting, melee, medicine, mechanics, carpentry, farming, cooking, stealth,
  piloting. Your background gives starting bonuses. Death mode 1 keeps them.

**Farming and cooking**
: Plant seeds in spring to autumn, water crops, cook raw food. Store food
  **spoils** over time.

## 12. Spawning and onboarding

- New characters spawn in a **random small town or village**.
- **Optional tutorial**: a short guided starting scenario. It's skippable.
- **Contextual hints** the first time you meet something (first bite, first
  car, first night). They can be turned off in settings.

## 13. Traders

**Very few**: 1–3 tiny camps per map.

- **Safe zones**: no zombies get in, and no PvP.
- **Barter only**: items for items, no money.
- They also sell **rare goods** that are hard or impossible to find
  elsewhere: aircraft parts, cure-adjacent medicine, solar panels, rare
  ammo.

## 14. Vehicles

Handling is **survival-realistic but forgiving**. You need fuel, keys or
hotwiring, a working battery and tires, and engines take damage. But driving
itself is easy and arcade-like, and repairs are simple (swap the part).

| Vehicle | Where | Needs |
|---|---|---|
| Bicycle | Houses, garages | Nothing; quiet |
| Motorbike | Towns | Fuel |
| Cars and trucks | Everywhere (most broken) | Fuel, keys or hotwiring, battery, tires |
| **Boats** (rowboat, motorboat) | Marinas, lakes, coast | Fuel for motorboats; zombies can't follow on water |
| **Helicopter** | **Airports only** | Jet fuel, keys; some need parts. Can land anywhere |
| **Plane** | **Airports only** | Jet fuel, keys; some need parts. Needs a runway or long straight road |

- Engines and **car alarms** are loud and attract zombies.
- Vehicles take damage when they hit zombies.

## 15. Controls and UI

- **Touch**: built (joystick, drag-to-look, action buttons).
- **Gamepad** (Xbox / PlayStation / Bluetooth):
  - **aim assist**: slowdown and gentle magnetism on zombies, adjustable,
    off for PvP
  - **button prompts** that match the connected controller
  - **remappable controls** in settings
  - **full menu navigation**: inventory, crafting and menus work without
    touching the screen
- **HUD** is a setting: **minimal** (icons appear only when something's
  wrong) or **always-on bars**.
- **Map** reveals **as you explore** (fog of war), with pings and markers
  shared in co-op.
- Keyboard and mouse for development and a possible PC version.

## 16. Difficulty and world settings

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
| Season length | 1 / 2 / 4 weeks |
| Utilities shut-off | Day 1 / ~2 weeks (default) / never |
| PvP | Off / On |
| Death modes allowed | Which of modes 1–3 are available |

## 17. Art and audio

**Art: detailed low-poly**
: A cohesive, stylized look that stays cheap on the Tab S6 Lite.
  - Use **free CC0 asset packs** (e.g. Quaternius and Kenney: animated
    characters and zombies, cars, suburban and city buildings, props), which
    can live in the public repo. Exact packs will be chosen after checking
    their contents and licenses.
  - Zombies are rigged and animated (walk, run, attack, hit, death) and look
    varied through mixed body parts, clothes and colors.
  - Cars come in several body types: sedan, pickup, SUV, van, police car,
    ambulance, bus.
  - Buildings use a modular kit (walls, doors, windows, roofs) so houses can
    be assembled procedurally into many variations with real interiors.
  - Polygon budgets: zombie ≤ 3k triangles (LODs below that), car ≤ 4k,
    house exterior ≤ 3k plus interior, with an imposter or simplified mesh
    far away.

**Audio: ambient, little music**
: Wind, birds, rain, creaking houses, distant groans and gunshots carrying
  across the map. Music only in menus and brief tense moments. Positional
  audio for zombies, so you can hear where they are.

## 18. Build stages

Each stage ends with a playable build on the Tab S6 Lite and iPhone.

| Stage | Contents |
|---|---|
| **0. Prototype** ✅ | Streaming world, towns, zombies, survival needs, touch and gamepad, APK CI |
| **1. Map and art** ← next | New world generator (sizes, coast, rivers, biomes), road network, American towns, cities and suburbs, special-location framework (research center and airport first), CC0 asset packs for houses, cars and animated zombies, enterable interiors with doors and loot containers, world-creation screen with multiple saves, unsigned iOS CI |
| **2. Items and combat** | Tetris inventory, loot tables, guns, bows, throwables, melee shove and durability, stealth, gamepad menu navigation and prompts |
| **3. Character and health** | Character creation with traits, injuries, infection with symptoms, cure vials, the three death modes, revive, all zombie types and abilities |
| **4. Multiplayer** | 2–4 player hosting, join codes, Wi-Fi discovery, pings, PvP setting, sync of zombies, loot and vehicles |
| **5. Vehicles** | Cars, bikes, fuel, boats, then helicopters and planes at airports |
| **6. Survival depth** | Crafting, base building, skills, farming, cooking, spoilage, sleep, temperature, weather and seasons, utilities and power plant, traders |
| **7. Polish** | Audio, hordes and migration, tutorial and hints, aim assist and remapping, HUD options, settings, performance pass |

Multiplayer comes at stage 4 by request, after the map. To avoid rework,
stages 1–3 are written **multiplayer-ready**: world state lives in data
(not in scene nodes), every gameplay change goes through functions that can
later become network calls, and randomness is seeded.

## 19. Open questions

- Which free relay service to use for internet join codes.
- Exact asset packs (checked for license and Tab S6 Lite performance).
