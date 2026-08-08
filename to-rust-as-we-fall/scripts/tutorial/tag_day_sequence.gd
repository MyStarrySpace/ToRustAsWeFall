@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

## Tag Day checkpoint, citizen failure, corridor walk, and Aster clearance.

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")

var _data_overlay: CanvasLayer
var _bystanders: Array = []
var _citizen  # Node3D + npc.gd at device to Aster's right.
var _naturalizer_1  # Node3D + npc.gd
var _naturalizer_2  # Node3D + npc.gd
var _citizen_light: OmniLight3D  # Light above citizen's device

# Tag Day is choreography, but it is still gameplay-observable world state: saves,
# targeting, replay, and the camera can all inspect the three bodies while the poem
# is running.  The scene therefore records which movement operations were accepted
# and joins the next beat only after BOTH the physical escort and its presentation
# have completed.  Dialogue and render tweens are presenters of this record, never
# the owner of progression.
const ESCORT_AUTHORITY_KEY := "tag_day:escort_authority"
const ESCORT_AUTHORITY_VERSION := 1
const ESCORT_AUTHORITY_CONTRACT := "tag_day_escort_v1"
const ESCORT_PHASE_IDLE := "idle"
const ESCORT_PHASE_FORMING := "forming"
const ESCORT_PHASE_CORRIDOR := "corridor"
const ESCORT_PHASE_JOINED := "joined"
const ESCORT_PHASE_BLOCKED := "blocked"
const ESCORT_PRESENTATION_SECONDS := 103.4
const ESCORT_PRESENTATION_TAG := "tag_day_escort_presentation"
const ESCORT_REPORT_TAG := "tag_day_escort_report"
const ESCORT_PAN_TAG := "tag_day_escort_pan_prompt"
const ESCORT_FAST_FORWARD_TAG := "tag_day_escort_fast_forward_prompt"
const ESCORT_ACTORS := ["citizen", "nk1", "nk2"]
const FORMATION_ACTORS := ["nk1", "nk2"]

# Callbacks living only in DialogueBox signal connections and the scheduler heap
# do not survive a load — TutorialSequence intentionally discards both — so a
# save during a whimper, lockdown, pass scan, or blue clearance could never
# continue. This compact record gives each phase an absolute deadline and an
# explicit presentation latch; reload reconstructs the signal and only consumes the
# saved remainder.
const CALLBACK_AUTHORITY_KEY := "tag_day:callback_authority"
const CALLBACK_AUTHORITY_VERSION := 1
const CALLBACK_AUTHORITY_CONTRACT := "tag_day_callbacks_v1"
const CALLBACK_PHASE_IDLE := "idle"
const CALLBACK_PHASE_FRAGMENTS := "fragments"
const CALLBACK_PHASE_NEUTRALIZATION := "neutralization"
const CALLBACK_PHASE_WHIMPER := "whimper"
const CALLBACK_PHASE_LOCKDOWN := "lockdown"
const CALLBACK_PHASE_RETURN_FOCUS := "return_focus"
const CALLBACK_PHASE_ASTER_SCAN := "aster_scan"
const CALLBACK_PHASE_CLEARANCE := "clearance"
const CALLBACK_PHASE_COMPLETE := "complete"
const CALLBACK_PHASE_TAG := "tag_day_callback_phase"
const FRAGMENTS_RECOVERY_SECONDS := 48.0
const NEUTRALIZATION_SECONDS := 2.5
const WHIMPER_RECOVERY_SECONDS := 18.0
const WHIMPER_POST_SECONDS := 1.0
const LOCKDOWN_RECOVERY_SECONDS := 42.0
const LOCKDOWN_POST_SECONDS := 1.5
const RETURN_FOCUS_SECONDS := 2.0
const ASTER_SCAN_RECOVERY_SECONDS := 18.0
const ASTER_SCAN_POST_SECONDS := 0.5
const CLEARANCE_SECONDS := 2.0

const ESCORT_DIALOGUE_KEYS := [
	"tag_day.poem.01",
	"tag_day.nk_chat.01",
	"tag_day.poem.02",
	"tag_day.nk_chat.02",
	"tag_day.poem.03",
	"tag_day.nk_chat.03",
	"tag_day.nk_chat.04",
	"tag_day.poem.04",
	"tag_day.nk_chat.05",
	"tag_day.nk_chat.06",
	"tag_day.poem.05",
	"tag_day.nk_chat.07",
	"tag_day.nk_chat.08",
	"tag_day.poem.06",
	"tag_day.nk_chat.09",
	"tag_day.nk_chat.10",
]

var _report_label_shown := false

# Psy-Knapse device positions.
const DEVICE_SPACING := 2.2
const ASTER_DEVICE_POS := Vector3(6, 0, 0)
const CITIZEN_DEVICE_POS := Vector3(6 + DEVICE_SPACING, 0, 0)  # To Aster's right

# Naturalizer standing positions (near the back wall, out of the way)
const NK_STAND_POS_1 := Vector3(13.2, 0, -5.5)
const NK_STAND_POS_2 := Vector3(14.8, 0, -5.5)
# Distinct grid-cell centres on either side of the citizen. Sub-cell offsets
# would quantize NK-02 onto the citizen's occupied cell — a physically impossible
# formation no arrival-gated escort could ever proceed from.
const NK_GRIP_POS_1 := Vector3(8.5, 0, -1.5)
const NK_GRIP_POS_2 := Vector3(8.5, 0, 1.5)
const GRIP_ARRIVAL_RADIUS := 0.2

# Corridor waypoints
const CORRIDOR_ENTRANCE := Vector3(14, 0, -8)
const CORRIDOR_A_END := Vector3(14, 0, -16)
const CORRIDOR_B_END := Vector3(24, 0, -17)
const CORRIDOR_C_END := Vector3(24, 0, -25)
const CORRIDOR_D_END := Vector3(19, 0, -27)
const DEAD_END := Vector3(17, 0, -28)

const BASE_NPC_SPEED := 2.0

# An OPEN walkable plane spanning the checkpoint room AND the twisted corridor down to the dead end
# (world X[-4,28], Z[-28,6]). No internal walls: the citizen's scripted command_walk_path waypoints carry
# the twist, so the grid just makes the cinematic's NPC movement cell-based + cooperative like the rest.
const GRID_ORIGIN := Vector3(-4.0, 0.0, -28.0)
const GRID_SIZE := Vector2i(32, 34)
var _grid: GridWorld

# --- Virtual overrides ---

func _build_scene() -> void:
	_build_grid()
	_build_environment()
	_build_corridor()
	_build_checkpoint_decorations()

func _build_grid() -> void:
	_grid = GridWorld.new()
	_grid.origin = GRID_ORIGIN
	_grid.create_room(GRID_SIZE.x, GRID_SIZE.y, false)

func _build_characters() -> void:
	var chars_node := Node3D.new()
	chars_node.name = "Characters"
	add_child(chars_node)

	# Aster at his Psy-Knapse device
	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = ASTER_DEVICE_POS + Vector3(0, 0.5, 0)
	if not Engine.is_editor_hint():
		_player.grid_world = _grid
	chars_node.add_child(_player)

	# Citizen (CZN-217) at the device to Aster's right
	_citizen = _create_npc("CZN-217", Color(0.5, 0.45, 0.4))
	_citizen.position = CITIZEN_DEVICE_POS
	chars_node.add_child(_citizen)

	# Other citizens at their own devices (further right)
	for i in range(3):
		var npc := _create_npc("CZN-%03d" % (400 + i), Color(0.4, 0.4, 0.45))
		npc.position = CITIZEN_DEVICE_POS + Vector3((i + 1) * DEVICE_SPACING, 0, 0)
		chars_node.add_child(npc)
		_bystanders.append(npc)

	# Naturalizers standing near the back wall
	_naturalizer_1 = _create_npc("NK-01", Color(0.85, 0.85, 0.88))
	_naturalizer_1.position = NK_STAND_POS_1
	chars_node.add_child(_naturalizer_1)

	_naturalizer_2 = _create_npc("NK-02", Color(0.85, 0.85, 0.88))
	_naturalizer_2.position = NK_STAND_POS_2
	chars_node.add_child(_naturalizer_2)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 10, 7))
		_bind_camera_to_level_bounds(_grid)
		# Dialogue is commonly advanced near the screen edge; enabling free-look on
		# that same frame must not launch the camera away from Aster. Tag Day teaches
		# WASD pan explicitly, so edge-scroll is deliberately disabled here.
		_camera.edge_scroll_margin = 0.0

func _register_characters() -> void:
	_game_state.grid = _grid
	_register_gs_character("aster", _player, 3.0)
	_register_gs_character("citizen", _citizen, BASE_NPC_SPEED)

	for i in range(_bystanders.size()):
		var id := "czn_%d" % (400 + i)
		_register_gs_character(id, _bystanders[i], BASE_NPC_SPEED)

	_register_gs_character("nk1", _naturalizer_1, BASE_NPC_SPEED)
	_register_gs_character("nk2", _naturalizer_2, BASE_NPC_SPEED)
	_publish_escort_authority(_baseline_escort_authority())
	_publish_callback_authority(_baseline_callback_authority())


