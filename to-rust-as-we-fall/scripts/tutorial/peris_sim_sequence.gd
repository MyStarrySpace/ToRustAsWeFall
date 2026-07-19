@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

## Peris simulation tutorial: run, stamina, Protect, and Monos.

@export_range(1, 2) var start_phase := 0
static var _visit_phase := 1

const PLACEMENT_ROOT := "ScenePlacement"
const ROOM_OCCUPANTS := [
	"Portal", "Kiosk", "PlantStand", "Armchair", "CoffeeTable",
	"Bookshelf", "bench", "couch",
]
const REQUIRED_ROOM_MARKERS := [
	"PortalAnchor", "KioskAnchor", "PlantStandAnchor", "ArmchairAnchor",
	"CoffeeTableAnchor", "BookshelfAnchor", "BenchAnchor", "CouchAnchor",
	"RugAnchor", "WallArtAnchor", "PerisStart", "MonosStart", "PortalStand",
	"WateringCanAnchor", "FernAnchor", "BookshelfPlantsZoneMarker",
	"PlantStandZoneMarker", "CoffeeTablePlantsZoneMarker", "PeaceLilyAnchor",
	"PaintingZoneMarker", "WellnessZoneMarker", "StrikeWarningZoneMarker",
	"LogbookConsoleAnchor", "LogbookGateMarker", "BookshelfPlantsApproach",
	"PlantStandApproach", "CoffeeTableApproach", "PaintingApproach", "WellnessApproach",
]

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
# portal surface, so the portal actually shows what's through it.
var _portal_view_vp: SubViewport
var _portal_view_surface: MeshInstance3D
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
const WATERING_CAN_POS := Vector3(10.99, 2.057, 1.1)  # upper shelf edge: approached from open cell (10, 1)
const FERN_POS := Vector3(3.4, 0.0, 2.0)  # Plant7 (Boston fern) — floor-standing watering target by the bench
# The watering beat drives the player to the dry fern; the input playthrough drives this point.
const DRY_PLANT_POS := FERN_POS

## Furniture surfaces MEASURED from the loaded room models (probe 2026-07-11). These defaults are
## refreshed from the authored furniture markers after layout, so furniture, surface rectangles, and
## every procedural plant move together. The peris-sim test verifies each Y against a live witness prop.
var PERIS_SURFACES := {
	"stand": {"y": 1.295, "rect": [1.38, 4.80, 2.26, 5.70]},         # PlantStand top
	"table": {"y": 0.805, "rect": [6.63, 2.47, 8.38, 3.53]},         # CoffeeTable top
	"shelf_low": {"y": 1.295, "rect": [10.95, 0.56, 13.05, 1.32]},   # Bookshelf lower board (Jar base)
	"shelf_high": {"y": 2.057, "rect": [10.95, 0.56, 13.05, 1.32]},  # Bookshelf photo board (Photo base)
}

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
	"BookshelfPlantsZone",
	"PlantStandZone",
	"CoffeeTablePlantsZone",
	"FernZone",
	"PeaceLilyZone",
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
	"bookshelf": {"zone": "BookshelfPlantsZone", "targets": ["Plant1Outline", "Plant2Outline", "Plant5Outline"], "label": "BOOKSHELF PLANTS"},
	"stand": {"zone": "PlantStandZone", "targets": ["Plant4Outline", "Plant6Outline"], "label": "SURVIVOR PLANTS"},
	"coffee": {"zone": "CoffeeTablePlantsZone", "targets": ["Plant3Outline", "Plant8Outline"], "label": "CLIENT PLANTS"},
	"fern": {"zone": "FernZone", "targets": ["Plant7Outline"], "label": "WATERING LOG"},
	"peace": {"zone": "PeaceLilyZone", "targets": ["Plant9Outline"], "label": "LEGACY PLANT"},
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

# The portal now sits on the WEST side wall facing the room (+X); the furniture turns to face it.
const PORTAL_PANEL := Vector3(0.5, 2.4, 3.0)   # portal panel centre on the west wall
const PORTAL_FACE := Vector3(1, 0, 0)          # the direction the portal faces (into the room)
const DESK_POS := Vector3(1.75, 0, 1.0)  # floor in front of the terminal (beside the portal)
const PORTAL_POS := Vector3(2.5, 0, 3.0)  # floor in front of the portal — clear space for Peris
const MONOS_POS := Vector3(3.5, 0, 2.5)  # open circulation cell, separate from the protect stand
const PROTECT_INPUT_ACTION := &"party_slot_2_ability_1"
const PERIS_START := Vector3(5.5, 0.5, 3.25)  # circulation lane, outside the can/fern auto-dwell radii

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

