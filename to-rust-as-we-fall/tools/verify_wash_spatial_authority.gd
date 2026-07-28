extends SceneTree

## Focused regression for Wash Relay's spatial authority.
##
## No test below calls `_process()` or `headless_process()`. Held stations are sampled again at
## flood consequence ticks, while concealment, retry-marker release, and route completion ride one
## saved fixed scheduler cadence. Same-node/fresh restore and fine/coarse advancement must therefore
## expose the same causal world without a render pass.

const RelayScene := preload("res://scenes/fragments/chunks/wash_relay_chunk.tscn")
const PARTY: Array[String] = ["aster", "peris", "endo"]

var _checks := 0
var _failures := 0


class RelayHost extends Node:
	var game_state := GameState.new()
	var scheduler := EventScheduler.new()
	var active_character := "aster"
	var party: Array[String] = PARTY.duplicate()

	func configure(spawns: Dictionary) -> void:
		game_state.scheduler = scheduler
		game_state.set_party(party)
		for char_id in party:
			game_state.register_character(char_id, spawns.get(char_id, Vector3.ZERO), 3.0, {
				"hp": 100.0,
				"max_hp": 100.0,
				"stamina": 100.0,
				"max_stamina": 100.0,
				"atp": 3.0,
			})

	func get_preview_game_state():
		return game_state

	func get_preview_scheduler():
		return scheduler

	func get_preview_scheduler_tick() -> float:
		return scheduler.get_current_tick()

	func get_preview_character_position(char_id: String) -> Vector3:
		return game_state.get_position(char_id)

	func set_preview_character_position(char_id: String, value: Vector3) -> void:
		game_state.snap_character_to(char_id, value)

	func get_preview_character_move_speed(_char_id: String, _running := false) -> float:
		return 3.0

	func get_preview_active_character() -> String:
		return active_character

	func get_preview_selected_characters() -> Array:
		return party.duplicate()

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)

	func set_preview_step(_step: String) -> void:
		pass

	func register_preview_interactable(_interactable: Node) -> void:
		pass

	func get_preview_dialogue_box():
		return null

	func get_preview_engram_overlay():
		return null

	func show_preview_note(_text: String, _duration := 3.0) -> void:
		pass

	func show_preview_message(_text: String, _duration := 2.0) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_plate_consequence_and_restore()
	await _verify_concealment_cadence_and_restore()
	await _verify_retry_route_cadence()
	await _verify_completion_boundary_and_fast_forward()
	print("WASH SPATIAL AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_plate_consequence_and_restore() -> void:
	var pair := await _boot()
	var host: RelayHost = pair.host
	var chunk: Node = pair.chunk
	var gs := host.game_state
	var plate_index := _section_index(chunk, "plate")
	check(plate_index >= 0, "relay exposes the held-plate section")
	if plate_index < 0:
		await _discard(host)
		return
	var section := _section_state(chunk, plate_index)
	var plate_pos := Vector3(float(section.get("x0", 0.0)) - 1.2, 0.5, 0.0)
	var bridge_pos := Vector3(
		(float(section.get("x0", 0.0)) + float(section.get("x1", 0.0))) * 0.5,
		0.5,
		0.0
	)
	gs.snap_character_to("aster", Vector3(3.0, 0.5, 0.0))
	gs.snap_character_to("peris", plate_pos)
	gs.snap_character_to("endo", bridge_pos)
	var onset_in := float(_section_state(chunk, plate_index).get("next_onset_in", -1.0))
	check(onset_in > 0.2, "plate test finds a future scheduler-owned flood boundary")
	host.scheduler.advance_ticks(maxf(0.0, onset_in - 0.12))
	var held_capture := _capture(host)

	# Discarded future: stepping off before the consequence tick catches the bridge occupant.
	gs.snap_character_to("peris", Vector3(20.0, 0.5, 0.0))
	host.scheduler.advance_ticks(0.14)
	check(int(chunk.get_preview_state().get("current_carry_count", 0)) == 1,
		"flood consequence samples the released plate without a presenter pass")

	# Roll back to the same physical positions and exact next spatial/flood ticks.
	_apply_capture(host, chunk, held_capture)
	_apply_capture(host, chunk, held_capture)
	var restored := _section_state(chunk, plate_index)
	check(bool(restored.get("plate_held", false))
			and bool(restored.get("disabled", false)),
		"same-node restore rebuilds held truth from canonical positions")
	host.scheduler.advance_ticks(0.14)
	check(int(chunk.get_preview_state().get("current_carry_count", -1)) == 0
			and not bool(_section_state(chunk, plate_index).get("flooding", true)),
		"restored holder suppresses the exact flood consequence without render/headless polling")

	var fresh_pair := await _boot()
	var fresh_host: RelayHost = fresh_pair.host
	var fresh: Node = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, held_capture)
	check(bool(_section_state(fresh, plate_index).get("plate_held", false)),
		"fresh presenter reconstructs the same held station")
	fresh_host.scheduler.advance_ticks(0.14)
	check(int(fresh.get_preview_state().get("current_carry_count", -1)) == 0,
		"fresh presenter preserves the held outcome at the original flood tick")
	await _discard(host)
	await _discard(fresh_host)


