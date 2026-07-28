@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

const DayNightCycleScript = preload("res://scripts/system/simulation/day_night_cycle.gd")
const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")

## Iron spill tutorial: routing, pressure, Endo join, first shelter rest.

var _routing_mode := "safe"
var _sector_gates_open: Array[bool] = [false, false, false]
var _sector_route_choices: Array[String] = ["", "", ""]
var _sector_gates: Array[PartyGate3D] = []
var _sector_gate_visuals: Array[MeshInstance3D] = []
var _sector_route_interactables: Array = []
var _cache_interactable
var _cache_mesh: Node3D
var _cache_item_id := ""
var _cache_collected := false
var _cache_phase := "available"
var _cache_claimed_by := ""
var _cache_claim_serial := 0
var _restoring_cache_authority := false
var _lookout_interactable
var _lookout_surveyed := false
var _iron_damage_total := 0.0
var _iron_exposure_seconds := 0.0
var _sectors_entered: Array[String] = []
var _iron_hazard_active := false
var _iron_hazard_next_tick := -1.0
var _restoring_iron_hazard := false
var _endo_join_signal_game_state: GameState
var _shelter_party_gate: PartyGate3D
var _shelter_interactable
var _restoring_shelter_authority := false
var _leaving_source_committed_counts: Dictionary = {}
var _restoring_leaving_source_authority := false

var _peris
var _endo
var _hud  # GameHUD
var _iron_lights: Array[OmniLight3D] = []
var _dir_light: DirectionalLight3D
var _world_environment: Environment

var _game_day := 1
var _game_time := 0.3
var _game_clock = DayNightCycleScript.new()
# HP and running live in GameState.

# Corridor runs along +X.  The authored route is 210 m from the facility lip to
# Shelter 1.  It is deliberately split into three different iron problems rather
# than stretched with slower movement or timer gates.
const EXIT_POS := Vector3(0, 0, 0)
const IRON_1_POS := Vector3(32, 0, 0)
const SAFE_1_WAYPOINT := Vector3(32, 0, -11)
const SAFE_1_END := Vector3(48, 0, 0)
const MIDPOINT := Vector3(69, 0, 0)
const IRON_2_POS := Vector3(91, 0, -1)
const SAFE_2_WAYPOINT := Vector3(91, 0, 11)
const SAFE_2_END := Vector3(114, 0, 0)
const IRON_3_POS := Vector3(151, 0, 1)
const SAFE_3_WAYPOINT := Vector3(151, 0, -11)
const SAFE_3_END := Vector3(177, 0, 0)
const SHELTER_POS := Vector3(210, 0, 0)

const CORRIDOR_X_MIN := -4.0
const CORRIDOR_X_MAX := 218.0
const CORRIDOR_HALF_WIDTH := 15.0
const CORRIDOR_LENGTH := CORRIDOR_X_MAX - CORRIDOR_X_MIN
const CACHE_POS := Vector3(65, 0, 11.5)
const LOOKOUT_POS := Vector3(129, 0, -11.5)
const IRON_DAMAGE_PER_SEC := 1.7
const IRON_DAMAGE_INTERVAL := 0.5
const IRON_HAZARD_AUTHORITY_VERSION := 1
const IRON_HAZARD_AUTHORITY_KEY := "runtime:leaving_facility_sequence:iron_hazard"
const IRON_HAZARD_TAG := "leaving_facility_iron_hazard"
const CACHE_AUTHORITY_VERSION := 1
const CACHE_AUTHORITY_KEY := "runtime:leaving_facility_sequence:side_cache"
const CACHE_AUTHORITY_CONTRACT := "leaving_facility_side_cache/v1"
const CACHE_SOURCE_FIXTURE := "LeavingFacilityCache"
const CACHE_ITEM_TYPE := "lysate"
const CACHE_PHASE_AVAILABLE := "available"
const CACHE_PHASE_CLAIMING := "claiming"
const CACHE_PHASE_CLAIMED := "claimed"
const ENDO_JOIN_AUTHORITY_VERSION := 1
const ENDO_JOIN_AUTHORITY_KEY := "runtime:leaving_facility_sequence:endo_join"
const ENDO_JOIN_AUTHORITY_CONTRACT := "leaving_facility_endo_join/v1"
const ENDO_JOIN_TAG := "leaving_facility_endo_join"
const ENDO_JOIN_DELAY := 3.5
const ENDO_JOIN_PHASE_ABSENT := "absent"
const ENDO_JOIN_PHASE_PENDING := "pending"
const ENDO_JOIN_PHASE_JOINED := "joined"
const PARTY_IDS := ["aster", "peris", "endo"]
const SHELTER_HALF_SIZE := Vector2(4.25, 3.25)
const SHELTER_READY_RADIUS := 3.2
const SHELTER_GATE_AUTHORITY_ID := "leaving_facility_shelter_1_party"
const SHELTER_GATE_OPEN_DURATION := 0.75
const SHELTER_REST_AUTHORITY_VERSION := 1
const SHELTER_REST_AUTHORITY_KEY := "runtime:leaving_facility_sequence:shelter_rest"
const SHELTER_REST_AUTHORITY_CONTRACT := "leaving_facility_shelter_rest/v1"
const SHELTER_REST_PHASE_IDLE := "idle"
const SHELTER_REST_PHASE_COMMITTING := "committing"
const SHELTER_REST_PHASE_DAWN_PENDING := "dawn_pending"
const SHELTER_REST_PHASE_COMPLETE := "complete"
const SHELTER_DAWN_DELAY := 0.5
const SHELTER_DAWN_TAG := "leaving_facility_shelter_dawn"
const SHELTER_REST_COMMIT_TAG := "leaving_facility_shelter_rest_commit"
const ROUTE_REGROUP_RADIUS := 8.0
const SECTOR_GATE_OPEN_DURATION := 1.25
const SECTOR_GATE_REVALIDATION_RADIUS := 20.5
const SECTOR_GATE_CLOSED_Y := 1.25
const SECTOR_GATE_OPEN_Y := 4.1
const SECTOR_GATE_CONTEXT_CONTRACT := "leaving_facility_route_gate/v1"
const MODELED_FIXED_TRANSITION_SECONDS := 12.5
const LEAVING_SOURCE_AUTHORITY_VERSION := 1
const LEAVING_SOURCE_AUTHORITY_CONTRACT := "leaving_facility_exact_sources/v1"
const LEAVING_SOURCE_AUTHORITY_KEY := "runtime:leaving_facility_sequence:exact_sources"
const LEAVING_SOURCE_CACHE := "cache"
const LEAVING_SOURCE_LOOKOUT := "lookout"
const LEAVING_SOURCE_SHELTER := "shelter"
const LEAVING_SOURCE_POSITION_TOLERANCE := 0.35
const LEAVING_SOURCE_HEIGHT_TOLERANCE := 1.25

# Each sector owns one recoverable risk field and a route seal.  Cautious routing
# pays the longer marked detour; direct routing crosses the field and pays HP.
# The seal has a station on both lanes, so the chosen route is an authored action,
# not merely a HUD label.
const IRON_SECTORS := [
	{
		"id": "bleedway",
		"label": "I / BLEEDWAY",
		"center": IRON_1_POS,
		"half_size": Vector2(8.0, 5.5),
		"safe_waypoint": SAFE_1_WAYPOINT,
		"safe_station": Vector3(45, 0, -11),
		"direct_station": Vector3(45, 0, 0),
		"gate_x": 48.0,
		"risk_penalty": 20.0,
	},
	{
		"id": "sump",
		"label": "II / FERRIC SUMP",
		"center": IRON_2_POS,
		"half_size": Vector2(10.0, 7.0),
		"safe_waypoint": SAFE_2_WAYPOINT,
		"safe_station": Vector3(111, 0, 11),
		"direct_station": Vector3(111, 0, 0),
		"gate_x": 114.0,
		"risk_penalty": 24.0,
	},
	{
		"id": "lattice",
		"label": "III / IRON LATTICE",
		"center": IRON_3_POS,
		"half_size": Vector2(12.0, 6.0),
		"safe_waypoint": SAFE_3_WAYPOINT,
		"safe_station": Vector3(174, 0, -11),
		"direct_station": Vector3(174, 0, 0),
		"gate_x": 177.0,
		"risk_penalty": 28.0,
	},
]

var _grid: GridWorld
const OUTDOOR_STEPS := [
	"first_corridor",
	"safe_route_lesson",
	"dusk_approaches",
	"second_iron",
	"reach_shelter",
]
const ENDO_JOINED_STEPS := [
	"endo_joins",
	"first_corridor",
	"safe_route_lesson",
	"dusk_approaches",
	"second_iron",
	"reach_shelter",
	"first_rest",
	"dawn",
	"complete",
]

# --- Virtual method overrides ---

func _build_scene() -> void:
	_build_grid()
	_build_environment()
	_build_decorations()
	var environment := get_node_or_null("Environment") as Node3D
	if environment != null:
		# Keep the shared quality pass, but measure it against the rebuilt route
		# rather than the original 50 m prototype corridor.
		LevelDecoratorScript.decorate_profile(environment, "leaving_facility", {
			"x0": CORRIDOR_X_MIN,
			"x1": CORRIDOR_X_MAX,
			"width": CORRIDOR_HALF_WIDTH * 2.0,
			"spacing": 11.5,
			"floor_tint": Color(0.19, 0.20, 0.22),
			"wall_tint": Color(0.25, 0.21, 0.19),
			"landmark_lights": true,
		})

## The corridor floor (222x30, world X[-4,218] Z[-15,15]) is one open plane.
## Iron cells remain walkable risk; only the three authored route seals block progress.
func _build_grid() -> void:
	_grid = GridWorld.new()
	_grid.origin = Vector3(CORRIDOR_X_MIN, 0.0, -CORRIDOR_HALF_WIDTH)
	_grid.create_room(int(CORRIDOR_LENGTH), int(CORRIDOR_HALF_WIDTH * 2.0), false)
	for sector in IRON_SECTORS:
		var center: Vector3 = sector["center"]
		var half_size: Vector2 = sector["half_size"]
		_grid.set_world_region_risk(
			Vector2(center.x - half_size.x, center.z - half_size.y),
			Vector2(center.x + half_size.x, center.z + half_size.y),
			float(sector["risk_penalty"]), true)
	# A route seal after each field makes the three crossings distinct decisions.
	# Five central cells reopen when either the safe or direct station is worked.
	for sector in IRON_SECTORS:
		_set_gate_grid_open(float(sector["gate_x"]), false)

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	# Aster (player)
	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = EXIT_POS + Vector3(1, 0.5, 0)
	if not Engine.is_editor_hint():
		_player.grid_world = _grid
	chars.add_child(_player)

	# Peris (follows)
	_peris = _create_npc("Peris", Color(1.0, 0.67, 0.27))
	_peris.position = EXIT_POS + Vector3(0, 0, 1)
	if not Engine.is_editor_hint():
		_peris.grid_world = _grid
	chars.add_child(_peris)

	# Endo (hidden until joins)
	_endo = _create_npc("Endo", Color(0.4, 0.67, 0.53))
	_endo.position = EXIT_POS + Vector3(3, 0, -2)
	_endo.visible = false
	# Hidden nodes are still live nodes. Keep the not-yet-present body inert until
	# the authoritative roster transaction commits the join.
	_endo.process_mode = Node.PROCESS_MODE_DISABLED
	if not Engine.is_editor_hint():
		_endo.grid_world = _grid
	chars.add_child(_endo)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 10, 8), true)
		_bind_camera_to_level_bounds(_grid, 2.0)

func _register_characters() -> void:
	_game_state.grid = _grid
	_register_gs_character("aster", _player, GameState.WALK_SPEED, {
		"hp": GameState.HP_MAX, "stamina": GameState.STAMINA_MAX, "atp": 4.0})
	_register_gs_character("peris", _peris, 2.5, {
		"hp": GameState.HP_MAX, "stamina": GameState.STAMINA_MAX, "atp": 4.0})
	# Endo has an authored entrance. Preparing his node is not the same operation as
	# admitting a character to GameState: registered characters drive range queries,
	# hazards, fog, causal-link visibility, and other gameplay even when their node is
	# hidden. The saved join record below is the only authority that may add him.
	_configure_endo_presenter()
	_game_state.set_party(["aster", "peris"])
	_publish_endo_join_authority(_baseline_endo_join_authority())
	_wire_endo_join_signals()
	_game_state.set_route_mode(true)
	_game_state.set_day_length(_game_clock.get_cycle_duration_seconds())
	_build_route_gameplay()


func _baseline_endo_join_authority() -> Dictionary:
	return {
		"version": ENDO_JOIN_AUTHORITY_VERSION,
		"contract": ENDO_JOIN_AUTHORITY_CONTRACT,
		"character_id": "endo",
		"phase": ENDO_JOIN_PHASE_ABSENT,
		"start_tick": -1.0,
		"deadline": -1.0,
		"joined_tick": -1.0,
	}


