extends "res://scripts/scene_chunks/scene_chunk.gd"

const FloraMemorySystem = preload("res://scripts/game/flora_memory_system.gd")

const LAB_ZONE := "overlay_lab"
const FLOOR_CENTER := Vector3(52.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(104.0, 0.1, 40.0)
const SPAWNS := {
	"aster": Vector3(6.0, 0.5, 0.0),
	"peris": Vector3(4.0, 0.5, 1.8),
	"endo": Vector3(2.0, 0.5, -1.8),
}

const DATA_TERMINAL_A_POS := Vector3(18.0, 0.85, -6.0)
const DATA_TERMINAL_B_POS := Vector3(24.0, 0.85, 4.2)
const DATA_TERMINAL_C_POS := Vector3(30.0, 0.85, -0.8)
const DATA_PORTAL_A_POS := Vector3(36.0, 1.0, -7.4)
const DATA_PORTAL_B_POS := Vector3(42.0, 1.0, 5.4)
const TAG_DAY_LAYOUT_POS := Vector3(24.0, 0.15, 11.0)
const ELEVATOR_LAYOUT_POS := Vector3(38.0, 0.15, 11.0)

const FLORA_WATCH_POS := Vector3(54.0, 0.0, -5.6)
const FLORA_CLIENT_POS := Vector3(59.0, 0.0, 2.8)
const FLORA_CACHE_POS := Vector3(64.0, 0.0, -1.2)
const CLIENT_MEMORY_POS := Vector3(68.0, 0.0, 6.8)
const RELATIONSHIP_TRACE_POS := Vector3(56.0, 0.0, 8.2)
const THREAT_BLUR_A_POS := Vector3(60.0, 0.0, -8.0)
const THREAT_BLUR_B_POS := Vector3(66.0, 0.0, 0.6)

const FOOD_CACHE_POS := Vector3(78.0, 0.55, -6.2)
const FOOD_SHELF_POS := Vector3(84.0, 0.9, -1.8)
const HIDE_SPOT_A_POS := Vector3(78.0, 0.0, 7.0)
const HIDE_SPOT_B_POS := Vector3(86.0, 0.0, 4.8)
const SHELTER_POS := Vector3(94.0, 0.5, 0.0)

var _flora_system := FloraMemorySystem.new()
var _flora_configs: Array[Dictionary] = []
var _last_flora_snapshot := {}
var _last_overlay_states := {
	"aster": false,
	"peris": false,
	"endo": false,
}
var _aster_trace_until := 0.0
var _endo_ping_until := 0.0

var _aster_overlay_root: Node3D
var _peris_overlay_root: Node3D
var _endo_overlay_root: Node3D
var _aster_overlay_materials: Array[StandardMaterial3D] = []
var _peris_status_markers: Dictionary = {}
var _peris_blur_nodes: Dictionary = {}
var _endo_beacon_materials: Dictionary = {}

func _build_chunk() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.05, 0.055, 0.065))
	_add_box(self, Vector3(52.0, 2.1, -20.1), Vector3(104.0, 4.2, 0.3), Color(0.11, 0.12, 0.14))
	_add_box(self, Vector3(52.0, 2.1, 20.1), Vector3(104.0, 4.2, 0.3), Color(0.11, 0.12, 0.14))
	_add_box(self, Vector3(0.1, 2.1, 0.0), Vector3(0.3, 4.2, 40.0), Color(0.11, 0.12, 0.14))
	_add_box(self, Vector3(103.9, 2.1, 0.0), Vector3(0.3, 4.2, 40.0), Color(0.11, 0.12, 0.14))

	for x_pos in [10.0, 26.0, 42.0, 58.0, 74.0, 90.0]:
		_add_light(self, Vector3(x_pos, 4.0, 0.0), Color(0.58, 0.66, 0.78), 1.5, 14.0)

	_add_box(self, Vector3(34.0, 1.2, 0.0), Vector3(0.2, 2.4, 18.0), Color(0.14, 0.16, 0.18))
	_add_box(self, Vector3(70.0, 1.2, 0.0), Vector3(0.2, 2.4, 18.0), Color(0.14, 0.16, 0.18))

	_add_label(self, "ASTER DATA", Vector3(22.0, 2.9, -15.0), Color(0.62, 0.8, 1.0))
	_add_label(self, "PERIS FLORA", Vector3(56.0, 2.9, -15.0), Color(1.0, 0.82, 0.54))
	_add_label(self, "ENDO SURVIVAL", Vector3(86.0, 2.9, -15.0), Color(0.66, 0.92, 0.74))

	_build_data_room()
	_build_flora_room()
	_build_survival_room()
	_build_overlay_roots()
	_reset_flora_system()
	update_preview_overlay_states(_last_overlay_states, 0.0, 0.0)

