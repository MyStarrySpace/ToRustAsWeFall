extends SceneTree

## Focused authority regression for Lockout's physical transitions. It exercises production-shaped
## same-instance rollback, fresh presenter restore, midpoint timing, input spam, and topology.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const LockoutScene := preload("res://scenes/fragments/chunks/lockout_chase_chunk.tscn")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_control_source_authority()
	await _verify_gantry_and_door_authority()
	await _verify_portal_follow_authority()
	await _verify_enemy_clamber_authority()
	await _verify_hushbloom_inventory_authority()
	await _verify_pair_roles_and_static_guards()
	print("LOCKOUT CHASE SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_control_source_authority() -> void:
	var pair := await _boot_lockout()
	var host = pair.host
	var chunk = pair.chunk
	var scanner: Interactable = chunk._boundary_scanner
	var door: Interactable = chunk._service_door
	chunk.set_pursuit_start_deferred(true)
	var pre_scan := _capture(host)

	check(not chunk._on_tags_rejected() and not chunk._chase_started,
		"source-less scanner helper cannot start the chase")
	scanner.interacted.emit()
	check(not chunk._chase_started,
		"manually emitting the scanner signal cannot mint its source receipt")
	scanner.active_character = "aster"
	check(not scanner._trigger() and not chunk._chase_started,
		"selected Aster cannot present tags while her body remains remote")
	var scanner_acceptance := {"value": {}}
	var capture_scanner := func(data_id: String, _actor: String) -> void:
		if data_id == str(scanner.data_id) \
				and (scanner_acceptance.value as Dictionary).is_empty():
			scanner_acceptance.value = _capture(host)
	host.game_state.interactable_triggered.connect(capture_scanner)
	host.game_state.snap_character_to("peris", _source_position(host, scanner))
	scanner.active_character = "peris"
	check(scanner._trigger() and chunk._chase_started,
		"a canonical nearby Peris body can trigger the exact scanner despite another portrait")
	host.game_state.interactable_triggered.disconnect(capture_scanner)
	var scanner_count := int(host.game_state.get_interactable(scanner.data_id).get(
		"trigger_count", 0))
	check(scanner_count == 1 and chunk._scanner_trigger_consumed == scanner_count \
			and not scanner._trigger(),
		"scanner receipt is consumed once and input spam cannot repeat rejection")
	check(not (scanner_acceptance.value as Dictionary).is_empty(),
		"save captured scanner acceptance before chase consequence dispatch")
	_apply_capture(host, chunk, scanner_acceptance.value)
	_apply_capture(host, chunk, scanner_acceptance.value)
	check(chunk._chase_started and chunk._scanner_trigger_consumed == 1,
		"accepted-scanner restore commits rejection exactly once")
	_apply_capture(host, chunk, pre_scan)
	check(not chunk._chase_started and scanner.is_interaction_enabled(),
		"rollback before scanner acceptance retracts the chase and re-arms its source")
	_apply_capture(host, chunk, scanner_acceptance.value)

	check(not chunk._on_door_sealed() and chunk._door_phase == chunk.DOOR_PHASE_OPEN,
		"source-less door helper cannot close the physical leaf")
	door.interacted.emit()
	check(chunk._door_phase == chunk.DOOR_PHASE_OPEN,
		"manually emitting the door signal cannot close it")
	door.active_character = "aster"
	check(not door._trigger(), "remote active portrait cannot seal the door")
	var door_acceptance := {"value": {}}
	var capture_door := func(data_id: String, _actor: String) -> void:
		if data_id == str(door.data_id) \
				and (door_acceptance.value as Dictionary).is_empty():
			door_acceptance.value = _capture(host)
	host.game_state.interactable_triggered.connect(capture_door)
	host.game_state.snap_character_to("peris", _source_position(host, door))
	door.active_character = "peris"
	check(door._trigger() and chunk._door_phase == chunk.DOOR_PHASE_CLOSING,
		"the exact nearby service-door control commits its closing phase")
	host.game_state.interactable_triggered.disconnect(capture_door)
	var door_count := int(host.game_state.get_interactable(door.data_id).get(
		"trigger_count", 0))
	check(door_count == 1 and chunk._door_trigger_consumed == door_count \
			and not door._trigger(),
		"door receipt is monotonic and the spent one-shot cannot double-close")
	check(not (door_acceptance.value as Dictionary).is_empty(),
		"save captured door acceptance before its closing phase dispatch")
	_apply_capture(host, chunk, door_acceptance.value)
	_apply_capture(host, chunk, door_acceptance.value)
	check(chunk._door_phase == chunk.DOOR_PHASE_CLOSING \
			and chunk._door_trigger_consumed == 1,
		"accepted-door restore commits one saved closing phase without reopening its source")

	var fresh_pair := await _boot_lockout()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, door_acceptance.value)
	check(fresh._chase_started and fresh._door_phase == fresh.DOOR_PHASE_CLOSING \
			and fresh._door_trigger_consumed == 1,
		"fresh presenter reconstructs accepted scanner and door receipts")

	await _discard(host)
	await _discard(fresh_host)


