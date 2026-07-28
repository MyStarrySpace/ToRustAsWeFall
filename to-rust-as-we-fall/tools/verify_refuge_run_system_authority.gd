extends SceneTree

## Refuge Run semantic/authority regression. The route choice is only a plan; real
## positions, reusable flora/hazard objects, Enemy acquisition, and scheduler
## deadlines own every consequence.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const RefugeScript := preload("res://scripts/fragments/chunks/refuge_run_chunk.gd")
const InteractionControllerScript := preload(
	"res://scripts/game/characters/character_interaction_controller.gd")


class InputDriver extends Node3D:
	signal arrived

	var char_id := "aster"
	var game_state

	func is_move_enabled() -> bool:
		return true

	func is_moving() -> bool:
		return game_state != null and game_state.is_moving(char_id)

	func move_to_world_position(world_position: Vector3) -> bool:
		return game_state != null and game_state.command_move_to_pos(char_id, world_position)

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_direct_helpers_are_inert()
	await _verify_real_input_reachability()
	var spatial_fixture := await _verify_spatial_systems()
	await _verify_fresh_spatial_restore(spatial_fixture)
	await _verify_hushbloom_is_real()
	var fixture := await _verify_midpoint_and_same_presenter_restore()
	await _verify_fresh_presenter_restore(fixture.midpoint)
	await _verify_fresh_exit_rest_restore(fixture.exit_rest_midpoint)
	await _verify_absence_retracts_future(fixture.baseline)
	await _verify_legacy_script_route_retracts()
	print("REFUGE RUN SYSTEM AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_direct_helpers_are_inert() -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	var before_authority: Dictionary = host.game_state.get_world_state(
		chunk.refuge_authority_key(), {})
	var before_hp := _party_hp(host.game_state)
	var before_atp := _party_atp(host.game_state)
	check(not chunk.choose_route("north")
			and not chunk.tend_bloom()
			and not chunk.activate_slit_lure()
			and not chunk.activate_spot_sweep()
			and not chunk.reach_exit(),
		"retired public helpers cannot impersonate route, flora, sweep, or shelter receipts")
	check(host.game_state.get_world_state(chunk.refuge_authority_key(), {}) == before_authority
			and _party_hp(host.game_state) == before_hp
			and _party_atp(host.game_state) == before_atp,
		"rejected helpers leave all refuge, HP, and ATP authority unchanged")
	chunk.call("_on_slit_flure_activated", 2, chunk._slit_flure)
	check(str(chunk.get_preview_state().get("slit_phase", "")) == "ready"
			and not chunk.activate_spot_sweep(chunk._spot_sweep_interactable)
			and not chunk.reach_exit(chunk._exit_shelter_interactable),
		"direct callbacks and borrowed node references still lack accepted one-shot receipts")
	await _discard(host)


