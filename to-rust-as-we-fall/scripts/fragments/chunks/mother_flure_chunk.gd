extends "res://scripts/scene_chunks/scene_chunk.gd"

const MOTHER_PORTAL_FRAME_SCENE := preload(
	"res://scenes/props/mother_flure/portal_frame.tscn"
)
const MOTHER_GEAR_VISUAL_SCENE := preload(
	"res://scenes/props/mother_flure/mother_gear.tscn"
)
const MOTHER_RINGS_MEMBRANE_SCENE := preload(
	"res://scenes/props/mother_flure/rings_membrane.tscn"
)
const MOTHER_GEAR_VISUAL_IDENTITY := "mother_gear_v1"

const FLOOR_CENTER := Vector3(58.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(120.0, 0.1, 54.0)
const CANONICAL_PARTY := ["aster", "peris", "endo"]
const WORLD_SLOT := {
	"slot_id": "act1_mother_flure",
	"act": 1,
	"region": "Mother Flure Chamber",
	"entry_shelter_id": "shelter_5",
	"exit_shelter_id": "shelter_6",
	"entry_anchor": "processing_stacks_exit",
	"exit_anchor": "residential_rings_approach",
	"canonical_party": CANONICAL_PARTY,
	"preview_party_preset": "full_party_full_health",
	"next_slot": "act1_residential_rings",
}

const BOARD_ORIGIN := Vector3(42.0, 0.0, -18.0)
const BOARD_CELL_SIZE := 6.0
const BOARD_ROWS := ["A", "B", "C", "D", "E", "F"]
const ROOT_CENTER_Y := 0.42
const ROOT_SWARM_Y_OFFSET := -0.32
const ROOT_GAP := 0.6
const ROOT_WIDTH := 4.2
const ROOT_SWARM_EXTRA_LENGTH := 2.2
const ROOT_SWARM_EXTRA_WIDTH := 0.7

const BASE_PORTAL_POS := Vector3(24.0, 0.45, 0.0)
const HIDE_SPOT_POS := Vector3(32.0, 0.0, 17.0)
const COLLAPSE_POS := Vector3(44.0, 0.0, 20.0)
const GEAR_POS := Vector3(35.0, 0.42, 8.4)
const CARRY_ROUTE_WEST_APRON := Vector3(32.0, 0.5, 24.0)
const CARRY_ROUTE_SOUTH_PASS := Vector3(67.0, 0.5, 24.0)
const CARRY_ROUTE_EAST_APRON := Vector3(82.0, 0.5, 24.0)
const INSTALL_SOCKET_POS := Vector3(93.0, 0.55, 0.0)
const MOTHER_POS := Vector3(100.0, 0.95, 0.0)
const EXIT_POS := Vector3(112.0, 0.45, -22.0)
# This band belongs to human first-clear playtesting. The deterministic contract
# below reports only authored movement/work and never invents reasoning time to
# make the model reach this target.
const HUMAN_FIRST_CLEAR_TARGET_MIN_SECONDS := 300.0
const HUMAN_FIRST_CLEAR_TARGET_MAX_SECONDS := 480.0
const ASTER_WALK_SPEED := 3.2
const PERIS_WALK_SPEED := 3.0
const ENDO_WALK_SPEED := 2.8
const TERMINAL_WORK_SECONDS := 3.2
const PORTAL_CALIBRATION_SECONDS := 1.4
const ROOT_WORK_SECONDS := 4.2
const GEAR_LIFT_SECONDS := 4.5
const REPAIR_MOUNT_SECONDS := 6.0
const MOTHER_TEND_SECONDS := 7.5
const EXIT_HANDOFF_SECONDS := 3.0
const EXIT_INTERACTION_RADIUS := 2.2
const INTERACTION_POSITION_TOLERANCE := 0.35

const CLEAN_ROOT_MOVES := [
	{"terminal": "term_gamma", "root": "gear_latch", "direction": 1},
	{"terminal": "term_beta", "root": "socket_brace", "direction": 1},
	{"terminal": "term_alpha", "root": "spine_gate", "direction": -1},
	{"terminal": "term_beta", "root": "socket_brace", "direction": 1},
	{"terminal": "term_gamma", "root": "tending_step", "direction": -1},
	{"terminal": "term_beta", "root": "crossbar", "direction": -1},
	{"terminal": "term_beta", "root": "bloom_curtain", "direction": 1},
	{"terminal": "term_alpha", "root": "mother_veil", "direction": 1},
	{"terminal": "term_alpha", "root": "mother_veil", "direction": 1},
]
const REPAIR_POINT_ORDER := ["edge_relief", "load_regulator", "bloom_bypass"]
const CORRECT_REPAIR_ID := "load_regulator"
const REPAIR_POINT_DEFS := {
	"edge_relief": {
		"label": "EDGE RELIEF",
		"position": Vector3(89.5, 0.55, -4.0),
		"color": Color(0.56, 0.72, 0.88),
		"flare_root": "spine_gate",
		"flare_direction": 1,
		"flare_note": "The edge relief drinks pressure that was never the real problem. The spine gate drops back into the carry lane and the gear spits back out.",
	},
	"load_regulator": {
		"label": "LOAD REGULATOR",
		"position": INSTALL_SOCKET_POS,
		"color": Color(0.72, 0.9, 0.58),
	},
	"bloom_bypass": {
		"label": "BLOOM BYPASS",
		"position": Vector3(89.5, 0.55, 4.0),
		"color": Color(0.88, 0.72, 0.96),
		"flare_root": "tending_step",
		"flare_direction": 1,
		"flare_note": "The bloom bypass sheds signal into the south lane instead of taking weight off the mother. The tending step skews and the gear gets rejected.",
	},
}

const TERM_ALPHA_POS := Vector3(16.0, 0.85, -8.0)
const TERM_BETA_POS := Vector3(16.0, 0.85, 0.0)
const TERM_GAMMA_POS := Vector3(16.0, 0.85, 8.0)

const SERVICE_ALPHA_POS := Vector3(84.0, 0.25, -11.8)
const SERVICE_BETA_POS := Vector3(83.5, 0.25, 1.5)
const SERVICE_GAMMA_POS := Vector3(70.0, 0.25, 14.0)
const REMOTE_SPAWN_OFFSET := Vector3(-2.8, 0.0, 0.0)

const BODY_POSITIONS := {
	"body_a": Vector3(50.0, 0.18, 24.0),
	"body_b": Vector3(55.0, 0.18, 24.6),
	"body_c": Vector3(60.0, 0.18, 23.6),
	"body_d": Vector3(65.0, 0.18, 24.2),
}
const BODY_NAMES := {
	"body_a": "Brobla",
	"body_b": "Senchy",
	"body_c": "Worker 3",
	"body_d": "Worker 4",
}

const SPAWNS := {
	"aster": Vector3(8.0, 0.0, 0.0),
	"peris": Vector3(5.8, 0.0, 1.8),
	"endo": Vector3(3.6, 0.0, -1.8),
}

const TERMINAL_ORDER := ["term_alpha", "term_beta", "term_gamma"]
const TERMINAL_SERVICES := {
	"term_alpha": ["north_rail", "spine_gate", "survey_rib", "mother_veil"],
	"term_beta": ["socket_brace", "bloom_curtain", "crossbar"],
	"term_gamma": ["gear_latch", "carry_spur", "tending_step"],
}
const TERMINAL_SERVICE_POSITIONS := {
	"term_alpha": SERVICE_ALPHA_POS,
	"term_beta": SERVICE_BETA_POS,
	"term_gamma": SERVICE_GAMMA_POS,
}

const ROOT_ORDER := [
	"north_rail",
	"spine_gate",
	"survey_rib",
	"gear_latch",
	"mother_veil",
	"socket_brace",
	"bloom_curtain",
	"crossbar",
	"carry_spur",
	"tending_step",
]
const ROOT_DEFS := {
	"north_rail": {"label": "NORTH RAIL", "short": "A", "orientation": "horizontal", "length": 3, "fixed_line": 0, "anchor": 0, "min_anchor": 0, "max_anchor": 3, "terminal": "term_alpha", "color": Color(0.52, 0.34, 0.18), "swarm_color": Color(0.84, 0.58, 0.24)},
	"spine_gate": {"label": "SPINE GATE", "short": "B", "orientation": "vertical", "length": 2, "fixed_line": 3, "anchor": 1, "min_anchor": 0, "max_anchor": 3, "terminal": "term_alpha", "color": Color(0.48, 0.32, 0.18), "swarm_color": Color(0.86, 0.6, 0.28)},
	"survey_rib": {"label": "SURVEY RIB", "short": "C", "orientation": "horizontal", "length": 2, "fixed_line": 0, "anchor": 4, "min_anchor": 3, "max_anchor": 4, "terminal": "term_alpha", "color": Color(0.58, 0.38, 0.22), "swarm_color": Color(0.9, 0.64, 0.3)},
	"gear_latch": {"label": "GEAR LATCH", "short": "D", "orientation": "horizontal", "length": 2, "fixed_line": 1, "anchor": 0, "min_anchor": 0, "max_anchor": 2, "terminal": "term_gamma", "color": Color(0.44, 0.3, 0.18), "swarm_color": Color(0.82, 0.54, 0.24)},
	"mother_veil": {"label": "MOTHER VEIL", "short": "E", "orientation": "vertical", "length": 2, "fixed_line": 5, "anchor": 1, "min_anchor": 1, "max_anchor": 3, "terminal": "term_alpha", "color": Color(0.56, 0.36, 0.2), "swarm_color": Color(0.94, 0.68, 0.32)},
	"socket_brace": {"label": "SOCKET BRACE", "short": "F", "orientation": "vertical", "length": 2, "fixed_line": 1, "anchor": 2, "min_anchor": 2, "max_anchor": 4, "terminal": "term_beta", "color": Color(0.5, 0.34, 0.18), "swarm_color": Color(0.84, 0.6, 0.26)},
	"bloom_curtain": {"label": "BLOOM CURTAIN", "short": "G", "orientation": "vertical", "length": 2, "fixed_line": 4, "anchor": 2, "min_anchor": 2, "max_anchor": 4, "terminal": "term_beta", "color": Color(0.54, 0.36, 0.2), "swarm_color": Color(0.92, 0.66, 0.3)},
	"crossbar": {"label": "CROSSBAR", "short": "H", "orientation": "horizontal", "length": 3, "fixed_line": 3, "anchor": 2, "min_anchor": 1, "max_anchor": 3, "terminal": "term_beta", "color": Color(0.46, 0.3, 0.16), "swarm_color": Color(0.8, 0.54, 0.22)},
	"carry_spur": {"label": "CARRY SPUR", "short": "I", "orientation": "vertical", "length": 3, "fixed_line": 0, "anchor": 3, "min_anchor": 2, "max_anchor": 3, "terminal": "term_gamma", "color": Color(0.42, 0.28, 0.16), "swarm_color": Color(0.76, 0.52, 0.24)},
	"tending_step": {"label": "TENDING STEP", "short": "J", "orientation": "horizontal", "length": 2, "fixed_line": 4, "anchor": 3, "min_anchor": 2, "max_anchor": 4, "terminal": "term_gamma", "color": Color(0.6, 0.42, 0.22), "swarm_color": Color(0.94, 0.7, 0.36)},
}

const PORTAL_DURATION := 18.0
const PORTAL_TRANSIT_SECONDS := 0.9
const ROOT_SLIDE_DURATION := 2.8
const ROOT_SWARM_LAG := 0.95
const ROOT_SWARM_DURATION := 1.5
const ROOT_HAZARD_DAMAGE := 8.0
const ROOT_HAZARD_INTERVAL := 0.85
const BODY_YIELD_PER_CORPSE := 2
const BODY_SOURCE_OFFSETS := [
	Vector3(-0.34, 0.38, -0.14),
	Vector3(0.34, 0.38, 0.14),
]

# Mother Flure owns its root/portal transits, two physical route commitments, and the finite corpse
# source ledger. Settled endpoints, reserved targets, item IDs,
# actors, phases, and absolute scheduler deadlines are portable truth; meshes, collision shapes,
# labels, and dynamic grid blockers are only presenters.
const MOTHER_AUTHORITY_VERSION := 5
const MOTHER_AUTHORITY_PREFIX := "runtime:mother_flure:"
const PORTAL_TRANSIT_IDLE := "idle"
const PORTAL_TRANSIT_OUTBOUND := "outbound"
const PORTAL_TRANSIT_RETURNING := "returning"
const COLLAPSE_PHASE_BLOCKED := "blocked"
const COLLAPSE_PHASE_SHIFTING := "shifting"
const COLLAPSE_PHASE_CLEARED := "cleared"
const COLLAPSE_SHIFT_SECONDS := 2.4
const COLLAPSE_SHIFT_OFFSET := Vector3(0.0, 0.0, 5.4)
const COLLAPSE_BLOCKER_CENTER := COLLAPSE_POS + Vector3(0.0, 1.0, -2.0)
const COLLAPSE_BLOCKER_SIZE := Vector3(2.8, 2.0, 8.2)
const RINGS_GATE_PHASE_SEALED := "sealed"
const RINGS_GATE_PHASE_OPENING := "opening"
const RINGS_GATE_PHASE_OPEN := "open"
const RINGS_GATE_OPEN_SECONDS := 1.8
const RINGS_GATE_OPEN_OFFSET := Vector3(0.0, 3.0, 0.0)
const RINGS_GATE_BLOCKER_CENTER := EXIT_POS + Vector3(0.0, 1.3, 0.0)
const RINGS_GATE_BLOCKER_SIZE := Vector3(3.0, 2.3, 0.24)
const BODY_CLAIM_IDLE := "idle"
const BODY_CLAIMING := "claiming"

var _roots: Dictionary = {}
var _active_terminal_id := ""
var _portal_open_until := 0.0
var _peris_remote_terminal := ""
var _portal_transit_phase := PORTAL_TRANSIT_IDLE
var _portal_transit_terminal := ""
var _collapse_cleared := false
var _collapse_phase := COLLAPSE_PHASE_BLOCKED
var _collapse_shift_started_at := -1.0
var _collapse_shift_deadline := -1.0
var _gear_item_id := ""
var _gear_installed := false
var _installed_repair_id := ""
var _mother_tended := false
var _route_phase := "investigate"
var _exit_reached := false
var _rings_gate_phase := RINGS_GATE_PHASE_SEALED
var _rings_gate_started_at := -1.0
var _rings_gate_deadline := -1.0
## Absolute EventScheduler deadline for the next whole-chamber root contact sample. The root mat
## is gameplay geometry; sampling it from `_process` would make both the first bite and its cadence
## depend on render/headless call frequency, so one saved global deadline owns every bite.
var _hazard_next_tick := -1.0
var _terminal_readings_seen: Array[String] = []
var _body_remaining: Dictionary = {}
## Every harvestable unit exists as one source-tagged GameState item before interaction. Claimed
## IDs remain in this finite ledger even after digestion removes the live item; old counter-only
## saves record their already-spent units separately instead of inventing a carrier.
var _body_source_item_ids: Dictionary = {}
var _body_claimed_item_ids: Array[String] = []
var _body_legacy_claimed: Dictionary = {}
var _body_claim_phase := BODY_CLAIM_IDLE
var _body_claim_item_id := ""
var _body_claim_body_id := ""
var _body_claimed_by := ""
var _body_claim_serial := 0
var _repair_attempts: Array[String] = []

var _mother_authority_baseline: Dictionary = {}
var _mother_authority_initialized := false
var _restoring_mother_authority := false
var _mother_signal_game_state: Object = null

var _terminal_materials: Dictionary = {}
var _terminal_labels: Dictionary = {}
var _terminal_interactables: Dictionary = {}
var _root_control_interactables: Dictionary = {}
var _portal_base_frame: Node3D
var _portal_base_fill: MeshInstance3D
var _portal_base_material: StandardMaterial3D
var _portal_remote_frame: Node3D
var _portal_remote_fill: MeshInstance3D
var _portal_remote_material: StandardMaterial3D
var _portal_remote_label: Label3D
var _portal_entry_interactable
var _portal_return_interactable
var _gear_interactable
var _install_interactable
var _repair_interactables: Dictionary = {}
var _collapse_interactable
var _mother_interactable
var _exit_interactable

var _body_materials: Dictionary = {}
var _body_labels: Dictionary = {}
var _body_interactables: Dictionary = {}
var _mother_bloom_materials: Array[StandardMaterial3D] = []
var _repair_point_materials: Dictionary = {}
var _repair_point_labels: Dictionary = {}
var _exit_material: StandardMaterial3D
var _exit_label: Label3D
var _rings_membrane_mesh: MeshInstance3D
var _installed_gear_root: Node3D
var _collapse_debris_root: Node3D
var _collapse_blocker_body: StaticBody3D
var _collapse_collision_shape: CollisionShape3D
var _exit_gate_root: Node3D
var _rings_gate_blocker_body: StaticBody3D
var _rings_gate_collision_shape: CollisionShape3D

var _aster_overlay_root: Node3D
var _peris_overlay_root: Node3D
var _endo_overlay_root: Node3D
var _peris_overlay_labels: Dictionary = {}
var _endo_overlay_materials: Dictionary = {}

func _build_chunk() -> void:
	_build_chamber_shell()
	_build_environment_decoration()
	_build_terminal_bank()
	_build_root_board()
	_build_service_alcoves()
	_build_portal_bank()
	_build_gear_station()
	_build_install_socket()
	_build_physical_repair_evidence()
	_build_mother()
	_build_exit_handoff()
	_build_collapse_offshoot()
	_build_hide_spot()
	_build_overlay_roots()
	_reset_mother_locals_to_defaults()
	_apply_mother_presenters()
	_initialize_mother_authority()

func _process(delta: float) -> void:
	_update_runtime(delta)

func headless_process(delta: float) -> void:
	_update_runtime(delta)

func get_scene_title() -> String:
	return "Mother Flure"

func get_scene_help() -> String:
	return "Run the full Mother chamber as a party investigation. Shift the 6x6 root board, compare the live terminal/overlay reads with the freight wear, caretaker tool marks, and three repair mounts, then let Endo commit the two-hand gear. Once the correct repair and east lane are stable, Peris can tend the mother and open the Rings handoff."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"portal_bank": BASE_PORTAL_POS,
		"gear": GEAR_POS,
		"install_socket": INSTALL_SOCKET_POS,
		"edge_relief": _repair_point_position("edge_relief"),
		"load_regulator": _repair_point_position("load_regulator"),
		"bloom_bypass": _repair_point_position("bloom_bypass"),
		"mother": MOTHER_POS,
		"exit": EXIT_POS,
		"collapse": COLLAPSE_POS,
		"hide_spot": HIDE_SPOT_POS,
		"service_alpha": SERVICE_ALPHA_POS,
		"service_beta": SERVICE_BETA_POS,
		"service_gamma": SERVICE_GAMMA_POS,
	}, true)
	return anchors

func get_world_slot() -> Dictionary:
	return WORLD_SLOT.duplicate(true)

func get_preview_time_state() -> Dictionary:
	return {
		"day": 5,
		"time": 0.61,
		"routing_mode": "safe",
		"note_default": "This preview drops the full Mother chamber into the regular game UI with the party topped off. Read the live system state and physical wear already present in the room, clear the board, and decide which repair point should take Endo's two-hand gear.",
	}


func get_playtime_contract() -> Dictionary:
	var traversal := _modeled_traversal_breakdown()
	var terminal_work := 0.0
	for move in CLEAN_ROOT_MOVES:
		if str(move.get("terminal", "")) != "term_alpha":
			terminal_work += TERMINAL_WORK_SECONDS
	var work := {
		"terminal_control_seconds": terminal_work,
		"portal_calibration_seconds": float(CLEAN_ROOT_MOVES.size()) * 2.0 * PORTAL_CALIBRATION_SECONDS,
		"portal_transit_seconds": float(CLEAN_ROOT_MOVES.size()) * 2.0 * PORTAL_TRANSIT_SECONDS,
		"root_shift_work_seconds": float(CLEAN_ROOT_MOVES.size()) * ROOT_WORK_SECONDS,
		"gear_lift_seconds": GEAR_LIFT_SECONDS,
		"repair_mount_seconds": REPAIR_MOUNT_SECONDS,
		"mother_tend_seconds": MOTHER_TEND_SECONDS,
		"rings_gate_open_seconds": RINGS_GATE_OPEN_SECONDS,
		"exit_handoff_seconds": EXIT_HANDOFF_SECONDS,
	}
	var work_seconds := 0.0
	for seconds in work.values():
		work_seconds += float(seconds)
	var movement_seconds := float(traversal.get("seconds", 0.0))
	var mechanical_seconds := movement_seconds + work_seconds
	var category_seconds := {
		"board_control": float(traversal.get("aster_terminal_meters", 0.0)) / ASTER_WALK_SPEED + float(work.get("terminal_control_seconds", 0.0)),
		"portal_and_root_service": (
			float(traversal.get("peris_portal_meters", 0.0))
			+ float(traversal.get("remote_service_meters", 0.0))
		) / PERIS_WALK_SPEED + float(work.get("portal_calibration_seconds", 0.0)) \
			+ float(work.get("portal_transit_seconds", 0.0)) \
			+ float(work.get("root_shift_work_seconds", 0.0)),
		"gear_and_repair": float(traversal.get("endo_gear_meters", 0.0)) / ENDO_WALK_SPEED + float(work.get("gear_lift_seconds", 0.0)) + float(work.get("repair_mount_seconds", 0.0)),
		"mother_and_handoff": (
			float(traversal.get("peris_mother_meters", 0.0))
			+ float(traversal.get("peris_handoff_meters", 0.0))
		) / PERIS_WALK_SPEED + float(work.get("mother_tend_seconds", 0.0)) \
			+ float(work.get("rings_gate_open_seconds", 0.0)) \
			+ float(work.get("exit_handoff_seconds", 0.0)),
	}
	return {
		# Human observation, hypothesis formation, and recoverable error determine
		# whether the encounter actually lands in this band; they are not fake dwell.
		"human_first_clear_target_min_seconds": HUMAN_FIRST_CLEAR_TARGET_MIN_SECONDS,
		"human_first_clear_target_max_seconds": HUMAN_FIRST_CLEAR_TARGET_MAX_SECONDS,
		"human_first_clear_target_basis": "playtest_only",
		"modeled_mechanical_workload_seconds": mechanical_seconds,
		"modeled_first_clear_seconds": mechanical_seconds,
		"meaningful_active_seconds": mechanical_seconds,
		"total_play_seconds": mechanical_seconds,
		"meaningful_active_ratio": 1.0,
		"active_ratio": 1.0,
		"max_dead_gap_seconds": 0.0,
		"max_single_mode_seconds": _modeled_max_single_mode_seconds(),
		"category_seconds": category_seconds,
		"controlled_traversal_meters": float(traversal.get("meters", 0.0)),
		"critical_route_meters": float(traversal.get("meters", 0.0)),
		"modeled_traversal_seconds": movement_seconds,
		"modeled_interaction_work_seconds": work_seconds,
		"modeled_reasoning_seconds": 0.0,
		"hard_idle_lock_seconds": 0.0,
		"root_settle_seconds_counted": 0.0,
		"mandatory_diagnostic_clicks": 0,
		"mandatory_care_node_clicks": 0,
		"decision_count": 2,
		"branch_count": REPAIR_POINT_ORDER.size(),
		"traversal_breakdown": traversal,
		"work_breakdown": work,
		"model_note": "Deterministic movement and required interactions only. Physical observation, hypothesis formation, root animation settling, portal expiry, wrong-repair recovery, optional roots, corpse harvesting, and human reading time are deliberately not fabricated into the model.",
	}

