extends Node

## QA-only deterministic input pilot for generated-stretch recording.
##
## This node never mutates puzzle state. It starts at the real main menu, chooses a maintained
## seed through the visible fragment picker, then sends the same mouse/key events a player would
## use to move and interact. PlaythroughSession records those events; the driver is intentionally
## not installed during replay, proving that the tape alone can reload and play the level.

const StretchSeedCatalogScript = preload("res://scripts/generation/stretch_seed_catalog.gd")
const RuntimeRegistryScript = preload(
	"res://scripts/generation/generated_node_runtime_registry.gd"
)
const PARTY_KEYS := {
	"aster": KEY_1,
	"peris": KEY_2,
	"endo": KEY_3,
}
const TARGET_COMPLETION_TIMEOUT_SECONDS := 12.0
const TARGET_ATTEMPTS := 4
const GENERATED_COMMAND_PREFIX := "qa_generated_node_command/"
const WORLD_INTERACTION_PREFIX := "qa_world_interaction/"
const GENERATED_CASE_PREFIX := "qa_play_generated_case/"
const AUTHORED_HYDRAULIC_CASE_ID := "teaching_channels_spiral"

var case_id := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

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
	if case_id == AUTHORED_HYDRAULIC_CASE_ID:
		var generated_button := _find_button(preview, "Generated Stretch")
		if generated_button == null:
			_fail("Generated Stretch button was not found")
			return
		await _click_control(generated_button)
	else:
		var case_index := _seed_case_index(case_id)
		if case_index < 0:
			_fail("unknown generated seed case '%s'" % case_id)
			return
		await _send_action(GENERATED_CASE_PREFIX + case_id)

	preview = await _wait_for_generated_preview(18.0)
	if preview == null:
		_fail("generated stretch did not load")
		return
	var chunk: Node = preview.get("_active_chunk")
	if chunk == null or not chunk.has_method("get_generation_spec"):
		_fail("generated stretch chunk is unavailable")
		return

	# Leave a brief readable establishing shot, then clear the large help/debug panels and run.
	await _wait_seconds(1.0)
	await _send_key(KEY_H)
	await _send_key(KEY_F4)
	# Peris services the authored hydraulic controls, so camera follow and the see-through
	# watch centre remain on the character the deterministic pilot actually moves.
	var preferred_active := _preferred_active_character()
	await _ensure_full_party(preview, preferred_active)
	if preferred_active != "" and not _autonomous_focus_matches(preview, preferred_active):
		_fail("autonomous focus did not settle on %s" % preferred_active)
		return
	await _send_key(KEY_R)
	await _send_key(KEY_HOME)
	if case_id == AUTHORED_HYDRAULIC_CASE_ID:
		if not await _play_authored_hydraulic(preview, chunk):
			_fail("could not complete the authored hydraulic teaching spiral")
			return
		print("[PLAYTHROUGH/pilot] COMPLETE %s" % case_id)
		await _wait_seconds(2.0)
		_finish_recording()
		return

	var spec: Dictionary = chunk.call("get_generation_spec")
	var path: Array = spec.get("headless", {}).get("golden_path", [])
	if path.is_empty():
		_fail("generated seed has no golden path")
		return
	var solution: Dictionary = spec.get("headless", {}).get("solution", {})
	var consumed_solution_actions := {}
	print("[PLAYTHROUGH/pilot] Playing %s through %d generated beats" % [case_id, path.size()])
	for node_id_v in path:
		var node_id := str(node_id_v)
		if not await _play_solution_actions_before_node(
			preview,
			chunk,
			solution,
			node_id,
			consumed_solution_actions
		):
			_fail("could not complete physical solution action before '%s'" % node_id)
			return
		if not await _play_node(preview, chunk, node_id, spec):
			_fail("could not complete generated beat '%s'" % node_id)
			return
		await _consume_generated_lysate(preview, chunk, node_id)
		await _wait_seconds(0.55)

	var final_state: Dictionary = chunk.call("get_preview_state")
	if final_state.get(
		"completion_ready", final_state.get("shelter_rested", false)
	) != true:
		_fail("golden path ended without shelter completion")
		return
	print("[PLAYTHROUGH/pilot] COMPLETE %s" % case_id)
	await _wait_seconds(2.0)
	_finish_recording()


