class_name AgentPlayerInputDriver
extends Node

## Deterministic executor for automated player decisions.
##
## Decisions may be clever, foolish, or random. Their execution is invariant:
## every action is expressed as shipped keyboard/pointer input from the live
## authored scene. This driver observes authority only to build receipts; it
## never mutates GameState, calls a consequence callback, or decomposes a party
## verb into singleton commands.

const CHARACTER_KEYS := {
	"aster": KEY_1,
	"peris": KEY_2,
	"endo": KEY_3,
}
# A missing/occluded indicator must never make an automated gesture release as
# a short click. This fallback is deliberately above the shipped configurable
# maximum; the normal path releases from the public rendered READY cue instead.
const RALLY_HOLD_FALLBACK_SECONDS := 1.35
const SETTLE_FRAMES := 2
const INTERACTION_COMMAND_EVENT_KINDS := [
	"move_to_cell",
	"move_cross_level",
	"move_to_pos",
	"walk_path",
	"begin_external_traversal",
	"trigger_interactable",
	"begin_mechanism_phase",
	"rally_members",
	"party_rest",
	"rest",
	"push_object",
	"pick_up_item",
]
const PRESENTATION_ONLY_RECEIPT_KINDS := [
	"hover_pointer",
	"park_pointer",
	"recenter",
	"rotate_camera",
	"toggle_instructions",
	"zoom_out",
]

var _host: Node
var _receipts: Array[Dictionary] = []
var _next_action_id := 1
var _held_keys: Dictionary = {}
var _held_mouse_buttons: Dictionary = {}
var _last_pointer := Vector2.ZERO
var _input_events: Array[Dictionary] = []
var _next_input_sequence := 1
var _rendered_hover_valid := false
var _rendered_hover_point := Vector2.INF
var _rendered_hover_token := ""
var _rendered_hover_sequence := -1

func setup(host: Node) -> void:
	_host = host
	_held_keys.clear()
	_held_mouse_buttons.clear()
	_last_pointer = _viewport_rect().get_center()
	_clear_rendered_hover()

func receipts() -> Array[Dictionary]:
	return _receipts.duplicate(true)

func last_receipt() -> Dictionary:
	return _receipts.back().duplicate(true) if not _receipts.is_empty() else {}

func clear_receipts() -> void:
	_receipts.clear()
	_next_action_id = 1
	_input_events.clear()
	_next_input_sequence = 1
	_clear_rendered_hover()


## Watchdog cleanup only. This never chooses or applies a gameplay action; it
## guarantees that an aborted automated gesture cannot leave a synthetic key or
## mouse button held in the shared production Input surface.
func release_all_held_input(reason := "watchdog_abort") -> Dictionary:
	var released_keys: Array[int] = []
	var released_buttons: Array[int] = []
	for keycode_v in _held_keys.keys():
		var keycode := int(keycode_v)
		var modifiers_v: Variant = _held_keys.get(keycode_v, {})
		var modifiers := modifiers_v as Dictionary \
			if modifiers_v is Dictionary else {}
		var event := InputEventKey.new()
		event.keycode = keycode as Key
		event.physical_keycode = keycode as Key
		event.ctrl_pressed = bool(modifiers.get("ctrl", false))
		event.shift_pressed = bool(modifiers.get("shift", false))
		event.pressed = false
		Input.parse_input_event(event)
		released_keys.append(keycode)
	for button_v in _held_mouse_buttons.keys():
		var button := int(button_v)
		var event := InputEventMouseButton.new()
		event.position = _last_pointer
		event.global_position = _last_pointer
		event.button_index = button as MouseButton
		event.button_mask = 0
		event.pressed = false
		Input.parse_input_event(event)
		released_buttons.append(button)
	_held_keys.clear()
	_held_mouse_buttons.clear()
	released_keys.sort()
	released_buttons.sort()
	await _wait_frames(1)
	return {
		"kind": "watchdog_input_release",
		"reason": reason,
		"released_keys": released_keys,
		"released_mouse_buttons": released_buttons,
		"all_inputs_released": true,
	}

func select_single(character_id: String) -> Dictionary:
	var receipt := _begin_receipt("select_single", {"character_id": character_id})
	receipt["input_issued"] = false
	receipt["already_selected"] = false
	if not CHARACTER_KEYS.has(character_id):
		return _finish_receipt(receipt, false, "No shipped selection key for %s." % character_id)
	var hud = _host.get("_hud") if _host != null else null
	if hud != null and hud.has_method("get_selected_ids"):
		var selected: Array = hud.call("get_selected_ids")
		# Shipped Ctrl+portrait input can remove every sibling from a multi-selection.
		# Clicking a guessed "empty" world pixel was both unnecessary and unsafe: the
		# guess was derived from private render positions and could issue a real move.
		if not selected.has(character_id):
			receipt["input_issued"] = true
			await _send_key(int(CHARACTER_KEYS[character_id]))
			selected = hud.call("get_selected_ids")
		for selected_id_v in selected.duplicate():
			var selected_id := str(selected_id_v)
			if selected_id == character_id or not CHARACTER_KEYS.has(selected_id):
				continue
			receipt["input_issued"] = true
			await _send_key(int(CHARACTER_KEYS[selected_id]), true)
		selected = hud.call("get_selected_ids")
		receipt["already_selected"] = not bool(receipt["input_issued"])
		return _finish_receipt(receipt, selected == [character_id],
			"" if selected == [character_id] else "Selection did not settle to one portrait.")
	return _finish_receipt(receipt, false, "The shipped HUD selection surface is unavailable.")

func select_party() -> Dictionary:
	var receipt := _begin_receipt("select_party", {})
	receipt["input_issued"] = false
	# Selection is a presentation verb over the visible portraits. A busy/traversing body is still a
	# visible party member, so hidden movement availability must never shrink this intent.
	var expected: Array[String] = _presented_party_ids()
	receipt["intended_members"] = expected.duplicate()
	receipt["member_results"] = _selection_member_results(expected, [])
	if expected.is_empty():
		return _finish_receipt(receipt, false, "No controllable party portraits are available.")
	receipt["expected"] = expected
	var unbound_members: Array[String] = []
	for member_id in expected:
		if not CHARACTER_KEYS.has(member_id):
			unbound_members.append(member_id)
	if not unbound_members.is_empty():
		receipt["unbound_members"] = unbound_members
		return _finish_receipt(receipt, false,
			"Visible party portraits lack shipped selection controls: %s." \
				% str(unbound_members))
	var selected: Array = _selected_ids()
	var already_selected := selected.size() == expected.size()
	for id in expected:
		already_selected = already_selected and selected.has(id)
	if already_selected:
		# The highlighted portraits are shipped, visible state. A human does not toggle two members off
		# merely to recreate an already-complete selection before the next group interaction.
		receipt["already_selected"] = true
		receipt["member_results"] = _selection_member_results(expected, selected)
		return _finish_receipt(receipt, true, "")
	# A non-modified key on an already-selected portrait is also a no-op. When a partial multi-select
	# exists, start with one visibly missing portrait so the shipped HUD deterministically collapses to
	# that singleton, then Ctrl-add every sibling exactly once.
	var primary := expected[0]
	if selected.size() > 1:
		for id in expected:
			if not selected.has(id):
				primary = id
				break
	await _send_key(int(CHARACTER_KEYS[primary]))
	receipt["input_issued"] = true
	for id in expected:
		if id != primary:
			await _send_key(int(CHARACTER_KEYS[id]), true)
	selected = _selected_ids()
	var accepted := selected.size() == expected.size()
	for id in expected:
		accepted = accepted and selected.has(id)
	receipt["member_results"] = _selection_member_results(expected, selected)
	return _finish_receipt(receipt, accepted,
		"" if accepted else "Ctrl+portrait selection did not select the controllable party.")


