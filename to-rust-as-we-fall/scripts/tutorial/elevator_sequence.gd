@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"
# @rendering_only_file: decorative timing/randomness only.

## Elevator tutorial through bridge collapse, route choice, and Endo's shelter.

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")

var _aster_node: CharacterBody3D
var _peris_node: CharacterBody3D
var _fall_landed_fired := false  # one-shot guard: bridge landing fires once
var _fall_tween: Tween           # the cosmetic fall animation (wall-clock)
var _fall_prev_offset_y := 12.0  # camera follow_offset.y before the fall dipped it (restored on landing)
var _fall_offset_dipped := false # true once _execute_bridge_fall dipped the camera (so landing knows to restore)
var _collapse_settle_tween: Tween
var _collapse_stagger_tweens: Array[Tween] = []
var _collapse_debris: Array[RigidBody3D] = []
var _collapse_paused_debris: Dictionary = {}
var _collapse_visual_paused := false
var _bridge_lines_pending: Array = []  # crossing dialogue fired by POSITION as the party walks the span
var _bridge_lines_fired := 0
var _collapsed_chunks_removed := false  # one-shot guard: old level chunks freed once
var _escort_1  # NPC
var _escort_2  # NPC
var _active_character := "peris"
var _selected_character_ids: Array[String] = ["peris"]
var _suppress_hud_character_signal := false

var _emergency_light: OmniLight3D
var _floor_indicator: Label3D
var _door_panel_a: MeshInstance3D
var _door_panel_b: MeshInstance3D
var _control_panel  # Interactable
var _indicator_timer := 0.0
var _indicator_b_label: Label3D  # The "B" that flickers
var _exit_button  # Interactable that flashes "NO EXIT".
var _aster_wake_interactable  # Interactable for waking knocked-out Aster
var _climb_interactable  # Interactable for checking the collapsed bridge
var _no_exit_label: Label3D

# Perception overlays are independent of the active portrait. Aster's data register is established when the
# elevator systems wake; Peris's memory register starts off so the post-fall fork can teach why turning it on
# matters. The route reads below are information states, not character-locked pedestal interactions.
var _elevator_overlay_states := {"aster": false, "peris": false}
var _elevator_overlays_available := false
var _elevator_overlay_ui: CanvasLayer
var _elevator_overlay_buttons: Dictionary = {}
var _elevator_overlay_status: Label
var _aster_route_overlay_root: Node3D
var _peris_route_overlay_root: Node3D
var _peris_route_overlay_endpoint: Node3D
var _route_reads_resolved := {"aster": false, "peris": false}
var _route_lane := ""
var _route_beats_crossed: Array[bool] = [false, false, false]
var _route_flure_interactables: Array = []
var _route_flure_meshes: Array[MeshInstance3D] = []
var _route_flure_enemy_groups: Dictionary = {}
var _route_flures_activated: Array[bool] = [false, false, false]
var _grated_platforms: Node3D
var _grated_platform_signal_marker: Marker3D
var _grated_platform_enemy_markers: Array[Marker3D] = []
var _grated_platform_wall_openings: Array[Marker3D] = []
var _wreckage_gate: Node3D
var _wreckage_interactable: Area3D
var _wreckage_listeners: Array[Enemy] = []
var _wreckage_armed := false
var _wreckage_cleared := false
var _wreckage_solo_attempted := false
var _wreckage_failure_active := false
var _wreckage_alert_target := ""

# Endo-junction exploration. The plant is the transition out of exploration,
# so it stays locked until the party has made three distinct reads with both
# perspectives and chosen one useful preparation.
var _junction_interactables: Dictionary = {}
var _junction_inspections: Dictionary = {}
var _junction_inspected_by := {"aster": false, "peris": false}
var _junction_prep_interactables: Dictionary = {}
var _junction_preparation := ""
var _junction_plant_interactable: Node
var _gauntlet_safe_window_bonus := 0.0
var _junction_field_interactables: Dictionary = {}
var _junction_field_evidence: Dictionary = {}
var _junction_field_choices: Dictionary = {}
var _junction_field_protocols_completed: Dictionary = {}
var _junction_field_protocol := ""
var _junction_field_findings: Array[String] = []

var _hud  # GameHUD

# EMP state
var _emp_count := 0
var _emp_queued := false
var _emp_pause_locked := false
var _emp_cooldown_end := 0.0  # scheduler tick when cooldown expires
var _emp_guard_approach_active := false
var _emp_guard_arrivals := {}
var _unit_1_stunned := false
var _unit_2_stunned := false
var _reboot_active := false
var _stamina := 100.0
var _emp_visual_root: Node3D
var _emp_animation_player: AnimationPlayer
var _emp_pulse_visual: MeshInstance3D
var _emp_pulse_core: MeshInstance3D
var _emp_pulse_light: OmniLight3D
var _emp_faceplates: Array = []
var _emp_faceplate_lights: Array = []
var _elevator_fill_light: OmniLight3D
var _elevator_indicator_glow: OmniLight3D
var _elevator_standby_lights: Array = []
var _elevator_powered := true

var _enemies: Array[Enemy] = []
var _enemy_count := 0
var _below_dormant_enemy_setups: Array[Dictionary] = []
# Landing enables the lower-deck ecology, but individual FSMs wake only when a
# lower-level party member enters their spatial band.  Cache the last cells so
# the proximity pass runs on cell changes, not every rendered frame.
var _below_fauna_active := false
var _below_activation_cells: Dictionary = {}
var _bridge_tile_materials: Dictionary = {}

# Party HP lives ONLY in GameState (the single source of truth): adjust_stat/get_stat. The HUD,
# downed state, and game-over all react to GameState's stat_changed via _on_party_stat_changed, so
# every damage source (enemy strikes, iron patches) just calls adjust_stat — no parallel counter.
const PARTY_MAX_HP := GameState.HP_MAX
var _game_over := false

# Iron hazard zones: Array of {pos: Vector3, size: Vector3}.
var _iron_patches: Array[Dictionary] = []
const IRON_DAMAGE_PER_SEC := 8.0
const IRON_DAMAGE_INTERVAL := 0.5
const IRON_DAMAGE_PER_TICK := IRON_DAMAGE_PER_SEC * IRON_DAMAGE_INTERVAL
const IRON_ROUTE_RISK_PENALTY := 80.0
const IRON_HAZARD_TAG := "elevator_iron_hazard"
var _iron_hazard_tick_armed := false
var _iron_route_risk_learned := false
var _damage_feedback_labels: Dictionary = {}
var _damage_feedback_tweens: Dictionary = {}
var _damage_feedback_counts: Dictionary = {}
var _iron_contact_warning_shown: Dictionary = {}

# Flure
var _flure_active := false
var _flure_mesh: MeshInstance3D
var _flure_interactable: Node
var _gauntlet_enemies: Array[Enemy] = []
var _gauntlet_enemy_groups := {0: [], 1: []}
var _gauntlet_flure_meshes: Array[MeshInstance3D] = []
var _gauntlet_flure_interactables: Array = []
var _gauntlet_flure_active := {0: false, 1: false}
var _gauntlet_active_stage := -1
var _gauntlet_stage := 0
var _gauntlet_midpoint_reached := false
var _gauntlet_strategy := ""
var _gauntlet_resetting := false
var _gauntlet_reset_count := 0
var _gauntlet_checkpoint_hp: Dictionary = {}

# Chunk system
@export var start_chunk := ""

# Endo (hidden until junction)
var _endo: Node3D
var _drink_mesh: MeshInstance3D  # Individual drink — carried by Endo

# Night watch
var _monster_eyes: Array[OmniLight3D] = []

const ELEVATOR_SIZE := Vector3(8.0, 4.0, 8.0)
const PERIS_START := Vector3(-1.0, 0.5, 1.5)
const ASTER_POS := Vector3(2.0, 0, -2.0)
const ESCORT_1_POS := Vector3(-2.5, 0, -2.5)
const ESCORT_2_POS := Vector3(-2.5, 0, 2.5)
const PANEL_POS := Vector3(3.5, 0, 0)
const EMP_GUARD_STANDOFF_DISTANCE := 2.6
const EMP_INPUT_ACTION := &"party_slot_1_ability_1"
const EMP_VISUAL_DURATION := 1.5

# Below-level ecology
const BELOW_Y := -4.0
const BRIDGE_START_X := 11.5  # ELEVATOR_SIZE.x/2 + 0.5 + 7.0
const BRIDGE_LENGTH := 24.0   # a real crossing (2x the old 12) so dialogue paces across the walk, not up front
const BRIDGE_END_X := BRIDGE_START_X + BRIDGE_LENGTH
const BRIDGE_COLLAPSE_X := BRIDGE_START_X + BRIDGE_LENGTH * 0.66  # the span gives way ~2/3 across, not after 4 steps
const BRIDGE_PIECES_PER_STREAM_STEP := 4
const BRIDGE_RAIL_Z := 1.4
const BRIDGE_END_LANDING_LENGTH := 4.0
const BRIDGE_BLOCKADE_X := BRIDGE_END_X + BRIDGE_END_LANDING_LENGTH

# The modeled elevator car SHELL (Blender, pixel-grid; floor grate is Geometry-Nodes): paneled walls,
# door opening + frame, ceiling light coffer, corner posts, control housing. Static; the sliding doors,
# emergency light, and floor indicators stay procedural in Godot because they animate.
const ELEVATOR_MODEL := preload("res://resources/models/elevator/elevator_car.glb")
const ENDO_JUNCTION_MODEL := preload("res://resources/models/elevator/endo-junction.glb")
const BRIDGE_LIGHTING_SCENE := preload("res://scenes/tutorial/elevator_bridge_lighting.tscn")
const LOWER_ROUTE_LIGHTING_SCENE := preload("res://scenes/tutorial/elevator_lower_route_lighting.tscn")
const LOWER_ROUTE_BLOCKADE_SCENE := preload("res://scenes/tutorial/elevator_lower_route_blockade.tscn")
const EMP_FACEPLATE_SCENE := preload("res://scenes/tutorial/elevator_emp_faceplate.tscn")
const GRATED_PLATFORMS_SCENE := preload("res://scenes/tutorial/elevator_grated_platforms.tscn")
const WRECKAGE_GATE_SCENE := preload("res://scenes/tutorial/elevator_wreckage_gate.tscn")
# Collapse debris physics layers (kept off every gameplay layer so debris never touches characters —
# they move on the grid, not via physics). Pieces collide ONLY with their own catch-floor (no inter-
# piece explosions from the initially-touching span).
const DEBRIS_PIECE_LAYER := 1 << 10
const DEBRIS_FLOOR_LAYER := 1 << 11
var _collapse_visual_active := false  # true while wall-clock debris physics is still settling

# Route fork. The old branch occupied only a few metres after the landing. The
# new course starts beyond the debris footprint and holds its two lanes for
# three readable beats before they converge.
const ROUTE_READ_ASTER_POS := Vector3(BRIDGE_COLLAPSE_X + 4.0, BELOW_Y + 0.05, -4.5)
const ROUTE_READ_PERIS_POS := Vector3(BRIDGE_COLLAPSE_X + 4.0, BELOW_Y + 0.05, 4.5)
const FORK_POS := Vector3(BRIDGE_COLLAPSE_X + 9.0, BELOW_Y, 0)
const ROUTE_BEAT_OFFSETS := [14.0, 38.0, 62.0]
const ROUTE_LANE_LENGTH := 78.0
const ENEMY_ROUTE_END := Vector3(FORK_POS.x + ROUTE_LANE_LENGTH, BELOW_Y, -4.0)
const HAZARD_ROUTE_END := Vector3(FORK_POS.x + ROUTE_LANE_LENGTH, BELOW_Y, 4.0)
const ROUTES_CONVERGE := Vector3(FORK_POS.x + ROUTE_LANE_LENGTH + 8.0, BELOW_Y, 0)
const ROUTE_FLURE_DURATION := 16.0
const ROUTE_REQUIRED_READS := 2
const ROUTE_BEAT_COUNT := 3
const GRATED_PLATFORM_ROUTE_BEAT := 1
const GRATED_PLATFORM_POS := Vector3(FORK_POS.x + 33.0, BELOW_Y, -10.0)
const WRECKAGE_GATE_POS := Vector3(ROUTES_CONVERGE.x + 5.0, BELOW_Y, 0.0)
const WRECKAGE_ASSIST_RADIUS := 3.25
const WRECKAGE_CLEAR_SECONDS := 1.15
const LOWER_ROUTE_WEST_X := BRIDGE_COLLAPSE_X - 5.0

# Endo junction and shelter
const JUNCTION_POS := Vector3(ROUTES_CONVERGE.x + 10.0, BELOW_Y, 0)
const SHELTER_SIZE := Vector3(6, 3, 5)
const JUNCTION_REQUIRED_INSPECTIONS := 3
# Aster's schematics cover the main facility out through Endo's junction (and its
# shelter); past this X the corridors are maintenance with no blueprints, so the
# data overlay goes dark.
const MAIN_FACILITY_MAX_X := JUNCTION_POS.x + SHELTER_SIZE.x

# Flure gauntlet: two packs, two lure stations, and a real midpoint refuge.
const GAUNTLET_POS := Vector3(JUNCTION_POS.x + 28.0, BELOW_Y, 0)
const GAUNTLET_MIDPOINT := Vector3(GAUNTLET_POS.x + 28.0, BELOW_Y, 0)
const FLURE_POS := Vector3(GAUNTLET_POS.x - 3.0, BELOW_Y + 0.3, 4.0)
const GAUNTLET_FLURE_2_POS := Vector3(GAUNTLET_MIDPOINT.x + 4.0, BELOW_Y + 0.3, -4.0)
const GAUNTLET_EXIT := Vector3(GAUNTLET_POS.x + 64.0, BELOW_Y, 0)
const FLURE_DURATION := 18.0

# A three-protocol service annex turns Endo's shelter survey into sustained, spatial preparation.
# Each clean path performs four specialist reads, one consequential plan, and one physical execution:
# 12x8s evidence + 3x8s plans + 3x14s executions = 162 seconds of click-gated fieldwork.
const JUNCTION_FIELD_PROTOCOL_ORDER := ["descent_power", "shelter_ecology", "relay_signal"]
const JUNCTION_FIELD_PROTOCOLS := {
	"descent_power": {
		"label": "DESCENT POWER RECOVERY",
		"evidence": ["power_drop", "power_bus", "power_ground", "power_load"],
		"choices": ["power_storage", "power_bypass"],
		"resolution_sites": {
			"power_storage": "power_storage_execution",
			"power_bypass": "power_bypass_execution",
		},
		"next": "shelter_ecology",
	},
	"shelter_ecology": {
		"label": "SHELTER ECOLOGY BALANCE",
		"evidence": ["ecology_root", "ecology_heat", "ecology_spore", "ecology_water"],
		"choices": ["ecology_warm", "ecology_sealed"],
		"resolution_sites": {
			"ecology_warm": "ecology_warm_execution",
			"ecology_sealed": "ecology_sealed_execution",
		},
		"next": "relay_signal",
	},
	"relay_signal": {
		"label": "FLURE RELAY CALIBRATION",
		"evidence": ["relay_echo", "relay_growth", "relay_timing", "relay_exit"],
		"choices": ["relay_safe", "relay_fast"],
		"resolution_sites": {
			"relay_safe": "relay_safe_execution",
			"relay_fast": "relay_fast_execution",
		},
		"next": "",
	},
}
const JUNCTION_FIELD_SITES := {
	"power_drop": {"protocol": "descent_power", "kind": "evidence", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 6.0, BELOW_Y + 0.05, -4.5), "dwell": 8.0, "verb": "MODEL DROP", "display": "VOLTAGE DROP"},
	"power_bus": {"protocol": "descent_power", "kind": "evidence", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 9.0, BELOW_Y + 0.05, -1.5), "dwell": 8.0, "verb": "READ LIVING BUS", "display": "LIVING BUS"},
	"power_ground": {"protocol": "descent_power", "kind": "evidence", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 12.0, BELOW_Y + 0.05, 1.5), "dwell": 8.0, "verb": "TRACE GROUND", "display": "GROUND PATH"},
	"power_load": {"protocol": "descent_power", "kind": "evidence", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 15.0, BELOW_Y + 0.05, 4.5), "dwell": 8.0, "verb": "FEEL LOAD", "display": "ROOT LOAD"},
	"power_storage": {"protocol": "descent_power", "kind": "choice", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 18.0, BELOW_Y + 0.05, -2.8), "dwell": 8.0, "verb": "PLAN STORAGE", "display": "STORE CHARGE"},
	"power_bypass": {"protocol": "descent_power", "kind": "choice", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 18.0, BELOW_Y + 0.05, 2.8), "dwell": 8.0, "verb": "PLAN BYPASS", "display": "ROOT BYPASS"},
	"power_storage_execution": {"protocol": "descent_power", "kind": "resolution", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 21.0, BELOW_Y + 0.05, -4.5), "dwell": 14.0, "verb": "SEAT CELL", "display": "SEAT STORAGE"},
	"power_bypass_execution": {"protocol": "descent_power", "kind": "resolution", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 21.0, BELOW_Y + 0.05, 4.5), "dwell": 14.0, "verb": "GRAFT BYPASS", "display": "GRAFT ROOT"},

	"ecology_root": {"protocol": "shelter_ecology", "kind": "evidence", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 24.0, BELOW_Y + 0.05, 4.5), "dwell": 8.0, "verb": "READ ROOT", "display": "ROOT HEALTH"},
	"ecology_heat": {"protocol": "shelter_ecology", "kind": "evidence", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 27.0, BELOW_Y + 0.05, 1.5), "dwell": 8.0, "verb": "MAP HEAT", "display": "HEAT VEIN"},
	"ecology_spore": {"protocol": "shelter_ecology", "kind": "evidence", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 30.0, BELOW_Y + 0.05, -1.5), "dwell": 8.0, "verb": "SAMPLE SPORE", "display": "SPORE LOAD"},
	"ecology_water": {"protocol": "shelter_ecology", "kind": "evidence", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 33.0, BELOW_Y + 0.05, -4.5), "dwell": 8.0, "verb": "TEST WATER", "display": "WATER LOOP"},
	"ecology_warm": {"protocol": "shelter_ecology", "kind": "choice", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 36.0, BELOW_Y + 0.05, 2.8), "dwell": 8.0, "verb": "PLAN WARM LOOP", "display": "WARM LOOP"},
	"ecology_sealed": {"protocol": "shelter_ecology", "kind": "choice", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 36.0, BELOW_Y + 0.05, -2.8), "dwell": 8.0, "verb": "PLAN HARD SEAL", "display": "HARD SEAL"},
	"ecology_warm_execution": {"protocol": "shelter_ecology", "kind": "resolution", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 39.0, BELOW_Y + 0.05, 4.5), "dwell": 14.0, "verb": "WAKE LOOP", "display": "WAKE ECOLOGY"},
	"ecology_sealed_execution": {"protocol": "shelter_ecology", "kind": "resolution", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 39.0, BELOW_Y + 0.05, -4.5), "dwell": 14.0, "verb": "DOG SEAL", "display": "DOG BULKHEAD"},

	"relay_echo": {"protocol": "relay_signal", "kind": "evidence", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 42.0, BELOW_Y + 0.05, -4.5), "dwell": 8.0, "verb": "MAP ECHO", "display": "RELAY ECHO"},
	"relay_growth": {"protocol": "relay_signal", "kind": "evidence", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 45.0, BELOW_Y + 0.05, -1.5), "dwell": 8.0, "verb": "READ GROWTH", "display": "FLURE GROWTH"},
	"relay_timing": {"protocol": "relay_signal", "kind": "evidence", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 48.0, BELOW_Y + 0.05, 1.5), "dwell": 8.0, "verb": "CLOCK WINDOW", "display": "LURE WINDOW"},
	"relay_exit": {"protocol": "relay_signal", "kind": "evidence", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 51.0, BELOW_Y + 0.05, 4.5), "dwell": 8.0, "verb": "READ EXIT", "display": "EXIT SCENT"},
	"relay_safe": {"protocol": "relay_signal", "kind": "choice", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 54.0, BELOW_Y + 0.05, 2.8), "dwell": 8.0, "verb": "PLAN SAFE RELAY", "display": "SAFE RELAY"},
	"relay_fast": {"protocol": "relay_signal", "kind": "choice", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 54.0, BELOW_Y + 0.05, -2.8), "dwell": 8.0, "verb": "PLAN FAST CUT", "display": "FAST CUT"},
	"relay_safe_execution": {"protocol": "relay_signal", "kind": "resolution", "role": "peris", "pos": Vector3(JUNCTION_POS.x + 57.0, BELOW_Y + 0.05, 4.5), "dwell": 14.0, "verb": "TUNE RELAY", "display": "TUNE FLURE"},
	"relay_fast_execution": {"protocol": "relay_signal", "kind": "resolution", "role": "aster", "pos": Vector3(JUNCTION_POS.x + 57.0, BELOW_Y + 0.05, -4.5), "dwell": 14.0, "verb": "PIN CADENCE", "display": "PIN WINDOW"},
}

# --- Multi-level grid (two stacked decks) ---
# The scene is two physical decks: the UPPER deck (elevator interior + bridge, world Y=0) and the
# LOWER deck (below landing + junction + gauntlet, world Y=BELOW_Y=-4), connected one-way by the
# bridge collapse. They map to grid levels with origin.y = BELOW_Y and level_height = -BELOW_Y, so:
#   level 0 -> Y = -4 (lower)   level 1 -> Y = 0 (upper)
# Choosing the origin this way keeps every literal world Y in the scene unchanged. The two decks
# overlap in X (the bridge sits above the lower landing), so each level gets its own walkable
# footprint (see _setup_level_footprints). Movement derives Y from the character's level; the fall
# is a real set_character_level transition, not a hand-tweened position poke.
const LEVEL_LOWER := 0
const LEVEL_UPPER := 1
const GRID_ORIGIN := Vector3(-5.0, BELOW_Y, -13.0)
# DERIVED from the layout so it always covers to just past the gauntlet exit — a longer bridge shifts the whole
# lower-deck run east, and a hardcoded width would leave the far end off-grid (non-walkable → stranded player).
const GRID_SIZE := Vector2i(int(GAUNTLET_EXIT.x - GRID_ORIGIN.x + 3.0), 21)  # Z in [-13, 8] covers route side platforms
var _grid: GridWorld
var _upper_exit_footprint_unlocked := false
# See-through level occlusion (the channels-spiral shader): level geometry between the camera and the active
# character dither-dissolves around the character, so the party is never lost behind an elevator wall / girder.
var _occlusion_mgr: CameraOcclusionManager

# --- Chunk dispatch ---

func _build_chunk(chunk_name: String, parent: Node3D) -> void:
	match chunk_name:
		"elevator": _build_elevator_chunk(parent)
		"bridge": _build_bridge_chunk(parent)
		"below":
			_build_below_chunk(parent, false)
			_apply_chunk_tiles(parent, "deck_metal", "facility_metal")
			_decorate_below_chunk(parent)
		"junction":
			_build_junction_chunk(parent)
			_apply_chunk_tiles(parent, "sand", "rock")
			_add_junction_model(parent)
			_build_junction_field_annex(parent)
		"gauntlet":
			_build_gauntlet_chunk(parent)
			_apply_chunk_tiles(parent, "deck_metal", "facility_metal")
			_decorate_gauntlet_chunk(parent)
	# Wrap each chunk's level meshes in the see-through occlusion shader as it loads (characters live under
	# "Characters", outside the chunk, so they're never dissolved).
	if _occlusion_mgr != null:
		_occlusion_mgr.apply_to(parent, 0.75 if chunk_name == "below" else 0.0)

## Wrap the chunk's meshes in the see-through occlusion shader — the final STREAM step (after every mesh exists),
## mirroring the post-`_build_chunk` apply above for chunks built in one shot.
func _chunk_occlusion_step(parent: Node3D) -> void:
	if _occlusion_mgr != null:
		_occlusion_mgr.apply_to(parent)

func _below_chunk_occlusion_step(parent: Node3D) -> void:
	if _occlusion_mgr != null:
		# Floors, field paint, props, and fauna never obscure a character from the camera. Wrapping only
		# wall-height geometry avoids dozens of needless ShaderMaterials during the lower-deck prewarm.
		_occlusion_mgr.apply_to(parent, 0.75)

# Break the bridge and lower-deck ecology into bounded construction steps. Repeated bridge pieces are capped per
# frame; lower fauna is built dormant and enters the simulation only when the hidden chunk is revealed.
func _chunk_build_steps(chunk_name: String, parent: Node3D) -> Array:
	match chunk_name:
		"bridge":
			var bridge_steps: Array = [
				_bridge_step_corridor.bind(parent),
				_bridge_step_floor.bind(parent),
				_bridge_step_model_root.bind(parent),
			]
			var piece_specs := _bridge_piece_specs()
			for first in range(0, piece_specs.size(), BRIDGE_PIECES_PER_STREAM_STEP):
				var batch: Array = []
				for piece_i in range(first, mini(first + BRIDGE_PIECES_PER_STREAM_STEP, piece_specs.size())):
					batch.append(piece_specs[piece_i])
				bridge_steps.append(_bridge_step_model_batch.bind(parent, batch))
			bridge_steps.append(_bridge_step_blocked_end.bind(parent))
			bridge_steps.append(_bridge_step_light.bind(parent))
			bridge_steps.append(_chunk_occlusion_step.bind(parent))
			return bridge_steps
		"below":
			return [
				_below_step_prepare.bind(parent),
				_below_step_ground.bind(parent),
				_below_step_grated_platforms.bind(parent),
				_below_step_read_stations.bind(parent),
				_below_step_aster_route_overlay.bind(parent),
				_below_step_peris_route_overlay_path.bind(parent),
				_below_step_peris_route_overlay_beat.bind(parent, 0),
				_below_step_peris_route_overlay_beat.bind(parent, 1),
				_below_step_peris_route_overlay_beat.bind(parent, 2),
				_below_step_huddle_chelator_batch.bind(parent, 0, 3, true),
				_below_step_huddle_chelator_batch.bind(parent, 3, 6, true),
				_below_step_huddle_predators.bind(parent, true),
				_below_step_ambient_props.bind(parent),
				_below_step_route_shell.bind(parent),
				_below_step_enemy_route_beat.bind(parent, 0, true),
				_below_step_enemy_route_beat.bind(parent, 1, true),
				_below_step_enemy_route_beat.bind(parent, 2, true),
				_below_step_hazard_shell.bind(parent),
				_below_step_hazard_beat.bind(parent, 0),
				_below_step_hazard_beat.bind(parent, 1),
				_below_step_hazard_beat.bind(parent, 2),
				_below_step_stalactites.bind(parent),
				_below_step_convergence.bind(parent),
				_below_step_wreckage_gate.bind(parent, true),
				_apply_chunk_tiles.bind(parent, "deck_metal", "facility_metal"),
				_decorate_below_chunk.bind(parent),
				_below_chunk_occlusion_step.bind(parent),
			]
	return []

func _on_chunk_revealed(_chunk_name: String, _chunk: Node3D) -> void:
	# The lower deck must be visible from the intact bridge, but it is not playable
	# until the party lands there.  Revealing its prewarmed geometry is therefore
	# not an AI lifecycle transition: activating here made the whole hidden ecology
	# roam, invalidate detection, and emit move events throughout the bridge scene.
	# _on_fall_landed() activates the already-constructed cohort at the causal seam.
	pass

# --- Virtual overrides ---

func _build_scene() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)
	# Persistent WorldEnvironment (not chunk-specific)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.02, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.15, 0.1)
	e.ambient_light_energy = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.3
	e.glow_bloom = 0.1
	we.environment = e
	env.add_child(we)
	# Create the see-through occlusion manager BEFORE the first chunk loads so its meshes get wrapped on build.
	# It tracks the active character once the GameState exists (set_watch in _register_characters).
	_occlusion_mgr = CameraOcclusionManager.new()
	_occlusion_mgr.name = "CameraOcclusionManager"
	add_child(_occlusion_mgr)
	_build_grid()
	_load_chunk("elevator")
	# The corridor shell and click-collision slab ship with the elevator's initial load. The repeated deck
	# pieces continue in four-piece slices during the stationary opening instead of arriving in one spike.
	if start_chunk == "" or start_chunk == "bridge":
		stream_chunk("bridge")
		_advance_chunk_streams()
		_advance_chunk_streams()

## Two stacked decks on one grid plane. No wall border — per-level footprints define the walkable
## area of each deck (the decks overlap in X, so a level-agnostic wall can't separate them).
func _build_grid() -> void:
	_grid = GridWorld.new()
	_grid.origin = GRID_ORIGIN
	_grid.create_room(GRID_SIZE.x, GRID_SIZE.y, false)

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	_player = _create_player_character("Peris", Color(0.8, 0.5, 0.35))
	_player.position = PERIS_START
	chars.add_child(_player)
	_peris_node = _player

	_aster_node = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_aster_node.position = ASTER_POS + Vector3(0, 0.5, 0)
	_aster_node.rotation_degrees.z = 30.0
	chars.add_child(_aster_node)
	# The elevator camera runs closer than the simulation cameras. Keep identity
	# tags readable without letting them cover the route line or fork geometry.
	for character: CharacterBody3D in [_player, _aster_node]:
		var identity_label := character.get_node_or_null("Label3D") as Label3D
		if identity_label != null:
			identity_label.pixel_size = 0.006

	# Escort units
	_escort_1 = _create_npc("EU-1", Color(0.7, 0.7, 0.75))
	_escort_1.position = ESCORT_1_POS
	chars.add_child(_escort_1)

	_escort_2 = _create_npc("EU-2", Color(0.7, 0.7, 0.75))
	_escort_2.position = ESCORT_2_POS
	chars.add_child(_escort_2)

	_endo = _create_npc("Endo", Color(0.4, 0.67, 0.53))
	_endo.position = Vector3(JUNCTION_POS.x + 3, BELOW_Y + 0.5, -2)
	_endo.visible = false
	chars.add_child(_endo)
	_build_emp_visuals()

	if not Engine.is_editor_hint():
		_player.grid_world = _grid  # player clicks route on the grid (cell snapping, per-deck footprint)
		_setup_game_camera(_player, Vector3(0, 3.5, 2.5))
		# Keep the view inside the elevator: pan / edge-scroll can't push the
		# look-at past the walls. Cleared when the corridor opens up.
		if _camera != null and _camera.has_method("set_look_bounds"):
			var hx := ELEVATOR_SIZE.x / 2.0
			var hz := ELEVATOR_SIZE.z / 2.0
			_camera.set_look_bounds(Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, hz))

func _register_characters() -> void:
	_game_state.grid = _grid          # assign BEFORE registering so each character's level derives from its spawn Y
	_configure_levels(2, -BELOW_Y)    # 2 decks, 4m apart: level 0 = lower (Y=-4), level 1 = upper (Y=0)
	_setup_level_footprints()
	# Party HP is GameState's (the single source). A positive HP is also the AI's "alive" flag — without
	# it, enemy detection treats the party as downed (hp<=0) and the ecology never gives chase.
	_register_gs_character("peris", _peris_node, 2.5, {"hp": PARTY_MAX_HP})
	_register_gs_character("aster", _aster_node, 2.5, {"hp": PARTY_MAX_HP})
	# TutorialSequence binds only the character stored in `_player` (Peris at
	# registration time). Elevator later promotes Aster to the active controller,
	# so his controller must also observe streamed interaction targets.
	if _aster_node.has_method("bind_interaction_root"):
		_aster_node.bind_interaction_root(self)
	_register_gs_character("eu1", _escort_1, 2.0)
	_register_gs_character("eu2", _escort_2, 2.0)
	if not _game_state.character_arrived.is_connected(_on_emp_guard_arrived):
		_game_state.character_arrived.connect(_on_emp_guard_arrived)
	_aster_node.set_move_enabled(false)
	# Reveal the level around the active character (data-layer position) now that the GameState is live.
	if _occlusion_mgr != null:
		_occlusion_mgr.set_watch(_game_state, _active_character)

