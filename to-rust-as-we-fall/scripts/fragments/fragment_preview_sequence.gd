extends "res://scripts/tutorial/tutorial_sequence.gd"

const DayNightCycleScript = preload("res://scripts/system/simulation/day_night_cycle.gd")
const PreviewWebE2EControllerScript = preload(
	"res://scripts/fragments/preview_web_e2e_controller.gd"
)
const GameHUDScript = preload("res://scripts/ui/game_hud.gd")
const GameHUDScene = preload("res://scenes/ui/game_hud.tscn")
const InputGlyphScene = preload("res://scenes/ui/input_glyph.tscn")
const FragmentPreviewUIScene = preload("res://scenes/ui/fragment_preview_ui.tscn")
const FragmentMenuButtonScene = preload("res://scenes/ui/fragment_menu_button.tscn")
const BranchOptionButtonScene = preload("res://scenes/ui/branch_option_button.tscn")
const InputHintChipScene = preload("res://scenes/ui/input_hint_chip.tscn")
const OverlayToggleButtonScene = preload("res://scenes/ui/overlay_toggle_button.tscn")
const StretchSeedCatalogScript = preload("res://scripts/generation/stretch_seed_catalog.gd")
const CanonicalCharacterAbilityScript = preload("res://scripts/game/mechanics/canonical_character_ability.gd")
const FixedCadenceScript := preload("res://scripts/system/core/fixed_cadence.gd")
const PERCEPTION_STACK_SHADER := preload("res://resources/perception_stack.gdshader")

const STACKS_CHUNK_SCENE := preload("res://scenes/fragments/chunks/stacks_fragment_chunk.tscn")
const RINGS_CHUNK_SCENE := preload("res://scenes/fragments/chunks/rings_fragment_chunk.tscn")
const LOCKOUT_CHUNK_SCENE := preload("res://scenes/fragments/chunks/lockout_fragment_chunk.tscn")
const MOTHER_FLURE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/mother_flure_chunk.tscn")
const SURVIVAL_RANGE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/survival_range_chunk.tscn")
const ENDO_JUNCTION_STRETCH_CHUNK_SCENE := preload("res://scenes/fragments/chunks/endo_junction_stretch_chunk.tscn")
const GENERATED_STRETCH_CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const RESULT_PULSE_WEB_CONTRACT_CHUNK_SCENE := preload(
	"res://scenes/fragments/chunks/result_pulse_web_contract_chunk.tscn")
const REFUGE_RUN_CHUNK_SCENE := preload("res://scenes/fragments/chunks/refuge_run_chunk.tscn")
const CHANNELS_WASH_INTRO_CHUNK_SCENE := preload("res://scenes/fragments/chunks/channels_wash_intro_chunk.tscn")
const PUSH_LAB_CHUNK_SCENE := preload("res://scenes/fragments/chunks/push_lab_chunk.tscn")
const REST_LAB_CHUNK_SCENE := preload("res://scenes/fragments/chunks/rest_lab_chunk.tscn")
const TWO_HANDS_GATE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/two_hands_gate_chunk.tscn")
const SCANNED_PLAZA_CHUNK_SCENE := preload("res://scenes/fragments/chunks/scanned_plaza_chunk.tscn")
const FLORA_GARDEN_CHUNK_SCENE := preload("res://scenes/fragments/chunks/flora_garden_chunk.tscn")
const DUSK_RUN_CHUNK_SCENE := preload("res://scenes/fragments/chunks/dusk_run_chunk.tscn")
const LURE_RELAY_CHUNK_SCENE := preload("res://scenes/fragments/chunks/lure_relay_chunk.tscn")
const DISTRACT_GATE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/distract_gate_chunk.tscn")
const PUZZLE_ATOM_CHUNK_SCENE := preload("res://scenes/fragments/chunks/puzzle_atom_chunk.tscn")
const SHOWCASE_GALLERY_CHUNK_SCENE := preload("res://scenes/fragments/chunks/showcase_gallery_chunk.tscn")
const WASH_RELAY_CHUNK_SCENE := preload("res://scenes/fragments/chunks/wash_relay_chunk.tscn")
const DATA_FRAGMENT_CHUNK_SCENE := preload("res://scenes/fragments/chunks/data_fragment.tscn")
const SHAPE_GRAMMAR_CHUNK_SCENE := preload("res://scenes/fragments/chunks/shape_grammar_preview.tscn")
const CREATURE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/creature_preview.tscn")
const ARCHETYPE_GALLERY_CHUNK_SCENE := preload("res://scenes/fragments/chunks/archetype_gallery.tscn")
const ARCHITECTURE_SHOWCASE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/architecture_showcase.tscn")
const GEOMETRY_LAB_CHUNK_SCENE := preload("res://scenes/fragments/chunks/geometry_lab.tscn")
const SET_PIECE_SHOWCASE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/set_piece_showcase_chunk.tscn")
const BOSS_SHOWCASE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/boss_showcase_chunk.tscn")
const LOCKOUT_CHASE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/lockout_chase_chunk.tscn")
const INFLAMMASHUNT_CHUNK_SCENE := preload("res://scenes/fragments/chunks/inflammashunt_chunk.tscn")
const AGHORA_BAZAAR_CHUNK_SCENE := preload("res://scenes/fragments/chunks/aghora_bazaar_chunk.tscn")
const WASH_ASCENT_CHUNK_SCENE := preload("res://scenes/fragments/chunks/wash_ascent_chunk.tscn")
const SightMaskBakerScript := preload("res://scripts/game/world/sight_mask_baker.gd")
const DEFAULT_PREVIEW_EDGE_SCROLL_MARGIN := 6.0
## Matches perception_stack.gdshader's fully-clear fog radius. Relationship UI uses
## the clear region rather than the soft fringe so it cannot reveal a fogged endpoint.
const PARTY_PERCEPTION_CLEAR_RADIUS := 14.0

# chunk name -> packed scene. The single lookup that replaced the old per-name match (and the reason
# we no longer need one *_preview.tscn per chunk: one scene reads this registry and picks at runtime).
const CHUNK_SCENES := {
	"stacks": STACKS_CHUNK_SCENE,
	"rings": RINGS_CHUNK_SCENE,
	"lockout": LOCKOUT_CHUNK_SCENE,
	"mother_flure": MOTHER_FLURE_CHUNK_SCENE,
	"survival_range": SURVIVAL_RANGE_CHUNK_SCENE,
	"endo_junction_stretch": ENDO_JUNCTION_STRETCH_CHUNK_SCENE,
	"generated_stretch": GENERATED_STRETCH_CHUNK_SCENE,
	"refuge_run": REFUGE_RUN_CHUNK_SCENE,
	"channels_wash_intro": CHANNELS_WASH_INTRO_CHUNK_SCENE,
	"lure_relay": LURE_RELAY_CHUNK_SCENE,
	"distract_gate": DISTRACT_GATE_CHUNK_SCENE,
	"puzzle_atom": PUZZLE_ATOM_CHUNK_SCENE,
	"push_lab": PUSH_LAB_CHUNK_SCENE,
	"rest_lab": REST_LAB_CHUNK_SCENE,
	"two_hands_gate": TWO_HANDS_GATE_CHUNK_SCENE,
	"scanned_plaza": SCANNED_PLAZA_CHUNK_SCENE,
	"flora_garden": FLORA_GARDEN_CHUNK_SCENE,
	"dusk_run": DUSK_RUN_CHUNK_SCENE,
	"showcase_gallery": SHOWCASE_GALLERY_CHUNK_SCENE,
	"wash_relay": WASH_RELAY_CHUNK_SCENE,
	"data_fragment": DATA_FRAGMENT_CHUNK_SCENE,
	"shape_grammar": SHAPE_GRAMMAR_CHUNK_SCENE,
	"creature_grammar": CREATURE_CHUNK_SCENE,
	"archetype_gallery": ARCHETYPE_GALLERY_CHUNK_SCENE,
	"architecture_showcase": ARCHITECTURE_SHOWCASE_CHUNK_SCENE,
	"geometry_lab": GEOMETRY_LAB_CHUNK_SCENE,
	"set_piece_showcase": SET_PIECE_SHOWCASE_CHUNK_SCENE,
	"boss_showcase": BOSS_SHOWCASE_CHUNK_SCENE,
	"lockout_chase": LOCKOUT_CHASE_CHUNK_SCENE,
	"inflammashunt": INFLAMMASHUNT_CHUNK_SCENE,
	"aghora_bazaar": AGHORA_BAZAAR_CHUNK_SCENE,
	"wash_ascent": WASH_ASCENT_CHUNK_SCENE,
}

# The fragment menu, ordered along the combine-characters learning ramp (its `stage` ascending). Each
# entry is a runnable preview: an id, the chunk it loads, a display title, the campaign progression
# stage it sits at, and an optional chunk config (the generated-stretch entries reuse one chunk with
# different spec specs). This list REPLACES the 14 near-identical *_preview.tscn files — the single
# fragment_preview.tscn boots into a picker built from these, and tests/tools select by id. The stage
# is the curriculum position: 1 = intro / single-mechanic, climbing to 6 = the Mother-Flure diagnosis.
const PREVIEW_ENTRIES := [
	{"id": "endo_junction_stretch", "chunk": "endo_junction_stretch", "title": "Endo's Junction to Shelter 1", "stage": 1},
	{"id": "showcase_gallery", "chunk": "showcase_gallery", "title": "Showcase Gallery", "stage": 1},
	{"id": "stacks", "chunk": "stacks", "title": "The Open Files Initiative", "stage": 1},
	{"id": "rings", "chunk": "rings", "title": "Rings Fragment Lab", "stage": 1},
	{"id": "rest_lab", "chunk": "rest_lab", "title": "Shelter Rest Lab", "stage": 2},
	# Compatibility id retained for old links; the scene now inherits the one canonical chase.
	{"id": "lockout", "chunk": "lockout", "title": "The Lockout Chase (legacy alias)", "stage": 4},
	{"id": "generated_stretch", "chunk": "generated_stretch", "title": "Generated Stretch", "stage": 2,
		"config": {"spec_path": "res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"}},
	{"id": "dusk_run", "chunk": "dusk_run", "title": "Dusk Run", "stage": 3},
	{"id": "flora_garden", "chunk": "flora_garden", "title": "Flora Garden", "stage": 3},
	{"id": "pump_hall", "chunk": "data_fragment", "title": "Pump Hall (tactical stealth)", "stage": 3,
		"config": {"fragment_path": "res://data/fragments/pump_hall.tres"}},
	{"id": "sprint_gap", "chunk": "data_fragment", "title": "Sprint Gap (stamina tension)", "stage": 3,
		"config": {"fragment_path": "res://data/fragments/sprint_gap.tres"}},
	{"id": "capbage_retrieve", "chunk": "data_fragment", "title": "The Retrieve (carry him home)", "stage": 3,
		"config": {"fragment_path": "res://data/fragments/capbage_retrieve.tres"}},
	{"id": "blind_floor", "chunk": "data_fragment", "title": "The Blind Floor (risk inversion)", "stage": 3,
		"config": {"fragment_path": "res://data/fragments/blind_floor.tres"}},
	{"id": "distract_gate", "chunk": "distract_gate", "title": "The Watched Gap", "stage": 3},
	{"id": "lure_relay", "chunk": "lure_relay", "title": "Flure Relay", "stage": 3},
	{"id": "generated_chain_nested_poc", "chunk": "generated_stretch", "title": "Generated Chain/Nested POC", "stage": 3,
		"config": {"spec_path": "res://data/generated_stretches/generated_chain_nested_poc_shelter_2_to_3.json"}},
	{"id": "generated_random_walk_poc", "chunk": "generated_stretch", "title": "Generated Random Walk POC", "stage": 4,
		"config": {"spec_path": "res://data/generated_stretches/generated_random_walk_poc_shelter_3_to_4.json"}},
	{"id": "survival_range", "chunk": "survival_range", "title": "Shelter-To-Shelter Range", "stage": 4},
	{"id": "refuge_run", "chunk": "refuge_run", "title": "Refuge Run", "stage": 4},
	{"id": "channels_wash_intro", "chunk": "channels_wash_intro", "title": "Channels — Wash Intro", "stage": 5},
	{"id": "mother_flure", "chunk": "mother_flure", "title": "Mother Flure", "stage": 6},
	# A DATA-driven fragment: the DataFragmentChunk loader composes this entirely from a .tres (no bespoke chunk
	# code) — point it at any Fragment resource via the config below.
	{"id": "object_showcase", "chunk": "data_fragment", "title": "Object Showcase (data)", "stage": 6,
		"config": {"fragment_path": "res://data/fragments/object_showcase.tres"}},
	# PROCEDURAL ROGUELIKE: generate a fresh stretch on load and, each time the party rests at the exit shelter,
	# descend — regenerate the next level (deeper seed, escalating tier) and reload. The fragment loader IS the
	# roguelike driver; no separate scene.
	{"id": "roguelike", "chunk": "puzzle_atom", "title": "Roguelike Run (atom chains)", "stage": 6,
		"config": {"roguelike": true, "levels": "atom", "seed": 1}},
	{"id": "roguelike_wfc", "chunk": "generated_stretch", "title": "Roguelike Run (WFC stretches)", "stage": 6,
		"config": {"roguelike": true, "seed": 1}},
	# SHAPE GRAMMAR: a fragment grown from parametric shapes joined at typed connectors. Press N to
	# regenerate a fresh deterministic variation (a new seed) in place. Boots with the soft fog ON
	# (the district reads through its sightlines) — F2 or the panel button turns it off.
	{"id": "shape_grammar", "chunk": "shape_grammar", "title": "Shape Grammar (procedural layouts)", "stage": 6,
		"config": {"seed": 1, "overlays": {"peris": true}}},
	# CREATURE GRAMMAR: a body grammar (parts with dimension ranges) compiled to SDF primitives and
	# smooth-min meshed — one specimen per canon-grounded archetype. Press N for a new generation.
	# Pure visual iteration surface — perception overlays (fog/data) OFF by default so the forms read clean.
	{"id": "creature_grammar", "chunk": "creature_grammar", "title": "Creature Grammar (SDF morphology)", "stage": 6,
		"config": {"seed": 1, "overlays": {"aster": false, "peris": false, "endo": false}}},
	# GEOMETRY LAB: minimal geometry-construction algorithms with labeled points (algorithm 1 = the
	# awning/hood from a face rectangle). Overlays OFF (a look-dev workbench).
	{"id": "geometry_lab", "chunk": "geometry_lab", "title": "Geometry Lab (minimal algorithms)", "stage": 6,
		"config": {"algorithm": 1, "angle": 45.0, "overlays": {"aster": false, "peris": false, "endo": false}}},
	# Same chunk, algorithm 2 = the RECURSIVE awning (all sides -> blocky stepped mass).
	{"id": "geometry_lab_recursive", "chunk": "geometry_lab", "title": "Geometry Lab 2 (recursive awnings)", "stage": 6,
		"config": {"algorithm": 2, "angle": 45.0, "overlays": {"aster": false, "peris": false, "endo": false}}},
	# Algorithm 3 = clean-merge crossing extruded paths (the lattice-junction fix).
	{"id": "geometry_lab_junction", "chunk": "geometry_lab", "title": "Geometry Lab 3 (path junction merge)", "stage": 6,
		"config": {"algorithm": 3, "overlays": {"aster": false, "peris": false, "endo": false}}},
	# Algorithm 4 = railings via textured cards (balcony + pixel-art alpha railing).
	{"id": "geometry_lab_railings", "chunk": "geometry_lab", "title": "Geometry Lab 4 (railings / cards)", "stage": 6,
		"config": {"algorithm": 4, "overlays": {"aster": false, "peris": false, "endo": false}}},
	# POLICY (director): the most recently worked-on fragments live at the END of this list — the
	# picker displays it REVERSED, so the last entries are the top buttons. When you touch a chunk,
	# MOVE its row down here.
	{"id": "set_piece_showcase", "chunk": "set_piece_showcase", "title": "Set Pieces — crawl / rotate / water / hoist", "stage": 1},
	# ARCHITECTURE SHOWCASE: the district buildings, each built bottom-up (base shape -> lattice). The
	# iteration surface — walk the row, N reseeds. Overlays OFF by default (it's a look-dev gallery).
	{"id": "architecture_showcase", "chunk": "architecture_showcase", "title": "Architecture Showcase (district heroes)", "stage": 6,
		"config": {"seed": 0, "overlays": {"aster": false, "peris": false, "endo": false}}},
	# THE AGHORA: the counterfeit agora's bazaar canyon — seed-varied stacks walling a market lane,
	# the Exchange at its head, banner lines + stalls + the magenta neon. N reseeds the stacks.
	{"id": "aghora_bazaar", "chunk": "aghora_bazaar", "title": "The Aghora (bazaar canyon)", "stage": 6,
		"config": {"seed": 0, "overlays": {"aster": false, "peris": false, "endo": false}}},
	# BOSS PIECES: the two mega-landmark boss encounters (GDD 11) — Loca's Watchtower on its crag
	# with the switchback approach, and the Paranucleus's turning ophanim wheels over the engulfed
	# NUTECH facility. N reseeds both.
	# HOSTILE STREETS: ornamental invasives (docs/DECORATIVE_FLORA.md — no highlight until Peris's
	# Y HARVEST read lights them yellow, CLEAR removes them) + anti-loiter spike strips
	# (SET_PIECES 21 — lure the pack across the studs). Wipe restarts demo the runback decor pass.
	{"id": "hostile_streets", "chunk": "data_fragment", "title": "Hostile Streets (decor + studs)", "stage": 6,
		"config": {"fragment_path": "res://data/fragments/hostile_streets.tres"}},
	# BOSS PIECES, now PLAYABLE: the watchtower switchback CLIMB + trail-head scree WINCH + summit
	# SURVEY beat; the paranucleus thread with the ring-rooted SPIKER sightline (SET_PIECES 18) and
	# the reservoir cache beyond the far mouth. N reseeds both.
	{"id": "boss_showcase", "chunk": "boss_showcase", "title": "Boss Pieces (Watchtower + Paranucleus)", "stage": 6,
		"config": {"seed": 0, "overlays": {"aster": false, "peris": false, "endo": false}}},
	# THE LOCKOUT CHASE (GDD 12.1, docs/LOCKOUT_CHASE.md): tags fail at the checkpoint, Naturalizer
	# waves take the corridor; the levers you learned, Tyreg's choice, the unmarked offshoot.
	{"id": "lockout_chase", "chunk": "lockout_chase", "title": "The Lockout Chase (Act 1 climax)", "stage": 4},
	{"id": "inflammashunt", "chunk": "inflammashunt", "title": "The Inflammashunt (danger zone)", "stage": 4},
	{"id": "puzzle_atom", "chunk": "puzzle_atom", "title": "Generated Atom Chain", "stage": 3,
		# A mechanics-first benchmark: production roguelike chains still receive district dressing,
		# while this standalone preview keeps every gate, signal, and failure readable for tuning.
		"config": {"stages": ["distract:lure", "distract:patrol", "distract:twin"], "seed": 7,
			"zone_setpieces": false}},
	# ADJACENCY LAB: the same generation path used by a real descent, with the prior district
	# supplied explicitly so the entry threshold can be judged without playing a whole run first.
	{"id": "zone_transition_lab", "chunk": "generated_stretch", "title": "Channels to Garden Transition", "stage": 3,
		"config": {"settings": {"id": "zone_transition_lab", "title": "Channels to Garden Transition",
			"seed": 431, "complexity_tier": "standard", "progression_stage": 3,
			"biome": "garden", "previous_biome": "channels"},
			"overlays": {"aster": false, "peris": false, "endo": false}}},
	# WASH RELAY, concept-plate detail pass: WashRelayDressing (survey-first drum / falls /
	# signage / shaft wall) + the two story beats — the lonely flure and the curecumin pad.
	{"id": "wash_relay", "chunk": "wash_relay", "title": "Wash Relay", "stage": 5},
	# The archetype PIECE LIBRARY gallery: every visual body in
	# ArchetypePieceLibrary on its own plinth (bodies, never verbs).
	{"id": "archetype_gallery", "chunk": "archetype_gallery", "title": "Archetype Piece Library", "stage": 1},
	# WASH ASCENT — the from-scratch rebuild (director's restart contract): placements
	# are SCENE NODES in wash_ascent_props.tscn, every visible mesh a library piece
	# (zero primitives, linted), runs measured from real AABBs, storytelling placement
	# (decaying approach / kept bay / measured manifold / overgrown portal ledge).
	{"id": "wash_ascent", "chunk": "wash_ascent", "title": "Wash Ascent (Rebuilt)", "stage": 5},
	# PUSH LAB — the finished queued-push grammar: crate-vs-crate routing (zone D pair),
	# hover outline + PUSH verb, the real-mesh ghost, pause-queue, supersede/stop.
	{"id": "push_lab", "chunk": "push_lab", "title": "Push Lab", "stage": 2},
	# BALANCING BASIN — Phase 1 proving fragment (docs/BALANCING_BASIN.md): the bowl-scale
	# water ROTA (BasinWater kit object) — LOW floor / MID float road / HIGH decks-only,
	# non-uniform windows, dweller eviction, sweep-to-outfall via the Channel transaction.
	{"id": "basin_fill_proof", "chunk": "data_fragment", "title": "Balancing Basin — Fill Proof (water rota)", "stage": 3,
		"config": {"fragment_path": "res://data/fragments/basin_fill_proof.tres"}},
	# TWO HANDS ON THE GATE — the bare-pair held-station co-op (FRAGMENT_IDEAS.md #6). The crossing
	# pads are dead unless somebody bears a gate console, and the holder cannot be the crosser, so the
	# role has to be traded across the gap. Only the near console is watched by a Naturalizer patrol.
	{"id": "two_hands_gate", "chunk": "two_hands_gate", "title": "Two Hands on the Gate", "stage": 2},
	# THE SCANNED PLAZA (FRAGMENT_IDEAS.md #21, base config) — a typed SINK of capacity 1. A fixed
	# enforcement route never leaves, so the plaza absorbs one Naturalizer. Two priced crossings: the
	# scanned open lane (time the sweep) and the scan-blind Candid mat (pay in health).
	{"id": "scanned_plaza", "chunk": "scanned_plaza", "title": "The Scanned Plaza", "stage": 3},
]

# Exported-browser regression fixtures are immutable launch contracts, not game
# content. They are absent from PREVIEW_ENTRIES, the ordinary picker, handoffs,
# and CLI id routing; MainMenu may resolve them only behind explicit ?e2e=1.
const WEB_E2E_PREVIEW_ENTRIES := {
	"generated_player_surface_seed_5": {
		"id": "generated_player_surface_seed_5",
		"chunk": "generated_stretch",
		"title": "Generated Player Surface — Seed 5",
		"stage": 2,
		"config": {
			"settings": {
				"id": "generated_player_surface_seed_5",
				"seed": 5,
				"complexity_tier": "standard",
				"budget": {"node_count": 7},
			},
			"spiral": false,
		},
	},
	"result_pulse_static_green_contract": {
		"id": "result_pulse_static_green_contract",
		"chunk": "result_pulse_web_contract",
		"title": "Result Pulse Static-Green Web Contract",
		"stage": 1,
	},
}

const WEB_E2E_CHUNK_SCENES := {
	"result_pulse_web_contract": RESULT_PULSE_WEB_CONTRACT_CHUNK_SCENE,
}

## The menu entry for an id (or {} if none).
static func get_preview_entry(entry_id: String) -> Dictionary:
	for entry in PREVIEW_ENTRIES:
		if String(entry.get("id", "")) == entry_id:
			return entry
	return {}


## Resolve the ordinary picker plus quarantined exported-browser fixtures. The
## caller is MainMenu's Web + ?e2e=1 boundary; normal preview routing deliberately
## continues to use get_preview_entry() and therefore cannot select these rows.
static func get_web_e2e_preview_entry(entry_id: String) -> Dictionary:
	var fixture_v: Variant = WEB_E2E_PREVIEW_ENTRIES.get(entry_id, null)
	if fixture_v is Dictionary:
		return (fixture_v as Dictionary).duplicate(true)
	var ordinary := get_preview_entry(entry_id)
	return ordinary.duplicate(true) if not ordinary.is_empty() else {}

## The curriculum progression stage a preview entry sits at (1 = intro, climbing to the
## Mother-Flure diagnosis). The picker is authored in ascending-stage order, so this reads
## straight off the entry; missing/unknown ids report stage 1 (the intro floor).
static func get_preview_stage(entry_id: String) -> int:
	return int(get_preview_entry(entry_id).get("stage", 1))

const CHARACTER_IDS := ["aster", "peris", "endo"]
const MAX_VISION_SOURCES := 64
const PROCEDURAL_OCCLUSION_CHUNKS := ["channels_wash_intro", "wash_relay", "generated_stretch"]
const NO_VISION_SOURCE := Vector3(0.0, 0.0, -9999.0)
## Members recruited later in the story. They exist in a preview ONLY when a chunk's
## presence map includes them: built hidden, registered + portraited on demand, and
## unregistered when absent so a parked invisible body never claims grid cells (parked
## characters are cooperative-pathfinding obstacles) in fragments that predate them.
const OPT_IN_CHARACTER_IDS := ["myke"]
const CHARACTER_DISPLAY_NAMES := {
	"aster": "Aster",
	"peris": "Peris",
	"endo": "Endo",
	"myke": "Myke",
}
const CHARACTER_COLORS := {
	"aster": Color(0.29, 0.62, 1.0),
	"peris": Color(1.0, 0.67, 0.27),
	"endo": Color(0.4, 0.72, 0.55),
	"myke": Color(0.85, 0.36, 0.2),
}
const CHARACTER_SPEEDS := {
	"aster": 3.2,
	"peris": 3.0,
	"endo": 2.8,
	"myke": 3.1,
}
const DEFAULT_SPAWNS := {
	"aster": Vector3(4.0, 0.0, 0.0),
	"peris": Vector3(2.0, 0.0, 1.8),
	"endo": Vector3(0.0, 0.0, -1.8),
	"myke": Vector3(-2.2, 0.0, 0.0),
}

const ABILITY_KEYCODES := {
	"Q": KEY_Q,
	"W": KEY_W,
	"E": KEY_E,
	"Z": KEY_Z,
	"X": KEY_X,
	"V": KEY_V,
}
## The spreadsheet still owns which legacy slot an ability uses; InputMap owns the live key behind
## that slot. Abilities that share a slot (Aster/Endo on primary) are resolved by active owner.
const ABILITY_INPUT_ACTION_BY_KEYBIND := {
	"Z": "ability_primary",
	"X": "ability_secondary",
	"Y": "ability_tertiary",
}
## Direct party abilities are arranged as six stable character columns with two rows each. InputMap
## owns the live, remappable right-hand layout (UIOP[] / JKL;'\\ by default). Spreadsheet Z/X/Y
## bindings remain compatibility fallbacks only when a direct action is explicitly unbound.
const PARTY_ABILITY_OWNER_ORDER := ["aster", "peris", "endo", "myke"]
const PARTY_ABILITY_ACTIONS := [
	["party_slot_1_ability_1", "party_slot_1_ability_2"],
	["party_slot_2_ability_1", "party_slot_2_ability_2"],
	["party_slot_3_ability_1", "party_slot_3_ability_2"],
	["party_slot_4_ability_1", "party_slot_4_ability_2"],
	["party_slot_5_ability_1", "party_slot_5_ability_2"],
	["party_slot_6_ability_1", "party_slot_6_ability_2"],
]
const PREVIEW_GUI_CONTRACT_ID := "fragment_preview_shared_gui_v1"
const GAME_HUD_SCRIPT_PATH := "res://scripts/ui/game_hud.gd"
const PREVIEW_CONTROL_ACTIONS := [
	"command", "camera_pan_forward", "camera_pan_back", "camera_pan_left", "camera_pan_right",
	"camera_pan", "select_primary", "select_secondary", "select_tertiary",
	"preview_cycle_character", "ability_primary", "ability_secondary", "preview_drop_item",
	"preview_transfer_item", "preview_retrieve_item", "preview_overlay_aster",
	"preview_overlay_peris", "preview_overlay_endo", "preview_overlay_drawer", "route",
	"preview_toggle_dodge", "pause", "run", "preview_reload", "preview_toggle_instructions",
	"party_slot_1_ability_1", "party_slot_1_ability_2",
	"party_slot_2_ability_1", "party_slot_2_ability_2",
	"party_slot_3_ability_1", "party_slot_3_ability_2",
	"party_slot_4_ability_1", "party_slot_4_ability_2",
	"party_slot_5_ability_1", "party_slot_5_ability_2",
	"party_slot_6_ability_1", "party_slot_6_ability_2",
]
const PREVIEW_INVENTORY_ACTIONS := [
	"party_slot_1_ability_1", "party_slot_1_ability_2",
	"party_slot_2_ability_1", "party_slot_2_ability_2",
	"party_slot_3_ability_1", "party_slot_3_ability_2",
	"party_slot_4_ability_1", "party_slot_4_ability_2",
	"party_slot_5_ability_1", "party_slot_5_ability_2",
	"party_slot_6_ability_1", "party_slot_6_ability_2",
	"ability_secondary", "preview_drop_item", "preview_transfer_item", "preview_retrieve_item",
]
# The canonical per-ability key/owner bindings now live in data/abilities/en/abilities.xlsx (the
# "bindings" sheet), read via AbilityData.binding(id) — see _apply_canonical_main_ability_binding.

