@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

const FloraMemorySystem = preload("res://scripts/system/simulation/flora_memory_system.gd")
const StacksBankEvidence = preload("res://scripts/game/mechanics/stacks_bank_evidence.gd")
const EnemyScript = preload("res://scripts/game/ai/enemy.gd")
const FlureScript = preload("res://scripts/game/objects/flure.gd")
const ChannelScript = preload("res://scripts/game/objects/channel.gd")
const ENDO_JUNCTION_STRETCH_CHUNK_SCENE := preload("res://scenes/fragments/chunks/endo_junction_stretch_chunk.tscn")
const LOCKOUT_CHASE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/lockout_chase_chunk.tscn")
const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")
const OPENING_FADE_DURATION := 2.5
const ACT1_CAMPAIGN_AUTHORITY_VERSION := 1
const ACT1_CAMPAIGN_AUTHORITY_KEY := "runtime:act1_sequence:campaign_handoffs"
const ACT1_SNAPSHOT_CHUNKS: Array[String] = [
	"channels", "stacks", "rings", "lockout", "lockout_chase_campaign",
	"endo_junction_stretch",
]

## Act 1 chunk sequence: Channels, Stacks, Rings, Lockout.
## The Endo's-Junction-to-Shelter-1 SCENE chunk (a self-contained SceneChunk, unlike the four
## procedural chunks above) is reachable as its own leg via start_chunk == "endo_junction_stretch".

var _aster_node: CharacterBody3D
var _peris_node: CharacterBody3D
var _endo: CharacterBody3D
var _active_character := "aster"
var _channels_flure: Flure
var _channels_flure_channel: Channel
var _channels_flow_strips: Array[MeshInstance3D] = []
var _channels_flush_enemy_ids: Array[String] = []
var _channels_run_lure: Flure
var _channels_hide_spot: Node3D
var _channels_swarm_enemy_ids: Array[String] = []
var _channels_window_lanes: Dictionary = {}
var _channels_active_window_lane := ""
var _channels_shortcut_gate: PartyGate3D
var _channels_shortcut_gate_mesh: MeshInstance3D
var _channels_shortcut_light: OmniLight3D
var _channels_run_lure_active := false
var _channels_run_lure_expire_tick := -1.0
var _channels_party_hidden := false
var _channels_encounter_resetting := false
var _channels_flow_power := 0.0
var _channels_coda_phase := "idle"
var _channels_coda_swept_ids: Array[String] = []
var _channels_shortcut_unlocked := false
var _channels_party_recuperated := false
var _channels_shelter_reached := false
var _channels_shelter_interactable
var _channels_shelter_rest_phase := "locked"
var _channels_shelter_rest_members: Array[String] = []
var _channels_shelter_rest_commit_tick := -1.0
var _channels_shelter_rest_commit_day := 0
var _channels_shelter_rest_before_atp: Dictionary = {}
var _channels_optional_sites: Dictionary = {}
var _channels_optional_visuals: Dictionary = {}
var _channels_optional_findings: Dictionary = {}
var _channels_encounter_phase := "idle"
var _channels_encounter_phase_start_tick := -1.0
var _channels_encounter_lure_start_tick := -1.0
var _channels_encounter_retry_deadline := -1.0
var _channels_exposure_by_character: Dictionary = {}
var _channels_encounter_spotted_ids: Array[String] = []
var _channels_formation_authority: Dictionary = {}
var _channels_authority_poll_active := false
var _channels_authority_poll_origin_tick := -1.0
var _channels_authority_next_poll_tick := -1.0
var _restoring_channels_authority := false
var _channels_arrival_signal_game_state
var _channels_enemy_specs: Dictionary = {}
var _channels_enemy_by_id: Dictionary = {}
var _channels_enemy_scope_by_id: Dictionary = {}
var _channels_channel_entries: Array[Dictionary] = []
var _channels_kit_active := false
var _channels_flures_bound := false

const STACKS_SUPPORT_LOG_KEY := "stacks_support_team_log"
var _stacks_signal_interactable
var _stacks_terminal_interactable
var _stacks_workspace_interactable
var _stacks_support_log_entry_id := -1
var _stacks_support_log_presented := false
var _stacks_signal_interacted := false
var _stacks_terminal_interacted := false
var _stacks_archive_interacted := false
var _stacks_audit_flags_found := false
var _stacks_bank_interactables: Dictionary = {}
var _stacks_bank_readouts: Dictionary = {}
var _stacks_bank_samples: Dictionary = {}
var _stacks_bank_resolved := false
var _stacks_bank_attempts := 0
var _stacks_last_commit := ""
var _stacks_failed_commits: Array[String] = []
var _stacks_shelter_interactable
var _stacks_anxiety_seen := false
var _stacks_rest_phase := "locked"
var _stacks_rest_members: Array[String] = []
var _stacks_rest_commit_tick := -1.0
var _stacks_rest_commit_day := 0
var _stacks_rest_before_atp: Dictionary = {}
var _restoring_stacks_rest_authority := false

# Rings' required story spine is Marco naming the reassignment pattern and Endo leaving at the
# junction. The flora/memory traces remain optional ambient reads and never own progression order.
var _rings_client_interactable
var _rings_trace_interactables: Dictionary = {}
var _rings_trace_seen: Dictionary = {}
var _rings_client_seen := false
const RINGS_AMBIENT_TRACE_IDS := ["client_bloom", "forget_me_not", "doorvine"]
const RINGS_ENDO_AUTHORITY_VERSION := 2
const RINGS_ENDO_AUTHORITY_KEY := "runtime:act1:rings_endo_departure"
const RINGS_ENDO_TRAVERSAL_ID := &"act1_rings_endo_departure"
const RINGS_ENDO_PHASE_PRESENT := "present"
const RINGS_ENDO_PHASE_DEPARTING := "departing"
const RINGS_ENDO_PHASE_DEPARTED := "departed"
const RINGS_ENDO_VALID_PHASES := [
	RINGS_ENDO_PHASE_PRESENT,
	RINGS_ENDO_PHASE_DEPARTING,
	RINGS_ENDO_PHASE_DEPARTED,
]
const RINGS_ENDO_JUNCTION_POS := Vector3(568.0, 0.5, -33.0)
const RINGS_ENDO_DEPARTURE_SPEED := 3.0
const RINGS_ENDO_MIN_DEPARTURE_DURATION := 4.0
const RINGS_ENDO_ENDPOINT_EPSILON := 0.08
const RINGS_REASSIGNMENT_ACTOR := "peris"
const RINGS_REASSIGNMENT_REQUIRED_PARTY := ["peris", "endo"]
const RINGS_REASSIGNMENT_GATHER_RADIUS := 3.4
var _rings_endo_phase := RINGS_ENDO_PHASE_PRESENT
var _rings_endo_departure_start_tick := -1.0
var _rings_endo_departure_deadline := -1.0
var _rings_reassignment_actor := ""
var _rings_reassignment_commit_tick := -1.0
var _rings_reassignment_positions: Dictionary = {}
var _restoring_rings_endo_authority := false
var _rings_departure_signal_game_state

@export var start_chunk := ""

# Iron hazard zones
var _iron_patches: Array[Dictionary] = []
const IRON_DAMAGE_PER_SEC := 8.0
const IRON_DAMAGE_INTERVAL := 0.5
const IRON_HAZARD_AUTHORITY_VERSION := 1
const IRON_HAZARD_AUTHORITY_KEY := "runtime:act1_sequence:iron_hazard"
const IRON_HAZARD_TAG := "act1_iron_hazard"
const CHANNELS_IRON_Z_OFFSETS := [-2.0, 1.5, -1.0, 2.0]
var _iron_hazard_active := false
var _iron_hazard_next_tick := -1.0
var _restoring_iron_hazard := false

# HP
var _aster_hp := 100.0
var _peris_hp := 100.0

# Naturalizers (lockout chase)
var _naturalizers: Array[Node3D] = []

# Overlay + flora state
var _overlay_ui: CanvasLayer
var _overlay_buttons: Dictionary = {}
var _overlay_note_label: Label
var _overlay_status_label: Label
var _overlay_note_timer := 0.0
var _overlay_states := {
	"aster": true,
	"peris": true,
}
var _flora_overlay_root: Node3D
var _flora_marker_nodes: Dictionary = {}
var _flora_nodes: Dictionary = {}
var _flora_system := FloraMemorySystem.new()

const FLORA_SMELL_RADIUS := 2.25

# Linear progression along +X.
const CHANNELS_START := Vector3(0, 0, 0)
const CHANNELS_END := Vector3(228, 0, 0)
const CHANNELS_MEMORY_TRIGGER_X := 54.0
const CHANNELS_BODY_POS := Vector3(74.0, 0.5, -3.0)
const CHANNELS_WINDOW_ONE_STAGE_POS := Vector3(104.0, 0.5, -2.0)
const CHANNELS_WINDOW_ONE_LURE_POS := Vector3(110.0, 0.5, -13.0)
const CHANNELS_WINDOW_ONE_CURTAIN_POS := Vector3(122.0, 0.6, -1.0)
const CHANNELS_WINDOW_ONE_GOAL_POS := Vector3(132.0, 0.5, 0.0)
const CHANNELS_WINDOW_ONE_DURATION := 13.5
const CHANNELS_FLURE_TRIGGER_X := 146.0
const CHANNELS_FLURE_POS := Vector3(156.0, 0.5, 9.0)
const CHANNELS_FLUSH_SWARM_POS := Vector3(162.0, 0.6, 8.8)
const CHANNELS_FLUSH_SWARM_OFFSETS := [-1.6, -0.8, 0.0, 0.8, 1.6]
const CHANNELS_WINDOW_TWO_STAGE_POS := Vector3(166.0, 0.5, 2.0)
const CHANNELS_WINDOW_TWO_LURE_POS := Vector3(170.0, 0.5, 13.0)
const CHANNELS_WINDOW_TWO_CURTAIN_POS := Vector3(179.0, 0.6, 1.0)
const CHANNELS_WINDOW_TWO_GOAL_POS := Vector3(184.0, 0.5, 0.0)
const CHANNELS_WINDOW_TWO_DURATION := 9.5
const CHANNELS_ENCOUNTER_TRIGGER_X := 192.0
const CHANNELS_ENCOUNTER_ENTRY_POS := Vector3(194.0, 0.5, 3.0)
const CHANNELS_RUN_LURE_POS := Vector3(198.0, 0.5, 1.5)
const CHANNELS_HIDE_SPOT_POS := Vector3(204.0, 0.5, -10.0)
const CHANNELS_SWARM_CLUSTER_X := 211.0
const CHANNELS_RUN_LURE_DURATION := 20.0
const CHANNELS_SWARM_OFFSETS := [-2.4, -1.6, -0.8, 0.0, 0.8, 1.6, 2.4]
const CHANNELS_WINDOW_DETECT_RADIUS := 3.0
const CHANNELS_WINDOW_PERIODIC_CHANNELS := 3
const CHANNELS_WINDOW_FLOW_PERIOD := 6.0
const CHANNELS_WINDOW_FLOOD_DURATION := 4.0
const CHANNELS_WINDOW_SWARM_SPEED := 3.6
const CHANNELS_WINDOW_CHANNEL_T_VALUES := [0.30, 0.48, 0.66]
const CHANNELS_WINDOW_SWARM_OFFSETS := [-1.4, -0.7, 0.0, 0.7, 1.4]
const CHANNELS_SHORTCUT_BRANCH_POS := Vector3(186.0, 0.5, 6.0)
const CHANNELS_SHORTCUT_GATE_POS := Vector3(186.0, 0.5, 10.4)
const CHANNELS_SHELTER_POS := Vector3(216.0, 0.5, 12.0)
const CHANNELS_SHORTCUT_GATE_AUTHORITY_ID := "act1_channels_shelter_return_gate"
const CHANNELS_SHORTCUT_GATE_OPEN_DURATION := 1.4
const CHANNELS_SHORTCUT_GATE_LIFT_HEIGHT := 3.2
const CHANNELS_REST_ATP_COST := 1.0
const CHANNELS_MAX_HP := 100.0
const CHANNELS_PARTY_IDS := ["aster", "peris", "endo"]
const LOCKOUT_PARTY_IDS := ["aster", "peris"]
const LOCKOUT_DEPARTED_CHARACTER_ID := "endo"
const CHANNELS_RUNTIME_AUTHORITY_VERSION := 3
const CHANNELS_RUNTIME_AUTHORITY_CONTRACT := "act1_channels/v3"
const CHANNELS_RUNTIME_AUTHORITY_KEY := "runtime:act1:channels"
const ACT1_REST_PHASES := ["locked", "ready", "committing", "rested"]
const CHANNELS_SHELTER_REST_TAG := "act1_channels_shelter_party_rest"
const CHANNELS_WINDOW_AUTHORITY_PHASES := [
	"idle", "activate", "cross", "failed", "reset", "safe",
]
const CHANNELS_ENCOUNTER_AUTHORITY_PHASES := [
	"idle", "activate", "hide", "run", "failed", "reset", "complete",
]
const CHANNELS_FORMATION_AUTHORITY_PHASES := [
	"idle", "moving", "interrupted", "completed",
]
const CHANNELS_WINDOW_GOAL_RADIUS := 2.6
const CHANNELS_HIDE_RADIUS := 2.3
const CHANNELS_SHELTER_RADIUS := 3.0
const CHANNELS_FORMATION_ENDPOINT_EPSILON := 0.35
const CHANNELS_FORMATION_POLL_INTERVAL := 0.1
const CHANNELS_AUTHORITY_POLL_INTERVAL := 0.1
const CHANNELS_WINDOW_RETRY_DELAY := 1.0
const CHANNELS_ENCOUNTER_RETRY_DELAY := 1.0
const CHANNELS_FORMATION_POLL_TAG := "channels_formation_poll"
const CHANNELS_AUTHORITY_POLL_TAG := "channels_authority_poll"
const CHANNELS_ENEMY_WASH_DAMAGE := 100000.0
const CHANNELS_CHANNEL_PARTY_BITE := 6.0
const CHANNELS_CHANNEL_REFRACTORY := 4.0
const CHANNELS_WINDOW_CHANNEL_HALF_WIDTH := 1.15
const CHANNELS_WINDOW_CHANNEL_HALF_LENGTH := 18.0
const CHANNELS_CODA_CHANNEL_TAG := "act1_channels_coda_wash"
const CHANNELS_CODA_FLURE_ID := "act1_channels_coda_flure"
const CHANNELS_ENCOUNTER_FLURE_ID := "act1_channels_encounter_flure"
const CHANNELS_ENCOUNTER_COMMIT_RADIUS := 3.0
const CHANNELS_OPTIONAL_SITES := {
	"optional_worker_names": {"role": "peris", "pos": Vector3(76, 0.5, -1), "dwell": 3.0, "verb": "REMEMBER NAMES", "display": "NAMES", "finding": "Peris preserves two names the casualty report could not recover."},
	"optional_sluice_manual": {"role": "aster", "pos": Vector3(118, 0.5, -14), "dwell": 3.0, "verb": "READ SLUICE MANUAL", "display": "MANUAL", "finding": "A maintenance note explains why the pressure relay was abandoned."},
	"optional_endo_marks": {"role": "endo", "pos": Vector3(188, 0.5, 13), "dwell": 3.0, "verb": "FOLLOW ENDO'S MARKS", "display": "MARKS", "finding": "Old hand marks connect this shelter to Endo's junction route."},
	"optional_seed_cache": {"role": "peris", "pos": Vector3(154, 0.5, 10), "dwell": 3.0, "verb": "INSPECT SEED CACHE", "display": "SEED CACHE", "finding": "Peris confirms the sealed seed pods are still viable and leaves the cache rooted beside the ferrolure."},
	"optional_report_stub": {"role": "aster", "pos": Vector3(48, 0.5, 13), "dwell": 3.0, "verb": "READ REPORT STUB", "display": "REPORT", "finding": "Aster reads the fixed report page in place: it logged flow failures, never the workers beside them."},
	"optional_shelter_bowl": {"role": "endo", "pos": Vector3(214, 0.5, 13), "dwell": 3.0, "verb": "CHECK SHARED BOWL", "display": "BOWL", "finding": "The bowl has been cleaned and left ready for whoever reaches the wall next."},
}

const ACT1_STACKS_REST_AUTHORITY_VERSION := 1
const ACT1_STACKS_REST_AUTHORITY_KEY := "runtime:act1:stacks_shelter_rest"
const ACT1_STACKS_REST_TAG := "act1_stacks_shelter_party_rest"
const STACKS_BANK_ACTOR := "aster"
const STACKS_SHELTER_REST_RADIUS := 5.0
const STACKS_INTERACTION_POSITION_TOLERANCE := 0.25
const STACKS_START := Vector3(240, 0, 0)
const STACKS_END := Vector3(460, 0, 0)
const RINGS_START := Vector3(480, 0, 0)
const RINGS_END := Vector3(680, 0, 0)
const LOCKOUT_START := Vector3(700, 0, 0)
const LOCKOUT_BOUNDARY := Vector3(780, 0, 0)

const STACKS_SHELTER_POS := Vector3(440.0, 0.5, 8.5)

# --- Per-chunk grids ---
# act1 CUTS between chunks (each loads as the previous unloads), so only one chunk is live at a time.
# Each gets its own OPEN GridWorld over its corridor footprint (a generous bounding rect from its
# START..END span); the active grid swaps in when its chunk loads. Movement is then cell-based +
# cooperative per chunk, without a single impractical world-spanning grid.
const CHUNK_GRIDS := {
	"channels": {"origin": Vector3(-6, 0, -16), "size": Vector2i(242, 32)},   # X[-6,236]
	"stacks": {"origin": Vector3(234, 0, -16), "size": Vector2i(232, 32)},    # X[234,466]
	"rings": {"origin": Vector3(474, 0, -16), "size": Vector2i(212, 32)},     # X[474,686]
	"lockout": {"origin": Vector3(694, 0, -16), "size": Vector2i(92, 32)},    # X[694,786]
	# The Endo scene chunk authors its own long-form corridor and all specialist field stations.
	# Keep the cooperative grid aligned to the complete 284x44 authored footprint.
	"endo_junction_stretch": {"origin": Vector3(-2, 0, -22), "size": Vector2i(284, 44)},
}
var _grid: GridWorld
var _endo_junction_chunk: Node3D
## True while the Endo stretch leg is running. The chunk overwrites _current_step with its own per-beat
## step ids (via set_preview_step), so the completion poll keys off this flag, not _current_step.
var _endo_junction_active := false
var _lockout_chase_chunk: Node3D
var _lockout_chase_active := false
var _lockout_rejection_presented := false
var _lockout_dispatch_presented := false
var _pending_act1_campaign_presenters: Dictionary = {}
var _restoring_act1_campaign_authority := false

## Build + activate the named chunk's OPEN grid, swapping it in as the live grid. The party re-derives
## its cells on the new grid (derived state); only one chunk grid is live at a time (act1 cuts between).
func _activate_chunk_grid(chunk_name: String) -> void:
	var spec = CHUNK_GRIDS.get(chunk_name)
	if spec == null or _game_state == null:
		return
	var size: Vector2i = spec["size"]
	_grid = GridWorld.new()
	_grid.origin = spec["origin"]
	_grid.create_room(size.x, size.y, false)
	_game_state.grid = _grid
	for node in [_aster_node, _peris_node, _endo]:
		if node != null and "grid_world" in node:
			node.grid_world = _grid
	for id in _game_state.characters.keys():
		_game_state.characters[id]["grid_cell"] = _grid.world_to_grid(_game_state.get_position(id))

## Scene chunks can author carved cells and dynamic obstacles rather than Act 1's open rectangles.
## Adopt that exact grid so the campaign version routes identically to the fragment preview/tests.
func _activate_hosted_chunk_grid(chunk: Node) -> bool:
	if chunk == null or _game_state == null or not chunk.has_method("get_grid_data"):
		push_error("Act 1 hosted-grid handoff requires a live chunk, GameState, and get_grid_data().")
		return false
	var grid_data: Variant = chunk.call("get_grid_data")
	if not (grid_data is Dictionary) or (grid_data as Dictionary).is_empty():
		push_error("Act 1 refused an empty hosted grid from %s; the previous grid remains active." % chunk.name)
		return false
	var data := grid_data as Dictionary
	if int(data.get("width", 0)) <= 0 or int(data.get("height", 0)) <= 0 \
			or (not bool(data.get("default_walkable", false)) \
				and (data.get("walkable_regions", []) as Array).is_empty() \
				and (data.get("walkable_cells", []) as Array).is_empty()):
		push_error("Act 1 refused a hosted grid with no navigable footprint from %s." % chunk.name)
		return false
	var candidate := GridWorld.from_data(data)
	if candidate.width <= 0 or candidate.height <= 0:
		push_error("Act 1 could not construct the hosted grid from %s." % chunk.name)
		return false
	# Commit only after the replacement has been validated: a malformed incoming
	# chunk must not strand the campaign on a stale origin after the outgoing
	# district has already been unloaded.
	_grid = candidate
	_game_state.grid = _grid
	if chunk.has_method("on_game_state_grid_ready"):
		chunk.call("on_game_state_grid_ready")
	for node in [_aster_node, _peris_node, _endo]:
		if node != null and "grid_world" in node:
			node.grid_world = _grid
	for id in _game_state.characters.keys():
		_game_state.characters[id]["grid_cell"] = _grid.world_to_grid(_game_state.get_position(id))
	return true

# --- Chunk dispatch ---

## Channels/Stacks/Rings/Lockout are PROCEDURAL (built by _build_chunk → null scene). The Endo
## stretch is a self-contained SCENE chunk: returning its PackedScene makes the base _load_chunk
## instantiate it and call attach_chunk_host(self, ...), wiring it to act1's GameState/scheduler/UI.
func _get_chunk_scene(chunk_name: String) -> PackedScene:
	if chunk_name == "endo_junction_stretch":
		return ENDO_JUNCTION_STRETCH_CHUNK_SCENE
	if chunk_name == "lockout_chase_campaign":
		return LOCKOUT_CHASE_CHUNK_SCENE
	return null

func _build_chunk(chunk_name: String, parent: Node3D) -> void:
	match chunk_name:
		"channels": _build_channels_chunk(parent)
		"stacks": _build_stacks_chunk(parent)
		"rings": _build_rings_chunk(parent)
		"lockout": _build_lockout_chunk(parent)
	LevelDecoratorScript.decorate_act1_chunk(parent, chunk_name)

# --- Virtual overrides ---

func _build_scene() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.2, 0.2, 0.25)
	e.ambient_light_energy = 0.4
	e.glow_enabled = true
	e.glow_intensity = 0.2
	we.environment = e
	env.add_child(we)
	_load_chunk("channels")

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	# Aster (player)
	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = CHANNELS_START + Vector3(1, 0.5, 0)
	chars.add_child(_player)
	_aster_node = _player

	# Peris
	_peris_node = _create_player_character("Peris", Color(1.0, 0.67, 0.27))
	_peris_node.position = CHANNELS_START + Vector3(0, 0.5, 1)
	chars.add_child(_peris_node)

	# Endo joins during the Channels encounter.
	_endo = _create_player_character("Endo", Color(0.4, 0.67, 0.53))
	_endo.position = CHANNELS_START + Vector3(-1, 0.5, 0)
	chars.add_child(_endo)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 10, 8), true)

func _register_characters() -> void:
	_activate_chunk_grid("channels")  # the live grid for the opening chunk
	_register_gs_character("aster", _aster_node, 3.0, {"hp": CHANNELS_MAX_HP, "atp": 6.0})
	_register_gs_character("peris", _peris_node, 2.5, {"hp": CHANNELS_MAX_HP, "atp": 6.0})
	_register_gs_character("endo", _endo, 2.5, {"hp": CHANNELS_MAX_HP, "atp": 6.0})
	_game_state.add_shelter_region(
		Vector2(CHANNELS_SHELTER_POS.x - 5.0, CHANNELS_SHELTER_POS.z - 5.0),
		Vector2(CHANNELS_SHELTER_POS.x + 5.0, CHANNELS_SHELTER_POS.z + 5.0)
	)
	_game_state.add_shelter_region(
		Vector2(STACKS_SHELTER_POS.x - 6.0, STACKS_SHELTER_POS.z - 5.0),
		Vector2(STACKS_SHELTER_POS.x + 6.0, STACKS_SHELTER_POS.z + 5.0)
	)
	_bind_channels_optional_sites_to_game_state()
	_setup_channels_shortcut_gate()
	_apply_channels_grid_occluders()
	_activate_channels_kit()
	_connect_channels_authority_signals()
	_ensure_channels_runtime_authority()
	_ensure_act1_stacks_rest_authority()
	_ensure_act1_campaign_authority()
	_connect_rings_departure_signals()

func _setup_ui() -> void:
	_build_overlay_ui()
	_flora_overlay_root = Node3D.new()
	_flora_overlay_root.name = "FloraOverlayRoot"
	add_child(_flora_overlay_root)
	_apply_overlay_visibility()
	_select_character("aster")

func _begin() -> void:
	_player.set_move_enabled(false)
	if start_chunk != "":
		if start_chunk == "endo_junction_stretch":
			# The scene chunk owns its own world; don't load the procedural opener around it.
			_start_endo_junction_stretch_enter()
			return
		_load_chunk(start_chunk)
		_player.set_move_enabled(true)
		match start_chunk:
			"channels":
				_player.global_position = CHANNELS_START + Vector3(5, 0.5, 0)
				_start_channels_enter()
			"stacks":
				_player.global_position = STACKS_START + Vector3(5, 0.5, 0)
				_start_stacks_enter()
			"rings":
				_player.global_position = RINGS_START + Vector3(5, 0.5, 0)
				_start_rings_enter()
			"lockout":
				_player.global_position = LOCKOUT_START + Vector3(5, 0.5, 0)
				_start_lockout_approach()
		return
	_current_step = "fade_in"
	_fade_from(Color(0.02, 0.02, 0.03, 1), OPENING_FADE_DURATION, _start_channels_enter, "channels_enter")

func _compute_speed() -> float:
	return 10.0 if Input.is_action_pressed("fast_forward") else 1.0

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_F1:
				_toggle_overlay("aster")
			KEY_F2:
				_toggle_overlay("peris")

func _on_process(delta: float, spd: float) -> void:
	if _current_step == "fade_in":
		_update_fade_in(OPENING_FADE_DURATION)

	var channels_formation_moving := (
		str(_channels_formation_authority.get("phase", "idle")) == "moving")
	var channels_script_locked := channels_formation_moving or _current_step in [
		"channels_window_one_intro",
		"channels_window_one_activate",
		"channels_window_one_cross",
		"channels_window_one_reset",
		"channels_window_two_intro",
		"channels_window_two_activate",
		"channels_window_two_cross",
		"channels_window_two_reset",
		"channels_encounter_intro",
		"channels_encounter_activate",
		"channels_encounter_hide",
		"channels_encounter_run",
		"channels_encounter_reset",
		"channels_memory",
		"channels_corpse",
		"channels_flure",
		"channels_shelter",
	]

	_update_channels_encounter(delta, spd)
	_update_channels_flure_flush(delta, spd)
	_update_channels_window_puzzles(delta, spd)
	_sync_channels_shortcut_gate_presentation()
	_update_overlay_note(delta)
	_update_flora_system()

	# Followers trail the leader outside cutscenes.
	if not channels_script_locked:
		var leader := _get_character_node(_active_character)
		for pair in [
			["aster", _aster_node, Vector3(-1.2, 0, 0.8)],
			["peris", _peris_node, Vector3(-1.2, 0, 1.2)],
			["endo", _endo, Vector3(-1.2, 0, -0.8)],
		]:
			var cid: String = pair[0]
			var cnode: CharacterBody3D = pair[1]
			var offset: Vector3 = pair[2]
			if cid == _active_character or cnode == null or not cnode.visible or not _game_state.characters.has(cid):
				continue
			var dist := cnode.global_position.distance_to(leader.global_position)
			if dist > 3.0 and not _game_state.is_moving(cid):
				_game_state.command_move_to_pos(cid, leader.global_position + offset)

	# Endo stretch (its own leg): the chunk overwrites _current_step with per-beat ids, so poll on the
	# leg flag and the chunk's route_phase (set to "complete" by reach_shelter), not _current_step.
	if _endo_junction_active:
		if _endo_junction_chunk != null and is_instance_valid(_endo_junction_chunk) and _endo_junction_chunk.has_method("get_preview_state"):
			var stretch_state: Dictionary = _endo_junction_chunk.call("get_preview_state")
			if str(stretch_state.get("route_phase", "")) == "complete":
				_start_endo_junction_stretch_complete()

	# The authored chase owns its hazards, checkpoints, and wall rest. Act 1 only watches the
	# completion contract, then resumes the existing aftermath/handoff.
	if _lockout_chase_active:
		if _lockout_chase_chunk != null and is_instance_valid(_lockout_chase_chunk) \
				and _lockout_chase_chunk.has_method("get_preview_state"):
			var chase_state: Dictionary = _lockout_chase_chunk.call("get_preview_state")
			if bool(chase_state.get("complete", false)):
				_start_lockout_exile()

	if _current_step == "stacks_explore":
		if _game_state.get_position("aster").x > STACKS_END.x - 5.0:
			_start_rings_enter()

	if _current_step == "rings_explore":
		if _game_state.get_position("aster").x > RINGS_END.x - 5.0:
			_start_lockout_approach()

	# Lockout chase: Naturalizers walk toward party, stop at boundary
	if _current_step == "lockout_chase" and not _lockout_chase_active:
		for nk in _naturalizers:
			if is_instance_valid(nk):
				var nk_pos := nk.global_position
				var aster_pos := _aster_node.global_position
				# Stop at the unserviced boundary.
				if aster_pos.x < LOCKOUT_START.x - 10.0:
					_start_lockout_exile()
					break


## Fixed scheduler cadence for Channels iron. The record is the save/replay authority; the callback
## heap is derived and is rebuilt by on_game_state_snapshot_restored after every production load.
func _start_iron_hazard_cadence() -> void:
	if _scheduler == null or _game_state == null:
		return
	if _iron_hazard_active:
		return
	_iron_hazard_active = true
	_arm_iron_hazard_at(float(_scheduler.get_current_tick()) + IRON_DAMAGE_INTERVAL)


func _stop_iron_hazard_cadence() -> void:
	if _scheduler != null:
		_scheduler.cancel_tag(IRON_HAZARD_TAG)
	_iron_hazard_active = false
	_iron_hazard_next_tick = -1.0
	_publish_iron_hazard_authority()


func _arm_iron_hazard_at(deadline: float) -> void:
	if _scheduler == null or not _iron_hazard_active:
		return
	_scheduler.cancel_tag(IRON_HAZARD_TAG)
	_iron_hazard_next_tick = maxf(float(_scheduler.get_current_tick()), deadline)
	_publish_iron_hazard_authority()
	_scheduler.schedule_at(_iron_hazard_next_tick, _on_iron_hazard_tick, IRON_HAZARD_TAG)


func _on_iron_hazard_tick() -> void:
	if not _iron_hazard_active or _scheduler == null:
		return
	_iron_hazard_next_tick = -1.0
	_apply_iron_damage_tick()
	_arm_iron_hazard_at(float(_scheduler.get_current_tick()) + IRON_DAMAGE_INTERVAL)


func _apply_iron_damage_tick() -> void:
	if _game_state == null:
		return
	for cid in ["aster", "peris"]:
		if not _game_state.characters.has(cid) or _game_state.get_stat(cid, "hp") <= 0.0:
			continue
		var cpos: Vector3 = _game_state.get_position(cid)
		for patch in _iron_patches:
			var ppos: Vector3 = patch.pos
			var psz: Vector3 = patch.size
			if absf(cpos.x - ppos.x) < psz.x / 2.0 \
					and absf(cpos.z - ppos.z) < psz.z / 2.0:
				_game_state.adjust_stat(
					cid, "hp", -(IRON_DAMAGE_PER_SEC * IRON_DAMAGE_INTERVAL), IRON_HAZARD_TAG)
				break
	if _game_state.characters.has("aster"):
		_aster_hp = _game_state.get_stat("aster", "hp")
	if _game_state.characters.has("peris"):
		_peris_hp = _game_state.get_stat("peris", "hp")


func _publish_iron_hazard_authority() -> void:
	if _restoring_iron_hazard or _game_state == null:
		return
	_game_state.set_world_state(IRON_HAZARD_AUTHORITY_KEY, {
		"version": IRON_HAZARD_AUTHORITY_VERSION,
		"active": _iron_hazard_active,
		"next_tick": _iron_hazard_next_tick,
	})


func _baseline_act1_campaign_authority() -> Dictionary:
	return {
		"version": ACT1_CAMPAIGN_AUTHORITY_VERSION,
		"endo_junction_active": false,
		"lockout_chase_active": false,
		"lockout_rejection_presented": false,
		"lockout_dispatch_presented": false,
	}


func _ensure_act1_campaign_authority() -> void:
	if _game_state == null or not _game_state.has_method("get_world_state"):
		return
	var saved: Variant = _game_state.get_world_state(ACT1_CAMPAIGN_AUTHORITY_KEY, null)
	if not saved is Dictionary:
		_game_state.set_world_state(
			ACT1_CAMPAIGN_AUTHORITY_KEY, _baseline_act1_campaign_authority())


func _publish_act1_campaign_authority() -> void:
	if _restoring_act1_campaign_authority or _game_state == null:
		return
	_game_state.set_world_state(ACT1_CAMPAIGN_AUTHORITY_KEY, {
		"version": ACT1_CAMPAIGN_AUTHORITY_VERSION,
		"endo_junction_active": _endo_junction_active,
		"lockout_chase_active": _lockout_chase_active,
		"lockout_rejection_presented": _lockout_rejection_presented,
		"lockout_dispatch_presented": _lockout_dispatch_presented,
	})


func _restore_act1_campaign_authority() -> void:
	if _game_state == null:
		return
	var saved_v: Variant = _game_state.get_world_state(ACT1_CAMPAIGN_AUTHORITY_KEY, null)
	# Legacy snapshots predate this record. The presenter snapshot/current step migration performed
	# before GameState replacement remains the conservative truth for those saves.
	if not saved_v is Dictionary \
			or int(saved_v.get("version", 0)) != ACT1_CAMPAIGN_AUTHORITY_VERSION:
		return
	var saved := saved_v as Dictionary
	_restoring_act1_campaign_authority = true
	_endo_junction_active = bool(saved.get("endo_junction_active", false)) \
		and is_instance_valid(_endo_junction_chunk)
	_lockout_chase_active = bool(saved.get("lockout_chase_active", false)) \
		and is_instance_valid(_lockout_chase_chunk)
	_lockout_rejection_presented = bool(saved.get("lockout_rejection_presented", false))
	_lockout_dispatch_presented = bool(saved.get("lockout_dispatch_presented", false))
	_restoring_act1_campaign_authority = false


func on_game_state_snapshot_restored() -> void:
	if _scheduler == null or _game_state == null:
		return
	_restore_act1_campaign_presenter_links(_current_step, false)
	_restore_act1_campaign_authority()
	_connect_channels_authority_signals()
	_restore_channels_runtime_authority_from_game_state()
	_restore_act1_stacks_rest_authority_from_game_state()
	_connect_rings_departure_signals()
	_restore_rings_endo_authority_from_game_state()
	_scheduler.cancel_tag(IRON_HAZARD_TAG)
	_restoring_iron_hazard = true
	_iron_hazard_active = false
	_iron_hazard_next_tick = -1.0
	var saved_v: Variant = _game_state.get_world_state(IRON_HAZARD_AUTHORITY_KEY, null)
	if saved_v is Dictionary:
		var saved := saved_v as Dictionary
		if int(saved.get("version", 0)) == IRON_HAZARD_AUTHORITY_VERSION:
			_iron_hazard_active = bool(saved.get("active", false))
			_iron_hazard_next_tick = float(saved.get("next_tick", -1.0))
			if _iron_hazard_active and _iron_hazard_next_tick >= 0.0:
				_arm_iron_hazard_at(_iron_hazard_next_tick)
	_restoring_iron_hazard = false
	if _game_state.characters.has("aster"):
		_aster_hp = _game_state.get_stat("aster", "hp")
	if _game_state.characters.has("peris"):
		_peris_hp = _game_state.get_stat("peris", "hp")
	if is_instance_valid(_channels_shortcut_gate):
		# The traversal notifies children after this controller, but restoring here as well makes the
		# campaign's derived shortcut state coherent for immediate snapshot inspection. PartyGate3D's
		# attachment is deliberately idempotent, so the later child notification cannot mint a timer.
		_channels_shortcut_gate.on_game_state_snapshot_restored()
		_sync_channels_shortcut_gate_presentation()


func _channels_full_conscious_party_past_x(threshold: float) -> bool:
	if _game_state == null:
		return false
	for char_id in CHANNELS_PARTY_IDS:
		if not _game_state.characters.has(char_id) or _game_state.is_downed(char_id) \
				or _game_state.get_position(char_id).x <= threshold:
			return false
	return true


func _channels_full_conscious_party_near(position: Vector3, radius: float) -> bool:
	if _game_state == null:
		return false
	for char_id in CHANNELS_PARTY_IDS:
		if not _game_state.characters.has(char_id) or _game_state.is_downed(char_id) \
				or _game_state.get_position(char_id).distance_to(position) > radius:
			return false
	return true


func _channels_conscious_party_positions() -> Dictionary:
	var positions := {}
	if _game_state == null:
		return positions
	for char_id in CHANNELS_PARTY_IDS:
		if _game_state.characters.has(char_id) and not _game_state.is_downed(char_id):
			positions[char_id] = _game_state.get_position(char_id)
	return positions


func _connect_channels_authority_signals() -> void:
	if _channels_arrival_signal_game_state != null \
			and is_instance_valid(_channels_arrival_signal_game_state) \
			and _channels_arrival_signal_game_state.character_arrived.is_connected(
				_on_channels_character_arrived):
		_channels_arrival_signal_game_state.character_arrived.disconnect(
			_on_channels_character_arrived)
	_channels_arrival_signal_game_state = _game_state
	if _game_state != null and not _game_state.character_arrived.is_connected(
			_on_channels_character_arrived):
		_game_state.character_arrived.connect(_on_channels_character_arrived)


func _channels_baseline_formation_authority() -> Dictionary:
	return {
		"phase": "idle",
		"operation_id": "",
		"tag": "",
		"required_ids": [],
		"accepted_ids": [],
		"already_at_endpoint_ids": [],
		"destinations": {},
		"start_tick": -1.0,
		"reason": "",
	}


func _valid_channels_flure(lane: Dictionary) -> Flure:
	var candidate: Variant = lane.get("interactable")
	if not is_instance_valid(candidate) or not candidate is Flure:
		return null
	return candidate as Flure


func _valid_channels_channel(container: Dictionary, key: String = "node") -> Channel:
	var candidate: Variant = container.get(key)
	if not is_instance_valid(candidate) or not candidate is Channel:
		return null
	return candidate as Channel


func _channels_window_authority_state(lane: Dictionary) -> Dictionary:
	var flure := _valid_channels_flure(lane)
	return {
		"phase": str(lane.get("phase", "idle")),
		"retry_deadline": float(lane.get("retry_deadline", -1.0)),
		"last_outcome": str(lane.get("last_outcome", "")),
		"flure_authority_id": flure.authority_id if is_instance_valid(flure) else "",
		"enemy_ids": (lane.get("enemy_ids", []) as Array).duplicate(),
		"swept_ids": (lane.get("swept_ids", []) as Array).duplicate(),
	}


func _channels_runtime_authority_state() -> Dictionary:
	var windows := {}
	for window_id_variant in _channels_window_lanes.keys():
		var window_id := str(window_id_variant)
		windows[window_id] = _channels_window_authority_state(
			_channels_window_lanes[window_id])
	return {
		"contract": CHANNELS_RUNTIME_AUTHORITY_CONTRACT,
		"version": CHANNELS_RUNTIME_AUTHORITY_VERSION,
		"required_party": CHANNELS_PARTY_IDS.duplicate(),
		"poll_active": _channels_authority_poll_active,
		"poll_origin_tick": _channels_authority_poll_origin_tick,
		"active_window_lane": _channels_active_window_lane,
		"windows": windows,
		"coda": {
			"phase": _channels_coda_phase,
			"flure_authority_id": CHANNELS_CODA_FLURE_ID,
			"enemy_ids": _channels_flush_enemy_ids.duplicate(),
			"swept_ids": _channels_coda_swept_ids.duplicate(),
		},
		"encounter": {
			"phase": _channels_encounter_phase,
			"phase_start_tick": _channels_encounter_phase_start_tick,
			"retry_deadline": _channels_encounter_retry_deadline,
			"flure_authority_id": CHANNELS_ENCOUNTER_FLURE_ID,
			"enemy_ids": _channels_swarm_enemy_ids.duplicate(),
			"spotted_ids": _channels_encounter_spotted_ids.duplicate(),
		},
		"formation": _channels_formation_authority.duplicate(true),
		"shelter": {
			"reached": _channels_shelter_reached,
			"recuperated": _channels_party_recuperated,
			"rest_phase": _channels_shelter_rest_phase,
			"rest_members": _channels_shelter_rest_members.duplicate(),
			"rest_commit_tick": _channels_shelter_rest_commit_tick,
			"rest_commit_day": _channels_shelter_rest_commit_day,
			"rest_before_atp": _channels_shelter_rest_before_atp.duplicate(true),
		},
	}


func _channels_baseline_runtime_authority() -> Dictionary:
	var baseline := _channels_runtime_authority_state()
	baseline["active_window_lane"] = ""
	baseline["poll_active"] = false
	baseline["poll_origin_tick"] = -1.0
	var windows: Dictionary = baseline.get("windows", {})
	for window_id_variant in windows.keys():
		var window_id := str(window_id_variant)
		var lane: Dictionary = _channels_window_lanes.get(window_id, {})
		var flure := _valid_channels_flure(lane)
		windows[window_id] = {
			"phase": "idle",
			"retry_deadline": -1.0,
			"last_outcome": "",
			"flure_authority_id": flure.authority_id if is_instance_valid(flure) else "",
			"enemy_ids": (lane.get("enemy_ids", []) as Array).duplicate(),
			"swept_ids": [],
		}
	baseline["windows"] = windows
	baseline["coda"] = {
		"phase": "idle",
		"flure_authority_id": CHANNELS_CODA_FLURE_ID,
		"enemy_ids": _channels_flush_enemy_ids.duplicate(),
		"swept_ids": [],
	}
	baseline["encounter"] = {
		"phase": "idle",
		"phase_start_tick": -1.0,
		"retry_deadline": -1.0,
		"flure_authority_id": CHANNELS_ENCOUNTER_FLURE_ID,
		"enemy_ids": _channels_swarm_enemy_ids.duplicate(),
		"spotted_ids": [],
	}
	baseline["formation"] = _channels_baseline_formation_authority()
	baseline["shelter"] = {
		"reached": false,
		"recuperated": false,
		"rest_phase": "locked",
		"rest_members": [],
		"rest_commit_tick": -1.0,
		"rest_commit_day": 0,
		"rest_before_atp": {},
	}
	return baseline


func _valid_channels_runtime_authority(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var saved := value as Dictionary
	if str(saved.get("contract", "")) != CHANNELS_RUNTIME_AUTHORITY_CONTRACT \
			or int(saved.get("version", 0)) != CHANNELS_RUNTIME_AUTHORITY_VERSION \
			or saved.get("required_party", []) != CHANNELS_PARTY_IDS \
			or not (saved.get("windows", null) is Dictionary) \
			or not (saved.get("coda", null) is Dictionary) \
			or not (saved.get("encounter", null) is Dictionary) \
			or not (saved.get("formation", null) is Dictionary) \
			or not (saved.get("shelter", null) is Dictionary):
		return false
	if bool(saved.get("poll_active", false)) \
			and float(saved.get("poll_origin_tick", -1.0)) < 0.0:
		return false
	var windows: Dictionary = saved["windows"]
	for window_id in ["window_one", "window_two"]:
		var lane_v: Variant = windows.get(window_id, null)
		if not (lane_v is Dictionary):
			return false
		var lane := lane_v as Dictionary
		var phase := str(lane.get("phase", ""))
		var expected_lane: Dictionary = _channels_window_lanes.get(window_id, {})
		var expected_enemy_ids: Array = expected_lane.get("enemy_ids", [])
		var swept_ids: Array = lane.get("swept_ids", [])
		if phase not in CHANNELS_WINDOW_AUTHORITY_PHASES \
				or str(lane.get("flure_authority_id", "")) \
					!= "act1_channels_%s_flure" % window_id \
				or lane.get("enemy_ids", []) != expected_enemy_ids \
				or not _channels_stable_subset(swept_ids, expected_enemy_ids):
			return false
		if phase == "failed" and float(lane.get("retry_deadline", -1.0)) < 0.0:
			return false
	var coda := saved["coda"] as Dictionary
	if str(coda.get("phase", "")) not in ["idle", "ready", "luring", "washing", "complete"] \
			or str(coda.get("flure_authority_id", "")) != CHANNELS_CODA_FLURE_ID \
			or coda.get("enemy_ids", []) != _channels_flush_enemy_ids \
			or not _channels_stable_subset(
				coda.get("swept_ids", []), _channels_flush_enemy_ids):
		return false
	var encounter := saved["encounter"] as Dictionary
	var encounter_phase := str(encounter.get("phase", ""))
	if encounter_phase not in CHANNELS_ENCOUNTER_AUTHORITY_PHASES \
			or str(encounter.get("flure_authority_id", "")) \
				!= CHANNELS_ENCOUNTER_FLURE_ID \
			or encounter.get("enemy_ids", []) != _channels_swarm_enemy_ids \
			or not _channels_stable_subset(
				encounter.get("spotted_ids", []), _channels_swarm_enemy_ids):
		return false
	if encounter_phase == "failed" \
			and float(encounter.get("retry_deadline", -1.0)) < 0.0:
		return false
	var formation := saved["formation"] as Dictionary
	var formation_phase := str(formation.get("phase", ""))
	if formation_phase not in CHANNELS_FORMATION_AUTHORITY_PHASES:
		return false
	if formation_phase == "moving" and (
			str(formation.get("operation_id", "")).is_empty()
			or formation.get("required_ids", []) != CHANNELS_PARTY_IDS
			or formation.get("accepted_ids", []) != CHANNELS_PARTY_IDS
			or not (formation.get("destinations", null) is Dictionary)):
		return false
	if formation_phase == "moving":
		var formation_destinations := formation["destinations"] as Dictionary
		for char_id in CHANNELS_PARTY_IDS:
			if not formation_destinations.has(char_id) \
					or not _valid_channels_position_data(formation_destinations[char_id]):
				return false
	var shelter := saved["shelter"] as Dictionary
	var rest_phase := str(shelter.get("rest_phase", ""))
	var rest_members_v: Variant = shelter.get("rest_members", null)
	var rest_before_v: Variant = shelter.get("rest_before_atp", null)
	if rest_phase not in ACT1_REST_PHASES \
			or not (rest_members_v is Array) or not (rest_before_v is Dictionary):
		return false
	var reached := bool(shelter.get("reached", false))
	var recuperated := bool(shelter.get("recuperated", false))
	if (rest_phase != "locked") != reached or (rest_phase == "rested") != recuperated:
		return false
	var rest_members := rest_members_v as Array
	var rest_before := rest_before_v as Dictionary
	if rest_phase == "committing":
		if rest_members.is_empty() \
				or not _channels_stable_subset(rest_members, CHANNELS_PARTY_IDS) \
				or float(shelter.get("rest_commit_tick", -1.0)) < 0.0:
			return false
		for char_id_v in rest_members:
			if not rest_before.has(str(char_id_v)):
				return false
	elif not rest_members.is_empty() or not rest_before.is_empty() \
			or float(shelter.get("rest_commit_tick", -1.0)) >= 0.0:
		return false
	return true


func _normalized_channels_runtime_authority(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var saved := (value as Dictionary).duplicate(true)
	if int(saved.get("version", 0)) == 2 \
			and str(saved.get("contract", "")) == "act1_channels/v2":
		saved["version"] = CHANNELS_RUNTIME_AUTHORITY_VERSION
		saved["contract"] = CHANNELS_RUNTIME_AUTHORITY_CONTRACT
		saved["shelter"] = {
			"reached": false,
			"recuperated": false,
			"rest_phase": "locked",
			"rest_members": [],
			"rest_commit_tick": -1.0,
			"rest_commit_day": 0,
			"rest_before_atp": {},
		}
	return saved if _valid_channels_runtime_authority(saved) else {}


func _channels_stable_subset(values: Variant, allowed: Array) -> bool:
	if not (values is Array):
		return false
	var seen := {}
	for value_v in values as Array:
		var value := str(value_v)
		if value not in allowed or seen.has(value):
			return false
		seen[value] = true
	return true


func _ensure_channels_runtime_authority() -> void:
	if _game_state == null:
		return
	var raw: Variant = _game_state.get_world_state(CHANNELS_RUNTIME_AUTHORITY_KEY, null)
	var normalized := _normalized_channels_runtime_authority(raw)
	if not normalized.is_empty():
		_restore_channels_runtime_authority_from_game_state()
		if int((raw as Dictionary).get("version", 0)) != CHANNELS_RUNTIME_AUTHORITY_VERSION:
			_game_state.set_world_state(CHANNELS_RUNTIME_AUTHORITY_KEY, normalized)
		return
	_channels_formation_authority = _channels_baseline_formation_authority()
	_game_state.set_world_state(
		CHANNELS_RUNTIME_AUTHORITY_KEY, _channels_baseline_runtime_authority())


func _publish_channels_runtime_authority() -> void:
	if _restoring_channels_authority or _game_state == null:
		return
	_game_state.set_world_state(
		CHANNELS_RUNTIME_AUTHORITY_KEY, _channels_runtime_authority_state())


func _cancel_channels_runtime_callbacks() -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(CHANNELS_FORMATION_POLL_TAG)
	_scheduler.cancel_tag(CHANNELS_AUTHORITY_POLL_TAG)
	_scheduler.cancel_tag(CHANNELS_SHELTER_REST_TAG)
	_scheduler.cancel_tag("channels_encounter_retry")
	for window_id_variant in _channels_window_lanes.keys():
		var window_id := str(window_id_variant)
		_scheduler.cancel_tag("channels_%s_retry" % window_id)


func _apply_channels_window_authority(window_id: String, saved: Dictionary) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	var lane: Dictionary = _reset_channels_window_swarm(_channels_window_lanes[window_id])
	lane["phase"] = str(saved.get("phase", "idle"))
	lane["retry_deadline"] = float(saved.get("retry_deadline", -1.0))
	lane["last_outcome"] = str(saved.get("last_outcome", ""))
	lane["swept_ids"] = (saved.get("swept_ids", []) as Array).duplicate()
	lane["swarm_state"] = (
		"washed" if _channels_scope_is_fully_swept(
			lane.get("enemy_ids", []), lane.get("swept_ids", []))
		else ("washing" if not (lane.get("swept_ids", []) as Array).is_empty() else "idle"))
	var flure := _valid_channels_flure(lane)
	var effect := flure.get_effect_state() if is_instance_valid(flure) else {}
	var lure_active := str(effect.get("phase", "")) == "active"
	lane["lure_active"] = lure_active
	lane["safe_until_tick"] = float(effect.get("end_tick", -1.0)) if lure_active else -1.0
	_channels_window_lanes[window_id] = lane
	_set_channels_window_lane_active(window_id, lure_active)
	if is_instance_valid(flure):
		var enabled := str(lane.get("phase", "")) in ["activate", "cross"] \
			and not lure_active
		flure.set_interaction_enabled(enabled)
		if enabled:
			flure.show_tutorial_label()
		else:
			flure.hide_tutorial_label()


func _apply_channels_runtime_authority(saved: Dictionary) -> void:
	_channels_authority_poll_active = bool(saved.get("poll_active", false))
	_channels_authority_poll_origin_tick = float(saved.get("poll_origin_tick", -1.0))
	_channels_authority_next_poll_tick = -1.0
	_channels_active_window_lane = str(saved.get("active_window_lane", ""))
	var windows: Dictionary = saved.get("windows", {})
	for window_id_variant in _channels_window_lanes.keys():
		var window_id := str(window_id_variant)
		var window_saved_v: Variant = windows.get(window_id, {})
		_apply_channels_window_authority(
			window_id, window_saved_v as Dictionary if window_saved_v is Dictionary else {})
	var coda_v: Variant = saved.get("coda", {})
	var coda: Dictionary = coda_v as Dictionary if coda_v is Dictionary else {}
	_channels_coda_phase = str(coda.get("phase", "idle"))
	_channels_coda_swept_ids.assign(coda.get("swept_ids", []))
	if is_instance_valid(_channels_flure):
		var coda_effect := _channels_flure.get_effect_state()
		var coda_ready := _channels_coda_phase == "ready" \
			and str(coda_effect.get("phase", "")) == "ready"
		_channels_flure.set_interaction_enabled(coda_ready)
		if coda_ready:
			_channels_flure.show_tutorial_label()
		else:
			_channels_flure.hide_tutorial_label()
	var encounter_v: Variant = saved.get("encounter", {})
	var encounter: Dictionary = encounter_v as Dictionary if encounter_v is Dictionary else {}
	_channels_encounter_phase = str(encounter.get("phase", "idle"))
	_channels_encounter_phase_start_tick = float(encounter.get("phase_start_tick", -1.0))
	_channels_encounter_retry_deadline = float(encounter.get("retry_deadline", -1.0))
	_channels_encounter_spotted_ids.assign(encounter.get("spotted_ids", []))
	_channels_party_hidden = _channels_full_conscious_party_near(
		CHANNELS_HIDE_SPOT_POS, CHANNELS_HIDE_RADIUS)
	_channels_exposure_by_character = _channels_compute_exposure_by_character()
	_channels_encounter_resetting = _channels_encounter_phase in ["failed", "reset"]
	var encounter_effect := (
		_channels_run_lure.get_effect_state()
		if is_instance_valid(_channels_run_lure) else {})
	_channels_encounter_lure_start_tick = float(encounter_effect.get("start_tick", -1.0))
	_channels_run_lure_expire_tick = float(encounter_effect.get("end_tick", -1.0))
	_set_channels_run_lure_active(str(encounter_effect.get("phase", "")) == "active")
	if is_instance_valid(_channels_run_lure):
		var encounter_ready := _channels_encounter_phase == "activate" \
			and not _channels_run_lure_active
		_channels_run_lure.set_interaction_enabled(encounter_ready)
		if encounter_ready:
			_channels_run_lure.show_tutorial_label()
		else:
			_channels_run_lure.hide_tutorial_label()
	var formation_v: Variant = saved.get("formation", {})
	_channels_formation_authority = (
		(formation_v as Dictionary).duplicate(true)
		if formation_v is Dictionary else _channels_baseline_formation_authority())
	var shelter_v: Variant = saved.get("shelter", {})
	var shelter: Dictionary = shelter_v as Dictionary if shelter_v is Dictionary else {}
	_channels_shelter_reached = bool(shelter.get("reached", false))
	_channels_party_recuperated = bool(shelter.get("recuperated", false))
	_channels_shelter_rest_phase = str(shelter.get("rest_phase", "locked"))
	_channels_shelter_rest_members.assign(shelter.get("rest_members", []))
	_channels_shelter_rest_commit_tick = float(shelter.get("rest_commit_tick", -1.0))
	_channels_shelter_rest_commit_day = int(shelter.get("rest_commit_day", 0))
	_channels_shelter_rest_before_atp = (
		shelter.get("rest_before_atp", {}) as Dictionary).duplicate(true)
	_apply_channels_shelter_rest_presentation()


func _restore_channels_runtime_authority_from_game_state() -> void:
	if _scheduler == null or _game_state == null:
		return
	_cancel_channels_runtime_callbacks()
	_restoring_channels_authority = true
	var raw: Variant = _game_state.get_world_state(CHANNELS_RUNTIME_AUTHORITY_KEY, null)
	var normalized := _normalized_channels_runtime_authority(raw)
	var saved := normalized if not normalized.is_empty() else _channels_baseline_runtime_authority()
	_apply_channels_runtime_authority(saved)
	_restoring_channels_authority = false
	_rearm_channels_runtime_authority()


func _arm_channels_callback_at(deadline: float, callback: Callable, tag: String) -> void:
	if _scheduler == null or deadline < 0.0:
		return
	_scheduler.cancel_tag(tag)
	_scheduler.schedule_at(
		maxf(float(_scheduler.get_current_tick()), deadline), callback, tag)


func _rearm_channels_runtime_authority() -> void:
	if _scheduler == null:
		return
	for window_id_variant in _channels_window_lanes.keys():
		var window_id := str(window_id_variant)
		var lane: Dictionary = _channels_window_lanes[window_id]
		if str(lane.get("phase", "idle")) == "failed":
			_arm_channels_callback_at(
				float(lane.get("retry_deadline", -1.0)),
				_restart_channels_window_lane.bind(window_id),
				"channels_%s_retry" % window_id)
	if _channels_encounter_phase == "failed":
		_arm_channels_callback_at(
			_channels_encounter_retry_deadline,
			_restart_channels_encounter.bind("saved_retry"),
			"channels_encounter_retry")
	if str(_channels_formation_authority.get("phase", "idle")) == "moving":
		_arm_channels_formation_poll()
	if _channels_authority_poll_active:
		_arm_channels_authority_poll_at(_channels_next_authority_poll_tick())
	if _channels_shelter_rest_phase == "committing":
		_arm_channels_shelter_rest_callback()


func _channels_next_authority_poll_tick() -> float:
	if _scheduler == null or _channels_authority_poll_origin_tick < 0.0:
		return -1.0
	var current_tick := float(_scheduler.get_current_tick())
	var elapsed := maxf(0.0, current_tick - _channels_authority_poll_origin_tick)
	var completed_intervals := floori(elapsed / CHANNELS_AUTHORITY_POLL_INTERVAL)
	var candidate := _channels_authority_poll_origin_tick \
		+ float(completed_intervals + 1) * CHANNELS_AUTHORITY_POLL_INTERVAL
	if candidate <= current_tick + 0.000001:
		candidate += CHANNELS_AUTHORITY_POLL_INTERVAL
	return candidate


func _arm_channels_authority_poll_at(deadline: float) -> void:
	if _scheduler == null or not _channels_authority_poll_active:
		return
	_scheduler.cancel_tag(CHANNELS_AUTHORITY_POLL_TAG)
	var current_tick := float(_scheduler.get_current_tick())
	var effective_deadline := maxf(
		current_tick, deadline if deadline >= 0.0 else current_tick + CHANNELS_AUTHORITY_POLL_INTERVAL)
	_channels_authority_next_poll_tick = effective_deadline
	_scheduler.schedule_at(
		effective_deadline,
		_on_channels_authority_poll,
		CHANNELS_AUTHORITY_POLL_TAG)


func _start_channels_authority_poll() -> void:
	if _scheduler == null:
		return
	if _channels_authority_poll_active:
		return
	_channels_authority_poll_active = true
	_channels_authority_poll_origin_tick = float(_scheduler.get_current_tick())
	_arm_channels_authority_poll_at(_channels_next_authority_poll_tick())
	_publish_channels_runtime_authority()


func _stop_channels_authority_poll() -> void:
	if _scheduler != null:
		_scheduler.cancel_tag(CHANNELS_AUTHORITY_POLL_TAG)
	_channels_authority_poll_active = false
	_channels_authority_poll_origin_tick = -1.0
	_channels_authority_next_poll_tick = -1.0
	_publish_channels_runtime_authority()


func _on_channels_authority_poll() -> void:
	if not _channels_authority_poll_active or _scheduler == null:
		return
	_channels_authority_next_poll_tick = -1.0
	_evaluate_channels_streaming_endpoints()
	_evaluate_channels_window_authority()
	_evaluate_channels_encounter_authority()
	if _channels_authority_poll_active:
		_arm_channels_authority_poll_at(_channels_next_authority_poll_tick())


func _evaluate_channels_streaming_endpoints() -> void:
	match _current_step:
		"channels_to_memory":
			if _channels_full_conscious_party_past_x(CHANNELS_MEMORY_TRIGGER_X):
				_start_channels_memory()
		"channels_to_flure":
			if _channels_full_conscious_party_past_x(CHANNELS_FLURE_TRIGGER_X):
				_start_channels_flure()
		"channels_to_encounter":
			if _channels_full_conscious_party_past_x(CHANNELS_ENCOUNTER_TRIGGER_X):
				_start_channels_encounter_intro()
		"channels_explore":
			if _channels_full_conscious_party_past_x(CHANNELS_END.x - 5.0):
				_start_stacks_enter()

# --- Step functions ---

func _get_character_node(id: String) -> CharacterBody3D:
	match id:
		"aster":
			return _aster_node
		"peris":
			return _peris_node
		"endo":
			return _endo
		_:
			return null

func _set_interactable_active_character(id: String) -> void:
	for node in find_children("*", "", true, false):
		if node.has_signal("interacted") and node.has_method("get_dwell_progress"):
			node.set("active_character", id)

func _select_character(id: String, preserve_authoritative_movement := false) -> void:
	if id == "endo" and (_rings_endo_phase != RINGS_ENDO_PHASE_PRESENT \
			or _game_state == null or not _game_state.characters.has("endo")):
		return
	var next := _get_character_node(id)
	if next == null:
		return
	for cid in ["aster", "peris", "endo"]:
		var node := _get_character_node(cid)
		if node:
			if preserve_authoritative_movement:
				# Loading a portrait is presentation attachment, not a new stop command. The ordinary
				# setter intentionally cancels movement when disabling input, which would erase saved
				# in-flight formations for the two unselected bodies during snapshot restoration.
				node.restore_move_input_enabled(cid == id)
			else:
				node.set_move_enabled(cid == id)
	_player = next
	_active_character = id
	_set_interactable_active_character(id)
	match id:
		"aster":
			_focus_aster_view()
		"peris":
			_focus_peris_view()
		"endo":
			_focus_endo_view()

func _focus_aster_view() -> void:
	if _camera:
		_camera.target = _aster_node
	_apply_overlay_visibility()

func _focus_peris_view() -> void:
	if _camera:
		_camera.target = _peris_node
	_apply_overlay_visibility()

func _focus_endo_view() -> void:
	if _camera:
		_camera.target = _endo
	_apply_overlay_visibility()

func _build_overlay_ui() -> void:
	_overlay_ui = preload("res://scenes/ui/perception_overlay.tscn").instantiate()
	_overlay_ui.name = "Act1OverlayUI"
	add_child(_overlay_ui)
	_overlay_note_label = _overlay_ui.get_node("Margin/Panel/Content/NoteLabel") as Label
	_overlay_status_label = _overlay_ui.get_node("Margin/Panel/Content/StatusLabel") as Label
	_bind_overlay_button(
		_overlay_ui.get_node("Margin/Panel/Content/Buttons/AsterOverlayButton") as Button,
		"aster", Color(0.29, 0.62, 1.0))
	_bind_overlay_button(
		_overlay_ui.get_node("Margin/Panel/Content/Buttons/PerisOverlayButton") as Button,
		"peris", Color(1.0, 0.67, 0.27))
	_update_overlay_status({})

func _bind_overlay_button(button: Button, overlay_id: String, color: Color) -> void:
	button.pressed.connect(_toggle_overlay.bind(overlay_id))
	_overlay_buttons[overlay_id] = {
		"button": button,
		"color": color,
	}
	_refresh_overlay_button(overlay_id)

func _toggle_overlay(overlay_id: String) -> void:
	if not _overlay_states.has(overlay_id):
		return
	_overlay_states[overlay_id] = not bool(_overlay_states[overlay_id])
	_refresh_overlay_button(overlay_id)
	_apply_overlay_visibility()
	_show_overlay_note("%s overlay %s" % [overlay_id.capitalize(), "ON" if bool(_overlay_states[overlay_id]) else "OFF"])

func _refresh_overlay_button(overlay_id: String) -> void:
	if not _overlay_buttons.has(overlay_id):
		return
	var info: Dictionary = _overlay_buttons[overlay_id]
	var button: Button = info.get("button")
	var color: Color = info.get("color", Color.WHITE)
	var enabled := bool(_overlay_states.get(overlay_id, false))
	var normal: StyleBoxFlat = button.get_theme_stylebox("normal")
	var hover: StyleBoxFlat = button.get_theme_stylebox("hover")
	var pressed: StyleBoxFlat = button.get_theme_stylebox("pressed")
	if enabled:
		normal.bg_color = Color(color, 0.18)
		normal.border_color = Color(color, 0.7)
		hover.bg_color = Color(color, 0.24)
		hover.border_color = Color(color, 0.85)
		pressed.bg_color = Color(color, 0.32)
		pressed.border_color = Color(color, 0.95)
		button.add_theme_color_override("font_color", Color(color, 0.95))
	else:
		normal.bg_color = Color(0.06, 0.06, 0.08, 0.9)
		normal.border_color = Color(color, 0.28)
		hover.bg_color = Color(0.08, 0.08, 0.1, 0.95)
		hover.border_color = Color(color, 0.45)
		pressed.bg_color = Color(0.11, 0.11, 0.13, 0.95)
		pressed.border_color = Color(color, 0.55)
		button.add_theme_color_override("font_color", Color(color, 0.6))

func _show_overlay_note(text: String, duration := 2.2) -> void:
	if _overlay_note_label == null:
		return
	_overlay_note_label.text = text
	_overlay_note_label.modulate.a = 0.95
	_overlay_note_timer = duration

func _update_overlay_note(delta: float) -> void:
	if _overlay_note_timer <= 0.0 or _overlay_note_label == null:
		return
	_overlay_note_timer = maxf(0.0, _overlay_note_timer - delta)
	if _overlay_note_timer <= 0.0:
		_overlay_note_label.modulate.a = 0.0

func _apply_overlay_visibility() -> void:
	if bool(_overlay_states.get("aster", false)):
		_setup_perception("data", _aster_node)
	else:
		if _perception_quad:
			_perception_quad.visible = false

func _update_overlay_status(snapshot: Dictionary) -> void:
	if _overlay_status_label == null:
		return
	var lines: Array[String] = [
		"Aster data: %s" % ("ON" if bool(_overlay_states.get("aster", false)) else "OFF"),
		"Peris flora: %s" % ("ON" if bool(_overlay_states.get("peris", false)) else "OFF"),
	]
	if bool(_overlay_states.get("peris", false)):
		if snapshot.is_empty():
			lines.append("")
			lines.append("Peris flora network is idle.")
		else:
			var relational: Dictionary = snapshot.get("relational", {})
			var words: Dictionary = snapshot.get("layer_words", {})
			lines.append("")
			lines.append("Network: %s" % ("bright" if bool(snapshot.get("window_active", false)) else "dormant"))
			if bool(snapshot.get("window_active", false)):
				lines.append("Read window: %.0fs" % float(snapshot.get("time_remaining", 0.0)))
			lines.append("Species: %s" % str(words.get("species", "clear")))
			lines.append("Health: %s" % str(words.get("health", "steady")))
			lines.append("Context: %s" % str(words.get("context", "readable")))
			lines.append("Direction: %s" % str(words.get("direction", "precise")))
			lines.append("Memory: %s" % str(words.get("memory", "anchored")))
			var scent := str(relational.get("scent", "none"))
			if scent == "none":
				lines.append("Forget-me-nots: scentless")
			elif scent == "flicker":
				lines.append("Forget-me-nots: flicker")
			else:
				lines.append("Forget-me-nots: %s" % scent)
	else:
		lines.append("")
		lines.append("Peris overlay hidden.")
	_overlay_status_label.text = "\n".join(lines)

func _update_flora_system() -> void:
	var current_tick := _scheduler.get_current_tick()
	var zone := _current_flora_zone()
	_flora_system.set_stage(_current_flora_stage())

	if zone != "":
		for node_id in _flora_nodes.keys():
			var info: Dictionary = _flora_nodes[node_id]
			if str(info.get("zone", "")) != zone:
				continue
			var pos: Vector3 = info.get("position", Vector3.ZERO)
			if _peris_node and _peris_node.visible and _peris_node.global_position.distance_to(pos) <= FLORA_SMELL_RADIUS:
				if _flora_system.can_activate_node(node_id, current_tick):
					var read := _flora_system.start_read(node_id, current_tick)
					if bool(read.get("started", false)):
						_show_overlay_note(str(read.get("message", "")))

	var snapshot := _flora_system.get_overlay_snapshot(current_tick, zone)
	_update_overlay_status(snapshot)
	_update_flora_markers(snapshot)

func _update_flora_markers(snapshot: Dictionary) -> void:
	for marker_id in _flora_marker_nodes.keys():
		var marker: Label3D = _flora_marker_nodes[marker_id]
		if marker:
			marker.visible = false

	if not bool(_overlay_states.get("peris", false)):
		return

	var clues: Array = snapshot.get("visible_clues", [])
	for clue_data in clues:
		var clue: Dictionary = clue_data
		var marker := _get_flora_marker(str(clue.get("id", "")))
		var signal_type := str(clue.get("signal_type", "memory"))
		var certainty := float(clue.get("certainty", 0.6))
		marker.position = clue.get("display_pos", Vector3.ZERO) + Vector3(0.0, 2.2, 0.0)
		marker.text = str(clue.get("signal_label", "")).to_upper()
		marker.modulate = Color(_flora_signal_color(signal_type), 0.2 + certainty * 0.75)
		marker.visible = true

func _get_flora_marker(id: String) -> Label3D:
	if _flora_marker_nodes.has(id):
		return _flora_marker_nodes[id]
	var marker := Label3D.new()
	marker.name = "FloraMarker_%s" % id
	marker.font_size = 28
	marker.pixel_size = 0.008
	marker.outline_modulate = Color(0.0, 0.0, 0.0, 0.45)
	marker.outline_size = 8
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.visible = false
	_flora_overlay_root.add_child(marker)
	_flora_marker_nodes[id] = marker
	return marker

func _flora_signal_color(signal_type: String) -> Color:
	match signal_type:
		"threat":
			return Color(0.92, 0.46, 0.32)
		"hazard", "iron":
			return Color(0.94, 0.64, 0.28)
		"resource", "cache":
			return Color(0.56, 0.84, 0.56)
		"relationship":
			return Color(0.6, 0.76, 0.95)
		_:
			return Color(1.0, 0.77, 0.42)

func _current_flora_zone() -> String:
	if _current_step.begins_with("channels"):
		return "channels"
	if _current_step.begins_with("stacks"):
		return "stacks"
	if _current_step.begins_with("rings"):
		return "rings"
	return ""

func _current_flora_stage() -> int:
	if _current_step.begins_with("channels"):
		return FloraMemorySystem.Stage.EARLY
	if _current_step.begins_with("stacks"):
		return FloraMemorySystem.Stage.MID
	if _current_step in ["rings_enter", "rings_client"]:
		return FloraMemorySystem.Stage.LATE_MID
	if _current_step.begins_with("rings") or _current_step.begins_with("lockout"):
		return FloraMemorySystem.Stage.LATE
	return FloraMemorySystem.Stage.EARLY

func get_capture_context() -> Dictionary:
	var zone_label := _capture_zone_label()
	var sub_location := _humanize_capture_token(_current_step)
	return {
		"scene_path": scene_file_path,
		"scene_name": "Act 1",
		"act": 1,
		"day": 1,
		"time_of_day": "",
		"timestamp_label": "Act 1 / Day 1",
		"location": zone_label,
		"sub_location": sub_location,
		"trigger_type": "manual",
		"trigger_context": _current_step if _current_step != "" else "manual_capture",
		"position": _player.global_position if _player != null else Vector3.ZERO,
		"caption": "%s, Day 1" % zone_label,
	}

func build_save_snapshot() -> Dictionary:
	var snapshot := super.build_save_snapshot()
	snapshot["act1_presenters"] = {
		"version": 1,
		"active_chunks": _active_act1_snapshot_chunk_ids(),
		"endo_junction_active": _endo_junction_active,
		"lockout_chase_active": _lockout_chase_active,
		"lockout_rejection_presented": _lockout_rejection_presented,
		"lockout_dispatch_presented": _lockout_dispatch_presented,
	}
	snapshot["act1"] = {
		"active_character": _active_character,
		"overlay_states": _overlay_states.duplicate(true),
		"channels_state": {
			"optional_findings": _channels_optional_findings.duplicate(true),
		},
		"stacks_state": {
			"support_log_entry_id": _stacks_support_log_entry_id,
			"support_log_presented": _stacks_support_log_presented,
			"signal_interacted": _stacks_signal_interacted,
			"terminal_interacted": _stacks_terminal_interacted,
			"archive_interacted": _stacks_archive_interacted,
			"audit_flags_found": _stacks_audit_flags_found,
			"bank_samples": _stacks_bank_samples.keys(),
			"bank_resolved": _stacks_bank_resolved,
			"bank_attempts": _stacks_bank_attempts,
			"last_commit": _stacks_last_commit,
			"failed_commits": _stacks_failed_commits.duplicate(),
			"anxiety_seen": _stacks_anxiety_seen,
			"rest_phase": _stacks_rest_phase,
		},
		"rings_state": {
			"trace_seen": _rings_trace_seen.duplicate(true),
		},
	}
	return snapshot

func apply_save_snapshot(data: Dictionary) -> void:
	# Chunk roots create the Enemy, Flure, gate, and traversal presenters that attach to GameState.
	# Rebuild the saved topology before deserializing it so fresh loads and same-node rollbacks both
	# replace construction defaults with the snapshot instead of retaining the discarded level.
	var presenter_v: Variant = data.get("act1_presenters", {})
	_pending_act1_campaign_presenters = (
		(presenter_v as Dictionary).duplicate(true)
		if presenter_v is Dictionary else {})
	_prepare_act1_chunks_for_snapshot(data)
	super.apply_save_snapshot(data)
	var act1_data: Dictionary = data.get("act1", {})
	if act1_data.has("overlay_states"):
		_overlay_states = act1_data.get("overlay_states", {}).duplicate(true)
		for overlay_id in _overlay_buttons.keys():
			_refresh_overlay_button(overlay_id)
		_apply_overlay_visibility()
	var active_character := str(act1_data.get("active_character", _active_character))
	if active_character != "":
		_select_character(active_character, true)
	# Accept the channels_fieldwork key only to preserve optional findings in old saves.
	var channels_state: Dictionary = act1_data.get(
		"channels_state", act1_data.get("channels_fieldwork", {}))
	_channels_optional_findings = channels_state.get(
		"optional_findings", _channels_optional_findings).duplicate(true)
	# HP is owned by the shared GameState snapshot. Read legacy scene-local HP only
	# when loading an old save that carried it outside the authoritative state.
	if channels_state.has("aster_hp") and _game_state != null and _game_state.characters.has("aster"):
		_game_state.set_stat("aster", "hp", float(channels_state.get("aster_hp", _game_state.get_stat("aster", "hp"))))
	if channels_state.has("peris_hp") and _game_state != null and _game_state.characters.has("peris"):
		_game_state.set_stat("peris", "hp", float(channels_state.get("peris_hp", _game_state.get_stat("peris", "hp"))))
	_aster_hp = _game_state.get_stat("aster", "hp") if _game_state != null and _game_state.characters.has("aster") else _aster_hp
	_peris_hp = _game_state.get_stat("peris", "hp") if _game_state != null and _game_state.characters.has("peris") else _peris_hp
	_restore_channels_optional_interactables()
	var stacks_state: Dictionary = act1_data.get("stacks_state", {})
	_stacks_support_log_entry_id = int(stacks_state.get("support_log_entry_id", _stacks_support_log_entry_id))
	_stacks_support_log_presented = bool(stacks_state.get("support_log_presented", _stacks_support_log_presented))
	_stacks_signal_interacted = bool(stacks_state.get("signal_interacted", _stacks_signal_interacted))
	_stacks_terminal_interacted = bool(stacks_state.get("terminal_interacted", _stacks_terminal_interacted))
	_stacks_archive_interacted = bool(stacks_state.get("archive_interacted", _stacks_archive_interacted))
	_stacks_audit_flags_found = bool(stacks_state.get("audit_flags_found", _stacks_audit_flags_found))
	_stacks_bank_samples.clear()
	for bank_id in stacks_state.get("bank_samples", []):
		_stacks_bank_samples[str(bank_id)] = true
	_stacks_bank_resolved = bool(stacks_state.get("bank_resolved", _stacks_bank_resolved))
	_stacks_bank_attempts = int(stacks_state.get("bank_attempts", _stacks_bank_attempts))
	_stacks_last_commit = str(stacks_state.get("last_commit", _stacks_last_commit))
	_stacks_failed_commits.clear()
	for bank_id in stacks_state.get("failed_commits", []):
		_stacks_failed_commits.append(str(bank_id))
	_stacks_anxiety_seen = bool(stacks_state.get("anxiety_seen", _stacks_anxiety_seen))
	_restore_stacks_bank_interactables()
	_restore_stacks_optional_interactables()
	_apply_act1_stacks_rest_presentation()
	_apply_channels_shelter_rest_presentation()
	var rings_state: Dictionary = act1_data.get("rings_state", {})
	_rings_trace_seen = rings_state.get("trace_seen", _rings_trace_seen).duplicate(true)
	_apply_rings_departure_interactable_state()
	_restore_rings_trace_interactables()
	if _rings_endo_phase == RINGS_ENDO_PHASE_DEPARTING and _player != null:
		_player.set_move_enabled(false)
	_restore_act1_campaign_presenter_links(str(data.get("current_step", "")), false)
	_pending_act1_campaign_presenters.clear()


func _prepare_act1_chunks_for_snapshot(data: Dictionary) -> void:
	var saved_step := str(data.get("current_step", ""))
	var required := _saved_act1_snapshot_chunk_ids(data, saved_step)
	# Chunk roots can already be gone while their runtime dictionaries still hold freed presenters.
	# Clear that causal/presentation cache before GameState broadcasts the restored authority.
	if not required.has("channels") and (
			_chunks.has("channels")
			or _channels_kit_active
			or _channels_flures_bound
			or not _channels_window_lanes.is_empty()
			or not _channels_channel_entries.is_empty()
			or not _channels_enemy_by_id.is_empty()):
		_clear_channels_runtime_state()
	for chunk_name in ACT1_SNAPSHOT_CHUNKS:
		if not required.has(chunk_name) and _chunks.has(chunk_name):
			_unload_chunk(chunk_name)
	for chunk_name in required:
		_load_chunk(chunk_name)
	_activate_saved_act1_grid(required)
	_restore_act1_campaign_presenter_links(saved_step, true)


func _saved_act1_snapshot_chunk_ids(
		data: Dictionary, saved_step: String) -> Array[String]:
	var result: Array[String] = []
	var presenter_v: Variant = data.get("act1_presenters", {})
	if presenter_v is Dictionary and int(presenter_v.get("version", 0)) == 1:
		for chunk_name_v in presenter_v.get("active_chunks", []):
			var chunk_name := str(chunk_name_v)
			if chunk_name in ACT1_SNAPSHOT_CHUNKS and not result.has(chunk_name):
				result.append(chunk_name)
	else:
		# Backward-compatible topology for saves made before presenter membership was recorded.
		if saved_step.begins_with("channels"):
			result.append("channels")
		elif saved_step.begins_with("stacks"):
			result.append("stacks")
		elif saved_step.begins_with("rings") or saved_step == "endo_departs":
			result.append("rings")
		elif saved_step.begins_with("lockout"):
			result.append("lockout_chase_campaign")
		elif saved_step == "endo_junction_stretch":
			result.append("endo_junction_stretch")
	return result


func _active_act1_snapshot_chunk_ids() -> Array[String]:
	var active: Array[String] = []
	for chunk_name in ACT1_SNAPSHOT_CHUNKS:
		var chunk: Node3D = _chunks.get(chunk_name) as Node3D
		if chunk == null or not is_instance_valid(chunk) or chunk.is_queued_for_deletion():
			continue
		if chunk.visible and chunk.process_mode != Node.PROCESS_MODE_DISABLED:
			active.append(chunk_name)
	return active


func _activate_saved_act1_grid(required: Array[String]) -> void:
	if required.has("endo_junction_stretch"):
		_activate_hosted_chunk_grid(_chunks.get("endo_junction_stretch"))
		return
	if required.has("lockout_chase_campaign"):
		_activate_hosted_chunk_grid(_chunks.get("lockout_chase_campaign"))
		return
	for chunk_name in ["rings", "stacks", "channels", "lockout"]:
		if not required.has(chunk_name):
			continue
		_activate_chunk_grid(chunk_name)
		if chunk_name == "channels":
			# Snapshot preparation creates a new GridWorld. Rebind the persistent physical gate before
			# GameState replacement so its closed/open topology is projected onto that exact grid.
			_setup_channels_shortcut_gate()
			_apply_channels_grid_occluders()
			_activate_channels_kit()
		return


func _restore_act1_campaign_presenter_links(
		saved_step: String, before_snapshot_restore: bool) -> void:
	_endo_junction_chunk = _chunks.get("endo_junction_stretch") as Node3D
	_lockout_chase_chunk = _chunks.get("lockout_chase_campaign") as Node3D
	var has_saved_flags := int(_pending_act1_campaign_presenters.get("version", 0)) == 1
	_endo_junction_active = is_instance_valid(_endo_junction_chunk) and (
		bool(_pending_act1_campaign_presenters.get("endo_junction_active", false))
		if has_saved_flags else saved_step != "endo_junction_stretch_complete")
	_lockout_chase_active = is_instance_valid(_lockout_chase_chunk) and (
		bool(_pending_act1_campaign_presenters.get("lockout_chase_active", false))
		if has_saved_flags else saved_step not in ["lockout_exile", "complete"])
	_lockout_rejection_presented = bool(_pending_act1_campaign_presenters.get(
		"lockout_rejection_presented", false)) if has_saved_flags else saved_step in [
		"lockout_rejected", "lockout_chase", "lockout_exile", "complete",
	]
	_lockout_dispatch_presented = bool(_pending_act1_campaign_presenters.get(
		"lockout_dispatch_presented", false)) if has_saved_flags else saved_step in [
		"lockout_chase", "lockout_exile", "complete",
	]
	if not is_instance_valid(_lockout_chase_chunk):
		return
	var rejection_callback := Callable(self, "_on_campaign_lockout_tags_rejected")
	if _lockout_chase_chunk.has_signal("tags_rejected") \
			and not _lockout_chase_chunk.is_connected("tags_rejected", rejection_callback):
		_lockout_chase_chunk.connect("tags_rejected", rejection_callback)
	# This pre-load configuration is only a construction default. GameState.deserialize replaces its
	# published value, and the chunk's restore hook then mirrors the exact saved pursuit authority.
	if before_snapshot_restore and _lockout_chase_chunk.has_method("set_pursuit_start_deferred"):
		_lockout_chase_chunk.call(
			"set_pursuit_start_deferred", saved_step != "lockout_chase")

func _capture_zone_label() -> String:
	if _current_step.begins_with("channels"):
		return "Plumbing Power Project"
	if _current_step.begins_with("stacks"):
		return "The Open Files Initiative"
	if _current_step.begins_with("rings"):
		return "Greenfields Collective"
	if _current_step.begins_with("lockout"):
		return "Lockout Corridor"
	return "Act 1"

func _add_flora_node(parent: Node3D, id: String, species: String, zone: String, pos: Vector3, signal_type: String, signal_label: String, signal_pos: Vector3, color: Color, relationship_strength := 0.55, extra: Dictionary = {}) -> void:
	var root := Node3D.new()
	root.name = "Flora_%s" % id
	root.position = pos
	parent.add_child(root)

	for i in range(3):
		var stem := MeshInstance3D.new()
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.03
		stem_mesh.bottom_radius = 0.05
		stem_mesh.height = 0.42 + float(i) * 0.08
		stem.mesh = stem_mesh
		var stem_mat := StandardMaterial3D.new()
		stem_mat.albedo_color = color.darkened(0.45)
		stem.material_override = stem_mat
		stem.position = Vector3(-0.18 + float(i) * 0.18, 0.2, -0.05 + sin(float(i)) * 0.08)
		root.add_child(stem)

		var bloom := MeshInstance3D.new()
		var bloom_mesh := SphereMesh.new()
		bloom_mesh.radius = 0.11 + float(i) * 0.015
		bloom_mesh.height = 0.22 + float(i) * 0.03
		bloom.mesh = bloom_mesh
		var bloom_mat := StandardMaterial3D.new()
		bloom_mat.albedo_color = color
		bloom_mat.emission_enabled = true
		bloom_mat.emission = color
		bloom_mat.emission_energy_multiplier = 0.25
		bloom.material_override = bloom_mat
		bloom.position = Vector3(-0.18 + float(i) * 0.18, 0.48 + float(i) * 0.09, -0.05 + sin(float(i)) * 0.08)
		root.add_child(bloom)

	_flora_nodes[id] = {
		"zone": zone,
		"position": pos,
		"node": root,
	}
	_flora_system.register_node(id, {
		"species": species,
		"zone": zone,
		"position": pos,
		"signal_type": signal_type,
		"signal_label": signal_label,
		"signal_pos": signal_pos,
		"relationship_strength": relationship_strength,
		"tended": bool(extra.get("tended", false)),
		"childhood_species": bool(extra.get("childhood_species", false)),
		"role": str(extra.get("role", "sensor")),
		"forget_me_not": bool(extra.get("forget_me_not", false)),
	})

func _channels_resolve_formation_destination(char_id: String, requested: Vector3) -> Vector3:
	if _game_state != null and _game_state.grid != null:
		return _game_state.grid.nearest_walkable_world(
			requested, 3, _game_state.get_character_level(char_id))
	return requested


func _valid_channels_position_data(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 3:
		return false
	for coordinate in value as Array:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT]:
			return false
	return true


func _channels_position_to_data(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _channels_position_from_data(value: Variant) -> Vector3:
	if not _valid_channels_position_data(value):
		return Vector3.INF
	var coordinates := value as Array
	return Vector3(
		float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))


func _channels_character_at_formation_endpoint(
		char_id: String, destination: Vector3
	) -> bool:
	if _game_state == null or not _game_state.characters.has(char_id) \
			or _game_state.is_downed(char_id) or destination == Vector3.INF:
		return false
	var current := _game_state.get_position(char_id)
	if current.distance_to(destination) <= CHANNELS_FORMATION_ENDPOINT_EPSILON:
		return true
	if _game_state.grid == null:
		return false
	return _game_state.grid.world_to_grid(current) \
		== _game_state.grid.world_to_grid(destination) \
		and _game_state.get_character_level(char_id) \
		== _game_state.grid.level_for_y(destination.y)


func _channels_formation_blocking_reason(destinations: Dictionary) -> String:
	if _game_state == null or _scheduler == null:
		return "missing_authority"
	for char_id in CHANNELS_PARTY_IDS:
		if not destinations.has(char_id):
			return "missing_destination:%s" % char_id
		if not _game_state.characters.has(char_id):
			return "missing_character:%s" % char_id
		if _game_state.is_downed(char_id):
			return "downed_character:%s" % char_id
		if not _game_state.can_accept_move_command(char_id):
			return "movement_unavailable:%s" % char_id
	return ""


func _move_party_and_continue(destinations: Dictionary, tag: String) -> bool:
	var resolved_destinations := {}
	var destination_data := {}
	for char_id in CHANNELS_PARTY_IDS:
		if destinations.has(char_id):
			resolved_destinations[char_id] = _channels_resolve_formation_destination(
				char_id, destinations[char_id])
			destination_data[char_id] = _channels_position_to_data(
				resolved_destinations[char_id])
	var reason := _channels_formation_blocking_reason(resolved_destinations)
	var start_tick := float(_scheduler.get_current_tick()) if _scheduler != null else -1.0
	_channels_formation_authority = {
		"phase": "interrupted",
		"operation_id": "%s@%.6f" % [tag, start_tick],
		"tag": tag,
		"required_ids": CHANNELS_PARTY_IDS.duplicate(),
		"accepted_ids": [],
		"already_at_endpoint_ids": [],
		"destinations": destination_data.duplicate(true),
		"start_tick": start_tick,
		"reason": reason,
	}
	if not reason.is_empty():
		_publish_channels_runtime_authority()
		_on_channels_formation_interrupted(reason)
		return false

	var accepted_ids: Array[String] = []
	var already_at_endpoint_ids: Array[String] = []
	for char_id in CHANNELS_PARTY_IDS:
		if _channels_character_at_formation_endpoint(
				char_id, resolved_destinations[char_id]):
			accepted_ids.append(char_id)
			already_at_endpoint_ids.append(char_id)
			continue
		var accepted := _game_state.command_move_to_pos(
			char_id, resolved_destinations[char_id])
		if not accepted:
			reason = "command_rejected:%s" % char_id
			break
		accepted_ids.append(char_id)
		var committed_destination := _game_state.get_destination(char_id)
		if committed_destination != Vector3.INF:
			resolved_destinations[char_id] = committed_destination
			destination_data[char_id] = _channels_position_to_data(committed_destination)

	_channels_formation_authority["accepted_ids"] = accepted_ids
	_channels_formation_authority["already_at_endpoint_ids"] = already_at_endpoint_ids
	_channels_formation_authority["destinations"] = destination_data
	if not reason.is_empty():
		_channels_formation_authority["phase"] = "interrupted"
		_channels_formation_authority["reason"] = reason
		for accepted_id in accepted_ids:
			_game_state.command_stop(accepted_id)
		_publish_channels_runtime_authority()
		_on_channels_formation_interrupted(reason)
		return false
	_channels_formation_authority["phase"] = "moving"
	_publish_channels_runtime_authority()
	_evaluate_channels_formation()
	return true


func _channels_formation_at_endpoints() -> bool:
	if _game_state == null:
		return false
	var required_ids: Array = _channels_formation_authority.get("required_ids", [])
	var destinations: Dictionary = _channels_formation_authority.get("destinations", {})
	if required_ids.is_empty() or destinations.is_empty():
		return false
	for char_id_variant in required_ids:
		var char_id := str(char_id_variant)
		if not destinations.has(char_id) or not _game_state.characters.has(char_id) \
				or _game_state.is_downed(char_id):
			return false
		var destination := _channels_position_from_data(destinations[char_id])
		if destination == Vector3.INF:
			return false
		if not _channels_character_at_formation_endpoint(char_id, destination):
			return false
	return true


func _channels_formation_all_commands_accepted() -> bool:
	var required_ids: Array = _channels_formation_authority.get("required_ids", [])
	var accepted_ids: Array = _channels_formation_authority.get("accepted_ids", [])
	if required_ids.size() != CHANNELS_PARTY_IDS.size() \
			or accepted_ids.size() != required_ids.size():
		return false
	for char_id in CHANNELS_PARTY_IDS:
		if not required_ids.has(char_id) or not accepted_ids.has(char_id):
			return false
	return true


func _channels_formation_moves_still_match() -> bool:
	if _game_state == null:
		return false
	var required_ids: Array = _channels_formation_authority.get("required_ids", [])
	var destinations: Dictionary = _channels_formation_authority.get("destinations", {})
	for char_id_variant in required_ids:
		var char_id := str(char_id_variant)
		if not _game_state.characters.has(char_id) or _game_state.is_downed(char_id) \
				or not destinations.has(char_id):
			return false
		var expected := _channels_position_from_data(destinations[char_id])
		if expected == Vector3.INF:
			return false
		if _channels_character_at_formation_endpoint(char_id, expected):
			continue
		if not _game_state.is_moving(char_id):
			return false
		var committed := _game_state.get_destination(char_id)
		if committed == Vector3.INF \
				or committed.distance_to(expected) > CHANNELS_FORMATION_ENDPOINT_EPSILON:
			return false
	return true


func _on_channels_character_arrived(char_id: String) -> void:
	if str(_channels_formation_authority.get("phase", "idle")) != "moving":
		return
	if not (_channels_formation_authority.get("required_ids", []) as Array).has(char_id):
		return
	_evaluate_channels_formation()


func _arm_channels_formation_poll() -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(CHANNELS_FORMATION_POLL_TAG)
	_scheduler.schedule_after(
		CHANNELS_FORMATION_POLL_INTERVAL,
		_evaluate_channels_formation,
		CHANNELS_FORMATION_POLL_TAG)


func _evaluate_channels_formation() -> void:
	var phase := str(_channels_formation_authority.get("phase", "idle"))
	if phase != "moving":
		return
	if _channels_formation_all_commands_accepted() \
			and _channels_formation_at_endpoints():
		var tag := str(_channels_formation_authority.get("tag", ""))
		_channels_formation_authority["phase"] = "completed"
		_channels_formation_authority["reason"] = ""
		_publish_channels_runtime_authority()
		if _scheduler != null:
			_scheduler.cancel_tag(CHANNELS_FORMATION_POLL_TAG)
		_continue_channels_formation(tag)
		return
	if not _channels_formation_moves_still_match():
		_channels_formation_authority["phase"] = "interrupted"
		_channels_formation_authority["reason"] = "movement_replaced_or_stopped"
		_publish_channels_runtime_authority()
		_on_channels_formation_interrupted("movement_replaced_or_stopped")
		return
	_arm_channels_formation_poll()


func _on_channels_formation_interrupted(reason: String) -> void:
	if _scheduler != null:
		_scheduler.cancel_tag(CHANNELS_FORMATION_POLL_TAG)
	if _player != null:
		_player.set_move_enabled(true)
	if _tutorial_prompt != null:
		_tutorial_prompt.show_prompt(
			"Regroup the whole conscious party at the marked formation (%s)" % reason)


func _continue_channels_formation(tag: String) -> void:
	match tag:
		"channels_memory_move":
			_on_channels_memory_party_arrived()
		"channels_window_one_intro_move":
			_on_channels_window_intro_party_arrived("window_one")
		"channels_window_two_intro_move":
			_on_channels_window_intro_party_arrived("window_two")
		"channels_window_one_reset_move":
			_begin_channels_window_lane("window_one")
		"channels_window_two_reset_move":
			_begin_channels_window_lane("window_two")
		"channels_flure_move":
			_on_channels_flure_party_arrived()
		"channels_encounter_intro_move", "channels_encounter_reset_move":
			_begin_channels_encounter()
		"channels_shelter_move":
			_on_channels_shelter_party_arrived()

func _bind_channels_optional_sites_to_game_state() -> void:
	# Optional worldbuilding uses the same authoritative interaction layer as the
	# causal core, but it never gates progression.
	if _game_state == null:
		return
	for site_id_variant in _channels_optional_sites.keys():
		var site_id := str(site_id_variant)
		var site = _channels_optional_sites[site_id]
		var spec: Dictionary = CHANNELS_OPTIONAL_SITES.get(site_id, {})
		if not is_instance_valid(site) or spec.is_empty():
			continue
		var data_id := "ChannelsOptional_%s" % site_id
		_game_state.register_interactable({
			"id": data_id,
			"position": spec.get("pos", Vector3.ZERO),
			"radius": 1.7,
			"hold_time": float(spec.get("dwell", 0.0)),
			"one_shot": true,
			"requires_hold": false,
			"required_character": str(spec.get("role", "")),
			"tutorial_label": str(spec.get("verb", "INSPECT")),
			"enabled": false,
		})
		site.bind_data(_game_state, data_id)
		site.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
		site.set("required_character", str(spec.get("role", "")))
		site.set_interaction_enabled(false)
		if site.has_method("set_movement_authority"):
			site.set_movement_authority(_game_state)

func _reset_channels_optional_state() -> void:
	for character in [_aster_node, _peris_node, _endo]:
		if is_instance_valid(character) and character.has_method("cancel_interaction_target"):
			character.cancel_interaction_target()
	_channels_optional_findings.clear()
	for site in _channels_optional_sites.values():
		if not is_instance_valid(site):
			continue
		site.reset()
		site.set_interaction_enabled(false)
		site.hide_tutorial_label()
	for visual in _channels_optional_visuals.values():
		if is_instance_valid(visual):
			visual.visible = false

func _restore_channels_optional_interactables() -> void:
	for site in _channels_optional_sites.values():
		if is_instance_valid(site):
			site.set_interaction_enabled(false)
			site.hide_tutorial_label()
	for visual in _channels_optional_visuals.values():
		if is_instance_valid(visual):
			visual.visible = false
	if _current_step == "channels_explore":
		_enable_channels_optional_exploration()

func _set_channels_optional_site_enabled(site_id: String, enabled: bool, reset_first := false) -> void:
	var site = _channels_optional_sites.get(site_id)
	if not is_instance_valid(site):
		return
	if reset_first:
		site.reset()
	if site.has_method("set_interaction_enabled"):
		site.set_interaction_enabled(enabled)
	var visual = _channels_optional_visuals.get(site_id)
	if is_instance_valid(visual):
		visual.visible = enabled
	if enabled:
		site.show_tutorial_label()
	else:
		site.hide_tutorial_label()

func _on_channels_optional_route_requested(
	_target: Node,
	world_position: Vector3,
	site_id: String
) -> void:
	if not CHANNELS_OPTIONAL_SITES.has(site_id) or _game_state == null:
		return
	var specialist := str(CHANNELS_OPTIONAL_SITES[site_id].get("role", ""))
	var offsets := {
		"aster": Vector3(-1.2, 0.0, -0.8),
		"peris": Vector3(-1.0, 0.0, 1.0),
		"endo": Vector3(1.1, 0.0, -0.6),
	}
	for char_id in ["aster", "peris", "endo"]:
		if char_id == specialist or not _game_state.characters.has(char_id):
			continue
		_game_state.command_move_to_pos(char_id, world_position + offsets[char_id])

func _on_channels_optional_site_interacted(site_id: String) -> void:
	if not CHANNELS_OPTIONAL_SITES.has(site_id) or _current_step != "channels_explore":
		return
	if bool(_channels_optional_findings.get(site_id, false)):
		return
	_channels_optional_findings[site_id] = true
	var spec: Dictionary = CHANNELS_OPTIONAL_SITES[site_id]
	_show_overlay_note(str(spec.get("finding", "The party records an optional field note.")), 4.2)
	_tutorial_prompt.show_prompt(
		"Optional Channels records %d/%d // continue to the Stacks when ready" % [
			_channels_optional_findings.size(), CHANNELS_OPTIONAL_SITES.size(),
		]
	)

func _enable_channels_optional_exploration() -> void:
	for site_id in CHANNELS_OPTIONAL_SITES.keys():
		if bool(_channels_optional_findings.get(site_id, false)):
			continue
		_set_channels_optional_site_enabled(str(site_id), true, true)

func _channels_optional_site_position(site_id: String) -> Vector3:
	if CHANNELS_OPTIONAL_SITES.has(site_id):
		return CHANNELS_OPTIONAL_SITES[site_id].get("pos", Vector3.ZERO)
	return Vector3.ZERO

func get_channels_playtime_contract() -> Dictionary:
	# This is intentionally a structural/mechanical measurement, not a claimed
	# first-clear duration. Deliberation, failed predictions, dialogue reading,
	# and route execution must be observed in playtests rather than fabricated.
	return {
		"contract_id": "channels_causal_core_measurement_v2",
		"measurement_kind": "causal_structure_not_first_clear_elapsed",
		"core_route_span_meters": CHANNELS_START.distance_to(CHANNELS_END),
		"window_count": 2,
		"window_safe_seconds": CHANNELS_WINDOW_ONE_DURATION + CHANNELS_WINDOW_TWO_DURATION,
		"encounter_lure_lifetime_seconds": CHANNELS_RUN_LURE_DURATION,
		"required_causal_beats": [
			"memory_at_body",
			"window_one_lure_and_flow",
			"flure_flush",
			"window_two_lure_and_flow",
			"lure_hide_run_encounter",
			"shelter_rest_and_shortcut",
		],
		"mandatory_checklist_operation_count": 0,
		"mandatory_checklist_action_count": 0,
		"optional_site_count": CHANNELS_OPTIONAL_SITES.size(),
		"timing_basis": "production geometry and mechanic constants only; no synthetic clue-reading or planning allowances",
	}


func _set_channels_flure_active(active: bool) -> void:
	if not is_instance_valid(_channels_flure):
		return
	_channels_flure.set_interaction_enabled(active)
	if active:
		_channels_flure.show_tutorial_label()
	else:
		_channels_flure.hide_tutorial_label()

func _set_channels_flow_power(power: float) -> void:
	_channels_flow_power = clampf(power, 0.0, 1.0)
	for strip in _channels_flow_strips:
		if strip == null:
			continue
		var mat := strip.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.1, 0.15, 0.2).lerp(Color(0.16, 0.24, 0.34), _channels_flow_power)
			mat.emission_energy_multiplier = lerpf(0.3, 1.35, _channels_flow_power)


## Act I composes reusable kit; it does not own another movement/combat/wash simulation.
## Construction specs may hold scene nodes, but no spec is saved. Stable IDs reconnect the
## Enemy/Flure/Channel presenters to their own portable GameState authority after load.
func _register_channels_enemy_spec(parent: Node3D, spec: Dictionary) -> void:
	var enemy_id := str(spec.get("id", ""))
	if enemy_id.is_empty() or not is_instance_valid(parent):
		return
	var stored := spec.duplicate(true)
	stored["parent"] = parent
	_channels_enemy_specs[enemy_id] = stored
	_channels_enemy_scope_by_id[enemy_id] = str(stored.get("scope", ""))


func _spawn_channels_enemy_presenter(enemy_id: String) -> Enemy:
	if _game_state == null or not _channels_enemy_specs.has(enemy_id):
		return null
	var spec: Dictionary = _channels_enemy_specs[enemy_id]
	var parent: Node3D = spec.get("parent")
	if not is_instance_valid(parent):
		return null
	var enemy: Enemy = EnemyScript.new()
	enemy.name = "ChannelsEnemy_%s" % enemy_id
	enemy.char_id = enemy_id
	enemy.game_state = _game_state
	enemy.move_speed = float(spec.get("move_speed", CHANNELS_WINDOW_SWARM_SPEED))
	enemy.pursuit_speed = maxf(enemy.move_speed, 3.6)
	enemy.detection_range = float(spec.get("detection_range", 4.0))
	enemy.color = spec.get("color", Color(0.52, 0.2, 0.06))
	enemy.pursuit_direct = true
	enemy.pursuit_hop = 4.5
	var already_registered := _game_state.characters.has(enemy_id)
	enemy.position = (
		_game_state.get_render_position(enemy_id)
		if already_registered else spec.get("position", Vector3.ZERO))
	parent.add_child(enemy)
	if not already_registered:
		_game_state.register_character(enemy_id, enemy.position, enemy.move_speed, {
			"detection_range": enemy.detection_range,
		})
	enemy.set_detection_targets(CHANNELS_PARTY_IDS)
	_channels_enemy_by_id[enemy_id] = enemy
	_game_state_character_nodes[enemy_id] = enemy
	enemy.target_spotted.connect(_on_channels_enemy_target_spotted.bind(enemy_id))
	enemy.hit_target.connect(_on_channels_enemy_hit_target.bind(enemy_id))
	enemy.activate()
	return enemy


func _add_channels_channel(
		parent: Node3D,
		tag: String,
		scope: String,
		x: float,
		half: float,
		z_half: float,
		period: float,
		duration: float,
		phase: float
	) -> Channel:
	var channel: Channel = ChannelScript.new()
	channel.name = "ChannelsChannel_%s" % tag
	channel.configure(x, half, z_half, period, duration, phase, tag)
	parent.add_child(channel)
	_channels_channel_entries.append({
		"node": channel,
		"tag": tag,
		"scope": scope,
	})
	return channel


func _activate_channels_kit() -> void:
	if _channels_kit_active or _game_state == null or _scheduler == null:
		return
	for char_id in CHANNELS_PARTY_IDS:
		if not _game_state.characters.has(char_id):
			return
	_bind_channels_flures_to_game_state()
	var enemy_ids := _channels_enemy_specs.keys()
	enemy_ids.sort()
	_game_state.begin_detection_update_batch()
	for enemy_id_v in enemy_ids:
		var enemy_id := str(enemy_id_v)
		if not is_instance_valid(_channels_enemy_by_id.get(enemy_id)):
			_spawn_channels_enemy_presenter(enemy_id)
	_game_state.end_detection_update_batch()
	for flure in _channels_flures():
		if is_instance_valid(flure):
			flure.set_enemy_resolver(_resolve_channels_enemy)
	for entry_v in _channels_channel_entries:
		_configure_channels_channel_entry(entry_v)
	_channels_kit_active = true


## Act I builds chunk geometry before TutorialSequence creates GameState. Flure's reusable contract
## requires that dependency at configure time, so attach it exactly once at the same lifecycle seam
## where Enemy and Channel presenters receive GameState. Later snapshot loads replace data inside the
## same GameState object and use each Flure's ordinary restore hook; they never reconfigure it.
func _bind_channels_flures_to_game_state() -> void:
	if _channels_flures_bound or _game_state == null:
		return
	if is_instance_valid(_channels_flure):
		_channels_flure.configure(
			_game_state, CHANNELS_FLURE_POS, _channels_flush_enemy_ids,
			42.0, 1.7, Color(0.32, 0.78, 0.45))
		_channels_flure.one_shot = false
		_channels_flure.interactable_type = Interactable.InteractableType.TIMED_ACTION
		_channels_flure.reset_flure()
	for window_id_v in _channels_window_lanes.keys():
		var window_id := str(window_id_v)
		var lane: Dictionary = _channels_window_lanes[window_id]
		var flure := _valid_channels_flure(lane)
		if not is_instance_valid(flure):
			continue
		flure.configure(
			_game_state,
			lane.get("lure_pos", Vector3.ZERO),
			lane.get("enemy_ids", []),
			48.0,
			1.7,
			Color(0.92, 0.5, 0.2))
		flure.one_shot = false
		flure.interactable_type = Interactable.InteractableType.TIMED_ACTION
		flure.reset_flure()
	if is_instance_valid(_channels_run_lure):
		_channels_run_lure.configure(
			_game_state, CHANNELS_RUN_LURE_POS, _channels_swarm_enemy_ids,
			44.0, 1.8, Color(0.9, 0.45, 0.18))
		_channels_run_lure.one_shot = false
		_channels_run_lure.interactable_type = Interactable.InteractableType.TIMED_ACTION
		_channels_run_lure.reset_flure()
	_channels_flures_bound = true


func _configure_channels_channel_entry(entry: Dictionary) -> void:
	var channel := _valid_channels_channel(entry)
	if not is_instance_valid(channel):
		return
	var scope := str(entry.get("scope", ""))
	channel.set_sweep(
		_game_state,
		CHANNELS_PARTY_IDS,
		_channels_channel_destination.bind(scope),
		{
			"party_hp": CHANNELS_CHANNEL_PARTY_BITE,
			"enemy_damage": CHANNELS_ENEMY_WASH_DAMAGE,
			"enemy_stun": 0.0,
			"refractory": CHANNELS_CHANNEL_REFRACTORY,
			"enemy_resolver": _resolve_channels_enemy_for_scope.bind(scope),
			"on_swept": _on_channels_party_swept.bind(scope),
			"on_enemy_swept": _on_channels_enemy_swept.bind(scope),
		}
	)
	channel.start(_scheduler, _game_state)


func _reset_channels_scope_kit(scope: String) -> void:
	var ids: Array = []
	for enemy_id_v in _channels_enemy_scope_by_id.keys():
		var enemy_id := str(enemy_id_v)
		if str(_channels_enemy_scope_by_id[enemy_id]) == scope:
			ids.append(enemy_id)
	ids.sort()
	for enemy_id_v in ids:
		var enemy_id := str(enemy_id_v)
		var enemy: Node = _channels_enemy_by_id.get(enemy_id)
		if is_instance_valid(enemy):
			enemy.free()
		_channels_enemy_by_id.erase(enemy_id)
		_game_state_character_nodes.erase(enemy_id)
		if _game_state.characters.has(enemy_id):
			_game_state.unregister_character(enemy_id)
		_game_state.set_world_state("runtime:enemy:%s" % enemy_id, null)
		_spawn_channels_enemy_presenter(enemy_id)
	for entry_v in _channels_channel_entries:
		var entry: Dictionary = entry_v
		if str(entry.get("scope", "")) != scope:
			continue
		var channel := _valid_channels_channel(entry)
		if is_instance_valid(channel):
			channel.reset()
			_configure_channels_channel_entry(entry)


func _deactivate_channels_kit(unregister_enemies: bool) -> void:
	for entry_v in _channels_channel_entries:
		var entry: Dictionary = entry_v
		var channel := _valid_channels_channel(entry)
		if is_instance_valid(channel):
			channel.reset()
	var ids := _channels_enemy_by_id.keys()
	for enemy_id_v in ids:
		var enemy_id := str(enemy_id_v)
		var enemy: Node = _channels_enemy_by_id.get(enemy_id)
		if is_instance_valid(enemy):
			enemy.free()
		_channels_enemy_by_id.erase(enemy_id)
		_game_state_character_nodes.erase(enemy_id)
		if unregister_enemies and _game_state != null:
			if _game_state.characters.has(enemy_id):
				_game_state.unregister_character(enemy_id)
			_game_state.set_world_state("runtime:enemy:%s" % enemy_id, null)
	_channels_kit_active = false


func _reset_channels_kit_for_attempt() -> void:
	_deactivate_channels_kit(true)
	for flure in _channels_flures():
		if is_instance_valid(flure):
			flure.reset_flure()
			flure.set_interaction_enabled(false)
			flure.hide_tutorial_label()
	_activate_channels_kit()


func _channels_flures() -> Array:
	var out: Array = []
	if is_instance_valid(_channels_flure):
		out.append(_channels_flure)
	if is_instance_valid(_channels_run_lure):
		out.append(_channels_run_lure)
	for lane_v in _channels_window_lanes.values():
		var lane: Dictionary = lane_v
		var flure = lane.get("interactable")
		if is_instance_valid(flure) and flure is Flure:
			out.append(flure)
	return out


func _resolve_channels_enemy(enemy_id: String):
	var enemy = _channels_enemy_by_id.get(enemy_id)
	return enemy if is_instance_valid(enemy) else null


func _resolve_channels_enemy_for_scope(enemy_id: String, scope: String):
	if str(_channels_enemy_scope_by_id.get(enemy_id, "")) != scope:
		return null
	return _resolve_channels_enemy(enemy_id)


func _channels_channel_destination(
		char_id: String, position: Vector3, scope: String
	) -> Vector3:
	if char_id in CHANNELS_PARTY_IDS:
		if _channels_window_lanes.has(scope):
			return (_channels_window_lanes[scope] as Dictionary).get(
				"stage_pos", CHANNELS_START)
		return CHANNELS_FLURE_POS + Vector3(-6.0, 0.0, -4.0)
	var downstream_sign := signf(position.z)
	if is_zero_approx(downstream_sign):
		downstream_sign = 1.0
	return Vector3(position.x, 0.5, downstream_sign * 23.0)


func _on_channels_party_swept(char_id: String, scope: String) -> void:
	if _channels_window_lanes.has(scope) \
			and _channels_active_window_lane == scope:
		_fail_channels_window_lane(scope, "channel_swept:%s" % char_id)
	elif scope == "coda" and _current_step == "channels_flure":
		_tutorial_prompt.show_prompt(
			"%s was carried downstream. Regroup before tending." % char_id.capitalize())


func _on_channels_enemy_swept(enemy_id: String, scope: String) -> void:
	if str(_channels_enemy_scope_by_id.get(enemy_id, "")) != scope:
		return
	if _channels_window_lanes.has(scope):
		var lane: Dictionary = _channels_window_lanes[scope]
		var swept_ids: Array = lane.get("swept_ids", [])
		if enemy_id not in swept_ids:
			swept_ids.append(enemy_id)
			swept_ids.sort()
		lane["swept_ids"] = swept_ids
		lane["swarm_state"] = (
			"washed" if _channels_scope_is_fully_swept(
				lane.get("enemy_ids", []), swept_ids) else "washing")
		lane["last_outcome"] = "channel_swept:%s" % enemy_id
		_channels_window_lanes[scope] = lane
		_publish_channels_runtime_authority()
		return
	if scope == "coda" and enemy_id not in _channels_coda_swept_ids:
		_channels_coda_swept_ids.append(enemy_id)
		_channels_coda_swept_ids.sort()
		_channels_coda_phase = (
			"complete" if _channels_scope_is_fully_swept(
				_channels_flush_enemy_ids, _channels_coda_swept_ids) else "washing")
		_publish_channels_runtime_authority()
		if _channels_coda_phase == "complete":
			_complete_channels_coda()


func _channels_scope_is_fully_swept(enemy_ids: Array, swept_ids: Array) -> bool:
	if enemy_ids.is_empty():
		return false
	for enemy_id_v in enemy_ids:
		var enemy_id := str(enemy_id_v)
		if enemy_id not in swept_ids or not _channels_enemy_has_swept_body(enemy_id):
			return false
	return true


func _channels_enemy_has_swept_body(enemy_id: String) -> bool:
	if _game_state == null or not _game_state.characters.has(enemy_id) \
			or _game_state.is_external_traversal_active(enemy_id):
		return false
	var enemy = _resolve_channels_enemy(enemy_id)
	return enemy != null and enemy.has_method("is_alive") and not bool(enemy.is_alive())


func _channels_enemy_pack_committed(enemy_ids: Array, settle_pos: Vector3) -> bool:
	if enemy_ids.is_empty() or _game_state == null:
		return false
	for enemy_id_v in enemy_ids:
		var enemy_id := str(enemy_id_v)
		var enemy = _resolve_channels_enemy(enemy_id)
		if enemy == null or not _game_state.characters.has(enemy_id):
			return false
		if enemy.has_method("is_alive") and not bool(enemy.is_alive()):
			continue
		if str(enemy.get_state()) != "lured" \
				or _game_state.get_position(enemy_id).distance_to(settle_pos) \
					> CHANNELS_ENCOUNTER_COMMIT_RADIUS:
			return false
	return true


func _on_channels_enemy_target_spotted(target_id: String, enemy_id: String) -> void:
	var scope := str(_channels_enemy_scope_by_id.get(enemy_id, ""))
	if target_id not in CHANNELS_PARTY_IDS:
		return
	if scope == "encounter" and _channels_encounter_phase in ["activate", "hide", "run"]:
		if enemy_id not in _channels_encounter_spotted_ids:
			_channels_encounter_spotted_ids.append(enemy_id)
			_channels_encounter_spotted_ids.sort()
		_fail_channels_encounter("spotted:%s:%s" % [enemy_id, target_id])
	elif _channels_window_lanes.has(scope) and _channels_active_window_lane == scope:
		_fail_channels_window_lane(scope, "spotted:%s:%s" % [enemy_id, target_id])


func _on_channels_enemy_hit_target(
		target_id: String, _damage: float, enemy_id: String
	) -> void:
	_on_channels_enemy_target_spotted(target_id, enemy_id)


func _apply_channels_grid_occluders() -> void:
	if _grid == null:
		return
	# The hide is a U-shaped physical recess. Mirror its authored walls into GridWorld so Enemy LOS
	# and navigation see the same occluders as the player; visual StaticBodies alone are not truth.
	for x in range(
			int(CHANNELS_HIDE_SPOT_POS.x - 5.0),
			int(CHANNELS_HIDE_SPOT_POS.x + 5.0) + 1):
		var cell := _grid.world_to_grid(Vector3(
			float(x), 0.0, CHANNELS_HIDE_SPOT_POS.z + 4.0))
		_grid.set_tile(cell.x, cell.y, GridWorld.Tile.WALL)
	for z in range(
			int(CHANNELS_HIDE_SPOT_POS.z - 4.0),
			int(CHANNELS_HIDE_SPOT_POS.z + 4.0) + 1):
		for wall_x in [
			CHANNELS_HIDE_SPOT_POS.x - 5.0,
			CHANNELS_HIDE_SPOT_POS.x + 5.0,
		]:
			var cell := _grid.world_to_grid(Vector3(wall_x, 0.0, float(z)))
			_grid.set_tile(cell.x, cell.y, GridWorld.Tile.WALL)

func _channels_window_branch_direction(stage_pos: Vector3, lure_pos: Vector3) -> Vector3:
	var branch := lure_pos - stage_pos
	branch.y = 0.0
	if branch.length() <= 0.001:
		return Vector3.FORWARD
	return branch.normalized()

func _channels_window_cross_direction(branch_dir: Vector3) -> Vector3:
	return Vector3(-branch_dir.z, 0.0, branch_dir.x).normalized()

func _channels_window_add_wrapped_interval(intervals: Array, start: float, duration: float, period: float) -> void:
	var wrapped_start := fposmod(start, period)
	var end := wrapped_start + duration
	if end <= period:
		intervals.append({"start": wrapped_start, "end": end})
		return
	intervals.append({"start": wrapped_start, "end": period})
	intervals.append({"start": 0.0, "end": end - period})

func _channels_window_offset_washes(lane: Dictionary, flow_offset: float) -> bool:
	var period := float(lane.get("flow_period", CHANNELS_WINDOW_FLOW_PERIOD))
	var flood_duration := float(lane.get("flood_duration", CHANNELS_WINDOW_FLOOD_DURATION))
	var channels: Array = lane.get("periodic_channels", [])
	for channel_variant in channels:
		var channel: Dictionary = channel_variant
		var local_phase := fposmod(
			flow_offset
			+ float(channel.get("contact_time", 0.0))
			+ float(channel.get("phase_offset", 0.0)),
			period
		)
		if local_phase < flood_duration:
			return true
	return false


func _sort_channels_window_interval_by_start(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("start", 0.0)) < float(b.get("start", 0.0))


func _channels_window_wash_analysis(lane: Dictionary, sample_count := 72) -> Dictionary:
	var period := float(lane.get("flow_period", CHANNELS_WINDOW_FLOW_PERIOD))
	var flood_duration := float(lane.get("flood_duration", CHANNELS_WINDOW_FLOOD_DURATION))
	var channels: Array = lane.get("periodic_channels", [])
	var intervals: Array = []
	for channel_variant in channels:
		var channel: Dictionary = channel_variant
		var start := -float(channel.get("contact_time", 0.0)) - float(channel.get("phase_offset", 0.0))
		_channels_window_add_wrapped_interval(intervals, start, flood_duration, period)
	intervals.sort_custom(_sort_channels_window_interval_by_start)
	var merged: Array = []
	for interval_variant in intervals:
		var interval: Dictionary = interval_variant
		if merged.is_empty():
			merged.append(interval.duplicate(true))
			continue
		var current: Dictionary = merged[merged.size() - 1]
		if float(interval.get("start", 0.0)) <= float(current.get("end", 0.0)) + 0.0001:
			current["end"] = maxf(float(current.get("end", 0.0)), float(interval.get("end", 0.0)))
			merged[merged.size() - 1] = current
			continue
		merged.append(interval.duplicate(true))
	var largest_gap := period
	if not merged.is_empty():
		largest_gap = 0.0
		for i in range(merged.size()):
			var current: Dictionary = merged[i]
			var next: Dictionary = merged[(i + 1) % merged.size()]
			var gap := float(next.get("start", 0.0)) - float(current.get("end", 0.0))
			if i == merged.size() - 1:
				gap = float(next.get("start", 0.0)) + period - float(current.get("end", 0.0))
			largest_gap = maxf(largest_gap, gap)
	var failed_offsets: Array = []
	for i in range(maxi(1, sample_count)):
		var offset := period * float(i) / float(maxi(1, sample_count))
		if not _channels_window_offset_washes(lane, offset):
			failed_offsets.append(offset)
	return {
		"guaranteed": largest_gap <= 0.0001 and failed_offsets.is_empty(),
		"coverage_gap": maxf(0.0, largest_gap),
		"sample_count": maxi(1, sample_count),
		"failed_offsets": failed_offsets,
	}

func _channels_window_local_phase(current_tick: float, lane: Dictionary, channel: Dictionary) -> float:
	var period := float(lane.get("flow_period", CHANNELS_WINDOW_FLOW_PERIOD))
	return fposmod(
		current_tick
		+ float(lane.get("flow_offset", 0.0))
		+ float(channel.get("phase_offset", 0.0)),
		period
	)

func _channels_window_channel_level(local_phase: float, flood_duration: float, period: float) -> float:
	if local_phase < flood_duration:
		var flood_t := clampf(local_phase / maxf(flood_duration, 0.001), 0.0, 1.0)
		return 0.68 + 0.32 * sin(PI * flood_t)
	var cooldown_t := clampf((local_phase - flood_duration) / maxf(period - flood_duration, 0.001), 0.0, 1.0)
	return lerpf(0.28, 0.08, cooldown_t)

func _add_channels_window_bridge_segment(parent: Node3D, name: String, from_pos: Vector3, to_pos: Vector3) -> MeshInstance3D:
	var segment := MeshInstance3D.new()
	segment.name = name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.45, 0.18, maxf(0.8, from_pos.distance_to(to_pos) + 0.35))
	segment.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.16, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(0.48, 0.3, 0.12)
	mat.emission_energy_multiplier = 0.15
	segment.material_override = mat
	segment.position = (from_pos + to_pos) * 0.5 + Vector3(0.0, 0.72, 0.0)
	segment.look_at_from_position(segment.position, to_pos + Vector3(0.0, 0.72, 0.0), Vector3.UP, true)
	parent.add_child(segment)
	return segment

func _reset_channels_window_swarm(lane: Dictionary) -> Dictionary:
	lane["swarm_state"] = "idle"
	lane["swept_ids"] = []
	return lane

func _setup_channels_shortcut_gate() -> void:
	if not is_instance_valid(_channels_shortcut_gate) or _game_state == null or _grid == null:
		return
	_channels_shortcut_gate.setup(_game_state, _grid, 0, ["aster", "peris", "endo"])
	_sync_channels_shortcut_gate_presentation()


func _begin_channels_shortcut_open() -> bool:
	if not is_instance_valid(_channels_shortcut_gate):
		return false
	var saved := _channels_shortcut_gate.get_authority_state()
	var phase := str(saved.get("phase", PartyGate3D.PHASE_CLOSED))
	if phase in [PartyGate3D.PHASE_OPENING, PartyGate3D.PHASE_OPEN]:
		_sync_channels_shortcut_gate_presentation()
		return true
	var started := _channels_shortcut_gate.begin_open({
		"cause": "whole_party_reached_channels_shelter",
		"shelter_position": CHANNELS_SHELTER_POS,
		"gate_position": CHANNELS_SHORTCUT_GATE_POS,
	})
	_sync_channels_shortcut_gate_presentation()
	return started


func _on_channels_shortcut_gate_opened() -> void:
	_sync_channels_shortcut_gate_presentation()


func _on_channels_shortcut_gate_blocked(_reason: StringName) -> void:
	_sync_channels_shortcut_gate_presentation()
	if _tutorial_prompt != null and _current_step == "channels_shelter":
		_tutorial_prompt.show_prompt("Bring the whole conscious party into the shelter to lift the return gate")


## Presentation samples the saved absolute opening window; it never owns completion. PartyGate3D
## keeps both physics and GridWorld blocked until its deadline revalidates the whole party.
func _sync_channels_shortcut_gate_presentation() -> void:
	if not is_instance_valid(_channels_shortcut_gate):
		_channels_shortcut_unlocked = false
		return
	var saved := _channels_shortcut_gate.get_authority_state()
	var phase := str(saved.get("phase", PartyGate3D.PHASE_CLOSED))
	_channels_shortcut_unlocked = phase == PartyGate3D.PHASE_OPEN
	var progress := 0.0
	if phase == PartyGate3D.PHASE_OPEN:
		progress = 1.0
	elif phase == PartyGate3D.PHASE_OPENING and _scheduler != null:
		var start_tick := float(saved.get("start_tick", 0.0))
		var end_tick := float(saved.get("end_tick", start_tick))
		progress = clampf(
			(float(_scheduler.get_current_tick()) - start_tick) / maxf(0.000001, end_tick - start_tick),
			0.0,
			1.0
		)
	# Smooth visual lift while retaining the exact linear authority window underneath.
	var eased := progress * progress * (3.0 - 2.0 * progress)
	if is_instance_valid(_channels_shortcut_gate_mesh):
		_channels_shortcut_gate_mesh.position = Vector3(
			0.0, 1.25 + CHANNELS_SHORTCUT_GATE_LIFT_HEIGHT * eased, 0.0)
		_channels_shortcut_gate_mesh.visible = true
	if is_instance_valid(_channels_shortcut_light):
		_channels_shortcut_light.light_color = Color(0.88, 0.72, 0.44).lerp(
			Color(0.46, 0.9, 0.58), progress)
		_channels_shortcut_light.light_energy = lerpf(0.8, 2.0, progress)

## Pure physical preflight shared by the two integrated Act 1 shelters. Every authored member must
## be settled at this exact fixture even when only the injured/night-rest subset pays the batch.
func _preflight_act1_party_rest(
		center: Vector3, radius: float, required_members: Array
	) -> Dictionary:
	var outcome := {
		"blocked": [],
		"rest_members": [],
		"before_atp": {},
	}
	var blocked := outcome["blocked"] as Array
	var rest_members := outcome["rest_members"] as Array
	var before_atp := outcome["before_atp"] as Dictionary
	if _game_state == null or _game_state.scheduler == null \
			or not _game_state.has_method("can_party_rest") \
			or not _game_state.has_method("command_party_rest"):
		blocked.append("Shelter authority is unavailable.")
		return outcome
	for char_id_v in required_members:
		var char_id := str(char_id_v)
		if not _game_state.characters.has(char_id):
			blocked.append("%s is not present." % char_id.capitalize())
			continue
		if _game_state.is_downed(char_id) or _game_state.is_knocked_down(char_id):
			blocked.append("%s must be conscious." % char_id.capitalize())
			continue
		if _game_state.get_position(char_id).distance_to(center) > radius \
				or not _game_state.is_at_shelter(char_id):
			blocked.append("%s is outside this shelter." % char_id.capitalize())
			continue
		if _game_state.is_moving(char_id):
			blocked.append("%s must finish moving." % char_id.capitalize())
			continue
		if _game_state.is_resting(char_id):
			blocked.append("%s is already resting." % char_id.capitalize())
			continue
		if _game_state.is_dodging(char_id) or _game_state.is_endocytosing(char_id) \
				or _game_state.is_external_traversal_active(char_id) \
				or _game_state.is_dragging(char_id) \
				or _game_state.is_field_restoring(char_id):
			blocked.append("%s is committed to another action." % char_id.capitalize())
			continue
		var needs_recovery := (
			_game_state.get_stat(char_id, "hp") < _game_state.get_stat_cap(char_id, "hp")
			or _game_state.get_stat(char_id, "stamina") \
				< _game_state.get_stat_cap(char_id, "stamina")
			or _game_state.get_time_of_day() >= GameState.NIGHT_START
		)
		if needs_recovery:
			rest_members.append(char_id)
			before_atp[char_id] = _game_state.get_stat(char_id, "atp")
	if not blocked.is_empty() or rest_members.is_empty():
		return outcome
	if not bool(_game_state.can_party_rest(rest_members)):
		for char_id_v in rest_members:
			var char_id := str(char_id_v)
			if _game_state.get_stat(char_id, "atp") < CHANNELS_REST_ATP_COST:
				blocked.append("%s needs lysate before resting." % char_id.capitalize())
		if blocked.is_empty():
			blocked.append("The party cannot begin shelter rest yet.")
	return outcome


func _act1_rest_preflight_matches_intent(
		preflight: Dictionary,
		expected_members: Array,
		expected_before_atp: Dictionary,
		expected_day: int
	) -> bool:
	if _game_state == null or _game_state.get_game_day() != expected_day \
			or not (preflight.get("blocked", []) as Array).is_empty() \
			or preflight.get("rest_members", []) != expected_members:
		return false
	for char_id_v in expected_members:
		var char_id := str(char_id_v)
		if not expected_before_atp.has(char_id) \
				or not is_equal_approx(
					_game_state.get_stat(char_id, "atp"),
					float(expected_before_atp[char_id])):
			return false
	return true


func _act1_party_rest_effect_matches(
		members: Array, before_atp: Dictionary, commit_day: int
	) -> bool:
	if _game_state == null or members.is_empty():
		return false
	for char_id_v in members:
		var char_id := str(char_id_v)
		if not before_atp.has(char_id) or not _game_state.characters.has(char_id):
			return false
		var expected_atp: float = float(
			_game_state.quantize_atp(float(before_atp[char_id]) - 1.0))
		if not is_equal_approx(_game_state.get_stat(char_id, "atp"), expected_atp):
			return false
	if _game_state.get_game_day() > commit_day:
		return true
	for char_id_v in members:
		if not _game_state.is_resting(str(char_id_v)):
			return false
	return true


func _clear_channels_shelter_rest_context() -> void:
	_channels_shelter_rest_members.clear()
	_channels_shelter_rest_commit_tick = -1.0
	_channels_shelter_rest_commit_day = 0
	_channels_shelter_rest_before_atp.clear()


func _apply_channels_shelter_rest_presentation() -> void:
	if not is_instance_valid(_channels_shelter_interactable):
		return
	var ready := _current_step == "channels_shelter" \
		and _channels_shelter_reached and _channels_shelter_rest_phase == "ready"
	if ready:
		# A rejected/rolled-back one-shot must become a real usable hearth again. Completion
		# remains disabled, so a loaded RESTED phase cannot duplicate the paid transaction.
		_channels_shelter_interactable.reset()
	_channels_shelter_interactable.set_interaction_enabled(ready)
	if ready:
		_channels_shelter_interactable.show_tutorial_label()
	else:
		_channels_shelter_interactable.hide_tutorial_label()


func _arm_channels_shelter_rest_callback() -> void:
	if _scheduler == null or _channels_shelter_rest_phase != "committing":
		return
	_scheduler.cancel_tag(CHANNELS_SHELTER_REST_TAG)
	_scheduler.schedule_at(
		maxf(float(_scheduler.get_current_tick()), _channels_shelter_rest_commit_tick),
		_resume_committed_channels_shelter_rest.bind(_channels_shelter_rest_commit_tick),
		CHANNELS_SHELTER_REST_TAG)


func _resume_committed_channels_shelter_rest(expected_tick: float) -> void:
	if _channels_shelter_rest_phase != "committing" \
			or not is_equal_approx(_channels_shelter_rest_commit_tick, expected_tick):
		return
	if _act1_party_rest_effect_matches(
			_channels_shelter_rest_members,
			_channels_shelter_rest_before_atp,
			_channels_shelter_rest_commit_day):
		_complete_channels_shelter_rest(true)
		return
	var preflight := _preflight_act1_party_rest(
		CHANNELS_SHELTER_POS, CHANNELS_SHELTER_RADIUS, CHANNELS_PARTY_IDS)
	if not _act1_rest_preflight_matches_intent(
			preflight,
			_channels_shelter_rest_members,
			_channels_shelter_rest_before_atp,
			_channels_shelter_rest_commit_day):
		_channels_shelter_rest_phase = "ready"
		_clear_channels_shelter_rest_context()
		_apply_channels_shelter_rest_presentation()
		_publish_channels_runtime_authority()
		return
	if bool(_game_state.command_party_rest(_channels_shelter_rest_members)):
		_complete_channels_shelter_rest(true)
	else:
		_channels_shelter_rest_phase = "ready"
		_clear_channels_shelter_rest_context()
		_apply_channels_shelter_rest_presentation()
		_publish_channels_runtime_authority()

## Inert compatibility seam. The coda advances only after the visible Flure accepts Peris.
func _start_channels_flure_flush() -> void:
	pass


func _on_channels_coda_flure_activated(pulled: int) -> void:
	if _current_step != "channels_flure" or _channels_coda_phase != "ready":
		return
	if pulled != _channels_flush_enemy_ids.size():
		_reset_channels_scope_kit("coda")
		_channels_flure.reset_flure()
		_set_channels_flure_active(true)
		_tutorial_prompt.show_prompt(
			"The signal reached %d of %d sentries. The demonstration resets; tend only when the pack is calm."
			% [pulled, _channels_flush_enemy_ids.size()])
		return
	_channels_coda_phase = "luring"
	_set_channels_flure_active(false)
	_set_channels_flow_power(0.6)
	_tutorial_prompt.show_prompt(
		"Watch the bodies follow the signal into the visible current")
	_publish_channels_runtime_authority()


func _complete_channels_coda() -> void:
	if _current_step != "channels_flure" or _channels_coda_phase != "complete":
		return
	_set_channels_flure_active(false)
	_tutorial_prompt.hide_prompt()
	_dialogue_chain([
		"channels.peris.touch",
		"channels.peris.always",
	], _start_channels_window_two_intro)


func _start_channels_window_two_intro() -> void:
	_start_channels_window_intro("window_two")


func _update_channels_flure_flush(delta: float, spd: float) -> void:
	# Ambient lengthwise strips are presentation only. Their pulse follows the real coda kit state;
	# no mesh interpolation decides whether a body moves, is caught, or dies.
	var target_power := 0.25
	if _channels_coda_phase in ["luring", "washing"]:
		var fraction := float(_channels_coda_swept_ids.size()) \
			/ float(maxi(1, _channels_flush_enemy_ids.size()))
		target_power = lerpf(0.6, 1.0, fraction)
	elif _channels_coda_phase == "complete":
		target_power = 0.45
	_set_channels_flow_power(move_toward(
		_channels_flow_power, target_power, maxf(0.0, delta * spd) * 0.8))

func _set_channels_run_lure_active(active: bool) -> void:
	_channels_run_lure_active = active

func _show_marker(pos: Vector3, text: String, tint := Color(0.4, 0.7, 0.5, 0.75)) -> void:
	var lbl := Label3D.new()
	lbl.name = "Marker_" + text
	lbl.text = text
	lbl.font_size = 28
	lbl.pixel_size = 0.008
	lbl.modulate = tint
	lbl.outline_modulate = Color(0, 0, 0, 0.5)
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = pos
	var env: Node = find_child("Environment", false, false)
	if env:
		env.add_child(lbl)

func _clear_markers() -> void:
	var env: Node = find_child("Environment", false, false)
	if env == null:
		return
	for child in env.get_children():
		if child is Label3D and child.name.begins_with("Marker_"):
			child.queue_free()

func _get_channels_window_party_positions(window_id: String) -> Dictionary:
	match window_id:
		"window_one":
			return {
				"aster": CHANNELS_WINDOW_ONE_STAGE_POS,
				"peris": CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-1.6, 0.0, 1.2),
				"endo": CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-2.8, 0.0, -1.0),
			}
		"window_two":
			return {
				"aster": CHANNELS_WINDOW_TWO_STAGE_POS,
				"peris": CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-1.6, 0.0, 1.2),
				"endo": CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-2.8, 0.0, -1.0),
			}
		_:
			return {}

func _channels_window_step_name(window_id: String, suffix: String) -> String:
	return "channels_%s_%s" % [window_id, suffix]

func _set_channels_window_lane_active(window_id: String, active: bool) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["lure_active"] = active
	_channels_window_lanes[window_id] = lane

func _reset_channels_window_lane(window_id: String, reset_kit := true) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _scheduler:
		_scheduler.cancel_tag("channels_%s_retry" % window_id)
	if reset_kit:
		_reset_channels_scope_kit(window_id)
	_set_channels_window_lane_active(window_id, false)
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["phase"] = "idle"
	lane["safe_until_tick"] = -1.0
	lane["retry_deadline"] = -1.0
	lane["last_outcome"] = ""
	lane["flow_offset"] = 0.0
	if lane.has("interactable"):
		var flure := _valid_channels_flure(lane)
		if is_instance_valid(flure):
			flure.reset_flure()
			flure.set_interaction_enabled(false)
			flure.hide_tutorial_label()
	lane = _reset_channels_window_swarm(lane)
	_channels_window_lanes[window_id] = lane

func _begin_channels_window_lane(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if not _enter_step(_channels_window_step_name(window_id, "activate")):
		return
	_channels_active_window_lane = window_id
	_select_character("peris")
	_player.set_move_enabled(true)
	_reset_channels_window_lane(window_id)
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["phase"] = "activate"
	lane["retry_deadline"] = -1.0
	_channels_window_lanes[window_id] = lane
	var flure := _valid_channels_flure(lane)
	if is_instance_valid(flure):
		flure.set_interaction_enabled(true)
		flure.show_tutorial_label()
	_publish_channels_runtime_authority()
	_clear_markers()
	_show_marker(lane["lure_pos"] + Vector3(0, 2.0, 0), "LURE", Color(0.76, 0.46, 0.2, 0.85))
	_show_marker(lane["goal_pos"] + Vector3(0, 2.0, 0), "CROSS", Color(0.36, 0.74, 0.88, 0.85))
	_tutorial_prompt.show_prompt(
		"Tend the flure. Watch which current carries the sentries, then cross between surges")

## Inert compatibility seam. QA drivers stage Peris at the lane's exact Flure and trigger that
## Interactable; this callback cannot stand in for the player action.
func _on_channels_window_lure_activated(_window_id: String) -> void:
	pass


func _on_channels_window_flure_activated(pulled: int, window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _channels_active_window_lane != window_id:
		return
	if _current_step not in [
		_channels_window_step_name(window_id, "activate"),
		_channels_window_step_name(window_id, "cross"),
	]:
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	if bool(lane.get("lure_active", false)):
		return
	var window_flure: Flure = lane.get("interactable")
	var expected_count := (lane.get("enemy_ids", []) as Array).size()
	if pulled != expected_count:
		_fail_channels_window_lane(
			window_id, "signal_reached:%d/%d" % [pulled, expected_count])
		return
	_set_channels_window_lane_active(window_id, true)
	lane = _channels_window_lanes[window_id]
	lane["phase"] = "cross"
	var effect := (
		window_flure.get_effect_state() if is_instance_valid(window_flure) else {})
	lane["safe_until_tick"] = float(effect.get("end_tick", -1.0))
	lane["swarm_state"] = "advancing"
	lane["swept_ids"] = []
	_channels_window_lanes[window_id] = lane
	_enter_step(_channels_window_step_name(window_id, "cross"))
	if lane.has("interactable"):
		var interactable = lane["interactable"]
		if is_instance_valid(interactable):
			interactable.hide_tutorial_label()
	_tutorial_prompt.show_prompt(
		"The bodies are moving. Read the real channel pulses; cross after the pack is carried")
	_publish_channels_runtime_authority()

func _on_channels_window_lure_expired(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _channels_active_window_lane != window_id:
		return
	if _current_step != _channels_window_step_name(window_id, "cross"):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	if _channels_scope_is_fully_swept(
			lane.get("enemy_ids", []), lane.get("swept_ids", [])):
		lane["phase"] = "safe"
		lane["swarm_state"] = "washed"
		lane["safe_until_tick"] = -1.0
		_channels_window_lanes[window_id] = lane
		_set_channels_window_lane_active(window_id, false)
		_publish_channels_runtime_authority()
		return
	_set_channels_window_lane_active(window_id, false)
	lane = _channels_window_lanes[window_id]
	lane["safe_until_tick"] = -1.0
	_channels_window_lanes[window_id] = lane
	_fail_channels_window_lane(window_id, "signal_ended_before_wash")

func _fail_channels_window_lane(window_id: String, reason: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _current_step not in [
		_channels_window_step_name(window_id, "activate"),
		_channels_window_step_name(window_id, "cross"),
	]:
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	if str(lane.get("phase", "")) == "failed":
		return
	_player.set_move_enabled(false)
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)
	lane["phase"] = "failed"
	lane["last_outcome"] = reason
	lane["safe_until_tick"] = -1.0
	lane["retry_deadline"] = float(_scheduler.get_current_tick()) \
		+ CHANNELS_WINDOW_RETRY_DELAY
	_channels_window_lanes[window_id] = lane
	_set_channels_window_lane_active(window_id, false)
	_publish_channels_runtime_authority()
	var failure_prompt := "Too slow. The Sapscraps spill back into the lane."
	if reason.begins_with("signal_reached:"):
		failure_prompt = "The signal did not take the whole pack. Wait for the reset, then tend before they commit."
	elif reason.begins_with("spotted:"):
		failure_prompt = "A sentry saw the party before the current carried it. Break line of sight, then retry."
	elif reason.begins_with("channel_swept:"):
		failure_prompt = "The visible surge caught the party. Read its pulse before crossing."
	_tutorial_prompt.show_prompt(failure_prompt)
	_clear_markers()
	_show_marker(lane["curtain_pos"] + Vector3(0, 2.0, 0), "BLOCKED", Color(0.86, 0.28, 0.22, 0.88))
	_arm_channels_callback_at(
		float(lane.get("retry_deadline", -1.0)),
		_restart_channels_window_lane.bind(window_id),
		"channels_%s_retry" % window_id)

func _restart_channels_window_lane(window_id: String) -> void:
	if not _enter_step(_channels_window_step_name(window_id, "reset")):
		return
	if not _channels_window_lanes.has(window_id):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["phase"] = "reset"
	lane["retry_deadline"] = -1.0
	_channels_window_lanes[window_id] = lane
	_publish_channels_runtime_authority()
	var party_positions := _get_channels_window_party_positions(window_id)
	_move_party_and_continue(
		party_positions, "channels_%s_reset_move" % window_id)

func _complete_channels_window_lane(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	if _channels_active_window_lane != window_id \
			or _current_step != _channels_window_step_name(window_id, "cross") \
			or not _channels_scope_is_fully_swept(
				lane.get("enemy_ids", []), lane.get("swept_ids", [])) \
			or not _channels_full_conscious_party_near(
				lane.get("goal_pos", Vector3.ZERO), CHANNELS_WINDOW_GOAL_RADIUS):
		return
	lane["phase"] = "safe"
	lane["last_outcome"] = "success"
	lane["safe_until_tick"] = -1.0
	lane["retry_deadline"] = -1.0
	_channels_window_lanes[window_id] = lane
	_channels_active_window_lane = ""
	_set_channels_window_lane_active(window_id, false)
	_publish_channels_runtime_authority()
	_clear_markers()
	_tutorial_prompt.hide_prompt()
	match window_id:
		"window_one":
			_start_channels_to_flure()
		"window_two":
			_start_channels_to_encounter()

func _update_channels_window_puzzles(_delta: float, _spd: float) -> void:
	for window_id in _channels_window_lanes.keys():
		var lane: Dictionary = _channels_window_lanes[window_id]
		var periodic_channels: Array = lane.get("periodic_channels", [])
		for i in range(periodic_channels.size()):
			var channel_state: Dictionary = periodic_channels[i]
			var channel := _valid_channels_channel(channel_state, "channel")
			channel_state["flooded"] = (
				channel.is_flooding() if is_instance_valid(channel) else false)
			periodic_channels[i] = channel_state
		lane["periodic_channels"] = periodic_channels
		_channels_window_lanes[window_id] = lane


func _evaluate_channels_window_authority() -> void:
	var window_id := _channels_active_window_lane
	if window_id.is_empty() or not _channels_window_lanes.has(window_id) \
			or _current_step != _channels_window_step_name(window_id, "cross"):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	var goal_pos: Vector3 = lane.get("goal_pos", Vector3.ZERO)
	var fully_swept := _channels_scope_is_fully_swept(
		lane.get("enemy_ids", []), lane.get("swept_ids", []))
	if fully_swept and str(lane.get("phase", "")) != "safe":
		lane["phase"] = "safe"
		lane["swarm_state"] = "washed"
		lane["last_outcome"] = "pack_carried"
		_channels_window_lanes[window_id] = lane
		_tutorial_prompt.show_prompt(
			"The current carried the pack. Cross between the visible pulses.")
		_publish_channels_runtime_authority()
	if fully_swept and _channels_full_conscious_party_near(
			goal_pos, CHANNELS_WINDOW_GOAL_RADIUS):
		_complete_channels_window_lane(window_id)
		return
	var flure := _valid_channels_flure(lane)
	var effect := flure.get_effect_state() if is_instance_valid(flure) else {}
	var lure_active := str(effect.get("phase", "")) == "active"
	lane["lure_active"] = lure_active
	lane["safe_until_tick"] = float(effect.get("end_tick", -1.0)) if lure_active else -1.0
	_channels_window_lanes[window_id] = lane
	if not fully_swept and not lure_active:
		_on_channels_window_lure_expired(window_id)

func _reset_channels_encounter_nodes(reset_kit := true) -> void:
	_clear_markers()
	_set_channels_run_lure_active(false)
	_channels_run_lure_expire_tick = -1.0
	_channels_encounter_lure_start_tick = -1.0
	_channels_encounter_retry_deadline = -1.0
	_channels_party_hidden = false
	_channels_exposure_by_character.clear()
	_channels_encounter_spotted_ids.clear()
	_channels_encounter_resetting = false
	if reset_kit:
		_reset_channels_scope_kit("encounter")
	if is_instance_valid(_channels_run_lure):
		_channels_run_lure.reset_flure()
		_channels_run_lure.set_interaction_enabled(false)
		_channels_run_lure.hide_tutorial_label()

func _begin_channels_encounter() -> void:
	if not _enter_step("channels_encounter_activate"):
		return
	_select_character("endo")
	_reset_channels_encounter_nodes()
	_channels_encounter_phase = "activate"
	_channels_encounter_phase_start_tick = float(_scheduler.get_current_tick())
	_channels_exposure_by_character = _channels_compute_exposure_by_character()
	_publish_channels_runtime_authority()
	_show_marker(CHANNELS_RUN_LURE_POS + Vector3(0, 2.0, 0), "LURE", Color(0.75, 0.45, 0.2, 0.8))
	_show_marker(CHANNELS_HIDE_SPOT_POS + Vector3(0, 2.0, 0), "HIDE", Color(0.35, 0.75, 0.55, 0.8))
	_show_marker(CHANNELS_SHELTER_POS + Vector3(0, 2.0, 0), "SHELTER", Color(0.8, 0.72, 0.45, 0.85))
	if is_instance_valid(_channels_run_lure):
		_channels_run_lure.set_interaction_enabled(true)
		_channels_run_lure.show_tutorial_label()
	_tutorial_prompt.show_prompt(
		"Tend Endo's flure, then move the whole party behind the walls")
	_player.set_move_enabled(true)


## Inert compatibility entry point. The real Flure's exact source/body receipt is mandatory.
func _on_channels_run_lure_activated() -> void:
	pass


func _on_channels_run_flure_activated(pulled: int) -> void:
	if _channels_run_lure_active \
			or _current_step not in ["channels_encounter_activate", "channels_encounter_hide"]:
		return
	if pulled != _channels_swarm_enemy_ids.size():
		_fail_channels_encounter(
			"signal_reached:%d/%d" % [pulled, _channels_swarm_enemy_ids.size()])
		return
	_set_channels_run_lure_active(true)
	_channels_encounter_phase = "hide"
	_channels_encounter_phase_start_tick = float(_scheduler.get_current_tick())
	var effect := _channels_run_lure.get_effect_state()
	_channels_encounter_lure_start_tick = float(
		effect.get("start_tick", _channels_encounter_phase_start_tick))
	_channels_run_lure_expire_tick = float(effect.get("end_tick", -1.0))
	_channels_encounter_retry_deadline = -1.0
	_channels_exposure_by_character = _channels_compute_exposure_by_character()
	_enter_step("channels_encounter_hide")
	_channels_run_lure.set_interaction_enabled(false)
	_channels_run_lure.hide_tutorial_label()
	_tutorial_prompt.show_prompt(
		"Hide behind the walls until every sentry physically reaches the signal")
	_publish_channels_runtime_authority()

func _on_channels_run_lure_expired() -> void:
	if _current_step not in ["channels_encounter_hide", "channels_encounter_run"]:
		return
	_set_channels_run_lure_active(false)
	_channels_run_lure_expire_tick = -1.0
	if _current_step == "channels_encounter_hide":
		_fail_channels_encounter("signal_ended_before_commit")

func _fail_channels_encounter(reason: String) -> void:
	if _channels_encounter_resetting or _current_step not in ["channels_encounter_activate", "channels_encounter_hide", "channels_encounter_run"]:
		return
	_channels_encounter_resetting = true
	_channels_encounter_phase = "failed"
	_channels_encounter_phase_start_tick = float(_scheduler.get_current_tick())
	_channels_encounter_retry_deadline = (
		_channels_encounter_phase_start_tick + CHANNELS_ENCOUNTER_RETRY_DELAY)
	_set_channels_run_lure_active(false)
	_channels_run_lure_expire_tick = -1.0
	if is_instance_valid(_channels_run_lure):
		_channels_run_lure.set_interaction_enabled(false)
		_channels_run_lure.hide_tutorial_label()
	_player.set_move_enabled(false)
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)
	var failure_prompt := "A sentry catches the movement. Break line of sight and try again."
	if reason.begins_with("signal_reached:"):
		failure_prompt = "The signal did not take the whole pack. Wait for the reset, then tend before they commit."
	elif reason.begins_with("signal_ended"):
		failure_prompt = "The signal ended before the pack committed. Tend, hide, then run as soon as they gather."
	elif reason.begins_with("required_body_unavailable:"):
		failure_prompt = "The whole conscious party must make this run."
	_tutorial_prompt.show_prompt(failure_prompt)
	_clear_markers()
	_show_marker(CHANNELS_HIDE_SPOT_POS + Vector3(0, 2.0, 0), "CAUGHT", Color(0.85, 0.28, 0.22, 0.85))
	_publish_channels_runtime_authority()
	_arm_channels_callback_at(
		_channels_encounter_retry_deadline,
		_restart_channels_encounter.bind(reason),
		"channels_encounter_retry")

func _restart_channels_encounter(_reason: String) -> void:
	if not _enter_step("channels_encounter_reset"):
		return
	_channels_encounter_phase = "reset"
	_channels_encounter_phase_start_tick = float(_scheduler.get_current_tick())
	_channels_encounter_retry_deadline = -1.0
	_publish_channels_runtime_authority()
	_move_party_and_continue({
		"aster": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-2.4, 0.0, 0.4),
		"peris": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-1.4, 0.0, 1.2),
		"endo": CHANNELS_ENCOUNTER_ENTRY_POS,
	}, "channels_encounter_reset_move")

func _complete_channels_encounter() -> void:
	if _current_step == "channels_shelter":
		return
	if not _channels_full_conscious_party_near(
			CHANNELS_SHELTER_POS, CHANNELS_SHELTER_RADIUS):
		return
	_channels_encounter_phase = "complete"
	_channels_encounter_phase_start_tick = float(_scheduler.get_current_tick())
	_channels_encounter_retry_deadline = -1.0
	_channels_run_lure_expire_tick = -1.0
	_set_channels_run_lure_active(false)
	if is_instance_valid(_channels_run_lure):
		_channels_run_lure.set_interaction_enabled(false)
		_channels_run_lure.hide_tutorial_label()
	_publish_channels_runtime_authority()
	_player.set_move_enabled(false)
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)
	_clear_markers()
	_tutorial_prompt.hide_prompt()
	_start_channels_shelter()

func _update_channels_encounter(_delta: float, _spd: float) -> void:
	if _current_step not in ["channels_encounter_activate", "channels_encounter_hide", "channels_encounter_run"]:
		return
	var effect := (
		_channels_run_lure.get_effect_state()
		if is_instance_valid(_channels_run_lure) else {})
	var active := str(effect.get("phase", "")) == Flure.PHASE_ACTIVE
	_set_channels_run_lure_active(active)
	_channels_encounter_lure_start_tick = float(effect.get("start_tick", -1.0))
	_channels_run_lure_expire_tick = float(effect.get("end_tick", -1.0)) if active else -1.0


func _channels_compute_exposure_by_character() -> Dictionary:
	var exposure_by_character := {}
	if _game_state == null:
		return exposure_by_character
	for char_id in CHANNELS_PARTY_IDS:
		if not _game_state.characters.has(char_id) or _game_state.is_downed(char_id):
			exposure_by_character[char_id] = true
			continue
		exposure_by_character[char_id] = (
			_game_state.get_position(char_id).distance_to(CHANNELS_HIDE_SPOT_POS)
			> CHANNELS_HIDE_RADIUS)
	return exposure_by_character


func _evaluate_channels_encounter_authority() -> void:
	if _current_step not in [
		"channels_encounter_activate",
		"channels_encounter_hide",
		"channels_encounter_run",
	]:
		return
	var exposure_by_character := _channels_compute_exposure_by_character()
	var hide_reached := _channels_full_conscious_party_near(
		CHANNELS_HIDE_SPOT_POS, CHANNELS_HIDE_RADIUS)
	if hide_reached != _channels_party_hidden \
			or exposure_by_character != _channels_exposure_by_character:
		_channels_party_hidden = hide_reached
		_channels_exposure_by_character = exposure_by_character
		if _channels_party_hidden and _current_step == "channels_encounter_hide":
			_tutorial_prompt.show_prompt(
				"Hold here until every sentry reaches the flure")
		_publish_channels_runtime_authority()

	for char_id in CHANNELS_PARTY_IDS:
		if not _game_state.characters.has(char_id) or _game_state.is_downed(char_id):
			_fail_channels_encounter("required_body_unavailable:%s" % char_id)
			return

	var effect := (
		_channels_run_lure.get_effect_state()
		if is_instance_valid(_channels_run_lure) else {})
	var lure_active := str(effect.get("phase", "")) == Flure.PHASE_ACTIVE
	_set_channels_run_lure_active(lure_active)
	_channels_encounter_lure_start_tick = float(effect.get("start_tick", -1.0))
	_channels_run_lure_expire_tick = float(effect.get("end_tick", -1.0)) \
		if lure_active else -1.0

	if _current_step == "channels_encounter_hide":
		var pack_committed := _channels_enemy_pack_committed(
			_channels_swarm_enemy_ids, CHANNELS_RUN_LURE_POS)
		if pack_committed and hide_reached:
			_channels_encounter_phase = "run"
			_channels_encounter_phase_start_tick = float(_scheduler.get_current_tick())
			_enter_step("channels_encounter_run")
			_tutorial_prompt.show_prompt(
				"Now run for shelter while the signal holds them")
			_publish_channels_runtime_authority()
		elif not lure_active:
			_on_channels_run_lure_expired()
		return

	if _current_step == "channels_encounter_run" and _channels_full_conscious_party_near(
			CHANNELS_SHELTER_POS, CHANNELS_SHELTER_RADIUS):
		_complete_channels_encounter()

func _start_channels_enter() -> void:
	if _fade_rect != null:
		_fade_rect.color.a = 0.0
	if not _enter_step("channels_enter"):
		return
	_start_channels_authority_poll()
	_start_iron_hazard_cadence()
	_focus_aster_view()
	_player.set_move_enabled(true)
	_dialogue_chain([
		"channels.narration.enter",
		"channels.aster.fluid",
		"channels.peris.sound",
	], _queue_channels_to_memory)


func _queue_channels_to_memory() -> void:
	_schedule_portable_method(0.5, _start_channels_to_memory, "channels_to_memory")

func _start_channels_to_memory() -> void:
	if not _enter_step("channels_to_memory"):
		return
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_memory() -> void:
	if not _enter_step("channels_memory"):
		return
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_game_state.command_stop("aster")
	_focus_peris_view()
	_move_party_and_continue({
		"peris": CHANNELS_BODY_POS + Vector3(-1.0, 0.0, 1.1),
		"aster": CHANNELS_BODY_POS + Vector3(-3.0, 0.0, 0.4),
		"endo": CHANNELS_BODY_POS + Vector3(-4.2, 0.0, -0.8),
	}, "channels_memory_move")


func _on_channels_memory_party_arrived() -> void:
	_dialogue_chain([
		"channels.narration.memory",
		"channels.peris.know_place",
		"channels.aster.not_here",
		"channels.peris.saw_it",
		"channels.narration.leads",
	], _queue_channels_corpse)


func _queue_channels_corpse() -> void:
	_schedule_portable_method(0.5, _start_channels_corpse, "channels_corpse")

func _start_channels_to_flure() -> void:
	if not _enter_step("channels_to_flure"):
		return
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_window_intro(window_id: String) -> void:
	var intro_step := _channels_window_step_name(window_id, "intro")
	if not _enter_step(intro_step):
		return
	_select_character("peris")
	_focus_peris_view()
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)

	var dialogue_keys: Array = []
	match window_id:
		"window_one":
			dialogue_keys = [
				"channels.narration.window_one",
				"channels.endo.window_one",
			]
		"window_two":
			dialogue_keys = [
				"channels.narration.window_two",
				"channels.peris.window_two",
			]
		_:
			return

	_move_party_and_continue(
		_get_channels_window_party_positions(window_id),
		"channels_%s_intro_move" % window_id)


func _on_channels_window_intro_party_arrived(window_id: String) -> void:
	var dialogue_keys: Array = []
	match window_id:
		"window_one":
			dialogue_keys = [
				"channels.narration.window_one",
				"channels.endo.window_one",
			]
		"window_two":
			dialogue_keys = [
				"channels.narration.window_two",
				"channels.peris.window_two",
			]
		_:
			return
	_dialogue_chain(
		dialogue_keys,
		_queue_channels_window_one_begin
			if window_id == "window_one" else _queue_channels_window_two_begin
	)


func _queue_channels_window_one_begin() -> void:
	_schedule_portable_method(
		0.35, _begin_channels_window_one, "channels_window_one_begin")


func _begin_channels_window_one() -> void:
	_begin_channels_window_lane("window_one")


func _queue_channels_window_two_begin() -> void:
	_schedule_portable_method(
		0.35, _begin_channels_window_two, "channels_window_two_begin")


func _begin_channels_window_two() -> void:
	_begin_channels_window_lane("window_two")

func _start_channels_corpse() -> void:
	if not _enter_step("channels_corpse"):
		return
	_focus_aster_view()
	_dialogue_chain([
		"channels.narration.body",
		"channels.endo.kneel",
		"channels.aster.report",
		"channels.peris.smell",
		"channels.peris.clients",
		"channels.aster.lysate",
		"channels.peris.people",
		"channels.aster.hungry",
		"channels.aster.downgrade",
	], _queue_channels_window_one_intro)


func _queue_channels_window_one_intro() -> void:
	_schedule_portable_method(
		0.5, _start_channels_window_one_intro, "channels_window_one_intro")


func _start_channels_window_one_intro() -> void:
	_start_channels_window_intro("window_one")

func _start_channels_flure() -> void:
	if not _enter_step("channels_flure"):
		return
	_select_character("peris")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	for char_id in CHANNELS_PARTY_IDS:
		if _game_state.characters.has(char_id):
			_game_state.command_stop(char_id)
	_channels_coda_phase = "idle"
	_channels_coda_swept_ids.clear()
	_set_channels_flure_active(false)
	_move_party_and_continue({
		"peris": CHANNELS_FLURE_POS + Vector3(-0.8, 0.0, 0.6),
		"aster": CHANNELS_FLURE_POS + Vector3(-2.5, 0.0, -0.3),
		"endo": CHANNELS_FLURE_POS + Vector3(-3.6, 0.0, 1.2),
	}, "channels_flure_move")


func _on_channels_flure_party_arrived() -> void:
	_dialogue_chain([
		"channels.narration.flora",
		"channels.aster.lure",
		"channels.peris.signals",
		"channels.peris.pause",
	], _arm_channels_coda_flure)


func _arm_channels_coda_flure() -> void:
	if _current_step != "channels_flure":
		return
	_channels_coda_phase = "ready"
	_select_character("peris")
	_player.set_move_enabled(true)
	_set_channels_flure_active(true)
	_tutorial_prompt.show_prompt(
		"Tend the flure with Peris, then step clear and watch the real bodies cross the current")
	_publish_channels_runtime_authority()

func _start_channels_to_encounter() -> void:
	if not _enter_step("channels_to_encounter"):
		return
	_select_character("aster")
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_encounter_intro() -> void:
	if not _enter_step("channels_encounter_intro"):
		return
	_select_character("endo")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_move_party_and_continue({
		"aster": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-2.4, 0.0, 0.4),
		"peris": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-1.4, 0.0, 1.2),
		"endo": CHANNELS_ENCOUNTER_ENTRY_POS,
	}, "channels_encounter_intro_move")

func _start_channels_shelter() -> void:
	if not _enter_step("channels_shelter"):
		return
	_select_character("endo")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_game_state.command_stop("aster")
	_game_state.command_stop("peris")
	_game_state.command_stop("endo")
	_move_party_and_continue({
		"aster": CHANNELS_SHELTER_POS + Vector3(-1.8, 0.0, -1.2),
		"peris": CHANNELS_SHELTER_POS + Vector3(-0.8, 0.0, 0.9),
		"endo": CHANNELS_SHELTER_POS + Vector3(-0.3, 0.0, -0.2),
	}, "channels_shelter_move")


func _on_channels_shelter_party_arrived() -> void:
	if _channels_shelter_reached:
		return
	if not _channels_full_conscious_party_near(
			CHANNELS_SHELTER_POS, CHANNELS_SHELTER_RADIUS):
		_player.set_move_enabled(true)
		_tutorial_prompt.show_prompt(
			"Bring the whole conscious party into the shelter to lift the return gate")
		return
	# Arrival is the cause. PartyGate3D independently rechecks registered, conscious, nearby bodies;
	# the story flag cannot get ahead of the physical commitment if the formation was interrupted.
	if not _begin_channels_shortcut_open():
		_player.set_move_enabled(true)
		_tutorial_prompt.show_prompt(
			"Bring the whole conscious party into the shelter to lift the return gate")
		return
	_channels_shelter_reached = true
	_channels_party_recuperated = false
	# Arrival opens the route but does not arm a proximity HOLD during its own introduction.
	# The named dialogue continuation below advances LOCKED -> READY after control is returned.
	_channels_shelter_rest_phase = "locked"
	_clear_channels_shelter_rest_context()
	_apply_channels_shelter_rest_presentation()
	_publish_channels_runtime_authority()
	_dialogue_chain([
		"channels.narration.shelter",
		"channels.endo.door",
		"channels.narration.shortcut",
	], _enable_channels_shelter_rest)


func _enable_channels_shelter_rest() -> void:
	if _current_step != "channels_shelter" or not _channels_shelter_reached:
		return
	if _channels_shelter_rest_phase == "locked":
		_channels_shelter_rest_phase = "ready"
		_clear_channels_shelter_rest_context()
		_publish_channels_runtime_authority()
	_player.set_move_enabled(true)
	_apply_channels_shelter_rest_presentation()
	_tutorial_prompt.show_prompt(
		"Use REST PARTY at the shelter hearth when everyone is settled")


## Compatibility probe for external tests/tapes. Rest can begin only from the hearth receipt below.
func trigger_channels_shelter_rest() -> bool:
	return false


func _validate_act1_channels_shelter_trigger(
		source: Node, active_character: String
	) -> bool:
	if _current_step != "channels_shelter" \
			or not _channels_shelter_reached \
			or _channels_shelter_rest_phase != "ready" \
			or source != _channels_shelter_interactable \
			or active_character not in CHANNELS_PARTY_IDS \
			or not _act1_interaction_actor_ready_at(source, active_character):
		return false
	var preflight := _preflight_act1_party_rest(
		CHANNELS_SHELTER_POS, CHANNELS_SHELTER_RADIUS, CHANNELS_PARTY_IDS)
	return (preflight.get("blocked", []) as Array).is_empty()


func _act1_channels_shelter_receipt_pending(source: Node) -> bool:
	var actor := str(source.get("active_character")) if source != null else ""
	return _validate_act1_channels_shelter_trigger(source, actor) \
		and bool(source.get("one_shot")) \
		and bool(source.get("_used")) \
		and not bool(source.get("interaction_enabled"))


func _on_act1_channels_shelter_interacted(
		source: Node, play_dialogue := true
	) -> void:
	if source != _channels_shelter_interactable \
			or not _act1_channels_shelter_receipt_pending(source):
		return
	var preflight := _preflight_act1_party_rest(
		CHANNELS_SHELTER_POS, CHANNELS_SHELTER_RADIUS, CHANNELS_PARTY_IDS)
	var blocked := preflight.get("blocked", []) as Array
	if not blocked.is_empty():
		show_preview_note(str(blocked[0]), 2.8)
		if is_instance_valid(_channels_shelter_interactable):
			_channels_shelter_interactable.reset()
			_apply_channels_shelter_rest_presentation()
		return
	var rest_members := preflight.get("rest_members", []) as Array
	if rest_members.is_empty():
		_complete_channels_shelter_rest(play_dialogue)
		return

	# Publish the story owner's COMMITTING record before the atomic command emits any ATP signal.
	_channels_shelter_rest_phase = "committing"
	_channels_shelter_rest_members.assign(rest_members)
	_channels_shelter_rest_commit_tick = float(_scheduler.get_current_tick())
	_channels_shelter_rest_commit_day = _game_state.get_game_day()
	_channels_shelter_rest_before_atp = (
		preflight.get("before_atp", {}) as Dictionary).duplicate(true)
	_apply_channels_shelter_rest_presentation()
	_publish_channels_runtime_authority()
	if not bool(_game_state.command_party_rest(_channels_shelter_rest_members)):
		_channels_shelter_rest_phase = "ready"
		_clear_channels_shelter_rest_context()
		_apply_channels_shelter_rest_presentation()
		_publish_channels_runtime_authority()
		show_preview_note("The party could not begin shelter rest yet.", 2.8)
		return
	_complete_channels_shelter_rest(play_dialogue)


func _on_act1_channels_shelter_requested(
		_interactable: Node, _world_position: Vector3
	) -> void:
	if _current_step != "channels_shelter" \
			or not _channels_shelter_reached \
			or _channels_shelter_rest_phase != "ready":
		return
	var blocked := (_preflight_act1_party_rest(
		CHANNELS_SHELTER_POS, CHANNELS_SHELTER_RADIUS,
		CHANNELS_PARTY_IDS).get("blocked", []) as Array)
	if not blocked.is_empty():
		show_preview_note(str(blocked[0]), 2.8)


## Compatibility probe for deterministic tapes; it cannot manufacture a hearth receipt.
func _recuperate_channels_party() -> bool:
	return false


func _complete_channels_shelter_rest(play_dialogue := false) -> void:
	if _channels_shelter_rest_phase == "rested":
		return
	if _scheduler != null:
		_scheduler.cancel_tag(CHANNELS_SHELTER_REST_TAG)
	_channels_shelter_rest_phase = "rested"
	_channels_party_recuperated = true
	_channels_shelter_reached = true
	_clear_channels_shelter_rest_context()
	_apply_channels_shelter_rest_presentation()
	_publish_channels_runtime_authority()
	_aster_hp = (
		_game_state.get_stat("aster", "hp")
		if _game_state != null and _game_state.characters.has("aster") else _aster_hp)
	_peris_hp = (
		_game_state.get_stat("peris", "hp")
		if _game_state != null and _game_state.characters.has("peris") else _peris_hp)
	if _current_step != "channels_shelter":
		return
	_tutorial_prompt.hide_prompt()
	if not play_dialogue:
		_start_channels_explore()
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"channels.narration.recuperate",
	], _queue_channels_explore)


func _queue_channels_explore() -> void:
	_schedule_portable_method(0.5, _start_channels_explore, "channels_explore")

func _start_channels_explore() -> void:
	if not _enter_step("channels_explore"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_enable_channels_optional_exploration()
	_tutorial_prompt.show_prompt("Optional records remain in the branches // continue to the Stacks when ready")

# --- Stacks ---

func _clear_channels_runtime_state() -> void:
	_stop_channels_authority_poll()
	_deactivate_channels_kit(true)
	_channels_flow_strips.clear()
	_channels_flush_enemy_ids.clear()
	_channels_swarm_enemy_ids.clear()
	_channels_coda_swept_ids.clear()
	_channels_encounter_spotted_ids.clear()
	_channels_window_lanes.clear()
	_channels_enemy_specs.clear()
	_channels_enemy_by_id.clear()
	_channels_enemy_scope_by_id.clear()
	_channels_channel_entries.clear()
	_channels_optional_sites.clear()
	_channels_optional_visuals.clear()
	_channels_optional_findings.clear()
	_channels_active_window_lane = ""
	_channels_flow_power = 0.0
	_channels_coda_phase = "idle"
	_channels_encounter_phase = "idle"
	_channels_flure = null
	_channels_flure_channel = null
	_channels_run_lure = null
	_channels_flures_bound = false
	_channels_shortcut_gate = null
	_channels_shortcut_gate_mesh = null
	_channels_shortcut_light = null
	_channels_shelter_interactable = null
	_iron_patches.clear()

func _reset_stacks_runtime_state() -> void:
	_stacks_support_log_entry_id = -1
	_stacks_support_log_presented = false
	_stacks_signal_interacted = false
	_stacks_terminal_interacted = false
	_stacks_archive_interacted = false
	_stacks_audit_flags_found = false
	_stacks_bank_samples.clear()
	_stacks_bank_resolved = false
	_stacks_bank_attempts = 0
	_stacks_last_commit = ""
	_stacks_failed_commits.clear()
	_stacks_anxiety_seen = false
	if is_instance_valid(_stacks_signal_interactable):
		_stacks_signal_interactable.reset()
		_stacks_signal_interactable.hide_tutorial_label()
	if is_instance_valid(_stacks_terminal_interactable):
		_stacks_terminal_interactable.reset()
		_stacks_terminal_interactable.hide_tutorial_label()
	if is_instance_valid(_stacks_workspace_interactable):
		_stacks_workspace_interactable.reset()
		_stacks_workspace_interactable.hide_tutorial_label()
	for interactable in _stacks_bank_interactables.values():
		if is_instance_valid(interactable):
			interactable.reset()
			interactable.set_interaction_enabled(true)
			interactable.hide_tutorial_label()
	_refresh_stacks_bank_presenters()
	if is_instance_valid(_stacks_shelter_interactable):
		_stacks_shelter_interactable.reset()
		_stacks_shelter_interactable.set_interaction_enabled(false)
		_stacks_shelter_interactable.hide_tutorial_label()

func _refresh_stacks_bank_presenters() -> void:
	for bank_id_v in StacksBankEvidence.BANK_IDS:
		var bank_id := str(bank_id_v)
		var sampled := bool(_stacks_bank_samples.get(bank_id, false))
		var readout := _stacks_bank_readouts.get(bank_id) as Label3D
		if is_instance_valid(readout):
			readout.text = StacksBankEvidence.observation_text(bank_id) if sampled else ""
			readout.visible = sampled
		var interactable = _stacks_bank_interactables.get(bank_id)
		if not is_instance_valid(interactable):
			continue
		interactable.description = (
			"Commit %s" if sampled else "Probe %s") % StacksBankEvidence.bank_title(bank_id)
		interactable.consequence_preview = (
			"Predict this bank retained the posted target trace"
			if sampled else "Sample this bank's three filter outcomes")
		interactable.tutorial_label = "COMMIT" if sampled else "PROBE"
		var tutorial_label_node := interactable.get_tutorial_label_node() as Label3D
		if is_instance_valid(tutorial_label_node):
			tutorial_label_node.text = InputLabels.expand(interactable.tutorial_label)

func _restore_stacks_bank_interactables() -> void:
	_refresh_stacks_bank_presenters()
	for interactable in _stacks_bank_interactables.values():
		if not is_instance_valid(interactable):
			continue
		interactable.reset()
		interactable.set_interaction_enabled(not _stacks_bank_resolved)
		if _stacks_bank_resolved or _current_step != "stacks_bank_audit":
			interactable.hide_tutorial_label()
		else:
			interactable.show_tutorial_label()


## The optional Stacks reads are sequence-owned one-shots rather than progression gates. Their
## presenter usage still has to follow the saved observation flags: a same-node rollback before a
## read must retract the discarded `_used` future, while a fresh load after a read must not offer a
## dead interaction that can only return from its callback. These flags are the portable truth for
## the observation; the Interactable is only its view.
func _restore_stacks_optional_interactables() -> void:
	_restore_sequence_one_shot_presenter(
		_stacks_terminal_interactable, _stacks_terminal_interacted,
		_current_step.begins_with("stacks"))
	_restore_sequence_one_shot_presenter(
		_stacks_signal_interactable, _stacks_signal_interacted,
		_current_step.begins_with("stacks"))
	_restore_sequence_one_shot_presenter(
		_stacks_workspace_interactable, _stacks_archive_interacted,
		_current_step.begins_with("stacks"))


func _restore_sequence_one_shot_presenter(
		interactable, completed: bool, available_in_step: bool
	) -> void:
	if not is_instance_valid(interactable):
		return
	if completed:
		interactable.set_interaction_enabled(false)
		interactable.hide_tutorial_label()
		return
	# reset() is essential on a reused presenter: loading a pre-interaction snapshot must erase a
	# discarded one-shot use just as replacing the node would on a fresh scene instance.
	interactable.reset()
	interactable.set_interaction_enabled(available_in_step)
	interactable.hide_tutorial_label()

func _ensure_stacks_support_log_entry() -> Dictionary:
	var journal: Node = get_node_or_null("/root/EngramJournal")
	if journal == null:
		return {}
	var context := {
		"scene_path": scene_file_path,
		"scene_name": "Act 1",
		"act": 1,
		"day": 1,
		"time_of_day": "maintenance_shift",
		"timestamp_label": "147 cycles ago",
		"location": "The Open Files Initiative",
		"sub_location": "Support Team Thread",
		"trigger_type": "story",
		"trigger_context": "support_team_log",
		"position": Vector3(STACKS_START.x + 88.0, 0.5, 0.0),
		"caption": "Maintenance thread surfaced from the old support logs",
	}
	var title := DialogueData.text("stacks.engram.support_log.title")
	var body := DialogueData.text("stacks.engram.support_log.body")
	return journal.ensure_story_log_entry(
		STACKS_SUPPORT_LOG_KEY,
		title,
		body,
		context,
		{
			"caption": "Support team maintenance log",
			"trigger_context": "support_team_log",
			"attached_data": {
				"channel": "#ependyma-core",
			},
		}
	)

## Presentation-only viewer for the log already acquired from the physical terminal. It cannot
## manufacture knowledge before that source interaction has committed.
func trigger_stacks_support_log() -> bool:
	if not _stacks_support_log_presented or _stacks_support_log_entry_id < 0:
		return false
	_present_stacks_support_log()
	return true

func close_stacks_engram_overlay() -> void:
	if _engram_overlay != null and _engram_overlay.visible:
		_engram_overlay.close_overlay()

func _present_stacks_support_log() -> void:
	_ensure_engram_overlay()
	if _engram_overlay == null:
		return
	_engram_overlay.open_overlay_for_entry(_stacks_support_log_entry_id)
	show_capture_message("Engram surfaced a maintenance log. J or Esc closes it.")

func _start_stacks_enter() -> void:
	_stop_iron_hazard_cadence()
	_stop_channels_authority_poll()
	_enter_step("stacks_enter")
	_tutorial_prompt.hide_prompt()
	_load_chunk("stacks")
	_unload_chunk("channels")
	_activate_chunk_grid("stacks")  # swap the live grid to the stacks footprint
	_clear_channels_runtime_state()
	_reset_stacks_runtime_state()
	_select_character("aster")
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.narration.enter",
		"stacks.aster.cores",
		"stacks.peris.noisy",
	], _start_stacks_bank_audit)

func _record_stacks_support_log_from_terminal() -> void:
	var entry := _ensure_stacks_support_log_entry()
	_stacks_support_log_presented = not entry.is_empty()
	_stacks_support_log_entry_id = int(entry.get("id", -1))


## Inert compatibility helper. Optional observations still require their exact world source.
func trigger_stacks_terminal(_play_dialogue := false) -> bool:
	return false


func _validate_act1_stacks_optional_trigger(
		source: Node, actor: String, expected_source: Node
	) -> bool:
	return source != null and source == expected_source \
		and _current_step.begins_with("stacks") \
		and actor == STACKS_BANK_ACTOR \
		and _act1_interaction_actor_ready_at(source, actor)


func _act1_stacks_optional_receipt_pending(
		source: Node, expected_source: Node
	) -> bool:
	return _validate_act1_stacks_optional_trigger(
			source, STACKS_BANK_ACTOR, expected_source) \
		and _act1_stacks_one_shot_receipt(source, STACKS_BANK_ACTOR)


func _on_act1_stacks_terminal_interacted(
		source: Node, play_dialogue := false
	) -> void:
	if not _current_step.begins_with("stacks") or _stacks_terminal_interacted:
		return
	if not _act1_stacks_optional_receipt_pending(
			source, _stacks_terminal_interactable):
		return
	_stacks_terminal_interacted = true
	_record_stacks_support_log_from_terminal()
	if is_instance_valid(_stacks_terminal_interactable):
		_stacks_terminal_interactable.hide_tutorial_label()
	if not play_dialogue:
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.aster.support_team",
		"stacks.aster.drink_machine",
		"stacks.peris.priorities",
		"stacks.narration.cleaned_terminal",
		"stacks.aster.cleaner_than_place",
		"stacks.aster.simplodrink",
		"stacks.peris.miss_machine",
		"stacks.aster.expectation",
	], _finish_stacks_terminal_dialogue)


func _finish_stacks_terminal_dialogue() -> void:
	if _current_step.begins_with("stacks") and _stacks_terminal_interacted:
		_player.set_move_enabled(true)

## Inert compatibility helper. Optional observations still require their exact world source.
func trigger_stacks_signal(_play_dialogue := false) -> bool:
	return false


func _on_act1_stacks_signal_interacted(
		source: Node, play_dialogue := false
	) -> void:
	if not _current_step.begins_with("stacks") or _stacks_signal_interacted:
		return
	if not _act1_stacks_optional_receipt_pending(
			source, _stacks_signal_interactable):
		return
	_stacks_signal_interacted = true
	if is_instance_valid(_stacks_signal_interactable):
		_stacks_signal_interactable.hide_tutorial_label()
	if not play_dialogue:
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.narration.instrumented_lane",
		"stacks.aster.nonstandard",
		"stacks.aster.metrics",
		"stacks.peris.damn_cooler",
		"stacks.aster.cooling_part",
		"stacks.peris.meaning",
		"stacks.aster.standardization",
	], _finish_stacks_signal_dialogue)


func _finish_stacks_signal_dialogue() -> void:
	if _current_step.begins_with("stacks") and _stacks_signal_interacted:
		_player.set_move_enabled(true)

func _start_stacks_bank_audit() -> void:
	if not _enter_step("stacks_bank_audit"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt(
		"Probe a bank, compare its result to the posted target, then revisit it to commit")
	for interactable in _stacks_bank_interactables.values():
		if is_instance_valid(interactable):
			interactable.reset()
			interactable.set_interaction_enabled(true)
			interactable.show_tutorial_label()

## Compatibility probe for external tests/tapes. Progress belongs to the real bank controls below.
func trigger_stacks_bank(_bank_id: String) -> bool:
	return false


func _validate_act1_stacks_bank_trigger(
		source: Node, actor: String, bank_id: String, expected_source: Node
	) -> bool:
	return source != null and source == expected_source \
		and _stacks_bank_interactables.get(bank_id) == source \
		and StacksBankEvidence.BANK_IDS.has(bank_id) \
		and actor == STACKS_BANK_ACTOR \
		and _current_step == "stacks_bank_audit" \
		and not _stacks_bank_resolved \
		and _act1_interaction_actor_ready_at(source, actor)


func _act1_interaction_actor_ready_at(source: Node, actor: String) -> bool:
	if _game_state == null or source == null or not (source is Node3D) \
			or not _game_state.characters.has(actor) \
			or not _game_state.is_narratively_available(actor) \
			or _game_state.is_downed(actor) \
			or _game_state.is_knocked_down(actor) \
			or _act1_interaction_character_busy(actor):
		return false
	var source_position := (source as Node3D).global_position
	if _game_state.coord_map != null and _game_state.coord_map.has_method("to_data"):
		source_position = _game_state.coord_map.to_data(source_position)
	var radius := float(source.get("interaction_radius")) \
		if source.get("interaction_radius") != null else 0.0
	return _rings_flat_distance(_game_state.get_position(actor), source_position) \
		<= radius + STACKS_INTERACTION_POSITION_TOLERANCE


func _act1_interaction_character_busy(actor: String) -> bool:
	return _game_state.is_moving(actor) \
		or _game_state.is_resting(actor) \
		or _game_state.is_dodging(actor) \
		or _game_state.is_endocytosing(actor) \
		or _game_state.is_external_traversal_active(actor) \
		or _game_state.is_dragging(actor) \
		or _game_state.is_field_restoring(actor)


func _act1_stacks_one_shot_receipt(source: Node, actor: String) -> bool:
	return source != null \
		and str(source.get("active_character")) == actor \
		and bool(source.get("one_shot")) \
		and bool(source.get("_used")) \
		and not bool(source.get("interaction_enabled"))


func _act1_stacks_bank_receipt_pending(source: Node, bank_id: String) -> bool:
	return _validate_act1_stacks_bank_trigger(
			source, STACKS_BANK_ACTOR, bank_id, source) \
		and _act1_stacks_one_shot_receipt(source, STACKS_BANK_ACTOR)


func _on_act1_stacks_bank_interacted(source: Node, bank_id: String) -> void:
	if _current_step != "stacks_bank_audit" or _stacks_bank_resolved:
		return
	if not StacksBankEvidence.BANK_IDS.has(bank_id) or not _stacks_bank_interactables.has(bank_id):
		return
	if source != _stacks_bank_interactables.get(bank_id) \
			or not _act1_stacks_bank_receipt_pending(source, bank_id):
		return
	_stacks_bank_attempts += 1
	var interactable = _stacks_bank_interactables.get(bank_id)
	if not _stacks_bank_samples.has(bank_id):
		_stacks_bank_samples[bank_id] = true
		_refresh_stacks_bank_presenters()
		show_preview_note(StacksBankEvidence.observation_text(bank_id), 4.2)
		_tutorial_prompt.show_prompt(
			"Probe another bank, or revisit a sampled bank to commit your prediction")
		if is_instance_valid(interactable):
			interactable.reset()
			interactable.show_tutorial_label()
		return

	_stacks_last_commit = bank_id
	if bank_id != StacksBankEvidence.solution_bank():
		_stacks_failed_commits.append(bank_id)
		show_preview_note(StacksBankEvidence.contradiction_text(bank_id), 4.2)
		_tutorial_prompt.show_prompt(
			"Prediction falsified. Inspect the probe results, then commit a revised prediction")
		if is_instance_valid(interactable):
			interactable.reset()
			interactable.show_tutorial_label()
		return

	_stacks_bank_resolved = true
	_tutorial_prompt.hide_prompt()
	show_preview_note(
		"Prediction confirmed: %s retains the posted target trace. The shelter ahead is safe to use."
		% StacksBankEvidence.bank_title(bank_id),
		3.4
	)
	for candidate in _stacks_bank_interactables.values():
		if is_instance_valid(candidate):
			candidate.hide_tutorial_label()
			candidate.set_interaction_enabled(false)
	_start_stacks_shelter()

## Inert compatibility helper. Optional observations still require their exact world source.
func trigger_stacks_archive(_play_dialogue := false) -> bool:
	return false


func _on_act1_stacks_archive_interacted(
		source: Node, play_dialogue := false
	) -> void:
	if not _current_step.begins_with("stacks") or _stacks_archive_interacted:
		return
	if not _act1_stacks_optional_receipt_pending(
			source, _stacks_workspace_interactable):
		return
	_stacks_archive_interacted = true
	_stacks_audit_flags_found = true
	if is_instance_valid(_stacks_workspace_interactable):
		_stacks_workspace_interactable.hide_tutorial_label()
	if not play_dialogue:
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.narration.workspace",
		"stacks.aster.pull_archive",
		"stacks.aster.ghost_ids",
		"stacks.peris.fake_permissions",
		"stacks.aster.security_patch",
		"stacks.aster.not_the_type",
		"stacks.aster.right",
	], _finish_stacks_archive_dialogue)


func _finish_stacks_archive_dialogue() -> void:
	if _current_step.begins_with("stacks") and _stacks_archive_interacted:
		_player.set_move_enabled(true)

func _start_stacks_shelter() -> void:
	if not _enter_step("stacks_shelter"):
		return
	if _stacks_rest_phase == "rested":
		_stacks_anxiety_seen = true
		_start_stacks_explore()
		return
	if _stacks_rest_phase == "locked":
		_stacks_rest_phase = "ready"
		_clear_act1_stacks_rest_context()
		_publish_act1_stacks_rest_authority()
	_select_character("peris")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Bring Aster, Peris, and Endo together, then REST at the shelter")
	_apply_act1_stacks_rest_presentation()

## Compatibility probe for external automation. The accepted shelter one-shot owns this consequence.
func trigger_stacks_shelter_rest(_play_dialogue := true) -> bool:
	return false


func _act1_stacks_shelter_receipt_pending(source: Node) -> bool:
	var actor := str(source.get("active_character")) if source != null else ""
	return _validate_act1_stacks_shelter_trigger(source, actor) \
		and _act1_stacks_one_shot_receipt(source, actor)


func _on_act1_stacks_shelter_interacted(
		source: Node, play_dialogue := true
	) -> void:
	if _current_step != "stacks_shelter" or _stacks_anxiety_seen \
			or not _stacks_bank_resolved or _stacks_rest_phase != "ready":
		return
	if source != _stacks_shelter_interactable \
			or not _act1_stacks_shelter_receipt_pending(source):
		return
	var preflight := _preflight_act1_party_rest(
		STACKS_SHELTER_POS, STACKS_SHELTER_REST_RADIUS, CHANNELS_PARTY_IDS)
	var blocked := preflight.get("blocked", []) as Array
	if not blocked.is_empty():
		show_preview_note(str(blocked[0]), 2.8)
		if is_instance_valid(_stacks_shelter_interactable):
			_stacks_shelter_interactable.reset()
			_apply_act1_stacks_rest_presentation()
		return
	var rest_members := preflight.get("rest_members", []) as Array
	if rest_members.is_empty():
		_complete_act1_stacks_shelter_rest(play_dialogue)
		return

	_stacks_rest_phase = "committing"
	_stacks_rest_members.assign(rest_members)
	_stacks_rest_commit_tick = float(_scheduler.get_current_tick())
	_stacks_rest_commit_day = _game_state.get_game_day()
	_stacks_rest_before_atp = (
		preflight.get("before_atp", {}) as Dictionary).duplicate(true)
	_apply_act1_stacks_rest_presentation()
	_publish_act1_stacks_rest_authority()
	if not bool(_game_state.command_party_rest(_stacks_rest_members)):
		_stacks_rest_phase = "ready"
		_clear_act1_stacks_rest_context()
		_apply_act1_stacks_rest_presentation()
		_publish_act1_stacks_rest_authority()
		show_preview_note("The party could not begin shelter rest yet.", 2.8)
		return
	_complete_act1_stacks_shelter_rest(play_dialogue)


func _validate_act1_stacks_shelter_trigger(
		source: Node, active_character: String
	) -> bool:
	if _current_step != "stacks_shelter" or _stacks_anxiety_seen \
			or not _stacks_bank_resolved or _stacks_rest_phase != "ready" \
			or source != _stacks_shelter_interactable \
			or active_character not in CHANNELS_PARTY_IDS \
			or not _act1_interaction_actor_ready_at(source, active_character):
		return false
	var preflight := _preflight_act1_party_rest(
		STACKS_SHELTER_POS, STACKS_SHELTER_REST_RADIUS, CHANNELS_PARTY_IDS)
	return (preflight.get("blocked", []) as Array).is_empty()


func _on_act1_stacks_shelter_requested(
		_interactable: Node, _world_position: Vector3
	) -> void:
	if _current_step != "stacks_shelter" or _stacks_rest_phase != "ready":
		return
	var blocked := (_preflight_act1_party_rest(
		STACKS_SHELTER_POS, STACKS_SHELTER_REST_RADIUS,
		CHANNELS_PARTY_IDS).get("blocked", []) as Array)
	if not blocked.is_empty():
		show_preview_note(str(blocked[0]), 2.8)


func _complete_act1_stacks_shelter_rest(play_dialogue := true) -> void:
	if _stacks_rest_phase == "rested":
		return
	if _scheduler != null:
		_scheduler.cancel_tag(ACT1_STACKS_REST_TAG)
	_stacks_rest_phase = "rested"
	_stacks_anxiety_seen = true
	_clear_act1_stacks_rest_context()
	_publish_act1_stacks_rest_authority()
	_tutorial_prompt.hide_prompt()
	_apply_act1_stacks_rest_presentation()
	if _current_step != "stacks_shelter":
		return
	if not play_dialogue:
		_start_stacks_explore()
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.rest.narration.open",
		"stacks.rest.narration.peris_quiet",
		"stacks.rest.peris.breath",
		"stacks.rest.peris.cant",
		"stacks.rest.peris.silence",
		"stacks.rest.peris.try_again",
		"stacks.rest.peris.scared",
		"stacks.rest.peris.ask",
		"stacks.rest.peris.wait_for_answer",
		"stacks.rest.aster.start",
		"stacks.rest.aster.models",
		"stacks.rest.aster.focus",
		"stacks.rest.aster.application",
		"stacks.rest.aster.peris",
		"stacks.rest.peris.listening",
		"stacks.rest.peris.huh",
		"stacks.rest.peris.focus",
		"stacks.rest.peris.breath_settles",
		"stacks.rest.aster.notice",
		"stacks.rest.peris.yeah",
		"stacks.rest.narration.close",
	], _queue_stacks_explore)


func _queue_stacks_explore() -> void:
	_schedule_portable_method(0.2, _start_stacks_explore, "stacks_explore")


func _clear_act1_stacks_rest_context() -> void:
	_stacks_rest_members.clear()
	_stacks_rest_commit_tick = -1.0
	_stacks_rest_commit_day = 0
	_stacks_rest_before_atp.clear()


func _act1_stacks_rest_authority_state() -> Dictionary:
	return {
		"version": ACT1_STACKS_REST_AUTHORITY_VERSION,
		"authority_id": ACT1_STACKS_REST_AUTHORITY_KEY,
		"phase": _stacks_rest_phase,
		"members": _stacks_rest_members.duplicate(),
		"commit_tick": _stacks_rest_commit_tick,
		"commit_day": _stacks_rest_commit_day,
		"before_atp": _stacks_rest_before_atp.duplicate(true),
	}


func _baseline_act1_stacks_rest_authority() -> Dictionary:
	return {
		"version": ACT1_STACKS_REST_AUTHORITY_VERSION,
		"authority_id": ACT1_STACKS_REST_AUTHORITY_KEY,
		"phase": "locked",
		"members": [],
		"commit_tick": -1.0,
		"commit_day": 0,
		"before_atp": {},
	}


func _valid_act1_stacks_rest_authority(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var saved := value as Dictionary
	var phase := str(saved.get("phase", ""))
	var members_v: Variant = saved.get("members", null)
	var before_v: Variant = saved.get("before_atp", null)
	if int(saved.get("version", 0)) != ACT1_STACKS_REST_AUTHORITY_VERSION \
			or str(saved.get("authority_id", "")) != ACT1_STACKS_REST_AUTHORITY_KEY \
			or phase not in ACT1_REST_PHASES \
			or not (members_v is Array) or not (before_v is Dictionary):
		return false
	var members := members_v as Array
	var before_atp := before_v as Dictionary
	if phase == "committing":
		if members.is_empty() or not _channels_stable_subset(members, CHANNELS_PARTY_IDS) \
				or float(saved.get("commit_tick", -1.0)) < 0.0:
			return false
		for char_id_v in members:
			if not before_atp.has(str(char_id_v)):
				return false
	elif not members.is_empty() or not before_atp.is_empty() \
			or float(saved.get("commit_tick", -1.0)) >= 0.0:
		return false
	return true


func _ensure_act1_stacks_rest_authority() -> void:
	if _game_state == null:
		return
	var raw: Variant = _game_state.get_world_state(
		ACT1_STACKS_REST_AUTHORITY_KEY, null)
	if _valid_act1_stacks_rest_authority(raw):
		_restore_act1_stacks_rest_authority_from_game_state()
		return
	_stacks_rest_phase = "locked"
	_clear_act1_stacks_rest_context()
	_game_state.set_world_state(
		ACT1_STACKS_REST_AUTHORITY_KEY, _baseline_act1_stacks_rest_authority())


func _publish_act1_stacks_rest_authority() -> void:
	if _restoring_stacks_rest_authority or _game_state == null:
		return
	_game_state.set_world_state(
		ACT1_STACKS_REST_AUTHORITY_KEY, _act1_stacks_rest_authority_state())


func _restore_act1_stacks_rest_authority_from_game_state() -> void:
	if _game_state == null:
		return
	if _scheduler != null:
		_scheduler.cancel_tag(ACT1_STACKS_REST_TAG)
	_restoring_stacks_rest_authority = true
	var raw: Variant = _game_state.get_world_state(
		ACT1_STACKS_REST_AUTHORITY_KEY, null)
	var saved := (
		(raw as Dictionary).duplicate(true)
		if _valid_act1_stacks_rest_authority(raw)
		else _baseline_act1_stacks_rest_authority())
	_stacks_rest_phase = str(saved.get("phase", "locked"))
	_stacks_rest_members.assign(saved.get("members", []))
	_stacks_rest_commit_tick = float(saved.get("commit_tick", -1.0))
	_stacks_rest_commit_day = int(saved.get("commit_day", 0))
	_stacks_rest_before_atp = (
		saved.get("before_atp", {}) as Dictionary).duplicate(true)
	_stacks_anxiety_seen = _stacks_rest_phase == "rested"
	_restoring_stacks_rest_authority = false
	_apply_act1_stacks_rest_presentation()
	if _stacks_rest_phase == "committing":
		_arm_act1_stacks_rest_callback()


func _apply_act1_stacks_rest_presentation() -> void:
	if not is_instance_valid(_stacks_shelter_interactable):
		return
	var ready := _current_step == "stacks_shelter" \
		and _stacks_bank_resolved and _stacks_rest_phase == "ready"
	_stacks_shelter_interactable.set_interaction_enabled(ready)
	if ready:
		_stacks_shelter_interactable.show_tutorial_label()
	else:
		_stacks_shelter_interactable.hide_tutorial_label()


func _arm_act1_stacks_rest_callback() -> void:
	if _scheduler == null or _stacks_rest_phase != "committing":
		return
	_scheduler.cancel_tag(ACT1_STACKS_REST_TAG)
	_scheduler.schedule_at(
		maxf(float(_scheduler.get_current_tick()), _stacks_rest_commit_tick),
		_resume_committed_act1_stacks_rest.bind(_stacks_rest_commit_tick),
		ACT1_STACKS_REST_TAG)


func _resume_committed_act1_stacks_rest(expected_tick: float) -> void:
	if _stacks_rest_phase != "committing" \
			or not is_equal_approx(_stacks_rest_commit_tick, expected_tick):
		return
	if _act1_party_rest_effect_matches(
			_stacks_rest_members, _stacks_rest_before_atp, _stacks_rest_commit_day):
		_complete_act1_stacks_shelter_rest(true)
		return
	var preflight := _preflight_act1_party_rest(
		STACKS_SHELTER_POS, STACKS_SHELTER_REST_RADIUS, CHANNELS_PARTY_IDS)
	if not _act1_rest_preflight_matches_intent(
			preflight,
			_stacks_rest_members,
			_stacks_rest_before_atp,
			_stacks_rest_commit_day):
		_stacks_rest_phase = "ready"
		_clear_act1_stacks_rest_context()
		_apply_act1_stacks_rest_presentation()
		_publish_act1_stacks_rest_authority()
		return
	if bool(_game_state.command_party_rest(_stacks_rest_members)):
		_complete_act1_stacks_shelter_rest(true)
	else:
		_stacks_rest_phase = "ready"
		_clear_act1_stacks_rest_context()
		_apply_act1_stacks_rest_presentation()
		_publish_act1_stacks_rest_authority()

func _start_stacks_explore() -> void:
	_enter_step("stacks_explore")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

# --- Rings ---

func rings_endo_departure_authority_key() -> String:
	return RINGS_ENDO_AUTHORITY_KEY


func _baseline_rings_endo_authority() -> Dictionary:
	return {
		"version": RINGS_ENDO_AUTHORITY_VERSION,
		"authority_id": rings_endo_departure_authority_key(),
		"phase": RINGS_ENDO_PHASE_PRESENT,
		"client_seen": false,
		"reassignment_actor": "",
		"reassignment_commit_tick": -1.0,
		"reassignment_positions": {},
		"start_tick": -1.0,
		"deadline": -1.0,
		"destination": [
			RINGS_ENDO_JUNCTION_POS.x,
			RINGS_ENDO_JUNCTION_POS.y,
			RINGS_ENDO_JUNCTION_POS.z,
		],
	}


func _rings_endo_authority_state() -> Dictionary:
	return {
		"version": RINGS_ENDO_AUTHORITY_VERSION,
		"authority_id": rings_endo_departure_authority_key(),
		"phase": _rings_endo_phase,
		"client_seen": _rings_client_seen,
		"reassignment_actor": _rings_reassignment_actor,
		"reassignment_commit_tick": _rings_reassignment_commit_tick,
		"reassignment_positions": _rings_reassignment_positions.duplicate(true),
		"start_tick": _rings_endo_departure_start_tick,
		"deadline": _rings_endo_departure_deadline,
		"destination": [
			RINGS_ENDO_JUNCTION_POS.x,
			RINGS_ENDO_JUNCTION_POS.y,
			RINGS_ENDO_JUNCTION_POS.z,
		],
	}


func _valid_rings_endo_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	var phase := str(saved.get("phase", ""))
	if int(saved.get("version", 0)) != RINGS_ENDO_AUTHORITY_VERSION \
			or str(saved.get("authority_id", "")) != rings_endo_departure_authority_key() \
			or phase not in RINGS_ENDO_VALID_PHASES:
		return false
	var destination_v: Variant = saved.get("destination", [])
	if not (destination_v is Array):
		return false
	var destination := destination_v as Array
	if destination.size() != 3 \
			or not is_equal_approx(float(destination[0]), RINGS_ENDO_JUNCTION_POS.x) \
			or not is_equal_approx(float(destination[1]), RINGS_ENDO_JUNCTION_POS.y) \
			or not is_equal_approx(float(destination[2]), RINGS_ENDO_JUNCTION_POS.z):
		return false
	var start_tick := float(saved.get("start_tick", -1.0))
	var deadline := float(saved.get("deadline", -1.0))
	var reassignment_actor := str(saved.get("reassignment_actor", ""))
	var reassignment_tick := float(saved.get("reassignment_commit_tick", -1.0))
	var positions_v: Variant = saved.get("reassignment_positions", {})
	if not positions_v is Dictionary:
		return false
	var reassignment_positions := positions_v as Dictionary
	match phase:
		RINGS_ENDO_PHASE_PRESENT:
			return not bool(saved.get("client_seen", true)) \
				and start_tick < 0.0 and deadline < 0.0 \
				and reassignment_actor.is_empty() and reassignment_tick < 0.0 \
				and reassignment_positions.is_empty()
		RINGS_ENDO_PHASE_DEPARTING:
			return bool(saved.get("client_seen", false)) \
				and start_tick >= 0.0 and deadline > start_tick \
				and reassignment_actor == RINGS_REASSIGNMENT_ACTOR \
				and reassignment_tick >= 0.0 and reassignment_tick <= start_tick \
				and _valid_rings_reassignment_positions(reassignment_positions)
		RINGS_ENDO_PHASE_DEPARTED:
			return bool(saved.get("client_seen", false)) \
				and start_tick >= 0.0 and deadline > start_tick \
				and reassignment_actor == RINGS_REASSIGNMENT_ACTOR \
				and reassignment_tick >= 0.0 and reassignment_tick <= start_tick \
				and _valid_rings_reassignment_positions(reassignment_positions)
		_:
			return false


func _valid_rings_reassignment_positions(positions: Dictionary) -> bool:
	if positions.size() != RINGS_REASSIGNMENT_REQUIRED_PARTY.size():
		return false
	var marco_position := _act1_rings_marco_position()
	for char_id in RINGS_REASSIGNMENT_REQUIRED_PARTY:
		var position_v: Variant = positions.get(char_id, null)
		if not position_v is Array or (position_v as Array).size() != 3:
			return false
		var position := GameEvent.arr_to_v3(position_v as Array)
		if not position.is_finite() \
				or _rings_flat_distance(position, marco_position) \
					> RINGS_REASSIGNMENT_GATHER_RADIUS:
			return false
	return true


func _publish_rings_endo_authority() -> void:
	if _restoring_rings_endo_authority or _game_state == null:
		return
	_game_state.set_world_state(
		rings_endo_departure_authority_key(), _rings_endo_authority_state())


func _restore_rings_endo_authority_from_game_state() -> void:
	if _game_state == null:
		return
	_restoring_rings_endo_authority = true
	var raw: Variant = _game_state.get_world_state(
		rings_endo_departure_authority_key(), null)
	var saved := _baseline_rings_endo_authority()
	if _valid_rings_endo_authority(raw):
		saved = (raw as Dictionary).duplicate(true)
	_apply_rings_endo_authority(saved)
	_restoring_rings_endo_authority = false


func _apply_rings_endo_authority(saved: Dictionary) -> void:
	_rings_endo_phase = str(saved.get("phase", RINGS_ENDO_PHASE_PRESENT))
	_rings_client_seen = bool(saved.get("client_seen", false))
	_rings_reassignment_actor = str(saved.get("reassignment_actor", ""))
	_rings_reassignment_commit_tick = float(saved.get("reassignment_commit_tick", -1.0))
	_rings_reassignment_positions = (
		saved.get("reassignment_positions", {}) as Dictionary).duplicate(true)
	_rings_endo_departure_start_tick = float(saved.get("start_tick", -1.0))
	_rings_endo_departure_deadline = float(saved.get("deadline", -1.0))
	var endo_is_registered := _game_state != null and _game_state.characters.has("endo")
	match _rings_endo_phase:
		RINGS_ENDO_PHASE_PRESENT:
			_clear_rings_reassignment_context()
			_endo.visible = endo_is_registered
		RINGS_ENDO_PHASE_DEPARTING:
			var traversal := _rings_endo_traversal_state()
			if not endo_is_registered or traversal.is_empty():
				# A semantic "departing" flag cannot mint its endpoint. A valid production save
				# carries the GameState traversal too; a mismatched record falls back to the
				# retryable pre-commit presentation instead of granting a load skip.
				_rings_endo_phase = RINGS_ENDO_PHASE_PRESENT
				_rings_client_seen = false
				_clear_rings_reassignment_context()
				_rings_endo_departure_start_tick = -1.0
				_rings_endo_departure_deadline = -1.0
				_endo.visible = endo_is_registered
			else:
				_endo.visible = true
				_endo.set_move_enabled(false)
				_current_step = "endo_departs"
		RINGS_ENDO_PHASE_DEPARTED:
			# Canonical completed saves already omit Endo from GameState. If a malformed
			# snapshot claims departure while retaining him, refuse to hide a live body.
			if endo_is_registered or _game_state.get_party().has("endo"):
				_rings_endo_phase = RINGS_ENDO_PHASE_PRESENT
				_rings_client_seen = false
				_clear_rings_reassignment_context()
				_rings_endo_departure_start_tick = -1.0
				_rings_endo_departure_deadline = -1.0
				_endo.visible = endo_is_registered
			else:
				_endo.visible = false
				_endo.set_move_enabled(false)
				if _current_step == "endo_departs":
					_current_step = "rings_explore"
	_apply_rings_departure_interactable_state()


func _clear_rings_reassignment_context() -> void:
	_rings_reassignment_actor = ""
	_rings_reassignment_commit_tick = -1.0
	_rings_reassignment_positions.clear()


func _apply_rings_departure_interactable_state() -> void:
	if not is_instance_valid(_rings_client_interactable):
		return
	var enabled := _rings_endo_phase == RINGS_ENDO_PHASE_PRESENT \
		and not _rings_client_seen
	_rings_client_interactable.set_interaction_enabled(enabled)
	if enabled:
		_rings_client_interactable.reset()


func _restore_rings_trace_interactables() -> void:
	var rings_active := _current_step.begins_with("rings") \
		or _current_step in ["endo_departs"]
	for trace_id_v in RINGS_AMBIENT_TRACE_IDS:
		var trace_id := str(trace_id_v)
		_restore_sequence_one_shot_presenter(
			_rings_trace_interactables.get(trace_id),
			bool(_rings_trace_seen.get(trace_id, false)),
			rings_active)


func _connect_rings_departure_signals() -> void:
	if _game_state == _rings_departure_signal_game_state:
		return
	if _rings_departure_signal_game_state != null \
			and is_instance_valid(_rings_departure_signal_game_state):
		if _rings_departure_signal_game_state.external_traversal_finished.is_connected(
				_on_rings_external_traversal_finished):
			_rings_departure_signal_game_state.external_traversal_finished.disconnect(
				_on_rings_external_traversal_finished)
		if _rings_departure_signal_game_state.external_traversal_cancelled.is_connected(
				_on_rings_external_traversal_cancelled):
			_rings_departure_signal_game_state.external_traversal_cancelled.disconnect(
				_on_rings_external_traversal_cancelled)
	_rings_departure_signal_game_state = _game_state
	if _game_state == null:
		return
	if not _game_state.external_traversal_finished.is_connected(
			_on_rings_external_traversal_finished):
		_game_state.external_traversal_finished.connect(
			_on_rings_external_traversal_finished)
	if not _game_state.external_traversal_cancelled.is_connected(
			_on_rings_external_traversal_cancelled):
		_game_state.external_traversal_cancelled.connect(
			_on_rings_external_traversal_cancelled)


func _rings_endo_traversal_state() -> Dictionary:
	if _game_state == null:
		return {}
	var traversal: Dictionary = _game_state.get_external_traversal_state("endo")
	if traversal.is_empty() or StringName(str(traversal.get("traversal_id", ""))) \
			!= RINGS_ENDO_TRAVERSAL_ID:
		return {}
	return traversal


func _reset_rings_runtime_state(recreate_endo := false) -> void:
	_restoring_rings_endo_authority = true
	if _game_state != null and not _rings_endo_traversal_state().is_empty():
		_game_state.cancel_external_traversal("endo", &"rings_reset")
	if recreate_endo and _game_state != null and not _game_state.characters.has("endo"):
		_game_state.register_character(
			"endo", RINGS_START + Vector3(5.0, 0.5, -1.8), 2.5,
			{"hp": CHANNELS_MAX_HP, "atp": 6.0})
	_rings_endo_phase = RINGS_ENDO_PHASE_PRESENT
	_rings_endo_departure_start_tick = -1.0
	_rings_endo_departure_deadline = -1.0
	_rings_client_seen = false
	_clear_rings_reassignment_context()
	_rings_trace_seen.clear()
	_endo.visible = _game_state != null and _game_state.characters.has("endo")
	if is_instance_valid(_rings_client_interactable):
		_rings_client_interactable.reset()
		_rings_client_interactable.set_interaction_enabled(true)
		_rings_client_interactable.hide_tutorial_label()
	for interactable in _rings_trace_interactables.values():
		if is_instance_valid(interactable):
			interactable.reset()
			interactable.set_interaction_enabled(true)
			interactable.hide_tutorial_label()
	_restoring_rings_endo_authority = false
	_publish_rings_endo_authority()

func _start_rings_enter() -> void:
	_enter_step("rings_enter")
	_tutorial_prompt.hide_prompt()
	_load_chunk("rings")
	_unload_chunk("stacks")
	_activate_chunk_grid("rings")  # swap the live grid to the rings footprint
	_reset_rings_runtime_state()
	_select_character("peris")
	_player.set_move_enabled(false)
	_dialogue_chain([
		"ring.entry.narration",
		"ring.entry.aster.home",
		"ring.entry.aster.machine",
		"ring.entry.peris.quiet",
		"ring.entry.endo.wall_touch",
		"ring.scatter.peris.notice",
		"ring.scatter.aster.continue",
	], _queue_rings_client)


func _queue_rings_client() -> void:
	_schedule_portable_method(0.2, _start_rings_client, "client")

func _start_rings_client() -> void:
	_enter_step("rings_client")
	_select_character("peris")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Take Peris to the former client")
	if is_instance_valid(_rings_client_interactable):
		_rings_client_interactable.reset()
		_rings_client_interactable.show_tutorial_label()


func _act1_rings_reassignment_preflight(require_semantic_receipt: bool) -> Dictionary:
	var outcome := {
		"complete": false,
		"actor": "",
		"positions": {},
		"blocked": [],
	}
	var blocked := outcome["blocked"] as Array
	if _current_step != "rings_client" or _rings_client_seen \
			or _rings_endo_phase != RINGS_ENDO_PHASE_PRESENT:
		blocked.append("Marco's reassignment conversation is not available.")
		return outcome
	if not is_instance_valid(_rings_client_interactable):
		blocked.append("Marco's world interaction is unavailable.")
		return outcome
	var actor := str(_rings_client_interactable.get("active_character"))
	if actor != RINGS_REASSIGNMENT_ACTOR:
		blocked.append("Peris must speak with Marco.")
		return outcome
	if require_semantic_receipt and (
			not bool(_rings_client_interactable.get("_used"))
			or bool(_rings_client_interactable.get("interaction_enabled"))):
		blocked.append("Speak with Marco through the world interaction.")
		return outcome
	outcome["actor"] = actor
	if _game_state == null:
		blocked.append("The party authority is unavailable.")
		return outcome
	var party := _game_state.get_party()
	var marco_position := _act1_rings_marco_position()
	for char_id in RINGS_REASSIGNMENT_REQUIRED_PARTY:
		if not _game_state.characters.has(char_id):
			blocked.append("%s is not present." % char_id.capitalize())
			continue
		if not party.has(char_id):
			blocked.append("%s is not in the available party." % char_id.capitalize())
			continue
		if not _game_state.is_narratively_available(char_id) \
				or _game_state.is_downed(char_id) \
				or _game_state.is_knocked_down(char_id):
			blocked.append("%s must be conscious." % char_id.capitalize())
			continue
		if _act1_rings_reassignment_character_busy(char_id):
			blocked.append("%s must finish their current action." % char_id.capitalize())
			continue
		var position := _game_state.get_position(char_id)
		(outcome["positions"] as Dictionary)[char_id] = GameEvent.v3_to_arr(position)
		if _rings_flat_distance(position, marco_position) \
				> RINGS_REASSIGNMENT_GATHER_RADIUS:
			blocked.append("%s must gather beside Marco." % char_id.capitalize())
	if blocked.is_empty():
		outcome["complete"] = true
	return outcome


func _validate_act1_rings_client_trigger(
		_interactable: Interactable, _active_character: String
	) -> bool:
	return bool(_act1_rings_reassignment_preflight(false).get("complete", false))


func _on_act1_rings_client_requested(
		_interactable: Node, _world_position: Vector3
	) -> void:
	var preflight := _act1_rings_reassignment_preflight(false)
	if bool(preflight.get("complete", false)):
		return
	var blocked := preflight.get("blocked", []) as Array
	show_preview_note(
		str(blocked[0]) if not blocked.is_empty()
		else "Peris and Endo must gather beside Marco.",
		2.8)


func _act1_rings_reassignment_character_busy(char_id: String) -> bool:
	return _game_state.is_moving(char_id) \
		or _game_state.is_resting(char_id) \
		or _game_state.is_dodging(char_id) \
		or _game_state.is_endocytosing(char_id) \
		or _game_state.is_external_traversal_active(char_id) \
		or _game_state.is_dragging(char_id) \
		or _game_state.is_field_restoring(char_id)


func _act1_rings_marco_position() -> Vector3:
	var position := Vector3(RINGS_START.x + 80.0, 0.5, -5.0)
	if is_instance_valid(_rings_client_interactable):
		position = _rings_client_interactable.global_position
		if _game_state != null and _game_state.coord_map != null \
				and _game_state.coord_map.has_method("to_data"):
			position = _game_state.coord_map.to_data(position)
	return position


func _rings_flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Retained for old automation callers only. Rings progression is a physical conversation:
## only the exact Marco node's post-trigger receipt may commit the reassignment.
func trigger_rings_client(_play_dialogue := true) -> bool:
	return false


func _act1_rings_client_receipt_pending(source: Node) -> bool:
	return is_instance_valid(source) \
			and source == _rings_client_interactable \
			and bool(source.get("_used")) \
			and not bool(source.get("interaction_enabled"))


func _on_act1_rings_client_interacted(
		source: Node, play_dialogue := true
	) -> void:
	if not _act1_rings_client_receipt_pending(source):
		return
	var preflight := _act1_rings_reassignment_preflight(true)
	if not bool(preflight.get("complete", false)):
		return
	_rings_reassignment_actor = str(preflight.get("actor", ""))
	_rings_reassignment_commit_tick = float(_scheduler.get_current_tick())
	_rings_reassignment_positions = (
		preflight.get("positions", {}) as Dictionary).duplicate(true)
	_rings_client_seen = true
	_tutorial_prompt.hide_prompt()
	if is_instance_valid(_rings_client_interactable):
		_rings_client_interactable.hide_tutorial_label()
	_start_endo_departs(play_dialogue)


func _start_endo_departs(play_dialogue := true) -> void:
	if _rings_endo_phase != RINGS_ENDO_PHASE_PRESENT or not _rings_client_seen:
		return
	_enter_step("endo_departs")
	_player.set_move_enabled(false)
	if not _begin_rings_endo_traversal():
		_current_step = "rings_client"
		_rings_client_seen = false
		_clear_rings_reassignment_context()
		_player.set_move_enabled(true)
		_apply_rings_departure_interactable_state()
		_publish_rings_endo_authority()
		show_preview_note(
			"Endo cannot use the junction while another action has control of him.", 3.2)
		return
	if play_dialogue:
		# Presentation rides beside the authoritative movement; it never owns the endpoint.
		# A save during these lines resumes Endo's exact GameState traversal even though
		# dialogue presentation itself is allowed to restart or clear on load.
		_dialogue_chain([
			"ring.marco.entry.narration",
			"ring.marco.entry.marco.warn",
			"ring.marco.entry.peris.name",
			"ring.marco.entry.marco.correct",
			"ring.reassignment.marco.pair",
			"ring.reassignment.peris.start",
			"ring.reassignment.marco.scatter",
			"ring.reassignment.peris.shift",
			"ring.marco.exit.marco.brief",
			"ring.marco.exit.narration",
			"ring.after_marco.aster.weird",
			"ring.after_marco.peris.quiet",
			"ring.after_marco.aster.move_on",
			"ring.after_marco.endo.watch",
			"ring.departure.narration",
			"ring.departure.aster.question",
			"ring.departure.peris.read",
			"ring.departure.endo.turn",
			"ring.departure.aster.delayed",
			"ring.departure.peris.explain",
			"ring.departure.aster.but",
			"ring.departure.peris.look",
			"ring.departure.aster.settle",
			"ring.departure.narration.closing",
		], Callable())
	else:
		show_preview_note("Endo is walking out through the outbound junction.", 3.2)


func _begin_rings_endo_traversal() -> bool:
	if _game_state == null or not _game_state.characters.has("endo"):
		return false
	if _active_character == "endo":
		_select_character("peris")
	var render_origin := _game_state.get_render_position("endo")
	var distance := render_origin.distance_to(RINGS_ENDO_JUNCTION_POS)
	var duration := maxf(
		RINGS_ENDO_MIN_DEPARTURE_DURATION,
		distance / RINGS_ENDO_DEPARTURE_SPEED)
	if not _game_state.command_external_traversal(
			"endo",
			RINGS_ENDO_TRAVERSAL_ID,
			RINGS_ENDO_JUNCTION_POS,
			render_origin,
			RINGS_ENDO_JUNCTION_POS,
			duration,
			&"locked"):
		return false
	var traversal := _rings_endo_traversal_state()
	if traversal.is_empty():
		return false
	_rings_endo_phase = RINGS_ENDO_PHASE_DEPARTING
	_rings_endo_departure_start_tick = float(traversal.get(
		"start_tick", _scheduler.get_current_tick()))
	_rings_endo_departure_deadline = float(traversal.get(
		"end_tick", _rings_endo_departure_start_tick + duration))
	_apply_rings_departure_interactable_state()
	_publish_rings_endo_authority()
	return true


func _on_rings_external_traversal_finished(
		char_id: String, traversal_id: StringName
	) -> void:
	if char_id != "endo" or traversal_id != RINGS_ENDO_TRAVERSAL_ID \
			or _rings_endo_phase != RINGS_ENDO_PHASE_DEPARTING:
		return
	_finalize_rings_endo_departure()


func _on_rings_external_traversal_cancelled(
		char_id: String, traversal_id: StringName, reason: StringName
	) -> void:
	if _restoring_rings_endo_authority or char_id != "endo" \
			or traversal_id != RINGS_ENDO_TRAVERSAL_ID \
			or _rings_endo_phase != RINGS_ENDO_PHASE_DEPARTING:
		return
	_rings_endo_phase = RINGS_ENDO_PHASE_PRESENT
	_rings_endo_departure_start_tick = -1.0
	_rings_endo_departure_deadline = -1.0
	_rings_client_seen = false
	_clear_rings_reassignment_context()
	_current_step = "rings_client"
	_endo.visible = _game_state != null and _game_state.characters.has("endo")
	_apply_rings_departure_interactable_state()
	_player.set_move_enabled(true)
	show_preview_note(
		"Endo's departure was interrupted (%s). Return to Marco to try again." % String(reason),
		3.2)
	_publish_rings_endo_authority()


func _finalize_rings_endo_departure() -> void:
	if _rings_endo_phase == RINGS_ENDO_PHASE_DEPARTED:
		return
	if _game_state == null or not _game_state.characters.has("endo") \
			or _game_state.get_position("endo").distance_to(RINGS_ENDO_JUNCTION_POS) \
			> RINGS_ENDO_ENDPOINT_EPSILON:
		return
	_rings_endo_phase = RINGS_ENDO_PHASE_DEPARTED
	if _active_character == "endo":
		_select_character("peris")
	_endo.visible = false
	var party: Array = _game_state.get_party()
	party.erase("endo")
	if _game_state.get_party() != party:
		_game_state.set_party(party)
	_game_state.unregister_character("endo")
	_apply_rings_departure_interactable_state()
	_publish_rings_endo_authority()
	_start_rings_explore()

## Inert compatibility helper. Ambient information is optional, but it must still be learned at
## the authored plant/door rather than injected as a dictionary key.
func trigger_rings_trace(_trace_id: String) -> bool:
	return false


func _validate_act1_rings_trace_trigger(
		source: Node, actor: String, trace_id: String, expected_source: Node
	) -> bool:
	return source != null and source == expected_source \
		and _rings_trace_interactables.get(trace_id) == source \
		and RINGS_AMBIENT_TRACE_IDS.has(trace_id) \
		and (_current_step.begins_with("rings") or _current_step == "endo_departs") \
		and not bool(_rings_trace_seen.get(trace_id, false)) \
		and actor == "peris" \
		and _act1_interaction_actor_ready_at(source, actor)


func _act1_rings_trace_receipt_pending(source: Node, trace_id: String) -> bool:
	return _validate_act1_rings_trace_trigger(
			source, "peris", trace_id, source) \
		and _act1_stacks_one_shot_receipt(source, "peris")


func _on_act1_rings_trace_interacted(source: Node, trace_id: String) -> void:
	if not RINGS_AMBIENT_TRACE_IDS.has(trace_id) \
			or not (_current_step.begins_with("rings") or _current_step == "endo_departs") \
			or bool(_rings_trace_seen.get(trace_id, false)):
		return
	if source != _rings_trace_interactables.get(trace_id) \
			or not _act1_rings_trace_receipt_pending(source, trace_id):
		return
	_rings_trace_seen[trace_id] = true
	var interactable = _rings_trace_interactables.get(trace_id)
	if is_instance_valid(interactable):
		interactable.hide_tutorial_label()
	var notes := {
		"client_bloom": "The bloom kept listening after the client stopped answering.",
		"forget_me_not": "The domestic trace turns inward: a familiar species, deliberately tended.",
		"doorvine": "Warmth remains behind this seal. Empty streets do not mean empty homes.",
	}
	show_preview_note(str(notes.get(trace_id, "The trace resolves.")), 3.2)

func _start_rings_explore() -> void:
	if _rings_endo_phase != RINGS_ENDO_PHASE_DEPARTED:
		return
	_enter_step("rings_explore")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

# --- Lockout ---

## Lockout begins after Endo's committed junction departure. A direct QA start must reconstruct
## that same roster instead of leaving an invisible, authoritative Endo body behind or an empty
## GameState party that makes the physical boundary scanner impossible to service.
func _prepare_lockout_party_authority() -> void:
	if _game_state == null:
		return
	if _game_state.characters.has(LOCKOUT_DEPARTED_CHARACTER_ID):
		_game_state.unregister_character(LOCKOUT_DEPARTED_CHARACTER_ID)
	var roster: Array[String] = []
	for char_id in LOCKOUT_PARTY_IDS:
		if _game_state.characters.has(char_id) \
				and _game_state.is_narratively_available(char_id):
			roster.append(char_id)
	if _game_state.get_party() != roster:
		_game_state.set_party(roster)


func _start_lockout_approach() -> void:
	_enter_step("lockout_approach")
	_tutorial_prompt.hide_prompt()
	_prepare_lockout_party_authority()
	_clear_lockout_runtime_state()
	_clear_channels_runtime_state()
	_lockout_chase_active = true
	_lockout_rejection_presented = false
	_lockout_dispatch_presented = false
	_lockout_chase_chunk = _load_chunk("lockout_chase_campaign")
	if not _activate_hosted_chunk_grid(_lockout_chase_chunk):
		_lockout_chase_active = false
		push_error("Lockout handoff aborted before unloading the current Act 1 district.")
		return
	_unload_chunk("rings")
	_unload_chunk("stacks")
	_unload_chunk("channels")
	if _lockout_chase_chunk != null:
		if _lockout_chase_chunk.has_method("set_pursuit_start_deferred"):
			_lockout_chase_chunk.call("set_pursuit_start_deferred", true)
		var rejection_callback := Callable(self, "_on_campaign_lockout_tags_rejected")
		if _lockout_chase_chunk.has_signal("tags_rejected") \
				and not _lockout_chase_chunk.is_connected("tags_rejected", rejection_callback):
			_lockout_chase_chunk.connect("tags_rejected", rejection_callback)
		var spawns := {}
		if _lockout_chase_chunk.has_method("get_spawn_positions"):
			spawns = _lockout_chase_chunk.call("get_spawn_positions")
		for char_id in ["aster", "peris"]:
			if spawns.has(char_id):
				set_preview_character_visible(char_id, true)
				set_preview_character_position(char_id, spawns[char_id])
	# Loading the data chunk publishes its own preview start step; restore the campaign step after
	# the host/grid/spawn hand-off, as the Endo stretch integration does.
	_current_step = "lockout_approach"
	_publish_act1_campaign_authority()
	_endo.visible = false
	_select_character("aster")
	_player.set_move_enabled(false)
	_dialogue_chain([
		"lockout.approach.narration",
		"lockout.approach.aster.confident",
	], _finish_lockout_approach_dialogue)


func _finish_lockout_approach_dialogue() -> void:
	if _current_step != "lockout_approach":
		return
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Present Aster and Peris's tags at the boundary scanner")

func _on_campaign_lockout_tags_rejected() -> void:
	if not _lockout_chase_active:
		return
	_tutorial_prompt.hide_prompt()
	if _lockout_rejection_presented:
		_start_lockout_chase()
	else:
		_start_lockout_rejected()

func _start_lockout_rejected() -> void:
	_enter_step("lockout_rejected")
	_player.set_move_enabled(false)
	_lockout_rejection_presented = true
	_publish_act1_campaign_authority()
	_dialogue_chain([
		"lockout.approach.panel_reject",
		"lockout.approach.aster.glitch",
		"lockout.approach.aster.retry",
		"lockout.approach.aster.confused",
		"lockout.escalate.aster.hack",
		"lockout.escalate.hack_block",
		"lockout.escalate.aster.recog",
		"lockout.escalate.aster.try_again",
		"lockout.escalate.peris.quiet",
		"lockout.escalate.peris_approaches",
		"lockout.escalate.aster.notices",
		"lockout.escalate.peris.dont",
	], _queue_lockout_chase)


func _queue_lockout_chase() -> void:
	_schedule_portable_method(0.2, _start_lockout_chase, "chase")

func _start_lockout_chase() -> void:
	_enter_step("lockout_chase")
	if _lockout_chase_active:
		var present_dispatch := not _lockout_dispatch_presented
		if present_dispatch:
			# Reserve the one-shot story overlay before the physical pursuit can emit any observer
			# signal. A signal-time save therefore cannot restart or silently omit the dispatch.
			_lockout_dispatch_presented = true
			_publish_act1_campaign_authority()
		if _lockout_chase_chunk != null and _lockout_chase_chunk.has_method("begin_deferred_pursuit"):
			_lockout_chase_chunk.call("begin_deferred_pursuit")
		_player.set_move_enabled(true)
		_tutorial_prompt.show_prompt("Run east to Endo's maintained wall")
		if not present_dispatch:
			return
		# These urgent lines ride over player-controlled movement; the pursuit scene remains sparse
		# and never turns its opening seconds into a stationary cutscene.
		_dialogue_chain([
			"lockout.dispatch.narration",
			"lockout.dispatch.aster.frozen",
			"lockout.dispatch.peris.hears",
			"lockout.dispatch.aster.pulled",
			"lockout.dispatch.peris.no",
			"lockout.dispatch.narration.start_chase",
			"lockout.chase.aster.lost",
			"lockout.chase.peris.listen",
		], _finish_lockout_dispatch_dialogue)
		return
	_dialogue_chain([
		"lockout.dispatch.narration",
		"lockout.dispatch.aster.frozen",
		"lockout.dispatch.peris.hears",
		"lockout.dispatch.aster.pulled",
		"lockout.dispatch.peris.no",
		"lockout.dispatch.narration.start_chase",
		"lockout.chase.aster.lost",
		"lockout.chase.peris.listen",
	], _finish_lockout_chase_dialogue)
	_spawn_lockout_naturalizers()


func _finish_lockout_dispatch_dialogue() -> void:
	# The pursuit is already authoritative and in motion. This named endpoint lets a save in the
	# overlaid urgent dialogue retire its portable continuation without inventing a side effect.
	pass


func _finish_lockout_chase_dialogue() -> void:
	if _current_step != "lockout_chase":
		return
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Run!")

func _start_lockout_exile() -> void:
	if not _enter_step("lockout_exile"):
		return
	_lockout_chase_active = false
	_publish_act1_campaign_authority()
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	# Stop Naturalizers
	for i in range(_naturalizers.size()):
		if _game_state.characters.has("nk_%d" % i):
			_game_state.command_stop("nk_%d" % i)
	_dialogue_chain([
		"lockout.chase.narration.boundary",
		"lockout.standoff.narration",
		"lockout.standoff.aster.try",
		"lockout.standoff.peris.back",
		"lockout.standoff.aster.cant_answer",
		"lockout.standoff.narration.silence",
		"lockout.aftermath.aster.watch",
		"lockout.aftermath.peris.answer",
		"lockout.aftermath.aster.sit",
		"lockout.aftermath.peris.sit",
		"lockout.aftermath.peris.ask_word",
		"lockout.aftermath.aster.fugacity",
		"lockout.aftermath.aster.clarify",
		"lockout.aftermath.peris.pressure",
		"lockout.aftermath.aster.laugh",
		"lockout.aftermath.peris.soft",
		"lockout.aftermath.narration.close",
	], _queue_act1_complete)


func _queue_act1_complete() -> void:
	_schedule_portable_method(2.0, _complete, "complete")

func _spawn_lockout_naturalizers() -> void:
	_clear_lockout_runtime_state()
	var chars := find_child("Characters", false, false)
	if chars == null:
		return
	for i in range(3):
		var nk := _create_npc("NK-%d" % (i + 1), Color(0.7, 0.7, 0.75))
		nk.position = LOCKOUT_BOUNDARY + Vector3(-2 + i * 2, 0.5, 0)
		chars.add_child(nk)
		_register_gs_character("nk_%d" % i, nk, 1.5)
		_game_state.command_move_to_pos("nk_%d" % i, _aster_node.global_position)
		_naturalizers.append(nk)

func _clear_lockout_runtime_state() -> void:
	if _lockout_chase_chunk != null and is_instance_valid(_lockout_chase_chunk):
		_unload_chunk("lockout_chase_campaign")
	_lockout_chase_chunk = null
	_lockout_chase_active = false
	_publish_act1_campaign_authority()
	for i in range(_naturalizers.size()):
		var nk := _naturalizers[i]
		if is_instance_valid(nk):
			nk.queue_free()
		if _game_state != null:
			var nk_id := "nk_%d" % i
			if _game_state.characters.has(nk_id):
				_game_state.unregister_character(nk_id)
	_naturalizers.clear()

# --- Endo's Junction to Shelter 1 (scene chunk, its own leg) ---

## Boot the Endo stretch as its own reachable leg: load the self-contained scene chunk (its
## attach_chunk_host wires it to act1), swap to its grid, teleport the full party onto the chunk's
## own spawn anchors (so its LOCAL station-distance checks line up), play a short intro, then hand
## control to the player. The chunk's interactables fire through act1 because the host interface is
## now inherited from tutorial_sequence; reach_shelter sets route_phase == "complete".

func _start_endo_junction_stretch_enter() -> void:
	if not _enter_step("endo_junction_stretch"):
		return
	_endo_junction_active = true
	_endo_junction_chunk = _load_chunk("endo_junction_stretch")
	if not _activate_hosted_chunk_grid(_endo_junction_chunk):
		_endo_junction_active = false
		push_error("Endo stretch handoff aborted before unloading Channels.")
		return
	_unload_chunk("channels")
	_clear_channels_runtime_state()

	var spawns := {}
	if _endo_junction_chunk != null and _endo_junction_chunk.has_method("get_spawn_positions"):
		spawns = _endo_junction_chunk.call("get_spawn_positions")
	for char_id in ["aster", "peris", "endo"]:
		if spawns.has(char_id):
			var node := _get_character_node(char_id)
			if node != null:
				node.visible = true
			set_preview_character_position(char_id, spawns[char_id])

	# The chunk already reset its story state in _build_chunk (on load). Re-set the step AFTER, because
	# the chunk's reset writes its own "..._start" step through set_preview_step (it shares _current_step).
	_current_step = "endo_junction_stretch"
	_publish_act1_campaign_authority()
	_select_character("endo")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_dialogue_chain([
		"endo_stretch.entry.aster_space",
		"endo_stretch.entry.peris_home",
		"endo_stretch.route.endo_gesture",
	], _finish_endo_junction_intro)


func _finish_endo_junction_intro() -> void:
	if _current_step != "endo_junction_stretch":
		return
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt(
		"Read Endo's junction, then choose the marked ledge or the pulsing bloom")

## The stretch resolved (party rested at Shelter 1). Hand off to the existing flow.
func _start_endo_junction_stretch_complete() -> void:
	if not _endo_junction_active:
		return
	_endo_junction_active = false
	_publish_act1_campaign_authority()
	_current_step = "endo_junction_stretch_complete"
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_unload_chunk("endo_junction_stretch")
	_schedule_portable_method(1.0, _start_stacks_enter, "endo_to_stacks")

func _complete() -> void:
	_enter_step("complete")
	_player.set_move_enabled(false)
	# Cosmetic fade; the scene hand-off rides the scheduler so fast-forward (and the
	# headless playthrough, which never advances tweens) reaches it at the same tick.
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color", Color(0.02, 0.02, 0.03, 1.0), 2.0)
	_schedule_portable_method(2.0, _handoff_to_leaving_facility, "complete_handoff")


func _handoff_to_leaving_facility() -> void:
	_change_scene_or_record("res://scenes/tutorial/leaving_facility.tscn")

# --- Chunk builders ---

func _build_channels_window_lane(
	parent: Node3D,
	window_id: String,
	stage_pos: Vector3,
	lure_pos: Vector3,
	curtain_pos: Vector3,
	goal_pos: Vector3,
	safe_duration: float
) -> void:
	var lane_root := Node3D.new()
	lane_root.name = "ChannelsWindowLane_%s" % window_id
	parent.add_child(lane_root)

	var side_sign := signf(lure_pos.z - stage_pos.z)
	var branch_dir := _channels_window_branch_direction(stage_pos, lure_pos)
	var cross_dir := _channels_window_cross_direction(branch_dir)
	var lane_floor_center := Vector3((stage_pos.x + goal_pos.x) * 0.5, -0.04, stage_pos.z)
	var lane_floor_size := Vector3(absf(goal_pos.x - stage_pos.x) + 8.0, 0.08, 7.0)
	_add_corridor_section(parent, lane_floor_center, lane_floor_size, Color(0.07, 0.085, 0.1))

	var lure_branch_center := Vector3((stage_pos.x + lure_pos.x) * 0.5, -0.04, (stage_pos.z + lure_pos.z) * 0.5)
	var lure_branch_size := Vector3(absf(lure_pos.x - stage_pos.x) + 5.0, 0.08, absf(lure_pos.z - stage_pos.z) + 4.0)
	_add_corridor_section(parent, lure_branch_center, lure_branch_size, Color(0.06, 0.075, 0.09))

	var stage_ring := MeshInstance3D.new()
	stage_ring.name = "ChannelsWindowStage_%s" % window_id
	var stage_ring_mesh := CylinderMesh.new()
	stage_ring_mesh.top_radius = 1.35
	stage_ring_mesh.bottom_radius = 1.35
	stage_ring_mesh.height = 0.04
	stage_ring.mesh = stage_ring_mesh
	var stage_ring_mat := StandardMaterial3D.new()
	stage_ring_mat.albedo_color = Color(0.18, 0.24, 0.3)
	stage_ring_mat.emission_enabled = true
	stage_ring_mat.emission = Color(0.18, 0.32, 0.46)
	stage_ring_mat.emission_energy_multiplier = 0.45
	stage_ring.material_override = stage_ring_mat
	stage_ring.position = stage_pos + Vector3(0.0, 0.03, 0.0)
	lane_root.add_child(stage_ring)

	var goal_beacon := MeshInstance3D.new()
	goal_beacon.name = "ChannelsWindowGoal_%s" % window_id
	var goal_beacon_mesh := CylinderMesh.new()
	goal_beacon_mesh.top_radius = 0.65
	goal_beacon_mesh.bottom_radius = 0.65
	goal_beacon_mesh.height = 0.12
	goal_beacon.mesh = goal_beacon_mesh
	var goal_beacon_mat := StandardMaterial3D.new()
	goal_beacon_mat.albedo_color = Color(0.3, 0.48, 0.56)
	goal_beacon_mat.emission_enabled = true
	goal_beacon_mat.emission = Color(0.32, 0.64, 0.76)
	goal_beacon_mat.emission_energy_multiplier = 0.5
	goal_beacon.material_override = goal_beacon_mat
	goal_beacon.position = goal_pos + Vector3(0.0, 0.06, 0.0)
	lane_root.add_child(goal_beacon)

	var goal_light := OmniLight3D.new()
	goal_light.position = goal_pos + Vector3(0.0, 1.6, 0.0)
	goal_light.light_color = Color(0.36, 0.78, 0.92)
	goal_light.light_energy = 1.4
	goal_light.omni_range = 8.0
	lane_root.add_child(goal_light)

	# The flower is a real reusable Flure. It is wired after the pack's stable IDs are known below,
	# and remains disabled until this particular window is the active intervention.
	var lure_interactable: Flure
	var curtain_nodes: Array = []

	var corpse_nodes: Array = []
	var corpse_center := stage_pos - branch_dir * 5.8 - cross_dir * 1.6
	var corpse_offsets := [
		Vector3.ZERO,
		cross_dir * 1.55 - branch_dir * 0.85,
		cross_dir * -1.35 + branch_dir * 0.75,
	]
	for i in range(corpse_offsets.size()):
		var corpse := MeshInstance3D.new()
		corpse.name = "ChannelsWindowCorpse_%s_%d" % [window_id, i]
		var corpse_mesh := CapsuleMesh.new()
		corpse_mesh.radius = 0.22 + 0.03 * float(i)
		corpse_mesh.height = 1.0 + 0.1 * float(i)
		corpse.mesh = corpse_mesh
		var corpse_mat := StandardMaterial3D.new()
		corpse_mat.albedo_color = Color(0.18, 0.16, 0.15).lerp(Color(0.24, 0.18, 0.16), float(i) * 0.2)
		corpse_mat.roughness = 0.95
		corpse.material_override = corpse_mat
		corpse.position = corpse_center + corpse_offsets[i] + Vector3(0.0, 0.28, 0.0)
		corpse.rotation_degrees = Vector3(88.0, 24.0 * float(i), 80.0 - 8.0 * float(i))
		lane_root.add_child(corpse)
		corpse_nodes.append(corpse)

	var bridge_points: Array = []
	var channel_specs: Array = []
	var channel_lateral_offsets := [-1.25, 1.3, -0.95]
	var swarm_start_pos := corpse_center + branch_dir * 0.95 + cross_dir * 0.15
	bridge_points.append(swarm_start_pos)
	bridge_points.append(stage_pos - branch_dir * 1.4 - cross_dir * 1.1)
	for i in range(CHANNELS_WINDOW_PERIODIC_CHANNELS):
		var t := float(CHANNELS_WINDOW_CHANNEL_T_VALUES[i])
		var lateral := float(channel_lateral_offsets[i % channel_lateral_offsets.size()])
		var approach := stage_pos.lerp(lure_pos, maxf(0.08, t - 0.055)) + cross_dir * (lateral * 0.72)
		var channel_pos := stage_pos.lerp(lure_pos, t) + cross_dir * lateral
		var exit := stage_pos.lerp(lure_pos, minf(0.9, t + 0.055)) + cross_dir * (-lateral * 0.42)
		if bridge_points[bridge_points.size() - 1].distance_to(approach) > 0.3:
			bridge_points.append(approach)
		bridge_points.append(channel_pos)
		channel_specs.append({
			"position": channel_pos,
			"path_index": bridge_points.size() - 1,
		})
		bridge_points.append(exit)
	bridge_points.append(lure_pos + branch_dir * 0.35 + cross_dir * 0.45)

	var bridge_segments: Array = []
	for i in range(bridge_points.size() - 1):
		bridge_segments.append(_add_channels_window_bridge_segment(
			lane_root,
			"ChannelsWindowBridge_%s_%d" % [window_id, i],
			bridge_points[i],
			bridge_points[i + 1]
		))

	var path_distances: Array = []
	var path_distance := 0.0
	for i in range(bridge_points.size()):
		if i == 0:
			path_distances.append(0.0)
			continue
		path_distance += bridge_points[i - 1].distance_to(bridge_points[i])
		path_distances.append(path_distance)

	var periodic_channels: Array = []
	var channel_contact_map := {}
	var flow_period := CHANNELS_WINDOW_FLOW_PERIOD
	var desired_spacing := flow_period / float(CHANNELS_WINDOW_PERIODIC_CHANNELS)
	for i in range(channel_specs.size()):
		var spec: Dictionary = channel_specs[i]
		var contact_path_index := int(spec.get("path_index", 0))
		var contact_time := float(path_distances[contact_path_index]) / CHANNELS_WINDOW_SWARM_SPEED
		var desired_start := fposmod(float(i) * desired_spacing, flow_period)
		var phase_offset := fposmod(-contact_time - desired_start, flow_period)
		var channel_tag := "act1_channels_%s_wash_%02d" % [window_id, i]
		var channel := _add_channels_channel(
			lane_root, channel_tag, window_id,
			(spec.get("position", Vector3.ZERO) as Vector3).x,
			CHANNELS_WINDOW_CHANNEL_HALF_WIDTH,
			CHANNELS_WINDOW_CHANNEL_HALF_LENGTH,
			flow_period, CHANNELS_WINDOW_FLOOD_DURATION, phase_offset)
		periodic_channels.append({
			"index": i,
			"position": spec.get("position", Vector3.ZERO),
			"path_index": contact_path_index,
			"contact_time": contact_time,
			"phase_offset": phase_offset,
			"channel": channel,
			"tag": channel_tag,
			"flooded": channel.is_flooding(),
		})
		channel_contact_map[contact_path_index] = i

	var enemy_ids: Array[String] = []
	for i in range(CHANNELS_WINDOW_SWARM_OFFSETS.size()):
		var base_pos: Vector3 = (
			swarm_start_pos
			+ cross_dir * (CHANNELS_WINDOW_SWARM_OFFSETS[i] * 0.65)
			+ branch_dir * (0.22 * float(i % 2) - 0.28)
		)
		var enemy_id := "act1_channels_%s_enemy_%02d" % [window_id, i]
		enemy_ids.append(enemy_id)
		_register_channels_enemy_spec(lane_root, {
			"id": enemy_id,
			"scope": window_id,
			"position": base_pos,
			"move_speed": CHANNELS_WINDOW_SWARM_SPEED,
			"detection_range": CHANNELS_WINDOW_DETECT_RADIUS,
			"color": Color(0.62, 0.22, 0.06),
		})

	lure_interactable = FlureScript.new()
	lure_interactable.name = "ChannelsWindowFlure_%s" % window_id
	lure_interactable.authority_id = "act1_channels_%s_flure" % window_id
	lure_interactable.configure(
		_game_state, lure_pos, enemy_ids, 48.0, 1.7, Color(0.92, 0.5, 0.2))
	lure_interactable.required_character = "peris"
	lure_interactable.dwell_time = 1.6
	lure_interactable.interactable_type = Interactable.InteractableType.TIMED_ACTION
	lure_interactable.lure_duration = safe_duration
	lure_interactable.settle_pos = lure_pos
	lure_interactable.one_shot = false
	parent.add_child(lure_interactable)
	register_preview_interactable(lure_interactable)
	lure_interactable.set_interaction_enabled(false)
	lure_interactable.hide_tutorial_label()
	lure_interactable.flure_activated.connect(
		_on_channels_window_flure_activated.bind(window_id))

	var attract_pos := curtain_pos + Vector3(0.0, 0.0, side_sign * 9.0)
	var lane := {
		"stage_pos": stage_pos,
		"lure_pos": lure_pos,
		"goal_pos": goal_pos,
		"curtain_pos": curtain_pos,
		"attract_pos": attract_pos,
		"safe_duration": safe_duration,
		"curtain_nodes": curtain_nodes,
		"interactable": lure_interactable,
		"phase": "idle",
		"safe_until_tick": -1.0,
		"retry_deadline": -1.0,
		"last_outcome": "",
		"lure_active": false,
		"branch_dir": branch_dir,
		"cross_dir": cross_dir,
		"swarm_start_pos": swarm_start_pos,
		"swarm_path": bridge_points,
		"channel_contact_map": channel_contact_map,
		"flow_period": flow_period,
		"flood_duration": CHANNELS_WINDOW_FLOOD_DURATION,
		"flow_offset": 0.0,
		"periodic_channels": periodic_channels,
		"bridge_segments": bridge_segments,
		"corpse_nodes": corpse_nodes,
		"enemy_ids": enemy_ids,
		"swept_ids": [],
		"swarm_state": "idle",
		"wash_analysis": {},
	}
	lane["wash_analysis"] = _channels_window_wash_analysis(lane)
	lane = _reset_channels_window_swarm(lane)
	_channels_window_lanes[window_id] = lane

func _channels_optional_role_color(role: String) -> Color:
	match role:
		"aster":
			return Color(0.30, 0.68, 1.0)
		"peris":
			return Color(0.95, 0.68, 0.30)
		"endo":
			return Color(0.38, 0.76, 0.55)
		_:
			return Color(0.72, 0.74, 0.76)

func _add_channels_optional_station_visual(site: Node3D, site_id: String, spec: Dictionary) -> Node3D:
	var assembly := Node3D.new()
	assembly.name = "ChannelsOptionalAssembly_%s" % site_id
	site.add_child(assembly)
	var role := str(spec.get("role", ""))
	var role_color := _channels_optional_role_color(role)
	var kind := str(spec.get("kind", "optional"))
	var operation_tint := role_color
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Color(0.075, 0.09, 0.095).lerp(role_color.darkened(0.4), 0.32)
	base_material.metallic = 0.42
	base_material.roughness = 0.58
	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = operation_tint.darkened(0.24)
	glow_material.emission_enabled = true
	glow_material.emission = operation_tint
	glow_material.emission_energy_multiplier = 1.15 if kind == "choice" else 0.58
	glow_material.metallic = 0.18
	glow_material.roughness = 0.42

	var footing := MeshInstance3D.new()
	footing.name = "MeasuredFooting"
	var footing_mesh := CylinderMesh.new()
	footing_mesh.top_radius = 0.54 if kind == "choice" else 0.42
	footing_mesh.bottom_radius = 0.68 if kind == "choice" else 0.56
	footing_mesh.height = 0.22
	footing.mesh = footing_mesh
	footing.material_override = base_material
	footing.position.y = 0.11
	assembly.add_child(footing)

	var body := MeshInstance3D.new()
	body.name = "InstrumentBody"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.72 if kind == "choice" else 0.54, 1.05, 0.52)
	body.mesh = body_mesh
	body.material_override = base_material
	body.position.y = 0.73
	assembly.add_child(body)

	var face := MeshInstance3D.new()
	face.name = "InstrumentReadout"
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(0.58 if kind == "choice" else 0.42, 0.26, 0.055)
	face.mesh = face_mesh
	face.material_override = glow_material
	face.position = Vector3(0, 0.92, -0.29)
	assembly.add_child(face)
	for band_i in range(3):
		var band := MeshInstance3D.new()
		band.name = "MeasuredBand%d" % band_i
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.12, 0.05, 0.06)
		band.mesh = band_mesh
		band.material_override = glow_material
		band.position = Vector3(-0.18 + float(band_i) * 0.18, 0.50, -0.30)
		assembly.add_child(band)

	# These two sites are fixed evidence, not abstract loot pickups. Give each a
	# distinct silhouette that depicts the thing being inspected/read and leave
	# that assembly in the world after the one-shot finding is recorded.
	if site_id == "optional_seed_cache":
		var cradle := MeshInstance3D.new()
		cradle.name = "SeedCacheCradle"
		var cradle_mesh := BoxMesh.new()
		cradle_mesh.size = Vector3(1.55, 0.20, 0.84)
		cradle.mesh = cradle_mesh
		cradle.material_override = base_material
		cradle.position = Vector3(0.0, 0.38, 0.46)
		cradle.rotation_degrees.x = 8.0
		assembly.add_child(cradle)
		for pod_i in range(4):
			var pod := MeshInstance3D.new()
			pod.name = "SealedSeedPod%d" % pod_i
			var pod_mesh := SphereMesh.new()
			pod_mesh.radius = 0.17
			pod_mesh.height = 0.46
			pod.mesh = pod_mesh
			pod.material_override = glow_material
			pod.position = Vector3(-0.54 + float(pod_i) * 0.36, 0.62, 0.43)
			pod.rotation_degrees.z = 90.0
			assembly.add_child(pod)
	elif site_id == "optional_report_stub":
		var lectern := MeshInstance3D.new()
		lectern.name = "ReportLectern"
		var lectern_mesh := BoxMesh.new()
		lectern_mesh.size = Vector3(1.28, 0.16, 0.94)
		lectern.mesh = lectern_mesh
		lectern.material_override = base_material
		lectern.position = Vector3(0.0, 1.14, 0.20)
		lectern.rotation_degrees.x = -24.0
		assembly.add_child(lectern)
		var page_material := StandardMaterial3D.new()
		page_material.albedo_color = Color(0.72, 0.73, 0.66)
		page_material.roughness = 0.92
		var page := MeshInstance3D.new()
		page.name = "FixedReportPage"
		var page_mesh := BoxMesh.new()
		page_mesh.size = Vector3(0.92, 0.035, 0.66)
		page.mesh = page_mesh
		page.material_override = page_material
		page.position = Vector3(0.0, 1.24, 0.11)
		page.rotation_degrees.x = -24.0
		assembly.add_child(page)
		for line_i in range(4):
			var line := MeshInstance3D.new()
			line.name = "ReportLine%d" % line_i
			var line_mesh := BoxMesh.new()
			line_mesh.size = Vector3(0.58 - float(line_i % 2) * 0.14, 0.025, 0.035)
			line.mesh = line_mesh
			line.material_override = glow_material
			line.position = Vector3(-0.08, 1.34 - float(line_i) * 0.10, -0.03 + float(line_i) * 0.044)
			line.rotation_degrees.x = -24.0
			assembly.add_child(line)

	# The top silhouette carries role, not arbitrary prop scatter: Aster gets a data vane, Peris a
	# living fork, Endo a brace bar. Players can read who will service a site from across a bay.
	match role:
		"aster":
			var vane := MeshInstance3D.new()
			vane.name = "DataVane"
			var vane_mesh := BoxMesh.new()
			vane_mesh.size = Vector3(0.08, 0.62, 0.42)
			vane.mesh = vane_mesh
			vane.material_override = glow_material
			vane.position = Vector3(0, 1.54, 0)
			vane.rotation_degrees.z = 24.0
			assembly.add_child(vane)
		"peris":
			for fork_x in [-0.16, 0.16]:
				var fork := MeshInstance3D.new()
				fork.name = "LivingFork"
				var fork_mesh := CylinderMesh.new()
				fork_mesh.top_radius = 0.045
				fork_mesh.bottom_radius = 0.065
				fork_mesh.height = 0.68
				fork.mesh = fork_mesh
				fork.material_override = glow_material
				fork.position = Vector3(float(fork_x), 1.54, 0)
				fork.rotation_degrees.z = -16.0 if float(fork_x) < 0.0 else 16.0
				assembly.add_child(fork)
		"endo":
			var brace := MeshInstance3D.new()
			brace.name = "BraceBar"
			var brace_mesh := BoxMesh.new()
			brace_mesh.size = Vector3(0.92, 0.12, 0.14)
			brace.mesh = brace_mesh
			brace.material_override = glow_material
			brace.position = Vector3(0, 1.48, 0)
			brace.rotation_degrees.z = -12.0
			assembly.add_child(brace)

	var label := Label3D.new()
	label.name = "MeasuredLabel"
	label.text = "%s // %s" % [role.to_upper(), str(spec.get("display", site_id)).to_upper()]
	label.font_size = 34
	label.pixel_size = 0.0075
	label.modulate = operation_tint.lightened(0.24)
	label.outline_modulate = Color(0.01, 0.015, 0.018, 0.96)
	label.outline_size = 10
	label.position = Vector3(0, 2.10, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	assembly.add_child(label)
	return assembly

func _bind_channels_optional_site_outline(site: Node3D, assembly: Node3D, site_id: String) -> void:
	if not is_instance_valid(site) or not is_instance_valid(assembly):
		return
	var target := _outline_object_meshes(
		site, "ChannelsOptionalOutline_%s" % site_id, _collect_mesh_instances(assembly),
		"channels.optional.%s" % site_id, 0.85
	)
	_set_room_target_interaction_delegate(target, site)

func _spawn_channels_optional_site(parent: Node3D, site_id: String, spec: Dictionary) -> void:
	var role := str(spec.get("role", ""))
	var site = InteractableFactory.spawn(
		_game_state, parent, "ChannelsOptional_%s" % site_id,
		{
			"position": spec.get("pos", Vector3.ZERO),
			"radius": 1.7,
			"hold_time": float(spec.get("dwell", 0.0)),
			"one_shot": true,
			"requires_hold": false,
			"interactable_type": Interactable.InteractableType.TIMED_ACTION,
			"required_character": role,
			"tutorial_label": str(spec.get("verb", "INSPECT")),
			"description": str(spec.get("display", site_id)),
			"enabled": false,
		},
		_scheduler, _dialogue, _active_character
	)
	site.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	site.set("required_character", role)
	site.set_interaction_enabled(false)
	site.set("selected_feedback_color", _channels_optional_role_color(role))
	site.set("outline_highlight_radius", 1.4)
	site.interacted.connect(Callable(self, "_on_channels_optional_site_interacted").bind(site_id))
	site.interaction_requested.connect(Callable(self, "_on_channels_optional_route_requested").bind(site_id))
	register_preview_interactable(site)
	var assembly := _add_channels_optional_station_visual(site, site_id, spec)
	_channels_optional_sites[site_id] = site
	_channels_optional_visuals[site_id] = assembly
	assembly.visible = false
	call_deferred("_bind_channels_optional_site_outline", site, assembly, site_id)

func _build_channels_optional_worldbuilding(parent: Node3D) -> void:
	_channels_optional_sites.clear()
	_channels_optional_visuals.clear()
	var root := Node3D.new()
	root.name = "ChannelsOptionalWorldbuilding"
	parent.add_child(root)
	for site_id_variant in CHANNELS_OPTIONAL_SITES.keys():
		var site_id := str(site_id_variant)
		_spawn_channels_optional_site(root, site_id, CHANNELS_OPTIONAL_SITES[site_id])
func _build_channels_chunk(parent: Node3D) -> void:
	var sx := CHANNELS_START.x
	var length := CHANNELS_END.x - CHANNELS_START.x
	var width := 50.0
	var floor_color := Color(0.06, 0.08, 0.1)
	var wall_color := Color(0.08, 0.08, 0.1)
	_channels_flow_strips.clear()
	_channels_flush_enemy_ids.clear()
	_channels_swarm_enemy_ids.clear()
	_channels_window_lanes.clear()
	_channels_enemy_specs.clear()
	_channels_enemy_by_id.clear()
	_channels_enemy_scope_by_id.clear()
	_channels_channel_entries.clear()
	_channels_kit_active = false
	_channels_flures_bound = false
	_channels_active_window_lane = ""
	_channels_shortcut_unlocked = false
	_channels_party_recuperated = false
	_channels_shelter_reached = false
	_channels_shelter_rest_phase = "locked"
	_clear_channels_shelter_rest_context()
	_channels_coda_phase = "idle"
	_channels_coda_swept_ids.clear()
	_channels_encounter_spotted_ids.clear()
	_channels_flow_power = 0.0

	# Main corridor ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Outer walls
	_add_wall(parent, Vector3(sx + length / 2.0, 1.5, -width / 2.0), Vector3(length, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 1.5, width / 2.0), Vector3(length, 3, 0.3), wall_color)

	# Flowing water channels along the main path (blue-tinted strips)
	for i in range(6):
		var water := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(length * 0.8, 0.02, 2.0)
		water.mesh = wb
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.1, 0.15, 0.2)
		wm.emission_enabled = true
		wm.emission = Color(0.05, 0.08, 0.12)
		wm.emission_energy_multiplier = 0.3
		water.material_override = wm
		water.position = Vector3(sx + length / 2.0, 0.01, -15.0 + i * 6.0)
		parent.add_child(water)
		_channels_flow_strips.append(water)

	# Side branches (3 alcoves off the main path for exploration)
	for i in range(3):
		var branch_x: float = sx + 50.0 + i * 60.0
		var branch_z: float = -width / 2.0 + 5.0 if i % 2 == 0 else width / 2.0 - 5.0
		var branch_sign: float = 1.0 if branch_z > 0 else -1.0
		# Alcove floor
		_add_corridor_section(parent, Vector3(branch_x, -0.04, branch_z + branch_sign * 10.0), Vector3(15, 0.08, 12), Color(0.05, 0.06, 0.08))
		# Alcove walls
		_add_wall(parent, Vector3(branch_x - 8.0, 1.5, branch_z + branch_sign * 10.0), Vector3(0.3, 3, 12), wall_color)
		_add_wall(parent, Vector3(branch_x + 8.0, 1.5, branch_z + branch_sign * 10.0), Vector3(0.3, 3, 12), wall_color)

	# Stagnant pools with iron deposits (multiple, spread out)
	for i in range(4):
		var sp_x: float = sx + 40.0 + i * 50.0
		# These positions are collision/damage truth, not decorative scatter. Keep them stable so a
		# fresh presenter and deterministic replay rebuild the same hazard under the saved party.
		var sp_z: float = (8.0 if i % 2 == 0 else -8.0) + CHANNELS_IRON_Z_OFFSETS[i]
		var sp_pos := Vector3(sp_x, 0.02, sp_z)
		var sp_size := Vector3(8, 0.04, 6)
		var stagnant := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = sp_size
		stagnant.mesh = sb
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.2, 0.12, 0.06)
		sm.emission_enabled = true
		sm.emission = Color(0.15, 0.06, 0.02)
		sm.emission_energy_multiplier = 0.2
		stagnant.material_override = sm
		stagnant.position = sp_pos
		parent.add_child(stagnant)
		_iron_patches.append({"pos": sp_pos, "size": sp_size})

	# Body in the drainage path grounds the memory reconstruction and the following story beat.
	var body := MeshInstance3D.new()
	body.name = "ChannelsBody"
	var corpse_mesh := CapsuleMesh.new()
	corpse_mesh.radius = 0.28
	corpse_mesh.height = 1.3
	body.mesh = corpse_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.2, 0.18, 0.16)
	body_mat.roughness = 0.9
	body.material_override = body_mat
	body.position = CHANNELS_BODY_POS
	body.rotation_degrees = Vector3(0, 0, 88)
	parent.add_child(body)

	for i in range(2):
		var memory_body := MeshInstance3D.new()
		var memory_mesh := CapsuleMesh.new()
		memory_mesh.radius = 0.22
		memory_mesh.height = 1.1
		memory_body.mesh = memory_mesh
		var memory_mat := StandardMaterial3D.new()
		memory_mat.albedo_color = Color(0.16, 0.18, 0.22)
		memory_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		memory_mat.albedo_color.a = 0.45
		memory_body.material_override = memory_mat
		memory_body.position = Vector3(sx + 48.0 + i * 14.0, 0.38, -10.0 + i * 6.0)
		memory_body.rotation_degrees = Vector3(0, 0, 90)
		parent.add_child(memory_body)

	# The coda reuses the exact same causal grammar as the playable windows: Peris tends a real
	# Flure, real Enemy bodies accept its lure through their FSM, and a real Channel catches them.
	# The flower is disabled until the party physically reaches this beat.
	_set_channels_flow_power(0.25)

	for i in range(CHANNELS_FLUSH_SWARM_OFFSETS.size()):
		var enemy_id := "act1_channels_coda_enemy_%02d" % i
		_channels_flush_enemy_ids.append(enemy_id)
		_register_channels_enemy_spec(parent, {
			"id": enemy_id,
			"scope": "coda",
			"position": CHANNELS_FLUSH_SWARM_POS + Vector3(
				CHANNELS_FLUSH_SWARM_OFFSETS[i], 0.0, sin(float(i) * 1.4) * 0.8),
			"move_speed": CHANNELS_WINDOW_SWARM_SPEED,
			"detection_range": 1.8,
			"color": Color(0.52, 0.20, 0.06),
		})
	_channels_flure = FlureScript.new()
	_channels_flure.name = "ChannelsCodaFlure"
	_channels_flure.authority_id = CHANNELS_CODA_FLURE_ID
	_channels_flure.configure(
		_game_state, CHANNELS_FLURE_POS, _channels_flush_enemy_ids,
		42.0, 1.7, Color(0.32, 0.78, 0.45))
	_channels_flure.required_character = "peris"
	_channels_flure.dwell_time = 1.6
	_channels_flure.interactable_type = Interactable.InteractableType.TIMED_ACTION
	_channels_flure.lure_duration = 18.0
	# The current is physically between the pack and the flower. The settle point continues past
	# the water so a mistimed dry phase remains legible; it is not a magic collision at activation.
	_channels_flure.settle_pos = CHANNELS_FLURE_POS + Vector3(-2.5, 0.0, 0.0)
	_channels_flure.one_shot = false
	parent.add_child(_channels_flure)
	register_preview_interactable(_channels_flure)
	_channels_flure.set_interaction_enabled(false)
	_channels_flure.hide_tutorial_label()
	_channels_flure.flure_activated.connect(_on_channels_coda_flure_activated)
	_channels_flure_channel = _add_channels_channel(
		parent, CHANNELS_CODA_CHANNEL_TAG, "coda",
		CHANNELS_FLURE_POS.x + 2.0, 1.1, 18.0,
		CHANNELS_WINDOW_FLOW_PERIOD, CHANNELS_WINDOW_FLOOD_DURATION, 0.0)

	_build_channels_window_lane(
		parent,
		"window_one",
		CHANNELS_WINDOW_ONE_STAGE_POS,
		CHANNELS_WINDOW_ONE_LURE_POS,
		CHANNELS_WINDOW_ONE_CURTAIN_POS,
		CHANNELS_WINDOW_ONE_GOAL_POS,
		CHANNELS_WINDOW_ONE_DURATION
	)
	_build_channels_window_lane(
		parent,
		"window_two",
		CHANNELS_WINDOW_TWO_STAGE_POS,
		CHANNELS_WINDOW_TWO_LURE_POS,
		CHANNELS_WINDOW_TWO_CURTAIN_POS,
		CHANNELS_WINDOW_TWO_GOAL_POS,
		CHANNELS_WINDOW_TWO_DURATION
	)

	# The encounter Flure is constructed after its stable Enemy roster below, so the reusable
	# object's saved target list is complete from its first authoritative record.

	# Hide alcove near the shelter route.
	_channels_hide_spot = Node3D.new()
	_channels_hide_spot.name = "ChannelsHideSpot"
	_channels_hide_spot.position = CHANNELS_HIDE_SPOT_POS
	parent.add_child(_channels_hide_spot)
	_add_corridor_section(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x, -0.04, CHANNELS_HIDE_SPOT_POS.z), Vector3(10, 0.08, 8), Color(0.05, 0.05, 0.07))
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x, 1.5, CHANNELS_HIDE_SPOT_POS.z + 4.0), Vector3(10, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x - 5.0, 1.5, CHANNELS_HIDE_SPOT_POS.z), Vector3(0.3, 3, 8), wall_color)
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x + 5.0, 1.5, CHANNELS_HIDE_SPOT_POS.z), Vector3(0.3, 3, 8), wall_color)

	# Swarm cluster guarding the stretch before the shelter.
	_channels_swarm_enemy_ids.clear()
	for i in range(CHANNELS_SWARM_OFFSETS.size()):
		var enemy_id := "act1_channels_encounter_enemy_%02d" % i
		_channels_swarm_enemy_ids.append(enemy_id)
		_register_channels_enemy_spec(parent, {
			"id": enemy_id,
			"scope": "encounter",
			"position": Vector3(
				CHANNELS_SWARM_CLUSTER_X + CHANNELS_SWARM_OFFSETS[i],
				0.5,
				0.5 + sin(float(i)) * 1.2),
			"move_speed": 3.6,
			"detection_range": 5.2,
			"color": Color(0.46, 0.16, 0.04),
		})

	_channels_run_lure = FlureScript.new()
	_channels_run_lure.name = "ChannelsEncounterFlure"
	_channels_run_lure.authority_id = CHANNELS_ENCOUNTER_FLURE_ID
	_channels_run_lure.configure(
		_game_state, CHANNELS_RUN_LURE_POS, _channels_swarm_enemy_ids,
		44.0, 1.8, Color(0.9, 0.45, 0.18))
	_channels_run_lure.required_character = "endo"
	_channels_run_lure.dwell_time = 2.0
	_channels_run_lure.interactable_type = Interactable.InteractableType.TIMED_ACTION
	_channels_run_lure.lure_duration = CHANNELS_RUN_LURE_DURATION
	_channels_run_lure.settle_pos = CHANNELS_RUN_LURE_POS
	_channels_run_lure.one_shot = false
	parent.add_child(_channels_run_lure)
	register_preview_interactable(_channels_run_lure)
	_channels_run_lure.set_interaction_enabled(false)
	_channels_run_lure.hide_tutorial_label()
	_channels_run_lure.flure_activated.connect(_on_channels_run_flure_activated)

	# Shelter alcove at the far end of the zone.
	_add_corridor_section(parent, Vector3(CHANNELS_SHELTER_POS.x, -0.04, CHANNELS_SHELTER_POS.z), Vector3(16, 0.08, 10), Color(0.07, 0.07, 0.08))
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x, 1.5, CHANNELS_SHELTER_POS.z + 5.0), Vector3(16, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x - 8.0, 1.5, CHANNELS_SHELTER_POS.z), Vector3(0.3, 3, 10), wall_color)
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x + 8.0, 1.5, CHANNELS_SHELTER_POS.z), Vector3(0.3, 3, 10), wall_color)
	var shelter_door := MeshInstance3D.new()
	shelter_door.name = "ChannelsShelterDoor"
	var shelter_door_mesh := BoxMesh.new()
	shelter_door_mesh.size = Vector3(2.4, 2.6, 0.18)
	shelter_door.mesh = shelter_door_mesh
	var shelter_door_mat := StandardMaterial3D.new()
	shelter_door_mat.albedo_color = Color(0.22, 0.2, 0.18)
	shelter_door.material_override = shelter_door_mat
	shelter_door.position = CHANNELS_SHELTER_POS + Vector3(0, 1.25, -4.8)
	parent.add_child(shelter_door)
	var shelter_light := OmniLight3D.new()
	shelter_light.position = CHANNELS_SHELTER_POS + Vector3(0, 2.0, 0)
	shelter_light.light_color = Color(0.85, 0.68, 0.42)
	shelter_light.light_energy = 2.1
	shelter_light.omni_range = 12.0
	parent.add_child(shelter_light)

	var shelter_label := Label3D.new()
	shelter_label.name = "ChannelsShelterLabel"
	shelter_label.text = "SHELTER"
	shelter_label.font_size = 28
	shelter_label.pixel_size = 0.008
	shelter_label.modulate = Color(0.92, 0.78, 0.52, 0.85)
	shelter_label.outline_modulate = Color(0, 0, 0, 0.45)
	shelter_label.outline_size = 8
	shelter_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shelter_label.position = CHANNELS_SHELTER_POS + Vector3(0, 2.6, 0)
	parent.add_child(shelter_label)
	_channels_shelter_interactable = _create_interactable(
		parent,
		CHANNELS_SHELTER_POS,
		"ChannelsShelterRest",
		CHANNELS_SHELTER_RADIUS,
		1.2,
		"REST PARTY",
		true,
		Interactable.InteractableType.HOLD_ACTION
	)
	_channels_shelter_interactable.set(
		"description", "Settle the whole party at the shelter hearth")
	_channels_shelter_interactable.set(
		"consequence_preview", "Spend one ATP for each member who needs recovery")
	_channels_shelter_interactable.set_interaction_enabled(false)
	_channels_shelter_interactable.hide_tutorial_label()
	_channels_shelter_interactable.set_pre_trigger_validator(
		_validate_act1_channels_shelter_trigger)
	_channels_shelter_interactable.interaction_requested.connect(
		_on_act1_channels_shelter_requested)
	_channels_shelter_interactable.interacted.connect(
		_on_act1_channels_shelter_interacted.bind(
			_channels_shelter_interactable, true))

	_add_flora_node(
		parent,
		"channels_memory_reed",
		"Memory Reed",
		"channels",
		CHANNELS_BODY_POS + Vector3(-2.2, 0.0, 1.2),
		"memory",
		"client trace",
		CHANNELS_BODY_POS + Vector3(-0.6, 0.0, 0.2),
		Color(0.86, 0.68, 0.38),
		0.76,
		{"tended": true}
	)
	_add_flora_node(
		parent,
		"channels_lumivine",
		"Lumivine",
		"channels",
		CHANNELS_FLURE_POS + Vector3(1.8, 0.0, -1.1),
		"iron",
		"iron bloom",
		CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(3.0, 0.0, -0.6),
		Color(0.48, 0.88, 0.58),
		0.84,
		{"tended": true, "childhood_species": true}
	)
	_add_flora_node(
		parent,
		"channels_shortcut_vine",
		"Shelter Vine",
		"channels",
		CHANNELS_SHORTCUT_BRANCH_POS + Vector3(1.2, 0.0, 2.6),
		"resource",
		"warm shelter trace",
		CHANNELS_SHELTER_POS + Vector3(0.8, 0.0, 0.4),
		Color(0.72, 0.88, 0.52),
		0.68,
		{"tended": true}
	)
	_add_flora_node(
		parent,
		"channels_forget_me_not",
		"Forget-Me-Not",
		"channels",
		CHANNELS_SHELTER_POS + Vector3(-2.6, 0.0, 1.7),
		"relationship",
		"Aster",
		CHANNELS_SHELTER_POS + Vector3(-0.8, 0.0, 0.9),
		Color(0.58, 0.72, 0.95),
		1.0,
		{"role": "relationship", "forget_me_not": true, "tended": true, "childhood_species": true}
	)

	# Shortcut branch: visible from the outer path, locked from this side until the shelter is reached.
	_add_corridor_section(parent, Vector3(CHANNELS_SHORTCUT_BRANCH_POS.x, -0.04, CHANNELS_SHORTCUT_BRANCH_POS.z), Vector3(6, 0.08, 12), Color(0.055, 0.06, 0.075))
	_add_wall(parent, Vector3(CHANNELS_SHORTCUT_BRANCH_POS.x - 3.0, 1.5, CHANNELS_SHORTCUT_BRANCH_POS.z), Vector3(0.3, 3, 12), wall_color)
	_add_wall(parent, Vector3(CHANNELS_SHORTCUT_BRANCH_POS.x + 3.0, 1.5, CHANNELS_SHORTCUT_BRANCH_POS.z), Vector3(0.3, 3, 12), wall_color)
	_add_corridor_section(parent, Vector3((CHANNELS_SHORTCUT_GATE_POS.x + CHANNELS_SHELTER_POS.x) * 0.5, -0.04, CHANNELS_SHELTER_POS.z), Vector3(CHANNELS_SHELTER_POS.x - CHANNELS_SHORTCUT_GATE_POS.x + 6.0, 0.08, 6), Color(0.06, 0.065, 0.08))
	_add_wall(parent, Vector3((CHANNELS_SHORTCUT_GATE_POS.x + CHANNELS_SHELTER_POS.x) * 0.5, 1.5, CHANNELS_SHELTER_POS.z - 3.0), Vector3(CHANNELS_SHELTER_POS.x - CHANNELS_SHORTCUT_GATE_POS.x + 6.0, 3, 0.3), wall_color)
	_add_wall(parent, Vector3((CHANNELS_SHORTCUT_GATE_POS.x + CHANNELS_SHELTER_POS.x) * 0.5, 1.5, CHANNELS_SHELTER_POS.z + 3.0), Vector3(CHANNELS_SHELTER_POS.x - CHANNELS_SHORTCUT_GATE_POS.x + 6.0, 3, 0.3), wall_color)

	# The return barrier is a real two-phase gate. Its interaction anchor sits in the shelter (the
	# causal trigger) while its blocker remains at the branch throat (the physical consequence).
	_channels_shortcut_gate = PartyGate3D.new()
	_channels_shortcut_gate.name = "ChannelsShelterReturnGate"
	_channels_shortcut_gate.authority_id = CHANNELS_SHORTCUT_GATE_AUTHORITY_ID
	_channels_shortcut_gate.required_members = PackedStringArray(["aster", "peris", "endo"])
	_channels_shortcut_gate.readiness_radius = 3.0
	_channels_shortcut_gate.opening_duration = CHANNELS_SHORTCUT_GATE_OPEN_DURATION
	_channels_shortcut_gate.navigation_padding = Vector2(0.15, 0.1)
	_channels_shortcut_gate.position = CHANNELS_SHORTCUT_GATE_POS

	var shortcut_markers := Node3D.new()
	shortcut_markers.name = "Markers"
	_channels_shortcut_gate.add_child(shortcut_markers)
	var shortcut_anchor := Marker3D.new()
	shortcut_anchor.name = "InteractionAnchor"
	shortcut_anchor.position = CHANNELS_SHELTER_POS - CHANNELS_SHORTCUT_GATE_POS
	shortcut_markers.add_child(shortcut_anchor)

	_channels_shortcut_gate_mesh = MeshInstance3D.new()
	_channels_shortcut_gate_mesh.name = "GateMesh"
	var shortcut_gate_mesh := BoxMesh.new()
	shortcut_gate_mesh.size = Vector3(6.0, 2.6, 0.18)
	_channels_shortcut_gate_mesh.mesh = shortcut_gate_mesh
	var shortcut_gate_mat := StandardMaterial3D.new()
	shortcut_gate_mat.albedo_color = Color(0.22, 0.26, 0.3)
	shortcut_gate_mat.metallic = 0.2
	shortcut_gate_mat.roughness = 0.7
	_channels_shortcut_gate_mesh.material_override = shortcut_gate_mat
	_channels_shortcut_gate_mesh.position = Vector3(0, 1.25, 0)
	_channels_shortcut_gate.add_child(_channels_shortcut_gate_mesh)

	var shortcut_gate_body := StaticBody3D.new()
	shortcut_gate_body.name = "RubbleBlocker"
	_channels_shortcut_gate.add_child(shortcut_gate_body)
	var shortcut_gate_shape := CollisionShape3D.new()
	shortcut_gate_shape.name = "BlockerShape"
	var shortcut_gate_box := BoxShape3D.new()
	shortcut_gate_box.size = Vector3(6.0, 2.6, 0.2)
	shortcut_gate_shape.shape = shortcut_gate_box
	shortcut_gate_shape.position = Vector3(0, 1.25, 0)
	shortcut_gate_body.add_child(shortcut_gate_shape)
	parent.add_child(_channels_shortcut_gate)
	_channels_shortcut_gate.opened.connect(_on_channels_shortcut_gate_opened)
	_channels_shortcut_gate.blocked.connect(_on_channels_shortcut_gate_blocked)

	_channels_shortcut_light = OmniLight3D.new()
	_channels_shortcut_light.position = CHANNELS_SHORTCUT_GATE_POS + Vector3(0, 2.0, 0.8)
	parent.add_child(_channels_shortcut_light)
	_setup_channels_shortcut_gate()

	var shortcut_table := MeshInstance3D.new()
	var shortcut_table_mesh := BoxMesh.new()
	shortcut_table_mesh.size = Vector3(2.0, 0.18, 1.0)
	shortcut_table.mesh = shortcut_table_mesh
	var shortcut_table_mat := StandardMaterial3D.new()
	shortcut_table_mat.albedo_color = Color(0.28, 0.24, 0.2)
	shortcut_table.material_override = shortcut_table_mat
	shortcut_table.position = CHANNELS_SHELTER_POS + Vector3(-2.8, 0.85, 1.4)
	parent.add_child(shortcut_table)

	var shortcut_bowl := MeshInstance3D.new()
	var shortcut_bowl_mesh := SphereMesh.new()
	shortcut_bowl_mesh.radius = 0.22
	shortcut_bowl_mesh.height = 0.16
	shortcut_bowl.mesh = shortcut_bowl_mesh
	var shortcut_bowl_mat := StandardMaterial3D.new()
	shortcut_bowl_mat.albedo_color = Color(0.7, 0.58, 0.4)
	shortcut_bowl.material_override = shortcut_bowl_mat
	shortcut_bowl.position = CHANNELS_SHELTER_POS + Vector3(-2.5, 1.03, 1.35)
	parent.add_child(shortcut_bowl)

	var shelter_heater := MeshInstance3D.new()
	var shelter_heater_mesh := BoxMesh.new()
	shelter_heater_mesh.size = Vector3(0.8, 0.9, 0.5)
	shelter_heater.mesh = shelter_heater_mesh
	var shelter_heater_mat := StandardMaterial3D.new()
	shelter_heater_mat.albedo_color = Color(0.34, 0.22, 0.14)
	shelter_heater_mat.emission_enabled = true
	shelter_heater_mat.emission = Color(0.95, 0.46, 0.18)
	shelter_heater_mat.emission_energy_multiplier = 0.35
	shelter_heater.material_override = shelter_heater_mat
	shelter_heater.position = CHANNELS_SHELTER_POS + Vector3(3.4, 0.45, 2.0)
	parent.add_child(shelter_heater)

	# Lighting spans the corridor.
	for i in range(5):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 20.0 + i * 45.0, 2.5, 0)
		light.light_color = Color(0.2, 0.25, 0.4)
		light.light_energy = 1.5
		light.omni_range = 20.0
		parent.add_child(light)

	# Warm lights near stagnant zones
	for i in range(3):
		var sl := OmniLight3D.new()
		sl.position = Vector3(sx + 50.0 + i * 60.0, 2.0, 12.0 if i % 2 == 0 else -12.0)
		sl.light_color = Color(0.5, 0.25, 0.1)
		sl.light_energy = 1.0
		sl.omni_range = 8.0
		parent.add_child(sl)

	_build_channels_optional_worldbuilding(parent)

func headless_get_anchor_positions() -> Dictionary:
	var anchors := {
		"channels_body": CHANNELS_BODY_POS,
		"channels_window_one_stage": CHANNELS_WINDOW_ONE_STAGE_POS,
		"channels_window_one_lure": CHANNELS_WINDOW_ONE_LURE_POS,
		"channels_window_one_curtain": CHANNELS_WINDOW_ONE_CURTAIN_POS,
		"channels_window_one_goal": CHANNELS_WINDOW_ONE_GOAL_POS,
		"channels_flure": CHANNELS_FLURE_POS,
		"channels_window_two_stage": CHANNELS_WINDOW_TWO_STAGE_POS,
		"channels_window_two_lure": CHANNELS_WINDOW_TWO_LURE_POS,
		"channels_window_two_curtain": CHANNELS_WINDOW_TWO_CURTAIN_POS,
		"channels_window_two_goal": CHANNELS_WINDOW_TWO_GOAL_POS,
		"channels_run_lure": CHANNELS_RUN_LURE_POS,
		"channels_encounter_entry": CHANNELS_ENCOUNTER_ENTRY_POS,
		"channels_hide_spot": CHANNELS_HIDE_SPOT_POS,
		"channels_shelter": CHANNELS_SHELTER_POS,
		"channels_shortcut_gate": CHANNELS_SHORTCUT_GATE_POS,
		"channels_shortcut_branch": CHANNELS_SHORTCUT_BRANCH_POS,
		"stacks_signal_wall": _stacks_signal_interactable.global_position if is_instance_valid(_stacks_signal_interactable) else Vector3(STACKS_START.x + 96.0, 1.0, -16.9),
		"stacks_terminal": _stacks_terminal_interactable.global_position if is_instance_valid(_stacks_terminal_interactable) else Vector3(STACKS_START.x + 88.0, 1.0, 0.0),
		"stacks_workspace": _stacks_workspace_interactable.global_position if is_instance_valid(_stacks_workspace_interactable) else Vector3(STACKS_START.x + 165.0, 1.0, -10.0),
		"stacks_shelter": STACKS_SHELTER_POS,
		"stacks_drink_machine": Vector3(STACKS_START.x + 132.0, 0.9, 14.0),
		"rings_client_bloom": _flora_nodes["rings_client_bloom"].get("position", Vector3(RINGS_START.x + 76.0, 0.0, -8.0)) if _flora_nodes.has("rings_client_bloom") else Vector3(RINGS_START.x + 76.0, 0.0, -8.0),
		"rings_forget_me_not": _flora_nodes["rings_forget_me_not"].get("position", Vector3(RINGS_START.x + 116.0, 0.0, 13.8)) if _flora_nodes.has("rings_forget_me_not") else Vector3(RINGS_START.x + 116.0, 0.0, 13.8),
		"rings_doorvine": _flora_nodes["rings_doorvine"].get("position", Vector3(RINGS_START.x + 156.0, 0.0, 8.5)) if _flora_nodes.has("rings_doorvine") else Vector3(RINGS_START.x + 156.0, 0.0, 8.5),
		"rings_marco": Vector3(RINGS_START.x + 80.0, 0.5, -5.0),
		"rings_endo_junction": RINGS_ENDO_JUNCTION_POS,
		"lockout_access_panel": LOCKOUT_BOUNDARY + Vector3(-1.5, 0.75, 0.0),
		"lockout_escape_trigger": Vector3(LOCKOUT_START.x - 11.0, 0.5, 0.0),
	}
	for window_id in _channels_window_lanes.keys():
		var lane: Dictionary = _channels_window_lanes[window_id]
		anchors["channels_%s_swarm_start" % window_id] = lane.get("swarm_start_pos", Vector3.ZERO)
	for site_id in CHANNELS_OPTIONAL_SITES.keys():
		anchors["channels_optional_%s" % site_id] = _channels_optional_site_position(str(site_id))
	return anchors


func _channels_enemy_headless_state(enemy_id: String) -> Dictionary:
	var enemy = _resolve_channels_enemy(enemy_id)
	var registered := _game_state != null and _game_state.characters.has(enemy_id)
	return {
		"id": enemy_id,
		"scope": str(_channels_enemy_scope_by_id.get(enemy_id, "")),
		"registered": registered,
		"position": _game_state.get_position(enemy_id) if registered else Vector3.INF,
		"render_position": (
			_game_state.get_render_position(enemy_id) if registered else Vector3.INF),
		"fsm_state": str(enemy.get_state()) if is_instance_valid(enemy) else "missing",
		"alive": bool(enemy.is_alive()) if is_instance_valid(enemy) else false,
		"hp": float(enemy.get_hp()) if is_instance_valid(enemy) else 0.0,
		"external_traversal": (
			_game_state.get_external_traversal_state(enemy_id)
			if registered and _game_state.is_external_traversal_active(enemy_id) else {}),
		"authority": (
			_game_state.get_world_state("runtime:enemy:%s" % enemy_id, {})
			if _game_state != null else {}),
	}


func _channels_enemy_states_for_ids(enemy_ids: Array) -> Dictionary:
	var states := {}
	for enemy_id_v in enemy_ids:
		var enemy_id := str(enemy_id_v)
		states[enemy_id] = _channels_enemy_headless_state(enemy_id)
	return states


func headless_get_state() -> Dictionary:
	var state := super.headless_get_state()
	var atp := {}
	var lane_state := {}
	var journal: Node = get_node_or_null("/root/EngramJournal")
	var support_log: Dictionary = {}
	var flora_state := _flora_system.get_debug_state(
		_scheduler.get_current_tick() if _scheduler else 0.0,
		_current_flora_zone()
	)
	flora_state["visible_clue_count"] = int(flora_state.get("visible_clues", []).size())
	if _game_state:
		for char_id in ["aster", "peris", "endo"]:
			if _game_state.characters.has(char_id):
				atp[char_id] = float(_game_state.characters[char_id].stats.get("atp", 0.0))
	for window_id in _channels_window_lanes.keys():
		var lane: Dictionary = _channels_window_lanes[window_id]
		var channel_states: Array = []
		var enemy_states := {}
		var actual_wash_channel_index := -1
		var lane_enemy_ids: Array = lane.get("enemy_ids", [])
		for channel_variant in lane.get("periodic_channels", []):
			var channel_entry: Dictionary = channel_variant
			var channel_node: Channel = channel_entry.get("channel")
			var channel_truth := (
				channel_node.get_state() if is_instance_valid(channel_node) else {})
			channel_truth["position"] = channel_entry.get("position", Vector3.ZERO)
			channel_truth["contact_time"] = float(channel_entry.get("contact_time", 0.0))
			channel_truth["phase_offset"] = float(channel_entry.get("phase_offset", 0.0))
			channel_states.append(channel_truth)
			if actual_wash_channel_index < 0:
				var refractory: Dictionary = channel_truth.get("sweep_refractory", {})
				for enemy_id_v in lane_enemy_ids:
					if refractory.has(str(enemy_id_v)):
						actual_wash_channel_index = int(channel_entry.get("index", -1))
						break
		for enemy_id_v in lane_enemy_ids:
			var enemy_id := str(enemy_id_v)
			enemy_states[enemy_id] = _channels_enemy_headless_state(enemy_id)
		var swept_ids: Array = lane.get("swept_ids", [])
		lane_state[window_id] = {
			"phase": str(lane.get("phase", "")),
			"last_outcome": str(lane.get("last_outcome", "")),
			"lure_active": bool(lane.get("lure_active", false)),
			"safe_until_tick": float(lane.get("safe_until_tick", -1.0)),
			"flow_offset": float(lane.get("flow_offset", 0.0)),
			"periodic_channel_count": int(lane.get("periodic_channels", []).size()),
			"bridge_segment_count": int(lane.get("bridge_segments", []).size()),
			"corpse_count": int(lane.get("corpse_nodes", []).size()),
			"enemy_count": lane_enemy_ids.size(),
			"alive_enemy_count": lane_enemy_ids.size() - swept_ids.size(),
			"swept_enemy_count": swept_ids.size(),
			"enemy_ids": lane_enemy_ids.duplicate(),
			"swept_ids": swept_ids.duplicate(),
			"enemies": enemy_states,
			"swarm_state": str(lane.get("swarm_state", "")),
			# Compatibility report, now derived from a Channel's real refractory record.
			"washed_channel_index": actual_wash_channel_index,
			"wash_analysis": lane.get("wash_analysis", {}),
			"channels": channel_states,
		}
	if journal != null:
		if _stacks_support_log_entry_id != -1:
			support_log = journal.get_entry(_stacks_support_log_entry_id)
		if support_log.is_empty():
			support_log = journal.get_entry_by_story_key(STACKS_SUPPORT_LOG_KEY)
	state["active_character"] = _active_character
	state["channels_active_window_lane"] = _channels_active_window_lane
	state["channels_shortcut_unlocked"] = _channels_shortcut_unlocked
	state["channels_shortcut_gate"] = _channels_shortcut_gate.get_authority_state() \
		if is_instance_valid(_channels_shortcut_gate) else {}
	state["channels_party_recuperated"] = _channels_party_recuperated
	state["channels_shelter_reached"] = _channels_shelter_reached
	state["channels_shelter_rest_phase"] = _channels_shelter_rest_phase
	state["channels_flow_power"] = _channels_flow_power
	state["channels_coda_phase"] = _channels_coda_phase
	state["channels_coda"] = {
		"phase": _channels_coda_phase,
		"flure": (
			_channels_flure.get_effect_state()
			if is_instance_valid(_channels_flure) else {}),
		"enemy_ids": _channels_flush_enemy_ids.duplicate(),
		"swept_ids": _channels_coda_swept_ids.duplicate(),
		"enemies": _channels_enemy_states_for_ids(_channels_flush_enemy_ids),
		"channel": (
			_channels_flure_channel.get_state()
			if is_instance_valid(_channels_flure_channel) else {}),
	}
	state["channels_window_lanes"] = lane_state
	state["channels_run_lure_active"] = _channels_run_lure_active
	state["channels_party_hidden"] = _channels_party_hidden
	state["channels_encounter_phase"] = _channels_encounter_phase
	state["channels_run_lure_deadline"] = _channels_run_lure_expire_tick
	state["channels_encounter_retry_deadline"] = _channels_encounter_retry_deadline
	state["channels_encounter"] = {
		"phase": _channels_encounter_phase,
		"flure": (
			_channels_run_lure.get_effect_state()
			if is_instance_valid(_channels_run_lure) else {}),
		"enemy_ids": _channels_swarm_enemy_ids.duplicate(),
		"spotted_ids": _channels_encounter_spotted_ids.duplicate(),
		"enemies": _channels_enemy_states_for_ids(_channels_swarm_enemy_ids),
	}
	state["channels_formation"] = _channels_formation_authority.duplicate(true)
	state["channels_runtime_authority"] = _channels_runtime_authority_state()
	state["channels_hp"] = {
		"aster": _aster_hp,
		"peris": _peris_hp,
	}
	state["channels_atp"] = atp
	state["channels_optional_worldbuilding"] = {
		"optional_findings": _channels_optional_findings.duplicate(true),
		"optional_count": _channels_optional_findings.size(),
		"site_count": CHANNELS_OPTIONAL_SITES.size(),
	}
	state["channels_causal_measurement"] = get_channels_playtime_contract()
	state["overlay_states"] = _overlay_states.duplicate(true)
	state["stacks"] = {
		"support_log_presented": _stacks_support_log_presented,
		"signal_interacted": _stacks_signal_interacted,
		"terminal_interacted": _stacks_terminal_interacted,
		"archive_interacted": _stacks_archive_interacted,
		"audit_flags_found": _stacks_audit_flags_found,
		"bank_samples": _stacks_bank_samples.keys(),
		"bank_resolved": _stacks_bank_resolved,
		"bank_attempts": _stacks_bank_attempts,
		"last_commit": _stacks_last_commit,
		"failed_commits": _stacks_failed_commits.duplicate(),
		"anxiety_seen": _stacks_anxiety_seen,
		"optional_record_count": int(_stacks_support_log_presented)
			+ int(_stacks_terminal_interacted)
			+ int(_stacks_signal_interacted)
			+ int(_stacks_archive_interacted),
		"engram": {
			"entry_count": journal.get_entry_count() if journal != null else 0,
			"story_key": str(support_log.get("story_key", "")),
			"overlay_visible": _engram_overlay != null and _engram_overlay.visible,
		},
	}
	var rings_departure := _rings_endo_traversal_state()
	state["rings"] = {
		"endo_visible": _endo != null and _endo.visible,
		"endo_present": _game_state != null and _game_state.characters.has("endo"),
		"endo_in_party": _game_state != null and _game_state.get_party().has("endo"),
		"endo_phase": _rings_endo_phase,
		"endo_departure_progress": float(rings_departure.get(
			"progress", 1.0 if _rings_endo_phase == RINGS_ENDO_PHASE_DEPARTED else 0.0)),
		"endo_departure_remaining": float(rings_departure.get("remaining", 0.0)),
		"endo_departure_start_tick": _rings_endo_departure_start_tick,
		"endo_departure_deadline": _rings_endo_departure_deadline,
		"reassignment_actor": _rings_reassignment_actor,
		"reassignment_commit_tick": _rings_reassignment_commit_tick,
		"reassignment_positions": _rings_reassignment_positions.duplicate(true),
		"peris_overlay_enabled": bool(_overlay_states.get("peris", false)),
		"client_seen": _rings_client_seen,
		"trace_seen": _rings_trace_seen.duplicate(true),
		"trace_count": _rings_trace_seen.size(),
		"ambient_trace_count": RINGS_AMBIENT_TRACE_IDS.size(),
	}
	var lockout_state := {
		"naturalizer_count": _naturalizers.size(),
		"boundary_crossed": _aster_node != null and _aster_node.global_position.x < LOCKOUT_START.x - 10.0,
		"campaign_chase_active": _lockout_chase_active,
	}
	if _lockout_chase_chunk != null and is_instance_valid(_lockout_chase_chunk) \
			and _lockout_chase_chunk.has_method("get_preview_state"):
		lockout_state.merge(_lockout_chase_chunk.call("get_preview_state"), true)
	state["lockout"] = lockout_state
	state["flora"] = flora_state
	return state

func headless_select_character(char_id: String) -> void:
	_select_character(char_id)

func headless_set_overlay_state(overlay_id: String, enabled: bool) -> void:
	if not _overlay_states.has(overlay_id):
		return
	_overlay_states[overlay_id] = enabled
	_refresh_overlay_button(overlay_id)
	_apply_overlay_visibility()

func headless_set_character_position(char_id: String, pos: Vector3) -> void:
	var node := _get_character_node(char_id)
	if node == null:
		return
	if _game_state and _game_state.characters.has(char_id):
		if _game_state.is_external_traversal_active(char_id):
			_game_state.cancel_external_traversal(char_id, &"fixture_placement")
		_game_state.command_stop(char_id)
		if _game_state.grid != null:
			var target_level := int(_game_state.grid.level_for_y(pos.y)) \
				if int(_game_state.grid.level_count) > 1 \
				else int(_game_state.get_character_level(char_id))
			# Re-applying the level is intentional: it projects stale spawn height
			# onto the actual graph floor before XZ is snapped.
			_game_state.set_character_level(char_id, target_level)
			pos.y = _game_state.grid.grid_to_world(
				_game_state.grid.world_to_grid(pos), target_level).y
		_game_state.snap_character_to(char_id, pos, false)
		node.global_position = _game_state.get_render_position(char_id)
	else:
		node.global_position = pos

# Shared front-half of every prepare_*_fragment entry point: wipe the transient UI/scheduler
# state and swap the named chunk in (load it, unload the others, activate its grid). Every
# fragment — channels included — initializes through this one path.
func _begin_fragment_prep(chunk_name: String) -> void:
	if _dialogue and _dialogue.has_method("clear"):
		_dialogue.clear()
	if _scheduler:
		_scheduler.clear()
	_clear_markers()
	_tutorial_prompt.hide_prompt()
	_swap_to_chunk(chunk_name)

# Load the named chunk, unload every other act1 chunk so only one is live (act1 cuts between
# chunks), and swap the live grid to this chunk's footprint. This is the SINGLE way a chunk is
# made current — the in-game enter beats and the prepare_*_fragment jump-ins both go through it,
# so a chunk is always initialized the same way. Unloading an already-unloaded chunk is a no-op,
# so it is safe from any starting state.
func _swap_to_chunk(chunk_name: String) -> void:
	if chunk_name != "channels":
		_deactivate_channels_kit(true)
	_load_chunk(chunk_name)
	for other in CHUNK_GRIDS.keys():
		if other != chunk_name:
			_unload_chunk(other)
	_activate_chunk_grid(chunk_name)
	if chunk_name == "channels":
		_apply_channels_grid_occluders()
		_activate_channels_kit()

# Halt the whole party so a fragment can reposition them cleanly.
func _stop_party() -> void:
	if _game_state == null:
		return
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)

func prepare_channels_fragment() -> void:
	_begin_fragment_prep("channels")
	# `_begin_fragment_prep` clears opaque scheduler Callables. Rebuild every reusable kit
	# presenter's own authority chain instead of leaving already-loaded nodes attached to dead tags.
	_reset_channels_kit_for_attempt()
	_reset_channels_optional_state()
	_channels_active_window_lane = ""
	for window_id in _channels_window_lanes.keys():
		_reset_channels_window_lane(window_id, false)
	_channels_coda_phase = "idle"
	_channels_coda_swept_ids.clear()
	_set_channels_flure_active(false)
	_reset_channels_encounter_nodes(false)
	_channels_encounter_phase = "idle"
	_channels_encounter_phase_start_tick = -1.0
	_channels_formation_authority = _channels_baseline_formation_authority()
	_channels_shelter_reached = false
	_channels_party_recuperated = false
	_channels_shelter_rest_phase = "locked"
	_clear_channels_shelter_rest_context()
	_apply_channels_shelter_rest_presentation()
	_channels_authority_poll_active = false
	_channels_authority_poll_origin_tick = -1.0
	_channels_authority_next_poll_tick = -1.0
	_publish_channels_runtime_authority()
	_start_channels_authority_poll()
	_stop_party()
	_current_step = ""
	_select_character("aster")
	_player.set_move_enabled(true)

func prepare_stacks_fragment(mode: String = "bank") -> void:
	_begin_fragment_prep("stacks")
	_clear_channels_runtime_state()
	_reset_stacks_runtime_state()
	_stacks_rest_phase = "locked"
	_clear_act1_stacks_rest_context()
	_publish_act1_stacks_rest_authority()
	var journal: Node = get_node_or_null("/root/EngramJournal")
	if journal != null:
		journal.reset_state(false)
	_select_character("aster")
	_player.global_position = STACKS_START + Vector3(5.0, 0.5, 0.0)
	_player.set_move_enabled(true)
	match mode:
		"shelter":
			_stacks_bank_resolved = true
			_start_stacks_shelter()
		"explore":
			_start_stacks_explore()
		_:
			_start_stacks_bank_audit()

func prepare_rings_fragment(mode: String = "client") -> void:
	_begin_fragment_prep("rings")
	_clear_lockout_runtime_state()
	_reset_rings_runtime_state(true)
	_stop_party()
	headless_set_character_position("aster", RINGS_START + Vector3(8.0, 0.5, 0.0))
	headless_set_character_position("peris", RINGS_START + Vector3(6.5, 0.5, 2.0))
	headless_set_character_position("endo", RINGS_START + Vector3(5.0, 0.5, -1.8))
	requested_scene_change = ""
	match mode:
		"explore":
			# A fixture may ask for the post-departure view, but the playable route cannot
			# manufacture that endpoint. Keep it at Marco unless a saved completed state is loaded.
			_select_character("peris")
			_start_rings_client()
		_:
			_select_character("peris")
			_enter_step("rings_client")
			_player.set_move_enabled(true)

func prepare_lockout_fragment(mode: String = "chase") -> void:
	_begin_fragment_prep("lockout")
	_clear_lockout_runtime_state()
	_endo.visible = true
	_stop_party()
	headless_set_character_position("aster", LOCKOUT_BOUNDARY + Vector3(-7.5, 0.5, 0.0))
	headless_set_character_position("peris", LOCKOUT_BOUNDARY + Vector3(-9.0, 0.5, 1.4))
	headless_set_character_position("endo", LOCKOUT_BOUNDARY + Vector3(-10.5, 0.5, -1.4))
	requested_scene_change = ""
	_select_character("aster")
	match mode:
		"approach":
			_enter_step("lockout_approach")
			_player.set_move_enabled(false)
		"rejected":
			_enter_step("lockout_rejected")
			_player.set_move_enabled(false)
		_:
			_enter_step("lockout_chase")
			_player.set_move_enabled(true)
			_tutorial_prompt.show_prompt("Run!")
			_spawn_lockout_naturalizers()

func start_channels_window_puzzle(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	prepare_channels_fragment()
	var party_positions := _get_channels_window_party_positions(window_id)
	for char_id in party_positions.keys():
		headless_set_character_position(char_id, party_positions[char_id])
	_begin_channels_window_lane(window_id)

func activate_channels_window_lure(_window_id: String) -> void:
	pass

func set_channels_window_flow_offset(window_id: String, offset: float) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["flow_offset"] = offset
	_channels_window_lanes[window_id] = lane
	_publish_channels_runtime_authority()

func get_channels_window_wash_analysis(window_id: String) -> Dictionary:
	if not _channels_window_lanes.has(window_id):
		return {}
	return _channels_window_lanes[window_id].get("wash_analysis", {})

func _add_stacks_audit_bank(
	parent: Node3D,
	bank_id: String,
	position: Vector3
) -> void:
	var status_text := StacksBankEvidence.bank_title(bank_id)
	var status_color := Color(0.42, 0.58, 0.68)
	var housing := MeshInstance3D.new()
	housing.name = "StacksAuditHousing_%s" % bank_id
	var housing_mesh := BoxMesh.new()
	housing_mesh.size = Vector3(2.6, 2.2, 1.2)
	housing.mesh = housing_mesh
	var housing_material := StandardMaterial3D.new()
	housing_material.albedo_color = Color(0.07, 0.08, 0.1)
	housing.material_override = housing_material
	housing.position = position + Vector3(0.0, 1.1, 0.0)
	parent.add_child(housing)

	var display := MeshInstance3D.new()
	display.name = "StacksAuditDisplay_%s" % bank_id
	var display_mesh := BoxMesh.new()
	display_mesh.size = Vector3(1.9, 0.55, 0.08)
	display.mesh = display_mesh
	var display_material := StandardMaterial3D.new()
	display_material.albedo_color = status_color.darkened(0.55)
	display_material.emission_enabled = true
	display_material.emission = status_color
	display_material.emission_energy_multiplier = 0.4
	display.material_override = display_material
	display.position = position + Vector3(0.0, 1.35, 0.64)
	parent.add_child(display)

	var label := Label3D.new()
	label.name = "StacksAuditLabel_%s" % bank_id
	label.text = status_text
	label.font_size = 24
	label.pixel_size = 0.008
	label.modulate = status_color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.7)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = position + Vector3(0.0, 2.65, 0.0)
	parent.add_child(label)

	var readout := Label3D.new()
	readout.name = "StacksAuditReadout_%s" % bank_id
	readout.text = ""
	readout.font_size = 19
	readout.pixel_size = 0.0055
	readout.modulate = Color(0.76, 0.86, 0.9)
	readout.outline_modulate = Color(0.0, 0.0, 0.0, 0.82)
	readout.outline_size = 7
	readout.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	readout.position = position + Vector3(0.0, 3.8, 0.0)
	readout.visible = false
	parent.add_child(readout)
	_stacks_bank_readouts[bank_id] = readout

	var interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	interactable.name = "StacksAudit_%s" % bank_id
	interactable.description = "Probe %s" % status_text
	interactable.consequence_preview = "Sample this bank's three filter outcomes"
	interactable.dialogue_box = _dialogue
	interactable.active_character = "aster"
	interactable.required_character = "aster"
	interactable.one_shot = true
	interactable.dwell_time = 1.2
	interactable.position = position + Vector3(0.0, 0.5, 0.0)
	interactable.tutorial_label = "PROBE"
	interactable.set_pre_trigger_validator(
		_validate_act1_stacks_bank_trigger.bind(bank_id, interactable))
	interactable.interacted.connect(
		_on_act1_stacks_bank_interacted.bind(interactable, bank_id))
	parent.add_child(interactable)
	register_preview_interactable(interactable)
	_stacks_bank_interactables[bank_id] = interactable

func _build_stacks_chunk(parent: Node3D) -> void:
	var sx := STACKS_START.x
	var length := 220.0
	var width := 40.0
	var floor_color := Color(0.05, 0.05, 0.06)
	var wall_color := Color(0.07, 0.07, 0.09)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, -width / 2.0), Vector3(length, 5, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, width / 2.0), Vector3(length, 5, 0.3), wall_color)

	# Dense rack grid creates corridors.
	for row in range(5):
		for col in range(12):
			var rack := MeshInstance3D.new()
			var rb := BoxMesh.new()
			rb.size = Vector3(1.0, 3.0, 5.0)
			rack.mesh = rb
			var rm := StandardMaterial3D.new()
			rm.albedo_color = Color(0.06, 0.06, 0.08)
			rm.metallic = 0.3
			rack.material_override = rm
			rack.position = Vector3(sx + 15 + col * 16.0, 1.5, -12.0 + row * 6.0)
			parent.add_child(rack)

	# Terminal interactable (midway through the stacks)
	var terminal = preload("res://scenes/game/interactable.tscn").instantiate()
	terminal.name = "DataTerminal"
	terminal.description = "Maintenance Terminal"
	terminal.dialogue_box = _dialogue
	terminal.active_character = "aster"
	terminal.required_character = "aster"
	terminal.one_shot = true
	terminal.dwell_time = 1.3
	terminal.position = Vector3(sx + length * 0.4, 1.0, 0)
	terminal.tutorial_label = "READ"
	terminal.set_pre_trigger_validator(
		_validate_act1_stacks_optional_trigger.bind(terminal))
	terminal.interacted.connect(
		_on_act1_stacks_terminal_interacted.bind(terminal, true))
	parent.add_child(terminal)
	_stacks_terminal_interactable = terminal

	# Sensor panels and cable bundles - the space reads as maintained instead of abandoned.
	for x_offset in [72.0, 84.0, 108.0]:
		var panel := MeshInstance3D.new()
		var panel_mesh := BoxMesh.new()
		panel_mesh.size = Vector3(3.4, 2.2, 0.16)
		panel.mesh = panel_mesh
		var panel_mat := StandardMaterial3D.new()
		panel_mat.albedo_color = Color(0.08, 0.1, 0.12)
		panel_mat.emission_enabled = true
		panel_mat.emission = Color(0.18, 0.34, 0.42)
		panel_mat.emission_energy_multiplier = 0.35
		panel.material_override = panel_mat
		panel.position = Vector3(sx + x_offset, 1.8, -width / 2.0 + 1.4)
		parent.add_child(panel)

		var cable := MeshInstance3D.new()
		var cable_mesh := CylinderMesh.new()
		cable_mesh.top_radius = 0.08
		cable_mesh.bottom_radius = 0.08
		cable_mesh.height = 4.8
		cable.mesh = cable_mesh
		var cable_mat := StandardMaterial3D.new()
		cable_mat.albedo_color = Color(0.16, 0.18, 0.2)
		cable.material_override = cable_mat
		cable.rotation_degrees.z = 90.0
		cable.position = Vector3(sx + x_offset + 1.5, 2.8, -width / 2.0 + 2.4)
		parent.add_child(cable)

	# Tuned signal lane - one wall reads as custom instrumentation instead of stock hardware.
	var signal_strip := MeshInstance3D.new()
	var signal_strip_mesh := BoxMesh.new()
	signal_strip_mesh.size = Vector3(7.0, 0.03, 1.6)
	signal_strip.mesh = signal_strip_mesh
	var signal_strip_mat := StandardMaterial3D.new()
	signal_strip_mat.albedo_color = Color(0.16, 0.14, 0.08)
	signal_strip_mat.emission_enabled = true
	signal_strip_mat.emission = Color(0.42, 0.3, 0.14)
	signal_strip_mat.emission_energy_multiplier = 0.25
	signal_strip.material_override = signal_strip_mat
	signal_strip.position = Vector3(sx + 96.0, 0.03, -width / 2.0 + 3.7)
	parent.add_child(signal_strip)

	var signal_panel := MeshInstance3D.new()
	var signal_panel_mesh := BoxMesh.new()
	signal_panel_mesh.size = Vector3(6.2, 2.5, 0.18)
	signal_panel.mesh = signal_panel_mesh
	var signal_panel_mat := StandardMaterial3D.new()
	signal_panel_mat.albedo_color = Color(0.11, 0.11, 0.09)
	signal_panel_mat.emission_enabled = true
	signal_panel_mat.emission = Color(0.46, 0.34, 0.16)
	signal_panel_mat.emission_energy_multiplier = 0.55
	signal_panel.material_override = signal_panel_mat
	signal_panel.position = Vector3(sx + 96.0, 1.85, -width / 2.0 + 1.32)
	parent.add_child(signal_panel)

	for i in range(4):
		var meter := MeshInstance3D.new()
		var meter_mesh := BoxMesh.new()
		meter_mesh.size = Vector3(0.45, 1.4 + 0.18 * float(i % 2), 0.08)
		meter.mesh = meter_mesh
		var meter_mat := StandardMaterial3D.new()
		meter_mat.albedo_color = Color(0.12, 0.16, 0.14)
		meter_mat.emission_enabled = true
		meter_mat.emission = Color(0.52, 0.74, 0.28) if i < 2 else Color(0.8, 0.62, 0.24)
		meter_mat.emission_energy_multiplier = 0.6
		meter.material_override = meter_mat
		meter.position = signal_panel.position + Vector3(-1.8 + float(i) * 1.2, -0.15 + 0.08 * float(i % 2), 0.12)
		parent.add_child(meter)

	var signal_light := OmniLight3D.new()
	signal_light.position = Vector3(sx + 96.0, 2.2, -13.8)
	signal_light.light_color = Color(0.46, 0.34, 0.18)
	signal_light.light_energy = 1.1
	signal_light.omni_range = 7.0
	parent.add_child(signal_light)

	var signal_wall = preload("res://scenes/game/interactable.tscn").instantiate()
	signal_wall.name = "SignalWall"
	signal_wall.description = "Custom Sensor Wall"
	signal_wall.dialogue_box = _dialogue
	signal_wall.active_character = "aster"
	signal_wall.required_character = "aster"
	signal_wall.one_shot = true
	signal_wall.dwell_time = 1.3
	signal_wall.position = Vector3(sx + 96.0, 1.0, -16.9)
	signal_wall.tutorial_label = "PARSE"
	signal_wall.set_pre_trigger_validator(
		_validate_act1_stacks_optional_trigger.bind(signal_wall))
	signal_wall.interacted.connect(
		_on_act1_stacks_signal_interacted.bind(signal_wall, true))
	parent.add_child(signal_wall)
	_stacks_signal_interactable = signal_wall

	# The target is posted before any probe. All three banks use the same neutral presentation so
	# their durable probe results, rather than answer-coded names or brightness, support prediction.
	var target_panel := MeshInstance3D.new()
	target_panel.name = "StacksAuditTargetPanel"
	var target_panel_mesh := BoxMesh.new()
	target_panel_mesh.size = Vector3(5.4, 2.6, 0.16)
	target_panel.mesh = target_panel_mesh
	var target_panel_material := StandardMaterial3D.new()
	target_panel_material.albedo_color = Color(0.12, 0.11, 0.08)
	target_panel_material.emission_enabled = true
	target_panel_material.emission = Color(0.42, 0.31, 0.14)
	target_panel_material.emission_energy_multiplier = 0.32
	target_panel.material_override = target_panel_material
	target_panel.position = Vector3(sx + 136.0, 1.7, -0.4)
	parent.add_child(target_panel)
	var target_text := Label3D.new()
	target_text.name = "StacksAuditTargetText"
	target_text.text = StacksBankEvidence.target_text()
	target_text.font_size = 22
	target_text.pixel_size = 0.006
	target_text.modulate = Color(0.92, 0.78, 0.48)
	target_text.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	target_text.outline_size = 7
	target_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	target_text.position = target_panel.position + Vector3(0.0, 0.0, 0.14)
	parent.add_child(target_text)

	_add_stacks_audit_bank(
		parent,
		"bank_a",
		Vector3(sx + 118.0, 0.0, -9.5)
	)
	_add_stacks_audit_bank(
		parent,
		"bank_b",
		Vector3(sx + 138.0, 0.0, 9.0)
	)
	_add_stacks_audit_bank(
		parent,
		"bank_c",
		Vector3(sx + 154.0, 0.0, -7.5)
	)

	# Myke's elegant workspace - deeper in, off the main path
	var elegant_light := OmniLight3D.new()
	elegant_light.position = Vector3(sx + length * 0.75, 2.0, -10)
	elegant_light.light_color = Color(0.42, 0.3, 0.2)
	elegant_light.light_energy = 1.5
	elegant_light.omni_range = 9.0
	parent.add_child(elegant_light)

	var work_table := MeshInstance3D.new()
	var work_table_mesh := BoxMesh.new()
	work_table_mesh.size = Vector3(3.2, 0.18, 1.6)
	work_table.mesh = work_table_mesh
	var work_table_mat := StandardMaterial3D.new()
	work_table_mat.albedo_color = Color(0.24, 0.2, 0.16)
	work_table.material_override = work_table_mat
	work_table.position = Vector3(sx + length * 0.75, 0.95, -10.0)
	parent.add_child(work_table)

	var notebook := MeshInstance3D.new()
	var notebook_mesh := BoxMesh.new()
	notebook_mesh.size = Vector3(0.55, 0.04, 0.8)
	notebook.mesh = notebook_mesh
	var notebook_mat := StandardMaterial3D.new()
	notebook_mat.albedo_color = Color(0.82, 0.78, 0.66)
	notebook.material_override = notebook_mat
	notebook.rotation_degrees.y = 18.0
	notebook.position = work_table.position + Vector3(0.6, 0.13, -0.2)
	parent.add_child(notebook)

	var workspace = preload("res://scenes/game/interactable.tscn").instantiate()
	workspace.name = "SupportWorkspace"
	workspace.description = "Support Workspace"
	workspace.dialogue_box = _dialogue
	workspace.active_character = "aster"
	workspace.required_character = "aster"
	workspace.one_shot = true
	workspace.dwell_time = 1.3
	workspace.position = Vector3(sx + length * 0.75, 1.0, -10.0)
	workspace.tutorial_label = "TRACE"
	workspace.set_pre_trigger_validator(
		_validate_act1_stacks_optional_trigger.bind(workspace))
	workspace.interacted.connect(
		_on_act1_stacks_archive_interacted.bind(workspace, true))
	parent.add_child(workspace)
	_stacks_workspace_interactable = workspace

	# The Open Files Initiative's required story payoff is a shelter rest, not another archive station.
	# These primitives are the district's existing blockout language; the shelter fixture itself
	# remains replaceable without changing the data-layer shelter region or interaction callback.
	_add_corridor_section(
		parent,
		STACKS_SHELTER_POS + Vector3(0.0, -0.04, 0.0),
		Vector3(12.0, 0.08, 10.0),
		Color(0.13, 0.11, 0.09)
	)
	_add_wall(parent, STACKS_SHELTER_POS + Vector3(0.0, 1.5, 5.0), Vector3(12.0, 3.0, 0.3), Color(0.12, 0.1, 0.09))
	_add_wall(parent, STACKS_SHELTER_POS + Vector3(6.0, 1.5, 0.0), Vector3(0.3, 3.0, 10.0), Color(0.12, 0.1, 0.09))
	var stacks_shelter_label := Label3D.new()
	stacks_shelter_label.name = "StacksShelterLabel"
	stacks_shelter_label.text = "SHELTER // OPEN FILES"
	stacks_shelter_label.font_size = 28
	stacks_shelter_label.pixel_size = 0.008
	stacks_shelter_label.modulate = Color(0.92, 0.76, 0.48, 0.9)
	stacks_shelter_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stacks_shelter_label.position = STACKS_SHELTER_POS + Vector3(0.0, 2.7, 0.0)
	parent.add_child(stacks_shelter_label)
	var stacks_shelter_light := OmniLight3D.new()
	stacks_shelter_light.position = STACKS_SHELTER_POS + Vector3(0.0, 2.2, 0.0)
	stacks_shelter_light.light_color = Color(0.86, 0.64, 0.38)
	stacks_shelter_light.light_energy = 2.0
	stacks_shelter_light.omni_range = 11.0
	parent.add_child(stacks_shelter_light)
	_stacks_shelter_interactable = _create_interactable(
		parent,
		STACKS_SHELTER_POS,
		"StacksShelterRest",
		3.0,
		1.2,
		"REST",
		true,
		Interactable.InteractableType.HOLD_ACTION
	)
	_stacks_shelter_interactable.set("description", "Rest with the party")
	_stacks_shelter_interactable.set("consequence_preview", "Rest here; Peris asks Aster what he knows")
	_stacks_shelter_interactable.set_interaction_enabled(false)
	_stacks_shelter_interactable.set_pre_trigger_validator(
		_validate_act1_stacks_shelter_trigger)
	_stacks_shelter_interactable.interaction_requested.connect(
		_on_act1_stacks_shelter_requested)
	_stacks_shelter_interactable.interacted.connect(
		_on_act1_stacks_shelter_interacted.bind(_stacks_shelter_interactable, true))

	var drink := MeshInstance3D.new()
	var drink_mesh := BoxMesh.new()
	drink_mesh.size = Vector3(1.1, 1.9, 0.9)
	drink.mesh = drink_mesh
	var drink_mat := StandardMaterial3D.new()
	drink_mat.albedo_color = Color(0.14, 0.18, 0.2)
	drink_mat.emission_enabled = true
	drink_mat.emission = Color(0.1, 0.18, 0.24)
	drink_mat.emission_energy_multiplier = 0.42
	drink.material_override = drink_mat
	drink.position = Vector3(sx + length * 0.6, 0.95, width / 2.0 - 3.0)
	parent.add_child(drink)

	# Cold lighting spans the corridor.
	for i in range(6):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 20.0 + i * 35.0, 4.0, 0)
		light.light_color = Color(0.2, 0.2, 0.3)
		light.light_energy = 2.0
		light.omni_range = 20.0
		parent.add_child(light)

	_add_flora_node(
		parent,
		"stacks_terminal_bloom",
		"Duct Bloom",
		"stacks",
		Vector3(sx + length * 0.4, 0.0, 3.2),
		"cache",
		"terminal cache",
		Vector3(sx + length * 0.4, 0.0, 0.0),
		Color(0.72, 0.88, 0.54),
		0.58
	)
	_add_flora_node(
		parent,
		"stacks_archive_vine",
		"Archive Vine",
		"stacks",
		Vector3(sx + length * 0.75, 0.0, -8.2),
		"resource",
		"warm archive trace",
		Vector3(sx + length * 0.75, 0.0, -10.0),
		Color(0.88, 0.78, 0.46),
		0.7,
		{"tended": true}
	)
	_apply_act1_stacks_rest_presentation()

func _add_rings_trace_interactable(
	parent: Node3D,
	trace_id: String,
	description: String,
	position: Vector3,
	label: String
) -> void:
	var interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	interactable.name = "RingsTrace_%s" % trace_id
	interactable.description = description
	interactable.dialogue_box = _dialogue
	interactable.active_character = "peris"
	interactable.required_character = "peris"
	interactable.one_shot = true
	interactable.dwell_time = 1.4
	interactable.position = position
	interactable.tutorial_label = label
	interactable.set_pre_trigger_validator(
		_validate_act1_rings_trace_trigger.bind(trace_id, interactable))
	interactable.interacted.connect(
		_on_act1_rings_trace_interacted.bind(interactable, trace_id))
	parent.add_child(interactable)
	register_preview_interactable(interactable)
	_rings_trace_interactables[trace_id] = interactable

func _build_rings_chunk(parent: Node3D) -> void:
	var sx := RINGS_START.x
	var length := 200.0
	var width := 50.0
	var floor_color := Color(0.12, 0.11, 0.1)
	var wall_color := Color(0.15, 0.14, 0.12)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Cleaner residential walls. The north wall breaks at a real outbound junction so
	# Endo's departure has an authored spatial endpoint instead of a visibility toggle.
	var junction_x := RINGS_ENDO_JUNCTION_POS.x
	var junction_gap := 6.0
	var left_wall_length := junction_x - junction_gap * 0.5 - sx
	var right_wall_start := junction_x + junction_gap * 0.5
	var right_wall_length := sx + length - right_wall_start
	_add_wall(
		parent,
		Vector3(sx + left_wall_length * 0.5, 2.0, -width / 2.0),
		Vector3(left_wall_length, 4.0, 0.3),
		wall_color)
	_add_wall(
		parent,
		Vector3(right_wall_start + right_wall_length * 0.5, 2.0, -width / 2.0),
		Vector3(right_wall_length, 4.0, 0.3),
		wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.0, width / 2.0), Vector3(length, 4, 0.3), wall_color)
	_add_corridor_section(
		parent,
		Vector3(junction_x, -0.05, -29.5),
		Vector3(junction_gap, 0.1, 9.0),
		floor_color.darkened(0.08))
	_add_wall(parent, Vector3(junction_x - 3.0, 2.0, -29.5), Vector3(0.3, 4.0, 9.0), wall_color)
	_add_wall(parent, Vector3(junction_x + 3.0, 2.0, -29.5), Vector3(0.3, 4.0, 9.0), wall_color)
	var junction_label := Label3D.new()
	junction_label.name = "RingsEndoJunctionLabel"
	junction_label.text = "OUTBOUND JUNCTION"
	junction_label.font_size = 28
	junction_label.pixel_size = 0.008
	junction_label.modulate = Color(0.66, 0.72, 0.68, 0.9)
	junction_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	junction_label.position = Vector3(junction_x, 2.8, -27.0)
	parent.add_child(junction_label)
	var junction_light := OmniLight3D.new()
	junction_light.name = "RingsEndoJunctionLight"
	junction_light.position = Vector3(junction_x, 2.6, -29.5)
	junction_light.light_color = Color(0.42, 0.55, 0.48)
	junction_light.light_energy = 1.6
	junction_light.omni_range = 9.0
	parent.add_child(junction_light)

	# Warm residential lighting.
	for i in range(8):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 15 + i * 25.0, 3.5, 0)
		light.light_color = Color(0.8, 0.6, 0.4)
		light.light_energy = 2.5
		light.omni_range = 18.0
		parent.add_child(light)

	# Simulation bay windows (glowing rectangles along the north wall)
	for i in range(10):
		var bay := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(5, 2.0, 0.1)
		bay.mesh = bb
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.15, 0.12, 0.1)
		bm.emission_enabled = true
		bm.emission = Color(0.3, 0.25, 0.15)
		bm.emission_energy_multiplier = 0.5
		bay.material_override = bm
		bay.position = Vector3(sx + 10 + i * 18.0, 1.8, -width / 2.0 + 0.2)
		parent.add_child(bay)

	# Apartment doors along the south wall (some sealed, one ajar)
	for i in range(8):
		var door := MeshInstance3D.new()
		var db := BoxMesh.new()
		db.size = Vector3(2.0, 2.5, 0.1)
		door.mesh = db
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.18, 0.16, 0.14)
		door.material_override = dm
		door.position = Vector3(sx + 20 + i * 22.0, 1.25, width / 2.0 - 0.2)
		parent.add_child(door)

	# Client interactable (Peris tries to talk)
	var client := preload("res://scenes/game/interactable.tscn").instantiate()
	client.name = "ClientNPC"
	client.description = "Former Client"
	client.dialogue_box = _dialogue
	client.active_character = "peris"
	client.required_character = "peris"
	client.one_shot = true
	client.dwell_time = 1.0
	client.position = Vector3(sx + length * 0.4, 0.5, -5)
	client.tutorial_label = "SPEAK"
	client.set_pre_trigger_validator(_validate_act1_rings_client_trigger)
	client.interaction_requested.connect(_on_act1_rings_client_requested)
	client.interacted.connect(
		_on_act1_rings_client_interacted.bind(client, true))
	parent.add_child(client)
	register_preview_interactable(client)
	_rings_client_interactable = client

	# Drink machine set dressing.
	var drink := MeshInstance3D.new()
	var drb := BoxMesh.new()
	drb.size = Vector3(1.0, 1.8, 0.8)
	drink.mesh = drb
	var drm := StandardMaterial3D.new()
	drm.albedo_color = Color(0.15, 0.18, 0.2)
	drm.emission_enabled = true
	drm.emission = Color(0.1, 0.15, 0.2)
	drm.emission_energy_multiplier = 0.3
	drink.material_override = drm
	drink.position = Vector3(sx + length * 0.6, 0.9, width / 2.0 - 2.0)
	parent.add_child(drink)

	_add_flora_node(
		parent,
		"rings_client_bloom",
		"Client Bloom",
		"rings",
		Vector3(sx + length * 0.38, 0.0, -8.0),
		"memory",
		"client trace",
		Vector3(sx + length * 0.4, 0.0, -5.0),
		Color(0.95, 0.74, 0.44),
		0.82,
		{"tended": true}
	)
	_add_flora_node(
		parent,
		"rings_forget_me_not",
		"Forget-Me-Not",
		"rings",
		Vector3(sx + length * 0.58, 0.0, 13.8),
		"relationship",
		"Aster",
		Vector3(sx + length * 0.58, 0.0, 13.8),
		Color(0.58, 0.72, 0.95),
		1.0,
		{"role": "relationship", "forget_me_not": true, "tended": true, "childhood_species": true}
	)
	_add_flora_node(
		parent,
		"rings_doorvine",
		"Doorvine",
		"rings",
		Vector3(sx + length * 0.78, 0.0, 8.5),
		"resource",
		"occupied warmth",
		Vector3(sx + length * 0.8, 0.0, 10.0),
		Color(0.72, 0.88, 0.58),
		0.52
	)

	_add_rings_trace_interactable(
		parent,
		"client_bloom",
		"Client Bloom",
		Vector3(sx + length * 0.38, 0.5, -8.0),
		"READ"
	)
	_add_rings_trace_interactable(
		parent,
		"forget_me_not",
		"Forget-Me-Not Bed",
		Vector3(sx + length * 0.58, 0.5, 13.8),
		"TEND"
	)
	_add_rings_trace_interactable(
		parent,
		"doorvine",
		"Occupied Doorvine",
		Vector3(sx + length * 0.78, 0.5, 8.5),
		"TRACE"
	)

func _build_lockout_chunk(parent: Node3D) -> void:
	var sx := LOCKOUT_START.x
	var length := 80.0  # Shorter — this is an event, not an exploration area
	var width := 20.0
	var floor_color := Color(0.1, 0.1, 0.12)
	var wall_color := Color(0.12, 0.12, 0.14)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Cleaner boundary walls.
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, -width / 2.0), Vector3(length, 5, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, width / 2.0), Vector3(length, 5, 0.3), wall_color)

	# Progressive lighting: dim at entry, bright at boundary (approaching civilization)
	for i in range(4):
		var light := OmniLight3D.new()
		var t: float = float(i) / 3.0
		light.position = Vector3(sx + 10.0 + i * 20.0, 3.0, 0)
		light.light_color = Color(0.3 + t * 0.3, 0.3 + t * 0.2, 0.35 + t * 0.25)
		light.light_energy = 1.0 + t * 2.0
		light.omni_range = 12.0 + t * 6.0
		parent.add_child(light)

	# Access panel visual (at the boundary)
	var panel := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.15, 1.5, 1.0)
	panel.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.12, 0.14, 0.18)
	pm.emission_enabled = true
	pm.emission = Color(0.1, 0.15, 0.25)
	pm.emission_energy_multiplier = 0.8
	panel.material_override = pm
	panel.position = LOCKOUT_BOUNDARY + Vector3(-0.5, 0.75, 0)
	parent.add_child(panel)

	# Access panel interactable
	var access := preload("res://scenes/game/interactable.tscn").instantiate()
	access.name = "AccessPanel"
	access.description = "Access Panel"
	access.dialogue_key = "lockout.approach.panel_reject"
	access.dialogue_box = _dialogue
	access.active_character = "aster"
	access.one_shot = true
	access.dwell_time = 1.5
	access.position = LOCKOUT_BOUNDARY + Vector3(-1.5, 0.75, 0)
	add_child(access)
