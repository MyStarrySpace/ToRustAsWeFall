class_name PlayerObservationController
extends Node

## Lossy, presentation-only perception adapter for automated players.
##
## The controller deliberately does not expose GameState, scene-node identities,
## navigation coordinates, authored anchors, or test receipts. It discovers the
## same screen targets a pointer can reach, verifies them through the production
## pointer-affordance ray, and replaces each live target with an opaque session
## token. A decision policy can therefore choose a visible token or screen bin,
## but cannot address hidden world state.

const OBSERVATION_SCHEMA := "player_observation_v1"
const OBSERVATION_SOURCE := "player_observable"
const SCREEN_QUANTUM_PX := 8.0
const GROUND_SAMPLE_COLUMNS := 13
const GROUND_SAMPLE_ROWS := 8
const POINTER_RAY_LENGTH := 120.0
const MAX_POINTER_RAY_HITS := 8
const BODY_COLOR_SAMPLE_RADIUS_PX := 3
const BODY_COLOR_MIN_MATCHING_PIXELS := 2
const BODY_COLOR_HUE_TOLERANCE := 0.10
const RESULT_TINT_SAMPLE_RADIUS_PX := 3
const RESULT_TINT_MIN_PIXELS_PER_CANDIDATE := 2
## How many silhouette points the occlusion probe depth-tests before ruling. Comfortably above
## the evidence quorum below, and bounded so an observation snapshot cannot cast hundreds of rays.
const RESULT_OCCLUSION_PROBE_SAMPLES := 8
const RESULT_TINT_MIN_MATCHED_CANDIDATES := 6
const RESULT_TINT_ANGULAR_SECTORS := 8
const RESULT_TINT_MIN_MATCHED_SECTORS := 3
const RESULT_TINT_MIN_SCREEN_SPAN_PX := 12.0
const CHARACTER_STATE_PRESENTER_GROUP := \
	&"player_observation_character_state_presenters"

var _host: Node
## Validation-only telemetry for the most recent framebuffer result proof. The
## observer never consumes this record as policy input; focused Windowed tests
## retain it only when an exact rendered cue fails so threshold/occlusion bugs
## can be diagnosed from measured pixels instead of loosening the gate blindly.
var _last_result_tint_diagnostic: Dictionary = {}
var _affordance_tokens: Dictionary = {}
var _affordance_presentation_sources: Dictionary = {}
var _portrait_tokens: Dictionary = {}
var _body_tokens: Dictionary = {}
var _ground_tokens: Dictionary = {}
## A movement presentation names one screen target for its entire rendered
## accepted/progress/terminal lineage. Bind that serial once to the unique
## affordance visible at its first resolvable frame; later occlusion or changed
## pixel contents must not silently retarget the same player-facing result.
var _movement_target_tokens_by_serial: Dictionary = {}
var _visible_party_subject_tokens: Dictionary = {}
var _visible_portrait_subject_tokens: Dictionary = {}
## Portrait tokens whose last completed framebuffer still showed exact HIDDEN
## while the production presenter is atomically handing off to a restored body.
## These tokens never escape separately; they only select one truthful presence
## mode inside the current observation.
var _reveal_handoff_portrait_tokens: Dictionary = {}
## Private subject identity never crosses the observation boundary. This map is
## retained only so successive rendered phases for the same nonparty subject use
## one session-local opaque token, and so the post-hoc release validator can bind
## an authoritative event to a token that was already made visible to the player.
var _consequence_subject_tokens: Dictionary = {}
var _known_party_subjects: Dictionary = {}
var _next_affordance_token := 1
var _next_portrait_token := 1
var _next_body_token := 1
var _next_ground_token := 1
var _next_consequence_subject_token := 1
var _capture_serial := 0


func setup(host: Node) -> void:
	_host = host
	_affordance_tokens.clear()
	_affordance_presentation_sources.clear()
	_portrait_tokens.clear()
	_body_tokens.clear()
	_ground_tokens.clear()
	_movement_target_tokens_by_serial.clear()
	_visible_party_subject_tokens.clear()
	_visible_portrait_subject_tokens.clear()
	_reveal_handoff_portrait_tokens.clear()
	_consequence_subject_tokens.clear()
	_known_party_subjects.clear()
	_next_affordance_token = 1
	_next_portrait_token = 1
	_next_body_token = 1
	_next_ground_token = 1
	_next_consequence_subject_token = 1
	_capture_serial = 0


func snapshot() -> Dictionary:
	_capture_serial += 1
	# Freeze already-rendered command acknowledgements at capture entry. Ground and
	# interaction discovery performs many production pointer rays and framebuffer
	# reads; a short interaction result must not age out halfway through one alleged
	# instant. The interaction snapshot includes its exact retained source/token,
	# current source visibility, pulse geometry, and framebuffer tint, so freezing it
	# cannot turn a stale, hidden, or off-screen logical receipt into evidence.
	var movement_presentation := _movement_presentation_snapshot()
	var viewport := _observation_viewport()
	var camera := _observation_camera(viewport)
	var interaction_presentation := _interaction_presentation_snapshot(
		camera, viewport)
	var player := _observation_player()
	var hud := _observation_hud()
	var hud_record := _hud_snapshot(hud)
	var ground_records := _ground_snapshot(player, viewport)
	var interaction_affordances := get_visible_interactives()
	var affordances := interaction_affordances.duplicate(true)
	affordances.append_array(ground_records)
	affordances.sort_custom(_screen_record_less)
	var state := {
		"hud": hud_record,
		"viewport": _viewport_snapshot(viewport),
		"affordances": affordances,
		# Policy predicates must not depend on the screen-sort index of an
		# affordance. These exact, de-duplicated presentation strings are derived
		# only from the current visible affordance records and sorted so the same
		# rendered information produces the same decision input on Native/Web.
		"visible_affordance_verbs": _visible_affordance_texts(affordances, "verb"),
		"visible_affordance_consequences": _visible_affordance_texts(
			affordances, "consequence"),
		"cues": _cue_snapshot(
			hud_record, movement_presentation, interaction_presentation,
			affordances),
		"viewport_bins": _viewport_bin_index(
			ground_records, interaction_affordances, viewport),
	}
	return {
		"schema": OBSERVATION_SCHEMA,
		"source": OBSERVATION_SOURCE,
		# Monotonic within one observer/run. This is ordering provenance only and
		# is deliberately excluded from policy predicates (which receive state).
		"capture_serial": _capture_serial,
		# Tick is trace provenance, not policy state. It is exposed only when the
		# shipped HUD presents time; otherwise the observation begins at zero.
		"tick": _presented_tick(hud),
		"state": state,
	}


## The only policy-facing interactive-object query.
##
## It returns opaque, screen-actionable presentation records rather than scene
## nodes or authored IDs. A record exists only when the production pointer can
## reach the object at that exact pixel, its rendered surface is unobstructed,
## HUD Controls do not cover the pixel, and the active scene confirms that the
## ray-hit point is outside fog of war. Consequently both automated personas and
## browser probes operate on the same set of interactions a human can discover.
func get_visible_interactives() -> Array:
	var viewport := _observation_viewport()
	var camera := _observation_camera(viewport)
	var player := _observation_player()
	return _affordance_snapshot(player, camera, viewport).duplicate(true)


func _viewport_snapshot(viewport: Viewport) -> Dictionary:
	if viewport == null:
		return {"origin": [0, 0], "size": [0, 0]}
	var rect := viewport.get_visible_rect()
	return {
		"origin": [int(roundf(rect.position.x)), int(roundf(rect.position.y))],
		"size": [int(roundf(rect.size.x)), int(roundf(rect.size.y))],
	}


func _visible_affordance_texts(affordances: Array, key: String) -> Array[String]:
	var unique := {}
	for raw_affordance in affordances:
		if not (raw_affordance is Dictionary):
			continue
		var value := str((raw_affordance as Dictionary).get(key, "")).strip_edges()
		if value != "":
			unique[value] = true
	var result: Array[String] = []
	for raw_value in unique.keys():
		result.append(str(raw_value))
	result.sort()
	return result


func _affordance_snapshot(player: Node, camera: Camera3D, viewport: Viewport) -> Array:
	var records: Array = []
	if player == null or camera == null or viewport == null \
			or not player.has_method("get_player_pointer_affordance"):
		return records
	var visible_rect := viewport.get_visible_rect()
	var seen_targets: Dictionary = {}
	for candidate_v in get_tree().get_nodes_in_group(
			&"player_observation_presenters"):
		if not (candidate_v is Node) \
				or not candidate_v.has_method(
					"get_player_observation_screen_candidates"):
			continue
		var candidate_points_v: Variant = candidate_v.call(
			"get_player_observation_screen_candidates", camera, viewport
		)
		if not (candidate_points_v is Array):
			continue
		for point_v in candidate_points_v as Array:
			if not (point_v is Vector2):
				continue
			var point := point_v as Vector2
			if not visible_rect.has_point(point):
				continue
			if _ui_blocks_point(point):
				continue
			var quantized_screen := _quantize_screen(point)
			var action_point := Vector2(
				float(quantized_screen[0]), float(quantized_screen[1]))
			if _ui_blocks_point(action_point):
				continue
			var hit_record := _command_hit_at(camera, action_point, candidate_v)
			var hit := hit_record.get("collider") as CollisionObject3D
			if hit == null or not _presentation_owner_matches_hit(candidate_v, hit) \
					or not _render_point_visible(camera, hit, action_point) \
					or not _interaction_hit_is_player_visible(hit_record) \
					or seen_targets.has(candidate_v.get_instance_id()):
				continue
			var pointer_v: Variant = player.call(
				"get_player_pointer_affordance", action_point)
			if not (pointer_v is Dictionary):
				continue
			var pointer := pointer_v as Dictionary
			if not bool(pointer.get("clickable", false)) \
					or str(pointer.get("kind", "")) != "interact":
				continue
			var verb := str(pointer.get("verb", "")).strip_edges()
			if verb.is_empty():
				continue
			# One rendered interaction presenter may own several valid collision
			# surfaces (mesh wrapper, Area delegate, child proxy). Camera angle can
			# change which child the production ray hits without changing the object
			# a player is pointing at. Tokenize the already-validated presenter, not
			# that transient hit child, so a later green/red pulse binds to the same
			# opaque token the player clicked.
			var target_key := candidate_v.get_instance_id()
			seen_targets[target_key] = true
			var token := _affordance_token(target_key)
			var presentation_source: Node = candidate_v
			if not presentation_source.has_method(
					"get_player_interaction_presentation"):
				presentation_source = hit
			if presentation_source.has_method(
					"get_player_interaction_presentation"):
				_affordance_presentation_sources[token] = weakref(presentation_source)
			records.append({
				"token": token,
				"kind": "interact",
				"verb": verb,
				"consequence": str(pointer.get("consequence", "")).strip_edges(),
				"screen": quantized_screen,
			})
			break
	records.sort_custom(_screen_record_less)
	return records


func _presentation_owner_matches_hit(owner: Node, hit: Node) -> bool:
	if owner == hit or owner.is_ancestor_of(hit) or hit.is_ancestor_of(owner):
		return true
	if owner.has_method("get_interaction_delegate") \
			and owner.call("get_interaction_delegate") == hit:
		return true
	if hit.has_method("get_interaction_delegate") \
			and hit.call("get_interaction_delegate") == owner:
		return true
	return false


## Fog is presentation state owned by the active scene, not by physics. The
## observer passes only the already-proven pointer hit point to that read-only
## seam. Scenes without fog need not implement it; scenes that do implement it
## fail closed for a malformed or non-finite hit.
func _interaction_hit_is_player_visible(hit_record: Dictionary) -> bool:
	if _host == null or not is_instance_valid(_host) \
			or not _host.has_method(
				"is_player_observation_world_point_visible"):
		return true
	var world_point_v: Variant = hit_record.get("position", null)
	if not (world_point_v is Vector3) \
			or not (world_point_v as Vector3).is_finite():
		return false
	return bool(_host.call(
		"is_player_observation_world_point_visible", world_point_v))


