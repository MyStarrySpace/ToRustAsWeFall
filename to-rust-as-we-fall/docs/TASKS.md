# To Rust As We Fall — Godot Implementation Task List

Derived from GDD v0.1, series bible, and React prototype. Organized by dependency order — later phases depend on earlier ones.

> **Historical prototype backlog:** this file predates the v0.2 GDD and is not gameplay
> authority. `reference-docs/to_rust_gdd_v02.md` and `docs/DESIGN_PRINCIPLES.md` override it.
> In particular, the ATP-100 model, ATP-driven exploration/ability costs, generic terminal
> recovery, and automatic hub restoration below are obsolete and must not be reimplemented.
> The explicit exception is the opt-in ATP-scarcity pressure projection used for generated-stretch
> QA. It is applied only after generation to the same mode-independent stretch spec; its interval
> and half-pip drain level are configurable, it starts on first movement, and it never funds
> abilities. Scarcity is the preferred approval run, while easier profiles only relax pressure.

**Enemy naming:** canonical in-world names used throughout (Sapscrap, Meeb, Flare, Naturalizer, Hidra, etc.). Biology references live in `data/enemy_ecosystem.md` — consult that doc for the roster, per-enemy role, and inter-enemy dynamics. When adding a new phase for an existing enemy, use the in-world name.

---

## Phase 0: Project Foundation

- [ ] **0.1** Define folder structure: `scenes/`, `scripts/`, `resources/`, `assets/`, `shaders/`, `ui/`
- [ ] **0.2** Choose rendering approach: TileMapLayer (Godot 4.x) for the world grid. 40 columns x 28 rows, 20px tile size (800x560 base resolution)
- [ ] **0.3** Create base tileset resource with tile IDs matching prototype: 0=floor, 1=wall, 2=flora, 3=iron_bloom, 4=shelter, 5=terminal, 6=food, 7=key, 8=locked_door, 9=hide_door
- [ ] **0.4** Set up autoload singletons: `GameState` (global state), `EventBus` (signals)
- [ ] **0.5** Configure project settings: 2D rendering, pixel art scaling, input map (click/tap, pause, character switch keys)

---

## Phase 1: World & Tilemap

- [ ] **1.1** Import map data from prototype's `MAP_DATA` (40x28 string grid) into a TileMapLayer scene
- [ ] **1.2** Create the six character-specific memory maps as additional data layers: `PERIS_MEMORY`, `ASTER_DATA`, `ENDO_DATA`, `OLI_DATA`, `TYREG_DATA`, and Myke's road network (generated on unlock)
- [ ] **1.3** Implement tile property lookup: `is_walkable(x, y)`, `get_tile_type(x, y)`, `is_blocked(x, y, locked_doors)`
- [ ] **1.4** Place interactable positions from map data: shelters, terminals, food, flora, keys, locked doors, hide rooms, flures (3 fixed positions), lock terminals (2 fixed positions)

---

## Phase 2: Core Character System

- [ ] **2.1** Create `Character` scene (CharacterBody2D or Node2D + script): position, stats (HP, maxHP, ATP, maxATP, stamina, maxStamina), vision radius, color
- [ ] **2.2** Implement character state machine: `idle`, `moving`, `resting`, `downed`, `channeling`, `phagocytosing`
- [ ] **2.3** Define per-character defaults from prototype:
  - Aster: HP 100, ATP 100, vision 6, color #4a9eff
  - Peris: HP 100, ATP 80, vision 5, color #ffaa44
  - Endo: HP 120, ATP 90, vision 4, color #66aa88
  - Myke: HP 90, ATP 70, vision 5, color #ff6644 (unlocked day 4)
  - Oli: HP 100, ATP 80, vision 4, color #44bbaa (unlocked day 7)
  - Tyreg: HP 80, ATP 60, vision 5, color #aa44dd (unlocked day 10)
- [ ] **2.4** Implement running toggle: walk speed 0.018, run speed 0.055. Running drains stamina (30/s, 45/s while dragging). Auto-stop when stamina hits 0
- [ ] **2.5** Implement cautious mode toggle: paths avoid iron_bloom tiles (hazard cost +20 in pathfinding). Linked mode ties cautious=!running
- [x] **2.6** Historical ATP drain replaced by the opt-in post-generation scarcity pressure projection (configurable interval and 0.5-pip drain increments; current named preset is 1 ATP / 60s after first movement, ATP can reach zero, and later zero-ATP ticks cost 5 HP). Generation never branches on it. Stamina regeneration remains a separate movement-system concern