func _verify_gantry_and_door_authority() -> void:
	var pair := await _boot_lockout()
	var host = pair.host
	var chunk = pair.chunk
	var baseline := _capture(host)

	check(str(chunk.get_preview_state().get("gantry_phase", "")) == "standing"
		and not bool(chunk.get_preview_state().get("bridge_down", true)),
		"gantry construction truth is a standing, non-bridge phase")
	check(not _path_exists(host.grid, Vector3(12.0, 0.0, 0.0), Vector3(22.0, 0.0, 0.0)),
		"standing gantry leaves the service trench topologically closed")
	chunk._drop_gantry()
	var gantry_deadline := float(chunk._gantry_phase_deadline)
	chunk._drop_gantry()
	check(str(chunk.get_preview_state().get("gantry_phase", "")) == "falling"
		and is_equal_approx(float(chunk._gantry_phase_deadline), gantry_deadline),
		"gantry input spam cannot skip or restart the committed fall")
	host.scheduler.advance_ticks(chunk.GANTRY_FALL_SECS * 0.5)
	chunk.headless_process(0.0)
	var gantry_midpoint := _capture(host)
	var gantry_mid: Dictionary = chunk.get_preview_state()
	check(absf(float(gantry_mid.get("gantry_progress", -1.0)) - 0.5) < 0.001
		and not bool(gantry_mid.get("bridge_down", true)),
		"gantry exposes an analytic physical midpoint without granting the bridge")
	check(not _path_exists(host.grid, Vector3(12.0, 0.0, 0.0), Vector3(22.0, 0.0, 0.0)),
		"falling gantry cannot be crossed before impact")
	host.scheduler.advance_ticks(chunk.GANTRY_FALL_SECS * 0.5)
	check(bool(chunk.get_preview_state().get("bridge_down", false))
		and _path_exists(host.grid, Vector3(12.0, 0.0, 0.0), Vector3(22.0, 0.0, 0.0)),
		"gantry impact commits presentation and trench topology together")
	var side_trench_cell: Vector2i = host.grid.world_to_grid(Vector3(
		(chunk.TRENCH_X0 + chunk.TRENCH_X1) * 0.5, 0.0, 4.5))
	check(not host.grid.is_walkable(side_trench_cell.x, side_trench_cell.y),
		"landed gantry opens only its visible span instead of erasing the whole trench")

	_apply_capture(host, chunk, gantry_midpoint)
	_apply_capture(host, chunk, gantry_midpoint)
	chunk.headless_process(0.0)
	check(str(chunk.get_preview_state().get("gantry_phase", "")) == "falling"
		and absf(float(chunk.get_preview_state().get("gantry_progress", -1.0)) - 0.5) < 0.001
		and not _path_exists(host.grid, Vector3(12.0, 0.0, 0.0), Vector3(22.0, 0.0, 0.0)),
		"same-instance idempotent restore retracts landed gantry and bridge topology")
	host.scheduler.advance_ticks(chunk.GANTRY_FALL_SECS * 0.5 - 0.001)
	check(not bool(chunk.get_preview_state().get("bridge_down", true)),
		"restored gantry cannot land before its original deadline")
	host.scheduler.advance_ticks(0.001)
	check(bool(chunk.get_preview_state().get("bridge_down", false)),
		"restored gantry lands once at its original deadline")

	var fresh_gantry_pair := await _boot_lockout()
	var fresh_gantry_host = fresh_gantry_pair.host
	var fresh_gantry = fresh_gantry_pair.chunk
	_apply_capture(fresh_gantry_host, fresh_gantry, gantry_midpoint)
	fresh_gantry.headless_process(0.0)
	check(str(fresh_gantry.get_preview_state().get("gantry_phase", "")) == "falling"
		and absf(float(fresh_gantry.get_preview_state().get("gantry_progress", -1.0)) - 0.5) < 0.001,
		"fresh presenter reconstructs the saved gantry angle and remainder")
	fresh_gantry_host.scheduler.advance_ticks(fresh_gantry.GANTRY_FALL_SECS * 0.5)
	check(bool(fresh_gantry.get_preview_state().get("bridge_down", false)),
		"fresh gantry restore lands at the saved absolute deadline")

	# Door phase authority is independent of the gantry; use a fresh baseline so the trench cannot
	# obscure the local west/east path assertion around x=42.
	var door_pair := await _boot_lockout()
	var door_host = door_pair.host
	var door = door_pair.chunk
	door.set_pursuit_start_deferred(true)
	check(_trigger_exact_source(door_host, door._boundary_scanner, "aster"),
		"door fixture begins through the exact boundary scanner")
	var door_baseline := _capture(door_host)
	check(_trigger_exact_source(door_host, door._service_door, "peris"),
		"door fixture consumes the exact nearby door source")
	var close_deadline := float(door._door_phase_deadline)
	check(not door._service_door._trigger(),
		"door input spam is rejected by the spent physical source")
	check(str(door.get_preview_state().get("door_phase", "")) == "closing"
		and is_equal_approx(float(door._door_phase_deadline), close_deadline),
		"door input spam cannot retarget or skip its closing phase")
	check(_path_exists(door_host.grid, Vector3(38.0, 0.0, 0.0), Vector3(46.0, 0.0, 0.0)),
		"doorway remains truthfully passable while the leaf is still crossing")
	door_host.scheduler.advance_ticks(door.DOOR_CLOSE_SECS * 0.5)
	door.headless_process(0.0)
	var door_midpoint := _capture(door_host)
	var door_mid: Dictionary = door.get_preview_state()
	check(absf(float(door_mid.get("door_phase_progress", -1.0)) - 0.5) < 0.001
		and float(door._service_door_slab.position.z) > 0.0
		and float(door._service_door_slab.position.z) < door._service_door_open_z(),
		"door midpoint is a visible in-flight leaf, not a flag or endpoint swap")
	door_host.scheduler.advance_ticks(door.DOOR_CLOSE_SECS * 0.5)
	check(str(door.get_preview_state().get("door_phase", "")) == "sealed"
		and bool(door.get_preview_state().get("door_blocking", false))
		and not _path_exists(door_host.grid, Vector3(38.0, 0.0, 0.0), Vector3(46.0, 0.0, 0.0)),
		"seated door commits the full navigation barrier only on physical arrival")
	door._begin_door_breach("fixture_cutter")
	door_host.scheduler.advance_ticks(door.DOOR_HOLD_SECS * 0.5)
	door.headless_process(0.0)
	check(str(door.get_preview_state().get("door_phase", "")) == "breaching"
		and bool(door.get_preview_state().get("door_blocking", false)),
		"mid-breach door still holds the whole pack behind physical topology")
	door_host.scheduler.advance_ticks(door.DOOR_HOLD_SECS * 0.5)
	check(str(door.get_preview_state().get("door_phase", "")) == "opening"
		and bool(door.get_preview_state().get("door_blocking", false)),
		"cutting the track begins a saved opening phase without early path access")
	door_host.scheduler.advance_ticks(door.DOOR_OPEN_SECS)
	check(str(door.get_preview_state().get("door_phase", "")) == "breached"
		and not bool(door.get_preview_state().get("door_blocking", true))
		and _path_exists(door_host.grid, Vector3(38.0, 0.0, 0.0), Vector3(46.0, 0.0, 0.0)),
		"damaged leaf clears the route only after its opening transit arrives")

	_apply_capture(door_host, door, door_midpoint)
	_apply_capture(door_host, door, door_midpoint)
	door.headless_process(0.0)
	check(str(door.get_preview_state().get("door_phase", "")) == "closing"
		and absf(float(door.get_preview_state().get("door_phase_progress", -1.0)) - 0.5) < 0.001
		and _path_exists(door_host.grid, Vector3(38.0, 0.0, 0.0), Vector3(46.0, 0.0, 0.0)),
		"same-instance rollback retracts breached topology to the saved closing midpoint")
	door_host.scheduler.advance_ticks(door.DOOR_CLOSE_SECS * 0.5 - 0.001)
	check(not bool(door.get_preview_state().get("door_blocking", true)),
		"restored closing door cannot block before its saved seat deadline")
	door_host.scheduler.advance_ticks(0.001)
	check(bool(door.get_preview_state().get("door_blocking", false)),
		"restored closing door seats exactly once at its saved deadline")

	var fresh_door_pair := await _boot_lockout()
	var fresh_door_host = fresh_door_pair.host
	var fresh_door = fresh_door_pair.chunk
	_apply_capture(fresh_door_host, fresh_door, door_midpoint)
	fresh_door.headless_process(0.0)
	check(str(fresh_door.get_preview_state().get("door_phase", "")) == "closing"
		and absf(float(fresh_door.get_preview_state().get("door_phase_progress", -1.0)) - 0.5) < 0.001,
		"fresh presenter reconstructs the same physical door midpoint")
	fresh_door_host.scheduler.advance_ticks(fresh_door.DOOR_CLOSE_SECS * 0.5)
	check(bool(fresh_door.get_preview_state().get("door_blocking", false)),
		"fresh door restore commits topology at the saved deadline")

	# Absence is construction truth: a reused presenter cannot retain either future mechanism.
	_apply_capture(door_host, door, door_baseline)
	check(str(door.get_preview_state().get("door_phase", "")) == "open"
		and not bool(door.get_preview_state().get("door_blocking", true)),
		"missing chase authority retracts a reused door to its open construction state")
	_apply_capture(host, chunk, baseline)
	check(str(chunk.get_preview_state().get("gantry_phase", "")) == "standing"
		and not bool(chunk.get_preview_state().get("bridge_down", true)),
		"missing chase authority retracts a reused gantry to its standing construction state")

	await _discard(host)
	await _discard(fresh_gantry_host)
	await _discard(door_host)
	await _discard(fresh_door_host)