func _modeled_traversal_breakdown() -> Dictionary:
	var aster_path := [
		SPAWNS["aster"], TERM_GAMMA_POS, TERM_BETA_POS, TERM_ALPHA_POS,
		TERM_BETA_POS, TERM_GAMMA_POS, TERM_BETA_POS, TERM_BETA_POS,
		TERM_ALPHA_POS, TERM_ALPHA_POS,
	]
	var aster_meters := _planar_path_distance(aster_path)

	var return_pos := BASE_PORTAL_POS + Vector3(2.6, 0.0, 0.0)
	var peris_portal_meters := _planar_distance(SPAWNS["peris"], BASE_PORTAL_POS)
	peris_portal_meters += _planar_distance(return_pos, BASE_PORTAL_POS) * float(CLEAN_ROOT_MOVES.size() - 1)
	var remote_service_meters := 0.0
	for move in CLEAN_ROOT_MOVES:
		var terminal_id := str(move.get("terminal", ""))
		var root_id := str(move.get("root", ""))
		var direction := int(move.get("direction", 0))
		var service_spawn := _terminal_service_spawn(terminal_id)
		var bud_pos := _modeled_service_bud_position(terminal_id, root_id, direction)
		var service_return := _terminal_service_position(terminal_id) + Vector3(-1.25, 0.0, 0.0)
		remote_service_meters += _planar_distance(service_spawn, bud_pos)
		remote_service_meters += _planar_distance(bud_pos, service_return)
	var peris_mother_meters := _planar_distance(return_pos, MOTHER_POS)
	var peris_handoff_meters := _planar_distance(MOTHER_POS, EXIT_POS)
	var peris_meters := peris_portal_meters + remote_service_meters \
		+ peris_mother_meters + peris_handoff_meters

	var endo_path: Array[Vector3] = [Vector3(SPAWNS["endo"]), GEAR_POS]
	endo_path.append_array(get_caretaker_carry_route(
		GEAR_POS,
		_repair_point_position(CORRECT_REPAIR_ID)
	))
	var endo_gear_meters := _planar_path_distance(endo_path)
	return {
		"meters": aster_meters + peris_meters + endo_gear_meters,
		"seconds": aster_meters / ASTER_WALK_SPEED \
			+ peris_meters / PERIS_WALK_SPEED \
			+ endo_gear_meters / ENDO_WALK_SPEED,
		"aster_meters": aster_meters,
		"peris_meters": peris_meters,
		"endo_meters": endo_gear_meters,
		"aster_terminal_meters": aster_meters,
		"peris_portal_meters": peris_portal_meters,
		"remote_service_meters": remote_service_meters,
		"peris_mother_meters": peris_mother_meters,
		"peris_handoff_meters": peris_handoff_meters,
		"endo_gear_meters": endo_gear_meters,
	}

func _modeled_max_single_mode_seconds() -> float:
	var longest := maxf(
		maxf(TERMINAL_WORK_SECONDS, ROOT_WORK_SECONDS),
		maxf(MOTHER_TEND_SECONDS, REPAIR_MOUNT_SECONDS)
	)
	var aster_path := [
		SPAWNS["aster"], TERM_GAMMA_POS, TERM_BETA_POS, TERM_ALPHA_POS,
		TERM_BETA_POS, TERM_GAMMA_POS, TERM_BETA_POS, TERM_BETA_POS,
		TERM_ALPHA_POS, TERM_ALPHA_POS,
	]
	longest = maxf(longest, _longest_path_leg_seconds(aster_path, ASTER_WALK_SPEED))
	var return_pos := BASE_PORTAL_POS + Vector3(2.6, 0.0, 0.0)
	longest = maxf(longest, _longest_path_leg_seconds([
		SPAWNS["peris"], BASE_PORTAL_POS, return_pos, MOTHER_POS, EXIT_POS,
	], PERIS_WALK_SPEED))
	var endo_path: Array[Vector3] = [Vector3(SPAWNS["endo"]), GEAR_POS]
	endo_path.append_array(get_caretaker_carry_route(
		GEAR_POS,
		_repair_point_position(CORRECT_REPAIR_ID)
	))
	longest = maxf(longest, _longest_path_leg_seconds(endo_path, ENDO_WALK_SPEED))
	for move in CLEAN_ROOT_MOVES:
		var terminal_id := str(move.get("terminal", ""))
		var root_id := str(move.get("root", ""))
		var direction := int(move.get("direction", 0))
		longest = maxf(longest, _longest_path_leg_seconds([
			_terminal_service_spawn(terminal_id),
			_modeled_service_bud_position(terminal_id, root_id, direction),
			_terminal_service_position(terminal_id) + Vector3(-1.25, 0.0, 0.0),
		], PERIS_WALK_SPEED))
	return longest

func _longest_path_leg_seconds(points: Array, speed: float) -> float:
	var longest := 0.0
	for index in range(1, points.size()):
		longest = maxf(longest, _planar_distance(Vector3(points[index - 1]), Vector3(points[index])) / maxf(speed, 0.1))
	return longest

func _modeled_service_bud_position(terminal_id: String, root_id: String, direction: int) -> Vector3:
	var service_roots: Array = TERMINAL_SERVICES.get(terminal_id, [])
	var root_index := service_roots.find(root_id)
	if root_index < 0:
		return _terminal_service_position(terminal_id)
	var row_pos := _service_row_position(terminal_id, root_index, service_roots.size())
	return row_pos + Vector3(-1.55 if direction < 0 else 1.55, 0.0, -0.48)

func _planar_path_distance(points: Array) -> float:
	var total := 0.0
	for index in range(1, points.size()):
		total += _planar_distance(Vector3(points[index - 1]), Vector3(points[index]))
	return total

func _planar_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))

func get_caretaker_carry_route(from: Vector3, destination: Vector3) -> Array[Vector3]:
	# The south caretaker pass is the legible no-immunity route around the live
	# root board. Reverse the same physical path when recovering a rejected gear.
	var waypoints: Array[Vector3] = []
	if from.x <= destination.x:
		waypoints.assign([
			CARRY_ROUTE_WEST_APRON,
			CARRY_ROUTE_SOUTH_PASS,
			CARRY_ROUTE_EAST_APRON,
		])
	else:
		waypoints.assign([
			CARRY_ROUTE_EAST_APRON,
			CARRY_ROUTE_SOUTH_PASS,
			CARRY_ROUTE_WEST_APRON,
		])
	waypoints.append(destination)
	return waypoints

func get_preview_state() -> Dictionary:
	var current_tick := _get_scheduler_tick()
	var exit_arrival := _canonical_party_exit_arrival()
	var portal_transit := _portal_transit_state()
	var roots := {}
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		var root: Dictionary = _roots[root_id]
		var cells: Array[String] = []
		for cell in _root_cells(root):
			cells.append(_cell_name(cell))
		roots[root_id] = {
			"anchor": int(root.get("anchor", 0)),
			"target_anchor": int(root.get("target_anchor", -1)),
			"cells": cells,
			"moving": _root_move_in_flight(root),
			"terminal": str(root.get("terminal", "")),
			"orientation": str(root.get("orientation", "")),
		}
	return {
		"active_terminal": _active_terminal_id,
		"portal_open": _is_portal_open(current_tick),
		"portal_time_remaining": maxf(0.0, _portal_open_until - current_tick),
		"peris_remote_terminal": _peris_remote_terminal,
		"portal_transit_phase": _portal_transit_phase,
		"portal_transit_terminal": _portal_transit_terminal,
		"portal_transit_active": not portal_transit.is_empty(),
		"portal_transit_progress": float(portal_transit.get("progress", 0.0)),
		"portal_transit_remaining": float(portal_transit.get("remaining", 0.0)),
		"collapse_cleared": _collapse_cleared,
		"collapse_phase": _collapse_phase,
		"collapse_shift_deadline": _collapse_shift_deadline,
		"collapse_shift_progress": _collapse_shift_progress(current_tick),
		"collapse_physically_blocked": _collapse_phase != COLLAPSE_PHASE_CLEARED,
		"gear_installed": _gear_installed,
		"installed_repair": _installed_repair_id,
		"installed_gear_visible": is_instance_valid(_installed_gear_root) and _installed_gear_root.visible,
		"gear_pocket_open": _is_gear_pocket_open(),
		"socket_lane_open": _is_socket_lane_open(),
		"mother_lane_clear": _is_mother_lane_clear(),
		"mother_tended": _mother_tended,
		"route_phase": _route_phase,
		"rings_gate_phase": _rings_gate_phase,
		"rings_gate_deadline": _rings_gate_deadline,
		"rings_gate_progress": _rings_gate_progress(current_tick),
		"hazard_next_tick": _hazard_next_tick,
		"rings_gate_physically_open": _rings_gate_phase == RINGS_GATE_PHASE_OPEN,
		"exit_open": _route_phase == "handoff" and _rings_gate_phase == RINGS_GATE_PHASE_OPEN,
		"exit_party_ready": bool(exit_arrival.get("ready", false)),
		"exit_party_arrival": exit_arrival,
		"exit_reached": _exit_reached,
		"complete": _route_phase == "complete",
		"repair_attempts": _repair_attempts.duplicate(),
		"repair_target": CORRECT_REPAIR_ID,
		"diagnosis": _diagnosis_summary(),
		"terminal_readings_seen": _terminal_readings_seen.duplicate(),
		"physical_repair_evidence_present": find_child("MotherPhysicalRepairEvidence", true, false) != null,
		"roots": roots,
		"bodies": _body_remaining.duplicate(true),
		"body_source_item_ids": _body_source_item_ids.duplicate(true),
		"body_claimed_item_ids": _body_claimed_item_ids.duplicate(),
		"body_legacy_claimed": _body_legacy_claimed.duplicate(true),
		"body_claim_phase": _body_claim_phase,
		"body_claim_item_id": _body_claim_item_id,
		"body_claim_body_id": _body_claim_body_id,
		"body_claimed_by": _body_claimed_by,
		"body_claim_serial": _body_claim_serial,
		"body_physical_source_count": _body_physical_source_count(),
		"gear_item": _gear_item_id,
	}

func reset_preview_state() -> void:
	var gs = _get_game_state()
	if gs != null and gs.has_method("is_external_traversal_active") \
			and bool(gs.call("is_external_traversal_active", "peris")):
		var transit := _portal_transit_state()
		if not _portal_identity_from_state(transit).is_empty() \
				and gs.has_method("cancel_external_traversal"):
			gs.call("cancel_external_traversal", "peris", &"mother_reset")
	_cancel_mother_callbacks()
	_remove_loose_mother_gears()
	_remove_all_mother_body_lysate()
	_reset_mother_locals_to_defaults()
	_spawn_gear(GEAR_POS)
	_spawn_fresh_body_sources()
	_apply_mother_presenters()
	_mother_authority_initialized = _get_game_state() != null
	_start_root_hazard_cadence()
	_mother_authority_baseline = _mother_authority_state().duplicate(true)
	_publish_mother_authority()

func _reset_mother_locals_to_defaults() -> void:
	_restoring_mother_authority = true
	_active_terminal_id = ""
	_portal_open_until = 0.0
	_peris_remote_terminal = ""
	_portal_transit_phase = PORTAL_TRANSIT_IDLE
	_portal_transit_terminal = ""
	_collapse_cleared = false
	_collapse_phase = COLLAPSE_PHASE_BLOCKED
	_collapse_shift_started_at = -1.0
	_collapse_shift_deadline = -1.0
	_gear_item_id = ""
	_gear_installed = false
	_installed_repair_id = ""
	_mother_tended = false
	_route_phase = "investigate"
	_exit_reached = false
	_rings_gate_phase = RINGS_GATE_PHASE_SEALED
	_rings_gate_started_at = -1.0
	_rings_gate_deadline = -1.0
	_hazard_next_tick = -1.0
	_terminal_readings_seen.clear()
	_repair_attempts.clear()
	_body_remaining = {}
	_body_source_item_ids = {}
	_body_claimed_item_ids.clear()
	_body_legacy_claimed = {}
	for body_id in BODY_POSITIONS.keys():
		_body_remaining[body_id] = BODY_YIELD_PER_CORPSE
		_body_source_item_ids[body_id] = []
		_body_legacy_claimed[body_id] = 0
	_clear_body_claim()
	_body_claim_serial = 0
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		var root: Dictionary = _roots[root_id]
		var initial_anchor := int(root.get("initial_anchor", 0))
		root["anchor"] = initial_anchor
		root["target_anchor"] = -1
		root["anim_start"] = 0.0
		root["anim_end"] = 0.0
		root["swarm_start"] = 0.0
		root["swarm_end"] = 0.0
		var root_pos := _root_world_center(root, initial_anchor)
		var swarm_pos := root_pos + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0)
		root["anim_from_pos"] = root_pos
		root["anim_to_pos"] = root_pos
		root["swarm_from_pos"] = swarm_pos
		root["swarm_to_pos"] = swarm_pos
		_apply_root_pose(root_id, root_pos, swarm_pos)
	_restoring_mother_authority = false

func _apply_mother_presenters() -> void:
	_reset_extension_interactables()
	_update_terminal_visuals()
	_update_portal_visuals()
	_update_body_visuals()
	_update_mother_visuals()
	_update_extension_visuals()
	_update_extension_interactable_states()
	_update_overlay_label_states()
	_update_gear_interactable_position()
	_update_timed_physical_presenters(_get_scheduler_tick())
	_apply_mother_topology()

func update_preview_overlay_states(overlay_states: Dictionary, current_tick: float, _delta: float) -> void:
	if _aster_overlay_root != null:
		_aster_overlay_root.visible = bool(overlay_states.get("aster", false))
	if _peris_overlay_root != null:
		_peris_overlay_root.visible = bool(overlay_states.get("peris", false))
	if _endo_overlay_root != null:
		_endo_overlay_root.visible = bool(overlay_states.get("endo", false))
	_update_overlay_label_states()
	_update_portal_overlay(current_tick)

func get_preview_overlay_status(overlay_id: String, current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return [
				"Portal bank: %s" % (_portal_label(_active_terminal_id) if _is_portal_open(current_tick) else "idle"),
				"Live service braid: %s  |  Ghost load: %s" % [_active_service_overlay_label(), _aster_load_read()],
				"Live load map follows the rail wear and converges at the center spindle.",
				"Shows terminal IDs, route ties, and the chamber's current freight load.",
			]
		"peris":
			return [
				"Mother stress: %s  |  Board pulse: %s" % [_mother_stress_label(), _peris_board_read()],
				"Care read: %s" % _peris_fault_read(),
				"Memory blur: %s  |  caretaker brace wear points inward" % _peris_memory_blur_read(),
				"The sustained pulse sits at the core; edge pain arrives as an echo.",
			]
		"endo":
			return [
				"Food sources: %d units left  |  Gear: %s" % [_body_units_remaining(), "mounted" if _gear_installed else "loose"],
				"Carry lane: %s  |  Repair target: %s" % [("open" if _is_socket_lane_open() else "closed"), _endo_repair_read()],
				"Tool fit: the center socket matches; both edge mounts retain their seals.",
				"Root pressure follows the live lane state; Endo has no separate immunity toggle.",
			]
		_:
			return []

func _root_control_key(root_id: String, direction: int) -> String:
	return "%s:%d" % [root_id, clampi(direction, -1, 1)]


func _mother_interaction_character_busy(actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null:
		return true
	return gs.is_moving(actor) \
		or gs.is_resting(actor) \
		or gs.is_dodging(actor) \
		or gs.is_endocytosing(actor) \
		or gs.is_external_traversal_active(actor) \
		or gs.is_dragging(actor) \
		or gs.is_field_restoring(actor)


func _mother_interaction_actor_ready_at(
	source: Node, actor: String, expected_actor := ""
) -> bool:
	var gs = _get_game_state()
	if gs == null or not is_instance_valid(source) or not (source is Node3D) \
			or actor == "" or not gs.characters.has(actor) \
			or (expected_actor != "" and actor != expected_actor) \
			or not gs.is_narratively_available(actor) \
			or gs.is_downed(actor) \
			or gs.is_knocked_down(actor) \
			or _mother_interaction_character_busy(actor):
		return false
	var required_actor := str(source.get("required_character"))
	if required_actor != "" and actor != required_actor:
		return false
	var source_position := (source as Node3D).global_position
	if gs.coord_map != null and gs.coord_map.has_method("to_data"):
		source_position = gs.coord_map.to_data(source_position)
	var actor_position: Vector3 = gs.get_position(actor)
	var planar_distance := Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)
	)
	return planar_distance <= float(source.get("interaction_radius")) \
		+ INTERACTION_POSITION_TOLERANCE


## A consequential callback accepts only the exact physical Interactable after that object has
## successfully crossed its own preflight and consumed its one-shot trigger. Repeatable mechanisms
## use one-shot controls too, then explicitly re-arm after this receipt has been consumed; that
## makes a direct callback distinguishable from a real world interaction.
func _mother_consumed_source_receipt(
	source: Node, expected_source: Node, actor: String
) -> bool:
	if not is_instance_valid(source) or source != expected_source \
			or str(source.get("active_character")) != actor \
			or not bool(source.get("one_shot")) \
			or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return false
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return false
	var spec: Dictionary = gs.get_interactable(data_id)
	return bool(spec.get("one_shot", false)) \
		and bool(spec.get("triggered", false)) \
		and not bool(spec.get("enabled", true))


func _rearm_repeatable_source(source: Node) -> void:
	if is_instance_valid(source) and source.has_method("reset"):
		source.reset()
	# Some repeatable controls move or become invalid as a direct consequence. Reapply all derived
	# presenter gates after reset so re-arming the receipt never leaves the wrong world control live.
	_update_portal_visuals()
	_update_extension_interactable_states()
	_update_gear_interactable_position()


func _validate_terminal_trigger(
	source: Node, actor: String, terminal_id: String, expected_source: Node
) -> bool:
	return source == expected_source \
		and _terminal_interactables.get(terminal_id) == source \
		and TERMINAL_SERVICES.has(terminal_id) \
		and _mother_interaction_actor_ready_at(source, actor, "aster") \
		and _portal_transit_phase == PORTAL_TRANSIT_IDLE \
		and (_peris_remote_terminal == "" or _peris_remote_terminal == terminal_id)


func _terminal_receipt_pending(source: Node, terminal_id: String) -> bool:
	return _validate_terminal_trigger(
		source, "aster", terminal_id, _terminal_interactables.get(terminal_id)
	) and _mother_consumed_source_receipt(
		source, _terminal_interactables.get(terminal_id), "aster"
	)


func _on_terminal_interacted(source: Node, terminal_id: String) -> void:
	if not _terminal_receipt_pending(source, terminal_id):
		return
	_activate_terminal_from_source_receipt(terminal_id)
	_rearm_repeatable_source(source)


## Automation cannot tune the bank; only the exact terminal's accepted source receipt can.
func activate_terminal(_terminal_id: String) -> bool:
	return false


func _activate_terminal_from_source_receipt(terminal_id: String) -> bool:
	_initialize_mother_authority()
	if not TERMINAL_SERVICES.has(terminal_id):
		return false
	if _portal_transit_phase != PORTAL_TRANSIT_IDLE:
		_show_message("The bank cannot retune while Peris is crossing.", 1.2)
		return false
	if _peris_remote_terminal != "" and _peris_remote_terminal != terminal_id:
		_show_message("Peris is still inside another service bay.", 1.2)
		return false
	_active_terminal_id = terminal_id
	_portal_open_until = _get_scheduler_tick() + PORTAL_DURATION
	_update_terminal_visuals()
	_update_portal_visuals()
	_surface_terminal_reading(terminal_id)
	_update_extension_interactable_states()
	_update_extension_visuals()
	_set_preview_step("mother_%s_online" % terminal_id)
	_show_note("%s opens. Peris can cross while the bank holds." % _portal_label(terminal_id), 3.2)
	_publish_mother_authority()
	return true


func _validate_portal_trigger(
	source: Node, actor: String, expected_source: Node
) -> bool:
	if source != expected_source or source not in [
		_portal_entry_interactable, _portal_return_interactable
	] or not _mother_interaction_actor_ready_at(source, actor, "peris") \
			or _portal_transit_phase != PORTAL_TRANSIT_IDLE:
		return false
	var gs = _get_game_state()
	if gs == null or not gs.has_method("command_external_traversal") \
			or not gs.has_method("is_external_traversal_active") \
			or bool(gs.call("is_external_traversal_active", "peris")):
		return false
	if source == _portal_entry_interactable:
		return _peris_remote_terminal == "" and _is_portal_open(_get_scheduler_tick())
	return _peris_remote_terminal != "" \
		and _is_portal_open(_get_scheduler_tick()) \
		and _active_terminal_id == _peris_remote_terminal


func _portal_receipt_pending(source: Node) -> bool:
	return _validate_portal_trigger(source, "peris", source) \
		and _mother_consumed_source_receipt(source, source, "peris")


func _on_portal_interacted(source: Node) -> void:
	if not _portal_receipt_pending(source):
		return
	_use_portal_from_source_receipt()
	_rearm_repeatable_source(source)


## Automation cannot start a crossing; a portal crossing begins only from its exact calibrated pad receipt.
func use_portal() -> bool:
	return false


func _use_portal_from_source_receipt() -> bool:
	_initialize_mother_authority()
	if _portal_transit_phase != PORTAL_TRANSIT_IDLE:
		_show_message("Peris is already inside the crossing.", 1.1)
		return false
	var gs = _get_game_state()
	if gs == null or not gs.has_method("command_external_traversal") \
			or not gs.has_method("is_external_traversal_active"):
		_show_message("The portal has no traversal authority.", 1.2)
		return false
	if bool(gs.call("is_external_traversal_active", "peris")):
		_show_message("Peris is already committed to another crossing.", 1.2)
		return false
	if _peris_remote_terminal == "":
		if not _is_portal_open(_get_scheduler_tick()):
			_show_message("No portal bank is stable right now.", 1.2)
			return false
		var outbound_terminal := _active_terminal_id
		var outbound_destination := _terminal_service_spawn(outbound_terminal)
		_portal_transit_phase = PORTAL_TRANSIT_OUTBOUND
		_portal_transit_terminal = outbound_terminal
		# Publish the reserved crossing before GameState begins moving the body. A save from this
		# notification either also contains the traversal or safely rolls the reservation back.
		_publish_mother_authority()
		if not bool(gs.call(
			"command_external_traversal",
			"peris",
			_portal_traversal_id(PORTAL_TRANSIT_OUTBOUND, outbound_terminal),
			outbound_destination,
			_get_character_position("peris"),
			outbound_destination,
			PORTAL_TRANSIT_SECONDS,
			&"locked"
		)):
			_clear_portal_transit_reservation()
			_publish_mother_authority()
			_show_message("The service braid refuses the crossing.", 1.2)
			return false
		_show_message("Peris enters the route to %s." % _terminal_service_label(outbound_terminal), 1.3)
		_update_portal_visuals()
		return true
	if not _is_portal_open(_get_scheduler_tick()) or _active_terminal_id != _peris_remote_terminal:
		_show_message("Aster needs the matching bank live to bring Peris back.", 1.3)
		return false
	var return_terminal := _peris_remote_terminal
	var return_destination := BASE_PORTAL_POS + Vector3(2.6, 0.0, 0.0)
	_portal_transit_phase = PORTAL_TRANSIT_RETURNING
	_portal_transit_terminal = return_terminal
	_publish_mother_authority()
	if not bool(gs.call(
		"command_external_traversal",
		"peris",
		_portal_traversal_id(PORTAL_TRANSIT_RETURNING, return_terminal),
		return_destination,
		_get_character_position("peris"),
		return_destination,
		PORTAL_TRANSIT_SECONDS,
		&"locked"
	)):
		_clear_portal_transit_reservation()
		_publish_mother_authority()
		_show_message("The return braid refuses the crossing.", 1.2)
		return false
	_show_message("Peris enters the return route through %s." % _portal_label(return_terminal), 1.2)
	_update_portal_visuals()
	return true

func _portal_traversal_id(phase: String, terminal_id: String) -> StringName:
	return StringName("%s:portal:%s:%s" % [mother_authority_key(), phase, terminal_id])

func _portal_transit_state() -> Dictionary:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_external_traversal_state"):
		return {}
	var state: Variant = gs.call("get_external_traversal_state", "peris")
	return (state as Dictionary).duplicate(true) if state is Dictionary else {}

func _is_our_portal_traversal(state: Dictionary, phase := "", terminal_id := "") -> bool:
	if state.is_empty():
		return false
	var expected_phase := phase if phase != "" else _portal_transit_phase
	var expected_terminal := terminal_id if terminal_id != "" else _portal_transit_terminal
	if expected_phase not in [PORTAL_TRANSIT_OUTBOUND, PORTAL_TRANSIT_RETURNING] \
			or expected_terminal not in TERMINAL_ORDER:
		return false
	return StringName(str(state.get("traversal_id", ""))) \
		== _portal_traversal_id(expected_phase, expected_terminal)

func _clear_portal_transit_reservation() -> void:
	_portal_transit_phase = PORTAL_TRANSIT_IDLE
	_portal_transit_terminal = ""
	_update_portal_visuals()
	_update_extension_interactable_states()

