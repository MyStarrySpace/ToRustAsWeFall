@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

## Peris simulation tutorial: run, stamina, Protect, and Monos.

@export_range(1, 2) var start_phase := 0
static var _visit_phase := 1

const PLACEMENT_ROOT := "ScenePlacement"
const ROOM_OCCUPANTS := [
	"Portal", "Kiosk", "CoffeeTable", "Bookshelf", "bench", "couch",
]
const REQUIRED_AUTHORED_ROOM_NODES := [
	"RoomShell", "RoomFurniture", "bench", "couch", "Portal", "Kiosk", "Armchair",
	"CoffeeTable", "Bookshelf", "Rug", "WallArtFrame", "WallArt", "WateringCan",
	"WellnessTerminal", "StrikeNotice", "CareLogbookConsole", "CareFieldKit",
	"Plant1Table", "Plant1", "Plant2Table", "Plant2", "Plant3Table", "Plant3",
	"Plant4Table", "Plant4", "Plant5Table", "Plant5", "Plant6Table", "Plant6",
	"Plant7Table", "Plant7", "Plant8Table", "Plant8", "Plant9Table", "Plant9",
	"Plant1Hanger", "Plant6Hanger",
]
const REQUIRED_ROOM_MARKERS := [
	"PortalAnchor", "KioskAnchor", "ArmchairAnchor",
	"CoffeeTableAnchor", "BookshelfAnchor", "BenchAnchor",
	"RugAnchor", "WallArtAnchor", "PerisStart", "MonosStart", "PortalStand",
	"WateringCanAnchor",
	"PaintingZoneMarker", "WellnessZoneMarker", "StrikeWarningZoneMarker",
	"LogbookConsoleAnchor", "LogbookGateMarker",
	"WellnessTerminalAnchor", "StrikeNoticeAnchor",
	"PaintingApproach", "WellnessApproach", "StrikeWarningApproach",
	"Plant1TableAnchor", "Plant2TableAnchor", "Plant3TableAnchor",
	"Plant4TableAnchor", "Plant5TableAnchor", "Plant6TableAnchor",
	"Plant7TableAnchor", "Plant8TableAnchor", "Plant9TableAnchor",
	"Plant1Approach", "Plant2Approach", "Plant3Approach",
	"Plant4Approach", "Plant5Approach", "Plant6Approach",
	"Plant7Approach", "Plant8Approach", "Plant9Approach",
]
const ROOM_GRID_STEP := 0.5
# Wall-mounted assets still snap along the floor-plan axis, while their other
# coordinate is the shallow inset needed to keep the mesh clear of the wall.
const WALL_MOUNTED_GRID_AXES := {
	"WallArtAnchor": "x",
	"WellnessTerminalAnchor": "z",
	"StrikeNoticeAnchor": "z",
}

var _has_sprinted := false
var _has_protected := false
var _protect_queued := false
var _protect_end_tick := 0.0

var _monos
var _portal_visual: MeshInstance3D
var _portal_light: OmniLight3D
var _attack_particles: OmniLight3D
var _sanction_feed_label: Label3D
var _portal_tween_active := false
# Portal-view: a SubViewport with its own World3D renders the connected room (where Monos stands) onto the
# whole circular Portal_Surface disc. The viewport camera mirrors the live camera through the portal
# each frame (rendering-only), so the disc reads as a real opening with parallax.
var _portal_view_vp: SubViewport
var _portal_view_surface: MeshInstance3D
var _portal_view_cam: Camera3D
const PORTAL_LENS_SHADER := preload("res://resources/portal_lens.gdshader")
# Where the portal opening stands in the Monos room's own world: centre height matches the
# Peris-side portal centre, so the two rooms line up like a doorway.
const MONOS_ROOM_PORTAL_ANCHOR := Vector3(0.0, 2.5, 0.0)
var _hud  # GameHUD

# Watering beat (phase 1): the hand-inventory tutorial. Peris waters the Boston fern (Plant7) out of
# HABIT — her plants are engineered to stay green, so it's a ritual, not survival (no drying). A
# watering can sits on the bookshelf as a real GameState ITEM: pick it up (hand slot fills, HUD shows it),
# carry it over, water the fern. The exploration gate only unlocks once the fern is watered AND the
# wander timer has elapsed — the beat is the wait for Monos. The fern's watering-tradition reflection
# (plant_7.line / .line_repeat) lives in its inspection zone.
var _watering_can_item_id := ""
var _watering_can_mesh: Node3D
var _water_plant_interactable
var _can_pickup_interactable
var _fern_exploration_interactable
var _fern_outline_target
var _plant_watered := false
var _explore_time_elapsed := false
const WATERING_CAN_POS := Vector3(2.5, 0.0, 2.0)  # floor by the kiosk, snapped in X/Z to the room plan
const FERN_POS := Vector3(7.0, 0.0, 5.0)  # fallback when the authored fern table is absent
# The watering beat drives the player to the dry fern; the input playthrough drives this point.
# It follows the authored fern table so moving the table in the editor moves the beat with it.
var DRY_PLANT_POS: Vector3:
	get:
		var p := _authored_position("Plant7Table", "Plant7TableAnchor", FERN_POS)
		return Vector3(p.x, 0.0, p.z)

# Exploration beat (phase 1, pre-Monos-arrival)
var _explore_logbook_gate  # Interactable at the logbook
const EXPLORE_MIN_TIME := 6.0  # scheduler seconds before the logbook gate unlocks
var _explore_gate_unlocked := false
var _explore_gate_fired := false

# Peris says she will take a lap while the client connection resolves. Make that
# lap active and spatial instead of allowing the six-second timer plus watering
# alone to skip the room. The plant category deliberately accepts any existing
# plant-group zone, preserving a first-clear exploration branch without moving
# or duplicating any room object.
const CARE_CONTEXT_REQUIRED := ["plant", "painting", "wellness", "strike_warning"]
const CARE_CONTEXT_PLANT_BRANCHES := [
	"shelf",
	"survivor",
	"client",
	"fern",
	"peace",
]

# A first read now covers every distinct room-context station. The second pass is
# a three-case, click-gated audit: an eight-record priority review, then two
# six-record branch reviews, with one logbook decision per case. A review is
# deliberately just under the project-wide five
# second dead-gap ceiling; the progress ring and queued outline make the committed
# work visible. No timer advances the audit without a right-clicked station.
const CARE_AUDIT_WORK_SECONDS := 4.9
const CARE_AUDIT_DIALOGUE_CPS := 30.0
const CARE_AUDIT_RESPONSE_SECONDS_PER_LINE := 0.75
const CARE_AUDIT_FIXED_PRESENTATION_COMPONENTS := {
	"first_visit_fade": 3.0,
	"first_visit_post_dialogue": 3.0,
	"first_visit_transition": 2.5,
	"second_visit_fade": 3.0,
	"session_attack_lead": 2.0,
	"efficiency_log_close": 1.6,
	"second_visit_transition": 2.5,
}
const CARE_AUDIT_COMMON_CASE := {
	"id": "priority",
	"label": "PRIORITY",
	"evidence": ["wellness", "strike", "fern", "painting", "stand", "bookshelf", "coffee", "peace"],
	"candidates": ["wellness", "strike"],
}
const CARE_AUDIT_BRANCH_CASES := {
	"care": {
		"id": "continuity",
		"label": "CARE CONTINUITY",
		"evidence": ["stand", "coffee", "peace", "painting", "bookshelf", "fern"],
		"candidates": ["stand", "coffee"],
	},
	"compliance": {
		"id": "continuity",
		"label": "COMPLIANCE CONTINUITY",
		"evidence": ["strike", "bookshelf", "coffee", "painting", "peace", "wellness"],
		"candidates": ["strike", "wellness"],
	},
}
const CARE_AUDIT_FINAL_CASES := {
	"stand": {
		"id": "disposition",
		"label": "RITUAL DISPOSITION",
		"evidence": ["wellness", "strike", "coffee", "peace", "painting", "fern"],
		"candidates": ["wellness", "strike"],
	},
	"coffee": {
		"id": "disposition",
		"label": "CLIENT-MEMORY DISPOSITION",
		"evidence": ["bookshelf", "stand", "coffee", "peace", "wellness", "strike"],
		"candidates": ["wellness", "strike"],
	},
	"strike": {
		"id": "disposition",
		"label": "WARNING DISPOSITION",
		"evidence": ["stand", "fern", "strike", "bookshelf", "coffee", "peace"],
		"candidates": ["strike", "fern"],
	},
	"wellness": {
		"id": "disposition",
		"label": "SAFEGUARD DISPOSITION",
		"evidence": ["painting", "fern", "wellness", "stand", "coffee", "peace"],
		"candidates": ["wellness", "fern"],
	},
}
const CARE_AUDIT_EVIDENCE_SOURCES := {
	"bookshelf": {"zone": "Plant1Zone", "targets": ["Plant1Outline", "Plant2Outline", "Plant5Outline"], "label": "BOOKSHELF PLANTS"},
	"stand": {"zone": "Plant4Zone", "targets": ["Plant4Outline", "Plant6Outline"], "label": "SURVIVOR PLANTS"},
	"coffee": {"zone": "Plant3Zone", "targets": ["Plant3Outline", "Plant8Outline"], "label": "CLIENT PLANTS"},
	"fern": {"zone": "Plant7Zone", "targets": ["Plant7Outline"], "label": "WATERING LOG"},
	"peace": {"zone": "Plant9Zone", "targets": ["Plant9Outline"], "label": "LEGACY PLANT"},
	"painting": {"zone": "PaintingZone", "targets": ["PaintingOutline"], "label": "WALL ART"},
	"wellness": {"zone": "WellnessZone", "targets": ["WellnessOutline"], "label": "WELLNESS FEED"},
	"strike": {"zone": "StrikeWarningZone", "targets": ["StrikeWarningOutline"], "label": "STRIKE WARNING"},
}

# The audit establishes what Peris believes.  The operations circuit that
# follows makes her turn that belief into a concrete care plan before Monos can
# break through.  Every task id is unique: later phases revisit parts of the
# room for a different verb (diagnose -> treat -> allocate -> verify), rather
# than padding the route with identical inspections.  Both candidate records
# are required, and whichever is reviewed last selects a different physical
# resolution job before the logbook can be committed.
const CARE_OPERATION_PHASES := [
	{
		"id": "diagnostics",
		"label": "CONDITION DIAGNOSTICS",
		"tasks": [
			{"id": "probe_fern_moisture", "source": "fern", "label": "PROBE FERN MOISTURE"},
			{"id": "scan_lily_roots", "source": "peace", "label": "SCAN LILY ROOTS"},
			{"id": "count_shelf_canopies", "source": "bookshelf", "label": "COUNT SHELF CANOPIES"},
			{"id": "check_stand_recovery", "source": "stand", "label": "CHECK STAND RECOVERY"},
			{"id": "sample_table_soil", "source": "coffee", "label": "SAMPLE CLIENT SOIL"},
			{"id": "meter_room_light", "source": "painting", "label": "METER ROOM LIGHT"},
			{"id": "read_wellness_load", "source": "wellness", "label": "READ CARE LOAD"},
			{"id": "read_strike_window", "source": "strike", "label": "READ STRIKE WINDOW"},
		],
		"candidates": ["read_wellness_load", "read_strike_window"],
		"resolutions": {
			"read_wellness_load": {"id": "set_care_baseline", "source": "peace", "label": "SET CARE BASELINE"},
			"read_strike_window": {"id": "freeze_compliance_clock", "source": "bookshelf", "label": "FREEZE COMPLIANCE CLOCK"},
		},
	},
	{
		"id": "treatment",
		"label": "TREATMENT PASS",
		"tasks": [
			{"id": "flush_fern_drainage", "source": "fern", "label": "FLUSH FERN DRAINAGE"},
			{"id": "wrap_lily_support", "source": "peace", "label": "WRAP LILY SUPPORT"},
			{"id": "rotate_shelf_stock", "source": "bookshelf", "label": "ROTATE SHELF STOCK"},
			{"id": "prune_stand_growth", "source": "stand", "label": "PRUNE SURVIVOR GROWTH"},
			{"id": "mix_client_feed", "source": "coffee", "label": "MIX CLIENT FEED"},
			{"id": "set_light_baffle", "source": "painting", "label": "SET LIGHT BAFFLE"},
			{"id": "reserve_recovery_window", "source": "wellness", "label": "RESERVE RECOVERY WINDOW"},
			{"id": "reserve_sanction_window", "source": "strike", "label": "RESERVE SANCTION WINDOW"},
		],
		"candidates": ["reserve_recovery_window", "reserve_sanction_window"],
		"resolutions": {
			"reserve_recovery_window": {"id": "stage_gentle_tools", "source": "stand", "label": "STAGE GENTLE TOOLS"},
			"reserve_sanction_window": {"id": "stage_rapid_feed", "source": "coffee", "label": "STAGE RAPID FEED"},
		},
	},
	{
		"id": "allocation",
		"label": "RESOURCE ALLOCATION",
		"tasks": [
			{"id": "dose_fern_minerals", "source": "fern", "label": "DOSE FERN MINERALS"},
			{"id": "allocate_lily_mist", "source": "peace", "label": "ALLOCATE LILY MIST"},
			{"id": "split_shelf_water", "source": "bookshelf", "label": "SPLIT SHELF WATER"},
			{"id": "stage_stand_tools", "source": "stand", "label": "STAGE STAND TOOLS"},
			{"id": "label_client_stock", "source": "coffee", "label": "LABEL CLIENT STOCK"},
			{"id": "align_privacy_screen", "source": "painting", "label": "ALIGN PRIVACY SCREEN"},
			{"id": "budget_rest_minutes", "source": "wellness", "label": "BUDGET REST MINUTES"},
			{"id": "budget_overtime_minutes", "source": "strike", "label": "BUDGET OVERTIME MINUTES"},
		],
		"candidates": ["budget_rest_minutes", "budget_overtime_minutes"],
		"resolutions": {
			"budget_rest_minutes": {"id": "seal_rest_reserve", "source": "fern", "label": "SEAL REST RESERVE"},
			"budget_overtime_minutes": {"id": "post_overtime_limit", "source": "painting", "label": "POST OVERTIME LIMIT"},
		},
	},
	{
		"id": "verification",
		"label": "RELEASE VERIFICATION",
		"tasks": [
			{"id": "check_fern_runoff", "source": "fern", "label": "CHECK FERN RUNOFF"},
			{"id": "check_lily_leaves", "source": "peace", "label": "CHECK LILY LEAVES"},
			{"id": "verify_shelf_balance", "source": "bookshelf", "label": "VERIFY SHELF BALANCE"},
			{"id": "verify_stand_rebound", "source": "stand", "label": "VERIFY STAND REBOUND"},
			{"id": "verify_client_labels", "source": "coffee", "label": "VERIFY CLIENT LABELS"},
			{"id": "verify_light_level", "source": "painting", "label": "VERIFY LIGHT LEVEL"},
			{"id": "sign_care_release", "source": "wellness", "label": "SIGN CARE RELEASE"},
			{"id": "sign_strike_release", "source": "strike", "label": "SIGN STRIKE RELEASE"},
		],
		"candidates": ["sign_care_release", "sign_strike_release"],
		"resolutions": {
			"sign_care_release": {"id": "witness_living_baseline", "source": "peace", "label": "WITNESS LIVING BASELINE"},
			"sign_strike_release": {"id": "witness_logged_baseline", "source": "bookshelf", "label": "WITNESS LOGGED BASELINE"},
		},
	},
]
const CARE_OPERATION_WORK_SECONDS := 4.9
const CARE_AUDIT_STORY_DIALOGUE_KEYS := [
	"peris_sim.monos.late", "peris_sim.peris.purpose", "peris_sim.monos.turn",
	"peris_sim.monos.opening", "peris_sim.monos.real", "peris_sim.monos.heart",
	"peris_sim.monos.mind", "peris_sim.peris.fight", "peris_sim.monos.hit",
	"peris_sim.peris.alarm", "peris_sim.monos.help", "peris_sim.system.overtime",
	"peris_sim.peris.protect_him", "peris_sim.monos.thanks", "peris_sim.system.complete",
	"peris_sim.system.sanction_notice", "peris_sim.system.wellness_feed",
	"peris_sim.peris.sanction_reaction", "peris_sim.system.spiral_flash",
	"peris_sim.peris.retro", "peris_sim.worker.okay", "peris_sim.worker.medical",
]
const CARE_AUDIT_CONTEXT_DIALOGUE_KEYS := [
	"peris.sim_expand.plant_1.line", "peris.sim_expand.plant_4.line",
	"peris.sim_expand.plant_3.line", "peris.sim_expand.plant_7.line",
	"peris.sim_expand.plant_9.line", "peris.sim_expand.painting.line",
	"peris.sim_expand.wellness.line", "peris.sim_expand.strike_warning.notification",
	"peris.sim_expand.strike_warning.line",
]
var _care_context_completed: Dictionary = {}
var _care_context_zone_visits: Dictionary = {}
var _care_context_plant_group := ""
var _care_context_ready := false
var _care_audit_started := false
var _care_audit_complete := false
var _care_audit_case_index := -1
var _care_audit_branch := ""
var _care_audit_secondary_route := ""
var _care_audit_outcome := ""
var _care_audit_case_evidence: Dictionary = {}
var _care_audit_selected_candidate := ""
var _care_audit_evidence_interactables: Dictionary = {}
var _care_audit_review_counts: Dictionary = {}
var _care_audit_commit_history: Array[Dictionary] = []
var _care_operation_interactables: Dictionary = {}
var _care_operation_resolution_interactable
var _care_operation_phase_index := -1
var _care_operation_stage := ""
var _care_operation_completed_tasks: Dictionary = {}
var _care_operation_selected_candidate := ""
var _care_operation_resolution_id := ""
var _care_operation_decisions: Array[Dictionary] = []
var _care_operations_complete := false
var _care_kit_item_id := ""
var _care_kit_mesh: Node3D
var _care_kit_pickup_interactable
var _care_kit_held := false
var _care_kit_returned := false

