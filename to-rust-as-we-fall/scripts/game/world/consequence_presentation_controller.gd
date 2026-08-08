class_name ConsequencePresentationController
extends Node

## Scene-level, presentation-only consumer for authoritative gameplay consequences.
##
## Kit objects publish a portable `state_change_cue_requested` warning before a modeled change,
## while GameState external traversals carry the same provenance in `presentation_receipt`. This
## controller turns both into one visual language without becoming a second gameplay authority:
## warning -> active movement -> arrival/cancellation. All geometry is derived from receipt/state
## positions and CausalFeedbackLink; no result is inferred from a traversal-id naming convention.

const CausalFeedbackLinkScript := preload(
	"res://scripts/game/world/causal_feedback_link.gd"
)
const MOVEMENT_RESULT_PRESENTATION_SCENE := preload(
	"res://scenes/ui/movement_result_presentation.tscn"
)

const PRESENTATION_CONTRACT := "consequence_presentation/v1"
const EMPHASIS_TAG := "consequence_presentation:emphasis"
const RECENT_LIFETIME_MSEC := 4000
## Keep acknowledgement visible long enough for both a human glance and one full
## player-observation capture on the slower browser/render probe.
## Phase wall time begins only after the exact phase has completed these draws.
## This keeps a synchronous observation or slow browser frame from silently
## consuming ACCEPTED/PROGRESS or an undrawn terminal acknowledgement.
const MOVEMENT_PHASE_MIN_PRESENTED_FRAMES := 4
const MOVEMENT_PHASE_MIN_MSEC := 1200
## A typed route can be momentarily idle while GameState hands a planar arrival to
## its ladder/ramp traversal (or vice versa). Only a sustained, authority-idle
## mismatch is a stopped route; one render snapshot is never terminal evidence.
const MOVEMENT_STOPPED_SHORT_GRACE_MSEC := 1200
const MOVEMENT_RECENT_LIFETIME_MSEC := 4000
## A speed/stamina change may replan an accepted route and legitimately increase
## its remaining distance. A slow observation/frame may outlive a wall-clock
## acknowledgement before that acknowledgement reaches a completed framebuffer.
## Require the same four completed draws as an exact interaction result, then
## start the human-readable duration. Only rendered time may retire the cue.
const MOVEMENT_ROUTE_STATUS_MIN_PRESENTED_FRAMES := 4
const MOVEMENT_ROUTE_STATUS_MIN_MSEC := 1200
const MOVEMENT_REPLAN_DISTANCE_EPSILON := 0.05
const MOVEMENT_WAIT_COUNTDOWN_STEP := 0.1
const MAX_ANNOUNCED_KEYS := 256
const WARNING_TINT := Color(1.0, 0.68, 0.22)
const ACTIVE_TINT := Color(0.25, 0.72, 1.0)
const COMPLETE_TINT := Color(0.38, 0.9, 0.64)
const FAILED_TINT := Color(1.0, 0.34, 0.22)

var _game_state = null
var _search_root: Node = null
var _camera = null
var _ui_scheduler = null
var _message_sink := Callable()
var _begin_focus := Callable()
var _finish_focus := Callable()
var _focus_active_query := Callable()
var _visibility_query := Callable()
var _portrait_presenter: Node = null
var _portrait_presenter_query := Callable()

# event-id -> entry; traversal-key -> entry; recent-key -> entry.
var _warning_entries: Dictionary = {}
var _active_entries: Dictionary = {}
var _recent_entries: Dictionary = {}
var _active_traversal_keys: Dictionary = {}

# Node instance id -> {node, callback}. Sources can be streamed in after setup.
var _registered_sources: Dictionary = {}
var _announced_keys: Dictionary = {}
var _announced_order: Array[String] = []

var _started_count := 0
var _arrival_count := 0
var _cancelled_count := 0
var _restore_rebuild_count := 0
var _toast_count := 0
var _visual_serial := 0
var _movement_presentation_serial := 0
var _movement_entries: Dictionary = {}
var _movement_layer: CanvasLayer = null
var _movement_panel: PanelContainer = null
var _movement_label: Label = null
var _movement_phase_draw_callback := Callable()
var _movement_phase_draw_presentation_serial := 0
var _movement_phase_draw_revision := 0
var _movement_phase_draw_phase := ""
var _shelter_portrait_keys: Dictionary = {} # character_id -> persistent HUD presentation key

var _restoring_authority := false
var _restore_rebuild_pending := false

# Extracted, reusable camera-emphasis state. Gameplay never reads these fields.
var _emphasis_active := false
var _emphasis_uses_focus := false
var _emphasis_token := 0
var _emphasis_prev_camera_target: Node3D = null
var _emphasis_prev_camera_offset := Vector3.ZERO
var _emphasis_prev_camera_state: Dictionary = {}


func setup(
		game_state,
		search_root: Node,
		camera,
		ui_scheduler,
		opts: Dictionary = {}
	) -> void:
	# Movement/consequence receipts are UI truth and must continue sampling and
	# drawing while tactical pause freezes gameplay nodes. Authority remains
	# untouched; this controller only projects the already-committed state.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_disconnect_runtime()
	_game_state = game_state
	_search_root = search_root if search_root != null else get_parent()
	_camera = camera
	_ui_scheduler = ui_scheduler
	_message_sink = _callable_option(opts, "message_sink")
	_begin_focus = _callable_option(opts, "begin_focus")
	_finish_focus = _callable_option(opts, "finish_focus")
	_focus_active_query = _callable_option(opts, "focus_active_query")
	_visibility_query = _callable_option(opts, "visibility_query")
	_portrait_presenter_query = _callable_option(opts, "portrait_presenter_query")
	var portrait_presenter_v: Variant = opts.get("portrait_presenter", null)
	_portrait_presenter = portrait_presenter_v as Node \
		if portrait_presenter_v is Node and is_instance_valid(portrait_presenter_v) else null
	_connect_runtime()
	_register_source_tree(_search_root)
	_ensure_movement_presentation_ui()
	set_process(true)


func register_source(source: Node) -> void:
	if source == null or not is_instance_valid(source):
		return
	var source_id := source.get_instance_id()
	if _registered_sources.has(source_id):
		return
	var callbacks := {}
	if source.has_signal("state_change_cue_requested"):
		var consequence_callback := Callable(
			self, "_on_state_change_cue_requested").bind(source)
		if not source.is_connected(
				"state_change_cue_requested", consequence_callback):
			source.connect("state_change_cue_requested", consequence_callback)
		callbacks["state_change_cue_requested"] = consequence_callback
	if source.has_signal("movement_result_requested"):
		var movement_callback := Callable(
			self, "_on_movement_result_requested").bind(source)
		if not source.is_connected("movement_result_requested", movement_callback):
			source.connect("movement_result_requested", movement_callback)
		callbacks["movement_result_requested"] = movement_callback
	if not callbacks.is_empty():
		_registered_sources[source_id] = {"node": source, "callbacks": callbacks}


func begin_authority_restore() -> void:
	_restoring_authority = true
	_restore_rebuild_pending = false
	cancel_emphasis()
	_clear_all_shelter_portrait_receipts()
	_clear_all_entries()
	# A rollback may legitimately replay the same deterministic event id. De-duplication belongs to
	# one presented timeline, not to the lifetime of this scene node. Restored active entries seed
	# their own keys during end_authority_restore(), so this does not replay in-flight toasts.
	_announced_keys.clear()
	_announced_order.clear()


func end_authority_restore() -> void:
	_restoring_authority = false
	_rebuild_active_from_authority()
	_restore_rebuild_pending = false


func on_game_state_snapshot_restored() -> void:
	# TutorialSequence keeps the controller in restore mode through every kit-presenter hook, so
	# synchronous reconstruction cannot replay a start announcement. Hosts that invoke this seam
	# directly still get the same cleanup/rebuild behavior.
	if _restoring_authority:
		_restore_rebuild_pending = true
		return
	_clear_all_entries()
	_rebuild_active_from_authority()


func clear_transient_presentation() -> void:
	cancel_emphasis()
	_clear_all_shelter_portrait_receipts()
	_clear_all_entries()


func get_presentation_state() -> Dictionary:
	_sync_entries(false)
	var warning := _public_records(_warning_entries)
	var active := _public_records(_active_entries)
	var recent := _public_records(_recent_entries)
	var visible_count := 0
	var render_visible_count := 0
	var portrait_render_visible_count := 0
	for record_v in warning + active + recent:
		var record := record_v as Dictionary
		if bool(record.get("visible", false)):
			visible_count += 1
		if bool(record.get("render_visible", false)):
			render_visible_count += 1
		if bool(record.get("portrait_render_visible", false)):
			portrait_render_visible_count += 1
	return {
		"contract": PRESENTATION_CONTRACT,
		"warning": warning,
		"active": active,
		"recent": recent,
		"visible_count": visible_count,
		"render_visible_count": render_visible_count,
		"portrait_render_visible_count": portrait_render_visible_count,
		"warning_count": warning.size(),
		"active_count": active.size(),
		"recent_count": recent.size(),
		"started_count": _started_count,
		"arrival_count": _arrival_count,
		"cancelled_count": _cancelled_count,
		"restore_rebuild_count": _restore_rebuild_count,
		"toast_count": _toast_count,
		"emphasis_active": _emphasis_active,
	}


