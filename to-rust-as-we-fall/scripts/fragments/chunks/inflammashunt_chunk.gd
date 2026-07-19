extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## THE INFLAMMASHUNT (danger zone; canonical spec data/puzzles/inflammashunt_puzzle.md, shadow
## path inflammashunt_shadow_solution.md): the Resolution Catalyst retrieval — the Manage
## Conflict puzzle. Three character-coded INFORMATION routes feed a shared eight-interactable
## junction room; every route report is honest and confidently WRONG; the correct solve is
## "water, clean, clean, tend, open". Route info is EFFICIENCY, not a gate (informed holds are
## short, uninformed holds are long); every wrong approach teaches exactly one rule and is
## recoverable without a reload (the hostile-root herding sub-puzzle is the largest recovery).
## The survival clock is OFF in here — danger is local state, not day/night attrition
## (GDD §10.2). Myke's value is information: scraping is general labor, so Aster+Peris can
## shadow-solve by reconstructing route C from routes A+B plus junction observation.

# --- Geometry (single floor; grid cs 1.5, origin z -16.5) ---
const APPROACH_X1 := 16.0
const HUB_X0 := 16.0
const HUB_X1 := 27.0
const HUB_HALF_Z := 6.0
const JCT_X0 := 30.0
const JCT_X1 := 55.5
const JCT_HALF_Z := 8.5
const ROUTE_X0 := 19.0
const ROUTE_X1 := 25.0
const POCKET := [29.5, 35.5, -14.5, -10.0]   # myke's crawl pocket [x0, x1, z0, z1]

const CHAR_A_POS := Vector3(34.0, 0.0, -2.0)
const CHAR_B_POS := Vector3(44.0, 0.0, 5.0)
const ROOT_BASE_POS := Vector3(45.2, 0.0, 5.8)
const VALVE_POS := Vector3(38.0, 0.6, -7.4)
const TERMINAL_POS := Vector3(42.0, 0.6, -7.4)
const RING_CENTER := Vector3(48.0, 0.0, 1.5)
const FLORA_POS := Vector3(32.5, 0.0, 6.8)
const HOUSING_POS := Vector3(51.5, 0.0, 5.5)
const GRATE_POS := Vector3(53.2, 0.0, 5.5)

# --- Tuning (spec values) ---
const SAC_DURATION := 22.0
const SAC_AURA := 3.0
const ROOT_CAPTURE_RADIUS := 1.5
const ROOT_RETRACT_DELAY := 1.0
const ROOT_REGROW_DELAY := 4.0
const RAGE_SECS := 16.0
const BUFFER_REFORM_SECS := 4.0
const POPCORN_DPS_TICK := 2.5
const HazardFieldScript := preload("res://scripts/game/objects/hazard_field.gd")
const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")

# The device housing is the end of the original five-step puzzle, but not the end of
# the level.  A live Resolution Catalyst cannot simply be carried out through the
# fire-damaged branch: the party must recommission its four support loops and seat it
# in the insulated extraction cradle.  Every site is spatial, click-gated work.  No
# phase advances from dialogue, elapsed time, or a platform-specific fallback.
const COMMISSIONING_EVIDENCE_SECONDS := 9.0
const COMMISSIONING_DECISION_SECONDS := 8.0
const COMMISSIONING_EXECUTION_SECONDS := 14.0
const EXTRACTION_WORK_SECONDS := 16.0
const COMMISSIONING_PROTOCOL_ORDER := ["coolant", "root_return", "buffer", "transfer"]
const COMMISSIONING_CLEAN_CHOICES := {
	"coolant": "coolant_balanced_feed",
	"root_return": "root_capillary_feed",
	# The wet lane is also the Aster+Peris shadow solution.  With Myke present the
	# dry-burn lane remains a distinct, equally valid specialist branch.
	"buffer": "buffer_wet_lane",
	"transfer": "transfer_linked_clock",
}
const COMMISSIONING_PROTOCOLS := {
	"coolant": {
		"label": "FLUSH LOOP / 01",
		"category": "hydraulic_recommissioning",
		"evidence": [
			{"id": "coolant_inlet_trace", "pos": Vector3(63.0, 0.5, -7.0), "role": "aster", "verb": "TRACE INLET", "kind": "data"},
			{"id": "coolant_root_sample", "pos": Vector3(68.0, 0.5, 6.5), "role": "peris", "verb": "SAMPLE RETURN", "kind": "root"},
			{"id": "coolant_pressure_read", "pos": Vector3(73.0, 0.5, -5.5), "role": "aster", "verb": "READ PRESSURE", "kind": "data"},
			{"id": "coolant_biofilm_read", "pos": Vector3(78.0, 0.5, 7.5), "role": "peris", "verb": "READ BIOFILM", "kind": "root"},
			{"id": "coolant_crossfeed_trace", "pos": Vector3(83.0, 0.5, -3.5), "role": "aster", "verb": "TRACE CROSSFEED", "kind": "data"},
		],
		"choices": [
			{"id": "coolant_balanced_feed", "pos": Vector3(88.0, 0.5, -7.0), "role": "aster", "verb": "BALANCE FEED", "kind": "decision"},
			{"id": "coolant_root_priority", "pos": Vector3(88.0, 0.5, 7.0), "role": "peris", "verb": "PRIORITIZE ROOT", "kind": "decision"},
		],
		"resolutions": {
			"coolant_balanced_feed": {"id": "coolant_metered_flush", "pos": Vector3(94.0, 0.5, -5.5), "role": "aster", "verb": "METER FLUSH", "kind": "execution"},
			"coolant_root_priority": {"id": "coolant_living_flush", "pos": Vector3(94.0, 0.5, 5.5), "role": "peris", "verb": "TEND FLUSH", "kind": "execution"},
		},
	},
	"root_return": {
		"label": "ROOT RETURN / 02",
		"category": "living_network_balance",
		"evidence": [
			{"id": "return_capillary_sample", "pos": Vector3(101.0, 0.5, 7.0), "role": "peris", "verb": "SAMPLE CAPILLARY", "kind": "root"},
			{"id": "return_load_trace", "pos": Vector3(106.0, 0.5, -6.5), "role": "aster", "verb": "TRACE LOAD", "kind": "data"},
			{"id": "return_growth_read", "pos": Vector3(111.0, 0.5, 5.5), "role": "peris", "verb": "READ GROWTH", "kind": "root"},
			{"id": "return_valve_scan", "pos": Vector3(116.0, 0.5, -7.5), "role": "aster", "verb": "SCAN VALVE", "kind": "data"},
			{"id": "return_pulse_map", "pos": Vector3(121.0, 0.5, 3.5), "role": "peris", "verb": "MAP PULSE", "kind": "root"},
		],
		"choices": [
			{"id": "root_capillary_feed", "pos": Vector3(126.0, 0.5, 7.0), "role": "peris", "verb": "FEED CAPILLARY", "kind": "decision"},
			{"id": "root_bypass_feed", "pos": Vector3(126.0, 0.5, -7.0), "role": "aster", "verb": "OPEN BYPASS", "kind": "decision"},
		],
		"resolutions": {
			"root_capillary_feed": {"id": "root_tend_return", "pos": Vector3(132.0, 0.5, 5.5), "role": "peris", "verb": "TEND RETURN", "kind": "execution"},
			"root_bypass_feed": {"id": "root_meter_bypass", "pos": Vector3(132.0, 0.5, -5.5), "role": "aster", "verb": "METER BYPASS", "kind": "execution"},
		},
	},
	"buffer": {
		"label": "BUFFER PERIMETER / 03",
		"category": "buffer_containment",
		"evidence": [
			{"id": "buffer_thermal_read", "pos": Vector3(139.0, 0.5, -7.0), "role": "aster", "verb": "READ THERMAL", "kind": "data"},
			{"id": "buffer_husk_sample", "pos": Vector3(144.0, 0.5, 6.5), "role": "peris", "verb": "SAMPLE HUSK", "kind": "root"},
			{"id": "buffer_gap_trace", "pos": Vector3(149.0, 0.5, -5.5), "role": "aster", "verb": "TRACE GAP", "kind": "data"},
			{"id": "buffer_filament_read", "pos": Vector3(154.0, 0.5, 7.5), "role": "peris", "verb": "READ FILAMENT", "kind": "root"},
			{"id": "buffer_airflow_scan", "pos": Vector3(159.0, 0.5, -3.5), "role": "aster", "verb": "SCAN AIRFLOW", "kind": "data"},
		],
		"choices": [
			{"id": "buffer_dry_burn_lane", "pos": Vector3(164.0, 0.5, -7.0), "role": "myke", "verb": "MARK BURN LANE", "kind": "decision"},
			{"id": "buffer_wet_lane", "pos": Vector3(164.0, 0.5, 7.0), "role": "aster", "verb": "MARK WET LANE", "kind": "decision"},
		],
		"resolutions": {
			"buffer_dry_burn_lane": {"id": "buffer_burn_break", "pos": Vector3(170.0, 0.5, -5.5), "role": "myke", "verb": "BURN BREAK", "kind": "execution"},
			"buffer_wet_lane": {"id": "buffer_scrape_break", "pos": Vector3(170.0, 0.5, 5.5), "role": "aster", "verb": "SCRAPE BREAK", "kind": "execution"},
		},
	},
	"transfer": {
		"label": "TRANSFER CLOCK / 04",
		"category": "catalyst_transfer",
		"evidence": [
			{"id": "transfer_root_clock", "pos": Vector3(177.0, 0.5, 7.0), "role": "peris", "verb": "READ ROOT CLOCK", "kind": "root"},
			{"id": "transfer_phase_trace", "pos": Vector3(182.0, 0.5, -6.5), "role": "aster", "verb": "TRACE PHASE", "kind": "data"},
			{"id": "transfer_membrane_read", "pos": Vector3(187.0, 0.5, 5.5), "role": "peris", "verb": "READ MEMBRANE", "kind": "root"},
			{"id": "transfer_cradle_scan", "pos": Vector3(192.0, 0.5, -7.5), "role": "aster", "verb": "SCAN CRADLE", "kind": "data"},
			{"id": "transfer_pulse_match", "pos": Vector3(197.0, 0.5, 3.5), "role": "peris", "verb": "MATCH PULSE", "kind": "root"},
		],
		"choices": [
			{"id": "transfer_linked_clock", "pos": Vector3(202.0, 0.5, 7.0), "role": "peris", "verb": "LINK CLOCK", "kind": "decision"},
			{"id": "transfer_isolated_clock", "pos": Vector3(202.0, 0.5, -7.0), "role": "aster", "verb": "ISOLATE CLOCK", "kind": "decision"},
		],
		"resolutions": {
			"transfer_linked_clock": {"id": "transfer_living_sync", "pos": Vector3(208.0, 0.5, 5.5), "role": "peris", "verb": "SYNC TRANSFER", "kind": "execution"},
			"transfer_isolated_clock": {"id": "transfer_machine_sync", "pos": Vector3(208.0, 0.5, -5.5), "role": "aster", "verb": "SYNC TRANSFER", "kind": "execution"},
		},
	},
}
const EXTRACTION_POS := Vector3(219.0, 0.5, 0.0)
const ROLE_WALK_SPEEDS := {"aster": 3.2, "peris": 3.0, "myke": 3.1}
const COMMISSIONING_DECORATION_PROFILE := {
	"id": "inflammashunt_commissioning",
	"x0": 56.0,
	"x1": 224.0,
	"width": 28.0,
	"wall_height": 4.8,
	"ground_y": 0.0,
	"seed": 0x1F1A5A,
	"program": "hydraulic",
	"spacing": 10.5,
	"floor_tile": "deck_metal",
	"wall_tile": "rust_iron",
	"floor_tint": Color(0.12, 0.14, 0.15),
	"wall_tint": Color(0.17, 0.15, 0.14),
	"trim": Color(0.40, 0.38, 0.34),
	"inset": Color(0.045, 0.050, 0.055),
	"service": Color(0.20, 0.23, 0.22),
	"rust": Color(0.40, 0.16, 0.065),
	"glow": Color(0.36, 0.91, 0.50),
	"light": Color(0.45, 0.53, 0.43),
	"signs": ["RESOLUTION SERVICE / 01", "LIVING RETURN SPINE", "CATALYST TRANSFER  >"],
}

