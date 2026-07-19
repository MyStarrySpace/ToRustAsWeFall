extends "res://scripts/scene_chunks/scene_chunk.gd"

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")

# One ordinary shelter stretch: the three specialist approaches are deliberately
# far enough apart to make deployment a real decision, while the final Endo run
# is a contiguous pressure line rather than a timer lock.
const FLOOR_CENTER := Vector3(162.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(328.0, 0.1, 24.0)

const WEST_SHELTER_POS := Vector3(8.0, 0.45, 0.0)
const SCOUT_PERCH_POS := Vector3(52.0, 0.45, -4.0)
const ECHO_COUPLER_POS := Vector3(106.0, 0.45, 5.8)
const MID_SEAM_POS := Vector3(132.0, 0.45, -1.8)
const SHORT_BLOOM_POS := Vector3(134.5, 0.45, 3.6)
const LURE_SPINDLE_POS := Vector3(194.0, 0.45, 0.0)
const HIDE_SLIT_POS := Vector3(258.0, 0.45, -3.2)
const EAST_SHELTER_POS := Vector3(316.0, 0.45, 0.0)
const RECOVERY_RIG_POS := Vector3(258.0, 0.45, -1.7)

const DEPART_WORK_SECONDS := 6.0
const SCOUT_WORK_SECONDS := 12.0
const ECHO_WORK_SECONDS := 12.0
const LURE_WORK_SECONDS := 14.0
const SEAM_WORK_SECONDS := 12.0
const HIDE_WORK_SECONDS := 12.0
const RECOVERY_WORK_SECONDS := 12.0
const LURE_DURATION := 42.0
const INTERACT_RADIUS := 2.4
const SHELTER_RADIUS := 2.6
const SHELTER_ATP_COST := 1.0
const SHELTER_REST_SECONDS := 4.0
const PERIS_TUNE_BONUS := 5.0
const ARRIVAL_BUFFER := 0.1
const SWARM_SPEED := 11.0
const SWARM_START_X := 312.5
const SWARM_LURE_X := 197.0
const SWARM_HIDE_X := 258.2
const SWARM_OFFSETS := [-1.8, 0.0, 1.8]

const DECORATION_PROFILE := {
	"id": "survival_range",
	"x0": 0.0,
	"x1": 324.0,
	"width": 24.0,
	"wall_height": 4.8,
	"ground_y": 0.0,
	"seed": 0x5A17E7,
	"program": "boundary",
	"spacing": 11.8,
	"floor_tile": "deck_metal",
	"wall_tile": "rust_iron",
	"floor_tint": Color(0.12, 0.14, 0.16),
	"wall_tint": Color(0.17, 0.18, 0.20),
	"trim": Color(0.38, 0.41, 0.43),
	"inset": Color(0.045, 0.052, 0.06),
	"service": Color(0.19, 0.22, 0.23),
	"rust": Color(0.38, 0.16, 0.07),
	"glow": Color(0.72, 0.34, 0.16),
	"light": Color(0.48, 0.36, 0.29),
	"signs": ["SHELTER RANGE / 03", "REFUGE SEAM  >", "LIVE SWEEP COURSE"],
}

const SPAWNS := {
	"aster": Vector3(7.0, 0.5, 1.4),
	"peris": Vector3(5.4, 0.5, 0.0),
	"endo": Vector3(6.0, 0.5, -1.7),
}

var _departure_interactable
var _scout_interactable
var _echo_interactable
var _lure_interactable
var _seam_interactable
var _direct_interactable
var _hide_interactable
var _recovery_interactable
var _east_shelter_interactable

var _west_beacon_material: StandardMaterial3D
var _east_beacon_material: StandardMaterial3D
var _spindle_material: StandardMaterial3D
var _echo_material: StandardMaterial3D
var _seam_material: StandardMaterial3D
var _hide_material: StandardMaterial3D
var _swarm_materials: Array[StandardMaterial3D] = []
var _swarm_markers: Array[MeshInstance3D] = []

var _departed := false
var _route_phase := "briefing"
var _last_outcome := ""
var _segments_completed: Array[String] = []
var _scouted := false
var _echo_tuned := false
var _lure_active := false
var _lure_remaining := 0.0
var _seam_crossed := false
var _hide_phase := "ready"
var _mid_seam_damage := 0.0
var _shelter_reached := false
var _recovery_assist := false
var _recovery_count := 0
var _decoration_audit := {}

func _build_chunk() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.09, 0.095, 0.11), "deck_metal")
	_add_box(self, Vector3(162.0, 2.4, -12.1), Vector3(328.0, 4.8, 0.3), Color(0.13, 0.14, 0.16))
	_add_box(self, Vector3(162.0, 2.4, 12.1), Vector3(328.0, 4.8, 0.3), Color(0.13, 0.14, 0.16))

	for i in range(19):
		var blend := float(i) / 18.0
		_add_light(
			self,
			Vector3(8.0 + float(i) * 17.0, 3.4, 0.0),
			Color(0.28 + blend * 0.22, 0.3 + blend * 0.16, 0.38 + blend * 0.18),
			1.1 + blend * 1.4,
			16.0
		)

	_build_range_dressing()
	_build_west_shelter()
	_build_scout_perch()
	_build_echo_coupler()
	_build_mid_seam()
	_build_lure_spindle()
	_build_hide_slit()
	_build_east_shelter()
	_build_swarm_markers()
	_decoration_audit = LevelDecoratorScript.decorate_corridor(self, DECORATION_PROFILE)
	reset_preview_state()

func _process(delta: float) -> void:
	_update_range(delta)

func headless_process(delta: float) -> void:
	_update_range(delta)

func get_scene_title() -> String:
	return "Shelter-To-Shelter Range"

func get_scene_help() -> String:
	return "Leave the west shelter, let Aster mark the route, tune Peris's mid-course echo coupler and lure spindle, then get Endo through the seam and slit. Bring the full conscious party to the east shelter and spend one ATP each to complete the rest."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"west_shelter": WEST_SHELTER_POS,
		"scout_perch": SCOUT_PERCH_POS,
		"echo_coupler": ECHO_COUPLER_POS,
		"mid_seam": MID_SEAM_POS,
		"short_bloom": SHORT_BLOOM_POS,
		"lure_spindle": LURE_SPINDLE_POS,
		"hide_slit": HIDE_SLIT_POS,
		"east_shelter": EAST_SHELTER_POS,
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 3,
		"time": 0.68,
		"routing_mode": "safe",
		"note_default": "This range boots like a real expedition slice: all three characters start healthy, all overlays can stack, and the route only becomes safe if the team sequences scout, lure, seam, hide, and shelter cleanly.",
	}

func get_preview_abilities() -> Array:
	# Display names + descriptions + tuning live in data/abilities/en/abilities.xlsx (per-context rows).
	return AbilityData.for_context("survival_range")