func get_movement_presentation_state() -> Dictionary:
	var records: Array = []
	for entry_value in _movement_entries.values():
		var entry := entry_value as Dictionary
		var phase_rendered := int(entry.get(
			"phase_presented_frames", 0)) > 0
		var route_status := str(entry.get("route_status", ""))
		# The getter is a projection, never a presentation tick. A freshly-written
		# movement phase is not visible until one exact phase draw; a route-status
		# annotation likewise stays private until a frame contains its exact serial.
		# The already-drawn base acknowledgement remains visible while only a new
		# annotation is withheld.
		var route_status_rendered := route_status.is_empty() \
			or (int(entry.get("route_status_serial", 0)) > 0 \
				and int(entry.get("route_status_presented_frames", 0)) > 0)
		var render_visible := _movement_label != null \
			and _movement_label.is_visible_in_tree() \
			and int(entry.get("presentation_serial", 0)) == _latest_movement_serial() \
			and phase_rendered
		records.append({
			"presentation_serial": int(entry.get("presentation_serial", 0)),
			"verb": str(entry.get("verb", "")),
			"phase": str(entry.get("phase", "")),
			"accepted": bool(entry.get("accepted", false)),
			"reason": str(entry.get("reason", "")),
			"progress": clampf(float(entry.get("progress", 0.0)), 0.0, 1.0),
			"route_status": route_status if route_status_rendered else "",
			"route_status_serial": (int(entry.get("route_status_serial", 0)) \
				if route_status_rendered else 0),
			"route_status_subject_ids": ((entry.get(
				"route_status_subject_ids", []) as Array).duplicate() \
				if route_status_rendered else []),
			"route_status_remaining_seconds": (maxf(0.0, float(entry.get(
				"route_status_remaining_seconds", 0.0))) \
				if route_status_rendered else 0.0),
			"subject_ids": (entry.get("subject_ids", []) as Array).duplicate(),
			"target_screen": (entry.get("target_screen", []) as Array).duplicate(),
			"data_target": _portable_position(
				entry.get("data_target", Vector3.ZERO), Vector3.ZERO),
			"subject_destinations": _portable_subject_destinations(
				entry.get("subject_destinations", {}) as Dictionary),
			"visible": render_visible,
			"render_visible": render_visible,
		})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("presentation_serial", 0)) \
			< int(b.get("presentation_serial", 0)))
	return {
		"contract": "movement_result_presentation/v1",
		"records": records,
		"latest_serial": _latest_movement_serial(),
	}


# --- Extracted host camera emphasis ---------------------------------------------------------

func emphasize_target(
		target_node: Node3D,
		duration := 0.9,
		pause_gameplay := false,
		opts: Dictionary = {}
	) -> bool:
	if target_node == null or not is_instance_valid(target_node):
		return false
	# Presentation must never pause an invisible headless simulation or alter predicted ticks.
	if DisplayServer.get_name() == "headless":
		return true
	if _camera == null or _ui_scheduler == null:
		return false
	var other_focus_active := false
	if _focus_active_query.is_valid():
		other_focus_active = bool(_focus_active_query.call())
	if _emphasis_active or other_focus_active \
			or (_camera.has_method("is_locked") and bool(_camera.call("is_locked"))):
		return false
	var shake_amount := float(opts.get("shake", 0.1))
	if shake_amount > 0.0:
		shake_camera(shake_amount, float(opts.get("shake_decay", 8.0)))
	if bool(opts.get("offscreen_only", true)) \
			and _camera.has_method("is_position_on_screen") \
			and bool(_camera.call("is_position_on_screen", target_node.global_position)):
		return true

	_emphasis_token += 1
	var token := _emphasis_token
	_emphasis_active = true
	_emphasis_uses_focus = pause_gameplay
	if pause_gameplay and _begin_focus.is_valid():
		_begin_focus.call(target_node)
	else:
		_emphasis_uses_focus = false
		_emphasis_prev_camera_target = _camera.get("target") as Node3D
		var follow_offset_v: Variant = _camera.get("follow_offset")
		_emphasis_prev_camera_offset = follow_offset_v as Vector3 \
			if follow_offset_v is Vector3 else Vector3.ZERO
		_emphasis_prev_camera_state = _camera.call("capture_view_state") \
			if _camera.has_method("capture_view_state") else {}
		var focus_height := float(opts.get("focus_height", 0.7))
		if _camera.has_method("lock_to"):
			_camera.call("lock_to", target_node.global_position + Vector3.UP * focus_height)

	_ui_scheduler.cancel_tag(EMPHASIS_TAG)
	_ui_scheduler.schedule_after(
		maxf(0.15, float(duration)),
		Callable(self, "_finish_emphasis_if_token").bind(token),
		EMPHASIS_TAG
	)
	return true


func cancel_emphasis() -> void:
	_emphasis_token += 1
	_finish_emphasis()


func shake_camera(intensity := 0.12, decay := 7.0) -> void:
	if _camera != null and _camera.has_method("shake"):
		_camera.call("shake", maxf(0.0, float(intensity)), maxf(0.1, float(decay)))


func _finish_emphasis_if_token(token: int) -> void:
	if token == _emphasis_token:
		_finish_emphasis()


func _finish_emphasis() -> void:
	if not _emphasis_active:
		return
	if _ui_scheduler != null:
		_ui_scheduler.cancel_tag(EMPHASIS_TAG)
	if _emphasis_uses_focus and _finish_focus.is_valid():
		_finish_focus.call()
	elif _camera != null:
		if not _emphasis_prev_camera_state.is_empty() \
				and _camera.has_method("restore_view_state"):
			_camera.call("restore_view_state", _emphasis_prev_camera_state)
		else:
			_camera.set("follow_offset", _emphasis_prev_camera_offset)
			_camera.set(
				"target",
				_emphasis_prev_camera_target \
					if is_instance_valid(_emphasis_prev_camera_target) else null
			)
			if _camera.has_method("unlock"):
				_camera.call("unlock")
	_emphasis_active = false
	_emphasis_uses_focus = false
	_emphasis_prev_camera_target = null
	_emphasis_prev_camera_state.clear()


# --- Authoritative consequence consumers ---------------------------------------------------

func _on_navigation_route_replanned(
		subject_id: String, state: Dictionary
	) -> void:
	if str(state.get("contract", "")) != "navigation_route_replan/v1" \
			or subject_id.is_empty():
		return
	# Keep the accepted command's one visible lineage. The pace change does not
	# create a second movement result; it annotates the still-active route so a
	# player can see why its timing changed even when geometry stayed identical.
	for serial_v in _movement_entries.keys():
		var serial := int(serial_v)
		var entry := _movement_entries[serial] as Dictionary
		if not bool(entry.get("accepted", false)) \
				or str(entry.get("phase", "")) not in ["accepted", "progress"] \
				or not (entry.get("subject_ids", []) as Array).has(subject_id):
			continue
		var pending := entry.get(
			"pending_reformed_subject_ids", []) as Array
		if not pending.has(subject_id):
			pending.append(subject_id)
		entry["pending_reformed_subject_ids"] = pending
		_movement_entries[serial] = entry


func _on_movement_result_requested(payload: Dictionary, _source: Node) -> void:
	if _restoring_authority:
		return
	var verb := str(payload.get("verb", "")).to_lower()
	var subject_ids: Array[String] = []
	for subject_value in payload.get("subject_ids", []):
		var subject_id := str(subject_value).strip_edges().to_lower()
		if subject_id != "" and not subject_ids.has(subject_id):
			subject_ids.append(subject_id)
	subject_ids.sort()
	var target_screen: Array = payload.get("target_screen", []) \
		if payload.get("target_screen", null) is Array else []
	if verb not in ["move", "rally"] or subject_ids.is_empty() \
			or target_screen.size() != 2:
		return
	# The HUD has one movement-result slot. A newer valid command causally
	# supersedes every older slot entry, including an entry that never completed
	# its draw latch. Retire those entries now so an under-drawn hidden phase can
	# neither leak nor resurface after the newer terminal expires.
	_retire_superseded_movement_entries()
	_movement_presentation_serial += 1
	var accepted := bool(payload.get("accepted", false))
	var reason := str(payload.get("reason", "")).strip_edges()
	if not accepted and reason == "":
		reason = "%s REFUSED // no movement command was accepted." % verb.to_upper()
	var now := Time.get_ticks_msec() # @rendering_only
	var subject_origins := {}
	var subject_route_distances := {}
	if accepted and _game_state != null:
		for subject_id in subject_ids:
			if _game_state.characters.has(subject_id):
				subject_origins[subject_id] = _game_state.get_position(subject_id)
				if _game_state.has_method(
						"get_navigation_route_remaining_distance"):
					var route_distance := float(_game_state.call(
						"get_navigation_route_remaining_distance", subject_id))
					if route_distance >= 0.0 and is_finite(route_distance):
						subject_route_distances[subject_id] = route_distance
	var entry := {
		"presentation_serial": _movement_presentation_serial,
		"verb": verb,
		"phase": "accepted" if accepted else "refused",
		"accepted": accepted,
		"reason": reason,
		"subject_ids": subject_ids,
		"target_screen": target_screen.duplicate(),
		"data_target": payload.get("data_target", Vector3.ZERO),
		"subject_destinations": (payload.get(
			"subject_destinations", {}) as Dictionary).duplicate(true) \
			if payload.get("subject_destinations", null) is Dictionary else {},
		"subject_origins": subject_origins,
		"subject_route_distances": subject_route_distances,
		"subject_route_progress_bases": {},
		"subject_last_route_remaining": subject_route_distances.duplicate(true),
		"subject_progress": {},
		"progress": 0.0 if accepted else 1.0,
		"route_status": "",
		"route_status_serial": 0,
		"route_status_started_msec": 0,
		"route_status_presented_frames": 0,
		"route_status_duration_started_msec": 0,
		"route_status_subject_ids": [],
		"route_status_remaining_seconds": 0.0,
		"pending_reformed_subject_ids": [],
		"phase_started_msec": now,
		"phase_revision": 1,
		"phase_presented_frames": 0,
		"phase_duration_started_msec": 0,
		"stopped_short_since_msec": 0,
		# These latches preserve the production command's immutable acceptance
		# while its minimum visible accepted -> progress sequence is still being
		# presented.  A non-preserving traversal can then terminate that same
		# lineage as interrupted, but can never turn it into arrival afterward.
		"arrival_pending": false,
		"interruption_pending": false,
		"interruption_reason": "",
		"recent_until_msec": 0,
	}
	_movement_entries[_movement_presentation_serial] = entry
	_present_latest_movement_entry()
	# Same receipt rule as _begin_movement_phase: an ACCEPTED birth deliberately draws nothing (the
	# party walking is the acknowledgement), so its receipt is granted at write; only a phase that
	# actually renders (a refusal at birth) arms the framebuffer receipt.
	if not _movement_phase_renders(str(entry.get("phase", ""))):
		entry["phase_presented_frames"] = MOVEMENT_PHASE_MIN_PRESENTED_FRAMES
		entry["phase_duration_started_msec"] = now
	else:
		_connect_movement_phase_draw(
			_movement_presentation_serial,
			int(entry.get("phase_revision", 0)),
			str(entry.get("phase", "")))


