extends SceneTree

## Production-shaped midpoint rollback and fresh-presenter coverage for the two showcase chunks.
## The scheduler heap is cleared before GameState is installed, exactly as TutorialSequence loads.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const SetPieceScene := preload("res://scenes/fragments/chunks/set_piece_showcase_chunk.tscn")
const BossScene := preload("res://scenes/fragments/chunks/boss_showcase_chunk.tscn")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	_verify_boss_strict_future_boundary()
	await _verify_set_piece_control_source_authority()
	await _verify_hub_and_trolley_transit_authority()
	await _verify_set_piece_midpoints()
	await _verify_plate_stripping_authority()
	await _verify_hoist_payload_truth()
	await _verify_plate_drop_location_truth()
	await _verify_boss_prize_authority()
	await _verify_boss_midpoints()
	print("SET PIECE SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_boss_strict_future_boundary() -> void:
	var chunk = BossScene.instantiate()
	chunk.set("_align_poll_epoch", 0.1)
	check(is_equal_approx(float(chunk.call("_next_align_poll_after", 0.35)), 0.6),
		"boss fractional alignment epoch reconstructs the next strict-future poll, not now")
	chunk.free()


func _verify_set_piece_control_source_authority() -> void:
	var pair := await _boot_set_piece()
	var host = pair.host
	var chunk = pair.chunk
	var wheel: Node = chunk._set_piece_control_for_action("wheel")
	var wheel_position: Vector3 = chunk._set_piece_control_data_position(wheel)
	host.active_character = "aster"
	host.game_state.snap_character_to("peris", wheel_position + Vector3(6.0, 0.0, 0.0))
	check(not _trigger_set_piece_control(host, chunk, "wheel", "peris", false)
			and str(chunk.get_preview_state().get("hub_phase", "")) == "idle",
		"selected portrait cannot let a distant servicing body turn the wheel")
	check(not chunk._on_wheel_pushed()
			and not chunk._on_valve_used()
			and not chunk._on_strut_pried()
			and not chunk._on_hoist_shunt()
			and not chunk._on_hoist_lever(),
		"direct set-piece handlers cannot manufacture a physical control receipt")
	var valve: Node = chunk._set_piece_control_for_action("valve")
	valve.interacted.emit()
	check(not bool(chunk.get_preview_state().get("filling", true)),
		"manually emitting a control signal cannot start its consequence")

	# Movement/action ownership belongs to the same body that uses the source. A nearby but locked
	# body cannot service it, and a different selected portrait cannot steal a ready body's receipt.
	host.game_state.snap_character_to("peris", wheel_position)
	var busy_destination := wheel_position + Vector3(0.2, 0.0, 0.0)
	check(host.game_state.command_external_traversal(
			"peris", &"verify_set_piece_busy", busy_destination,
			wheel_position, busy_destination, 1.0, &"locked"),
		"set-piece refusal fixture places Peris in an authoritative locked action")
	check(not _trigger_set_piece_control(host, chunk, "wheel", "peris", false)
			and str(chunk.get_preview_state().get("hub_phase", "")) == "idle",
		"a busy body cannot consume a set-piece control")
	host.game_state.cancel_external_traversal("peris", &"verify_complete")
	check(_trigger_set_piece_control(host, chunk, "wheel", "peris", false)
			and str(chunk.get_preview_state().get("hub_phase", "")) == "rotating",
		"the nearby ready body turns the wheel even while another portrait is selected")
	var wheel_spec: Dictionary = host.game_state.get_interactable(str(wheel.get("data_id")))
	check(not bool(wheel_spec.get("triggered", true))
			and int(wheel_spec.get("trigger_count", 0)) == 1,
		"the consumed repeatable wheel receipt is re-armed without erasing its trigger history")
	check(not chunk._on_wheel_pushed(wheel)
			and int(chunk.get_preview_state().get("hub_target_rot", -1)) == 1,
		"a stale source object cannot replay its already-consumed wheel receipt")
	host.scheduler.advance_ticks(chunk.HUB_ROTATE_TIME)

	# Capture the exact seam after GameState accepts the valve but before Interactable and the chunk
	# consume it. Restore must not strand a disabled source or grant the uncommitted water change.
	var accepted_box := {"capture": {}}
	var valve_id := str(valve.get("data_id"))
	var accepted_listener := func(interactable_id: String, _character_id: String) -> void:
		if interactable_id == valve_id and (accepted_box.capture as Dictionary).is_empty():
			accepted_box.capture = _capture(host)
	host.game_state.interactable_triggered.connect(accepted_listener)
	check(_trigger_set_piece_control(host, chunk, "valve", "peris")
			and bool(chunk.get_preview_state().get("filling", false)),
		"a real nearby valve interaction starts the saved fill phase")
	host.game_state.interactable_triggered.disconnect(accepted_listener)
	check(not (accepted_box.capture as Dictionary).is_empty(),
		"the accepted-source seam is observable before consequence commitment")
	_apply_capture(host, chunk, accepted_box.capture as Dictionary)
	check(not bool(chunk.get_preview_state().get("filling", true))
			and valve.is_interaction_enabled(),
		"same-instance accepted-source restore retracts the fill and re-arms the valve")
	var legacy_control_capture := (accepted_box.capture as Dictionary).duplicate(true)
	var legacy_game_state: Dictionary = legacy_control_capture.get("game_state", {})
	var legacy_interactables: Dictionary = legacy_game_state.get("interactables", {})
	var legacy_valve: Dictionary = legacy_interactables.get(valve_id, {})
	legacy_valve["one_shot"] = false
	legacy_valve["triggered"] = false
	legacy_valve["enabled"] = true
	legacy_interactables[valve_id] = legacy_valve
	legacy_game_state["interactables"] = legacy_interactables
	legacy_control_capture["game_state"] = legacy_game_state
	_apply_capture(host, chunk, legacy_control_capture)
	check(bool(host.game_state.get_interactable(valve_id).get("one_shot", false))
			and valve.is_interaction_enabled(),
		"legacy cycling-control registry migrates to an exact consumable receipt source")
	check(_trigger_set_piece_control(host, chunk, "valve", "peris")
			and bool(chunk.get_preview_state().get("filling", false)),
		"the restored valve can be physically retried exactly once")

	var fresh_pair := await _boot_set_piece()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, accepted_box.capture as Dictionary)
	var fresh_valve: Node = fresh._set_piece_control_for_action("valve")
	check(not bool(fresh.get_preview_state().get("filling", true))
			and fresh_valve.is_interaction_enabled(),
		"fresh presenter normalizes the accepted-but-uncommitted valve receipt")
	check(_trigger_set_piece_control(fresh_host, fresh, "valve", "peris")
			and bool(fresh.get_preview_state().get("filling", false)),
		"fresh presenter accepts the same physical retry without granting a duplicate outcome")
	await _discard(host)
	await _discard(fresh_host)

	# The strut is genuinely one-shot rather than a cycling control, but its pre-callback seam has
	# the same rule: accepted alone is not a falling slab. A restored uncommitted receipt is retryable;
	# after that retry, the slab and source become spent together at the physical deadline.
	var strut_pair := await _boot_set_piece()
	var strut_host = strut_pair.host
	var strut_chunk = strut_pair.chunk
	var strut: Node = strut_chunk._set_piece_control_for_action("strut")
	var strut_id := str(strut.get("data_id"))
	var strut_box := {"capture": {}}
	var strut_listener := func(interactable_id: String, _character_id: String) -> void:
		if interactable_id == strut_id and (strut_box.capture as Dictionary).is_empty():
			strut_box.capture = _capture(strut_host)
	strut_host.game_state.interactable_triggered.connect(strut_listener)
	check(_trigger_set_piece_control(strut_host, strut_chunk, "strut", "aster")
			and str(strut_chunk.get_preview_state().get("slab_phase", "")) == "falling",
		"the exact loose strut receipt starts the physical slab fall")
	strut_host.game_state.interactable_triggered.disconnect(strut_listener)
	check(not (strut_box.capture as Dictionary).is_empty(),
		"the one-shot strut exposes its accepted-source seam before the fall commitment")
	_apply_capture(strut_host, strut_chunk, strut_box.capture as Dictionary)
	check(str(strut_chunk.get_preview_state().get("slab_phase", "")) == "standing"
			and strut.is_interaction_enabled(),
		"accepted-source restore does not grant or strand the one-shot slab consequence")
	check(_trigger_set_piece_control(strut_host, strut_chunk, "strut", "aster")
			and not strut.is_interaction_enabled(),
		"the restored physical strut can be consumed once")
	strut_host.scheduler.advance_ticks(strut_chunk.CRUMBLE_DELAY)
	check(not bool(strut_chunk.get_preview_state().get("slab_intact", true))
			and not strut.is_interaction_enabled(),
		"the landed slab and spent one-shot source commit together exactly once")
	await _discard(strut_host)


