extends SceneTree
## MOVIE DRIVER: plays the canonical wash_ascent solve in REAL TIME for
## Godot's movie-maker mode. No headless_advance — the scene's own _process
## advances the clock, and every awaited frame is one written movie frame,
## so the recording is deterministic at the fixed fps.
##
##   ../Godot_v4.7-stable_win64_console.exe --path "." \
##       --write-movie <out.avi> --fixed-fps 30 --resolution 1280x720 \
##       --script tools/record_playthrough.gd
##
## The route is the pacing probe's canonical solve (stage at each mouth,
## launch on the flood->dry transition, hold each span's taught lane), plus
## the first-shelter rest beat, ending on the ring completion.

const FPS := 30.0

var _scene: Node
var _chunk: Node
var _gs
var _cam: Camera3D

## The recording's own CHASE CAMERA: the default follow camera's offset is
## world-fixed, so on half the coil it sits INSIDE the drum staring at the
## shell. A player orbits out of that with Q/E; the chase cam keeps the
## outside-in angle automatically — party centroid pushed radially out from
## the helix axis, eased per frame.
var _label_sweep := 0

# --- NARRATION (director: the automated system announces its decision
# --- making). Each beat gets one caption: burned into the frame live, and
# --- collected with video timestamps so an .srt subtitle file is written
# --- next to the movie (CAPTIONS_OUT env) for post-editing or re-burning.
var _caption_label: Label
var _caption_panel: PanelContainer
var _captions: Array = []
var _caption_hide_frame := -1

func _build_caption_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	get_root().add_child(layer)
	_caption_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.72)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	_caption_panel.add_theme_stylebox_override("panel", style)
	_caption_panel.anchor_left = 0.5
	_caption_panel.anchor_right = 0.5
	_caption_panel.anchor_top = 1.0
	_caption_panel.anchor_bottom = 1.0
	_caption_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption_panel.offset_bottom = -132.0
	_caption_label = Label.new()
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.custom_minimum_size = Vector2(0, 0)
	_caption_label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.92))
	_caption_label.add_theme_font_size_override("font_size", 19)
	_caption_panel.add_child(_caption_label)
	_caption_panel.visible = false
	layer.add_child(_caption_panel)

func _narrate(text: String) -> void:
	if _caption_label != null:
		_caption_label.text = text
		_caption_label.custom_minimum_size = Vector2(minf(880.0, 24.0 + text.length() * 9.2), 0)
		_caption_panel.visible = true
	_caption_hide_frame = _label_sweep + int(maxf(3.4, 0.055 * float(text.length())) * FPS)
	_captions.append({"t": float(_label_sweep) / FPS, "text": text})
	print("[REC] NARRATE %s" % text)

func _write_captions_srt() -> void:
	var out := OS.get_environment("CAPTIONS_OUT")
	if out == "" or _captions.is_empty():
		return
	var srt := ""
	for i in range(_captions.size()):
		var t0 := float(_captions[i]["t"])
		var t1 := t0 + maxf(3.4, 0.055 * float(str(_captions[i]["text"]).length()))
		if i + 1 < _captions.size():
			t1 = minf(t1, float(_captions[i + 1]["t"]) - 0.05)
		srt += "%d\n%s --> %s\n%s\n\n" % [i + 1, _srt_time(t0), _srt_time(t1),
			str(_captions[i]["text"])]
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f != null:
		f.store_string(srt)
		print("[REC] captions -> %s" % out)

func _srt_time(t: float) -> String:
	var ms := int(round(t * 1000.0))
	return "%02d:%02d:%02d,%03d" % [ms / 3600000, (ms / 60000) % 60, (ms / 1000) % 60, ms % 1000]

