extends "res://scripts/scene_chunks/scene_chunk.gd"
# @rendering_only_file: visual setup and pulse animation only.

const FLOOR_CENTER := Vector3(34.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(72.0, 0.1, 30.0)
const CLIENT_POS := Vector3(14.0, 0.55, -4.5)
const CLIENT_BLOOM_POS := Vector3(12.5, 0.0, -7.2)
const PROPAGATION_POS := Vector3(34.0, 0.0, 8.0)
const FORGET_ME_NOT_POS := Vector3(56.0, 0.0, 10.5)
const SPAWNS := {
	"aster": Vector3(5.0, 0.5, 0.0),
	"peris": Vector3(3.2, 0.5, 1.7),
	"endo": Vector3(1.4, 0.5, -1.7),
}

var _client_interactable
var _propagation_interactable
var _forget_me_not_interactable

var _client_seen := false
var _propagation_seen := false
var _forget_me_not_seen := false
var _last_fragment := ""

var _flora_materials: Array[StandardMaterial3D] = []

func _build_chunk() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.13, 0.11, 0.1))
	_add_box(self, Vector3(34.0, 2.2, -15.2), Vector3(72.0, 4.4, 0.3), Color(0.15, 0.14, 0.12))
	_add_box(self, Vector3(34.0, 2.2, 15.2), Vector3(72.0, 4.4, 0.3), Color(0.17, 0.15, 0.13))

	for i in range(7):
		_add_light(self, Vector3(8.0 + float(i) * 9.0, 3.6, 0.0), Color(0.84, 0.64, 0.42), 2.0, 16.0)

	for i in range(6):
		_add_box(self, Vector3(10.0 + float(i) * 10.0, 1.5, -14.7), Vector3(4.4, 2.0, 0.1), Color(0.16, 0.13, 0.1), Color(0.28, 0.22, 0.14), 0.5)
		_add_box(self, Vector3(14.0 + float(i) * 10.0, 1.3, 14.7), Vector3(1.8, 2.6, 0.1), Color(0.2, 0.17, 0.14))

	_build_client_fragment()
	_build_propagation_fragment()
	_build_forget_me_not_fragment()

func _process(_delta: float) -> void:
	_update_flora_pulse()

func headless_process(_delta: float) -> void:
	_update_flora_pulse()

func get_scene_title() -> String:
	return "Rings Fragment Lab"

func get_scene_help() -> String:
	return "Peris reads the residential rings through the former client, the propagation trail, and the forget-me-not alcove."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"client": CLIENT_POS,
		"client_bloom": CLIENT_BLOOM_POS,
		"propagation": PROPAGATION_POS,
		"forget_me_not": FORGET_ME_NOT_POS,
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 2,
		"time": 0.46,
		"routing_mode": "safe",
		"note_default": "Rings opens as a domestic memory slice: the full party UI is live, but Peris owns the emotional center of this fragment.",
	}

func get_preview_abilities() -> Array:
	return [
		{
			"id": "aster_focus",
			"display_name": "READ",
			"duration": 1.1,
			"cooldown": 4.0,
			"message": "Aster reads the floral trace.",
			"note": "Aster treats the flora like evidence, mapping habit and memory into something legible.",
		},
		{
			"id": "peris_tune",
			"display_name": "TEND",
			"duration": 1.8,
			"cooldown": 5.0,
			"message": "Peris tends the bloom.",
			"note": "Peris coaxes the fragment back toward intimacy instead of surveillance.",
		},
		{
			"id": "endo_patch",
			"display_name": "GRAFT",
			"duration": 1.0,
			"cooldown": 6.0,
			"message": "Endo grafts a steadier footing into the lane.",
			"note": "Endo keeps the party stable enough to linger in the alcoves instead of bouncing out of them.",
		},
	]

func get_preview_state() -> Dictionary:
	return {
		"client_seen": _client_seen,
		"propagation_seen": _propagation_seen,
		"forget_me_not_seen": _forget_me_not_seen,
		"last_fragment": _last_fragment,
	}

func reset_preview_state() -> void:
	_client_seen = false
	_propagation_seen = false
	_forget_me_not_seen = false
	_last_fragment = ""
	for interactable in [_client_interactable, _propagation_interactable, _forget_me_not_interactable]:
		if interactable != null and interactable.has_method("reset"):
			interactable.reset()

func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	match ability_id:
		"peris_tune":
			return {
				"characters": {
					"peris": {"sta_delta": 16.0},
					"aster": {"hp_delta": 4.0},
				},
			}
		"endo_patch":
			return {
				"characters": {
					"endo": {"sta_delta": 12.0},
					"peris": {"hp_delta": 6.0},
				},
			}
		_:
			return {}

func _build_client_fragment() -> void:
	var client_root := Node3D.new()
	client_root.position = CLIENT_POS
	add_child(client_root)
	_add_box(client_root, Vector3.ZERO, Vector3(0.7, 1.5, 0.45), Color(0.18, 0.16, 0.14), Color(0.24, 0.16, 0.1), 0.18)
	_add_label(self, "FORMER CLIENT", CLIENT_POS + Vector3(0.0, 2.2, 0.0))
	_add_flora_cluster(CLIENT_BLOOM_POS, Color(0.94, 0.74, 0.44), 1.0, 4)
	_client_interactable = _add_inspection_interactable(
		self,
		"ClientBloomInteractable",
		"Client Bloom",
		CLIENT_POS + Vector3(0.0, 0.2, 0.0),
		"CALL",
		"peris"
	)
	_client_interactable.interacted.connect(_on_client_interacted)

