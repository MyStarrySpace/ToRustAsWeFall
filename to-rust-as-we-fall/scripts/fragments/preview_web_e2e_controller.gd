class_name PreviewWebE2EController
extends Node

## Read-only browser-release observation controller. It is dormant unless the Web build was
## launched with the explicit ?e2e=1 query and intentionally exposes no command or mutation API.

const PlayerObservationControllerScript := preload(
	"res://scripts/testing/player_observation_controller.gd")
const ContentFingerprintScript := preload(
	"res://scripts/testing/content_fingerprint.gd")
const MovementContinuityTrackerScript := preload(
	"res://scripts/testing/movement_continuity_tracker.gd")
const MovementAuthoritySnapshotScript := preload(
	"res://scripts/testing/movement_authority_snapshot.gd")
const BASIN_FRAGMENT_RESOURCE := "res://data/fragments/basin_fill_proof.tres"

var _context_provider: Callable
var _character_ids: Array[String] = []

var _game_state = null
var _characters: Dictionary = {}
var _active_chunk: Node3D = null
var _preview_interactables: Array = []
var _camera: Camera3D = null
var _active_preview_entry_id := ""
var preview_chunk := ""
var _active_char_id := ""
var _selected_char_ids: Array = []
var _scheduler = null
var _anchor_positions: Dictionary = {}
var _consequence_presentation_controller = null
var _player_observation_controller: Node = null

var _web_e2e_checked := false
var _web_e2e_enabled := false
var _web_e2e_bridge = null
var _web_e2e_publish_elapsed := 0.0
var _web_e2e_move_refusals: Array[String] = []
var _web_e2e_max_position_error: Dictionary = {}
var _web_e2e_max_transform_error: Dictionary = {}
var _web_e2e_transform_sample_counts: Dictionary = {}
var _web_e2e_max_movement_position_error: Dictionary = {}
var _web_e2e_max_movement_transform_error: Dictionary = {}
var _web_e2e_movement_transform_sample_counts: Dictionary = {}
var _web_e2e_projection_error: Dictionary = {}
var _web_e2e_max_projection_error: Dictionary = {}
var _web_e2e_projection_valid: Dictionary = {}
var _web_e2e_max_movement_projection_error: Dictionary = {}
var _web_e2e_movement_projection_valid: Dictionary = {}
var _web_e2e_last_levels: Dictionary = {}
var _web_e2e_last_cells: Dictionary = {}
var _web_e2e_pending_navigation_edges: Dictionary = {}
var _web_e2e_level_transitions: Dictionary = {}
var _web_e2e_content_fingerprint: Dictionary = {}
var _web_e2e_gameplay_build_fingerprint: Dictionary = {}
var _web_e2e_movement_continuity = MovementContinuityTrackerScript.new()
var _web_e2e_continuity_game_state = null
var _web_e2e_continuity_entry_id := ""


func setup(context_provider: Callable, character_ids: Array) -> void:
	_context_provider = context_provider
	_character_ids.assign(character_ids)
	# The browser and native persona layers share one presentation-only observation
	# adapter. Its snapshot contains opaque screen affordances and visible HUD/cue
	# state; authored anchors, world coordinates, navigation internals, and test
	# receipts remain outside the policy boundary.
	_player_observation_controller = PlayerObservationControllerScript.new()
	_player_observation_controller.name = "WebPlayerObservationController"
	add_child(_player_observation_controller)
	_player_observation_controller.setup(get_parent())


func is_enabled() -> bool:
	return _web_e2e_enabled


func record_move_refusal(char_id: String, reason: String) -> void:
	if _web_e2e_enabled:
		_web_e2e_move_refusals.append("%s: %s" % [char_id, reason])


