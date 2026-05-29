extends "res://scripts/scene_chunks/scene_chunk.gd"
# @rendering_only_file: visual setup and pulse animation only.

const FLOOR_CENTER := Vector3(28.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(60.0, 0.1, 18.0)
const ACCESS_PANEL_POS := Vector3(49.0, 0.8, 0.0)
const SAFE_ALCOVE_POS := Vector3(8.0, 0.4, -4.2)
const SAFE_THRESHOLD_X := 11.5
const PURSUER_START_X := 46.0
const CHASE_SPEED := 5.1
const CATCH_RADIUS := 1.45
const PURSUER_OFFSETS := [-1.8, 0.0, 1.8]
const SPAWNS := {
	"aster": Vector3(38.0, 0.5, 0.0),
	"peris": Vector3(35.8, 0.5, 1.5),
	"endo": Vector3(33.6, 0.5, -1.5),
}

var _access_interactable
var _safe_beacon_material: StandardMaterial3D
var _pursuit_markers: Array[MeshInstance3D] = []
var _pursuit_materials: Array[StandardMaterial3D] = []

var _access_denied := false
var _chase_active := false
var _last_outcome := ""
var _chase_time := 0.0

func _build_chunk() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.1, 0.1, 0.12))
	_add_box(self, Vector3(28.0, 2.4, -9.1), Vector3(60.0, 4.8, 0.3), Color(0.13, 0.13, 0.15))
	_add_box(self, Vector3(28.0, 2.4, 9.1), Vector3(60.0, 4.8, 0.3), Color(0.13, 0.13, 0.15))

	for i in range(5):
		var blend := float(i) / 4.0
		_add_light(
			self,
			Vector3(8.0 + float(i) * 10.0, 3.2, 0.0),
			Color(0.34 + blend * 0.34, 0.36 + blend * 0.22, 0.42 + blend * 0.22),
			1.1 + blend * 1.8,
			12.0 + blend * 6.0
		)

	for i in range(6):
		_add_box(
			self,
			Vector3(7.0 + float(i) * 7.2, 0.02, 0.0),
			Vector3(4.0, 0.04, 1.2),
			Color(0.16, 0.14, 0.1),
			Color(0.42, 0.28, 0.16),
			0.2
		)

	_build_safe_alcove()
	_build_boundary_panel()
	_build_pursuit_markers()

func _process(delta: float) -> void:
	_update_chase(delta)

func headless_process(delta: float) -> void:
	_update_chase(delta)

func get_scene_title() -> String:
	return "Lockout Fragment Lab"

func get_scene_help() -> String:
	return "Trip the access panel, get denied, and run Aster back to the maintenance alcove before the sweep catches up."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"access_panel": ACCESS_PANEL_POS,
		"safe_alcove": SAFE_ALCOVE_POS,
		"pursuer_start": Vector3(PURSUER_START_X, 0.5, 0.0),
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 2,
		"time": 0.54,
		"routing_mode": "direct",
		"note_default": "Lockout boots as a boundary-chase slice: trip the access panel, then use run, routing, and the party kit to rehearse the full escape loop.",
	}

func get_preview_abilities() -> Array:
	return [
		{
			"id": "aster_focus",
			"display_name": "BURST",
			"duration": 0.8,
			"cooldown": 4.0,
			"message": "Aster forces a burst window.",
			"note": "Burst buys Aster back a little stamina so the chase lane can be rehearsed repeatedly.",
		},
		{
			"id": "peris_tune",
			"display_name": "LURE",
			"duration": 1.2,
			"cooldown": 5.0,
			"message": "Peris throws the sweep off-beat.",
			"note": "Peris creates just enough noise to make the boundary feel briefly misaligned.",
		},
		{
			"id": "endo_patch",
			"display_name": "BRACE",
			"duration": 0.9,
			"cooldown": 6.0,
			"message": "Endo braces the team for impact.",
			"note": "Brace is a recovery tool for resetting the chase state without leaving the fragment.",
		},
	]

func get_preview_state() -> Dictionary:
	return {
		"access_denied": _access_denied,
		"chase_active": _chase_active,
		"last_outcome": _last_outcome,
		"chase_time": _chase_time,
	}

func reset_preview_state() -> void:
	_access_denied = false
	_chase_active = false
	_last_outcome = ""
	_chase_time = 0.0
	if _access_interactable != null and _access_interactable.has_method("reset"):
		_access_interactable.reset()
	_reset_pursuit_markers()
	_set_safe_beacon(false)

func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	match ability_id:
		"aster_focus":
			return {
				"characters": {
					"aster": {"sta_delta": 20.0},
				},
			}
		"peris_tune":
			return {
				"routing_mode": "safe" if _get_routing_mode() == "direct" else "direct",
				"characters": {
					"peris": {"sta_delta": 10.0},
				},
			}
		"endo_patch":
			return {
				"characters": {
					"aster": {"hp_delta": 10.0},
					"peris": {"hp_delta": 6.0},
					"endo": {"sta_delta": 10.0},
				},
			}
		_:
			return {}