# Stamina and run speed are authoritative in GameState.
var _is_paused := false
var _efficiency_score := 100.0

# Fallback positions are used only when a stripped test scene omits the editor-authored nodes.
const PORTAL_PANEL := Vector3(0.5, 2.5, 3.0)   # portal panel centre on the west wall
const PORTAL_POS := Vector3(2.5, 0, 3.0)  # floor in front of the portal — clear space for Peris
const MONOS_POS := Vector3(2.5, 0, 4.0)  # open circulation cell, separate from the protect stand
const PROTECT_INPUT_ACTION := &"party_slot_2_ability_1"
const PERIS_START := Vector3(6.0, 0.5, 4.5)  # circulation lane, outside the can/fern auto-dwell radii

# The workspace is the modeled Crocotile room (peris-sim.gltf): floor X in [0, 14], Z in [0, 6], up
# Y in [0, 5]. The grid is that footprint at 1 cell / unit, so movement is cell-based + cooperative
# like the other gridded scenes. OPEN (no border): the whole floor is walkable. Plants/zones sit right
# up against the visual walls — a bordered grid would wall those edge cells off and make those
# exploration zones unreachable.
const GRID_ORIGIN := Vector3(0.0, 0.0, 0.0)
const GRID_SIZE := Vector2i(14, 6)
const ROOM_FLOOR_Y := 0.0  # the modeled floor's top surface
var _grid: GridWorld
var _room_layout_problems: Array[String] = []
# The room model binding — model lookups / floor surface / occupancy flow through this (RoomModelBinder).
var _room_binder := RoomModelBinder.new()

# The composed room visuals and portable props are authored directly in peris_sim.tscn so they are
# visible, selectable, and movable in the editor. Only the separate live portal-view world is
# instantiated at runtime.
const MONOS_PORTAL_ROOM_VISUAL_SCENE := preload("res://scenes/props/peris/monos_portal_room_visual.tscn")


## The scene's Marker3Ds are the editable floor plan. Constants above are only
## deterministic fallbacks for tests/tools that instantiate the script without
## the authored placement tree.
func _layout_position(marker_name: String, fallback: Vector3) -> Vector3:
	var placement := find_child(PLACEMENT_ROOT, true, false)
	if placement == null:
		return fallback
	var marker := placement.find_child(marker_name, true, false) as Node3D
	return marker.global_position if marker != null else fallback


func _authored_room_node(node_name: String) -> Node3D:
	var room := find_child("PerisRoom", true, false) as Node3D
	if room == null:
		return null
	return room.find_child(node_name, true, false) as Node3D


func _authored_position(node_name: String, marker_name: String, fallback: Vector3) -> Vector3:
	var authored := _authored_room_node(node_name)
	return authored.global_position if authored != null else _layout_position(marker_name, fallback)


func _portal_panel_position() -> Vector3:
	return _authored_position("Portal", "PortalAnchor", PORTAL_PANEL)


func _portal_basis() -> Basis:
	var portal := _authored_room_node("Portal")
	return portal.global_basis.orthonormalized() if portal != null else Basis(Vector3.UP, PI * 0.5)


func _portal_face() -> Vector3:
	return (_portal_basis() * Vector3.BACK).normalized()


## Floor interaction points follow the visible node. `local_floor_offset` rotates with the prop,
## so moving a wall fixture to another wall does not strand its clickable zone at the old marker.
func _authored_floor_interaction_position(
	node_name: String,
	marker_name: String,
	fallback: Vector3,
	local_floor_offset: Vector3
) -> Vector3:
	var authored := _authored_room_node(node_name)
	if authored == null:
		return _layout_position(marker_name, fallback)
	var point := authored.global_position
	point.y = ROOM_FLOOR_Y
	return point + authored.global_basis.orthonormalized() * local_floor_offset


func _set_interaction_approach(interactable: Node, marker_name: String, fallback: Vector3) -> void:
	if interactable != null:
		interactable.set_meta("interaction_target_position", _layout_position(marker_name, fallback))


# --- Virtual method overrides ---

func _build_scene() -> void:
	_build_grid()
	_build_environment()
	# Occupancy depends on the post-layout world AABBs, so derive it only after
	# every modeled assembly has been moved to its authored marker.
	_room_binder.apply_occupancy()

## A single-level walkable plane over the modeled floor (open, no border).
func _build_grid() -> void:
	_grid = GridWorld.new()
	_grid.origin = GRID_ORIGIN
	_grid.create_room(GRID_SIZE.x, GRID_SIZE.y, false)
	# The scene's ONE declaration of its modeled room: the floor surface (overlays/raycast ride it),
	# grid seams aligned to the model's floor, and the re-export guards. setup() lifts grid.origin.y
	# to the floor top so every ground overlay sits on the modeled floor, not inside the slab.
	_room_binder.setup(self, _grid, {
		"root_name": "PerisRoom",
		"floor_surface_y": ROOM_FLOOR_Y,
		"grid_origin_xz": Vector2(0, 0),
		"occupants": ROOM_OCCUPANTS,
		"gltf_path": "res://resources/models/peris-sim/peris-sim.gltf",
		"wired_materials": [],
	})
	_build_portal()

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	_player = _create_player_character("Peris", Color(1.0, 0.67, 0.27))
	_player.position = _layout_position("PerisStart", PERIS_START)
	if not Engine.is_editor_hint():
		_player.grid_world = _grid
	chars.add_child(_player)

	_monos = _create_npc("Monos", Color(0.6, 0.5, 0.35))
	_monos.display_name = "MONOS"
	_monos.position = _layout_position("MonosStart", MONOS_POS)
	_monos.visible = false
	if not Engine.is_editor_hint():
		_monos.grid_world = _grid
	chars.add_child(_monos)

	if not Engine.is_editor_hint():
		# The modeled room is small (14x6); pull the follow camera up/back so the whole floor frames,
		# keeping the far corners (plant stand / bookshelf) clickable.
		_setup_game_camera(_player, Vector3(0, 14, 10), true)
		_bind_camera_to_level_bounds(_grid, 0.5)

func _register_characters() -> void:
	_game_state.grid = _grid
	_register_gs_character("peris", _player, GameState.WALK_SPEED, {
		"stamina": GameState.STAMINA_MAX,
	})
	_register_gs_character("monos", _monos, _monos.move_speed)

func _setup_ui() -> void:
	_thought_label.add_theme_color_override("font_color", Color(0.75, 0.6, 0.45))

	_hud = preload("res://scenes/ui/game_hud.tscn").instantiate()
	add_child(_hud)
	_hud.add_stat_bar("sta", Color(0.3, 0.5, 0.7), GameState.STAMINA_MAX, GameState.STAMINA_MAX)
	_hud.show_pause_toggle(false)
	_hud.show_run_toggle(false)
	var protect_binding := AbilityData.binding("protect")
	_hud.add_ability("protect", AbilityData.get_ability("peris_sim.protect").get("display_name", "PROTECT"),
		InputHints.label_for_action(PROTECT_INPUT_ACTION, str(protect_binding.get("keybind", ""))),
		protect_binding.get("color", Color(0.8, 0.55, 0.2)),
		PROTECT_INPUT_ACTION, "peris", "Peris", 1, 0)
	_hud.pause_toggled.connect(_on_pause_toggled)
	# Step guards decide when run toggles are allowed.
	_hud.run_toggled.connect(func(running: bool): _toggle_run())
	_hud.ability_pressed.connect(func(id: String):
		if id == "protect":
			_on_protect_pressed()
	)
	# Keep run input gated by step.
	_hud.bind_game_state(_game_state, "peris", false)

func _begin() -> void:
	_add_screen_effect("ChromaticAberration", preload("res://resources/chromatic_aberration.gdshader"))
	if start_phase > 0:
		_visit_phase = start_phase
	_current_step = "fade_in"
	_player.set_move_enabled(false)
	# The room is DRESSED from the first frame, in BOTH phases — plants on their furniture, the
	# wall pieces, the logbook console (they used to pop in only when the workspace step fired,
	# seconds after the fade; phase 2 had a plantless room). Interactions stay dark until the
	# phase-1 workspace step arms them.
	_build_exploration_objects()
	if _visit_phase == 1:
		_fade_from(Color(0.15, 0.1, 0.03, 1), 3.0, _start_workspace, "workspace")
	else:
		# Phase 2 resumes mid-session.
		_monos.visible = true
		_portal_light.light_color = Color(0.9, 0.6, 0.3)
		_portal_light.light_energy = 3.0
		_fade_from(Color(0.15, 0.1, 0.03, 1), 3.0, _start_session_begins, "session_begins")

func _compute_speed() -> float:
	var spd := 10.0 if Input.is_action_pressed("fast_forward") else 1.0
	if _is_paused or _current_step in ["alert_monos", "protect_prompt", "run_prompt", "click_monos", "confirm_protect"]:
		spd = 0.0
	return spd

func _on_process(delta: float, spd: float) -> void:
	_update_fades()

	# GameState and GameHUD handle stats, running, and queued Protect.

	if _portal_light and not _portal_tween_active:
		_portal_light.light_energy = 1.5 + sin(Time.get_ticks_msec() * 0.002) * 0.3  # @rendering_only: portal glow

	# Attack light flash
	if _attack_particles and _attack_particles.visible:
		_attack_particles.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.015) * 2.0  # @rendering_only: attack flash

	_update_portal_view()  # @rendering_only: portal lens camera mirror

	# Protect ability display from scheduler ticks
	if _protect_end_tick > 0 and _hud:
		var remaining := maxf(0, _protect_end_tick - _scheduler.get_current_tick())
		_hud.set_ability_state("protect", "active", remaining)
		if remaining <= 0:
			_protect_end_tick = 0.0