func _baseline_escort_authority() -> Dictionary:
	return {
		"version": ESCORT_AUTHORITY_VERSION,
		"contract": ESCORT_AUTHORITY_CONTRACT,
		"phase": ESCORT_PHASE_IDLE,
		"actors": ESCORT_ACTORS.duplicate(),
		"required_arrival_ids": [],
		"accepted_movement_ops": {},
		"endpoints": {},
		"arrivals": {},
		"started_at": -1.0,
		"presentation_started_at": -1.0,
		"presentation_deadline": -1.0,
		"presentation_complete": false,
		"presentation_completed_at": -1.0,
		"physical_completed_at": -1.0,
		"joined_at": -1.0,
	}


func _baseline_callback_authority() -> Dictionary:
	return {
		"version": CALLBACK_AUTHORITY_VERSION,
		"contract": CALLBACK_AUTHORITY_CONTRACT,
		"phase": CALLBACK_PHASE_IDLE,
		"started_at": -1.0,
		"deadline": -1.0,
		"presentation_complete": false,
		"presentation_completed_at": -1.0,
	}


func _escort_authority_state() -> Dictionary:
	if _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(ESCORT_AUTHORITY_KEY, null)
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _callback_authority_state() -> Dictionary:
	if _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(CALLBACK_AUTHORITY_KEY, null)
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _publish_escort_authority(authority: Dictionary) -> void:
	if _game_state != null:
		_game_state.set_world_state(ESCORT_AUTHORITY_KEY, authority.duplicate(true))


func _publish_callback_authority(authority: Dictionary) -> void:
	if _game_state != null:
		_game_state.set_world_state(CALLBACK_AUTHORITY_KEY, authority.duplicate(true))