func _retire_superseded_movement_entries() -> void:
	if _movement_entries.is_empty():
		return
	_disconnect_movement_phase_draw()
	_disconnect_route_status_draw()
	_movement_entries.clear()


func _ensure_movement_presentation_ui() -> void:
	if _movement_layer != null or Engine.is_editor_hint():
		return
	var layer_v := MOVEMENT_RESULT_PRESENTATION_SCENE.instantiate()
	if not (layer_v is CanvasLayer):
		if layer_v != null:
			layer_v.queue_free()
		return
	var layer := layer_v as CanvasLayer
	var panel_v := layer.get_node_or_null("MovementResultPresentation")
	var label_v := layer.get_node_or_null(
		"MovementResultPresentation/MovementResultLabel")
	if not (panel_v is PanelContainer) or not (label_v is Label):
		layer.queue_free()
		return
	_movement_layer = layer
	_movement_panel = panel_v as PanelContainer
	_movement_label = label_v as Label
	add_child(_movement_layer)


func _present_latest_movement_entry() -> void:
	_ensure_movement_presentation_ui()
	if _movement_panel == null or _movement_label == null:
		return
	var serial := _latest_movement_serial()
	if serial <= 0 or not _movement_entries.has(serial):
		_movement_panel.visible = false
		_movement_label.text = ""
		return
	var entry := _movement_entries[serial] as Dictionary
	var verb := str(entry.get("verb", "move")).to_upper()
	var phase := str(entry.get("phase", "")).to_upper()
	var subject_count := (entry.get("subject_ids", []) as Array).size()
	var reason := str(entry.get("reason", "")).strip_edges()
	var progress := clampf(float(entry.get("progress", 0.0)), 0.0, 1.0)
	_movement_label.text = "%s %s // %d %s" % [
		verb, phase, subject_count, "MEMBER" if subject_count == 1 else "MEMBERS",
	]
	if phase in ["ACCEPTED", "PROGRESS", "ARRIVAL", "INTERRUPTED"]:
		_movement_label.text = "%s\nROUTE %d%%" % [
			_movement_label.text, int(round(progress * 100.0)),
		]
	var route_status := str(entry.get("route_status", ""))
	var route_status_count := (entry.get(
		"route_status_subject_ids", []) as Array).size()
	if route_status == "reforming_route":
		_movement_label.text = "%s\nREFORMING ROUTE // %d %s" % [
			_movement_label.text,
			route_status_count,
			"MEMBER" if route_status_count == 1 else "MEMBERS",
		]
	elif route_status == "cooperative_hold":
		_movement_label.text = "%s\nCOOPERATIVE HOLD // %d %s // %.1fs" % [
			_movement_label.text,
			route_status_count,
			"MEMBER" if route_status_count == 1 else "MEMBERS",
			maxf(0.0, float(entry.get(
				"route_status_remaining_seconds", 0.0))),
		]
	if phase in ["REFUSED", "INTERRUPTED"] and reason != "":
		_movement_label.text = "%s\n%s" % [_movement_label.text, reason]
	_movement_label.modulate = FAILED_TINT if phase == "REFUSED" \
		else (WARNING_TINT if phase == "INTERRUPTED" \
		else (COMPLETE_TINT if phase == "ARRIVAL" else ACTIVE_TINT))
	# The player is never told about their own successful movement. Watching the party walk IS the
	# feedback; a banner reading "RALLY ARRIVAL // 3 MEMBERS // ROUTE 100%" narrates what is already
	# on screen. Words are earned only by what the world cannot show by itself: a move that did NOT
	# happen (refused, interrupted), or a party visibly STALLED for a reason with no visual -- a route
	# being reformed, a cooperative hold on a contested cell.
	_movement_panel.visible = phase in ["REFUSED", "INTERRUPTED"] 		or route_status in ["reforming_route", "cooperative_hold"]


func _latest_movement_serial() -> int:
	var latest := 0
	for serial_value in _movement_entries.keys():
		latest = maxi(latest, int(serial_value))
	return latest


func _portable_subject_destinations(destinations: Dictionary) -> Dictionary:
	var result := {}
	for subject_value in destinations.keys():
		result[str(subject_value)] = _portable_position(
			destinations[subject_value], Vector3.ZERO)
	return result

func _on_state_change_cue_requested(cue: Dictionary, source: Node) -> void:
	if _restoring_authority:
		return
	var fallback_source: Vector3 = source.global_position \
		if is_instance_valid(source) and source is Node3D else Vector3.ZERO
	var receipt := _normalize_receipt(cue, "", "", {}, fallback_source)
	if receipt.is_empty():
		return
	var event_id := str(receipt["event_id"])
	_discard_entry(_warning_entries, event_id)
	var entry := _create_entry(receipt, "warning", "warning")
	entry["source_owner_id"] = source.get_instance_id() if is_instance_valid(source) else 0
	_warning_entries[event_id] = entry
	_present_entry_on_portraits(entry)
	_started_count += 1
	_announce_once("warning|%s" % event_id, str(receipt.get("label", "")), 2.4)


func _on_external_traversal_started(subject_id: String, state: Dictionary) -> void:
	if _restoring_authority:
		_restore_rebuild_pending = true
		return
	_latch_nonpreserving_movement_override(subject_id, state)
	_add_external_traversal(subject_id, state, false)


func _latch_nonpreserving_movement_override(
		subject_id: String, state: Dictionary) -> void:
	# Ladder/ramp edges temporarily hand an ordinary route to the external
	# traversal engine while preserving its graph plan. Forced carries do not:
	# GameState cancels that plan before emitting this exact public boundary.
	if bool(state.get("preserve_cross_level_plan", false)):
		return
	var receipt := state.get("presentation_receipt", {}) as Dictionary
	var cause_label := str(receipt.get("label", "FORCED MOVEMENT")).strip_edges()
	if cause_label == "":
		cause_label = "FORCED MOVEMENT"
	var changed := false
	for serial_value in _movement_entries.keys():
		var serial := int(serial_value)
		var entry := _movement_entries[serial] as Dictionary
		if not bool(entry.get("accepted", false)) \
				or str(entry.get("phase", "")) not in ["accepted", "progress"] \
				or not (entry.get("subject_ids", []) as Array).has(subject_id) \
				or bool(entry.get("interruption_pending", false)):
			continue
		# If the whole group had already reached its shown endpoints before this
		# forced traversal began, preserve that historical arrival even though the
		# acknowledgement is still stepping through its minimum visible phases.
		if _movement_entry_at_destinations(entry):
			entry["arrival_pending"] = true
		else:
			entry["interruption_pending"] = true
			entry["interruption_reason"] = (
				"%s INTERRUPTED // %s stopped the party before the shown destination."
				% [str(entry.get("verb", "move")).to_upper(), cause_label.to_upper()])
		entry["stopped_short_since_msec"] = 0
		_movement_entries[serial] = entry
		changed = true
	if changed:
		_present_latest_movement_entry()


func _add_external_traversal(subject_id: String, state: Dictionary, restored: bool) -> void:
	var traversal_id := str(state.get("traversal_id", ""))
	var receipt_v: Variant = state.get("presentation_receipt", {})
	if not (receipt_v is Dictionary):
		return
	var receipt := _normalize_receipt(
		receipt_v as Dictionary,
		subject_id,
		traversal_id,
		state,
		state.get("render_origin", Vector3.ZERO) as Vector3
			if state.get("render_origin", null) is Vector3 else Vector3.ZERO
	)
	if receipt.is_empty():
		return
	var event_id := str(receipt["event_id"])
	_discard_entry(_warning_entries, event_id)
	var active_key := _active_key(subject_id, traversal_id, event_id)
	_discard_entry(_active_entries, active_key)
	var entry := _create_entry(receipt, "active", "active")
	entry["restored"] = restored
	entry["progress"] = clampf(float(state.get("progress", 0.0)), 0.0, 1.0)
	entry["last_progress"] = float(entry["progress"])
	_active_entries[active_key] = entry
	_active_traversal_keys[_traversal_key(subject_id, traversal_id)] = active_key
	_present_entry_on_portraits(entry)
	if restored:
		_restore_rebuild_count += 1
		_remember_announcement("active|%s" % event_id)
	else:
		_started_count += 1
		var text := str(receipt.get("label", ""))
		var destination_label := str(receipt.get("destination_label", ""))
		if not destination_label.is_empty():
			text += " // " + destination_label
		_announce_once("active|%s" % event_id, text, 2.4)


func _on_external_traversal_finished(subject_id: String, traversal_id: StringName) -> void:
	var lookup := _traversal_key(subject_id, String(traversal_id))
	var active_key := str(_active_traversal_keys.get(lookup, ""))
	if active_key.is_empty() or not _active_entries.has(active_key):
		return
	var entry: Dictionary = _active_entries[active_key]
	_active_entries.erase(active_key)
	_active_traversal_keys.erase(lookup)
	entry["phase"] = "arrival"
	entry["mode"] = "complete"
	entry["progress"] = 1.0
	entry["recent_until_msec"] = Time.get_ticks_msec() + RECENT_LIFETIME_MSEC # @rendering_only
	_reset_entry_endpoints_to_receipt(entry)
	_set_link_phase(entry, "complete", true, true)
	_present_entry_on_portraits(entry)
	_replace_recent(active_key, entry)
	_arrival_count += 1
	var receipt: Dictionary = entry.get("receipt", {})
	var event_id := str(receipt.get("event_id", ""))
	var destination_label := str(receipt.get("destination_label", ""))
	var text := "ARRIVED"
	if not destination_label.is_empty():
		text += " // " + destination_label
	_announce_once("arrival|%s" % event_id, text, 2.0)