func headless_get_state() -> Dictionary:
	var state := super.headless_get_state()
	state.merge({
		"visit_phase": _visit_phase,
		"plant_watered": _plant_watered,
		"explore_time_elapsed": _explore_time_elapsed,
		"explore_gate_unlocked": _explore_gate_unlocked,
		"care_context_completed": _care_context_completed.duplicate(true),
		"care_context_count": _care_context_completed_count(),
		"care_context_required": CARE_CONTEXT_REQUIRED.duplicate(),
		"care_context_complete": _care_context_complete(),
		"care_context_plant_group": _care_context_plant_group,
		"care_context_zone_visits": _care_context_zone_visits.duplicate(true),
		"care_context_plant_groups_complete": _care_context_plant_groups_completed_count(),
		"care_context_ready": _care_context_ready,
		"care_audit_started": _care_audit_started,
		"care_audit_complete": _care_audit_complete,
		"care_audit_case_index": _care_audit_case_index,
		"care_audit_case_total": _care_audit_cases().size() if _care_audit_started else 3,
		"care_audit_branch": _care_audit_branch,
		"care_audit_secondary_route": _care_audit_secondary_route,
		"care_audit_outcome": _care_audit_outcome,
		"care_audit_case_evidence": _care_audit_case_evidence.keys(),
		"care_audit_selected_candidate": _care_audit_selected_candidate,
		"care_audit_review_counts": _care_audit_review_counts.duplicate(true),
		"care_audit_commit_history": _care_audit_commit_history.duplicate(true),
		"care_operation_phase_index": _care_operation_phase_index,
		"care_operation_phase_total": CARE_OPERATION_PHASES.size(),
		"care_operation_stage": _care_operation_stage,
		"care_operation_completed_tasks": _care_operation_completed_tasks.keys(),
		"care_operation_selected_candidate": _care_operation_selected_candidate,
		"care_operation_resolution_id": _care_operation_resolution_id,
		"care_operation_decisions": _care_operation_decisions.duplicate(true),
		"care_operations_complete": _care_operations_complete,
		"care_kit_held": _care_kit_held,
		"care_kit_returned": _care_kit_returned,
	}, true)
	return state

func get_playtime_contract() -> Dictionary:
	var context_route_meters := _care_context_minimum_route_meters()
	var care_route_meters := _care_audit_branch_route_meters("care")
	var compliance_route_meters := _care_audit_branch_route_meters("compliance")
	var audit_route_meters := minf(care_route_meters, compliance_route_meters)
	var operation_route_meters := _care_operation_minimum_route_meters()
	var move_speed := maxf(float(_player.move_speed) if _player != null else GameState.WALK_SPEED, 0.1)
	var audit_evidence_reviews := (CARE_AUDIT_COMMON_CASE.get("evidence", []) as Array).size() + 2 * 6
	var operation_task_reviews := 0
	for raw_phase in CARE_OPERATION_PHASES:
		operation_task_reviews += ((raw_phase as Dictionary).get("tasks", []) as Array).size()
	var operation_resolution_actions := CARE_OPERATION_PHASES.size()
	# Open audit + three audit commits + operations handoff, four operation
	# commits, and the final connection release.  Returning the kit also happens
	# at the logbook but is categorized as inventory handling, not double-counted.
	var audit_logbook_actions := 5
	var operation_logbook_commits := CARE_OPERATION_PHASES.size()
	var final_release_actions := 1
	var logbook_work_actions := audit_logbook_actions + operation_logbook_commits + final_release_actions
	var station_work_seconds := (
		audit_evidence_reviews
		+ operation_task_reviews
		+ operation_resolution_actions
		+ logbook_work_actions
	) * CARE_OPERATION_WORK_SECONDS
	var watering_inventory_seconds := _care_inventory_work_seconds()
	var care_kit_actions := 2
	var inventory_work_seconds := watering_inventory_seconds \
		+ care_kit_actions * CARE_OPERATION_WORK_SECONDS
	var story_dialogue_seconds := _care_audit_dialogue_model_seconds(CARE_AUDIT_STORY_DIALOGUE_KEYS)
	var context_dialogue_seconds := _care_audit_dialogue_model_seconds(CARE_AUDIT_CONTEXT_DIALOGUE_KEYS)
	var route_seconds := (context_route_meters + audit_route_meters + operation_route_meters) / move_speed
	var fixed_presentation_seconds := _care_audit_fixed_presentation_seconds()
	var meaningful_active_seconds := station_work_seconds + inventory_work_seconds + route_seconds
	var modeled_first_clear := meaningful_active_seconds + fixed_presentation_seconds \
		+ story_dialogue_seconds + context_dialogue_seconds
	var category_seconds := {
		"audit_casework": (audit_evidence_reviews + audit_logbook_actions) * CARE_AUDIT_WORK_SECONDS,
		"connection_release": final_release_actions * CARE_OPERATION_WORK_SECONDS,
		"inventory_handling": inventory_work_seconds,
		"spatial_navigation": route_seconds,
	}
	for raw_phase in CARE_OPERATION_PHASES:
		var phase: Dictionary = raw_phase
		category_seconds["%s_work" % str(phase.get("id", "operation"))] = (
			(phase.get("tasks", []) as Array).size() + 2
		) * CARE_OPERATION_WORK_SECONDS
	return {
		"required_first_clear_seconds": 300.0,
		"target_min_seconds": 300.0,
		"target_max_seconds": 480.0,
		"target_metric": "meaningful_active_seconds",
		"modeled_first_clear_seconds": modeled_first_clear,
		"modeled_total_first_clear_seconds": modeled_first_clear,
		"modeled_meaningful_active_seconds": meaningful_active_seconds,
		"meaningful_active_seconds": meaningful_active_seconds,
		"total_play_seconds": modeled_first_clear,
		"active_ratio": meaningful_active_seconds / modeled_first_clear,
		"max_dead_gap_seconds": 3.0,
		"max_single_mode_seconds": CARE_OPERATION_WORK_SECONDS * 2.0,
		"category_seconds": category_seconds,
		"modeled_story_dialogue_seconds": story_dialogue_seconds,
		"modeled_context_dialogue_seconds": context_dialogue_seconds,
		"authored_fixed_presentation_seconds": fixed_presentation_seconds,
		"fixed_presentation_components": CARE_AUDIT_FIXED_PRESENTATION_COMPONENTS.duplicate(true),
		"minimum_context_route_meters": context_route_meters,
		"minimum_audit_route_meters": audit_route_meters,
		"minimum_operation_route_meters": operation_route_meters,
		"care_branch_route_meters": care_route_meters,
		"compliance_branch_route_meters": compliance_route_meters,
		"movement_speed_meters_per_second": move_speed,
		"mandatory_audit_evidence_reviews": audit_evidence_reviews,
		"mandatory_operation_task_reviews": operation_task_reviews,
		"mandatory_operation_resolution_actions": operation_resolution_actions,
		"mandatory_operation_commits": operation_logbook_commits,
		"mandatory_logbook_actions": logbook_work_actions,
		"audit_work_seconds_each": CARE_AUDIT_WORK_SECONDS,
		"operation_work_seconds_each": CARE_OPERATION_WORK_SECONDS,
		"mandatory_inventory_work_seconds": inventory_work_seconds,
		"mandatory_watering_inventory_seconds": watering_inventory_seconds,
		"mandatory_care_kit_actions": care_kit_actions,
		"maximum_authored_dead_gap_seconds": 3.0,
		"dialogue_chars_per_second": CARE_AUDIT_DIALOGUE_CPS,
		"dialogue_response_seconds_per_line": CARE_AUDIT_RESPONSE_SECONDS_PER_LINE,
		"required_care_categories": CARE_CONTEXT_REQUIRED.duplicate(),
		"mandatory_context_categories": CARE_CONTEXT_REQUIRED.size(),
		"mandatory_plant_groups": CARE_CONTEXT_PLANT_BRANCHES.size(),
		"mandatory_inventory_actions": 4,
		"mandatory_logbook_commits": 3 + operation_logbook_commits,
		"plant_group_branches": CARE_CONTEXT_PLANT_BRANCHES.duplicate(),
		"decision_count": 3 + CARE_OPERATION_PHASES.size(),
		"branch_count": 4 + CARE_OPERATION_PHASES.size() * 2,
		"hard_idle_lock_seconds": 0.0,
		"basis": "live marker constrained-route minima + scheduler-backed unique care jobs + real carried inventory + authored normal-speed first reads + fixed scene transitions",
	}

func _care_audit_fixed_presentation_seconds() -> float:
	var total := 0.0
	for raw_seconds in CARE_AUDIT_FIXED_PRESENTATION_COMPONENTS.values():
		total += float(raw_seconds)
	return total

func _care_inventory_work_seconds() -> float:
	var total := 0.0
	for interactable in [_can_pickup_interactable, _water_plant_interactable]:
		if interactable != null and is_instance_valid(interactable):
			total += float(interactable.get("dwell_time"))
	return total if total > 0.0 else 1.6

func _care_audit_dialogue_model_seconds(keys: Array) -> float:
	var characters := 0
	var line_count := 0
	for raw_key in keys:
		var line := DialogueData.get_line(str(raw_key))
		if line.text == "" or line.text.begins_with("[MISSING:"):
			continue
		characters += line.text.length()
		line_count += 1
	return characters / CARE_AUDIT_DIALOGUE_CPS + line_count * CARE_AUDIT_RESPONSE_SECONDS_PER_LINE

func _care_context_minimum_route_meters() -> float:
	var start := _layout_position("PerisStart", PERIS_START)
	var can := _authored_position("WateringCan", "WateringCanAnchor", WATERING_CAN_POS)
	var fern := _care_audit_evidence_contract_position("fern")
	var logbook := _care_logbook_contract_position()
	var remaining := ["bookshelf", "stand", "coffee", "peace", "painting", "wellness", "strike"]
	return _horizontal_distance(start, can) + _horizontal_distance(can, fern) \
		+ _care_minimum_route(fern, logbook, remaining)

func _care_audit_branch_route_meters(branch: String) -> float:
	var continuity: Dictionary = CARE_AUDIT_BRANCH_CASES.get(branch, {})
	if continuity.is_empty():
		return 0.0
	var primary_selection := "wellness" if branch == "care" else "strike"
	var common_distance := _care_audit_case_minimum_route_meters(CARE_AUDIT_COMMON_CASE, primary_selection)
	var best := INF
	for raw_secondary in (continuity.get("candidates", []) as Array):
		var secondary := str(raw_secondary)
		var final_case: Dictionary = CARE_AUDIT_FINAL_CASES.get(secondary, {})
		if final_case.is_empty():
			continue
		var distance := common_distance \
			+ _care_audit_case_minimum_route_meters(continuity, secondary) \
			+ _care_audit_case_minimum_route_meters(final_case)
		best = minf(best, distance)
	return 0.0 if best == INF else best


func _care_operation_minimum_route_meters() -> float:
	var total := 0.0
	for raw_phase in CARE_OPERATION_PHASES:
		total += _care_operation_phase_minimum_route_meters(raw_phase as Dictionary)
	return total


func _care_operation_phase_minimum_route_meters(phase: Dictionary) -> float:
	var logbook := _care_logbook_contract_position()
	var source_ids: Array = []
	var task_sources: Dictionary = {}
	for raw_task in (phase.get("tasks", []) as Array):
		var task: Dictionary = raw_task
		var task_id := str(task.get("id", ""))
		var source_id := str(task.get("source", ""))
		task_sources[task_id] = source_id
		source_ids.append(source_id)
	var candidates: Array = phase.get("candidates", [])
	var resolutions: Dictionary = phase.get("resolutions", {})
	var best := INF
	for raw_selected in candidates:
		var selected := str(raw_selected)
		var other := ""
		for raw_candidate in candidates:
			if str(raw_candidate) != selected:
				other = str(raw_candidate)
				break
		var resolution: Dictionary = resolutions.get(selected, {})
		var resolution_source := str(resolution.get("source", ""))
		if resolution_source == "":
			continue
		var resolution_position := _care_audit_evidence_contract_position(resolution_source)
		var distance := _care_minimum_route(
			logbook,
			resolution_position,
			source_ids,
			str(task_sources.get(selected, "")),
			str(task_sources.get(other, ""))
		) + _horizontal_distance(resolution_position, logbook)
		best = minf(best, distance)
	return 0.0 if best == INF else best

func _care_audit_case_minimum_route_meters(case_data: Dictionary, selected_candidate := "") -> float:
	var ids: Array = case_data.get("evidence", [])
	var candidates: Array = case_data.get("candidates", [])
	var other_candidate := ""
	if selected_candidate != "":
		for raw_candidate in candidates:
			if str(raw_candidate) != selected_candidate:
				other_candidate = str(raw_candidate)
				break
	var logbook := _care_logbook_contract_position()
	return _care_minimum_route(logbook, logbook, ids, selected_candidate, other_candidate)

func _care_minimum_route(
	start: Vector3,
	finish: Vector3,
	ids: Array,
	selected_candidate := "",
	other_candidate := ""
) -> float:
	if ids.is_empty():
		return _horizontal_distance(start, finish)
	var points: Array[Vector3] = []
	for raw_id in ids:
		points.append(_care_audit_evidence_contract_position(str(raw_id)))
	var selected_index := ids.find(selected_candidate) if selected_candidate != "" else -1
	var other_index := ids.find(other_candidate) if other_candidate != "" else -1
	var full_mask := (1 << ids.size()) - 1
	var costs: Dictionary = {}
	for index in range(ids.size()):
		if index == selected_index and other_index >= 0:
			continue
		costs[((1 << index) << 5) | index] = _horizontal_distance(start, points[index])
	for mask in range(1, full_mask + 1):
		for last in range(ids.size()):
			var key := (mask << 5) | last
			if not costs.has(key):
				continue
			var current := float(costs[key])
			for next in range(ids.size()):
				var next_bit := 1 << next
				if (mask & next_bit) != 0:
					continue
				if next == selected_index and other_index >= 0 and (mask & (1 << other_index)) == 0:
					continue
				var next_mask := mask | next_bit
				var next_key := (next_mask << 5) | next
				var candidate := current + _horizontal_distance(points[last], points[next])
				if not costs.has(next_key) or candidate < float(costs[next_key]):
					costs[next_key] = candidate
	var best := INF
	for last in range(ids.size()):
		var final_key := (full_mask << 5) | last
		if costs.has(final_key):
			best = minf(best, float(costs[final_key]) + _horizontal_distance(points[last], finish))
	return 0.0 if best == INF else best

func _care_logbook_contract_position() -> Vector3:
	if _explore_logbook_gate != null and is_instance_valid(_explore_logbook_gate):
		return _explore_logbook_gate.global_position
	return _layout_position("LogbookGateMarker", Vector3(12.5, 0.0, 3.5))