func _endo_join_authority_state() -> Dictionary:
	if _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(ENDO_JOIN_AUTHORITY_KEY, null)
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _valid_endo_join_authority(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var saved := raw as Dictionary
	if int(saved.get("version", 0)) != ENDO_JOIN_AUTHORITY_VERSION \
			or str(saved.get("contract", "")) != ENDO_JOIN_AUTHORITY_CONTRACT \
			or str(saved.get("character_id", "")) != "endo":
		return false
	var phase := str(saved.get("phase", ""))
	var start_tick := float(saved.get("start_tick", -1.0))
	var deadline := float(saved.get("deadline", -1.0))
	var joined_tick := float(saved.get("joined_tick", -1.0))
	match phase:
		ENDO_JOIN_PHASE_ABSENT:
			return start_tick < 0.0 and deadline < 0.0 and joined_tick < 0.0
		ENDO_JOIN_PHASE_PENDING:
			return is_finite(start_tick) and is_finite(deadline) \
				and start_tick >= 0.0 and deadline > start_tick and joined_tick < 0.0
		ENDO_JOIN_PHASE_JOINED:
			return is_finite(start_tick) and is_finite(deadline) and is_finite(joined_tick) \
				and start_tick >= 0.0 and deadline > start_tick and joined_tick >= deadline
		_:
			return false


func _publish_endo_join_authority(authority: Dictionary) -> void:
	if _game_state == null:
		return
	_game_state.set_world_state(ENDO_JOIN_AUTHORITY_KEY, authority.duplicate(true))


## Prepare a stable presenter id for save attachment without registering a body.
## GameState.deserialize can then restore a post-join snapshot onto the same node,
## while a pre-join snapshot still has no gameplay character to see or target.
func _configure_endo_presenter() -> void:
	if not is_instance_valid(_endo) or _game_state == null:
		return
	_endo.set("game_state", _game_state)
	_endo.set("char_id", "endo")
	_endo.set("grid_world", _grid)
	_game_state_character_nodes["endo"] = _endo


func _wire_endo_join_signals() -> void:
	if _game_state == _endo_join_signal_game_state:
		return
	if _endo_join_signal_game_state != null \
			and _endo_join_signal_game_state.world_state_changed.is_connected(
				_on_endo_join_world_state_changed):
		_endo_join_signal_game_state.world_state_changed.disconnect(
			_on_endo_join_world_state_changed)
	_endo_join_signal_game_state = _game_state
	if _game_state != null and not _game_state.world_state_changed.is_connected(
			_on_endo_join_world_state_changed):
		_game_state.world_state_changed.connect(_on_endo_join_world_state_changed)


func _on_endo_join_world_state_changed(key: String, _value: Variant) -> void:
	if key == ENDO_JOIN_AUTHORITY_KEY:
		_sync_endo_presence_from_authority()


func _set_endo_presenter_present(present: bool) -> void:
	if not is_instance_valid(_endo):
		return
	_endo.visible = present
	_endo.process_mode = Node.PROCESS_MODE_INHERIT if present else Node.PROCESS_MODE_DISABLED


func _endo_is_authoritatively_joined() -> bool:
	if _game_state == null:
		return false
	var saved := _endo_join_authority_state()
	return _valid_endo_join_authority(saved) \
		and str(saved.get("phase", "")) == ENDO_JOIN_PHASE_JOINED \
		and _game_state.characters.has("endo")


func _remove_endo_from_authoritative_roster() -> void:
	if _game_state == null:
		return
	var party := _game_state.get_party()
	if party.has("endo"):
		party.erase("endo")
		_game_state.set_party(party)
	if _game_state.characters.has("endo"):
		_game_state.unregister_character("endo")


func _sync_endo_presence_from_authority() -> void:
	var saved := _endo_join_authority_state()
	if not _valid_endo_join_authority(saved):
		_set_endo_presenter_present(false)
		return
	var phase := str(saved.get("phase", ENDO_JOIN_PHASE_ABSENT))
	if phase != ENDO_JOIN_PHASE_JOINED:
		# A pre-join save must also retract a same-presenter future timeline.
		_remove_endo_from_authoritative_roster()
		_set_endo_presenter_present(false)
		return
	# A semantic joined flag cannot mint a body. Normal saves contain both the
	# story record and the serialized character; malformed ones fail closed.
	var registered := _game_state != null and _game_state.characters.has("endo")
	if not registered and _game_state != null and _game_state.get_party().has("endo"):
		var party := _game_state.get_party()
		party.erase("endo")
		_game_state.set_party(party)
	_set_endo_presenter_present(registered)


func _baseline_shelter_rest_authority() -> Dictionary:
	return {
		"version": SHELTER_REST_AUTHORITY_VERSION,
		"contract": SHELTER_REST_AUTHORITY_CONTRACT,
		"phase": SHELTER_REST_PHASE_IDLE,
		"party_ids": PARTY_IDS.duplicate(),
		"shelter_center": GameEvent.v3_to_arr(SHELTER_POS),
		"shelter_half_size": [SHELTER_HALF_SIZE.x, SHELTER_HALF_SIZE.y],
		"start_tick": -1.0,
		"dawn_deadline": -1.0,
		"start_day": -1,
		"start_time": -1.0,
		"dawn_day": -1,
		"atp_before": {},
		"cost_applied": false,
	}


func _shelter_rest_authority_state() -> Dictionary:
	if _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(SHELTER_REST_AUTHORITY_KEY, null)
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _valid_shelter_rest_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	if int(saved.get("version", 0)) != SHELTER_REST_AUTHORITY_VERSION \
			or str(saved.get("contract", "")) != SHELTER_REST_AUTHORITY_CONTRACT \
			or saved.get("party_ids", []) != PARTY_IDS:
		return false
	var center_v: Variant = saved.get("shelter_center", [])
	var half_v: Variant = saved.get("shelter_half_size", [])
	if not center_v is Array or not half_v is Array \
			or (center_v as Array).size() != 3 or (half_v as Array).size() != 2 \
			or not GameEvent.arr_to_v3(center_v as Array).is_equal_approx(SHELTER_POS) \
			or not Vector2(
				float((half_v as Array)[0]), float((half_v as Array)[1])
			).is_equal_approx(SHELTER_HALF_SIZE):
		return false
	var phase := str(saved.get("phase", ""))
	if phase == SHELTER_REST_PHASE_IDLE:
		return float(saved.get("start_tick", -1.0)) < 0.0 \
			and float(saved.get("dawn_deadline", -1.0)) < 0.0 \
			and not bool(saved.get("cost_applied", false))
	if phase not in [
		SHELTER_REST_PHASE_COMMITTING,
		SHELTER_REST_PHASE_DAWN_PENDING,
		SHELTER_REST_PHASE_COMPLETE,
	]:
		return false
	var start_tick := float(saved.get("start_tick", -1.0))
	var dawn_deadline := float(saved.get("dawn_deadline", -1.0))
	var atp_before_v: Variant = saved.get("atp_before", {})
	if not is_finite(start_tick) or start_tick < 0.0 \
			or not is_finite(dawn_deadline) or dawn_deadline <= start_tick \
			or int(saved.get("start_day", -1)) < 1 or not atp_before_v is Dictionary:
		return false
	for char_id in PARTY_IDS:
		if not (atp_before_v as Dictionary).has(char_id) \
				or float((atp_before_v as Dictionary).get(char_id, -1.0)) < 1.0:
			return false
	if phase == SHELTER_REST_PHASE_COMMITTING:
		return not bool(saved.get("cost_applied", false))
	return bool(saved.get("cost_applied", false)) \
		and int(saved.get("dawn_day", -1)) >= int(saved.get("start_day", -1)) + 1


func _publish_shelter_rest_authority(authority: Dictionary) -> void:
	if _restoring_shelter_authority or _game_state == null:
		return
	_game_state.set_world_state(SHELTER_REST_AUTHORITY_KEY, authority.duplicate(true))


func _party_inside_authored_shelter() -> bool:
	if _game_state == null or _shelter_party_gate == null \
			or not _shelter_party_gate.is_satisfied():
		return false
	for char_id in PARTY_IDS:
		if not _game_state.characters.has(char_id) or _game_state.is_downed(char_id):
			return false
		var pos := _game_state.get_position(char_id)
		if absf(pos.x - SHELTER_POS.x) > SHELTER_HALF_SIZE.x \
				or absf(pos.z - SHELTER_POS.z) > SHELTER_HALF_SIZE.y \
				or not _game_state.is_at_shelter(char_id):
			return false
	return true


func _shelter_rest_outcome_matches(authority: Dictionary) -> bool:
	if _game_state == null:
		return false
	var start_day := int(authority.get("start_day", -1))
	if _game_state.get_game_day() < start_day + 1 \
			or _game_state.get_time_of_day() > GameState.DAWN_TIME + 0.0001:
		return false
	var atp_before := authority.get("atp_before", {}) as Dictionary
	for char_id in PARTY_IDS:
		if not _game_state.characters.has(char_id) \
				or not is_equal_approx(
					_game_state.get_stat(char_id, "atp"),
					float(atp_before.get(char_id, -1.0)) - 1.0):
			return false
	return true


func _on_shelter_settle_requested(source: Node = null) -> bool:
	var receipt := _consume_leaving_source_receipt(
		source, LEAVING_SOURCE_SHELTER)
	if receipt.is_empty() or _shelter_party_gate == null:
		return false
	if not _shelter_party_gate.begin_open({
		"contract": SHELTER_REST_AUTHORITY_CONTRACT,
		"shelter": "Shelter 1",
		"party_ids": PARTY_IDS.duplicate(),
	}):
		_project_leaving_sources()
		return false
	_project_leaving_sources()
	if _hud != null:
		_hud.show_message("Shelter 1 checks the whole conscious party. Stay together while it settles.", 2.2)
	return true


func _on_shelter_party_blocked(reason: StringName) -> void:
	_project_leaving_sources()
	if _hud != null:
		var member := str(reason).trim_prefix("missing_").trim_prefix("unavailable_").trim_prefix("out_of_range_")
		_hud.show_message(
			"Shelter 1 is waiting for %s." % (member.capitalize() if not member.is_empty() else "the whole party"),
			1.8)


func _on_shelter_party_ready() -> void:
	if _current_step == "second_iron" and _party_inside_authored_shelter():
		_start_reach_shelter()

func _setup_ui() -> void:
	_hud = preload("res://scenes/ui/game_hud.tscn").instantiate()
	add_child(_hud)
	_hud.add_stat_bar("hp", Color(0.7, 0.3, 0.25), GameState.HP_MAX, GameState.HP_MAX)
	_hud.show_center_camera_button("P")
	if _camera != null and not _hud.center_camera_requested.is_connected(_recenter_party_camera):
		_hud.center_camera_requested.connect(_recenter_party_camera)
	# Bind after _game_state exists; route guards still own toggles.

func _recenter_party_camera() -> void:
	if _camera == null:
		return
	var centroid := Vector3.ZERO
	var visible_count := 0
	for entry in [["aster", _player], ["peris", _peris], ["endo", _endo]]:
		var char_id := str(entry[0])
		var character: Node3D = entry[1] as Node3D
		if not is_instance_valid(character) or not character.visible \
				or _game_state == null or not _game_state.characters.has(char_id):
			continue
		if char_id == "endo" and not _endo_is_authoritatively_joined():
			continue
		centroid += character.global_position
		visible_count += 1
	if visible_count > 0:
		_camera.recenter_on(centroid / float(visible_count))

func _begin() -> void:
	if _hud:
		_hud.bind_game_state(_game_state, "aster", false)
	_set_game_time(_game_day, _game_time, false)
	_start_fade_in()

func _on_process(delta: float, spd: float) -> void:
	# Time advances during outdoor phases
	var outdoor := OUTDOOR_STEPS.has(_current_step)
	if outdoor:
		_advance_game_clock(delta * spd)

	# Iron lighting is presentation-only. Damage runs on the fixed scheduler cadence below.
	if outdoor and _current_step != "reach_shelter":
		_update_iron_lights()

	# NPC follow behavior
	_update_npc_follow()

	# Per-frame visual updates
	_update_fades()
	_update_sector_gate_visuals()

	# Position-based step triggers
	if _current_step == "first_corridor":
		var px: float = _game_state.get_position("aster").x
		if px > IRON_1_POS.x - 3.0:
			DialogueData.say_to(_dialogue, "facility.endo.iron_warn")
			_start_safe_route_lesson()
	elif _current_step == "safe_route_lesson":
		var px: float = _game_state.get_position("aster").x
		if px > MIDPOINT.x - 1.0:
			_start_dusk_approaches()

func _update_fades() -> void:
	if _current_step == "fade_in":
		_update_fade_in(2.0)
	elif _current_step == "dawn":
		pass  # No fade

func _update_npc_follow() -> void:
	if _current_step in ["first_corridor", "safe_route_lesson", "dusk_approaches", "second_iron"]:
		var aster_pos := _game_state.get_position("aster")
		# Peris follows
		var peris_pos := _game_state.get_position("peris")
		if aster_pos.distance_to(peris_pos) > 2.5 and not _game_state.is_moving("peris"):
			_game_state.command_move_to_pos("peris", aster_pos + Vector3(-1.2, 0, 0.8))
		# Follow is a roster capability, not a property of the prebuilt hidden node.
		if _endo_is_authoritatively_joined():
			var endo_pos := _game_state.get_position("endo")
			if aster_pos.distance_to(endo_pos) > 3.0 and not _game_state.is_moving("endo"):
				_game_state.command_move_to_pos("endo", aster_pos + Vector3(-1.2, 0, -0.8))

# --- Route gameplay ---

func _build_route_gameplay() -> void:
	var environment := get_node_or_null("Environment") as Node3D
	if environment == null:
		return
	_sector_route_interactables.clear()
	for sector_index in range(IRON_SECTORS.size()):
		var sector: Dictionary = IRON_SECTORS[sector_index]
		var safe_station := _create_interactable(
			environment, sector["safe_station"], "Sector%dSafeStation" % (sector_index + 1),
			2.0, 3.5, "REGROUP / WORK SAFE SEAL", true, Interactable.InteractableType.TIMED_ACTION)
		safe_station.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
		_configure_leaving_source(
			safe_station, _leaving_route_action_id(sector_index, "safe"))
		safe_station.interaction_requested.connect(
			Callable(self, "_on_route_station_requested").bind("safe"))
		_add_route_station_mesh(safe_station, Color(0.22, 0.58, 0.42), "SAFE")
		var direct_station := _create_interactable(
			environment, sector["direct_station"], "Sector%dDirectStation" % (sector_index + 1),
			2.0, 2.0, "REGROUP / FORCE DIRECT SEAL", true, Interactable.InteractableType.TIMED_ACTION)
		direct_station.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
		_configure_leaving_source(
			direct_station, _leaving_route_action_id(sector_index, "direct"))
		direct_station.interaction_requested.connect(
			Callable(self, "_on_route_station_requested").bind("direct"))
		_add_route_station_mesh(direct_station, Color(0.72, 0.24, 0.08), "DIRECT")
		_sector_route_interactables.append([safe_station, direct_station])
		# Only the next physically reachable seal advertises an action. Opening it
		# exposes the following pair without inserting an abstract checklist.
		safe_station.set_interaction_enabled(false)
		direct_station.set_interaction_enabled(false)
	_setup_sector_gate_authority()
	_restore_sector_gate_progression()

	_cache_interactable = _create_interactable(
		environment, CACHE_POS, "LeavingFacilityCache", 2.0, 2.5, "SALVAGE LYSATE",
		true, Interactable.InteractableType.TIMED_ACTION)
	_cache_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_configure_leaving_source(_cache_interactable, LEAVING_SOURCE_CACHE)
	_cache_mesh = _add_route_station_mesh(_cache_interactable, Color(0.67, 0.55, 0.25), "CACHE")
	_retract_cache_to_source(true, false)

	_lookout_interactable = _create_interactable(
		environment, LOOKOUT_POS, "IronLookoutSurvey", 2.0, 3.0, "SURVEY LATTICE",
		true, Interactable.InteractableType.TIMED_ACTION)
	_lookout_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_configure_leaving_source(_lookout_interactable, LEAVING_SOURCE_LOOKOUT)
	_add_route_station_mesh(_lookout_interactable, Color(0.36, 0.68, 0.74), "LOOKOUT")

	# Shelter 1 is one authored spatial mechanism, not a region invented around whichever body
	# happened to reach the corridor endpoint first. The interactable asks for commitment; PartyGate3D
	# checks the complete conscious trio both at commitment and at its short settle endpoint.
	_game_state.add_shelter_region(
		Vector2(SHELTER_POS.x - SHELTER_HALF_SIZE.x, SHELTER_POS.z - SHELTER_HALF_SIZE.y),
		Vector2(SHELTER_POS.x + SHELTER_HALF_SIZE.x, SHELTER_POS.z + SHELTER_HALF_SIZE.y)
	)
	_shelter_party_gate = PartyGate3D.new()
	_shelter_party_gate.name = "Shelter1PartyGate"
	_shelter_party_gate.position = SHELTER_POS
	_shelter_party_gate.required_members = PackedStringArray(PARTY_IDS)
	_shelter_party_gate.readiness_radius = SHELTER_READY_RADIUS
	_shelter_party_gate.authority_id = SHELTER_GATE_AUTHORITY_ID
	_shelter_party_gate.opening_duration = SHELTER_GATE_OPEN_DURATION
	environment.add_child(_shelter_party_gate)
	_shelter_party_gate.setup(_game_state, null, 0, PARTY_IDS)
	_shelter_party_gate.opened.connect(_on_shelter_party_ready)
	_shelter_party_gate.blocked.connect(_on_shelter_party_blocked)
	_shelter_interactable = _create_interactable(
		environment, SHELTER_POS, "Shelter1SettleInteractable", 2.4, 1.0,
		"SETTLE PARTY AT SHELTER 1", true, Interactable.InteractableType.TIMED_ACTION)
	_shelter_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_configure_leaving_source(_shelter_interactable, LEAVING_SOURCE_SHELTER)
	_shelter_interactable.set_interaction_enabled(false)
	_add_route_station_mesh(_shelter_interactable, Color(0.88, 0.63, 0.28), "SHELTER 1")
	_publish_shelter_rest_authority(_baseline_shelter_rest_authority())
	_initialize_leaving_source_authority()


func _leaving_route_action_id(sector_index: int, route_choice: String) -> String:
	return "route:%d:%s" % [sector_index, route_choice]


func _leaving_source_action_ids() -> Array[String]:
	var actions: Array[String] = []
	for sector_index in range(IRON_SECTORS.size()):
		actions.append(_leaving_route_action_id(sector_index, "safe"))
		actions.append(_leaving_route_action_id(sector_index, "direct"))
	actions.append(LEAVING_SOURCE_CACHE)
	actions.append(LEAVING_SOURCE_LOOKOUT)
	actions.append(LEAVING_SOURCE_SHELTER)
	return actions


func _leaving_route_action_context(action_id: String) -> Dictionary:
	var parts := action_id.split(":")
	if parts.size() != 3 or parts[0] != "route" \
			or not parts[1].is_valid_int() or parts[2] not in ["safe", "direct"]:
		return {}
	var sector_index := int(parts[1])
	if sector_index < 0 or sector_index >= IRON_SECTORS.size():
		return {}
	return {
		"sector_index": sector_index,
		"route_choice": str(parts[2]),
	}


func _leaving_source_for_action(action_id: String) -> Node:
	var route := _leaving_route_action_context(action_id)
	if not route.is_empty():
		var sector_index := int(route.get("sector_index", -1))
		var choice_index := 0 if str(route.get("route_choice", "")) == "safe" else 1
		if sector_index >= 0 and sector_index < _sector_route_interactables.size():
			var pair: Array = _sector_route_interactables[sector_index]
			if choice_index < pair.size():
				return pair[choice_index]
		return null
	match action_id:
		LEAVING_SOURCE_CACHE:
			return _cache_interactable
		LEAVING_SOURCE_LOOKOUT:
			return _lookout_interactable
		LEAVING_SOURCE_SHELTER:
			return _shelter_interactable
		_:
			return null


func _leaving_source_data_id(action_id: String) -> String:
	var route := _leaving_route_action_context(action_id)
	if not route.is_empty():
		var suffix := "SafeStation" \
			if str(route.get("route_choice", "")) == "safe" else "DirectStation"
		return "Sector%d%s" % [int(route.get("sector_index", -1)) + 1, suffix]
	match action_id:
		LEAVING_SOURCE_CACHE:
			return "LeavingFacilityCache"
		LEAVING_SOURCE_LOOKOUT:
			return "IronLookoutSurvey"
		LEAVING_SOURCE_SHELTER:
			return "Shelter1SettleInteractable"
		_:
			return ""


func _configure_leaving_source(source: Node, action_id: String) -> void:
	if not is_instance_valid(source):
		return
	source.set("one_shot", true)
	source.set_meta("leaving_source_action", action_id)
	source.call(
		"set_pre_trigger_validator",
		_validate_leaving_source_trigger.bind(action_id, source))
	var callback := _on_leaving_source_interacted.bind(action_id, source)
	if not source.is_connected("interacted", callback):
		source.connect("interacted", callback)
	_ensure_leaving_source_registry_contract(source)


func _on_leaving_source_interacted(action_id: String, source: Node) -> void:
	var route := _leaving_route_action_context(action_id)
	if not route.is_empty():
		_on_sector_route_station_completed(
			int(route.get("sector_index", -1)),
			str(route.get("route_choice", "")),
			source)
		return
	match action_id:
		LEAVING_SOURCE_CACHE:
			_on_cache_collected(source)
		LEAVING_SOURCE_LOOKOUT:
			_on_lookout_surveyed(source)
		LEAVING_SOURCE_SHELTER:
			_on_shelter_settle_requested(source)


func _validate_leaving_source_trigger(
		source: Node,
		actor: String,
		action_id: String,
		expected_source: Node
	) -> bool:
	return is_instance_valid(source) and source == expected_source \
		and source == _leaving_source_for_action(action_id) \
		and _leaving_actor_ready_at_source(source, actor) \
		and _leaving_source_action_ready(action_id) \
		and _leaving_action_physical_preflight(action_id, actor)


func _leaving_source_action_ready(action_id: String) -> bool:
	var route := _leaving_route_action_context(action_id)
	if not route.is_empty():
		var sector_index := int(route.get("sector_index", -1))
		if not _endo_is_authoritatively_joined() \
				or sector_index != _next_sector_gate_index() \
				or sector_index >= _sector_gates.size():
			return false
		return str(_sector_gates[sector_index].get_authority_state().get(
			"phase", PartyGate3D.PHASE_CLOSED)) == PartyGate3D.PHASE_CLOSED
	match action_id:
		LEAVING_SOURCE_CACHE:
			return _cache_phase == CACHE_PHASE_AVAILABLE and _cache_item_at_source()
		LEAVING_SOURCE_LOOKOUT:
			return not _lookout_surveyed
		LEAVING_SOURCE_SHELTER:
			if _current_step != "second_iron" \
					or str(_shelter_rest_authority_state().get(
						"phase", SHELTER_REST_PHASE_IDLE)) != SHELTER_REST_PHASE_IDLE:
				return false
			return _shelter_party_gate != null and str(
				_shelter_party_gate.get_authority_state().get(
					"phase", PartyGate3D.PHASE_CLOSED)
			) == PartyGate3D.PHASE_CLOSED
		_:
			return false


func _leaving_action_physical_preflight(
		action_id: String, actor: String
	) -> bool:
	var route := _leaving_route_action_context(action_id)
	if not route.is_empty():
		var source := _leaving_source_for_action(action_id)
		return _leaving_party_ready_at(
			_leaving_source_data_position(source), ROUTE_REGROUP_RADIUS)
	match action_id:
		LEAVING_SOURCE_CACHE:
			return _game_state.has_free_hands(actor, 1)
		LEAVING_SOURCE_LOOKOUT:
			return true
		LEAVING_SOURCE_SHELTER:
			return _party_inside_authored_shelter() \
				and _leaving_party_action_ready()
		_:
			return false


func _leaving_character_action_ready(character_id: String) -> bool:
	return _game_state != null and _game_state.characters.has(character_id) \
		and _game_state.get_party().has(character_id) \
		and _game_state.is_narratively_available(character_id) \
		and _game_state.get_stat(character_id, "hp") > 0.0 \
		and not _game_state.is_downed(character_id) \
		and not _game_state.is_knocked_down(character_id) \
		and not _game_state.is_moving(character_id) \
		and not _game_state.is_resting(character_id) \
		and not _game_state.is_dodging(character_id) \
		and not _game_state.is_endocytosing(character_id) \
		and not _game_state.is_external_traversal_active(character_id) \
		and not _game_state.is_dragging(character_id) \
		and not _game_state.is_field_restoring(character_id) \
		and not _game_state.is_pushing(character_id)


func _leaving_actor_ready_at_source(source: Node, actor: String) -> bool:
	if _game_state == null or not is_instance_valid(source) \
			or not (source is Node3D) or actor not in PARTY_IDS \
			or not _leaving_character_action_ready(actor):
		return false
	var source_position := _leaving_source_data_position(source)
	if not source_position.is_finite():
		return false
	if _game_state.grid != null and _game_state.grid.level_count > 1 \
			and int(_game_state.get_character_level(actor)) != int(
				_game_state.grid.level_for_y(source_position.y)):
		return false
	var actor_position: Vector3 = _game_state.get_position(actor)
	var radius := float(source.get("interaction_radius")) \
		+ LEAVING_SOURCE_POSITION_TOLERANCE
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)) <= radius \
		and absf(actor_position.y - source_position.y) \
			<= LEAVING_SOURCE_HEIGHT_TOLERANCE