func _verify_concealment_cadence_and_restore() -> void:
	var pair := await _boot()
	var host: RelayHost = pair.host
	var chunk: Node = pair.chunk
	var gs := host.game_state
	var alcoves: Array = chunk.get("HIDE_ALCOVES")
	check(not alcoves.is_empty(), "relay exposes a physical hide alcove")
	if alcoves.is_empty():
		await _discard(host)
		return
	var alcove: Dictionary = alcoves[0]
	var hidden_pos: Vector3 = alcove.get("pos", Vector3.ZERO)
	var exposed_pos := hidden_pos + Vector3(0.0, 0.0, float(alcove.get("radius", 1.0)) + 1.0)
	gs.snap_character_to("endo", hidden_pos)
	host.scheduler.advance_ticks(float(chunk.SPATIAL_AUTHORITY_INTERVAL) + 0.001)
	check(gs.get_character_concealment("endo") == GameState.CONCEAL_FULL,
		"fixed spatial tick derives alcove concealment without a render pass")
	var hidden_capture := _capture(host)
	var saved_next := float(chunk.get_preview_state().get("next_spatial_authority_tick", -1.0))

	gs.snap_character_to("endo", exposed_pos)
	var remaining := saved_next - host.scheduler.get_current_tick()
	host.scheduler.advance_ticks(maxf(0.0, remaining - 0.001))
	check(gs.get_character_concealment("endo") == GameState.CONCEAL_FULL,
		"concealment remains the saved sampled truth until its explicit next boundary")
	host.scheduler.advance_ticks(0.002)
	check(gs.get_character_concealment("endo") == GameState.CONCEAL_NONE,
		"crossing the saved boundary exposes the character exactly once")

	_apply_capture(host, chunk, hidden_capture)
	check(gs.get_character_concealment("endo") == GameState.CONCEAL_FULL
			and gs.get_position("endo").distance_to(hidden_pos) < 0.001,
		"same-node restore preserves GameState concealment and its physical cause")
	var restored_next := float(chunk.get_preview_state().get("next_spatial_authority_tick", -1.0))
	check(is_equal_approx(restored_next, saved_next),
		"same-node restore preserves the absolute spatial deadline")
	gs.snap_character_to("endo", exposed_pos)
	host.scheduler.advance_ticks(maxf(0.0, restored_next - host.scheduler.get_current_tick() + 0.001))
	check(gs.get_character_concealment("endo") == GameState.CONCEAL_NONE,
		"restored cadence re-evaluates concealment without any presenter call")

	var fresh_pair := await _boot()
	var fresh_host: RelayHost = fresh_pair.host
	var fresh: Node = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, hidden_capture)
	check(fresh_host.game_state.get_character_concealment("endo") == GameState.CONCEAL_FULL
			and is_equal_approx(
				float(fresh.get_preview_state().get("next_spatial_authority_tick", -1.0)),
				saved_next
			),
		"fresh presenter restores both sampled concealment and the next absolute tick")
	await _discard(host)
	await _discard(fresh_host)