func _selection_member_results(expected: Array[String], selected: Array) -> Dictionary:
	var results := {}
	for member_id in expected:
		results[member_id] = "accepted" if selected.has(member_id) else "refused"
	return results

func move(character_id: String, data_target: Vector3) -> Dictionary:
	var receipt := _begin_receipt("move", {
		"character_id": character_id,
		"target": data_target,
	})
	var selection := await select_single(character_id)
	if not bool(selection.get("accepted", false)):
		return _finish_receipt(receipt, false, str(selection.get("reason", "Selection refused.")))
	var render_target := _render_position(data_target)
	var point := _screen_point(render_target)
	if not point.is_finite():
		return _finish_receipt(receipt, false, "Target is not visible through the current player camera.")
	await _mouse_click(point, MOUSE_BUTTON_RIGHT)
	await _wait_frames(SETTLE_FRAMES)
	return _finish_from_live_command(receipt, character_id)


## Screen-space variant used by observation-driven players. The policy receives the same pixel a
## person can point at; it never needs an authored world coordinate or target node name.
func move_screen(character_id: String, point: Vector2) -> Dictionary:
	var receipt := _begin_receipt("move", {
		"character_id": character_id,
		"screen_point": point,
	})
	if not _viewport_rect().has_point(point):
		return _finish_receipt(receipt, false, "The point is outside the shipped viewport.")
	var selection := await select_single(character_id)
	if not bool(selection.get("accepted", false)):
		return _finish_receipt(receipt, false, str(selection.get("reason", "Selection refused.")))
	await _mouse_click(point, MOUSE_BUTTON_RIGHT)
	await _wait_frames(SETTLE_FRAMES)
	return _finish_from_live_command(receipt, character_id)

func rally(data_target: Vector3) -> Dictionary:
	var receipt := _begin_receipt("rally", {"target": data_target})
	var render_target := _render_position(data_target)
	var point := _screen_point(render_target)
	if not point.is_finite():
		return _finish_receipt(receipt, false, "Rally target is not visible through the current player camera.")
	return await hold_rally(receipt, point)


func rally_screen(point: Vector2) -> Dictionary:
	var receipt := _begin_receipt("rally", {"screen_point": point})
	if not _viewport_rect().has_point(point):
		return _finish_receipt(receipt, false, "The point is outside the shipped viewport.")
	return await hold_rally(receipt, point)


## Stage one of an observation-bound pointer action. This sends one ordinary
## viewport-local MouseMotion (never an OS cursor warp), waits until the hover
## has had a rendered frame, and receipts the exact packet that was delivered.
## The opaque token is copied from player_observation_v1; the driver never
## resolves it through a node, camera, collider, or world coordinate.
func hover_screen(point: Vector2, target_token := "") -> Dictionary:
	var receipt := _begin_receipt("hover_pointer", {
		"screen_point": point,
		"target_token": target_token,
		"rendered_hover_waited": false,
	})
	_clear_rendered_hover()
	if not _viewport_rect().has_point(point):
		return _finish_receipt(
			receipt, false, "The hover point is outside the shipped viewport.")
	if target_token.strip_edges() == "":
		return _finish_receipt(
			receipt, false, "The hover has no opaque player-observation token.")
	await _mouse_move(point)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	receipt["rendered_hover_waited"] = true
	var finished := _finish_receipt(receipt, true, "")
	_rendered_hover_valid = true
	_rendered_hover_point = point
	_rendered_hover_token = target_token
	_rendered_hover_sequence = int(finished.get("input_sequence_after", -1))
	return finished


## Stage two for generated observation-driven Rally. The caller must first
## hover, render, and rebind this same opaque token at this exact actual pixel.
## No process/render yield or replacement MouseMotion occurs before RMB-down.
func rally_screen_from_rendered_hover(
		point: Vector2, target_token: String
	) -> Dictionary:
	var receipt := _begin_receipt("rally", {
		"screen_point": point,
		"target_token": target_token,
		"rendered_hover_required": true,
	})
	if not _viewport_rect().has_point(point):
		return _finish_receipt(receipt, false,
			"The point is outside the shipped viewport.")
	return await hold_rally(receipt, point, target_token)


## The same Home-key camera recenter advertised by the shipped HUD. This is presentation pacing,
## not a world-state shortcut, and lets an automated player recover when moving bodies leave frame.
func recenter() -> Dictionary:
	var receipt := _begin_receipt("recenter", {})
	# Edge-scroll is ordinary shipped input. A human who presses Home to recover the
	# board also moves the pointer out of the edge band; otherwise the still-edge
	# cursor immediately pans the camera away again and makes Home appear broken.
	await _mouse_move(_viewport_rect().get_center())
	await _send_key(KEY_HOME)
	await _wait_frames(SETTLE_FRAMES)
	return _finish_receipt(receipt, true, "")


## Hold the same shipped Q/E camera action a person uses to change the view yaw.
## A timed hold is intentional: repeated taps make the resulting angle depend on
## how many render frames happen to land between synthetic packets.  Like Home
## and wheel zoom, this changes presentation only and never invokes world
## authority.
func rotate_camera(direction: String, hold_seconds := 0.45) -> Dictionary:
	var normalized_direction := direction.strip_edges().to_lower()
	var keycode := KEY_Q if normalized_direction == "left" else KEY_E
	var receipt := _begin_receipt("rotate_camera", {
		"direction": normalized_direction,
		"keycode": keycode,
		"hold_seconds": maxf(0.05, hold_seconds),
	})
	if normalized_direction not in ["left", "right"]:
		return _finish_receipt(
			receipt, false, "Camera rotation direction must be left or right.")
	await _mouse_move(_viewport_rect().get_center())
	await _send_key_state(keycode, true)
	await get_tree().create_timer(maxf(0.05, hold_seconds)).timeout
	await _send_key_state(keycode, false)
	await _wait_frames(SETTLE_FRAMES)
	return _finish_receipt(receipt, true, "")