func _on_mother_external_traversal_finished(char_id: String, traversal_id: StringName) -> void:
	if char_id != "peris" or _portal_transit_phase == PORTAL_TRANSIT_IDLE \
			or traversal_id != _portal_traversal_id(_portal_transit_phase, _portal_transit_terminal):
		return
	var terminal_id := _portal_transit_terminal
	var finished_phase := _portal_transit_phase
	if finished_phase == PORTAL_TRANSIT_OUTBOUND:
		_peris_remote_terminal = terminal_id
		_set_preview_step("mother_%s_remote" % terminal_id)
		_show_message("Peris reaches %s." % _terminal_service_label(terminal_id), 1.3)
	else:
		_peris_remote_terminal = ""
		_show_message("Peris returns through %s." % _portal_label(terminal_id), 1.2)
	_clear_portal_transit_reservation()
	_publish_mother_authority()

func _on_mother_external_traversal_cancelled(
	char_id: String, traversal_id: StringName, _reason: StringName
) -> void:
	if char_id != "peris" or _portal_transit_phase == PORTAL_TRANSIT_IDLE \
			or traversal_id != _portal_traversal_id(_portal_transit_phase, _portal_transit_terminal):
		return
	# A cancellation never grants the reserved endpoint. Outbound leaves Peris local; return keeps
	# the remote ownership until a complete matching traversal reaches the base bank.
	_clear_portal_transit_reservation()
	_show_note("The crossing broke before its endpoint. Recalibrate the same bank.", 2.2)
	_publish_mother_authority()

func _validate_root_control_trigger(
	source: Node,
	actor: String,
	root_id: String,
	direction: int,
	expected_source: Node
) -> bool:
	if source != expected_source \
			or _root_control_interactables.get(_root_control_key(root_id, direction)) != source \
			or not _mother_interaction_actor_ready_at(source, actor, "peris") \
			or direction not in [-1, 1] \
			or not _roots.has(root_id) \
			or _get_scheduler() == null:
		return false
	var root: Dictionary = _roots[root_id]
	if _peris_remote_terminal != str(root.get("terminal", "")) \
			or _root_move_in_flight(root):
		return false
	var target_anchor := int(root.get("anchor", 0)) + direction
	return target_anchor >= int(root.get("min_anchor", 0)) \
		and target_anchor <= int(root.get("max_anchor", 0)) \
		and _blocking_root_for(root_id, target_anchor) == ""


func _root_control_receipt_pending(
	source: Node, root_id: String, direction: int
) -> bool:
	var expected_source: Node = _root_control_interactables.get(
		_root_control_key(root_id, direction)
	)
	return _validate_root_control_trigger(
		source, "peris", root_id, direction, expected_source
	) and _mother_consumed_source_receipt(source, expected_source, "peris")


func _on_root_control_interacted(
	source: Node, root_id: String, direction: int
) -> void:
	if not _root_control_receipt_pending(source, root_id, direction):
		return
	_move_root_from_source_receipt(root_id, direction)
	_rearm_repeatable_source(source)


## Automation cannot shift roots; root movement belongs to the exact remote service bud.
func activate_fragment(_root_id: String) -> bool:
	return false


func activate_fragment_move(_root_id: String, _direction: int) -> bool:
	return false


func _move_root_from_source_receipt(root_id: String, direction: int) -> bool:
	_initialize_mother_authority()
	if not _roots.has(root_id):
		return false
	var root: Dictionary = _roots[root_id]
	var terminal_id := str(root.get("terminal", ""))
	if _peris_remote_terminal != terminal_id:
		_show_message("Peris needs the matching service bay first.", 1.2)
		return false
	if _get_scheduler() == null:
		_show_message("The root transit has no gameplay clock.", 1.2)
		return false
	var current_tick := _get_scheduler_tick()
	if _root_move_in_flight(root):
		_show_message("%s is still settling." % _fragment_label(root_id), 1.2)
		return false
	var target_anchor := int(root.get("anchor", 0)) + clampi(direction, -1, 1)
	if target_anchor < int(root.get("min_anchor", 0)) or target_anchor > int(root.get("max_anchor", 0)):
		_show_message("That bud on %s doesn't answer anymore." % _fragment_label(root_id), 1.3)
		return false
	var blocker := _blocking_root_for(root_id, target_anchor)
	if blocker != "":
		_show_message("%s is still braced somewhere deeper in the board." % _fragment_label(root_id), 1.4)
		return false
	var from_anchor := int(root.get("anchor", 0))
	root["target_anchor"] = target_anchor
	root["anim_start"] = current_tick
	root["anim_end"] = current_tick + ROOT_SLIDE_DURATION
	root["swarm_start"] = float(root.get("anim_end", current_tick)) + ROOT_SWARM_LAG
	root["swarm_end"] = float(root.get("swarm_start", current_tick)) + ROOT_SWARM_DURATION
	root["anim_from_pos"] = _root_node(root).position
	root["anim_to_pos"] = _root_world_center(root, target_anchor)
	root["swarm_from_pos"] = _root_swarm_node(root).position
	root["swarm_to_pos"] = Vector3(root.get("anim_to_pos", Vector3.ZERO)) + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0)
	_rearm_root_move_commit(root_id)
	_set_preview_step("mother_%s_%s_%d" % [root_id, "forward" if target_anchor > from_anchor else "back", target_anchor])
	_show_note("Peris wakes one of %s's dormant buds. The root drifts and the Sapscrap mat follows." % _fragment_label(root_id), 3.6)
	_update_extension_interactable_states()
	_update_extension_visuals()
	_update_overlay_label_states()
	_publish_mother_authority()
	return true

func _validate_collapse_trigger(
	source: Node, actor: String, expected_source: Node
) -> bool:
	return source == expected_source \
		and expected_source == _collapse_interactable \
		and _mother_interaction_actor_ready_at(source, actor, "endo") \
		and _collapse_phase == COLLAPSE_PHASE_BLOCKED \
		and _get_scheduler() != null


func _collapse_receipt_pending(source: Node) -> bool:
	return _validate_collapse_trigger(source, "endo", _collapse_interactable) \
		and _mother_consumed_source_receipt(
			source, _collapse_interactable, "endo"
		)


func _on_collapse_interacted(source: Node) -> void:
	if not _collapse_receipt_pending(source):
		return
	_shift_collapse_from_source_receipt()


## Automation cannot clear the collapse; it moves only after Endo consumes its physical source.
func clear_collapse() -> bool:
	return false


func _shift_collapse_from_source_receipt() -> bool:
	_initialize_mother_authority()
	if _collapse_phase != COLLAPSE_PHASE_BLOCKED:
		_show_message(
			"The debris is still shifting." if _collapse_phase == COLLAPSE_PHASE_SHIFTING \
			else "The offshoot is already open.",
			1.0
		)
		return false
	var scheduler = _get_scheduler()
	if scheduler == null:
		_show_message("The debris shift has no gameplay clock.", 1.2)
		return false
	_collapse_phase = COLLAPSE_PHASE_SHIFTING
	_collapse_cleared = false
	_collapse_shift_started_at = float(scheduler.get_current_tick())
	_collapse_shift_deadline = _collapse_shift_started_at + COLLAPSE_SHIFT_SECONDS
	_set_preview_step("mother_collapse_shifting")
	_show_note("Endo leans into the collapse. The route stays blocked until the last slab clears.", 3.4)
	_update_body_visuals()
	_update_timed_physical_presenters(_collapse_shift_started_at)
	_update_extension_interactable_states()
	_publish_mother_authority()
	_rearm_collapse_commit()
	return true

func _validate_body_harvest_trigger(
	source: Node,
	actor: String,
	body_id: String,
	expected_source: Node
) -> bool:
	if source != expected_source \
			or _body_interactables.get(body_id) != source \
			or not BODY_POSITIONS.has(body_id) \
			or not _mother_interaction_actor_ready_at(source, actor, "endo") \
			or _collapse_phase != COLLAPSE_PHASE_CLEARED \
			or _body_claim_phase != BODY_CLAIM_IDLE \
			or int(_body_remaining.get(body_id, 0)) <= 0 \
			or not _has_free_hand_slots(actor, 1):
		return false
	var item_id := _next_body_source_item_id(body_id)
	return item_id != "" and _body_item_at_source(item_id)


func _body_harvest_receipt_pending(source: Node, body_id: String) -> bool:
	var expected_source: Node = _body_interactables.get(body_id)
	return _validate_body_harvest_trigger(
		source, "endo", body_id, expected_source
	) and _mother_consumed_source_receipt(source, expected_source, "endo")


func _on_body_harvest_interacted(source: Node, body_id: String) -> void:
	if not _body_harvest_receipt_pending(source, body_id):
		return
	_harvest_body_from_source_receipt(body_id, "endo")
	_rearm_repeatable_source(source)


## Automation cannot harvest; a corpse reward must be claimed through its exact visible source.
func harvest_body(_body_id: String, _actor_id := "") -> bool:
	return false


func _harvest_body_from_source_receipt(body_id: String, actor: String) -> bool:
	_initialize_mother_authority()
	if not _collapse_cleared:
		_show_message("The debris still blocks the bodies.", 1.2)
		return false
	if not BODY_POSITIONS.has(body_id):
		return false
	if actor != "endo":
		_say("Only Endo can actually draw anything usable out of them.", "PERIS")
		return false
	if _body_claim_phase != BODY_CLAIM_IDLE:
		_show_message("A starch unit is still between source and carrier.", 1.2)
		return false
	if int(_body_remaining.get(body_id, 0)) <= 0:
		_show_message("%s is spent." % BODY_NAMES.get(body_id, body_id), 1.1)
		return false
	if not _has_free_hand_slots(actor, 1):
		_show_message("Endo needs a free hand before he can absorb more starch.", 1.3)
		return false
	var item_id := _next_body_source_item_id(body_id)
	if item_id == "" or not _body_item_at_source(item_id):
		_show_message("No physical starch unit remains at that body.", 1.2)
		return false
	# Reserve the exact finite identity before GameState crosses the pickup signal seam. A save on
	# either side can therefore roll the reservation back or finish it without minting another unit.
	_body_claim_phase = BODY_CLAIMING
	_body_claim_item_id = item_id
	_body_claim_body_id = body_id
	_body_claimed_by = actor
	_body_claim_serial += 1
	_body_claimed_item_ids.append(item_id)
	_sync_body_remaining_from_sources()
	_update_body_visuals()
	_update_extension_interactable_states()
	_publish_mother_authority()
	if not _pick_up_item(actor, item_id):
		_body_claimed_item_ids.erase(item_id)
		_clear_body_claim()
		_sync_body_remaining_from_sources()
		_update_body_visuals()
		_update_extension_interactable_states()
		_publish_mother_authority()
		return false
	_clear_body_claim()
	_sync_body_remaining_from_sources()
	_update_body_visuals()
	_update_extension_interactable_states()
	_set_preview_step("mother_%s_harvested" % body_id)
	_show_note("Endo lifts one of %s's visible starch nodules." % BODY_NAMES.get(body_id, body_id), 2.8)
	_publish_mother_authority()
	return true

func _validate_gear_pickup_trigger(
	source: Node, actor: String, expected_source: Node
) -> bool:
	if source != expected_source or expected_source != _gear_interactable \
			or not _mother_interaction_actor_ready_at(source, actor, "endo") \
			or _gear_installed or _gear_item_id == "" \
			or not _is_gear_pocket_open() \
			or not _has_free_hand_slots(actor, 2):
		return false
	var item := _get_item_state(_gear_item_id)
	return not item.is_empty() and str(item.get("location", "")) == "ground"


func _gear_pickup_receipt_pending(source: Node) -> bool:
	return _validate_gear_pickup_trigger(source, "endo", _gear_interactable) \
		and _mother_consumed_source_receipt(
			source, _gear_interactable, "endo"
		)


func _on_gear_pickup_interacted(source: Node) -> void:
	if not _gear_pickup_receipt_pending(source):
		return
	_pick_up_gear_from_source_receipt()
	_rearm_repeatable_source(source)


## Automation cannot lift the gear; the exact Mother Gear pedestal receipt owns the two-hand pickup.
func pick_up_gear() -> bool:
	return false


func _pick_up_gear_from_source_receipt() -> bool:
	_initialize_mother_authority()
	if _gear_installed:
		_show_message("The gear is already mounted.", 1.0)
		return false
	if _gear_item_id == "":
		return false
	if not _is_gear_pocket_open():
		_show_message("The west side still feels pinned shut.", 1.3)
		return false
	if not _pick_up_item("endo", _gear_item_id):
		_show_message("Endo needs both hands clear to carry the gear.", 1.3)
		return false
	_set_preview_step("mother_gear_carried")
	_show_note("Endo lifts the mother gear with both hands.", 2.8)
	_update_extension_interactable_states()
	_update_extension_visuals()
	_update_overlay_label_states()
	_update_gear_interactable_position()
	_publish_mother_authority()
	return true

func _validate_gear_install_trigger(
	source: Node,
	actor: String,
	repair_id: String,
	expected_source: Node
) -> bool:
	return source == expected_source \
		and _repair_interactables.get(repair_id) == source \
		and REPAIR_POINT_DEFS.has(repair_id) \
		and _mother_interaction_actor_ready_at(source, actor, "endo") \
		and not _gear_installed \
		and _is_socket_lane_open() \
		and _endo_holds_gear()


func _gear_install_receipt_pending(source: Node, repair_id: String) -> bool:
	var expected_source: Node = _repair_interactables.get(repair_id)
	return _validate_gear_install_trigger(
		source, "endo", repair_id, expected_source
	) and _mother_consumed_source_receipt(source, expected_source, "endo")


func _on_gear_install_interacted(source: Node, repair_id: String) -> void:
	if not _gear_install_receipt_pending(source, repair_id):
		return
	_install_gear_from_source_receipt(repair_id)
	_rearm_repeatable_source(source)


## Automation cannot mount the gear; a mount commits only from the exact repair fixture receipt.
func install_gear() -> bool:
	return false


func install_gear_from_interaction(_repair_id: String) -> bool:
	return false


func install_gear_at(_repair_id: String) -> bool:
	return false


func _install_gear_from_source_receipt(repair_id: String) -> bool:
	_initialize_mother_authority()
	if not REPAIR_POINT_DEFS.has(repair_id):
		return false
	if _gear_installed:
		return false
	if not _is_socket_lane_open():
		_show_message("The carry route still reads too tight.", 1.2)
		return false
	if not _endo_holds_gear():
		_show_message("Endo needs to be carrying the gear first.", 1.2)
		return false
	if not _repair_attempts.has(repair_id):
		_repair_attempts.append(repair_id)
	if repair_id != CORRECT_REPAIR_ID:
		_reject_wrong_repair(repair_id)
		return true
	_remove_item(_gear_item_id)
	_gear_item_id = ""
	_gear_installed = true
	_installed_repair_id = repair_id
	_set_preview_step("mother_gear_installed")
	_show_note("The load regulator takes the gear cleanly. The mother's stress profile loosens instead of flaring and the east side begins to unravel.", 3.8)
	_update_mother_visuals()
	_update_extension_interactable_states()
	_update_extension_visuals()
	_update_overlay_label_states()
	_update_gear_interactable_position()
	_publish_mother_authority()
	return true

func _validate_mother_tend_trigger(
	source: Node, actor: String, expected_source: Node
) -> bool:
	return source == expected_source \
		and expected_source == _mother_interactable \
		and _mother_interaction_actor_ready_at(source, actor, "peris") \
		and _gear_installed \
		and _installed_repair_id == CORRECT_REPAIR_ID \
		and _is_mother_lane_clear() \
		and not _mother_tended \
		and _get_scheduler() != null


func _mother_tend_receipt_pending(source: Node) -> bool:
	return _validate_mother_tend_trigger(
		source, "peris", _mother_interactable
	) and _mother_consumed_source_receipt(
		source, _mother_interactable, "peris"
	)


func _on_mother_tend_interacted(source: Node) -> void:
	if not _mother_tend_receipt_pending(source):
		return
	_tend_mother_from_source_receipt()


## Automation cannot tend the mother; tending commits only through Mother Flure's exact physical fixture.
func tend_mother() -> bool:
	return false


func tend_mother_from_interaction() -> bool:
	return false


func _tend_mother_from_source_receipt() -> bool:
	_initialize_mother_authority()
	if not _gear_installed:
		_show_message("The mechanism still needs the gear.", 1.2)
		return false
	if _installed_repair_id != CORRECT_REPAIR_ID:
		_show_message("Peris can feel the load still being routed wrong.", 1.2)
		return false
	if not _is_mother_lane_clear():
		_show_message("The mother still reads walled in.", 1.2)
		return false
	if _mother_tended:
		_show_message(
			"The Rings membrane is still opening." if _rings_gate_phase == RINGS_GATE_PHASE_OPENING \
			else "The mother is already awake.",
			1.0
		)
		return false
	var scheduler = _get_scheduler()
	if scheduler == null:
		_show_message("The Rings handoff has no gameplay clock.", 1.2)
		return false
	_mother_tended = true
	scheduler.cancel_tag(_root_hazard_tag())
	_hazard_next_tick = -1.0
	_route_phase = "opening"
	_rings_gate_phase = RINGS_GATE_PHASE_OPENING
	_rings_gate_started_at = float(scheduler.get_current_tick())
	_rings_gate_deadline = _rings_gate_started_at + RINGS_GATE_OPEN_SECONDS
	_set_preview_step("mother_bloomed")
	_clear_dialogue()
	_say("You're all right. You just needed the load to move.", "PERIS")
	_say("The chamber's opening toward the Rings. Give the membrane a second to lift.", "ASTER")
	_show_note("Mother Flure stabilizes the handoff. The route remains sealed while its membrane rises.", 4.0)
	_update_mother_visuals()
	_update_extension_interactable_states()
	_update_extension_visuals()
	_update_overlay_label_states()
	_update_timed_physical_presenters(_rings_gate_started_at)
	_publish_mother_authority()
	_rearm_rings_gate_commit()
	return true


func _validate_exit_handoff_trigger(
	source: Node, actor: String, expected_source: Node
) -> bool:
	return source == expected_source \
		and expected_source == _exit_interactable \
		and actor in CANONICAL_PARTY \
		and _mother_interaction_actor_ready_at(source, actor) \
		and _mother_tended \
		and _route_phase == "handoff" \
		and _rings_gate_phase == RINGS_GATE_PHASE_OPEN \
		and bool(_canonical_party_exit_arrival().get("ready", false))


func _exit_handoff_receipt_pending(source: Node) -> bool:
	var actor := str(source.get("active_character")) if is_instance_valid(source) else ""
	return _validate_exit_handoff_trigger(source, actor, _exit_interactable) \
		and _mother_consumed_source_receipt(source, _exit_interactable, actor)


func _on_exit_handoff_interacted(source: Node) -> void:
	if not _exit_handoff_receipt_pending(source):
		return
	_complete_exit_handoff_from_source_receipt()


## Automation cannot finish the handoff; the Rings boundary accepts only its gathered-party source receipt.
func complete_exit_handoff() -> bool:
	return false


func _complete_exit_handoff_from_source_receipt() -> bool:
	_initialize_mother_authority()
	if _route_phase == "complete":
		return true
	if not _mother_tended or _route_phase != "handoff" \
			or _rings_gate_phase != RINGS_GATE_PHASE_OPEN:
		_show_message(
			"The Rings membrane is still opening." if _rings_gate_phase == RINGS_GATE_PHASE_OPENING \
			else "Stabilize Mother Flure before taking the Rings handoff.",
			1.4
		)
		return false
	var arrival := _canonical_party_exit_arrival()
	if not bool(arrival.get("ready", false)):
		_surface_exit_gather_feedback(arrival)
		return false
	_exit_reached = true
	_route_phase = "complete"
	_set_preview_step("mother_complete")
	_clear_dialogue()
	_say("Mother's stable. The Rings route is ours.", "ASTER")
	_show_note("Mother Flure complete — the party can continue toward the Greenfields Collective.", 3.4)
	_update_extension_interactable_states()
	_update_extension_visuals()
	_update_overlay_label_states()
	_publish_mother_authority()
	return true


## The handoff is a party-scale boundary, so completion is derived from the same canonical
## GameState bodies that hazards, saves, and replay see. The active portrait is deliberately
## irrelevant: one runner cannot cash out a route while a friend is absent, downed, or still in
## the chamber. This is sampled only when the player commits the exit interaction; it adds no
## per-frame polling or repeated execution after the party has already gathered.
func _canonical_party_exit_arrival() -> Dictionary:
	var missing: Array[String] = []
	var downed: Array[String] = []
	var distant: Array[String] = []
	var gs = _get_game_state()
	if gs == null:
		missing.assign(CANONICAL_PARTY)
	else:
		for char_id in CANONICAL_PARTY:
			if not gs.characters.has(char_id):
				missing.append(char_id)
			elif gs.is_downed(char_id) or float(gs.get_stat(char_id, "hp")) <= 0.0:
				downed.append(char_id)
			elif _get_character_position(char_id).distance_to(EXIT_POS) > EXIT_INTERACTION_RADIUS:
				distant.append(char_id)
	return {
		"ready": missing.is_empty() and downed.is_empty() and distant.is_empty(),
		"missing": missing,
		"downed": downed,
		"distant": distant,
	}


func _surface_exit_gather_feedback(arrival: Dictionary) -> void:
	var missing: Array = arrival.get("missing", [])
	var downed: Array = arrival.get("downed", [])
	var distant: Array = arrival.get("distant", [])
	if not missing.is_empty():
		_show_message(
			"The Rings handoff needs the whole party. Missing: %s." % _party_name_list(missing),
			2.1
		)
		return
	if not downed.is_empty():
		_show_message(
			"Retrieve and revive %s before leaving; the whole party must be conscious." \
				% _party_name_list(downed),
			2.3
		)
		return
	_show_message(
		"Gather the whole party on the Rings handoff. Waiting for: %s." \
			% _party_name_list(distant),
		2.1
	)


func _party_name_list(character_ids: Array) -> String:
	var names: Array[String] = []
	for char_id_v in character_ids:
		names.append(_display_name(str(char_id_v)))
	return ", ".join(names)

func _update_runtime(_delta: float) -> void:
	_initialize_mother_authority()
	var current_tick := _get_scheduler_tick()
	_update_portal_timeout(current_tick)
	_update_root_animation(current_tick)
	# Root-dependent permissions are derived from the saved transit deadlines, not
	# from the render pose. Re-evaluate them as simulation time crosses a settling
	# deadline so a completed physical move enables its real interaction in the same
	# headless/runtime update.
	_update_extension_interactable_states()
	_update_timed_physical_presenters(current_tick)
	_update_terminal_pulse(current_tick)
	_update_overlay_label_states()
	_update_gear_interactable_position()

func _update_portal_timeout(current_tick: float) -> void:
	if _active_terminal_id == "" or _portal_open_until > current_tick:
		return
	_active_terminal_id = ""
	_portal_open_until = 0.0
	if _peris_remote_terminal != "":
		_show_note("The remote bank closes. Aster can reopen the same terminal to bring Peris back.", 3.1)
	else:
		_show_message("The portal bank winds down.", 1.1)
	_update_terminal_visuals()
	_update_portal_visuals()
	_publish_mother_authority()

func _update_root_animation(current_tick: float) -> void:
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		var root: Dictionary = _roots[root_id]
		var root_node := _root_node(root)
		var swarm_node := _root_swarm_node(root)
		var anim_start := float(root.get("anim_start", 0.0))
		var anim_end := float(root.get("anim_end", 0.0))
		if anim_end > anim_start and current_tick < anim_end:
			var t := clampf((current_tick - anim_start) / maxf(anim_end - anim_start, 0.001), 0.0, 1.0)
			root_node.position = Vector3(root.get("anim_from_pos", root_node.position)).lerp(Vector3(root.get("anim_to_pos", root_node.position)), t)
		elif anim_end > 0.0:
			root_node.position = Vector3(root.get("anim_to_pos", root_node.position))
		var swarm_start := float(root.get("swarm_start", 0.0))
		var swarm_end := float(root.get("swarm_end", 0.0))
		if swarm_end > swarm_start and current_tick < swarm_start:
			swarm_node.position = Vector3(root.get("swarm_from_pos", swarm_node.position))
		elif swarm_end > swarm_start and current_tick < swarm_end:
			var swarm_t := clampf((current_tick - swarm_start) / maxf(swarm_end - swarm_start, 0.001), 0.0, 1.0)
			swarm_node.position = Vector3(root.get("swarm_from_pos", swarm_node.position)).lerp(Vector3(root.get("swarm_to_pos", swarm_node.position)), swarm_t)
		elif swarm_end > 0.0:
			swarm_node.position = Vector3(root.get("swarm_to_pos", swarm_node.position))
		_update_root_world_label(root)

