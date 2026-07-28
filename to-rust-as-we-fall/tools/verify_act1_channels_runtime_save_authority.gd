extends SceneTree

## Focused regression for the production Act 1 Channels composition.
##
## This fixture deliberately does not retain the retired assumptions that the room owns a scalar-X
## swarm, an analytical wash projection, or a local lure timer. It observes the reusable kit at its
## authority seams instead: stable Enemy IDs and FSM records, Flure effect windows, Channel-owned
## external traversals, and the room's bookkeeping-only phase record.

const ACT1_SCENE := preload("res://scenes/tutorial/act1.tscn")
const EPSILON := 0.002

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var sequence: Node = await _spawn_sequence()
	_verify_real_kit_composition(sequence)
	await _verify_enemy_flure_midpoint_restore(sequence)
	await _verify_channel_carry_restore_and_signal_save(sequence)
	await _verify_channels_explicit_party_rest()
	await _verify_integrated_stacks_party_rest()
	_verify_coda_uses_physical_kit(sequence)
	await _verify_encounter_los_and_midpoint_restore(sequence)
	_end_sequence(sequence)
	print("ACT1 CHANNELS RUNTIME SAVE AUTHORITY: %d checks, %d failures" % [
		_checks, _failures,
	])
	quit(0 if _failures == 0 else 1)


func _verify_real_kit_composition(sequence: Node) -> void:
	sequence.prepare_channels_fragment()
	sequence._scheduler.resume()
	var authority := _authority(sequence)
	check(str(authority.get("contract", "")) == "act1_channels/v3"
			and sequence._valid_channels_runtime_authority(authority),
		"Act 1 publishes one valid v3 room bookkeeping record")
	check(sequence._channels_flure is Flure
			and sequence._channels_run_lure is Flure
			and sequence._channels_flure_channel is Channel,
		"coda and encounter use reusable Flure/Channel nodes")

	for window_id in ["window_one", "window_two"]:
		var lane: Dictionary = sequence._channels_window_lanes[window_id]
		check(lane.get("interactable") is Flure,
			"%s owns a real Flure rather than a generic proxy" % window_id)
		check((lane.get("periodic_channels", []) as Array).all(
			func(entry: Dictionary): return entry.get("channel") is Channel),
			"%s wash strips are real Channel nodes" % window_id)
		var enemy_ids: Array = lane.get("enemy_ids", [])
		var stable := not enemy_ids.is_empty()
		for enemy_id_v in enemy_ids:
			var enemy_id := str(enemy_id_v)
			stable = stable \
				and enemy_id.begins_with("act1_channels_%s_enemy_" % window_id) \
				and sequence._resolve_channels_enemy(enemy_id) is Enemy \
				and sequence._game_state.characters.has(enemy_id)
		check(stable, "%s uses registered stable-ID Enemy bodies" % window_id)

	check(sequence._channels_flush_enemy_ids.size() == 5
			and sequence._channels_swarm_enemy_ids.size() == 7,
		"coda and final encounter expose their complete stable rosters")