const DEFAULT_HP := 100.0
const DEFAULT_STAMINA := 100.0
const DEFAULT_ATP := GameState.ATP_MAX_PIPS
const DEFAULT_DAY := 1
const DEFAULT_TIME := 0.28
const DEFAULT_DAY_DURATION_SECONDS := DayNightCycleScript.DEFAULT_DAY_DURATION_SECONDS
const DEFAULT_NIGHT_DURATION_SECONDS := DayNightCycleScript.DEFAULT_NIGHT_DURATION_SECONDS
# Keep preview play on the same 40-world-unit sprint bar as canonical GameState.
# A separate 18/s override made generated proofs, deterministic replays, and the
# playable browser disagree about whether the same route exhausted Peris.
const STAMINA_DRAIN := 15.0
const STAMINA_REGEN := 10.0
const PREVIEW_STAMINA_TICK := 0.25
const PREVIEW_RUNTIME_AUTHORITY_VERSION := 1
const PREVIEW_RUNTIME_AUTHORITY_KEY := "runtime:fragment_preview"
const PREVIEW_STAMINA_TAG := "fragment_preview:stamina"
const PREVIEW_ABILITY_TAG_PREFIX := "fragment_preview:ability:"

# The chunk this preview loads. A string (it's the serializable handle the data layer needs — the
# puzzle JSON, the --preview=<id> CLI arg, and test .set() all key on it), but constrained to the
# registry by an inspector dropdown + load-time validation. Keep this list == CHUNK_SCENES.keys()
# (the --test-fragment-preview-registry test enforces it). Empty = the picker (preview_menu).
@export_enum("stacks", "rings", "lockout", "mother_flure", "survival_range",
	"endo_junction_stretch", "generated_stretch",
	"refuge_run", "channels_wash_intro", "lure_relay", "distract_gate", "puzzle_atom", "push_lab", "rest_lab", "flora_garden", "dusk_run", "showcase_gallery", "wash_relay", "data_fragment", "shape_grammar", "creature_grammar", "archetype_gallery", "architecture_showcase", "geometry_lab", "set_piece_showcase", "boss_showcase", "aghora_bazaar", "lockout_chase", "inflammashunt", "wash_ascent", "two_hands_gate", "scanned_plaza") var preview_chunk := "stacks"
@export var scene_title_override := ""
@export var preview_chunk_config: Dictionary = {}

# --- Procedural roguelike run (the loader is a thin presenter over RunSession, the headless run authority) ---
var _roguelike_active := false
var _roguelike_advancing := false
var _run_session: RunSession = null
var _branch_modal: Control = null
## When true, boot into a fragment PICKER instead of loading a chunk directly. The single
## fragment_preview.tscn sets this; selecting an entry loads it, and the Menu action (M) returns here.
## A `--preview=<id>` command-line arg (or a preset preview_chunk) skips the menu and loads directly.
@export var preview_menu := false

## One-shot launch override for MAIN-MENU buttons: change_scene_to_file can't set exports, so a menu
## button stores the registry id here before switching scenes and the preview boots that entry
## directly (the peris `_visit_phase` static pattern). Cleared on consume — R still returns to the
## picker afterwards.
static var menu_launch_id := ""
static var menu_launch_entry: Dictionary = {}
var _active_preview_entry_id := ""
var _active_preview_entry: Dictionary = {}
var _pending_preview_handoff_id := ""

var _characters: Dictionary = {}
var _character_state: Dictionary = {}
var _ability_defs: Dictionary = {}
var _ability_runtime: Dictionary = {}
var _ability_order: Array[String] = []
var _pending_targeted_ability_id := ""

var _hud
var _active_char_id := ""
var _selected_char_ids: Array[String] = []
var _occlusion_mgr: CameraOcclusionManager   # see-through level: geometry between camera + active char dissolves
var _run_active := false
var _routing_mode := "safe"
## Preview-only toggle (G): when true the party can dodge-roll, so enemy strikes auto-evade. Off by
## default — dodge isn't unlocked in every chunk, so attacks land. A chunk may default it on via
## preview_dodge_unlocked().
var _preview_dodge_unlocked := false
var _pushed_active_char_id := ""
var _preview_interactables: Array = []
var _active_chunk: Node3D
var _preview_day := DEFAULT_DAY
var _preview_time := DEFAULT_TIME
var _preview_clock_running := true
var _preview_show_time := true
var _preview_cycle = DayNightCycleScript.new()
## The preview clock is an analytic projection of scheduler time. These anchors, rather than a
## render-delta accumulator, are the portable authority used by saves, replay, and shelter commits.
var _preview_clock_anchor_day := DEFAULT_DAY
var _preview_clock_anchor_time := DEFAULT_TIME
var _preview_clock_anchor_tick := 0.0
## Field stamina regeneration is the only preview-specific stamina rule. Sprint drain itself uses
## GameState's serialized running cadence; this fixed epoch reconstructs every regeneration tick.
var _preview_stamina_epoch := -1.0
var _preview_stamina_next_tick := -1.0
var _preview_runtime_initialized := false
var _restoring_preview_runtime := false
var _applying_preview_run_state := false
var _preview_runtime_baseline: Dictionary = {}
var _preview_environment: Environment
var _preview_directional_light: DirectionalLight3D
var _suppress_hud_character_signal := false

# Browser release observation is isolated in an addable controller and is dormant unless ?e2e=1.
var _web_e2e_controller = null

var _overlay_states := {
	"aster": true,
	"peris": true,
	"endo": true,
}
var _overlay_buttons: Dictionary = {}
var _overlay_panel_content: VBoxContainer
var _overlay_panel_status_label: Label
var _overlay_panel_collapse_button: Button
var _overlay_panel_collapsed := false
var _overlay_panel_margin: MarginContainer
var _overlay_stack_quad: MeshInstance3D
var _overlay_stack_material: ShaderMaterial
var _vision_sources_image: Image
var _vision_sources_texture: ImageTexture
var _vision_sources_cache: Array[Vector3] = []
var _inventory_panel_label: Label
var _inventory_panel_title: Label
var _inventory_controls_flow: HFlowContainer
var _inventory_panel_margin: MarginContainer

var _preview_layer: CanvasLayer
var _menu_panel: PanelContainer
var _menu_backdrop: ColorRect
var _in_menu := false
var _seed_case_selector: OptionButton
var _seed_value_edit: LineEdit
var _seed_tier_selector: OptionButton
var _seed_case_note: Label
var _seed_cases: Array[Dictionary] = []
var _instructions_margin: MarginContainer   # the top briefing/instructions panel — toggled with H
var _title_label: Label
var _help_label: Label
var _control_hint_flow: HFlowContainer
var _ability_hint_flow: HFlowContainer
var _note_label: Label
var _note_default := ""
var _show_default_note := true
var _status_margin: MarginContainer
var _note_timer := 0.0

func _get_chunk_scene(chunk_name: String) -> PackedScene:
	if WEB_E2E_PREVIEW_ENTRIES.has(_active_preview_entry_id):
		var web_fixture_scene_v: Variant = WEB_E2E_CHUNK_SCENES.get(
			chunk_name, null)
		if web_fixture_scene_v is PackedScene:
			return web_fixture_scene_v as PackedScene
	return CHUNK_SCENES.get(chunk_name, null)

func _build_scene() -> void:
	_web_e2e_controller = PreviewWebE2EControllerScript.new()
	_web_e2e_controller.name = "PreviewWebE2EController"
	add_child(_web_e2e_controller)
	_web_e2e_controller.setup(Callable(self, "_web_e2e_context"), CHARACTER_IDS)

	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.035, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.25, 0.27, 0.32)
	environment.ambient_light_energy = 0.55
	environment.glow_enabled = true
	environment.glow_intensity = 0.25
	world_environment.environment = environment
	env.add_child(world_environment)
	_preview_environment = environment

	var preview_sun := DirectionalLight3D.new()
	preview_sun.name = "PreviewSun"
	preview_sun.rotation_degrees = Vector3(-54.0, 28.0, 0.0)
	preview_sun.light_color = Color(0.82, 0.78, 0.74)
	preview_sun.light_energy = 0.75
	preview_sun.shadow_enabled = true
	env.add_child(preview_sun)
	_preview_directional_light = preview_sun
	_apply_preview_lighting()

func _build_characters() -> void:
	var characters_root := Node3D.new()
	characters_root.name = "Characters"
	add_child(characters_root)

	for char_id in CHARACTER_IDS:
		var node := _create_player_character(CHARACTER_DISPLAY_NAMES[char_id], CHARACTER_COLORS[char_id])
		node.position = DEFAULT_SPAWNS[char_id]
		characters_root.add_child(node)
		_characters[char_id] = node

	for char_id in OPT_IN_CHARACTER_IDS:
		var node := _create_player_character(CHARACTER_DISPLAY_NAMES[char_id], CHARACTER_COLORS[char_id])
		node.position = DEFAULT_SPAWNS[char_id]
		node.visible = false
		characters_root.add_child(node)
		_characters[char_id] = node

	for character_node in _characters.values():
		var target_callable := Callable(self, "_on_preview_ability_target_clicked")
		if character_node != null and character_node.has_signal("ground_clicked") \
				and not character_node.is_connected("ground_clicked", target_callable):
			character_node.connect("ground_clicked", target_callable)
		var refused_callable := Callable(self, "_on_preview_move_command_refused")
		if character_node != null and character_node.has_signal("move_command_refused") \
				and not character_node.is_connected("move_command_refused", refused_callable):
			character_node.connect("move_command_refused", refused_callable)

	_player = _characters["aster"]
	if not Engine.is_editor_hint():
		# Free-look on by default in the preview — you're here to inspect a chunk, so WASD / middle-drag
		# pan the camera around it (click recenters on the active character).
		_setup_game_camera(_player, Vector3(0, 12, 9), true)

func _register_characters() -> void:
	# Sprint drain is already a portable GameState phase (including its next cadence tick). Keep the
	# preview on the canonical game-wide rate; modes may later override that through explicit settings,
	# never through a second hidden preview economy.
	if _game_state != null:
		_game_state.run_stamina_drain_per_sec = STAMINA_DRAIN
	for char_id in CHARACTER_IDS:
		var character_node: Node3D = _characters[char_id]
		_register_gs_character(char_id, character_node, CHARACTER_SPEEDS[char_id], {
			"hp": DEFAULT_HP,
			"stamina": DEFAULT_STAMINA,
			"atp": DEFAULT_ATP,
		})
		if character_node != null and character_node.has_method("bind_interaction_root"):
			character_node.call("bind_interaction_root", self)

func _setup_ui() -> void:
	_build_preview_ui()
	_build_game_hud()
	if is_instance_valid(_party_item_controller):
		_party_item_controller.configure({
			"mode": "rich",
			"present_all_items": true,
			"character_names": CHARACTER_DISPLAY_NAMES,
			"message_sink": Callable(self, "show_preview_message"),
			"note_sink": Callable(self, "show_preview_note"),
			"status_sink": Callable(self, "set_preview_character_status"),
			"character_sync_sink": Callable(self, "_sync_character_from_game_state"),
			"character_position_resolver": Callable(self, "get_preview_character_position"),
			"character_node_resolver": Callable(self, "get_preview_character_node"),
		})
		_party_item_controller.bind_inventory_view(Callable(self, "_refresh_inventory_panel"))
	_connect_preview_runtime_signals()
	_initialize_default_character_state()
	_apply_selection_state(["aster"], "aster")

func _begin() -> void:
	# A command-line `--preview=<id>` always wins (headless tests / `godot ... -- --preview=lure_relay`).
	var cli_id := _cli_preview_id()
	if cli_id != "":
		_apply_preview_entry(get_preview_entry(cli_id))
	elif not menu_launch_entry.is_empty():
		_apply_preview_entry(menu_launch_entry)
		menu_launch_entry = {}
	elif menu_launch_id != "":
		_apply_preview_entry(get_preview_entry(menu_launch_id))
		menu_launch_id = ""
	elif preview_menu:
		_show_fragment_menu()
		return
	_begin_chunk()

## Opt-in load tracing: run with PREVIEW_DEBUG=1 to print each load step (the last "→ X" before a crash
## is the step that died). Cheap + harmless when the env var is unset.
func _pdbg(msg: String) -> void:
	if OS.has_environment("PREVIEW_DEBUG"):
		print("[preview] → ", msg)

func _configure_hud_atp_granularity() -> void:
	if _hud == null or not _hud.has_method("set_atp_pip_subdivisions"):
		return
	var subdivisions := 1
	if _active_chunk != null and _active_chunk.has_method("get_preview_state"):
		var state: Dictionary = _active_chunk.call("get_preview_state")
		if str(state.get("food_test", "")) == "scarcity":
			subdivisions = 2
	_hud.call("set_atp_pip_subdivisions", subdivisions)

## Build (or load) the chunk named by preview_chunk and wire up the party/UI around it.
func _begin_chunk() -> void:
	_pdbg("begin_chunk '%s'" % preview_chunk)
	_in_menu = false
	if _menu_panel != null:
		_menu_panel.visible = false
	if _menu_backdrop != null:
		_menu_backdrop.visible = false
	if _hud != null:
		_hud.visible = true
	# Fail LOUD on a typo'd id — otherwise _load_chunk silently builds an empty placeholder chunk and
	# the preview looks "booted but blank". The registry is the allow-list.
	if _get_chunk_scene(preview_chunk) == null:
		push_error("fragment_preview: unknown chunk '%s'. Valid: %s" % [preview_chunk, ", ".join(CHUNK_SCENES.keys())])
		show_preview_message("Unknown fragment '%s' — see CHUNK_SCENES." % preview_chunk, 6.0)
	set_preview_step(preview_chunk)
	_pdbg("load_chunk")
	_active_chunk = _load_chunk(preview_chunk)
	_configure_hud_atp_granularity()
	# These Channels chunks add tall procedural walls/branch frames outside their imported
	# backdrop. Wrap that environment-scale geometry too; other chunks keep their authored
	# dynamic materials untouched until they explicitly opt in.
	if preview_chunk in PROCEDURAL_OCCLUSION_CHUNKS:
		_ensure_occlusion_manager()
	if _occlusion_mgr != null and _active_chunk != null and preview_chunk in PROCEDURAL_OCCLUSION_CHUNKS:
		var chunk_wrapped: int = _occlusion_mgr.apply_to(_active_chunk, 2.0)
		_pdbg("camera occlusion applied to %d chunk surfaces" % chunk_wrapped)
	_pdbg("load_environment_model")
	_load_environment_model()
	_maybe_install_chunk_coord_map()
	_pdbg("connect_outline_feedback")
	_connect_outline_feedback_sources(self)
	_connect_push_targets(self)
	_apply_chunk_runtime_preset()
	if _active_chunk != null and _active_chunk.has_method("reset_preview_state"):
		_pdbg("reset_preview_state")
		_active_chunk.call("reset_preview_state")
	# Runtime reset is allowed to restore authored StandardMaterial overrides. Re-scan afterward so
	# those restored tall surfaces receive the same see-through wrapper as initial construction.
	# apply_to() skips already wrapped ShaderMaterials, making this refresh idempotent.
	if _occlusion_mgr != null and _active_chunk != null and preview_chunk in PROCEDURAL_OCCLUSION_CHUNKS:
		var refreshed_wrappers: int = _occlusion_mgr.apply_to(_active_chunk, 2.0)
		_pdbg("camera occlusion refreshed on %d reset surfaces" % refreshed_wrappers)
	_apply_chunk_ui_defaults()
	# Optional cosmetic contract: a chunk may annotate paused queued paths (for example, learned surge
	# timing). Rebinding every load/reset also clears cached feedback from the previous fragment.
	if _path_render_manager != null:
		_path_render_manager.set_path_feedback_source(_active_chunk)
	if _active_chunk != null and _active_chunk.has_method("set_preview_planning_feedback"):
		_active_chunk.call("set_preview_planning_feedback", _scheduler != null and _scheduler.is_paused())
	_pdbg("apply_chunk_navigation_graph")
	_apply_chunk_navigation_graph()
	if _active_chunk != null and _active_chunk.has_method("on_game_state_grid_ready"):
		_active_chunk.call("on_game_state_grid_ready")
	_apply_chunk_metadata()
	_pdbg("position_party_for_chunk")
	_position_party_for_chunk()
	_apply_chunk_party_presence()
	# Dodge defaults to the chunk's declaration (off unless a chunk unlocks it). Toggle live with G.
	if _active_chunk != null and _active_chunk.has_method("preview_dodge_unlocked"):
		_preview_dodge_unlocked = bool(_active_chunk.call("preview_dodge_unlocked"))
	_apply_dodge_setting()
	_select_character(_default_chunk_character())
	# Camera profiles depend on the final rendered spawn + selected follow target. Apply and snap only
	# after both are established, so a stacked level never eases through a neighbouring floor on entry.
	_configure_preview_camera_feedback()
	# Per-entry overlay defaults: a config `"overlays": {"peris": true}` boots the view with that
	# perception layer on (fog for generated districts). Applied once per ENTRY — F1-F3 / the panel
	# buttons toggle live, and an N-regenerate keeps the player's current choice.
	if not _overlays_config_applied:
		_overlays_config_applied = true
		var overlay_defaults: Dictionary = preview_chunk_config.get("overlays", {})
		for ov_id in overlay_defaults.keys():
			headless_set_overlay_state(str(ov_id), bool(overlay_defaults[ov_id]))
	_refresh_preview_items()
	_refresh_inventory_panel()
	_tutorial_prompt.show_action_prompt("command", "Move", 0.0, "RMB")
	if bool(preview_chunk_config.get("preserve_party_state", false)):
		show_preview_message("Next stretch loaded — carried resources and party losses persist.", 2.0)
	else:
		show_preview_message("Preview booted with full HP, stamina, and ATP.", 2.0)

## Optional presentation contract for authored showcase-like chunks. It lets a scene protect its
## first read from the diagnostic chrome while preserving H/F4 as explicit inspection controls.
func _apply_chunk_ui_defaults() -> void:
	if _active_chunk == null or not _active_chunk.has_method("get_preview_ui_defaults"):
		return
	var defaults: Dictionary = _active_chunk.call("get_preview_ui_defaults")
	if _instructions_margin != null and defaults.has("instructions_visible"):
		_instructions_margin.visible = bool(defaults.get("instructions_visible", true))
	if defaults.has("overlay_collapsed"):
		_set_overlay_panel_collapsed(bool(defaults.get("overlay_collapsed", false)))

## N in a GENERATION preview (a chunk answering is_generation_preview): bump the seed and rebuild the
## layout in place — the roguelike regenerate flow (_roguelike_choose), so all nav/party/outline wiring
## re-runs against the fresh variation. Inert for any other chunk.
func _regenerate_preview_variation() -> void:
	if _active_chunk == null or not _active_chunk.has_method("is_generation_preview"):
		return
	var current_seed := int(preview_chunk_config.get("seed", 0))
	if not preview_chunk_config.has("seed") and _active_chunk.has_method("get_generation_seed"):
		current_seed = int(_active_chunk.call("get_generation_seed"))
	var next_seed := current_seed + 1
	preview_chunk_config = preview_chunk_config.duplicate()
	preview_chunk_config["seed"] = next_seed
	# The seed override already drives generation, but the authored settings title/id
	# and picker entry also need to advance. Otherwise the world is seed N+1 while the
	# header and restart contract continue claiming seed N.
	var generation_settings: Dictionary = preview_chunk_config.get("settings", {}).duplicate(true)
	if not generation_settings.is_empty():
		var case_id := str(preview_chunk_config.get("seed_case_id", "custom"))
		if case_id == "custom":
			var tier := str(generation_settings.get("complexity_tier", "teaching"))
			var stage := int(generation_settings.get("progression_stage", -1))
			generation_settings = StretchSeedCatalogScript.custom_settings(next_seed, tier, stage)
		else:
			var case_settings := StretchSeedCatalogScript.settings_for_case(case_id, next_seed)
			if not case_settings.is_empty():
				generation_settings = case_settings
		preview_chunk_config["settings"] = generation_settings
		var case_status := str(preview_chunk_config.get("seed_case_status", "custom"))
		scene_title_override = "%s  [seed %d, %s]" % [
			str(generation_settings.get("title", "Generated Stretch")), next_seed, case_status
		]
		if not _active_preview_entry.is_empty():
			_active_preview_entry["title"] = scene_title_override
			_active_preview_entry["config"] = preview_chunk_config.duplicate(true)
	_unload_chunk(preview_chunk)
	_preview_interactables.clear()
	_begin_chunk()
	show_preview_message("Regenerated — seed %d" % next_seed, 1.8)


func _unload_chunk(chunk_name: String) -> void:
	cancel_preview_emphasis()
	var unloading_active: bool = _active_chunk != null and _chunks.get(chunk_name) == _active_chunk
	if unloading_active:
		_cancel_preview_runtime_callbacks()
		_preview_runtime_initialized = false
		# A coord map is part of the active chunk's spatial contract, not persistent run
		# state. Retire it with the geometry so a flat successor cannot inherit a helix.
		if _game_state != null:
			_game_state.coord_map = null
		if _path_render_manager != null:
			_path_render_manager.set_path_feedback_source(null)
		_active_chunk = null
	super._unload_chunk(chunk_name)

# If the chunk names an environment GLB (a modeled backdrop), instantiate it under the scene and force
# NEAREST texture filtering so the pixel-art tiles stay crisp. The gameplay data layer is unchanged —
# the model is the visual the chunk's coordinate transform (e.g. ChannelsArc) maps the gauntlet onto.
func _load_environment_model() -> void:
	if _active_chunk == null or not _active_chunk.has_method("get_environment_model"):
		return
	var path := String(_active_chunk.call("get_environment_model"))
	if path == "":
		return
	# LOUD on a missing/unloadable model: without it the coord_map never installs, so a warped scene (the
	# channels helix) silently falls back to its FLAT graybox — which is confusing AND, for a chunk whose
	# geometry is authored pre-warped (wash_relay's branches), leaves it mismatched. Re-import if you see this.
	if not ResourceLoader.exists(path):
		push_warning("fragment_preview: environment model NOT FOUND (%s) — scene stays FLAT (no coord_map). Re-import the project." % path)
		show_preview_message("Environment model missing (%s) — scene is FLAT. Re-import." % path.get_file(), 8.0)
		return
	var packed = load(path)
	if packed == null:
		push_warning("fragment_preview: environment model failed to LOAD (%s) — scene stays FLAT (no coord_map)." % path)
		return
	var model: Node3D = packed.instantiate()
	model.name = "EnvironmentModel"
	add_child(model)
	_pdbg("model added: %s" % path)
	_force_nearest_filter(model)
	_add_deck_collision(model)
	_pdbg("deck collision added")
	# See-through level: wrap the model's meshes so geometry that comes between the camera and the active
	# character dither-dissolves around them (you never lose the party behind a wall / an upper helix loop).
	_ensure_occlusion_manager()
	var wrapped: int = _occlusion_mgr.apply_to(model)
	_pdbg("camera occlusion applied to %d surfaces" % wrapped)
	# If the chunk maps its flat gauntlet onto this model (the channels helix), install the coord_map so
	# node followers + clicks run through it, and hide the now-redundant flat graybox.
	if _active_chunk.has_method("get_coord_map") and _game_state != null:
		_game_state.coord_map = _active_chunk.call("get_coord_map")
		_pdbg("coord_map installed")
		if _active_chunk.has_method("hide_flat_graybox"):
			_active_chunk.call("hide_flat_graybox")
			_pdbg("flat graybox hidden")
		# The data layer is flat but the world is warped — move the interactable zones onto the helix
		# so they overlap the warped character bodies (otherwise the hold-dwell could never arm).
		if _active_chunk.has_method("warp_interactables_onto_coord_map"):
			_active_chunk.call("warp_interactables_onto_coord_map", _game_state.coord_map)
			_pdbg("interactables warped onto coord_map")
		# Generate ground collision DIRECTLY from the chunk's walkable_regions, warped onto the deck. The GLB's
		# set-piece decks + the chunk's straight collision planks don't match the declared walkable footprint
		# (narrow set-pieces, chord-vs-curve branch boxes), so ~30% of walkable cells had no deck to ray-hit and
		# were un-clickable. This makes collision == walkable by construction for ANY coord_map chunk.
		_add_warped_walkable_collision()

func _ensure_occlusion_manager() -> void:
	if _occlusion_mgr == null or not is_instance_valid(_occlusion_mgr):
		_occlusion_mgr = CameraOcclusionManager.new()
		add_child(_occlusion_mgr)
	_occlusion_mgr.set_watch(_game_state, _active_char_id)

## A chunk can WARP its OWN procedural geometry (the generated stretch builds its tiled floor + node dressing
## pre-warped onto a helix) and expose a coord_map WITHOUT an environment GLB. Install it so character render +
## the click inverse run through the same warp the geometry used. The GLB path above already installs one for a
## modeled scene (guarded here so we never double-install); and because the chunk warps its own interactable
## zones at build, we deliberately do NOT call warp_interactables_onto_coord_map (that would double-warp them).
func _maybe_install_chunk_coord_map() -> void:
	if _game_state == null or _game_state.coord_map != null:
		return
	if _active_chunk == null or not _active_chunk.has_method("get_coord_map"):
		return
	var cm = _active_chunk.call("get_coord_map")
	if cm == null:
		return
	_game_state.coord_map = cm
	_pdbg("chunk coord_map installed (self-warped chunk, no env model)")

## Walkable surfaces of the environment model get trimesh collision on layer 1 (the ground layer the
## player ray queries), so a click lands on the deck under the cursor — its world height is what
## ChannelsCoordMap.to_data reads back to a flat (s, lane) target. Walls/glows/props are skipped so the
## ray doesn't catch a gate or spout instead of the floor.
const _DECK_NAME_HINTS := ["deck", "apin", "apout", "near", "far", "span", "cat", "floor", "entry",
	"exit", "stair", "conn", "well", "overlook", "ch"]
func _add_deck_collision(node: Node) -> void:
	if node is MeshInstance3D:
		var nm := String(node.name).to_lower()
		for hint in _DECK_NAME_HINTS:
			if nm.contains(hint):
				(node as MeshInstance3D).create_trimesh_collision()
				break
	for c in node.get_children():
		_add_deck_collision(c)