func _ground_snapshot(player: Node, viewport: Viewport) -> Array:
	var records: Array = []
	if player == null or viewport == null \
		or not player.has_method("get_player_pointer_affordance"):
		return records
	var rect := viewport.get_visible_rect()
	var seen_bins: Dictionary = {}
	for point in _ground_sample_points(viewport):
		if _ui_blocks_point(point):
			continue
		var pointer_v: Variant = player.call("get_player_pointer_affordance", point)
		if not (pointer_v is Dictionary):
			continue
		var pointer := pointer_v as Dictionary
		if not bool(pointer.get("clickable", false)) \
				or str(pointer.get("kind", "")) != "move":
			continue
		var screen := _quantize_screen(point)
		var action_point := Vector2(float(screen[0]), float(screen[1]))
		var quantized_pointer_v: Variant = player.call(
			"get_player_pointer_affordance", action_point)
		if not (quantized_pointer_v is Dictionary) \
				or not bool((quantized_pointer_v as Dictionary).get("clickable", false)) \
				or str((quantized_pointer_v as Dictionary).get("kind", "")) != "move":
			continue
		var quantized_pointer := quantized_pointer_v as Dictionary
		var bin_key := "%d:%d" % [int(screen[0]), int(screen[1])]
		if seen_bins.has(bin_key):
			continue
		seen_bins[bin_key] = true
		records.append({
			"token": _ground_token(bin_key),
			"kind": "move",
			# This exact quantized pixel is what the driver will click. Recording the
			# neighboring pre-quantization hover could advertise a route the player does
			# not actually receive at the stored action point.
			"verb": str(quantized_pointer.get("verb", "MOVE")).strip_edges(),
			"consequence": str(quantized_pointer.get(
				"consequence", "")).strip_edges(),
			"screen": screen,
		})
	records.sort_custom(_screen_record_less)
	return records


func _ground_sample_points(viewport: Viewport) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var rect := viewport.get_visible_rect()
	for row in range(GROUND_SAMPLE_ROWS):
		var y := rect.position.y + rect.size.y * float(row + 1) / float(GROUND_SAMPLE_ROWS + 1)
		for column in range(GROUND_SAMPLE_COLUMNS):
			var x := rect.position.x + rect.size.x * float(column + 1) \
				/ float(GROUND_SAMPLE_COLUMNS + 1)
			points.append(Vector2(x, y))
	return points


func _viewport_bin_index(ground_records: Array, interaction_records: Array,
		viewport: Viewport) -> Dictionary:
	var bins := {
		"top_left": [], "top_center": [], "top_right": [],
		"middle_left": [], "middle_center": [], "middle_right": [],
		"bottom_left": [], "bottom_center": [], "bottom_right": [],
		"interact_visible": [],
	}
	if viewport == null:
		return bins
	var rect := viewport.get_visible_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return bins
	var row_names := ["top", "middle", "bottom"]
	var column_names := ["left", "center", "right"]
	for record_v in ground_records:
		if not (record_v is Dictionary):
			continue
		var record := record_v as Dictionary
		var screen: Array = record.get("screen", [])
		if screen.size() < 2:
			continue
		var normalized_x := (float(screen[0]) - rect.position.x) / rect.size.x
		var normalized_y := (float(screen[1]) - rect.position.y) / rect.size.y
		var column := clampi(int(floor(normalized_x * 3.0)), 0, 2)
		var row := clampi(int(floor(normalized_y * 3.0)), 0, 2)
		var bin_name := "%s_%s" % [row_names[row], column_names[column]]
		(bins[bin_name] as Array).append(str(record.get("token", "")))
	for record_v in interaction_records:
		if record_v is Dictionary:
			(bins["interact_visible"] as Array).append(
				str((record_v as Dictionary).get("token", "")))
	return bins


func _hud_snapshot(hud: Node) -> Dictionary:
	_visible_portrait_subject_tokens.clear()
	_reveal_handoff_portrait_tokens.clear()
	var result := {
		"portraits": [],
		"hands": [],
		"run_label": "",
		"routing_label": "",
		"message": "",
	}
	if hud == null or not hud.has_method("get_player_observation"):
		return result
	var presented_v: Variant = hud.call("get_player_observation")
	if not (presented_v is Dictionary):
		return result
	var presented := presented_v as Dictionary
	var reveal_handoffs := _concealment_reveal_handoffs()
	for hand_label_v in presented.get("hands", []):
		var hand_label := str(hand_label_v).strip_edges()
		if hand_label != "" and not (result["hands"] as Array).has(hand_label):
			(result["hands"] as Array).append(hand_label)
	result["run_label"] = str(presented.get("run_label", "")).strip_edges()
	result["routing_label"] = str(
		presented.get("routing_label", "")
	).strip_edges()
	result["message"] = str(presented.get("message", "")).strip_edges()
	var portrait_state_v: Variant = presented.get("portraits", {})
	if not (portrait_state_v is Dictionary):
		return result
	var portrait_state := portrait_state_v as Dictionary
	var portrait_records: Array = []
	for raw_key in portrait_state.keys():
		var shown_v: Variant = portrait_state.get(raw_key)
		if not (shown_v is Dictionary):
			continue
		var shown := shown_v as Dictionary
		var label := str(shown.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		var portrait_token := _portrait_token(raw_key)
		var private_subject := _normalized_subject_label(str(raw_key))
		if private_subject != "" and portrait_token != "":
			_visible_portrait_subject_tokens[private_subject] = portrait_token
			_known_party_subjects[private_subject] = true
			_consequence_subject_tokens.erase(private_subject)
		var bars := {}
		var shown_bars_v: Variant = shown.get("bars", {})
		if shown_bars_v is Dictionary:
			var shown_bars := shown_bars_v as Dictionary
			for presented_bar in ["hp", "sta", "atp"]:
				if shown_bars.has(presented_bar):
					var public_bar: String = "stamina" if str(presented_bar) == "sta" \
						else str(presented_bar)
					bars[public_bar] = snappedf(clampf(
						float(shown_bars.get(presented_bar, 0.0)), 0.0, 1.0), 0.01)
		var status := str(shown.get("status", ""))
		# Auxiliary portrait cues are copied only from GameHUD's rendered
		# presentation surface. Never infer HIDDEN from GameState, scene nodes, or
		# body visibility: the exact case-sensitive word is legitimate policy input
		# only when the player could read it on the portrait.
		var statuses: Array[String] = []
		var shown_statuses_v: Variant = shown.get("statuses", [])
		if shown_statuses_v is Array:
			for shown_status_v in shown_statuses_v as Array:
				if not (shown_status_v is String):
					continue
				var shown_status := str(shown_status_v)
				if shown_status != "" and not statuses.has(shown_status):
					statuses.append(shown_status)
		# Concealment can clear during `_process` before the body/HUD update has
		# reached a completed framebuffer. During that one render handoff, retain
		# the exact HIDDEN presentation from the prior frame and suppress the not-
		# yet-drawn body below. Policy therefore receives one mode, never a gap or
		# a contradictory HIDDEN-plus-body pair.
		if str(reveal_handoffs.get(private_subject, "")) == "HIDDEN":
			statuses.erase("COVERED")
			if not statuses.has("HIDDEN"):
				statuses.append("HIDDEN")
			_reveal_handoff_portrait_tokens[portrait_token] = true
		statuses.sort()
		var hold := {}
		var shown_hold_v: Variant = shown.get("hold", {})
		if shown_hold_v is Dictionary and not (shown_hold_v as Dictionary).is_empty():
			var shown_hold := shown_hold_v as Dictionary
			hold = {
				"kind": str(shown_hold.get("kind", "")).strip_edges(),
				"label": str(shown_hold.get("label", "")).strip_edges(),
				"locked": bool(shown_hold.get("locked", false)),
			}
		portrait_records.append({
			"token": portrait_token,
			"label": label,
			"selected": bool(shown.get("selected", false)),
			"bars": bars,
			"status": status,
			"statuses": statuses,
			"hold": hold,
			"downed": status == "downed",
			"visible": true,
		})
	portrait_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("token", "")) < str(b.get("token", "")))
	result["portraits"] = portrait_records
	return result


func _cue_snapshot(hud_record: Dictionary, movement_presentation: Dictionary,
		interaction_presentation: Array, affordances: Array) -> Array:
	var cues: Array = _party_body_cues()
	cues.append_array(_presented_text_cues())
	cues.append_array(_consequence_cues(hud_record))
	cues.append_array(_movement_result_cues(
		hud_record, movement_presentation, affordances))
	cues.append_array(_interaction_result_cues(interaction_presentation))
	for node_v in get_tree().get_nodes_in_group(
			&"player_observation_overlay_presenters"):
		if not (node_v is RallyHoldIndicator) \
				or not node_v.has_method("get_player_presentation"):
			continue
		var indicator_v: Variant = node_v.call("get_player_presentation")
		if not (indicator_v is Dictionary) \
				or not bool((indicator_v as Dictionary).get("visible", false)):
			continue
		var indicator := indicator_v as Dictionary
		cues.append({
			"kind": "rally",
			"state": str(indicator.get("state", "")),
			"text": str(indicator.get("text", "")),
			"progress": float(indicator.get("progress", 0.0)),
			"screen": indicator.get("screen", []).duplicate(),
			"visible": true,
		})
	return cues


func _movement_presentation_snapshot() -> Dictionary:
	if _host == null or not _host.has_method(
			"get_player_observation_consequence_presenter"):
		return {}
	var presenter_v: Variant = _host.call(
		"get_player_observation_consequence_presenter")
	if not (presenter_v is Node) or not is_instance_valid(presenter_v) \
			or not (presenter_v as Node).has_method(
				"get_movement_presentation_state"):
		return {}
	var state_v: Variant = (presenter_v as Node).call(
		"get_movement_presentation_state")
	if not (state_v is Dictionary):
		return {}
	return (state_v as Dictionary).duplicate(true)