## Pointer-only presentation hygiene after a click. This is the exact mouse
## motion a person can make to leave the shipped edge-scroll band; it has no
## world target and invokes no semantic gameplay authority.
func park_pointer() -> Dictionary:
	var viewport_rect := _viewport_rect()
	var from_screen := _last_pointer
	var to_screen := viewport_rect.get_center()
	var receipt := _begin_receipt("park_pointer", {
		"from_screen": [from_screen.x, from_screen.y],
		"to_screen": [to_screen.x, to_screen.y],
		"input_issued": false,
	})
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0:
		return _finish_receipt(
			receipt, false, "The shipped viewport has no safe pointer area.")
	await _mouse_move(to_screen)
	receipt["input_issued"] = true
	return _finish_receipt(receipt, true, "")


## The same advertised H-key action a person uses to collapse the large instruction card.
## This changes presentation only; it does not read or mutate puzzle state.
func toggle_instructions() -> Dictionary:
	var receipt := _begin_receipt("toggle_instructions", {})
	await _send_key(KEY_H)
	await _wait_frames(SETTLE_FRAMES)
	return _finish_receipt(receipt, true, "")


## Mouse-wheel framing is a shipped player action. Multi-level boards deliberately require the
## zoomed-out structural view before an overhead deck becomes a selectable destination.
func zoom_out(notches := 6) -> Dictionary:
	var receipt := _begin_receipt("zoom_out", {"notches": maxi(1, notches)})
	var center := _viewport_rect().get_center()
	await _mouse_move(center)
	for _notch in range(maxi(1, notches)):
		await _mouse_button(center, MOUSE_BUTTON_WHEEL_DOWN, true)
		await _mouse_button(center, MOUSE_BUTTON_WHEEL_DOWN, false)
	await _wait_frames(SETTLE_FRAMES)
	return _finish_receipt(receipt, true, "")


## Explicit atomic-Rally boundary used by both world- and screen-addressed
## entry points. The only implementation is the shipped held-RMB gesture.
func hold_rally(
		receipt: Dictionary, point: Vector2, rendered_hover_token := ""
	) -> Dictionary:
	var event_count_before := _event_count()
	# A held Rally means the whole party presented in the HUD. Do not mirror the
	# production controller's transient availability filtering here: that would let
	# a busy member disappear from the test's stated intent and turn a partial Rally
	# into a false positive.
	var intended_members := _presented_party_ids()
	if intended_members.is_empty():
		receipt["intended_members"] = []
		receipt["member_results"] = {}
		receipt["atomic_group"] = true
		return _finish_receipt(
			receipt, false, "No visible party portraits are available for Rally.")
	var hold_started_msec := 0
	if rendered_hover_token != "":
		hold_started_msec = Time.get_ticks_msec() # @wallclock_input_only
		if not _dispatch_rally_down_from_rendered_hover(
				point, rendered_hover_token):
			return _finish_receipt(receipt, false,
				"The rendered hover no longer matches the rebound visible target.")
		await _wait_frames(1)
	else:
		await _mouse_move(point)
		hold_started_msec = Time.get_ticks_msec() # @wallclock_input_only
		await _mouse_button(point, MOUSE_BUTTON_RIGHT, true)
	var release_gate := await _wait_for_visible_rally_release(hold_started_msec)
	receipt["rally_hold_elapsed_seconds"] = float(release_gate.get(
		"elapsed_seconds", 0.0))
	receipt["rally_hold_release_basis"] = str(release_gate.get("basis", ""))
	receipt["rally_hold_ready_visible"] = bool(release_gate.get(
		"ready_visible", false))
	receipt["rally_hold_blocked_visible"] = bool(release_gate.get(
		"blocked_visible", false))
	receipt["rally_hold_presentation"] = (release_gate.get(
		"presentation", {}) as Dictionary).duplicate(true)
	# Input.parse_input_event dispatches the release synchronously. Capture the
	# production indicator at that boundary; waiting several rendered frames first
	# made a legitimate red refusal disappear during slow capture frames and turned
	# visible feedback into a false "hidden" infrastructure failure.
	await _release_rally(point)
	await _wait_frames(SETTLE_FRAMES)
	var rally_events := _new_event_kinds(event_count_before).count("rally_members")
	receipt["rally_event_count"] = rally_events
	receipt["production_event_count"] = rally_events
	receipt["intended_members"] = intended_members
	var emitted_members := _rally_event_members(event_count_before)
	receipt["member_destinations"] = _rally_event_member_destinations(
		event_count_before)
	var member_results := {}
	for member_id in intended_members:
		member_results[member_id] = "accepted" if emitted_members.has(member_id) else "refused"
	receipt["member_results"] = member_results
	var exact_members := emitted_members.size() == intended_members.size()
	for member_id in intended_members:
		exact_members = exact_members and emitted_members.has(member_id)
	# A whole-command refusal is atomic too: no Rally event and no member accepted.
	# Multiple events or a one-event roster mismatch are the non-atomic cases.
	receipt["atomic_group"] = (rally_events == 1 and exact_members) \
		or (rally_events == 0 and emitted_members.is_empty())
	if rally_events != 1:
		return _finish_receipt(receipt, false,
			"One held Rally gesture produced %d rally events." % rally_events)
	if not exact_members:
		return _finish_receipt(receipt, false,
			"One held Rally did not include the complete visible party (intended %s, emitted %s)." \
				% [str(intended_members), str(emitted_members)])
	return _finish_receipt(receipt, true, "")


## Synchronous commit edge for a rendered-hover Rally. Keep this helper free of
## awaits: after the playthrough takes its fresh public observation, RMB-down is
## the very next shipped input packet.
func _dispatch_rally_down_from_rendered_hover(
		point: Vector2, target_token: String
	) -> bool:
	if not _rendered_hover_matches(point, target_token):
		return false
	_clear_rendered_hover()
	_dispatch_mouse_button(point, MOUSE_BUTTON_RIGHT, true)
	return true