## Build ground collision (layer 1) from the active chunk's DECLARED walkable_regions, warped onto the deck via
## the coord_map — so a click/hover ray finds deck under EVERY walkable cell, regardless of where the model's
## set-piece meshes or the chunk's straight collision planks happen to sit. Each region is tiled into thin boxes
## ALONG the curve (re-warped per segment so the box tangent tracks the local arc, no chord gaps), sized from
## the region rect so collision-extent == walkable-extent. Collision-only (no mesh); derived, rebuilt on load.
const _WARP_COLL_SEG_S := 1.2     # flat-s per collision segment (fine enough the chord error stays under a cell)
const _WARP_COLL_THICK := 0.4
func _add_warped_walkable_collision() -> void:
	if _game_state == null or _game_state.coord_map == null or _active_chunk == null:
		return
	if not _active_chunk.has_method("get_grid_data"):
		return
	var data: Dictionary = _active_chunk.call("get_grid_data")
	var regions: Array = data.get("walkable_regions", [])
	if regions.is_empty():
		return
	var cm = _game_state.coord_map
	# The grid rasterizes a region to every cell it OVERLAPS, so walkable cell CENTRES extend ~half a cell past
	# the region rect — pad the collision by half a cell on every side so those edge cells get deck too.
	var cell_pad: float = float(data.get("cell_size", 1.0)) * 0.5
	var root := Node3D.new()
	root.name = "WarpedWalkCollision"
	add_child(root)
	var boxes := 0
	for region in regions:
		var mn: Array = region["min"]
		var mx: Array = region["max"]
		var s0: float = float(mn[0]) - cell_pad; var lane0: float = float(mn[1]) - cell_pad
		var s1: float = float(mx[0]) + cell_pad; var lane1: float = float(mx[1]) + cell_pad
		var lane_c := (lane0 + lane1) * 0.5
		var lane_span: float = absf(lane1 - lane0)
		var s_span: float = absf(s1 - s0)
		var nseg: int = maxi(1, int(ceil(s_span / _WARP_COLL_SEG_S)))
		var ds := s_span / float(nseg)
		for k in range(nseg):
			var sc: float = lerpf(s0, s1, (k + 0.5) / float(nseg))
			var center = cm.to_world(Vector3(sc, 0.0, lane_c))
			var p0 = cm.to_world(Vector3(sc - ds * 0.5, 0.0, lane_c))
			var p1 = cm.to_world(Vector3(sc + ds * 0.5, 0.0, lane_c))
			if not (center is Vector3 and (center as Vector3).is_finite() and p0 is Vector3 and p1 is Vector3):
				continue
			var basis := Basis.IDENTITY
			if cm.has_method("to_basis"):
				var b = cm.to_basis(Vector3(sc, 0.0, lane_c))
				if b is Basis:
					basis = b
			var seg_len: float = (p1 as Vector3).distance_to(p0 as Vector3) * 1.4 + 0.2   # overlap so segments never gap
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(lane_span + 0.3, _WARP_COLL_THICK, seg_len)
			col.shape = shape
			body.add_child(col)
			root.add_child(body)
			body.global_transform = Transform3D(basis, center as Vector3)
			boxes += 1
	_pdbg("warped walkable collision: %d boxes over %d regions" % [boxes, regions.size()])