func _care_audit_evidence_contract_position(evidence_id: String) -> Vector3:
	var live = _care_audit_evidence_interactables.get(evidence_id)
	if live is Node3D and is_instance_valid(live):
		return _care_interaction_contract_position(live as Node3D)
	var config: Dictionary = CARE_AUDIT_EVIDENCE_SOURCES.get(evidence_id, {})
	var source := find_child(str(config.get("zone", "")), true, false) as Node3D
	if source != null:
		return _care_interaction_contract_position(source)
	return Vector3.ZERO

func _care_interaction_contract_position(interactable: Node3D) -> Vector3:
	if interactable.has_meta("interaction_target_position"):
		var target = interactable.get_meta("interaction_target_position")
		if target is Vector3:
			return target
	return interactable.global_position

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

# --- Per-frame visual helpers ---

func _update_fades() -> void:
	if _current_step == "fade_in":
		_update_fade_in(2.5)
	elif _current_step == "transition_out":
		_update_fade_out(Color(0.03, 0.03, 0.04), 2.0)

# --- Target selection (click Monos) ---

## During click_monos the player is in "select" click mode; the shared input
## controller reports the clicked ground position here. We only decide whether
## it's close enough to Monos — no raycasting in the sequence.
func _on_target_selected(world_pos: Vector3) -> void:
	if _current_step != "click_monos":
		return
	var monos_pos := _layout_position("MonosStart", MONOS_POS)
	var dist_to_monos := Vector2(world_pos.x - monos_pos.x, world_pos.z - monos_pos.z).length()
	if dist_to_monos < 2.5:
		if _player.ground_clicked.is_connected(_on_target_selected):
			_player.ground_clicked.disconnect(_on_target_selected)
		_player.set_click_mode("move")
		_tutorial_prompt.hide_prompt()
		_start_confirm_protect()
	else:
		_show_correction("peris_sim.correct.target_monos")

func _toggle_pause() -> void:
	# Only allow unpause at the confirm_protect step
	if _current_step == "confirm_protect":
		_start_executing()
		return
	# Correction: trying to unpause during the ordered tutorial
	if _current_step in ["alert_monos", "protect_prompt", "run_prompt", "click_monos"]:
		_show_correction("peris_sim.correct.not_yet")
		return
	_is_paused = not _is_paused
	if _hud:
		_hud.set_paused(_is_paused)

func _on_pause_toggled(is_paused: bool) -> void:
	if _current_step == "confirm_protect" and not is_paused:
		_start_executing()
		return
	if _current_step in ["alert_monos", "protect_prompt", "run_prompt", "click_monos"]:
		_show_correction("peris_sim.correct.not_yet")
		return
	_is_paused = is_paused

func _toggle_run() -> void:
	if _game_state == null:
		return
	# Run is only valid at run_prompt.
	if _current_step == "run_prompt":
		_has_sprinted = true
		_game_state.set_running("peris", true)
		_player.set_running(true)
		_start_click_monos()
		return
	if _current_step == "protect_prompt":
		_has_sprinted = true
		_game_state.set_running("peris", true)
		_player.set_running(true)
		_show_thought(DialogueData.text("peris_sim.protect_remind"))
		return
	if _current_step in ["alert_monos", "click_monos", "confirm_protect"]:
		return
	# Normal run toggle.
	_game_state.toggle_running("peris")
	var now_running := _game_state.is_running("peris")
	if now_running:
		_has_sprinted = true
	_player.set_running(now_running)

func _show_correction(key: String) -> void:
	_show_thought(DialogueData.text(key))

# --- Event-driven steps ---

func _start_workspace() -> void:
	_current_step = "workspace"
	_player.set_move_enabled(true)
	# Phase 1 wanders the room while the new client's session stalls; the
	# exploration gate is where the spoofed signal finally breaks through.
	_show_thought(DialogueData.text("peris.sim_expand.opening.line"))
	_build_exploration_objects()   # idempotent — the room was dressed at _begin
	_reset_care_context_progress()
	_set_exploration_armed(true)   # the wander step is where the room becomes touchable
	if _can_pickup_interactable != null:
		_can_pickup_interactable.call_deferred("show_tutorial_label")
	_explore_gate_unlocked = false
	_explore_gate_fired = false
	_explore_time_elapsed = false
	# Teach the reveal-all overlay while the player is hunting the room for what to interact with.
	# UI lane so the hint shows even if gameplay is paused, and speeds with hold-F like the rest.
	_ui_scheduler.schedule_after(2.5, func():
		if _tutorial_prompt != null:
			_tutorial_prompt.show_action_prompt(
				"highlight", "Reveal interactions", 4.0, "Shift"
			), "highlight_hint")
	_ui_scheduler.schedule_after(6.5, _show_care_context_progress_hint, "care_context_hint")
	_scheduler.schedule_after(EXPLORE_MIN_TIME, _unlock_exploration_gate, "explore_gate_unlock")

func _unlock_exploration_gate() -> void:
	# Time is only a reminder threshold. Watering and the active context lap own the unlock.
	_explore_time_elapsed = true
	_maybe_unlock_exploration_gate()

func _reset_care_context_progress() -> void:
	_care_context_completed.clear()
	for category in CARE_CONTEXT_REQUIRED:
		_care_context_completed[category] = false
	_care_context_zone_visits.clear()
	_care_context_plant_group = ""
	_care_context_ready = false
	_care_audit_started = false
	_care_audit_complete = false
	_care_audit_case_index = -1
	_care_audit_branch = ""
	_care_audit_secondary_route = ""
	_care_audit_outcome = ""
	_care_audit_case_evidence.clear()
	_care_audit_selected_candidate = ""
	_care_audit_review_counts.clear()
	_care_audit_commit_history.clear()
	_care_operation_phase_index = -1
	_care_operation_stage = ""
	_care_operation_completed_tasks.clear()
	_care_operation_selected_candidate = ""
	_care_operation_resolution_id = ""
	_care_operation_decisions.clear()
	_care_operations_complete = false
	_care_kit_held = false
	_care_kit_returned = false

func _care_context_completed_count() -> int:
	var completed := _care_context_plant_groups_completed_count()
	for category in ["painting", "wellness", "strike_warning"]:
		if bool(_care_context_completed.get(category, false)):
			completed += 1
	return completed

func _care_context_plant_groups_completed_count() -> int:
	var completed := 0
	for branch_id in CARE_CONTEXT_PLANT_BRANCHES:
		if int(_care_context_zone_visits.get(branch_id, 0)) > 0:
			completed += 1
	return completed

func _care_context_total_required_count() -> int:
	return CARE_CONTEXT_PLANT_BRANCHES.size() + 3

func _care_context_complete() -> bool:
	return _care_context_completed_count() == _care_context_total_required_count()

func _register_care_context_zone(zone: Node, category: String, branch_id: String) -> void:
	if zone == null or not zone.has_signal("interacted"):
		return
	var callback := Callable(self, "_on_care_context_zone_interacted").bind(category, branch_id)
	if not zone.is_connected("interacted", callback):
		zone.connect("interacted", callback)

func _on_care_context_zone_interacted(category: String, branch_id: String) -> void:
	if _visit_phase != 1 or _current_step != "workspace" or not CARE_CONTEXT_REQUIRED.has(category):
		return
	var visit_key := branch_id if branch_id != "" else category
	_care_context_zone_visits[visit_key] = int(_care_context_zone_visits.get(visit_key, 0)) + 1
	var first_category := not bool(_care_context_completed.get(category, false))
	_care_context_completed[category] = true
	if category == "plant" and _care_context_plant_group == "":
		_care_context_plant_group = branch_id
	if not first_category and category != "plant":
		_show_care_context_progress_hint()
		return
	_ui_scheduler.cancel_tag("care_context_hint")
	_show_care_context_progress_hint()
	_maybe_unlock_exploration_gate()

func _show_care_context_progress_hint() -> void:
	if _tutorial_prompt == null or _visit_phase != 1 or _current_step != "workspace":
		return
	var complete_count := _care_context_completed_count()
	if not _care_context_complete():
		var remaining: Array[String] = []
		for branch_id in CARE_CONTEXT_PLANT_BRANCHES:
			if int(_care_context_zone_visits.get(branch_id, 0)) <= 0:
				remaining.append(_care_context_plant_label(str(branch_id)))
		for category in ["painting", "wellness", "strike_warning"]:
			if not bool(_care_context_completed.get(category, false)):
				remaining.append(_care_context_category_label(category))
		_tutorial_prompt.show_prompt(
			"ROOM CONTEXT  %d/%d  ·  STILL TO READ: %s" % [
				complete_count,
				_care_context_total_required_count(),
				", ".join(remaining),
			], 7.0
		)
	elif not _plant_watered:
		_tutorial_prompt.show_prompt("ROOM CONTEXT  8/8  ·  WATER THE FERN", 5.0)
	elif not _explore_time_elapsed:
		_tutorial_prompt.show_prompt("ROOM CONTEXT  8/8  ·  CONNECTION RESOLVING", 5.0)
	else:
		_tutorial_prompt.show_prompt("ROOM CONTEXT COMPLETE  ·  OPEN THE LOGBOOK AUDIT", 6.0)

func _care_context_plant_label(branch_id: String) -> String:
	match branch_id:
		"shelf":
			return "bookshelf plants"
		"survivor":
			return "survivor plants"
		"client":
			return "client plants"
		"fern":
			return "watering fern"
		"peace":
			return "legacy lily"
		_:
			return branch_id

func _care_context_category_label(category: String) -> String:
	match category:
		"painting":
			return "wall art"
		"wellness":
			return "wellness feed"
		"strike_warning":
			return "strike warning"
		_:
			return category

func _on_exploration_gate_interacted() -> void:
	if _visit_phase == 1 and _current_step == "workspace" and _care_context_ready and not _care_audit_started:
		_start_care_audit_circuit()
		return
	if _visit_phase == 1 and _current_step == "care_audit":
		_on_care_audit_logbook_interacted()
		return
	if _visit_phase == 1 and _current_step == "care_operations":
		_on_care_operation_logbook_interacted()
		return
	if not _explore_gate_unlocked or _explore_gate_fired:
		return
	_explore_gate_fired = true
	_hide_thought()
	_start_monos_breakthrough()

func _start_care_audit_circuit() -> void:
	if _care_audit_started:
		return
	_care_audit_started = true
	_care_audit_complete = false
	_care_audit_case_index = 0
	_care_audit_branch = ""
	_care_audit_secondary_route = ""
	_care_audit_outcome = ""
	_current_step = "care_audit"
	_ui_scheduler.cancel_tag("care_context_hint")
	_build_care_audit_interactables()
	for interactable in _exploration_interactables:
		if interactable != null and is_instance_valid(interactable) \
				and interactable != _explore_logbook_gate \
				and interactable.has_method("set_interaction_enabled"):
			interactable.set_interaction_enabled(false)
	_start_care_audit_case()

func _build_care_audit_interactables() -> void:
	if not _care_audit_evidence_interactables.is_empty():
		return
	for raw_id in CARE_AUDIT_EVIDENCE_SOURCES:
		var evidence_id := str(raw_id)
		var config: Dictionary = CARE_AUDIT_EVIDENCE_SOURCES[evidence_id]
		var source := find_child(str(config.get("zone", "")), true, false) as Node3D
		if source == null:
			continue
		if source.has_method("set_interaction_enabled"):
			source.set_interaction_enabled(false)
		var parent := source.get_parent() as Node3D
		if parent == null:
			continue
		var evidence := _create_interactable(
			parent,
			source.position,
			"CareAudit%s" % evidence_id.capitalize().replace(" ", ""),
			float(source.get("interaction_radius")),
			CARE_AUDIT_WORK_SECONDS,
			"AUDIT %s" % str(config.get("label", evidence_id)).to_upper(),
			false,
			Interactable.InteractableType.TIMED_ACTION
		)
		# The data layer records click-gated actions as non-hold interactions;
		# restore TIMED_ACTION on the view so arrival starts the visible work ring.
		evidence.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
		evidence.set("dwell_time", CARE_AUDIT_WORK_SECONDS)
		evidence.set("one_shot", false)
		evidence.set("required_character", "peris")
		evidence.set("description", "Care Audit: %s" % str(config.get("label", evidence_id)))
		evidence.set_meta("care_audit_evidence_id", evidence_id)
		if source.has_meta("interaction_target_position"):
			evidence.set_meta(
				"interaction_target_position",
				source.get_meta("interaction_target_position")
			)
		evidence.interacted.connect(_on_care_audit_evidence_reviewed.bind(evidence_id))
		evidence.set_interaction_enabled(false)
		_care_audit_evidence_interactables[evidence_id] = evidence
		var primary_target: Node = null
		for raw_target_name in (config.get("targets", []) as Array):
			var target := find_child(str(raw_target_name), true, false)
			if target == null:
				continue
			if primary_target == null:
				primary_target = target
			_set_room_target_interaction_delegate(target, evidence)
		if primary_target != null and evidence.has_method("set_outline_target"):
			evidence.set_outline_target(primary_target)

func _care_audit_cases() -> Array:
	return _care_audit_cases_for_branch(
		_care_audit_branch if _care_audit_branch != "" else "care",
		_care_audit_secondary_route
	)

func _care_audit_cases_for_branch(branch: String, secondary_route := "") -> Array:
	var cases: Array = [CARE_AUDIT_COMMON_CASE]
	var continuity: Dictionary = CARE_AUDIT_BRANCH_CASES.get(branch, {})
	if not continuity.is_empty():
		cases.append(continuity)
	var route_id := secondary_route
	if route_id == "":
		var candidates: Array = continuity.get("candidates", [])
		if not candidates.is_empty():
			route_id = str(candidates[0])
	var final_case: Dictionary = CARE_AUDIT_FINAL_CASES.get(route_id, {})
	if not final_case.is_empty():
		cases.append(final_case)
	return cases

func _current_care_audit_case() -> Dictionary:
	var cases := _care_audit_cases()
	if _care_audit_case_index < 0 or _care_audit_case_index >= cases.size():
		return {}
	return cases[_care_audit_case_index]