func _verify_portal_follow_authority() -> void:
	var pair := await _boot_lockout()
	var host = pair.host
	var chunk = pair.chunk
	chunk._spawn_wave(1, false, 2.0)
	var enemies: Array = chunk.enemies()
	check(enemies.size() == 1, "portal-follow fixture has one authoritative pursuer")
	if enemies.is_empty():
		await _discard(host)
		return
	var pursuer = enemies[0]
	var pursuer_id := str(pursuer.char_id)
	var source: Vector3 = chunk._pad_in.get_data_source()
	var destination: Vector3 = chunk._pad_in.get_data_destination()
	check(_path_exists(host.grid, destination, destination + Vector3(4.0, 0.0, 0.0))
		and not _path_exists(host.grid, source, destination),
		"offshoot floor is navigable inside while remaining portal-only from the corridor")

	# The quarry is physically inside the disconnected pocket and the pursuer has reached the
	# visible source pad. Enter pursuit without waiting through the separate alert presentation.
	host.game_state.snap_character_to("aster", destination + Vector3(0.4, 0.0, 0.0))
	host.game_state.snap_character_to("peris", destination + Vector3(1.0, 0.0, 1.0))
	pursuer.re_post(source)
	pursuer._current_target_id = "aster"
	pursuer._last_known_target_pos = destination
	pursuer._change_state("pursuit")
	var before_entry := _capture(host)
	chunk._arm_portal_follow()
	var entry: Dictionary = host.game_state.get_external_traversal_state(pursuer_id)
	check(host.game_state.is_external_traversal_active(pursuer_id)
		and str(entry.get("traversal_id", ""))
		== str(chunk._portal_follow_traversal_id(pursuer_id, "enter"))
		and not host.game_state.command_move_to_pos(pursuer_id, Vector3(chunk.WALL_X, 0.0, 0.0)),
		"open entrance commits a locked PortalPad/GameState traversal, not an endpoint snap")
	host.scheduler.advance_ticks(chunk.PORTAL_FOLLOW_TRANSIT_SECS * 0.5)
	var entry_midpoint := _capture(host)
	var entry_mid: Dictionary = host.game_state.get_external_traversal_state(pursuer_id)
	var entry_mid_pos: Vector3 = host.game_state.get_position(pursuer_id)
	check(absf(float(entry_mid.get("progress", -1.0)) - 0.5) < 0.001
		and entry_mid_pos.distance_to(source) > 0.1
		and entry_mid_pos.distance_to(destination) > 0.1,
		"portal follower has a visible analytic midpoint observed by gameplay authority")
	host.scheduler.advance_ticks(chunk.PORTAL_FOLLOW_TRANSIT_SECS * 0.5)
	check(not host.game_state.is_external_traversal_active(pursuer_id)
		and host.game_state.get_position(pursuer_id).distance_to(destination) < 0.001,
		"portal follower commits the pocket endpoint only at the saved arrival tick")

	_apply_capture(host, chunk, entry_midpoint)
	_apply_capture(host, chunk, entry_midpoint)
	var rolled: Dictionary = host.game_state.get_external_traversal_state(pursuer_id)
	check(host.game_state.is_external_traversal_active(pursuer_id)
		and absf(float(rolled.get("progress", -1.0)) - 0.5) < 0.001,
		"same-instance idempotent restore retracts the follower into its saved portal midpoint")
	host.scheduler.advance_ticks(chunk.PORTAL_FOLLOW_TRANSIT_SECS * 0.5)
	check(not host.game_state.is_external_traversal_active(pursuer_id)
		and host.game_state.get_position(pursuer_id).distance_to(destination) < 0.001,
		"restored portal follower arrives exactly once at the original endpoint")

	var fresh_pair := await _boot_lockout()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, entry_midpoint)
	var fresh_mid: Dictionary = fresh_host.game_state.get_external_traversal_state(pursuer_id)
	check(fresh._enemy_by_id(pursuer_id) != null
		and fresh_host.game_state.is_external_traversal_active(pursuer_id)
		and absf(float(fresh_mid.get("progress", -1.0)) - 0.5) < 0.001,
		"fresh presenter reconstructs the pursuer and its in-flight portal body")
	fresh_host.scheduler.advance_ticks(fresh.PORTAL_FOLLOW_TRANSIT_SECS * 0.5)
	check(not fresh_host.game_state.is_external_traversal_active(pursuer_id)
		and fresh_host.game_state.get_position(pursuer_id).distance_to(destination) < 0.001,
		"fresh portal restore preserves the original arrival deadline")

	# Absence is also authoritative: rolling back before commitment must remove both transit and
	# its destination progress instead of leaving an invisible or duplicated traveller behind.
	_apply_capture(host, chunk, before_entry)
	check(not host.game_state.is_external_traversal_active(pursuer_id)
		and Vector2(host.game_state.get_position(pursuer_id).x - source.x,
			host.game_state.get_position(pursuer_id).z - source.z).length() < 0.001,
		"absence restore retracts portal transit to the physically reached source pad")

	# Returning uses the same visible mechanism in reverse. It cannot begin from arbitrary pocket
	# space; the recurring director first issues an ordinary walk back to the receiver.
	pursuer = chunk._enemy_by_id(pursuer_id)
	pursuer._change_state("idle")
	host.game_state.snap_character_to(pursuer_id, destination + Vector3(4.0, 0.0, 0.0))
	chunk._arm_portal_follow()
	check(not host.game_state.is_external_traversal_active(pursuer_id)
		and host.game_state.is_moving(pursuer_id),
		"pocket egress walks to the portal receiver instead of teleporting from arbitrary space")
	host.game_state.command_stop(pursuer_id)
	host.game_state.snap_character_to(pursuer_id, destination)
	chunk._arm_portal_follow()
	var return_leg: Dictionary = host.game_state.get_external_traversal_state(pursuer_id)
	check(str(return_leg.get("traversal_id", ""))
		== str(chunk._portal_follow_traversal_id(pursuer_id, "return")),
		"a pursuer at the receiver commits the explicit reverse portal traversal")
	host.scheduler.advance_ticks(chunk.PORTAL_FOLLOW_TRANSIT_SECS)
	check(not host.game_state.is_external_traversal_active(pursuer_id)
		and host.game_state.get_position(pursuer_id).distance_to(source) < 0.001,
		"reverse portal transit lands at the corridor endpoint")

	# A chase reset unregisters the pursuer; GameState cancellation owns any in-flight portal state.
	pursuer._change_state("idle")
	host.game_state.snap_character_to(pursuer_id, destination)
	chunk._arm_portal_follow()
	check(host.game_state.is_external_traversal_active(pursuer_id),
		"reset fixture starts with an in-flight portal follower")
	chunk._restart_fragment()
	check(not host.game_state.characters.has(pursuer_id)
		and not host.game_state.is_external_traversal_active(pursuer_id)
		and chunk.enemies().is_empty(),
		"full chase reset cancels portal transit and removes its pursuer without a stale callback")

	var source_text := FileAccess.get_file_as_string(
		"res://scripts/fragments/chunks/lockout_chase_chunk.gd")
	check(not source_text.contains("snap_character_to(enemy.char_id, _pad_in")
		and not source_text.contains("snap_character_to(enemy2.char_id, _pad_in")
		and source_text.contains("begin_external_transit"),
		"source guard forbids bespoke portal hops and retains the PortalPad authority seam")

	await _discard(host)
	await _discard(fresh_host)