## Root contact is sampled only at fixed simulation deadlines. Render frames project the board and
## may be called zero, one, or thousands of times between these callbacks without changing HP.
func _start_root_hazard_cadence() -> void:
	if _mother_tended or _get_scheduler() == null:
		_hazard_next_tick = -1.0
		return
	_hazard_next_tick = _get_scheduler_tick() + ROOT_HAZARD_INTERVAL
	_rearm_root_hazard_tick()


func _root_hazard_tag() -> String:
	return _mother_callback_tag("root_hazard")


func _rearm_root_hazard_tick() -> void:
	var scheduler = _get_scheduler()
	if scheduler == null:
		return
	var tag := _root_hazard_tag()
	scheduler.cancel_tag(tag)
	if _mother_tended or _hazard_next_tick < 0.0:
		return
	scheduler.schedule_at(
		_hazard_next_tick,
		_on_root_hazard_tick.bind(_hazard_next_tick),
		tag
	)


func _on_root_hazard_tick(expected_tick: float) -> void:
	if _mother_tended or not is_equal_approx(_hazard_next_tick, expected_tick):
		return
	var scheduler = _get_scheduler()
	if scheduler == null or float(scheduler.get_current_tick()) + 0.000001 < expected_tick:
		return
	# Advance from the saved anchor rather than from a render timestamp. EventScheduler dispatches
	# reactive chains at their exact event ticks, so coarse and fine advances visit the same contacts.
	_hazard_next_tick = expected_tick + ROOT_HAZARD_INTERVAL
	var gs = _get_game_state()
	for char_id in ["aster", "peris", "endo"]:
		if gs == null or not "characters" in gs or not gs.characters.has(char_id) \
				or _get_character_stat(char_id, "hp") <= 0.0:
			continue
		# Portal transit is a non-local service-braid edge, not a walk through every root cell
		# between its mouths. Its locked interpolation must not manufacture lane contacts.
		if char_id == "peris" and _portal_transit_phase != PORTAL_TRANSIT_IDLE:
			continue
		if not _character_in_any_hazard(_get_character_position(char_id)):
			continue
		_adjust_character_stat(char_id, "hp", -ROOT_HAZARD_DAMAGE)
		_show_message("%s gets clipped by the Sapscrap mat." % _display_name(char_id), 1.1)
	_publish_mother_authority()
	_rearm_root_hazard_tick()

func _update_terminal_pulse(current_tick: float) -> void:
	for terminal_id in _terminal_materials.keys():
		var material: StandardMaterial3D = _terminal_materials[terminal_id]
		if material == null:
			continue
		var active: bool = terminal_id == _active_terminal_id and _is_portal_open(current_tick)
		material.emission_energy_multiplier = 0.65 + 0.2 * (0.5 + 0.5 * sin(current_tick * 6.0)) if active else 0.26

func _surface_terminal_reading(terminal_id: String) -> void:
	if terminal_id in _terminal_readings_seen:
		return
	_terminal_readings_seen.append(terminal_id)
	match terminal_id:
		"term_alpha":
			_clear_dialogue()
			_say("LIVE LOAD MAP: every carrying rail still converges on the center spindle. Both edge feeds are unloaded.", "ENGRAM", "data")
			_say("That matches the polished freight wear on the floor. The load kept going through the middle.", "ASTER")
		"term_beta":
			_clear_dialogue()
			_say("LIVE ROOT STRESS: sustained pressure at the core. Edge pulses lag behind the central contraction.", "ENGRAM", "data")
			_say("She's hurting at the core. The edge lanes are echoes, like the old brace marks show.", "PERIS")
		"term_gamma":
			_clear_dialogue()
			_say("LIVE TORQUE FEEDBACK: center socket matches the Mother Gear. Edge mounts remain sealed and show no load wear.", "ENGRAM", "data")
			_say("The caretaker gauge and socket scars say the same thing. Center mount fits; the others kick back.", "ENDO")

func _build_chamber_shell() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.07, 0.065, 0.06))
	_add_box(self, Vector3(58.0, 2.1, -27.1), Vector3(120.0, 4.2, 0.3), Color(0.12, 0.11, 0.1))
	_add_box(self, Vector3(58.0, 2.1, 27.1), Vector3(120.0, 4.2, 0.3), Color(0.12, 0.11, 0.1))
	_add_box(self, Vector3(-0.1, 2.1, 0.0), Vector3(0.3, 4.2, 54.0), Color(0.12, 0.11, 0.1))
	_add_box(self, Vector3(116.1, 2.1, 0.0), Vector3(0.3, 4.2, 54.0), Color(0.12, 0.11, 0.1))
	for x_pos in [10.0, 26.0, 42.0, 58.0, 74.0, 90.0, 106.0]:
		_add_light(self, Vector3(x_pos, 4.1, 0.0), Color(0.58, 0.54, 0.48), 1.45, 14.0)
	var board_center := Vector3(60.0, 0.01, 0.0)
	_add_box(self, board_center, Vector3(36.0, 0.05, 36.0), Color(0.14, 0.1, 0.08), Color(0.28, 0.2, 0.12), 0.14)
	_add_box(self, board_center, Vector3(36.6, 0.18, 0.28), Color(0.3, 0.22, 0.14))
	_add_box(self, board_center, Vector3(0.28, 0.18, 36.6), Color(0.3, 0.22, 0.14))
	for col in range(7):
		var x_pos := BOARD_ORIGIN.x + float(col) * BOARD_CELL_SIZE
		_add_box(self, Vector3(x_pos, 0.12, 0.0), Vector3(0.14, 0.18, 36.0), Color(0.22, 0.18, 0.12))
	for row in range(7):
		var z_pos := BOARD_ORIGIN.z + float(row) * BOARD_CELL_SIZE
		_add_box(self, Vector3(60.0, 0.12, z_pos), Vector3(36.0, 0.18, 0.14), Color(0.22, 0.18, 0.12))
	_add_label(self, "PORTAL BANK 12", TERM_BETA_POS + Vector3(2.2, 2.65, 0.0), Color(0.8, 0.88, 0.96))
	_add_label(self, "COLLAPSED 12-F", COLLAPSE_POS + Vector3(8.0, 2.5, 0.0), Color(0.82, 0.72, 0.6))
	_add_label(self, "MOTHER FLURE", MOTHER_POS + Vector3(-1.0, 3.2, 0.0), Color(0.94, 0.82, 0.58))
	_add_label(self, "LOT CLOT CHAMBER", Vector3(60.0, 2.8, -22.8), Color(0.72, 0.62, 0.46))

func _build_environment_decoration() -> void:
	var decoration := Node3D.new()
	decoration.name = "MotherFlureDecoration"
	add_child(decoration)

	# Repeated wall bays give the 120 m chamber the same measured facade rhythm
	# as the authored district buildings: pier, inset panel, illuminated datum.
	var wall_bays := Node3D.new()
	wall_bays.name = "WallBays"
	decoration.add_child(wall_bays)
	for side in [-1.0, 1.0]:
		for bay_index in range(14):
			var bay_x := 4.0 + float(bay_index) * 8.3
			var wall_z: float = side * 26.78
			_add_box(wall_bays, Vector3(bay_x, 1.55, wall_z), Vector3(6.9, 2.6, 0.12),
				Color(0.105, 0.1, 0.09), Color.BLACK, 0.0,
				"WallInset_%d_%d" % [int(side), bay_index])
			_add_box(wall_bays, Vector3(bay_x - 3.55, 1.65, wall_z - side * 0.06), Vector3(0.22, 3.3, 0.3),
				Color(0.25, 0.21, 0.16), Color.BLACK, 0.0,
				"WallPier_%d_%d" % [int(side), bay_index])
			_add_box(wall_bays, Vector3(bay_x, 2.78, wall_z - side * 0.12), Vector3(4.6, 0.11, 0.16),
				Color(0.32, 0.23, 0.13), Color(0.8, 0.48, 0.18), 0.34,
				"WallDatum_%d_%d" % [int(side), bay_index])

	var trusses := Node3D.new()
	trusses.name = "CeilingTrusses"
	decoration.add_child(trusses)
	for truss_index in range(12):
		var truss_x := 5.0 + float(truss_index) * 9.7
		_add_box(trusses, Vector3(truss_x, 4.02, 0.0), Vector3(0.28, 0.28, 52.4),
			Color(0.19, 0.17, 0.14), Color.BLACK, 0.0, "TrussSpine%d" % truss_index)
		for side in [-1.0, 1.0]:
			_add_box(trusses, Vector3(truss_x, 3.62, side * 18.0), Vector3(1.5, 0.18, 0.18),
				Color(0.34, 0.25, 0.15), Color(0.9, 0.54, 0.2), 0.42,
				"TrussLamp%d_%d" % [truss_index, int(side)])
			if truss_index % 2 == 0:
				var light := _add_light(trusses, Vector3(truss_x, 3.45, side * 18.0),
					Color(0.92, 0.67, 0.36), 0.72, 8.0)
				light.name = "TrussWorkLight%d_%d" % [truss_index, int(side)]

	# Drain lips and datum studs make every board row legible without turning the
	# chamber into a literal toy grid.
	var gutters := Node3D.new()
	gutters.name = "BoardGutters"
	decoration.add_child(gutters)
	for lane_index in range(7):
		var lane_offset := -18.0 + float(lane_index) * BOARD_CELL_SIZE
		_add_box(gutters, Vector3(60.0, 0.18, lane_offset), Vector3(38.6, 0.12, 0.32),
			Color(0.29, 0.2, 0.11), Color(0.62, 0.38, 0.14), 0.16,
			"RowGutter%d" % lane_index)
		_add_box(gutters, Vector3(42.0 + float(lane_index) * BOARD_CELL_SIZE, 0.18, 0.0), Vector3(0.32, 0.12, 38.6),
			Color(0.29, 0.2, 0.11), Color(0.62, 0.38, 0.14), 0.16,
			"ColumnGutter%d" % lane_index)
	for stud_index in range(18):
		var stud_x := 42.5 + float(stud_index % 9) * 4.35
		var stud_z := -19.2 if stud_index < 9 else 19.2
		_add_box(gutters, Vector3(stud_x, 0.28, stud_z), Vector3(0.42, 0.22, 0.42),
			Color(0.4, 0.29, 0.15), Color(0.9, 0.56, 0.2), 0.32,
			"BoardDatumStud%d" % stud_index)

	var conduits := Node3D.new()
	conduits.name = "ServiceConduits"
	decoration.add_child(conduits)
	for conduit_index in range(3):
		var source: Vector3 = [TERM_ALPHA_POS, TERM_BETA_POS, TERM_GAMMA_POS][conduit_index]
		var tint: Color = [Color(0.36, 0.66, 0.9), Color(0.56, 0.8, 0.48), Color(0.88, 0.58, 0.28)][conduit_index]
		for segment_index in range(6):
			var segment_x := source.x + 5.0 + float(segment_index) * 7.2
			_add_box(conduits, Vector3(segment_x, 0.24, source.z), Vector3(6.5, 0.12, 0.24),
				Color(0.2, 0.17, 0.13), tint, 0.22,
				"ServiceConduit%d_%d" % [conduit_index, segment_index])

	var mother_nave := Node3D.new()
	mother_nave.name = "MotherNave"
	decoration.add_child(mother_nave)
	for rib_index in range(6):
		var rib_x := 88.0 + float(rib_index) * 5.2
		_add_box(mother_nave, Vector3(rib_x, 0.22, -18.5), Vector3(0.3, 0.32, 6.0),
			Color(0.28, 0.2, 0.12), Color(0.72, 0.42, 0.18), 0.2,
			"NaveRibNorth%d" % rib_index)
		_add_box(mother_nave, Vector3(rib_x, 0.22, 18.5), Vector3(0.3, 0.32, 6.0),
			Color(0.28, 0.2, 0.12), Color(0.72, 0.42, 0.18), 0.2,
			"NaveRibSouth%d" % rib_index)
	for pylon_index in range(5):
		var pylon_z := -16.0 + float(pylon_index) * 8.0
		_add_box(mother_nave, Vector3(113.5, 1.25, pylon_z), Vector3(0.65, 2.5, 0.65),
			Color(0.18, 0.16, 0.13), Color(0.86, 0.58, 0.24), 0.25,
			"NavePylon%d" % pylon_index)

	decoration.set_meta("decoration_audit", {
		"instances": decoration.find_children("*", "MeshInstance3D", true, false).size(),
		"lights": decoration.find_children("*", "OmniLight3D", true, false).size(),
		"collision_shapes": decoration.find_children("*", "CollisionShape3D", true, false).size(),
		"clearance": "surface_only_no_obstacles",
		"families": ["wall_bays", "ceiling_trusses", "board_gutters", "service_conduits", "mother_nave"],
	})

func _build_terminal_bank() -> void:
	_build_terminal("term_alpha", TERM_ALPHA_POS, "TERM-12A", "PORTAL-12A")
	_build_terminal("term_beta", TERM_BETA_POS, "TERM-12B", "PORTAL-12B")
	_build_terminal("term_gamma", TERM_GAMMA_POS, "TERM-12C", "PORTAL-12C")

func _build_root_board() -> void:
	for root_id in ROOT_ORDER:
		_build_root(root_id)

func _build_service_alcoves() -> void:
	for terminal_id in TERMINAL_ORDER:
		_build_service_alcove(terminal_id)

func _build_service_alcove(terminal_id: String) -> void:
	var base_pos: Vector3 = TERMINAL_SERVICE_POSITIONS[terminal_id]
	var service_roots: Array = TERMINAL_SERVICES[terminal_id]
	var platform_depth := maxf(9.0, float(service_roots.size()) * 3.6 + 2.0)
	_add_box(self, base_pos + Vector3(0.0, -0.06, 0.0), Vector3(8.4, 0.14, platform_depth), Color(0.11, 0.1, 0.09))
	_add_box(self, base_pos + Vector3(-3.8, 1.1, 0.0), Vector3(0.24, 2.2, platform_depth), Color(0.16, 0.14, 0.12))
	_add_box(self, base_pos + Vector3(0.0, 1.1, -platform_depth * 0.5), Vector3(8.4, 2.2, 0.24), Color(0.16, 0.14, 0.12))
	_add_label(self, _terminal_service_label(terminal_id).to_upper(), base_pos + Vector3(0.0, 2.35, 0.0), Color(0.84, 0.76, 0.62))
	for index in range(service_roots.size()):
		var root_id := str(service_roots[index])
		var row_pos := _service_row_position(terminal_id, index, service_roots.size())
		_add_box(self, row_pos + Vector3(0.0, 0.16, 0.0), Vector3(5.8, 0.08, 1.7), Color(0.18, 0.14, 0.1), Color(0.34, 0.22, 0.14), 0.08)
		_add_label(self, str(ROOT_DEFS[root_id].get("label", root_id)), row_pos + Vector3(0.0, 1.45, 0.52), Color(0.9, 0.78, 0.56))
		for direction in [-1, 1]:
			var bud_pos := row_pos + Vector3(-1.55 if direction < 0 else 1.55, 0.14, -0.48)
			_add_box(self, bud_pos + Vector3(0.0, 0.18, 0.0), Vector3(0.54, 0.36, 0.54), Color(0.24, 0.18, 0.12), Color(0.72, 0.54, 0.26), 0.22)
			_add_label(self, _bud_label(direction), bud_pos + Vector3(0.0, 0.86, 0.0), Color(0.96, 0.8, 0.52))
			var interactable = _add_interactable(
				self,
				"%s_%s_%s" % [terminal_id.capitalize(), root_id.capitalize(), "neg" if direction < 0 else "pos"],
				"%s / %s" % [ROOT_DEFS[root_id].get("label", root_id), _bud_label(direction)],
				bud_pos,
				"SHIFT",
				"peris",
				ROOT_WORK_SECONDS,
				true,
				1.5,
				Interactable.InteractableType.TIMED_ACTION
			)
			var control_key := _root_control_key(root_id, direction)
			_root_control_interactables[control_key] = interactable
			interactable.set_pre_trigger_validator(
				_validate_root_control_trigger.bind(root_id, direction, interactable)
			)
			interactable.interacted.connect(
				_on_root_control_interacted.bind(interactable, root_id, direction)
			)

func _build_portal_bank() -> void:
	# The fixed portal hardware is a portable, UV-mapped mechanism. Only the luminous lens below
	# remains procedural because it is a live state surface, not a decorative prop.
	_portal_base_frame = MOTHER_PORTAL_FRAME_SCENE.instantiate() as Node3D
	_portal_base_frame.name = "MotherPortalBaseFrame"
	_portal_base_frame.position = BASE_PORTAL_POS
	add_child(_portal_base_frame)
	_portal_base_fill = _add_portal_lens(
		self,
		"MotherPortalBaseLens",
		BASE_PORTAL_POS + Vector3(0.0, 1.18, 0.0),
		Color(0.76, 0.56, 0.28)
	)
	_portal_base_material = _portal_base_fill.material_override
	_portal_entry_interactable = _add_interactable(
		self, "MotherPortalEntry", "Calibrate portal crossing",
		BASE_PORTAL_POS + Vector3(0.0, 0.2, 0.0), "CROSS", "peris",
		PORTAL_CALIBRATION_SECONDS, true, 1.5, Interactable.InteractableType.TIMED_ACTION
	)
	_portal_entry_interactable.set_pre_trigger_validator(
		_validate_portal_trigger.bind(_portal_entry_interactable)
	)
	_portal_entry_interactable.interacted.connect(
		_on_portal_interacted.bind(_portal_entry_interactable)
	)
	_portal_remote_frame = MOTHER_PORTAL_FRAME_SCENE.instantiate() as Node3D
	_portal_remote_frame.name = "MotherPortalRemoteFrame"
	_portal_remote_frame.position = Vector3(2000.0, 0.0, 2000.0)
	_portal_remote_frame.visible = false
	add_child(_portal_remote_frame)
	_portal_remote_fill = _add_portal_lens(
		self,
		"MotherPortalRemoteLens",
		Vector3(2000.0, 1.18, 2000.0),
		Color(0.92, 0.66, 0.32)
	)
	_portal_remote_material = _portal_remote_fill.material_override
	_portal_remote_label = _add_label(self, "RETURN", Vector3(2000.0, 3.0, 2000.0), Color(0.94, 0.76, 0.46))
	_portal_return_interactable = _add_interactable(
		self, "MotherPortalReturn", "Calibrate return crossing",
		Vector3(2000.0, 0.2, 2000.0), "RETURN", "peris",
		PORTAL_CALIBRATION_SECONDS, true, 1.5, Interactable.InteractableType.TIMED_ACTION
	)
	_portal_return_interactable.set_pre_trigger_validator(
		_validate_portal_trigger.bind(_portal_return_interactable)
	)
	_portal_return_interactable.interacted.connect(
		_on_portal_interacted.bind(_portal_return_interactable)
	)

func _add_portal_lens(
	parent: Node3D,
	lens_name: String,
	position: Vector3,
	emission: Color
) -> MeshInstance3D:
	var lens := MeshInstance3D.new()
	lens.name = lens_name
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = 0.8
	lens_mesh.bottom_radius = 0.8
	lens_mesh.height = 0.045
	lens_mesh.radial_segments = 32
	lens.mesh = lens_mesh
	lens.position = position
	lens.rotation.x = PI * 0.5
	lens.scale = Vector3(0.78, 1.0, 1.08)
	lens.material_override = _make_material(
		Color(0.12, 0.1, 0.08), emission, 0.2
	)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lens.set_meta("runtime_state_visual", "portal_lens")
	parent.add_child(lens)
	return lens

func _build_gear_station() -> void:
	_add_box(self, GEAR_POS + Vector3(0.0, -0.1, 0.0), Vector3(3.8, 0.28, 3.4), Color(0.12, 0.1, 0.08))
	_add_box(self, GEAR_POS + Vector3(0.0, 0.38, 0.0), Vector3(2.1, 0.26, 2.1), Color(0.18, 0.14, 0.1), Color(0.46, 0.3, 0.16), 0.22)
	_add_label(self, "MOTHER GEAR", GEAR_POS + Vector3(0.0, 2.2, 0.0), Color(0.88, 0.76, 0.58))
	_gear_interactable = _add_interactable(
		self, "MotherGearInteractable", "Brace and lift Mother Gear",
		GEAR_POS + Vector3(0.0, 0.25, 0.0), "LIFT", "endo",
		GEAR_LIFT_SECONDS, true, 1.8, Interactable.InteractableType.TIMED_ACTION
	)
	_gear_interactable.set_pre_trigger_validator(
		_validate_gear_pickup_trigger.bind(_gear_interactable)
	)
	_gear_interactable.interacted.connect(
		_on_gear_pickup_interacted.bind(_gear_interactable)
	)

func _build_install_socket() -> void:
	_add_box(self, INSTALL_SOCKET_POS + Vector3(-2.3, -0.06, 0.0), Vector3(9.6, 0.18, 10.2), Color(0.12, 0.1, 0.08))
	for repair_id in REPAIR_POINT_ORDER:
		var repair_pos := _repair_point_position(repair_id)
		var repair_color: Color = REPAIR_POINT_DEFS[repair_id].get("color", Color(0.72, 0.82, 0.94))
		_add_box(self, repair_pos + Vector3(0.0, 0.48, 0.0), Vector3(1.9, 0.7, 1.9), Color(0.16, 0.16, 0.18))
		var mount := _add_box(self, repair_pos + Vector3(0.0, 0.78, 0.0), Vector3(1.14, 0.24, 1.14), Color(0.18, 0.2, 0.24), repair_color, 0.22)
		_repair_point_materials[repair_id] = mount.material_override
		_repair_point_labels[repair_id] = _add_label(self, str(REPAIR_POINT_DEFS[repair_id].get("label", repair_id)).to_upper(), repair_pos + Vector3(0.0, 2.1, 0.0), repair_color.lightened(0.15))
		var interactable := _add_interactable(
			self, "%sRepairInteractable" % repair_id.capitalize(),
			str(REPAIR_POINT_DEFS[repair_id].get("label", repair_id)),
			repair_pos + Vector3(0.0, 0.2, 0.0), "MOUNT", "endo",
			REPAIR_MOUNT_SECONDS, true, 1.7, Interactable.InteractableType.TIMED_ACTION
		)
		_repair_interactables[repair_id] = interactable
		interactable.set_pre_trigger_validator(
			_validate_gear_install_trigger.bind(repair_id, interactable)
		)
		interactable.interacted.connect(
			_on_gear_install_interacted.bind(interactable, repair_id)
		)
		if repair_id == CORRECT_REPAIR_ID:
			_install_interactable = interactable
	# The inventory item is removed when the repair commits, so the socket owns a persistent view of
	# the exact authored gear used by the ground/carried item presenter. It is not a second item and
	# never participates in inventory logic.
	_installed_gear_root = MOTHER_GEAR_VISUAL_SCENE.instantiate() as Node3D
	_installed_gear_root.name = "InstalledMotherGear"
	_installed_gear_root.position = INSTALL_SOCKET_POS + Vector3(0.0, 1.03, 0.0)
	_installed_gear_root.set_meta("reuses_visual_kind", "mother_gear")
	_installed_gear_root.set_meta("visual_identity", MOTHER_GEAR_VISUAL_IDENTITY)
	add_child(_installed_gear_root)
	_installed_gear_root.visible = false