# The composed room visuals (shell + sofas) and the authored furniture/portal/props, both authored in
# the same Godot frame as the grid above.
const ROOM_GLTF := preload("res://resources/models/peris-sim/peris-sim.gltf")
const FURNITURE_GLTF := preload("res://resources/models/peris-sim/peris-furniture.gltf")


## The scene's Marker3Ds are the editable floor plan. Constants above are only
## deterministic fallbacks for tests/tools that instantiate the script without
## the authored placement tree.
func _layout_position(marker_name: String, fallback: Vector3) -> Vector3:
	var placement := find_child(PLACEMENT_ROOT, true, false)
	if placement == null:
		return fallback
	var marker := placement.find_child(marker_name, true, false) as Node3D
	return marker.global_position if marker != null else fallback


func _layout_yaw(marker_name: String, fallback_degrees: float) -> float:
	var placement := find_child(PLACEMENT_ROOT, true, false)
	if placement != null:
		var marker := placement.find_child(marker_name, true, false) as Node3D
		if marker != null:
			return marker.global_transform.basis.get_euler().y
	return deg_to_rad(fallback_degrees)


func _set_interaction_approach(interactable: Node, marker_name: String, fallback: Vector3) -> void:
	if interactable != null:
		interactable.set_meta("interaction_target_position", _layout_position(marker_name, fallback))


func _refresh_peris_surfaces() -> void:
	var stand := _layout_position("PlantStandAnchor", Vector3(1.75, 0.0, 5.25))
	var table := _layout_position("CoffeeTableAnchor", Vector3(7.5, 0.0, 3.0))
	var shelf := _layout_position("BookshelfAnchor", Vector3(12.0, 0.0, 0.95))
	PERIS_SURFACES = {
		"stand": {"y": stand.y + 1.295,
			"rect": [stand.x - 0.37, stand.z - 0.45, stand.x + 0.51, stand.z + 0.45]},
		"table": {"y": table.y + 0.805,
			"rect": [table.x - 0.87, table.z - 0.53, table.x + 0.88, table.z + 0.53]},
		"shelf_low": {"y": shelf.y + 1.295,
			"rect": [shelf.x - 1.05, shelf.z - 0.39, shelf.x + 1.05, shelf.z + 0.37]},
		"shelf_high": {"y": shelf.y + 2.057,
			"rect": [shelf.x - 1.05, shelf.z - 0.39, shelf.x + 1.05, shelf.z + 0.37]},
	}


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
	var can := _layout_position("WateringCanAnchor", WATERING_CAN_POS)
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
	return _layout_position("LogbookGateMarker", Vector3(12.0, 0.0, 3.0))

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
		"BookshelfPlantsZone":
			return "bookshelf plants"
		"PlantStandZone":
			return "survivor plants"
		"CoffeeTablePlantsZone":
			return "client plants"
		"FernZone":
			return "watering fern"
		"PeaceLilyZone":
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
	var kit_pos := _care_logbook_contract_position() + Vector3(-0.35, 0.55, 0.0)
	_care_kit_mesh = Node3D.new()
	_care_kit_mesh.name = "CareFieldKit"
	_care_kit_mesh.position = kit_pos
	add_child(_care_kit_mesh)
	var case_mesh := MeshInstance3D.new()
	var case_shape := BoxMesh.new()
	case_shape.size = Vector3(0.42, 0.22, 0.28)
	case_mesh.mesh = case_shape
	var case_material := StandardMaterial3D.new()
	case_material.albedo_color = Color(0.32, 0.42, 0.31)
	case_material.metallic = 0.25
	case_material.roughness = 0.55
	case_mesh.material_override = case_material
	_care_kit_mesh.add_child(case_mesh)
	var clasp := MeshInstance3D.new()
	var clasp_shape := BoxMesh.new()
	clasp_shape.size = Vector3(0.09, 0.08, 0.04)
	clasp.mesh = clasp_shape
	var clasp_material := StandardMaterial3D.new()
	clasp_material.albedo_color = Color(0.78, 0.58, 0.24)
	clasp_material.metallic = 0.7
	clasp.material_override = clasp_material
	clasp.position = Vector3(0.0, 0.0, 0.16)
	_care_kit_mesh.add_child(clasp)
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
		_care_kit_mesh.position = _care_logbook_contract_position() + Vector3(-0.35, 0.55, 0.0)
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
	var panel := _layout_position("PortalAnchor", PORTAL_PANEL)
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