func get_scene_title() -> String:
	return "Overlay Lab"

func get_scene_help() -> String:
	return "Stack every overlay at once here: Aster reads terminals and ghost layouts, Peris blooms the flora network into memory blurs, and Endo tags food, shelter, and hiding routes."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"data_terminal": DATA_TERMINAL_A_POS,
		"portal": DATA_PORTAL_A_POS,
		"flora": FLORA_WATCH_POS,
		"client_memory": CLIENT_MEMORY_POS,
		"food": FOOD_CACHE_POS,
		"hide_spot": HIDE_SPOT_A_POS,
		"shelter": SHELTER_POS,
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 2,
		"time": 0.44,
		"routing_mode": "safe",
		"note_default": "This lab is built to stack the overlays together. Toggle F1-F3 freely and use Peris's BLOOM to kick the flora network into motion.",
	}

func get_preview_abilities() -> Array:
	return [
		{
			"id": "aster_focus",
			"display_name": "TRACE",
			"duration": 1.1,
			"cooldown": 4.0,
			"message": "Aster spikes the data lattice.",
			"note": "Terminal links, portal IDs, and cached floor ghosts all brighten for a moment.",
		},
		{
			"id": "peris_tune",
			"display_name": "BLOOM",
			"duration": 0.7,
			"cooldown": 6.0,
			"message": "Peris wakes the nearby flora network.",
			"note": "Enemy blurs and client-memory traces ripple outward from the plants she already knows.",
		},
		{
			"id": "endo_patch",
			"display_name": "SCROUNGE",
			"duration": 0.9,
			"cooldown": 5.5,
			"message": "Endo sweeps the room for survival anchors.",
			"note": "Food caches, hiding slots, and the shelter route flare brighter in the survival pass.",
		},
	]

func get_preview_state() -> Dictionary:
	return {
		"overlay_states": _last_overlay_states.duplicate(true),
		"aster_trace_until": _aster_trace_until,
		"endo_ping_until": _endo_ping_until,
		"flora": _flora_system.get_debug_state(_get_scheduler_tick(), LAB_ZONE),
	}

func reset_preview_state() -> void:
	_aster_trace_until = 0.0
	_endo_ping_until = 0.0
	_last_overlay_states = {
		"aster": false,
		"peris": false,
		"endo": false,
	}
	_reset_flora_system()
	update_preview_overlay_states(_last_overlay_states, _get_scheduler_tick(), 0.0)

func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	var current_tick := _get_scheduler_tick()
	match ability_id:
		"aster_focus":
			_aster_trace_until = current_tick + 5.0
			return {}
		"peris_tune":
			var read := _flora_system.start_read("lab_watch_bloom", current_tick)
			if bool(read.get("started", false)):
				var duration := float(read.get("duration", 0.0))
				return {
					"characters": {
						"peris": {"sta_delta": 10.0},
					},
					"message": str(read.get("message", "Peris wakes the flora network.")),
					"note": "The remembered network opens for %.0fs." % duration,
				}
			return {
				"message": "The nearby flora has nothing new to give right now.",
				"note": "Wait for the bloom to settle before you open it again.",
			}
		"endo_patch":
			_endo_ping_until = current_tick + 6.0
			return {
				"characters": {
					"endo": {"sta_delta": 8.0},
					"aster": {"atp_delta": 1.0},
				},
			}
		_:
			return {}