func _on_external_traversal_cancelled(
		subject_id: String,
		traversal_id: StringName,
		_reason: StringName
	) -> void:
	var lookup := _traversal_key(subject_id, String(traversal_id))
	var active_key := str(_active_traversal_keys.get(lookup, ""))
	if active_key.is_empty() or not _active_entries.has(active_key):
		return
	var entry: Dictionary = _active_entries[active_key]
	_active_entries.erase(active_key)
	_active_traversal_keys.erase(lookup)
	entry["phase"] = "cancelled"
	entry["mode"] = "failed"
	entry["recent_until_msec"] = Time.get_ticks_msec() + RECENT_LIFETIME_MSEC # @rendering_only
	_set_link_phase(entry, "failed", true, false)
	_present_entry_on_portraits(entry)
	_replace_recent(active_key, entry)
	_cancelled_count += 1


## Shelter transitions are authoritative GameState changes, but they still need
## the same player-facing receipt as a modeled movement consequence. Keeping the
## wiring here prevents individual previews from inventing private rest UI.
func _on_rest_started(character_id: String) -> void:
	_announce_state_transition(
		"rest_started", character_id,
		"%s settles into shelter rest." % character_id.capitalize(), 2.2)
	_set_shelter_portrait_receipt(character_id, "RESTING", "SHELTER")


func _on_rest_stopped(character_id: String) -> void:
	_clear_shelter_portrait_receipt(character_id)


func _on_character_revived(character_id: String) -> void:
	var joins_rest: bool = _game_state != null \
		and _game_state.has_method("is_resting") \
		and bool(_game_state.call("is_resting", character_id))
	_announce_state_transition(
		"character_revived", character_id,
		"%s recovers at the shelter%s." % [
			character_id.capitalize(),
			" and joins the rest" if joins_rest else "",
		], 2.8)
	if joins_rest:
		_set_shelter_portrait_receipt(character_id, "RECOVERED", "RESTING")


func _on_night_skipped(new_day: int) -> void:
	_clear_all_shelter_portrait_receipts()
	_announce_state_transition(
		"night_skipped", str(new_day),
		"Dawn arrives. Day %d begins." % new_day, 2.8)


func _announce_state_transition(
		kind: String,
		subject: String,
		text: String,
		duration: float
	) -> void:
	_visual_serial += 1
	_announce_once(
		"state|%s|%s|%d" % [kind, subject, _visual_serial], text, duration)


func _set_shelter_portrait_receipt(
		character_id: String,
		label: String,
		destination_label: String
	) -> void:
	var portrait_presenter := _resolve_portrait_presenter()
	if portrait_presenter == null or not portrait_presenter.has_method(
			"set_portrait_consequence_presentation"):
		return
	var presentation_key := "shelter_state|%s" % character_id
	portrait_presenter.call(
		"set_portrait_consequence_presentation",
		character_id,
		{
			"presentation_key": presentation_key,
			"event_id": "state|shelter|%s|%d" % [character_id, _visual_serial],
			"phase": "active",
			"label": label,
			"destination_label": destination_label,
			"progress": 1.0,
		})
	_shelter_portrait_keys[character_id] = presentation_key


func _clear_shelter_portrait_receipt(character_id: String) -> void:
	if not _shelter_portrait_keys.has(character_id):
		return
	var portrait_presenter := _resolve_portrait_presenter()
	if portrait_presenter != null and portrait_presenter.has_method(
			"clear_portrait_consequence_presentation"):
		portrait_presenter.call(
			"clear_portrait_consequence_presentation",
			character_id,
			str(_shelter_portrait_keys[character_id]))
	_shelter_portrait_keys.erase(character_id)


func _clear_all_shelter_portrait_receipts() -> void:
	for character_id_v in _shelter_portrait_keys.keys():
		_clear_shelter_portrait_receipt(str(character_id_v))


func _rebuild_active_from_authority() -> void:
	if _game_state == null:
		return
	for subject_id_v in _game_state.characters.keys():
		var subject_id := str(subject_id_v)
		if not bool(_game_state.is_external_traversal_active(subject_id)):
			continue
		var state: Dictionary = _game_state.get_external_traversal_state(subject_id)
		_add_external_traversal(subject_id, state, true)


# --- Presentation lifecycle ---------------------------------------------------------------

func _process(_delta: float) -> void:
	_sync_entries(true)
	_sync_movement_entries()


func _sync_movement_entries() -> void:
	_sync_movement_entries_at(Time.get_ticks_msec()) # @rendering_only


func _sync_movement_entries_at(now: int) -> void:
	var expired: Array[int] = []
	var changed := false
	for serial_value in _movement_entries.keys():
		var serial := int(serial_value)
		var entry := _movement_entries[serial] as Dictionary
		var phase := str(entry.get("phase", ""))
		if phase in ["accepted", "progress"] \
				and _update_movement_entry_progress(entry, now):
			changed = true
		if phase == "accepted" \
				and _movement_phase_readable_complete(entry, now,
					MOVEMENT_PHASE_MIN_MSEC):
			# Acceptance is immutable history: the production command was either
			# accepted or refused at emission. A later hazard/stop may interrupt an
			# accepted route, but it cannot retroactively turn that command into a
			# refusal. Keep one causal lineage through a separately visible terminal.
			_begin_movement_phase(entry, "progress", now)
			changed = true
		elif phase == "progress" \
				and _movement_phase_readable_complete(entry, now,
					MOVEMENT_PHASE_MIN_MSEC):
			if bool(entry.get("arrival_pending", false)):
				entry["progress"] = 1.0
				entry["stopped_short_since_msec"] = 0
				_begin_movement_phase(entry, "arrival", now)
				changed = true
			elif bool(entry.get("interruption_pending", false)):
				entry["reason"] = str(entry.get("interruption_reason",
					"%s INTERRUPTED // forced movement stopped the party before the shown destination."
						% str(entry.get("verb", "move")).to_upper()))
				entry["stopped_short_since_msec"] = 0
				_begin_movement_phase(entry, "interrupted", now)
				changed = true
			elif _movement_entry_arrived(entry):
				entry["progress"] = 1.0
				entry["stopped_short_since_msec"] = 0
				_begin_movement_phase(entry, "arrival", now)
				changed = true
			elif _movement_entry_route_active(entry):
				# In particular, `_cross_level_plan` remains authoritative across the
				# brief instant where is_moving() is false between route segments.
				entry["stopped_short_since_msec"] = 0
			elif _movement_entry_stopped_short(entry):
				var stopped_since := int(entry.get("stopped_short_since_msec", 0))
				if stopped_since <= 0:
					entry["stopped_short_since_msec"] = now
				elif now - stopped_since >= MOVEMENT_STOPPED_SHORT_GRACE_MSEC:
					entry["reason"] = "%s INTERRUPTED // movement stopped before the shown destination." \
						% str(entry.get("verb", "move")).to_upper()
					_begin_movement_phase(entry, "interrupted", now)
					changed = true
			else:
				entry["stopped_short_since_msec"] = 0
		elif phase in ["arrival", "interrupted", "refused"] \
				and _movement_phase_readable_complete(entry, now,
					MOVEMENT_RECENT_LIFETIME_MSEC):
			expired.append(serial)
		_movement_entries[serial] = entry
	for serial in expired:
		_movement_entries.erase(serial)
		changed = true
	if changed:
		_present_latest_movement_entry()


## Which movement phases put PIXELS on screen. Successful movement (accepted / progress / arrival)
## deliberately renders nothing -- the party visibly walking IS the acknowledgement, and a banner
## narrating it was ruled UI junk. Only a move that did not happen earns chrome; a stall status
## (reforming_route / cooperative_hold) renders through the same panel when present.
func _movement_phase_renders(phase: String) -> bool:
	return phase in ["refused", "interrupted"]

func _begin_movement_phase(entry: Dictionary, phase: String, now: int) -> void:
	entry["phase"] = phase
	entry["phase_started_msec"] = now
	entry["phase_revision"] = int(entry.get("phase_revision", 0)) + 1
	entry["phase_presented_frames"] = 0
	entry["phase_duration_started_msec"] = 0
	entry["recent_until_msec"] = 0
	# Paint the new phase before arming its exact post-draw receipt. This ordering
	# matters when arrival coincides with the final moving frame: registering the
	# callback against the old label can otherwise leave a static ARRIVAL phase at
	# zero presented frames until some unrelated animation dirties the canvas.
	_present_latest_movement_entry()
	if not _movement_phase_renders(phase):
		# A non-rendering phase cannot earn framebuffer receipts -- there is deliberately nothing to
		# draw. Its evidence is the WORLD: the party's real positions, which the observation layer
		# reads directly. Grant the receipt at write time so downstream lifetimes (a status serial
		# gating on the current phase, arrival's recent-window) do not chain on a banner that never
		# comes, while render_visible stays honestly false.
		entry["phase_presented_frames"] = MOVEMENT_PHASE_MIN_PRESENTED_FRAMES
		entry["phase_duration_started_msec"] = now
		if phase == "arrival":
			entry["recent_until_msec"] = now + MOVEMENT_RECENT_LIFETIME_MSEC
		return
	_connect_movement_phase_draw(
		int(entry.get("presentation_serial", 0)),
		int(entry.get("phase_revision", 0)),
		phase)


func _movement_phase_readable_complete(
		entry: Dictionary, now: int, required_msec: int
	) -> bool:
	# The latest entry is the only movement result eligible for the HUD. A phase
	# cannot spend any of its readable lifetime until its exact render-receipt
	# latch completes; wall time alone is never evidence that the player saw it.
	if int(entry.get("presentation_serial", 0)) != _latest_movement_serial():
		return false
	var presented_frames := int(entry.get("phase_presented_frames", 0))
	var duration_started := int(entry.get("phase_duration_started_msec", 0))
	return presented_frames >= MOVEMENT_PHASE_MIN_PRESENTED_FRAMES \
		and duration_started > 0 \
		and now - duration_started >= required_msec