func _verify_enemy_flure_midpoint_restore(sequence: Node) -> void:
	sequence.start_channels_window_puzzle("window_two")
	sequence._scheduler.resume()
	var lane: Dictionary = sequence._channels_window_lanes["window_two"]
	var flure: Flure = lane["interactable"]
	var enemy_ids: Array = lane["enemy_ids"]
	var first_id := str(enemy_ids[0])
	var before: Vector3 = sequence._game_state.get_position(first_id)
	_trigger_flure(sequence, flure, "peris")
	var report := flure.get_last_activation_report()
	check(int(report.get("pulled", 0)) == enemy_ids.size()
			and str(flure.get_effect_state().get("phase", "")) == Flure.PHASE_ACTIVE,
		"the window Flure commits its own effect and pulls the whole real pack")
	check(_all_enemies_in_state(sequence, enemy_ids, "lured"),
		"Flure activation enters every linked Enemy's saved lured FSM state")

	sequence.headless_advance(0.45, 0.05)
	var midpoint: Vector3 = sequence._game_state.get_position(first_id)
	var enemy_authority := _enemy_authority(sequence, first_id)
	var flure_effect := flure.get_effect_state()
	var snapshot := _json_round_trip(sequence.build_save_snapshot())
	check(midpoint.distance_to(before) > 0.05
			and str(enemy_authority.get("state", "")) == "lured"
			and float(flure_effect.get("end_tick", -1.0))
				> float(sequence._scheduler.get_current_tick()),
		"the midpoint is real body movement with Enemy and Flure absolute deadlines")

	sequence.headless_advance(0.35, 0.05)
	check(sequence._game_state.get_position(first_id).distance_to(midpoint) > 0.05,
		"advancing the discarded future changes the authoritative Enemy body")
	sequence.apply_save_snapshot(snapshot)
	check(sequence._game_state.get_position(first_id).distance_to(midpoint) <= EPSILON
			and str(sequence._resolve_channels_enemy(first_id).get_state()) == "lured"
			and _same_effect_window(
				sequence._channels_window_lanes["window_two"].get("interactable"),
				flure_effect),
		"same-presenter rollback restores exact Enemy position/FSM and Flure window")
	var attached_once := _authority(sequence)
	sequence.on_game_state_snapshot_restored()
	check(_authority(sequence) == attached_once
			and sequence._game_state.get_position(first_id).distance_to(midpoint) <= EPSILON,
		"repeated attachment is idempotent at the real-kit midpoint")

	var fresh: Node = await _spawn_sequence()
	fresh.apply_save_snapshot(snapshot)
	var fresh_window_position_ok: bool = (
		fresh._game_state.get_position(first_id).distance_to(midpoint) <= EPSILON)
	var fresh_window_state_ok := (
		str(fresh._resolve_channels_enemy(first_id).get_state()) == "lured")
	var fresh_window_enemy_ok := _same_enemy_authority(
		enemy_authority, _enemy_authority(fresh, first_id))
	var fresh_window_flure_ok := _same_effect_window(
		fresh._channels_window_lanes["window_two"].get("interactable"), flure_effect)
	check(fresh_window_position_ok and fresh_window_state_ok
			and fresh_window_enemy_ok and fresh_window_flure_ok,
		"fresh reconstruction restores the same stable Enemy and Flure authority")
	_end_sequence(fresh)