func update_preview_overlay_states(overlay_states: Dictionary, current_tick: float, _delta: float) -> void:
	_last_overlay_states = overlay_states.duplicate(true)

	if _aster_overlay_root != null:
		_aster_overlay_root.visible = bool(overlay_states.get("aster", false))
		_update_aster_overlay(current_tick)

	if _peris_overlay_root != null:
		_peris_overlay_root.visible = bool(overlay_states.get("peris", false))
		_update_peris_overlay(current_tick)

	if _endo_overlay_root != null:
		_endo_overlay_root.visible = bool(overlay_states.get("endo", false))
		_update_endo_overlay(current_tick)

func get_preview_overlay_status(overlay_id: String, current_tick: float) -> Array:
	match overlay_id:
		"aster":
			var trace_remaining := maxf(0.0, _aster_trace_until - current_tick)
			return [
				"Terminals 3  |  Portals 2  |  Layout ghosts 2",
				"Shows IDs, control links, and cached facility slices from Tag Day and the elevator.",
				"Trace spike: %.1fs" % trace_remaining if trace_remaining > 0.0 else "Trace spike: idle",
			]
		"peris":
			var snapshot := _flora_system.get_overlay_snapshot(current_tick, LAB_ZONE)
			var relational: Dictionary = snapshot.get("relational", {})
			var words: Dictionary = snapshot.get("layer_words", {})
			return [
				"Network: %s" % ("OPEN" if bool(snapshot.get("window_active", false)) else "DORMANT"),
				"Read window: %.0fs" % float(snapshot.get("time_remaining", 0.0)),
				"Context %s  |  Direction %s" % [str(words.get("context", "muddled")), str(words.get("direction", "fuzzy"))],
				"Forget-me-nots: %s" % str(relational.get("scent", "none")),
			]
		"endo":
			var ping_remaining := maxf(0.0, _endo_ping_until - current_tick)
			return [
				"Food caches 2  |  Hide slots 2  |  Shelter 1",
				"Flags practical anchors instead of party vitals.",
				"Scrounge ping: %.1fs" % ping_remaining if ping_remaining > 0.0 else "Scrounge ping: idle",
			]
		_:
			return []

func _build_data_room() -> void:
	for x_pos in [14.0, 20.0, 26.0]:
		_add_box(self, Vector3(x_pos, 1.1, -11.0), Vector3(2.0, 2.2, 1.4), Color(0.08, 0.09, 0.11))
		_add_box(self, Vector3(x_pos, 1.1, 11.0), Vector3(2.0, 2.2, 1.4), Color(0.08, 0.09, 0.11))

	_build_terminal(DATA_TERMINAL_A_POS, "TERM-17")
	_build_terminal(DATA_TERMINAL_B_POS, "TERM-24")
	_build_terminal(DATA_TERMINAL_C_POS, "TERM-31")
	_build_portal(DATA_PORTAL_A_POS, "PORTAL-K2")
	_build_portal(DATA_PORTAL_B_POS, "PORTAL-M5")

func _build_flora_room() -> void:
	_add_lab_flora_node(
		"lab_watch_bloom",
		"Watch Bloom",
		FLORA_WATCH_POS,
		"threat",
		"watch drift",
		THREAT_BLUR_A_POS,
		Color(0.76, 0.88, 0.52),
		0.92,
		{"tended": true, "encountered": true}
	)
	_add_lab_flora_node(
		"lab_client_bloom",
		"Client Bloom",
		FLORA_CLIENT_POS,
		"memory",
		"client trace",
		CLIENT_MEMORY_POS,
		Color(0.95, 0.76, 0.44),
		0.88,
		{"tended": true, "encountered": true}
	)
	_add_lab_flora_node(
		"lab_cache_moss",
		"Cache Moss",
		FLORA_CACHE_POS,
		"resource",
		"food trace",
		FOOD_CACHE_POS,
		Color(0.62, 0.88, 0.58),
		0.68,
		{"encountered": true}
	)
	_add_lab_flora_node(
		"lab_forget_me_not",
		"Forget-Me-Not",
		Vector3(56.0, 0.0, 5.8),
		"relationship",
		"Aster",
		RELATIONSHIP_TRACE_POS,
		Color(0.58, 0.74, 0.95),
		1.0,
		{
			"role": "relationship",
			"forget_me_not": true,
			"tended": true,
			"encountered": true,
			"childhood_species": true,
		}
	)