## This is the anti-stupefaction guard: no choose/activate method is called. A normal
## movement plan crosses the fork, then synthetic right-clicks enter through
## Interactable._on_input_event -> CharacterInteractionController -> walk -> arrival.
func _verify_real_input_reachability() -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	var gs = host.game_state
	var controller = context.controller

	check(chunk.get_playthrough_interaction_target("slit_flure") == chunk._slit_flure
			and host.interactables.has(chunk._slit_flure),
		"the authored Flure is registered as a real player interaction target")
	check(chunk.get_playthrough_interaction_target("spot_sweep")
			== chunk._spot_sweep_interactable
			and host.interactables.has(chunk._spot_sweep_interactable),
		"the shelter sweep has a registered visible world control")
	check(not chunk._slit_flure.is_interaction_enabled()
			and not chunk._spot_sweep_interactable.is_interaction_enabled(),
		"future controls stay unavailable before their physical causal prerequisites")

	check(gs.command_move_to_pos(
			"aster", Vector3(chunk.ROUTE_COMMIT_MIN_X + 1.0, 0.5, chunk.NORTH_LANE_Z)),
		"ordinary GameState movement starts toward the north threshold")
	_advance_until_parked(host, chunk, controller, "aster", 12.0)
	var route_state: Dictionary = chunk.get_preview_state()
	check(str(route_state.get("route_choice", "")) == "north"
			and str(route_state.get("route_commit_actor", "")) == "aster"
			and (route_state.get("route_commit_position", []) as Array).size() == 3,
		"crossing the painted north lane commits the route without choose_route()")
	check(chunk._slit_flure.is_interaction_enabled(),
		"the physical lane commitment exposes the real Flure")
	var route_capture := _capture(host)
	_apply_capture(host, chunk, route_capture)
	_apply_capture(host, chunk, route_capture)
	check(str(chunk.get_preview_state().get("route_commit_actor", "")) == "aster"
			and chunk._slit_flure.is_interaction_enabled(),
		"same-presenter rollback preserves the movement-derived fork and its next affordance")

	# Move close only to isolate the input/arrival chain from encounter balance. The click
	# still has to issue and finish a non-zero movement plan before the object can trigger.
	gs.snap_character_to(
		"aster", chunk.SLIT_FLURE_POS + Vector3(-2.2, 0.05, 0.0))
	check(_right_click_world_target(
			host, chunk, controller, chunk._slit_flure, "aster", 4.0),
		"a right-click walks to and lights the registered Flure through the coordinator")
	var slit_state: Dictionary = chunk.get_preview_state()
	var flure_effect: Dictionary = slit_state.get("slit_flure", {}) as Dictionary
	check(str(slit_state.get("slit_phase", "")) == "window"
			and str(flure_effect.get("phase", "")) == "active"
			and int((flure_effect.get("last_activation_report", {}) as Dictionary)
				.get("pulled", 0)) >= 1,
		"the slit window derives from the Flure's canonical saved effect")

	gs.snap_character_to("aster", chunk.HIDE_SLIT_POS)
	host.scheduler.advance_ticks(float(slit_state.get("slit_window_remaining", 0.0)))
	check(str(chunk.get_preview_state().get("slit_phase", "")) == "safe"
			and chunk._spot_sweep_interactable.is_interaction_enabled(),
		"holding the slit to the canonical deadline exposes the physical sweep control")
	for i in range(RefugeScript.PARTY_IDS.size()):
		var char_id := str(RefugeScript.PARTY_IDS[i])
		gs.snap_character_to(
			char_id, chunk.HIDE_SPOT_POS + Vector3(float(i) - 1.0, 0.0, 0.0))
	chunk.headless_process(0.0)
	check(_right_click_world_target(
			host, chunk, controller, chunk._spot_sweep_interactable, "aster", 4.0),
		"a right-click reaches the pulse control and starts its ordinary interaction")
	check(str(chunk.get_preview_state().get("spot_phase", "")) == "sweeping",
		"the visible pulse control, not a test-only method, owns sweep entry")
	await _discard(host)

	var fresh := await _boot()
	_apply_capture(fresh.host, fresh.chunk, route_capture)
	check(str(fresh.chunk.get_preview_state().get("route_choice", "")) == "north"
			and str(fresh.chunk.get_preview_state().get("route_commit_actor", "")) == "aster"
			and fresh.chunk._slit_flure.is_interaction_enabled(),
		"a fresh presenter reconstructs the physical route commitment and clickable Flure")
	await _discard(fresh.host)