## Each deck's walkable footprint (world XZ). The decks overlap in X, so a cell walkable on the
## upper deck (the bridge) may be void on the lower deck and vice versa. Clicks off a deck's
## footprint are rejected by the grid, so the player can't walk into the void or off the bridge.
func _setup_level_footprints() -> void:
	# Upper deck (level 1) begins as the elevator cabin only. The streamed corridor and bridge are
	# intentionally absent from pathfinding until the rally lesson has brought BOTH characters to
	# the doorway. Otherwise a route queued during the paused scene can carry Aster into unseen space.
	_add_level_walkable_region(LEVEL_UPPER, Vector2(-4.0, -3.5), Vector2(4.5, 3.5))   # elevator cabin
	# Lower deck (level 0): the below landing / fork / junction / gauntlet run, one open span.
	_add_level_walkable_region(LEVEL_LOWER, Vector2(LOWER_ROUTE_WEST_X, -8.0), Vector2(GAUNTLET_EXIT.x + 1.0, 8.0))

func _set_lower_route_camera_bounds() -> void:
	if _camera == null or not _camera.has_method("set_look_bounds"):
		return
	_camera.set_look_bounds(
		Vector3(LOWER_ROUTE_WEST_X + 0.5, BELOW_Y, -8.0),
		Vector3(JUNCTION_POS.x + 5.0, BELOW_Y, 8.0)
	)

func _set_junction_camera_bounds() -> void:
	if _camera == null or not _camera.has_method("set_look_bounds"):
		return
	_camera.set_look_bounds(
		Vector3(ROUTES_CONVERGE.x - 3.0, BELOW_Y, -12.0),
		Vector3(JUNCTION_POS.x + 64.0, BELOW_Y, 12.0)
	)

func _set_gauntlet_camera_bounds() -> void:
	if _camera == null or not _camera.has_method("set_look_bounds"):
		return
	_camera.set_look_bounds(
		Vector3(GAUNTLET_POS.x - 10.0, BELOW_Y, -8.0),
		Vector3(GAUNTLET_EXIT.x + 4.0, BELOW_Y, 8.0)
	)

func _unlock_upper_exit_footprint() -> void:
	if _upper_exit_footprint_unlocked:
		return
	_upper_exit_footprint_unlocked = true
	# The girder inner faces sit at roughly z=±1.3. Author the two central one-metre lanes explicitly;
	# an inclusive world rectangle previously admitted the cells centred on/outside the rails (z=±1.5/2.5),
	# letting the grid-authoritative mover route straight through the visible railing.
	var min_cell := _grid.world_to_grid(Vector3(4.0, 0.0, -0.5))
	var max_cell := _grid.world_to_grid(Vector3(BRIDGE_END_X - 1.0, 0.0, 0.5))
	_grid.allow_cell_region_on_level(min_cell, max_cell, LEVEL_UPPER)

## Remove a world-space rectangle from one stacked level's allow-set. The shared tile grid cannot
## represent a wall that blocks the lower deck without also blocking the overlapping upper bridge.
func _block_level_walkable_region(level: int, min_xz: Vector2, max_xz: Vector2) -> void:
	if _grid == null or not _grid.level_allowed.has(level):
		return
	var min_cell := _grid.world_to_grid(Vector3(min_xz.x, 0.0, min_xz.y))
	var max_cell := _grid.world_to_grid(Vector3(max_xz.x, 0.0, max_xz.y))
	for z in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for x in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			_grid.level_allowed[level].erase(Vector2i(x, z))

func _setup_ui() -> void:
	_hud = preload("res://scenes/ui/game_hud.tscn").instantiate()
	add_child(_hud)
	_hud.add_portrait("peris", "Peris", Color(1.0, 0.67, 0.27))
	_hud.add_portrait("aster", "Aster", Color(0.29, 0.62, 1.0))
	_hud.set_selected_portraits(_selected_character_ids)
	# HP mirrors GameState (the single source); stat_changed keeps the portraits in sync from then on.
	_hud.set_portrait_stat("peris", "hp", _game_state.get_stat("peris", "hp"))
	_hud.set_portrait_stat("aster", "hp", _game_state.get_stat("aster", "hp"))
	if not _game_state.stat_changed.is_connected(_on_party_stat_changed):
		_game_state.stat_changed.connect(_on_party_stat_changed)
	_hud.set_portrait_status("aster", "downed")
	_hud.set_portrait_stat("aster", "sta", 0)
	_hud.show_pause_toggle(false)
	_hud.pause_toggled.connect(_on_pause_toggled)
	var emp_binding := AbilityData.binding("emp")
	# The key hint comes from Aster's live direct ability slot, never a baked legacy letter, so a rebind / controller
	# is reflected (the xlsx keybind is only the fallback if the action somehow has no binding).
	_hud.add_ability("emp", AbilityData.get_ability("elevator.emp").get("display_name", "EMP"),
		InputHints.label_for_action(EMP_INPUT_ACTION, str(emp_binding.get("keybind", ""))),
		emp_binding.get("color", Color(0.29, 0.62, 1.0)),
		EMP_INPUT_ACTION, "aster", "Aster", 0, 0)
	_hud.set_ability_state("emp", "disabled")
	_hud.ability_pressed.connect(func(id: String):
		if id == "emp":
			_on_emp_pressed()
	)
	_hud.character_selection_changed.connect(_on_character_selected)
	_build_elevator_overlay_ui()

	# Door button changes behavior after EMP.
	_exit_button = preload("res://scenes/game/interactable.tscn").instantiate()
	_exit_button.name = "ExitButton"
	_exit_button.description = "Door Button"
	_exit_button.one_shot = false
	_exit_button.dwell_time = 0.5
	_exit_button.tutorial_label = "OPEN"
	_exit_button.interaction_enabled = false
	_exit_button.monitoring = false
	_exit_button.monitorable = false
	_exit_button.visible = false
	_exit_button.position = Vector3(ELEVATOR_SIZE.x / 2.0 - 0.3, 1.0, 1.5)
	add_child(_exit_button)
	_exit_button.interacted.connect(_on_exit_button_pressed)
	_set_exit_button_interactable(false)

func _build_elevator_overlay_ui() -> void:
	_elevator_overlay_ui = preload("res://scenes/ui/perception_overlay.tscn").instantiate()
	_elevator_overlay_ui.name = "ElevatorOverlayUI"
	_elevator_overlay_ui.visible = false
	add_child(_elevator_overlay_ui)
	var margin := _elevator_overlay_ui.get_node("Margin") as MarginContainer
	margin.offset_left = -346.0
	margin.offset_bottom = 118.0
	var content := _elevator_overlay_ui.get_node("Margin/Panel/Content") as VBoxContainer
	content.add_theme_constant_override("separation", 5)
	var title := content.get_node("Title") as Label
	title.visible = true
	var note := content.get_node("NoteLabel") as Label
	note.visible = false
	var aster_button := content.get_node("Buttons/AsterOverlayButton") as Button
	aster_button.text = "Aster Data  F1"
	_bind_elevator_overlay_button(aster_button, "aster", Color(0.29, 0.62, 1.0))
	var peris_button := content.get_node("Buttons/PerisOverlayButton") as Button
	peris_button.text = "Peris Memory  F2"
	_bind_elevator_overlay_button(peris_button, "peris", Color(1.0, 0.67, 0.27))
	_elevator_overlay_status = content.get_node("StatusLabel") as Label
	_elevator_overlay_status.name = "ElevatorOverlayStatus"
	_elevator_overlay_status.add_theme_font_size_override("font_size", 10)
	_refresh_elevator_overlay_ui()

func _bind_elevator_overlay_button(button: Button, overlay_id: String, color: Color) -> void:
	button.add_theme_font_size_override("font_size", 10)
	button.pressed.connect(_toggle_elevator_overlay.bind(overlay_id))
	_elevator_overlay_buttons[overlay_id] = {"button": button, "color": color}

func _unlock_elevator_overlays() -> void:
	if not _elevator_overlays_available:
		_elevator_overlays_available = true
		_elevator_overlay_states["aster"] = true
		_elevator_overlay_states["peris"] = false
	if _elevator_overlay_ui != null:
		_elevator_overlay_ui.visible = true
	_apply_elevator_overlay_visibility()
	_refresh_elevator_overlay_ui()

func _toggle_elevator_overlay(overlay_id: String) -> void:
	if not _elevator_overlays_available or not _elevator_overlay_states.has(overlay_id):
		return
	_set_elevator_overlay_state(overlay_id, not bool(_elevator_overlay_states[overlay_id]))

func _set_elevator_overlay_state(overlay_id: String, enabled: bool) -> void:
	if not _elevator_overlay_states.has(overlay_id):
		return
	if not _elevator_overlays_available:
		_elevator_overlays_available = true
		if _elevator_overlay_ui != null:
			_elevator_overlay_ui.visible = true
	_elevator_overlay_states[overlay_id] = enabled
	_apply_elevator_overlay_visibility()
	_refresh_elevator_overlay_ui()
	if overlay_id == "peris" and enabled and _current_step == "route_read_circuit":
		_resolve_peris_overlay_route_read()

func _apply_elevator_overlay_visibility() -> void:
	if bool(_elevator_overlay_states.get("aster", false)):
		_setup_perception("data", _aster_node)
		var aster_x := _game_state.get_position("aster").x \
			if _game_state != null and _game_state.characters.has("aster") else _aster_node.global_position.x
		_perception_quad.visible = aster_x <= MAIN_FACILITY_MAX_X
	elif _perception_quad != null:
		_perception_quad.visible = false
	if is_instance_valid(_aster_route_overlay_root):
		_aster_route_overlay_root.visible = bool(_elevator_overlay_states.get("aster", false))
	if is_instance_valid(_peris_route_overlay_root):
		_peris_route_overlay_root.visible = bool(_elevator_overlay_states.get("peris", false))

func _refresh_elevator_overlay_ui() -> void:
	for overlay_id in _elevator_overlay_buttons:
		var info: Dictionary = _elevator_overlay_buttons[overlay_id]
		var button: Button = info.get("button")
		var color: Color = info.get("color", Color.WHITE)
		var enabled := bool(_elevator_overlay_states.get(overlay_id, false))
		button.modulate = Color(color, 1.0 if enabled else 0.55)
		button.tooltip_text = "%s overlay %s" % [overlay_id.capitalize(), "ON" if enabled else "OFF"]
	if _elevator_overlay_status != null:
		_elevator_overlay_status.text = "Aster data: %s     Peris memory: %s" % [
			"ON" if bool(_elevator_overlay_states.get("aster", false)) else "OFF",
			"ON" if bool(_elevator_overlay_states.get("peris", false)) else "OFF",
		]

func _begin() -> void:
	_player.set_move_enabled(false)
	_fade_rect.color = Color(0, 0, 0, 1)
	if start_chunk == "emp":
		# Focused render/export probe: all ordinary scene construction still runs,
		# but dialogue is skipped so the EMP can be inspected frame by frame.
		_fade_rect.color = Color(0, 0, 0, 0)
		_start_emp_focus()
		return
	if start_chunk != "":
		_load_chunk("below" if start_chunk in ["route", "wreckage"] else start_chunk)
		_player.set_move_enabled(true)
		_fade_rect.color = Color(0, 0, 0, 0)
		match start_chunk:
			"route":
				_start_route_focus()
			"wreckage":
				_start_wreckage_focus()
			"junction":
				_player.global_position = Vector3(JUNCTION_POS.x, BELOW_Y + 0.5, 0)
				_start_junction_arrive()
			"gauntlet":
				_player.global_position = Vector3(GAUNTLET_POS.x, BELOW_Y + 0.5, 0)
				_start_gauntlet()
			"bridge":
				# Focused bridge playtests still need the lower geometry in view, but
				# must preserve the normal prewarm lifecycle: a one-shot _load_chunk
				# constructs its fauna live and would run the whole hidden ecology.
				stream_chunk("below")
				reveal_chunk("below")
				# The escorts have completed their story role before this checkpoint.
				# Keeping them visible in a focused Web probe leaves two oversized labels
				# at the bridge mouth and misrepresents the playable composition.
				if _escort_1 != null:
					_escort_1.visible = false
				if _escort_2 != null:
					_escort_2.visible = false
				_player.global_position = Vector3(0, 0.5, 0)
				_start_bridge()
			_:
				_player.global_position = Vector3.ZERO
		return
	_scheduler.schedule_after(1.0, _start_consciousness_fragments, "fragments")
	# Finish the bridge and prewarm the lower route across the long stationary opening. Lower-deck enemies are
	# registered and activated only on reveal, so hidden construction adds no patrol or detection scheduler traffic.
	stream_chunk("bridge")
	stream_chunk("below")

func _compute_speed() -> float:
	return 10.0 if Input.is_action_pressed("fast_forward") else 1.0

func _on_process(delta: float, spd: float) -> void:
	# Intro + outro fades are driven off the scheduler tick (not wall-clock tweens)
	# so they speed with F in lockstep with their scheduled step transitions.
	if _current_step == "complete":
		_update_fade_out(Color(0.02, 0.02, 0.03), 2.0)
	elif _current_step == "consciousness_fragments":
		_update_consciousness_fade()
	elif _current_step == "fade_in":
		_update_fade_in(FADE_IN_DURATION)

	# Aster's data overlay maps the main facility, where blueprints exist. It stays
	# active out to Endo's junction; past it is maintenance with no schematic, so the
	# overlay reads nothing there. Gating on Aster's position keeps it lit through the
	# whole bridge → fall → junction stretch and dark only once she's past the junction.
	if _perception_mode == "data" and _perception_quad and is_instance_valid(_perception_quad):
		var aster_x := _aster_node.global_position.x
		if _game_state and _game_state.characters.has("aster"):
			aster_x = _game_state.get_position("aster").x
		_perception_quad.visible = _elevator_overlays_available \
			and bool(_elevator_overlay_states.get("aster", false)) \
			and aster_x <= MAIN_FACILITY_MAX_X

	# Emergency light pulse.
	if _elevator_powered and _emergency_light and is_instance_valid(_emergency_light):
		_emergency_light.light_energy = 1.5 + sin(Time.get_ticks_msec() * 0.003) * 0.5

	# Floor indicator flicker.
	if _elevator_powered and _indicator_b_label and is_instance_valid(_indicator_b_label):
		_indicator_timer += delta * spd
		if _indicator_timer > 0.3:
			_indicator_timer = 0.0
			_indicator_b_label.visible = not _indicator_b_label.visible

	# Sync EMP cooldown display.
	if _emp_cooldown_end > 0:
		var remaining := maxf(0, _emp_cooldown_end - _scheduler.get_current_tick())
		_hud.set_ability_state("emp", "cooldown", remaining)
		if remaining <= 0:
			_emp_cooldown_end = 0.0
			_hud.set_ability_state("emp", "ready")

	# Visual patrol drift.
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy.rotation.y += delta * spd * 0.3

	# Iron contact is evaluated on the gameplay scheduler by _iron_hazard_tick, never once per render frame.
	# Approach gate
	if _current_step == "approach_aster":
		var peris_pos := _game_state.get_position("peris")
		if (_aster_wake_interactable == null or not is_instance_valid(_aster_wake_interactable)) and peris_pos.distance_to(ASTER_POS) < 1.8:
			_tutorial_prompt.hide_prompt()
			_player.set_move_enabled(false)
			_start_wake_aster()

	# Rally gate: the command-hold addresses the whole controllable roster without changing the
	# singleton selection. Once both have reached the doorway the lesson is complete.
	if _current_step == "rally_tutorial":
		var exit_gate := Vector3(ELEVATOR_SIZE.x / 2.0, 0, 0)
		var pp := _game_state.get_position("peris")
		var ap := _game_state.get_position("aster")
		var peris_at_door := pp.distance_to(exit_gate) < 2.5
		var aster_at_door := ap.distance_to(exit_gate) < 2.5
		if peris_at_door and aster_at_door:
			_start_corridor()
		elif peris_at_door or aster_at_door:
			_show_rally_together_hint()

	# Bridge gate: the span gives way MID-SPAN as the player walks out onto it (the narration's
	# "it gives way mid-span"). The trigger sits comfortably inside the walkable bridge, NOT at the far
	# edge — clicking the far edge raycasts down to the lower deck (no ladder there → the move is
	# rejected and the player looks stranded), so requiring the edge stranded the player.
	if _current_step == "bridge":
		var lead := _party_lead_x()
		# Pace the crossing dialogue by DISTANCE: fire each remaining line at evenly spaced thresholds up to the
		# collapse point, so the party talks WHILE crossing the long span instead of before stepping on.
		var span := BRIDGE_COLLAPSE_X - BRIDGE_START_X
		while _bridge_lines_fired < _bridge_lines_pending.size() \
				and lead > BRIDGE_START_X + span * (float(_bridge_lines_fired + 1) / float(_bridge_lines_pending.size() + 1)):
			DialogueData.say_to(_dialogue, str(_bridge_lines_pending[_bridge_lines_fired]))
			_bridge_lines_fired += 1
		# The whole party falls only when the whole party is actually on the
		# failing span.  Previously the lead unit could trigger this alone; the
		# trailing unit was then teleported straight down from the bridge mouth
		# into the dormant huddle and could be killed off-screen.
		if _party_tail_x() > BRIDGE_COLLAPSE_X:
			_tutorial_prompt.hide_prompt()
			_player.set_move_enabled(false)
			_start_bridge_collapse()

	# Route convergence reveals the last causal gate instead of unloading the level under a trailing
	# partner. The wreckage itself decides whether the party distributes the load or makes enough
	# noise to wake the nearby fauna.
	if _current_step == "route_choice":
		_update_route_course_progress()
		# The ecology gates itself: it's distracted by its flures, so it only chases a party that cuts
		# through the huddle (the enemy lane). The hazard lane keeps enough distance to slip past.
		if not _wreckage_armed and _party_lead_x() > ROUTES_CONVERGE.x - 2.0 \
				and _route_beats_crossed.count(true) >= ROUTE_BEAT_COUNT:
			_arm_wreckage_gate()

	# Gauntlet exit gate: player passed the enemies
	if _current_step == "gauntlet":
		if not _gauntlet_midpoint_reached and _party_lead_x() > GAUNTLET_MIDPOINT.x - 2.0:
			_reach_gauntlet_midpoint()
		if _party_lead_x() > GAUNTLET_EXIT.x - 2.0:
			_tutorial_prompt.hide_prompt()
			_player.set_move_enabled(false)
			_complete()

	_update_below_fauna_activation()

## Whichever party member (aster/peris) is furthest east. The descent's position gates fire on the
## LEAD member, so they trigger whether the player walks aster, peris, or both as a group (party-move)
## — not just when aster happens to be the one who advanced.
func _party_lead_x() -> float:
	return maxf(_game_state.get_position("aster").x, _game_state.get_position("peris").x)

func _party_tail_x() -> float:
	return minf(_game_state.get_position("aster").x, _game_state.get_position("peris").x)

func _party_average_z() -> float:
	return (_game_state.get_position("aster").z + _game_state.get_position("peris").z) * 0.5

func _update_route_course_progress() -> void:
	var lead := _party_lead_x()
	if _route_lane == "" and lead > FORK_POS.x + 4.0:
		var avg_z := _party_average_z()
		if avg_z < -0.75:
			_route_lane = "flure"
		elif avg_z > 0.75:
			_route_lane = "iron"
		if _route_lane != "":
			_show_marker(Vector3(FORK_POS.x + 5.0, BELOW_Y + 2.2, avg_z), _route_lane.to_upper() + " ROUTE")
	for i in range(ROUTE_BEAT_COUNT):
		var threshold := FORK_POS.x + float(ROUTE_BEAT_OFFSETS[i]) + 6.0
		if not _route_beats_crossed[i] and lead > threshold:
			_route_beats_crossed[i] = true
			_show_marker(Vector3(threshold, BELOW_Y + 2.1, _party_average_z()), "BEAT %d / 3" % (i + 1))

# --- Input ---

# Pause and Aster's direct EMP slot arrive as HUD signals (pause_toggled / ability_pressed)
# mapped from the input map by GameHUD. Only the elevator-specific character
# switch shortcuts are handled here, via input actions. Multi-selection is taught later, when a
# split perspective puzzle actually gives it a purpose; this doorway teaches whole-party rally.
func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("preview_overlay_aster"):
		_toggle_elevator_overlay("aster")
	elif event.is_action_pressed("preview_overlay_peris"):
		_toggle_elevator_overlay("peris")
	elif event.is_action_pressed("route") and _current_step in ["hack_tutorial", "junction_arrive"]:
		_switch_character()

func _toggle_pause() -> void:
	if _scheduler.is_paused():
		if _emp_pause_locked and not _emp_queued:
			_hud.set_paused(true)
			_tutorial_prompt.show_prompt("%s - queue Aster's EMP before unpausing" % InputHints.bracket(EMP_INPUT_ACTION))
			return
		_set_collapse_visual_paused(false)
		_scheduler.resume()
		_hud.set_paused(false)
		_flush_queued_abilities()
		if _current_step == "rally_tutorial":
			_update_rally_tutorial_prompt()
	else:
		_scheduler.pause()
		_set_collapse_visual_paused(true)
		_hud.set_paused(true)

func _on_pause_toggled(is_paused: bool) -> void:
	if is_paused:
		_scheduler.pause()
		_set_collapse_visual_paused(true)
	else:
		if _emp_pause_locked and not _emp_queued:
			_hud.set_paused(true)
			_tutorial_prompt.show_prompt("%s - queue Aster's EMP before unpausing" % InputHints.bracket(EMP_INPUT_ACTION))
			return
		_set_collapse_visual_paused(false)
		_scheduler.resume()
		_flush_queued_abilities()
		if _current_step == "rally_tutorial":
			_update_rally_tutorial_prompt()

## Gameplay pause is scheduler-owned, while the bridge collapse deliberately uses wall-clock
## presentation (Tween + rigid-body settling). Keep those two clocks observationally atomic: a
## paused player must never watch the bridge retire while the authoritative landing is frozen.
func _set_collapse_visual_paused(paused: bool) -> void:
	_collapse_visual_paused = paused
	for tween in [_fall_tween, _collapse_settle_tween]:
		if tween != null and tween.is_valid():
			if paused:
				tween.pause()
			else:
				tween.play()
	for stagger in _collapse_stagger_tweens:
		if stagger != null and stagger.is_valid():
			if paused:
				stagger.pause()
			else:
				stagger.play()
	if paused:
		for rb in _collapse_debris:
			if not is_instance_valid(rb) or rb.freeze:
				continue
			_collapse_paused_debris[rb.get_instance_id()] = {
				"linear_velocity": rb.linear_velocity,
				"angular_velocity": rb.angular_velocity,
			}
			rb.freeze = true
		return
	for rb in _collapse_debris:
		if not is_instance_valid(rb):
			continue
		var saved: Dictionary = _collapse_paused_debris.get(rb.get_instance_id(), {})
		if not saved.is_empty():
			rb.freeze = false
			rb.linear_velocity = saved.get("linear_velocity", Vector3.ZERO)
			rb.angular_velocity = saved.get("angular_velocity", Vector3.ZERO)
		elif bool(rb.get_meta("collapse_release_ready", false)) \
				and not bool(rb.get_meta("collapse_impulse_applied", false)):
			_release_debris_now(rb)
	_collapse_paused_debris.clear()

func _flush_queued_abilities() -> void:
	if _emp_queued:
		_emp_queued = false
		_fire_emp_both()

func _on_emp_pressed() -> void:
	if _current_step == "emp_tutorial" and _emp_count == 0:
		if _scheduler.is_paused():
			_emp_queued = true
			_emp_pause_locked = false
			_hud.set_ability_state("emp", "queued")
			_tutorial_prompt.show_prompt("%s - unpause to fire queued EMP" % InputHints.bracket("pause"))
		else:
			_fire_emp_both()

func _fire_emp_both() -> void:
	_emp_pause_locked = false
	_emp_queued = false
	_stamina = maxf(0, _stamina - 25.0)
	_hud.set_portrait_stat("peris", "sta", _stamina)
	_emp_cooldown_end = _scheduler.get_current_tick() + 10.0
	_hud.set_ability_state("emp", "cooldown", 10.0)
	_camera.shake(0.3, 4.0)
	_escort_1.stop()
	_escort_2.stop()
	_play_emp_discharge_animation()
	_unit_1_stunned = true
	_unit_2_stunned = true
	_emp_count = 2
	_reboot_active = true
	_tutorial_prompt.hide_prompt()
	# Reboot and hack tutorial on the scheduler
	_scheduler.schedule_after(30.0, _on_reboot, "reboot")
	_scheduler.schedule_after(1.5, _start_doors_unlocked, "doors_unlock")

func _on_reboot() -> void:
	if not _reboot_active:
		return
	_reboot_active = false
	# Once the EMP has visibly released the doors, the guard-reboot fallback no
	# longer owns the encounter. Never let a stale callback erase Rally's prompt
	# or repower the room underneath the player.
	if _current_step not in ["emp_tutorial", "doors_unlocked"]:
		return
	_unit_1_stunned = false
	_unit_2_stunned = false
	if _escort_1:
		_escort_1.visible = true
	if _escort_2:
		_escort_2.visible = true
	_restore_elevator_power_visuals()
	_emp_count = 0
	_enter_step("units_activate")
	_start_units_activate()

func _on_exit_button_pressed() -> void:
	# Flash "NO EXIT" on the indicator
	if _no_exit_label:
		var tween := create_tween()
		tween.tween_property(_no_exit_label, "modulate:a", 0.9, 0.2)
		tween.tween_interval(1.5)
		tween.tween_property(_no_exit_label, "modulate:a", 0.0, 0.5)
	_camera.shake(0.05, 10.0)

func _set_exit_button_interactable(active: bool) -> void:
	if _exit_button == null:
		return
	if active and _exit_button.has_method("reset"):
		_exit_button.reset()
	_exit_button.visible = active
	if _exit_button.has_method("set_interaction_enabled"):
		_exit_button.set_interaction_enabled(active)
	else:
		_exit_button.monitoring = active
		_exit_button.monitorable = active
	if not active:
		if _exit_button.has_method("hide_tutorial_label"):
			_exit_button.hide_tutorial_label()
		if _exit_button.has_method("cancel_queued_feedback"):
			_exit_button.cancel_queued_feedback()

func _switch_character() -> void:
	var next_id: String = _hud.get_next_portrait_id(_active_character)
	_select_character(next_id)

func _select_character(id: String, preserve_multi_selection := false) -> void:
	if not (id in ["peris", "aster"]):
		return
	if id == "peris":
		_player = _peris_node
		_camera.target = _peris_node
	else:
		_player = _aster_node
		_camera.target = _aster_node
	_active_character = id
	if _occlusion_mgr != null:
		# Camera and reveal target change in the same input frame; publishing the
		# uniform synchronously avoids a transient full-wall occlusion plane.
		_occlusion_mgr.set_watch(_game_state, id)
	if not preserve_multi_selection:
		_selected_character_ids = [id]
	elif not _selected_character_ids.has(id):
		_selected_character_ids.append(id)
	_suppress_hud_character_signal = true
	_hud.set_active_portrait(id, preserve_multi_selection)
	if preserve_multi_selection:
		_hud.set_selected_portraits(_selected_character_ids)
	_suppress_hud_character_signal = false
	_apply_character_control_selection()

func _on_character_selected(selected_ids: Array) -> void:
	if _suppress_hud_character_signal:
		return
	var sanitized := _sanitize_character_selection(selected_ids)
	if sanitized.is_empty():
		sanitized = [_active_character]
	_selected_character_ids = sanitized
	var preferred := sanitized[0]
	# Character perspective remains a live verb after the tutorial. Junction reads
	# deliberately require both Aster and Peris, so portrait/box selection must keep
	# switching the active controller throughout the playable descent.
	if preferred != _active_character:
		_select_character(preferred, bool(_hud.get("_multi_select")))
	else:
		_apply_character_control_selection()

func _sanitize_character_selection(selected_ids: Array) -> Array[String]:
	var sanitized: Array[String] = []
	for raw_id in selected_ids:
		var id := str(raw_id)
		if not (id in ["peris", "aster"]):
			continue
		if sanitized.has(id):
			continue
		sanitized.append(id)
	return sanitized

func _apply_character_control_selection() -> void:
	var group_control := _hud != null and bool(_hud.get("_multi_select")) and _selected_character_ids.size() > 1
	# In group control the party moves as one: the active character's player drives
	# the click and issues a spread party move (distinct cells, no overlap), so only
	# it is move-enabled — the other member is carried by the party move, not its
	# own click. Single control: only the active character moves, no group move.
	_apply_party_control({"peris": _peris_node, "aster": _aster_node},
		_sanitize_character_selection(_selected_character_ids), _active_character, group_control)

func _update_rally_tutorial_prompt() -> void:
	_tutorial_prompt.show_action_prompt(
		&"command",
		"Hold on the open doorway until RALLY ALL appears, release to queue both paths, then press %s."
			% InputHints.bracket("pause"),
		0.0,
		"RMB HOLD"
	)

func _show_rally_together_hint() -> void:
	_update_rally_tutorial_prompt()

## Compatibility for old focused tools/saves that still call the former tutorial helper directly.
func _start_multiselect_tutorial() -> void:
	_start_rally_tutorial()

# --- Event steps ---

# Consciousness-fragment intro fade phases (scheduler ticks). Two fragments, each
# fade-in -> hold -> fade-out; the second starts at FRAG2_TICK. Total 5.8 ticks.
const CONSCIOUSNESS_FADE := 0.8
const CONSCIOUSNESS_HOLD := 1.5
const CONSCIOUSNESS_FADE_OUT := 0.6
const CONSCIOUSNESS_FRAG2_TICK := 2.9
const FADE_IN_DURATION := 1.0

func _start_consciousness_fragments() -> void:
	_enter_step("consciousness_fragments")
	# Hide everything except Peris initially
	_emergency_light.light_energy = 0.0
	if _aster_node:
		_aster_node.visible = false
	for unit in [_escort_1, _escort_2]:
		if unit:
			unit.visible = false

	# The two consciousness-fragment fades are driven per-frame off the scheduler
	# tick (see _update_consciousness_fade in _on_process), so holding F speeds the
	# fades and the fade_in transition together — a wall-clock tween here would lag
	# the (scheduler-timed) transition under fast-forward and tear the fade.
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_start_tick = _scheduler.get_current_tick()
	# Fragment 2 reveals Aster at the start of its fade-in (after fragment 1).
	_scheduler.schedule_after(CONSCIOUSNESS_FRAG2_TICK, func():
		if _aster_node:
			_aster_node.visible = true
	, "frag2_reveal")
	_scheduler.schedule_after(5.8, _start_fade_in, "fade_in")

## Per-frame alpha for the two-fragment consciousness intro, read off the
## scheduler tick so fast-forward scales it with the scheduled transitions.
func _update_consciousness_fade() -> void:
	if _fade_rect == null:
		return
	var elapsed: float = _scheduler.get_current_tick() - _fade_start_tick
	# Each fragment: fade-in (black->clear) -> hold (clear) -> fade-out (clear->black).
	var local := elapsed
	if elapsed >= CONSCIOUSNESS_FRAG2_TICK:
		local = elapsed - CONSCIOUSNESS_FRAG2_TICK
	var alpha := 1.0
	if local < CONSCIOUSNESS_FADE:
		alpha = 1.0 - clampf(local / CONSCIOUSNESS_FADE, 0.0, 1.0)
	elif local < CONSCIOUSNESS_FADE + CONSCIOUSNESS_HOLD:
		alpha = 0.0
	else:
		var out_t := local - (CONSCIOUSNESS_FADE + CONSCIOUSNESS_HOLD)
		alpha = clampf(out_t / CONSCIOUSNESS_FADE_OUT, 0.0, 1.0)
	_fade_rect.color.a = alpha