func _connect_movement_phase_draw(
		presentation_serial: int, phase_revision: int, phase: String
	) -> void:
	_disconnect_movement_phase_draw()
	if presentation_serial <= 0 or phase_revision <= 0 \
			or phase not in ["accepted", "progress", "arrival", "refused", "interrupted"]:
		return
	_movement_phase_draw_presentation_serial = presentation_serial
	_movement_phase_draw_revision = phase_revision
	_movement_phase_draw_phase = phase
	_movement_phase_draw_callback = Callable(
		self, "_on_movement_phase_frame_drawn").bind(
			presentation_serial, phase_revision, phase)
	RenderingServer.frame_post_draw.connect(_movement_phase_draw_callback)


func _disconnect_movement_phase_draw() -> void:
	if _movement_phase_draw_callback.is_valid() \
			and RenderingServer.frame_post_draw.is_connected(
				_movement_phase_draw_callback):
		RenderingServer.frame_post_draw.disconnect(_movement_phase_draw_callback)
	_movement_phase_draw_callback = Callable()
	_movement_phase_draw_presentation_serial = 0
	_movement_phase_draw_revision = 0
	_movement_phase_draw_phase = ""


func _on_movement_phase_frame_drawn(
		presentation_serial: int, phase_revision: int, phase: String
	) -> void:
	_record_movement_phase_frame_drawn_at(
		Time.get_ticks_msec(), # @rendering_only
		presentation_serial, phase_revision, phase)


func _record_movement_phase_frame_drawn_at(
		now: int,
		presentation_serial: int,
		phase_revision: int,
		phase: String
	) -> void:
	# This explicit seam is shared by the real post-draw callback and deterministic
	# tests. Its three immutable guards reject a delayed callback from a previous
	# command or phase even when the replacement happens to use the same verb.
	if presentation_serial != _latest_movement_serial() \
			or not _movement_entries.has(presentation_serial) \
			or _movement_panel == null or _movement_label == null \
			or not _movement_panel.is_visible_in_tree() \
			or not _movement_label.is_visible_in_tree():
		return
	var entry := _movement_entries[presentation_serial] as Dictionary
	if int(entry.get("phase_revision", 0)) != phase_revision \
			or str(entry.get("phase", "")) != phase:
		return
	var expected_prefix := "%s %s // " % [
		str(entry.get("verb", "move")).to_upper(), phase.to_upper(),
	]
	if not _movement_label.text.begins_with(expected_prefix):
		return
	var presented_frames := mini(
		MOVEMENT_PHASE_MIN_PRESENTED_FRAMES,
		int(entry.get("phase_presented_frames", 0)) + 1)
	entry["phase_presented_frames"] = presented_frames
	if presented_frames >= MOVEMENT_PHASE_MIN_PRESENTED_FRAMES \
			and int(entry.get("phase_duration_started_msec", 0)) <= 0:
		entry["phase_duration_started_msec"] = now
		if phase in ["arrival", "interrupted", "refused"]:
			entry["recent_until_msec"] = now + MOVEMENT_RECENT_LIFETIME_MSEC
		if _movement_phase_draw_presentation_serial == presentation_serial \
				and _movement_phase_draw_revision == phase_revision \
				and _movement_phase_draw_phase == phase:
			_disconnect_movement_phase_draw()
	_movement_entries[presentation_serial] = entry


func _update_movement_entry_progress(entry: Dictionary, now: int) -> bool:
	if _game_state == null:
		return false
	var destinations := entry.get("subject_destinations", {}) as Dictionary
	var origins := entry.get("subject_origins", {}) as Dictionary
	var route_distances := entry.get(
		"subject_route_distances", {}) as Dictionary
	var route_progress_bases := entry.get(
		"subject_route_progress_bases", {}) as Dictionary
	var last_route_remaining := entry.get(
		"subject_last_route_remaining", {}) as Dictionary
	var previous_by_subject := entry.get("subject_progress", {}) as Dictionary
	var next_by_subject := previous_by_subject.duplicate()
	var total := 0.0
	var counted := 0
	var reformed_subjects: Array[String] = []
	for pending_subject_v in entry.get(
			"pending_reformed_subject_ids", []):
		var pending_subject := str(pending_subject_v)
		if pending_subject != "" and not reformed_subjects.has(pending_subject):
			reformed_subjects.append(pending_subject)
	entry["pending_reformed_subject_ids"] = []
	var waiting_subjects: Array[String] = []
	var longest_wait_remaining := 0.0
	for subject_value in entry.get("subject_ids", []):
		var subject_id := str(subject_value)
		if not _game_state.characters.has(subject_id) \
				or not destinations.get(subject_id, null) is Vector3 \
				or not origins.get(subject_id, null) is Vector3:
			continue
		var destination := destinations[subject_id] as Vector3
		var origin := origins[subject_id] as Vector3
		var current: Vector3 = _game_state.get_position(subject_id)
		var initial_distance := origin.distance_to(destination)
		var previous_subject_progress := clampf(float(
			previous_by_subject.get(subject_id, 0.0)), 0.0, 1.0)
		var candidate := 1.0 if initial_distance <= 0.001 else clampf(
			1.0 - current.distance_to(destination) / initial_distance, 0.0, 1.0)
		var route_distance_v: Variant = route_distances.get(subject_id, null)
		if (route_distance_v is int or route_distance_v is float) \
				and _game_state.has_method(
					"get_navigation_route_remaining_distance"):
			var route_distance_basis := float(route_distance_v)
			var remaining_route_distance := float(_game_state.call(
				"get_navigation_route_remaining_distance", subject_id))
			if remaining_route_distance >= 0.0 \
					and is_finite(remaining_route_distance):
				var previous_remaining := float(last_route_remaining.get(
					subject_id, route_distance_basis))
				var route_active := bool(_game_state.is_moving(subject_id))
				if _game_state.has_method("is_navigation_route_active"):
					route_active = bool(_game_state.call(
						"is_navigation_route_active", subject_id))
				# Running exhaustion and other visible speed changes can replan onto a
				# longer valid route. Preserve completed work, rebase only the unsolved
				# suffix, and name that state instead of freezing the old percentage.
				if route_active and remaining_route_distance \
						> previous_remaining + MOVEMENT_REPLAN_DISTANCE_EPSILON:
					route_distance_basis = remaining_route_distance
					route_distances[subject_id] = route_distance_basis
					route_progress_bases[subject_id] = previous_subject_progress
					if not reformed_subjects.has(subject_id):
						reformed_subjects.append(subject_id)
				var progress_base := clampf(float(route_progress_bases.get(
					subject_id, 0.0)), 0.0, 1.0)
				if route_distance_basis <= 0.001:
					candidate = 1.0
				else:
					candidate = progress_base + (1.0 - progress_base) * clampf(
						1.0 - remaining_route_distance / route_distance_basis,
						0.0, 1.0)
				last_route_remaining[subject_id] = remaining_route_distance
		if _game_state.has_method("get_navigation_wait_state"):
			var wait_v: Variant = _game_state.call(
				"get_navigation_wait_state", subject_id)
			if wait_v is Dictionary \
					and bool((wait_v as Dictionary).get("active", false)) \
					and str((wait_v as Dictionary).get(
						"kind", "")) == "cooperative_hold":
				waiting_subjects.append(subject_id)
				longest_wait_remaining = maxf(longest_wait_remaining, float(
					(wait_v as Dictionary).get("remaining_seconds", 0.0)))
		# A curved or cooperative route can briefly increase straight-line distance.
		# The visible acknowledgement is cumulative work, so never run it backward.
		candidate = maxf(candidate, previous_subject_progress)
		if current.distance_to(destination) <= 0.2 \
				and not bool(_game_state.is_moving(subject_id)):
			candidate = 1.0
		next_by_subject[subject_id] = candidate
		total += candidate
		counted += 1
	if counted <= 0:
		return false
	# Final authoritative placement outranks lagging route-distance cleanup. Latch
	# the terminal while sampling so the readable ACCEPTED -> PROGRESS sequence can
	# finish normally and then must advance to ARRIVAL.
	if counted == (entry.get("subject_ids", []) as Array).size() \
			and not bool(entry.get("interruption_pending", false)) \
			and _movement_entry_exactly_at_destinations(entry):
		entry["arrival_pending"] = true
	var previous := clampf(float(entry.get("progress", 0.0)), 0.0, 1.0)
	var next := maxf(previous, clampf(total / float(counted), 0.0, 1.0))
	entry["subject_route_distances"] = route_distances
	entry["subject_route_progress_bases"] = route_progress_bases
	entry["subject_last_route_remaining"] = last_route_remaining
	entry["subject_progress"] = next_by_subject
	entry["progress"] = next
	var status_changed := _update_movement_route_status(
		entry, now, reformed_subjects, waiting_subjects,
		longest_wait_remaining)
	return status_changed or next > previous + 0.0001


func _update_movement_route_status(
		entry: Dictionary,
		now: int,
		reformed_subjects: Array[String],
		waiting_subjects: Array[String],
		longest_wait_remaining: float
	) -> bool:
	var previous_status := str(entry.get("route_status", ""))
	var previous_subjects := entry.get(
		"route_status_subject_ids", []) as Array
	var previous_remaining := maxf(0.0, float(entry.get(
		"route_status_remaining_seconds", 0.0)))
	var next_status := previous_status
	var next_subjects: Array[String] = []
	for subject_v in previous_subjects:
		next_subjects.append(str(subject_v))
	var next_remaining := previous_remaining
	var begins_new_status := false
	if not reformed_subjects.is_empty():
		next_status = "reforming_route"
		next_subjects = reformed_subjects.duplicate()
		next_remaining = 0.0
		begins_new_status = true
	elif previous_status == "reforming_route" \
			and not _reforming_route_presentation_complete(entry, now):
		pass
	elif not waiting_subjects.is_empty():
		next_status = "cooperative_hold"
		next_subjects = waiting_subjects.duplicate()
		# Round upward so an active finite hold never renders as a misleading 0.0s.
		next_remaining = ceilf(longest_wait_remaining \
			/ MOVEMENT_WAIT_COUNTDOWN_STEP) * MOVEMENT_WAIT_COUNTDOWN_STEP
		begins_new_status = previous_status != next_status
	else:
		next_status = ""
		next_subjects.clear()
		next_remaining = 0.0
	if begins_new_status:
		entry["route_status_serial"] = int(entry.get(
			"route_status_serial", 0)) + 1
		entry["route_status_started_msec"] = now
		entry["route_status_presented_frames"] = 0
		entry["route_status_duration_started_msec"] = 0
		_ensure_route_status_draw_connection()
	next_subjects.sort()
	var changed := next_status != previous_status \
		or next_subjects != previous_subjects \
		or not is_equal_approx(next_remaining, previous_remaining)
	entry["route_status"] = next_status
	entry["route_status_subject_ids"] = next_subjects
	entry["route_status_remaining_seconds"] = next_remaining
	return changed


