extends SceneTree

## Anti-teleport contract for Channels wash currents. A caught character must remain inside a
## locked, saved two-leg traversal until the body reaches the start shelter; no decorative streak
## may grant the endpoint, the waiting set, or the climb-back affordance early.

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
				"hp": 100.0, "max_hp": 100.0,
				"stamina": 100.0, "max_stamina": 100.0,
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
	var pair := await _boot()
	var host: RelayHost = pair.host
	var chunk = pair.chunk
	var gs: GameState = host.game_state
	var baseline := _capture(host)
	var section: Dictionary = (chunk.get_preview_state().get("sections", []) as Array)[0]
	var caught_at := Vector3(
		(float(section.get("x0", 0.0)) + float(section.get("x1", 0.0))) * 0.5,
		0.5,
		0.0
	)
	gs.snap_character_to("aster", caught_at)
	var accepted := bool(chunk.call("_wash_character", "aster"))
	var started: Dictionary = chunk.get_preview_state()
	var knock: Dictionary = gs.get_external_traversal_state("aster")
	check(accepted, "the visible current accepts a caught character")
	check(str(knock.get("traversal_id", "")) == "wash_relay_current:knock:aster",
		"wash begins a locked knock traversal instead of snapping to shelter")
	check(int(started.get("current_carry_count", 0)) == 1
			and int(started.get("washed_count", -1)) == 0,
		"commit records in-flight current ownership without granting the waiting endpoint")
	check(gs.get_position("aster").distance_to(caught_at) < 0.001,
		"caught character remains at the physical origin on the commitment tick")
	check(not gs.command_move_to_pos("aster", caught_at + Vector3(8.0, 0.0, 0.0)),
		"ordinary movement cannot cancel the committed current")
	check(gs.get_character_concealment("aster") >= GameState.CONCEAL_FULL,
		"the opaque current owns concealment only while the body is in transit")
	check(not bool(chunk.call("_wash_character", "aster")),
		"flood rechecks cannot duplicate an already carried character")

	host.scheduler.advance_ticks(chunk.WASH_CURRENT_KNOCK_DURATION * 0.5)
	chunk.headless_process(0.0)
	var knock_midpoint := _capture(host)
	var knock_mid: Dictionary = gs.get_external_traversal_state("aster")
	var knock_progress := float(knock_mid.get("progress", -1.0))
	var knock_render: Vector3 = knock_mid.get("render_position", caught_at)
	check(knock_progress > 0.49 and knock_progress < 0.51,
		"knock midpoint is scheduler-derived and serialized")
	check(knock_render.distance_to(caught_at) > 0.2
			and gs.get_position("aster").distance_to(chunk.START_POS) > 1.0,
		"the real body moves inward while the shelter endpoint remains unearned")
	chunk.headless_process(9999.0)
	check(is_equal_approx(
		float(gs.get_external_traversal_state("aster").get("progress", -2.0)), knock_progress),
		"render-frame delta cannot advance the current")

	host.scheduler.advance_ticks(float(knock_mid.get("remaining", 0.0)) + 0.001)
	var return_leg: Dictionary = gs.get_external_traversal_state("aster")
	var returning: Dictionary = chunk.get_preview_state()
	check(str(return_leg.get("traversal_id", "")) == "wash_relay_current:return:aster"
			and str((returning.get("current_carries", {}) as Dictionary).get("aster", {}).get(
				"phase", "")) == "return",
		"knock completion chains into a saved return leg rather than teleporting")
	check(int(returning.get("washed_count", -1)) == 0
			and int(chunk.call("_rejoin_waiting_crew")) == 0,
		"the retired chunk helper stays inert and cannot recover an in-flight body")
	host.scheduler.advance_ticks(float(return_leg.get("remaining", 0.0)) * 0.5)
	var return_midpoint := _capture(host)
	var return_mid: Dictionary = gs.get_external_traversal_state("aster")
	check(float(return_mid.get("progress", 0.0)) > 0.49
			and float(return_mid.get("progress", 1.0)) < 0.51,
		"return midpoint remains a real in-flight position")
	host.scheduler.advance_ticks(maxf(0.0, float(return_mid.get("remaining", 0.0)) - 0.001))
	check(int(chunk.get_preview_state().get("washed_count", -1)) == 0,
		"waiting state cannot commit before shelter impact")
	host.scheduler.advance_ticks(0.002)
	var landed: Dictionary = chunk.get_preview_state()
	check(int(landed.get("current_carry_count", -1)) == 0
			and int(landed.get("washed_count", -1)) == 1,
		"shelter impact atomically ends current ownership and starts waiting")
	check(not gs.is_external_traversal_active("aster")
			and gs.get_position("aster").distance_to(chunk.START_POS) < 0.001,
		"the authoritative body reaches the shelter at the final deadline")
	check(gs.get_character_concealment("aster") == GameState.CONCEAL_NONE,
		"current-only concealment clears on shelter arrival")

	# Same-instance rollback through both legs must retract the already-landed future.
	_apply_capture(host, chunk, knock_midpoint)
	_apply_capture(host, chunk, knock_midpoint)
	var rolled_knock: Dictionary = gs.get_external_traversal_state("aster")
	check(str(rolled_knock.get("traversal_id", "")) == "wash_relay_current:knock:aster"
			and absf(float(rolled_knock.get("progress", 0.0)) - 0.5) < 0.001
			and int(chunk.get_preview_state().get("washed_count", -1)) == 0,
		"same-instance rollback reconstructs the exact knock midpoint")
	host.scheduler.advance_ticks(float(rolled_knock.get("remaining", 0.0)) + 0.001)
	check(str(gs.get_external_traversal_state("aster").get("traversal_id", "")) \
			== "wash_relay_current:return:aster",
		"restored knock chains exactly once into its saved return")

	_apply_capture(host, chunk, return_midpoint)
	var rolled_return: Dictionary = gs.get_external_traversal_state("aster")
	check(str(rolled_return.get("traversal_id", "")) == "wash_relay_current:return:aster"
			and float(rolled_return.get("progress", 0.0)) > 0.49
			and float(rolled_return.get("progress", 1.0)) < 0.51,
		"same-instance rollback reconstructs the exact return midpoint")
	host.scheduler.advance_ticks(float(rolled_return.get("remaining", 0.0)) + 0.001)
	check(int(chunk.get_preview_state().get("washed_count", -1)) == 1,
		"restored return lands once after consuming only its saved remainder")

	var fresh_pair := await _boot()
	var fresh_host: RelayHost = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, return_midpoint)
	var fresh_state: Dictionary = fresh_host.game_state.get_external_traversal_state("aster")
	check(str(fresh_state.get("traversal_id", "")) == "wash_relay_current:return:aster"
			and float(fresh_state.get("progress", 0.0)) > 0.49
			and int(fresh.get_preview_state().get("washed_count", -1)) == 0,
		"fresh presenter reconstructs the in-flight return without granting arrival")
	fresh_host.scheduler.advance_ticks(float(fresh_state.get("remaining", 0.0)) + 0.001)
	check(int(fresh.get_preview_state().get("washed_count", -1)) == 1
			and not fresh_host.game_state.is_external_traversal_active("aster"),
		"fresh presenter lands once at the original return deadline")

	# An absent record is construction truth, never permission to retain a carried/landed future.
	var absent := baseline.duplicate(true)
	var absent_gs: Dictionary = absent.get("game_state", {}) as Dictionary
	var absent_world: Dictionary = absent_gs.get("world_state", {}) as Dictionary
	absent_world.erase(chunk.WASH_AUTHORITY_KEY)
	absent_gs["world_state"] = absent_world
	absent["game_state"] = absent_gs
	_apply_capture(host, chunk, absent)
	check(int(chunk.get_preview_state().get("current_carry_count", -1)) == 0
			and int(chunk.get_preview_state().get("washed_count", -1)) == 0
			and not gs.is_external_traversal_active("aster"),
		"missing wash authority retracts every carried/waiting future")

	await _discard(host)
	await _discard(fresh_host)
	print("WASH CURRENT SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _boot() -> Dictionary:
	var resource = load("res://data/fragments/wash_relay.tres")
	var host := RelayHost.new()
	host.configure(resource.spawns)
	root.add_child(host)
	var chunk = RelayScene.instantiate()
	chunk.attach_chunk_host(host, "wash_relay")
	host.add_child(chunk)
	await process_frame
	host.game_state.grid = GridWorld.from_data(chunk.get_grid_data())
	chunk.reset_preview_state()
	chunk.headless_process(0.0)
	await process_frame
	return {"host": host, "chunk": chunk}


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