func _refresh_context() -> void:
	if not _context_provider.is_valid():
		return
	var context_v: Variant = _context_provider.call()
	if not (context_v is Dictionary):
		return
	var context := context_v as Dictionary
	var next_game_state = context.get("game_state", null)
	var next_entry_id := str(context.get("active_preview_entry_id", ""))
	if next_game_state != _web_e2e_continuity_game_state \
			or next_entry_id != _web_e2e_continuity_entry_id:
		_web_e2e_continuity_game_state = next_game_state
		_web_e2e_continuity_entry_id = next_entry_id
		# Chunk/spawn construction is outside the measured browser journey. The
		# first presented frame of each new gameplay authority becomes the immutable
		# origin baseline; later movement must prove its own continuity. Every legacy
		# movement/transition accumulator changes identity atomically with that root.
		_web_e2e_reset_authority_ledgers()
	_game_state = next_game_state
	_characters = context.get("characters", {}) as Dictionary
	_active_chunk = context.get("active_chunk", null) as Node3D
	_preview_interactables = context.get("preview_interactables", []) as Array
	_camera = context.get("camera", null) as Camera3D
	_active_preview_entry_id = next_entry_id
	preview_chunk = str(context.get("preview_chunk", ""))
	_active_char_id = str(context.get("active_char_id", ""))
	_selected_char_ids = context.get("selected_char_ids", []) as Array
	_scheduler = context.get("scheduler", null)
	_anchor_positions = context.get("anchor_positions", {}) as Dictionary
	_consequence_presentation_controller = context.get(
		"consequence_presentation_controller", null)


func _web_e2e_reset_authority_ledgers() -> void:
	_web_e2e_publish_elapsed = 0.0
	_web_e2e_content_fingerprint.clear()
	_web_e2e_move_refusals.clear()
	_web_e2e_max_position_error.clear()
	_web_e2e_max_transform_error.clear()
	_web_e2e_transform_sample_counts.clear()
	_web_e2e_max_movement_position_error.clear()
	_web_e2e_max_movement_transform_error.clear()
	_web_e2e_movement_transform_sample_counts.clear()
	_web_e2e_projection_error.clear()
	_web_e2e_max_projection_error.clear()
	_web_e2e_projection_valid.clear()
	_web_e2e_max_movement_projection_error.clear()
	_web_e2e_movement_projection_valid.clear()
	_web_e2e_last_levels.clear()
	_web_e2e_last_cells.clear()
	_web_e2e_pending_navigation_edges.clear()
	_web_e2e_level_transitions.clear()
	_web_e2e_movement_continuity.reset(_character_ids)


func update(delta: float) -> void:
	if not _web_e2e_checked:
		_web_e2e_checked = true
		if OS.has_feature("web") and _web_e2e_query_value("e2e") == "1":
			_web_e2e_bridge = Engine.get_singleton("JavaScriptBridge")
			_web_e2e_enabled = _web_e2e_bridge != null
	if not _web_e2e_enabled:
		return
	_refresh_context()
	_sample_web_e2e_presenter_state()
	_web_e2e_publish_elapsed += delta
	if _web_e2e_publish_elapsed < 0.1:
		return
	_web_e2e_publish_elapsed = 0.0
	_publish_web_e2e_state()