func _leaving_party_action_ready() -> bool:
	for character_id in PARTY_IDS:
		if not _leaving_character_action_ready(character_id):
			return false
	return true


func _leaving_party_ready_at(position: Vector3, radius: float) -> bool:
	if not position.is_finite() or not _leaving_party_action_ready():
		return false
	for character_id in PARTY_IDS:
		var member_position: Vector3 = _game_state.get_position(character_id)
		if Vector2(member_position.x, member_position.z).distance_to(
				Vector2(position.x, position.z)) > radius \
				or absf(member_position.y - position.y) \
					> LEAVING_SOURCE_HEIGHT_TOLERANCE:
			return false
	return true


func _leaving_source_data_position(source: Node) -> Vector3:
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


func _leaving_source_registry_count(action_id: String) -> int:
	if _game_state == null:
		return -1
	var data_id := _leaving_source_data_id(action_id)
	if data_id == "" or not _game_state.has_interactable(data_id):
		return -1
	return int(_game_state.get_interactable(data_id).get("trigger_count", -1))


func _leaving_source_receipt_count(source: Node, action_id: String) -> int:
	if not is_instance_valid(source) or source != _leaving_source_for_action(action_id):
		return -1
	var actor := str(source.get("active_character"))
	if not _validate_leaving_source_trigger(source, actor, action_id, source) \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return -1
	var data_id := str(source.get("data_id"))
	if _game_state == null or data_id != _leaving_source_data_id(action_id) \
			or not _game_state.has_interactable(data_id):
		return -1
	var receipt: Dictionary = _game_state.get_interactable(data_id)
	var trigger_count := int(receipt.get("trigger_count", -1))
	if not bool(receipt.get("one_shot", false)) \
			or not bool(receipt.get("triggered", false)) \
			or bool(receipt.get("enabled", true)) \
			or str(receipt.get("last_trigger_character", "")) != actor \
			or trigger_count <= int(
				_leaving_source_committed_counts.get(action_id, 0)):
		return -1
	return trigger_count


func _consume_leaving_source_receipt(
		source: Node, action_id: String
	) -> Dictionary:
	var trigger_count := _leaving_source_receipt_count(source, action_id)
	if trigger_count < 0:
		return {}
	var actor := str(source.get("active_character"))
	_leaving_source_committed_counts[action_id] = trigger_count
	# The source edge commits before PartyGate, item, knowledge, or rest authority can emit.
	_publish_leaving_source_authority()
	return {
		"action": action_id,
		"actor": actor,
		"trigger_count": trigger_count,
	}


func _baseline_leaving_source_authority() -> Dictionary:
	var counts := {}
	for action_id in _leaving_source_action_ids():
		counts[action_id] = 0
	return {
		"version": LEAVING_SOURCE_AUTHORITY_VERSION,
		"contract": LEAVING_SOURCE_AUTHORITY_CONTRACT,
		"committed_counts": counts,
	}


func _leaving_source_authority_state() -> Dictionary:
	if _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(
		LEAVING_SOURCE_AUTHORITY_KEY, null)
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _valid_leaving_source_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	var counts_v: Variant = saved.get("committed_counts", null)
	if int(saved.get("version", 0)) != LEAVING_SOURCE_AUTHORITY_VERSION \
			or str(saved.get("contract", "")) != LEAVING_SOURCE_AUTHORITY_CONTRACT \
			or not counts_v is Dictionary:
		return false
	var counts := counts_v as Dictionary
	for action_id in _leaving_source_action_ids():
		if not counts.has(action_id) or int(counts.get(action_id, -1)) < 0:
			return false
	return true


func _initialize_leaving_source_authority() -> void:
	if _game_state == null:
		return
	var saved := _leaving_source_authority_state()
	if _valid_leaving_source_authority(saved):
		_leaving_source_committed_counts = (
			saved.get("committed_counts", {}) as Dictionary).duplicate(true)
		return
	_leaving_source_committed_counts.clear()
	for action_id in _leaving_source_action_ids():
		_leaving_source_committed_counts[action_id] = 0
	_publish_leaving_source_authority()


func _publish_leaving_source_authority() -> void:
	if _restoring_leaving_source_authority or _game_state == null:
		return
	var counts := {}
	for action_id in _leaving_source_action_ids():
		counts[action_id] = maxi(
			0, int(_leaving_source_committed_counts.get(action_id, 0)))
	_game_state.set_world_state(LEAVING_SOURCE_AUTHORITY_KEY, {
		"version": LEAVING_SOURCE_AUTHORITY_VERSION,
		"contract": LEAVING_SOURCE_AUTHORITY_CONTRACT,
		"committed_counts": counts,
	})


func _ensure_leaving_source_registry_contract(source: Node) -> void:
	if _game_state == null or not is_instance_valid(source):
		return
	var data_id := str(source.get("data_id"))
	if data_id == "" or not _game_state.has_interactable(data_id):
		return
	var spec: Dictionary = _game_state.get_interactable(data_id)
	if bool(spec.get("one_shot", false)):
		return
	spec["one_shot"] = true
	_game_state.interactables[data_id] = spec


func _rearm_leaving_source(source: Node) -> void:
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


