class_name SelectionController
extends Node

signal movement_result_requested(payload: Dictionary)

## RTS selection authority (RimWorld / Phylactory-style). LEFT-click picks the party character under
## the cursor; LEFT click-drag draws a marquee and box-selects everyone inside it. The result is pushed
## through the HUD (the single selection source of truth), so the existing character_selection_changed
## fan-out drives set_party + group_move exactly as before. RIGHT-click stays the move/interact command
## (player.gd / the interactables).
##
## Lives in scripts/game/ (shared), instantiated ONCE per scene by tutorial_sequence._ready next to the
## PathRenderManager — so every gameplay/preview/elevator scene gets world-space selection for free. Its
## input handling is here, NOT in a sequence, so the --test-sequence-input-discipline lint never sees it.
##
## Selection is UI pacing: it mutates no game state and emits ZERO EventLog entries (only the resulting
## move/interaction does). Box-select math is camera.unproject_position(world_pos) + rect.has_point() —
## the Phylactory pattern — so headless tests drive headless_pick / headless_box_select display-free.
## The world_pos is the character's RENDER position (get_render_position), so on a warped scene (the
## channels helix, where the data layer stays flat but bodies render on the spiral via coord_map) the
## marquee hugs the VISIBLE bodies. It's identity on flat scenes, so they're unchanged.

const DRAG_THRESHOLD := 10.0       # px — click vs box-drag (Phylactory CLICK_DRAG_PIXEL_THRESHOLD)
const PICK_SCREEN_RADIUS := 56.0   # px — how near a single click must land to pick a character
const RALLY_CANCEL_DISTANCE := 24.0
const RallyHoldIndicatorScript := preload("res://scripts/ui/rally_hold_indicator.gd")
const RALLY_FORMATION_REGION_CONTRACT := "rally_formation_region/v1"
const RALLY_CAPBAGE_CLUSTER_RADIUS := 4.0
const PathRendererScript := preload("res://scripts/game/world/path_renderer.gd")

var _game_state
var _hud
var _scene_root: Node
var _active_player: Node3D
var _camera: Camera3D

var _marquee
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragging := false
var _rally_indicator: RallyHoldIndicator
var _command_pressed := false
var _command_cancelled := false
var _command_hold_matured := false
var _command_press_pos := Vector2.ZERO
var _command_pointer := Vector2.ZERO
var _command_started_msec := 0
var _command_modifiers := {}
var _command_suppressed_until_release := false
## Completed short gestures wait here only until the current input stack has
## unwound. Each entry already owns its release-time Player and immutable
## production pointer record, so a later camera/portrait change cannot retarget
## it. The FIFO also prevents two app-local quick clicks in one frame from
## collapsing into one command.
var _queued_short_commands: Array[Dictionary] = []
var _short_command_cancel_epoch := 0
var _short_command_flush_ticket := 0
var _short_command_flush_scheduled := false
## The visible portrait roster when this held command began. A Rally is one whole-party intent:
## release must either submit this exact roster or visibly refuse it. Never recompute a smaller
## "currently free" subset after the player has already seen RALLY ALL charging.
var _command_rally_members: Array[String] = []
## Typed world target beneath the latest delivered pointer event for this held
## command. Camera follow/smoothing may keep moving after the press; a stationary
## human pointer must keep the same world intent instead of silently re-raycasting
## a different (or empty) pixel every process frame. Only an actual MouseMotion
## refreshes this record.
var _command_rally_target_record: Dictionary = {}
var _rally_previews: Dictionary = {}
var _rally_preview_nodes: Dictionary = {}
var _rally_preview_signature := ""
var _rally_preview_valid := false
var _rally_preview_reason := "NO COMPLETE PARTY ROUTE"
var _last_rally_refusal_reason := ""
## Immutable pointer resolution used by both the command and its visible result
## receipt. Gameplay callbacks may move the camera or presenters during commit;
## presentation must never re-raycast and describe a different destination.
var _last_rally_commit_record: Dictionary = {}