func _movement_result_cues(hud_record: Dictionary,
		state: Dictionary, affordances: Array = []) -> Array:
	var cues: Array = []
	if str(state.get(
			"contract", "")) != "movement_result_presentation/v1":
		return cues

	# Production keeps subject IDs so it can follow authority. The observation
	# boundary binds those IDs to the stable opaque tokens established while this
	# exact HUD snapshot was read, then immediately discards them. Do not derive
	# identity from the rendered label: transient warnings such as `ENDO  !` are
	# legitimate visible decoration, not a different party member.
	var portrait_token_by_subject := {}
	var visible_portrait_tokens := {}
	for portrait_v in hud_record.get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		if not bool(portrait.get("visible", false)):
			continue
		var portrait_token := str(portrait.get("token", ""))
		if portrait_token != "":
			visible_portrait_tokens[portrait_token] = true
	for subject_v in _visible_portrait_subject_tokens.keys():
		var subject := _normalized_subject_label(str(subject_v))
		var portrait_token := str(_visible_portrait_subject_tokens.get(subject_v, ""))
		if subject != "" and visible_portrait_tokens.has(portrait_token) \
				and not portrait_token_by_subject.has(subject):
			portrait_token_by_subject[subject] = portrait_token
	# Pure contract tests may call this projection without first running the full
	# HUD snapshot. Retain a fail-closed fallback for that seam, recognizing the
	# exact low-resource warning suffix rendered by GameHUD.
	if portrait_token_by_subject.is_empty():
		var ambiguous_subjects := {}
		for portrait_v in hud_record.get("portraits", []):
			if not (portrait_v is Dictionary):
				continue
			var portrait := portrait_v as Dictionary
			if not bool(portrait.get("visible", false)):
				continue
			var subject := _normalized_subject_label(
				str(portrait.get("label", "")).trim_suffix("  !"))
			var portrait_token := str(portrait.get("token", ""))
			if subject == "" or portrait_token == "":
				continue
			if portrait_token_by_subject.has(subject):
				ambiguous_subjects[subject] = true
			else:
				portrait_token_by_subject[subject] = portrait_token
		for subject_v in ambiguous_subjects.keys():
			portrait_token_by_subject.erase(subject_v)

	for record_v in state.get("records", []):
		if not (record_v is Dictionary):
			continue
		var record := record_v as Dictionary
		if not bool(record.get("visible", false)) \
				or not bool(record.get("render_visible", false)):
			continue
		var phase := str(record.get("phase", "")).to_lower()
		var serial := int(record.get("presentation_serial", 0))
		if phase not in ["accepted", "progress", "arrival", "interrupted", "refused"] \
				or serial <= 0:
			continue
		var target_screen_v: Variant = record.get("target_screen", null)
		if not (target_screen_v is Array) or (target_screen_v as Array).size() != 2:
			continue
		var target_screen := Vector2(
			float((target_screen_v as Array)[0]),
			float((target_screen_v as Array)[1]))
		if not target_screen.is_finite():
			continue
		var quantized_target := _quantize_screen(target_screen)
		var target_token := str(_movement_target_tokens_by_serial.get(serial, ""))
		if target_token == "":
			target_token = _unique_visible_affordance_token_at_screen(
				affordances, quantized_target)
			if target_token == "":
				continue
			_movement_target_tokens_by_serial[serial] = target_token
		var subject_tokens: Array[String] = []
		var subjects_valid := true
		for subject_id_v in record.get("subject_ids", []):
			var subject_id := _normalized_subject_label(str(subject_id_v))
			var subject_token := str(portrait_token_by_subject.get(subject_id, ""))
			if subject_token == "" or subject_tokens.has(subject_token):
				subjects_valid = false
				break
			subject_tokens.append(subject_token)
		if not subjects_valid or subject_tokens.is_empty():
			continue
		subject_tokens.sort()
		var route_status := str(record.get("route_status", ""))
		if route_status not in ["", "reforming_route", "cooperative_hold"]:
			continue
		var route_status_subjects: Array[String] = []
		if route_status != "":
			for status_subject_v in record.get(
					"route_status_subject_ids", []):
				var status_subject := _normalized_subject_label(
					str(status_subject_v))
				var status_token := str(portrait_token_by_subject.get(
					status_subject, ""))
				if status_token == "" or route_status_subjects.has(status_token):
					subjects_valid = false
					break
				route_status_subjects.append(status_token)
			if not subjects_valid or route_status_subjects.is_empty():
				continue
			route_status_subjects.sort()
		cues.append({
			"kind": "movement_result",
			"target_token": target_token,
			"subjects": subject_tokens,
			"phase": phase,
			# This is the same changing percentage rendered in the production
			# acknowledgement. It lets a player (and an observation-only player)
			# distinguish a camera-tracked route that is still advancing from a
			# genuinely stopped party without reading GameState or transforms.
			"progress": clampf(float(record.get("progress", 0.0)), 0.0, 1.0),
			"route_status": route_status,
			"route_status_serial": int(record.get("route_status_serial", 0)),
			"route_status_subjects": route_status_subjects,
			"route_status_remaining_seconds": maxf(0.0, float(record.get(
				"route_status_remaining_seconds", 0.0))),
			"accepted": bool(record.get("accepted", false)),
			"reason": str(record.get("reason", "")).strip_edges(),
			"presentation_serial": serial,
			"visible": true,
		})
	return cues


func _unique_visible_affordance_token_at_screen(
		affordances: Array, quantized_target: Array) -> String:
	if quantized_target.size() != 2:
		return ""
	var matched_token := ""
	var match_count := 0
	for affordance_v in affordances:
		if not (affordance_v is Dictionary):
			continue
		var affordance := affordance_v as Dictionary
		if str(affordance.get("kind", "")) not in ["move", "interact"]:
			continue
		var token := str(affordance.get("token", ""))
		var screen_v: Variant = affordance.get("screen", null)
		if token == "" or not (screen_v is Array) \
				or (screen_v as Array).size() != 2:
			continue
		var screen := Vector2(
			float((screen_v as Array)[0]), float((screen_v as Array)[1]))
		if not screen.is_finite() \
				or _quantize_screen(screen) != quantized_target:
			continue
		match_count += 1
		matched_token = token
		if match_count > 1:
			return ""
	return matched_token if match_count == 1 else ""


func _normalized_subject_label(value: String) -> String:
	return value.strip_edges().to_snake_case().to_lower()


func _consequence_cues(hud_record: Dictionary) -> Array:
	if _host == null or not _host.has_method(
			"get_player_observation_consequence_presenter"):
		return []
	var presenter_v: Variant = _host.call(
		"get_player_observation_consequence_presenter")
	if not (presenter_v is Node) or not is_instance_valid(presenter_v) \
			or not (presenter_v as Node).has_method("get_presentation_state"):
		return []
	var state_v: Variant = (presenter_v as Node).call("get_presentation_state")
	if not (state_v is Dictionary):
		return []
	return _consequence_cues_from_presentation(
		hud_record, state_v as Dictionary)


## Pure projection seam used by the headless contract verifier. The only retained
## private data is the observer-local raw-subject -> opaque-token map; returned
## cues contain no raw subject, event, traversal, scene, or authored identity.
func _consequence_cues_from_presentation(
		hud_record: Dictionary, presentation: Dictionary
	) -> Array:
	var cues: Array = []

	# Resolve presenter subject identities internally, then discard them. Policies
	# receive only an opaque token for a portrait/body that is visible in this same
	# observation. A world-rendered nonparty causal link receives a separate stable
	# session token because it has no party portrait/body to bind. Known party
	# subjects never fall back to that path, so a missing party binding still fails
	# closed rather than being laundered as a generic world consequence.
	var subject_tokens: Dictionary = _visible_party_subject_tokens.duplicate(true)
	for subject_v in _visible_portrait_subject_tokens.keys():
		subject_tokens[subject_v] = _visible_portrait_subject_tokens[subject_v]

	var seen := {}
	for bucket_name in ["warning", "active", "recent"]:
		for record_v in presentation.get(bucket_name, []):
			if not (record_v is Dictionary):
				continue
			var record := record_v as Dictionary
			# A consequence crosses this boundary only through an actual rendered
			# surface: either its world-space causal link or the affected member's
			# always-visible HUD badge. The presenter supplies exact per-subject badge
			# proof so one visible portrait cannot launder an unrendered sibling cue.
			var world_render_visible := bool(record.get("render_visible", false))
			var portrait_render_visible_subjects: Array = record.get(
				"portrait_render_visible_subjects", []) \
					if record.get("portrait_render_visible_subjects", null) is Array else []
			var portrait_presentations: Dictionary = record.get(
				"portrait_presentations", {}) \
					if record.get("portrait_presentations", null) is Dictionary else {}
			if not world_render_visible and portrait_render_visible_subjects.is_empty():
				continue
			var subject_ids: Array[String] = []
			var primary_subject := _normalized_subject_label(str(
				record.get("subject_id", "")))
			if primary_subject != "":
				subject_ids.append(primary_subject)
			for subject_v in record.get("subjects", []):
				var subject := _normalized_subject_label(str(subject_v))
				if subject != "" and not subject_ids.has(subject):
					subject_ids.append(subject)
			var label := str(record.get("label", "")).strip_edges()
			var destination_label := str(record.get(
				"destination_label", "")).strip_edges()
			var text := label
			if destination_label != "" \
					and not text.to_upper().contains(destination_label.to_upper()):
				text = "%s // %s" % [text, destination_label] if text != "" \
					else destination_label
			if text == "":
				continue
			for subject_id in subject_ids:
				var portrait_only := not world_render_visible
				if portrait_only and not portrait_render_visible_subjects.has(subject_id):
					continue
				var source_token := str(subject_tokens.get(subject_id, ""))
				if source_token == "" and world_render_visible \
						and not _known_party_subjects.has(subject_id):
					source_token = _consequence_subject_token(subject_id)
				if source_token == "":
					continue
				var cue_phase := str(record.get("phase", ""))
				var cue_label := label
				var cue_destination_label := destination_label
				var cue_text := text
				var cue_progress := clampf(float(record.get(
					"progress", 0.0)), 0.0, 1.0)
				if portrait_only:
					var portrait_v: Variant = portrait_presentations.get(
						subject_id, null)
					if not (portrait_v is Dictionary):
						continue
					var portrait := portrait_v as Dictionary
					cue_phase = str(portrait.get("phase", ""))
					cue_label = str(portrait.get("label", "")).strip_edges()
					cue_destination_label = str(portrait.get(
						"destination_label", "")).strip_edges()
					cue_text = str(portrait.get("text", "")).strip_edges()
					cue_progress = clampf(float(portrait.get(
						"progress", 0.0)), 0.0, 1.0)
					if cue_text == "":
						continue
				var key := "%s|%s|%s|%s" % [
					source_token, cue_phase, cue_label,
					cue_destination_label,
				]
				if seen.has(key):
					continue
				seen[key] = true
				cues.append({
					"kind": "consequence",
					"source_token": source_token,
					"phase": cue_phase,
					"label": cue_label,
					"destination_label": cue_destination_label,
					"text": cue_text,
					"progress": snappedf(cue_progress, 0.05),
					"visible": true,
				})
	return cues


## Validation-only lookup. This never allocates a token and is never included in
## snapshot state or policy input. A raw authoritative subject can therefore bind
## only to a nonparty token that an actually rendered consequence already minted.
func validation_consequence_subject_token(subject_id: String) -> String:
	var normalized := _normalized_subject_label(subject_id)
	if normalized == "" or _known_party_subjects.has(normalized):
		return ""
	return str(_consequence_subject_tokens.get(normalized, ""))


