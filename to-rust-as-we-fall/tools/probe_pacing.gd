extends SceneTree
## PACING PROBE for wash_ascent: drives the canonical solve (the playthrough
## test's flow) and buckets every 0.1 s of simulated time into WAIT (standing,
## nothing in flight), WALK (someone moving), RIDE (carry/climb traversal), or
## ACT (an interaction beat just fired). Reports per-phase totals, the
## active/passive split, and the LONGEST continuous passive stretch — the
## walking-simulator number. Numbers, never vibes.
##
##   ../Godot_v4.7-stable_win64_console.exe --headless --path "." \
##       --script tools/probe_pacing.gd

var _timeline: Array = []   # [{phase, kind, dur}]
var _scene: Node
var _gs
var _chunk

func _bucket(phase: String, kind: String, dur: float) -> void:
	_timeline.append({"phase": phase, "kind": kind, "dur": dur})

func _advance_tagged(phase: String, secs: float, step := 0.1) -> void:
	var t := 0.0
	while t < secs:
		_scene.call("headless_advance", step)
		t += step
		var kind := "wait"
		for id in ["aster", "peris", "endo"]:
			if bool(_gs.call("is_external_traversal_active", id)):
				kind = "ride"
				break
			if bool(_gs.is_moving(id)):
				kind = "walk"
		_bucket(phase, kind, step)

func _advance_until(phase: String, cond: Callable, cap: float, step := 0.1) -> void:
	var t := 0.0
	while t < cap and not bool(cond.call()):
		_scene.call("headless_advance", step)
		t += step
		var kind := "wait"
		for id in ["aster", "peris", "endo"]:
			if bool(_gs.call("is_external_traversal_active", id)):
				kind = "ride"
				break
			if bool(_gs.is_moving(id)):
				kind = "walk"
		_bucket(phase, kind, step)

func _move_all(phase: String, targets: Dictionary, cap := 25.0) -> void:
	for id in targets:
		_gs.command_move_to_pos(str(id), targets[id])
	_advance_until(phase, func():
		for id in targets:
			if bool(_gs.is_moving(str(id))):
				return false
			if _gs.get_position(str(id)).distance_to(targets[id] as Vector3) > 1.6:
				return false
		return true, cap)

func _act(phase: String) -> void:
	_bucket(phase, "act", 0.4)