func _reforming_route_presentation_complete(entry: Dictionary, now: int) -> bool:
	# Superseded acknowledgements are not on screen and must not retain an old
	# render hold forever. The latest acknowledgement, however, can retire only
	# after the renderer has completed the minimum draw receipts and the readable
	# duration that begins at the last required receipt.
	if int(entry.get("presentation_serial", 0)) != _latest_movement_serial():
		return now - int(entry.get("route_status_started_msec", now)) \
			>= MOVEMENT_ROUTE_STATUS_MIN_MSEC
	var presented_frames := int(entry.get("route_status_presented_frames", 0))
	var duration_started := int(entry.get(
		"route_status_duration_started_msec", 0))
	return presented_frames >= MOVEMENT_ROUTE_STATUS_MIN_PRESENTED_FRAMES \
		and duration_started > 0 \
		and now - duration_started >= MOVEMENT_ROUTE_STATUS_MIN_MSEC


func _ensure_route_status_draw_connection() -> void:
	var callback := Callable(self, "_on_route_status_frame_drawn")
	if not RenderingServer.frame_post_draw.is_connected(callback):
		RenderingServer.frame_post_draw.connect(callback)


func _disconnect_route_status_draw() -> void:
	var callback := Callable(self, "_on_route_status_frame_drawn")
	if RenderingServer.frame_post_draw.is_connected(callback):
		RenderingServer.frame_post_draw.disconnect(callback)


func _on_route_status_frame_drawn() -> void:
	_record_route_status_frame_drawn_at(Time.get_ticks_msec()) # @rendering_only


func _record_route_status_frame_drawn_at(now: int) -> void:
	# A signal delivery is useful only when the exact latest acknowledgement was
	# actually eligible to draw. Logical status on an occluded/superseded entry is
	# not a player-visible receipt and cannot start its lifetime.
	var serial := _latest_movement_serial()
	if serial <= 0 or not _movement_entries.has(serial) \
			or _movement_panel == null or _movement_label == null \
			or not _movement_panel.is_visible_in_tree() \
			or not _movement_label.is_visible_in_tree():
		_disconnect_route_status_draw()
		return
	var entry := _movement_entries[serial] as Dictionary
	var route_status := str(entry.get("route_status", ""))
	var expected_label := ""
	match route_status:
		"reforming_route":
			expected_label = "REFORMING ROUTE"
		"cooperative_hold":
			expected_label = "COOPERATIVE HOLD"
	if expected_label.is_empty() or not _movement_label.text.contains(
			expected_label):
		_disconnect_route_status_draw()
		return
	var presented_frames := mini(
		MOVEMENT_ROUTE_STATUS_MIN_PRESENTED_FRAMES,
		int(entry.get("route_status_presented_frames", 0)) + 1)
	entry["route_status_presented_frames"] = presented_frames
	if presented_frames >= MOVEMENT_ROUTE_STATUS_MIN_PRESENTED_FRAMES:
		entry["route_status_duration_started_msec"] = now
		_disconnect_route_status_draw()
	_movement_entries[serial] = entry


func _movement_entry_arrived(entry: Dictionary) -> bool:
	if bool(entry.get("interruption_pending", false)):
		return false
	if _game_state == null:
		return false
	if not _movement_entry_at_destinations(entry):
		return false
	# Route cleanup can trail the final authoritative placement by one rendered
	# frame.  When every member is already at the immutable command endpoint,
	# keeping the public receipt in PROGRESS creates a second reality: the bodies
	# have arrived but the HUD claims the route is still underway.  Exact endpoint
	# parity is terminal even if is_moving() still reflects that cleanup frame.
	if _movement_entry_exactly_at_destinations(entry):
		return true
	for subject_value in entry.get("subject_ids", []):
		if bool(_game_state.is_moving(str(subject_value))):
			return false
	return true


func _movement_entry_exactly_at_destinations(entry: Dictionary) -> bool:
	if _game_state == null:
		return false
	var destinations := entry.get("subject_destinations", {}) as Dictionary
	for subject_value in entry.get("subject_ids", []):
		var subject_id := str(subject_value)
		if not destinations.has(subject_id) \
				or not _game_state.characters.has(subject_id):
			return false
		var expected_value: Variant = destinations[subject_id]
		if not (expected_value is Vector3) \
				or _game_state.get_position(subject_id).distance_to(
					expected_value as Vector3) > 0.02:
			return false
	return not destinations.is_empty()


func _movement_entry_at_destinations(entry: Dictionary) -> bool:
	if _game_state == null:
		return false
	var destinations := entry.get("subject_destinations", {}) as Dictionary
	for subject_value in entry.get("subject_ids", []):
		var subject_id := str(subject_value)
		if not destinations.has(subject_id) \
				or not _game_state.characters.has(subject_id):
			return false
		var expected_value: Variant = destinations[subject_id]
		if not (expected_value is Vector3) \
				or _game_state.get_position(subject_id).distance_to(
					expected_value as Vector3) > 0.2:
			return false
	return not destinations.is_empty()


func _movement_entry_stopped_short(entry: Dictionary) -> bool:
	if _game_state == null:
		return true
	var destinations := entry.get("subject_destinations", {}) as Dictionary
	for subject_value in entry.get("subject_ids", []):
		var subject_id := str(subject_value)
		if _game_state.characters.has(subject_id) \
				and bool(_game_state.is_moving(subject_id)):
			return false
		if destinations.has(subject_id) and destinations[subject_id] is Vector3 \
				and _game_state.characters.has(subject_id) \
				and _game_state.get_position(subject_id).distance_to(
					destinations[subject_id] as Vector3) <= 0.2:
			continue
		return true
	return false


func _movement_entry_route_active(entry: Dictionary) -> bool:
	if _game_state == null:
		return false
	for subject_value in entry.get("subject_ids", []):
		var subject_id := str(subject_value)
		if not _game_state.characters.has(subject_id):
			continue
		if _game_state.has_method("is_navigation_route_active"):
			if bool(_game_state.call("is_navigation_route_active", subject_id)):
				return true
		elif bool(_game_state.is_moving(subject_id)):
			return true
	return false


func _sync_entries(count_sample: bool) -> void:
	var now_msec := Time.get_ticks_msec() # @rendering_only
	var now_tick := _scheduler_tick()
	var warning_to_complete: Array[String] = []
	for key_v in _warning_entries.keys():
		var key := str(key_v)
		var entry: Dictionary = _warning_entries[key]
		_sample_entry(entry, count_sample)
		_warning_entries[key] = entry
		var commit_tick := float((entry.get("receipt", {}) as Dictionary).get(
			"commit_tick", INF))
		if is_finite(commit_tick) and now_tick >= commit_tick:
			warning_to_complete.append(key)
	for key in warning_to_complete:
		_complete_warning(key)

	for key_v in _active_entries.keys():
		var key := str(key_v)
		var entry: Dictionary = _active_entries[key]
		var receipt: Dictionary = entry.get("receipt", {})
		var subject_id := str(receipt.get("subject_id", ""))
		var traversal_id := str(receipt.get("traversal_id", ""))
		if _game_state != null and not subject_id.is_empty() \
				and bool(_game_state.is_external_traversal_active(subject_id)):
			var live: Dictionary = _game_state.get_external_traversal_state(subject_id)
			if str(live.get("traversal_id", "")) == traversal_id:
				entry["progress"] = clampf(float(live.get("progress", 0.0)), 0.0, 1.0)
				var source_anchor_v: Variant = entry.get("source_anchor", null)
				if is_instance_valid(source_anchor_v) \
						and _game_state.has_method("get_render_position"):
					(source_anchor_v as Node3D).global_position = \
						_game_state.get_render_position(subject_id)
		_sample_entry(entry, count_sample)
		_active_entries[key] = entry

	var expired_recent: Array[String] = []
	for key_v in _recent_entries.keys():
		var key := str(key_v)
		var entry: Dictionary = _recent_entries[key]
		_sample_entry(entry, count_sample)
		_recent_entries[key] = entry
		if now_msec >= int(entry.get("recent_until_msec", 0)):
			expired_recent.append(key)
	for key in expired_recent:
		_discard_entry(_recent_entries, key)
	_prune_registered_sources()


func _complete_warning(key: String) -> void:
	if not _warning_entries.has(key):
		return
	var entry: Dictionary = _warning_entries[key]
	_warning_entries.erase(key)
	entry["phase"] = "arrival"
	entry["mode"] = "complete"
	entry["progress"] = 1.0
	entry["recent_until_msec"] = Time.get_ticks_msec() + RECENT_LIFETIME_MSEC # @rendering_only
	_set_link_phase(entry, "complete", true, true)
	_present_entry_on_portraits(entry)
	_replace_recent("warning|%s" % key, entry)
	_arrival_count += 1