func _start_care_audit_case() -> void:
	var case_data := _current_care_audit_case()
	if case_data.is_empty():
		_complete_care_audit()
		return
	_care_audit_case_evidence.clear()
	_care_audit_selected_candidate = ""
	_set_care_audit_evidence_enabled(case_data.get("evidence", []) as Array)
	if _explore_logbook_gate != null:
		_explore_logbook_gate.set_interaction_enabled(false)
	_show_care_audit_prompt(
		"CARE AUDIT %d/3 · %s\nReview %s. PRIORITY CHOICE: %s. The last choice record reviewed is staged for the logbook." % [
			_care_audit_case_index + 1,
			str(case_data.get("label", "CASE")),
			_care_audit_evidence_labels(case_data.get("evidence", []) as Array),
			_care_audit_evidence_labels(case_data.get("candidates", []) as Array),
		],
		9.0
	)

func _set_care_audit_evidence_enabled(required: Array) -> void:
	for raw_id in _care_audit_evidence_interactables:
		var evidence_id := str(raw_id)
		var evidence = _care_audit_evidence_interactables[evidence_id]
		if evidence == null or not is_instance_valid(evidence):
			continue
		if required.has(evidence_id):
			_rearm_care_interactable(evidence)
			if evidence.has_method("show_tutorial_label"):
				evidence.call_deferred("show_tutorial_label")
		else:
			evidence.set_interaction_enabled(false)

func _on_care_audit_evidence_reviewed(evidence_id: String) -> void:
	if _current_step != "care_audit" or _care_audit_complete:
		return
	var case_data := _current_care_audit_case()
	var required: Array = case_data.get("evidence", [])
	if not required.has(evidence_id):
		return
	_care_audit_case_evidence[evidence_id] = true
	_care_audit_review_counts[evidence_id] = int(_care_audit_review_counts.get(evidence_id, 0)) + 1
	var candidates: Array = case_data.get("candidates", [])
	if candidates.has(evidence_id):
		_care_audit_selected_candidate = evidence_id
	var message := "CARE AUDIT %d/3 · %s\nRECORDS %d/%d" % [
		_care_audit_case_index + 1,
		str(case_data.get("label", "CASE")),
		_care_audit_case_evidence.size(),
		required.size(),
	]
	if _care_audit_case_evidence_complete():
		message += " · PRIORITY: %s\nReturn to the logbook to commit, or review the other priority record to change it." % \
			_care_audit_evidence_label(_care_audit_selected_candidate)
		_rearm_care_interactable(_explore_logbook_gate)
		if _explore_logbook_gate != null and _explore_logbook_gate.has_method("show_tutorial_label"):
			_explore_logbook_gate.show_tutorial_label()
	else:
		message += "\nSTILL TO REVIEW: %s" % _care_audit_evidence_labels(_care_audit_missing_evidence())
	_show_care_audit_prompt(message, 8.0)

func _care_audit_case_evidence_complete() -> bool:
	var required: Array = _current_care_audit_case().get("evidence", [])
	for raw_id in required:
		if not bool(_care_audit_case_evidence.get(str(raw_id), false)):
			return false
	return not required.is_empty()

func _care_audit_missing_evidence() -> Array:
	var missing: Array = []
	for raw_id in (_current_care_audit_case().get("evidence", []) as Array):
		if not bool(_care_audit_case_evidence.get(str(raw_id), false)):
			missing.append(str(raw_id))
	return missing

func _on_care_audit_logbook_interacted() -> void:
	if _care_audit_complete:
		_start_care_operations()
		return
	if not _care_audit_case_evidence_complete():
		_show_care_audit_prompt(
			"CARE AUDIT · REVIEW MISSING RECORDS: %s" % _care_audit_evidence_labels(_care_audit_missing_evidence()),
			7.0
		)
		return
	if _care_audit_selected_candidate == "":
		_show_care_audit_prompt("CARE AUDIT · REVIEW A PRIORITY RECORD AGAIN, THEN COMMIT.", 7.0)
		return
	if _care_audit_case_index == 0:
		_care_audit_branch = "care" if _care_audit_selected_candidate == "wellness" else "compliance"
	elif _care_audit_case_index == 1:
		# The continuity decision selects a genuinely different final evidence
		# route; it is not a cosmetic entry in the commit history.
		_care_audit_secondary_route = _care_audit_selected_candidate
	else:
		# The final priority becomes the visible audit disposition.
		_care_audit_outcome = _care_audit_selected_candidate
	_care_audit_commit_history.append({
		"case_id": str(_current_care_audit_case().get("id", "")),
		"candidate": _care_audit_selected_candidate,
		"branch": _care_audit_branch,
		"secondary_route": _care_audit_secondary_route,
		"outcome": _care_audit_outcome,
	})
	_care_audit_case_index += 1
	if _care_audit_case_index >= _care_audit_cases().size():
		_complete_care_audit()
	else:
		_start_care_audit_case()

func _complete_care_audit() -> void:
	_care_audit_complete = true
	_explore_gate_unlocked = true
	for evidence in _care_audit_evidence_interactables.values():
		if evidence != null and is_instance_valid(evidence) and evidence.has_method("set_interaction_enabled"):
			evidence.set_interaction_enabled(false)
	_rearm_care_interactable(_explore_logbook_gate)
	if _explore_logbook_gate != null and _explore_logbook_gate.has_method("show_tutorial_label"):
		_explore_logbook_gate.show_tutorial_label()
	_show_care_audit_prompt(
		"CARE AUDIT CLOSED · %s-FIRST / %s DISPOSITION\nRight-click the logbook to collect the field plan and make it executable." % [
			_care_audit_branch.to_upper(),
			_care_audit_evidence_label(_care_audit_outcome),
		],
		9.0
	)

func _rearm_care_interactable(interactable: Node) -> void:
	if interactable == null or not is_instance_valid(interactable):
		return
	if interactable.has_method("reset"):
		interactable.reset()
	elif interactable.has_method("set_interaction_enabled"):
		interactable.set_interaction_enabled(true)
	interactable.set("one_shot", false)

func _show_care_audit_prompt(message: String, duration: float) -> void:
	if _tutorial_prompt != null and _tutorial_prompt.has_method("show_prompt"):
		_tutorial_prompt.show_prompt(message, duration)

func _care_audit_evidence_label(evidence_id: String) -> String:
	var config: Dictionary = CARE_AUDIT_EVIDENCE_SOURCES.get(evidence_id, {})
	return str(config.get("label", evidence_id)).to_upper()

func _care_audit_evidence_labels(ids: Array) -> String:
	var labels: Array[String] = []
	for raw_id in ids:
		labels.append(_care_audit_evidence_label(str(raw_id)))
	return ", ".join(labels)


# --- Active care-operation circuit ---

func _start_care_operations() -> void:
	if _current_step == "care_operations":
		return
	_current_step = "care_operations"
	_care_operation_phase_index = 0
	_care_operation_stage = "collect_kit"
	_care_operation_completed_tasks.clear()
	_care_operation_selected_candidate = ""
	_care_operation_resolution_id = ""
	_care_operation_decisions.clear()
	_care_operations_complete = false
	_care_kit_held = false
	_care_kit_returned = false
	_build_care_operation_interactables()
	_build_care_operation_kit()
	if _explore_logbook_gate != null:
		_explore_logbook_gate.set_interaction_enabled(false)
	_show_care_audit_prompt(
		"CARE PLAN 0/4 · TAKE THE FIELD KIT\nCarry the diagnostic tools through four distinct operations before releasing the connection.",
		9.0
	)
	if _care_kit_pickup_interactable != null:
		_rearm_care_interactable(_care_kit_pickup_interactable)
		if _care_kit_pickup_interactable.has_method("show_tutorial_label"):
			_care_kit_pickup_interactable.show_tutorial_label()


func _build_care_operation_kit() -> void:
	if _care_kit_pickup_interactable != null and is_instance_valid(_care_kit_pickup_interactable):
		return
	_care_kit_mesh = _authored_room_node("CareFieldKit")
	if _care_kit_mesh == null:
		push_warning("Peris room is missing its editor-authored CareFieldKit")
		return
	var kit_pos := _care_kit_mesh.global_position
	_care_kit_mesh.visible = true
	_care_kit_item_id = _game_state.spawn_item("peris_care_field_kit", kit_pos)
	_care_kit_pickup_interactable = _create_interactable(
		self, kit_pos, "CareKitPickup", 1.25, CARE_OPERATION_WORK_SECONDS,
		"TAKE CARE KIT", false, Interactable.InteractableType.TIMED_ACTION
	)
	_care_kit_pickup_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_care_kit_pickup_interactable.set("dwell_time", CARE_OPERATION_WORK_SECONDS)
	_care_kit_pickup_interactable.set("required_character", "peris")
	_care_kit_pickup_interactable.set("description", "Carry Peris's field-care kit")
	_care_kit_pickup_interactable.interacted.connect(_on_care_kit_picked)
	var kit_target := _outline_object_meshes(
		self, "CareKitOutline", _collect_mesh_instances(_care_kit_mesh), "peris_care_kit", 0.65
	)
	_set_room_target_interaction_delegate(kit_target, _care_kit_pickup_interactable)
	if _care_kit_pickup_interactable.has_method("set_outline_target"):
		_care_kit_pickup_interactable.set_outline_target(kit_target)


func _on_care_kit_picked() -> void:
	if _current_step != "care_operations" or _care_operation_stage != "collect_kit":
		return
	if _care_kit_item_id == "" or not _game_state.pick_up_item("peris", _care_kit_item_id):
		_show_care_audit_prompt("CARE PLAN · FREE PERIS'S HAND, THEN TAKE THE FIELD KIT.", 6.0)
		_rearm_care_interactable(_care_kit_pickup_interactable)
		return
	_care_kit_held = true
	if _care_kit_mesh != null:
		_care_kit_mesh.visible = false
	if _care_kit_pickup_interactable != null:
		_care_kit_pickup_interactable.set_interaction_enabled(false)
	_start_care_operation_phase()


func _build_care_operation_interactables() -> void:
	if not _care_operation_interactables.is_empty():
		return
	for raw_phase in CARE_OPERATION_PHASES:
		var phase: Dictionary = raw_phase
		for raw_task in (phase.get("tasks", []) as Array):
			var task: Dictionary = raw_task
			var task_id := str(task.get("id", ""))
			var source_id := str(task.get("source", ""))
			var source_config: Dictionary = CARE_AUDIT_EVIDENCE_SOURCES.get(source_id, {})
			var source := find_child(str(source_config.get("zone", "")), true, false) as Node3D
			if task_id == "" or source == null:
				continue
			var parent := source.get_parent() as Node3D
			if parent == null:
				continue
			var task_interactable := _create_interactable(
				parent,
				source.position,
				"CareOperation%s" % task_id.capitalize().replace(" ", ""),
				float(source.get("interaction_radius")),
				CARE_OPERATION_WORK_SECONDS,
				str(task.get("label", task_id)),
				false,
				Interactable.InteractableType.TIMED_ACTION
			)
			task_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
			task_interactable.set("dwell_time", CARE_OPERATION_WORK_SECONDS)
			task_interactable.set("one_shot", false)
			task_interactable.set("required_character", "peris")
			task_interactable.set("description", "Care Operation: %s" % str(task.get("label", task_id)))
			task_interactable.set_meta("care_operation_task_id", task_id)
			task_interactable.set_meta("care_operation_source_id", source_id)
			task_interactable.set_meta("care_operation_phase_id", str(phase.get("id", "")))
			if source.has_meta("interaction_target_position"):
				task_interactable.set_meta("interaction_target_position", source.get_meta("interaction_target_position"))
			task_interactable.interacted.connect(_on_care_operation_task_completed.bind(task_id))
			task_interactable.set_interaction_enabled(false)
			_care_operation_interactables[task_id] = task_interactable


func _current_care_operation_phase() -> Dictionary:
	if _care_operation_phase_index < 0 or _care_operation_phase_index >= CARE_OPERATION_PHASES.size():
		return {}
	return CARE_OPERATION_PHASES[_care_operation_phase_index]


func _start_care_operation_phase() -> void:
	var phase := _current_care_operation_phase()
	if phase.is_empty():
		_complete_care_operations()
		return
	_care_operation_stage = "work"
	_care_operation_completed_tasks.clear()
	_care_operation_selected_candidate = ""
	_care_operation_resolution_id = ""
	if _care_operation_resolution_interactable != null \
			and is_instance_valid(_care_operation_resolution_interactable):
		_care_operation_resolution_interactable.set_interaction_enabled(false)
		_care_operation_resolution_interactable.queue_free()
	_care_operation_resolution_interactable = null
	if _explore_logbook_gate != null:
		_explore_logbook_gate.set_interaction_enabled(false)
	_set_care_operation_tasks_enabled(phase.get("tasks", []) as Array)
	_show_care_audit_prompt(
		"CARE PLAN %d/4 · %s\nComplete eight unique jobs. The last highlighted policy record chooses the physical resolution." % [
			_care_operation_phase_index + 1,
			str(phase.get("label", "OPERATION")),
		],
		9.0
	)


func _set_care_operation_tasks_enabled(tasks: Array) -> void:
	var required_ids: Array[String] = []
	for raw_task in tasks:
		required_ids.append(str((raw_task as Dictionary).get("id", "")))
	for raw_id in _care_operation_interactables:
		var task_id := str(raw_id)
		var interactable = _care_operation_interactables[task_id]
		if interactable == null or not is_instance_valid(interactable):
			continue
		if not required_ids.has(task_id):
			interactable.set_interaction_enabled(false)
			continue
		_rearm_care_interactable(interactable)
		var source_id := str(interactable.get_meta("care_operation_source_id", ""))
		_bind_care_operation_target(source_id, interactable)
		if interactable.has_method("show_tutorial_label"):
			interactable.call_deferred("show_tutorial_label")


func _bind_care_operation_target(source_id: String, interactable: Node) -> void:
	var config: Dictionary = CARE_AUDIT_EVIDENCE_SOURCES.get(source_id, {})
	var primary_target: Node = null
	for raw_target_name in (config.get("targets", []) as Array):
		var target := find_child(str(raw_target_name), true, false)
		if target == null:
			continue
		if primary_target == null:
			primary_target = target
		_set_room_target_interaction_delegate(target, interactable)
	if primary_target != null and interactable.has_method("set_outline_target"):
		interactable.set_outline_target(primary_target)