func _v3_data(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _v3_from_data(value: Variant) -> Vector3:
	if not (value is Array) or (value as Array).size() != 3:
		return Vector3.INF
	var encoded := value as Array
	return Vector3(float(encoded[0]), float(encoded[1]), float(encoded[2]))


func _v3_path(value: Variant) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not (value is Array):
		return result
	for point_v in value as Array:
		if point_v is Vector3:
			result.append(point_v as Vector3)
	return result


func _same_string_members(raw: Variant, expected: Array) -> bool:
	if not (raw is Array) or (raw as Array).size() != expected.size():
		return false
	for member_v in expected:
		if not (raw as Array).has(str(member_v)):
			return false
	return true


func _valid_movement_contract(authority: Dictionary, required: Array) -> bool:
	if not _same_string_members(authority.get("required_arrival_ids", []), required):
		return false
	var operations_v: Variant = authority.get("accepted_movement_ops", null)
	var endpoints_v: Variant = authority.get("endpoints", null)
	var arrivals_v: Variant = authority.get("arrivals", null)
	if not (operations_v is Dictionary) or not (endpoints_v is Dictionary) \
			or not (arrivals_v is Dictionary):
		return false
	var operations := operations_v as Dictionary
	var endpoints := endpoints_v as Dictionary
	var arrivals := arrivals_v as Dictionary
	for actor_v in required:
		var actor_id := str(actor_v)
		if not operations.has(actor_id) or not endpoints.has(actor_id) \
				or not arrivals.has(actor_id):
			return false
		var operation_v: Variant = operations[actor_id]
		if not (operation_v is Dictionary):
			return false
		var operation := operation_v as Dictionary
		if str(operation.get("actor_id", "")) != actor_id \
				or str(operation.get("kind", "")) not in ["move_to_pos", "walk_path"] \
				or not bool(operation.get("accepted", false)):
			return false
		var endpoint := _v3_from_data(endpoints[actor_id])
		var operation_endpoint := _v3_from_data(operation.get("endpoint", null))
		if not endpoint.is_finite() or not operation_endpoint.is_finite() \
				or not endpoint.is_equal_approx(operation_endpoint):
			return false
	return true


func _valid_escort_authority(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var authority := raw as Dictionary
	if int(authority.get("version", 0)) != ESCORT_AUTHORITY_VERSION \
			or str(authority.get("contract", "")) != ESCORT_AUTHORITY_CONTRACT \
			or not _same_string_members(authority.get("actors", []), ESCORT_ACTORS):
		return false
	var phase := str(authority.get("phase", ""))
	var started_at := float(authority.get("started_at", -1.0))
	match phase:
		ESCORT_PHASE_IDLE:
			return started_at < 0.0
		ESCORT_PHASE_FORMING:
			return is_finite(started_at) and started_at >= 0.0 \
				and _valid_movement_contract(authority, FORMATION_ACTORS)
		ESCORT_PHASE_CORRIDOR, ESCORT_PHASE_JOINED:
			var presentation_started := float(authority.get(
				"presentation_started_at", -1.0))
			var presentation_deadline := float(authority.get(
				"presentation_deadline", -1.0))
			if not is_finite(started_at) or not is_finite(presentation_started) \
					or not is_finite(presentation_deadline) or started_at < 0.0 \
					or presentation_started < started_at \
					or presentation_deadline <= presentation_started \
					or not _valid_movement_contract(authority, ESCORT_ACTORS):
				return false
			if phase == ESCORT_PHASE_JOINED:
				var arrivals := authority.get("arrivals", {}) as Dictionary
				for actor_v in ESCORT_ACTORS:
					if not bool(arrivals.get(str(actor_v), false)):
						return false
				return bool(authority.get("presentation_complete", false)) \
					and float(authority.get("physical_completed_at", -1.0)) >= started_at \
					and float(authority.get("joined_at", -1.0)) >= started_at
			return true
		ESCORT_PHASE_BLOCKED:
			# BLOCKED is fail-closed evidence of a rejected or replaced authored move.
			# It can be inspected, but may never satisfy the progression join.
			return is_finite(started_at) and started_at >= 0.0
		_:
			return false


func _valid_callback_authority(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var authority := raw as Dictionary
	if int(authority.get("version", 0)) != CALLBACK_AUTHORITY_VERSION \
			or str(authority.get("contract", "")) != CALLBACK_AUTHORITY_CONTRACT:
		return false
	var phase := str(authority.get("phase", ""))
	var started_at := float(authority.get("started_at", -1.0))
	var deadline := float(authority.get("deadline", -1.0))
	if phase in [CALLBACK_PHASE_IDLE, CALLBACK_PHASE_COMPLETE]:
		return deadline < 0.0 and (phase == CALLBACK_PHASE_IDLE or started_at >= 0.0)
	if phase not in [
		CALLBACK_PHASE_FRAGMENTS,
		CALLBACK_PHASE_NEUTRALIZATION,
		CALLBACK_PHASE_WHIMPER,
		CALLBACK_PHASE_LOCKDOWN,
		CALLBACK_PHASE_RETURN_FOCUS,
		CALLBACK_PHASE_ASTER_SCAN,
		CALLBACK_PHASE_CLEARANCE,
	]:
		return false
	return is_finite(started_at) and is_finite(deadline) \
		and started_at >= 0.0 and deadline >= started_at

func _setup_ui() -> void:
	# Aster's data-view perception (managed by base class)
	_setup_perception("data", _player)
	# Data perception cannot read past the dead-end alcove.
	_perception_material.set_shader_parameter("blackout_pos", DEAD_END + Vector3(0, 1.0, -1.0))
	_perception_material.set_shader_parameter("blackout_radius", 4.0)
	_perception_material.set_shader_parameter("blackout_blend", 2.5)

	_data_overlay = preload("res://scenes/ui/tag_day_data_overlay.tscn").instantiate() as CanvasLayer
	add_child(_data_overlay)

func _begin() -> void:
	# Tag Day is a scripted escort witnessed through optional camera control.
	# Dialogue rides the shared beat so fast-forward stays synchronized with motion.
	if _dialogue != null and _dialogue.has_method("set_cutscene_mode"):
		_dialogue.set_cutscene_mode(true)
	_start_arrive()


func _on_process(_delta: float, _spd: float) -> void:
	_sync_callback_visuals()

# --- Event-driven steps ---

func _start_arrive() -> void:
	_enter_step("arrive")
	_player.set_move_enabled(false)
	if not _game_state.character_arrived.is_connected(_on_character_arrived):
		_game_state.character_arrived.connect(_on_character_arrived)
	DialogueData.say_to(_dialogue, "tag_day.checkpoint_id")
	# Citizen tries small talk, Aster shuts them down, then scan fails
	_schedule_portable_method(2.0, _start_checkpoint_conversation, "citizen_talk")


func _start_checkpoint_conversation() -> void:
	_dialogue_chain(
		["tag_day.citizen.talk", "tag_day.aster.shush", "tag_day.citizen.scan",
		 "tag_day.murmur.01", "tag_day.murmur.02"],
		_finish_checkpoint_conversation
	)


func _finish_checkpoint_conversation() -> void:
	_schedule_portable_method(1.5, _start_citizen_scan, "citizen_scan")

func _on_character_arrived(id: String) -> void:
	var escort := _escort_authority_state()
	if not _valid_escort_authority(escort):
		return
	match str(escort.get("phase", "")):
		ESCORT_PHASE_FORMING:
			if id in FORMATION_ACTORS:
				_record_escort_arrival(id)
				_maybe_begin_corridor_walk()
		ESCORT_PHASE_CORRIDOR:
			if id in ESCORT_ACTORS:
				_record_escort_arrival(id)
				_try_finish_corridor_escort()

func _start_citizen_scan() -> void:
	_enter_step("citizen_scan")
	# The citizen's device scan fails
	_citizen_light.light_color = Color(0.8, 0.1, 0.05)
	_citizen_light.light_energy = 6.0
	DialogueData.say_to(_dialogue, "tag_day.scan_failed")
	_schedule_portable_method(3.0, _start_naturalizers_grip, "nk_grip")

func _start_naturalizers_grip() -> void:
	_enter_step("naturalizers_grip")
	if not _game_state.character_arrived.is_connected(_on_character_arrived):
		_game_state.character_arrived.connect(_on_character_arrived)
	# Naturalizers approach slowly.
	_game_state.change_move_speed("nk1", 1.5)
	_game_state.change_move_speed("nk2", 1.5)
	var now := float(_scheduler.get_current_tick())
	var authority := _baseline_escort_authority()
	authority["phase"] = ESCORT_PHASE_FORMING
	authority["started_at"] = now
	authority["required_arrival_ids"] = FORMATION_ACTORS.duplicate()
	authority["endpoints"] = {
		"nk1": _v3_data(NK_GRIP_POS_1),
		"nk2": _v3_data(NK_GRIP_POS_2),
	}
	authority["arrivals"] = {"nk1": false, "nk2": false}
	_publish_escort_authority(authority)
	var operations := {}
	operations["nk1"] = _commit_escort_move_to("nk1", NK_GRIP_POS_1, "formation:nk1")
	operations["nk2"] = _commit_escort_move_to("nk2", NK_GRIP_POS_2, "formation:nk2")
	authority["accepted_movement_ops"] = operations
	if not bool((operations["nk1"] as Dictionary).get("accepted", false)) \
			or not bool((operations["nk2"] as Dictionary).get("accepted", false)):
		authority["phase"] = ESCORT_PHASE_BLOCKED
	_publish_escort_authority(authority)
	# The corridor handoff is arrival-owned. A fixed delay can fire while NK-02 is
	# still en route, hiding the mismatch behind a render-node snap.
	_maybe_begin_corridor_walk()


func _maybe_begin_corridor_walk() -> void:
	if _game_state == null:
		return
	var authority := _escort_authority_state()
	if not _valid_escort_authority(authority) \
			or str(authority.get("phase", "")) != ESCORT_PHASE_FORMING:
		return
	for arrival in [
		{"id": "nk1", "target": NK_GRIP_POS_1},
		{"id": "nk2", "target": NK_GRIP_POS_2},
	]:
		var char_id := str(arrival["id"])
		var target := arrival["target"] as Vector3
		if not _game_state.characters.has(char_id) or _game_state.is_moving(char_id):
			return
		if _game_state.get_position(char_id).distance_to(target) > GRIP_ARRIVAL_RADIUS:
			return
	_begin_corridor_walk()


func _commit_escort_move_to(actor_id: String, endpoint: Vector3, op_id: String) -> Dictionary:
	var accepted := false
	if _game_state != null and _game_state.can_accept_move_command(actor_id):
		accepted = _game_state.command_move_to_pos(actor_id, endpoint)
		accepted = accepted and (
			(_game_state.is_moving(actor_id)
				and _game_state.get_destination(actor_id).distance_to(endpoint) <= GRIP_ARRIVAL_RADIUS)
			or (not _game_state.is_moving(actor_id)
				and _game_state.get_position(actor_id).distance_to(endpoint) <= GRIP_ARRIVAL_RADIUS)
		)
	return {
		"op_id": op_id,
		"actor_id": actor_id,
		"kind": "move_to_pos",
		"accepted": accepted,
		"committed_at": float(_scheduler.get_current_tick()) if _scheduler != null else -1.0,
		"endpoint": _v3_data(endpoint),
	}


func _commit_escort_walk_path(
	actor_id: String,
	path: Array[Vector3],
	op_id: String
) -> Dictionary:
	var accepted := false
	var endpoint := path[-1] if not path.is_empty() else Vector3.INF
	if _game_state != null and not path.is_empty() \
			and _game_state.can_accept_move_command(actor_id):
		_game_state.command_walk_path(actor_id, path)
		accepted = _game_state.is_moving(actor_id) \
			and _game_state.get_destination(actor_id).distance_to(endpoint) <= GRIP_ARRIVAL_RADIUS
	return {
		"op_id": op_id,
		"actor_id": actor_id,
		"kind": "walk_path",
		"accepted": accepted,
		"committed_at": float(_scheduler.get_current_tick()) if _scheduler != null else -1.0,
		"endpoint": _v3_data(endpoint),
		"waypoint_count": path.size(),
	}


func _record_escort_arrival(actor_id: String) -> void:
	var authority := _escort_authority_state()
	if not _valid_escort_authority(authority):
		return
	var required := authority.get("required_arrival_ids", []) as Array
	if not required.has(actor_id):
		return
	var endpoints := authority.get("endpoints", {}) as Dictionary
	if not endpoints.has(actor_id) or not _game_state.characters.has(actor_id) \
			or _game_state.is_moving(actor_id):
		return
	var endpoint := _v3_from_data(endpoints[actor_id])
	if not endpoint.is_finite() \
			or _game_state.get_position(actor_id).distance_to(endpoint) > GRIP_ARRIVAL_RADIUS:
		return
	var arrivals := (authority.get("arrivals", {}) as Dictionary).duplicate(true)
	if bool(arrivals.get(actor_id, false)):
		return
	arrivals[actor_id] = true
	authority["arrivals"] = arrivals
	_publish_escort_authority(authority)

func _show_report_label() -> void:
	if _report_label_shown or not is_instance_valid(_naturalizer_1):
		return
	_report_label_shown = true
	var lbl := Label3D.new()
	lbl.name = "ReportLabel"
	lbl.text = "REPORT FILED  |  CAUSE: MENTAL INSTABILITY"
	lbl.font_size = 48
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.8, 0.3, 0.2, 0.0)
	lbl.outline_modulate = Color(0, 0, 0, 0.5)
	lbl.outline_size = 4
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_naturalizer_1.add_child(lbl)
	lbl.position = Vector3(0, 2.0, 0)
	var tween := create_tween()
	tween.tween_property(lbl, "modulate:a", 0.9, 1.0)
	tween.tween_interval(8.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 2.0)


func _clear_report_label() -> void:
	_report_label_shown = false
	if not is_instance_valid(_naturalizer_1):
		return
	var existing: Node = _naturalizer_1.get_node_or_null("ReportLabel")
	if existing != null:
		existing.free()

func _begin_corridor_walk() -> void:
	var existing := _escort_authority_state()
	if _valid_escort_authority(existing) and str(existing.get("phase", "")) \
			in [ESCORT_PHASE_CORRIDOR, ESCORT_PHASE_JOINED]:
		return
	_enter_step("corridor_walk")
	# Slow walk leaves room for poem and fragments.
	_game_state.change_move_speed("citizen", 0.4)
	_game_state.change_move_speed("nk1", 0.4)
	_game_state.change_move_speed("nk2", 0.4)
	var paths := _corridor_escort_paths()
	var now := float(_scheduler.get_current_tick())
	var authority := _baseline_escort_authority()
	authority["phase"] = ESCORT_PHASE_CORRIDOR
	authority["started_at"] = now
	authority["required_arrival_ids"] = ESCORT_ACTORS.duplicate()
	authority["presentation_started_at"] = now
	authority["presentation_deadline"] = now + ESCORT_PRESENTATION_SECONDS
	authority["arrivals"] = {"citizen": false, "nk1": false, "nk2": false}
	var endpoints := {}
	for actor_v in ESCORT_ACTORS:
		var actor_id := str(actor_v)
		var actor_path := _v3_path(paths.get(actor_id, []))
		endpoints[actor_id] = _v3_data(actor_path[-1])
	authority["endpoints"] = endpoints
	_publish_escort_authority(authority)

	# Continue from the formation's actual arrival positions. Each accepted GameState
	# operation is recorded with the endpoint the physical-arrival latch will test.
	var operations := {}
	for actor_v in ESCORT_ACTORS:
		var actor_id := str(actor_v)
		operations[actor_id] = _commit_escort_walk_path(
			actor_id,
			_v3_path(paths[actor_id]),
			"corridor:%s" % actor_id
		)
	authority["accepted_movement_ops"] = operations
	for operation_v in operations.values():
		if not bool((operation_v as Dictionary).get("accepted", false)):
			authority["phase"] = ESCORT_PHASE_BLOCKED
			break
	_publish_escort_authority(authority)
	if str(authority.get("phase", "")) == ESCORT_PHASE_BLOCKED:
		push_error("Tag Day escort rejected an authored movement operation; progression is fail-closed.")
		return

	_arm_corridor_presentation_from_authority(true)
	_try_finish_corridor_escort()


func _corridor_escort_paths() -> Dictionary:

	# Explicit corners prevent wall-cutting.
	var corner_AB := Vector3(14, 0, -17)   # Turn from A (along Z) to B (along X)
	var corner_BC := Vector3(24, 0, -17)   # Turn from B (along X) to C (along Z)
	var corner_CD := Vector3(24, 0, -27)   # Turn from C (along Z) to D (along X)

	var citizen_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE,
		CORRIDOR_A_END, corner_AB,
		CORRIDOR_B_END, corner_BC,
		CORRIDOR_C_END, corner_CD,
		CORRIDOR_D_END, DEAD_END,
	]

	# NKs flank the citizen.
	var nk1_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE + Vector3(-0.6, 0, 0),         # A: moving along -Z, offset in -X
		CORRIDOR_A_END + Vector3(-0.6, 0, 0),
		corner_AB + Vector3(-0.6, 0, 0),
		CORRIDOR_B_END + Vector3(0, 0, -0.6),            # B: moving along +X, offset in -Z
		corner_BC + Vector3(0, 0, -0.6),
		CORRIDOR_C_END + Vector3(-0.6, 0, 0),            # C: moving along -Z, offset in -X
		corner_CD + Vector3(-0.6, 0, 0),
		CORRIDOR_D_END + Vector3(0, 0, -0.6),            # D: moving along -X, offset in -Z
		DEAD_END + Vector3(-0.6, 0, 0),
	]

	var nk2_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE + Vector3(0.6, 0, 0),          # A: offset in +X
		CORRIDOR_A_END + Vector3(0.6, 0, 0),
		corner_AB + Vector3(0.6, 0, 0),
		CORRIDOR_B_END + Vector3(0, 0, 0.6),             # B: offset in +Z
		corner_BC + Vector3(0, 0, 0.6),
		CORRIDOR_C_END + Vector3(0.6, 0, 0),             # C: offset in +X
		corner_CD + Vector3(0.6, 0, 0),
		CORRIDOR_D_END + Vector3(0, 0, 0.6),             # D: offset in +Z
		DEAD_END + Vector3(0.6, 0, 0),
	]
	return {"citizen": citizen_path, "nk1": nk1_path, "nk2": nk2_path}