---

## Phase 3: Pathfinding & Movement

- [ ] **3.1** Implement A* pathfinding with 8-directional movement (including diagonals at 1.41 cost)
- [ ] **3.2** Diagonal corner-cutting prevention: can't cut through walls diagonally
- [ ] **3.3** Pathfinding respects explored tiles only: unknown tiles are treated as passable, explored walls/locked doors are avoided
- [ ] **3.4** Cautious mode: add +20 cost to hazard tiles (iron_bloom) during pathfinding
- [ ] **3.5** Road bonus: -0.4 cost on road tiles (Myke's network) during pathfinding
- [ ] **3.6** Click-to-move: click/tap on map → pathfind from character position → set path
- [ ] **3.7** Path following: move along waypoints, shift to next when within 0.1 distance
- [ ] **3.8** Speed modifiers: Endo 1.25x base, Oli Conduct 1.35x, road tiles 1.3x, dragging 0.5x
- [ ] **3.9** Dynamic repath: when newly-explored tiles reveal a wall/locked door on the current path, recalculate. Show "Path blocked" if no path exists
- [ ] **3.10** Path visualization: dashed line along path (solid color for explored tiles, gray for unknown), destination marker circle

---

## Phase 4: Fog of War & Perception System

- [ ] **4.1** Per-character `explored` tile set (Set of Vector2i). Tiles within vision radius are added each frame
- [ ] **4.2** Pre-knowledge per character on game start:
  - Aster: knows all terminal, door, iron_bloom, hide_room positions + outer walls
  - Peris: knows a small area near center + partial paths
  - Endo: knows all food, flora, shelter, hide_room positions
  - Myke (on unlock): knows all floor and hide_room positions
  - Oli (on unlock): knows all terminal and locked_door positions
  - Tyreg (on unlock): knows hide_rooms, locked_doors, and starting corner area
- [ ] **4.3** Three-layer rendering per tile:
  - **True sight** (within vision radius): full-fidelity tile rendering with brightness falloff by distance
  - **Memory layer** (explored, outside vision): character-specific subjective rendering using their memory map
  - **Unexplored**: not rendered (black)
- [ ] **4.4** Aster memory layer: blueprint/schematic style. Blue grid overlay, monospace labels (Fe⚠, TRM, DOOR, HIDE, KEY), dim blue glows on terminals
- [ ] **4.5** Peris memory layer: warm-toned, inaccurate. Uses `PERIS_MEMORY` (which has shifted walls, missing objects). Warm amber grid, soft icons. False walls where Peris remembers walls that don't exist
- [ ] **4.6** Endo memory layer: green-tinted survival data. Shows food, flora, shelter, hide rooms with warm green icons and glows
- [ ] **4.7** Myke memory layer: road network only. Orange-highlighted road tiles. No walls or structure. Hide rooms shown dimly
- [ ] **4.8** Oli memory layer: electrical connections only. Teal-tinted. Lock terminals and terminal-locked doors labeled. Dashed connection lines from lock terminal to controlled shelter (visible in true sight when Oli is active)
- [ ] **4.9** Tyreg memory layer: tactical overlay. Purple-tinted. Iron blooms labeled. Naturalizer patrol routes shown as dashed lines (in true sight only)
- [ ] **4.10** Map layer conflict rule: true sight always overrides memory. Contradictions between memory layers outside anyone's vision remain unresolved
- [ ] **4.11** Knocked-out characters' map layers go dark until revived

---

## Phase 5: Day/Night Cycle

- [ ] **5.1** Game time: 0.0→1.0 per day. Advances at `dt * 0.003` while unpaused. Day counter increments at 1.0, wraps to 0.0
- [ ] **5.2** Time-of-day labels: Morning (<0.15), Afternoon (0.15-0.3), Evening (0.3-0.4), Dusk (0.4-0.5), NIGHT (>=0.5)
- [ ] **5.3** Vision radius changes:
  - Night (>=0.5): Peris→1, Aster→2, Endo→1.5
  - Evening: Peris degrades from 5 to 2 (sundowning formula: `max(2, 5 - (tod - 0.35) * 12)`)
  - Day: Peris=5, Aster=6, Endo=4
- [ ] **5.4** Darkness overlay: evening dims (0→0.3 alpha from 0.3→0.5 tod), night nearly black (0.3→0.85 alpha from 0.5→1.0 tod)
- [ ] **5.5** Night exposure damage: 3 HP/s for characters not in shelter or hide room
- [ ] **5.6** Night warning text at 0.5 tod: "NIGHT — GET TO SHELTER"

---

## Phase 6: Pause-and-Direct Control

- [ ] **6.1** Pause toggle: game time and all entity updates freeze. Player can still click to set waypoints, switch characters, use abilities
- [ ] **6.2** Path lines render brighter when paused (1.6x alpha boost, 2px line width)
- [ ] **6.3** Resume continues all movement and timers from where they were

---

## Phase 7: Sapscrap Enemy AI

- [ ] **7.1** Spawn 8 Sapscraps at game start, minimum 8 tiles from all characters. Stats: 30 HP, speed 0.025
- [ ] **7.2** State machine:
  - **Idle**: wander within 6 tiles of home position, new target every 3-7s, move at 0.5x speed
  - **Pursue**: move toward visible character (<6 tile detection), track last-seen position
  - **Investigate**: move to last-seen position at 0.8x speed when target lost
  - **Search**: wander within 4 tiles of last-seen for 8s, new target every 1.5-3.5s at 0.6x speed
  - **Scatter**: move away from hide room/shelter when target entered one, 4s duration
- [ ] **7.3** Attack state machine (when within 1.5 tiles of target):
  - **Windup** (0.6s): freeze in place, visual tell (pulsing ring expanding)
  - **Charge** (0.25s): lunge toward locked target position at 3x speed
  - **Impact**: deal `8 + day*2` damage to characters within 1.2 tiles
  - **Recover** (0.8s): vulnerable, can't move
- [ ] **7.4** Detection rules: can't detect characters in hide rooms (tile 9) or shelters (tile 4). Can't detect cloaked Endo
- [ ] **7.5** Territorial repulsion: idle Sapscraps push apart when within 3 tiles (`push = 0.003/distance`)
- [ ] **7.6** Daily scaling: target count = `min(20, 8 + floor((day-1) * 1.5))`. Stats scale: `maxHP = 30 + (day-1)*5`, `speed = 0.025 + (day-1)*0.002`
- [ ] **7.7** Death/respawn: on 0 HP, teleport to home position, reset to idle, become invisible for 12s
- [ ] **7.8** Flure override: active flures (within 8 tiles) attract Sapscraps, overriding character targeting

---

## Phase 8: Meeb (Amoeba) AI

- [ ] **8.1** Spawn 3 Meebs at game start, minimum 12 tiles from characters. Speed 0.022
- [ ] **8.2** Target acquisition: detect nearest entity (Sapscrap or character) within 6 tiles. Ignore cloaked Endo, characters in shelter/hide
- [ ] **8.3** Pursuit: move toward target. Speed 1.3x when within 3 tiles
- [ ] **8.4** Engulfing (Sapscraps): on contact, lock both in place, drain Sapscrap 10 HP/s. When Sapscrap dies, 2s digest pause, Sapscrap respawns at home
- [ ] **8.5** Character damage: on contact with character, deal 10 damage/s (continuous)
- [ ] **8.6** Roaming: when no target, wander with bias toward iron_bloom tiles (50% chance to target nearest iron_bloom within 8 tiles)
- [ ] **8.7** Endo NO Pulse interaction: slowed to 40% speed when within 5 tiles of Endo with active NO Pulse

---

## Phase 9: Flares (Night Hunters / Neutrophils)

- [ ] **9.1** Spawn 3 Flares at nightfall, maximizing distance from all characters. Speed 0.065
- [ ] **9.2** Priority: nearby Sapscrap (<3 tiles) > visible character (<8 tiles) > roaming drift
- [ ] **9.3** Sapscrap kill: on contact, instant kill (teleport to home, 8s respawn timer)
- [ ] **9.4** Character pursuit: move toward character, deal 40 damage/s on contact
- [ ] **9.5** Shelter circling: if target is in shelter/hide room, orbit at 2.5 tile radius at 0.6x speed
- [ ] **9.6** Roaming: drift toward nearest character at 0.4x speed with random wander
- [ ] **9.7** Always partially visible: glow visible up to 12 tiles even outside vision radius (alpha scales with distance)
- [ ] **9.8** Despawn at dawn (game time wraps to 0)

---

## Phase 10: Interactable & Channel System

- [ ] **10.1** Channel framework: action type, timer, duration, position, range. Progress while in range, cancel if character moves out of range, is downed, or starts resting
- [ ] **10.2** Food (tile 6): 1.0s channel. Gain 10/15/20 ATP (random). Mark tile as eaten (respawns after 3 days). Any character
- [ ] **10.3** Flora tending (tile 2):
  - Peris: 1.5s channel. Marks flora as tended (decays after 5 days). +5 HP. Tended flora gives nearby vision boost and stamina regen bonus
  - Myke: 1.0s channel. Marks tended. +15 stamina to self, +10 stamina to allies within 4 tiles
  - Others: message "Flora. Peris or Myke can tend it"
- [ ] **10.4** Data terminal (tile 5): Aster only, 2.0s channel. Reveals 8-tile radius on Aster's explored map. Terminal marked as used
- [ ] **10.5** Key (tile 7): 0.5s channel. Sets `keyCollected = true`
- [ ] **10.6** Locked door (tile 8): if key collected, instantly unlock. Otherwise "Locked. You need a key" and stop movement
- [ ] **10.7** Flure: Peris only, 1.0s channel. Activates for 18s (lures Sapscraps within 8 tiles). Fixed positions on map
- [ ] **10.8** Lock terminal: Oli or Aster, 1.5s channel. Unlocks the associated shelter (removes from blocked set, removes terminal)
- [ ] **10.9** Ammo pickup: any character, 0.5s channel. Removes ammo spot, adds 3 rounds to Tyreg. Auto-triggers on arrival
- [ ] **10.10** Channel progress bar: yellow bar below character, pulsing glow during channel

---

## Phase 11: Character Abilities

- [ ] **11.1** **Peris — Wrap**: 5s duration, 12s cooldown, 15 stamina cost. While active, absorbs 8 flat damage per hit from allies within 4 tiles. Absorbed damage transfers to Peris
- [ ] **11.2** **Peris — Harvest**: Must be on tended flora. 30s buff. Slow HP regen (0.5/s), vision boost (+harvestTimer*0.3), floating particle VFX
- [ ] **11.3** **Endo — NO Pulse**: 6s duration, 15s cooldown, 20 stamina cost. Enemies within 5 tiles slowed to 40% speed. Breaks cloak
- [ ] **11.4** **Endo — Cloak**: 10s duration, 25 stamina cost. Invisible to all enemies. Breaks on ability use
- [ ] **11.5** **Aster — EMP Hack**: AoE within 5 tiles. Deals 15 damage, suppresses enemies 8s, disrupts Meebs. 3-day cooldown, 30 stamina cost
- [ ] **11.6** **Aster — Phagocytosis** (day 7+): Target mode → tap weakened enemy (<50% HP, within 2 tiles). Lock both in place, drain 10 HP/s, heal Aster. 20s cooldown after consume. Tap to cancel
- [ ] **11.7** **Myke — Inflame**: Target mode → tap tile within 6 tiles. Creates fire zone (4s duration, 6 damage/s to enemies, 3 damage/s to allies within 1.2 tiles). 10s cooldown, 20 stamina
- [ ] **11.8** **Myke — Engulf**: Target mode → tap enemy within 5 tiles. Burns target 8s (4 HP/s self-damage, 2 HP/s to nearby enemies, 3 HP/s to nearby allies). 18s cooldown, 25 stamina
- [ ] **11.9** **Oli — Sheath**: Target mode → tap ally within 5 tiles. +25% of target's maxHP as shield. Decays over 8s. 10s cooldown, 15 stamina
- [ ] **11.10** **Oli — Conduct**: Target mode → tap ally within 4 tiles. +35% speed for 8s. 14s cooldown, 15 stamina
- [ ] **11.11** **Tyreg — Shoot**: Target mode → tap enemy. 25 damage. Uses 1 ammo. 2s cooldown
- [ ] **11.12** **Tyreg — Suppress**: Target mode → tap enemy within 4 tiles. Freezes 5s. 10s cooldown, 20 stamina
- [ ] **11.13** Ability targeting mode: enter mode on button press, click target on map, cancel with X button or by clicking empty space

---

## Phase 12: Damage System

- [ ] **12.1** Damage application order: Peris Wrap absorption (flat 8 per hit) → Oli Shield absorption → HP damage
- [ ] **12.2** Attack timer: 1.5s on HP damage (red flash, "!" indicator). Channel interrupted on any HP damage
- [ ] **12.3** Iron bloom environmental damage: 4 HP/s + 5 stamina/s drain while standing on tile 3
- [ ] **12.4** Peris flora vision boost: +1.5 vision radius when near tended flora
- [ ] **12.5** Stamina regen formula: base 15/s when idle. Reduced to 0.2x while moving (not running). On iron: regen * 0.3. Near tended flora: regen * 1.3. ATP > 20: full rate. ATP > 0: 5/s rate. ATP = 0: no regen

---

## Phase 13: Party Management

- [ ] **13.1** Character switching: click portrait or press key to switch active character. Clears alert on switched-to character
- [ ] **13.2** Multi-select: long-press portrait to enter multi-select. Toggle characters. Click map to move all selected. X to exit
- [ ] **13.3** Alert system: non-active characters who can see Sapscraps/Naturalizers/Meebs get yellow "!" indicator and pulsing ring
- [ ] **13.4** Downed state: HP reaches 0 → downed. Can't move, act, or rest. Path cleared. Message: "[Name] is DOWN! Drag them to a shelter"
- [ ] **13.5** Dragging: auto-pickup when walking over downed character. Dragged character follows dragger. 0.5x speed, 2x stamina drain
- [ ] **13.6** Revive at shelter: downed character at shelter tile with a conscious ally nearby → 10s revive timer → revive at 1 HP, auto-rest
- [ ] **13.7** All-downed = game over

---

## Phase 14: Rest & Night Skip

- [ ] **14.1** Rest action: must be at shelter. Not downed. ATP >= 5. Sets resting=true, clears path. Heals 1 HP/s, drains 0.4 ATP/s, regens stamina 10/s
- [ ] **14.2** Auto-stop rest: at shelter, stop if ATP empty. Not at shelter, stop if HP full or ATP empty
- [ ] **14.3** Night skip: all conscious characters resting at shelter during night → skip to dawn
  - Base healing: `50 * nightFraction` HP, costs `15 * nightFraction` ATP
  - Restful bonus: 1.5x healing if nobody is downed anywhere
  - Downed at shelter: revive at 1 HP + 30% of base healing
  - Downed outside shelter: left behind, no healing
- [ ] **14.4** Dawn reset: clear Flares, reset all enemy positions/HP/states, scale enemy count/stats for new day, respawn consumed food (after 3 days), decay tended flora (after 5 days), regenerate lock terminals

---

## Phase 15: Character Recruitment

- [ ] **15.1** **Myke (day 4)**: Spawn at (24.5, 18.5). Unlock road network (row/column grid pattern). Roads give 1.3x speed bonus. Myke's memory map: roads + hide rooms
- [ ] **15.2** **Oli (day 7)**: Spawn at (2.5, 2.5). Set up lock terminals: (4,2)→shelter(2,2), (22,18)→shelter(24,18). Selective quarantine: just-used shelter gets locked. Oli's memory map: terminals + locked doors
- [ ] **15.3** **Tyreg (day 10)**: Spawn at (2.5, 2.5). Activate Naturalizer patrols (3 patrols with waypoint routes). Place ammo spots (6 fixed locations). Full containment: all shelters locked. Tyreg's memory map: iron blooms + hide rooms

---

## Phase 16: Shelter Lock System

- [ ] **16.1** Lock terminals: two fixed positions, each controlling one shelter. Regenerate each dawn
- [ ] **16.2** Selective quarantine (days 7-9, Oli unlocked): just-used shelter gets locked, other stays open
- [ ] **16.3** Full containment (day 10+, Tyreg unlocked): all shelters locked
- [ ] **16.4** Lock terminal activation: Oli or Aster, 1.5s channel, unlocks associated shelter
- [ ] **16.5** Naturalizer scanner interference: when Naturalizer patrol passes within 3 tiles of lock terminal, temporarily unlock associated shelter for 10s
- [ ] **16.6** Temporary unlock indicator: pulsing green glow on shelter + countdown timer
- [ ] **16.7** Lock re-engagement: shelter re-locks when temp unlock timer expires

---

## Phase 17: Naturalizer Patrol System

- [ ] **17.1** 3 patrol routes with fixed waypoints (see prototype for exact coordinates). Speed 0.015
- [ ] **17.2** Patrol behavior: walk to next waypoint in sequence, loop
- [ ] **17.3** Detection: scan for characters within 4 tiles (ignore cloaked, in shelter/hide)
- [ ] **17.4** Chase: 8s leash, 1.5x speed. Deal 20 damage/s on contact. Return to patrol when leash expires or target at 8+ tiles
- [ ] **17.5** Scanner line visual: rotating line from Naturalizer position
- [ ] **17.6** Patrol route visualization: dashed line when Tyreg is active character
- [ ] **17.7** Tyreg immune balancing: Tyreg recognized by NKs, they defer briefly (from GDD — specific implementation TBD)

---

## Phase 18: UI System

- [ ] **18.1** HUD layout: title bar, canvas/viewport, time bar, character cards, controls
- [ ] **18.2** Time bar: gradient progress bar (gold→orange→red→dark), time-of-day label, day counter
- [ ] **18.3** Character cards: name, HP/ATP/STA bars, status indicators (downed ✗, resting zzz, alert !, under attack !, dragging). Active character highlighted. Click to switch
- [ ] **18.4** Long-press for multi-select mode (portrait toggle, X to exit)
- [ ] **18.5** Control buttons: Pause/Resume, Walk/Run, Link toggle, Safe/Direct routing, Rest
- [ ] **18.6** Ability buttons: context-sensitive per active character. Show cooldowns, costs. Target mode indicator. Cancel button
- [ ] **18.7** Message bar: bottom of screen, text with timed fade. Gameplay feedback and narrative messages
- [ ] **18.8** View Key/Legend: collapsible panel explaining current character's perception layer
- [ ] **18.9** Menu screen: title, how-to-play instructions, Begin button
- [ ] **18.10** Death screen: "we fell.", day count, Start Over / Load Save buttons
- [ ] **18.11** Debug panel: unlock characters, skip to dusk, advance day, heal all, save/load

---

## Phase 19: Save/Load System

- [ ] **19.1** Serialize full game state: character positions/stats/states, enemies, Meebs, Naturalizers, explored sets, day/time, door locks, consumed food, tended flora, all flags
- [ ] **19.2** Handle object references: convert entity cross-references to IDs for serialization, restore on deserialize
- [ ] **19.3** Save trigger: per-shelter (on rest/night skip). Export to JSON file
- [ ] **19.4** Load: from JSON file, reconstruct full state, resume gameplay

---

## Phase 20: VFX & Rendering

- [ ] **20.1** Tile glow effects: flora (green, stronger when tended), iron_bloom (red), terminal (blue, flickers near Naturalizer), shelter (blue), lock terminal (teal)
- [ ] **20.2** Fire zone rendering: pulsing orange/red with inner yellow core
- [ ] **20.3** Sapscrap rendering: color by state (idle=brown, pursue=red, investigate=orange, search=tan, scatter=yellow). Attack state visuals: windup ring, charge trail, impact flash, recover dim
- [ ] **20.4** Meeb rendering: translucent shifting blobs (two overlapping circles with sine-wave oscillation), engulfing animation (larger pulsing, prey fading inside)
- [ ] **20.5** Flare rendering: dark red with glowing red eyes, always slightly visible in darkness
- [ ] **20.6** Naturalizer rendering: clean white circle, rotating scanner line, chase timer ring, detection radius when pursuing, scanner disruption spark near lock terminals
- [ ] **20.7** Character rendering: colored circle with letter label, white selection ring for active, vision radius tint, path line. Status overlays: red flash when attacked, yellow alert ring, downed X, resting Z, channel progress bar, shield glow, dragging line
- [ ] **20.8** Grid overlay: per-character colored grid (not Peris)
- [ ] **20.9** Ability VFX: Wrap aura (dashed yellow ring), Sheath connection line, Shield glow, NO Pulse green area, Cloak transparency, Harvest floating particles, Phagocytosis blue membrane, Conduct dashed line, burning enemies (orange ring + area glow), suppressed enemies (purple dashed ring + X)

---

## Phase 21: Audio (Not in Prototype — New Work)

- [ ] **21.1** Ambient soundscape: biological hum, machinery, fluid. Different per zone/time
- [ ] **21.2** Day/night transition audio cues
- [ ] **21.3** Enemy detection stinger (Sapscrap pursuit)
- [ ] **21.4** Flare warning sound
- [ ] **21.5** Ability activation SFX per ability
- [ ] **21.6** Channel completion chime
- [ ] **21.7** Character downed alert
- [ ] **21.8** UI interaction sounds (button clicks, character switch)
- [ ] **21.9** Rest/dawn transition

---

## Phase 22: Future Scope (GDD Features Beyond Prototype)

These are in the GDD but not yet implemented in the prototype. Defer until core is solid.

- [ ] **22.1** Multiple zones (Zone 1: sheltered, Zone 2: corridor/Naturalizer patrols, Zone 3: pathogen territory). Metroidvania ability gating between zones
- [ ] **22.2** Peris perception degradation shader: cartographic memory-map distortion that worsens over days (desaturation, spatial warping, detail loss, fog thickening). See GDD section 16.2
- [ ] **22.3** Sapscrap iron gradient system: static iron map with event-based updates, proximity detection, party iron as mobile attractor. See GDD section 16.1
- [ ] **22.4** Additional threat types: Infiltrators (zone transformers), Recruiters (capture enemies), Cytokine storms (timed hazards), Biofilm patches (slow terrain), Spore fields, Resonance zones
- [ ] **22.5** Flora species taxonomy: different species with distinct gameplay effects (wayfinding, bioluminescence, medicine, communication network, fast-travel via mycelial network)
- [ ] **22.6** LaFerr's device: narrative MacGuffin + mid-game tool (40Hz gamma entrainment for Myke, diagnostics, therapeutic modes)
- [ ] **22.7** Multiple endings (4 tiers based on exploration depth, party recruitment, cure components found)
- [ ] **22.8** Difficulty settings: adjustable degradation rate, ATP consumption, enemy aggression
- [ ] **22.9** Ability tier progression: Myke fire tiers (Flare/Blaze/Inferno), Oli buff tiers (Insulate/Conduct/Mend/Restore), Tyreg gun tiers (Sidearm/Rifle/Suppressor)
- [ ] **22.10** Endo stays behind mechanic: Endo is an early-game companion who remains at Zone 1 when the party ventures deeper
- [ ] **22.11** Molecule characters as items/systems: Cydin, Nox, Tau, Clement, Gilphorax as consumables, equipment, or environmental regulators
- [ ] **22.12** Roguelike mode (post-launch DLC): permadeath, procedural map elements, permanent map layer loss on character death
- [ ] **22.13** DLC characters: Ninj (Meninges), Pendy (Ependymal Cell)

---

## Suggested Build Order (Critical Path)

For a playable vertical slice, build in this order:

1. **Phases 0-1**: Project setup + tilemap → see the world
2. **Phase 2 + 3**: Character + pathfinding → click to move
3. **Phase 4**: Fog of war → the core perception mechanic works
4. **Phase 5 + 6**: Day/night + pause → survival pressure exists
5. **Phase 7**: Sapscraps → something to survive against
6. **Phase 10 (food + shelter only)**: Eat, rest → survival loop closes
7. **Phase 14**: Rest/night skip → complete day cycle
8. **Phase 18 (minimal)**: Basic UI → playable
9. **Phase 12**: Damage system → combat feels right
10. **Phase 13**: Party management → multi-character play
11. **Phases 8-9**: Meebs + Flares → threat ecology
12. **Phase 11**: Abilities → tactical depth
13. **Phase 15-17**: Recruitment + locks + NKs → mid/late-game systems
14. **Phase 19**: Save/load → persistence
15. **Phase 20-21**: Polish → ship