## Sample every presented frame, not only the throttled JavaScript publication.
## The browser contract can therefore reject a transient below-floor presenter
## even when it snaps back before the next checkpoint assertion.
func _sample_web_e2e_presenter_state() -> void:
	if _game_state == null:
		return
	for char_id in _character_ids:
		if not _game_state.characters.has(char_id):
			continue
		var character_node: Node3D = _characters.get(char_id, null) as Node3D
		if character_node == null or not is_instance_valid(character_node):
			continue
		var logical_position: Vector3 = _game_state.get_position(char_id)
		var expected: Vector3 = _game_state.get_render_position(char_id)
		var position_error := character_node.global_position.distance_to(expected)
		var transform_error := character_node.global_transform.origin.distance_to(expected)
		_web_e2e_max_position_error[char_id] = maxf(
			float(_web_e2e_max_position_error.get(char_id, 0.0)),
			position_error
		)
		_web_e2e_max_transform_error[char_id] = maxf(
			float(_web_e2e_max_transform_error.get(char_id, 0.0)),
			transform_error
		)
		_web_e2e_transform_sample_counts[char_id] = \
			int(_web_e2e_transform_sample_counts.get(char_id, 0)) + 1
		var projection_receipt := _web_e2e_logical_render_projection_receipt(
			char_id, logical_position, expected)
		var projection_error := float(projection_receipt.get("error", 1000000.0))
		var projection_valid := bool(projection_receipt.get("valid", false))
		_web_e2e_projection_error[char_id] = projection_error
		_web_e2e_max_projection_error[char_id] = maxf(
			float(_web_e2e_max_projection_error.get(char_id, 0.0)),
			projection_error
		)
		_web_e2e_projection_valid[char_id] = \
			bool(_web_e2e_projection_valid.get(char_id, true)) and projection_valid
		var movement_in_flight := _web_e2e_character_in_flight(char_id)
		var motion_authority := MovementAuthoritySnapshotScript.capture(
			_game_state, char_id, logical_position, expected)
		_web_e2e_movement_continuity.sample({
			"character_id": char_id,
			"scheduler_tick": float(_scheduler.get_current_tick()) \
				if _scheduler != null else 0.0,
			"presented_frame": int(Engine.get_process_frames()),
			"in_flight": movement_in_flight,
			"logical_position": logical_position,
			"render_position": expected,
			"presented_position": character_node.global_position,
			"presented_transform_origin": character_node.global_transform.origin,
			"logical_to_render_projection_valid": projection_valid,
			"logical_to_render_projection_error": projection_error,
			"declared_local_speed_bound": \
				MovementAuthoritySnapshotScript.declared_speed_bound(
					motion_authority),
			"motion_authority": motion_authority,
			"movement_provenance": _web_e2e_movement_provenance(char_id),
			# Basin has no portal. No discontinuity receipt is synthesized from names,
			# endpoints, or traversal ids; every Basin displacement must be continuous.
			"portal_discontinuity": {},
		})
		if movement_in_flight:
			_web_e2e_movement_transform_sample_counts[char_id] = \
				int(_web_e2e_movement_transform_sample_counts.get(char_id, 0)) + 1
			_web_e2e_max_movement_position_error[char_id] = maxf(
				float(_web_e2e_max_movement_position_error.get(char_id, 0.0)),
				position_error
			)
			_web_e2e_max_movement_transform_error[char_id] = maxf(
				float(_web_e2e_max_movement_transform_error.get(char_id, 0.0)),
				transform_error
			)
			_web_e2e_max_movement_projection_error[char_id] = maxf(
				float(_web_e2e_max_movement_projection_error.get(char_id, 0.0)),
				projection_error
			)
			_web_e2e_movement_projection_valid[char_id] = \
				bool(_web_e2e_movement_projection_valid.get(char_id, true)) \
				and projection_valid
		var level := int(_game_state.get_character_level(char_id))
		var cell := Vector2i.ZERO
		var active_navigation_edge: Dictionary = {}
		if _game_state.grid != null:
			cell = _game_state.grid.world_to_grid(_game_state.get_position(char_id))
			var traversal_state: Dictionary = _game_state.get_external_traversal_state(char_id)
			active_navigation_edge = traversal_state.get("navigation_edge", {}) as Dictionary
			if not active_navigation_edge.is_empty():
				_web_e2e_pending_navigation_edges[char_id] = \
					active_navigation_edge.duplicate(true)
				if not _web_e2e_last_cells.has(char_id):
					_web_e2e_last_cells[char_id] = active_navigation_edge.get(
						"from_cell", cell)
		var level_changed := _web_e2e_last_levels.has(char_id) \
			and int(_web_e2e_last_levels[char_id]) != level
		if level_changed \
				and _game_state.grid != null:
			var from_level := int(_web_e2e_last_levels[char_id])
			var from_cell: Vector2i = _web_e2e_last_cells.get(char_id, cell)
			var executed_edge: Dictionary = _web_e2e_pending_navigation_edges.get(
				char_id, {}) as Dictionary
			var attributed_edge: Dictionary = {}
			# The typed edge executor validates this source vertex before the traversal starts.
			# Preserve that receipt rather than sampling an interpolated XZ position halfway up
			# an offset ladder; the destination remains the authoritative arrival cell below.
			if not executed_edge.is_empty() \
					and int(executed_edge.get("from_level", -1)) == from_level \
					and int(executed_edge.get("to_level", -1)) == level \
					and executed_edge.get("from_cell", null) is Vector2i \
					and executed_edge.get("to_cell", null) is Vector2i \
					and (executed_edge.get("to_cell") as Vector2i) == cell:
				from_cell = executed_edge.get("from_cell", from_cell) as Vector2i
				attributed_edge = executed_edge
			var transitions: Array = _web_e2e_level_transitions.get(char_id, [])
			transitions.append({
				"from_cell": _web_e2e_vector2i(from_cell),
				"from_level": from_level,
				"to_cell": _web_e2e_vector2i(cell),
				"to_level": level,
				"edge_category": str(attributed_edge.get("category", "")),
				"edge_kind": str(attributed_edge.get("kind", "")),
				"edge_type": str(attributed_edge.get("type", "")),
			})
			_web_e2e_level_transitions[char_id] = transitions
			_web_e2e_pending_navigation_edges.erase(char_id)
		elif active_navigation_edge.is_empty():
			# A connector receipt is causal evidence for this traversal only. If the
			# traversal ends or is cancelled without changing level, it cannot be
			# retained and silently attributed to some later level change.
			_web_e2e_pending_navigation_edges.erase(char_id)
		_web_e2e_last_levels[char_id] = level
		if active_navigation_edge.is_empty():
			_web_e2e_last_cells[char_id] = cell