func get_preview_state() -> Dictionary:
	return {
		"departed": _departed,
		"route_phase": _route_phase,
		"last_outcome": _last_outcome,
		"segments_completed": _segments_completed.duplicate(),
		"scouted": _scouted,
		"echo_tuned": _echo_tuned,
		"lure_active": _lure_active,
		"lure_remaining": _lure_remaining,
		"seam_crossed": _seam_crossed,
		"hide_phase": _hide_phase,
		"mid_seam_damage": _mid_seam_damage,
		"shelter_reached": _shelter_reached,
		"shelter_rested": _shelter_reached,
		"complete": _route_phase == "complete",
		"recovery_assist": _recovery_assist,
		"recovery_count": _recovery_count,
	}

func get_route_timing_predictions() -> Dictionary:
	return {
		"staged_safe": predict_route_timing("staged_safe"),
		"optimal_safe": predict_route_timing("optimal_safe"),
		"tuned_direct": predict_route_timing("tuned_direct"),
		"greedy_direct": predict_route_timing("greedy_direct"),
	}

func get_pacing_contract() -> Dictionary:
	var direct := predict_route_timing("tuned_direct")
	var safe := predict_route_timing("optimal_safe")
	var shortest: Dictionary = direct if float(direct.get("total_time", INF)) <= float(safe.get("total_time", INF)) else safe
	var active_seconds := float(shortest.get("active_time", 0.0))
	var total_seconds := float(shortest.get("total_time", 0.0))
	var segments: Dictionary = shortest.get("segments", {})
	var category_seconds := {
		# These are mutually exclusive mechanics, not arbitrary distance bands:
		# Aster reads the course, Endo stages the crossing, Peris builds the
		# decoy signal through two physical stations, and Endo crosses/escapes.
		"route_analysis": _segment_active_seconds(segments, "depart") + _segment_active_seconds(segments, "scout"),
		"survivor_staging": _segment_active_seconds(segments, "stage_endo"),
		"decoy_calibration": _segment_active_seconds(segments, "echo") + _segment_active_seconds(segments, "stage_peris") + _segment_active_seconds(segments, "lure"),
		"hazard_crossing": _segment_active_seconds(segments, "cross") + _segment_active_seconds(segments, "hide"),
		"shelter_sprint": _segment_active_seconds(segments, "shelter"),
	}
	return {
		"contract_id": "ordinary_shelter_stretch_v1",
		"target_min_seconds": 180.0,
		"target_max_seconds": 300.0,
		"shortest_profile": str(shortest.get("profile", "")),
		"shortest_modeled_clear_seconds": total_seconds,
		"active_seconds": active_seconds,
		"active_share": active_seconds / maxf(total_seconds, 0.001),
		"meaningful_active_seconds": active_seconds,
		"total_play_seconds": total_seconds,
		"active_ratio": active_seconds / maxf(total_seconds, 0.001),
		"max_dead_gap_seconds": 0.0,
		"max_single_mode_seconds": _max_route_mode_seconds(segments),
		"category_seconds": category_seconds,
		"movement_seconds": float(shortest.get("movement_time", 0.0)),
		"work_seconds": float(shortest.get("work_time", 0.0)),
		"route_distance_meters": float(shortest.get("route_distance", 0.0)),
		"decision_count": 2,
		"branch_count": 3,
		"decisions": ["safe seam or hot bloom", "spend Peris tune or risk the short window"],
		"branches": ["scouted safe", "tuned direct", "failed window into recovery"],
		"failure_recovery_work_seconds": RECOVERY_WORK_SECONDS,
		"idle_lock_seconds": 0.0,
	}

func _segment_active_seconds(segments: Dictionary, segment_id: String) -> float:
	var segment_variant: Variant = segments.get(segment_id, {})
	if not segment_variant is Dictionary:
		return 0.0
	return float((segment_variant as Dictionary).get("total_time", 0.0))

func _max_route_mode_seconds(segments: Dictionary) -> float:
	var longest := 0.0
	for segment_variant in segments.values():
		if not segment_variant is Dictionary:
			continue
		var segment := segment_variant as Dictionary
		longest = maxf(longest, float(segment.get("travel_time", 0.0)))
		longest = maxf(longest, float(segment.get("dwell_time", 0.0)))
	return longest

func get_decoration_audit() -> Dictionary:
	return _decoration_audit.duplicate(true)