func _verify_channel_carry_restore_and_signal_save(sequence: Node) -> void:
	sequence.start_channels_window_puzzle("window_one")
	sequence._scheduler.resume()
	var lane: Dictionary = sequence._channels_window_lanes["window_one"]
	var pre_forgery := _json_round_trip(sequence.build_save_snapshot())
	var forged := _json_round_trip(pre_forgery)
	_set_window_swept_ids(
		forged, sequence.CHANNELS_RUNTIME_AUTHORITY_KEY, "window_one",
		(lane.get("enemy_ids", []) as Array).duplicate())
	sequence.apply_save_snapshot(forged)
	var forged_lane: Dictionary = sequence._channels_window_lanes["window_one"]
	check(not sequence._channels_scope_is_fully_swept(
			forged_lane.get("enemy_ids", []), forged_lane.get("swept_ids", []))
			and str(forged_lane.get("swarm_state", "")) != "washed",
		"a forged swept-ID ledger cannot replace the living stable Enemy bodies")
	sequence.apply_save_snapshot(pre_forgery)
	lane = sequence._channels_window_lanes["window_one"]
	var enemy_id := str((lane.get("enemy_ids", []) as Array)[0])
	for char_id in sequence.CHANNELS_PARTY_IDS:
		sequence.headless_set_character_position(
			char_id, Vector3(sequence.CHANNELS_MEMORY_TRIGGER_X - 12.0, 0.5, 0.0))
	var channel_entry: Dictionary = (lane.get("periodic_channels", []) as Array)[0]
	var channel: Channel = channel_entry["channel"]
	var channel_pos: Vector3 = channel_entry["position"]
	sequence._game_state.command_stop(enemy_id)
	sequence._game_state.snap_character_to(enemy_id, channel_pos)

	var signal_capture := {}
	var root_key: String = sequence.CHANNELS_RUNTIME_AUTHORITY_KEY
	sequence._game_state.world_state_changed.connect(func(key: String, value: Variant):
		if key != root_key or not (value is Dictionary) or signal_capture.has("snapshot"):
			return
		var windows: Dictionary = (value as Dictionary).get("windows", {})
		var window: Dictionary = windows.get("window_one", {})
		if enemy_id in (window.get("swept_ids", []) as Array):
			signal_capture["snapshot"] = _json_round_trip(sequence.build_save_snapshot())
	)

	channel.flood_now()
	sequence.headless_advance(0.061, 0.001)
	var traversal: Dictionary = sequence._game_state.get_external_traversal_state(enemy_id)
	var arrival := float(traversal.get("end_tick", -1.0))
	check(sequence._game_state.is_external_traversal_active(enemy_id)
			and str(traversal.get("traversal_id", "")).begins_with(
				"channel_sweep/act1_channels_window_one_wash_00/")
			and sequence._resolve_channels_enemy(enemy_id).is_alive(),
		"the real Channel catches a live Enemy into a locked external traversal")

	var half := maxf(0.001,
		(arrival - float(sequence._scheduler.get_current_tick())) * 0.5)
	sequence.headless_advance(half, minf(0.02, half))
	var midpoint: Vector3 = sequence._game_state.get_position(enemy_id)
	var progress := float(sequence._game_state.get_external_traversal_state(
		enemy_id).get("progress", -1.0))
	var midpoint_snapshot := _json_round_trip(sequence.build_save_snapshot())
	check(progress > 0.0 and progress < 1.0
			and midpoint.distance_to(channel_pos) > 0.05,
		"Channel midpoint stores an in-between GameState body, not a moved mesh")

	_advance_across(sequence, arrival)
	check(not sequence._resolve_channels_enemy(enemy_id).is_alive()
			and enemy_id in (
				sequence._channels_window_lanes["window_one"].get("swept_ids", []) as Array),
		"arrival lets Channel kill the Enemy before the room records the swept stable ID")
	check(signal_capture.has("snapshot"),
		"a save can be captured from the room-authority signal at the consequence boundary")

	sequence.apply_save_snapshot(midpoint_snapshot)
	check(sequence._game_state.is_external_traversal_active(enemy_id)
			and absf(float(sequence._game_state.get_external_traversal_state(
				enemy_id).get("progress", -2.0)) - progress) <= EPSILON
			and sequence._game_state.get_position(enemy_id).distance_to(midpoint) <= EPSILON
			and sequence._resolve_channels_enemy(enemy_id).is_alive(),
		"same-presenter rollback restores the exact live Channel carry midpoint")
	_advance_across(sequence, arrival)
	check(not sequence._resolve_channels_enemy(enemy_id).is_alive(),
		"restored Channel carry commits exactly one lethal arrival")

	var fresh_mid: Node = await _spawn_sequence()
	fresh_mid.apply_save_snapshot(midpoint_snapshot)
	check(fresh_mid._game_state.is_external_traversal_active(enemy_id)
			and absf(float(fresh_mid._game_state.get_external_traversal_state(
				enemy_id).get("progress", -2.0)) - progress) <= EPSILON
			and fresh_mid._game_state.get_position(enemy_id).distance_to(midpoint) <= EPSILON
			and fresh_mid._resolve_channels_enemy(enemy_id).is_alive(),
		"fresh presenter reconstructs the same Channel-owned carry")
	_advance_across(fresh_mid, arrival)
	check(not fresh_mid._resolve_channels_enemy(enemy_id).is_alive()
			and enemy_id in (
				fresh_mid._channels_window_lanes["window_one"].get(
					"swept_ids", []) as Array),
		"fresh carry reaches the same physical consequence once")
	_end_sequence(fresh_mid)

	if signal_capture.has("snapshot"):
		var fresh_signal: Node = await _spawn_sequence()
		fresh_signal.apply_save_snapshot(signal_capture["snapshot"])
		check(not fresh_signal._resolve_channels_enemy(enemy_id).is_alive()
				and enemy_id in (
					fresh_signal._channels_window_lanes["window_one"].get(
						"swept_ids", []) as Array),
			"signal-time save reconstructs the committed Enemy death and room bookkeeping")
		_end_sequence(fresh_signal)


