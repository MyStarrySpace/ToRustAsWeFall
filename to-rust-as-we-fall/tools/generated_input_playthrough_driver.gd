extends Node

## Deterministic player-input pilot used to record maintained generated-stretch cases.
##
## The policy explores the same visible interactables a player can see. Every selection,
## camera move, Rally, interaction, and item use is delivered as shipped keyboard/pointer
## input. Read-only authority is inspected only after an input to verify its outcome; it
## never chooses an action from solver output and never edits gameplay state.

const AgentPlayerInputDriverScript := preload(
	"res://tools/agent_player_input_driver.gd"
)
const StretchSeedCatalogScript := preload(
	"res://scripts/generation/stretch_seed_catalog.gd"
)

const PARTY_IDS := ["aster", "peris", "endo"]
const AUTHORED_HYDRAULIC_CASE_ID := "teaching_channels_spiral"
const TARGET_COMPLETION_TIMEOUT_SECONDS := 42.0
const PLAYTHROUGH_TIMEOUT_SECONDS := 300.0
const MAX_PLAYER_DECISIONS := 96
const PARTY_NEAR_TARGET_RADIUS := 3.2
const SAFE_SCREEN_MARGIN := Vector4(0.12, 0.13, 0.20, 0.31)

var case_id := ""
var _player_input_driver: Node
var _decision_receipts: Array[Dictionary] = []
var _rally_gesture_count := 0
var _accepted_rally_count := 0
var _rally_members: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func get_decision_receipts() -> Array[Dictionary]:
	return _decision_receipts.duplicate(true)


func get_player_input_receipts() -> Array[Dictionary]:
	if _player_input_driver != null and _player_input_driver.has_method("receipts"):
		return _player_input_driver.call("receipts")
	return []


func _run() -> void:
	if case_id.strip_edges() == "":
		_fail("missing generated seed case id")
		return

	await _wait_frames(3)
	var fragments_button := await _wait_for_button("Fragments", 8.0)
	if fragments_button == null:
		_fail("main-menu Fragments button was not found")
		return
	await _click_control(fragments_button)

	var preview := await _wait_for_preview_menu(14.0)
	if preview == null:
		_fail("fragment picker did not load")
		return
	if not await _choose_case_through_visible_menu(preview):
		return

	preview = await _wait_for_generated_preview(18.0)
	if preview == null:
		_fail("generated stretch did not load")
		return
	var chunk: Node = preview.get("_active_chunk")
	if chunk == null or not chunk.has_method("get_preview_state"):
		_fail("generated stretch chunk is unavailable")
		return

	_player_input_driver = AgentPlayerInputDriverScript.new()
	_player_input_driver.name = "GeneratedPilotPlayerInput"
	add_child(_player_input_driver)
	_player_input_driver.call("setup", preview)

	# Establishing shot, then the same help/overlay keys a player uses to clear the view.
	await _wait_seconds(1.0)
	await _send_key(KEY_H)
	await _send_key(KEY_F4)
	await _send_key(KEY_HOME)

	var preferred_active := _preferred_active_character()
	if preferred_active != "":
		var selection_receipt: Dictionary = await _player_input_driver.call(
			"select_single", preferred_active
		)
		_record_decision(
			preview,
			"focus_character",
			"Use the visible portrait for the character who reads this system.",
			{"character": preferred_active},
			selection_receipt
		)
		if not bool(selection_receipt.get("accepted", false)):
			_fail("could not select %s through the shipped portrait binding" % preferred_active)
			return
		if not _autonomous_focus_matches(preview, preferred_active):
			_fail("autonomous focus did not settle on %s" % preferred_active)
			return

	print("[PLAYTHROUGH/pilot] Exploring %s from visible world evidence" % case_id)
	if not await _play_visible_interaction_policy(preview, chunk):
		_fail("visible-input policy did not reach the exit")
		return

	var final_state: Dictionary = chunk.call("get_preview_state")
	if final_state.get(
		"completion_ready", final_state.get("shelter_rested", false)
	) != true:
		_fail("player-input policy ended without shelter completion")
		return
	if _accepted_rally_count <= 0:
		_fail("playthrough completed without a whole-party Rally gesture")
		return

	print(
		"[PLAYTHROUGH/pilot] COMPLETE %s decisions=%d rallies=%d/%d"
		% [
			case_id,
			_decision_receipts.size(),
			_accepted_rally_count,
			_rally_gesture_count,
		]
	)
	await _wait_seconds(2.0)
	_finish_recording()