## Telemetry: the movie renders blind in the background, so the run narrates
## itself — a line per stage plus a 10-second heartbeat. Diagnosis reads the
## log next to the footage instead of spelunking stills.
func _log(tag: String) -> void:
	if _gs == null:
		return
	var parts := []
	for id in ["aster", "peris", "endo"]:
		if _gs.characters.has(id):
			var p: Vector3 = _gs.get_position(id)
			parts.append("%s(%.1f,%.1f hp%.0f)" % [id, p.x, p.z, float(_gs.get_stat(id, "hp"))])
	for eid in ["sapscrap_0", "sapscrap_1", "sapscrap_2", "sapscrap_3"]:
		if _gs.characters.has(eid):
			var ep: Vector3 = _gs.get_position(eid)
			var foe = _chunk.call("_fauna_by_id", eid)
			parts.append("%s(%.1f,%.1f %s)" % [eid.replace("sapscrap_", "ss"), ep.x, ep.z,
				str(foe.call("get_state")) if foe != null else "?"])
	print("[REC] t=%.1f %-18s %s" % [
		float(_gs.scheduler.get_current_tick()) if _gs.scheduler != null else -1.0,
		tag, " ".join(parts)])

## The interactable verb labels float over half the frame — hide them, keep
## the single-word character name tags. Swept periodically because verbs
## spawn with new stages.
func _hide_verb_labels(n: Node) -> void:
	if n is Label3D and " " in str((n as Label3D).text):
		(n as Label3D).visible = false
	for c in n.get_children():
		_hide_verb_labels(c)

func _cam_update() -> void:
	_label_sweep += 1
	if _label_sweep % 90 == 1:
		_hide_verb_labels(get_root())
	if _caption_panel != null and _caption_hide_frame >= 0 and _label_sweep > _caption_hide_frame:
		_caption_panel.visible = false
		_caption_hide_frame = -1
	if _label_sweep % 300 == 5:
		_log("heartbeat")
	if _gs != null and _label_sweep % 60 == 3:
		for id_hp in ["aster", "peris", "endo"]:
			if _gs.characters.has(id_hp) and float(_gs.get_stat(id_hp, "hp")) <= 0.0:
				_log("DOWNED-ABORT " + id_hp)
				quit(1)
				return
	# watchdog: the movie must never sit paused — if a stray toggle slips
	# through anyway, unpause through the proper path
	if _scene != null and _label_sweep % 30 == 2:
		var sched = _scene.get("_scheduler")
		if sched != null and bool(sched.is_paused()) \
				and _scene.has_method("_on_pause_toggled"):
			_scene.call("_on_pause_toggled", false)
	if _cam == null or _gs == null:
		return
	var ids := ["aster", "peris", "endo"]
	var centroid := Vector3.ZERO
	var n := 0
	for id in ids:
		if _gs.characters.has(id):
			centroid += _gs.get_render_position(id) as Vector3
			n += 1
	if n == 0:
		return
	centroid /= float(n)
	var out := Vector3(centroid.x, 0.0, centroid.z)
	out = out.normalized() if out.length() > 0.5 else Vector3.RIGHT
	var want: Vector3 = centroid + out * 9.5 + Vector3(0, 4.6, 0)
	_cam.global_position = _cam.global_position.lerp(want, 0.06)
	var look: Vector3 = centroid + Vector3(0, 0.6, 0)
	if _cam.global_position.distance_to(look) > 0.5:
		_cam.look_at(look, Vector3.UP)

func _wait_s(secs: float) -> void:
	for _i in range(int(secs * FPS)):
		_cam_update()
		await process_frame

func _wait_cond(cond: Callable, cap_s: float) -> void:
	for _i in range(int(cap_s * FPS)):
		if bool(cond.call()):
			return
		_cam_update()
		await process_frame

func _move_all(targets: Dictionary, cap := 30.0) -> void:
	for id in targets:
		_gs.command_move_to_pos(str(id), targets[id])
	await _wait_cond(func():
		for id in targets:
			if bool(_gs.is_moving(str(id))):
				return false
			if _gs.get_position(str(id)).distance_to(targets[id] as Vector3) > 1.8:
				return false
		return true, cap)

func _click(node_name: String, walker := "aster", walk_to := Vector3.INF) -> void:
	var obj = _chunk.find_child(node_name, true, false)
	if obj == null:
		return
	if walk_to != Vector3.INF:
		_gs.command_move_to_pos(walker, walk_to)
		await _wait_cond(func(): return not bool(_gs.is_moving(walker)), 12.0)
	obj.set("active_character", walker)
	await process_frame
	obj.call("_trigger")