## Re-lay-out the modeled room: portal onto the WEST side wall facing the room, the seating turned to
## face it, the terminal beside it, decor along the far walls — leaving the floor in front of the portal
## clear for Peris. The furniture are group nodes in the loaded model, so we set their transforms in the
## gameplay frame (preserving each group's scale; yaw only).
func _relayout_room(root: Node) -> void:
	# Every movable cluster has one measured Marker3D. Props move with their furniture as an
	# assembly, so a chair never leaves its plush behind and a future DCC re-export cannot quietly
	# scatter the room. The imported models remain the visual skin; ScenePlacement owns layout.
	_room_layout_problems.clear()
	_place_assembly(root, "Portal", "PortalAnchor", PORTAL_PANEL, 90.0, ["Portal"])
	_place_assembly(root, "Kiosk", "KioskAnchor", DESK_POS, 90.0, ["Kiosk"])
	_place_assembly(root, "PlantStand", "PlantStandAnchor", Vector3(1.75, 0.0, 5.25), 0.0,
		["PlantStand"])
	_place_assembly(root, "Armchair", "ArmchairAnchor", Vector3(4.0, 0.0, 4.75), -35.0,
		["Armchair", "Plush_Cat"])
	_place_assembly(root, "CoffeeTable", "CoffeeTableAnchor", Vector3(7.5, 0.0, 3.0), 0.0,
		["CoffeeTable", "Mug_Teal", "Mug_Cream", "CupSaucer"])
	_place_assembly(root, "Bookshelf", "BookshelfAnchor", Vector3(12.0, 0.0, 0.95), 0.0,
		["Bookshelf", "Jar", "BookStack", "Photo"])
	_place_assembly(root, "bench", "BenchAnchor", Vector3(5.625, 0.375, 0.75), 90.0, ["bench"])
	_place_assembly(root, "couch", "CouchAnchor", Vector3(9.25, 0.5, 0.75), 90.0,
		["couch", "Plush_Bear"])
	_place_assembly(root, "Rug", "RugAnchor", Vector3(7.0, 0.03, 3.2), 0.0, ["Rug"])
	_place_assembly(root, "WallArtFrame", "WallArtAnchor", Vector3(8.5, 3.3, 0.1), 0.0,
		["WallArtFrame", "WallArt"])
	_validate_room_plan()
	for problem in _room_layout_problems:
		push_warning("Peris room layout: %s" % problem)


func _place_assembly(
		root: Node,
		anchor_name: String,
		marker_name: String,
		fallback: Vector3,
		yaw_deg: float,
		member_names: Array
) -> void:
	var anchor := root.find_child(anchor_name, true, false) as Node3D
	if anchor == null:
		_room_layout_problems.append("missing modeled assembly anchor '%s'" % anchor_name)
		return
	var old_pivot := anchor.global_position
	var old_yaw := anchor.global_transform.basis.get_euler().y
	var yaw_delta := _layout_yaw(marker_name, yaw_deg) - old_yaw
	var delta_basis := Basis(Vector3.UP, yaw_delta)
	var target := _layout_position(marker_name, fallback)
	for raw_name in member_names:
		var member := root.find_child(str(raw_name), true, false) as Node3D
		if member == null:
			_room_layout_problems.append("assembly '%s' is missing member '%s'" % [anchor_name, str(raw_name)])
			continue
		var transform := member.global_transform
		transform.origin = target + delta_basis * (transform.origin - old_pivot)
		transform.basis = delta_basis * transform.basis
		member.global_transform = transform


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

	var monos := placement.find_child("MonosStart", true, false) as Node3D
	var protect := placement.find_child("PortalStand", true, false) as Node3D
	if monos != null and protect != null:
		var monos_cell := Vector2i(floori(monos.global_position.x), floori(monos.global_position.z))
		var protect_cell := Vector2i(floori(protect.global_position.x), floori(protect.global_position.z))
		if monos_cell == protect_cell:
			_room_layout_problems.append("MonosStart and PortalStand reserve the same grid cell %s" % monos_cell)