func _verify_enemy_clamber_authority() -> void:
	var pair := await _boot_lockout()
	var host = pair.host
	var chunk = pair.chunk
	chunk._spawn_wave(2, false, 2.0)
	var enemies: Array = chunk.enemies()
	check(enemies.size() >= 2, "enemy clamber fixture has two authoritative pursuers")
	if enemies.size() < 2:
		await _discard(host)
		return
	var climber = enemies[0]
	var climber_id := str(climber.char_id)
	host.game_state.snap_character_to("aster", Vector3(chunk.BARRICADE_X1 + 8.0, 0.0, -1.0))
	host.game_state.snap_character_to("peris", Vector3(chunk.BARRICADE_X1 + 8.0, 0.0, 1.0))
	var clamber_origin := Vector3(chunk.BARRICADE_X0 - 2.0, 0.0, 0.0)
	host.game_state.snap_character_to(climber_id, clamber_origin)
	check(chunk._begin_barricade_clamber(host.game_state, climber, clamber_origin),
		"pursuer commits the barricade's ascent traversal")
	var started: Dictionary = host.game_state.get_external_traversal_state(climber_id)
	check(str(started.get("traversal_id", "")) == str(chunk._barricade_up_traversal_id(climber_id))
		and not host.game_state.command_move_to_pos(climber_id, Vector3(chunk.WALL_X, 0.0, 0.0)),
		"barricade ascent is a locked GameState movement state, not a delayed teleport")
	host.scheduler.advance_ticks(chunk.BARRICADE_ENEMY_CLAMBER_SECS * 0.25)
	var barricade_midpoint := _capture(host)
	var mid_state: Dictionary = host.game_state.get_external_traversal_state(climber_id)
	var mid_pos: Vector3 = host.game_state.get_position(climber_id)
	check(absf(float(mid_state.get("progress", -1.0)) - 0.5) < 0.001
		and mid_pos.x > clamber_origin.x and mid_pos.x < (chunk.BARRICADE_X0 + chunk.BARRICADE_X1) * 0.5
		and mid_pos.y > 0.0,
		"pursuer has an analytic raised barricade midpoint")
	host.scheduler.advance_ticks(chunk.BARRICADE_ENEMY_CLAMBER_SECS * 0.25)
	check(str(host.game_state.get_external_traversal_state(climber_id).get("traversal_id", ""))
		== str(chunk._barricade_down_traversal_id(climber_id)),
		"arrival at the crest commits the descent traversal instead of an endpoint snap")
	host.scheduler.advance_ticks(chunk.BARRICADE_ENEMY_CLAMBER_SECS * 0.5)
	check(not host.game_state.is_external_traversal_active(climber_id)
		and host.game_state.get_position(climber_id).x > chunk.BARRICADE_X1,
		"pursuer physically completes both barricade traversal stages")

	_apply_capture(host, chunk, barricade_midpoint)
	_apply_capture(host, chunk, barricade_midpoint)
	check(host.game_state.is_external_traversal_active(climber_id)
		and str(host.game_state.get_external_traversal_state(climber_id).get("traversal_id", ""))
		== str(chunk._barricade_up_traversal_id(climber_id)),
		"same-instance rollback restores the pursuer inside its ascent state")
	host.scheduler.advance_ticks(chunk.BARRICADE_ENEMY_CLAMBER_SECS * 0.75)
	check(not host.game_state.is_external_traversal_active(climber_id)
		and host.game_state.get_position(climber_id).x > chunk.BARRICADE_X1,
		"restored pursuer chains crest and descent exactly once")

	var fresh_pair := await _boot_lockout()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, barricade_midpoint)
	check(fresh_host.game_state.is_external_traversal_active(climber_id)
		and fresh._enemy_by_id(climber_id) != null,
		"fresh presenter reconstructs both the pursuer and its active barricade traversal")
	fresh_host.scheduler.advance_ticks(fresh.BARRICADE_ENEMY_CLAMBER_SECS * 0.75)
	check(not fresh_host.game_state.is_external_traversal_active(climber_id)
		and fresh_host.game_state.get_position(climber_id).x > fresh.BARRICADE_X1,
		"fresh restored pursuer reaches the authored far landing")

	# The crowd governor's next body now climbs over the prone body instead of being stunned in place.
	var pile_pair := await _boot_lockout()
	var pile_host = pile_pair.host
	var pile_chunk = pile_pair.chunk
	pile_chunk._spawn_wave(2, false, 2.0)
	var pile_enemies: Array = pile_chunk.enemies()
	var fallen = pile_enemies[0]
	var follower = pile_enemies[1]
	var pin: Array = pile_chunk.PINCHES[0]
	var px := float(pin[0])
	var gz := float(pin[1])
	pile_host.game_state.snap_character_to(str(fallen.char_id), Vector3(px, 0.0, gz))
	fallen.stun(8.0)
	pile_chunk._fallen[str(fallen.char_id)] = true
	pile_host.game_state.snap_character_to(str(follower.char_id), Vector3(px - 1.0, 0.0, gz))
	pile_host.game_state.command_move_to_pos(str(follower.char_id), Vector3(px + 4.0, 0.0, gz))
	pile_chunk._pinch_rule(pile_host.game_state, pile_host.scheduler.get_current_tick())
	var pile_started: Dictionary = pile_host.game_state.get_external_traversal_state(str(follower.char_id))
	check(str(pile_started.get("traversal_id", "")).begins_with("lockout_pinch_up:0:1:")
		and not follower.is_stunned(),
		"body-pile follower enters a real ascent state rather than a proxy stun")
	pile_host.scheduler.advance_ticks(pile_chunk.CLIMB_SECS * 0.25)
	var pile_midpoint := _capture(pile_host)
	var pile_mid: Vector3 = pile_host.game_state.get_position(str(follower.char_id))
	check(pile_mid.y > 0.0 and pile_mid.x > px - 1.0 and pile_mid.x < px + 0.1,
		"body-pile traversal exposes a raised analytic midpoint")
	pile_host.scheduler.advance_ticks(pile_chunk.CLIMB_SECS * 0.75)
	check(not pile_host.game_state.is_external_traversal_active(str(follower.char_id))
		and pile_host.game_state.get_position(str(follower.char_id)).x >= px + pile_chunk.PINCH_CLAMBER_EXIT_X - 0.01,
		"body-pile follower descends beyond the physical obstacle")

	var fresh_pile_pair := await _boot_lockout()
	var fresh_pile_host = fresh_pile_pair.host
	var fresh_pile = fresh_pile_pair.chunk
	_apply_capture(fresh_pile_host, fresh_pile, pile_midpoint)
	check(fresh_pile_host.game_state.is_external_traversal_active(str(follower.char_id)),
		"fresh presenter restores the follower midway over the body pile")
	fresh_pile_host.scheduler.advance_ticks(fresh_pile.CLIMB_SECS * 0.75)
	check(not fresh_pile_host.game_state.is_external_traversal_active(str(follower.char_id))
		and fresh_pile_host.game_state.get_position(str(follower.char_id)).x >= px + fresh_pile.PINCH_CLAMBER_EXIT_X - 0.01,
		"fresh body-pile restore completes the same authored landing")

	await _discard(host)
	await _discard(fresh_host)
	await _discard(pile_host)
	await _discard(fresh_pile_host)


