# Level-Design Research: Elements Fished from Comparable Games

> **Character-kit note (2026-07-21):** older TRAWF translations in this research use
> `TRACE`, `BLOOM`, and `BRACE` as proposal shorthand. They are not canonical cast
> abilities. Preserve the underlying asymmetric-information lesson through contextual
> world interactions and overlays; the committed cast roster is EMP and Wrap only.

Deep-research pass over the pause-and-direct stealth-party / procedural-gating / escalation-clock corpus.
Every claim below survived adversarial verification (3 independent votes; 24 of 25 unanimous) and traces to
a primary source (GDC/devcom talks, developer postmortems, peer-reviewed PCG papers). 25 claims merged into
17 findings. Companion to DESIGN_PRINCIPLES.md — each element names the register principles it serves.

## Synthesis

Three verified primary-source corpora anchor the report: Mimimi's postmortems/talks (Shadow Tactics, Desperados III, Shadow Gambit) supply the within-chunk grammar — the mutual-overwatch multi-solution 'setup' atom, a counterability-keyed guard-type grammar, two-height cover as explicit data, radical perception legibility, golden-path-plus-open-solutions, and weakness-forced team combination; Joris Dormans' PCG Workshop papers (2010/2011) supply the chunk-topology layer — mission/space two-phase generation, tight-vs-loose coupling edges, symbol-provenance gating enforcement, solvability-by-construction rewrite rules, and lock-before-key ordering; Klei's Invisible Inc deep dive supplies the run-scale layer — a quantized, telegraphed escalation clock that makes elapsed time (not per-room difficulty) the pressure source. All 25 surviving claims trace to primary sources (GDC/devcom talks, developer postmortems, peer-reviewed papers), 24 of 25 by unanimous 3-0 votes, merged here into 17 findings. Highest-leverage for TRAWF, because they compose mechanics already in the codebase: (1) the mutual-overwatch setup as the chunk-atom recipe (LOS detection + lures + conceal tiers exist), (2) the anchor/timer/filler guard grammar (static sentries + patrol cadences + distraction exist), (3) tight/loose coupling edges + provenance tracking in the seeded chunk generator (gating invariant already proven per-chunk), (4) the 6x5-style quantized escalation clock riding the existing scheduler/day-night economy, and (5) Mimimi's weakness-forced-combination rule as the formal statement of TRAWF's shadow-solve requirement. Notable coverage gap: no claims survived on ascent-with-fall-cost structures (Rain World, Jusant), Spelunky's level grammar, or Unexplored's cyclic generation, so the wash/sweep-back design remains unbenchmarked against a shipped source.

## Findings

### LINEAGE/SOURCE BASE

LINEAGE/SOURCE BASE: Mimimi's Shadow Tactics is the explicit modern revival of the Commandos/Desperados pause-and-direct party-stealth idiom TRAWF draws on (the studio itself framed it as reviving a genre 'dead for over 10 years'), and the GDC 2018 postmortem by designer Moritz Wagner is a primary practitioner source covering exactly TRAWF's open questions: how characters and levels were designed and how the whole game was paced.

**Evidence & TRAWF translation:** GDC Vault session 1025239 description verbatim: 'Developing Shadow Tactics meant reviving a genre that has been dead for over 10 years' and 'This session will share how they designed the characters and levels, what their goal were for the story and how they tried to pace the whole game out.' Corroborated by Mimimi's written Game Developer postmortem. Establishes Mimimi's talks/postmortems as the authoritative practitioner corpus for TRAWF's genre.

**Confidence:** high | **Verification:** 3-0 (x2, merged claims 0+1)
- https://www.gdcvault.com/play/1025239/-Shadow-Tactics-Postmortem-Commandos

### WITHIN-CHUNK — THE 'SETUP' AS THE ATOMIC PUZZLE UNIT

WITHIN-CHUNK — THE 'SETUP' AS THE ATOMIC PUZZLE UNIT: Mimimi's atomic level-design unit is a multi-solution puzzle built from the level's predefined character toolbox, containing at least two enemies watching EACH OTHER (mutual overwatch is what makes it a puzzle rather than a sequential pick-off), sized to ideally one screen, anchored to a point of interest (blocked path, set piece, objective, or usable), with one main setup plus a few smaller ones per area.

