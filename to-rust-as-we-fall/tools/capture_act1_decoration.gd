extends Node

## Neutral-light capture of an authored Act 1 space after the shared decoration pass.
##
## ACT1_CHUNK=lockout [FOCUS_X=740] [OUT_DIR=<scratch>] Godot --path . \
##   res://tools/capture_act1_decoration.tscn
##
## The output stays outside the project when OUT_DIR is supplied. The script also prints the
## decorator's audit contract so a capture records its batching, instance, light, and clearance cost.

const DEFAULT_FOCUS := {
	"channels": 112.0,
	"stacks": 350.0,
	"rings": 580.0,
	"lockout": 740.0,
	"endo_stretch": 47.0,
	"leaving_facility": 22.0,
}


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	EventLog.print_events = false
	var chunk_id := OS.get_environment("ACT1_CHUNK")
	if not DEFAULT_FOCUS.has(chunk_id):
		chunk_id = "lockout"
	var focus_x := float(DEFAULT_FOCUS[chunk_id])
	if OS.get_environment("FOCUS_X") != "":
		focus_x = float(OS.get_environment("FOCUS_X"))

	var scene_path := "res://scenes/tutorial/act1.tscn"
	if chunk_id == "endo_stretch":
		scene_path = "res://scenes/fragments/chunks/endo_junction_stretch_chunk.tscn"
	elif chunk_id == "leaving_facility":
		scene_path = "res://scenes/tutorial/leaving_facility.tscn"
	var packed := load(scene_path) as PackedScene
	var scene := packed.instantiate()
	if chunk_id not in ["endo_stretch", "leaving_facility"]:
		scene.set("start_chunk", chunk_id)
		scene.set("suppress_scene_change", true)
	# The capture scene's own _ready is still inside SceneTree's child-setup pass.
	await get_tree().process_frame
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame
	EventLog.print_events = false
	for _i in range(89):
		await get_tree().process_frame

	_hide_canvas(scene)
	_hide_named(scene, "PerceptionQuad")
	_hide_named(scene, "FadeRect")
	_hide_interaction_prompts(scene)
	var chunk: Node3D
	if chunk_id == "endo_stretch":
		chunk = scene as Node3D
	elif chunk_id == "leaving_facility":
		chunk = scene.get_node_or_null("Environment") as Node3D
	else:
		chunk = scene.find_child("Chunk_" + chunk_id, true, false) as Node3D
	if chunk == null:
		push_error("Level decoration capture could not find %s" % chunk_id)
		get_tree().quit(1)
		return
	var decoration := chunk.get_node_or_null("LevelDecoration")
	if decoration == null:
		push_error("Level decoration capture found no LevelDecoration in %s" % chunk_id)
		get_tree().quit(1)
		return
	print("[ACT1_DECOR_AUDIT] %s" % JSON.stringify(decoration.get_meta("decoration_audit", {})))

	var camera := Camera3D.new()
	camera.fov = 48.0
	camera.far = 600.0
	get_tree().root.add_child(camera)
	var target := Vector3(focus_x, 1.2, 0.0)
	camera.look_at_from_position(target + Vector3(-12.0, 18.0, 24.0), target, Vector3.UP)
	camera.current = true

	var neutral_environment := Environment.new()
	neutral_environment.background_mode = Environment.BG_COLOR
	neutral_environment.background_color = Color(0.055, 0.06, 0.065)
	neutral_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	neutral_environment.ambient_light_color = Color(0.48, 0.52, 0.54)
	neutral_environment.ambient_light_energy = 0.70
	neutral_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var world_environment := WorldEnvironment.new()
	world_environment.environment = neutral_environment
	get_tree().root.add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	key.light_color = Color(0.72, 0.75, 0.78)
	key.light_energy = 1.15
	key.shadow_enabled = true
	get_tree().root.add_child(key)
	# Give Forward+ shader/material pipelines time to finish after a cold import; otherwise the
	# first capture after changing a shader-backed decoration can be an all-black warm-up frame.
	for _j in range(60):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir == "":
		out_dir = "user://"
	var out_path := out_dir.path_join("act1_%s_x%d.png" % [chunk_id, int(focus_x)])
	var error := get_tree().root.get_texture().get_image().save_png(out_path)
	if error != OK:
		push_error("Could not save Act 1 decoration capture: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("[ACT1_DECOR_CAPTURE] %s" % out_path)
	get_tree().quit()


func _hide_canvas(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_canvas(child)


func _hide_named(node: Node, target_name: String) -> void:
	if node.name == target_name and node is CanvasItem:
		(node as CanvasItem).visible = false
	elif node.name == target_name and node is Node3D:
		(node as Node3D).visible = false
	for child in node.get_children():
		_hide_named(child, target_name)


func _hide_interaction_prompts(node: Node) -> void:
	if node is Label3D and (node as Label3D).text.strip_edges().begins_with("Right-click"):
		(node as Label3D).visible = false
	for child in node.get_children():
		_hide_interaction_prompts(child)