func _on_care_operation_task_completed(task_id: String) -> void:
	if _current_step != "care_operations" or _care_operation_stage != "work" or not _care_kit_is_held():
		return
	var phase := _current_care_operation_phase()
	var task_ids: Array[String] = []
	for raw_task in (phase.get("tasks", []) as Array):
		task_ids.append(str((raw_task as Dictionary).get("id", "")))
	if not task_ids.has(task_id) or bool(_care_operation_completed_tasks.get(task_id, false)):
		return
	_care_operation_completed_tasks[task_id] = true
	var interactable = _care_operation_interactables.get(task_id)
	if interactable != null and is_instance_valid(interactable):
		interactable.set_interaction_enabled(false)
	var candidates: Array = phase.get("candidates", [])
	if candidates.has(task_id):
		_care_operation_selected_candidate = task_id
	if _care_operation_completed_tasks.size() >= task_ids.size():
		_start_care_operation_resolution()
	else:
		_show_care_audit_prompt(
			"CARE PLAN %d/4 · %s · JOBS %d/%d" % [
				_care_operation_phase_index + 1,
				str(phase.get("label", "OPERATION")),
				_care_operation_completed_tasks.size(),
				task_ids.size(),
			],
			6.0
		)


func _start_care_operation_resolution() -> void:
	var phase := _current_care_operation_phase()
	var resolutions: Dictionary = phase.get("resolutions", {})
	var resolution: Dictionary = resolutions.get(_care_operation_selected_candidate, {})
	if resolution.is_empty():
		_show_care_audit_prompt("CARE PLAN · REVIEW BOTH POLICY RECORDS BEFORE RESOLUTION.", 7.0)
		return
	_care_operation_stage = "resolution"
	for interactable in _care_operation_interactables.values():
		if interactable != null and is_instance_valid(interactable):
			interactable.set_interaction_enabled(false)
	var source_id := str(resolution.get("source", ""))
	var source_config: Dictionary = CARE_AUDIT_EVIDENCE_SOURCES.get(source_id, {})
	var source := find_child(str(source_config.get("zone", "")), true, false) as Node3D
	if source == null:
		return
	var parent := source.get_parent() as Node3D
	if parent == null:
		return
	_care_operation_resolution_interactable = _create_interactable(
		parent,
		source.position,
		"CareResolution%s" % str(resolution.get("id", "resolution")).capitalize().replace(" ", ""),
		float(source.get("interaction_radius")),
		CARE_OPERATION_WORK_SECONDS,
		str(resolution.get("label", "RESOLVE PLAN")),
		false,
		Interactable.InteractableType.TIMED_ACTION
	)
	_care_operation_resolution_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_care_operation_resolution_interactable.set("dwell_time", CARE_OPERATION_WORK_SECONDS)
	_care_operation_resolution_interactable.set("one_shot", false)
	_care_operation_resolution_interactable.set("required_character", "peris")
	_care_operation_resolution_interactable.set("description", "Care Resolution: %s" % str(resolution.get("label", "")))
	_care_operation_resolution_interactable.set_meta("care_operation_resolution_id", str(resolution.get("id", "")))
	_care_operation_resolution_interactable.set_meta("care_operation_source_id", source_id)
	if source.has_meta("interaction_target_position"):
		_care_operation_resolution_interactable.set_meta(
			"interaction_target_position", source.get_meta("interaction_target_position")
		)
	_care_operation_resolution_interactable.interacted.connect(
		_on_care_operation_resolution_completed.bind(str(resolution.get("id", "")))
	)
	_bind_care_operation_target(source_id, _care_operation_resolution_interactable)
	if _care_operation_resolution_interactable.has_method("show_tutorial_label"):
		_care_operation_resolution_interactable.show_tutorial_label()
	_show_care_audit_prompt(
		"%s · ROUTE SELECTED\nComplete %s, then return to the logbook." % [
			str(phase.get("label", "OPERATION")),
			str(resolution.get("label", "THE RESOLUTION")),
		],
		8.0
	)


func _on_care_operation_resolution_completed(resolution_id: String) -> void:
	if _current_step != "care_operations" or _care_operation_stage != "resolution" \
			or not _care_kit_is_held():
		return
	_care_operation_resolution_id = resolution_id
	_care_operation_stage = "commit"
	if _care_operation_resolution_interactable != null:
		_care_operation_resolution_interactable.set_interaction_enabled(false)
	_rearm_care_interactable(_explore_logbook_gate)
	if _explore_logbook_gate != null and _explore_logbook_gate.has_method("show_tutorial_label"):
		_explore_logbook_gate.show_tutorial_label()
	_show_care_audit_prompt("CARE PLAN · RESOLUTION COMPLETE · RETURN TO THE LOGBOOK TO COMMIT.", 7.0)


func _on_care_operation_logbook_interacted() -> void:
	match _care_operation_stage:
		"commit":
			var phase := _current_care_operation_phase()
			_care_operation_decisions.append({
				"phase_id": str(phase.get("id", "")),
				"candidate": _care_operation_selected_candidate,
				"resolution_id": _care_operation_resolution_id,
			})
			_care_operation_phase_index += 1
			if _care_operation_phase_index >= CARE_OPERATION_PHASES.size():
				_complete_care_operations()
			else:
				_start_care_operation_phase()
		"return_kit":
			_return_care_operation_kit()
		"release":
			_explore_gate_fired = true
			_hide_thought()
			_start_monos_breakthrough()
		_:
			_show_care_audit_prompt("CARE PLAN · COMPLETE THE HIGHLIGHTED FIELD WORK FIRST.", 6.0)


func _complete_care_operations() -> void:
	_care_operations_complete = true
	_care_operation_stage = "return_kit"
	for interactable in _care_operation_interactables.values():
		if interactable != null and is_instance_valid(interactable):
			interactable.set_interaction_enabled(false)
	if _care_operation_resolution_interactable != null \
			and is_instance_valid(_care_operation_resolution_interactable):
		_care_operation_resolution_interactable.set_interaction_enabled(false)
	_rearm_care_interactable(_explore_logbook_gate)
	if _explore_logbook_gate != null and _explore_logbook_gate.has_method("show_tutorial_label"):
		_explore_logbook_gate.show_tutorial_label()
	_show_care_audit_prompt(
		"CARE PLAN COMPLETE · 4/4 OPERATIONS COMMITTED\nReturn the field kit at the logbook before releasing the connection.",
		9.0
	)


func _return_care_operation_kit() -> void:
	if not _care_kit_is_held():
		return
	_game_state.drop_item("peris", _care_kit_item_id)
	_care_kit_held = false
	_care_kit_returned = true
	if _care_kit_mesh != null:
		_care_kit_mesh.global_position = _care_logbook_contract_position() + Vector3(-0.35, 0.55, 0.0)
		_care_kit_mesh.visible = true
	_care_operation_stage = "release"
	_rearm_care_interactable(_explore_logbook_gate)
	if _explore_logbook_gate != null and _explore_logbook_gate.has_method("show_tutorial_label"):
		_explore_logbook_gate.show_tutorial_label()
	_show_care_audit_prompt(
		"FIELD KIT RETURNED · PLAN SEALED\nRight-click the logbook once more to release the waiting connection.",
		8.0
	)


func _care_kit_is_held() -> bool:
	if not _care_kit_held or _care_kit_item_id == "":
		return false
	var item: Dictionary = _game_state.items.get(_care_kit_item_id, {})
	return str(item.get("holder", "")) == "peris"

## Monos breaks through on a spoofed signal — not the scheduled client. He is
## panicked, apologetic for the channel, and discloses why he risked it.
## Turn Peris to face the portal — she works facing it (the session, the attack, casting Protect).
func _face_peris_to_portal() -> void:
	if _player == null:
		return
	var panel := _portal_panel_position()
	var target := Vector3(panel.x, _player.global_position.y, panel.z)
	if target.distance_to(_player.global_position) > 0.1:
		_player.look_at(target, Vector3.UP)

func _start_monos_breakthrough() -> void:
	_current_step = "monos_breakthrough"
	_face_peris_to_portal()
	_monos.visible = true
	_portal_light.light_color = Color(0.9, 0.6, 0.3)
	_portal_light.light_energy = 3.0
	_dialogue_chain([
		"peris_sim.monos.late",
		"peris_sim.peris.purpose",
		"peris_sim.monos.turn",
		"peris_sim.monos.opening",
		"peris_sim.monos.real",
		"peris_sim.monos.heart",
		"peris_sim.monos.mind",
		"peris_sim.peris.fight",
	], func():
		_scheduler.schedule_after(3.0, _start_transition_out, "transition_out")
	)

func _start_session_begins() -> void:
	_current_step = "session_begins"
	_face_peris_to_portal()
	_portal_tween_active = true
	var t := create_tween()
	t.tween_property(_portal_light, "light_energy", 4.0, 0.4)
	t.tween_property(_portal_light, "light_energy", 3.0, 0.6)
	t.tween_callback(func(): _portal_tween_active = false)
	_scheduler.schedule_after(2.0, _start_attack, "attack")

func _start_attack() -> void:
	_current_step = "attack"
	_attack_particles.visible = true
	_attack_particles.light_color = Color(0.9, 0.15, 0.05)
	_attack_particles.light_energy = 5.0
	_portal_light.light_color = Color(0.8, 0.2, 0.1)
	_camera.shake(0.15, 6.0)
	DialogueData.say_to(_dialogue, "peris_sim.monos.hit")
	DialogueData.say_to(_dialogue, "peris_sim.peris.alarm")
	DialogueData.say_to(_dialogue, "peris_sim.monos.help")
	DialogueData.say_to(_dialogue, "peris_sim.system.overtime")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_alert_monos, "alert_monos"),
		CONNECT_ONE_SHOT
	)

# --- Strict ordered tutorial sequence ---

func _start_alert_monos() -> void:
	_enter_step("alert_monos")
	# White "!" over Monos
	var alert := Label3D.new()
	alert.name = "AlertMark"
	alert.text = "!"
	alert.font_size = 72
	alert.pixel_size = 0.012
	alert.modulate = Color(1, 1, 1, 0.95)
	alert.outline_modulate = Color(0, 0, 0, 0.6)
	alert.outline_size = 5
	alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alert.position = Vector3(0, 1.8, 0)
	_monos.add_child(alert)
	_is_paused = true
	_player.set_move_enabled(false)
	if _hud:
		_hud.set_paused(true)
	_start_protect_prompt()

func _start_protect_prompt() -> void:
	_enter_step("protect_prompt")
	DialogueData.say_to(_dialogue, "peris_sim.peris.protect_him")
	_dialogue.dialogue_finished.connect(func():
		_tutorial_prompt.show_action_prompt(
			PROTECT_INPUT_ACTION,
			"Queue Protect",
			0.0,
			str(AbilityData.binding("protect").get("keybind", ""))
		)
	, CONNECT_ONE_SHOT)

func _start_run_prompt() -> void:
	_enter_step("run_prompt")
	_tutorial_prompt.show_action_prompt("run", "Toggle Run", 0.0, "R")
	if _hud:
		_hud.show_run_toggle(true)

func _start_click_monos() -> void:
	_enter_step("click_monos")
	_player.set_move_enabled(true)
	# Clicks select a target rather than move; the shared controller reports the
	# clicked ground position to _on_target_selected.
	_player.set_click_mode("select")
	if not _player.ground_clicked.is_connected(_on_target_selected):
		_player.ground_clicked.connect(_on_target_selected)
	_tutorial_prompt.show_action_prompt("select", "Select Monos as Protect target", 0.0, "LMB")

func _start_confirm_protect() -> void:
	_enter_step("confirm_protect")
	_protect_queued = true
	var shield := Label3D.new()
	shield.name = "ShieldMark"
	shield.text = "SHIELD"
	shield.font_size = 36
	shield.pixel_size = 0.01
	shield.modulate = Color(0.8, 0.6, 0.2, 0.9)
	shield.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shield.position = Vector3(0, 2.2, 0)
	_monos.add_child(shield)
	if _hud:
		_hud.set_ability_state("protect", "queued")
	_tutorial_prompt.show_action_prompt("pause", "Unpause", 0.0, "Space")

func _start_executing() -> void:
	_current_step = "executing"
	_is_paused = false
	if _hud:
		_hud.set_paused(false)
	_tutorial_prompt.hide_prompt()
	_hide_thought()
	# Queue Protect; GameState moves Peris into range.
	if _protect_queued:
		_protect_queued = false
		_game_state.queue_ability("peris", "protect", _layout_position("PortalStand", PORTAL_POS), 2.5, _fire_queued_protect)

func _on_protect_pressed() -> void:
	if _has_protected:
		return
	# The direct Peris ability slot is only valid at protect_prompt.
	if _current_step == "protect_prompt":
		_tutorial_prompt.hide_prompt()
		if _hud:
			_hud.set_ability_state("protect", "queued")
		_start_run_prompt()
		return
	if _current_step in ["alert_monos", "run_prompt", "click_monos", "confirm_protect"]:
		return

func _fire_queued_protect() -> void:
	_has_protected = true
	_face_peris_to_portal()
	_protect_end_tick = _scheduler.get_current_tick() + 5.0
	if _hud:
		_hud.set_ability_state("protect", "active", 5.0)
		_hud.show_message("Peris: PROTECT! Absorbing damage from nearby allies.", 2.0)
	_attack_particles.light_energy = 0.5
	_portal_light.light_color = Color(0.9, 0.7, 0.3)
	_portal_light.light_energy = 4.0
	_game_state.adjust_stat("peris", "stamina", -15.0)
	_scheduler.schedule_after(0, _start_aftermath, "aftermath")

func _start_aftermath() -> void:
	_current_step = "aftermath"
	_attack_particles.visible = false
	_portal_light.light_color = Color(0.8, 0.6, 0.3)
	_portal_light.light_energy = 2.0
	DialogueData.say_to(_dialogue, "peris_sim.monos.thanks")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_efficiency_log, "efficiency_log"),
		CONNECT_ONE_SHOT
	)

func _start_efficiency_log() -> void:
	_current_step = "efficiency_log"
	_efficiency_score = 62.0
	DialogueData.say_to(_dialogue, "peris_sim.system.complete")
	_monos.fade_out(1.5)
	# Sync portal closure with Monos fade.
	_portal_tween_active = true
	var t := create_tween()
	t.tween_property(_portal_light, "light_energy", 0.0, 1.5)
	t.parallel().tween_property(_portal_visual, "scale", Vector3(1.0, 0.0, 1.0), 1.5)
	t.tween_callback(func(): _portal_tween_active = false)
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(1.6, _start_sanction_notice, "sanction_notice"),
		CONNECT_ONE_SHOT
	)