func _verify_hub_and_trolley_transit_authority() -> void:
	var pair := await _boot_set_piece()
	var host = pair.host
	var chunk = pair.chunk
	var baseline := _capture(host)

	_trigger_set_piece_control(host, chunk, "hoist_lever") # begin lifting the stored plate
	var lift_started: Dictionary = chunk.get_preview_state()
	check(str(lift_started.get("magnet_phase", "")) == "lifting_plate"
			and str(lift_started.get("plate", "")) == "stored"
			and str(lift_started.get("magnet_carrying", "x")) == ""
			and not bool(lift_started.get("hoist_switch_enabled", true)),
		"magnet commitment starts a locked physical lift without granting the payload")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME * 0.5)
	chunk.headless_process(999.0)
	var lift_mid: Dictionary = chunk.get_preview_state()
	check(float(lift_mid.get("magnet_phase_progress", -1.0)) > 0.49
			and float(lift_mid.get("magnet_phase_progress", -1.0)) < 0.51
			and float((lift_mid.get("plate_position", Vector3.ZERO) as Vector3).y) > 0.12
			and float((lift_mid.get("plate_position", Vector3.ZERO) as Vector3).y) < chunk.MAGNET_HELD_Y,
		"plate presentation follows the saved lift midpoint rather than a cosmetic tween")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME * 0.5)
	check(str(chunk.get_preview_state().get("plate", "")) == "held",
		"plate becomes carried only on physical arrival at the magnet")
	_trigger_set_piece_control(host, chunk, "wheel")
	_trigger_set_piece_control(host, chunk, "hoist_switch")
	var committed: Dictionary = chunk.get_preview_state()
	check(str(committed.get("hub_phase", "")) == "rotating"
			and not bool(committed.get("hub_aligned", true))
			and not bool(committed.get("hub_wheel_enabled", true)),
		"hub commitment starts a locked rotation without opening topology")
	check(str(committed.get("trolley_phase", "")) == "travelling"
			and int(committed.get("trolley_station", -1)) == 0
			and int(committed.get("trolley_target_station", -1)) == 1
			and not bool(committed.get("hoist_switch_enabled", true))
			and not bool(committed.get("hoist_lever_enabled", true)),
		"trolley commitment owns an origin and target while both controls lock")
	check(str(committed.get("plate", "")) == "held"
			and absf(float(committed.get("trolley_x", -99.0)) - float(chunk.STATION_X[0])) < 0.001,
		"held payload and trolley remain at the origin on the commitment tick")
	var committed_record: Dictionary = host.game_state.get_world_state(
		chunk.set_piece_authority_key(), {})
	check(str(committed_record.get("hub_phase", "")) == "rotating"
			and is_equal_approx(float(committed_record.get("hub_rotation_deadline", -1.0)), 0.8)
			and str(committed_record.get("trolley_phase", "")) == "travelling"
			and is_equal_approx(float(committed_record.get("trolley_travel_deadline", -1.0)), 0.9),
		"portable authority records both phase identities and absolute arrival deadlines")

	# Direct handler spam is refused as well as the disabled interaction zones.
	chunk._on_wheel_pushed()
	chunk._on_hoist_shunt()
	chunk._on_hoist_lever()
	var spammed: Dictionary = chunk.get_preview_state()
	check(int(spammed.get("hub_target_rot", -1)) == 1
			and int(spammed.get("trolley_target_station", -1)) == 1
			and str(spammed.get("plate", "")) == "held",
		"mid-motion input spam cannot retarget, skip, or discharge either mechanism")

	host.scheduler.advance_ticks(0.2)
	chunk.headless_process(0.0)
	var midpoint := _capture(host)
	var mid: Dictionary = chunk.get_preview_state()
	check(absf(float(mid.get("hub_rotation_progress", -1.0)) - 0.5) < 0.001
			and absf(float(mid.get("trolley_travel_progress", -1.0)) - 0.4) < 0.001,
		"both mechanisms expose scheduler-derived midpoint progress")
	check(not bool(mid.get("hub_aligned", true))
			and int(mid.get("trolley_station", -1)) == 0
			and float(mid.get("trolley_x", 0.0)) > float(chunk.STATION_X[0])
			and float(mid.get("trolley_x", 0.0)) < float(chunk.STATION_X[1]),
		"midpoint presentation advances without committing either endpoint")

	host.scheduler.advance_ticks(0.2)
	check(bool(chunk.get_preview_state().get("hub_aligned", false))
			and int(chunk.get_preview_state().get("trolley_station", -1)) == 0,
		"the hub opens exactly at its own arrival while the trolley remains in flight")
	host.scheduler.advance_ticks(0.1)
	var arrived: Dictionary = chunk.get_preview_state()
	check(int(arrived.get("trolley_station", -1)) == 1
			and str(arrived.get("trolley_phase", "")) == "idle"
			and bool(arrived.get("hoist_switch_enabled", false))
			and bool(arrived.get("hoist_lever_enabled", false)),
		"trolley station and controls commit only on physical arrival")

	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	var rolled: Dictionary = chunk.get_preview_state()
	check(str(rolled.get("hub_phase", "")) == "rotating"
			and str(rolled.get("trolley_phase", "")) == "travelling"
			and not bool(rolled.get("hub_aligned", true))
			and int(rolled.get("trolley_station", -1)) == 0,
		"same-instance idempotent restore retracts both arrived endpoints")
	host.scheduler.advance_ticks(0.199)
	check(not bool(chunk.get_preview_state().get("hub_aligned", true)),
		"restored hub cannot open before its original deadline")
	host.scheduler.advance_ticks(0.002)
	check(bool(chunk.get_preview_state().get("hub_aligned", false)),
		"restored hub opens once at its original deadline")
	host.scheduler.advance_ticks(0.098)
	check(int(chunk.get_preview_state().get("trolley_station", -1)) == 0,
		"restored trolley cannot claim its target station early")
	host.scheduler.advance_ticks(0.002)
	check(int(chunk.get_preview_state().get("trolley_station", -1)) == 1,
		"restored trolley arrives once at its original deadline")

	# An absent authority record is a rollback to construction truth, not permission to retain future.
	var absent := baseline.duplicate(true)
	var absent_gs: Dictionary = absent.get("game_state", {}) as Dictionary
	var absent_world: Dictionary = absent_gs.get("world_state", {}) as Dictionary
	absent_world.erase(chunk.set_piece_authority_key())
	absent_gs["world_state"] = absent_world
	absent["game_state"] = absent_gs
	_apply_capture(host, chunk, absent)
	var retracted: Dictionary = chunk.get_preview_state()
	check(str(retracted.get("hub_phase", "")) == "idle"
			and int(retracted.get("hub_rot", -1)) == 0
			and str(retracted.get("trolley_phase", "")) == "idle"
			and int(retracted.get("trolley_station", -1)) == 0,
		"missing mechanism authority retracts a reused presenter to construction defaults")

	var fresh_pair := await _boot_set_piece()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, midpoint)
	var fresh_mid: Dictionary = fresh.get_preview_state()
	check(str(fresh_mid.get("hub_phase", "")) == "rotating"
			and str(fresh_mid.get("trolley_phase", "")) == "travelling"
			and absf(float(fresh_mid.get("trolley_x", 0.0)) - 12.5) < 0.01,
		"fresh presenter reconstructs both transit midpoints at saved progress")
	fresh_host.scheduler.advance_ticks(0.31)
	var coarse: Dictionary = fresh.get_preview_state()

	var fine_pair := await _boot_set_piece()
	var fine_host = fine_pair.host
	var fine = fine_pair.chunk
	_apply_capture(fine_host, fine, midpoint)
	for _step in range(31):
		fine_host.scheduler.advance_ticks(0.01)
	var fine_state: Dictionary = fine.get_preview_state()
	check(str(coarse.get("hub_phase", "")) == str(fine_state.get("hub_phase", ""))
			and int(coarse.get("hub_rot", -1)) == int(fine_state.get("hub_rot", -2))
			and str(coarse.get("trolley_phase", "")) == str(fine_state.get("trolley_phase", ""))
			and int(coarse.get("trolley_station", -1)) == int(fine_state.get("trolley_station", -2)),
		"coarse and fine scheduler steps produce identical hub and trolley outcomes")

	await _discard(host)
	await _discard(fresh_host)
	await _discard(fine_host)