## Prove get_render_position is a projection of DATA/logical truth instead of allowing the
## presenter and a second render getter to agree with the same bad offset. External traversals
## publish both sides of their authored mapping; coordinate-mapped chunks use their full-XYZ map.
func _web_e2e_logical_render_projection_receipt(
		char_id: String, logical_position: Vector3, render_position: Vector3) -> Dictionary:
	var valid := logical_position.is_finite() and render_position.is_finite()
	var projection_error := 0.0
	if _game_state.is_external_traversal_active(char_id):
		var traversal_state: Dictionary = _game_state.get_external_traversal_state(char_id)
		var data_projection_v: Variant = traversal_state.get("data_position", null)
		var render_projection_v: Variant = traversal_state.get("render_position", null)
		if data_projection_v is Vector3 and render_projection_v is Vector3:
			var data_projection := data_projection_v as Vector3
			var render_projection := render_projection_v as Vector3
			valid = valid and data_projection.is_finite() and render_projection.is_finite()
			projection_error = maxf(
				data_projection.distance_to(logical_position),
				render_projection.distance_to(render_position)
			)
		else:
			valid = false
			projection_error = 1000000.0
	elif _game_state.coord_map != null and _game_state.coord_map.has_method("to_world"):
		var mapped_position_v: Variant = _game_state.coord_map.call(
			"to_world", logical_position)
		if mapped_position_v is Vector3:
			var mapped_position := mapped_position_v as Vector3
			valid = valid and mapped_position.is_finite()
			projection_error = mapped_position.distance_to(render_position)
		else:
			valid = false
			projection_error = 1000000.0
	else:
		projection_error = logical_position.distance_to(render_position)
	return {"error": projection_error, "valid": valid}


func _web_e2e_character_in_flight(char_id: String) -> bool:
	var navigation_route_active := bool(_game_state.call(
		"is_navigation_route_active", char_id)) \
		if _game_state.has_method("is_navigation_route_active") else false
	return navigation_route_active \
		or bool(_game_state.is_moving(char_id)) \
		or bool(_game_state.is_dodging(char_id)) \
		or bool(_game_state.is_external_traversal_active(char_id))