func _arm_corridor_presentation_from_authority(start_dialogue: bool) -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(ESCORT_PRESENTATION_TAG)
	_scheduler.cancel_tag(ESCORT_REPORT_TAG)
	_scheduler.cancel_tag(ESCORT_PAN_TAG)
	_scheduler.cancel_tag(ESCORT_FAST_FORWARD_TAG)
	var authority := _escort_authority_state()
	if not _valid_escort_authority(authority) \
			or str(authority.get("phase", "")) != ESCORT_PHASE_CORRIDOR:
		return
	var now := float(_scheduler.get_current_tick())
	var started_at := float(authority.get("started_at", now))
	var deadline := float(authority.get("presentation_deadline", now))
	if not bool(authority.get("presentation_complete", false)):
		if start_dialogue:
			_start_corridor_presentation()
		if deadline <= now:
			_on_escort_presentation_deadline(deadline)
		else:
			_scheduler.schedule_at(
				deadline,
				_on_escort_presentation_deadline.bind(deadline),
				ESCORT_PRESENTATION_TAG
			)
	_arm_corridor_presenter_callbacks(started_at, now)


func _start_corridor_presentation() -> void:
	if _dialogue == null:
		return
	_dialogue.default_hold_time = 4.0
	# Constants are read-only in Godot 4.6. The shared dialogue presenter mutates its
	# working list during teardown, so give it an owned copy rather than aliasing the
	# authored constant into transient presenter state.
	_dialogue_chain(ESCORT_DIALOGUE_KEYS.duplicate(), _on_poem_finished)


func _arm_corridor_presenter_callbacks(started_at: float, now: float) -> void:
	var report_tick := started_at + 5.0
	if now >= report_tick:
		_show_report_label()
	else:
		_scheduler.schedule_at(report_tick, _show_report_label, ESCORT_REPORT_TAG)
	var pan_tick := started_at + 2.0
	var ff_tick := started_at + 22.0
	if now >= ff_tick:
		_start_pan_prompt()
		_show_fastforward_prompt()
	elif now >= pan_tick:
		_start_pan_prompt()
		_scheduler.schedule_at(ff_tick, _show_fastforward_prompt,
			ESCORT_FAST_FORWARD_TAG)
	else:
		_scheduler.schedule_at(pan_tick, _start_pan_prompt, ESCORT_PAN_TAG)
		_scheduler.schedule_at(ff_tick, _show_fastforward_prompt,
			ESCORT_FAST_FORWARD_TAG)


func _on_escort_presentation_deadline(expected_deadline: float) -> void:
	var authority := _escort_authority_state()
	if not _valid_escort_authority(authority) \
			or str(authority.get("phase", "")) != ESCORT_PHASE_CORRIDOR \
			or not is_equal_approx(float(authority.get(
				"presentation_deadline", -1.0)), expected_deadline):
		return
	_mark_escort_presentation_finished()


func _mark_escort_presentation_finished() -> void:
	var authority := _escort_authority_state()
	if not _valid_escort_authority(authority) \
			or str(authority.get("phase", "")) != ESCORT_PHASE_CORRIDOR \
			or bool(authority.get("presentation_complete", false)):
		return
	authority["presentation_complete"] = true
	authority["presentation_completed_at"] = float(_scheduler.get_current_tick())
	_publish_escort_authority(authority)
	_scheduler.cancel_tag(ESCORT_PRESENTATION_TAG)
	_try_finish_corridor_escort()


func _try_finish_corridor_escort() -> void:
	var authority := _escort_authority_state()
	if not _valid_escort_authority(authority) \
			or str(authority.get("phase", "")) != ESCORT_PHASE_CORRIDOR:
		return
	var endpoints := authority.get("endpoints", {}) as Dictionary
	var arrivals := (authority.get("arrivals", {}) as Dictionary).duplicate(true)
	var physical_complete := true
	var malformed_move := false
	for actor_v in ESCORT_ACTORS:
		var actor_id := str(actor_v)
		var endpoint := _v3_from_data(endpoints.get(actor_id, null))
		var at_endpoint := endpoint.is_finite() \
			and _game_state.characters.has(actor_id) \
			and not _game_state.is_moving(actor_id) \
			and _game_state.get_position(actor_id).distance_to(endpoint) <= GRIP_ARRIVAL_RADIUS
		if _game_state.is_moving(actor_id) \
				and _game_state.get_destination(actor_id).distance_to(endpoint) \
					> GRIP_ARRIVAL_RADIUS:
			malformed_move = true
		arrivals[actor_id] = at_endpoint
		physical_complete = physical_complete and at_endpoint
	authority["arrivals"] = arrivals
	if malformed_move:
		authority["phase"] = ESCORT_PHASE_BLOCKED
		_publish_escort_authority(authority)
		return
	if physical_complete and float(authority.get("physical_completed_at", -1.0)) < 0.0:
		authority["physical_completed_at"] = float(_scheduler.get_current_tick())
	_publish_escort_authority(authority)
	if not physical_complete or not bool(authority.get("presentation_complete", false)):
		return
	authority["phase"] = ESCORT_PHASE_JOINED
	authority["joined_at"] = float(_scheduler.get_current_tick())
	_publish_escort_authority(authority)
	_cancel_corridor_presenter_callbacks()
	_start_fragments()


func _escort_bodies_at_saved_endpoints(authority: Dictionary) -> bool:
	if _game_state == null:
		return false
	var endpoints := authority.get("endpoints", {}) as Dictionary
	for actor_v in ESCORT_ACTORS:
		var actor_id := str(actor_v)
		var endpoint := _v3_from_data(endpoints.get(actor_id, null))
		if not endpoint.is_finite() or not _game_state.characters.has(actor_id) \
				or _game_state.is_moving(actor_id) \
				or _game_state.get_position(actor_id).distance_to(endpoint) \
					> GRIP_ARRIVAL_RADIUS:
			return false
	return true


func _cancel_corridor_presenter_callbacks() -> void:
	if _scheduler == null:
		return
	for tag in [ESCORT_PRESENTATION_TAG, ESCORT_REPORT_TAG, ESCORT_PAN_TAG,
			ESCORT_FAST_FORWARD_TAG]:
		_scheduler.cancel_tag(tag)

func on_game_state_snapshot_restored() -> void:
	if _game_state == null or _scheduler == null:
		return
	if not _game_state.character_arrived.is_connected(_on_character_arrived):
		_game_state.character_arrived.connect(_on_character_arrived)
	_cancel_corridor_presenter_callbacks()
	_scheduler.cancel_tag(CALLBACK_PHASE_TAG)
	_clear_report_label()
	_clear_dialogue_presenter()

	var escort := _escort_authority_state()
	if not _valid_escort_authority(escort):
		escort = _migrate_legacy_escort_authority()
		_publish_escort_authority(escort)
	var callback := _callback_authority_state()
	if not _valid_callback_authority(callback):
		callback = _migrate_legacy_callback_authority()
		_publish_callback_authority(callback)

	if str(callback.get("phase", CALLBACK_PHASE_IDLE)) != CALLBACK_PHASE_IDLE:
		if str(escort.get("phase", "")) == ESCORT_PHASE_JOINED \
				and _escort_bodies_at_saved_endpoints(escort):
			_restore_callback_presenter(callback)
		else:
			escort["phase"] = ESCORT_PHASE_BLOCKED
			escort["started_at"] = maxf(0.0, float(_scheduler.get_current_tick()))
			_publish_escort_authority(escort)
			_publish_callback_authority(_baseline_callback_authority())
			_current_step = "corridor_walk"
			push_error("Loaded Tag Day callback future lacks its physical escort join.")
	else:
		_restore_escort_presenter(escort)
	_sync_callback_visuals()


