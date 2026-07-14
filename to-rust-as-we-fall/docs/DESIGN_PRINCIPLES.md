# TRAWF Design Principle Register

Derived from the canonical corpus (GDD v02, CHANNELS_DESIGN, design_archetypes, shadow-solutions,
dlc_roguelike_mode, run_meta_decisions) plus the director's session corrections (2026-07-01), by a
five-slice extraction + synthesis pass. Every principle cites its sources; every translation is marked
exists-today or not. This is a WORKING register: edit it, strike entries, re-rank — it is yours.

## The spine (the one test)

The world is a truthful, deterministic machine that never cheats — all challenge lives in the widening gap between that truth and the party's degrading, composited perception of it, and all meaning lives in care (tending, patience, maintenance, trust) as the only real counter to the decay. The ONE design test every proposed element must pass: "Is this challenge expressed as information or capability withdrawn from the CHARACTERS (never hardness added to the world), and is it still PROVEN — by solver verdict and real-player replay, not topology or narration — that Aster and Peris alone can finish it?" If the world had to get bigger, denser, faster, or random to be hard, or solvability is only asserted, redesign.

## Pillars

1. Perception, information, and learning are the content
2. The world is a truthful, deterministic machine
3. Levels are gated, proven, multi-solution compositions
4. A legible ecology that carries the theme mechanically
5. Time and choice have measured prices

## The register

### P1-degradation-difficulty

**Difficulty rises because the characters degrade — information and capability are withdrawn from the party — never because the levels get harder; escalation reuses the SAME geometry with degradation params or one stacked NEW pressure, and timing windows never shrink.**

- Pillar: Perception, information, and learning are the content
- Sources: GDD §1 (line 182), §2.3.3, §2.3.7, §2.5; CHANNELS_DESIGN §Section-design #4 + Holdfast Escalation ('NO new spouts, NO shorter period'); channels_edits.md Beat 2 (baselines); slices 1.1, 2.6, 3.5
- FORBIDS: Level-side stat inflation (bigger mazes, more enemy HP, denser hazard soup); shorter cadence periods, added spouts, or tighter reaction windows as difficulty; shrinking stamina (deliberately the one stable bar, GDD 2.4.1); escalation that changes geometry instead of parameterizing it.
- DEMANDS: The curve is carried by shrinking information/capability: Peris's read-window (60s→30s→10s→2-3s), fuzzy overlay self-representation, bloom germination delay/failure, marker fuzz, observable wrongness late; stacked pressure = a guard laid over an existing surge (WHEN+WHERE at once); sharp baselines established early so their absence registers later.
- Machine-checkable: Enforceable: for the same section id across stages, assert the cadence period list is IDENTICAL and only degradation params differ (not built); extend --test-curriculum-ramp so late-stage escalation is carried by degradation params, not depth/size. Today's ramp test partially contradicts this — flagged in tensions.
- Translations:
  - [BUILD] (new-mechanic) Peris flora-network read-window as a single milestone-keyed duration (GDD 2.3.3/2.3.5) — game_state.gd has get_flora_network() but no read-window/degradation number
  - [BUILD] (generator-constraint) Degradation params (germination delay/failure rate, marker fuzz radius) as generator knobs applied to an UNCHANGED section spec
  - [EXISTS] (mechanic-composition) Guard-over-surge stacked-pressure composition (concealment tiers + analytic cadence) — both halves exist (CONCEAL tiers, wash_relay cadence); the deliberate stacked section is authored, not yet built
  - [EXISTS] (test-invariant) --test-curriculum-ramp escalation across stages 1..6 — currently ALSO grows depth/size with stage — acceptable early ramp, contradicts the long arc; see tensions
  - [BUILD] (content-pattern) Four telegraph channels for sensor decay in order: dialogue → fuzzy cones → party observation → observable wrongness (GDD 2.3.7)

### P2-composite-perception

**Asymmetric perception IS the gameplay: each character is a distinct cognitive REGISTER (not a recolor), the player's view is the composite, overlay visibility is decoupled from selection and keyed to consciousness (lose the hands, keep the eyes) — and a legitimate section composes at least TWO registers, one answering WHERE and the other WHEN, each ability load-bearing state, never flavor.**

- Pillar: Perception, information, and learning are the content
- Sources: GDD §2.2/2.2.1/2.2.2 (lines 210, 328), §2.4.3; CHANNELS_DESIGN §Section-design #2 + PERCEPTION_LOCK template field; slices 1.2, 2.6, 3.3
- FORBIDS: Any single layer that shows everything; tying an overlay to being the active character; killing a conscious character's overlay when merely out of play; one-button sections clearable by a single register; ability effects that are toasts; a section solvable at identical difficulty with an ability reverted.
- DEMANDS: Six distinct visual registers (Aster cyan data, Peris warm flora/memory, Endo survival, Myke roads, Oli power, Tyreg patrols) that stack without interfering; per-level content legible only through specific layers; a PERCEPTION_LOCK per section naming what each single register cannot see; swept-but-conscious members keep contributing.
- Machine-checkable: Enforceable via an ABLATION slot: regenerate a section, remove one ability from the stretch_capabilities loadout, assert the solver returns BLOCKED or strictly costlier (natural extension of stretch_capabilities.gd/stretch_solution_solver.gd, not built); plus PERCEPTION_LOCK as a validated spec field. TRACE truthfulness already enforced.
- Translations:
  - [EXISTS] (mechanic-composition) TRACE/BLOOM/BRACE: each character extracts DIFFERENT info from the same section (wash_relay_chunk.gd; --test-wash-relay-abilities) — the embryo of layer-asymmetry
  - [EXISTS] (test-invariant) --test-wash-relay-trace-cadence: TRACE names the REAL scheduled beat, not a guess
  - [BUILD] (new-mechanic) Six toggleable overlays decoupled from selection, availability keyed to consciousness — per-chunk aster/peris overlays exist; the composite six-layer toggle system does not
  - [BUILD] (generator-constraint) PERCEPTION_LOCK as a required generator field {where_register, when_register, hidden_from_each}
  - [BUILD] (generator-constraint) Generator constraint: ≥1 hazard/resource per node readable only via a specific register — stretch_poi_distribution.gd places POIs but doesn't tag them by layer

### P3-information-scarcity

**Information is content and gets scarcer: the whole-stretch overlook is a diegetic gift in story mode and the first few roguelike stretches ONLY; foreknowledge (layout, plant/enemy positions, cadence values) is budgeted like ATP — granted freely early to teach, then earned via abilities, sparse vantages, recruits, or paid recon; perception has PROVENANCE (pins exist because a character actually observed them, so they can later fuzz and drop).**