**Evidence & TRAWF translation:** Verified verbatim in the devcom digital 2020 talk 'Desperados III — Designing a Level the Mimimi Way' (~26:33-27:22): 'a setup is basically a multi-solution puzzle... at least two enemies that are looking at each other otherwise... it wouldn't be a challenge at all... one area usually contains one main setup and a few smaller ones... in the perfect world it would be one [screen].' TRAWF translation: this is the missing recipe for TRAWF's chunk atom — the gated puzzle room's INTERIOR. TRAWF already has LOS detection, patrol cadences, conceal tiers, and lures; the composition rule to adopt is mutual overwatch (each guard covered by another's cone) so no single lure/hide trivially unpicks the room, plus the POI anchor (the gate/console IS the point of interest). Directly serves gated composition and shadow solves (multi-solution is definitional, not emergent).

**Confidence:** high | **Verification:** 3-0
- https://www.youtube.com/watch?v=mLGBbFPjicQ

### WITHIN-CHUNK — GUARD-TYPE GRAMMAR KEYED TO COUNTERABILITY

WITHIN-CHUNK — GUARD-TYPE GRAMMAR KEYED TO COUNTERABILITY: Setups are composed from a small enemy grammar: a static 'poncho' anchor guard who never leaves his post even when distracted (the 'problem guard' the puzzle is built around); an 'elite' who patrols a fixed loop acting as the setup's walking TIMER, is counterable by only one specific character (Hector), and uniquely sees through Kate's disguise; and ordinary freely-distractable guards as filler material.

**Evidence & TRAWF translation:** Verified in the devcom talk transcript: 'this is what we might call the problem guard... a static type or in the game it's called poncho... they don't leave their post'; 'this elite also kind of acts as a timer in this specific setup'; 'he's the only guard type that can see her and raises the alarm'; elites are 'very beefy so Hector is the only one who can take them out.' Corroborated by gamepressure/Neoseeker guides (Long Coats see through disguise, Hector counters them). TRAWF translation: composes almost entirely from existing mechanics — a lure-immune anchor enemy (set_character_distracted already only SHRINKS range, so a 'won't move' flag is trivial), a patrol-loop enemy whose scheduler cadence IS the timer Aster's TRACE reads (perception asymmetry becomes the counter), and per-character-counterable enemy types that make the 2-character shadow solve concretely harder when the counter-character is the absent one.

**Confidence:** high | **Verification:** 3-0
- https://www.youtube.com/watch?v=mLGBbFPjicQ

### WITHIN-CHUNK — TWO-HEIGHT COVER AS EXPLICIT PER-ASSET DATA

WITHIN-CHUNK — TWO-HEIGHT COVER AS EXPLICIT PER-ASSET DATA: Desperados III implements cover as data on every asset: nav-mesh occluders plus view-cone occluders in exactly two heights — HIGH occluders block enemy vision completely (safe standing), LOW occluders block only while crouched — and a decoration/art pass can silently break a setup if an artist changes an occluder's height or footprint, so the constraint must be guarded.

**Evidence & TRAWF translation:** Verified verbatim from the talk's captions: 'the high ones block the vision completely so you can even stand up behind it you will never be seen the lower ones block them partially so if you are crouched you're fine'; and the breakage warning: 'if I place a couch here that makes the low cover high cover I can't do that... that has to be avoided at all costs.' TRAWF translation: this IS TRAWF's conceal-tier system (CONCEAL_MEDIUM ~ low occluder, CONCEAL_FULL ~ high occluder) — the adoptable elements are (a) binding tiers to ASSETS/geometry rather than authored zones so chunk generation places cover and gets detection semantics for free, and (b) a validate()-style lint (TRAWF already has the RoomModelBinder pattern and --test-chunk-* guards) that fails when a model re-export changes a cover asset's effective tier.

**Confidence:** high | **Verification:** 3-0
- https://www.youtube.com/watch?v=mLGBbFPjicQ

### WITHIN-CHUNK — LEGIBILITY OVER REALISM AS A STATED PILLAR