func _verify_spatial_systems() -> Dictionary:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	var gs = host.game_state
	check(gs.is_at_shelter("aster") and gs.is_at_shelter("peris")
			and gs.is_at_shelter("endo"),
		"the entry enclosure is an authored GameState shelter region, not a glowing marker")
	check(chunk._exit_shelter_interactable != null
			and not chunk._exit_shelter_interactable.is_interaction_enabled(),
		"the physical exit shelter exists but stays locked until the refuge model is solved")
	var before := _party_hp(gs)
	gs.snap_character_to(
		"aster", Vector3(chunk.ROUTE_COMMIT_MIN_X + 1.0, 0.5, chunk.SOUTH_LANE_Z))
	chunk.headless_process(1000.0)
	check(str(chunk.get_preview_state().get("route_choice", "")) == "",
		"headless presentation cannot turn a body position into route history")
	host.scheduler.advance_ticks(chunk.SPATIAL_AUTHORITY_INTERVAL)
	check(str(chunk.get_preview_state().get("route_choice", "")) == "south"
			and str(chunk.get_preview_state().get("route_commit_actor", "")) == "aster",
		"the saved spatial cadence records the exact south-threshold body")
	check(_party_hp(gs) == before,
		"physical route commitment does not remotely damage the party")
	for enemy in chunk.call("_refuge_enemies"):
		enemy.stun(20.0)
	gs.snap_character_to("aster", Vector3(27.0, 0.5, chunk.SOUTH_LANE_Z))
	gs.snap_character_to("peris", Vector3(12.0, 0.5, 0.0))
	gs.snap_character_to("endo", Vector3(12.0, 0.5, 2.0))
	host.scheduler.advance_ticks(chunk.RISKY_BLOOM_TICK_INTERVAL)
	var aster_after := float(gs.get_stat("aster", "hp"))
	check(is_equal_approx(aster_after, float(before.aster) - chunk.RISKY_BLOOM_DAMAGE_PER_TICK),
		"the spatial rust field bites the one body physically inside it (%.1f -> %.1f)" % [
			float(before.aster), aster_after])
	check(is_equal_approx(gs.get_stat("peris", "hp"), before.peris)
			and is_equal_approx(gs.get_stat("endo", "hp"), before.endo),
		"the same hazard tick cannot damage party members outside its bounds")
	check(bool(chunk.get_preview_state().get("hazard_taken", false)),
		"the route report derives hazard contact from the field callback")

	host.active_character = "peris"
	gs.snap_character_to("peris", chunk.CONCEAL_PATCH_POS)
	chunk.headless_process(1000.0)
	check(gs.get_character_concealment("peris") == GameState.CONCEAL_NONE,
		"render/headless projection cannot grant Scarpet concealment")
	host.scheduler.advance_ticks(chunk.SPATIAL_AUTHORITY_INTERVAL)
	check(gs.get_character_concealment("peris") == GameState.CONCEAL_MEDIUM,
		"the saved spatial cadence commits Scarpet concealment consumed by Enemy")
	chunk.headless_process(0.0)
	check(bool(chunk.get_preview_state().get("patch_concealed", false)),
		"presentation derives its Scarpet glow from canonical concealment")
	var scarpet_midpoint := _capture(host)
	var spatial_authority: Dictionary = gs.get_world_state(chunk.refuge_authority_key(), {})
	var saved_remainder: float = float(spatial_authority.get(
		"next_spatial_authority_tick", -1.0)) - host.scheduler.get_current_tick()
	check(saved_remainder > 0.0
			and saved_remainder <= chunk.SPATIAL_AUTHORITY_INTERVAL + 0.000001,
		"the refuge record preserves the next absolute spatial-authority tick")
	gs.snap_character_to("peris", chunk.CONCEAL_PATCH_POS + Vector3(chunk.PATCH_RADIUS + 0.2, 0.0, 0.0))
	chunk.headless_process(1000.0)
	check(gs.get_character_concealment("peris") == GameState.CONCEAL_MEDIUM,
		"leaving Scarpet remains pending until the saved gameplay poll")
	host.scheduler.advance_ticks(maxf(0.0, saved_remainder - 0.001))
	check(gs.get_character_concealment("peris") == GameState.CONCEAL_MEDIUM,
		"Scarpet concealment cannot retract before its saved poll deadline")
	host.scheduler.advance_ticks(0.002)
	check(gs.get_character_concealment("peris") == GameState.CONCEAL_NONE
			and not bool(chunk.get_preview_state().get("patch_concealed", true)),
		"crossing the saved poll retracts concealment exactly once")

	_apply_capture(host, chunk, scarpet_midpoint)
	_apply_capture(host, chunk, scarpet_midpoint)
	check(gs.get_character_concealment("peris") == GameState.CONCEAL_MEDIUM,
		"same-presenter rollback reconstructs canonical Scarpet concealment")
	gs.snap_character_to(
		"peris", chunk.CONCEAL_PATCH_POS + Vector3(chunk.PATCH_RADIUS + 0.2, 0.0, 0.0))
	host.scheduler.advance_ticks(maxf(0.0, saved_remainder - 0.001))
	check(gs.get_character_concealment("peris") == GameState.CONCEAL_MEDIUM,
		"idempotent rollback leaves one original spatial deadline")
	host.scheduler.advance_ticks(0.002)
	check(gs.get_character_concealment("peris") == GameState.CONCEAL_NONE,
		"the restored spatial deadline retracts cover without duplicate callbacks")
	await _discard(host)
	return {
		"midpoint": scarpet_midpoint,
		"remainder": saved_remainder,
	}


