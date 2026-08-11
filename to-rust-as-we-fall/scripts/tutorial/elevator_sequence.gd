@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"
# @rendering_only_file: decorative timing/randomness only.

## Elevator tutorial through bridge collapse, route choice, and Endo's shelter.

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")
const CanonicalCharacterAbilityScript := preload(
	"res://scripts/game/mechanics/canonical_character_ability.gd")
const StagedRigidCollapseScript := preload("res://scripts/game/world/staged_rigid_collapse_3d.gd")

var _aster_node: CharacterBody3D
var _peris_node: CharacterBody3D
var _fall_landed_fired := false  # one-shot guard: bridge landing fires once
var _fall_tween: Tween           # the cosmetic fall animation (wall-clock)
var _fall_prev_offset_y := 12.0  # camera follow_offset.y before the fall dipped it (restored on landing)
var _fall_offset_dipped := false # true once _execute_bridge_fall dipped the camera (so landing knows to restore)
var _bridge_collapse_authority: Dictionary = {}
var _pending_snapshot_camera_state: Dictionary = {}
var _pending_snapshot_control_state: Dictionary = {}
var _collapse_presenter: StagedRigidCollapse3D
var _collapse_visual_generation := 0
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
var _route_beat_character_lanes: Array[Dictionary] = [{}, {}, {}]
var _route_beat_character_windows: Array[Dictionary] = [{}, {}, {}]
var _route_beat_character_window_sources: Array[Dictionary] = [{}, {}, {}]
var _route_flure_interactables: Array = []
var _route_flure_meshes: Array[MeshInstance3D] = []
var _route_flure_enemy_groups: Dictionary = {}
var _route_flure_activation_counts: Array[int] = [0, 0, 0]
var _route_flure_failed_counts: Array[int] = [0, 0, 0]
var _route_flure_window_history: Array[Dictionary] = [{}, {}, {}]
var _route_flure_countdown_labels: Array[Label3D] = []
var _route_causal_links: Dictionary = {}
var _route_beat_lanes: Array[String] = ["", "", ""]
var _route_started_tick := -1.0
var _route_finished_tick := -1.0
var _route_iron_damage_taken := 0.0
var _route_enemy_damage_taken := 0.0
var _route_wasted_flure_windows := 0
var _route_failure_provenance: Array[Dictionary] = []
var _route_controls_shown := false
var _grated_platforms: Node3D
var _grated_platform_signal_marker: Marker3D
var _grated_platform_enemy_markers: Array[Marker3D] = []
var _grated_platform_wall_openings: Array[Marker3D] = []
var _wreckage_gate
var _wreckage_interactable: Area3D
var _wreckage_listeners: Array[Enemy] = []
var _wreckage_armed := false
var _wreckage_clear_in_progress := false
var _wreckage_cleared := false
var _wreckage_solo_attempted := false
var _wreckage_failure_active := false
var _wreckage_alert_target := ""
var _wreckage_rearm_deadline := -1.0
var _elevator_source_committed_counts: Dictionary = {}
var _restoring_elevator_source_authority := false

# Endo-junction presentation. Optional shelter observations and Peris's required
# plant-tending transition live in a reusable SurveyProtocolStoryBeat; this
# controller only binds the authored world objects.
var _junction_interactables: Dictionary = {}
var _junction_plant_interactable: Node
var _junction_plant_mesh: MeshInstance3D
var _junction_plant_material: StandardMaterial3D
var _junction_beat: SurveyProtocolStoryBeat
var _junction_shelter_layout: AuthoredSpatialLayout3D

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
var _iron_hazard_next_tick := -1.0
var _iron_route_risk_learned := false
var _iron_route_risk_cells: Array[Vector2i] = []
var _damage_feedback_labels: Dictionary = {}
var _damage_feedback_tweens: Dictionary = {}
var _damage_feedback_counts: Dictionary = {}
var _iron_contact_warning_shown: Dictionary = {}
const ELEVATOR_RUNTIME_AUTHORITY_VERSION := 5
const ELEVATOR_RUNTIME_AUTHORITY_CONTRACT := "elevator_runtime/v5"
const ELEVATOR_RUNTIME_AUTHORITY_KEY := "runtime:elevator_sequence:hazards_and_wreckage"
var _restoring_elevator_runtime_authority := false
const ELEVATOR_SOURCE_AUTHORITY_VERSION := 1
const ELEVATOR_SOURCE_AUTHORITY_CONTRACT := "elevator_exact_sources/v1"
const ELEVATOR_SOURCE_AUTHORITY_KEY := "runtime:elevator_sequence:exact_sources"
const ELEVATOR_SOURCE_WAKE := "wake_aster"
const ELEVATOR_SOURCE_COLLAPSE := "inspect_collapsed_bridge"
const ELEVATOR_SOURCE_WRECKAGE := "clear_wreckage"
const ELEVATOR_SOURCE_ACTIONS: Array[String] = [
	ELEVATOR_SOURCE_WAKE,
	ELEVATOR_SOURCE_COLLAPSE,
	ELEVATOR_SOURCE_WRECKAGE,
]
const ELEVATOR_SOURCE_POSITION_TOLERANCE := 0.35
const ELEVATOR_SOURCE_HEIGHT_TOLERANCE := 1.25

const SNAPSHOT_WORLD_CHUNKS: Array[String] = [
	"elevator", "bridge", "below", "junction", "gauntlet",
]

# Flure
var _flure_active := false
var _flure_mesh: MeshInstance3D
var _flure_interactable: Flure
var _gauntlet_enemies: Array[Enemy] = []
var _gauntlet_enemy_groups := {0: [], 1: []}
var _gauntlet_enemy_posts: Dictionary = {}
var _gauntlet_dormant_enemy_setups: Array[Dictionary] = []
var _gauntlet_flure_meshes: Array[MeshInstance3D] = []
var _gauntlet_flure_interactables: Array[Flure] = []
var _gauntlet_flure_active := {0: false, 1: false}
var _gauntlet_stage_markers: Dictionary = {}
var _gauntlet_context_markers: Dictionary = {}
var _gauntlet_wasted_flure_windows := 0
var _gauntlet_active_stage := -1
var _gauntlet_stage := 0
var _gauntlet_midpoint_reached := false
var _gauntlet_strategy := ""
var _gauntlet_resetting := false
var _gauntlet_reset_count := 0
var _gauntlet_checkpoint_hp: Dictionary = {}
const GAUNTLET_INTRO_PHASE_ASSEMBLING := "assembling"
const GAUNTLET_INTRO_PHASE_ARMING := "arming"
const GAUNTLET_INTRO_PHASE_READY := "ready"
const GAUNTLET_INTRO_REQUIRED_MEMBERS: Array[String] = ["aster", "peris", "endo"]
const GAUNTLET_INTRO_ARRIVAL_RADIUS := 0.55
const GAUNTLET_INTRO_RETRY_INTERVAL := 0.25
const GAUNTLET_INTRO_POLL_TAG := "elevator_gauntlet_intro_poll"
var _gauntlet_intro_authority: Dictionary = {}
const GAUNTLET_RUN_CONTRACT := "elevator_gauntlet_run/v1"
const GAUNTLET_RUN_VERSION := 3
const GAUNTLET_RUN_PHASE_ACTIVE := "active"
const GAUNTLET_RUN_PHASE_MIDPOINT_ARMING := "midpoint_arming"
const GAUNTLET_RUN_PHASE_RESET_PENDING := "reset_pending"
const GAUNTLET_RUN_PHASE_RESETTING := "resetting"
const GAUNTLET_RUN_PHASE_TRANSITIONING := "transitioning"
const GAUNTLET_WINDOW_READY := "ready"
const GAUNTLET_WINDOW_ACTIVE := "active"
const GAUNTLET_WINDOW_FAILED := "failed_rearming"
const GAUNTLET_POLL_INTERVAL := 0.1
const GAUNTLET_POLL_TAG := "elevator_gauntlet_progress_poll"
const GAUNTLET_RESET_START_TAG := "elevator_gauntlet_reset_start"
const GAUNTLET_RESET_TAG := "elevator_gauntlet_reset_release"
var _gauntlet_run_authority: Dictionary = {}

# Chunk system
@export var start_chunk := ""

# Endo (hidden until junction)
var _endo: Node3D
var _drink_mesh: MeshInstance3D
var _drink_home_parent: Node
var _drink_home_rotation := Vector3.ZERO
var _drink_home_scale := Vector3.ONE
var _drink_item_id := ""
var _endo_handoff_signal_game_state: GameState
var _endo_entry_dialogue_started := false
var _endo_delivery_dialogue_started := false

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
const BRIDGE_LENGTH := 24.0   # a real crossing, long enough that dialogue paces across the walk, not up front
const BRIDGE_END_X := BRIDGE_START_X + BRIDGE_LENGTH
const BRIDGE_COLLAPSE_X := BRIDGE_START_X + BRIDGE_LENGTH * 0.66  # the span gives way ~2/3 across, not after 4 steps
const BRIDGE_PIECES_PER_STREAM_STEP := 4
const BRIDGE_COLLAPSE_PIECES_PER_FRAME := 4
const BRIDGE_COLLAPSE_AUTHORITY_VERSION := 1
const BRIDGE_COLLAPSE_AUTHORITY_ID := "elevator_bridge_collapse"
const BRIDGE_COLLAPSE_PHASE_ARMED := "armed"
const BRIDGE_COLLAPSE_PHASE_FALLING := "falling"
const BRIDGE_COLLAPSE_PHASE_LANDED := "landed"
const BRIDGE_COLLAPSE_PHASE_COMPLETE := "complete"
const BRIDGE_COLLAPSE_ARM_SECONDS := 0.8
const BRIDGE_COLLAPSE_FALL_SECONDS := 1.4 * 1.05
const BRIDGE_COLLAPSE_RECOVERY_SECONDS := 1.0
const BRIDGE_COLLAPSE_CALLBACK_PRIORITY := 10
const BRIDGE_FALL_TRAVERSAL_PREFIX := "elevator_bridge_fall:"
const JUNCTION_SURVEYS_PER_STREAM_STEP := 4
const GAUNTLET_ENEMIES_PER_STREAM_STEP := 2
const BRIDGE_RAIL_Z := 1.4
const BRIDGE_END_LANDING_LENGTH := 4.0
const BRIDGE_BLOCKADE_X := BRIDGE_END_X + BRIDGE_END_LANDING_LENGTH

# The modeled elevator car SHELL (Blender, pixel-grid; floor grate is Geometry-Nodes): paneled walls,
# door opening + frame, ceiling light coffer, corner posts, control housing. Static; the sliding doors,
# emergency light, and floor indicators stay procedural in Godot because they animate.
const ELEVATOR_MODEL := preload("res://resources/models/elevator/elevator_car.glb")
const BRIDGE_LIGHTING_SCENE := preload("res://scenes/tutorial/elevator_bridge_lighting.tscn")
const LOWER_ROUTE_LIGHTING_SCENE := preload("res://scenes/tutorial/elevator_lower_route_lighting.tscn")
const LOWER_ROUTE_BLOCKADE_SCENE := preload("res://scenes/tutorial/elevator_lower_route_blockade.tscn")
const EMP_FACEPLATE_SCENE := preload("res://scenes/tutorial/elevator_emp_faceplate.tscn")
const GRATED_PLATFORMS_SCENE := preload("res://scenes/tutorial/elevator_grated_platforms.tscn")
const WRECKAGE_GATE_SCENE := preload("res://scenes/tutorial/elevator_wreckage_gate.tscn")
const JUNCTION_SHELTER_SCENE := preload("res://scenes/tutorial/elevator_junction_shelter.tscn")
# Collapse debris physics layers (kept off every gameplay layer so debris never touches characters —
# they move on the grid, not via physics). Pieces collide ONLY with their own catch-floor (no inter-
# piece explosions from the initially-touching span).
const DEBRIS_PIECE_LAYER := 1 << 10
const DEBRIS_FLOOR_LAYER := 1 << 11
var _collapse_visual_active := false  # true while wall-clock debris physics is still settling

# Route fork. The course starts beyond the debris footprint and holds its two
# lanes for three readable beats before they converge — a fork only a few
# metres long would be over before its lanes could be read.
const ROUTE_READ_ASTER_POS := Vector3(BRIDGE_COLLAPSE_X + 4.0, BELOW_Y + 0.05, -4.5)
const ROUTE_READ_PERIS_POS := Vector3(BRIDGE_COLLAPSE_X + 4.0, BELOW_Y + 0.05, 4.5)
const FORK_POS := Vector3(BRIDGE_COLLAPSE_X + 9.0, BELOW_Y, 0)
const ROUTE_BEAT_OFFSETS := [14.0, 38.0, 62.0]
const ROUTE_LANE_LENGTH := 78.0
const ENEMY_ROUTE_END := Vector3(FORK_POS.x + ROUTE_LANE_LENGTH, BELOW_Y, -4.0)
const HAZARD_ROUTE_END := Vector3(FORK_POS.x + ROUTE_LANE_LENGTH, BELOW_Y, 4.0)
const ROUTES_CONVERGE := Vector3(FORK_POS.x + ROUTE_LANE_LENGTH + 8.0, BELOW_Y, 0)
## Nine seconds is long enough for both cooperative paths in a staged crossing beyond the linked
## pack's return envelope, but
## shorter than a whole-beat catch-up. Staging, RUN, and crossover planning therefore change the result.
const ROUTE_FLURE_DURATION := 9.0
const ROUTE_BEAT_CLEARANCE_OFFSET := 12.0
const ROUTE_BEAT_RALLY_OFFSET := 13.0
const ROUTE_REQUIRED_READS := 0
const ROUTE_BEAT_COUNT := 3
const ROUTE_CROSSOVER_X_OFFSETS := [26.0, 50.0]
const ROUTE_CROSSOVER_WIDTH := 3.5
const GRATED_PLATFORM_ROUTE_BEAT := 1
const GRATED_PLATFORM_POS := Vector3(FORK_POS.x + 39.0, BELOW_Y, -10.0)
const WRECKAGE_GATE_POS := Vector3(ROUTES_CONVERGE.x + 5.0, BELOW_Y, 0.0)
const WRECKAGE_CLEAR_SECONDS := 1.15
const LOWER_ROUTE_WEST_X := BRIDGE_COLLAPSE_X - 5.0
const ROUTE_SAFE_EDGE_Z := 6.45
const ROUTE_OUTER_WALL_Z := 7.7
const ROUTE_OUTER_WALL_HALF_THICKNESS := 0.15
# The safe edge runs close to the +Z wall. Keep the camera's maximum horizontal
# offset inside that wall at every supported zoom/yaw, then gain overview with
# height rather than by backing through the geometry.
const LOWER_ROUTE_CAMERA_OFFSET := Vector3(0.0, 5.5, 0.65)
const LOWER_ROUTE_CAMERA_MAX_ZOOM := 1.4

# Endo junction and shelter
const JUNCTION_POS := Vector3(ROUTES_CONVERGE.x + 10.0, BELOW_Y, 0)
const SHELTER_SIZE := Vector3(9, 3, 7)
const JUNCTION_REQUIRED_INSPECTIONS := 0
const ENDO_DRINK_CONTRACT := "elevator_junction_water/v1"
const ENDO_DRINK_PICKUP_PHASE_ID := &"elevator_junction_water_pickup"
const ENDO_DRINK_PICKUP_PHASE := &"collecting"
const ENDO_DRINK_PICKED_PHASE := &"collected"
const ENDO_DRINK_PICKUP_SECONDS := 1.5
const ENDO_DRINK_PICKUP_RADIUS := 1.1
const ENDO_DRINK_DELIVERY_RADIUS := 0.45
const ENDO_ENTRY_AUTHORITY_VERSION := 1
const ENDO_ENTRY_AUTHORITY_KEY := "runtime:elevator_sequence:endo_entry"
const ENDO_ENTRY_CONTRACT := "elevator_endo_entry/v1"
const ENDO_ENTRY_PHASE_APPROACHING := "approaching"
const ENDO_ENTRY_PHASE_INTERRUPTED := "interrupted"
const ENDO_ENTRY_PHASE_ARRIVED := "arrived"
const ENDO_ENTRY_RADIUS := 0.2
const JUNCTION_REST_AUTHORITY_VERSION := 1
const JUNCTION_REST_AUTHORITY_KEY := "runtime:elevator_sequence:junction_party_rest"
const JUNCTION_REST_CONTRACT := "elevator_junction_party_rest/v1"
const JUNCTION_REST_PHASE_IDLE := "idle"
const JUNCTION_REST_PHASE_COMMITTING := "committing"
const JUNCTION_REST_PHASE_NIGHT_WATCH := "night_watch"
const JUNCTION_REST_PHASE_COMPLETE := "complete"
const JUNCTION_REST_PARTY: Array[String] = ["aster", "peris", "endo"]
const JUNCTION_SHELTER_CENTER := JUNCTION_POS + Vector3(0.8, 0.0, 0.0)
const JUNCTION_SHELTER_HALF_SIZE := Vector2(4.5, 3.5)
const JUNCTION_REST_NIGHT_TIME := 0.55
const JUNCTION_REST_WATCH_SECONDS := 8.0
const JUNCTION_REST_COMMIT_TAG := "elevator_junction_rest_commit"
const JUNCTION_REST_DAWN_TAG := "elevator_junction_rest_dawn"
const JUNCTION_REST_FLICKER_TAG := "elevator_junction_rest_flicker"
# Aster's schematics cover the main facility out through Endo's junction (and its
# shelter); past this X the corridors are maintenance with no blueprints, so the
# data overlay goes dark.
const MAIN_FACILITY_MAX_X := JUNCTION_POS.x + SHELTER_SIZE.x

# Flure gauntlet: two packs, two lure stations, and a real midpoint refuge.
const GAUNTLET_POS := Vector3(JUNCTION_POS.x + 28.0, BELOW_Y, 0)
const GAUNTLET_MIDPOINT := Vector3(GAUNTLET_POS.x + 28.0, BELOW_Y, 0)
const FLURE_POS := Vector3(GAUNTLET_POS.x - 3.0, BELOW_Y + 0.3, 4.0)
const GAUNTLET_FLURE_2_POS := Vector3(GAUNTLET_MIDPOINT.x + 4.0, BELOW_Y + 0.3, -4.0)
## At activation, an unstaged partner at the midpoint needs 15.2s to clear the exit while a staged
## pair needs about 13.7s. The 14s window rewards staging or RUN. Measure only post-activation
## movement; the approach to the Flure is not on the clock.
const GAUNTLET_EXIT := Vector3(GAUNTLET_POS.x + 68.0, BELOW_Y, 0)
const FLURE_DURATION := 14.0

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
				_below_step_grated_platforms_layout.bind(parent),
				_below_step_grated_platforms_navigation.bind(parent),
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
				_below_step_wreckage_gate_layout.bind(parent),
				_below_step_wreckage_gate_interaction.bind(parent),
				_below_step_wreckage_listener.bind(parent, "ListenerSpawnA", 0, true),
				_below_step_wreckage_listener.bind(parent, "ListenerSpawnB", 1, true),
				_apply_chunk_tiles.bind(parent, "deck_metal", "facility_metal"),
				_decorate_below_chunk.bind(parent),
				_below_chunk_occlusion_step.bind(parent),
			]
		"junction":
			var junction_steps: Array = [
				_junction_step_prepare.bind(parent),
				_junction_step_shelter_layout.bind(parent),
			]
			var survey_count := _junction_survey_specs().size()
			for first in range(0, survey_count, JUNCTION_SURVEYS_PER_STREAM_STEP):
				junction_steps.append(_junction_step_survey_batch.bind(
					parent, first, mini(JUNCTION_SURVEYS_PER_STREAM_STEP, survey_count - first)))
			junction_steps.append(_junction_step_plant.bind(parent))
			junction_steps.append(_apply_chunk_tiles.bind(parent, "sand", "rock"))
			junction_steps.append(_chunk_occlusion_step.bind(parent))
			return junction_steps
		"gauntlet":
			var gauntlet_steps: Array = [
				_gauntlet_step_prepare.bind(parent),
				_gauntlet_step_floor.bind(parent),
				_gauntlet_step_walls.bind(parent),
				_gauntlet_step_flure_1.bind(parent),
				_gauntlet_step_flure_2.bind(parent),
				_gauntlet_step_refuge.bind(parent),
			]
			var gauntlet_enemy_count := _gauntlet_enemy_specs().size()
			for first in range(0, gauntlet_enemy_count, GAUNTLET_ENEMIES_PER_STREAM_STEP):
				gauntlet_steps.append(_gauntlet_step_enemy_batch.bind(
					parent, first, mini(GAUNTLET_ENEMIES_PER_STREAM_STEP, gauntlet_enemy_count - first)))
			gauntlet_steps.append(_gauntlet_step_light.bind(parent))
			gauntlet_steps.append(_apply_chunk_tiles.bind(parent, "deck_metal", "facility_metal"))
			gauntlet_steps.append(_decorate_gauntlet_chunk.bind(parent))
			gauntlet_steps.append(_chunk_occlusion_step.bind(parent))
			return gauntlet_steps
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
	if not Engine.is_editor_hint() and start_chunk != "gauntlet":
		_prewarm_detached_scene(&"elevator_grated_platforms", GRATED_PLATFORMS_SCENE)
		_prewarm_detached_scene(&"elevator_junction_shelter", JUNCTION_SHELTER_SCENE)
	_build_grid()
	_load_chunk("elevator")
	# The corridor shell and click-collision slab ship with the elevator's initial load. The repeated deck
	# pieces continue in four-piece slices during the stationary opening instead of arriving in one spike.
	if start_chunk == "" or start_chunk == "bridge":
		stream_chunk("bridge")
		_advance_chunk_streams()
		_advance_chunk_streams()
	# The shelter GLB contains many tiny named meshes. Its unavoidable tree-entry work joins
	# scene loading; the root then stays paused, hidden, and physics-inert until the fall gives
	# the remaining Junction detail steps a long quiet streaming window.
	if start_chunk != "gauntlet":
		prime_chunk_stream("junction", 2)

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

	var peris_started := PerformanceTrace.begin()
	_player = _create_player_character("Peris", Color(0.8, 0.5, 0.35))
	_player.position = PERIS_START
	chars.add_child(_player)
	PerformanceTrace.end(&"draw", &"elevator.characters.peris", peris_started, name, 1)
	_peris_node = _player

	var aster_started := PerformanceTrace.begin()
	_aster_node = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_aster_node.position = ASTER_POS + Vector3(0, 0.5, 0)
	_aster_node.rotation_degrees.z = 30.0
	chars.add_child(_aster_node)
	PerformanceTrace.end(&"draw", &"elevator.characters.aster", aster_started, name, 1)
	# The elevator camera runs closer than the simulation cameras. Keep identity
	# tags readable without letting them cover the route line or fork geometry.
	for character: CharacterBody3D in [_player, _aster_node]:
		var identity_label := character.get_node_or_null("Label3D") as Label3D
		if identity_label != null:
			identity_label.pixel_size = 0.006

	# Escort units
	var npcs_started := PerformanceTrace.begin()
	_escort_1 = _create_npc("EU-1", Color(0.7, 0.7, 0.75))
	_escort_1.emp_compatible = true
	_escort_1.position = ESCORT_1_POS
	chars.add_child(_escort_1)

	_escort_2 = _create_npc("EU-2", Color(0.7, 0.7, 0.75))
	_escort_2.emp_compatible = true
	_escort_2.position = ESCORT_2_POS
	chars.add_child(_escort_2)

	# Endo becomes a full party member before the gauntlet. Build the same
	# controllable character presenter Act 1 expects instead of leaving him as a
	# scripted NPC that silently drops out of selection after his entrance scene.
	_endo = _create_player_character("Endo", Color(0.4, 0.67, 0.53))
	_endo.position = Vector3(JUNCTION_POS.x + 3, BELOW_Y + 0.5, -2)
	_endo.visible = false
	# The authored body is only a presenter until the entrance command commits. A
	# hidden live NPC would still run process/input code before Endo exists in the
	# simulation and could leak a not-yet-joined visibility source.
	_endo.process_mode = Node.PROCESS_MODE_DISABLED
	chars.add_child(_endo)
	if not Engine.is_editor_hint() and "grid_world" in _endo:
		_endo.set("grid_world", _grid)
	PerformanceTrace.end(&"draw", &"elevator.characters.npcs", npcs_started, name, 3)
	var emp_visuals_started := PerformanceTrace.begin()
	_build_emp_visuals()
	PerformanceTrace.end(&"draw", &"elevator.characters.emp_visuals", emp_visuals_started, name, 1)

	if not Engine.is_editor_hint():
		_player.grid_world = _grid  # player clicks route on the grid (cell snapping, per-deck footprint)
		var camera_started := PerformanceTrace.begin()
		_setup_game_camera(_player, Vector3(0, 3.5, 2.5))
		PerformanceTrace.end(&"draw", &"elevator.characters.camera", camera_started, name, 1)
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
	# The authored shelter floor, not its light or dialogue beat, owns sanctuary/rest eligibility.
	# The region is scene configuration (like a grid footprint), so it exists before either a live
	# command or a deserialized snapshot asks GameState to validate a party rest.
	_game_state.add_shelter_region(
		Vector2(
			JUNCTION_SHELTER_CENTER.x - JUNCTION_SHELTER_HALF_SIZE.x,
			JUNCTION_SHELTER_CENTER.z - JUNCTION_SHELTER_HALF_SIZE.y),
		Vector2(
			JUNCTION_SHELTER_CENTER.x + JUNCTION_SHELTER_HALF_SIZE.x,
			JUNCTION_SHELTER_CENTER.z + JUNCTION_SHELTER_HALF_SIZE.y)
	)
	# Party HP is GameState's (the single source). A positive HP is also the AI's "alive" flag — without
	# it, enemy detection treats the party as downed (hp<=0) and the ecology never gives chase.
	var party_stats := {
		"hp": PARTY_MAX_HP,
		"stamina": GameState.STAMINA_MAX,
		"atp": GameState.ATP_MAX_PIPS,
	}
	_register_gs_character("peris", _peris_node, 2.5, party_stats)
	_register_gs_character("aster", _aster_node, 2.5, party_stats)
	# TutorialSequence binds only the character stored in `_player` (Peris at
	# registration time). Elevator later promotes Aster to the active controller,
	# so his controller must also observe streamed interaction targets.
	if _aster_node.has_method("bind_interaction_root"):
		_aster_node.bind_interaction_root(self)
	_register_gs_character("eu1", _escort_1, 2.0)
	_register_gs_character("eu2", _escort_2, 2.0)
	if not _game_state.character_arrived.is_connected(_on_emp_guard_arrived):
		_game_state.character_arrived.connect(_on_emp_guard_arrived)
	_configure_endo_handoff_presenter()
	_wire_endo_handoff_signals()
	_aster_node.set_move_enabled(false)
	_initialize_elevator_source_authority()
	# Reveal the level around the active character (data-layer position) now that the GameState is live.
	if _occlusion_mgr != null:
		_occlusion_mgr.set_watch(_game_state, _active_character)


## Endo is deliberately absent from GameState until the junction entry beat. The node can still be
## prepared as a presenter now: a later snapshot may deserialize Endo directly into the roster, and
## that saved body must have a scheduler and a stable id without registering construction defaults.
func _configure_endo_handoff_presenter() -> void:
	if not is_instance_valid(_endo) or _game_state == null:
		return
	_endo.set("game_state", _game_state)
	_endo.set("char_id", "endo")
	_game_state_character_nodes["endo"] = _endo
	if _endo.has_method("set_scheduler"):
		_endo.call("set_scheduler", _scheduler)


func _wire_endo_handoff_signals() -> void:
	if _endo_handoff_signal_game_state != null \
			and _endo_handoff_signal_game_state != _game_state:
		if _endo_handoff_signal_game_state.character_arrived.is_connected(
				_on_endo_story_character_arrived):
			_endo_handoff_signal_game_state.character_arrived.disconnect(
				_on_endo_story_character_arrived)
		if _endo_handoff_signal_game_state.movement_started.is_connected(
				_on_endo_handoff_movement_started):
			_endo_handoff_signal_game_state.movement_started.disconnect(
				_on_endo_handoff_movement_started)
		if _endo_handoff_signal_game_state.mechanism_phase_completed.is_connected(
				_on_endo_handoff_phase_completed):
			_endo_handoff_signal_game_state.mechanism_phase_completed.disconnect(
				_on_endo_handoff_phase_completed)
		if _endo_handoff_signal_game_state.stat_changed.is_connected(
				_on_endo_handoff_stat_changed):
			_endo_handoff_signal_game_state.stat_changed.disconnect(
				_on_endo_handoff_stat_changed)
		if _endo_handoff_signal_game_state.character_downed.is_connected(
				_on_endo_story_character_downed):
			_endo_handoff_signal_game_state.character_downed.disconnect(
				_on_endo_story_character_downed)
		if _endo_handoff_signal_game_state.character_restored.is_connected(
				_on_endo_story_character_restored):
			_endo_handoff_signal_game_state.character_restored.disconnect(
				_on_endo_story_character_restored)
	_endo_handoff_signal_game_state = _game_state
	if _game_state == null:
		return
	if not _game_state.character_arrived.is_connected(_on_endo_story_character_arrived):
		_game_state.character_arrived.connect(_on_endo_story_character_arrived)
	if not _game_state.movement_started.is_connected(_on_endo_handoff_movement_started):
		_game_state.movement_started.connect(_on_endo_handoff_movement_started)
	if not _game_state.mechanism_phase_completed.is_connected(_on_endo_handoff_phase_completed):
		_game_state.mechanism_phase_completed.connect(_on_endo_handoff_phase_completed)
	if not _game_state.stat_changed.is_connected(_on_endo_handoff_stat_changed):
		_game_state.stat_changed.connect(_on_endo_handoff_stat_changed)
	if not _game_state.character_downed.is_connected(_on_endo_story_character_downed):
		_game_state.character_downed.connect(_on_endo_story_character_downed)
	if not _game_state.character_restored.is_connected(_on_endo_story_character_restored):
		_game_state.character_restored.connect(_on_endo_story_character_restored)

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
	if _camera == null:
		return
	if _camera.has_method("apply_follow_profile"):
		_camera.apply_follow_profile({
			"follow_offset": LOWER_ROUTE_CAMERA_OFFSET,
			"min_zoom": 0.75,
			"max_zoom": LOWER_ROUTE_CAMERA_MAX_ZOOM,
			"initial_zoom": 1.0,
		}, true)
	if not _camera.has_method("set_look_bounds"):
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
	# an inclusive world rectangle would admit the cells centred on/outside the rails (z=±1.5/2.5),
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
	_grid.disallow_cell_region_on_level(min_cell, max_cell, level)


## Gameplay topology changes at the physical landing endpoint, never when the cosmetic debris starts.
## Unlike queue_free(), collision-layer and allow-set changes are reversible for same-instance rollback.
func _commit_bridge_collapse_topology(committed: bool) -> void:
	if _grid != null:
		var min_cell := _grid.world_to_grid(
			Vector3(BRIDGE_START_X - 1.0, 0.0, -0.5))
		var max_cell := _grid.world_to_grid(
			Vector3(BRIDGE_END_X, 0.0, 0.5))
		if committed:
			_grid.disallow_cell_region_on_level(min_cell, max_cell, LEVEL_UPPER)
		else:
			_grid.allow_cell_region_on_level(min_cell, max_cell, LEVEL_UPPER)
	var bridge_chunk: Node3D = _chunks.get("bridge") as Node3D
	var bridge_floor: Node3D = bridge_chunk.find_child("BridgeFloor", false, false) \
		if bridge_chunk != null else null
	if bridge_floor == null:
		return
	for collision_name in [
			"BridgeDeckCollision", "BridgeRailCollisionL", "BridgeRailCollisionR"]:
		var body := bridge_floor.get_node_or_null(collision_name) as CollisionObject3D
		if body != null:
			body.collision_layer = 0 if committed else 1
	var model := bridge_floor.find_child("BridgeModel", false, false) as Node3D
	if model != null:
		model.visible = not committed or _collapse_visual_active

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
	_hud.run_toggled.connect(_on_route_run_toggled)
	_hud.routing_toggled.connect(_on_route_mode_toggled)
	var emp_binding := AbilityData.binding("emp")
	# The key hint comes from Aster's live direct ability slot, never a baked letter, so a rebind / controller
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


func _configure_story_beats() -> void:
	_junction_beat = SurveyProtocolStoryBeat.new(&"junction_arrive")
	_junction_beat.configure(
		JUNCTION_REQUIRED_INSPECTIONS,
		[],
		[],
		[],
		{},
		{},
		true
	)
	if not _story_beat_runner.register_beat(_junction_beat):
		push_error("Could not register the reusable Junction story beat.")

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
	_publish_elevator_runtime_authority()

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
	if overlay_id == "peris" and enabled and _current_step in ["route_read_circuit", "route_choice"]:
		_resolve_peris_overlay_route_read()
	_publish_elevator_runtime_authority()

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
				_start_junction_focus()
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
	_schedule_portable_method(1.0, _start_consciousness_fragments, "fragments")
	# Finish the bridge and prewarm the lower route across the long stationary opening. Lower-deck enemies are
	# registered and activated only on reveal, so hidden construction adds no patrol or detection scheduler traffic.
	stream_chunk("bridge")
	# Tree-enter the authored grated-platform subtree before the first rendered frame, while the
	# scene is already loading behind black. The remaining lower route continues one global-budget
	# slice at a time during the stationary opening.
	prime_chunk_stream("below", 3)
	resume_chunk_stream("below")


## Chunk roots are presenters, but they create the Enemy/Interactable presenters that attach to saved
## GameState records. Rebuild the snapshot's topology *before* GameState.deserialize(), so construction
## defaults are replaced by the snapshot rather than overwriting it. This also makes a same-instance
## rollback work after the future timeline already unloaded the saved level chunk.
func apply_save_snapshot(data: Dictionary) -> void:
	var presenter_data: Dictionary = data.get("elevator_presenters", {}) as Dictionary
	_pending_snapshot_camera_state = (presenter_data.get(
		"camera", {}) as Dictionary).duplicate(true)
	_pending_snapshot_control_state = (presenter_data.get(
		"controls", {}) as Dictionary).duplicate(true) \
		if int(presenter_data.get("version", 0)) >= 3 else {}
	_prepare_chunks_for_save_snapshot(data)
	super.apply_save_snapshot(data)


func build_save_snapshot() -> Dictionary:
	# Fold any source publication that landed before its listener signal into the same observation.
	# This writes only route history; active phase/deadline remain exclusively in each Flure record.
	for route_index in range(ROUTE_BEAT_COUNT):
		_reconcile_route_flure_history_from_source(route_index)
		_account_closed_route_flure_window(route_index)
	_publish_elevator_runtime_authority()
	var snapshot := super.build_save_snapshot()
	snapshot["elevator_presenters"] = {
		"version": 3,
		"active_chunks": _active_snapshot_chunk_ids(),
		"camera": _capture_portable_elevator_camera_state(),
		"controls": _capture_portable_elevator_control_state(),
	}
	return snapshot


func _prepare_chunks_for_save_snapshot(data: Dictionary) -> void:
	var saved_step := str(data.get("current_step", ""))
	var required := _saved_active_chunks(data, saved_step)
	# Retire presenters from the discarded future first. Their current GameState registrations are
	# irrelevant because the exact serialized roster/world state replaces them immediately afterward.
	for chunk_name in SNAPSHOT_WORLD_CHUNKS:
		if not required.has(chunk_name) and _chunks.has(chunk_name):
			_unload_chunk(chunk_name)
	for chunk_name in required:
		# A completed prewarm root can still be hidden and process-disabled after its
		# stream entry has been retired. Saved membership describes active topology,
		# so reconstruct through the reveal seam rather than accepting that inert root.
		reveal_chunk(chunk_name)
	# These story sources are created only for their active beat during ordinary play. Recreate
	# them before GameState.deserialize so the saved registry replaces construction defaults and
	# a fresh presenter cannot erase an accepted-before-owner receipt.
	if saved_step == "approach_aster":
		_ensure_aster_wake_interactable()
	elif saved_step in ["climb_attempt", "climb_inspected"]:
		_ensure_climb_interactable()


func _saved_active_chunks(data: Dictionary, saved_step: String) -> Array[String]:
	var result: Array[String] = []
	var presenter_data: Variant = data.get("elevator_presenters", {})
	if presenter_data is Dictionary and int(presenter_data.get("version", 0)) in [1, 2, 3]:
		for chunk_name_v in presenter_data.get("active_chunks", []):
			var chunk_name := str(chunk_name_v)
			if chunk_name in SNAPSHOT_WORLD_CHUNKS and not result.has(chunk_name):
				result.append(chunk_name)
	if not result.is_empty():
		return result
	# Backward-compatible topology for saves made before chunk membership was recorded.
	if saved_step in [
			"consciousness_fragments", "fade_in", "waking", "approach_aster", "wake_aster",
			"conversation", "system_restored", "units_activate", "emp_tutorial",
			"emp_tutorial_2", "doors_unlocked", "doors_open", "rally_tutorial"]:
		return ["elevator"]
	if saved_step in ["corridor", "bridge", "bridge_collapse"]:
		return ["elevator", "bridge", "below"]
	if saved_step in [
		"fallen", "climb_attempt", "climb_inspected", "route_read_circuit", "route_choice",
	]:
		return ["below"]
	if saved_step in [
			"junction_arrive", "endo_enters", "endo_shelter", "endo_delivery",
			"endo_delivered", "night_watch", "dawn", "morning"]:
		return ["junction"]
	if saved_step in ["gauntlet", "complete"]:
		return ["gauntlet"]
	return []


func _active_snapshot_chunk_ids() -> Array[String]:
	var active: Array[String] = []
	for chunk_name in SNAPSHOT_WORLD_CHUNKS:
		var chunk: Node3D = _chunks.get(chunk_name) as Node3D
		if chunk == null or not is_instance_valid(chunk) or chunk.is_queued_for_deletion():
			continue
		if chunk.visible and chunk.process_mode != Node.PROCESS_MODE_DISABLED:
			active.append(chunk_name)
	return active