WITHIN-CHUNK — LEGIBILITY OVER REALISM AS A STATED PILLAR: Mimimi's design pillar for Desperados III was giving the player maximum information: vision cones and striped safe-while-crouched zones deliberately trade realism for perception rules that are 'easy to understand and fast to process,' so the player always knows exactly why a plan failed.

**Evidence & TRAWF translation:** Creative Director Dominik Abé verbatim: 'One of our design pillars for Desperados III was to give the player as much information as possible... far from realism but it represents basic perception of vision and sound in a way that is easy to understand and fast to process,' plus 'we always want the players to know why their plan fails.' TRAWF translation: serves perception asymmetry directly — each character's overlay (WHEN/cadence, WHERE/flora, survival tiles) should be this stylized-legible, and detection failures must be attributable in the overlay the player was reading (e.g. show the inner CONCEAL_MEDIUM band as a striped region inside the outer cone, exactly Mimimi's visual grammar). A failed hide the player can't explain is a bug by this pillar.

**Confidence:** high | **Verification:** 3-0
- https://www.gamedeveloper.com/design/designing-the-real-time-stealth-and-combat-of-i-desperados-iii-i-

### WITHIN-CHUNK/RUN — GOLDEN PATH PLUS OPEN SOLUTIONS

WITHIN-CHUNK/RUN — GOLDEN PATH PLUS OPEN SOLUTIONS: Desperados III levels are authored with a designed 'golden path' and sub-paths, but core mechanics are intentionally too open for single-solution puzzles — player-invented strategies beyond intended routes are treated as the design's goal, not its failure.

**Evidence & TRAWF translation:** Abé verbatim: 'We always design the levels with a golden path and some sub paths but the real fun for us begins when the players choose their own paths and strategies... The core mechanics are way too open to create situations or puzzles where only one solution would work.' TRAWF translation: formalizes TRAWF's solver requirement — the generator should verify a golden path (specialist trio solve) plus at least one sub-path (the 2-character shadow solve) as SOLVABILITY PROOFS, while the mechanic set (lures + conceal + held consoles + cadence timing) stays open enough that unverified emergent solves exist. TRAWF's solution-as-data replay artifact is the natural home for the golden path.

**Confidence:** high | **Verification:** 3-0
- https://www.gamedeveloper.com/design/designing-the-real-time-stealth-and-combat-of-i-desperados-iii-i-
- https://www.youtube.com/watch?v=mLGBbFPjicQ

### WITHIN-CHUNK — SHORT SYNCHRONIZED BURSTS, NOT LONG ACTION CHAINS

WITHIN-CHUNK — SHORT SYNCHRONIZED BURSTS, NOT LONG ACTION CHAINS: Showdown mode queues exactly ONE action per character (up to 5 simultaneously) and Mimimi deliberately rejected longer pre-planned chains because 'long chains of pre-planned actions would make the game feel very different and would nearly change the genre' — the pause-and-direct feel lives in short synchronized bursts resolved in real time.

**Evidence & TRAWF translation:** Abé verbatim: 'Making an elaborate plan with 5 characters at the same time and seeing it unfold can lead to the most satisfying moments... We decided against chaining more than one main player action because we want the game to stay real-time as much as possible.' TRAWF translation: guides TRAWF's trio choreography moments (one member holds an override console while two cross a guard cone) — the design ceiling should be one queued action per member released together, not scripted multi-step programs; TRAWF's pause + per-character command queue on the scheduler already supports exactly this shape. Serves trio co-op with held roles.

**Confidence:** high | **Verification:** 3-0
- https://www.gamedeveloper.com/design/designing-the-real-time-stealth-and-combat-of-i-desperados-iii-i-

### WITHIN-CHUNK/RUN — WEAKNESS-FORCED COMBINATION AND ANY-SUBSET SOLVABILITY (the shadow-solve rule stated by a shipped studio)

WITHIN-CHUNK/RUN — WEAKNESS-FORCED COMBINATION AND ANY-SUBSET SOLVABILITY (the shadow-solve rule stated by a shipped studio): Mimimi's explicit character rule is that every skill is strong in combination with teammates' skills yet effective solo (Shadow Tactics), and Shadow Gambit's free crew selection (any subset per mission) is balanced by built-in per-character weaknesses that force combination play (e.g. sniper Teresa must physically recover her projectile after each shot), so encounters must remain solvable by MANY different character combinations rather than a fixed roster.

