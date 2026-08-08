extends "res://scripts/scene_chunks/scene_chunk.gd"

## Web interaction-result render contract.
##
## This is intentionally a playable chunk rather than a test-only state bridge:
## its sole state changes come from a real, repeatable Interactable reached through
## the normal pointer -> route -> arrival -> trigger path.  The exact Capbage-green
## box is an adversarial static background.  A framebuffer observer must reject the
## first success receipt because its transient pulse was hidden, then accept the
## newer second receipt after production restores the pulse material.

const FIXTURE_TARGET_SCRIPT := preload(
	"res://scripts/testing/web_interaction_result_fixture_target.gd")

const CONTRACT_ID := "web_interaction_result_adversarial_v1"
const FIXTURE_POSITION := Vector3(7.0, 0.0, 5.0)
const CAPBAGE_BOX_SIZE := Vector3(1.5, 1.0, 1.5)
const CAPBAGE_ALBEDO := Color(0.16, 0.34, 0.18)
const CAPBAGE_EMISSION := Color(0.3, 0.7, 0.35)
const CAPBAGE_EMISSION_ENERGY := 0.25
const ACKNOWLEDGEMENT_COLOR := Color(0.74, 0.74, 0.74, 1.0)
const SPAWNS := {
	"aster": Vector3(2.5, 0.0, 4.5),
	"peris": Vector3(2.5, 0.0, 5.5),
	"endo": Vector3(3.5, 0.0, 5.0),
}

var _fixture_config: Dictionary = {}
var _fixture_interactable: Interactable = null
var _fixture_target: WebInteractionResultFixtureTarget = null
var _acknowledgement: Label3D = null
var _interaction_count := 0
var _first_result_serial := 0
var _second_result_serial := 0
var _latest_result_serial := 0
var _first_pulse_suppression_applied := false
var _second_pulse_production_restored := false


## Standalone Web contract runners can use the same pre-tree lifecycle in one
## call.  The ordinary preview loader remains compatible through its established
## attach_chunk_host() + configure_chunk() calls.
func setup(config: Dictionary, next_host: Node) -> void:
	attach_chunk_host(
		next_host,
		str(config.get("chunk_name", "result_pulse_web_contract"))
	)
	configure_chunk(config)


func configure_chunk(config: Dictionary) -> void:
	_fixture_config = config.duplicate(true)


func _build_chunk() -> void:
	_add_floor(
		self,
		Vector3(6.0, -0.05, 5.0),
		Vector3(12.0, 0.1, 10.0),
		Color(0.075, 0.08, 0.09)
	)
	_add_label(
		self,
		"TEST RESULT PULSE\nRight-click the Capbage box twice",
		Vector3(6.0, 3.3, 7.6),
		Color(0.78, 0.8, 0.84)
	)
	_build_adversarial_capbage_surface()


func _build_adversarial_capbage_surface() -> void:
	# Match Capbage._build_head exactly.  This permanent green/emissive surface
	# must never satisfy a transient success-pulse framebuffer assertion by itself.
	var head := _add_box(
		self,
		FIXTURE_POSITION + Vector3(0.0, 0.2, 0.0),
		CAPBAGE_BOX_SIZE,
		CAPBAGE_ALBEDO,
		CAPBAGE_EMISSION,
		CAPBAGE_EMISSION_ENERGY,
		"StaticCapbageGreenBox"
	)

	_fixture_interactable = _add_interactable(
		self,
		"WebResultContractInteractable",
		"Exercise the Web interaction-result presentation contract",
		FIXTURE_POSITION,
		"TEST RESULT PULSE",
		"",
		0.0,
		false,
		1.4,
		Interactable.InteractableType.INSPECTION,
		false
	) as Interactable
	_fixture_interactable.consequence_preview = \
		"Acknowledge this repeatable interaction"
	_fixture_interactable.set_meta(
		"web_interaction_result_contract_fixture", true)

	_fixture_target = FIXTURE_TARGET_SCRIPT.new() \
		as WebInteractionResultFixtureTarget
	_fixture_target.name = "WebResultContractSurface"
	_fixture_target.position = FIXTURE_POSITION + Vector3(0.0, 0.2, 0.0)
	_fixture_target.outline_highlight_radius = 1.4
	_fixture_target.outline_highlight_extents = CAPBAGE_BOX_SIZE * 0.5
	_fixture_target.outline_highlight_height = 0.0
	_fixture_target.set_meta("room_element_id", CONTRACT_ID)
	_fixture_target.set_meta("web_interaction_result_contract_fixture", true)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = CAPBAGE_BOX_SIZE + Vector3.ONE * 0.24
	collision.shape = shape
	_fixture_target.add_child(collision)
	add_child(_fixture_target)
	_fixture_target.register_highlight_mesh(head)
	_fixture_target.set_interaction_delegate(_fixture_interactable)
	_fixture_interactable.set_outline_target(_fixture_target)
	_fixture_target.fixture_presentation_minted.connect(
		_on_fixture_presentation_minted)

	_acknowledgement = _add_label(
		self,
		"",
		FIXTURE_POSITION + Vector3(0.0, 2.0, 0.0),
		ACKNOWLEDGEMENT_COLOR
	)
	_acknowledgement.name = "NeutralInteractionAcknowledgement"
	_acknowledgement.visible = false