func _force_nearest_filter(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			for i in range(mesh.get_surface_count()):
				var m := mi.get_active_material(i)
				if m is BaseMaterial3D:
					# NEAREST WITH mipmaps: crisp pixel-art tiles up close, but distant
					# grazing-angle geometry averages instead of sparkling — plain NEAREST
					# keeps every far tile motif hard white, so upstream walkway decks
					# read as rows of floating dashes across the void.
					(m as BaseMaterial3D).texture_filter = \
						BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	for c in node.get_children():
		_force_nearest_filter(c)

# --- Fragment picker (replaces the per-chunk *_preview.tscn files) ---

## Read a `--preview=<id>` (or `--preview <id>`) user arg, if present.
func _cli_preview_id() -> String:
	var cli: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(cli.size()):
		var a := String(cli[i])
		if a.begins_with("--preview="):
			return a.substr("--preview=".length())
		if a == "--preview" and i + 1 < cli.size():
			return String(cli[i + 1])
	return ""

## Point the preview at a menu entry (chunk + title + config) before loading it.
func _apply_preview_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	_active_preview_entry = entry.duplicate(true)
	_active_preview_entry_id = String(entry.get("id", ""))
	preview_chunk = String(entry.get("chunk", preview_chunk))
	scene_title_override = String(entry.get("title", scene_title_override))
	preview_chunk_config = (entry.get("config", {}) as Dictionary).duplicate(true)
	_overlays_config_applied = false   # a fresh entry re-applies its overlay defaults
	# Roguelike entry: start a RunSession and point the chunk config at its opening level.
	if bool(preview_chunk_config.get("roguelike", false)):
		_roguelike_active = true
		_run_session = RunSession.new(int(preview_chunk_config.get("seed", 1)),
			str(preview_chunk_config.get("levels", RunSession.LEVELS_STRETCH)))
		_run_session.start()
		_roguelike_sync_config()

## PauseMenu calls this immediately before reloading the scene. Preserve the selected picker
## entry across that reload so "Restart Scene" restarts the active fragment instead of silently
## dropping the player back at the picker. The M action remains the explicit fragment-menu route.
func prepare_scene_restart() -> void:
	if not _active_preview_entry.is_empty() and get_preview_entry(_active_preview_entry_id).is_empty():
		menu_launch_entry = _active_preview_entry.duplicate(true)
		return
	if _active_preview_entry_id != "":
		menu_launch_id = _active_preview_entry_id
		return
	for entry in PREVIEW_ENTRIES:
		if String(entry.get("chunk", "")) == preview_chunk:
			menu_launch_id = String(entry.get("id", ""))
			return

## Hosted chunks may request a continuation while running in the normal picker-backed
## preview. Wait for their final narrative line, then reload the whole preview scene so
## chunk-scoped shelters, scheduler callbacks, models, collision, and coord maps cannot
## leak into the next fragment. Direct/CLI previews and campaign hosts do not chain.
func request_preview_handoff(entry_id: String) -> void:
	if not preview_menu or _pending_preview_handoff_id != "":
		return
	if get_preview_entry(entry_id).is_empty():
		push_warning("fragment_preview: unknown handoff entry '%s'" % entry_id)
		return
	_pending_preview_handoff_id = entry_id
	if _dialogue != null and _dialogue.is_active():
		_dialogue.dialogue_finished.connect(_defer_pending_preview_handoff, CONNECT_ONE_SHOT)
	else:
		call_deferred("_commit_pending_preview_handoff")

func _defer_pending_preview_handoff() -> void:
	call_deferred("_commit_pending_preview_handoff")

func _commit_pending_preview_handoff() -> void:
	if not preview_menu or _pending_preview_handoff_id == "":
		_pending_preview_handoff_id = ""
		return
	var entry_id := _pending_preview_handoff_id
	_pending_preview_handoff_id = ""
	menu_launch_id = entry_id
	var reload_error := get_tree().reload_current_scene()
	if reload_error != OK:
		menu_launch_id = ""
		push_error("fragment_preview: failed to hand off to '%s' (%s)" % [entry_id, error_string(reload_error)])

## Point the chunk config at the session's current level (or warn if generation failed).
func _roguelike_sync_config() -> void:
	if _run_session == null or not bool(_run_session.spec.get("success", false)):
		show_preview_message("Roguelike generation failed.", 6.0)
		return
	if str(_run_session.spec.get("kind", "")) == "atom":
		# Atom-chain level: the chunk regenerates the SAME graded skeleton from (stages, seed) and lays it
		# on the run's hub shape — the report card the session already checked is the level's provenance.
		preview_chunk = "puzzle_atom"
		# THE DESCENT'S INTERMEDIATE ZONES (ARCHITECTURE_DESIGN.md §4.18-4.24 as playable scenery):
		# each depth dresses its level as the district band the run is passing through — the
		# commerce strip first, then the clerical blocks, the supply belt, the infill wards, the
		# collectives — with decay rising as the run goes down.
		var zone_idioms: Array = ["capitalist", "institutional", "industrial", "mixed", "socialist"]
		var zone_names: Array = ["the commerce strip", "the clerical blocks", "the supply belt",
			"the infill wards", "the collectives"]
		var zone_i: int = mini(_run_session.depth, zone_idioms.size() - 1)
		preview_chunk_config = {
			"stages": (_run_session.spec.get("stages", []) as Array).duplicate(),
			"seed": int(_run_session.spec.get("seed", 0)),
			"hub_shape": (_run_session.spec.get("hub_shape", {}) as Dictionary).duplicate(true),
			"roguelike": true,
			"district": {"idiom": str(zone_idioms[zone_i]),
				"decay": clampf(float(_run_session.depth) * 0.12, 0.0, 0.6)},
		}
		scene_title_override = "Roguelike — Depth %d (%d gates, %s)" % [_run_session.depth + 1,
			(_run_session.spec.get("stages", []) as Array).size(), str(zone_names[zone_i])]
		return
	if str(_run_session.spec.get("kind", "")) == RunSession.LEVEL_CHASE:
		# The run's dealt CHASE: the authored lockout corridor. Its failure economy is the
		# checkpoint runback, so the permadeath wire skips it (see _roguelike_on_downed).
		preview_chunk = "lockout_chase"
		preview_chunk_config = {"roguelike": true}
		scene_title_override = "Roguelike — Depth %d: LOCKOUT" % (_run_session.depth + 1)
		return
	if str(_run_session.spec.get("kind", "")) == RunSession.FINALE_PARANUCLEUS:
		# THE FINALE: the boss site. The run completes when the prize is taken (the poll watches).
		preview_chunk = "boss_showcase"
		preview_chunk_config = {"seed": int(_run_session.spec.get("seed", 0)), "finale": true,
			"roguelike": true, "overlays": {"aster": false, "peris": false, "endo": false}}
		scene_title_override = "Roguelike — THE SITE (depth %d): take the dose" % (_run_session.depth + 1)
		return
	preview_chunk = "generated_stretch"
	preview_chunk_config = {
		"spec": _run_session.spec,
		"roguelike": true,
		# Depth zero establishes the run fixture. Every later stretch inherits the
		# same authoritative party stats so losses and ATP decisions remain real.
		"preserve_party_state": _run_session.depth > 0,
	}
	var tier := str(_run_session.spec.get("source", {}).get("complexity_tier", "teaching"))
	scene_title_override = "Roguelike — Depth %d (%s)" % [_run_session.depth + 1, tier]

## Move the party to the freshly-loaded level's spawn anchors (the data layer is the authority).
func _roguelike_respawn_party() -> void:
	if _active_chunk == null or not _active_chunk.has_method("get_spawn_positions") or _game_state == null:
		return
	var spawns: Dictionary = _active_chunk.call("get_spawn_positions")
	for cid in spawns.keys():
		if _game_state.characters.has(cid):
			_game_state.snap_character_to(cid, spawns[cid], false)

func _apply_photo_mode(active: bool) -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.visible = not active
	if _preview_layer != null and is_instance_valid(_preview_layer):
		_preview_layer.visible = not active
	_sync_overlay_stack()

func _web_e2e_context() -> Dictionary:
	return {
		"game_state": _game_state,
		"characters": _characters,
		"active_chunk": _active_chunk,
		"preview_interactables": _preview_interactables,
		"camera": _camera,
		"active_preview_entry_id": _active_preview_entry_id,
		"preview_chunk": preview_chunk,
		"active_char_id": _active_char_id,
		"selected_char_ids": _selected_char_ids,
		"scheduler": _scheduler,
		"anchor_positions": headless_get_anchor_positions(),
		"consequence_presentation_controller": _consequence_presentation_controller,
	}


func _process(delta: float) -> void:
	super._process(delta)
	_sync_preview_character_holds()
	_roguelike_poll()
	if _web_e2e_controller != null:
		_web_e2e_controller.update(delta)



## A chunk may report positional work without the shared HUD knowing any level-specific details. The
## same portrait badge also falls back to a carried item, matching the rally rule: click the visible
## holder badge to leave that character in place while the rest of the party rallies.
func _sync_preview_character_holds() -> void:
	if (_hud == null or not is_instance_valid(_hud)
			or not _hud.has_method("set_portrait_hold_state") or not _hud.has_method("get_portrait_ids")):
		return
	var holds: Dictionary = {}
	if (_active_chunk != null and is_instance_valid(_active_chunk)
			and _active_chunk.has_method("get_preview_character_holds")):
		var reported = _active_chunk.call("get_preview_character_holds")
		if reported is Dictionary:
			holds = reported
	for raw_id in _hud.get_portrait_ids():
		var char_id := str(raw_id)
		var info = holds.get(char_id, {})
		if not (info is Dictionary) or (info as Dictionary).is_empty():
			info = _preview_carried_item_hold(char_id)
		_hud.call("set_portrait_hold_state", char_id, info if info is Dictionary else {})

func _preview_carried_item_hold(char_id: String) -> Dictionary:
	return _party_item_controller.get_hold_receipt(char_id) \
		if is_instance_valid(_party_item_controller) else {}

## When the roguelike party rests at the exit shelter, present the run's next branch CHOICE (the meta-decision).
func _roguelike_poll() -> void:
	if not _roguelike_active or _roguelike_advancing or _active_chunk == null:
		return
	if not _active_chunk.has_method("get_preview_state"):
		return
	_roguelike_wire_permadeath()   # idempotent; covers the run's FIRST level (loads outside _roguelike_choose)
	var st: Dictionary = _active_chunk.call("get_preview_state")
	if bool(st.get("prize_retrieved", false)) and not _run_session.completed:
		# THE GOAL: the prize is taken — the run is complete. Show the report card.
		_roguelike_advancing = true
		_run_session.retrieve()
		_show_run_summary()
		return
	if _run_session.run_over:
		_roguelike_advancing = true
		_show_run_summary()
		return
	if bool(st.get("shelter_rested", false)):
		_roguelike_advancing = true   # latched until the player picks a branch
		_roguelike_present_branch()

## Build a branch decision for the next descent and show the choice modal.
func _roguelike_present_branch() -> void:
	if _run_session == null:
		return
	_show_branch_modal(_run_session.branch())

## The player picked a branch: the session applies its reward + generates the next level; reload + respawn here.
func _roguelike_choose(option: Dictionary) -> void:
	_close_branch_modal()
	if _run_session == null:
		return
	# Keep the outgoing id before the session advances. _roguelike_sync_config() points
	# preview_chunk at the NEXT level; unloading after that call by the new id leaves the
	# old generated floor, collision, and coord map alive beneath its successor.
	var outgoing_chunk := preview_chunk
	if bool(option.get("summary_new_run", false)):
		# a fresh run on the next seed: new descent, new target depth, full roster
		_clear_roguelike_inventory()
		_run_session = RunSession.new(_run_session.seed + 1, _run_session.levels)
		_run_session.start()
		_roguelike_sync_config()
		_unload_chunk(outgoing_chunk)
		_preview_interactables.clear()
		_begin_chunk()
		_roguelike_respawn_party()
		_roguelike_wire_permadeath()
		_roguelike_advancing = false
		return
	var reward: Dictionary = option.get("reward", {})
	var candidate_spec: Dictionary = _run_session.choose(option)
	if not bool(candidate_spec.get("success", false)):
		# RunSession rejects failed generation transactionally, so the current
		# shelter and level remain authoritative. Make that refusal visible and
		# return the player to the same real branch choice instead of unloading
		# the world into a failed spec.
		show_preview_message(
			"That route failed to form. Choose another path.", 6.0)
		_roguelike_advancing = false
		call_deferred("_roguelike_present_branch")
		return
	if reward.has("recruit"):
		show_preview_message("%s joins the run." % RunBranchDecisions.display_name(str(reward["recruit"])), 3.5)
	_roguelike_sync_config()
	if _active_chunk != null and _active_chunk.has_method("preserve_carried_resources_on_detach"):
		_active_chunk.call("preserve_carried_resources_on_detach")
	_unload_chunk(outgoing_chunk)
	# The unloaded chunk's interactables are queue_free'd; drop them from the preview's caches so the speed-recipient
	# list (and the active-character push) never touch a freed node. _begin_chunk repopulates from the new chunk.
	_preview_interactables.clear()
	_begin_chunk()
	_roguelike_respawn_party()
	_roguelike_wire_permadeath()
	if reward.has("gear"):
		show_preview_message("Salvaged: %s." % str(reward["gear"]).capitalize(), 3.0)
	_roguelike_advancing = false


## Carried resources cross ordinary descents, but ownership ends with the run.
## Clear authoritative inventory before a summary-driven new run so an item first
## claimed several chunks ago cannot escape the current chunk's cleanup ledger.
func _clear_roguelike_inventory() -> void:
	if is_instance_valid(_party_item_controller):
		_party_item_controller.clear_items()

## PERMADEATH (the DLC doc's law): in a roguelike run a fallen character leaves the run — the
## session shrinks the roster (every deeper level regenerates for the smaller party) and an empty
## roster ends the run. Reconnected after every level load (the game state persists across loads).
func _roguelike_wire_permadeath() -> void:
	if _game_state == null or _run_session == null:
		return
	if not _game_state.character_downed.is_connected(_roguelike_on_downed):
		_game_state.character_downed.connect(_roguelike_on_downed)

func _roguelike_on_downed(id: String) -> void:
	if _run_session == null or not _roguelike_active:
		return
	if str(preview_chunk) == "lockout_chase":
		return   # a chase death costs a checkpoint runback, not the roster -- the corridor revives its pair
	if not _run_session.roster.has(str(id)):
		return
	_run_session.mark_death(str(id))
	show_preview_message("%s is gone. The run remembers." % RunBranchDecisions.display_name(str(id)), 4.5)

## The run's REPORT CARD: shown on retrieval (complete) or wipe (over). One button starts a fresh
## run on the next seed; rides the same modal plumbing as the branch choice.
func _show_run_summary() -> void:
	if _run_session == null:
		return
	var sm: Dictionary = _run_session.summary()
	var verdict := "THE DOSE IS OUT" if bool(sm.get("completed", false)) else "THE RUN IS LOST"
	var lines: Array = []
	lines.append("Depth %d of %d" % [int(sm.get("depth", 0)), int(sm.get("target_depth", 0))])
	lines.append("Survivors: %s" % (", ".join(sm.get("survivors", [])) if not (sm.get("survivors", []) as Array).is_empty() else "none"))
	if not (sm.get("deaths", []) as Array).is_empty():
		lines.append("Lost: %s" % ", ".join(sm.get("deaths", [])))
	lines.append("Branches chosen: %d" % int(sm.get("choices", 0)))
	_show_branch_modal({
		"prompt": "%s\n%s" % [verdict, "\n".join(lines)],
		"options": [{"id": "new_run", "label": "NEW RUN", "risk": "",
			"reward": {}, "summary_new_run": true}],
	})

## A modal showing the branch prompt + one button per option (label, risk, and the tradeoff). Picking calls
## _roguelike_choose. Built on the same UI layer as the fragment picker.
func _show_branch_modal(decision: Dictionary) -> void:
	_close_branch_modal()
	if _preview_layer == null:
		return
	var backdrop := _preview_layer.get_node("BranchBackdrop") as ColorRect
	var panel := _preview_layer.get_node("BranchModal") as PanelContainer
	var prompt := panel.get_node("Margin/Content/Prompt") as Label
	prompt.text = str(decision.get("prompt", "The route forks."))
	var sub := panel.get_node("Margin/Content/Subtitle") as Label
	sub.text = "Choose your descent — Depth %d" % ((_run_session.depth if _run_session != null else 0) + 2)
	var row := panel.get_node("Margin/Content/Options") as HBoxContainer
	for opt in decision.get("options", []):
		var o: Dictionary = opt
		var b := BranchOptionButtonScene.instantiate() as Button
		b.text = "%s\n[%s RISK]\n\n%s" % [str(o.get("label", "?")), str(o.get("risk", "")).to_upper(), str(o.get("desc", ""))]
		b.pressed.connect(_roguelike_choose.bind(o))
		row.add_child(b)
	backdrop.visible = true
	panel.visible = true
	_branch_modal = panel

func _close_branch_modal() -> void:
	if _branch_modal != null and is_instance_valid(_branch_modal):
		_branch_modal.visible = false
		var options := _branch_modal.get_node("Margin/Content/Options") as HBoxContainer
		for child in options.get_children():
			options.remove_child(child)
			child.queue_free()
		var backdrop := _preview_layer.get_node_or_null("BranchBackdrop") as ColorRect
		if backdrop != null:
			backdrop.visible = false
	_branch_modal = null

## Build and show the picker: one button per PREVIEW_ENTRIES row. Selecting one loads that fragment.
func _show_fragment_menu() -> void:
	_in_menu = true
	if _menu_panel == null:
		_build_fragment_menu()
	if _menu_backdrop != null:
		_menu_backdrop.visible = true
	_menu_panel.visible = true
	if _hud != null:
		_hud.visible = false   # the gameplay HUD belongs to a loaded chunk, not the picker

func _build_fragment_menu() -> void:
	if _preview_layer == null:
		return
	_menu_backdrop = _preview_layer.get_node("FragmentMenuBackdrop") as ColorRect
	_menu_panel = _preview_layer.get_node("FragmentMenu") as PanelContainer
	var reload_glyph := _menu_panel.get_node("Margin/Content/Subtitle/ReloadGlyph") as InputGlyph
	reload_glyph.configure_action("preview_reload", "M")
	_build_seed_lab_controls()
	# A wrapping grid instead of one tall column, so the list fits on screen. Columns scale with the
	# entry count (~sqrt), capped so each cell stays wide enough for the longest title.
	var grid := _menu_panel.get_node("Margin/Content/EntryGrid") as GridContainer
	grid.columns = clampi(int(ceil(sqrt(float(PREVIEW_ENTRIES.size())))), 2, 3)
	# Display NEWEST-first: PREVIEW_ENTRIES stays in canonical (append) order for the data/tests, but the
	# picker shows it reversed, so a freshly-added fragment (appended to the list) lands at the top here.
	var ordered := PREVIEW_ENTRIES.duplicate()
	ordered.reverse()
	for entry in ordered:
		var button := FragmentMenuButtonScene.instantiate() as Button
		button.text = String(entry.get("title", entry.get("id", "?")))
		button.pressed.connect(_on_menu_entry_pressed.bind(entry))
		grid.add_child(button)

func _build_seed_lab_controls() -> void:
	_seed_case_selector = _menu_panel.get_node("Margin/Content/SeedRow/CaseSelector") as OptionButton
	_seed_case_selector.add_item("Custom profile")
	var catalog: Dictionary = StretchSeedCatalogScript.load_catalog()
	_seed_cases = StretchSeedCatalogScript.cases(catalog)
	for case_def in _seed_cases:
		_seed_case_selector.add_item(StretchSeedCatalogScript.display_name(case_def))
	_seed_case_selector.item_selected.connect(_on_seed_case_selected)
	_seed_value_edit = _menu_panel.get_node("Margin/Content/SeedRow/SeedEdit") as LineEdit
	_seed_value_edit.text_submitted.connect(func(_value: String) -> void: _on_seed_play_pressed())
	_seed_tier_selector = _menu_panel.get_node("Margin/Content/SeedRow/TierSelector") as OptionButton
	for tier in StretchSeedCatalogScript.VALID_TIERS:
		_seed_tier_selector.add_item(str(tier))
	var play_button := _menu_panel.get_node("Margin/Content/SeedRow/PlayButton") as Button
	play_button.pressed.connect(_on_seed_play_pressed)
	_seed_case_note = _menu_panel.get_node("Margin/Content/SeedNote") as Label
	var validation: Dictionary = catalog.get("validation", {})
	if not bool(validation.get("valid", false)):
		_seed_case_note.text = "Seed corpus error: %s" % ", ".join(validation.get("errors", []))
		_seed_case_note.modulate = Color(1.0, 0.42, 0.38)

func _on_seed_case_selected(index: int) -> void:
	if index <= 0 or index - 1 >= _seed_cases.size():
		_seed_tier_selector.disabled = false
		_seed_case_note.text = "Custom profile uses the selected tier; enter any integer seed."
		return
	var case_def: Dictionary = _seed_cases[index - 1]
	_seed_tier_selector.disabled = true
	_seed_value_edit.text = str(int(case_def.get("seed", 1)))
	var settings: Dictionary = case_def.get("settings", {})
	var tier := str(settings.get("complexity_tier", "teaching"))
	for tier_index in range(_seed_tier_selector.item_count):
		if _seed_tier_selector.get_item_text(tier_index) == tier:
			_seed_tier_selector.select(tier_index)
			break
	_seed_case_note.text = "%s: %s" % [
		str(case_def.get("status", "candidate")).to_upper(),
		str(case_def.get("purpose", "")),
	]

func _on_seed_play_pressed() -> void:
	var seed_text := _seed_value_edit.text.strip_edges()
	if not seed_text.is_valid_int():
		_seed_case_note.text = "Seed must be a whole number."
		_seed_case_note.modulate = Color(1.0, 0.42, 0.38)
		return
	var seed := int(seed_text)
	var settings := {}
	var case_id := "custom"
	var case_status := "custom"
	if _seed_case_selector.selected > 0 and _seed_case_selector.selected - 1 < _seed_cases.size():
		var case_def: Dictionary = _seed_cases[_seed_case_selector.selected - 1]
		case_id = str(case_def.get("id", "custom"))
		case_status = str(case_def.get("status", "candidate"))
		settings = StretchSeedCatalogScript.settings_for_case(case_id, seed)
	else:
		var tier := _seed_tier_selector.get_item_text(_seed_tier_selector.selected)
		settings = StretchSeedCatalogScript.custom_settings(seed, tier)
	if settings.is_empty():
		_seed_case_note.text = "Could not build generator settings for this seed case."
		_seed_case_note.modulate = Color(1.0, 0.42, 0.38)
		return
	var chunk_config := StretchSeedCatalogScript.play_config_for_case(case_id)
	chunk_config.merge({
		"settings": settings,
		"seed": seed,
		"seed_case_id": case_id,
		"seed_case_status": case_status,
	}, true)
	var entry := {
		"id": "generated_seed_lab_%s" % case_id,
		"chunk": "generated_stretch",
		"title": "%s  [seed %d, %s]" % [str(settings.get("title", "Generated Stretch")), seed, case_status],
		"stage": int(settings.get("progression_stage", 2)),
		"config": chunk_config,
	}
	_apply_preview_entry(entry)
	_begin_chunk()

func _on_menu_entry_pressed(entry: Dictionary) -> void:
	_apply_preview_entry(entry)
	_begin_chunk()

func _configure_loaded_chunk(chunk: Node3D, chunk_name: String) -> void:
	if chunk_name != preview_chunk:
		return
	if chunk != null and chunk.has_method("configure_chunk"):
		# Game modes are Settings configurations projected onto a chunk at load time.
		# The authored preview config merges last so a focused QA case can explicitly
		# override the player's persisted mode without changing the level spec/seed.
		var resolved_config: Dictionary = {}
		var settings := get_tree().root.get_node_or_null("Settings")
		if settings != null and settings.has_method("chunk_config_overrides"):
			var overrides: Variant = settings.call("chunk_config_overrides", chunk_name)
			if overrides is Dictionary:
				resolved_config = (overrides as Dictionary).duplicate(true)
		resolved_config.merge(preview_chunk_config, true)
		chunk.call("configure_chunk", resolved_config)

## Wire every PushTarget in the scene to the ACTIVE player's queued-push mode. Signal plumbing only
## (no input handling here — the target itself consumes the click; the player owns the mode).
func _connect_push_targets(root: Node) -> void:
	for t in root.find_children("*", "", true, false):
		if t.has_signal("push_queue_requested") and not t.push_queue_requested.is_connected(_on_push_queue_requested):
			t.push_queue_requested.connect(_on_push_queue_requested)

func _on_push_queue_requested(obj_id: String) -> void:
	if _player != null and _player.has_method("queue_push"):
		_player.queue_push(obj_id)
		_show_push_queue_prompt(_player)

func _apply_chunk_navigation_graph() -> void:
	if _game_state == null:
		return
	# A chunk exposing get_grid_data() routes on the unified grid (cells + per-cell risk). Chunks
	# without one are gridless: straight-line movement only.
	var next_grid: GridWorld = null
	if _active_chunk != null and _active_chunk.has_method("get_grid_data"):
		var grid_data: Variant = _active_chunk.call("get_grid_data")
		if grid_data is Dictionary and not (grid_data as Dictionary).is_empty():
			next_grid = GridWorld.from_data(grid_data as Dictionary)
	# Player derives its navigation grid from GameState, so this one assignment updates
	# both simulation and click-to-move authority (including clearing gridless chunks).
	_game_state.grid = next_grid

func _compute_speed() -> float:
	if _scheduler != null and _scheduler.is_paused():
		return 0.0
	return 10.0 if Input.is_key_pressed(KEY_F) else 1.0

func _on_process(delta: float, spd: float) -> void:
	# Push active_character only when it changed (or the interactable set was rebuilt) — the
	# unconditional per-frame write touched every interactable 60x/sec for nothing.
	if _active_char_id != _pushed_active_char_id:
		_pushed_active_char_id = _active_char_id
		for interactable in _preview_interactables:
			if interactable != null and is_instance_valid(interactable):
				interactable.active_character = _active_char_id

	# Gameplay clocks advance on EventScheduler callbacks/anchors. A render frame only projects
	# their already-committed state into the HUD and lighting.
	_sync_preview_clock_from_authority(true)
	_refresh_ability_display()
	_update_overlay_runtime(delta)
	_refresh_overlay_panel_status()
	_refresh_inventory_panel()

	if _note_timer > 0.0:
		_note_timer = maxf(0.0, _note_timer - delta)
		if _note_timer <= 0.0 and _note_label != null:
			_restore_default_note()

func _get_speed_recipients() -> Array:
	return _preview_interactables

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if event.is_action_pressed("ui_cancel") and _pending_targeted_ability_id != "":
			_cancel_preview_ability_targeting()
			show_preview_message("Ability target cancelled.", 1.0)
			get_viewport().set_input_as_handled()
			return
		var direct_ability_action := _pressed_party_ability_action(event)
		if direct_ability_action != "":
			_activate_action_bound_preview_ability(direct_ability_action)
		elif event.is_action_pressed("preview_toggle_instructions"):
			_toggle_instructions_panel()
		elif event.is_action_pressed("preview_overlay_drawer"):
			_toggle_overlay_panel()
		# `route`, `pause`, and `run` remain owned by GameHUD. Keeping one action owner prevents a
		# single press from toggling twice as events traverse the scene tree.
		elif event.is_action_pressed("preview_cycle_character"):
			_cycle_character()
		elif event.is_action_pressed("ability_primary"):
			_activate_action_bound_preview_ability("ability_primary")
		elif event.is_action_pressed("ability_secondary"):
			if not _activate_action_bound_preview_ability("ability_secondary"):
				_consume_active_item()
		elif event.is_action_pressed("ability_tertiary"):
			_activate_action_bound_preview_ability("ability_tertiary")
		elif event.is_action_pressed("preview_reload"):
			get_tree().reload_current_scene()
		elif event.is_action_pressed("preview_regenerate"):
			_regenerate_preview_variation()
		elif event.is_action_pressed("preview_overlay_aster"):
			_toggle_overlay("aster")
		elif event.is_action_pressed("preview_overlay_peris"):
			_toggle_overlay("peris")
		elif event.is_action_pressed("preview_overlay_endo"):
			_toggle_overlay("endo")
		elif event.is_action_pressed("preview_drop_item"):
			_drop_active_item()
		elif event.is_action_pressed("preview_transfer_item"):
			_transfer_active_item()
		elif event.is_action_pressed("preview_retrieve_item"):
			_exocytose_active_item()
		elif event.is_action_pressed("preview_toggle_dodge"):
			_preview_dodge_unlocked = not _preview_dodge_unlocked
			_apply_dodge_setting()
			show_preview_message("Dodge roll: %s" % ("ENABLED" if _preview_dodge_unlocked else "locked"), 1.4)
		elif event.is_action_pressed("select_primary"):
			_select_or_toggle_character("aster", key_event)
		elif event.is_action_pressed("select_secondary"):
			_select_or_toggle_character("peris", key_event)
		elif event.is_action_pressed("select_tertiary"):
			_select_or_toggle_character("endo", key_event)
		else:
			# Data-only/experimental abilities may still carry an explicit keycode outside the three
			# shared slots. Preserve that fallback until their data gains a named InputMap action.
			var code := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
			_activate_keybound_preview_ability(code)

func _select_or_toggle_character(char_id: String, key_event: InputEventKey) -> void:
	if key_event.ctrl_pressed or key_event.shift_pressed:
		_toggle_character_selected(char_id)
	else:
		_select_character(char_id)

func register_preview_interactable(interactable: Node) -> void:
	if _preview_interactables.has(interactable):
		return
	_preview_interactables.append(interactable)
	interactable.dialogue_box = _dialogue
	interactable.active_character = _active_char_id
	# Chunk-built interactables must ride the GAMEPLAY scheduler like every other interactable (the
	# tutorial base's tree-walk injection runs before chunks load, so it never reaches them). Without
	# this a TIMED_ACTION dwell falls back to the wall clock — non-deterministic under headless_advance
	# and not fast-forward invariant (The Watched Gap's flure tend caught it firing late).
	if _scheduler != null and interactable.has_method("set_scheduler"):
		interactable.call("set_scheduler", _scheduler)
	# Timed work also belongs to the authoritative mover. Dynamically loaded chunk
	# controls miss TutorialSequence's startup tree walk, so bind GameState here as
	# well; otherwise arrival, interruption, and a restored mid-dwell can disagree
	# with the body that actually walked to the station.
	if _game_state != null and interactable.has_method("set_movement_authority"):
		interactable.call("set_movement_authority", _game_state)
	_connect_interactable_outline_feedback(interactable)
	for char_id in CHARACTER_IDS:
		var character_node: Node = _characters.get(char_id, null)
		if character_node != null and character_node.has_method("bind_interaction_target"):
			character_node.call("bind_interaction_target", interactable)

func get_preview_dialogue_box() -> Node:
	return _dialogue

func get_preview_engram_overlay() -> Node:
	return _ensure_engram_overlay()

func get_preview_active_character() -> String:
	return _active_char_id


func get_preview_character_node(char_id: String) -> Node3D:
	var character = _characters.get(char_id, null)
	return character as Node3D if character is Node3D and is_instance_valid(character) else null

func get_preview_selected_characters() -> Array:
	return _selected_char_ids.duplicate()

## Public roster seam for collective kit objects. This is deliberately the
## exact set the shipped selection UI can currently present and accept, not the
## current selection and not an authored hard-coded party list.
func get_preview_available_party_ids() -> Array:
	return _available_preview_party_ids()

func get_preview_scheduler_tick() -> float:
	return _scheduler.get_current_tick() if _scheduler != null else 0.0

func get_preview_character_move_speed(char_id: String, running := false) -> float:
	var base_speed: float = float(CHARACTER_SPEEDS.get(char_id, 3.0))
	if not running:
		return base_speed
	if not _characters.has(char_id):
		return base_speed
	var node: Node = _characters[char_id]
	if node != null:
		var run_speed: Variant = node.get("run_speed")
		if run_speed != null:
			return float(run_speed)
	return base_speed

func get_preview_character_position(char_id: String) -> Vector3:
	# Chunk logic runs in the flat DATA frame, so return the DATA position whenever the data layer knows the
	# character — the data is the authority. (On a warped scene the rendered node sits on the curved helix; on a
	# flat scene the node usually matches the data but LAGS a frame after a data-layer snap — e.g. a Portal
	# teleport via snap_character_to — so reading the node would report the stale spot.) Fall back to the node only
	# for a character with no data-layer entry.
	if _game_state != null and _game_state.characters.has(char_id):
		return _game_state.get_position(char_id)
	if not _characters.has(char_id):
		return Vector3.ZERO
	return (_characters[char_id] as CharacterBody3D).global_position

func get_preview_character_stat(char_id: String, stat_name: String) -> float:
	if not _character_state.has(char_id):
		return 0.0
	return float(_character_state[char_id].get(_normalize_stat_name(stat_name), 0.0))

func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
	if not _character_state.has(char_id):
		return

	var normalized := _normalize_stat_name(stat_name)
	if normalized not in ["hp", "sta", "atp"]:
		return
	# GameState is the ONE truth for hp/stamina/atp: a registered character writes THROUGH the logged
	# set_stat (clamping + combat-down marking live there) and the HUD ledger mirrors back via
	# stat_changed. Pushing the ledger INTO gs instead let the per-frame stamina regen overwrite real
	# enemy strike damage the same frame it landed.
	if _game_state != null and _game_state.characters.has(char_id):
		var game_stat := "stamina" if normalized == "sta" else normalized
		var canonical := value
		if game_stat == "atp":
			canonical = clampf(GameState.quantize_atp(value), 0.0, _game_state.get_stat_cap(char_id, game_stat))
		else:
			canonical = clampf(value, 0.0, _game_state.get_stat_cap(char_id, game_stat))
		# Continuous regeneration at an already-full cap used to emit a logged
		# over-cap set_stat every render frame, only for GameState to clamp it back
		# to the same value. A semantic no-op must not pollute deterministic traces.
		if not is_equal_approx(_game_state.get_stat(char_id, game_stat), canonical):
			_game_state.set_stat(char_id, game_stat, canonical)
		return
	var previous_value := float(_character_state[char_id].get(normalized, 0.0))
	match normalized:
		"hp":
			_character_state[char_id][normalized] = clampf(value, 0.0, DEFAULT_HP)
		"sta":
			_character_state[char_id][normalized] = clampf(value, 0.0, DEFAULT_STAMINA)
		"atp":
			_character_state[char_id][normalized] = GameState.clamp_atp(value)
	_sync_character_hud(char_id)
	if normalized == "hp" and previous_value > 0.0 and float(_character_state[char_id].get("hp", 0.0)) <= 0.0:
		_ensure_valid_selection()

func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
	var normalized := _normalize_stat_name(stat_name)
	# Route combat damage through GameState so shared defenses such as Peris's WRAP can resolve it.
	# Administrative setters still intentionally bypass temporary shields for resets and authored setup.
	if normalized == "hp" and delta < 0.0 and _game_state != null \
			and _game_state.characters.has(char_id):
		_game_state.adjust_stat(char_id, "hp", delta)
		return
	set_preview_character_stat(char_id, stat_name, get_preview_character_stat(char_id, stat_name) + delta)

func set_preview_character_status(char_id: String, status: String) -> void:
	if not _character_state.has(char_id):
		return
	_character_state[char_id]["status"] = status
	_sync_character_hud(char_id)

func set_preview_character_visible(char_id: String, visible: bool) -> void:
	if not _character_state.has(char_id) or not _characters.has(char_id):
		return
	_character_state[char_id]["visible"] = visible
	_characters[char_id].visible = visible
	if not visible:
		_characters[char_id].set_move_enabled(false)
	_sync_character_hud(char_id)
	if not visible:
		_ensure_valid_selection()

## Story/chunk-facing presence query. A character provides gameplay presence only while its body is
## visible in this beat and its canonical GameState record is registered.
func is_preview_character_present(char_id: String) -> bool:
	return _game_state != null and _game_state.characters.has(char_id) \
		and _characters.has(char_id) and _characters[char_id] != null \
		and _character_is_visible(char_id)

## Runback recovery may need to repair more than HP: a party member can have been hidden or
## unregistered by story presence. Re-register the existing body, restore it, and put it at the
## checkpoint so the next run really begins with the authored party.
func restore_preview_character_for_restart(char_id: String, world_pos: Vector3) -> bool:
	if _game_state == null or not _characters.has(char_id) or _characters[char_id] == null \
			or not _character_state.has(char_id):
		return false
	# A scenario reset invalidates any click-to-interact walk already in flight. Cancel it before
	# stopping/snapping the body; otherwise the controller observes the forced stop as an arrival and
	# can complete the old target remotely from the checkpoint on its next poll.
	if _characters[char_id].has_method("cancel_interaction_target"):
		_characters[char_id].call("cancel_interaction_target")
	if not _game_state.characters.has(char_id):
		_register_gs_character(char_id, _characters[char_id],
			float(CHARACTER_SPEEDS.get(char_id, 3.0)), {
				"hp": DEFAULT_HP,
				"stamina": DEFAULT_STAMINA,
				"atp": DEFAULT_ATP,
			})
		if _characters[char_id].has_method("bind_interaction_root"):
			_characters[char_id].call("bind_interaction_root", self)
	set_preview_character_visible(char_id, true)
	_game_state.restore_character(char_id)
	_game_state.snap_character_to(char_id, world_pos, false)
	_sync_character_from_game_state(char_id)
	return true

func select_preview_character(char_id: String) -> void:
	_select_character(char_id)

func show_preview_message(text: String, duration := 2.0) -> void:
	if EventLog.print_events:
		print("[MSG ] %s" % text)
	if _hud != null:
		_hud.show_message(text, duration)


## Public, read-only presentation seams for accessibility and input-driven
## players. They expose only controls that are actually rendered; private scene
## state and authored world coordinates stay behind the preview controller.
func get_player_observation_pointer_source() -> Node:
	return _player if _player != null and is_instance_valid(_player) else null


## Read-only twin of the fog overlay's clear-region rule. Player observation
## calls this only after a real production pointer ray has hit a rendered command
## surface, and passes that exact hit point. This prevents automation from seeing
## or clicking a collider that the screen-space fog still hides while preserving
## partially revealed large objects whose visible edge a human can actually hit.
func is_player_observation_world_point_visible(world_point: Vector3) -> bool:
	if not world_point.is_finite():
		return false
	if not fog_of_war_enabled:
		return true
	return _party_can_perceive_world_point(world_point)


func get_player_observation_consequence_presenter() -> Node:
	# Explicit presentation-only seam. Automated players may inspect the same
	# warning/carry/arrival presenter that is rendering to the player, but never
	# the GameState traversal registry or a fragment-private sweep counter.
	return _consequence_presentation_controller \
		if _consequence_presentation_controller != null \
			and is_instance_valid(_consequence_presentation_controller) else null


func get_player_observation_text_cues() -> Array:
	var cues: Array = []
	for pair in [
		[_title_label, "instruction"],
		[_help_label, "instruction"],
		[_note_label, "hud"],
	]:
		var label: Label = (pair as Array)[0]
		if label == null or not label.is_visible_in_tree() or label.modulate.a <= 0.01:
			continue
		var text := str(label.text).strip_edges()
		if text == "":
			continue
		cues.append({
			"kind": str((pair as Array)[1]),
			"text": text,
			"visible": true,
		})
	# Input-hint chips are part of the rendered briefing too. Preserve their
	# visible glyph labels and descriptions so an observation-only browser player
	# can discover the same camera/selection/action controls a human reads. The
	# flow's inherited visibility makes Hiding the briefing remove these cues.
	for flow in [
		_control_hint_flow,
		_ability_hint_flow,
		_inventory_controls_flow,
	]:
		for hint_text in _visible_input_hint_texts(flow):
			cues.append({
				"kind": "instruction",
				"text": hint_text,
				"visible": true,
			})
	return cues


func _visible_input_hint_texts(flow: Container) -> Array[String]:
	var result: Array[String] = []
	if flow == null or not flow.is_visible_in_tree():
		return result
	for chip_v in flow.get_children():
		if not (chip_v is Control) \
				or not _control_has_player_visible_area(chip_v as Control):
			continue
		var row := (chip_v as Node).get_node_or_null("Row")
		if row == null:
			continue
		var parts: Array[String] = []
		for part_v in row.get_children():
			if part_v.has_method("get_binding_label"):
				var binding_label := str(part_v.call(
					"get_binding_label")).strip_edges()
				if binding_label != "":
					parts.append(binding_label)
			elif part_v is Label and (part_v as Label).is_visible_in_tree():
				var description := str((part_v as Label).text).strip_edges()
				if description != "":
					parts.append(description)
		var rendered_text := " ".join(parts).strip_edges()
		if rendered_text != "" and not result.has(rendered_text):
			result.append(rendered_text)
	return result


func _control_has_player_visible_area(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree() \
			or control.modulate.a <= 0.01 or control.self_modulate.a <= 0.01:
		return false
	var viewport := control.get_viewport()
	if viewport == null:
		return false
	var visible_area := control.get_global_rect().intersection(
		viewport.get_visible_rect())
	if not visible_area.has_area():
		return false
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is CanvasItem \
				and not (ancestor as CanvasItem).is_visible_in_tree():
			return false
		if ancestor is Control and (ancestor as Control).clip_contents:
			visible_area = visible_area.intersection(
				(ancestor as Control).get_global_rect())
			if not visible_area.has_area():
				return false
		ancestor = ancestor.get_parent()
	return true


## Atom is a long planning board. Browser pointers naturally rest against the viewport
## edge and used to drift the board away from the decision the player was reading. Keep
## intentional WASD/middle-drag pan, but disable accidental edge pan for this preview.
func _configure_preview_camera_feedback() -> void:
	if _camera == null:
		return
	_camera.edge_scroll_margin = 0.0 if preview_chunk == "puzzle_atom" else DEFAULT_PREVIEW_EDGE_SCROLL_MARGIN
	_camera.clear_look_bounds()
	var profile := {
		"follow_offset": Vector3(0.0, 12.0, 9.0),
		"min_zoom": 0.45,
		"max_zoom": 2.2,
		"initial_zoom": 1.0,
		"reset_yaw": false,
	}
	if _active_chunk != null and _active_chunk.has_method("get_preview_camera_profile"):
		var chunk_profile = _active_chunk.call("get_preview_camera_profile")
		if chunk_profile is Dictionary:
			profile.merge(chunk_profile as Dictionary, true)
	_camera.apply_follow_profile(profile, true)

func set_preview_ability_state(ability_id: String, state: String, remaining := 0.0) -> void:
	_set_runtime_ability_state(ability_id, state, remaining)

func get_preview_routing_mode() -> String:
	return _routing_mode

func set_preview_step(step: String) -> void:
	_current_step = step

func show_preview_note(text: String, duration := 3.0) -> void:
	if EventLog.print_events:
		print("[NOTE] %s" % text)
	if _note_label == null:
		return
	if _status_margin != null:
		_status_margin.visible = true
	_note_label.text = text
	_note_timer = maxf(0.0, duration)

func headless_get_anchor_positions() -> Dictionary:
	var anchors := DEFAULT_SPAWNS.duplicate(true)
	if _active_chunk != null and _active_chunk.has_method("get_preview_anchors"):
		anchors.merge(_active_chunk.call("get_preview_anchors"), true)
	return anchors


## Read-only bridge for scene chunks that must validate a shelter interaction
## against the exact clock the preview displays. Callers decide when to synchronize
## GameState; this getter deliberately emits no clock events.
func get_preview_clock_state() -> Dictionary:
	_sync_preview_clock_from_authority(false)
	return {"day": _preview_day, "time": _preview_time}


func headless_get_state() -> Dictionary:
	_sync_preview_clock_from_authority(false)
	var state := {
		"preview_chunk": preview_chunk,
		"preview_party_preset": _preview_party_preset(),
		"world_slot": _active_world_slot(),
		"current_step": _current_step,
		"active_character": _active_char_id,
		"selected_characters": _selected_char_ids.duplicate(),
		"routing_mode": _routing_mode,
		"run_active": _run_active,
		"paused": _scheduler.is_paused() if _scheduler else false,
		"scheduler_tick": _scheduler.get_current_tick() if _scheduler else 0.0,
		"day": _preview_day,
		"time": _preview_time,
		"time_phase": _preview_cycle.get_phase_name(_preview_time),
		"clock": {
			"running": _preview_clock_running,
			"show_time": _preview_show_time,
			"phase": _preview_cycle.get_phase_name(_preview_time),
			"phase_duration_seconds": _preview_cycle.get_phase_duration_seconds(_preview_time),
			"phase_elapsed_seconds": _preview_cycle.get_phase_elapsed_seconds(_preview_time),
			"phase_remaining_seconds": _preview_cycle.get_seconds_until_next_phase(_preview_time),
			"cycle_elapsed_seconds": _preview_cycle.get_cycle_elapsed_seconds(_preview_time),
			"cycle_duration_seconds": _preview_cycle.get_cycle_duration_seconds(),
			"day_duration_seconds": _preview_cycle.day_duration_seconds,
			"night_duration_seconds": _preview_cycle.night_duration_seconds,
		},
		"overlay_states": _overlay_states.duplicate(true),
		"enabled_overlays": _get_enabled_overlays(),
		"active_overlay": _get_live_overlay_id(),
		"overlay_vision_sources": _get_overlay_vision_source_state(),
		"overlay_panel_collapsed": _overlay_panel_collapsed,
		"ui": _get_preview_ui_state(),
		"inventory": {
			"collection": get_preview_collection_items(),
			"endocytosing": {},
		},
		"navigation": _game_state.get_navigation_state() if _game_state != null else {},
		"characters": {},
		"character_stats": {},
		"abilities": {},
	}

	for char_id in CHARACTER_IDS:
		state["characters"][char_id] = get_preview_character_position(char_id)
		state["character_stats"][char_id] = _character_state.get(char_id, {}).duplicate(true)
		state["inventory"][char_id] = {
			"hands": get_preview_hand_items(char_id),
			"hand_slots": get_preview_hand_slots(char_id),
			"internal": get_preview_internal_items(char_id),
		}
		state["inventory"]["endocytosing"][char_id] = _game_state.is_endocytosing(char_id) if _game_state != null else false

	for ability_id in _ability_order:
		var ability_def: Dictionary = _ability_defs.get(ability_id, {})
		var ability_runtime: Dictionary = _ability_runtime.get(ability_id, {})
		state["abilities"][ability_id] = {
			"display_name": str(ability_def.get("display_name", ability_id.to_upper())),
			"keybind": str(ability_def.get("keybind", "")),
			"keycode": int(ability_def.get("keycode", 0)),
			"input_action": str(ability_def.get("input_action", "")),
			"legacy_input_action": str(ability_def.get("legacy_input_action", "")),
			"legacy_keybind": str(ability_def.get("legacy_keybind", "")),
			"legacy_keycode": int(ability_def.get("legacy_keycode", ability_def.get("keycode", 0))),
			"state": str(ability_runtime.get("base_state", "ready")),
			"remaining": _preview_ability_remaining(ability_id),
			"owner": str(ability_def.get("owner", "")),
			"owner_display": str(ability_def.get("owner_display", "")),
			"party_slot": int(ability_def.get("party_slot", -1)),
			"ability_slot": int(ability_def.get("ability_slot", -1)),
		}

	if _active_chunk != null and _active_chunk.has_method("get_preview_state"):
		state["chunk"] = _active_chunk.call("get_preview_state")

	return state

func _get_preview_ui_state() -> Dictionary:
	var hud_contract := {}
	if _hud != null and _hud.has_method("get_hud_contract"):
		hud_contract = _hud.call("get_hud_contract")
	return {
		"contract_id": PREVIEW_GUI_CONTRACT_ID,
		"hud_script": GAME_HUD_SCRIPT_PATH,
		"shared_hud": _hud != null and _hud.get_script() == GameHUDScript,
		"controls": _preview_control_help_text(),
		"inventory_controls": _preview_inventory_control_help_text(),
		"control_bindings": _input_binding_contract(PREVIEW_CONTROL_ACTIONS),
		"party_ability_actions": PARTY_ABILITY_ACTIONS.duplicate(true),
		"ability_keymap": _get_canonical_main_ability_keymap(),
		"hud": hud_contract,
	}

func _input_binding_contract(actions: Array) -> Dictionary:
	var bindings := {}
	for action_v in actions:
		var action := str(action_v)
		bindings[action] = InputHints.label_for_action(action, "")
	return bindings

func _preview_control_help_text() -> String:
	var labels := _input_binding_contract(PREVIEW_CONTROL_ACTIONS)
	return "%s move  %s/%s/%s/%s or %s pan  %s/%s/%s focus  Ctrl+%s/%s/%s group  %s cycle  %s party abilities  %s drop  %s transfer  %s retrieve  %s/%s/%s overlays  %s drawer  %s route  %s dodge  %s pause  %s run  %s reload  %s hide" % [
		labels.get("command", ""),
		labels.get("camera_pan_forward", ""), labels.get("camera_pan_left", ""),
		labels.get("camera_pan_back", ""), labels.get("camera_pan_right", ""),
		labels.get("camera_pan", ""),
		labels.get("select_primary", ""), labels.get("select_secondary", ""),
		labels.get("select_tertiary", ""),
		labels.get("select_primary", ""), labels.get("select_secondary", ""),
		labels.get("select_tertiary", ""),
		labels.get("preview_cycle_character", ""),
		_party_ability_bank_help_text(),
		labels.get("preview_drop_item", ""), labels.get("preview_transfer_item", ""),
		labels.get("preview_retrieve_item", ""),
		labels.get("preview_overlay_aster", ""), labels.get("preview_overlay_peris", ""),
		labels.get("preview_overlay_endo", ""), labels.get("preview_overlay_drawer", ""),
		labels.get("route", ""), labels.get("preview_toggle_dodge", ""),
		labels.get("pause", ""), labels.get("run", ""), labels.get("preview_reload", ""),
		labels.get("preview_toggle_instructions", ""),
	]

func _preview_inventory_control_help_text() -> String:
	var labels := _input_binding_contract(PREVIEW_INVENTORY_ACTIONS)
	return "%s party abilities  %s use item  %s drop  %s transfer  %s retrieve" % [
		_party_ability_bank_help_text(),
		labels.get("ability_secondary", ""),
		labels.get("preview_drop_item", ""), labels.get("preview_transfer_item", ""),
		labels.get("preview_retrieve_item", ""),
	]

## Render the remappable six-column/two-row bank exactly as InputMap exposes it. Empty direct slots
## stay out of help; their spreadsheet Z/X/Y compatibility route is intentionally not advertised once
## a direct slot is bound.
func _party_ability_bank_help_text() -> String:
	var columns: Array[String] = []
	for row_v in PARTY_ABILITY_ACTIONS:
		var column_labels: Array[String] = []
		for action_v in row_v:
			var label := InputHints.label_for_action(str(action_v), "")
			if label != "":
				column_labels.append(label)
		if not column_labels.is_empty():
			columns.append("/".join(column_labels))
	return "  ".join(columns)

func _get_canonical_main_ability_keymap() -> Dictionary:
	var keymap := {}
	for ability_id in AbilityData.ABILITY_ORDER:
		var binding := AbilityData.binding(ability_id)
		if binding.is_empty():
			continue
		var ability: Dictionary = _ability_defs.get(ability_id, {})
		var legacy_keybind := str(binding.get("keybind", "")).to_upper()
		var legacy_input_action := str(ability.get(
			"legacy_input_action",
			ABILITY_INPUT_ACTION_BY_KEYBIND.get(legacy_keybind, "")
		))
		var input_action := str(ability.get("input_action", ""))
		var input_event := (
			InputHints.primary_event_for_action(legacy_input_action, "keyboard")
			if legacy_input_action != ""
			else null
		)
		var keycode := int(ability.get("legacy_keycode", binding.get("keycode", 0)))
		if input_event is InputEventKey:
			var key_event := input_event as InputEventKey
			keycode = (
				key_event.physical_keycode
				if key_event.physical_keycode != KEY_NONE
				else key_event.keycode
			)
		keymap[ability_id] = {
			"owner": str(ability.get("owner", binding.get("owner", ""))),
			"input_action": input_action,
			"legacy_input_action": legacy_input_action,
			"keybind": str(ability.get("keybind", InputHints.label_for_action(
				legacy_input_action,
				legacy_keybind
			))),
			"legacy_keybind": str(ability.get("legacy_keybind", legacy_keybind)),
			"keycode": keycode,
			"legacy_keycode": keycode,
			"party_slot": int(ability.get("party_slot", -1)),
			"ability_slot": int(ability.get("ability_slot", -1)),
		}
	return keymap

func _active_world_slot() -> Dictionary:
	if _active_chunk != null and _active_chunk.has_method("get_world_slot"):
		var slot: Variant = _active_chunk.call("get_world_slot")
		if slot is Dictionary:
			return (slot as Dictionary).duplicate(true)
	return {}

func _preview_party_preset() -> String:
	var slot := _active_world_slot()
	return str(slot.get("preview_party_preset", "full_party_full_health"))

func headless_select_character(char_id: String) -> void:
	select_preview_character(char_id)

func headless_set_selected_characters(char_ids: Array) -> void:
	var preferred_active := str(char_ids[0]) if char_ids.size() > 0 else ""
	_apply_selection_state(char_ids, preferred_active)

func headless_move_character(char_id: String, pos: Vector3, running := false) -> bool:
	if _game_state == null or not _game_state.characters.has(char_id):
		return false
	_game_state.change_move_speed(char_id, get_preview_character_move_speed(char_id, running))
	# Deterministic input playback must exercise the same graph-location boundary as
	# an ordinary click. Generated approach points can lie on dressing or a WFC wall
	# mask; resolve them to the nearest valid node while preserving the inferred deck
	# and typed connector edges. Gridless previews retain straight-line movement.
	if _game_state.grid != null:
		var navigation_location: Dictionary = _game_state.resolve_navigation_location(
			char_id, pos
		)
		if navigation_location.is_empty():
			return false
		return _game_state.command_move_to_navigation_location(
			char_id, navigation_location
		)
	return _game_state.command_move_to_pos(char_id, pos)

func headless_is_character_moving(char_id: String) -> bool:
	if _game_state == null:
		return false
	return _game_state.is_moving(char_id)

func headless_get_character_movement_info(char_id: String) -> Dictionary:
	if _game_state == null or not _game_state.characters.has(char_id):
		return {"moving": false}
	var ch: Dictionary = _game_state.characters[char_id]
	var speed := float(ch.get("move_speed", get_preview_character_move_speed(char_id, false)))
	var walk_speed := get_preview_character_move_speed(char_id, false)
	var running := speed > walk_speed + 0.05
	var movement: Variant = ch.get("movement", null)
	if not (movement is Dictionary):
		return {
			"moving": false,
			"speed": speed,
			"running": running,
			"locomotion": "idle",
		}
	var path: Array = (movement as Dictionary).get("path", [])
	return {
		"moving": true,
		"duration": float(movement.get("duration", 0.0)),
		"total_distance": float(movement.get("total_distance", 0.0)),
		"start_tick": float(movement.get("start_tick", 0.0)),
		"speed": speed,
		"running": running,
		"locomotion": "run" if running else "walk",
		"path_count": path.size(),
		"path": _serialize_vector3_path(path),
	}

func headless_activate_ability(ability_id: String) -> bool:
	if not _ability_defs.has(ability_id):
		return false
	return _execute_preview_ability(
		ability_id, _headless_default_ability_target(ability_id), _headless_default_wrap_target())

func _headless_default_ability_target(ability_id: String) -> Vector3:
	if _game_state == null or not _ability_defs.has(ability_id):
		return Vector3.ZERO
	var owner := str((_ability_defs[ability_id] as Dictionary).get("owner", ""))
	if owner == "" or not _game_state.characters.has(owner):
		return Vector3.ZERO
	return _game_state.get_render_position(owner)

func _headless_default_wrap_target() -> String:
	# Deterministic smoke tests use the owner as a guaranteed in-range valid party target. Targeted
	# tests call headless_activate_ability_at() with the ally they intend to verify.
	return "peris" if _character_is_available("peris") else ""

func headless_activate_ability_at(
		ability_id: String,
		world_pos: Vector3,
		target_id := ""
	) -> bool:
	return _execute_preview_ability(ability_id, world_pos, target_id)

## Deterministic QA contract for the 6x2 drawer. The direct action names are stable while their
## physical keys remain entirely InputMap/settings-owned.
func headless_get_party_ability_routes() -> Dictionary:
	var routes := {}
	for ability_id in _ability_order:
		var ability: Dictionary = _ability_defs.get(ability_id, {})
		routes[ability_id] = {
			"owner": str(ability.get("owner", "")),
			"party_slot": int(ability.get("party_slot", -1)),
			"ability_slot": int(ability.get("ability_slot", -1)),
			"input_action": str(ability.get("input_action", "")),
			"legacy_input_action": str(ability.get("legacy_input_action", "")),
			"legacy_keycode": int(ability.get("legacy_keycode", ability.get("keycode", 0))),
		}
	return routes

func headless_activate_ability_action(input_action: String) -> bool:
	var ability_id := _get_ability_for_input_action(input_action)
	if ability_id == "":
		return false
	return headless_activate_ability(ability_id)

func headless_set_overlay_state(overlay_id: String, enabled: bool) -> void:
	if not _overlay_states.has(overlay_id):
		return
	_overlay_states[overlay_id] = enabled
	_refresh_overlay_button(overlay_id)
	_refresh_active_overlay()
	_refresh_overlay_panel_status()

func headless_set_routing_mode(mode: String) -> void:
	_on_routing_toggled(mode)

func headless_set_preview_time(day: int, time_of_day: float) -> void:
	_anchor_preview_clock(maxi(day, 1), clampf(float(time_of_day), 0.0, 1.0))
	_sync_preview_time_presentation()
	_publish_preview_runtime_authority()

func headless_set_preview_clock_running(enabled: bool) -> void:
	_set_preview_clock_running_authoritative(enabled)

func headless_set_character_position(char_id: String, pos: Vector3) -> void:
	if not _characters.has(char_id):
		return
	if _game_state != null and _game_state.characters.has(char_id):
		if _game_state.is_external_traversal_active(char_id):
			_game_state.cancel_external_traversal(char_id, &"fixture_placement")
		_game_state.command_stop(char_id)
		if _game_state.grid != null:
			var target_level := int(_game_state.grid.level_for_y(pos.y)) \
				if int(_game_state.grid.level_count) > 1 \
				else int(_game_state.get_character_level(char_id))
			# Re-apply even when the level index is unchanged. Authoritative fixture
			# placement must normalize a stale body Y onto that graph floor.
			_game_state.set_character_level(char_id, target_level)
			pos.y = _game_state.grid.grid_to_world(
				_game_state.grid.world_to_grid(pos), target_level).y
		_game_state.snap_character_to(char_id, pos, false)
	if _characters[char_id] != null:
		_characters[char_id].global_position = _game_state.get_render_position(char_id) \
			if _game_state != null and _game_state.characters.has(char_id) else pos

func headless_call_chunk(method_name: String, args: Array = []) -> Variant:
	if _active_chunk == null or not _active_chunk.has_method(method_name):
		return null
	return _active_chunk.callv(method_name, args)

func _serialize_vector3_path(path: Array) -> Array:
	var result := []
	for point in path:
		if point is Vector3:
			result.append([point.x, point.y, point.z])
	return result

func set_preview_character_position(char_id: String, pos: Vector3) -> void:
	headless_set_character_position(char_id, pos)

func _headless_sync_runtime(delta: float) -> void:
	for char_id in CHARACTER_IDS:
		var node: CharacterBody3D = _characters.get(char_id, null)
		if node != null and node.has_method("_physics_process"):
			node._physics_process(delta)
	if _active_chunk != null and _active_chunk.has_method("headless_process"):
		_active_chunk.call("headless_process", delta)

func _build_preview_ui() -> void:
	_preview_layer = FragmentPreviewUIScene.instantiate()
	add_child(_preview_layer)
	_instructions_margin = _preview_layer.get_node("InstructionsMargin") as MarginContainer
	_title_label = _preview_layer.get_node("InstructionsMargin/Panel/Content/TitleLabel") as Label
	_help_label = _preview_layer.get_node("InstructionsMargin/Panel/Content/HelpLabel") as Label
	_control_hint_flow = _preview_layer.get_node("InstructionsMargin/Panel/Content/ControlHints") as HFlowContainer
	_refresh_control_hint_flow()
	_ability_hint_flow = _preview_layer.get_node("InstructionsMargin/Panel/Content/AbilityHints") as HFlowContainer
	# Consequence/refusal status is intentionally outside the H-toggle briefing.
	# H may clear the board, but it must never hide a state-change receipt.
	_status_margin = _preview_layer.get_node("StatusMargin") as MarginContainer
	_note_label = _preview_layer.get_node("StatusMargin/Panel/NoteLabel") as Label
	_build_inventory_panel()
	_build_overlay_stack()
	_build_overlay_panel()

func _add_action_hint(
	parent: Container,
	action: StringName,
	description: String,
	fallback_label := "",
	tint := Color(0.42, 0.66, 0.74)
) -> PanelContainer:
	return _add_input_hint(parent, [{"action": action, "fallback": fallback_label}], description, tint)

func _add_input_hint(
	parent: Container,
	parts: Array,
	description: String,
	tint := Color(0.42, 0.66, 0.74)
) -> PanelContainer:
	var chip := InputHintChipScene.instantiate() as PanelContainer
	var style := chip.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = Color(tint, 0.34)
	parent.add_child(chip)
	var row := chip.get_node("Row") as HBoxContainer
	var label := row.get_node("Description") as Label
	for part_v in parts:
		var part: Dictionary = part_v if part_v is Dictionary else {"action": str(part_v)}
		var glyph := InputGlyphScene.instantiate() as InputGlyph
		if part.has("key"):
			glyph.configure_key_label(str(part.get("key", "")))
		else:
			glyph.configure_action(
				StringName(str(part.get("action", ""))),
				str(part.get("fallback", ""))
			)
		row.add_child(glyph)
		row.move_child(glyph, label.get_index())
	label.text = description
	label.add_theme_color_override("font_color", Color(tint.lightened(0.3), 0.95))
	return chip

func _clear_hint_flow(flow: Container) -> void:
	for child in flow.get_children():
		flow.remove_child(child)
		child.queue_free()

func _refresh_control_hint_flow() -> void:
	if _control_hint_flow == null:
		return
	_clear_hint_flow(_control_hint_flow)
	_add_action_hint(_control_hint_flow, "command", "Move", "RMB")
	_add_input_hint(_control_hint_flow, [
		{"action": "camera_pan_forward", "fallback": "W"},
		{"action": "camera_pan_left", "fallback": "A"},
		{"action": "camera_pan_back", "fallback": "S"},
		{"action": "camera_pan_right", "fallback": "D"},
	], "Pan")
	_add_action_hint(_control_hint_flow, "camera_pan", "Drag pan", "MMB")
	_add_input_hint(_control_hint_flow, [
		{"action": "select_primary", "fallback": "1"},
		{"action": "select_secondary", "fallback": "2"},
		{"action": "select_tertiary", "fallback": "3"},
	], "Focus")
	_add_input_hint(_control_hint_flow, [
		{"key": "Ctrl"},
		{"action": "select_primary", "fallback": "1"},
		{"action": "select_secondary", "fallback": "2"},
		{"action": "select_tertiary", "fallback": "3"},
	], "Group")
	_add_action_hint(_control_hint_flow, "preview_cycle_character", "Cycle", "C")
	_add_action_hint(_control_hint_flow, "route", "Route", "Tab")
	_add_action_hint(_control_hint_flow, "preview_toggle_dodge", "Dodge", "G")
	_add_action_hint(_control_hint_flow, "pause", "Pause", "Space")
	_add_action_hint(_control_hint_flow, "run", "Run", "R")
	_add_action_hint(_control_hint_flow, "preview_reload", "Menu", "M")
	_add_action_hint(_control_hint_flow, "preview_toggle_instructions", "Hide", "H")

func _refresh_ability_hint_flow() -> void:
	if _ability_hint_flow == null:
		return
	_clear_hint_flow(_ability_hint_flow)
	for ability_id in _ability_order:
		var ability: Dictionary = _ability_defs.get(ability_id, {})
		var action := str(ability.get("input_action", ""))
		var keybind := str(ability.get("keybind", ""))
		if action == "" and keybind == "":
			continue
		var owner := str(ability.get("owner", ""))
		var owner_name := str(CHARACTER_DISPLAY_NAMES.get(owner, owner.capitalize()))
		var display := str(ability.get("display_name", ability_id.to_upper()))
		var parts: Array = (
			[{"action": action, "fallback": keybind}]
			if action != ""
			else [{"key": keybind}]
		)
		_add_input_hint(
			_ability_hint_flow,
			parts,
			"%s · %s" % [owner_name, display] if owner_name != "" else display,
			CHARACTER_COLORS.get(owner, Color(0.68, 0.72, 0.78))
		)
	_ability_hint_flow.visible = _ability_hint_flow.get_child_count() > 0

func _build_inventory_panel() -> void:
	_inventory_panel_margin = _preview_layer.get_node("InventoryMargin") as MarginContainer
	_inventory_panel_title = _preview_layer.get_node("InventoryMargin/Panel/Content/Title") as Label
	_inventory_controls_flow = _preview_layer.get_node("InventoryMargin/Panel/Content/ControlHints") as HFlowContainer
	# The old secondary action remains the explicit consume-item key. Direct party abilities have their
	# own 6x2 drawer and hints, so this must not imply that X still fires one of them.
	_add_action_hint(_inventory_controls_flow, "ability_secondary", "Use item", "X")
	_add_action_hint(_inventory_controls_flow, "preview_drop_item", "Drop", "V")
	_add_action_hint(_inventory_controls_flow, "preview_transfer_item", "Transfer", "T")
	_add_action_hint(_inventory_controls_flow, "preview_retrieve_item", "Retrieve", "B")

	_inventory_panel_label = _preview_layer.get_node("InventoryMargin/Panel/Content/InventoryLabel") as Label
	_refresh_inventory_panel()

const OVERLAY_PANEL_TOP := 12.0
const OVERLAY_PANEL_EXPANDED_BOTTOM := 260.0
const OVERLAY_PANEL_COLLAPSED_BOTTOM := 56.0  # header-only height when collapsed

func _build_overlay_panel() -> void:
	_overlay_panel_margin = _preview_layer.get_node("OverlayMargin") as MarginContainer
	_overlay_panel_collapse_button = _preview_layer.get_node("OverlayMargin/Panel/Content/Header/CollapseButton") as Button
	_overlay_panel_collapse_button.pressed.connect(_toggle_overlay_panel)
	var drawer_glyph := _overlay_panel_collapse_button.get_node("DrawerGlyph") as InputGlyph
	drawer_glyph.configure_action("preview_overlay_drawer", "F4")
	drawer_glyph.attach_to_button(_overlay_panel_collapse_button)
	_overlay_panel_content = _preview_layer.get_node("OverlayMargin/Panel/Content/PanelContent") as VBoxContainer
	var selection_hints := _overlay_panel_content.get_node("SelectionHints") as HFlowContainer
	_add_action_hint(selection_hints, "select", "Primary portrait", "LMB")
	_add_input_hint(selection_hints, [
		{"key": "Ctrl"},
		{"action": "select_primary", "fallback": "1"},
		{"action": "select_secondary", "fallback": "2"},
		{"action": "select_tertiary", "fallback": "3"},
	], "Add / remove")

	var buttons := _overlay_panel_content.get_node("Buttons") as VBoxContainer
	_add_overlay_toggle_button(buttons, "aster", "Aster Data", "preview_overlay_aster", CHARACTER_COLORS["aster"])
	_add_overlay_toggle_button(buttons, "peris", "Peris Flora", "preview_overlay_peris", CHARACTER_COLORS["peris"])
	_add_overlay_toggle_button(buttons, "endo", "Endo Survival", "preview_overlay_endo", CHARACTER_COLORS["endo"])

	_overlay_panel_status_label = _overlay_panel_content.get_node("StatusLabel") as Label
	_refresh_overlay_panel_status()

func _build_overlay_stack() -> void:
	if _overlay_stack_quad != null:
		return
	_overlay_stack_quad = MeshInstance3D.new()
	_overlay_stack_quad.name = "PreviewOverlayQuad"
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_overlay_stack_quad.mesh = quad
	_overlay_stack_quad.extra_cull_margin = 10000.0
	_overlay_stack_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_overlay_stack_material = ShaderMaterial.new()
	_overlay_stack_material.shader = PERCEPTION_STACK_SHADER
	_overlay_stack_material.set_shader_parameter("fog_clear_radius", PARTY_PERCEPTION_CLEAR_RADIUS)
	_overlay_stack_material.render_priority = 126
	_overlay_stack_quad.material_override = _overlay_stack_material
	_overlay_stack_quad.visible = false
	add_child(_overlay_stack_quad)
	_sync_overlay_stack()

func _add_overlay_toggle_button(
	parent: VBoxContainer,
	overlay_id: String,
	label: String,
	input_action: String,
	color: Color
) -> void:
	var button := OverlayToggleButtonScene.instantiate() as Button
	button.pressed.connect(func() -> void:
		_toggle_overlay(overlay_id)
	)
	parent.add_child(button)
	var glyph := InputGlyphScene.instantiate() as InputGlyph
	glyph.configure_action(input_action)
	glyph.attach_to_button(button)
	_overlay_buttons[overlay_id] = {
		"button": button,
		"label": label,
		"color": color,
		"glyph": glyph,
	}
	_refresh_overlay_button(overlay_id)

func _color_with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)

func _toggle_overlay(overlay_id: String) -> void:
	if not _overlay_states.has(overlay_id):
		return
	_overlay_states[overlay_id] = not bool(_overlay_states[overlay_id])
	_refresh_overlay_button(overlay_id)
	_refresh_active_overlay()
	_refresh_overlay_panel_status()
	show_preview_message("%s overlay %s." % [_overlay_display_name(overlay_id), "ON" if bool(_overlay_states[overlay_id]) else "OFF"], 1.2)

func _refresh_overlay_button(overlay_id: String) -> void:
	if not _overlay_buttons.has(overlay_id):
		return
	var info: Dictionary = _overlay_buttons[overlay_id]
	var button: Button = info.get("button")
	var color: Color = info.get("color", Color.WHITE)
	var glyph: InputGlyph = info.get("glyph", null)
	var enabled := bool(_overlay_states.get(overlay_id, false))
	var state_label := "ON" if enabled else "OFF"
	button.text = "%s  ·  %s" % [str(info.get("label", overlay_id)), state_label]

	var normal := StyleBoxFlat.new()
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 10
	normal.content_margin_right = glyph.custom_minimum_size.x + 12.0 if glyph != null else 10.0
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	var hover := normal.duplicate()
	var pressed := normal.duplicate()
	if enabled:
		normal.bg_color = _color_with_alpha(color, 0.18)
		normal.border_color = _color_with_alpha(color, 0.7)
		hover.bg_color = _color_with_alpha(color, 0.24)
		hover.border_color = _color_with_alpha(color, 0.84)
		pressed.bg_color = _color_with_alpha(color, 0.32)
		pressed.border_color = _color_with_alpha(color, 0.95)
		button.add_theme_color_override("font_color", _color_with_alpha(color, 0.95))
	else:
		normal.bg_color = Color(0.06, 0.06, 0.08, 0.9)
		normal.border_color = _color_with_alpha(color, 0.28)
		hover.bg_color = Color(0.08, 0.08, 0.1, 0.95)
		hover.border_color = _color_with_alpha(color, 0.45)
		pressed.bg_color = Color(0.11, 0.11, 0.13, 0.95)
		pressed.border_color = _color_with_alpha(color, 0.55)
		button.add_theme_color_override("font_color", _color_with_alpha(color, 0.62))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)