func _web_e2e_movement_provenance(char_id: String) -> Dictionary:
	if _game_state == null or not _game_state.characters.has(char_id):
		return {}
	if _game_state.is_external_traversal_active(char_id):
		var traversal := _game_state.get_external_traversal_state(char_id) as Dictionary
		var navigation_edge := traversal.get("navigation_edge", {}) as Dictionary
		if not navigation_edge.is_empty():
			return {
				"category": str(navigation_edge.get("category", "navigation_edge")),
				"kind": str(navigation_edge.get("kind", "")),
				"type": str(navigation_edge.get("type", "")).to_lower(),
			}
		var presentation := traversal.get("presentation_receipt", {}) as Dictionary
		if not presentation.is_empty():
			return {
				"category": "external_traversal",
				"kind": str(presentation.get("effect_kind", "")),
				"type": str(presentation.get("cue_kind", "")),
			}
		return {
			"category": "external_traversal",
			"kind": "continuous",
			"type": "authored_path",
		}
	if bool(_game_state.is_moving(char_id)) \
			or (_game_state.has_method("is_navigation_route_active") \
				and bool(_game_state.call("is_navigation_route_active", char_id))):
		return {
			"category": "navigation",
			"kind": "continuous_route",
			"type": "walk",
		}
	return {}


func _web_e2e_query_value(name: String) -> String:
	var bridge := Engine.get_singleton("JavaScriptBridge")
	if bridge == null:
		return ""
	return str(bridge.call(
		"eval",
		"new URLSearchParams(window.location.search).get('%s') || ''" % name,
		true
	))