## Validation-only party presenter/ray audit. This method is never called by
## `snapshot()` or `_party_body_cues()` and its raw subject IDs, transforms, node
## paths, and colliders must never enter persona policy or learning evidence. It
## exists so a failed Windowed binding gate can distinguish an offscreen body,
## UI occlusion, solid-world occlusion, and logical/render transform divergence.
func validation_party_body_probe() -> Dictionary:
	var viewport := _observation_viewport()
	var camera := _observation_camera(viewport)
	var result := {
		"contract": "validation_only_party_body_probe_v1",
		"viewport_available": viewport != null,
		"camera_available": camera != null,
		"presenters": [],
	}
	if viewport == null or camera == null:
		return result
	var viewport_rect := viewport.get_visible_rect()
	result["viewport_rect"] = {
		"position": _validation_v2(viewport_rect.position),
		"size": _validation_v2(viewport_rect.size),
	}
	result["camera_global_position"] = _validation_v3(camera.global_position)
	result["camera_forward"] = _validation_v3(-camera.global_transform.basis.z)
	if camera.has_method("capture_view_state"):
		var camera_state_v: Variant = camera.call("capture_view_state")
		if camera_state_v is Dictionary:
			var camera_state := camera_state_v as Dictionary
			result["camera_view"] = {
				"follow_offset": _validation_v3(camera_state.get(
					"follow_offset", Vector3.ZERO) as Vector3),
				"pan_offset": _validation_v3(camera_state.get(
					"pan_offset", Vector3.ZERO) as Vector3),
				"view_yaw": float(camera_state.get("view_yaw", 0.0)),
				"view_zoom": float(camera_state.get("view_zoom", 1.0)),
				"locked": bool(camera_state.get("locked", false)),
			}
	var game_state = _host.get("_game_state") if _host != null else null
	var presenter_records: Array = []
	for body_v in get_tree().get_nodes_in_group(
			&"player_observation_party_presenters"):
		if not (body_v is Node3D) or not is_instance_valid(body_v):
			continue
		var body := body_v as Node3D
		var portrait_key := ""
		if body.has_method("get_player_observation_portrait_key"):
			portrait_key = str(body.call(
				"get_player_observation_portrait_key")).strip_edges()
		var presenter := {
			"portrait_key": portrait_key,
			"name": str(body.name),
			"class": body.get_class(),
			"path": str(body.get_path()),
			"instance_id": int(body.get_instance_id()),
			"live_global_position": _validation_v3(body.global_position),
			"live_global_transform_origin": _validation_v3(
				body.global_transform.origin),
			"body_behind_camera": camera.is_position_behind(
				body.global_transform.origin),
			"render_nodes": [],
			"candidate_screens": [],
			"candidate_probes": [],
			"ui_blocked_screens": [],
			"body_ray_match_screens": [],
			"observer_visible_screens": [],
			"empty_ray_screens": [],
			"ray_blockers": [],
		}
		if game_state != null and portrait_key != "" \
				and game_state.has_method("get_position") \
				and game_state.has_method("get_render_position"):
			presenter["logical_position"] = _validation_v3(
				game_state.call("get_position", portrait_key) as Vector3)
			presenter["render_position"] = _validation_v3(
				game_state.call("get_render_position", portrait_key) as Vector3)
		var render_nodes_v: Variant = body.call(
			"get_player_observation_render_nodes") \
			if body.has_method("get_player_observation_render_nodes") else []
		if render_nodes_v is Array:
			for render_node_v in render_nodes_v as Array:
				if not (render_node_v is Node3D) \
						or not is_instance_valid(render_node_v):
					continue
				var render_node := render_node_v as Node3D
				var render_record := {
					"name": str(render_node.name),
					"class": render_node.get_class(),
					"path": str(render_node.get_path()),
					"global_position": _validation_v3(
						render_node.global_position),
					"global_transform_origin": _validation_v3(
						render_node.global_transform.origin),
					"visible_in_tree": render_node.is_visible_in_tree(),
				}
				if render_node is MeshInstance3D:
					var mesh_node := render_node as MeshInstance3D
					render_record["mesh_present"] = mesh_node.mesh != null
					render_record["transparency"] = mesh_node.transparency
					render_record["world_aabb_center"] = _validation_v3(
						mesh_node.global_transform * mesh_node.get_aabb().get_center())
				(presenter["render_nodes"] as Array).append(render_record)

		var candidates_v: Variant = body.call(
			"get_player_observation_screen_candidates", camera, viewport) \
			if body.has_method("get_player_observation_screen_candidates") else []
		var blockers_by_key := {}
		var validation_framebuffer_cache := {}
		if candidates_v is Array:
			var candidate_index := 0
			for candidate_v in candidates_v as Array:
				if not (candidate_v is Vector2):
					continue
				var candidate := candidate_v as Vector2
				var screen := _validation_v2(candidate)
				(presenter["candidate_screens"] as Array).append(screen)
				var inside_viewport := viewport_rect.has_point(candidate)
				var ui_blocked := inside_viewport and _ui_blocks_point(candidate)
				var candidate_probe := {
					"candidate_index": candidate_index,
					"screen": screen,
					"inside_viewport": inside_viewport,
					"ui_blocked": ui_blocked,
					"ray_hit": false,
					"matches_body": false,
					"relation": "outside_viewport" \
						if not inside_viewport else "no_hit",
				}
				candidate_index += 1
				if not inside_viewport:
					(presenter["candidate_probes"] as Array).append(
						candidate_probe)
					continue
				if ui_blocked:
					(presenter["ui_blocked_screens"] as Array).append(screen)
				var visibility_probe := _body_point_visibility_probe(
					camera, body, candidate, viewport,
					validation_framebuffer_cache)
				candidate_probe["visibility_resolution"] = str(
					visibility_probe.get("resolution", "unresolved"))
				candidate_probe["provisional_proxy_count"] = int(
					visibility_probe.get("provisional_proxy_count", 0))
				candidate_probe["exact_body_hit"] = bool(
					visibility_probe.get("exact_body_hit", false))
				candidate_probe["framebuffer_required"] = bool(
					visibility_probe.get("framebuffer_required", false))
				candidate_probe["framebuffer_corroborated"] = bool(
					visibility_probe.get("framebuffer_corroborated", false))
				candidate_probe["proxy_surface_checks"] = (
					visibility_probe.get("proxy_surface_checks", []) as Array
				).duplicate(true)
				candidate_probe["visible_by_contract"] = bool(
					visibility_probe.get("visible", false)) and not ui_blocked
				if bool(candidate_probe["visible_by_contract"]):
					(presenter["observer_visible_screens"] as Array).append(screen)
				var ray_result := _body_point_ray_result(camera, candidate)
				if ray_result.is_empty():
					(presenter["empty_ray_screens"] as Array).append(screen)
					(presenter["candidate_probes"] as Array).append(
						candidate_probe)
					continue
				var collider := ray_result.get("collider") as Node
				var relation := "blocker"
				if collider == body:
					relation = "body"
				elif collider != null and body.is_ancestor_of(collider):
					relation = "body_descendant"
				elif collider != null and collider.is_ancestor_of(body):
					relation = "body_ancestor"
				var matches_body := relation in [
					"body", "body_descendant", "body_ancestor"]
				var collider_script_path := ""
				if collider != null:
					var collider_script_v: Variant = collider.get_script()
					if collider_script_v is Script:
						collider_script_path = (collider_script_v as Script).resource_path
				candidate_probe["ray_hit"] = true
				candidate_probe["matches_body"] = matches_body
				candidate_probe["relation"] = relation
				candidate_probe["collider"] = {
					"name": str(collider.name) if collider != null else "",
					"class": collider.get_class() if collider != null else "",
					"path": str(collider.get_path()) if collider != null else "",
					"script_path": collider_script_path,
					"instance_id": int(collider.get_instance_id()) \
						if collider != null else 0,
				}
				candidate_probe["hit_position"] = _validation_v3(
					ray_result.get("position", Vector3.ZERO) as Vector3)
				candidate_probe["hit_normal"] = _validation_v3(
					ray_result.get("normal", Vector3.ZERO) as Vector3)
				candidate_probe["shape"] = int(ray_result.get("shape", -1))
				candidate_probe["rid"] = str(ray_result.get("rid", RID()))
				(presenter["candidate_probes"] as Array).append(candidate_probe)
				if matches_body:
					(presenter["body_ray_match_screens"] as Array).append(screen)
					continue
				var blocker_key := "missing"
				if collider != null:
					blocker_key = "%s|%s|%s" % [
						collider.get_class(), str(collider.get_path()),
						str(collider.get_instance_id()),
					]
				var blocker := blockers_by_key.get(blocker_key, {
					"name": str(collider.name) if collider != null else "",
					"class": collider.get_class() if collider != null else "",
					"path": str(collider.get_path()) if collider != null else "",
					"instance_id": int(collider.get_instance_id()) \
						if collider != null else 0,
					"hit_position": _validation_v3(
						ray_result.get("position", Vector3.ZERO) as Vector3),
					"hit_normal": _validation_v3(
						ray_result.get("normal", Vector3.ZERO) as Vector3),
					"collider_global_position": _validation_v3(
						(collider as Node3D).global_position) \
						if collider is Node3D else [],
					"screens": [],
					"count": 0,
				}) as Dictionary
				blocker["count"] = int(blocker.get("count", 0)) + 1
				if (blocker["screens"] as Array).size() < 6:
					(blocker["screens"] as Array).append(screen)
				blockers_by_key[blocker_key] = blocker
		presenter["candidate_count"] = (
			presenter["candidate_screens"] as Array).size()
		presenter["observer_visible_candidate_count"] = (
			presenter["observer_visible_screens"] as Array).size()
		var blocker_keys := blockers_by_key.keys()
		blocker_keys.sort()
		for blocker_key_v in blocker_keys:
			(presenter["ray_blockers"] as Array).append(
				(blockers_by_key[blocker_key_v] as Dictionary).duplicate(true))
		presenter_records.append(presenter)
	presenter_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("portrait_key", "")) < str(b.get("portrait_key", "")))
	result["presenters"] = presenter_records
	return result


func _validation_v2(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _validation_v3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _consequence_subject_token(subject_id: String) -> String:
	var normalized := _normalized_subject_label(subject_id)
	if normalized == "" or _known_party_subjects.has(normalized):
		return ""
	if not _consequence_subject_tokens.has(normalized):
		_consequence_subject_tokens[normalized] = "consequence_%04d" \
			% _next_consequence_subject_token
		_next_consequence_subject_token += 1
	return str(_consequence_subject_tokens[normalized])


## Atomically retain exact, currently rendered interaction results before the
## slower affordance/ground discovery pass begins. A source enters this snapshot
## only after its retained opaque token, visible source surface, live pulse
## geometry, and success/rejection framebuffer tint all agree at capture entry.
func _interaction_presentation_snapshot(
		camera: Camera3D, viewport: Viewport
	) -> Array:
	var presentations: Array = []
	var stale_tokens: Array = []
	for token_v in _affordance_presentation_sources.keys():
		var token := str(token_v)
		# The result pulse is its own transient rendered surface. A successful
		# one-shot interaction may disable or remove the base pointer affordance in
		# the same frame, so rediscovering that old affordance may corroborate the
		# screen point but must never gate the legitimate result receipt.
		var source_ref_v: Variant = _affordance_presentation_sources.get(token_v)
		if not (source_ref_v is WeakRef):
			stale_tokens.append(token_v)
			continue
		var source_v: Variant = (source_ref_v as WeakRef).get_ref()
		if not (source_v is Node) or not is_instance_valid(source_v) \
				or not (source_v as Node).has_method(
					"get_player_interaction_presentation"):
			stale_tokens.append(token_v)
			continue
		var presentation_v: Variant = (source_v as Node).call(
			"get_player_interaction_presentation"
		)
		if not (presentation_v is Dictionary):
			continue
		var presentation := presentation_v as Dictionary
		var result := str(presentation.get("result", ""))
		var serial := int(presentation.get("presentation_serial", 0))
		if not bool(presentation.get("visible", false)) \
				or result not in ["success", "rejected"] or serial <= 0:
			continue
		var result_screen := _interaction_result_screen(
			source_v as Node, token, camera, viewport, result)
		if result_screen.is_empty():
			continue
		presentations.append({
			"source_token": token,
			"presentation_serial": serial,
			"result": result,
			"screen": result_screen.duplicate(),
			"visible": true,
		})
	for token_v in stale_tokens:
		_affordance_presentation_sources.erase(token_v)
	presentations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var token_a := str(a.get("source_token", ""))
		var token_b := str(b.get("source_token", ""))
		if token_a != token_b:
			return token_a < token_b
		return int(a.get("presentation_serial", 0)) \
			< int(b.get("presentation_serial", 0)))
	return presentations


## Project only the immutable, entry-validated presentation records. Never
## reopen the HUD or current target state here: later ambient feedback cannot
## bless a click whose exact target result was absent at capture entry.
func _interaction_result_cues(interaction_presentation: Array) -> Array:
	var cues: Array = []
	for presentation_v in interaction_presentation:
		if not (presentation_v is Dictionary):
			continue
		var presentation := presentation_v as Dictionary
		var source_token := str(presentation.get("source_token", ""))
		var result := str(presentation.get("result", ""))
		var serial := int(presentation.get("presentation_serial", 0))
		var screen_v: Variant = presentation.get("screen", [])
		if source_token == "" or result not in ["success", "rejected"] \
				or serial <= 0 or not bool(presentation.get("visible", false)) \
				or not (screen_v is Array) or (screen_v as Array).size() != 2:
			continue
		cues.append({
			"kind": "interaction_result",
			"source_token": source_token,
			"presentation_serial": serial,
			"result": result,
			"screen": (screen_v as Array).duplicate(),
			"visible": true,
		})
	return cues