func _build_survival_room() -> void:
	_add_box(self, FOOD_CACHE_POS, Vector3(1.4, 1.0, 1.2), Color(0.22, 0.18, 0.14))
	_add_box(self, FOOD_SHELF_POS, Vector3(1.6, 1.8, 0.8), Color(0.2, 0.19, 0.16))
	_add_box(self, FOOD_SHELF_POS + Vector3(0.0, 0.55, 0.0), Vector3(1.2, 0.08, 0.6), Color(0.26, 0.22, 0.16))
	_add_box(self, FOOD_SHELF_POS + Vector3(-0.25, 0.78, 0.0), Vector3(0.22, 0.36, 0.18), Color(0.36, 0.3, 0.18))
	_add_box(self, FOOD_SHELF_POS + Vector3(0.18, 0.74, 0.08), Vector3(0.18, 0.28, 0.14), Color(0.3, 0.24, 0.16))

	_add_box(self, HIDE_SPOT_A_POS + Vector3(0.0, 0.75, 0.0), Vector3(3.2, 1.5, 0.2), Color(0.16, 0.16, 0.18))
	_add_box(self, HIDE_SPOT_A_POS + Vector3(-1.6, 0.75, 1.4), Vector3(0.2, 1.5, 2.8), Color(0.16, 0.16, 0.18))
	_add_box(self, HIDE_SPOT_B_POS + Vector3(0.0, 0.75, 0.0), Vector3(2.8, 1.5, 0.2), Color(0.16, 0.16, 0.18))
	_add_box(self, HIDE_SPOT_B_POS + Vector3(1.4, 0.75, -1.2), Vector3(0.2, 1.5, 2.4), Color(0.16, 0.16, 0.18))

	_add_box(self, SHELTER_POS + Vector3(0.0, 0.05, 0.0), Vector3(8.0, 0.1, 8.0), Color(0.09, 0.085, 0.08))
	_add_box(self, SHELTER_POS + Vector3(0.0, 1.35, -3.8), Vector3(8.0, 2.7, 0.2), Color(0.18, 0.16, 0.14))
	_add_box(self, SHELTER_POS + Vector3(-3.8, 1.35, 0.0), Vector3(0.2, 2.7, 8.0), Color(0.18, 0.16, 0.14))
	_add_box(self, SHELTER_POS + Vector3(3.8, 1.35, 0.0), Vector3(0.2, 2.7, 8.0), Color(0.18, 0.16, 0.14))
	_add_box(self, SHELTER_POS + Vector3(0.0, 2.75, 0.0), Vector3(8.0, 0.12, 8.0), Color(0.08, 0.08, 0.09))
	_add_light(self, SHELTER_POS + Vector3(0.0, 2.0, 0.0), Color(0.92, 0.72, 0.44), 1.9, 10.0)

func _build_overlay_roots() -> void:
	_aster_overlay_root = Node3D.new()
	_aster_overlay_root.name = "AsterOverlayRoot"
	_aster_overlay_root.visible = false
	add_child(_aster_overlay_root)
	_build_aster_overlay()

	_peris_overlay_root = Node3D.new()
	_peris_overlay_root.name = "PerisOverlayRoot"
	_peris_overlay_root.visible = false
	add_child(_peris_overlay_root)

	_endo_overlay_root = Node3D.new()
	_endo_overlay_root.name = "EndoOverlayRoot"
	_endo_overlay_root.visible = false
	add_child(_endo_overlay_root)
	_build_endo_overlay()