**Evidence & TRAWF translation:** Shadow Tactics postmortem verbatim: 'every character skill was strong in combination with skills of other teammates but also quite effective on its own' (framed as the corrective to Commandos 2 making characters 'too powerful, eventually harming the unique team play aspect'). Shadow Gambit Dev Diary #4 verbatim: 'The long ranged sniper Theresa for example needs to regain her arrow after shooting,' with weaknesses explicitly overcome by combining crew abilities, and islands 'designed to allow multiple different approaches.' TRAWF translation: this is TRAWF's shadow-solve principle validated by two shipped games — give each committed mechanic a legible cost or weakness whose mitigation comes from another character's contextual perception or action (for example, Peris revealing flora ground that makes Aster's timing read usable), then require the generator's solver to prove solvability for the designated 2-character subparties, exactly Shadow Gambit's any-subset constraint. This lesson does not authorize inventing character abilities.

**Confidence:** high | **Verification:** 3-0 (x2, merged claims 9+12)
- https://www.gamedeveloper.com/business/postmortem-mimimi-s-i-shadow-tactics-blades-of-the-shogun-i-
- https://www.shadowgambit.com/category/dev-diary/

### CHUNK-TOPOLOGY — OPEN-APPROACH ENCOUNTERS COST MORE, AND DECOMPRESSION ZONES ARE DELIBERATE

CHUNK-TOPOLOGY — OPEN-APPROACH ENCOUNTERS COST MORE, AND DECOMPRESSION ZONES ARE DELIBERATE: Shadow Gambit's islands have an open structure where nearly every encounter must work from ALL approach directions — which Head of Design Mo Wagner identifies as a real design burden versus corridor-vignette missions ('there is no direction anymore we can focus on') — and Mimimi paces these levels with an explicitly larger emphasis on easy 'in-between' areas the player just passes through between hard setups.

**Evidence & TRAWF translation:** Dev Diary #4 verbatim: 'Shadow Gambit doesn't feature a real open world, but islands with a very open structure... Almost all encounters can be approached from all sides, which makes it different to design for us' and 'a larger emphasis on in-between areas where enemy setups aren't too hard and you just go through.' TRAWF translation: two lessons for chunk topology. (1) TRAWF's gated chunks with defined entry/exit are the CHEAPER-to-design corridor-vignette form — keep single-approach chunks as the default atom and treat any open-approach chunk as a deliberate, expensive exception. (2) Between gated puzzle rooms, generate low-threat connective tissue (roaming set_roam ambience, no setups) as an explicit pacing element — decompression is authored, not leftover space. Scope caveat: the decompression statement is specific to Shadow Gambit's open islands.

**Confidence:** high | **Verification:** 3-0 (x2, merged claims 10+11)
- https://www.shadowgambit.com/category/dev-diary/

### WITHIN-CHUNK/RUN — INFORMATION AS A LEVEL OBJECTIVE WITH A RISK-PRICED ALTERNATIVE

WITHIN-CHUNK/RUN — INFORMATION AS A LEVEL OBJECTIVE WITH A RISK-PRICED ALTERNATIVE: Desperados III's New Orleans level replaced passive walk-and-click investigation with an information economy: three randomly chosen candidate targets, only one correct per playthrough, discoverable either by spreading party members out to eavesdrop on clue conversations in free/lightly-guarded areas, or by brute-forcing all three heavily guarded target zones — bought/risked information as a genuine alternative to force.

