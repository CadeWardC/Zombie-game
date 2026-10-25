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

The **death rule is chosen when the world is created** and can't be changed
later, so permadeath stays meaningful.

| World rule | When you die |
|---|---|
| **1. Respawn** | Same character, same world. **Keeps your skills and stats.** Your gear drops where you died. |
| **2. New character** | Start a fresh character in the same world. Skills and stats are wiped. |
| **3. Permadeath** | Your character is gone for good. The **only** way back is the cure (below). |

**Infection is the one way back from death:**

- **Single player**: you must take a cure **before you fully turn**. Once you
  turn, it's over. In a permadeath world the **world is lost**.
- **Multiplayer**: when an infected player dies, they **rise as a zombie**.
  Friends can **subdue and cure that zombie** to bring the player back. If
  the zombie is killed, the player is gone (rules 1 and 2 then respawn them
  as usual).
- Death from anything else (bites without infection, starvation, falls,
  gunshots) follows the world rule immediately.

**Permadeath in multiplayer**: a player who dies for good is **out**: they can
only spectate friends. If everyone is dead, the world is lost.

**Lost worlds** are kept as a **memorial**: they can't be played, but show
days survived, kills, cause of death and the explored map.

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

### 5.4 Clothing

Clothing gives **warmth**, **pockets / storage** and **bite protection**:
leather jackets, thick pants, riot gear and military armor lower the chance
that a bite breaks the skin (and can infect). Clothes tear and can be
repaired with a sewing kit.

### 5.5 Food and water from nature

- **Fishing** in rivers, lakes and the ocean (rods, nets).
- **Foraging**: berries, mushrooms (some poisonous), wild plants.
- **Hunting** deer, rabbits and birds for meat and hides.
- **Water from rivers and lakes must be boiled or purified**, or you get
  sick. Rain collectors give clean water.

### 5.6 Dog companion

You can find and tame a dog. It follows you, warns you of nearby zombies,
and can be hurt or killed.

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
- **Night**: **more zombies are active and runners appear**. Night is when
  you hide in your base.
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
| Death rule | Respawn / New character / Permadeath (fixed at creation) |

## 17. Art and audio

**Art: realistic low-poly, made in code**
: The owner chose this over the available free CC0 packs (which are cartoony
  and chibi-styled).
  - Everything is generated in code:
    - terrain and roads
    - buildings with interiors and furniture
    - cars and aircraft
    - trees and street props
    - rigged, animated zombies with outfit variants
  - Normal human proportions and a gritty palette: blood, rust, worn paint.
  - The models can later be replaced with hand-made ones (keep zombies
    ≤ 3k triangles, cars ≤ 4k) without changing the game code around them.

**Audio: ambient, little music**
: Wind, birds, rain, creaking houses, distant groans and gunshots carrying
  across the map. Music only in menus and brief tense moments. Positional
  audio for zombies, so you can hear where they are.

## 18. Build stages

Each stage ends with a playable build on the Tab S6 Lite and iPhone.

| Stage | Contents |
|---|---|
| **0. Prototype** ✅ | Streaming world, towns, zombies, survival needs, touch and gamepad, APK CI |
| **1. Map and art** ✅ | New world generator (sizes, coast, rivers, biomes), road network, American towns, cities and suburbs, special-location framework (research center and airport first), procedural realistic houses, cars and animated zombies, enterable interiors with doors and loot containers, world-creation screen with multiple saves, unsigned iOS CI |
| **2. Items and combat** ✅ | Tetris inventory, loot tables, guns, bows, throwables, melee shove and durability, stealth, gamepad menu navigation and prompts |
| **3. Character and health** ✅ | Character creation with traits, injuries, clothing protection, infection with symptoms, cure vials, the three death rules, curing zombified friends, memorial worlds, all zombie types and abilities |
| **4. Multiplayer** ✅ (Wi-Fi) | 2–4 player hosting, join codes, Wi-Fi discovery, pings, PvP setting, sync of zombies, loot and vehicles |
| **5. Vehicles** ✅ | Cars, bikes, fuel, boats, then helicopters and planes at airports |
| **6. Survival depth** ✅ | Crafting, base building, skills, farming, cooking, spoilage, sleep, temperature, weather and seasons, utilities and power plant, traders, hunting, fishing, foraging, water purification, dog companion |
| **7. Polish** ✅ | Audio, hordes and migration, tutorial and hints, aim assist and remapping, HUD options, settings, performance pass |