func _build_physical_repair_evidence() -> void:
	var evidence := Node3D.new()
	evidence.name = "MotherPhysicalRepairEvidence"
	evidence.set_meta("clicks_required", 0)
	evidence.set_meta(
		"causal_model",
		"Freight wear, socket wear, intact seals, root film, and caretaker tools distinguish the load-bearing center mount from the two false hypotheses."
	)
	add_child(evidence)

	# Old freight paths polish the floor where they converge on the center mount.
	# These are existing architecture, not additional inspection stations.
	_add_floor_trace(evidence, "FreightWearNorth", Vector3(77.0, 0.13, -8.5), Vector3(92.2, 0.13, -0.65), 0.34, Color(0.5, 0.42, 0.3))
	_add_floor_trace(evidence, "FreightWearCenter", Vector3(77.0, 0.13, 0.0), Vector3(92.1, 0.13, 0.0), 0.46, Color(0.58, 0.48, 0.32))
	_add_floor_trace(evidence, "FreightWearSouth", Vector3(77.0, 0.13, 8.5), Vector3(92.2, 0.13, 0.65), 0.34, Color(0.5, 0.42, 0.3))

	# The center spindle is scarred on every bearing face. The edge relief still
	# carries its dusty seal, while the bloom bypass has only root film: neither
	# false mount has ever carried freight load.
	var center := _repair_point_position(CORRECT_REPAIR_ID)
	for scar in [
		{"name": "CenterSocketWearNorth", "offset": Vector3(0.0, 0.94, -0.72), "size": Vector3(1.2, 0.08, 0.16)},
		{"name": "CenterSocketWearSouth", "offset": Vector3(0.0, 0.94, 0.72), "size": Vector3(1.2, 0.08, 0.16)},
		{"name": "CenterSocketWearWest", "offset": Vector3(-0.72, 0.94, 0.0), "size": Vector3(0.16, 0.08, 1.2)},
		{"name": "CenterSocketWearEast", "offset": Vector3(0.72, 0.94, 0.0), "size": Vector3(0.16, 0.08, 1.2)},
	]:
		_add_box(evidence, center + Vector3(scar["offset"]), Vector3(scar["size"]), Color(0.74, 0.68, 0.52), Color(0.34, 0.29, 0.18), 0.08, str(scar["name"]))
	var edge := _repair_point_position("edge_relief")
	_add_box(evidence, edge + Vector3(0.0, 0.95, 0.0), Vector3(1.48, 0.07, 0.18), Color(0.35, 0.32, 0.27), Color.BLACK, 0.0, "EdgeReliefDustSeal")
	_add_box(evidence, edge + Vector3(0.0, 0.95, 0.0), Vector3(0.18, 0.07, 1.48), Color(0.35, 0.32, 0.27), Color.BLACK, 0.0, "EdgeReliefSealCross")
	var bypass := _repair_point_position("bloom_bypass")
	_add_floor_trace(evidence, "BloomBypassRootFilm", bypass + Vector3(-1.1, 0.94, -0.9), bypass + Vector3(1.05, 0.94, 0.85), 0.2, Color(0.34, 0.26, 0.18))
	_add_floor_trace(evidence, "BloomBypassRootFilmFork", bypass + Vector3(-0.85, 0.94, 0.8), bypass + Vector3(0.9, 0.94, -0.65), 0.16, Color(0.28, 0.34, 0.2))

	# The caretaker's worn gauge and center-sized brace communicate the same fit.
	var tool_base := HIDE_SPOT_POS + Vector3(1.75, 0.0, -1.05)
	_add_box(evidence, tool_base + Vector3(0.0, 0.72, 0.0), Vector3(1.7, 1.44, 0.18), Color(0.16, 0.14, 0.12), Color.BLACK, 0.0, "CaretakerToolRack")
	_add_box(evidence, tool_base + Vector3(-0.45, 0.82, -0.14), Vector3(0.18, 0.95, 0.18), Color(0.52, 0.47, 0.36), Color.BLACK, 0.0, "CaretakerTorqueGauge")
	_add_box(evidence, tool_base + Vector3(-0.31, 1.2, -0.16), Vector3(0.48, 0.09, 0.12), Color(0.7, 0.62, 0.42), Color(0.32, 0.26, 0.14), 0.08, "CaretakerGaugeNeedle")
	_add_box(evidence, tool_base + Vector3(0.42, 0.75, -0.14), Vector3(0.62, 0.16, 0.18), Color(0.58, 0.52, 0.4), Color.BLACK, 0.0, "CaretakerCenterBrace")
	_add_floor_trace(evidence, "CaretakerBraceMarkNorth", HIDE_SPOT_POS + Vector3(-1.5, 0.13, -0.7), HIDE_SPOT_POS + Vector3(1.2, 0.13, -0.7), 0.16, Color(0.45, 0.37, 0.25))
	_add_floor_trace(evidence, "CaretakerBraceMarkSouth", HIDE_SPOT_POS + Vector3(-1.5, 0.13, 0.7), HIDE_SPOT_POS + Vector3(1.2, 0.13, 0.7), 0.16, Color(0.45, 0.37, 0.25))

func _add_floor_trace(parent: Node3D, trace_name: String, from: Vector3, to: Vector3, width: float, color: Color) -> MeshInstance3D:
	var trace := _add_box(
		parent,
		(from + to) * 0.5,
		Vector3(width, 0.055, maxf(from.distance_to(to), 0.12)),
		color,
		color.lightened(0.08),
		0.06,
		trace_name
	)
	trace.look_at(to, Vector3.UP, true)
	return trace

func _build_exit_handoff() -> void:
	var pad := _add_box(self, EXIT_POS + Vector3(0.0, -0.05, 0.0), Vector3(5.2, 0.14, 4.2),
		Color(0.11, 0.12, 0.1), Color(0.42, 0.72, 0.5), 0.08, "MotherExitPad")
	var left_pylon := _add_box(self, EXIT_POS + Vector3(-1.65, 1.35, 0.0), Vector3(0.34, 2.7, 0.44),
		Color(0.18, 0.2, 0.16), Color(0.54, 0.86, 0.62), 0.16, "MotherExitPylonLeft")
	var right_pylon := _add_box(self, EXIT_POS + Vector3(1.65, 1.35, 0.0), Vector3(0.34, 2.7, 0.44),
		Color(0.18, 0.2, 0.16), Color(0.54, 0.86, 0.62), 0.16, "MotherExitPylonRight")
	var lintel := _add_box(self, EXIT_POS + Vector3(0.0, 2.62, 0.0), Vector3(3.65, 0.3, 0.44),
		Color(0.18, 0.2, 0.16), Color(0.54, 0.86, 0.62), 0.16, "MotherExitLintel")
	_exit_gate_root = MOTHER_RINGS_MEMBRANE_SCENE.instantiate() as Node3D
	_exit_gate_root.name = "MotherRingsGatePresenter"
	_exit_gate_root.position = EXIT_POS
	add_child(_exit_gate_root)
	# The ribbed chembrane is visibly flexible and lifts through the authoritative opening phase;
	# it reads as a physical gate, never an abstract rectangular beacon.
	_rings_membrane_mesh = _exit_gate_root.find_child("Model", true, false) as MeshInstance3D
	_exit_material = (
		_rings_membrane_mesh.material_override as StandardMaterial3D
		if is_instance_valid(_rings_membrane_mesh) else null
	)
	var gate_blocker := _add_static_blocker(
		"MotherRingsGateBlocker", RINGS_GATE_BLOCKER_CENTER, RINGS_GATE_BLOCKER_SIZE
	)
	_rings_gate_blocker_body = gate_blocker.get("body")
	_rings_gate_collision_shape = gate_blocker.get("shape")
	_exit_label = _add_label(self, "RINGS HANDOFF  ·  SEALED", EXIT_POS + Vector3(0.0, 3.35, 0.0), Color(0.46, 0.5, 0.42))
	_exit_interactable = _add_object_interactable(
		self, "MotherExitInteractable", "Gather the conscious party for the Greenfields Collective", EXIT_POS,
		"REGROUP", [pad, left_pylon, right_pylon, lintel, _rings_membrane_mesh], "", EXIT_HANDOFF_SECONDS,
		true, EXIT_INTERACTION_RADIUS, Interactable.InteractableType.TIMED_ACTION
	)
	_exit_interactable.set_pre_trigger_validator(
		_validate_exit_handoff_trigger.bind(_exit_interactable)
	)
	_exit_interactable.interacted.connect(
		_on_exit_handoff_interacted.bind(_exit_interactable)
	)

func _build_mother() -> void:
	for i in range(3):
		_add_box(self, MOTHER_POS + Vector3(-1.0 + float(i), 0.45, 0.0), Vector3(1.1, 0.9, 2.2), Color(0.24, 0.18, 0.12))
	for bloom_offset in [Vector3(-1.4, 1.8, 0.8), Vector3(-0.2, 2.15, -0.5), Vector3(1.0, 1.9, 0.4), Vector3(0.2, 2.5, 0.0)]:
		var bloom := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.42
		mesh.height = 0.84
		bloom.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.56, 0.46, 0.22)
		material.emission_enabled = true
		material.emission = Color(0.82, 0.58, 0.24)
		material.emission_energy_multiplier = 0.12
		bloom.material_override = material
		bloom.position = MOTHER_POS + bloom_offset
		add_child(bloom)
		_mother_bloom_materials.append(material)
	_mother_interactable = _add_interactable(
		self, "MotherTendInteractable", "Tend Mother Flure",
		MOTHER_POS + Vector3(-2.2, 0.4, 0.0), "TEND", "peris",
		MOTHER_TEND_SECONDS, true, 2.0, Interactable.InteractableType.TIMED_ACTION
	)
	_mother_interactable.set_pre_trigger_validator(
		_validate_mother_tend_trigger.bind(_mother_interactable)
	)
	_mother_interactable.interacted.connect(
		_on_mother_tend_interacted.bind(_mother_interactable)
	)

func _build_collapse_offshoot() -> void:
	_add_box(self, Vector3(50.0, 0.01, 18.0), Vector3(28.0, 0.04, 8.0), Color(0.1, 0.085, 0.08))
	_add_box(self, Vector3(50.0, 1.3, 22.1), Vector3(28.0, 2.6, 0.3), Color(0.14, 0.12, 0.1))
	_add_box(self, Vector3(50.0, 1.3, 13.9), Vector3(28.0, 2.6, 0.3), Color(0.14, 0.12, 0.1))
	_collapse_debris_root = Node3D.new()
	_collapse_debris_root.name = "MotherCollapseDebrisPresenter"
	add_child(_collapse_debris_root)
	# The visible rubble spans the same choke as its collision/grid footprint; there is no invisible
	# wall for the player to discover by bumping into empty corridor space.
	for debris_offset in [
		Vector3(-0.7, 0.55, -5.0),
		Vector3(0.45, 0.48, -3.4),
		Vector3(-0.35, 0.6, -1.8),
		Vector3(0.65, 0.52, -0.2),
		Vector3(-0.5, 0.58, 1.2),
	]:
		_add_box(_collapse_debris_root, COLLAPSE_POS + debris_offset, Vector3(1.4, 1.0, 1.0), Color(0.28, 0.24, 0.18))
	var collapse_blocker := _add_static_blocker(
		"MotherCollapseBlocker", COLLAPSE_BLOCKER_CENTER, COLLAPSE_BLOCKER_SIZE
	)
	_collapse_blocker_body = collapse_blocker.get("body")
	_collapse_collision_shape = collapse_blocker.get("shape")
	# The rubble body remains movement-authoritative, but the visible debris/interactable owns
	# object picking. Letting this enclosing physics volume answer input rays makes the truthful
	# SHIFT affordance unreachable even though Endo can see it.
	if is_instance_valid(_collapse_blocker_body):
		_collapse_blocker_body.input_ray_pickable = false
	_collapse_interactable = _add_inspection_interactable(
		self,
		"MotherCollapseInteractable",
		"Collapsed Debris",
		COLLAPSE_POS + Vector3(0.0, 0.2, 0.0),
		"SHIFT",
		"endo",
		1.5,
		true
	)
	_collapse_interactable.set_pre_trigger_validator(
		_validate_collapse_trigger.bind(_collapse_interactable)
	)
	_collapse_interactable.interacted.connect(
		_on_collapse_interacted.bind(_collapse_interactable)
	)
	for body_id in BODY_POSITIONS.keys():
		var pos: Vector3 = BODY_POSITIONS[body_id]
		var body := _add_box(self, pos, Vector3(2.2, 0.3, 0.86), Color(0.34, 0.28, 0.22))
		_body_materials[body_id] = body.material_override
		_body_labels[body_id] = _add_label(self, BODY_NAMES.get(body_id, body_id).to_upper(), pos + Vector3(0.0, 1.25, 0.0), Color(0.8, 0.72, 0.64))
		var interactable = _add_inspection_interactable(
			self,
			"%sInteractable" % body_id.capitalize(),
			BODY_NAMES.get(body_id, body_id),
			pos + Vector3(0.0, 0.22, 0.0),
			"ABSORB",
			"endo",
			1.5,
			true
		)
		_body_interactables[body_id] = interactable
		interactable.set_pre_trigger_validator(
			_validate_body_harvest_trigger.bind(body_id, interactable)
		)
		interactable.interacted.connect(
			_on_body_harvest_interacted.bind(interactable, body_id)
		)

func _add_static_blocker(blocker_name: String, center: Vector3, size: Vector3) -> Dictionary:
	var body := StaticBody3D.new()
	body.name = blocker_name
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.name = "%sCollision" % blocker_name
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return {"body": body, "shape": collision}

func _build_hide_spot() -> void:
	_add_box(self, HIDE_SPOT_POS + Vector3(0.0, -0.02, 0.0), Vector3(7.4, 0.08, 6.0), Color(0.08, 0.1, 0.09))
	_add_box(self, HIDE_SPOT_POS + Vector3(-3.7, 1.2, 0.0), Vector3(0.2, 2.4, 6.0), Color(0.14, 0.16, 0.14))
	_add_box(self, HIDE_SPOT_POS + Vector3(0.0, 1.2, -3.0), Vector3(7.4, 2.4, 0.2), Color(0.14, 0.16, 0.14))
	_add_light(self, HIDE_SPOT_POS + Vector3(0.0, 1.8, 0.0), Color(0.7, 0.54, 0.32), 1.25, 8.0)
	_add_label(self, "CARETAKER ALCOVE", HIDE_SPOT_POS + Vector3(0.0, 2.3, 0.0), Color(0.88, 0.76, 0.62))

func _build_overlay_roots() -> void:
	_aster_overlay_root = Node3D.new()
	add_child(_aster_overlay_root)
	for terminal_id in TERMINAL_ORDER:
		var terminal_pos: Vector3 = _terminal_position(terminal_id)
		var service_pos: Vector3 = TERMINAL_SERVICE_POSITIONS[terminal_id]
		_add_overlay_label(_aster_overlay_root, _portal_label(terminal_id), terminal_pos + Vector3(0.0, 2.5, 0.0), Color(0.58, 0.86, 1.0))
		_add_link_overlay(terminal_pos + Vector3(0.0, 1.4, 0.0), service_pos + Vector3(0.0, 1.4, 0.0), Color(0.58, 0.86, 1.0))
		_add_overlay_label(_aster_overlay_root, _terminal_service_label(terminal_id).to_upper(), service_pos + Vector3(0.0, 2.35, 0.0), Color(0.58, 0.86, 1.0))
	_add_layout_ghost(_aster_overlay_root, Vector3(60.0, 0.12, 0.0), Vector2(36.0, 36.0), Color(0.46, 0.76, 0.98))
	_add_layout_ghost(_aster_overlay_root, Vector3(50.0, 0.12, 19.0), Vector2(28.0, 8.0), Color(0.38, 0.66, 0.88))
	_aster_overlay_root.visible = false

	_peris_overlay_root = Node3D.new()
	add_child(_peris_overlay_root)
	_peris_overlay_labels["mother"] = _add_overlay_label(_peris_overlay_root, "MOTHER: STALLED", MOTHER_POS + Vector3(0.0, 3.2, 0.0), Color(1.0, 0.82, 0.48))
	_peris_overlay_labels["care"] = _add_overlay_label(_peris_overlay_root, "CARETAKER TRACE", HIDE_SPOT_POS + Vector3(0.0, 1.9, 0.0), Color(0.82, 0.7, 0.96))
	_peris_overlay_labels["blur"] = _add_overlay_label(_peris_overlay_root, "WORKER MEMORY BLUR", Vector3(57.0, 2.0, 21.0), Color(0.7, 0.74, 1.0))
	for terminal_id in TERMINAL_ORDER:
		var service_roots: Array = TERMINAL_SERVICES[terminal_id]
		for index in range(service_roots.size()):
			var root_id := str(service_roots[index])
			var row_pos := _service_row_position(terminal_id, index, service_roots.size())
			_peris_overlay_labels[root_id] = _add_overlay_label(_peris_overlay_root, "", row_pos + Vector3(0.0, 2.05, 0.0), Color(0.98, 0.78, 0.46))
	_peris_overlay_root.visible = false

	_endo_overlay_root = Node3D.new()
	add_child(_endo_overlay_root)
	_add_endo_beacon("hide", "HIDE SLOT", HIDE_SPOT_POS + Vector3(0.0, 1.8, 0.0), Color(0.64, 0.82, 0.96))
	_add_endo_beacon("gear", "MOTHER GEAR", GEAR_POS + Vector3(0.0, 1.8, 0.0), Color(0.96, 0.78, 0.46))
	_add_endo_beacon("socket", "REPAIR ARRAY", INSTALL_SOCKET_POS + Vector3(-1.6, 1.9, 0.0), Color(0.76, 0.92, 0.54))
	_add_endo_beacon("repair_center", "LOAD REGULATOR", _repair_point_position(CORRECT_REPAIR_ID) + Vector3(0.0, 1.8, 0.0), Color(0.86, 0.98, 0.62))
	_add_endo_beacon("bodies", "FOOD SOURCE", Vector3(57.0, 1.9, 24.0), Color(0.92, 0.7, 0.54))
	_add_endo_beacon("carry", "SAFE CARRY PASS", CARRY_ROUTE_SOUTH_PASS + Vector3(0.0, 1.2, 0.0), Color(0.72, 0.94, 0.62))
	_endo_overlay_root.visible = false

func _build_terminal(terminal_id: String, position: Vector3, label_text: String, portal_label: String) -> void:
	_add_box(self, position, Vector3(2.2, 1.5, 1.2), Color(0.1, 0.12, 0.14))
	var screen := _add_box(self, position + Vector3(0.0, 0.9, 0.42), Vector3(1.55, 0.5, 0.08), Color(0.12, 0.16, 0.2), Color(0.18, 0.34, 0.5), 0.42)
	_terminal_materials[terminal_id] = screen.material_override
	_terminal_labels[terminal_id] = _add_label(self, portal_label, position + Vector3(0.0, 1.72, -0.82), Color(0.72, 0.66, 0.54))
	_add_label(self, label_text, position + Vector3(0.0, 2.2, 0.0), Color(0.76, 0.84, 0.92))
	# TERM-12A is the click-arrival onboarding seam used by the shared preview
	# contract. The two later banks are deliberate trace/reconstruction work.
	var interaction_type := Interactable.InteractableType.INSPECTION if terminal_id == "term_alpha" else Interactable.InteractableType.TIMED_ACTION
	var dwell_time := 0.0 if terminal_id == "term_alpha" else TERMINAL_WORK_SECONDS
	var interactable = _add_interactable(
		self, "%sInteractable" % terminal_id.capitalize(), label_text,
		position + Vector3(0.0, 0.2, 0.0), "HACK", "aster", dwell_time,
		true, 1.5, interaction_type
	)
	_terminal_interactables[terminal_id] = interactable
	interactable.set_pre_trigger_validator(
		_validate_terminal_trigger.bind(terminal_id, interactable)
	)
	interactable.interacted.connect(
		_on_terminal_interacted.bind(interactable, terminal_id)
	)

func _build_root(root_id: String) -> void:
	var def: Dictionary = ROOT_DEFS[root_id]
	var anchor := int(def.get("anchor", 0))
	var root_pos := _root_world_center(def, anchor)
	var size := _root_size(def)
	var swarm_size := _root_swarm_size(def)
	var root_color: Color = def.get("color", Color(0.5, 0.34, 0.18))
	var root_node := _add_box(self, root_pos, size, root_color, root_color.lightened(0.08), 0.18)
	var swarm_node := _add_box(self, root_pos + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0), swarm_size, Color(0.16, 0.12, 0.08), def.get("swarm_color", Color(0.82, 0.56, 0.2)), 0.48)
	var world_label := _add_label(self, "%s %s" % [def.get("short", ""), def.get("label", root_id)], root_pos + Vector3(0.0, 1.85, 0.0), Color(0.9, 0.78, 0.56))
	_roots[root_id] = {
		"id": root_id,
		"label": def.get("label", root_id.to_upper()),
		"short": def.get("short", root_id.substr(0, 1).to_upper()),
		"orientation": def.get("orientation", "horizontal"),
		"length": int(def.get("length", 2)),
		"fixed_line": int(def.get("fixed_line", 0)),
		"anchor": anchor,
		"target_anchor": -1,
		"initial_anchor": anchor,
		"min_anchor": int(def.get("min_anchor", anchor)),
		"max_anchor": int(def.get("max_anchor", anchor)),
		"terminal": str(def.get("terminal", "")),
		"node": root_node,
		"swarm_node": swarm_node,
		"world_label": world_label,
		"size": size,
		"swarm_size": swarm_size,
		"anim_start": 0.0,
		"anim_end": 0.0,
		"swarm_start": 0.0,
		"swarm_end": 0.0,
		"anim_from_pos": root_pos,
		"anim_to_pos": root_pos,
		"swarm_from_pos": root_pos + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0),
		"swarm_to_pos": root_pos + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0),
	}

func _update_terminal_visuals() -> void:
	for terminal_id in _terminal_materials.keys():
		var material: StandardMaterial3D = _terminal_materials[terminal_id]
		var active: bool = terminal_id == _active_terminal_id and _is_portal_open(_get_scheduler_tick())
		if material != null:
			material.albedo_color = Color(0.18, 0.24, 0.3) if active else Color(0.12, 0.16, 0.2)
			material.emission = Color(0.46, 0.78, 1.0) if active else Color(0.18, 0.34, 0.5)
			material.emission_enabled = true
		if _terminal_labels.has(terminal_id):
			_terminal_labels[terminal_id].modulate = Color(0.98, 0.8, 0.5) if active else Color(0.72, 0.66, 0.54)

func _update_portal_visuals() -> void:
	var open := _is_portal_open(_get_scheduler_tick())
	var transit_idle := _portal_transit_phase == PORTAL_TRANSIT_IDLE
	if _portal_base_fill != null:
		_portal_base_fill.visible = open
	if _portal_base_material != null:
		_portal_base_material.emission_energy_multiplier = 0.84 if open else 0.12
	var remote_frame_pos := Vector3(2000.0, 0.0, 2000.0)
	var remote_pos := Vector3(2000.0, 1.18, 2000.0)
	var label_pos := Vector3(2000.0, 3.0, 2000.0)
	if open:
		remote_frame_pos = _terminal_service_position(_active_terminal_id)
		remote_pos = remote_frame_pos + Vector3(0.0, 1.18, 0.0)
		label_pos = _terminal_service_position(_active_terminal_id) + Vector3(0.0, 2.9, 0.0)
		_portal_return_interactable.position = _terminal_service_position(_active_terminal_id) + Vector3(-1.25, 0.2, 0.0)
	else:
		_portal_return_interactable.position = Vector3(2000.0, 0.2, 2000.0)
	if is_instance_valid(_portal_remote_frame):
		_portal_remote_frame.position = remote_frame_pos
		_portal_remote_frame.visible = open
	if _portal_remote_fill != null:
		_portal_remote_fill.position = remote_pos
		_portal_remote_fill.visible = open
	if _portal_remote_material != null:
		_portal_remote_material.emission_energy_multiplier = 0.92 if open else 0.12
	if _portal_remote_label != null:
		_portal_remote_label.position = label_pos
		_portal_remote_label.visible = open
		_portal_remote_label.text = _terminal_service_label(_active_terminal_id).to_upper() if open else "RETURN"
	_set_extension_interactable_enabled(
		_portal_entry_interactable,
		open and transit_idle and _peris_remote_terminal == ""
	)
	_set_extension_interactable_enabled(
		_portal_return_interactable,
		open and transit_idle and _peris_remote_terminal != "" \
			and _active_terminal_id == _peris_remote_terminal
	)

func _update_portal_overlay(current_tick: float) -> void:
	if _portal_base_material != null and _is_portal_open(current_tick):
		_portal_base_material.emission_energy_multiplier = 0.65 + 0.22 * sin(current_tick * 7.4)
	if _portal_remote_material != null and _is_portal_open(current_tick):
		_portal_remote_material.emission_energy_multiplier = 0.72 + 0.22 * sin(current_tick * 7.4 + 0.4)

