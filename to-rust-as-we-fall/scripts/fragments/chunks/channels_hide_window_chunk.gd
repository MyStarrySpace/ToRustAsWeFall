extends "res://scripts/scene_chunks/scene_chunk.gd"

const FLOOR_CENTER := Vector3(22.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(58.0, 0.1, 34.0)
const MAIN_LANE_CENTER := Vector3(21.0, -0.04, -0.4)
const MAIN_LANE_SIZE := Vector3(32.0, 0.08, 7.2)
const BRANCH_CENTER := Vector3(15.2, -0.04, -7.2)
const BRANCH_SIZE := Vector3(16.0, 0.08, 12.5)
const HIDE_CORRIDOR_CENTER := Vector3(9.8, -0.04, -11.8)
const HIDE_CORRIDOR_SIZE := Vector3(8.6, 0.08, 4.8)

const STAGE_POS := Vector3(8.0, 0.45, -1.6)
const LURE_POS := Vector3(14.0, 0.45, -12.4)
const CURTAIN_POS := Vector3(24.0, 0.62, -0.8)
const GOAL_POS := Vector3(34.0, 0.45, 0.0)
const HIDE_ENTRY_POS := Vector3(11.8, 0.45, -10.8)
const HIDE_PATCH_POS := Vector3(8.0, 0.45, -11.9)

const CURTAIN_OFFSETS := [-4.0, -2.0, 0.0, 2.0, 4.0]
const PERIODIC_CHANNELS := 3
const FLOW_PERIOD := 6.0
const FLOOD_DURATION := 1.1
const SAFE_DURATION := 13.5
const SEARCH_DURATION := 1.8
const DETECTION_ARM_DELAY := 0.75
const SWARM_SPEED := 3.6
const SWARM_DELAY := 0.12
const SWARM_WASH_SPEED := 8.4
const SWARM_RESET_SPEED := 10.0
const CHANNEL_T_VALUES := [0.30, 0.49, 0.68]
const SWARM_OFFSETS := [-1.4, -0.7, 0.0, 0.7, 1.4]
const CONCEAL_PATCH_RADIUS := 2.25

const SPAWNS := {
	"aster": Vector3(7.4, 0.5, -2.0),
	"peris": Vector3(5.6, 0.5, -0.3),
	"endo": Vector3(5.8, 0.5, -3.5),
}

var _lure_interactable
var _lure_mesh: MeshInstance3D
var _lure_light: OmniLight3D
var _curtain_nodes: Array[MeshInstance3D] = []
var _periodic_channels: Array = []
var _bridge_segments: Array[MeshInstance3D] = []
var _corpse_nodes: Array[MeshInstance3D] = []
var _swarm_units: Array = []
var _swarm_path: Array[Vector3] = []
var _channel_contact_map := {}

var _hide_patch_mesh: MeshInstance3D
var _hide_patch_material: StandardMaterial3D
var _hide_corridor_lights: Array[OmniLight3D] = []

var _branch_dir := Vector3.FORWARD
var _cross_dir := Vector3.RIGHT
var _attract_pos := Vector3.ZERO
var _swarm_start_pos := Vector3.ZERO
var _search_pos := Vector3.ZERO

var _phase := "activate"
var _last_outcome := ""
var _lure_active := false
var _safe_until_tick := -1.0
var _swarm_state := "idle"
var _swarm_start_tick := -1.0
var _washed_channel_index := -1
var _flow_offset := 0.0
var _timing_offset := 0.0
var _search_until_tick := -1.0
var _detect_arm_tick := -1.0
var _detected := false
var _concealed_retries := 0
var _wash_analysis := {}

func _build_chunk() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.065, 0.075, 0.09))
	_add_floor(self, MAIN_LANE_CENTER, MAIN_LANE_SIZE, Color(0.085, 0.095, 0.11))
	_add_floor(self, BRANCH_CENTER, BRANCH_SIZE, Color(0.075, 0.09, 0.105))
	_add_floor(self, HIDE_CORRIDOR_CENTER, HIDE_CORRIDOR_SIZE, Color(0.06, 0.1, 0.085))

	_add_box(self, Vector3(FLOOR_CENTER.x, 2.2, -FLOOR_SIZE.z * 0.5 - 0.18), Vector3(FLOOR_SIZE.x, 4.4, 0.36), Color(0.14, 0.15, 0.17))
	_add_box(self, Vector3(FLOOR_CENTER.x, 2.2, FLOOR_SIZE.z * 0.5 + 0.18), Vector3(FLOOR_SIZE.x, 4.4, 0.36), Color(0.14, 0.15, 0.17))
	_add_box(self, Vector3(STAGE_POS.x - 6.0, 2.2, BRANCH_CENTER.z), Vector3(0.36, 4.4, BRANCH_SIZE.z + 3.0), Color(0.12, 0.13, 0.16))
	_add_box(self, Vector3(GOAL_POS.x + 6.0, 2.2, MAIN_LANE_CENTER.z), Vector3(0.36, 4.4, MAIN_LANE_SIZE.z + 2.0), Color(0.12, 0.13, 0.16))
	_add_box(self, HIDE_CORRIDOR_CENTER + Vector3(0.0, 1.65, -2.55), Vector3(HIDE_CORRIDOR_SIZE.x, 3.2, 0.3), Color(0.1, 0.13, 0.12))
	_add_box(self, HIDE_CORRIDOR_CENTER + Vector3(0.0, 1.65, 2.55), Vector3(HIDE_CORRIDOR_SIZE.x, 3.2, 0.3), Color(0.1, 0.13, 0.12))
	_add_box(self, HIDE_CORRIDOR_CENTER + Vector3(-4.45, 1.65, 0.0), Vector3(0.3, 3.2, HIDE_CORRIDOR_SIZE.z), Color(0.1, 0.13, 0.12))

	for i in range(5):
		_add_light(
			self,
			Vector3(4.0 + float(i) * 9.0, 3.2, -1.5 + sin(float(i)) * 0.7),
			Color(0.28 + float(i) * 0.05, 0.33 + float(i) * 0.04, 0.42 + float(i) * 0.03),
			1.0 + float(i) * 0.16,
			11.5
		)

	_branch_dir = _branch_direction(STAGE_POS, LURE_POS)
	_cross_dir = _cross_direction(_branch_dir)
	_attract_pos = CURTAIN_POS + Vector3(0.0, 0.0, signf(LURE_POS.z - STAGE_POS.z) * 9.0)
	_search_pos = HIDE_ENTRY_POS + _branch_dir * 0.55 + _cross_dir * 0.8

	_build_stage()
	_build_goal()
	_build_lure()
	_build_curtain()
	_build_corpse_cluster()
	_build_periodic_bridge()
	_build_hide_corridor()
	_build_swarm_units()

	_wash_analysis = _wash_analysis_report()
	reset_preview_state()