func _start_fade_in() -> void:
	# Scheduler-driven from consciousness_fragments. If a test force-fired straight to
	# waking, this scheduled call is stale — no-op so it can't drag the step backward.
	if _current_step != "consciousness_fragments":
		return
	_enter_step("fade_in")
	# Full reveal: escort units, full lighting
	for unit in [_escort_1, _escort_2]:
		if unit:
			unit.visible = true
	_emergency_light.light_energy = 3.0
	# Scheduler-driven fade-in (see _on_process) so it speeds with F in lockstep
	# with the scheduled waking transition.
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(1.5, _start_waking, "waking")

func _start_waking() -> void:
	_enter_step("waking")
	_dialogue_chain(
		[
			"elevator.narration.room",
			"elevator.aster.wake",
			"elevator.peris.wake",
		],
		func(): _scheduler.schedule_after(1.0, _start_approach_aster, "approach")
	)

func _start_approach_aster() -> void:
	_enter_step("approach_aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")
	_show_aster_wake_interactable()

func _start_wake_aster() -> void:
	_enter_step("wake_aster")
	_clear_aster_wake_interactable()
	_hud.set_portrait_status("aster", "")
	_hud.set_portrait_stat("aster", "sta", 100)
	DialogueData.say_to(_dialogue, "elevator.aster.surface")
	# Tween Aster upright
	var tween := create_tween()
	tween.tween_property(_aster_node, "rotation_degrees:z", 0.0, 1.5)
	_dialogue.dialogue_finished.connect(func():
		_scheduler.schedule_after(0.5, _start_conversation, "conversation")
	, CONNECT_ONE_SHOT)

func _show_aster_wake_interactable() -> void:
	if _aster_wake_interactable != null and is_instance_valid(_aster_wake_interactable):
		return
	var parent := _chunks.get("elevator", null) as Node3D
	if parent == null:
		parent = find_child("Environment", false, false) as Node3D
	var zone_pos := ASTER_POS + Vector3(0.0, 0.05, 0.0)
	_aster_wake_interactable = _create_interactable(parent, zone_pos, "AsterWakeZone", 2.0, 0.6, "Wake", true)
	_aster_wake_interactable.description = "Aster"
	_aster_wake_interactable.required_character = "peris"
	_aster_wake_interactable.active_character = "peris"
	_aster_wake_interactable.interacted.connect(_on_aster_wake_interacted)
	_aster_wake_interactable.call_deferred("show_tutorial_label")

func _clear_aster_wake_interactable() -> void:
	if _aster_wake_interactable == null or not is_instance_valid(_aster_wake_interactable):
		_aster_wake_interactable = null
		return
	_aster_wake_interactable.visible = false
	_aster_wake_interactable.monitoring = false
	_aster_wake_interactable.monitorable = false
	if _aster_wake_interactable.has_method("hide_tutorial_label"):
		_aster_wake_interactable.hide_tutorial_label()
	_aster_wake_interactable.queue_free()
	_aster_wake_interactable = null

func _on_aster_wake_interacted() -> void:
	if _current_step != "approach_aster":
		return
	_tutorial_prompt.hide_prompt()
	_player.set_move_enabled(false)
	_start_wake_aster()

func _start_conversation() -> void:
	_enter_step("conversation")
	_dialogue.default_hold_time = 3.0
	_dialogue_chain([
		"elevator.peris.clock",
		"elevator.aster.device",
		"elevator.peris.doors",
	], _start_system_restored, 0.5)

func _start_system_restored() -> void:
	_enter_step("system_restored")
	_camera.shake(0.1, 8.0)
	# Establish the asymmetric baseline: Aster's map is online, while Peris's memory layer is available but off.
	# The fork later gives the second toggle a concrete use instead of teaching portrait selection in the abstract.
	_unlock_elevator_overlays()
	DialogueData.say_to(_dialogue, "elevator.unit.wake")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0.5, _start_units_activate, "units_activate"),
		CONNECT_ONE_SHOT
	)

func _start_units_activate() -> void:
	_enter_step("units_activate")
	# Hold the units in their alcoves while the protocol exchange plays. Their approach is the final
	# visible warning immediately before tactical time pauses, not background motion under dialogue.
	_emp_guard_approach_active = false
	_emp_guard_arrivals.clear()
	_escort_1.stop()
	_escort_2.stop()
	_camera.shake(0.2, 6.0)
	_dialogue_chain(
		["elevator.unit.protocol", "elevator.peris.urgent", "elevator.aster.emp"],
		_start_emp_guard_approach
	)

func _start_emp_guard_approach() -> void:
	if _current_step != "units_activate":
		return
	_emp_guard_approach_active = true
	_emp_guard_arrivals.clear()
	var party_center := _get_emp_party_center()
	var guards := {
		"eu1": _escort_1,
		"eu2": _escort_2,
	}
	for guard_id in guards:
		var guard: Node3D = guards[guard_id]
		var target := _get_emp_guard_standoff_pos(str(guard_id), guard, party_center)
		var current := _game_state.get_position(str(guard_id))
		if Vector2(current.x - target.x, current.z - target.z).length() < 0.15:
			_emp_guard_arrivals[str(guard_id)] = true
		else:
			guard.walk_to(target)
	_maybe_finish_emp_guard_approach()

func _on_emp_guard_arrived(id: String) -> void:
	if not _emp_guard_approach_active or not (id in ["eu1", "eu2"]):
		return
	_emp_guard_arrivals[id] = true
	_maybe_finish_emp_guard_approach()

func _maybe_finish_emp_guard_approach() -> void:
	if not _emp_guard_approach_active:
		return
	if not bool(_emp_guard_arrivals.get("eu1", false)) \
			or not bool(_emp_guard_arrivals.get("eu2", false)):
		return
	_emp_guard_approach_active = false
	_start_emp_tutorial()

func _get_emp_party_center() -> Vector3:
	var peris_pos := _game_state.get_position("peris") if _game_state and _game_state.characters.has("peris") else _peris_node.global_position
	var aster_pos := _game_state.get_position("aster") if _game_state and _game_state.characters.has("aster") else _aster_node.global_position
	return (peris_pos + aster_pos) * 0.5

func _get_emp_guard_standoff_pos(guard_id: String, guard_node: Node3D, party_center: Vector3) -> Vector3:
	var guard_pos := _game_state.get_position(guard_id) if _game_state and _game_state.characters.has(guard_id) else guard_node.global_position
	var away_from_party := guard_pos - party_center
	away_from_party.y = 0.0
	if away_from_party.length() < 0.01:
		away_from_party = Vector3.LEFT
	var standoff := party_center + away_from_party.normalized() * EMP_GUARD_STANDOFF_DISTANCE
	standoff.y = guard_pos.y
	return standoff

func _start_emp_tutorial() -> void:
	_enter_step("emp_tutorial")
	# EMP belongs to Aster.
	_select_character("aster")
	_emp_pause_locked = true
	_emp_queued = false
	_hud.set_ability_state("emp", "ready")
	_tutorial_prompt.show_prompt("%s - queue Aster's EMP" % InputHints.bracket(EMP_INPUT_ACTION))
	_scheduler.pause()
	_hud.set_paused(true)

func _start_emp_focus() -> void:
	var party_center := _get_emp_party_center()
	for guard_info in [["eu1", _escort_1], ["eu2", _escort_2]]:
		var guard_id := str(guard_info[0])
		var guard := guard_info[1] as Node3D
		var standoff := _get_emp_guard_standoff_pos(guard_id, guard, party_center)
		_game_state.snap_character_to(guard_id, standoff)
	_start_emp_tutorial()

func _start_emp_tutorial_2() -> void:
	_enter_step("emp_tutorial_2")

## Bind the authored EMP nodes to one in-world AnimationPlayer. The fixed meshes,
## materials, lights, and faceplate hierarchy live in .tscn files; this script only
## adds tracks for runtime-owned elevator lights and guard instances.
func _build_emp_visuals() -> void:
	if _emp_animation_player != null:
		return
	_emp_visual_root = get_node_or_null("EmpVisuals") as Node3D
	if _emp_visual_root == null:
		push_error("Elevator: authored EmpVisuals scene is missing")
		return
	_emp_pulse_visual = _emp_visual_root.get_node_or_null("EmpPulseVisual") as MeshInstance3D
	_emp_pulse_core = _emp_visual_root.get_node_or_null("EmpPulseCore") as MeshInstance3D
	_emp_pulse_light = _emp_visual_root.get_node_or_null("EmpPulseLight") as OmniLight3D
	_emp_animation_player = _emp_visual_root.get_node_or_null("EmpAnimationPlayer") as AnimationPlayer
	if _emp_pulse_visual == null or _emp_pulse_core == null or _emp_pulse_light == null \
			or _emp_animation_player == null:
		push_error("Elevator: authored EMP effect is incomplete")
		_emp_animation_player = null
		return
	# Animation paths are authored/built relative to the Elevator root so the one
	# player can address both EmpVisuals children and runtime guard/light nodes.
	_emp_animation_player.root_node = NodePath("../..")
	_emp_faceplates.clear()
	_emp_faceplate_lights.clear()
	for unit in [_escort_1, _escort_2]:
		var faceplate_effect := EMP_FACEPLATE_SCENE.instantiate() as Node3D
		unit.add_child(faceplate_effect)
		var faceplate := faceplate_effect.get_node("Faceplate") as MeshInstance3D
		var face_light := faceplate_effect.get_node("FaceLight") as OmniLight3D
		_emp_faceplates.append(faceplate)
		_emp_faceplate_lights.append(face_light)
	var animation := Animation.new()
	animation.length = EMP_VISUAL_DURATION
	animation.loop_mode = Animation.LOOP_NONE
	_emp_add_track(animation, _emp_pulse_visual, "visible", [
		[0.0, true], [1.08, false],
	], true)
	_emp_add_track(animation, _emp_pulse_visual, "scale", [
		[0.0, Vector3.ONE * 0.12], [0.12, Vector3.ONE * 0.35],
		[0.95, Vector3.ONE * 5.2], [1.06, Vector3.ONE * 5.4],
	])
	# A short emissive core and local blue flash make the source readable even
	# against the elevator's red lighting; the torus then carries direction/scale.
	_emp_add_track(animation, _emp_pulse_core, "visible", [
		[0.0, true], [0.32, false],
	], true)
	_emp_add_track(animation, _emp_pulse_core, "scale", [
		[0.0, Vector3.ONE * 0.12], [0.10, Vector3.ONE * 0.55],
		[0.30, Vector3.ONE * 0.78],
	])
	_emp_add_track(animation, _emp_pulse_light, "light_energy", [
		[0.0, 0.0], [0.05, 2.5], [0.20, 1.1], [0.58, 0.0],
	])
	for index in range(_emp_faceplates.size()):
		var faceplate: MeshInstance3D = _emp_faceplates[index]
		var face_light: OmniLight3D = _emp_faceplate_lights[index]
		_emp_add_track(animation, faceplate, "transparency", [
			[0.0, 0.0], [0.30, 0.70], [0.45, 0.12], [0.60, 0.82],
			[0.75, 0.32], [0.95, 1.0],
		])
		_emp_add_track(animation, face_light, "light_energy", [
			[0.0, 1.3], [0.30, 0.05], [0.45, 0.9], [0.60, 0.02],
			[0.75, 0.45], [0.95, 0.0],
		])
	var escort_1_rotation: Vector3 = _escort_1.rotation
	var escort_2_rotation: Vector3 = _escort_2.rotation
	_emp_add_track(animation, _escort_1, "rotation", [
		[0.0, escort_1_rotation], [0.75, escort_1_rotation],
		[1.02, escort_1_rotation + Vector3(0.0, 0.0, -0.18)],
	])
	_emp_add_track(animation, _escort_2, "rotation", [
		[0.0, escort_2_rotation], [0.75, escort_2_rotation],
		[1.02, escort_2_rotation + Vector3(0.0, 0.0, 0.18)],
	])
	_emp_add_track(animation, _emergency_light, "light_energy", [
		[0.0, 1.5], [0.08, 5.0], [0.18, 0.15], [0.30, 2.5], [0.48, 0.35],
	])
	_emp_add_track(animation, _elevator_fill_light, "light_energy", [
		[0.0, 1.0], [0.12, 1.4], [0.52, 0.18],
	])
	_emp_add_track(animation, _elevator_indicator_glow, "light_energy", [
		[0.0, 1.4], [0.12, 3.0], [0.46, 0.0],
	])
	for standby in _elevator_standby_lights:
		_emp_add_track(animation, standby, "light_energy", [
			[0.0, 0.5], [0.18, 0.9], [0.58, 0.08],
		])
	_emp_add_track(animation, _floor_indicator, "modulate", [
		[0.0, Color(2.0, 0.45, 0.2, 1.0)], [0.46, Color(0.08, 0.02, 0.01, 0.0)],
	])
	_emp_add_track(animation, _indicator_b_label, "modulate", [
		[0.0, Color(2.0, 0.45, 0.2, 1.0)], [0.46, Color(0.08, 0.02, 0.01, 0.0)],
	])
	var library := AnimationLibrary.new()
	library.add_animation("emp_discharge", animation)
	_emp_animation_player.add_animation_library("", library)

func _emp_add_track(
		animation: Animation,
		target: Node,
		property: String,
		keys: Array,
		discrete := false
	) -> void:
	if target == null:
		return
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("%s:%s" % [str(get_path_to(target)), property]))
	animation.value_track_set_update_mode(
		track,
		Animation.UPDATE_DISCRETE if discrete else Animation.UPDATE_CONTINUOUS
	)
	for key in keys:
		animation.track_insert_key(track, float(key[0]), key[1])

func _play_emp_discharge_animation() -> void:
	_elevator_powered = false
	if _indicator_b_label != null:
		_indicator_b_label.visible = true
	if _emp_visual_root != null and _aster_node != null:
		_emp_visual_root.global_position = _aster_node.global_position + Vector3(0.0, 0.48, 0.0)
		_emp_pulse_visual.transparency = 0.0
		_emp_pulse_core.transparency = 0.0
	if _emp_animation_player != null and _emp_animation_player.has_animation("emp_discharge"):
		_emp_animation_player.stop()
		_emp_animation_player.speed_scale = _compute_speed()
		_emp_animation_player.play("emp_discharge")
		_emp_animation_player.advance(0.0)

## Scheduler beats and AnimationPlayer frames are deliberately separate clocks.
## On a fast-forward frame or render hitch, doors_unlock can win their tie at 1.5 s
## before the animation samples its final hidden-pulse key. Rally then pauses the
## encounter with the expanded, nearly edge-on torus still covering the elevator.
## Settle the authored end state explicitly at the scheduler boundary.
func _finish_emp_discharge_animation() -> void:
	if _emp_animation_player != null:
		if _emp_animation_player.has_animation("emp_discharge"):
			_emp_animation_player.seek(EMP_VISUAL_DURATION, true)
		_emp_animation_player.stop()
	if _emp_pulse_visual != null:
		_emp_pulse_visual.visible = false
		_emp_pulse_visual.transparency = 0.0
	if _emp_pulse_core != null:
		_emp_pulse_core.visible = false
		_emp_pulse_core.transparency = 0.0
	if _emp_pulse_light != null:
		_emp_pulse_light.light_energy = 0.0
	# AnimationPlayer's sampled `transparency = 1` is not a reliable rendered
	# shutdown on Web when the faceplate material itself is opaque/emissive. Cash
	# out the consequence as visibility as well as energy so a stopped animation
	# cannot leave a powered-blue plate in the rally frame.
	for faceplate in _emp_faceplates:
		if is_instance_valid(faceplate):
			faceplate.transparency = 1.0
			faceplate.visible = false
	for face_light in _emp_faceplate_lights:
		if is_instance_valid(face_light):
			face_light.light_energy = 0.0

func _restore_elevator_power_visuals() -> void:
	_elevator_powered = true
	if _emp_animation_player != null:
		_emp_animation_player.stop()
	if _emp_pulse_visual != null:
		_emp_pulse_visual.visible = false
		_emp_pulse_visual.transparency = 0.0
	if _emp_pulse_core != null:
		_emp_pulse_core.visible = false
		_emp_pulse_core.transparency = 0.0
	if _emp_pulse_light != null:
		_emp_pulse_light.light_energy = 0.0
	for faceplate in _emp_faceplates:
		if is_instance_valid(faceplate):
			faceplate.visible = true
			faceplate.transparency = 0.0
	for face_light in _emp_faceplate_lights:
		if is_instance_valid(face_light):
			face_light.light_energy = 1.3
	if _escort_1 != null:
		_escort_1.rotation.z = 0.0
	if _escort_2 != null:
		_escort_2.rotation.z = 0.0
	if _emergency_light != null:
		_emergency_light.light_energy = 1.5
	if _elevator_fill_light != null:
		_elevator_fill_light.light_energy = 1.0
	if _elevator_indicator_glow != null:
		_elevator_indicator_glow.light_energy = 1.4
	for standby in _elevator_standby_lights:
		if is_instance_valid(standby):
			standby.light_energy = 0.5
	if _floor_indicator != null:
		_floor_indicator.modulate = Color(2.0, 0.45, 0.2, 1.0)
	if _indicator_b_label != null:
		_indicator_b_label.modulate = Color(2.0, 0.45, 0.2, 1.0)

func _start_doors_unlocked() -> void:
	_enter_step("doors_unlocked")
	_reboot_active = false
	_scheduler.cancel_tag("reboot")
	_tutorial_prompt.hide_prompt()
	_finish_emp_discharge_animation()
	# The pulse animation has already shown the faceplates and room panels dying. Cash out that visible
	# consequence directly: the failed lock releases and the doors cycle, with no prose card describing it.
	_start_doors_open()

func _start_doors_open() -> void:
	if not _enter_step("doors_open"):
		return
	_set_exit_button_interactable(false)
	if _door_panel_a and _door_panel_b:
		var tween := create_tween()
		tween.tween_property(_door_panel_a, "position:z", -1.5, 1.5)
		tween.parallel().tween_property(_door_panel_b, "position:z", 1.5, 1.5)
	var outside_light := OmniLight3D.new()
	outside_light.position = Vector3(3.5, 1.5, 0)
	outside_light.light_color = Color(0.4, 0.4, 0.5)
	outside_light.light_energy = 2.0
	outside_light.omni_range = 6.0
	find_child("Environment", false, false).add_child(outside_light)
	_scheduler.schedule_after(2.0, _start_rally_tutorial, "rally_tutorial")

func _start_rally_tutorial() -> void:
	_enter_step("rally_tutorial")
	# Rally is deliberately NOT selection. Keep the existing primary as a singleton so this beat proves
	# the held command reaches the whole controllable roster without mutating party-selection semantics.
	_selected_character_ids = [_active_character]
	_suppress_hud_character_signal = true
	_hud.set_multi_select_enabled(false)
	_hud.set_active_portrait(_active_character)
	_hud.set_selected_portraits(_selected_character_ids)
	_suppress_hud_character_signal = false
	_apply_character_control_selection()
	_scheduler.pause()
	_hud.set_paused(true)
	_hud.show_message("RALLY ALL READY  //  preview both final positions, then release to queue", 3.0)
	# The former spreadsheet line explicitly taught multi-selection, which is no longer this beat's
	# mechanic. Keep the instruction truthful and immediate; perspective selection is taught later.
	_update_rally_tutorial_prompt()

func _start_corridor() -> void:
	_enter_step("corridor")
	_tutorial_prompt.hide_prompt()
	# This is the causal release for the doorway boundary: before this step the
	# streamed exterior may render, but it cannot accept or retain a movement route.
	_unlock_upper_exit_footprint()
	# Leaving the elevator: the view can follow the party out into the corridor.
	if _camera != null and _camera.has_method("clear_look_bounds"):
		_camera.clear_look_bounds()
	# Reveal the chunks streamed in during the opening (instant if the background build finished; otherwise this
	# block-finishes the remainder — never worse than the old synchronous load).
	reveal_chunk("bridge")
	reveal_chunk("below")
	var exit_pos := Vector3(ELEVATOR_SIZE.x / 2.0 + 3.0, 0, 0)
	_game_state.command_move_to_pos("aster", exit_pos)
	_game_state.command_move_to_pos("peris", exit_pos + Vector3(0, 0, 1.0))
	_dialogue_chain([
		"elevator.narration.doors",
		"elevator.peris.device_q",
		"elevator.aster.outcome",
		"elevator.aster.spoof",
		"elevator.aster.only_community",
		"elevator.peris.disgust",
		"elevator.aster.not_into",
		"elevator.peris.interesting",
		"elevator.aster.curious",
		"elevator.peris.not_supposed",
		"elevator.aster.no_service",
	], func(): _scheduler.schedule_after(2.0, _start_bridge, "bridge"))

func _start_bridge() -> void:
	_enter_step("bridge")
	# Focused bridge probes and old saves bypass Aster's wake tween. The bridge beat
	# starts with both characters conscious, so do not carry the incapacitated pose
	# into a traversal/collapse test.
	if _aster_node != null:
		_aster_node.rotation_degrees.z = 0.0
	# Focused bridge starts and old saves may enter here without the corridor beat.
	_unlock_upper_exit_footprint()
	# Those entry seams also bypass _start_corridor(), which normally releases the
	# cabin-only camera clamp. Leaving it active pins the look point inside the
	# elevator while the party and route ribbons move onto the bridge, producing a
	# black level with floating horizontal paths in focused Web playtests/saves.
	if _camera != null and _camera.has_method("clear_look_bounds"):
		_camera.clear_look_bounds()
	_player.set_move_enabled(false)
	# Step onto the START of the bridge; the player then walks across and it gives way mid-span,
	# dropping the party onto the broken section (where the climb prompt waits), clear of the ecology.
	# Stage just inside the long intact span. At BRIDGE_START_X exactly, the
	# close follow camera sits outside the corridor side wall and looks through
	# its occluded end-cap; the room appears black and ground rays land on that
	# hidden corner instead of the bridge. Two metres preserves the long crossing
	# while putting both the view and its command rays clear of the corridor shell.
	var bridge_pos := Vector3(BRIDGE_START_X + 2.0, 0, 0)
	_game_state.command_move_to_pos("aster", bridge_pos + Vector3(1.0, 0, 0))
	_game_state.command_move_to_pos("peris", bridge_pos)
	# One line at the bridge mouth, THEN hand control — the rest of the crossing dialogue fires by POSITION as the
	# party walks the (now long) span (_process), so it paces across the crossing instead of stacking up front.
	_bridge_lines_pending = ["elevator.peris.bodies", "elevator.aster.logs", "elevator.aster.ahead"]
	_bridge_lines_fired = 0
	DialogueData.say_to(_dialogue, "elevator.bridge.narration")
	_dialogue.dialogue_finished.connect(func():
		# Hand control to the player: walk out across the bridge — that's what collapses it.
		_player.set_move_enabled(true)
		_tutorial_prompt.show_prompt("Rally both units across the bridge")
	, CONNECT_ONE_SHOT)

# --- Bridge Collapse ---

func _start_bridge_collapse() -> void:
	_enter_step("bridge_collapse")
	_fall_landed_fired = false
	_peris_node.set_move_enabled(false)
	_aster_node.set_move_enabled(false)
	_game_state.command_stop("aster")
	_game_state.command_stop("peris")
	if _escort_1:
		_escort_1.visible = false
	if _escort_2:
		_escort_2.visible = false
	_camera.shake(0.4, 2.0)
	DialogueData.say_to(_dialogue, "elevator.narration.collapse")
	DialogueData.say_to(_dialogue, "elevator.peris.floor")
	_scheduler.schedule_after(0.8, _execute_bridge_fall, "bridge_fall")

func _execute_bridge_fall() -> void:
	_camera.shake(0.75, 1.5)
	var fall_duration := 1.4
	var bridge_chunk: Node3D = _chunks.get("bridge")
	var bridge_floor: Node3D = bridge_chunk.find_child("BridgeFloor", false, false) if bridge_chunk else null
	var model: Node3D = bridge_floor.find_child("BridgeModel", false, false) if bridge_floor != null else null
	if bridge_floor != null:
		# The visible girders become debris below; retire their continuous traversal blockers in the same beat.
		for rail_name in ["BridgeRailCollisionL", "BridgeRailCollisionR"]:
			var rail_body := bridge_floor.get_node_or_null(rail_name)
			if rail_body != null:
				rail_body.queue_free()
	# HYBRID collapse: the span shears where the player stands and the break races outward (art-directed
	# cascade); each modeled piece is then handed to PHYSICS to tumble and settle (believable). Cosmetic,
	# wall-clock — the party's landing rides the scheduler (_on_fall_landed) so replay/fast-forward match.
	var break_x: float = _game_state.get_position("aster").x
	if model != null:
		_collapse_bridge_model(model, break_x)
		_spawn_collapse_dust(bridge_floor, break_x)
	# The party rides the failing centre down (visual); the data-layer landing is the scheduler's.
	# Remember the pre-fall camera height so the landing can restore it — the fall DIPS follow_offset.y for a
	# plunging framing, and since the camera also follows the target's Y down, leaving the dip in would frame the
	# lower deck a full BELOW_Y too low (the "camera stuck in an odd location" after the collapse).
	_fall_prev_offset_y = _camera.follow_offset.y
	_fall_offset_dipped = true
	var tween := create_tween()
	tween.set_parallel(true)
	for char_node in [_peris_node, _aster_node]:
		tween.tween_property(char_node, "position:y", BELOW_Y + 0.5, fall_duration * 0.8) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_camera, "follow_offset:y", _camera.follow_offset.y + BELOW_Y, fall_duration)
	_fall_tween = tween
	_scheduler.schedule_after(fall_duration * 1.05, _on_fall_landed, "fall_landed")

## Turn the modeled span into falling debris: each piece becomes a frozen RigidBody at its current pose,
## then is RELEASED in a cascade from the break point (art-directed timing) with a shove + tumble, after
## which gravity + the catch-floor do the believable settle. Cosmetic + wall-clock (uses SceneTree timers
## and the physics server), so it never touches the data layer; the catch-floor is on its own physics
## layer so debris collides with nothing but the floor (no character interference, no inter-piece blowups).
func _collapse_bridge_model(model: Node3D, break_x: float) -> void:
	_collapse_visual_active = true
	_collapse_debris.clear()
	_collapse_stagger_tweens.clear()
	_collapse_paused_debris.clear()
	var host: Node = model.get_parent()
	# A catch-floor at the lower deck so the debris lands instead of falling forever.
	var catch := StaticBody3D.new()
	catch.name = "DebrisCatch"
	catch.collision_layer = DEBRIS_FLOOR_LAYER
	catch.collision_mask = 0
	var ccs := CollisionShape3D.new()
	var cbx := BoxShape3D.new()
	cbx.size = Vector3(60, 1.0, 30)
	ccs.shape = cbx
	catch.add_child(ccs)
	catch.position = Vector3(break_x, BELOW_Y - 0.4, 0)
	host.add_child(catch)
	# Snapshot the pieces first (we reparent them, which mutates the child list).
	var pieces: Array[MeshInstance3D] = []
	for child in model.get_children():
		if child is MeshInstance3D:
			pieces.append(child)
	for mi in pieces:
		var gx := mi.global_transform
		var ab := mi.get_aabb()  # local, centred on the piece origin
		var rb := RigidBody3D.new()
		rb.collision_layer = DEBRIS_PIECE_LAYER
		rb.collision_mask = DEBRIS_FLOOR_LAYER   # only the catch-floor — never each other or characters
		rb.gravity_scale = 1.4
		rb.freeze = true
		_collapse_debris.append(rb)
		host.add_child(rb)
		rb.global_transform = gx
		mi.get_parent().remove_child(mi)
		rb.add_child(mi)
		mi.transform = Transform3D()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = ab.size.max(Vector3(0.05, 0.05, 0.05))
		cs.shape = bx
		cs.position = ab.position + ab.size * 0.5  # AABB centre (≈ origin for these boxes)
		rb.add_child(cs)
		var delay: float = minf(absf(gx.origin.x - break_x) * 0.05, 0.5)
		_release_debris(rb, delay, break_x, _bridge_piece_spin(gx.origin.x))
	model.queue_free()  # the (now-empty) original model node
	# Free everything once the debris has visually settled (wall-clock; the physics is cosmetic).
	# A tween bound to the sequence, NOT a SceneTree timer: the tree's timers outlive a freed
	# scene and fire against freed captures; this dies with the scene. (Headless/data-layer
	# teardown calls _remove_collapsed_chunks directly.)
	_collapse_settle_tween = create_tween()
	_collapse_settle_tween.tween_interval(3.0)
	_collapse_settle_tween.tween_callback(_remove_collapsed_chunks)

## Release one debris piece: unfreeze it and give it a shove away from the break + a downward kick and
## the deterministic tumble. `delay` staggers the cascade (a SceneTree timer; instant when ~0).
func _release_debris(rb: RigidBody3D, delay: float, break_x: float, spin: Vector3) -> void:
	rb.set_meta("collapse_break_x", break_x)
	rb.set_meta("collapse_spin", spin)
	rb.set_meta("collapse_release_ready", false)
	rb.set_meta("collapse_impulse_applied", false)
	var fire := func() -> void:
		if not is_instance_valid(rb):
			return
		rb.set_meta("collapse_release_ready", true)
		_release_debris_now(rb)
	if delay <= 0.001:
		fire.call()
	else:
		# bound to the piece itself -- a freed piece (scene teardown mid-tumble) kills its
		# pending stagger instead of leaving a tree-owned timer to fire on freed captures
		var stagger := rb.create_tween()
		_collapse_stagger_tweens.append(stagger)
		stagger.tween_interval(delay)
		stagger.tween_callback(fire)

func _release_debris_now(rb: RigidBody3D) -> void:
	if not is_instance_valid(rb) or _collapse_visual_paused \
			or bool(rb.get_meta("collapse_impulse_applied", false)):
		return
	var break_x := float(rb.get_meta("collapse_break_x", rb.global_position.x))
	var spin: Vector3 = rb.get_meta("collapse_spin", Vector3.ZERO)
	rb.freeze = false
	var away: float = signf(rb.global_position.x - break_x)
	if away == 0.0:
		away = 1.0
	rb.apply_central_impulse(Vector3(away * 1.3, -1.0, 0.0))
	rb.angular_velocity = spin * 2.2
	rb.set_meta("collapse_impulse_applied", true)

## Deterministic per-piece tumble (hashed from its X, never wall-clock RNG — replay-stable seeding).
func _bridge_piece_spin(x: float) -> Vector3:
	var h := int(absf(x) * 17.0)
	return Vector3(
		0.7 + float(h % 6) * 0.22,           # pitch
		-0.5 + float((h / 6) % 7) * 0.18,    # yaw
		-0.6 + float((h / 42) % 6) * 0.24    # roll
	)