func _build_environment() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	# The modeled room is the scene's space: the Crocotile shell + sofas, and the authored
	# furniture / portal frame / props, both authored in the grid frame (X[0,14] Z[0,6]).
	var room := Node3D.new()
	room.name = "PerisRoom"
	add_child(room)
	var shell := ROOM_GLTF.instantiate()
	shell.name = "RoomShell"
	room.add_child(shell)
	var furniture := FURNITURE_GLTF.instantiate()
	furniture.name = "RoomFurniture"
	room.add_child(furniture)
	_relayout_room(room)
	_refresh_peris_surfaces()

	# The gltf carries no collision; a thin static slab over the floor footprint gives the shared
	# click-raycast a surface (layer 1, mask 0 — picked by the ground ray, collides with nothing).
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorCollision"
	floor_body.position = Vector3(GRID_SIZE.x * 0.5, ROOM_FLOOR_Y - 0.01, GRID_SIZE.y * 0.5)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(GRID_SIZE.x, 0.02, GRID_SIZE.y)
	fc.shape = fs
	floor_body.add_child(fc)
	env.add_child(floor_body)

	# Cool key + cool ambient (the original peris_room.tscn palette) — a calm lavender daylight, not the
	# warm/orange wash. The directional angle is unchanged; only the colours + glow match the old room.
	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-40, -20, 0)
	dir_light.light_color = Color(0.88, 0.9, 1.0)      # cool white
	dir_light.light_energy = 0.95
	dir_light.shadow_enabled = true
	env.add_child(dir_light)

	var room_fill := OmniLight3D.new()                 # gentle COOL fill so corners aren't black
	room_fill.position = Vector3(7, 2.8, 3)
	room_fill.light_color = Color(0.55, 0.6, 0.8)
	room_fill.light_energy = 1.2
	room_fill.omni_range = 12.0
	env.add_child(room_fill)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.07)        # cool dark, not warm brown
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4527142, 0.37521115, 0.5201956)   # the old room's cool lavender ambient
	e.ambient_light_energy = 0.6
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_bloom = 0.12
	we.environment = e
	env.add_child(we)

# --- Portal ---

## The modeled portal is the wall-mounted frame; this builds only the GAMEPLAY portal layer
## (the morphing glow/light/attack flash and labels the session steps drive), in front of it.
func _build_portal() -> void:
	# The modeled portal is on the WEST wall facing +X; the glow surface sits just in front of the panel.
	var portal_panel := _layout_position("PortalAnchor", PORTAL_PANEL)
	var portal_surface := portal_panel + PORTAL_FACE * 0.12

	_portal_visual = MeshInstance3D.new()
	var pv := BoxMesh.new()
	pv.size = Vector3(0.06, 2.0, 0.9)   # thin along X — the panel faces +X
	_portal_visual.mesh = pv
	var pvm := StandardMaterial3D.new()
	pvm.albedo_color = Color(0.8, 0.5, 0.2, 0.25)
	pvm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pvm.emission_enabled = true
	pvm.emission = Color(0.6, 0.35, 0.15)
	pvm.emission_energy_multiplier = 1.2
	pvm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal_visual.material_override = pvm
	_portal_visual.position = portal_surface
	add_child(_portal_visual)

	_portal_light = OmniLight3D.new()
	_portal_light.position = portal_panel + PORTAL_FACE * 0.5
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
	lbl.position = portal_surface + Vector3(0, 1.4, 0)
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
	_sanction_feed_label.position = portal_surface + Vector3(0, 0, 0.1)
	_sanction_feed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sanction_feed_label.visible = false
	add_child(_sanction_feed_label)