Multiplayer comes at stage 4 by request, after the map. To avoid rework,
stages 1–3 are written **multiplayer-ready**: world state lives in data
(not in scene nodes), every gameplay change goes through functions that can
later become network calls, and randomness is seeded.

## 19. Stage 1 notes

Done:
- World sizes and seeds; coast, rivers, lakes, biomes.
- Roads and bridges.
- Villages, towns and cities with American layouts.
- Houses and shops with enterable interiors, doors and loot containers.
- Airports and research centers (exteriors), gas stations.
- Animated zombies, detailed cars.
- Main menu with multiple worlds, threaded generation.
- Unsigned iOS CI.

Moved to later stages:
- **Special locations**: military base, prison, power plant, farms and
  cabins (stage 6), harbors and boats (stage 5).
- **Research center interior**: the dungeon-style lab interior with
  keycards and the generator (stage 3, together with the cure).
- **Zombies**: opening doors and breaking barricades (stage 3).

## 20. Stage 2 notes

Done:
- Item database (about 50 items) with procedural 3D models and inventory
  icons rendered from them.
- Tetris inventory:
  - pockets, vest and backpack grids, plus weapon, bag and vest slots;
  - weight that slows you down; long items need a backpack or a slot;
  - touch drag and drop, mouse, and full gamepad cursor control.
- Loot rolled per container from pools that depend on the building, and
  saved. Car trunks are searchable. Items can be dropped on the ground and
  stay there.
- Melee wear, the shove, and silent takedowns.
- Guns:
  - aim down sights, recoil, spread;
  - reloading from loose ammo (shotguns and revolvers load shell by shell);
  - jams on worn guns, and noise;
  - scope, red dot, suppressor and weapon light.
- Compound bow and crossbow, with arrows and bolts you can recover.
- Throwables and traps: bottles, alarm clocks, molotovs, grenades and bear
  traps.
- Zombies stagger, burn, get trapped, and build up awareness before
  chasing.
- Stealth: crouching, bushes, dark interiors, and the HUD eye.
- Button prompts per controller, and basic gamepad aim assist.
- On death your gear drops where you fell.

Simplified or moved:
- **Magazines**: guns reload straight from loose ammo; there are no
  separate magazine items. They can be added later if wanted.
- **Hiding in tall grass** waits for grass (stage 6, with farming and
  foraging). Bushes and dark rooms work now.
- **Aim assist strength and remapping settings**: stage 7, with the other
  settings.

## 21. Stage 3 notes

Done:
- Character creation: name, appearance with a 3D preview, ten
  backgrounds (skills, starting items and clothes) and eighteen traits on
  a points budget. Skills already used: aiming, melee, first aid, stealth,
  fitness and strength.
- Injuries on six body parts: scratch, laceration, deep wound, bite,
  broken bone, sprain, burn. Bleeding, slowdowns, pain, wound infection
  and fever. Treatments: bandage, rag, suture kit, splint, alcohol wipes,
  antibiotics, painkillers, first aid kit. Fall damage.
- Clothing in five slots (head, shirt, jacket, pants, shoes): bite and
  scratch protection by body part, wear, pockets, warmth (stored for
  temperature later), mending with a sewing kit, ripping into rags.
  Backgrounds start dressed for the job.
- Zombie infection: chance per bite (world setting), 24–48 in-game hours
  to turn, symptoms from about 15% (screen blur, fading colour, heartbeat
  vignette, coughing that zombies hear, weakness, slower healing).
  Antibiotics slow it; the cure vial stops it.
- Research centres: generator (loud while running), keycard security
  doors (blue and red), offices, labs, containment and the vault with 1–2
  cure vials. Zombies, scientists and soldiers wait inside.
- The three death rules. Dying infected makes you rise as a zombie
  carrying your gear (it stays in the world and is saved). A turned
  friend can be beaten down without killing them and given the cure.
- Lost worlds are memorials: survivor, background, days, kills, cause of
  death, how much was explored and the explored map. The pause menu shows
  the map with the parts you've seen.
- Zombie types: walker, runner, brute, screamer, crawler, soldier (plus
  lab-coated scientists). More runners at night; a "zombie speed" world
  setting (shamblers / mixed / fast). Interior spawn points in labs and
  some houses.