func _capture_portable_elevator_camera_state() -> Dictionary:
	if _camera == null:
		return {}
	return {
		"follow_offset": GameEvent.v3_to_arr(_camera.follow_offset),
		"pan_offset": GameEvent.v3_to_arr(_camera.get("_pan_offset") as Vector3),
		"view_yaw": float(_camera.get("_view_yaw")),
		"view_zoom": float(_camera.get("_view_zoom")),
		"zoom_min": float(_camera.get("_zoom_min")),
		"zoom_max": float(_camera.get("_zoom_max")),
		"look_bounds_active": bool(_camera.get("_look_bounds_active")),
		"look_bounds_min": GameEvent.v3_to_arr(_camera.get("_look_bounds_min") as Vector3),
		"look_bounds_max": GameEvent.v3_to_arr(_camera.get("_look_bounds_max") as Vector3),
	}


func _capture_portable_elevator_control_state() -> Dictionary:
	return {
		"version": 1,
		"active_character": _active_character,
		"selected_character_ids": _selected_character_ids.duplicate(),
		"multi_select": _hud != null and bool(_hud.get("_multi_select")),
	}


func _restore_portable_elevator_control_state() -> void:
	if _hud == null or _game_state == null:
		return
	var available := _available_party_control_ids()
	var game_party: Array[String] = []
	for raw_id in _game_state.get_party():
		var member_id := str(raw_id)
		if available.has(member_id) and not game_party.has(member_id):
			game_party.append(member_id)
	if game_party.is_empty():
		var fallback := _active_character if available.has(_active_character) \
			else (available[0] if not available.is_empty() else "")
		if fallback.is_empty():
			_pending_snapshot_control_state.clear()
			return
		game_party = [fallback]
	var active := game_party[0]
	var selected: Array[String] = game_party.duplicate()
	var multi_select := game_party.size() > 1
	# Presenter metadata may choose which saved party member leads, but it may
	# never contradict the serialized GameState party or overwrite it.
	if int(_pending_snapshot_control_state.get("version", 0)) == 1:
		var saved_active := str(_pending_snapshot_control_state.get(
			"active_character", ""))
		var saved_selected_v: Variant = _pending_snapshot_control_state.get(
			"selected_character_ids", null)
		var saved_selected: Array[String] = []
		if saved_selected_v is Array:
			for raw_id in saved_selected_v as Array:
				var member_id := str(raw_id)
				if available.has(member_id) and not saved_selected.has(member_id):
					saved_selected.append(member_id)
		var saved_multi := bool(_pending_snapshot_control_state.get(
			"multi_select", false))
		if saved_selected == game_party and game_party.has(saved_active) \
				and saved_multi == (game_party.size() > 1):
			active = saved_active
			selected = saved_selected
			multi_select = saved_multi
	_active_character = active
	_selected_character_ids = selected
	_player = _elevator_party_node(active)
	if _camera != null:
		_camera.target = _player
	if _occlusion_mgr != null:
		_occlusion_mgr.set_watch(_game_state, active)
	_suppress_hud_character_signal = true
	_hud.set_multi_select_enabled(multi_select)
	_hud.set_active_portrait(active, multi_select)
	_hud.set_selected_portraits(selected)
	_suppress_hud_character_signal = false
	_restore_character_control_input_gate()
	if _route_controls_shown:
		_hud.set_run_mode(_game_state.is_running(active))
	_pending_snapshot_control_state.clear()


## Selection metadata is presentation derived from the already-deserialized party. Restore its input
## gates without issuing command_stop through Player.set_move_enabled(): saved movement plans must
## remain the same physical plans at the same absolute deadlines.
func _restore_character_control_input_gate() -> void:
	var group_control := _hud != null and bool(_hud.get("_multi_select")) \
		and _selected_character_ids.size() > 1
	var nodes: Dictionary = _available_party_control_nodes()
	for character_id in nodes:
		var character_node := nodes.get(character_id) as Node3D
		if character_node == null or not is_instance_valid(character_node):
			continue
		var is_active := str(character_id) == _active_character
		if character_node.has_method("restore_move_input_enabled"):
			character_node.call("restore_move_input_enabled", is_active)
		if "group_move" in character_node:
			character_node.set("group_move", group_control and is_active)


func _restore_portable_elevator_camera_state() -> void:
	if _camera == null or _pending_snapshot_camera_state.is_empty():
		return
	var saved := _pending_snapshot_camera_state
	_camera.follow_offset = _bridge_context_position(
		saved, "follow_offset", _camera.follow_offset)
	_camera.set("_pan_offset", _bridge_context_position(
		saved, "pan_offset", Vector3.ZERO))
	_camera.set("_view_yaw", float(saved.get("view_yaw", _camera.get("_view_yaw"))))
	_camera.set("_view_zoom", float(saved.get("view_zoom", _camera.get("_view_zoom"))))
	_camera.set("_zoom_min", float(saved.get("zoom_min", _camera.get("_zoom_min"))))
	_camera.set("_zoom_max", float(saved.get("zoom_max", _camera.get("_zoom_max"))))
	if bool(saved.get("look_bounds_active", false)):
		_camera.set_look_bounds(
			_bridge_context_position(saved, "look_bounds_min", Vector3.ZERO),
			_bridge_context_position(saved, "look_bounds_max", Vector3.ZERO))
	else:
		_camera.clear_look_bounds()
	_camera.call("_update_immediate")

func _compute_speed() -> float:
	return 10.0 if Input.is_action_pressed("fast_forward") else 1.0

func _on_process(delta: float, spd: float) -> void:
	_sync_endo_drink_presenter()
	_sync_endo_entry_interruption()
	# The collapse presenter consumes unscaled presentation time in bounded batches. It is
	# explicitly paused with gameplay, so headless advancement and live frames share one path.
	if _collapse_presenter != null and is_instance_valid(_collapse_presenter):
		_collapse_presenter.advance_visual_time(delta)
	_sync_bridge_fall_presentation_from_authority()
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
		if is_instance_valid(enemy) and enemy.process_mode != Node.PROCESS_MODE_DISABLED and enemy.is_alive():
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
		# failing span.  Triggering on the lead unit alone would teleport the
		# trailing unit straight down from the bridge mouth into the dormant
		# huddle, where it could be killed off-screen.
		if _party_tail_x() > BRIDGE_COLLAPSE_X:
			_tutorial_prompt.hide_prompt()
			_player.set_move_enabled(false)
			_start_bridge_collapse()

	# Route convergence reveals the last causal gate instead of unloading the level under a trailing
	# partner. The wreckage itself decides whether the party distributes the load or makes enough
	# noise to wake the nearby fauna.
	if _current_step == "route_choice":
		_update_route_course_progress()
		_update_route_flure_feedback()

	# Gauntlet formation, midpoint, and exit consequences are sampled on the
	# gameplay scheduler. Render cadence may project the scene, but cannot grant
	# progress or change whether a save lands before/after a threshold.

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

func _both_conscious_party_past_x(threshold: float) -> bool:
	for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		if not _game_state.characters.has(member_id) or _game_state.is_downed(member_id) \
				or _game_state.get_position(member_id).x <= threshold:
			return false
	return true

func _update_route_course_progress() -> void:
	var progress_changed := false
	for i in range(ROUTE_BEAT_COUNT):
		var threshold := FORK_POS.x + float(ROUTE_BEAT_OFFSETS[i]) + ROUTE_BEAT_CLEARANCE_OFFSET
		if _route_beats_crossed[i]:
			continue
		for member_id in ["aster", "peris"]:
			if _route_beat_character_lanes[i].has(member_id) \
					or not _game_state.characters.has(member_id) \
					or _game_state.is_downed(member_id) \
					or _game_state.get_position(member_id).x <= threshold:
				continue
			var crossing_z := _game_state.get_position(member_id).z
			_route_beat_character_lanes[i][member_id] = (
				"flure" if crossing_z < -0.75 else "iron" if crossing_z > 0.75 else "mixed"
			)
			var source_start := _route_flure_live_window_start(i)
			_route_beat_character_windows[i][member_id] = source_start >= 0.0
			_route_beat_character_window_sources[i][member_id] = source_start
			progress_changed = true
		if not (_route_beat_character_lanes[i].has("aster") \
				and _route_beat_character_lanes[i].has("peris")):
			continue
		_route_beats_crossed[i] = true
		var aster_lane := str(_route_beat_character_lanes[i]["aster"])
		var peris_lane := str(_route_beat_character_lanes[i]["peris"])
		_route_beat_lanes[i] = aster_lane if aster_lane == peris_lane and aster_lane in ["flure", "iron"] \
			else "mixed"
		# A window counts as used only when both bodies crossed during the same source-owned Flure
		# activation. Two individually-live crossings from different activations are not clean mastery.
		var aster_window := float(
			_route_beat_character_window_sources[i].get("aster", -1.0))
		var peris_window := float(
			_route_beat_character_window_sources[i].get("peris", -1.0))
		if aster_window >= 0.0 and is_equal_approx(aster_window, peris_window):
			_mark_route_flure_window_used(i, aster_window)
		progress_changed = true
	if _route_beats_crossed.count(true) == ROUTE_BEAT_COUNT:
		var flure_beats := _route_beat_lanes.count("flure")
		var iron_beats := _route_beat_lanes.count("iron")
		var resolved_lane := "flure" if flure_beats == ROUTE_BEAT_COUNT else (
			"iron" if iron_beats == ROUTE_BEAT_COUNT else "hybrid"
		)
		if _route_lane != resolved_lane:
			_route_lane = resolved_lane
			progress_changed = true
	if progress_changed:
		_publish_elevator_runtime_authority()

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
	elif event.is_action_pressed("route") and _current_step == "hack_tutorial":
		_switch_character()

func _on_route_run_toggled(running: bool) -> void:
	if _game_state == null or _current_step not in ["route_choice", "gauntlet"]:
		return
	var members := _sanitize_character_selection(_selected_character_ids)
	if members.is_empty():
		members = [_active_character]
	for member_id in members:
		_game_state.set_running(member_id, running)

func _on_route_mode_toggled(mode: String) -> void:
	if _game_state != null:
		_game_state.set_route_mode(mode == "safe")

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
## presentation (Tween + frame-sliced rigid-body settling). Keep those two clocks observationally atomic: a
## paused player must never watch the bridge retire while the authoritative landing is frozen.
func _set_collapse_visual_paused(paused: bool) -> void:
	_collapse_visual_paused = paused
	if _fall_tween != null and _fall_tween.is_valid():
		if paused:
			_fall_tween.pause()
		else:
			_fall_tween.play()
	if _collapse_presenter != null and is_instance_valid(_collapse_presenter):
		_collapse_presenter.set_visual_paused(paused)

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
	var elevator_emp := AbilityData.get_ability("elevator.emp")
	var disable_duration := float(elevator_emp.get("duration", 30.0))
	if disable_duration <= 0.0:
		disable_duration = 30.0
	var cooldown := float(elevator_emp.get("cooldown", 10.0))
	if cooldown <= 0.0:
		cooldown = 10.0
	var result: Dictionary = CanonicalCharacterAbilityScript.execute(
		_game_state, "emp", "aster", Vector3.ZERO,
		{"world_root": self, "duration": disable_duration})
	if not bool(result.get("accepted", false)):
		_hud.show_message("Aster cannot fire EMP: %s." % str(result.get("reason", "unavailable")), 1.8)
		return
	_hud.set_portrait_stat("aster", "sta", _game_state.get_stat("aster", "stamina"))
	_emp_cooldown_end = _scheduler.get_current_tick() + cooldown
	_hud.set_ability_state("emp", "cooldown", cooldown)
	_camera.shake(0.3, 4.0)
	_play_emp_discharge_animation()
	_unit_1_stunned = true
	_unit_2_stunned = true
	_emp_count = int(result.get("affected_count", 0))
	_reboot_active = true
	_tutorial_prompt.hide_prompt()
	# Reboot and hack tutorial on the scheduler
	_scheduler.schedule_after(disable_duration, _on_reboot, "reboot")
	_schedule_portable_method(1.5, _start_doors_unlocked, "doors_unlock")

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
	if not _available_party_control_ids().has(id):
		return
	var selected_node := _elevator_party_node(id)
	if selected_node == null:
		return
	_player = selected_node
	_camera.target = selected_node
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
	if _route_controls_shown:
		_hud.set_run_mode(_game_state.is_running(id))

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
	var available := _available_party_control_ids()
	for raw_id in selected_ids:
		var id := str(raw_id)
		if not available.has(id):
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
	var nodes := _available_party_control_nodes()
	var selected := _sanitize_character_selection(_selected_character_ids)
	# The gauntlet briefing owns a three-body formation. Portrait input may
	# change the eventual active member, but it cannot release one body while the
	# accepted formation operation is still assembling.
	if _current_step in ["gauntlet", "complete"] \
			and (str(_gauntlet_intro_authority.get("phase", "")) \
				!= GAUNTLET_INTRO_PHASE_READY \
				or str(_gauntlet_run_authority.get("phase", "")) \
				!= GAUNTLET_RUN_PHASE_ACTIVE):
		if _game_state != null and _game_state.get_party() != selected:
			_game_state.set_party(selected)
		for node in nodes.values():
			if is_instance_valid(node) and node.has_method("set_move_enabled"):
				node.call("set_move_enabled", false)
			if is_instance_valid(node) and "group_move" in node:
				node.set("group_move", false)
		return
	_apply_party_control(nodes, selected, _active_character, group_control)


func _available_party_control_ids() -> Array[String]:
	var result: Array[String] = []
	for character_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		if character_id in ["aster", "peris"] \
				or (_game_state != null and _game_state.characters.has(character_id)):
			result.append(character_id)
	return result


func _available_party_control_nodes() -> Dictionary:
	var nodes := {}
	for character_id in _available_party_control_ids():
		var character_node := _elevator_party_node(character_id)
		if character_node != null:
			nodes[character_id] = character_node
	return nodes


func _elevator_party_node(character_id: String) -> Node3D:
	match character_id:
		"aster":
			return _aster_node
		"peris":
			return _peris_node
		"endo":
			return _endo
	return null


func _ensure_endo_gauntlet_party_ui() -> void:
	if _hud == null or _game_state == null or not _game_state.characters.has("endo"):
		return
	if not _hud.get_portrait_ids().has("endo"):
		_hud.add_portrait("endo", "Endo", Color(0.4, 0.67, 0.53))
	_hud.set_portrait_stat("endo", "hp", _game_state.get_stat("endo", "hp"))
	_hud.set_portrait_stat("endo", "sta", _game_state.get_stat("endo", "stamina"))
	_hud.set_portrait_stat("endo", "atp", _game_state.get_stat("endo", "atp"))
	_hud.set_selected_portraits(_selected_character_ids)

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

## Compatibility alias for focused tools/saves that call this helper by name.
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
	_schedule_portable_method(5.8, _start_fade_in, "fade_in")

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
	_schedule_portable_method(1.5, _start_waking, "waking")

func _start_waking() -> void:
	_enter_step("waking")
	_dialogue_chain(
		[
			"elevator.narration.room",
			"elevator.aster.wake",
			"elevator.peris.wake",
		],
		_queue_start_approach_aster
	)


func _queue_start_approach_aster() -> void:
	_schedule_portable_method(1.0, _start_approach_aster, "approach")


func _start_approach_aster() -> void:
	_enter_step("approach_aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")
	_show_aster_wake_interactable()


func _baseline_elevator_source_authority() -> Dictionary:
	var counts := {}
	for action_id in ELEVATOR_SOURCE_ACTIONS:
		counts[action_id] = 0
	return {
		"version": ELEVATOR_SOURCE_AUTHORITY_VERSION,
		"contract": ELEVATOR_SOURCE_AUTHORITY_CONTRACT,
		"committed_counts": counts,
	}


func _elevator_source_authority_state() -> Dictionary:
	if _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(
		ELEVATOR_SOURCE_AUTHORITY_KEY, null)
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _valid_elevator_source_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	var counts_v: Variant = saved.get("committed_counts", null)
	if int(saved.get("version", 0)) != ELEVATOR_SOURCE_AUTHORITY_VERSION \
			or str(saved.get("contract", "")) != ELEVATOR_SOURCE_AUTHORITY_CONTRACT \
			or not counts_v is Dictionary:
		return false
	var counts := counts_v as Dictionary
	for action_id in ELEVATOR_SOURCE_ACTIONS:
		if not counts.has(action_id) or int(counts.get(action_id, -1)) < 0:
			return false
	return true


func _initialize_elevator_source_authority() -> void:
	if _game_state == null:
		return
	var saved := _elevator_source_authority_state()
	if _valid_elevator_source_authority(saved):
		_elevator_source_committed_counts = (
			saved.get("committed_counts", {}) as Dictionary).duplicate(true)
		return
	_elevator_source_committed_counts.clear()
	for action_id in ELEVATOR_SOURCE_ACTIONS:
		_elevator_source_committed_counts[action_id] = 0
	_publish_elevator_source_authority()


func _publish_elevator_source_authority() -> void:
	if _restoring_elevator_source_authority or _game_state == null:
		return
	var counts := {}
	for action_id in ELEVATOR_SOURCE_ACTIONS:
		counts[action_id] = maxi(
			0, int(_elevator_source_committed_counts.get(action_id, 0)))
	_game_state.set_world_state(ELEVATOR_SOURCE_AUTHORITY_KEY, {
		"version": ELEVATOR_SOURCE_AUTHORITY_VERSION,
		"contract": ELEVATOR_SOURCE_AUTHORITY_CONTRACT,
		"committed_counts": counts,
	})


func _elevator_source_data_id(action_id: String) -> String:
	match action_id:
		ELEVATOR_SOURCE_WAKE:
			return "AsterWakeZone"
		ELEVATOR_SOURCE_COLLAPSE:
			return "ClimbPromptZone"
		ELEVATOR_SOURCE_WRECKAGE:
			return "WreckageClear"
		_:
			return ""


func _elevator_source_for_action(action_id: String) -> Node:
	match action_id:
		ELEVATOR_SOURCE_WAKE:
			return _aster_wake_interactable
		ELEVATOR_SOURCE_COLLAPSE:
			return _climb_interactable
		ELEVATOR_SOURCE_WRECKAGE:
			return _wreckage_interactable
		_:
			return null


func _configure_elevator_source(source: Node, action_id: String) -> void:
	if not is_instance_valid(source):
		return
	source.set("one_shot", true)
	source.set_meta("elevator_source_action", action_id)
	source.call(
		"set_pre_trigger_validator",
		_validate_elevator_source_trigger.bind(action_id, source))
	var callback := Callable()
	match action_id:
		ELEVATOR_SOURCE_WAKE:
			callback = _on_aster_wake_interacted.bind(source)
		ELEVATOR_SOURCE_COLLAPSE:
			callback = _on_climb_prompt_interacted.bind(source)
		ELEVATOR_SOURCE_WRECKAGE:
			callback = _on_wreckage_interacted.bind(source)
	if callback.is_valid() and not source.is_connected("interacted", callback):
		source.connect("interacted", callback)
	_ensure_elevator_source_registry_contract(source)


func _validate_elevator_source_trigger(
		source: Node,
		actor: String,
		action_id: String,
		expected_source: Node
	) -> bool:
	if not is_instance_valid(source) or source != expected_source \
			or source != _elevator_source_for_action(action_id):
		return false
	var required_actor := "peris" if action_id == ELEVATOR_SOURCE_WAKE else ""
	return _elevator_actor_ready_at_source(source, actor, required_actor) \
		and _elevator_source_action_ready(action_id)


func _elevator_source_action_ready(action_id: String) -> bool:
	match action_id:
		ELEVATOR_SOURCE_WAKE:
			return _current_step == "approach_aster"
		ELEVATOR_SOURCE_COLLAPSE:
			return _current_step == "climb_attempt"
		ELEVATOR_SOURCE_WRECKAGE:
			return _current_step == "route_choice" and _wreckage_armed \
				and not _wreckage_cleared and not _wreckage_clear_in_progress \
				and not _wreckage_failure_active
		_:
			return false


func _elevator_actor_ready_at_source(
		source: Node, actor: String, expected_actor := ""
	) -> bool:
	if _game_state == null or not is_instance_valid(source) \
			or not (source is Node3D) or actor not in ["aster", "peris"] \
			or (expected_actor != "" and actor != expected_actor) \
			or not _game_state.characters.has(actor) \
			or not _game_state.is_narratively_available(actor) \
			or _game_state.get_stat(actor, "hp") <= 0.0 \
			or _game_state.is_downed(actor) or _game_state.is_knocked_down(actor) \
			or _game_state.is_moving(actor) or _game_state.is_resting(actor) \
			or _game_state.is_dodging(actor) or _game_state.is_endocytosing(actor) \
			or _game_state.is_external_traversal_active(actor) \
			or _game_state.is_dragging(actor) \
			or _game_state.is_field_restoring(actor) \
			or _game_state.is_pushing(actor):
		return false
	var source_position := _elevator_source_data_position(source)
	if not source_position.is_finite():
		return false
	if _game_state.grid != null and _game_state.grid.level_count > 1 \
			and int(_game_state.get_character_level(actor)) != int(
				_game_state.grid.level_for_y(source_position.y)):
		return false
	var actor_position: Vector3 = _game_state.get_position(actor)
	var radius := float(source.get("interaction_radius")) \
		+ ELEVATOR_SOURCE_POSITION_TOLERANCE
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)) <= radius \
		and absf(actor_position.y - source_position.y) \
			<= ELEVATOR_SOURCE_HEIGHT_TOLERANCE


func _elevator_source_data_position(source: Node) -> Vector3:
	if _game_state == null or not is_instance_valid(source):
		return Vector3.INF
	var data_id := str(source.get("data_id"))
	if data_id != "" and _game_state.has_interactable(data_id):
		var position_v: Variant = _game_state.get_interactable(data_id).get(
			"position", Vector3.INF)
		if position_v is Vector3:
			return position_v
	if source is Node3D:
		var world_position := (source as Node3D).global_position
		if _game_state.coord_map != null \
				and _game_state.coord_map.has_method("to_data"):
			return _game_state.coord_map.to_data(world_position)
		return world_position
	return Vector3.INF


func _elevator_source_registry_count(action_id: String) -> int:
	if _game_state == null:
		return -1
	var data_id := _elevator_source_data_id(action_id)
	if data_id == "" or not _game_state.has_interactable(data_id):
		return -1
	return int(_game_state.get_interactable(data_id).get("trigger_count", -1))


func _elevator_source_receipt_count(source: Node, action_id: String) -> int:
	if not is_instance_valid(source) or source != _elevator_source_for_action(action_id):
		return -1
	var actor := str(source.get("active_character"))
	if not _validate_elevator_source_trigger(source, actor, action_id, source) \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return -1
	var data_id := str(source.get("data_id"))
	if _game_state == null or data_id != _elevator_source_data_id(action_id) \
			or not _game_state.has_interactable(data_id):
		return -1
	var receipt: Dictionary = _game_state.get_interactable(data_id)
	var trigger_count := int(receipt.get("trigger_count", -1))
	if not bool(receipt.get("one_shot", false)) \
			or not bool(receipt.get("triggered", false)) \
			or bool(receipt.get("enabled", true)) \
			or str(receipt.get("last_trigger_character", "")) != actor \
			or trigger_count <= int(
				_elevator_source_committed_counts.get(action_id, 0)):
		return -1
	return trigger_count


func _consume_elevator_source_receipt(
		source: Node, action_id: String
	) -> Dictionary:
	var trigger_count := _elevator_source_receipt_count(source, action_id)
	if trigger_count < 0:
		return {}
	var actor := str(source.get("active_character"))
	_elevator_source_committed_counts[action_id] = trigger_count
	# Publish the exact accepted edge before any PartyGate or story callback can emit. A save at
	# this publication is still pre-consequence and therefore rearms from semantic owner truth.
	_publish_elevator_source_authority()
	return {
		"action": action_id,
		"actor": actor,
		"trigger_count": trigger_count,
	}


func _ensure_elevator_source_registry_contract(source: Node) -> void:
	if _game_state == null or not is_instance_valid(source):
		return
	var data_id := str(source.get("data_id"))
	if data_id == "" or not _game_state.has_interactable(data_id):
		return
	var spec: Dictionary = _game_state.get_interactable(data_id)
	if bool(spec.get("one_shot", false)):
		return
	spec["one_shot"] = true
	# Restore normalization must preserve the stable trigger count and actor history.
	_game_state.interactables[data_id] = spec


func _rearm_elevator_source(source: Node) -> void:
	if not is_instance_valid(source):
		return
	if source.is_node_ready():
		source.call("reset")
		return
	var data_id := str(source.get("data_id"))
	if _game_state != null and data_id != "" \
			and _game_state.has_interactable(data_id):
		_game_state.reset_interactable(data_id)
	source.set("_used", false)
	source.set("interaction_enabled", true)


func _project_elevator_source(action_id: String) -> void:
	var source := _elevator_source_for_action(action_id)
	if not is_instance_valid(source):
		return
	_ensure_elevator_source_registry_contract(source)
	var source_position := _elevator_source_data_position(source)
	if source is Node3D and source_position.is_finite():
		var world_position := source_position
		if _game_state.coord_map != null \
				and _game_state.coord_map.has_method("to_world"):
			world_position = _game_state.coord_map.to_world(source_position)
		(source as Node3D).global_position = world_position
	var data_id := str(source.get("data_id"))
	if _game_state == null or data_id == "" \
			or not _game_state.has_interactable(data_id):
		return
	var spec: Dictionary = _game_state.get_interactable(data_id)
	var should_enable := _elevator_source_action_ready(action_id)
	if should_enable:
		if bool(spec.get("triggered", false)):
			_rearm_elevator_source(source)
		else:
			_game_state.set_interactable_enabled(data_id, true)
			if source.has_method("restore_one_shot_presenter"):
				source.call("restore_one_shot_presenter", false, true)
		source.set("visible", true)
		return
	_game_state.set_interactable_enabled(data_id, false)
	if source.has_method("restore_one_shot_presenter"):
		source.call(
			"restore_one_shot_presenter",
			bool(spec.get("triggered", false)),
			false)
	source.set("visible", false)


func _restore_elevator_source_authority() -> void:
	if _game_state == null:
		return
	_restoring_elevator_source_authority = true
	var raw := _elevator_source_authority_state()
	var migrated := not _valid_elevator_source_authority(raw)
	_elevator_source_committed_counts.clear()
	if not migrated:
		_elevator_source_committed_counts = (
			raw.get("committed_counts", {}) as Dictionary).duplicate(true)
	else:
		for action_id in ELEVATOR_SOURCE_ACTIONS:
			_elevator_source_committed_counts[action_id] = maxi(
				0, _elevator_source_registry_count(action_id))
	var reconciled := false
	for action_id in ELEVATOR_SOURCE_ACTIONS:
		var registry_count := maxi(0, _elevator_source_registry_count(action_id))
		var committed_count := maxi(
			0, int(_elevator_source_committed_counts.get(action_id, 0)))
		if registry_count > committed_count:
			# Accepted-before-owner save: burn the orphan edge, never infer its endpoint.
			_elevator_source_committed_counts[action_id] = registry_count
			reconciled = true
	_restoring_elevator_source_authority = false
	for action_id in ELEVATOR_SOURCE_ACTIONS:
		_project_elevator_source(action_id)
	if migrated or reconciled:
		_publish_elevator_source_authority()


func _start_wake_aster() -> void:
	_enter_step("wake_aster")
	_clear_aster_wake_interactable()
	_hud.set_portrait_status("aster", "")
	_hud.set_portrait_stat("aster", "sta", 100)
	# Tween Aster upright
	var tween := create_tween()
	tween.tween_property(_aster_node, "rotation_degrees:z", 0.0, 1.5)
	_dialogue_chain(["elevator.aster.surface"], _queue_start_conversation)


func _queue_start_conversation() -> void:
	_schedule_portable_method(0.5, _start_conversation, "conversation")

func _show_aster_wake_interactable() -> void:
	_ensure_aster_wake_interactable()
	if not is_instance_valid(_aster_wake_interactable):
		return
	_project_elevator_source(ELEVATOR_SOURCE_WAKE)
	_aster_wake_interactable.call_deferred("show_tutorial_label")


func _ensure_aster_wake_interactable() -> void:
	if is_instance_valid(_aster_wake_interactable) \
			and not _aster_wake_interactable.is_queued_for_deletion():
		_configure_elevator_source(
			_aster_wake_interactable, ELEVATOR_SOURCE_WAKE)
		return
	var parent := _chunks.get("elevator", null) as Node3D
	if parent == null:
		parent = find_child("Environment", false, false) as Node3D
	if parent == null:
		return
	var zone_pos := ASTER_POS + Vector3(0.0, 0.05, 0.0)
	_aster_wake_interactable = _create_interactable(
		parent, zone_pos, "AsterWakeZone", 2.0, 0.6, "Wake", true)
	_aster_wake_interactable.description = "Aster"
	_aster_wake_interactable.required_character = "peris"
	_aster_wake_interactable.active_character = "peris"
	_configure_elevator_source(_aster_wake_interactable, ELEVATOR_SOURCE_WAKE)

func _clear_aster_wake_interactable() -> void:
	if _aster_wake_interactable == null or not is_instance_valid(_aster_wake_interactable):
		_aster_wake_interactable = null
		return
	_aster_wake_interactable.visible = false
	_aster_wake_interactable.set_interaction_enabled(false)
	if _aster_wake_interactable.has_method("hide_tutorial_label"):
		_aster_wake_interactable.hide_tutorial_label()


func _on_aster_wake_interacted(source: Node = null) -> bool:
	var receipt := _consume_elevator_source_receipt(
		source, ELEVATOR_SOURCE_WAKE)
	if receipt.is_empty():
		return false
	_tutorial_prompt.hide_prompt()
	_player.set_move_enabled(false)
	_start_wake_aster()
	return true

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
	_dialogue_chain(["elevator.unit.wake"], _queue_start_units_activate)


func _queue_start_units_activate() -> void:
	_schedule_portable_method(0.5, _start_units_activate, "units_activate")

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
	_schedule_portable_method(2.0, _start_rally_tutorial, "rally_tutorial")

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
	# The instruction stays truthful and immediate: this beat teaches the rally release, not
	# multi-selection; perspective selection is taught later.
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
	# block-finishes the remainder — the cost is bounded by one full build).
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
	], _queue_start_bridge)


func _queue_start_bridge() -> void:
	_schedule_portable_method(2.0, _start_bridge, "bridge")

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
	_dialogue_chain(["elevator.bridge.narration"], _enable_bridge_player_control)


func _enable_bridge_player_control() -> void:
	if _current_step != "bridge":
		return
	# Hand control to the player: walk out across the bridge — that's what collapses it.
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Rally both units across the bridge")

# --- Bridge Collapse ---

func _start_bridge_collapse() -> void:
	if not _enter_step("bridge_collapse"):
		return
	_fall_landed_fired = false
	_peris_node.set_move_enabled(false)
	_aster_node.set_move_enabled(false)
	_game_state.command_stop("aster")
	_game_state.command_stop("peris")
	_retire_elevator_guards()
	_camera.shake(0.4, 2.0)
	DialogueData.say_to(_dialogue, "elevator.narration.collapse")
	DialogueData.say_to(_dialogue, "elevator.peris.floor")
	var now := float(_scheduler.get_current_tick())
	_bridge_collapse_authority = _new_bridge_collapse_authority(now)
	_publish_elevator_runtime_authority()
	_arm_bridge_collapse_callback(
		BRIDGE_COLLAPSE_PHASE_ARMED,
		float(_bridge_collapse_authority.get("phase_deadline", now)))


## These guards do not survive the bridge collapse. Hiding their nodes while retaining their
## GameState bodies made them invisible participants in detection, saves, and the all-conscious
## shelter-rest test. Roster removal is the causal fact; visibility only mirrors it.
func _retire_elevator_guards() -> void:
	for guard_data in [["eu1", _escort_1], ["eu2", _escort_2]]:
		var guard_id := str(guard_data[0])
		var guard := guard_data[1] as Node3D
		if is_instance_valid(guard):
			guard.visible = false
			guard.process_mode = Node.PROCESS_MODE_DISABLED
		_game_state_character_nodes.erase(guard_id)
		if _game_state != null and _game_state.characters.has(guard_id):
			_game_state.unregister_character(guard_id)


## A same-presenter rollback can cross the collapse boundary in either direction. The serialized
## roster decides whether each authored guard presenter exists; no local "was hidden" flag survives.
func _sync_elevator_guard_presence_from_roster() -> void:
	if _game_state == null:
		return
	for guard_data in [["eu1", _escort_1], ["eu2", _escort_2]]:
		var guard_id := str(guard_data[0])
		var guard := guard_data[1] as Node3D
		if not is_instance_valid(guard):
			continue
		var present := _game_state.characters.has(guard_id)
		guard.visible = present
		guard.process_mode = Node.PROCESS_MODE_INHERIT if present else Node.PROCESS_MODE_DISABLED
		if present:
			guard.set("game_state", _game_state)
			guard.set("char_id", guard_id)
			if guard.has_method("set_scheduler"):
				guard.call("set_scheduler", _scheduler)
			_game_state_character_nodes[guard_id] = guard
		else:
			_game_state_character_nodes.erase(guard_id)


## Rebuildable callback arm for each committed collapse phase. Every callback validates the saved
## absolute deadline and phase identity, so rollback cannot retain a future callback and a fresh
## scene can attach exactly one replacement.
func _arm_bridge_collapse_callback(phase: String, deadline: float) -> void:
	if _scheduler == null or deadline < 0.0:
		return
	match phase:
		BRIDGE_COLLAPSE_PHASE_ARMED:
			_scheduler.cancel_tag("bridge_fall")
			_scheduler.schedule_at(
				maxf(_scheduler.get_current_tick(), deadline),
				_on_bridge_arm_deadline.bind(deadline),
				"bridge_fall",
				BRIDGE_COLLAPSE_CALLBACK_PRIORITY)
		BRIDGE_COLLAPSE_PHASE_FALLING:
			_scheduler.cancel_tag("fall_landed")
			_scheduler.schedule_at(
				maxf(_scheduler.get_current_tick(), deadline),
				_on_bridge_fall_deadline.bind(deadline),
				"fall_landed",
				BRIDGE_COLLAPSE_CALLBACK_PRIORITY)
		BRIDGE_COLLAPSE_PHASE_LANDED:
			_scheduler.cancel_tag("fallen")
			_scheduler.schedule_at(
				maxf(_scheduler.get_current_tick(), deadline),
				_on_bridge_recovery_deadline.bind(deadline),
				"fallen",
				BRIDGE_COLLAPSE_CALLBACK_PRIORITY)


func _on_bridge_arm_deadline(expected_deadline: float) -> void:
	if not _bridge_phase_matches(BRIDGE_COLLAPSE_PHASE_ARMED, expected_deadline) \
			or _current_step != "bridge_collapse":
		return
	_execute_bridge_fall()

func _execute_bridge_fall(expected_story_generation := -1) -> void:
	if expected_story_generation >= 0 and (
			expected_story_generation != _current_story_step_generation()
			or _current_step != "bridge_collapse"):
		return
	if _current_step != "bridge_collapse":
		return
	var phase := _bridge_collapse_phase()
	if phase in [BRIDGE_COLLAPSE_PHASE_FALLING, BRIDGE_COLLAPSE_PHASE_LANDED,
			BRIDGE_COLLAPSE_PHASE_COMPLETE]:
		return
	# Backward-compatible direct test/old-save seam. Production reaches this function only after
	# _start_bridge_collapse has published the armed record.
	if phase != BRIDGE_COLLAPSE_PHASE_ARMED:
		_bridge_collapse_authority = _new_bridge_collapse_authority(
			float(_scheduler.get_current_tick()) - BRIDGE_COLLAPSE_ARM_SECONDS)
	var now := float(_scheduler.get_current_tick())
	_bridge_collapse_authority["phase"] = BRIDGE_COLLAPSE_PHASE_FALLING
	_bridge_collapse_authority["phase_started_at"] = now
	_bridge_collapse_authority["phase_deadline"] = now + BRIDGE_COLLAPSE_FALL_SECONDS
	_bridge_collapse_authority["topology_committed"] = false
	_bridge_collapse_authority["chunks_retired"] = false
	_begin_bridge_party_traversals(_bridge_collapse_authority)
	_publish_elevator_runtime_authority()
	_camera.shake(0.75, 1.5)
	var bridge_chunk: Node3D = _chunks.get("bridge")
	var bridge_floor: Node3D = bridge_chunk.find_child("BridgeFloor", false, false) if bridge_chunk else null
	var model: Node3D = bridge_floor.find_child("BridgeModel", false, false) if bridge_floor != null else null
	# HYBRID collapse: the span shears where the player stands and the break races outward (art-directed
	# cascade); each modeled piece is then handed to PHYSICS to tumble and settle (believable). Cosmetic.
	# Authoritative party motion is the saved external traversal above; bridge collision and path topology
	# do not retire until that traversal reaches the physical endpoint.
	var break_x := float(_bridge_collapse_authority.get(
		"break_x", _game_state.get_position("aster").x))
	if model != null:
		var collapse_started := PerformanceTrace.begin()
		_collapse_bridge_model(model, break_x)
		PerformanceTrace.end(&"draw", &"elevator.bridge_collapse_begin", collapse_started,
			str(model.name), BRIDGE_COLLAPSE_PIECES_PER_FRAME)
		var dust_started := PerformanceTrace.begin()
		_spawn_collapse_dust(bridge_floor, break_x)
		PerformanceTrace.end(&"draw", &"elevator.bridge_collapse_dust", dust_started,
			str(bridge_floor.name), 48)
	_start_bridge_fall_presentation(_bridge_collapse_authority)
	_arm_bridge_collapse_callback(
		BRIDGE_COLLAPSE_PHASE_FALLING,
		float(_bridge_collapse_authority.get("phase_deadline", now)))