- Pillar: Perception, information, and learning are the content
- Sources: director, session 2026-07-01 (cited in ALL five slices); CHANNELS_DESIGN §Spatial structure Entry (bridge overlook is why Peris knows the plants); dlc_roguelike_mode.md info-kit characters (Pendy/Swan/Vasca); GDD §2.3.3-2.3.5; slices 1.1, 2.6, 3.11, 5.6
- FORBIDS: Free minimap-grade knowledge of a generated stretch at every depth; an overlook element injected unconditionally; overlays that render world TRUTH regardless of what a character observed; info abilities that duplicate what the level already shows free.
- DEMANDS: Bridge-top entry vantage early (the diegetic justification for Peris's plant knowledge); a stage/depth threshold beyond which no full-layout view is emitted; flora pins populated from observation events, not world state; recruiting as buying information (CSF Flow / Peripheral Map / Flow Sense).
- Machine-checkable: Enforceable: assert high-stage/depth specs contain NO full-layout vantage node and player-facing preview data omits undiscovered POI positions (not built; fits the existing stage-keyed curriculum test pattern).
- Translations:
  - [BUILD] (generator-constraint) Stage-gated overlook: vantage node emitted only at progression_stage ≤ N (stretch_generator)
  - [BUILD] (level-element) Bridge entry vantage over the spiral (explicit 🔜 in CHANNELS_DESIGN; SpiralCoordMap exists to overlook)
  - [BUILD] (new-mechanic) Peris flora-pin overlay populated from an observation event with decay hooks
  - [EXISTS] (generator-constraint) Progression-scaled ambient POI density (_apply_poi_density, solver-neutral) — the existing hook for scaling what a stretch shows
  - [BUILD] (new-mechanic) DLC info-kits as depth currency delivered by the recruit branch pattern — the recruit pattern that would deliver them exists (run_branch_decisions.gd)

### P4-no-memory-gate

**Degradable memory is depth, never a gate: the critical path routes only through stable or recoverable information; the attentive player earns optional richness (shadow paths, transcript review, better endings) while the casual player still finishes — and no design may require player note-taking.**

- Pillar: Perception, information, and learning are the content
- Sources: GDD §2.3.9 (line 421: 'explicitly not designed to require player note-taking'), §1 (line 190); slice 1.10
- FORBIDS: Main-story progression gated on information Peris's degradation can erase or the player must write down; hard-blocking the inattentive player (they progress, but experience the world as emptier); cognitive compensation where mechanical compensation belongs.
- DEMANDS: Early flora tending as strategic investment in late-game sensor durability (relationship-based decay hits weakest bonds first); every critical-path read re-acquirable in-world at a TIME price; optional depth stays optional.
- Machine-checkable: Enforceable once degradable reads exist as a solver resource: assert every generated stretch's critical/pair path consumes zero of them (host: stretch_solution_solver.gd). Until then authored-only.
- Translations:
  - [BUILD] (new-mechanic) Flora tending as spatial/temporal investment; decay hits briefly-met plants first (GDD 2.3.3) — flora_garden_chunk + FloraLight are the substrate
  - [EXISTS] (mechanic-composition) Aster's diegetic dialogue transcript (--test-dialogue-transcript-cap, TRANSCRIPT_MAX=40) — cap may need rethinking if it is meant as a full reviewable archive
  - [BUILD] (test-invariant) Solver constraint: the shadow/pair solution consumes ZERO degradable-layer reads — stretch_solution_solver.gd is the natural host once degradable reads exist as a resource
  - [BUILD] (level-element) Forget-me-nots as pure-relational flora, first to go under degradation (GDD 2.3.2/2.3.8)

### P5-deterministic-emergent

**The world is emergent-deterministic: every gameplay outcome rides the EventScheduler tick, hazard cadences are DATA with analytically computed next-onsets (never per-frame coincidence sampling), enemy behavior is rule-legible and reproducible, and outcomes are identical at 1x and 10x — the only uncertainty is epistemic: the gap between the player's decaying reads and where things actually are now.**

- Pillar: The world is a truthful, deterministic machine
- Sources: GDD §2.3.6 ('The variance is not random... emergent-deterministic'), §2.7 (line 533); CHANNELS_DESIGN CADENCE field + Invariants; channels_hide_encounter_spec 'No hidden randomness'; slices 1.5, 2.9, 3.8
- FORBIDS: randf()/wall-clock in gameplay logic; RNG spawns, aggro, or decisions; per-frame-sampled outcomes that change under fast-forward; 'random encounter' spawning as a difficulty knob; swarm behavior irreproducible under test.
- DEMANDS: Scheduler as the single time authority; detection as a scheduled analytic prediction (first-contact tick solved, recomputed on state change); timing-puzzle outcomes precomputed at commitment (the swarm-surge lesson); felt randomness derived only from stale reads plus enemy motion between read and act.
- Machine-checkable: ENFORCED today (the FF suite + roam/combat invariance). Cheap addition: a lint in the --test-sequence-input-discipline style greping gameplay scripts for randf(/randi(/Time.get_ticks outside @rendering_only.
- Translations:
  - [EXISTS] (mechanic-composition) C++ min-heap EventScheduler + _recompute_all_detection_predictions analytic detection
  - [EXISTS] (mechanic-composition) Deterministic roam: tick-locked heading hashed from char_id + sequence (--test-enemy-roaming)
  - [EXISTS] (test-invariant) FF-invariance suite: --test-fast-forward-invariance, --test-puzzle-fast-forward-invariance, --test-combat-cycle FF check
  - [BUILD] (new-mechanic) Stale-read gameplay: flora-network reads snapshot enemy positions with time-limited freshness; enemies keep moving (Duskers mode, GDD 2.3.6) — determinism substrate exists; the read-snapshot-with-freshness layer does not

### P6-proven-mechanical-truth

**Mechanical truth beats designer intent and solvability is a PROVEN verdict: topology gating is never passed off as solvable; every mechanic backing a puzzle must be real, taught, and engine-tested (an honest buildability ledger); every generated puzzle emits its SOLUTION as data, regenerates from its seed, and is replayed end-to-end as a real player; every failure mode maps to one specific named player mistake, and tuning numbers are derived, not guessed.**

- Pillar: The world is a truthful, deterministic machine
- Sources: GDD §2.6.2; director 2026-07-01 (cited in all five slices; commit ef797e6 'topology-gating != solvable'); channels_hide_encounter_spec math/failure-modes/harness list; design_archetypes step 7; ChunkGenerator code-of-record doc; run_session.gd seed discipline; slices 1.4, 3.9, 4.5, 4.6, 5.8
- FORBIDS: Shipping a puzzle whose 'solution' exists only as topology or narration; claiming an archetype buildable without a tested chunk; enemy cheating (wall-hack detection, teleport strikes); coin-flip failure modes; multi-solution declared because approaches were authored; success flags not backed by a solver or replay; randf/wall-clock in generation or branch selection.
- DEMANDS: verify() per chunk (locked_blocks/solved_connects/ordering_ok); mechanic() ledger naming the real backing system or declaring NOT BUILDABLE YET; solver error severities (shadow_broken, multi_solution_missing, no_puzzle_nodes for hard/setpiece); _solution_script consumed by stretch_replay_builder + the playtest loop; deterministic seed hashing at every level; derived variables tables (d_run_max = v_run × S_max / D_run).
- Machine-checkable: Largely ENFORCED: verify(), solver severities, replay artifact, --test-run-session-e2e, --test-wash-relay-playthrough. Open verifier slots: in-engine replay of generated stretches, shadow-path replay, per-failure-mode triggers.
- Translations:
  - [EXISTS] (test-invariant) ChunkGenerator.verify(): flood-fill with the game's own movement rule proves start→end blocked while any gate is shut, mechanisms nested in order (chunk_generator.gd:220-281)
  - [EXISTS] (generator-constraint) ChunkGenerator.mechanic() honesty ledger (holdfast/split/distract buildable with cited tests; redirect/vinebridge NOT BUILDABLE YET)
  - [EXISTS] (test-invariant) Solution-as-data pipeline: stretch_solution_solver + stretch_replay_builder + stretch_generation_playtest_loop, regenerate-from-seed — plus --test-wash-relay-playthrough proving the gauntlet BEATABLE, not just present
  - [BUILD] (test-invariant) Live in-engine replay of a GENERATED stretch (real detection, real washes, real dwell), including the shadow path — the missing rung: the playtest loop walks the golden spine on the solver graph, not each divergent path in the live scene
  - [BUILD] (test-invariant) Per-failure-mode tests: each of the 4 named mistakes (slow retreat/slow activation/early hide/slow exit) provably triggers its failure and only it

### P7-one-simulation

**There is ONE simulation: every mode — story, channels, roguelike, preview, CLI, headless test — drives the same GameState/EventScheduler/detection/economy systems; a generated run strips only narrative scaffolding, never mechanics; and a scene or spec is 'done' only when a data-layer playthrough completes its WHOLE lifecycle (UI state, scheduling, transitions) — only rendering may be skipped.**

- Pillar: The world is a truthful, deterministic machine
- Sources: dlc_roguelike_mode.md 'Core concept' + 'Systems inherited' (lines 9-11, 164-181); run_session.gd doc ('single authority for run logic'); project law (CLAUDE.md data-layer playability); slice 5.1
- FORBIDS: Roguelike-only stub mechanics; faked enemy/flora behavior in generated levels; a run loop entangled with scene/UI code; bespoke anatomy per mode; playthroughs that fake teardown or stop at requested_scene_change.
- DEMANDS: RunSession as pure data (generate → branch → choose → next) with the fragment loader a thin presenter; generated stretches load through the same chunk-host interface as story scenes; headless and rendered behave identically; real-input coverage proves gates reachable without force-fire.
- Machine-checkable: ENFORCED by the suite's architecture (playthrough gates, run-session e2e, real-input tests). Open slot: validate at generation that no shipped-tier spec node resolves to a 'placeholder' support-level palette entry.
- Translations:
  - [EXISTS] (mechanic-composition) RunSession headless pure-data run loop (scripts/generation/run_session.gd)
  - [EXISTS] (content-pattern) generated_stretch chunk via the shared chunk-host interface (tutorial_sequence preview_* methods)
  - [EXISTS] (test-invariant) --test-run-session-e2e + the per-scene data-layer playthrough gates + real-input playthroughs
  - [BUILD] (generator-constraint) Enforced ledger: every node type in a roguelike spec maps to a real engine object class (Flure, Capbage, Channel, consoles, enemies) — commit ef797e6 started the honesty pass; no enforced mapping check yet — palette support_level is the hook

### P8-gated-ascent

**A level is a gated puzzle composition, never free-walk space: the chunk is the atom (start, end, gates in solve order, a PROVEN cannot-walk-through invariant); a channels stretch is an ASCENT against the flow bookended by two shelters, a wash sweeps you DOWN, each chunk carries its own connect-back device, and each section's solve helps the others advance.**

- Pillar: Levels are gated, proven, multi-solution compositions
- Sources: director 2026-07-01 (gated composition; stairs/links everywhere = design failure; chunk atom — commits 98aeeaa, aea8251); CHANNELS_DESIGN §Spatial structure + §Failure & recovery; GDD §2.6; level_design_canon memory; slices 1.7, 2.8, 3.1, 4.6
- FORBIDS: Stairs/links everywhere connecting everything; a generated stretch walkable end-to-end without solving; descending or flat layouts where the wash has no directional cost; failure that merely respawns in place; a chunk without a verify() proof.
- DEMANDS: verify() per chunk; two-shelter bookends (start bottom, end top under the entry bridge); connect-back (sloperope/terminal) per chunk with recovery rejoining at the CHUNK, not the stretch start; monotone ascent at stretch level; meta-template macro shapes (spiral/rect/polygon hubs + spokes) reading hub-and-spoke.
- Machine-checkable: ENFORCED per chunk today (verify()). Open slot: lift to stretch level — monotone ascent + per-chunk checkpoint constraint in stretch_generator.gd, asserted in the generation tests.
- Translations:
  - [EXISTS] (test-invariant) ChunkGenerator.verify() {locked_blocks, solved_connects, ordering_ok}
  - [EXISTS] (mechanic-composition) wash_relay sweep + Terminal/Sloperope connect-back recovery
  - [BUILD] (level-element) Multi-chunk stretch with per-chunk connect-back — explicit 🔜 in CHANNELS_DESIGN
  - [BUILD] (generator-constraint) Monotone-ascent stretch-level verifier: each chunk's exit strictly deeper/higher than its entry, wash target = current chunk's start, verify() run per chunk in the emitted stretch
  - [EXISTS] (generator-constraint) Meta-template macro shapes (SpiralCoordMap / hub_shape_coord_map / hub_meta_template / stretch_branch_weaver) — the warp armature exists but connectivity is currently free-walk/descending — the gated-ASCENT rework is THE open task (spiral_meta_template_system memory)

### P9-archetype-vocabulary

**All content composes the eleven archetypes — every generated puzzle names its macro-archetype, variants, nests, and chains; a nest is valid only if the inner puzzle fully executes inside a designed host slot (a puzzle to reach the puzzle), a chain is valid only if each link's typed OUTPUT is exactly the next link's SETUP; and expectation subversion (Archetype 9) is hand-authored and one-off — it never enters a procedural pool.**

- Pillar: Levels are gated, proven, multi-solution compositions
- Sources: design_archetypes.md Purpose/Construction (lines 5-16, 200-218), named nest points and chains, Archetype 9 (lines 153-166: 'each subversion needs rarity to land'); slices 4.1, 4.2, 4.8
- FORBIDS: Bespoke one-off puzzles with no archetype decomposition; decorative nesting the player can bypass; chains where a link produces nothing the next consumes; generating subversion beats from seeds; reusing a subversion (a second Psyknapse-style trap teaches distrust of the whole grammar); subverting a convention the game hasn't established.
- DEMANDS: The validated catalog as a data dependency of generation; composition normalization (chain_index, host_id/parent_ref/depth, catalog validation per entry); nesting provable topologically; an output→consumes handshake typed at generation time; archetype-9 excluded from the generator's pool.
- Machine-checkable: Partially ENFORCED (catalog validate, _validate_composition_entry, ordering_ok). Open slots: typed handshake check; never-generate-archetype-9 assert.
- Translations:
  - [EXISTS] (generator-constraint) StretchArchetypeCatalog.validate() requiring archetypes 1-11 in data/generation/archetype_catalog.json
  - [EXISTS] (generator-constraint) Composition normalization + verify() ordering_ok (the nest property as a hard topological invariant)
  - [BUILD] (generator-constraint) Typed produced-state chaining: links declare OUTPUTS (revealed plant, opened gate, cleared path) and CONSUMES, checked at generation — the doc's four canonical chains are all output-typed; the generator only enforces order + membership
  - [BUILD] (generator-constraint) Archetype-9 pool exclusion + a test asserting no generated spec ever contains a subversion node
  - [BUILD] (level-element) The Psyknapse trap: a hand-authored fake class-gated terminal trading on the established outline/highlight grammar — its prerequisite — uniform click-gated interactable grammar — is built and enforced (--test-chunk-interactable-outlines)

### P10-shadow-law

**Every major puzzle is ONE geometry with TWO solves: a Presented specialist path and a designed Aster+Peris SHADOW path through the SAME hazard — the pair must finish unconditionally at every stage and under any roster (the permadeath floor); the shadow is harder (a visible, stage-scaled cost premium), never surfaced first-play, rewarded with agency not efficiency, and taught only diegetically (NPC demos, terminal logs, shelter lines).**

- Pillar: Levels are gated, proven, multi-solution compositions
- Sources: GDD §2.6/2.6.2 (line 475: 'redesigned until it can')/2.6.3/2.6.4/2.6.5; design_principles_shadow_solutions.md Commitments + Anti-principles; CHANNELS_DESIGN §Section-design #1 + Holdfast worked example; dlc_roguelike_mode.md permadeath (line 9); slices 1.3, 3.2, 4.3, 4.4, 5.5
- FORBIDS: Puzzles hard-requiring a specialist; a shadow that is a relabel of the same button or bolted-on separate geometry; UI/prompts/dialogue/environment hinting the shadow; a shadow cheaper than the presented path; shadows relying on undocumented exploits; generation whose only solution needs a character the player might have lost.
- DEMANDS: Generation-time dual-path proof (shadow_broken and bare_pair_unsolvable as severity-ERROR); the pair pays COMBINATION_PREMIUM at choice nodes while staying solvable; first-play path stays in-stage while the shadow may use future techniques (enforce_stage asymmetry); roster-aware regeneration with the bare-pair floor; shadow-teaching content authored separately from the puzzle.
- Machine-checkable: ENFORCED at generation (solver severities + ramp monotonicity + RunSession.current_is_playable bare-pair floor). Open: shadow-path in-engine replay; 'never surfaced' is authored-only — review UI/dialogue for hints, keep completion logging invisible.
- Translations:
  - [EXISTS] (generator-constraint) stretch_solution_solver.gd dual loadouts: shadow_broken / bare_pair_unsolvable errors — 'the pair must be able to finish unconditionally'
  - [EXISTS] (test-invariant) Combination-pressure model (PREMIUM_BASE + PER_STAGE vs SPOTLIGHT_RELIEF) + --test-curriculum-ramp: shadow pressure rises strictly, pair stays solvable
  - [BUILD] (mechanic-composition) Mother Flure Scarpet-drag shadow (drag gear over a pre-planted Scarpet bed instead of Endo carrying, GDD 2.6.4) — mother_flure_chunk + Flure/Capbage exist; Scarpet and the carry/drag state do not
  - [BUILD] (content-pattern) Marco's Scarpet-drag NPC demo, construction-era terminal logs, shelter-conversation drops — marco_drag_scene.md 'to be drafted'; no such beats in built scenes
  - [BUILD] (new-mechanic) Roster SHRINK on permadeath stripping that character's overlay + ability keys (RunSession today only grows)

### P11-fail-forward

**Failure costs exactly one section at a chosen, depth-scaled, diegetic price: a wash sweeps the member back (mobile at the previous gap, or stranded-but-recoverable at the start shelter), recovery is a CHOSEN time investment (Terminal fast/priced, Sloperope slow/cheap) scaling with how deep you fell, the party may defer it, all-washed means redo the chunk — and no reachable state soft-locks.**

- Pillar: Levels are gated, proven, multi-solution compositions
- Sources: CHANNELS_DESIGN §Failure & recovery (lines 75-91) + §Section-design #6; channels_hide_encounter_spec 'Failure is recoverable in spirit' (line 155) + soft-lock harness demand (line 166); director 2026-07-01 (depth-scaled diegetic cost); slices 1.7, 3.7
- FORBIDS: Failure that costs the whole run OR nothing; instant free respawn at the party; a downed member silently teleporting back; flat recovery cost regardless of depth; unrecoverable strands.
- DEMANDS: Sweep to the previous gap / start shelter; a real recover-now vs leave-until-chunk-end choice; BRACE refunds re-cross stamina; recovery time as a place where the day-clock bites; per-chunk (not per-stretch) checkpointing.
- Machine-checkable: Partially ENFORCED (--test-wash-relay-checkpoint). Open slots: soft-lock absence sweep over reachable states; monotone depth→cost assertion.
- Translations:
  - [EXISTS] (mechanic-composition) wash_relay _washed registry + Terminal telephone-up + Sloperope deploy-then-climb + BRACE refund
  - [EXISTS] (test-invariant) --test-wash-relay-checkpoint: a wash loses ONE section, counts one sweep, leaves the member MOBILE
  - [BUILD] (generator-constraint) Depth-scaled recovery cost: Terminal ATP/time price and Sloperope climb duration as functions of fall depth — devices exist; cost is flat — director ties this to 'runs too easy vs the day/night cycle'
  - [BUILD] (test-invariant) Soft-lock absence sweep: from every reachable state (any washed subset, any lure/override state) the solver reaches the exit or the redo path — demanded verbatim by the hide-encounter spec harness list

### P12-held-commitment

**Setup beats reflex and commitment beats latches: care is infrastructural (pre-resting, positioning, luring, pause-planning decide success, never twitch); advance-helpers are HELD stations with inheritable roles — stand and the flow calms, vacate and it resumes, a co-located threat targets the HOLDER, any surviving member can take the station — and at least one required distance sits beyond the relevant full-resource budget so reflex cannot substitute for setup.**

- Pillar: Levels are gated, proven, multi-solution compositions
- Sources: channels_hide_encounter_spec §Design principles ('Care is infrastructural, not reactive', lines 150-154); CHANNELS_DESIGN §Section-design #5 + §three-character co-op + ADVANCE_HELPER/ROLE_INHERITANCE fields; channels_edits.md hold-on-interactable ('rhythm-reading rather than reaction-timing'); slices 3.6, 3.10
- FORBIDS: Permanent _override_locked latches; advance-helpers that fire once and stay solved; twitch-winnable encounters; directly fightable swarms (you REDIRECT siderophores, never DPS them); hold windows left as dead time instead of hosting character beats; losing a member reducing to a retry instead of a re-plan.
- DEMANDS: plate/double_plate/override disable only WHILE occupied; ≥1 held-helper section per chunk drawn from {held-override, held-plate, double-plate, timed-window} — never a latch type; guard placement on REAL mechanics (baiting requires dodge enabled + standing on the charge line); stamina budgets that reward arriving rested (the retreat exceeds the full-stamina run budget by design).
- Machine-checkable: Partially ENFORCED (playthrough proves holding; lure relay tested). Open slots: helper-type field validation (never latch), holder-wash inheritance test, the setup inequality asserted per generated encounter.
- Translations:
  - [EXISTS] (mechanic-composition) wash_relay held controls — 'no permanent latch (principle #5)' (wash_relay_chunk.gd:956-958; --test-wash-relay-playthrough proves the plate is solved by HOLDING)
  - [BUILD] (level-element) Guard-threatens-the-holder placement (patrol/charge targeting the console position) — enemy FSM + charge exist; the deliberate holder-threat composition is unbuilt
  - [BUILD] (test-invariant) Test: washing the current holder mid-hold resumes the hazard AND a surviving member can inherit the station
  - [BUILD] (generator-constraint) Setup-over-reflex inequality as a generation assert (e.g. L > d_run_max, derived from the variables table)
  - [EXISTS] (mechanic-composition) Flure lure + wash-drown: redirect-into-hazard as the only way to clear a blocking swarm (--test-lure-relay)

### P13-ecology-of-regulators

**Every enemy is a regulator doing its old job in a context where the job no longer makes sense, inside an ecosystem that fights itself: each pursues a world resource (iron, metabolic signal, neural activity, tags) on ONE perception channel with a legible non-combat counter, never detects through walls, and ships with three mandatory components — universal FSM behavior, deployment sub-archetypes per biome, and counterplay verified against the live mechanics — so the player routes THROUGH enemy relationships, and combat is rarely the best move.**

- Pillar: A legible ecology that carries the theme mechanically
- Sources: GDD §7 intro + §7.2-7.14 ('every encounter is multilateral') + §2.7 (line 537) + §1.1 (line 228: maintenance, not combat); design_archetypes.md enemy framework + Techos worked example (lines 241-303); director 2026-07-01 (no wall-hacks; real bait mechanics); slices 1.6, 2.1, 2.2, 4.7
- FORBIDS: A zoo of isolated stat-check encounters; enemies whose only goal is to block/aggro the player; omniscient or through-wall detection; a same-for-everyone detection radius; a threat whose only answer is damage; counterplay by designer fiat; encounters whose only exit is killing everything; identical placement across biomes; combat-power progression as the reward spine.
- DEMANDS: Resource-seeking home modes (roam-to-iron, converge-on-metabolic-spike); an inter-enemy predation/competition matrix as routable content (Naturalizer clears a Neutro, trapped locusts cannibalize, Tangler into a Candid zone); channel-keyed detection (LOS/scent/metabolic/neural/tag) each with a channel-appropriate counter; distribution readable as corridor history; 4-8 ways-to-deal per deployment with archetype refs.
- Machine-checkable: Counterplay stack ENFORCED today. Open: per-matrix-edge tests as edges are built (analytic, tick-driven); palette schema validation for deployment contexts; 'no wall-hack' already guarded (--test-detection-vertical-band + LOS gate).
- Translations:
  - [EXISTS] (mechanic-composition) enemy.gd universal FSM (idle/roam/patrol/alert/pursuit/windup/charge/impact/recover/search/return), scheduler-driven, disengage guards (--test-enemy-pursuit-timeout, --test-enemy-roaming)
  - [EXISTS] (test-invariant) Mechanical-truth counterplay stack: LOS-blocked predictive detection + DETECTION_VERTICAL_BAND + CONCEAL tiers + lure distraction + dodge-at-impact (--test-two-tier-detection, --test-hidden-detection, --test-lure-relay, --test-dodge-combat-timing)
  - [BUILD] (new-mechanic) Inter-enemy interaction matrix (13 species; enemy-on-enemy resolution) — _resolve_strike is enemy→party only today; every matrix edge must be scheduler-analytic or FF invariance breaks
  - [BUILD] (generator-constraint) Deployment sub-archetype schema in content_palette.json (per-enemy, per-biome: hiding_spots, cover, affordances, ways_to_deal)
  - [BUILD] (new-mechanic) Seefern reveal layer exposing invisible enemies (Nosoma/Redactor outlines) within a glow radius
  - [BUILD] (content-pattern) Distribution-as-history dressing (dead Spikers where Tanglers fed, Neutro corpses under Naturalizers) — use the CANONICAL renamed roster — Sapscraps/Aembers/Flares/Redactors per fauna_roster.md

### P14-flora-one-verb

**Every gameplay flora is load-bearing with exactly ONE distinct verb, hides are tiered by commitment and cost — loosest (decoy that redirects attention while you keep moving), medium (scent-mask idle enemies route around and committed pursuers lose over time), tight (full break that surrenders your actions: lose-the-hands-keep-the-eyes) — and tended flora join a network that becomes Peris's externalized map, so early care is late-game navigational capital.**

- Pillar: A legible ecology that carries the theme mechanically
- Sources: GDD §8.1 ('earn its place through load-bearing mechanics') + §8.2 network + §8.3 hiding-tier mapping + §8.8 Flure + §8.9 Capbage + §2.3.3/2.3.5; flora_taxonomy.md hiding-tier mapping + Capbage; slices 2.3, 2.4
- FORBIDS: Decorative-only functional flora; two flora sharing a verb; a one-button binary hide; a hide with no downside; a tight hide you can act from; medium cover that instantly stops a committed pursuer; a network that gives nothing for tending it.
- DEMANDS: One verb per species (light/reveal, decoy, scent-mask, stun, tight-hide, repellent, traversal); hide-rest as survive-not-recover (no ATP cost, no HP restore, stacked tiredness debuff); the tight hide openable only by the plant; zone flora density = how well-mapped the zone stays late; tending upgrades.
- Machine-checkable: Partially enforceable: verb UNIQUENESS as a palette-data validation (one verb per species, no duplicates); per-object tier behavior tests on the CONCEAL pattern (--test-two-tier-detection is the template). Network capital and hide-rest costs are authored + future solver resources.
- Translations:
  - [EXISTS] (level-element) One-verb objects shipped: Flure (iron decoy), Capbage (tight hide, CONCEAL_FULL), FloraLight (persistent light) — flure.gd / capbage.gd / flora_light.gd + flora_species.gd substrate
  - [BUILD] (new-mechanic) Scarpet medium-tier scent-mask ground cover — CONCEAL_MEDIUM exists to host it; concealment code already name-checks scarpet
  - [BUILD] (new-mechanic) Hushbloom stun-burst + Gasafoetida repellent pod (the GEAR_POOL flora already referenced by the gear branch pattern)
  - [BUILD] (mechanic-composition) Climbvine/Sloperope traversal flora mapped onto grid inter-level links — add_inter_level_link substrate exists; no flora object places links
  - [BUILD] (new-mechanic) Tended-network degrading read-window surfacing resources/enemies through any node — the same element P1/P3/P5 converge on
  - [BUILD] (generator-constraint) Generator constraint: zone flora density scales legibility (tended zones stay mapped late; Dead Zones don't)

### P15-canon-and-meaning

**Every element connects to canon and carries the theme MECHANICALLY: variants fit the area's actual flora/enemy palette (a validated constraint, not a suggestion); each major reward dramatizes ONE relational virtue — the correct answer is care, patience, or trust, never force, and the meaning is never named in-game; combination systems are legible chemistry the player can predict after learning ingredient properties, never an opaque recipe lookup.**

- Pillar: A legible ecology that carries the theme mechanically
- Sources: design_archetypes.md steps 6-8 + 'Connecting to canonical worldbuilding' (lines 314-362); GDD §10.4 per-component archetypes + §10.6 (cure as encoded relationship); dlc_roguelike_mode.md combination principles (lines 80-84); project Critical Rule 'consult the canonical docs' (the Capbage failure); slices 2.7, 4.9, 5.9
- FORBIDS: Placing flora/enemies/structures a biome doesn't field; inventing names or roles not in the GDD/taxonomies; content that supports the thematic spine in no way; a cure component that is a combat fetch; a puzzle whose intended answer is violence; a component that lectures its meaning; hand-authored recipe tables with arbitrary unrelated outcomes.
- DEMANDS: Generation draws only from the validated, area-filtered palette with honest support levels; each big reward embodies a distinct dimension (spatial/historical/interpersonal/mnemonic) via a relational act; ingredients carry property tags resolved by an interaction FUNCTION; rare combos as memorable outliers; a canon manifest per spec for audit.
- Machine-checkable: Palette membership + support levels ENFORCED at generation. Chemistry totality is a clean future test once the system exists. The relational-virtue reading is authored-only — auditable via the canon manifest, never auto-verifiable.
- Translations:
  - [EXISTS] (generator-constraint) content_palette.json + StretchArchetypeCatalog support levels + _build_nodes area filtering
  - [BUILD] (new-mechanic) Cure-component puzzle archetypes: plan-and-relinquish (trust), dry-run/wet-run maze (memorize-then-blind), carry-under-fire with a failing reader, temporal-overlay cascade — wash_relay's timed-current + wash-back is adjacent to dry/wet-run; the rest unbuilt
  - [BUILD] (new-mechanic) Ingredient-property interaction system for Marco's kit (categories + flora properties resolved by a function, Borrowed Vocabulary as a pure UI skin over the stable HUD contract)
  - [BUILD] (test-invariant) Chemistry-totality test: every (categoryA, categoryB) pair resolves; same-property pairs yield the same effect family
  - [BUILD] (generator-constraint) Per-spec canon manifest (cure component, GDD area, spine connection) emitted beside the solution script

### P16-clock-budget

**The day is a finite forage-then-shelter budget and the four bars CASCADE rather than stack: ATP is the night gate spent only at shelter, stamina the stable moment budget (never shrinks), HP the encounter cost, sleep-deprivation a one-directional multi-day ratchet cleared only by full rest — and run length, content density, and recovery time are tuned so a tier-N stretch finishes near-but-NOT-comfortably before dusk.**

- Pillar: Time and choice have measured prices
- Sources: GDD §2.4.1-2.4.5 ('cascade rather than stack'; 'the ratchet is one-directional') + §2.5 (12-unpaused-minute day); director 2026-07-01 ('runs too easy vs the day/night cycle' — cited in three slices); run_meta_decisions.md shelter/ATP-cadence candidates; slices 1.8, 2.5, 5.7
- FORBIDS: Run lengths/density that let the player ignore dusk; ATP draining during exploration (it drains only at rest); shrinking stamina over the campaign; HP-drain-from-low-ATP (explicitly de-canonized, §2.4.4); free night skips; shelters so dense the night is never faced in the open; a safe branch that is ALSO fast.
- DEMANDS: Discrete countable ATP; rest at shelter as the only night skip; skipped/partial rest → next-day deprivation debuffs; traversal time priced as exposure; a day/night term in the economy model; risky-route-out-values-safe for clean play and vice versa for sloppy play.
- Machine-checkable: Enforceable in the headless playtest loop: nominal-pace completion time vs remaining daylight must land in a target band per tier (host exists; assertion not built). Bar mechanics partially enforced via existing state tests.
- Translations:
  - [EXISTS] (mechanic-composition) run_economy.gd (atp_reward, SHELTER_RESTORE=8.0, TRAVERSAL_EXPOSURE, exposure priced in ATP-equivalents)
  - [EXISTS] (mechanic-composition) Dusk Run chunk + _rest_deprived derived state + REST_DEPRIVED_STAMINA_FACTOR (sleep before rollover or wake DEPRIVED) — also Lysate endocytosis as the ATP refill verb (item_data.gd)
  - [BUILD] (generator-constraint) Day/night term in expected_net (projected dusk overrun from stretch length × cadence vs remaining daylight), generator budgets validated against it
  - [BUILD] (test-invariant) Dusk-margin playtest assertion: clean player reaches shelter with margin, doom-scroller wakes deprived — measured by the headless loop, not asserted by hand — stretch_generation_playtest_loop.gd exists to host it; the 'too easy vs the clock' regression guard

### P17-crossover-decisions

**A branch is only a decision if the winner flips with play quality — the costly path out-values the safe one for CLEAN play and the safe one wins for SLOPPY play, a measured crossover; meta-decisions are authored as coherent choices over knobs that already exist (tier, atp_reward, pressure, roster, budget — never new machinery), and every decision ships with its constraint AND a tuning target the headless loop measures before it counts as decided.**

- Pillar: Time and choice have measured prices
- Sources: run_meta_decisions.md lines 7, 11, 21, 23 ('If the harder branch pays too little it is never chosen... the choice collapses'); slices 5.2, 5.3, 5.4
- FORBIDS: A fork where one child dominates at every skill level; 'feels balanced' tuning; a branch type requiring a new resource/stat/parallel economy; a knob with no measurement hook; verification only by hand-play.
- DEMANDS: Expected-value scoring at multiple play-quality points (miss rates); every new pattern added to the sweep (or a categorical band) before shipping; inverse forks (respite: safe = longer + richer) proving the constraint is crossover, not risky-pays-more.
- Machine-checkable: ENFORCED for shipped patterns (--test-run-economy / --test-run-branch-decisions). Keep the process law: no meta-decision is 'decided' without its sweep assertion landing in the suite.
- Translations:
  - [EXISTS] (mechanic-composition) RunEconomy.expected_net / evaluate_branch(decision, miss_rate) → {costly, safe, costly_wins}
  - [EXISTS] (test-invariant) --test-run-economy: 40-seed × 5-depth sweep, rich_clean / lean_sloppy ≥80% per pattern
  - [EXISTS] (content-pattern) The five patterns (risk_reward, respite, shortcut, gear, recruit) built purely over existing knobs; gear from the canonical flora GEAR_POOL
  - [BUILD] (generator-constraint) The undecided candidates (reconvergence vs regions, shelter/ATP cadence, portal placement, depth scaling, meta-progression) shaped as same-knob patterns + sweep assertions

### P18-taught-by-scene

**The game teaches by scene and geometry, never by lecture: the binding icon is the only tutor and the scene provides the reason; the implicit tell is present from FIRST sight (anything that can hurt you telegraphs diegetically — no coin-flips), explicit help is EARNED by repeated failure in the same place; a missed prompt never repeats — the mechanic just waits; and nothing already taught is ever re-taught.**

- Pillar: Perception, information, and learning are the content
- Sources: GDD §2.8 (lines 543-545: 'Tutorial as scene, not as segment') + §2.1.2/2.1.3; CHANNELS_DESIGN §Section-design #3 + §Entry teaching (the Junction wash-intro: an ENEMY dies in the wash before the player can); channels_edits.md 'Don't re-tutorial' (the flow/stagnant cut); slices 1.9, 3.4, 3.11
- FORBIDS: Explanatory tutorial popups ('Press E to interact'); a zone called 'tutorial'; hiding the implicit telegraph behind failure; tutorial spam up front; pausing or repeating on a missed prompt; teaching a mechanic outside a scene that motivates it; re-teaching what an earlier scene taught.
- DEMANDS: Binding icons appear on availability and vanish when irrelevant; flow-strips brighten before EVERY surge from first sight; earned-hint thresholds (ghost flush-preview only after ~3 washes in the SAME section); demonstration over description; a HAZARD+TELL field naming each hazard's pause-readable telegraph; a TEACH_BEAT checklist against prior scenes.
- Machine-checkable: Partially ENFORCED (real-input reachability is first-class in --test-all). Open slots: tell-at-t0 + hint-threshold asserts; HAZARD+TELL field validation. 'Never re-teach' is authored-only (checklist against prior scenes).
- Translations:
  - [EXISTS] (mechanic-composition) wash_relay FLUSH_HINT_THRESHOLD=3 + _section_wash_counts + _play_flush_hint ghost preview — the earned-hint escalation implemented exactly as specified
  - [EXISTS] (level-element) channels_wash_intro_chunk teaching room (Capbage ×3, flure, portal, lure-into-wash drown) + tutorial_prompt.gd + poem-teaches-fast-forward
  - [EXISTS] (test-invariant) Real-input first-gate reachability: every scene's teaching gate completable with ONLY real input, no force-fire (--test-input-playthrough, --test-intro-realinput)
  - [BUILD] (test-invariant) Test: implicit tell fires before onset 1 at t=0; explicit hint node ABSENT until wash_count==3 in one section
  - [BUILD] (generator-constraint) HAZARD+TELL as a required generator field for every emitted hazard — the telegraph strips exist and survive the warped GLB scene; the field enforcement doesn't

## Build-next (leverage-ranked: each serves multiple principles)

1. **Degrading flora-network read-window with observation PROVENANCE: a run-scoped milestone-keyed duration (60s→2-3s), pins populated from observation events (the bridge overlook), freshness-stamped enemy-position snapshots that go stale, relationship-keyed decay order** (effort: large; serves: P1-degradation-difficulty, P2-composite-perception, P3-information-scarcity, P4-no-memory-gate, P5-deterministic-emergent, P14-flora-one-verb) — THE convergence point — six principles land on this one mechanic. Substrate exists: get_flora_network(), FloraLight, flora_garden_chunk, the deterministic detection layer to snapshot. This is also what finally makes the long-arc difficulty ramp (P1) buildable at all.
2. **Scarpet: medium-tier scent-mask ground cover + the drag/carry state (slow, no combat, perception loss)** (effort: medium; serves: P10-shadow-law, P12-held-commitment, P13-ecology-of-regulators, P14-flora-one-verb, P15-canon-and-meaning, P18-taught-by-scene) — One flora unlocks the canonical Mother Flure shadow solve (GDD 2.6.4), completes the hide-tier triad (CONCEAL_MEDIUM already hosts it, code even name-checks 'scarpet'), and later carries Marco's diegetic demo scene. Highest leverage-per-effort on the list.
3. **Stage-gated overlook + POI-visibility scarcity in stretch_generator, with its test (high-stage specs emit no full-layout vantage; preview data omits undiscovered POIs)** (effort: small; serves: P1-degradation-difficulty, P3-information-scarcity, P16-clock-budget, P17-crossover-decisions) — Direct encoding of the director's 'information gets scarcer'; fits the existing stage-keyed curriculum pattern. Turns scouting into a time spend, feeding the clock.
4. **Ability-ablation verifier slot in stretch_solution_solver: regenerate a section minus one ability, assert BLOCKED or strictly costlier** (effort: small; serves: P2-composite-perception, P6-proven-mechanical-truth, P10-shadow-law) — Makes 'load-bearing, not flavor' a machine verdict. Natural extension of stretch_capabilities.gd — the loadout model already exists.
5. **Day-clock term in RunEconomy + dusk-margin assertion in the headless playtest loop (nominal-pace finish lands near-but-not-before-comfortably dusk, per tier)** (effort: medium; serves: P7-one-simulation, P11-fail-forward, P16-clock-budget, P17-crossover-decisions) — The regression guard for the director's 'runs too easy vs the day/night cycle'. Host (stretch_generation_playtest_loop.gd) and economy model (run_economy.gd) both exist; this is wiring + a target band.
6. **Monotone-ascent stretch-level verifier (chunk exits strictly ascend, wash target = current chunk start, verify() per chunk in emitted stretches) — the gated-ASCENT rework of the meta-template connectivity** (effort: medium; serves: P6-proven-mechanical-truth, P8-gated-ascent, P11-fail-forward) — Memory flags the spiral meta-template connectivity as free-walk/descending — the register's clearest existing violation. verify() exists per chunk; lift it to stretch level and fix the weaver.
7. **Depth-scaled diegetic recovery cost: Terminal ATP/time price and Sloperope climb duration as monotone functions of fall depth** (effort: small; serves: P11-fail-forward, P12-held-commitment, P16-clock-budget) — Devices exist with flat costs. This is where the clock bites failure — small change, closes the loop between the failure grammar and the day budget.
8. **Inter-enemy interaction matrix, built scheduler-analytic edge by edge (Naturalizer-vs-Flare friendly fire, Meeb engulf-freeze window, locust cannibalize, siderophore iron-gradient seeking)** (effort: large; serves: P5-deterministic-emergent, P6-proven-mechanical-truth, P9-archetype-vocabulary, P13-ecology-of-regulators, P15-canon-and-meaning) — Ecology as routable content — the GDD's multilateral encounters. _resolve_strike is enemy→party only today. MUST be scheduled predictions, not per-frame contact (the swarm-surge lesson), or FF invariance breaks. Use the canonical renamed roster.
9. **Live in-engine replay of a GENERATED stretch, including the SHADOW path (real detection, washes, dwell — not the solver graph)** (effort: large; serves: P5-deterministic-emergent, P6-proven-mechanical-truth, P7-one-simulation, P10-shadow-law) — The named missing rung closing 'topology-gating != solvable' at run scale. Solver artifact + replay builder + real-input test patterns all exist; compose them.
10. **Held-helper hardening: generator field (helper ∈ held types, never latch) + holder-washed-mid-hold inheritance test + one authored guard-threatens-the-holder section** (effort: medium; serves: P2-composite-perception, P12-held-commitment, P13-ecology-of-regulators) — The wash_relay held controls exist; this makes the commitment grammar a rule, proves role inheritance, and ships the first stacked WHERE+WHEN pressure section (also serves P1's escalation menu).
11. **Typed chain handshake (link OUTPUT → next link CONSUMES, checked at generation) + archetype-9 pool exclusion with a never-generated assert** (effort: small; serves: P6-proven-mechanical-truth, P9-archetype-vocabulary) — The four canonical chains in design_archetypes are already output-typed in prose; make the generator honor them, and keep subversions out of the pool by rule not convention.
12. **Enemy-charge structure impact (a charge that breaks/activates what it hits)** (effort: medium; serves: P6-proven-mechanical-truth, P9-archetype-vocabulary, P13-ecology-of-regulators) — The single named mechanic blocking 'redirect' chunks in the honesty ledger (Archetype 1's entire premise). Charge, dodge-at-impact, and bait-positioning already exist and are tested — only the collision→state-change is missing.

## Tensions the director should arbitrate

- Geometry-teaches vs information-scarcity: every hazard must telegraph diegetically from FIRST sight (no coin-flips), yet information is content that gets scarcer — and late-game 'observable wrongness' deliberately makes the party's data WRONG. The line to hold: TELLS are never scarce and the WORLD never lies; only FOREKNOWLEDGE (layout, positions, cadence values) is withdrawn, and only the OVERLAY may lie. Every degradation effect must be classified as overlay-side before shipping, or the game breaks its no-coin-flips covenant.
- Degradation-difficulty vs the shipped curriculum ramp: --test-curriculum-ramp — the register's flagship escalation verifier — currently grows effective depth/size with stage, which is exactly the level-side hardness P1 rejects. Defensible as an early teaching ramp, but there is no defined handoff point where escalation migrates to degradation params (which don't exist yet in generation). Until that handoff is designed, the test suite partially enforces the anti-principle.
- No-memory-gate vs decaying reads: P3/P1 withdraw information and let reads go stale, while P4 forbids requiring note-taking. The reconciliation — every critical-path read must be re-acquirable in-world at a TIME price (scarcity prices time, never memory) — is stated nowhere as a rule and encoded nowhere in the solver. Without it, any designer adding a stale-read gate on the critical path violates P4 silently.
- Shadow-never-surfaced vs multi-solution-proven: generation must PROVE two divergent solves (P6/P10) while the UI, dialogue, and environment must never hint the second one exists. The proof machinery (solver verdicts, replay artifacts, completion logging) must stay invisible to the player — no badges, no 'alternate route found' toasts. This is an authored-only discipline sitting directly on top of a machine-verified one; easy to break in a well-meaning UI pass.
- Permadeath vs the bare-pair floor: the shadow law floors solvability on Aster+Peris, but roguelike permadeath (dlc_roguelike) could take one of THEM. Either the core pair is un-permadeathable (undermining 'losing a character means losing their layer' at its most dramatic) or generation must re-floor on the surviving roster — and RunSession today only GROWS the roster; shrink is unbuilt and the design answer is genuinely undecided.
- Held-commitment vs clock-budget: holds burn real daylight while the holder stands exposed, and depth-scaled recovery adds more time cost. Stack P12 and P16 carelessly and setup-over-reflex degrades into waiting-as-content. The channels docs' own mitigation — hold windows host character beats, and BRACE refunds re-cross stamina — must be preserved when the dusk-margin assertion starts tightening run slack, or the fix for 'too easy' will make holds feel like punishment.
- Determinism vs ecological emergence: every inter-enemy matrix edge (P13) multiplies world state that P5 requires to stay analytic on the scheduler tick. Built as per-frame contact checks, the matrix breaks fast-forward invariance the moment two enemies interact off-screen — the swarm-surge divergence generalized. Rule for the build: each matrix edge ships WITH its FF-invariance test, or it doesn't ship.

## Source audit (independent verification pass)

All 18 entries were spot-checked against their cited sources and the codebase: 17/18 verified (quotes confirmed verbatim, exists-today claims confirmed in code). Flags:

- **P11-fail-forward FLAGGED:** Concrete conflict papered over: the statement sanctions 'mobile at the previous gap' and 'stranded-but-recoverable at the start shelter' as interchangeable variants, but its primary cited source says only one. CHANNELS_DESIGN lines 75-91 + #6 are unambiguous — swept 'to the START of the stretch (the start shelter)... STRANDED there until recovered', and the chunk-mapping section marks strand-and-rescue as '⏳ being made real now'. 'Mobile at the previous gap' is only the shipped wash_relay behavior (--test-wash-relay-checkpoint, verified in test_runner_cli.gd/CLAUDE.md). The register cites that test as ENFORCING the principle while the principle's source specifies the opposite sweep target and mobility — an unflagged doc-vs-code contradiction the register should surface as a tension, not merge with 'or'. Everything else in the entry is sound: depth-scaled consequence, recover-now-vs-defer choice, all-washed=redo-chunk, BRACE refund are all verbatim CHANNELS_DESIGN; soft-lock harness demand verbatim in the hide spec; flat-cost gap honestly flagged.

## Audit addenda — canonical principles the register MISSED (candidate P19-P28)

The auditor found these in the docs but absent from the register. Promote, merge, or strike as you see fit:

1. Danger-zone clock exemption (GDD §10.2): once the player commits to a cure-component retrieval zone, the day/night cycle stops applying, nighttime threats do not spawn, external threats do not enter, sustenance is scattered in the puzzle area, and leave-and-return preserves progress ('the game respects their attention by removing the clock'). This is a canonical carve-out that directly bounds P16's clock-budget and P5/P16 tuning — absent from the register.
2. Cure discovery principle (GDD §10.1): nobody — including the party — knows a cure exists while early components are found; they are encountered as gifts/salvage/curiosities and retroactively reframed by mid-game schematics. Before that, the player is just exploring. A canonical structure/reveal principle with no register entry.
3. Tutorial-seed reward pattern (GDD §9.4): tutorial interactions are never rewarded mechanically in the tutorial; they may seed rewards later in locations chosen for thematic resonance, rewarding players who treat tutorials as character-revelation, not loot. Distinct from P18's teach-by-scene and absent.
4. Shadow solutions never gate endings + endings scale with completeness (GDD §2.6.6, §13, §1): 'Shadow solutions do not lock or unlock endings' (endings depend on cure-component collection only; 'It Takes Two' is achievement-only); the four endings differentiate on effort/attention (worst is the default main-path outcome, best requires every component/shelter/ally). P10 stops short of the shadow/endings firewall and no entry carries the endings-differentiation principle.
5. Two-to-six roster scalability of setpieces (GDD §13.4 + 2.6.4): the endgame Psy-Knapse defense is 'designed to be solvable from two characters to six, with the experience scaling rather than the puzzle'. P10's bare-pair floor covers the bottom end only; the scale-the-experience-not-the-puzzle law is absent.
6. Pause-and-direct indirect control as design law (GDD §2.1, §2.5): the player directs, never inhabits; pause decouples session time from game time; shift-click action queueing with parallel per-character queues; channel-on-arrival interaction (no separate interact button; channel duration = the work, not input cost); the four item verbs as the ENTIRE item vocabulary. The register treats control grammar as implementation, but the GDD states it as core design.
7. Auto-dodge as policy, not reflex, with scan-gated coverage (GDD §2.1.6): 'The player times nothing; the verb stays inside the game's policy grammar of reads, positioning, and commitments rather than reflexes'; the device only evades species the overlay has scanned, so every unscanned species gets one free attack — observation from cover is systematically rewarded; a dodged charge carries the attacker into what stood behind (a deliberately untutorialized bait affordance). Adjacent to P12 but a distinct canonical mechanic law.
8. Three voices in three registers / Endo never speaks / hazards themed as pathology (CHANNELS_DESIGN §Section-design #7 + DIALOGUE template field, character_endo_silent memory): Aster = data read, Peris = relational/flora read, Endo NEVER speaks (UI marker/gesture/pre-scouted path only); '//' reserved for true machine confirmations; every hazard themed as the body's waste-clearance failing ('the wash is iron, not water'). These are register/theming constraints on game design (not prose style) and the register's channels template coverage skips this field.
9. Section ID/TYPE = ONE verb per section (CHANNELS_DESIGN spec template): each section names exactly one verb (override / read-the-beat / hold-plate / hide / lure). The register covers PERCEPTION_LOCK, CADENCE, ADVANCE_HELPER, ROLE_INHERITANCE, FAIL/RECOVER, HAZARD+TELL, TEACH_BEAT, ESCALATION_HOOK — but not the one-verb-per-section field.
10. Act-scale ecological succession (GDD §2.7 line ~539, §7.13): the ecology itself shifts across acts — enemies fought in Act 1 are displaced by species the party never met early; 'the world the player traverses in Act 3 is not the same world they traversed in Act 1; the regulatory failure has propagated'. P13 covers the inter-enemy matrix as routable content but not world-scale succession as a content/difficulty principle.

## Tension metrics + the micro-chunk method (director ruling, 2026-07-02)

The director's diagnosis of the first hand-authored level (Pump Hall): *boring — no thinking required.*
The correction is a METHOD, not a bigger level: **start from ONE core tension point per chunk**, prove it
plays taut, and only then compose. Big chunks come from proven small ones, never authored whole.

**The three metrics every chunk must answer (director's words, lightly compressed):**
1. **Optimal-solution feel** — is there a solve the player feels *clever* for finding? (Not a walk;
   a plan.)
2. **Positioning significance** — is standing-ground a real decision? If ~90% of the level is safe,
   decisions are cheap; shrink safe ground until *where you are* matters.
3. **Stamina sufficiency under threat** — when the route runs past an enemy (this game runs past,
   not only around), is the bar *just* enough for the efficient plan? The target feel: "I made it
   with my heart racing — if I'd done any step less efficiently I wouldn't have."

**The pricing currency (SWEPT + ADOPTED, director ruling off the tension-sweep table):** one full
stamina bar = **40 world units of sprint** (drain 15/s at RUN_SPEED 6; "20 was too short"), then
forced to a walk. The sweep's second axis — the DEATH MARCH (run dry point-blank, walk away under
the strike cycle): a standard 2.4 patroller NEVER downs a walker (slow watches are area denial, not
death); the 3.6 pressure tier downs a dry walker within ~68wu (4 hits at 25); elites (4.2) within
~51wu. Game-wide reading: dry mid-chunk near fast fauna = down before the next haven unless a
shelter or a friend is close. `--test-run-stamina-budget` + `--test-tension-sweep` assert all of it;
re-run the sweep (`--test-tension-sweep`) whenever speeds/damage change. Underneath sits the LEADING
LUNGE: a charge aims where the target WILL be (predict_position off the committed plan) — walkers
are catchable, sprinters slip it inside the charge cap, and strikes only land in reach. SPRINT
ESCAPES, WALK EATS IT — that asymmetry IS the dry-bar tension. A tension chunk PRICES its route in
this currency and asserts the price in its test: the Sprint Gap's two legs price at **84% of the
bar** (clean route arrives with ~17 stamina). Tuning law: 80–98%.

**The closed field economy (fragment param `stamina_field_regen: false`):** in tension chunks the bar
regenerates ONLY on shelter ground — havens are recovery points, the field is scarce, and the pause
on a hide pad is *free but not restorative*. (The open legacy economy remains the default elsewhere;
promote closing it globally only after playtests.)

**Core tension seeds (build order):**
1. **Sprint Gap** (SHIPPED, `--preview=sprint_gap`): budget × timing × one hide. Launch on the east
   sweep, hold the scarpet through the pass (MEDIUM at 3.0wu — inside outer 5.0, outside inner 2.25),
   burst as it clears. 95% bar price. `--test-sprint-gap` asserts the clean route, the price band,
   and that the blind walk is spotted-and-attacked.
2. **Run-lure window** (next): fire the flure, then RUN the opened corridor while the lured watcher
   transits — the window is shorter than a walk and the bar must cover approach + crossing.
3. **Sacrificial activation** (next): send Aster to hold/activate a portal inside a watch fan — he
   eats a survivable strike (whiff rules now real: timing the activation against the windup reduces
   the toll), and the portal opens the offshoot hide the others cross through safely. Emergence:
   watch + portal + carry (if he goes down, the retrieve verb is the recovery).

**Emergence rule:** a tension chunk introduces NO new mechanic — it composes run/stamina, hide tiers,
lures, portals, shelters, downs/carry. If a seed seems to need a new mechanic, it's two seeds.

## The two design registers (2026-07-02) + re-ranked build-next

**ENVIRONMENT_ELEMENTS.md** — 52 canon-vetted environmental puzzle elements across all 13 regions
(24 Act 1 / 17 Act 2 / 11 Act 3 *proposals*): each one verb, telegraphed, shadow-solvable, cited, and
honestly tiered (24 COMPOSABLE-NOW / 28 NEEDS-BUILD). **ECOLOGY_COMBOS.md** — the 130-cell flora x
fauna interaction matrix (CANON cite-audited / DERIVED / NONE / 21 OPEN cells awaiting director
rulings) + 12 judge-approved combo cards, each with an emergent property, a tension pricing, its
level-element composition, and a micro-chunk seed in the 80-98% band.

**Ledger additions ([BUILD] items the registers wait on, deduped, roughly by leverage):**
1. CandidZone (DoT floor volume that blinds Naturalizer scans — the risk-inversion corridor; ONE class)
2. Gnawer-tier pursuer (3.6-speed pack pursuer; near-term stand-in: tuned base Enemy, pack logic later)
3. HushbloomStun (proximity stun-burst flora object, regenerating)
4. GasafoetidaPod (carried repellent + fire-burst register)
5. SpikerEnemy (rooted LOS turret) + TanglerEnemy (stealth grappler) — unlocks the predation duel cards
6. Meeb engulf-freeze window (already on the leverage list)
7. CloakedEnemy + reveal channels (the Redactor gate; late-game mandatory). Reveal mechanisms RULED 2026-07-02: material-signature mismatch under Seefern light (metallic/roughness vs surroundings — one rule covering Hidra/early-Crust/Redactor/Tangler) + gas-flow distortion inside a Gasafoetida cloud (silhouette while in the aura, cloak not stripped)
8. Flora-network warning propagation (the tended-network read — flagship, already Tier-3 on the list)
9. FlowRouterValve (rotate-the-pipes terminal variant), MovingPlatform/portal-ferry, conveyor-ride,
   spike-ledge sweep toggles — the element-side classes, one each.

**Re-ranked build-next (T1 = nearest real play):**
- T1a **Capbage retrieve-under-pursuit** (Card 6): stage is composable NOW (held console + downs/carry
  + Capbage + a tuned fast pursuer standing in for the Gnawer). The retrieve verb finally gets its
  tension chunk.
- T1b **Candid risk-inversion corridor** (Card 2): one new class (CandidZone) + existing Naturalizer
  patrols; the trade-hp-for-invisibility decision is the strongest new positioning tension available.
- T1c **Flare-lane vent stage** (Cards 3/11 stage): the Ancourage fused-heat band + Aster vent console
  compose NOW; the Gasafoetida/Flare organisms join later without re-authoring the stage.
- Then: Spiker/Tangler duel stages (Card 9), Meeb ferry (Card 5), Seefern/Redactor reveal gate (Card 1).

## P-KIT: chunks COMPOSE, the kit CONSEQUENCES (director's architecture ruling, 2026-07-14)

The scaffold is shared (one preview scene; chunks are registry data + a Fragment). But Fragment
data cannot express WIRING, so every chunk also ships a script — and an unrestricted script with
GameState access is an invitation to hard-code mechanics. That is exactly how "catch = swept to
the START" (design GUIDANCE, P11) became a bespoke teleport with no visible mechanism: the escape
hatch was open, so under doc pressure it got used — an audit found 20+ consequence-grade calls
across 9 chunks, not one slip.

**The law:** a chunk script may (a) place and wire kit objects, (b) do BOOKKEEPING on kit signals
(e.g. a spotted sentry is no longer lure-distracted; derived hide-tier state), (c) read state for
its preview surface. CONSEQUENCES — teleports, damage, revives, floor changes — belong to KIT
objects (loader object kinds, Enemy behaviors, Channel, CrawlTunnel...), where the player can see
the mechanism that did it to them. When the kit lacks a verb, EXTEND THE KIT (the Enemy
return-to-post default was born exactly this way), never script around it.

**The guard:** `--test-chunk-mutation-discipline` (in --test-all) freezes the existing debt per
(file, mutator) exactly — a new bespoke consequence goes red naming the file and the remedy, and
a burned-down debt must ratchet the ledger down. The loader (data_fragment_chunk) is scaffold and
exempt.

**Burned down (2026-07-14, 20+ calls / 9 chunks → 9 calls / 4 chunks):** the wash sweep is now
`Channel.set_sweep()` — the channel itself stops/carries/bites bodies standing in its flooding
strip; a chunk supplies only the POLICY (where "downstream" lands, what the party pays, the
enemy-id resolver for the tumble). Area burn hazards are the `HazardField` kit object (the
inflammashunt popcorn rides it; toggled by the level's own mechanisms). The root whip rides
`Enemy._resolve_strike` — the kit's ONE strike path, so dodge/sanctuary/conceal/corpse-skip
apply to it for free. All five scripted sentry re-posts are `Enemy.re_post()`.

**Still on the ledger (each needs a kit verb before it can burn):** the chase's portal-follow
pursuer hops (2), its barricade clamber (1) and checkpoint resume (snap+restore — restart-grade
machinery, like the loader's), the boss knockback (snap+adjust), the set-piece magnet pin (1),
and the wash_relay reset flow (2).