## The portal actually SHOWS what's through it: a SubViewport with its OWN World3D renders the connected
## room — where Monos stands — and that live view is textured onto the portal surface. Its own world keeps
## it fully self-contained (a true portal to ELSEWHERE, not a security-camera of this room), so there's no
## coupling to the main camera, no feedback, and Monos is visible through the portal before he steps through.
func _build_portal_view() -> void:
	_portal_view_vp = SubViewport.new()
	_portal_view_vp.size = Vector2i(288, 600)   # portrait, ~ the portal panel's 0.9w x 2.0h aspect
	_portal_view_vp.own_world_3d = true          # a separate space beyond the portal
	_portal_view_vp.transparent_bg = false
	_portal_view_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_portal_view_vp.handle_input_locally = false
	add_child(_portal_view_vp)
	_build_monos_room(_portal_view_vp)

	_portal_view_surface = MeshInstance3D.new()
	_portal_view_surface.name = "PortalViewSurface"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 1.9)
	_portal_view_surface.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _portal_view_vp.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_portal_view_surface.material_override = mat
	# Just in front of the panel; the quad's +Z normal rotated to PORTAL_FACE (+X) faces the room.
	_portal_view_surface.position = _layout_position("PortalAnchor", PORTAL_PANEL) + PORTAL_FACE * 0.14
	_portal_view_surface.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
	add_child(_portal_view_surface)

## The space BEYOND the portal — a small graybox room with Monos standing in it, lit so it reads through
## the portal. Built into the SubViewport's own world. Stand-in geometry for now; swap for the real
## modeled facility room when it exists.
func _build_monos_room(vp: SubViewport) -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.5, 5.4)
	cam.fov = 52.0
	vp.add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)   # orient AFTER it's in the tree (look_at needs a global xform)
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
	_portal_room_box(vp, Vector3(0, -0.1, 0), Vector3(8, 0.2, 8), Color(0.13, 0.13, 0.16))
	_portal_room_box(vp, Vector3(0, 1.8, -3.6), Vector3(8, 3.6, 0.2), Color(0.16, 0.15, 0.19))
	_portal_room_box(vp, Vector3(-3.6, 1.8, 0), Vector3(0.2, 3.6, 8), Color(0.15, 0.14, 0.18))
	# Monos — a standing figure in his color, so the portal reads as "Monos's room".
	var body := _portal_room_box(vp, Vector3(0, 0.85, 0), Vector3(0.5, 1.0, 0.5), Color(0.6, 0.5, 0.35))
	var bm := CapsuleMesh.new()
	bm.radius = 0.26
	bm.height = 1.3
	body.mesh = bm
	var head := _portal_room_box(vp, Vector3(0, 1.62, 0), Vector3(0.34, 0.34, 0.34), Color(0.66, 0.56, 0.4))
	var hm := SphereMesh.new()
	hm.radius = 0.2
	hm.height = 0.4
	head.mesh = hm
	# A soft portal glow behind Monos (the connection back to Peris's portal).
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 1.4, -2.0)
	glow.light_color = Color(0.8, 0.5, 0.25)
	glow.light_energy = 2.0
	glow.omni_range = 6.0
	vp.add_child(glow)