func _wait_for_visible_rally_release(hold_started_msec: int) -> Dictionary:
	var presentation: Dictionary = {}
	while true:
		# Let the production SelectionController update the public overlay from the
		# same held input. This is the on-screen contract a human follows.
		await _wait_frames(1)
		presentation = _visible_rally_hold_presentation()
		var elapsed := maxf(0.0,
			float(Time.get_ticks_msec() - hold_started_msec) / 1000.0) # @wallclock_input_only
		if rally_release_gate_open(presentation, elapsed):
			var ready_visible := rally_ready_cue_visible(presentation)
			var blocked_visible := rally_blocked_cue_visible(presentation)
			if (ready_visible or blocked_visible) \
					and DisplayServer.get_name() != "headless":
				# Public state becomes READY during process; do not release until that
				# exact READY/BLOCKED state has survived through an actually presented frame.
				await RenderingServer.frame_post_draw
				presentation = _visible_rally_hold_presentation()
				ready_visible = rally_ready_cue_visible(presentation)
				blocked_visible = rally_blocked_cue_visible(presentation)
				if not ready_visible and not blocked_visible:
					continue
			return {
				"basis": "visible_release_cue" if ready_visible \
					else ("visible_blocked_cue" if blocked_visible \
						else "conservative_max_fallback"),
				"ready_visible": ready_visible,
				"blocked_visible": blocked_visible,
				"elapsed_seconds": elapsed,
				"presentation": presentation.duplicate(true),
			}
	# GDScript does not treat `while true` as exhaustive for typed returns.
	return {}


static func rally_ready_cue_visible(presentation: Dictionary) -> bool:
	return bool(presentation.get("visible", false)) \
		and str(presentation.get("state", "")).strip_edges().to_lower() == "ready" \
		and str(presentation.get("text", "")).strip_edges().to_upper() \
			== "RELEASE: RALLY ALL"


static func rally_blocked_cue_visible(presentation: Dictionary) -> bool:
	return bool(presentation.get("visible", false)) \
		and str(presentation.get("state", "")).strip_edges().to_lower() == "blocked" \
		and not str(presentation.get("text", "")).strip_edges().is_empty()


static func rally_release_gate_open(presentation: Dictionary,
		elapsed_seconds: float) -> bool:
	return rally_ready_cue_visible(presentation) \
		or rally_blocked_cue_visible(presentation) \
		or elapsed_seconds >= RALLY_HOLD_FALLBACK_SECONDS


func _visible_rally_hold_presentation() -> Dictionary:
	if get_tree() == null:
		return {}
	for presenter_v in get_tree().get_nodes_in_group(
			&"player_observation_overlay_presenters"):
		if not is_instance_valid(presenter_v) \
				or not presenter_v.has_method("get_player_presentation"):
			continue
		var presentation_v: Variant = presenter_v.call("get_player_presentation")
		if presentation_v is Dictionary \
				and bool((presentation_v as Dictionary).get("visible", false)):
			return (presentation_v as Dictionary).duplicate(true)
	return {}

func interact(character_id: String, target: Node3D) -> Dictionary:
	var target_name := str(target.name) if target != null and is_instance_valid(target) else ""
	var receipt := _begin_receipt("interact", {
		"character_id": character_id,
		"target_node": target_name,
	})
	if target == null or not is_instance_valid(target):
		return _finish_receipt(receipt, false, "The visible interaction target is unavailable.")
	var selection := await select_single(character_id)
	if not bool(selection.get("accepted", false)):
		return _finish_receipt(receipt, false, str(selection.get("reason", "Selection refused.")))
	var point := _screen_point(target.global_position)
	if not point.is_finite():
		return _finish_receipt(receipt, false, "Interaction target is not visible through the current player camera.")
	await _mouse_click(point, MOUSE_BUTTON_RIGHT)
	await _wait_frames(SETTLE_FRAMES)
	var player := _active_player()
	var accepted := _interaction_command_seen_since(
		int(receipt.get("event_count_before", 0)))
	var reason := "" if accepted else _visible_refusal_text(player)
	if reason == "":
		reason = "The shipped interaction surface did not accept the click."
	return _finish_receipt(receipt, accepted, "" if accepted else reason)


func interact_screen(character_id: String, point: Vector2) -> Dictionary:
	var receipt := _begin_receipt("interact", {
		"character_id": character_id,
		"screen_point": point,
	})
	if not _viewport_rect().has_point(point):
		return _finish_receipt(receipt, false, "The point is outside the shipped viewport.")
	var selection := await select_single(character_id)
	if not bool(selection.get("accepted", false)):
		return _finish_receipt(receipt, false, str(selection.get("reason", "Selection refused.")))
	await _mouse_click(point, MOUSE_BUTTON_RIGHT)
	await _wait_frames(SETTLE_FRAMES)
	var player := _active_player()
	var accepted := _interaction_command_seen_since(
		int(receipt.get("event_count_before", 0)))
	var reason := "" if accepted else _visible_refusal_text(player)
	if reason == "":
		reason = "The shipped interaction surface did not accept the click."
	return _finish_receipt(receipt, accepted, "" if accepted else reason)


## Click a visible interaction while preserving the player's current group selection. Group
## consoles and party shelters intentionally consume that selection; collapsing to a singleton
## before the click changes the shipped action and makes an honest group interaction impossible.
func interact_selected_screen(required_character_id: String, point: Vector2) -> Dictionary:
	var receipt := _begin_receipt("interact", {
		"character_id": required_character_id,
		"screen_point": point,
		"preserve_group_selection": true,
	})
	if not _viewport_rect().has_point(point):
		return _finish_receipt(receipt, false, "The point is outside the shipped viewport.")
	var selected := _selected_ids()
	if not selected.has(required_character_id):
		return _finish_receipt(receipt, false,
			"The required portrait is not part of the visible group selection.")
	await _mouse_click(point, MOUSE_BUTTON_RIGHT)
	await _wait_frames(SETTLE_FRAMES)
	var player := _active_player()
	var accepted := _interaction_command_seen_since(
		int(receipt.get("event_count_before", 0)))
	receipt["selection_after"] = _selected_ids()
	var reason := "" if accepted else _visible_refusal_text(player)
	if reason == "":
		reason = "The shipped group interaction surface did not accept the click."
	return _finish_receipt(receipt, accepted, "" if accepted else reason)


## Observation-atomic selected interaction. Selection is already established by
## shipped portrait input. This method consumes only a rendered hover bearing
## the same opaque observation token and emits RMB down/up without another
## MouseMotion or frame boundary before the down edge.
func interact_selected_screen_from_rendered_hover(
		required_character_id: String,
		point: Vector2,
		target_token: String
	) -> Dictionary:
	var receipt := _begin_receipt("interact", {
		"character_id": required_character_id,
		"screen_point": point,
		"target_token": target_token,
		"preserve_group_selection": true,
		"rendered_hover_required": true,
	})
	if not _viewport_rect().has_point(point):
		return _finish_receipt(receipt, false,
			"The point is outside the shipped viewport.")
	var selected := _selected_ids()
	if not selected.has(required_character_id):
		return _finish_receipt(receipt, false,
			"The required portrait is not part of the visible group selection.")
	if not _dispatch_quick_right_click_from_rendered_hover(point, target_token):
		return _finish_receipt(receipt, false,
			"The rendered hover no longer matches the rebound visible target.")
	await _wait_frames(1)
	await _wait_frames(SETTLE_FRAMES)
	var player := _active_player()
	var accepted := _interaction_command_seen_since(
		int(receipt.get("event_count_before", 0)))
	var reason := "" if accepted else _visible_refusal_text(player)
	if reason == "":
		reason = "The shipped group interaction surface did not accept the click."
	return _finish_receipt(receipt, accepted, "" if accepted else reason)