func _play_authored_hydraulic(preview: Node, chunk: Node) -> bool:
	print("[PLAYTHROUGH/pilot] Playing authored hydraulic teach -> practice -> transfer")
	# Teaching: one marked intervention demonstrates that opening a source makes
	# downstream water and its cistern relationship visible.
	if not await _play_world_step(preview, chunk, "open_first_sluice", "first_sluice_open"):
		return false
	# Guided practice: collect the mandatory carried resource, then use the now-wet
	# cistern. Its hover relation remains available, but it has no persistent answer arrow.
	if not await _play_node(preview, chunk, "node_02"):
		return false
	if not await _play_world_step(preview, chunk, "release_cistern_bridge", "cistern_bridge_installed"):
		return false
	# Optional transfer: briefly borrow the ready main current, then restore it while the
	# physical lysate is still traveling. The payload keeps its launch-time spillway route;
	# once it visibly arrives, take it with a free hand. A minimal run may skip this whole bet.
	if not await _play_world_step(preview, chunk, "divert_current", "borrowed_current_diverted"):
		return false
	if not await _play_world_step(preview, chunk, "restore_main_current", "main_current_restored"):
		return false
	if not await _wait_for_state_value(
		chunk, "spillway_delivery_phase", "available", TARGET_COMPLETION_TIMEOUT_SECONDS
	):
		return false
	if not await _play_world_step(preview, chunk, "catch_spillway", "hydraulic_spillway_food_collected"):
		return false
	return await _play_world_step(
		preview, chunk, "enter_shelter", "completion_ready", true, 40.0
	)


func _wait_for_state_value(
	chunk: Node,
	state_key: String,
	expected: Variant,
	timeout_seconds: float
) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = chunk.call("get_preview_state")
		if state.get(state_key) == expected:
			return true
		await _wait_seconds(0.12)
	return false


func _play_world_step(
	preview: Node,
	chunk: Node,
	action_id: String,
	state_key: String,
	expected := true,
	timeout_seconds := TARGET_COMPLETION_TIMEOUT_SECONDS
) -> bool:
	for attempt in range(TARGET_ATTEMPTS):
		var state: Dictionary = chunk.call("get_preview_state")
		if bool(state.get(state_key, not expected)) == expected:
			return true
		await _ensure_full_party(preview, _preferred_active_character())
		if attempt == 0:
			print("[PLAYTHROUGH/pilot] world action %s" % action_id)
		await _send_key(KEY_HOME)
		await _send_world_interaction(action_id)
		var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
		while Time.get_ticks_msec() < deadline:
			state = chunk.call("get_preview_state")
			if bool(state.get(state_key, not expected)) == expected:
				# Consequence cameras for the teaching and practice beats briefly pause
				# gameplay. Let that readable shot finish before issuing the next tape input.
				await _wait_seconds(1.8)
				return true
			await _wait_seconds(0.12)
		print("[PLAYTHROUGH/pilot] world action %s retry=%d phase=%s outcome=%s" % [
			action_id,
			attempt + 1,
			str(state.get("hydraulic_phase", "")),
			str(state.get("last_outcome", "")),
		])
	return false