## A one-shot dust burst at the break point — sells the impact as the span shears apart.
func _spawn_collapse_dust(parent: Node3D, at_x: float) -> void:
	if parent == null:
		return
	var dust := CPUParticles3D.new()
	dust.position = Vector3(at_x, -0.1, 0.0)
	dust.amount = 48
	dust.lifetime = 1.8
	dust.one_shot = true
	dust.explosiveness = 0.6
	dust.spread = 70.0
	dust.direction = Vector3(0, -0.3, 0)
	dust.gravity = Vector3(0, -3.0, 0)
	dust.initial_velocity_min = 1.5
	dust.initial_velocity_max = 4.0
	dust.scale_amount_min = 0.25
	dust.scale_amount_max = 0.7
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.32, 0.3, 0.28, 0.45)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = dmat
	dust.mesh = quad
	dust.emitting = true
	parent.add_child(dust)

func _on_fall_landed() -> void:
	# Fires from the scheduled landing (or a test force-fire) — exactly once.
	if _fall_landed_fired:
		return
	_fall_landed_fired = true
	_camera.shake(0.3, 6.0)
	# The party is now on the lower deck (their node Y carries the drop via the level transition below), so undo
	# the fall's camera DIP or the lower deck frames a full BELOW_Y too low. Kill the cosmetic wall-clock fall
	# tween first so it can't animate follow_offset.y back down after we restore it (matters under fast-forward,
	# where the scheduled landing fires before the wall-clock tween finishes).
	if _fall_offset_dipped:
		if _fall_tween != null and _fall_tween.is_valid():
			_fall_tween.kill()
		_camera.follow_offset.y = _fall_prev_offset_y
		_fall_offset_dipped = false
	# Land STRAIGHT DOWN where the span gave way — the broken section juts out mid-span here (the climb
	# prompt + fork sit at this X), so the party drops onto the ecology below, no teleport to a far ledge.
	for char_id in ["peris", "aster"]:
		var pos: Vector3 = _game_state.get_position(char_id)
		# Real cross-level transition (logs KIND_SET_LEVEL): the data-layer Y snaps to the LOWER deck and
		# the move stops, so movement, detection, and paths now read at the lower floor — not a hand-poked Y.
		_game_state.set_character_level(char_id, LEVEL_LOWER)
		var lp: Vector3 = _game_state.get_position(char_id)
		_game_state.characters[char_id]["position"] = Vector3(pos.x, lp.y, lp.z)
		if _game_state.grid != null:
			_game_state.characters[char_id]["grid_cell"] = _game_state.grid.world_to_grid(_game_state.characters[char_id]["position"])
	_set_lower_route_camera_bounds()
	# Geometry was revealed above the bridge so the lower route could be read, but
	# its ecology has remained outside GameState and entirely unprocessed.  The
	# landing is the first moment those actors can affect (or be affected by) the
	# party, so wake the cohort now in one batched detection update.
	_activate_below_fauna()
	# Free the old level once the debris has visually settled. In real play _collapse_bridge_model set
	# _collapse_visual_active and owns the removal (a wall-clock timer), so we don't rip the bridge away
	# mid-fall. Headless / force-fire (no live collapse) removes here.
	if not _collapse_visual_active:
		_remove_collapsed_chunks()
	_scheduler.schedule_after(1.0, _start_fallen, "fallen")

## Cosmetic: free the elevator + bridge chunks (the old, fallen-away level) once the debris has settled.
## Idempotent — runs from the settle timer (real play) or directly (headless), whichever resolves first.
func _remove_collapsed_chunks() -> void:
	if _collapsed_chunks_removed:
		return
	_collapsed_chunks_removed = true
	_collapse_visual_active = false
	_collapse_settle_tween = null
	_collapse_stagger_tweens.clear()
	_collapse_debris.clear()
	_collapse_paused_debris.clear()
	_unload_chunk("elevator")
	_unload_chunk("bridge")
	_emergency_light = null
	_elevator_fill_light = null
	_elevator_indicator_glow = null
	_elevator_standby_lights.clear()
	_indicator_b_label = null
	_floor_indicator = null
	_door_panel_a = null
	_door_panel_b = null
	_no_exit_label = null

func _start_fallen() -> void:
	_enter_step("fallen")
	_dialogue_chain([
		"elevator.narration.landing",
		"elevator.narration.scramble",
		"elevator.aster.way_back",
		"elevator.peris.laugh",
		"elevator.aster.funny",
		"elevator.peris.most_felt",
	], func(): _scheduler.schedule_after(1.0, _start_climb_attempt, "climb"))

func _start_climb_attempt() -> void:
	_enter_step("climb_attempt")
	# Establish that the bridge cannot be retraced.
	_dialogue_chain([
		"elevator.narration.wall_try",
		"elevator.aster.climb",
		"elevator.peris.climb",
	], func():
		_show_climb_interactable()
	)

func _show_climb_interactable() -> void:
	if _climb_interactable != null and is_instance_valid(_climb_interactable):
		return
	var parent := _chunks.get("below", null) as Node3D
	if parent == null:
		parent = find_child("Environment", false, false) as Node3D
	# Sits under where the bridge gave way (~2/3 across), so the party checks the collapse right where they fell,
	# not a walk back to a far ledge. Derived from the party's landing X so it tracks BRIDGE_COLLAPSE_X.
	var land_x: float = _game_state.get_position("aster").x if _game_state != null and _game_state.characters.has("aster") else BRIDGE_COLLAPSE_X
	var zone_pos := Vector3(land_x, BELOW_Y + 0.05, 0.0)
	_climb_interactable = _create_interactable(parent, zone_pos, "ClimbPromptZone", 2.4, 0.8, "Climb", true)
	_climb_interactable.description = "Collapsed Bridge"
	_climb_interactable.interacted.connect(_on_climb_prompt_interacted)
	_climb_interactable.call_deferred("show_tutorial_label")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Climb zone - check the collapsed bridge")

func _on_climb_prompt_interacted() -> void:
	if _current_step != "climb_attempt":
		return
	_tutorial_prompt.hide_prompt()
	if _climb_interactable != null and is_instance_valid(_climb_interactable):
		_climb_interactable.queue_free()
		_climb_interactable = null
	# Bridge can't be retraced — now choose a way forward through the fork.
	_scheduler.schedule_after(0.2, _start_route_read_circuit, "route_reads")

func _start_route_read_circuit() -> void:
	if not _enter_step("route_read_circuit"):
		return
	_unlock_elevator_overlays()
	_player.set_move_enabled(true)
	DialogueData.say_to(_dialogue, "elevator.narration.fork")
	DialogueData.say_to(_dialogue, "elevator.narration.look")
	# Aster's already-live data map supplies one side of the comparison without another interaction tax.
	if not bool(_route_reads_resolved.get("aster", false)):
		_route_reads_resolved["aster"] = true
		DialogueData.say_to(_dialogue, "elevator.aster.short_way")
	_apply_elevator_overlay_visibility()
	if bool(_elevator_overlay_states.get("peris", false)):
		_resolve_peris_overlay_route_read()
	else:
		_tutorial_prompt.show_action_prompt(
			&"preview_overlay_peris",
			"Aster maps the Flures. Turn on Peris's memory overlay to reveal the iron fields' exact safe edge.",
			0.0,
			"F2"
		)

## Focused browser/native probe for the route-read composite. It preserves the
## ordinary lower-deck build and fauna lifecycle while skipping the bridge fall.
func _start_route_focus() -> void:
	for entry in [
		["peris", Vector3(ROUTE_READ_PERIS_POS.x, BELOW_Y, ROUTE_READ_PERIS_POS.z)],
		["aster", Vector3(ROUTE_READ_ASTER_POS.x, BELOW_Y, ROUTE_READ_ASTER_POS.z)],
	]:
		var character_id := str(entry[0])
		_game_state.set_character_level(character_id, LEVEL_LOWER)
		_game_state.snap_character_to(character_id, entry[1])
		var character_node: Node3D = _peris_node if character_id == "peris" else _aster_node
		character_node.global_position = (entry[1] as Vector3) + Vector3(0.0, 0.5, 0.0)
	_activate_below_fauna()
	_select_character("peris")
	# The ordinary bridge beat releases the cabin clamp before the fall. A focused
	# route probe bypasses that seam, so release and snap it explicitly.
	if _camera != null:
		_set_lower_route_camera_bounds()
		_camera.call("_update_immediate")
	_start_route_read_circuit()

## Focused browser/native probe for the hallway's final causal gate. Both characters begin on their
## clearly labelled brace marks so success can be inspected immediately; the dedicated wreckage test
## drives the one-person failure and verifies that the ordinary enemy FSM delivers the consequence.
func _start_wreckage_focus() -> void:
	var anchor := _wreckage_interaction_anchor()
	for entry in [
		["peris", anchor + Vector3(-1.0, 0.0, -1.0)],
		["aster", anchor + Vector3(-1.0, 0.0, 1.0)],
	]:
		var character_id := str(entry[0])
		var position := entry[1] as Vector3
		_game_state.set_character_level(character_id, LEVEL_LOWER)
		_game_state.snap_character_to(character_id, position)
		var character_node: Node3D = _peris_node if character_id == "peris" else _aster_node
		character_node.global_position = position + Vector3(0.0, 0.5, 0.0)
	_activate_below_fauna()
	_route_reads_resolved["aster"] = true
	_route_reads_resolved["peris"] = true
	for beat_i in range(ROUTE_BEAT_COUNT):
		_route_beats_crossed[beat_i] = true
	_enter_step("route_choice")
	_select_character("peris")
	if _camera != null:
		_set_lower_route_camera_bounds()
		_camera.call("_update_immediate")
	_arm_wreckage_gate()

func _resolve_peris_overlay_route_read() -> void:
	if bool(_route_reads_resolved.get("peris", false)):
		return
	_route_reads_resolved["peris"] = true
	_learn_iron_route_risk()
	# F2 is deliberately available while Aster's initial read is still speaking.
	# Do not pile two reactive lines on top of that queue; let the current exchange
	# finish, then play the response as its own short beat.
	if _dialogue.is_active():
		_dialogue.dialogue_finished.connect(_play_peris_route_dialogue, CONNECT_ONE_SHOT)
	else:
		_play_peris_route_dialogue()
	_tutorial_prompt.show_prompt(
		"Peris marks the iron footprints. Move previews now follow the safe outer edge to the rejoin point."
	)
	_scheduler.schedule_after(0.5, _start_route_choice, "route_choice")

func _play_peris_route_dialogue() -> void:
	DialogueData.say_to(_dialogue, "elevator.peris.community")
	DialogueData.say_to(_dialogue, "elevator.aster.long_way")

func _on_route_read_resolved(read_id: String) -> void:
	if not _route_reads_resolved.has(read_id) or bool(_route_reads_resolved[read_id]):
		return
	if read_id == "peris":
		_set_elevator_overlay_state("peris", true)
		return
	_route_reads_resolved["aster"] = true
	if read_id == "aster":
		DialogueData.say_to(_dialogue, "elevator.aster.short_way")
	if _route_reads_resolved.values().count(true) >= ROUTE_REQUIRED_READS:
		_tutorial_prompt.show_prompt("Both overlays read. Commit to the green Flure lane or the iron field.")
		_scheduler.schedule_after(0.5, _start_route_choice, "route_choice")

func _start_route_fork_dialogue() -> void:
	# Compatibility entry for focused tools. The authored lines now accompany
	# the two character-specific spatial reads instead of one passive block.
	_start_route_read_circuit()

# --- Route Choice ---

func _start_route_choice() -> void:
	if _route_reads_resolved.values().count(true) < ROUTE_REQUIRED_READS:
		_start_route_read_circuit()
		return
	_enter_step("route_choice")
	_player.set_move_enabled(true)
	for station in _route_flure_interactables:
		if is_instance_valid(station):
			station.set_interaction_enabled(true)
	_tutorial_prompt.show_prompt("Choose a path: green Flure stations draw the packs; the iron lane trades distance for exposure.")

func _wreckage_interaction_anchor() -> Vector3:
	if is_instance_valid(_wreckage_gate):
		var marker := _wreckage_gate.get_node_or_null("Markers/InteractionAnchor") as Marker3D
		if marker != null:
			return marker.global_position
	return WRECKAGE_GATE_POS + Vector3(-2.3, 0.0, 0.0)

func _wreckage_member_ready(character_id: String) -> bool:
	if _game_state == null or not _game_state.characters.has(character_id) \
			or _game_state.is_downed(character_id):
		return false
	var pos := _game_state.get_position(character_id)
	var anchor := _wreckage_interaction_anchor()
	return Vector2(pos.x - anchor.x, pos.z - anchor.z).length() <= WRECKAGE_ASSIST_RADIUS

func _wreckage_party_ready() -> bool:
	return _wreckage_member_ready("aster") and _wreckage_member_ready("peris")

func _arm_wreckage_gate() -> void:
	if _wreckage_armed or _wreckage_cleared or not is_instance_valid(_wreckage_interactable):
		return
	_wreckage_armed = true
	_wreckage_interactable.set_interaction_enabled(true)
	_wreckage_interactable.call_deferred("show_tutorial_label")
	_tutorial_prompt.show_prompt(
		"Wreckage blocks Endo's hall. Rally Aster and Peris onto both brace marks, then clear it."
	)

func _on_wreckage_interacted() -> void:
	if not _wreckage_armed or _wreckage_cleared or _wreckage_failure_active:
		return
	var interactor := _active_character
	if is_instance_valid(_wreckage_interactable):
		var recorded := str(_wreckage_interactable.get("active_character"))
		if recorded != "":
			interactor = recorded
	if _wreckage_party_ready():
		_clear_wreckage_together()
	else:
		_fail_wreckage_solo(interactor)

func _wreckage_animation(animation_name: String) -> void:
	if not is_instance_valid(_wreckage_gate):
		return
	var animation := _wreckage_gate.get_node_or_null("GateAnimation") as AnimationPlayer
	if animation != null and animation.has_animation(animation_name):
		animation.play(animation_name)

func _clear_wreckage_together() -> void:
	_wreckage_cleared = true
	_wreckage_failure_active = false
	if is_instance_valid(_wreckage_interactable):
		_wreckage_interactable.set_interaction_enabled(false)
	_wreckage_animation("clear_together")
	var blocker := _wreckage_gate.get_node_or_null("RubbleBlocker/BlockerShape") as CollisionShape3D \
		if is_instance_valid(_wreckage_gate) else null
	if blocker != null:
		blocker.set_deferred("disabled", true)
	if _grid != null:
		_grid.allow_world_region_on_level(
			Vector2(WRECKAGE_GATE_POS.x - 0.75, -6.0),
			Vector2(WRECKAGE_GATE_POS.x + 0.75, 6.0),
			LEVEL_LOWER
		)
	_tutorial_prompt.show_prompt("Both braces take the load. The passage to Endo is clear.")
	_show_marker(WRECKAGE_GATE_POS + Vector3(0.0, 2.4, 0.0), "TWO BRACES  /  CLEAR")
	_player.set_move_enabled(false)
	_scheduler.schedule_after(WRECKAGE_CLEAR_SECONDS, _finish_wreckage_clear, "wreckage_clear")

func _finish_wreckage_clear() -> void:
	if _current_step != "route_choice" or not _wreckage_cleared:
		return
	_tutorial_prompt.hide_prompt()
	_start_junction_arrive()

func _wake_wreckage_listeners() -> void:
	var remaining: Array[Dictionary] = []
	for setup in _below_dormant_enemy_setups:
		var enemy = setup.get("enemy")
		if is_instance_valid(enemy) and _wreckage_listeners.has(enemy as Enemy):
			_activate_below_enemy_setup(setup)
		else:
			remaining.append(setup)
	_below_dormant_enemy_setups = remaining

func _fail_wreckage_solo(interactor: String) -> void:
	if not (interactor in ["aster", "peris"]) or not _game_state.characters.has(interactor) \
			or _game_state.is_downed(interactor):
		return
	_wreckage_solo_attempted = true
	_wreckage_failure_active = true
	_wreckage_alert_target = interactor
	if is_instance_valid(_wreckage_interactable):
		_wreckage_interactable.set_interaction_enabled(false)
	_game_state.command_stop(interactor)
	_wreckage_animation("solo_failure")
	_camera.shake(0.14, 14.0)
	_show_marker(WRECKAGE_GATE_POS + Vector3(-1.0, 2.5, 0.0), "RUBBLE  ->  NOISE  ->  FAUNA")
	_hud.show_message(
		"Loose rubble fell. The side-niche fauna heard %s." % interactor.capitalize(),
		2.8
	)
	_wake_wreckage_listeners()
	for enemy in _wreckage_listeners:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		_game_state.set_character_distracted(enemy.char_id, false)
		enemy.engage_target(interactor)
	_scheduler.schedule_after(1.05, _rearm_wreckage_after_solo_failure, "wreckage_rearm")

func _rearm_wreckage_after_solo_failure() -> void:
	_wreckage_failure_active = false
	if _wreckage_cleared or _current_step != "route_choice" \
			or not is_instance_valid(_wreckage_interactable):
		return
	_wreckage_interactable.set_interaction_enabled(true)
	_wreckage_interactable.call_deferred("show_tutorial_label")
	_tutorial_prompt.show_prompt(
		"The noise brought the fauna in. Regroup both conscious characters at the brace marks."
	)

# --- Junction / Shelter ---

func _junction_survey_ready() -> bool:
	return _junction_inspections.size() >= JUNCTION_REQUIRED_INSPECTIONS \
		and bool(_junction_inspected_by.get("aster", false)) \
		and bool(_junction_inspected_by.get("peris", false))

func _update_junction_survey_prompt() -> void:
	if _junction_preparation != "":
		if _junction_fieldwork_complete():
			_tutorial_prompt.show_prompt("The annex is secured. Return to the shelter and tend the dormant plant.")
		elif _junction_field_protocol != "":
			var protocol: Dictionary = JUNCTION_FIELD_PROTOCOLS.get(_junction_field_protocol, {})
			var evidence: Dictionary = _junction_field_evidence.get(_junction_field_protocol, {})
			_tutorial_prompt.show_prompt("%s: %d/%d specialist reads, then choose and execute a plan." % [
				str(protocol.get("label", _junction_field_protocol)), evidence.size(),
				(protocol.get("evidence", []) as Array).size(),
			])
		return
	if _junction_survey_ready():
		_unlock_junction_preparation()
		return
	var count := mini(_junction_inspections.size(), JUNCTION_REQUIRED_INSPECTIONS)
	var missing_perspective := ""
	if not bool(_junction_inspected_by.get("aster", false)):
		missing_perspective = " Select Aster's portrait (or cycle) for his read."
	elif not bool(_junction_inspected_by.get("peris", false)):
		missing_perspective = " Select Peris's portrait (or cycle) for her read."
	_tutorial_prompt.show_prompt(
		"Survey Endo's shelter: %d/%d distinct stations.%s" % [
			count, JUNCTION_REQUIRED_INSPECTIONS, missing_perspective,
		]
	)

func _on_junction_inspection(label: String, interact: Node) -> void:
	if _current_step != "junction_arrive":
		return
	var inspector := _active_character
	if interact != null and "active_character" in interact and str(interact.get("active_character")) != "":
		inspector = str(interact.get("active_character"))
	if not (inspector in ["aster", "peris"]):
		return
	if not _junction_inspections.has(label):
		_junction_inspections[label] = inspector
	_junction_inspected_by[inspector] = true
	_update_junction_survey_prompt()

func _unlock_junction_preparation() -> void:
	for prep in _junction_prep_interactables.values():
		if is_instance_valid(prep):
			prep.set_interaction_enabled(true)
			prep.call_deferred("show_tutorial_label")
	_tutorial_prompt.show_prompt("Choose one preparation: RECOVER health, or SCOUT longer Flure windows.")

func _choose_junction_preparation(choice: String) -> void:
	if _current_step != "junction_arrive" or _junction_preparation != "" or not _junction_survey_ready():
		return
	_junction_preparation = choice
	if choice == "recover":
		for id in ["aster", "peris"]:
			var hp := _game_state.get_stat(id, "hp")
			_game_state.adjust_stat(id, "hp", minf(25.0, PARTY_MAX_HP - hp))
	else:
		_gauntlet_safe_window_bonus = 6.0
	for prep in _junction_prep_interactables.values():
		if is_instance_valid(prep):
			prep.set_interaction_enabled(false)
	_start_junction_field_protocol(JUNCTION_FIELD_PROTOCOL_ORDER[0])
	_update_junction_survey_prompt()

func _junction_fieldwork_complete() -> bool:
	return _junction_field_protocols_completed.size() >= JUNCTION_FIELD_PROTOCOL_ORDER.size()

func _start_junction_field_protocol(protocol_id: String) -> void:
	if not JUNCTION_FIELD_PROTOCOLS.has(protocol_id):
		return
	_junction_field_protocol = protocol_id
	if not _junction_field_evidence.has(protocol_id):
		_junction_field_evidence[protocol_id] = {}
	for site_id_variant in JUNCTION_FIELD_SITES.keys():
		var site_id := str(site_id_variant)
		var spec: Dictionary = JUNCTION_FIELD_SITES[site_id]
		var enabled := str(spec.get("protocol", "")) == protocol_id \
			and str(spec.get("kind", "")) == "evidence" \
			and not bool((_junction_field_evidence.get(protocol_id, {}) as Dictionary).get(site_id, false))
		_set_junction_field_site_enabled(site_id, enabled)
	_update_junction_survey_prompt()

func _set_junction_field_site_enabled(site_id: String, enabled: bool) -> void:
	var interact: Node = _junction_field_interactables.get(site_id)
	if not is_instance_valid(interact):
		return
	interact.set_interaction_enabled(enabled)
	if enabled:
		interact.call_deferred("show_tutorial_label")

func _on_junction_field_site(site_id: String) -> void:
	if _current_step != "junction_arrive" or not JUNCTION_FIELD_SITES.has(site_id):
		return
	var spec: Dictionary = JUNCTION_FIELD_SITES[site_id]
	var protocol_id := str(spec.get("protocol", ""))
	if protocol_id != _junction_field_protocol or not JUNCTION_FIELD_PROTOCOLS.has(protocol_id):
		return
	var kind := str(spec.get("kind", ""))
	var protocol: Dictionary = JUNCTION_FIELD_PROTOCOLS[protocol_id]
	match kind:
		"evidence":
			var evidence: Dictionary = _junction_field_evidence.get(protocol_id, {})
			if bool(evidence.get(site_id, false)):
				return
			evidence[site_id] = true
			_junction_field_evidence[protocol_id] = evidence
			_junction_field_findings.append(site_id)
			_set_junction_field_site_enabled(site_id, false)
			if evidence.size() >= (protocol.get("evidence", []) as Array).size():
				for choice_variant in protocol.get("choices", []):
					_set_junction_field_site_enabled(str(choice_variant), true)
		"choice":
			var evidence: Dictionary = _junction_field_evidence.get(protocol_id, {})
			if evidence.size() < (protocol.get("evidence", []) as Array).size():
				return
			_junction_field_choices[protocol_id] = site_id
			_junction_field_findings.append(site_id)
			for choice_variant in protocol.get("choices", []):
				_set_junction_field_site_enabled(str(choice_variant), false)
			var resolution_id := str((protocol.get("resolution_sites", {}) as Dictionary).get(site_id, ""))
			_set_junction_field_site_enabled(resolution_id, true)
		"resolution":
			var choice_id := str(_junction_field_choices.get(protocol_id, ""))
			var expected := str((protocol.get("resolution_sites", {}) as Dictionary).get(choice_id, ""))
			if expected != site_id:
				return
			_set_junction_field_site_enabled(site_id, false)
			_junction_field_findings.append(site_id)
			_junction_field_protocols_completed[protocol_id] = true
			var next_id := str(protocol.get("next", ""))
			if next_id == "":
				_junction_field_protocol = "complete"
				_unlock_junction_plant()
			else:
				_start_junction_field_protocol(next_id)
	_update_junction_survey_prompt()

func _unlock_junction_plant() -> void:
	if not _junction_fieldwork_complete() or not is_instance_valid(_junction_plant_interactable):
		return
	_junction_plant_interactable.set_interaction_enabled(true)
	_junction_plant_interactable.call_deferred("show_tutorial_label")

func _start_junction_arrive() -> void:
	_enter_step("junction_arrive")
	_set_junction_camera_bounds()
	_clear_markers()
	_load_chunk("junction")
	_unload_chunk("below")
	_enemies.clear()
	_player.set_move_enabled(true)
	_update_junction_survey_prompt()
	# The plant remains a visible destination, but the party earns it by reading
	# three different shelter stations with both character perspectives and then
	# choosing one preparation for the next stretch.

func _start_endo_enters() -> void:
	_enter_step("endo_enters")
	# Endo arrives from a side entrance
	_endo.visible = true
	_endo.position = Vector3(JUNCTION_POS.x + SHELTER_SIZE.x / 2.0 + 1.0, BELOW_Y + 0.5, 0)
	_register_gs_character("endo", _endo, 2.5)
	# Endo walks into the junction
	var junction_center := Vector3(JUNCTION_POS.x, BELOW_Y + 0.5, 0)
	_game_state.command_move_to_pos("endo", junction_center)
	_show_marker(Vector3(JUNCTION_POS.x, BELOW_Y + 2.5, 0), "SHELTER")
	_player.set_move_enabled(false)
	_dialogue_chain([
		"junction.endo.beckon",
		"junction.peris.who",
		"junction.aster.endo_read",
	], func(): _scheduler.schedule_after(1.0, _start_endo_shelter, "shelter"))

func _start_endo_shelter() -> void:
	_enter_step("endo_shelter")
	_player.set_move_enabled(false)
	# Endo walks to the drink container
	var container_pos := Vector3(JUNCTION_POS.x + 1.5, BELOW_Y + 0.5, -1.0)
	_game_state.command_move_to_pos("endo", container_pos)
	_game_state.character_arrived.connect(_on_endo_at_container, CONNECT_ONE_SHOT)

func _on_endo_at_container(id: String) -> void:
	if id != "endo":
		# Wrong character arrived; re-listen.
		_game_state.character_arrived.connect(_on_endo_at_container, CONNECT_ONE_SHOT)
		return
	# Dwell indicator while Endo picks up drink
	_show_marker(_endo.global_position + Vector3(0, 1.5, 0), "...")
	_scheduler.schedule_after(1.5, _endo_pickup_drink, "endo_pickup")

func _endo_pickup_drink() -> void:
	_clear_markers()
	# Reparent drink to Endo so it moves with him
	if _drink_mesh and is_instance_valid(_drink_mesh):
		var global_pos := _drink_mesh.global_position
		_drink_mesh.get_parent().remove_child(_drink_mesh)
		_endo.add_child(_drink_mesh)
		_drink_mesh.position = Vector3(0, 1.2, 0.3)
	# WATER marker on the drink
	_show_marker(Vector3(JUNCTION_POS.x + 1.5, BELOW_Y + 1.5, -1.0), "WATER")
	# Endo walks back to the party
	var party_pos := Vector3(JUNCTION_POS.x - SHELTER_SIZE.x / 2.0 + 1.0, BELOW_Y + 0.5, 0)
	_game_state.command_move_to_pos("endo", party_pos)
	_game_state.character_arrived.connect(_on_endo_delivered, CONNECT_ONE_SHOT)

func _on_endo_delivered(id: String) -> void:
	if id != "endo":
		_game_state.character_arrived.connect(_on_endo_delivered, CONNECT_ONE_SHOT)
		return
	_clear_markers()
	_dialogue_chain([
		"junction.endo.drink",
		"junction.peris.stomach",
		"junction.endo.rest",
	], func():
		_scheduler.schedule_after(2.0, _start_night_watch, "night_watch")
	)

func _spawn_enemy(id: String, pos: Vector3, parent: Node3D, activate_now := true) -> Enemy:
	var enemy := Enemy.new()
	enemy.name = id
	enemy.game_state = _game_state
	enemy.char_id = id
	enemy.detection_range = 6.0
	enemy.set_detection_targets(["aster", "peris"])
	enemy.position = pos
	if not activate_now:
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	parent.add_child(enemy)
	enemy.hit_target.connect(_on_enemy_hit)
	if activate_now:
		_register_gs_character(id, enemy, enemy.move_speed, {
			"detection_range": enemy.detection_range,
			"detection_targets": enemy.get_detection_targets(),
		})
		enemy.activate()
	_enemies.append(enemy)
	_enemy_count += 1
	return enemy

func _queue_below_enemy_setup(
		enemy: Enemy, mode: String, data: Dictionary, wake_radius: float) -> void:
	_below_dormant_enemy_setups.append({
		"enemy": enemy,
		"mode": mode,
		"data": data,
		"wake_radius": wake_radius,
	})

## Streaming may construct and reveal the lower ecology while the party is still on the bridge, but it does not
## register any of those bodies with GameState. Landing enables proximity activation; only the cohort near a
## lower-deck party member joins the simulation. This keeps later packs from planning and detecting through an
## encounter the player has not reached yet.
func _activate_below_fauna() -> void:
	if _below_fauna_active:
		return
	_below_fauna_active = true
	_below_activation_cells.clear()
	_update_below_fauna_activation(true)

func _update_below_fauna_activation(force := false) -> void:
	if not _below_fauna_active or _below_dormant_enemy_setups.is_empty() \
			or _game_state == null or _game_state.grid == null:
		return
	var lower_party: Array[String] = []
	var cells_changed := force
	for character_id in ["aster", "peris"]:
		if not _game_state.characters.has(character_id) \
				or _game_state.get_character_level(character_id) != LEVEL_LOWER \
				or _game_state.get_stat(character_id, "hp") <= 0.0:
			continue
		lower_party.append(character_id)
		var cell := _game_state.grid.world_to_grid(_game_state.get_position(character_id))
		if _below_activation_cells.get(character_id, Vector2i(-99999, -99999)) != cell:
			cells_changed = true
			_below_activation_cells[character_id] = cell
	if lower_party.is_empty() or not cells_changed:
		return
	var remaining: Array[Dictionary] = []
	var waking: Array[Dictionary] = []
	for setup in _below_dormant_enemy_setups:
		# A test/focused chunk transition can free the below chunk between
		# proximity samples. Keep the Variant untyped until validity is known;
		# assigning a freed Object to a typed Enemy raises before the guard runs.
		var enemy = setup.get("enemy")
		if not is_instance_valid(enemy):
			continue
		var wake_radius := float(setup.get("wake_radius", 12.0))
		var wake := false
		for character_id in lower_party:
			var party_pos := _game_state.get_position(character_id)
			if Vector2(party_pos.x - enemy.position.x, party_pos.z - enemy.position.z).length() <= wake_radius:
				wake = true
				break
		if wake:
			waking.append(setup)
		else:
			remaining.append(setup)
	if waking.is_empty():
		return
	_game_state.begin_detection_update_batch()
	for setup in waking:
		_activate_below_enemy_setup(setup)
	_game_state.end_detection_update_batch()
	_below_dormant_enemy_setups = remaining

func _activate_below_enemy_setup(setup: Dictionary) -> void:
	var enemy: Enemy = setup.get("enemy")
	if not is_instance_valid(enemy):
		return
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	_register_gs_character(enemy.char_id, enemy, enemy.move_speed, {
		"detection_range": enemy.detection_range,
		"detection_targets": enemy.get_detection_targets(),
	})
	enemy.activate()
	var data: Dictionary = setup.get("data", {})
	match str(setup.get("mode", "")):
		"roam":
			_arm_below_fauna(enemy, data.get("anchor", enemy.position), float(data.get("radius", 2.0)))
		"patrol":
			var waypoints: Array[Vector3] = []
			waypoints.assign(data.get("waypoints", []))
			enemy.set_patrol(waypoints)
			# Route-lane patrols are already occupied by the nearby Flures. They retain a tight
			# personal-space watch, but do not acquire a party merely skirting the huddle.
			_game_state.set_character_distracted(enemy.char_id, true)