func predict_route_timing(profile := "optimal_safe") -> Dictionary:
	var spec := _route_timing_profile(profile)
	if spec.is_empty():
		return {}

	var positions := get_spawn_positions()
	var segments := {}
	var total_time := 0.0
	var routing_mode := str(spec.get("routing_mode", "safe"))
	var use_peris_tune := bool(spec.get("use_peris_tune", false))
	var scout_required := bool(spec.get("scout_required", true))
	var lure_required := bool(spec.get("lure_required", true))
	var cross_target: Vector3 = spec.get("cross_target", MID_SEAM_POS)
	var cross_running := bool(spec.get("cross_running", false))
	var hide_running := bool(spec.get("hide_running", true))
	var shelter_running := bool(spec.get("shelter_running", true))

	var depart: Dictionary = _predict_station_action(
		"aster",
		positions["aster"],
		WEST_SHELTER_POS,
		INTERACT_RADIUS,
		false,
		DEPART_WORK_SECONDS,
		"depart"
	)
	segments["depart"] = depart
	positions["aster"] = depart["end_position"]
	total_time += float(depart.get("total_time", 0.0))

	if scout_required:
		var scout: Dictionary = _predict_station_action(
			"aster",
			positions["aster"],
			SCOUT_PERCH_POS,
			INTERACT_RADIUS,
			false,
			SCOUT_WORK_SECONDS,
			"scout"
		)
		segments["scout"] = scout
		positions["aster"] = scout["end_position"]
		total_time += float(scout.get("total_time", 0.0))

	if lure_required:
		var stage_endo: Dictionary = _predict_station_action(
			"endo",
			positions["endo"],
			cross_target,
			INTERACT_RADIUS,
			cross_running,
			0.0,
			"stage_endo"
		)
		segments["stage_endo"] = stage_endo
		positions["endo"] = stage_endo["end_position"]
		total_time += float(stage_endo.get("total_time", 0.0))

		var echo: Dictionary = _predict_station_action(
			"peris",
			positions["peris"],
			ECHO_COUPLER_POS,
			INTERACT_RADIUS,
			false,
			ECHO_WORK_SECONDS,
			"echo"
		)
		segments["echo"] = echo
		positions["peris"] = echo["end_position"]
		total_time += float(echo.get("total_time", 0.0))

		var stage_peris: Dictionary = _predict_station_action(
			"peris",
			positions["peris"],
			LURE_SPINDLE_POS,
			INTERACT_RADIUS,
			false,
			0.0,
			"stage_peris"
		)
		segments["stage_peris"] = stage_peris
		positions["peris"] = stage_peris["end_position"]
		total_time += float(stage_peris.get("total_time", 0.0))

		var lure: Dictionary = _predict_station_action(
			"peris",
			positions["peris"],
			LURE_SPINDLE_POS,
			INTERACT_RADIUS,
			false,
			LURE_WORK_SECONDS,
			"lure"
		)
		segments["lure"] = lure
		total_time += float(lure.get("total_time", 0.0))

	var seam: Dictionary = _predict_station_action(
		"endo",
		positions["endo"],
		cross_target,
		INTERACT_RADIUS,
		cross_running,
		SEAM_WORK_SECONDS,
		"cross"
	)
	segments["cross"] = seam
	positions["endo"] = seam["end_position"]
	var pre_window_total := total_time

	var cross_mode := "short_bloom" if cross_target.distance_to(SHORT_BLOOM_POS) <= 0.01 else "seam"
	var scouted := scout_required
	var lure_open := lure_required
	var predicted_damage := _predict_cross_damage(scouted, lure_open, routing_mode == "direct", cross_mode == "short_bloom")

	var hide: Dictionary = _predict_station_action(
		"endo",
		positions["endo"],
		HIDE_SLIT_POS,
		INTERACT_RADIUS,
		hide_running,
		HIDE_WORK_SECONDS,
		"hide"
	)
	segments["hide"] = hide
	positions["endo"] = hide["end_position"]

	if not lure_required:
		total_time += float(seam.get("total_time", 0.0))
		total_time += float(hide.get("total_time", 0.0))
		return _with_route_metrics({
			"profile": profile,
			"routing_mode": routing_mode,
			"success": false,
			"outcome": "hide_without_window",
			"cross_mode": cross_mode,
			"use_peris_tune": false,
			"predicted_damage": predicted_damage,
			"predicted_endo_hp": maxf(0.0, 100.0 - predicted_damage),
			"total_time": total_time,
			"segments": segments,
		})

	var active_window := LURE_DURATION + (PERIS_TUNE_BONUS if use_peris_tune else 0.0)
	var window_elapsed := float(seam.get("total_time", 0.0)) + float(hide.get("total_time", 0.0))
	var window_margin := active_window - window_elapsed

	if window_margin < 0.0:
		return _with_route_metrics({
			"profile": profile,
			"routing_mode": routing_mode,
			"success": false,
			"outcome": "late_window",
			"cross_mode": cross_mode,
			"use_peris_tune": use_peris_tune,
			"predicted_damage": predicted_damage,
			"predicted_endo_hp": maxf(0.0, 100.0 - predicted_damage),
			"window_time": active_window,
			"window_elapsed": window_elapsed,
			"window_margin": window_margin,
			"total_time": pre_window_total + active_window,
			"segments": segments,
		})

	total_time = pre_window_total
	total_time += float(seam.get("total_time", 0.0))
	total_time += float(hide.get("total_time", 0.0))

	# The party can be routed together once Endo releases the sprint. Model that
	# authored parallel assembly by its slowest member, then charge the explicit
	# hearth interaction. The combined distance still records all three routes.
	var party_movements := {}
	var shelter_travel_time := 0.0
	var shelter_travel_distance := 0.0
	for char_id in ["aster", "peris", "endo"]:
		var movement: Dictionary = _predict_station_action(
			char_id,
			positions[char_id],
			EAST_SHELTER_POS,
			SHELTER_RADIUS,
			shelter_running,
			0.0,
			"shelter_%s" % char_id
		)
		party_movements[char_id] = movement
		shelter_travel_time = maxf(shelter_travel_time, float(movement.get("travel_time", 0.0)))
		shelter_travel_distance += float(movement.get("travel_distance", 0.0))
	var shelter := {
		"label": "shelter",
		"character": "party",
		"running": shelter_running,
		"target": EAST_SHELTER_POS,
		"end_position": EAST_SHELTER_POS,
		"arrival_radius": SHELTER_RADIUS,
		"party_movements": party_movements,
		"travel_distance": shelter_travel_distance,
		"travel_time": shelter_travel_time,
		"dwell_time": SHELTER_REST_SECONDS,
		"total_time": shelter_travel_time + SHELTER_REST_SECONDS,
	}
	segments["shelter"] = shelter
	total_time += float(shelter.get("total_time", 0.0))

	return _with_route_metrics({
		"profile": profile,
		"routing_mode": routing_mode,
		"success": true,
		"outcome": "success",
		"cross_mode": cross_mode,
		"use_peris_tune": use_peris_tune,
		"predicted_damage": predicted_damage,
		"predicted_endo_hp": maxf(0.0, 100.0 - predicted_damage),
		"window_time": active_window,
		"window_elapsed": window_elapsed,
		"window_margin": window_margin,
		"total_time": total_time,
		"segments": segments,
	})

