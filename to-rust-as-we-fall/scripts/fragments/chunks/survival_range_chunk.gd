extends "res://scripts/scene_chunks/scene_chunk.gd"

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")
const EnemyScript := preload("res://scripts/game/ai/enemy.gd")
const HazardFieldScript := preload("res://scripts/game/objects/hazard_field.gd")
const CapbageScript := preload("res://scripts/game/objects/capbage.gd")

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
const LURE_DURATION := 47.0
const WINCH_PULL_DURATION := 12.0
const SAFE_CROSS_DURATION := 4.0
const DIRECT_CROSS_DURATION := 2.0
const INTERACT_RADIUS := 2.4
const HIDE_CONCEAL_RADIUS := 1.45
const SHELTER_RADIUS := 2.6
const SHELTER_ATP_COST := 1.0
const SHELTER_REST_SECONDS := 4.0
const ARRIVAL_BUFFER := 0.1
const SWARM_SPEED := 4.2
const SWARM_START_X := 270.0
const SWARM_LURE_X := 229.0
const SWARM_LURE_Z := 9.2
const SWARM_UNTUNED_X := 246.0
const SWARM_UNTUNED_Z := 0.0
const SWARM_CLEAR_X := 238.0
const SWARM_CLEAR_Z := 6.4
const SWARM_DETECTION_RANGE := 10.5
const SWARM_OFFSETS := [-1.8, 0.0, 1.8]
const DIRECT_BLOOM_MIN := Vector2(136.0, 1.6)
const DIRECT_BLOOM_MAX := Vector2(142.5, 5.7)
const DIRECT_BLOOM_DAMAGE := 6.0
const DIRECT_BLOOM_INTERVAL := 1.0
const SAFE_CROSS_END_POS := Vector3(143.5, 0.5, -1.8)
const DIRECT_CROSS_END_POS := Vector3(143.2, 0.5, 3.6)

const PARTY_IDS := ["aster", "peris", "endo"]
const RANGE_AUTHORITY_VERSION := 4
const RANGE_AUTHORITY_PREFIX := "runtime:survival_range:"
const LURE_EXPIRY_TAG_PREFIX := "survival_range_lure_expiry:"
const SHELTER_REST_TAG_PREFIX := "survival_range_party_rest:"
const WINCH_TRAVERSAL_PREFIX := "survival_range_reset_winch:"
const CROSS_TRAVERSAL_PREFIX := "survival_range_seam_crossing:"
const WINCH_RETURN_POS := MID_SEAM_POS + Vector3(-INTERACT_RADIUS + 0.25, 0.05, 0.0)
const VALID_ROUTE_PHASES := [
	"briefing", "departed", "scouted", "calibrated", "window", "crossing", "midway",
	"hide", "run", "failed", "resetting", "complete",
]
const VALID_HIDE_PHASES := ["ready", "hide", "run", "failed", "resetting", "safe"]
const VALID_CROSS_MODES := ["", "seam", "short_bloom"]
const LURE_ROUTE_NONE := ""
const LURE_ROUTE_LANE := "lane"
const LURE_ROUTE_RECESS := "recess"
const VALID_LURE_ROUTES := [LURE_ROUTE_NONE, LURE_ROUTE_LANE, LURE_ROUTE_RECESS]
const SHELTER_REST_PHASES := ["ready", "committing", "rested"]

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
var _echo_lane_indicator_material: StandardMaterial3D
var _echo_recess_indicator_material: StandardMaterial3D
var _seam_material: StandardMaterial3D
var _hide_material: StandardMaterial3D
var _direct_bloom_material: StandardMaterial3D
var _winch_material: StandardMaterial3D
var _winch_source_mesh: MeshInstance3D
var _winch_anchor_mesh: MeshInstance3D
var _echo_direction_arm: MeshInstance3D
var _echo_lane_receiver: MeshInstance3D
var _echo_recess_receiver: MeshInstance3D
var _echo_route_link: Node3D
var _swarm_enemies: Array = []
var _direct_bloom_field
var _hide_capbage

var _departed := false
var _route_phase := "briefing"
var _last_outcome := ""
var _segments_completed: Array[String] = []
var _scouted := false
var _echo_tuned := false
var _lure_active := false
var _lure_remaining := 0.0
var _lure_deadline := -1.0
var _lure_route_mode := LURE_ROUTE_NONE
var _seam_crossed := false
var _cross_mode := ""
var _cross_start_hp := 0.0
var _hide_phase := "ready"
var _mid_seam_damage := 0.0
var _shelter_reached := false
var _shelter_rest_phase := "ready"
var _shelter_rest_commit_tick := -1.0
var _shelter_rest_commit_day := 0
var _shelter_rest_before_atp: Dictionary = {}
var _reset_count := 0
var _decoration_audit := {}
var _range_authority_initialized := false
var _restoring_range_authority := false
var _range_authority_baseline: Dictionary = {}
var _range_signal_game_state = null

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
	_build_range_systems()
	_decoration_audit = LevelDecoratorScript.decorate_corridor(self, DECORATION_PROFILE)
	reset_preview_state()
	_initialize_range_authority()
	_connect_range_game_state_signals()

func _process(delta: float) -> void:
	_update_range(delta)

func headless_process(delta: float) -> void:
	_update_range(delta)

func get_scene_title() -> String:
	return "Shelter-To-Shelter Range"

func get_scene_help() -> String:
	return "Leave the west shelter. Aster reveals the unchanged rust-bloom cadence. Peris can fire the spindle immediately, but the coupler visibly chooses whether the real sweep stops in the release lane or diverts into the side recess. Endo then chooses the long clean seam or short live field before using the Capbage slit. Bring the full conscious party to the east shelter and spend one ATP each to complete the rest."

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
		"echo_lane_endpoint": Vector3(SWARM_UNTUNED_X, 0.5, SWARM_UNTUNED_Z),
		"echo_recess_endpoint": Vector3(SWARM_LURE_X, 0.5, SWARM_LURE_Z),
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
		# Begin just after nightfall. The authored 3-5 minute range then reaches the east hearth
		# before dawn, so GameState.command_rest sees the same paid-night commitment the level teaches.
		"time": 0.52,
		"routing_mode": "safe",
		"note_default": "The world is literal here: scan reveals but never reduces the pulse, the direct bloom damages only bodies inside it, the sweep is made of real enemies, and the slit conceals only bodies actually inside its Capbage.",
	}