- Zombie abilities: open unlocked doors, batter locked doors only while
  they know you're there (brutes much faster), smash windows and crawl
  through, climb low fences. Survivors lock doors from the inside (hold
  interact), batter doors down, smash windows and climb through.
- HUD: health warnings, nearby-zombie arcs (wider with keen hearing),
  hold-to-use ring.

Simplified or moved:
- **Treatments are instant**: no timed actions yet.
- **Heartbeat sound**: stage 7 (audio). The heartbeat shows as a pulse on
  screen now.
- **Friends can see you turn pale, and the cure revives them**: the
  infection level and turned players are in the saved, synced data; the
  revive itself needs stage 4. In single player the cure prompt doesn't
  appear for your own turned body (you've already respawned); kill it to
  get your gear back.
- **Barricades**: stage 6 (base building). Locking doors works now.
- **Crawlers in tall grass and soldiers at the military base**: stage 6.
  For now crawlers lie in fields and houses, and soldiers guard research
  centres.
- **Sleep, temperature and skill growth** (heavy sleeper, warmth, fast
  learner): stage 6. The traits and values are stored already.
- **The lab's upper floor** isn't enterable.

## 22. Stage 4 notes

Done:
- Hosting from the pause menu ("Invite Friends"); joining from the main
  menu. Guests find games on the local network by themselves (a broadcast
  plus a probe of every address in the subnet, which also works on iOS
  without Apple's multicast entitlement).
- The host's device is the server: it simulates zombies around every
  player (each goes after the nearest), loads the ground with collision
  around guests, keeps containers, dropped items, doors, windows, power,
  turned players and the clock, and saves the world with every guest's
  survivor (character, inventory, health, position, explored map).
- Each player's own device runs their survivor (movement, health,
  inventory) and reports it 15 times a second; zombies near each guest are
  sent 10 times a second and shown as puppets. Hits on zombies, noise,
  loot, door and window changes go to the host, which passes them on.
- Avatars for the other players: their clothes and looks, human walk /
  run / crouch animations, a name tag, a flashlight beam, muzzle flashes,
  and a grey-green tint as the infection spreads (friends can tell).
- Pings: mark a spot, a zombie or loot, or hold to call for help; shown in
  the world, at the screen edge and on the map. Friends appear on the map.
- PvP world setting (off: bullets pass through friends).
- Death with friends: a turned survivor's body is in the world with their
  gear; subdue it and give it a cure vial to bring them back where it
  stood. If it's killed, the cure can't help (permadeath: they're out).
  Out players watch a living friend; a permadeath world is lost when
  everyone is out. Respawn and new-character rules work as before.
- Zombie caps grow by 60% of the solo cap per extra player.
- Disconnects: guests go back to the menu with a message when the host
  leaves; the host keeps a guest's last saved state when they leave.
- A two-device test (a host and a guest on one machine) runs in CI.

Simplified or moved:
- **Internet join codes** need a relay server; the owner chose Wi-Fi only
  for now. The relay can be added later without changing the game code.
- **Guests' movement isn't checked by the host** (it trusts each device):
  fine for friends playing together.
- **Picking up dropped items** is checked by the host (no duplicates);
  taking items from containers is shared but not locked, so two players
  grabbing the same item at the same instant could both get it.
- **Sleeping speeds up time only if everyone sleeps**: stage 6, with sleep.
- **Spawning near a friend's base bed**: stage 6, with base building. New
  guests start in a random small town.

## 23. Stage 5 notes

Done:
- Every parked car, bike and aircraft can be used. They stay cheap props
  until someone walks up to one; then it gets a saved record (fuel, engine,
  battery, flat tires, keys, hotwired, locked, damage) and a vehicle takes
  over from the prop. Its condition is rolled from its id, so everyone in a
  world finds it the same way, and most cars need work: no fuel, a dead
  battery, a shot engine, flats, no keys, locked doors.
- Vehicles: bicycle (pedal power uses stamina, silent), motorbike, sedan,
  hatchback, SUV, pickup, van, police car, ambulance, school bus,
  rowboat and motorboat (moored at docks on lakes and the coast; zombies
  can't follow), helicopters (airports, helipads, research centres) and
  light aircraft (airports).
- Driving is arcade and forgiving: cars follow the ground and tilt with
  it, bikes lean into turns, flats pull to one side and slow you down,
  deep water floods the engine. Boats glide and run aground at the shore.
  Helicopters climb, descend and fly anywhere, and land gently or crash.
  Planes need take-off speed and a pull on the stick, stall when slow,
  and are wrecked by a hard or banked landing.
- A vehicle menu at each vehicle: drive or ride as a passenger, break into
  a locked car (it may set off the alarm), open the trunk (it travels with
  the car), refuel from a gas or jet fuel can or a nearby pump, swap in a
  battery, change a flat, fix the engine with engine parts, hotwire with a
  screwdriver or mechanics skill.
- Fuel: gas station pumps and airport jet fuel pumps each hold a limited,
  saved amount; fill cans there or refuel at them. New items: gas can, jet
  fuel can, screwdriver, car battery, spare tire, engine parts (hardware
  stores, warehouses, gas stations, hangars, trunks).
- Noise: engines are heard for 30–40 m (helicopters and planes much
  further), horns and car alarms draw zombies from far away.
- Running zombies over hurts them and the vehicle; crashes into walls hurt
  the vehicle and, when hard, the people inside. In a closed vehicle
  zombies pound on it instead of biting you until it's wrecked.
- Chase camera (look input orbits it, it swings back behind while
  driving), a driving panel (speed, fuel, condition, warnings, plane
  throttle and take-off speed, helicopter altitude), headlights, touch
  buttons relabelled while driving (HORN, BRAKE / UP / THROTTLE, EXIT,
  LIGHTS, START).
- Multiplayer: the driver's device simulates the vehicle and sends its
  motion 15 times a second; records, seats, alarms and pump levels are
  shared through the host and saved with the world. Passengers ride along.

Simplified or moved:
- **Vehicle physics** are kinematic (not a full wheel simulation), which is
  steadier on low-end tablets and easier to sync.
- **Parked vehicles far from every player** are kept only as records; a
  moved vehicle is drawn again once someone comes within ~260 m.
- **Riders aren't drawn on bikes or in seats**; other players' survivors
  are hidden while they're in a vehicle.
- **Planes on long roads** work (any flat straight stretch long enough),
  but there's no taxiing guidance or runway lights.
- **Car parts from wrecks** (stripping a broken car for its battery or
  tires) are left for stage 6, with crafting.

## 24. Stage 6 notes

Done:
- **Skills grow by doing**: shooting (aiming), hitting (melee), heavy
  weapons and loads (strength), sprinting (fitness), sneaking and takedowns
  (stealth), treating wounds (first aid), repairs and hotwiring
  (mechanics), building and woodwork (carpentry), planting and harvesting
  (farming), cooking, foraging and fishing (foraging), flying (piloting).
  Medium speed: the first levels come in a session. A Skills page shows
  progress. Fast Learner speeds it up.
- **Crafting**: a menu (from the inventory, K, or R3 there) with every
  recipe known from the start, greyed out until you have the materials and
  tools: planks from logs (saw), spears, nail bats, arrows and bolts,
  molotovs, splints, boiled bandages, rope, fishing rods, hatchets,
  shovels, cooking pots, sleeping bags, scrap armour, hide jackets and
  cooked food. Workbenches unlock the bigger recipes; cooking needs a lit
  fire. New materials and tools in the loot: logs (chop trees with an axe
  or hatchet), planks, nails, scrap metal, rope, duct tape, feathers,
  hides, saws, pots, matches, lighters, watering cans.
- **Building**: walls, gates, spike barricades, watchtowers (climb the
  ladder; zombies can't), storage crates, beds, workbenches, campfires,
  rain collectors and farm plots. A preview shows where it goes (green
  fits, red doesn't) and snaps to a grid; rotate in 45° steps. Carpentry
  makes them sturdier. Zombies batter what's in their way (brutes much
  faster); repair with a plank and nails, or take apart for half the
  materials back. **Fortifying**: board up windows and barricade doors
  from the inside (planks, nails, a hammer); zombies have to break through
  first.
- **Food**: fresh food spoils (bread, milk, meat, fish, vegetables, stews);
  fridges keep it while the power is on. Rotten or raw food, river water
  and some mushrooms cause food poisoning (vomiting, weakness). Boil water
  in a pot on a fire or use purification tablets; rain collectors give
  clean water. Good cooks make more filling meals.
- **Sleep and fatigue**: tiredness builds while awake (blurred vision, less
  stamina) and you may pass out. Sleep in a bed (best), a sleeping bag, or
  on the ground (out in the open, a zombie may find you). Time speeds up
  while you sleep; in co-op only when everyone sleeps.
- **Temperature and wetness**: seasons, time of day, weather, altitude and
  deserts set the air temperature; shelter, fires and the warmth of your
  clothes help; rain and swimming soak you (raincoats help) and being wet
  chills you. Cold drains stamina and, at its worst, health. Heat makes you
  thirsty. The HUD shows season, weather and how warm it feels.
- **Weather and seasons**: clear, overcast, rain, thunderstorms (lightning
  and thunder), fog and snow, changing every few hours with odds that
  depend on the season. Rain and storms dull zombies' hearing and sight;
  fog closes in. Seasons last 1, 2 or 4 weeks (a world setting); winter
  snows, is cold and kills crops.
- **Utilities**: power and water work for about two weeks (a world setting:
  off from day 1, ~2 weeks, never). Each map has a **power plant** by the
  water (turbine hall, control room, cooling towers): restarting it takes
  20 litres of fuel and engine parts, is very loud, and brings the grid
  back for a week.
- **Farming**: dig a farm plot (shovel), plant seeds (potato, carrot,
  tomato, corn) from spring to autumn, keep it watered (watering can,
  bottles, or rain), harvest for food and seeds.
- **Nature**: search bushes for berries (summer, autumn) and mushrooms
  (spring, autumn; some are poisonous; foraging skill tells), fish with a
  rod in rivers, lakes and the sea, hunt deer, rabbits and wild turkeys
  (they bolt when they see or hear you; crouch and approach slowly) and
  butcher them with a knife for meat, hides and feathers. Chop trees for
  logs.
- **Traders**: one to three fenced trader camps per map. Barter only (a
  value for every item; the trader takes a cut), stock restocked every
  three days, with rare goods: engine parts, antibiotics, military ammo,
  seeds, the occasional cure vial. Safe zones: guards shoot zombies that
  get in, and there's no PvP.
- **Dog companion**: strays turn up in towns. Win one over with dog food or
  meat; it follows you, growls when zombies are near, fights the ones that
  come for you, can be told to stay, and can be hurt and killed.
- Multiplayer: structures, boards and barricades, felled trees, picked
  bushes, trader stock, the restarted grid, the weather and sleeping are
  shared through the host and saved with the world.

Simplified or moved:
- **Wildlife and dogs** run on each player's own device (not shared in
  co-op): everyone hunts their own animals, and a dog follows only its
  owner's game.
- **Base power** (solar panels, generators wired to a base) isn't built:
  the grid (early weeks or a restarted plant) is the only power, and it
  only matters for fridges and lab doors for now.
- **Free-form fishing nets, snares and traps for animals** are left out;
  the rod, the bow and the gun cover it.
- **Sleeping speeds up time in co-op** only when everyone sleeps; a player
  sleeping alone in co-op rests faster instead.
- **Taps and running water** aren't separate: rain collectors, rivers and
  bottles are the water sources.
- **Snow on the ground** isn't drawn: winter shows as falling snow, cold
  and dead crops, but the land stays green.

## 25. Stage 7 notes

Done:
- **Audio, made in code** like the art: gunshots (pistol, rifle, shotgun,
  suppressed), bows, swings and hits, footsteps (quieter crouching),
  zombie groans, snarls and the screamer's shriek, doors, breaking glass,
  explosions, thunder, car horns and alarms, engine hum that rises with
  speed, a heartbeat when badly hurt or turning, and button clicks. Zombies
  near you groan now and then, positionally, so you hear where they are.
  Ambience: wind (stronger in storms), birds by day, crickets on summer and
  autumn nights, rain, a crackling fire; quieter indoors. A slow, uneasy
  pad plays on the menus only. Sounds are synthesized the first time
  they're needed (all of them together take under half a second).
- **Hordes**: a few large groups per map (3 / 6 / 12 by size) drift from
  town to town; loud noises (gunfire, generators, alarms, explosions) pull
  them off course. Near a player they appear and walk together (allowed
  past the normal zombie cap); away from everyone they fold back into the
  map. Killing zombies thins an area out; it fills back up over about four
  in-game days, or at once when a horde passes through.
- **Tips**: short hints the first time something matters (zombies nearby,
  night, a bite, bleeding, hunger, thirst, tiredness, cold, rain, guns,
  vehicles, looting, crafting, hordes, traders, dogs, infected wounds,
  turning), once per device; off in Settings, or show them all again.
- **Tutorial** (main menu): a fixed world with a ready-made survivor and a
  checklist: walk and look, search a container, equip a hammer, kill a
  zombie, eat, build a campfire.
- **Settings** (main menu and pause menu): graphics, field of view,
  master / effects / ambience / music volume, look sensitivity, invert
  look, aim assist (off, normal, strong; always off in PvP worlds), HUD
  (always-on bars, or minimal: bars only when they need attention), tips,
  and remapping every control (a key and a gamepad button each, with
  reset).
- **Performance**: measured at the Low preset (the Tab S6 Lite budget).
  Ground-level views draw 67–146 calls (budget 150); only high aerial
  camera views go over. Structures and animals vanish with distance,
  animals are a handful of merged meshes, rain and snow use fewer
  particles on Low. A frame-time benchmark (tests/bench.tscn) runs a busy
  scene uncapped: on a desktop CPU about 3.5 ms of script and 2.8 ms of
  physics with 20 zombies chasing, a base, animals and a storm.

Simplified or moved:
- **Music** is one generated pad on the menus; there are no "tense moment"
  stings in play yet.
- **Hordes** aren't drawn on the map; you hear them coming.
- **Performance on the real Tab S6 Lite** hasn't been measured (no device
  here); the numbers above are from a desktop at the Low preset.

## 26. After stage 7: playtest fixes and a new look

From playing the build on a phone:
- **Houses**: doorways are wider (outside doors 1.15 m, inside doors 1.1 m;
  the player is 0.7 m across), and nothing tall stands in front of a
  window any more: wardrobes, bookshelves, fridges and lockers move to a
  solid stretch of wall, and kitchen counters under a window lose their
  wall cabinets. Beds' headboards sit below the sill.
- **More to find**: 29 new items (canned tuna, peaches and corn, peanut
  butter, noodles, cereal, candy, juice, sports drinks, canned coffee
  that wakes you up, vitamins, batteries, wire, glue, tarps, cloth,
  binoculars, wallets, watches, car keys, and frying pans, golf clubs,
  tire irons, pipe wrenches, lead pipes, meat cleavers and pickaxes to
  fight with). Most containers now hold something (about 1 in 5 has been
  picked clean, down from more than half), with more rolls each.
- **More zombies**: about 75% more around you (more in towns and at
  night), in bigger groups, and a third of houses have someone still
  inside. Caps per preset: 22 / 36 / 55.
- **Searching bodies**: a killed zombie lies where it fell for a couple
  of minutes (longer while you're next to it) and can be searched like a
  container: wallets, keys, cigarettes, lighters, bandages, snacks, now
  and then a knife or a pistol. Soldiers carry military gear, scientists
  lab supplies. Bodies don't count against the zombie cap; at most 14 lie
  around at once.
- **New look** for every screen, all drawn in code:
  - A shared theme (dark panels, rust-red accent, bold spaced headings)
    applied to Godot's default theme at startup, so every menu matches.
  - Vector icons (heart, food, water, stamina, bleeding, bones, infection,
    weather, and one for every touch button).
  - HUD: a vitals card with icons and bars that pulse red when low,
    warnings as coloured chips, a clock and weather pill, a weapon card
    with the item's picture, prompts in a pill under the crosshair.
  - Touch buttons: dark discs with icons and short captions, item counts
    as badges; pause moved to the corner.
  - Main menu over a drawn backdrop (a dead town at dusk with fog);
    character creator with a lit, turning preview, background details as
    tags, strengths and weaknesses grouped; pause menu as a side panel;
    inventory columns as panels with headings and slot silhouettes;
    crafting rows with the item's picture and what's missing in red;
    styled death and loading screens.

## 27. Open questions

- Which free relay service to use for internet join codes.
- Exact asset packs (checked for license and Tab S6 Lite performance).