func _update_body_visuals() -> void:
	for body_id in BODY_POSITIONS.keys():
		var remaining := int(_body_remaining.get(body_id, 0))
		if _body_materials.has(body_id):
			var material: StandardMaterial3D = _body_materials[body_id]
			material.albedo_color = Color(0.18, 0.16, 0.14) if remaining <= 0 else (Color(0.36, 0.28, 0.2) if _collapse_cleared else Color(0.26, 0.22, 0.18))
		if _body_labels.has(body_id):
			_body_labels[body_id].text = "%s // %d UNIT%s" % [
				str(BODY_NAMES.get(body_id, body_id)).to_upper(),
				remaining,
				"" if remaining == 1 else "S",
			]
			_body_labels[body_id].modulate = Color(0.52, 0.48, 0.44) if remaining <= 0 else Color(0.82, 0.74, 0.66)

func _update_mother_visuals() -> void:
	for material in _mother_bloom_materials:
		if _mother_tended:
			material.albedo_color = Color(0.82, 0.68, 0.26)
			material.emission = Color(1.0, 0.82, 0.34)
			material.emission_energy_multiplier = 1.1
		elif _gear_installed:
			material.albedo_color = Color(0.68, 0.56, 0.22)
			material.emission = Color(0.96, 0.74, 0.3)
			material.emission_energy_multiplier = 0.52
		elif not _repair_attempts.is_empty():
			material.albedo_color = Color(0.62, 0.42, 0.24)
			material.emission = Color(0.88, 0.34, 0.22)
			material.emission_energy_multiplier = 0.28
		else:
			material.albedo_color = Color(0.56, 0.46, 0.22)
			material.emission = Color(0.82, 0.58, 0.24)
			material.emission_energy_multiplier = 0.12
	for repair_id in REPAIR_POINT_ORDER:
		if not _repair_point_materials.has(repair_id):
			continue
		var material: StandardMaterial3D = _repair_point_materials[repair_id]
		if material == null:
			continue
		var base_color: Color = REPAIR_POINT_DEFS[repair_id].get("color", Color(0.72, 0.82, 0.94))
		if _installed_repair_id == repair_id:
			material.albedo_color = base_color.lightened(0.16)
			material.emission_energy_multiplier = 0.9
		elif _repair_attempts.has(repair_id):
			material.albedo_color = base_color.darkened(0.25)
			material.emission_energy_multiplier = 0.18
		else:
			material.albedo_color = Color(0.18, 0.2, 0.24)
			material.emission_energy_multiplier = 0.26
		if _repair_point_labels.has(repair_id):
			_repair_point_labels[repair_id].modulate = base_color.lightened(0.16) if _installed_repair_id == repair_id else (base_color.darkened(0.15) if _repair_attempts.has(repair_id) else base_color)
	if is_instance_valid(_installed_gear_root):
		_installed_gear_root.visible = (
			_gear_installed and _installed_repair_id == CORRECT_REPAIR_ID
		)

func _reset_extension_interactables() -> void:
	for interactable in _terminal_interactables.values():
		if is_instance_valid(interactable) and interactable.has_method("reset"):
			interactable.reset()
	for interactable in _root_control_interactables.values():
		if is_instance_valid(interactable) and interactable.has_method("reset"):
			interactable.reset()
	for interactable in [
		_portal_entry_interactable,
		_portal_return_interactable,
		_gear_interactable,
		_collapse_interactable,
	]:
		if is_instance_valid(interactable) and interactable.has_method("reset"):
			interactable.reset()
	for interactable in _body_interactables.values():
		if is_instance_valid(interactable) and interactable.has_method("reset"):
			interactable.reset()
	for interactable in _repair_interactables.values():
		if is_instance_valid(interactable) and interactable.has_method("reset"):
			interactable.reset()
	if is_instance_valid(_mother_interactable) and _mother_interactable.has_method("reset"):
		_mother_interactable.reset()
	if is_instance_valid(_exit_interactable) and _exit_interactable.has_method("reset"):
		_exit_interactable.reset()


## Mother authority owns every completed consequence; the Interactable registry owns only the
## short-lived accepted-source receipt. A snapshot can land synchronously after GameState records
## that receipt but before Interactable emits `interacted`. On restore, roll that uncommitted receipt
## back to an unused source instead of leaving the object permanently wedged or guessing a
## consequence. This also upgrades pre-receipt saves whose repeatable controls were registered as
## non-one-shots.
func _normalize_mother_source_receipt_registry() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var sources: Array = []
	sources.append_array(_terminal_interactables.values())
	sources.append_array(_root_control_interactables.values())
	sources.append_array([
		_portal_entry_interactable,
		_portal_return_interactable,
		_gear_interactable,
		_collapse_interactable,
		_mother_interactable,
		_exit_interactable,
	])
	sources.append_array(_body_interactables.values())
	sources.append_array(_repair_interactables.values())
	for source_v in sources:
		var source: Node = source_v
		if not is_instance_valid(source):
			continue
		source.set("one_shot", true)
		var data_id := str(source.get("data_id"))
		if data_id == "" or not gs.has_method("has_interactable") \
				or not gs.has_method("reset_interactable"):
			continue
		if not bool(gs.call("has_interactable", data_id)):
			continue
		var spec: Dictionary = gs.call("get_interactable", data_id)
		if not bool(spec.get("one_shot", false)) and gs.has_method("register_interactable"):
			spec["id"] = data_id
			spec["one_shot"] = true
			spec["triggered"] = false
			spec["enabled"] = true
			gs.call("register_interactable", spec)
		# Even a current one-shot may have been serialized in the tiny accepted-trigger seam.
		# The owner record has not committed that consequence, so the safe reconstruction is retry.
		gs.call("reset_interactable", data_id)


func _update_extension_interactable_states() -> void:
	for terminal_id in _terminal_interactables.keys():
		_set_extension_interactable_enabled(
			_terminal_interactables.get(terminal_id),
			_portal_transit_phase == PORTAL_TRANSIT_IDLE \
				and (_peris_remote_terminal == "" or _peris_remote_terminal == terminal_id)
		)
	for control_key in _root_control_interactables.keys():
		var parts := str(control_key).split(":")
		if parts.size() != 2:
			continue
		var root_id := str(parts[0])
		var direction := int(parts[1])
		var root: Dictionary = _roots.get(root_id, {})
		var target_anchor := int(root.get("anchor", 0)) + direction
		_set_extension_interactable_enabled(
			_root_control_interactables.get(control_key),
			not root.is_empty() \
				and _portal_transit_phase == PORTAL_TRANSIT_IDLE \
				and _peris_remote_terminal == str(root.get("terminal", "")) \
				and not _root_move_in_flight(root) \
				and target_anchor >= int(root.get("min_anchor", 0)) \
				and target_anchor <= int(root.get("max_anchor", 0)) \
				and _blocking_root_for(root_id, target_anchor) == ""
		)
	var gear_state := _get_item_state(_gear_item_id)
	_set_extension_interactable_enabled(
		_gear_interactable,
		not _gear_installed \
			and _gear_item_id != "" \
			and not gear_state.is_empty() \
			and str(gear_state.get("location", "")) == "ground" \
			and _is_gear_pocket_open()
	)
	var repair_enabled := (
		not _gear_installed
		and _endo_holds_gear()
		and _is_socket_lane_open()
	)
	for interactable in _repair_interactables.values():
		_set_extension_interactable_enabled(interactable, repair_enabled)

	var mother_ready := (
		_gear_installed
		and _installed_repair_id == CORRECT_REPAIR_ID
		and _is_mother_lane_clear()
		and not _mother_tended
	)
	_set_extension_interactable_enabled(_mother_interactable, mother_ready)
	_set_extension_interactable_enabled(
		_exit_interactable,
		_route_phase == "handoff"
			and _rings_gate_phase == RINGS_GATE_PHASE_OPEN
			and _mother_tended
			and not _exit_reached
	)
	_set_extension_interactable_enabled(
		_collapse_interactable, _collapse_phase == COLLAPSE_PHASE_BLOCKED
	)
	for body_id in BODY_POSITIONS.keys():
		_set_extension_interactable_enabled(
			_body_interactables.get(body_id),
			_collapse_phase == COLLAPSE_PHASE_CLEARED
				and _body_claim_phase == BODY_CLAIM_IDLE
				and int(_body_remaining.get(body_id, 0)) > 0
				and _next_body_source_item_id(body_id) != ""
		)

func _set_extension_interactable_enabled(interactable, enabled: bool) -> void:
	if not is_instance_valid(interactable):
		return
	# This projection runs every runtime/headless update. Reapplying the same value is
	# not harmless: Interactable.set_interaction_enabled() deliberately cancels an
	# in-flight dwell. Only cross the enablement boundary when authority actually changed.
	if bool(interactable.get("interaction_enabled")) == enabled:
		return
	if interactable.has_method("set_interaction_enabled"):
		interactable.set_interaction_enabled(enabled)
	else:
		interactable.set("interaction_enabled", enabled)

func _update_extension_visuals() -> void:
	var gate_open := _rings_gate_phase == RINGS_GATE_PHASE_OPEN
	var gate_opening := _rings_gate_phase == RINGS_GATE_PHASE_OPENING
	if _exit_material != null:
		_exit_material.albedo_color = (
			Color(0.46, 0.78, 0.54) if gate_open
			else (Color(0.32, 0.56, 0.38) if gate_opening else Color(0.16, 0.2, 0.17))
		)
		_exit_material.emission_energy_multiplier = (
			0.92 if gate_open else (0.56 if gate_opening else 0.1)
		)
	if _exit_label != null:
		var gate_readout := (
			"COMPLETE" if _route_phase == "complete"
			else ("OPEN  ·  REGROUP" if gate_open else ("OPENING" if gate_opening else "SEALED"))
		)
		_exit_label.text = "RINGS HANDOFF  ·  %s" % gate_readout
		_exit_label.modulate = (
			Color(0.72, 1.0, 0.76) if gate_open
			else (Color(0.62, 0.84, 0.66) if gate_opening else Color(0.46, 0.5, 0.42))
		)

# --- portable Mother Flure authority -----------------------------------------------------------

func mother_authority_key() -> String:
	var stable_id := chunk_name if chunk_name != "" else "mother_flure"
	return MOTHER_AUTHORITY_PREFIX + stable_id

func _body_source_position(body_id: String, ordinal: int) -> Vector3:
	if not BODY_POSITIONS.has(body_id):
		return Vector3.INF
	var index := clampi(ordinal - 1, 0, BODY_SOURCE_OFFSETS.size() - 1)
	var body_position: Vector3 = BODY_POSITIONS[body_id]
	var offset: Vector3 = BODY_SOURCE_OFFSETS[index]
	return body_position + offset

func _spawn_body_source(body_id: String, ordinal: int, legacy_recovery := false) -> String:
	return _spawn_item("lysate", _body_source_position(body_id, ordinal), {
		"display_name": "%s starch nodule %d" % [BODY_NAMES.get(body_id, body_id), ordinal],
		"display_names_by_character": {
			"aster": "Lysate",
			"peris": "Lysate",
			"endo": "Starch",
		},
		"visual_kind": "lysate",
		"visual_color": Color(0.78, 0.66, 0.38),
		"ground_label_visible": false,
		"atp_restore": 3.0,
		"mother_body_authority": mother_authority_key(),
		"mother_body_id": body_id,
		"mother_body_ordinal": ordinal,
		"source_fixture": "%sCorpse" % body_id.capitalize(),
		"legacy_source_recovery": legacy_recovery,
	})

func _is_tagged_mother_body_lysate(item_id: String) -> bool:
	var item := _get_item_state(item_id)
	if item.is_empty() or str(item.get("type", "")) != "lysate":
		return false
	var properties: Dictionary = item.get("properties", {})
	return str(properties.get("mother_body_authority", "")) == mother_authority_key()

func _is_valid_mother_body_source(item_id: String) -> bool:
	if not _is_tagged_mother_body_lysate(item_id):
		return false
	var properties: Dictionary = _get_item_state(item_id).get("properties", {})
	var body_id := str(properties.get("mother_body_id", ""))
	var ordinal := int(properties.get("mother_body_ordinal", 0))
	return BODY_POSITIONS.has(body_id) and ordinal >= 1 and ordinal <= BODY_YIELD_PER_CORPSE

func _body_item_at_source(item_id: String) -> bool:
	if not _is_valid_mother_body_source(item_id):
		return false
	var item := _get_item_state(item_id)
	var properties: Dictionary = item.get("properties", {})
	var body_id := str(properties.get("mother_body_id", ""))
	var ordinal := int(properties.get("mother_body_ordinal", 0))
	var item_position: Vector3 = item.get("position", Vector3.INF)
	return str(item.get("location", "")) == "ground" \
		and item_position.distance_to(
			_body_source_position(body_id, ordinal)) <= 0.05

func _body_item_holder(item_id: String) -> String:
	var item := _get_item_state(item_id)
	return str(item.get("holder", "")) if not item.is_empty() else ""

func _body_source_ids_for(body_id: String) -> Array:
	var ids_v: Variant = _body_source_item_ids.get(body_id, [])
	return ids_v as Array if ids_v is Array else []

func _next_body_source_item_id(body_id: String) -> String:
	for item_id_v in _body_source_ids_for(body_id):
		var item_id := str(item_id_v)
		if not _body_claimed_item_ids.has(item_id) and _body_item_at_source(item_id):
			return item_id
	return ""

func _body_physical_source_count() -> int:
	var count := 0
	for body_id in BODY_POSITIONS.keys():
		for item_id_v in _body_source_ids_for(body_id):
			var item_id := str(item_id_v)
			if not _body_claimed_item_ids.has(item_id) and _body_item_at_source(item_id):
				count += 1
	return count

func _clear_body_claim() -> void:
	_body_claim_phase = BODY_CLAIM_IDLE
	_body_claim_item_id = ""
	_body_claim_body_id = ""
	_body_claimed_by = ""

func _sync_body_remaining_from_sources() -> void:
	_body_remaining.clear()
	for body_id in BODY_POSITIONS.keys():
		var remaining := 0
		for item_id_v in _body_source_ids_for(body_id):
			if not _body_claimed_item_ids.has(str(item_id_v)):
				remaining += 1
		_body_remaining[body_id] = remaining

func _remove_all_mother_body_lysate() -> void:
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return
	var remove_ids: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		if _is_tagged_mother_body_lysate(item_id):
			remove_ids.append(item_id)
	for item_id in remove_ids:
		_remove_item(item_id)

func _spawn_fresh_body_sources() -> void:
	_remove_all_mother_body_lysate()
	_body_source_item_ids.clear()
	_body_claimed_item_ids.clear()
	_body_legacy_claimed.clear()
	for body_id_v in BODY_POSITIONS.keys():
		var body_id := str(body_id_v)
		var ids: Array[String] = []
		for ordinal in range(1, BODY_YIELD_PER_CORPSE + 1):
			ids.append(_spawn_body_source(body_id, ordinal))
		_body_source_item_ids[body_id] = ids
		_body_legacy_claimed[body_id] = 0
	_clear_body_claim()
	_body_claim_serial = 0
	_sync_body_remaining_from_sources()

func _migrate_legacy_body_sources(saved_bodies: Dictionary) -> void:
	_remove_all_mother_body_lysate()
	_body_source_item_ids.clear()
	_body_claimed_item_ids.clear()
	_body_legacy_claimed.clear()
	for body_id_v in BODY_POSITIONS.keys():
		var body_id := str(body_id_v)
		var remaining := clampi(
			int(saved_bodies.get(body_id, BODY_YIELD_PER_CORPSE)),
			0,
			BODY_YIELD_PER_CORPSE
		)
		var retired := BODY_YIELD_PER_CORPSE - remaining
		var ids: Array[String] = []
		# The exact IDs of already-spent legacy units never existed. Preserve only their count and make
		# every genuinely remaining unit physical at its source; never guess a holder.
		for ordinal in range(retired + 1, BODY_YIELD_PER_CORPSE + 1):
			ids.append(_spawn_body_source(body_id, ordinal, true))
		_body_source_item_ids[body_id] = ids
		_body_legacy_claimed[body_id] = retired
	_clear_body_claim()
	_body_claim_serial = 0
	_sync_body_remaining_from_sources()

func _reconcile_restored_body_claim() -> bool:
	if _body_claim_phase != BODY_CLAIMING:
		return false
	if _body_item_at_source(_body_claim_item_id):
		# Save landed after the reservation publication but before GameState moved the item.
		_body_claimed_item_ids.erase(_body_claim_item_id)
		_clear_body_claim()
		_sync_body_remaining_from_sources()
		return true
	if _body_item_holder(_body_claim_item_id) == _body_claimed_by:
		# Save landed in GameState's pickup signal: the exact item already reached the reserved actor.
		_clear_body_claim()
		_sync_body_remaining_from_sources()
		return true
	# Missing or wrong-holder items remain an unresolved reservation. All corpse interactions stay
	# disabled, so corrupted ownership can never be silently retargeted into a fresh reward.
	return false

func _mother_callback_tag(kind: String) -> String:
	return "%s:%s" % [mother_authority_key(), kind]

func _collapse_shift_progress(current_tick: float) -> float:
	if _collapse_phase == COLLAPSE_PHASE_CLEARED:
		return 1.0
	if _collapse_phase != COLLAPSE_PHASE_SHIFTING:
		return 0.0
	return clampf(
		(current_tick - _collapse_shift_started_at)
			/ maxf(_collapse_shift_deadline - _collapse_shift_started_at, 0.000001),
		0.0,
		1.0
	)

func _rings_gate_progress(current_tick: float) -> float:
	if _rings_gate_phase == RINGS_GATE_PHASE_OPEN:
		return 1.0
	if _rings_gate_phase != RINGS_GATE_PHASE_OPENING:
		return 0.0
	return clampf(
		(current_tick - _rings_gate_started_at)
			/ maxf(_rings_gate_deadline - _rings_gate_started_at, 0.000001),
		0.0,
		1.0
	)

func _ease_physical_progress(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _update_timed_physical_presenters(current_tick: float) -> void:
	if is_instance_valid(_collapse_debris_root):
		_collapse_debris_root.position = COLLAPSE_SHIFT_OFFSET * _ease_physical_progress(
			_collapse_shift_progress(current_tick)
		)
	if is_instance_valid(_collapse_collision_shape):
		_collapse_collision_shape.disabled = _collapse_phase == COLLAPSE_PHASE_CLEARED
	if is_instance_valid(_exit_gate_root):
		_exit_gate_root.position = EXIT_POS + RINGS_GATE_OPEN_OFFSET * _ease_physical_progress(
			_rings_gate_progress(current_tick)
		)
	if is_instance_valid(_rings_gate_collision_shape):
		_rings_gate_collision_shape.disabled = _rings_gate_phase == RINGS_GATE_PHASE_OPEN
	if is_instance_valid(_installed_gear_root):
		_installed_gear_root.visible = (
			_gear_installed and _installed_repair_id == CORRECT_REPAIR_ID
		)

func _commit_collapse_shift(expected_deadline: float) -> void:
	if _collapse_phase != COLLAPSE_PHASE_SHIFTING \
			or not is_equal_approx(_collapse_shift_deadline, expected_deadline):
		return
	_collapse_phase = COLLAPSE_PHASE_CLEARED
	_collapse_cleared = true
	_collapse_shift_started_at = -1.0
	_collapse_shift_deadline = -1.0
	_set_preview_step("mother_collapse_open")
	_show_note("The last slab clears. The preserved workers are physically reachable now.", 3.4)
	_update_timed_physical_presenters(_get_scheduler_tick())
	_apply_mother_topology()
	_update_body_visuals()
	_update_extension_interactable_states()
	_publish_mother_authority()

func _commit_rings_gate(expected_deadline: float) -> void:
	if _rings_gate_phase != RINGS_GATE_PHASE_OPENING \
			or not is_equal_approx(_rings_gate_deadline, expected_deadline):
		return
	_rings_gate_phase = RINGS_GATE_PHASE_OPEN
	_rings_gate_started_at = -1.0
	_rings_gate_deadline = -1.0
	if _route_phase != "complete":
		_route_phase = "handoff"
	_set_preview_step("mother_handoff_open")
	_show_note("The Rings membrane reaches its upper stop. The handoff is open.", 2.8)
	_update_timed_physical_presenters(_get_scheduler_tick())
	_apply_mother_topology()
	_update_extension_interactable_states()
	_update_extension_visuals()
	_update_overlay_label_states()
	_publish_mother_authority()

func _rearm_collapse_commit() -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or _collapse_phase != COLLAPSE_PHASE_SHIFTING:
		return
	var tag := _mother_callback_tag("collapse_shift")
	scheduler.cancel_tag(tag)
	scheduler.schedule_at(
		_collapse_shift_deadline,
		_commit_collapse_shift.bind(_collapse_shift_deadline),
		tag
	)

func _rearm_rings_gate_commit() -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or _rings_gate_phase != RINGS_GATE_PHASE_OPENING:
		return
	var tag := _mother_callback_tag("rings_gate")
	scheduler.cancel_tag(tag)
	scheduler.schedule_at(
		_rings_gate_deadline,
		_commit_rings_gate.bind(_rings_gate_deadline),
		tag
	)


func _root_move_tag(root_id: String) -> String:
	return _mother_callback_tag("root_settle:%s" % root_id)


func _rearm_root_move_commit(root_id: String) -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or not _roots.has(root_id):
		return
	var root: Dictionary = _roots[root_id]
	var target_anchor := int(root.get("target_anchor", -1))
	if target_anchor < 0:
		return
	var deadline := float(root.get("swarm_end", -1.0))
	var tag := _root_move_tag(root_id)
	scheduler.cancel_tag(tag)
	if deadline <= float(scheduler.get_current_tick()):
		_commit_root_move(root_id, target_anchor, deadline)
		return
	scheduler.schedule_at(
		deadline,
		_commit_root_move.bind(root_id, target_anchor, deadline),
		tag
	)


## The settled board anchor changes only when both the root and its delayed Sapscrap mat have
## reached the reserved destination. Until this exact saved deadline, `anchor` remains the
## departure truth and `target_anchor` is only a reservation used for collision checks.
func _commit_root_move(root_id: String, expected_anchor: int, expected_deadline: float) -> void:
	if not _roots.has(root_id):
		return
	var root: Dictionary = _roots[root_id]
	if int(root.get("target_anchor", -1)) != expected_anchor \
			or not is_equal_approx(float(root.get("swarm_end", -1.0)), expected_deadline):
		return
	if _get_scheduler_tick() + 0.000001 < expected_deadline:
		return
	root["anchor"] = expected_anchor
	root["target_anchor"] = -1
	_apply_root_pose(
		root_id,
		Vector3(root.get("anim_to_pos", _root_node(root).position)),
		Vector3(root.get("swarm_to_pos", _root_swarm_node(root).position))
	)
	_update_extension_interactable_states()
	_update_extension_visuals()
	_update_overlay_label_states()
	_publish_mother_authority()


func _cancel_mother_callbacks() -> void:
	var scheduler = _get_scheduler()
	if scheduler == null:
		return
	scheduler.cancel_tag(_mother_callback_tag("collapse_shift"))
	scheduler.cancel_tag(_mother_callback_tag("rings_gate"))
	scheduler.cancel_tag(_root_hazard_tag())
	for root_id in ROOT_ORDER:
		scheduler.cancel_tag(_root_move_tag(root_id))

func on_game_state_grid_ready() -> void:
	_apply_mother_topology()

func _grid_cells_for_blocker(center: Vector3, size: Vector3) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return result
	var grid = gs.grid
	var half := size * 0.5
	var min_cell: Vector2i = grid.world_to_grid(center - Vector3(half.x, 0.0, half.z))
	var max_cell: Vector2i = grid.world_to_grid(center + Vector3(half.x, 0.0, half.z))
	for z in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for x in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			if grid.is_in_bounds(x, z):
				result.append(Vector2i(x, z))
	return result

func _apply_grid_blocker(cells: Array[Vector2i], blocker_id: String, blocked: bool) -> void:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	var grid = gs.grid
	for cell in cells:
		var existing := str(grid.dynamic_blockers.get(cell, ""))
		if blocked:
			if existing == "" or existing == blocker_id:
				grid.add_dynamic_blocker(cell, blocker_id)
		elif existing == blocker_id:
			grid.remove_dynamic_blocker(cell)

func _apply_mother_topology() -> void:
	_apply_grid_blocker(
		_grid_cells_for_blocker(COLLAPSE_BLOCKER_CENTER, COLLAPSE_BLOCKER_SIZE),
		_mother_callback_tag("collapse_blocker"),
		_collapse_phase != COLLAPSE_PHASE_CLEARED
	)
	_apply_grid_blocker(
		_grid_cells_for_blocker(RINGS_GATE_BLOCKER_CENTER, RINGS_GATE_BLOCKER_SIZE),
		_mother_callback_tag("rings_gate_blocker"),
		_rings_gate_phase != RINGS_GATE_PHASE_OPEN
	)

func _encode_vec3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _decode_vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback

func _root_authority_state(root: Dictionary) -> Dictionary:
	return {
		"anchor": int(root.get("anchor", root.get("initial_anchor", 0))),
		"target_anchor": int(root.get("target_anchor", -1)),
		"anim_start": float(root.get("anim_start", 0.0)),
		"anim_end": float(root.get("anim_end", 0.0)),
		"swarm_start": float(root.get("swarm_start", 0.0)),
		"swarm_end": float(root.get("swarm_end", 0.0)),
		"anim_from_pos": _encode_vec3(Vector3(root.get("anim_from_pos", Vector3.ZERO))),
		"anim_to_pos": _encode_vec3(Vector3(root.get("anim_to_pos", Vector3.ZERO))),
		"swarm_from_pos": _encode_vec3(Vector3(root.get("swarm_from_pos", Vector3.ZERO))),
		"swarm_to_pos": _encode_vec3(Vector3(root.get("swarm_to_pos", Vector3.ZERO))),
	}

func _mother_authority_state() -> Dictionary:
	var root_states := {}
	for root_id in ROOT_ORDER:
		if _roots.has(root_id):
			root_states[root_id] = _root_authority_state(_roots[root_id])
	return {
		"version": MOTHER_AUTHORITY_VERSION,
		"owner": mother_authority_key(),
		"active_terminal": _active_terminal_id,
		"portal_open_until": _portal_open_until,
		"peris_remote_terminal": _peris_remote_terminal,
		"portal_transit_phase": _portal_transit_phase,
		"portal_transit_terminal": _portal_transit_terminal,
		"roots": root_states,
		"collapse_phase": _collapse_phase,
		"collapse_shift_started_at": _collapse_shift_started_at,
		"collapse_shift_deadline": _collapse_shift_deadline,
		"gear_item_id": _gear_item_id,
		"gear_installed": _gear_installed,
		"installed_repair_id": _installed_repair_id,
		"mother_tended": _mother_tended,
		"route_phase": _route_phase,
		"exit_reached": _exit_reached,
		"rings_gate_phase": _rings_gate_phase,
		"rings_gate_started_at": _rings_gate_started_at,
		"rings_gate_deadline": _rings_gate_deadline,
		"hazard_next_tick": _hazard_next_tick,
		"terminal_readings_seen": _terminal_readings_seen.duplicate(),
		"body_remaining": _body_remaining.duplicate(true),
		"body_source_item_ids": _body_source_item_ids.duplicate(true),
		"body_claimed_item_ids": _body_claimed_item_ids.duplicate(),
		"body_legacy_claimed": _body_legacy_claimed.duplicate(true),
		"body_claim_phase": _body_claim_phase,
		"body_claim_item_id": _body_claim_item_id,
		"body_claim_body_id": _body_claim_body_id,
		"body_claimed_by": _body_claimed_by,
		"body_claim_serial": _body_claim_serial,
		"repair_attempts": _repair_attempts.duplicate(),
	}

func _default_mother_authority_state() -> Dictionary:
	var root_states := {}
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		var root: Dictionary = _roots[root_id]
		var anchor := int(root.get("initial_anchor", 0))
		var root_pos := _root_world_center(root, anchor)
		var swarm_pos := root_pos + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0)
		root_states[root_id] = {
			"anchor": anchor,
			"target_anchor": -1,
			"anim_start": 0.0,
			"anim_end": 0.0,
			"swarm_start": 0.0,
			"swarm_end": 0.0,
			"anim_from_pos": _encode_vec3(root_pos),
			"anim_to_pos": _encode_vec3(root_pos),
			"swarm_from_pos": _encode_vec3(swarm_pos),
			"swarm_to_pos": _encode_vec3(swarm_pos),
		}
	var bodies := {}
	var legacy_claimed := {}
	for body_id in BODY_POSITIONS.keys():
		bodies[body_id] = BODY_YIELD_PER_CORPSE
		legacy_claimed[body_id] = 0
	return {
		"version": MOTHER_AUTHORITY_VERSION,
		"owner": mother_authority_key(),
		"active_terminal": "",
		"portal_open_until": 0.0,
		"peris_remote_terminal": "",
		"portal_transit_phase": PORTAL_TRANSIT_IDLE,
		"portal_transit_terminal": "",
		"roots": root_states,
		"collapse_phase": COLLAPSE_PHASE_BLOCKED,
		"collapse_shift_started_at": -1.0,
		"collapse_shift_deadline": -1.0,
		"gear_item_id": _find_mother_gear_item_id(),
		"gear_installed": false,
		"installed_repair_id": "",
		"mother_tended": false,
		"route_phase": "investigate",
		"exit_reached": false,
		"rings_gate_phase": RINGS_GATE_PHASE_SEALED,
		"rings_gate_started_at": -1.0,
		"rings_gate_deadline": -1.0,
		"hazard_next_tick": _get_scheduler_tick() + ROOT_HAZARD_INTERVAL,
		"terminal_readings_seen": [],
		"body_remaining": bodies,
		"body_source_item_ids": _body_source_item_ids.duplicate(true),
		"body_claimed_item_ids": [],
		"body_legacy_claimed": legacy_claimed,
		"body_claim_phase": BODY_CLAIM_IDLE,
		"body_claim_item_id": "",
		"body_claim_body_id": "",
		"body_claimed_by": "",
		"body_claim_serial": 0,
		"repair_attempts": [],
	}

