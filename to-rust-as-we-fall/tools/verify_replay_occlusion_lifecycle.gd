extends SceneTree

## Focused regression for deterministic movie presentation. Run with:
##   godot --headless --path . --script res://tools/verify_replay_occlusion_lifecycle.gd

const GeneratedInputDriverScript := preload(
	"res://tools/generated_input_playthrough_driver.gd"
)

var _checks := 0
var _failures := 0


class CameraTargetFixture extends Node:
	var target: Node3D


class RecordingOcclusionManager extends CameraOcclusionManager:
	var published_watch := Vector3.INF

	func sync_now() -> void:
		published_watch = _watch_pos()


class PreviewFocusFixture extends Node:
	var active_character := "peris"
	var _characters: Dictionary = {}
	var _camera: CameraTargetFixture
	var _occlusion_mgr: CameraOcclusionManager

	func get_preview_active_character() -> String:
		return active_character


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager := RecordingOcclusionManager.new()
	root.add_child(manager)
	var scheduler := EventScheduler.new()
	var game_state := GameState.new()
	game_state.scheduler = scheduler
	game_state.register_character("aster", Vector3(1.0, 0.0, 2.0), 3.0, {})
	game_state.register_character("peris", Vector3(9.0, 0.0, -3.0), 3.0, {})
	manager.set_watch(game_state, "aster")
	check(manager._watch_pos().distance_to(Vector3(1.0, 0.0, 2.0)) < 0.001,
		"occlusion initially follows the generated-playthrough lead")
	manager.set_watch(game_state, "peris")
	check(manager._watch_pos().distance_to(Vector3(9.0, 0.0, -3.0)) < 0.001,
		"autonomous focus switch updates the watched character immediately")
	check(manager.published_watch.distance_to(Vector3(9.0, 0.0, -3.0)) < 0.001,
		"focus switch publishes Peris to the occlusion shader in the same frame")
	var hydraulic_driver: Node = GeneratedInputDriverScript.new()
	hydraulic_driver.set("case_id", "teaching_channels_spiral")
	check(str(hydraulic_driver.call("_preferred_active_character")) == "peris",
		"autonomous hydraulic play selects its actual Peris actor as camera lead")
	var focus_fixture := PreviewFocusFixture.new()
	var aster_node := Node3D.new()
	var peris_node := Node3D.new()
	focus_fixture.add_child(aster_node)
	focus_fixture.add_child(peris_node)
	focus_fixture._characters = {"aster": aster_node, "peris": peris_node}
	focus_fixture._camera = CameraTargetFixture.new()
	focus_fixture.add_child(focus_fixture._camera)
	focus_fixture._camera.target = peris_node
	focus_fixture._occlusion_mgr = manager
	check(bool(hydraulic_driver.call(
		"_autonomous_focus_matches", focus_fixture, "peris"
	)), "autonomous focus contract covers both Peris camera target and occlusion watch")
	focus_fixture._camera.target = aster_node
	check(not bool(hydraulic_driver.call(
		"_autonomous_focus_matches", focus_fixture, "peris"
	)), "focus regression detects a camera that drifts back to Aster")
	focus_fixture._camera.target = peris_node
	focus_fixture._occlusion_mgr = null
	check(not bool(hydraulic_driver.call(
		"_autonomous_focus_matches", focus_fixture, "peris"
	)), "focus regression detects a missing see-through shader manager")
	focus_fixture.free()
	hydraulic_driver.free()

	var visual_root := Node3D.new()
	visual_root.set_meta("camera_occlusion_outline_safe_clip", true)
	root.add_child(visual_root)
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(2.0, 4.0, 0.4)
	wall.mesh = wall_mesh
	wall.material_override = standard_material(Color(0.16, 0.32, 0.48))
	visual_root.add_child(wall)

	var effect := MeshInstance3D.new()
	var effect_mesh := BoxMesh.new()
	effect_mesh.size = Vector3(2.0, 4.0, 0.4)
	effect.mesh = effect_mesh
	var effect_shader := Shader.new()
	effect_shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(0.1, 0.4, 0.8); }"
	var authored_effect := ShaderMaterial.new()
	authored_effect.shader = effect_shader
	effect.material_override = authored_effect
	visual_root.add_child(effect)

	check(manager.apply_to(visual_root, 2.0) == 1
			and is_occlusion_material(wall.material_override, manager),
		"initial preview load wraps its tall StandardMaterial occluder")
	check(effect.material_override == authored_effect,
		"authored water/fog/effect ShaderMaterial is never replaced")
	var tracked_before := manager.tracked_geometry_count()
	check(tracked_before == 1,
		"authored effect geometry is excluded from the runtime wrapper watchlist")
	check(manager.apply_to(visual_root, 2.0) == 0
			and manager.tracked_geometry_count() == tracked_before,
		"repeated wrapper scan is idempotent")

	var reset_color := Color(0.42, 0.25, 0.12)
	wall.material_override = standard_material(reset_color)
	check(manager.apply_to(visual_root, 2.0) == 1
			and wrapped_color(wall).is_equal_approx(reset_color),
		"post-reset preview scan restores wrapper and reset material state")

	var runtime_color := Color(0.22, 0.64, 0.31)
	wall.material_override = standard_material(runtime_color)
	manager._process(0.0)
	check(is_occlusion_material(wall.material_override, manager)
			and wrapped_color(wall).is_equal_approx(runtime_color),
		"runtime material replacement is automatically re-wrapped")
	manager._process(0.0)
	check(is_occlusion_material(wall.material_override, manager)
			and effect.material_override == authored_effect,
		"runtime refresh stays idempotent and preserves authored effects")

	visual_root.queue_free()
	manager.queue_free()
	await process_frame
	print("REPLAY OCCLUSION LIFECYCLE: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func standard_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


func is_occlusion_material(material: Material, manager: CameraOcclusionManager) -> bool:
	return material is ShaderMaterial \
		and (material as ShaderMaterial).shader == manager.OCCLUSION_SHADER


func wrapped_color(mesh: MeshInstance3D) -> Color:
	if not mesh.material_override is ShaderMaterial:
		return Color.TRANSPARENT
	var color: Variant = (mesh.material_override as ShaderMaterial).get_shader_parameter("albedo_color")
	return color as Color if color is Color else Color.TRANSPARENT


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % label)
	else:
		_failures += 1
		push_error("  FAIL: %s" % label)