func _create_entry(receipt: Dictionary, phase: String, mode: String) -> Dictionary:
	_visual_serial += 1
	var visual_root := Node3D.new()
	visual_root.name = "ConsequencePresentation_%d" % _visual_serial
	add_child(visual_root)
	var source_anchor := Node3D.new()
	source_anchor.name = "Cause"
	visual_root.add_child(source_anchor)
	var target_anchor := Node3D.new()
	target_anchor.name = "Effect"
	visual_root.add_child(target_anchor)
	source_anchor.global_position = _position_from_portable(receipt.get("source", []))
	target_anchor.global_position = _position_from_portable(receipt.get("destination", []))
	var link := CausalFeedbackLinkScript.new() as Node3D
	visual_root.add_child(link)
	var tint := _tint_for_mode(mode)
	var opts := {
		"name": "ConsequenceLink_%d" % _visual_serial,
		"label": str(receipt.get("label", "")),
		"path_style": "movement_chevrons",
		"flow_speed": 0.52 if mode == "warning" else 0.9,
		"feedback_mode": mode,
		"visibility_policy": "contextual",
		"show_label": bool(receipt.get("show_label", true)),
		"arc_height": 0.35,
		"draw_duration": 0.18,
	}
	var owner_character := str(receipt.get("subject_id", ""))
	if not owner_character.is_empty():
		opts["owner_character"] = owner_character
	# Immediate personal consequences default to visible truth. A source may explicitly opt into
	# party-perception gating for relationships that would otherwise reveal unseen world state.
	if bool(receipt.get("perception_gated", false)) and _visibility_query.is_valid():
		opts["visibility_query"] = _visibility_query
	link.call("configure", source_anchor, target_anchor, tint, opts)
	link.call("set_latched", true)
	if mode == "warning":
		link.call("flash", 1.0, 1.15)
	var feedback_state := link.call("get_feedback_state") as Dictionary
	var visible := bool(feedback_state.get("visible", false))
	var render_visible := bool(feedback_state.get("render_parts_visible", false))
	return {
		"receipt": receipt.duplicate(true),
		"phase": phase,
		"mode": mode,
		"visible": visible,
		"render_visible": render_visible,
		"progress": 0.0,
		"sample_count": 1,
		"visible_sample_count": 1 if visible else 0,
		"render_visible_sample_count": 1 if render_visible else 0,
		"restored": false,
		"visual_root": visual_root,
		"link": link,
		"source_anchor": source_anchor,
		"target_anchor": target_anchor,
	}


func _set_link_phase(entry: Dictionary, mode: String, latched: bool, pulse: bool) -> void:
	var link_v: Variant = entry.get("link", null)
	if not is_instance_valid(link_v):
		return
	var link := link_v as Node
	link.call("set_feedback_mode", mode)
	link.call("set_latched", latched)
	if pulse:
		link.call("pulse_arrival", 1.35, 1.05)
	elif mode == "failed":
		link.call("flash", 0.8, 1.1)


func _reset_entry_endpoints_to_receipt(entry: Dictionary) -> void:
	var receipt: Dictionary = entry.get("receipt", {})
	var source_anchor_v: Variant = entry.get("source_anchor", null)
	var target_anchor_v: Variant = entry.get("target_anchor", null)
	if is_instance_valid(source_anchor_v):
		(source_anchor_v as Node3D).global_position = _position_from_portable(
			receipt.get("source", []))
	if is_instance_valid(target_anchor_v):
		(target_anchor_v as Node3D).global_position = _position_from_portable(
			receipt.get("destination", []))


func _sample_entry(entry: Dictionary, count_sample: bool) -> void:
	var link_v: Variant = entry.get("link", null)
	var visible := false
	var render_visible := false
	if is_instance_valid(link_v):
		var feedback_state := (link_v as Node).call("get_feedback_state") as Dictionary
		visible = bool(feedback_state.get("visible", false))
		render_visible = bool(feedback_state.get("render_parts_visible", false))
	entry["visible"] = visible
	entry["render_visible"] = render_visible
	if count_sample:
		# A normal render/process sample may refresh a late-created HUD. The public
		# getter calls this function with false and must never create the evidence it
		# is about to report.
		_present_entry_on_portraits(entry)
		entry["sample_count"] = int(entry.get("sample_count", 0)) + 1
		if visible:
			entry["visible_sample_count"] = int(entry.get("visible_sample_count", 0)) + 1
		if render_visible:
			entry["render_visible_sample_count"] = int(
				entry.get("render_visible_sample_count", 0)) + 1


func _replace_recent(key: String, entry: Dictionary) -> void:
	_discard_entry(_recent_entries, key)
	_recent_entries[key] = entry


func _discard_entry(entries: Dictionary, key: String) -> void:
	if not entries.has(key):
		return
	var entry: Dictionary = entries[key]
	entries.erase(key)
	_free_entry_visuals(entry)


func _free_entry_visuals(entry: Dictionary) -> void:
	_clear_entry_from_portraits(entry)
	var visual_root_v: Variant = entry.get("visual_root", null)
	if is_instance_valid(visual_root_v):
		(visual_root_v as Node).queue_free()


func _entry_subject_ids(entry: Dictionary) -> Array[String]:
	var receipt := entry.get("receipt", {}) as Dictionary
	var result: Array[String] = []
	var primary := str(receipt.get("subject_id", "")).strip_edges().to_lower()
	if primary != "":
		result.append(primary)
	for subject_v in receipt.get("subjects", []):
		var subject := str(subject_v).strip_edges().to_lower()
		if subject != "" and not result.has(subject):
			result.append(subject)
	result.sort()
	return result


func _present_entry_on_portraits(entry: Dictionary) -> void:
	var portrait_presenter := _resolve_portrait_presenter()
	if portrait_presenter == null or not portrait_presenter.has_method(
				"set_portrait_consequence_presentation"):
		return
	var receipt := entry.get("receipt", {}) as Dictionary
	if not bool(receipt.get("show_label", true)):
		_clear_entry_from_portraits(entry)
		return
	for subject_id in _entry_subject_ids(entry):
		var presentation_key := _entry_portrait_presentation_key(entry, subject_id)
		if not bool(entry.get("visible", false)):
			portrait_presenter.call(
				"clear_portrait_consequence_presentation", subject_id,
				presentation_key)
			continue
		var presentation := {
			"presentation_key": presentation_key,
			"event_id": str(receipt.get("event_id", "")),
			"phase": str(entry.get("phase", "")),
			"label": str(receipt.get("label", "")),
			"destination_label": str(receipt.get("destination_label", "")),
			"progress": clampf(float(entry.get("progress", 0.0)), 0.0, 1.0),
		}
		portrait_presenter.call(
			"set_portrait_consequence_presentation", subject_id, presentation)


func _clear_entry_from_portraits(entry: Dictionary) -> void:
	var portrait_presenter := _resolve_portrait_presenter()
	if portrait_presenter == null or not portrait_presenter.has_method(
				"clear_portrait_consequence_presentation"):
		return
	for subject_id in _entry_subject_ids(entry):
		portrait_presenter.call(
			"clear_portrait_consequence_presentation", subject_id,
			_entry_portrait_presentation_key(entry, subject_id))