func _verify_hushbloom_inventory_authority() -> void:
	var pair := await _boot_lockout()
	var host = pair.host
	var chunk = pair.chunk
	var blooms: Array = chunk.hushblooms()
	check(not blooms.is_empty(), "Lockout inventory fixture has a real pickable Hushbloom")
	if blooms.is_empty():
		await _discard(host)
		return
	var bloom: Hushbloom = blooms[0]
	var baseline := _capture(host)
	var pickup_seam := {"capture": {}, "count": 0}
	host.game_state.item_picked_up.connect(func(char_id: String, picked_item_id: String) -> void:
		if char_id != "aster" or int(pickup_seam.get("count", 0)) > 0 \
				or not host.game_state.items.has(picked_item_id):
			return
		var item: Dictionary = host.game_state.items[picked_item_id]
		if str(item.get("type", "")) != "hushbloom":
			return
		pickup_seam["count"] = 1
		pickup_seam["capture"] = _capture(host))
	host.game_state.snap_character_to("aster", bloom.position)
	bloom.active_character = "aster"
	check(bloom.pick(), "Aster physically picks the charged Hushbloom")
	var held: Array = host.game_state.get_hand_items("aster")
	var item_id := str(held[0]) if not held.is_empty() else ""
	check(item_id != "" and host.game_state.items.has(item_id)
			and str((host.game_state.items[item_id] as Dictionary).get("type", "")) == "hushbloom"
			and int(chunk.get_preview_state().get("bloom_carry", 0)) == 1,
		"Lockout derives its carry readout from one canonical hand item")
	var picked := _capture(host)

	# A dropped flower exists where its holder set it down, but cannot remotely pay a portal seal.
	check(host.game_state.drop_item("aster", item_id),
		"ordinary inventory drop sets the picked bloom down")
	var seal: Interactable = chunk.find_child("SealPadIn", true, false) as Interactable
	var pad: PortalPad = chunk._pad_in
	host.game_state.snap_character_to("aster", seal.position)
	seal.active_character = "aster"
	check(not chunk._on_seal_interacted(seal, pad),
		"direct seal helper has no accepted physical-source receipt")
	check(not seal._trigger(), "seal source rejects a nearby body without a held bloom")
	check(not pad.is_stunned() and host.game_state.items.has(item_id)
			and int(chunk.get_preview_state().get("bloom_carry", -1)) == 0,
		"a bloom on the ground cannot be spent through a chunk counter")

	# Pickup and transfer are ordinary GameState operations. The character who actually holds the
	# item—not the selected portrait or its original picker—owns the seal affordance.
	host.game_state.snap_character_to("aster", bloom.position)
	check(host.game_state.pick_up_item("aster", item_id), "Aster can recover the same dropped item")
	host.game_state.snap_character_to("peris", bloom.position + Vector3(0.5, 0.0, 0.0))
	check(host.game_state.transfer_item("aster", "peris", item_id),
		"the physical Hushbloom can transfer between party members")
	host.game_state.snap_character_to("aster", seal.position)
	host.game_state.snap_character_to("peris", seal.position + Vector3(0.5, 0.0, 0.0))
	seal.active_character = "aster"
	check(not seal._trigger(), "the former holder cannot trigger Peris's bloom")
	check(not pad.is_stunned() and host.game_state.items.has(item_id),
		"the former holder cannot spend Peris's bloom")
	seal.active_character = "peris"
	var accepted_source_capture := {"value": {}}
	var capture_seal_acceptance := func(source_data_id: String, _actor: String) -> void:
		if source_data_id == str(seal.data_id) \
				and (accepted_source_capture.value as Dictionary).is_empty():
			accepted_source_capture.value = _capture(host)
	host.game_state.interactable_triggered.connect(capture_seal_acceptance)
	check(seal._trigger(), "the actual holder triggers the exact seal source")
	host.game_state.interactable_triggered.disconnect(capture_seal_acceptance)
	check(pad.is_stunned() and not host.game_state.items.has(item_id)
			and host.game_state.get_hand_items("peris").is_empty(),
		"the actual holder consumes the item and commits PortalPad's saved stun")
	check(not (accepted_source_capture.value as Dictionary).is_empty(),
		"save captured the accepted seal source before chunk consequence dispatch")
	_apply_capture(host, chunk, accepted_source_capture.value)
	check(pad.is_stunned() and not host.game_state.items.has(item_id)
			and int(chunk._seal_trigger_consumed.get(str(seal.data_id), 0)) == 1,
		"accepted-source restore finishes the exact bloom spend and portal effect")
	var reconciled_seal := _capture(host)
	_apply_capture(host, chunk, reconciled_seal)
	_apply_capture(host, chunk, reconciled_seal)
	check(pad.is_stunned() and not host.game_state.items.has(item_id)
			and int(chunk._seal_trigger_consumed.get(str(seal.data_id), 0)) == 1,
		"repeated restore cannot duplicate or retract the committed seal receipt")

	# The generic pickup publishes a reservation before GameState emits item_picked_up. Lockout must
	# not consume that pending item until the restored deterministic finalizer has run.
	var pending_pair := await _boot_lockout()
	var pending_host = pending_pair.host
	var pending = pending_pair.chunk
	_apply_capture(pending_host, pending, pickup_seam.get("capture", {}) as Dictionary)
	var pending_items: Array = pending_host.game_state.get_hand_items("aster")
	var pending_item_id := str(pending_items[0]) if not pending_items.is_empty() else ""
	var pending_seal: Interactable = pending.find_child("SealPadIn", true, false) as Interactable
	pending_host.game_state.snap_character_to("aster", pending_seal.position)
	pending_seal.active_character = "aster"
	check(not pending_seal._trigger(),
		"seal source refuses a signal-time PICKING item")
	check(pending_item_id != "" and pending_host.game_state.items.has(pending_item_id)
			and not pending._pad_in.is_stunned(),
		"portal refuses a signal-time PICKING item before its source transaction finalizes")
	pending_host.scheduler.advance_ticks(0.0)
	check(pending_seal._trigger(),
		"seal source accepts the finalized exact held item")
	check(not pending_host.game_state.items.has(pending_item_id) and pending._pad_in.is_stunned(),
		"the same restored item becomes spendable exactly once after deterministic finalization")

	# Restore the pre-spend pickup on a fresh chunk: item identity, holder, and source plant all agree.
	var fresh_pair := await _boot_lockout()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, picked)
	var fresh_bloom: Hushbloom = fresh.hushblooms()[0]
	check(fresh_host.game_state.items.has(item_id)
			and str((fresh_host.game_state.items[item_id] as Dictionary).get("holder", "")) == "aster"
			and not fresh_bloom.visible
			and int(fresh.get_preview_state().get("bloom_carry", 0)) == 1,
		"fresh restore reconstructs the exact held item and absent source plant")
	_apply_capture(host, chunk, baseline)
	# Lockout now seeds Tyreg's finite physical magazine at construction, so the baseline inventory
	# is intentionally non-empty. The rollback contract is about the future bloom's exact identity:
	# it disappears while its one source plant returns charged; unrelated baseline items remain.
	check(not host.game_state.items.has(item_id) and bloom.visible and bloom.is_charged(),
		"same-instance baseline rollback retracts the future bloom and regrows only its source plant")

	await _discard(host)
	await _discard(fresh_host)
	await _discard(pending_host)