func _choose_case_through_visible_menu(preview: Node) -> bool:
	if case_id == AUTHORED_HYDRAULIC_CASE_ID:
		var generated_button := _find_button(preview, "Generated Stretch")
		if generated_button == null:
			_fail("Generated Stretch button was not found")
			return false
		await _click_control(generated_button)
		return true

	var case_index := _seed_case_index(case_id)
	if case_index < 0:
		_fail("unknown generated seed case '%s'" % case_id)
		return false
	var selector := _find_visible_option_button(preview)
	if selector == null:
		_fail("maintained seed selector was not found")
		return false
	await _select_option_index(selector, case_index + 1)
	if selector.selected != case_index + 1:
		_fail("visible seed selector did not choose '%s'" % case_id)
		return false
	var play_button := _find_button(preview, "Play seed")
	if play_button == null:
		_fail("visible Play seed button was not found")
		return false
	await _click_control(play_button)
	return true


func _play_visible_interaction_policy(preview: Node, chunk: Node) -> bool:
	var deadline := Time.get_ticks_msec() + int(PLAYTHROUGH_TIMEOUT_SECONDS * 1000.0)
	var attempted := {}
	var consumed_visible_states := {}
	var last_success_token := ""
	var decision_count := 0
	var camera_sweep_index := 0

	while Time.get_ticks_msec() < deadline and decision_count < MAX_PLAYER_DECISIONS:
		if _completion_ready(chunk):
			return true

		var candidates := _ordered_visible_targets(
			preview, chunk, consumed_visible_states, last_success_token
		)
		var progressed := false
		for candidate_v in candidates:
			var candidate := candidate_v as Dictionary
			var target := candidate.get("target") as Node3D
			if target == null or not is_instance_valid(target):
				continue
			var visible_state := str(candidate.get("visible_state", ""))
			if not await _bring_target_into_player_view(preview, target):
				continue

			var actors := _actor_order(preview)
			for actor_v in actors:
				var actor := str(actor_v)
				var attempt_key := "%s|%s" % [visible_state, actor]
				if attempted.has(attempt_key):
					continue
				attempted[attempt_key] = true
				decision_count += 1

				var travel_event_start := _event_count(preview)
				if _party_needs_group_travel(preview, target):
					if not await _rally_whole_party(preview, target):
						continue
					if not await _wait_for_rally_settle(preview, TARGET_COMPLETION_TIMEOUT_SECONDS):
						_fail("whole-party Rally did not settle through normal navigation")
						return false
					await _send_key(KEY_HOME)
					var arrival_triggers := _events_of_kind(
						preview, travel_event_start, "trigger_interactable"
					)
					if not arrival_triggers.is_empty():
						var arrival_receipt := {
							"kind": "rally_arrival_interaction",
							"accepted": true,
							"player_reproducible": true,
							"world_trigger": (arrival_triggers[0] as Dictionary).duplicate(true),
						}
						_record_decision(
							preview,
							"observe_rally_arrival",
							"The whole-party arrival visibly committed a proximity action.",
							_observe_target(preview, target),
							arrival_receipt
						)
						if _trigger_matches_target(arrival_triggers[0], target):
							consumed_visible_states[visible_state] = true
							last_success_token = visible_state
						attempted.clear()
						await _consume_visible_lysate(preview)
						progressed = true
						break

				var event_start := _event_count(preview)
				var click_target := _visible_click_target(target)
				var action_receipt: Dictionary = await _player_input_driver.call(
					"interact", actor, click_target
				)
				var trigger_receipt := {}
				if bool(action_receipt.get("accepted", false)):
					trigger_receipt = await _wait_for_interaction_trigger(
						preview,
						target,
						actor,
						event_start,
						TARGET_COMPLETION_TIMEOUT_SECONDS
					)
				action_receipt["world_trigger"] = trigger_receipt.duplicate(true)
				action_receipt["accepted"] = not trigger_receipt.is_empty()
				if trigger_receipt.is_empty() and str(action_receipt.get("reason", "")) == "":
					action_receipt["reason"] = _visible_refusal_text(preview)

				_record_decision(
					preview,
					"interact_visible_target",
					"Try the nearest currently usable world object and inspect its feedback.",
					_observe_target(preview, target),
					action_receipt
				)
				if trigger_receipt.is_empty():
					continue

				consumed_visible_states[visible_state] = true
				last_success_token = visible_state
				attempted.clear()
				await _consume_visible_lysate(preview)
				await _wait_seconds(1.25)
				progressed = true
				break
			if progressed:
				break

		if progressed:
			continue

		# Waiting and camera search are real player actions. If no new visible affordance
		# appears after a full view sweep, fail honestly instead of consulting an answer.
		await _wait_seconds(1.0)
		if _completion_ready(chunk):
			return true
		await _camera_sweep_step(preview, camera_sweep_index)
		camera_sweep_index += 1
		if camera_sweep_index >= 8:
			var refreshed := _ordered_visible_targets(
				preview, chunk, consumed_visible_states, last_success_token
			)
			if refreshed.is_empty() or _all_targets_attempted(refreshed, attempted, preview):
				return false
			camera_sweep_index = 0

	return _completion_ready(chunk)