func _interaction_result_source_visible(
		source: Node,
		token: String,
		camera: Camera3D,
		viewport: Viewport,
		result_kind: String
	) -> bool:
	return not _interaction_result_screen(
		source, token, camera, viewport, result_kind).is_empty()


func _interaction_result_screen(
		source: Node,
		token: String,
		camera: Camera3D,
		viewport: Viewport,
		result_kind: String
	) -> Array:
	if source == null or not is_instance_valid(source) or camera == null \
			or viewport == null or token == "" \
			or not source.has_method(
				"get_player_interaction_presentation_screen_candidates"):
		return []
	var source_token_v: Variant = _affordance_tokens.get(source.get_instance_id())
	if source_token_v == null:
		# Interactable proxies are bound to the same target token when the base
		# affordance is first observed. Accept that exact retained weakref identity;
		# never allocate or infer a new token from the pulse itself.
		var retained_ref_v: Variant = _affordance_presentation_sources.get(token)
		if not (retained_ref_v is WeakRef) \
				or (retained_ref_v as WeakRef).get_ref() != source:
			return []
	elif str(source_token_v) != token:
		return []
	# The pulse is top-level so it can finish its short animation if the source is
	# removed from layout. Do not let that stale screen coordinate self-attest a
	# source that has since moved off-camera or hidden its rendered geometry. This
	# checks the source's presentation surface only; it deliberately does not
	# require the one-shot pointer affordance to remain enabled after success.
	if not source.has_method("get_player_observation_screen_candidates"):
		return []
	var source_candidates_v: Variant = source.call(
		"get_player_observation_screen_candidates", camera, viewport)
	if not (source_candidates_v is Array):
		return []
	var source_surface_visible := false
	var source_rect := viewport.get_visible_rect()
	for source_candidate_v in source_candidates_v as Array:
		if source_candidate_v is Vector2 \
				and source_rect.has_point(source_candidate_v as Vector2) \
				and not _ui_blocks_point(source_candidate_v as Vector2):
			source_surface_visible = true
			break
	if not source_surface_visible:
		return []
	var candidates_v: Variant = source.call(
		"get_player_interaction_presentation_screen_candidates", camera, viewport)
	if not (candidates_v is Array):
		return []
	# Pixels alone cannot prove the player sees the result: the outline mask composites the
	# silhouette regardless of scene occluders, so a body standing in front of the object would
	# still leave tinted pixels on screen. An occlusion probe depth-tests a BOUNDED, evenly spread
	# sample of the silhouette's world points; if no sampled point is reachable from the camera,
	# the whole result is treated as hidden. Bounded because this runs per presentation per
	# observation snapshot, and a ray per silhouette vertex would put hundreds of casts in an
	# observation loop. The approximation is honest: a partial occluder covering exactly the
	# sampled points and nothing else would mis-rule, while the property under test -- an opaque
	# body between camera and source -- covers every sample by construction.
	var world_candidates: Array = []
	if source.has_method("get_player_interaction_presentation_world_candidates"):
		world_candidates = source.call(
			"get_player_interaction_presentation_world_candidates")
	if not world_candidates.is_empty():
		var own_rids := _result_own_body_rids(source)
		var probe_stride := maxi(1, int(ceil(float(world_candidates.size())
			/ float(RESULT_OCCLUSION_PROBE_SAMPLES))))
		var any_reachable := false
		for probe_index in range(0, world_candidates.size(), probe_stride):
			if not (world_candidates[probe_index] is Vector3):
				continue
			if _result_point_depth_visible(
					camera, world_candidates[probe_index] as Vector3, own_rids):
				any_reachable = true
				break
		if not any_reachable:
			return []
	var rect := viewport.get_visible_rect()
	var framebuffer_candidates: Array[Vector2] = []
	for candidate_v in candidates_v as Array:
		if not (candidate_v is Vector2):
			continue
		var candidate := candidate_v as Vector2
		if not rect.has_point(candidate) or _ui_blocks_point(candidate):
			continue
		framebuffer_candidates.append(candidate)
	var matched_candidate := _framebuffer_result_tint_candidate(
		viewport, framebuffer_candidates, result_kind)
	if not matched_candidate.is_finite():
		return []
	return _quantize_screen(matched_candidate)


## True when no OTHER body stands between the camera and this surface point. The source's own
## collision shapes are excluded deliberately: a silhouette sample on the far side of the object is
## still part of the outline the mask draws, and self-occlusion would thin the candidate set below
## its evidence quorum. The question this answers is whether something ELSE hides the result.
func _result_point_depth_visible(
		camera: Camera3D,
		world_point: Vector3,
		exclude: Array[RID]
	) -> bool:
	if camera == null or not camera.is_inside_tree():
		return false
	var world := camera.get_world_3d()
	if world == null:
		return true
	var origin := camera.global_position
	var span := world_point - origin
	var span_length := span.length()
	if span_length <= 0.001:
		return true
	var query := PhysicsRayQueryParameters3D.create(origin, world_point)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = exclude
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var hit_distance := (hit.get("position", world_point) as Vector3 - origin).length()
	return hit_distance >= span_length - 0.05

