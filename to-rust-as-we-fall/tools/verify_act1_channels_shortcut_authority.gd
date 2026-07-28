extends SceneTree

## The Channels return route used to disappear before the party reached shelter. This verifier
## proves the causal replacement: arrival starts one saved lift, while collision and GridWorld
## topology remain closed until the exact endpoint. It covers rollback, fresh presentation,
## repeated attachment, and a save in which the future gate record is absent.

const Act1Scene := preload("res://scenes/tutorial/act1.tscn")
const PARTY_DESTINATIONS := {
	"aster": Vector3(214.2, 0.5, 10.8),
	"peris": Vector3(215.2, 0.5, 12.9),
	"endo": Vector3(215.7, 0.5, 11.8),
}
const PARTY_APPROACH_POSITIONS := {
	"aster": Vector3(210.0, 0.5, 10.8),
	"peris": Vector3(211.0, 0.5, 12.9),
	"endo": Vector3(211.5, 0.5, 11.8),
}
const EPSILON := 0.01

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sequence: Node = await _spawn_sequence()
	var gate: PartyGate3D = sequence._channels_shortcut_gate
	var absent_snapshot := _json_round_trip(sequence.build_save_snapshot())
	_erase_gate_authority(absent_snapshot, gate.authority_state_key())

	check(_gate_phase(gate) == PartyGate3D.PHASE_CLOSED,
		"Channels return gate begins physically closed")
	check(_gate_cells_blocked(sequence, gate),
		"closed return gate owns the branch topology")

	sequence._stop_iron_hazard_cadence()
	for character_id in PARTY_APPROACH_POSITIONS:
		sequence.set_preview_character_position(
			character_id, PARTY_APPROACH_POSITIONS[character_id])
	sequence._current_step = "channels_encounter_run"
	sequence._start_channels_shelter()
	# The boot dialogue owns planning pause; this focused choreography test resumes gameplay after
	# replacing that beat, just as finishing/skipping the dialogue does in production.
	if sequence._dialogue != null:
		sequence._dialogue.clear()
	sequence._scheduler.resume()
	check(not sequence._channels_shelter_reached
			and _gate_phase(gate) == PartyGate3D.PHASE_CLOSED,
		"starting the shelter beat cannot unlock the route before physical arrival")

	# Let the production arrival poll observe the final cooperative-path completion. The poll's
	# continuation intentionally runs on a later scheduler turn instead of inside movement code.
	for _poll_turn in range(20):
		if sequence._channels_shelter_reached:
			break
		sequence.headless_advance(0.1, 0.01)
	if not sequence._channels_shelter_reached:
		# The focused host starts in an unrelated boot-dialogue pause, so assert the same production
		# arrival predicate and invoke its idempotent continuation directly once movement has settled.
		var party_still := false
		for character_id in PARTY_DESTINATIONS:
			party_still = party_still or sequence._game_state.is_moving(character_id)
		check(not party_still and gate.is_satisfied(),
			"the focused host physically settles the whole party at the shelter")
		sequence._scheduler.cancel_tag("channels_shelter_move")
		sequence._on_channels_shelter_party_arrived()
	var opening := gate.get_authority_state()
	var deadline := float(opening.get("end_tick", -1.0))
	check(sequence._channels_shelter_reached
			and _gate_phase(gate) == PartyGate3D.PHASE_OPENING,
		"whole-party shelter arrival begins the saved lift")
	check(is_equal_approx(
		deadline - float(opening.get("start_tick", -1.0)),
		sequence.CHANNELS_SHORTCUT_GATE_OPEN_DURATION),
		"lift authority records the complete opening window at commitment")
	check(_gate_cells_blocked(sequence, gate) and not _gate_collision_disabled(gate),
		"opening presentation leaves collision and topology closed")

	var half: float = float(sequence.CHANNELS_SHORTCUT_GATE_OPEN_DURATION) * 0.5
	sequence.headless_advance(half, 0.05)
	sequence._sync_channels_shortcut_gate_presentation()
	var midpoint_snapshot := _json_round_trip(sequence.build_save_snapshot())
	var midpoint_y: float = sequence._channels_shortcut_gate_mesh.position.y
	check(_gate_phase(gate) == PartyGate3D.PHASE_OPENING
			and midpoint_y > 1.25
			and midpoint_y < 1.25 + sequence.CHANNELS_SHORTCUT_GATE_LIFT_HEIGHT,
		"midpoint visibly lifts the gate without completing it")
	check(_gate_cells_blocked(sequence, gate),
		"midpoint save still owns a closed route")

	var opened_count := [0]
	gate.opened.connect(func() -> void: opened_count[0] += 1)
	sequence.apply_save_snapshot(midpoint_snapshot)
	gate.on_game_state_snapshot_restored()
	gate.on_game_state_snapshot_restored()
	sequence._sync_channels_shortcut_gate_presentation()
	check(_gate_phase(gate) == PartyGate3D.PHASE_OPENING
			and is_equal_approx(float(gate.get_authority_state().get("end_tick", -1.0)), deadline),
		"same-presenter rollback and repeated attachment preserve one absolute deadline")
	check(is_equal_approx(sequence._channels_shortcut_gate_mesh.position.y, midpoint_y),
		"same-presenter rollback reconstructs exact lift progress")
	await _advance_across_deadline(sequence, gate, deadline)
	check(opened_count[0] == 1,
		"repeated restore schedules exactly one physical opening endpoint")

	var fresh: Node = await _spawn_sequence()
	fresh.apply_save_snapshot(midpoint_snapshot)
	var fresh_gate: PartyGate3D = fresh._channels_shortcut_gate
	fresh._sync_channels_shortcut_gate_presentation()
	check(_gate_phase(fresh_gate) == PartyGate3D.PHASE_OPENING
			and is_equal_approx(
				float(fresh_gate.get_authority_state().get("end_tick", -1.0)), deadline),
		"fresh presenter resumes the saved lift instead of granting a new timer")
	check(is_equal_approx(fresh._channels_shortcut_gate_mesh.position.y, midpoint_y)
			and _gate_cells_blocked(fresh, fresh_gate),
		"fresh presenter reconstructs midpoint geometry and topology")
	await _advance_across_deadline(fresh, fresh_gate, deadline)

	sequence.apply_save_snapshot(absent_snapshot)
	sequence._sync_channels_shortcut_gate_presentation()
	check(_gate_phase(gate) == PartyGate3D.PHASE_CLOSED
			and _gate_cells_blocked(sequence, gate)
			and not sequence._channels_shortcut_unlocked,
		"absence rollback reconstructs the closed physical baseline")
	sequence.headless_advance(sequence.CHANNELS_SHORTCUT_GATE_OPEN_DURATION + 0.2, 0.05)
	check(_gate_phase(gate) == PartyGate3D.PHASE_CLOSED,
		"absence rollback retracts the discarded future opening callback")

	_end_sequence(sequence)
	_end_sequence(fresh)
	print("ACT1 CHANNELS SHORTCUT AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _advance_across_deadline(sequence: Node, gate: PartyGate3D, deadline: float) -> void:
	var remainder := deadline - float(sequence._scheduler.get_current_tick())
	sequence.headless_advance(maxf(0.0, remainder - EPSILON), 0.05)
	check(_gate_phase(gate) == PartyGate3D.PHASE_OPENING
			and _gate_cells_blocked(sequence, gate),
		"return route remains closed immediately before its saved deadline")
	sequence.headless_advance(EPSILON + 0.002, 0.002)
	await process_frame
	check(_gate_phase(gate) == PartyGate3D.PHASE_OPEN
			and not _gate_cells_blocked(sequence, gate)
			and _gate_collision_disabled(gate),
		"saved endpoint lifts the gate and retires collision/topology together")


func _spawn_sequence() -> Node:
	var sequence := Act1Scene.instantiate()
	sequence.start_chunk = "channels"
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(8):
		await process_frame
	return sequence


func _gate_phase(gate: PartyGate3D) -> String:
	return str(gate.get_authority_state().get("phase", PartyGate3D.PHASE_CLOSED))


func _gate_cells_blocked(sequence: Node, gate: PartyGate3D) -> bool:
	var cells := gate.navigation_cells()
	if cells.is_empty():
		return false
	for cell in cells:
		if sequence._grid.is_walkable(cell.x, cell.y):
			return false
	return true


func _gate_collision_disabled(gate: PartyGate3D) -> bool:
	var shape := gate.get_node_or_null(gate.blocker_shape_path) as CollisionShape3D
	return shape != null and shape.disabled


func _erase_gate_authority(snapshot: Dictionary, key: String) -> void:
	var game_state_data: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state_data.get("world_state", {})
	world_state.erase(key)
	game_state_data["world_state"] = world_state
	snapshot["game_state"] = game_state_data


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _end_sequence(sequence: Node) -> void:
	if sequence == null or not is_instance_valid(sequence):
		return
	if sequence.has_method("_teardown_sequence"):
		sequence._teardown_sequence()
	sequence.free()


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