**Evidence & TRAWF translation:** Verified in the devcom talk: 'we introduced three randomly chosen objectives only one of them is right... the idea is that you spread out with your characters listen in on those conversations and... figure out the right target'; the brute-force path is explicit ('eventually you're gonna find the letter which is also an option'). Corroborated by Mission 10 walkthroughs (randomized Jackal/Spider/Hawk letter-holder). TRAWF translation: the cleanest shipped template for TRAWF's 'information is content' principle — a seeded chunk variable (which of 3 gates is live, which cadence is real) knowable either through a cheap-but-time-costing perception read (spread the trio, each overlay reads a different clue — perception asymmetry makes the eavesdrop path inherently multi-character) or through the expensive direct probe (walk into the guarded zone and test it). Also the shipped precedent for per-seed randomization inside an authored chunk.

**Confidence:** high | **Verification:** 3-0
- https://www.youtube.com/watch?v=mLGBbFPjicQ

### CHUNK-TOPOLOGY (GENERATION) — MISSION AND SPACE ARE SEPARATE ARTIFACTS, GENERATE MISSION FIRST

CHUNK-TOPOLOGY (GENERATION) — MISSION AND SPACE ARE SEPARATE ARTIFACTS, GENERATE MISSION FIRST: Dormans' framework models a complete level as a double structure — a MISSION (graph of tasks/gates) and a SPACE (geometric layout) — and procedural generation works best in two steps: generate the mission graph first (graph grammars, non-linear structures preferred for exploration games), then generate/grow a space to accommodate it; the separation yields a richer palette than treating them as isomorphic (e.g. System Shock 2 hosting multiple missions in one space).

**Evidence & TRAWF translation:** Dormans 2010 (PCGames workshop, ACM) verbatim: 'The levels of action adventure games are double structures consisting of both a space and a mission... it is best to break down the generation process in two steps'; 2011 paper: 'Separating between mission and space allows for far richer palette of level design strategies,' with the System Shock 2 same-space-multiple-missions example. The same architecture later shipped in Unexplored. TRAWF translation: directly ratifies TRAWF's pipeline — the chunk/gate dependency graph (nested archetypes, which gate blocks which) should be generated and SOLVED first as pure data, then bound to geometry (meta-template warps, room layouts); TRAWF's solution-as-data replay lives naturally at the mission layer. Also licenses reusing one modeled space for multiple generated missions (roguelike re-runs through familiar geometry).

**Confidence:** high | **Verification:** 3-0 (x2, merged claims 13+19)
- https://pcgworkshop.com/archive/dormans2010adventures.pdf
- https://www.pcgworkshop.com/archive/dormans2011design.pdf

### CHUNK-TOPOLOGY (GENERATION) — AN EDGE-TYPE VOCABULARY PLUS PROVENANCE TRACKING ENFORCES GATING AT GENERATION TIME

CHUNK-TOPOLOGY (GENERATION) — AN EDGE-TYPE VOCABULARY PLUS PROVENANCE TRACKING ENFORCES GATING AT GENERATION TIME: Dormans' mission graphs distinguish TIGHT coupling (double edges: the subordinate MUST be placed spatially behind its superordinate — a hard gate) from LOOSE coupling (placeable anywhere — free-floating content), and the space generator enforces this by binding each shape-grammar rule to a mission terminal symbol and storing which mission symbol produced each spatial element — guaranteeing keys/rewards land behind their specified tests/locks, never at random reachable locations.

**Evidence & TRAWF translation:** Verbatim from the paper: 'the double edges indicate a tight coupling... the subordinate must be placed behind the superordinate in the generated space... A normal edge represents a loose coupling'; and 'The algorithm stores a reference to the mission symbol for which each element was generated... This prevents the algorithm from placing keys and items at random locations instead of behind tests or locks as specified by the mission.' Confidence medium only because the provenance claim drew a 2-1 vote: the paper never says 'provably' (it is a prototype with a heuristically-mitigated short-circuit risk in loop reconnection), though the mechanism itself is verbatim. TRAWF translation: this is TRAWF's 'you provably cannot walk past the puzzle' invariant implemented as a generation-time constraint rather than a post-hoc check — tag every generated chunk element with its mission-graph provenance, mark gate edges tight vs ambient-content edges loose, and keep TRAWF's existing per-chunk topology proof as the verification layer Dormans' prototype lacked.

**Confidence:** medium | **Verification:** 3-0 + 2-1 (merged claims 14+15)
- https://pcgworkshop.com/archive/dormans2010adventures.pdf

### CHUNK-TOPOLOGY (GENERATION) — LOCK-AND-KEY REWRITE RULES GIVE SOLVABILITY BY CONSTRUCTION AND EXACT SIZE CONTROL

CHUNK-TOPOLOGY (GENERATION) — LOCK-AND-KEY REWRITE RULES GIVE SOLVABILITY BY CONSTRUCTION AND EXACT SIZE CONTROL: Just two graph rewrite rules suffice to transform a linear task sequence into a branching, gated level; by inspection of the rule set, no rule removes the node after a lock and every generated branch terminates in a key required to proceed elsewhere, so all tasks must be completed to finish — and level size is exactly the length of the initial mission (demo: levels generated from a 21-task mission).

**Evidence & TRAWF translation:** Dormans 2011 (PCGames, ACM) verbatim: 'This transformation can be captured with only two graph rewrite rules'; 'there is no rule that allows the removal of the last node after a lock, and all additional branches that are created end with a key node that is required to proceed elsewhere. This means that all tasks must be completed in order to finish the level'; 'the size of a level is dictated by the length of the initial mission'; Figure 8 caption confirms the 21-task sample. Deadlock prevention (key behind its own lock) is cited as the rewrite system's advantage. TRAWF translation: gives TRAWF's roguelike generator a difficulty/length dial (mission task count maps to stretch length — plugs into the existing curriculum-ramp stages) and the correct engineering posture: make the RULE SET carry the gating invariant so every seed is valid by construction, rather than generate-and-reject. Caveat preserved from the paper: the guarantee is by-inspection on the mission graph, and the space-mapping step is where violations can still creep in — keep TRAWF's topology test as the belt to this suspender.

**Confidence:** high | **Verification:** 3-0 (x2, merged claims 16+17)
- https://www.pcgworkshop.com/archive/dormans2011design.pdf

### CHUNK-TOPOLOGY — LOCK BEFORE KEY

CHUNK-TOPOLOGY — LOCK BEFORE KEY: players should encounter the LOCK before the KEY, for three player-experience reasons: key-first play degrades into indiscriminate collecting; a known lock makes a disguised key recognizable and lets players form an intention to return; and re-negotiating a previously impassable obstacle produces a felt sense of progress.

**Evidence & TRAWF translation:** Dormans 2011 verbatim, all three reasons: '1) When keys are encountered first players will simply be forced to collect everything... without discrimination... 2) ...it is easier to recognize the key if players know what the lock is... they will actively formulate the intention to return to the lock. 3) When players can negotiate obstacles they were unable to get past earlier, they will experience progress and accomplishment.' The paper notes its own rule 3 (move lock toward goal) 'breaks with' this wisdom — a hedge the claim preserves. TRAWF translation: a presentation-ordering constraint for chunk generation — the player should SEE the sealed gate/blocked channel/dead console before finding the ability, lure, or held-console partner that opens it; in TRAWF's disguised-key world (a Capbage hide, a cadence window, a flora light) reason 2 is the operative one: knowing the lock is what makes a perception-layer read legible as the key. In the channels ascent, each gate glimpsed from below before its solve doubles as reason-3 progress feedback after a wash sweeps you back down past locks you have already opened.

**Confidence:** high | **Verification:** 3-0
- https://www.pcgworkshop.com/archive/dormans2011design.pdf

### RUN-SCALE — THE ESCALATION CLOCK

RUN-SCALE — THE ESCALATION CLOCK: TIME ITSELF IS THE PRESSURE, WHICH BUYS DOWN PER-ROOM DIFFICULTY: In Invisible Inc the alarm rises automatically at the end of EVERY turn (not just on mistakes like kills or spotted bodies), making elapsed time the core pressure mechanism; this explicitly allowed Klei to LOWER the baseline difficulty of each level — 'no starting situation... is particularly difficult to solve on its own' — shifting challenge from immediate per-room threat to cumulative mid/long-term decision pressure.

**Evidence & TRAWF translation:** James Lantz (Klei technical designer on Invisible Inc) verbatim: 'It goes up when you kill a guard and when guards see bodies, but most importantly it also goes up at the end of each turn'; 'it also allowed us to lower the overall difficulty in each level. No starting situation in Invisible is particularly difficult to solve on its own. Instead they work together to challenge the player's decision-making in the mid to long term.' Community wikis confirm the shipped behavior. TRAWF translation: the strongest run-scale template for TRAWF's day/night + ATP/stamina economy AND its degradation-as-difficulty principle — individual chunks can stay gentle (matching degradation-never-tighter-timing) while the always-advancing scheduler clock (day/night, iron accumulation, degradation ticks) supplies the real difficulty; it also prices the information economy (every eavesdrop/overlook read costs clock) and the wash recovery (depth-scaled time cost is automatically a difficulty cost).

**Confidence:** high | **Verification:** 3-0 (x2, merged claims 20+23)
- https://www.gamedeveloper.com/design/game-design-deep-dive-alarm-systems-in-klei-s-i-invisible-inc-i-

### RUN-SCALE — QUANTIZE THE CLOCK INTO FEW, TELEGRAPHED, FIXED-EFFECT THRESHOLDS

RUN-SCALE — QUANTIZE THE CLOCK INTO FEW, TELEGRAPHED, FIXED-EFFECT THRESHOLDS: Klei's first alarm (20-30 fine-grained levels with consequences at intervals) failed for legibility — players couldn't tell when the next threshold would bite, and consequences were unpredictable/random, 'unwelcome in a stealth game about careful planning'; the shipped fix was 6 major levels x 5 no-effect sub-levels, so consequences fire only at legible transitions with fixed, predictable effects (level 2: all firewalls +1; level 3: another patrol enters).

**Evidence & TRAWF translation:** Lantz verbatim: 'Initially, the alarm was a series of 20-30 levels... the UI was unintuitive -- 20 levels of alarm made it unclear when the next alarm level would actually become a problem... the consequences of each alarm level were unpredictable and random'; 'we instead made the alarm 6 levels and gave each level 5 sub-levels that had no effect... at alarm level 2, all the firewalls in the building are raised by one. At alarm level 3, another patrol enters the building.' A rare documented failed-iteration + shipped-fix pair. TRAWF translation: apply directly to the day/night threat ramp and to channels wash pressure — few named thresholds (dusk: +1 roamer per yard; night: detection outer range +X; deep-night: washes quicken) each with ONE fixed, pre-announced effect visible in the HUD, never a continuous or randomized ramp; sub-threshold ticks show progress without firing effects. This is also the planning-game justification: TRAWF is pause-and-direct, so like Invisible Inc it cannot afford illegible escalation.

**Confidence:** high | **Verification:** 3-0 (x2, merged claims 21+22)
- https://www.gamedeveloper.com/design/game-design-deep-dive-alarm-systems-in-klei-s-i-invisible-inc-i-

### CHUNK-TOPOLOGY (TOOLING) — BOSS KEYS NOTATION AS A GATING VOCABULARY

CHUNK-TOPOLOGY (TOOLING) — BOSS KEYS NOTATION AS A GATING VOCABULARY: Mark Brown's Boss Keys dungeon-graph notation encodes gating as typed lock/key node pairs — red diamond/square = small key/locked door, orange = dungeon key item/the obstacles it overcomes, blue = boss key/boss door, lettered green (then purple/yellow/pink) diamond/square = switch/the barrier it removes — a compact, third-party-adopted vocabulary for drawing gated compositions as dependency graphs.

**Evidence & TRAWF translation:** Legend verified verbatim via multiple independent reproductions of the Patreon post (direct fetch blocked, HTTP 403): 'Red diamonds are small keys. Red squares are locked doors... Orange diamonds are for the key item... Blue diamonds are for the boss key... A green diamond with the letter A is some kind of switch, a green square is whatever barrier is removed.' Corroborated by BorisTheBrave's lock-and-key survey and the pfirsich/DungeonGraphs tool, which adopt it as canonical. Vote was unanimous but the source could not be fetched directly, hence medium. TRAWF translation: adopt as the authoring/debug notation for chunk compositions — consumable keys (red) vs persistent character capabilities or learned world-state access (orange) vs the stretch's end-gate (blue) vs held-state switches (green: held-override consoles and dynamic grid blockers, which are switch/barrier pairs exactly); it slots straight onto Dormans' tight-coupling edges and gives the generator's mission graphs a human-readable rendering for level review. Orange does not imply that every gate needs a new cast ability.

**Confidence:** medium | **Verification:** 3-0
- https://www.patreon.com/posts/how-my-boss-key-13801754

## Coverage gaps (honestly unbenchmarked)

No claims survived verification on: Rain World / Jusant ascent-with-fall-cost structures, Spelunky's room-
template grammar, or Unexplored's cyclic generation (their verification votes died on a session limit and the
candidate claims were dropped rather than passed unverified). The wash/sweep-back ascent design therefore
remains unbenchmarked against a shipped game — worth a follow-up pass if we want outside validation for it.