func _set_leaving_source_enabled(source: Node, enabled: bool) -> void:
	if not is_instance_valid(source):
		return
	_ensure_leaving_source_registry_contract(source)
	var data_id := str(source.get("data_id"))
	if _game_state == null or data_id == "" \
			or not _game_state.has_interactable(data_id):
		return
	var spec: Dictionary = _game_state.get_interactable(data_id)
	if enabled:
		if bool(spec.get("triggered", false)):
			_rearm_leaving_source(source)
		else:
			_game_state.set_interactable_enabled(data_id, true)
			if source.has_method("restore_one_shot_presenter"):
				source.call("restore_one_shot_presenter", false, true)
		return
	_game_state.set_interactable_enabled(data_id, false)
	if source.has_method("restore_one_shot_presenter"):
		source.call(
			"restore_one_shot_presenter",
			bool(spec.get("triggered", false)),
			false)


func _project_leaving_sources() -> void:
	for action_id in _leaving_source_action_ids():
		_set_leaving_source_enabled(
			_leaving_source_for_action(action_id),
			_leaving_source_action_ready(action_id))


func _restore_leaving_source_authority() -> void:
	if _game_state == null:
		return
	_restoring_leaving_source_authority = true
	var raw := _leaving_source_authority_state()
	var migrated := not _valid_leaving_source_authority(raw)
	_leaving_source_committed_counts.clear()
	if not migrated:
		_leaving_source_committed_counts = (
			raw.get("committed_counts", {}) as Dictionary).duplicate(true)
	else:
		for action_id in _leaving_source_action_ids():
			_leaving_source_committed_counts[action_id] = maxi(
				0, _leaving_source_registry_count(action_id))
	var reconciled := false
	for action_id in _leaving_source_action_ids():
		var registry_count := maxi(0, _leaving_source_registry_count(action_id))
		var committed_count := maxi(
			0, int(_leaving_source_committed_counts.get(action_id, 0)))
		if registry_count > committed_count:
			# The exact source fired, but its semantic owner did not. Burn that edge and rearm only
			# when the physical mechanism/item/knowledge/rest phase is still genuinely ready.
			_leaving_source_committed_counts[action_id] = registry_count
			reconciled = true
	_restoring_leaving_source_authority = false
	_project_leaving_sources()
	if migrated or reconciled:
		_publish_leaving_source_authority()


func _setup_sector_gate_authority() -> void:
	for sector_index in range(_sector_gates.size()):
		var gate := _sector_gates[sector_index]
		var opening_callback := Callable(self, "_on_sector_gate_opening_started").bind(sector_index)
		var opened_callback := Callable(self, "_on_sector_gate_opened").bind(sector_index)
		var blocked_callback := Callable(self, "_on_sector_gate_blocked").bind(sector_index)
		if not gate.opening_started.is_connected(opening_callback):
			gate.opening_started.connect(opening_callback)
		if not gate.opened.is_connected(opened_callback):
			gate.opened.connect(opened_callback)
		if not gate.blocked.is_connected(blocked_callback):
			gate.blocked.connect(blocked_callback)
		gate.setup(_game_state, _grid, 0, ["aster", "peris", "endo"])