func _process(delta: float) -> void:
	_update_lane(delta)

func headless_process(delta: float) -> void:
	_update_lane(delta)

func get_scene_title() -> String:
	return "Channels Hide Window"

func get_scene_help() -> String:
	return "This lane keeps the early ferrolure bridge idea, but the surge cadence is no longer guaranteed. Read the flood timing, and if you miss it, duck into the hush-moss corridor until the pack searches past and you can retry."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	return {
		"stage": STAGE_POS,
		"lure": LURE_POS,
		"curtain": CURTAIN_POS,
		"goal": GOAL_POS,
		"hide_entry": HIDE_ENTRY_POS,
		"hide_patch": HIDE_PATCH_POS,
		"swarm_start": _swarm_start_pos,
		"search_point": _search_pos,
	}

func get_preview_time_state() -> Dictionary:
	return {
		"day": 2,
		"time": 0.41,
		"advance_time": false,
		"routing_mode": "safe",
		"note_default": "The bridge no longer guarantees a wash. If the cadence misses, cut into the hush moss corridor and wait for the pack to peel off before you try again.",
	}

func get_preview_abilities() -> Array:
	return [
		{
			"id": "aster_focus",
			"display_name": "TRACE",
			"duration": 0.8,
			"cooldown": 4.0,
			"message": "Aster pings the uneven surge rhythm.",
			"note": "TRACE surfaces one known safe lure offset and one dead offset for this lane.",
		},
		{
			"id": "peris_tune",
			"display_name": "BLOOM",
			"duration": 0.8,
			"cooldown": 5.0,
			"message": "Peris thickens the hush moss for a breath.",
			"note": "BLOOM steadies the concealment patch if the pack is already sweeping the corridor mouth.",
		},
		{
			"id": "endo_patch",
			"display_name": "BRACE",
			"duration": 0.8,
			"cooldown": 6.0,
			"message": "Endo commits the fallback sprint.",
			"note": "BRACE is a timing reminder: if the wash misses, go left into the corridor immediately.",
		},
	]

func get_preview_state() -> Dictionary:
	var channels: Array = []
	var visible_swarm_units := 0
	var washed_swarm_units := 0
	for channel_variant in _periodic_channels:
		var channel: Dictionary = channel_variant
		channels.append({
			"position": channel.get("position", Vector3.ZERO),
			"contact_time": float(channel.get("contact_time", 0.0)),
			"phase_offset": float(channel.get("phase_offset", 0.0)),
			"local_phase": float(channel.get("local_phase", 0.0)),
			"level": float(channel.get("level", 0.0)),
			"flooded": bool(channel.get("flooded", false)),
		})
	for unit_variant in _swarm_units:
		var unit: Dictionary = unit_variant
		var node = unit.get("node")
		if is_instance_valid(node) and node.visible:
			visible_swarm_units += 1
		if str(unit.get("state", "")) == "washed":
			washed_swarm_units += 1
	return {
		"phase": _phase,
		"last_outcome": _last_outcome,
		"lure_active": _lure_active,
		"safe_until_tick": _safe_until_tick,
		"flow_period": FLOW_PERIOD,
		"flood_duration": FLOOD_DURATION,
		"timing_offset": _timing_offset,
		"flow_offset": _flow_offset,
		"periodic_channel_count": _periodic_channels.size(),
		"bridge_segment_count": _bridge_segments.size(),
		"corpse_count": _corpse_nodes.size(),
		"swarm_unit_count": _swarm_units.size(),
		"visible_swarm_units": visible_swarm_units,
		"washed_swarm_units": washed_swarm_units,
		"swarm_state": _swarm_state,
		"washed_channel_index": _washed_channel_index,
		"detected": _detected,
		"search_until_tick": _search_until_tick,
		"detect_arm_tick": _detect_arm_tick,
		"inside_conceal_patch": _is_active_character_in_patch(),
		"concealment_active": _concealment_active(),
		"concealed_retries": _concealed_retries,
		"corridor_present": true,
		"conceal_patch_present": is_instance_valid(_hide_patch_mesh),
		"conceal_patch_radius": CONCEAL_PATCH_RADIUS,
		"wash_analysis": _wash_analysis.duplicate(true),
		"channels": channels,
	}