## scene_root is the sequence (it owns _hud + _player, both created after the base _ready), so the HUD
## and active player are resolved lazily from it — same trick player.gd selection deferral uses.
func setup(game_state, scene_root: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game_state = game_state
	_scene_root = scene_root
	_ensure_marquee()
	_ensure_rally_indicator()

func set_active_player(node: Node3D) -> void:
	_active_player = node

func set_camera(cam: Camera3D) -> void:
	_camera = cam

## Tests inject a HUD directly (no scene root); live scenes resolve it lazily from the sequence.
func set_hud(hud) -> void:
	_hud = hud

func _resolve_hud():
	if _hud != null and is_instance_valid(_hud):
		return _hud
	if _scene_root != null:
		_hud = _scene_root.get("_hud")
	return _hud

func _ensure_marquee() -> void:
	if _marquee != null or Engine.is_editor_hint():
		return
	var layer := preload("res://scenes/ui/selection_marquee_layer.tscn").instantiate() as CanvasLayer
	add_child(layer)
	_marquee = layer.get_node("SelectionMarquee")

func _ensure_rally_indicator() -> void:
	if _rally_indicator != null or Engine.is_editor_hint():
		return
	var layer := preload("res://scenes/ui/rally_hold_layer.tscn").instantiate() as CanvasLayer
	add_child(layer)
	_rally_indicator = layer.get_node("RallyHoldIndicator")

# --- Live input ------------------------------------------------------------

## COMMAND is intercepted before GUI/physics picking so a hold cannot accidentally interact on its
## press edge. A short release captures one immutable production command and drains it FIFO after
## this input stack unwinds (or before the next input); a long release commits an explicit-member
## rally. Selection itself is never mutated.
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if is_inside_tree() and get_tree().paused:
		if _command_pressed or _command_suppressed_until_release \
				or not _queued_short_commands.is_empty():
			cancel_command_hold()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _command_pressed or not _queued_short_commands.is_empty():
			_cancel_command_hold()
			get_viewport().set_input_as_handled()
		return
	# Any later input must observe earlier completed releases first. This keeps a
	# same-frame left selection, camera key, or second RMB gesture from changing
	# the actor/party semantics of an already captured command.
	if not _queued_short_commands.is_empty():
		_drain_queued_short_commands()
	if event is InputEventMouseMotion and _command_pressed:
		_update_command_pointer((event as InputEventMouseMotion).position)
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _command_suppressed_until_release:
		if not mb.pressed:
			_command_suppressed_until_release = false
		get_viewport().set_input_as_handled()
		return
	if mb.pressed:
		if _command_belongs_to_gui():
			_command_suppressed_until_release = true
			get_viewport().set_input_as_handled()
			return
		_begin_command_hold(mb)
		get_viewport().set_input_as_handled()
	elif _command_pressed:
		# A release packet terminates the gesture; it is not pointer motion. Keep
		# the typed target captured by press/latest MouseMotion even if the camera
		# continued easing beneath the stationary cursor during the hold.
		_command_pointer = mb.position
		if _command_belongs_to_gui():
			_cancel_command_hold()
		else:
			_finish_command_hold(mb)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	# A "pick the ground target" sequence beat (e.g. peris click-Monos) owns LEFT for that moment —
	# let player.gd emit ground_clicked instead of selecting a character.
	if _defer_to_pick_mode():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.is_action_pressed("select"):
		_pressed = true
		_dragging = false
		_press_pos = mb.position
		# Don't consume on press — it might be a click or a drag; commit on release.
	elif mb.is_action_released("select"):
		if _pressed:
			if _press_pos.distance_to(mb.position) > DRAG_THRESHOLD:
				_commit_box_select(Rect2(_press_pos, mb.position - _press_pos).abs())
			else:
				_commit_pick(mb.position)
			get_viewport().set_input_as_handled()
		_pressed = false
		_dragging = false
		if _marquee != null:
			_marquee.clear_rect()

func _process(_delta: float) -> void:
	var perf_started := PerformanceTrace.begin()
	if is_inside_tree() and get_tree().paused:
		if _command_pressed or _command_suppressed_until_release \
				or not _queued_short_commands.is_empty():
			cancel_command_hold()
		PerformanceTrace.end(&"update", &"selection.process", perf_started, "paused", 0)
		return
	var hold_started := PerformanceTrace.begin()
	_update_command_hold()
	PerformanceTrace.end(&"update", &"selection.command_hold", hold_started, "active" if _command_pressed else "idle", 1)
	if not _pressed or _marquee == null or not is_inside_tree():
		PerformanceTrace.end(&"update", &"selection.process", perf_started, "no_marquee", 0)
		return
	var cur := get_viewport().get_mouse_position()
	if not _dragging and _press_pos.distance_to(cur) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging:
		_marquee.set_rect(Rect2(_press_pos, cur - _press_pos))
	PerformanceTrace.end(&"update", &"selection.process", perf_started, "marquee", 1)

func _begin_command_hold(event: InputEventMouseButton) -> void:
	if _command_pressed:
		_cancel_command_hold()
	# A completed release precedes this new press. Drain it before the new hold
	# begins so a batched down/up/down/held sequence remains short-command then
	# Rally, never Rally followed by a stale deferred click.
	_drain_queued_short_commands()
	_command_pressed = true
	_command_cancelled = false
	_command_hold_matured = false
	_command_press_pos = event.position
	_command_pointer = event.position
	# Input-hold wall time is UI intent sampling only. The resulting rally command is
	# the deterministic/logged boundary; simulation never reads this timestamp.
	_command_started_msec = Time.get_ticks_msec() # @wallclock_input_only
	_command_modifiers = {
		"alt": event.alt_pressed,
		"shift": event.shift_pressed,
		"ctrl": event.ctrl_pressed,
		"meta": event.meta_pressed,
	}
	_command_rally_members = _rally_candidate_ids()
	_command_rally_target_record = _capture_rally_target(_command_pointer)
	_rally_preview_valid = false
	_rally_preview_reason = "NO COMPLETE PARTY ROUTE"
	_last_rally_refusal_reason = ""
	_last_rally_commit_record.clear()
	_ensure_rally_indicator()
	if _rally_indicator != null:
		_rally_indicator.begin(_command_pointer, _command_rally_members.size())

func _update_command_pointer(pointer: Vector2) -> void:
	_command_pointer = pointer
	if _command_cancelled:
		return
	_command_rally_target_record = _capture_rally_target(pointer)
	var elapsed := _command_elapsed()
	if elapsed >= _rally_hold_duration():
		# Crossing the threshold changes this into a movable rally placement. Pointer
		# travel now relocates the formation rather than cancelling the gesture.
		_command_hold_matured = true
	elif _command_drag_would_cancel(_command_press_pos.distance_to(pointer), elapsed):
		_command_cancelled = true

func _update_command_hold() -> void:
	if not _command_pressed:
		return
	# The press/release/motion events are the authority for this gesture's pointer. Polling the
	# viewport here can sample a different OS window (notably a browser beside the native game),
	# turning a stationary human hold into a hidden drag and cancelling it without user input.
	var progress := _command_elapsed() / maxf(_rally_hold_duration(), 0.001)
	if progress >= 1.0 and not _command_cancelled:
		_command_hold_matured = true
	if _command_hold_matured and not _command_cancelled:
		_update_rally_preview_for_record(
			_command_rally_target_record, _command_rally_members)
	else:
		_clear_rally_preview()
	if _rally_indicator != null:
		_rally_indicator.update_hold(
			_command_pointer, progress, _command_cancelled,
			_rally_preview_valid, _rally_preview_reason)

func _finish_command_hold(event: InputEventMouseButton) -> void:
	var elapsed := _command_elapsed()
	var should_rally := not _command_cancelled \
		and (_command_hold_matured or elapsed >= _rally_hold_duration())
	var intended_members := _command_rally_members.duplicate()
	var target_record := _command_rally_target_record.duplicate(true)
	_command_pressed = false
	_command_hold_matured = false
	_command_rally_members.clear()
	_command_rally_target_record.clear()
	_clear_rally_preview()
	if _command_cancelled:
		if _rally_indicator != null:
			_rally_indicator.cancel()
		return
	if should_rally:
		var moved := _commit_rally_record(target_record, intended_members)
		var target_screen_v: Variant = target_record.get(
			"target_screen", event.position)
		var target_screen := event.position
		if target_screen_v is Vector2:
			target_screen = target_screen_v as Vector2
		elif target_screen_v is Array and (target_screen_v as Array).size() == 2:
			target_screen = Vector2(
				float((target_screen_v as Array)[0]),
				float((target_screen_v as Array)[1]))
		_emit_rally_movement_result(
			target_screen, intended_members, moved,
			_last_rally_commit_record.duplicate(true))
		if _rally_indicator != null:
			if moved > 0:
				_rally_indicator.commit(moved)
			elif moved == 0:
				_rally_indicator.reject(_last_rally_refusal_reason)
			else:
				_rally_indicator.cancel()
		return
	if _rally_indicator != null:
		_rally_indicator.cancel()
	_queue_short_command(event.position, _command_modifiers.duplicate(true))


func _emit_rally_movement_result(
		screen_pos: Vector2,
		intended_members: Array[String],
		moved: int,
		commit_record: Dictionary = {}
	) -> void:
	var resolved_record := commit_record.duplicate(true)
	# Compatibility for low-level presentation tests that exercise this method in
	# isolation. The production held-RMB path always supplies the immutable record.
	if resolved_record.is_empty():
		var fallback_anchor_id := _pick_character_id(screen_pos)
		var fallback_target := Vector3.INF
		if fallback_anchor_id != "" and _game_state != null \
				and _game_state.characters.has(fallback_anchor_id):
			fallback_target = _game_state.get_position(fallback_anchor_id)
		else:
			fallback_target = _rally_ground_target(screen_pos)
		resolved_record = {
			"anchor_id": fallback_anchor_id,
			"target": fallback_target,
		}
	var target_v: Variant = resolved_record.get("target", Vector3.INF)
	var target: Vector3 = target_v as Vector3 \
		if target_v is Vector3 else Vector3.INF
	var accepted := moved == intended_members.size() and moved > 0
	var reason := ""
	if not accepted:
		reason = "RALLY REFUSED // no complete visible-party route was accepted."
		if not _last_rally_refusal_reason.is_empty():
			reason = "RALLY REFUSED // %s." % _last_rally_refusal_reason
		if moved > 0:
			reason = "RALLY REFUSED // only %d of %d visible members were accepted." % [
				moved, intended_members.size(),
			]
	var destinations := {}
	if _game_state != null:
		for subject_id in intended_members:
			# A cross-level Rally's ordinary get_destination() is only its current
			# planar/ladder segment. Bind presentation to the final endpoint of the
			# already-accepted route so the visible result cannot later judge arrival
			# against an intermediate connector. An accepted no-op member has no live
			# route; its current position is the exact settled endpoint.
			var destination: Vector3 = _game_state.get_navigation_route_destination(
				subject_id) if _game_state.has_method(
					"get_navigation_route_destination") else (
					_game_state.get_destination(subject_id) \
						if _game_state.has_method("get_destination") else Vector3.INF)
			if accepted and not destination.is_finite() \
					and _game_state.characters.has(subject_id) \
					and (not _game_state.has_method("is_navigation_route_active") \
						or not bool(_game_state.call(
							"is_navigation_route_active", subject_id))):
				destination = _game_state.get_position(subject_id)
			if destination.is_finite():
				destinations[subject_id] = destination
	movement_result_requested.emit({
		"verb": "rally",
		"subject_ids": intended_members.duplicate(),
		"target_screen": [screen_pos.x, screen_pos.y],
		"data_target": target,
		"subject_destinations": destinations,
		"accepted": accepted,
		"reason": reason,
	})

func _cancel_command_hold() -> void:
	_short_command_cancel_epoch += 1
	_short_command_flush_ticket += 1
	_short_command_flush_scheduled = false
	_queued_short_commands.clear()
	_command_pressed = false
	_command_cancelled = true
	_command_hold_matured = false
	_command_suppressed_until_release = false
	_command_rally_members.clear()
	_command_rally_target_record.clear()
	_last_rally_commit_record.clear()
	_clear_rally_preview()
	if _rally_indicator != null:
		_rally_indicator.cancel()

## Public cancellation edge used by touch-mode and scene transitions. It deliberately never replays
## a short command: abandoning a proxy press must not leak a move/interact into the next mode.
func cancel_command_hold() -> void:
	_cancel_command_hold()

func _exit_tree() -> void:
	_cancel_command_hold()

func _command_elapsed() -> float:
	return maxf(0.0, float(Time.get_ticks_msec() - _command_started_msec) / 1000.0) # @wallclock_input_only

func _rally_hold_duration() -> float:
	var settings := GameSettings.resolve(self)
	if settings != null and settings.has_method("get_rally_hold_duration"):
		return clampf(
			float(settings.call("get_rally_hold_duration")),
			GameSettings.RALLY_HOLD_MIN,
			GameSettings.RALLY_HOLD_MAX
		)
	return GameSettings.RALLY_HOLD_DEFAULT

func _command_drag_would_cancel(distance: float, elapsed: float) -> bool:
	return distance > RALLY_CANCEL_DISTANCE and elapsed < _rally_hold_duration()

func _queue_short_command(pointer: Vector2, modifiers: Dictionary) -> void:
	var player := _resolve_active_player()
	if player == null or not player.has_method("capture_short_command") \
			or not player.has_method("submit_captured_short_command"):
		_present_short_command_refusal(
			pointer, player, "COMMAND REFUSED // no active character can act.")
		return
	var command_v: Variant = player.call(
		"capture_short_command", pointer, modifiers.duplicate(true))
	if not (command_v is Dictionary):
		_present_short_command_refusal(
			pointer, player, "COMMAND REFUSED // the visible target could not be resolved.")
		return
	_queued_short_commands.append({
		"epoch": _short_command_cancel_epoch,
		"player": player,
		"command": (command_v as Dictionary).duplicate(true),
		"pointer": pointer,
	})
	_schedule_short_command_flush()


func _schedule_short_command_flush() -> void:
	if _short_command_flush_scheduled:
		return
	_short_command_flush_scheduled = true
	_short_command_flush_ticket += 1
	var ticket := _short_command_flush_ticket
	call_deferred("_flush_queued_short_commands", ticket,
		_short_command_cancel_epoch)


func _flush_queued_short_commands(ticket: int, epoch: int) -> void:
	if ticket != _short_command_flush_ticket \
			or epoch != _short_command_cancel_epoch:
		return
	if not is_inside_tree() or get_tree().paused:
		_cancel_command_hold()
		return
	_drain_queued_short_commands()


func _drain_queued_short_commands() -> void:
	if _queued_short_commands.is_empty():
		_short_command_flush_scheduled = false
		return
	_short_command_flush_scheduled = false
	# Invalidate any older deferred flush before a new gesture can enqueue more.
	_short_command_flush_ticket += 1
	var pending := _queued_short_commands.duplicate(true)
	_queued_short_commands.clear()
	for queued_v in pending:
		var queued := queued_v as Dictionary
		if int(queued.get("epoch", -1)) != _short_command_cancel_epoch:
			continue
		var player_v: Variant = queued.get("player", null)
		var player := player_v as Node if player_v is Node else null
		var pointer_v: Variant = queued.get("pointer", Vector2.ZERO)
		var pointer := pointer_v as Vector2 \
			if pointer_v is Vector2 else Vector2.ZERO
		if player == null or not is_instance_valid(player) \
				or not player.is_inside_tree() \
				or player.get_viewport() != get_viewport() \
				or not player.has_method("submit_captured_short_command"):
			_present_short_command_refusal(
				pointer, player, "COMMAND REFUSED // the acting character is no longer available.")
			continue
		# This is the shipped human command boundary, not an automation shortcut:
		# physical and app-local RMB gestures both enter SelectionController above,
		# receive the same short-vs-Rally classification, and submit the exact
		# release-time production surface/ground record once, in FIFO order.
		var accepted := bool(player.call("submit_captured_short_command",
			(queued.get("command", {}) as Dictionary).duplicate(true)))
		if not accepted:
			# Player's submission contract already emitted its move-refusal signal;
			# add the pointer-local cue without duplicating that host notification.
			_present_short_command_refusal(
				pointer, null, "COMMAND REFUSED // the shown target is no longer available.")


func _present_short_command_refusal(
		pointer: Vector2, player: Node, reason: String
	) -> void:
	if player != null and is_instance_valid(player) \
			and player.has_method("present_move_refusal"):
		player.call("present_move_refusal", reason)
	_ensure_rally_indicator()
	if _rally_indicator != null:
		_rally_indicator.begin(pointer, 0)
		_rally_indicator.reject(reason)

func _command_belongs_to_gui() -> bool:
	if not is_inside_tree():
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	return _control_chain_blocks_command(hovered)

## COMMAND is captured in _input() before normal GUI dispatch. Direct STOP controls (buttons, panels)
## own the click. Decorative children can opt their containing surface in with
## `blocks_world_commands`; do not treat every STOP ancestor as blocking because CanvasLayer UI roots
## may span the viewport and would swallow every world command.
static func _control_chain_blocks_command(hovered: Control) -> bool:
	if hovered == null:
		return false
	if hovered.mouse_filter == Control.MOUSE_FILTER_STOP:
		return true
	var control := hovered
	while control != null:
		if bool(control.get_meta("blocks_world_commands", false)):
			return true
		control = control.get_parent_control()
	return false

func _commit_rally_at_screen(screen_pos: Vector2, intended_members: Array[String]) -> int:
	return _commit_rally_record(
		_capture_rally_target(screen_pos), intended_members)


func _capture_rally_target(screen_pos: Vector2) -> Dictionary:
	var anchor_id := ""
	var target := Vector3.INF
	var kind := "typed_ground"
	var formation_region: Dictionary = {}
	var player := _resolve_active_player()
	var navigation: Dictionary = {}
	if player != null and player.has_method("get_rally_navigation_target"):
		var navigation_v: Variant = player.call(
			"get_rally_navigation_target", screen_pos)
		if navigation_v is Dictionary:
			navigation = (navigation_v as Dictionary).duplicate(true)
	# An exact visible semantic surface outranks the broad screen-radius body
	# anchor heuristic.  The shelter pad often sits within 50 px of a gathered
	# portrait; preferring the nearby body would silently discard the pad's typed
	# formation contract even though the ray actually hit the pad.
	if str(navigation.get("kind", "")) == "formation_region":
		var region_v: Variant = navigation.get("formation_region", {})
		if region_v is Dictionary:
			formation_region = (region_v as Dictionary).duplicate(true)
		kind = "formation_region"
		if _game_state != null and _game_state.has_method(
				"get_rally_formation_region_target"):
			var target_v: Variant = _game_state.call(
				"get_rally_formation_region_target", formation_region)
			if target_v is Vector3:
				target = target_v as Vector3
	else:
		anchor_id = _pick_character_id(screen_pos)
		if anchor_id != "" and _game_state != null \
				and _game_state.characters.has(anchor_id):
			kind = "character_anchor"
			target = _game_state.get_position(anchor_id)
		else:
			var data_position_v: Variant = navigation.get(
				"data_position", Vector3.INF)
			if data_position_v is Vector3:
				target = data_position_v as Vector3
			if not target.is_finite():
				target = _rally_ground_target(screen_pos)
	# A held Rally beside several Capbages is a semantic whole-party hide, not a
	# generic ring formation that happens to conceal only one member.  Publish the
	# plants' exact bodily-inside navigation cells as atomic parking slots.  The
	# ordinary region preflight will refuse the whole gesture if there are fewer
	# valid slots than visible portraits or any member cannot reach its slot.
	if kind == "typed_ground" and anchor_id == "" and target.is_finite():
		var capbage_region := _capbage_rally_formation_region(
			target, _command_rally_members)
		if not capbage_region.is_empty():
			formation_region = capbage_region
			kind = "formation_region"
	# A malformed semantic surface is a visible refusal, never permission to
	# reinterpret the same held pointer as unrelated ground behind it.
	var record := {
		"contract": "rally_pointer_target/v1",
		"kind": kind,
		"anchor_id": anchor_id,
		"target": target,
		# Keep the immutable input receipt JSON-safe like the emitted movement
		# payload, while runtime world authority remains the typed Vector3 above.
		"target_screen": [screen_pos.x, screen_pos.y],
	}
	if kind == "formation_region":
		record["formation_region"] = formation_region.duplicate(true)
	return record


func _capbage_rally_formation_region(
		target: Vector3, intended_members: Array[String]
	) -> Dictionary:
	if _game_state == null or _game_state.grid == null \
			or intended_members.is_empty():
		return {}
	var level := -1
	for member_id in intended_members:
		if not _game_state.characters.has(member_id):
			return {}
		var member_level := int(_game_state.get_character_level(member_id))
		if level < 0:
			level = member_level
		elif member_level != level:
			return {}
	if level < 0:
		return {}
	var slots: Array[Dictionary] = []
	var seen_cells := {}
	for source_v in get_tree().get_nodes_in_group(&"capbage_hide_sources"):
		if not (source_v is Node3D) or not is_instance_valid(source_v) \
				or not source_v.has_method("get_concealment_origin") \
				or not source_v.has_method("conceals"):
			continue
		var origin_v: Variant = source_v.call("get_concealment_origin")
		if not (origin_v is Vector3) or not (origin_v as Vector3).is_finite():
			continue
		var origin := origin_v as Vector3
		if Vector2(origin.x - target.x, origin.z - target.z).length() \
				> RALLY_CAPBAGE_CLUSTER_RADIUS:
			continue
		var cell: Vector2i = _game_state.grid.world_to_grid(origin)
		if seen_cells.has(cell) \
				or not _game_state.grid.is_in_bounds(cell.x, cell.y) \
				or not _game_state.grid.is_walkable(cell.x, cell.y, {}, {}, level):
			continue
		var slot_position: Vector3 = _game_state.grid.grid_to_world(cell, level)
		if not bool(source_v.call("conceals", slot_position)):
			continue
		seen_cells[cell] = true
		slots.append({
			"cell": cell,
			"distance": Vector2(
				slot_position.x - target.x,
				slot_position.z - target.z).length_squared(),
		})
	# A partial cluster must not steal an otherwise valid ground Rally. The
	# semantic hide command activates only when every visible member can receive a
	# distinct bodily-inside slot; once active, its downstream commit is atomic.
	if slots.size() < intended_members.size():
		return {}
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var distance_a := float(a.get("distance", INF))
		var distance_b := float(b.get("distance", INF))
		if not is_equal_approx(distance_a, distance_b):
			return distance_a < distance_b
		var cell_a := a.get("cell", Vector2i.ZERO) as Vector2i
		var cell_b := b.get("cell", Vector2i.ZERO) as Vector2i
		return cell_a.x < cell_b.x if cell_a.y == cell_b.y \
			else cell_a.y < cell_b.y)
	var cells: Array = []
	for slot in slots:
		var cell := slot.get("cell", Vector2i.ZERO) as Vector2i
		cells.append([cell.x, cell.y])
	var approach := slots[0].get("cell", Vector2i.ZERO) as Vector2i
	var revision := int(_game_state.grid.get_path_walkability_revision()) \
		if _game_state.grid.has_method("get_path_walkability_revision") else 0
	return {
		"contract_id": RALLY_FORMATION_REGION_CONTRACT,
		"semantic_id": "capbage_hide_cluster",
		"label": "CAPBAGE // RALLY PARTY TO HIDE",
		"slot_policy": "exact_hide_slots",
		"authored_level": level,
		"graph_revision": revision,
		"approach_cell": [approach.x, approach.y],
		"cells": cells,
	}