func _verify_channels_explicit_party_rest() -> void:
	var sequence: Node = await _spawn_sequence()
	sequence.prepare_channels_fragment()
	sequence._scheduler.resume()
	sequence._current_step = "channels_shelter"
	for char_id_v in sequence.CHANNELS_PARTY_IDS:
		var char_id := str(char_id_v)
		sequence.headless_set_character_position(char_id, sequence.CHANNELS_SHELTER_POS)
	var arrival_atp := _party_atp(sequence)
	sequence._on_channels_shelter_party_arrived()
	var arrival_authority := _authority(sequence)
	var arrival_shelter: Dictionary = arrival_authority.get("shelter", {})
	check(sequence._channels_shelter_reached
			and not sequence._channels_party_recuperated
			and str(arrival_shelter.get("rest_phase", "")) == "locked"
			and not sequence._channels_shelter_interactable.interaction_enabled
			and _party_atp(sequence) == arrival_atp
			and not _any_party_resting(sequence),
		"Channels arrival opens its physical shortcut but cannot auto-fire rest during dialogue")
	sequence._dialogue.clear()
	sequence._enable_channels_shelter_rest()
	check(sequence._channels_shelter_rest_phase == "ready"
			and sequence._channels_shelter_interactable.interaction_enabled,
		"the named introduction completion explicitly arms the Channels hearth")

	sequence._scheduler.resume()
	for char_id_v in sequence.CHANNELS_PARTY_IDS:
		var char_id := str(char_id_v)
		sequence._game_state.set_stat(
			char_id,
			"stamina",
			maxf(0.0, sequence._game_state.get_stat_cap(char_id, "stamina") - 1.0))
	var paid_before := _party_atp(sequence)
	var signal_box := {"snapshot": {}}
	var signal_probe := func(_char_id: String, stat: String, _value: float) -> void:
		if stat == "atp" and (signal_box.get("snapshot", {}) as Dictionary).is_empty():
			signal_box["snapshot"] = _json_round_trip(sequence.build_save_snapshot())
	sequence._game_state.stat_changed.connect(signal_probe)
	sequence._select_character("aster")
	sequence._channels_shelter_interactable.active_character = "aster"
	var accepted := bool(sequence._channels_shelter_interactable._trigger(false))
	check(accepted,
		"Channels REST PARTY enters through the real hearth interaction")
	sequence._game_state.stat_changed.disconnect(signal_probe)
	var signal_snapshot: Dictionary = signal_box.get("snapshot", {})
	var signal_record := _channels_shelter_authority_from_snapshot(
		signal_snapshot, sequence.CHANNELS_RUNTIME_AUTHORITY_KEY)
	check(not signal_snapshot.is_empty()
			and str(signal_record.get("rest_phase", "")) == "committing"
			and _party_paid_once(sequence, paid_before)
			and _all_party_resting(sequence),
		"Channels first ATP signal sees COMMITTING after the complete batch is installed")
	check(sequence._channels_party_recuperated
			and sequence._channels_shelter_rest_phase == "rested",
		"explicit Channels REST PARTY finalizes the authored shelter")

	var same_events_before := _party_rest_event_count(sequence)
	sequence.apply_save_snapshot(signal_snapshot)
	sequence._scheduler.resume()
	sequence.headless_advance(0.001, 0.001)
	check(sequence._channels_party_recuperated
			and sequence._channels_shelter_rest_phase == "rested"
			and _party_paid_once(sequence, paid_before)
			and _all_party_resting(sequence)
			and _party_rest_event_count(sequence) == same_events_before,
		"same-presenter Channels signal restore reconciles without replay or repayment")

	var fresh: Node = await _spawn_sequence()
	var fresh_events_before := _party_rest_event_count(fresh)
	fresh.apply_save_snapshot(signal_snapshot)
	fresh._scheduler.resume()
	fresh.headless_advance(0.001, 0.001)
	check(fresh._channels_party_recuperated
			and fresh._channels_shelter_rest_phase == "rested"
			and _party_paid_once(fresh, paid_before)
			and _all_party_resting(fresh)
			and _party_rest_event_count(fresh) == fresh_events_before,
		"fresh Channels signal restore reconstructs the same paid rest without replay")
	_end_sequence(fresh)
	_end_sequence(sequence)