func _verify_fresh_spatial_restore(fixture: Dictionary) -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	var gs = host.game_state
	_apply_capture(host, chunk, fixture.get("midpoint", {}) as Dictionary)
	check(gs.get_character_concealment("peris") == GameState.CONCEAL_MEDIUM,
		"a fresh presenter restores the saved physical Scarpet truth")
	gs.snap_character_to(
		"peris", chunk.CONCEAL_PATCH_POS + Vector3(chunk.PATCH_RADIUS + 0.2, 0.0, 0.0))
	var remainder := float(fixture.get("remainder", 0.0))
	chunk.headless_process(1000.0)
	host.scheduler.advance_ticks(maxf(0.0, remainder - 0.001))
	check(gs.get_character_concealment("peris") == GameState.CONCEAL_MEDIUM,
		"fresh restore cannot retract concealment before the saved deadline")
	host.scheduler.advance_ticks(0.002)
	check(gs.get_character_concealment("peris") == GameState.CONCEAL_NONE,
		"fresh restore reattaches one spatial callback at the original deadline")
	await _discard(host)


func _verify_hushbloom_is_real() -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	var gs = host.game_state
	var bloom: Node = chunk.find_child("RefugeEntryHushbloom", true, false)
	var sentry: Node = chunk.find_child("RefugeStandardSentry", true, false)
	check(bloom != null and bloom.get_script() == preload("res://scripts/game/objects/hushbloom.gd"),
		"entry Hushbloom is the reusable gameplay object, not a decorative sphere")
	check(not chunk.tend_bloom(),
		"the retired decorative tend checkbox cannot claim a Hushbloom consequence")
	gs.snap_character_to("refuge_standard", chunk.HUSHBLOOM_POS + Vector3(1.0, 0.0, 0.0))
	gs.snap_character_to("aster", chunk.HUSHBLOOM_POS)
	host.scheduler.advance_ticks(0.25)
	var bloom_state: Dictionary = bloom.get_authority_state()
	check(str(bloom_state.get("phase", "")) == "recharging",
		"a body crossing the plant commits its real saved recharge phase")
	check(sentry != null and str(sentry.get_state()) == "stunned",
		"the physical burst stuns a real nearby sentry")
	await _discard(host)