func _commit_rally_record(
		target_record: Dictionary,
		intended_members: Array[String]
	) -> int:
	var anchor_id := str(target_record.get("anchor_id", ""))
	var target_v: Variant = target_record.get("target", Vector3.INF)
	var target := target_v as Vector3 \
		if target_v is Vector3 else Vector3.INF
	_last_rally_commit_record = target_record.duplicate(true)
	var region_v: Variant = target_record.get("formation_region", {})
	var formation_region := region_v as Dictionary \
		if region_v is Dictionary else {}
	return _commit_rally_for_members(
		target, anchor_id, intended_members, formation_region)

func _commit_rally(target: Vector3, anchor_id := "") -> int:
	return _commit_rally_for_members(target, anchor_id, _rally_candidate_ids())

func _commit_rally_for_members(
		target: Vector3,
		anchor_id: String,
		intended_members: Array[String],
		formation_region: Dictionary = {}
	) -> int:
	_last_rally_refusal_reason = ""
	if _game_state == null or not target.is_finite() \
			or (formation_region.is_empty() \
				and not _game_state.has_method("command_rally_members")) \
			or (not formation_region.is_empty() \
				and not _game_state.has_method(
					"command_rally_members_to_region")):
		_last_rally_refusal_reason = "NO RALLY TARGET"
		return -1
	var members: Array[String] = intended_members.duplicate()
	if members.is_empty():
		_last_rally_refusal_reason = "NO VISIBLE PARTY"
		return 0
	# Availability is a transaction precondition, not a roster filter. If one portrait that was part
	# of the visible intent becomes held, downed, or traversal-owned before release, submit nothing;
	# the caller turns this zero into the red Rally refusal cue.
	if not _rally_members_available(members):
		_last_rally_refusal_reason = "A PARTY MEMBER IS NOT READY"
		return 0
	if not _rally_members_share_anchor_level(members, anchor_id):
		_last_rally_refusal_reason = "THE PARTY IS ON DIFFERENT LEVELS"
		return -1
	if not formation_region.is_empty():
		if not _game_state.has_method("compute_rally_region_preflight"):
			_last_rally_refusal_reason = "RALLY REGION CHANGED"
			return 0
		var region_preflight_v: Variant = _game_state.call(
			"compute_rally_region_preflight", members, formation_region)
		if not (region_preflight_v is Dictionary) or not bool(
				(region_preflight_v as Dictionary).get("accepted", false)):
			_last_rally_refusal_reason = str(
				(region_preflight_v as Dictionary).get(
					"reason", "RALLY REGION CHANGED")) \
				if region_preflight_v is Dictionary \
				else "RALLY REGION CHANGED"
			return 0
		return int(_game_state.call(
			"command_rally_members_to_region", members, formation_region))
	if _game_state.has_method("compute_rally_preflight"):
		var preflight_v: Variant = _game_state.call(
			"compute_rally_preflight", members, target, anchor_id)
		if preflight_v is Dictionary and not bool(
				(preflight_v as Dictionary).get("accepted", false)):
			_last_rally_refusal_reason = str(
				(preflight_v as Dictionary).get(
					"reason", "NO COMPLETE PARTY ROUTE"))
			return 0
	return int(_game_state.call("command_rally_members", members, target, anchor_id))