## The below-bridge ecology huddles around flures and is DISTRACTED by them: each fauna targets the
## party but its detection range is shrunk (DETECTION_DISTRACTED_FACTOR), so it only gives chase when
## Aster/Peris come really close — cutting through the huddle. Keeping distance (or the hazard lane)
## slips past. Roaming (no A*) keeps it cheap; the distraction flag is derived (not logged, replay-safe).
func _arm_below_fauna(enemy: Enemy, anchor: Vector3, radius: float) -> void:
	enemy.set_detection_targets(["aster", "peris"])
	enemy.set_roam(anchor, radius)
	if _game_state != null:
		_game_state.set_character_distracted(enemy.char_id, true)

## A flure: a glowing lure the ecology clusters around (the distraction source — purely cosmetic here;
## the distraction itself is the shrunk detection range set in _arm_below_fauna).
func _build_flure(parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 0.8, 0)
	light.light_color = Color(0.6, 0.9, 0.2)
	light.light_energy = 0.9
	light.omni_range = 3.5
	parent.add_child(light)
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.7, 0.15, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.85, 0.2)
	mat.emission_energy_multiplier = 1.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	mesh.position = pos + Vector3(0, 0.5, 0)
	parent.add_child(mesh)
	return mesh

## Thin, collision-free course paint. The green plates establish a legible safe
## datum beside the orange iron fields without changing either route's physics.
func _add_route_field_plate(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	plate.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color.darkened(0.18)
	mat.emission_energy_multiplier = 0.7
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plate.material_override = mat
	plate.position = pos
	parent.add_child(plate)
	return plate

func _add_course_station_visual(parent: Node3D, name_prefix: String, pos: Vector3, color: Color, label_text: String) -> MeshInstance3D:
	var pedestal := MeshInstance3D.new()
	pedestal.name = name_prefix + "Visual"
	var pedestal_box := BoxMesh.new()
	pedestal_box.size = Vector3(0.85, 0.9, 0.55)
	pedestal.mesh = pedestal_box
	var pedestal_mat := StandardMaterial3D.new()
	pedestal_mat.albedo_color = color.darkened(0.55)
	pedestal_mat.metallic = 0.28
	pedestal_mat.roughness = 0.62
	pedestal_mat.emission_enabled = true
	pedestal_mat.emission = color
	pedestal_mat.emission_energy_multiplier = 0.42
	pedestal.material_override = pedestal_mat
	pedestal.position = pos + Vector3(0, 0.45, 0)
	parent.add_child(pedestal)
	var label := Label3D.new()
	label.name = name_prefix + "Label"
	label.text = label_text
	label.font_size = 48
	label.pixel_size = 0.0035
	label.modulate = color.lightened(0.18)
	label.outline_modulate = Color(0.01, 0.01, 0.015, 0.95)
	label.outline_size = 10
	label.position = pos + Vector3(0, 1.25, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return pedestal

## `_create_interactable` registers its generic spec before sequence code can
## set a required character. Re-register that one field through GameState so
## both the data authority and the view enforce the same character gate.
func _require_interactable_character(interact: Node, character_id: String) -> void:
	interact.set("required_character", character_id)
	if _game_state == null or not ("data_id" in interact):
		return
	var data_id := str(interact.get("data_id"))
	if data_id == "" or not _game_state.has_interactable(data_id):
		return
	var spec := _game_state.get_interactable(data_id)
	spec["required_character"] = character_id
	_game_state.register_interactable(spec)

func _build_route_flure_station(parent: Node3D, index: int, pos: Vector3) -> void:
	var visual := _build_flure(parent, pos)
	visual.name = "RouteFlureVisual%d" % index
	_route_flure_meshes.append(visual)
	var interact := _create_interactable(
		parent, pos, "RouteFlure%d" % index, 1.8, 0.8, "Prime Flure", true,
		Interactable.InteractableType.INSPECTION
	)
	interact.description = "Route Flure %d" % (index + 1)
	_require_interactable_character(interact, "peris")
	interact.set_interaction_enabled(false)
	interact.interacted.connect(_on_route_flure_activated.bind(index))
	_route_flure_interactables.append(interact)

func _on_route_flure_activated(index: int) -> void:
	if index < 0 or index >= _route_flures_activated.size() or _route_flures_activated[index]:
		return
	_route_flures_activated[index] = true
	var lure_mesh: MeshInstance3D = _route_flure_meshes[index] if index < _route_flure_meshes.size() else null
	if is_instance_valid(lure_mesh):
		var mat := lure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 3.0
	var groups: Array = _route_flure_enemy_groups.get(index, [])
	for enemy in groups:
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy.set_detection_targets([])
			enemy._current_target_id = ""
			enemy._change_state("idle")
			if enemy.game_state != null and enemy.game_state.characters.has(enemy.char_id) and is_instance_valid(lure_mesh):
				enemy.game_state.command_move_to_pos(enemy.char_id, lure_mesh.global_position)
	if is_instance_valid(lure_mesh):
		_show_marker(lure_mesh.global_position + Vector3(0, 1.6, 0), "FLURE %d" % (index + 1))
	_scheduler.schedule_after(ROUTE_FLURE_DURATION, _expire_route_flure.bind(index), "route_flure_%d" % index)

func _expire_route_flure(index: int) -> void:
	if index < 0 or index >= _route_flures_activated.size() or not _route_flures_activated[index]:
		return
	_route_flures_activated[index] = false
	var lure_mesh: MeshInstance3D = _route_flure_meshes[index] if index < _route_flure_meshes.size() else null
	if is_instance_valid(lure_mesh):
		var mat := lure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 1.6
	for enemy in _route_flure_enemy_groups.get(index, []):
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy.set_detection_targets(["aster", "peris"])
			enemy._change_state("idle")

## GameState is the single source of truth for party HP. Every hp change (enemy strikes apply it via
## _resolve_strike's adjust_stat; iron patches via adjust_stat) fans out here to drive the HUD, the
## downed portrait, and game-over — so no damage source maintains a parallel counter.
func _on_party_stat_changed(id: String, stat: String, value: float) -> void:
	if stat != "hp" or not (id == "aster" or id == "peris"):
		return
	if _hud != null:
		_hud.set_portrait_stat(id, "hp", value)
		if value <= 0.0:
			_hud.set_portrait_status(id, "downed")
	if not _game_over and _game_state != null \
			and _game_state.get_stat("aster", "hp") <= 0.0 and _game_state.get_stat("peris", "hp") <= 0.0:
		if _current_step == "gauntlet":
			_scheduler.schedule_after(0.1, _reset_gauntlet_to_refuge, "gauntlet_party_reset")
			return
		_start_game_over()

## The strike already applied data-layer damage; present one consistent source-labelled response in the world/HUD.
func _on_enemy_hit(target_id: String, damage: float) -> void:
	if _game_over:
		return
	_show_party_damage_feedback(target_id, damage, "IMPACT", Color(1.0, 0.28, 0.18))
	if _current_step == "gauntlet" and not _gauntlet_resetting:
		_scheduler.schedule_after(0.4, _reset_gauntlet_to_refuge, "gauntlet_hit_reset")

## Iron is a cadenced simulation hazard, not a render-frame drain. One authoritative tick replaces dozens of
## fractional stat writes per second, keeping replay/event/HUD work bounded while every hit names its source.
func _arm_iron_hazard_tick() -> void:
	if _iron_hazard_tick_armed or _scheduler == null or _iron_patches.is_empty():
		return
	_iron_hazard_tick_armed = true
	_scheduler.schedule_after(IRON_DAMAGE_INTERVAL, _iron_hazard_tick, IRON_HAZARD_TAG)

func _iron_hazard_tick() -> void:
	_iron_hazard_tick_armed = false
	if _game_over or _scheduler == null or _iron_patches.is_empty():
		return
	for cid in ["aster", "peris"]:
		if not _game_state.characters.has(cid) or _game_state.get_stat(cid, "hp") <= 0.0:
			continue
		if _iron_patch_contains(_game_state.get_position(cid)):
			_game_state.adjust_stat(cid, "hp", -IRON_DAMAGE_PER_TICK)
			_show_party_damage_feedback(cid, IRON_DAMAGE_PER_TICK, "IRON", Color(1.0, 0.32, 0.08))
			if not bool(_iron_contact_warning_shown.get(cid, false)):
				_iron_contact_warning_shown[cid] = true
				_hud.show_message(
					"%s is in an IRON FIELD — move to Peris's amber outer edge." % cid.capitalize(),
					2.2
				)
	_arm_iron_hazard_tick()

func _iron_patch_contains(world_pos: Vector3) -> bool:
	# The hidden prewarm may overlap the bridge in XZ; only the lower deck can contact these fields.
	if absf(world_pos.y - BELOW_Y) > 1.0:
		return false
	for patch in _iron_patches:
		var ppos: Vector3 = patch.pos
		var psz: Vector3 = patch.size
		if absf(world_pos.x - ppos.x) < psz.x * 0.5 \
				and absf(world_pos.z - ppos.z) < psz.z * 0.5:
			return true
	return false

func _show_party_damage_feedback(
		character_id: String, amount: float, source: String, flash_color: Color) -> void:
	var feedback_key := "%s:%s" % [character_id, source]
	_damage_feedback_counts[feedback_key] = int(_damage_feedback_counts.get(feedback_key, 0)) + 1
	var target_node: Node3D = _aster_node if character_id == "aster" else _peris_node
	if target_node == null or not is_instance_valid(target_node):
		return
	if _hud != null and _hud.has_method("pulse_portrait_damage"):
		_hud.pulse_portrait_damage(character_id)
	var hit_mesh := target_node.get_node_or_null("Mesh") as MeshInstance3D
	if hit_mesh != null and hit_mesh.material_override is StandardMaterial3D:
		var mat := hit_mesh.material_override as StandardMaterial3D
		var base_color: Color = target_node.color if "color" in target_node else mat.albedo_color
		var material_tween: Tween = _damage_feedback_tweens.get(character_id + "_material")
		if material_tween != null and material_tween.is_valid():
			material_tween.kill()
		mat.albedo_color = flash_color
		material_tween = create_tween()
		material_tween.tween_property(mat, "albedo_color", base_color, 0.24)
		_damage_feedback_tweens[character_id + "_material"] = material_tween
	var label: Label3D = _damage_feedback_labels.get(character_id)
	if label == null or not is_instance_valid(label):
		label = Label3D.new()
		label.name = "DamageFeedback" + character_id.capitalize()
		label.font_size = 42
		label.pixel_size = 0.007
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 8
		label.outline_modulate = Color(0.04, 0.01, 0.0, 0.96)
		label.top_level = true
		add_child(label)
		_damage_feedback_labels[character_id] = label
	var label_tween: Tween = _damage_feedback_tweens.get(character_id + "_label")
	if label_tween != null and label_tween.is_valid():
		label_tween.kill()
	# Keep the hit read above the character name and Peris's field annotation; those sit around 1.3-1.5m.
	var start := target_node.global_position + Vector3(0.0, 2.25, 0.0)
	var hp_left := _game_state.get_stat(character_id, "hp") if _game_state != null else 0.0
	label.text = "%s  -%d HP  /  %d LEFT" % [source, int(round(amount)), int(ceil(hp_left))]
	label.global_position = start
	label.modulate = Color(flash_color, 1.0)
	label.visible = true
	label_tween = create_tween().set_parallel(true)
	label_tween.tween_property(label, "global_position", start + Vector3(0.0, 0.55, 0.0), 0.65)
	label_tween.tween_property(label, "modulate", Color(flash_color, 0.0), 0.65).set_delay(0.18)
	label_tween.chain().tween_callback(func():
		if is_instance_valid(label):
			label.visible = false
	)
	_damage_feedback_tweens[character_id + "_label"] = label_tween

func _show_marker(pos: Vector3, text: String) -> void:
	var lbl := Label3D.new()
	lbl.name = "Marker_" + text
	lbl.text = text
	lbl.font_size = 28
	lbl.pixel_size = 0.008
	lbl.modulate = Color(0.4, 0.6, 0.8, 0.7)
	lbl.outline_modulate = Color(0, 0, 0, 0.5)
	lbl.outline_size = 3
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = pos
	find_child("Environment", false, false).add_child(lbl)

func _clear_markers() -> void:
	var env: Node = find_child("Environment", false, false)
	for child in env.get_children():
		if child is Label3D and child.name.begins_with("Marker_"):
			child.queue_free()

func _start_night_watch() -> void:
	_enter_step("night_watch")
	# Darken the world for nightfall.
	var env_node: Node = find_child("Environment", false, false)
	var we: WorldEnvironment = env_node.find_child("*", false, false) as WorldEnvironment if env_node else null
	for child in env_node.get_children():
		if child is WorldEnvironment:
			we = child
			break
	if we and we.environment:
		we.environment.ambient_light_energy = 0.1

	# Flicker the shelter interior light
	var shelter_light: OmniLight3D
	var junction_chunk: Node3D = _chunks.get("junction")
	if junction_chunk:
		shelter_light = junction_chunk.find_child("ShelterLight", false, false)

	# Spawn monster eye pairs outside both windows
	_monster_eyes.clear()
	var ground_y := BELOW_Y
	var sx := JUNCTION_POS.x
	var sd := SHELTER_SIZE.z
	for side_idx in range(2):
		var side_sign: float = -1.0 if side_idx == 0 else 1.0
		var wz: float = side_sign * (sd / 2.0 + 0.5)
		for i in range(3):
			var pair_x: float = sx - 2.0 + i * 2.5
			for eye_idx in range(2):
				var eye := OmniLight3D.new()
				var eye_offset: float = -0.15 if eye_idx == 0 else 0.15
				eye.position = Vector3(pair_x + eye_offset, ground_y + 1.6, wz)
				eye.light_color = Color(0.95, 0.1, 0.05)
				eye.light_energy = 0.0
				eye.omni_range = 0.8
				find_child("Environment", false, false).add_child(eye)
				_monster_eyes.append(eye)

	# Fade eyes in over 2 seconds
	for eye in _monster_eyes:
		var tween := create_tween()
		tween.tween_property(eye, "light_energy", 0.5 + randf() * 0.3, 2.0 + randf() * 1.0)

	# Shelter light flickers
	if shelter_light:
		_scheduler.schedule_after(3.0, func():
			var flicker := create_tween()
			flicker.tween_property(shelter_light, "light_energy", 1.0, 0.1)
			flicker.tween_property(shelter_light, "light_energy", 2.5, 0.1)
			flicker.tween_property(shelter_light, "light_energy", 0.8, 0.1)
			flicker.tween_property(shelter_light, "light_energy", 2.5, 0.3)
		, "flicker")

	DialogueData.say_to(_dialogue, "junction.night.eyes")
	_scheduler.schedule_after(8.0, _start_dawn, "dawn")

func _start_dawn() -> void:
	_enter_step("dawn")
	# Eyes fade out
	for eye in _monster_eyes:
		if is_instance_valid(eye):
			var tween := create_tween()
			tween.tween_property(eye, "light_energy", 0.0, 2.0)
			tween.tween_callback(eye.queue_free)
	_monster_eyes.clear()
	# Restore ambient light
	var env_node: Node = find_child("Environment", false, false)
	for child in env_node.get_children():
		if child is WorldEnvironment:
			child.environment.ambient_light_energy = 0.5
			break
	DialogueData.say_to(_dialogue, "junction.dawn")
	_dialogue.dialogue_finished.connect(func():
		_scheduler.schedule_after(1.0, _start_morning, "morning")
	, CONNECT_ONE_SHOT)

# --- Morning / Endo Joins ---

func _start_morning() -> void:
	_enter_step("morning")
	_dialogue_chain([
		"junction.morning.trail",
		"junction.endo.stands",
		"junction.peris.coming",
		"junction.aster.ok",
	], func(): _scheduler.schedule_after(1.5, _start_gauntlet, "gauntlet"))

# --- Flure Gauntlet ---

func _start_gauntlet() -> void:
	_enter_step("gauntlet")
	_set_gauntlet_camera_bounds()
	_load_chunk("gauntlet")
	_unload_chunk("junction")
	_gauntlet_stage = 0
	_gauntlet_midpoint_reached = false
	_gauntlet_strategy = ""
	_gauntlet_resetting = false
	_gauntlet_flure_active = {0: false, 1: false}
	_flure_active = false
	_player.set_move_enabled(true)
	# The entrance is inside the first patrol's normal detection radius. Keep the pack inert and
	# the lure unclickable until the mandatory briefing finishes, then arm both together.
	for enemy in _gauntlet_enemies:
		if is_instance_valid(enemy):
			enemy.set_detection_targets([])
	# Walk party to gauntlet entrance
	var entrance := Vector3(GAUNTLET_POS.x - 8.0, BELOW_Y + 0.5, 0)
	_game_state.command_move_to_pos("aster", entrance)
	_game_state.command_move_to_pos("peris", entrance + Vector3(-1, 0, 1))
	_game_state.command_move_to_pos("endo", entrance + Vector3(-1, 0, -1))
	_store_gauntlet_checkpoint_hp()
	_dialogue_chain([
		"junction.aster.blocked",
		"junction.peris.flure",
	], _finish_gauntlet_intro)

func _finish_gauntlet_intro() -> void:
	if bool(_gauntlet_flure_active.get(0, false)):
		if _flure_interactable != null:
			_flure_interactable.set_interaction_enabled(false)
		return
	for enemy in _gauntlet_enemy_groups.get(0, []):
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy.set_detection_targets(["aster", "peris"])
	if _flure_interactable != null:
		_flure_interactable.set_interaction_enabled(true)
	if _gauntlet_flure_interactables.size() > 1:
		_gauntlet_flure_interactables[1].set_interaction_enabled(false)
	_tutorial_prompt.show_action_prompt(
		&"command",
		"activate Flure (Peris only)",
		0.0,
		"RMB"
	)

func _on_flure_activated() -> void:
	_on_gauntlet_flure_activated(0)

func _on_gauntlet_flure_activated(stage: int) -> void:
	if bool(_gauntlet_flure_active.get(stage, false)):
		return
	if stage == 1 and not _gauntlet_midpoint_reached:
		return
	_gauntlet_flure_active[stage] = true
	_gauntlet_active_stage = stage
	_flure_active = true
	_tutorial_prompt.hide_prompt()
	var lure_mesh: MeshInstance3D = _gauntlet_flure_meshes[stage] if stage < _gauntlet_flure_meshes.size() else null
	if lure_mesh:
		var mat := lure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 3.0
	var lure_pos := FLURE_POS if stage == 0 else GAUNTLET_FLURE_2_POS
	# Each station redirects only the pack that owns its half of the course.
	for enemy in _gauntlet_enemy_groups.get(stage, []):
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy.set_detection_targets([])
			enemy._current_target_id = ""
			enemy._change_state("idle")
			if enemy.game_state and enemy.game_state.characters.has(enemy.char_id):
				enemy.game_state.command_move_to_pos(enemy.char_id, lure_pos)
	_show_marker(lure_pos + Vector3(0, 1.5, 0), "LURE %d ACTIVE" % (stage + 1))
	_dialogue.default_hold_time = 2.0
	if stage == 0:
		DialogueData.say_to(_dialogue, "junction.flure.active")
	var active_duration := FLURE_DURATION + _gauntlet_safe_window_bonus
	_scheduler.schedule_after(active_duration, _on_flure_expired.bind(stage), "flure_expire_%d" % stage)

func _on_flure_expired(stage := -1) -> void:
	var resolved_stage: int = _gauntlet_active_stage if int(stage) < 0 else int(stage)
	if resolved_stage < 0 or not bool(_gauntlet_flure_active.get(resolved_stage, false)):
		return
	_gauntlet_flure_active[resolved_stage] = false
	_flure_active = bool(_gauntlet_flure_active.get(0, false)) or bool(_gauntlet_flure_active.get(1, false))
	_clear_markers()
	var lure_mesh: MeshInstance3D = _gauntlet_flure_meshes[resolved_stage] if resolved_stage < _gauntlet_flure_meshes.size() else null
	if lure_mesh:
		var mat := lure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 0.5
	# Restore only this stage's pack.
	for enemy in _gauntlet_enemy_groups.get(resolved_stage, []):
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy.set_detection_targets(["aster", "peris"])
			enemy._change_state("idle")

func _reach_gauntlet_midpoint() -> void:
	_gauntlet_midpoint_reached = true
	_gauntlet_stage = 1
	if _gauntlet_strategy == "":
		_gauntlet_strategy = "safe_relay" if bool(_gauntlet_flure_active.get(0, false)) else "fast_direct"
	_store_gauntlet_checkpoint_hp()
	for enemy in _gauntlet_enemy_groups.get(1, []):
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy.set_detection_targets(["aster", "peris"])
	if _gauntlet_flure_interactables.size() > 1:
		_gauntlet_flure_interactables[1].set_interaction_enabled(true)
	_show_marker(GAUNTLET_MIDPOINT + Vector3(0, 2.0, 0), "MIDPOINT REFUGE")
	_tutorial_prompt.show_action_prompt(&"command", "second Flure or fast exit", 0.0, "RMB")

func _store_gauntlet_checkpoint_hp() -> void:
	_gauntlet_checkpoint_hp.clear()
	for id in ["aster", "peris"]:
		_gauntlet_checkpoint_hp[id] = _game_state.get_stat(id, "hp")

func _reset_gauntlet_to_refuge() -> void:
	if _gauntlet_resetting or _current_step != "gauntlet":
		return
	_gauntlet_resetting = true
	_gauntlet_reset_count += 1
	var base := GAUNTLET_MIDPOINT if _gauntlet_midpoint_reached else Vector3(GAUNTLET_POS.x - 8.0, BELOW_Y, 0)
	var placements := {
		"aster": base + Vector3(-0.8, 0.5, -0.7),
		"peris": base + Vector3(-0.8, 0.5, 0.7),
	}
	for id in placements:
		_game_state.command_stop(id)
		var pos: Vector3 = placements[id]
		_game_state.characters[id]["position"] = pos
		_game_state.characters[id]["grid_cell"] = _grid.world_to_grid(pos)
		var node: Node3D = _aster_node if id == "aster" else _peris_node
		node.global_position = pos
		var target_hp := float(_gauntlet_checkpoint_hp.get(id, PARTY_MAX_HP))
		_game_state.adjust_stat(id, "hp", target_hp - _game_state.get_stat(id, "hp"))
	var reset_stage := 1 if _gauntlet_midpoint_reached else 0
	_gauntlet_flure_active[reset_stage] = false
	_flure_active = bool(_gauntlet_flure_active.get(0, false)) or bool(_gauntlet_flure_active.get(1, false))
	if reset_stage < _gauntlet_flure_interactables.size():
		var station: Node = _gauntlet_flure_interactables[reset_stage]
		station.call("reset")
		station.call("set_interaction_enabled", true)
	for enemy in _gauntlet_enemy_groups.get(reset_stage, []):
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy.set_detection_targets(["aster", "peris"])
			enemy._current_target_id = ""
			enemy._change_state("idle")
	_show_marker(base + Vector3(0, 2.0, 0), "REFUGE RESET")
	_scheduler.schedule_after(1.0, func(): _gauntlet_resetting = false, "gauntlet_reset_release")

## Evidence-backed first-clear budget. This is a pacing contract, not a timer:
## no entry can be earned by waiting, and dialogue is allowed to overlap movement.
## The active estimate covers route finding, character swaps, spatial reads,
## encounter execution, and recovery; presentation time covers the 59 existing
## authored lines and short collapse/night transitions.
func get_playtime_contract() -> Dictionary:
	var critical_route_meters := (BRIDGE_COLLAPSE_X - BRIDGE_START_X) \
		+ (ROUTES_CONVERGE.x - BRIDGE_COLLAPSE_X) \
		+ (JUNCTION_POS.x - ROUTES_CONVERGE.x) \
		+ (GAUNTLET_EXIT.x - JUNCTION_POS.x) + 156.0
	var meaningful_active_seconds := 516.0
	var total_play_seconds := 716.0
	return {
		"contract_id": "elevator_first_clear_8_to_12_v3",
		"required_first_clear_seconds": 480.0,
		"target_min_seconds": 480.0,
		"target_max_seconds": 720.0,
		"modeled_first_clear_seconds": total_play_seconds,
		"modeled_meaningful_active_seconds": meaningful_active_seconds,
		"meaningful_active_seconds": meaningful_active_seconds,
		"total_play_seconds": total_play_seconds,
		"modeled_presentation_seconds": 200.0,
		"modeled_navigation_seconds": 148.0,
		"modeled_decision_execution_seconds": 129.0,
		"modeled_hazard_adaptation_seconds": 95.0,
		"modeled_field_investigation_seconds": 96.0,
		"modeled_field_execution_seconds": 48.0,
		"meaningful_active_ratio": meaningful_active_seconds / total_play_seconds,
		"active_ratio": meaningful_active_seconds / total_play_seconds,
		"max_dead_gap_seconds": 4.8,
		"max_single_mode_seconds": 42.0,
		"category_seconds": {
			"navigation": 148.0,
			"investigation": 96.0,
			"planning": 129.0,
			"hazard_adaptation": 95.0,
			"field_execution": 48.0,
		},
		"critical_route_meters": critical_route_meters,
		"mandatory_dialogue_lines": 59,
		"mandatory_route_overlay_reads": ROUTE_REQUIRED_READS,
		"mandatory_route_beats": ROUTE_BEAT_COUNT,
		"mandatory_wreckage_assists": 2,
		"mandatory_junction_inspections": JUNCTION_REQUIRED_INSPECTIONS,
		"mandatory_character_perspectives": 2,
		"mandatory_field_protocols": JUNCTION_FIELD_PROTOCOL_ORDER.size(),
		"mandatory_field_evidence": 12,
		"mandatory_field_actions": 18,
		"fieldwork_seconds": 162.0,
		"field_route_meters": 156.0,
		"gauntlet_stages": 2,
		"decision_count": 7,
		"branch_count": 14,
		"hard_idle_lock_seconds": 0.0,
		"dialogue_overlap_allowed": true,
	}

func headless_get_anchor_positions() -> Dictionary:
	return {
		"bridge_collapse": Vector3(BRIDGE_COLLAPSE_X, 0.0, 0.0),
		"route_overlay_aster": ROUTE_READ_ASTER_POS,
		"route_overlay_peris": ROUTE_READ_PERIS_POS,
		"peris_safe_route_end": Vector3(ROUTES_CONVERGE.x, BELOW_Y, 4.0),
		"route_fork": FORK_POS,
		"route_flure_1": Vector3(FORK_POS.x + float(ROUTE_BEAT_OFFSETS[0]) - 5.0, BELOW_Y + 0.3, -5.7),
		"route_flure_2": Vector3(FORK_POS.x + float(ROUTE_BEAT_OFFSETS[1]) - 5.0, BELOW_Y + 0.3, -5.7),
		"route_flure_3": Vector3(FORK_POS.x + float(ROUTE_BEAT_OFFSETS[2]) - 5.0, BELOW_Y + 0.3, -5.7),
		"route_converge": ROUTES_CONVERGE,
		"wreckage_gate": WRECKAGE_GATE_POS,
		"junction": JUNCTION_POS,
		"junction_field_annex_end": Vector3(JUNCTION_POS.x + 60.0, BELOW_Y, 0.0),
		"gauntlet_entrance": Vector3(GAUNTLET_POS.x - 8.0, BELOW_Y, 0.0),
		"gauntlet_flure_1": FLURE_POS,
		"gauntlet_midpoint": GAUNTLET_MIDPOINT,
		"gauntlet_flure_2": GAUNTLET_FLURE_2_POS,
		"gauntlet_exit": GAUNTLET_EXIT,
	}

func headless_get_state() -> Dictionary:
	var state: Dictionary = super.headless_get_state()
	state.merge({
		"overlay_states": _elevator_overlay_states.duplicate(),
		"overlays_available": _elevator_overlays_available,
		"aster_route_overlay_visible": is_instance_valid(_aster_route_overlay_root) \
			and _aster_route_overlay_root.visible,
		"peris_route_overlay_visible": is_instance_valid(_peris_route_overlay_root) \
			and _peris_route_overlay_root.visible,
		"peris_route_final_position": _peris_route_overlay_endpoint.global_position \
			if is_instance_valid(_peris_route_overlay_endpoint) \
			else Vector3(ROUTES_CONVERGE.x, BELOW_Y + 0.12, 4.0),
		"route_reads_resolved": _route_reads_resolved.duplicate(),
		"route_read_count": _route_reads_resolved.values().count(true),
		"route_lane": _route_lane,
		"route_beats_crossed": _route_beats_crossed.duplicate(),
		"route_flures_activated": _route_flures_activated.duplicate(),
		"wreckage_armed": _wreckage_armed,
		"wreckage_party_ready": _wreckage_party_ready(),
		"wreckage_cleared": _wreckage_cleared,
		"wreckage_solo_attempted": _wreckage_solo_attempted,
		"wreckage_failure_active": _wreckage_failure_active,
		"wreckage_alert_target": _wreckage_alert_target,
		"junction_inspection_ids": _junction_inspections.keys(),
		"junction_inspection_count": _junction_inspections.size(),
		"junction_inspected_by": _junction_inspected_by.duplicate(),
		"junction_survey_ready": _junction_survey_ready(),
		"junction_preparation": _junction_preparation,
		"junction_field_protocol": _junction_field_protocol,
		"junction_field_evidence": _junction_field_evidence.duplicate(true),
		"junction_field_choices": _junction_field_choices.duplicate(),
		"junction_field_protocols_completed": _junction_field_protocols_completed.duplicate(),
		"junction_field_completed_count": _junction_field_protocols_completed.size(),
		"junction_fieldwork_complete": _junction_fieldwork_complete(),
		"junction_field_findings": _junction_field_findings.duplicate(),
		"junction_plant_unlocked": is_instance_valid(_junction_plant_interactable) \
			and bool(_junction_plant_interactable.get("interaction_enabled")),
		"gauntlet_stage": _gauntlet_stage,
		"gauntlet_midpoint_reached": _gauntlet_midpoint_reached,
		"gauntlet_strategy": _gauntlet_strategy,
		"gauntlet_flure_active": _gauntlet_flure_active.duplicate(),
		"gauntlet_reset_count": _gauntlet_reset_count,
		"gauntlet_safe_window_bonus": _gauntlet_safe_window_bonus,
		"damage_feedback_counts": _damage_feedback_counts.duplicate(),
		"below_fauna_enabled": _below_fauna_active,
		"below_fauna_dormant": _below_dormant_enemy_setups.size(),
	}, true)
	return state

func _complete() -> void:
	_enter_step("complete")
	_player.set_move_enabled(false)
	# Fade + scene change ride the scheduler (not a wall-clock tween), so the
	# blackout and the swap fire on the scheduler clock and never race a paused
	# or fast-forwarded sequence. The fade alpha is driven per-frame in
	# _on_process while the step is "complete".
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(2.0, _do_complete_scene_change, "complete_change")

func _do_complete_scene_change() -> void:
	_change_scene_or_record("res://scenes/tutorial/act1.tscn")

# --- Game Over ---

func _start_game_over() -> void:
	if _game_over:
		return
	_game_over = true
	_enter_step("game_over")
	_player.set_move_enabled(false)
	_scheduler.pause()
	# Stop all enemies
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy._change_state("idle")
	# Fade to dark red-black
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color", Color(0.08, 0.02, 0.02, 0.85), 2.0)
	tween.tween_callback(_show_game_over_text)

func _show_game_over_text() -> void:
	var overlay := preload("res://scenes/ui/game_over_overlay.tscn").instantiate() as CanvasLayer
	add_child(overlay)
	var label := overlay.get_node("Label") as Label
	var tween := create_tween()
	tween.tween_property(label, "theme_override_colors/font_color:a", 1.0, 2.0)

# The bridge chunk is built in STREAMABLE steps (see _chunk_build_steps): synchronous debug loads build it all,
# while normal play emits only a small batch of its repeated procedural pieces per frame.
func _build_bridge_chunk(parent: Node3D) -> void:
	_bridge_step_corridor(parent)
	_bridge_step_floor(parent)
	_bridge_step_model(parent)
	_bridge_step_blocked_end(parent)
	_bridge_step_light(parent)

func _bridge_step_corridor(parent: Node3D) -> void:
	var start_x := ELEVATOR_SIZE.x / 2.0 + 0.5
	var corridor_color := Color(0.07, 0.07, 0.09)
	var wall_color := Color(0.1, 0.1, 0.12)
	# Corridor floor leading out of elevator
	_add_corridor_section(parent, Vector3(start_x + 3.0, -0.05, 0), Vector3(7, 0.1, 4), corridor_color)
	var body := StaticBody3D.new()
	body.position = Vector3(start_x + 3.0, -0.01, 0)
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7, 0.02, 4)
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	_add_wall(parent, Vector3(start_x + 3.0, 2.0, -2.0), Vector3(7, 4, 0.2), wall_color)
	_add_wall(parent, Vector3(start_x + 3.0, 2.0, 2.0), Vector3(7, 4, 0.2), wall_color)
	var cor_light := OmniLight3D.new()
	cor_light.position = Vector3(start_x + 3.0, 3.0, 0)
	cor_light.light_color = Color(0.3, 0.2, 0.15)
	cor_light.light_energy = 1.5
	cor_light.omni_range = 8.0
	parent.add_child(cor_light)

# The collapsing span's WALKABLE collision slab (invisible): the player walks the grid, not the mesh. Spans the
# full BRIDGE_LENGTH so a click anywhere on the span lands on collision.
func _bridge_step_floor(parent: Node3D) -> void:
	var bridge_start := ELEVATOR_SIZE.x / 2.0 + 0.5 + 7.0
	var bridge_floor := Node3D.new()
	bridge_floor.name = "BridgeFloor"
	parent.add_child(bridge_floor)
	# Slab spans [bridge_start-1, bridge_start+LENGTH]: the -1 overlaps the corridor so a click at the seam still
	# lands on collision (the player walks the grid; this is only the click-raycast surface).
	var slab_west := bridge_start - 1.0
	var slab_east := bridge_start + BRIDGE_LENGTH
	var b2 := StaticBody3D.new()
	b2.position = Vector3((slab_west + slab_east) * 0.5, -0.01, 0)
	b2.collision_layer = 1
	b2.collision_mask = 0
	var c2 := CollisionShape3D.new()
	var s2 := BoxShape3D.new()
	s2.size = Vector3(slab_east - slab_west, 0.02, 3)
	c2.shape = s2
	b2.add_child(c2)
	bridge_floor.add_child(b2)
	_add_bridge_rail_collision(bridge_floor, "BridgeRailCollisionL", bridge_start, -BRIDGE_RAIL_Z)
	_add_bridge_rail_collision(bridge_floor, "BridgeRailCollisionR", bridge_start, BRIDGE_RAIL_Z)

func _add_bridge_rail_collision(parent: Node3D, body_name: String, bridge_start: float, z: float) -> void:
	var rail_body := StaticBody3D.new()
	rail_body.name = body_name
	rail_body.position = Vector3(bridge_start + BRIDGE_LENGTH * 0.5, 0.25, z)
	rail_body.collision_layer = 1
	rail_body.collision_mask = 0
	var rail_shape := CollisionShape3D.new()
	rail_shape.name = "RailShape"
	var rail_box := BoxShape3D.new()
	rail_box.size = Vector3(BRIDGE_LENGTH, 0.65, 0.25)
	rail_shape.shape = rail_box
	rail_body.add_child(rail_shape)
	parent.add_child(rail_body)

# The span is built from REPEATED TILE geometry sampling the pixel atlas (the same technique as the sim rooms /
# below deck): deck planks (deck_metal), segmented rusted girders (rust_iron) and cross-beams (facility_metal),
# each a discrete tiled box. A longer bridge just adds MORE planks — the world-triplanar atlas repeats crisply
# at any length (no stretching), and the discrete pieces are exactly what the hybrid collapse shatters + drops.
func _bridge_piece_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var bridge_start := ELEVATOR_SIZE.x / 2.0 + 0.5 + 7.0
	var plank_count := maxi(6, int(round(BRIDGE_LENGTH / 1.5)))
	var plank_len := BRIDGE_LENGTH / float(plank_count)
	for i in range(plank_count):
		var px := bridge_start + (i + 0.5) * plank_len
		specs.append({"name": "Deck_Plank_%d" % i, "pos": Vector3(px, -0.075, 0.0),
			"size": Vector3(plank_len * 0.97, 0.15, 3.0), "tile": "deck_metal"})
	var rail_count := maxi(3, int(round(BRIDGE_LENGTH / 3.0)))
	var rail_len := BRIDGE_LENGTH / float(rail_count)
	for side in [-1.0, 1.0]:
		for i in range(rail_count):
			var rx := bridge_start + (i + 0.5) * rail_len
			specs.append({"name": "Girder_%s_%d" % ["R" if side > 0.0 else "L", i],
				"pos": Vector3(rx, 0.25, side * BRIDGE_RAIL_Z), "size": Vector3(rail_len * 0.95, 0.5, 0.2),
				"tile": "rust_iron"})
	var beam_count := maxi(2, int(round(BRIDGE_LENGTH / 4.0)))
	for i in range(beam_count):
		var bx := bridge_start + (i + 0.5) * (BRIDGE_LENGTH / float(beam_count))
		specs.append({"name": "Crossbeam_%d" % i, "pos": Vector3(bx, -0.3, 0.0),
			"size": Vector3(0.3, 0.35, 3.2), "tile": "facility_metal"})
	return specs

func _bridge_step_model_root(parent: Node3D) -> void:
	var bridge_floor := parent.find_child("BridgeFloor", false, false)
	if bridge_floor == null or bridge_floor.find_child("BridgeModel", false, false) != null:
		return
	var model := Node3D.new()
	model.name = "BridgeModel"
	bridge_floor.add_child(model)

func _bridge_step_model_batch(parent: Node3D, specs: Array) -> void:
	var bridge_floor := parent.find_child("BridgeFloor", false, false)
	var model: Node3D = bridge_floor.find_child("BridgeModel", false, false) if bridge_floor != null else null
	if model == null:
		return
	for spec_variant in specs:
		var spec: Dictionary = spec_variant
		_add_bridge_piece(model, str(spec["name"]), spec["pos"], spec["size"], str(spec["tile"]))

func _bridge_step_model(parent: Node3D) -> void:
	_bridge_step_model_root(parent)
	_bridge_step_model_batch(parent, _bridge_piece_specs())

## One tiled bridge piece: a box mesh sampling the atlas tile via the world-triplanar tiling material. Named so
## the collapse can identify deck planks; a discrete MeshInstance3D so _collapse_bridge_model drops it as debris.
func _add_bridge_piece(model: Node3D, piece_name: String, pos: Vector3, size: Vector3, tile: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = piece_name
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	if not _bridge_tile_materials.has(tile):
		_bridge_tile_materials[tile] = _tile_material(tile, 1.0)
	mi.material_override = _bridge_tile_materials[tile]
	# Low walkable/debris pieces cannot hide the party. Keeping them out of the dissolve pass also avoids
	# allocating a unique ShaderMaterial for every plank and girder at the end of the stream.
	mi.set_meta("camera_occlusion_exempt", true)
	mi.position = pos
	model.add_child(mi)

## Give the intact span a truthful destination. The old deck ended in unlit void, so the last third vanished
## against the background and read like a prematurely truncated bridge. This landing and sealed bulkhead are
## deliberately outside BridgeModel: the span collapses, while the blocked destination remains structurally
## intact until the upper chunk is retired after the fall.
func _bridge_step_blocked_end(parent: Node3D) -> void:
	if parent.find_child("BridgeBlockedEnd", false, false) != null:
		return
	var blocked_end := Node3D.new()
	blocked_end.name = "BridgeBlockedEnd"
	parent.add_child(blocked_end)

	var landing_center_x := BRIDGE_END_X + BRIDGE_END_LANDING_LENGTH * 0.5
	var landing := MeshInstance3D.new()
	landing.name = "BridgeEndLanding"
	var landing_mesh := BoxMesh.new()
	landing_mesh.size = Vector3(BRIDGE_END_LANDING_LENGTH, 0.22, 6.0)
	landing.mesh = landing_mesh
	landing.material_override = _tile_material("deck_metal", 1.0)
	landing.position = Vector3(landing_center_x, -0.11, 0.0)
	landing.set_meta("camera_occlusion_exempt", true)
	blocked_end.add_child(landing)

	var landing_body := StaticBody3D.new()
	landing_body.name = "BridgeEndLandingCollision"
	landing_body.position = landing.position
	landing_body.collision_layer = 1
	landing_body.collision_mask = 0
	var landing_shape := CollisionShape3D.new()
	var landing_box := BoxShape3D.new()
	landing_box.size = landing_mesh.size
	landing_shape.shape = landing_box
	landing_body.add_child(landing_shape)
	blocked_end.add_child(landing_body)

	# A dark load-bearing frame makes the translucent seal read as a blocked aperture, not open darkness.
	var frame_mat := _tile_material("rust_iron", 1.0)
	_add_bridge_end_box(blocked_end, "BridgeEndFrameL",
		Vector3(BRIDGE_BLOCKADE_X, 2.0, -2.8), Vector3(0.55, 4.0, 0.55), frame_mat)
	_add_bridge_end_box(blocked_end, "BridgeEndFrameR",
		Vector3(BRIDGE_BLOCKADE_X, 2.0, 2.8), Vector3(0.55, 4.0, 0.55), frame_mat)
	_add_bridge_end_box(blocked_end, "BridgeEndFrameTop",
		Vector3(BRIDGE_BLOCKADE_X, 3.8, 0.0), Vector3(0.55, 0.45, 6.1), frame_mat)

	var chembrane_mat := StandardMaterial3D.new()
	chembrane_mat.albedo_color = Color(0.34, 0.16, 0.42, 0.84)
	chembrane_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	chembrane_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	chembrane_mat.emission_enabled = true
	chembrane_mat.emission = Color(0.16, 0.05, 0.22)
	chembrane_mat.emission_energy_multiplier = 1.4
	var chembrane := _add_bridge_end_box(blocked_end, "ChembraneBarrier",
		Vector3(BRIDGE_BLOCKADE_X - 0.03, 1.85, 0.0), Vector3(0.18, 3.45, 5.1), chembrane_mat)
	chembrane.set_meta("substance", "chembrane")
	chembrane.set_meta("display_name", "Chembrane Seal")

	# Physics agrees with the picture even though the upper grid footprint already ends before this wall.
	var blocker := StaticBody3D.new()
	blocker.name = "BridgeEndBlocker"
	blocker.position = Vector3(BRIDGE_BLOCKADE_X, 1.9, 0.0)
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var blocker_shape := CollisionShape3D.new()
	blocker_shape.name = "BlockerShape"
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(0.5, 3.8, 6.0)
	blocker_shape.shape = blocker_box
	blocker.add_child(blocker_shape)
	blocked_end.add_child(blocker)

	var status := Label3D.new()
	status.name = "BridgeEndBlockedLabel"
	status.text = "CHEMBRANE SEAL  /  ACCESS BLOCKED"
	status.font_size = 48
	status.pixel_size = 0.004
	status.modulate = Color(1.0, 0.48, 0.18)
	status.outline_modulate = Color(0.02, 0.01, 0.02, 0.95)
	status.outline_size = 10
	status.position = Vector3(BRIDGE_BLOCKADE_X - 0.35, 2.6, 0.0)
	status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	blocked_end.add_child(status)

func _add_bridge_end_box(
		parent: Node3D,
		box_name: String,
		pos: Vector3,
		size: Vector3,
		material: Material
	) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = box_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	mesh_instance.position = pos
	mesh_instance.set_meta("camera_occlusion_exempt", true)
	parent.add_child(mesh_instance)
	return mesh_instance

func _bridge_step_light(parent: Node3D) -> void:
	if parent.find_child("BridgeLighting", false, false) != null:
		return
	# Fixed light hierarchy and defaults belong in the authored scene. Streaming
	# decides WHEN it exists; the .tscn remains the inspectable source of WHAT it is.
	parent.add_child(BRIDGE_LIGHTING_SCENE.instantiate())

func _build_below_chunk(parent: Node3D, enemies_dormant := false) -> void:
	_below_step_prepare(parent)
	_below_step_ground(parent)
	_below_step_grated_platforms(parent)
	_below_step_read_stations(parent)
	_below_step_aster_route_overlay(parent)
	_below_step_peris_route_overlay_path(parent)
	for beat_i in range(ROUTE_BEAT_COUNT):
		_below_step_peris_route_overlay_beat(parent, beat_i)
	_below_step_huddle_chelator_batch(parent, 0, 3, enemies_dormant)
	_below_step_huddle_chelator_batch(parent, 3, 6, enemies_dormant)
	_below_step_huddle_predators(parent, enemies_dormant)
	_below_step_ambient_props(parent)
	_below_step_route_shell(parent)
	for beat_i in range(ROUTE_BEAT_COUNT):
		_below_step_enemy_route_beat(parent, beat_i, enemies_dormant)
	_below_step_hazard_shell(parent)
	for beat_i in range(ROUTE_BEAT_COUNT):
		_below_step_hazard_beat(parent, beat_i)
	_below_step_stalactites(parent)
	_below_step_convergence(parent)
	_below_step_wreckage_gate(parent, enemies_dormant)
	if not enemies_dormant:
		_below_fauna_active = true

func _below_step_prepare(parent: Node3D) -> void:
	# The lower route has broad wall/ceiling meshes close to the camera. Their
	# dithered reveal holes become a dense field of bright micro-silhouettes when
	# Aster's screen-space data view is active. Use the same coherent reveal edge
	# as the elevator shell so the two effects compose without stipple or the
	# associated outline cost.
	parent.set_meta("camera_occlusion_outline_safe_clip", true)
	if _scheduler != null:
		_scheduler.cancel_tag(IRON_HAZARD_TAG)
	_iron_hazard_tick_armed = false
	_aster_route_overlay_root = null
	_peris_route_overlay_root = null
	_peris_route_overlay_endpoint = null
	_route_flure_interactables.clear()
	_route_flure_meshes.clear()
	_route_flure_enemy_groups.clear()
	_grated_platforms = null
	_grated_platform_signal_marker = null
	_grated_platform_enemy_markers.clear()
	_grated_platform_wall_openings.clear()
	_wreckage_gate = null
	_wreckage_interactable = null
	_wreckage_listeners.clear()
	_wreckage_armed = false
	_wreckage_cleared = false
	_wreckage_solo_attempted = false
	_wreckage_failure_active = false
	_wreckage_alert_target = ""
	_iron_patches.clear()
	_iron_contact_warning_shown.clear()
	_below_dormant_enemy_setups.clear()
	_below_fauna_active = false
	_below_activation_cells.clear()

func _below_step_ground(parent: Node3D) -> void:
	var deck_west := LOWER_ROUTE_WEST_X
	var deck_east := JUNCTION_POS.x + 4.0
	var deck_len := deck_east - deck_west
	var deck_cx := (deck_west + deck_east) * 0.5
	var ground_body := StaticBody3D.new()
	ground_body.position = Vector3(deck_cx, BELOW_Y - 0.01, 0)
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(deck_len, 0.02, 16)
	gc.shape = gs
	ground_body.add_child(gc)
	parent.add_child(ground_body)
	_add_corridor_section(parent, Vector3(deck_cx, BELOW_Y - 0.05, 0), Vector3(deck_len, 0.1, 16),
		Color(0.05, 0.05, 0.07))
	var west_blockade := LOWER_ROUTE_BLOCKADE_SCENE.instantiate() as Node3D
	west_blockade.position = Vector3(LOWER_ROUTE_WEST_X - 0.75, BELOW_Y, 0.0)
	parent.add_child(west_blockade)

## Two authored standing decks turn the second ecology beat into a spatial composition: Peris can
## light the western Flure while the eastern fauna are still on their roost, or cross first and let
## their ordinary perception react. The scene owns geometry/collision/sockets; this loader only binds
## those sockets to the shared grid and the existing stage-1 Plant-as-tool beat.
func _below_step_grated_platforms(parent: Node3D) -> void:
	if is_instance_valid(_grated_platforms):
		return
	_grated_platforms = GRATED_PLATFORMS_SCENE.instantiate() as Node3D
	_grated_platforms.position = GRATED_PLATFORM_POS
	parent.add_child(_grated_platforms)
	_grated_platform_signal_marker = _grated_platforms.get_node_or_null("Markers/SignalMarker") as Marker3D
	for marker_name in ["EnemySpawn0", "EnemySpawn1"]:
		var marker := _grated_platforms.get_node_or_null("Markers/" + marker_name) as Marker3D
		if marker != null:
			_grated_platform_enemy_markers.append(marker)
	for marker_name in ["WallOpening0", "WallOpening1"]:
		var marker := _grated_platforms.get_node_or_null("Markers/" + marker_name) as Marker3D
		if marker != null:
			_grated_platform_wall_openings.append(marker)
	for marker_name in ["WalkableSignalDeck", "WalkableConnector", "WalkableRoostDeck"]:
		var marker := _grated_platforms.get_node_or_null("Markers/" + marker_name) as Marker3D
		if marker == null:
			continue
		var half_extents: Vector2 = marker.get_meta("half_extents", Vector2.ZERO)
		var center := Vector2(marker.global_position.x, marker.global_position.z)
		_add_level_walkable_region(LEVEL_LOWER, center - half_extents, center + half_extents)
	_block_grated_platform_rail_cells()

## Grid movement is authoritative for both the party and fauna, so the authored rail collision is
## mirrored into the level allow-set. Reading the BoxShape3D nodes keeps visual/physics/grid bounds
## coupled: moving a rail in the scene moves the gameplay blocker with it.
func _block_grated_platform_rail_cells() -> void:
	if not is_instance_valid(_grated_platforms):
		return
	var rail_body := _grated_platforms.get_node_or_null("RailCollision") as StaticBody3D
	if rail_body == null:
		return
	for child in rail_body.get_children():
		var collision := child as CollisionShape3D
		if collision == null or not (collision.shape is BoxShape3D):
			continue
		var size := (collision.shape as BoxShape3D).size
		var center := collision.global_position
		var half := Vector2(size.x, size.z) * 0.5
		_block_level_walkable_region(
			LEVEL_LOWER,
			Vector2(center.x, center.z) - half,
			Vector2(center.x, center.z) + half
		)

func _below_step_read_stations(parent: Node3D) -> void:
	var overlay_guides := Node3D.new()
	overlay_guides.name = "RouteOverlayGuides"
	parent.add_child(overlay_guides)
	_aster_route_overlay_root = Node3D.new()
	_aster_route_overlay_root.name = "AsterRouteOverlay"
	overlay_guides.add_child(_aster_route_overlay_root)
	_peris_route_overlay_root = Node3D.new()
	_peris_route_overlay_root.name = "PerisRouteOverlay"
	overlay_guides.add_child(_peris_route_overlay_root)
	_apply_elevator_overlay_visibility()
	# Authored broad pools keep the route readable in Web and replace the old
	# four tiny generated lamps that left almost the entire decision space black.
	parent.add_child(LOWER_ROUTE_LIGHTING_SCENE.instantiate())

## Aster's already-active data register describes the ecology lane as a causal network: every Flure broadcasts
## to the two bodies it can draw away. This is visible from the fork without walking to three read pedestals.
func _route_flure_position(beat_i: int) -> Vector3:
	if beat_i == GRATED_PLATFORM_ROUTE_BEAT and is_instance_valid(_grated_platform_signal_marker):
		return _grated_platform_signal_marker.global_position
	return Vector3(
		FORK_POS.x + float(ROUTE_BEAT_OFFSETS[beat_i]) - 5.0,
		BELOW_Y + 0.3,
		-5.7
	)

func _route_enemy_position(beat_i: int, local_i: int) -> Vector3:
	if beat_i == GRATED_PLATFORM_ROUTE_BEAT and local_i >= 0 \
			and local_i < _grated_platform_enemy_markers.size():
		var marker := _grated_platform_enemy_markers[local_i]
		if is_instance_valid(marker):
			return marker.global_position
	var beat_x := FORK_POS.x + float(ROUTE_BEAT_OFFSETS[beat_i])
	return Vector3(beat_x + 1.5 + local_i * 3.0, BELOW_Y + 0.5, -3.0 - local_i * 2.0)

func _below_step_aster_route_overlay(_parent: Node3D) -> void:
	if not is_instance_valid(_aster_route_overlay_root):
		return
	var route_mat := _route_overlay_material(Color(0.22, 0.78, 0.72, 0.72))
	var link_mat := _route_overlay_material(Color(0.42, 0.78, 1.0, 0.72))
	var route_points: Array[Vector3] = [
		Vector3(ROUTE_READ_ASTER_POS.x, BELOW_Y + 0.09, -4.5),
	]
	for beat_i in range(ROUTE_BEAT_COUNT):
		var flure_world := _route_flure_position(beat_i)
		var flure_pos := Vector3(flure_world.x, BELOW_Y + 0.09, flure_world.z)
		if beat_i == GRATED_PLATFORM_ROUTE_BEAT \
				and not _grated_platform_wall_openings.is_empty() \
				and is_instance_valid(_grated_platform_wall_openings[0]):
			var entry := _grated_platform_wall_openings[0].global_position
			route_points.append(Vector3(entry.x, BELOW_Y + 0.09, entry.z))
		route_points.append(flure_pos)
		for local_i in range(2):
			var enemy_world := _route_enemy_position(beat_i, local_i)
			var enemy_pos := Vector3(enemy_world.x, BELOW_Y + 0.09, enemy_world.z)
			_add_route_overlay_segment(
				_aster_route_overlay_root,
				"AsterFlureLink%d_%d" % [beat_i, local_i],
				flure_pos,
				enemy_pos,
				0.09,
				link_mat
			)
		_add_route_overlay_label(
			_aster_route_overlay_root,
			"AsterFlureLabel%d" % beat_i,
			"FLURE %d  ->  PACK DRAW" % (beat_i + 1),
			flure_pos + Vector3(0.0, 1.5, 0.0),
			Color(0.48, 0.88, 1.0)
		)
		if beat_i == GRATED_PLATFORM_ROUTE_BEAT \
				and _grated_platform_wall_openings.size() > 1 \
				and is_instance_valid(_grated_platform_wall_openings[1]):
			var exit_marker_pos := _grated_platform_wall_openings[1].global_position
			route_points.append(Vector3(exit_marker_pos.x, BELOW_Y + 0.09, exit_marker_pos.z))
	route_points.append(Vector3(ROUTES_CONVERGE.x, BELOW_Y + 0.09, -4.0))
	for point_i in range(route_points.size() - 1):
		_add_route_overlay_segment(
			_aster_route_overlay_root,
			"AsterEcologyRoute%d" % point_i,
			route_points[point_i],
			route_points[point_i + 1],
			0.12,
			route_mat
		)
	_apply_elevator_overlay_visibility()

## Peris supplies the missing WHERE read. Her memory layer draws one exact edge route around the iron fields and
## carries it all the way to a final-position marker at convergence, so the overlay changes a route decision.
func _below_step_peris_route_overlay_path(_parent: Node3D) -> void:
	if not is_instance_valid(_peris_route_overlay_root):
		return
	var path_mat := _route_overlay_material(Color(1.0, 0.65, 0.24, 0.86))
	var points: Array[Vector3] = [
		Vector3(ROUTE_READ_PERIS_POS.x, BELOW_Y + 0.11, 4.5),
		Vector3(FORK_POS.x + 4.0, BELOW_Y + 0.11, 6.45),
	]
	for beat_i in range(ROUTE_BEAT_COUNT):
		points.append(Vector3(
			FORK_POS.x + float(ROUTE_BEAT_OFFSETS[beat_i]) + 6.0,
			BELOW_Y + 0.11,
			6.45
		))
	points.append(Vector3(ROUTES_CONVERGE.x, BELOW_Y + 0.11, 4.0))
	# Reuse the same dashed, grounded, depth-aware renderer as ordinary hover
	# previews and the fragments. This keeps one visual grammar for "planned path"
	# and avoids a second implementation made from enormous solid BoxMeshes.
	var safe_route_guide := PathRenderer.new()
	safe_route_guide.name = "PerisSafeRouteGuide"
	safe_route_guide.preview_style = true
	safe_route_guide.game_state = _game_state
	safe_route_guide.color = Color(1.0, 0.65, 0.24)
	_peris_route_overlay_root.add_child(safe_route_guide)
	safe_route_guide.global_position = points[0]
	safe_route_guide.set_explicit_path(points)
	var start_marker := MeshInstance3D.new()
	start_marker.name = "PerisSafeRouteStart"
	var start_ring := TorusMesh.new()
	start_ring.inner_radius = 0.68
	start_ring.outer_radius = 0.78
	start_marker.mesh = start_ring
	start_marker.material_override = path_mat
	start_marker.position = points[0] + Vector3(0.0, 0.02, 0.0)
	start_marker.rotation.x = PI * 0.5
	start_marker.set_meta("camera_occlusion_exempt", true)
	_peris_route_overlay_root.add_child(start_marker)
	_add_route_overlay_label(
		_peris_route_overlay_root,
		"PerisSafeEdgeLabel",
		"REMEMBERED MAINTENANCE EDGE  /  SAFE",
		points[1] + Vector3(1.0, 1.5, 0.0),
		Color(1.0, 0.76, 0.34)
	)
	_peris_route_overlay_endpoint = Node3D.new()
	_peris_route_overlay_endpoint.name = "PerisRouteFinalPosition"
	_peris_route_overlay_endpoint.position = Vector3(ROUTES_CONVERGE.x, BELOW_Y + 0.12, 4.0)
	_peris_route_overlay_root.add_child(_peris_route_overlay_endpoint)
	var endpoint_mesh := MeshInstance3D.new()
	endpoint_mesh.name = "FinalPositionRing"
	var ring := CylinderMesh.new()
	ring.top_radius = 1.0
	ring.bottom_radius = 1.0
	ring.height = 0.035
	endpoint_mesh.mesh = ring
	endpoint_mesh.material_override = path_mat
	endpoint_mesh.set_meta("camera_occlusion_exempt", true)
	_peris_route_overlay_endpoint.add_child(endpoint_mesh)
	_add_route_overlay_label(
		_peris_route_overlay_endpoint,
		"PerisRouteFinalLabel",
		"ROUTES REJOIN  /  FINAL POSITION",
		Vector3(0.0, 1.65, 0.0),
		Color(1.0, 0.8, 0.42)
	)
	_apply_elevator_overlay_visibility()

## Peris's read makes the same visible rectangles available to the cautious planner. The preview and committed
## move now agree with her warm edge line; direct routing remains available later as an explicit risky choice.
func _learn_iron_route_risk() -> void:
	_iron_route_risk_learned = true
	for patch in _iron_patches:
		_register_iron_patch_risk(patch)
	if _game_state != null and not _game_state.is_route_cautious():
		_game_state.set_route_mode(true)

func _register_iron_patch_risk(patch: Dictionary) -> void:
	if _grid == null or patch.is_empty():
		return
	var pos: Vector3 = patch.get("pos", Vector3.ZERO)
	var size: Vector3 = patch.get("size", Vector3.ZERO)
	_grid.set_world_region_risk(
		Vector2(pos.x - size.x * 0.5, pos.z - size.z * 0.5),
		Vector2(pos.x + size.x * 0.5, pos.z + size.z * 0.5),
		IRON_ROUTE_RISK_PENALTY,
		true
	)

## Outline one authoritative damage footprint per stream step. The ordinary scene keeps the rust stain as a
## qualitative warning; Peris's layer adds the exact boundary needed to predict whether the edge route is safe.
func _below_step_peris_route_overlay_beat(_parent: Node3D, beat_i: int) -> void:
	if not is_instance_valid(_peris_route_overlay_root) or beat_i < 0 or beat_i >= ROUTE_BEAT_COUNT:
		return
	var ix := FORK_POS.x + float(ROUTE_BEAT_OFFSETS[beat_i])
	var center := Vector3(ix, BELOW_Y + 0.12, 3.3)
	var half_x := 5.0
	var half_z := 2.6
	var outline_mat := _route_overlay_material(Color(0.98, 0.35, 0.14, 0.78))
	var corners := [
		center + Vector3(-half_x, 0.0, -half_z),
		center + Vector3(half_x, 0.0, -half_z),
		center + Vector3(half_x, 0.0, half_z),
		center + Vector3(-half_x, 0.0, half_z),
	]
	for edge_i in range(4):
		_add_route_overlay_segment(
			_peris_route_overlay_root,
			"PerisIronBoundary%d_%d" % [beat_i, edge_i],
			corners[edge_i],
			corners[(edge_i + 1) % 4],
			0.16,
			outline_mat
		)
	_add_route_overlay_label(
		_peris_route_overlay_root,
		"PerisIronLabel%d" % beat_i,
		"IRON FIELD %d  /  KEEP TO OUTER EDGE" % (beat_i + 1),
		center + Vector3(0.0, 1.45, 0.0),
		Color(1.0, 0.55, 0.25)
	)
	_apply_elevator_overlay_visibility()

func _route_overlay_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# Grounded opaque emission is stable in Web and composes with the perception
	# pass without the transparent/no-depth sorting failures that erased this read.
	material.albedo_color = Color(color.r, color.g, color.b, 1.0)
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	return material

func _add_route_overlay_segment(
		parent: Node3D,
		segment_name: String,
		from_pos: Vector3,
		to_pos: Vector3,
		width: float,
		material: Material
	) -> MeshInstance3D:
	var delta := to_pos - from_pos
	var length := Vector2(delta.x, delta.z).length()
	var segment := MeshInstance3D.new()
	segment.name = segment_name
	var box := BoxMesh.new()
	box.size = Vector3(maxf(length, 0.05), 0.035, width)
	segment.mesh = box
	segment.material_override = material
	segment.position = (from_pos + to_pos) * 0.5
	segment.rotation.y = -atan2(delta.z, delta.x)
	segment.set_meta("camera_occlusion_exempt", true)
	parent.add_child(segment)
	return segment

func _add_route_overlay_label(
		parent: Node3D, label_name: String, text: String, pos: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = label_name
	label.text = text
	label.font_size = 42
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_modulate = Color(0.01, 0.01, 0.015, 0.96)
	label.outline_size = 9
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	return label

func _below_step_huddle_chelator_batch(
		parent: Node3D, first: int, end_exclusive: int, enemies_dormant: bool) -> void:
	for i in range(first, end_exclusive):
		var rng := RandomNumberGenerator.new()
		rng.seed = 0xBE10A5 + 100 + i
		var cid := "chelator_%d" % i
		var enemy_pos := Vector3(BRIDGE_START_X + i * 1.0, BELOW_Y + 0.5,
			(-5.0 if i % 2 == 0 else 5.0) + rng.randf_range(-1, 1))
		var enemy := _spawn_enemy(cid, enemy_pos, parent, false)
		enemy.max_hp = 20.0
		enemy._hp = 20.0
		enemy.detection_range = 4.0
		if i < 2:
			_build_flure(parent, Vector3(BRIDGE_START_X + 1.0, BELOW_Y + 0.4, -5.0 if i == 0 else 5.0))
		if enemies_dormant:
			_queue_below_enemy_setup(enemy, "roam", {"anchor": enemy_pos, "radius": 2.0}, 8.5)
		else:
			_activate_below_enemy_setup({"enemy": enemy, "mode": "roam",
				"data": {"anchor": enemy_pos, "radius": 2.0}})

func _below_step_huddle_predators(parent: Node3D, enemies_dormant: bool) -> void:
	for i in range(2):
		var pid := "predator_%d" % i
		var enemy_pos := Vector3(BRIDGE_START_X + 1.0 + i * 2.0, BELOW_Y + 0.5,
			-2.0 if i % 2 == 0 else 2.0)
		var predator := _spawn_enemy(pid, enemy_pos, parent, false)
		predator.max_hp = 80.0
		predator._hp = 80.0
		predator.move_speed = 2.0
		predator.charge_speed = 10.0
		predator.charge_damage = 35.0
		predator.detection_range = 6.0
		if predator._mesh and predator._mesh.mesh is CapsuleMesh:
			(predator._mesh.mesh as CapsuleMesh).radius = 0.35
			(predator._mesh.mesh as CapsuleMesh).height = 1.2
			predator._mesh.position.y = 0.6
		predator.color = Color(0.5, 0.12, 0.08)
		predator._base_color = Color(0.5, 0.12, 0.08)
		if predator._mesh and predator._mesh.material_override:
			(predator._mesh.material_override as StandardMaterial3D).albedo_color = Color(0.5, 0.12, 0.08)
		if enemies_dormant:
			_queue_below_enemy_setup(predator, "roam", {"anchor": enemy_pos, "radius": 2.5}, 9.0)
		else:
			_activate_below_enemy_setup({"enemy": predator, "mode": "roam",
				"data": {"anchor": enemy_pos, "radius": 2.5}})

func _below_step_ambient_props(parent: Node3D) -> void:
	var fluor_light := OmniLight3D.new()
	fluor_light.position = Vector3(BRIDGE_START_X + 3.0, BELOW_Y + 1.5, 6.0)
	fluor_light.light_color = Color(0.6, 0.9, 0.2)
	fluor_light.light_energy = 0.8
	fluor_light.omni_range = 3.5
	parent.add_child(fluor_light)
	var fluor_mesh := MeshInstance3D.new()
	var fluor_sphere := SphereMesh.new()
	fluor_sphere.radius = 0.3
	fluor_sphere.height = 0.6
	fluor_mesh.mesh = fluor_sphere
	var fluor_mat := StandardMaterial3D.new()
	fluor_mat.albedo_color = Color(0.4, 0.7, 0.15, 0.7)
	fluor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fluor_mat.emission_enabled = true
	fluor_mat.emission = Color(0.5, 0.8, 0.2)
	fluor_mat.emission_energy_multiplier = 1.5
	fluor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fluor_mesh.material_override = fluor_mat
	fluor_mesh.position = Vector3(BRIDGE_START_X + 3.0, BELOW_Y + 1.2, 6.0)
	parent.add_child(fluor_mesh)
	var chain := MeshInstance3D.new()
	var chain_cyl := CylinderMesh.new()
	chain_cyl.top_radius = 0.06
	chain_cyl.bottom_radius = 0.08
	chain_cyl.height = 3.5
	chain.mesh = chain_cyl
	var chain_mat := StandardMaterial3D.new()
	chain_mat.albedo_color = Color(0.08, 0.06, 0.05)
	chain.material_override = chain_mat
	chain.position = Vector3(BRIDGE_START_X + 8.0, BELOW_Y + 3.0, -5.5)
	chain.rotation.z = 0.15
	parent.add_child(chain)
	for i in range(4):
		var rng := RandomNumberGenerator.new()
		rng.seed = 0xBE10A5 + 200 + i
		var body_mesh := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.2
		cap.height = 0.8
		body_mesh.mesh = cap
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.15, 0.12, 0.1)
		body_mesh.material_override = bm
		body_mesh.position = Vector3(BRIDGE_START_X + 1.0 + i * 3.0, BELOW_Y,
			rng.randf_range(-3, 3))
		body_mesh.rotation.z = PI / 2.0
		parent.add_child(body_mesh)
	var terminal_glow := OmniLight3D.new()
	terminal_glow.position = Vector3(BRIDGE_START_X + 10.0, BELOW_Y + 2.0, -5.0)
	terminal_glow.light_color = Color(0.2, 0.5, 0.4)
	terminal_glow.light_energy = 0.6
	terminal_glow.omni_range = 4.0
	parent.add_child(terminal_glow)
	var growth_light := OmniLight3D.new()
	growth_light.position = Vector3(BRIDGE_START_X + 6.0, BELOW_Y + 0.8, 5.5)
	growth_light.light_color = Color(0.15, 0.5, 0.45)
	growth_light.light_energy = 0.4
	growth_light.omni_range = 2.5
	parent.add_child(growth_light)

func _add_route_outer_wall_segment(
		parent: Node3D, from_x: float, to_x: float, wall_color: Color) -> void:
	if to_x - from_x <= 0.05:
		return
	_add_wall(
		parent,
		Vector3((from_x + to_x) * 0.5, BELOW_Y + 1.5, -7.7),
		Vector3(to_x - from_x, 3.0, 0.3),
		wall_color
	)
	_block_level_walkable_region(LEVEL_LOWER, Vector2(from_x, -7.85), Vector2(to_x, -7.55))

## The ordinary corridor wall remains authoritative except at the two authored mouths. Keeping the
## openings as scene markers makes moving/resizing a platform an editor operation rather than a second
## set of hard-coded wall coordinates.
func _add_route_outer_wall_with_platform_openings(
		parent: Node3D, from_x: float, to_x: float, wall_color: Color) -> void:
	if _grated_platform_wall_openings.is_empty():
		_add_route_outer_wall_segment(parent, from_x, to_x, wall_color)
		return
	var cursor := from_x
	for opening in _grated_platform_wall_openings:
		if not is_instance_valid(opening):
			continue
		var half_width := float(opening.get_meta("width", 2.4)) * 0.5
		var opening_left := clampf(opening.global_position.x - half_width, from_x, to_x)
		var opening_right := clampf(opening.global_position.x + half_width, from_x, to_x)
		_add_route_outer_wall_segment(parent, cursor, opening_left, wall_color)
		cursor = maxf(cursor, opening_right)
	_add_route_outer_wall_segment(parent, cursor, to_x, wall_color)

func _below_step_route_shell(parent: Node3D) -> void:
	var route_wall_len := ROUTE_LANE_LENGTH + 4.0
	var route_wall_center := FORK_POS.x + route_wall_len * 0.5
	var wall_color := Color(0.08, 0.08, 0.1)
	_add_wall(parent, Vector3(route_wall_center, BELOW_Y + 1.5, 0),
		Vector3(route_wall_len, 3.0, 0.4), wall_color)
	_block_level_walkable_region(LEVEL_LOWER, Vector2(FORK_POS.x, -0.2),
		Vector2(FORK_POS.x + route_wall_len, 0.2))
	_add_route_outer_wall_with_platform_openings(
		parent, FORK_POS.x, FORK_POS.x + route_wall_len, wall_color
	)
	_route_flure_enemy_groups.clear()

func _below_step_enemy_route_beat(parent: Node3D, beat_i: int, enemies_dormant: bool) -> void:
	var beat_x := FORK_POS.x + float(ROUTE_BEAT_OFFSETS[beat_i])
	var lure_pos := _route_flure_position(beat_i)
	_build_route_flure_station(parent, beat_i, lure_pos)
	_route_flure_enemy_groups[beat_i] = []
	for local_i in range(2):
		var enemy_pos := _route_enemy_position(beat_i, local_i)
		var enemy := _spawn_enemy("route_enemy_%d_%d" % [beat_i, local_i], enemy_pos, parent, false)
		enemy.detection_range = 6.0
		# These animals huddle around the Flure; they do not need an A* patrol to
		# communicate that relationship. Cheap deterministic roam keeps them alive
		# and readable without six hidden route searches running under the bridge.
		var roam_data := {"anchor": enemy_pos, "radius": 1.8}
		if enemies_dormant:
			# Wake the two-body beat as one readable cohort before either member
			# reaches detection distance; the farther partner sits ~17.5m from the
			# approach seam.
			_queue_below_enemy_setup(enemy, "roam", roam_data, 19.0)
		else:
			_activate_below_enemy_setup({"enemy": enemy, "mode": "roam", "data": roam_data})
		(_route_flure_enemy_groups[beat_i] as Array).append(enemy)
	_add_route_field_plate(parent, Vector3(beat_x, BELOW_Y + 0.015, -4.0),
		Vector3(13.0, 0.02, 6.5), Color(0.08, 0.30, 0.20, 0.62))

func _below_step_hazard_shell(parent: Node3D) -> void:
	var route_wall_len := ROUTE_LANE_LENGTH + 4.0
	var route_wall_center := FORK_POS.x + route_wall_len * 0.5
	_add_wall(parent, Vector3(route_wall_center, BELOW_Y + 1.5, 7.7),
		Vector3(route_wall_len, 3.0, 0.3), Color(0.08, 0.08, 0.1))

func _below_step_hazard_beat(parent: Node3D, beat_i: int) -> void:
	var ix: float = FORK_POS.x + float(ROUTE_BEAT_OFFSETS[beat_i])
	var iron_pos := Vector3(ix, BELOW_Y + 0.02, 3.3)
	var iron_size := Vector3(10.0, 0.05, 5.2)
	var iron := MeshInstance3D.new()
	iron.name = "RouteIronField%d" % beat_i
	var ib := BoxMesh.new()
	ib.size = iron_size
	iron.mesh = ib
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(0.35, 0.15, 0.05)
	im.emission_enabled = true
	im.emission = Color(0.25, 0.08, 0.02)
	im.emission_energy_multiplier = 0.3
	iron.material_override = im
	iron.position = iron_pos
	parent.add_child(iron)
	var patch := {"pos": iron_pos, "size": iron_size}
	_iron_patches.append(patch)
	if _iron_route_risk_learned:
		_register_iron_patch_risk(patch)
	_arm_iron_hazard_tick()
	var ig := OmniLight3D.new()
	ig.position = Vector3(ix, BELOW_Y + 0.5, 5.0)
	ig.light_color = Color(0.7, 0.25, 0.05)
	ig.light_energy = 0.6
	ig.omni_range = 4.5
	parent.add_child(ig)
	_add_route_field_plate(parent, Vector3(ix, BELOW_Y + 0.04, 6.45),
		Vector3(12.5, 0.025, 1.35), Color(0.10, 0.15, 0.12, 0.42))

func _below_step_stalactites(parent: Node3D) -> void:
	for i in range(9):
		var rng := RandomNumberGenerator.new()
		rng.seed = 0xBE10A5 + 300 + i
		var drip := MeshInstance3D.new()
		var dc := CylinderMesh.new()
		dc.top_radius = 0.02
		dc.bottom_radius = 0.06
		dc.height = 0.8
		drip.mesh = dc
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.3, 0.12, 0.06)
		drip.material_override = dm
		var drip_beat := i / 3
		var drip_x := FORK_POS.x + float(ROUTE_BEAT_OFFSETS[drip_beat]) - 4.0 + float(i % 3) * 4.0
		drip.position = Vector3(drip_x, BELOW_Y + 2.6, 4.0 + rng.randf_range(-0.5, 2.0))
		parent.add_child(drip)

func _below_step_convergence(parent: Node3D) -> void:
	_add_corridor_section(parent, Vector3(ROUTES_CONVERGE.x, BELOW_Y - 0.04, 0),
		Vector3(8, 0.08, 12), Color(0.06, 0.06, 0.08))

## Authored transfer gate at the end of the lower route. The wreckage presents a visible two-body
## threshold; its two listeners remain dormant with the rest of the streamed ecology until the party
## approaches. A noisy solo attempt only WAKES + points ordinary Enemy FSMs at the actor -- strikes,
## damage feedback, downs, and game-over all stay in their shared gameplay systems.
func _below_step_wreckage_gate(parent: Node3D, enemies_dormant := false) -> void:
	if is_instance_valid(_wreckage_gate):
		return
	_wreckage_gate = WRECKAGE_GATE_SCENE.instantiate() as Node3D
	_wreckage_gate.position = WRECKAGE_GATE_POS
	parent.add_child(_wreckage_gate)
	_block_level_walkable_region(
		LEVEL_LOWER,
		Vector2(WRECKAGE_GATE_POS.x - 0.75, -6.0),
		Vector2(WRECKAGE_GATE_POS.x + 0.75, 6.0)
	)

	var anchor := _wreckage_interaction_anchor()
	_wreckage_interactable = _create_interactable(
		parent,
		anchor,
		"WreckageClear",
		2.0,
		2.2,
		"Clear together",
		false,
		Interactable.InteractableType.TIMED_ACTION
	)
	_wreckage_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_wreckage_interactable.set("description", "Unstable wreckage -- two braces required")
	_wreckage_interactable.set_interaction_enabled(false)
	_wreckage_interactable.interacted.connect(_on_wreckage_interacted)
	var rubble := _wreckage_gate.get_node_or_null("Rubble")
	var outline_target := _outline_object_meshes(
		parent,
		"WreckageGateOutline",
		_collect_mesh_instances(rubble) if rubble != null else [],
		"elevator_wreckage_gate",
		2.4,
		0.16
	)
	_set_room_target_interaction_delegate(outline_target, _wreckage_interactable)

	for marker_name in ["ListenerSpawnA", "ListenerSpawnB"]:
		var marker := _wreckage_gate.get_node_or_null("Markers/" + marker_name) as Marker3D
		if marker == null:
			continue
		var listener := _spawn_enemy("wreckage_listener_%d" % _wreckage_listeners.size(),
			marker.global_position, parent, false)
		listener.display_name = "Rubble Listener"
		listener.detection_range = 6.0
		listener.move_speed = 2.2
		listener.pursuit_speed = 4.2
		listener.pursuit_direct = true
		listener.charge_speed = 10.0
		listener.charge_damage = PARTY_MAX_HP
		listener.alert_duration = 0.45
		listener.windup_duration = 0.85
		listener.color = Color(0.56, 0.19, 0.08)
		listener._base_color = listener.color
		if listener._mesh != null and listener._mesh.material_override is StandardMaterial3D:
			(listener._mesh.material_override as StandardMaterial3D).albedo_color = listener.color
		_wreckage_listeners.append(listener)
		var setup := {
			"enemy": listener,
			"mode": "roam",
			"data": {"anchor": marker.global_position, "radius": 0.8},
			"wake_radius": 9.0,
		}
		if enemies_dormant:
			_below_dormant_enemy_setups.append(setup)
		else:
			_activate_below_enemy_setup(setup)

# One-shot source retained only as a layout reference while the staged methods above mirror the authored route.
func _build_below_chunk_one_shot_reference(parent: Node3D) -> void:
	var bridge_start := ELEVATOR_SIZE.x / 2.0 + 0.5 + 7.0
	var ground_y := BELOW_Y
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xBE10A5
	_route_flure_interactables.clear()
	_route_flure_meshes.clear()
	_route_flure_enemy_groups.clear()
	_iron_patches.clear()

	# The lower deck must be WALKABLE from the fall landing east to route convergence +
	# junction approach. The collapsed shaft is a truthful western system boundary;
	# extending the footprint back under the elevator created a long, black non-route.
	var deck_west := LOWER_ROUTE_WEST_X
	var deck_east := JUNCTION_POS.x + 4.0
	var deck_len := deck_east - deck_west
	var deck_cx := (deck_west + deck_east) * 0.5
	var ground_body := StaticBody3D.new()
	ground_body.position = Vector3(deck_cx, ground_y - 0.01, 0)
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(deck_len, 0.02, 16)
	gc.shape = gs
	ground_body.add_child(gc)
	parent.add_child(ground_body)

	_add_corridor_section(parent, Vector3(deck_cx, ground_y - 0.05, 0), Vector3(deck_len, 0.1, 16), Color(0.05, 0.05, 0.07))
	var west_blockade := LOWER_ROUTE_BLOCKADE_SCENE.instantiate() as Node3D
	west_blockade.position = Vector3(LOWER_ROUTE_WEST_X - 0.75, ground_y, 0.0)
	parent.add_child(west_blockade)

	# The retired one-shot reference mirrors the current overlay-first route read:
	# there are no character-locked perspective pedestals at the fork.

	# Iron blooms.
	for i in range(4):
		var bloom := OmniLight3D.new()
		bloom.position = Vector3(bridge_start + 1.5 + i * 3.0, ground_y + 1.0, rng.randf_range(-4, 4))
		bloom.light_color = Color(0.7, 0.3, 0.1)
		bloom.light_energy = 0.5
		bloom.omni_range = 3.0
		parent.add_child(bloom)

	# The below-bridge ecology huddles around flures and is DISTRACTED by them (see _arm_below_fauna):
	# it targets the party but only chases when Aster/Peris get really close. The party crosses the
	# bridge ABOVE (the vertical gap blocks detection entirely), then on the lower deck can keep distance
	# or take the hazard lane to slip past, or cut through the huddle and get caught. A flure sits with
	# each chelator cluster.
	var chelator_ids: Array[String] = []
	for i in range(6):
		var cid := "chelator_%d" % i
		chelator_ids.append(cid)
		var enemy := _spawn_enemy(cid,
			Vector3(bridge_start + 0.0 + i * 1.0, ground_y + 0.5, (-5.0 if i % 2 == 0 else 5.0) + rng.randf_range(-1, 1)),
			parent)
		enemy.max_hp = 20.0
		enemy._hp = 20.0
		enemy.detection_range = 4.0
		if i < 2:
			_build_flure(parent, Vector3(bridge_start + 1.0, ground_y + 0.4, -5.0 if i == 0 else 5.0))
		_arm_below_fauna(enemy, enemy.position, 2.0)

	# Predators are the bigger fauna in the same huddle — same rule (distracted, only chase up close).
	for i in range(2):
		var pid := "predator_%d" % i
		var predator := _spawn_enemy(pid,
			Vector3(bridge_start + 1.0 + i * 2.0, ground_y + 0.5, (-2.0 if i % 2 == 0 else 2.0)),
			parent)
		predator.max_hp = 80.0
		predator._hp = 80.0
		predator.move_speed = 2.0
		predator.charge_speed = 10.0
		predator.charge_damage = 35.0
		predator.detection_range = 6.0
		_game_state.characters[pid].stats["detection_range"] = 6.0
		if predator._mesh and predator._mesh.mesh is CapsuleMesh:
			(predator._mesh.mesh as CapsuleMesh).radius = 0.35
			(predator._mesh.mesh as CapsuleMesh).height = 1.2
			predator._mesh.position.y = 0.6
		predator.color = Color(0.5, 0.12, 0.08)
		predator._base_color = Color(0.5, 0.12, 0.08)
		if predator._mesh and predator._mesh.material_override:
			(predator._mesh.material_override as StandardMaterial3D).albedo_color = Color(0.5, 0.12, 0.08)
		_arm_below_fauna(predator, predator.position, 2.5)

	# Fluor bioluminescence.
	var fluor_light := OmniLight3D.new()
	fluor_light.position = Vector3(bridge_start + 3.0, ground_y + 1.5, 6.0)
	fluor_light.light_color = Color(0.6, 0.9, 0.2)
	fluor_light.light_energy = 0.8
	fluor_light.omni_range = 3.5
	parent.add_child(fluor_light)
	var fluor_mesh := MeshInstance3D.new()
	var fluor_sphere := SphereMesh.new()
	fluor_sphere.radius = 0.3
	fluor_sphere.height = 0.6
	fluor_mesh.mesh = fluor_sphere
	var fluor_mat := StandardMaterial3D.new()
	fluor_mat.albedo_color = Color(0.4, 0.7, 0.15, 0.7)
	fluor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fluor_mat.emission_enabled = true
	fluor_mat.emission = Color(0.5, 0.8, 0.2)
	fluor_mat.emission_energy_multiplier = 1.5
	fluor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fluor_mesh.material_override = fluor_mat
	fluor_mesh.position = Vector3(bridge_start + 3.0, ground_y + 1.2, 6.0)
	parent.add_child(fluor_mesh)

	# Chain hanging alongside a conduit bundle
	var chain := MeshInstance3D.new()
	var chain_cyl := CylinderMesh.new()
	chain_cyl.top_radius = 0.06
	chain_cyl.bottom_radius = 0.08
	chain_cyl.height = 3.5
	chain.mesh = chain_cyl
	var chain_mat := StandardMaterial3D.new()
	chain_mat.albedo_color = Color(0.08, 0.06, 0.05)
	chain.material_override = chain_mat
	chain.position = Vector3(bridge_start + 8.0, ground_y + 3.0, -5.5)
	chain.rotation.z = 0.15
	parent.add_child(chain)

	# Bodies between the blooms
	for i in range(4):
		var body_mesh := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.2
		cap.height = 0.8
		body_mesh.mesh = cap
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.15, 0.12, 0.1)
		body_mesh.material_override = bm
		body_mesh.position = Vector3(bridge_start + 1.0 + i * 3.0, ground_y, rng.randf_range(-3, 3))
		body_mesh.rotation.z = PI / 2.0
		parent.add_child(body_mesh)

	# Powered terminal (faint blue-green)
	var terminal_glow := OmniLight3D.new()
	terminal_glow.position = Vector3(bridge_start + 10.0, ground_y + 2.0, -5.0)
	terminal_glow.light_color = Color(0.2, 0.5, 0.4)
	terminal_glow.light_energy = 0.6
	terminal_glow.omni_range = 4.0
	parent.add_child(terminal_glow)

	# Something growing in an alcove (blue-green, alive)
	var growth_light := OmniLight3D.new()
	growth_light.position = Vector3(bridge_start + 6.0, ground_y + 0.8, 5.5)
	growth_light.light_color = Color(0.15, 0.5, 0.45)
	growth_light.light_energy = 0.4
	growth_light.omni_range = 2.5
	parent.add_child(growth_light)

	# --- Route fork geometry ---
	var fork_x := FORK_POS.x
	var wall_h := 3.0
	var wall_color := Color(0.08, 0.08, 0.1)

	# Central divider creates two branches.
	var route_wall_len := ROUTE_LANE_LENGTH + 4.0
	var route_wall_center := fork_x + route_wall_len * 0.5
	_add_wall(parent, Vector3(route_wall_center, ground_y + wall_h / 2.0, 0), Vector3(route_wall_len, wall_h, 0.4), wall_color)
	_block_level_walkable_region(LEVEL_LOWER, Vector2(fork_x, -0.2), Vector2(fork_x + route_wall_len, 0.2))

	var en_z := -4.0
	_add_wall(parent, Vector3(route_wall_center, ground_y + wall_h / 2.0, -7.7), Vector3(route_wall_len, wall_h, 0.3), wall_color)
	# Enemy-lane huddle: the fauna cluster around flures that BLOCK the corridor. Distracted by the
	# flures (shrunk detection), they ignore a party keeping its distance — but cutting straight through
	# the huddle to get down the lane brings Aster/Peris inside their reach and they give chase.
	_route_flure_enemy_groups.clear()
	for beat_i in range(ROUTE_BEAT_COUNT):
		var beat_x := fork_x + float(ROUTE_BEAT_OFFSETS[beat_i])
		var lure_pos := Vector3(beat_x - 5.0, ground_y + 0.3, -5.7)
		_build_route_flure_station(parent, beat_i, lure_pos)
		_route_flure_enemy_groups[beat_i] = []
		for local_i in range(2):
			var enemy_pos := Vector3(beat_x + 1.5 + local_i * 3.0, ground_y + 0.5, -3.0 - local_i * 2.0)
			var enemy := _spawn_enemy("route_enemy_%d_%d" % [beat_i, local_i], enemy_pos, parent)
			enemy.detection_range = 6.0
			enemy.set_patrol([
				enemy_pos + Vector3(-1.5, 0, -0.8),
				enemy_pos + Vector3(1.5, 0, 0.8),
			])
			(_route_flure_enemy_groups[beat_i] as Array).append(enemy)
		_add_route_field_plate(parent, Vector3(beat_x, ground_y + 0.015, en_z), Vector3(13.0, 0.02, 6.5), Color(0.08, 0.30, 0.20, 0.62))

	# Hazard route.
	var hz_z := 4.0
	_add_wall(parent, Vector3(route_wall_center, ground_y + wall_h / 2.0, 7.7), Vector3(route_wall_len, wall_h, 0.3), wall_color)
	# Three broad iron fields make this lane materially faster to read but dangerous
	# to cross carelessly. A narrow green edge strip remains a deliberate safe line.
	for i in range(ROUTE_BEAT_COUNT):
		var ix: float = fork_x + float(ROUTE_BEAT_OFFSETS[i])
		var iron_pos := Vector3(ix, ground_y + 0.02, hz_z - 0.7)
		var iron_size := Vector3(10.0, 0.05, 5.2)
		var iron := MeshInstance3D.new()
		iron.name = "RouteIronField%d" % i
		var ib := BoxMesh.new()
		ib.size = iron_size
		iron.mesh = ib
		var im := StandardMaterial3D.new()
		im.albedo_color = Color(0.35, 0.15, 0.05)
		im.emission_enabled = true
		im.emission = Color(0.25, 0.08, 0.02)
		im.emission_energy_multiplier = 0.3
		iron.material_override = im
		iron.position = iron_pos
		parent.add_child(iron)
		_iron_patches.append({"pos": iron_pos, "size": iron_size})
		var ig := OmniLight3D.new()
		ig.position = Vector3(ix, ground_y + 0.5, hz_z + 1.0)
		ig.light_color = Color(0.7, 0.25, 0.05)
		ig.light_energy = 0.6
		ig.omni_range = 4.5
		parent.add_child(ig)
		_add_route_field_plate(parent, Vector3(ix, ground_y + 0.04, 6.45), Vector3(12.5, 0.025, 1.35), Color(0.18, 0.46, 0.24, 0.82))

	# Rust stalactites.
	for i in range(9):
		var drip := MeshInstance3D.new()
		var dc := CylinderMesh.new()
		dc.top_radius = 0.02
		dc.bottom_radius = 0.06
		dc.height = 0.8
		drip.mesh = dc
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.3, 0.12, 0.06)
		drip.material_override = dm
		var drip_beat := i / 3
		var drip_x := fork_x + float(ROUTE_BEAT_OFFSETS[drip_beat]) - 4.0 + float(i % 3) * 4.0
		drip.position = Vector3(drip_x, ground_y + wall_h - 0.4, hz_z + rng.randf_range(-0.5, 2.0))
		parent.add_child(drip)

	# Route convergence chamber.
	var conv_x := ROUTES_CONVERGE.x
	_add_corridor_section(parent, Vector3(conv_x, ground_y - 0.04, 0), Vector3(8, 0.08, 12), Color(0.06, 0.06, 0.08))