func get_preview_overlay_status(overlay_id: String, _current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return [
				"DATA: scout perch links the refuge seam to the hide slit and east shelter light.",
				"Survey: %s" % ("resolved" if _scouted else "blind"),
				"Route: %s" % ("safe seam" if _get_routing_mode() == "safe" else "direct bloom"),
			]
		"peris":
			return [
				"FOG: the echo coupler and spindle remember the slit as one signal chain.",
				"Echo: %s" % ("tuned" if _echo_tuned else "unresolved"),
				"Lure: %s" % ("open %.1fs" % _lure_remaining if _lure_active else "cold"),
				"Blur: %s" % ("holding the sweep off the slit" if _lure_active else "back in the corridor"),
			]
		"endo":
			return [
				"SURVIVAL: west shelter -> scout seam -> hide slit -> east shelter.",
				"Margin: HP %.0f / ATP %.0f" % [_get_character_stat("endo", "hp"), _get_character_stat("endo", "atp")],
				"Next: %s" % _current_route_instruction(),
			]
		_:
			return []

func reset_preview_state() -> void:
	_departed = false
	_route_phase = "briefing"
	_last_outcome = ""
	_segments_completed.clear()
	_scouted = false
	_echo_tuned = false
	_lure_active = false
	_lure_remaining = 0.0
	_seam_crossed = false
	_hide_phase = "ready"
	_mid_seam_damage = 0.0
	_shelter_reached = false
	_recovery_assist = false
	_recovery_count = 0
	_set_preview_step("survival_range_briefing")

	for interactable in [_departure_interactable, _scout_interactable, _echo_interactable, _lure_interactable, _seam_interactable, _direct_interactable, _hide_interactable, _recovery_interactable, _east_shelter_interactable]:
		if interactable != null and interactable.has_method("reset"):
			interactable.reset()

	for i in range(_swarm_markers.size()):
		var marker := _swarm_markers[i]
		if marker != null:
			marker.position = Vector3(SWARM_START_X, 0.72, SWARM_OFFSETS[i])

	_refresh_interaction_gates()
	_update_visual_state()

func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	match ability_id:
		"aster_focus":
			if _departed and not _scouted and _get_character_position("aster").distance_to(SCOUT_PERCH_POS) <= INTERACT_RADIUS + 0.6:
				_scouted = true
				_mark_segment("scouted")
				_route_phase = "scouted" if _route_phase == "briefing" or _route_phase == "departed" else _route_phase
				_set_preview_step("survival_range_scouted")
				_show_note("Aster's mark resolves the refuge seam and the slit.", 2.4)
				_refresh_interaction_gates()
				_update_visual_state()
			return {
				"characters": {
					"aster": {"sta_delta": 8.0},
				},
			}
		"peris_tune":
			if _lure_active:
				_lure_remaining += PERIS_TUNE_BONUS
				_show_note("Peris keeps the lure thread alive a little longer.", 2.2)
				_update_visual_state()
			return {
				"characters": {
					"peris": {"sta_delta": 10.0},
				},
			}
		"endo_patch":
			return {
				"characters": {
					"endo": {"hp_delta": 8.0, "sta_delta": 10.0},
				},
			}
		_:
			return {}

func on_preview_routing_changed(mode: String) -> void:
	if mode == "direct":
		_show_note("Direct routing skims the hot bloom. It is shorter, but it burns the margin fast.", 2.5)
	else:
		_show_note("Safe routing keeps Endo on the refuge seam. It takes the full setup, but it preserves the run.", 2.5)
	_refresh_interaction_gates()

func depart_range() -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if not _require_station("", WEST_SHELTER_POS, "the west shelter beacon"):
		return false
	_departed = true
	_mark_segment("departed")
	_route_phase = "departed"
	_set_preview_step("survival_range_departed")
	_show_message("The team leaves shelter. Scout first, then open the window.", 2.0)
	_refresh_interaction_gates()
	_update_visual_state()
	return true

func survey_route() -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if not _departed:
		_show_message("Take the shelter briefing before marking the live range.", 1.4)
		return false
	if not _require_station("aster", SCOUT_PERCH_POS, "the scout perch"):
		return false
	_scouted = true
	_mark_segment("scouted")
	if _route_phase in ["briefing", "departed"]:
		_route_phase = "scouted"
	_set_preview_step("survival_range_scouted")
	_show_message("Aster marks the refuge seam and the hide slit.", 1.8)
	_refresh_interaction_gates()
	_update_visual_state()
	return true

func activate_range_lure() -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if not _departed:
		_show_message("The range has not left shelter control yet.", 1.4)
		return false
	if not _scouted:
		_show_message("Aster has to resolve the course before Peris can tune either route.", 1.5)
		return false
	if not _echo_tuned:
		_show_message("Peris has to tune the mid-course echo coupler before the spindle can carry a stable decoy.", 1.7)
		return false
	if not _require_station("peris", LURE_SPINDLE_POS, "the lure spindle"):
		return false
	_lure_active = true
	_lure_remaining = LURE_DURATION + (PERIS_TUNE_BONUS if _recovery_assist else 0.0)
	_recovery_assist = false
	_mark_segment("lure")
	_route_phase = "window"
	_set_preview_step("survival_range_window")
	_show_message("Peris opens a lure window across the corridor.", 1.8)
	_refresh_interaction_gates()
	_update_visual_state()
	return true

func tune_echo_coupler() -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if not _departed or not _scouted:
		_show_message("Aster has to resolve the course before Peris can tune its echo return.", 1.5)
		return false
	if not _require_station("peris", ECHO_COUPLER_POS, "the echo coupler"):
		return false
	_echo_tuned = true
	_mark_segment("echo")
	_route_phase = "calibrated"
	_set_preview_step("survival_range_echo_tuned")
	_show_message("Peris locks the coupler onto the hide slit. The spindle can now carry the decoy forward.", 2.0)
	_refresh_interaction_gates()
	_update_visual_state()
	return true

func cross_seam() -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if not _departed:
		_show_message("Leave the west shelter before entering the live lane.", 1.4)
		return false
	var cross_mode := _crossing_mode()
	if cross_mode == "":
		_show_message("Move Endo to the refuge seam or the short bloom first.", 1.4)
		return false

	var damage := 4.0
	if cross_mode == "short_bloom":
		damage += 14.0
	if not _scouted:
		damage += 10.0
	if not _lure_active:
		damage += 12.0
	if _get_routing_mode() == "direct":
		damage += 6.0

	_mid_seam_damage = damage
	_seam_crossed = true
	_mark_segment("seam")
	_route_phase = "midway"
	_set_preview_step("survival_range_midway")
	_adjust_character_stat("endo", "hp", -damage)
	_adjust_character_stat("endo", "sta", -10.0 if cross_mode == "short_bloom" else -6.0)
	_show_message(
		"Endo %s and pays %.0f HP." % ["cuts the hot bloom" if cross_mode == "short_bloom" else "threads the refuge seam", damage],
		1.8
	)
	if _get_character_stat("endo", "hp") <= 0.0:
		_fail_range("bloomed_out")
		return false
	_refresh_interaction_gates()
	_update_visual_state()
	return true

func commit_hide() -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if not _require_station("endo", HIDE_SLIT_POS, "the hide slit"):
		return false
	if not _seam_crossed:
		_show_message("The slit only matters after Endo crosses the seam.", 1.4)
		return false
	if not _lure_active:
		_fail_range("hide_without_window")
		return false
	# The twelve-second slit action is the active concealment/read beat. Once it
	# completes the sweep has committed to Peris's decoy, so the player gets an
	# immediate sprint instead of waiting out an otherwise dead timer.
	_hide_phase = "run"
	_mark_segment("hide")
	_mark_segment("release")
	_route_phase = "run"
	_set_preview_step("survival_range_run")
	_show_message("The sweep commits to the decoy. Run for the east shelter.", 1.6)
	_refresh_interaction_gates()
	_update_visual_state()
	return true

func recover_from_failure() -> bool:
	if _route_phase != "failed":
		return false
	if not _require_station("", RECOVERY_RIG_POS, "the reset winch"):
		return false
	var gs = _get_game_state()
	if gs != null and gs.characters.has("endo") and gs.is_downed("endo"):
		var preserved_atp: float = float(gs.get_stat("endo", "atp"))
		gs.restore_character("endo")
		gs.set_stat("endo", "hp", 25.0)
		gs.set_stat("endo", "atp", preserved_atp)
	_recovery_count += 1
	_recovery_assist = true
	_lure_active = false
	_lure_remaining = 0.0
	_seam_crossed = false
	_hide_phase = "ready"
	_mid_seam_damage = 0.0
	_last_outcome = "recovered"
	_route_phase = "calibrated" if _echo_tuned else ("scouted" if _scouted else "departed")
	_mark_segment("recovery")
	_set_character_position("endo", MID_SEAM_POS + Vector3(-INTERACT_RADIUS + 0.25, 0.05, 0.0))
	_adjust_character_stat("endo", "atp", -1.0)
	for interactable in [_lure_interactable, _seam_interactable, _direct_interactable, _hide_interactable]:
		if interactable != null and interactable.has_method("reset"):
			interactable.reset()
	_set_preview_step("survival_range_recovered")
	_show_message("The winch returns Endo to the seam. Its stored pulse grants one recovery-tuned window.", 2.2)
	_refresh_interaction_gates()
	_update_visual_state()
	return true

func _build_range_dressing() -> void:
	# Construction hierarchy: two service trenches establish the long datum;
	# measured ribs split it into legible bays; smaller ticks make distance and
	# sprint progress readable without placing a single obstacle in the lane.
	for side in [-1.0, 1.0]:
		_add_box(
			self,
			Vector3(FLOOR_CENTER.x, 0.025, float(side) * 8.9),
			Vector3(FLOOR_SIZE.x - 4.0, 0.025, 1.1),
			Color(0.035, 0.042, 0.048),
			Color.BLACK,
			0.0,
			"RangeDrain_%s" % ("North" if side < 0.0 else "South")
		)
		for rail_offset in [-0.64, 0.64]:
			_add_box(
				self,
				Vector3(FLOOR_CENTER.x, 0.045, float(side) * 8.9 + float(rail_offset)),
				Vector3(FLOOR_SIZE.x - 4.0, 0.035, 0.09),
				Color(0.34, 0.37, 0.38),
				Color.BLACK,
				0.0
			)

	var rib_xs := [24.0, 64.0, 104.0, 144.0, 184.0, 224.0, 264.0, 304.0]
	for rib_index in range(rib_xs.size()):
		var x := float(rib_xs[rib_index])
		for side in [-1.0, 1.0]:
			_add_box(self, Vector3(x, 2.15, float(side) * 11.15), Vector3(0.42, 4.3, 1.45),
				Color(0.24, 0.25, 0.26), Color.BLACK, 0.0,
				"RangeRib_%02d_%s" % [rib_index, "N" if side < 0.0 else "S"])
		_add_box(self, Vector3(x, 4.35, 0.0), Vector3(0.42, 0.36, 22.0),
			Color(0.27, 0.28, 0.29), Color.BLACK, 0.0, "RangeRibBeam_%02d" % rib_index)
		_add_box(self, Vector3(x, 0.035, 0.0), Vector3(0.11, 0.025, 19.0),
			Color(0.06, 0.065, 0.072), Color.BLACK, 0.0, "RangeDatum_%02d" % rib_index)
		_add_label(self, "%02d0 m" % (rib_index * 4 + 2), Vector3(x, 1.0, -10.75), Color(0.56, 0.61, 0.64))

	for tick_index in range(1, 40):
		var tick_x := 8.0 + float(tick_index) * 7.6
		var major := tick_index % 5 == 0
		_add_box(self, Vector3(tick_x, 0.04, -7.25),
			Vector3(0.06 if not major else 0.11, 0.03, 0.7 if not major else 1.35),
			Color(0.30, 0.33, 0.35) if not major else Color(0.67, 0.37, 0.18),
			Color.BLACK, 0.0, "RangeMeasure_%02d" % tick_index)

	# The safe and direct readings are physical floor datums. Their colors match
	# the station emissives, so the choice remains readable at camera height.
	_add_box(self, Vector3(92.0, 0.055, -1.8), Vector3(78.0, 0.03, 0.16),
		Color(0.18, 0.34, 0.42), Color(0.38, 0.68, 0.88), 0.18, "RangeSafeDatum")
	_add_box(self, Vector3(93.0, 0.057, 3.6), Vector3(81.0, 0.03, 0.18),
		Color(0.40, 0.18, 0.08), Color(0.92, 0.38, 0.12), 0.26, "RangeDirectDatum")

	var sector_labels := [
		[36.0, "01 / READ"],
		[112.0, "02 / COMMIT"],
		[196.0, "03 / DECOY"],
		[266.0, "04 / CONCEAL"],
		[306.0, "05 / SHELTER"],
	]
	for label_index in range(sector_labels.size()):
		var spec: Array = sector_labels[label_index]
		_add_label(self, str(spec[1]), Vector3(float(spec[0]), 2.85, 10.7),
			Color(0.74, 0.68, 0.58))

func _build_west_shelter() -> void:
	_add_box(self, WEST_SHELTER_POS + Vector3(-1.2, 0.0, 0.0), Vector3(6.8, 0.3, 6.2), Color(0.1, 0.11, 0.09))
	_add_box(self, WEST_SHELTER_POS + Vector3(-3.6, 1.7, 0.0), Vector3(0.3, 3.4, 6.2), Color(0.14, 0.13, 0.11))
	_add_box(self, WEST_SHELTER_POS + Vector3(0.0, 1.7, -3.0), Vector3(7.0, 3.4, 0.3), Color(0.14, 0.13, 0.11))
	_add_label(self, "WEST SHELTER", WEST_SHELTER_POS + Vector3(0.0, 2.5, 0.0), Color(0.94, 0.82, 0.52))
	_west_beacon_material = _make_material(Color(0.2, 0.2, 0.18), Color(0.9, 0.76, 0.42), 0.35)
	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.34
	beacon_mesh.height = 0.68
	beacon.mesh = beacon_mesh
	beacon.material_override = _west_beacon_material
	beacon.position = WEST_SHELTER_POS + Vector3(0.0, 1.15, 0.0)
	add_child(beacon)
	_departure_interactable = _add_interactable(
		self,
		"RangeDepartureInteractable",
		"Shelter Briefing",
		WEST_SHELTER_POS + Vector3(0.8, 0.0, 0.0),
		"LEAVE",
		"",
		DEPART_WORK_SECONDS,
		false,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_departure_interactable.interacted.connect(depart_range)

func _build_scout_perch() -> void:
	_add_box(self, SCOUT_PERCH_POS + Vector3(0.0, -0.04, 0.0), Vector3(5.0, 0.22, 4.2), Color(0.11, 0.13, 0.15))
	_add_box(self, SCOUT_PERCH_POS + Vector3(2.2, 1.3, 0.0), Vector3(0.3, 2.4, 4.2), Color(0.16, 0.18, 0.22))
	_add_label(self, "SCOUT PERCH", SCOUT_PERCH_POS + Vector3(0.0, 2.2, 0.0), Color(0.62, 0.8, 0.96))
	_scout_interactable = _add_interactable(
		self,
		"RangeScoutInteractable",
		"Scout Perch",
		SCOUT_PERCH_POS + Vector3(-0.6, 0.0, 0.0),
		"MARK",
		"aster",
		SCOUT_WORK_SECONDS,
		false,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_scout_interactable.interacted.connect(survey_route)

func _build_echo_coupler() -> void:
	# A physical midpoint for Peris keeps the long decoy deployment leg readable:
	# the player first captures the corridor echo here, then carries that tuned
	# signal forward to the lure spindle instead of issuing one minute-long walk.
	_add_box(self, ECHO_COUPLER_POS + Vector3(0.0, -0.04, 0.0), Vector3(5.4, 0.2, 4.2), Color(0.10, 0.12, 0.14))
	_add_box(self, ECHO_COUPLER_POS + Vector3(0.0, 0.65, 1.65), Vector3(4.8, 1.3, 0.28), Color(0.14, 0.17, 0.19))
	_add_label(self, "ECHO COUPLER", ECHO_COUPLER_POS + Vector3(0.0, 2.25, 0.0), Color(0.64, 0.82, 0.92))
	_echo_material = _make_material(Color(0.15, 0.19, 0.21), Color(0.42, 0.76, 0.92), 0.18)
	var coupler := MeshInstance3D.new()
	var coupler_mesh := CylinderMesh.new()
	coupler_mesh.top_radius = 0.72
	coupler_mesh.bottom_radius = 0.72
	coupler_mesh.height = 0.34
	coupler.mesh = coupler_mesh
	coupler.rotation_degrees.z = 90.0
	coupler.material_override = _echo_material
	coupler.position = ECHO_COUPLER_POS + Vector3(0.0, 0.9, 0.0)
	coupler.name = "RangeEchoCouplerTarget"
	add_child(coupler)
	_echo_interactable = _add_interactable(
		self,
		"RangeEchoInteractable",
		"Echo Coupler",
		ECHO_COUPLER_POS + Vector3(-0.7, 0.0, 0.0),
		"TUNE",
		"peris",
		ECHO_WORK_SECONDS,
		false,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_echo_interactable.interacted.connect(tune_echo_coupler)

func _build_mid_seam() -> void:
	_add_label(self, "REFUGE SEAM", MID_SEAM_POS + Vector3(0.0, 2.2, 0.0), Color(0.78, 0.88, 0.94))
	_add_box(self, MID_SEAM_POS + Vector3(0.0, -0.03, 0.0), Vector3(7.0, 0.12, 2.0), Color(0.16, 0.17, 0.19))
	_add_box(self, MID_SEAM_POS + Vector3(0.0, 0.06, 2.8), Vector3(9.0, 0.12, 3.0), Color(0.22, 0.12, 0.08), Color(0.72, 0.28, 0.1), 0.3)
	_add_label(self, "SHORT BLOOM", SHORT_BLOOM_POS + Vector3(0.0, 1.8, 0.0), Color(0.96, 0.62, 0.34))
	_seam_material = _make_material(Color(0.22, 0.24, 0.26), Color(0.48, 0.6, 0.72), 0.15)
	var seam_marker := MeshInstance3D.new()
	var seam_mesh := BoxMesh.new()
	seam_mesh.size = Vector3(1.0, 0.6, 7.0)
	seam_marker.mesh = seam_mesh
	seam_marker.material_override = _seam_material
	seam_marker.position = MID_SEAM_POS + Vector3(0.0, 0.35, 0.8)
	add_child(seam_marker)
	_seam_interactable = _add_interactable(
		self,
		"RangeSeamInteractable",
		"Cross Seam",
		MID_SEAM_POS + Vector3(-0.6, 0.0, 0.0),
		"CROSS",
		"endo",
		SEAM_WORK_SECONDS,
		false,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_seam_interactable.interacted.connect(cross_seam)

	_add_box(
		self,
		SHORT_BLOOM_POS + Vector3(0.0, 0.65, 0.0),
		Vector3(0.8, 1.3, 0.8),
		Color(0.28, 0.12, 0.055),
		Color(0.94, 0.34, 0.10),
		0.48,
		"RangeDirectBloomMarker"
	)
	_direct_interactable = _add_interactable(
		self,
		"RangeDirectInteractable",
		"Cut Hot Bloom",
		SHORT_BLOOM_POS,
		"CUT",
		"endo",
		SEAM_WORK_SECONDS,
		false,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_direct_interactable.interacted.connect(cross_seam)

func _build_lure_spindle() -> void:
	_add_label(self, "LURE SPINDLE", LURE_SPINDLE_POS + Vector3(0.0, 2.4, 0.0), Color(0.96, 0.74, 0.38))
	var spindle := MeshInstance3D.new()
	var spindle_mesh := CylinderMesh.new()
	spindle_mesh.top_radius = 0.22
	spindle_mesh.bottom_radius = 0.34
	spindle_mesh.height = 1.8
	spindle.mesh = spindle_mesh
	_spindle_material = _make_material(Color(0.22, 0.18, 0.12), Color(0.86, 0.44, 0.18), 0.22)
	spindle.material_override = _spindle_material
	spindle.position = LURE_SPINDLE_POS + Vector3(0.0, 0.9, 0.0)
	add_child(spindle)
	_lure_interactable = _add_interactable(
		self,
		"RangeLureInteractable",
		"Lure Spindle",
		LURE_SPINDLE_POS + Vector3(-0.8, 0.0, 0.0),
		"BLOOM",
		"peris",
		LURE_WORK_SECONDS,
		false,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_lure_interactable.interacted.connect(activate_range_lure)

func _build_hide_slit() -> void:
	_add_box(self, HIDE_SLIT_POS + Vector3(0.0, -0.05, 0.0), Vector3(6.0, 0.2, 3.0), Color(0.08, 0.1, 0.09))
	_add_box(self, HIDE_SLIT_POS + Vector3(-2.9, 1.3, 0.0), Vector3(0.3, 2.8, 3.0), Color(0.11, 0.13, 0.12))
	_add_box(self, HIDE_SLIT_POS + Vector3(2.9, 1.3, 0.0), Vector3(0.3, 2.8, 3.0), Color(0.11, 0.13, 0.12))
	_add_label(self, "HIDE SLIT", HIDE_SLIT_POS + Vector3(0.0, 2.2, 0.0), Color(0.62, 0.92, 0.72))
	_hide_material = _make_material(Color(0.14, 0.18, 0.16), Color(0.44, 0.8, 0.56), 0.18)
	var hide_marker := MeshInstance3D.new()
	var hide_mesh := BoxMesh.new()
	hide_mesh.size = Vector3(0.6, 1.6, 2.1)
	hide_marker.mesh = hide_mesh
	hide_marker.material_override = _hide_material
	hide_marker.position = HIDE_SLIT_POS + Vector3(0.0, 0.8, 0.0)
	add_child(hide_marker)
	_hide_interactable = _add_interactable(
		self,
		"RangeHideInteractable",
		"Hide Slit",
		HIDE_SLIT_POS + Vector3(-0.7, 0.0, 0.0),
		"HIDE",
		"endo",
		HIDE_WORK_SECONDS,
		false,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_hide_interactable.interacted.connect(commit_hide)

	_add_box(self, RECOVERY_RIG_POS + Vector3(0.0, 0.75, 0.0), Vector3(1.4, 1.5, 0.8),
		Color(0.18, 0.14, 0.10), Color(0.92, 0.42, 0.16), 0.28)
	_add_label(self, "RESET WINCH", RECOVERY_RIG_POS + Vector3(0.0, 2.0, 0.0), Color(0.94, 0.54, 0.28))
	_recovery_interactable = _add_interactable(
		self,
		"RangeRecoveryInteractable",
		"Range Reset Winch",
		RECOVERY_RIG_POS,
		"RESET",
		"",
		RECOVERY_WORK_SECONDS,
		false,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_recovery_interactable.interacted.connect(recover_from_failure)

func _build_east_shelter() -> void:
	# Arriving is only half the loop. The explicit hearth action below requires the
	# full conscious party and debits the real ATP ledger before completion.
	_add_box(self, EAST_SHELTER_POS + Vector3(0.0, -0.03, 0.0), Vector3(7.8, 0.22, 6.2), Color(0.11, 0.1, 0.09))
	_add_box(self, EAST_SHELTER_POS + Vector3(3.9, 1.7, 0.0), Vector3(0.3, 3.4, 6.2), Color(0.14, 0.13, 0.11))
	_add_box(self, EAST_SHELTER_POS + Vector3(0.0, 1.7, -3.0), Vector3(8.0, 3.4, 0.3), Color(0.14, 0.13, 0.11))
	_add_label(self, "NEXT SHELTER", EAST_SHELTER_POS + Vector3(0.0, 2.5, 0.0), Color(0.98, 0.84, 0.56))
	_east_beacon_material = _make_material(Color(0.18, 0.18, 0.16), Color(0.96, 0.82, 0.48), 0.18)
	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.34
	beacon_mesh.height = 0.68
	beacon.mesh = beacon_mesh
	beacon.material_override = _east_beacon_material
	beacon.position = EAST_SHELTER_POS + Vector3(0.0, 1.15, 0.0)
	add_child(beacon)
	_east_shelter_interactable = _add_object_interactable(
		self, "RangeEastShelterInteractable", "East Shelter Hearth", EAST_SHELTER_POS,
		"REST PARTY", [beacon], "", SHELTER_REST_SECONDS, false, SHELTER_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_east_shelter_interactable.interacted.connect(rest_at_east_shelter)
	var gs = _get_game_state()
	if gs != null and gs.has_method("add_shelter_region"):
		gs.add_shelter_region(
			Vector2(EAST_SHELTER_POS.x - 3.0, EAST_SHELTER_POS.z - 2.5),
			Vector2(EAST_SHELTER_POS.x + 3.0, EAST_SHELTER_POS.z + 2.5)
		)

func _build_swarm_markers() -> void:
	for i in range(SWARM_OFFSETS.size()):
		var marker := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.44
		mesh.height = 0.88
		marker.mesh = mesh
		var material := _make_material(Color(0.22, 0.12, 0.08), Color(0.7, 0.24, 0.12), 0.45)
		marker.material_override = material
		marker.position = Vector3(SWARM_START_X, 0.72, SWARM_OFFSETS[i])
		add_child(marker)
		_swarm_markers.append(marker)
		_swarm_materials.append(material)

func _update_range(delta: float) -> void:
	_update_swarm_markers(delta)
	if _route_phase in ["failed", "complete"]:
		return

	if _lure_active:
		_lure_remaining = maxf(0.0, _lure_remaining - delta)
		if _lure_remaining <= 0.0:
			_lure_active = false
			if _hide_phase == "hide":
				_hide_phase = "run"
				_mark_segment("release")
				_route_phase = "run"
				_set_preview_step("survival_range_run")
				_show_message("The sweep breaks away. Run for the shelter light.", 1.8)
			elif _hide_phase != "run" and _seam_crossed and not _shelter_reached:
				_fail_range("late_window")
				return
			_update_visual_state()

	if _hide_phase == "hide":
		if _get_character_position("endo").distance_to(HIDE_SLIT_POS) > INTERACT_RADIUS + 0.8:
			_fail_range("broke_cover")
			return
	# Reaching the east radius never completes the level by itself. The party must
	# assemble and deliberately work the hearth interaction.

func _update_swarm_markers(delta: float) -> void:
	var target_x := SWARM_START_X
	if _hide_phase == "hide":
		target_x = SWARM_HIDE_X
	elif _lure_active:
		target_x = SWARM_LURE_X
	elif _hide_phase == "run":
		target_x = SWARM_HIDE_X - 5.2

	for marker in _swarm_markers:
		if marker == null:
			continue
		marker.position.x = move_toward(marker.position.x, target_x, SWARM_SPEED * delta)

func _crossing_mode() -> String:
	if not _require_station("endo", MID_SEAM_POS, "the refuge seam", false):
		if _require_station("endo", SHORT_BLOOM_POS, "the short bloom", false):
			return "short_bloom"
		return ""
	var endo_pos := _get_character_position("endo")
	return "short_bloom" if endo_pos.distance_to(SHORT_BLOOM_POS) <= INTERACT_RADIUS else "seam"

func _route_timing_profile(profile: String) -> Dictionary:
	match profile:
		"staged_safe":
			return {
				"routing_mode": "safe",
				"scout_required": true,
				"lure_required": true,
				"use_peris_tune": false,
				"cross_target": MID_SEAM_POS,
				"cross_running": false,
				"hide_running": true,
				"shelter_running": true,
			}
		"optimal_safe":
			return {
				"routing_mode": "safe",
				"scout_required": true,
				"lure_required": true,
				"use_peris_tune": true,
				"cross_target": MID_SEAM_POS,
				"cross_running": false,
				"hide_running": true,
				"shelter_running": true,
			}
		"tuned_direct":
			return {
				"routing_mode": "direct",
				"scout_required": true,
				"lure_required": true,
				"use_peris_tune": true,
				"cross_target": SHORT_BLOOM_POS,
				"cross_running": true,
				"hide_running": true,
				"shelter_running": true,
			}
		"greedy_direct":
			return {
				"routing_mode": "direct",
				"scout_required": false,
				"lure_required": false,
				"use_peris_tune": false,
				"cross_target": SHORT_BLOOM_POS,
				"cross_running": true,
				"hide_running": true,
				"shelter_running": true,
			}
		_:
			return {}

func _predict_station_action(
	char_id: String,
	from: Vector3,
	target: Vector3,
	arrival_radius: float,
	running: bool,
	dwell_time: float,
	label: String
) -> Dictionary:
	var end_position := _approach_position(from, target, arrival_radius)
	var speed := maxf(_get_character_move_speed(char_id, running), 0.1)
	var travel_distance := from.distance_to(end_position)
	var travel_time := travel_distance / speed
	return {
		"label": label,
		"character": char_id,
		"running": running,
		"from": from,
		"target": target,
		"end_position": end_position,
		"arrival_radius": arrival_radius,
		"speed": speed,
		"travel_distance": travel_distance,
		"travel_time": travel_time,
		"dwell_time": dwell_time,
		"total_time": travel_time + dwell_time,
	}

func _with_route_metrics(result: Dictionary) -> Dictionary:
	var movement_time := 0.0
	var work_time := 0.0
	var route_distance := 0.0
	var segments: Dictionary = result.get("segments", {})
	for segment_variant in segments.values():
		if not segment_variant is Dictionary:
			continue
		var segment := segment_variant as Dictionary
		movement_time += float(segment.get("travel_time", 0.0))
		work_time += float(segment.get("dwell_time", 0.0))
		route_distance += float(segment.get("travel_distance", 0.0))
	var total_time := float(result.get("total_time", 0.0))
	result["movement_time"] = movement_time
	result["work_time"] = work_time
	result["route_distance"] = route_distance
	# Every second in a successful prediction is either authored traversal or a
	# click-gated work beat. Failure predictions can end mid-action when a lure
	# window closes, so their active measure is clamped to their actual end time.
	result["active_time"] = minf(total_time, movement_time + work_time)
	result["active_share"] = float(result["active_time"]) / maxf(total_time, 0.001)
	return result

func _approach_position(from: Vector3, target: Vector3, arrival_radius: float) -> Vector3:
	var delta := target - from
	var distance := delta.length()
	if distance <= maxf(arrival_radius, 0.0) or distance <= 0.001:
		return from
	var effective_radius := maxf(arrival_radius - ARRIVAL_BUFFER, 0.0)
	return target - delta.normalized() * effective_radius

func _predict_cross_damage(scouted: bool, lure_open: bool, direct_route: bool, short_bloom: bool) -> float:
	var damage := 4.0
	if short_bloom:
		damage += 14.0
	if not scouted:
		damage += 10.0
	if not lure_open:
		damage += 12.0
	if direct_route:
		damage += 6.0
	return damage

func _require_station(required_char: String, position: Vector3, label: String, report := true) -> bool:
	var actor := _get_active_character()
	if actor == "":
		if report:
			_show_message("Pick an active character first.", 1.2)
		return false
	if required_char != "" and actor != required_char:
		if report:
			_show_message("%s has to handle %s." % [required_char.capitalize(), label], 1.4)
		return false
	if _get_character_position(actor).distance_to(position) > INTERACT_RADIUS:
		if report:
			_show_message("Move %s to %s first." % [actor.capitalize(), label], 1.4)
		return false
	return true

func _refresh_interaction_gates() -> void:
	var direct_route := _get_routing_mode() == "direct"
	_set_interactable_enabled(_departure_interactable, _route_phase == "briefing")
	_set_interactable_enabled(_scout_interactable,
		_departed and not _scouted and _route_phase not in ["failed", "complete"])
	_set_interactable_enabled(_echo_interactable,
		_departed and _scouted and not _echo_tuned
		and _route_phase not in ["failed", "complete", "midway", "run"])
	_set_interactable_enabled(_lure_interactable,
		_departed and _scouted and _echo_tuned and not _lure_active
		and _route_phase not in ["failed", "complete", "midway", "run"])
	_set_interactable_enabled(_seam_interactable,
		_departed and not direct_route and _lure_active and not _seam_crossed
		and _route_phase not in ["failed", "complete"])
	_set_interactable_enabled(_direct_interactable,
		_departed and direct_route and not _seam_crossed
		and _route_phase not in ["failed", "complete"])
	_set_interactable_enabled(_hide_interactable,
		_seam_crossed and _route_phase == "midway")
	_set_interactable_enabled(_recovery_interactable, _route_phase == "failed")
	_set_interactable_enabled(_east_shelter_interactable, _route_phase == "run")

func _set_interactable_enabled(interactable, enabled: bool) -> void:
	if interactable == null:
		return
	if interactable.has_method("set_interaction_enabled"):
		interactable.call("set_interaction_enabled", enabled)
	else:
		interactable.set("interaction_enabled", enabled)

func _mark_segment(segment: String) -> void:
	if not _segments_completed.has(segment):
		_segments_completed.append(segment)

func _fail_range(reason: String) -> void:
	if _route_phase in ["failed", "complete"]:
		return
	_route_phase = "failed"
	_hide_phase = "failed"
	_last_outcome = reason
	_set_preview_step("survival_range_failed")
	_show_message("The range collapses: %s." % reason.replace("_", " "), 1.8)
	_refresh_interaction_gates()
	_update_visual_state()

func rest_at_east_shelter() -> bool:
	if _route_phase == "complete":
		return true
	if _route_phase != "run":
		_show_message("The shelter sprint is not open yet.", 1.3)
		return false
	if not _full_conscious_party_at_east_shelter():
		_show_message("Bring Aster, Peris, and Endo into the east shelter conscious.", 1.8)
		return false
	var gs = _get_game_state()
	if gs == null:
		return false
	for char_id in ["aster", "peris", "endo"]:
		if gs.get_stat(char_id, "atp") < SHELTER_ATP_COST:
			_show_message("Everyone needs at least one ATP to survive the night.", 1.6)
			return false
	for char_id in ["aster", "peris", "endo"]:
		gs.adjust_stat(char_id, "atp", -SHELTER_ATP_COST)
		gs.set_stat(char_id, "hp", gs.get_stat_cap(char_id, "hp"))
		gs.set_stat(char_id, "stamina", gs.get_stat_cap(char_id, "stamina"))
		_set_character_status(char_id, "rested")
	_complete_range()
	return true

func _full_conscious_party_at_east_shelter() -> bool:
	var gs = _get_game_state()
	if gs == null:
		return false
	for char_id in ["aster", "peris", "endo"]:
		if not gs.characters.has(char_id) or gs.is_downed(char_id):
			return false
		if _get_character_position(char_id).distance_to(EAST_SHELTER_POS) > SHELTER_RADIUS:
			return false
	return true

func _complete_range() -> void:
	if _route_phase == "complete":
		return
	_shelter_reached = true
	_route_phase = "complete"
	_hide_phase = "safe"
	_last_outcome = "success"
	_mark_segment("shelter")
	_set_preview_step("survival_range_complete")
	_show_message("The next shelter holds. The route is now proven.", 1.9)
	_refresh_interaction_gates()
	_update_visual_state()

func _current_route_instruction() -> String:
	match _route_phase:
		"briefing":
			return "leave the west shelter"
		"departed":
			return "get Aster onto the scout perch"
		"scouted":
			return "let Peris tune the echo coupler"
		"calibrated":
			return "carry Peris's tuned echo to the spindle"
		"window":
			return "move Endo through the seam"
		"midway":
			return "reach the hide slit"
		"hide":
			return "finish the slit concealment read"
		"run":
			return "cash out the shelter sprint"
		"complete":
			return "the route is safe"
		"failed":
			return "reset and try the chain again"
		_:
			return "keep the chain intact"

func _update_visual_state() -> void:
	_set_signal_material(_west_beacon_material, not _departed, Color(0.18, 0.18, 0.16), Color(0.94, 0.8, 0.48), 0.9)
	_set_signal_material(_east_beacon_material, _route_phase == "run" or _route_phase == "complete", Color(0.18, 0.18, 0.16), Color(0.98, 0.86, 0.56), 1.0 if _route_phase == "complete" else 0.45)
	_set_signal_material(_spindle_material, _lure_active, Color(0.22, 0.18, 0.12), Color(0.88, 0.46, 0.18), 1.25)
	_set_signal_material(_echo_material, _echo_tuned, Color(0.15, 0.19, 0.21), Color(0.42, 0.76, 0.92), 0.95)
	_set_signal_material(_seam_material, _scouted, Color(0.22, 0.24, 0.26), Color(0.48, 0.68, 0.86), 0.7)
	_set_signal_material(_hide_material, _hide_phase in ["hide", "run", "safe"], Color(0.14, 0.18, 0.16), Color(0.42, 0.84, 0.58), 0.85)

	for material in _swarm_materials:
		if material == null:
			continue
		material.emission_energy_multiplier = 0.85 if _lure_active or _hide_phase == "hide" else 0.42

func _set_signal_material(
	material: StandardMaterial3D,
	active: bool,
	inactive_color: Color,
	emission_color: Color,
	active_energy: float
) -> void:
	if material == null:
		return
	material.albedo_color = emission_color if active else inactive_color
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = active_energy if active else 0.18