func _add_route_station_mesh(interactable: Node3D, color: Color, station_label: String) -> Node3D:
	var assembly := Node3D.new()
	assembly.name = "%sAssembly" % station_label.capitalize()
	interactable.add_child(assembly)
	var plinth := MeshInstance3D.new()
	var plinth_mesh := CylinderMesh.new()
	plinth_mesh.top_radius = 0.42
	plinth_mesh.bottom_radius = 0.58
	plinth_mesh.height = 0.85
	plinth.mesh = plinth_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.45)
	mat.metallic = 0.35
	mat.roughness = 0.62
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.3
	plinth.material_override = mat
	plinth.position.y = 0.43
	assembly.add_child(plinth)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.68, 0.16, 0.52)
	plate.mesh = plate_mesh
	plate.material_override = mat
	plate.position = Vector3(0, 0.95, 0)
	assembly.add_child(plate)
	var label := Label3D.new()
	label.text = station_label
	label.font_size = 28
	label.pixel_size = 0.009
	label.modulate = color.lightened(0.25)
	label.outline_modulate = Color(0.025, 0.025, 0.03, 0.95)
	label.outline_size = 9
	label.position = Vector3(0, 1.48, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	assembly.add_child(label)
	# Route gameplay is built before the shared outline manager exists. Bind on
	# the deferred frame so every visible station still gets object-level hover
	# and click feedback through the common tutorial outline system.
	call_deferred("_bind_route_station_outline", interactable, assembly, station_label)
	return assembly

func _bind_route_station_outline(interactable: Node3D, assembly: Node3D, station_label: String) -> void:
	if not is_instance_valid(interactable) or not is_instance_valid(assembly):
		return
	var target := _outline_object_meshes(
		interactable, "%sOutline" % station_label.capitalize(),
		_collect_mesh_instances(assembly), "leaving_facility.%s" % station_label.to_lower(), 0.8)
	_set_room_target_interaction_delegate(target, interactable)

func _set_sector_route_available(sector_index: int, available: bool) -> void:
	if sector_index < 0 or sector_index >= _sector_route_interactables.size():
		return
	for seal_station in _sector_route_interactables[sector_index]:
		_set_leaving_source_enabled(seal_station, available)
		if available:
			seal_station.call_deferred("show_tutorial_label")

func _on_sector_route_station_completed(
		sector_index: int,
		route_choice: String,
		source: Node = null
	) -> bool:
	var action_id := _leaving_route_action_id(sector_index, route_choice)
	var receipt := _consume_leaving_source_receipt(source, action_id)
	if receipt.is_empty():
		return false
	return _commit_sector_route(sector_index, route_choice)

func _set_gate_grid_open(gate_x: float, opened: bool) -> void:
	if _grid == null:
		return
	var gate_cell := _grid.world_to_grid(Vector3(gate_x, 0, 0))
	if not opened:
		for z in range(_grid.height):
			_grid.set_tile(gate_cell.x, z, GridWorld.Tile.WALL)
		return
	# Keep the sector bulkheads in place and open only the marked central seal.
	for dz in range(-3, 4):
		_grid.set_tile(gate_cell.x, gate_cell.y + dz, GridWorld.Tile.FLOOR)

func _on_route_station_requested(_target: Node, world_position: Vector3, route_choice: String) -> void:
	# The generic interaction controller may have issued its first path during the
	# same click. Re-issue it after applying this station's route mode so the path
	# to SAFE really detours and the path to DIRECT really crosses the risk field.
	_apply_routing_mode(route_choice, false)
	if _game_state != null:
		_game_state.command_move_to_pos("aster", world_position)

## Compatibility surface retained for old callers and malicious/manual signal tests.
## A route consequence is accepted only through the exact registered source receipt.
func _on_sector_route_committed(
		_sector_index: int, _route_choice: String
	) -> bool:
	return false


func _commit_sector_route(sector_index: int, route_choice: String) -> bool:
	if sector_index < 0 or sector_index >= _sector_gates_open.size():
		return false
	if not _endo_is_authoritatively_joined():
		if _hud != null:
			_hud.show_message("Wait for the full party before working the route seal.", 1.8)
		_project_leaving_sources()
		return false
	if route_choice not in ["safe", "direct"]:
		_project_leaving_sources()
		return false
	if sector_index != _next_sector_gate_index():
		if _hud != null:
			_hud.show_message("Open the route seals in corridor order.", 1.8)
		_project_leaving_sources()
		return false
	if sector_index >= _sector_gates.size():
		_project_leaving_sources()
		return false
	var station_pos: Vector3 = IRON_SECTORS[sector_index]["safe_station" if route_choice == "safe" else "direct_station"]
	var missing_party: Array[String] = []
	for char_id in ["aster", "peris", "endo"]:
		if not _game_state.characters.has(char_id) \
				or _game_state.get_position(char_id).distance_to(station_pos) > ROUTE_REGROUP_RADIUS:
			missing_party.append(char_id.capitalize())
	if not missing_party.is_empty():
		if _hud != null:
			_hud.show_message("The seal needs the whole party. Regroup with %s." % ", ".join(missing_party), 2.3)
		_project_leaving_sources()
		return false
	var sector: Dictionary = IRON_SECTORS[sector_index]
	var context := {
		"contract": SECTOR_GATE_CONTEXT_CONTRACT,
		"sector_index": sector_index,
		"sector_id": str(sector["id"]),
		"route_choice": route_choice,
		"commit_order": sector_index,
	}
	if not _sector_gates[sector_index].begin_open(context):
		_project_leaving_sources()
		return false
	_apply_routing_mode(route_choice, false)
	_project_leaving_sources()
	return true


func _on_sector_gate_opening_started(sector_index: int) -> void:
	_restore_sector_gate_progression()
	if _hud != null:
		_hud.show_message("%s seal is lifting. Keep the party together." %
			str(IRON_SECTORS[sector_index]["label"]), 1.8)


func _on_sector_gate_opened(sector_index: int) -> void:
	_restore_sector_gate_progression()
	var route_choice := _sector_route_choices[sector_index]
	if _hud != null:
		_hud.show_message("%s seal opened via %s route." % [
			str(IRON_SECTORS[sector_index]["label"]), route_choice.to_upper()], 2.0)


func _on_sector_gate_blocked(reason: StringName, sector_index: int) -> void:
	_restore_sector_gate_progression()
	if _hud != null:
		var detail := str(reason).trim_prefix("out_of_range_").trim_prefix("unavailable_")
		_hud.show_message("%s seal stopped; regroup with %s and work it again." % [
			str(IRON_SECTORS[sector_index]["label"]), detail.capitalize()], 2.3)


func _next_sector_gate_index() -> int:
	for sector_index in range(_sector_gates.size()):
		var phase := str(_sector_gates[sector_index].get_authority_state().get(
			"phase", PartyGate3D.PHASE_CLOSED))
		if phase == PartyGate3D.PHASE_OPEN:
			continue
		if phase == PartyGate3D.PHASE_CLOSED:
			return sector_index
		# A seal that is visibly opening owns the one active commitment. A later
		# station cannot be used during its saved window.
		return -1
	return -1


func _sector_gate_context(saved: Dictionary) -> Dictionary:
	var context_v: Variant = saved.get("context", {})
	return (context_v as Dictionary).duplicate(true) if context_v is Dictionary else {}


func _sector_gate_record_is_valid(sector_index: int, saved: Dictionary) -> bool:
	var phase := str(saved.get("phase", PartyGate3D.PHASE_CLOSED))
	if phase == PartyGate3D.PHASE_CLOSED:
		return true
	if phase not in [PartyGate3D.PHASE_OPENING, PartyGate3D.PHASE_OPEN]:
		return false
	var start_tick := float(saved.get("start_tick", -1.0))
	var end_tick := float(saved.get("end_tick", -1.0))
	if not is_finite(start_tick) or not is_finite(end_tick) or end_tick <= start_tick:
		return false
	var context := _sector_gate_context(saved)
	var route_choice := str(context.get("route_choice", ""))
	return str(context.get("contract", "")) == SECTOR_GATE_CONTEXT_CONTRACT \
		and int(context.get("sector_index", -1)) == sector_index \
		and int(context.get("commit_order", -1)) == sector_index \
		and str(context.get("sector_id", "")) == str(IRON_SECTORS[sector_index]["id"]) \
		and route_choice in ["safe", "direct"]


## Project scene-local arrays, station affordances, GridWorld cells, and the lift
## presenter from PartyGate3D records. These are all derived views: only the
## versioned gate records survive a save.
func _restore_sector_gate_progression() -> void:
	if _grid == null or _game_state == null:
		return
	for sector_index in range(_sector_route_interactables.size()):
		_set_sector_route_available(sector_index, false)
	var prefix_open := true
	var opening_seen := false
	var roster_ready := _endo_is_authoritatively_joined()
	for sector_index in range(_sector_gates.size()):
		var gate := _sector_gates[sector_index]
		var saved := gate.get_authority_state()
		var phase := str(saved.get("phase", PartyGate3D.PHASE_CLOSED))
		var valid := not saved.is_empty() and _sector_gate_record_is_valid(sector_index, saved)
		if not roster_ready and phase != PartyGate3D.PHASE_CLOSED:
			valid = false
		if phase != PartyGate3D.PHASE_CLOSED and (not prefix_open or opening_seen):
			valid = false
		if not valid:
			gate.restore_closed_baseline()
			saved = gate.get_authority_state()
			phase = PartyGate3D.PHASE_CLOSED
		var context := _sector_gate_context(saved)
		_sector_gates_open[sector_index] = phase == PartyGate3D.PHASE_OPEN
		_sector_route_choices[sector_index] = str(context.get("route_choice", "")) \
			if phase != PartyGate3D.PHASE_CLOSED else ""
		_set_gate_grid_open(float(IRON_SECTORS[sector_index]["gate_x"]),
			phase == PartyGate3D.PHASE_OPEN)
		if phase == PartyGate3D.PHASE_OPENING:
			opening_seen = true
			prefix_open = false
		elif phase == PartyGate3D.PHASE_CLOSED:
			prefix_open = false
	if not opening_seen and roster_ready:
		var next_sector := _sector_gates_open.find(false)
		if next_sector >= 0:
			_set_sector_route_available(next_sector, true)
	_update_sector_gate_visuals()


func _update_sector_gate_visuals() -> void:
	var now := float(_scheduler.get_current_tick()) if _scheduler != null else 0.0
	for sector_index in range(mini(_sector_gates.size(), _sector_gate_visuals.size())):
		var saved := _sector_gates[sector_index].get_authority_state()
		var phase := str(saved.get("phase", PartyGate3D.PHASE_CLOSED))
		var progress := 0.0
		if phase == PartyGate3D.PHASE_OPEN:
			progress = 1.0
		elif phase == PartyGate3D.PHASE_OPENING:
			var start_tick := float(saved.get("start_tick", now))
			var end_tick := float(saved.get("end_tick", start_tick + SECTOR_GATE_OPEN_DURATION))
			progress = clampf((now - start_tick) / maxf(end_tick - start_tick, 0.000001), 0.0, 1.0)
		# Smoothstep is a presenter sample only. The saved endpoint still owns
		# collision and GridWorld commitment.
		var eased := progress * progress * (3.0 - 2.0 * progress)
		var panel := _sector_gate_visuals[sector_index]
		panel.visible = true
		panel.position.y = lerpf(SECTOR_GATE_CLOSED_Y, SECTOR_GATE_OPEN_Y, eased)

func _baseline_cache_authority() -> Dictionary:
	return {
		"version": CACHE_AUTHORITY_VERSION,
		"contract": CACHE_AUTHORITY_CONTRACT,
		"source_fixture": CACHE_SOURCE_FIXTURE,
		"source_position": GameEvent.v3_to_arr(CACHE_POS),
		"item_type": CACHE_ITEM_TYPE,
		"item_id": _cache_item_id,
		"phase": CACHE_PHASE_AVAILABLE,
		"claimed_by": "",
		"claim_serial": 0,
	}


func _cache_authority_state() -> Dictionary:
	var state := _baseline_cache_authority()
	state["item_id"] = _cache_item_id
	state["phase"] = _cache_phase
	state["claimed_by"] = _cache_claimed_by
	state["claim_serial"] = _cache_claim_serial
	return state


func _valid_cache_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	if int(saved.get("version", 0)) != CACHE_AUTHORITY_VERSION \
			or str(saved.get("contract", "")) != CACHE_AUTHORITY_CONTRACT \
			or str(saved.get("source_fixture", "")) != CACHE_SOURCE_FIXTURE \
			or str(saved.get("item_type", "")) != CACHE_ITEM_TYPE:
		return false
	var source_v: Variant = saved.get("source_position", [])
	if not source_v is Array or (source_v as Array).size() != 3 \
			or not GameEvent.arr_to_v3(source_v as Array).is_equal_approx(CACHE_POS):
		return false
	var phase := str(saved.get("phase", ""))
	var claimed_by := str(saved.get("claimed_by", ""))
	var serial := int(saved.get("claim_serial", -1))
	if str(saved.get("item_id", "")) == "" or serial < 0:
		return false
	if phase == CACHE_PHASE_AVAILABLE:
		return claimed_by == "" and serial >= 0
	if phase in [CACHE_PHASE_CLAIMING, CACHE_PHASE_CLAIMED]:
		return claimed_by != "" and serial >= 1
	return false


func _publish_cache_authority() -> void:
	if _restoring_cache_authority or _game_state == null:
		return
	_game_state.set_world_state(CACHE_AUTHORITY_KEY, _cache_authority_state())


func _spawn_cache_source_item(properties: Dictionary = {}) -> String:
	var item_properties := {
		"display_name": "Iron-route Lysate",
		"visual_color": Color(0.72, 0.64, 0.34),
		"atp_restore": 2.0,
		"source_authority": CACHE_AUTHORITY_KEY,
		"source_fixture": CACHE_SOURCE_FIXTURE,
		"endocytosis_allowed": true,
	}
	item_properties.merge(properties, true)
	return spawn_preview_item(CACHE_ITEM_TYPE, CACHE_POS, item_properties)


func _is_cache_item(item_id: String) -> bool:
	if _game_state == null or not _game_state.items.has(item_id):
		return false
	var item: Dictionary = _game_state.items[item_id]
	var properties: Dictionary = item.get("properties", {})
	return str(item.get("type", "")) == CACHE_ITEM_TYPE \
		and str(properties.get("source_authority", "")) == CACHE_AUTHORITY_KEY \
		and str(properties.get("source_fixture", "")) == CACHE_SOURCE_FIXTURE


func _find_cache_item_id() -> String:
	if _game_state == null:
		return ""
	var candidates: Array[String] = []
	for item_id_v in _game_state.items.keys():
		var item_id := str(item_id_v)
		if _is_cache_item(item_id):
			candidates.append(item_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""


func _remove_cache_items(except_id := "") -> void:
	if _game_state == null:
		return
	var remove_ids: Array[String] = []
	for item_id_v in _game_state.items.keys():
		var item_id := str(item_id_v)
		if item_id != except_id and _is_cache_item(item_id):
			remove_ids.append(item_id)
	for item_id in remove_ids:
		remove_preview_item(item_id)


func _cache_item_at_source() -> bool:
	if not _is_cache_item(_cache_item_id):
		return false
	var item: Dictionary = _game_state.items[_cache_item_id]
	return str(item.get("location", "")) == "ground" \
		and (item.get("position", CACHE_POS) as Vector3).distance_to(CACHE_POS) <= 0.05


func _cache_item_holder() -> String:
	if not _is_cache_item(_cache_item_id):
		return ""
	return str((_game_state.items[_cache_item_id] as Dictionary).get("holder", ""))


func _apply_cache_interactable_state() -> void:
	var available := _cache_phase == CACHE_PHASE_AVAILABLE and _cache_item_at_source()
	_cache_collected = _cache_phase == CACHE_PHASE_CLAIMED and not _cache_item_at_source()
	if is_instance_valid(_cache_interactable):
		_set_leaving_source_enabled(_cache_interactable, available)
	if is_instance_valid(_cache_mesh):
		_cache_mesh.visible = available
	_refresh_chunk_item_presenters()


## Snapshot absence and old boolean-only scenes cannot identify a carrier or a particular item. They
## therefore retract to one visible source item instead of manufacturing ownership in Aster's hand.
func _retract_cache_to_source(publish_state := true, legacy_recovery := true) -> void:
	_remove_cache_items()
	var source_properties := {"legacy_source_recovery": true} if legacy_recovery else {}
	_cache_item_id = _spawn_cache_source_item(source_properties)
	_cache_phase = CACHE_PHASE_AVAILABLE
	_cache_claimed_by = ""
	_cache_claim_serial = 0
	_cache_collected = false
	_apply_cache_interactable_state()
	if publish_state:
		_publish_cache_authority()


func _restore_cache_authority() -> void:
	var raw: Variant = _game_state.get_world_state(CACHE_AUTHORITY_KEY, null) \
		if _game_state != null else null
	if not _valid_cache_authority(raw):
		_retract_cache_to_source()
		return
	var saved := raw as Dictionary
	_restoring_cache_authority = true
	_cache_item_id = str(saved.get("item_id", ""))
	_cache_phase = str(saved.get("phase", CACHE_PHASE_AVAILABLE))
	_cache_claimed_by = str(saved.get("claimed_by", ""))
	_cache_claim_serial = int(saved.get("claim_serial", 0))

	if not _is_cache_item(_cache_item_id):
		_cache_item_id = _find_cache_item_id()
	_remove_cache_items(_cache_item_id)
	match _cache_phase:
		CACHE_PHASE_AVAILABLE:
			# A moved item without a published reservation is malformed history. Return exactly
			# one item to the authored cache instead of accepting an unexplained carrier.
			if not _cache_item_at_source():
				_remove_cache_items()
				_cache_item_id = _spawn_cache_source_item()
			_cache_claimed_by = ""
		CACHE_PHASE_CLAIMING:
			if not _is_cache_item(_cache_item_id):
				_cache_item_id = _spawn_cache_source_item()
				_cache_phase = CACHE_PHASE_AVAILABLE
				_cache_claimed_by = ""
			elif _cache_item_at_source():
				_cache_phase = CACHE_PHASE_AVAILABLE
				_cache_claimed_by = ""
			elif _cache_item_holder() == _cache_claimed_by:
				_cache_phase = CACHE_PHASE_CLAIMED
			# A different holder is not silently retargeted or accepted: remain CLAIMING and
			# disabled so the malformed save cannot grant the reward transaction.
		CACHE_PHASE_CLAIMED:
			if _cache_item_at_source():
				_cache_phase = CACHE_PHASE_AVAILABLE
				_cache_claimed_by = ""
	_restoring_cache_authority = false
	_apply_cache_interactable_state()
	_publish_cache_authority()


## The timed lid/work interaction only requests this exact source-item transfer. GameState owns the
## distance and hand checks, while CLAIMING is published first so a pickup-signal save has one honest
## interpretation on either a same-presenter or fresh-presenter restore.
func _on_cache_collected(source: Node = null) -> bool:
	var receipt := _consume_leaving_source_receipt(
		source, LEAVING_SOURCE_CACHE)
	if receipt.is_empty():
		return false
	var actor := str(receipt.get("actor", ""))
	if actor == "" or _game_state == null or not _game_state.characters.has(actor):
		_project_leaving_sources()
		return false
	if not _game_state.has_free_hands(actor, 1):
		if _hud != null:
			_hud.show_message("%s needs a free hand for the lysate." % actor.capitalize(), 1.8)
		_project_leaving_sources()
		return false

	_cache_phase = CACHE_PHASE_CLAIMING
	_cache_claimed_by = actor
	_cache_claim_serial += 1
	_apply_cache_interactable_state()
	_publish_cache_authority()
	if not pick_up_preview_item(actor, _cache_item_id):
		_cache_phase = CACHE_PHASE_AVAILABLE
		_cache_claimed_by = ""
		_apply_cache_interactable_state()
		_publish_cache_authority()
		if _hud != null:
			_hud.show_message("The lysate remains in the cache; stand close with one hand free.", 1.8)
		return false

	_cache_phase = CACHE_PHASE_CLAIMED
	_cache_collected = true
	_apply_cache_interactable_state()
	_publish_cache_authority()
	if _hud != null:
		_hud.show_message("%s secured the lysate for later endocytosis or shelter rest." % actor.capitalize(), 2.8)
	return true

func _on_lookout_surveyed(source: Node = null) -> bool:
	var receipt := _consume_leaving_source_receipt(
		source, LEAVING_SOURCE_LOOKOUT)
	if receipt.is_empty():
		return false
	_lookout_surveyed = true
	_publish_iron_hazard_authority()
	_project_leaving_sources()
	if _hud != null:
		_hud.show_message(
			"Lookout mapped: the third lattice pulses every %.1f s. SAFE beacons remain the mitigation." \
			% IRON_DAMAGE_INTERVAL, 3.0)
	return true

func headless_get_anchor_positions() -> Dictionary:
	var anchors := {
		"facility_exit": EXIT_POS,
		"sector_1_iron": IRON_1_POS,
		"sector_1_safe": SAFE_1_WAYPOINT,
		"sector_1_gate": Vector3(float(IRON_SECTORS[0]["gate_x"]), 0, 0),
		"side_cache": CACHE_POS,
		"sector_2_iron": IRON_2_POS,
		"sector_2_safe": SAFE_2_WAYPOINT,
		"sector_2_gate": Vector3(float(IRON_SECTORS[1]["gate_x"]), 0, 0),
		"lookout": LOOKOUT_POS,
		"sector_3_iron": IRON_3_POS,
		"sector_3_safe": SAFE_3_WAYPOINT,
		"sector_3_gate": Vector3(float(IRON_SECTORS[2]["gate_x"]), 0, 0),
		"shelter": SHELTER_POS,
	}
	return anchors

func headless_get_state() -> Dictionary:
	var state := super.headless_get_state()
	var sector_gate_phases: Array[String] = []
	var sector_gate_contexts: Array[Dictionary] = []
	for gate in _sector_gates:
		var saved := gate.get_authority_state()
		sector_gate_phases.append(str(saved.get("phase", PartyGate3D.PHASE_CLOSED)))
		sector_gate_contexts.append(_sector_gate_context(saved))
	state.merge({
		"routing_mode": _routing_mode,
		"route_cautious": _game_state.is_route_cautious() if _game_state != null else true,
		"sector_gates_open": _sector_gates_open.duplicate(),
		"sector_route_choices": _sector_route_choices.duplicate(),
		"sector_gate_phases": sector_gate_phases,
		"sector_gate_contexts": sector_gate_contexts,
		"endo_join_authority": _endo_join_authority_state(),
		"endo_registered": _game_state != null and _game_state.characters.has("endo"),
		"endo_in_party": _game_state != null and _game_state.get_party().has("endo"),
		"endo_visible": is_instance_valid(_endo) and _endo.visible,
		"endo_present": _endo_is_authoritatively_joined(),
		"shelter_gate_phase": str(_shelter_party_gate.get_authority_state().get(
			"phase", PartyGate3D.PHASE_CLOSED)) if _shelter_party_gate != null else "missing",
		"shelter_party_ready": _party_inside_authored_shelter(),
		"shelter_rest_authority": _shelter_rest_authority_state(),
		"sectors_entered": _sectors_entered.duplicate(),
		"cache_collected": _cache_collected,
		"cache_item_id": _cache_item_id,
		"cache_phase": _cache_phase,
		"cache_claimed_by": _cache_claimed_by,
		"cache_claim_serial": _cache_claim_serial,
		"cache_item_at_source": _cache_item_at_source(),
		"cache_item_holder": _cache_item_holder(),
		"lookout_surveyed": _lookout_surveyed,
		"source_committed_counts": _leaving_source_committed_counts.duplicate(true),
		"iron_damage_total": _iron_damage_total,
		"iron_exposure_seconds": _iron_exposure_seconds,
		"authored_route_meters": SHELTER_POS.x - EXIT_POS.x,
		"sector_count": IRON_SECTORS.size(),
		"optional_branch_count": 2,
		"route_regroup_radius": ROUTE_REGROUP_RADIUS,
	}, true)
	return state

func _modeled_route_meters(route_choice := "direct") -> float:
	var total := 0.0
	var cursor := EXIT_POS
	for sector_index in range(IRON_SECTORS.size()):
		var sector: Dictionary = IRON_SECTORS[sector_index]
		if route_choice == "safe":
			var waypoint: Vector3 = sector["safe_waypoint"]
			total += cursor.distance_to(waypoint)
			cursor = waypoint
		var station_pos: Vector3 = sector["safe_station" if route_choice == "safe" else "direct_station"]
		total += cursor.distance_to(station_pos)
		cursor = station_pos
		var gate_pos := Vector3(float(sector["gate_x"]), 0, 0)
		total += cursor.distance_to(gate_pos)
		cursor = gate_pos
	total += cursor.distance_to(SHELTER_POS)
	return total

func get_playtime_contract() -> Dictionary:
	# Lower-bound first-clear model. It includes only authored movement, real timed
	# work, and fixed transitions; dialogue reading time is deliberately excluded.
	# The sprint allowance uses the live full-stamina economy (100 / 15 s drain at
	# 6 m/s = 40 m). Everything after that is priced at the live 3 m/s walk speed.
	var direct_route_meters := _modeled_route_meters("direct")
	var safe_route_meters := _modeled_route_meters("safe")
	var run_drain := 15.0
	if _game_state != null:
		run_drain = maxf(0.001, float(_game_state.run_stamina_drain_per_sec))
	var sprint_seconds_available := GameState.STAMINA_MAX / run_drain
	var sprint_distance := minf(direct_route_meters, sprint_seconds_available * GameState.RUN_SPEED)
	var traversal_seconds := (
		sprint_distance / GameState.RUN_SPEED
		+ (direct_route_meters - sprint_distance) / GameState.WALK_SPEED
	)
	var direct_seal_work_seconds := float(IRON_SECTORS.size()) * 2.0
	var mandatory_interaction_seconds := direct_seal_work_seconds
	var active_seconds := traversal_seconds + mandatory_interaction_seconds
	var modeled_total_seconds := active_seconds + MODELED_FIXED_TRANSITION_SECONDS
	return {
		"target_minutes": Vector2(1.25, 2.0),
		"target_first_clear_seconds": Vector2(75.0, 120.0),
		"modeled_shortest_clean_first_clear_seconds": modeled_total_seconds,
		"modeled_meaningful_active_seconds": active_seconds,
		"meaningful_active_seconds": active_seconds,
		"total_play_seconds": modeled_total_seconds,
		"modeled_active_ratio": active_seconds / modeled_total_seconds,
		"modeled_traversal_seconds": traversal_seconds,
		"modeled_mandatory_interaction_seconds": mandatory_interaction_seconds,
		"modeled_direct_seal_work_seconds": direct_seal_work_seconds,
		"modeled_fixed_transition_seconds": MODELED_FIXED_TRANSITION_SECONDS,
		"dialogue_seconds_in_model": 0.0,
		"idle_padding_seconds": 0.0,
		"model_basis": "shortest direct seal route; one full stamina bar; dialogue excluded",
		"critical_route_meters": SHELTER_POS.x - EXIT_POS.x,
		"shortest_route_meters": direct_route_meters,
		"safe_route_estimate_meters": safe_route_meters,
		"direct_route_estimate_meters": direct_route_meters,
		"sprint_distance_allowance_meters": sprint_distance,
		"mandatory_seal_actions": IRON_SECTORS.size(),
		"mandatory_route_actions": IRON_SECTORS.size(),
		"mandatory_party_regroups": IRON_SECTORS.size(),
		"optional_branches": ["lysate_cache", "iron_lookout"],
		"route_choices_per_sector": ["safe", "direct"],
		"decision_count": IRON_SECTORS.size(),
		"branch_count": IRON_SECTORS.size() + 2,
	}

# --- Input ---

# Route (Tab) and run (Z) arrive as HUD signals (routing_toggled / run_toggled)
# mapped from the input map by GameHUD — wired in _start_first_corridor.

# --- Event-driven steps ---

func _start_fade_in() -> void:
	_current_step = "fade_in"
	_fade_from(Color(0.03, 0.03, 0.04, 1), 2.5, _start_facility_exit, "facility_exit")
	_player.set_move_enabled(false)

func _start_facility_exit() -> void:
	_current_step = "facility_exit"
	var orig_offset: Vector3 = _camera.follow_offset
	var t := create_tween()
	t.tween_property(_camera, "follow_offset", orig_offset + Vector3(3, 0, 0), 1.5)
	t.tween_interval(0.5)
	t.tween_property(_camera, "follow_offset", orig_offset, 1.0)
	_begin_endo_join_wait()


func _begin_endo_join_wait() -> void:
	if _scheduler == null or _game_state == null:
		return
	var saved := _endo_join_authority_state()
	if _valid_endo_join_authority(saved):
		var phase := str(saved.get("phase", ENDO_JOIN_PHASE_ABSENT))
		if phase == ENDO_JOIN_PHASE_PENDING:
			_arm_endo_join_from_authority()
			return
		if phase == ENDO_JOIN_PHASE_JOINED:
			_sync_endo_presence_from_authority()
			return
	var now := float(_scheduler.get_current_tick())
	var pending := _baseline_endo_join_authority()
	pending["phase"] = ENDO_JOIN_PHASE_PENDING
	pending["start_tick"] = now
	pending["deadline"] = now + ENDO_JOIN_DELAY
	_publish_endo_join_authority(pending)
	_arm_endo_join_from_authority()


func _arm_endo_join_from_authority() -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(ENDO_JOIN_TAG)
	var saved := _endo_join_authority_state()
	if not _valid_endo_join_authority(saved) \
			or str(saved.get("phase", "")) != ENDO_JOIN_PHASE_PENDING:
		return
	var now := float(_scheduler.get_current_tick())
	var deadline := float(saved.get("deadline", now))
	if deadline <= now:
		_commit_endo_join()
		return
	_scheduler.schedule_at(deadline, _commit_endo_join, ENDO_JOIN_TAG)


func _commit_endo_join() -> void:
	if _scheduler == null or _game_state == null:
		return
	var saved := _endo_join_authority_state()
	if not _valid_endo_join_authority(saved) \
			or str(saved.get("phase", "")) != ENDO_JOIN_PHASE_PENDING:
		return
	var now := float(_scheduler.get_current_tick())
	var deadline := float(saved.get("deadline", now))
	if now + 0.000001 < deadline:
		_arm_endo_join_from_authority()
		return
	# Register the physical body and party membership before publishing JOINED. These operations
	# emit no gameplay signal; therefore the first observable join signal can only see a complete
	# roster/body transaction. The entrance move is a subsequent, separately authoritative action.
	if not _prepare_endo_join_body():
		return
	saved["phase"] = ENDO_JOIN_PHASE_JOINED
	saved["joined_tick"] = maxf(now, deadline)
	_publish_endo_join_authority(saved)
	_start_endo_joins()


func _prepare_endo_join_body() -> bool:
	if _game_state == null or not is_instance_valid(_endo):
		return false
	if not _game_state.characters.has("endo"):
		_endo.position = EXIT_POS + Vector3(3, 0, -2)
		_register_gs_character("endo", _endo, 2.5, {
			"hp": GameState.HP_MAX, "stamina": GameState.STAMINA_MAX, "atp": 4.0})
	var party := _game_state.get_party()
	for required_id in PARTY_IDS:
		if not party.has(required_id) and _game_state.characters.has(required_id):
			party.append(required_id)
	if not party.has("endo"):
		_remove_endo_from_authoritative_roster()
		return false
	if _game_state.get_party() != party:
		_game_state.set_party(party)
	_set_endo_presenter_present(true)
	return true

func _start_endo_joins() -> void:
	var saved := _endo_join_authority_state()
	if not _valid_endo_join_authority(saved) \
			or str(saved.get("phase", "")) != ENDO_JOIN_PHASE_JOINED:
		return
	_current_step = "endo_joins"
	_sync_endo_presence_from_authority()
	_restore_sector_gate_progression()
	_game_state.command_move_to_pos("endo", EXIT_POS + Vector3(1.5, 0, -0.8))
	_dialogue_chain(["facility.endo.shelters"], _start_first_corridor)

func _start_first_corridor() -> void:
	if not _endo_is_authoritatively_joined():
		return
	_current_step = "first_corridor"
	_start_iron_hazard_cadence()
	_player.set_move_enabled(true)
	if _hud:
		_hud.show_routing_toggle("safe")
		if not _hud.routing_toggled.is_connected(_on_routing_toggled):
			_hud.routing_toggled.connect(_on_routing_toggled)
		_hud.show_run_toggle(false)
		if not _hud.run_toggled.is_connected(_on_run_toggled):
			_hud.run_toggled.connect(_on_run_toggled)
		_hud.show_message(
			"Reach Shelter 1. At each iron field, regroup and choose the SAFE detour or DIRECT crossing.",
			6.0
		)
	_set_game_time(_game_day, _game_time, true)

func _start_safe_route_lesson() -> void:
	_current_step = "safe_route_lesson"

func _start_dusk_approaches() -> void:
	_current_step = "dusk_approaches"
	_set_game_time(_game_day, 0.4, true)
	DialogueData.say_to(_dialogue, "facility.endo.dusk")
	_schedule_portable_method(4.0, _start_second_iron, "second_iron")

func _start_second_iron() -> void:
	_current_step = "second_iron"
	_project_leaving_sources()

func _start_reach_shelter() -> void:
	if not _party_inside_authored_shelter():
		_on_shelter_party_blocked(&"out_of_range_party")
		return
	_current_step = "reach_shelter"
	_stop_iron_hazard_cadence()
	if _shelter_interactable != null:
		_shelter_interactable.set_interaction_enabled(false)
	for char_id in PARTY_IDS:
		_game_state.command_stop(char_id)
	_player.set_move_enabled(false)
	DialogueData.say_to(_dialogue, "facility.endo.shelter")
	_schedule_portable_method(2.5, _start_first_rest, "first_rest")

func _start_first_rest() -> void:
	_current_step = "first_rest"
	_set_game_time(_game_day, 0.55, true)
	if not _party_inside_authored_shelter() or not _game_state.can_party_rest(PARTY_IDS):
		_reject_shelter_rest("The whole conscious party must be settled, still, and able to pay one ATP each.")
		return
	# Night transition: dim world, pulse iron threat
	var t := create_tween()
	t.tween_property(_dir_light, "light_energy", 0.05, 1.5)
	for light in _iron_lights:
		var lt := create_tween()
		lt.set_loops(3)
		lt.tween_property(light, "light_energy", 3.5, 0.8)
		lt.tween_property(light, "light_energy", 1.5, 0.8)
	DialogueData.say_to(_dialogue, "facility.endo.rest")
	var now := float(_scheduler.get_current_tick())
	var authority := _baseline_shelter_rest_authority()
	authority["phase"] = SHELTER_REST_PHASE_COMMITTING
	authority["start_tick"] = now
	authority["dawn_deadline"] = now + SHELTER_DAWN_DELAY
	authority["start_day"] = _game_state.get_game_day()
	authority["start_time"] = _game_state.get_time_of_day()
	var atp_before := {}
	for char_id in PARTY_IDS:
		atp_before[char_id] = _game_state.get_stat(char_id, "atp")
	authority["atp_before"] = atp_before
	# COMMITTING is published before cost. A save on this signal is truthfully pre-payment; the
	# canonical party command below then changes every ATP/rest/night fact before its first signal.
	_publish_shelter_rest_authority(authority)
	_complete_shelter_rest_commit(authority)


func _complete_shelter_rest_commit(authority: Dictionary) -> void:
	if not _game_state.command_party_rest(PARTY_IDS):
		_publish_shelter_rest_authority(_baseline_shelter_rest_authority())
		_reject_shelter_rest("The party rest transaction was refused without charging anyone.")
		return
	if not _shelter_rest_outcome_matches(authority):
		# This cannot happen after a successful night batch; retain COMMITTING so a diagnostic save
		# never lies by calling a partial result complete.
		_reject_shelter_rest("Shelter 1 could not produce a complete dawn. No partial result is accepted.", false)
		return
	authority["phase"] = SHELTER_REST_PHASE_DAWN_PENDING
	authority["cost_applied"] = true
	authority["dawn_day"] = _game_state.get_game_day()
	_publish_shelter_rest_authority(authority)
	_arm_shelter_dawn(authority)


func _reject_shelter_rest(message: String, reset_authority := true) -> void:
	_scheduler.cancel_tag(SHELTER_DAWN_TAG)
	if reset_authority:
		_publish_shelter_rest_authority(_baseline_shelter_rest_authority())
	_current_step = "second_iron"
	if _shelter_party_gate != null:
		_shelter_party_gate.restore_closed_baseline()
	_project_leaving_sources()
	_player.set_move_enabled(true)
	_start_iron_hazard_cadence()
	if _hud != null:
		_hud.show_message(message, 2.8)


func _arm_shelter_dawn(authority: Dictionary) -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(SHELTER_DAWN_TAG)
	var deadline := float(authority.get("dawn_deadline", -1.0))
	var now := float(_scheduler.get_current_tick())
	if deadline <= now + 0.000001:
		_scheduler.schedule_after(0.000001, _start_dawn, SHELTER_DAWN_TAG)
	else:
		_scheduler.schedule_at(deadline, _start_dawn, SHELTER_DAWN_TAG)

func _start_dawn() -> void:
	if _current_step != "first_rest":
		return
	_current_step = "dawn"
	_sync_game_clock_from_authority(true)
	var authority := _shelter_rest_authority_state()
	if _valid_shelter_rest_authority(authority):
		if str(authority.get("phase", "")) == SHELTER_REST_PHASE_COMMITTING \
				and _shelter_rest_outcome_matches(authority):
			authority["cost_applied"] = true
			authority["dawn_day"] = _game_state.get_game_day()
		authority["phase"] = SHELTER_REST_PHASE_COMPLETE
		_publish_shelter_rest_authority(authority)
	_dialogue_chain(["facility.dawn"], _complete_facility_sequence)


func _complete_facility_sequence() -> void:
	_current_step = "complete"

# --- Routing ---

func _toggle_run() -> void:
	if _game_state == null:
		return
	_game_state.toggle_running("aster")

func _on_run_toggled(_running: bool) -> void:
	_toggle_run()

func _on_routing_toggled(mode: String) -> void:
	_apply_routing_mode(mode, true)

func _apply_routing_mode(mode: String, announce := false) -> void:
	_routing_mode = "direct" if mode == "direct" else "safe"
	if _game_state != null:
		_game_state.set_route_mode(_routing_mode == "safe")
	if _hud != null:
		_hud.set_routing_mode(_routing_mode)
		if announce:
			var explanation := "marked detours avoid recoverable iron" if _routing_mode == "safe" else "short lines cross iron and cost party health"
			_hud.show_message("%s routing: %s." % [_routing_mode.capitalize(), explanation], 2.2)

func _toggle_routing() -> void:
	_apply_routing_mode("direct" if _routing_mode == "safe" else "safe", true)

# --- Iron damage ---

## The scheduler owns iron contact outcomes. The versioned record survives callback-heap clearing,
## preserves the exact next tick, and also carries the cumulative QA evidence that used to reset.
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
	if _game_state == null or not OUTDOOR_STEPS.has(_current_step) \
			or _current_step == "reach_shelter":
		return
	var aster_pos := _game_state.get_position("aster")
	for sector_index in range(IRON_SECTORS.size()):
		var sector: Dictionary = IRON_SECTORS[sector_index]
		var center: Vector3 = sector["center"]
		var half_size: Vector2 = sector["half_size"]
		if abs(aster_pos.x - center.x) <= half_size.x + 2.0 and not _sectors_entered.has(str(sector["id"])):
			_sectors_entered.append(str(sector["id"]))
			if _hud != null:
				_hud.show_message("%s: SAFE follows the outer beacons; DIRECT crosses the iron." % str(sector["label"]), 3.0)
		for char_id in ["aster", "peris", "endo"]:
			if not _game_state.characters.has(char_id) or _game_state.get_stat(char_id, "hp") <= 0.0:
				continue
			if char_id == "endo" and not _endo_is_authoritatively_joined():
				continue
			var pos := _game_state.get_position(char_id)
			if abs(pos.x - center.x) > half_size.x or abs(pos.z - center.z) > half_size.y:
				continue
			# Surveying reveals the cadence and route; information cannot physically weaken iron.
			var multiplier := 1.0
			if char_id == "endo":
				multiplier *= 1.15
			var damage := IRON_DAMAGE_PER_SEC * multiplier * IRON_DAMAGE_INTERVAL
			_game_state.adjust_stat(char_id, "hp", -damage, IRON_HAZARD_TAG)
			_iron_damage_total += damage
			_iron_exposure_seconds += IRON_DAMAGE_INTERVAL


func _update_iron_lights() -> void:
	if _game_state == null:
		return
	for sector_index in range(IRON_SECTORS.size()):
		var sector: Dictionary = IRON_SECTORS[sector_index]
		var center: Vector3 = sector["center"]
		var half_size: Vector2 = sector["half_size"]
		var sector_active := false
		for char_id in ["aster", "peris", "endo"]:
			if not _game_state.characters.has(char_id):
				continue
			if char_id == "endo" and not _endo_is_authoritatively_joined():
				continue
			var pos := _game_state.get_position(char_id)
			if abs(pos.x - center.x) <= half_size.x and abs(pos.z - center.z) <= half_size.y:
				sector_active = true
				break
		if sector_active and sector_index < _iron_lights.size():
			var light := _iron_lights[sector_index]
			light.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.01) * 1.5  # @rendering_only


func _publish_iron_hazard_authority() -> void:
	if _restoring_iron_hazard or _game_state == null:
		return
	_game_state.set_world_state(IRON_HAZARD_AUTHORITY_KEY, {
		"version": IRON_HAZARD_AUTHORITY_VERSION,
		"active": _iron_hazard_active,
		"next_tick": _iron_hazard_next_tick,
		"damage_total": _iron_damage_total,
		"exposure_seconds": _iron_exposure_seconds,
		"sectors_entered": _sectors_entered.duplicate(),
		"lookout_surveyed": _lookout_surveyed,
	})


func _restore_shelter_rest_authority() -> void:
	if _scheduler == null or _game_state == null:
		return
	_scheduler.cancel_tag(SHELTER_DAWN_TAG)
	_scheduler.cancel_tag(SHELTER_REST_COMMIT_TAG)
	_restoring_shelter_authority = true
	_sync_game_clock_from_authority(_current_step != "fade_in")
	if _shelter_party_gate != null:
		_shelter_party_gate.on_game_state_snapshot_restored()
	var authority := _shelter_rest_authority_state()
	if not _valid_shelter_rest_authority(authority):
		authority = _baseline_shelter_rest_authority()
	var phase := str(authority.get("phase", SHELTER_REST_PHASE_IDLE))
	match phase:
		SHELTER_REST_PHASE_COMMITTING:
			_current_step = "first_rest"
			if _shelter_rest_outcome_matches(authority):
				_arm_shelter_dawn(authority)
			else:
				# A save made by the COMMITTING publication owns the pending transaction even
				# though no ATP was paid yet. Resume on the scheduler after attachment rather
				# than mutating or emitting gameplay from the restore hook itself.
				_scheduler.schedule_after(
					0.000001,
					_complete_shelter_rest_commit.bind(authority.duplicate(true)),
					SHELTER_REST_COMMIT_TAG)
		SHELTER_REST_PHASE_DAWN_PENDING:
			_current_step = "first_rest"
			if _shelter_rest_outcome_matches(authority):
				_arm_shelter_dawn(authority)
			else:
				# A paid semantic record without the canonical dawn is malformed. It cannot
				# grant progression; preserve inspection state but arm no consequence.
				_current_step = "second_iron"
		SHELTER_REST_PHASE_COMPLETE:
			_current_step = "dawn" if _current_step != "complete" else "complete"
		_:
			# `reach_shelter` is now a legitimate portable pre-commit phase: the party is
			# physically settled and the saved named continuation owns the exact hand-off to
			# `_start_first_rest`. Only later phases require a committed rest transaction.
			if _current_step in ["first_rest", "dawn"]:
				_current_step = "second_iron"
	_restoring_shelter_authority = false
	var rest_committed := phase in [
		SHELTER_REST_PHASE_COMMITTING,
		SHELTER_REST_PHASE_DAWN_PENDING,
		SHELTER_REST_PHASE_COMPLETE,
	]
	if _shelter_interactable != null:
		_shelter_interactable.set_interaction_enabled(
			_current_step == "second_iron" and not rest_committed)
	if _player != null and _player.has_method("restore_move_input_enabled"):
		_player.restore_move_input_enabled(
			not rest_committed and _current_step != "reach_shelter"
		)


func _restore_endo_join_authority() -> void:
	if _scheduler == null or _game_state == null:
		return
	_scheduler.cancel_tag(ENDO_JOIN_TAG)
	_configure_endo_presenter()
	_wire_endo_join_signals()
	var saved := _endo_join_authority_state()
	if not _valid_endo_join_authority(saved):
		# Saves from before the roster contract existed still carry an authoritative
		# sequence step and serialized character roster. Migrate only when those two
		# independent facts agree; a semantic later step may never invent a missing body.
		if ENDO_JOINED_STEPS.has(_current_step) and _game_state.characters.has("endo"):
			var now := float(_scheduler.get_current_tick())
			saved = _baseline_endo_join_authority()
			saved["phase"] = ENDO_JOIN_PHASE_JOINED
			saved["start_tick"] = maxf(0.0, now - ENDO_JOIN_DELAY)
			saved["deadline"] = maxf(0.000001, now)
			if float(saved["deadline"]) <= float(saved["start_tick"]):
				saved["start_tick"] = maxf(0.0, float(saved["deadline"]) - ENDO_JOIN_DELAY)
			saved["joined_tick"] = float(saved["deadline"])
		else:
			saved = _baseline_endo_join_authority()
		_publish_endo_join_authority(saved)
	_sync_endo_presence_from_authority()
	if str(saved.get("phase", "")) == ENDO_JOIN_PHASE_PENDING:
		_arm_endo_join_from_authority()


func on_game_state_snapshot_restored() -> void:
	if _scheduler == null or _game_state == null:
		return
	_restore_endo_join_authority()
	_restore_shelter_rest_authority()
	# Validate the ordered gate prefix before child PartyGate3D presenters attach.
	# This closes malformed/out-of-order records to the physical baseline rather
	# than granting a route skip on load.
	_restore_sector_gate_progression()
	_restore_cache_authority()
	_scheduler.cancel_tag(IRON_HAZARD_TAG)
	_restoring_iron_hazard = true
	_iron_hazard_active = false
	_iron_hazard_next_tick = -1.0
	_iron_damage_total = 0.0
	_iron_exposure_seconds = 0.0
	_sectors_entered.clear()
	_lookout_surveyed = false
	var saved_v: Variant = _game_state.get_world_state(IRON_HAZARD_AUTHORITY_KEY, null)
	if saved_v is Dictionary:
		var saved := saved_v as Dictionary
		if int(saved.get("version", 0)) == IRON_HAZARD_AUTHORITY_VERSION:
			_iron_hazard_active = bool(saved.get("active", false))
			_iron_hazard_next_tick = float(saved.get("next_tick", -1.0))
			_iron_damage_total = maxf(0.0, float(saved.get("damage_total", 0.0)))
			_iron_exposure_seconds = maxf(0.0, float(saved.get("exposure_seconds", 0.0)))
			for sector_v in saved.get("sectors_entered", []):
				var sector_id := str(sector_v)
				if sector_id != "" and not _sectors_entered.has(sector_id):
					_sectors_entered.append(sector_id)
			_lookout_surveyed = bool(saved.get("lookout_surveyed", false))
			if _iron_hazard_active and _iron_hazard_next_tick >= 0.0:
				_arm_iron_hazard_at(_iron_hazard_next_tick)
	_restoring_iron_hazard = false
	if is_instance_valid(_lookout_interactable):
		if _lookout_surveyed:
			_lookout_interactable.set_interaction_enabled(false)
		else:
			_lookout_interactable.reset()
			_lookout_interactable.set_interaction_enabled(true)
	_restore_leaving_source_authority()


# --- Environment ---

func _build_environment() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	var ground := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(CORRIDOR_LENGTH, 0.1, CORRIDOR_HALF_WIDTH * 2.0)
	ground.mesh = gb
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.1, 0.1, 0.12)
	ground.material_override = gm
	ground.position = Vector3((CORRIDOR_X_MIN + CORRIDOR_X_MAX) * 0.5, -0.05, 0)
	env.add_child(ground)

	var fbody := StaticBody3D.new()
	fbody.position = Vector3((CORRIDOR_X_MIN + CORRIDOR_X_MAX) * 0.5, -0.01, 0)
	fbody.collision_layer = 1
	fbody.collision_mask = 0
	var fcol := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(CORRIDOR_LENGTH, 0.02, CORRIDOR_HALF_WIDTH * 2.0)
	fcol.shape = fshape
	fbody.add_child(fcol)
	env.add_child(fbody)

	var wc := Color(0.13, 0.12, 0.14)
	var corridor_center_x := (CORRIDOR_X_MIN + CORRIDOR_X_MAX) * 0.5
	_add_wall(env, Vector3(corridor_center_x, 1.5, -CORRIDOR_HALF_WIDTH), Vector3(CORRIDOR_LENGTH, 3, 0.3), wc)
	_add_wall(env, Vector3(corridor_center_x, 1.5, CORRIDOR_HALF_WIDTH), Vector3(CORRIDOR_LENGTH, 3, 0.3), wc)
	_add_wall(env, Vector3(CORRIDOR_X_MIN, 1.5, 0), Vector3(0.4, 3, CORRIDOR_HALF_WIDTH * 2.0), Color(0.08, 0.08, 0.1))

	_add_shelter(env, SHELTER_POS)
	for sector_index in range(IRON_SECTORS.size()):
		var sector: Dictionary = IRON_SECTORS[sector_index]
		_add_iron_patch(env, sector["center"], sector["half_size"], str(sector["label"]))
		_add_detour_markers(env, sector["center"], sector["safe_waypoint"], 7)
		_add_detour_markers(env, sector["safe_waypoint"], sector["safe_station"], 7)
		_add_sector_gate_visual(env, sector_index)
		_add_sector_identity(env, sector_index)
	_add_side_branch_markers(env)

	_dir_light = DirectionalLight3D.new()
	_dir_light.rotation_degrees = Vector3(-50, 20, 0)
	_dir_light.light_color = Color(0.6, 0.55, 0.5)
	_dir_light.light_energy = 0.5
	_dir_light.shadow_enabled = true
	env.add_child(_dir_light)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.28, 0.25)
	e.ambient_light_energy = 0.4
	e.glow_enabled = true
	e.glow_intensity = 0.3
	we.environment = e
	env.add_child(we)
	_world_environment = e
	_apply_time_of_day_visuals()