func _verify_midpoint_and_same_presenter_restore() -> Dictionary:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	var gs = host.game_state
	var baseline := _capture(host)
	check(_commit_route_by_body(host, chunk, "north", "aster"),
		"safe-route fixture commits through the physical north threshold")
	check(_trigger_exact_control(host, chunk._slit_flure, "aster", chunk.SLIT_FLURE_POS),
		"slit action comes from the exact Flure one-shot")
	gs.snap_character_to("aster", chunk.HIDE_SLIT_POS)
	host.scheduler.advance_ticks(chunk.SPATIAL_AUTHORITY_INTERVAL)
	var opened: Dictionary = chunk.get_preview_state()
	var flure: Dictionary = opened.get("slit_flure", {}) as Dictionary
	var report: Dictionary = flure.get("last_activation_report", {}) as Dictionary
	check(str(opened.get("slit_phase", "")) == "window"
			and int(report.get("pulled", 0)) >= 1,
		"the slit window exists because at least one linked sentry is physically lured")
	check(gs.get_character_concealment("aster") == GameState.CONCEAL_FULL,
		"the occupied slit writes full concealment during the Flure window")
	host.scheduler.advance_ticks(3.0)
	var slit_midpoint_remaining := float(
		chunk.get_preview_state().get("slit_window_remaining", -1.0))
	var midpoint := _capture(host)
	chunk.headless_process(1000.0)
	check(str(chunk.get_preview_state().get("slit_phase", "")) == "window"
			and is_equal_approx(
				float(chunk.get_preview_state().get("slit_window_remaining", -1.0)),
				slit_midpoint_remaining),
		"render delta cannot consume the saved slit deadline")
	host.scheduler.advance_ticks(maxf(0.0, slit_midpoint_remaining - 0.001))
	check(str(chunk.get_preview_state().get("slit_phase", "")) == "window",
		"slit cannot clear before its absolute deadline")
	host.scheduler.advance_ticks(0.002)
	check(str(chunk.get_preview_state().get("slit_phase", "")) == "safe",
		"an actor physically in the slit clears it exactly when the song ends")

	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	check(str(chunk.get_preview_state().get("slit_phase", "")) == "window"
			and is_equal_approx(
				float(chunk.get_preview_state().get("slit_window_remaining", -1.0)),
				slit_midpoint_remaining),
		"same-presenter rollback idempotently restores the exact slit midpoint")
	host.scheduler.advance_ticks(slit_midpoint_remaining + 0.001)
	check(str(chunk.get_preview_state().get("slit_phase", "")) == "safe",
		"restored slit consumes only its saved remainder")

	for i in range(RefugeScript.PARTY_IDS.size()):
		var char_id := str(RefugeScript.PARTY_IDS[i])
		gs.snap_character_to(char_id, chunk.HIDE_SPOT_POS + Vector3(float(i) - 1.0, 0.0, 0.0))
	check(_trigger_exact_control(
			host, chunk._spot_sweep_interactable, "aster", chunk.SPOT_SWEEP_CONTROL_POS),
		"a gathered party uses the exact sweep control one-shot")
	check(_all_concealed(gs, GameState.CONCEAL_FULL),
		"the occupied shelter spot writes full concealment for every party member")
	host.scheduler.advance_ticks(2.5)
	var spot_midpoint := _capture(host)
	chunk.headless_process(500.0)
	check(str(chunk.get_preview_state().get("spot_phase", "")) == "sweeping"
			and is_equal_approx(float(chunk.get_preview_state().get("spot_sweep_remaining", -1.0)), 3.5),
		"render work cannot advance the scheduler-owned sweep")

	gs.snap_character_to("aster", chunk.HIDE_SPOT_POS + Vector3(chunk.SPOT_RADIUS + 1.0, 0.0, 0.0))
	chunk.headless_process(0.0)
	host.scheduler.advance_ticks(chunk.SPOT_PROBE_INTERVAL)
	check(str(chunk.get_preview_state().get("route_phase", "")) == "failed"
			and str(chunk.get_preview_state().get("last_outcome", "")) == "spot_sentry_acquired_target",
		"leaving cover fails only when a real sentry acquires the exposed actor")

	_apply_capture(host, chunk, spot_midpoint)
	_apply_capture(host, chunk, spot_midpoint)
	check(str(chunk.get_preview_state().get("spot_phase", "")) == "sweeping"
			and _all_concealed(gs, GameState.CONCEAL_FULL),
		"rollback retracts the failed branch and reconstructs live cover")
	host.scheduler.advance_ticks(3.5)
	check(str(chunk.get_preview_state().get("spot_phase", "")) == "safe"
			and str(chunk.get_preview_state().get("route_phase", "")) == "underway",
		"holding cover to the deadline produces the safe outcome once")
	check(str(chunk.get_preview_state().get("exit_rest_phase", "")) == "ready"
			and chunk._exit_shelter_interactable.is_interaction_enabled(),
		"solving the timed refuges exposes a real exit-shelter rest, not a radius completion")

	var before_rest_atp := _party_atp(gs)
	gs.snap_character_to("aster", chunk.EXIT_SHELTER_POS + Vector3(-0.8, 0.0, 0.0))
	gs.snap_character_to("peris", chunk.EXIT_SHELTER_POS + Vector3(0.8, 0.0, 0.0))
	gs.snap_character_to("endo", chunk.EXIT_SHELTER_POS + Vector3(0.0, 0.0, chunk.SHELTER_RADIUS + 0.4))
	check(not _trigger_exact_control(
				host, chunk._exit_shelter_interactable, "aster",
				chunk.EXIT_SHELTER_POS + Vector3(-0.8, 0.0, 0.0))
			and not bool(chunk.get_preview_state().get("shelter_reached", true))
			and _party_atp(gs) == before_rest_atp,
		"the physical shelter rejects one straggler with no partial ATP charge")

	gs.snap_character_to("endo", chunk.EXIT_SHELTER_POS)
	check(gs.is_at_shelter("aster") and gs.is_at_shelter("peris") and gs.is_at_shelter("endo"),
		"the gathered trio is authoritatively inside the registered exit shelter")
	var signal_seam := {"capture": {}}
	var capture_signal_seam := func(_char_id: String, stat_name: String, _value: float) -> void:
		if stat_name != "atp" or not (signal_seam["capture"] as Dictionary).is_empty():
			return
		var authority: Dictionary = gs.get_world_state(chunk.refuge_authority_key(), {})
		if str(authority.get("exit_rest_phase", "")) == "committing":
			signal_seam["capture"] = _capture(host)
	gs.stat_changed.connect(capture_signal_seam)
	check(_trigger_exact_control(
			host, chunk._exit_shelter_interactable, "aster",
			chunk.EXIT_SHELTER_POS + Vector3(-0.8, 0.0, 0.0)),
		"the exact shelter one-shot commits one canonical trio rest")
	if gs.stat_changed.is_connected(capture_signal_seam):
		gs.stat_changed.disconnect(capture_signal_seam)
	var exit_rest_midpoint: Dictionary = signal_seam["capture"] as Dictionary
	check(not exit_rest_midpoint.is_empty()
			and str(chunk.get_preview_state().get("exit_rest_phase", "")) == "rested"
			and bool(chunk.get_preview_state().get("shelter_reached", false))
			and str(chunk.get_preview_state().get("route_phase", "")) == "complete",
		"the rest signal seam carries COMMITTING authority before one final completed outcome")
	check(_party_atp(gs) == _offset_stats(before_rest_atp, -1.0)
			and _all_resting(gs),
		"exit success is backed by one atomic three-member ATP/rest transaction")

	_apply_capture(host, chunk, exit_rest_midpoint)
	_apply_capture(host, chunk, exit_rest_midpoint)
	var restored_paid_atp := _party_atp(gs)
	check(str(chunk.get_preview_state().get("exit_rest_phase", "")) == "committing"
			and not bool(chunk.get_preview_state().get("shelter_reached", true)),
		"same-presenter restore preserves the paid signal seam without granting its latch in restore")
	host.scheduler.advance_ticks(0.001)
	check(str(chunk.get_preview_state().get("exit_rest_phase", "")) == "rested"
			and _party_atp(gs) == restored_paid_atp
			and bool(chunk.get_preview_state().get("shelter_reached", false)),
		"the derived commit callback finalizes once without a second ATP charge")
	await _discard(host)
	return {
		"baseline": baseline,
		"midpoint": spot_midpoint,
		"exit_rest_midpoint": exit_rest_midpoint,
	}