func _clear_dialogue_presenter() -> void:
	if _dialogue == null:
		return
	for connection_v in _dialogue.dialogue_finished.get_connections():
		var connection := connection_v as Dictionary
		_dialogue.dialogue_finished.disconnect(connection.callable)
	_dialogue.clear()
	# Rebind instead of mutating: the chain keys may reference a read-only
	# constant array, which in-place mutation would reject.
	_dlg_chain_keys = []
	_dlg_chain_index = 0
	_dlg_chain_next = Callable()
	_dlg_chain_delay = 0.0


func _movement_matches_endpoint(actor_id: String, endpoint: Vector3) -> bool:
	if _game_state == null or not _game_state.characters.has(actor_id):
		return false
	if _game_state.is_moving(actor_id):
		return _game_state.get_destination(actor_id).distance_to(endpoint) \
			<= GRIP_ARRIVAL_RADIUS
	return _game_state.get_position(actor_id).distance_to(endpoint) <= GRIP_ARRIVAL_RADIUS


func _migration_operation(
	actor_id: String,
	kind: String,
	endpoint: Vector3,
	op_id: String
) -> Dictionary:
	return {
		"op_id": op_id,
		"actor_id": actor_id,
		"kind": kind,
		"accepted": _movement_matches_endpoint(actor_id, endpoint),
		"committed_at": float(_scheduler.get_current_tick()),
		"endpoint": _v3_data(endpoint),
	}


func _migrate_legacy_escort_authority() -> Dictionary:
	var now := float(_scheduler.get_current_tick())
	var authority := _baseline_escort_authority()
	if _current_step == "naturalizers_grip":
		authority["phase"] = ESCORT_PHASE_FORMING
		authority["started_at"] = now
		authority["required_arrival_ids"] = FORMATION_ACTORS.duplicate()
		authority["endpoints"] = {
			"nk1": _v3_data(NK_GRIP_POS_1),
			"nk2": _v3_data(NK_GRIP_POS_2),
		}
		authority["accepted_movement_ops"] = {
			"nk1": _migration_operation("nk1", "move_to_pos", NK_GRIP_POS_1,
				"legacy:formation:nk1"),
			"nk2": _migration_operation("nk2", "move_to_pos", NK_GRIP_POS_2,
				"legacy:formation:nk2"),
		}
		authority["arrivals"] = {
			"nk1": not _game_state.is_moving("nk1") \
				and _game_state.get_position("nk1").distance_to(NK_GRIP_POS_1) \
					<= GRIP_ARRIVAL_RADIUS,
			"nk2": not _game_state.is_moving("nk2") \
				and _game_state.get_position("nk2").distance_to(NK_GRIP_POS_2) \
					<= GRIP_ARRIVAL_RADIUS,
		}
		return authority

	var callback_steps := [
		"fragments", "neutralization", "lockdown", "return_focus",
		"aster_scans", "clearance", "complete",
	]
	if _current_step != "corridor_walk" and not callback_steps.has(_current_step):
		return authority
	var paths := _corridor_escort_paths()
	var endpoints := {}
	var operations := {}
	var arrivals := {}
	for actor_v in ESCORT_ACTORS:
		var actor_id := str(actor_v)
		var actor_path := _v3_path(paths[actor_id])
		var endpoint := actor_path[-1]
		endpoints[actor_id] = _v3_data(endpoint)
		operations[actor_id] = _migration_operation(
			actor_id, "walk_path", endpoint, "legacy:corridor:%s" % actor_id)
		arrivals[actor_id] = not _game_state.is_moving(actor_id) \
			and _game_state.get_position(actor_id).distance_to(endpoint) \
				<= GRIP_ARRIVAL_RADIUS
	authority["phase"] = (
		ESCORT_PHASE_CORRIDOR if _current_step == "corridor_walk" else ESCORT_PHASE_JOINED)
	authority["started_at"] = now
	authority["required_arrival_ids"] = ESCORT_ACTORS.duplicate()
	authority["accepted_movement_ops"] = operations
	authority["endpoints"] = endpoints
	authority["arrivals"] = arrivals
	authority["presentation_started_at"] = now
	authority["presentation_deadline"] = now + ESCORT_PRESENTATION_SECONDS
	if authority["phase"] == ESCORT_PHASE_JOINED:
		authority["presentation_complete"] = true
		authority["presentation_completed_at"] = now
		authority["physical_completed_at"] = now
		authority["joined_at"] = now
	return authority


func _migrate_legacy_callback_authority() -> Dictionary:
	var phase := CALLBACK_PHASE_IDLE
	var duration := 0.0
	var presentation_complete := false
	match _current_step:
		"fragments":
			phase = CALLBACK_PHASE_FRAGMENTS
			duration = FRAGMENTS_RECOVERY_SECONDS
		"neutralization":
			phase = CALLBACK_PHASE_NEUTRALIZATION
			duration = NEUTRALIZATION_SECONDS
			presentation_complete = true
		"lockdown":
			phase = CALLBACK_PHASE_LOCKDOWN
			duration = LOCKDOWN_RECOVERY_SECONDS
		"return_focus":
			phase = CALLBACK_PHASE_RETURN_FOCUS
			duration = RETURN_FOCUS_SECONDS
			presentation_complete = true
		"aster_scans":
			phase = CALLBACK_PHASE_ASTER_SCAN
			duration = ASTER_SCAN_RECOVERY_SECONDS
		"clearance":
			phase = CALLBACK_PHASE_CLEARANCE
			duration = CLEARANCE_SECONDS
			presentation_complete = true
		"complete":
			phase = CALLBACK_PHASE_COMPLETE
			presentation_complete = true
		_:
			return _baseline_callback_authority()
	var now := float(_scheduler.get_current_tick())
	var authority := _baseline_callback_authority()
	authority["phase"] = phase
	authority["started_at"] = now
	authority["deadline"] = -1.0 if phase == CALLBACK_PHASE_COMPLETE else now + duration
	authority["presentation_complete"] = presentation_complete
	authority["presentation_completed_at"] = now if presentation_complete else -1.0
	return authority


func _restore_escort_presenter(authority: Dictionary) -> void:
	var phase := str(authority.get("phase", ESCORT_PHASE_IDLE))
	match phase:
		ESCORT_PHASE_IDLE:
			_citizen_light.position = CITIZEN_DEVICE_POS + Vector3(0, 2, 0)
			if _current_step == "citizen_scan":
				_citizen_light.light_color = Color(0.8, 0.1, 0.05)
				_citizen_light.light_energy = 6.0
			else:
				_citizen_light.light_color = Color(0.3, 0.3, 0.35)
				_citizen_light.light_energy = 1.5
			return
		ESCORT_PHASE_FORMING:
			_current_step = "naturalizers_grip"
			_player.set_move_enabled(false)
			_citizen_light.position = CITIZEN_DEVICE_POS + Vector3(0, 2, 0)
			_citizen_light.light_color = Color(0.8, 0.1, 0.05)
			_citizen_light.light_energy = 6.0
			call_deferred("_maybe_begin_corridor_walk")
		ESCORT_PHASE_CORRIDOR:
			_current_step = "corridor_walk"
			_player.set_move_enabled(false)
			_citizen_light.position = CITIZEN_DEVICE_POS + Vector3(0, 2, 0)
			_citizen_light.light_color = Color(0.8, 0.1, 0.05)
			_citizen_light.light_energy = 6.0
			_arm_corridor_presentation_from_authority(
				not bool(authority.get("presentation_complete", false)))
			_try_finish_corridor_escort()
		ESCORT_PHASE_JOINED:
			# The join and callback record are normally published synchronously. This
			# handles an old/manual snapshot at that exact boundary without skipping it.
			if _escort_bodies_at_saved_endpoints(authority):
				_start_fragments()
			else:
				authority["phase"] = ESCORT_PHASE_BLOCKED
				_publish_escort_authority(authority)
				_current_step = "corridor_walk"
				push_error("Loaded Tag Day join disagrees with the three physical endpoints.")
		ESCORT_PHASE_BLOCKED:
			_current_step = "corridor_walk"
			push_error("Loaded Tag Day escort is blocked by a rejected movement contract.")