## Hold-time table (spec "Route Information As Efficiency"): [with info, without info].
const HOLDS := {
	"valve": [2.5, 14.0],
	"char_a": [2.0, 10.0],
	"char_b": [2.5, 11.0],
	"root": [2.5, 12.0],
}

# --- Core state model (spec field names; exposed via headless_get_state) ---
var route_info := {
	"aster_log": false,
	"aster_pipe_diagram": false,
	"peris_dead_roots": false,
	"peris_living_junction": false,
	"myke_char_feed": false,
	"myke_buffer_ring": false,
}
var valve_open := false
var char_a_state := "dry"        # dry, damp, cleared, burned
var char_b_state := "dry"
var root_state := "suppressed"   # suppressed, tame, hostile, recovering, connected
var buffer_state := "stable"     # stable, shattered, reforming
var gas_sac_state := "idle"      # idle, tended, carried, expired, ignited
var healing_zone := 0.0
var housing_unlocked := false
var device_retrieved := false
var wrong_events: Array = []
var long_hold_count := 0

var _party: Array = ["aster", "peris", "myke"]
var _entry_played := false
var _reports := {}               # route -> true once the confident wrong answer played
var _reunion_played := false
var _popcorn := false
var _popcorn_field = null
var _sac_carrier := ""
var _sac_expires := -1.0
var _sac_visual: MeshInstance3D
var _rage_until := -1.0
var _raged := {}                 # chelator id -> true while in the woken encounter
var _extra_chelators: Array = []
var _root_enemy: ChainEnemy
var _whip_ready := {}
var _polls_armed := false
var _healing_glow: MeshInstance3D
var _char_a_mesh: MeshInstance3D
var _char_b_mesh: MeshInstance3D
var _husks: Array = []

var _valve_it: Area3D
var _char_a_it: Area3D
var _char_b_it: Area3D
var _root_it: Area3D
var _flora_it: Area3D
var _take_sac_it: Area3D
var _terminal_it: Area3D
var _reset_it: Area3D
var _housing_it: Area3D
var _examine_it: Area3D
var _strike_it: Area3D
var _observe_it: Area3D
var _commissioning_sites := {}
var _commissioning_evidence := {}
var _commissioning_choices := {}
var _commissioning_resolved := {}
var _commissioning_completed_actions: Array[String] = []
var _commissioning_phase := "locked"
var _extraction_it: Area3D
var _decoration_audit := {}

func get_scene_title() -> String:
	return "The Inflammashunt (danger zone)"

func get_default_character() -> String:
	return "aster"

func configure_chunk(config: Dictionary) -> void:
	super.configure_chunk(config)
	if config.has("party"):
		_party = (config["party"] as Array).duplicate()

## The presence map drives the host's opt-in roster (myke exists only where a chunk asks).
func get_party_presence() -> Dictionary:
	return {
		"aster": _party.has("aster"),
		"peris": _party.has("peris"),
		"endo": _party.has("endo"),
		"myke": _party.has("myke"),
	}

func _build_chunk() -> void:
	fragment = _inflammashunt_fragment()
	super._build_chunk()
	_build_approach()
	_build_routes()
	_build_junction_room()
	_build_commissioning_gallery()
	_spawn_active_chelators()
	_refresh_hold_times()
	_decoration_audit = LevelDecoratorScript.decorate_corridor(self, COMMISSIONING_DECORATION_PROFILE)

func _update(delta: float) -> void:
	super._update(delta)
	_ensure_polls()

# --- The fragment (floors, walls, grid, spawns) ---

