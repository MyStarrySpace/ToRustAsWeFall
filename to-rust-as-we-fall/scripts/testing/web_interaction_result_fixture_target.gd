class_name WebInteractionResultFixtureTarget
extends "res://scripts/game/objects/outline_surface_target.gd"

## Adversarial Web-render fixture for the interaction-result observer.
##
## A result rides the object's OWN silhouette: production registers the
## highlight meshes with the scene's OutlineMaskManager at the result tint.
## The first successful production interaction still mints the ordinary
## OutlineSurfaceTarget receipt, but this fixture withdraws that mint's mask
## registration before the renderer can draw it, so no result-tinted
## silhouette pixel exists for the receipt's serial.  The second successful
## interaction is left entirely to the production implementation, whose mint
## re-registers the silhouette at the canonical success tint and advances the
## presentation serial.

signal fixture_presentation_minted(
	attempt_index: int,
	presentation_serial: int,
	pulse_suppressed: bool,
	production_pulse_restored: bool
)

var _successful_interaction_count := 0
var _seam_presented_result := false


## Production's single attestation seam.  The fixture only records the seam's
## own return value as proof that a result really presented on this renderer;
## production keeps every guard and the outline registration.
func _play_interaction_pulse(
		tint: Color, kind: String, presentation_serial := -1
	) -> bool:
	var rendered := super._play_interaction_pulse(tint, kind, presentation_serial)
	if kind in ["success", "rejected"]:
		_seam_presented_result = rendered
	return rendered


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
		# receipt and applied the result tint to this object's outline.  Withdraw
		# only the mask registration, synchronously, so no result-tinted
		# silhouette pixel can reach the first framebuffer for this serial.  The
		# receipt, highlight meshes, and production timing stay untouched: the
		# observer must reject it from pixels.
		pulse_suppressed = _suppress_current_result_mask()
	elif _successful_interaction_count == 2:
		# Every production mint re-registers the silhouette with the scene's
		# outline mask at the result tint.  Prove that the second human
		# interaction did not inherit the adversarial withdrawal.
		production_pulse_restored = _current_result_rides_production_mask()

	fixture_presentation_minted.emit(
		_successful_interaction_count,
		presentation_serial,
		pulse_suppressed,
		production_pulse_restored
	)


func _suppress_current_result_mask() -> bool:
	if not _seam_presented_result or not _outline_active:
		return false
	var manager := _get_mask_manager()
	if manager == null or not manager.is_registered(get_instance_id()):
		return false
	_unregister_mask()
	return true


func _current_result_rides_production_mask() -> bool:
	if not _seam_presented_result or not _outline_active:
		return false
	if not _active_outline_color.is_equal_approx(INTERACTION_SUCCESS_TINT):
		return false
	var manager := _get_mask_manager()
	return manager != null and manager.is_registered(get_instance_id())


## Pure assertion surface for the Web contract.  This deliberately delegates
## presentation and screen-candidate discovery to the production accessors; it
## exposes render facts but cannot mint, hide, restore, or otherwise change one.
func get_fixture_pulse_diagnostics() -> Dictionary:
	var diagnostics := get_player_interaction_presentation()
	var manager := _get_mask_manager()
	var mask_registered := manager != null \
		and manager.is_registered(get_instance_id())

	var result_screen_candidate_count := 0
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null and viewport != null:
		result_screen_candidate_count = \
			get_player_interaction_presentation_screen_candidates(
				camera, viewport).size()

	diagnostics.merge({
		"result_render_node_count":
			get_player_interaction_presentation_render_nodes().size(),
		"result_screen_candidate_count": result_screen_candidate_count,
		"outline_active": has_active_mesh_outline(),
		"mask_registered": mask_registered,
		"outline_color": [
			_active_outline_color.r,
			_active_outline_color.g,
			_active_outline_color.b,
			_active_outline_color.a,
		],
		"outline_color_is_success_tint":
			_active_outline_color.is_equal_approx(INTERACTION_SUCCESS_TINT),
		"seam_presented_result": _seam_presented_result,
		"successful_interaction_count": _successful_interaction_count,
	}, true)
	return diagnostics