func _verify_retry_route_cadence() -> void:
	var pair := await _boot()
	var host: RelayHost = pair.host
	var chunk: Node = pair.chunk
	var gs := host.game_state
	var section := _section_state(chunk, 0)
	var caught := Vector3(
		(float(section.get("x0", 0.0)) + float(section.get("x1", 0.0))) * 0.5,
		0.5,
		0.0
	)
	gs.snap_character_to("aster", caught)
	check(bool(chunk.call("_wash_character", "aster")),
		"route test enters the ordinary current transaction")
	host.scheduler.advance_ticks(
		float(chunk.WASH_CURRENT_KNOCK_DURATION)
		+ float(chunk.WASH_CURRENT_RETURN_MAX)
		+ 0.2
	)
	check(int(chunk.get_preview_state().get("washed_count", -1)) == 1,
		"current impact records one waiting route state")
	var waiting_capture := _capture(host)
	var retry_boundary := float(section.get("x0", 0.0)) - 0.5
	gs.snap_character_to("aster", Vector3(retry_boundary + 0.25, 0.5, 0.0))
	check(int(chunk.get_preview_state().get("washed_count", -1)) == 1,
		"moving beyond the retry boundary does not mutate state through a preview read")
	var next_tick := float(chunk.get_preview_state().get("next_spatial_authority_tick", -1.0))
	host.scheduler.advance_ticks(maxf(0.0, next_tick - host.scheduler.get_current_tick() + 0.001))
	check(int(chunk.get_preview_state().get("washed_count", -1)) == 0,
		"saved spatial consequence releases the retry marker without headless polling")

	_apply_capture(host, chunk, waiting_capture)
	check(int(chunk.get_preview_state().get("washed_count", -1)) == 1
			and gs.get_position("aster").distance_to(chunk.START_POS) < 0.001,
		"restore retracts the later route release to the physical waiting endpoint")
	await _discard(host)


func _verify_completion_boundary_and_fast_forward() -> void:
	var fine_pair := await _boot()
	var fine_host: RelayHost = fine_pair.host
	var fine: Node = fine_pair.chunk
	for char_id in PARTY:
		fine_host.game_state.snap_character_to(char_id, Vector3(85.0, 0.5, 0.0))
	var before_completion := _capture(fine_host)
	var deadline := float(fine.get_preview_state().get("next_spatial_authority_tick", -1.0))
	var remaining := deadline - fine_host.scheduler.get_current_tick()
	fine_host.scheduler.advance_ticks(maxf(0.0, remaining - 0.001))
	check(not bool(fine.get_preview_state().get("complete", false)),
		"whole-party exit cannot complete before the saved consequence boundary")
	fine_host.scheduler.advance_ticks(0.002)
	check(bool(fine.get_preview_state().get("complete", false)),
		"fine advancement completes at the fixed spatial boundary without a render pass")

	_apply_capture(fine_host, fine, before_completion)
	_apply_capture(fine_host, fine, before_completion)
	fine_host.scheduler.advance_ticks(remaining + 0.001)
	check(bool(fine.get_preview_state().get("complete", false)),
		"same-node rollback re-arms exactly one completion boundary")

	var coarse_pair := await _boot()
	var coarse_host: RelayHost = coarse_pair.host
	var coarse: Node = coarse_pair.chunk
	_apply_capture(coarse_host, coarse, before_completion)
	coarse_host.scheduler.advance_ticks(remaining + 1.0)
	var coarse_state: Dictionary = coarse.get_preview_state()
	check(bool(coarse_state.get("complete", false))
			and str(coarse_state.get("phase", "")) == "complete",
		"coarse fast-forward reaches the identical completion outcome")
	check(fine_host.game_state.get_character_concealment("aster")
			== coarse_host.game_state.get_character_concealment("aster")
			and fine_host.game_state.get_character_concealment("aster") == GameState.CONCEAL_FULL,
		"fine and coarse completion publish the same sanctuary consequence")
	await _discard(fine_host)
	await _discard(coarse_host)


func _boot() -> Dictionary:
	var resource = load("res://data/fragments/wash_relay.tres")
	var host := RelayHost.new()
	host.configure(resource.spawns)
	root.add_child(host)
	var chunk: Node = RelayScene.instantiate()
	chunk.call("attach_chunk_host", host, "wash_relay")
	chunk.set_process(false)
	host.add_child(chunk)
	await process_frame
	host.game_state.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	chunk.call("reset_preview_state")
	chunk.set_process(false)
	return {"host": host, "chunk": chunk}


func _section_index(chunk: Node, section_type: String) -> int:
	var sections: Array = chunk.call("get_preview_state").get("sections", [])
	for index in range(sections.size()):
		if str((sections[index] as Dictionary).get("type", "")) == section_type:
			return index
	return -1


func _section_state(chunk: Node, index: int) -> Dictionary:
	var sections: Array = chunk.call("get_preview_state").get("sections", [])
	return sections[index] as Dictionary if index >= 0 and index < sections.size() else {}


func _capture(host: RelayHost) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _apply_capture(host: RelayHost, chunk: Node, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	_notify_snapshot_restored(chunk)


func _notify_snapshot_restored(node: Node) -> void:
	if node.has_method("on_game_state_snapshot_restored"):
		node.call("on_game_state_snapshot_restored")
	for child in node.get_children():
		_notify_snapshot_restored(child)


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	await process_frame
	await process_frame


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