func _start_sanction_notice() -> void:
	_current_step = "sanction_notice"
	_show_sanction_feed_visual(
		"SANCTION MODE",
		"CLIENT FEED DISCONNECTED\nCASELOAD REASSIGNED",
		Color(0.75, 0.82, 0.7)
	)
	DialogueData.say_to(_dialogue, "peris_sim.system.sanction_notice")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_sanction_feed, "sanction_feed"),
		CONNECT_ONE_SHOT
	)

func _start_sanction_feed() -> void:
	_current_step = "sanction_feed"
	_show_sanction_feed_visual(
		"RESTORATIVE MODE",
		"GEL LOOP\nSOAP LOOP\nPLANT TIMELAPSE",
		Color(0.6, 0.85, 0.78)
	)
	DialogueData.say_to(_dialogue, "peris_sim.system.wellness_feed")
	DialogueData.say_to(_dialogue, "peris_sim.peris.sanction_reaction")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_spiral_flash, "spiral_flash"),
		CONNECT_ONE_SHOT
	)

func _start_spiral_flash() -> void:
	_current_step = "spiral_flash"
	_show_sanction_feed_visual(
		"FRAME DROP",
		"SPIRAL SIGNAL DETECTED",
		Color(0.55, 0.65, 1.0)
	)
	DialogueData.say_to(_dialogue, "peris_sim.system.spiral_flash")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_retro, "retro"),
		CONNECT_ONE_SHOT
	)

func _start_retro() -> void:
	_current_step = "retro"
	_show_sanction_feed_visual(
		"RESTORATIVE MODE",
		"ARCHIVE FOOTAGE",
		Color(0.68, 0.78, 0.72)
	)
	DialogueData.say_to(_dialogue, "peris_sim.peris.retro")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_sim_bay_exit, "sim_bay_exit"),
		CONNECT_ONE_SHOT
	)

func _start_sim_bay_exit() -> void:
	_current_step = "sim_bay_exit"
	_player.set_move_enabled(false)
	if _sanction_feed_label:
		_sanction_feed_label.visible = false
	DialogueData.say_to(_dialogue, "peris_sim.worker.okay")
	DialogueData.say_to(_dialogue, "peris_sim.worker.medical")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_transition_out, "transition_out"),
		CONNECT_ONE_SHOT
	)

func _start_transition_out() -> void:
	_current_step = "transition_out"
	_player.set_move_enabled(false)
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(2.5, _complete, "complete")

func _complete() -> void:
	_current_step = "complete"
	if _visit_phase == 1:
		# First half opens the game, then hands off to Aster's sim.
		_visit_phase = 2
		_change_scene_or_record("res://scenes/tutorial/aster_sim.tscn")
	else:
		# Second half (Monos session) leads into Tag Day.
		_change_scene_or_record("res://scenes/tutorial/tag_day.tscn")

# Run/pause/protect keys arrive as HUD signals (run_toggled / pause_toggled /
# ability_pressed), mapped from the input map by GameHUD — see _setup_ui.

# --- Environment ---

## ScenePlacement retains measured fallback/approach markers. Visible placement is owned by the
## editor-authored nodes under PerisRoom.
func get_room_layout_problems() -> Array[String]:
	return _room_layout_problems.duplicate()


func _validate_room_plan() -> void:
	var placement := find_child(PLACEMENT_ROOT, true, false)
	if placement == null:
		_room_layout_problems.append("ScenePlacement floor plan is missing")
		return
	var room_plan := placement.find_child("RoomPlan", true, false)
	if room_plan == null:
		_room_layout_problems.append("RoomPlan measurement guide is missing")
	elif "room_size" in room_plan:
		var measured_size: Vector2 = room_plan.get("room_size")
		if not measured_size.is_equal_approx(Vector2(GRID_SIZE)):
			_room_layout_problems.append("RoomPlan is %s but the movement grid is %s" % [measured_size, GRID_SIZE])

	for marker_name in REQUIRED_ROOM_MARKERS:
		var marker := placement.find_child(marker_name, true, false) as Node3D
		if marker == null:
			_room_layout_problems.append("missing placement marker '%s'" % marker_name)
			continue
		var p := marker.global_position
		if p.x < 0.0 or p.x > GRID_SIZE.x or p.z < 0.0 or p.z > GRID_SIZE.y:
			_room_layout_problems.append("marker '%s' is outside the 14 m x 6 m room at %s" % [marker_name, p])
		var grid_axes: String = WALL_MOUNTED_GRID_AXES.get(marker_name, "xz")
		var is_off_grid := (grid_axes.contains("x") and not _is_room_grid_value(p.x)) \
			or (grid_axes.contains("z") and not _is_room_grid_value(p.z))
		if is_off_grid:
			_room_layout_problems.append("marker '%s' is off the %.1f m X/Z grid at %s" % [
				marker_name, ROOM_GRID_STEP, p])
		if marker.get_parent() != null and marker.get_parent().name == "FurnitureMarkers":
			var quarter_turns := marker.global_transform.basis.get_euler().y / (PI * 0.5)
			if absf(quarter_turns - roundf(quarter_turns)) > 0.001:
				_room_layout_problems.append("furniture marker '%s' is not aligned to a 90-degree axis" % marker_name)

	var room := find_child("PerisRoom", true, false) as Node3D
	if room == null:
		_room_layout_problems.append("authored PerisRoom node is missing")
	else:
		for node_name in REQUIRED_AUTHORED_ROOM_NODES:
			if room.find_child(node_name, true, false) == null:
				_room_layout_problems.append("missing editor-authored room node '%s'" % node_name)

	var monos := placement.find_child("MonosStart", true, false) as Node3D
	var protect := placement.find_child("PortalStand", true, false) as Node3D
	if monos != null and protect != null:
		var monos_cell := Vector2i(floori(monos.global_position.x), floori(monos.global_position.z))
		var protect_cell := Vector2i(floori(protect.global_position.x), floori(protect.global_position.z))
		if monos_cell == protect_cell:
			_room_layout_problems.append("MonosStart and PortalStand reserve the same grid cell %s" % monos_cell)


func _is_room_grid_value(value: float) -> bool:
	return absf(value / ROOM_GRID_STEP - roundf(value / ROOM_GRID_STEP)) <= 0.001

func _build_environment() -> void:
	# Static geometry, props, collision, and lighting live in peris_sim.tscn. Runtime setup only
	# validates and binds those authored nodes; it never creates a second invisible layout.
	_room_layout_problems.clear()
	_validate_room_plan()
	for problem in _room_layout_problems:
		push_warning("Peris room layout: %s" % problem)

# --- Portal ---

## The modeled portal is the wall-mounted frame; this builds only the GAMEPLAY portal layer
## (the morphing glow/light/attack flash and labels the session steps drive), in front of it.
func _build_portal() -> void:
	# The gameplay layers inherit the editor-authored portal transform.
	var portal_panel := _portal_panel_position()
	var portal_face := _portal_face()
	var portal_surface := portal_panel + portal_face * 0.10

	_portal_visual = MeshInstance3D.new()
	_portal_visual.name = "PortalGlowSurface"
	# The gameplay glow layer is a RING hugging the circular frame (the session/attack/sanction
	# flash colour), leaving the whole disc inside it free for the live view.
	var pv := TorusMesh.new()
	pv.inner_radius = 1.2
	pv.outer_radius = 1.42
	_portal_visual.mesh = pv
	var pvm := StandardMaterial3D.new()
	pvm.albedo_color = Color(0.8, 0.5, 0.2, 0.25)
	pvm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pvm.emission_enabled = true
	pvm.emission = Color(0.6, 0.35, 0.15)
	pvm.emission_energy_multiplier = 1.2
	pvm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal_visual.material_override = pvm
	# TorusMesh lies flat around Y; pitch it so the ring stands in the portal plane.
	_portal_visual.global_transform = Transform3D(
		_portal_basis() * Basis(Vector3.RIGHT, PI * 0.5), portal_surface)
	add_child(_portal_visual)

	_portal_light = OmniLight3D.new()
	_portal_light.position = portal_panel + portal_face * 0.5
	_portal_light.light_color = Color(0.8, 0.5, 0.25)
	_portal_light.light_energy = 1.5
	_portal_light.omni_range = 5.0
	add_child(_portal_light)

	_build_portal_view()

	_attack_particles = OmniLight3D.new()
	_attack_particles.position = _layout_position("MonosStart", MONOS_POS) + Vector3(0, 1.0, 0)
	_attack_particles.light_color = Color(0.9, 0.15, 0.05)
	_attack_particles.light_energy = 0
	_attack_particles.omni_range = 4.0
	_attack_particles.visible = false
	add_child(_attack_particles)

	var lbl := Label3D.new()
	lbl.text = "FEED TERMINAL"
	lbl.font_size = 22
	lbl.pixel_size = 0.006
	# Keep this as signage attached to the portal, not a screen-space banner that
	# grows over the entire room when the camera pulls back.
	lbl.fixed_size = false
	lbl.modulate = Color(0.7, 0.5, 0.3, 0.6)
	lbl.position = portal_surface + Vector3(0, 1.95, 0)  # clear of the frame ring's top arc
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)

	_sanction_feed_label = Label3D.new()
	_sanction_feed_label.name = "SanctionFeedLabel"
	_sanction_feed_label.text = ""
	_sanction_feed_label.font_size = 28
	_sanction_feed_label.pixel_size = 0.009
	_sanction_feed_label.modulate = Color(0.6, 0.85, 0.78, 0.95)
	_sanction_feed_label.outline_modulate = Color(0.03, 0.04, 0.03, 0.8)
	_sanction_feed_label.outline_size = 4
	_sanction_feed_label.position = portal_surface + portal_face * 0.1
	_sanction_feed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sanction_feed_label.visible = false
	add_child(_sanction_feed_label)

## The portal actually SHOWS what's through it: a SubViewport with its OWN World3D renders the connected
## room — where Monos stands — and that live view is textured onto the portal surface. Its own world keeps
## it fully self-contained (a true portal to ELSEWHERE, not a security-camera of this room), so there's no
## coupling to the main camera, no feedback, and Monos is visible through the portal before he steps through.
func _build_portal_view() -> void:
	_portal_view_vp = SubViewport.new()
	_portal_view_vp.name = "PortalViewViewport"
	_portal_view_vp.size = Vector2i(512, 512)    # resized to the live window each frame
	_portal_view_vp.own_world_3d = true          # a separate space beyond the portal
	_portal_view_vp.transparent_bg = false
	_portal_view_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_portal_view_vp.handle_input_locally = false
	add_child(_portal_view_vp)
	_build_monos_room(_portal_view_vp)

	# The modeled circular Portal_Surface disc IS the lens: the live view fills the whole
	# portal opening instead of a pasted quad. SCREEN_UV sampling + the mirrored viewport
	# camera make it read as a hole in the wall.
	var lens: MeshInstance3D = null
	var portal := _authored_room_node("Portal")
	if portal != null:
		for mi in portal.find_children("*", "MeshInstance3D", true, false):
			if String(mi.name).begins_with("Portal_Surface"):
				lens = mi
				break
	if lens == null:
		# Stripped test scenes have no modeled portal; a disc stands in so the layer exists.
		lens = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.14
		disc.bottom_radius = 1.14
		disc.height = 0.02
		lens.mesh = disc
		lens.global_transform = Transform3D(
			_portal_basis() * Basis(Vector3.RIGHT, PI * 0.5),
			_portal_panel_position() - _portal_face() * 0.02)
		add_child(lens)
	lens.name = "PortalViewSurface"
	var mat := ShaderMaterial.new()
	mat.shader = PORTAL_LENS_SHADER
	mat.set_shader_parameter("view_texture", _portal_view_vp.get_texture())
	lens.material_override = mat
	_portal_view_surface = lens

## Mirrors the live camera through the portal into the Monos-room world so the lens disc
## shows the connected room with true parallax. Rendering-only: nothing gameplay reads it.
func _update_portal_view() -> void:
	if _portal_view_vp == null or _portal_view_cam == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vp_size := Vector2i(get_viewport().get_visible_rect().size)
	if vp_size.x > 0 and vp_size.y > 0 and _portal_view_vp.size != vp_size:
		_portal_view_vp.size = vp_size
	var portal_xf := Transform3D(_portal_basis(), _portal_panel_position())
	var anchor := Transform3D(Basis(), MONOS_ROOM_PORTAL_ANCHOR)
	_portal_view_cam.fov = cam.fov
	_portal_view_cam.global_transform = anchor * (portal_xf.affine_inverse() * cam.global_transform)

## The space BEYOND the portal — a small graybox room with Monos standing in it, lit so it reads through
## the portal. Built into the SubViewport's own world. Stand-in geometry for now; swap for the real
## modeled facility room when it exists.
func _build_monos_room(vp: SubViewport) -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.5, 6.0)
	vp.add_child(cam)
	cam.look_at(Vector3(0.0, 1.6, -2.0), Vector3.UP)   # orient AFTER it's in the tree (look_at needs a global xform)
	_portal_view_cam = cam   # per-frame mirror of the live camera (rendering-only)
	# Lighting for the fresh world (no scene env): cool ambient + a key light, matching Peris's room mood.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.42, 0.52)
	e.ambient_light_energy = 1.0
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	key.light_color = Color(0.95, 0.88, 0.8)
	key.light_energy = 1.1
	vp.add_child(key)
	# Floor + back wall + side wall (graybox).
	var visual := MONOS_PORTAL_ROOM_VISUAL_SCENE.instantiate() as Node3D
	visual.name = "MonosPortalRoomVisual"
	vp.add_child(visual)
	# Monos stands at his console; a warm key over him makes the figure read
	# through the lens from gameplay camera angles.
	var glow := OmniLight3D.new()
	glow.position = Vector3(0.9, 2.2, -2.0)
	glow.light_color = Color(0.9, 0.62, 0.35)
	glow.light_energy = 2.6
	glow.omni_range = 5.0
	vp.add_child(glow)

