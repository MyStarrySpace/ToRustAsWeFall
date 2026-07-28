extends SceneTree
## Money shots of the SCAVENGER CARGO BEAT (docs/SCAVENGER_CARGO_BEAT.md): boots the
## real generated-stretch preview on the teaching-channels spec and drives the ACTUAL
## sequence — sluice opens, the scavenger's contact drops the cargo, it departs to the
## lysate source, the cistern current carries the cargo into its bridge seat — capturing
## one frame per causal stage. Party bodies hide; the scavenger is the subject.
##
## NOTE: stages read the generated_stretch chunk's hydraulic internals (phase vars +
## control node names). Those live in the parallel session's in-flight work — if a name
## drifts, this tool fails LOUDLY rather than photographing the wrong thing.
##
##   OUT_DIR=<scratchpad> ../Godot_v4.7-stable_win64.exe --path "." \
##       --position 20000,20000 --resolution 1600x900 --script tools/capture_scavenger_beat.gd

const SPEC := "res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"

var _scene: Node
var _chunk: Node
var _cam: Camera3D
var _out := ""

func _initialize() -> void:
	_out = OS.get_environment("OUT_DIR")
	if _out == "":
		push_error("OUT_DIR not set")
		quit(1)
		return
	var packed = load("res://scenes/fragments/fragment_preview.tscn")
	_scene = packed.instantiate()
	_scene.set("preview_menu", false)
	_scene.set("preview_chunk", "generated_stretch")
	_scene.set("preview_chunk_config", {"spec_path": SPEC})
	get_root().add_child(_scene)
	# generation takes real seconds — poll for the chunk rather than counting frames
	for _i in range(1200):
		await process_frame
		_chunk = _scene.find_child("GeneratedStretchChunk_*", true, false)
		if _chunk == null:
			_chunk = _scene.find_child("Chunk_generated_stretch", true, false)
		if _chunk != null and _i > 40:
			break
	_scene.set("fog_of_war_enabled", false)
	var st = _scene.get("_overlay_states")
	if st is Dictionary:
		for k in (st as Dictionary).keys():
			st[k] = false
		if _scene.has_method("_refresh_active_overlay"):
			_scene.call("_refresh_active_overlay")
	_hide_canvas(_scene)
	_hide_party(_scene)
	RenderingServer.global_shader_parameter_set("player_world_pos", Vector3(0.0, -100000.0, 0.0))
	if _chunk == null:
		var env := _scene.find_child("Environment", true, false)
		if env != null:
			for c in env.get_children():
				print("[BEAT-DBG] env child: %s" % c.name)
		push_error("generated_stretch chunk not found")
		quit(1)
		return
	_cam = Camera3D.new()
	get_root().add_child(_cam)
	_cam.make_current()
	_cam.fov = 50.0

	var cargo: Node3D = _chunk.get("_hydraulic_bridge_cargo")
	var scav: Node3D = _chunk.get("_hydraulic_scavenger")
	var lysate: Node3D = _chunk.get("_hydraulic_lysate_source")
	if cargo == null or scav == null:
		push_error("beat presenters missing (cargo=%s scav=%s)" % [cargo, scav])
		quit(1)
		return

	# STAGE 1 — the setup: cargo elevated on the rack, the scavenger dormant.
	await _shot("beat_1_setup", [cargo, scav])

	# STAGE 2 — the knock-down: sluice opens, contact drops the cargo.
	if not await _trigger("FirstSluiceControl"):
		quit(1)
		return
	await _advance_until(_phase_fallen, 90.0)
	await _shot("beat_2_fall", [cargo, scav])

	# STAGE 3 — the departure: the scavenger leaves for the richer lysate source.
	await _advance_until(_phase_clear, 90.0)
	var lysate_targets: Array = [scav]
	if lysate != null:
		lysate_targets.append(lysate)
	await _shot("beat_3_lysate", lysate_targets)

	# STAGE 4 — the current seats the bridge: release the cistern, cargo floats home.
	if not await _trigger("CisternReleaseControl"):
		quit(1)
		return
	await _advance_until(_bridge_installed, 90.0)
	await _advance(1.0)
	await _shot("beat_4_bridge", [cargo])

	print("[BEAT] done -> %s" % _out)
	quit()

func _phase_fallen() -> bool:
	return str(_chunk.get("_bridge_scavenger_phase")) in ["retreating_to_lysate", "clear"]

func _phase_clear() -> bool:
	return str(_chunk.get("_bridge_scavenger_phase")) == "clear"

func _bridge_installed() -> bool:
	return bool(_chunk.get("_cistern_bridge_installed"))

func _trigger(control_name: String) -> bool:
	var node = _chunk.find_child(control_name, true, false)
	if node == null:
		push_error("control '%s' not found" % control_name)
		return false
	# the kit refuses remote firing — stand the actor at the control's DATA
	# position and name it, exactly as the authority regression does
	var data_pos: Variant = _chunk.call("_generated_interaction_data_position", node)
	if data_pos is Vector3 and _scene.has_method("headless_set_character_position"):
		_scene.call("headless_set_character_position", "aster", data_pos)
		node.set("active_character", "aster")
		await process_frame
		await process_frame
	var ok := bool(node.call("_trigger", false))
	if not ok:
		push_error("control '%s' refused the trigger" % control_name)
	return ok

func _advance(seconds: float) -> void:
	if _scene.has_method("headless_advance"):
		_scene.call("headless_advance", seconds)
	if _chunk.has_method("_update_hydraulic_cargo_sequence"):
		_chunk.call("_update_hydraulic_cargo_sequence", seconds)
	await process_frame

func _advance_until(done: Callable, cap: float) -> void:
	var waited := 0.0
	while waited < cap and not bool(done.call()):
		await _advance(1.0)
		waited += 1.0
		if fmod(waited, 15.0) < 0.5:
			print("[BEAT] ... waiting %.0fs (phase=%s)" % [waited,
				_chunk.get("_bridge_scavenger_phase")])
	if waited >= cap:
		push_warning("beat stage cap hit (%.0fs) — capturing current state honestly" % cap)

func _shot(shot_name: String, targets: Array) -> void:
	var c := Vector3.ZERO
	var n := 0
	for t in targets:
		if t is Node3D and is_instance_valid(t):
			c += (t as Node3D).global_position
			n += 1
	if n > 0:
		c /= float(n)
	_cam.look_at_from_position(c + Vector3(-5.2, 4.6, 5.2), c + Vector3(0, 0.5, 0), Vector3.UP)
	for _j in range(8):
		await process_frame
	_hide_labels(_scene)
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(_out.path_join(shot_name + ".png"))
	img.save_jpg(_out.path_join(shot_name + ".jpg"), 0.88)
	print("[BEAT] %s" % shot_name)

func _hide_labels(n: Node) -> void:
	if n is Label3D:
		(n as Label3D).visible = false
	for c in n.get_children():
		_hide_labels(c)

func _hide_canvas(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_canvas(c)

func _hide_party(n: Node) -> void:
	var scr: Variant = n.get_script()
	if scr != null:
		var path := str(scr.resource_path)
		if path.ends_with("characters/player.gd") or path.ends_with("ai/npc.gd") \
				or path.ends_with("causal_feedback_link.gd"):
			if n is Node3D:
				(n as Node3D).visible = false
			return
	for c in n.get_children():
		_hide_party(c)