func _advance_game_clock(delta_seconds: float) -> void:
	if delta_seconds <= 0.0 or _game_state == null:
		return
	# Gameplay time is the scheduler-analytic GameState clock. Render delta only decides when its
	# current projection is sampled for the HUD/lighting; it never advances the simulation.
	_sync_game_clock_from_authority(true)

func _set_game_time(day: int, time_of_day: float, show_time := true) -> void:
	if _game_state != null:
		_game_state.set_game_clock(maxi(day, 1), clampf(float(time_of_day), 0.0, 1.0))
	_sync_game_clock_from_authority(show_time)


func _sync_game_clock_from_authority(show_time := true) -> void:
	if _game_state != null:
		_game_day = _game_state.get_game_day()
		_game_time = _game_state.get_time_of_day()
	if _hud != null:
		if show_time:
			_hud.show_time(_game_day, _game_time)
		else:
			_hud.hide_time()
	_apply_time_of_day_visuals()

func _sync_game_time_display() -> void:
	if _hud != null:
		_hud.set_time(_game_day, _game_time)
	_apply_time_of_day_visuals()

func _apply_time_of_day_visuals() -> void:
	if _dir_light == null or _world_environment == null:
		return

	var normalized := clampf(_game_time, 0.0, 1.0)
	if normalized < DayNightCycleScript.NIGHT_START:
		var dusk_blend := clampf(normalized / DayNightCycleScript.NIGHT_START, 0.0, 1.0)
		_world_environment.background_color = Color(0.06, 0.07, 0.09).lerp(Color(0.12, 0.08, 0.06), dusk_blend)
		_world_environment.ambient_light_color = Color(0.32, 0.34, 0.38).lerp(Color(0.42, 0.31, 0.23), dusk_blend)
		# WebGL's linear lighting renders the old dusk floor almost black. Keep the
		# atmosphere, but preserve enough fill to read route seams and interactables.
		_world_environment.ambient_light_energy = lerpf(0.58, 0.40, dusk_blend)
		_world_environment.glow_intensity = lerpf(0.22, 0.34, dusk_blend)
		_dir_light.light_color = Color(0.7, 0.73, 0.78).lerp(Color(0.92, 0.52, 0.24), dusk_blend)
		_dir_light.light_energy = lerpf(0.86, 0.42, dusk_blend)
		return

	var night_blend := clampf((normalized - DayNightCycleScript.NIGHT_START) / DayNightCycleScript.SEGMENT_SPAN, 0.0, 1.0)
	_world_environment.background_color = Color(0.03, 0.03, 0.05).lerp(Color(0.01, 0.012, 0.02), night_blend)
	_world_environment.ambient_light_color = Color(0.12, 0.14, 0.2).lerp(Color(0.05, 0.06, 0.09), night_blend)
	_world_environment.ambient_light_energy = lerpf(0.24, 0.12, night_blend)
	_world_environment.glow_intensity = lerpf(0.32, 0.14, night_blend)
	_dir_light.light_color = Color(0.24, 0.34, 0.54).lerp(Color(0.1, 0.14, 0.26), night_blend)
	_dir_light.light_energy = lerpf(0.22, 0.08, night_blend)