func _play_solution_actions_before_node(
	preview: Node,
	chunk: Node,
	solution: Dictionary,
	node_id: String,
	consumed: Dictionary
) -> bool:
	var groups := [
		{"group": "world", "actions": solution.get("world_actions", [])},
		{"group": "branch", "actions": solution.get("branch_actions", [])},
	]
	for group_v in groups:
		var group := group_v as Dictionary
		var action_group := str(group.get("group", ""))
		var actions: Array = group.get("actions", [])
		for index in range(actions.size()):
			var key := "%s:%d" % [action_group, index]
			if consumed.has(key):
				continue
			var action_v: Variant = actions[index]
			if not (action_v is Dictionary):
				continue
			var action := action_v as Dictionary
			var before_nodes: Array = action.get(
				"before_nodes", [str(action.get("before_node", ""))]
			)
			if not before_nodes.has(node_id):
				continue
			consumed[key] = true
			var completed := false
			if action_group == "branch":
				completed = await _play_branch_solution_action(
					preview, chunk, action
				)
			else:
				completed = await _play_world_solution_action(
					preview, chunk, action
				)
			if not completed:
				return false
	return true


func _play_branch_solution_action(
	preview: Node, chunk: Node, action: Dictionary
) -> bool:
	var action_id := str(action.get("id", ""))
	var branch_id := str(action.get(
		"branch_id", action.get("target", "")
	))
	var expected_phase := str(action.get("expected_phase", "bridged"))
	if action_id == "" or branch_id == "":
		return false
	for attempt in range(TARGET_ATTEMPTS):
		if _branch_solution_action_complete(
			chunk, branch_id, expected_phase
		):
			return true
		await _ensure_full_party(preview, _preferred_active_character())
		if attempt == 0:
			print("[PLAYTHROUGH/pilot] branch action %s" % action_id)
		await _send_key(KEY_HOME)
		await _send_world_interaction(action_id)
		var deadline := Time.get_ticks_msec() \
			+ int(TARGET_COMPLETION_TIMEOUT_SECONDS * 1000.0)
		while Time.get_ticks_msec() < deadline:
			if _branch_solution_action_complete(
				chunk, branch_id, expected_phase
			):
				return true
			await _wait_seconds(0.12)
		print("[PLAYTHROUGH/pilot] branch action %s retry=%d state=%s" % [
			action_id,
			attempt + 1,
			str(chunk.call("get_preview_state").get("branch_span_states", [])),
		])
	return false


func _branch_solution_action_complete(
	chunk: Node, branch_id: String, expected_phase: String
) -> bool:
	var state: Dictionary = chunk.call("get_preview_state")
	for span_v in state.get("branch_span_states", []):
		if not (span_v is Dictionary):
			continue
		var span := span_v as Dictionary
		if str(span.get("branch_id", "")) == branch_id:
			return str(span.get("phase", "")) == expected_phase
	return false


func _play_world_solution_action(
	preview: Node, chunk: Node, action: Dictionary
) -> bool:
	match str(action.get("action", "")):
		"open_sluice", "open_first_sluice":
			return await _play_world_step(
				preview, chunk, "open_first_sluice", "first_sluice_open"
			)
		"release_bridge", "release_cistern_bridge":
			return await _play_world_step(
				preview,
				chunk,
				"release_cistern_bridge",
				"cistern_bridge_installed",
				true,
				24.0
			)
		"divert", "divert_current":
			return await _play_world_step(
				preview, chunk, "divert_current", "borrowed_current_diverted"
			)
		"restore", "restore_main_current":
			return await _play_world_step(
				preview, chunk, "restore_main_current", "main_current_restored"
			)
		"catch", "catch_spillway":
			return await _play_world_step(
				preview,
				chunk,
				"catch_spillway",
				"hydraulic_spillway_food_collected"
			)
		"enter_shelter":
			return await _play_world_step(
				preview, chunk, "enter_shelter", "completion_ready", true, 40.0
			)
	return false