func _build_junction_chunk(parent: Node3D) -> void:
	var ground_y := BELOW_Y
	var sx := JUNCTION_POS.x
	var sw := SHELTER_SIZE.x
	var sh := SHELTER_SIZE.y
	var sd := SHELTER_SIZE.z
	var wc := Color(0.12, 0.11, 0.1)
	_junction_interactables.clear()
	_junction_prep_interactables.clear()
	_junction_field_interactables.clear()
	_junction_field_evidence.clear()
	_junction_field_choices.clear()
	_junction_field_protocols_completed.clear()
	_junction_field_protocol = ""
	_junction_field_findings.clear()

	# Shelter floor
	_add_corridor_section(parent, Vector3(sx, ground_y - 0.03, 0), Vector3(sw + 2, 0.06, sd + 2), Color(0.08, 0.08, 0.09))

	# Entry wall with door gap.
	_add_wall(parent, Vector3(sx - sw / 2.0, ground_y + sh / 2.0, -sd * 0.35), Vector3(0.2, sh, sd * 0.3), wc)
	_add_wall(parent, Vector3(sx - sw / 2.0, ground_y + sh / 2.0, sd * 0.35), Vector3(0.2, sh, sd * 0.3), wc)
	_add_wall(parent, Vector3(sx + sw / 2.0, ground_y + sh / 2.0, 0), Vector3(0.2, sh, sd), wc)
	# Window-gap walls.
	_add_wall(parent, Vector3(sx, ground_y + 0.5, -sd / 2.0), Vector3(sw, 1.0, 0.2), wc)
	_add_wall(parent, Vector3(sx, ground_y + sh - 0.3, -sd / 2.0), Vector3(sw, 0.6, 0.2), wc)
	_add_wall(parent, Vector3(sx, ground_y + 0.5, sd / 2.0), Vector3(sw, 1.0, 0.2), wc)
	_add_wall(parent, Vector3(sx, ground_y + sh - 0.3, sd / 2.0), Vector3(sw, 0.6, 0.2), wc)
	_add_wall(parent, Vector3(sx, ground_y + sh, 0), Vector3(sw, 0.15, sd), Color(0.07, 0.07, 0.09))

	# Window grating.
	for z_side in [-sd / 2.0, sd / 2.0]:
		for i in range(4):
			var bar := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(0.03, 1.2, 0.03)
			bar.mesh = bb
			var bm := StandardMaterial3D.new()
			bm.albedo_color = Color(0.15, 0.14, 0.13)
			bar.material_override = bm
			bar.position = Vector3(sx - sw / 2.0 + 1.0 + i * 1.2, ground_y + 1.6, z_side)
			parent.add_child(bar)

	var interior_light := OmniLight3D.new()
	interior_light.name = "ShelterLight"
	interior_light.position = Vector3(sx, ground_y + sh - 0.5, 0)
	interior_light.light_color = Color(0.8, 0.6, 0.35)
	interior_light.light_energy = 2.5
	interior_light.omni_range = 6.0
	parent.add_child(interior_light)

	for i in range(2):
		var crate := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.6, 0.5, 0.6)
		crate.mesh = cb
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.2, 0.18, 0.15)
		crate.material_override = cm
		crate.position = Vector3(sx + 1.0 - i * 2.0, ground_y + 0.25, 1.0)
		parent.add_child(crate)

	var container := MeshInstance3D.new()
	container.name = "DrinkContainer"
	var co := BoxMesh.new()
	co.size = Vector3(0.8, 0.4, 0.5)
	container.mesh = co
	var cont_mat := StandardMaterial3D.new()
	cont_mat.albedo_color = Color(0.18, 0.2, 0.18)
	container.material_override = cont_mat
	container.position = Vector3(sx + 1.5, ground_y + 0.2, -1.0)
	parent.add_child(container)

	_drink_mesh = MeshInstance3D.new()
	_drink_mesh.name = "Drink"
	var dc := CylinderMesh.new()
	dc.top_radius = 0.06
	dc.bottom_radius = 0.05
	dc.height = 0.18
	_drink_mesh.mesh = dc
	var drink_mat := StandardMaterial3D.new()
	drink_mat.albedo_color = Color(0.25, 0.3, 0.35)
	drink_mat.metallic = 0.4
	drink_mat.roughness = 0.3
	_drink_mesh.material_override = drink_mat
	_drink_mesh.position = Vector3(sx + 1.5, ground_y + 0.5, -1.0)
	parent.add_child(_drink_mesh)

	# --- Junction interactables (GDD: Endo's Junction) ---

	# Workbench with tools
	var workbench := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(1.5, 0.7, 0.6)
	workbench.mesh = wb
	var wbm := StandardMaterial3D.new()
	wbm.albedo_color = Color(0.18, 0.15, 0.12)
	workbench.material_override = wbm
	workbench.position = Vector3(sx - 1.5, ground_y + 0.35, -1.8)
	parent.add_child(workbench)
	_add_junction_interactable("Workbench", Vector3(sx - 1.5, ground_y + 0.8, -1.8),
		"junction.workbench", "aster")

	# Monitoring station.
	var monitor_panel := MeshInstance3D.new()
	var mp := BoxMesh.new()
	mp.size = Vector3(1.0, 0.8, 0.1)
	monitor_panel.mesh = mp
	var mpm := StandardMaterial3D.new()
	mpm.albedo_color = Color(0.12, 0.14, 0.13)
	mpm.emission_enabled = true
	mpm.emission = Color(0.05, 0.08, 0.05)
	mpm.emission_energy_multiplier = 0.3
	monitor_panel.material_override = mpm
	monitor_panel.position = Vector3(sx + SHELTER_SIZE.x / 2.0 - 0.15, ground_y + 1.5, -1.0)
	parent.add_child(monitor_panel)
	_add_junction_interactable("Monitor", Vector3(sx + SHELTER_SIZE.x / 2.0 - 0.5, ground_y + 1.5, -1.0),
		"junction.monitor")

	# Food cache.
	var food_cache := MeshInstance3D.new()
	var fc := BoxMesh.new()
	fc.size = Vector3(0.5, 0.3, 0.4)
	food_cache.mesh = fc
	var fcm := StandardMaterial3D.new()
	fcm.albedo_color = Color(0.2, 0.2, 0.15)
	food_cache.material_override = fcm
	food_cache.position = Vector3(sx - 2.0, ground_y + 0.8, 1.5)
	parent.add_child(food_cache)
	_add_junction_interactable("Food", Vector3(sx - 2.0, ground_y + 1.0, 1.5),
		"junction.food", "peris")

	_add_junction_interactable("Lookout", Vector3(sx + 1.0, ground_y + 1.0, -SHELTER_SIZE.z / 2.0 + 0.3),
		"junction.lookout")

	var heater := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.4, 0.5, 0.4)
	heater.mesh = hb
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.25, 0.15, 0.1)
	hm.emission_enabled = true
	hm.emission = Color(0.3, 0.15, 0.05)
	hm.emission_energy_multiplier = 0.5
	heater.material_override = hm
	heater.position = Vector3(sx - SHELTER_SIZE.x / 2.0 + 0.3, ground_y + 0.25, 0)
	parent.add_child(heater)
	_add_junction_interactable("Heater", Vector3(sx - SHELTER_SIZE.x / 2.0 + 0.5, ground_y + 0.5, 0),
		"junction.heater")

	# Endo's barrier markings.
	var markings := Label3D.new()
	markings.text = "|| /// ||| // ||||| / ||"
	markings.font_size = 24
	markings.pixel_size = 0.008
	markings.modulate = Color(0.5, 0.45, 0.35, 0.6)
	markings.position = Vector3(sx + SHELTER_SIZE.x / 2.0 - 0.15, ground_y + 1.0, 1.0)
	markings.rotation.y = -PI / 2.0
	parent.add_child(markings)
	_add_junction_interactable("Markings", Vector3(sx + SHELTER_SIZE.x / 2.0 - 0.5, ground_y + 1.0, 1.0),
		"junction.markings")

	# Hand-carved puzzle.
	var game_piece := MeshInstance3D.new()
	var gp := BoxMesh.new()
	gp.size = Vector3(0.3, 0.1, 0.3)
	game_piece.mesh = gp
	var gpm := StandardMaterial3D.new()
	gpm.albedo_color = Color(0.22, 0.18, 0.14)
	gpm.roughness = 0.2
	game_piece.material_override = gpm
	game_piece.position = Vector3(sx - 1.2, ground_y + 0.75, -1.6)
	parent.add_child(game_piece)
	_add_junction_interactable("Game", Vector3(sx - 1.2, ground_y + 0.9, -1.6),
		"junction.game")

	# Peris tends this plant to trigger dusk and Endo.
	var plant_mesh := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.2
	pm.height = 0.3
	plant_mesh.mesh = pm
	var plant_mat := StandardMaterial3D.new()
	plant_mat.albedo_color = Color(0.15, 0.12, 0.08)
	plant_mat.roughness = 0.8
	plant_mesh.material_override = plant_mat
	plant_mesh.position = Vector3(sx + SHELTER_SIZE.x / 2.0 - 0.8, ground_y + 0.15, SHELTER_SIZE.z / 2.0 - 0.5)
	parent.add_child(plant_mesh)

	var plant_interact := preload("res://scenes/game/interactable.tscn").instantiate()
	plant_interact.name = "DormantPlant"
	plant_interact.description = "Dormant Plant"
	plant_interact.dialogue_key = "junction.peris.tend_plant"
	plant_interact.dialogue_box = _dialogue
	plant_interact.active_character = _active_character
	plant_interact.required_character = "peris"
	# Tending is deliberate click-to-work.  A proximity HOLD depended on a
	# physics body-enter event after click-arrival, which could leave the player
	# standing on the plant with no progress ring and no way forward.
	plant_interact.interactable_type = Interactable.InteractableType.TIMED_ACTION
	plant_interact.one_shot = true
	plant_interact.dwell_time = 2.0
	plant_interact.position = plant_mesh.position + Vector3(0, 0.3, 0)
	add_child(plant_interact)
	if plant_interact.has_method("set_scheduler"):
		plant_interact.set_scheduler(_scheduler)
		plant_interact.set_movement_authority(_game_state)
	_junction_plant_interactable = plant_interact
	plant_interact.set_interaction_enabled(false)
	plant_interact.interacted.connect(func():
		var bloom := create_tween()
		bloom.tween_property(plant_mat, "albedo_color", Color(0.2, 0.5, 0.3), 1.5)
		bloom.parallel().tween_property(plant_mat, "emission_enabled", true, 0.0)
		plant_mat.emission_enabled = true
		plant_mat.emission = Color(0.1, 0.3, 0.15)
		bloom.parallel().tween_property(plant_mat, "emission_energy_multiplier", 0.8, 2.0)
		bloom.parallel().tween_property(plant_mesh, "scale", Vector3(1.5, 1.8, 1.5), 2.0)
		_start_dusk_from_plant()
	)

	# The survey earns one of two practical preparations. These are real timed
	# work choices, remain disabled until the three-read/two-perspective gate, and
	# never add a passive timer to the shelter.
	_add_course_station_visual(parent, "JunctionRecoverStation", Vector3(sx - 0.6, ground_y, 1.75),
		Color(0.42, 0.78, 0.48), "RECOVER")
	var recover := _create_interactable(
		parent, Vector3(sx - 0.6, ground_y + 0.05, 1.75), "JunctionPrepRecover",
		1.35, 2.5, "Prepare recovery", true, Interactable.InteractableType.TIMED_ACTION
	)
	recover.description = "Prepare Recovery"
	recover.set_interaction_enabled(false)
	recover.interacted.connect(_choose_junction_preparation.bind("recover"))
	_junction_prep_interactables["recover"] = recover

	_add_course_station_visual(parent, "JunctionScoutStation", Vector3(sx + 1.25, ground_y, -1.75),
		Color(0.38, 0.68, 0.92), "SCOUT")
	var scout := _create_interactable(
		parent, Vector3(sx + 1.25, ground_y + 0.05, -1.75), "JunctionPrepScout",
		1.35, 2.5, "Map Flure windows", true, Interactable.InteractableType.TIMED_ACTION
	)
	scout.description = "Scout Flure Windows"
	scout.set_interaction_enabled(false)
	scout.interacted.connect(_choose_junction_preparation.bind("scout"))
	_junction_prep_interactables["scout"] = scout