func _add_iron_patch(parent: Node3D, pos: Vector3, half_size := Vector2(2.0, 2.0), sector_label := "Fe") -> void:
	var patch := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(half_size.x * 2.0, 0.02, half_size.y * 2.0)
	patch.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.35, 0.15, 0.05)
	pm.emission_enabled = true
	pm.emission = Color(0.25, 0.08, 0.02)
	pm.emission_energy_multiplier = 0.4
	patch.material_override = pm
	patch.position = pos + Vector3(0, 0.01, 0)
	parent.add_child(patch)

	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 0.5, 0)
	light.light_color = Color(0.7, 0.25, 0.05)
	light.light_energy = 2.0
	light.omni_range = maxf(7.0, minf(14.0, maxf(half_size.x, half_size.y) + 2.0))
	parent.add_child(light)
	_iron_lights.append(light)

	var lbl := Label3D.new()
	lbl.text = sector_label
	lbl.font_size = 64
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.8, 0.3, 0.1, 0.5)
	lbl.position = pos + Vector3(0, 0.3, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)

func _add_sector_gate_visual(parent: Node3D, sector_index: int) -> void:
	var sector: Dictionary = IRON_SECTORS[sector_index]
	var gate_x := float(sector["gate_x"])
	# Side pylons frame the only traversable opening. PartyGate3D owns the
	# scheduled lift and physical blocker; this sequence changes the central
	# GridWorld cells only when that mechanism reaches its saved endpoint.
	_add_wall(parent, Vector3(gate_x, 1.45, -9.2), Vector3(0.45, 2.9, 11.6), Color(0.11, 0.1, 0.1))
	_add_wall(parent, Vector3(gate_x, 1.45, 9.2), Vector3(0.45, 2.9, 11.6), Color(0.11, 0.1, 0.1))
	var gate := PartyGate3D.new()
	gate.name = "SectorGateMechanism%d" % (sector_index + 1)
	gate.position = Vector3(gate_x, 0.0, 0.0)
	gate.authority_id = "leaving_facility_sector_gate_%d" % sector_index
	gate.required_members = PackedStringArray(["aster", "peris", "endo"])
	gate.readiness_radius = SECTOR_GATE_REVALIDATION_RADIUS
	gate.opening_duration = SECTOR_GATE_OPEN_DURATION
	gate.navigation_padding = Vector2(0.15, 0.15)
	parent.add_child(gate)

	var markers := Node3D.new()
	markers.name = "Markers"
	gate.add_child(markers)
	var anchor := Marker3D.new()
	anchor.name = "InteractionAnchor"
	markers.add_child(anchor)

	var blocker_body := StaticBody3D.new()
	blocker_body.name = "RubbleBlocker"
	blocker_body.collision_layer = 1
	blocker_body.collision_mask = 0
	gate.add_child(blocker_body)
	var blocker_shape := CollisionShape3D.new()
	blocker_shape.name = "BlockerShape"
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(0.42, 2.5, 6.0)
	blocker_shape.shape = blocker_box
	blocker_shape.position = Vector3(0.0, SECTOR_GATE_CLOSED_Y, 0.0)
	blocker_body.add_child(blocker_shape)

	var panel := MeshInstance3D.new()
	panel.name = "SectorGate%d" % (sector_index + 1)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.38, 2.5, 6.0)
	panel.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.12, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(0.62, 0.2, 0.04)
	mat.emission_energy_multiplier = 0.25
	panel.material_override = mat
	panel.position = Vector3(0.0, SECTOR_GATE_CLOSED_Y, 0.0)
	gate.add_child(panel)
	_sector_gates.append(gate)
	_sector_gate_visuals.append(panel)

