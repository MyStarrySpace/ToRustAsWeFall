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
	# --- gap watch: high flure, pad clear, final crossing, rest ---
	var hflure = _chunk.find_child("HighFlureObject", true, false)
	_gs.command_move_to_pos("aster", Vector3(38.0, 0.1, 6.8))
	_advance_until("walk-to-hflure", func(): return not bool(_gs.is_moving("aster")), 8.0)
	hflure.set("active_character", "aster")
	await process_frame
	hflure.call("_trigger")
	_act("hflure-sing")
	_advance_until("pad-clear", func():
		return _gs.get_position("sapscrap_2").x < 46.5, 40.0, 0.25)
	_advance_until("wait-dry-4", func():
		var on: Array = (_chunk.call("get_preview_state") as Dictionary).get("next_onsets_in", [])
		return not bool((channels[4] as Node).call("is_flooding")) \
			and on.size() > 4 and float(on[4]) > 3.2, 16.0)
	var t4 := {"aster": Vector3(47.8, 0.1, 2.2), "peris": Vector3(48.5, 0.1, 2.8),
		"endo": Vector3(49.2, 0.1, 3.8)}
	_move_all("cross-4-to-pad", t4, 22.0)
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