func _verify_fresh_presenter_restore(midpoint: Dictionary) -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	_apply_capture(host, chunk, midpoint)
	var state: Dictionary = chunk.get_preview_state()
	check(str(state.get("spot_phase", "")) == "sweeping"
			and is_equal_approx(float(state.get("spot_sweep_remaining", -1.0)), 3.5),
		"a fresh presenter reconstructs the saved in-flight sweep")
	host.scheduler.advance_ticks(3.499)
	check(str(chunk.get_preview_state().get("spot_phase", "")) == "sweeping",
		"fresh restore cannot grant the shelter outcome early")
	host.scheduler.advance_ticks(0.001)
	check(str(chunk.get_preview_state().get("spot_phase", "")) == "safe",
		"fresh restore commits at the original absolute deadline")
	await _discard(host)


func _verify_fresh_exit_rest_restore(midpoint: Dictionary) -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	_apply_capture(host, chunk, midpoint)
	var paid_atp := _party_atp(host.game_state)
	check(str(chunk.get_preview_state().get("exit_rest_phase", "")) == "committing"
			and not bool(chunk.get_preview_state().get("shelter_reached", true)),
		"a fresh presenter reconstructs the exact paid exit-rest signal seam")
	host.scheduler.advance_ticks(0.001)
	check(str(chunk.get_preview_state().get("exit_rest_phase", "")) == "rested"
			and bool(chunk.get_preview_state().get("shelter_reached", false))
			and _party_atp(host.game_state) == paid_atp,
		"fresh restore finishes the exit once without replaying its resource transaction")
	await _discard(host)