## Every collision RID belonging to the presenting object itself, so the depth test measures other
## bodies rather than the object's own front face.
func _result_own_body_rids(source: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if source == null or not is_instance_valid(source):
		return rids
	# The SOURCE's own subtree only. A presenting object is itself a body, so its shapes live here;
	# widening to the parent would also exclude its siblings -- which is exactly where a genuine
	# occluder stands.
	var stack: Array = [source]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
	return rids


func _framebuffer_has_result_tint(
		viewport: Viewport,
		candidates: Array[Vector2],
		result_kind: String
	) -> bool:
	return _framebuffer_result_tint_candidate(
		viewport, candidates, result_kind).is_finite()


func _framebuffer_result_tint_candidate(
		viewport: Viewport,
		candidates: Array[Vector2],
		result_kind: String
	) -> Vector2:
	var diagnostic := {
		"result_kind": result_kind,
		"candidate_count": candidates.size(),
		"accepted": false,
		"accepted_orientation": "",
		"reason": "invalid_input",
	}
	_last_result_tint_diagnostic = diagnostic
	if viewport == null or candidates.is_empty() \
			or result_kind not in ["success", "rejected"]:
		return Vector2.INF
	var texture := viewport.get_texture()
	if texture == null:
		diagnostic["reason"] = "missing_viewport_texture"
		_last_result_tint_diagnostic = diagnostic
		return Vector2.INF
	var image := texture.get_image()
	if image == null or image.is_empty():
		diagnostic["reason"] = "missing_viewport_image"
		_last_result_tint_diagnostic = diagnostic
		return Vector2.INF
	var rect := viewport.get_visible_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		diagnostic["reason"] = "empty_viewport_rect"
		_last_result_tint_diagnostic = diagnostic
		return Vector2.INF
	var scale := Vector2(
		float(image.get_width()) / rect.size.x,
		float(image.get_height()) / rect.size.y
	)
	var candidate_min := candidates[0] as Vector2
	var candidate_max := candidate_min
	for candidate_v in candidates:
		var candidate := candidate_v as Vector2
		candidate_min = Vector2(
			minf(candidate_min.x, candidate.x),
			minf(candidate_min.y, candidate.y))
		candidate_max = Vector2(
			maxf(candidate_max.x, candidate.x),
			maxf(candidate_max.y, candidate.y))
	var pulse_screen_center := (candidate_min + candidate_max) * 0.5
	# ViewportTexture readback orientation differs across rendering backends.
	# Evaluate both hypotheses through the exact same proof implementation. Each
	# must independently satisfy pixel, annular-sector, and screen-span quorums;
	# evidence is never pooled between orientations.
	var normal_y_proof := _framebuffer_result_tint_orientation_hypothesis(
		image, rect, scale, candidates, pulse_screen_center, result_kind, false)
	var flipped_y_proof := _framebuffer_result_tint_orientation_hypothesis(
		image, rect, scale, candidates, pulse_screen_center, result_kind, true)
	diagnostic["candidate_bounds_span_px"] = candidate_min.distance_to(
		candidate_max)
	diagnostic["normal_y_hypothesis"] = normal_y_proof
	diagnostic["flipped_y_hypothesis"] = flipped_y_proof
	var strongest_proof := normal_y_proof
	if _result_tint_orientation_proof_score(flipped_y_proof) \
			> _result_tint_orientation_proof_score(normal_y_proof):
		strongest_proof = flipped_y_proof
	for metric_key in [
		"matched_candidate_count",
		"matched_sector_count",
		"max_matching_pixels_per_candidate",
		"matched_screen_span_px",
		"max_alpha",
		"alpha_above_floor_pixel_count",
		"max_green",
		"max_green_minus_red",
		"max_green_minus_blue",
		"success_strict_best_margin",
		"success_strict_best_color",
	]:
		diagnostic[metric_key] = strongest_proof.get(metric_key)
	var accepted_proof: Dictionary = {}
	if bool(normal_y_proof.get("accepted", false)):
		accepted_proof = normal_y_proof
	elif bool(flipped_y_proof.get("accepted", false)):
		accepted_proof = flipped_y_proof
	if accepted_proof.is_empty():
		diagnostic["reason"] = "no_complete_orientation_proof"
		_last_result_tint_diagnostic = diagnostic
		return Vector2.INF
	var candidate_v: Variant = accepted_proof.get(
		"first_matched_candidate", [])
	if not (candidate_v is Array) or (candidate_v as Array).size() != 2:
		diagnostic["reason"] = "accepted_orientation_missing_candidate"
		_last_result_tint_diagnostic = diagnostic
		return Vector2.INF
	diagnostic["accepted"] = true
	diagnostic["accepted_orientation"] = str(
		accepted_proof.get("orientation", ""))
	diagnostic["reason"] = "accepted"
	_last_result_tint_diagnostic = diagnostic
	return Vector2(
		float((candidate_v as Array)[0]), float((candidate_v as Array)[1]))


func _result_tint_orientation_proof_score(proof: Dictionary) -> int:
	return int(proof.get("matched_candidate_count", 0)) * 1000000 \
		+ int(proof.get("matched_sector_count", 0)) * 10000 \
		+ int(proof.get("candidate_count", 0)) * 100 \
		+ int(proof.get("max_matching_pixels_per_candidate", 0))
func _framebuffer_result_tint_orientation_hypothesis(
		image: Image,
		rect: Rect2,
		scale: Vector2,
		candidates: Array[Vector2],
		pulse_screen_center: Vector2,
		result_kind: String,
		flip_y: bool
	) -> Dictionary:
	var proof := {
		"orientation": "flipped_y" if flip_y else "normal_y",
		"candidate_count": candidates.size(),
		"matched_candidate_count": 0,
		"matched_sector_count": 0,
		"max_matching_pixels_per_candidate": 0,
		"matched_screen_span_px": 0.0,
		"max_alpha": 0.0,
		"alpha_above_floor_pixel_count": 0,
		"max_green": 0.0,
		"max_green_minus_red": -INF,
		"max_green_minus_blue": -INF,
		"success_strict_best_margin": -INF,
		"success_strict_best_color": [],
		"first_matched_candidate": [],
		"accepted": false,
		"reason": "matched_candidate_quorum",
	}
	var matched_candidates: Array[Vector2] = []
	var matched_sectors := {}
	for candidate in candidates:
		var image_y := (candidate.y - rect.position.y) * scale.y
		if flip_y:
			image_y = float(image.get_height() - 1) - image_y
		var image_center := Vector2(
			(candidate.x - rect.position.x) * scale.x, image_y)
		var matching_pixels := 0
		for y_offset in range(
				-RESULT_TINT_SAMPLE_RADIUS_PX,
				RESULT_TINT_SAMPLE_RADIUS_PX + 1):
			for x_offset in range(
					-RESULT_TINT_SAMPLE_RADIUS_PX,
					RESULT_TINT_SAMPLE_RADIUS_PX + 1):
				var pixel := Vector2i(
					clampi(int(roundf(image_center.x)) + x_offset, 0,
						image.get_width() - 1),
					clampi(int(roundf(image_center.y)) + y_offset, 0,
						image.get_height() - 1))
				var color := image.get_pixelv(pixel)
				proof["max_alpha"] = maxf(float(proof["max_alpha"]), color.a)
				if color.a > 0.05:
					proof["alpha_above_floor_pixel_count"] = int(
						proof["alpha_above_floor_pixel_count"]) + 1
				proof["max_green"] = maxf(float(proof["max_green"]), color.g)
				proof["max_green_minus_red"] = maxf(
					float(proof["max_green_minus_red"]), color.g - color.r)
				proof["max_green_minus_blue"] = maxf(
					float(proof["max_green_minus_blue"]), color.g - color.b)
				var strict_margin := minf(
					color.g - 0.58,
					minf(color.g - color.r - 0.08,
						minf(color.g - color.b - 0.05,
							minf(color.g - color.r * 1.12,
								color.g - color.b * 1.05))))
				if strict_margin > float(proof["success_strict_best_margin"]):
					proof["success_strict_best_margin"] = strict_margin
					proof["success_strict_best_color"] = [
						color.r, color.g, color.b, color.a]
				if _framebuffer_color_matches_result_tint(color, result_kind):
					matching_pixels += 1
		proof["max_matching_pixels_per_candidate"] = maxi(
			int(proof["max_matching_pixels_per_candidate"]), matching_pixels)
		if matching_pixels < RESULT_TINT_MIN_PIXELS_PER_CANDIDATE:
			continue
		matched_candidates.append(candidate)
		var radial := candidate - pulse_screen_center
		if radial.length_squared() > 1.0:
			var angle := fposmod(atan2(radial.y, radial.x), TAU)
			var sector := clampi(int(floorf(
				angle / TAU * RESULT_TINT_ANGULAR_SECTORS)),
				0, RESULT_TINT_ANGULAR_SECTORS - 1)
			matched_sectors[sector] = true
	proof["matched_candidate_count"] = matched_candidates.size()
	proof["matched_sector_count"] = matched_sectors.size()
	if not matched_candidates.is_empty():
		proof["first_matched_candidate"] = [
			matched_candidates[0].x, matched_candidates[0].y]
	var matched_screen_span_px := 0.0
	for first_index in range(matched_candidates.size()):
		for second_index in range(first_index + 1, matched_candidates.size()):
			matched_screen_span_px = maxf(
				matched_screen_span_px,
				matched_candidates[first_index].distance_to(
					matched_candidates[second_index]))
	proof["matched_screen_span_px"] = matched_screen_span_px
	proof["accepted"] = matched_candidates.size() \
		>= RESULT_TINT_MIN_MATCHED_CANDIDATES \
		and matched_sectors.size() >= RESULT_TINT_MIN_MATCHED_SECTORS \
		and matched_screen_span_px >= RESULT_TINT_MIN_SCREEN_SPAN_PX
	if bool(proof["accepted"]):
		proof["reason"] = "accepted"
	elif matched_candidates.size() >= RESULT_TINT_MIN_MATCHED_CANDIDATES \
			and matched_sectors.size() < RESULT_TINT_MIN_MATCHED_SECTORS:
		proof["reason"] = "matched_sector_quorum"
	elif matched_candidates.size() >= RESULT_TINT_MIN_MATCHED_CANDIDATES:
		proof["reason"] = "matched_screen_span"
	return proof


func _framebuffer_color_matches_result_tint(
		color: Color, result_kind: String
	) -> bool:
	if color.a <= 0.05:
		return false
	if result_kind == "success":
		return color.g >= 0.58 \
			and color.g - color.r >= 0.08 \
			and color.g - color.b >= 0.05 \
			and color.g > color.r * 1.12 \
			and color.g > color.b * 1.05
	return color.r >= 0.58 \
		and color.r - color.g >= 0.12 \
		and color.r - color.b >= 0.10 \
		and color.r > color.g * 1.25 \
		and color.r > color.b * 1.15


## Text that is physically rendered in the current player view is legitimate level information.
## Keeping it in the same cue stream as consequence banners lets a non-visual policy follow the
## labels and instructions a human reads without exposing scene identities or authored anchors.
func _presented_text_cues() -> Array:
	var cues: Array = []
	var seen: Dictionary = {}
	var public_cues_v: Variant = _host.call(
		"get_player_observation_text_cues") \
		if _host != null and _host.has_method(
			"get_player_observation_text_cues") else []
	if public_cues_v is Array:
		for cue_v in public_cues_v as Array:
			if not (cue_v is Dictionary):
				continue
			var cue := cue_v as Dictionary
			var text := str(cue.get("text", "")).strip_edges()
			if text == "" or seen.has(text) or not bool(cue.get("visible", false)):
				continue
			seen[text] = true
			cues.append({
				"kind": str(cue.get("kind", "instruction")),
				"text": text,
				"visible": true,
			})
	var hud := _observation_hud()
	if hud != null and hud.has_method("get_player_observation"):
		var hud_v: Variant = hud.call("get_player_observation")
		if hud_v is Dictionary:
			var message := str((hud_v as Dictionary).get("message", "")).strip_edges()
			if message != "" and not seen.has(message):
				cues.append({"kind": "hud", "text": message, "visible": true})
	return cues


func _party_body_cues() -> Array:
	var cues: Array = []
	_visible_party_subject_tokens.clear()
	var viewport := _observation_viewport()
	var camera := _observation_camera(viewport)
	if viewport == null or camera == null:
		return cues
	var rect := viewport.get_visible_rect()
	# A readback is needed only for the exceptional collision-padding path. Share
	# that one captured frame across all candidates in this observation so every
	# admitted body is corroborated against the same pixels a player received.
	var body_framebuffer_cache := {}
	for body_v in get_tree().get_nodes_in_group(
			&"player_observation_party_presenters"):
		if not (body_v is Node3D) or not is_instance_valid(body_v) \
				or not body_v.has_method("get_player_observation_screen_candidates"):
			continue
		var body := body_v as Node3D
		var portrait_key := ""
		var binding_token := ""
		if body.has_method("get_player_observation_portrait_key"):
			portrait_key = str(body.call(
				"get_player_observation_portrait_key")).strip_edges()
			if portrait_key != "":
				binding_token = _portrait_token(portrait_key)
				if _reveal_handoff_portrait_tokens.has(binding_token):
					continue
		var candidates_v: Variant = body.call(
			"get_player_observation_screen_candidates", camera, viewport)
		if not (candidates_v is Array):
			continue
		var visible_screen := Vector2.INF
		for candidate_v in candidates_v as Array:
			if not (candidate_v is Vector2):
				continue
			var candidate := candidate_v as Vector2
			if rect.has_point(candidate) and not _ui_blocks_point(candidate) \
					and _body_point_visible(
						camera, body, candidate, viewport,
						body_framebuffer_cache):
				visible_screen = candidate
				break
		if not visible_screen.is_finite():
			continue
		var cue := {
			"kind": "party_body",
			"source_token": _body_token(body.get_instance_id()),
			"screen": _quantize_screen(visible_screen),
			"visible": true,
		}
		if portrait_key != "":
			cue["binding"] = binding_token
			var normalized_party_subject := _normalized_subject_label(portrait_key)
			_visible_party_subject_tokens[normalized_party_subject] = str(
				cue.get("source_token", ""))
			_known_party_subjects[normalized_party_subject] = true
			_consequence_subject_tokens.erase(normalized_party_subject)
		cues.append(cue)
	return cues


func _concealment_reveal_handoffs() -> Dictionary:
	var result := {}
	if _host == null or not is_instance_valid(_host) or get_tree() == null:
		return result
	var matched_presenter: Node = null
	for presenter_v in get_tree().get_nodes_in_group(
			CHARACTER_STATE_PRESENTER_GROUP):
		if not (presenter_v is Node) or not is_instance_valid(presenter_v):
			continue
		var presenter := presenter_v as Node
		if presenter != _host and not _host.is_ancestor_of(presenter):
			continue
		if not presenter.has_method(
				"get_player_observation_concealment_reveal_handoffs"):
			continue
		# Ambiguous presenters fail closed instead of choosing another scene's
		# render epoch or merging two unrelated HUD histories.
		if matched_presenter != null:
			return {}
		matched_presenter = presenter
	if matched_presenter == null:
		return result
	var handoffs_v: Variant = matched_presenter.call(
		"get_player_observation_concealment_reveal_handoffs")
	if not (handoffs_v is Dictionary):
		return result
	for character_id_v in (handoffs_v as Dictionary).keys():
		var character_id := _normalized_subject_label(str(character_id_v))
		var status_v: Variant = (handoffs_v as Dictionary).get(
			character_id_v, "")
		if character_id != "" and status_v is String \
				and str(status_v) == "HIDDEN":
			result[character_id] = "HIDDEN"
	return result


func _body_point_visible(
		camera: Camera3D,
		body: Node3D,
		screen: Vector2,
		viewport_override: Viewport = null,
		framebuffer_cache_override: Variant = null
	) -> bool:
	var viewport := viewport_override
	if viewport == null and camera != null:
		viewport = camera.get_viewport()
	var framebuffer_cache: Dictionary = {}
	if framebuffer_cache_override is Dictionary:
		framebuffer_cache = framebuffer_cache_override as Dictionary
	return bool(_body_point_visibility_probe(
		camera, body, screen, viewport, framebuffer_cache).get("visible", false))


## Resolves one party-body pixel without manufacturing x-ray visibility. An
## OutlineSurfaceTarget owns a padded physics hull for pointer accessibility, so
## its collision may be provisionally skipped. That exception is admitted only
## after the eventual exact body hit proves that every skipped target's registered
## opaque triangles miss this same camera-to-body segment and the live framebuffer
## independently contains the body's current rendered material colour.
##
## The returned reasons are validation diagnostics only. `_party_body_cues()`
## consumes the boolean and never copies collider, geometry, or framebuffer facts
## into policy observation.
func _body_point_visibility_probe(
		camera: Camera3D,
		body: Node3D,
		screen: Vector2,
		viewport: Viewport,
		framebuffer_cache: Dictionary
	) -> Dictionary:
	var probe := {
		"visible": false,
		"resolution": "unresolved",
		"provisional_proxy_count": 0,
		"proxy_surface_checks": [],
		"exact_body_hit": false,
		"framebuffer_required": false,
		"framebuffer_corroborated": false,
	}
	if camera == null or body == null or not is_instance_valid(body):
		probe["resolution"] = "missing_camera_or_body"
		return probe
	var world := camera.get_world_3d()
	if world == null:
		probe["resolution"] = "missing_world"
		return probe
	var ray_from := camera.project_ray_origin(screen)
	var ray_direction := camera.project_ray_normal(screen)
	if not ray_from.is_finite() or not ray_direction.is_finite() \
			or ray_direction.is_zero_approx():
		probe["resolution"] = "invalid_ray"
		return probe
	var ray_to := ray_from + ray_direction * POINTER_RAY_LENGTH
	var excluded: Array[RID] = []
	var skipped_proxies: Array = []
	for _hit_index in range(MAX_POINTER_RAY_HITS):
		var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		# Area3D nodes are gameplay triggers rather than rendered occluders. Solid
		# bodies retain ordinary opaque occlusion unless they satisfy the narrow,
		# reviewed OutlineSurfaceTarget proof below.
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = excluded
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			probe["resolution"] = "no_solid_hit"
			return probe
		var collider := hit.get("collider") as Node
		if skipped_proxies.is_empty() and _body_hit_matches(body, collider):
			# Preserve the established direct-body contract. The stricter exact-hit
			# and framebuffer requirements apply only after collision was pierced.
			probe["visible"] = true
			probe["exact_body_hit"] = collider == body
			probe["resolution"] = "direct_body"
			return probe
		if not skipped_proxies.is_empty() and collider == body:
			probe["exact_body_hit"] = true
			probe["framebuffer_required"] = true
			var body_hit_position_v: Variant = hit.get("position", null)
			if not (body_hit_position_v is Vector3) \
					or not (body_hit_position_v as Vector3).is_finite():
				probe["resolution"] = "missing_exact_body_hit_position"
				return probe
			var body_hit_position := body_hit_position_v as Vector3
			for skipped_v in skipped_proxies:
				var skipped := skipped_v as Dictionary
				var surface_probe := _proxy_opaque_segment_probe(
					skipped.get("render_nodes", []) as Array,
					ray_from, body_hit_position)
				(probe["proxy_surface_checks"] as Array).append(
					surface_probe.duplicate(true))
				if str(surface_probe.get("resolution", "unsupported")) != "clear":
					probe["resolution"] = "proxy_%s" % str(
						surface_probe.get("resolution", "unsupported"))
					return probe
			var framebuffer_matches := _framebuffer_matches_body_material(
				viewport, body, screen, framebuffer_cache)
			probe["framebuffer_corroborated"] = framebuffer_matches
			if not framebuffer_matches:
				probe["resolution"] = "framebuffer_body_colour_unconfirmed"
				return probe
			probe["visible"] = true
			probe["resolution"] = "proxy_padding_only"
			return probe

		# No other PhysicsBody may be tunneled. Only the production presentation
		# wrapper with its filtered render-node API is eligible for provisional
		# exclusion; unsupported geometry later fails the whole proof closed.
		if not (collider is OutlineSurfaceTarget) \
				or not collider.is_in_group(&"player_observation_presenters") \
				or not collider.has_method("get_player_observation_render_nodes"):
			probe["resolution"] = "proxy_next_hit_not_exact_body" \
				if not skipped_proxies.is_empty() else "solid_blocker"
			return probe
		var render_nodes_v: Variant = collider.call(
			"get_player_observation_render_nodes")
		if not (render_nodes_v is Array) or (render_nodes_v as Array).is_empty():
			probe["resolution"] = "unreviewed_proxy_render_nodes"
			return probe
		var render_nodes: Array = []
		for render_node_v in render_nodes_v as Array:
			if not (render_node_v is Node3D) \
					or not is_instance_valid(render_node_v) \
					or not (render_node_v as Node3D).is_visible_in_tree():
				probe["resolution"] = "unreviewed_proxy_render_nodes"
				return probe
			render_nodes.append(render_node_v)
		var proxy_rid: RID = hit.get("rid", RID())
		if not proxy_rid.is_valid() or excluded.has(proxy_rid):
			probe["resolution"] = "invalid_proxy_rid"
			return probe
		skipped_proxies.append({
			"render_nodes": render_nodes,
		})
		excluded.append(proxy_rid)
		probe["provisional_proxy_count"] = skipped_proxies.size()
	probe["resolution"] = "ray_hit_limit"
	return probe


func _body_hit_matches(body: Node3D, collider: Node) -> bool:
	return collider == body or (collider != null and (
		body.is_ancestor_of(collider) or collider.is_ancestor_of(body)))


## Focused validation seam for one candidate. Like the broader party probe above,
## this is never called by `snapshot()` and returns no collider or authored ID.
func validation_party_body_candidate_visibility(
		camera: Camera3D, body: Node3D, screen: Vector2
	) -> Dictionary:
	var viewport := camera.get_viewport() if camera != null else null
	return _body_point_visibility_probe(camera, body, screen, viewport, {})


## Validation-only seam for focused geometry fixtures. It does not allocate an
## observation token and is never called by `snapshot()`: raw nodes and world
## positions stay on the post-hoc validation side of the policy boundary.
func validation_proxy_opaque_segment_probe(
		proxy: Node, segment_from: Vector3, segment_to: Vector3
	) -> Dictionary:
	if not (proxy is OutlineSurfaceTarget) \
			or not proxy.has_method("get_player_observation_render_nodes"):
		return {"resolution": "unsupported", "reason": "unreviewed_proxy"}
	var render_nodes_v: Variant = proxy.call("get_player_observation_render_nodes")
	if not (render_nodes_v is Array):
		return {"resolution": "unsupported", "reason": "missing_render_nodes"}
	return _proxy_opaque_segment_probe(
		render_nodes_v as Array, segment_from, segment_to)


## Tests whether an already-reviewed proxy has real opaque render geometry on the
## exact camera-to-body segment. Triangle intersection is the final authority:
## bounds are never sufficient evidence of occlusion. Missing, malformed, custom,
## or non-triangle geometry fails closed instead of becoming an x-ray exception.
func _proxy_opaque_segment_probe(
		render_nodes: Array, segment_from: Vector3, segment_to: Vector3
	) -> Dictionary:
	var probe := {
		"resolution": "unsupported",
		"mesh_count": 0,
		"opaque_surface_count": 0,
		"triangle_count": 0,
	}
	if render_nodes.is_empty() or not segment_from.is_finite() \
			or not segment_to.is_finite() \
			or segment_from.is_equal_approx(segment_to):
		return probe
	for render_node_v in render_nodes:
		if not (render_node_v is MeshInstance3D) \
				or not is_instance_valid(render_node_v):
			probe["reason"] = "non_mesh_render_node"
			return probe
		var mesh_instance := render_node_v as MeshInstance3D
		if not mesh_instance.is_visible_in_tree() or mesh_instance.mesh == null \
				or mesh_instance.transparency >= 0.99:
			probe["reason"] = "unavailable_mesh"
			return probe
		var mesh := mesh_instance.mesh
		if mesh.get_surface_count() <= 0:
			probe["reason"] = "empty_mesh"
			return probe
		if absf(mesh_instance.global_transform.basis.determinant()) <= 0.0000001:
			probe["reason"] = "non_invertible_mesh_transform"
			return probe
		var inverse := mesh_instance.global_transform.affine_inverse()
		var local_from := inverse * segment_from
		var local_to := inverse * segment_to
		if not local_from.is_finite() or not local_to.is_finite():
			probe["reason"] = "invalid_mesh_transform"
			return probe
		probe["mesh_count"] = int(probe["mesh_count"]) + 1
		var mesh_opaque_surface_count := 0
		var mesh_triangle_count := 0
		for surface_index in range(mesh.get_surface_count()):
			var opacity_state := _proxy_surface_opacity_state(
				mesh_instance, surface_index)
			if opacity_state == "non_opaque":
				continue
			if opacity_state != "opaque":
				probe["reason"] = "unsupported_material"
				return probe
			if mesh.has_method("surface_get_primitive_type") \
					and int(mesh.call("surface_get_primitive_type", surface_index)) \
						!= Mesh.PRIMITIVE_TRIANGLES:
				probe["reason"] = "non_triangle_surface"
				return probe
			var arrays_v: Variant = mesh.surface_get_arrays(surface_index)
			if not (arrays_v is Array):
				probe["reason"] = "missing_surface_arrays"
				return probe
			var arrays := arrays_v as Array
			if arrays.size() <= Mesh.ARRAY_VERTEX \
					or not (arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array):
				probe["reason"] = "missing_vertices"
				return probe
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			if vertices.is_empty():
				probe["reason"] = "empty_vertices"
				return probe
			var indices := PackedInt32Array()
			if arrays.size() > Mesh.ARRAY_INDEX \
					and arrays[Mesh.ARRAY_INDEX] != null:
				if not (arrays[Mesh.ARRAY_INDEX] is PackedInt32Array):
					probe["reason"] = "unsupported_indices"
					return probe
				indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			var element_count := indices.size() if not indices.is_empty() \
				else vertices.size()
			if element_count < 3 or element_count % 3 != 0:
				probe["reason"] = "malformed_triangles"
				return probe
			mesh_opaque_surface_count += 1
			probe["opaque_surface_count"] = int(
				probe["opaque_surface_count"]) + 1
			@warning_ignore("integer_division")
			var triangle_count: int = element_count / 3
			for triangle_index in range(triangle_count):
				var vertex_indices := [
					triangle_index * 3,
					triangle_index * 3 + 1,
					triangle_index * 3 + 2,
				]
				if not indices.is_empty():
					for corner in range(3):
						vertex_indices[corner] = indices[vertex_indices[corner]]
				var valid_indices := true
				for vertex_index_v in vertex_indices:
					var vertex_index := int(vertex_index_v)
					if vertex_index < 0 or vertex_index >= vertices.size():
						valid_indices = false
						break
				if not valid_indices:
					probe["reason"] = "out_of_range_index"
					return probe
				var a := vertices[int(vertex_indices[0])]
				var b := vertices[int(vertex_indices[1])]
				var c := vertices[int(vertex_indices[2])]
				if not a.is_finite() or not b.is_finite() or not c.is_finite():
					probe["reason"] = "invalid_vertex"
					return probe
				if (b - a).cross(c - a).length_squared() <= 0.0000000001:
					continue
				mesh_triangle_count += 1
				probe["triangle_count"] = int(probe["triangle_count"]) + 1
				var intersection_v: Variant = Geometry3D.segment_intersects_triangle(
					local_from, local_to, a, b, c)
				# Do not depend on authored winding or a negative-scale transform. If
				# the engine helper culls one face, the reversed triangle still proves
				# the same opaque surface blocks the player's ray.
				var reverse_intersection_v: Variant = null
				if not (intersection_v is Vector3):
					reverse_intersection_v = Geometry3D.segment_intersects_triangle(
						local_from, local_to, a, c, b)
				if intersection_v is Vector3 or reverse_intersection_v is Vector3:
					probe["resolution"] = "opaque_surface_blocked"
					return probe
		if mesh_opaque_surface_count <= 0 or mesh_triangle_count <= 0:
			probe["reason"] = "no_supported_opaque_triangles"
			return probe
	probe["resolution"] = "clear"
	return probe


func _proxy_surface_opacity_state(
		mesh_instance: MeshInstance3D, surface_index: int
	) -> String:
	var material: Material = mesh_instance.material_override
	if material == null:
		material = mesh_instance.get_active_material(surface_index)
	# Godot's fallback material is opaque.
	if material == null:
		return "opaque"
	if not (material is BaseMaterial3D):
		# A shader can discard or emit alpha arbitrarily; it cannot participate in
		# the narrow collision-padding exception without independent geometry proof.
		return "unsupported"
	var base := material as BaseMaterial3D
	if base.albedo_color.a <= 0.01:
		return "non_opaque"
	if base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and base.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED \
			and not base.proximity_fade_enabled:
		return "opaque"
	return "non_opaque"


func _framebuffer_matches_body_material(
		viewport: Viewport,
		body: Node3D,
		screen: Vector2,
		framebuffer_cache: Dictionary
	) -> bool:
	if viewport == null or body == null or not screen.is_finite():
		return false
	var expected_colors := _body_rendered_material_colors(body)
	if expected_colors.is_empty():
		return false
	var image := _body_framebuffer_image(viewport, framebuffer_cache)
	if image == null or image.is_empty():
		return false
	var rect := viewport.get_visible_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 \
			or image.get_width() <= 0 or image.get_height() <= 0:
		return false
	var scale := Vector2(
		float(image.get_width()) / rect.size.x,
		float(image.get_height()) / rect.size.y)
	var image_center := Vector2(
		(screen.x - rect.position.x) * scale.x,
		(screen.y - rect.position.y) * scale.y)
	var matching_pixels := 0
	var anchor_pixel_matches := false
	for y_offset in range(
			-BODY_COLOR_SAMPLE_RADIUS_PX, BODY_COLOR_SAMPLE_RADIUS_PX + 1):
		for x_offset in range(
				-BODY_COLOR_SAMPLE_RADIUS_PX, BODY_COLOR_SAMPLE_RADIUS_PX + 1):
			var pixel_position := Vector2i(
				clampi(int(roundf(image_center.x)) + x_offset,
					0, image.get_width() - 1),
				clampi(int(roundf(image_center.y)) + y_offset,
					0, image.get_height() - 1))
			var pixel_color := image.get_pixelv(pixel_position)
			var pixel_matches := false
			for expected_v in expected_colors:
				if _framebuffer_color_matches_material(
						pixel_color, expected_v as Color):
					pixel_matches = true
					break
			if not pixel_matches:
				continue
			matching_pixels += 1
			if absi(x_offset) <= 1 and absi(y_offset) <= 1:
				anchor_pixel_matches = true
	return anchor_pixel_matches \
		and matching_pixels >= BODY_COLOR_MIN_MATCHING_PIXELS


func _body_framebuffer_image(
		viewport: Viewport, framebuffer_cache: Dictionary
	) -> Image:
	if bool(framebuffer_cache.get("capture_attempted", false)):
		var cached_v: Variant = framebuffer_cache.get("image", null)
		return cached_v as Image if cached_v is Image else null
	framebuffer_cache["capture_attempted"] = true
	var texture := viewport.get_texture() if viewport != null else null
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	framebuffer_cache["image"] = image
	return image


func _body_rendered_material_colors(body: Node3D) -> Array:
	var colors: Array = []
	if not body.has_method("get_player_observation_render_nodes"):
		return colors
	var render_nodes_v: Variant = body.call(
		"get_player_observation_render_nodes")
	if not (render_nodes_v is Array) or (render_nodes_v as Array).is_empty():
		return colors
	for render_node_v in render_nodes_v as Array:
		if not (render_node_v is MeshInstance3D) \
				or not is_instance_valid(render_node_v):
			return []
		var mesh_instance := render_node_v as MeshInstance3D
		if not mesh_instance.is_visible_in_tree() or mesh_instance.mesh == null \
				or mesh_instance.transparency >= 0.99:
			return []
		if mesh_instance.material_override != null:
			if not _append_body_material_color(
					colors, mesh_instance.material_override):
				return []
			continue
		if mesh_instance.mesh.get_surface_count() <= 0:
			return []
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index)
			# The fallback material has no stable authored colour that can identify
			# this body in a composited frame, so it cannot corroborate a pierce.
			if material == null or not _append_body_material_color(colors, material):
				return []
	return colors