func _build_safe_alcove() -> void:
	_add_box(self, SAFE_ALCOVE_POS + Vector3(0.0, -0.1, 0.0), Vector3(8.0, 0.3, 6.0), Color(0.08, 0.11, 0.1))
	_add_box(self, SAFE_ALCOVE_POS + Vector3(-4.0, 1.6, 0.0), Vector3(0.3, 3.2, 6.0), Color(0.1, 0.13, 0.12))
	_add_box(self, SAFE_ALCOVE_POS + Vector3(0.0, 1.6, -3.0), Vector3(8.0, 3.2, 0.3), Color(0.1, 0.13, 0.12))
	_add_label(self, "MAINTENANCE ALCOVE", SAFE_ALCOVE_POS + Vector3(0.0, 2.3, 0.0), Color(0.78, 0.88, 0.84))
	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.35
	beacon_mesh.height = 0.7
	beacon.mesh = beacon_mesh
	_safe_beacon_material = _make_material(Color(0.2, 0.22, 0.24), Color(0.24, 0.32, 0.36), 0.35)
	beacon.material_override = _safe_beacon_material
	beacon.position = SAFE_ALCOVE_POS + Vector3(0.0, 1.2, 0.0)
	add_child(beacon)

func _build_boundary_panel() -> void:
	_add_box(self, ACCESS_PANEL_POS + Vector3(0.6, 0.0, 0.0), Vector3(0.2, 1.5, 1.0), Color(0.12, 0.15, 0.2), Color(0.14, 0.22, 0.36), 0.75)
	_add_box(self, ACCESS_PANEL_POS + Vector3(2.4, 1.9, 0.0), Vector3(3.6, 3.8, 0.4), Color(0.17, 0.18, 0.22))
	_add_label(self, "LOCKOUT BOUNDARY", ACCESS_PANEL_POS + Vector3(-1.0, 2.5, 0.0))
	_access_interactable = _add_inspection_interactable(
		self,
		"AccessPanelInteractable",
		"Access Panel",
		ACCESS_PANEL_POS + Vector3(-1.0, 0.0, 0.0),
		"ACCESS",
		"aster"
	)
	_access_interactable.interacted.connect(_on_access_interacted)

func _build_pursuit_markers() -> void:
	for i in range(PURSUER_OFFSETS.size()):
		var marker := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.55
		mesh.height = 1.1
		marker.mesh = mesh
		var material := _make_material(Color(0.34, 0.1, 0.1), Color(0.84, 0.2, 0.16), 0.55)
		marker.material_override = material
		marker.position = Vector3(PURSUER_START_X, 0.75, PURSUER_OFFSETS[i])
		add_child(marker)
		_pursuit_markers.append(marker)
		_pursuit_materials.append(material)

func _reset_pursuit_markers() -> void:
	for i in range(_pursuit_markers.size()):
		var marker := _pursuit_markers[i]
		if marker != null:
			marker.position = Vector3(PURSUER_START_X, 0.75, PURSUER_OFFSETS[i])

func _set_safe_beacon(active: bool) -> void:
	if _safe_beacon_material == null:
		return
	if active:
		_safe_beacon_material.albedo_color = Color(0.18, 0.28, 0.2)
		_safe_beacon_material.emission = Color(0.34, 0.8, 0.46)
		_safe_beacon_material.emission_energy_multiplier = 0.9
	else:
		_safe_beacon_material.albedo_color = Color(0.2, 0.22, 0.24)
		_safe_beacon_material.emission = Color(0.24, 0.32, 0.36)
		_safe_beacon_material.emission_energy_multiplier = 0.35

func _on_access_interacted() -> void:
	_access_denied = true
	_last_outcome = "denied"
	_set_preview_step("lockout_denied")
	_clear_dialogue()
	_say("Access denied. Service corridor reserved. Non-service biomass reroute in progress.", "SYSTEM", "data")
	_say("That sounds bad in a very specific way.", "PERIS")
	_say("Run back to the alcove. Now.", "ASTER")
	_start_chase()

func _start_chase() -> void:
	_chase_active = true
	_chase_time = 0.0
	_last_outcome = "running"
	_set_preview_step("lockout_chase")
	_reset_pursuit_markers()
	_set_safe_beacon(false)
	_show_note("Boundary sweep active. Hold Z if you need speed and get Aster back to the alcove.", 4.2)

func _update_chase(delta: float) -> void:
	var pulse := 0.45 + 0.15 * sin(Time.get_ticks_msec() * 0.008)
	for material in _pursuit_materials:
		if material != null:
			material.emission_energy_multiplier = 0.5 + pulse

	if not _chase_active:
		return

	_chase_time += delta
	var aster_position := _get_character_position("aster")
	if aster_position.x <= SAFE_THRESHOLD_X:
		_finish_chase("success")
		return

	for i in range(_pursuit_markers.size()):
		var marker := _pursuit_markers[i]
		if marker == null:
			continue
		marker.position.x -= CHASE_SPEED * delta
		marker.position.z = PURSUER_OFFSETS[i] + sin(_chase_time * 3.0 + float(i)) * 0.5
		var flat_distance := Vector2(marker.global_position.x - aster_position.x, marker.global_position.z - aster_position.z).length()
		if flat_distance <= CATCH_RADIUS:
			_finish_chase("caught")
			return

func _finish_chase(outcome: String) -> void:
	_chase_active = false
	_last_outcome = outcome
	match outcome:
		"success":
			_set_preview_step("lockout_escape")
			_set_safe_beacon(true)
			_clear_dialogue()
			_say("Back across the line. They stop once the corridor stops belonging to anyone important.", "ASTER")
			_show_note("Boundary escape clear. The fragment works when denial turns the polished space into a chase trigger.", 4.5)
		"caught":
			_set_preview_step("lockout_caught")
			_set_safe_beacon(false)
			_clear_dialogue()
			_say("Too slow. The sweep closes the gap before the alcove does.", "", "fragment")
			_show_note("Caught by the sweep. Hit the panel again to retry the boundary escape.", 4.2)