func get_preview_overlay_status(overlay_id: String, _current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return [
				"DATA: three surge channels on a six-second loop, but the bridge is no longer fully covered.",
				"Read: safe sample %.2fs / dead sample %.2fs" % [
					float(_wash_analysis.get("safe_sample_offset", -1.0)),
					float(_wash_analysis.get("failed_sample_offset", -1.0)),
				],
				"Hush corridor: %s" % ("concealed" if _concealment_active() else "open"),
			]
		"peris":
			return [
				"FOG: corpse memory pulls toward the lure, then collapses into the hush moss corridor.",
				"Blur: %s" % ("the pack is already hunting the corridor mouth" if _swarm_state in ["searching", "detected"] else "the bridge can still take them"),
				"Hush moss: %s" % ("masking while unspotted" if not _detected else "burned once marked"),
			]
		"endo":
			return [
				"SURVIVAL: read the wash, or cut left into the corridor and hold inside the patch.",
				"Status: %s" % _phase,
				"Next: %s" % _current_instruction(),
			]
		_:
			return []

func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	match ability_id:
		"aster_focus":
			return {
				"note": "Sample safe offset %.2fs. Sample dead offset %.2fs." % [
					float(_wash_analysis.get("safe_sample_offset", -1.0)),
					float(_wash_analysis.get("failed_sample_offset", -1.0)),
				],
			}
		"peris_tune":
			if _swarm_state == "searching" and not _detected and _concealment_active():
				_search_until_tick += 0.7
				return {"note": "Peris thickens the hush moss. The search will slide past a little longer."}
			return {"note": "Peris can only thicken the patch while the pack is actively searching and you are still concealed."}
		"endo_patch":
			return {"note": "If the bridge misses, sprint left and stay in the patch until the sweep peels off."}
		_:
			return {}

func reset_preview_state() -> void:
	_phase = "activate"
	_last_outcome = ""
	_lure_active = false
	_safe_until_tick = -1.0
	_swarm_state = "idle"
	_swarm_start_tick = -1.0
	_washed_channel_index = -1
	_flow_offset = 0.0
	_timing_offset = 0.0
	_search_until_tick = -1.0
	_detect_arm_tick = -1.0
	_detected = false
	_concealed_retries = 0
	_set_lane_active(false)

	for i in range(_curtain_nodes.size()):
		var node := _curtain_nodes[i]
		if is_instance_valid(node):
			node.position = CURTAIN_POS + Vector3(0.0, 0.0, CURTAIN_OFFSETS[i])

	if _lure_interactable != null:
		if _lure_interactable.has_method("reset"):
			_lure_interactable.call("reset")
		if _lure_interactable.has_method("show_tutorial_label"):
			_lure_interactable.call("show_tutorial_label")

	_reset_swarm_units()
	_update_channel_visuals(_get_scheduler_tick())
	_update_visual_state()
	_set_preview_step("channels_hide_window_activate")

func activate_lure() -> bool:
	if _phase == "failed":
		return false
	if _lure_active or _swarm_state in ["advancing", "washing", "searching", "resetting", "detected"]:
		return false
	_set_lane_active(true)
	_phase = "window"
	_last_outcome = ""
	_safe_until_tick = _get_scheduler_tick() + SAFE_DURATION
	_swarm_state = "advancing"
	_swarm_start_tick = _get_scheduler_tick()
	_washed_channel_index = -1
	_search_until_tick = -1.0
	_detect_arm_tick = -1.0
	_detected = false

	for i in range(_swarm_units.size()):
		var unit: Dictionary = _swarm_units[i]
		unit["state"] = "advance"
		unit["path_index"] = 1
		unit["wash_vector"] = Vector3.ZERO
		_swarm_units[i] = unit

	if _lure_interactable != null and _lure_interactable.has_method("hide_tutorial_label"):
		_lure_interactable.call("hide_tutorial_label")
	_set_preview_step("channels_hide_window_window")
	_show_message("The pack commits to the lure. If the surge misses, cut into the hush moss corridor.", 2.0)
	_update_visual_state()
	return true

func set_timing_offset(offset: float) -> void:
	_timing_offset = fposmod(offset, FLOW_PERIOD)
	_flow_offset = _timing_offset - _get_scheduler_tick()
	_update_channel_visuals(_get_scheduler_tick())

func set_recommended_offset(kind: String) -> bool:
	var key := "safe_sample_offset" if kind.strip_edges().to_lower() == "safe" else "failed_sample_offset"
	var offset := float(_wash_analysis.get(key, -1.0))
	if offset < 0.0:
		return false
	set_timing_offset(offset)
	return true

func get_wash_analysis() -> Dictionary:
	return _wash_analysis.duplicate(true)

func _build_stage() -> void:
	var stage_ring := MeshInstance3D.new()
	stage_ring.name = "StageRing"
	var stage_mesh := CylinderMesh.new()
	stage_mesh.top_radius = 1.35
	stage_mesh.bottom_radius = 1.35
	stage_mesh.height = 0.04
	stage_ring.mesh = stage_mesh
	stage_ring.material_override = _make_material(Color(0.18, 0.24, 0.3), Color(0.18, 0.32, 0.46), 0.45)
	stage_ring.position = STAGE_POS + Vector3(0.0, 0.03, 0.0)
	add_child(stage_ring)
	_add_label(self, "STAGE", STAGE_POS + Vector3(0.0, 1.9, 0.0), Color(0.74, 0.82, 0.9))

func _build_goal() -> void:
	var goal_beacon := MeshInstance3D.new()
	goal_beacon.name = "GoalBeacon"
	var goal_mesh := CylinderMesh.new()
	goal_mesh.top_radius = 0.65
	goal_mesh.bottom_radius = 0.65
	goal_mesh.height = 0.12
	goal_beacon.mesh = goal_mesh
	goal_beacon.material_override = _make_material(Color(0.3, 0.48, 0.56), Color(0.32, 0.64, 0.76), 0.5)
	goal_beacon.position = GOAL_POS + Vector3(0.0, 0.06, 0.0)
	add_child(goal_beacon)
	_add_light(self, GOAL_POS + Vector3(0.0, 1.6, 0.0), Color(0.36, 0.78, 0.92), 1.4, 8.0)
	_add_label(self, "GOAL", GOAL_POS + Vector3(0.0, 1.9, 0.0), Color(0.56, 0.82, 0.96))

func _build_lure() -> void:
	var lure_root := Node3D.new()
	lure_root.name = "Ferrolure"
	lure_root.position = LURE_POS
	add_child(lure_root)

	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.08
	stem_mesh.bottom_radius = 0.12
	stem_mesh.height = 0.95
	stem.mesh = stem_mesh
	stem.material_override = _make_material(Color(0.24, 0.28, 0.18))
	stem.position = Vector3(0.0, 0.48, 0.0)
	lure_root.add_child(stem)

	_lure_mesh = MeshInstance3D.new()
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.34
	bulb_mesh.height = 0.68
	_lure_mesh.mesh = bulb_mesh
	_lure_mesh.material_override = _make_material(Color(0.56, 0.34, 0.16), Color(0.82, 0.46, 0.18), 0.35)
	_lure_mesh.position = Vector3(0.0, 1.0, 0.0)
	lure_root.add_child(_lure_mesh)

	_lure_light = _add_light(lure_root, Vector3(0.0, 1.1, 0.0), Color(0.92, 0.5, 0.2), 0.45, 7.5)
	_lure_interactable = _add_interactable(
		self,
		"FerrolureInteract",
		"Ferrolure",
		LURE_POS,
		"HOLD",
		"aster",
		1.6,
		false,
		2.4
	)
	_lure_interactable.interacted.connect(_on_lure_interacted)
	_add_label(self, "FERROLURE", LURE_POS + Vector3(0.0, 2.2, 0.0), Color(0.92, 0.68, 0.42))

func _build_curtain() -> void:
	for i in range(CURTAIN_OFFSETS.size()):
		var curtain := MeshInstance3D.new()
		curtain.name = "Curtain_%d" % i
		var curtain_mesh := SphereMesh.new()
		curtain_mesh.radius = 0.36
		curtain_mesh.height = 0.72
		curtain.mesh = curtain_mesh
		curtain.material_override = _make_material(Color(0.2, 0.14, 0.08), Color(0.7, 0.24, 0.08), 0.55)
		curtain.position = CURTAIN_POS + Vector3(0.0, 0.0, CURTAIN_OFFSETS[i])
		add_child(curtain)
		_curtain_nodes.append(curtain)

func _build_corpse_cluster() -> void:
	var corpse_center := STAGE_POS - _branch_dir * 5.8 - _cross_dir * 1.6
	var corpse_offsets := [
		Vector3.ZERO,
		_cross_dir * 1.55 - _branch_dir * 0.85,
		_cross_dir * -1.35 + _branch_dir * 0.75,
	]
	for i in range(corpse_offsets.size()):
		var corpse := MeshInstance3D.new()
		corpse.name = "Corpse_%d" % i
		var corpse_mesh := CapsuleMesh.new()
		corpse_mesh.radius = 0.22 + 0.03 * float(i)
		corpse_mesh.height = 1.0 + 0.1 * float(i)
		corpse.mesh = corpse_mesh
		corpse.material_override = _make_material(Color(0.18, 0.16, 0.15).lerp(Color(0.24, 0.18, 0.16), float(i) * 0.2))
		corpse.position = corpse_center + corpse_offsets[i] + Vector3(0.0, 0.28, 0.0)
		corpse.rotation_degrees = Vector3(88.0, 24.0 * float(i), 80.0 - 8.0 * float(i))
		add_child(corpse)
		_corpse_nodes.append(corpse)
	_add_label(self, "CORPSES", corpse_center + Vector3(0.0, 1.8, 0.0), Color(0.86, 0.7, 0.54))

func _build_periodic_bridge() -> void:
	_swarm_start_pos = STAGE_POS - _branch_dir * 4.85 - _cross_dir * 1.45
	_swarm_path.clear()
	_channel_contact_map.clear()
	_periodic_channels.clear()
	_bridge_segments.clear()

	_swarm_path.append(_swarm_start_pos)
	_swarm_path.append(STAGE_POS - _branch_dir * 1.4 - _cross_dir * 1.1)

	var channel_specs: Array = []
	var channel_lateral_offsets := [-1.15, 1.35, -0.85]
	for i in range(PERIODIC_CHANNELS):
		var t := float(CHANNEL_T_VALUES[i])
		var lateral := float(channel_lateral_offsets[i % channel_lateral_offsets.size()])
		var approach := STAGE_POS.lerp(LURE_POS, maxf(0.08, t - 0.055)) + _cross_dir * (lateral * 0.72)
		var channel_pos := STAGE_POS.lerp(LURE_POS, t) + _cross_dir * lateral
		var exit := STAGE_POS.lerp(LURE_POS, minf(0.9, t + 0.055)) + _cross_dir * (-lateral * 0.42)
		if _swarm_path[_swarm_path.size() - 1].distance_to(approach) > 0.3:
			_swarm_path.append(approach)
		_swarm_path.append(channel_pos)
		channel_specs.append({
			"position": channel_pos,
			"path_index": _swarm_path.size() - 1,
		})
		_swarm_path.append(exit)
	_swarm_path.append(LURE_POS + _branch_dir * 0.35 + _cross_dir * 0.45)

	for i in range(_swarm_path.size() - 1):
		_bridge_segments.append(_add_bridge_segment(
			"Bridge_%d" % i,
			_swarm_path[i],
			_swarm_path[i + 1]
		))

	var path_distances: Array = []
	var path_distance := 0.0
	for i in range(_swarm_path.size()):
		if i == 0:
			path_distances.append(0.0)
			continue
		path_distance += _swarm_path[i - 1].distance_to(_swarm_path[i])
		path_distances.append(path_distance)

	var desired_spacing := FLOW_PERIOD / float(PERIODIC_CHANNELS)
	for i in range(channel_specs.size()):
		var spec: Dictionary = channel_specs[i]
		var channel_root := Node3D.new()
		channel_root.name = "Channel_%d" % i
		channel_root.position = spec.get("position", Vector3.ZERO)
		channel_root.look_at_from_position(channel_root.position, channel_root.position + _cross_dir, Vector3.UP, true)
		add_child(channel_root)

		var trench := MeshInstance3D.new()
		var trench_mesh := BoxMesh.new()
		trench_mesh.size = Vector3(2.6, 0.32, 5.8)
		trench.mesh = trench_mesh
		trench.material_override = _make_material(Color(0.07, 0.1, 0.12))
		trench.position = Vector3(0.0, 0.12, 0.0)
		channel_root.add_child(trench)

		var water := MeshInstance3D.new()
		var water_mesh := BoxMesh.new()
		water_mesh.size = Vector3(1.65, 1.0, 5.1)
		water.mesh = water_mesh
		water.material_override = _make_material(Color(0.08, 0.16, 0.24), Color(0.14, 0.42, 0.65), 0.3)
		water.position = Vector3(0.0, -0.22, 0.0)
		channel_root.add_child(water)

		var foam := MeshInstance3D.new()
		var foam_mesh := BoxMesh.new()
		foam_mesh.size = Vector3(1.7, 0.08, 5.2)
		foam.mesh = foam_mesh
		foam.material_override = _make_material(
			Color(0.54, 0.7, 0.78, 0.8),
			Color(0.42, 0.78, 0.9),
			0.18,
			BaseMaterial3D.TRANSPARENCY_ALPHA
		)
		foam.position = Vector3(0.0, 0.1, 0.0)
		channel_root.add_child(foam)

		var channel_light := _add_light(channel_root, Vector3(0.0, 1.0, 0.0), Color(0.24, 0.58, 0.8), 0.35, 5.0)
		var contact_path_index := int(spec.get("path_index", 0))
		var contact_time := float(path_distances[contact_path_index]) / SWARM_SPEED
		var desired_start := fposmod(float(i) * desired_spacing, FLOW_PERIOD)
		var phase_offset := fposmod(-contact_time - desired_start, FLOW_PERIOD)
		_periodic_channels.append({
			"index": i,
			"position": spec.get("position", Vector3.ZERO),
			"path_index": contact_path_index,
			"contact_time": contact_time,
			"phase_offset": phase_offset,
			"root": channel_root,
			"water": water,
			"foam": foam,
			"light": channel_light,
			"level": 0.0,
			"flooded": false,
			"local_phase": 0.0,
		})
		_channel_contact_map[contact_path_index] = i

func _build_hide_corridor() -> void:
	_add_label(self, "HIDE CORRIDOR", HIDE_ENTRY_POS + Vector3(-1.2, 2.0, 0.0), Color(0.68, 0.88, 0.8))
	_add_label(self, "HUSH MOSS", HIDE_PATCH_POS + Vector3(0.0, 1.7, 0.0), Color(0.54, 0.96, 0.74))
	for i in range(2):
		var light := _add_light(
			self,
			HIDE_CORRIDOR_CENTER + Vector3(-2.4 + float(i) * 3.8, 1.8, 0.0),
			Color(0.22, 0.6, 0.44),
			0.38,
			5.4
		)
		_hide_corridor_lights.append(light)

	_hide_patch_mesh = MeshInstance3D.new()
	var patch_mesh := CylinderMesh.new()
	patch_mesh.top_radius = CONCEAL_PATCH_RADIUS
	patch_mesh.bottom_radius = CONCEAL_PATCH_RADIUS
	patch_mesh.height = 0.05
	_hide_patch_mesh.mesh = patch_mesh
	_hide_patch_material = _make_material(
		Color(0.14, 0.28, 0.18, 0.92),
		Color(0.3, 0.86, 0.5),
		0.28,
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)
	_hide_patch_mesh.material_override = _hide_patch_material
	_hide_patch_mesh.position = HIDE_PATCH_POS + Vector3(0.0, 0.03, 0.0)
	add_child(_hide_patch_mesh)

func _build_swarm_units() -> void:
	_swarm_units.clear()
	for i in range(SWARM_OFFSETS.size()):
		var swarm := MeshInstance3D.new()
		swarm.name = "Swarm_%d" % i
		var swarm_mesh := SphereMesh.new()
		swarm_mesh.radius = 0.28
		swarm_mesh.height = 0.56
		swarm.mesh = swarm_mesh
		swarm.material_override = _make_material(Color(0.32, 0.19, 0.08), Color(0.86, 0.3, 0.08), 0.4)
		var base_pos: Vector3 = (
			_swarm_start_pos
			+ _cross_dir * (SWARM_OFFSETS[i] * 0.65)
			+ _branch_dir * (0.22 * float(i % 2) - 0.28)
		)
		swarm.position = base_pos
		add_child(swarm)
		_swarm_units.append({
			"node": swarm,
			"base_pos": base_pos,
			"delay": float(i) * SWARM_DELAY,
			"path_index": 1,
			"state": "idle",
			"wash_vector": Vector3.ZERO,
		})

func _update_lane(delta: float) -> void:
	var current_tick := _get_scheduler_tick()
	_update_channel_visuals(current_tick)
	_update_swarm(delta, current_tick)
	_update_curtain(delta)
	_update_visual_state()

	if _swarm_state == "washed" and _phase != "safe":
		if _phase != "cross":
			_phase = "cross"
			_set_preview_step("channels_hide_window_cross")
			_show_message("The bridge clears. Cross now.", 1.6)
		if _get_character_position("aster").distance_to(GOAL_POS) <= 2.6:
			_phase = "safe"
			_last_outcome = "success"
			_safe_until_tick = -1.0
			_set_lane_active(false)
			_set_preview_step("channels_hide_window_safe")
			return

	if _phase == "window" and _safe_until_tick >= 0.0 and current_tick >= _safe_until_tick and _swarm_state not in ["washed", "washing"]:
		_begin_search(current_tick)

func _update_channel_visuals(current_tick: float) -> void:
	for i in range(_periodic_channels.size()):
		var channel: Dictionary = _periodic_channels[i]
		var local_phase := _channel_local_phase(current_tick, channel)
		var level := _channel_level(local_phase)
		channel["local_phase"] = local_phase
		channel["level"] = level
		channel["flooded"] = local_phase < FLOOD_DURATION

		var water = channel.get("water")
		var water_height := -0.22
		var water_scale := maxf(0.08, level)
		if is_instance_valid(water):
			water.scale = Vector3(1.0, water_scale, 1.0)
			water.position.y = -0.42 + water.scale.y * 0.46
			water_height = water.position.y
			var water_mat := water.material_override as StandardMaterial3D
			if water_mat != null:
				water_mat.emission_energy_multiplier = lerpf(0.2, 1.3, level)

		var foam = channel.get("foam")
		if is_instance_valid(foam):
			foam.position.y = water_height + 0.42 * water_scale
			foam.visible = bool(channel.get("flooded", false))
			var foam_mat := foam.material_override as StandardMaterial3D
			if foam_mat != null:
				var foam_color := foam_mat.albedo_color
				foam_color.a = 0.35 + 0.45 * level
				foam_mat.albedo_color = foam_color
				foam_mat.emission_energy_multiplier = lerpf(0.08, 0.48, level)

		var light = channel.get("light")
		if is_instance_valid(light):
			light.light_energy = lerpf(0.2, 1.15, level)

		_periodic_channels[i] = channel

func _update_swarm(delta: float, current_tick: float) -> void:
	match _swarm_state:
		"advancing":
			var wash_triggered := false
			var wash_channel_index := -1
			var all_lured := not _swarm_units.is_empty()
			for i in range(_swarm_units.size()):
				var unit: Dictionary = _swarm_units[i]
				var node = unit.get("node")
				if not is_instance_valid(node):
					_swarm_units[i] = unit
					continue
				if current_tick < _swarm_start_tick + float(unit.get("delay", 0.0)):
					all_lured = false
					_swarm_units[i] = unit
					continue
				if str(unit.get("state", "")) == "washed":
					_swarm_units[i] = unit
					continue
				var path_index := int(unit.get("path_index", 0))
				if path_index >= _swarm_path.size():
					unit["state"] = "lured"
					_swarm_units[i] = unit
					continue
				all_lured = false
				var target: Vector3 = _swarm_path[path_index]
				node.position = node.position.move_toward(target, delta * SWARM_SPEED)
				if node.position.distance_to(target) <= 0.08:
					if _channel_contact_map.has(path_index):
						var candidate_channel_index := int(_channel_contact_map[path_index])
						if candidate_channel_index >= 0 and candidate_channel_index < _periodic_channels.size():
							var contact_channel: Dictionary = _periodic_channels[candidate_channel_index]
							if bool(contact_channel.get("flooded", false)):
								wash_triggered = true
								wash_channel_index = candidate_channel_index
					unit["path_index"] = path_index + 1
					if int(unit.get("path_index", 0)) >= _swarm_path.size():
						unit["state"] = "lured"
				_swarm_units[i] = unit
				if wash_triggered:
					break
			if wash_triggered:
				_trigger_swarm_wash(wash_channel_index, current_tick)
			elif all_lured:
				_begin_search(current_tick)
		"washing":
			var washed_count := 0
			for i in range(_swarm_units.size()):
				var unit: Dictionary = _swarm_units[i]
				var node = unit.get("node")
				if not is_instance_valid(node):
					_swarm_units[i] = unit
					continue
				if str(unit.get("state", "")) == "washed":
					washed_count += 1
					_swarm_units[i] = unit
					continue
				var wash_vector: Vector3 = unit.get("wash_vector", Vector3.ZERO)
				node.position += wash_vector * delta
				node.position.y -= delta * 1.6
				node.scale = node.scale.move_toward(Vector3.ONE * 0.28, delta * 1.2)
				if current_tick - _swarm_start_tick >= 1.1 + float(unit.get("delay", 0.0)) * 0.5:
					node.visible = false
					unit["state"] = "washed"
					washed_count += 1
				_swarm_units[i] = unit
			if washed_count >= _swarm_units.size() and not _swarm_units.is_empty():
				_swarm_state = "washed"
				_search_until_tick = -1.0
				_detect_arm_tick = -1.0
				_set_lane_active(false)
		"searching":
			_move_swarm_to_target(delta, _search_pos, SWARM_SPEED * 0.85)
			if current_tick >= _detect_arm_tick and not _concealment_active():
				_trigger_detection()
				return
			if current_tick >= _search_until_tick:
				_begin_reset()
		"resetting":
			if _move_swarm_to_base(delta):
				_finish_reset()
		"detected":
			_move_swarm_to_target(delta, _get_character_position(_get_active_character()), SWARM_SPEED * 0.95)

func _update_curtain(delta: float) -> void:
	for i in range(_curtain_nodes.size()):
		var node := _curtain_nodes[i]
		if not is_instance_valid(node):
			continue
		var base_target := CURTAIN_POS + Vector3(0.0, 0.0, CURTAIN_OFFSETS[i])
		var active_target := _attract_pos + Vector3(0.35 * CURTAIN_OFFSETS[i], 0.0, 0.7 * CURTAIN_OFFSETS[i])
		node.position = node.position.move_toward(active_target if _lure_active else base_target, delta * 6.0)

func _update_visual_state() -> void:
	_set_lane_active(_lure_active)
	if _hide_patch_material != null:
		var concealed := _concealment_active()
		var patch_color := Color(0.16, 0.28, 0.18, 0.88)
		if _detected:
			patch_color = Color(0.28, 0.16, 0.14, 0.88)
		elif concealed:
			patch_color = Color(0.24, 0.4, 0.22, 0.92)
		_hide_patch_material.albedo_color = patch_color
		_hide_patch_material.emission_enabled = true
		_hide_patch_material.emission = Color(0.34, 0.92, 0.58) if not _detected else Color(0.9, 0.34, 0.2)
		_hide_patch_material.emission_energy_multiplier = 0.95 if concealed else (0.18 if _detected else 0.42)

	for light in _hide_corridor_lights:
		if not is_instance_valid(light):
			continue
		light.light_energy = 0.95 if _concealment_active() else 0.38
		light.light_color = Color(0.34, 0.92, 0.58) if not _detected else Color(0.88, 0.38, 0.24)

func _set_lane_active(active: bool) -> void:
	_lure_active = active
	if is_instance_valid(_lure_mesh):
		var lure_mat := _lure_mesh.material_override as StandardMaterial3D
		if lure_mat != null:
			lure_mat.emission_energy_multiplier = 1.9 if active else 0.35
	if is_instance_valid(_lure_light):
		_lure_light.light_energy = 2.1 if active else 0.45

func _reset_swarm_units() -> void:
	for i in range(_swarm_units.size()):
		var unit: Dictionary = _swarm_units[i]
		unit["state"] = "idle"
		unit["path_index"] = 1
		unit["wash_vector"] = Vector3.ZERO
		var node = unit.get("node")
		if is_instance_valid(node):
			node.visible = true
			node.scale = Vector3.ONE
			node.position = unit.get("base_pos", node.position)
		_swarm_units[i] = unit

func _begin_search(current_tick: float) -> void:
	if _swarm_state in ["searching", "resetting", "detected", "washed"]:
		return
	_swarm_state = "searching"
	_phase = "hide"
	_last_outcome = "missed_window"
	_lure_active = false
	_safe_until_tick = -1.0
	_search_until_tick = current_tick + SEARCH_DURATION
	_detect_arm_tick = current_tick + DETECTION_ARM_DELAY
	for i in range(_swarm_units.size()):
		var unit: Dictionary = _swarm_units[i]
		unit["state"] = "search"
		_swarm_units[i] = unit
	_set_preview_step("channels_hide_window_hide")
	_show_message("The surge misses. Cut into the hush moss corridor before the pack reacquires you.", 2.1)

func _begin_reset() -> void:
	if _swarm_state != "searching":
		return
	_swarm_state = "resetting"
	_phase = "retry"
	_last_outcome = "retry_ready"
	_detect_arm_tick = -1.0
	_search_until_tick = -1.0
	_concealed_retries += 1
	for i in range(_swarm_units.size()):
		var unit: Dictionary = _swarm_units[i]
		unit["state"] = "reset"
		_swarm_units[i] = unit
	_set_preview_step("channels_hide_window_retry")
	_show_message("The pack searches past the corridor and peels back. Re-time the lure.", 2.0)

func _finish_reset() -> void:
	_swarm_state = "idle"
	_phase = "activate"
	if _lure_interactable != null and _lure_interactable.has_method("show_tutorial_label"):
		_lure_interactable.call("show_tutorial_label")
	_set_preview_step("channels_hide_window_activate")

func _trigger_detection() -> void:
	if _detected:
		return
	_detected = true
	_swarm_state = "detected"
	_phase = "failed"
	_last_outcome = "detected"
	_lure_active = false
	_set_preview_step("channels_hide_window_failed")
	_show_message("The pack marks you before the patch can hide you.", 2.0)

func _trigger_swarm_wash(channel_index: int, current_tick: float) -> void:
	_swarm_state = "washing"
	_washed_channel_index = channel_index
	_swarm_start_tick = current_tick
	for i in range(_swarm_units.size()):
		var unit: Dictionary = _swarm_units[i]
		unit["state"] = "wash"
		unit["wash_vector"] = _branch_dir * SWARM_WASH_SPEED + _cross_dir * (SWARM_OFFSETS[i] * 0.65)
		_swarm_units[i] = unit

func _move_swarm_to_target(delta: float, target_center: Vector3, speed: float) -> void:
	for i in range(_swarm_units.size()):
		var unit: Dictionary = _swarm_units[i]
		var node = unit.get("node")
		if not is_instance_valid(node):
			continue
		if not node.visible:
			continue
		var target: Vector3 = target_center + _cross_dir * (SWARM_OFFSETS[i] * 0.55) + _branch_dir * (0.08 * float(i % 2))
		node.position = node.position.move_toward(target, delta * speed)

func _move_swarm_to_base(delta: float) -> bool:
	var all_at_base := true
	for i in range(_swarm_units.size()):
		var unit: Dictionary = _swarm_units[i]
		var node = unit.get("node")
		if not is_instance_valid(node):
			continue
		var target: Vector3 = unit.get("base_pos", node.position)
		node.position = node.position.move_toward(target, delta * SWARM_RESET_SPEED)
		if node.position.distance_to(target) > 0.08:
			all_at_base = false
	return all_at_base

func _add_bridge_segment(name: String, from_pos: Vector3, to_pos: Vector3) -> MeshInstance3D:
	var segment := MeshInstance3D.new()
	segment.name = name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.45, 0.18, maxf(0.8, from_pos.distance_to(to_pos) + 0.35))
	segment.mesh = mesh
	segment.material_override = _make_material(Color(0.18, 0.16, 0.12), Color(0.48, 0.3, 0.12), 0.15)
	segment.position = (from_pos + to_pos) * 0.5 + Vector3(0.0, 0.72, 0.0)
	segment.look_at_from_position(segment.position, to_pos + Vector3(0.0, 0.72, 0.0), Vector3.UP, true)
	add_child(segment)
	return segment

