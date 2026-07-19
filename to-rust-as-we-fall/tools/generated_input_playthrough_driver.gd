extends Node

## QA-only deterministic input pilot for generated-stretch recording.
##
## This node never mutates puzzle state. It starts at the real main menu, chooses a maintained
## seed through the visible fragment picker, then sends the same mouse/key events a player would
## use to move and interact. PlaythroughSession records those events; the driver is intentionally
## not installed during replay, proving that the tape alone can reload and play the level.

const StretchSeedCatalogScript = preload("res://scripts/generation/stretch_seed_catalog.gd")
const PARTY_KEYS := {
	"aster": KEY_1,
	"peris": KEY_2,
	"endo": KEY_3,
}
const TARGET_COMPLETION_TIMEOUT_SECONDS := 12.0
const TARGET_ATTEMPTS := 4
const GENERATED_COMMAND_PREFIX := "qa_generated_node_command/"
const GENERATED_CASE_PREFIX := "qa_play_generated_case/"

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
	await _ensure_full_party(preview)
	await _send_key(KEY_R)
	await _send_key(KEY_HOME)

	var spec: Dictionary = chunk.call("get_generation_spec")
	var path: Array = spec.get("headless", {}).get("golden_path", [])
	if path.is_empty():
		_fail("generated seed has no golden path")
		return
	print("[PLAYTHROUGH/pilot] Playing %s through %d generated beats" % [case_id, path.size()])
	for node_id_v in path:
		var node_id := str(node_id_v)
		if not await _play_node(preview, chunk, node_id):
			_fail("could not complete generated beat '%s'" % node_id)
			return
		await _wait_seconds(0.55)

	var final_state: Dictionary = chunk.call("get_preview_state")
	if final_state.get("shelter_rested", false) != true:
		_fail("golden path ended without shelter completion")
		return
	print("[PLAYTHROUGH/pilot] COMPLETE %s" % case_id)
	await _wait_seconds(2.0)
	_finish_recording()

func _play_node(preview: Node, chunk: Node, node_id: String) -> bool:
	for attempt in range(TARGET_ATTEMPTS):
		if _node_complete(chunk, node_id):
			return true
		await _ensure_full_party(preview)
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
		var deadline := Time.get_ticks_msec() + int(TARGET_COMPLETION_TIMEOUT_SECONDS * 1000.0)
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

func _node_complete(chunk: Node, node_id: String) -> bool:
	var state: Dictionary = chunk.call("get_preview_state")
	if node_id == "exit_shelter":
		return state.get("shelter_rested", false) == true
	var generation: Dictionary = state.get("generation", {})
	return (generation.get("completed_nodes", []) as Array).has(node_id)

func _ensure_full_party(preview: Node) -> void:
	if not preview.has_method("get_preview_selected_characters"):
		return
	var selected: Array = preview.call("get_preview_selected_characters")
	for char_id in PARTY_KEYS:
		if not selected.has(char_id):
			await _send_key(int(PARTY_KEYS[char_id]), true)
			await _wait_seconds(0.08)
			selected = preview.call("get_preview_selected_characters")

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
		recorder.call("stop_recording", true)
	else:
		get_tree().quit(1)