func _play_node(
	preview: Node, chunk: Node, node_id: String, spec: Dictionary = {}
) -> bool:
	var resolved_spec := spec
	if resolved_spec.is_empty() and chunk.has_method("get_generation_spec"):
		resolved_spec = chunk.call("get_generation_spec")
	var node := _find_spec_node(resolved_spec, node_id)
	var runtime_handler := RuntimeRegistryScript.handler_for_node(
		node, str(resolved_spec.get("id", ""))
	)
	if runtime_handler == "":
		# Layout-only records deliberately own no phantom interaction. The next real
		# target's ordinary click-to-walk path physically traverses this route space.
		print("[PLAYTHROUGH/pilot] traverse layout %s" % node_id)
		return true
	for attempt in range(TARGET_ATTEMPTS):
		if _node_complete(chunk, node_id):
			return true
		await _ensure_full_party(preview, _preferred_active_character())
		var target := chunk.get_node_or_null("GeneratedNode_%s" % node_id) as Node3D
		if target == null:
			return false
		if attempt == 0:
			print("[PLAYTHROUGH/pilot] command %s" % node_id)
		await _send_key(KEY_HOME)
		await _send_generated_command(node_id)
		# Let the live cooperative route, arrival signal, and timed interaction finish before
		# issuing another command. Re-commanding every second cancels and replans reservation
		# waits, which can starve a long final leg even though every click is individually valid.
		var completion_timeout := (
			40.0 if node_id == "exit_shelter" else TARGET_COMPLETION_TIMEOUT_SECONDS
		)
		var deadline := Time.get_ticks_msec() + int(completion_timeout * 1000.0)
		var next_recenter := Time.get_ticks_msec() + 2600
		while Time.get_ticks_msec() < deadline:
			if _node_complete(chunk, node_id):
				return true
			if Time.get_ticks_msec() >= next_recenter:
				await _send_key(KEY_HOME)
				next_recenter = Time.get_ticks_msec() + 2600
			await _wait_seconds(0.12)
		var attempt_state: Dictionary = chunk.call("get_preview_state")
		var attempt_generation: Dictionary = attempt_state.get("generation", {})
		print("[PLAYTHROUGH/pilot] %s retry=%d completed=%s outcome=%s phase=%s" % [
			node_id,
			attempt + 1,
			attempt_generation.get("completed_nodes", []),
			attempt_state.get("last_outcome", ""),
			attempt_state.get("route_phase", ""),
		])
	return _node_complete(chunk, node_id)


func _consume_generated_lysate(
	preview: Node, chunk: Node, node_id: String
) -> void:
	var spec: Dictionary = chunk.call("get_generation_spec")
	var node := _find_spec_node(spec, node_id)
	if RuntimeRegistryScript.handler_for_node(
		node, str(spec.get("id", ""))
	) != RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE:
		return
	for char_id in PARTY_KEYS:
		for item_id_v in preview.call("get_preview_hand_items", char_id):
			var item_id := str(item_id_v)
			var item: Dictionary = preview.call("get_preview_item_state", item_id)
			var properties: Dictionary = item.get("properties", {})
			if str(item.get("type", "")) != "lysate" \
					or str(properties.get("generated_node_id", "")) != node_id:
				continue
			print("[PLAYTHROUGH/pilot] %s consumes %s to keep a hand free" % [
				char_id,
				item_id,
			])
			await _send_key(int(PARTY_KEYS[char_id]))
			await _send_key(_keycode_for_action("ability_secondary", KEY_X))
			var deadline := Time.get_ticks_msec() + 6000
			while Time.get_ticks_msec() < deadline:
				var current: Dictionary = preview.call(
					"get_preview_item_state", item_id
				)
				if str(current.get("location", "")) != "hand":
					return
				await _wait_seconds(0.12)
			return


func _find_spec_node(spec: Dictionary, node_id: String) -> Dictionary:
	for node_v in spec.get("nodes", []):
		if node_v is Dictionary \
				and str((node_v as Dictionary).get("id", "")) == node_id:
			return (node_v as Dictionary).duplicate(true)
	return {}


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


func _node_complete(chunk: Node, node_id: String) -> bool:
	var state: Dictionary = chunk.call("get_preview_state")
	if node_id == "exit_shelter":
		return state.get(
			"completion_ready", state.get("shelter_rested", false)
		) == true
	var generation: Dictionary = state.get("generation", {})
	return (generation.get("completed_nodes", []) as Array).has(node_id)