func _branch_direction(stage_pos: Vector3, lure_pos: Vector3) -> Vector3:
	var branch := lure_pos - stage_pos
	branch.y = 0.0
	if branch.length() <= 0.001:
		return Vector3.FORWARD
	return branch.normalized()

func _cross_direction(branch_dir: Vector3) -> Vector3:
	return Vector3(-branch_dir.z, 0.0, branch_dir.x).normalized()

func _channel_local_phase(current_tick: float, channel: Dictionary) -> float:
	return fposmod(current_tick + _flow_offset + float(channel.get("phase_offset", 0.0)), FLOW_PERIOD)

func _channel_level(local_phase: float) -> float:
	if local_phase < FLOOD_DURATION:
		var flood_t := clampf(local_phase / maxf(FLOOD_DURATION, 0.001), 0.0, 1.0)
		return 0.62 + 0.28 * sin(PI * flood_t)
	var cooldown_t := clampf((local_phase - FLOOD_DURATION) / maxf(FLOW_PERIOD - FLOOD_DURATION, 0.001), 0.0, 1.0)
	return lerpf(0.22, 0.06, cooldown_t)

func _offset_washes(offset: float) -> bool:
	for channel_variant in _periodic_channels:
		var channel: Dictionary = channel_variant
		for unit_variant in _swarm_units:
			var unit: Dictionary = unit_variant
			var local_phase := fposmod(
				offset
				+ float(channel.get("contact_time", 0.0))
				+ float(unit.get("delay", 0.0))
				+ float(channel.get("phase_offset", 0.0)),
				FLOW_PERIOD
			)
			if local_phase < FLOOD_DURATION:
				return true
	return false