func _rally_ground_target(screen_pos: Vector2) -> Vector3:
	var player := _resolve_active_player()
	if player == null:
		return Vector3.INF
	# Consume the same typed floor record used by the Player's hover and ordinary
	# move path. A transformed upper deck is identified by its collider level;
	# flattening the ray to coord_map.y0 here would Rally the party underneath it.
	if player.has_method("get_ground_navigation_target"):
		var ground_target_v: Variant = player.call(
			"get_ground_navigation_target", screen_pos)
		if ground_target_v is Dictionary:
			var data_position_v: Variant = (ground_target_v as Dictionary).get(
				"data_position", null)
			if data_position_v is Vector3 \
					and (data_position_v as Vector3).is_finite():
				return data_position_v as Vector3
		return Vector3.INF
	if not player.has_method("_raycast_ground"):
		return Vector3.INF
	var world_hit = player.call("_raycast_ground", screen_pos)
	if not (world_hit is Vector3) or not (world_hit as Vector3).is_finite():
		return Vector3.INF
	var target: Vector3 = world_hit
	if player.has_method("_ground_hit_to_data"):
		target = player.call("_ground_hit_to_data", target)
	elif _game_state != null and _game_state.coord_map != null:
		target = _game_state.coord_map.to_data(target)
	return target