func _verify_absence_retracts_future(baseline: Dictionary) -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	check(_commit_route_by_body(host, chunk, "north", "aster"),
		"absence fixture first creates body-derived route state")
	var absent := baseline.duplicate(true)
	var world_state: Dictionary = (absent.get("game_state", {}) as Dictionary).get("world_state", {}) as Dictionary
	var erase_keys: Array = []
	for key_v in world_state.keys():
		var key := str(key_v)
		if "refuge" in key:
			erase_keys.append(key_v)
	for key_v in erase_keys:
		world_state.erase(key_v)
	_apply_capture(host, chunk, absent)
	var state: Dictionary = chunk.get_preview_state()
	check(str(state.get("route_phase", "")) == "briefing"
			and str(state.get("route_choice", "")) == ""
			and str(state.get("slit_phase", "")) == "ready"
			and str(state.get("spot_phase", "")) == "ready"
			and str(state.get("exit_rest_phase", "")) == "locked"
			and not bool(state.get("shelter_reached", true)),
		"missing records retract every future route/refuge phase")
	var normalized: Dictionary = host.game_state.get_world_state(chunk.refuge_authority_key(), {})
	check(int(normalized.get("version", 0)) == chunk.REFUGE_AUTHORITY_VERSION
			and str(normalized.get("route_phase", "")) == "briefing",
		"authority absence normalizes to an explicit construction baseline")
	await _discard(host)


func _verify_legacy_script_route_retracts() -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	var legacy := _capture(host)
	var authority: Dictionary = host.game_state.get_world_state(
		chunk.refuge_authority_key(), {}).duplicate(true)
	authority["version"] = 3
	authority["route_phase"] = "underway"
	authority["route_choice"] = "north"
	authority["route_commit_actor"] = "script"
	authority["route_commit_position"] = []
	var game_state_capture := legacy.get("game_state", {}) as Dictionary
	var world_state := game_state_capture.get("world_state", {}) as Dictionary
	world_state[chunk.refuge_authority_key()] = authority
	_apply_capture(host, chunk, legacy)
	var state: Dictionary = chunk.get_preview_state()
	var normalized: Dictionary = host.game_state.get_world_state(
		chunk.refuge_authority_key(), {})
	check(str(state.get("route_phase", "")) == "briefing"
			and str(state.get("route_choice", "")) == ""
			and str(state.get("route_commit_actor", "")) == "",
		"a legacy actor=script route has no body provenance and retracts on load")
	check(int(normalized.get("version", 0)) == chunk.REFUGE_AUTHORITY_VERSION
			and float(normalized.get("next_spatial_authority_tick", -1.0))
				> host.scheduler.get_current_tick(),
		"legacy retraction publishes a current body-authoritative record and future poll")
	await _discard(host)


func _commit_route_by_body(host, chunk, route_id: String, actor: String) -> bool:
	var lane_z: float = chunk.NORTH_LANE_Z if route_id == "north" else chunk.SOUTH_LANE_Z
	host.game_state.snap_character_to(
		actor, Vector3(chunk.ROUTE_COMMIT_MIN_X + 1.0, 0.5, lane_z))
	host.scheduler.advance_ticks(chunk.SPATIAL_AUTHORITY_INTERVAL)
	var state: Dictionary = chunk.get_preview_state()
	return str(state.get("route_choice", "")) == route_id \
		and str(state.get("route_commit_actor", "")) == actor