func _verify_integrated_stacks_party_rest() -> void:
	var sequence: Node = await _spawn_sequence()
	sequence.prepare_stacks_fragment("shelter")
	sequence._scheduler.resume()
	for char_id_v in sequence.CHANNELS_PARTY_IDS:
		var char_id := str(char_id_v)
		sequence._game_state.command_stop(char_id)
		sequence.headless_set_character_position(char_id, sequence.STACKS_SHELTER_POS)
		sequence._game_state.set_stat(
			char_id,
			"stamina",
			maxf(0.0, sequence._game_state.get_stat_cap(char_id, "stamina") - 1.0))
	var paid_before := _party_atp(sequence)
	var signal_box := {"snapshot": {}}
	var signal_probe := func(_char_id: String, stat: String, _value: float) -> void:
		if stat == "atp" and (signal_box.get("snapshot", {}) as Dictionary).is_empty():
			signal_box["snapshot"] = _json_round_trip(sequence.build_save_snapshot())
	sequence._game_state.stat_changed.connect(signal_probe)
	sequence._select_character("aster")
	sequence._stacks_shelter_interactable.active_character = "aster"
	check(bool(sequence._stacks_shelter_interactable._trigger(false)),
		"integrated Stacks rest enters through its gathered party shelter control")
	sequence._game_state.stat_changed.disconnect(signal_probe)
	var signal_snapshot: Dictionary = signal_box.get("snapshot", {})
	var signal_record := _world_authority_from_snapshot(
		signal_snapshot, sequence.ACT1_STACKS_REST_AUTHORITY_KEY)
	check(not signal_snapshot.is_empty()
			and str(signal_record.get("phase", "")) == "committing"
			and _party_paid_once(sequence, paid_before)
			and _all_party_resting(sequence),
		"integrated Stacks first ATP signal sees its published COMMITTING batch")
	check(sequence._stacks_rest_phase == "rested" and sequence._stacks_anxiety_seen,
		"integrated Stacks resolves anxiety only after the canonical party rest")

	var same_events_before := _party_rest_event_count(sequence)
	sequence.apply_save_snapshot(signal_snapshot)
	sequence._scheduler.resume()
	sequence.headless_advance(0.001, 0.001)
	check(sequence._stacks_rest_phase == "rested"
			and sequence._stacks_anxiety_seen
			and _party_paid_once(sequence, paid_before)
			and _all_party_resting(sequence)
			and _party_rest_event_count(sequence) == same_events_before,
		"same-presenter Stacks signal restore reconciles without a second command")

	var fresh: Node = await _spawn_sequence()
	var fresh_events_before := _party_rest_event_count(fresh)
	fresh.apply_save_snapshot(signal_snapshot)
	fresh._scheduler.resume()
	fresh.headless_advance(0.001, 0.001)
	check(fresh._stacks_rest_phase == "rested"
			and fresh._stacks_anxiety_seen
			and _party_paid_once(fresh, paid_before)
			and _all_party_resting(fresh)
			and _party_rest_event_count(fresh) == fresh_events_before,
		"fresh integrated Stacks signal restore reaches the same outcome without replay")
	_end_sequence(fresh)
	_end_sequence(sequence)