func _rally_candidate_ids() -> Array[String]:
	var ids: Array[String] = []
	var hud = _resolve_hud()
	if hud == null or not hud.has_method("get_portrait_ids") or _game_state == null:
		return ids
	for raw_id in hud.get_portrait_ids():
		var id := str(raw_id)
		if not _game_state.characters.has(id):
			continue
		ids.append(id)
	return ids

func _rally_members_available(members: Array[String]) -> bool:
	if _game_state == null:
		return false
	var hud = _resolve_hud()
	var locked: Array = hud.get_hold_locked_ids() \
		if hud != null and hud.has_method("get_hold_locked_ids") else []
	for id in members:
		if not _game_state.characters.has(id) or locked.has(id):
			return false
		if _game_state.has_method("can_accept_move_command"):
			if not bool(_game_state.call("can_accept_move_command", id)):
				return false
		elif _game_state.has_method("is_downed") and bool(_game_state.call("is_downed", id)):
			return false
	return true

func _rally_members_share_anchor_level(members: Array[String], anchor_id: String) -> bool:
	if anchor_id == "" or _game_state == null or not _game_state.characters.has(anchor_id):
		return true
	var anchor_level := int(_game_state.get_character_level(anchor_id))
	for id in members:
		if not _game_state.characters.has(id) or int(_game_state.get_character_level(id)) != anchor_level:
			return false
	return true