func _build_terminal(position: Vector3, label_text: String) -> void:
	_add_box(self, position, Vector3(2.2, 1.4, 1.2), Color(0.1, 0.12, 0.14))
	_add_box(self, position + Vector3(0.0, 0.92, 0.44), Vector3(1.5, 0.5, 0.08), Color(0.12, 0.16, 0.2), Color(0.18, 0.38, 0.56), 0.72)
	_add_label(self, label_text, position + Vector3(0.0, 2.1, 0.0), Color(0.74, 0.82, 0.92))

func _build_portal(position: Vector3, label_text: String) -> void:
	_add_box(self, position + Vector3(-0.55, 1.3, 0.0), Vector3(0.18, 2.4, 0.18), Color(0.22, 0.2, 0.18))
	_add_box(self, position + Vector3(0.55, 1.3, 0.0), Vector3(0.18, 2.4, 0.18), Color(0.22, 0.2, 0.18))
	_add_box(self, position + Vector3(0.0, 2.42, 0.0), Vector3(1.3, 0.18, 0.18), Color(0.22, 0.2, 0.18))
	_add_box(self, position + Vector3(0.0, 1.25, 0.0), Vector3(0.9, 2.0, 0.08), Color(0.18, 0.16, 0.14), Color(0.82, 0.56, 0.24), 0.45)
	_add_label(self, label_text, position + Vector3(0.0, 3.0, 0.0), Color(0.92, 0.72, 0.48))

func _build_aster_overlay() -> void:
	_add_overlay_label(_aster_overlay_root, "TERM-17", DATA_TERMINAL_A_POS + Vector3(0.0, 2.4, 0.0), Color(0.58, 0.86, 1.0))
	_add_overlay_label(_aster_overlay_root, "TERM-24", DATA_TERMINAL_B_POS + Vector3(0.0, 2.4, 0.0), Color(0.58, 0.86, 1.0))
	_add_overlay_label(_aster_overlay_root, "TERM-31", DATA_TERMINAL_C_POS + Vector3(0.0, 2.4, 0.0), Color(0.58, 0.86, 1.0))
	_add_overlay_label(_aster_overlay_root, "PORTAL-K2", DATA_PORTAL_A_POS + Vector3(0.0, 3.1, 0.0), Color(0.92, 0.72, 0.42))
	_add_overlay_label(_aster_overlay_root, "PORTAL-M5", DATA_PORTAL_B_POS + Vector3(0.0, 3.1, 0.0), Color(0.92, 0.72, 0.42))
	_add_link_overlay(DATA_TERMINAL_A_POS + Vector3(0.0, 1.5, 0.0), DATA_PORTAL_A_POS + Vector3(0.0, 1.5, 0.0), Color(0.58, 0.86, 1.0))
	_add_link_overlay(DATA_TERMINAL_B_POS + Vector3(0.0, 1.5, 0.0), DATA_PORTAL_B_POS + Vector3(0.0, 1.5, 0.0), Color(0.92, 0.72, 0.42))
	_add_link_overlay(DATA_TERMINAL_C_POS + Vector3(0.0, 1.5, 0.0), DATA_PORTAL_A_POS + Vector3(0.0, 1.5, 0.0), Color(0.72, 0.88, 1.0))
	_add_overlay_label(_aster_overlay_root, "LAYOUT GHOST: TAG DAY", TAG_DAY_LAYOUT_POS + Vector3(0.0, 1.8, -0.4), Color(0.54, 0.78, 1.0))
	_add_overlay_label(_aster_overlay_root, "LAYOUT GHOST: ELEVATOR", ELEVATOR_LAYOUT_POS + Vector3(0.0, 1.8, -0.4), Color(0.54, 0.78, 1.0))
	_add_layout_ghost(TAG_DAY_LAYOUT_POS, Vector2(8.0, 5.2), Color(0.48, 0.76, 0.98))
	_add_layout_ghost(ELEVATOR_LAYOUT_POS, Vector2(5.4, 5.4), Color(0.48, 0.76, 0.98))