func _portal_room_box(vp: SubViewport, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	mi.position = pos
	vp.add_child(mi)
	return mi

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

# The plant gltfs export at WILDLY different native scales (boston_fern ~2.9 tall, haworthia ~1.4),
# all pot-at-Y0 and XZ-centered on their own origin. These are the measured native AABB heights — a
# uniform scale of target/native normalizes each instance deterministically (no per-frame AABB read,
# so movement/replay stay deterministic), and the pot lands on the floor at `pos`.
const PLANT_NATIVE_HEIGHT := {
	"boston_fern": 2.94, "calathea": 3.32, "haworthia": 1.36, "jade": 2.57,
	"jasmine": 2.69, "peace_lily": 4.58, "pilea": 3.48, "pothos": 2.81, "spider": 3.93,
}

## Instance a plant gltf, normalized to `target_height` and grounded so its pot sits at `pos`.
func _make_peris_plant(parent: Node3D, pos: Vector3, species: String, target_height: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var native: float = float(PLANT_NATIVE_HEIGHT.get(species, 1.0))
	var s := target_height / native if native > 0.0 else 1.0
	var gltf: PackedScene = load("res://resources/models/peris-sim/plants/plant_%s.gltf" % species)
	if gltf != null:
		var inst := gltf.instantiate() as Node3D
		inst.scale = Vector3(s, s, s)  # uniform — the pot stays at the model origin (Y=0)
		root.add_child(inst)
	return root

func _build_peris_plants(parent: Node3D) -> void:
	# Potted plants sit ON their furniture at the MEASURED surface heights (PERIS_SURFACES): small
	# pots across the two bookshelf boards, the coffee table (clear of the modeled mugs) and the
	# plant stand. Only the Boston fern (Plant7, the watering target — a walk-up beat) and the big
	# peace lily stand on the floor, deliberately. Furniture-mates SHARE one walk-to inspection
	# zone that advances through their lines on repeat clicks (per-plant zones could not keep the
	# 2.8 m inspectable spacing once the pots clustered onto shared surfaces); every pot still
	# carries its OWN outline target, delegating to its furniture's zone.
	var stand_anchor := _layout_position("PlantStandAnchor", Vector3(1.75, 0.0, 5.25))
	var table_anchor := _layout_position("CoffeeTableAnchor", Vector3(7.5, 0.0, 3.0))
	var shelf_anchor := _layout_position("BookshelfAnchor", Vector3(12.0, 0.0, 0.95))
	var fern_pos := _layout_position("FernAnchor", FERN_POS)
	var peace_lily_pos := _layout_position("PeaceLilyAnchor", Vector3(9.3, 0.0, 5.3))
	var plants := [  # [surface key ("" = floor), xz, species, target height]
		["shelf_low", Vector2(shelf_anchor.x + 0.75, shelf_anchor.z - 0.01), "spider", 0.55], # Plant1
		["shelf_high", Vector2(shelf_anchor.x + 0.75, shelf_anchor.z - 0.01), "calathea", 0.50], # Plant2
		["table", Vector2(table_anchor.x - 0.55, table_anchor.z + 0.30), "haworthia", 0.32], # Plant3
		["stand", Vector2(stand_anchor.x - 0.15, stand_anchor.z - 0.15), "jade", 0.62],  # Plant4
		["shelf_low", Vector2(shelf_anchor.x, shelf_anchor.z - 0.01), "jasmine", 0.55], # Plant5
		["stand", Vector2(stand_anchor.x + 0.22, stand_anchor.z + 0.13), "pothos", 0.55], # Plant6
		["", Vector2(fern_pos.x, fern_pos.z), "boston_fern", 1.3],  # Plant7 — the watering target
		["table", Vector2(table_anchor.x + 0.12, table_anchor.z - 0.28), "pilea", 0.42], # Plant8
		["", Vector2(peace_lily_pos.x, peace_lily_pos.z), "peace_lily", 1.4], # Plant9
	]
	var plant_targets: Array = []
	for i in range(plants.size()):
		var p: Array = plants[i]
		var skey: String = p[0]
		var xz: Vector2 = p[1]
		var y := 0.0 if skey == "" else float((PERIS_SURFACES[skey] as Dictionary)["y"])
		var plant_node := _make_peris_plant(parent, Vector3(xz.x, y, xz.y), str(p[2]), float(p[3]))
		plant_node.name = "Plant%d" % (i + 1)
		plant_targets.append(_outline_object_meshes(parent, "Plant%dOutline" % (i + 1),
			_collect_mesh_instances(plant_node), "peris_plant_%d" % (i + 1), 0.7))
	# One inspection zone per furniture group / floor plant (floor spots, spaced >=2.8 m from every
	# other inspectable — the --test-peris-sim spacing guard). Repeat clicks walk a shelf's lines.
	var zone_defs := [  # [name, floor pos, plant indices (1-based, line order)]
		["BookshelfPlantsZone", _layout_position("BookshelfPlantsZoneMarker", Vector3(13.7, 0, 0.6)), [1, 2, 5]],
		["PlantStandZone", _layout_position("PlantStandZoneMarker", Vector3(1.75, 0, 5.25)), [4, 6]],
		["CoffeeTablePlantsZone", _layout_position("CoffeeTablePlantsZoneMarker", Vector3(6.8, 0, 3.4)), [3, 8]],
		["FernZone", Vector3(fern_pos.x, 0, fern_pos.z), [7]],
		["PeaceLilyZone", Vector3(peace_lily_pos.x, 0, peace_lily_pos.z), [9]],
	]
	for zd_v in zone_defs:
		var zd := zd_v as Array
		var idxs: Array = zd[2]
		var zone: Area3D
		if idxs == [7]:  # the fern: the watering-tradition line advances to a follow-up on re-inspection
			zone = _make_exploration_sequence_zone(parent, zd[1] as Vector3, str(zd[0]),
				["peris.sim_expand.plant_7.line", "peris.sim_expand.plant_7.line_repeat"], 1.0, 0.6)
		elif idxs.size() == 1:
			zone = _make_exploration_zone(parent, zd[1] as Vector3, str(zd[0]),
				"peris.sim_expand.plant_%d.line" % int(idxs[0]), 1.0, 0.6)
		else:
			var keys: Array = []
			for pi in idxs:
				keys.append("peris.sim_expand.plant_%d.line" % int(pi))
			zone = _make_exploration_sequence_zone(parent, zd[1] as Vector3, str(zd[0]), keys, 1.0, 0.6)
		_exploration_interactables.append(zone)
		_register_care_context_zone(zone, "plant", str(zd[0]))
		match str(zd[0]):
			"BookshelfPlantsZone":
				_set_interaction_approach(zone, "BookshelfPlantsApproach", Vector3(13.5, 0, 2.0))
			"PlantStandZone":
				_set_interaction_approach(zone, "PlantStandApproach", Vector3(1.5, 0, 4.5))
			"CoffeeTablePlantsZone":
				_set_interaction_approach(zone, "CoffeeTableApproach", Vector3(5.5, 0, 3.0))
		for pi2 in idxs:
			var target = plant_targets[int(pi2) - 1]
			_set_room_target_interaction_delegate(target, zone)
			if int(pi2) == 7:
				_fern_exploration_interactable = zone
				_fern_outline_target = target

## The watering can is a REAL item (spawn_item + pick_up_item), not a flag: the beat teaches the
## hand-slot inventory. The dry fern's water spot only accepts a character actually HOLDING it.
func _build_watering_beat(parent: Node3D) -> void:
	# The can: a small kettle on the bookshelf, mirrored by a data-layer item. Separating it from
	# the fern turns the beat back into an actual carry instead of two overlapping auto-dwells.
	var can_pos := _layout_position("WateringCanAnchor", WATERING_CAN_POS)
	var fern_pos := _layout_position("FernAnchor", FERN_POS)
	_watering_can_mesh = Node3D.new()
	_watering_can_mesh.name = "WateringCan"
	_watering_can_mesh.position = can_pos
	parent.add_child(_watering_can_mesh)
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.12
	bm.bottom_radius = 0.16
	bm.height = 0.26
	body.mesh = bm
	var can_mat := StandardMaterial3D.new()
	can_mat.albedo_color = Color(0.45, 0.55, 0.6)
	can_mat.metallic = 0.5
	can_mat.roughness = 0.35
	body.material_override = can_mat
	body.position = Vector3(0, 0.13, 0)
	_watering_can_mesh.add_child(body)
	var spout := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.22, 0.04, 0.04)
	spout.mesh = sm
	spout.material_override = can_mat
	spout.position = Vector3(0.18, 0.18, 0.0)
	spout.rotation.z = 0.5
	_watering_can_mesh.add_child(spout)

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
		_watering_can_mesh.position = _layout_position("FernAnchor", FERN_POS) + Vector3(0.5, 0.0, 0.3)
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
		var pos := Vector3(8.5, 2.2, 0.12)
		var frame := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(1.2, 0.85, 0.06)
		frame.mesh = fb
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.2, 0.14, 0.1)
		frame.material_override = fm
		frame.position = pos
		parent.add_child(frame)
		var canvas := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(1.1, 0.75, 0.05)
		canvas.mesh = cb
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.55, 0.38, 0.45)
		cm.roughness = 0.6
		canvas.material_override = cm
		canvas.position = pos + Vector3(0, 0, 0.04)
		parent.add_child(canvas)
		visual_meshes = [frame, canvas]
	var zone := _make_exploration_zone(parent,
		_layout_position("PaintingZoneMarker", Vector3(8.5, 0, 0.3)),
		"PaintingZone",
		"peris.sim_expand.painting.line",
		1.3, 0.6)
	_set_interaction_approach(zone, "PaintingApproach", Vector3(10.5, 0, 1.5))
	_exploration_interactables.append(zone)
	_register_care_context_zone(zone, "painting", "PaintingZone")
	var target := _outline_object_meshes(parent, "PaintingOutline",
		visual_meshes, "peris_painting", 0.95)
	_set_room_target_interaction_delegate(target, zone)