func _rally_whole_party(preview: Node, target: Node3D) -> bool:
	# One group-travel decision is exactly one held-RMB gesture. No selection churn,
	# no singleton loop, and no retry hidden inside this helper.
	_rally_gesture_count += 1
	var before_positions := {}
	var gs = preview.get("_game_state")
	if gs == null:
		return false
	var expected_members := _available_party_ids(preview)
	for member in expected_members:
		before_positions[member] = gs.get_position(member)
	var event_start := _event_count(preview)
	var data_target := target.global_position
	if gs.coord_map != null and gs.coord_map.has_method("to_data"):
		data_target = gs.coord_map.to_data(data_target)

	var receipt: Dictionary = await _player_input_driver.call("rally", data_target)
	var rally_events := _events_of_kind(preview, event_start, "rally_members")
	receipt["observed_rally_events"] = rally_events.duplicate(true)
	var accepted := bool(receipt.get("accepted", false)) and rally_events.size() == 1
	var observed_members: Array[String] = []
	var event_members: Array[String] = []
	var rally_payload: Dictionary = {}
	if rally_events.size() == 1:
		rally_payload = (rally_events[0] as Dictionary).get("payload", {})
		for member_v in rally_payload.get("members", []):
			event_members.append(str(member_v))
	observed_members = event_members.duplicate()
	observed_members.sort()
	expected_members.sort()
	accepted = accepted and observed_members == expected_members

	var destinations: Array[Vector3] = GameEvent.arr_to_path(
		rally_payload.get("destinations", [])
	)
	var accepted_members: Array[String] = []
	var moving_members: Array[String] = []
	for member in expected_members:
		var moved: bool = gs.get_position(member).distance_to(
			before_positions.get(member, gs.get_position(member))
		) > 0.001
		if moved or gs.is_moving(member) or gs.is_external_traversal_active(member):
			moving_members.append(member)
			accepted_members.append(member)
		var event_index := event_members.find(member)
		if not accepted_members.has(member) and event_index >= 0 \
				and event_index < destinations.size() \
				and gs.get_position(member).distance_to(destinations[event_index]) < 0.15:
			accepted_members.append(member)
	receipt["requested_members"] = expected_members.duplicate()
	receipt["moving_members"] = moving_members.duplicate()
	receipt["accepted_members"] = accepted_members.duplicate()
	accepted = accepted \
		and accepted_members.size() == expected_members.size() \
		and not moving_members.is_empty()
	receipt["accepted"] = accepted
	if not accepted and str(receipt.get("reason", "")) == "":
		receipt["reason"] = "Rally did not accept exactly one route for every visible party member."

	_record_decision(
		preview,
		"rally_whole_party",
		"Move the whole visible party as one intent before servicing the next object.",
		_observe_target(preview, target),
		receipt
	)
	if accepted:
		_accepted_rally_count += 1
		_rally_members = observed_members.duplicate()
	return accepted