## One ladder leg, the playthrough's two-stage plan: stage the party at the
## span's MOUTH (full-cell 1.2 row spacing so nobody trails head-to-tail),
## then launch on the flood->dry TRANSITION once the window covers the need.
func _cross_section(phase_id: String, idx: int, mouth_x: float, dest_x: float,
		need: float, mouth_z := 0.9, speed := -1.0, dest_z := 0.9, row_pitch := 1.2) -> void:
	var channels: Array = _chunk.get("_channels")
	var ids := ["aster", "peris", "endo"]
	var tm: Dictionary = {}
	for k in range(3):
		tm[ids[k]] = Vector3(mouth_x, 0.1, mouth_z + row_pitch * float(k))
	_move_all("stage-%s" % phase_id, tm)
	var st := {"saw": false}
	var ch = channels[idx]
	_advance_until("window-%s" % phase_id, func():
		var flooding: bool = bool(ch.call("is_flooding"))
		if flooding:
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
		td[ids[k2]] = Vector3(dest_x, 0.1, dest_z + row_pitch * float(k2))
	_move_all("cross-%s" % phase_id, td)
	if speed > 0.0:
		_gs.change_move_speed("aster", 3.2)
		_gs.change_move_speed("peris", 2.8)
		_gs.change_move_speed("endo", 2.8)

func _initialize() -> void:
	var packed = load("res://scenes/fragments/fragment_preview.tscn")
	_scene = packed.instantiate()
	_scene.set("preview_menu", false)
	_scene.set("preview_chunk", "wash_ascent")
	get_root().add_child(_scene)
	for _i in range(30):
		await process_frame
	_chunk = _scene.find_child("Chunk_wash_ascent", true, false)
	_gs = _scene.get("_game_state")
	_scene.call("headless_advance", 0.05)
	_advance_tagged("intro-overlook-drop", 20.0, 0.2)
	var channels: Array = _chunk.get("_channels")
	var ids := ["aster", "peris", "endo"]

	# --- act one: three read-and-dash crossings + the lure play ---
	for leg in [[0, 10.2], [1, 18.3]]:
		var ch = channels[int(leg[0])]
		_advance_until("wait-dry-%d" % int(leg[0]), func():
			var on: Array = (_chunk.call("get_preview_state") as Dictionary).get("next_onsets_in", [])
			return not bool(ch.call("is_flooding")) and on.size() > int(leg[0]) \
				and float(on[int(leg[0])]) > 3.2, 20.0)
		var t: Dictionary = {}
		for k in range(3):
			t[ids[k]] = Vector3(float(leg[1]), 0.1, 0.9 + 0.6 * float(k))
		_move_all("cross-%d" % int(leg[0]), t)
	_act("flure-fire")
	var flure = _chunk.find_child("LonelyFlureObject", true, false)
	_gs.command_move_to_pos("aster", Vector3(17.6, 0.1, 1.4))
	_advance_until("walk-to-flure", func():
		return not bool(_gs.is_moving("aster")), 8.0)
	_advance_until("fire-on-telegraph", func():
		var on: Array = (_chunk.call("get_preview_state") as Dictionary).get("next_onsets_in", [])
		return not bool((channels[2] as Node).call("is_flooding")) \
			and on.size() > 2 and float(on[2]) > 0.4 and float(on[2]) < 1.1, 16.0)
	flure.set("active_character", "aster")
	await process_frame
	flure.call("_trigger")
	_act("flure-sing")
	_advance_until("demonstration-kill", func():
		var foe = _chunk.call("_fauna_by_id", "sapscrap_0")
		return foe != null and not bool(foe.call("is_alive")), 30.0, 0.2)
	# --- landing: cross section 2, drop rope 1, valve, keyed crossing ---
	_advance_until("wait-dry-2", func():
		var on: Array = (_chunk.call("get_preview_state") as Dictionary).get("next_onsets_in", [])
		return not bool((channels[2] as Node).call("is_flooding")) \
			and on.size() > 2 and float(on[2]) > 3.2, 16.0)
	var t2: Dictionary = {}
	for k2 in range(3):
		t2[ids[k2]] = Vector3(25.6, 0.1, 3.4 + 0.8 * float(k2))
	_move_all("cross-2", t2)
	var drop1 = _chunk.find_child("DropRope1", true, false)
	_gs.command_move_to_pos("aster", Vector3(26.8, 0.1, 1.4))
	_advance_until("walk-to-drop", func(): return not bool(_gs.is_moving("aster")), 6.0)
	drop1.set("active_character", "aster")
	drop1.call("_trigger")
	_act("drop-rope-1")
	_move_all("stage-wall", {"peris": Vector3(26.6, 0.1, 5.6), "endo": Vector3(27.2, 0.1, 6.4)}, 10.0)
	var lvalve = _chunk.find_child("LandingValve", true, false)
	_gs.command_move_to_pos("aster", Vector3(26.4, 0.1, 1.2))
	_advance_until("walk-to-valve", func(): return not bool(_gs.is_moving("aster")), 6.0)
	lvalve.set("active_character", "aster")
	lvalve.call("_trigger")
	_act("hold-valve")
	_move_all("rejoin-wall", {"aster": Vector3(26.4, 0.1, 4.8)}, 5.0)
	var t3: Dictionary = {}
	for k3 in range(3):
		t3[ids[k3]] = Vector3(37.2, 0.1, 6.2 + 0.4 * float(k3))
	_move_all("cross-keyed", t3, 14.0)
	# --- the climb: S4 and the turn-2/3 ladder (the playthrough's plan: stage
	# --- at each mouth, launch on the flood->dry transition) ---
	_cross_section("s4", 4, 38.5, 46.5, 3.0, 5.6, -1.0, 5.0, 0.6)
	_cross_section("s5", 5, 56.5, 66.0, 3.7)
	# S6, the intended MULTI-BEAT plan: Aster rides the queue crawl entered
	# WHILE the water runs (the tube spends the flood, the exit lands dry);
	# the others cross the bed on the same dry window his ride spans.
	var qcrawl = _chunk.find_child("QueueCrawl", true, false)
	_move_all("stage-s6", {"aster": Vector3(68.0, 0.1, 7.0),
		"peris": Vector3(67.2, 0.1, 1.0), "endo": Vector3(67.2, 0.1, 2.0)}, 12.0)
	var ch6 = (_chunk.get("_channels") as Array)[6]
	_advance_until("wait-s6-flood", func(): return bool(ch6.call("is_flooding")), 14.0)
	_scene.call("headless_set_selected_characters", ["aster"])
	qcrawl.set("active_character", "aster")
	await process_frame
	qcrawl.call("_trigger")
	_act("queue-crawl")
	_advance_until("s6-beat", func(): return not bool(ch6.call("is_flooding")), 10.0)
	_gs.command_move_to_pos("peris", Vector3(78.0, 0.1, 1.0))
	_gs.command_move_to_pos("endo", Vector3(78.0, 0.1, 2.2))
	# the exit lands inside the span's TAIL — the plan's last beat is walking
	# straight off it (the pre-clicked move a real rider queues before landing)
	_advance_until("crawl-ride", func():
		return not bool(_gs.call("is_external_traversal_active", "aster")), 16.0, 0.1)
	_gs.command_move_to_pos("aster", Vector3(78.0, 0.1, 3.2))
	_advance_until("crawl-and-bed", func():
		for id_q in ["aster", "peris", "endo"]:
			if bool(_gs.is_moving(str(id_q))):
				return false
		return _gs.get_position("peris").x > 76.8 \
			and _gs.get_position("aster").x > 76.8, 20.0, 0.2)
	_scene.call("headless_set_selected_characters", ["aster", "peris", "endo"])
	_cross_section("s7-sprint", 7, 82.5, 96.5, 2.43, 0.9, 6.4)
	var drop3 = _chunk.find_child("DropRope3", true, false)
	_gs.command_move_to_pos("aster", Vector3(99.0, 0.1, 1.4))
	_advance_until("walk-to-drop3", func(): return not bool(_gs.is_moving("aster")), 8.0)
	drop3.set("active_character", "aster")
	drop3.call("_trigger")
	_act("drop-rope-3")
	_cross_section("s8", 8, 102.5, 116.0, 4.44, 0.2, -1.0, 0.2, 0.8)
	_cross_section("s9", 9, 124.5, 136.5, 4.44, 0.2, -1.0, 0.2, 0.8)
	var drop4 = _chunk.find_child("DropRope4", true, false)
	_gs.command_move_to_pos("aster", Vector3(137.0, 0.1, 1.4))
	_advance_until("walk-to-drop4", func(): return not bool(_gs.is_moving("aster")), 8.0)
	drop4.set("active_character", "aster")
	drop4.call("_trigger")
	_act("drop-rope-4")
	var evalve = _chunk.find_child("ExamValve", true, false)
	_gs.command_move_to_pos("aster", Vector3(137.5, 0.1, 1.2))
	_advance_until("walk-to-exam-valve", func(): return not bool(_gs.is_moving("aster")), 6.0)
	evalve.set("active_character", "aster")
	evalve.call("_trigger")
	_act("hold-exam-valve")
	var te: Dictionary = {}
	for ke in range(3):
		te[ids[ke]] = Vector3(150.5, 0.1, 0.9 + 0.6 * float(ke))
	_move_all("cross-exam", te, 16.0)
	# --- the summit: high flure pulls the watcher, the pad takes the rest ---
	var hflure = _chunk.find_child("HighFlureObject", true, false)
	_gs.command_move_to_pos("aster", Vector3(158.0, 0.1, 6.8))
	_advance_until("walk-to-hflure", func(): return not bool(_gs.is_moving("aster")), 10.0)
	hflure.set("active_character", "aster")
	await process_frame
	hflure.call("_trigger")
	_act("hflure-sing")
	_advance_until("pad-clear", func():
		return _gs.get_position("sapscrap_2").x < 162.0, 40.0, 0.25)
	var t4 := {"aster": Vector3(166.8, 0.1, 2.2), "peris": Vector3(167.5, 0.1, 2.8),
		"endo": Vector3(168.2, 0.1, 2.4)}
	_move_all("cross-to-pad", t4, 16.0)
	_act("ring-rest")

	# --- the failure loop: wash + runback + climb (the checkpoint price) ---
	_scene.call("headless_set_character_position", "peris", Vector3(30.0, 0.1, 3.0))
	_advance_until("fail-wash-carry", func():
		var pp: Vector3 = _gs.get_position("peris")
		return pp.x < 2.2 and not bool(_gs.call("is_external_traversal_active", "peris")), 30.0, 0.2)
	_scene.call("headless_set_selected_characters", ["peris"])
	_gs.command_move_to_pos("peris", Vector3(1.6, 0.1, 2.4))
	_advance_until("runback-to-rope", func():
		return not bool(_gs.is_moving("peris")), 10.0)
	var cp_up = _chunk.find_child("SloperopeUp1", true, false)
	cp_up.set("active_character", "peris")
	await process_frame
	cp_up.call("_trigger")
	_advance_until("climb-rope-1", func():
		return _gs.get_position("peris").x > 25.0 \
			and not bool(_gs.call("is_external_traversal_active", "peris")), 120.0, 0.2)

	# --- report ---
	var totals: Dictionary = {}
	var by_kind: Dictionary = {"wait": 0.0, "walk": 0.0, "ride": 0.0, "act": 0.0}
	var longest_passive := 0.0
	var cur_passive := 0.0
	var longest_label := ""
	var cur_start_label := ""
	for e in _timeline:
		var ph := str(e["phase"])
		var kd := str(e["kind"])
		totals[ph] = float(totals.get(ph, 0.0)) + float(e["dur"])
		by_kind[kd] = float(by_kind.get(kd, 0.0)) + float(e["dur"])
		if kd == "wait" or kd == "walk":
			if cur_passive == 0.0:
				cur_start_label = ph
			cur_passive += float(e["dur"])
			if cur_passive > longest_passive:
				longest_passive = cur_passive
				longest_label = cur_start_label
		else:
			cur_passive = 0.0
	print("[pacing] ---- per-phase seconds ----")
	var seen := {}
	for e3 in _timeline:
		var ph2 := str(e3["phase"])
		if not seen.has(ph2):
			seen[ph2] = true
			print("[pacing] %-18s %6.1fs" % [ph2, float(totals[ph2])])
	var total: float = float(by_kind["wait"]) + float(by_kind["walk"]) 		+ float(by_kind["ride"]) + float(by_kind["act"])
	print("[pacing] ---- kinds: wait %.1fs | walk %.1fs | ride %.1fs | act %.1fs | total %.1fs" % [
		float(by_kind["wait"]), float(by_kind["walk"]), float(by_kind["ride"]),
		float(by_kind["act"]), total])
	print("[pacing] LONGEST PASSIVE STRETCH: %.1fs (starting in '%s')" % [longest_passive, longest_label])
	quit(0)
