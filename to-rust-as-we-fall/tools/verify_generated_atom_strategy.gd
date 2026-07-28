extends SceneTree

const PREVIEW := preload("res://scenes/fragments/fragment_preview.tscn")
const CONTRACT_SEEDS := [7, 11, 1701, 2207, 3117, 8128]
const PARTY_IDS := ["aster", "peris", "endo"]

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for seed in CONTRACT_SEEDS:
		var measured := await _boot_atom(["distract:lure", "distract:patrol", "distract:twin"], seed)
		if measured == null:
			_fail("generated atom preview boots for seed %d" % seed)
			continue
		var contract: Dictionary = measured._active_chunk.get_strategy_contract()
		print("[ATOM STRATEGY seed=%d] %s" % [seed, JSON.stringify(contract)])
		_check(bool(contract.get("ok", false)),
			"seed %d keeps every lure lane clear, makes walk lose, and lets RUN win" % seed)
		for stage_variant in contract.get("stages", []):
			var stage: Dictionary = stage_variant
			var stage_prefix := "seed %d stage %d" % [seed, int(stage.get("index", -1))]
			_check(bool(stage.get("walk_loses", false)), "%s rejects the fastest walk" % stage_prefix)
			_check(bool(stage.get("run_wins", false)), "%s leaves a readable sprint margin" % stage_prefix)
			_check(bool(stage.get("path_clear", false)),
				"%s keeps the legal sprint path outside distracted reach" % stage_prefix)
			_check(bool(stage.get("speed_legal", false)),
				"%s keeps watcher return speed between walk and RUN" % stage_prefix)
		measured.queue_free()
		await process_frame
	var two_lure := await _boot_atom(["distract:lure", "distract:lure"], 7)
	if two_lure == null:
		_fail("the two-lure stock chain boots")
	else:
		var two_lure_contract: Dictionary = two_lure._active_chunk.get_strategy_contract()
		print("[ATOM TWO-LURE CONTRACT] %s" % JSON.stringify(two_lure_contract))
		_check(bool(two_lure_contract.get("ok", false)),
			"the stock two-lure chain proves the same executable formation rule")
		two_lure.queue_free()
		await process_frame

	var walk_outcome := await _play_single_lure(false)
	print("[ATOM STRATEGY] walk outcome %s" % JSON.stringify(walk_outcome))
	_check(bool(walk_outcome.get("spotted", false)) and not bool(walk_outcome.get("cleared", false)),
		"correct lane at walking speed loses the watcher race")

	var run_outcome := await _play_single_lure(true)
	print("[ATOM STRATEGY] run outcome %s" % JSON.stringify(run_outcome))
	_check(bool(run_outcome.get("cleared", false)) and not bool(run_outcome.get("spotted", false)),
		"the same plan with RUN beats the watcher home")

	var twin_outcome := await _play_single_lure(true, 12, "distract:twin")
	print("[ATOM STRATEGY] twin RUN outcome %s" % JSON.stringify(twin_outcome))
	_check(bool(twin_outcome.get("cleared", false)) and not bool(twin_outcome.get("spotted", false)),
		"the twin's three-wide gold formation beats its linked watcher without queue latency")

	print("[ATOM STRATEGY] %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)

func _boot_atom(
	stages: Array = ["distract:lure", "distract:patrol", "distract:twin"], seed := 7
) -> Node:
	var preview := PREVIEW.instantiate()
	preview.preview_menu = false
	preview.preview_chunk = "puzzle_atom"
	preview.preview_chunk_config = {"stages": stages, "seed": seed, "zone_setpieces": false}
	root.add_child(preview)
	for _frame in range(180):
		await process_frame
		if preview._active_chunk != null and preview._game_state != null:
			return preview
	return null

func _play_single_lure(
	running: bool, seed := 7, stage_id := "distract:lure"
) -> Dictionary:
	var preview := await _boot_atom([stage_id], seed)
	if preview == null:
		return {"error": "boot_failed"}
	var chunk = preview._active_chunk
	var gs = preview._game_state
	var anchors: Dictionary = chunk.get_preview_anchors()
	var launch: Vector3 = anchors["launch_0"]
	var rally_slots: Array[Vector3] = gs.compute_rally_destinations(PARTY_IDS, launch)
	gs.set_party(PARTY_IDS)
	for party_id in PARTY_IDS:
		gs.set_running(party_id, false)
	gs.party_move_to_pos(launch)
	var staged := _advance_until(preview, func() -> bool:
		return _party_stationary(gs) or _stage_state(chunk).get("spotted", false), 20.0)
	var state: Dictionary = _stage_state(chunk)
	if not staged or bool(state.get("spotted", false)):
		var failed_staging := _lure_outcome(preview, chunk, gs, running, false, false)
		preview.queue_free()
		await process_frame
		return failed_staging

	# Preparation is part of the strategy: only Peris leaves formation, tends, and
	# physically returns to her exact slot before the visible crossing beat.  The
	# outbound leg has no deadline, so spending sprint stamina there would turn a
	# correct timing read into an unexplained exhaustion failure on the way back.
	# Walk out; start RUN only when tending commits the watcher.
	gs.command_move_to_pos("peris", anchors["flure_0"])
	_advance_until(preview, func() -> bool: return not gs.is_moving("peris"), 20.0)
	var flure := chunk.find_child("AtomFlure0", true, false) as Flure
	if flure == null:
		var missing_flure := _lure_outcome(preview, chunk, gs, running, true, false)
		missing_flure["error"] = "missing_physical_flure"
		preview.queue_free()
		await process_frame
		return missing_flure
	flure.active_character = "peris"
	flure.on_interaction_arrived()
	preview.headless_advance(float(flure.dwell_time) + 0.1, 0.05)
	gs.set_running("peris", true)
	gs.command_move_to_pos("peris", rally_slots[PARTY_IDS.find("peris")])
	var regrouped := _advance_until(preview, func() -> bool:
		return not gs.is_moving("peris") or _stage_state(chunk).get("spotted", false), 20.0)
	var ready := regrouped and _advance_until(preview, func() -> bool:
		var current: Dictionary = _stage_state(chunk)
		return bool(current.get("lure_ready", false)) \
			or bool(current.get("race_started", false)) \
			or bool(current.get("spotted", false)), 20.0)
	state = _stage_state(chunk)
	ready = ready and bool(state.get("lure_ready", false)) \
		and not bool(state.get("spotted", false))
	var crossing_trace: Dictionary = {}
	if ready:
		for party_id in PARTY_IDS:
			gs.set_running(party_id, running)
		var committed_slots: Array[Vector3] = gs.compute_rally_destinations(
			PARTY_IDS, anchors["cross_0"])
		gs.party_move_to_pos(anchors["cross_0"])
		crossing_trace = {
			"command_tick": float(gs.scheduler.get_current_tick()),
			"committed_slots": _positions_text(committed_slots),
			"party": _party_trace(gs),
			"watcher": _character_trace(gs, "atom_sentry_0"),
			"stage": _stage_state(chunk).duplicate(true),
		}
		var elapsed := 0.0
		while elapsed < 20.0:
			var crossing_state: Dictionary = _stage_state(chunk)
			if bool(crossing_state["cleared"]) or bool(crossing_state["spotted"]):
				break
			preview.headless_advance(0.05, 0.05)
			elapsed += 0.05
		crossing_trace["resolution_seconds"] = elapsed
		crossing_trace["resolved_party"] = _party_trace(gs)
		crossing_trace["resolved_watcher"] = _character_trace(gs, "atom_sentry_0")
		crossing_trace["resolved_stage"] = _stage_state(chunk).duplicate(true)
	var outcome := _lure_outcome(preview, chunk, gs, running, staged, regrouped)
	outcome["ready"] = ready
	outcome["crossing_trace"] = crossing_trace
	preview.queue_free()
	await process_frame
	return outcome


func _stage_state(chunk: Node) -> Dictionary:
	return (chunk.get_preview_state()["stages"] as Array)[0] as Dictionary


func _party_stationary(gs) -> bool:
	for party_id in PARTY_IDS:
		if gs.is_moving(party_id):
			return false
	return true


func _party_trace(gs) -> Dictionary:
	var out: Dictionary = {}
	for party_id in PARTY_IDS:
		out[party_id] = _character_trace(gs, party_id)
	return out


func _character_trace(gs, character_id: String) -> Dictionary:
	if not gs.characters.has(character_id):
		return {"missing": true}
	var movement = gs.characters[character_id].movement
	var path_text: Array[String] = []
	var arrival_ticks: Array[float] = []
	if movement != null:
		for point_v in (movement.get("path", []) as Array):
			path_text.append(str(point_v as Vector3))
		for tick_v in (movement.get("arrival_ticks", []) as Array):
			arrival_ticks.append(float(tick_v))
	return {
		"position": str(gs.get_position(character_id)),
		"moving": gs.is_moving(character_id),
		"running": gs.is_running(character_id),
		"speed": float(gs.characters[character_id].move_speed),
		"stamina": gs.get_stat(character_id, "stamina"),
		"path": path_text,
		"arrival_ticks": arrival_ticks,
	}


func _positions_text(positions: Array[Vector3]) -> Array[String]:
	var out: Array[String] = []
	for position in positions:
		out.append(str(position))
	return out


func _lure_outcome(
	preview: Node, chunk: Node, gs, running: bool, staged: bool, regrouped: bool
) -> Dictionary:
	var state: Dictionary = _stage_state(chunk)
	return {
		"ready": bool(state.get("lure_ready", false)),
		"staged": staged,
		"regrouped": regrouped,
		"running": running,
		"cleared": bool(state["cleared"]),
		"spotted": bool(state["spotted"]),
		"race_started": bool(state["race_started"]),
		"peris_position": str(gs.get_position("peris")),
		"preview_valid": preview != null,
	}

func _advance_until(preview: Node, predicate: Callable, limit: float) -> bool:
	var elapsed := 0.0
	while elapsed < limit:
		if predicate.call():
			return true
		preview.headless_advance(0.05, 0.05)
		elapsed += 0.05
	return predicate.call()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_fail(message)

func _fail(message: String) -> void:
	_failures += 1
	push_error("  FAIL: %s" % message)