func _wait_for_rally_settle(preview: Node, timeout_seconds: float) -> bool:
	var gs = preview.get("_game_state")
	if gs == null:
		return false
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var moving := false
		for member in _rally_members:
			moving = moving or gs.is_moving(member) \
				or gs.is_external_traversal_active(member)
		if not moving:
			return true
		await _wait_seconds(0.10)
	return false


func _wait_for_interaction_trigger(
	preview: Node,
	target: Node3D,
	actor: String,
	event_start: int,
	timeout_seconds: float
) -> Dictionary:
	var started_at := Time.get_ticks_msec()
	var deadline := started_at + int(timeout_seconds * 1000.0)
	var settle_without_trigger_at := -1
	while Time.get_ticks_msec() < deadline:
		var triggers := _events_of_kind(preview, event_start, "trigger_interactable")
		if not triggers.is_empty():
			return (triggers[0] as Dictionary).duplicate(true)
		if Time.get_ticks_msec() - started_at > 600:
			var gs = preview.get("_game_state")
			if gs != null and gs.characters.has(actor) \
					and not gs.is_moving(actor) \
					and not gs.is_external_traversal_active(actor) \
					and not _interaction_pending(preview):
				if int(target.get("interactable_type")) != 2:
					return {}
				if settle_without_trigger_at < 0:
					settle_without_trigger_at = Time.get_ticks_msec()
				var dwell_grace_ms := int(
					(maxf(0.0, float(target.get("dwell_time"))) + 0.75) * 1000.0
				)
				if Time.get_ticks_msec() - settle_without_trigger_at > dwell_grace_ms:
					return {}
		await _wait_seconds(0.10)
	return {}


func _interaction_pending(preview: Node) -> bool:
	var player: Node = preview.get("_player")
	if player == null:
		return false
	var controller := player.get_node_or_null("CharacterInteractionController")
	return controller != null and controller.get("active_target") != null


func _ordered_visible_targets(
	preview: Node,
	chunk: Node,
	consumed_visible_states: Dictionary,
	last_success_token: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_targets: Variant = preview.get("_preview_interactables")
	if not (raw_targets is Array):
		return result
	var active_node := _active_character_node(preview)
	for target_v in raw_targets:
		if not (target_v is Node3D):
			continue
		var target := target_v as Node3D
		if not is_instance_valid(target) or not chunk.is_ancestor_of(target):
			continue
		if not _target_is_presented(target):
			continue
		var visible_state := _target_visible_state(target)
		if consumed_visible_states.has(visible_state):
			continue
		var distance := 0.0
		if active_node != null:
			distance = active_node.global_position.distance_to(target.global_position)
		result.append({
			"target": target,
			"visible_state": visible_state,
			"distance": distance,
			"repeat_penalty": 1 if visible_state == last_success_token else 0,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("repeat_penalty", 0)) != int(b.get("repeat_penalty", 0)):
			return int(a.get("repeat_penalty", 0)) < int(b.get("repeat_penalty", 0))
		if not is_equal_approx(float(a.get("distance", 0.0)), float(b.get("distance", 0.0))):
			return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0))
		return str(a.get("visible_state", "")) < str(b.get("visible_state", ""))
	)
	return result


