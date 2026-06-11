extends "res://scripts/scene_chunks/scene_chunk.gd"

const FLOOR_CENTER := Vector3(42.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(88.0, 0.1, 24.0)

const WEST_SHELTER_POS := Vector3(8.0, 0.45, 0.0)
const SCOUT_PERCH_POS := Vector3(18.5, 0.45, -4.0)
const MID_SEAM_POS := Vector3(35.0, 0.45, -1.8)
const SHORT_BLOOM_POS := Vector3(37.4, 0.45, 3.6)
const LURE_SPINDLE_POS := Vector3(49.5, 0.45, 0.0)
const HIDE_SLIT_POS := Vector3(63.0, 0.45, -3.2)
const EAST_SHELTER_POS := Vector3(77.0, 0.45, 0.0)

const LURE_DURATION := 5.6
const INTERACT_DWELL := 1.0
const INTERACT_RADIUS := 2.4
const SHELTER_RADIUS := 2.6
const PERIS_TUNE_BONUS := 1.4
const ARRIVAL_BUFFER := 0.1
const SWARM_SPEED := 11.0
const SWARM_START_X := 74.5
const SWARM_LURE_X := 51.5
const SWARM_HIDE_X := 63.2
const SWARM_OFFSETS := [-1.8, 0.0, 1.8]

const SPAWNS := {
	"aster": Vector3(7.0, 0.5, 1.4),
	"peris": Vector3(5.4, 0.5, 0.0),
	"endo": Vector3(6.0, 0.5, -1.7),
}

var _departure_interactable
var _scout_interactable
var _lure_interactable
var _seam_interactable
var _hide_interactable

var _west_beacon_material: StandardMaterial3D
var _east_beacon_material: StandardMaterial3D
var _spindle_material: StandardMaterial3D
var _seam_material: StandardMaterial3D
var _hide_material: StandardMaterial3D
var _swarm_materials: Array[StandardMaterial3D] = []
var _swarm_markers: Array[MeshInstance3D] = []

var _departed := false
var _route_phase := "briefing"
var _last_outcome := ""
var _segments_completed: Array[String] = []
var _scouted := false
var _lure_active := false
var _lure_remaining := 0.0
var _seam_crossed := false
var _hide_phase := "ready"
var _mid_seam_damage := 0.0
var _shelter_reached := false

func _build_chunk() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.09, 0.095, 0.11))
	_add_box(self, Vector3(42.0, 2.4, -12.1), Vector3(88.0, 4.8, 0.3), Color(0.13, 0.14, 0.16))
	_add_box(self, Vector3(42.0, 2.4, 12.1), Vector3(88.0, 4.8, 0.3), Color(0.13, 0.14, 0.16))

	for i in range(8):
		var blend := float(i) / 7.0
		_add_light(
			self,
			Vector3(8.0 + float(i) * 10.0, 3.4, 0.0),
			Color(0.28 + blend * 0.22, 0.3 + blend * 0.16, 0.38 + blend * 0.18),
			1.1 + blend * 1.4,
			14.0
		)

	_build_west_shelter()
	_build_scout_perch()
	_build_mid_seam()
	_build_lure_spindle()
	_build_hide_slit()
	_build_east_shelter()
	_build_swarm_markers()
	_update_visual_state()
	_set_preview_step("survival_range_briefing")

func _process(delta: float) -> void:
	_update_range(delta)

func headless_process(delta: float) -> void:
	_update_range(delta)

func get_scene_title() -> String:
	return "Shelter-To-Shelter Range"

func get_scene_help() -> String:
	return "Leave the west shelter, let Aster mark the route, let Peris pull the sweep with the spindle, then get Endo through the seam, into the slit, and across to the next shelter."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"west_shelter": WEST_SHELTER_POS,
		"scout_perch": SCOUT_PERCH_POS,
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
		"lure_active": _lure_active,
		"lure_remaining": _lure_remaining,
		"seam_crossed": _seam_crossed,
		"hide_phase": _hide_phase,
		"mid_seam_damage": _mid_seam_damage,
		"shelter_reached": _shelter_reached,
	}