func _publish_web_e2e_state() -> void:
	if _web_e2e_bridge == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var chunk_state: Dictionary = {}
	if _active_chunk != null and is_instance_valid(_active_chunk) \
			and _active_chunk.has_method("get_preview_state"):
		chunk_state = _active_chunk.call("get_preview_state")
	var character_state := {}
	for char_id in _character_ids:
		if _game_state == null or not _game_state.characters.has(char_id):
			continue
		var logical_position: Vector3 = _game_state.get_position(char_id)
		var expected_render_position: Vector3 = _game_state.get_render_position(char_id)
		var presented_position: Variant = null
		var presented_transform_origin: Variant = null
		var character_node: Node3D = _characters.get(char_id, null) as Node3D
		if character_node != null and is_instance_valid(character_node):
			presented_position = _web_e2e_vector3(character_node.global_position)
			presented_transform_origin = _web_e2e_vector3(
				character_node.global_transform.origin)
		var committed := _web_e2e_character_in_flight(char_id)
		character_state[char_id] = {
			# Backward-compatible alias for existing browser journeys. New contracts keep
			# simulation truth and the actual scene presenter separate so one cannot prove itself.
			"position": _web_e2e_vector3(expected_render_position),
			"logical_position": _web_e2e_vector3(logical_position),
			"expected_render_position": _web_e2e_vector3(expected_render_position),
			"presented_position": presented_position,
			"presented_transform_origin": presented_transform_origin,
			"max_presented_position_error": float(
				_web_e2e_max_position_error.get(char_id, 0.0)),
			"max_presented_transform_error": float(
				_web_e2e_max_transform_error.get(char_id, 0.0)),
			"transform_sample_count": int(
				_web_e2e_transform_sample_counts.get(char_id, 0)),
			# Boot/idle frames deliberately do not increment these counters. Browser journeys
			# snapshot one at command acceptance and require later growth before arrival.
			"movement_transform_sample_count": int(
				_web_e2e_movement_transform_sample_counts.get(char_id, 0)),
			"in_flight_transform_sample_count": int(
				_web_e2e_movement_transform_sample_counts.get(char_id, 0)),
			"max_movement_presented_position_error": float(
				_web_e2e_max_movement_position_error.get(char_id, 0.0)),
			"max_movement_presented_transform_error": float(
				_web_e2e_max_movement_transform_error.get(char_id, 0.0)),
			"logical_to_render_projection_error": float(
				_web_e2e_projection_error.get(char_id, 1000000.0)),
			"max_logical_to_render_projection_error": float(
				_web_e2e_max_projection_error.get(char_id, 1000000.0)),
			"logical_to_render_projection_valid": bool(
				_web_e2e_projection_valid.get(char_id, false)),
			"max_movement_logical_to_render_projection_error": float(
				_web_e2e_max_movement_projection_error.get(char_id, 1000000.0)),
			"movement_logical_to_render_projection_valid": bool(
				_web_e2e_movement_projection_valid.get(char_id, false)),
			# Additive v1 receipt; all legacy movement counters above remain stable.
			"movement_continuity": _web_e2e_movement_continuity.receipt(char_id),
			"level_transitions": (_web_e2e_level_transitions.get(char_id, []) as Array).duplicate(true),
			"level": int(_game_state.get_character_level(char_id)),
			"moving": bool(_game_state.is_moving(char_id)),
			"committed": committed,
			"downed": bool(_game_state.is_downed(char_id)),
		}
	var anchors := _anchor_positions.duplicate(true)
	var float_entry: Vector3 = anchors.get("float_entry", Vector3(8.25, 2.7, -0.75))
	var west_ladder: Vector3 = anchors.get("west_stair", Vector3(0.75, 0.5, -0.75))
	# Aim at authored upper-deck geometry immediately beyond the nearby west ladder. This is the
	# shortest truthful climb from spawn; crossing the whole deck first adds no new decision.
	var upper_deck := Vector3(west_ladder.x, float_entry.y, west_ladder.z)
	var console := _web_e2e_interactable("FlowReadConsole")
	var shelter := _web_e2e_interactable("BasinExitShelter")
	var assist_armed := false
	var assist_phase := "idle"
	if _active_chunk != null and _active_chunk.has_method("assists"):
		for assist_v in (_active_chunk.call("assists") as Array):
			if is_instance_valid(assist_v) and assist_v.has_method("is_read_armed"):
				assist_armed = bool(assist_v.call("is_read_armed"))
				if assist_v.has_method("get_read_phase"):
					assist_phase = str(assist_v.call("get_read_phase"))
				break
	var content_fingerprint := _web_e2e_content_fingerprint_result()
	var gameplay_build_fingerprint := _web_e2e_gameplay_build_fingerprint_result()
	var payload := {
		"version": 1,
		"stage": "fragment",
		"ready": _active_chunk != null and is_instance_valid(_active_chunk),
		"fragment": _active_preview_entry_id,
		"preview_chunk": preview_chunk,
		# Provenance lives outside player_observation_v1 and is never policy input.
		# The browser consumes the exact shared Godot result rather than re-hashing
		# a platform-specific scene representation in JavaScript.
		"content_fingerprint_schema": str(content_fingerprint.get(
			"content_fingerprint_schema", "")),
		"content_fingerprint": str(content_fingerprint.get(
			"content_fingerprint", "")),
		"gameplay_build_fingerprint_schema": str(gameplay_build_fingerprint.get(
			"gameplay_build_fingerprint_schema", "")),
		"gameplay_build_fingerprint": str(gameplay_build_fingerprint.get(
			"gameplay_build_fingerprint", "")),
		"viewport": {"width": viewport_size.x, "height": viewport_size.y},
		"active_character": _active_char_id,
		"selected_characters": _selected_char_ids.duplicate(),
		"paused": _scheduler != null and _scheduler.is_paused(),
		"characters": character_state,
		"chunk": chunk_state,
		"assist_armed": assist_armed,
		"assist_phase": assist_phase,
		"consequence_feedback": _web_e2e_consequence_feedback(),
		"player_observation": _web_e2e_player_observation(),
		"anchors": _web_e2e_authored_anchors(),
		"move_refusals": _web_e2e_move_refusals.duplicate(),
		"ladder_cells": _web_e2e_ladder_cells(),
		"ladder_edges": _web_e2e_ladder_edges(),
		"click_targets": {
			"upper_deck": _web_e2e_project(upper_deck),
			"start_return": _web_e2e_project_authored_anchor("start_return"),
			"bowl_center": _web_e2e_project_authored_anchor("bowl_center"),
			"failure_bowl": _web_e2e_project_authored_anchor("failure_bowl"),
			# The pedestal/screen volume is independently visible above the console's interaction root.
			# Aim there so a misplaced collider cannot make an invisible root-only click pass this test.
			"flow_read_console": _web_e2e_project_node(console, Vector3.UP * 0.65),
			"exit_shelter": _web_e2e_project_node(shelter),
		},
	}
	_web_e2e_bridge.call(
		"eval",
		"window.__trawfE2E = %s;" % JSON.stringify(payload),
		true
	)