func _build_peris_wellness_feed(parent: Node3D) -> void:
	# Mounted on the modeled left wall (X~0), near the back corner.
	var pos := Vector3(0.12, 1.6, 0.6)
	var screen := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.04, 0.5, 0.8)
	screen.mesh = sb
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.35, 0.4, 0.5, 0.85)
	sm.emission_enabled = true
	sm.emission = Color(0.3, 0.4, 0.55)
	sm.emission_energy_multiplier = 0.9
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override = sm
	screen.position = pos
	parent.add_child(screen)
	var zone := _make_exploration_zone(parent,
		_layout_position("WellnessZoneMarker", Vector3(0.7, 0, 0.3)),
		"WellnessZone",
		"peris.sim_expand.wellness.line",
		1.0, 0.6)
	_set_interaction_approach(zone, "WellnessApproach", Vector3(1.5, 0, 2.5))
	_exploration_interactables.append(zone)
	_register_care_context_zone(zone, "wellness", "WellnessZone")
	var target := _outline_object_meshes(parent, "WellnessOutline",
		[screen], "peris_wellness", 0.8)
	_set_room_target_interaction_delegate(target, zone)

func _build_peris_strike_warning(parent: Node3D) -> void:
	# Pinned to the modeled right wall (X~14), near the open front corner.
	var pos := Vector3(13.88, 1.8, 5.6)
	var icon := MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(0.04, 0.55, 0.4)
	icon.mesh = ib
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(0.85, 0.8, 0.68)
	im.emission_enabled = true
	im.emission = Color(0.3, 0.25, 0.18)
	im.emission_energy_multiplier = 0.2
	icon.material_override = im
	icon.position = pos
	parent.add_child(icon)
	var strip := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.045, 0.08, 0.4)
	strip.mesh = rb
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.5, 0.2, 0.2)
	strip.material_override = rm
	strip.position = pos + Vector3(-0.001, 0.24, 0)
	parent.add_child(strip)
	var area := _make_exploration_zone(parent,
		_layout_position("StrikeWarningZoneMarker", Vector3(13.4, 0, 5.6)),
		"StrikeWarningZone",
		"",
		1.0, 0.8)  # re-inspectable: re-opening the warning replays the document + Peris's line
	_set_interaction_approach(area, "StrikeWarningApproach", Vector3(12.5, 0.0, 4.5))
	_exploration_interactables.append(area)
	area.connect("interacted", func():
		_play_focused_dialogue_keys([
			"peris.sim_expand.strike_warning.notification",
			"peris.sim_expand.strike_warning.line",
		], area)
	)
	_register_care_context_zone(area, "strike_warning", "StrikeWarningZone")
	var target := _outline_object_meshes(parent, "StrikeWarningOutline",
		[icon, strip], "peris_strike_warning", 0.7)
	_set_room_target_interaction_delegate(target, area)