func _show_sanction_feed_visual(title: String, body: String, color: Color) -> void:
	if _sanction_feed_label:
		_sanction_feed_label.text = "%s\n%s" % [title, body]
		_sanction_feed_label.modulate = Color(color.r, color.g, color.b, 0.95)
		_sanction_feed_label.visible = true
	if _portal_visual:
		_portal_visual.scale = Vector3.ONE
		var mat := _portal_visual.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(color.r, color.g, color.b, 0.3)
			mat.emission = color
			mat.emission_energy_multiplier = 1.8
	if _portal_light:
		_portal_light.light_color = color
		_portal_light.light_energy = 2.4

# --- Exploration objects (phase 1, pre-Monos-arrival) ---
# The modeled room (peris-sim.gltf + peris-furniture.gltf) carries all cosmetic decor — rug, shelves,
# sofas, props — so there is no procedural decoration pass; gameplay objects live below.

var _exploration_objects_built := false
var _exploration_interactables: Array = []

func _build_exploration_objects() -> void:
	# Idempotent: built at _begin (the room is dressed from the first frame); a direct
	# _start_workspace (tests) re-enters harmlessly. The watering beat is a REAL data-layer item,
	# so it exists only in the phase that plays it.
	if Engine.is_editor_hint() or _exploration_objects_built:
		return
	_exploration_objects_built = true
	var env: Node3D = self
	_build_peris_plants(env)
	if _visit_phase == 1:
		_build_watering_beat(env)
	else:
		var authored_can := _authored_room_node("WateringCan")
		if authored_can != null:
			authored_can.visible = false
	_build_peris_painting(env)
	_build_peris_wellness_feed(env)
	_build_peris_strike_warning(env)
	_build_peris_logbook_gate(env)
	# built before the workspace step: everything stays dark until the step arms it
	_set_exploration_armed(false)

func _set_exploration_armed(armed: bool) -> void:
	var can_held := false
	if _game_state != null and _watering_can_item_id != "":
		var item: Dictionary = _game_state.items.get(_watering_can_item_id, {})
		can_held = str(item.get("holder", "")) == "peris"
	for ia in _exploration_interactables:
		if ia != null and is_instance_valid(ia) and ia.has_method("set_interaction_enabled"):
			var enable := armed
			if ia == _water_plant_interactable:
				enable = armed and can_held and not _plant_watered
			elif ia == _can_pickup_interactable:
				enable = armed and not can_held and not _plant_watered
			elif ia == _explore_logbook_gate:
				# The logbook is a visible objective only once the full first-read
				# context and watering prerequisites are complete. Walking past it
				# earlier must not auto-dwell into a silent locked interaction.
				enable = armed and _care_context_ready
			ia.set_interaction_enabled(enable)

func _build_peris_plants(parent: Node3D) -> void:
	# Visual plants and tables are scene-authored. Runtime creates only their verbs and derives
	# collision/interaction positions from the movable nodes.
	var care_groups := ["shelf", "shelf", "client", "survivor", "shelf", "survivor", "fern", "client", "peace"]
	for i in range(care_groups.size()):
		var plant_number := i + 1
		var table := _authored_room_node("Plant%dTable" % plant_number)
		var plant_node := _authored_room_node("Plant%d" % plant_number)
		if table == null or plant_node == null:
			push_warning("Peris room is missing editor-authored Plant%d/table nodes" % plant_number)
			continue
		var table_pos := table.global_position
		if _grid != null:
			_grid.add_dynamic_blocker(_grid.world_to_grid(table_pos), "peris_plant_table_%d" % plant_number)

		var target := _outline_object_meshes(parent, "Plant%dOutline" % plant_number,
			_collect_mesh_instances(plant_node), "peris_plant_%d" % plant_number, 0.7)

		# The zone lives on the floor under the display — an elevated support (hanging basket,
		# bookshelf tray) must still meet the walking character's proximity dwell.
		var zone_pos := Vector3(table_pos.x, ROOM_FLOOR_Y, table_pos.z)
		var zone_name := "Plant%dZone" % plant_number
		var zone: Area3D
		if plant_number == 7:
			zone = _make_exploration_sequence_zone(parent, zone_pos, zone_name,
				["peris.sim_expand.plant_7.line", "peris.sim_expand.plant_7.line_repeat"], 0.7, 0.6)
		else:
			zone = _make_exploration_zone(parent, zone_pos, zone_name,
				"peris.sim_expand.plant_%d.line" % plant_number, 0.7, 0.6)
		zone.set_meta("interaction_target_position", _authored_floor_interaction_position(
			"Plant%dTable" % plant_number,
			"Plant%dApproach" % plant_number,
			Vector3(table_pos.x, 0.0, table_pos.z - 1.0),
			Vector3(0.0, 0.0, -1.0)
		))
		_exploration_interactables.append(zone)
		_register_care_context_zone(zone, "plant", str(care_groups[i]))
		_set_room_target_interaction_delegate(target, zone)
		if plant_number == 7:
			_fern_exploration_interactable = zone
			_fern_outline_target = target


## The watering can is a REAL item (spawn_item + pick_up_item), not a flag: the beat teaches the
## hand-slot inventory. The dry fern's water spot only accepts a character actually HOLDING it.
func _build_watering_beat(parent: Node3D) -> void:
	# The can sits on the floor beside Peris's kiosk, mirrored by a data-layer item. Separating it
	# from the fern turns the beat back into an actual carry instead of two overlapping auto-dwells.
	var can_pos := _authored_position("WateringCan", "WateringCanAnchor", WATERING_CAN_POS)
	var fern_pos := _authored_position("Plant7Table", "Plant7TableAnchor", FERN_POS)
	_watering_can_mesh = _authored_room_node("WateringCan")
	if _watering_can_mesh == null:
		push_warning("Peris room is missing its editor-authored WateringCan")
		return
	_watering_can_mesh.visible = true

	_watering_can_item_id = _game_state.spawn_item("watering_can", can_pos)

	_can_pickup_interactable = _create_interactable(parent, can_pos, "WateringCanPickup",
		1.25, 0.7, "PICK UP", false)
	_can_pickup_interactable.interacted.connect(_on_watering_can_picked)
	_exploration_interactables.append(_can_pickup_interactable)
	var can_target := _outline_object_meshes(parent, "WateringCanOutline",
		_collect_mesh_instances(_watering_can_mesh), "watering_can", 0.5)
	_set_room_target_interaction_delegate(can_target, _can_pickup_interactable)
	# The PICK UP prompt shows when the workspace step arms the room (the can exists from the
	# first frame, but the intro fade is not the time to advertise it).

	# The water spot sits ON the fern (Plant7).
	_water_plant_interactable = _create_interactable(parent, fern_pos, "WaterPlantSpot",
		1.8, 0.9, "WATER", false)
	_water_plant_interactable.interacted.connect(_on_plant_watered)
	_exploration_interactables.append(_water_plant_interactable)

func _on_watering_can_picked() -> void:
	if _watering_can_item_id == "" or _plant_watered:
		return
	if not _game_state.pick_up_item("peris", _watering_can_item_id):
		return
	if _watering_can_mesh != null:
		_watering_can_mesh.visible = false
	if _can_pickup_interactable != null:
		_can_pickup_interactable.set_interaction_enabled(false)
	# The fern has two stateful verbs. Only one pick volume/delegate is active at
	# a time so INSPECT cannot steal the WATER command (or vice versa).
	if _fern_exploration_interactable != null:
		_fern_exploration_interactable.set_interaction_enabled(false)
	if _water_plant_interactable != null:
		_water_plant_interactable.set_interaction_enabled(true)
		_set_room_target_interaction_delegate(_fern_outline_target, _water_plant_interactable)
		if _water_plant_interactable.has_method("show_tutorial_label"):
			_water_plant_interactable.show_tutorial_label()

func _on_plant_watered() -> void:
	if _plant_watered:
		return
	var item: Dictionary = _game_state.items.get(_watering_can_item_id, {})
	if str(item.get("holder", "")) != "peris":
		return  # need the can in hand first (the WATER prompt only appears after pickup, so this is rare)
	_plant_watered = true
	_game_state.drop_item("peris", _watering_can_item_id)
	if _watering_can_mesh != null:
		_watering_can_mesh.global_position = _authored_position(
			"Plant7Table", "Plant7TableAnchor", FERN_POS
		) + Vector3(0.5, 0.6, 0.3)
		_watering_can_mesh.visible = true
	# The watering ACTION narration — Peris's habitual motion over the fern.
	_show_thought(DialogueData.text("peris.sim_expand.plant_7.look"))
	if _water_plant_interactable != null:
		_water_plant_interactable.set_interaction_enabled(false)
	if _fern_exploration_interactable != null:
		_fern_exploration_interactable.set_interaction_enabled(true)
		_set_room_target_interaction_delegate(_fern_outline_target, _fern_exploration_interactable)
	_maybe_unlock_exploration_gate()

func _maybe_unlock_exploration_gate() -> void:
	if not _explore_time_elapsed or not _plant_watered or not _care_context_complete():
		return
	if _care_context_ready:
		return
	_care_context_ready = true
	_ui_scheduler.cancel_tag("care_context_hint")
	_show_care_context_progress_hint()
	_rearm_care_interactable(_explore_logbook_gate)
	if _explore_logbook_gate != null:
		_explore_logbook_gate.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
		_explore_logbook_gate.set("dwell_time", CARE_AUDIT_WORK_SECONDS)
		if _explore_logbook_gate.has_method("show_tutorial_label"):
			_explore_logbook_gate.show_tutorial_label()

func _build_peris_painting(parent: Node3D) -> void:
	# The furniture GLTF already contains the measured wall art. Reuse it instead of laying a
	# second procedural painting over the same wall; retain a fallback for stripped test assets.
	var visual_meshes: Array = _room_binder.object_meshes(["WallArtFrame", "WallArt"])
	if visual_meshes.is_empty():
		push_warning("Peris room is missing the portable WallArt/WallArtFrame asset")
	var zone_pos := _authored_floor_interaction_position(
		"WallArtFrame", "PaintingZoneMarker", Vector3(8.5, 0, 0.5), Vector3(0, 0, 0.4)
	)
	var zone := _make_exploration_zone(parent,
		zone_pos,
		"PaintingZone",
		"peris.sim_expand.painting.line",
		1.3, 0.6)
	zone.set_meta("interaction_target_position", zone_pos + Vector3(0.5, 0, 1.0))
	_exploration_interactables.append(zone)
	_register_care_context_zone(zone, "painting", "PaintingZone")
	var target := _outline_object_meshes(parent, "PaintingOutline",
		visual_meshes, "peris_painting", 0.95)
	_set_room_target_interaction_delegate(target, zone)

func _build_peris_wellness_feed(parent: Node3D) -> void:
	# Mounted on the modeled left wall (X~0), near the back corner.
	var terminal := _authored_room_node("WellnessTerminal")
	if terminal == null:
		push_warning("Peris room is missing its editor-authored WellnessTerminal")
		return
	var zone_pos := _authored_floor_interaction_position(
		"WellnessTerminal", "WellnessZoneMarker", Vector3(0.5, 0, 0.5), Vector3(0.5, 0, 0)
	)
	var zone := _make_exploration_zone(parent,
		zone_pos,
		"WellnessZone",
		"peris.sim_expand.wellness.line",
		1.0, 0.6)
	zone.set_meta("interaction_target_position", zone_pos + Vector3(2.0, 0, 1.0))
	_exploration_interactables.append(zone)
	_register_care_context_zone(zone, "wellness", "WellnessZone")
	var target := _outline_object_meshes(parent, "WellnessOutline",
		_collect_mesh_instances(terminal), "peris_wellness", 0.8)
	_set_room_target_interaction_delegate(target, zone)

func _build_peris_strike_warning(parent: Node3D) -> void:
	# Pinned to the modeled right wall (X~14), near the open front corner.
	var notice := _authored_room_node("StrikeNotice")
	if notice == null:
		push_warning("Peris room is missing its editor-authored StrikeNotice")
		return
	var zone_pos := _authored_floor_interaction_position(
		"StrikeNotice", "StrikeWarningZoneMarker", Vector3(13.5, 0, 2.5), Vector3(-0.5, 0, 0)
	)
	var area := _make_exploration_zone(parent,
		zone_pos,
		"StrikeWarningZone",
		"",
		1.0, 0.8)  # re-inspectable: re-opening the warning replays the document + Peris's line
	area.set_meta("interaction_target_position", zone_pos + Vector3(-1.0, 0, 0))
	_exploration_interactables.append(area)
	area.connect("interacted", func():
		_play_focused_dialogue_keys([
			"peris.sim_expand.strike_warning.notification",
			"peris.sim_expand.strike_warning.line",
		], area)
	)
	_register_care_context_zone(area, "strike_warning", "StrikeWarningZone")
	var target := _outline_object_meshes(parent, "StrikeWarningOutline",
		_collect_mesh_instances(notice), "peris_strike_warning", 0.7)
	_set_room_target_interaction_delegate(target, area)

func _build_peris_logbook_gate(parent: Node3D) -> void:
	# Logbook is the gate to Monos — by the modeled bookshelf on the right side.
	var console := _authored_room_node("CareLogbookConsole")
	if console == null:
		push_warning("Peris room is missing its editor-authored CareLogbookConsole")
		return
	var pos := console.global_position
	var label := Label3D.new()
	label.name = "CareLogbookLabel"
	label.text = "CARE LOGBOOK"
	label.font_size = 26
	label.pixel_size = 0.006
	label.modulate = Color(0.72, 0.92, 0.82, 0.9)
	label.outline_modulate = Color(0.02, 0.03, 0.03, 0.9)
	label.outline_size = 5
	label.position = pos + Vector3(0.0, 0.72, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	var gate_pos := _authored_floor_interaction_position(
		"CareLogbookConsole", "LogbookGateMarker", Vector3(12.5, 0, 3.5), Vector3(-0.5, 0, 0)
	)
	var gate := _create_interactable(parent, gate_pos, "LogbookGate", 1.6, 0.8,
		"Continue", false, Interactable.InteractableType.HOLD_ACTION, "peris.logbook_gate")
	gate.connect("interacted", _on_exploration_gate_interacted)
	_explore_logbook_gate = gate
	_exploration_interactables.append(gate)
	var target := _outline_object_meshes(parent, "LogbookOutline",
		_collect_mesh_instances(console), "peris_logbook", 1.0)
	_set_room_target_interaction_delegate(target, gate)