func _verify_set_piece_midpoints() -> void:
	var pair := await _boot_set_piece()
	var host = pair.host
	var chunk = pair.chunk
	# Four independent commitments share one snapshot: aligned hub, filling basin, falling slab,
	# and a placed bridge plate that the live swarm is already committed to eat.
	_trigger_set_piece_control(host, chunk, "wheel")
	host.scheduler.advance_ticks(chunk.HUB_ROTATE_TIME)
	_trigger_set_piece_control(host, chunk, "hoist_lever") # station 0: begin lifting plate
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME)
	_trigger_set_piece_control(host, chunk, "hoist_switch")
	host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME) # station 1: over canal
	_trigger_set_piece_control(host, chunk, "hoist_lever") # begin dropping plate
	check(not host.game_state.grid.is_walkable(15, 19),
		"a descending plate cannot open the canal before impact")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME)
	check(host.game_state.grid.is_walkable(15, 19),
		"the plate opens canal topology exactly when its physical drop settles")
	var phase_start := float(host.scheduler.get_current_tick())
	_trigger_set_piece_control(host, chunk, "valve")
	_trigger_set_piece_control(host, chunk, "strut")
	host.scheduler.advance_ticks(0.4)
	var midpoint := _capture(host)
	var saved: Dictionary = host.game_state.get_world_state(chunk.set_piece_authority_key(), {})
	var saved_approachers: Array = saved.get("plate_approach_ids", []) as Array
	check(int(saved.get("hub_rot", -1)) == 1
			and is_equal_approx(float(saved.get("basin_fill_deadline", -1.0)), phase_start + 1.4)
			and is_equal_approx(float(saved.get("slab_fall_started_at", -1.0)), phase_start)
			and is_equal_approx(float(saved.get("slab_crumble_deadline", -1.0)), phase_start + 0.9)
			and saved_approachers.size() == 2
			and float(saved.get("plate_strip_deadline", -1.0)) < 0.0
			and not saved.has("plate_eat_deadline"),
		"set-piece record captures topology while both scraps still physically approach")
	for scrap_id in saved_approachers:
		check(host.game_state.get_external_traversal_state(str(scrap_id)).get(
			"traversal_id", &"") == chunk._plate_approach_traversal_id(str(scrap_id)),
			"%s's approach midpoint lives in GameState traversal authority" % str(scrap_id))

	# Discarded future: everything commits, and the hub is rotated away again.
	_trigger_set_piece_control(host, chunk, "wheel")
	host.scheduler.advance_ticks(7.0)
	var future: Dictionary = chunk.get_preview_state()
	check(int(future.get("water_level", -1)) == 1
			and not bool(future.get("slab_intact", true))
			and str(future.get("plate", "")) == "eaten",
		"future branch commits basin, slab, and plate decay")
	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint) # attachment pass is deliberately idempotent
	var rolled: Dictionary = chunk.get_preview_state()
	check(bool(rolled.get("hub_aligned", false))
			and int(rolled.get("water_level", -1)) == 0
			and bool(rolled.get("filling", false))
			and bool(rolled.get("slab_intact", false))
			and str(rolled.get("plate", "")) == "placed"
			and str(rolled.get("plate_strip_phase", "")) == "approaching",
		"same-instance rollback retracts all future mechanism topology")
	var restored_slab_progress := float(rolled.get("slab_fall_progress", -1.0))
	var restored_slab_angle := float(rolled.get("slab_angle", 0.0))
	check(str(rolled.get("slab_phase", "")) == "falling"
			and restored_slab_progress > 0.4 and restored_slab_progress < 0.5
			and restored_slab_angle < -0.5 and restored_slab_angle > -0.9,
		"rollback reconstructs the slab's visible saved fall midpoint")
	chunk.headless_process(1000.0)
	check(is_equal_approx(float(chunk.get_preview_state().get("slab_fall_progress", -1.0)), restored_slab_progress)
			and is_equal_approx(float(chunk.get_preview_state().get("slab_angle", 0.0)), restored_slab_angle),
		"render-frame work cannot advance the falling slab")
	check(host.game_state.grid.is_walkable(15, 19)
			and not host.game_state.grid.is_walkable(22, 9),
		"rollback rebuilds canal-open and basin-closed navigation truth")

	host.scheduler.advance_ticks(0.498)
	chunk.headless_process(0.0)
	check(bool(chunk.get_preview_state().get("slab_intact", false))
			and float(chunk.get_preview_state().get("slab_angle", 0.0)) < -1.4,
		"restored slab cannot fall before its original tick")
	host.scheduler.advance_ticks(0.003)
	check(not bool(chunk.get_preview_state().get("slab_intact", true)),
		"restored slab falls once at its original tick")
	host.scheduler.advance_ticks(0.496)
	check(int(chunk.get_preview_state().get("water_level", -1)) == 0,
		"restored basin cannot finish early")
	host.scheduler.advance_ticks(0.004)
	check(int(chunk.get_preview_state().get("water_level", -1)) == 1,
		"restored basin commits once at its original tick")
	var approach_remaining := _earliest_plate_approach_remaining(host, chunk)
	host.scheduler.advance_ticks(maxf(0.0, approach_remaining - 0.002))
	check(str(chunk.get_preview_state().get("plate_strip_phase", "")) == "approaching"
			and str(chunk.get_preview_state().get("plate", "")) == "placed",
		"restored scrap cannot begin stripping before physical contact")
	host.scheduler.advance_ticks(0.003)
	check(str(chunk.get_preview_state().get("plate_strip_phase", "")) == "stripping",
		"restored scrap begins the saved stripping phase only on arrival")
	host.scheduler.advance_ticks(chunk.PLATE_STRIP_TIME + 0.6)
	check(str(chunk.get_preview_state().get("plate", "")) == "eaten",
		"restored contacting scraps eventually consume the bridge")

	# A newly constructed chunk must present the same midpoint, not inherit its defaults.
	var fresh_pair := await _boot_set_piece()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, midpoint)
	var fresh_state: Dictionary = fresh.get_preview_state()
	check(bool(fresh_state.get("hub_aligned", false))
			and bool(fresh_state.get("filling", false))
			and bool(fresh_state.get("slab_intact", false))
			and str(fresh_state.get("plate", "")) == "placed"
			and str(fresh_state.get("plate_strip_phase", "")) == "approaching",
		"fresh presenter reconstructs the complete committed midpoint")
	check(str(fresh_state.get("slab_phase", "")) == "falling"
			and is_equal_approx(float(fresh_state.get("slab_angle", 0.0)), restored_slab_angle),
		"fresh presenter reconstructs the exact saved slab angle")
	fresh_host.scheduler.advance_ticks(0.5)
	check(not bool(fresh.get_preview_state().get("slab_intact", true)),
		"fresh presenter consumes only the slab's saved remainder")
	fresh_host.scheduler.advance_ticks(0.5)
	check(int(fresh.get_preview_state().get("water_level", -1)) == 1,
		"fresh presenter consumes only the basin's saved remainder")
	fresh_host.scheduler.advance_ticks(chunk.PLATE_STRIP_TIME + 3.6)
	check(str(fresh.get_preview_state().get("plate", "")) == "eaten",
		"fresh presenter completes saved approach plus contact stripping")
	await _discard(host)
	await _discard(fresh_host)