func _verify_coda_uses_physical_kit(sequence: Node) -> void:
	sequence.prepare_channels_fragment()
	sequence._scheduler.resume()
	sequence._current_step = "channels_flure"
	sequence._channels_coda_phase = "ready"
	for char_id in sequence.CHANNELS_PARTY_IDS:
		sequence.headless_set_character_position(
			char_id, sequence.CHANNELS_FLURE_POS + Vector3(-7.0, 0.0, 0.0))
	sequence._set_channels_flure_active(true)
	_trigger_flure(sequence, sequence._channels_flure, "peris")
	check(sequence._channels_coda_phase == "luring"
			and _all_enemies_in_state(
				sequence, sequence._channels_flush_enemy_ids, "lured"),
		"coda activation is a real Peris Flure signal into real Enemy FSMs")

	var channel_pos: Vector3 = sequence.CHANNELS_FLURE_POS + Vector3(2.0, 0.0, 0.0)
	for enemy_id_v in sequence._channels_flush_enemy_ids:
		var enemy_id := str(enemy_id_v)
		sequence._game_state.snap_character_to(enemy_id, channel_pos)
	sequence._channels_flure_channel.flood_now()
	sequence.headless_advance(0.061, 0.001)
	var caught := 0
	var last_arrival := float(sequence._scheduler.get_current_tick())
	for enemy_id_v in sequence._channels_flush_enemy_ids:
		var enemy_id := str(enemy_id_v)
		if sequence._game_state.is_external_traversal_active(enemy_id):
			caught += 1
			last_arrival = maxf(last_arrival, float(
				sequence._game_state.get_external_traversal_state(
					enemy_id).get("end_tick", last_arrival)))
	check(caught == sequence._channels_flush_enemy_ids.size(),
		"coda current physically owns every caught Enemy body")
	_advance_across(sequence, last_arrival)
	check(sequence._channels_coda_phase == "complete"
			and sequence._channels_coda_swept_ids.size()
				== sequence._channels_flush_enemy_ids.size()
			and _all_enemies_in_state(
				sequence, sequence._channels_flush_enemy_ids, "dead"),
		"coda completes only after Channel arrivals kill and report the full pack")