func _on_fixture_presentation_minted(
	attempt_index: int,
	presentation_serial: int,
	pulse_suppressed: bool,
	production_pulse_restored: bool
) -> void:
	_interaction_count = attempt_index
	_latest_result_serial = presentation_serial
	if attempt_index == 1:
		_first_result_serial = presentation_serial
		_first_pulse_suppression_applied = pulse_suppressed
		_show_neutral_acknowledgement(
			"CONTROL RECEIVED — CLICK AGAIN FOR VISIBLE PULSE")
	elif attempt_index == 2:
		_second_result_serial = presentation_serial
		_second_pulse_production_restored = production_pulse_restored
		_show_neutral_acknowledgement(
			"ACKNOWLEDGED\nproduction result pulse restored")
	else:
		_show_neutral_acknowledgement(
			"ACKNOWLEDGED\nproduction result pulse active")


func _show_neutral_acknowledgement(message: String) -> void:
	if _acknowledgement == null:
		return
	_acknowledgement.text = message
	_acknowledgement.modulate = ACKNOWLEDGEMENT_COLOR
	_acknowledgement.visible = true
	# Mirror the same neutral acknowledgement into the ordinary preview-note
	# presenter. This keeps it legible to a human at any camera angle and puts it
	# on the exact player-observation surface used by browser players, without
	# introducing a test-only observation seam.
	_show_note(message, 6.0)


func get_scene_title() -> String:
	return "Web Interaction Result Contract"


func get_scene_help() -> String:
	return "Right-click the Capbage-green box twice. The first real interaction has only a neutral acknowledgement; the second restores the normal production success pulse."


func get_default_character() -> String:
	return "aster"


func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()


func get_preview_anchors() -> Dictionary:
	return {
		"interaction_result_fixture": FIXTURE_POSITION,
	}


func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": 13,
		"height": 11,
		"walkable_regions": [
			{"min": [0.5, 0.5], "max": [11.5, 9.5]},
		],
	}


## Assertion-only diagnostics.  There is deliberately no trigger, teleport,
## direct-state mutation, or synthetic-input method on this fixture.
func get_preview_state() -> Dictionary:
	var current_presentation := {
		"presentation_serial": 0,
		"result": "",
		"visible": false,
	}
	var pulse_diagnostics := {
		"presentation_serial": 0,
		"result": "",
		"visible": false,
		"result_render_node_count": 0,
		"result_screen_candidate_count": 0,
		"outline_active": false,
		"mask_registered": false,
		"outline_color": [0.0, 0.0, 0.0, 0.0],
		"outline_color_is_success_tint": false,
		"seam_presented_result": false,
		"successful_interaction_count": 0,
	}
	if _fixture_target != null and is_instance_valid(_fixture_target):
		current_presentation = \
			_fixture_target.get_player_interaction_presentation()
		pulse_diagnostics = \
			_fixture_target.get_fixture_pulse_diagnostics()
	return {
		"contract_id": CONTRACT_ID,
		"interaction_count": _interaction_count,
		"first_result_serial": _first_result_serial,
		"second_result_serial": _second_result_serial,
		"latest_result_serial": _latest_result_serial,
		"first_pulse_suppression_applied": \
			_first_pulse_suppression_applied,
		"second_pulse_production_restored": \
			_second_pulse_production_restored,
		"second_serial_is_newer": _second_result_serial > _first_result_serial,
		"acknowledgement_visible": _acknowledgement != null \
			and _acknowledgement.visible,
		"acknowledgement_color": [
			ACKNOWLEDGEMENT_COLOR.r,
			ACKNOWLEDGEMENT_COLOR.g,
			ACKNOWLEDGEMENT_COLOR.b,
			ACKNOWLEDGEMENT_COLOR.a,
		],
		"static_capbage_box": {
			"size": [CAPBAGE_BOX_SIZE.x, CAPBAGE_BOX_SIZE.y, CAPBAGE_BOX_SIZE.z],
			"albedo": [CAPBAGE_ALBEDO.r, CAPBAGE_ALBEDO.g, CAPBAGE_ALBEDO.b],
			"emission": [
				CAPBAGE_EMISSION.r,
				CAPBAGE_EMISSION.g,
				CAPBAGE_EMISSION.b,
			],
			"emission_energy": CAPBAGE_EMISSION_ENERGY,
		},
		"current_presentation": current_presentation.duplicate(true),
		"pulse_diagnostics": pulse_diagnostics.duplicate(true),
		"config": _fixture_config.duplicate(true),
	}