func _verify_plate_stripping_authority() -> void:
	# One live scrap makes the two phases and their interruption policy unambiguous: movement must
	# first reach the bridge, then a separately saved contact dwell consumes visible integrity.
	var pair := await _boot_set_piece()
	var host = pair.host
	var chunk = pair.chunk
	var baseline := _capture(host)
	var spare = chunk._scrap_for_id("scrap_b")
	spare.take_damage(float(spare.max_hp))
	_drop_plate_at_canal(host, chunk)
	var approach: Dictionary = chunk.get_preview_state()
	check(str(approach.get("plate_strip_phase", "")) == "approaching"
			and (approach.get("plate_approachers", []) as Array).size() == 1
			and (approach.get("plate_strippers", []) as Array).is_empty()
			and is_equal_approx(float(approach.get("plate_integrity", -1.0)), 1.0),
		"a live scrap walks toward a full bridge before any stripping stock drains")
	var approach_leg: Dictionary = host.game_state.get_external_traversal_state("scrap_a")
	check(approach_leg.get("traversal_id", &"") == chunk._plate_approach_traversal_id(
			"scrap_a") and float(approach_leg.get("remaining", 0.0)) > 2.0,
		"the approach is a visible locked GameState traversal, not a delayed remote effect")
	host.scheduler.advance_ticks(float(approach_leg.get("remaining", 0.0)) * 0.5)
	chunk.headless_process(0.0)
	var approach_midpoint := _capture(host)
	var approach_mid: Dictionary = host.game_state.get_external_traversal_state("scrap_a")
	check(float(approach_mid.get("progress", 0.0)) > 0.49
			and float(approach_mid.get("progress", 1.0)) < 0.51
			and is_equal_approx(float(chunk.get_preview_state().get(
				"plate_integrity", -1.0)), 1.0),
		"approach midpoint moves the scrap while leaving the untouched bridge intact")

	host.scheduler.advance_ticks(float(approach_mid.get("remaining", 0.0)) + 0.001)
	var contacted: Dictionary = chunk.get_preview_state()
	check(str(contacted.get("plate_strip_phase", "")) == "stripping"
			and (contacted.get("plate_strippers", []) as Array) == ["scrap_a"]
			and float(contacted.get("plate_strip_remaining", 0.0)) > 3.99,
		"physical contact starts a distinct saved stripping dwell")
	host.scheduler.advance_ticks(1.0)
	chunk.headless_process(0.0)
	var strip_midpoint := _capture(host)
	var strip_mid: Dictionary = chunk.get_preview_state()
	check(float(strip_mid.get("plate_integrity", -1.0)) > 0.74
			and float(strip_mid.get("plate_integrity", -1.0)) < 0.76
			and float(strip_mid.get("plate_strip_progress", -1.0)) > 0.24
			and host.game_state.grid.is_walkable(15, 19),
		"contact visibly consumes saved plate integrity without closing topology early")
	host.scheduler.advance_ticks(float(strip_mid.get("plate_strip_remaining", 0.0)) + 0.001)
	check(str(chunk.get_preview_state().get("plate", "")) == "eaten"
			and not host.game_state.grid.is_walkable(15, 19),
		"only the completed contact dwell removes the physical crossing")

	_apply_capture(host, chunk, strip_midpoint)
	_apply_capture(host, chunk, strip_midpoint)
	var rolled: Dictionary = chunk.get_preview_state()
	check(str(rolled.get("plate_strip_phase", "")) == "stripping"
			and absf(float(rolled.get("plate_integrity", -1.0))
				- float(strip_mid.get("plate_integrity", -2.0))) < 0.001
			and host.game_state.grid.is_walkable(15, 19),
		"same-instance idempotent rollback reconstructs contact, stock, and topology")
	var saved_strip_remaining := float(rolled.get("plate_strip_remaining", 0.0))
	host.scheduler.advance_ticks(saved_strip_remaining - 0.001)
	check(str(chunk.get_preview_state().get("plate", "")) == "placed",
		"restored stripping cannot complete before its original deadline")
	host.scheduler.advance_ticks(0.002)
	check(str(chunk.get_preview_state().get("plate", "")) == "eaten",
		"restored stripping completes exactly once at the saved deadline")

	var fresh_pair := await _boot_set_piece()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, strip_midpoint)
	var fresh_mid: Dictionary = fresh.get_preview_state()
	check(str(fresh_mid.get("plate_strip_phase", "")) == "stripping"
			and absf(float(fresh_mid.get("plate_integrity", -1.0))
				- float(strip_mid.get("plate_integrity", -2.0))) < 0.001,
		"fresh presenter reconstructs the saved stripping midpoint")
	fresh_host.scheduler.advance_ticks(float(fresh_mid.get("plate_strip_remaining", 0.0)) + 0.001)
	check(str(fresh.get_preview_state().get("plate", "")) == "eaten",
		"fresh presenter consumes only the saved stripping remainder")

	# Restoring an absent record retracts both semantic phase and GameState movement authority.
	_apply_capture(host, chunk, approach_midpoint)
	_apply_capture(host, chunk, baseline)
	var absent: Dictionary = chunk.get_preview_state()
	check(str(absent.get("plate", "")) == "stored"
			and str(absent.get("plate_strip_phase", "")) == "idle"
			and not host.game_state.is_external_traversal_active("scrap_a")
			and is_equal_approx(float(absent.get("plate_integrity", -1.0)), 1.0),
		"absence retracts a reused presenter to an uncommitted plate and no borrowed approach")
	await _discard(host)
	await _discard(fresh_host)

	# A lure that moves a contacting scrap away freezes exact partial damage and invalidates the old
	# deadline. The plate cannot vanish remotely while that scrap pursues the competing cause.
	var lure_pair := await _boot_set_piece()
	var lure_host = lure_pair.host
	var lure_chunk = lure_pair.chunk
	var lure_spare = lure_chunk._scrap_for_id("scrap_b")
	lure_spare.take_damage(float(lure_spare.max_hp))
	_drop_plate_at_canal(lure_host, lure_chunk)
	var lure_approach: Dictionary = lure_host.game_state.get_external_traversal_state("scrap_a")
	lure_host.scheduler.advance_ticks(float(lure_approach.get("remaining", 0.0)) + 0.501)
	var before_lure: Dictionary = lure_chunk.get_preview_state()
	var old_deadline := float(before_lure.get("plate_strip_deadline", -1.0))
	var frozen_integrity := float(before_lure.get("plate_integrity", -1.0))
	var lure_scrap = lure_chunk._scrap_for_id("scrap_a")
	check(bool(lure_scrap.lure_to(Vector3(22.4, 0.0, 18.1), 10.0)),
		"a competing lure can move a contacting scrap away")
	var interrupted: Dictionary = lure_chunk.get_preview_state()
	check(str(interrupted.get("plate_strip_phase", "")) == "interrupted"
			and str(interrupted.get("plate_strip_interrupt_reason", "")) == "moved_away"
			and float(interrupted.get("plate_strip_deadline", 0.0)) < 0.0
			and absf(float(interrupted.get("plate_integrity", -1.0)) - frozen_integrity) < 0.01,
		"moving away freezes partial stripping and cancels its old consequence deadline")
	var stale_remainder := old_deadline - float(lure_host.scheduler.get_current_tick()) + 0.1
	lure_host.scheduler.advance_ticks(stale_remainder)
	check(str(lure_chunk.get_preview_state().get("plate", "")) == "placed",
		"an interrupted scrap cannot consume the bridge at its stale deadline")
	await _discard(lure_host)

	# Death cancels an in-flight approach; without another live scrap there is no hidden eater.
	var death_pair := await _boot_set_piece()
	var death_host = death_pair.host
	var death_chunk = death_pair.chunk
	var death_spare = death_chunk._scrap_for_id("scrap_b")
	death_spare.take_damage(float(death_spare.max_hp))
	_drop_plate_at_canal(death_host, death_chunk)
	var doomed = death_chunk._scrap_for_id("scrap_a")
	doomed.take_damage(float(doomed.max_hp))
	check(not death_host.game_state.is_external_traversal_active("scrap_a")
			and str(death_chunk.get_preview_state().get("plate_strip_phase", "")) == "interrupted",
		"scrap death immediately cancels its authoritative approach")
	death_host.scheduler.advance_ticks(10.0)
	check(str(death_chunk.get_preview_state().get("plate", "")) == "placed",
		"dead scraps cannot strip a remote bridge")
	await _discard(death_host)

	# The hoist may capture only scraps still physically under station 2. Capturing them interrupts
	# their approach first; holding them aloft then falsifies the predicted plate loss.
	var magnet_pair := await _boot_set_piece()
	var magnet_host = magnet_pair.host
	var magnet_chunk = magnet_pair.chunk
	_drop_plate_at_canal(magnet_host, magnet_chunk)
	_trigger_set_piece_control(magnet_host, magnet_chunk, "hoist_switch") # station 1 -> 2 while the scraps are still leaving the pen
	magnet_host.scheduler.advance_ticks(magnet_chunk.TROLLEY_TRAVEL_TIME)
	_trigger_set_piece_control(magnet_host, magnet_chunk, "hoist_lever")
	var captured: Dictionary = magnet_chunk.get_preview_state()
	check(str(captured.get("magnet_phase", "")) == "lifting_swarm"
			and (captured.get("plate_approachers", []) as Array).is_empty()
			and (captured.get("plate_strippers", []) as Array).is_empty(),
		"magnet capture interrupts the scraps' old plate-bound traversals before lifting")
	magnet_host.scheduler.advance_ticks(magnet_chunk.MAGNET_OPERATION_TIME)
	magnet_host.scheduler.advance_ticks(magnet_chunk.PLATE_STRIP_TIME + 5.0)
	check(str(magnet_chunk.get_preview_state().get("plate", "")) == "placed",
		"scraps visibly pinned above the pen cannot eat the bridge")
	await _discard(magnet_host)