func _refresh_all_overlay_buttons() -> void:
	for overlay_id in _overlay_buttons.keys():
		_refresh_overlay_button(str(overlay_id))

## Hide/show the top instructions (briefing + controls) panel — H. Hiding the whole margin frees the view;
## pressing H again brings it back.
func _toggle_instructions_panel() -> void:
	if _instructions_margin != null:
		_instructions_margin.visible = not _instructions_margin.visible

func _toggle_overlay_panel() -> void:
	_set_overlay_panel_collapsed(not _overlay_panel_collapsed)

func _set_overlay_panel_collapsed(collapsed: bool) -> void:
	_overlay_panel_collapsed = collapsed
	if _overlay_panel_content != null:
		_overlay_panel_content.visible = not collapsed
	# Shrink the margin itself to the header height — hiding the content alone leaves the
	# PanelContainer filling the fixed margin rect, so the dark window stays full-size.
	if _overlay_panel_margin != null:
		_overlay_panel_margin.offset_bottom = OVERLAY_PANEL_COLLAPSED_BOTTOM if collapsed else OVERLAY_PANEL_EXPANDED_BOTTOM
	if _overlay_panel_collapse_button != null:
		_overlay_panel_collapse_button.text = "SHOW" if collapsed else "HIDE"

func _refresh_overlay_panel_status() -> void:
	if _overlay_panel_status_label == null:
		return
	var selected_names: Array[String] = []
	for char_id in _selected_char_ids:
		selected_names.append(str(CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize())))

	var lines: Array[String] = []
	lines.append("Selected: %s" % (", ".join(selected_names) if not selected_names.is_empty() else "none"))
	lines.append("Primary: %s" % (CHARACTER_DISPLAY_NAMES.get(_active_char_id, _active_char_id.capitalize()) if _active_char_id != "" else "none"))
	for overlay_id in CHARACTER_IDS:
		var state_label := "ON" if bool(_overlay_states.get(overlay_id, false)) else "OFF"
		lines.append("%s: %s" % [_overlay_display_name(overlay_id), state_label])
		if state_label == "ON" and _active_chunk != null and _active_chunk.has_method("get_preview_overlay_status"):
			for status_line in _active_chunk.call("get_preview_overlay_status", overlay_id, get_preview_scheduler_tick()):
				lines.append("  %s" % str(status_line))
	lines.append("Active overlays combine automatically; you do not need to swap portraits to read them together.")
	_overlay_panel_status_label.text = "\n".join(lines)
	_refresh_all_overlay_buttons()

func _overlay_display_name(overlay_id: String) -> String:
	match overlay_id:
		"aster":
			return "Aster data"
		"peris":
			return "Peris flora"
		"endo":
			return "Endo survival"
		_:
			return overlay_id.capitalize()

func _get_enabled_overlays() -> Array[String]:
	var enabled: Array[String] = []
	for overlay_id in CHARACTER_IDS:
		if bool(_overlay_states.get(overlay_id, false)):
			enabled.append(overlay_id)
	return enabled

func _get_live_overlay_id() -> String:
	var enabled := _get_enabled_overlays()
	return enabled[0] if not enabled.is_empty() else ""

func _refresh_active_overlay() -> void:
	# Standalone previews keep the base sequence perception pass disabled and
	# drive their own stackable fullscreen overlays instead.
	_set_perception_mode("")
	_perception_target = null
	_update_overlay_runtime(0.0)

func _update_survival_overlay() -> void:
	pass

var _flora_marks_mgr: FloraMemoryMarks = null

func _update_overlay_runtime(delta: float) -> void:
	_sync_overlay_stack()
	# Peris's overlook memory rides her overlay toggle: the marks manager
	# renders whatever the chunk remembers (empty until the overlook beat).
	if _flora_marks_mgr == null or not is_instance_valid(_flora_marks_mgr):
		_flora_marks_mgr = FloraMemoryMarks.new()
		_flora_marks_mgr.name = "FloraMemoryMarks"
		add_child(_flora_marks_mgr)
		_flora_marks_mgr.setup(_game_state, func(): return _active_chunk)
	_flora_marks_mgr.set_active(bool(_overlay_states.get("peris", false)))
	if _active_chunk != null and _active_chunk.has_method("update_preview_overlay_states"):
		_active_chunk.call("update_preview_overlay_states", _overlay_states, get_preview_scheduler_tick(), delta)
	_refresh_preview_items()

# The grid whose sight mask is currently baked into the overlay shader (rebake on change).
var _occ_mask_grid: Object = null

# Whether the current entry's config overlay defaults have been applied (once per entry, not per
# N-regenerate — the player's live F1-F3 choices survive a reseed).
var _overlays_config_applied := false

## Bake the live grid's sight-blocking cells into the overlay shader's occluder mask. Bilinear
## sampling of this mask is what makes the fog edge SOFT (see perception_stack.gdshader). Object
## identity tracks chunk reloads: a new grid (load, N-regenerate, picker return) rebakes once.
func _sync_occluder_mask() -> void:
	if _overlay_stack_material == null:
		return
	var grid: Object = _game_state.grid if _game_state != null else null
	# A WARPED (coord_map) scene renders every position through the warp, but the mask is baked in
	# the FLAT data frame and the shader samples it with WORLD xz — there is no inverse warp on the
	# GPU, so baked occlusion there reads phantom walls (fog over the party's own feet). Warped
	# scenes keep the screen-space depth-march LOS, which is warp-agnostic; the CPU twin
	# (_perception_line_of_sight) already converts through coord_map.to_data for the same reason.
	if _game_state != null and _game_state.coord_map != null:
		grid = null
	if grid == _occ_mask_grid:
		return
	_occ_mask_grid = grid
	var baked: Dictionary = SightMaskBakerScript.bake(grid)
	if baked.is_empty():
		_overlay_stack_material.set_shader_parameter("occ_baked_enabled", false)
		return
	_overlay_stack_material.set_shader_parameter("occ_baked_enabled", true)
	_overlay_stack_material.set_shader_parameter("occ_tex", baked["texture"])
	_overlay_stack_material.set_shader_parameter("occ_origin", baked["origin"])
	_overlay_stack_material.set_shader_parameter("occ_cell", baked["cell"])
	_overlay_stack_material.set_shader_parameter("occ_size", baked["size"])

func _sync_overlay_stack() -> void:
	_sync_occluder_mask()
	var vision_positions := _get_overlay_vision_positions()
	var data_enabled := bool(_overlay_states.get("aster", false)) \
		and _character_contributes_perception("aster") and not vision_positions.is_empty()
	# Fog of war is its OWN gameplay layer — never gated on the Peris view (turning the perception
	# overlays off must not reveal the map). With zero viewers the shader remains on and resolves to
	# full fog; only the dev console (`fog off`) disables it.
	var fog_enabled := fog_of_war_enabled
	var source_0 := _overlay_vision_source_at(vision_positions, 0)
	var source_1 := _overlay_vision_source_at(vision_positions, 1)
	var source_2 := _overlay_vision_source_at(vision_positions, 2)
	var source_count := mini(vision_positions.size(), MAX_VISION_SOURCES)
	_sync_vision_source_texture(vision_positions, source_count)

	# Shared "visible range" globals: transparent effects (the flood water) fade THEMSELVES past the clear
	# radius, since a transparent surface is excluded from the perception overlay's screen rewrite and can't be
	# data-viewed like the opaque geometry. The same registry-driven texture feeds those effects; the three
	# legacy positions remain populated for shaders outside this stack that have not migrated yet.
	RenderingServer.global_shader_parameter_set("visible_range_active", data_enabled or fog_enabled)
	RenderingServer.global_shader_parameter_set("vision_source_count", source_count)
	RenderingServer.global_shader_parameter_set("vision_sources_tex", _vision_sources_texture)
	RenderingServer.global_shader_parameter_set("vision_pos_0", source_0)
	RenderingServer.global_shader_parameter_set("vision_pos_1", source_1)
	RenderingServer.global_shader_parameter_set("vision_pos_2", source_2)

	if _overlay_stack_material == null or _overlay_stack_quad == null:
		return
	_overlay_stack_quad.visible = data_enabled or fog_enabled

	_overlay_stack_material.set_shader_parameter("vision_source_count", source_count)
	_overlay_stack_material.set_shader_parameter("vision_sources_tex", _vision_sources_texture)
	_overlay_stack_material.set_shader_parameter("data_enabled", data_enabled)
	_overlay_stack_material.set_shader_parameter("data_blackout_pos", Vector3(0.0, 0.0, -9999.0))
	_overlay_stack_material.set_shader_parameter("data_blackout_radius", 0.0)
	_overlay_stack_material.set_shader_parameter("fog_enabled", fog_enabled)