func _build_endo_overlay() -> void:
	_add_endo_beacon("food_cache", "FOOD CACHE", FOOD_CACHE_POS + Vector3(0.0, 1.8, 0.0), Color(0.76, 0.92, 0.54))
	_add_endo_beacon("food_shelf", "SHELF STOCK", FOOD_SHELF_POS + Vector3(0.0, 1.8, 0.0), Color(0.76, 0.92, 0.54))
	_add_endo_beacon("hide_a", "HIDE SLOT", HIDE_SPOT_A_POS + Vector3(0.0, 1.6, 0.0), Color(0.62, 0.82, 0.96))
	_add_endo_beacon("hide_b", "HIDE SLOT", HIDE_SPOT_B_POS + Vector3(0.0, 1.6, 0.0), Color(0.62, 0.82, 0.96))
	_add_endo_beacon("shelter", "SHELTER", SHELTER_POS + Vector3(0.0, 2.6, 0.0), Color(0.96, 0.8, 0.5))

func _add_lab_flora_node(
	id: String,
	species: String,
	position: Vector3,
	signal_type: String,
	signal_label: String,
	signal_pos: Vector3,
	color: Color,
	relationship_strength: float,
	extra: Dictionary = {}
) -> void:
	var root := Node3D.new()
	root.name = "Flora_%s" % id
	root.position = position
	add_child(root)

	for i in range(3):
		var stem := MeshInstance3D.new()
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.03
		stem_mesh.bottom_radius = 0.05
		stem_mesh.height = 0.42 + float(i) * 0.08
		stem.mesh = stem_mesh
		var stem_mat := StandardMaterial3D.new()
		stem_mat.albedo_color = color.darkened(0.45)
		stem.material_override = stem_mat
		stem.position = Vector3(-0.18 + float(i) * 0.18, 0.2, -0.05 + sin(float(i)) * 0.08)
		root.add_child(stem)

		var bloom := MeshInstance3D.new()
		var bloom_mesh := SphereMesh.new()
		bloom_mesh.radius = 0.11 + float(i) * 0.015
		bloom_mesh.height = 0.22 + float(i) * 0.03
		bloom.mesh = bloom_mesh
		var bloom_mat := StandardMaterial3D.new()
		bloom_mat.albedo_color = color
		bloom_mat.emission_enabled = true
		bloom_mat.emission = color
		bloom_mat.emission_energy_multiplier = 0.25
		bloom.material_override = bloom_mat
		bloom.position = Vector3(-0.18 + float(i) * 0.18, 0.48 + float(i) * 0.09, -0.05 + sin(float(i)) * 0.08)
		root.add_child(bloom)

	var config := {
		"id": id,
		"species": species,
		"zone": LAB_ZONE,
		"position": position,
		"signal_type": signal_type,
		"signal_label": signal_label,
		"signal_pos": signal_pos,
		"relationship_strength": relationship_strength,
		"role": str(extra.get("role", "sensor")),
		"forget_me_not": bool(extra.get("forget_me_not", false)),
		"tended": bool(extra.get("tended", false)),
		"encountered": bool(extra.get("encountered", false)),
		"childhood_species": bool(extra.get("childhood_species", false)),
	}
	_flora_configs.append(config)

func _reset_flora_system() -> void:
	_flora_system = FloraMemorySystem.new()
	_flora_system.set_stage(FloraMemorySystem.Stage.LATE_MID)
	for config in _flora_configs:
		_flora_system.register_node(str(config.get("id", "")), config)
	_last_flora_snapshot = _flora_system.get_overlay_snapshot(_get_scheduler_tick(), LAB_ZONE)

func _update_aster_overlay(current_tick: float) -> void:
	var pulse := 0.4
	if current_tick < _aster_trace_until:
		pulse = 0.75 + 0.2 * sin(current_tick * 8.0)
	for material in _aster_overlay_materials:
		material.emission_energy_multiplier = pulse