func _verify_hoist_payload_truth() -> void:
	var pair := await _boot_set_piece()
	var host = pair.host
	var chunk = pair.chunk
	_trigger_set_piece_control(host, chunk, "hoist_switch")
	host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME)
	_trigger_set_piece_control(host, chunk, "hoist_switch")
	host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME) # station 2, above scraps
	_trigger_set_piece_control(host, chunk, "hoist_lever")
	var swarm_lift: Dictionary = chunk.get_preview_state()
	check(str(swarm_lift.get("magnet_phase", "")) == "lifting_swarm"
			and str(swarm_lift.get("magnet_carrying", "x")) == ""
			and int(swarm_lift.get("pinned", 0)) == 2,
		"magnet captures eligible scraps into a visible locked lift before carrying them")
	for sc in chunk._pinned:
		check(host.game_state.is_external_traversal_active(sc.char_id),
			"lifting %s is an authoritative external traversal" % str(sc.char_id))
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME)
	check(str(chunk.get_preview_state().get("magnet_carrying", "")) == "swarm"
			and int(chunk.get_preview_state().get("pinned", 0)) == 2,
		"magnet commits both pinned scrap ids only after lift arrival")
	_trigger_set_piece_control(host, chunk, "hoist_switch") # begin station 2 -> station 0
	var started: Dictionary = chunk.get_preview_state()
	check(int(started.get("trolley_station", -1)) == 2
			and int(started.get("trolley_target_station", -1)) == 0,
		"payload transit keeps the trolley's logical station at its origin")
	for sc in chunk._pinned:
		check(host.game_state.is_external_traversal_active(sc.char_id)
				and absf(host.game_state.get_position(sc.char_id).x - float(chunk.STATION_X[2])) < 1.0,
			"pinned %s begins a locked authoritative traversal at station 2" % str(sc.char_id))
	host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME * 0.5)
	chunk.headless_process(0.0)
	for sc in chunk._pinned:
		var mid_x := float(host.game_state.get_position(sc.char_id).x)
		check(mid_x < float(chunk.STATION_X[2]) - 1.0
				and mid_x > float(chunk.STATION_X[0]) + 1.0,
			"pinned %s has an analytic in-flight position, not an endpoint teleport" % str(sc.char_id))
	_trigger_set_piece_control(host, chunk, "hoist_lever")
	check(int(chunk.get_preview_state().get("scraps_alive", -1)) == 2,
		"a discharge request in flight cannot kill or release the payload")
	host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME * 0.5)
	for sc in chunk._pinned:
		check(absf(host.game_state.get_position(sc.char_id).x - float(chunk.STATION_X[0])) < 1.0,
			"pinned %s logically follows the trolley to station 0" % str(sc.char_id))
	_trigger_set_piece_control(host, chunk, "hoist_switch") # begin station 0 -> station 1
	host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME * 0.5)
	var pinned_midpoint := _capture(host)
	_trigger_set_piece_control(host, chunk, "hoist_lever") # still in transit: refused
	check(int(chunk.get_preview_state().get("scraps_alive", -1)) == 2,
		"mid-transit canal discharge remains locked")
	host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME * 0.5)
	_trigger_set_piece_control(host, chunk, "hoist_lever") # begin real drop after canal arrival
	check(int(chunk.get_preview_state().get("scraps_alive", -1)) == 2,
		"canal drop does not kill the payload on the lever press")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME)
	check(int(chunk.get_preview_state().get("scraps_alive", -1)) == 0,
		"only the physically landed payload is discharged into the canal")
	_apply_capture(host, chunk, pinned_midpoint)
	_apply_capture(host, chunk, pinned_midpoint)
	check(str(chunk.get_preview_state().get("trolley_phase", "")) == "travelling"
			and int(chunk.get_preview_state().get("trolley_station", -1)) == 0
			and int(chunk.get_preview_state().get("trolley_target_station", -1)) == 1
			and str(chunk.get_preview_state().get("magnet_carrying", "")) == "swarm"
			and int(chunk.get_preview_state().get("pinned", 0)) == 2
			and int(chunk.get_preview_state().get("scraps_alive", -1)) == 2,
		"rollback restores in-flight trolley phase, payload membership, and enemy life together")
	for sc in chunk._pinned:
		check(host.game_state.is_external_traversal_active(sc.char_id),
			"rollback restores %s's matching external traversal" % str(sc.char_id))
	host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME * 0.5)
	_trigger_set_piece_control(host, chunk, "hoist_lever") # begin a real fall into the canal
	check(int(chunk.get_preview_state().get("scraps_alive", -1)) == 2
			and str(chunk.get_preview_state().get("magnet_phase", "")) == "dropping_swarm",
		"canal discharge begins a visible fall without applying early damage")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME - 0.001)
	check(int(chunk.get_preview_state().get("scraps_alive", -1)) == 2,
		"falling scraps remain alive until canal impact")
	host.scheduler.advance_ticks(0.001)
	check(int(chunk.get_preview_state().get("scraps_alive", -1)) == 0,
		"restored payload can be discharged exactly once at its saved station")

	var fresh_pair := await _boot_set_piece()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, pinned_midpoint)
	check(str(fresh.get_preview_state().get("trolley_phase", "")) == "travelling"
			and int(fresh.get_preview_state().get("pinned", 0)) == 2,
		"fresh presenter reconstructs the saved in-flight payload")
	for sc in fresh._pinned:
		check(fresh_host.game_state.is_external_traversal_active(sc.char_id),
			"fresh presenter keeps %s inside GameState's locked traversal" % str(sc.char_id))
	fresh_host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME * 0.5)
	_trigger_set_piece_control(fresh_host, fresh, "hoist_lever")
	fresh_host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME)
	check(int(fresh.get_preview_state().get("scraps_alive", -1)) == 0,
		"fresh in-flight payload arrives and discharges at the saved deadline")
	await _discard(host)
	await _discard(fresh_host)