func _entry_portrait_render_visible_subjects(entry: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for subject_id_v in _entry_portrait_presentations(entry).keys():
		result.append(str(subject_id_v))
	result.sort()
	return result


func _entry_portrait_presentations(entry: Dictionary) -> Dictionary:
	var result := {}
	var portrait_presenter := _resolve_portrait_presenter()
	if portrait_presenter == null or not portrait_presenter.has_method(
				"get_portrait_consequence_presentation"):
		return result
	for subject_id in _entry_subject_ids(entry):
		var state_v: Variant = portrait_presenter.call(
			"get_portrait_consequence_presentation", subject_id,
			_entry_portrait_presentation_key(entry, subject_id))
		if state_v is Dictionary and bool((state_v as Dictionary).get(
				"render_visible", false)):
			result[subject_id] = (state_v as Dictionary).duplicate(true)
	return result


func _entry_portrait_render_visible(entry: Dictionary) -> bool:
	return not _entry_portrait_render_visible_subjects(entry).is_empty()


func _entry_portrait_presentation_key(entry: Dictionary,
		subject_id: String) -> String:
	var receipt := entry.get("receipt", {}) as Dictionary
	return "%s|%s|%s" % [
		str(receipt.get("event_id", "")),
		str(receipt.get("traversal_id", "")),
		subject_id,
	]


func _resolve_portrait_presenter() -> Node:
	if _portrait_presenter != null and is_instance_valid(_portrait_presenter):
		return _portrait_presenter
	_portrait_presenter = null
	if not _portrait_presenter_query.is_valid():
		return null
	var resolved_v: Variant = _portrait_presenter_query.call()
	if resolved_v is Node and is_instance_valid(resolved_v):
		_portrait_presenter = resolved_v as Node
	return _portrait_presenter


func _clear_all_entries() -> void:
	_disconnect_movement_phase_draw()
	_disconnect_route_status_draw()
	for entries in [_warning_entries, _active_entries, _recent_entries]:
		for entry_v in (entries as Dictionary).values():
			_free_entry_visuals(entry_v as Dictionary)
		(entries as Dictionary).clear()
	_active_traversal_keys.clear()
	_movement_entries.clear()
	if _movement_panel != null:
		_movement_panel.visible = false


func _discard_warning(event_id: String) -> void:
	_discard_entry(_warning_entries, event_id)


# --- Public-state projection ---------------------------------------------------------------

func _public_records(entries: Dictionary) -> Array:
	var result: Array = []
	for entry_v in entries.values():
		var entry := entry_v as Dictionary
		var receipt: Dictionary = entry.get("receipt", {})
		var portrait_presentations := _entry_portrait_presentations(entry)
		var portrait_render_visible_subjects: Array[String] = []
		for subject_id_v in portrait_presentations.keys():
			portrait_render_visible_subjects.append(str(subject_id_v))
		portrait_render_visible_subjects.sort()
		result.append({
			"phase": str(entry.get("phase", "")),
			"mode": str(entry.get("mode", "")),
			"visible": bool(entry.get("visible", false)),
			"render_visible": bool(entry.get("render_visible", false)),
			"portrait_render_visible": not portrait_render_visible_subjects.is_empty(),
			"portrait_render_visible_subjects": portrait_render_visible_subjects,
			"portrait_presentations": portrait_presentations,
			"event_id": str(receipt.get("event_id", "")),
			"cause_id": str(receipt.get("cause_id", "")),
			"cause_kind": str(receipt.get("cause_kind", "")),
			"effect_kind": str(receipt.get("effect_kind", "")),
			"cue_kind": str(receipt.get("cue_kind", "")),
			"label": str(receipt.get("label", "")),
			"show_label": bool(receipt.get("show_label", true)),
			"traversal_id": str(receipt.get("traversal_id", "")),
			"subject_id": str(receipt.get("subject_id", "")),
			"subjects": (receipt.get("subjects", []) as Array).duplicate(),
			"destination_label": str(receipt.get("destination_label", "")),
			"source": (receipt.get("source", []) as Array).duplicate(),
			"destination": (receipt.get("destination", []) as Array).duplicate(),
			"progress": clampf(float(entry.get("progress", 0.0)), 0.0, 1.0),
			"sample_count": int(entry.get("sample_count", 0)),
			"visible_sample_count": int(entry.get("visible_sample_count", 0)),
			"render_visible_sample_count": int(
				entry.get("render_visible_sample_count", 0)),
			"restored": bool(entry.get("restored", false)),
		})
	result.sort_custom(_public_record_less)
	return result


func _public_record_less(a: Dictionary, b: Dictionary) -> bool:
	var a_key := "%s|%s|%s" % [a.get("event_id", ""), a.get("subject_id", ""), a.get("phase", "")]
	var b_key := "%s|%s|%s" % [b.get("event_id", ""), b.get("subject_id", ""), b.get("phase", "")]
	return a_key < b_key


func _normalize_receipt(
		raw: Dictionary,
		subject_id: String,
		traversal_id: String,
		state: Dictionary,
		fallback_source: Vector3
	) -> Dictionary:
	if str(raw.get("scope", "")) != "player_facing":
		return {}
	for required in ["event_id", "cause_id", "cause_kind", "effect_kind", "cue_kind"]:
		if str(raw.get(required, "")).is_empty():
			return {}
	if bool(raw.get("show_label", true)) and str(raw.get("label", "")).is_empty():
		return {}
	var resolved_subject := str(raw.get("subject_id", subject_id))
	var subjects: Array = []
	var subjects_v: Variant = raw.get("subjects", [])
	if subjects_v is Array:
		for candidate in subjects_v as Array:
			var candidate_id := str(candidate)
			if not candidate_id.is_empty() and not subjects.has(candidate_id):
				subjects.append(candidate_id)
	if not resolved_subject.is_empty() and not subjects.has(resolved_subject):
		subjects.append(resolved_subject)
	var source_v: Variant = raw.get(
		"source_render_position", state.get("render_origin", fallback_source))
	var destination_v: Variant = raw.get(
		"destination_render_position", state.get("render_destination", source_v))
	var result := raw.duplicate(true)
	result["subject_id"] = resolved_subject
	result["subjects"] = subjects
	result["traversal_id"] = traversal_id
	result["source"] = _portable_position(source_v, fallback_source)
	result["destination"] = _portable_position(destination_v, fallback_source)
	result["destination_label"] = str(raw.get("destination_label", ""))
	return result


func _portable_position(value: Variant, fallback: Vector3) -> Array:
	var position := fallback
	if value is Vector3:
		position = value as Vector3
	elif value is Array and (value as Array).size() >= 3:
		position = Vector3(
			float((value as Array)[0]),
			float((value as Array)[1]),
			float((value as Array)[2])
		)
	elif value is Dictionary:
		position = Vector3(
			float((value as Dictionary).get("x", fallback.x)),
			float((value as Dictionary).get("y", fallback.y)),
			float((value as Dictionary).get("z", fallback.z))
		)
	if not position.is_finite():
		position = fallback if fallback.is_finite() else Vector3.ZERO
	return [position.x, position.y, position.z]


func _position_from_portable(value: Variant) -> Vector3:
	var portable := _portable_position(value, Vector3.ZERO)
	return Vector3(float(portable[0]), float(portable[1]), float(portable[2]))


# --- Runtime wiring / utility --------------------------------------------------------------

func _connect_runtime() -> void:
	if _game_state != null:
		_connect_signal(_game_state, "navigation_route_replanned", "_on_navigation_route_replanned")
		_connect_signal(_game_state, "external_traversal_started", "_on_external_traversal_started")
		_connect_signal(_game_state, "external_traversal_finished", "_on_external_traversal_finished")
		_connect_signal(_game_state, "external_traversal_cancelled", "_on_external_traversal_cancelled")
		_connect_signal(_game_state, "rest_started", "_on_rest_started")
		_connect_signal(_game_state, "rest_stopped", "_on_rest_stopped")
		_connect_signal(_game_state, "character_revived", "_on_character_revived")
		_connect_signal(_game_state, "night_skipped", "_on_night_skipped")
	var tree := get_tree()
	if tree != null:
		var added := Callable(self, "_on_tree_node_added")
		if not tree.node_added.is_connected(added):
			tree.node_added.connect(added)
		var removed := Callable(self, "_on_tree_node_removed")
		if not tree.node_removed.is_connected(removed):
			tree.node_removed.connect(removed)


func _disconnect_runtime() -> void:
	if _game_state != null:
		_disconnect_signal(_game_state, "navigation_route_replanned", "_on_navigation_route_replanned")
		_disconnect_signal(_game_state, "external_traversal_started", "_on_external_traversal_started")
		_disconnect_signal(_game_state, "external_traversal_finished", "_on_external_traversal_finished")
		_disconnect_signal(_game_state, "external_traversal_cancelled", "_on_external_traversal_cancelled")
		_disconnect_signal(_game_state, "rest_started", "_on_rest_started")
		_disconnect_signal(_game_state, "rest_stopped", "_on_rest_stopped")
		_disconnect_signal(_game_state, "character_revived", "_on_character_revived")
		_disconnect_signal(_game_state, "night_skipped", "_on_night_skipped")
	var tree := get_tree()
	if tree != null:
		var added := Callable(self, "_on_tree_node_added")
		if tree.node_added.is_connected(added):
			tree.node_added.disconnect(added)
		var removed := Callable(self, "_on_tree_node_removed")
		if tree.node_removed.is_connected(removed):
			tree.node_removed.disconnect(removed)
	for registration_v in _registered_sources.values():
		var registration := registration_v as Dictionary
		var source_v: Variant = registration.get("node", null)
		var callbacks_v: Variant = registration.get("callbacks", {})
		if not is_instance_valid(source_v) or not (callbacks_v is Dictionary):
			continue
		for signal_name_v in (callbacks_v as Dictionary).keys():
			var signal_name := StringName(str(signal_name_v))
			var callback_v: Variant = (callbacks_v as Dictionary)[signal_name_v]
			if callback_v is Callable and (callback_v as Callable).is_valid() \
					and (source_v as Node).has_signal(signal_name) \
					and (source_v as Node).is_connected(
						signal_name, callback_v as Callable):
				(source_v as Node).disconnect(signal_name, callback_v as Callable)
	_registered_sources.clear()


func _connect_signal(source: Object, signal_name: StringName, method_name: StringName) -> void:
	if source == null or not source.has_signal(signal_name):
		return
	var callback := Callable(self, method_name)
	if not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


func _disconnect_signal(source: Object, signal_name: StringName, method_name: StringName) -> void:
	if source == null or not source.has_signal(signal_name):
		return
	var callback := Callable(self, method_name)
	if source.is_connected(signal_name, callback):
		source.disconnect(signal_name, callback)


func _register_source_tree(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		register_source(node)
		for child in node.get_children():
			pending.append(child)


func _on_tree_node_added(node: Node) -> void:
	if _search_root == null or not is_instance_valid(_search_root):
		return
	if node == _search_root or _search_root.is_ancestor_of(node):
		register_source(node)


func _on_tree_node_removed(node: Node) -> void:
	if node == null:
		return
	var source_id := node.get_instance_id()
	_registered_sources.erase(source_id)
	var stale_warning: Array[String] = []
	for key_v in _warning_entries.keys():
		var key := str(key_v)
		if int((_warning_entries[key] as Dictionary).get("source_owner_id", 0)) == source_id:
			stale_warning.append(key)
	for key in stale_warning:
		_discard_entry(_warning_entries, key)


func _prune_registered_sources() -> void:
	var stale: Array = []
	for source_id in _registered_sources.keys():
		var source_v: Variant = (_registered_sources[source_id] as Dictionary).get("node", null)
		if not is_instance_valid(source_v):
			stale.append(source_id)
	for source_id in stale:
		_registered_sources.erase(source_id)


func _announce_once(key: String, text: String, duration: float) -> void:
	if text.strip_edges().is_empty() or _restoring_authority or _announced_keys.has(key):
		return
	_remember_announcement(key)
	if _message_sink.is_valid():
		_message_sink.call(text, duration)
		_toast_count += 1


func _remember_announcement(key: String) -> void:
	if _announced_keys.has(key):
		return
	_announced_keys[key] = true
	_announced_order.append(key)
	while _announced_order.size() > MAX_ANNOUNCED_KEYS:
		var retired: String = str(_announced_order.pop_front())
		_announced_keys.erase(retired)


func _scheduler_tick() -> float:
	if _game_state != null and _game_state.get("scheduler") != null:
		return float(_game_state.get("scheduler").get_current_tick())
	return 0.0


func _callable_option(opts: Dictionary, key: String) -> Callable:
	var value: Variant = opts.get(key, Callable())
	return value as Callable if value is Callable else Callable()


func _active_key(subject_id: String, traversal_id: String, event_id: String) -> String:
	return "%s|%s|%s" % [event_id, subject_id, traversal_id]


func _traversal_key(subject_id: String, traversal_id: String) -> String:
	return "%s|%s" % [subject_id, traversal_id]


func _tint_for_mode(mode: String) -> Color:
	match mode:
		"warning":
			return WARNING_TINT
		"active":
			return ACTIVE_TINT
		"complete":
			return COMPLETE_TINT
		"failed":
			return FAILED_TINT
		_:
			return ACTIVE_TINT


func _exit_tree() -> void:
	cancel_emphasis()
	_clear_all_entries()
	_disconnect_runtime()