func _update_peris_overlay(current_tick: float) -> void:
	for marker_id in _peris_status_markers.keys():
		var marker: Label3D = _peris_status_markers[marker_id]
		if marker != null:
			marker.visible = false
	for blur_id in _peris_blur_nodes.keys():
		var blur: Node3D = _peris_blur_nodes[blur_id]
		if blur != null:
			blur.visible = false

	if _peris_overlay_root == null or not _peris_overlay_root.visible:
		return

	var snapshot := _flora_system.get_overlay_snapshot(current_tick, LAB_ZONE)
	_last_flora_snapshot = snapshot
	var relational: Dictionary = snapshot.get("relational", {})
	var relational_strength := float(relational.get("strength", 0.0))
	if relational_strength > 0.08:
		_place_peris_blur(
			"relational_trace",
			RELATIONSHIP_TRACE_POS,
			Color(0.58, 0.74, 0.95),
			0.2 + relational_strength * 0.45,
			"RELATIONAL TRACE",
			current_tick,
			1.2
		)

	_place_peris_blur(
		"client_memory_static",
		CLIENT_MEMORY_POS,
		Color(0.95, 0.76, 0.44),
		0.32,
		"CLIENT MEMORY",
		current_tick,
		0.8
	)

	for clue_data in snapshot.get("visible_clues", []):
		var clue: Dictionary = clue_data
		var signal_type := str(clue.get("signal_type", "memory"))
		var certainty := float(clue.get("certainty", 0.55))
		var display_pos: Vector3 = clue.get("display_pos", clue.get("source_pos", Vector3.ZERO))
		var signal_label := str(clue.get("signal_label", "")).to_upper()
		if signal_type in ["threat", "hazard", "iron", "memory", "relationship"]:
			_place_peris_blur(
				"clue_%s" % str(clue.get("id", "")),
				display_pos,
				_flora_signal_color(signal_type),
				0.18 + certainty * 0.55,
				signal_label,
				current_tick,
				1.0 if bool(clue.get("fuzzy", false)) else 0.45
			)
		else:
			var marker := _get_peris_status_marker(str(clue.get("id", "")))
			marker.position = display_pos + Vector3(0.0, 2.1, 0.0)
			marker.text = signal_label
			marker.modulate = Color(_flora_signal_color(signal_type), 0.22 + certainty * 0.72)
			marker.visible = true

func _update_endo_overlay(current_tick: float) -> void:
	var highlight := 0.45
	if current_tick < _endo_ping_until:
		highlight = 0.9 + 0.18 * sin(current_tick * 7.0)
	for beacon_id in _endo_beacon_materials.keys():
		var material: StandardMaterial3D = _endo_beacon_materials[beacon_id]
		material.emission_energy_multiplier = highlight

func _add_overlay_label(parent: Node3D, text: String, position: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.pixel_size = 0.009
	label.font_size = 30
	label.modulate = Color(color, 0.88)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.45)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

func _add_link_overlay(from: Vector3, to: Vector3, color: Color) -> void:
	var segment := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, from.distance_to(to))
	segment.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.4
	segment.material_override = material
	segment.position = from.lerp(to, 0.5)
	_aster_overlay_root.add_child(segment)
	segment.look_at_from_position(segment.global_position, to, Vector3.UP)
	segment.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	_aster_overlay_materials.append(material)

func _add_layout_ghost(origin: Vector3, size: Vector2, color: Color) -> void:
	var segments := [
		{"pos": origin + Vector3(0.0, 0.0, -size.y / 2.0), "size": Vector3(size.x, 0.05, 0.08)},
		{"pos": origin + Vector3(0.0, 0.0, size.y / 2.0), "size": Vector3(size.x, 0.05, 0.08)},
		{"pos": origin + Vector3(-size.x / 2.0, 0.0, 0.0), "size": Vector3(0.08, 0.05, size.y)},
		{"pos": origin + Vector3(size.x / 2.0, 0.0, 0.0), "size": Vector3(0.08, 0.05, size.y)},
	]
	for segment_data in segments:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = segment_data["size"]
		mesh.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.4
		mesh.material_override = material
		mesh.position = segment_data["pos"]
		_aster_overlay_root.add_child(mesh)
		_aster_overlay_materials.append(material)