func _verify_plate_drop_location_truth() -> void:
	var pair := await _boot_set_piece()
	var host = pair.host
	var chunk = pair.chunk
	_trigger_set_piece_control(host, chunk, "hoist_lever")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME)
	_trigger_set_piece_control(host, chunk, "hoist_switch")
	host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME)
	_trigger_set_piece_control(host, chunk, "hoist_switch")
	host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME)
	_trigger_set_piece_control(host, chunk, "hoist_lever")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME * 0.5)
	chunk.headless_process(0.0)
	var midpoint := _capture(host)
	var mid: Dictionary = chunk.get_preview_state()
	var mid_pos: Vector3 = mid.get("plate_position", Vector3.ZERO) as Vector3
	check(str(mid.get("magnet_phase", "")) == "dropping_plate"
			and str(mid.get("plate", "")) == "held"
			and absf(mid_pos.x - float(chunk.STATION_X[2])) < 0.01
			and mid_pos.y > 0.12 and mid_pos.y < chunk.MAGNET_HELD_Y,
		"a non-canal discharge visibly lowers the plate at the trolley's real station")
	var progress_before := float(mid.get("magnet_phase_progress", -1.0))
	chunk.headless_process(9999.0)
	check(is_equal_approx(
		float(chunk.get_preview_state().get("magnet_phase_progress", -2.0)), progress_before),
		"render delta cannot finish a plate discharge")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME * 0.5)
	var landed: Dictionary = chunk.get_preview_state()
	check(str(landed.get("plate", "")) == "stored"
			and int(landed.get("plate_station", -1)) == 2
			and absf(float((landed.get("plate_position", Vector3.ZERO) as Vector3).x)
				- float(chunk.STATION_X[2])) < 0.01,
		"dropping at station 2 leaves the plate there instead of teleporting it west")
	check(not host.game_state.grid.is_walkable(15, 19),
		"a plate grounded away from the canal cannot counterfeit bridge topology")
	_trigger_set_piece_control(host, chunk, "hoist_lever")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME)
	check(str(chunk.get_preview_state().get("magnet_carrying", "")) == "plate",
		"the plate can be physically retrieved from the station where it landed")

	_apply_capture(host, chunk, midpoint)
	var rolled: Dictionary = chunk.get_preview_state()
	check(str(rolled.get("magnet_phase", "")) == "dropping_plate"
			and absf(float(rolled.get("magnet_phase_progress", -1.0)) - 0.5) < 0.001,
		"same-instance rollback reconstructs the saved plate-drop midpoint")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME * 0.5 + 0.001)
	check(int(chunk.get_preview_state().get("plate_station", -1)) == 2,
		"restored plate lands once at its saved station")

	var fresh_pair := await _boot_set_piece()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, midpoint)
	var fresh_mid: Dictionary = fresh.get_preview_state()
	check(str(fresh_mid.get("magnet_phase", "")) == "dropping_plate"
			and absf(float((fresh_mid.get("plate_position", Vector3.ZERO) as Vector3).x)
				- float(fresh.STATION_X[2])) < 0.01,
		"fresh presenter reconstructs the plate above its saved non-canal landing")
	fresh_host.scheduler.advance_ticks(fresh.MAGNET_OPERATION_TIME * 0.5 + 0.001)
	check(int(fresh.get_preview_state().get("plate_station", -1)) == 2,
		"fresh presenter consumes only the saved plate-drop remainder")
	await _discard(host)
	await _discard(fresh_host)


func _verify_boss_prize_authority() -> void:
	var pair := await _boot_boss(23)
	var host = pair.host
	var chunk = pair.chunk
	var initial: Dictionary = _capture(host)
	var initial_state: Dictionary = chunk.get_preview_state()
	var prize_id := str(initial_state.get("prize_item_id", ""))
	var prize_item: Dictionary = host.game_state.items.get(prize_id, {})
	var initial_record: Dictionary = host.game_state.get_world_state(
		chunk.boss_authority_key(), {})
	check(int(initial_record.get("version", 0)) == chunk.BOSS_AUTHORITY_VERSION
			and str(initial_state.get("prize_phase", "")) == chunk.PRIZE_PHASE_AVAILABLE
			and str(prize_item.get("type", "")) == chunk.PRIZE_ITEM_TYPE
			and str(prize_item.get("location", "")) == "ground"
			and (prize_item.get("position", Vector3.ZERO) as Vector3).distance_to(
				chunk.PRIZE_POS) <= 0.05,
		"boss cache begins as one source-tagged physical GameState item")
	check(_boss_prize_ids(host, chunk).size() == 1
			and chunk._prize_interactable.visible
			and chunk._prize_interactable.is_interaction_enabled(),
		"available physical vial and its authored cache presenter agree")

	host.active_character = "aster"
	host.game_state.snap_character_to("aster", chunk.PRIZE_POS + Vector3(8.0, 0.0, 0.0))
	check(not _trigger_boss_prize(chunk, "aster")
			and str(chunk.get_preview_state().get("prize_phase", "")) \
				== chunk.PRIZE_PHASE_AVAILABLE,
		"a distant servicing body cannot remotely claim the cache")
	check(not chunk._on_prize_retrieved(),
		"the retired direct prize callback cannot substitute the selected portrait")
	host.game_state.snap_character_to("aster", chunk.PRIZE_POS)
	var filler_a: String = host.game_state.spawn_item(
		"test_filler", chunk.PRIZE_POS, {"hand_slots": 1})
	var filler_b: String = host.game_state.spawn_item(
		"test_filler", chunk.PRIZE_POS, {"hand_slots": 1})
	check(host.game_state.pick_up_item("aster", filler_a)
			and host.game_state.pick_up_item("aster", filler_b),
		"prize refusal fixture fills Aster's two canonical hands")
	check(not _trigger_boss_prize(chunk, "aster")
			and str(chunk.get_preview_state().get("prize_phase", "")) \
				== chunk.PRIZE_PHASE_AVAILABLE
			and str((host.game_state.items[prize_id] as Dictionary).get("location", "")) == "ground",
		"full hands leave the same vial visibly and retryably in the cache")
	host.game_state.remove_item(filler_a)
	host.game_state.remove_item(filler_b)

	var accepted_source_box := {"capture": {}}
	var accepted_source_listener := func(interactable_id: String, char_id: String) -> void:
		if interactable_id == str(chunk._prize_interactable.data_id) and char_id == "aster" \
				and str(chunk.get_preview_state().get("prize_phase", "")) \
					== chunk.PRIZE_PHASE_AVAILABLE:
			accepted_source_box.capture = _capture(host)
	var precommand_box := {"capture": {}}
	var precommand_listener := func(key: String, value: Variant) -> void:
		if key != chunk.boss_authority_key() or not value is Dictionary:
			return
		var record := value as Dictionary
		if str(record.get("prize_phase", "")) == chunk.PRIZE_PHASE_CLAIMING \
				and str((host.game_state.items.get(prize_id, {}) as Dictionary).get(
					"location", "")) == "ground":
			precommand_box.capture = _capture(host)
	var post_pick_box := {"capture": {}}
	var post_pick_listener := func(char_id: String, item_id: String) -> void:
		if char_id == "aster" and item_id == prize_id:
			post_pick_box.capture = _capture(host)
	host.game_state.interactable_triggered.connect(accepted_source_listener)
	host.game_state.world_state_changed.connect(precommand_listener)
	host.game_state.item_picked_up.connect(post_pick_listener)
	host.active_character = "peris"
	check(_trigger_boss_prize(chunk, "aster"),
		"the nearby servicing Aster claims the dose even while Peris is the selected portrait")
	host.game_state.interactable_triggered.disconnect(accepted_source_listener)
	host.game_state.world_state_changed.disconnect(precommand_listener)
	host.game_state.item_picked_up.disconnect(post_pick_listener)
	var claimed: Dictionary = _capture(host)
	var claimed_state: Dictionary = chunk.get_preview_state()
	check(not (accepted_source_box.capture as Dictionary).is_empty()
			and not (precommand_box.capture as Dictionary).is_empty()
			and not (post_pick_box.capture as Dictionary).is_empty(),
		"accepted-source, pre-pick, and post-pick/pre-finalize save seams are observable")
	check(str(claimed_state.get("prize_phase", "")) == chunk.PRIZE_PHASE_CLAIMED
			and str(claimed_state.get("prize_item_holder", "")) == "aster"
			and host.game_state.get_hand_items("aster").has(prize_id)
			and not chunk._prize_interactable.visible
			and not chunk._prize_interactable.is_interaction_enabled(),
		"claim completes only with the exact vial in Aster's real hand")
	check(not _trigger_boss_prize(chunk, "aster")
			and not chunk._on_prize_retrieved()
			and _boss_prize_ids(host, chunk).size() == 1,
		"neither the consumed source nor direct callback can duplicate the sealed dose")

	host.game_state.snap_character_to("peris", chunk.PRIZE_POS + Vector3(0.5, 0.0, 0.0))
	check(host.game_state.transfer_item("aster", "peris", prize_id),
		"the claimed vial uses canonical hand-to-hand transfer")
	var transferred: Dictionary = _capture(host)
	_apply_capture(host, chunk, claimed)
	_apply_capture(host, chunk, claimed)
	check(str(chunk.get_preview_state().get("prize_item_holder", "")) == "aster"
			and host.game_state.get_hand_items("aster").has(prize_id)
			and _boss_prize_ids(host, chunk).size() == 1,
		"same-presenter rollback restores the exact claimed vial and holder once")

	var fresh_claimed := await _boot_boss(23)
	_apply_capture(fresh_claimed.host, fresh_claimed.chunk, claimed)
	_apply_capture(fresh_claimed.host, fresh_claimed.chunk, claimed)
	check(str(fresh_claimed.chunk.get_preview_state().get("prize_phase", "")) \
			== fresh_claimed.chunk.PRIZE_PHASE_CLAIMED
			and fresh_claimed.host.game_state.get_hand_items("aster").has(prize_id)
			and _boss_prize_ids(fresh_claimed.host, fresh_claimed.chunk).size() == 1,
		"fresh presenter reconstructs the claimed vial without replaying pickup")

	var fresh_transfer := await _boot_boss(23)
	_apply_capture(fresh_transfer.host, fresh_transfer.chunk, transferred)
	check(str(fresh_transfer.chunk.get_preview_state().get("prize_item_holder", "")) == "peris"
			and fresh_transfer.host.game_state.get_hand_items("peris").has(prize_id)
			and bool(fresh_transfer.chunk.get_preview_state().get("prize_retrieved", false)),
		"fresh restore preserves later physical ownership independently of first claimant")

	var fresh_precommand := await _boot_boss(23)
	_apply_capture(fresh_precommand.host, fresh_precommand.chunk,
		precommand_box.capture as Dictionary)
	check(str(fresh_precommand.chunk.get_preview_state().get("prize_phase", "")) \
			== fresh_precommand.chunk.PRIZE_PHASE_AVAILABLE
			and str(fresh_precommand.chunk.get_preview_state().get(
				"prize_item_location", "")) == "ground"
			and not bool(fresh_precommand.chunk.get_preview_state().get("prize_retrieved", true)),
		"fresh pre-command seam rolls its reservation back without granting pickup")
	fresh_precommand.host.active_character = "aster"
	fresh_precommand.host.game_state.snap_character_to("aster", fresh_precommand.chunk.PRIZE_POS)
	check(_trigger_boss_prize(fresh_precommand.chunk, "aster")
			and _boss_prize_ids(fresh_precommand.host, fresh_precommand.chunk).size() == 1,
		"rolled-back pre-command seam remains retryable with the same item")

	var fresh_accepted_source := await _boot_boss(23)
	_apply_capture(fresh_accepted_source.host, fresh_accepted_source.chunk,
		accepted_source_box.capture as Dictionary)
	check(str(fresh_accepted_source.chunk.get_preview_state().get("prize_phase", "")) \
			== fresh_accepted_source.chunk.PRIZE_PHASE_AVAILABLE
			and fresh_accepted_source.chunk._prize_interactable.is_interaction_enabled()
			and str(fresh_accepted_source.chunk.get_preview_state().get(
				"prize_item_location", "")) == "ground",
		"fresh accepted-trigger seam re-arms the exact visible source without granting pickup")
	fresh_accepted_source.host.game_state.snap_character_to(
		"aster", fresh_accepted_source.chunk.PRIZE_POS)
	check(_trigger_boss_prize(fresh_accepted_source.chunk, "aster")
			and _boss_prize_ids(
				fresh_accepted_source.host, fresh_accepted_source.chunk).size() == 1,
		"fresh accepted-trigger retry claims the original source item exactly once")

	var fresh_post_pick := await _boot_boss(23)
	_apply_capture(fresh_post_pick.host, fresh_post_pick.chunk,
		post_pick_box.capture as Dictionary)
	check(str(fresh_post_pick.chunk.get_preview_state().get("prize_phase", "")) \
			== fresh_post_pick.chunk.PRIZE_PHASE_CLAIMED
			and fresh_post_pick.host.game_state.get_hand_items("aster").has(prize_id)
			and _boss_prize_ids(fresh_post_pick.host, fresh_post_pick.chunk).size() == 1,
		"fresh post-pick seam finalizes the already-moved item exactly once")

	_apply_capture(host, chunk, initial)
	check(str(chunk.get_preview_state().get("prize_phase", "")) == chunk.PRIZE_PHASE_AVAILABLE
			and str(chunk.get_preview_state().get("prize_item_location", "")) == "ground"
			and _boss_prize_ids(host, chunk).size() == 1,
		"construction rollback retracts the discarded claim to one source vial")
	await _discard(host)
	await _discard(fresh_claimed.host)
	await _discard(fresh_transfer.host)
	await _discard(fresh_precommand.host)
	await _discard(fresh_accepted_source.host)
	await _discard(fresh_post_pick.host)