func _add_sector_identity(parent: Node3D, sector_index: int) -> void:
	var sector: Dictionary = IRON_SECTORS[sector_index]
	var center: Vector3 = sector["center"]
	# Each sector receives a different floor datum, so its route problem reads at
	# camera height before the player reaches the damaging material.
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(float((sector["half_size"] as Vector2).x * 2.0 + 12.0), 0.012, 1.0 + sector_index * 0.35)
	band.mesh = band_mesh
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = [
		Color(0.24, 0.11, 0.055),
		Color(0.18, 0.14, 0.07),
		Color(0.22, 0.08, 0.045),
	][sector_index]
	band.material_override = band_mat
	band.position = center + Vector3(0, 0.012, 0)
	parent.add_child(band)
	var label := Label3D.new()
	label.text = str(sector["label"])
	label.font_size = 42
	label.pixel_size = 0.008
	label.modulate = Color(0.93, 0.52, 0.22, 0.9)
	label.position = Vector3(center.x - float((sector["half_size"] as Vector2).x) - 3.0, 2.25, -CORRIDOR_HALF_WIDTH + 0.35)
	parent.add_child(label)

func _add_side_branch_markers(parent: Node3D) -> void:
	for branch in [
		{"pos": CACHE_POS, "text": "SIDE CACHE / LYSATE"},
		{"pos": LOOKOUT_POS, "text": "IRON LOOKOUT"},
	]:
		var pos: Vector3 = branch["pos"]
		var stripe := MeshInstance3D.new()
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(4.0, 0.014, 0.22)
		stripe.mesh = stripe_mesh
		var stripe_mat := StandardMaterial3D.new()
		stripe_mat.albedo_color = Color(0.24, 0.44, 0.31)
		stripe_mat.emission_enabled = true
		stripe_mat.emission = Color(0.12, 0.34, 0.2)
		stripe_mat.emission_energy_multiplier = 0.55
		stripe.material_override = stripe_mat
		stripe.position = Vector3(pos.x, 0.015, pos.z)
		parent.add_child(stripe)
		var label := Label3D.new()
		label.text = str(branch["text"])
		label.font_size = 30
		label.pixel_size = 0.007
		label.modulate = Color(0.58, 0.86, 0.67, 0.88)
		label.position = pos + Vector3(0, 1.8, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(label)

func _add_detour_markers(parent: Node3D, iron_pos: Vector3, waypoint: Vector3, count: int) -> void:
	for i in range(count):
		var t := float(i) / float(count - 1) if count > 1 else 0.5
		var pos := iron_pos.lerp(waypoint, t)
		var marker := MeshInstance3D.new()
		var mb := BoxMesh.new()
		mb.size = Vector3(0.6, 0.015, 0.6)
		marker.mesh = mb
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.18, 0.58, 0.36)
		mm.emission_enabled = true
		mm.emission = Color(0.12, 0.48, 0.28)
		mm.emission_energy_multiplier = 1.1
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = mm
		marker.position = pos + Vector3(0, 0.005, 0)
		parent.add_child(marker)

func _add_shelter(parent: Node3D, pos: Vector3) -> void:
	# The visible Shelter 1 shell and the authoritative PartyGate use the same fixed footprint.
	# It stays open toward the approach (-X), while its other three walls make the exact settle
	# volume readable without relying on an invisible Aster-only coordinate threshold.
	var width := SHELTER_HALF_SIZE.x * 2.0
	var depth := SHELTER_HALF_SIZE.y * 2.0
	var wall_color := Color(0.14, 0.13, 0.12)
	_add_wall(parent, pos + Vector3(0, 1.15, -SHELTER_HALF_SIZE.y),
		Vector3(width, 2.3, 0.25), wall_color)
	_add_wall(parent, pos + Vector3(0, 1.15, SHELTER_HALF_SIZE.y),
		Vector3(width, 2.3, 0.25), wall_color)
	_add_wall(parent, pos + Vector3(SHELTER_HALF_SIZE.x, 1.15, 0),
		Vector3(0.25, 2.3, depth), wall_color)
	_add_wall(parent, pos + Vector3(0, 2.3, 0),
		Vector3(width, 0.15, depth), Color(0.12, 0.11, 0.1))

	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 1.5, 0)
	light.light_color = Color(0.8, 0.6, 0.35)
	light.light_energy = 2.5
	light.omni_range = maxf(width, depth)
	parent.add_child(light)

	var lbl := Label3D.new()
	lbl.text = "SHELTER 1"
	lbl.font_size = 36
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.4, 0.5, 0.7, 0.6)
	lbl.position = pos + Vector3(0, 2.65, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)

# --- Decorations ---

func _build_decorations() -> void:
	var env_node: Node = find_child("Environment", false, false)
	if not env_node:
		return

	# Exposed vasculature.
	var pipe_mat := StandardMaterial3D.new()
	pipe_mat.albedo_color = Color(0.18, 0.1, 0.08)
	pipe_mat.roughness = 0.6
	# Main artery along the corridor
	var artery := MeshInstance3D.new()
	var ac := CylinderMesh.new()
	ac.top_radius = 0.15
	ac.bottom_radius = 0.15
	ac.height = SHELTER_POS.x - EXIT_POS.x + 2.0
	artery.mesh = ac
	artery.material_override = pipe_mat
	artery.position = Vector3((SHELTER_POS.x + EXIT_POS.x) * 0.5, 2.7, -5.0)
	artery.rotation.z = PI / 2.0
	env_node.add_child(artery)
	# Branching capillaries
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.2, 0.1, 0.07)
	for i in range(24):
		var cap := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.04
		cc.bottom_radius = 0.06
		cc.height = 3.0 + fmod(i * 1.3, 2.0)
		cap.mesh = cc
		cap.material_override = cap_mat
		cap.position = Vector3(3.0 + i * 8.6, 2.7, -5.0)
		cap.rotation.x = PI / 2.0
		cap.rotation.z = 0.3 * (1 if i % 2 == 0 else -1)
		env_node.add_child(cap)

	# Iron deposit growths.
	var rust_mat := StandardMaterial3D.new()
	rust_mat.albedo_color = Color(0.4, 0.15, 0.05)
	rust_mat.emission_enabled = true
	rust_mat.emission = Color(0.2, 0.06, 0.02)
	rust_mat.emission_energy_multiplier = 0.3
	rust_mat.roughness = 0.9
	for iron_x in [IRON_1_POS.x, IRON_2_POS.x, IRON_3_POS.x]:
		for j in range(5):
			var nodule := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.08 + fmod(j * 0.7, 0.12)
			sp.height = sp.radius * 1.6
			nodule.mesh = sp
			nodule.material_override = rust_mat
			var side := 1.0 if j % 2 == 0 else -1.0
			nodule.position = Vector3(
				iron_x - 1.5 + j * 0.8,
				0.3 + fmod(j * 0.5, 0.6),
				side * (CORRIDOR_HALF_WIDTH - 0.2)
			)
			env_node.add_child(nodule)

	# Support struts.
	var strut_mat := StandardMaterial3D.new()
	strut_mat.albedo_color = Color(0.1, 0.1, 0.12)
	for i in range(24):
		var strut := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.1, 2.5, 0.1)
		strut.mesh = sb
		strut.material_override = strut_mat
		strut.position = Vector3(5.0 + i * 8.8, 1.5, -CORRIDOR_HALF_WIDTH + 0.2)
		strut.rotation.z = 0.2
		env_node.add_child(strut)

	# Emergency route beacons.
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(0.2, 0.4, 0.3)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(0.15, 0.35, 0.2)
	beacon_mat.emission_energy_multiplier = 1.5
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var beacon_positions := [
		SAFE_1_WAYPOINT + Vector3(-2, 0, 0),
		SAFE_1_WAYPOINT,
		SAFE_1_WAYPOINT + Vector3(2, 0, 0),
		SAFE_2_WAYPOINT + Vector3(-2, 0, 0),
		SAFE_2_WAYPOINT,
		SAFE_2_WAYPOINT + Vector3(2, 0, 0),
		SAFE_3_WAYPOINT + Vector3(-2, 0, 0),
		SAFE_3_WAYPOINT,
		SAFE_3_WAYPOINT + Vector3(2, 0, 0),
	]
	for bpos in beacon_positions:
		var beacon := MeshInstance3D.new()
		var bsp := SphereMesh.new()
		bsp.radius = 0.16
		bsp.height = 0.28
		beacon.mesh = bsp
		beacon.material_override = beacon_mat
		beacon.position = bpos + Vector3(0, 0.15, 0)
		env_node.add_child(beacon)

	# A repeated overhead datum makes the 210 m run measurable at a glance and
	# supplies WebGL-safe local fill. The fixtures are rendering-only and stay
	# above every route, so decoration never changes navigation or interaction.
	var work_light_mat := StandardMaterial3D.new()
	work_light_mat.albedo_color = Color(0.55, 0.31, 0.16)
	work_light_mat.emission_enabled = true
	work_light_mat.emission = Color(0.95, 0.55, 0.25)
	work_light_mat.emission_energy_multiplier = 1.6
	work_light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var work_light_index := 0
	var work_x := 10.0
	while work_x < SHELTER_POS.x - 4.0:
		var fixture := MeshInstance3D.new()
		fixture.name = "RouteWorkFixture%d" % work_light_index
		var fixture_mesh := BoxMesh.new()
		fixture_mesh.size = Vector3(1.7, 0.10, 0.34)
		fixture.mesh = fixture_mesh
		fixture.material_override = work_light_mat
		fixture.position = Vector3(work_x, 2.72, 0.0)
		env_node.add_child(fixture)

		var work_light := OmniLight3D.new()
		work_light.name = "RouteWorkLight%d" % work_light_index
		work_light.position = Vector3(work_x, 2.45, 0.0)
		work_light.light_color = Color(0.94, 0.58, 0.31)
		work_light.light_energy = 1.15
		work_light.omni_range = 12.5
		work_light.shadow_enabled = false
		work_light.distance_fade_enabled = true
		work_light.distance_fade_begin = 20.0
		work_light.distance_fade_length = 10.0
		env_node.add_child(work_light)
		work_light_index += 1
		work_x += 18.0

	# The side lanes sit outside the centerline fixtures' useful WebGL range.
	# Give each decision station and optional branch its own readable beacon.
	var lane_light_index := 0
	var lane_light_positions: Array[Vector3] = [CACHE_POS, LOOKOUT_POS]
	for sector in IRON_SECTORS:
		lane_light_positions.append(sector["safe_station"] as Vector3)
	for lane_pos in lane_light_positions:
		var lane_light := OmniLight3D.new()
		lane_light.name = "RouteLaneLight%d" % lane_light_index
		lane_light.position = lane_pos + Vector3(0, 2.1, 0)
		lane_light.light_color = Color(0.34, 0.76, 0.49)
		lane_light.light_energy = 1.05
		lane_light.omni_range = 7.5
		lane_light.shadow_enabled = false
		env_node.add_child(lane_light)
		lane_light_index += 1

	# Warning signage along the corridor
	var signs := [
		{"pos": Vector3(20, 1.8, -CORRIDOR_HALF_WIDTH + 0.2), "text": "I / BLEEDWAY"},
		{"pos": Vector3(76, 1.8, -CORRIDOR_HALF_WIDTH + 0.2), "text": "II / FERRIC SUMP"},
		{"pos": Vector3(134, 1.8, -CORRIDOR_HALF_WIDTH + 0.2), "text": "III / IRON LATTICE"},
		{"pos": Vector3(198, 1.8, -CORRIDOR_HALF_WIDTH + 0.2), "text": "SHELTER 1  >"},
	]
	for s in signs:
		var sign_bg := MeshInstance3D.new()
		var sgb := BoxMesh.new()
		sgb.size = Vector3(2.4, 0.5, 0.02)
		sign_bg.mesh = sgb
		var sgm := StandardMaterial3D.new()
		sgm.albedo_color = Color(0.12, 0.08, 0.03)
		sign_bg.material_override = sgm
		sign_bg.position = s.pos
		env_node.add_child(sign_bg)
		var lbl := Label3D.new()
		lbl.text = s.text
		lbl.font_size = 24
		lbl.pixel_size = 0.008
		lbl.modulate = Color(0.8, 0.4, 0.15, 0.8)
		lbl.position = s.pos + Vector3(0, 0, -0.02)
		env_node.add_child(lbl)

	# Degradation marks.
	var stain_mat := StandardMaterial3D.new()
	stain_mat.albedo_color = Color(0.06, 0.05, 0.04)
	for iron_x in [IRON_1_POS.x, IRON_2_POS.x, IRON_3_POS.x]:
		for j in range(3):
			var stain := MeshInstance3D.new()
			var stb := BoxMesh.new()
			stb.size = Vector3(1.5 + j * 0.5, 0.003, 1.0 + j * 0.3)
			stain.mesh = stb
			stain.material_override = stain_mat
			stain.position = Vector3(iron_x + j * 1.5 - 1.0, 0.005, 2.0 - j * 1.5)
			stain.rotation.y = j * 0.4
			env_node.add_child(stain)