func _build_propagation_fragment() -> void:
	_add_label(self, "PROPAGATION TRACE", PROPAGATION_POS + Vector3(0.0, 2.5, 0.0))
	for i in range(4):
		_add_flora_cluster(
			PROPAGATION_POS + Vector3(-4.0 + float(i) * 2.6, 0.0, -1.0 + float(i % 2) * 1.2),
			Color(0.78, 0.58, 0.36),
			0.8 + float(i) * 0.08,
			3
		)
	_propogation_doorframe(PROPAGATION_POS + Vector3(0.0, 1.4, 2.2))
	_propagation_interactable = _add_inspection_interactable(
		self,
		"PropagationInteractable",
		"Propagation Trace",
		PROPAGATION_POS + Vector3(0.0, 0.3, 0.0),
		"TRACE",
		"peris"
	)
	_propagation_interactable.interacted.connect(_on_propagation_interacted)

func _build_forget_me_not_fragment() -> void:
	_add_label(self, "FORGET-ME-NOT", FORGET_ME_NOT_POS + Vector3(0.0, 2.6, 0.0), Color(0.76, 0.84, 0.96))
	_add_box(self, FORGET_ME_NOT_POS + Vector3(0.0, 0.25, 0.0), Vector3(7.0, 0.5, 6.0), Color(0.12, 0.11, 0.1))
	_add_flora_cluster(FORGET_ME_NOT_POS + Vector3(-0.8, 0.0, -0.6), Color(0.58, 0.72, 0.95), 1.1, 5)
	_add_flora_cluster(FORGET_ME_NOT_POS + Vector3(1.1, 0.0, 0.9), Color(0.66, 0.78, 0.98), 0.9, 4)
	_forget_me_not_interactable = _add_inspection_interactable(
		self,
		"ForgetMeNotInteractable",
		"Forget-Me-Not",
		FORGET_ME_NOT_POS + Vector3(0.0, 0.3, 0.0),
		"TEND",
		""
	)
	_forget_me_not_interactable.interacted.connect(_on_forget_me_not_interacted)

func _add_flora_cluster(position: Vector3, color: Color, height_scale: float, stems: int) -> void:
	var root := Node3D.new()
	root.position = position
	add_child(root)
	for i in range(stems):
		var stem := MeshInstance3D.new()
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.03
		stem_mesh.bottom_radius = 0.05
		stem_mesh.height = (0.42 + float(i) * 0.08) * height_scale
		stem.mesh = stem_mesh
		stem.material_override = _make_material(color.darkened(0.45))
		stem.position = Vector3(-0.25 + float(i) * 0.14, 0.18 + float(i) * 0.03, -0.1 + sin(float(i)) * 0.08)
		root.add_child(stem)

		var bloom := MeshInstance3D.new()
		var bloom_mesh := SphereMesh.new()
		bloom_mesh.radius = 0.11 + float(i) * 0.012
		bloom_mesh.height = 0.24 + float(i) * 0.03
		bloom.mesh = bloom_mesh
		var bloom_material := _make_material(color, color, 0.42)
		bloom.material_override = bloom_material
		bloom.position = stem.position + Vector3(0.0, 0.3 + float(i) * 0.07, 0.0)
		root.add_child(bloom)
		_flora_materials.append(bloom_material)

func _propogation_doorframe(position: Vector3) -> void:
	_add_box(self, position + Vector3(-2.0, 0.0, 0.0), Vector3(0.3, 2.8, 0.6), Color(0.18, 0.16, 0.14))
	_add_box(self, position + Vector3(2.0, 0.0, 0.0), Vector3(0.3, 2.8, 0.6), Color(0.18, 0.16, 0.14))
	_add_box(self, position + Vector3(0.0, 1.3, 0.0), Vector3(4.3, 0.3, 0.6), Color(0.18, 0.16, 0.14))

func _update_flora_pulse() -> void:
	var pulse := 0.25 + 0.12 * sin(Time.get_ticks_msec() * 0.003)
	for material in _flora_materials:
		if material != null:
			material.emission_energy_multiplier = 0.34 + pulse

func _on_client_interacted() -> void:
	_client_seen = true
	_last_fragment = "client_bloom"
	_set_preview_step("rings_client_bloom")
	_clear_dialogue()
	_say("Hello? ...No answer. Just the bloom still listening.", "PERIS")
	_say("The flora kept the emotional outline of the room after the client left it.", "ASTER", "data")
	_show_note("Client bloom: the plant remembers the relationship even after the person is gone.", 4.0)

func _on_propagation_interacted() -> void:
	_propagation_seen = true
	_last_fragment = "propagation"
	_set_preview_step("rings_propagation")
	_clear_dialogue()
	_say("It spread along the routes people used to take home.", "PERIS")
	_say("Not random growth. It is following habit, warmth, and repeated contact.", "ASTER", "data")
	_show_note("Propagation trace: the flora maps former routines instead of just occupying space.", 4.0)

func _on_forget_me_not_interacted() -> void:
	_forget_me_not_seen = true
	_last_fragment = "forget_me_not"
	_set_preview_step("rings_forget_me_not")
	_clear_dialogue()
	if _get_active_character() == "aster":
		_say("I know this species. I should not know it this fast.", "ASTER")
	else:
		_say("This one remembers before either of us had language for it.", "PERIS")
	_say("The room feels domestic again for half a second, and then it doesn't.", "", "fragment")
	_show_note("Forget-me-not: a small domestic species carrying more intimacy than the architecture can hold.", 4.2)