func _append_body_material_color(colors: Array, material: Material) -> bool:
	if not (material is BaseMaterial3D):
		return false
	var base := material as BaseMaterial3D
	# A texture or vertex tint makes the final per-pixel body colour UV/vertex
	# dependent. Without an object-ID pass, treating the constant tint as proof
	# would admit unrelated pixels, so that presentation fails closed.
	if base.albedo_texture != null or base.vertex_color_use_as_albedo \
			or base.albedo_color.a <= 0.05:
		return false
	_append_unique_color(colors, base.albedo_color)
	if base.emission_enabled and base.emission.a > 0.05:
		_append_unique_color(colors, base.emission)
		var energy := maxf(0.0, base.emission_energy_multiplier)
		_append_unique_color(colors, Color(
			base.albedo_color.r + base.emission.r * energy,
			base.albedo_color.g + base.emission.g * energy,
			base.albedo_color.b + base.emission.b * energy,
			base.albedo_color.a))
	return not colors.is_empty()


func _append_unique_color(colors: Array, candidate: Color) -> void:
	for existing_v in colors:
		if (existing_v as Color).is_equal_approx(candidate):
			return
	colors.append(candidate)


func _framebuffer_color_matches_material(pixel: Color, expected: Color) -> bool:
	if pixel.a <= 0.05 or expected.a <= 0.05:
		return false
	# Material colours are linear while framebuffer formats differ by renderer.
	# Compare chroma in both encodings; hue and saturation survive lighting and
	# tone mapping while still distinguishing Aster/Peris/Endo body materials.
	return _colors_have_matching_chroma(pixel, expected) \
		or _colors_have_matching_chroma(pixel.srgb_to_linear(), expected) \
		or _colors_have_matching_chroma(pixel, expected.linear_to_srgb())