func _trigger_exact_control(
	host,
	control: Node,
	actor: String,
	position: Vector3
) -> bool:
	if control == null or not is_instance_valid(control):
		return false
	host.active_character = actor
	host.game_state.snap_character_to(actor, position)
	control.set("active_character", actor)
	return bool(control.call("_trigger", false))


func _right_click_world_target(
	host,
	chunk,
	controller,
	target: Node,
	expected_actor: String,
	max_seconds: float
) -> bool:
	if target == null or not target.has_method("_on_input_event") \
			or not target.is_interaction_enabled():
		return false
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	target.call(
		"_on_input_event",
		null,
		event,
		(target as Node3D).global_position,
		Vector3.UP,
		0)
	var elapsed := 0.0
	while controller.active_target != null and elapsed < max_seconds:
		host.scheduler.advance_ticks(0.05)
		chunk.headless_process(0.0)
		controller.sync_scheduler_visuals()
		elapsed += 0.05
	return controller.active_target == null \
		and str(target.get("active_character")) == expected_actor


func _advance_until_parked(
	host,
	chunk,
	controller,
	char_id: String,
	max_seconds: float
) -> void:
	var elapsed := 0.0
	while host.game_state.is_moving(char_id) and elapsed < max_seconds:
		host.scheduler.advance_ticks(0.05)
		chunk.headless_process(0.0)
		controller.sync_scheduler_visuals()
		elapsed += 0.05
	chunk.headless_process(0.0)


func _boot() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = RefugeScript.new()
	chunk.attach_chunk_host(host, "refuge_run_authority_fixture")
	for char_id_v in chunk.get_spawn_positions().keys():
		var char_id := str(char_id_v)
		host.game_state.register_character(char_id, chunk.get_spawn_positions()[char_id], 3.0, {
			"hp": 100.0,
			"stamina": 100.0,
			"atp": 8.0,
		})
	host.game_state.set_party(RefugeScript.PARTY_IDS)
	host.game_state.set_game_clock(4, 0.82)
	host.add_child(chunk)
	var input_driver := InputDriver.new()
	input_driver.name = "RefugeInputDriver"
	input_driver.char_id = "aster"
	input_driver.game_state = host.game_state
	host.add_child(input_driver)
	var controller = InteractionControllerScript.new()
	controller.name = "CharacterInteractionController"
	input_driver.add_child(controller)
	controller.setup(input_driver)
	controller.bind_interaction_root(chunk)
	await process_frame
	return {
		"host": host,
		"chunk": chunk,
		"input_driver": input_driver,
		"controller": controller,
	}


func _capture(host) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _apply_capture(host, chunk, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	_notify_restore_children(chunk)
	chunk.on_game_state_snapshot_restored()


func _notify_restore_children(node: Node) -> void:
	for child in node.get_children():
		_notify_restore_children(child)
		if child.has_method("on_game_state_snapshot_restored"):
			child.call("on_game_state_snapshot_restored")


func _party_hp(gs) -> Dictionary:
	return {
		"aster": gs.get_stat("aster", "hp"),
		"peris": gs.get_stat("peris", "hp"),
		"endo": gs.get_stat("endo", "hp"),
	}


func _party_atp(gs) -> Dictionary:
	return {
		"aster": gs.get_stat("aster", "atp"),
		"peris": gs.get_stat("peris", "atp"),
		"endo": gs.get_stat("endo", "atp"),
	}


func _offset_stats(values: Dictionary, offset: float) -> Dictionary:
	var out := {}
	for key_v in values.keys():
		var key := str(key_v)
		out[key] = float(values[key]) + offset
	return out


func _all_resting(gs) -> bool:
	for char_id in RefugeScript.PARTY_IDS:
		if not gs.is_resting(char_id):
			return false
	return true


func _all_concealed(gs, tier: int) -> bool:
	for char_id in RefugeScript.PARTY_IDS:
		if gs.get_character_concealment(char_id) != tier:
			return false
	return true


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