func _build_junction_field_annex(parent: Node3D) -> void:
	# A measured service hall extends beyond the modeled shelter. It is loaded only during the
	# junction leg, so its footprint can overlap the later gauntlet chunk without coexisting with it.
	var annex_x0 := JUNCTION_POS.x + 3.5
	var annex_x1 := JUNCTION_POS.x + 60.0
	var annex_center := (annex_x0 + annex_x1) * 0.5
	var annex_length := annex_x1 - annex_x0
	_add_corridor_section(parent, Vector3(annex_center, BELOW_Y - 0.035, 0.0),
		Vector3(annex_length, 0.07, 12.0), Color(0.055, 0.075, 0.08))
	_add_wall(parent, Vector3(annex_center, BELOW_Y + 1.5, -6.0),
		Vector3(annex_length, 3.0, 0.25), Color(0.10, 0.14, 0.15))
	_add_wall(parent, Vector3(annex_center, BELOW_Y + 1.5, 6.0),
		Vector3(annex_length, 3.0, 0.25), Color(0.10, 0.14, 0.15))
	_add_wall(parent, Vector3(annex_x1, BELOW_Y + 1.5, 0.0),
		Vector3(0.25, 3.0, 12.0), Color(0.11, 0.13, 0.14))

	# Continuous center and shoulder datums make the hall legible at camera scale.
	for z in [-4.5, 0.0, 4.5]:
		_add_route_field_plate(parent, Vector3(annex_center, BELOW_Y + 0.012, z),
			Vector3(annex_length - 0.8, 0.018, 0.08), Color(0.26, 0.72, 0.68, 0.72))
	for meter_x in range(int(annex_x0) + 4, int(annex_x1), 3):
		_add_route_field_plate(parent, Vector3(float(meter_x), BELOW_Y + 0.014, 0.0),
			Vector3(0.055, 0.02, 11.0), Color(0.24, 0.50, 0.48, 0.5))

	var protocol_colors := {
		"descent_power": Color(0.38, 0.72, 0.94),
		"shelter_ecology": Color(0.42, 0.88, 0.56),
		"relay_signal": Color(0.94, 0.58, 0.24),
	}
	for protocol_index in range(JUNCTION_FIELD_PROTOCOL_ORDER.size()):
		var protocol_id := str(JUNCTION_FIELD_PROTOCOL_ORDER[protocol_index])
		var protocol: Dictionary = JUNCTION_FIELD_PROTOCOLS[protocol_id]
		var section_x := JUNCTION_POS.x + 12.0 + float(protocol_index) * 18.0
		var heading := Label3D.new()
		heading.name = "JunctionFieldHeading_%s" % protocol_id
		heading.text = "%02d  %s" % [protocol_index + 1, str(protocol.get("label", protocol_id))]
		heading.font_size = 48
		heading.pixel_size = 0.0035
		heading.modulate = (protocol_colors[protocol_id] as Color).lightened(0.15)
		heading.outline_modulate = Color(0.01, 0.02, 0.025, 0.96)
		heading.outline_size = 10
		heading.position = Vector3(section_x, BELOW_Y + 2.35, -5.72)
		heading.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(heading)

	for site_id_variant in JUNCTION_FIELD_SITES.keys():
		var site_id := str(site_id_variant)
		var spec: Dictionary = JUNCTION_FIELD_SITES[site_id]
		var protocol_id := str(spec.get("protocol", ""))
		var kind := str(spec.get("kind", "evidence"))
		var role := str(spec.get("role", ""))
		var pos: Vector3 = spec.get("pos", Vector3.ZERO)
		var color: Color = protocol_colors.get(protocol_id, Color.WHITE)
		if kind == "choice":
			color = color.lightened(0.18)
		elif kind == "resolution":
			color = color.lerp(Color(1.0, 0.76, 0.30), 0.35)
		var node_prefix := "JunctionField_%s" % site_id
		var visual := _add_course_station_visual(parent, node_prefix, pos, color,
			"%s / %s" % [str(spec.get("display", site_id)), role.to_upper()])
		var interact := _create_interactable(
			parent, pos, node_prefix, 1.55, float(spec.get("dwell", 8.0)),
			str(spec.get("verb", "WORK")), true, Interactable.InteractableType.TIMED_ACTION
		)
		interact.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
		interact.description = str(spec.get("display", site_id)).capitalize()
		_require_interactable_character(interact, role)
		interact.set_interaction_enabled(false)
		interact.interacted.connect(_on_junction_field_site.bind(site_id))
		var outline_target := _outline_object_meshes(parent, node_prefix + "Outline", [visual],
			"elevator_field_%s" % site_id, 1.55, 0.10)
		_set_room_target_interaction_delegate(outline_target, interact)
		_junction_field_interactables[site_id] = interact

	LevelDecoratorScript.decorate_corridor(parent, {
		"id": "elevator_junction_field_annex",
		"x0": annex_x0,
		"x1": annex_x1,
		"width": 12.0,
		"wall_height": 3.0,
		"ground_y": BELOW_Y,
		"seed": 0xE1E7A70,
		"program": "hydraulic",
		"spacing": 9.0,
		"replace_shell_materials": false,
		"floor_tint": Color(0.08, 0.13, 0.14),
		"wall_tint": Color(0.11, 0.17, 0.18),
		"trim": Color(0.30, 0.49, 0.48),
		"inset": Color(0.025, 0.045, 0.05),
		"service": Color(0.14, 0.24, 0.24),
		"rust": Color(0.40, 0.17, 0.06),
		"glow": Color(0.35, 0.90, 0.70),
		"light": Color(0.27, 0.56, 0.50),
		"signs": ["DESCENT POWER", "SHELTER ECOLOGY", "FLURE RELAY", "RETURN TO SHELTER  <"],
		"landmark_lights": true,
	})