func _restore_callback_presenter(authority: Dictionary) -> void:
	_cancel_corridor_presenter_callbacks()
	var phase := str(authority.get("phase", CALLBACK_PHASE_IDLE))
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	if phase not in [CALLBACK_PHASE_ASTER_SCAN, CALLBACK_PHASE_CLEARANCE,
			CALLBACK_PHASE_COMPLETE]:
		_citizen_light.position = CITIZEN_DEVICE_POS + Vector3(0, 2, 0)
	else:
		_citizen_light.position = ASTER_DEVICE_POS + Vector3(0, 2, 0)
	match phase:
		CALLBACK_PHASE_FRAGMENTS:
			_current_step = "fragments"
			_camera.enable_free_look(40.0)
			_citizen_light.light_color = Color(0.8, 0.1, 0.05)
			_citizen_light.light_energy = 6.0
			_dialogue.default_hold_time = 2.5
			if not bool(authority.get("presentation_complete", false)):
				_dialogue_chain([
					"tag_day.fragment.01", "tag_day.fragment.02", "tag_day.fragment.03",
					"tag_day.fragment.04", "tag_day.fragment.07",
				], _on_bang, 1.5)
		CALLBACK_PHASE_NEUTRALIZATION:
			_current_step = "neutralization"
			_camera.enable_free_look(40.0)
			_citizen_light.light_color = Color(0.8, 0.1, 0.05)
			_citizen_light.light_energy = 6.0
		CALLBACK_PHASE_WHIMPER:
			_current_step = "neutralization"
			_camera.enable_free_look(40.0)
			_citizen_light.light_color = Color(0.8, 0.1, 0.05)
			_citizen_light.light_energy = 6.0
			if not bool(authority.get("presentation_complete", false)):
				DialogueData.say_to(_dialogue, "tag_day.fragment.08")
				_dialogue.dialogue_finished.connect(
					_on_whimper_presentation_finished, CONNECT_ONE_SHOT)
		CALLBACK_PHASE_LOCKDOWN:
			_current_step = "lockdown"
			_camera.enable_free_look(40.0)
			_citizen_light.light_color = Color(0.8, 0.1, 0.05)
			_citizen_light.light_energy = 4.0
			if not bool(authority.get("presentation_complete", false)):
				_dialogue_chain(
					["tag_day.lockdown", "tag_day.groan", "tag_day.report_blocked"],
					_on_lockdown_presentation_finished)
		CALLBACK_PHASE_RETURN_FOCUS:
			_current_step = "return_focus"
			_camera.disable_free_look()
			_citizen_light.light_color = Color(0.3, 0.3, 0.35)
			_citizen_light.light_energy = 1.5
		CALLBACK_PHASE_ASTER_SCAN:
			_current_step = "aster_scans"
			_citizen_light.light_color = Color(0.2, 0.5, 0.9)
			_citizen_light.light_energy = 4.0
			_citizen_light.position = ASTER_DEVICE_POS + Vector3(0, 2, 0)
			if not bool(authority.get("presentation_complete", false)):
				DialogueData.say_to(_dialogue, "tag_day.scan_passed")
				_dialogue.dialogue_finished.connect(
					_on_aster_scan_presentation_finished, CONNECT_ONE_SHOT)
		CALLBACK_PHASE_CLEARANCE:
			_current_step = "clearance"
			_citizen_light.light_color = Color(0.15, 0.4, 0.85)
			_citizen_light.light_energy = 6.0
		CALLBACK_PHASE_COMPLETE:
			_current_step = "complete"
			_citizen_light.light_color = Color(0.15, 0.4, 0.85)
			_citizen_light.light_energy = 6.0
	_arm_callback_phase_from_authority()


func _start_pan_prompt() -> void:
	_camera.enable_free_look(40.0)
	_tutorial_prompt.show_prompt(_camera_control_prompt_text())


func _camera_control_prompt_text() -> String:
	var pan_labels := [
		InputHints.label_for_action("camera_pan_forward", "W"),
		InputHints.label_for_action("camera_pan_left", "A"),
		InputHints.label_for_action("camera_pan_back", "S"),
		InputHints.label_for_action("camera_pan_right", "D"),
	]
	var rotate_left := InputHints.label_for_action("camera_rotate_left", "Q")
	var rotate_right := InputHints.label_for_action("camera_rotate_right", "E")
	return "%s — pan camera   •   %s / %s — rotate view" % [" / ".join(pan_labels), rotate_left, rotate_right]

func _show_fastforward_prompt() -> void:
	var fast_forward := InputHints.label_for_action("fast_forward", "X")
	_tutorial_prompt.show_prompt("%s — hold to fast-forward time" % fast_forward)

func _on_poem_finished() -> void:
	_mark_escort_presentation_finished()

func _start_fragments() -> void:
	var escort := _escort_authority_state()
	if not _valid_escort_authority(escort) \
			or str(escort.get("phase", "")) != ESCORT_PHASE_JOINED:
		return
	_enter_step("fragments")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_dialogue.default_hold_time = 2.5
	_begin_callback_phase(CALLBACK_PHASE_FRAGMENTS, FRAGMENTS_RECOVERY_SECONDS, false)
	# Stuttering prayer fragments with gaps, then "world ends" x3, then bang
	_dialogue_chain([
		"tag_day.fragment.01", "tag_day.fragment.02", "tag_day.fragment.03",
		"tag_day.fragment.04",
		"tag_day.fragment.07",
	], _on_bang, 1.5)

func _on_bang() -> void:
	var authority := _callback_authority_state()
	if not _valid_callback_authority(authority) \
			or str(authority.get("phase", "")) != CALLBACK_PHASE_FRAGMENTS:
		return
	_start_neutralization()


func _start_neutralization() -> void:
	_enter_step("neutralization")
	_begin_callback_phase(CALLBACK_PHASE_NEUTRALIZATION, NEUTRALIZATION_SECONDS, true)
	_camera.shake(0.5, 3.0)
	_dialogue.clear()
	_citizen.fade_out(2.0)
	_sync_callback_visuals()

func _fragment_whimper() -> void:
	# Keep the public sequence step at neutralization (the authored beat), while the
	# portable callback authority records the narrower whimper subphase.
	_begin_callback_phase(CALLBACK_PHASE_WHIMPER, WHIMPER_RECOVERY_SECONDS, false)
	DialogueData.say_to(_dialogue, "tag_day.fragment.08")
	_dialogue.dialogue_finished.connect(_on_whimper_presentation_finished, CONNECT_ONE_SHOT)


func _on_whimper_presentation_finished() -> void:
	_complete_callback_presentation(CALLBACK_PHASE_WHIMPER, WHIMPER_POST_SECONDS)

func _start_lockdown() -> void:
	_enter_step("lockdown")
	_begin_callback_phase(CALLBACK_PHASE_LOCKDOWN, LOCKDOWN_RECOVERY_SECONDS, false)
	_citizen_light.light_energy = 4.0
	_camera.shake(0.15, 8.0)
	_dialogue_chain(
		["tag_day.lockdown", "tag_day.groan", "tag_day.report_blocked"],
		_on_lockdown_presentation_finished
	)


func _on_lockdown_presentation_finished() -> void:
	_complete_callback_presentation(CALLBACK_PHASE_LOCKDOWN, LOCKDOWN_POST_SECONDS)

func _start_return_focus() -> void:
	_enter_step("return_focus")
	_begin_callback_phase(CALLBACK_PHASE_RETURN_FOCUS, RETURN_FOCUS_SECONDS, true)
	_camera.disable_free_look()
	# Citizen's light dims back down
	_citizen_light.light_color = Color(0.3, 0.3, 0.35)
	_citizen_light.light_energy = 1.5

func _start_aster_scans() -> void:
	_enter_step("aster_scans")
	_begin_callback_phase(CALLBACK_PHASE_ASTER_SCAN, ASTER_SCAN_RECOVERY_SECONDS, false)
	# Aster's scan light.
	_citizen_light.light_color = Color(0.2, 0.5, 0.9)
	_citizen_light.light_energy = 4.0
	_citizen_light.position = ASTER_DEVICE_POS + Vector3(0, 2, 0)
	DialogueData.say_to(_dialogue, "tag_day.scan_passed")
	_dialogue.dialogue_finished.connect(_on_aster_scan_presentation_finished, CONNECT_ONE_SHOT)


func _on_aster_scan_presentation_finished() -> void:
	_complete_callback_presentation(CALLBACK_PHASE_ASTER_SCAN, ASTER_SCAN_POST_SECONDS)

func _start_blue_transition() -> void:
	_enter_step("clearance")
	_begin_callback_phase(CALLBACK_PHASE_CLEARANCE, CLEARANCE_SECONDS, true)
	_citizen_light.light_color = Color(0.15, 0.4, 0.85)
	_citizen_light.light_energy = 6.0
	_dialogue.default_hold_time = 2.0
	# Blue fade into the elevator is sampled from the same saved phase/deadline as
	# the transition, so fresh loads and fast-forward show the same progress.
	_fade_rect.color = Color(0.1, 0.2, 0.5, 0.0)

func _on_sequence_complete() -> void:
	_enter_step("complete")
	var now := float(_scheduler.get_current_tick()) if _scheduler != null else 0.0
	var authority := _baseline_callback_authority()
	authority["phase"] = CALLBACK_PHASE_COMPLETE
	authority["started_at"] = now
	authority["presentation_complete"] = true
	authority["presentation_completed_at"] = now
	_publish_callback_authority(authority)
	_change_scene_or_record("res://scenes/tutorial/elevator.tscn")


func _begin_callback_phase(
	phase: String,
	duration: float,
	presentation_complete: bool
) -> void:
	if _scheduler == null:
		return
	var now := float(_scheduler.get_current_tick())
	var authority := _baseline_callback_authority()
	authority["phase"] = phase
	authority["started_at"] = now
	authority["deadline"] = now + maxf(0.0, duration)
	authority["presentation_complete"] = presentation_complete
	authority["presentation_completed_at"] = now if presentation_complete else -1.0
	_publish_callback_authority(authority)
	_arm_callback_phase_from_authority()


func _arm_callback_phase_from_authority() -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(CALLBACK_PHASE_TAG)
	var authority := _callback_authority_state()
	if not _valid_callback_authority(authority):
		return
	var phase := str(authority.get("phase", ""))
	if phase in [CALLBACK_PHASE_IDLE, CALLBACK_PHASE_COMPLETE]:
		return
	var deadline := float(authority.get("deadline", -1.0))
	var now := float(_scheduler.get_current_tick())
	if deadline <= now:
		_on_callback_phase_deadline(phase, deadline)
	else:
		_scheduler.schedule_at(
			deadline,
			_on_callback_phase_deadline.bind(phase, deadline),
			CALLBACK_PHASE_TAG
		)