func _target_is_presented(target: Node3D) -> bool:
	if not target.is_inside_tree() or not target.is_visible_in_tree():
		return false
	if not target.has_signal("interaction_requested"):
		return false
	if target.has_method("is_interaction_enabled") \
			and not bool(target.call("is_interaction_enabled")):
		return false
	if target is CollisionObject3D \
			and not (target as CollisionObject3D).input_ray_pickable:
		return false
	return true


func _target_visible_state(target: Node3D) -> String:
	# Only text and enabled state exposed by the object's hover/presentation surface
	# affect policy. Instance identity prevents two identical nearby props from collapsing.
	return "%d|%s|%s|%s|%s" % [
		target.get_instance_id(),
		str(target.get("tutorial_label")),
		str(target.get("description")),
		str(target.get("consequence_preview")),
		str(target.get("interaction_enabled")),
	]


func _visible_click_target(interactable: Node3D) -> Node3D:
	# The outline is the object a player actually sees and clicks. When present,
	# use its collision surface rather than aiming at a hidden Area origin.
	var outline: Variant = interactable.get("_outline_target")
	if outline is Node3D and is_instance_valid(outline) \
			and (outline as Node3D).is_visible_in_tree() \
			and (outline as Node3D).has_signal("interaction_requested"):
		return outline as Node3D
	return interactable


func _observe_target(preview: Node, target: Node3D) -> Dictionary:
	var point := _screen_point(preview, target.global_position)
	return {
		"tutorial_label": str(target.get("tutorial_label")),
		"description": str(target.get("description")),
		"consequence_preview": str(target.get("consequence_preview")),
		"screen_point": [point.x, point.y] if point.is_finite() else [],
		"interaction_enabled": bool(target.get("interaction_enabled")),
	}


func _actor_order(preview: Node) -> Array[String]:
	var order: Array[String] = []
	var preferred := _preferred_active_character()
	if preferred != "":
		order.append(preferred)
	var active := str(preview.call("get_preview_active_character")) \
		if preview.has_method("get_preview_active_character") else ""
	if active != "" and not order.has(active):
		order.append(active)
	for actor in PARTY_IDS:
		if not order.has(actor):
			order.append(actor)
	return order


func _party_needs_group_travel(preview: Node, target: Node3D) -> bool:
	var characters: Variant = preview.get("_characters")
	if not (characters is Dictionary):
		return true
	for member in _available_party_ids(preview):
		var node := (characters as Dictionary).get(member, null) as Node3D
		if node == null or node.global_position.distance_to(target.global_position) \
				> PARTY_NEAR_TARGET_RADIUS:
			return true
	return false


func _available_party_ids(preview: Node) -> Array[String]:
	var result: Array[String] = []
	var gs = preview.get("_game_state")
	var hud = preview.get("_hud")
	if gs == null or hud == null or not hud.has_method("get_portrait_ids"):
		return result
	var locked: Array = hud.call("get_hold_locked_ids") \
		if hud.has_method("get_hold_locked_ids") else []
	for member_v in hud.call("get_portrait_ids"):
		var member := str(member_v)
		if not gs.characters.has(member) or locked.has(member):
			continue
		if gs.has_method("can_accept_move_command") \
				and not bool(gs.call("can_accept_move_command", member)):
			continue
		result.append(member)
	result.sort()
	return result


func _bring_target_into_player_view(preview: Node, target: Node3D) -> bool:
	var camera := _camera(preview)
	if camera == null:
		return false
	for _step in range(12):
		var point := _screen_point(preview, target.global_position)
		var safe_rect := _safe_world_rect(preview)
		if point.is_finite() and safe_rect.has_point(point):
			return true
		if camera.is_position_behind(target.global_position):
			return false
		var viewport_rect := preview.get_viewport().get_visible_rect()
		var raw_point := camera.unproject_position(target.global_position)
		var center := safe_rect.get_center()
		var delta := raw_point - center
		var key := KEY_D if delta.x > 0.0 else KEY_A
		if absf(delta.y / maxf(1.0, viewport_rect.size.y)) \
				> absf(delta.x / maxf(1.0, viewport_rect.size.x)):
			key = KEY_S if delta.y > 0.0 else KEY_W
		await _hold_key(key, 0.24)
		await _wait_frames(1)
	return _safe_world_rect(preview).has_point(
		_screen_point(preview, target.global_position)
	)