func _verify_pair_roles_and_static_guards() -> void:
	var pair := await _boot_lockout()
	var host = pair.host
	var chunk = pair.chunk
	var clamber: CrawlTunnel = chunk._clamber
	var mouth := Vector3(chunk.BARRICADE_X0 - 1.2, 0.0, 0.0)
	host.game_state.snap_character_to("aster", mouth)
	host.game_state.snap_character_to("peris", Vector3(4.0, 0.0, 0.0))
	clamber.active_character = "aster"
	clamber._on_interacted()
	check(not host.game_state.is_moving("aster"),
		"remote party presence cannot satisfy the physical boost role")
	host.game_state.snap_character_to("peris", mouth + Vector3(-1.4, 0.0, 1.0))
	clamber._on_interacted()
	check(not host.game_state.is_moving("aster"),
		"a direct clamber callback cannot substitute for its physical source receipt")
	check(clamber._trigger(false),
		"the nearby climber consumes the exact barricade source with a booster present")
	var first_crawl_authority: Dictionary = host.game_state.get_world_state(
		clamber._crawl_authority_key(), {})
	check(not (first_crawl_authority.get("activation_receipt", {}) as Dictionary).is_empty() \
		and not (first_crawl_authority.get("phases", {}) as Dictionary).is_empty(),
		"accepted boost records its climber receipt and pending begin phase before movement")
	host.scheduler.advance_ticks(0.06)
	check(host.game_state.is_external_traversal_active("aster") \
		and not host.game_state.is_external_traversal_active("peris")
		and host.game_state.get_character_concealment("aster") == GameState.CONCEAL_NONE,
		"partner below boosts one exposed climber into a recorded traversal instead of teleporting a selected group")
	host.scheduler.advance_ticks(3.94)
	check(host.game_state.get_position("aster").x > chunk.BARRICADE_X1
		and host.game_state.get_position("peris").x < chunk.BARRICADE_X0,
		"first climber reaches the top while the booster remains physically below")
	host.game_state.snap_character_to("peris", mouth)
	clamber.active_character = "peris"
	check(clamber._trigger(false),
		"the partner at the mouth consumes a second exact source receipt with a puller above")
	host.scheduler.advance_ticks(0.06)
	check(host.game_state.is_external_traversal_active("peris"),
		"first climber's top-side position commits the partner's recorded pull traversal")
	host.scheduler.advance_ticks(3.94)
	check(host.game_state.get_position("peris").x > chunk.BARRICADE_X1,
		"pulled partner completes the authored crawl state")

	var source := FileAccess.get_file_as_string(
		"res://scripts/fragments/chunks/lockout_chase_chunk.gd")
	check(not source.contains("_barricade_wait")
		and not source.contains("snap_character_to(enemy.char_id, Vector3(BARRICADE_X1")
		and not source.contains("enemy2.stun(minf(CLIMB_SECS"),
		"source guard forbids delayed endpoint snaps and stun-as-climb regressions")
	check(source.contains("command_external_traversal")
		and source.contains("DOOR_PHASE_BREACHING")
		and source.contains("GANTRY_PHASE_FALLING"),
		"source guard retains authoritative traversal and multi-phase mechanism seams")
	check(not source.contains("var _bloom_carry")
		and source.contains("get_hand_items")
		and source.contains("remove_item(item_id)"),
		"source guard forbids a Hushbloom counter and retains canonical inventory consumption")
	await _discard(host)


func _boot_lockout() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = LockoutScene.instantiate()
	chunk.attach_chunk_host(host, "lockout_chase")
	host.add_child(chunk)
	await process_frame
	host.register_party(chunk.get_spawn_positions())
	host.grid = GridWorld.from_data(chunk.get_grid_data())
	host.game_state.grid = host.grid
	chunk.reset_preview_state()
	chunk.headless_process(0.0)
	await process_frame
	return {"host": host, "chunk": chunk}


func _source_position(host, source: Interactable) -> Vector3:
	if host.game_state.has_interactable(source.data_id):
		return host.game_state.get_interactable(source.data_id).get(
			"position", source.position) as Vector3
	return source.position


func _trigger_exact_source(host, source: Interactable, actor: String) -> bool:
	host.game_state.snap_character_to(actor, _source_position(host, source))
	source.active_character = actor
	return source._trigger(false)


func _path_exists(grid: GridWorld, from_world: Vector3, to_world: Vector3) -> bool:
	return not grid.find_path(grid.world_to_grid(from_world), grid.world_to_grid(to_world)).is_empty()


func _capture(host) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _apply_capture(host, chunk, capture: Dictionary) -> void:
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