## WebGL does not reliably upload vector uniform arrays through ShaderMaterial. A tiny float data
## texture is portable across native and web renderers and keeps the roster registry-driven: adding
## another visible, conscious character only appends another texel.
func _sync_vision_source_texture(positions: Array[Vector3], source_count: int) -> void:
	var next_sources: Array[Vector3] = []
	for source_index in range(source_count):
		next_sources.append(positions[source_index])
	# Headless tests validate the registry-driven perception state directly. Uploading a float
	# texture for every simulated movement tick adds minutes of RenderingServer work without
	# exercising any browser-visible behaviour.
	if DisplayServer.get_name() == "headless":
		_vision_sources_cache = next_sources
		return
	if _vision_sources_texture != null and _vision_sources_cache == next_sources:
		return
	if _vision_sources_image == null:
		_vision_sources_image = Image.create(MAX_VISION_SOURCES, 1, false, Image.FORMAT_RGBAF)
	for source_index in range(MAX_VISION_SOURCES):
		var source_pos := next_sources[source_index] if source_index < source_count else NO_VISION_SOURCE
		_vision_sources_image.set_pixel(source_index, 0,
			Color(source_pos.x, source_pos.y, source_pos.z, 1.0))
	if _vision_sources_texture == null:
		_vision_sources_texture = ImageTexture.create_from_image(_vision_sources_image)
	else:
		_vision_sources_texture.update(_vision_sources_image)
	_vision_sources_cache = next_sources

func _get_overlay_vision_positions() -> Array[Vector3]:
	# Every present, conscious character clears fog. Iterate the actual character registry rather
	# than the three launch characters so future/opt-in members contribute automatically.
	var positions: Array[Vector3] = []
	for char_id_v in _characters.keys():
		var char_id := str(char_id_v)
		if not _characters.has(char_id) or _characters[char_id] == null:
			continue
		if not _character_contributes_perception(char_id):
			continue
		var character_node := _characters[char_id] as CharacterBody3D
		if character_node == null:
			continue
		positions.append(character_node.global_position + Vector3(0.0, 1.0, 0.0))
	return positions

func _get_overlay_vision_source_state() -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for char_id_v in _characters.keys():
		var char_id := str(char_id_v)
		if not _characters.has(char_id) or _characters[char_id] == null:
			continue
		if not _character_contributes_perception(char_id):
			continue
		var character_node := _characters[char_id] as CharacterBody3D
		if character_node == null:
			continue
		sources.append({
			"character_id": char_id,
			"position": character_node.global_position + Vector3(0.0, 1.0, 0.0),
		})
	return sources


## Both cause and effect must be perceived by the union of every present, conscious
## character. Different characters may reveal the two endpoints, so scouting with Endo
## while Peris tends a cause works and future party members opt in automatically.
func can_party_perceive_feedback_link(source_world: Vector3, target_world: Vector3) -> bool:
	return _party_can_perceive_world_point(source_world) \
		and _party_can_perceive_world_point(target_world)


func _party_can_perceive_world_point(world_point: Vector3) -> bool:
	for vision_source in _get_overlay_vision_positions():
		if vision_source.distance_to(world_point) > PARTY_PERCEPTION_CLEAR_RADIUS:
			continue
		if _perception_line_of_sight(vision_source, world_point):
			return true
	return false


func _perception_line_of_sight(from_world: Vector3, to_world: Vector3) -> bool:
	if _game_state == null or _game_state.grid == null:
		return true
	var from_data := from_world
	var to_data := to_world
	if _game_state.coord_map != null and _game_state.coord_map.has_method("to_data"):
		from_data = _game_state.coord_map.to_data(from_world)
		to_data = _game_state.coord_map.to_data(to_world)
	return _game_state.grid.has_line_of_sight(from_data, to_data)


func _character_contributes_perception(char_id: String) -> bool:
	if not _character_is_visible(char_id):
		return false
	if _game_state != null:
		if not _game_state.characters.has(char_id):
			return false
		return not _game_state.is_downed(char_id) and float(_game_state.get_stat(char_id, "hp")) > 0.0
	return float(_character_state.get(char_id, {}).get("hp", 0.0)) > 0.0

func _overlay_vision_source_at(positions: Array[Vector3], index: int) -> Vector3:
	if index >= 0 and index < positions.size():
		return positions[index]
	if not positions.is_empty():
		return positions[0]
	return Vector3(0.0, 0.0, -9999.0)

func _connect_preview_runtime_signals() -> void:
	if _game_state == null:
		return
	if not _game_state.stat_changed.is_connected(_on_gs_stat_changed):
		_game_state.stat_changed.connect(_on_gs_stat_changed)
	if not _game_state.running_changed.is_connected(_on_preview_running_changed):
		_game_state.running_changed.connect(_on_preview_running_changed)
	if not _game_state.damage_shield_changed.is_connected(_on_preview_damage_shield_changed):
		_game_state.damage_shield_changed.connect(_on_preview_damage_shield_changed)
	if not _game_state.damage_absorbed.is_connected(_on_preview_damage_absorbed):
		_game_state.damage_absorbed.connect(_on_preview_damage_absorbed)
	if not _game_state.character_downed.is_connected(_on_preview_character_downed):
		_game_state.character_downed.connect(_on_preview_character_downed)

## The mirror half of the one-truth rule: every gs stat change (combat strikes, drains, restores,
## revives) lands in the HUD ledger — the portraits can never show a fiction again.
func _on_gs_stat_changed(char_id: String, stat: String, value: float) -> void:
	if not _character_state.has(char_id):
		return
	var normalized := _normalize_stat_name(stat)
	if normalized not in ["hp", "sta", "atp"]:
		return
	var previous := float(_character_state[char_id].get(normalized, 0.0))
	_character_state[char_id][normalized] = value
	# Some chunks seed a presentation-only "downed" label alongside canonical
	# GameState data. Once a real revive/restore makes the character conscious,
	# retire that seed so the portrait does not keep lying after HP returns.
	if normalized == "hp" and value > 0.0 \
			and str(_character_state[char_id].get("status", "")) == "downed" \
			and _game_state != null and not _game_state.is_downed(char_id):
		_character_state[char_id]["status"] = ""
	_sync_character_hud(char_id)
	# Damage needs immediate, source-agnostic acknowledgement. This covers enemy
	# strikes, hazards, and zero-ATP scarcity through the same authoritative HP
	# signal instead of requiring every chunk to remember a private HUD effect.
	if normalized == "hp" and value < previous \
			and _hud != null and _hud.has_method("pulse_portrait_damage"):
		_hud.call("pulse_portrait_damage", char_id)
	if normalized == "hp" and previous > 0.0 and value <= 0.0:
		_ensure_valid_selection()

func _on_preview_running_changed(char_id: String, running: bool) -> void:
	if _applying_preview_run_state:
		return
	_sync_preview_run_presenters_from_game_state()
	# GameState ends a sprint exactly on its fixed drain tick. If the active runner exhausted,
	# retire the party intent too so companions do not keep sprinting after the HUD toggle drops.
	if not running and char_id == _active_char_id and _game_state != null \
			and _game_state.get_stat(char_id, "stamina") <= 0.0:
		_run_active = false
		_apply_active_run_state()
		show_preview_message("Stamina exhausted.", 1.2)

func _on_preview_damage_shield_changed(char_id: String, amount: float, source_id: String) -> void:
	if source_id != CanonicalCharacterAbilityScript.WRAP_ID or not _character_state.has(char_id):
		return
	if amount > 0.0:
		set_preview_character_status(char_id, "wrapped")
	elif str(_character_state[char_id].get("status", "")) == "wrapped":
		set_preview_character_status(char_id, "")

func _on_preview_damage_absorbed(
		char_id: String,
		amount: float,
		shield_remaining: float,
		source_id: String
	) -> void:
	if source_id != CanonicalCharacterAbilityScript.WRAP_ID:
		return
	var display_name := str(CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize()))
	show_preview_message("WRAP absorbed %.0f damage for %s (%.0f shield left)." % [
		amount, display_name, shield_remaining,
	], 1.5)

## Scripted downs do not emit stat_changed. Mirror the canonical GameState transition here too,
## so control, HUD state, and the perception roster all hand off in the same frame.
func _on_preview_character_downed(char_id: String) -> void:
	if not _character_state.has(char_id):
		return
	_sync_character_from_game_state(char_id)
	_ensure_valid_selection()
	_refresh_active_overlay()

func _refresh_preview_items() -> void:
	if is_instance_valid(_party_item_controller):
		_party_item_controller.refresh_presenters()
func _refresh_inventory_panel() -> void:
	if _inventory_panel_label == null:
		return
	var lines: Array[String] = []
	var has_inventory_state := false
	for char_id in CHARACTER_IDS:
		var slot_names: Array[String] = []
		for slot in get_preview_hand_slots(char_id):
			slot_names.append("-" if slot == null else get_preview_item_display_name(str(slot), char_id))
		var internal_names: Array[String] = []
		for item_id in get_preview_internal_items(char_id):
			internal_names.append(get_preview_item_display_name(str(item_id), char_id))
		if not slot_names.all(func(value: String) -> bool: return value == "-") or not internal_names.is_empty():
			has_inventory_state = true
		var status := ""
		if _game_state != null and _game_state.is_endocytosing(char_id):
			status = "  |  consuming"
		lines.append("%s  L:%s  R:%s  In:%s%s" % [
			str(CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize())).to_upper(),
			slot_names[0] if slot_names.size() > 0 else "-",
			slot_names[1] if slot_names.size() > 1 else "-",
			", ".join(internal_names) if not internal_names.is_empty() else "-",
			status,
		])

	var active_item := _get_primary_held_item(_active_char_id)
	if active_item != "":
		has_inventory_state = true
		lines.append("Active hold: %s" % get_preview_item_display_name(active_item, _active_char_id))
	else:
		lines.append("Active hold: -")

	var collection_names: Array[String] = []
	for item_id in get_preview_collection_items():
		collection_names.append(get_preview_item_display_name(str(item_id)))
	if not collection_names.is_empty():
		has_inventory_state = true
	lines.append("Collection: %s" % (", ".join(collection_names) if not collection_names.is_empty() else "-"))
	if not has_inventory_state:
		lines = ["No carried items."]
	if _inventory_panel_margin != null:
		# Empty inventory is a compact control drawer, not a permanent diagnostic
		# ledger covering a quarter of the playable ground.
		_inventory_panel_margin.offset_top = -176.0 if not has_inventory_state else -288.0
	_inventory_panel_label.text = "\n".join(lines)

func _get_primary_held_item(char_id: String) -> String:
	return _party_item_controller.get_primary_held_item(char_id) \
		if is_instance_valid(_party_item_controller) else ""

func _consume_active_item() -> void:
	if is_instance_valid(_party_item_controller) and not _active_char_id.is_empty():
		_party_item_controller.consume_primary(_active_char_id)

func _drop_active_item() -> void:
	if is_instance_valid(_party_item_controller) and not _active_char_id.is_empty():
		_party_item_controller.drop_primary(_active_char_id)

func _transfer_active_item() -> void:
	if not is_instance_valid(_party_item_controller) or _active_char_id.is_empty():
		return
	var candidates: Array = _selected_char_ids.duplicate()
	for char_id in CHARACTER_IDS:
		if not candidates.has(char_id):
			candidates.append(char_id)
	_party_item_controller.transfer_primary(_active_char_id, candidates)

func _exocytose_active_item() -> void:
	if is_instance_valid(_party_item_controller) and not _active_char_id.is_empty():
		_party_item_controller.retrieve_primary(_active_char_id)
func _build_game_hud() -> void:
	_hud = GameHUDScene.instantiate()
	add_child(_hud)

	_hud.add_stat_bar("hp", Color(0.72, 0.3, 0.26), DEFAULT_HP, DEFAULT_HP)
	_hud.add_stat_bar("sta", Color(0.3, 0.52, 0.72), DEFAULT_STAMINA, DEFAULT_STAMINA)
	_hud.add_stat_bar("atp", Color(0.34, 0.62, 0.38), DEFAULT_ATP, DEFAULT_ATP)
	_hud.show_pause_toggle(false)
	_hud.show_run_toggle(false, "")
	_hud.show_routing_toggle(_routing_mode)
	_hud.show_center_camera_button("P")
	_hud.pause_toggled.connect(_on_pause_toggled)
	_hud.run_toggled.connect(_on_run_toggled)
	_hud.routing_toggled.connect(_on_routing_toggled)
	_hud.ability_pressed.connect(_on_ability_pressed)
	_hud.center_camera_requested.connect(_on_center_camera_requested)
	if _hud.has_signal("portrait_hold_lock_changed"):
		_hud.connect("portrait_hold_lock_changed", _on_portrait_hold_lock_changed)

	for char_id in CHARACTER_IDS:
		_hud.add_portrait(char_id, CHARACTER_DISPLAY_NAMES[char_id], CHARACTER_COLORS[char_id])
		_hud.set_portrait_stat(char_id, "hp", DEFAULT_HP)
		_hud.set_portrait_stat(char_id, "sta", DEFAULT_STAMINA)
		_hud.set_portrait_stat(char_id, "atp", DEFAULT_ATP)

	_hud.set_multi_select_enabled(true)
	_hud.character_selection_changed.connect(_on_character_selected)
	_hud.show_time(DEFAULT_DAY, DEFAULT_TIME)

func _initialize_default_character_state() -> void:
	# Previews always start from a clean full-stats GameState. This clears
	# any running flags, cancels drain ticks, and resets HP/stamina/ATP for
	# every registered character. Local _character_state then mirrors it.
	if _game_state != null:
		_game_state.reset_characters_to_full()
	_character_state.clear()
	for char_id in CHARACTER_IDS:
		_character_state[char_id] = {
			"hp": DEFAULT_HP,
			"sta": DEFAULT_STAMINA,
			"atp": DEFAULT_ATP,
			"status": "",
			"visible": true,
		}
		if _characters.has(char_id):
			_characters[char_id].visible = true
			_characters[char_id].set_running(false)
			_characters[char_id].set_move_enabled(false)
		_update_character_in_game_state(char_id)
		_sync_character_hud(char_id)
	_run_active = false

func _apply_chunk_runtime_preset() -> void:
	_cancel_preview_runtime_callbacks()
	_preview_runtime_initialized = false
	var chunk_character_state := {}
	var chunk_time_state := {}
	var chunk_abilities: Array = []

	if _active_chunk != null:
		if _active_chunk.has_method("get_preview_character_state"):
			chunk_character_state = _active_chunk.call("get_preview_character_state")
		if _active_chunk.has_method("get_preview_time_state"):
			chunk_time_state = _active_chunk.call("get_preview_time_state")
		if _active_chunk.has_method("get_preview_abilities"):
			chunk_abilities = _active_chunk.call("get_preview_abilities")

	_preview_day = DEFAULT_DAY
	_preview_time = DEFAULT_TIME
	_preview_clock_running = true
	_preview_show_time = true
	_preview_cycle.configure(DEFAULT_DAY_DURATION_SECONDS, DEFAULT_NIGHT_DURATION_SECONDS)
	_routing_mode = "safe"
	_note_default = ""
	_show_default_note = true

	_apply_preview_time_state(chunk_time_state)

	for char_id in CHARACTER_IDS:
		if chunk_character_state.has(char_id):
			_apply_character_override(char_id, chunk_character_state[char_id])

	_configure_preview_abilities(chunk_abilities)
	_capture_preview_runtime_baseline()
	_start_preview_runtime_from_current_preset()
	_refresh_overlay_panel_status()
	_refresh_active_overlay()

func _apply_preview_time_state(state: Dictionary) -> void:
	_preview_clock_running = bool(state.get("advance_time", true))
	_preview_show_time = bool(state.get("show_time", true))
	_preview_cycle.configure(
		float(state.get("day_duration_seconds", DEFAULT_DAY_DURATION_SECONDS)),
		float(state.get("night_duration_seconds", DEFAULT_NIGHT_DURATION_SECONDS))
	)
	if state.is_empty():
		_preview_day = DEFAULT_DAY
		_preview_time = DEFAULT_TIME
	else:
		_preview_day = maxi(int(state.get("day", DEFAULT_DAY)), 1)
		_preview_time = clampf(float(state.get("time", DEFAULT_TIME)), 0.0, 1.0)
		_routing_mode = str(state.get("routing_mode", _routing_mode))
		_show_default_note = bool(state.get("show_default_note", true))
		if state.has("note_default"):
			_note_default = str(state.get("note_default", ""))

	_anchor_preview_clock(_preview_day, _preview_time)
	# The displayed preview clock and shelter/hazard authority must begin from one
	# state. Previously the HUD could render authored night while GameState kept
	# its default daytime value, so a visible REST PARTY command was refused for
	# a condition the player could not observe. This is the explicit preview-preset
	# command boundary; later frames remain analytic projections and do not write.
	if _game_state != null and _game_state.has_method("set_game_clock"):
		_game_state.set_game_clock(_preview_day, _preview_time)
	_sync_preview_time_presentation()

	if _hud != null:
		_hud.set_routing_mode(_routing_mode)

	if state.has("message"):
		show_preview_message(str(state.get("message", "")), float(state.get("message_duration", 2.0)))
	if state.has("note"):
		show_preview_note(str(state.get("note", "")), float(state.get("note_duration", 3.5)))

func _anchor_preview_clock(day: int, time_of_day: float) -> void:
	_preview_clock_anchor_day = maxi(day, 1)
	_preview_clock_anchor_time = clampf(time_of_day, 0.0, 1.0)
	_preview_clock_anchor_tick = get_preview_scheduler_tick()
	_preview_day = _preview_clock_anchor_day
	_preview_time = _preview_clock_anchor_time

## Project, never accumulate: frame rate cannot change the day/time later committed by a shelter.
func _sync_preview_clock_from_authority(update_presentation := false) -> void:
	var next_day := _preview_clock_anchor_day
	var next_time := _preview_clock_anchor_time
	if _preview_clock_running:
		var elapsed := maxf(0.0, get_preview_scheduler_tick() - _preview_clock_anchor_tick)
		var projected: Dictionary = _preview_cycle.advance(
			_preview_clock_anchor_day, _preview_clock_anchor_time, elapsed)
		next_day = int(projected.get("day", next_day))
		next_time = float(projected.get("time", next_time))
	var changed := next_day != _preview_day or absf(next_time - _preview_time) > 0.000001
	_preview_day = next_day
	_preview_time = next_time
	if update_presentation and changed:
		_sync_preview_time_presentation()

func _set_preview_clock_running_authoritative(enabled: bool) -> void:
	_sync_preview_clock_from_authority(false)
	_preview_clock_running = enabled
	_anchor_preview_clock(_preview_day, _preview_time)
	_sync_preview_time_presentation()
	_publish_preview_runtime_authority()

# --- portable preview runtime authority --------------------------------------------------------

func preview_runtime_authority_key() -> String:
	return PREVIEW_RUNTIME_AUTHORITY_KEY

func _capture_preview_runtime_baseline() -> void:
	var abilities := {}
	for ability_id in _ability_order:
		var runtime: Dictionary = _ability_runtime.get(ability_id, {})
		abilities[ability_id] = {
			"state": str(runtime.get("base_state", "ready")),
			"remaining": maxf(0.0, float(runtime.get("remaining", 0.0))),
		}
	_preview_runtime_baseline = {
		"clock": {
			"day": _preview_day,
			"time": _preview_time,
			"running": _preview_clock_running,
			"show_time": _preview_show_time,
			"day_duration_seconds": _preview_cycle.day_duration_seconds,
			"night_duration_seconds": _preview_cycle.night_duration_seconds,
		},
		"abilities": abilities,
	}

func _start_preview_runtime_from_current_preset() -> void:
	_cancel_preview_runtime_callbacks()
	var now := get_preview_scheduler_tick()
	_anchor_preview_clock(_preview_day, _preview_time)
	_preview_stamina_epoch = now
	for ability_id in _ability_order:
		var runtime: Dictionary = _ability_runtime.get(ability_id, {})
		var state := str(runtime.get("base_state", "ready"))
		var remaining := maxf(0.0, float(runtime.get("remaining", 0.0)))
		runtime["deadline"] = now + remaining if state in ["active", "cooldown"] else -1.0
		runtime["remaining"] = remaining
		_ability_runtime[ability_id] = runtime
	_preview_runtime_initialized = true
	_apply_preview_ability_status_presenters()
	_arm_preview_runtime_callbacks()
	_publish_preview_runtime_authority()

func _preview_runtime_authority_state() -> Dictionary:
	var abilities := {}
	for ability_id in _ability_order:
		var runtime: Dictionary = _ability_runtime.get(ability_id, {})
		abilities[ability_id] = {
			"state": str(runtime.get("base_state", "ready")),
			"deadline": float(runtime.get("deadline", -1.0)),
		}
	return {
		"version": PREVIEW_RUNTIME_AUTHORITY_VERSION,
		"chunk": preview_chunk,
		"entry_id": _active_preview_entry_id,
		"clock": {
			"anchor_day": _preview_clock_anchor_day,
			"anchor_time": _preview_clock_anchor_time,
			"anchor_tick": _preview_clock_anchor_tick,
			"running": _preview_clock_running,
			"show_time": _preview_show_time,
			"day_duration_seconds": _preview_cycle.day_duration_seconds,
			"night_duration_seconds": _preview_cycle.night_duration_seconds,
		},
		"stamina_epoch": _preview_stamina_epoch,
		"abilities": abilities,
	}

func _publish_preview_runtime_authority() -> void:
	if not _preview_runtime_initialized or _restoring_preview_runtime or _game_state == null:
		return
	_game_state.set_world_state(preview_runtime_authority_key(), _preview_runtime_authority_state())

func on_game_state_snapshot_restored() -> void:
	_cancel_preview_runtime_callbacks()
	_preview_runtime_initialized = true
	var raw: Variant = _game_state.get_world_state(preview_runtime_authority_key(), null) \
		if _game_state != null else null
	if raw is Dictionary and int(raw.get("version", 0)) == PREVIEW_RUNTIME_AUTHORITY_VERSION \
			and str(raw.get("chunk", preview_chunk)) == preview_chunk:
		_restore_preview_runtime_authority(raw)
	else:
		_restore_preview_runtime_baseline()
	# GameState.deserialize replaced the stat/running ledgers before this presenter hook. Rebuild
	# local mirrors without emitting commands or paying any cost a second time.
	if _game_state != null:
		for char_id_v in _character_state.keys():
			var char_id := str(char_id_v)
			if _game_state.characters.has(char_id):
				_sync_character_from_game_state(char_id)
	_sync_preview_run_presenters_from_game_state()

func _restore_preview_runtime_authority(saved: Dictionary) -> void:
	_restoring_preview_runtime = true
	var clock: Dictionary = saved.get("clock", {}) as Dictionary
	_preview_cycle.configure(
		float(clock.get("day_duration_seconds", DEFAULT_DAY_DURATION_SECONDS)),
		float(clock.get("night_duration_seconds", DEFAULT_NIGHT_DURATION_SECONDS)))
	_preview_clock_anchor_day = maxi(int(clock.get("anchor_day", DEFAULT_DAY)), 1)
	_preview_clock_anchor_time = clampf(float(clock.get("anchor_time", DEFAULT_TIME)), 0.0, 1.0)
	_preview_clock_anchor_tick = float(clock.get("anchor_tick", get_preview_scheduler_tick()))
	_preview_clock_running = bool(clock.get("running", true))
	_preview_show_time = bool(clock.get("show_time", true))
	_preview_stamina_epoch = float(saved.get("stamina_epoch", get_preview_scheduler_tick()))
	if _preview_stamina_epoch < 0.0:
		_preview_stamina_epoch = get_preview_scheduler_tick()
	var saved_abilities: Dictionary = saved.get("abilities", {}) as Dictionary
	for ability_id in _ability_order:
		var entry: Dictionary = saved_abilities.get(ability_id, {}) as Dictionary
		var state := str(entry.get("state", "ready"))
		if state not in ["ready", "active", "cooldown", "disabled"]:
			state = "ready"
		var deadline := float(entry.get("deadline", -1.0)) if state in ["active", "cooldown"] else -1.0
		if deadline < 0.0 and state in ["active", "cooldown"]:
			state = "ready"
		_ability_runtime[ability_id] = {
			"base_state": state,
			"deadline": deadline,
			"remaining": maxf(0.0, deadline - get_preview_scheduler_tick()) if deadline >= 0.0 else 0.0,
		}
	_sync_preview_clock_from_authority(false)
	_apply_preview_ability_status_presenters()
	_restoring_preview_runtime = false
	_arm_preview_runtime_callbacks()
	_sync_preview_time_presentation()
	_refresh_ability_display()

func _restore_preview_runtime_baseline() -> void:
	_restoring_preview_runtime = true
	if _preview_runtime_baseline.is_empty():
		_capture_preview_runtime_baseline()
	var clock: Dictionary = _preview_runtime_baseline.get("clock", {}) as Dictionary
	_preview_cycle.configure(
		float(clock.get("day_duration_seconds", DEFAULT_DAY_DURATION_SECONDS)),
		float(clock.get("night_duration_seconds", DEFAULT_NIGHT_DURATION_SECONDS)))
	_preview_clock_running = bool(clock.get("running", true))
	_preview_show_time = bool(clock.get("show_time", true))
	_anchor_preview_clock(
		maxi(int(clock.get("day", DEFAULT_DAY)), 1),
		clampf(float(clock.get("time", DEFAULT_TIME)), 0.0, 1.0))
	var now := get_preview_scheduler_tick()
	_preview_stamina_epoch = now
	var baseline_abilities: Dictionary = _preview_runtime_baseline.get("abilities", {}) as Dictionary
	for ability_id in _ability_order:
		var entry: Dictionary = baseline_abilities.get(ability_id, {}) as Dictionary
		var state := str(entry.get("state", "ready"))
		var remaining := maxf(0.0, float(entry.get("remaining", 0.0)))
		_ability_runtime[ability_id] = {
			"base_state": state,
			"deadline": now + remaining if state in ["active", "cooldown"] else -1.0,
			"remaining": remaining,
		}
	_apply_preview_ability_status_presenters()
	_restoring_preview_runtime = false
	_arm_preview_runtime_callbacks()
	_sync_preview_time_presentation()
	_refresh_ability_display()

func _apply_preview_ability_status_presenters() -> void:
	for ability_id in _ability_order:
		var ability: Dictionary = _ability_defs.get(ability_id, {})
		var owner := str(ability.get("owner", ""))
		var active_status := str(ability.get("active_status", ""))
		if owner == "" or active_status == "" or not _character_state.has(owner):
			continue
		if str(_ability_runtime.get(ability_id, {}).get("base_state", "ready")) == "active":
			set_preview_character_status(owner, active_status)
		elif str(_character_state[owner].get("status", "")) == active_status:
			set_preview_character_status(owner, "")

func _arm_preview_runtime_callbacks() -> void:
	if _scheduler == null:
		return
	var next_stamina := _next_preview_stamina_tick_after(get_preview_scheduler_tick())
	if next_stamina >= 0.0:
		_schedule_preview_stamina_tick_at(next_stamina)
	for ability_id in _ability_order:
		_arm_preview_ability_deadline(ability_id)