func _ensure_full_party(preview: Node, preferred_active := "") -> void:
	if not preview.has_method("get_preview_selected_characters"):
		return
	var selected: Array = preview.call("get_preview_selected_characters")
	for char_id in PARTY_KEYS:
		if not selected.has(char_id):
			await _send_key(int(PARTY_KEYS[char_id]), true)
			await _wait_seconds(0.08)
			selected = preview.call("get_preview_selected_characters")
	if preferred_active != "" and PARTY_KEYS.has(preferred_active) \
			and selected.has(preferred_active) \
			and preview.has_method("get_preview_active_character") \
			and str(preview.call("get_preview_active_character")) != preferred_active:
		# A plain number press makes this member active while FragmentPreviewSequence
		# deliberately preserves the already-selected party.
		await _send_key(int(PARTY_KEYS[preferred_active]))


func _preferred_active_character() -> String:
	# Peris owns the hydraulic interactions in this maintained Movie Maker run.
	# Other generated cases keep their authored/default lead.
	return "peris" if case_id == AUTHORED_HYDRAULIC_CASE_ID else ""


func _autonomous_focus_matches(preview: Node, expected_character: String) -> bool:
	if preview == null or not preview.has_method("get_preview_active_character") \
			or str(preview.call("get_preview_active_character")) != expected_character:
		return false
	# FragmentPreviewSequence derives both camera follow and the see-through shader watch
	# from the active character. Assert both seams so a future presentation refactor cannot
	# silently frame/cut around Aster while Peris works the hydraulic controls.
	var characters: Variant = preview.get("_characters")
	if not characters is Dictionary:
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
		if current != null and current.get("_in_menu") == true and _find_visible_option_button(current) != null:
			return current
		await get_tree().process_frame
	return null

func _wait_for_generated_preview(timeout_seconds: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var current := get_tree().current_scene
		if current != null:
			var chunk: Node = current.get("_active_chunk")
			if chunk != null and chunk.has_method("get_generation_spec"):
				return current
		await get_tree().process_frame
	return null

func _find_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	if root is Button and not root is OptionButton and (root as Button).text == text and (root as Button).is_visible_in_tree():
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
	if popup != null and popup.visible and popup.item_count > 0:
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
	Input.warp_mouse(position)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await get_tree().process_frame
	await get_tree().physics_frame
	var pressed := InputEventMouseButton.new()
	pressed.position = position
	pressed.global_position = position
	pressed.button_index = button
	pressed.pressed = true
	pressed.button_mask = _mouse_mask(button)
	Input.parse_input_event(pressed)
	await get_tree().process_frame
	var released := pressed.duplicate() as InputEventMouseButton
	released.pressed = false
	released.button_mask = 0
	Input.parse_input_event(released)
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

func _send_key(keycode: Key, shift := false) -> void:
	_send_key_event(keycode, true, shift)
	await get_tree().process_frame
	_send_key_event(keycode, false, shift)
	await get_tree().process_frame

func _send_key_event(keycode: Key, pressed: bool, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.shift_pressed = shift
	event.pressed = pressed
	Input.parse_input_event(event)

func _send_generated_command(node_id: String) -> void:
	await _send_action(GENERATED_COMMAND_PREFIX + node_id)


func _send_world_interaction(action_id: String) -> void:
	await _send_action(WORLD_INTERACTION_PREFIX + action_id)

func _send_action(action_name: String) -> void:
	var event := InputEventAction.new()
	event.action = StringName(action_name)
	event.pressed = true
	event.strength = 1.0
	Input.parse_input_event(event)
	await get_tree().process_frame
	var released := event.duplicate() as InputEventAction
	released.pressed = false
	released.strength = 0.0
	Input.parse_input_event(released)
	await get_tree().process_frame

func _wait_frames(count: int) -> void:
	for _frame in range(count):
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