## Synchronous quick-click commit for a rendered hover. The press and release
## remain one human quick-click packet; importantly, the press is issued with no
## intervening frame after the caller's exact-token public rebind.
func _dispatch_quick_right_click_from_rendered_hover(
		point: Vector2, target_token: String
	) -> bool:
	if not _rendered_hover_matches(point, target_token):
		return false
	_clear_rendered_hover()
	_dispatch_mouse_button(point, MOUSE_BUTTON_RIGHT, true)
	_dispatch_mouse_button(point, MOUSE_BUTTON_RIGHT, false)
	return true


## Complete the receipt for a selected-party interaction after its visible, routed consequence has
## settled. The initial pointer click may only enqueue Aster's walk; the Basin console's authoritative
## Rally is emitted later, when the interaction controller reaches the console. Reading that later
## event is evidence bookkeeping only: it never advances, invokes, or mutates gameplay authority.
func finalize_group_rally_receipt(
		receipt: Dictionary,
		intended_members_value: Array
	) -> Dictionary:
	var start_index := int(receipt.get("event_count_before", 0))
	receipt["event_count_after"] = _event_count()
	receipt["new_event_kinds"] = _new_event_kinds(start_index)
	_annotate_group_rally_effect(receipt, intended_members_value)
	var rally_events := int(receipt.get("rally_event_count", 0))
	var exact_group := bool(receipt.get("atomic_group", false))
	if rally_events == 1 and exact_group:
		receipt["accepted"] = true
		receipt["reason"] = ""
	else:
		receipt["accepted"] = false
		if str(receipt.get("reason", "")) == "":
			receipt["reason"] = (
				"The selected-party interaction did not emit its announced whole-party movement."
				if rally_events == 0 else
				"The selected-party interaction emitted a non-atomic party movement."
			)
	_replace_receipt_snapshot(receipt)
	return receipt


## Finalize an ordinary click-to-walk interaction from the later visible semantic result. The
## pointer receipt is returned immediately so the persona can keep observing; reaching and triggering
## the source can take seconds. This method only refreshes evidence from authority that already ran.
func finalize_interaction_receipt(
		receipt: Dictionary,
		target_presentation: Dictionary,
		result_reason := "",
		expected_target_token := "",
		baseline_presentation_serial := 0
	) -> Dictionary:
	var start_index := int(receipt.get("event_count_before", 0))
	receipt["event_count_after"] = _event_count()
	receipt["new_event_kinds"] = _new_event_kinds(start_index)
	var presentation := {
		"source_token": str(target_presentation.get("source_token", "")),
		"presentation_serial": int(target_presentation.get("presentation_serial", 0)),
		"result": str(target_presentation.get("result", "")),
		"visible": bool(target_presentation.get("visible", false)),
	}
	var initial_command_accepted := bool(receipt.get("accepted", false))
	if receipt.has("initial_command_accepted"):
		initial_command_accepted = bool(receipt.get(
			"initial_command_accepted", initial_command_accepted))
	# Physics picking and a routed walk-to-use can outlive the two-frame pointer
	# probe above. The probe remains useful diagnostics, but it is not authority
	# over the later result: a real issued gesture followed by a newer, visible,
	# exact-target success is the authoritative acceptance receipt. This also
	# covers fast-path shelters which legitimately emit no party_rest event.
	var accepted_from_target_result := bool(receipt.get("input_issued", false)) \
		and expected_target_token != "" \
		and str(presentation["source_token"]) == expected_target_token \
		and bool(presentation["visible"]) \
		and str(presentation["result"]) == "success" \
		and int(presentation["presentation_serial"]) \
			> baseline_presentation_serial
	receipt["target_result_attestation"] = presentation
	receipt["expected_target_token"] = expected_target_token
	receipt["target_result_baseline_serial"] = baseline_presentation_serial
	receipt["initial_command_accepted"] = initial_command_accepted
	receipt["accepted"] = accepted_from_target_result
	receipt["reason"] = "" if accepted_from_target_result else result_reason
	if not accepted_from_target_result and str(receipt["reason"]) == "":
		receipt["reason"] = "The exact target did not render a successful interaction receipt."
	_replace_receipt_snapshot(receipt)
	return receipt

func push(character_id: String, object_id: String, target_cell: Vector2i) -> Dictionary:
	var receipt := _begin_receipt("push", {
		"character_id": character_id,
		"object_id": object_id,
		"target_cell": target_cell,
	})
	var selection := await select_single(character_id)
	if not bool(selection.get("accepted", false)):
		return _finish_receipt(receipt, false, str(selection.get("reason", "Selection refused.")))
	var push_target: Node3D = null
	if _host != null:
		for candidate in _host.get_tree().get_nodes_in_group("push_targets"):
			if candidate is Node3D and str(candidate.get("obj_id")) == object_id:
				push_target = candidate as Node3D
				break
	if push_target == null:
		return _finish_receipt(receipt, false, "No visible PushTarget exists for %s." % object_id)
	var source_point := _screen_point(push_target.global_position)
	if not source_point.is_finite():
		return _finish_receipt(receipt, false, "The pushable object is not visible through the current player camera.")
	await _mouse_click(source_point, MOUSE_BUTTON_LEFT)
	await _wait_frames(SETTLE_FRAMES)
	var player := _active_player()
	if player == null or not bool(player.call("is_push_queued")):
		return _finish_receipt(receipt, false, "The shipped crate click did not enter push planning.")
	var gs = _game_state()
	if gs == null or gs.grid == null:
		return _finish_receipt(receipt, false, "Push planning has no live navigation grid.")
	var data_target: Vector3 = gs.grid.grid_to_world(target_cell, gs.get_character_level(character_id))
	var destination_point := _screen_point(_render_position(data_target))
	if not destination_point.is_finite():
		return _finish_receipt(receipt, false, "The push destination is not visible through the current player camera.")
	await _mouse_click(destination_point, MOUSE_BUTTON_RIGHT, true)
	await _wait_frames(SETTLE_FRAMES)
	var accepted: bool = gs.is_pushing(character_id) \
		or _event_count() > int(receipt.get("event_count_before", 0))
	return _finish_receipt(receipt, accepted,
		"" if accepted else _visible_refusal_text(player))