## Combined build-next (research x DESIGN_PRINCIPLES.md register, leverage-ranked)

Where a researched element and a register translation point at the same build, they are merged. "Composes existing"
means every mechanic named already exists in the codebase.

### Tier 1 — small effort, composes existing mechanics
1. **Mutual-overwatch setup recipe** (Mimimi) -> the interior rule for every chunk atom: at least two enemies
   covering EACH OTHER, anchored to a point of interest, ~one screen. Upgrade the next fragment to two sentries in
   mutual overwatch. Serves P6/P8/P13. Composes existing (LOS detection, idle/patrol guards, conceal tiers, lures).
2. **Ability-ablation verifier slot** (register) == **weakness-forced combination** (Mimimi's shipped statement of
   the shadow law): regenerate a section minus one ability -> solver must return BLOCKED or strictly costlier.
   Serves P2/P6/P10.
3. **Stage-gated overlook + POI-visibility scarcity** (register; reinforced by Mimimi's info-as-objective mission):
   the generator emits a vantage node only at low progression stages. Serves P1/P3/P16.
4. **Depth-scaled diegetic reunion cost** (register): physical sloperope/runback duration as monotone
   functions of wash depth. Serves P11/P12/P16.
5. **Quantized day-clock thresholds** (Klei: 20-30 fine alarm levels FAILED legibility; ~6 telegraphed fixed-effect
   thresholds worked): restate TRAWF's day as 5-6 named dusk stages with fixed effects, telegraphed in-world.
   Serves P16/P18; pairs with the register's day-clock term in RunEconomy.
6. **Lock-before-key generator ordering** (Dormans): the gate must be encounterable before its mechanism on every
   generated chunk (The Watched Gap already plays this way; make it an invariant `verify()` checks). Serves P6/P8.

### Tier 2 — medium effort
7. **Guard-type grammar: anchor / timer / filler** (Mimimi): a static anchor who never leaves post even when
   distracted, a patrolling elite whose loop IS the setup's clock, cheap fillers — typed per enemy roster species
   and keyed to counterability (who can remove whom). Serves P5/P9/P13. Mostly composes existing.
8. **Tight/loose coupling edges + key provenance** (Dormans) in the stretch generator: tight = strict order, loose
   = any order; provenance ensures a key cannot leak past its lock. Pairs with the register's monotone-ascent
   verifier + typed chain handshake. Serves P6/P8/P9.
9. **Seen-cells legibility overlay** (Mimimi's legibility-over-realism pillar; the panel's #3): Endo's register
   paints the sentry's actual seen cells vs wall-shadow, derived from the SAME LOS data detection uses. Serves P2/P18.
10. **Decompression zones** (Shadow Gambit): deliberate low-pressure nodes between setups as a generator pacing
    constraint (breathers are authored, not accidental). Serves P16 + run pacing.
11. **Info-objective chunk archetype** (Desperados III New Orleans): N candidate objectives, one real; cheap-but-
    slow clue gathering (spread the party, eavesdrop) vs expensive-but-direct assault — information itself as the
    puzzle with a risk-priced alternative. A NEW archetype for the catalog; serves P3/P10/P17.

### Tier 3 — large / new mechanics (strategic)
12. **Degrading flora read-window with observation provenance** (register #1) — the flagship P1/P2/P3 build.
13. **Live in-engine shadow-path replay of a generated stretch** (register #9) — the P6/P7/P10 proof loop.
14. **Mission-then-space two-phase generation for chunk INTERIORS** (Dormans; validates the existing node-graph ->
    WFC split at stretch scale): generate the chunk's mission graph (gates, mechanisms, nests) before its room
    geometry, so interior topology is solvable by construction. Serves P6/P8/P9.

### Notation to adopt (cheap, immediate)
- **Boss Keys-style typed lock/key graphs** as the debug/ASCII notation for chunk + stretch topology (the existing
  ASCII layers show SPACE; this shows STRUCTURE — which gate depends on which mechanism).