func _on_callback_phase_deadline(expected_phase: String, expected_deadline: float) -> void:
	var authority := _callback_authority_state()
	if not _valid_callback_authority(authority) \
			or str(authority.get("phase", "")) != expected_phase \
			or not is_equal_approx(float(authority.get("deadline", -1.0)), expected_deadline):
		return
	if not bool(authority.get("presentation_complete", false)):
		_complete_callback_presentation(
			expected_phase,
			_callback_post_presentation_seconds(expected_phase)
		)
		return
	_advance_callback_phase(expected_phase)


func _complete_callback_presentation(expected_phase: String, post_seconds: float) -> void:
	var authority := _callback_authority_state()
	if not _valid_callback_authority(authority) \
			or str(authority.get("phase", "")) != expected_phase \
			or bool(authority.get("presentation_complete", false)):
		return
	var now := float(_scheduler.get_current_tick())
	authority["presentation_complete"] = true
	authority["presentation_completed_at"] = now
	authority["deadline"] = now + maxf(0.0, post_seconds)
	_publish_callback_authority(authority)
	if post_seconds <= 0.000001:
		_advance_callback_phase(expected_phase)
	else:
		_arm_callback_phase_from_authority()


func _callback_post_presentation_seconds(phase: String) -> float:
	match phase:
		CALLBACK_PHASE_WHIMPER:
			return WHIMPER_POST_SECONDS
		CALLBACK_PHASE_LOCKDOWN:
			return LOCKDOWN_POST_SECONDS
		CALLBACK_PHASE_ASTER_SCAN:
			return ASTER_SCAN_POST_SECONDS
		_:
			return 0.0


func _advance_callback_phase(phase: String) -> void:
	match phase:
		CALLBACK_PHASE_FRAGMENTS:
			_start_neutralization()
		CALLBACK_PHASE_NEUTRALIZATION:
			_fragment_whimper()
		CALLBACK_PHASE_WHIMPER:
			_start_lockdown()
		CALLBACK_PHASE_LOCKDOWN:
			_start_return_focus()
		CALLBACK_PHASE_RETURN_FOCUS:
			_start_aster_scans()
		CALLBACK_PHASE_ASTER_SCAN:
			_start_blue_transition()
		CALLBACK_PHASE_CLEARANCE:
			_on_sequence_complete()


func _sync_callback_visuals() -> void:
	if _scheduler == null or not is_instance_valid(_citizen) or _fade_rect == null:
		return
	var authority := _callback_authority_state()
	if not _valid_callback_authority(authority):
		return
	var phase := str(authority.get("phase", CALLBACK_PHASE_IDLE))
	var now := float(_scheduler.get_current_tick())
	var citizen_alpha := 1.0
	# Same-presenter rollback must retire an already-running NPC-local fade. From
	# here onward the saved phase clock is the sole presentation source.
	_citizen.set("_fade_active", false)
	if phase == CALLBACK_PHASE_NEUTRALIZATION:
		var elapsed := maxf(0.0, now - float(authority.get("started_at", now)))
		citizen_alpha = 1.0 - clampf(elapsed / 2.0, 0.0, 1.0)
	elif phase in [
		CALLBACK_PHASE_WHIMPER,
		CALLBACK_PHASE_LOCKDOWN,
		CALLBACK_PHASE_RETURN_FOCUS,
		CALLBACK_PHASE_ASTER_SCAN,
		CALLBACK_PHASE_CLEARANCE,
		CALLBACK_PHASE_COMPLETE,
	]:
		citizen_alpha = 0.0
	if _citizen.has_method("_apply_fade_alpha"):
		_citizen.call("_apply_fade_alpha", citizen_alpha)

	if phase in [CALLBACK_PHASE_CLEARANCE, CALLBACK_PHASE_COMPLETE]:
		var fade_alpha := 1.0
		if phase == CALLBACK_PHASE_CLEARANCE:
			var started_at := float(authority.get("started_at", now))
			var deadline := float(authority.get("deadline", started_at + CLEARANCE_SECONDS))
			fade_alpha = clampf((now - started_at) \
				/ maxf(0.000001, deadline - started_at), 0.0, 1.0)
		_fade_rect.color = Color(0.1, 0.2, 0.5, fade_alpha)
	else:
		_fade_rect.color.a = 0.0


func headless_get_state() -> Dictionary:
	var state := super.headless_get_state()
	state["escort_authority"] = _escort_authority_state()
	state["callback_authority"] = _callback_authority_state()
	return state


# --- Checkpoint presentation ---
func _build_checkpoint_decorations() -> void:
	var environment := find_child("Environment", false, false) as Node3D
	if environment == null:
		return
	# The shared building-quality grammar assumes a straight, centered corridor.
	# Two offset spans dress the clinical checkpoint walls without drawing facade
	# panels across the Wellness doorway at x=14, z=-8.
	for span in [
		{"name": "CheckpointWestDatum", "x0": -4.0, "x1": 12.4, "signs": ["CHECKPOINT 7-B"]},
		{"name": "CheckpointEastDatum", "x0": 15.6, "x1": 28.0, "signs": ["PSY-KNAPSE ARRAY"]},
	]:
		var anchor := Node3D.new()
		anchor.name = str(span["name"])
		anchor.position.z = -1.0  # room walls are centered between z=-8 and z=6
		environment.add_child(anchor)
		LevelDecoratorScript.decorate_profile(anchor, "tag_checkpoint", {
			"x0": float(span["x0"]),
			"x1": float(span["x1"]),
			"signs": span["signs"],
		})

	# A continuous surface datum makes the four turns legible without adding
	# collision or changing the authored GridWorld route.
	_add_checkpoint_route_datum(environment, Vector3(14, 0.022, -12), Vector3(0.10, 0.018, 7.2), 0)
	_add_checkpoint_route_datum(environment, Vector3(20, 0.022, -17), Vector3(9.2, 0.018, 0.10), 1)
	_add_checkpoint_route_datum(environment, Vector3(24, 0.022, -22), Vector3(0.10, 0.018, 7.2), 2)
	_add_checkpoint_route_datum(environment, Vector3(20.5, 0.022, -27), Vector3(6.2, 0.018, 0.10), 3)

func _add_checkpoint_route_datum(parent: Node3D, pos: Vector3, size: Vector3, index: int) -> void:
	var datum := MeshInstance3D.new()
	datum.name = "WellnessRouteDatum%d" % index
	var mesh := BoxMesh.new()
	mesh.size = size
	datum.mesh = mesh
	var material := StandardMaterial3D.new()
	var color := Color(0.26, 0.58, 0.82).lerp(Color(0.72, 0.24, 0.12), float(index) / 4.0)
	material.albedo_color = color.darkened(0.38)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.75
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	datum.material_override = material
	datum.position = pos
	parent.add_child(datum)


# --- Environment Build ---

func _build_environment() -> void:
	var env_node := Node3D.new()
	env_node.name = "Environment"
	add_child(env_node)

	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(32, 0.1, 16)
	floor_mesh.mesh = floor_box
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.14, 0.16, 0.20)
	floor_mat.metallic = 0.28
	floor_mat.roughness = 0.74
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(12, -0.05, -2)
	env_node.add_child(floor_mesh)

	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(12, -0.01, -2)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(32, 0.02, 16)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	env_node.add_child(floor_body)

	# Main-room walls with doorway.
	_add_wall(env_node, Vector3(4.5, 1.5, -8), Vector3(17, 3, 0.3))
	_add_wall(env_node, Vector3(21.5, 1.5, -8), Vector3(13, 3, 0.3))
	_add_wall(env_node, Vector3(12, 1.5, 6), Vector3(32, 3, 0.3))
	_add_wall(env_node, Vector3(-4, 1.5, -2), Vector3(0.3, 3, 14))
	_add_wall(env_node, Vector3(28, 1.5, -2), Vector3(0.3, 3, 14))

	# Psy-Knapse device row.
	for i in range(5):
		var dev_pos := ASTER_DEVICE_POS + Vector3(i * DEVICE_SPACING, 0, 0)
		_add_booth(env_node, dev_pos, "PSY-%d" % (i + 1))

	# Lane dividers between devices.
	for i in range(6):
		var marker := MeshInstance3D.new()
		var line := BoxMesh.new()
		line.size = Vector3(0.05, 0.02, 1.2)
		marker.mesh = line
		var line_mat := StandardMaterial3D.new()
		line_mat.albedo_color = Color(0.15, 0.15, 0.2)
		marker.material_override = line_mat
		marker.position = ASTER_DEVICE_POS + Vector3(i * DEVICE_SPACING + DEVICE_SPACING * 0.5, 0.01, 0)
		env_node.add_child(marker)

	for i in range(4):
		var ceiling_light := MeshInstance3D.new()
		var cl_box := BoxMesh.new()
		cl_box.size = Vector3(4, 0.05, 1.5)
		ceiling_light.mesh = cl_box
		var cl_mat := StandardMaterial3D.new()
		cl_mat.albedo_color = Color(0.6, 0.6, 0.65)
		cl_mat.emission_enabled = true
		cl_mat.emission = Color(0.5, 0.5, 0.55)
		cl_mat.emission_energy_multiplier = 0.5
		ceiling_light.material_override = cl_mat
		ceiling_light.position = Vector3(3 + i * 7, 2.95, -1)
		env_node.add_child(ceiling_light)
		var work_light := OmniLight3D.new()
		work_light.name = "CheckpointWorkLight%d" % i
		work_light.position = Vector3(3 + i * 7, 2.52, -1)
		work_light.light_color = Color(0.62, 0.72, 0.9)
		work_light.light_energy = 1.25
		work_light.omni_range = 7.2
		work_light.shadow_enabled = false
		env_node.add_child(work_light)

	# Clinical fluorescent directional light
	var dir_light := DirectionalLight3D.new()
	dir_light.transform = Transform3D(
		Basis(Vector3(1, 0, 0), -PI / 3.0),
		Vector3(0, 8, 0)
	)
	dir_light.light_color = Color(0.75, 0.75, 0.8)
	dir_light.light_energy = 0.86
	dir_light.shadow_enabled = true
	env_node.add_child(dir_light)

	# Ambient fill
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.56)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.1
	world_env.environment = env
	env_node.add_child(world_env)

	# Verification sign
	var overhead := MeshInstance3D.new()
	var oh_box := BoxMesh.new()
	oh_box.size = Vector3(3, 0.1, 0.6)
	overhead.mesh = oh_box
	var oh_mat := StandardMaterial3D.new()
	oh_mat.albedo_color = Color(0.15, 0.15, 0.2)
	oh_mat.emission_enabled = true
	oh_mat.emission = Color(0.1, 0.12, 0.2)
	oh_mat.emission_energy_multiplier = 0.3
	overhead.material_override = oh_mat
	var sign_x := ASTER_DEVICE_POS.x + 2.0 * DEVICE_SPACING
	overhead.position = Vector3(sign_x, 2.6, 0)
	env_node.add_child(overhead)
	var sign_lbl := Label3D.new()
	sign_lbl.text = "TAG DAY  //  VERIFICATION  7-B"
	sign_lbl.font_size = 32
	sign_lbl.pixel_size = 0.008
	sign_lbl.modulate = Color(0.3, 0.4, 0.6, 0.7)
	sign_lbl.position = Vector3(sign_x, 2.6, -0.04)
	env_node.add_child(sign_lbl)

	# Light above citizen's device (used for scan result + lockdown)
	_citizen_light = OmniLight3D.new()
	_citizen_light.position = CITIZEN_DEVICE_POS + Vector3(0, 2, 0)
	_citizen_light.light_color = Color(0.3, 0.3, 0.35)
	_citizen_light.light_energy = 1.5
	_citizen_light.omni_range = 4.0
	env_node.add_child(_citizen_light)