func set_party_running(desired: bool) -> Dictionary:
	var receipt := _begin_receipt("set_party_running", {"desired": desired})
	receipt["input_issued"] = false
	var selection := await select_party()
	if not bool(selection.get("accepted", false)):
		return _finish_receipt(receipt, false, str(selection.get("reason", "Party selection refused.")))
	var before_label := _visible_run_label()
	var desired_label := "RUN" if desired else "WALK"
	receipt["visible_label_before"] = before_label
	if before_label != desired_label:
		receipt["input_issued"] = true
		await _send_key(KEY_R)
	await _wait_frames(SETTLE_FRAMES)
	var after_label := _visible_run_label()
	receipt["visible_label_after"] = after_label
	var accepted := after_label == desired_label
	return _finish_receipt(receipt, accepted,
		"" if accepted else "The shipped HUD did not present the requested group run state.")

func set_running(character_id: String, desired: bool) -> Dictionary:
	var receipt := _begin_receipt("set_running", {
		"character_id": character_id,
		"desired": desired,
	})
	var selection := await select_single(character_id)
	if not bool(selection.get("accepted", false)):
		return _finish_receipt(receipt, false, str(selection.get("reason", "Selection refused.")))
	var gs = _game_state()
	var before := bool(gs.is_running(character_id)) if gs != null and gs.characters.has(character_id) else false
	if before != desired:
		await _send_key(KEY_R)
	var after := bool(gs.is_running(character_id)) if gs != null and gs.characters.has(character_id) else false
	return _finish_receipt(receipt, after == desired,
		"" if after == desired else "The shipped run toggle did not reach the requested state.")

func stop(character_id: String) -> Dictionary:
	var gs = _game_state()
	if gs == null or not gs.characters.has(character_id):
		var missing := _begin_receipt("stop", {"character_id": character_id})
		return _finish_receipt(missing, false, "Character is unavailable.")
	# A player stops/replans a body by issuing an ordinary command at its feet.
	return await move(character_id, gs.get_position(character_id))

func click_screen(point: Vector2, button := MOUSE_BUTTON_LEFT,
		shift := false, double_click := false) -> Dictionary:
	var receipt := _begin_receipt("screen_click", {
		"point": point,
		"button": button,
		"shift": shift,
		"double_click": double_click,
	})
	if not _viewport_rect().has_point(point):
		return _finish_receipt(receipt, false, "The point is outside the shipped viewport.")
	await _mouse_click(point, button, shift, double_click)
	return _finish_receipt(receipt, true, "")

func drag_screen(from: Vector2, to: Vector2, button := MOUSE_BUTTON_LEFT) -> Dictionary:
	var receipt := _begin_receipt("screen_drag", {"from": from, "to": to, "button": button})
	if not _viewport_rect().has_point(from) or not _viewport_rect().has_point(to):
		return _finish_receipt(receipt, false, "The drag leaves the shipped viewport.")
	await _mouse_move(from)
	await _mouse_button(from, button, true)
	var midpoint := (from + to) * 0.5
	await _mouse_move(midpoint, _button_mask(button))
	await _mouse_move(to, _button_mask(button))
	await _mouse_button(to, button, false)
	return _finish_receipt(receipt, true, "")

func cancel_rally(from: Vector2, to: Vector2) -> Dictionary:
	var receipt := _begin_receipt("cancel_rally", {"from": from, "to": to})
	if not _viewport_rect().has_point(from) or not _viewport_rect().has_point(to):
		return _finish_receipt(receipt, false, "The gesture leaves the shipped viewport.")
	await _mouse_move(from)
	await _mouse_button(from, MOUSE_BUTTON_RIGHT, true)
	await _mouse_move(to, MOUSE_BUTTON_MASK_RIGHT)
	await _mouse_button(to, MOUSE_BUTTON_RIGHT, false)
	return _finish_receipt(receipt, true, "")

func press_key(keycode: int, repeat_count := 1) -> Dictionary:
	var receipt := _begin_receipt("key", {"keycode": keycode, "repeat_count": repeat_count})
	for _index in range(maxi(1, repeat_count)):
		await _send_key(keycode)
	return _finish_receipt(receipt, true, "")

func unavailable_action(action_name: String, reason: String) -> Dictionary:
	var receipt := _begin_receipt("unavailable", {"requested_action": action_name})
	return _finish_receipt(receipt, false, reason)

func _begin_receipt(kind: String, details: Dictionary) -> Dictionary:
	var receipt := details.duplicate(true)
	receipt["id"] = _next_action_id
	_next_action_id += 1
	receipt["kind"] = kind
	receipt["player_reproducible"] = true
	receipt["selection_before"] = _selected_ids()
	receipt["event_count_before"] = _event_count()
	receipt["input_sequence_before"] = _next_input_sequence - 1
	return receipt

func _finish_from_live_command(receipt: Dictionary, character_id: String) -> Dictionary:
	var gs = _game_state()
	var player := _character_node(character_id)
	var accepted: bool = gs != null and gs.characters.has(character_id) \
		and (gs.is_moving(character_id) or gs.is_external_traversal_active(character_id) \
			or _event_count() > int(receipt.get("event_count_before", 0)))
	var refusal := _visible_refusal_text(player)
	receipt["feedback"] = {
		"kind": "movement",
		"accepted": accepted,
		"refusal": refusal,
		"moving": gs != null and gs.characters.has(character_id) and gs.is_moving(character_id),
	}
	return _finish_receipt(receipt, accepted, "" if accepted else refusal)

func _finish_receipt(receipt: Dictionary, accepted: bool, reason: String) -> Dictionary:
	receipt["accepted"] = accepted
	receipt["reason"] = reason
	receipt["selection_after"] = _selected_ids()
	receipt["event_count_after"] = _event_count()
	receipt["new_event_kinds"] = _new_event_kinds(int(receipt.get("event_count_before", 0)))
	if str(receipt.get("kind", "")) in PRESENTATION_ONLY_RECEIPT_KINDS:
		# H/Home/held-QE/wheel/pointer hygiene changes only the rendered input surface.
		# Scheduler work that happens during their settle frames is background
		# activity, not production authority caused by these gestures.
		receipt["new_event_kinds"] = []
		receipt["production_event_count"] = 0
		receipt["production_event_kinds"] = []
	receipt["input_sequence_after"] = _next_input_sequence - 1
	receipt["input_events"] = _input_events_since(int(
		receipt.get("input_sequence_before", 0)))
	receipt["input_event_count"] = (receipt["input_events"] as Array).size()
	receipt["input_issued"] = int(receipt["input_event_count"]) > 0
	_receipts.append(receipt.duplicate(true))
	return receipt