func _web_e2e_content_fingerprint_result() -> Dictionary:
	if not _web_e2e_content_fingerprint.is_empty():
		return _web_e2e_content_fingerprint.duplicate(true)
	var result: Dictionary = {}
	if _active_preview_entry_id == "basin_fill_proof":
		result = ContentFingerprintScript.authored_fragment_resource(
			BASIN_FRAGMENT_RESOURCE)
	elif _active_chunk != null and is_instance_valid(_active_chunk) \
			and _active_chunk.has_method("get_generation_spec"):
		var specification_v: Variant = _active_chunk.call("get_generation_spec")
		if specification_v is Dictionary and not (specification_v as Dictionary).is_empty():
			result = ContentFingerprintScript.generated_spec(
				specification_v as Dictionary)
	else:
		return {}
	if not bool(result.get("ok", false)):
		push_error("Web E2E content fingerprint failed: %s" % str(
			result.get("error", "unknown error")))
		return {}
	_web_e2e_content_fingerprint = {
		"content_fingerprint_schema": str(result.get(
			"content_fingerprint_schema", "")),
		"content_fingerprint": str(result.get("content_fingerprint", "")),
	}
	return _web_e2e_content_fingerprint.duplicate(true)


func _web_e2e_gameplay_build_fingerprint_result() -> Dictionary:
	if not _web_e2e_gameplay_build_fingerprint.is_empty():
		return _web_e2e_gameplay_build_fingerprint.duplicate(true)
	var result: Dictionary = ContentFingerprintScript.gameplay_build()
	if not bool(result.get("ok", false)):
		push_error("Web E2E gameplay build fingerprint failed: %s" % str(
			result.get("error", "unknown error")))
		return {}
	_web_e2e_gameplay_build_fingerprint = {
		"gameplay_build_fingerprint_schema": str(result.get(
			"gameplay_build_fingerprint_schema", "")),
		"gameplay_build_fingerprint": str(result.get(
			"gameplay_build_fingerprint", "")),
	}
	return _web_e2e_gameplay_build_fingerprint.duplicate(true)


func _web_e2e_player_observation() -> Dictionary:
	if _player_observation_controller == null \
			or not is_instance_valid(_player_observation_controller):
		return {}
	var observation_v: Variant = _player_observation_controller.snapshot()
	if observation_v is Dictionary:
		return (observation_v as Dictionary).duplicate(true)
	return {}


## Semantic feedback only: browser journeys can verify that a visible consequence receipt exists,
## but the bridge never gains a method for commanding or acknowledging that consequence.
func _web_e2e_consequence_feedback() -> Dictionary:
	if _consequence_presentation_controller == null \
			or not is_instance_valid(_consequence_presentation_controller) \
			or not _consequence_presentation_controller.has_method("get_presentation_state"):
		return {}
	var state_v: Variant = _consequence_presentation_controller.call("get_presentation_state")
	if state_v is Dictionary:
		return (state_v as Dictionary).duplicate(true)
	return {}


## Only authored anchors are surfaced. Missing keys stay missing/hidden instead of silently gaining
## inferred coordinates that could let a browser proof pass against a destination the level did not author.
func _web_e2e_authored_anchors() -> Dictionary:
	var result: Dictionary = {}
	for anchor_name in ["start_return", "bowl_center", "failure_bowl"]:
		var position_v: Variant = _anchor_positions.get(anchor_name, null)
		if position_v is Vector3 and (position_v as Vector3).is_finite():
			result[anchor_name] = _web_e2e_vector3(position_v as Vector3)
	return result


func _web_e2e_project_authored_anchor(anchor_name: String) -> Dictionary:
	var position_v: Variant = _anchor_positions.get(anchor_name, null)
	if not (position_v is Vector3) or not (position_v as Vector3).is_finite():
		return {"visible": false}
	return _web_e2e_project(position_v as Vector3)