## One ladder leg: stage at the mouth, launch on the flood->dry transition.
func _cross_section(idx: int, mouth_x: float, dest_x: float, need: float,
		mouth_z := 0.9, speed := -1.0, dest_z := 0.9, row_pitch := 1.2,
		stage := true, note := "") -> void:
	if note != "":
		_narrate(note)
	var channels: Array = _chunk.get("_channels")
	var ids := ["aster", "peris", "endo"]
	# staging spreads on X as well as Z: three targets in one x-column share
	# grid cells, and the cooperative planner shoves the overlap z-ward —
	# straight into a watch (the patroller took aster at the S4 mouth this
	# way; the roamer took two on the S8 march). A leg whose PREVIOUS beat
	# already parked the party at the mouth passes stage=false: even a
	# careful re-stage walk can be detoured by its own crossing traffic.
	if stage:
		var tm: Dictionary = {}
		for k in range(3):
			tm[ids[k]] = Vector3(mouth_x + float(k - 1) * 0.9, 0.1, mouth_z + row_pitch * float(k))
		await _move_all(tm, 26.0)
	var st := {"saw": false}
	var ch = channels[idx]
	await _wait_cond(func():
		if bool(ch.call("is_flooding")):
			st["saw"] = true
			return false
		if not bool(st["saw"]):
			return false
		var on: Array = (_chunk.call("get_preview_state") as Dictionary).get("next_onsets_in", [])
		return on.size() > idx and float(on[idx]) > need, 26.0)
	if speed > 0.0:
		for id_s in ids:
			_gs.change_move_speed(str(id_s), speed)
	var td: Dictionary = {}
	for k2 in range(3):
		td[ids[k2]] = Vector3(dest_x + float(k2 - 1) * 0.9, 0.1, dest_z + row_pitch * float(k2))
	await _move_all(td, 26.0)
	if speed > 0.0:
		_gs.change_move_speed("aster", 3.2)
		_gs.change_move_speed("peris", 2.8)
		_gs.change_move_speed("endo", 2.8)
	_log("crossed-s%d" % idx)