func _on_bridge_fall_deadline(expected_deadline: float) -> void:
	if not _bridge_phase_matches(BRIDGE_COLLAPSE_PHASE_FALLING, expected_deadline) \
			or _current_step != "bridge_collapse":
		return
	_on_fall_landed()

func _on_fall_landed_if_current(expected_story_generation: int) -> void:
	if expected_story_generation != _current_story_step_generation() \
			or _current_step != "bridge_collapse":
		return
	_on_fall_landed()


func _new_bridge_collapse_authority(start_tick: float) -> Dictionary:
	var party := {}
	for character_id in ["aster", "peris"]:
		var data_origin := _game_state.get_position(character_id)
		var character_node := get_game_state_character_node(character_id)
		var render_origin := character_node.global_position \
			if character_node != null else data_origin + Vector3(0.0, 0.5, 0.0)
		var data_destination := Vector3(data_origin.x, BELOW_Y, data_origin.z)
		var render_destination := Vector3(render_origin.x, BELOW_Y + 0.5, render_origin.z)
		party[character_id] = {
			"data_origin": GameEvent.v3_to_arr(data_origin),
			"data_destination": GameEvent.v3_to_arr(data_destination),
			"render_origin": GameEvent.v3_to_arr(render_origin),
			"render_destination": GameEvent.v3_to_arr(render_destination),
		}
	return {
		"version": BRIDGE_COLLAPSE_AUTHORITY_VERSION,
		"collapse_id": BRIDGE_COLLAPSE_AUTHORITY_ID,
		"phase": BRIDGE_COLLAPSE_PHASE_ARMED,
		"phase_started_at": start_tick,
		"phase_deadline": start_tick + BRIDGE_COLLAPSE_ARM_SECONDS,
		"break_x": _game_state.get_position("aster").x,
		"camera_follow_y": _camera.follow_offset.y if _camera != null else 12.0,
		"party": party,
		"topology_committed": false,
		"chunks_retired": false,
	}


func _bridge_collapse_phase() -> String:
	if int(_bridge_collapse_authority.get("version", 0)) \
			!= BRIDGE_COLLAPSE_AUTHORITY_VERSION \
			or str(_bridge_collapse_authority.get("collapse_id", "")) \
			!= BRIDGE_COLLAPSE_AUTHORITY_ID:
		return ""
	return str(_bridge_collapse_authority.get("phase", ""))


func _bridge_phase_matches(phase: String, deadline: float) -> bool:
	return _bridge_collapse_phase() == phase and is_equal_approx(
		float(_bridge_collapse_authority.get("phase_deadline", -1.0)), deadline)