# --- Corridor Build ---

func _build_corridor() -> void:
	var env_node: Node = find_child("Environment", false, false)
	if not env_node:
		return

	var floor_color := Color(0.105, 0.115, 0.145)

	# Segment A: straight away from doorway (x=13-15, z=-8 to z=-16)
	_add_corridor_floor(env_node, Vector3(14, -0.05, -12), Vector3(2, 0.1, 8), floor_color)
	_add_corridor_collision(env_node, Vector3(14, -0.01, -12), Vector3(2, 0.02, 8))
	_add_wall(env_node, Vector3(12.85, 1.5, -12), Vector3(0.3, 3, 8))
	_add_wall(env_node, Vector3(15.15, 1.5, -12), Vector3(0.3, 3, 8))

	# Segment B: turn right (x=15-25, z=-16 to z=-18)
	_add_corridor_floor(env_node, Vector3(20, -0.05, -17), Vector3(10, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(20, -0.01, -17), Vector3(10, 0.02, 2))
	_add_wall(env_node, Vector3(20, 1.5, -15.85), Vector3(10, 3, 0.3))
	_add_wall(env_node, Vector3(20, 1.5, -18.15), Vector3(10, 3, 0.3))

	# Segment C: turn away again (x=23-25, z=-18 to z=-26)
	_add_corridor_floor(env_node, Vector3(24, -0.05, -22), Vector3(2, 0.1, 8), floor_color)
	_add_corridor_collision(env_node, Vector3(24, -0.01, -22), Vector3(2, 0.02, 8))
	_add_wall(env_node, Vector3(22.85, 1.5, -22), Vector3(0.3, 3, 8))
	_add_wall(env_node, Vector3(25.15, 1.5, -22), Vector3(0.3, 3, 8))

	# Segment D: turn left into dead-end (x=16-23, z=-26 to z=-28)
	_add_corridor_floor(env_node, Vector3(19.5, -0.05, -27), Vector3(7, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(19.5, -0.01, -27), Vector3(7, 0.02, 2))
	_add_wall(env_node, Vector3(19.5, 1.5, -25.85), Vector3(7, 3, 0.3))
	_add_wall(env_node, Vector3(19.5, 1.5, -28.15), Vector3(7, 3, 0.3))

	# Dead end alcove (x=16-18, z=-28 to z=-30)
	_add_corridor_floor(env_node, Vector3(17, -0.05, -29), Vector3(2, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(17, -0.01, -29), Vector3(2, 0.02, 2))
	_add_wall(env_node, Vector3(15.85, 1.5, -29), Vector3(0.3, 3, 2))
	_add_wall(env_node, Vector3(18.15, 1.5, -29), Vector3(0.3, 3, 2))
	_add_wall(env_node, Vector3(17, 1.5, -30.15), Vector3(2, 3, 0.3))

	# "Wellness Wing" sign above the corridor entrance
	var ww_sign := MeshInstance3D.new()
	var ww_box := BoxMesh.new()
	ww_box.size = Vector3(2.5, 0.1, 0.4)
	ww_sign.mesh = ww_box
	var ww_mat := StandardMaterial3D.new()
	ww_mat.albedo_color = Color(0.12, 0.12, 0.18)
	ww_mat.emission_enabled = true
	ww_mat.emission = Color(0.08, 0.1, 0.18)
	ww_mat.emission_energy_multiplier = 0.3
	ww_sign.material_override = ww_mat
	ww_sign.position = Vector3(CORRIDOR_ENTRANCE.x, 2.6, CORRIDOR_ENTRANCE.z + 0.2)
	env_node.add_child(ww_sign)
	var ww_lbl := Label3D.new()
	ww_lbl.text = "WELLNESS WING"
	ww_lbl.font_size = 36
	ww_lbl.pixel_size = 0.008
	ww_lbl.modulate = Color(0.3, 0.4, 0.6, 0.7)
	ww_lbl.position = Vector3(CORRIDOR_ENTRANCE.x, 2.6, CORRIDOR_ENTRANCE.z + 0.17)
	env_node.add_child(ww_lbl)

	_add_corridor_ceiling(env_node, Vector3(14, 2.95, -12), Vector3(1.5, 0.05, 3), 0.3)
	_add_corridor_ceiling(env_node, Vector3(20, 2.95, -17), Vector3(4, 0.05, 1.5), 0.2)
	_add_corridor_ceiling(env_node, Vector3(24, 2.95, -22), Vector3(1.5, 0.05, 3), 0.15)
	_add_corridor_ceiling(env_node, Vector3(17, 2.95, -28), Vector3(1.5, 0.05, 1.5), 0.1)

	# Corridor lights grow dimmer and redder.
	_add_corridor_light(env_node, Vector3(14, 2.5, -12), 1.25, Color(0.46, 0.38, 0.31))
	_add_corridor_light(env_node, Vector3(20, 2.5, -17), 1.05, Color(0.43, 0.30, 0.22))
	_add_corridor_light(env_node, Vector3(24, 2.5, -22), 0.86, Color(0.40, 0.24, 0.17))
	_add_corridor_light(env_node, Vector3(17, 2.5, -29), 0.72, Color(0.36, 0.18, 0.13))

func _add_corridor_floor(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	mesh_inst.position = pos
	parent.add_child(mesh_inst)

func _add_corridor_collision(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)

func _add_corridor_ceiling(parent: Node3D, pos: Vector3, size: Vector3, emission_energy: float) -> void:
	var ceiling := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = size
	ceiling.mesh = cb
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.5, 0.5, 0.55)
	cm.emission_enabled = true
	cm.emission = Color(0.4, 0.4, 0.45)
	cm.emission_energy_multiplier = emission_energy
	ceiling.material_override = cm
	ceiling.position = pos
	parent.add_child(ceiling)

func _add_corridor_light(parent: Node3D, pos: Vector3, energy: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 5.0
	parent.add_child(light)

func _add_booth(parent: Node3D, pos: Vector3, label_text: String) -> void:
	for z_off in [-0.6, 0.6]:
		var pillar := MeshInstance3D.new()
		var pbox := BoxMesh.new()
		pbox.size = Vector3(0.15, 2.5, 0.15)
		pillar.mesh = pbox
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.18, 0.18, 0.22)
		pillar.material_override = pmat
		pillar.position = pos + Vector3(0, 1.25, z_off)
		parent.add_child(pillar)

	var bar := MeshInstance3D.new()
	var barmesh := BoxMesh.new()
	barmesh.size = Vector3(0.15, 0.15, 1.35)
	bar.mesh = barmesh
	var barmat := StandardMaterial3D.new()
	barmat.albedo_color = Color(0.18, 0.18, 0.22)
	bar.material_override = barmat
	bar.position = pos + Vector3(0, 2.5, 0)
	parent.add_child(bar)

	var lbl := Label3D.new()
	lbl.text = label_text
	lbl.font_size = 36
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.3, 0.4, 0.6, 0.7)
	lbl.position = pos + Vector3(0, 2.2, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)