## Once the hold crosses the configured threshold, replace the ambiguous cursor ring with the same
## destination formation and route computation that release will commit. The signature cache keeps
## stationary holds read-only and cheap instead of pathfinding every frame.
func _update_rally_preview_at_screen(
		screen_pos: Vector2,
		intended_members: Array[String]
	) -> void:
	_update_rally_preview_for_record(
		_capture_rally_target(screen_pos), intended_members)


func _update_rally_preview_for_record(
		target_record: Dictionary,
		intended_members: Array[String]
	) -> void:
	var perf_started := PerformanceTrace.begin()
	var anchor_id := str(target_record.get("anchor_id", ""))
	var target_v: Variant = target_record.get("target", Vector3.INF)
	var target := target_v as Vector3 \
		if target_v is Vector3 else Vector3.INF
	var region_v: Variant = target_record.get("formation_region", {})
	var formation_region := region_v as Dictionary \
		if region_v is Dictionary else {}
	_update_rally_preview_for_members(
		target, anchor_id, intended_members, formation_region)
	PerformanceTrace.end(&"nav", &"selection.rally_target", perf_started, anchor_id, 1)

func _update_rally_preview(target: Vector3, anchor_id := "") -> void:
	_update_rally_preview_for_members(target, anchor_id, _rally_candidate_ids())