func _bridge_context_position(
		context: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var encoded: Variant = context.get(key, null)
	if encoded is Vector3:
		return encoded as Vector3
	if encoded is Array and (encoded as Array).size() >= 3:
		return GameEvent.arr_to_v3(encoded as Array)
	return fallback


func _begin_bridge_party_traversals(authority: Dictionary) -> void:
	if _game_state == null or _scheduler == null:
		return
	var party: Dictionary = authority.get("party", {}) as Dictionary
	var duration := maxf(0.000001,
		float(authority.get("phase_deadline", _scheduler.get_current_tick())) \
		- float(_scheduler.get_current_tick()))
	for character_id in ["aster", "peris"]:
		if not _game_state.characters.has(character_id) \
				or _game_state.is_external_traversal_active(character_id):
			continue
		var context: Dictionary = party.get(character_id, {}) as Dictionary
		var data_origin := _bridge_context_position(
			context, "data_origin", _game_state.get_position(character_id))
		var data_destination := _bridge_context_position(
			context, "data_destination", Vector3(data_origin.x, BELOW_Y, data_origin.z))
		var character_node := get_game_state_character_node(character_id)
		var render_origin := _bridge_context_position(
			context,
			"render_origin",
			character_node.global_position if character_node != null else data_origin)
		var render_destination := _bridge_context_position(
			context,
			"render_destination",
			Vector3(render_origin.x, BELOW_Y + 0.5, render_origin.z))
		_game_state.command_external_traversal(
			character_id,
			StringName(BRIDGE_FALL_TRAVERSAL_PREFIX + character_id),
			data_destination,
			render_origin,
			render_destination,
			duration,
			&"locked")


## Presentation follows the saved traversal's exact scheduler progress. Tween is only the smooth live
## view; GameState remains the owner of the rider positions and reconstructs their current point first.
func _start_bridge_fall_presentation(authority: Dictionary) -> void:
	if _camera == null or _scheduler == null:
		return
	if _fall_tween != null and _fall_tween.is_valid():
		_fall_tween.kill()
	var start_tick := float(authority.get("phase_started_at", _scheduler.get_current_tick()))
	var deadline := float(authority.get("phase_deadline", start_tick))
	var now := float(_scheduler.get_current_tick())
	var total := maxf(0.000001, deadline - start_tick)
	var progress := clampf((now - start_tick) / total, 0.0, 1.0)
	_fall_prev_offset_y = float(authority.get("camera_follow_y", _camera.follow_offset.y))
	_fall_offset_dipped = true
	_camera.follow_offset.y = lerpf(
		_fall_prev_offset_y, _fall_prev_offset_y + BELOW_Y, progress)
	var party: Dictionary = authority.get("party", {}) as Dictionary
	for character_id in ["aster", "peris"]:
		var character_node := get_game_state_character_node(character_id)
		if character_node == null:
			continue
		if _game_state.is_external_traversal_active(character_id):
			var traversal := _game_state.get_external_traversal_state(character_id)
			character_node.global_position = traversal.get(
				"render_position", character_node.global_position) as Vector3
		else:
			var context: Dictionary = party.get(character_id, {}) as Dictionary
			var origin := _bridge_context_position(
				context, "render_origin", character_node.global_position)
			var destination := _bridge_context_position(
				context, "render_destination", Vector3(origin.x, BELOW_Y + 0.5, origin.z))
			character_node.global_position = origin.lerp(destination, progress)
	var remaining := maxf(0.0, deadline - now)
	if remaining <= 0.000001:
		_fall_tween = null
		return
	var tween := create_tween()
	tween.set_parallel(true)
	for character_id in ["peris", "aster"]:
		var character_node := get_game_state_character_node(character_id)
		if character_node == null:
			continue
		var context: Dictionary = party.get(character_id, {}) as Dictionary
		var destination := _bridge_context_position(
			context,
			"render_destination",
			Vector3(character_node.global_position.x, BELOW_Y + 0.5, character_node.global_position.z))
		tween.tween_property(character_node, "position:y", destination.y, remaining)
	tween.tween_property(
		_camera, "follow_offset:y", _fall_prev_offset_y + BELOW_Y, remaining)
	_fall_tween = tween
	if _collapse_visual_paused or _scheduler.is_paused():
		_fall_tween.pause()


## Keep deterministic/headless playback on the exact same saved trajectory as GameState. The Tween
## remains a cosmetic interpolator between rendered ticks, but it is never allowed to become truth.
func _sync_bridge_fall_presentation_from_authority() -> void:
	if _bridge_collapse_phase() != BRIDGE_COLLAPSE_PHASE_FALLING \
			or _scheduler == null:
		return
	for character_id in ["aster", "peris"]:
		if not _game_state.is_external_traversal_active(character_id):
			continue
		var character_node := get_game_state_character_node(character_id)
		if character_node != null:
			character_node.global_position = _game_state.get_external_traversal_state(
				character_id).get("render_position", character_node.global_position) as Vector3
	if _camera != null:
		var start_tick := float(_bridge_collapse_authority.get(
			"phase_started_at", _scheduler.get_current_tick()))
		var deadline := float(_bridge_collapse_authority.get("phase_deadline", start_tick))
		var progress := clampf(
			(_scheduler.get_current_tick() - start_tick) \
			/ maxf(0.000001, deadline - start_tick), 0.0, 1.0)
		var base_y := float(_bridge_collapse_authority.get(
			"camera_follow_y", _fall_prev_offset_y))
		_camera.follow_offset.y = lerpf(base_y, base_y + BELOW_Y, progress)

## Turn the modeled span into falling debris through a reusable, frame-sliced presenter. Its own
## lifecycle token intentionally survives the following story-step transition while scene ownership
## and explicit pause keep cosmetic physics observationally atomic with the authoritative fall.
func _collapse_bridge_model(model: Node3D, break_x: float) -> void:
	_collapse_visual_active = true
	if _collapse_presenter != null and is_instance_valid(_collapse_presenter):
		_collapse_presenter.cancel()
		_collapse_presenter.queue_free()
	var host := model.get_parent() as Node3D
	if host == null:
		_collapse_visual_active = false
		return
	_collapse_presenter = StagedRigidCollapseScript.new() as StagedRigidCollapse3D
	_collapse_presenter.name = "BridgeCollapsePresenter"
	host.add_child(_collapse_presenter)
	_collapse_presenter.settled.connect(_on_bridge_collapse_settled)
	_collapse_visual_generation = _collapse_presenter.begin(model, break_x, {
		"pieces_per_step": BRIDGE_COLLAPSE_PIECES_PER_FRAME,
		"settle_seconds": 3.0,
		"debris_layer": DEBRIS_PIECE_LAYER,
		"floor_layer": DEBRIS_FLOOR_LAYER,
		"gravity_scale": 1.4,
		"catch_size": Vector3(60.0, 1.0, 30.0),
		"catch_global_position": Vector3(break_x, BELOW_Y - 0.4, 0.0),
	})
	_collapse_presenter.set_visual_paused(_collapse_visual_paused)

func _on_bridge_collapse_settled(generation: int) -> void:
	if _collapse_presenter == null or not is_instance_valid(_collapse_presenter) \
			or generation != _collapse_visual_generation:
		return
	_collapse_visual_active = false
	# Physics is a cosmetic presenter and may run on a different clock. It can never retire the
	# authoritative bridge topology before the party's saved traversal reaches its endpoint.
	if _bridge_collapse_phase() in [
			BRIDGE_COLLAPSE_PHASE_LANDED, BRIDGE_COLLAPSE_PHASE_COMPLETE]:
		_remove_collapsed_chunks()

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

func _on_fall_landed(force_legacy_endpoint := false) -> void:
	# Fires from the scheduled landing (or a test force-fire) — exactly once.
	if _fall_landed_fired:
		return
	var authoritative_fall := _bridge_collapse_phase() == BRIDGE_COLLAPSE_PHASE_FALLING
	# This callback has lower scheduler priority than GameState's traversal endpoints. An active
	# rider therefore proves this is an early/stale call (or a sub-microsecond JSON rounding skew);
	# topology cannot commit yet. Recheck at the latest rider endpoint without changing authority.
	if authoritative_fall:
		var latest_rider_endpoint := -1.0
		for character_id in ["aster", "peris"]:
			if _game_state.is_external_traversal_active(character_id):
				if not force_legacy_endpoint:
					var traversal := _game_state.get_external_traversal_state(character_id)
					latest_rider_endpoint = maxf(
						latest_rider_endpoint,
						_scheduler.get_current_tick() + float(traversal.get("remaining", 0.0)))
					continue
				_game_state.cancel_external_traversal(
					character_id, &"explicit_test_force_endpoint")
		if latest_rider_endpoint >= 0.0:
			var expected_deadline := float(_bridge_collapse_authority.get(
				"phase_deadline", latest_rider_endpoint))
			_scheduler.cancel_tag("fall_landed")
			_scheduler.schedule_at(
				maxf(_scheduler.get_current_tick() + 0.000001, latest_rider_endpoint),
				_on_bridge_fall_deadline.bind(expected_deadline),
				"fall_landed",
				BRIDGE_COLLAPSE_CALLBACK_PRIORITY)
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
		# The shared external-traversal state machine normally committed this endpoint immediately
		# before the sequence callback. This fallback preserves pre-authority saves and direct probes.
		if _game_state.get_character_level(char_id) != LEVEL_LOWER:
			var pos: Vector3 = _game_state.get_position(char_id)
			_game_state.set_character_level(char_id, LEVEL_LOWER)
			var lower_pos: Vector3 = _game_state.get_position(char_id)
			_game_state.characters[char_id]["position"] = Vector3(pos.x, lower_pos.y, pos.z)
			if _game_state.grid != null:
				_game_state.characters[char_id]["grid_cell"] = _game_state.grid.world_to_grid(
					_game_state.characters[char_id]["position"])
		var character_node := get_game_state_character_node(char_id)
		if character_node != null:
			var party: Dictionary = _bridge_collapse_authority.get("party", {}) as Dictionary
			var context: Dictionary = party.get(char_id, {}) as Dictionary
			character_node.global_position = _bridge_context_position(
				context,
				"render_destination",
				Vector3(_game_state.get_position(char_id).x, BELOW_Y + 0.5,
					_game_state.get_position(char_id).z))
	if authoritative_fall:
		var now := float(_scheduler.get_current_tick())
		_bridge_collapse_authority["phase"] = BRIDGE_COLLAPSE_PHASE_LANDED
		_bridge_collapse_authority["phase_started_at"] = now
		_bridge_collapse_authority["phase_deadline"] = now + BRIDGE_COLLAPSE_RECOVERY_SECONDS
		_bridge_collapse_authority["topology_committed"] = true
		_commit_bridge_collapse_topology(true)
		_publish_elevator_runtime_authority()
	_set_lower_route_camera_bounds()
	# Geometry was revealed above the bridge so the lower route could be read, but
	# its ecology has remained outside GameState and entirely unprocessed.  The
	# landing is the first moment those actors can affect (or be affected by) the
	# party, so wake the cohort now in one batched detection update.
	_activate_below_fauna()
	# The route, wreckage gate, and arrival dialogue provide a long construction
	# window. Build Endo's Junction invisibly in bounded slices now, after the
	# bridge/lower-deck streams have finished, rather than on the arrival frame.
	stream_chunk("junction")
	resume_chunk_stream("junction")
	# Free the old level once the debris has visually settled. In real play _collapse_bridge_model set
	# _collapse_visual_active and owns the removal (a wall-clock timer), so we don't rip the bridge away
	# mid-fall. Headless / force-fire (no live collapse) removes here.
	if not _collapse_visual_active:
		_remove_collapsed_chunks()
	if authoritative_fall:
		_arm_bridge_collapse_callback(
			BRIDGE_COLLAPSE_PHASE_LANDED,
			float(_bridge_collapse_authority.get("phase_deadline", -1.0)))
	else:
		var landing_story_generation := _current_story_step_generation()
		_scheduler.schedule_after(BRIDGE_COLLAPSE_RECOVERY_SECONDS,
			_start_fallen_if_current.bind(landing_story_generation), "fallen")


func _on_bridge_recovery_deadline(expected_deadline: float) -> void:
	if not _bridge_phase_matches(BRIDGE_COLLAPSE_PHASE_LANDED, expected_deadline) \
			or _current_step != "bridge_collapse":
		return
	_start_fallen()

func _start_fallen_if_current(expected_story_generation: int) -> void:
	if expected_story_generation != _current_story_step_generation() \
			or _current_step != "bridge_collapse":
		return
	_start_fallen()

## Cosmetic: free the elevator + bridge chunks (the old, fallen-away level) once the debris has settled.
## Idempotent — runs from the presenter settlement signal or directly in a force-fired/headless seam.
func _remove_collapsed_chunks() -> void:
	if _collapsed_chunks_removed:
		return
	_collapsed_chunks_removed = true
	_collapse_visual_active = false
	if _collapse_presenter != null and is_instance_valid(_collapse_presenter):
		_collapse_presenter.cancel(false)
	_collapse_presenter = null
	_collapse_visual_generation = 0
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
	if not _bridge_collapse_authority.is_empty():
		_bridge_collapse_authority["chunks_retired"] = true
		_publish_elevator_runtime_authority()

func _start_fallen() -> void:
	if _bridge_collapse_phase() == BRIDGE_COLLAPSE_PHASE_LANDED:
		_bridge_collapse_authority["phase"] = BRIDGE_COLLAPSE_PHASE_COMPLETE
		_bridge_collapse_authority["phase_started_at"] = float(_scheduler.get_current_tick())
		_bridge_collapse_authority["phase_deadline"] = -1.0
		_bridge_collapse_authority["topology_committed"] = true
		_publish_elevator_runtime_authority()
	if not _collapse_visual_active:
		_remove_collapsed_chunks()
	_enter_step("fallen")
	_dialogue_chain([
		"elevator.narration.landing",
		"elevator.narration.scramble",
		"elevator.aster.way_back",
		"elevator.peris.laugh",
		"elevator.aster.funny",
		"elevator.peris.most_felt",
	], _queue_start_climb_attempt)


func _queue_start_climb_attempt() -> void:
	_schedule_portable_method(1.0, _start_climb_attempt, "climb")

func _start_climb_attempt() -> void:
	_enter_step("climb_attempt")
	# Establish that the bridge cannot be retraced.
	_dialogue_chain([
		"elevator.narration.wall_try",
		"elevator.aster.climb",
		"elevator.peris.climb",
	], _show_climb_interactable)

func _show_climb_interactable() -> void:
	_ensure_climb_interactable()
	if not is_instance_valid(_climb_interactable):
		return
	_project_elevator_source(ELEVATOR_SOURCE_COLLAPSE)
	_climb_interactable.call_deferred("show_tutorial_label")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Climb zone - check the collapsed bridge")


func _ensure_climb_interactable() -> void:
	if is_instance_valid(_climb_interactable) \
			and not _climb_interactable.is_queued_for_deletion():
		_configure_elevator_source(
			_climb_interactable, ELEVATOR_SOURCE_COLLAPSE)
		return
	var parent := _chunks.get("below", null) as Node3D
	if parent == null:
		parent = find_child("Environment", false, false) as Node3D
	if parent == null:
		return
	# Sits under where the bridge gave way (~2/3 across), so the party checks the collapse right where they fell,
	# not a walk back to a far ledge. Derived from the party's landing X so it tracks BRIDGE_COLLAPSE_X.
	var land_x: float = _game_state.get_position("aster").x if _game_state != null and _game_state.characters.has("aster") else BRIDGE_COLLAPSE_X
	var zone_pos := Vector3(land_x, BELOW_Y + 0.05, 0.0)
	_climb_interactable = _create_interactable(parent, zone_pos, "ClimbPromptZone", 2.4, 0.8, "Climb", true)
	_climb_interactable.description = "Collapsed Bridge"
	_configure_elevator_source(
		_climb_interactable, ELEVATOR_SOURCE_COLLAPSE)

func _on_climb_prompt_interacted(source: Node = null) -> bool:
	var receipt := _consume_elevator_source_receipt(
		source, ELEVATOR_SOURCE_COLLAPSE)
	if receipt.is_empty():
		return false
	_enter_step("climb_inspected")
	_tutorial_prompt.hide_prompt()
	if _climb_interactable != null and is_instance_valid(_climb_interactable):
		_climb_interactable.visible = false
		_climb_interactable.set_interaction_enabled(false)
	# Bridge can't be retraced — now choose a way forward through the fork.
	_schedule_portable_method(0.2, _start_route_read_circuit, "route_reads")
	return true

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
		_tutorial_prompt.show_prompt(
			"Aster shows which Flure pulls which pack. F2 optionally reveals exact iron footprints."
		)
	_publish_elevator_runtime_authority()
	# Information changes prediction quality, never permission to act.
	_schedule_portable_method(0.35, _start_route_choice, "route_choice")

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


## Focused browser/native probe for the shelter. Both party members start alive
## and inside the authored entry lane so the checkpoint represents the state the
## ordinary two-person wreckage gate guarantees.
func _start_junction_focus() -> void:
	var focus_center := _junction_anchor_position("Center", JUNCTION_POS + Vector3(0.5, 0.5, 0))
	for entry_spec in [
		["peris", focus_center + Vector3(-0.7, 0, -0.55)],
		["aster", focus_center + Vector3(-0.7, 0, 0.55)],
	]:
		var character_id := str(entry_spec[0])
		var position := entry_spec[1] as Vector3
		_game_state.set_character_level(character_id, LEVEL_LOWER)
		_game_state.snap_character_to(character_id, position)
		_game_state.set_stat(character_id, "hp", PARTY_MAX_HP)
		var character_node: Node3D = _peris_node if character_id == "peris" else _aster_node
		character_node.global_position = position
	_hud.set_portrait_status("aster", "")
	_hud.set_portrait_stat("aster", "sta", 100)
	_select_character("peris")
	_start_junction_arrive()
	if _camera != null:
		_camera.call("_update_immediate")

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
	if _current_step == "route_choice":
		_hud.show_message("Peris marks exact iron footprints; SAFE routing can now avoid them.", 2.8)
	else:
		_tutorial_prompt.show_prompt(
			"Peris marks each iron footprint and its damage rate; your movement plan stays yours."
		)
	_publish_elevator_runtime_authority()

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
	_publish_elevator_runtime_authority()
	if _current_step == "route_read_circuit":
		_schedule_portable_method(0.1, _start_route_choice, "route_choice")

func _start_route_fork_dialogue() -> void:
	# Compatibility entry for focused tools. The authored lines now accompany
	# the two character-specific spatial reads instead of one passive block.
	_start_route_read_circuit()

# --- Route Choice ---

func _start_route_choice() -> void:
	if _current_step == "route_choice":
		return
	_enter_step("route_choice")
	_route_started_tick = _scheduler.get_current_tick()
	_player.set_move_enabled(true)
	for station in _route_flure_interactables:
		if is_instance_valid(station):
			station.set_interaction_enabled(true)
	if not _route_controls_shown:
		_route_controls_shown = true
		_hud.show_run_toggle(false)
		_hud.show_routing_toggle("safe" if _game_state.is_route_cautious() else "direct")
	_arm_wreckage_gate(false)
	_tutorial_prompt.show_prompt(
		"Deliver BOTH characters to the distant brace marks. F1 shows signal links; F2 optionally shows exact hazard boundaries. R run / Tab safe-direct."
	)
	_publish_elevator_runtime_authority()

func _wreckage_interaction_anchor() -> Vector3:
	if is_instance_valid(_wreckage_gate):
		return _wreckage_gate.get_interaction_anchor()
	return WRECKAGE_GATE_POS + Vector3(-2.3, 0.0, 0.0)

func _wreckage_party_ready() -> bool:
	return is_instance_valid(_wreckage_gate) and _wreckage_gate.is_satisfied()

func _arm_wreckage_gate(show_guidance := true) -> void:
	if _wreckage_armed or _wreckage_cleared or not is_instance_valid(_wreckage_interactable):
		return
	_wreckage_armed = true
	_project_elevator_source(ELEVATOR_SOURCE_WRECKAGE)
	_wreckage_interactable.call_deferred("show_tutorial_label")
	_publish_elevator_runtime_authority()
	if show_guidance:
		_tutorial_prompt.show_prompt(
			"Wreckage blocks Endo's hall. Rally Aster and Peris onto both brace marks, then clear it."
		)

func _on_wreckage_interacted(source: Node = null) -> bool:
	var receipt := _consume_elevator_source_receipt(
		source, ELEVATOR_SOURCE_WRECKAGE)
	if receipt.is_empty():
		return false
	var interactor := str(receipt.get("actor", ""))
	if is_instance_valid(_wreckage_gate) and _wreckage_gate.begin_open():
		_clear_wreckage_together()
	else:
		_fail_wreckage_solo(interactor)
	return true

func _wreckage_animation(animation_name: String) -> void:
	if not is_instance_valid(_wreckage_gate):
		return
	var animation := _wreckage_gate.get_node_or_null("GateAnimation") as AnimationPlayer
	if animation != null and animation.has_animation(animation_name):
		animation.play(animation_name)

func _clear_wreckage_together() -> void:
	_wreckage_clear_in_progress = true
	_wreckage_failure_active = false
	if is_instance_valid(_wreckage_interactable):
		_wreckage_interactable.set_interaction_enabled(false)
	_wreckage_animation("clear_together")
	_tutorial_prompt.show_prompt("Both braces take the load. The passage to Endo is clear.")
	_show_marker(WRECKAGE_GATE_POS + Vector3(0.0, 2.4, 0.0), "TWO BRACES  /  CLEAR")
	_player.set_move_enabled(false)
	# PartyGate3D owns the absolute opening deadline and emits `opened` after the second party check.
	# Sequence progression listens to that authoritative completion instead of arming a parallel callback.
	_publish_elevator_runtime_authority()

func _finish_wreckage_clear() -> void:
	if _current_step != "route_choice" or not _wreckage_clear_in_progress:
		return
	_wreckage_clear_in_progress = false
	# The reusable gate performs a second authoritative check after the lift.
	# A death or departure during presentation cannot inherit the earlier pass.
	if not is_instance_valid(_wreckage_gate) or not _wreckage_gate.commit_open():
		_player.set_move_enabled(true)
		_wreckage_animation("RESET")
		var remaining := ""
		for member_id in ["aster", "peris"]:
			if _game_state.characters.has(member_id) and not _game_state.is_downed(member_id):
				remaining = member_id
				break
		if remaining != "":
			_fail_wreckage_solo(remaining)
		else:
			_tutorial_prompt.show_prompt("Both brace marks require conscious party members.")
		return
	_wreckage_cleared = true
	_publish_elevator_runtime_authority()
	_tutorial_prompt.hide_prompt()
	_start_junction_arrive()


func _on_wreckage_gate_blocked(_reason: StringName) -> void:
	# The reusable gate performs its second party check at the authoritative deadline. A failed
	# check closes itself and reports `blocked`; convert that result into the authored noise consequence
	# without maintaining a second completion timer in this sequence.
	if _current_step != "route_choice" or not _wreckage_clear_in_progress:
		return
	var remaining := ""
	for member_id in ["aster", "peris"]:
		if _game_state.characters.has(member_id) and not _game_state.is_downed(member_id):
			remaining = member_id
			break
	if remaining != "":
		_fail_wreckage_solo(remaining)
	else:
		_wreckage_clear_in_progress = false
		_publish_elevator_runtime_authority()
		_tutorial_prompt.show_prompt("Both brace marks require conscious party members.")

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
	_wreckage_clear_in_progress = false
	if is_instance_valid(_wreckage_gate):
		_wreckage_gate.cancel_open()
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
	_wreckage_rearm_deadline = _scheduler.get_current_tick() + 1.05
	_scheduler.schedule_at(
		_wreckage_rearm_deadline,
		_rearm_wreckage_after_solo_failure,
		"wreckage_rearm")
	_publish_elevator_runtime_authority()

func _rearm_wreckage_after_solo_failure() -> void:
	_wreckage_failure_active = false
	_wreckage_rearm_deadline = -1.0
	_publish_elevator_runtime_authority()
	if _wreckage_cleared or _wreckage_clear_in_progress or _current_step != "route_choice" \
			or not is_instance_valid(_wreckage_interactable):
		return
	_project_elevator_source(ELEVATOR_SOURCE_WRECKAGE)
	_wreckage_interactable.call_deferred("show_tutorial_label")
	_tutorial_prompt.show_prompt(
		"The noise brought the fauna in. Regroup both conscious characters at the brace marks."
	)

# --- Junction / Shelter ---

func _junction_survey_ready() -> bool:
	return _junction_beat != null and _junction_beat.survey_ready()

func _update_junction_survey_prompt() -> void:
	if _junction_beat == null:
		return
	_tutorial_prompt.show_prompt(
		"Tend the dormant plant with Peris to continue; shelter objects are optional world-building."
	)

func _on_junction_inspection(label: String, interact: Node) -> void:
	if _current_step != "junction_arrive":
		return
	var inspector := _active_character
	if interact != null and "active_character" in interact and str(interact.get("active_character")) != "":
		inspector = str(interact.get("active_character"))
	if not (inspector in ["aster", "peris"]):
		return
	_junction_beat.record_observation(label, inspector)

func _start_junction_arrive() -> void:
	if _route_started_tick >= 0.0 and _route_finished_tick < 0.0:
		_route_finished_tick = _scheduler.get_current_tick()
		_publish_elevator_runtime_authority()
	# Reset logical progress at the story boundary, never from chunk construction.
	# Presentation assets may be streamed/rebuilt without changing beat lifecycle.
	if _junction_beat != null and not _junction_beat.is_active():
		_junction_beat.reset()
	_enter_step("junction_arrive")
	_set_junction_camera_bounds()
	if _camera != null and _camera.has_method("apply_follow_profile"):
		_camera.apply_follow_profile({
			"follow_offset": Vector3(0, 5.8, 3.8),
			"min_zoom": 0.75,
			"max_zoom": 1.6,
			"initial_zoom": 1.0,
		}, true)
	_clear_markers()
	reveal_chunk("junction")
	_ensure_endo_drink_item()
	_sync_endo_drink_presenter()
	_activate_junction_interactions()
	_retire_lower_route_runtime()
	_unload_chunk("below")
	_enemies.clear()
	_player.set_move_enabled(true)
	_update_junction_survey_prompt()
	# Shelter objects remain optional world-building; Peris tending the dormant
	# plant is the only required story transition.


func _retire_lower_route_runtime() -> void:
	# Timed Flure/iron callbacks must not outlive the streamed chunk that owns their labels, links,
	# enemies, and collision. Keep route-result telemetry, but retire every live runtime reference.
	if _scheduler != null:
		_scheduler.cancel_tag(IRON_HAZARD_TAG)
		for route_index in range(ROUTE_BEAT_COUNT):
			_scheduler.cancel_tag("route_flure_feedback_%d" % route_index)
			_scheduler.cancel_tag("route_flure_failed_feedback_%d" % route_index)
			_scheduler.cancel_tag("flure_reset_RouteFlure%d" % route_index)
	_iron_hazard_tick_armed = false
	for flure_variant in _route_flure_interactables:
		if is_instance_valid(flure_variant) and flure_variant is Flure:
			(flure_variant as Flure).reset_flure()
	_route_flure_interactables.clear()
	_route_flure_meshes.clear()
	_route_flure_enemy_groups.clear()
	_route_flure_countdown_labels.clear()
	_route_causal_links.clear()
	_clear_iron_route_risk_cells()
	_iron_patches.clear()

func _start_endo_enters() -> void:
	_enter_step("endo_enters")
	_endo_entry_dialogue_started = false
	# The plant interaction closes the exploration beat. Settle both existing party bodies through
	# GameState before scripted formation begins, so the later shelter preflight never depends on a
	# presentation node continuing (or silently abandoning) an old click route.
	for character_id in ["aster", "peris"]:
		if _game_state.characters.has(character_id):
			_game_state.command_stop(character_id)
	var entry_position := _junction_anchor_position(
		"EndoEntry", Vector3(JUNCTION_POS.x + SHELTER_SIZE.x / 2.0 + 1.0, BELOW_Y + 0.5, 0)
	)
	_set_endo_presenter_present(true)
	if not _game_state.characters.has("endo"):
		_endo.global_position = entry_position
		_register_gs_character("endo", _endo, 2.5, {
			"hp": PARTY_MAX_HP,
			"stamina": GameState.STAMINA_MAX,
			"atp": GameState.ATP_MAX_PIPS,
		})
		_game_state.set_character_level("endo", LEVEL_LOWER)
		_game_state.snap_character_to("endo", entry_position)
	_player.set_move_enabled(false)
	var junction_center := _endo_entry_destination()
	_show_marker(junction_center + Vector3(0, 2.0, 0), "SHELTER")
	_begin_endo_entry_approach(junction_center, 1)


func _set_endo_presenter_present(
	present: bool, preserve_authoritative_movement := false
) -> void:
	if not is_instance_valid(_endo):
		return
	_endo.visible = present
	_endo.process_mode = Node.PROCESS_MODE_INHERIT if present else Node.PROCESS_MODE_DISABLED
	if preserve_authoritative_movement and _endo.has_method("restore_move_input_enabled"):
		_endo.call("restore_move_input_enabled", false)
	elif _endo.has_method("set_move_enabled"):
		# Joining, delivery, and the gauntlet briefing are scripted formation
		# phases. Party control explicitly releases Endo after the three-body
		# arrival latch, never merely because his presenter became visible.
		_endo.call("set_move_enabled", false)


func _endo_entry_destination() -> Vector3:
	var authored := _junction_anchor_position(
		"Center", JUNCTION_POS + Vector3(0, 0.5, 0))
	if _grid == null:
		return authored
	var target_cell := _grid.nearest_walkable_cell(
		_grid.world_to_grid(authored), LEVEL_LOWER)
	return _grid.grid_to_world(target_cell, LEVEL_LOWER)


## The authored PartyRest marker centers the shelter composition, but ordinary
## navigation can only settle Endo on a graph node. The delivery receipt must
## use that same resolved node; comparing a cell-center arrival to the decorative
## marker with a smaller radius made the water handoff impossible.
func _endo_delivery_destination() -> Vector3:
	var authored := _junction_anchor_position(
		"PartyRest",
		Vector3(JUNCTION_POS.x - SHELTER_SIZE.x / 2.0 + 1.0, BELOW_Y + 0.5, 0)
	)
	if _grid == null:
		return authored
	var target_cell := _grid.nearest_walkable_cell(
		_grid.world_to_grid(authored), LEVEL_LOWER)
	return _grid.grid_to_world(target_cell, LEVEL_LOWER)


func _endo_entry_authority_state() -> Dictionary:
	if _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(ENDO_ENTRY_AUTHORITY_KEY, null)
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _valid_endo_entry_authority(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var state := raw as Dictionary
	if int(state.get("version", 0)) != ENDO_ENTRY_AUTHORITY_VERSION \
			or str(state.get("contract", "")) != ENDO_ENTRY_CONTRACT \
			or str(state.get("character_id", "")) != "endo" \
			or not (state.get("origin", null) is Array) \
			or not (state.get("destination", null) is Array):
		return false
	var started_at := float(state.get("started_at", -1.0))
	var arrival_deadline := float(state.get("arrival_deadline", -1.0))
	var arrived_at := float(state.get("arrived_at", -1.0))
	if not is_finite(started_at) or started_at < 0.0 \
			or int(state.get("attempt", 0)) < 1:
		return false
	match str(state.get("phase", "")):
		ENDO_ENTRY_PHASE_APPROACHING:
			return arrived_at < 0.0 and (arrival_deadline < 0.0 \
				or arrival_deadline >= started_at)
		ENDO_ENTRY_PHASE_INTERRUPTED:
			return arrived_at < 0.0 and arrival_deadline < 0.0
		ENDO_ENTRY_PHASE_ARRIVED:
			return is_finite(arrived_at) and arrived_at >= started_at
		_:
			return false


func _publish_endo_entry_authority(state: Dictionary) -> void:
	if _game_state == null:
		return
	_game_state.set_world_state(ENDO_ENTRY_AUTHORITY_KEY, state.duplicate(true))


func _endo_entry_movement_deadline() -> float:
	if _game_state == null or not _game_state.characters.has("endo"):
		return -1.0
	var movement_v: Variant = (_game_state.characters["endo"] as Dictionary).get(
		"movement", null)
	if not (movement_v is Dictionary):
		return -1.0
	var arrival_ticks: Array = (movement_v as Dictionary).get("arrival_ticks", [])
	if not arrival_ticks.is_empty():
		return float(arrival_ticks.back())
	return float((movement_v as Dictionary).get("start_tick", -1.0)) \
		+ float((movement_v as Dictionary).get("duration", 0.0))


func _begin_endo_entry_approach(destination: Vector3, attempt: int) -> bool:
	if _game_state == null or not _game_state.characters.has("endo") \
			or _game_state.is_downed("endo"):
		return false
	var now := float(_scheduler.get_current_tick())
	_publish_endo_entry_authority({
		"version": ENDO_ENTRY_AUTHORITY_VERSION,
		"contract": ENDO_ENTRY_CONTRACT,
		"character_id": "endo",
		"phase": ENDO_ENTRY_PHASE_APPROACHING,
		"origin": GameEvent.v3_to_arr(_game_state.get_position("endo")),
		"destination": GameEvent.v3_to_arr(destination),
		"started_at": now,
		"arrival_deadline": -1.0,
		"arrived_at": -1.0,
		"attempt": maxi(1, attempt),
		"interruption_policy": "pause_then_resume_from_authoritative_position",
		"interruption_reason": "",
	})
	if _horizontal_distance(_game_state.get_position("endo"), destination) \
			<= ENDO_ENTRY_RADIUS:
		_commit_endo_entry_arrival()
		return true
	if not _game_state.command_move_to_pos("endo", destination):
		_mark_endo_entry_interrupted(&"path_rejected")
		return false
	var state := _endo_entry_authority_state()
	if _valid_endo_entry_authority(state) \
			and str(state.get("phase", "")) == ENDO_ENTRY_PHASE_APPROACHING:
		state["arrival_deadline"] = _endo_entry_movement_deadline()
		_publish_endo_entry_authority(state)
	return true


func _mark_endo_entry_interrupted(reason: StringName) -> void:
	var state := _endo_entry_authority_state()
	if not _valid_endo_entry_authority(state) \
			or str(state.get("phase", "")) == ENDO_ENTRY_PHASE_ARRIVED:
		return
	state["phase"] = ENDO_ENTRY_PHASE_INTERRUPTED
	state["arrival_deadline"] = -1.0
	state["interruption_reason"] = str(reason)
	state["interrupted_at"] = float(_scheduler.get_current_tick())
	_publish_endo_entry_authority(state)


func _resume_endo_entry() -> bool:
	if _current_step != "endo_enters" or _game_state == null \
			or not _game_state.characters.has("endo") or _game_state.is_downed("endo"):
		return false
	var state := _endo_entry_authority_state()
	if not _valid_endo_entry_authority(state) \
			or str(state.get("phase", "")) != ENDO_ENTRY_PHASE_INTERRUPTED:
		return false
	return _begin_endo_entry_approach(
		GameEvent.arr_to_v3(state.get("destination", [])),
		int(state.get("attempt", 1)) + 1)


func _sync_endo_entry_interruption() -> void:
	if _current_step != "endo_enters" or _game_state == null \
			or not _game_state.characters.has("endo"):
		return
	var state := _endo_entry_authority_state()
	if not _valid_endo_entry_authority(state) \
			or str(state.get("phase", "")) != ENDO_ENTRY_PHASE_APPROACHING:
		return
	var destination := GameEvent.arr_to_v3(state.get("destination", []))
	if _game_state.is_moving("endo"):
		if _horizontal_distance(_game_state.get_destination("endo"), destination) \
				> ENDO_ENTRY_RADIUS:
			_mark_endo_entry_interrupted(&"route_replaced")
		return
	if _horizontal_distance(_game_state.get_position("endo"), destination) \
			<= ENDO_ENTRY_RADIUS:
		_commit_endo_entry_arrival()
	else:
		_mark_endo_entry_interrupted(
			&"downed" if _game_state.is_downed("endo") else &"movement_stopped")


func _commit_endo_entry_arrival() -> void:
	if _current_step != "endo_enters" or _game_state == null \
			or not _game_state.characters.has("endo") or _game_state.is_moving("endo") \
			or _game_state.is_downed("endo"):
		return
	var state := _endo_entry_authority_state()
	if not _valid_endo_entry_authority(state):
		return
	if str(state.get("phase", "")) == ENDO_ENTRY_PHASE_ARRIVED:
		_start_endo_entry_dialogue()
		return
	if str(state.get("phase", "")) != ENDO_ENTRY_PHASE_APPROACHING:
		return
	var destination := GameEvent.arr_to_v3(state.get("destination", []))
	if _horizontal_distance(_game_state.get_position("endo"), destination) \
			> ENDO_ENTRY_RADIUS:
		return
	state["phase"] = ENDO_ENTRY_PHASE_ARRIVED
	state["arrived_at"] = float(_scheduler.get_current_tick())
	state["interruption_reason"] = ""
	_publish_endo_entry_authority(state)
	_start_endo_entry_dialogue()


func _start_endo_entry_dialogue() -> void:
	if _current_step != "endo_enters" or _endo_entry_dialogue_started:
		return
	var state := _endo_entry_authority_state()
	if not _valid_endo_entry_authority(state) \
			or str(state.get("phase", "")) != ENDO_ENTRY_PHASE_ARRIVED:
		return
	_endo_entry_dialogue_started = true
	_clear_markers()
	_dialogue_chain([
		"junction.endo.beckon",
		"junction.peris.who",
		"junction.aster.endo_read",
	], _start_endo_shelter)

func _start_endo_shelter() -> void:
	_enter_step("endo_shelter")
	_player.set_move_enabled(false)
	_endo_delivery_dialogue_started = false
	_ensure_endo_drink_item()
	_sync_endo_drink_presenter()
	# Endo walks to the physical container. Arrival, not a narrative timer, begins
	# the saved pickup phase.
	var container_pos := _junction_anchor_position(
		"DrinkPickup", Vector3(JUNCTION_POS.x + 1.5, BELOW_Y + 0.5, -1.0)
	)
	if _endo_holds_drink():
		_start_endo_delivery()
	elif _game_state.characters.has("endo") \
			and _horizontal_distance(
				_game_state.get_position("endo"), container_pos) <= ENDO_DRINK_PICKUP_RADIUS:
		_on_endo_at_container("endo")
	else:
		_game_state.command_move_to_pos("endo", container_pos)

func _on_endo_at_container(id: String) -> void:
	if id != "endo" or _current_step != "endo_shelter" \
			or not _game_state.characters.has("endo") or _game_state.is_moving("endo"):
		return
	if _endo_holds_drink():
		_start_endo_delivery()
		return
	var drink_id := _ensure_endo_drink_item()
	if drink_id == "" or not _game_state.items.has(drink_id):
		return
	var container_pos := _endo_drink_ground_position()
	if _horizontal_distance(
			_game_state.get_position("endo"), container_pos) > ENDO_DRINK_PICKUP_RADIUS:
		return
	var item: Dictionary = _game_state.items[drink_id]
	if str(item.get("location", "")) != "ground":
		return
	var phase := _game_state.get_mechanism_phase_state(ENDO_DRINK_PICKUP_PHASE_ID)
	if not phase.is_empty():
		if StringName(str(phase.get("phase", ""))) == ENDO_DRINK_PICKED_PHASE:
			_commit_endo_drink_pickup()
		return
	# The visible hold is a scheduler-owned state machine. Saving here preserves
	# its exact remaining time; moving or being downed resets it through GameState signals.
	_show_marker(_endo.global_position + Vector3(0, 1.5, 0), "...")
	_game_state.command_begin_mechanism_phase(
		ENDO_DRINK_PICKUP_PHASE_ID,
		ENDO_DRINK_PICKUP_PHASE,
		ENDO_DRINK_PICKUP_SECONDS,
		ENDO_DRINK_PICKED_PHASE,
		{
			"actor_id": "endo",
			"item_id": drink_id,
			"source_contract": ENDO_DRINK_CONTRACT,
			"source_position": GameEvent.v3_to_arr(container_pos),
		}
	)

func _endo_pickup_drink() -> void:
	# Compatibility seam for older focused tools: it can only cash out a completed
	# authoritative phase and cannot skip the physical dwell.
	_commit_endo_drink_pickup()


func _commit_endo_drink_pickup() -> void:
	if _game_state == null or not _game_state.characters.has("endo"):
		return
	var phase := _game_state.get_mechanism_phase_state(ENDO_DRINK_PICKUP_PHASE_ID)
	if StringName(str(phase.get("phase", ""))) != ENDO_DRINK_PICKED_PHASE:
		return
	var drink_id := _resolve_endo_drink_item_id()
	if drink_id == "":
		return
	if _endo_holds_drink():
		_start_endo_delivery()
		return
	if _game_state.is_downed("endo") \
			or _horizontal_distance(_game_state.get_position("endo"),
				_endo_drink_ground_position()) > ENDO_DRINK_PICKUP_RADIUS:
		_game_state.command_reset_mechanism_phase(
			ENDO_DRINK_PICKUP_PHASE_ID, &"actor_left_pickup")
		return
	if not _game_state.pick_up_item("endo", drink_id):
		_game_state.command_reset_mechanism_phase(
			ENDO_DRINK_PICKUP_PHASE_ID, &"pickup_rejected")
		return
	_clear_markers()
	_sync_endo_drink_presenter()
	_start_endo_delivery()


func _start_endo_delivery() -> void:
	if _current_step not in ["endo_shelter", "endo_delivery"] or not _endo_holds_drink():
		return
	_enter_step("endo_delivery")
	# The hand item is GameState truth from this point onward. The mesh merely follows
	# that hand, so a mid-route save reloads Endo carrying the same physical container.
	_sync_endo_drink_presenter()
	var party_pos := _endo_delivery_destination()
	_show_marker(party_pos + Vector3(0, 1.0, 0), "WATER")
	if _horizontal_distance(
			_game_state.get_position("endo"), party_pos) <= ENDO_DRINK_DELIVERY_RADIUS:
		_on_endo_delivered("endo")
	else:
		_game_state.command_move_to_pos("endo", party_pos)

func _on_endo_delivered(id: String) -> void:
	if id != "endo" or _current_step != "endo_delivery" \
			or not _game_state.characters.has("endo") or _game_state.is_moving("endo") \
			or not _endo_holds_drink():
		return
	var party_pos := _endo_delivery_destination()
	if _horizontal_distance(
			_game_state.get_position("endo"), party_pos) > ENDO_DRINK_DELIVERY_RADIUS:
		return
	_enter_step("endo_delivered")
	_start_endo_delivery_dialogue()


func _start_endo_delivery_dialogue() -> void:
	if _current_step != "endo_delivered" or _endo_delivery_dialogue_started:
		return
	_endo_delivery_dialogue_started = true
	_clear_markers()
	_dialogue_chain([
		"junction.endo.drink",
		"junction.peris.stomach",
		"junction.endo.rest",
	], _start_night_watch)


func _on_endo_story_character_arrived(id: String) -> void:
	if id != "endo":
		return
	match _current_step:
		"endo_enters":
			var state := _endo_entry_authority_state()
			if not _valid_endo_entry_authority(state):
				return
			if str(state.get("phase", "")) == ENDO_ENTRY_PHASE_APPROACHING:
				_commit_endo_entry_arrival()
		"endo_shelter":
			if _endo_holds_drink():
				_start_endo_delivery()
				return
			var container_pos := _endo_drink_ground_position()
			if _horizontal_distance(_game_state.get_position("endo"),
					container_pos) <= ENDO_DRINK_PICKUP_RADIUS:
				_on_endo_at_container(id)
			elif not _game_state.is_downed("endo"):
				# A scripted interruption remains recoverable: after reaching its
				# alternate endpoint Endo walks back and begins a fresh physical hold.
				_game_state.command_move_to_pos("endo", container_pos)
		"endo_delivery":
			_on_endo_delivered(id)


func _on_endo_handoff_movement_started(id: String) -> void:
	if id != "endo" or _game_state == null:
		return
	if _current_step == "endo_enters":
		var entry_state := _endo_entry_authority_state()
		if _valid_endo_entry_authority(entry_state) \
				and str(entry_state.get("phase", "")) == ENDO_ENTRY_PHASE_APPROACHING:
			var intended_destination := GameEvent.arr_to_v3(
				entry_state.get("destination", []))
			if _horizontal_distance(
					_game_state.get_destination("endo"), intended_destination) \
					> ENDO_ENTRY_RADIUS:
				_mark_endo_entry_interrupted(&"route_replaced")
			else:
				entry_state["arrival_deadline"] = _endo_entry_movement_deadline()
				_publish_endo_entry_authority(entry_state)
	var phase := _game_state.get_mechanism_phase_state(ENDO_DRINK_PICKUP_PHASE_ID)
	if StringName(str(phase.get("phase", ""))) == ENDO_DRINK_PICKUP_PHASE:
		_game_state.command_reset_mechanism_phase(
			ENDO_DRINK_PICKUP_PHASE_ID, &"actor_moved")
		_clear_markers()


func _on_endo_handoff_stat_changed(id: String, stat: String, value: float) -> void:
	if id != "endo" or stat != "hp" or value > 0.0 or _game_state == null:
		return
	var phase := _game_state.get_mechanism_phase_state(ENDO_DRINK_PICKUP_PHASE_ID)
	if StringName(str(phase.get("phase", ""))) == ENDO_DRINK_PICKUP_PHASE:
		_game_state.command_reset_mechanism_phase(
			ENDO_DRINK_PICKUP_PHASE_ID, &"actor_downed")
		_clear_markers()


func _on_endo_story_character_downed(id: String) -> void:
	if id != "endo" or _game_state == null:
		return
	if _current_step == "endo_enters":
		_mark_endo_entry_interrupted(&"downed")
	var phase := _game_state.get_mechanism_phase_state(ENDO_DRINK_PICKUP_PHASE_ID)
	if StringName(str(phase.get("phase", ""))) == ENDO_DRINK_PICKUP_PHASE:
		_game_state.command_reset_mechanism_phase(
			ENDO_DRINK_PICKUP_PHASE_ID, &"actor_downed")
		_clear_markers()


func _on_endo_story_character_restored(id: String) -> void:
	if id == "endo" and _current_step == "endo_enters":
		_resume_endo_entry()


func _on_endo_handoff_phase_completed(mechanism_id: StringName, phase: StringName) -> void:
	if mechanism_id == ENDO_DRINK_PICKUP_PHASE_ID and phase == ENDO_DRINK_PICKED_PHASE:
		_commit_endo_drink_pickup()


func _ensure_endo_drink_item() -> String:
	var existing := _resolve_endo_drink_item_id()
	if existing != "" or _game_state == null or not is_instance_valid(_drink_mesh):
		return existing
	_drink_item_id = _game_state.spawn_item(
		"water_container",
		_junction_anchor_position("DrinkPickup", _drink_mesh.global_position),
		{
			"display_name": "Water Container",
			"hand_slots": 1,
			"endocytosis_allowed": false,
			"source_contract": ENDO_DRINK_CONTRACT,
		}
	)
	return _drink_item_id


func _resolve_endo_drink_item_id() -> String:
	if _game_state == null:
		return ""
	if _drink_item_id != "" and _game_state.items.has(_drink_item_id):
		var cached: Dictionary = _game_state.items[_drink_item_id]
		if str((cached.get("properties", {}) as Dictionary).get(
				"source_contract", "")) == ENDO_DRINK_CONTRACT:
			return _drink_item_id
	_drink_item_id = ""
	var item_ids := _game_state.items.keys()
	item_ids.sort()
	for item_id_variant in item_ids:
		var item_id := str(item_id_variant)
		var item: Dictionary = _game_state.items[item_id_variant]
		if str((item.get("properties", {}) as Dictionary).get(
				"source_contract", "")) == ENDO_DRINK_CONTRACT:
			_drink_item_id = item_id
			break
	return _drink_item_id


func _endo_holds_drink() -> bool:
	var drink_id := _resolve_endo_drink_item_id()
	if drink_id == "" or not _game_state.characters.has("endo"):
		return false
	var item: Dictionary = _game_state.items[drink_id]
	return str(item.get("holder", "")) == "endo" \
		and str(item.get("location", "")) == "hand" \
		and _game_state.get_hand_items("endo").has(drink_id)


func _endo_drink_ground_position() -> Vector3:
	var drink_id := _resolve_endo_drink_item_id()
	if drink_id != "":
		return _game_state.items[drink_id].get(
			"position", _junction_anchor_position("DrinkPickup", JUNCTION_POS)) as Vector3
	if is_instance_valid(_drink_mesh):
		return _drink_mesh.global_position
	return _junction_anchor_position(
		"DrinkPickup", Vector3(JUNCTION_POS.x + 1.5, BELOW_Y + 0.5, -1.0))


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Render-only projection of GameState item ownership. Reparenting never decides
## whether the handoff happened; rollback can therefore put the same authored mesh
## back on its container without inventing or erasing the held item.
func _sync_endo_drink_presenter() -> void:
	if not is_instance_valid(_drink_mesh) or _game_state == null:
		return
	var drink_id := _resolve_endo_drink_item_id()
	if drink_id == "":
		# Once the canonical item has been consumed by the party-rest transaction, absence is the
		# intended projection. Before that transaction, absence means this fresh presenter has not
		# spawned/reattached its item yet and the authored container remains visible.
		var rest_authority := _junction_rest_authority_state()
		_drink_mesh.visible = not (_valid_junction_rest_authority(rest_authority) \
			and (bool(rest_authority.get("water_consumed", false)) \
				or _junction_rest_outcome_matches(rest_authority)))
		return
	var item: Dictionary = _game_state.items[drink_id]
	match str(item.get("location", "ground")):
		"ground":
			if is_instance_valid(_drink_home_parent) \
					and _drink_mesh.get_parent() != _drink_home_parent:
				_drink_mesh.reparent(_drink_home_parent, true)
			_drink_mesh.visible = true
			_drink_mesh.global_position = item.get("position", _drink_mesh.global_position) as Vector3
			_drink_mesh.rotation = _drink_home_rotation
			_drink_mesh.scale = _drink_home_scale
		"hand":
			var holder_id := str(item.get("holder", ""))
			var holder := get_game_state_character_node(holder_id)
			if holder == null:
				_drink_mesh.visible = false
				return
			if _drink_mesh.get_parent() != holder:
				_drink_mesh.reparent(holder, false)
			_drink_mesh.visible = true
			_drink_mesh.position = Vector3(0.0, 1.2, 0.3)
			_drink_mesh.rotation = Vector3.ZERO
			_drink_mesh.scale = _drink_home_scale
		_:
			_drink_mesh.visible = false

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
	enemy.hit_target.connect(_on_enemy_hit.bind(enemy))
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
		enemy: Enemy, mode: String, data: Dictionary, wake_radius: float, distracted := true,
		wake_cohort := "") -> void:
	_below_dormant_enemy_setups.append({
		"enemy": enemy,
		"mode": mode,
		"data": data,
		"wake_radius": wake_radius,
		"distracted": distracted,
		"wake_cohort": wake_cohort,
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
	# A linked pack is one readable simulation cohort. If the party crosses any
	# member's authored wake boundary, register the entire named cohort in the
	# same detection batch; waking only the nearer body leaves the visible
	# two-body Flure link lying about which pack is currently alive.
	var individually_waking := {}
	var waking_cohorts := {}
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
			individually_waking[enemy.get_instance_id()] = true
			var wake_cohort := str(setup.get("wake_cohort", ""))
			if not wake_cohort.is_empty():
				waking_cohorts[wake_cohort] = true
	if individually_waking.is_empty():
		return
	var remaining: Array[Dictionary] = []
	var waking: Array[Dictionary] = []
	for setup in _below_dormant_enemy_setups:
		var enemy = setup.get("enemy")
		if not is_instance_valid(enemy):
			continue
		var wake_cohort := str(setup.get("wake_cohort", ""))
		if individually_waking.has(enemy.get_instance_id()) \
				or (not wake_cohort.is_empty() and waking_cohorts.has(wake_cohort)):
			waking.append(setup)
		else:
			remaining.append(setup)
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
			_arm_below_fauna(
				enemy,
				data.get("anchor", enemy.position),
				float(data.get("radius", 2.0)),
				bool(setup.get("distracted", true))
			)
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
func _arm_below_fauna(enemy: Enemy, anchor: Vector3, radius: float, distracted := true) -> void:
	enemy.set_detection_targets(["aster", "peris"])
	enemy.set_roam(anchor, radius)
	if _game_state != null:
		_game_state.set_character_distracted(enemy.char_id, distracted)

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

func _build_route_flure_station(parent: Node3D, index: int, pos: Vector3) -> Flure:
	var target_ids := ["route_enemy_%d_0" % index, "route_enemy_%d_1" % index]
	var flure := Flure.new()
	flure.name = "RouteFlure%d" % index
	flure.authority_id = _route_flure_authority_id(index)
	flure.configure(_game_state, pos, target_ids, 22.0, 1.8, Color(0.58, 0.92, 0.22))
	flure.one_shot = false
	flure.lure_duration = ROUTE_FLURE_DURATION
	flure.settle_pos = _route_flure_settle_position(index, pos)
	flure.description = "Prime Flure %d" % (index + 1)
	flure.consequence_preview = "Pulls linked Pack %d for %d seconds; inner reach remains." % [
		index + 1, int(ROUTE_FLURE_DURATION),
	]
	flure.tutorial_label = "PRIME PACK %d / %ds" % [index + 1, int(ROUTE_FLURE_DURATION)]
	flure.set_enemy_resolver(_resolve_route_enemy)
	parent.add_child(flure)
	register_preview_interactable(flure)
	_require_interactable_character(flure, "peris")
	flure.set_interaction_enabled(false)
	flure.flure_activated.connect(_on_route_flure_activated.bind(index))
	_route_flure_interactables.append(flure)
	if is_instance_valid(flure._glow):
		flure._glow.name = "RouteFlureVisual%d" % index
		_route_flure_meshes.append(flure._glow)
	var status := Label3D.new()
	status.name = "RouteFlureStatus%d" % index
	status.text = "PACK %d / READY" % (index + 1)
	status.font_size = 44
	status.pixel_size = 0.0038
	status.modulate = Color(0.66, 0.92, 0.42)
	status.outline_modulate = Color(0.01, 0.015, 0.01, 0.96)
	status.outline_size = 9
	status.position = Vector3(0.0, 1.42, 0.0)
	status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status.no_depth_test = true
	status.set_meta("overlay_semantic", "state")
	flure.add_child(status)
	_route_flure_countdown_labels.append(status)
	return flure


func _route_flure_authority_id(index: int) -> String:
	return "elevator_route_flure_%d" % index

func _resolve_route_enemy(enemy_id: String) -> Enemy:
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.char_id == enemy_id:
			return enemy
	return null

func _route_flure_effect_state(index: int) -> Dictionary:
	if index < 0 or index >= ROUTE_BEAT_COUNT:
		return {}
	if index < _route_flure_interactables.size():
		var flure := _route_flure_interactables[index] as Flure
		if is_instance_valid(flure):
			return flure.get_effect_state()
	if _game_state == null or not _game_state.has_method("get_world_state"):
		return {}
	var value: Variant = _game_state.get_world_state(
		"gameplay:flure:%s" % _route_flure_authority_id(index), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _route_flure_same_activation(history: Dictionary, state: Dictionary) -> bool:
	var history_serial := int(history.get("source_activation_serial", 0))
	var state_serial := int(state.get("activation_serial", 0))
	if history_serial > 0 and state_serial > 0:
		return history_serial == state_serial
	return is_equal_approx(
		float(history.get("source_start_tick", -2.0)),
		float(state.get("start_tick", -1.0)))


## Reconcile durable route history against the physical Flure record. The source's start tick is the
## readable timing fact; Flure's monotonic activation serial is the identity. Elevator never copies
## its active phase or deadline into parallel authority.
func _reconcile_route_flure_history_from_source(index: int) -> Dictionary:
	var state := _route_flure_effect_state(index)
	var start_tick := float(state.get("start_tick", -1.0))
	if start_tick < 0.0:
		return {"changed": false, "successful": false, "state": state, "report": {}}
	var previous: Dictionary = _route_flure_window_history[index]
	if _route_flure_same_activation(previous, state):
		return {
			"changed": false,
			"successful": bool(previous.get("successful", false)),
			"state": state,
			"report": (state.get("last_activation_report", {}) as Dictionary).duplicate(true),
		}
	var report := (state.get("last_activation_report", {}) as Dictionary).duplicate(true)
	var linked_count := (state.get("linked_target_ids", []) as Array).size()
	var pulled := int(report.get("pulled", (report.get("pulled_ids", []) as Array).size()))
	var successful := linked_count > 0 and pulled >= linked_count
	_route_flure_window_history[index] = {
		"source_start_tick": start_tick,
		"source_activation_serial": int(state.get("activation_serial", 0)),
		"successful": successful,
		"used": false,
		# A failed signal is accounted immediately. A successful but unused window is accounted
		# only after the source itself leaves ACTIVE.
		"closed_accounted": not successful,
	}
	if successful:
		_route_flure_activation_counts[index] += 1
	else:
		_route_flure_failed_counts[index] += 1
		_route_wasted_flure_windows += 1
	return {
		"changed": true,
		"successful": successful,
		"state": state,
		"report": report,
	}


func _route_flure_live_window_start(index: int) -> float:
	var state := _route_flure_effect_state(index)
	if str(state.get("phase", Flure.PHASE_READY)) != Flure.PHASE_ACTIVE:
		return -1.0
	var source_start := float(state.get("start_tick", -1.0))
	var history: Dictionary = _route_flure_window_history[index]
	if not bool(history.get("successful", false)) \
			or not _route_flure_same_activation(history, state):
		return -1.0
	return source_start


func _mark_route_flure_window_used(index: int, source_start: float) -> void:
	if index < 0 or index >= ROUTE_BEAT_COUNT:
		return
	var history: Dictionary = _route_flure_window_history[index]
	var state := _route_flure_effect_state(index)
	if not bool(history.get("successful", false)) \
			or not is_equal_approx(
				float(history.get("source_start_tick", -2.0)), source_start) \
			or not _route_flure_same_activation(history, state):
		return
	history["used"] = true
	_route_flure_window_history[index] = history


func _route_flure_window_used(index: int) -> bool:
	return index >= 0 and index < ROUTE_BEAT_COUNT \
		and bool(_route_flure_window_history[index].get("used", false))


func _account_closed_route_flure_window(index: int) -> bool:
	if index < 0 or index >= ROUTE_BEAT_COUNT:
		return false
	var state := _route_flure_effect_state(index)
	var history: Dictionary = _route_flure_window_history[index]
	if history.is_empty() or bool(history.get("closed_accounted", false)) \
			or str(state.get("phase", Flure.PHASE_READY)) == Flure.PHASE_ACTIVE \
			or not _route_flure_same_activation(history, state):
		return false
	if bool(history.get("successful", false)) and not bool(history.get("used", false)):
		_route_wasted_flure_windows += 1
	history["closed_accounted"] = true
	_route_flure_window_history[index] = history
	return true


func _on_route_flure_activated(_pulled: int, index: int) -> void:
	if index < 0 or index >= ROUTE_BEAT_COUNT:
		return
	var reconciliation := _reconcile_route_flure_history_from_source(index)
	var report: Dictionary = reconciliation.get("report", {}) as Dictionary
	var successful := bool(reconciliation.get("successful", false))
	var linked_count := (
		(reconciliation.get("state", {}) as Dictionary).get(
			"linked_target_ids", []) as Array).size()
	var pulled := int(report.get("pulled", (report.get("pulled_ids", []) as Array).size()))
	_publish_elevator_runtime_authority()
	_rearm_route_flure_feedback_from_source(index)
	_apply_route_flure_presentation(index)
	if successful:
		_set_route_causal_link_state(index, CausalFeedbackLink.MODE_ACTIVE, true, true)
		return
	_set_route_causal_link_report(index, report)
	var committed_count := (report.get("committed_ids", []) as Array).size()
	if committed_count > 0:
		_hud.show_message(
			"Flure %d was too late: %d/%d guards were already committed. Break contact, let the pack return, then signal before it acquires either character." % [
				index + 1, linked_count - pulled, linked_count,
			],
			3.6
		)
	else:
		_hud.show_message(
			"Flure %d found no complete linked pack in range. Follow Aster's links, check the pack's position, then retry after rearming." % (index + 1),
			3.2
		)


## This callback owns no gameplay phase. It is a reconstructible observer scheduled from the exact
## Flure deadline and only records whether that source-owned window was used before it closed.
func _rearm_route_flure_feedback_from_source(index: int) -> void:
	if _scheduler == null or index < 0 or index >= ROUTE_BEAT_COUNT:
		return
	var tag := "route_flure_feedback_%d" % index
	_scheduler.cancel_tag(tag)
	var state := _route_flure_effect_state(index)
	if str(state.get("phase", Flure.PHASE_READY)) != Flure.PHASE_ACTIVE:
		return
	var end_tick := float(state.get("end_tick", -1.0))
	if end_tick < 0.0:
		return
	# Flure's own completion runs at end_tick. The tiny ordered observer offset guarantees this
	# callback sees the source's READY phase regardless of callback insertion order after restore.
	_scheduler.schedule_at(
		maxf(_scheduler.get_current_tick() + 0.000001, end_tick + 0.000001),
		_on_route_flure_source_deadline.bind(
			index,
			float(state.get("start_tick", -1.0)),
			int(state.get("activation_serial", 0))),
		tag
	)


func _on_route_flure_source_deadline(
		index: int,
		expected_start_tick: float,
		expected_activation_serial: int
	) -> void:
	var state := _route_flure_effect_state(index)
	if not is_equal_approx(
			float(state.get("start_tick", -2.0)), expected_start_tick) \
			or (
				expected_activation_serial > 0
				and int(state.get("activation_serial", 0)) != expected_activation_serial
			):
		return
	if str(state.get("phase", Flure.PHASE_READY)) == Flure.PHASE_ACTIVE:
		_rearm_route_flure_feedback_from_source(index)
		return
	var newly_closed := _account_closed_route_flure_window(index)
	if newly_closed:
		_publish_elevator_runtime_authority()
	_apply_route_flure_presentation(index)
	var history: Dictionary = _route_flure_window_history[index]
	if newly_closed and bool(history.get("successful", false)) \
			and not bool(history.get("used", false)):
		_hud.show_message(
			"Pack %d's Flure window closed; the watch is returning." % (index + 1),
			2.4
		)


func _restore_route_flure_feedback_from_source() -> bool:
	var history_changed := false
	for index in range(ROUTE_BEAT_COUNT):
		var reconciliation := _reconcile_route_flure_history_from_source(index)
		history_changed = bool(reconciliation.get("changed", false)) or history_changed
		history_changed = _account_closed_route_flure_window(index) or history_changed
		_apply_route_flure_presentation(index)
		_rearm_route_flure_feedback_from_source(index)
	return history_changed


func _apply_route_flure_presentation(index: int) -> void:
	var status := _route_flure_status(index)
	if status == null:
		return
	var state := _route_flure_effect_state(index)
	var phase := str(state.get("phase", Flure.PHASE_READY))
	var history: Dictionary = _route_flure_window_history[index]
	var same_source := _route_flure_same_activation(history, state)
	if phase == Flure.PHASE_ACTIVE and same_source \
			and bool(history.get("successful", false)):
		var remaining := maxf(
			0.0, float(state.get("end_tick", -1.0)) - _scheduler.get_current_tick())
		status.text = "PACK %d / %ds / PULLING" % [index + 1, int(ceil(remaining))]
		status.modulate = Color(1.0, 0.64, 0.18) \
			if remaining <= 4.0 else Color(0.82, 1.0, 0.36)
		_set_route_causal_link_state(
			index,
			CausalFeedbackLink.MODE_WARNING \
				if remaining <= 4.0 else CausalFeedbackLink.MODE_ACTIVE,
			true,
			false
		)
		return
	if phase == Flure.PHASE_ACTIVE and same_source:
		var report: Dictionary = state.get("last_activation_report", {}) as Dictionary
		var pulled := int(report.get("pulled", 0))
		var linked_count := (state.get("linked_target_ids", []) as Array).size()
		if not (report.get("committed_ids", []) as Array).is_empty():
			status.text = "PACK %d / %s / TOO LATE" % [
				index + 1,
				"PARTIAL %d/%d" % [pulled, linked_count] if pulled > 0 else "ENGAGED",
			]
		else:
			status.text = "PACK %d / NO PACK IN RANGE" % (index + 1)
		status.modulate = Color(1.0, 0.38, 0.16)
		_set_route_causal_link_report(index, report)
		return
	if same_source and bool(history.get("successful", false)):
		if bool(history.get("used", false)):
			status.text = "PACK %d / ROUTE WINDOW USED" % (index + 1)
			status.modulate = Color(0.66, 0.92, 0.42)
			_set_route_causal_link_state(index, CausalFeedbackLink.MODE_READY, false, false)
		else:
			status.text = "PACK %d / WATCH RETURNED" % (index + 1)
			status.modulate = Color(1.0, 0.42, 0.18)
			_set_route_causal_link_state(index, CausalFeedbackLink.MODE_FAILED, false, false)
		return
	status.text = "PACK %d / READY" % (index + 1)
	status.modulate = Color(0.66, 0.92, 0.42)
	_set_route_causal_link_state(index, CausalFeedbackLink.MODE_READY, false, false)

func _route_flure_status(index: int) -> Label3D:
	if index < 0 or index >= _route_flure_countdown_labels.size():
		return null
	var label := _route_flure_countdown_labels[index]
	return label if is_instance_valid(label) else null

func _update_route_flure_feedback() -> void:
	for index in range(ROUTE_BEAT_COUNT):
		_apply_route_flure_presentation(index)

func _set_route_causal_link_state(index: int, mode: String, latched: bool, flash: bool) -> void:
	for link_variant in _route_causal_links.get(index, []):
		if not is_instance_valid(link_variant):
			continue
		var link := link_variant as CausalFeedbackLink
		if not is_instance_valid(link):
			continue
		link.set_feedback_mode(mode)
		link.set_latched(latched)
		if flash:
			link.flash(0.8, 1.2)

func _set_route_causal_link_report(index: int, report: Dictionary) -> void:
	var pulled_ids := report.get("pulled_ids", []) as Array
	var enemies := _route_flure_enemy_groups.get(index, []) as Array
	var links := _route_causal_links.get(index, []) as Array
	for local_i in range(mini(enemies.size(), links.size())):
		var enemy := enemies[local_i] as Enemy
		var link := links[local_i] as CausalFeedbackLink
		if not is_instance_valid(enemy) or not is_instance_valid(link):
			continue
		var was_pulled := enemy.char_id in pulled_ids
		link.set_feedback_mode(CausalFeedbackLink.MODE_ACTIVE if was_pulled else CausalFeedbackLink.MODE_FAILED)
		link.set_latched(was_pulled)
		link.flash(0.8, 1.2)

## GameState is the single source of truth for party HP. Every hp change (enemy strikes apply it via
## _resolve_strike's adjust_stat; iron patches via adjust_stat) fans out here to drive the HUD, the
## downed portrait, and game-over — so no damage source maintains a parallel counter.
func _on_party_stat_changed(id: String, stat: String, value: float) -> void:
	if not GAUNTLET_INTRO_REQUIRED_MEMBERS.has(id):
		return
	if stat == "stamina":
		if _hud != null:
			_hud.set_portrait_stat(id, "sta", value)
		return
	if stat != "hp":
		return
	if _hud != null:
		_hud.set_portrait_stat(id, "hp", value)
		if value <= 0.0:
			_hud.set_portrait_status(id, "downed")
	var defeat_roster: Array[String] = []
	defeat_roster.assign(
		GAUNTLET_INTRO_REQUIRED_MEMBERS \
		if _current_step == "gauntlet" else ["aster", "peris"])
	var whole_roster_downed := true
	for member_id in defeat_roster:
		if _game_state == null or not _game_state.characters.has(member_id) \
				or _game_state.get_stat(member_id, "hp") > 0.0:
			whole_roster_downed = false
			break
	if not _game_over and _current_step == "gauntlet" and value <= 0.0:
		_request_gauntlet_reset(
			0.1 if whole_roster_downed else 0.4,
			"whole_party_downed" if whole_roster_downed else "%s_downed" % id)
		return
	if not _game_over and whole_roster_downed:
		_start_game_over()

## The strike already applied data-layer damage; present one consistent source-labelled response in the world/HUD.
func _on_enemy_hit(target_id: String, damage: float, source_enemy: Enemy = null) -> void:
	if _game_over:
		return
	var source_id := source_enemy.char_id if is_instance_valid(source_enemy) else "unknown_enemy"
	var source_label := "IMPACT"
	var failure_class := "control_error"
	var correction := "Move after the windup and clear the committed strike point."
	if source_id.begins_with("route_enemy_"):
		var parts := source_id.split("_")
		var beat_index := int(parts[2]) if parts.size() > 2 else -1
		if beat_index >= 0 and beat_index < ROUTE_BEAT_COUNT:
			if _route_flure_live_window_start(beat_index) >= 0.0:
				source_label = "PACK %d / INNER REACH" % (beat_index + 1)
				correction = "Give the lured pack space; the Flure shrinks reach, not to zero."
			elif _route_flure_activation_counts[beat_index] > 0:
				source_label = "PACK %d / WINDOW CLOSED" % (beat_index + 1)
				failure_class = "timing_error"
				correction = "Prime this Flure only after both characters are staged to cross."
			else:
				source_label = "PACK %d / NO SIGNAL" % (beat_index + 1)
				failure_class = "model_error"
				correction = "Use Aster's links to prime the Flure connected to this pack."
			_set_route_causal_link_state(beat_index, CausalFeedbackLink.MODE_FAILED, false, true)
		_route_enemy_damage_taken += damage
	_route_failure_provenance.append({
		"victim_id": target_id,
		"source_kind": "enemy",
		"source_id": source_id,
		"source_position": source_enemy.global_position if is_instance_valid(source_enemy) else Vector3.ZERO,
		"amount": damage,
		"hp_after": _game_state.get_stat(target_id, "hp"),
		"impact_tick": _scheduler.get_current_tick(),
		"failure_class": failure_class,
		"correction": correction,
	})
	_show_party_damage_feedback(target_id, damage, source_label, Color(1.0, 0.28, 0.18))
	if _current_step == "route_choice":
		_publish_elevator_runtime_authority()
	if _current_step == "gauntlet" and not _gauntlet_resetting:
		# A surviving impact costs persistent HP but does not erase the attempt; only
		# a downed party member invokes the refuge checkpoint.
		if _game_state.get_stat(target_id, "hp") <= 0.0:
			_request_gauntlet_reset(0.4, "%s_downed" % target_id)
		else:
			_hud.show_message(
				"%s absorbed the hit and can continue; that HP will not reset." % target_id.capitalize(),
				2.2
			)

## Iron is a cadenced simulation hazard, not a render-frame drain. One authoritative tick replaces dozens of
## fractional stat writes per second, keeping replay/event/HUD work bounded while every hit names its source.
func _arm_iron_hazard_tick(absolute_tick := -1.0) -> void:
	if _iron_hazard_tick_armed or _scheduler == null or _iron_patches.is_empty():
		return
	_iron_hazard_tick_armed = true
	var now := float(_scheduler.get_current_tick())
	_iron_hazard_next_tick = float(absolute_tick)
	if _iron_hazard_next_tick < 0.0:
		_iron_hazard_next_tick = now + IRON_DAMAGE_INTERVAL
	_iron_hazard_next_tick = maxf(now + 0.000001, _iron_hazard_next_tick)
	_scheduler.schedule_at(_iron_hazard_next_tick, _iron_hazard_tick, IRON_HAZARD_TAG)
	_publish_elevator_runtime_authority()

func _iron_hazard_tick() -> void:
	_iron_hazard_tick_armed = false
	_iron_hazard_next_tick = -1.0
	if _game_over or _scheduler == null or _iron_patches.is_empty():
		_publish_elevator_runtime_authority()
		return
	for cid in ["aster", "peris"]:
		if not _game_state.characters.has(cid) or _game_state.get_stat(cid, "hp") <= 0.0:
			continue
		var iron_index := _iron_patch_index(_game_state.get_position(cid))
		if iron_index >= 0:
			var hp_before := _game_state.get_stat(cid, "hp")
			_game_state.adjust_stat(cid, "hp", -IRON_DAMAGE_PER_TICK)
			var hp_after := _game_state.get_stat(cid, "hp")
			var applied_damage := maxf(0.0, hp_before - hp_after)
			if _current_step == "route_choice":
				_route_iron_damage_taken += applied_damage
			_route_failure_provenance.append({
				"victim_id": cid,
				"source_kind": "iron_field",
				"source_id": "iron_field_%d" % (iron_index + 1),
				"source_position": (_iron_patches[iron_index] as Dictionary).get("pos", Vector3.ZERO),
				"amount": applied_damage,
				"hp_before": hp_before,
				"hp_after": hp_after,
				"impact_tick": _scheduler.get_current_tick(),
				"failure_class": "prediction_error",
				"correction": "Use Peris's exact footprint and keep the command preview outside it.",
			})
			_show_party_damage_feedback(
				cid,
				applied_damage,
				"IRON FIELD %d" % (iron_index + 1),
				Color(1.0, 0.32, 0.08)
			)
			if not bool(_iron_contact_warning_shown.get(cid, false)):
				_iron_contact_warning_shown[cid] = true
				_hud.show_message(
					"%s is inside IRON FIELD %d — move outside Peris's marked footprint." % [
						cid.capitalize(), iron_index + 1,
					],
					2.2
				)
	_arm_iron_hazard_tick()


func _route_progress_authority_state() -> Dictionary:
	return {
		"reads_resolved": _route_reads_resolved.duplicate(),
		"overlays_available": _elevator_overlays_available,
		"overlay_states": _elevator_overlay_states.duplicate(),
		"lane": _route_lane,
		"beats_crossed": _route_beats_crossed.duplicate(),
		"beat_lanes": _route_beat_lanes.duplicate(),
		"beat_character_lanes": _route_beat_character_lanes.duplicate(true),
		"beat_character_windows": _route_beat_character_windows.duplicate(true),
		"beat_character_window_sources": \
			_route_beat_character_window_sources.duplicate(true),
		"started_tick": _route_started_tick,
		"finished_tick": _route_finished_tick,
		"iron_damage_taken": _route_iron_damage_taken,
		"enemy_damage_taken": _route_enemy_damage_taken,
		"wasted_flure_windows": _route_wasted_flure_windows,
		"failure_provenance": _route_failure_provenance.duplicate(true),
		"flure_activation_counts": _route_flure_activation_counts.duplicate(),
		"flure_failed_counts": _route_flure_failed_counts.duplicate(),
		"flure_window_history": _route_flure_window_history.duplicate(true),
	}


func _reset_route_progress_for_snapshot() -> void:
	_set_iron_route_risk_learned(false)
	_route_reads_resolved = {"aster": false, "peris": false}
	_elevator_overlays_available = false
	_elevator_overlay_states = {"aster": false, "peris": false}
	_route_lane = ""
	_route_beats_crossed = [false, false, false]
	_route_beat_lanes = ["", "", ""]
	_route_beat_character_lanes = [{}, {}, {}]
	_route_beat_character_windows = [{}, {}, {}]
	_route_beat_character_window_sources = [{}, {}, {}]
	_route_started_tick = -1.0
	_route_finished_tick = -1.0
	_route_iron_damage_taken = 0.0
	_route_enemy_damage_taken = 0.0
	_route_wasted_flure_windows = 0
	_route_failure_provenance.clear()
	_route_flure_activation_counts = [0, 0, 0]
	_route_flure_failed_counts = [0, 0, 0]
	_route_flure_window_history = [{}, {}, {}]


func _restore_route_progress_from_authority(
		saved: Dictionary, saved_version: int) -> void:
	_reset_route_progress_for_snapshot()
	if saved_version < ELEVATOR_RUNTIME_AUTHORITY_VERSION:
		_route_iron_damage_taken = maxf(
			0.0, float(saved.get("route_iron_damage_taken", 0.0)))
		# Legacy records predate route knowledge. Infer only the unavoidable Aster read for a save
		# already inside the fork; never invent Peris's optional footprint knowledge or mastery.
		if _current_step in ["route_read_circuit", "route_choice"]:
			_elevator_overlays_available = true
			_elevator_overlay_states["aster"] = true
			_route_reads_resolved["aster"] = true
		_apply_route_knowledge_presentation()
		return
	var progress_v: Variant = saved.get("route_progress", {})
	if not (progress_v is Dictionary):
		_apply_route_knowledge_presentation()
		return
	var progress := progress_v as Dictionary
	var reads: Dictionary = progress.get("reads_resolved", {}) as Dictionary
	var overlays: Dictionary = progress.get("overlay_states", {}) as Dictionary
	for member_id in ["aster", "peris"]:
		_route_reads_resolved[member_id] = bool(reads.get(member_id, false))
		_elevator_overlay_states[member_id] = bool(overlays.get(member_id, false))
	_elevator_overlays_available = bool(progress.get("overlays_available", false))
	if not _elevator_overlays_available:
		_elevator_overlay_states = {"aster": false, "peris": false}
	var saved_lane := str(progress.get("lane", ""))
	_route_lane = saved_lane if saved_lane in ["", "flure", "iron", "hybrid"] else ""
	var beats: Array = progress.get("beats_crossed", []) as Array
	var beat_lanes: Array = progress.get("beat_lanes", []) as Array
	var character_lanes: Array = progress.get("beat_character_lanes", []) as Array
	var character_windows: Array = progress.get("beat_character_windows", []) as Array
	var window_sources: Array = (
		progress.get("beat_character_window_sources", []) as Array)
	var activation_counts: Array = progress.get("flure_activation_counts", []) as Array
	var failed_counts: Array = progress.get("flure_failed_counts", []) as Array
	var window_history: Array = progress.get("flure_window_history", []) as Array
	for index in range(ROUTE_BEAT_COUNT):
		_route_beats_crossed[index] = bool(beats[index]) if index < beats.size() else false
		var beat_lane := str(beat_lanes[index]) if index < beat_lanes.size() else ""
		_route_beat_lanes[index] = beat_lane \
			if beat_lane in ["", "flure", "iron", "mixed"] else ""
		var saved_character_lanes: Dictionary = character_lanes[index] as Dictionary \
			if index < character_lanes.size() and character_lanes[index] is Dictionary else {}
		var saved_character_windows: Dictionary = character_windows[index] as Dictionary \
			if index < character_windows.size() and character_windows[index] is Dictionary else {}
		var saved_window_sources: Dictionary = window_sources[index] as Dictionary \
			if index < window_sources.size() and window_sources[index] is Dictionary else {}
		for member_id in ["aster", "peris"]:
			if saved_character_lanes.has(member_id):
				var member_lane := str(saved_character_lanes[member_id])
				if member_lane in ["flure", "iron", "mixed"]:
					_route_beat_character_lanes[index][member_id] = member_lane
			if saved_character_windows.has(member_id):
				_route_beat_character_windows[index][member_id] = bool(
					saved_character_windows[member_id])
				_route_beat_character_window_sources[index][member_id] = float(
					saved_window_sources.get(member_id, -1.0))
		_route_flure_activation_counts[index] = maxi(
			0, int(activation_counts[index]) if index < activation_counts.size() else 0)
		_route_flure_failed_counts[index] = maxi(
			0, int(failed_counts[index]) if index < failed_counts.size() else 0)
		if index < window_history.size() and window_history[index] is Dictionary:
			var history := window_history[index] as Dictionary
			var source_start := float(history.get("source_start_tick", -1.0))
			if source_start >= 0.0:
				_route_flure_window_history[index] = {
					"source_start_tick": source_start,
					"source_activation_serial": maxi(
						0, int(history.get("source_activation_serial", 0))),
					"successful": bool(history.get("successful", false)),
					"used": bool(history.get("used", false)),
					"closed_accounted": bool(history.get("closed_accounted", false)),
				}
	_route_started_tick = float(progress.get("started_tick", -1.0))
	_route_finished_tick = float(progress.get("finished_tick", -1.0))
	_route_iron_damage_taken = maxf(0.0, float(progress.get("iron_damage_taken", 0.0)))
	_route_enemy_damage_taken = maxf(0.0, float(progress.get("enemy_damage_taken", 0.0)))
	_route_wasted_flure_windows = maxi(
		0, int(progress.get("wasted_flure_windows", 0)))
	for entry_v in progress.get("failure_provenance", []) as Array:
		if entry_v is Dictionary:
			_route_failure_provenance.append((entry_v as Dictionary).duplicate(true))
	_set_iron_route_risk_learned(bool(_route_reads_resolved.get("peris", false)))
	_apply_route_knowledge_presentation()


func _apply_route_knowledge_presentation() -> void:
	if _elevator_overlay_ui != null:
		_elevator_overlay_ui.visible = _elevator_overlays_available
	_apply_elevator_overlay_visibility()
	_refresh_elevator_overlay_ui()


func _publish_elevator_runtime_authority() -> void:
	if _restoring_elevator_runtime_authority or _game_state == null \
			or not _game_state.has_method("set_world_state"):
		return
	_refresh_gauntlet_run_authority_fields()
	_game_state.set_world_state(ELEVATOR_RUNTIME_AUTHORITY_KEY, {
		"version": ELEVATOR_RUNTIME_AUTHORITY_VERSION,
		"contract": ELEVATOR_RUNTIME_AUTHORITY_CONTRACT,
		"bridge_collapse": _bridge_collapse_authority.duplicate(true),
		"iron_next_tick": _iron_hazard_next_tick,
		"iron_contact_warning_shown": _iron_contact_warning_shown.duplicate(true),
		"route_progress": _route_progress_authority_state(),
		"wreckage_armed": _wreckage_armed,
		"wreckage_clear_in_progress": _wreckage_clear_in_progress,
		"wreckage_cleared": _wreckage_cleared,
		"wreckage_solo_attempted": _wreckage_solo_attempted,
		"wreckage_failure_active": _wreckage_failure_active,
		"wreckage_alert_target": _wreckage_alert_target,
		"wreckage_rearm_deadline": _wreckage_rearm_deadline,
		"gauntlet_intro": _gauntlet_intro_authority.duplicate(true),
		"gauntlet_run": _gauntlet_run_authority.duplicate(true),
	})


## Sequence-local callbacks are not serialized by EventScheduler. Rebuild the remaining iron cadence
## and noisy-failure cooldown from GameState, while deriving the main clear transition from PartyGate3D.
func on_game_state_snapshot_restored() -> void:
	if _game_state == null or _scheduler == null:
		return
	_restoring_elevator_runtime_authority = true
	_scheduler.cancel_tag(IRON_HAZARD_TAG)
	_scheduler.cancel_tag("wreckage_clear")
	_scheduler.cancel_tag("wreckage_rearm")
	_scheduler.cancel_tag("bridge_fall")
	_scheduler.cancel_tag("fall_landed")
	_scheduler.cancel_tag("fallen")
	_scheduler.cancel_tag("night_watch")
	_scheduler.cancel_tag("dawn")
	_scheduler.cancel_tag("morning")
	_scheduler.cancel_tag(JUNCTION_REST_COMMIT_TAG)
	_scheduler.cancel_tag(JUNCTION_REST_DAWN_TAG)
	_scheduler.cancel_tag(JUNCTION_REST_FLICKER_TAG)
	for route_index in range(ROUTE_BEAT_COUNT):
		_scheduler.cancel_tag("route_flure_feedback_%d" % route_index)
		_scheduler.cancel_tag("route_flure_failed_feedback_%d" % route_index)
	_cancel_gauntlet_runtime_callbacks()
	_reset_bridge_collapse_presentation_for_restore()
	_iron_hazard_tick_armed = false
	_iron_hazard_next_tick = -1.0
	_iron_contact_warning_shown.clear()
	_wreckage_rearm_deadline = -1.0
	var saved: Variant = _game_state.get_world_state(ELEVATOR_RUNTIME_AUTHORITY_KEY, {}) \
		if _game_state.has_method("get_world_state") else {}
	var saved_version := int(saved.get("version", 0)) if saved is Dictionary else 0
	var supported_record := saved is Dictionary and saved_version in [
		1, 2, 3, 4, ELEVATOR_RUNTIME_AUTHORITY_VERSION,
	] and (
		saved_version < ELEVATOR_RUNTIME_AUTHORITY_VERSION \
		or str(saved.get("contract", "")) == ELEVATOR_RUNTIME_AUTHORITY_CONTRACT
	)
	if supported_record:
		_bridge_collapse_authority = (saved.get(
			"bridge_collapse", {}) as Dictionary).duplicate(true) \
			if saved_version >= 2 else {}
		_iron_hazard_next_tick = float(saved.get("iron_next_tick", -1.0))
		_iron_contact_warning_shown = (
			saved.get("iron_contact_warning_shown", {}) as Dictionary).duplicate(true)
		_restore_route_progress_from_authority(saved, saved_version)
		_wreckage_armed = bool(saved.get("wreckage_armed", false))
		_wreckage_clear_in_progress = bool(saved.get("wreckage_clear_in_progress", false))
		_wreckage_cleared = bool(saved.get("wreckage_cleared", false))
		_wreckage_solo_attempted = bool(saved.get("wreckage_solo_attempted", false))
		_wreckage_failure_active = bool(saved.get("wreckage_failure_active", false))
		_wreckage_alert_target = str(saved.get("wreckage_alert_target", ""))
		_wreckage_rearm_deadline = float(saved.get("wreckage_rearm_deadline", -1.0))
		var saved_gauntlet_v: Variant = saved.get("gauntlet_intro", {}) \
			if saved_version >= 3 else {}
		_gauntlet_intro_authority = (
			(saved_gauntlet_v as Dictionary).duplicate(true)
			if saved_gauntlet_v is Dictionary \
				and _valid_gauntlet_intro_authority(saved_gauntlet_v as Dictionary)
			else {}
		)
		var saved_gauntlet_run_v: Variant = saved.get("gauntlet_run", {}) \
			if saved_version >= 4 else {}
		_gauntlet_run_authority = (
			(saved_gauntlet_run_v as Dictionary).duplicate(true)
			if _valid_gauntlet_run_authority(saved_gauntlet_run_v)
			else {}
		)
	else:
		# Absence represents a snapshot before these scene-local phases began.
		_bridge_collapse_authority.clear()
		_restore_route_progress_from_authority({}, 0)
		_wreckage_clear_in_progress = false
		_wreckage_cleared = false
		_wreckage_solo_attempted = false
		_wreckage_failure_active = false
		_wreckage_alert_target = ""
		_gauntlet_intro_authority.clear()
		_gauntlet_run_authority.clear()

	var gate := _wreckage_gate as PartyGate3D
	var gate_phase := PartyGate3D.PHASE_CLOSED
	if gate != null:
		gate_phase = str(gate.get_authority_state().get("phase", PartyGate3D.PHASE_CLOSED))
	match gate_phase:
		PartyGate3D.PHASE_OPENING:
			_wreckage_armed = true
			_wreckage_clear_in_progress = true
			_wreckage_cleared = false
			_wreckage_failure_active = false
			if is_instance_valid(_wreckage_interactable):
				_wreckage_interactable.set_interaction_enabled(false)
			if is_instance_valid(_player):
				_player.set_move_enabled(false)
		PartyGate3D.PHASE_OPEN:
			_wreckage_armed = true
			_wreckage_clear_in_progress = true
			_wreckage_cleared = false
			_wreckage_failure_active = false
			if is_instance_valid(_wreckage_interactable):
				_wreckage_interactable.set_interaction_enabled(false)
			call_deferred("_finish_wreckage_clear")
		_:
			_wreckage_clear_in_progress = false
			_wreckage_cleared = false
			if _current_step == "route_choice":
				_wreckage_armed = true
			if is_instance_valid(_wreckage_interactable):
				_wreckage_interactable.set_interaction_enabled(
					_wreckage_armed and not _wreckage_failure_active)

	if _wreckage_failure_active and _wreckage_rearm_deadline >= 0.0:
		_scheduler.schedule_at(
			maxf(_scheduler.get_current_tick() + 0.000001, _wreckage_rearm_deadline),
			_rearm_wreckage_after_solo_failure,
			"wreckage_rearm")
	if not _iron_patches.is_empty():
		if _iron_hazard_next_tick < 0.0:
			_iron_hazard_next_tick = _scheduler.get_current_tick() + IRON_DAMAGE_INTERVAL
		_arm_iron_hazard_tick(_iron_hazard_next_tick)
	var route_history_reconciled := _restore_route_flure_feedback_from_source()
	var bridge_migrated := _restore_bridge_collapse_from_authority(saved_version)
	_restoring_elevator_runtime_authority = false
	_restore_elevator_source_authority()
	# Endo's entrance and water handoff are reconstructed from the saved semantic
	# phase, roster, movement, item hands, and timed mechanism phase. Authored nodes
	# only mirror those records; repeated attachment issues no movement command.
	_configure_endo_handoff_presenter()
	_wire_endo_handoff_signals()
	_sync_elevator_guard_presence_from_roster()
	_set_endo_presenter_present(_game_state.characters.has("endo"), true)
	if _current_step in ["gauntlet", "complete"]:
		_ensure_endo_gauntlet_party_ui()
		_reattach_saved_gauntlet_enemies()
	_restore_portable_elevator_control_state()
	_endo_entry_dialogue_started = false
	_endo_delivery_dialogue_started = false
	_restore_junction_rest_authority()
	_sync_endo_drink_presenter()
	if _current_step == "endo_enters":
		_reset_endo_entry_dialogue_for_restore()
		var entry_state := _endo_entry_authority_state()
		if _valid_endo_entry_authority(entry_state) \
				and str(entry_state.get("phase", "")) == ENDO_ENTRY_PHASE_ARRIVED \
				and _game_state.characters.has("endo") \
				and not _game_state.is_moving("endo") \
				and _horizontal_distance(
					_game_state.get_position("endo"),
					GameEvent.arr_to_v3(entry_state.get("destination", []))) \
					<= ENDO_ENTRY_RADIUS:
			call_deferred("_start_endo_entry_dialogue")
	if _current_step == "endo_delivered" and _endo_holds_drink():
		call_deferred("_start_endo_delivery_dialogue")
	if _current_step in ["gauntlet", "complete"]:
		call_deferred("_restore_gauntlet_after_snapshot")
	if bridge_migrated or route_history_reconciled \
			or (supported_record and saved_version < ELEVATOR_RUNTIME_AUTHORITY_VERSION):
		_publish_elevator_runtime_authority()


func _reset_endo_entry_dialogue_for_restore() -> void:
	if _dialogue == null:
		return
	if _dialogue.has_method("clear"):
		_dialogue.clear()
	# A same-presenter rollback can leave one-shot callbacks from the discarded
	# future attached to the dialogue box. They reference the shared chain cursor,
	# so allowing them to consume the restored line would advance twice.
	for connection in _dialogue.dialogue_finished.get_connections():
		_dialogue.dialogue_finished.disconnect(connection.callable)


func _reset_bridge_collapse_presentation_for_restore() -> void:
	if _fall_tween != null and _fall_tween.is_valid():
		_fall_tween.kill()
	_fall_tween = null
	if _fall_offset_dipped and _camera != null:
		_camera.follow_offset.y = _fall_prev_offset_y
	_fall_offset_dipped = false
	if _collapse_presenter != null and is_instance_valid(_collapse_presenter):
		_collapse_presenter.cancel()
		_collapse_presenter.queue_free()
	_collapse_presenter = null
	_collapse_visual_generation = 0
	_collapse_visual_active = false


## Attach the scene to the already-deserialized GameState record without emitting a command, signal,
## damage event, or story transition. Returns true only when an older outer record was migrated.
func _restore_bridge_collapse_from_authority(saved_outer_version: int) -> bool:
	var migrated := false
	_restore_portable_elevator_camera_state()
	if _bridge_collapse_phase() == "":
		_bridge_collapse_authority.clear()
		# Version 1 predates bridge authority. A save written at that version holds GameState
		# upstairs throughout the visual tween, so its bridge_collapse step can only have been
		# either waiting to fall (upper party) or already landed (lower party).
		if saved_outer_version > 0 and saved_outer_version < 2 \
				and _current_step == "bridge_collapse":
			var now := float(_scheduler.get_current_tick())
			_bridge_collapse_authority = _new_bridge_collapse_authority(now)
			if _game_state.get_character_level("aster") == LEVEL_LOWER \
					and _game_state.get_character_level("peris") == LEVEL_LOWER:
				_bridge_collapse_authority["phase"] = BRIDGE_COLLAPSE_PHASE_LANDED
				_bridge_collapse_authority["phase_deadline"] = \
					now + BRIDGE_COLLAPSE_RECOVERY_SECONDS
				_bridge_collapse_authority["topology_committed"] = true
			migrated = true
		else:
			_fall_landed_fired = false
			if _current_step in ["bridge", "bridge_collapse"]:
				_collapsed_chunks_removed = false
				_commit_bridge_collapse_topology(false)
				if _current_step == "bridge" and is_instance_valid(_player):
					_player.set_move_enabled(true)
			return false

	var phase := _bridge_collapse_phase()
	var topology_committed := bool(_bridge_collapse_authority.get(
		"topology_committed",
		phase in [BRIDGE_COLLAPSE_PHASE_LANDED, BRIDGE_COLLAPSE_PHASE_COMPLETE]))
	_collapsed_chunks_removed = bool(_bridge_collapse_authority.get("chunks_retired", false)) \
		or not _chunks.has("bridge")
	_commit_bridge_collapse_topology(topology_committed)
	match phase:
		BRIDGE_COLLAPSE_PHASE_ARMED:
			_fall_landed_fired = false
			_lock_bridge_party_control()
			_sync_bridge_party_endpoint_presentation("render_origin")
			if _camera != null:
				_camera.follow_offset.y = float(_bridge_collapse_authority.get(
					"camera_follow_y", _camera.follow_offset.y))
			if _current_step == "bridge_collapse":
				_arm_bridge_collapse_callback(
					phase,
					float(_bridge_collapse_authority.get("phase_deadline", -1.0)))
		BRIDGE_COLLAPSE_PHASE_FALLING:
			_fall_landed_fired = false
			_lock_bridge_party_control()
			_rebuild_bridge_collapse_presenter()
			_start_bridge_fall_presentation(_bridge_collapse_authority)
			if _current_step == "bridge_collapse":
				_arm_bridge_collapse_callback(
					phase,
					float(_bridge_collapse_authority.get("phase_deadline", -1.0)))
		BRIDGE_COLLAPSE_PHASE_LANDED:
			_fall_landed_fired = true
			_lock_bridge_party_control()
			_sync_bridge_party_endpoint_presentation("render_destination")
			_set_lower_route_camera_bounds()
			_reattach_saved_below_fauna()
			if _current_step == "bridge_collapse":
				_arm_bridge_collapse_callback(
					phase,
					float(_bridge_collapse_authority.get("phase_deadline", -1.0)))
		BRIDGE_COLLAPSE_PHASE_COMPLETE:
			_fall_landed_fired = true
			_sync_bridge_party_endpoint_presentation("render_destination")
			_reattach_saved_below_fauna()
	return migrated


func _lock_bridge_party_control() -> void:
	for character_node in [_aster_node, _peris_node]:
		if is_instance_valid(character_node):
			character_node.set_move_enabled(false)
	if is_instance_valid(_player):
		_player.set_move_enabled(false)


func _sync_bridge_party_endpoint_presentation(context_key: String) -> void:
	var party: Dictionary = _bridge_collapse_authority.get("party", {}) as Dictionary
	for character_id in ["aster", "peris"]:
		var character_node := get_game_state_character_node(character_id)
		if character_node == null:
			continue
		var context: Dictionary = party.get(character_id, {}) as Dictionary
		character_node.global_position = _bridge_context_position(
			context, context_key, character_node.global_position)


func _rebuild_bridge_collapse_presenter() -> void:
	if bool(_bridge_collapse_authority.get("chunks_retired", false)):
		return
	var bridge_chunk := _chunks.get("bridge") as Node3D
	var bridge_floor := bridge_chunk.find_child("BridgeFloor", false, false) as Node3D \
		if bridge_chunk != null else null
	var model := bridge_floor.find_child("BridgeModel", false, false) as Node3D \
		if bridge_floor != null else null
	if model != null:
		_collapse_bridge_model(model, float(_bridge_collapse_authority.get(
			"break_x", BRIDGE_COLLAPSE_X)))


## Fresh chunk construction leaves all lower fauna dormant. Saved GameState already contains every
## cohort that had awakened, so attach those nodes to their records without registering defaults over
## the snapshot; the ordinary presenter notification pass restores each enemy FSM afterwards.
func _reattach_saved_below_fauna() -> void:
	if _game_state == null or _below_dormant_enemy_setups.is_empty():
		_below_fauna_active = true
		return
	_below_fauna_active = true
	_below_activation_cells.clear()
	var still_dormant: Array[Dictionary] = []
	for setup in _below_dormant_enemy_setups:
		var enemy = setup.get("enemy")
		if not is_instance_valid(enemy):
			continue
		if not _game_state.characters.has(enemy.char_id):
			still_dormant.append(setup)
			continue
		enemy.game_state = _game_state
		enemy.process_mode = Node.PROCESS_MODE_INHERIT
		_game_state_character_nodes[enemy.char_id] = enemy
	_below_dormant_enemy_setups = still_dormant


## Fresh save loading constructs the gauntlet chunk before GameState is replaced,
## so its enemy presenters begin dormant. Attach them to existing serialized
## bodies without registering construction defaults, and let Enemy.activate()
## restore its FSM/deadlines plus the detection signal subscription.
func _reattach_saved_gauntlet_enemies() -> void:
	if _game_state == null or _gauntlet_dormant_enemy_setups.is_empty():
		return
	var still_dormant: Array[Dictionary] = []
	for setup in _gauntlet_dormant_enemy_setups:
		var enemy := setup.get("enemy") as Enemy
		if not is_instance_valid(enemy):
			continue
		if not _game_state.characters.has(enemy.char_id):
			still_dormant.append(setup)
			continue
		enemy.game_state = _game_state
		enemy.process_mode = Node.PROCESS_MODE_INHERIT
		_game_state_character_nodes[enemy.char_id] = enemy
		if not bool(enemy.call("_has_saved_enemy_authority")):
			var waypoints: Array[Vector3] = []
			waypoints.assign(setup.get("waypoints", []))
			enemy.configure_patrol(waypoints)
		enemy.activate()
	_gauntlet_dormant_enemy_setups = still_dormant


func _iron_patch_contains(world_pos: Vector3) -> bool:
	return _iron_patch_index(world_pos) >= 0

func _iron_patch_index(world_pos: Vector3) -> int:
	# The hidden prewarm may overlap the bridge in XZ; only the lower deck can contact these fields.
	if absf(world_pos.y - BELOW_Y) > 1.0:
		return -1
	for patch_index in range(_iron_patches.size()):
		var patch: Dictionary = _iron_patches[patch_index]
		var ppos: Vector3 = patch.pos
		var psz: Vector3 = patch.size
		if absf(world_pos.x - ppos.x) < psz.x * 0.5 \
				and absf(world_pos.z - ppos.z) < psz.z * 0.5:
			return patch_index
	return -1

func _show_party_damage_feedback(
		character_id: String, amount: float, source: String, flash_color: Color) -> void:
	var feedback_key := "%s:%s" % [character_id, source]
	_damage_feedback_counts[feedback_key] = int(_damage_feedback_counts.get(feedback_key, 0)) + 1
	var target_node: Node3D = _elevator_party_node(character_id)
	if target_node == null or not is_instance_valid(target_node):
		return
	var feedback_started := PerformanceTrace.begin()
	if _hud != null and _hud.has_method("pulse_portrait_damage"):
		_hud.pulse_portrait_damage(character_id)
	var hp_left := _game_state.get_stat(character_id, "hp") if _game_state != null else 0.0
	if target_node.has_method("show_damage_feedback"):
		target_node.call("show_damage_feedback", amount, source, flash_color, hp_left)
		PerformanceTrace.end(&"draw", &"elevator.damage_feedback", feedback_started,
			character_id, 1)
		return
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
	PerformanceTrace.end(&"draw", &"elevator.damage_feedback", feedback_started,
		character_id, 1)

func _show_marker(pos: Vector3, text: String) -> Label3D:
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
	return lbl

func _show_gauntlet_stage_marker(stage: int, pos: Vector3, text: String) -> void:
	_clear_gauntlet_stage_marker(stage)
	_gauntlet_stage_markers[stage] = _show_marker(pos, text)

func _clear_gauntlet_stage_marker(stage: int) -> void:
	var marker: Variant = _gauntlet_stage_markers.get(stage)
	if is_instance_valid(marker):
		(marker as Node).queue_free()
	_gauntlet_stage_markers.erase(stage)


func _show_gauntlet_context_marker(key: String, pos: Vector3, text: String) -> void:
	_clear_gauntlet_context_marker(key)
	_gauntlet_context_markers[key] = _show_marker(pos, text)


func _clear_gauntlet_context_marker(key: String) -> void:
	var marker: Variant = _gauntlet_context_markers.get(key)
	if is_instance_valid(marker):
		(marker as Node).queue_free()
	_gauntlet_context_markers.erase(key)


func _clear_gauntlet_context_markers() -> void:
	for key_v in _gauntlet_context_markers.keys():
		_clear_gauntlet_context_marker(str(key_v))


func _clear_markers() -> void:
	var env: Node = find_child("Environment", false, false)
	for child in env.get_children():
		if child is Label3D and child.name.begins_with("Marker_"):
			child.queue_free()

func _baseline_junction_rest_authority() -> Dictionary:
	return {
		"version": JUNCTION_REST_AUTHORITY_VERSION,
		"contract": JUNCTION_REST_CONTRACT,
		"phase": JUNCTION_REST_PHASE_IDLE,
		"party_ids": JUNCTION_REST_PARTY.duplicate(),
		"shelter_center": GameEvent.v3_to_arr(JUNCTION_SHELTER_CENTER),
		"shelter_half_size": [JUNCTION_SHELTER_HALF_SIZE.x, JUNCTION_SHELTER_HALF_SIZE.y],
		"water_contract": ENDO_DRINK_CONTRACT,
		"water_item_id": "",
		"start_tick": -1.0,
		"dawn_deadline": -1.0,
		"start_day": -1,
		"start_time": -1.0,
		"dawn_day": -1,
		"atp_before": {},
		"water_consumed": false,
		"cost_applied": false,
	}


func _junction_rest_authority_state() -> Dictionary:
	if _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(JUNCTION_REST_AUTHORITY_KEY, null)
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _valid_junction_rest_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	if int(saved.get("version", 0)) != JUNCTION_REST_AUTHORITY_VERSION \
			or str(saved.get("contract", "")) != JUNCTION_REST_CONTRACT \
			or str(saved.get("water_contract", "")) != ENDO_DRINK_CONTRACT \
			or saved.get("party_ids", []) != JUNCTION_REST_PARTY:
		return false
	var center_v: Variant = saved.get("shelter_center", [])
	var half_v: Variant = saved.get("shelter_half_size", [])
	if not center_v is Array or not half_v is Array \
			or (center_v as Array).size() != 3 or (half_v as Array).size() != 2 \
			or not GameEvent.arr_to_v3(center_v as Array).is_equal_approx(JUNCTION_SHELTER_CENTER) \
			or not Vector2(
				float((half_v as Array)[0]), float((half_v as Array)[1])
			).is_equal_approx(JUNCTION_SHELTER_HALF_SIZE):
		return false
	var phase := str(saved.get("phase", ""))
	if phase == JUNCTION_REST_PHASE_IDLE:
		return str(saved.get("water_item_id", "")).is_empty() \
			and float(saved.get("start_tick", -1.0)) < 0.0 \
			and float(saved.get("dawn_deadline", -1.0)) < 0.0 \
			and float(saved.get("start_time", -1.0)) < 0.0 \
			and not bool(saved.get("water_consumed", false)) \
			and not bool(saved.get("cost_applied", false))
	if phase not in [
			JUNCTION_REST_PHASE_COMMITTING,
			JUNCTION_REST_PHASE_NIGHT_WATCH,
			JUNCTION_REST_PHASE_COMPLETE,
	]:
		return false
	var start_tick := float(saved.get("start_tick", -1.0))
	var deadline := float(saved.get("dawn_deadline", -1.0))
	var start_time := float(saved.get("start_time", -1.0))
	var atp_before_v: Variant = saved.get("atp_before", {})
	if not is_finite(start_tick) or start_tick < 0.0 \
			or not is_finite(deadline) \
			or not is_equal_approx(deadline - start_tick, JUNCTION_REST_WATCH_SECONDS) \
			or not is_finite(start_time) or start_time < 0.0 or start_time > 1.0 \
			or int(saved.get("start_day", -1)) < 1 \
			or str(saved.get("water_item_id", "")).is_empty() \
			or not atp_before_v is Dictionary:
		return false
	for character_id in JUNCTION_REST_PARTY:
		if not (atp_before_v as Dictionary).has(character_id) \
				or float((atp_before_v as Dictionary).get(character_id, -1.0)) < 1.0:
			return false
	if phase == JUNCTION_REST_PHASE_COMMITTING:
		return not bool(saved.get("water_consumed", false)) \
			and not bool(saved.get("cost_applied", false))
	return bool(saved.get("water_consumed", false)) \
		and bool(saved.get("cost_applied", false)) \
		and int(saved.get("dawn_day", -1)) == int(saved.get("start_day", -1)) + 1


func _publish_junction_rest_authority(authority: Dictionary) -> void:
	if _game_state != null:
		_game_state.set_world_state(JUNCTION_REST_AUTHORITY_KEY, authority.duplicate(true))


func _junction_roster_is_exact_party() -> bool:
	if _game_state == null:
		return false
	var roster: Array[String] = []
	for character_id_v in _game_state.characters.keys():
		roster.append(str(character_id_v))
	roster.sort()
	var expected: Array[String] = JUNCTION_REST_PARTY.duplicate()
	expected.sort()
	return roster == expected


## The one-shot plant is the last reversible player action before Endo/night choreography takes
## control. Refuse it while Aster or Peris is outside the exact shelter (or cannot pay), so a bad
## formation prediction is falsified while the player can still correct it instead of deadlocking
## after the dialogue continuation has been consumed.
func _junction_existing_party_ready_for_endo() -> bool:
	if _game_state == null:
		return false
	for character_id in ["aster", "peris"]:
		if not _game_state.characters.has(character_id) \
				or _game_state.get_character_level(character_id) != LEVEL_LOWER \
				or _game_state.is_downed(character_id) \
				or _game_state.get_stat(character_id, "atp") < 1.0 \
				or not _game_state.is_at_shelter(character_id):
			return false
		var position := _game_state.get_position(character_id)
		if absf(position.x - JUNCTION_SHELTER_CENTER.x) > JUNCTION_SHELTER_HALF_SIZE.x \
				or absf(position.z - JUNCTION_SHELTER_CENTER.z) > JUNCTION_SHELTER_HALF_SIZE.y:
			return false
	return true


## Rest eligibility is a causal query over authored geometry and every GameState-owned activity.
## No light, timer, dialogue line, or presenter transform can satisfy it.
func _junction_party_can_commit_rest() -> bool:
	if not _junction_roster_is_exact_party() or not _endo_holds_drink():
		return false
	for character_id in JUNCTION_REST_PARTY:
		if not _game_state.characters.has(character_id) \
				or _game_state.get_character_level(character_id) != LEVEL_LOWER \
				or _game_state.is_downed(character_id) \
				or _game_state.is_moving(character_id) \
				or _game_state.is_resting(character_id) \
				or _game_state.is_knocked_down(character_id) \
				or _game_state.is_dodging(character_id) \
				or _game_state.is_endocytosing(character_id) \
				or _game_state.is_external_traversal_active(character_id) \
				or _game_state.is_dragging(character_id) \
				or _game_state.is_field_restoring(character_id) \
				or _game_state.get_stat(character_id, "atp") < 1.0 \
				or not _game_state.is_at_shelter(character_id):
			return false
		var position := _game_state.get_position(character_id)
		if absf(position.x - JUNCTION_SHELTER_CENTER.x) > JUNCTION_SHELTER_HALF_SIZE.x \
				or absf(position.z - JUNCTION_SHELTER_CENTER.z) > JUNCTION_SHELTER_HALF_SIZE.y:
			return false
	return true


func _junction_rest_outcome_matches(authority: Dictionary) -> bool:
	if _game_state == null:
		return false
	var water_item_id := str(authority.get("water_item_id", ""))
	if water_item_id.is_empty() or _game_state.items.has(water_item_id) \
			or _game_state.get_game_day() < int(authority.get("start_day", -1)) + 1:
		return false
	var atp_before := authority.get("atp_before", {}) as Dictionary
	for character_id in JUNCTION_REST_PARTY:
		var expected_atp := GameState.quantize_atp(
			float(atp_before.get(character_id, -1.0)) - 1.0)
		if not _game_state.characters.has(character_id) \
				or not is_equal_approx(_game_state.get_stat(character_id, "atp"), expected_atp) \
				or _game_state.is_resting(character_id):
			return false
	return true


## The narrative line is only an invitation. This method is the single commit point: exact trio,
## exact shelter, still/conscious bodies, Endo's canonical water, and one ATP each are all checked
## before a semantic record or gameplay resource changes.
func _start_night_watch() -> bool:
	if _current_step != "endo_delivered" or not _junction_party_can_commit_rest():
		if _hud != null:
			_hud.show_message(
				"The whole conscious trio must be still inside the shelter, with Endo's water and one ATP each.",
				2.8)
		return false
	if not _enter_step("night_watch"):
		return false
	var now := float(_scheduler.get_current_tick())
	var authority := _baseline_junction_rest_authority()
	authority["phase"] = JUNCTION_REST_PHASE_COMMITTING
	authority["water_item_id"] = _resolve_endo_drink_item_id()
	authority["start_tick"] = now
	authority["dawn_deadline"] = now + JUNCTION_REST_WATCH_SECONDS
	authority["start_day"] = _game_state.get_game_day()
	authority["start_time"] = _game_state.get_time_of_day()
	var atp_before := {}
	for character_id in JUNCTION_REST_PARTY:
		atp_before[character_id] = _game_state.get_stat(character_id, "atp")
	authority["atp_before"] = atp_before
	# This publication is the coherent pre-payment boundary. A listener may save here; restore will
	# resume the same transaction without treating the invitation dialogue as proof that it happened.
	_publish_junction_rest_authority(authority)
	return _complete_junction_rest_commit(authority)


func _complete_junction_rest_commit(authority: Dictionary) -> bool:
	if not _valid_junction_rest_authority(authority) \
			or str(authority.get("phase", "")) != JUNCTION_REST_PHASE_COMMITTING:
		return false
	# A save taken from the first atomic party-rest feedback signal already contains the complete
	# water/cost/dawn result while its outer semantic record still says COMMITTING. Normalize it; do
	# not consume or charge a second time.
	if _junction_rest_outcome_matches(authority):
		authority["phase"] = JUNCTION_REST_PHASE_NIGHT_WATCH
		authority["water_consumed"] = true
		authority["cost_applied"] = true
		authority["dawn_day"] = _game_state.get_game_day()
		_publish_junction_rest_authority(authority)
		_sync_endo_drink_presenter()
		_present_junction_night_watch(authority, false)
		return true
	if not _junction_party_can_commit_rest():
		_reject_junction_rest_commit(
			"The shelter transaction no longer has the complete settled party or its water.", true)
		return false
	# Set night only after COMMITTING exists. A game-clock listener therefore captures either the
	# original daytime world or an explicitly pending transaction, never an unexplained dark scene.
	if _game_state.get_game_day() != int(authority.get("start_day", 1)) \
			or _game_state.get_time_of_day() < GameState.NIGHT_START:
		_game_state.set_game_clock(
			int(authority.get("start_day", 1)), JUNCTION_REST_NIGHT_TIME)
	if not _game_state.can_party_rest(JUNCTION_REST_PARTY):
		_reject_junction_rest_commit(
			"The canonical party-rest preflight refused the settled trio without charging it.", false)
		return false
	var water_item_id := str(authority.get("water_item_id", ""))
	if water_item_id != _resolve_endo_drink_item_id() or not _endo_holds_drink():
		_reject_junction_rest_commit("Endo's delivered water is no longer available.", false)
		return false
	# remove_item emits no gameplay signal. command_party_rest then mutates all three ATP/rest/day
	# records before its first signal, so observers cannot save a consumed-water/partially-paid prefix.
	_game_state.remove_item(water_item_id)
	_drink_item_id = ""
	if not _game_state.command_party_rest(JUNCTION_REST_PARTY):
		_reject_junction_rest_commit(
			"The atomic party rest was refused; the incomplete transaction remains diagnostic.", false)
		return false
	if not _junction_rest_outcome_matches(authority):
		_reject_junction_rest_commit(
			"The shelter did not produce one complete paid dawn; no partial result is accepted.", false)
		return false
	authority["phase"] = JUNCTION_REST_PHASE_NIGHT_WATCH
	authority["water_consumed"] = true
	authority["cost_applied"] = true
	authority["dawn_day"] = _game_state.get_game_day()
	_publish_junction_rest_authority(authority)
	_sync_endo_drink_presenter()
	_present_junction_night_watch(authority, true)
	return true


func _reject_junction_rest_commit(message: String, reset_to_idle: bool) -> void:
	_scheduler.cancel_tag(JUNCTION_REST_COMMIT_TAG)
	_scheduler.cancel_tag(JUNCTION_REST_DAWN_TAG)
	if reset_to_idle:
		_publish_junction_rest_authority(_baseline_junction_rest_authority())
		_current_step = "endo_delivered"
	if _hud != null:
		_hud.show_message(message, 3.0)


func _junction_world_environment() -> WorldEnvironment:
	var environment_root := find_child("Environment", false, false)
	if environment_root == null:
		return null
	for child in environment_root.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
	return null


func _junction_shelter_light() -> OmniLight3D:
	var junction_chunk := _chunks.get("junction") as Node3D
	if junction_chunk == null:
		return null
	return junction_chunk.find_child("ShelterLight", true, false) as OmniLight3D


## Night is a deterministic projection of the saved start/deadline. Random tween targets made two
## loads of the same save visibly disagree; fixed targets plus elapsed-time reconstruction do not.
func _present_junction_night_watch(authority: Dictionary, announce: bool) -> void:
	_clear_junction_night_presentation(false)
	var world_environment := _junction_world_environment()
	if world_environment != null and world_environment.environment != null:
		world_environment.environment.ambient_light_energy = 0.1
	var environment_root := find_child("Environment", false, false) as Node3D
	var now := float(_scheduler.get_current_tick())
	var start_tick := float(authority.get("start_tick", now))
	var fade_progress := clampf((now - start_tick) / 2.5, 0.0, 1.0)
	if environment_root != null:
		for side_index in range(2):
			var side_sign := -1.0 if side_index == 0 else 1.0
			var window_z := side_sign * (SHELTER_SIZE.z * 0.5 + 0.5)
			for pair_index in range(3):
				var pair_x := JUNCTION_POS.x - 2.0 + pair_index * 2.5
				var target_energy := 0.56 + 0.08 * float((side_index + pair_index) % 3)
				for eye_index in range(2):
					var eye := OmniLight3D.new()
					eye.name = "JunctionNightEye_%d_%d_%d" % [side_index, pair_index, eye_index]
					var eye_offset := -0.15 if eye_index == 0 else 0.15
					eye.position = Vector3(
						pair_x + eye_offset, BELOW_Y + 1.6, window_z)
					eye.light_color = Color(0.95, 0.1, 0.05)
					eye.light_energy = target_energy * fade_progress
					eye.omni_range = 0.8
					environment_root.add_child(eye)
					_monster_eyes.append(eye)
					if fade_progress < 1.0:
						var tween := create_tween()
						tween.tween_property(
							eye, "light_energy", target_energy,
							maxf(0.001, 2.5 * (1.0 - fade_progress)))
	var flicker_deadline := start_tick + 3.0
	if flicker_deadline > now + 0.000001 and _junction_shelter_light() != null:
		_scheduler.schedule_at(
			flicker_deadline, _play_junction_shelter_flicker, JUNCTION_REST_FLICKER_TAG)
	if announce:
		DialogueData.say_to(_dialogue, "junction.night.eyes")
	_arm_junction_rest_dawn(authority)


func _play_junction_shelter_flicker() -> void:
	var authority := _junction_rest_authority_state()
	if not _valid_junction_rest_authority(authority) \
			or str(authority.get("phase", "")) not in [
				JUNCTION_REST_PHASE_COMMITTING, JUNCTION_REST_PHASE_NIGHT_WATCH]:
		return
	var shelter_light := _junction_shelter_light()
	if shelter_light == null:
		return
	var flicker := create_tween()
	flicker.tween_property(shelter_light, "light_energy", 1.0, 0.1)
	flicker.tween_property(shelter_light, "light_energy", 2.5, 0.1)
	flicker.tween_property(shelter_light, "light_energy", 0.8, 0.1)
	flicker.tween_property(shelter_light, "light_energy", 2.5, 0.3)


func _clear_junction_night_presentation(restore_daylight := true) -> void:
	if _scheduler != null:
		_scheduler.cancel_tag(JUNCTION_REST_FLICKER_TAG)
		_scheduler.cancel_tag("flicker")
	for eye in _monster_eyes:
		if is_instance_valid(eye):
			eye.queue_free()
	_monster_eyes.clear()
	var shelter_light := _junction_shelter_light()
	if shelter_light != null:
		shelter_light.light_energy = 2.5
	if restore_daylight:
		var world_environment := _junction_world_environment()
		if world_environment != null and world_environment.environment != null:
			world_environment.environment.ambient_light_energy = 0.5


func _arm_junction_rest_dawn(authority: Dictionary) -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(JUNCTION_REST_DAWN_TAG)
	_scheduler.cancel_tag("dawn") # pre-authority save callbacks from this same presenter
	var deadline := float(authority.get("dawn_deadline", -1.0))
	var now := float(_scheduler.get_current_tick())
	if deadline <= now + 0.000001:
		_scheduler.schedule_after(0.000001, _start_dawn, JUNCTION_REST_DAWN_TAG)
	else:
		_scheduler.schedule_at(deadline, _start_dawn, JUNCTION_REST_DAWN_TAG)


func _start_dawn() -> void:
	var authority := _junction_rest_authority_state()
	if not _valid_junction_rest_authority(authority):
		return
	var phase := str(authority.get("phase", ""))
	if phase == JUNCTION_REST_PHASE_COMMITTING and _junction_rest_outcome_matches(authority):
		authority["phase"] = JUNCTION_REST_PHASE_NIGHT_WATCH
		authority["water_consumed"] = true
		authority["cost_applied"] = true
		authority["dawn_day"] = _game_state.get_game_day()
		_publish_junction_rest_authority(authority)
		phase = JUNCTION_REST_PHASE_NIGHT_WATCH
	if phase != JUNCTION_REST_PHASE_NIGHT_WATCH \
			or not _junction_rest_outcome_matches(authority):
		return
	var deadline := float(authority.get("dawn_deadline", -1.0))
	if float(_scheduler.get_current_tick()) + 0.000001 < deadline:
		_arm_junction_rest_dawn(authority)
		return
	if _current_step != "night_watch" or not _enter_step("dawn"):
		return
	authority["phase"] = JUNCTION_REST_PHASE_COMPLETE
	_publish_junction_rest_authority(authority)
	_clear_junction_night_presentation(true)
	_sync_endo_drink_presenter()
	# Named portable continuation: a save during the dawn line resumes morning without preserving
	# an opaque anonymous callback or padding the already-solved rest transaction with another timer.
	_dialogue_chain(["junction.dawn"], _start_morning)


## Attach presentation/callbacks to the deserialized transaction without issuing gameplay from the
## restore hook. COMMITTING may denote either the pre-payment publication or a signal-time snapshot
## after the atomic batch; the canonical outcome distinguishes them without a second local flag.
func _restore_junction_rest_authority() -> void:
	if _scheduler == null or _game_state == null:
		return
	_scheduler.cancel_tag("night_watch")
	_scheduler.cancel_tag("dawn")
	_scheduler.cancel_tag("morning")
	_scheduler.cancel_tag(JUNCTION_REST_COMMIT_TAG)
	_scheduler.cancel_tag(JUNCTION_REST_DAWN_TAG)
	_scheduler.cancel_tag(JUNCTION_REST_FLICKER_TAG)
	_clear_junction_night_presentation(true)
	var authority := _junction_rest_authority_state()
	if not _valid_junction_rest_authority(authority):
		authority = _baseline_junction_rest_authority()
	var phase := str(authority.get("phase", JUNCTION_REST_PHASE_IDLE))
	match phase:
		JUNCTION_REST_PHASE_COMMITTING:
			_current_step = "night_watch"
			_present_junction_night_watch(authority, false)
			if not _junction_rest_outcome_matches(authority):
				# Resume after every presenter has attached. This normal command path may emit signals;
				# the restore hook itself remains a silent projection.
				_scheduler.schedule_after(
					0.000001,
					_complete_junction_rest_commit.bind(authority.duplicate(true)),
					JUNCTION_REST_COMMIT_TAG)
		JUNCTION_REST_PHASE_NIGHT_WATCH:
			if _junction_rest_outcome_matches(authority):
				_current_step = "night_watch"
				_present_junction_night_watch(authority, false)
			else:
				# Semantic completion without its paid dawn/water outcome cannot grant progression.
				_current_step = "endo_delivered"
				_clear_junction_night_presentation(true)
		JUNCTION_REST_PHASE_COMPLETE:
			_clear_junction_night_presentation(true)
			if _junction_rest_outcome_matches(authority):
				if _current_step not in ["morning", "gauntlet", "complete"]:
					_current_step = "dawn"
			else:
				_current_step = "endo_delivered"
		_:
			if _current_step in ["night_watch", "dawn"]:
				# Saves from the pre-authority implementation fail closed at the delivered-water beat.
				# They cannot inherit a stale anonymous dawn timer from the discarded future.
				_current_step = "endo_delivered"


# --- Morning / Endo Joins ---

func _start_morning() -> void:
	_enter_step("morning")
	_dialogue_chain([
		"junction.morning.trail",
		"junction.endo.stands",
		"junction.peris.coming",
		"junction.aster.ok",
	], _queue_start_gauntlet)


func _queue_start_gauntlet() -> void:
	_schedule_portable_method(1.5, _start_gauntlet, "gauntlet")

# --- Flure Gauntlet ---

func _start_gauntlet() -> void:
	var gauntlet_started := PerformanceTrace.begin()
	_enter_step("gauntlet")
	_ensure_endo_gauntlet_party_ui()
	_set_gauntlet_camera_bounds()
	var reveal_started := PerformanceTrace.begin()
	reveal_chunk("gauntlet")
	PerformanceTrace.end(&"update", &"elevator.gauntlet.reveal", reveal_started, "gauntlet", 1)
	var unload_started := PerformanceTrace.begin()
	_unload_chunk("junction")
	PerformanceTrace.end(&"update", &"elevator.gauntlet.unload_junction", unload_started, "junction", 1)
	_gauntlet_stage = 0
	_gauntlet_midpoint_reached = false
	_gauntlet_strategy = ""
	_gauntlet_resetting = false
	_gauntlet_flure_active = {0: false, 1: false}
	_flure_active = false
	_ensure_gauntlet_party_lower_level()
	var enemies_started := PerformanceTrace.begin()
	_activate_gauntlet_enemies()
	PerformanceTrace.end(&"update", &"elevator.gauntlet.activate_enemies", enemies_started,
		"gauntlet", _gauntlet_enemies.size())
	_player.set_move_enabled(false)
	# Keep the pack inert and the lure unclickable until the mandatory briefing finishes, then arm
	# both together. The authored posts remain outside immediate sight range so the decision is fair.
	for enemy in _gauntlet_enemies:
		if is_instance_valid(enemy):
			enemy.set_detection_targets([])
	# The briefing and the bodies are independent latches. Dialogue can finish
	# while a slower member is still walking, but that never arms the pack or the
	# Flure. Accepted GameState movement and real settled endpoints own formation.
	_gauntlet_intro_authority = _new_gauntlet_intro_authority()
	_store_gauntlet_checkpoint_hp()
	_gauntlet_run_authority = _new_gauntlet_run_authority()
	_issue_next_gauntlet_intro_move()
	_dialogue_chain([
		"junction.aster.blocked",
		"junction.peris.flure",
	], _finish_gauntlet_intro)
	_publish_elevator_runtime_authority()
	PerformanceTrace.end(&"update", &"elevator.gauntlet.start", gauntlet_started, "gauntlet", 1)


func _ensure_gauntlet_party_lower_level() -> void:
	for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		if not _game_state.characters.has(member_id) \
				or _game_state.get_character_level(member_id) == LEVEL_LOWER:
			continue
		var pos: Vector3 = _game_state.get_position(member_id)
		_game_state.set_character_level(member_id, LEVEL_LOWER)
		pos.y = BELOW_Y + 0.5
		_game_state.snap_character_to(member_id, pos)
		var presenter: Node3D = _elevator_party_node(member_id)
		if presenter != null:
			presenter.global_position = pos

func _finish_gauntlet_intro() -> void:
	if str(_gauntlet_intro_authority.get("phase", "")) != GAUNTLET_INTRO_PHASE_ASSEMBLING:
		return
	_gauntlet_intro_authority["presentation_complete"] = true
	_publish_elevator_runtime_authority()
	_try_arm_gauntlet_intro()


func _arm_gauntlet_after_intro() -> void:
	if not _valid_gauntlet_run_authority(_gauntlet_run_authority):
		_store_gauntlet_checkpoint_hp()
		_gauntlet_run_authority = _new_gauntlet_run_authority()
	_sync_gauntlet_station_interactivity()
	_tutorial_prompt.show_action_prompt(
		&"command",
		"activate Flure (Peris only)",
		0.0,
		"RMB"
	)
	_ensure_endo_gauntlet_party_ui()
	_apply_character_control_selection()
	_arm_gauntlet_progress_poll(float(
		_gauntlet_run_authority.get("next_poll_tick", -1.0)))
	_publish_elevator_runtime_authority()


func _resume_gauntlet_intro_arming() -> void:
	if str(_gauntlet_intro_authority.get("phase", "")) \
			!= GAUNTLET_INTRO_PHASE_ARMING:
		return
	for enemy_v in _gauntlet_enemy_groups.get(0, []):
		var enemy := enemy_v as Enemy
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		if enemy.get_detection_targets() != GAUNTLET_INTRO_REQUIRED_MEMBERS:
			enemy.set_detection_targets(GAUNTLET_INTRO_REQUIRED_MEMBERS)
		if enemy.get_state() == "idle":
			enemy.begin_home_behavior()
	_gauntlet_intro_authority["phase"] = GAUNTLET_INTRO_PHASE_READY
	_publish_elevator_runtime_authority()
	_arm_gauntlet_after_intro()


## Derive presentation and controls from the already-committed Enemy, Flure,
## GameState, and run records. Restore and reset-release both use this path; it
## must not issue movement or mutate an enemy detection/FSM authority record.
func _sync_gauntlet_presenter_from_authority() -> void:
	_ensure_endo_gauntlet_party_ui()
	var run_phase := str(_gauntlet_run_authority.get("phase", ""))
	_sync_gauntlet_station_interactivity()
	for stage in range(2):
		_clear_gauntlet_stage_marker(stage)
		if str(_gauntlet_window_state(stage).get("phase", "")) \
				== GAUNTLET_WINDOW_ACTIVE:
			var lure_pos := FLURE_POS if stage == 0 else GAUNTLET_FLURE_2_POS
			_show_gauntlet_stage_marker(
				stage, lure_pos + Vector3(0, 1.5, 0),
				"LURE %d ACTIVE" % (stage + 1))
	_clear_gauntlet_context_markers()
	if run_phase == GAUNTLET_RUN_PHASE_RESETTING:
		var reset_base := GAUNTLET_MIDPOINT if _gauntlet_midpoint_reached \
			else Vector3(GAUNTLET_POS.x - 8.0, BELOW_Y, 0.0)
		_show_gauntlet_context_marker(
			"reset", reset_base + Vector3(0, 2.0, 0), "REFUGE RESET")
	elif _gauntlet_midpoint_reached:
		_show_gauntlet_context_marker(
			"midpoint", GAUNTLET_MIDPOINT + Vector3(0, 2.0, 0),
			"MIDPOINT REFUGE")
	if _fade_rect != null:
		var fade_alpha := 0.0
		if _current_step == "complete" \
				and run_phase == GAUNTLET_RUN_PHASE_TRANSITIONING:
			var transition_deadline := float(_gauntlet_run_authority.get(
				"transition_deadline", -1.0))
			fade_alpha = clampf(
				(_scheduler.get_current_tick() - (transition_deadline - 2.0)) / 2.0,
				0.0, 1.0)
		_fade_rect.color.a = fade_alpha
	_apply_character_control_selection()
	if run_phase == GAUNTLET_RUN_PHASE_ACTIVE:
		var prompt_stage := clampi(_gauntlet_stage, 0, 1)
		var prompt_window := _gauntlet_window_state(prompt_stage)
		match str(prompt_window.get("phase", GAUNTLET_WINDOW_READY)):
			GAUNTLET_WINDOW_ACTIVE:
				_tutorial_prompt.show_action_prompt(
					&"command", "move the whole party before Pack %d returns" \
						% (prompt_stage + 1), 0.0, "RMB")
			GAUNTLET_WINDOW_FAILED:
				_tutorial_prompt.show_prompt(
					"Pack %d was only partly pulled - break contact; Flure rearming" \
						% (prompt_stage + 1))
			_:
				_tutorial_prompt.show_action_prompt(
					&"command", "activate Flure %d (Peris only)" \
						% (prompt_stage + 1), 0.0, "RMB")
	else:
		_tutorial_prompt.hide_prompt()


func _sync_gauntlet_station_interactivity() -> void:
	var can_interact := str(_gauntlet_intro_authority.get("phase", "")) \
		== GAUNTLET_INTRO_PHASE_READY \
		and str(_gauntlet_run_authority.get("phase", "")) \
		== GAUNTLET_RUN_PHASE_ACTIVE
	for stage in range(_gauntlet_flure_interactables.size()):
		var station := _gauntlet_flure_interactables[stage] as Flure
		if not is_instance_valid(station):
			continue
		station.set_interaction_enabled(
			can_interact
			and str(_gauntlet_window_state(stage).get("phase", "")) \
				== GAUNTLET_WINDOW_READY
			and (stage == 0 or _gauntlet_midpoint_reached)
		)


func _gauntlet_intro_targets() -> Dictionary:
	var entrance := Vector3(GAUNTLET_POS.x - 8.0, BELOW_Y + 0.5, 0.0)
	return {
		"aster": entrance,
		"peris": entrance + Vector3(-1.0, 0.0, 1.0),
		"endo": entrance + Vector3(-1.0, 0.0, -1.0),
	}


func _encoded_gauntlet_intro_targets() -> Dictionary:
	var encoded := {}
	for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		encoded[member_id] = GameEvent.v3_to_arr(
			_gauntlet_intro_targets().get(member_id, Vector3.ZERO)
		)
	return encoded


func _new_gauntlet_intro_authority() -> Dictionary:
	var arrivals := {}
	var accepted_commands := {}
	for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		arrivals[member_id] = false
		accepted_commands[member_id] = false
	return {
		"phase": GAUNTLET_INTRO_PHASE_ASSEMBLING,
		"required_members": GAUNTLET_INTRO_REQUIRED_MEMBERS.duplicate(),
		"targets": _encoded_gauntlet_intro_targets(),
		"arrivals": arrivals,
		"accepted_commands": accepted_commands,
		"presentation_complete": false,
		"next_retry_tick": _scheduler.get_current_tick() if _scheduler != null else 0.0,
	}


func _gauntlet_intro_member_arrived(member_id: String, target: Vector3) -> bool:
	return (
		_game_state != null
		and _game_state.characters.has(member_id)
		and not _game_state.is_downed(member_id)
		and not _game_state.is_moving(member_id)
		and _horizontal_distance(_game_state.get_position(member_id), target)
			<= GAUNTLET_INTRO_ARRIVAL_RADIUS
	)


func _update_gauntlet_intro_formation() -> void:
	if str(_gauntlet_intro_authority.get("phase", "")) != GAUNTLET_INTRO_PHASE_ASSEMBLING:
		return
	var changed := false
	var arrivals: Dictionary = (
		_gauntlet_intro_authority.get("arrivals", {}) as Dictionary
	).duplicate(true)
	var targets := _gauntlet_intro_targets()
	for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		var arrived := _gauntlet_intro_member_arrived(
			member_id, targets.get(member_id, Vector3.ZERO)
		)
		if bool(arrivals.get(member_id, false)) != arrived:
			arrivals[member_id] = arrived
			changed = true
	_gauntlet_intro_authority["arrivals"] = arrivals
	if changed:
		_publish_elevator_runtime_authority()
	_issue_next_gauntlet_intro_move()
	_try_arm_gauntlet_intro()


func _issue_next_gauntlet_intro_move() -> void:
	if _game_state == null or _scheduler == null \
			or str(_gauntlet_intro_authority.get("phase", "")) \
			!= GAUNTLET_INTRO_PHASE_ASSEMBLING:
		return
	var now := _scheduler.get_current_tick()
	if now + 0.000001 < float(_gauntlet_intro_authority.get("next_retry_tick", 0.0)):
		return
	var arrivals: Dictionary = _gauntlet_intro_authority.get("arrivals", {})
	var accepted: Dictionary = (
		_gauntlet_intro_authority.get("accepted_commands", {}) as Dictionary
	).duplicate(true)
	var targets := _gauntlet_intro_targets()
	for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		if bool(arrivals.get(member_id, false)):
			# An assembling snapshot may catch a body on its slot one signal before
			# the formation records the operation. Earn a canonical zero-distance
			# receipt instead of either deadlocking or treating position alone as an
			# accepted command.
			if not bool(accepted.get(member_id, false)) \
					and _game_state.characters.has(member_id) \
					and not _game_state.is_downed(member_id):
				accepted[member_id] = bool(_game_state.command_move_to_pos(
					member_id, targets.get(member_id, Vector3.ZERO)
				))
			continue
		if not _game_state.characters.has(member_id) or _game_state.is_downed(member_id):
			accepted[member_id] = false
			continue
		if _game_state.is_moving(member_id):
			accepted[member_id] = true
			continue
		accepted[member_id] = bool(_game_state.command_move_to_pos(
			member_id, targets.get(member_id, Vector3.ZERO)
		))
		_gauntlet_intro_authority["accepted_commands"] = accepted
		_gauntlet_intro_authority["next_retry_tick"] = now + GAUNTLET_INTRO_RETRY_INTERVAL
		_publish_elevator_runtime_authority()
		_arm_gauntlet_intro_poll()
		return
	_gauntlet_intro_authority["accepted_commands"] = accepted
	_gauntlet_intro_authority["next_retry_tick"] = now + GAUNTLET_INTRO_RETRY_INTERVAL
	_publish_elevator_runtime_authority()
	_arm_gauntlet_intro_poll()


func _arm_gauntlet_intro_poll() -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(GAUNTLET_INTRO_POLL_TAG)
	if str(_gauntlet_intro_authority.get("phase", "")) \
			!= GAUNTLET_INTRO_PHASE_ASSEMBLING:
		return
	var deadline := maxf(
		_scheduler.get_current_tick() + 0.000001,
		float(_gauntlet_intro_authority.get(
			"next_retry_tick", _scheduler.get_current_tick()))
	)
	if not is_equal_approx(
			float(_gauntlet_intro_authority.get("next_retry_tick", -1.0)), deadline):
		_gauntlet_intro_authority["next_retry_tick"] = deadline
		_publish_elevator_runtime_authority()
	_scheduler.schedule_at(
		deadline,
		_on_gauntlet_intro_poll.bind(deadline),
		GAUNTLET_INTRO_POLL_TAG
	)


func _on_gauntlet_intro_poll(expected_deadline: float) -> void:
	if _current_step != "gauntlet" \
			or str(_gauntlet_intro_authority.get("phase", "")) \
			!= GAUNTLET_INTRO_PHASE_ASSEMBLING \
			or not is_equal_approx(
				float(_gauntlet_intro_authority.get("next_retry_tick", -1.0)),
				expected_deadline):
		return
	_update_gauntlet_intro_formation()


func _try_arm_gauntlet_intro() -> void:
	if str(_gauntlet_intro_authority.get("phase", "")) != GAUNTLET_INTRO_PHASE_ASSEMBLING \
			or not bool(_gauntlet_intro_authority.get("presentation_complete", false)):
		return
	var arrivals: Dictionary = _gauntlet_intro_authority.get("arrivals", {})
	var accepted: Dictionary = _gauntlet_intro_authority.get("accepted_commands", {})
	for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		if not bool(arrivals.get(member_id, false)) \
				or not bool(accepted.get(member_id, false)):
			return
	_gauntlet_intro_authority["phase"] = GAUNTLET_INTRO_PHASE_ARMING
	_gauntlet_intro_authority["next_retry_tick"] = -1.0
	_scheduler.cancel_tag(GAUNTLET_INTRO_POLL_TAG)
	_publish_elevator_runtime_authority()
	_resume_gauntlet_intro_arming()


func _valid_gauntlet_intro_authority(state: Dictionary) -> bool:
	var phase := str(state.get("phase", ""))
	if phase not in [
		GAUNTLET_INTRO_PHASE_ASSEMBLING,
		GAUNTLET_INTRO_PHASE_ARMING,
		GAUNTLET_INTRO_PHASE_READY,
	]:
		return false
	var required: Array = state.get("required_members", [])
	if required != GAUNTLET_INTRO_REQUIRED_MEMBERS:
		return false
	var saved_targets: Dictionary = state.get("targets", {})
	var expected_targets := _gauntlet_intro_targets()
	var arrivals_v: Variant = state.get("arrivals", null)
	var accepted_v: Variant = state.get("accepted_commands", null)
	if not (arrivals_v is Dictionary) or not (accepted_v is Dictionary):
		return false
	for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		if not saved_targets.has(member_id) \
				or not (saved_targets[member_id] is Array) \
				or GameEvent.arr_to_v3(saved_targets[member_id]).distance_to(
					expected_targets.get(member_id, Vector3.ZERO)
				) > 0.001 \
				or not (arrivals_v as Dictionary).has(member_id) \
				or not (accepted_v as Dictionary).has(member_id):
			return false
	var next_retry := float(state.get("next_retry_tick", -1.0))
	if not is_finite(next_retry):
		return false
	if phase in [GAUNTLET_INTRO_PHASE_ARMING, GAUNTLET_INTRO_PHASE_READY]:
		if not bool(state.get("presentation_complete", false)) or next_retry != -1.0:
			return false
		for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
			if not bool((arrivals_v as Dictionary).get(member_id, false)) \
					or not bool((accepted_v as Dictionary).get(member_id, false)):
				return false
	elif next_retry < 0.0:
		return false
	return true


func _gauntlet_window_baseline() -> Dictionary:
	return {
		"phase": GAUNTLET_WINDOW_READY,
		"deadline": -1.0,
	}


func _new_gauntlet_run_authority() -> Dictionary:
	return {
		"contract": GAUNTLET_RUN_CONTRACT,
		"version": GAUNTLET_RUN_VERSION,
		"phase": GAUNTLET_RUN_PHASE_ACTIVE,
		"required_party": GAUNTLET_INTRO_REQUIRED_MEMBERS.duplicate(),
		"stage": 0,
		"midpoint_reached": false,
		"strategy": "",
		"active_stage": -1,
		"windows": {
			"0": _gauntlet_window_baseline(),
			"1": _gauntlet_window_baseline(),
		},
		"checkpoint_hp": _gauntlet_checkpoint_hp.duplicate(true),
		"reset_count": _gauntlet_reset_count,
		"wasted_windows": _gauntlet_wasted_flure_windows,
		"next_poll_tick": -1.0,
		"resume_poll_tick": -1.0,
		"reset_start_deadline": -1.0,
		"reset_reason": "",
		"reset_release_deadline": -1.0,
		"transition_deadline": -1.0,
	}


func _refresh_gauntlet_run_authority_fields() -> void:
	if _gauntlet_run_authority.is_empty():
		return
	_gauntlet_run_authority["stage"] = _gauntlet_stage
	_gauntlet_run_authority["midpoint_reached"] = _gauntlet_midpoint_reached
	_gauntlet_run_authority["strategy"] = _gauntlet_strategy
	_gauntlet_run_authority["active_stage"] = _gauntlet_active_stage
	_gauntlet_run_authority["checkpoint_hp"] = _gauntlet_checkpoint_hp.duplicate(true)
	_gauntlet_run_authority["reset_count"] = _gauntlet_reset_count
	_gauntlet_run_authority["wasted_windows"] = _gauntlet_wasted_flure_windows


func _valid_gauntlet_run_authority(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var state := raw as Dictionary
	if str(state.get("contract", "")) != GAUNTLET_RUN_CONTRACT \
			or int(state.get("version", 0)) != GAUNTLET_RUN_VERSION \
			or state.get("required_party", []) != GAUNTLET_INTRO_REQUIRED_MEMBERS:
		return false
	var phase := str(state.get("phase", ""))
	if phase not in [
		GAUNTLET_RUN_PHASE_ACTIVE,
		GAUNTLET_RUN_PHASE_MIDPOINT_ARMING,
		GAUNTLET_RUN_PHASE_RESET_PENDING,
		GAUNTLET_RUN_PHASE_RESETTING,
		GAUNTLET_RUN_PHASE_TRANSITIONING,
	]:
		return false
	var stage := int(state.get("stage", -1))
	if stage not in [0, 1] \
			or bool(state.get("midpoint_reached", false)) != (stage == 1):
		return false
	var checkpoint_v: Variant = state.get("checkpoint_hp", null)
	if not (checkpoint_v is Dictionary):
		return false
	for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		if not (checkpoint_v as Dictionary).has(member_id) \
				or not is_finite(float((checkpoint_v as Dictionary).get(member_id, -1.0))) \
				or float((checkpoint_v as Dictionary).get(member_id, -1.0)) < 0.0:
			return false
	var windows_v: Variant = state.get("windows", null)
	if not (windows_v is Dictionary):
		return false
	for stage_key in ["0", "1"]:
		var window_v: Variant = (windows_v as Dictionary).get(stage_key, null)
		if not (window_v is Dictionary):
			return false
		var window_phase := str((window_v as Dictionary).get("phase", ""))
		var deadline := float((window_v as Dictionary).get("deadline", -1.0))
		if window_phase not in [
			GAUNTLET_WINDOW_READY, GAUNTLET_WINDOW_ACTIVE, GAUNTLET_WINDOW_FAILED,
		] or not is_finite(deadline):
			return false
		if (window_phase == GAUNTLET_WINDOW_READY and deadline >= 0.0) \
				or (window_phase != GAUNTLET_WINDOW_READY and deadline < 0.0):
			return false
	var next_poll := float(state.get("next_poll_tick", -1.0))
	var resume_poll := float(state.get("resume_poll_tick", -1.0))
	var reset_start_deadline := float(state.get("reset_start_deadline", -1.0))
	var reset_reason_v: Variant = state.get("reset_reason", null)
	var reset_deadline := float(state.get("reset_release_deadline", -1.0))
	var transition_deadline := float(state.get("transition_deadline", -1.0))
	if not (reset_reason_v is String) \
			or not is_finite(next_poll) or not is_finite(resume_poll) \
			or not is_finite(reset_start_deadline) \
			or not is_finite(reset_deadline) \
			or not is_finite(transition_deadline):
		return false
	if phase == GAUNTLET_RUN_PHASE_RESET_PENDING and reset_start_deadline < 0.0:
		return false
	if phase == GAUNTLET_RUN_PHASE_MIDPOINT_ARMING and resume_poll < 0.0:
		return false
	if phase == GAUNTLET_RUN_PHASE_RESET_PENDING and str(reset_reason_v).is_empty():
		return false
	if phase == GAUNTLET_RUN_PHASE_RESETTING and reset_deadline < 0.0:
		return false
	if phase == GAUNTLET_RUN_PHASE_TRANSITIONING and transition_deadline < 0.0:
		return false
	if phase != GAUNTLET_RUN_PHASE_RESET_PENDING and reset_start_deadline >= 0.0:
		return false
	if phase != GAUNTLET_RUN_PHASE_MIDPOINT_ARMING and resume_poll >= 0.0:
		return false
	if phase != GAUNTLET_RUN_PHASE_RESETTING and reset_deadline >= 0.0:
		return false
	if phase != GAUNTLET_RUN_PHASE_TRANSITIONING and transition_deadline >= 0.0:
		return false
	if phase != GAUNTLET_RUN_PHASE_ACTIVE and next_poll >= 0.0:
		return false
	return true


func _valid_gauntlet_cross_record_context() -> bool:
	var run_phase := str(_gauntlet_run_authority.get("phase", ""))
	var intro_phase := str(_gauntlet_intro_authority.get("phase", ""))
	if _current_step == "complete":
		return run_phase == GAUNTLET_RUN_PHASE_TRANSITIONING \
			and intro_phase == GAUNTLET_INTRO_PHASE_READY
	if _current_step != "gauntlet" or run_phase == GAUNTLET_RUN_PHASE_TRANSITIONING:
		return false
	if run_phase in [GAUNTLET_RUN_PHASE_RESET_PENDING, GAUNTLET_RUN_PHASE_RESETTING]:
		return intro_phase == GAUNTLET_INTRO_PHASE_READY
	if run_phase == GAUNTLET_RUN_PHASE_MIDPOINT_ARMING:
		return intro_phase == GAUNTLET_INTRO_PHASE_READY
	return true


func _reconcile_uncommitted_gauntlet_defeat() -> void:
	if _current_step != "gauntlet" \
			or str(_gauntlet_intro_authority.get("phase", "")) \
			!= GAUNTLET_INTRO_PHASE_READY \
			or str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_ACTIVE:
		return
	var defeated: Array[String] = []
	for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		if _game_state.characters.has(member_id) \
				and (_game_state.get_stat(member_id, "hp") <= 0.0 \
					or _game_state.is_downed(member_id)):
			defeated.append(member_id)
	if defeated.is_empty():
		return
	var delay: float = 0.1 \
		if defeated.size() == GAUNTLET_INTRO_REQUIRED_MEMBERS.size() else 0.4
	_gauntlet_run_authority["phase"] = GAUNTLET_RUN_PHASE_RESET_PENDING
	_gauntlet_run_authority["next_poll_tick"] = -1.0
	_gauntlet_run_authority["resume_poll_tick"] = -1.0
	_gauntlet_run_authority["reset_start_deadline"] = \
		_scheduler.get_current_tick() + delay
	_gauntlet_run_authority["reset_reason"] = "recovered_%s_downed" % defeated[0]
	_gauntlet_run_authority["reset_release_deadline"] = -1.0
	_gauntlet_run_authority["transition_deadline"] = -1.0


func _gauntlet_window_state(stage: int) -> Dictionary:
	if _gauntlet_run_authority.is_empty():
		return _gauntlet_window_baseline()
	var windows: Dictionary = _gauntlet_run_authority.get("windows", {})
	var raw: Variant = windows.get(str(stage), null)
	return (raw as Dictionary).duplicate(true) \
		if raw is Dictionary else _gauntlet_window_baseline()


func _set_gauntlet_window_state(stage: int, phase: String, deadline: float) -> void:
	if _gauntlet_run_authority.is_empty():
		_gauntlet_run_authority = _new_gauntlet_run_authority()
	var windows: Dictionary = (
		_gauntlet_run_authority.get("windows", {}) as Dictionary
	).duplicate(true)
	windows[str(stage)] = {"phase": phase, "deadline": deadline}
	_gauntlet_run_authority["windows"] = windows
	_gauntlet_flure_active[stage] = phase == GAUNTLET_WINDOW_ACTIVE
	_flure_active = bool(_gauntlet_flure_active.get(0, false)) \
		or bool(_gauntlet_flure_active.get(1, false))


func _cancel_gauntlet_runtime_callbacks() -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(GAUNTLET_INTRO_POLL_TAG)
	_scheduler.cancel_tag(GAUNTLET_POLL_TAG)
	_scheduler.cancel_tag(GAUNTLET_RESET_START_TAG)
	_scheduler.cancel_tag(GAUNTLET_RESET_TAG)
	# Retire callbacks written by authority versions predating reset-pending state.
	_scheduler.cancel_tag("gauntlet_party_reset")
	_scheduler.cancel_tag("gauntlet_hit_reset")
	for stage in range(2):
		_cancel_gauntlet_flure_timers(stage)


func _arm_gauntlet_progress_poll(deadline := -1.0) -> void:
	if _scheduler == null or _current_step != "gauntlet" \
			or str(_gauntlet_intro_authority.get("phase", "")) \
			!= GAUNTLET_INTRO_PHASE_READY \
			or str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_ACTIVE:
		return
	_scheduler.cancel_tag(GAUNTLET_POLL_TAG)
	var next_tick := float(deadline)
	if next_tick < 0.0:
		next_tick = _scheduler.get_current_tick() + GAUNTLET_POLL_INTERVAL
	next_tick = maxf(_scheduler.get_current_tick() + 0.000001, next_tick)
	_gauntlet_run_authority["next_poll_tick"] = next_tick
	_publish_elevator_runtime_authority()
	_scheduler.schedule_at(
		next_tick,
		_on_gauntlet_progress_poll.bind(next_tick),
		GAUNTLET_POLL_TAG
	)


func _on_gauntlet_progress_poll(expected_tick: float) -> void:
	if _current_step != "gauntlet" \
			or str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_ACTIVE \
			or not is_equal_approx(
				float(_gauntlet_run_authority.get("next_poll_tick", -1.0)),
				expected_tick):
		return
	_gauntlet_run_authority["next_poll_tick"] = -1.0
	if not _gauntlet_midpoint_reached \
			and _both_conscious_party_past_x(GAUNTLET_MIDPOINT.x - 2.0):
		_reach_gauntlet_midpoint(expected_tick + GAUNTLET_POLL_INTERVAL)
		return
	if _both_conscious_party_past_x(GAUNTLET_EXIT.x - 2.0):
		_tutorial_prompt.hide_prompt()
		for node in _available_party_control_nodes().values():
			if is_instance_valid(node) and node.has_method("set_move_enabled"):
				node.call("set_move_enabled", false)
		_complete()
		return
	_arm_gauntlet_progress_poll(expected_tick + GAUNTLET_POLL_INTERVAL)


func _gauntlet_flure_deadline(stage: int) -> float:
	if stage < 0 or stage >= _gauntlet_flure_interactables.size():
		return -1.0
	var station := _gauntlet_flure_interactables[stage] as Flure
	if not is_instance_valid(station):
		return -1.0
	var state := station.get_effect_state()
	return float(state.get("end_tick", -1.0)) \
		if str(state.get("phase", "")) == Flure.PHASE_ACTIVE else -1.0


func _arm_gauntlet_window_callbacks(stage: int) -> void:
	if _scheduler == null:
		return
	_cancel_gauntlet_flure_timers(stage)
	var window := _gauntlet_window_state(stage)
	var phase := str(window.get("phase", GAUNTLET_WINDOW_READY))
	var deadline := float(window.get("deadline", -1.0))
	if deadline < 0.0 or phase == GAUNTLET_WINDOW_READY:
		return
	var due := maxf(_scheduler.get_current_tick() + 0.000001, deadline)
	if phase == GAUNTLET_WINDOW_FAILED:
		_scheduler.schedule_at(
			due,
			_reset_failed_gauntlet_flure.bind(stage, deadline),
			"gauntlet_flure_failed_%d" % stage
		)
		return
	for remaining_v in [6.0, 2.0]:
		var remaining := float(remaining_v)
		var warning_tick: float = deadline - remaining
		if warning_tick > _scheduler.get_current_tick() + 0.000001:
			_scheduler.schedule_at(
				warning_tick,
				_warn_gauntlet_flure.bind(stage, remaining),
				"gauntlet_flure_warning_%d_%d" % [stage, int(remaining)]
			)
	_scheduler.schedule_at(
		due,
		_on_flure_expired.bind(stage, deadline),
		"flure_expire_%d" % stage
	)


func _restore_gauntlet_after_snapshot() -> void:
	_restore_gauntlet_run_after_snapshot()
	if _current_step == "gauntlet":
		_restore_gauntlet_intro_after_snapshot()
	elif _current_step == "complete" \
			and str(_gauntlet_intro_authority.get("phase", "")) \
			== GAUNTLET_INTRO_PHASE_READY:
		_sync_gauntlet_presenter_from_authority()


func _restore_gauntlet_run_after_snapshot() -> void:
	if _current_step not in ["gauntlet", "complete"] or _game_state == null:
		return
	_cancel_gauntlet_runtime_callbacks()
	if not _valid_gauntlet_run_authority(_gauntlet_run_authority) \
			or not _valid_gauntlet_cross_record_context():
		_recover_gauntlet_run_from_invalid_snapshot()
	else:
		_reconcile_uncommitted_gauntlet_defeat()
	_gauntlet_stage = int(_gauntlet_run_authority.get("stage", 0))
	_gauntlet_midpoint_reached = bool(
		_gauntlet_run_authority.get("midpoint_reached", false))
	_gauntlet_strategy = str(_gauntlet_run_authority.get("strategy", ""))
	_gauntlet_active_stage = int(_gauntlet_run_authority.get("active_stage", -1))
	_gauntlet_checkpoint_hp = (
		_gauntlet_run_authority.get("checkpoint_hp", {}) as Dictionary
	).duplicate(true)
	_gauntlet_reset_count = int(_gauntlet_run_authority.get("reset_count", 0))
	_gauntlet_wasted_flure_windows = int(
		_gauntlet_run_authority.get("wasted_windows", 0))
	_gauntlet_resetting = str(_gauntlet_run_authority.get("phase", "")) \
		== GAUNTLET_RUN_PHASE_RESETTING
	for stage in range(2):
		var window := _gauntlet_window_state(stage)
		var flower_deadline := _gauntlet_flure_deadline(stage)
		# The reusable Flure is the paid effect authority. If the host record was
		# absent or edited to READY while that flower is still active, reconstruct
		# the host classification from its committed report instead of erasing it.
		if flower_deadline >= 0.0:
			var station := _gauntlet_flure_interactables[stage] as Flure
			var report: Dictionary = station.get_effect_state().get(
				"last_activation_report", {}) as Dictionary
			var expected := (_gauntlet_enemy_groups.get(stage, []) as Array).size()
			var derived_phase := GAUNTLET_WINDOW_ACTIVE \
				if int(report.get("pulled", 0)) >= expected and expected > 0 \
				else GAUNTLET_WINDOW_FAILED
			if str(window.get("phase", "")) == GAUNTLET_WINDOW_READY \
					or not is_equal_approx(
						float(window.get("deadline", -1.0)), flower_deadline):
				_set_gauntlet_window_state(stage, derived_phase, flower_deadline)
				window = _gauntlet_window_state(stage)
		elif str(window.get("phase", "")) != GAUNTLET_WINDOW_READY:
			_set_gauntlet_window_state(stage, GAUNTLET_WINDOW_READY, -1.0)
			window = _gauntlet_window_state(stage)
		var window_phase := str(window.get("phase", GAUNTLET_WINDOW_READY))
		_gauntlet_flure_active[stage] = window_phase == GAUNTLET_WINDOW_ACTIVE
		_arm_gauntlet_window_callbacks(stage)
	_flure_active = bool(_gauntlet_flure_active.get(0, false)) \
		or bool(_gauntlet_flure_active.get(1, false))
	_ensure_endo_gauntlet_party_ui()
	match str(_gauntlet_run_authority.get("phase", "")):
		GAUNTLET_RUN_PHASE_ACTIVE:
			var next_poll := float(
				_gauntlet_run_authority.get("next_poll_tick", -1.0))
			if str(_gauntlet_intro_authority.get("phase", "")) \
					== GAUNTLET_INTRO_PHASE_READY:
				_arm_gauntlet_progress_poll(next_poll)
		GAUNTLET_RUN_PHASE_MIDPOINT_ARMING:
			_resume_gauntlet_midpoint_arming()
		GAUNTLET_RUN_PHASE_RESET_PENDING:
			for node in _available_party_control_nodes().values():
				if is_instance_valid(node) and node.has_method("set_move_enabled"):
					node.call("set_move_enabled", false)
			var reset_start_deadline := float(
				_gauntlet_run_authority.get("reset_start_deadline", -1.0))
			_scheduler.schedule_at(
				maxf(_scheduler.get_current_tick() + 0.000001, reset_start_deadline),
				_begin_gauntlet_reset.bind(reset_start_deadline),
				GAUNTLET_RESET_START_TAG
			)
		GAUNTLET_RUN_PHASE_RESETTING:
			var reset_deadline := float(
				_gauntlet_run_authority.get("reset_release_deadline", -1.0))
			_scheduler.schedule_at(
				maxf(_scheduler.get_current_tick() + 0.000001, reset_deadline),
				_finish_gauntlet_reset.bind(reset_deadline),
				GAUNTLET_RESET_TAG
			)
		GAUNTLET_RUN_PHASE_TRANSITIONING:
			var transition_deadline := float(
				_gauntlet_run_authority.get("transition_deadline", -1.0))
			_fade_start_tick = transition_deadline - 2.0
			_scheduler.schedule_at(
				maxf(_scheduler.get_current_tick() + 0.000001, transition_deadline),
				_do_complete_scene_change.bind(transition_deadline),
				"complete_change"
			)
	_publish_elevator_runtime_authority()


## Missing or malformed run authority cannot inherit spatial progress from the
## discarded presenter. Reconstruct the known start checkpoint, including all
## three physical bodies and both reusable stations. This deliberately loses
## progress instead of granting a midpoint/exit from unauthoritative positions.
func _recover_gauntlet_run_from_invalid_snapshot() -> void:
	_current_step = "gauntlet"
	_gauntlet_stage = 0
	_gauntlet_midpoint_reached = false
	_gauntlet_strategy = ""
	_gauntlet_active_stage = -1
	_gauntlet_resetting = false
	_gauntlet_reset_count = 0
	_gauntlet_wasted_flure_windows = 0
	_gauntlet_flure_active = {0: false, 1: false}
	_flure_active = false
	_gauntlet_checkpoint_hp.clear()
	var targets := _gauntlet_intro_targets()
	for member_id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		if not _game_state.characters.has(member_id):
			continue
		_game_state.command_stop(member_id)
		var target: Vector3 = targets.get(
			member_id, Vector3(GAUNTLET_POS.x - 6.0, BELOW_Y + 0.5, 0.0))
		_game_state.snap_character_to(member_id, target)
		var presenter := _elevator_party_node(member_id)
		if presenter != null:
			presenter.global_position = target
		_gauntlet_checkpoint_hp[member_id] = maxf(
			0.0, _game_state.get_stat(member_id, "hp"))
	for stage in range(_gauntlet_flure_interactables.size()):
		var station := _gauntlet_flure_interactables[stage] as Flure
		if not is_instance_valid(station):
			continue
		station.reset_flure()
		station.reset()
		station.set_interaction_enabled(false)
	for stage in range(2):
		_clear_gauntlet_stage_marker(stage)
		for enemy_v in _gauntlet_enemy_groups.get(stage, []):
			var enemy := enemy_v as Enemy
			if not is_instance_valid(enemy) or not enemy.is_alive():
				continue
			enemy.set_detection_targets([])
			enemy.re_post(_gauntlet_enemy_posts.get(enemy.char_id, enemy.global_position))
	_gauntlet_run_authority = _new_gauntlet_run_authority()


func _restore_gauntlet_intro_after_snapshot() -> void:
	if _current_step != "gauntlet" or _game_state == null:
		return
	_ensure_endo_gauntlet_party_ui()
	if _fade_rect != null:
		_fade_rect.color.a = 0.0
	for stage in range(2):
		_clear_gauntlet_stage_marker(stage)
	_clear_gauntlet_context_markers()
	for station_v in _gauntlet_flure_interactables:
		var station := station_v as Flure
		if is_instance_valid(station):
			station.set_interaction_enabled(false)
	if _gauntlet_intro_authority.is_empty() \
			or not _valid_gauntlet_intro_authority(_gauntlet_intro_authority):
		_gauntlet_intro_authority = _new_gauntlet_intro_authority()
	if str(_gauntlet_intro_authority.get("phase", "")) \
			== GAUNTLET_INTRO_PHASE_ARMING:
		_apply_character_control_selection()
		_resume_gauntlet_intro_arming()
		return
	if str(_gauntlet_intro_authority.get("phase", "")) == GAUNTLET_INTRO_PHASE_READY:
		_sync_gauntlet_presenter_from_authority()
		return
	_apply_character_control_selection()
	_arm_gauntlet_intro_poll()
	if not bool(_gauntlet_intro_authority.get("presentation_complete", false)):
		_reset_endo_entry_dialogue_for_restore()
		_dialogue_chain([
			"junction.aster.blocked",
			"junction.peris.flure",
		], _finish_gauntlet_intro)
	_publish_elevator_runtime_authority()

## Inert compatibility seam. The gauntlet begins only when Peris services the exact visible Flure.
func _on_flure_activated() -> void:
	pass

func _on_gauntlet_flure_activated(pulled: int, stage: int) -> void:
	if stage < 0 or stage >= _gauntlet_flure_interactables.size():
		return
	if str(_gauntlet_run_authority.get("phase", "")) != GAUNTLET_RUN_PHASE_ACTIVE \
			or str(_gauntlet_intro_authority.get("phase", "")) \
			!= GAUNTLET_INTRO_PHASE_READY \
			or str(_gauntlet_window_state(stage).get("phase", "")) \
			!= GAUNTLET_WINDOW_READY:
		return
	if stage == 1 and not _gauntlet_midpoint_reached:
		return
	var station := _gauntlet_flure_interactables[stage]
	var report := station.get_last_activation_report()
	var expected := (_gauntlet_enemy_groups.get(stage, []) as Array).size()
	if expected <= 0 or pulled < expected:
		_gauntlet_wasted_flure_windows += 1
		station.set_interaction_enabled(false)
		var failed_deadline := _gauntlet_flure_deadline(stage)
		if failed_deadline < 0.0:
			failed_deadline = _scheduler.get_current_tick() + station.lure_duration
		_set_gauntlet_window_state(
			stage, GAUNTLET_WINDOW_FAILED, failed_deadline)
		_publish_elevator_runtime_authority()
		var committed := (report.get("committed_ids", []) as Array).size()
		if committed > 0:
			_hud.show_message(
				"PACK %d / TOO LATE — %d/%d guards were already attacking. Break contact and retry before acquisition." % [
					stage + 1, committed, expected,
				],
				3.4
			)
		else:
			_hud.show_message(
				"PACK %d / INCOMPLETE SIGNAL — %d/%d guards pulled. Check the linked pack and retry after rearming." % [
					stage + 1, pulled, expected,
				],
				3.2
			)
		_arm_gauntlet_window_callbacks(stage)
		return
	var active_deadline := _gauntlet_flure_deadline(stage)
	if active_deadline < 0.0:
		active_deadline = _scheduler.get_current_tick() + station.lure_duration
	_set_gauntlet_window_state(stage, GAUNTLET_WINDOW_ACTIVE, active_deadline)
	_gauntlet_active_stage = stage
	station.set_interaction_enabled(false)
	_tutorial_prompt.hide_prompt()
	var lure_pos := FLURE_POS if stage == 0 else GAUNTLET_FLURE_2_POS
	_show_gauntlet_stage_marker(stage, lure_pos + Vector3(0, 1.5, 0), "LURE %d ACTIVE" % (stage + 1))
	_dialogue.default_hold_time = 2.0
	if stage == 0:
		DialogueData.say_to(_dialogue, "junction.flure.active")
	var active_duration := station.lure_duration
	_hud.show_message(
		"PACK %d PULLED / %ds — move the WHOLE PARTY before the watch returns." % [
			stage + 1, int(active_duration),
		],
		3.0
	)
	_publish_elevator_runtime_authority()
	_arm_gauntlet_window_callbacks(stage)

func _cancel_gauntlet_flure_timers(stage: int) -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag("flure_expire_%d" % stage)
	_scheduler.cancel_tag("gauntlet_flure_failed_%d" % stage)
	for remaining in [6, 2]:
		_scheduler.cancel_tag("gauntlet_flure_warning_%d_%d" % [stage, remaining])

func _reset_failed_gauntlet_flure(stage: int, expected_deadline := -1.0) -> void:
	if stage < 0 or stage >= _gauntlet_flure_interactables.size() \
			or str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_ACTIVE \
			or str(_gauntlet_window_state(stage).get("phase", "")) \
			!= GAUNTLET_WINDOW_FAILED:
		return
	var saved_deadline := float(_gauntlet_window_state(stage).get("deadline", -1.0))
	if expected_deadline >= 0.0 and not is_equal_approx(saved_deadline, expected_deadline):
		return
	var station := _gauntlet_flure_interactables[stage]
	if is_instance_valid(station):
		station.reset_flure()
		station.reset()
	_set_gauntlet_window_state(stage, GAUNTLET_WINDOW_READY, -1.0)
	_sync_gauntlet_station_interactivity()
	_publish_elevator_runtime_authority()
	_hud.show_message("PACK %d / FLURE REARMED" % (stage + 1), 1.8)


func _warn_gauntlet_flure(stage: int, remaining: float) -> void:
	if _current_step != "gauntlet" \
			or str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_ACTIVE \
			or str(_gauntlet_window_state(stage).get("phase", "")) \
			!= GAUNTLET_WINDOW_ACTIVE:
		return
	_hud.show_message(
		"PACK %d / %ds — the watch is returning." % [stage + 1, int(remaining)],
		1.8
	)


func _on_flure_expired(stage := -1, expected_deadline := -1.0) -> void:
	var resolved_stage: int = _gauntlet_active_stage if int(stage) < 0 else int(stage)
	if resolved_stage < 0 \
			or str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_ACTIVE \
			or str(_gauntlet_window_state(resolved_stage).get("phase", "")) \
			!= GAUNTLET_WINDOW_ACTIVE:
		return
	var saved_deadline := float(
		_gauntlet_window_state(resolved_stage).get("deadline", -1.0))
	if expected_deadline >= 0.0 and not is_equal_approx(saved_deadline, expected_deadline):
		return
	_set_gauntlet_window_state(resolved_stage, GAUNTLET_WINDOW_READY, -1.0)
	_clear_gauntlet_stage_marker(resolved_stage)
	if resolved_stage < _gauntlet_flure_interactables.size():
		var station := _gauntlet_flure_interactables[resolved_stage]
		if is_instance_valid(station):
			station.reset_flure()
			station.reset()
	_sync_gauntlet_station_interactivity()
	_publish_elevator_runtime_authority()
	_hud.show_message(
		"PACK %d / WINDOW CLOSED — the watch has returned." % (resolved_stage + 1),
		2.4
	)

func _reach_gauntlet_midpoint(resume_poll_tick := -1.0) -> void:
	if _gauntlet_midpoint_reached \
			or str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_ACTIVE:
		return
	_gauntlet_midpoint_reached = true
	_gauntlet_stage = 1
	if _gauntlet_strategy == "":
		_gauntlet_strategy = "safe_relay" if bool(_gauntlet_flure_active.get(0, false)) else "fast_direct"
	_store_gauntlet_checkpoint_hp()
	var resume_tick := float(resume_poll_tick)
	if resume_tick < 0.0:
		resume_tick = _scheduler.get_current_tick() + GAUNTLET_POLL_INTERVAL
	_gauntlet_run_authority["phase"] = GAUNTLET_RUN_PHASE_MIDPOINT_ARMING
	_gauntlet_run_authority["next_poll_tick"] = -1.0
	_gauntlet_run_authority["resume_poll_tick"] = resume_tick
	_publish_elevator_runtime_authority()
	_resume_gauntlet_midpoint_arming()


func _resume_gauntlet_midpoint_arming() -> void:
	if str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_MIDPOINT_ARMING:
		return
	for enemy in _gauntlet_enemy_groups.get(1, []):
		if is_instance_valid(enemy) and enemy.is_alive():
			if enemy.get_detection_targets() != GAUNTLET_INTRO_REQUIRED_MEMBERS:
				enemy.set_detection_targets(GAUNTLET_INTRO_REQUIRED_MEMBERS)
			if enemy.get_state() == "idle":
				enemy.begin_home_behavior()
	var resume_tick := float(_gauntlet_run_authority.get(
		"resume_poll_tick", _scheduler.get_current_tick() + GAUNTLET_POLL_INTERVAL))
	_gauntlet_run_authority["phase"] = GAUNTLET_RUN_PHASE_ACTIVE
	_gauntlet_run_authority["resume_poll_tick"] = -1.0
	_gauntlet_run_authority["next_poll_tick"] = resume_tick
	_publish_elevator_runtime_authority()
	_sync_gauntlet_presenter_from_authority()
	_arm_gauntlet_progress_poll(resume_tick)

func _store_gauntlet_checkpoint_hp() -> void:
	_gauntlet_checkpoint_hp.clear()
	for id in GAUNTLET_INTRO_REQUIRED_MEMBERS:
		if _game_state.characters.has(id):
			_gauntlet_checkpoint_hp[id] = _game_state.get_stat(id, "hp")


func _request_gauntlet_reset(delay: float, reason: String) -> void:
	if _scheduler == null or _current_step != "gauntlet" \
			or str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_ACTIVE:
		return
	var reset_start_deadline := _scheduler.get_current_tick() + maxf(delay, 0.0)
	_gauntlet_run_authority["phase"] = GAUNTLET_RUN_PHASE_RESET_PENDING
	_gauntlet_run_authority["next_poll_tick"] = -1.0
	_gauntlet_run_authority["resume_poll_tick"] = -1.0
	_gauntlet_run_authority["reset_start_deadline"] = reset_start_deadline
	_gauntlet_run_authority["reset_reason"] = reason
	_gauntlet_run_authority["reset_release_deadline"] = -1.0
	_gauntlet_run_authority["transition_deadline"] = -1.0
	_scheduler.cancel_tag(GAUNTLET_POLL_TAG)
	_scheduler.cancel_tag(GAUNTLET_RESET_START_TAG)
	# Commit the consequence before disabling controls/stations: either derived
	# presenter write can emit a save-observable GameState signal.
	_publish_elevator_runtime_authority()
	for node in _available_party_control_nodes().values():
		if is_instance_valid(node) and node.has_method("set_move_enabled"):
			node.call("set_move_enabled", false)
	_sync_gauntlet_station_interactivity()
	_scheduler.schedule_at(
		maxf(_scheduler.get_current_tick() + 0.000001, reset_start_deadline),
		_begin_gauntlet_reset.bind(reset_start_deadline),
		GAUNTLET_RESET_START_TAG
	)


func _begin_gauntlet_reset(expected_deadline: float) -> void:
	if str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_RESET_PENDING \
			or not is_equal_approx(float(_gauntlet_run_authority.get(
				"reset_start_deadline", -1.0)), expected_deadline):
		return
	_reset_gauntlet_to_refuge()


func _reset_gauntlet_to_refuge() -> void:
	var run_phase := str(_gauntlet_run_authority.get("phase", ""))
	if _gauntlet_resetting or _current_step != "gauntlet" \
			or run_phase not in [
				GAUNTLET_RUN_PHASE_ACTIVE, GAUNTLET_RUN_PHASE_RESET_PENDING,
			]:
		return
	_gauntlet_resetting = true
	_gauntlet_reset_count += 1
	var base := GAUNTLET_MIDPOINT if _gauntlet_midpoint_reached else Vector3(GAUNTLET_POS.x - 8.0, BELOW_Y, 0)
	var placements := {
		"aster": base + Vector3(-0.8, 0.5, -0.7),
		"peris": base + Vector3(-0.8, 0.5, 0.7),
		"endo": base + Vector3(-1.8, 0.5, 0.0),
	}
	for id in placements:
		if not _game_state.characters.has(id):
			continue
		_game_state.command_stop(id)
		if _game_state.get_character_level(id) != LEVEL_LOWER:
			_game_state.set_character_level(id, LEVEL_LOWER)
		var pos: Vector3 = placements[id]
		_game_state.snap_character_to(id, pos)
		var node := _elevator_party_node(id)
		if node != null:
			node.global_position = pos
		var target_hp := float(_gauntlet_checkpoint_hp.get(id, PARTY_MAX_HP))
		# HP alone does not revive a downed GameState character: the narrative
		# availability latch is authoritative too. Restore first, then preserve the
		# checkpoint's actual HP instead of silently awarding a full heal.
		_game_state.restore_character(id)
		_game_state.adjust_stat(id, "hp", target_hp - _game_state.get_stat(id, "hp"))
		_hud.set_portrait_status(id, "")
	_gauntlet_active_stage = -1
	# A first-pack pursuer can follow the party across the midpoint. Reset every
	# reachable pack and every outstanding Flure generation, not merely the pack
	# associated with the current checkpoint.
	for stage in range(2):
		_cancel_gauntlet_flure_timers(stage)
		_clear_gauntlet_stage_marker(stage)
		_set_gauntlet_window_state(stage, GAUNTLET_WINDOW_READY, -1.0)
		if stage < _gauntlet_flure_interactables.size():
			var station := _gauntlet_flure_interactables[stage] as Flure
			station.reset_flure()
			station.reset()
			station.set_interaction_enabled(false)
		for enemy_v in _gauntlet_enemy_groups.get(stage, []):
			var enemy := enemy_v as Enemy
			if is_instance_valid(enemy) and enemy.is_alive():
				enemy.set_detection_targets(GAUNTLET_INTRO_REQUIRED_MEMBERS)
				enemy.re_post(_gauntlet_enemy_posts.get(
					enemy.char_id, enemy.global_position))
	_clear_gauntlet_context_marker("midpoint")
	_show_gauntlet_context_marker(
		"reset", base + Vector3(0, 2.0, 0), "REFUGE RESET")
	var reset_deadline := _scheduler.get_current_tick() + 1.0
	_gauntlet_run_authority["phase"] = GAUNTLET_RUN_PHASE_RESETTING
	_gauntlet_run_authority["next_poll_tick"] = -1.0
	_gauntlet_run_authority["resume_poll_tick"] = -1.0
	_gauntlet_run_authority["reset_start_deadline"] = -1.0
	_gauntlet_run_authority["reset_release_deadline"] = reset_deadline
	_publish_elevator_runtime_authority()
	_scheduler.cancel_tag(GAUNTLET_POLL_TAG)
	_scheduler.cancel_tag(GAUNTLET_RESET_START_TAG)
	_scheduler.cancel_tag(GAUNTLET_RESET_TAG)
	_scheduler.schedule_at(
		reset_deadline,
		_finish_gauntlet_reset.bind(reset_deadline),
		GAUNTLET_RESET_TAG
	)


func _finish_gauntlet_reset(expected_deadline: float) -> void:
	if str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_RESETTING \
			or not is_equal_approx(float(_gauntlet_run_authority.get(
				"reset_release_deadline", -1.0)), expected_deadline):
		return
	_gauntlet_resetting = false
	_gauntlet_run_authority["phase"] = GAUNTLET_RUN_PHASE_ACTIVE
	_gauntlet_run_authority["reset_reason"] = ""
	_gauntlet_run_authority["reset_release_deadline"] = -1.0
	_clear_gauntlet_context_marker("reset")
	if _gauntlet_midpoint_reached:
		_show_gauntlet_context_marker(
			"midpoint", GAUNTLET_MIDPOINT + Vector3(0, 2.0, 0),
			"MIDPOINT REFUGE")
	_publish_elevator_runtime_authority()
	_sync_gauntlet_presenter_from_authority()
	_arm_gauntlet_progress_poll()

## Evidence-backed first-clear budget. This is a pacing contract, not a timer:
## no entry can be earned by waiting, and dialogue is allowed to overlap movement.
## The active estimate covers route finding, character swaps, spatial reads,
## encounter execution, and recovery; presentation time covers the 59 existing
## authored lines and short collapse/night transitions.
func get_playtime_contract() -> Dictionary:
	var critical_route_meters := (BRIDGE_COLLAPSE_X - BRIDGE_START_X) \
		+ (ROUTES_CONVERGE.x - BRIDGE_COLLAPSE_X) \
		+ (JUNCTION_POS.x - ROUTES_CONVERGE.x) \
		+ (GAUNTLET_EXIT.x - JUNCTION_POS.x)
	var meaningful_active_seconds := 500.0
	var total_play_seconds := 680.0
	return {
		"contract_id": "elevator_first_clear_systemic_v4",
		"required_first_clear_seconds": 480.0,
		"target_min_seconds": 480.0,
		"target_max_seconds": 720.0,
		"modeled_first_clear_seconds": total_play_seconds,
		"modeled_meaningful_active_seconds": meaningful_active_seconds,
		"meaningful_active_seconds": meaningful_active_seconds,
		"total_play_seconds": total_play_seconds,
		"modeled_presentation_seconds": 180.0,
		"modeled_navigation_seconds": 150.0,
		"modeled_decision_execution_seconds": 95.0,
		"modeled_hazard_adaptation_seconds": 90.0,
		"modeled_system_observation_seconds": 85.0,
		"modeled_field_execution_seconds": 0.0,
		"meaningful_active_ratio": meaningful_active_seconds / total_play_seconds,
		"active_ratio": meaningful_active_seconds / total_play_seconds,
		"max_dead_gap_seconds": 4.8,
		"max_single_mode_seconds": 42.0,
		"category_seconds": {
			"navigation": 150.0,
			"system_observation": 85.0,
			"planning": 95.0,
			"hazard_adaptation": 90.0,
			"execution": 80.0,
		},
		"critical_route_meters": critical_route_meters,
		"mandatory_dialogue_lines": 59,
		"mandatory_route_overlay_reads": ROUTE_REQUIRED_READS,
		"systemic_route_beats": ROUTE_BEAT_COUNT,
		"route_strategies": 3,
		"route_crossovers": ROUTE_CROSSOVER_X_OFFSETS.size(),
		"mandatory_wreckage_assists": 2,
		"mandatory_junction_inspections": JUNCTION_REQUIRED_INSPECTIONS,
		"optional_junction_inspections": _junction_survey_specs().size(),
		"mandatory_character_perspectives": 0,
		"mandatory_field_protocols": 0,
		"mandatory_field_evidence": 0,
		"mandatory_field_actions": 0,
		"fieldwork_seconds": 0.0,
		"field_route_meters": 0.0,
		"solved_state_execution_tail_actions": 1,
		"solved_state_execution_tail_seconds": 2.5,
		"gauntlet_stages": 2,
		"decision_count": 5,
		"branch_count": 6,
		"hard_idle_lock_seconds": 0.0,
		"dialogue_overlap_allowed": true,
	}

func headless_get_anchor_positions() -> Dictionary:
	return {
		"bridge_collapse": Vector3(BRIDGE_COLLAPSE_X, 0.0, 0.0),
		"route_overlay_aster": ROUTE_READ_ASTER_POS,
		"route_overlay_peris": ROUTE_READ_PERIS_POS,
		"route_fork": FORK_POS,
		"route_crossover_1": Vector3(FORK_POS.x + float(ROUTE_CROSSOVER_X_OFFSETS[0]), BELOW_Y, 0.0),
		"route_crossover_2": Vector3(FORK_POS.x + float(ROUTE_CROSSOVER_X_OFFSETS[1]), BELOW_Y, 0.0),
		"route_flure_1": _route_flure_position(0),
		"route_flure_2": _route_flure_position(1),
		"route_flure_3": _route_flure_position(2),
		"route_converge": ROUTES_CONVERGE,
		"wreckage_gate": WRECKAGE_GATE_POS,
		"junction": JUNCTION_POS,
		"gauntlet_entrance": Vector3(GAUNTLET_POS.x - 8.0, BELOW_Y, 0.0),
		"gauntlet_flure_1": FLURE_POS,
		"gauntlet_midpoint": GAUNTLET_MIDPOINT,
		"gauntlet_flure_2": GAUNTLET_FLURE_2_POS,
		"gauntlet_exit": GAUNTLET_EXIT,
	}

func _route_flure_source_is_active(index: int) -> bool:
	return str(_route_flure_effect_state(index).get(
		"phase", Flure.PHASE_READY)) == Flure.PHASE_ACTIVE


func _route_flure_source_end_tick(index: int) -> float:
	var state := _route_flure_effect_state(index)
	return float(state.get("end_tick", -1.0)) \
		if str(state.get("phase", Flure.PHASE_READY)) == Flure.PHASE_ACTIVE else -1.0


func _route_flure_active_states() -> Array[bool]:
	var result: Array[bool] = []
	for index in range(ROUTE_BEAT_COUNT):
		result.append(_route_flure_source_is_active(index))
	return result


func _route_flure_source_end_ticks() -> Array[float]:
	var result: Array[float] = []
	for index in range(ROUTE_BEAT_COUNT):
		result.append(_route_flure_source_end_tick(index))
	return result


func _route_flure_window_usage() -> Array[bool]:
	var result: Array[bool] = []
	for index in range(ROUTE_BEAT_COUNT):
		result.append(_route_flure_window_used(index))
	return result


func headless_get_state() -> Dictionary:
	var state: Dictionary = super.headless_get_state()
	state.merge({
		"overlay_states": _elevator_overlay_states.duplicate(),
		"overlays_available": _elevator_overlays_available,
		"aster_route_overlay_visible": is_instance_valid(_aster_route_overlay_root) \
			and _aster_route_overlay_root.visible,
		"peris_route_overlay_visible": is_instance_valid(_peris_route_overlay_root) \
			and _peris_route_overlay_root.visible,
		"route_solution_marker_present": is_instance_valid(_peris_route_overlay_endpoint),
		"route_reads_resolved": _route_reads_resolved.duplicate(),
		"route_read_count": _route_reads_resolved.values().count(true),
		"route_lane": _route_lane,
		"route_beats_crossed": _route_beats_crossed.duplicate(),
		"route_beat_lanes": _route_beat_lanes.duplicate(),
		"route_beat_character_lanes": _route_beat_character_lanes.duplicate(true),
		"route_beat_character_windows": _route_beat_character_windows.duplicate(true),
		"route_beat_character_window_sources": \
			_route_beat_character_window_sources.duplicate(true),
		"route_flures_activated": _route_flure_active_states(),
		"route_flure_end_ticks": _route_flure_source_end_ticks(),
		"route_flure_activation_counts": _route_flure_activation_counts.duplicate(),
		"route_flure_failed_counts": _route_flure_failed_counts.duplicate(),
		"route_flure_windows_used": _route_flure_window_usage(),
		"route_wasted_flure_windows": _route_wasted_flure_windows,
		"route_iron_damage_taken": _route_iron_damage_taken,
		"route_enemy_damage_taken": _route_enemy_damage_taken,
		"route_elapsed_seconds": maxf(0.0, (_route_finished_tick if _route_finished_tick >= 0.0 \
			else _scheduler.get_current_tick()) - _route_started_tick) if _route_started_tick >= 0.0 else 0.0,
		"route_failure_provenance": _route_failure_provenance.duplicate(true),
		"wreckage_armed": _wreckage_armed,
		"wreckage_party_ready": _wreckage_party_ready(),
		"wreckage_clear_in_progress": _wreckage_clear_in_progress,
		"wreckage_cleared": _wreckage_cleared,
		"wreckage_solo_attempted": _wreckage_solo_attempted,
		"wreckage_failure_active": _wreckage_failure_active,
		"wreckage_alert_target": _wreckage_alert_target,
		"source_committed_counts": _elevator_source_committed_counts.duplicate(true),
		"junction_inspection_ids": _junction_beat.survey.observation_ids() if _junction_beat != null else [],
		"junction_inspection_count": _junction_beat.survey.observation_count() if _junction_beat != null else 0,
		"junction_inspected_by": _junction_beat.survey.actor_presence() if _junction_beat != null else {},
		"junction_survey_ready": _junction_survey_ready(),
		"junction_tended": _junction_beat.is_complete() if _junction_beat != null else false,
		"junction_plant_enabled": is_instance_valid(_junction_plant_interactable) \
			and bool(_junction_plant_interactable.get("interaction_enabled")),
		"gauntlet_stage": _gauntlet_stage,
		"gauntlet_intro": _gauntlet_intro_authority.duplicate(true),
		"gauntlet_run": _gauntlet_run_authority.duplicate(true),
		"gauntlet_midpoint_reached": _gauntlet_midpoint_reached,
		"gauntlet_strategy": _gauntlet_strategy,
		"gauntlet_flure_active": _gauntlet_flure_active.duplicate(),
		"gauntlet_reset_count": _gauntlet_reset_count,
		"gauntlet_wasted_flure_windows": _gauntlet_wasted_flure_windows,
		"damage_feedback_counts": _damage_feedback_counts.duplicate(),
		"below_fauna_enabled": _below_fauna_active,
		"below_fauna_dormant": _below_dormant_enemy_setups.size(),
	}, true)
	return state

func _complete() -> void:
	if _current_step != "gauntlet" or not _enter_step("complete"):
		return
	var transition_deadline := _scheduler.get_current_tick() + 2.0
	_cancel_gauntlet_runtime_callbacks()
	if not _gauntlet_run_authority.is_empty():
		_gauntlet_run_authority["phase"] = GAUNTLET_RUN_PHASE_TRANSITIONING
		_gauntlet_run_authority["next_poll_tick"] = -1.0
		_gauntlet_run_authority["resume_poll_tick"] = -1.0
		_gauntlet_run_authority["reset_start_deadline"] = -1.0
		_gauntlet_run_authority["reset_reason"] = ""
		_gauntlet_run_authority["reset_release_deadline"] = -1.0
		_gauntlet_run_authority["transition_deadline"] = transition_deadline
		_publish_elevator_runtime_authority()
		_sync_gauntlet_station_interactivity()
	for node in _available_party_control_nodes().values():
		if is_instance_valid(node) and node.has_method("set_move_enabled"):
			node.call("set_move_enabled", false)
	# Fade + scene change ride the scheduler (not a wall-clock tween), so the
	# blackout and the swap fire on the scheduler clock and never race a paused
	# or fast-forwarded sequence. The fade alpha is driven per-frame in
	# _on_process while the step is "complete".
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_at(
		transition_deadline,
		_do_complete_scene_change.bind(transition_deadline),
		"complete_change"
	)

func _do_complete_scene_change(expected_deadline := -1.0) -> void:
	if _current_step != "complete" \
			or str(_gauntlet_run_authority.get("phase", "")) \
			!= GAUNTLET_RUN_PHASE_TRANSITIONING \
			or expected_deadline < 0.0 \
			or not is_equal_approx(float(_gauntlet_run_authority.get(
				"transition_deadline", -1.0)), expected_deadline):
		return
	_change_scene_or_record("res://scenes/tutorial/act1.tscn")

# --- Game Over ---

func _start_game_over() -> void:
	if _game_over:
		return
	var perf_started := PerformanceTrace.begin()
	_game_over = true
	_enter_step("game_over")
	_player.set_move_enabled(false)
	# Enemy FSM transitions and movement all ride the authoritative gameplay
	# scheduler, so pausing it freezes every attacker atomically. Forcing each
	# (including dormant) enemy through idle here would cascade movement stops
	# and detection rebuilds inside the lethal damage signal.
	_scheduler.pause()
	# Fade to dark red-black
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color", Color(0.08, 0.02, 0.02, 0.85), 2.0)
	tween.tween_callback(_show_game_over_text)
	PerformanceTrace.end(&"update", &"elevator.game_over.enter", perf_started, "party", 1)

func _show_game_over_text() -> void:
	var overlay := preload("res://scenes/ui/game_over_overlay.tscn").instantiate() as GameOverOverlay
	add_child(overlay)
	# Nothing carried through the elevator survives past it either way, so taking the level again
	# costs the player only the walk.
	overlay.set_guidance(GameOverOverlay.DEFAULT_GUIDANCE)
	overlay.reset_requested.connect(_on_game_over_reset)
	overlay.reveal()

## The overlay asks; the scene change belongs to the host. This is the same restart the pause menu
## offers, taken through the same door: the scene gets its `prepare_scene_restart` notice, and the
## tree is released so the replacement starts live rather than inheriting the death pause.
func _on_game_over_reset() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("prepare_scene_restart"):
		current_scene.call("prepare_scene_restart")
	get_tree().paused = false
	get_tree().reload_current_scene()

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
	b2.name = "BridgeDeckCollision"
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

## Give the intact span a truthful destination. A deck ending in unlit void makes its last third vanish
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
	_iron_hazard_next_tick = -1.0
	_aster_route_overlay_root = null
	_peris_route_overlay_root = null
	_peris_route_overlay_endpoint = null
	_route_flure_interactables.clear()
	_route_flure_meshes.clear()
	_route_flure_enemy_groups.clear()
	_route_flure_countdown_labels.clear()
	_route_causal_links.clear()
	# Stream construction resets presenters only. Route knowledge, crossings, and source-window
	# history are restored from the versioned runtime record, never invented or erased by a chunk.
	if _scheduler != null:
		for route_flure_i in range(ROUTE_BEAT_COUNT):
			_scheduler.cancel_tag("route_flure_feedback_%d" % route_flure_i)
	_grated_platforms = null
	_grated_platform_signal_marker = null
	_grated_platform_enemy_markers.clear()
	_grated_platform_wall_openings.clear()
	_wreckage_gate = null
	_wreckage_interactable = null
	_wreckage_listeners.clear()
	_clear_iron_route_risk_cells()
	_iron_patches.clear()
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
	_below_step_grated_platforms_layout(parent)
	_below_step_grated_platforms_navigation(parent)

func _below_step_grated_platforms_layout(parent: Node3D) -> void:
	if is_instance_valid(_grated_platforms):
		return
	var instance_started := PerformanceTrace.begin()
	_grated_platforms = _take_prewarmed_scene(
		&"elevator_grated_platforms", GRATED_PLATFORMS_SCENE) as Node3D
	PerformanceTrace.end(&"draw", &"elevator.below.grated_platforms_instance", instance_started,
		"prewarmed", 1 if _grated_platforms != null else 0)
	_grated_platforms.position = GRATED_PLATFORM_POS
	var tree_started := PerformanceTrace.begin()
	parent.add_child(_grated_platforms)
	PerformanceTrace.end(&"draw", &"elevator.below.grated_platforms_tree_entry", tree_started,
		"below", 1)

func _below_step_grated_platforms_navigation(_parent: Node3D) -> void:
	if not is_instance_valid(_grated_platforms) \
			or bool(_grated_platforms.get_meta("navigation_bound", false)):
		return
	_grated_platforms.set_meta("navigation_bound", true)
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
		FORK_POS.x + float(ROUTE_BEAT_OFFSETS[beat_i]) - 1.0,
		BELOW_Y + 0.3,
		-1.6
	)


func _route_flure_settle_position(beat_i: int, interaction_pos: Vector3) -> Vector3:
	# The interaction perch and the fauna settle point must be visibly linked but physically distinct.
	# Pulling a pack onto Peris's exact interaction point made correct play unavoidably lethal.
	if beat_i == GRATED_PLATFORM_ROUTE_BEAT and is_instance_valid(_grated_platforms):
		var connector := _grated_platforms.get_node_or_null("Markers/WalkableConnector") as Marker3D
		if connector != null:
			return connector.global_position
	return Vector3(interaction_pos.x, BELOW_Y + 0.5, -6.35)

func _route_enemy_position(beat_i: int, local_i: int) -> Vector3:
	if beat_i == GRATED_PLATFORM_ROUTE_BEAT and local_i >= 0 \
			and local_i < _grated_platform_enemy_markers.size():
		var marker := _grated_platform_enemy_markers[local_i]
		if is_instance_valid(marker):
			return marker.global_position
	var beat_x := FORK_POS.x + float(ROUTE_BEAT_OFFSETS[beat_i])
	# Posts sit beyond the retained inner reach of the -1.5 traversal edge. On activation they move
	# farther outward to the settle pocket instead of crossing through the player's intended line.
	return Vector3(beat_x + 5.5 + local_i * 3.0, BELOW_Y + 0.5, -4.5 - local_i * 1.7)

func _below_step_aster_route_overlay(_parent: Node3D) -> void:
	if not is_instance_valid(_aster_route_overlay_root):
		return
	_aster_route_overlay_root.set_meta("overlay_semantic", "cause_effect")
	var model_label := _add_route_overlay_label(
		_aster_route_overlay_root,
		"AsterFlureModel",
		"FLURE SIGNAL: LINKED PACK PULLS FOR %ds / INNER REACH REMAINS" % int(ROUTE_FLURE_DURATION),
		Vector3(FORK_POS.x + 5.0, BELOW_Y + 2.0, -4.0),
		Color(0.48, 0.88, 1.0)
	)
	model_label.set_meta("overlay_semantic", "cause_effect")
	_apply_elevator_overlay_visibility()

## Peris supplies exact hazard footprints, not a solved route. Ordinary command
## previews remain the only lines that tell the player where their own plan goes.
func _below_step_peris_route_overlay_path(_parent: Node3D) -> void:
	if not is_instance_valid(_peris_route_overlay_root):
		return
	_peris_route_overlay_root.set_meta("overlay_semantic", "hazard_boundary")
	var fact_label := _add_route_overlay_label(
		_peris_route_overlay_root,
		"PerisIronModel",
		"IRON CONTACT: %d HP / SEC  /  SAFE ROUTING RECOGNIZES MARKED CELLS" % int(IRON_DAMAGE_PER_SEC),
		Vector3(FORK_POS.x + 5.0, BELOW_Y + 2.0, 4.0),
		Color(1.0, 0.76, 0.34)
	)
	fact_label.set_meta("overlay_semantic", "hazard_boundary")
	_peris_route_overlay_endpoint = null
	_apply_elevator_overlay_visibility()

## Peris's read makes the same visible rectangles available to the cautious planner. The preview and committed
## move now agree with her warm edge line; direct routing remains available later as an explicit risky choice.
func _learn_iron_route_risk() -> void:
	_set_iron_route_risk_learned(true)


func _set_iron_route_risk_learned(learned: bool) -> void:
	_clear_iron_route_risk_cells()
	_iron_route_risk_learned = learned
	if not learned:
		return
	for patch in _iron_patches:
		_register_iron_patch_risk(patch)


func _clear_iron_route_risk_cells() -> void:
	if _grid != null:
		for cell in _iron_route_risk_cells:
			_grid.clear_cell_risk(cell)
	_iron_route_risk_cells.clear()


func _register_iron_patch_risk(patch: Dictionary) -> void:
	if _grid == null or patch.is_empty():
		return
	var pos: Vector3 = patch.get("pos", Vector3.ZERO)
	var size: Vector3 = patch.get("size", Vector3.ZERO)
	var min_cell := _grid.world_to_grid(
		Vector3(pos.x - size.x * 0.5, 0.0, pos.z - size.z * 0.5))
	var max_cell := _grid.world_to_grid(
		Vector3(pos.x + size.x * 0.5, 0.0, pos.z + size.z * 0.5))
	for z in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for x in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			var cell := Vector2i(x, z)
			_grid.set_cell_risk(cell, IRON_ROUTE_RISK_PENALTY, true)
			if not _iron_route_risk_cells.has(cell):
				_iron_route_risk_cells.append(cell)

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
		var boundary_segment := _add_route_overlay_segment(
			_peris_route_overlay_root,
			"PerisIronBoundary%d_%d" % [beat_i, edge_i],
			corners[edge_i],
			corners[(edge_i + 1) % 4],
			0.16,
			outline_mat
		)
		boundary_segment.set_meta("overlay_semantic", "hazard_boundary")
	_add_route_overlay_label(
		_peris_route_overlay_root,
		"PerisIronLabel%d" % beat_i,
		"IRON FIELD %d  /  %d HP PER SEC" % [beat_i + 1, int(IRON_DAMAGE_PER_SEC)],
		center + Vector3(0.0, 1.45, 0.0),
		Color(1.0, 0.55, 0.25)
	).set_meta("overlay_semantic", "hazard_boundary")
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
		Vector3((from_x + to_x) * 0.5, BELOW_Y + 1.5, -ROUTE_OUTER_WALL_Z),
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

func _add_route_center_wall_segment(
		parent: Node3D, from_x: float, to_x: float, wall_color: Color) -> void:
	if to_x - from_x <= 0.05:
		return
	_add_wall(
		parent,
		Vector3((from_x + to_x) * 0.5, BELOW_Y + 1.5, 0.0),
		Vector3(to_x - from_x, 3.0, 0.4),
		wall_color
	)
	_block_level_walkable_region(
		LEVEL_LOWER,
		Vector2(from_x, -0.2),
		Vector2(to_x, 0.2)
	)

func _below_step_route_shell(parent: Node3D) -> void:
	var route_wall_len := ROUTE_LANE_LENGTH + 4.0
	var wall_color := Color(0.08, 0.08, 0.1)
	var route_end := FORK_POS.x + route_wall_len
	var wall_cursor := FORK_POS.x
	for crossover_offset in ROUTE_CROSSOVER_X_OFFSETS:
		var crossover_x := FORK_POS.x + float(crossover_offset)
		var opening_left := crossover_x - ROUTE_CROSSOVER_WIDTH * 0.5
		var opening_right := crossover_x + ROUTE_CROSSOVER_WIDTH * 0.5
		_add_route_center_wall_segment(parent, wall_cursor, opening_left, wall_color)
		wall_cursor = opening_right
		var crossover_plate := _add_route_field_plate(
			parent,
			Vector3(crossover_x, BELOW_Y + 0.018, 0.0),
			Vector3(ROUTE_CROSSOVER_WIDTH, 0.022, 1.5),
			Color(0.24, 0.42, 0.38, 0.72)
		)
		crossover_plate.name = "RouteCrossover%d" % int(crossover_offset)
		crossover_plate.set_meta("route_affordance", "crossover")
	_add_route_center_wall_segment(parent, wall_cursor, route_end, wall_color)
	_add_route_outer_wall_with_platform_openings(
		parent, FORK_POS.x, route_end, wall_color
	)
	_route_flure_enemy_groups.clear()

func _below_step_enemy_route_beat(parent: Node3D, beat_i: int, enemies_dormant: bool) -> void:
	var beat_x := FORK_POS.x + float(ROUTE_BEAT_OFFSETS[beat_i])
	var lure_pos := _route_flure_position(beat_i)
	var route_flure := _build_route_flure_station(parent, beat_i, lure_pos)
	_route_flure_enemy_groups[beat_i] = []
	for local_i in range(2):
		var enemy_pos := _route_enemy_position(beat_i, local_i)
		var enemy := _spawn_enemy("route_enemy_%d_%d" % [beat_i, local_i], enemy_pos, parent, false)
		enemy.detection_range = 6.0
		# These animals huddle around the Flure; they do not need an A* patrol to
		# communicate that relationship. Cheap deterministic roam keeps them alive
		# and readable without six hidden route searches running under the bridge.
		# Keep the marked interaction perch outside the full idle envelope. A wider
		# wander let the first guard randomly acquire a correctly staged party before
		# Peris could signal, turning identical reasoning into a patrol-phase coin flip.
		var roam_data := {"anchor": enemy_pos, "radius": 0.75}
		if enemies_dormant:
			# Wake the two-body beat as one readable cohort before either member
			# reaches detection distance; the farther partner sits ~17.5m from the
			# approach seam.
			_queue_below_enemy_setup(
				enemy, "roam", roam_data, 19.0, false, "route_beat_%d" % beat_i)
		else:
			_activate_below_enemy_setup({
				"enemy": enemy,
				"mode": "roam",
				"data": roam_data,
				"distracted": false,
			})
		(_route_flure_enemy_groups[beat_i] as Array).append(enemy)
	_build_route_flure_causal_links(beat_i, route_flure, _route_flure_enemy_groups[beat_i])
	_add_route_field_plate(parent, Vector3(beat_x, BELOW_Y + 0.015, -4.0),
		Vector3(13.0, 0.02, 6.5), Color(0.08, 0.30, 0.20, 0.62))

func _build_route_flure_causal_links(
		index: int, flure: Flure, enemies: Array) -> void:
	if not is_instance_valid(_aster_route_overlay_root) or not is_instance_valid(flure):
		return
	var links: Array[CausalFeedbackLink] = []
	for enemy_variant in enemies:
		var enemy := enemy_variant as Enemy
		if not is_instance_valid(enemy):
			continue
		var link := CausalFeedbackLink.new()
		_aster_route_overlay_root.add_child(link)
		link.configure(flure, enemy, Color(0.29, 0.62, 1.0), {
			"name": "AsterFlureLink%d_%s" % [index, enemy.char_id],
			"interaction_source": flure,
			"label": "PULLS PACK %d / %ds" % [index + 1, int(ROUTE_FLURE_DURATION)],
			"owner_character": "aster",
			"feedback_mode": CausalFeedbackLink.MODE_PREDICTED,
			"visibility_policy": CausalFeedbackLink.VISIBILITY_CONTEXTUAL,
			"flow_speed": 0.7,
		})
		link.set_planning_active(true)
		link.set_meta("overlay_semantic", "cause_effect")
		links.append(link)
	_route_causal_links[index] = links

func _below_step_hazard_shell(parent: Node3D) -> void:
	var route_wall_len := ROUTE_LANE_LENGTH + 4.0
	var route_wall_center := FORK_POS.x + route_wall_len * 0.5
	_add_wall(parent, Vector3(route_wall_center, BELOW_Y + 1.5, ROUTE_OUTER_WALL_Z),
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
	_below_step_wreckage_gate_layout(parent)
	_below_step_wreckage_gate_interaction(parent)
	_below_step_wreckage_listener(parent, "ListenerSpawnA", 0, enemies_dormant)
	_below_step_wreckage_listener(parent, "ListenerSpawnB", 1, enemies_dormant)


func _below_step_wreckage_gate_layout(parent: Node3D) -> void:
	if is_instance_valid(_wreckage_gate):
		return
	_wreckage_gate = WRECKAGE_GATE_SCENE.instantiate()
	_wreckage_gate.position = WRECKAGE_GATE_POS
	parent.add_child(_wreckage_gate)
	_wreckage_gate.setup(_game_state, _grid, LEVEL_LOWER, ["aster", "peris"])
	var gate := _wreckage_gate as PartyGate3D
	if gate != null and not gate.opened.is_connected(_finish_wreckage_clear):
		gate.opened.connect(_finish_wreckage_clear)
	if gate != null and not gate.blocked.is_connected(_on_wreckage_gate_blocked):
		gate.blocked.connect(_on_wreckage_gate_blocked)


func _below_step_wreckage_gate_interaction(parent: Node3D) -> void:
	if is_instance_valid(_wreckage_interactable) or not is_instance_valid(_wreckage_gate):
		return
	var anchor := _wreckage_interaction_anchor()
	_wreckage_interactable = _create_interactable(
		parent,
		anchor,
		"WreckageClear",
		2.0,
		2.2,
		"Clear together",
		true,
		Interactable.InteractableType.TIMED_ACTION
	)
	_wreckage_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_wreckage_interactable.set("description", "Unstable wreckage -- two braces required")
	_wreckage_interactable.set("consequence_preview",
		"Pair clears passage; solo shifts rubble and alerts fauna")
	_wreckage_interactable.set_interaction_enabled(false)
	_configure_elevator_source(
		_wreckage_interactable, ELEVATOR_SOURCE_WRECKAGE)
	var guidance_layout: Node = _wreckage_gate.get_node_or_null("GuidanceLayout")
	if guidance_layout != null and guidance_layout.has_method("register_label") \
			and _wreckage_interactable.has_method("get_tutorial_label_node"):
		var action_label := _wreckage_interactable.call("get_tutorial_label_node") as Label3D
		guidance_layout.call("register_label", action_label)
	# The full blocker spans the entire hallway. Outlining that ten-metre slab at
	# close camera range turns its silhouette into screen-edge white bands, which
	# reads like a render artifact instead of interaction feedback. The two loose
	# stones are the local, causal part the player is about to disturb, so keep the
	# same click delegate and highlight only that authored focus cluster.
	var rubble_focus: Node = _wreckage_gate.get_node_or_null("LooseBits")
	var outline_target := _outline_object_meshes(
		parent,
		"WreckageGateOutline",
		_collect_mesh_instances(rubble_focus) if rubble_focus != null else [],
		"elevator_wreckage_gate",
		2.4,
		0.16
	)
	_set_room_target_interaction_delegate(outline_target, _wreckage_interactable)


func _below_step_wreckage_listener(
		parent: Node3D,
		marker_name: String,
		listener_index: int,
		enemies_dormant := false
	) -> void:
	if not is_instance_valid(_wreckage_gate):
		return
	var listener_id := "wreckage_listener_%d" % listener_index
	for existing in _wreckage_listeners:
		if is_instance_valid(existing) and existing.char_id == listener_id:
			return
	var marker := _wreckage_gate.get_node_or_null("Markers/" + marker_name) as Marker3D
	if marker == null:
		return
	var listener := _spawn_enemy(listener_id, marker.global_position, parent, false)
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

	# The route read is overlay-first: there are no character-locked perspective
	# pedestals at the fork.

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
	_add_wall(parent, Vector3(route_wall_center, ground_y + wall_h / 2.0, -ROUTE_OUTER_WALL_Z), Vector3(route_wall_len, wall_h, 0.3), wall_color)
	# Enemy-lane huddle: the fauna cluster around flures that BLOCK the corridor. Distracted by the
	# flures (shrunk detection), they ignore a party keeping its distance — but cutting straight through
	# the huddle to get down the lane brings Aster/Peris inside their reach and they give chase.
	_route_flure_enemy_groups.clear()
	for beat_i in range(ROUTE_BEAT_COUNT):
		var beat_x := fork_x + float(ROUTE_BEAT_OFFSETS[beat_i])
		var lure_pos := Vector3(beat_x - 5.0, ground_y + 0.3, -1.6)
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
	_add_wall(parent, Vector3(route_wall_center, ground_y + wall_h / 2.0, ROUTE_OUTER_WALL_Z), Vector3(route_wall_len, wall_h, 0.3), wall_color)
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
		_add_route_field_plate(parent, Vector3(ix, ground_y + 0.04, ROUTE_SAFE_EDGE_Z), Vector3(12.5, 0.025, 1.35), Color(0.18, 0.46, 0.24, 0.82))

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

func _junction_survey_specs() -> Array[Dictionary]:
	return [
		{"label": "Workbench", "dialogue": "junction.workbench", "role": "aster"},
		{"label": "Monitor", "dialogue": "junction.monitor", "role": ""},
		{"label": "Food", "dialogue": "junction.food", "role": "peris"},
		{"label": "Lookout", "dialogue": "junction.lookout", "role": ""},
		{"label": "Heater", "dialogue": "junction.heater", "role": ""},
		{"label": "Markings", "dialogue": "junction.markings", "role": ""},
		{"label": "Game", "dialogue": "junction.game", "role": ""},
	]

func _junction_step_prepare(parent: Node3D) -> void:
	_junction_interactables.clear()
	_junction_plant_interactable = null
	_junction_plant_mesh = null
	_junction_plant_material = null
	_junction_shelter_layout = null
	_drink_mesh = null
	_drink_home_parent = null
	parent.set_meta("camera_occlusion_outline_safe_clip", true)

func _junction_step_shelter_layout(parent: Node3D) -> void:
	# Spatial content is an authored scene. The elevator owns the story gates;
	# the scene owns the model, visibility choices, collision, and editable anchors.
	var instance_started := PerformanceTrace.begin()
	_junction_shelter_layout = _take_prewarmed_scene(
		&"elevator_junction_shelter", JUNCTION_SHELTER_SCENE) as AuthoredSpatialLayout3D
	PerformanceTrace.end(&"draw", &"elevator.junction.shelter_instance", instance_started,
		"prewarmed", 1 if _junction_shelter_layout != null else 0)
	_junction_shelter_layout.name = "JunctionShelterLayout"
	_junction_shelter_layout.position = JUNCTION_POS
	var tree_started := PerformanceTrace.begin()
	parent.add_child(_junction_shelter_layout)
	PerformanceTrace.end(&"draw", &"elevator.junction.shelter_tree_entry", tree_started,
		"junction", 1)
	_drink_mesh = _junction_shelter_layout.find_child("Drink", true, false) as MeshInstance3D
	if is_instance_valid(_drink_mesh):
		_drink_home_parent = _drink_mesh.get_parent()
		_drink_home_rotation = _drink_mesh.rotation
		_drink_home_scale = _drink_mesh.scale

func _junction_step_survey_batch(parent: Node3D, first: int, count: int) -> void:
	var survey_specs := _junction_survey_specs()
	for i in range(first, mini(first + count, survey_specs.size())):
		var spec: Dictionary = survey_specs[i]
		var label := str(spec["label"])
		_add_junction_interactable(
			parent,
			label,
			_junction_anchor_position(label, JUNCTION_POS),
			str(spec["dialogue"]),
			str(spec["role"])
		)

func _junction_step_plant(parent: Node3D) -> void:
	# Peris tends this plant to trigger dusk and Endo.
	_junction_plant_mesh = _junction_shelter_layout.find_child(
		"DormantPlantVisual", true, false) as MeshInstance3D
	if _junction_plant_mesh != null \
			and _junction_plant_mesh.get_active_material(0) is StandardMaterial3D:
		_junction_plant_material = (
			_junction_plant_mesh.get_active_material(0) as StandardMaterial3D).duplicate()
		_junction_plant_mesh.material_override = _junction_plant_material

	var plant_interact := preload("res://scenes/game/interactable.tscn").instantiate()
	plant_interact.name = "DormantPlant"
	plant_interact.description = "Tend Dormant Plant"
	plant_interact.dialogue_key = "junction.peris.tend_plant"
	plant_interact.tutorial_label = "TEND / SIGNAL ENDO"
	plant_interact.consequence_preview = "Peris wakes the plant, bringing dusk and signaling Endo."
	plant_interact.dialogue_box = _dialogue
	plant_interact.active_character = _active_character
	plant_interact.required_character = "peris"
	# Tending is deliberate click-to-work. A proximity HOLD depended on a
	# physics body-enter event after click-arrival, which could leave the player
	# standing on the plant with no progress ring and no way forward.
	plant_interact.interactable_type = Interactable.InteractableType.TIMED_ACTION
	plant_interact.one_shot = true
	plant_interact.dwell_time = 2.0
	plant_interact.position = _junction_anchor_position("Plant", JUNCTION_POS)
	parent.add_child(plant_interact)
	if plant_interact.has_method("set_scheduler"):
		plant_interact.set_scheduler(_scheduler)
		plant_interact.set_movement_authority(_game_state)
	plant_interact.set_pre_trigger_validator(_validate_junction_plant_trigger)
	_junction_plant_interactable = plant_interact
	plant_interact.set_interaction_enabled(false)
	plant_interact.interaction_requested.connect(_on_junction_plant_requested)
	plant_interact.interacted.connect(_on_junction_plant_interacted)


## This query runs before Interactable records a trigger or consumes its one-shot. The callback below
## repeats it only as a fail-closed direct-call guard; normal play cannot create a saved "plant used"
## fact while either required body is absent, downed, outside the authored shelter, or unable to pay.
func _validate_junction_plant_trigger(
		interactable: Interactable, active_character: String
	) -> bool:
	return interactable == _junction_plant_interactable \
		and active_character == "peris" \
		and _current_step == "junction_arrive" \
		and _junction_existing_party_ready_for_endo()


func _junction_plant_has_semantic_receipt() -> bool:
	return is_instance_valid(_junction_plant_interactable) \
		and bool(_junction_plant_interactable.get("_used")) \
		and not bool(_junction_plant_interactable.get("interaction_enabled"))


func _on_junction_plant_requested(
		_interactable: Node, _world_position: Vector3
	) -> void:
	if _current_step == "junction_arrive" and not _junction_existing_party_ready_for_endo() \
			and _hud != null:
		_hud.show_message(
			"Bring conscious Aster and Peris inside the shelter with one ATP each before signaling Endo.",
			2.8)


func _on_junction_plant_interacted() -> void:
	if not _validate_junction_plant_trigger(
			_junction_plant_interactable as Interactable,
			str(_junction_plant_interactable.get("active_character"))) \
			or not _junction_plant_has_semantic_receipt():
		return
	if _junction_plant_mesh != null and _junction_plant_material != null:
		_junction_plant_material.emission_enabled = true
		_junction_plant_material.emission = Color(0.1, 0.3, 0.15)
		var bloom := create_tween()
		bloom.tween_property(
			_junction_plant_material, "albedo_color", Color(0.2, 0.5, 0.3), 1.5)
		bloom.parallel().tween_property(
			_junction_plant_material, "emission_energy_multiplier", 0.8, 2.0)
		bloom.parallel().tween_property(
			_junction_plant_mesh, "scale", Vector3(1.5, 1.8, 1.5), 2.0)
	_start_dusk_from_plant()

func _activate_junction_interactions() -> void:
	for interact in _junction_interactables.values():
		if is_instance_valid(interact):
			interact.set_interaction_enabled(true)
	if is_instance_valid(_junction_plant_interactable):
		_junction_plant_interactable.set_interaction_enabled(true)
		_junction_plant_interactable.call_deferred("show_tutorial_label")

func _build_junction_chunk(parent: Node3D) -> void:
	_junction_step_prepare(parent)
	_junction_step_shelter_layout(parent)
	_junction_step_survey_batch(parent, 0, _junction_survey_specs().size())
	_junction_step_plant(parent)


func _junction_anchor_position(anchor_name: StringName, fallback: Vector3) -> Vector3:
	if is_instance_valid(_junction_shelter_layout):
		var marker := _junction_shelter_layout.anchor(anchor_name)
		if marker != null:
			return marker.global_position
	return fallback

func _start_dusk_from_plant() -> void:
	# The accepted plant interaction is the physical party gate. Freeze the accepted formation now,
	# before the two-second dusk presentation, so neither body can leave after the retryable gate closes.
	for character_id in ["aster", "peris"]:
		if _game_state.characters.has(character_id):
			_game_state.command_stop(character_id)
	if is_instance_valid(_player):
		_player.set_move_enabled(false)
	if _junction_beat != null:
		_junction_beat.complete({"action": "tend_plant", "actor": "peris"})
	# The shelter beat is over, so the later gauntlet may safely occupy its overlapping
	# footprint. Its geometry and dormant enemy visuals stream throughout the
	# Endo/night sequence; no AI enters GameState before _start_gauntlet().
	stream_chunk("gauntlet")
	var env_node: Node = find_child("Environment", false, false)
	if env_node:
		for child in env_node.get_children():
			if child is WorldEnvironment:
				var t := create_tween()
				t.tween_property(child.environment, "ambient_light_energy", 0.15, 3.0)
				break
	# This dusk hold is a causal story phase, not a cosmetic delay: the player cannot move and Endo
	# does not exist yet. Keep its absolute deadline and successor in the portable continuation record
	# so a save here resumes the same remaining dusk instead of discarding the only route forward.
	_schedule_portable_method(2.0, _start_endo_enters, "endo_enters")

func _add_junction_interactable(
		parent: Node3D,
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
	# character stands nearby: a proximity dwell on a repeatable prop re-arms itself and floods
	# the dialogue queue.
	interact.interactable_type = Interactable.InteractableType.INSPECTION
	interact.one_shot = false
	interact.dwell_time = 1.0
	interact.position = pos
	parent.add_child(interact)
	if interact.has_method("set_scheduler"):
		interact.set_scheduler(_scheduler)
		interact.set_movement_authority(_game_state)
	# Streamed presentation must be inert until the Junction story boundary.
	# A hidden Node3D does not disable an Area3D's physics/input by itself.
	interact.set_interaction_enabled(false)
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
	_gauntlet_step_prepare(parent)
	_gauntlet_step_floor(parent)
	_gauntlet_step_walls(parent)
	_gauntlet_step_flure_1(parent)
	_gauntlet_step_flure_2(parent)
	_gauntlet_step_refuge(parent)
	_gauntlet_step_enemy_batch(parent, 0, _gauntlet_enemy_specs().size())
	_gauntlet_step_light(parent)

func _gauntlet_step_prepare(_parent: Node3D) -> void:
	_gauntlet_intro_authority.clear()
	_gauntlet_run_authority.clear()
	_gauntlet_flure_meshes.clear()
	_gauntlet_flure_interactables.clear()
	_gauntlet_enemies.clear()
	_gauntlet_enemy_groups = {0: [], 1: []}
	_gauntlet_enemy_posts.clear()
	_gauntlet_dormant_enemy_setups.clear()
	_gauntlet_stage_markers.clear()
	_gauntlet_context_markers.clear()
	_gauntlet_wasted_flure_windows = 0
	_flure_mesh = null
	_flure_interactable = null

func _gauntlet_step_floor(parent: Node3D) -> void:
	var ground_y := BELOW_Y
	var gx := GAUNTLET_POS.x

	# Ground floor — extends EAST past the exit gate so the player can actually run OUT of the gauntlet.
	# A chamber whose floor and east wall end at x = GAUNTLET_EXIT.x - 2 (exactly the exit gate) walls
	# the player off from ever crossing it. Spans from the west entrance to the grid's east edge.
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


func _gauntlet_step_walls(parent: Node3D) -> void:
	var ground_y := BELOW_Y
	var gx := GAUNTLET_POS.x
	var wc := Color(0.09, 0.09, 0.11)
	var g_west := gx - 10.0
	var g_east := GAUNTLET_EXIT.x + 2.0
	var g_len := g_east - g_west
	var g_cx := (g_west + g_east) * 0.5
	# Chamber walls: z-sides run the full length; the east wall sits at the far edge, PAST the exit gate
	# (GAUNTLET_EXIT.x - 2), so reaching the gate never means running into a wall.
	_add_wall(parent, Vector3(g_cx, ground_y + 1.5, -7.0), Vector3(g_len, 3, 0.3), wc)
	_add_wall(parent, Vector3(g_cx, ground_y + 1.5, 7.0), Vector3(g_len, 3, 0.3), wc)
	_add_wall(parent, Vector3(g_east, ground_y + 1.5, 0), Vector3(0.3, 3, 14), wc)


func _gauntlet_step_flure_1(parent: Node3D) -> void:
	var flure_1 := _build_gauntlet_flure_station(parent, 0, FLURE_POS)
	flure_1.set_interaction_enabled(false)
	_flure_interactable = flure_1
	_flure_mesh = flure_1._glow


func _gauntlet_step_flure_2(parent: Node3D) -> void:
	var flure_2 := _build_gauntlet_flure_station(parent, 1, GAUNTLET_FLURE_2_POS)
	flure_2.set_interaction_enabled(false)


func _build_gauntlet_flure_station(parent: Node3D, stage: int, pos: Vector3) -> Flure:
	var target_ids: Array = []
	var first_enemy := 0 if stage == 0 else 3
	var end_enemy := 3 if stage == 0 else 5
	for enemy_index in range(first_enemy, end_enemy):
		target_ids.append("gauntlet_%d" % enemy_index)
	var flure := Flure.new()
	flure.name = "GauntletFlure%d" % (stage + 1)
	flure.configure(_game_state, pos, target_ids, 24.0, 1.8, Color(0.95, 0.58, 0.18))
	flure.one_shot = false
	flure.lure_duration = FLURE_DURATION
	flure.settle_pos = Vector3(pos.x, BELOW_Y + 0.5, 6.5 if stage == 0 else -6.5)
	flure.description = "Prime relay Flure %d" % (stage + 1)
	flure.tutorial_label = "PRIME PACK %d / %ds" % [stage + 1, int(flure.lure_duration)]
	flure.consequence_preview = "Pulls Pack %d for %ds; get all three characters to the %s before it returns." % [
		stage + 1,
		int(flure.lure_duration),
		"midpoint refuge" if stage == 0 else "exit",
	]
	flure.set_enemy_resolver(_resolve_gauntlet_enemy)
	parent.add_child(flure)
	register_preview_interactable(flure)
	_require_interactable_character(flure, "peris")
	flure.flure_activated.connect(_on_gauntlet_flure_activated.bind(stage))
	_gauntlet_flure_interactables.append(flure)
	if is_instance_valid(flure._glow):
		flure._glow.name = "GauntletFlureVisual%d" % (stage + 1)
		_gauntlet_flure_meshes.append(flure._glow)
	return flure


func _resolve_gauntlet_enemy(enemy_id: String) -> Enemy:
	for enemy in _gauntlet_enemies:
		if is_instance_valid(enemy) and enemy.char_id == enemy_id:
			return enemy
	return null


func _gauntlet_step_refuge(parent: Node3D) -> void:
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


func _gauntlet_enemy_specs() -> Array[Dictionary]:
	var gx := GAUNTLET_POS.x
	var ground_y := BELOW_Y
	return [
		# Each refuge/station is outside normal sight range, while every linked guard remains inside
		# the Flure's 24m signal radius. Advancing before signalling can still commit the pack; merely
		# arriving at the decision point does not make the correct action impossible.
		{"stage": 0, "pos": Vector3(gx + 2.0, ground_y + 0.5, 0.0)},
		{"stage": 0, "pos": Vector3(gx + 9.0, ground_y + 0.5, -2.4)},
		{"stage": 0, "pos": Vector3(gx + 16.0, ground_y + 0.5, 2.4)},
		{"stage": 1, "pos": GAUNTLET_MIDPOINT + Vector3(12.0, 0.5, 0.0)},
		{"stage": 1, "pos": GAUNTLET_MIDPOINT + Vector3(22.0, 0.5, 2.2)},
	]


func _gauntlet_step_enemy_batch(parent: Node3D, first: int, count: int) -> void:
	# Five deterministic enemies form two independent packs: three in stage one,
	# two beyond the refuge. This preserves the established encounter budget while
	# making the relay/reset structure spatially honest. Hidden prewarm creates
	# only disabled views; registration, patrol schedules, and detection wait for
	# the actual gauntlet story boundary.
	var enemy_specs := _gauntlet_enemy_specs()
	for i in range(first, mini(first + count, enemy_specs.size())):
		var spec: Dictionary = enemy_specs[i]
		var stage := int(spec["stage"])
		var enemy_pos: Vector3 = spec["pos"]
		var eid := "gauntlet_%d" % i
		var enemy := _spawn_enemy(eid, enemy_pos, parent, false)
		enemy.detection_range = 5.0
		var pa := enemy_pos + Vector3(-1.0, 0, -1.5)
		var pb := enemy_pos + Vector3(1.0, 0, 1.5)
		_gauntlet_enemies.append(enemy)
		_gauntlet_enemy_posts[eid] = enemy_pos
		(_gauntlet_enemy_groups[stage] as Array).append(enemy)
		_gauntlet_dormant_enemy_setups.append({
			"enemy": enemy,
			"waypoints": [pa, pb],
		})


func _gauntlet_step_light(parent: Node3D) -> void:
	var ground_y := BELOW_Y
	var gx := GAUNTLET_POS.x
	var gauntlet_light := OmniLight3D.new()
	gauntlet_light.position = Vector3(gx, ground_y + 2.5, 0)
	gauntlet_light.light_color = Color(0.2, 0.12, 0.08)
	gauntlet_light.light_energy = 1.5
	gauntlet_light.omni_range = 12.0
	parent.add_child(gauntlet_light)


func _activate_gauntlet_enemies() -> void:
	if _gauntlet_dormant_enemy_setups.is_empty():
		return
	_game_state.begin_detection_update_batch()
	for setup in _gauntlet_dormant_enemy_setups:
		var enemy: Enemy = setup.get("enemy")
		if not is_instance_valid(enemy):
			continue
		var enemy_started := PerformanceTrace.begin()
		enemy.set_detection_targets([])
		enemy.process_mode = Node.PROCESS_MODE_INHERIT
		_register_gs_character(enemy.char_id, enemy, enemy.move_speed, {
			"detection_range": enemy.detection_range,
			"detection_targets": [],
		})
		enemy.activate()
		var waypoints: Array[Vector3] = []
		waypoints.assign(setup.get("waypoints", []))
		enemy.configure_patrol(waypoints)
		PerformanceTrace.end(&"update", &"elevator.gauntlet.activate_enemy", enemy_started,
			enemy.char_id, waypoints.size())
	_game_state.end_detection_update_batch()
	_gauntlet_dormant_enemy_setups.clear()

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
	# Prefer the 8x8 variation atlas (one metre = one hand-varied cell); the single
	# tile stays the fallback for stems without one.
	var scale := world_scale
	var atlas_path := "res://resources/textures/atlases/%s_var8.png" % tile_name
	var tex = load(atlas_path) if ResourceLoader.exists(atlas_path) else null
	if tex != null:
		scale = world_scale / 8.0
	else:
		tex = load("res://resources/models/elevator/tiles/%s.png" % tile_name)
	if tex != null:
		m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)  # 1 tile-cell / (1/world_scale) m
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
