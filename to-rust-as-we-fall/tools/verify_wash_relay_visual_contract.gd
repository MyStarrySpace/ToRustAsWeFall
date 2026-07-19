extends Node

## Focused Wash Relay browser-play regression. Boots the real FragmentPreview
## and inspects its existing live follow camera (never a test-only camera).
## Run from the Godot project root:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     --script res://tools/verify_wash_relay_visual_contract.gd

const PREVIEW := preload("res://scenes/fragments/fragment_preview.tscn")
const CAMERA_OFFSET := Vector3(0.0, 6.0, 7.0)
const MIN_ZOOM := 0.8
const MAX_ZOOM := 1.25
const INITIAL_ZOOM := 1.0
const EPS := 0.001

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		failures.append(message)
		push_error("  FAIL: %s" % message)


func _run() -> void:
	EventLog.print_events = false
	print("\n=== Wash Relay visual contract ===")
	var preview := PREVIEW.instantiate()
	preview.set("preview_menu", false)
	preview.set("preview_chunk", "wash_relay")
	preview.set("suppress_scene_change", true)
	get_tree().root.add_child(preview)
	for _frame in range(16):
		await get_tree().process_frame

	var chunk: Node = preview.get("_active_chunk")
	var camera: Camera3D = preview.get("_camera")
	var gs = preview.get("_game_state")
	check(chunk != null, "real Wash Relay chunk boots")
	check(camera != null and camera.is_inside_tree(), "real preview follow camera stays live")
	check(gs != null and gs.coord_map != null, "live preview uses the helix coordinate map")
	if chunk != null and camera != null and gs != null:
		await verify_camera(preview, chunk, camera, gs)
		await verify_guidance(preview, chunk, camera, gs)
		await verify_water(preview, chunk, camera, gs)

	preview.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("\nWASH RELAY VISUAL CONTRACT PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		print("\nWASH RELAY VISUAL CONTRACT FAIL (%d/%d failed)" % [failures.size(), checks])
		get_tree().quit(1)


func verify_camera(preview: Node, chunk: Node, camera: Camera3D, gs) -> void:
	print("\n--- Live follow camera ---")
	check(chunk.has_method("get_preview_camera_profile"), "chunk publishes a local camera profile")
	var profile: Dictionary = chunk.call("get_preview_camera_profile") if \
		chunk.has_method("get_preview_camera_profile") else {}
	check((profile.get("follow_offset", Vector3.ZERO) as Vector3).is_equal_approx(CAMERA_OFFSET),
		"camera profile uses the authored 6 m height")
	check(absf(float(profile.get("min_zoom", -1.0)) - MIN_ZOOM) <= EPS
		and absf(float(profile.get("max_zoom", -1.0)) - MAX_ZOOM) <= EPS
		and absf(float(profile.get("initial_zoom", -1.0)) - INITIAL_ZOOM) <= EPS,
		"camera profile constrains zoom to 0.8..1.25 and starts at 1.0")
	check(bool(profile.get("reset_yaw", false)), "camera profile restores a readable yaw")

	var characters: Dictionary = preview.get("_characters")
	var active_id := str(preview.get("_active_char_id"))
	check(camera.get("target") == characters.get(active_id),
		"unchanged live camera follows the selected character")
	check((camera.get("follow_offset") as Vector3).is_equal_approx(CAMERA_OFFSET)
		and absf(float(camera.get("_view_zoom")) - INITIAL_ZOOM) <= EPS,
		"profile is applied to the live camera instance")

	var camera_id := camera.get_instance_id()
	preview.call("_select_character", "peris")
	await get_tree().process_frame
	camera = preview.get("_camera")
	check(camera.get_instance_id() == camera_id and camera.get("target") == characters.get("peris"),
		"selection retargets the same follow camera")

	for _notch in range(20):
		camera.call("_unhandled_input", zoom_event("camera_zoom_out"))
	var pitch := TAU / ChannelsArc.KTHETA * ChannelsArc.KCLIMB
	var zoom := float(camera.get("_view_zoom"))
	var max_height := (camera.get("follow_offset") as Vector3).y * zoom
	check(absf(zoom - MAX_ZOOM) <= EPS, "wheel zoom-out stops at the chunk maximum")
	check(max_height < pitch - 1.0,
		"maximum camera height stays below the next helix turn (%.2f m < %.2f m)" % [max_height, pitch])
	for _notch in range(20):
		camera.call("_unhandled_input", zoom_event("camera_zoom_in"))
	check(absf(float(camera.get("_view_zoom")) - MIN_ZOOM) <= EPS,
		"wheel zoom-in stops at the chunk minimum")
	if camera.has_method("apply_follow_profile"):
		camera.call("apply_follow_profile", profile, true)
	for _frame in range(6):
		await get_tree().process_frame

	var flat: Vector3 = gs.get_position("peris")
	var points := [
		gs.get_render_position("peris"),
		ChannelsArc.arc_pos(flat.x - 1.5, flat.z),
		ChannelsArc.arc_pos(flat.x + 3.0, flat.z),
		ChannelsArc.arc_pos(flat.x + 1.0, flat.z - 1.5),
		ChannelsArc.arc_pos(flat.x + 1.0, flat.z + 1.5),
	]
	var all_visible := true
	for point in points:
		if not bool(camera.call("is_position_on_screen", point)):
			all_visible = false
			break
	check(all_visible, "active character and nearby deck stay inside the live view")


func verify_water(preview: Node, chunk: Node, _camera: Camera3D, gs) -> void:
	print("\n--- Flood water visibility and reveal ---")
	chunk.call("_update", 0.0)
	chunk.call("_flood_onset", 0)
	chunk.call("_update", 0.0)
	await get_tree().process_frame
	var shown: Array = (chunk.call("get_preview_state") as Dictionary).get("water_shown", [])
	check(not shown.is_empty() and bool(shown[0]), "a live flood still shows section water")

	var sections: Array = chunk.get("_section_water")
	var water: MeshInstance3D = null
	if not sections.is_empty() and not (sections[0] as Array).is_empty():
		water = (sections[0] as Array)[0] as MeshInstance3D
	check(water != null and water.visible, "flood uses a visible warped water surface")
	if water == null:
		return
	var material := water.material_override as ShaderMaterial
	check(material != null and material.shader != null, "flood keeps its authored water shader")
	if material == null or material.shader == null:
		return

	var alpha := float(material.get_shader_parameter("water_alpha"))
	var emission := float(material.get_shader_parameter("emission_strength"))
	var radius := float(material.get_shader_parameter("reveal_radius"))
	var min_factor := float(material.get_shader_parameter("reveal_min_factor"))
	var softness := float(material.get_shader_parameter("reveal_softness"))
	var alpha_floor := float(material.get_shader_parameter("reveal_alpha_floor"))
	var emission_floor := float(material.get_shader_parameter("reveal_emission_floor"))
	var height_cut := float(material.get_shader_parameter("reveal_cut_above_player"))
	check(alpha >= 0.5 and emission >= 1.0, "ordinary water keeps strong alpha and emission")
	check(radius > 0.0 and radius < ChannelsArc.LANE_HALF * 2.0
		and softness > 0.0 and softness <= 2.0,
		"camera reveal is a narrow, softly bounded corridor")
	check(min_factor > 0.0 and min_factor < 1.0
		and alpha_floor > 0.0 and emission_floor > 0.0,
		"overhead water dims but never becomes invisible")
	check(height_cut > 1.0 and height_cut < 3.0,
		"only water meaningfully above the player enters the reveal corridor")
	var player_world: Vector3 = gs.get_render_position(str(preview.get("_active_char_id")))
	check(water.global_position.y <= player_world.y + height_cut,
		"current-turn water stays outside the overhead fade")
	var code := material.shader.code
	check(code.contains("CAMERA_POSITION_WORLD") and code.contains("player_world_pos")
		and code.contains("reveal_cut_above_player"),
		"fade is limited to the live camera/player overhead corridor")
	check(code.contains("reveal_alpha_floor") and code.contains("reveal_emission_floor"),
		"shader retains nonzero blocker-water floors")

	chunk.call("_set_flood_off", 0)
	chunk.call("_update", 0.0)
	shown = (chunk.call("get_preview_state") as Dictionary).get("water_shown", [])
	check(not shown.is_empty() and not bool(shown[0]), "water still hides when the flood ends")


func verify_guidance(preview: Node, chunk: Node, camera: Camera3D, gs) -> void:
	print("\n--- Local objectives and honest affordances ---")
	var state: Dictionary = chunk.call("get_preview_state")
	var guidance: Node = chunk.find_child("SectionGuidance", true, false)
	check(guidance != null, "relay builds guidance beneath a persistent Node3D root")
	check(int(state.get("guidance_count", 0)) == int(state.get("section_count", -1)),
		"every section has exactly one local guidance stage")
	var visible_guides := 0
	if guidance != null:
		for guide in guidance.get_children():
			if guide is Node3D and (guide as Node3D).visible:
				visible_guides += 1
			var objective: Label3D = guide.find_child("Objective", true, false) as Label3D
			var destination: Label3D = guide.find_child("Destination", true, false) as Label3D
			check(objective != null and objective.text.strip_edges() != ""
				and destination != null and destination.text.strip_edges() != "",
				"%s has an objective and a named destination" % guide.name)
	check(visible_guides == 1 and int(state.get("guidance_section", -1)) == 0,
		"spawn presents one opening objective instead of nine simultaneous demands")

	var climb: Node = chunk.find_child("ClimbLine", true, false)
	var rope: MeshInstance3D = chunk.get("_rope_mesh") as MeshInstance3D
	check(climb != null and not bool(climb.call("is_interaction_enabled")) and rope != null and not rope.visible,
		"premature CLIMB click/hover target and rope both begin hidden")
	chunk.call("_on_sloperope")
	check(bool(climb.call("is_interaction_enabled")) and rope.visible,
		"dropping the sloperope reveals and enables CLIMB together")
	chunk.call("reset_preview_state")
	check(not bool(climb.call("is_interaction_enabled")) and not rope.visible,
		"reset cannot leak the early CLIMB affordance back in")

	var sections: Array = state.get("sections", [])
	if sections.size() >= 2:
		var second: Dictionary = sections[1]
		gs.snap_character_to(str(preview.get("_active_char_id")),
			Vector3((float(second["x0"]) + float(second["x1"])) * 0.5, 0.5, 0.0))
		chunk.call("_update", 0.0)
		check(int((chunk.call("get_preview_state") as Dictionary).get("guidance_section", -1)) == 1,
			"guidance advances with the selected character's local section")

	var optional_labels := 0
	for label in chunk.find_children("*", "Label3D", true, false):
		if (label as Label3D).text.contains("OPTIONAL"):
			optional_labels += 1
	check(optional_labels == int(state.get("branch_count", 0)) + 1,
		"every salvage branch and the drain cache explicitly say OPTIONAL")
	check((chunk.get("_causal_feedback_links") as Array).size() >= 3,
		"held overrides reuse the perception-aware cause/effect link system")

	# The true console is farther than the opening camera can frame. Keep its marker honest, and require a local
	# directional cue at the decision point so the player understands what lies beyond the surge before committing.
	var first: Dictionary = sections[0] if not sections.is_empty() else {}
	if not first.is_empty() and guidance != null:
		gs.snap_character_to(str(preview.get("_active_char_id")), Vector3(float(first["x0"]) - 0.3, 0.5, 0.0))
		chunk.call("_update", 0.0)
		for _frame in range(6):
			await get_tree().process_frame
		var opening: Node3D = guidance.get_child(0) as Node3D
		var marker: Node3D = opening.find_child("DestinationMarker", true, false) as Node3D
		var cue: Node3D = opening.find_child("DecisionCue", true, false) as Node3D
		check(cue != null and bool(camera.call("is_position_on_screen", cue.global_position)),
			"opening decision point visibly points toward the off-screen override")
		var expected_marker := ChannelsArc.arc_pos(float(first["x1"]) + 1.5, 0.0)
		var marker_distance := Vector2(marker.position.x, marker.position.z).distance_to(
			Vector2(expected_marker.x, expected_marker.z)) if marker != null else INF
		check(marker != null and marker_distance < 0.05,
			"HOLD marker remains anchored to the real override instead of lying for framing (error %.3f m)" % marker_distance)


func zoom_event(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event