func _cancel_preview_runtime_callbacks() -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(PREVIEW_STAMINA_TAG)
	_preview_stamina_next_tick = -1.0
	for ability_id in _ability_order:
		_scheduler.cancel_tag(_preview_ability_tag(ability_id))

func _sync_preview_time_presentation() -> void:
	if _hud != null:
		if _preview_show_time:
			_hud.show_time(_preview_day, _preview_time)
		else:
			_hud.hide_time()
	_apply_preview_lighting()

func _apply_preview_lighting() -> void:
	if _preview_environment == null or _preview_directional_light == null:
		return

	var normalized := clampf(_preview_time, 0.0, 1.0)
	if normalized < DayNightCycleScript.NIGHT_START:
		var dusk_blend := clampf(normalized / DayNightCycleScript.NIGHT_START, 0.0, 1.0)
		_preview_environment.background_color = Color(0.035, 0.05, 0.075).lerp(Color(0.14, 0.09, 0.06), dusk_blend)
		_preview_environment.ambient_light_color = Color(0.3, 0.36, 0.48).lerp(Color(0.5, 0.33, 0.24), dusk_blend)
		_preview_environment.ambient_light_energy = lerpf(0.62, 0.34, dusk_blend)
		_preview_environment.glow_intensity = lerpf(0.18, 0.28, dusk_blend)
		_preview_directional_light.light_color = Color(0.84, 0.9, 0.98).lerp(Color(0.97, 0.53, 0.26), dusk_blend)
		_preview_directional_light.light_energy = lerpf(1.0, 0.38, dusk_blend)
		_apply_chunk_preview_lighting_profile()
		return

	var night_blend := clampf((normalized - DayNightCycleScript.NIGHT_START) / DayNightCycleScript.SEGMENT_SPAN, 0.0, 1.0)
	_preview_environment.background_color = Color(0.015, 0.02, 0.035).lerp(Color(0.005, 0.008, 0.015), night_blend)
	# Night must still support tactical reading in Web builds, where display black levels and
	# fog-of-war compound. Keep the sky dark, but retain a moonlit ambient floor around the party.
	_preview_environment.ambient_light_color = Color(0.15, 0.19, 0.28).lerp(Color(0.08, 0.11, 0.18), night_blend)
	_preview_environment.ambient_light_energy = lerpf(0.30, 0.20, night_blend)
	_preview_environment.glow_intensity = lerpf(0.28, 0.18, night_blend)
	_preview_directional_light.light_color = Color(0.22, 0.34, 0.58).lerp(Color(0.1, 0.16, 0.3), night_blend)
	_preview_directional_light.light_energy = lerpf(0.24, 0.14, night_blend)
	_apply_chunk_preview_lighting_profile()

## A chunk can preserve a dark authored time while raising the tactical light floor needed by
## its materials and camera. This is applied after the shared day/night curve so it survives
## clock updates and Web compatibility's reduced glow without globally flattening every night.
const _TONEMAP_MODES := {
	"linear": Environment.TONE_MAPPER_LINEAR, "reinhard": Environment.TONE_MAPPER_REINHARDT,
	"filmic": Environment.TONE_MAPPER_FILMIC, "aces": Environment.TONE_MAPPER_ACES,
	"agx": Environment.TONE_MAPPER_AGX,
}

func _apply_chunk_preview_lighting_profile() -> void:
	if _preview_environment == null:
		return
	# Reset the GRADE knobs first so a chunk without a profile (or without these keys)
	# never inherits the previous chunk's filmic tonemap / bloom / fog.
	_preview_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_preview_environment.tonemap_white = 1.0
	_preview_environment.tonemap_exposure = 1.0
	_preview_environment.glow_bloom = 0.0
	_preview_environment.glow_hdr_threshold = 1.0
	_preview_environment.fog_enabled = false
	if _active_chunk == null or not _active_chunk.has_method("get_preview_lighting_profile"):
		return
	var profile_variant = _active_chunk.call("get_preview_lighting_profile")
	if not (profile_variant is Dictionary):
		return
	var profile: Dictionary = profile_variant
	var ambient_floor := float(profile.get("ambient_energy_floor", 0.0))
	var ambient_ceiling := maxf(
		ambient_floor, float(profile.get("ambient_energy_ceiling", 1000000.0))
	)
	_preview_environment.ambient_light_energy = clampf(
		_preview_environment.ambient_light_energy, ambient_floor, ambient_ceiling
	)
	var directional_floor := float(profile.get("directional_energy_floor", 0.0))
	var directional_ceiling := maxf(
		directional_floor, float(profile.get("directional_energy_ceiling", 1000000.0))
	)
	_preview_directional_light.light_energy = clampf(
		_preview_directional_light.light_energy, directional_floor, directional_ceiling
	)
	var glow_floor := float(profile.get("glow_intensity_floor", 0.0))
	var glow_ceiling := maxf(
		glow_floor, float(profile.get("glow_intensity_ceiling", 1000000.0))
	)
	_preview_environment.glow_intensity = clampf(
		_preview_environment.glow_intensity, glow_floor, glow_ceiling
	)
	var background_mix := clampf(float(profile.get("background_mix", 0.0)), 0.0, 1.0)
	if background_mix > 0.0 and profile.has("background_color"):
		var background_target: Color = profile.get(
			"background_color", _preview_environment.background_color
		)
		_preview_environment.background_color = _preview_environment.background_color.lerp(
			background_target, background_mix
		)
	var color_mix := clampf(float(profile.get("color_mix", 0.0)), 0.0, 1.0)
	if color_mix > 0.0 and profile.has("ambient_color"):
		var ambient_target: Color = profile.get("ambient_color", _preview_environment.ambient_light_color)
		_preview_environment.ambient_light_color = _preview_environment.ambient_light_color.lerp(
			ambient_target, color_mix)
	if color_mix > 0.0 and profile.has("directional_color"):
		var directional_target: Color = profile.get("directional_color", _preview_directional_light.light_color)
		_preview_directional_light.light_color = _preview_directional_light.light_color.lerp(
			directional_target, color_mix)
	# The GRADE: a chunk (the interior channels) can pull the whole space into a
	# filmic, bloom-lit mood without touching any other fragment's look.
	_preview_environment.tonemap_mode = _TONEMAP_MODES.get(
		str(profile.get("tonemap_mode", "linear")), Environment.TONE_MAPPER_LINEAR)
	_preview_environment.tonemap_white = float(profile.get("tonemap_white", 1.0))
	_preview_environment.tonemap_exposure = float(profile.get("exposure", 1.0))
	_preview_environment.glow_bloom = float(profile.get("glow_bloom", 0.0))
	_preview_environment.glow_hdr_threshold = float(profile.get("glow_hdr_threshold", 1.0))
	# Atmospheric depth fog: the vast-dark-shaft feel, far geometry fading into the
	# murk. Separate from the perception fog-of-war (a screen shader); this is the
	# Environment's own depth fog and works on both renderers.
	if float(profile.get("fog_density", 0.0)) > 0.0:
		_preview_environment.fog_enabled = true
		_preview_environment.fog_density = float(profile.get("fog_density", 0.0))
		_preview_environment.fog_light_color = profile.get("fog_color", Color(0.05, 0.08, 0.12))
		_preview_environment.fog_light_energy = float(profile.get("fog_energy", 1.0))
		_preview_environment.fog_sky_affect = float(profile.get("fog_sky_affect", 0.0))
		_preview_environment.fog_aerial_perspective = float(profile.get("fog_aerial", 0.4))

func _apply_character_override(char_id: String, override: Dictionary) -> void:
	if not _character_state.has(char_id):
		return

	if override.has("hp"):
		_character_state[char_id]["hp"] = clampf(float(override.get("hp", DEFAULT_HP)), 0.0, DEFAULT_HP)
	if override.has("sta"):
		_character_state[char_id]["sta"] = clampf(float(override.get("sta", DEFAULT_STAMINA)), 0.0, DEFAULT_STAMINA)
	if override.has("stamina"):
		_character_state[char_id]["sta"] = clampf(float(override.get("stamina", DEFAULT_STAMINA)), 0.0, DEFAULT_STAMINA)
	if override.has("atp"):
		_character_state[char_id]["atp"] = GameState.clamp_atp(float(override.get("atp", DEFAULT_ATP)))
	if override.has("status"):
		_character_state[char_id]["status"] = str(override.get("status", ""))
	if override.has("visible"):
		_character_state[char_id]["visible"] = bool(override.get("visible", true))

	if _characters.has(char_id):
		_characters[char_id].visible = bool(_character_state[char_id].get("visible", true))

	_update_character_in_game_state(char_id)
	_sync_character_hud(char_id)

## Canonical cast-ability fallback content + mechanics, sourced from the abilities xlsx (the "default"
## context for content and the bindings sheet for owner/keybind/color/stamina cost/status). Chunk-provided
## entries may tune those canonical abilities for a scenario but cannot add a new cast ability.
func _build_default_ability_definitions() -> Dictionary:
	var defs := {}
	for ability_id in AbilityData.ABILITY_ORDER:
		var d := {"id": ability_id}
		d.merge(AbilityData.get_ability("default." + ability_id), true)  # display_name, duration, cooldown, message, note
		d = _apply_canonical_main_ability_binding(ability_id, d)         # owner, keybind, keycode, color, stamina cost, status
		defs[ability_id] = d
	return defs

func _configure_preview_abilities(chunk_abilities: Array) -> void:
	_cancel_preview_ability_targeting()
	_ability_defs.clear()
	_ability_runtime.clear()
	_ability_order.clear()
	if _hud != null and _hud.has_method("clear_abilities"):
		_hud.call("clear_abilities")

	var default_defs := _build_default_ability_definitions()
	for ability_id in AbilityData.ABILITY_ORDER:
		var def: Dictionary = default_defs[ability_id].duplicate(true)
		def = _apply_canonical_main_ability_binding(ability_id, def)
		_ability_defs[ability_id] = def
		_ability_order.append(ability_id)

	for entry in chunk_abilities:
		if not (entry is Dictionary):
			continue
		var entry_dict: Dictionary = entry
		var ability_id := str(entry_dict.get("id", ""))
		if ability_id == "" or not AbilityData.is_canonical_ability(ability_id):
			continue
		var merged: Dictionary = _ability_defs.get(ability_id, {}).duplicate(true)
		merged.merge(entry_dict, true)
		merged = _apply_canonical_main_ability_binding(ability_id, merged)
		_ability_defs[ability_id] = merged
		if not _ability_order.has(ability_id):
			_ability_order.append(ability_id)

	_assign_party_ability_routes()
	for ability_id in _ability_order:
		var ability: Dictionary = _ability_defs[ability_id]
		_ability_runtime[ability_id] = {
			"base_state": str(ability.get("initial_state", "ready")),
			"remaining": float(ability.get("initial_remaining", 0.0)),
			"deadline": -1.0,
		}
		if (
			_hud != null
			and int(ability.get("party_slot", -1)) >= 0
			and int(ability.get("ability_slot", -1)) >= 0
		):
			_hud.add_ability(
				ability_id,
				str(ability.get("display_name", ability_id.to_upper())),
				str(ability.get("keybind", "")),
				ability.get("color", Color(0.7, 0.7, 0.75)),
				str(ability.get("input_action", "")),
				str(ability.get("owner", "")),
				str(ability.get("owner_display", "")),
				int(ability.get("party_slot", -1)),
				int(ability.get("ability_slot", -1))
			)

	_refresh_ability_display()

func _ability_owner_id(ability_id: String, ability: Dictionary) -> String:
	var owner := str(ability.get("owner", "")).strip_edges().to_lower()
	if owner != "":
		return owner
	var prefix := ability_id.get_slice("_", 0).strip_edges().to_lower()
	if prefix in PARTY_ABILITY_OWNER_ORDER or prefix in CHARACTER_IDS or prefix in OPT_IN_CHARACTER_IDS:
		return prefix
	# Ownerless/global abilities still need a deterministic drawer home without pretending one of
	# the named protagonists owns them.
	return "party"

func _capture_legacy_ability_binding(ability: Dictionary) -> void:
	if not ability.has("legacy_input_action"):
		ability["legacy_input_action"] = str(ability.get("input_action", ""))
	if not ability.has("legacy_keybind"):
		ability["legacy_keybind"] = str(ability.get("keybind", ""))
	if not ability.has("legacy_keycode"):
		ability["legacy_keycode"] = int(ability.get("keycode", 0))

func _legacy_ability_binding_label(ability: Dictionary) -> String:
	var fallback := str(ability.get("legacy_keybind", ability.get("keybind", "")))
	var legacy_action := str(ability.get("legacy_input_action", ""))
	return InputHints.label_for_action(legacy_action, fallback) if legacy_action != "" else fallback

func _set_party_ability_route(ability_id: String, party_slot: int, ability_slot: int) -> void:
	var ability: Dictionary = _ability_defs.get(ability_id, {})
	var legacy_label := _legacy_ability_binding_label(ability)
	ability["party_slot"] = party_slot
	ability["ability_slot"] = ability_slot
	if (
		party_slot >= 0
		and party_slot < PARTY_ABILITY_ACTIONS.size()
		and ability_slot >= 0
		and ability_slot < 2
	):
		var actions: Array = PARTY_ABILITY_ACTIONS[party_slot]
		var direct_action := str(actions[ability_slot])
		ability["input_action"] = direct_action
		ability["keybind"] = InputHints.label_for_action(direct_action, legacy_label)
	else:
		ability["input_action"] = ""
		ability["keybind"] = legacy_label
	_ability_defs[ability_id] = ability

## Resolve party columns independently of selection. Known protagonists retain the same column even
## when a particular fragment hides another member; future owners are sorted into columns five/six.
## Within a column explicit zero-based ability_slot values win, then remaining abilities fill 0, 1.
func _assign_party_ability_routes() -> void:
	var abilities_by_owner := {}
	for ability_id in _ability_order:
		var ability: Dictionary = _ability_defs.get(ability_id, {})
		_capture_legacy_ability_binding(ability)
		var owner := _ability_owner_id(ability_id, ability)
		ability["owner"] = owner
		ability["owner_display"] = str(CHARACTER_DISPLAY_NAMES.get(owner, owner.capitalize()))
		_ability_defs[ability_id] = ability
		if not abilities_by_owner.has(owner):
			abilities_by_owner[owner] = []
		(abilities_by_owner[owner] as Array).append(ability_id)

	var ordered_owners: Array[String] = []
	for owner_v in PARTY_ABILITY_OWNER_ORDER:
		var owner := str(owner_v)
		if abilities_by_owner.has(owner):
			ordered_owners.append(owner)
	var extra_owners: Array[String] = []
	for owner_v in abilities_by_owner.keys():
		var owner := str(owner_v)
		if owner not in PARTY_ABILITY_OWNER_ORDER:
			extra_owners.append(owner)
	extra_owners.sort()
	ordered_owners.append_array(extra_owners)

	var owner_party_slots := {}
	for owner in ordered_owners:
		var known_slot := PARTY_ABILITY_OWNER_ORDER.find(owner)
		if known_slot >= 0:
			owner_party_slots[owner] = known_slot
		else:
			var extra_slot := PARTY_ABILITY_OWNER_ORDER.size() + extra_owners.find(owner)
			if extra_slot < PARTY_ABILITY_ACTIONS.size():
				owner_party_slots[owner] = extra_slot

	for owner in ordered_owners:
		var ids: Array = abilities_by_owner.get(owner, [])
		var party_slot := int(owner_party_slots.get(owner, -1))
		if party_slot < 0:
			for ability_id_v in ids:
				_set_party_ability_route(str(ability_id_v), -1, -1)
			push_warning("The six party ability columns are full; owner '%s' has no direct slot." % owner)
			continue

		var assigned := {}
		var pending: Array[String] = []
		# Reserve valid explicit rows before assigning any automatic rows.
		for ability_id_v in ids:
			var ability_id := str(ability_id_v)
			var ability: Dictionary = _ability_defs.get(ability_id, {})
			var requested := int(ability.get("ability_slot", -1))
			if requested >= 0 and requested < 2 and not assigned.has(requested):
				assigned[requested] = ability_id
				_set_party_ability_route(ability_id, party_slot, requested)
			else:
				pending.append(ability_id)
		for ability_id in pending:
			var open_slot := -1
			for candidate in range(2):
				if not assigned.has(candidate):
					open_slot = candidate
					break
			if open_slot < 0:
				_set_party_ability_route(ability_id, -1, -1)
				push_warning("Ability owner '%s' has more than two abilities; '%s' stays legacy-only." % [
					owner,
					ability_id,
				])
				continue
			assigned[open_slot] = ability_id
			_set_party_ability_route(ability_id, party_slot, open_slot)

## Apply an ability's MECHANICS from the abilities xlsx bindings sheet (owner / keybind / keycode / color /
## stamina_cost / active_status) — the canonical, per-ability-id values that do not change per context.
func _apply_canonical_main_ability_binding(ability_id: String, ability: Dictionary) -> Dictionary:
	var binding := AbilityData.binding(ability_id)
	if binding.is_empty():
		_capture_legacy_ability_binding(ability)
		return ability
	ability["owner"] = str(binding.get("owner", ability.get("owner", "")))
	var legacy_keybind := str(binding.get("keybind", ability.get("keybind", ""))).to_upper()
	var legacy_input_action := str(ABILITY_INPUT_ACTION_BY_KEYBIND.get(legacy_keybind, ""))
	ability["legacy_input_action"] = legacy_input_action
	ability["legacy_keybind"] = legacy_keybind
	ability["keybind"] = (
		InputHints.label_for_action(legacy_input_action, legacy_keybind)
		if legacy_input_action != ""
		else legacy_keybind
	)
	var input_event := (
		InputHints.primary_event_for_action(legacy_input_action, "keyboard")
		if legacy_input_action != ""
		else null
	)
	if input_event is InputEventKey:
		var key_event := input_event as InputEventKey
		ability["legacy_keycode"] = (
			key_event.physical_keycode
			if key_event.physical_keycode != KEY_NONE
			else key_event.keycode
		)
	else:
		ability["legacy_keycode"] = int(binding.get("keycode", ability.get("keycode", 0)))
	ability["keycode"] = int(ability.get("legacy_keycode", 0))
	for k in ["color", "stamina_cost", "active_status"]:
		if binding.has(k):
			ability[k] = binding[k]
	return ability

func _apply_chunk_metadata() -> void:
	var title := scene_title_override
	var generation_fallback := {}
	if _active_chunk != null and _active_chunk.has_method("get_generation_fallback_state"):
		generation_fallback = _active_chunk.call("get_generation_fallback_state")
	# A run-menu title must never hide that the requested generator settings failed.
	if bool(generation_fallback.get("active", false)) and _active_chunk.has_method("get_scene_title"):
		title = str(_active_chunk.call("get_scene_title"))
	if title == "":
		title = preview_chunk.capitalize() + " Fragment"
		if _active_chunk != null and _active_chunk.has_method("get_scene_title"):
			title = str(_active_chunk.call("get_scene_title"))

	var help := ""
	if _active_chunk != null and _active_chunk.has_method("get_scene_help"):
		help = str(_active_chunk.call("get_scene_help"))

	if _title_label != null:
		_title_label.text = title
	if _help_label != null:
		_help_label.text = help
		_help_label.visible = help != ""
	_refresh_control_hint_flow()
	_refresh_ability_hint_flow()

	if _show_default_note and _note_default == "":
		_note_default = "All three characters start topped off. Run and cast abilities spend stamina; ATP pays for shelter rest unless an experimental scarcity preset is selected."
	if _note_timer <= 0.0:
		_restore_default_note()


func _restore_default_note() -> void:
	if _note_label == null:
		return
	_note_label.text = _note_default if _show_default_note else ""
	if _status_margin != null:
		_status_margin.visible = _show_default_note

func _position_party_for_chunk() -> void:
	var positions := DEFAULT_SPAWNS.duplicate(true)
	if _active_chunk != null and _active_chunk.has_method("get_spawn_positions"):
		positions.merge(_active_chunk.call("get_spawn_positions"), true)

	for char_id in CHARACTER_IDS:
		if positions.has(char_id):
			headless_set_character_position(char_id, positions[char_id])

## Honour a chunk's PartyPresence node (if any): hide absent members so they
## can't be selected or moved. No node / empty map => keep the full roster.
func _apply_chunk_party_presence() -> void:
	var presence: Dictionary = {}
	if _active_chunk != null and _active_chunk.has_method("get_party_presence"):
		var p: Variant = _active_chunk.call("get_party_presence")
		if p is Dictionary:
			presence = p
	_apply_opt_in_members(presence)
	if presence.is_empty():
		return
	for char_id in CHARACTER_IDS:
		if presence.has(char_id):
			set_preview_character_visible(char_id, bool(presence[char_id]))

## Opt-in members exist only while a chunk's presence map includes them. Registration is
## the load-bearing part: an absent member must NOT be in GameState at all.
func _apply_opt_in_members(presence: Dictionary) -> void:
	if _game_state == null:
		return
	var spawns := DEFAULT_SPAWNS.duplicate(true)
	if _active_chunk != null and _active_chunk.has_method("get_spawn_positions"):
		spawns.merge(_active_chunk.call("get_spawn_positions"), true)
	for cid_v in OPT_IN_CHARACTER_IDS:
		var char_id := str(cid_v)
		var want := bool(presence.get(char_id, false))
		var have: bool = _game_state.characters.has(char_id)
		if want and not have:
			_register_gs_character(char_id, _characters.get(char_id), CHARACTER_SPEEDS[char_id], {
				"hp": DEFAULT_HP,
				"stamina": DEFAULT_STAMINA,
				"atp": DEFAULT_ATP,
			})
			if _characters.get(char_id) != null and _characters[char_id].has_method("bind_interaction_root"):
				_characters[char_id].call("bind_interaction_root", self)
			_character_state[char_id] = {"hp": DEFAULT_HP, "sta": DEFAULT_STAMINA, "atp": DEFAULT_ATP,
				"status": "", "visible": true}
			if _hud != null:
				_hud.add_portrait(char_id, CHARACTER_DISPLAY_NAMES[char_id], CHARACTER_COLORS[char_id])
			if spawns.has(char_id):
				headless_set_character_position(char_id, spawns[char_id])
			set_preview_character_visible(char_id, true)
			_sync_character_hud(char_id)
		elif not want and have:
			set_preview_character_visible(char_id, false)
			_game_state.unregister_character(char_id)
			_character_state.erase(char_id)
			if _hud != null:
				_hud.remove_portrait(char_id)
		elif want and have:
			set_preview_character_visible(char_id, true)

func _default_chunk_character() -> String:
	var default_id := "aster"
	if _active_chunk != null and _active_chunk.has_method("get_default_character"):
		default_id = str(_active_chunk.call("get_default_character"))
	if _character_is_available(default_id):
		return default_id
	for char_id in CHARACTER_IDS:
		if _character_is_available(char_id):
			return char_id
	return "aster"

func _cycle_character() -> void:
	if _active_char_id == "":
		_select_character(_default_chunk_character())
		return

	var cycle_ids: Array[String] = _selected_char_ids.duplicate()
	if cycle_ids.size() <= 1:
		cycle_ids.clear()
		for char_id in CHARACTER_IDS + OPT_IN_CHARACTER_IDS:
			if _character_is_available(char_id):
				cycle_ids.append(char_id)
	if cycle_ids.size() <= 1:
		return

	var start_index := cycle_ids.find(_active_char_id)
	for offset in range(1, cycle_ids.size() + 1):
		var next_id: String = cycle_ids[(start_index + offset) % cycle_ids.size()]
		if _character_is_available(next_id):
			_select_character(next_id)
			return

func _toggle_pause() -> void:
	_on_pause_toggled(not (_scheduler != null and _scheduler.is_paused()))

func _toggle_run() -> void:
	_on_run_toggled(not _run_active)

func _select_character(char_id: String) -> void:
	if not _characters.has(char_id):
		return
	if not _character_is_available(char_id):
		return
	var next_selected: Array = [char_id]
	if _selected_char_ids.has(char_id):
		next_selected = _selected_char_ids.duplicate()
	_apply_selection_state(next_selected, char_id)

func _toggle_character_selected(char_id: String) -> void:
	if not _characters.has(char_id) or not _character_is_available(char_id):
		return
	var next_selected := _selected_char_ids.duplicate()
	if next_selected.has(char_id):
		if next_selected.size() <= 1:
			show_preview_message("Keep one character selected.", 1.1)
			return
		next_selected.erase(char_id)
	else:
		next_selected.append(char_id)
	var preferred_active := _active_char_id
	if not next_selected.has(preferred_active) and not next_selected.is_empty():
		preferred_active = next_selected[0]
	_apply_selection_state(next_selected, preferred_active)

func _apply_selection_state(selected_ids: Array, preferred_active := "") -> void:
	var sanitized := _sanitize_selected_ids(selected_ids)
	if sanitized.is_empty():
		var fallback := preferred_active
		if fallback == "" or not _character_is_available(fallback):
			fallback = _active_char_id if _character_is_available(_active_char_id) else _default_chunk_character()
		if fallback == "":
			return
		sanitized = [fallback]

	var next_active := preferred_active
	if next_active == "" or not sanitized.has(next_active):
		next_active = sanitized[0]

	var selection_changed := _selected_char_ids != sanitized
	_selected_char_ids = sanitized
	if _active_char_id != next_active:
		_set_active_character(next_active)
	else:
		_sync_active_stat_panel()
		_refresh_ability_display()
		_refresh_active_overlay()

	if _hud != null:
		_sync_hud_selection()
	if selection_changed:
		var selected_names: Array[String] = []
		for char_id in _selected_char_ids:
			selected_names.append(str(CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize())))
		show_preview_message("Selected: %s" % ", ".join(selected_names), 1.1)
	# Re-wire click-to-move for the new selection (party move when >1 selected). Runs on EVERY
	# selection change, including adding a member while the active stays put (where _set_active_character
	# early-returns and would otherwise leave group_move stale).
	_apply_group_control()
	_apply_active_run_state()
	_refresh_overlay_panel_status()
	_update_survival_overlay()

func _set_active_character(char_id: String) -> void:
	if _active_char_id == char_id:
		return
	_cancel_preview_ability_targeting()

	if _active_char_id != "" and _characters.has(_active_char_id):
		var previous: CharacterBody3D = _characters[_active_char_id]
		previous.restore_move_input_enabled(false)
		previous.set_running(false)
		if _game_state != null and _game_state.characters.has(_active_char_id):
			var walk_speed := float(CHARACTER_SPEEDS[_active_char_id])
			if not is_equal_approx(
					float(_game_state.characters[_active_char_id].get("move_speed", walk_speed)),
					walk_speed):
				_game_state.change_move_speed(_active_char_id, walk_speed)

	_active_char_id = char_id
	_player = _characters[char_id]
	_sync_character_move_enabled()
	if _occlusion_mgr != null:
		# Publish the new reveal centre in the same input frame. Directly replacing watch_id leaves
		# autonomous playback with one rendered frame cut around the previously focused character.
		_occlusion_mgr.set_watch(_game_state, char_id)
	if _camera != null:
		_camera.target = _player

	_apply_active_run_state()
	_sync_active_stat_panel()
	_refresh_ability_display()
	_refresh_active_overlay()

	for interactable in _preview_interactables:
		if interactable != null and is_instance_valid(interactable):
			interactable.active_character = _active_char_id

	if _active_chunk != null and _active_chunk.has_method("on_preview_character_selected"):
		_active_chunk.call("on_preview_character_selected", char_id)