func get_preview_state() -> Dictionary:
	_refresh_lure_readback()
	var winch_state := _winch_traversal_state()
	return {
		"departed": _departed,
		"route_phase": _route_phase,
		"last_outcome": _last_outcome,
		"segments_completed": _segments_completed.duplicate(),
		"scouted": _scouted,
		"echo_tuned": _echo_tuned,
		"lure_route_mode": _lure_route_mode,
		"lure_endpoint": _swarm_lure_endpoint(1) if _lure_route_mode != LURE_ROUTE_NONE else Vector3.ZERO,
		"lure_active": _lure_active,
		"lure_remaining": _lure_remaining,
		"lure_deadline": _lure_deadline,
		"seam_crossed": _seam_crossed,
		"cross_mode": _cross_mode,
		"cross_in_progress": _route_phase == "crossing" and not _cross_traversal_state().is_empty(),
		"cross_progress": float(_cross_traversal_state().get("progress", 0.0)),
		"cross_remaining": float(_cross_traversal_state().get("remaining", 0.0)),
		"hide_phase": _hide_phase,
		"endo_concealment": _endo_concealment(),
		"swarm_clear": _swarm_clear_of_release_lane(),
		"swarm": _swarm_report(),
		"direct_hazard": _direct_bloom_field.get_state() if _direct_bloom_field != null else {},
		"scout_readout": _scout_readout(),
		"mid_seam_damage": _mid_seam_damage,
		"shelter_reached": _shelter_reached,
		"shelter_rested": _shelter_reached,
		"shelter_rest_phase": _shelter_rest_phase,
		"complete": _route_phase == "complete",
		"reset_count": _reset_count,
		"winch_in_progress": _route_phase == "resetting" and not winch_state.is_empty(),
		"winch_progress": float(winch_state.get("progress", 0.0)),
		"winch_remaining": float(winch_state.get("remaining", 0.0)),
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
		"hazard_crossing": _segment_active_seconds(segments, "cross") \
			+ _segment_active_seconds(segments, "cross_traversal") \
			+ _segment_active_seconds(segments, "hide"),
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
		"decision_count": 1,
		"branch_count": 3,
		"decisions": ["safe seam or hot bloom"],
		"branches": ["scouted safe", "direct", "failed window into reset"],
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
	var pre_window_total := total_time

	var cross_mode := "short_bloom" if cross_target.distance_to(SHORT_BLOOM_POS) <= 0.01 else "seam"
	var traversal_duration := DIRECT_CROSS_DURATION if cross_mode == "short_bloom" else SAFE_CROSS_DURATION
	var traversal_end := DIRECT_CROSS_END_POS if cross_mode == "short_bloom" else SAFE_CROSS_END_POS
	var seam_end: Vector3 = seam["end_position"]
	var cross_traversal := {
		"label": "cross_traversal",
		"character": "endo",
		"running": false,
		"from": seam_end,
		"target": traversal_end,
		"end_position": traversal_end,
		"arrival_radius": 0.0,
		"speed": seam_end.distance_to(traversal_end) / maxf(traversal_duration, 0.001),
		"travel_distance": seam_end.distance_to(traversal_end),
		"travel_time": traversal_duration,
		"dwell_time": 0.0,
		"total_time": traversal_duration,
		"external_traversal": true,
	}
	segments["cross_traversal"] = cross_traversal
	positions["endo"] = traversal_end
	var predicted_damage := _predict_cross_damage(cross_mode == "short_bloom")

	var hide: Dictionary = _predict_station_action(
		"endo",
		positions["endo"],
		HIDE_SLIT_POS,
		HIDE_CONCEAL_RADIUS,
		hide_running,
		HIDE_WORK_SECONDS,
		"hide"
	)
	segments["hide"] = hide
	positions["endo"] = hide["end_position"]

	if not lure_required:
		total_time += float(seam.get("total_time", 0.0))
		total_time += traversal_duration
		total_time += float(hide.get("total_time", 0.0))
		return _with_route_metrics({
			"profile": profile,
			"routing_mode": routing_mode,
			"success": false,
			"outcome": "swarm_still_blocks_release",
			"cross_mode": cross_mode,
			"predicted_damage": predicted_damage,
			"predicted_endo_hp": maxf(0.0, 100.0 - predicted_damage),
			"total_time": total_time,
			"segments": segments,
		})

	var active_window := LURE_DURATION
	var window_elapsed := float(seam.get("total_time", 0.0)) + traversal_duration \
		+ float(hide.get("total_time", 0.0))
	var window_margin := active_window - window_elapsed

	if window_margin < 0.0:
		return _with_route_metrics({
			"profile": profile,
			"routing_mode": routing_mode,
			"success": false,
			"outcome": "late_window",
			"cross_mode": cross_mode,
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
	total_time += traversal_duration
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
			var scan := _scout_readout()
			return [
				"DATA: scan reveals a fixed spatial pulse; it never weakens the field.",
				"Survey: %s" % ("resolved" if _scouted else "blind"),
				"Bloom pulse: %s" % ("%.1fs / %.0f HP" % [float(scan.get("next_bloom_pulse_in", -1.0)), float(scan.get("damage_per_pulse", 0.0))] if _scouted else "not yet measured"),
				"Route: %s" % ("safe seam" if _get_routing_mode() == "safe" else "direct bloom"),
			]
		"peris":
			return [
				"FOG: the coupler physically selects where the spindle's echo terminates.",
				"Echo: %s" % ("SIDE RECESS" if _echo_tuned else "RELEASE LANE"),
				"Lure: %s" % ("%s route open %.1fs" % [_lure_route_mode.to_upper(), _lure_remaining] if _lure_active else "cold"),
				"Sweep: %s" % ("physically clear of release lane" if _swarm_clear_of_release_lane() else "still blocks release lane"),
			]
		"endo":
			return [
				"SURVIVAL: cross a real field, enter full cover, release only after the bodies clear.",
				"Margin: HP %.0f / ATP %.0f" % [_get_character_stat("endo", "hp"), _get_character_stat("endo", "atp")],
				"Next: %s" % _current_route_instruction(),
			]
		_:
			return []

func reset_preview_state() -> void:
	_cancel_range_callbacks()
	_departed = false
	_route_phase = "briefing"
	_last_outcome = ""
	_segments_completed.clear()
	_scouted = false
	_echo_tuned = false
	_lure_active = false
	_lure_remaining = 0.0
	_lure_deadline = -1.0
	_lure_route_mode = LURE_ROUTE_NONE
	_seam_crossed = false
	_cross_mode = ""
	_cross_start_hp = 0.0
	_hide_phase = "ready"
	_mid_seam_damage = 0.0
	_shelter_reached = false
	_shelter_rest_phase = "ready"
	_clear_range_shelter_rest_context()
	_reset_count = 0
	_set_preview_step("survival_range_briefing")

	for interactable in [_departure_interactable, _scout_interactable, _echo_interactable, _lure_interactable, _seam_interactable, _direct_interactable, _hide_interactable, _recovery_interactable, _east_shelter_interactable]:
		if interactable != null and interactable.has_method("reset"):
			interactable.reset()

	var gs = _get_game_state()
	if gs != null and gs.has_method("cancel_external_traversal") \
			and gs.has_method("is_external_traversal_active") \
			and gs.is_external_traversal_active("endo"):
		gs.cancel_external_traversal("endo", &"range_reset")
	_reset_swarm_to_posts()
	if _direct_bloom_field != null:
		_direct_bloom_field.set_active(true)
	_update_range_concealment()

	_refresh_interaction_gates()
	_update_visual_state()
	if _range_authority_initialized:
		_publish_range_authority()

func on_preview_routing_changed(mode: String) -> void:
	if mode == "direct":
		_show_note("Direct routing crosses the orange field for two seconds. Its fixed pulse can bite only while Endo is inside.", 2.7)
	else:
		_show_note("Safe routing takes the four-second unburned seam. Aster's scan shows the difference; it does not create it.", 2.7)
	_refresh_interaction_gates()

func depart_range(source: Node = null) -> bool:
	if not _range_control_receipt_pending(source, "depart"):
		return false
	if _route_phase in ["failed", "resetting", "complete"]:
		return false
	_departed = true
	_mark_segment("departed")
	_route_phase = "departed"
	_set_preview_step("survival_range_departed")
	_show_message("The team leaves shelter. Scout first, then open the window.", 2.0)
	_refresh_interaction_gates()
	_update_visual_state()
	_publish_range_authority()
	return true

func survey_route(source: Node = null) -> bool:
	if not _range_control_receipt_pending(source, "scout"):
		return false
	if _route_phase in ["failed", "resetting", "complete"]:
		return false
	if not _departed:
		_show_message("Take the shelter briefing before marking the live range.", 1.4)
		return false
	_scouted = true
	_mark_segment("scouted")
	if _route_phase in ["briefing", "departed"]:
		_route_phase = "scouted"
	_set_preview_step("survival_range_scouted")
	_show_message("Aster exposes the fixed bloom cadence and marks the unburned seam. The field itself does not weaken.", 2.2)
	_refresh_interaction_gates()
	_update_visual_state()
	_publish_range_authority()
	return true

func activate_range_lure(source: Node = null) -> bool:
	if not _range_control_receipt_pending(source, "lure"):
		return false
	if _route_phase in ["failed", "resetting", "complete", "crossing", "midway", "run"]:
		return false
	if not _departed:
		_show_message("The range has not left shelter control yet.", 1.4)
		return false
	if not _scouted:
		_show_message("Aster has to resolve the course before the lure can use either route.", 1.5)
		return false
	for enemy in _swarm_enemies:
		if enemy == null or not is_instance_valid(enemy) or not enemy.has_method("get_lure_availability") \
				or str(enemy.get_lure_availability()) != "available":
			_show_message("One of the sweep bodies has already committed to a target. Break contact before singing again.", 2.0)
			_rearm_range_control(source)
			return false
	# The coupler is a physical route selector, not a prerequisite checkbox. Firing
	# untuned is allowed and teaches the causal model by parking the real sweep in
	# the visibly marked release lane; tuning redirects the same bodies to recess.
	_lure_route_mode = LURE_ROUTE_RECESS if _echo_tuned else LURE_ROUTE_LANE
	for i in range(_swarm_enemies.size()):
		var enemy = _swarm_enemies[i]
		var settle := _swarm_lure_endpoint(i)
		if not bool(enemy.lure_to(settle, LURE_DURATION)):
			_lure_route_mode = LURE_ROUTE_NONE
			_rearm_range_control(source)
			return false
	_lure_active = true
	_lure_remaining = LURE_DURATION
	_lure_deadline = _get_scheduler_tick() + LURE_DURATION
	_arm_lure_expiry(_lure_deadline)
	_mark_segment("lure")
	_route_phase = "window"
	_set_preview_step("survival_range_window")
	if _lure_route_mode == LURE_ROUTE_RECESS:
		_show_message("The tuned spindle pulls the real sweep toward the marked side recess. Watch the release lane clear.", 2.2)
	else:
		_show_message("The untuned spindle answers from the marked release lane. The sweep moves, but still blocks Endo's exit.", 2.3)
	_refresh_interaction_gates()
	_update_visual_state()
	_publish_range_authority()
	return true

func tune_echo_coupler(source: Node = null) -> bool:
	if not _range_control_receipt_pending(source, "echo"):
		return false
	if _route_phase in ["failed", "resetting", "complete", "window", "crossing", "midway", "run"] \
			or _lure_active:
		return false
	if not _departed or not _scouted:
		_show_message("Aster has to resolve the course before Peris can tune its echo return.", 1.5)
		return false
	_echo_tuned = true
	_mark_segment("echo")
	_route_phase = "calibrated"
	_set_preview_step("survival_range_echo_tuned")
	_show_message("Peris rotates the coupler off the release lane and locks its pointer onto the side recess.", 2.1)
	_refresh_interaction_gates()
	_update_visual_state()
	_publish_range_authority()
	return true

func cross_seam(source: Node = null) -> bool:
	var receipt_action := "seam" if source == _seam_interactable else "direct"
	if not _range_control_receipt_pending(source, receipt_action):
		return false
	if _route_phase in ["failed", "resetting", "complete"]:
		return false
	if not _departed:
		_show_message("Leave the west shelter before entering the live lane.", 1.4)
		return false
	var cross_mode := "seam" if source == _seam_interactable else "short_bloom"
	if cross_mode == "":
		_show_message("Move Endo to the refuge seam or the short bloom first.", 1.4)
		return false
	var gs = _get_game_state()
	if gs == null or not gs.characters.has("endo") or gs.is_downed("endo") \
			or gs.is_external_traversal_active("endo"):
		return false
	var destination := DIRECT_CROSS_END_POS if cross_mode == "short_bloom" else SAFE_CROSS_END_POS
	var duration := DIRECT_CROSS_DURATION if cross_mode == "short_bloom" else SAFE_CROSS_DURATION
	var render_destination := destination
	if gs.coord_map != null and gs.coord_map.has_method("to_world"):
		render_destination = gs.coord_map.to_world(destination)
	_cross_mode = cross_mode
	_cross_start_hp = gs.get_stat("endo", "hp")
	_mid_seam_damage = 0.0
	if not gs.command_external_traversal(
			"endo", _cross_traversal_id(cross_mode), destination,
			gs.get_render_position("endo"), render_destination, duration, &"locked"):
		_cross_mode = ""
		_cross_start_hp = 0.0
		_rearm_range_control(source)
		return false
	_route_phase = "crossing"
	_set_preview_step("survival_range_crossing")
	_show_message(
		"Endo commits to the %s. Damage now comes only from the space his body crosses." % [
			"short rust bloom" if cross_mode == "short_bloom" else "long unburned seam"],
		2.0
	)
	_refresh_interaction_gates()
	_update_visual_state()
	_publish_range_authority()
	return true

func commit_hide(source: Node = null) -> bool:
	if not _range_control_receipt_pending(source, "hide"):
		return false
	if _route_phase in ["failed", "resetting", "complete"]:
		return false
	if not _seam_crossed:
		_show_message("The slit only matters after Endo crosses the seam.", 1.4)
		return false
	_update_range_concealment()
	var gs = _get_game_state()
	if gs == null or _endo_concealment() < GameState.CONCEAL_FULL:
		_fail_range("hide_slit_not_entered")
		return false
	if _swarm_has_endo_target():
		_fail_range("cover_entered_after_acquisition")
		return false
	if not _swarm_clear_of_release_lane():
		_fail_range(
			"untuned_echo_blocks_release"
			if _lure_route_mode == LURE_ROUTE_LANE
			else "swarm_still_blocks_release")
		return false
	# The click-gated work ends only while Endo is physically inside the Capbage and
	# every real sweep body is outside the release lane. The state flag records that
	# proven world condition; it never substitutes for it.
	_hide_phase = "run"
	_mark_segment("hide")
	_mark_segment("release")
	_route_phase = "run"
	_set_preview_step("survival_range_run")
	_show_message("The sweep is visibly off-lane and Endo is fully concealed. Run for the east shelter.", 1.8)
	_refresh_interaction_gates()
	_update_visual_state()
	_publish_range_authority()
	return true

func reset_after_failure(source: Node = null) -> bool:
	if not _range_control_receipt_pending(source, "recovery"):
		return false
	if _route_phase != "failed":
		return false
	var gs = _get_game_state()
	if gs == null or not gs.characters.has("endo"):
		return false
	if gs.is_downed("endo"):
		_show_message("Endo is unconscious. The winch can move him, but only shelter rest can revive him.", 2.2)
		return false
	if gs.is_external_traversal_active("endo"):
		_show_message("Endo is already committed to another traversal.", 1.4)
		return false
	var render_destination := WINCH_RETURN_POS
	if gs.coord_map != null and gs.coord_map.has_method("to_world"):
		render_destination = gs.coord_map.to_world(WINCH_RETURN_POS)
	var traversal_id := _winch_traversal_id()
	if not gs.command_external_traversal(
			"endo",
			traversal_id,
			WINCH_RETURN_POS,
			gs.get_render_position("endo"),
			render_destination,
			WINCH_PULL_DURATION,
			&"locked"
		):
		_rearm_range_control(source)
		return false
	_cancel_lure_expiry()
	_lure_active = false
	_lure_remaining = 0.0
	_lure_deadline = -1.0
	_lure_route_mode = LURE_ROUTE_NONE
	_seam_crossed = false
	_hide_phase = "resetting"
	_mid_seam_damage = 0.0
	_last_outcome = "winch_in_progress"
	_route_phase = "resetting"
	_set_preview_step("survival_range_resetting")
	_show_message("The winch locks onto Endo and starts pulling him back along the recovery rail.", 2.2)
	_refresh_interaction_gates()
	_update_visual_state()
	_set_causal_feedback_mode(_recovery_interactable, "active")
	_set_causal_feedback_latched(_recovery_interactable, true)
	_flash_causal_feedback(_recovery_interactable, 1.8, 1.4)
	_publish_range_authority()
	return true


func _on_winch_traversal_finished(char_id: String, traversal_id: StringName) -> void:
	if char_id != "endo" or traversal_id != _winch_traversal_id() or _route_phase != "resetting":
		return
	_reset_count += 1
	_hide_phase = "ready"
	_last_outcome = "reset"
	_route_phase = _resolved_setup_phase()
	_mark_segment("reset")
	_reset_swarm_to_posts()
	for interactable in [_lure_interactable, _seam_interactable, _direct_interactable, _hide_interactable]:
		if interactable != null and interactable.has_method("reset"):
			interactable.reset()
	_set_preview_step("survival_range_reset")
	_show_message("Endo reaches the seam. The winch grants no recovery or refund; ordinary time effects continue.", 2.2)
	_refresh_interaction_gates()
	_update_visual_state()
	_set_causal_feedback_latched(_recovery_interactable, false)
	_set_causal_feedback_mode(_recovery_interactable, "complete")
	_publish_range_authority()


func _on_cross_traversal_finished(char_id: String, traversal_id: StringName) -> void:
	if char_id != "endo" or _route_phase != "crossing" or _cross_mode == "" \
			or traversal_id != _cross_traversal_id(_cross_mode):
		return
	var gs = _get_game_state()
	_mid_seam_damage = maxf(0.0, _cross_start_hp - gs.get_stat("endo", "hp")) if gs != null else 0.0
	_seam_crossed = true
	_mark_segment("seam")
	_route_phase = "midway"
	_set_preview_step("survival_range_midway")
	_show_message(
		"Endo reaches the far edge. The %s cost %.0f HP from real field/enemy contact." % [
			"short bloom" if _cross_mode == "short_bloom" else "refuge seam", _mid_seam_damage],
		1.9
	)
	if gs != null and gs.is_downed("endo"):
		_fail_range("bloomed_out")
		return
	_refresh_interaction_gates()
	_update_visual_state()
	_publish_range_authority()


func _resolved_setup_phase() -> String:
	if not _departed:
		return "briefing"
	if _echo_tuned:
		return "calibrated"
	if _scouted:
		return "scouted"
	return "departed"

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
		true,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_configure_range_control(_departure_interactable, "depart", depart_range)

func _build_scout_perch() -> void:
	_add_box(self, SCOUT_PERCH_POS + Vector3(0.0, -0.04, 0.0), Vector3(5.0, 0.22, 4.2), Color(0.11, 0.13, 0.15))
	_add_box(self, SCOUT_PERCH_POS + Vector3(2.2, 1.3, 0.0), Vector3(0.3, 2.4, 4.2), Color(0.16, 0.18, 0.22))
	_add_label(self, "ROUTE SCAN", SCOUT_PERCH_POS + Vector3(0.0, 2.2, 0.0), Color(0.62, 0.8, 0.96))
	_scout_interactable = _add_interactable(
		self,
		"RangeScoutInteractable",
		"Route Survey Array",
		SCOUT_PERCH_POS + Vector3(-0.6, 0.0, 0.0),
		"SCAN ROUTE",
		"aster",
		SCOUT_WORK_SECONDS,
		true,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_scout_interactable.set("consequence_preview", "reveals the fixed rust-bloom footprint and its next scheduler pulse; does not reduce damage")
	_configure_range_control(_scout_interactable, "scout", survey_route)

func _build_echo_coupler() -> void:
	# This is a physical two-detent router, not a permission switch. Its arm,
	# endpoint lamps, and hover path all persistently agree about where the next
	# spindle call will park the real sweep bodies.
	_add_box(self, ECHO_COUPLER_POS + Vector3(0.0, -0.04, 0.0), Vector3(5.4, 0.2, 4.2), Color(0.10, 0.12, 0.14))
	_add_box(self, ECHO_COUPLER_POS + Vector3(0.0, 0.65, 1.65), Vector3(4.8, 1.3, 0.28), Color(0.14, 0.17, 0.19))
	_add_label(self, "ECHO ROUTER", ECHO_COUPLER_POS + Vector3(0.0, 2.55, 0.0), Color(0.64, 0.82, 0.92))
	_add_label(self, "LANE", ECHO_COUPLER_POS + Vector3(-1.55, 1.75, 0.0), Color(0.98, 0.48, 0.20))
	_add_label(self, "RECESS", ECHO_COUPLER_POS + Vector3(1.55, 1.75, 0.0), Color(0.42, 0.82, 0.96))
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

	_echo_direction_arm = _add_box(
		self,
		ECHO_COUPLER_POS + Vector3(0.0, 1.16, 0.0),
		Vector3(2.6, 0.15, 0.26),
		Color(0.12, 0.17, 0.19),
		Color(0.42, 0.76, 0.92),
		0.45,
		"RangeEchoDirectionArm")
	# Paired detent lamps make the selector legible even when the player is too
	# far away for the hover chevrons.
	var lane_indicator := _add_box(
		self,
		ECHO_COUPLER_POS + Vector3(-1.45, 1.06, -0.9),
		Vector3(0.42, 0.30, 0.42),
		Color(0.22, 0.12, 0.07),
		Color(1.0, 0.42, 0.14),
		0.8,
		"RangeEchoLaneIndicator")
	_echo_lane_indicator_material = lane_indicator.material_override as StandardMaterial3D
	var recess_indicator := _add_box(
		self,
		ECHO_COUPLER_POS + Vector3(1.45, 1.06, -0.9),
		Vector3(0.42, 0.30, 0.42),
		Color(0.07, 0.15, 0.18),
		Color(0.36, 0.82, 0.98),
		0.18,
		"RangeEchoRecessIndicator")
	_echo_recess_indicator_material = recess_indicator.material_override as StandardMaterial3D

	_echo_lane_receiver = _add_box(
		self,
		Vector3(SWARM_UNTUNED_X, 0.08, SWARM_UNTUNED_Z),
		Vector3(5.8, 0.14, 4.8),
		Color(0.20, 0.09, 0.045),
		Color(1.0, 0.36, 0.10),
		0.62,
		"RangeEchoLaneReceiver")
	_add_label(
		self,
		"RELEASE LANE // BLOCKED",
		Vector3(SWARM_UNTUNED_X, 1.6, SWARM_UNTUNED_Z),
		Color(1.0, 0.48, 0.20))
	_echo_recess_receiver = _add_box(
		self,
		Vector3(SWARM_LURE_X, 0.08, SWARM_LURE_Z),
		Vector3(5.8, 0.14, 4.2),
		Color(0.055, 0.14, 0.16),
		Color(0.34, 0.84, 0.98),
		0.48,
		"RangeEchoRecessReceiver")
	_add_label(
		self,
		"SIDE RECESS // CLEAR",
		Vector3(SWARM_LURE_X, 1.6, SWARM_LURE_Z),
		Color(0.42, 0.86, 0.98))

	_echo_interactable = _add_interactable(
		self,
		"RangeEchoInteractable",
		"Echo Coupler",
		ECHO_COUPLER_POS + Vector3(-0.7, 0.0, 0.0),
		"ROUTE TO RECESS",
		"peris",
		ECHO_WORK_SECONDS,
		true,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_echo_interactable.set(
		"consequence_preview",
		"rotates the spindle echo from the marked release-lane stop into the side recess")
	_configure_range_control(_echo_interactable, "echo", tune_echo_coupler)
	_echo_route_link = _add_causal_feedback_link(
		_echo_direction_arm,
		_echo_lane_receiver,
		Color(1.0, 0.67, 0.27),
		{
			"name": "RangeEchoSelectedRoute",
			"interaction_source": _echo_interactable,
			"owner_character": "peris",
			"visibility_policy": "hover_only",
			"show_label": false,
			"path_style": "movement_chevrons",
			"flow_speed": 1.15,
			"draw_duration": 0.55,
			"dash_count": 18,
			"source_offset": Vector3(0.0, 0.1, 0.0),
			"target_offset": Vector3(0.0, 0.12, 0.0),
			"arc_height": 0.7,
		})

func _build_mid_seam() -> void:
	_add_label(self, "REFUGE SEAM", MID_SEAM_POS + Vector3(0.0, 2.2, 0.0), Color(0.78, 0.88, 0.94))
	_add_box(self, MID_SEAM_POS + Vector3(0.0, -0.03, 0.0), Vector3(7.0, 0.12, 2.0), Color(0.16, 0.17, 0.19))
	var bloom_center := Vector3(
		(DIRECT_BLOOM_MIN.x + DIRECT_BLOOM_MAX.x) * 0.5,
		0.06,
		(DIRECT_BLOOM_MIN.y + DIRECT_BLOOM_MAX.y) * 0.5
	)
	var bloom_visual := _add_box(self, bloom_center,
		Vector3(DIRECT_BLOOM_MAX.x - DIRECT_BLOOM_MIN.x, 0.12,
			DIRECT_BLOOM_MAX.y - DIRECT_BLOOM_MIN.y),
		Color(0.22, 0.12, 0.08), Color(0.92, 0.26, 0.08), 0.5,
		"RangeDirectBloomFieldVisual")
	_direct_bloom_material = bloom_visual.material_override as StandardMaterial3D
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
		true,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_configure_range_control(_seam_interactable, "seam", cross_seam)

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
		true,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_configure_range_control(_direct_interactable, "direct", cross_seam)

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
		"OPEN LURE",
		"peris",
		LURE_WORK_SECONDS,
		true,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_lure_interactable.set(
		"consequence_preview",
		"broadcasts for 47 seconds; sweep bodies stop at whichever endpoint the echo arm visibly selects")
	_configure_range_control(_lure_interactable, "lure", activate_range_lure)

func _build_hide_slit() -> void:
	_add_box(self, HIDE_SLIT_POS + Vector3(0.0, -0.05, 0.0), Vector3(6.0, 0.2, 3.0), Color(0.08, 0.1, 0.09))
	_add_box(self, HIDE_SLIT_POS + Vector3(-2.9, 1.3, 0.0), Vector3(0.3, 2.8, 3.0), Color(0.11, 0.13, 0.12))
	_add_box(self, HIDE_SLIT_POS + Vector3(2.9, 1.3, 0.0), Vector3(0.3, 2.8, 3.0), Color(0.11, 0.13, 0.12))
	_add_label(self, "HIDE SLIT", HIDE_SLIT_POS + Vector3(0.0, 2.2, 0.0), Color(0.62, 0.92, 0.72))
	_hide_material = _make_material(Color(0.14, 0.18, 0.16), Color(0.44, 0.8, 0.56), 0.18)
	var conceal_halo := _add_box(self, HIDE_SLIT_POS + Vector3(0.0, -0.35, 0.0),
		Vector3(2.8, 0.05, 2.8), Color(0.14, 0.18, 0.16), Color(0.44, 0.8, 0.56), 0.18,
		"RangeCapbageConcealmentFootprint")
	conceal_halo.material_override = _hide_material
	_hide_capbage = CapbageScript.new()
	_hide_capbage.name = "RangeHideInteractable"
	_hide_capbage.configure(_get_game_state(), HIDE_SLIT_POS, HIDE_CONCEAL_RADIUS)
	_hide_capbage.required_character = "endo"
	_hide_capbage.dwell_time = HIDE_WORK_SECONDS
	_hide_capbage.one_shot = true
	_hide_capbage.interactable_type = Interactable.InteractableType.TIMED_ACTION
	_hide_capbage.description = "Hold inside the Capbage until the sweep visibly clears the release lane"
	_hide_capbage.tutorial_label = "HIDE"
	add_child(_hide_capbage)
	_register_interactable(_hide_capbage)
	_hide_interactable = _hide_capbage
	_hide_interactable.set("consequence_preview", "full concealment blocks acquisition, but release is safe only after the real sweep bodies leave the east lane")
	_configure_range_control(_hide_interactable, "hide", commit_hide)

	var cable_midpoint := (RECOVERY_RIG_POS + WINCH_RETURN_POS) * 0.5 + Vector3(0.0, 2.75, 0.0)
	_add_box(self, cable_midpoint,
		Vector3(absf(RECOVERY_RIG_POS.x - WINCH_RETURN_POS.x), 0.08, 0.10),
		Color(0.055, 0.05, 0.045), Color(0.16, 0.12, 0.08), 0.08,
		"RangeRecoveryCable")
	_winch_source_mesh = _add_box(self, RECOVERY_RIG_POS + Vector3(0.0, 0.75, 0.0),
		Vector3(1.4, 1.5, 0.8), Color(0.18, 0.14, 0.10),
		Color(0.92, 0.42, 0.16), 0.28, "RangeRecoveryWinch")
	_winch_material = _winch_source_mesh.material_override as StandardMaterial3D
	_winch_anchor_mesh = _add_box(self, WINCH_RETURN_POS + Vector3(0.0, 2.75, 0.0),
		Vector3(0.36, 0.8, 0.36), Color(0.11, 0.10, 0.09),
		Color(0.4, 0.72, 0.55), 0.16, "RangeRecoveryAnchor")
	_add_label(self, "RESET WINCH", RECOVERY_RIG_POS + Vector3(0.0, 2.0, 0.0), Color(0.94, 0.54, 0.28))
	_recovery_interactable = _add_interactable(
		self,
		"RangeRecoveryInteractable",
		"Range Reset Winch",
		RECOVERY_RIG_POS,
		"RESET",
		"",
		RECOVERY_WORK_SECONDS,
		true,
		INTERACT_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_recovery_interactable.set("consequence_preview", "starts a 12-second locked pull to the seam; grants no recovery or refund")
	_configure_range_control(_recovery_interactable, "recovery", reset_after_failure)
	_add_causal_feedback_link(_winch_source_mesh, _winch_anchor_mesh, Color(0.4, 0.72, 0.55), {
		"name": "RangeRecoveryWinchRoute",
		"interaction_source": _recovery_interactable,
		"owner_character": "endo",
		"visibility_policy": "hover_only",
		"show_label": false,
		"path_style": "movement_chevrons",
		"flow_speed": 1.2,
		"draw_duration": 0.5,
		"dash_count": 16,
		"source_offset": Vector3(0.0, 0.9, 0.0),
		"target_offset": Vector3(0.0, 0.15, 0.0),
		"arc_height": 0.3,
	})

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
		"REST PARTY", [beacon], "", SHELTER_REST_SECONDS, true, SHELTER_RADIUS,
		Interactable.InteractableType.TIMED_ACTION
	)
	_configure_range_control(_east_shelter_interactable, "shelter", rest_at_east_shelter)
	var gs = _get_game_state()
	if gs != null and gs.has_method("add_shelter_region"):
		gs.add_shelter_region(
			Vector2(EAST_SHELTER_POS.x - 3.0, EAST_SHELTER_POS.z - 2.5),
			Vector2(EAST_SHELTER_POS.x + 3.0, EAST_SHELTER_POS.z + 2.5)
		)

func _build_range_systems() -> void:
	var gs = _get_game_state()
	var scheduler = _get_scheduler()
	if gs == null or scheduler == null:
		return

	# The orange floor is a scheduler-owned spatial hazard. It never asks whether
	# Aster scouted or which UI route is selected; only a body inside its rectangle
	# on a pulse is bitten.
	_direct_bloom_field = HazardFieldScript.new()
	_direct_bloom_field.name = "RangeDirectRustBloomHazard"
	add_child(_direct_bloom_field)
	_direct_bloom_field.setup(gs, scheduler, DIRECT_BLOOM_MIN, DIRECT_BLOOM_MAX,
		["aster", "peris", "endo"], {
			"dps_tick": DIRECT_BLOOM_DAMAGE,
			"interval": DIRECT_BLOOM_INTERVAL,
			"tag": _direct_bloom_tag(),
			"on_bite": Callable(self, "_on_direct_bloom_bite"),
		})
	_direct_bloom_field.set_active(true)

	# These are real Enemy FSM actors: their positions, lure/return phase, target,
	# attacks, and deadlines live in GameState. The spindle calls their reusable
	# lure verb; no render-delta sphere stands in for the encounter.
	for i in range(SWARM_OFFSETS.size()):
		var enemy = EnemyScript.new()
		enemy.name = "RangeSweepEnemy_%d" % i
		enemy.display_name = "Range Sweep %d" % (i + 1)
		enemy.color = Color(0.34, 0.12 + float(i) * 0.025, 0.06)
		enemy.move_speed = SWARM_SPEED
		enemy.pursuit_speed = SWARM_SPEED
		enemy.detection_range = SWARM_DETECTION_RANGE
		enemy.charge_damage = 18.0
		enemy.attack_range = 2.6
		enemy.strike_reach = 1.35
		enemy.char_id = _swarm_id(i)
		enemy.game_state = gs
		enemy.position = _swarm_post(i)
		add_child(enemy)
		gs.register_character(enemy.char_id, enemy.position, enemy.move_speed,
			{"detection_range": enemy.detection_range})
		enemy.set_detection_targets(["aster", "peris", "endo"])
		enemy.activate()
		var patrol: Array[Vector3] = [
			_swarm_post(i) + Vector3(-10.0, 0.0, 0.0),
			_swarm_post(i) + Vector3(8.0, 0.0, 0.0),
		]
		enemy.set_patrol(patrol)
		if not enemy.hit_target.is_connected(_on_swarm_hit_target):
			enemy.hit_target.connect(_on_swarm_hit_target)
		_swarm_enemies.append(enemy)


func _swarm_id(index: int) -> String:
	return "survival_range_sweep_%d" % index


func _swarm_post(index: int) -> Vector3:
	return Vector3(SWARM_START_X + float(index) * 4.0, 0.5, SWARM_OFFSETS[index])


func _swarm_lure_endpoint(index: int) -> Vector3:
	var offset: float = float(SWARM_OFFSETS[index]) * 0.45
	if _lure_route_mode == LURE_ROUTE_RECESS:
		return Vector3(SWARM_LURE_X, 0.5, SWARM_LURE_Z + offset)
	return Vector3(SWARM_UNTUNED_X, 0.5, SWARM_UNTUNED_Z + offset)


func _reset_swarm_to_posts() -> void:
	for i in range(_swarm_enemies.size()):
		var enemy = _swarm_enemies[i]
		if enemy != null and is_instance_valid(enemy) and enemy.has_method("re_post"):
			enemy.re_post(_swarm_post(i))


func _direct_bloom_tag() -> String:
	return "survival_range_direct_bloom:%s" % str(absi(range_authority_key().hash()))


func _on_direct_bloom_bite(char_id: String) -> void:
	_last_outcome = "direct_bloom_bit:%s" % char_id
	_show_message("%s is physically inside the rust bloom on its pulse." % char_id.capitalize(), 1.2)
	_publish_range_authority()


func _on_swarm_hit_target(target_id: String, _damage: float) -> void:
	_last_outcome = "sweep_hit:%s" % target_id
	var gs = _get_game_state()
	if gs != null and gs.has_method("is_downed") and gs.is_downed(target_id):
		_fail_range("sweep_downed_%s" % target_id)
	else:
		_publish_range_authority()

func _update_range(_delta: float) -> void:
	# Gameplay systems are scheduler-owned. This pass derives only spatial
	# concealment/presentation and can be partitioned into any render-frame cadence.
	_update_range_concealment()
	# Gameplay expiry is scheduler-owned. Render cadence only derives the countdown readout.
	_refresh_lure_readback()
	_update_direct_hazard_telegraph()
	if _route_phase in ["failed", "resetting", "complete"]:
		return

	# Reaching the east radius never completes the level by itself. The party must
	# assemble and deliberately work the hearth interaction.


func _on_lure_expired(expected_deadline: float) -> void:
	if _lure_deadline < 0.0 or not is_equal_approx(_lure_deadline, expected_deadline):
		return
	_lure_active = false
	_lure_remaining = 0.0
	_lure_deadline = -1.0
	_lure_route_mode = LURE_ROUTE_NONE
	if _lure_interactable != null and _lure_interactable.has_method("reset"):
		_lure_interactable.reset()
	if _route_phase in ["failed", "resetting", "complete"]:
		_refresh_interaction_gates()
		_update_visual_state()
		_publish_range_authority()
		return
	# Enemy.lure_to owns each sweep body's return phase. Expiry retracts only the
	# information window; it never manufactures a level failure or teleports actors.
	if _route_phase == "window":
		_route_phase = _resolved_setup_phase()
	_refresh_interaction_gates()
	_update_visual_state()
	_publish_range_authority()


func _arm_lure_expiry(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	var tag := _lure_expiry_tag()
	sched.cancel_tag(tag)
	var remaining := deadline - _get_scheduler_tick()
	if remaining <= 0.0:
		_on_lure_expired(deadline)
		return
	sched.schedule_after(remaining, _on_lure_expired.bind(deadline), tag)


func _cancel_lure_expiry() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_lure_expiry_tag())


func _refresh_lure_readback() -> void:
	if not _lure_active or _lure_deadline < 0.0:
		_lure_remaining = 0.0
		return
	_lure_remaining = maxf(0.0, _lure_deadline - _get_scheduler_tick())

func _update_range_concealment() -> void:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("set_character_concealment"):
		return
	for char_id in ["aster", "peris", "endo"]:
		if not gs.characters.has(char_id):
			continue
		var tier := GameState.CONCEAL_NONE
		if _hide_capbage != null and _hide_capbage.conceals(gs.get_position(char_id)):
			tier = GameState.CONCEAL_FULL
		gs.set_character_concealment(char_id, tier)


func _endo_concealment() -> int:
	var gs = _get_game_state()
	if gs == null or not gs.characters.has("endo") or not gs.has_method("get_character_concealment"):
		return GameState.CONCEAL_NONE
	return int(gs.get_character_concealment("endo"))


func _swarm_has_endo_target() -> bool:
	for enemy in _swarm_enemies:
		if enemy != null and is_instance_valid(enemy) and str(enemy._current_target_id) == "endo":
			return true
	return false


func _swarm_clear_of_release_lane() -> bool:
	var gs = _get_game_state()
	if gs == null or _swarm_enemies.is_empty():
		return false
	for i in range(_swarm_enemies.size()):
		var enemy = _swarm_enemies[i]
		if enemy == null or not is_instance_valid(enemy):
			return false
		var pos: Vector3 = gs.get_position(_swarm_id(i)) if gs.characters.has(_swarm_id(i)) else enemy.position
		# The side recess and the whole west side of the release threshold are
		# physically clear of the hide->shelter sprint. A UI lure flag is irrelevant.
		if pos.x > SWARM_CLEAR_X and absf(pos.z) < SWARM_CLEAR_Z:
			return false
	return not _swarm_has_endo_target()


func _swarm_report() -> Array:
	var reports: Array = []
	var gs = _get_game_state()
	for i in range(_swarm_enemies.size()):
		var enemy = _swarm_enemies[i]
		var id := _swarm_id(i)
		var pos: Vector3 = gs.get_position(id) if gs != null and gs.characters.has(id) else Vector3.ZERO
		reports.append({
			"id": id,
			"position": pos,
			"state": str(enemy.get_state()) if enemy != null and enemy.has_method("get_state") else "",
			"target": str(enemy._current_target_id) if enemy != null else "",
			"lure_settle": enemy.get("_lure_settle") if enemy != null else Vector3.ZERO,
			"clear_of_release_lane": pos.x <= SWARM_CLEAR_X or absf(pos.z) >= SWARM_CLEAR_Z,
		})
	return reports


func _scout_readout() -> Dictionary:
	if not _scouted:
		return {"revealed": false}
	var hazard: Dictionary = _direct_bloom_field.get_state() if _direct_bloom_field != null else {}
	return {
		"revealed": true,
		"safe_route": {"from": MID_SEAM_POS, "to": SAFE_CROSS_END_POS, "hazard": "none"},
		"direct_route": {"from": SHORT_BLOOM_POS, "to": DIRECT_CROSS_END_POS,
			"hazard_min": DIRECT_BLOOM_MIN, "hazard_max": DIRECT_BLOOM_MAX},
		"next_bloom_pulse_in": float(hazard.get("next_bite_in", -1.0)),
		"damage_per_pulse": float(hazard.get("damage_per_bite", DIRECT_BLOOM_DAMAGE)),
		"pulse_interval": float(hazard.get("interval", DIRECT_BLOOM_INTERVAL)),
	}

func _route_timing_profile(profile: String) -> Dictionary:
	match profile:
		"staged_safe":
			return {
				"routing_mode": "safe",
				"scout_required": true,
				"lure_required": true,
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

func _predict_cross_damage(short_bloom: bool) -> float:
	if not short_bloom:
		return 0.0
	# The field pulse is fixed world truth. The two-second traverse begins before
	# the rectangle and lands beyond it, so only its midpoint pulse is spatially
	# inside. Scouting reveals this cost but cannot alter it.
	return DIRECT_BLOOM_DAMAGE

## Bind every range verb to the physical control that emitted it. The callback receives its
## source only after Interactable has accepted the exact body, proximity, one-shot, and saved
## registry transaction; public method calls without that receipt are deliberately inert.
func _configure_range_control(control: Node, action_id: String, callback: Callable) -> void:
	if control == null:
		return
	control.set_pre_trigger_validator(
		_validate_range_control_trigger.bind(action_id, control))
	control.interacted.connect(callback.bind(control))


func _validate_range_control_trigger(
	source: Node,
	actor: String,
	action_id: String,
	expected_source: Node
) -> bool:
	if source == null or source != expected_source \
			or source != _range_control_for_action(action_id):
		return false
	return _range_interaction_actor_ready_at(source, actor, _range_required_actor(action_id)) \
		and _range_control_action_ready(action_id)


func _range_control_receipt_pending(source: Node, action_id: String) -> bool:
	if source == null or source != _range_control_for_action(action_id):
		return false
	# Interactable flips a one-shot presenter only after its preflight and serialized
	# GameState trigger succeed. Requiring that spent edge prevents helpers, stale
	# callbacks, and a caller-supplied node reference from impersonating interaction.
	if not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return false
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var spec: Dictionary = gs.get_interactable(data_id)
		return bool(spec.get("one_shot", false)) \
			and bool(spec.get("triggered", false)) \
			and not gs.is_interactable_enabled(data_id)
	return true


func _rearm_range_control(source: Node) -> void:
	if source != null and source.has_method("reset"):
		source.call("reset")
	_refresh_interaction_gates()


func _range_control_for_action(action_id: String) -> Node:
	match action_id:
		"depart":
			return _departure_interactable
		"scout":
			return _scout_interactable
		"echo":
			return _echo_interactable
		"lure":
			return _lure_interactable
		"seam":
			return _seam_interactable
		"direct":
			return _direct_interactable
		"hide":
			return _hide_interactable
		"recovery":
			return _recovery_interactable
		"shelter":
			return _east_shelter_interactable
	return null


func _range_required_actor(action_id: String) -> String:
	match action_id:
		"scout":
			return "aster"
		"echo", "lure":
			return "peris"
		"seam", "direct", "hide":
			return "endo"
	return ""


func _range_interaction_actor_ready_at(source: Node, actor: String, required_actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or actor == "" or not gs.characters.has(actor) \
			or not gs.is_narratively_available(actor):
		return false
	if required_actor != "" and actor != required_actor:
		return false
	if gs.is_moving(actor) or gs.is_resting(actor) or gs.is_dodging(actor) \
			or gs.is_knocked_down(actor) or gs.is_endocytosing(actor) \
			or gs.is_external_traversal_active(actor) or gs.is_dragging(actor) \
			or gs.is_field_restoring(actor):
		return false
	var actor_position: Vector3 = gs.get_position(actor)
	var source_position := _range_control_data_position(source)
	var radius := float(source.get("interaction_radius")) + 0.15
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)) <= radius


func _range_control_data_position(source: Node) -> Vector3:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if source != null else ""
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var position: Variant = gs.get_interactable(data_id).get("position", Vector3.ZERO)
		if position is Vector3:
			return position
	var world_position := (source as Node3D).global_position if source is Node3D else Vector3.ZERO
	if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
		return gs.coord_map.to_data(world_position)
	return world_position


func _range_control_action_ready(action_id: String) -> bool:
	var invalid_phase := _route_phase in ["failed", "resetting", "complete"]
	match action_id:
		"depart":
			return _route_phase == "briefing" and not _departed
		"scout":
			return _departed and not _scouted and not invalid_phase
		"echo":
			return _departed and _scouted and not _echo_tuned and not _lure_active \
				and _route_phase not in ["failed", "resetting", "complete", "window", "crossing", "midway", "run"]
		"lure":
			return _departed and _scouted and not _lure_active \
				and _route_phase not in ["failed", "resetting", "complete", "crossing", "midway", "run"] \
				and _range_swarm_available_for_lure()
		"seam":
			return _departed and _get_routing_mode() != "direct" and _lure_active \
				and not _seam_crossed and _route_phase not in ["failed", "resetting", "complete", "crossing"]
		"direct":
			return _departed and _get_routing_mode() == "direct" and not _seam_crossed \
				and _route_phase not in ["failed", "resetting", "complete", "crossing"]
		"hide":
			return _seam_crossed and _route_phase == "midway"
		"recovery":
			var gs = _get_game_state()
			return _route_phase == "failed" and gs != null \
				and gs.characters.has("endo") and not gs.is_downed("endo") \
				and not gs.is_external_traversal_active("endo")
		"shelter":
			return _route_phase == "run" and _shelter_rest_phase != "committing" \
				and _full_conscious_party_at_east_shelter() \
				and (_preflight_range_shelter_rest().get("blocked", []) as Array).is_empty()
	return false


func _range_swarm_available_for_lure() -> bool:
	for enemy in _swarm_enemies:
		if enemy == null or not is_instance_valid(enemy) \
				or not enemy.has_method("get_lure_availability") \
				or str(enemy.get_lure_availability()) != "available":
			return false
	return not _swarm_enemies.is_empty()

func _refresh_interaction_gates() -> void:
	var direct_route := _get_routing_mode() == "direct"
	_set_interactable_enabled(_departure_interactable, _route_phase == "briefing")
	_set_interactable_enabled(_scout_interactable,
		_departed and not _scouted and _route_phase not in ["failed", "resetting", "complete"])
	_set_interactable_enabled(_echo_interactable,
		_departed and _scouted and not _echo_tuned and not _lure_active
		and _route_phase not in ["failed", "resetting", "complete", "window", "crossing", "midway", "run"])
	_set_interactable_enabled(_lure_interactable,
		_departed and _scouted and not _lure_active
		and _route_phase not in ["failed", "resetting", "complete", "crossing", "midway", "run"])
	_set_interactable_enabled(_seam_interactable,
		_departed and not direct_route and _lure_active and not _seam_crossed
		and _route_phase not in ["failed", "resetting", "complete", "crossing"])
	_set_interactable_enabled(_direct_interactable,
		_departed and direct_route and not _seam_crossed
		and _route_phase not in ["failed", "resetting", "complete", "crossing"])
	_set_interactable_enabled(_hide_interactable,
		_seam_crossed and _route_phase == "midway")
	_set_interactable_enabled(_recovery_interactable, _route_phase == "failed")
	_set_interactable_enabled(
		_east_shelter_interactable,
		_route_phase == "run" and _shelter_rest_phase != "committing")

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
	# Every new failure is a new physical winch transaction. A prior recovery's
	# one-shot receipt must not strand a later failure with a glowing but spent rig.
	if _recovery_interactable != null and _recovery_interactable.has_method("reset"):
		_recovery_interactable.reset()
	_set_preview_step("survival_range_failed")
	_show_message("The range collapses: %s." % reason.replace("_", " "), 1.8)
	_refresh_interaction_gates()
	_update_visual_state()
	_publish_range_authority()

func rest_at_east_shelter(source: Node = null) -> bool:
	if not _range_control_receipt_pending(source, "shelter"):
		return false
	if _route_phase == "complete":
		return true
	if _shelter_rest_phase == "committing":
		return false
	if _route_phase != "run":
		_show_message("The shelter sprint is not open yet.", 1.3)
		return false
	if not _full_conscious_party_at_east_shelter():
		_show_message("Bring Aster, Peris, and Endo into the east shelter conscious.", 1.8)
		return false
	var gs = _get_game_state()
	if gs == null:
		return false
	_sync_host_clock_to_game_state()
	var preflight := _preflight_range_shelter_rest()
	var blocked := preflight.get("blocked", []) as Array
	if not blocked.is_empty():
		_show_message(str(blocked[0]), 1.7)
		return false

	# The range owns the larger "rest completes the route" transaction. Publish COMMITTING before
	# GameState crosses its batch event/signal boundary so a signal-time save can reconcile once.
	_shelter_rest_phase = "committing"
	_shelter_rest_commit_tick = _get_scheduler_tick()
	_shelter_rest_commit_day = gs.get_game_day()
	_shelter_rest_before_atp = (
		preflight.get("before_atp", {}) as Dictionary).duplicate(true)
	_refresh_interaction_gates()
	_publish_range_authority()
	if not bool(gs.command_party_rest(PARTY_IDS)):
		_shelter_rest_phase = "ready"
		_clear_range_shelter_rest_context()
		_refresh_interaction_gates()
		_publish_range_authority()
		_show_message("The party cannot settle into the shelter yet.", 1.5)
		_rearm_range_control(source)
		return false
	_complete_range(true)
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

func _preflight_range_shelter_rest() -> Dictionary:
	var outcome := _preflight_authored_party_rest(
		EAST_SHELTER_POS, Vector2(SHELTER_RADIUS * 2.0, SHELTER_RADIUS * 2.0), PARTY_IDS)
	var blocked := outcome.get("blocked", []) as Array
	if blocked.is_empty() and not _full_conscious_party_at_east_shelter():
		blocked.append("Bring Aster, Peris, and Endo fully inside the east shelter.")
	return outcome


func _complete_range(show_story := false) -> void:
	if _route_phase == "complete":
		return
	_cancel_range_shelter_rest_callback()
	_shelter_rest_phase = "rested"
	_shelter_reached = true
	_route_phase = "complete"
	_hide_phase = "safe"
	_last_outcome = "success"
	_cancel_lure_expiry()
	_lure_active = false
	_lure_remaining = 0.0
	_lure_deadline = -1.0
	_lure_route_mode = LURE_ROUTE_NONE
	_mark_segment("shelter")
	_set_preview_step("survival_range_complete")
	if show_story:
		_show_message("The next shelter holds. The route is now proven.", 1.9)
	_clear_range_shelter_rest_context()
	_refresh_interaction_gates()
	_update_visual_state()
	_publish_range_authority()

func _current_route_instruction() -> String:
	match _route_phase:
		"briefing":
			return "leave the west shelter"
		"departed":
			return "get Aster onto the scout perch"
		"scouted":
			return "compare the lane and recess endpoints; tune or test the spindle"
		"calibrated":
			return "carry the recess route to the spindle"
		"window":
			return "read where the real sweep stopped before moving Endo"
		"crossing":
			return "watch Endo's body cross the live field"
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
		"resetting":
			return "wait for the recovery winch to pull Endo back"
		_:
			return "keep the chain intact"


# --- portable Survival Range authority ---------------------------------------------------------

func range_authority_key() -> String:
	var stable_id := chunk_name if chunk_name != "" else "survival_range"
	return RANGE_AUTHORITY_PREFIX + stable_id


func _lure_expiry_tag() -> String:
	return LURE_EXPIRY_TAG_PREFIX + str(absi(range_authority_key().hash()))


func _winch_traversal_id() -> StringName:
	return StringName(WINCH_TRAVERSAL_PREFIX + str(absi(range_authority_key().hash())))


func _cross_traversal_id(mode: String) -> StringName:
	return StringName("%s%s:%s" % [CROSS_TRAVERSAL_PREFIX,
		str(absi(range_authority_key().hash())), mode])


func _range_authority_state() -> Dictionary:
	_refresh_lure_readback()
	return {
		"version": RANGE_AUTHORITY_VERSION,
		"range_id": range_authority_key(),
		"departed": _departed,
		"route_phase": _route_phase,
		"last_outcome": _last_outcome,
		"segments_completed": _segments_completed.duplicate(),
		"scouted": _scouted,
		"echo_tuned": _echo_tuned,
		"lure_deadline": _lure_deadline,
		"lure_route_mode": _lure_route_mode,
		"seam_crossed": _seam_crossed,
		"cross_mode": _cross_mode,
		"cross_start_hp": _cross_start_hp,
		"hide_phase": _hide_phase,
		"mid_seam_damage": _mid_seam_damage,
		"shelter_reached": _shelter_reached,
		"shelter_rest_phase": _shelter_rest_phase,
		"shelter_rest_commit_tick": _shelter_rest_commit_tick,
		"shelter_rest_commit_day": _shelter_rest_commit_day,
		"shelter_rest_before_atp": _shelter_rest_before_atp.duplicate(true),
		"reset_count": _reset_count,
	}


func _valid_range_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	var route_phase := str(saved.get("route_phase", ""))
	var rest_phase := str(saved.get("shelter_rest_phase", ""))
	var lure_route_mode := str(saved.get("lure_route_mode", LURE_ROUTE_NONE))
	var lure_deadline := float(saved.get("lure_deadline", -1.0))
	var before_atp: Variant = saved.get("shelter_rest_before_atp", null)
	if int(saved.get("version", 0)) != RANGE_AUTHORITY_VERSION \
			or str(saved.get("range_id", "")) != range_authority_key() \
			or route_phase not in VALID_ROUTE_PHASES \
			or str(saved.get("hide_phase", "")) not in VALID_HIDE_PHASES \
			or str(saved.get("cross_mode", "")) not in VALID_CROSS_MODES \
			or lure_route_mode not in VALID_LURE_ROUTES \
			or ((lure_deadline >= 0.0) != (lure_route_mode != LURE_ROUTE_NONE)) \
			or (route_phase == "crossing" \
				and str(saved.get("cross_mode", "")) not in ["seam", "short_bloom"]) \
			or not (saved.get("segments_completed", null) is Array) \
			or rest_phase not in SHELTER_REST_PHASES \
			or not before_atp is Dictionary:
		return false
	var reached := bool(saved.get("shelter_reached", false))
	if (rest_phase == "rested") != reached or (route_phase == "complete") != reached:
		return false
	if rest_phase == "committing":
		if route_phase != "run" or reached \
				or float(saved.get("shelter_rest_commit_tick", -1.0)) < 0.0:
			return false
		for char_id in PARTY_IDS:
			if not (before_atp as Dictionary).has(char_id):
				return false
	elif float(saved.get("shelter_rest_commit_tick", -1.0)) >= 0.0 \
			or not (before_atp as Dictionary).is_empty():
		return false
	return true


func _normalized_range_authority(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var saved := (raw as Dictionary).duplicate(true)
	var saved_version := int(saved.get("version", 0))
	if saved_version == 1:
		saved["cross_mode"] = ""
		saved["cross_start_hp"] = 0.0
	if saved_version in [1, 2]:
		var legacy_rested := bool(saved.get("shelter_reached", false)) \
			and str(saved.get("route_phase", "")) == "complete"
		saved["shelter_rest_phase"] = "rested" if legacy_rested else "ready"
		saved["shelter_rest_commit_tick"] = -1.0
		saved["shelter_rest_commit_day"] = 0
		saved["shelter_rest_before_atp"] = {}
	if saved_version in [1, 2, 3]:
		# Legacy code prohibited an untuned spindle call, so every live legacy
		# deadline necessarily targeted the side recess.
		saved["lure_route_mode"] = (
			LURE_ROUTE_RECESS
			if float(saved.get("lure_deadline", -1.0)) >= 0.0
			else LURE_ROUTE_NONE)
		saved["version"] = RANGE_AUTHORITY_VERSION
	return saved if _valid_range_authority(saved) else {}


func _initialize_range_authority() -> void:
	if _range_authority_initialized:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_world_state"):
		return
	_range_authority_initialized = true
	_range_authority_baseline = _range_authority_state().duplicate(true)
	var saved := _normalized_range_authority(gs.get_world_state(range_authority_key(), null))
	if not saved.is_empty():
		_restore_range_authority(saved)
	else:
		_publish_range_authority()


func _publish_range_authority() -> void:
	if _restoring_range_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(range_authority_key(), _range_authority_state())


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_cancel_range_callbacks()
	_connect_range_game_state_signals()
	_restore_range_system_presenters()
	_range_authority_initialized = true
	if _range_authority_baseline.is_empty():
		_range_authority_baseline = _baseline_range_authority_state()
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(range_authority_key(), null) \
		if gs != null and gs.has_method("get_world_state") else null
	var saved := _normalized_range_authority(raw)
	if saved.is_empty():
		var baseline := _range_authority_baseline.duplicate(true)
		if gs != null and gs.has_method("set_world_state"):
			gs.set_world_state(range_authority_key(), baseline)
		_restore_range_authority(baseline)
		return
	_restore_range_authority(saved)


func _baseline_range_authority_state() -> Dictionary:
	return {
		"version": RANGE_AUTHORITY_VERSION,
		"range_id": range_authority_key(),
		"departed": false,
		"route_phase": "briefing",
		"last_outcome": "",
		"segments_completed": [],
		"scouted": false,
		"echo_tuned": false,
		"lure_deadline": -1.0,
		"lure_route_mode": LURE_ROUTE_NONE,
		"seam_crossed": false,
		"cross_mode": "",
		"cross_start_hp": 0.0,
		"hide_phase": "ready",
		"mid_seam_damage": 0.0,
		"shelter_reached": false,
		"shelter_rest_phase": "ready",
		"shelter_rest_commit_tick": -1.0,
		"shelter_rest_commit_day": 0,
		"shelter_rest_before_atp": {},
		"reset_count": 0,
	}


func _restore_range_authority(saved: Dictionary) -> void:
	_restoring_range_authority = true
	_cancel_range_callbacks()
	_departed = bool(saved.get("departed", false))
	_route_phase = str(saved.get("route_phase", "briefing"))
	_last_outcome = str(saved.get("last_outcome", ""))
	_segments_completed.clear()
	for segment_v in saved.get("segments_completed", []) as Array:
		var segment := str(segment_v)
		if segment != "" and not _segments_completed.has(segment):
			_segments_completed.append(segment)
	_scouted = bool(saved.get("scouted", false))
	_echo_tuned = bool(saved.get("echo_tuned", false))
	_lure_deadline = float(saved.get("lure_deadline", -1.0))
	_lure_route_mode = str(saved.get("lure_route_mode", LURE_ROUTE_NONE))
	_lure_active = _lure_deadline > _get_scheduler_tick()
	_refresh_lure_readback()
	_seam_crossed = bool(saved.get("seam_crossed", false))
	_cross_mode = str(saved.get("cross_mode", ""))
	_cross_start_hp = maxf(0.0, float(saved.get("cross_start_hp", 0.0)))
	_hide_phase = str(saved.get("hide_phase", "ready"))
	_mid_seam_damage = maxf(0.0, float(saved.get("mid_seam_damage", 0.0)))
	_shelter_reached = bool(saved.get("shelter_reached", false))
	_shelter_rest_phase = str(saved.get("shelter_rest_phase", "ready"))
	_shelter_rest_commit_tick = float(saved.get("shelter_rest_commit_tick", -1.0))
	_shelter_rest_commit_day = int(saved.get("shelter_rest_commit_day", 0))
	_shelter_rest_before_atp = (
		saved.get("shelter_rest_before_atp", {}) as Dictionary).duplicate(true)
	_reset_count = maxi(0, int(saved.get("reset_count", 0)))
	_restoring_range_authority = false

	var winch_state := _winch_traversal_state()
	var cross_state := _cross_traversal_state()
	var owned_traversal := _range_owned_external_traversal_state()
	if _route_phase == "resetting" and winch_state.is_empty():
		# A route phase without its movement owner is corrupt/incomplete. Leave the player at their
		# saved position and re-open the physical reset; never manufacture the upper endpoint.
		_route_phase = "failed"
		_hide_phase = "failed"
		_last_outcome = "winch_interrupted"
	elif _route_phase != "resetting" and not winch_state.is_empty():
		# The inverse mismatch would leave Endo locked in a traversal the range no longer acknowledges.
		var gs = _get_game_state()
		if gs != null and gs.has_method("cancel_external_traversal"):
			gs.cancel_external_traversal("endo", &"range_authority_mismatch")
	if _route_phase == "crossing" and cross_state.is_empty():
		# The world record cannot prove arrival without the traversal owner. Keep
		# Endo at the loaded position and expose the bounded reset instead.
		_route_phase = "failed"
		_hide_phase = "failed"
		_last_outcome = "cross_interrupted"
	elif _route_phase != "crossing" and not cross_state.is_empty():
		var gs = _get_game_state()
		if gs != null and gs.has_method("cancel_external_traversal"):
			gs.cancel_external_traversal("endo", &"range_authority_mismatch")
	elif _route_phase not in ["crossing", "resetting"] and not owned_traversal.is_empty():
		# Absence rollback can remove the local mode that identifies an otherwise
		# surviving future traversal. Match by this chunk's stable id prefix so that
		# the unowned motion cannot finish later and grant an endpoint.
		var gs = _get_game_state()
		if gs != null and gs.has_method("cancel_external_traversal"):
			gs.cancel_external_traversal("endo", &"range_authority_absent")

	_normalize_range_source_receipt_registry()
	if _lure_active:
		_arm_lure_expiry(_lure_deadline)
	elif _lure_deadline >= 0.0:
		_on_lure_expired(_lure_deadline)
	_refresh_interaction_gates()
	_update_visual_state()
	_apply_range_feedback_state()
	_set_preview_step(_preview_step_for_route_phase())
	_publish_range_authority()
	if _shelter_rest_phase == "committing":
		_arm_range_shelter_rest_callback()


## Range authority owns consequences; the Interactable registry owns only the short accepted-source
## edge. A snapshot can land synchronously after GameState records a trigger but before `interacted`
## commits the range record. Re-arm every source on restore, then let the restored range phase derive
## which controls are enabled. That makes the uncommitted seam retryable without guessing a result.
func _normalize_range_source_receipt_registry() -> void:
	var gs = _get_game_state()
	for source_v in [
		_departure_interactable,
		_scout_interactable,
		_echo_interactable,
		_lure_interactable,
		_seam_interactable,
		_direct_interactable,
		_hide_interactable,
		_recovery_interactable,
		_east_shelter_interactable,
	]:
		var source: Node = source_v
		if not is_instance_valid(source):
			continue
		source.set("one_shot", true)
		var data_id := str(source.get("data_id"))
		if gs != null and data_id != "" and gs.has_interactable(data_id):
			var spec: Dictionary = gs.get_interactable(data_id)
			if not bool(spec.get("one_shot", false)):
				spec["id"] = data_id
				spec["one_shot"] = true
				spec["triggered"] = false
				spec["enabled"] = true
				gs.register_interactable(spec)
		if source.has_method("reset"):
			source.reset()


func _restore_range_system_presenters() -> void:
	var gs = _get_game_state()
	if _direct_bloom_field != null and _direct_bloom_field.has_method("on_game_state_snapshot_restored"):
		var hazard_key: String = _direct_bloom_field.authority_state_key()
		var has_saved_hazard := gs != null and gs.get_world_state(hazard_key, null) is Dictionary
		_direct_bloom_field.on_game_state_snapshot_restored()
		if not has_saved_hazard:
			# This field exists at construction. Missing runtime phase means the save
			# predates its first callback, not that the visible rust ceased to burn.
			_direct_bloom_field.set_active(true)
	for enemy in _swarm_enemies:
		if enemy != null and is_instance_valid(enemy) and enemy.has_method("on_game_state_snapshot_restored"):
			enemy.on_game_state_snapshot_restored()
	_update_range_concealment()


func _preview_step_for_route_phase() -> String:
	match _route_phase:
		"briefing": return "survival_range_briefing"
		"departed": return "survival_range_departed"
		"scouted": return "survival_range_scouted"
		"calibrated": return "survival_range_echo_tuned"
		"window": return "survival_range_window"
		"crossing": return "survival_range_crossing"
		"midway": return "survival_range_midway"
		"run": return "survival_range_run"
		"failed": return "survival_range_failed"
		"resetting": return "survival_range_resetting"
		"complete": return "survival_range_complete"
		_: return "survival_range_briefing"


func _connect_range_game_state_signals() -> void:
	var gs = _get_game_state()
	if gs == _range_signal_game_state:
		return
	if _range_signal_game_state != null and is_instance_valid(_range_signal_game_state):
		if _range_signal_game_state.external_traversal_finished.is_connected(_on_winch_traversal_finished):
			_range_signal_game_state.external_traversal_finished.disconnect(_on_winch_traversal_finished)
		if _range_signal_game_state.external_traversal_finished.is_connected(_on_cross_traversal_finished):
			_range_signal_game_state.external_traversal_finished.disconnect(_on_cross_traversal_finished)
		if _range_signal_game_state.external_traversal_cancelled.is_connected(_on_winch_traversal_cancelled):
			_range_signal_game_state.external_traversal_cancelled.disconnect(_on_winch_traversal_cancelled)
		if _range_signal_game_state.external_traversal_cancelled.is_connected(_on_cross_traversal_cancelled):
			_range_signal_game_state.external_traversal_cancelled.disconnect(_on_cross_traversal_cancelled)
	_range_signal_game_state = gs
	if gs == null:
		return
	if not gs.external_traversal_finished.is_connected(_on_winch_traversal_finished):
		gs.external_traversal_finished.connect(_on_winch_traversal_finished)
	if not gs.external_traversal_finished.is_connected(_on_cross_traversal_finished):
		gs.external_traversal_finished.connect(_on_cross_traversal_finished)
	if not gs.external_traversal_cancelled.is_connected(_on_winch_traversal_cancelled):
		gs.external_traversal_cancelled.connect(_on_winch_traversal_cancelled)
	if not gs.external_traversal_cancelled.is_connected(_on_cross_traversal_cancelled):
		gs.external_traversal_cancelled.connect(_on_cross_traversal_cancelled)


func _on_winch_traversal_cancelled(
		char_id: String, traversal_id: StringName, reason: StringName
	) -> void:
	if char_id != "endo" or traversal_id != _winch_traversal_id() or _route_phase != "resetting":
		return
	_route_phase = "failed"
	_hide_phase = "failed"
	_last_outcome = "winch_%s" % String(reason)
	_set_preview_step("survival_range_failed")
	_refresh_interaction_gates()
	_update_visual_state()
	_apply_range_feedback_state()
	_publish_range_authority()


func _on_cross_traversal_cancelled(
		char_id: String, traversal_id: StringName, reason: StringName
	) -> void:
	if char_id != "endo" or _route_phase != "crossing" or _cross_mode == "" \
			or traversal_id != _cross_traversal_id(_cross_mode):
		return
	_route_phase = "failed"
	_hide_phase = "failed"
	_last_outcome = "cross_%s" % String(reason)
	_set_preview_step("survival_range_failed")
	_refresh_interaction_gates()
	_update_visual_state()
	_publish_range_authority()


func _winch_traversal_state() -> Dictionary:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_external_traversal_state"):
		return {}
	var state: Dictionary = gs.get_external_traversal_state("endo")
	if state.is_empty() or StringName(str(state.get("traversal_id", ""))) != _winch_traversal_id():
		return {}
	return state


func _cross_traversal_state() -> Dictionary:
	var gs = _get_game_state()
	if gs == null or _cross_mode == "" or not gs.has_method("get_external_traversal_state"):
		return {}
	var state: Dictionary = gs.get_external_traversal_state("endo")
	if state.is_empty() or StringName(str(state.get("traversal_id", ""))) != _cross_traversal_id(_cross_mode):
		return {}
	return state


func _range_owned_external_traversal_state() -> Dictionary:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_external_traversal_state"):
		return {}
	var state: Dictionary = gs.get_external_traversal_state("endo")
	var traversal_id := str(state.get("traversal_id", ""))
	var stable_hash := str(absi(range_authority_key().hash()))
	if traversal_id == str(_winch_traversal_id()) \
			or traversal_id.begins_with(CROSS_TRAVERSAL_PREFIX + stable_hash + ":"):
		return state
	return {}


func _cancel_range_callbacks() -> void:
	_cancel_lure_expiry()
	_cancel_range_shelter_rest_callback()


func _clear_range_shelter_rest_context() -> void:
	_shelter_rest_commit_tick = -1.0
	_shelter_rest_commit_day = 0
	_shelter_rest_before_atp.clear()


func _range_shelter_rest_tag() -> String:
	return SHELTER_REST_TAG_PREFIX + range_authority_key().sha256_text().substr(0, 12)


func _cancel_range_shelter_rest_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler != null:
		scheduler.cancel_tag(_range_shelter_rest_tag())


func _arm_range_shelter_rest_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or _shelter_rest_phase != "committing":
		return
	scheduler.cancel_tag(_range_shelter_rest_tag())
	scheduler.schedule_at(
		maxf(_get_scheduler_tick(), _shelter_rest_commit_tick),
		_resume_committed_range_shelter_rest.bind(_shelter_rest_commit_tick),
		_range_shelter_rest_tag())


func _resume_committed_range_shelter_rest(expected_tick: float) -> void:
	if _shelter_rest_phase != "committing" \
			or not is_equal_approx(_shelter_rest_commit_tick, expected_tick):
		return
	if _authored_party_rest_effect_matches(
			PARTY_IDS, _shelter_rest_before_atp, _shelter_rest_commit_day):
		_complete_range(true)
		return
	var preflight := _preflight_range_shelter_rest()
	if not _range_shelter_preflight_matches_commit(preflight):
		_shelter_rest_phase = "ready"
		_clear_range_shelter_rest_context()
		_refresh_interaction_gates()
		_publish_range_authority()
		return
	var gs = _get_game_state()
	if gs != null and bool(gs.command_party_rest(PARTY_IDS)):
		_complete_range(true)
	else:
		_shelter_rest_phase = "ready"
		_clear_range_shelter_rest_context()
		_refresh_interaction_gates()
		_publish_range_authority()


func _range_shelter_preflight_matches_commit(preflight: Dictionary) -> bool:
	var gs = _get_game_state()
	if gs == null or gs.get_game_day() != _shelter_rest_commit_day \
			or not (preflight.get("blocked", []) as Array).is_empty() \
			or preflight.get("members", []) != PARTY_IDS:
		return false
	for char_id in PARTY_IDS:
		if not _shelter_rest_before_atp.has(char_id) \
				or not is_equal_approx(
					gs.get_stat(char_id, "atp"),
					float(_shelter_rest_before_atp[char_id])):
			return false
	return true


func _apply_range_feedback_state() -> void:
	if _echo_interactable != null:
		# Hover-only means this relationship never clutters ordinary traversal.
		# Its grammar still reports whether the selected route is safe, active, or
		# the specific cause of the last failed prediction.
		_set_causal_feedback_latched(_echo_interactable, false)
		if _last_outcome == "untuned_echo_blocks_release":
			_set_causal_feedback_mode(_echo_interactable, "failed")
		elif _lure_active:
			_set_causal_feedback_mode(
				_echo_interactable,
				"active" if _lure_route_mode == LURE_ROUTE_RECESS else "warning")
		elif _echo_tuned:
			_set_causal_feedback_mode(_echo_interactable, "complete")
		else:
			_set_causal_feedback_mode(_echo_interactable, "warning")
	if _recovery_interactable != null:
		var pulling := _route_phase == "resetting"
		_set_causal_feedback_latched(_recovery_interactable, pulling)
		if pulling:
			_set_causal_feedback_mode(_recovery_interactable, "active")
		elif _route_phase == "failed":
			_set_causal_feedback_mode(_recovery_interactable, "ready")
		elif _reset_count > 0:
			_set_causal_feedback_mode(_recovery_interactable, "complete")
		else:
			_set_causal_feedback_mode(_recovery_interactable, "predicted")

func _update_visual_state() -> void:
	_set_signal_material(_west_beacon_material, not _departed, Color(0.18, 0.18, 0.16), Color(0.94, 0.8, 0.48), 0.9)
	_set_signal_material(_east_beacon_material, _route_phase == "run" or _route_phase == "complete", Color(0.18, 0.18, 0.16), Color(0.98, 0.86, 0.56), 1.0 if _route_phase == "complete" else 0.45)
	_set_signal_material(_spindle_material, _lure_active, Color(0.22, 0.18, 0.12), Color(0.88, 0.46, 0.18), 1.25)
	_set_signal_material(_echo_material, _echo_tuned, Color(0.15, 0.19, 0.21), Color(0.42, 0.76, 0.92), 0.95)
	_set_signal_material(_echo_lane_indicator_material, not _echo_tuned,
		Color(0.18, 0.10, 0.065), Color(1.0, 0.42, 0.14), 1.15)
	_set_signal_material(_echo_recess_indicator_material, _echo_tuned,
		Color(0.07, 0.14, 0.17), Color(0.36, 0.82, 0.98), 1.15)
	if _echo_direction_arm != null:
		_echo_direction_arm.rotation_degrees.y = 34.0 if _echo_tuned else -34.0
	if _echo_route_link != null:
		_echo_route_link.set(
			"target",
			_echo_recess_receiver if _echo_tuned else _echo_lane_receiver)
	_set_signal_material(_seam_material, _scouted, Color(0.22, 0.24, 0.26), Color(0.48, 0.68, 0.86), 0.7)
	_set_signal_material(_hide_material, _hide_phase in ["hide", "run", "safe"], Color(0.14, 0.18, 0.16), Color(0.42, 0.84, 0.58), 0.85)
	_set_signal_material(_winch_material, _route_phase == "resetting", Color(0.18, 0.14, 0.10), Color(0.4, 0.72, 0.55), 1.15)
	_update_direct_hazard_telegraph()
	_apply_range_feedback_state()


func _update_direct_hazard_telegraph() -> void:
	if _direct_bloom_material == null:
		return
	var hazard: Dictionary = _direct_bloom_field.get_state() if _direct_bloom_field != null else {}
	var remaining := float(hazard.get("next_bite_in", DIRECT_BLOOM_INTERVAL))
	var approach := 1.0 - clampf(remaining / DIRECT_BLOOM_INTERVAL, 0.0, 1.0)
	_direct_bloom_material.emission_enabled = true
	_direct_bloom_material.emission = Color(0.92, 0.26, 0.08)
	_direct_bloom_material.emission_energy_multiplier = 0.35 + approach * 1.1

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