func _camera_sweep_step(preview: Node, index: int) -> void:
	var keys := [KEY_W, KEY_D, KEY_S, KEY_A]
	var key: Key = keys[index % keys.size()]
	await _hold_key(key, 0.32 if index < 4 else 0.52)
	_record_decision(
		preview,
		"search_camera",
		"Pan the shipped camera to look for another visible affordance.",
		{"direction_key": int(key)},
		{
			"kind": "camera_pan",
			"accepted": true,
			"player_reproducible": true,
			"keycode": int(key),
		}
	)


func _safe_world_rect(preview: Node) -> Rect2:
	var viewport_rect := preview.get_viewport().get_visible_rect()
	var top_left := Vector2(
		viewport_rect.size.x * SAFE_SCREEN_MARGIN.x,
		viewport_rect.size.y * SAFE_SCREEN_MARGIN.y
	)
	var bottom_right := Vector2(
		viewport_rect.size.x * (1.0 - SAFE_SCREEN_MARGIN.z),
		viewport_rect.size.y * (1.0 - SAFE_SCREEN_MARGIN.w)
	)
	return Rect2(top_left, bottom_right - top_left)


func _screen_point(preview: Node, world_position: Vector3) -> Vector2:
	var camera := _camera(preview)
	if camera == null or camera.is_position_behind(world_position):
		return Vector2(INF, INF)
	var point := camera.unproject_position(world_position)
	return point if preview.get_viewport().get_visible_rect().has_point(point) \
		else Vector2(INF, INF)


func _camera(preview: Node) -> Camera3D:
	var candidate: Variant = preview.get("_camera")
	if candidate is Camera3D:
		return candidate as Camera3D
	return preview.get_viewport().get_camera_3d()


func _active_character_node(preview: Node) -> Node3D:
	var characters: Variant = preview.get("_characters")
	if not (characters is Dictionary):
		return null
	var active := str(preview.call("get_preview_active_character")) \
		if preview.has_method("get_preview_active_character") else ""
	return (characters as Dictionary).get(active, null) as Node3D


func _consume_visible_lysate(preview: Node) -> void:
	if not preview.has_method("get_preview_hand_items") \
			or not preview.has_method("get_preview_item_state"):
		return
	for actor in PARTY_IDS:
		for item_id_v in preview.call("get_preview_hand_items", actor):
			var item_id := str(item_id_v)
			var item: Dictionary = preview.call("get_preview_item_state", item_id)
			if str(item.get("type", "")) != "lysate" \
					or str(item.get("location", "")) != "hand":
				continue
			var selection: Dictionary = await _player_input_driver.call(
				"select_single", actor
			)
			if not bool(selection.get("accepted", false)):
				return
			var consume_receipt: Dictionary = await _player_input_driver.call(
				"press_key", _keycode_for_action("ability_secondary", KEY_X)
			)
			var deadline := Time.get_ticks_msec() + 6000
			while Time.get_ticks_msec() < deadline:
				var current: Dictionary = preview.call("get_preview_item_state", item_id)
				if str(current.get("location", "")) != "hand":
					consume_receipt["item_left_hand"] = true
					break
				await _wait_seconds(0.10)
			_record_decision(
				preview,
				"consume_visible_lysate",
				"Use the visible carried item so later pickups still have a free hand.",
				{"carrier": actor, "item_type": "lysate"},
				consume_receipt
			)
			return