func _verify_encounter_los_and_midpoint_restore(sequence: Node) -> void:
	sequence.prepare_channels_fragment()
	sequence._scheduler.resume()
	sequence._begin_channels_encounter()
	for char_id in sequence.CHANNELS_PARTY_IDS:
		sequence.headless_set_character_position(char_id, sequence.CHANNELS_HIDE_SPOT_POS)
	var enemy_id := str(sequence._channels_swarm_enemy_ids[0])
	var enemy_before: Vector3 = sequence._game_state.get_position(enemy_id)
	check(not sequence._game_state.grid.has_line_of_sight(
			Vector3(sequence.CHANNELS_HIDE_SPOT_POS.x, 0.5, 0.0),
			sequence.CHANNELS_HIDE_SPOT_POS),
		"the visible hide walls are mirrored into authoritative GridWorld LOS")
	_trigger_flure(sequence, sequence._channels_run_lure, "endo")
	# The physical activation moved Endo to the source; now perform the actual hide leg rather than
	# retaining the old direct-helper fiction that he could signal while already behind the wall.
	sequence.headless_set_character_position("endo", sequence.CHANNELS_HIDE_SPOT_POS)
	sequence.headless_advance(0.6, 0.05)
	var midpoint: Vector3 = sequence._game_state.get_position(enemy_id)
	var enemy_authority := _enemy_authority(sequence, enemy_id)
	var effect: Dictionary = sequence._channels_run_lure.get_effect_state()
	var snapshot := _json_round_trip(sequence.build_save_snapshot())
	check(sequence._channels_encounter_phase == "hide"
			and str(sequence._resolve_channels_enemy(enemy_id).get_state()) == "lured"
			and midpoint.distance_to(enemy_before) > 0.05,
		"final encounter hide phase derives from a moving real lured Enemy pack")

	sequence.headless_advance(0.3, 0.05)
	sequence.apply_save_snapshot(snapshot)
	var same_encounter_position_ok: bool = (
		sequence._game_state.get_position(enemy_id).distance_to(midpoint) <= EPSILON)
	var same_encounter_enemy_ok := _same_enemy_authority(
		enemy_authority, _enemy_authority(sequence, enemy_id))
	var same_encounter_flure_ok := _same_effect_window(sequence._channels_run_lure, effect)
	check(same_encounter_position_ok and same_encounter_enemy_ok
			and same_encounter_flure_ok,
		"same-presenter encounter rollback restores exact Enemy/Flure midpoint")

	var fresh: Node = await _spawn_sequence()
	fresh.apply_save_snapshot(snapshot)
	var fresh_encounter_position_ok: bool = (
		fresh._game_state.get_position(enemy_id).distance_to(midpoint) <= EPSILON)
	var fresh_encounter_enemy_ok := _same_enemy_authority(
		enemy_authority, _enemy_authority(fresh, enemy_id))
	var fresh_encounter_flure_ok := _same_effect_window(fresh._channels_run_lure, effect)
	check(fresh_encounter_position_ok and fresh_encounter_enemy_ok
			and fresh_encounter_flure_ok,
		"fresh encounter reconstruction restores exact Enemy/Flure midpoint")
	_end_sequence(fresh)

	for id_v in sequence._channels_swarm_enemy_ids:
		sequence._game_state.snap_character_to(
			str(id_v), sequence.CHANNELS_RUN_LURE_POS)
	sequence._evaluate_channels_encounter_authority()
	check(sequence._channels_encounter_phase == "run"
			and sequence._current_step == "channels_encounter_run",
		"run opens only after all real lured bodies reach the settle point and party reaches cover")

	# A separate attempt proves failure comes from Enemy's real detector and LOS, not a room radius.
	sequence.prepare_channels_fragment()
	sequence._scheduler.resume()
	sequence._begin_channels_encounter()
	var detector_id := str(sequence._channels_swarm_enemy_ids[0])
	var detector: Enemy = sequence._resolve_channels_enemy(detector_id)
	var detector_pos: Vector3 = sequence._game_state.get_position(detector_id)
	sequence.headless_set_character_position("aster", Vector3(150.0, 0.5, -12.0))
	sequence.headless_set_character_position("endo", Vector3(150.0, 0.5, 12.0))
	sequence.headless_set_character_position(
		"peris", detector_pos + Vector3(0.8, 0.0, 0.0))
	sequence.headless_advance(0.2, 0.01)
	if sequence._channels_encounter_phase != "failed":
		detector.engage_target("peris")
	check(sequence._channels_encounter_phase == "failed"
			and detector_id in sequence._channels_encounter_spotted_ids,
		"an exposed body fails through Enemy target_spotted after authoritative LOS")


func _same_effect_window(flure: Variant, expected: Dictionary) -> bool:
	if not (flure is Flure):
		return false
	var actual: Dictionary = (flure as Flure).get_effect_state()
	return str(actual.get("phase", "")) == str(expected.get("phase", "")) \
		and is_equal_approx(
			float(actual.get("start_tick", -2.0)), float(expected.get("start_tick", -1.0))) \
		and is_equal_approx(
			float(actual.get("end_tick", -2.0)), float(expected.get("end_tick", -1.0))) \
		and actual.get("linked_target_ids", []) == expected.get("linked_target_ids", [])


func _same_enemy_authority(expected: Dictionary, actual: Dictionary) -> bool:
	# Production saves are JSON. Normalize both records through that contract before exact equality:
	# pre-save Vector3 components/deadlines can retain engine-side numeric container details that do
	# not survive JSON despite representing the same portable value.
	return _json_round_trip(expected) == _json_round_trip(actual)


func _all_enemies_in_state(sequence: Node, enemy_ids: Array, expected: String) -> bool:
	for enemy_id_v in enemy_ids:
		var enemy = sequence._resolve_channels_enemy(str(enemy_id_v))
		if not is_instance_valid(enemy) or str(enemy.get_state()) != expected:
			return false
	return true


