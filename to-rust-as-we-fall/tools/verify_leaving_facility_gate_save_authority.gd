extends SceneTree

## Portable authority and rollback regression for Leaving Facility's three ordered route seals.
## The authored lift is visible during OPENING, while collision and GridWorld clearance commit only
## at the saved endpoint. Same-presenter, fresh-presenter, absence, repeated attachment, endpoint
## revalidation, and out-of-order-load cases all project from the PartyGate3D records.

const LeavingFacilityScene := preload("res://scenes/tutorial/leaving_facility.tscn")
const MIDPOINT_SECONDS := 0.45
const DEADLINE_EPSILON := 0.01

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sequence: Node = await _spawn_sequence()
	sequence._scheduler.clear()
	sequence._scheduler.resume()
	check(sequence._sector_gates.size() == 3,
		"Leaving Facility builds three authoritative route-gate mechanisms")
	check(_all_gate_phases(sequence, PartyGate3D.PHASE_CLOSED)
			and _only_station_pair_available(sequence, 0),
		"construction derives the closed prefix and exposes only sector one")
	check(_all_gate_cells_closed(sequence),
		"construction keeps all three GridWorld seals physically closed")

	# Calling a later station directly is not a progression API: only the first
	# non-open member of the saved gate prefix may start a commitment.
	_place_party_at_station(sequence, 1, "direct")
	sequence._on_sector_route_committed(1, "direct")
	check(str(sequence._sector_gates[1].get_authority_state().get("phase", ""))
			== PartyGate3D.PHASE_CLOSED and _gate_cells_closed(sequence, 1),
		"a later seal cannot bypass corridor order through a direct call")

	var closed_snapshot := _json_round_trip(sequence.build_save_snapshot())
	var absent_snapshot := _json_round_trip(closed_snapshot)
	_erase_all_gate_records(absent_snapshot, sequence)

	var first_direct_source: Node = sequence._sector_route_interactables[0][1]
	first_direct_source.set("active_character", "aster")
	first_direct_source.emit_signal("interacted")
	check(str(sequence._sector_gates[0].get_authority_state().get("phase", "")) \
			== PartyGate3D.PHASE_CLOSED,
		"a manually emitted route signal cannot counterfeit exact station acceptance")
	check(not bool(first_direct_source.call("_trigger", false)),
		"a remote selected portrait cannot accept the exact first route source")

	_place_party_at_station(sequence, 0, "direct")
	var first_panel: MeshInstance3D = sequence._sector_gate_visuals[0]
	var closed_y: float = first_panel.position.y
	var accepted_box := {"snapshot": {}}
	var capture_accepted := func(data_id: String, actor: String) -> void:
		if data_id == str(first_direct_source.get("data_id")) and actor == "aster" \
				and (accepted_box.get("snapshot", {}) as Dictionary).is_empty():
			accepted_box["snapshot"] = _json_round_trip(sequence.build_save_snapshot())
	sequence._game_state.interactable_triggered.connect(capture_accepted, CONNECT_ONE_SHOT)
	check(_trigger_route_source(sequence, 0, "direct", "aster"),
		"the exact nearby direct station accepts the first route receipt")
	var opening: Dictionary = sequence._sector_gates[0].get_authority_state()
	var context: Dictionary = opening.get("context", {})
	check(str(opening.get("phase", "")) == PartyGate3D.PHASE_OPENING
			and str(opening.get("contract", "")) == PartyGate3D.STATE_CONTRACT,
		"working sector one publishes a versioned OPENING phase")
	check(str(context.get("contract", "")) == sequence.SECTOR_GATE_CONTEXT_CONTRACT
			and int(context.get("sector_index", -1)) == 0
			and int(context.get("commit_order", -1)) == 0
			and str(context.get("sector_id", "")) == "bleedway"
			and str(context.get("route_choice", "")) == "direct",
		"the same record carries versioned sector, order, and route context")
	check(not sequence._sector_gates_open[0] and _gate_cells_closed(sequence, 0)
			and _no_station_pair_available(sequence),
		"OPENING retires station affordances without granting early clearance")

	sequence._scheduler.advance_ticks(MIDPOINT_SECONDS)
	sequence._update_sector_gate_visuals()
	var midpoint_y: float = first_panel.position.y
	var midpoint_snapshot := _json_round_trip(sequence.build_save_snapshot())
	var saved_deadline := float(opening.get("end_tick", -1.0))
	var saved_tick := float(sequence._scheduler.get_current_tick())
	check(midpoint_y > closed_y and midpoint_y < sequence.SECTOR_GATE_OPEN_Y,
		"the saved midpoint visibly lifts the seal instead of hiding its mesh")
	check(_gate_cells_closed(sequence, 0) and not sequence._sector_gates_open[0],
		"the visibly moving midpoint still owns closed collision/navigation truth")

	sequence._scheduler.advance_ticks(saved_deadline - saved_tick + 0.001)
	check(sequence._sector_gates_open[0] and _gate_cells_open(sequence, 0)
			and _only_station_pair_available(sequence, 1),
		"the discarded future opens sector one and exposes sector two only at the endpoint")

	# Roll the same presenter back into the lift, then attach twice. Stable scheduler
	# tags must still yield one completion at the original absolute deadline.
	sequence.apply_save_snapshot(midpoint_snapshot)
	sequence._notify_authoritative_presenters_after_load()
	sequence._notify_authoritative_presenters_after_load()
	var restored: Dictionary = sequence._sector_gates[0].get_authority_state()
	check(str(restored.get("phase", "")) == PartyGate3D.PHASE_OPENING
			and is_equal_approx(float(restored.get("end_tick", -1.0)), saved_deadline),
		"same-presenter rollback and repeated attachment preserve one absolute lift deadline")
	check(not sequence._sector_gates_open[0] and _gate_cells_closed(sequence, 0)
			and is_equal_approx(first_panel.position.y, midpoint_y),
		"same-presenter rollback retracts future clearance and resamples the saved lift")
	var same_opened_count := [0]
	sequence._sector_gates[0].opened.connect(func(): same_opened_count[0] += 1)
	_advance_to_just_before(sequence, saved_deadline)
	check(str(sequence._sector_gates[0].get_authority_state().get("phase", ""))
			== PartyGate3D.PHASE_OPENING and _gate_cells_closed(sequence, 0),
		"same-presenter restore cannot clear the seal before the saved remainder")
	sequence._scheduler.advance_ticks(DEADLINE_EPSILON + 0.001)
	check(sequence._sector_gates_open[0] and _gate_cells_open(sequence, 0)
			and same_opened_count[0] == 1,
		"same-presenter restore commits exactly once at the saved endpoint")
	var accepted_snapshot: Dictionary = accepted_box.get("snapshot", {}) as Dictionary
	check(not accepted_snapshot.is_empty(),
		"the exact route acceptance boundary can be saved before PartyGate ownership")
	sequence.apply_save_snapshot(accepted_snapshot)
	check(str(sequence._sector_gates[0].get_authority_state().get("phase", "")) \
			== PartyGate3D.PHASE_CLOSED
			and _gate_cells_closed(sequence, 0)
			and sequence._sector_route_interactables[0][1].is_interaction_enabled(),
		"same-presenter accepted-before-owner restore burns the edge without opening the seal")

	_end_sequence(sequence)
	var fresh: Node = await _spawn_sequence()
	fresh._scheduler.clear()
	fresh._scheduler.resume()
	fresh.apply_save_snapshot(midpoint_snapshot)
	var fresh_panel: MeshInstance3D = fresh._sector_gate_visuals[0]
	var fresh_saved: Dictionary = fresh._sector_gates[0].get_authority_state()
	check(str(fresh_saved.get("phase", "")) == PartyGate3D.PHASE_OPENING
			and is_equal_approx(float(fresh_saved.get("end_tick", -1.0)), saved_deadline)
			and is_equal_approx(fresh_panel.position.y, midpoint_y),
		"a fresh presenter reconstructs the same midpoint phase, deadline, and visible lift")
	check(_gate_cells_closed(fresh, 0) and _no_station_pair_available(fresh),
		"a fresh midpoint load cannot receive early GridWorld or station progression")
	var fresh_opened_count := [0]
	fresh._sector_gates[0].opened.connect(func(): fresh_opened_count[0] += 1)
	_advance_to_just_before(fresh, saved_deadline)
	check(_gate_cells_closed(fresh, 0),
		"fresh attachment remains physically closed before the saved endpoint")
	fresh._scheduler.advance_ticks(DEADLINE_EPSILON + 0.001)
	check(fresh._sector_gates_open[0] and _gate_cells_open(fresh, 0)
			and fresh_opened_count[0] == 1 and _only_station_pair_available(fresh, 1),
		"fresh attachment commits once and derives the next reachable station pair")

	# An older snapshot with no gate records is the authored closed baseline. Loading
	# it after an open future must retract collision, progression, and pending callbacks.
	fresh.apply_save_snapshot(absent_snapshot)
	check(_all_gate_phases(fresh, PartyGate3D.PHASE_CLOSED)
			and _all_gate_cells_closed(fresh) and _only_station_pair_available(fresh, 0),
		"snapshot absence retracts all gate progress to the authored baseline")
	fresh._scheduler.advance_ticks(fresh.SECTOR_GATE_OPEN_DURATION * 2.1)
	check(_all_gate_phases(fresh, PartyGate3D.PHASE_CLOSED)
			and _all_gate_cells_closed(fresh),
		"absence leaves no callback from the discarded open future")

	# A syntactically valid later OPEN record with no preceding OPEN prefix is still
	# invalid causal history. Attachment closes it rather than enabling a load exploit.
	var out_of_order_snapshot := _json_round_trip(absent_snapshot)
	_inject_open_record(out_of_order_snapshot, fresh, 1)
	fresh.apply_save_snapshot(out_of_order_snapshot)
	check(str(fresh._sector_gates[1].get_authority_state().get("phase", ""))
			== PartyGate3D.PHASE_CLOSED and _gate_cells_closed(fresh, 1)
			and _only_station_pair_available(fresh, 0),
		"an out-of-order loaded gate is normalized closed and cannot bypass the sequence")

	# Deadline revalidation remains part of the mechanism: leaving during the saved
	# lift falsifies the player's 'we can abandon Peris now' prediction visibly and safely.
	_place_party_at_station(fresh, 0, "safe")
	check(_trigger_route_source(fresh, 0, "safe", "aster"),
		"the restored exact safe station starts a new physical lift attempt")
	fresh.set_preview_character_position("peris", fresh.EXIT_POS)
	fresh._scheduler.advance_ticks(fresh.SECTOR_GATE_OPEN_DURATION + 0.001)
	check(str(fresh._sector_gates[0].get_authority_state().get("phase", ""))
			== PartyGate3D.PHASE_CLOSED and _gate_cells_closed(fresh, 0)
			and _only_station_pair_available(fresh, 0),
		"party departure at the endpoint stops the lift and restores the current choice")
	fresh.apply_save_snapshot(accepted_snapshot)
	check(str(fresh._sector_gates[0].get_authority_state().get("phase", "")) \
			== PartyGate3D.PHASE_CLOSED
			and _gate_cells_closed(fresh, 0)
			and fresh._sector_route_interactables[0][1].is_interaction_enabled(),
		"fresh accepted-before-owner restore also rearms without granting clearance")

	_end_sequence(fresh)
	print("LEAVING FACILITY GATE SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _spawn_sequence() -> Node:
	var sequence := LeavingFacilityScene.instantiate()
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(8):
		await process_frame
	# This verifier targets the corridor gates, whose authored contract begins only
	# after Endo joins the saved roster. Pre-join absence has its own focused suite.
	sequence._scheduler.clear()
	sequence._scheduler.resume()
	sequence._begin_endo_join_wait()
	sequence._scheduler.advance_ticks(sequence.ENDO_JOIN_DELAY + 0.001)
	return sequence


func _place_party_at_station(sequence: Node, sector_index: int, route_choice: String) -> void:
	var key := "safe_station" if route_choice == "safe" else "direct_station"
	var station: Vector3 = sequence.IRON_SECTORS[sector_index][key]
	sequence.set_preview_character_position("aster", station)
	sequence.set_preview_character_position("peris", station + Vector3(-0.8, 0.0, 0.8))
	sequence.set_preview_character_position("endo", station + Vector3(-0.8, 0.0, -0.8))


func _trigger_route_source(
		sequence: Node,
		sector_index: int,
		route_choice: String,
		actor: String
	) -> bool:
	var choice_index := 0 if route_choice == "safe" else 1
	var source: Node = sequence._sector_route_interactables[sector_index][choice_index]
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _advance_to_just_before(sequence: Node, deadline: float) -> void:
	var remaining := deadline - float(sequence._scheduler.get_current_tick())
	sequence._scheduler.advance_ticks(maxf(0.0, remaining - DEADLINE_EPSILON))
	sequence._update_sector_gate_visuals()


func _gate_cells_closed(sequence: Node, sector_index: int) -> bool:
	var gate_x := float(sequence.IRON_SECTORS[sector_index]["gate_x"])
	var gate_cell: Vector2i = sequence._grid.world_to_grid(Vector3(gate_x, 0.0, 0.0))
	for dz in range(-3, 4):
		if sequence._grid.get_tile(gate_cell.x, gate_cell.y + dz) != GridWorld.Tile.WALL:
			return false
	return true


func _gate_cells_open(sequence: Node, sector_index: int) -> bool:
	var gate_x := float(sequence.IRON_SECTORS[sector_index]["gate_x"])
	var gate_cell: Vector2i = sequence._grid.world_to_grid(Vector3(gate_x, 0.0, 0.0))
	for dz in range(-3, 4):
		if sequence._grid.get_tile(gate_cell.x, gate_cell.y + dz) != GridWorld.Tile.FLOOR:
			return false
	return true


func _all_gate_cells_closed(sequence: Node) -> bool:
	for sector_index in range(sequence._sector_gates.size()):
		if not _gate_cells_closed(sequence, sector_index):
			return false
	return true


func _all_gate_phases(sequence: Node, expected: String) -> bool:
	for gate in sequence._sector_gates:
		if str(gate.get_authority_state().get("phase", "")) != expected:
			return false
	return true


func _only_station_pair_available(sequence: Node, available_index: int) -> bool:
	for sector_index in range(sequence._sector_route_interactables.size()):
		for station in sequence._sector_route_interactables[sector_index]:
			if station.is_interaction_enabled() != (sector_index == available_index):
				return false
	return true


func _no_station_pair_available(sequence: Node) -> bool:
	for pair in sequence._sector_route_interactables:
		for station in pair:
			if station.is_interaction_enabled():
				return false
	return true


func _erase_all_gate_records(snapshot: Dictionary, sequence: Node) -> void:
	var game_state_data: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state_data.get("world_state", {})
	for gate in sequence._sector_gates:
		world_state.erase(gate.authority_state_key())
	game_state_data["world_state"] = world_state
	snapshot["game_state"] = game_state_data


func _inject_open_record(snapshot: Dictionary, sequence: Node, sector_index: int) -> void:
	var game_state_data: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state_data.get("world_state", {})
	var gate: PartyGate3D = sequence._sector_gates[sector_index]
	world_state[gate.authority_state_key()] = {
		"contract": PartyGate3D.STATE_CONTRACT,
		"authority_id": gate.authority_id,
		"phase": PartyGate3D.PHASE_OPEN,
		"start_tick": 0.0,
		"end_tick": sequence.SECTOR_GATE_OPEN_DURATION,
		"required_members": ["aster", "peris", "endo"],
		"context": {
			"contract": sequence.SECTOR_GATE_CONTEXT_CONTRACT,
			"sector_index": sector_index,
			"sector_id": str(sequence.IRON_SECTORS[sector_index]["id"]),
			"route_choice": "direct",
			"commit_order": sector_index,
		},
	}
	game_state_data["world_state"] = world_state
	snapshot["game_state"] = game_state_data


func _end_sequence(sequence: Node) -> void:
	if sequence.has_method("_teardown_sequence"):
		sequence._teardown_sequence()
	sequence.free()


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