func _initialize() -> void:
	# The recording window must NEVER take keyboard focus: it parks off-screen
	# but still grabs focus on open, and anything typed at the desktop while
	# the movie renders lands in the game (a spacebar = the pause action —
	# one recording froze at its spawn for nine minutes this way). And it
	# must be parked at runtime — the --position flag is clamped against
	# wide/multi-monitor desktops and leaves a sliver visible.
	get_root().unfocusable = true
	OffscreenWindow.park(get_root())
	var packed = load("res://scenes/fragments/fragment_preview.tscn")
	_scene = packed.instantiate()
	_scene.set("preview_menu", false)
	_scene.set("preview_chunk", "wash_ascent")
	get_root().add_child(_scene)
	for _i in range(10):
		await process_frame
	_chunk = _scene.find_child("Chunk_wash_ascent", true, false)
	_gs = _scene.get("_game_state")
	if _gs != null and _gs.has_signal("detection_predicted"):
		_gs.detection_predicted.connect(func(det, tgt):
			var dp: Vector3 = _gs.get_position(str(det))
			var tp: Vector3 = _gs.get_position(str(tgt))
			print("[REC] DETECTED %s -> %s det(%.1f,%.1f) tgt(%.1f,%.1f) dist=%.2f" % [
				str(det), str(tgt), dp.x, dp.z, tp.x, tp.z,
				Vector2(dp.x - tp.x, dp.z - tp.z).length()]))
	var channels: Array = _chunk.get("_channels")
	var ids := ["aster", "peris", "endo"]
	# a player's first act: select the party — this is what aims the camera,
	# centres the fog watch, and sets the active character
	_scene.call("headless_set_selected_characters", ["aster", "peris", "endo"])
	# the fog mask doesn't update under the movie-mode main loop (the same
	# family as the headless vision-upload skip), so the recording plays with
	# fog off — like every capture tool
	_scene.set("fog_of_war_enabled", false)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	get_root().add_child(_cam)
	_cam.make_current()
	var boot_pos: Vector3 = _gs.get_render_position("aster")
	_cam.global_position = boot_pos + Vector3(boot_pos.x, 0, boot_pos.z).normalized() * 9.5 \
		+ Vector3(0, 4.6, 0)
	_cam_update()
	_build_caption_ui()
	_narrate("Automated canonical solve. The party enters on the span above the summit — then the bridge gives way.")
	# tuck the diagnostic chrome a viewer doesn't need (H/F4, the showcase
	# presentation contract's own switches)
	var im = _scene.get("_instructions_margin")
	if im != null:
		(im as CanvasItem).visible = false
	if _scene.has_method("_set_overlay_panel_collapsed"):
		_scene.call("_set_overlay_panel_collapsed", true)
	# the party-select stacks all three PERCEPTION overlays — the recording
	# wants the painted level, not the wireframe read
	var ov = _scene.get("_overlay_states")
	if ov is Dictionary:
		for k in (ov as Dictionary).keys():
			ov[k] = false
		if _scene.has_method("_refresh_active_overlay"):
			_scene.call("_refresh_active_overlay")

	# --- the overlook, the collapse, the ride down (plays itself) ---
	await _wait_cond(func():
		for id in ids:
			var p: Vector3 = _gs.get_position(str(id))
			if p.x > 2.5 or bool(_gs.call("is_external_traversal_active", str(id))):
				return false
		return true, 45.0)
	await _wait_s(1.5)
	_log("landed")
	_narrate("The water carries the party down the whole coil to the stretch start — the first shelter is right here.")

	# --- the first shelter: rest at the camp before the climb ---
	var base_rest = _chunk.find_child("BaseShelterRest", true, false)
	if base_rest != null:
		base_rest.call("_on_rest_requested")
	await _wait_s(3.5)
	_log("base-rest")
	_narrate("Camp rest taken. Turn one: read each channel beat and cross when the next surge is far enough out.")

	# --- turn 1: S0 and S1 on their beats ---
	for leg in [[0, 10.2], [1, 18.3]]:
		var ch = channels[int(leg[0])]
		await _wait_cond(func():
			var on: Array = (_chunk.call("get_preview_state") as Dictionary).get("next_onsets_in", [])
			return not bool(ch.call("is_flooding")) and on.size() > int(leg[0]) \
				and float(on[int(leg[0])]) > 3.2, 22.0)
		var t: Dictionary = {}
		for k in range(3):
			t[ids[k]] = Vector3(float(leg[1]), 0.1, 0.9 + 0.6 * float(k))
		await _move_all(t)
		_log("cross-s%d" % int(leg[0]))

	# --- the flure verb: sing on the telegraph, RETREAT, and let the wash
	# --- take the answering sentry. At real pace the crossing can miss the
	# --- flood; the smart play is distance + another song — the WHOLE party
	# --- stages west out of reach, aster fires and falls back, and nobody
	# --- re-approaches the console while the answered sentry is away from
	# --- its home ground.
	var flure = _chunk.find_child("LonelyFlureObject", true, false)
	var foe0 = _chunk.call("_fauna_by_id", "sapscrap_0")
	_narrate("A sentry holds the landing. Plan: sing the flure on the telegraph and FALL BACK — whatever answers arrives at the song, not at us.")
	var _foe_dead := func() -> bool:
		return foe0 != null and not bool(foe0.call("is_alive"))
	await _move_all({"peris": Vector3(11.0, 0.1, 2.0), "endo": Vector3(11.6, 0.1, 3.0)}, 12.0)
	for _sing in range(3):
		if bool(_foe_dead.call()):
			break
		# the console is only safe while the sentry is on its home ground
		await _wait_cond(func():
			return bool(_foe_dead.call()) or _gs.get_position("sapscrap_0").x > 24.5, 34.0)
		if bool(_foe_dead.call()):
			break
		_gs.command_move_to_pos("aster", Vector3(17.6, 0.1, 1.4))
		await _wait_cond(func(): return not bool(_gs.is_moving("aster")), 10.0)
		await _wait_cond(func():
			var on: Array = (_chunk.call("get_preview_state") as Dictionary).get("next_onsets_in", [])
			return not bool((channels[2] as Node).call("is_flooding")) \
				and on.size() > 2 and float(on[2]) > 0.4 and float(on[2]) < 1.1, 18.0)
		if flure != null:
			flure.set("active_character", "aster")
			await process_frame
			flure.call("_trigger")
		_gs.command_move_to_pos("aster", Vector3(11.5, 0.1, 1.0))
		_log("sang")
		await _wait_cond(_foe_dead, 34.0)
		_log("song-watch-done")
	await _wait_s(1.0)
	_log("flure-resolved")
	_narrate("The wash takes the sentry mid-crossing — the demonstration, and a clear landing.")

	# --- the landing: cross S2, drop the rope, hold the valve, keyed span ---
	await _wait_cond(func():
		var on: Array = (_chunk.call("get_preview_state") as Dictionary).get("next_onsets_in", [])
		return not bool((channels[2] as Node).call("is_flooding")) \
			and on.size() > 2 and float(on[2]) > 3.2, 18.0)
	var t2: Dictionary = {}
	for k2 in range(3):
		t2[ids[k2]] = Vector3(25.6, 0.1, 3.4 + 0.8 * float(k2))
	await _move_all(t2)
	_log("s2-crossed")
	await _click("DropRope1", "aster", Vector3(26.8, 0.1, 1.4))
	_narrate("Dropping a sloperope: the checkpoint that makes the next failure cost a runback, not the run.")
	await _wait_s(1.0)
	await _move_all({"peris": Vector3(26.6, 0.1, 5.6), "endo": Vector3(27.2, 0.1, 6.4)}, 12.0)
	await _click("LandingValve", "aster", Vector3(26.4, 0.1, 1.2))
	_narrate("The keyed span fits NO gait — its dry beat is one second. Holding the valve IS the crossing.")
	await _wait_s(0.8)
	await _move_all({"aster": Vector3(26.4, 0.1, 4.8)}, 8.0)
	# distinct cells by X AND Z: stacked targets get reparked by the
	# cooperative planner, and a repark off the high shelf is a walk into
	# the patrol watch
	var t3: Dictionary = {
		"aster": Vector3(36.6, 0.1, 6.2), "peris": Vector3(37.5, 0.1, 6.9),
		"endo": Vector3(38.4, 0.1, 6.2)}
	await _move_all(t3, 16.0)
	_log("keyed-crossed")

	# --- the climb: S4 high shelf, then the transfer and exam laps ---
	await _cross_section(4, 38.5, 46.5, 3.0, 4.6, -1.0, 5.0, 0.6, false,
		"Section 4 is watched ground: the whole leg stays on the high shelf, out of the patrol reach.")
	await _cross_section(5, 56.5, 66.0, 3.7, 0.9, -1.0, 0.9, 1.2, true,
		"Turn two: no gauges reach this high. The first naked read — watch a full cycle, then cross.")
	# S6, the intended plan: Aster rides the queue crawl entered WHILE the
	# water runs; the others cross the bed on the window his ride spans.
	_narrate("The queue crawl exits inside the span tail. Entering WHILE the water runs — the tube spends the flood, so the exit lands on the dry beat.")
	var qcrawl = _chunk.find_child("QueueCrawl", true, false)
	await _move_all({"aster": Vector3(68.0, 0.1, 7.0),
		"peris": Vector3(67.2, 0.1, 1.0), "endo": Vector3(67.2, 0.1, 2.0)}, 14.0)
	var ch6 = channels[6]
	await _wait_cond(func(): return bool(ch6.call("is_flooding")), 14.0)
	_scene.call("headless_set_selected_characters", ["aster"])
	if qcrawl != null:
		qcrawl.set("active_character", "aster")
		await process_frame
		qcrawl.call("_trigger")
	await _wait_cond(func(): return not bool(ch6.call("is_flooding")), 10.0)
	_gs.command_move_to_pos("peris", Vector3(78.0, 0.1, 1.0))
	_gs.command_move_to_pos("endo", Vector3(78.0, 0.1, 2.2))
	await _wait_cond(func():
		return not bool(_gs.call("is_external_traversal_active", "aster")), 16.0)
	_gs.command_move_to_pos("aster", Vector3(78.0, 0.1, 3.2))
	await _wait_cond(func():
		for id_q in ids:
			if bool(_gs.is_moving(str(id_q))):
				return false
		return _gs.get_position("aster").x > 76.8, 20.0)
	_scene.call("headless_set_selected_characters", ["aster", "peris", "endo"])
	await _cross_section(7, 82.5, 96.5, 2.43, 0.9, 6.4, 0.9, 1.2, true,
		"Run-only: the dry beat fits no walk. Sprinting, paid from the stamina banked below.")
	await _click("DropRope3", "aster", Vector3(99.0, 0.1, 1.4))
	await _wait_s(1.0)
	await _cross_section(8, 102.5, 116.0, 4.44, 0.2, -1.0, 0.2, 0.45, true,
		"Watched altitude: the roamer prices the high side, so the party holds the low lane the whole way.")
	await _cross_section(9, 124.5, 136.5, 4.44, 0.2, -1.0, 0.2, 0.45, true,
		"Turn three, the exam lap: the same read, faster and darker.")
	await _click("DropRope4", "aster", Vector3(137.0, 0.1, 1.4))
	await _wait_s(1.0)
	_narrate("The exam: keyed again, no gauge — and the valve stands BEFORE the span it keys. The inversion, answered from memory.")
	await _click("ExamValve", "aster", Vector3(137.5, 0.1, 1.2))
	await _wait_s(0.8)
	# the exam-cross parks in the LOW lane with x-spread: the summit flure's
	# lured watcher WANDERS a disc around the song (observed to x 151), and
	# its distracted reach still catches anything mid-deck inside the disc
	var te: Dictionary = {
		"aster": Vector3(149.6, 0.1, 0.3), "peris": Vector3(150.5, 0.1, 0.9),
		"endo": Vector3(151.4, 0.1, 1.5)}
	await _move_all(te, 18.0)
	_log("exam-crossed")

	# --- the summit: the flure pulls the watcher, the ring takes the rest ---
	_narrate("The summit watcher owns the pad. Singing the high flure and falling back — pulling it off its ground.")
	_gs.command_move_to_pos("aster", Vector3(158.0, 0.1, 6.8))
	await _wait_cond(func(): return not bool(_gs.is_moving("aster")), 12.0)
	var hflure = _chunk.find_child("HighFlureObject", true, false)
	if hflure != null:
		hflure.set("active_character", "aster")
		await process_frame
		hflure.call("_trigger")
	# fire and FALL BACK — the lured watcher parks ON the song, and a singer
	# who lingers is standing in its arrival spot (the lonely flure's lesson,
	# re-learned at altitude)
	_gs.command_move_to_pos("aster", Vector3(152.0, 0.1, 0.5))
	await _wait_cond(func(): return not bool(_gs.is_moving("aster")), 10.0)
	# gate ONLY on "the watcher is west of the pad, up at the song's side" —
	# then GO: the lure window is short, and lingering inside the wander
	# disc waiting for a settle that never comes is how the last run died
	await _wait_cond(func():
		var wp: Vector3 = _gs.get_position("sapscrap_2")
		return wp.x < 161.0 and wp.z > 4.0, 30.0)
	_log("pad-clear")
	_narrate("The watcher is at the song, west of the pad. Crossing NOW — low lane, inside the fresh lure window.")
	await _move_all({"aster": Vector3(166.8, 0.1, 2.2), "peris": Vector3(167.5, 0.1, 2.8),
		"endo": Vector3(168.2, 0.1, 2.4)}, 22.0)
	_log("on-pad")
	var ring = _chunk.find_child("AscentPortal", true, false)
	if ring != null:
		ring.call("_on_rest_requested")
		await _wait_cond(func(): return bool(ring.call("is_completed")), 8.0)
		if not bool(ring.call("is_completed")):
			ring.call("_on_rest_requested")
	_narrate("Everyone on the pad. The ring takes the party — stretch complete, zero damage taken.")
	await _wait_cond(func():
		return str((_chunk.call("get_preview_state") as Dictionary).get("phase", "")) == "complete", 10.0)
	await _wait_s(4.0)
	_write_captions_srt()
	quit(0)
