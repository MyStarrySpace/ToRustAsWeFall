class_name WebInteractionResultFixtureTarget
extends "res://scripts/game/objects/outline_surface_target.gd"

## Adversarial Web-render fixture for the interaction-result observer.
##
## The first successful production interaction still mints the ordinary
## OutlineSurfaceTarget receipt, but this fixture makes only that pulse's own
## material transparent before the renderer can draw it.  The second successful
## interaction is left entirely to the production implementation, which restores
## the canonical success material and advances the presentation serial.

signal fixture_presentation_minted(
	attempt_index: int,
	presentation_serial: int,
	pulse_suppressed: bool,
	production_pulse_restored: bool
)

var _successful_interaction_count := 0


func play_interaction_result(succeeded: bool) -> void:
	super.play_interaction_result(succeeded)
	if not succeeded:
		return

	_successful_interaction_count += 1
	var presentation := get_player_interaction_presentation()
	var presentation_serial := int(presentation.get("presentation_serial", 0))
	var pulse_suppressed := false
	var production_pulse_restored := false

	if _successful_interaction_count == 1:
		# super.play_interaction_result() has already minted the real production
		# result and connected its post-draw lifetime callback.  Suppress only the
		# transient pulse material, synchronously, so no success-colored pixel can
		# reach the first framebuffer for this serial.  Keep the node, receipt, and
		# production timing untouched: the observer must reject it from pixels.
		pulse_suppressed = _suppress_current_pulse_material()
	elif _successful_interaction_count == 2:
		# The production call above reapplies the complete opaque, unshaded,
		# double-sided, depth-tested material contract on every mint. Prove that the
		# second human interaction did not inherit the adversarial transparency.
		production_pulse_restored = _current_pulse_uses_production_success_material()

	fixture_presentation_minted.emit(
		_successful_interaction_count,
		presentation_serial,
		pulse_suppressed,
		production_pulse_restored
	)


func _suppress_current_pulse_material() -> bool:
	if _interaction_pulse_material == null:
		return false
	_interaction_pulse_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var transparent := _interaction_pulse_material.albedo_color
	transparent.a = 0.0
	_interaction_pulse_material.albedo_color = transparent
	_interaction_pulse_material.emission_enabled = false
	_interaction_pulse_material.emission_energy_multiplier = 0.0
	return true


func _current_pulse_uses_production_success_material() -> bool:
	if _interaction_pulse_material == null:
		return false
	return _interaction_pulse_material.shading_mode \
			== BaseMaterial3D.SHADING_MODE_UNSHADED \
		and _interaction_pulse_material.transparency \
			== BaseMaterial3D.TRANSPARENCY_DISABLED \
		and not _interaction_pulse_material.emission_enabled \
		and not _interaction_pulse_material.no_depth_test \
		and _interaction_pulse_material.cull_mode \
			== BaseMaterial3D.CULL_DISABLED \
		and _interaction_pulse_material.albedo_color.a > 0.99 \
		and _interaction_pulse_material.emission.is_equal_approx(
			INTERACTION_SUCCESS_TINT) \
		and is_equal_approx(
			_interaction_pulse_material.emission_energy_multiplier,
			INTERACTION_SUCCESS_EMISSION_ENERGY
		)


## Pure assertion surface for the Web contract.  This deliberately delegates
## presentation and screen-candidate discovery to the production methods; it
## exposes render facts but cannot mint, hide, restore, or otherwise change one.
func get_fixture_pulse_diagnostics() -> Dictionary:
	var diagnostics := get_player_interaction_presentation()
	var pulse_node_visible := _interaction_pulse != null \
		and is_instance_valid(_interaction_pulse) \
		and _interaction_pulse.is_visible_in_tree()
	var pulse_alpha := -1.0
	var pulse_emission_energy := -1.0
	var pulse_transparency := -1
	var pulse_emission_enabled := false
	var pulse_cull_mode := -1
	var pulse_no_depth_test := true
	if _interaction_pulse_material != null:
		pulse_alpha = _interaction_pulse_material.albedo_color.a
		pulse_emission_energy = \
			_interaction_pulse_material.emission_energy_multiplier
		pulse_transparency = _interaction_pulse_material.transparency
		pulse_emission_enabled = _interaction_pulse_material.emission_enabled
		pulse_cull_mode = _interaction_pulse_material.cull_mode
		pulse_no_depth_test = _interaction_pulse_material.no_depth_test

	var pulse_screen_candidate_count := 0
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null and viewport != null:
		pulse_screen_candidate_count = \
			get_player_interaction_presentation_screen_candidates(
				camera, viewport).size()

	diagnostics.merge({
		"pulse_node_visible": pulse_node_visible,
		"pulse_screen_candidate_count": pulse_screen_candidate_count,
		"pulse_alpha": pulse_alpha,
		"pulse_emission_energy": pulse_emission_energy,
		"pulse_transparency": pulse_transparency,
		"pulse_emission_enabled": pulse_emission_enabled,
		"pulse_cull_mode": pulse_cull_mode,
		"pulse_no_depth_test": pulse_no_depth_test,
		"successful_interaction_count": _successful_interaction_count,
	}, true)
	return diagnostics