func _update_rally_preview_for_members(
		target: Vector3,
		anchor_id: String,
		intended_members: Array[String],
		formation_region: Dictionary = {}
	) -> void:
	var perf_started := PerformanceTrace.begin()
	if _game_state == null \
			or (formation_region.is_empty() \
				and not _game_state.has_method("compute_rally_destinations")) \
			or (not formation_region.is_empty() \
				and not _game_state.has_method(
					"compute_rally_region_preflight")):
		_rally_preview_valid = false
		_rally_preview_reason = "RALLY PREVIEW UNAVAILABLE"
		_clear_rally_preview(false)
		PerformanceTrace.end(&"nav", &"selection.rally_preview", perf_started, "unavailable", 0)
		return
	var members: Array[String] = intended_members.duplicate()
	if not target.is_finite():
		_rally_preview_valid = false
		_rally_preview_reason = "RALLY REGION CHANGED" \
			if not formation_region.is_empty() else "NO RALLY TARGET"
		_clear_rally_preview(false)
		PerformanceTrace.end(&"nav", &"selection.rally_preview", perf_started, "invalid", members.size())
		return
	if members.is_empty():
		_rally_preview_valid = false
		_rally_preview_reason = "NO VISIBLE PARTY"
		_clear_rally_preview(false)
		PerformanceTrace.end(&"nav", &"selection.rally_preview", perf_started, "invalid", members.size())
		return
	if not _rally_members_available(members):
		_rally_preview_valid = false
		_rally_preview_reason = "A PARTY MEMBER IS NOT READY"
		_clear_rally_preview(false)
		PerformanceTrace.end(&"nav", &"selection.rally_preview", perf_started, "unavailable", members.size())
		return
	if not _rally_members_share_anchor_level(members, anchor_id):
		_rally_preview_valid = false
		_rally_preview_reason = "THE PARTY IS ON DIFFERENT LEVELS"
		_clear_rally_preview(false)
		PerformanceTrace.end(&"nav", &"selection.rally_preview", perf_started, "invalid", members.size())
		return
	# On grid scenes the resolved formation cannot change while the pointer stays
	# inside one cell. Key the cache by that causal destination, not raw ray-hit
	# floats; camera/pointer jitter inside a cell used to rerun one A* per member.
	var signature := _rally_preview_target_signature(
		target, anchor_id, members, formation_region)
	if signature == _rally_preview_signature:
		# The cached signature owns both the rendered paths and their authoritative
		# READY/BLOCKED verdict. Preserve that verdict on unchanged process frames;
		# resetting it before this return made a valid stationary hold turn red one
		# frame after its routes were computed even though release accepted them.
		PerformanceTrace.end(&"nav", &"selection.rally_preview", perf_started, "cached", members.size())
		return
	_clear_rally_preview()
	_rally_preview_signature = signature
	var raw_destinations: Variant = []
	var raw_paths: Variant = []
	var authoritative_preflight := false
	if not formation_region.is_empty():
		var region_preflight_v: Variant = _game_state.call(
			"compute_rally_region_preflight", members, formation_region)
		if region_preflight_v is Dictionary:
			var region_preflight := region_preflight_v as Dictionary
			authoritative_preflight = true
			raw_destinations = region_preflight.get("destinations", [])
			raw_paths = region_preflight.get("paths", [])
			_rally_preview_valid = bool(
				region_preflight.get("accepted", false))
			_rally_preview_reason = str(region_preflight.get(
				"reason", "" if _rally_preview_valid \
				else "RALLY REGION CHANGED"))
	elif _game_state.has_method("compute_rally_preflight"):
		var preflight_v: Variant = _game_state.call(
			"compute_rally_preflight", members, target, anchor_id)
		if preflight_v is Dictionary:
			var preflight := preflight_v as Dictionary
			authoritative_preflight = true
			raw_destinations = preflight.get("destinations", [])
			raw_paths = preflight.get("paths", [])
			_rally_preview_valid = bool(preflight.get("accepted", false))
			_rally_preview_reason = str(preflight.get(
				"reason", "" if _rally_preview_valid else "NO COMPLETE PARTY ROUTE"))
	else:
		raw_destinations = _game_state.call(
			"compute_rally_destinations", members, target, anchor_id)
	if not (raw_destinations is Array) or raw_destinations.size() != members.size():
		_rally_preview_valid = false
		_rally_preview_reason = "NO COMPLETE FORMATION"
		_clear_rally_preview(false)
		PerformanceTrace.end(&"nav", &"selection.rally_preview", perf_started, "no_formation", members.size())
		return
	if formation_region.is_empty() \
			and not _game_state.has_method("compute_rally_preflight"):
		_rally_preview_valid = true
		_rally_preview_reason = ""
	if authoritative_preflight and _rally_preview_valid \
			and (not (raw_paths is Array) or raw_paths.size() != members.size()):
		_rally_preview_valid = false
		_rally_preview_reason = "ROUTE PREVIEW CHANGED"
	# Resolve and lock every member BEFORE assigning any formation endpoints. Activating a Player's
	# external preview clears its previous single/group hover, which can touch other party members;
	# doing that cleanup as a first pass prevents a later member from erasing an earlier Rally slot.
	var entries: Array[Dictionary] = []
	for i in range(members.size()):
		var id := members[i]
		var destination: Vector3 = raw_destinations[i]
		var node := _find_character_node(id)
		if node == null:
			_rally_preview_valid = false
			_rally_preview_reason = "%s IS NOT PRESENT" % id.to_upper()
			continue
		var path: Array[Vector3] = []
		if authoritative_preflight and raw_paths is Array and i < raw_paths.size():
			var preflight_path_v: Variant = raw_paths[i]
			if preflight_path_v is Array:
				for point in preflight_path_v:
					if point is Vector3:
						path.append(point as Vector3)
		elif _game_state.has_method("compute_preview_path"):
			var compatibility_path_v: Variant = _game_state.call(
				"compute_preview_path", id, destination)
			if compatibility_path_v is Array:
				for point in compatibility_path_v:
					if point is Vector3:
						path.append(point as Vector3)
		entries.append({
			"id": id,
			"destination": destination,
			"node": node,
			"path": path,
		})
	for entry in entries:
		var node: Node = entry["node"]
		if node.has_method("set_external_path_preview_active"):
			node.call("set_external_path_preview_active", true)
	for entry in entries:
		var id: String = entry["id"]
		var destination: Vector3 = entry["destination"]
		var node: Node3D = entry["node"]
		var path: Array[Vector3] = entry["path"]
		var renderer: PathRenderer = _rally_previews.get(id)
		if renderer == null or not is_instance_valid(renderer):
			renderer = PathRendererScript.new()
			renderer.preview_style = true
			add_child(renderer)
			var line_color := Color(0.34, 1.0, 0.62, 0.9)
			if "color" in node:
				line_color = node.color
			renderer.setup(_game_state, "", line_color, node)
			_rally_previews[id] = renderer
		_rally_preview_nodes[id] = node
		if path.size() >= 2:
			renderer.set_explicit_path(path, 1)
		else:
			renderer.clear_explicit_path()
			# An authoritative refusal already carries the exact blocked portrait and
			# reason. Missing render data must not overwrite that causal explanation.
			if _rally_preview_valid:
				_rally_preview_valid = false
				_rally_preview_reason = "NO COMPLETE ROUTE FOR %s" % id.to_upper()
		if "preview_move_target" in node:
			node.preview_move_target = path[path.size() - 1] if not path.is_empty() else destination
	PerformanceTrace.end(&"nav", &"selection.rally_preview", perf_started, anchor_id, entries.size())

func _rally_preview_target_signature(
		target: Vector3,
		anchor_id: String,
		members: Array[String],
		formation_region: Dictionary = {}
	) -> String:
	var target_key := str(target)
	if not formation_region.is_empty():
		target_key = "region=%s|level=%d|revision=%d|approach=%s|cells=%s" % [
			str(formation_region.get("semantic_id", "")),
			int(formation_region.get("authored_level", -1)),
			int(formation_region.get("graph_revision", -1)),
			str(formation_region.get("approach_cell", [])),
			str(formation_region.get("cells", [])),
		]
	var planning_key := "gridless"
	if _game_state != null and _game_state.grid != null:
		var grid: GridWorld = _game_state.grid
		var cell: Vector2i = grid.world_to_grid(target)
		if formation_region.is_empty():
			target_key = "%d,%d,%d" % [
				cell.x, cell.y, grid.level_for_y(target.y)]
		# A target cell alone determines the final formation, but each displayed
		# route also starts at the member's live cell/level and uses the current
		# cautious/direct mode. Keep sub-cell pointer jitter cached while a moving
		# member crossing a cell (or a route-mode change) invalidates stale paths.
		var origins := PackedStringArray()
		var hold_locked: Array = []
		var hud = _resolve_hud()
		if hud != null and hud.has_method("get_hold_locked_ids"):
			hold_locked = hud.get_hold_locked_ids()
		for id in members:
			if not _game_state.characters.has(id):
				origins.append("%s:missing" % id)
				continue
			var origin_cell: Vector2i = grid.world_to_grid(_game_state.get_position(id))
			var available: bool = not hold_locked.has(id) \
				and (not _game_state.has_method("can_accept_move_command") \
					or bool(_game_state.call("can_accept_move_command", id)))
			origins.append("%s:%d,%d,%d:%s" % [
				id, origin_cell.x, origin_cell.y, _game_state.get_character_level(id),
				"ready" if available else "blocked"])
		planning_key = "%s|revision=%d|%s" % [
			"cautious" if _game_state.is_route_cautious() else "direct",
			grid.get_path_walkability_revision(),
			",".join(origins),
		]
	return "%s|%s|%s|%s" % [anchor_id, target_key, ",".join(members), planning_key]