func _start_dusk_from_plant() -> void:
	var env_node: Node = find_child("Environment", false, false)
	if env_node:
		for child in env_node.get_children():
			if child is WorldEnvironment:
				var t := create_tween()
				t.tween_property(child.environment, "ambient_light_energy", 0.15, 3.0)
				break
	_scheduler.schedule_after(2.0, _start_endo_enters, "endo_enters")

func _add_junction_interactable(
		label: String,
		pos: Vector3,
		dialogue_prefix: String,
		required_character := ""
	) -> Area3D:
	var interact := preload("res://scenes/game/interactable.tscn").instantiate()
	interact.name = "Junction_" + label
	interact.description = ("%s — %s" % [label, required_character.capitalize()]
		if required_character != "" else label)
	interact.dialogue_key = dialogue_prefix
	interact.dialogue_box = _dialogue
	interact.active_character = _active_character
	interact.required_character = required_character
	# Shelter props are repeatable inspections, but they must never auto-trigger merely because a
	# character stands nearby. The old HOLD_ACTION re-armed itself and flooded the dialogue queue.
	interact.interactable_type = Interactable.InteractableType.INSPECTION
	interact.one_shot = false
	interact.dwell_time = 1.0
	interact.position = pos
	add_child(interact)
	if interact.has_method("set_scheduler"):
		interact.set_scheduler(_scheduler)
		interact.set_movement_authority(_game_state)
	interact.interacted.connect(_on_junction_inspection.bind(label, interact))
	_junction_interactables[label] = interact
	return interact

func _make_gauntlet_flure_mesh(parent: Node3D, pos: Vector3, station_name: String, station_number: int) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = station_name
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.4, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.3, 0.05)
	mat.emission_energy_multiplier = 0.5
	mat.metallic = 0.5
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	var label := Label3D.new()
	label.name = station_name + "Label"
	label.text = "FLURE %d" % station_number
	label.font_size = 44
	label.pixel_size = 0.0035
	label.modulate = Color(1.0, 0.66, 0.24)
	label.outline_modulate = Color(0.02, 0.01, 0.0, 0.95)
	label.outline_size = 9
	label.position = pos + Vector3(0, 1.0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return mesh

func _build_gauntlet_chunk(parent: Node3D) -> void:
	var ground_y := BELOW_Y
	var gx := GAUNTLET_POS.x
	var wc := Color(0.09, 0.09, 0.11)

	# Ground floor — extended EAST past the exit gate so the player can actually run OUT of the gauntlet.
	# The old chamber + east wall both ended at x = GAUNTLET_EXIT.x - 2 (exactly the exit gate), so the
	# wall blocked the player from ever crossing it. Spans from the west entrance to the grid's east edge.
	var g_west := gx - 10.0
	var g_east := GAUNTLET_EXIT.x + 2.0
	var g_len := g_east - g_west
	var g_cx := (g_west + g_east) * 0.5
	_add_corridor_section(parent, Vector3(g_cx, ground_y - 0.03, 0), Vector3(g_len, 0.06, 14), Color(0.05, 0.05, 0.07))
	var gb := StaticBody3D.new()
	gb.position = Vector3(g_cx, ground_y - 0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(g_len, 0.02, 14)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Chamber walls: z-sides run the full length; the east wall sits at the far edge, PAST the exit gate
	# (GAUNTLET_EXIT.x - 2), so reaching the gate no longer means running into a wall.
	_add_wall(parent, Vector3(g_cx, ground_y + 1.5, -7.0), Vector3(g_len, 3, 0.3), wc)
	_add_wall(parent, Vector3(g_cx, ground_y + 1.5, 7.0), Vector3(g_len, 3, 0.3), wc)
	_add_wall(parent, Vector3(g_east, ground_y + 1.5, 0), Vector3(0.3, 3, 14), wc)

	# Two Peris-only stations divide the run into independently readable halves.
	_gauntlet_flure_meshes.clear()
	_gauntlet_flure_interactables.clear()
	_flure_mesh = _make_gauntlet_flure_mesh(parent, FLURE_POS, "Flure", 1)
	_gauntlet_flure_meshes.append(_flure_mesh)
	var flure_1 := _create_interactable(
		parent, FLURE_POS, "FlureInteract", 1.8, 1.0, "Activate Flure 1", true,
		Interactable.InteractableType.INSPECTION
	)
	flure_1.description = "Flure 1"
	_require_interactable_character(flure_1, "peris")
	flure_1.set_interaction_enabled(false)
	flure_1.interacted.connect(_on_flure_activated)
	_flure_interactable = flure_1
	_gauntlet_flure_interactables.append(flure_1)

	var flure_2_mesh := _make_gauntlet_flure_mesh(parent, GAUNTLET_FLURE_2_POS, "FlureRelay", 2)
	_gauntlet_flure_meshes.append(flure_2_mesh)
	var flure_2 := _create_interactable(
		parent, GAUNTLET_FLURE_2_POS, "FlureInteract2", 1.8, 1.0, "Activate Flure 2", true,
		Interactable.InteractableType.INSPECTION
	)
	flure_2.description = "Flure 2"
	_require_interactable_character(flure_2, "peris")
	flure_2.set_interaction_enabled(false)
	flure_2.interacted.connect(_on_gauntlet_flure_activated.bind(1))
	_gauntlet_flure_interactables.append(flure_2)

	# The midpoint is a visible, collision-free refuge and a real reset anchor.
	_add_route_field_plate(parent, GAUNTLET_MIDPOINT + Vector3(0, 0.025, 0),
		Vector3(7.0, 0.035, 9.0), Color(0.12, 0.42, 0.30, 0.78))
	var refuge_label := Label3D.new()
	refuge_label.name = "GauntletMidpointLabel"
	refuge_label.text = "MIDPOINT REFUGE"
	refuge_label.font_size = 54
	refuge_label.pixel_size = 0.0035
	refuge_label.modulate = Color(0.48, 0.94, 0.66)
	refuge_label.outline_modulate = Color(0.01, 0.03, 0.02, 0.95)
	refuge_label.outline_size = 10
	refuge_label.position = GAUNTLET_MIDPOINT + Vector3(0, 2.0, 0)
	refuge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(refuge_label)
	var refuge_light := OmniLight3D.new()
	refuge_light.name = "GauntletRefugeLight"
	refuge_light.position = GAUNTLET_MIDPOINT + Vector3(0, 2.2, 0)
	refuge_light.light_color = Color(0.30, 0.72, 0.48)
	refuge_light.light_energy = 1.15
	refuge_light.omni_range = 8.0
	parent.add_child(refuge_light)

	# Five deterministic enemies form two independent packs: three in stage one,
	# two beyond the refuge. This preserves the established encounter budget while
	# making the relay/reset structure spatially honest.
	_gauntlet_enemies.clear()
	_gauntlet_enemy_groups = {0: [], 1: []}
	var enemy_specs := [
		{"stage": 0, "pos": Vector3(gx - 4.0, ground_y + 0.5, 0.0)},
		{"stage": 0, "pos": Vector3(gx + 4.0, ground_y + 0.5, -2.4)},
		{"stage": 0, "pos": Vector3(gx + 12.0, ground_y + 0.5, 2.4)},
		{"stage": 1, "pos": GAUNTLET_MIDPOINT + Vector3(6.0, 0.5, -2.2)},
		{"stage": 1, "pos": GAUNTLET_MIDPOINT + Vector3(16.0, 0.5, 2.2)},
	]
	for i in range(enemy_specs.size()):
		var spec: Dictionary = enemy_specs[i]
		var stage := int(spec["stage"])
		var enemy_pos: Vector3 = spec["pos"]
		var eid := "gauntlet_%d" % i
		var enemy := _spawn_enemy(eid, enemy_pos, parent)
		enemy.detection_range = 5.0
		var pa := enemy_pos + Vector3(-1.0, 0, -1.5)
		var pb := enemy_pos + Vector3(1.0, 0, 1.5)
		enemy.set_patrol([pa, pb])
		_gauntlet_enemies.append(enemy)
		(_gauntlet_enemy_groups[stage] as Array).append(enemy)

	var gauntlet_light := OmniLight3D.new()
	gauntlet_light.position = Vector3(gx, ground_y + 2.5, 0)
	gauntlet_light.light_color = Color(0.2, 0.12, 0.08)
	gauntlet_light.light_energy = 1.5
	gauntlet_light.omni_range = 12.0
	parent.add_child(gauntlet_light)

## The shared authored corridor grammar supplies the same structural hierarchy
## as the building pass: repeated facade bays, attached service detail, route
## datums, restrained landmarks, and zero gameplay collision.
func _decorate_below_chunk(parent: Node3D) -> void:
	LevelDecoratorScript.decorate_corridor(parent, {
		"id": "elevator_below_routes",
		"x0": -3.5,
		"x1": JUNCTION_POS.x + 4.0,
		"width": 16.0,
		"wall_height": 3.0,
		"ground_y": BELOW_Y,
		"seed": 0xBE10A5,
		"program": "hydraulic",
		"spacing": 11.5,
		"replace_shell_materials": false,
		"floor_tile": "deck_metal",
		"wall_tile": "facility_metal",
		"floor_tint": Color(0.10, 0.15, 0.16),
		"wall_tint": Color(0.13, 0.19, 0.19),
		"trim": Color(0.31, 0.41, 0.38),
		"inset": Color(0.035, 0.055, 0.06),
		"service": Color(0.15, 0.23, 0.21),
		"rust": Color(0.37, 0.16, 0.06),
		"glow": Color(0.36, 0.91, 0.50),
		"light": Color(0.24, 0.48, 0.40),
		"signs": ["LOWER DECK / ROUTE READ", "FLURE LANE  <", "IRON FIELD  >"],
		"landmark_lights": true,
	})

func _decorate_gauntlet_chunk(parent: Node3D) -> void:
	LevelDecoratorScript.decorate_corridor(parent, {
		"id": "elevator_flure_relay",
		"x0": GAUNTLET_POS.x - 10.0,
		"x1": GAUNTLET_EXIT.x + 2.0,
		"width": 14.0,
		"wall_height": 3.0,
		"ground_y": BELOW_Y,
		"seed": 0xF1A2E2,
		"program": "boundary",
		"spacing": 9.0,
		"replace_shell_materials": false,
		"floor_tile": "deck_metal",
		"wall_tile": "rust_iron",
		"floor_tint": Color(0.10, 0.11, 0.14),
		"wall_tint": Color(0.16, 0.13, 0.12),
		"trim": Color(0.38, 0.34, 0.31),
		"inset": Color(0.045, 0.04, 0.05),
		"service": Color(0.22, 0.19, 0.18),
		"rust": Color(0.43, 0.17, 0.055),
		"glow": Color(0.95, 0.46, 0.12),
		"light": Color(0.58, 0.31, 0.18),
		"signs": ["FLURE RELAY / STAGE 1", "MIDPOINT REFUGE", "STAGE 2 / EXIT  >"],
		"landmark_lights": true,
	})

# --- Tiling pixel-art textures (the 32 px/m atlas, house technique) ---
# A world-triplanar material that REPEATS a tile in world space (no UV setup needed) with NEAREST
# sampling (crisp pixel art). Tiles live in res://resources/models/elevator/tiles/ (the procedural
# starting point in blender/textures/, for the user to repaint).
func _tile_material(tile_name: String, world_scale := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex = load("res://resources/models/elevator/tiles/%s.png" % tile_name)
	if tex != null:
		m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(world_scale, world_scale, world_scale)  # 1 tile / (1/scale) m
	return m

## Tile a chunk's STRUCTURAL surfaces (the direct mesh children that _add_corridor_section / _add_wall /
## _add_box add): flat slabs get the floor tile, vertical slabs the wall tile, via world triplanar so
## the tiles repeat in world space. Direct-children only, so enemies/props nested under their own nodes
## keep their materials.
func _apply_chunk_tiles(node: Node, floor_tile: String, wall_tile: String) -> void:
	for c in node.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var ab: AABB = (c as MeshInstance3D).mesh.get_aabb()
			var tile := floor_tile if ab.size.y < 0.6 else wall_tile
			if tile != "":
				(c as MeshInstance3D).material_override = _tile_material(tile, 1.0)

## Drop the modeled + textured Endo's-junction cave (Blender) in as the VISUAL backdrop for the junction
## chunk. The procedural shelter keeps ALL its gameplay (collision, interactables, the plant->dusk
## trigger, Endo's drink path, lights); only its plain floor slab + tall thin wall meshes are hidden so
## the modeled cave (rock walls, bioluminescent flora, catwalk, workbench) is what reads. Pre-repaint;
## fine alignment of the interactable zones to the model's features is a later pass.
func _add_junction_model(parent: Node3D) -> void:
	for c in parent.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var ab: AABB = (c as MeshInstance3D).mesh.get_aabb()
			# Only the big shell (the wide floor slab + the long tall thin walls) — NOT the small props
			# (plant, drink, mugs) or the workbench, which stay as the interactables.
			var is_floor := ab.size.y < 0.5 and (ab.size.x > 4.0 or ab.size.z > 4.0)
			var is_wall := ab.size.y > 2.0 and (ab.size.x > 3.0 or ab.size.z > 3.0) and minf(ab.size.x, ab.size.z) < 1.0
			if is_floor or is_wall:
				(c as MeshInstance3D).visible = false
	var m := ENDO_JUNCTION_MODEL.instantiate()
	m.name = "EndoJunctionModel"
	m.position = Vector3(JUNCTION_POS.x - 3.0, BELOW_Y, -3.1)
	m.scale = Vector3(0.55, 0.55, 0.55)
	parent.add_child(m)

func _add_corridor_section(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mesh.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	# Walkable collision under the section so click-raycasts land on it. Chunks built only via corridor
	# sections (the junction, the gauntlet) had no floor body, so once the below chunk unloaded the player
	# was clicking into void — the move silently failed and the descent stalled at junction_arrive.
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var cshape := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = size
	cshape.shape = cbox
	body.add_child(cshape)
	parent.add_child(body)

# --- Environment ---

func _build_elevator_chunk(parent: Node3D) -> void:
	var hw := ELEVATOR_SIZE.x / 2.0
	var h := ELEVATOR_SIZE.y
	# Aster's data outline follows this room. Give the car a continuous reveal
	# boundary so the outline cannot turn the occlusion dither into white pixels.
	parent.set_meta("camera_occlusion_outline_safe_clip", true)

	# The car SHELL is the modeled, pixel-grid elevator (Blender + a Geometry-Nodes floor grate): paneled
	# walls, the door opening + frame, ceiling light coffer, corner posts, control housing.
	var car := ELEVATOR_MODEL.instantiate()
	car.name = "ElevatorCar"
	parent.add_child(car)

	# Walkable / clickable floor collision (the player moves on the grid; clicks raycast this slab).
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0, -0.01, 0)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(ELEVATOR_SIZE.x, 0.02, ELEVATOR_SIZE.z)
	fc.shape = fs
	floor_body.add_child(fc)
	parent.add_child(floor_body)

	# Sliding doors (DYNAMIC — they animate apart): fill the modeled doorway, slide out on Z to open.
	_door_panel_a = _make_door_panel(parent, Vector3(hw - 0.05, 1.45, -0.6))
	_door_panel_b = _make_door_panel(parent, Vector3(hw - 0.05, 1.45, 0.6))

	# Pulsing red emergency light + a dim warm fill (the modeled ceiling panel adds static ambient glow).
	_emergency_light = OmniLight3D.new()
	_emergency_light.position = Vector3(0, h - 0.4, 0)
	_emergency_light.light_color = Color(0.85, 0.15, 0.1)
	_emergency_light.light_energy = 3.0
	_emergency_light.omni_range = 10.0
	parent.add_child(_emergency_light)

	_elevator_fill_light = OmniLight3D.new()
	_elevator_fill_light.name = "ElevatorFillLight"
	_elevator_fill_light.position = Vector3(0, h * 0.6, 0)
	_elevator_fill_light.light_color = Color(0.4, 0.25, 0.2)
	_elevator_fill_light.light_energy = 1.0
	_elevator_fill_light.omni_range = 8.0
	parent.add_child(_elevator_fill_light)

	# Floor readout "3B" on the wall beside the door: "3" steady, "B" flickering, both glowing. HDR
	# (>1) modulate blooms through the environment glow; a small red light backs it.
	var indicator_x := hw - 0.14
	_floor_indicator = Label3D.new()
	_floor_indicator.text = "3"
	_floor_indicator.font_size = 64
	_floor_indicator.pixel_size = 0.012
	_floor_indicator.modulate = Color(2.0, 0.45, 0.2, 1.0)
	_floor_indicator.position = Vector3(indicator_x, 2.6, 1.7)
	_floor_indicator.rotation.y = -PI / 2.0
	parent.add_child(_floor_indicator)

	_indicator_b_label = Label3D.new()
	_indicator_b_label.text = "B"
	_indicator_b_label.font_size = 64
	_indicator_b_label.pixel_size = 0.012
	_indicator_b_label.modulate = Color(2.0, 0.45, 0.2, 1.0)
	_indicator_b_label.position = Vector3(indicator_x, 2.6, 1.35)
	_indicator_b_label.rotation.y = -PI / 2.0
	parent.add_child(_indicator_b_label)

	_elevator_indicator_glow = OmniLight3D.new()
	_elevator_indicator_glow.name = "ElevatorIndicatorGlow"
	_elevator_indicator_glow.light_color = Color(0.95, 0.25, 0.15)
	_elevator_indicator_glow.light_energy = 1.4
	_elevator_indicator_glow.omni_range = 1.6
	_elevator_indicator_glow.position = Vector3(indicator_x - 0.15, 2.85, 1.5)
	parent.add_child(_elevator_indicator_glow)

	# Flashes before door access is restored.
	_no_exit_label = Label3D.new()
	_no_exit_label.text = "NO EXIT"
	_no_exit_label.font_size = 36
	_no_exit_label.pixel_size = 0.01
	_no_exit_label.modulate = Color(0.9, 0.15, 0.1, 0.0)
	_no_exit_label.position = Vector3(indicator_x, 2.1, 1.5)
	_no_exit_label.rotation.y = -PI / 2.0
	parent.add_child(_no_exit_label)

	_elevator_standby_lights.clear()
	for pos in [ESCORT_1_POS, ESCORT_2_POS]:
		var standby := OmniLight3D.new()
		standby.name = "EscortStandbyLight%d" % _elevator_standby_lights.size()
		standby.position = pos + Vector3(0, 1.5, 0)
		standby.light_color = Color(0.3, 0.3, 0.4)
		standby.light_energy = 0.5
		standby.omni_range = 2.5
		parent.add_child(standby)
		_elevator_standby_lights.append(standby)

func _make_door_panel(parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.12, 2.9, 1.2)  # fits the modeled 3u-tall doorway
	panel.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.105, 0.13)
	mat.metallic = 0.6
	mat.roughness = 0.45
	panel.material_override = mat
	panel.position = pos
	parent.add_child(panel)
	return panel