func _valid_saved_body_authority(saved: Dictionary) -> bool:
	var source_v: Variant = saved.get("body_source_item_ids", null)
	var claimed_v: Variant = saved.get("body_claimed_item_ids", null)
	var legacy_v: Variant = saved.get("body_legacy_claimed", null)
	var remaining_v: Variant = saved.get("body_remaining", null)
	if not source_v is Dictionary or not claimed_v is Array \
			or not legacy_v is Dictionary or not remaining_v is Dictionary:
		return false
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return false
	var sources := source_v as Dictionary
	var claimed := claimed_v as Array
	var legacy := legacy_v as Dictionary
	var remaining := remaining_v as Dictionary
	var unique_sources := {}
	var source_body := {}
	for body_id_v in BODY_POSITIONS.keys():
		var body_id := str(body_id_v)
		var ids_v: Variant = sources.get(body_id, null)
		var legacy_count := int(legacy.get(body_id, -1))
		if not ids_v is Array or legacy_count < 0 or legacy_count > BODY_YIELD_PER_CORPSE:
			return false
		var ids := ids_v as Array
		if ids.size() + legacy_count != BODY_YIELD_PER_CORPSE:
			return false
		var ordinals := {}
		for item_id_v in ids:
			var item_id := str(item_id_v)
			if item_id == "" or unique_sources.has(item_id):
				return false
			unique_sources[item_id] = true
			source_body[item_id] = body_id
			if not gs.items.has(item_id):
				continue # A claimed unit may already have been digested.
			if not _is_valid_mother_body_source(item_id):
				return false
			var properties: Dictionary = _get_item_state(item_id).get("properties", {})
			var ordinal := int(properties.get("mother_body_ordinal", 0))
			if str(properties.get("mother_body_id", "")) != body_id or ordinals.has(ordinal):
				return false
			ordinals[ordinal] = true

	var unique_claimed := {}
	for item_id_v in claimed:
		var item_id := str(item_id_v)
		if item_id == "" or unique_claimed.has(item_id) or not unique_sources.has(item_id):
			return false
		unique_claimed[item_id] = true
	for body_id_v in BODY_POSITIONS.keys():
		var body_id := str(body_id_v)
		var ids := sources.get(body_id, []) as Array
		var claimed_here := 0
		for item_id_v in ids:
			var item_id := str(item_id_v)
			if unique_claimed.has(item_id):
				claimed_here += 1
			elif not gs.items.has(item_id) or not _body_item_at_source(item_id):
				return false
		if int(remaining.get(body_id, -1)) != ids.size() - claimed_here:
			return false
	# A tagged ninth unit is not decorative: it is duplicate spendable inventory and invalidates the
	# whole finite-source record.
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		if _is_tagged_mother_body_lysate(item_id) and not unique_sources.has(item_id):
			return false

	var claim_phase := str(saved.get("body_claim_phase", ""))
	var claim_item_id := str(saved.get("body_claim_item_id", ""))
	var claim_body_id := str(saved.get("body_claim_body_id", ""))
	var claimed_by := str(saved.get("body_claimed_by", ""))
	var claim_serial := int(saved.get("body_claim_serial", -1))
	if claim_serial < 0 or claim_phase not in [BODY_CLAIM_IDLE, BODY_CLAIMING]:
		return false
	if claim_phase == BODY_CLAIM_IDLE:
		return claim_item_id == "" and claim_body_id == "" and claimed_by == ""
	return claim_serial >= 1 and unique_claimed.has(claim_item_id) \
		and str(source_body.get(claim_item_id, "")) == claim_body_id \
		and BODY_POSITIONS.has(claim_body_id) and claimed_by in CANONICAL_PARTY

func _valid_mother_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	var saved_version := int(saved.get("version", 0))
	if saved_version not in [1, 2, 3, 4, MOTHER_AUTHORITY_VERSION] \
			or str(saved.get("owner", "")) != mother_authority_key():
		return false
	if not saved.get("roots", null) is Dictionary \
			or not saved.get("body_remaining", null) is Dictionary \
			or not saved.get("terminal_readings_seen", null) is Array \
			or not saved.get("repair_attempts", null) is Array:
		return false
	if saved_version >= 2:
		var saved_roots := saved.get("roots", {}) as Dictionary
		for root_id in ROOT_ORDER:
			if not saved_roots.get(root_id, null) is Dictionary or not _roots.has(root_id):
				return false
			var root_saved := saved_roots[root_id] as Dictionary
			var root: Dictionary = _roots[root_id]
			var anchor := int(root_saved.get("anchor", -1))
			var target_anchor := int(root_saved.get("target_anchor", -1))
			var min_anchor := int(root.get("min_anchor", 0))
			var max_anchor := int(root.get("max_anchor", 0))
			if anchor < min_anchor or anchor > max_anchor \
					or target_anchor < -1 or target_anchor > max_anchor:
				return false
			if target_anchor >= 0 and (
					target_anchor < min_anchor or target_anchor == anchor
					or float(root_saved.get("anim_end", -1.0)) <= float(root_saved.get("anim_start", 0.0))
					or float(root_saved.get("swarm_end", -1.0)) <= float(root_saved.get("anim_end", 0.0))
			):
				return false
	if saved_version >= 3:
		var transit_phase := str(saved.get("portal_transit_phase", ""))
		var transit_terminal := str(saved.get("portal_transit_terminal", ""))
		var remote_terminal := str(saved.get("peris_remote_terminal", ""))
		if transit_phase not in [
			PORTAL_TRANSIT_IDLE, PORTAL_TRANSIT_OUTBOUND, PORTAL_TRANSIT_RETURNING
		]:
			return false
		if transit_phase == PORTAL_TRANSIT_IDLE:
			if transit_terminal != "":
				return false
		elif transit_terminal not in TERMINAL_ORDER:
			return false
		elif transit_phase == PORTAL_TRANSIT_OUTBOUND and remote_terminal != "":
			return false
		elif transit_phase == PORTAL_TRANSIT_RETURNING and remote_terminal != transit_terminal:
			return false
	var collapse_phase := str(saved.get("collapse_phase", ""))
	if collapse_phase not in [
		COLLAPSE_PHASE_BLOCKED, COLLAPSE_PHASE_SHIFTING, COLLAPSE_PHASE_CLEARED
	]:
		return false
	if collapse_phase == COLLAPSE_PHASE_SHIFTING:
		var collapse_start := float(saved.get("collapse_shift_started_at", -1.0))
		var collapse_deadline := float(saved.get("collapse_shift_deadline", -1.0))
		if collapse_start < 0.0 or collapse_deadline <= collapse_start:
			return false
	var gate_phase := str(saved.get("rings_gate_phase", ""))
	if gate_phase not in [
		RINGS_GATE_PHASE_SEALED, RINGS_GATE_PHASE_OPENING, RINGS_GATE_PHASE_OPEN
	]:
		return false
	if gate_phase == RINGS_GATE_PHASE_OPENING:
		var gate_start := float(saved.get("rings_gate_started_at", -1.0))
		var gate_deadline := float(saved.get("rings_gate_deadline", -1.0))
		if gate_start < 0.0 or gate_deadline <= gate_start:
			return false
	var gear_installed := bool(saved.get("gear_installed", false))
	var installed_repair := str(saved.get("installed_repair_id", ""))
	if gear_installed != (installed_repair == CORRECT_REPAIR_ID):
		return false
	var mother_tended := bool(saved.get("mother_tended", false))
	if saved_version >= 4:
		var hazard_next_tick := float(saved.get("hazard_next_tick", -1.0))
		if (mother_tended and hazard_next_tick >= 0.0) \
				or (not mother_tended and hazard_next_tick < 0.0):
			return false
	if saved_version >= 5 and not _valid_saved_body_authority(saved):
		return false
	var route_phase := str(saved.get("route_phase", ""))
	var exit_reached := bool(saved.get("exit_reached", false))
	if route_phase not in ["investigate", "opening", "handoff", "complete"]:
		return false
	if not mother_tended:
		return gate_phase == RINGS_GATE_PHASE_SEALED \
			and route_phase == "investigate" and not exit_reached
	if not gear_installed:
		return false
	if gate_phase == RINGS_GATE_PHASE_OPENING:
		return route_phase == "opening" and not exit_reached
	if gate_phase == RINGS_GATE_PHASE_OPEN:
		return route_phase in ["handoff", "complete"] \
			and exit_reached == (route_phase == "complete")
	return false

func _initialize_mother_authority() -> void:
	_ensure_mother_game_state_signals()
	if _mother_authority_initialized:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_world_state"):
		return
	_mother_authority_initialized = true
	var raw: Variant = gs.get_world_state(mother_authority_key(), null)
	_mother_authority_baseline = _default_mother_authority_state().duplicate(true)
	if _valid_mother_authority(raw):
		_restore_mother_authority(raw as Dictionary)
		return
	_spawn_fresh_body_sources()
	_gear_item_id = _find_mother_gear_item_id()
	if _gear_item_id == "":
		_spawn_gear(GEAR_POS)
	_start_root_hazard_cadence()
	_mother_authority_baseline = _mother_authority_state().duplicate(true)
	_apply_mother_presenters()
	_publish_mother_authority()

func _ensure_mother_game_state_signals() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	if is_instance_valid(_mother_signal_game_state) and _mother_signal_game_state != gs:
		_disconnect_mother_game_state_signals()
	_mother_signal_game_state = gs
	var finished := Callable(self, "_on_mother_external_traversal_finished")
	var cancelled := Callable(self, "_on_mother_external_traversal_cancelled")
	if gs.has_signal("external_traversal_finished") \
			and not gs.is_connected("external_traversal_finished", finished):
		gs.connect("external_traversal_finished", finished)
	if gs.has_signal("external_traversal_cancelled") \
			and not gs.is_connected("external_traversal_cancelled", cancelled):
		gs.connect("external_traversal_cancelled", cancelled)

func _disconnect_mother_game_state_signals() -> void:
	if not is_instance_valid(_mother_signal_game_state):
		_mother_signal_game_state = null
		return
	var finished := Callable(self, "_on_mother_external_traversal_finished")
	var cancelled := Callable(self, "_on_mother_external_traversal_cancelled")
	if _mother_signal_game_state.is_connected("external_traversal_finished", finished):
		_mother_signal_game_state.disconnect("external_traversal_finished", finished)
	if _mother_signal_game_state.is_connected("external_traversal_cancelled", cancelled):
		_mother_signal_game_state.disconnect("external_traversal_cancelled", cancelled)
	_mother_signal_game_state = null

func _publish_mother_authority() -> void:
	if _restoring_mother_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(mother_authority_key(), _mother_authority_state())

func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_ensure_mother_game_state_signals()
	_cancel_mother_callbacks()
	_mother_authority_initialized = true
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(mother_authority_key(), null) \
		if gs != null and gs.has_method("get_world_state") else null
	if not _valid_mother_authority(raw):
		# Missing/malformed authority is the pre-interaction construction state. Remove any discarded
		# future's tagged units and expose eight new finite source identities at the four bodies; never
		# restore a claimed unit directly into somebody's hand.
		_spawn_fresh_body_sources()
		var baseline := (
			_mother_authority_baseline.duplicate(true)
			if not _mother_authority_baseline.is_empty()
			else _default_mother_authority_state()
		)
		baseline["body_remaining"] = _body_remaining.duplicate(true)
		baseline["body_source_item_ids"] = _body_source_item_ids.duplicate(true)
		baseline["body_claimed_item_ids"] = []
		baseline["body_legacy_claimed"] = _body_legacy_claimed.duplicate(true)
		baseline["body_claim_phase"] = BODY_CLAIM_IDLE
		baseline["body_claim_item_id"] = ""
		baseline["body_claim_body_id"] = ""
		baseline["body_claimed_by"] = ""
		baseline["body_claim_serial"] = 0
		var loose_gear_id := _find_mother_gear_item_id()
		if loose_gear_id != "":
			baseline["gear_item_id"] = loose_gear_id
		_restore_mother_authority(baseline)
		return
	_restore_mother_authority(raw as Dictionary)

func _restore_mother_authority(saved: Dictionary) -> void:
	_restoring_mother_authority = true
	_cancel_mother_callbacks()
	_active_terminal_id = str(saved.get("active_terminal", ""))
	_portal_open_until = float(saved.get("portal_open_until", 0.0))
	_peris_remote_terminal = str(saved.get("peris_remote_terminal", ""))
	var saved_version := int(saved.get("version", 1))
	_portal_transit_phase = str(saved.get("portal_transit_phase", PORTAL_TRANSIT_IDLE)) \
		if saved_version >= 3 else PORTAL_TRANSIT_IDLE
	_portal_transit_terminal = str(saved.get("portal_transit_terminal", "")) \
		if saved_version >= 3 else ""
	var restore_tick := _get_scheduler_tick()
	var normalized_mother_authority := saved_version < MOTHER_AUTHORITY_VERSION
	var saved_roots: Dictionary = saved.get("roots", {})
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		var root: Dictionary = _roots[root_id]
		var root_saved: Dictionary = saved_roots.get(root_id, {})
		var default_anchor := int(root.get("initial_anchor", 0))
		var saved_anchor := clampi(
			int(root_saved.get("anchor", default_anchor)),
			int(root.get("min_anchor", default_anchor)),
			int(root.get("max_anchor", default_anchor))
		)
		var saved_swarm_end := float(root_saved.get("swarm_end", 0.0))
		var saved_from_pos := _decode_vec3(
			root_saved.get("anim_from_pos", null), _root_world_center(root, saved_anchor)
		)
		var anchor := saved_anchor
		var target_anchor := -1
		if saved_version >= 2:
			var raw_target := int(root_saved.get("target_anchor", -1))
			if raw_target >= 0:
				target_anchor = clampi(
					raw_target,
					int(root.get("min_anchor", default_anchor)),
					int(root.get("max_anchor", default_anchor))
				)
		else:
			# Version 1 wrote the reserved destination into `anchor` immediately.
			# Recover the actual settled departure from the saved physical start pose.
			if saved_swarm_end > restore_tick:
				target_anchor = saved_anchor
				anchor = _root_anchor_for_world_center(root, saved_from_pos)
		if target_anchor >= 0 and saved_swarm_end <= restore_tick:
			anchor = target_anchor
			target_anchor = -1
			normalized_mother_authority = true
		var default_root_pos := _root_world_center(root, anchor)
		var default_swarm_pos := default_root_pos + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0)
		root["anchor"] = anchor
		root["target_anchor"] = target_anchor
		root["anim_start"] = float(root_saved.get("anim_start", 0.0))
		root["anim_end"] = float(root_saved.get("anim_end", 0.0))
		root["swarm_start"] = float(root_saved.get("swarm_start", 0.0))
		root["swarm_end"] = saved_swarm_end
		root["anim_from_pos"] = saved_from_pos
		root["anim_to_pos"] = _decode_vec3(root_saved.get("anim_to_pos", null), default_root_pos)
		root["swarm_from_pos"] = _decode_vec3(root_saved.get("swarm_from_pos", null), default_swarm_pos)
		root["swarm_to_pos"] = _decode_vec3(root_saved.get("swarm_to_pos", null), default_swarm_pos)
	_collapse_phase = str(saved.get("collapse_phase", COLLAPSE_PHASE_BLOCKED))
	_collapse_cleared = _collapse_phase == COLLAPSE_PHASE_CLEARED
	_collapse_shift_started_at = float(saved.get("collapse_shift_started_at", -1.0)) \
		if _collapse_phase == COLLAPSE_PHASE_SHIFTING else -1.0
	_collapse_shift_deadline = float(saved.get("collapse_shift_deadline", -1.0)) \
		if _collapse_phase == COLLAPSE_PHASE_SHIFTING else -1.0
	_gear_item_id = str(saved.get("gear_item_id", ""))
	_gear_installed = bool(saved.get("gear_installed", false))
	_installed_repair_id = str(saved.get("installed_repair_id", ""))
	if not _gear_installed and _get_item_state(_gear_item_id).is_empty():
		_gear_item_id = _find_mother_gear_item_id()
	_mother_tended = bool(saved.get("mother_tended", false))
	_route_phase = str(saved.get("route_phase", "investigate"))
	_exit_reached = bool(saved.get("exit_reached", false))
	_rings_gate_phase = str(saved.get("rings_gate_phase", RINGS_GATE_PHASE_SEALED))
	_rings_gate_started_at = float(saved.get("rings_gate_started_at", -1.0)) \
		if _rings_gate_phase == RINGS_GATE_PHASE_OPENING else -1.0
	_rings_gate_deadline = float(saved.get("rings_gate_deadline", -1.0)) \
		if _rings_gate_phase == RINGS_GATE_PHASE_OPENING else -1.0
	_hazard_next_tick = (
		float(saved.get("hazard_next_tick", -1.0))
		if saved_version >= 4
		else (restore_tick + ROOT_HAZARD_INTERVAL if not _mother_tended else -1.0)
	)
	_terminal_readings_seen.clear()
	for terminal_id_v in saved.get("terminal_readings_seen", []) as Array:
		var terminal_id := str(terminal_id_v)
		if terminal_id in TERMINAL_ORDER and not _terminal_readings_seen.has(terminal_id):
			_terminal_readings_seen.append(terminal_id)
	var saved_bodies: Dictionary = saved.get("body_remaining", {})
	if saved_version >= 5:
		_body_source_item_ids.clear()
		var saved_sources: Dictionary = saved.get("body_source_item_ids", {})
		for body_id_v in BODY_POSITIONS.keys():
			var body_id := str(body_id_v)
			var ids: Array[String] = []
			for item_id_v in saved_sources.get(body_id, []) as Array:
				ids.append(str(item_id_v))
			_body_source_item_ids[body_id] = ids
		_body_claimed_item_ids.clear()
		for item_id_v in saved.get("body_claimed_item_ids", []) as Array:
			_body_claimed_item_ids.append(str(item_id_v))
		_body_legacy_claimed.clear()
		var saved_legacy: Dictionary = saved.get("body_legacy_claimed", {})
		for body_id_v in BODY_POSITIONS.keys():
			var body_id := str(body_id_v)
			_body_legacy_claimed[body_id] = clampi(
				int(saved_legacy.get(body_id, 0)), 0, BODY_YIELD_PER_CORPSE
			)
		_body_claim_phase = str(saved.get("body_claim_phase", BODY_CLAIM_IDLE))
		_body_claim_item_id = str(saved.get("body_claim_item_id", ""))
		_body_claim_body_id = str(saved.get("body_claim_body_id", ""))
		_body_claimed_by = str(saved.get("body_claimed_by", ""))
		_body_claim_serial = maxi(0, int(saved.get("body_claim_serial", 0)))
		_sync_body_remaining_from_sources()
		if _reconcile_restored_body_claim():
			normalized_mother_authority = true
	else:
		_migrate_legacy_body_sources(saved_bodies)
		normalized_mother_authority = true
	_repair_attempts.clear()
	for repair_id_v in saved.get("repair_attempts", []) as Array:
		var repair_id := str(repair_id_v)
		if repair_id in REPAIR_POINT_ORDER and not _repair_attempts.has(repair_id):
			_repair_attempts.append(repair_id)
	if _reconcile_restored_portal_transit():
		normalized_mother_authority = true
	_normalize_mother_source_receipt_registry()
	_update_root_animation(_get_scheduler_tick())
	_update_terminal_visuals()
	_update_portal_visuals()
	_update_body_visuals()
	_update_mother_visuals()
	_update_extension_visuals()
	_update_overlay_label_states()
	_update_gear_interactable_position()
	_update_timed_physical_presenters(_get_scheduler_tick())
	_apply_mother_topology()
	_update_extension_interactable_states()
	_restoring_mother_authority = false
	if _collapse_phase == COLLAPSE_PHASE_SHIFTING:
		_rearm_collapse_commit()
	if _rings_gate_phase == RINGS_GATE_PHASE_OPENING:
		_rearm_rings_gate_commit()
	for root_id in ROOT_ORDER:
		if _roots.has(root_id) and _root_move_in_flight(_roots[root_id]):
			_rearm_root_move_commit(root_id)
	if not _mother_tended:
		_rearm_root_hazard_tick()
	if normalized_mother_authority:
		_publish_mother_authority()