func _replace_receipt_snapshot(receipt: Dictionary) -> void:
	# `_finish_receipt` stores an early snapshot for driver diagnostics. Keep that public history in
	# lockstep with the returned delayed receipt without creating a second action.
	for index in range(_receipts.size()):
		if str((_receipts[index] as Dictionary).get("id", "")) \
				== str(receipt.get("id", "")):
			_receipts[index] = receipt.duplicate(true)
			break

func _send_key(keycode: int, ctrl := false, shift := false) -> void:
	for pressed in [true, false]:
		await _send_key_state(keycode, pressed, ctrl, shift)


func _send_key_state(
		keycode: int, pressed: bool, ctrl := false, shift := false
	) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode as Key
	event.physical_keycode = keycode as Key
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.pressed = pressed
	Input.parse_input_event(event)
	_record_input_event("key", {
		"key": _input_key_name(keycode),
		"pressed": pressed,
		"modifiers": {
			"ctrl": ctrl,
			"shift": shift,
			"alt": false,
			"meta": false,
		},
	})
	if pressed:
		_held_keys[keycode] = {"ctrl": ctrl, "shift": shift}
	else:
		_held_keys.erase(keycode)
	await _wait_frames(1)

func _mouse_click(point: Vector2, button: int, shift := false, double_click := false) -> void:
	# Give hover/physics picking one presented frame to settle at the chosen pixel,
	# then deliver a human quick-click as one app-local packet. Yielding a rendered
	# frame between RMB down and up lets a slow generated scene consume more than
	# the shipped Rally threshold and reclassify this ordinary interaction as a
	# held whole-party command. Explicit Rally continues to use `_mouse_button`
	# plus its visible hold/release gate and is intentionally unaffected.
	await _mouse_move(point)
	_dispatch_mouse_button(point, button, true, shift, double_click)
	_dispatch_mouse_button(point, button, false, shift, false)
	await _wait_frames(1)

func _mouse_move(point: Vector2, button_mask := 0) -> void:
	_clear_rendered_hover()
	_last_pointer = point
	# Feed the same viewport-local event a player produces without changing the
	# workstation's hardware cursor. Windowed automation must remain confined to
	# the game process; an OS cursor-warp call would leak the test onto the user's desktop.
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.button_mask = button_mask
	Input.parse_input_event(motion)
	_record_input_event("pointer_move", {
		"button_mask": button_mask,
		# Receipt the actual viewport-local MouseMotion payload. This lets the
		# validator prove pointer parking reached the safe center instead of merely
		# trusting the caller-authored `to_screen` description.
		"position": [point.x, point.y],
	})
	await _wait_frames(1)


func _rendered_hover_matches(point: Vector2, target_token: String) -> bool:
	return _rendered_hover_valid \
		and target_token != "" \
		and _rendered_hover_token == target_token \
		and _rendered_hover_point.is_equal_approx(point) \
		and _rendered_hover_sequence == _next_input_sequence - 1


func _clear_rendered_hover() -> void:
	_rendered_hover_valid = false
	_rendered_hover_point = Vector2.INF
	_rendered_hover_token = ""
	_rendered_hover_sequence = -1

func _mouse_button(point: Vector2, button: int, pressed: bool,
		shift := false, double_click := false) -> void:
	_dispatch_mouse_button(point, button, pressed, shift, double_click)
	await _wait_frames(1)


func _dispatch_mouse_button(point: Vector2, button: int, pressed: bool,
		shift := false, double_click := false) -> void:
	_last_pointer = point
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button as MouseButton
	event.button_mask = _button_mask(button) if pressed else 0
	event.shift_pressed = shift
	event.double_click = double_click
	event.pressed = pressed
	Input.parse_input_event(event)
	_record_input_event("pointer_button", {
		"button": button,
		"pressed": pressed,
		"shift": shift,
		"double_click": double_click,
		"button_mask": _button_mask(button) if pressed else 0,
		# Receipt the exact viewport-local MouseButton payload. Describing only
		# which button changed cannot prove that the shipped click was issued at
		# the revalidated visible target rather than at another screen point.
		"position": [point.x, point.y],
	})
	if pressed:
		_held_mouse_buttons[button] = true
	else:
		_held_mouse_buttons.erase(button)


func _release_rally(point: Vector2) -> void:
	_last_pointer = point
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_RIGHT
	event.button_mask = 0
	event.pressed = false
	Input.parse_input_event(event)
	_record_input_event("pointer_button", {
		"button": MOUSE_BUTTON_RIGHT,
		"pressed": false,
		"shift": false,
		"double_click": false,
		"button_mask": 0,
		"position": [point.x, point.y],
	})
	_held_mouse_buttons.erase(MOUSE_BUTTON_RIGHT)
	await _wait_frames(1)


func _record_input_event(kind: String, fields: Dictionary) -> void:
	var record := fields.duplicate(true)
	record["sequence"] = _next_input_sequence
	record["kind"] = kind
	record["issued"] = true
	_next_input_sequence += 1
	_input_events.append(record)


func _input_events_since(sequence: int) -> Array:
	var result: Array = []
	for event_value in _input_events:
		if int((event_value as Dictionary).get("sequence", 0)) > sequence:
			result.append((event_value as Dictionary).duplicate(true))
	return result


func _input_key_name(keycode: int) -> String:
	match keycode:
		KEY_1: return "Digit1"
		KEY_2: return "Digit2"
		KEY_3: return "Digit3"
		KEY_W: return "KeyW"
		KEY_A: return "KeyA"
		KEY_S: return "KeyS"
		KEY_D: return "KeyD"
		KEY_Q: return "KeyQ"
		KEY_E: return "KeyE"
		KEY_F: return "KeyF"
		KEY_H: return "KeyH"
		KEY_R: return "KeyR"
		KEY_HOME: return "Home"
	return OS.get_keycode_string(keycode)

func _button_mask(button: int) -> int:
	match button:
		MOUSE_BUTTON_LEFT:
			return MOUSE_BUTTON_MASK_LEFT
		MOUSE_BUTTON_RIGHT:
			return MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			return MOUSE_BUTTON_MASK_MIDDLE
	return 0

func _screen_point(render_target: Vector3) -> Vector2:
	var camera := _camera()
	if camera == null or camera.is_position_behind(render_target):
		return Vector2(INF, INF)
	if camera.is_inside_tree() and not camera.current:
		camera.make_current()
	var point := camera.unproject_position(render_target)
	return point if _viewport_rect().has_point(point) else Vector2(INF, INF)

func _render_position(data_target: Vector3) -> Vector3:
	var gs = _game_state()
	if gs != null and gs.coord_map != null:
		return gs.coord_map.to_world(data_target)
	return data_target