func _build_peris_logbook_gate(parent: Node3D) -> void:
	# Logbook is the gate to Monos — by the modeled bookshelf on the right side.
	var pos := _layout_position("LogbookConsoleAnchor", Vector3(11.3, 0.9, 3.0))
	var console := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.5, 1.0, 0.4)
	console.mesh = cb
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.2, 0.22, 0.25)
	console.material_override = cm
	console.position = pos
	parent.add_child(console)
	var screen := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.45, 0.45, 0.04)
	screen.mesh = sb
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.75, 0.55, 0.35)
	sm.emission_enabled = true
	sm.emission = Color(0.65, 0.45, 0.25)
	sm.emission_energy_multiplier = 0.8
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override = sm
	screen.position = pos + Vector3(0, 0.1, 0.22)
	parent.add_child(screen)
	var gate_pos := _layout_position("LogbookGateMarker", Vector3(pos.x + 0.7, 0, pos.z))
	var gate := _create_interactable(parent, gate_pos, "LogbookGate", 1.6, 0.8,
		"Continue", false, Interactable.InteractableType.HOLD_ACTION, "peris.logbook_gate")
	gate.connect("interacted", _on_exploration_gate_interacted)
	_explore_logbook_gate = gate
	_exploration_interactables.append(gate)
	var target := _outline_object_meshes(parent, "LogbookOutline",
		[console, screen], "peris_logbook", 1.0)
	_set_room_target_interaction_delegate(target, gate)