func _web_e2e_ladder_cells() -> Array:
	var result: Array = []
	if _active_chunk == null or not is_instance_valid(_active_chunk) \
			or not _active_chunk.has_method("get_grid_data"):
		return result
	var grid_data: Dictionary = _active_chunk.call("get_grid_data")
	for link_v in grid_data.get("links", []):
		var link := link_v as Dictionary
		if str(link.get("type", "")) != "ladder":
			continue
		var raw_cell: Array = link.get("cell", []) as Array
		if raw_cell.size() >= 2:
			result.append({"x": int(raw_cell[0]), "y": int(raw_cell[1])})
	return result


## Directional runtime graph receipts. Each endpoint is exported separately so a browser
## transition must match the actual connected edge, not merely share a ladder's XZ cell.
func _web_e2e_ladder_edges() -> Array:
	var result: Array = []
	if _game_state == null or _game_state.grid == null:
		return result
	var grid: GridWorld = _game_state.grid
	for edge_v in grid.inter_level_links.values():
		if not (edge_v is Dictionary):
			continue
		var edge := edge_v as Dictionary
		if str(edge.get("type", "")).to_lower() != "ladder":
			continue
		var from_cell_v: Variant = edge.get("from_cell", null)
		var to_cell_v: Variant = edge.get("to_cell", null)
		if not (from_cell_v is Vector2i) or not (to_cell_v is Vector2i):
			continue
		var from_cell := from_cell_v as Vector2i
		var to_cell := to_cell_v as Vector2i
		var from_level := int(edge.get("from_level", -1))
		var to_level := int(edge.get("to_level", -1))
		# This is structural graph connectivity, deliberately independent of a temporary
		# dynamic blocker such as rising water after the ladder was already traversed.
		var from_walkable := from_level >= 0 and from_level < grid.level_count \
			and grid.get_tile(from_cell.x, from_cell.y) != GridWorld.Tile.WALL \
			and grid.is_cell_allowed_on_level(from_cell, from_level)
		var to_walkable := to_level >= 0 and to_level < grid.level_count \
			and grid.get_tile(to_cell.x, to_cell.y) != GridWorld.Tile.WALL \
			and grid.is_cell_allowed_on_level(to_cell, to_level)
		result.append({
			"id": "%d,%d,%d>%d,%d,%d" % [
				from_cell.x, from_cell.y, from_level,
				to_cell.x, to_cell.y, to_level,
			],
			"kind": str(edge.get("kind", "")),
			"type": str(edge.get("type", "")).to_lower(),
			"annotation": "ladder",
			"from_cell": _web_e2e_vector2i(from_cell),
			"from_level": from_level,
			"to_cell": _web_e2e_vector2i(to_cell),
			"to_level": to_level,
			"from_walkable": from_walkable,
			"to_walkable": to_walkable,
			"connected": from_walkable and to_walkable,
		})
	result.sort_custom(_web_e2e_edge_receipt_less)
	return result


func _web_e2e_edge_receipt_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("id", "")) < str(b.get("id", ""))


func _web_e2e_vector2i(value: Vector2i) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _web_e2e_interactable(target_name: String) -> Node3D:
	for interactable_v in _preview_interactables:
		if interactable_v is Node3D and is_instance_valid(interactable_v) \
				and str(interactable_v.name) == target_name:
			return interactable_v as Node3D
	return null


func _web_e2e_project_node(target: Node3D, offset := Vector3.ZERO) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {"visible": false}
	return _web_e2e_project(target.global_position + offset)


func _web_e2e_project(world_position: Vector3) -> Dictionary:
	if _camera == null or not is_instance_valid(_camera) or _camera.is_position_behind(world_position):
		return {"visible": false}
	var point: Vector2 = _camera.unproject_position(world_position)
	var viewport_size := get_viewport().get_visible_rect().size
	return {
		"x": point.x,
		"y": point.y,
		"visible": point.x >= 0.0 and point.y >= 0.0 \
			and point.x < viewport_size.x and point.y < viewport_size.y,
	}


func _web_e2e_vector3(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}