func _viewport_rect() -> Rect2:
	if _host == null or _host.get_viewport() == null:
		return Rect2(Vector2.ZERO, Vector2(1.0, 1.0))
	return _host.get_viewport().get_visible_rect()

func _camera() -> Camera3D:
	var candidate = _host.get("_camera") if _host != null else null
	if candidate is Camera3D:
		return candidate as Camera3D
	return get_viewport().get_camera_3d() if get_viewport() != null else null

func _game_state():
	return _host.get("_game_state") if _host != null else null

func _active_player() -> Node:
	return _host.get("_player") if _host != null else null

func _character_node(character_id: String) -> Node:
	if _host == null:
		return null
	var characters: Variant = _host.get("_characters")
	if characters is Dictionary:
		return (characters as Dictionary).get(character_id, null)
	var player := _active_player()
	return player if player != null and str(player.get("char_id")) == character_id else null

func _selected_ids() -> Array:
	var hud = _host.get("_hud") if _host != null else null
	return hud.call("get_selected_ids") if hud != null and hud.has_method("get_selected_ids") else []

func _portrait_ids() -> Array:
	var hud = _host.get("_hud") if _host != null else null
	return hud.call("get_portrait_ids") if hud != null and hud.has_method("get_portrait_ids") else []


func _presented_party_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id in _portrait_ids():
		var id := str(raw_id)
		if id != "" and not ids.has(id):
			ids.append(id)
	ids.sort()
	return ids

func _event_count() -> int:
	var gs = _game_state()
	return gs.event_log.size() if gs != null and gs.event_log != null else 0


## Validation-only cursor for mutations that occur after a human-equivalent gesture has returned
## (for example, a Basin rise during a passive wait). Persona policy never receives these records;
## the controller uses them only after the observation interval to prove a rendered causal cue.
func validation_event_cursor() -> int:
	return _event_count()


func validation_events_since(start_index: int) -> Array:
	var result: Array = []
	var gs = _game_state()
	if gs == null or gs.event_log == null:
		return result
	for index in range(maxi(0, start_index), gs.event_log.events.size()):
		var event_v: Variant = gs.event_log.events[index]
		if event_v is Dictionary:
			result.append((event_v as Dictionary).duplicate(true))
	return result

func _new_event_kinds(start_index: int) -> Array[String]:
	var kinds: Array[String] = []
	var gs = _game_state()
	if gs == null or gs.event_log == null:
		return kinds
	for index in range(maxi(0, start_index), gs.event_log.events.size()):
		kinds.append(str((gs.event_log.events[index] as Dictionary).get("kind", "")))
	return kinds


func _interaction_command_seen_since(start_index: int) -> bool:
	# Periodic world-state presentation events can be recorded while a pointer
	# receipt settles. They are not proof that this click was accepted. Require a
	# production locomotion/interaction command so ambient simulation cannot turn
	# a dead click green. Final persona acceptance additionally requires the
	# player-visible semantic consequence after this receipt settles.
	for kind in _new_event_kinds(start_index):
		if INTERACTION_COMMAND_EVENT_KINDS.has(kind):
			return true
	return false


func _rally_event_members(start_index: int) -> Array[String]:
	var members: Array[String] = []
	var gs = _game_state()
	if gs == null or gs.event_log == null:
		return members
	for index in range(maxi(0, start_index), gs.event_log.events.size()):
		var event: Dictionary = gs.event_log.events[index]
		if str(event.get("kind", "")) != "rally_members":
			continue
		for raw_id in (event.get("payload", {}) as Dictionary).get("members", []):
			members.append(str(raw_id))
	return members


## Validation-only copy of the immutable destinations carried by the one
## production Rally event. Persona policy never receives these coordinates;
## the playthrough validator uses them after the gesture to distinguish real
## travel from a member that already occupied its assigned formation endpoint.
func _rally_event_member_destinations(start_index: int) -> Dictionary:
	var result := {}
	var gs = _game_state()
	if gs == null or gs.event_log == null:
		return result
	for index in range(maxi(0, start_index), gs.event_log.events.size()):
		var event: Dictionary = gs.event_log.events[index]
		if str(event.get("kind", "")) != "rally_members":
			continue
		var payload := event.get("payload", {}) as Dictionary
		var members := payload.get("members", []) as Array
		var destinations := payload.get("destinations", []) as Array
		if members.size() != destinations.size():
			return {}
		for member_index in range(members.size()):
			var destination_v: Variant = destinations[member_index]
			if not (destination_v is Array) \
					or (destination_v as Array).size() != 3:
				return {}
			result[str(members[member_index])] = \
				(destination_v as Array).duplicate()
		return result
	return result


## Some shipped interactions (the Basin crossing console) have one atomic Rally as their
## authoritative consequence. Preserve that membership in the interaction receipt so the trace
## cannot call a selected-party interaction successful if production silently omitted a portrait.
func _annotate_group_rally_effect(receipt: Dictionary, intended_members_value: Array) -> void:
	var start_index := int(receipt.get("event_count_before", 0))
	var rally_events := _new_event_kinds(start_index).count("rally_members")
	var intended_members: Array[String] = []
	for raw_id in intended_members_value:
		var id := str(raw_id)
		if id != "" and not intended_members.has(id):
			intended_members.append(id)
	var emitted_members := _rally_event_members(start_index)
	var exact_members := rally_events == 1 \
		and emitted_members.size() == intended_members.size()
	var member_results := {}
	for member_id in intended_members:
		var accepted := emitted_members.has(member_id)
		exact_members = exact_members and accepted
		member_results[member_id] = "accepted" if accepted else "refused"
	receipt["rally_event_count"] = rally_events
	# A zero-event refusal is also atomic: every intended member received the same refused result.
	# Mixed membership or multiple production events are the only decomposed outcomes.
	receipt["atomic_group"] = rally_events == 0 or exact_members
	receipt["intended_members"] = intended_members
	receipt["member_results"] = member_results

func _visible_refusal_text(_player: Node) -> String:
	# v3 feedback comes exclusively from persisted player observations. The
	# input driver reports command acceptance/refusal but never reopens private
	# HUD labels or Rally-indicator state to manufacture a presentation hint.
	return "The shipped interaction command was not observed."


func _visible_run_label() -> String:
	var hud = _host.get("_hud") if _host != null else null
	if hud == null or not hud.has_method("get_player_observation"):
		return ""
	var observation_v: Variant = hud.call("get_player_observation")
	if not (observation_v is Dictionary):
		return ""
	return str((observation_v as Dictionary).get("run_label", "")).strip_edges().to_upper()

func _wait_frames(count: int) -> void:
	for _frame in range(maxi(1, count)):
		await get_tree().process_frame