func get_route_timing_predictions() -> Dictionary:
	return {
		"staged_safe": predict_route_timing("staged_safe"),
		"optimal_safe": predict_route_timing("optimal_safe"),
		"greedy_direct": predict_route_timing("greedy_direct"),
	}

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
		INTERACT_DWELL,
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
			INTERACT_DWELL,
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
			INTERACT_DWELL,
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
		INTERACT_DWELL,
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
		INTERACT_DWELL,
		"hide"
	)
	segments["hide"] = hide
	positions["endo"] = hide["end_position"]

	if not lure_required:
		total_time += float(seam.get("total_time", 0.0))
		total_time += float(hide.get("total_time", 0.0))
		return {
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
		}

	var active_window := LURE_DURATION + (PERIS_TUNE_BONUS if use_peris_tune else 0.0)
	var window_elapsed := float(seam.get("total_time", 0.0)) + float(hide.get("total_time", 0.0))
	var window_margin := active_window - window_elapsed

	if window_margin < 0.0:
		return {
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
		}

	total_time = pre_window_total
	total_time += float(seam.get("total_time", 0.0))
	total_time += float(hide.get("total_time", 0.0))
	var hold_time := maxf(window_margin, 0.0)
	segments["hold"] = {
		"label": "hold",
		"total_time": hold_time,
	}
	total_time += hold_time

	var shelter: Dictionary = _predict_station_action(
		"endo",
		positions["endo"],
		EAST_SHELTER_POS,
		SHELTER_RADIUS,
		shelter_running,
		0.0,
		"shelter"
	)
	segments["shelter"] = shelter
	total_time += float(shelter.get("total_time", 0.0))

	return {
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
	}

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
				"FOG: the spindle still remembers the slit and the shelter chain.",
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
	_lure_active = false
	_lure_remaining = 0.0
	_seam_crossed = false
	_hide_phase = "ready"
	_mid_seam_damage = 0.0
	_shelter_reached = false
	_set_preview_step("survival_range_briefing")

	for interactable in [_departure_interactable, _scout_interactable, _lure_interactable, _seam_interactable, _hide_interactable]:
		if interactable != null and interactable.has_method("reset"):
			interactable.reset()

	for i in range(_swarm_markers.size()):
		var marker := _swarm_markers[i]
		if marker != null:
			marker.position = Vector3(SWARM_START_X, 0.72, SWARM_OFFSETS[i])

	_update_visual_state()

func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	match ability_id:
		"aster_focus":
			if not _scouted and _get_character_position("aster").distance_to(SCOUT_PERCH_POS) <= INTERACT_RADIUS + 0.6:
				_scouted = true
				_mark_segment("scouted")
				_route_phase = "scouted" if _route_phase == "briefing" or _route_phase == "departed" else _route_phase
				_set_preview_step("survival_range_scouted")
				_show_note("Aster's mark resolves the refuge seam and the slit.", 2.4)
				_update_visual_state()
			return {
				"characters": {
					"aster": {"sta_delta": 8.0},
				},
			}
		"peris_tune":
			if _lure_active:
				_lure_remaining += 1.4
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
	_update_visual_state()
	return true

func survey_route() -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if not _require_station("aster", SCOUT_PERCH_POS, "the scout perch"):
		return false
	_scouted = true
	_mark_segment("scouted")
	if _route_phase in ["briefing", "departed"]:
		_route_phase = "scouted"
	_set_preview_step("survival_range_scouted")
	_show_message("Aster marks the refuge seam and the hide slit.", 1.8)
	_update_visual_state()
	return true

func activate_range_lure() -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if not _require_station("peris", LURE_SPINDLE_POS, "the lure spindle"):
		return false
	_lure_active = true
	_lure_remaining = LURE_DURATION
	_mark_segment("lure")
	_route_phase = "window"
	_set_preview_step("survival_range_window")
	_show_message("Peris opens a lure window across the corridor.", 1.8)
	_update_visual_state()
	return true

func cross_seam() -> bool:
	if _route_phase in ["failed", "complete"]:
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
	_hide_phase = "hide"
	_mark_segment("hide")
	_route_phase = "hide"
	_set_preview_step("survival_range_hide")
	_show_message("Stay hidden until the lure burns out.", 1.6)
	_update_visual_state()
	return true

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
		INTERACT_DWELL,
		false,
		INTERACT_RADIUS
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
		INTERACT_DWELL,
		false,
		INTERACT_RADIUS
	)
	_scout_interactable.interacted.connect(survey_route)

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
		INTERACT_DWELL,
		false,
		INTERACT_RADIUS
	)
	_seam_interactable.interacted.connect(cross_seam)

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
		INTERACT_DWELL,
		false,
		INTERACT_RADIUS
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
		INTERACT_DWELL,
		false,
		INTERACT_RADIUS
	)
	_hide_interactable.interacted.connect(commit_hide)

func _build_east_shelter() -> void:
	# Arriving is only half the loop: the destination shelter is a REAL rest point (sleep heals,
	# costs ATP, and the night skips once everyone conscious is bedded down).
	_add_rest_point(self, EAST_SHELTER_POS, Vector2(6.0, 5.0))
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
			elif _seam_crossed and not _shelter_reached:
				_fail_range("late_window")
				return
			_update_visual_state()

	if _hide_phase == "hide":
		if _get_character_position("endo").distance_to(HIDE_SLIT_POS) > INTERACT_RADIUS + 0.8:
			_fail_range("broke_cover")
			return
	elif _hide_phase == "run":
		if _get_character_position("endo").distance_to(EAST_SHELTER_POS) <= SHELTER_RADIUS:
			_complete_range()

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
	_update_visual_state()

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
	_update_visual_state()

func _current_route_instruction() -> String:
	match _route_phase:
		"briefing":
			return "leave the west shelter"
		"departed":
			return "get Aster onto the scout perch"
		"scouted":
			return "let Peris open the spindle window"
		"window":
			return "move Endo through the seam"
		"midway":
			return "reach the hide slit"
		"hide":
			return "hold until the sweep commits away"
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