func _add_wrapped_interval(intervals: Array, start: float, duration: float) -> void:
	var wrapped_start := fposmod(start, FLOW_PERIOD)
	var finish := wrapped_start + duration
	if finish <= FLOW_PERIOD:
		intervals.append({"start": wrapped_start, "end": finish})
		return
	intervals.append({"start": wrapped_start, "end": FLOW_PERIOD})
	intervals.append({"start": 0.0, "end": finish - FLOW_PERIOD})

func _wash_analysis_report(sample_count := 180) -> Dictionary:
	var intervals: Array = []
	for channel_variant in _periodic_channels:
		var channel: Dictionary = channel_variant
		for unit_variant in _swarm_units:
			var unit: Dictionary = unit_variant
			var start := (
				-float(channel.get("contact_time", 0.0))
				- float(unit.get("delay", 0.0))
				- float(channel.get("phase_offset", 0.0))
			)
			_add_wrapped_interval(intervals, start, FLOOD_DURATION)
	intervals.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("start", 0.0)) < float(b.get("start", 0.0)))

	var merged: Array = []
	for interval_variant in intervals:
		var interval: Dictionary = interval_variant
		if merged.is_empty():
			merged.append(interval.duplicate(true))
			continue
		var current: Dictionary = merged[merged.size() - 1]
		if float(interval.get("start", 0.0)) <= float(current.get("end", 0.0)) + 0.0001:
			current["end"] = maxf(float(current.get("end", 0.0)), float(interval.get("end", 0.0)))
			merged[merged.size() - 1] = current
			continue
		merged.append(interval.duplicate(true))

	var largest_gap := FLOW_PERIOD
	var largest_gap_start := 0.0
	var largest_gap_end := FLOW_PERIOD
	if not merged.is_empty():
		largest_gap = 0.0
		for i in range(merged.size()):
			var current: Dictionary = merged[i]
			var next: Dictionary = merged[(i + 1) % merged.size()]
			var gap := float(next.get("start", 0.0)) - float(current.get("end", 0.0))
			var gap_start := float(current.get("end", 0.0))
			var gap_end := float(next.get("start", 0.0))
			if i == merged.size() - 1:
				gap = float(next.get("start", 0.0)) + FLOW_PERIOD - float(current.get("end", 0.0))
				gap_end += FLOW_PERIOD
			if gap > largest_gap:
				largest_gap = gap
				largest_gap_start = gap_start
				largest_gap_end = gap_end

	var safe_offsets: Array = []
	var failed_offsets: Array = []
	var safe_count := 0
	var failed_count := 0
	for i in range(maxi(1, sample_count)):
		var offset := FLOW_PERIOD * float(i) / float(maxi(1, sample_count))
		if _offset_washes(offset):
			safe_count += 1
			if safe_offsets.size() < 8:
				safe_offsets.append(offset)
		else:
			failed_count += 1
			if failed_offsets.size() < 8:
				failed_offsets.append(offset)

	var safe_sample_offset := -1.0
	if not merged.is_empty():
		var safe_interval: Dictionary = merged[0]
		safe_sample_offset = fposmod(
			(float(safe_interval.get("start", 0.0)) + float(safe_interval.get("end", 0.0))) * 0.5,
			FLOW_PERIOD
		)
	var failed_sample_offset := -1.0
	if largest_gap > 0.0001:
		failed_sample_offset = fposmod((largest_gap_start + largest_gap_end) * 0.5, FLOW_PERIOD)

	return {
		"guaranteed": largest_gap <= 0.0001 and failed_offsets.is_empty(),
		"coverage_gap": maxf(0.0, largest_gap),
		"sample_count": maxi(1, sample_count),
		"safe_sample_offset": safe_sample_offset,
		"failed_sample_offset": failed_sample_offset,
		"safe_sample_count": safe_count,
		"failed_sample_count": failed_count,
		"safe_offsets": safe_offsets,
		"failed_offsets": failed_offsets,
		"safe_window_count": merged.size(),
	}

func _is_active_character_in_patch() -> bool:
	var actor := _get_active_character()
	if actor == "":
		actor = "aster"
	return _get_character_position(actor).distance_to(HIDE_PATCH_POS) <= CONCEAL_PATCH_RADIUS

func _concealment_active() -> bool:
	return _is_active_character_in_patch() and not _detected

func _current_instruction() -> String:
	match _phase:
		"activate":
			return "prime the ferrolure when a safe surge window lines up"
		"window":
			return "watch the bridge and commit only if the wash catches"
		"hide":
			return "hold inside the hush moss until the pack peels back"
		"retry":
			return "re-time the lure for a real flood window"
		"cross":
			return "cross to the goal while the bridge is clear"
		"safe":
			return "the lane is proven"
		"failed":
			return "reset before the pack reacquires you"
		_:
			return "read the cadence"

func _on_lure_interacted() -> void:
	activate_lure()