func _inflammashunt_fragment() -> Fragment:
	var frag := Fragment.new()
	frag.id = "inflammashunt"
	frag.title = "The Inflammashunt"
	frag.help = "Myke's old corridors. Salvageable working tech somewhere past the burn damage."
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(_party)
	var spawn_slots := {
		"aster": Vector3(4.0, 0.5, 0.0),
		"peris": Vector3(2.5, 0.5, 1.6),
		"myke": Vector3(2.5, 0.5, -1.6),
		"endo": Vector3(1.0, 0.5, 0.0),
	}
	frag.spawns = {}
	for cid in _party:
		if spawn_slots.has(cid):
			frag.spawns[cid] = spawn_slots[cid]
	var scorch := Color(0.09, 0.08, 0.075)
	frag.floors = [
		{"pos": Vector3(8.0, -0.05, 0.0), "size": Vector3(16.0, 0.1, 6.4), "color": scorch, "tile": "deck_metal"},
		{"pos": Vector3(21.5, -0.05, 0.0), "size": Vector3(11.0, 0.1, HUB_HALF_Z * 2.0), "color": scorch, "tile": "deck_metal"},
		{"pos": Vector3(22.0, -0.05, -9.75), "size": Vector3(6.5, 0.1, 7.9), "color": scorch, "tile": "deck_metal"},
		{"pos": Vector3(22.0, -0.05, 9.75), "size": Vector3(6.5, 0.1, 7.9), "color": Color(0.08, 0.09, 0.08), "tile": "deck_metal"},
		{"pos": Vector3(28.5, -0.05, 0.0), "size": Vector3(3.5, 0.1, 3.2), "color": scorch, "tile": "deck_metal"},
		{"pos": Vector3(42.75, -0.05, 0.0), "size": Vector3(25.5, 0.1, JCT_HALF_Z * 2.0), "color": Color(0.1, 0.095, 0.09), "tile": "deck_metal"},
		{"pos": Vector3(32.5, -0.05, -12.25), "size": Vector3(6.0, 0.1, 4.5), "color": Color(0.07, 0.065, 0.06), "tile": "deck_metal"},
		# The measured service gallery begins at the housing's east threshold.
		{"pos": Vector3(140.0, -0.05, 0.0), "size": Vector3(168.0, 0.1, 28.0), "color": Color(0.105, 0.11, 0.115), "tile": "deck_metal"},
	]
	var wallc := Color(0.06, 0.055, 0.05)
	frag.walls = [
		{"pos": Vector3(8.0, 1.5, 3.3), "size": Vector3(16.0, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(8.0, 1.5, -3.3), "size": Vector3(16.0, 3.0, 0.4), "color": wallc},
		# hub shell (gaps: south+north route doors, east junction door)
		{"pos": Vector3(17.8, 1.5, -6.2), "size": Vector3(4.6, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(25.6, 1.5, -6.2), "size": Vector3(3.6, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(17.8, 1.5, 6.2), "size": Vector3(4.6, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(25.6, 1.5, 6.2), "size": Vector3(3.6, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(27.2, 1.5, -4.0), "size": Vector3(0.4, 3.0, 4.6), "color": wallc},
		{"pos": Vector3(27.2, 1.5, 4.0), "size": Vector3(0.4, 3.0, 4.6), "color": wallc},
		# route shells
		{"pos": Vector3(18.8, 1.5, -9.75), "size": Vector3(0.4, 3.0, 7.9), "color": wallc},
		{"pos": Vector3(25.2, 1.5, -9.75), "size": Vector3(0.4, 3.0, 7.9), "color": wallc},
		{"pos": Vector3(22.0, 1.5, -13.9), "size": Vector3(6.8, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(18.8, 1.5, 9.75), "size": Vector3(0.4, 3.0, 7.9), "color": wallc},
		{"pos": Vector3(25.2, 1.5, 9.75), "size": Vector3(0.4, 3.0, 7.9), "color": wallc},
		{"pos": Vector3(22.0, 1.5, 13.9), "size": Vector3(6.8, 3.0, 0.4), "color": wallc},
		# junction shell
		{"pos": Vector3(42.75, 1.5, -8.9), "size": Vector3(25.5, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(42.75, 1.5, 8.9), "size": Vector3(25.5, 3.0, 0.4), "color": wallc},
		# split around the service-gallery threshold
		{"pos": Vector3(55.9, 1.5, -6.0), "size": Vector3(0.4, 3.0, 6.2), "color": wallc},
		{"pos": Vector3(55.9, 1.5, 6.0), "size": Vector3(0.4, 3.0, 6.2), "color": wallc},
		{"pos": Vector3(29.8, 1.5, -5.25), "size": Vector3(0.4, 3.0, 7.3), "color": wallc},
		{"pos": Vector3(29.8, 1.5, 5.25), "size": Vector3(0.4, 3.0, 7.3), "color": wallc},
		# the crawl pocket's sealed shell
		{"pos": Vector3(32.5, 1.2, -9.8), "size": Vector3(6.4, 2.4, 0.4), "color": wallc},
		{"pos": Vector3(32.5, 1.2, -14.7), "size": Vector3(6.4, 2.4, 0.4), "color": wallc},
		{"pos": Vector3(29.3, 1.2, -12.25), "size": Vector3(0.4, 2.4, 4.9), "color": wallc},
		{"pos": Vector3(35.7, 1.2, -12.25), "size": Vector3(0.4, 2.4, 4.9), "color": wallc},
		# commissioning gallery shell
		{"pos": Vector3(140.0, 2.4, -14.15), "size": Vector3(168.0, 4.8, 0.3), "color": Color(0.12, 0.11, 0.105), "tile": "rust_iron"},
		{"pos": Vector3(140.0, 2.4, 14.15), "size": Vector3(168.0, 4.8, 0.3), "color": Color(0.12, 0.11, 0.105), "tile": "rust_iron"},
		{"pos": Vector3(224.15, 2.4, 0.0), "size": Vector3(0.3, 4.8, 28.0), "color": Color(0.10, 0.095, 0.09), "tile": "rust_iron"},
	]
	frag.lights = [
		{"pos": Vector3(8.0, 3.6, 0.0), "color": Color(0.9, 0.68, 0.5), "energy": 1.2, "range": 16.0},
		{"pos": Vector3(21.5, 3.8, 0.0), "color": Color(0.85, 0.8, 0.7), "energy": 1.5, "range": 18.0},
		{"pos": Vector3(22.0, 3.4, 10.0), "color": Color(0.45, 0.85, 0.6), "energy": 1.1, "range": 14.0},
		{"pos": Vector3(22.0, 3.4, -10.0), "color": Color(0.6, 0.75, 0.95), "energy": 1.1, "range": 14.0},
		{"pos": Vector3(38.0, 3.8, 0.0), "color": Color(0.85, 0.78, 0.68), "energy": 1.6, "range": 22.0},
		{"pos": Vector3(50.0, 3.6, 4.0), "color": Color(0.5, 0.9, 0.62), "energy": 1.2, "range": 14.0},
		{"pos": Vector3(75.0, 3.7, 0.0), "color": Color(0.42, 0.62, 0.58), "energy": 1.1, "range": 18.0},
		{"pos": Vector3(116.0, 3.7, 0.0), "color": Color(0.40, 0.58, 0.48), "energy": 1.1, "range": 18.0},
		{"pos": Vector3(157.0, 3.7, 0.0), "color": Color(0.54, 0.46, 0.36), "energy": 1.1, "range": 18.0},
		{"pos": Vector3(198.0, 3.7, 0.0), "color": Color(0.38, 0.62, 0.44), "energy": 1.2, "range": 18.0},
	]
	frag.labels = [
		{"pos": Vector3(8.0, 3.0, 0.0), "text": "MAINTENANCE BRANCH 7 — DECOMMISSIONED", "color": Color(0.62, 0.58, 0.55)},
	]
	frag.labels.append({"pos": Vector3(58.0, 3.1, 0.0), "text": "RESOLUTION SUPPORT // FOUR LOOPS", "color": Color(0.44, 0.78, 0.56)})
	frag.objects = []
	frag.params = {"restart_on_wipe": false}
	frag.time_state = {"note_default": "Salvage run. The survival clock holds outside — in here the danger is local.",
		"routing_mode": "direct"}
	var cs := 1.5
	var w := 150
	var hgrid := 22
	var cells: Array = []
	for z in range(hgrid):
		for x in range(w):
			var wx := (float(x) + 0.5) * cs
			var wz := (float(z) + 0.5) * cs - 16.5
			var ok := false
			if wx < APPROACH_X1 and absf(wz) < 3.0 and wx > 0.5:
				ok = true
			elif wx >= HUB_X0 and wx < HUB_X1 and absf(wz) < HUB_HALF_Z:
				ok = true
			elif wx >= ROUTE_X0 and wx < ROUTE_X1 and wz > -13.5 and wz < -7.5:
				ok = true
			elif wx >= 20.5 and wx < 23.5 and wz >= -7.5 and wz < -6.0:
				ok = true
			elif wx >= ROUTE_X0 and wx < ROUTE_X1 and wz > 7.5 and wz < 13.5:
				ok = true
			elif wx >= 20.5 and wx < 23.5 and wz > 6.0 and wz <= 7.5:
				ok = true
			elif wx >= HUB_X1 and wx < JCT_X0 and absf(wz) < 1.6:
				ok = true
			elif wx >= JCT_X0 and wx < JCT_X1 and absf(wz) < JCT_HALF_Z:
				ok = true
			elif wx >= JCT_X1 and wx < 224.0 and absf(wz) < 13.5:
				ok = true
			elif wx > POCKET[0] and wx < POCKET[1] and wz > POCKET[2] and wz < POCKET[3]:
				ok = true
			if ok:
				cells.append([x, z])
	frag.grid = {"contract_id": "unified_grid_v1", "cell_size": cs,
		"origin": [0.0, 0.0, -16.5], "width": w, "height": hgrid, "walkable_cells": cells}
	return frag

# --- Approach corridor: the burn-damage read ---

func _build_approach() -> void:
	# scorch streaks + fused conduit — elegant routing beneath the burn (the key read)
	for i in range(5):
		var sx := 3.0 + float(i) * 2.6
		_add_box(self, Vector3(sx, 0.02, -1.0 + float(i % 3)), Vector3(1.8, 0.04, 1.2), Color(0.05, 0.045, 0.04))
	_add_box(self, Vector3(8.0, 2.4, -3.0), Vector3(14.0, 0.18, 0.18), Color(0.2, 0.16, 0.12),
		Color(0.9, 0.5, 0.2), 0.12)
	_add_box(self, Vector3(8.0, 2.1, -3.0), Vector3(14.0, 0.12, 0.12), Color(0.18, 0.15, 0.12))
	# Crust organisms on accumulated char (fauna roster: ambient char growth)
	for i in range(4):
		var c := _add_box(self, Vector3(4.5 + float(i) * 3.1, 0.28, 2.4 - float(i % 2) * 0.8),
			Vector3(0.55, 0.5, 0.5), Color(0.28, 0.2, 0.12), Color(0.75, 0.45, 0.15), 0.35)
		c.name = "Crust%d" % i
	_add_label(self, "OLD CHELATOR DAMAGE // REPEAT BURN RESIDUE", Vector3(11.0, 2.6, 0.0), Color(0.62, 0.5, 0.42))

# --- The three information routes ---

func _build_routes() -> void:
	# Route A (Aster): engineering log + pipe diagram
	_add_label(self, "A — RECORDS", Vector3(22.0, 2.9, -8.0), Color(0.6, 0.75, 0.95))
	var a1 := _add_interactable(self, "AsterLogTerminal", "Read the final engineering log",
		Vector3(20.0, 0.6, -11.5), "READ LOG", "aster", 1.0, false, 1.6)
	_outline_interactable_child(a1, _add_box(a1, Vector3(0, 0.55, 0), Vector3(0.7, 1.1, 0.4),
		Color(0.14, 0.16, 0.2), Color(0.36, 0.91, 0.5), 0.5), "AsterLogTerminal", 1.6)
	a1.interacted.connect(_on_aster_log)
	var a2 := _add_interactable(self, "PipeDiagram", "Scan the pipe junction diagram",
		Vector3(24.0, 0.6, -11.5), "SCAN DIAGRAM", "aster", 1.0, false, 1.6)
	_outline_interactable_child(a2, _add_box(a2, Vector3(0, 0.9, -0.4), Vector3(1.6, 1.2, 0.12),
		Color(0.16, 0.18, 0.22), Color(0.5, 0.7, 0.95), 0.4), "PipeDiagram", 1.6)
	a2.interacted.connect(_on_pipe_diagram)
	# Route B (Peris): dead roots + the living root-Chelator junction
	_add_label(self, "B — UNDERGROWTH", Vector3(22.0, 2.9, 8.0), Color(0.45, 0.85, 0.6))
	var p1 := _add_interactable(self, "DeadRootNetwork", "Examine the dead root network",
		Vector3(20.0, 0.4, 11.5), "EXAMINE ROOTS", "peris", 1.0, false, 1.6)
	_outline_interactable_child(p1, _add_box(p1, Vector3(0, 0.2, 0), Vector3(1.7, 0.4, 1.0),
		Color(0.16, 0.13, 0.1)), "DeadRootNetwork", 1.7)
	p1.interacted.connect(_on_dead_roots)
	var p2 := _add_interactable(self, "LivingJunction", "Examine the living root-Chelator junction",
		Vector3(24.0, 0.4, 11.5), "EXAMINE JUNCTION", "peris", 1.0, false, 1.6)
	_outline_interactable_child(p2, _add_box(p2, Vector3(0, 0.25, 0), Vector3(1.4, 0.5, 1.0),
		Color(0.14, 0.2, 0.15), Color(0.4, 0.9, 0.55), 0.6), "LivingJunction", 1.7)
	p2.interacted.connect(_on_living_junction)
	# Route C (Myke): the crawlspace — physically character-coded
	var crawl_in := CrawlTunnel.new()
	crawl_in.name = "MykeCrawlIn"
	crawl_in.description = "A crawlspace only Myke fits through"
	crawl_in.tutorial_label = "CRAWL"
	crawl_in.configure(_get_game_state(), Vector3(26.2, 0.0, -4.5),
		[Vector3(28.2, 0.7, -8.0), Vector3(31.0, 0.0, -12.0)], 1.3, 1.1)
	_wire_myke_crawl(crawl_in)
	var crawl_out := CrawlTunnel.new()
	crawl_out.name = "MykeCrawlOut"
	crawl_out.description = "Back through the crawlspace"
	crawl_out.tutorial_label = "CRAWL BACK"
	crawl_out.configure(_get_game_state(), Vector3(30.4, 0.0, -11.0),
		[Vector3(28.2, 0.7, -8.0), Vector3(25.4, 0.0, -4.0)], 1.3, 1.1)
	_wire_myke_crawl(crawl_out)
	var m1 := _add_interactable(self, "GrateObservation", "Watch the corridor floor through the grate",
		Vector3(31.8, 0.4, -13.2), "WATCH FEEDERS", "myke", 1.0, false, 1.6)
	_outline_interactable_child(m1, _add_box(m1, Vector3(0, 0.3, 0.5), Vector3(1.2, 0.6, 0.14),
		Color(0.14, 0.14, 0.15)), "GrateObservation", 1.6)
	m1.interacted.connect(_on_grate_observation)
	var m2 := _add_interactable(self, "DeviceGap", "Sight the device through the gap",
		Vector3(34.2, 0.4, -13.2), "SIGHT DEVICE", "myke", 1.0, false, 1.6)
	_outline_interactable_child(m2, _add_box(m2, Vector3(0, 0.3, 0.5), Vector3(1.2, 0.6, 0.14),
		Color(0.14, 0.14, 0.15), Color(0.5, 0.9, 0.62), 0.3), "DeviceGap", 1.6)
	m2.interacted.connect(_on_device_gap)

func _wire_myke_crawl(crawl: CrawlTunnel) -> void:
	crawl.requirement = func() -> bool: return str(crawl.active_character) == "myke"
	crawl.refused.connect(func() -> void:
		_show_note("The gap is a hand-span wide. Only Myke could fit through there.", 2.4))
	add_child(crawl)
	_register_interactable(crawl)
	var stub := _add_box(crawl, Vector3(0.0, 0.35, 0.0), Vector3(0.5, 0.7, 0.5), Color(0.1, 0.1, 0.11))
	_outline_interactable_child(crawl, stub, crawl.name, 1.4)

# --- The junction room: eight interactables in one shared space ---

func _build_junction_room() -> void:
	var gs = _get_game_state()
	# 1. drainage valve (wall-mounted, near the terminal but visually distinct)
	_valve_it = _add_interactable(self, "DrainageValve", "Open the drainage valve",
		VALVE_POS, "OPEN VALVE", "", HOLDS["valve"][1], false, 1.7,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_valve_it, _add_box(_valve_it, Vector3(0, 0.4, -0.5), Vector3(0.9, 0.9, 0.35),
		Color(0.2, 0.28, 0.34), Color(0.4, 0.7, 0.9), 0.4), "DrainageValve", 1.7)
	_valve_it.interacted.connect(_on_valve)
	# 2 + 3. char deposits
	_char_a_mesh = _add_box(self, CHAR_A_POS + Vector3(0, 0.12, 0), Vector3(2.2, 0.24, 1.8), Color(0.05, 0.045, 0.04))
	_char_a_it = _add_interactable(self, "CharDepositA", "Clear the char deposit",
		CHAR_A_POS, "CLEAR CHAR", "", HOLDS["char_a"][1], false, 1.7,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_char_a_it, _add_box(_char_a_it, Vector3(0, 0.1, 0), Vector3(1.6, 0.2, 1.3),
		Color(0.06, 0.055, 0.05)), "CharDepositA", 1.8)
	_char_a_it.interacted.connect(func() -> void: _on_char_deposit("a"))
	_char_b_mesh = _add_box(self, CHAR_B_POS + Vector3(0, 0.12, 0), Vector3(1.8, 0.24, 1.5), Color(0.05, 0.045, 0.04))
	_char_b_it = _add_interactable(self, "CharDepositB", "Clear the char deposit by the root crack",
		CHAR_B_POS, "CLEAR CHAR", "", HOLDS["char_b"][1], false, 1.6,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_char_b_it, _add_box(_char_b_it, Vector3(0, 0.1, 0), Vector3(1.3, 0.2, 1.1),
		Color(0.06, 0.055, 0.05)), "CharDepositB", 1.7)
	_char_b_it.interacted.connect(func() -> void: _on_char_deposit("b"))
	# 4. the root tendril in the floor crack near char B
	var crack := _add_box(self, ROOT_BASE_POS + Vector3(0, 0.03, 0), Vector3(1.2, 0.06, 0.5), Color(0.03, 0.03, 0.03))
	crack.name = "RootCrack"
	_root_it = _add_interactable(self, "RootTendril", "Tend the suppressed root tendril",
		ROOT_BASE_POS, "TEND ROOT", "peris", HOLDS["root"][1], false, 1.5,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_root_it, _add_box(_root_it, Vector3(0, 0.18, 0), Vector3(0.35, 0.36, 0.35),
		Color(0.16, 0.24, 0.17), Color(0.4, 0.9, 0.55), 0.25), "RootTendril", 1.5)
	_root_it.interacted.connect(_on_tend_root)
	# 5. the dormant Chelator ring: examine is the read, strike is the mistake
	for i in range(5):
		var ang := TAU * float(i) / 5.0
		var husk := _add_box(self, RING_CENTER + Vector3(cos(ang) * 2.1, 0.3, sin(ang) * 2.1),
			Vector3(0.6, 0.6, 0.6), Color(0.22, 0.16, 0.12), Color(0.7, 0.45, 0.25), 0.18)
		husk.name = "DormantHusk%d" % i
		_husks.append(husk)
	_examine_it = _add_interactable(self, "ExamineCluster", "Examine the dormant Chelator ring",
		RING_CENTER + Vector3(-2.0, 0.4, -0.9), "EXAMINE", "", 1.0, false, 1.6)
	_outline_interactable_child(_examine_it, _add_box(_examine_it, Vector3(0, 0.25, 0), Vector3(0.3, 0.5, 0.3),
		Color(0.2, 0.2, 0.22), Color(0.55, 0.75, 1.0), 0.3), "ExamineCluster", 1.6)
	_examine_it.interacted.connect(_on_examine_cluster)
	_strike_it = _add_interactable(self, "StrikeCluster", "Strike the dormant Chelators",
		RING_CENTER + Vector3(1.6, 0.4, -1.1), "STRIKE", "", 1.0, false, 1.6)
	_outline_interactable_child(_strike_it, _add_box(_strike_it, Vector3(0, 0.2, 0), Vector3(0.4, 0.4, 0.4),
		Color(0.24, 0.14, 0.12), Color(0.9, 0.4, 0.25), 0.3), "StrikeCluster", 1.6)
	_strike_it.interacted.connect(_on_strike_cluster)
	# 6. gas sac flora in the damp corner (Gasafoetida — flora_taxonomy: Peris-only tend,
	# carryable repellent pod)
	_flora_it = _add_interactable(self, "GasSacFlora", "Tend the gas sac flora",
		FLORA_POS, "TEND FLORA", "peris", 2.0, false, 1.7,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_flora_it, _add_box(_flora_it, Vector3(0, 0.35, 0), Vector3(0.8, 0.7, 0.8),
		Color(0.2, 0.26, 0.16), Color(0.6, 0.8, 0.3), 0.4), "GasSacFlora", 1.7)
	_flora_it.interacted.connect(_on_tend_flora)
	_take_sac_it = _add_interactable(self, "TakeSac", "Take the swollen gas sac",
		FLORA_POS + Vector3(1.3, 0.3, 0.4), "TAKE SAC", "", 0.8, false, 1.4)
	_outline_interactable_child(_take_sac_it, _add_box(_take_sac_it, Vector3(0, 0.18, 0), Vector3(0.35, 0.35, 0.35),
		Color(0.35, 0.5, 0.2), Color(0.7, 0.9, 0.3), 0.5), "TakeSac", 1.4)
	_take_sac_it.interacted.connect(_on_take_sac)
	# 7. the terminal (hack = read-only diagnostics; the reset command is the trap)
	_terminal_it = _add_interactable(self, "JunctionTerminal", "Hack the maintenance terminal",
		TERMINAL_POS, "HACK", "aster", 1.0, false, 1.7)
	_outline_interactable_child(_terminal_it, _add_box(_terminal_it, Vector3(0, 0.5, -0.5), Vector3(0.9, 1.0, 0.3),
		Color(0.13, 0.15, 0.19), Color(0.36, 0.91, 0.5), 0.6), "JunctionTerminal", 1.7)
	_terminal_it.interacted.connect(_on_hack_terminal)
	_reset_it = _add_interactable(self, "ThermalResetConfirm", "Initiate the logged thermal reset",
		TERMINAL_POS + Vector3(1.5, 0.5, 0.6), "THERMAL RESET", "aster", 1.2, false, 1.4)
	_outline_interactable_child(_reset_it, _add_box(_reset_it, Vector3(0, 0.3, 0), Vector3(0.32, 0.6, 0.32),
		Color(0.3, 0.12, 0.1), Color(0.95, 0.3, 0.15), 0.7), "ThermalResetConfirm", 1.4)
	_reset_it.interacted.connect(_on_thermal_reset)
	# 8. the device housing + the healing zone under the grate
	_housing_it = _add_interactable(self, "DeviceHousing", "Open the device housing",
		HOUSING_POS, "OPEN HOUSING", "", 1.2, false, 1.6,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_housing_it, _add_box(_housing_it, Vector3(0, 0.3, 0), Vector3(1.1, 0.6, 1.1),
		Color(0.18, 0.2, 0.22), Color(0.5, 0.9, 0.62), 0.3), "DeviceHousing", 1.7)
	_housing_it.interacted.connect(_on_open_housing)
	var grate := _add_box(self, GRATE_POS + Vector3(0, 0.02, 0), Vector3(2.2, 0.05, 2.2), Color(0.12, 0.13, 0.14))
	grate.name = "HealingGrate"
	_healing_glow = _add_box(self, GRATE_POS + Vector3(0, -0.35, 0), Vector3(0.8, 0.15, 0.8),
		Color(0.1, 0.2, 0.12), Color(0.45, 0.95, 0.55), 1.4)
	_healing_glow.name = "HealingZoneGlow"
	# the shadow observation point: watching the feeders from inside the room
	_observe_it = _add_interactable(self, "ObserveFeeding", "Watch the active Chelators around the char",
		CHAR_A_POS + Vector3(1.8, 0.4, 1.4), "OBSERVE", "", 1.0, false, 1.6)
	_outline_interactable_child(_observe_it, _add_box(_observe_it, Vector3(0, 0.06, 0), Vector3(0.9, 0.12, 0.9),
		Color(0.13, 0.14, 0.15), Color(0.55, 0.75, 1.0), 0.2), "ObserveFeeding", 1.6)
	_observe_it.interacted.connect(_on_observe_feeding)
	# the thermal-reset command is not offered until the terminal has been hacked
	if gs != null:
		gs.set_interactable_enabled(_interactable_data_id("ThermalResetConfirm"), false)

# --- Long-form commissioning gallery: four evidence -> decision -> execution loops ---

func _build_commissioning_gallery() -> void:
	var gallery := Node3D.new()
	gallery.name = "CommissioningGallery"
	add_child(gallery)
	var frames := Node3D.new()
	frames.name = "ProtocolFrames"
	gallery.add_child(frames)
	var datums := Node3D.new()
	datums.name = "MeasurementDatums"
	gallery.add_child(datums)
	var instruments := Node3D.new()
	instruments.name = "CommissioningInstruments"
	gallery.add_child(instruments)

	var datum_count := 0
	var station_count := 0
	for protocol_index in range(COMMISSIONING_PROTOCOL_ORDER.size()):
		var protocol_id := str(COMMISSIONING_PROTOCOL_ORDER[protocol_index])
		var protocol: Dictionary = COMMISSIONING_PROTOCOLS[protocol_id]
		_build_commissioning_protocol_frame(frames, datums, protocol_id, protocol_index, protocol)
		for evidence_index in range((protocol["evidence"] as Array).size()):
			var evidence: Dictionary = (protocol["evidence"] as Array)[evidence_index]
			_build_commissioning_site(instruments, protocol_id, evidence, "evidence",
				COMMISSIONING_EVIDENCE_SECONDS, evidence_index)
			station_count += 1
			datum_count += 1
		for choice_variant in protocol["choices"] as Array:
			var choice: Dictionary = choice_variant
			_build_commissioning_site(instruments, protocol_id, choice, "decision",
				COMMISSIONING_DECISION_SECONDS)
			station_count += 1
		for choice_id_variant in (protocol["resolutions"] as Dictionary).keys():
			var choice_id := str(choice_id_variant)
			var resolution: Dictionary = (protocol["resolutions"] as Dictionary)[choice_id]
			_build_commissioning_site(instruments, protocol_id, resolution, "execution",
				COMMISSIONING_EXECUTION_SECONDS, -1, choice_id)
			station_count += 1

	# The cradle is not a presentation trigger: seating and sealing the live device is
	# one final outlined timed action, enabled only after all four executions.
	_extraction_it = _add_interactable(instruments, "Commissioning_extraction_cradle",
		"Seat the live Resolution Catalyst in the insulated extraction cradle",
		EXTRACTION_POS, "SEAT CATALYST", "aster", EXTRACTION_WORK_SECONDS, true, 2.0,
		Interactable.InteractableType.TIMED_ACTION, false)
	var cradle := _add_box(_extraction_it, Vector3(0.0, 0.55, 0.0), Vector3(2.4, 1.1, 1.6),
		Color(0.14, 0.17, 0.16), Color(0.36, 0.91, 0.50), 0.65, "ExtractionCradle")
	_outline_interactable_child(_extraction_it, cradle, "Commissioning_extraction_cradle", 2.0)
	_extraction_it.set_meta("commissioning_stage", "extraction")
	_extraction_it.set_meta("commissioning_category", "extraction_handoff")
	_extraction_it.interacted.connect(_on_extraction_cradle_completed)
	_extraction_it.set_interaction_enabled(false)
	_commissioning_sites["extraction_cradle"] = _extraction_it
	station_count += 1

	# Continuous longitudinal measurement rails bind the four bays into one readable
	# service system.  They are paper-thin rendering-only datums, not obstacles.
	for guide_z in [-9.6, 0.0, 9.6]:
		var guide := _add_box(datums, Vector3(140.0, 0.024, float(guide_z)),
			Vector3(164.0, 0.018, 0.055), Color(0.08, 0.15, 0.11),
			Color(0.36, 0.91, 0.50), 0.55, "LongitudinalDatum_%s" % str(guide_z))
		guide.set_meta("rendering_only", true)
		datum_count += 1

	gallery.set_meta("environment_audit", {
		"contract_id": "inflammashunt_commissioning_environment_v1",
		"protocol_frames": COMMISSIONING_PROTOCOL_ORDER.size(),
		"station_count": station_count,
		"measurement_datums": datum_count,
		"collision_shapes": 0,
		"clearance": "rendering_only_outside_station_footprints",
		"deterministic": true,
	})

func _build_commissioning_protocol_frame(
	frames: Node3D,
	datums: Node3D,
	protocol_id: String,
	protocol_index: int,
	protocol: Dictionary
) -> void:
	var evidence: Array = protocol["evidence"]
	var first_x := float((evidence[0] as Dictionary)["pos"].x) - 3.0
	var resolutions: Dictionary = protocol["resolutions"]
	var last_x := first_x + 34.0
	for resolution_variant in resolutions.values():
		last_x = maxf(last_x, float((resolution_variant as Dictionary)["pos"].x) + 3.0)
	var frame := Node3D.new()
	frame.name = "ProtocolFrame_%02d_%s" % [protocol_index + 1, protocol_id]
	frames.add_child(frame)
	var frame_color := Color(0.26, 0.29, 0.28) if protocol_index % 2 == 0 else Color(0.30, 0.25, 0.21)
	for arch_x in [first_x, last_x]:
		for side_z in [-10.8, 10.8]:
			_add_box(frame, Vector3(float(arch_x), 1.8, float(side_z)), Vector3(0.34, 3.6, 0.34),
				frame_color, Color.BLACK, 0.0, "ArchColumn")
		_add_box(frame, Vector3(float(arch_x), 3.45, 0.0), Vector3(0.34, 0.24, 21.9),
			frame_color, Color.BLACK, 0.0, "ArchBeam")
	var span := last_x - first_x
	_add_box(frame, Vector3((first_x + last_x) * 0.5, 0.035, -11.0),
		Vector3(span, 0.025, 0.12), frame_color, Color(0.36, 0.91, 0.50), 0.42,
		"ProtocolBoundary")
	_add_label(frame, "%s // %03dm-%03dm" % [str(protocol["label"]), int(first_x), int(last_x)],
		Vector3(first_x + 3.0, 2.75, -10.55), Color(0.58, 0.86, 0.67))
	var light := _add_light(frame, Vector3((first_x + last_x) * 0.5, 3.25, 0.0),
		Color(0.38, 0.58, 0.46), 0.72, 10.0)
	light.name = "ProtocolLight_%02d" % (protocol_index + 1)
	light.shadow_enabled = false

	for evidence_variant in evidence:
		var pos: Vector3 = (evidence_variant as Dictionary)["pos"]
		_add_box(datums, Vector3(pos.x, 0.026, 0.0), Vector3(0.055, 0.022, 22.0),
			Color(0.07, 0.12, 0.10), Color(0.36, 0.91, 0.50), 0.38,
			"StationDatum_%s" % str((evidence_variant as Dictionary)["id"]))

func _build_commissioning_site(
	parent: Node3D,
	protocol_id: String,
	site: Dictionary,
	stage: String,
	dwell_seconds: float,
	evidence_index := -1,
	choice_id := ""
) -> void:
	var site_id := str(site["id"])
	var role := str(site["role"])
	var node_name := "Commissioning_%s" % site_id
	var interactable := _add_interactable(parent, node_name,
		"%s: %s" % [str((COMMISSIONING_PROTOCOLS[protocol_id] as Dictionary)["label"]),
			str(site["verb"]).capitalize()],
		site["pos"], str(site["verb"]), role, dwell_seconds, true, 1.8,
		Interactable.InteractableType.TIMED_ACTION, false)
	var role_color := Color(0.34, 0.58, 0.92) if role == "aster" else (
		Color(0.50, 0.78, 0.38) if role == "peris" else Color(0.86, 0.34, 0.18))
	var kind := str(site.get("kind", "data"))
	var body_size := Vector3(0.9, 1.05, 0.65)
	if kind == "root":
		body_size = Vector3(1.35, 0.60, 1.10)
	elif kind == "decision":
		body_size = Vector3(1.25, 0.86, 0.82)
	elif kind == "execution":
		body_size = Vector3(1.65, 1.20, 1.10)
	var body := _add_box(interactable, Vector3(0.0, body_size.y * 0.5, 0.0), body_size,
		Color(0.13, 0.15, 0.15), role_color, 0.48, "%sBody" % site_id)
	# A second silhouette layer tells evidence, choice, and execution apart at camera distance.
	if kind == "root":
		for offset in [-0.38, 0.0, 0.38]:
			_add_box(interactable, Vector3(float(offset), 0.76, 0.0), Vector3(0.11, 0.55, 0.11),
				role_color.darkened(0.20), role_color, 0.30, "%sRootStem" % site_id)
	elif kind == "decision":
		_add_box(interactable, Vector3(0.0, 1.05, 0.0), Vector3(1.75, 0.10, 0.22),
			role_color.darkened(0.25), role_color, 0.55, "%sDecisionBar" % site_id)
	elif kind == "execution":
		_add_box(interactable, Vector3(0.0, 1.45, 0.0), Vector3(0.28, 0.42, 0.28),
			role_color.darkened(0.25), role_color, 0.70, "%sExecutionBeacon" % site_id)
	else:
		_add_box(interactable, Vector3(0.0, 1.18, 0.0), Vector3(0.58, 0.18, 0.16),
			role_color.darkened(0.25), role_color, 0.65, "%sDataVane" % site_id)
	_outline_interactable_child(interactable, body, node_name, 1.8)
	interactable.set_meta("commissioning_protocol", protocol_id)
	interactable.set_meta("commissioning_stage", stage)
	interactable.set_meta("commissioning_role", role)
	interactable.set_meta("commissioning_category",
		str((COMMISSIONING_PROTOCOLS[protocol_id] as Dictionary)["category"]))
	if stage == "evidence":
		interactable.set_meta("commissioning_index", evidence_index)
		interactable.interacted.connect(_on_commissioning_evidence.bind(protocol_id, evidence_index, site_id))
	elif stage == "decision":
		interactable.interacted.connect(_on_commissioning_choice.bind(protocol_id, site_id))
	else:
		interactable.set_meta("commissioning_choice", choice_id)
		interactable.interacted.connect(_on_commissioning_execution.bind(protocol_id, choice_id, site_id))
	interactable.set_interaction_enabled(false)
	_commissioning_sites[site_id] = interactable

func _spawn_active_chelators() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for i in range(3):
		var eid := "chelator_%d" % i
		var ang := TAU * float(i) / 3.0
		var enemy := Enemy.new()
		enemy.name = "Enemy_%s" % eid
		enemy.position = CHAR_A_POS + Vector3(cos(ang) * 1.8, 0.4, sin(ang) * 1.8)
		enemy.scale = Vector3.ONE * 0.62
		enemy.color = Color(0.45, 0.18, 0.1)
		enemy.move_speed = 2.0
		enemy.detection_range = 0.0
		enemy.windup_duration = 0.4
		enemy.recover_duration = 0.8
		enemy.charge_speed = 6.0
		enemy.attack_range = 1.5
		enemy.charge_damage = 6.0
		enemy._detection_targets.assign(_party)
		add_child(enemy)
		enemy.char_id = eid
		enemy.game_state = gs
		gs.register_character(eid, enemy.position, enemy.move_speed, {})
		if gs.has_method("set_coop_exempt"):
			gs.set_coop_exempt(eid)
		enemy.activate()
		enemy.set_roam(CHAR_A_POS, 2.4)
		_enemy_posts[eid] = enemy.position
		_enemies.append(enemy)

# --- Route handlers: every report is honest and confidently wrong ---

func _on_aster_log() -> void:
	route_info["aster_log"] = true
	_show_note("FINAL ENTRY // Resolution capacity exceeded. Recommend thermal reset. // Filed: same day as section removal from registry.", 4.2)
	_maybe_report("aster")
	_refresh_hold_times()

func _on_pipe_diagram() -> void:
	route_info["aster_pipe_diagram"] = true
	_show_note("Drainage routing — the valve feeds from the Plumbing Power Project. Flow and pressure ratings. Water infrastructure, not heat.", 3.8)
	_maybe_report("aster")
	_refresh_hold_times()

func _on_dead_roots() -> void:
	route_info["peris_dead_roots"] = true
	_show_note("The old network is hollow — tunneled from inside, then coated by char. It was eaten before it burned.", 3.6)
	_maybe_report("peris")
	_refresh_hold_times()

func _on_living_junction() -> void:
	route_info["peris_living_junction"] = true
	_show_note("Living filaments feed the dormant husks — and the husks feed the roots back. A cycle, still running.", 3.6)
	_maybe_report("peris")
	_refresh_hold_times()

func _on_grate_observation() -> void:
	route_info["myke_char_feed"] = true
	_show_note("The active crawlers aren't roaming. They're feeding — clustered on the char.", 3.2)
	_maybe_report("myke")
	_refresh_hold_times()

func _on_device_gap() -> void:
	route_info["myke_buffer_ring"] = true
	_show_note("Dormant crawlers ring the device — calm, inside. The active ones press from outside the ring.", 3.2)
	_maybe_report("myke")
	_refresh_hold_times()

## The confident wrong answer, played once when a route's pair of reads is complete.
func _maybe_report(route: String) -> void:
	if _reports.has(route):
		return
	match route:
		"aster":
			if route_info["aster_log"] and route_info["aster_pipe_diagram"]:
				_reports["aster"] = true
				_show_note("Aster: \"The engineers left instructions. The device needs a thermal reset.\"", 3.4)
		"peris":
			if route_info["peris_dead_roots"] and route_info["peris_living_junction"]:
				_reports["peris"] = true
				_show_note("Peris: \"The old roots were burned. Fire killed the previous resolution system. We can't use fire near the device.\"", 3.8)
		"myke":
			if route_info["myke_char_feed"] and route_info["myke_buffer_ring"] and _party.has("myke"):
				_reports["myke"] = true
				_show_note("Myke: \"Too many crawlers. We burn the corridor clean, give the thing room to breathe.\"", 3.6)

## The reunion triangle: back at the hub with the reports in hand, the contradictions land.
func _check_reunion() -> void:
	if _reunion_played or _reports.size() < 2:
		return
	var gs = _get_game_state()
	if gs == null:
		return
	for cid in _party:
		if not gs.characters.has(cid):
			continue
		var p: Vector3 = gs.get_position(cid)
		if p.x < HUB_X0 or p.x > HUB_X1 or absf(p.z) > HUB_HALF_Z:
			return
	_reunion_played = true
	var sched = _get_scheduler()
	if sched == null:
		return
	if _reports.size() >= 3:
		sched.schedule_after(0.5, func() -> void:
			_show_note("Aster: \"Thermal reset.\"  Peris: \"Heat killed the old system.\"", 3.4), "inflam_reunion")
		sched.schedule_after(4.0, func() -> void:
			_show_note("Myke: \"Burn it clean.\"  Aster: \"The only live infrastructure is water.\"", 3.4), "inflam_reunion")
		sched.schedule_after(7.5, func() -> void:
			_show_note("Three confident answers. They can't all be right.", 3.0), "inflam_reunion")
	else:
		sched.schedule_after(0.5, func() -> void:
			_show_note("Two confident answers that can't both be right. Something out there settles it.", 3.4), "inflam_reunion")

# --- Junction handlers ---

func _on_valve() -> void:
	if not valve_open:
		if not route_info["aster_pipe_diagram"]:
			_long_hold(str(_valve_it.active_character))
		valve_open = true
		if char_a_state == "dry" or char_a_state == "burned":
			char_a_state = "damp"
		if char_b_state == "dry" or char_b_state == "burned":
			char_b_state = "damp"
		_sync_char_visuals()
		if _popcorn:
			_end_popcorn("The flood takes the fire. Scorched sacs drift in the runoff.")
		else:
			_show_note("The pipes rumble. The floor channels fill — the char darkens and steams. The crawlers recoil.", 3.6)
		_refresh_hold_times()

func _on_char_deposit(which: String) -> void:
	var it := _char_a_it if which == "a" else _char_b_it
	var actor := str(it.active_character)
	var state := char_a_state if which == "a" else char_b_state
	match state:
		"dry", "burned":
			if actor == "myke":
				_burn_char(which)
			else:
				_show_note("The residue is baked on — it won't come loose dry. Water would soften it.", 2.8)
		"damp":
			if not route_info["myke_char_feed"]:
				_long_hold(actor)
			if which == "a":
				char_a_state = "cleared"
				_show_note("The damp char comes away clean. The feeders lose their food source and thin out.", 3.2)
				_thin_out_chelators()
			else:
				char_b_state = "cleared"
				_show_note("Careful strokes around the crack — the char lifts without touching the root.", 3.0)
			_sync_char_visuals()
		"cleared":
			_show_note("Bare floor. Nothing left to clear.", 2.0)

func _burn_char(which: String) -> void:
	if which == "a":
		char_a_state = "burned"
		_wrong("burned_char_a")
		_show_note("Myke's fire takes the char — and the heat wakes what was sleeping. They're up.", 3.2)
		_wake_chelators(0)
	else:
		char_b_state = "burned"
		root_state = "hostile"
		_wrong("burned_char_b")
		_show_note("The char flashes off — and the root beside it whips out of the crack, thrashing.", 3.2)
		_spawn_hostile_root()
	_sync_char_visuals()

func _on_tend_root() -> void:
	if root_state == "hostile" or root_state == "recovering":
		_show_note("The root is in no state to be tended.", 2.2)
		return
	if char_a_state != "cleared" or char_b_state != "cleared":
		_show_note("The pulse flickers under Peris's hands and dies down. The residue is still smothering it.", 3.2)
		if not route_info["peris_living_junction"]:
			_long_hold("peris")
		return
	if not route_info["peris_living_junction"]:
		_long_hold("peris")
	root_state = "connected"
	healing_zone = 1.0
	housing_unlocked = true
	_sync_healing_visual()
	_show_note("The root brightens. Filaments thread toward the dormant ring — and the glow under the grate spreads to the housing.", 4.0)

func _on_examine_cluster() -> void:
	_show_note("Warm. Connected by thin filaments. Not feeding, not moving — a perimeter.", 3.2)
	if route_info["peris_living_junction"] and not route_info["myke_buffer_ring"]:
		route_info["myke_buffer_ring"] = true
		_show_note("Peris: \"They're in the same state as the junction underground. It's a buffer — not a siege.\"", 3.6)
		_refresh_hold_times()

func _on_observe_feeding() -> void:
	_show_note("The active crawlers cluster on the char deposits. They don't wander off them.", 3.0)
	if route_info["aster_pipe_diagram"] and route_info["peris_living_junction"] \
			and not route_info["myke_char_feed"]:
		route_info["myke_char_feed"] = true
		_show_note("Aster: \"The system was built to flush something. They're eating it. The char is the food.\"", 3.6)
		_refresh_hold_times()

func _on_strike_cluster() -> void:
	if buffer_state != "stable":
		_show_note("The scattered husks don't react.", 2.0)
		return
	buffer_state = "shattered"
	_wrong("attacked_buffer")
	if root_state == "connected" and not device_retrieved:
		root_state = "suppressed"
		healing_zone = 0.0
		housing_unlocked = false
		_sync_healing_visual()
	_show_note("The ring shatters — and everything that was calm isn't. The root snaps back into its crack.", 3.4)
	for husk in _husks:
		if is_instance_valid(husk):
			husk.visible = false
	_wake_chelators(2)

func _on_tend_flora() -> void:
	if gas_sac_state == "ignited":
		_show_note("The flora is still burning. Nothing to tend yet.", 2.2)
		return
	gas_sac_state = "tended"
	_show_note("The flora swells under Peris's hands. A sac ripens, ready to carry.", 3.0)

func _on_take_sac() -> void:
	if gas_sac_state != "tended":
		_show_note("No ripe sac. The flora needs tending first.", 2.2)
		return
	var actor := str(_take_sac_it.active_character)
	if actor == "":
		return
	_sac_carrier = actor
	_sac_expires = _now() + SAC_DURATION
	gas_sac_state = "carried"
	_attach_sac_visual(actor)
	_show_note("%s carries the sac at arm's length. The smell peels paint — nothing rooted will come near it." % actor.capitalize(), 3.2)

func _on_hack_terminal() -> void:
	var gs = _get_game_state()
	_show_note("Read-only diagnostics: resolution loop INCOMPLETE // residue accumulating // flush line INTACT. One logged command is still queued: THERMAL RESET.", 4.2)
	if gs != null:
		gs.set_interactable_enabled(_interactable_data_id("ThermalResetConfirm"), true)

func _on_thermal_reset() -> void:
	if _popcorn:
		return
	_wrong("thermal_reset")
	gas_sac_state = "ignited"
	_popcorn = true
	_arm_popcorn_poll()
	_show_note("Heaters cough alive — and the gas sacs go up. Flaming sacs skip off the walls. The VALVE. Flood the room.", 3.8)

func _on_open_housing() -> void:
	if device_retrieved:
		return
	if not housing_unlocked:
		_show_note("It does not budge. The lock is warm, but the warmth is coming from below, not from the panel.", 3.4)
		return
	device_retrieved = true
	_phase = "catalyst_retrieved"
	_sync_healing_visual()
	_begin_commissioning()
	_show_note("The housing opens. The Inflammashunt — still running, still warm. Salvage worth the walk.", 3.6)
	var sched = _get_scheduler()
	if sched != null and _party.has("myke"):
		sched.schedule_after(4.0, func() -> void:
			_show_note("Myke: \"...Huh. So that's what it looks like when somebody finishes the job.\"", 3.8), "inflam_after")

func _begin_commissioning() -> void:
	if _commissioning_phase != "locked":
		return
	_commissioning_evidence.clear()
	_commissioning_choices.clear()
	_commissioning_resolved.clear()
	_commissioning_completed_actions.clear()
	for protocol_id_variant in COMMISSIONING_PROTOCOL_ORDER:
		var protocol_id := str(protocol_id_variant)
		_commissioning_evidence[protocol_id] = []
		_commissioning_resolved[protocol_id] = false
	_commissioning_phase = str(COMMISSIONING_PROTOCOL_ORDER[0])
	_set_preview_step("inflammashunt_commissioning_%s" % _commissioning_phase)
	_enable_commissioning_site(_first_evidence_id(_commissioning_phase), true)
	_show_note("The east service gallery answers: FLUSH // ROOT RETURN // BUFFER // TRANSFER. Five reads, one decision, one execution per loop.", 4.4)

func _on_commissioning_evidence(protocol_id: String, evidence_index: int, site_id: String) -> void:
	if _commissioning_phase != protocol_id:
		return
	var completed: Array = _commissioning_evidence.get(protocol_id, [])
	if evidence_index != completed.size():
		return
	completed.append(site_id)
	_commissioning_evidence[protocol_id] = completed
	_commissioning_completed_actions.append(site_id)
	var protocol: Dictionary = COMMISSIONING_PROTOCOLS[protocol_id]
	var evidence: Array = protocol["evidence"]
	if completed.size() < evidence.size():
		var next_site: Dictionary = evidence[completed.size()]
		_enable_commissioning_site(str(next_site["id"]), true)
		_show_note("%s evidence %d/%d recorded. The next datum lights east." % [
			str(protocol["label"]), completed.size(), evidence.size()], 2.6)
	else:
		for choice_variant in protocol["choices"] as Array:
			_enable_commissioning_site(str((choice_variant as Dictionary)["id"]), true)
		_show_note("%s is mapped. Choose the support strategy the evidence can sustain." % str(protocol["label"]), 3.2)

func _on_commissioning_choice(protocol_id: String, choice_id: String) -> void:
	if _commissioning_phase != protocol_id or _commissioning_choices.has(protocol_id):
		return
	var protocol: Dictionary = COMMISSIONING_PROTOCOLS[protocol_id]
	if (_commissioning_evidence.get(protocol_id, []) as Array).size() < (protocol["evidence"] as Array).size():
		return
	_commissioning_choices[protocol_id] = choice_id
	_commissioning_completed_actions.append(choice_id)
	for choice_variant in protocol["choices"] as Array:
		_enable_commissioning_site(str((choice_variant as Dictionary)["id"]), false)
	var resolution: Dictionary = (protocol["resolutions"] as Dictionary)[choice_id]
	_enable_commissioning_site(str(resolution["id"]), true)
	_show_note("Strategy committed. The matching execution rig is live; the unused lane goes dark.", 3.0)

func _on_commissioning_execution(protocol_id: String, choice_id: String, site_id: String) -> void:
	if _commissioning_phase != protocol_id \
			or str(_commissioning_choices.get(protocol_id, "")) != choice_id \
			or bool(_commissioning_resolved.get(protocol_id, false)):
		return
	_commissioning_resolved[protocol_id] = true
	_commissioning_completed_actions.append(site_id)
	var protocol_index := COMMISSIONING_PROTOCOL_ORDER.find(protocol_id)
	if protocol_index + 1 < COMMISSIONING_PROTOCOL_ORDER.size():
		_commissioning_phase = str(COMMISSIONING_PROTOCOL_ORDER[protocol_index + 1])
		_set_preview_step("inflammashunt_commissioning_%s" % _commissioning_phase)
		_enable_commissioning_site(_first_evidence_id(_commissioning_phase), true)
		_show_note("%s holds. The next loop answers farther down the service spine." %
			str((COMMISSIONING_PROTOCOLS[protocol_id] as Dictionary)["label"]), 3.2)
	else:
		_commissioning_phase = "extraction"
		_set_preview_step("inflammashunt_extraction")
		_extraction_it.set_interaction_enabled(true)
		_show_note("All four support loops hold together. Carry the catalyst to the green cradle and seal it for transit.", 3.6)

func _on_extraction_cradle_completed() -> void:
	if _commissioning_phase != "extraction":
		return
	for protocol_id_variant in COMMISSIONING_PROTOCOL_ORDER:
		if not bool(_commissioning_resolved.get(str(protocol_id_variant), false)):
			return
	_commissioning_completed_actions.append("extraction_cradle")
	_commissioning_phase = "complete"
	_phase = "complete"
	_set_preview_step("inflammashunt_complete")
	_show_note("The cradle closes around the warm housing. The Inflammashunt is stable, portable, and finally clear of the burn branch.", 4.0)

func _first_evidence_id(protocol_id: String) -> String:
	var evidence: Array = (COMMISSIONING_PROTOCOLS[protocol_id] as Dictionary)["evidence"]
	return str((evidence[0] as Dictionary)["id"])

func _enable_commissioning_site(site_id: String, enabled: bool) -> void:
	var site: Node = _commissioning_sites.get(site_id)
	if site != null and is_instance_valid(site):
		site.call("set_interaction_enabled", enabled)

# --- Wrong-approach machinery ---

func _wrong(event: String) -> void:
	wrong_events.append(event)
	var missing: Array = []
	for k in route_info:
		if not bool(route_info[k]):
			missing.append(str(k))
	if missing.is_empty():
		return
	# explicit recon push (spec: after a wrong consequence with missing route info)
	var sched = _get_scheduler()
	if sched == null:
		return
	if not route_info["aster_log"] or not route_info["aster_pipe_diagram"]:
		sched.schedule_after(3.5, func() -> void:
			_show_note("Aster: \"We're missing something. Let me check that terminal back at the junction.\"", 3.2), "inflam_hint")
	elif _party.has("myke") and (not route_info["myke_char_feed"] or not route_info["myke_buffer_ring"]):
		sched.schedule_after(3.5, func() -> void:
			_show_note("Myke: \"We're doing this blind. Let me crawl in and see what we're actually dealing with.\"", 3.2), "inflam_hint")
	elif not route_info["peris_dead_roots"] or not route_info["peris_living_junction"]:
		sched.schedule_after(3.5, func() -> void:
			_show_note("Peris: \"There's something growing underground near the junction. I need to see it before we try anything else.\"", 3.2), "inflam_hint")

## Hold-without-info: counted, and the hint ladder pushes RECONNAISSANCE, never solutions.
func _long_hold(actor: String) -> void:
	long_hold_count += 1
	match mini(long_hold_count, 3):
		1:
			match actor:
				"aster": _show_note("Aster: \"This interface is fighting me.\"", 2.6)
				"peris": _show_note("Peris: \"It is not answering yet.\"", 2.6)
				"myke": _show_note("Myke: \"I don't like guessing at crawler sign.\"", 2.6)
				_: _show_note("Slow, blind work.", 2.2)
		2:
			if _party.has("myke") and actor != "myke":
				_show_note("Myke: \"You look like you're guessing.\"", 2.6)
			else:
				_show_note("Peris: \"Maybe we should look around first.\"", 2.6)
		3:
			var sched = _get_scheduler()
			if sched != null:
				if _party.has("myke"):
					sched.schedule_after(0.4, func() -> void:
						_show_note("Myke: \"There's a crawlspace back there I could fit through. Might see something useful.\"", 3.2), "inflam_hint")
				sched.schedule_after(3.6, func() -> void:
					_show_note("Peris: \"I noticed a growth at that junction. I could follow it underground.\"", 3.2), "inflam_hint")
				sched.schedule_after(6.8, func() -> void:
					_show_note("Aster: \"That terminal at the junction had a hack lock. I should take a look.\"", 3.2), "inflam_hint")

## Waking the dormant systems: the roamers turn on the party, plus `extra` fresh bodies out of
## the shattered ring. The encounter cools on its own once nothing keeps provoking it.
func _wake_chelators(extra: int) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for i in range(extra):
		var eid := "chelator_x%d" % _extra_chelators.size()
		var enemy := Enemy.new()
		enemy.name = "Enemy_%s" % eid
		enemy.position = RING_CENTER + Vector3(-1.2 + 1.2 * float(i), 0.4, 0.8 - 1.6 * float(i % 2))
		enemy.scale = Vector3.ONE * 0.62
		enemy.color = Color(0.5, 0.16, 0.08)
		enemy.move_speed = 2.2
		enemy.detection_range = 0.0
		enemy.windup_duration = 0.4
		enemy.recover_duration = 0.8
		enemy.charge_speed = 6.0
		enemy.attack_range = 1.5
		enemy.charge_damage = 6.0
		enemy._detection_targets.assign(_party)
		add_child(enemy)
		enemy.char_id = eid
		enemy.game_state = gs
		gs.register_character(eid, enemy.position, enemy.move_speed, {})
		if gs.has_method("set_coop_exempt"):
			gs.set_coop_exempt(eid)
		enemy.activate()
		_extra_chelators.append(enemy)
		_enemies.append(enemy)
	_rage_until = _now() + RAGE_SECS
	for enemy in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive() or enemy == _root_enemy:
			continue
		_raged[enemy.char_id] = true
		var target := _nearest_party_to(gs.get_position(enemy.char_id))
		if target != "" and enemy.has_method("engage_target"):
			enemy.engage_target(target)

func _thin_out_chelators() -> void:
	# the food source is gone: the feeders disperse (roam wide, away from the cleared deposit)
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy != _root_enemy and enemy.has_method("set_roam") \
				and not _raged.get(enemy.char_id, false):
			enemy.set_roam(Vector3(33.0, 0.0, -6.0), 1.6)

## The rage cooling + buffer reform pass, on the shared poll.
func _cool_encounters(now: float) -> void:
	if _rage_until > 0.0 and now >= _rage_until:
		_rage_until = -1.0
		var gs = _get_game_state()
		for enemy in _enemies:
			if not is_instance_valid(enemy) or enemy == _root_enemy or not enemy.is_alive():
				continue
			if _raged.get(enemy.char_id, false) and enemy.has_method("re_post"):
				enemy.re_post(_enemy_posts.get(enemy.char_id, enemy.position))
				if enemy.has_method("set_roam"):
					enemy.set_roam(CHAR_A_POS, 2.4)
		_raged.clear()
		_show_note("The crawlers settle. Whatever woke them, it's over.", 2.6)
		if buffer_state == "shattered":
			buffer_state = "reforming"
			var sched = _get_scheduler()
			if sched != null:
				sched.schedule_after(BUFFER_REFORM_SECS, _reform_buffer, "inflam_reform")

func _reform_buffer() -> void:
	buffer_state = "stable"
	for husk in _husks:
		if is_instance_valid(husk):
			husk.visible = true
	_show_note("One by one the husks drift back into their ring around the housing.", 3.0)

# --- The hostile-root recovery sub-puzzle (Chain AI, herd it home with a sac) ---

func _spawn_hostile_root() -> void:
	if _root_enemy != null and is_instance_valid(_root_enemy):
		return
	var gs = _get_game_state()
	if gs == null:
		return
	var root := ChainEnemy.new()
	root.name = "Enemy_hostile_root"
	root.position = ROOT_BASE_POS + Vector3(-1.2, 0.3, -0.8)
	root.segment_count = 7
	add_child(root)
	root.char_id = "hostile_root"
	root.game_state = gs
	gs.register_character("hostile_root", root.position, 2.8, {})
	if gs.has_method("set_coop_exempt"):
		gs.set_coop_exempt("hostile_root")
	# no activate(): the chunk drives the whole behavior deterministically (flee/whip/capture),
	# so the herding reads the same at 1x and 10x
	_root_enemy = root
	_whip_ready.clear()
	_arm_root_poll()

func _arm_root_poll() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("inflam_root")
		sched.schedule_after(0.35, _root_poll, "inflam_root")

func _root_poll() -> void:
	if not is_inside_tree() or _root_enemy == null or not is_instance_valid(_root_enemy):
		return
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		return
	var now := _now()
	var rp: Vector3 = gs.get_position("hostile_root")
	var carrier_live: bool = _sac_carrier != "" and now < _sac_expires and gs.characters.has(_sac_carrier)
	if carrier_live:
		var cp: Vector3 = gs.get_position(_sac_carrier)
		var d := Vector2(rp.x - cp.x, rp.z - cp.z)
		if d.length() < SAC_AURA:
			# recoil from the sac: straight flee, clamped inside the junction room
			var dir := d.normalized() if d.length() > 0.05 else Vector2(1, 0)
			var tx := clampf(rp.x + dir.x * 2.4, JCT_X0 + 1.0, JCT_X1 - 1.0)
			var tz := clampf(rp.z + dir.y * 2.4, -JCT_HALF_Z + 1.0, JCT_HALF_Z - 1.0)
			gs.command_move_to_pos("hostile_root", Vector3(tx, 0.0, tz))
			# boxed in at its base: it goes home
			if Vector2(rp.x - ROOT_BASE_POS.x, rp.z - ROOT_BASE_POS.z).length() < ROOT_CAPTURE_RADIUS:
				gs.command_stop("hostile_root")
				sched.schedule_after(ROOT_RETRACT_DELAY, _retract_root, "inflam_root")
				return
	else:
		# aggressive: threads toward the nearest character and whips at close range
		var target := _nearest_party_to(rp)
		if target != "":
			var tp: Vector3 = gs.get_position(target)
			if Vector2(rp.x - tp.x, rp.z - tp.z).length() > 1.4:
				gs.command_move_to_pos("hostile_root", tp)
			elif now >= float(_whip_ready.get(target, -100.0)):
				_whip_ready[target] = now + 2.2
				# the whip rides the kit's ONE strike path -- dodge windows, sanctuary,
				# concealment, and corpse-skip all come from Enemy._resolve_strike
				_root_enemy.charge_damage = 5.0
				_root_enemy._charge_hit = false
				if _root_enemy._resolve_strike(target):
					_show_note("The root whips %s across the deck." % target.capitalize(), 2.0)
	sched.schedule_after(0.35, _root_poll, "inflam_root")

func _retract_root() -> void:
	if _root_enemy == null or not is_instance_valid(_root_enemy):
		return
	var gs = _get_game_state()
	if gs != null and gs.characters.has("hostile_root"):
		gs.unregister_character("hostile_root")
	_enemies.erase(_root_enemy)
	_root_enemy.queue_free()
	_root_enemy = null
	root_state = "recovering"
	_show_note("The root pours itself back into the crack and stills.", 3.0)
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(ROOT_REGROW_DELAY, func() -> void:
			root_state = "suppressed"
			_show_note("A smaller tendril noses back out of the crack. Tame — and still smothered.", 3.0), "inflam_root")

# --- The popcorn hazard (thermal reset trap): a kit HazardField owns the burn; the chunk only
# --- places it over the junction and toggles it from its own mechanisms (reset lever / valve) ---

func _arm_popcorn_poll() -> void:
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		return
	if _popcorn_field == null or not is_instance_valid(_popcorn_field):
		_popcorn_field = HazardFieldScript.new()
		_popcorn_field.name = "PopcornHazard"
		_popcorn_field.position = Vector3((JCT_X0 + JCT_X1) * 0.5, 0.0, 0.0)
		add_child(_popcorn_field)
	_popcorn_field.setup(gs, sched, Vector2(JCT_X0, -JCT_HALF_Z), Vector2(JCT_X1, JCT_HALF_Z),
		_party, {"dps_tick": POPCORN_DPS_TICK, "interval": 1.0, "tag": "inflam_popcorn"})
	_popcorn_field.set_active(true)

func _end_popcorn(msg: String) -> void:
	_popcorn = false
	gas_sac_state = "idle"
	if _popcorn_field != null and is_instance_valid(_popcorn_field):
		_popcorn_field.set_active(false)
	_show_note(msg, 3.4)

# --- The shared cadence poll ---

func _ensure_polls() -> void:
	if _polls_armed:
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_polls_armed = true
	sched.schedule_after(0.5, _shared_poll, "inflam_shared")

func _shared_poll() -> void:
	if not is_inside_tree():
		return
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		return
	var now := _now()
	if not _entry_played:
		for cid in _party:
			if gs.characters.has(cid) and gs.get_position(cid).x > 10.0:
				_play_entry_beat()
				break
	if _sac_carrier != "" and now >= _sac_expires:
		_sac_carrier = ""
		gas_sac_state = "expired"
		_detach_sac_visual()
		_show_note("The sac wilts and goes quiet. Peris can tend another.", 2.8)
	_cool_encounters(now)
	_check_reunion()
	sched.schedule_after(0.5, _shared_poll, "inflam_shared")

func _play_entry_beat() -> void:
	_entry_played = true
	var sched = _get_scheduler()
	if sched == null:
		return
	if _party.has("myke"):
		_show_note("Myke: \"...I cleared this section. Twice, maybe. The crawlers kept coming back.\"", 3.2)
		sched.schedule_after(3.6, func() -> void:
			_show_note("Aster: \"The fire worked. The crawlers are gone.\"", 2.6), "inflam_entry")
		sched.schedule_after(6.6, func() -> void:
			_show_note("Myke: \"Yeah.\"", 1.8), "inflam_entry")
	else:
		_show_note("Scorched walls, fused conduit — elegant routing under all that burn. Somebody fought here for a long time, and nobody cleaned up.", 4.0)

# --- Helpers ---

func _now() -> float:
	var sched = _get_scheduler()
	return float(sched.get_current_tick()) if sched != null else 0.0

func _nearest_party_to(pos: Vector3) -> String:
	var gs = _get_game_state()
	if gs == null:
		return ""
	var best := ""
	var best_d := INF
	for cid in _party:
		if not gs.characters.has(cid) or gs.is_downed(cid):
			continue
		var d: float = pos.distance_to(gs.get_position(cid))
		if d < best_d:
			best_d = d
			best = str(cid)
	return best

## Route info is EFFICIENCY: informed holds are short, uninformed holds are long.
func _refresh_hold_times() -> void:
	if _valve_it != null:
		_valve_it.dwell_time = HOLDS["valve"][0] if route_info["aster_pipe_diagram"] else HOLDS["valve"][1]
	if _char_a_it != null:
		_char_a_it.dwell_time = (1.0 if char_a_state in ["dry", "burned"]
			else (HOLDS["char_a"][0] if route_info["myke_char_feed"] else HOLDS["char_a"][1]))
	if _char_b_it != null:
		_char_b_it.dwell_time = (1.0 if char_b_state in ["dry", "burned"]
			else (HOLDS["char_b"][0] if route_info["myke_char_feed"] else HOLDS["char_b"][1]))
	if _root_it != null:
		_root_it.dwell_time = HOLDS["root"][0] if route_info["peris_living_junction"] else HOLDS["root"][1]

func _sync_char_visuals() -> void:
	var colors := {
		"dry": Color(0.05, 0.045, 0.04),
		"damp": Color(0.03, 0.032, 0.04),
		"burned": Color(0.12, 0.05, 0.02),
		"cleared": Color(0.14, 0.14, 0.15),
	}
	if _char_a_mesh != null and is_instance_valid(_char_a_mesh):
		_char_a_mesh.material_override = _make_material(colors.get(char_a_state, colors["dry"]))
		_char_a_mesh.visible = char_a_state != "cleared"
	if _char_b_mesh != null and is_instance_valid(_char_b_mesh):
		_char_b_mesh.material_override = _make_material(colors.get(char_b_state, colors["dry"]))
		_char_b_mesh.visible = char_b_state != "cleared"
	_refresh_hold_times()

func _sync_healing_visual() -> void:
	if _healing_glow == null or not is_instance_valid(_healing_glow):
		return
	var spread := 0.8 + healing_zone * (3.4 if device_retrieved else 2.2)
	_healing_glow.scale = Vector3(spread, 1.0, spread)

func _attach_sac_visual(actor: String) -> void:
	_detach_sac_visual()
	var node = _chunk_character_node(actor)
	if node == null:
		return
	_sac_visual = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	_sac_visual.mesh = sphere
	_sac_visual.material_override = _make_material(Color(0.5, 0.7, 0.25), Color(0.7, 0.9, 0.3), 0.8)
	_sac_visual.position = Vector3(0.5, 1.0, 0.0)
	node.add_child(_sac_visual)

func _detach_sac_visual() -> void:
	if _sac_visual != null and is_instance_valid(_sac_visual):
		_sac_visual.queue_free()
	_sac_visual = null

func _chunk_character_node(cid: String) -> Node3D:
	var host := get_parent()
	while host != null and not host.has_method("get_preview_state"):
		host = host.get_parent()
	if host != null and "_characters" in host:
		var chars: Dictionary = host.get("_characters")
		if chars.has(cid):
			return chars[cid]
	return null

# --- Evidence-backed first-clear pacing model and QA surfaces ---

func get_commissioning_clean_action_plan() -> Array:
	var plan: Array = []
	for protocol_id_variant in COMMISSIONING_PROTOCOL_ORDER:
		var protocol_id := str(protocol_id_variant)
		var protocol: Dictionary = COMMISSIONING_PROTOCOLS[protocol_id]
		for evidence_variant in protocol["evidence"] as Array:
			var evidence: Dictionary = evidence_variant
			plan.append(_pacing_action(protocol_id, evidence, "evidence",
				COMMISSIONING_EVIDENCE_SECONDS))
		var choice_id := str(COMMISSIONING_CLEAN_CHOICES[protocol_id])
		var chosen: Dictionary = {}
		for choice_variant in protocol["choices"] as Array:
			if str((choice_variant as Dictionary)["id"]) == choice_id:
				chosen = choice_variant
				break
		plan.append(_pacing_action(protocol_id, chosen, "decision",
			COMMISSIONING_DECISION_SECONDS))
		var resolution: Dictionary = (protocol["resolutions"] as Dictionary)[choice_id]
		plan.append(_pacing_action(protocol_id, resolution, "execution",
			COMMISSIONING_EXECUTION_SECONDS))
	plan.append({
		"id": "extraction_cradle",
		"node_name": "Commissioning_extraction_cradle",
		"protocol": "extraction",
		"category": "extraction_handoff",
		"stage": "extraction",
		"role": "aster",
		"pos": EXTRACTION_POS,
		"work_seconds": EXTRACTION_WORK_SECONDS,
	})
	return plan

func _pacing_action(protocol_id: String, site: Dictionary, stage: String, work_seconds: float) -> Dictionary:
	return {
		"id": str(site["id"]),
		"node_name": "Commissioning_%s" % str(site["id"]),
		"protocol": protocol_id,
		"category": str((COMMISSIONING_PROTOCOLS[protocol_id] as Dictionary)["category"]),
		"stage": stage,
		"role": str(site["role"]),
		"pos": site["pos"],
		"work_seconds": work_seconds,
	}

## Hook order for a normal-input driver.  Route C's two crawl interactions are
## deliberately explicit; a shadow-party driver substitutes ObserveFeeding and
## ExamineCluster for Myke's crawl/read quartet, then uses the same commissioning plan.
func get_normal_input_hook_order() -> Array:
	var order: Array = [
		{"node_name": "AsterLogTerminal", "role": "aster"},
		{"node_name": "PipeDiagram", "role": "aster"},
		{"node_name": "DeadRootNetwork", "role": "peris"},
		{"node_name": "LivingJunction", "role": "peris"},
		{"node_name": "MykeCrawlIn", "role": "myke"},
		{"node_name": "GrateObservation", "role": "myke"},
		{"node_name": "DeviceGap", "role": "myke"},
		{"node_name": "MykeCrawlOut", "role": "myke"},
		{"node_name": "DrainageValve", "role": "aster"},
		{"node_name": "CharDepositA", "role": "myke"},
		{"node_name": "CharDepositB", "role": "myke"},
		{"node_name": "RootTendril", "role": "peris"},
		{"node_name": "DeviceHousing", "role": "aster"},
	]
	for action_variant in get_commissioning_clean_action_plan():
		var action: Dictionary = action_variant
		order.append({"node_name": str(action["node_name"]), "role": str(action["role"])})
	return order

func get_playtime_contract() -> Dictionary:
	var core := _modeled_core_route()
	var commissioning := _modeled_commissioning_route()
	var meaningful_active_seconds := float(core["active_seconds"]) + float(commissioning["active_seconds"])
	var category_seconds: Dictionary = {"route_reconstruction_and_core_solve": float(core["active_seconds"])}
	for category_name in (commissioning["category_seconds"] as Dictionary):
		category_seconds[category_name] = float((commissioning["category_seconds"] as Dictionary)[category_name])
	var max_single_mode_seconds := maxf(float(core["max_single_mode_seconds"]),
		float(commissioning["max_single_mode_seconds"]))
	return {
		"contract_id": "inflammashunt_first_clear_7_to_9_v1",
		"required_first_clear_seconds": 420.0,
		"target_min_seconds": 420.0,
		"target_max_seconds": 540.0,
		"modeled_first_clear_seconds": meaningful_active_seconds,
		"modeled_meaningful_active_seconds": meaningful_active_seconds,
		"meaningful_active_seconds": meaningful_active_seconds,
		"total_play_seconds": meaningful_active_seconds,
		"active_ratio": 1.0,
		"meaningful_active_ratio": 1.0,
		"max_dead_gap_seconds": 0.0,
		"max_single_mode_seconds": max_single_mode_seconds,
		"category_seconds": category_seconds,
		"critical_route_meters": float(core["route_meters"]) + float(commissioning["route_meters"]),
		"modeled_traversal_seconds": float(core["traversal_seconds"]) + float(commissioning["traversal_seconds"]),
		"modeled_interaction_work_seconds": float(core["work_seconds"]) + float(commissioning["work_seconds"]),
		"mandatory_route_observations": 6,
		"mandatory_core_actions": 5,
		"mandatory_commissioning_protocols": COMMISSIONING_PROTOCOL_ORDER.size(),
		"mandatory_commissioning_evidence": 20,
		"mandatory_commissioning_actions": get_commissioning_clean_action_plan().size(),
		"authored_commissioning_station_count": _commissioning_sites.size(),
		"decision_count": 7,
		"branch_count": 10,
		"hard_idle_lock_seconds": 0.0,
		"dialogue_seconds_in_model": 0.0,
		"idle_padding_seconds": 0.0,
		"platform_fallback_seconds": 0.0,
		"core_breakdown": core,
		"commissioning_breakdown": commissioning,
		"model_note": "Exact authored role-route distances at preview walk speeds plus real TIMED_ACTION dwell. Dialogue, scheduler waiting, failed approaches, combat cooling, and platform fallbacks contribute zero seconds.",
	}

func _modeled_core_route() -> Dictionary:
	var route_meters := 0.0
	var traversal_seconds := 0.0
	var max_mode := 0.0
	var role_routes := {
		"aster": [Vector3(4.0, 0.5, 0.0), Vector3(20.0, 0.6, -11.5),
			Vector3(24.0, 0.6, -11.5), VALVE_POS, HOUSING_POS],
		"peris": [Vector3(2.5, 0.5, 1.6), Vector3(20.0, 0.4, 11.5),
			Vector3(24.0, 0.4, 11.5), ROOT_BASE_POS],
		# The crawl's slow internal waypoints are priced separately below.
		"myke": [Vector3(2.5, 0.5, -1.6), Vector3(26.2, 0.0, -4.5)],
	}
	for role_variant in role_routes:
		var role := str(role_variant)
		var points: Array = role_routes[role]
		for index in range(1, points.size()):
			var meters := _planar_distance(points[index - 1], points[index])
			var seconds := meters / float(ROLE_WALK_SPEEDS[role])
			route_meters += meters
			traversal_seconds += seconds
			max_mode = maxf(max_mode, seconds)
	var myke_walk_and_crawl := [
		{"from": Vector3(26.2, 0.0, -4.5), "to": Vector3(28.2, 0.7, -8.0), "speed": 1.1},
		{"from": Vector3(28.2, 0.7, -8.0), "to": Vector3(31.0, 0.0, -12.0), "speed": 1.1},
		{"from": Vector3(31.0, 0.0, -12.0), "to": Vector3(31.8, 0.4, -13.2), "speed": 3.1},
		{"from": Vector3(31.8, 0.4, -13.2), "to": Vector3(34.2, 0.4, -13.2), "speed": 3.1},
		{"from": Vector3(34.2, 0.4, -13.2), "to": Vector3(30.4, 0.0, -11.0), "speed": 3.1},
		{"from": Vector3(30.4, 0.0, -11.0), "to": Vector3(28.2, 0.7, -8.0), "speed": 1.1},
		{"from": Vector3(28.2, 0.7, -8.0), "to": Vector3(25.4, 0.0, -4.0), "speed": 1.1},
		{"from": Vector3(25.4, 0.0, -4.0), "to": CHAR_A_POS, "speed": 3.1},
		{"from": CHAR_A_POS, "to": CHAR_B_POS, "speed": 3.1},
	]
	for leg_variant in myke_walk_and_crawl:
		var leg: Dictionary = leg_variant
		var meters := _planar_distance(leg["from"], leg["to"])
		var seconds := meters / float(leg["speed"])
		route_meters += meters
		traversal_seconds += seconds
		max_mode = maxf(max_mode, seconds)
	var work_seconds := HOLDS["valve"][0] + HOLDS["char_a"][0] + HOLDS["char_b"][0] \
		+ HOLDS["root"][0] + 1.2
	max_mode = maxf(max_mode, HOLDS["valve"][0])
	return {
		"route_meters": route_meters,
		"traversal_seconds": traversal_seconds,
		"work_seconds": work_seconds,
		"active_seconds": traversal_seconds + work_seconds,
		"max_single_mode_seconds": max_mode,
	}

func _modeled_commissioning_route() -> Dictionary:
	# Each next station is state-hidden until the previous action resolves, so this
	# is an ordered role route rather than a sum of simultaneous free-roam paths.
	var last_positions := {
		"aster": HOUSING_POS,
		"peris": ROOT_BASE_POS,
		"myke": CHAR_B_POS,
	}
	var route_meters := 0.0
	var traversal_seconds := 0.0
	var work_seconds := 0.0
	var max_mode := 0.0
	var categories := {}
	for action_variant in get_commissioning_clean_action_plan():
		var action: Dictionary = action_variant
		var role := str(action["role"])
		var pos: Vector3 = action["pos"]
		var meters := _planar_distance(last_positions[role], pos)
		var travel_seconds := meters / float(ROLE_WALK_SPEEDS[role])
		var action_work := float(action["work_seconds"])
		var category := str(action["category"])
		route_meters += meters
		traversal_seconds += travel_seconds
		work_seconds += action_work
		categories[category] = float(categories.get(category, 0.0)) + travel_seconds + action_work
		max_mode = maxf(max_mode, maxf(travel_seconds, action_work))
		last_positions[role] = pos
	return {
		"route_meters": route_meters,
		"traversal_seconds": traversal_seconds,
		"work_seconds": work_seconds,
		"active_seconds": traversal_seconds + work_seconds,
		"max_single_mode_seconds": max_mode,
		"category_seconds": categories,
		"clean_action_count": get_commissioning_clean_action_plan().size(),
	}

func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func get_commissioning_anchor_positions() -> Dictionary:
	var anchors := {"device_housing": HOUSING_POS, "extraction_cradle": EXTRACTION_POS}
	for protocol_id_variant in COMMISSIONING_PROTOCOL_ORDER:
		var protocol_id := str(protocol_id_variant)
		var protocol: Dictionary = COMMISSIONING_PROTOCOLS[protocol_id]
		anchors[protocol_id] = (protocol["evidence"] as Array)[0]["pos"]
	return anchors

func get_decoration_audit() -> Dictionary:
	return _decoration_audit.duplicate(true)

# --- State surfaces (spec: headless_get_state) ---

func headless_get_state() -> Dictionary:
	return {
		"current_step": "complete" if _commissioning_phase == "complete" else (
			"commissioning_%s" % _commissioning_phase if device_retrieved else "ready"),
		"route_info": route_info.duplicate(),
		"valve_open": valve_open,
		"char_a_state": char_a_state,
		"char_b_state": char_b_state,
		"root_state": root_state,
		"buffer_state": buffer_state,
		"gas_sac_state": gas_sac_state,
		"healing_zone": healing_zone,
		"housing_unlocked": housing_unlocked,
		"device_retrieved": device_retrieved,
		"wrong_events": wrong_events.duplicate(),
		"active_hazards": {"popcorn": _popcorn, "hostile_root": _root_enemy != null and is_instance_valid(_root_enemy), "rage": _rage_until > 0.0},
		"long_hold_count": long_hold_count,
		"sac_carrier": _sac_carrier,
		"reports": _reports.duplicate(),
		"commissioning_phase": _commissioning_phase,
		"commissioning_evidence": _commissioning_evidence.duplicate(true),
		"commissioning_choices": _commissioning_choices.duplicate(true),
		"commissioning_resolved": _commissioning_resolved.duplicate(true),
		"commissioning_completed_actions": _commissioning_completed_actions.duplicate(),
		"commissioning_complete": _commissioning_phase == "complete",
		"decoration_audit": _decoration_audit.duplicate(true),
	}

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	st.merge(headless_get_state(), true)
	return st