func _advance_across(sequence: Node, deadline: float) -> void:
	var remainder := deadline - float(sequence._scheduler.get_current_tick())
	sequence.headless_advance(maxf(0.0, remainder - EPSILON), minf(0.02, EPSILON))
	sequence.headless_advance(EPSILON * 1.1, EPSILON * 1.1)


func _trigger_flure(sequence: Node, flure: Flure, actor: String) -> bool:
	if flure == null:
		return false
	sequence._game_state.command_stop(actor)
	sequence._game_state.snap_character_to(actor, flure.get_source_data_position())
	sequence._select_character(actor)
	flure.active_character = actor
	return bool(flure.call("_trigger", false))


func _spawn_sequence() -> Node:
	var sequence := ACT1_SCENE.instantiate()
	sequence.start_chunk = "channels"
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(10):
		await process_frame
	sequence.set_process(false)
	sequence.set_physics_process(false)
	return sequence


func _authority(sequence: Node) -> Dictionary:
	var value: Variant = sequence._game_state.get_world_state(
		sequence.CHANNELS_RUNTIME_AUTHORITY_KEY, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _enemy_authority(sequence: Node, enemy_id: String) -> Dictionary:
	var value: Variant = sequence._game_state.get_world_state(
		"runtime:enemy:%s" % enemy_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _channels_shelter_authority_from_snapshot(
		snapshot: Dictionary, authority_key: String) -> Dictionary:
	var root_authority := _world_authority_from_snapshot(snapshot, authority_key)
	var shelter: Variant = root_authority.get("shelter", {})
	return (shelter as Dictionary).duplicate(true) if shelter is Dictionary else {}


func _world_authority_from_snapshot(snapshot: Dictionary, authority_key: String) -> Dictionary:
	var game_state: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	var authority: Variant = world_state.get(authority_key, {})
	return (authority as Dictionary).duplicate(true) if authority is Dictionary else {}


func _party_atp(sequence: Node) -> Dictionary:
	var result := {}
	for char_id_v in sequence.CHANNELS_PARTY_IDS:
		var char_id := str(char_id_v)
		result[char_id] = sequence._game_state.get_stat(char_id, "atp")
	return result


func _party_paid_once(sequence: Node, before: Dictionary) -> bool:
	for char_id_v in sequence.CHANNELS_PARTY_IDS:
		var char_id := str(char_id_v)
		if not before.has(char_id) \
				or not is_equal_approx(
					sequence._game_state.get_stat(char_id, "atp"),
					float(before[char_id]) - 1.0):
			return false
	return true


func _all_party_resting(sequence: Node) -> bool:
	for char_id_v in sequence.CHANNELS_PARTY_IDS:
		if not sequence._game_state.is_resting(str(char_id_v)):
			return false
	return true


func _any_party_resting(sequence: Node) -> bool:
	for char_id_v in sequence.CHANNELS_PARTY_IDS:
		if sequence._game_state.is_resting(str(char_id_v)):
			return true
	return false


func _party_rest_event_count(sequence: Node) -> int:
	var count := 0
	if sequence == null or sequence._game_state == null \
			or sequence._game_state.event_log == null:
		return count
	for event_v in sequence._game_state.event_log.events:
		var event: Dictionary = event_v
		if str(event.get("kind", "")) == str(GameEvent.KIND_PARTY_REST):
			count += 1
	return count


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _set_window_swept_ids(
		snapshot: Dictionary, authority_key: String, window_id: String, enemy_ids: Array
	) -> void:
	var game_state: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	var authority: Dictionary = world_state.get(authority_key, {})
	var windows: Dictionary = authority.get("windows", {})
	var window: Dictionary = windows.get(window_id, {})
	window["swept_ids"] = enemy_ids.duplicate()
	windows[window_id] = window
	authority["windows"] = windows
	world_state[authority_key] = authority
	game_state["world_state"] = world_state
	snapshot["game_state"] = game_state


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