func _verify_boss_midpoints() -> void:
	var pair := await _boot_boss(7)
	var host = pair.host
	var chunk = pair.chunk
	# Hold the Spiker on the corridor to make the next fixed poll externally observable.
	var wheel0 := chunk._wheels[0] as Dictionary
	chunk._ring0_parked = wrapf(float(wheel0["bottom"]) - chunk._spiker_angle, 0.0, TAU)
	host.game_state.snap_character_to("aster", chunk.PRIZE_POS)
	check(_trigger_boss_prize(chunk, "aster"),
		"boss midpoint claims the real cache item before carrying it through rollback")
	host.game_state.snap_character_to(
		"peris", _boss_control_position(host, chunk._survey_interactable))
	check(_trigger_boss_control(chunk._survey_interactable, "peris"),
		"boss midpoint survey comes from Peris physically holding the summit source")
	var apron := Vector3(float(chunk.TOWER_X) - 5.4, 0.0, float(chunk.CRAG_R) + 1.0)
	host.game_state.snap_character_to("aster", apron)
	host.game_state.snap_character_to(
		"endo", _boss_control_position(host, chunk._winch_interactable))
	check(_trigger_boss_control(chunk._winch_interactable, "endo"),
		"boss midpoint winch comes from Endo physically working its trail-head source")
	var scree_start: Dictionary = host.game_state.get_external_traversal_state("aster")
	var scree_start_pos: Vector3 = host.game_state.get_position("aster")
	var scree_start_distance := Vector2(
		scree_start_pos.x - apron.x, scree_start_pos.z - apron.z).length()
	var scree_start_id := StringName(str(scree_start.get("traversal_id", "")))
	check(not scree_start.is_empty()
			and scree_start_id == chunk._scree_traversal_id("aster")
			and scree_start_distance < 0.001,
		"scree commits a locked forced traversal without granting its landing (id=%s distance=%.4f)" % [
			str(scree_start_id), scree_start_distance])
	check(not host.game_state.command_move_to_pos("aster", apron + Vector3(12.0, 0.0, 0.0)),
		"ordinary movement cannot cancel a committed scree sweep")
	chunk._publish_boss_authority()
	host.game_state.snap_character_to("peris", Vector3(float(chunk.PARA_X), 0.0, 2.0))
	host.scheduler.advance_ticks(0.1)
	var midpoint := _capture(host)
	var scree_midpoint: Dictionary = host.game_state.get_external_traversal_state("aster")
	check(float(scree_midpoint.get("progress", 0.0)) > 0.11
			and float(scree_midpoint.get("progress", 1.0)) < 0.12,
		"boss midpoint stores analytic scree progress rather than an endpoint snap")
	var hp0 := float(host.game_state.get_stat("peris", "hp"))
	var saved: Dictionary = host.game_state.get_world_state(chunk.boss_authority_key(), {})
	check(bool(saved.get("ring0_is_parked", false))
			and bool(saved.get("flight_scramble", false))
			and str(saved.get("prize_phase", "")) == chunk.PRIZE_PHASE_CLAIMED
			and str(saved.get("prize_item_id", "")) != ""
			and is_equal_approx(float(saved.get("scramble_deadline", -1.0)), 18.0)
			and is_equal_approx(float(saved.get("align_poll_epoch", -1.0)), 0.0),
		"boss record captures brake, scree deadline, and absolute poll epoch")

	host.scheduler.advance_ticks(0.15)
	var armed_hazard: Dictionary = chunk.get_preview_state().get("spiker_hazard", {}) as Dictionary
	check(is_equal_approx(float(host.game_state.get_stat("peris", "hp")), hp0)
			and bool(armed_hazard.get("active", false))
			and is_equal_approx(float(armed_hazard.get("next_bite_tick", -1.0)), 0.5),
		"quarter-second alignment poll arms the visible Spiker field before impact")
	host.scheduler.advance_ticks(0.249)
	check(is_equal_approx(float(host.game_state.get_stat("peris", "hp")), hp0),
		"armed Spiker cannot land before its saved strike deadline")
	host.scheduler.advance_ticks(0.001)
	check(is_equal_approx(float(host.game_state.get_stat("peris", "hp")), hp0 - 1.0),
		"reusable Spiker HazardField owns the strike at its deadline")
	host.game_state.snap_character_to(
		"peris", _boss_control_position(host, chunk._brake_ia))
	check(_trigger_boss_control(chunk._brake_ia, "peris"),
		"the discarded brake future still requires its nearby physical source")
	host.scheduler.advance_ticks(18.0)
	check(not bool(chunk.get_preview_state().get("scramble", true)),
		"discarded future reaches the end of the scree span")
	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	var rolled: Dictionary = chunk.get_preview_state()
	check(bool(rolled.get("ring0_parked", false))
			and bool(rolled.get("scramble", false))
			and bool(rolled.get("prize_retrieved", false))
			and bool(rolled.get("watch_vantage", false)),
		"boss rollback restores brake, objective, and active scree phase")
	check(host.game_state.is_external_traversal_active("aster")
			and absf(float(host.game_state.get_external_traversal_state("aster").get("progress", 0.0))
				- float(scree_midpoint.get("progress", 0.0))) < 0.001,
		"boss rollback restores the exact in-flight scree trajectory")
	host.scheduler.advance_ticks(0.149)
	check(is_equal_approx(float(host.game_state.get_stat("peris", "hp")), hp0),
		"restored Spiker telegraph cannot arm early")
	host.scheduler.advance_ticks(0.001)
	check(is_equal_approx(float(host.game_state.get_stat("peris", "hp")), hp0)
			and bool((chunk.get_preview_state().get("spiker_hazard", {}) as Dictionary).get("active", false)),
		"idempotent restore attaches exactly one Spiker telegraph poll")
	host.scheduler.advance_ticks(0.249)
	check(is_equal_approx(float(host.game_state.get_stat("peris", "hp")), hp0),
		"restored field preserves its full telegraph interval")
	host.scheduler.advance_ticks(0.001)
	check(is_equal_approx(float(host.game_state.get_stat("peris", "hp")), hp0 - 1.0),
		"restored field strikes once at the original deadline")
	host.scheduler.advance_ticks(17.499)
	check(bool(chunk.get_preview_state().get("scramble", false)),
		"restored scree remains active until its absolute deadline")
	host.scheduler.advance_ticks(0.001)
	check(not bool(chunk.get_preview_state().get("scramble", true)),
		"restored scree ends once at its original deadline")

	var fresh_pair := await _boot_boss(7)
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, midpoint)
	var fresh_state: Dictionary = fresh.get_preview_state()
	check(bool(fresh_state.get("ring0_parked", false))
			and bool(fresh_state.get("scramble", false))
			and bool(fresh_state.get("prize_retrieved", false))
			and bool(fresh_state.get("watch_vantage", false)),
		"fresh boss presenter reconstructs the complete midpoint")
	check(fresh_host.game_state.is_external_traversal_active("aster")
			and absf(float(fresh_host.game_state.get_external_traversal_state("aster").get("progress", 0.0))
				- float(scree_midpoint.get("progress", 0.0))) < 0.001,
		"fresh boss presenter reconstructs the saved scree midpoint")
	fresh_host.scheduler.advance_ticks(0.15)
	check(is_equal_approx(float(fresh_host.game_state.get_stat("peris", "hp")), hp0)
			and bool((fresh.get_preview_state().get("spiker_hazard", {}) as Dictionary).get("active", false)),
		"fresh boss presenter reconstructs the telegraph phase before impact")
	fresh_host.scheduler.advance_ticks(0.25)
	check(is_equal_approx(float(fresh_host.game_state.get_stat("peris", "hp")), hp0 - 1.0),
		"fresh boss presenter resumes the HazardField strike deadline")
	fresh_host.scheduler.advance_ticks(17.5)
	check(not bool(fresh.get_preview_state().get("scramble", true)),
		"fresh boss presenter ends scree at the saved absolute deadline")
	await _discard(host)
	await _discard(fresh_host)