func _sync_character_move_enabled() -> void:
	# Opt-in companions use the same Player controller as the launch roster. Leaving one out here
	# keeps its controller live after selecting somebody else, so both bodies answer one right-click
	# and the late arrival can steal a timed action's actor.
	for char_id in CHARACTER_IDS + OPT_IN_CHARACTER_IDS:
		var character_node = _characters.get(char_id, null)
		if character_node != null and character_node.has_method("restore_move_input_enabled"):
			character_node.call("restore_move_input_enabled", char_id == _active_char_id)

## Push the dodge-roll setting onto every party member's stats. Off (the default) means enemy strikes
## land; on means they can auto-evade. Derived preview state — set from a toggle, not the data log.
func _apply_dodge_setting() -> void:
	if _game_state == null:
		return
	for char_id in CHARACTER_IDS:
		if _game_state.characters.has(char_id):
			var st: Dictionary = _game_state.characters[char_id].stats
			st["dodge_unlocked"] = _preview_dodge_unlocked
			st["auto_dodge"] = _preview_dodge_unlocked

## Wire click-to-move for the current selection. With more than one selected, the party moves as one:
## the active character's controller issues a spread party move (set_party + group_move on the active
## node only), and the others are carried by that move, not their own clicks. Single select: just the
## active character moves. Mirrors the elevator's _apply_character_control_selection.
func _apply_group_control() -> void:
	var nodes := {}
	for char_id in CHARACTER_IDS + OPT_IN_CHARACTER_IDS:
		nodes[char_id] = _characters.get(char_id, null)
	_apply_party_control(nodes, _selected_char_ids, _active_char_id, _selected_char_ids.size() > 1)

func _sanitize_selected_ids(selected_ids: Array) -> Array[String]:
	var sanitized: Array[String] = []
	for raw_id in selected_ids:
		var char_id := str(raw_id)
		if char_id not in CHARACTER_IDS + OPT_IN_CHARACTER_IDS:
			continue
		if not _character_is_available(char_id):
			continue
		if sanitized.has(char_id):
			continue
		sanitized.append(char_id)
	return sanitized

func _sync_hud_selection() -> void:
	if _hud == null:
		return
	_suppress_hud_character_signal = true
	_hud.set_selected_portraits(_selected_char_ids)
	if _active_char_id != "":
		_hud.set_active_portrait(_active_char_id, true)
	_suppress_hud_character_signal = false

func _ensure_valid_selection() -> void:
	var sanitized := _sanitize_selected_ids(_selected_char_ids)
	var preferred_active := _active_char_id
	if preferred_active == "" or not _character_is_available(preferred_active):
		preferred_active = sanitized[0] if not sanitized.is_empty() else ""
	_apply_selection_state(sanitized, preferred_active)

func _apply_active_run_state() -> void:
	# Run is a PARTY intent: every SELECTED member that can run does, so a group move (the channels gauntlet)
	# crosses a surge TOGETHER instead of stranding everyone but the leader at a walk. Members out of stamina
	# fall back to a walk individually. The toggle reads "off" if the leader is spent (that drives the UI).
	if _active_char_id != "" and _characters.has(_active_char_id) \
			and get_preview_character_stat(_active_char_id, "sta") <= 0.0:
		_run_active = false
	var ids: Array = _selected_char_ids.duplicate() if not _selected_char_ids.is_empty() else [_active_char_id]
	_applying_preview_run_state = true
	for cid_v in CHARACTER_IDS + OPT_IN_CHARACTER_IDS:
		var cid := str(cid_v)
		if cid == "" or not _characters.has(cid):
			continue
		var node: CharacterBody3D = _characters[cid]
		var can_run: bool = ids.has(cid) and _run_active and _character_is_available(cid) \
			and get_preview_character_stat(cid, "sta") > 0.0
		if _game_state != null and _game_state.characters.has(cid):
			if _game_state.is_running(cid) != can_run:
				_game_state.set_running(cid, can_run)
			var desired_speed: float = node.run_speed if can_run else float(
				CHARACTER_SPEEDS.get(cid, node.move_speed))
			if not is_equal_approx(float(_game_state.characters[cid].get("move_speed", desired_speed)), desired_speed):
				_game_state.change_move_speed(cid, desired_speed)
		node.set_running(can_run)
	_applying_preview_run_state = false
	_sync_preview_run_presenters_from_game_state()

func _sync_preview_run_presenters_from_game_state() -> void:
	if _game_state == null:
		return
	for cid_v in CHARACTER_IDS + OPT_IN_CHARACTER_IDS:
		var cid := str(cid_v)
		if not _characters.has(cid) or not _game_state.characters.has(cid):
			continue
		var running := _game_state.is_running(cid)
		var node = _characters[cid]
		if node != null and node.has_method("set_running"):
			node.call("set_running", running)
	_run_active = _active_char_id != "" and _game_state.characters.has(_active_char_id) \
		and _game_state.is_running(_active_char_id)
	if _hud != null:
		_hud.set_run_mode(_run_active)

func _on_run_toggled(is_running: bool) -> void:
	_run_active = is_running and _character_is_available(_active_char_id) and get_preview_character_stat(_active_char_id, "sta") > 0.0
	_apply_active_run_state()

func _on_pause_toggled(is_paused: bool) -> void:
	if _scheduler == null:
		return
	if is_paused:
		_scheduler.pause()
	else:
		_scheduler.resume()
	if _active_chunk != null and _active_chunk.has_method("set_preview_planning_feedback"):
		_active_chunk.call("set_preview_planning_feedback", _scheduler.is_paused())
	if _hud != null:
		_hud.set_paused(_scheduler.is_paused())

func _on_routing_toggled(mode: String) -> void:
	_routing_mode = "direct" if mode == "direct" else "safe"
	# The HUD is only a projection of the authoritative routing policy. Keeping
	# this in preview-only state made SAFE labels issue DIRECT GameState plans,
	# invalidating both player feedback and survival timing measurements.
	if _game_state != null \
			and bool(_game_state.is_route_cautious()) != (_routing_mode == "safe"):
		_game_state.set_route_mode(_routing_mode == "safe")
	if _hud != null:
		_hud.set_routing_mode(_routing_mode)
	show_preview_message("Routing: %s" % _routing_mode.to_upper(), 1.2)
	if _active_chunk != null and _active_chunk.has_method("on_preview_routing_changed"):
		_active_chunk.call("on_preview_routing_changed", _routing_mode)

func _on_character_selected(selected_ids: Array) -> void:
	if _suppress_hud_character_signal:
		return
	var preferred_active := str(selected_ids[0]) if selected_ids.size() > 0 else ""
	_apply_selection_state(selected_ids, preferred_active)

func _on_portrait_hold_lock_changed(char_id: String, locked: bool) -> void:
	var display_name := str(CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize()))
	var hold_label := "their post"
	if _hud != null and _hud.has_method("get_portrait_hold_state"):
		var info = _hud.call("get_portrait_hold_state", char_id)
		if info is Dictionary:
			hold_label = str(info.get("label", hold_label)).to_lower()
	if locked:
		show_preview_message("%s locked at %s — whole-party rallies leave them in place." % [display_name, hold_label], 2.4)
	else:
		show_preview_message("%s unlocked — whole-party rallies include them again." % display_name, 2.0)

func _on_ability_pressed(ability_id: String) -> void:
	_activate_preview_ability(ability_id)

## Recenter the camera on the whole available party. Warped chunks may provide a safe target because
## a Euclidean average of points around a coil can sit inside its solid core. No-ops if a scripted
## focus holds the camera.
func _on_center_camera_requested() -> void:
	if _camera == null or not _camera.has_method("recenter_on"):
		return
	var safe_chunk_target = null
	if _active_chunk != null and _active_chunk.has_method("get_preview_camera_recenter_target"):
		var chunk_target = _active_chunk.call("get_preview_camera_recenter_target")
		if chunk_target is Dictionary:
			var target_info := chunk_target as Dictionary
			if not bool(target_info.get("allowed", true)):
				show_preview_message(str(target_info.get("message", "Camera is following the action.")), 1.8)
				return
			safe_chunk_target = target_info
	if _camera.is_locked():
		show_preview_message("Camera is following the action.", 1.4)
		return
	if safe_chunk_target is Dictionary:
		var safe_target = (safe_chunk_target as Dictionary).get("target", null)
		if safe_target is Vector3 and (safe_target as Vector3).is_finite():
			_camera.recenter_on(safe_target as Vector3)
			show_preview_message(str((safe_chunk_target as Dictionary).get(
				"message", "Camera centered on the party")), 1.0)
			return
	var sum := Vector3.ZERO
	var n := 0
	for char_id in CHARACTER_IDS:
		if not _character_is_available(char_id):
			continue
		var node = _characters.get(char_id, null)
		if node == null or not is_instance_valid(node):
			continue
		sum += (node as Node3D).global_position
		n += 1
	if n == 0:
		return
	_camera.recenter_on(sum / float(n))
	show_preview_message("Camera centered on the party", 1.0)

func _on_preview_move_command_refused(char_id: String, reason: String) -> void:
	if _web_e2e_controller != null:
		_web_e2e_controller.record_move_refusal(char_id, reason)
	var display_name := str(CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize()))
	show_preview_message("%s — %s" % [display_name, reason], 2.2)

func _activate_preview_ability(ability_id: String) -> void:
	var failure := _preview_ability_cast_failure(ability_id)
	if failure != "":
		show_preview_message(failure, 1.3)
		return
	_begin_preview_ability_targeting(ability_id)

func _begin_preview_ability_targeting(ability_id: String) -> void:
	_cancel_preview_ability_targeting()
	_pending_targeted_ability_id = ability_id
	if _player != null and _player.has_method("set_click_mode"):
		_player.call("set_click_mode", "select")
	show_preview_message(CanonicalCharacterAbilityScript.target_prompt(ability_id), 4.0)

func _cancel_preview_ability_targeting() -> void:
	_pending_targeted_ability_id = ""
	for character_node in _characters.values():
		if character_node != null and is_instance_valid(character_node) \
				and character_node.has_method("set_click_mode"):
			character_node.call("set_click_mode", "move")

func _on_preview_ability_target_clicked(world_pos: Vector3) -> void:
	if _pending_targeted_ability_id == "":
		return
	var ability_id := _pending_targeted_ability_id
	_cancel_preview_ability_targeting()
	_execute_preview_ability(ability_id, world_pos)

func _preview_ability_cast_failure(ability_id: String) -> String:
	if not AbilityData.is_canonical_ability(ability_id) \
			or not _ability_defs.has(ability_id) or not _ability_runtime.has(ability_id):
		return "That is not a cast ability. Use contextual actions on their world targets."
	var ability: Dictionary = _ability_defs[ability_id]
	var runtime: Dictionary = _ability_runtime[ability_id]
	var owner := str(ability.get("owner", ""))
	if owner != "" and not _character_is_available(owner):
		return "%s is unavailable." % CHARACTER_DISPLAY_NAMES.get(owner, owner.capitalize())
	if str(runtime.get("base_state", "ready")) != "ready":
		return "%s is not ready." % str(ability.get("display_name", ability_id.to_upper()))
	var stamina_cost := float(ability.get("stamina_cost", 0.0))
	if owner != "" and get_preview_character_stat(owner, "sta") < stamina_cost:
		return "%s needs %.0f stamina." % [
			CHARACTER_DISPLAY_NAMES.get(owner, owner.capitalize()), stamina_cost,
		]
	return ""

func _available_preview_party_ids() -> Array:
	var result: Array = []
	for char_id in CHARACTER_IDS + OPT_IN_CHARACTER_IDS:
		if _character_is_available(char_id):
			result.append(char_id)
	return result

func _execute_preview_ability(
		ability_id: String,
		world_pos: Vector3,
		explicit_target_id := ""
	) -> bool:
	var failure := _preview_ability_cast_failure(ability_id)
	if failure != "":
		show_preview_message(failure, 1.3)
		return false

	var ability: Dictionary = _ability_defs[ability_id]
	var owner := str(ability.get("owner", ""))
	var result: Dictionary = {}
	match ability_id:
		CanonicalCharacterAbilityScript.EMP_ID:
			var emp_duration := float(ability.get(
				"duration", CanonicalCharacterAbilityScript.EMP_STUN_SECONDS))
			if emp_duration <= 0.0:
				emp_duration = CanonicalCharacterAbilityScript.EMP_STUN_SECONDS
			result = CanonicalCharacterAbilityScript.execute(
				_game_state, ability_id, owner, world_pos,
				{"world_root": self, "duration": emp_duration})
		CanonicalCharacterAbilityScript.WRAP_ID:
			var party_ids := _available_preview_party_ids()
			var target_id := explicit_target_id
			if target_id == "":
				target_id = CanonicalCharacterAbilityScript.nearest_party_target(
					_game_state, party_ids, world_pos)
			var wrap_duration := float(ability.get(
				"duration", CanonicalCharacterAbilityScript.WRAP_DURATION_SECONDS))
			if wrap_duration <= 0.0:
				wrap_duration = CanonicalCharacterAbilityScript.WRAP_DURATION_SECONDS
			result = CanonicalCharacterAbilityScript.execute(
				_game_state, ability_id, owner, world_pos, {
					"target_id": target_id,
					"allowed_target_ids": party_ids,
					"duration": wrap_duration,
				})
		_:
			return false

	if not bool(result.get("accepted", false)):
		var reason := str(result.get("reason", "invalid_target"))
		match reason:
			"out_of_range":
				show_preview_message("Target is outside %s's cast range." % [
					CHARACTER_DISPLAY_NAMES.get(owner, owner.capitalize()),
				], 1.4)
			_:
				show_preview_message("Choose a conscious party member as the WRAP target.", 1.6)
		return false

	if ability_id == CanonicalCharacterAbilityScript.EMP_ID:
		var affected_count := int(result.get("affected_count", 0))
		if affected_count > 0:
			show_preview_message("EMP disabled %d compatible electronic%s." % [
				affected_count, "" if affected_count == 1 else "s",
			], 2.0)
		else:
			show_preview_message(
				"EMP fired, but no EMP-compatible electronics were inside the pulse.", 2.2)
	else:
		var target_id := str(result.get("target_id", ""))
		var target_name := str(CHARACTER_DISPLAY_NAMES.get(target_id, target_id.capitalize()))
		show_preview_message("Peris WRAPs %s: %.0f incoming damage can be absorbed." % [
			target_name, float(result.get("absorption_each", 0.0)),
		], 2.2)

	var duration := float(ability.get("duration", 0.0))
	var cooldown := float(ability.get("cooldown", 0.0))
	var next_state := "active" if duration > 0.0 else ("cooldown" if cooldown > 0.0 else "ready")
	var remaining := duration if next_state == "active" else cooldown
	_set_runtime_ability_state(ability_id, next_state, remaining)
	return true

func _set_runtime_ability_state(ability_id: String, state: String, remaining := 0.0) -> void:
	if not _ability_runtime.has(ability_id):
		return
	var deadline := -1.0
	if state in ["active", "cooldown"]:
		deadline = get_preview_scheduler_tick() + maxf(0.0, remaining)
	_set_runtime_ability_state_at(ability_id, state, deadline)

func _set_runtime_ability_state_at(
		ability_id: String,
		state: String,
		deadline: float,
		cancel_existing_callback := true
	) -> void:
	if not _ability_runtime.has(ability_id):
		return
	var previous_state := str(_ability_runtime[ability_id].get("base_state", "ready"))
	var ability: Dictionary = _ability_defs.get(ability_id, {})
	var owner := str(ability.get("owner", ""))
	var active_status := str(ability.get("active_status", ""))

	_ability_runtime[ability_id]["base_state"] = state
	_ability_runtime[ability_id]["deadline"] = deadline if state in ["active", "cooldown"] else -1.0
	_ability_runtime[ability_id]["remaining"] = _preview_ability_remaining(ability_id)

	if owner != "":
		if state == "active" and active_status != "":
			set_preview_character_status(owner, active_status)
		elif previous_state == "active" and active_status != "" and str(_character_state.get(owner, {}).get("status", "")) == active_status:
			set_preview_character_status(owner, "")

	_arm_preview_ability_deadline(ability_id, cancel_existing_callback)
	_publish_preview_runtime_authority()
	_refresh_ability_display(ability_id)

func _preview_ability_remaining(ability_id: String) -> float:
	if not _ability_runtime.has(ability_id):
		return 0.0
	var runtime: Dictionary = _ability_runtime[ability_id]
	if str(runtime.get("base_state", "ready")) not in ["active", "cooldown"]:
		return 0.0
	return maxf(0.0, float(runtime.get("deadline", -1.0)) - get_preview_scheduler_tick())

func _preview_ability_tag(ability_id: String) -> String:
	return PREVIEW_ABILITY_TAG_PREFIX + ability_id

func _arm_preview_ability_deadline(ability_id: String, cancel_existing := true) -> void:
	if _scheduler == null:
		return
	# A callback is removed from the scheduler as it dispatches. Cancelling that same tag from inside
	# its callback corrupts EventScheduler's pending-count bookkeeping; only replacement/restore paths
	# need to cancel a callback that is still genuinely queued.
	if cancel_existing:
		_scheduler.cancel_tag(_preview_ability_tag(ability_id))
	if not _ability_runtime.has(ability_id):
		return
	var runtime: Dictionary = _ability_runtime[ability_id]
	var state := str(runtime.get("base_state", "ready"))
	var deadline := float(runtime.get("deadline", -1.0))
	if state not in ["active", "cooldown"] or deadline < 0.0:
		return
	_scheduler.schedule_at(
		maxf(get_preview_scheduler_tick(), deadline),
		_on_preview_ability_deadline.bind(ability_id, deadline),
		_preview_ability_tag(ability_id)
	)

func _on_preview_ability_deadline(ability_id: String, expected_deadline: float) -> void:
	if not _ability_runtime.has(ability_id):
		return
	var runtime: Dictionary = _ability_runtime[ability_id]
	if not is_equal_approx(float(runtime.get("deadline", -1.0)), expected_deadline):
		return
	var state := str(runtime.get("base_state", "ready"))
	if state == "active":
		var cooldown := maxf(0.0, float(_ability_defs.get(ability_id, {}).get("cooldown", 0.0)))
		if cooldown > 0.0:
			_set_runtime_ability_state_at(
				ability_id, "cooldown", expected_deadline + cooldown, false)
		else:
			_set_runtime_ability_state_at(ability_id, "ready", -1.0, false)
	elif state == "cooldown":
		_set_runtime_ability_state_at(ability_id, "ready", -1.0, false)

func _refresh_ability_display(ability_id := "") -> void:
	if _hud == null:
		return

	var ids: Array[String] = []
	if ability_id == "":
		for current_id in _ability_order:
			ids.append(current_id)
	else:
		ids.append(String(ability_id))
	for current_id in ids:
		if not _ability_defs.has(current_id) or not _ability_runtime.has(current_id):
			continue

		var ability: Dictionary = _ability_defs[current_id]
		var runtime: Dictionary = _ability_runtime[current_id]
		var owner := str(ability.get("owner", ""))
		var display_state := str(runtime.get("base_state", "ready"))
		var display_remaining := _preview_ability_remaining(current_id)

		if owner != "":
			if not _character_is_available(owner):
				display_state = "disabled"
				display_remaining = 0.0
			elif display_state == "ready":
				var stamina_cost := float(ability.get("stamina_cost", 0.0))
				if get_preview_character_stat(owner, "sta") < stamina_cost:
					display_state = "disabled"
					display_remaining = 0.0

		_hud.set_ability_state(current_id, display_state, display_remaining)

func _pressed_party_ability_action(event: InputEvent) -> String:
	for row_v in PARTY_ABILITY_ACTIONS:
		var row: Array = row_v
		for action_v in row:
			var action := str(action_v)
			if event.is_action_pressed(action):
				return action
	return ""

func _is_party_ability_action(input_action: String) -> bool:
	for row_v in PARTY_ABILITY_ACTIONS:
		var row: Array = row_v
		if row.has(input_action):
			return true
	return false

func _input_action_is_bound(input_action: String) -> bool:
	return (
		input_action != ""
		and InputMap.has_action(input_action)
		and not InputMap.action_get_events(input_action).is_empty()
	)

func _get_ability_for_keycode(keycode: int) -> String:
	var fallback := ""
	for ability_id in _ability_order:
		var ability: Dictionary = _ability_defs.get(ability_id, {})
		# A direct 6x2 binding supersedes this ability's spreadsheet key. Until then the old keycode
		# remains a selection-aware compatibility route.
		if _input_action_is_bound(str(ability.get("input_action", ""))):
			continue
		var mapped_keycode := int(ability.get("legacy_keycode", ability.get("keycode", 0)))
		if mapped_keycode == 0:
			var keybind := str(ability.get("legacy_keybind", ability.get("keybind", ""))).to_upper()
			mapped_keycode = int(ABILITY_KEYCODES.get(keybind, 0))
		if mapped_keycode == keycode:
			if str(ability.get("owner", "")) == _active_char_id:
				return ability_id
			if fallback == "":
				fallback = ability_id
	return fallback

func _get_ability_for_input_action(input_action: String) -> String:
	if _is_party_ability_action(input_action):
		for ability_id in _ability_order:
			var ability: Dictionary = _ability_defs.get(ability_id, {})
			if str(ability.get("input_action", "")) == input_action:
				return ability_id
		return ""

	var fallback := ""
	for ability_id in _ability_order:
		var ability: Dictionary = _ability_defs.get(ability_id, {})
		if str(ability.get("legacy_input_action", "")) != input_action:
			continue
		if _input_action_is_bound(str(ability.get("input_action", ""))):
			continue
		if str(ability.get("owner", "")) == _active_char_id:
			return ability_id
		if fallback == "":
			fallback = ability_id
	return fallback

func _activate_action_bound_preview_ability(input_action: String) -> bool:
	var ability_id := _get_ability_for_input_action(input_action)
	if ability_id == "":
		return false
	_activate_preview_ability(ability_id)
	return true

func _activate_keybound_preview_ability(keycode: int) -> bool:
	var ability_id := _get_ability_for_keycode(keycode)
	if ability_id == "":
		return false
	_activate_preview_ability(ability_id)
	return true

func _schedule_preview_stamina_tick_at(deadline: float, cancel_existing := true) -> void:
	if _scheduler == null or _preview_stamina_epoch < 0.0:
		return
	if cancel_existing:
		_scheduler.cancel_tag(PREVIEW_STAMINA_TAG)
	_preview_stamina_next_tick = deadline
	_scheduler.schedule_at(
		maxf(get_preview_scheduler_tick(), deadline),
		_on_preview_stamina_tick.bind(deadline), PREVIEW_STAMINA_TAG)

func _on_preview_stamina_tick(expected_tick: float) -> void:
	if not is_equal_approx(_preview_stamina_next_tick, expected_tick):
		return
	_preview_stamina_next_tick = -1.0
	_apply_preview_stamina_tick()
	_schedule_preview_stamina_tick_at(expected_tick + PREVIEW_STAMINA_TICK, false)

func _apply_preview_stamina_tick() -> void:
	if _game_state == null:
		return
	for char_id_v in _character_state.keys():
		var char_id := str(char_id_v)
		if not _game_state.characters.has(char_id) or not _character_is_available(char_id):
			continue
		# GameState owns sprint drain. The preview cadence only supplies the authored recovery policy.
		if _game_state.is_running(char_id) or not _stamina_field_regen_allowed(char_id):
			continue
		var rate := STAMINA_REGEN * (0.35 if _game_state.is_moving(char_id) else 1.0)
		var current := _game_state.get_stat(char_id, "stamina")
		var next := minf(
			_game_state.get_stat_cap(char_id, "stamina"),
			current + rate * PREVIEW_STAMINA_TICK)
		if next > current + 0.000001:
			_game_state.set_stat(char_id, "stamina", next)

func _next_preview_stamina_tick_after(tick: float) -> float:
	if _preview_stamina_epoch < 0.0:
		return -1.0
	return FixedCadenceScript.next_strict_tick(
		_preview_stamina_epoch, PREVIEW_STAMINA_TICK, tick)

## A tension level can CLOSE the field stamina economy (fragment params.stamina_field_regen=false):
## the bar then only comes back on SHELTER ground — havens are recovery points, the field is scarce,
## and "do I have enough stamina for this plan" is a real question. Default: the legacy open economy.
func _stamina_field_regen_allowed(char_id: String) -> bool:
	if _active_chunk != null and _active_chunk.has_method("preview_field_stamina_regen"):
		if not bool(_active_chunk.call("preview_field_stamina_regen")):
			return _game_state != null and _game_state.is_at_shelter(char_id)
	return true

func _update_character_in_game_state(char_id: String) -> void:
	if _game_state == null or not _game_state.characters.has(char_id):
		return
	var runtime_char: Dictionary = _game_state.characters[char_id]
	var stats: Dictionary = runtime_char.get("stats", {}).duplicate(true)
	stats["hp"] = float(_character_state.get(char_id, {}).get("hp", DEFAULT_HP))
	stats["stamina"] = float(_character_state.get(char_id, {}).get("sta", DEFAULT_STAMINA))
	stats["atp"] = float(_character_state.get(char_id, {}).get("atp", DEFAULT_ATP))
	runtime_char["stats"] = stats

func _sync_character_from_game_state(char_id: String) -> void:
	if _game_state == null or not _game_state.characters.has(char_id) or not _character_state.has(char_id):
		return
	var runtime_char: Dictionary = _game_state.characters[char_id]
	var stats: Dictionary = runtime_char.get("stats", {})
	_character_state[char_id]["hp"] = float(stats.get("hp", DEFAULT_HP))
	_character_state[char_id]["sta"] = float(stats.get("stamina", DEFAULT_STAMINA))
	_character_state[char_id]["atp"] = float(stats.get("atp", DEFAULT_ATP))
	_sync_character_hud(char_id)

func _sync_character_hud(char_id: String) -> void:
	if _hud == null or not _character_state.has(char_id):
		return

	var state: Dictionary = _character_state[char_id]
	_hud.set_portrait_stat(char_id, "hp", float(state.get("hp", DEFAULT_HP)))
	_hud.set_portrait_stat(char_id, "sta", float(state.get("sta", DEFAULT_STAMINA)))
	_hud.set_portrait_stat(char_id, "atp", float(state.get("atp", DEFAULT_ATP)))

	var display_status := str(state.get("status", ""))
	if not bool(state.get("visible", true)):
		display_status = "offline"
	elif float(state.get("hp", 0.0)) <= 0.0 and display_status == "":
		display_status = "downed"
	_hud.set_portrait_status(char_id, display_status)
	_hud.set_portrait_alert(char_id, float(state.get("hp", DEFAULT_HP)) <= 35.0 or float(state.get("sta", DEFAULT_STAMINA)) <= 20.0)

	if char_id == _active_char_id:
		_sync_active_stat_panel()
	_refresh_overlay_panel_status()
	_update_survival_overlay()

func _sync_active_stat_panel() -> void:
	if _hud == null or _active_char_id == "" or not _character_state.has(_active_char_id):
		return
	var state: Dictionary = _character_state[_active_char_id]
	_hud.set_stat("hp", float(state.get("hp", DEFAULT_HP)))
	_hud.set_stat("sta", float(state.get("sta", DEFAULT_STAMINA)))
	_hud.set_stat("atp", float(state.get("atp", DEFAULT_ATP)))
	_update_survival_overlay()

func _normalize_stat_name(stat_name: String) -> String:
	match stat_name.strip_edges().to_lower():
		"hp", "health":
			return "hp"
		"sta", "stamina":
			return "sta"
		"atp":
			return "atp"
		_:
			return stat_name.strip_edges().to_lower()

func _character_is_visible(char_id: String) -> bool:
	if not _character_state.has(char_id):
		return false
	return bool(_character_state[char_id].get("visible", true))

func _character_is_available(char_id: String) -> bool:
	if not _character_state.has(char_id):
		return false
	return _character_is_visible(char_id) and float(_character_state[char_id].get("hp", 0.0)) > 0.0