func _get_peris_status_marker(id: String) -> Label3D:
	if _peris_status_markers.has(id):
		return _peris_status_markers[id]
	var marker := Label3D.new()
	marker.name = "PerisStatus_%s" % id
	marker.font_size = 28
	marker.pixel_size = 0.008
	marker.outline_modulate = Color(0.0, 0.0, 0.0, 0.45)
	marker.outline_size = 8
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.visible = false
	_peris_overlay_root.add_child(marker)
	_peris_status_markers[id] = marker
	return marker

func _get_peris_blur_node(id: String) -> Node3D:
	if _peris_blur_nodes.has(id):
		return _peris_blur_nodes[id]
	var root := Node3D.new()
	root.name = "PerisBlur_%s" % id
	root.visible = false

	var mesh := MeshInstance3D.new()
	mesh.name = "BlurMesh"
	var sphere := SphereMesh.new()
	sphere.radius = 0.36
	sphere.height = 0.7
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.8, 0.4, 0.18)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.8, 0.4)
	material.emission_energy_multiplier = 0.45
	mesh.material_override = material
	root.add_child(mesh)

	var label := Label3D.new()
	label.name = "BlurLabel"
	label.position = Vector3(0.0, 0.7, 0.0)
	label.pixel_size = 0.0075
	label.font_size = 24
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.35)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	_peris_overlay_root.add_child(root)
	_peris_blur_nodes[id] = root
	return root

func _place_peris_blur(
	id: String,
	base_position: Vector3,
	color: Color,
	alpha: float,
	label_text: String,
	current_tick: float,
	radius: float
) -> void:
	var root := _get_peris_blur_node(id)
	var offset := _sporadic_offset(id, current_tick, radius)
	root.position = base_position + offset + Vector3(0.0, 1.5, 0.0)
	root.visible = true

	var mesh: MeshInstance3D = root.get_node("BlurMesh")
	var material: StandardMaterial3D = mesh.material_override
	material.albedo_color = Color(color, alpha)
	material.emission = color
	material.emission_energy_multiplier = 0.25 + alpha * 1.1
	mesh.scale = Vector3.ONE * (0.75 + alpha * 0.55)

	var label: Label3D = root.get_node("BlurLabel")
	label.text = label_text
	label.modulate = Color(color.lightened(0.18), 0.08 + alpha * 0.7)

func _sporadic_offset(id: String, current_tick: float, radius: float) -> Vector3:
	var phase := int(floor(current_tick * 1.7))
	var seed: int = abs(int(("%s_%d" % [id, phase]).hash()))
	var x := float(seed % 13) / 12.0 - 0.5
	var z := float((seed / 13) % 13) / 12.0 - 0.5
	var y := 0.08 + 0.12 * sin(current_tick * 3.1 + float(seed % 7))
	return Vector3(x * radius, y, z * radius)

func _add_endo_beacon(id: String, text: String, position: Vector3, color: Color) -> void:
	var beacon := Node3D.new()
	beacon.name = "EndoBeacon_%s" % id
	beacon.position = position
	_endo_overlay_root.add_child(beacon)

	var pillar := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.06
	cylinder.bottom_radius = 0.06
	cylinder.height = 2.0
	pillar.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.45
	pillar.material_override = material
	pillar.position = Vector3(0.0, -0.8, 0.0)
	beacon.add_child(pillar)

	var label := Label3D.new()
	label.text = text
	label.position = Vector3(0.0, 0.5, 0.0)
	label.pixel_size = 0.0085
	label.font_size = 28
	label.modulate = Color(color, 0.9)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.45)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	beacon.add_child(label)

	_endo_beacon_materials[id] = material

func _flora_signal_color(signal_type: String) -> Color:
	match signal_type:
		"threat":
			return Color(0.92, 0.46, 0.32)
		"hazard", "iron":
			return Color(0.94, 0.64, 0.28)
		"resource", "cache":
			return Color(0.56, 0.84, 0.56)
		"relationship":
			return Color(0.6, 0.76, 0.95)
		_:
			return Color(1.0, 0.77, 0.42)