func _boot_set_piece() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = SetPieceScene.instantiate()
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "set_piece_showcase")
	host.add_child(chunk)
	await process_frame
	host.grid = GridWorld.from_data(chunk.get_grid_data())
	host.game_state.grid = host.grid
	chunk.reset_preview_state()
	chunk.headless_process(0.0)
	await process_frame
	return {"host": host, "chunk": chunk}


func _boot_boss(seed: int) -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = BossScene.instantiate()
	chunk.configure_chunk({"seed": seed})
	chunk.attach_chunk_host(host, "boss_showcase")
	host.add_child(chunk)
	await process_frame
	host.register_party(chunk.get_spawn_positions())
	for char_id in chunk.get_spawn_positions().keys():
		host.game_state.set_stat(str(char_id), "hp", 100.0)
		host.game_state.set_stat(str(char_id), "stamina", 100.0)
	host.grid = GridWorld.from_data(chunk.get_grid_data())
	host.game_state.grid = host.grid
	chunk.reset_preview_state()
	chunk.headless_process(0.0)
	await process_frame
	return {"host": host, "chunk": chunk}


func _drop_plate_at_canal(host, chunk) -> void:
	_trigger_set_piece_control(host, chunk, "hoist_lever")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME)
	_trigger_set_piece_control(host, chunk, "hoist_switch")
	host.scheduler.advance_ticks(chunk.TROLLEY_TRAVEL_TIME)
	_trigger_set_piece_control(host, chunk, "hoist_lever")
	host.scheduler.advance_ticks(chunk.MAGNET_OPERATION_TIME)


func _trigger_set_piece_control(
	host, chunk, action_id: String, actor := "peris", place_body := true
) -> bool:
	var source: Node = chunk._set_piece_control_for_action(action_id)
	if source == null or not is_instance_valid(source):
		return false
	if place_body:
		host.game_state.snap_character_to(
			actor, chunk._set_piece_control_data_position(source))
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _boss_prize_ids(host, chunk) -> Array[String]:
	var result: Array[String] = []
	for item_id_v in host.game_state.items.keys():
		var item_id := str(item_id_v)
		var item: Dictionary = host.game_state.items.get(item_id_v, {})
		var properties: Dictionary = item.get("properties", {})
		if str(item.get("type", "")) == chunk.PRIZE_ITEM_TYPE \
				and str(properties.get("source_boss_prize", "")) == chunk.boss_authority_key():
			result.append(item_id)
	result.sort()
	return result


func _trigger_boss_prize(chunk, actor: String) -> bool:
	var source: Node = chunk._prize_interactable
	if source == null or not is_instance_valid(source):
		return false
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _trigger_boss_control(source: Node, actor: String) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _boss_control_position(host, source: Node) -> Vector3:
	if source == null or not is_instance_valid(source):
		return Vector3.ZERO
	var data_id := str(source.get("data_id"))
	if data_id != "" and host.game_state.has_interactable(data_id):
		return host.game_state.get_interactable(data_id).get("position", Vector3.ZERO)
	return (source as Node3D).global_position if source is Node3D else Vector3.ZERO


func _capture(host) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _earliest_plate_approach_remaining(host, chunk) -> float:
	var earliest := INF
	for scrap_id in chunk.get_preview_state().get("plate_approachers", []) as Array:
		var traversal: Dictionary = host.game_state.get_external_traversal_state(str(scrap_id))
		earliest = minf(earliest, float(traversal.get("remaining", INF)))
	return 0.0 if is_inf(earliest) else earliest


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