func _clear_rally_preview(reset_status := true) -> void:
	for raw_id in _rally_previews.keys():
		var renderer: PathRenderer = _rally_previews.get(raw_id)
		if renderer != null and is_instance_valid(renderer):
			renderer.clear_explicit_path()
		var node: Node = _rally_preview_nodes.get(raw_id)
		if node != null and is_instance_valid(node) and "preview_move_target" in node:
			node.preview_move_target = Vector3.INF
		if node != null and is_instance_valid(node) and node.has_method("set_external_path_preview_active"):
			node.call("set_external_path_preview_active", false)
	_rally_preview_signature = ""
	if reset_status:
		_rally_preview_valid = false
		_rally_preview_reason = "NO COMPLETE PARTY ROUTE"

func _find_character_node(id: String) -> Node3D:
	var cached = _rally_preview_nodes.get(id)
	if cached != null and is_instance_valid(cached):
		return cached
	if _active_player != null and is_instance_valid(_active_player):
		if "char_id" in _active_player and str(_active_player.char_id) == id:
			_rally_preview_nodes[id] = _active_player
			return _active_player
	var root: Node = _scene_root if _scene_root != null else get_parent()
	if root == null:
		return null
	for candidate in root.find_children("*", "", true, false):
		if candidate is Node3D and "char_id" in candidate and str(candidate.char_id) == id:
			_rally_preview_nodes[id] = candidate
			return candidate
	return null

func _pick_character_id(screen_pos: Vector2) -> String:
	var camera := _resolve_camera()
	var hud = _resolve_hud()
	if camera == null or hud == null or not hud.has_method("get_portrait_ids") or _game_state == null:
		return ""
	var best := ""
	var best_distance := PICK_SCREEN_RADIUS
	for raw_id in hud.get_portrait_ids():
		var id := str(raw_id)
		if (not _game_state.characters.has(id)
				or (_game_state.has_method("is_downed") and _game_state.is_downed(id))):
			continue
		var distance := camera.unproject_position(_game_state.get_render_position(id)).distance_to(screen_pos)
		if distance < best_distance:
			best_distance = distance
			best = id
	return best

func _resolve_active_player() -> Node:
	if _active_player != null and is_instance_valid(_active_player):
		return _active_player
	if _scene_root != null:
		var player = _scene_root.get("_player")
		if player != null and is_instance_valid(player):
			return player
	return null

# --- Selection commits (shared by live input + headless API) ---------------

func _commit_pick(screen_pos: Vector2) -> void:
	var cam := _resolve_camera()
	var hud = _resolve_hud()
	if cam == null or hud == null:
		return
	var best := ""
	var best_d := PICK_SCREEN_RADIUS
	for id in _selectable_ids():
		var d := cam.unproject_position(_game_state.get_render_position(id)).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = id
	if best != "":
		hud.set_active_portrait(best)
	else:
		_deselect_extras()

func _commit_box_select(rect: Rect2) -> void:
	var cam := _resolve_camera()
	var hud = _resolve_hud()
	if cam == null or hud == null:
		return
	var inside: Array[String] = []
	for id in _selectable_ids():
		if rect.has_point(cam.unproject_position(_game_state.get_render_position(id))):
			inside.append(id)
	if inside.is_empty():
		_deselect_extras()
	elif inside.size() == 1:
		hud.set_active_portrait(inside[0])
	else:
		if hud.has_method("set_multi_select_enabled"):
			hud.set_multi_select_enabled(true)
		hud.set_selected_portraits(inside)

## There is always a controlled leader, so an empty click collapses a multi-selection back to it
## rather than to nothing (you never end up controlling no one).
func _deselect_extras() -> void:
	var hud = _resolve_hud()
	if hud == null or not hud.has_method("get_selected_ids"):
		return
	var sel: Array = hud.get_selected_ids()
	if sel.size() > 1 and hud.has_method("set_selected_portraits"):
		hud.set_selected_portraits([sel[0]])

# --- Helpers ---------------------------------------------------------------

func _selectable_ids() -> Array:
	var out: Array[String] = []
	var hud = _resolve_hud()
	if hud == null or not hud.has_method("get_portrait_ids") or _game_state == null:
		return out
	for raw in hud.get_portrait_ids():
		var id := str(raw)
		if _game_state.characters.has(id):
			out.append(id)
	return out

func _resolve_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	if is_inside_tree():
		return get_viewport().get_camera_3d()
	return null

func _defer_to_pick_mode() -> bool:
	var p: Node = _active_player
	if (p == null or not is_instance_valid(p)) and _scene_root != null:
		p = _scene_root.get("_player")
	return p != null and is_instance_valid(p) and p.has_method("is_pick_mode") and bool(p.call("is_pick_mode"))

# --- Headless API (display-free; tests drive the same commit math) ----------

func headless_pick(screen_pos: Vector2, camera: Camera3D = null) -> void:
	if camera != null:
		_camera = camera
	_commit_pick(screen_pos)

func headless_box_select(rect: Rect2, camera: Camera3D = null) -> void:
	if camera != null:
		_camera = camera
	_commit_box_select(rect)

func headless_rally_candidate_ids() -> Array[String]:
	return _rally_candidate_ids()

func headless_commit_rally(target: Vector3, anchor_id := "") -> int:
	return _commit_rally(target, anchor_id)

func headless_preview_rally(target: Vector3, anchor_id := "") -> Dictionary:
	_update_rally_preview(target, anchor_id)
	var final_positions := {}
	for raw_id in _rally_preview_nodes.keys():
		var id := str(raw_id)
		var node: Node = _rally_preview_nodes.get(id)
		if node != null and is_instance_valid(node) and "preview_move_target" in node:
			var destination = node.preview_move_target
			if destination is Vector3 and (destination as Vector3).is_finite():
				final_positions[id] = destination
	return final_positions

func headless_classify_command_hold(elapsed: float, cancelled := false, drag_distance := 0.0) -> String:
	if cancelled or _command_drag_would_cancel(drag_distance, elapsed):
		return "cancelled"
	return "rally" if elapsed >= _rally_hold_duration() else "short"