func _portal_identity_from_state(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}
	var traversal_id := StringName(str(state.get("traversal_id", "")))
	for phase in [PORTAL_TRANSIT_OUTBOUND, PORTAL_TRANSIT_RETURNING]:
		for terminal_id in TERMINAL_ORDER:
			if traversal_id == _portal_traversal_id(phase, terminal_id):
				return {"phase": phase, "terminal": terminal_id}
	return {}

func _reconcile_restored_portal_transit() -> bool:
	var transit := _portal_transit_state()
	var live_identity := _portal_identity_from_state(transit)
	if not live_identity.is_empty():
		var live_phase := str(live_identity.get("phase", PORTAL_TRANSIT_IDLE))
		var live_terminal := str(live_identity.get("terminal", ""))
		var changed := _portal_transit_phase != live_phase \
			or _portal_transit_terminal != live_terminal
		_portal_transit_phase = live_phase
		_portal_transit_terminal = live_terminal
		# Settled ownership changes only in the traversal-finished transaction.
		if live_phase == PORTAL_TRANSIT_OUTBOUND and _peris_remote_terminal != "":
			_peris_remote_terminal = ""
			changed = true
		elif live_phase == PORTAL_TRANSIT_RETURNING \
				and _peris_remote_terminal != live_terminal:
			_peris_remote_terminal = live_terminal
			changed = true
		return changed

	if _portal_transit_phase == PORTAL_TRANSIT_IDLE:
		if _portal_transit_terminal == "":
			return false
		_portal_transit_terminal = ""
		return true

	# A save notification can land on either side of the GameState finish signal. If the body is
	# already at the reserved endpoint, finish the local ownership transaction; otherwise this was
	# the pre-command publication seam and grants no movement or endpoint access.
	var terminal_id := _portal_transit_terminal
	var peris_position := _get_character_position("peris")
	if _portal_transit_phase == PORTAL_TRANSIT_OUTBOUND \
			and terminal_id in TERMINAL_ORDER \
			and peris_position.distance_to(_terminal_service_spawn(terminal_id)) <= 0.05:
		_peris_remote_terminal = terminal_id
	elif _portal_transit_phase == PORTAL_TRANSIT_RETURNING \
			and peris_position.distance_to(BASE_PORTAL_POS + Vector3(2.6, 0.0, 0.0)) <= 0.05:
		_peris_remote_terminal = ""
	_portal_transit_phase = PORTAL_TRANSIT_IDLE
	_portal_transit_terminal = ""
	return true

func _find_mother_gear_item_id() -> String:
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return ""
	var candidates: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		var item_v: Variant = gs.items.get(item_id_v, {})
		if item_v is Dictionary and str((item_v as Dictionary).get("type", "")) == "mother_gear":
			candidates.append(item_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""

func _remove_loose_mother_gears() -> void:
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return
	var remove_ids: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_v: Variant = gs.items.get(item_id_v, {})
		if item_v is Dictionary and str((item_v as Dictionary).get("type", "")) == "mother_gear":
			remove_ids.append(str(item_id_v))
	for item_id in remove_ids:
		_remove_item(item_id)

func detach_chunk_host() -> void:
	_cancel_mother_callbacks()
	_disconnect_mother_game_state_signals()
	super.detach_chunk_host()

func _update_overlay_label_states() -> void:
	if _peris_overlay_labels.has("mother"):
		_peris_overlay_labels["mother"].text = "MOTHER: %s" % _mother_stress_label().to_upper()
	for root_id in ROOT_ORDER:
		if not _peris_overlay_labels.has(root_id) or not _roots.has(root_id):
			continue
		_peris_overlay_labels[root_id].text = "%s  %s" % [_fragment_label(root_id), _root_trace_state(root_id)]
	if _endo_overlay_materials.has("gear"):
		_endo_overlay_materials["gear"].emission_energy_multiplier = 0.12 if _gear_installed else 0.62
	if _endo_overlay_materials.has("bodies"):
		_endo_overlay_materials["bodies"].emission_energy_multiplier = 0.18 if _body_units_remaining() <= 0 else 0.7
	if _endo_overlay_materials.has("carry"):
		_endo_overlay_materials["carry"].emission_energy_multiplier = 0.82 if _is_socket_lane_open() else 0.18
	if _endo_overlay_materials.has("socket"):
		_endo_overlay_materials["socket"].emission_energy_multiplier = 0.84 if _is_socket_lane_open() else 0.24
	if _endo_overlay_materials.has("repair_center"):
		_endo_overlay_materials["repair_center"].emission_energy_multiplier = 0.96 if _gear_installed else (0.72 if _core_readings_converged() else 0.28)

func _add_overlay_label(parent: Node3D, text: String, position: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.pixel_size = 0.009
	label.font_size = 38
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.48)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

func _add_link_overlay(from: Vector3, to: Vector3, color: Color) -> void:
	var segment := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, maxf(from.distance_to(to), 0.12))
	segment.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.62
	segment.material_override = material
	segment.position = (from + to) * 0.5
	_aster_overlay_root.add_child(segment)
	segment.look_at(to, Vector3.UP, true)

func _add_layout_ghost(parent: Node3D, position: Vector3, size: Vector2, color: Color) -> void:
	var ghost := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.05, size.y)
	ghost.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.16)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.34
	ghost.material_override = material
	ghost.position = position
	parent.add_child(ghost)

func _add_endo_beacon(id: String, text: String, position: Vector3, color: Color) -> void:
	var beacon := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.24
	mesh.height = 0.48
	beacon.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.12)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.68
	beacon.material_override = material
	beacon.position = position
	_endo_overlay_root.add_child(beacon)
	_add_overlay_label(_endo_overlay_root, text, position + Vector3(0.0, 0.95, 0.0), color)
	_endo_overlay_materials[id] = material

func _repair_point_position(repair_id: String) -> Vector3:
	return Vector3(REPAIR_POINT_DEFS.get(repair_id, {}).get("position", INSTALL_SOCKET_POS))

func _repair_point_label(repair_id: String) -> String:
	return str(REPAIR_POINT_DEFS.get(repair_id, {}).get("label", repair_id.to_upper()))

func _spawn_gear(position: Vector3) -> void:
	if _gear_item_id != "":
		_remove_item(_gear_item_id)
	_gear_item_id = _spawn_item("mother_gear", position, {
		"display_name": "Mother Gear",
		"visual_kind": "mother_gear",
		"visual_scene": MOTHER_GEAR_VISUAL_SCENE.resource_path,
		"visual_identity": MOTHER_GEAR_VISUAL_IDENTITY,
		"visual_color": Color(0.84, 0.7, 0.44),
	})
	_update_gear_interactable_position()

func _update_gear_interactable_position() -> void:
	if _gear_interactable == null:
		return
	if _gear_installed or _gear_item_id == "":
		_gear_interactable.position = Vector3(2000.0, 0.2, 2000.0)
		return
	var state := _get_item_state(_gear_item_id)
	if str(state.get("location", "ground")) != "ground":
		_gear_interactable.position = Vector3(2000.0, 0.2, 2000.0)
		return
	var item_pos: Vector3 = state.get("position", GEAR_POS)
	_gear_interactable.position = item_pos + Vector3(0.0, 0.2, 0.0)

func _reject_wrong_repair(repair_id: String) -> void:
	var current_tick := _get_scheduler_tick()
	_installed_repair_id = ""
	_remove_item(_gear_item_id)
	_gear_item_id = ""
	_apply_wrong_repair_shift(repair_id, current_tick)
	var recovery_pos := HIDE_SPOT_POS + Vector3(1.4 * float(_repair_attempts.size()), 0.24, 0.0)
	_spawn_gear(recovery_pos)
	_set_preview_step("mother_%s_rejected" % repair_id)
	_show_note(str(REPAIR_POINT_DEFS[repair_id].get("flare_note", "The chamber rejects the mount and kicks the gear back into the alcove.")), 4.2)
	_update_mother_visuals()
	_update_extension_interactable_states()
	_update_extension_visuals()
	_update_overlay_label_states()
	_publish_mother_authority()

func _apply_wrong_repair_shift(repair_id: String, current_tick: float) -> void:
	if not REPAIR_POINT_DEFS.has(repair_id) or _get_scheduler() == null:
		return
	var root_id := str(REPAIR_POINT_DEFS[repair_id].get("flare_root", ""))
	var direction := int(REPAIR_POINT_DEFS[repair_id].get("flare_direction", 0))
	if root_id == "" or direction == 0 or not _roots.has(root_id):
		return
	var root: Dictionary = _roots[root_id]
	var target_anchor := clampi(
		int(root.get("anchor", 0)) + direction,
		int(root.get("min_anchor", 0)),
		int(root.get("max_anchor", 0))
	)
	if target_anchor == int(root.get("anchor", 0)):
		return
	if _blocking_root_for(root_id, target_anchor) != "":
		return
	root["target_anchor"] = target_anchor
	root["anim_start"] = current_tick
	root["anim_end"] = current_tick + ROOT_SLIDE_DURATION * 0.7
	root["swarm_start"] = float(root.get("anim_end", current_tick)) + ROOT_SWARM_LAG * 0.5
	root["swarm_end"] = float(root.get("swarm_start", current_tick)) + ROOT_SWARM_DURATION
	root["anim_from_pos"] = _root_node(root).position
	root["anim_to_pos"] = _root_world_center(root, target_anchor)
	root["swarm_from_pos"] = _root_swarm_node(root).position
	root["swarm_to_pos"] = Vector3(root.get("anim_to_pos", Vector3.ZERO)) + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0)
	_rearm_root_move_commit(root_id)

func _core_readings_converged() -> bool:
	return (
		"term_alpha" in _terminal_readings_seen
		and "term_beta" in _terminal_readings_seen
		and "term_gamma" in _terminal_readings_seen
	)

func _diagnosis_summary() -> String:
	if _mother_tended:
		return "resolved through the load regulator"
	if _gear_installed:
		return "load regulator mounted"
	if _core_readings_converged():
		return "core load jam; center spindle wants the gear"
	if "term_alpha" in _terminal_readings_seen and "term_beta" in _terminal_readings_seen:
		return "live load and stress both converge through the center"
	if "term_alpha" in _terminal_readings_seen:
		return "freight wear and live load converge through the center"
	if "term_beta" in _terminal_readings_seen:
		return "mother is stressed, but the edges look secondary"
	if "term_gamma" in _terminal_readings_seen:
		return "center socket matches the caretaker's gear gauge"
	return "partial read only"

func _aster_load_read() -> String:
	if _mother_tended:
		return "handoff open"
	if _core_readings_converged():
		return "center spindle still owns the freight load"
	if "term_alpha" in _terminal_readings_seen:
		return "live freight load converges toward the middle"
	return "live load map incomplete"

func _peris_fault_read() -> String:
	if _mother_tended:
		return "she's taking the weight cleanly again"
	if _gear_installed:
		return "the core is easing instead of flaring"
	if _core_readings_converged():
		return "the pain is pooled at her core; edge vents are only echoes"
	if "term_beta" in _terminal_readings_seen:
		return "the outer lanes hurt, but the knot is deeper"
	return "she feels stalled, not venting"

func _endo_repair_read() -> String:
	if _mother_tended:
		return "handoff complete"
	if _gear_installed:
		return _repair_point_label(_installed_repair_id).to_lower()
	if _core_readings_converged():
		return _repair_point_label(CORRECT_REPAIR_ID).to_lower()
	if "term_gamma" in _terminal_readings_seen:
		return "center socket matches the caretaker gauge"
	if _repair_attempts.is_empty():
		return "compare the mounts' wear"
	return "rejected: %s" % _repair_point_label(str(_repair_attempts[_repair_attempts.size() - 1])).to_lower()

func _terminal_position(terminal_id: String) -> Vector3:
	match terminal_id:
		"term_alpha": return TERM_ALPHA_POS
		"term_beta": return TERM_BETA_POS
		"term_gamma": return TERM_GAMMA_POS
		_: return Vector3.ZERO

func _terminal_service_position(terminal_id: String) -> Vector3:
	return Vector3(TERMINAL_SERVICE_POSITIONS.get(terminal_id, Vector3.ZERO))

func _terminal_service_spawn(terminal_id: String) -> Vector3:
	return _terminal_service_position(terminal_id) + REMOTE_SPAWN_OFFSET

func _terminal_service_label(terminal_id: String) -> String:
	match terminal_id:
		"term_alpha": return "north/east service bay"
		"term_beta": return "central service bay"
		"term_gamma": return "west/south service bay"
		_: return "service bay"

func _portal_label(terminal_id: String) -> String:
	match terminal_id:
		"term_alpha": return "PORTAL-12A"
		"term_beta": return "PORTAL-12B"
		"term_gamma": return "PORTAL-12C"
		_: return "PORTAL"

func _active_service_overlay_label() -> String:
	if _active_terminal_id == "" or not TERMINAL_SERVICES.has(_active_terminal_id):
		return "no braid selected"
	return _terminal_service_label(_active_terminal_id)

func _fragment_label(root_id: String) -> String:
	return str(_roots.get(root_id, {}).get("label", root_id.to_upper()))

func _display_name(char_id: String) -> String:
	match char_id:
		"aster": return "Aster"
		"peris": return "Peris"
		"endo": return "Endo"
		_: return char_id.capitalize()

func _root_node(root: Dictionary) -> MeshInstance3D:
	return root.get("node")

func _root_swarm_node(root: Dictionary) -> MeshInstance3D:
	return root.get("swarm_node")

func _root_world_center(root: Dictionary, anchor: int) -> Vector3:
	var orientation := str(root.get("orientation", "horizontal"))
	var length := int(root.get("length", 2))
	var fixed_line := int(root.get("fixed_line", 0))
	if orientation == "horizontal":
		return Vector3(BOARD_ORIGIN.x + (float(anchor) + float(length) * 0.5) * BOARD_CELL_SIZE, ROOT_CENTER_Y, BOARD_ORIGIN.z + (float(fixed_line) + 0.5) * BOARD_CELL_SIZE)
	return Vector3(BOARD_ORIGIN.x + (float(fixed_line) + 0.5) * BOARD_CELL_SIZE, ROOT_CENTER_Y, BOARD_ORIGIN.z + (float(anchor) + float(length) * 0.5) * BOARD_CELL_SIZE)

func _root_size(root: Dictionary) -> Vector3:
	var orientation := str(root.get("orientation", "horizontal"))
	var length := int(root.get("length", 2))
	if orientation == "horizontal":
		return Vector3(float(length) * BOARD_CELL_SIZE - ROOT_GAP, ROOT_WIDTH * 0.2, ROOT_WIDTH)
	return Vector3(ROOT_WIDTH, ROOT_WIDTH * 0.2, float(length) * BOARD_CELL_SIZE - ROOT_GAP)

func _root_swarm_size(root: Dictionary) -> Vector3:
	var size := _root_size(root)
	var orientation := str(root.get("orientation", "horizontal"))
	if orientation == "horizontal":
		return Vector3(size.x + ROOT_SWARM_EXTRA_LENGTH, 0.06, size.z + ROOT_SWARM_EXTRA_WIDTH)
	return Vector3(size.x + ROOT_SWARM_EXTRA_WIDTH, 0.06, size.z + ROOT_SWARM_EXTRA_LENGTH)

func _service_row_position(terminal_id: String, index: int, count: int) -> Vector3:
	var base_pos := _terminal_service_position(terminal_id)
	return base_pos + Vector3(0.0, 0.0, (float(index) - float(count - 1) * 0.5) * 3.6)

func _bud_label(direction: int) -> String:
	return "LEFT BUD" if direction < 0 else "RIGHT BUD"

func _default_move_direction(root_id: String) -> int:
	if not _roots.has(root_id):
		return 0
	var root: Dictionary = _roots[root_id]
	var anchor := int(root.get("anchor", 0))
	var initial_anchor := int(root.get("initial_anchor", anchor))
	if anchor <= initial_anchor and anchor < int(root.get("max_anchor", anchor)):
		return 1
	if anchor > int(root.get("min_anchor", anchor)):
		return -1
	return 0

func _update_root_world_label(root: Dictionary) -> void:
	var world_label: Label3D = root.get("world_label")
	if world_label != null:
		world_label.position = _root_node(root).position + Vector3(0.0, 1.85, 0.0)

func _apply_root_pose(root_id: String, root_pos: Vector3, swarm_pos: Vector3) -> void:
	if not _roots.has(root_id):
		return
	_root_node(_roots[root_id]).position = root_pos
	_root_swarm_node(_roots[root_id]).position = swarm_pos
	_update_root_world_label(_roots[root_id])

func _root_cells(root: Dictionary) -> Array[Vector2i]:
	return _root_cells_for_anchor(root, int(root.get("anchor", 0)))

func _root_cells_for_anchor(root: Dictionary, anchor: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var length := int(root.get("length", 2))
	var fixed_line := int(root.get("fixed_line", 0))
	if str(root.get("orientation", "horizontal")) == "horizontal":
		for step in range(length):
			cells.append(Vector2i(anchor + step, fixed_line))
	else:
		for step in range(length):
			cells.append(Vector2i(fixed_line, anchor + step))
	return cells

func _cell_name(cell: Vector2i) -> String:
	return "%s%d" % [BOARD_ROWS[cell.y], cell.x + 1]

func _mother_stress_label() -> String:
	if _mother_tended:
		return "blooming"
	if _gear_installed:
		return "easing"
	if not _repair_attempts.is_empty():
		return "flaring"
	return "stalled"

func _peris_board_read() -> String:
	if _mother_tended or _is_mother_lane_clear():
		return "open toward the mother"
	if _gear_installed:
		return "east side thinning"
	if not _repair_attempts.is_empty():
		return "core still misread"
	if _is_socket_lane_open():
		return "center line breathing"
	if _is_gear_pocket_open():
		return "west pocket exposed"
	return "still knotted"

func _peris_memory_blur_read() -> String:
	if _collapse_cleared and _body_units_remaining() <= 0:
		return "fading from the collapse wing"
	if _collapse_cleared:
		return "clustering near the collapse wing"
	return "distant and intermittent"

func _root_trace_state(root_id: String) -> String:
	if not _roots.has(root_id):
		return ""
	var root: Dictionary = _roots[root_id]
	if _root_move_in_flight(root):
		return "SHIVERING"
	var anchor := int(root.get("anchor", 0))
	var initial_anchor := int(root.get("initial_anchor", anchor))
	var min_anchor := int(root.get("min_anchor", anchor))
	var max_anchor := int(root.get("max_anchor", anchor))
	if anchor == initial_anchor:
		return "FAMILIAR"
	if anchor == min_anchor or anchor == max_anchor:
		return "STRAINED"
	return "DISTURBED"

func _blocking_root_for(root_id: String, target_anchor: int) -> String:
	if not _roots.has(root_id):
		return ""
	var target_cells := _root_cells_for_anchor(_roots[root_id], target_anchor)
	for other_id in ROOT_ORDER:
		if other_id == root_id or not _roots.has(other_id):
			continue
		for target_cell in target_cells:
			if _root_reserved_cells(_roots[other_id]).has(target_cell):
				return other_id
	return ""

func _character_in_any_hazard(char_pos: Vector3) -> bool:
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		var root: Dictionary = _roots[root_id]
		if _point_in_hazard_band(char_pos, _root_node(root).position, Vector3(root.get("size", Vector3.ONE)) + Vector3(0.4, 0.0, 0.4)):
			return true
		if _point_in_hazard_band(char_pos, _root_swarm_node(root).position, Vector3(root.get("swarm_size", Vector3.ONE)) + Vector3(0.5, 0.0, 0.5)):
			return true
	return false

func _point_in_hazard_band(point: Vector3, center: Vector3, size: Vector3) -> bool:
	return absf(point.x - center.x) <= size.x * 0.5 and absf(point.z - center.z) <= size.z * 0.5

func _is_portal_open(current_tick: float) -> bool:
	return _active_terminal_id != "" and current_tick <= _portal_open_until

func _body_units_remaining() -> int:
	var total := 0
	for remaining in _body_remaining.values():
		total += int(remaining)
	return total

func _has_free_hand_slots(char_id: String, required_slots: int) -> bool:
	var free_count := 0
	for slot in _get_hand_slots(char_id):
		if slot == null:
			free_count += 1
			if free_count >= required_slots:
				return true
	return false

func _endo_holds_gear() -> bool:
	if _gear_item_id == "":
		return false
	var state := _get_item_state(_gear_item_id)
	return str(state.get("holder", "")) == "endo" and str(state.get("location", "")) == "hand"

func _lane_cells_clear(row: int, start_col: int, end_col: int) -> bool:
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		var root: Dictionary = _roots[root_id]
		# During transit, `anchor` remains the settled departure and `target_anchor`
		# reserves the destination. Both are blocked until the saved arrival commits.
		var occupied_cells := _root_reserved_cells(root)
		for cell in occupied_cells:
			if cell.y == row and cell.x >= start_col and cell.x <= end_col:
				return false
	return true

func _is_gear_pocket_open() -> bool:
	var gear_latch: Dictionary = _roots.get("gear_latch", {})
	var socket_brace: Dictionary = _roots.get("socket_brace", {})
	return not _root_move_in_flight(gear_latch) \
		and not _root_move_in_flight(socket_brace) \
		and int(gear_latch.get("anchor", 0)) >= 1 \
		and int(socket_brace.get("anchor", 2)) >= 3

func _is_socket_lane_open() -> bool:
	return _lane_cells_clear(2, 0, 3)

func _is_mother_lane_clear() -> bool:
	return _lane_cells_clear(2, 0, 5)

func _root_move_in_flight(root: Dictionary) -> bool:
	if root.is_empty():
		return false
	# The scheduler callback, not render time, clears the reservation. Keeping this
	# true if a callback is ever missing fails closed instead of granting an endpoint.
	return int(root.get("target_anchor", -1)) >= 0

func _root_reserved_cells(root: Dictionary) -> Array[Vector2i]:
	var cells := _root_cells(root)
	var target_anchor := int(root.get("target_anchor", -1))
	if target_anchor < 0:
		return cells
	for target_cell in _root_cells_for_anchor(root, target_anchor):
		if not cells.has(target_cell):
			cells.append(target_cell)
	return cells

func _root_anchor_for_world_center(root: Dictionary, world_center: Vector3) -> int:
	var length := int(root.get("length", 2))
	var continuous_anchor := (
		(world_center.x - BOARD_ORIGIN.x) / BOARD_CELL_SIZE - float(length) * 0.5
		if str(root.get("orientation", "horizontal")) == "horizontal"
		else (world_center.z - BOARD_ORIGIN.z) / BOARD_CELL_SIZE - float(length) * 0.5
	)
	return clampi(
		roundi(continuous_anchor),
		int(root.get("min_anchor", roundi(continuous_anchor))),
		int(root.get("max_anchor", roundi(continuous_anchor)))
	)