func _colors_have_matching_chroma(sample: Color, expected: Color) -> bool:
	if sample.v < 0.05 or expected.v < 0.05 or expected.s < 0.15:
		return false
	if sample.s < maxf(0.12, expected.s * 0.35):
		return false
	var hue_delta := absf(sample.h - expected.h)
	hue_delta = minf(hue_delta, 1.0 - hue_delta)
	if hue_delta > BODY_COLOR_HUE_TOLERANCE:
		return false
	var sample_chroma := Vector3(sample.r, sample.g, sample.b) / sample.v
	var expected_chroma := Vector3(expected.r, expected.g, expected.b) / expected.v
	return sample_chroma.distance_to(expected_chroma) <= 0.48


func _body_point_ray_result(camera: Camera3D, screen: Vector2) -> Dictionary:
	var world := camera.get_world_3d()
	if world == null:
		return {}
	var ray_from := camera.project_ray_origin(screen)
	var ray_direction := camera.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(
		ray_from, ray_from + ray_direction * POINTER_RAY_LENGTH)
	# Area3D nodes are gameplay trigger volumes, not rendered occluders. In the
	# Basin, the shelter Area encloses Aster and Peris at the authored crossing
	# destinations; counting it here made two plainly rendered bodies disappear
	# from presentation-only observation while Endo, just outside the radius,
	# remained visible. Solid physics bodies may still occlude exactly as their
	# rendered world geometry does.
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return world.direct_space_state.intersect_ray(query)


func _command_hit_at(
		camera: Camera3D,
		point: Vector2,
		expected_owner: Node = null
	) -> Dictionary:
	var world := camera.get_world_3d()
	if world == null:
		return {}
	var ray_from := camera.project_ray_origin(point)
	var ray_direction := camera.project_ray_normal(point)
	var excluded: Array[RID] = []
	for _hit_index in range(MAX_POINTER_RAY_HITS):
		var query := PhysicsRayQueryParameters3D.create(
			ray_from, ray_from + ray_direction * POINTER_RAY_LENGTH)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = excluded
		var result := world.direct_space_state.intersect_ray(query)
		if result.is_empty():
			return {}
		var collider := result.get("collider") as CollisionObject3D
		if collider == null:
			return {}
		if not collider.input_ray_pickable:
			# Invisible gameplay trigger Areas are not rendered occluders. Solid
			# bodies are: never tunnel a wall merely because it does not accept
			# pointer input. The registered owner itself may continue to the exact
			# pointer-affordance check below.
			if collider is Area3D:
				var area_rid: RID = result.get("rid", RID())
				if area_rid.is_valid():
					excluded.append(area_rid)
					continue
				return {}
			if expected_owner == null \
					or not _presentation_owner_matches_hit(expected_owner, collider):
				return {}
		if not collider.input_ray_pickable and expected_owner != null \
				and _presentation_owner_matches_hit(expected_owner, collider):
			return result
		if collider.has_signal(&"interaction_requested") \
				or collider.has_signal(&"push_queue_requested"):
			return result
		# A pickable wall or prop is real pointer occlusion. Do not tunnel through it.
		return {}
	return {}


## Compatibility wrapper retained for focused geometry diagnostics. Policy
## discovery uses `_command_hit_at()` so it can test fog at the exact surface
## point instead of approximating visibility from an object's hidden transform.
func _command_collider_at(
		camera: Camera3D,
		point: Vector2,
		expected_owner: Node = null
	) -> CollisionObject3D:
	return _command_hit_at(camera, point, expected_owner).get(
		"collider") as CollisionObject3D


func _render_point_visible(
		camera: Camera3D,
		expected_surface: Node,
		point: Vector2
	) -> bool:
	if camera == null or expected_surface == null:
		return false
	var world := camera.get_world_3d()
	if world == null:
		return false
	var ray_from := camera.project_ray_origin(point)
	var ray_direction := camera.project_ray_normal(point)
	var query := PhysicsRayQueryParameters3D.create(
		ray_from, ray_from + ray_direction * POINTER_RAY_LENGTH)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var collider := result.get("collider") as Node
	return collider != null and _presentation_owner_matches_hit(
		expected_surface, collider)


func _ui_blocks_point(point: Vector2) -> bool:
	var viewport := _observation_viewport()
	if viewport == null:
		return false
	for node_v in viewport.find_children("*", "Control", true, false):
		var control := node_v as Control
		if control == null or not control.is_visible_in_tree() \
				or control.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		# Camera projections are expressed in viewport/canvas coordinates, while a
		# stretched Window can report Control global rects in final framebuffer
		# pixels. Comparing those spaces directly lets opaque scaled HUD panels
		# masquerade as transparent. Convert the candidate through each Control's
		# full canvas/screen transform, then test its local authored rectangle.
		var local_point := control.make_canvas_position_local(point)
		if Rect2(Vector2.ZERO, control.size).has_point(local_point):
			return true
	return false


func _presented_tick(_hud: Node) -> float:
	# The current HUD does not expose a rendered clock value. Exact scheduler time
	# belongs in trace provenance outside the policy observation, never here.
	return 0.0


func _observation_viewport() -> Viewport:
	if _host != null and is_instance_valid(_host):
		return _host.get_viewport()
	return get_viewport()


func _observation_camera(viewport: Viewport) -> Camera3D:
	return viewport.get_camera_3d() if viewport != null else null


func _observation_player() -> Node:
	if _host != null and _host.has_method("get_player_observation_pointer_source"):
		var player_v: Variant = _host.call("get_player_observation_pointer_source")
		if player_v is Node and player_v.has_method(
				"get_player_pointer_affordance"):
			return player_v as Node
	return null


func _observation_hud() -> Node:
	for node_v in get_tree().get_nodes_in_group(
			&"player_observation_hud_presenters"):
		if node_v.has_method("get_player_observation"):
			return node_v
	return null


func _quantize_screen(point: Vector2) -> Array[int]:
	return [
		int(roundf(point.x / SCREEN_QUANTUM_PX) * SCREEN_QUANTUM_PX),
		int(roundf(point.y / SCREEN_QUANTUM_PX) * SCREEN_QUANTUM_PX),
	]


func _affordance_token(target_key: int) -> String:
	if not _affordance_tokens.has(target_key):
		_affordance_tokens[target_key] = "aff_%04d" % _next_affordance_token
		_next_affordance_token += 1
	return str(_affordance_tokens[target_key])


func _portrait_token(portrait_key: Variant) -> String:
	if not _portrait_tokens.has(portrait_key):
		_portrait_tokens[portrait_key] = "portrait_%04d" % _next_portrait_token
		_next_portrait_token += 1
	return str(_portrait_tokens[portrait_key])


func _body_token(body_key: Variant) -> String:
	if not _body_tokens.has(body_key):
		_body_tokens[body_key] = "body_%04d" % _next_body_token
		_next_body_token += 1
	return str(_body_tokens[body_key])


func _ground_token(bin_key: String) -> String:
	if not _ground_tokens.has(bin_key):
		_ground_tokens[bin_key] = "ground_%04d" % _next_ground_token
		_next_ground_token += 1
	return str(_ground_tokens[bin_key])


func _screen_record_less(a: Dictionary, b: Dictionary) -> bool:
	var screen_a: Array = a.get("screen", [])
	var screen_b: Array = b.get("screen", [])
	var ay := int(screen_a[1]) if screen_a.size() >= 2 else 0
	var by := int(screen_b[1]) if screen_b.size() >= 2 else 0
	if ay != by:
		return ay < by
	var ax := int(screen_a[0]) if screen_a.size() >= 2 else 0
	var bx := int(screen_b[0]) if screen_b.size() >= 2 else 0
	if ax != bx:
		return ax < bx
	return str(a.get("token", "")) < str(b.get("token", ""))