func _keycode_for_action(action_name: String, fallback: Key) -> Key:
	if InputMap.has_action(action_name):
		for event_v in InputMap.action_get_events(action_name):
			if not (event_v is InputEventKey):
				continue
			var event := event_v as InputEventKey
			if event.physical_keycode != KEY_NONE:
				return event.physical_keycode
			if event.keycode != KEY_NONE:
				return event.keycode
	return fallback


func _completion_ready(chunk: Node) -> bool:
	var state: Dictionary = chunk.call("get_preview_state")
	return state.get(
		"completion_ready", state.get("shelter_rested", false)
	) == true


func _all_targets_attempted(
	candidates: Array[Dictionary], attempted: Dictionary, preview: Node
) -> bool:
	for candidate in candidates:
		var visible_state := str(candidate.get("visible_state", ""))
		for actor in _actor_order(preview):
			if not attempted.has("%s|%s" % [visible_state, actor]):
				return false
	return true


func _event_count(preview: Node) -> int:
	var gs = preview.get("_game_state")
	return gs.event_log.events.size() \
		if gs != null and gs.event_log != null else 0


func _events_of_kind(
	preview: Node, start_index: int, kind: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var gs = preview.get("_game_state")
	if gs == null or gs.event_log == null:
		return result
	for index in range(maxi(0, start_index), gs.event_log.events.size()):
		var event: Dictionary = gs.event_log.events[index]
		if str(event.get("kind", "")) == kind:
			result.append(event.duplicate(true))
	return result


func _trigger_matches_target(event: Dictionary, target: Node3D) -> bool:
	var payload: Dictionary = event.get("payload", {})
	var triggered_id := str(payload.get("id", ""))
	if triggered_id == "":
		return false
	return triggered_id == str(target.get("data_id")) \
		or triggered_id == str(target.get("interactable_id"))


func _visible_refusal_text(preview: Node) -> String:
	var hud_message: Variant = preview.get("_hud_message")
	if hud_message != null and bool((hud_message as Object).get("visible")):
		return str((hud_message as Object).get("text"))
	return "No player-facing acceptance cue was observed."


func _record_decision(
	preview: Node,
	decision: String,
	rationale: String,
	observation: Dictionary,
	action_receipt: Dictionary
) -> void:
	var row := {
		"index": _decision_receipts.size(),
		"decision": decision,
		"rationale": rationale,
		"observation": observation.duplicate(true),
		"action_receipt": action_receipt.duplicate(true),
		"player_reproducible": bool(
			action_receipt.get("player_reproducible", false)
		),
		"scheduler_tick": (
			float(preview.call("get_preview_scheduler_tick"))
			if preview != null and preview.has_method("get_preview_scheduler_tick")
			else 0.0
		),
	}
	_decision_receipts.append(row)
	print("[PLAYTHROUGH/decision] %s" % JSON.stringify(row))


func _preferred_active_character() -> String:
	# Peris owns the hydraulic read/interaction grammar in this maintained case.
	return "peris" if case_id == AUTHORED_HYDRAULIC_CASE_ID else ""


func _autonomous_focus_matches(preview: Node, expected_character: String) -> bool:
	if preview == null or not preview.has_method("get_preview_active_character") \
			or str(preview.call("get_preview_active_character")) != expected_character:
		return false
	var characters: Variant = preview.get("_characters")
	if not (characters is Dictionary):
		return false
	var expected_node := (
		(characters as Dictionary).get(expected_character, null) as Node3D
	)
	if expected_node == null:
		return false
	var camera: Variant = preview.get("_camera")
	if camera == null or (camera as Object).get("target") != expected_node:
		return false
	var occlusion_manager: Variant = preview.get("_occlusion_mgr")
	return occlusion_manager != null \
		and str((occlusion_manager as Object).get("watch_id")) == expected_character


func _wait_for_button(text: String, timeout_seconds: float) -> Button:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var current := get_tree().current_scene
		var button := _find_button(current, text)
		if button != null:
			return button
		await get_tree().process_frame
	return null


func _wait_for_preview_menu(timeout_seconds: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var current := get_tree().current_scene
		if current != null and current.get("_in_menu") == true \
				and _find_visible_option_button(current) != null:
			return current
		await get_tree().process_frame
	return null


func _wait_for_generated_preview(timeout_seconds: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var current := get_tree().current_scene
		if current != null:
			var chunk: Node = current.get("_active_chunk")
			if chunk != null and chunk.has_method("get_preview_state"):
				return current
		await get_tree().process_frame
	return null


func _find_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	if root is Button and not root is OptionButton \
			and (root as Button).text == text \
			and (root as Button).is_visible_in_tree():
		return root as Button
	for child in root.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _find_visible_option_button(root: Node) -> OptionButton:
	if root == null:
		return null
	if root is OptionButton and (root as OptionButton).is_visible_in_tree():
		return root as OptionButton
	for child in root.get_children():
		var found := _find_visible_option_button(child)
		if found != null:
			return found
	return null


func _seed_case_index(wanted_id: String) -> int:
	var catalog: Dictionary = StretchSeedCatalogScript.load_catalog()
	var cases: Array[Dictionary] = StretchSeedCatalogScript.cases(catalog)
	for index in range(cases.size()):
		if str(cases[index].get("id", "")) == wanted_id:
			return index
	return -1


func _select_option_index(selector: OptionButton, index: int) -> void:
	await _click_control(selector)
	await _wait_seconds(0.18)
	var popup: PopupMenu = selector.get_popup()
	if popup != null and popup.visible and popup.item_count > index:
		var popup_rect := Rect2(Vector2(popup.position), Vector2(popup.size))
		var row_height: float = popup_rect.size.y / float(popup.item_count)
		var item_position := Vector2(
			popup_rect.position.x + popup_rect.size.x * 0.5,
			popup_rect.position.y + row_height * (float(index) + 0.5)
		)
		await _mouse_click(item_position, MOUSE_BUTTON_LEFT)
	await _wait_seconds(0.3)


func _click_control(control: Control) -> void:
	var rect := control.get_global_rect()
	await _mouse_click(rect.position + rect.size * 0.5, MOUSE_BUTTON_LEFT)


func _mouse_click(position: Vector2, button: MouseButton) -> void:
	# Synthetic player input stays local to Godot. Moving the workstation cursor
	# would make the same test depend on desktop focus and disrupt the user.
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await get_tree().process_frame
	await get_tree().physics_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = button
		event.pressed = pressed
		event.button_mask = _mouse_mask(button) if pressed else 0
		Input.parse_input_event(event)
		await get_tree().process_frame


func _mouse_mask(button: MouseButton) -> int:
	match button:
		MOUSE_BUTTON_LEFT:
			return MOUSE_BUTTON_MASK_LEFT
		MOUSE_BUTTON_RIGHT:
			return MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			return MOUSE_BUTTON_MASK_MIDDLE
	return 0


func _send_key(keycode: Key) -> void:
	for pressed in [true, false]:
		_send_key_event(keycode, pressed)
		await get_tree().process_frame


func _hold_key(keycode: Key, seconds: float) -> void:
	_send_key_event(keycode, true)
	await get_tree().create_timer(seconds, true, false, true).timeout
	_send_key_event(keycode, false)
	await get_tree().process_frame


func _send_key_event(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _wait_frames(count: int) -> void:
	for _frame in range(maxi(1, count)):
		await get_tree().process_frame


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _finish_recording() -> void:
	var recorder := get_parent()
	if recorder != null and recorder.has_method("stop_recording"):
		recorder.call("stop_recording", true)
	else:
		get_tree().quit(0)


func _fail(reason: String) -> void:
	push_error("[PLAYTHROUGH/pilot] %s" % reason)
	var recorder := get_parent()
	if recorder != null and recorder.has_method("stop_recording"):
		recorder.call("stop_recording", false)
	get_tree().quit(1)
