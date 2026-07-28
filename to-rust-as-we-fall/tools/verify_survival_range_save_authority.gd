extends SceneTree

## Regression for the Survival Range's previously local/proxy shortcuts:
## - the lure window is an absolute scheduler deadline, not render-delta countdown state;
## - the reset winch owns a saved external traversal, not an endpoint teleport after its work prompt.
## - both seam choices are saved physical traversals through fixed spatial hazard truth;
## - scouting reveals that truth without changing it;
## - the sweep uses real Enemy FSM actors and the slit uses positional Capbage concealment.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const RangeScript := preload("res://scripts/fragments/chunks/survival_range_chunk.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_public_verbs_require_physical_receipts()
	await _verify_accepted_source_signal_seam()
	await _verify_spatial_hazard_and_scout_truth()
	await _verify_echo_coupler_redirects_real_swarm()
	await _verify_lure_deadline_and_frame_invariance()
	var cross_snapshots := await _verify_crossing_midpoint_and_rollback()
	await _verify_fresh_crossing_presenter(cross_snapshots.midpoint)
	await _verify_crossing_absence_retracts_future(cross_snapshots.midpoint)
	var swarm_snapshot := await _verify_real_swarm_and_cover()
	await _verify_fresh_swarm_presenter(swarm_snapshot.capture, swarm_snapshot.report)
	await _verify_cover_spatial_selectivity()
	var snapshots := await _verify_winch_midpoint_and_rollback()
	await _verify_fresh_winch_presenter(snapshots.midpoint)
	await _verify_missing_record_retracts_future(snapshots.before)
	await _verify_atomic_shelter_signal_restore()
	print("SURVIVAL RANGE SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_public_verbs_require_physical_receipts() -> void:
	var pair := await _boot_range()
	var chunk = pair.chunk
	var before: Dictionary = chunk.get_preview_state().duplicate(true)
	check(not chunk.depart_range() and not chunk.survey_route()
			and not chunk.activate_range_lure() and not chunk.tune_echo_coupler()
			and not chunk.cross_seam() and not chunk.commit_hide()
			and not chunk.reset_after_failure() and not chunk.rest_at_east_shelter()
			and chunk.get_preview_state() == before,
		"public range verbs cannot forge a physical control receipt or mutate authority")
	await _discard(pair.host)


func _verify_accepted_source_signal_seam() -> void:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	var departure: Node = chunk.get("_departure_interactable")
	var departure_id := str(departure.get("data_id"))
	var signal_box := {"capture": {}}
	var signal_probe := func(data_id: String, _actor: String) -> void:
		if data_id == departure_id \
				and (signal_box.get("capture", {}) as Dictionary).is_empty():
			signal_box["capture"] = _capture(host)
	host.game_state.interactable_triggered.connect(signal_probe)
	check(_trigger_range_control(host, chunk, "_departure_interactable", "aster",
		chunk.WEST_SHELTER_POS),
		"departure commits through its exact physical source after the accepted-trigger signal")
	host.game_state.interactable_triggered.disconnect(signal_probe)
	var signal_capture: Dictionary = signal_box.get("capture", {})
	check(not signal_capture.is_empty()
			and bool(chunk.get_preview_state().get("departed", false)),
		"signal-time fixture captures the accepted receipt before the owner consequence")

	_apply_capture(host, chunk, signal_capture)
	check(not bool(chunk.get_preview_state().get("departed", true))
			and not bool(departure.get("_used"))
			and bool(departure.get("interaction_enabled")),
		"same-presenter restore retracts an uncommitted receipt and reopens its source")
	check(_trigger_range_control(host, chunk, "_departure_interactable", "aster",
		chunk.WEST_SHELTER_POS),
		"same-presenter retry can consume one fresh receipt and commit once")

	var fresh := await _boot_range()
	_apply_capture(fresh.host, fresh.chunk, signal_capture)
	var fresh_departure: Node = fresh.chunk.get("_departure_interactable")
	check(not bool(fresh.chunk.get_preview_state().get("departed", true))
			and not bool(fresh_departure.get("_used"))
			and bool(fresh_departure.get("interaction_enabled")),
		"fresh restore also retracts the accepted-only receipt without granting departure")
	check(_trigger_range_control(
		fresh.host, fresh.chunk, "_departure_interactable", "aster",
		fresh.chunk.WEST_SHELTER_POS),
		"fresh presenter remains physically retryable after accepted-signal rollback")
	await _discard(fresh.host)
	await _discard(host)


func _verify_spatial_hazard_and_scout_truth() -> void:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	var initial_hazard: Dictionary = chunk.get_preview_state().get("direct_hazard", {})
	check(bool(initial_hazard.get("active", false))
			and is_equal_approx(float(initial_hazard.get("damage_per_bite", -1.0)), chunk.DIRECT_BLOOM_DAMAGE)
			and is_equal_approx(float(initial_hazard.get("interval", -1.0)), chunk.DIRECT_BLOOM_INTERVAL),
		"direct bloom is a live scheduler-owned HazardField at construction")

	var hp_start: float = host.game_state.get_stat("endo", "hp")
	host.game_state.snap_character_to("endo", Vector3(138.0, 0.5, chunk.MID_SEAM_POS.z))
	host.scheduler.advance_ticks(chunk.DIRECT_BLOOM_INTERVAL)
	check(is_equal_approx(host.game_state.get_stat("endo", "hp"), hp_start),
		"the safe seam is outside the bloom rectangle and takes no proxy damage")

	host.game_state.snap_character_to("endo", Vector3(138.0, 0.5, chunk.SHORT_BLOOM_POS.z))
	host.scheduler.advance_ticks(chunk.DIRECT_BLOOM_INTERVAL - 0.001)
	check(is_equal_approx(host.game_state.get_stat("endo", "hp"), hp_start),
		"a body inside the direct field is not bitten before the visible cadence")
	host.scheduler.advance_ticks(0.0011)
	check(is_equal_approx(host.game_state.get_stat("endo", "hp"), hp_start - chunk.DIRECT_BLOOM_DAMAGE),
		"the same body is bitten exactly on the field's scheduler pulse")
	host.game_state.snap_character_to("endo", chunk.MID_SEAM_POS)

	check(_trigger_range_control(host, chunk, "_departure_interactable", "aster",
		chunk.WEST_SHELTER_POS), "scout fixture departs from the west shelter")
	var hazard_before_scan: Dictionary = chunk.get_preview_state().get("direct_hazard", {})
	check(_trigger_range_control(host, chunk, "_scout_interactable", "aster",
		chunk.SCOUT_PERCH_POS), "Aster resolves the physical route read")
	var after_scan: Dictionary = chunk.get_preview_state()
	var hazard_after_scan: Dictionary = after_scan.get("direct_hazard", {})
	check(bool((after_scan.get("scout_readout", {}) as Dictionary).get("revealed", false))
			and is_equal_approx(float(hazard_after_scan.get("damage_per_bite", -1.0)),
				float(hazard_before_scan.get("damage_per_bite", -2.0)))
			and is_equal_approx(float(hazard_after_scan.get("interval", -1.0)),
				float(hazard_before_scan.get("interval", -2.0)))
			and is_equal_approx(float(hazard_after_scan.get("next_bite_tick", -1.0)),
				float(hazard_before_scan.get("next_bite_tick", -2.0))),
		"scouting reveals field footprint/cadence without changing strength or rebasing its pulse")
	await _discard(host)


func _verify_echo_coupler_redirects_real_swarm() -> void:
	var untuned := await _boot_range()
	var host = untuned.host
	var chunk = untuned.chunk
	check(_trigger_range_control(host, chunk, "_departure_interactable", "aster",
		chunk.WEST_SHELTER_POS), "untuned-route fixture leaves shelter")
	check(_trigger_range_control(host, chunk, "_scout_interactable", "aster",
		chunk.SCOUT_PERCH_POS), "untuned-route fixture learns the course")
	check(_trigger_range_control(host, chunk, "_lure_interactable", "peris",
		chunk.LURE_SPINDLE_POS),
		"the spindle can fire before calibration instead of treating echo as a permission flag")
	var untuned_state: Dictionary = chunk.get_preview_state()
	var untuned_targets_are_lane: bool = \
		str(untuned_state.get("lure_route_mode", "")) == chunk.LURE_ROUTE_LANE
	for row_v in untuned_state.get("swarm", []) as Array:
		var settle: Vector3 = (row_v as Dictionary).get("lure_settle", Vector3.ZERO)
		untuned_targets_are_lane = untuned_targets_are_lane \
			and is_equal_approx(settle.x, chunk.SWARM_UNTUNED_X) \
			and absf(settle.z - chunk.SWARM_UNTUNED_Z) < 1.0
	check(untuned_targets_are_lane,
		"untuned echo gives every real Enemy a saved settle point inside the marked release lane")
	host.scheduler.advance_ticks(8.0)
	check(not bool(chunk.get_preview_state().get("swarm_clear", true)),
		"the untuned bodies visibly move but remain physical release-lane blockers")
	_set_range_routing(host, chunk, "direct")
	check(_trigger_range_control(host, chunk, "_direct_interactable", "endo",
		chunk.SHORT_BLOOM_POS), "Endo can act on the bad untuned prediction")
	host.scheduler.advance_ticks(chunk.DIRECT_CROSS_DURATION + 0.001)
	host.game_state.snap_character_to("endo", chunk.HIDE_SLIT_POS)
	chunk.headless_process(0.0)
	check(_trigger_range_control(host, chunk, "_hide_interactable", "endo",
		chunk.HIDE_SLIT_POS)
			and str(chunk.get_preview_state().get("last_outcome", "")) == "untuned_echo_blocks_release",
		"release falsifies that prediction with the specific physical echo-route cause")
	var failed_capture := _capture(host)
	var failed_report: Array = chunk.get_preview_state().get("swarm", [])
	_apply_capture(host, chunk, failed_capture)
	check(str(chunk.get_preview_state().get("lure_route_mode", "")) == chunk.LURE_ROUTE_LANE
			and str(chunk.get_preview_state().get("last_outcome", "")) == "untuned_echo_blocks_release",
		"same-presenter restore preserves the failed route selector and readable cause")

	var failed_fresh := await _boot_range()
	_apply_capture(failed_fresh.host, failed_fresh.chunk, failed_capture)
	var fresh_failed_report: Array = failed_fresh.chunk.get_preview_state().get("swarm", [])
	var failed_positions_match := fresh_failed_report.size() == failed_report.size()
	for i in range(fresh_failed_report.size()):
		failed_positions_match = failed_positions_match \
			and ((fresh_failed_report[i] as Dictionary).get("position", Vector3.ZERO) as Vector3).distance_to(
				(failed_report[i] as Dictionary).get("position", Vector3.ZERO) as Vector3) < 0.001
	check(failed_positions_match
			and str(failed_fresh.chunk.get_preview_state().get("lure_route_mode", "")) \
				== failed_fresh.chunk.LURE_ROUTE_LANE,
		"fresh restore reconstructs the lane-blocking Enemy bodies rather than only a permission bit")
	await _discard(failed_fresh.host)
	await _discard(host)

	var tuned := await _boot_range()
	host = tuned.host
	chunk = tuned.chunk
	var arm: MeshInstance3D = chunk.get("_echo_direction_arm")
	var untuned_arm_y := arm.rotation_degrees.y
	check(_trigger_range_control(host, chunk, "_departure_interactable", "aster",
		chunk.WEST_SHELTER_POS), "tuned-route fixture leaves shelter")
	check(_trigger_range_control(host, chunk, "_scout_interactable", "aster",
		chunk.SCOUT_PERCH_POS), "tuned-route fixture learns the course")
	check(_trigger_range_control(host, chunk, "_echo_interactable", "peris",
		chunk.ECHO_COUPLER_POS) and not is_equal_approx(arm.rotation_degrees.y, untuned_arm_y),
		"Peris persistently rotates the physical echo arm to its other detent")
	var feedback: Dictionary = chunk.get_causal_feedback_state()
	var echo_link: Dictionary = {}
	for link_v in feedback.get("links", []) as Array:
		var link := link_v as Dictionary
		if str(link.get("interaction_source_name", "")) == "RangeEchoInteractable":
			echo_link = link
			break
	check(str(echo_link.get("target_name", "")) == "RangeEchoRecessReceiver"
			and str(echo_link.get("owner_character", "")) == "peris"
			and str(echo_link.get("visibility_policy", "")) == "hover_only"
			and str(echo_link.get("path_style", "")) == "movement_chevrons",
		"hovering Peris's coupler draws only her route chevrons to the selected side recess")
	check(_trigger_range_control(host, chunk, "_lure_interactable", "peris",
		chunk.LURE_SPINDLE_POS)
			and str(chunk.get_preview_state().get("lure_route_mode", "")) == chunk.LURE_ROUTE_RECESS,
		"the tuned spindle records a side-recess route before moving the real sweep")
	host.scheduler.advance_ticks(5.0)
	var tuned_capture := _capture(host)
	var tuned_fresh := await _boot_range()
	_apply_capture(tuned_fresh.host, tuned_fresh.chunk, tuned_capture)
	var tuned_report: Array = tuned_fresh.chunk.get_preview_state().get("swarm", [])
	var tuned_targets_are_recess: bool = str(
		tuned_fresh.chunk.get_preview_state().get("lure_route_mode", "")) \
		== tuned_fresh.chunk.LURE_ROUTE_RECESS
	for row_v in tuned_report:
		var settle: Vector3 = (row_v as Dictionary).get("lure_settle", Vector3.ZERO)
		tuned_targets_are_recess = tuned_targets_are_recess \
			and is_equal_approx(settle.x, tuned_fresh.chunk.SWARM_LURE_X) \
			and settle.z > tuned_fresh.chunk.SWARM_CLEAR_Z
	check(tuned_targets_are_recess,
		"fresh restore preserves both the selected recess route and every Enemy's physical endpoint")
	tuned_fresh.host.scheduler.advance_ticks(8.0)
	check(bool(tuned_fresh.chunk.get_preview_state().get("swarm_clear", false)),
		"the same spindle action now clears the lane because the coupler changed its outcome")
	await _discard(tuned_fresh.host)
	await _discard(host)


func _verify_crossing_midpoint_and_rollback() -> Dictionary:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	check(_trigger_range_control(host, chunk, "_departure_interactable", "aster",
		chunk.WEST_SHELTER_POS), "direct-cross fixture departs from shelter")
	_set_range_routing(host, chunk, "direct")
	var hp_before: float = host.game_state.get_stat("endo", "hp")
	var before := _capture(host)
	check(_trigger_range_control(host, chunk, "_direct_interactable", "endo",
		chunk.SHORT_BLOOM_POS), "direct seam commits a physical external traversal")
	var committed: Dictionary = chunk.get_preview_state()
	check(str(committed.get("route_phase", "")) == "crossing"
			and bool(committed.get("cross_in_progress", false))
			and not bool(committed.get("seam_crossed", true))
			and host.game_state.is_external_traversal_active("endo")
			and is_zero_approx(float(committed.get("cross_progress", -1.0))),
		"crossing begins in flight without granting the far edge or seam credit")
	chunk.headless_process(1000.0)
	check(is_zero_approx(float(chunk.get_preview_state().get("cross_progress", -1.0)))
			and is_equal_approx(host.game_state.get_stat("endo", "hp"), hp_before),
		"render delta cannot move Endo or apply direct-route damage")

	host.scheduler.advance_ticks(chunk.DIRECT_CROSS_DURATION * 0.5)
	var midpoint := _capture(host)
	var middle_state: Dictionary = chunk.get_preview_state()
	var middle_pos: Vector3 = host.game_state.get_position("endo")
	check(float(middle_state.get("cross_progress", 0.0)) >= 0.49
			and float(middle_state.get("cross_progress", 1.0)) <= 0.51
			and middle_pos.distance_to(chunk.SHORT_BLOOM_POS) > 0.1
			and middle_pos.distance_to(chunk.DIRECT_CROSS_END_POS) > 0.1,
		"mid-cross snapshot records Endo's real authoritative spatial progress")
	check(host.game_state.get_stat("endo", "hp") < hp_before,
		"direct-route HP loss is produced by the field while Endo is physically inside it")
	for _i in range(120):
		chunk.headless_process(0.5)
	check(is_equal_approx(float(chunk.get_preview_state().get("cross_progress", -1.0)),
			float(middle_state.get("cross_progress", -2.0)))
			and host.game_state.get_position("endo").distance_to(middle_pos) < 0.001,
		"crossing progress is invariant to render-frame partitioning")

	host.scheduler.advance_ticks(chunk.DIRECT_CROSS_DURATION * 0.5 - 0.001)
	check(bool(chunk.get_preview_state().get("cross_in_progress", false))
			and not bool(chunk.get_preview_state().get("seam_crossed", true)),
		"crossing cannot grant its endpoint before the saved deadline")
	host.scheduler.advance_ticks(0.0011)
	var completed: Dictionary = chunk.get_preview_state()
	check(not bool(completed.get("cross_in_progress", true))
			and bool(completed.get("seam_crossed", false))
			and str(completed.get("route_phase", "")) == "midway"
			and host.game_state.get_position("endo").distance_to(chunk.DIRECT_CROSS_END_POS) < 0.01,
		"direct crossing commits exactly once at physical arrival")
	check(is_equal_approx(float(completed.get("mid_seam_damage", -1.0)),
			hp_before - host.game_state.get_stat("endo", "hp")),
		"cross readback reports the real field damage instead of a flag-derived tariff")

	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	check(bool(chunk.get_preview_state().get("cross_in_progress", false))
			and host.game_state.get_position("endo").distance_to(middle_pos) < 0.001,
		"same-instance idempotent rollback reconstructs the exact mid-cross state")
	host.scheduler.advance_ticks(chunk.DIRECT_CROSS_DURATION * 0.5)
	check(bool(chunk.get_preview_state().get("seam_crossed", false))
			and host.game_state.get_position("endo").distance_to(chunk.DIRECT_CROSS_END_POS) < 0.01,
		"restored crossing consumes only its saved remainder")
	await _discard(host)
	return {"before": before, "midpoint": midpoint}


func _verify_fresh_crossing_presenter(midpoint: Dictionary) -> void:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	_apply_capture(host, chunk, midpoint)
	var state: Dictionary = chunk.get_preview_state()
	check(str(state.get("route_phase", "")) == "crossing"
			and bool(state.get("cross_in_progress", false))
			and is_equal_approx(float(state.get("cross_progress", -1.0)), 0.5),
		"fresh presenter reconstructs the saved direct-cross midpoint")
	var hp_mid: float = host.game_state.get_stat("endo", "hp")
	host.scheduler.advance_ticks(chunk.DIRECT_CROSS_DURATION * 0.5 - 0.001)
	check(bool(chunk.get_preview_state().get("cross_in_progress", false)),
		"fresh presenter cannot finish the crossing early")
	host.scheduler.advance_ticks(0.0011)
	check(bool(chunk.get_preview_state().get("seam_crossed", false))
			and host.game_state.get_position("endo").distance_to(chunk.DIRECT_CROSS_END_POS) < 0.01
			and is_equal_approx(host.game_state.get_stat("endo", "hp"), hp_mid),
		"fresh presenter consumes exactly the saved crossing remainder without a phantom field bite")
	await _discard(host)


func _verify_crossing_absence_retracts_future(midpoint: Dictionary) -> void:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	var absent := midpoint.duplicate(true)
	(absent.get("game_state", {}).get("world_state", {}) as Dictionary).erase(chunk.range_authority_key())
	_apply_capture(host, chunk, absent)
	var state: Dictionary = chunk.get_preview_state()
	check(str(state.get("route_phase", "")) == "briefing"
			and not bool(state.get("seam_crossed", true))
			and not bool(state.get("cross_in_progress", true)),
		"missing range authority retracts future crossing phase and seam credit")
	check(not host.game_state.is_external_traversal_active("endo"),
		"absence rollback cancels the otherwise surviving orphaned crossing")
	var held_pos: Vector3 = host.game_state.get_position("endo")
	host.scheduler.advance_ticks(chunk.DIRECT_CROSS_DURATION * 2.0)
	check(host.game_state.get_position("endo").distance_to(held_pos) < 0.001
			and not bool(chunk.get_preview_state().get("seam_crossed", true)),
		"an absent crossing cannot later finish and grant the endpoint")
	await _discard(host)


func _verify_lure_deadline_and_frame_invariance() -> void:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	_setup_to_calibrated(host, chunk)
	check(_trigger_range_control(host, chunk, "_lure_interactable", "peris",
		chunk.LURE_SPINDLE_POS), "lure spindle commits the authored window")
	var record: Dictionary = host.game_state.get_world_state(chunk.range_authority_key(), {})
	check(is_equal_approx(float(record.get("lure_deadline", -1.0)), chunk.LURE_DURATION),
		"lure authority stores one absolute deadline")

	chunk.headless_process(1000.0)
	var after_render := chunk.get_preview_state() as Dictionary
	check(is_equal_approx(float(after_render.get("lure_remaining", -1.0)), chunk.LURE_DURATION),
		"a huge render delta cannot consume gameplay lure time")
	host.scheduler.advance_ticks(10.0)
	var midpoint := _capture(host)
	check(is_equal_approx(float(chunk.get_preview_state().get("lure_remaining", -1.0)), 37.0),
		"scheduler time consumes exactly ten seconds of the lure")
	for _i in range(200):
		chunk.headless_process(0.5)
	check(is_equal_approx(float(chunk.get_preview_state().get("lure_remaining", -1.0)), 37.0),
		"render-frame partitioning cannot alter the saved remainder")
	host.scheduler.advance_ticks(36.999)
	check(bool(chunk.get_preview_state().get("lure_active", false)),
		"lure cannot expire before its authority deadline")
	host.scheduler.advance_ticks(0.001)
	check(not bool(chunk.get_preview_state().get("lure_active", true)),
		"lure expires exactly once at the original deadline")

	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	check(is_equal_approx(float(chunk.get_preview_state().get("lure_remaining", -1.0)), 37.0),
		"idempotent rollback restores the exact lure remainder")
	host.scheduler.advance_ticks(37.0)
	check(not bool(chunk.get_preview_state().get("lure_active", true))
			and is_equal_approx(float(host.scheduler.get_current_tick()), chunk.LURE_DURATION),
		"restored lure consumes only its saved remainder")
	await _discard(host)


func _verify_real_swarm_and_cover() -> Dictionary:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	check(chunk._swarm_enemies.size() == 3,
		"the range owns three real Enemy FSM actors instead of decorative marker meshes")
	var all_registered := true
	for i in range(3):
		all_registered = all_registered and host.game_state.characters.has(chunk._swarm_id(i))
	check(all_registered, "all sweep bodies are registered in authoritative GameState space")

	_setup_to_calibrated(host, chunk)
	check(_trigger_range_control(host, chunk, "_lure_interactable", "peris",
		chunk.LURE_SPINDLE_POS), "spindle calls the reusable lure verb on every sweep actor")
	var all_lured := true
	for enemy in chunk._swarm_enemies:
		all_lured = all_lured and str(enemy.get_state()) == "lured"
	check(all_lured, "all sweep actors enter their saved lured FSM phase")
	host.scheduler.advance_ticks(5.0)
	var midpoint := _capture(host)
	var midpoint_report: Array = chunk.get_preview_state().get("swarm", [])
	var moved := true
	for i in range(midpoint_report.size()):
		var row := midpoint_report[i] as Dictionary
		moved = moved and (row.get("position", Vector3.ZERO) as Vector3).distance_to(chunk._swarm_post(i)) > 1.0
	check(moved, "lured sweep bodies move through GameState rather than render-delta interpolation")

	for _i in range(80):
		chunk.headless_process(0.5)
	var after_render: Array = chunk.get_preview_state().get("swarm", [])
	var render_invariant := after_render.size() == midpoint_report.size()
	for i in range(after_render.size()):
		var a := after_render[i] as Dictionary
		var b := midpoint_report[i] as Dictionary
		render_invariant = render_invariant and (a.get("position", Vector3.ZERO) as Vector3).distance_to(
			b.get("position", Vector3.ZERO) as Vector3) < 0.001
	check(render_invariant, "swarm positions are invariant to render-frame partitioning")

	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	var restored_report: Array = chunk.get_preview_state().get("swarm", [])
	var same_restored := restored_report.size() == midpoint_report.size()
	for i in range(restored_report.size()):
		var a := restored_report[i] as Dictionary
		var b := midpoint_report[i] as Dictionary
		same_restored = same_restored and str(a.get("state", "")) == "lured" \
			and (a.get("position", Vector3.ZERO) as Vector3).distance_to(
				b.get("position", Vector3.ZERO) as Vector3) < 0.001
	check(same_restored, "same-instance rollback restores every lured actor's phase and position")

	host.scheduler.advance_ticks(8.0)
	var cleared: Dictionary = chunk.get_preview_state()
	check(bool(cleared.get("swarm_clear", false)),
		"scheduler motion physically clears the sweep into the side recess")

	var hp_before_safe_cross: float = host.game_state.get_stat("endo", "hp")
	check(_trigger_range_control(host, chunk, "_seam_interactable", "endo",
		chunk.MID_SEAM_POS), "Endo begins the longer unburned seam after the sweep clears")
	host.scheduler.advance_ticks(chunk.SAFE_CROSS_DURATION)
	check(is_equal_approx(host.game_state.get_stat("endo", "hp"), hp_before_safe_cross),
		"the longer seam stays physically outside the direct HazardField for its full traversal")
	host.game_state.snap_character_to("endo", chunk.HIDE_SLIT_POS)
	chunk.headless_process(0.0)
	var covered: Dictionary = chunk.get_preview_state()
	check(int(covered.get("endo_concealment", -1)) == GameState.CONCEAL_FULL
			and bool(host.game_state.is_character_hidden("endo")),
		"the actual Capbage footprint writes full concealment into GameState")
	check(_trigger_range_control(host, chunk, "_hide_interactable", "endo",
		chunk.HIDE_SLIT_POS),
		"hide release succeeds from physical concealment plus actual enemy clearance")
	await _discard(host)
	return {"capture": midpoint, "report": midpoint_report}


func _verify_fresh_swarm_presenter(capture: Dictionary, expected_report: Array) -> void:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	_apply_capture(host, chunk, capture)
	var report: Array = chunk.get_preview_state().get("swarm", [])
	var restored := report.size() == expected_report.size()
	for i in range(report.size()):
		var actual := report[i] as Dictionary
		var expected := expected_report[i] as Dictionary
		restored = restored and str(actual.get("state", "")) == "lured" \
			and str(actual.get("target", "x")) == "" \
			and (actual.get("position", Vector3.ZERO) as Vector3).distance_to(
				expected.get("position", Vector3.ZERO) as Vector3) < 0.001
	check(restored, "fresh presenter reconstructs all saved lured Enemy phases and positions")
	host.scheduler.advance_ticks(8.0)
	check(bool(chunk.get_preview_state().get("swarm_clear", false)),
		"fresh swarm presenters continue the same deterministic side-recess movement")
	await _discard(host)


func _verify_cover_spatial_selectivity() -> void:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	var enemy = chunk._swarm_enemies[0]
	host.game_state.snap_character_to("endo", chunk.HIDE_SLIT_POS)
	enemy.re_post(chunk.HIDE_SLIT_POS + Vector3(2.0, 0.0, 0.0))
	chunk.headless_process(0.0)
	check(host.game_state.is_character_hidden("endo") and not enemy.engage_target("endo"),
		"a nearby real enemy cannot acquire Endo while his body is inside Capbage cover")

	var exposed_pos: Vector3 = chunk.HIDE_SLIT_POS + Vector3(0.0, 0.0, 3.2)
	host.game_state.snap_character_to("endo", exposed_pos)
	enemy.re_post(exposed_pos + Vector3(2.0, 0.0, 0.0))
	chunk.headless_process(0.0)
	check(not host.game_state.is_character_hidden("endo") and enemy.engage_target("endo")
			and str(enemy._current_target_id) == "endo",
		"the same nearby enemy acquires Endo once his body leaves the concealment footprint")
	await _discard(host)


func _verify_winch_midpoint_and_rollback() -> Dictionary:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	_setup_to_calibrated(host, chunk)
	chunk._fail_range("authority_fixture")
	var stats_before := _endo_stats(host)
	var before := _capture(host)
	check(_trigger_range_control(host, chunk, "_recovery_interactable", "endo",
		chunk.RECOVERY_RIG_POS), "reset winch accepts a conscious Endo at its rig")
	var committed := host.game_state.get_external_traversal_state("endo") as Dictionary
	check(str(chunk.get_preview_state().get("route_phase", "")) == "resetting"
			and host.game_state.is_external_traversal_active("endo")
			and str(committed.get("traversal_id", "")).begins_with(chunk.WINCH_TRAVERSAL_PREFIX),
		"winch begins a distinct locked traversal phase")
	check(host.game_state.get_position("endo").distance_to(chunk.WINCH_RETURN_POS) > 100.0
			and int(chunk.get_preview_state().get("reset_count", -1)) == 0,
		"working the winch neither teleports Endo nor commits the reset endpoint")
	check(not _trigger_range_control(host, chunk, "_lure_interactable", "peris",
			chunk.LURE_SPINDLE_POS)
			and not _trigger_range_control(host, chunk, "_seam_interactable", "endo",
				chunk.MID_SEAM_POS),
		"other route verbs are locked while the physical pull is in progress")

	host.scheduler.advance_ticks(4.0)
	var midpoint := _capture(host)
	var middle := host.game_state.get_external_traversal_state("endo") as Dictionary
	var middle_pos: Vector3 = host.game_state.get_position("endo")
	check(float(middle.get("progress", 0.0)) > 0.33
			and float(middle.get("progress", 1.0)) < 0.34
			and middle_pos.distance_to(chunk.RECOVERY_RIG_POS) > 35.0
			and middle_pos.distance_to(chunk.WINCH_RETURN_POS) > 70.0,
		"mid-winch snapshot records real spatial progress")
	check(is_equal_approx(float(middle.get("remaining", -1.0)), 8.0),
		"mid-winch snapshot stores the unconsumed eight-second remainder")
	check(_endo_stats(host) == stats_before, "the moving winch restores or spends no Endo stats")

	host.scheduler.advance_ticks(7.999)
	check(host.game_state.is_external_traversal_active("endo")
			and str(chunk.get_preview_state().get("route_phase", "")) == "resetting",
		"winch cannot commit before its authored deadline")
	host.scheduler.advance_ticks(0.0011)
	check(not host.game_state.is_external_traversal_active("endo")
			and host.game_state.get_position("endo").distance_to(chunk.WINCH_RETURN_POS) < 0.01,
		"uninterrupted winch lands Endo at the visible cable anchor")
	check(str(chunk.get_preview_state().get("route_phase", "")) == "calibrated"
			and int(chunk.get_preview_state().get("reset_count", 0)) == 1,
		"route reset commits only after physical arrival")
	check(_endo_stats(host) == stats_before, "completed winch still preserves HP, stamina, and ATP")

	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	var restored := host.game_state.get_external_traversal_state("endo") as Dictionary
	check(str(chunk.get_preview_state().get("route_phase", "")) == "resetting"
			and is_equal_approx(float(restored.get("progress", -1.0)), float(middle.get("progress", -2.0)))
			and host.game_state.get_position("endo").distance_to(middle_pos) < 0.01,
		"same-instance rollback restores the exact mid-pull state")
	host.scheduler.advance_ticks(8.0)
	check(int(chunk.get_preview_state().get("reset_count", 0)) == 1
			and str(chunk.get_preview_state().get("route_phase", "")) == "calibrated",
		"idempotent restore attaches exactly one winch completion")

	var feedback: Dictionary = chunk.get_causal_feedback_state()
	var route_link: Dictionary = {}
	for link_v in feedback.get("links", []) as Array:
		var link := link_v as Dictionary
		if str(link.get("interaction_source_name", "")) == "RangeRecoveryInteractable":
			route_link = link
			break
	check(chunk.find_child("RangeRecoveryCable", true, false) != null
			and str(route_link.get("path_style", "")) == "movement_chevrons"
			and str(route_link.get("owner_character", "")) == "endo"
			and str(route_link.get("visibility_policy", "")) == "hover_only",
		"winch has a physical cable plus Endo-colored hover route chevrons")
	await _discard(host)
	return {"before": before, "midpoint": midpoint}


func _verify_fresh_winch_presenter(midpoint: Dictionary) -> void:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	_apply_capture(host, chunk, midpoint)
	var state := chunk.get_preview_state() as Dictionary
	check(str(state.get("route_phase", "")) == "resetting"
			and bool(state.get("winch_in_progress", false))
			and is_equal_approx(float(state.get("winch_remaining", -1.0)), 8.0),
		"fresh presenter reconstructs the saved in-flight winch")
	host.scheduler.advance_ticks(7.999)
	check(host.game_state.is_external_traversal_active("endo"),
		"fresh presenter cannot grant an early landing")
	host.scheduler.advance_ticks(0.0011)
	check(not host.game_state.is_external_traversal_active("endo")
			and host.game_state.get_position("endo").distance_to(chunk.WINCH_RETURN_POS) < 0.01
			and int(chunk.get_preview_state().get("reset_count", 0)) == 1,
		"fresh presenter consumes exactly the saved remainder and commits once")
	await _discard(host)


func _verify_missing_record_retracts_future(before: Dictionary) -> void:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	var absent := before.duplicate(true)
	(absent.get("game_state", {}).get("world_state", {}) as Dictionary).erase(chunk.range_authority_key())
	_apply_capture(host, chunk, absent)
	var state := chunk.get_preview_state() as Dictionary
	check(str(state.get("route_phase", "")) == "briefing"
			and (state.get("segments_completed", []) as Array).is_empty()
			and not bool(state.get("scouted", true))
			and not bool(state.get("echo_tuned", true)),
		"missing range record retracts every later local course flag")
	check(not host.game_state.is_external_traversal_active("endo")
			and int(state.get("reset_count", -1)) == 0,
		"missing record cannot preserve a future winch or reset credit")
	var normalized: Dictionary = host.game_state.get_world_state(chunk.range_authority_key(), {})
	check(int(normalized.get("version", 0)) == chunk.RANGE_AUTHORITY_VERSION
			and str(normalized.get("route_phase", "")) == "briefing",
		"legacy absence normalizes to an explicit construction baseline")
	await _discard(host)


func _verify_atomic_shelter_signal_restore() -> void:
	var pair := await _boot_range()
	var host = pair.host
	var chunk = pair.chunk
	_setup_to_calibrated(host, chunk)
	check(_trigger_range_control(host, chunk, "_lure_interactable", "peris",
		chunk.LURE_SPINDLE_POS), "shelter fixture opens the physical sweep window")
	host.scheduler.advance_ticks(12.0)
	check(bool(chunk.get_preview_state().get("swarm_clear", false)),
		"shelter fixture waits for the real sweep bodies to clear")
	check(_trigger_range_control(host, chunk, "_seam_interactable", "endo",
		chunk.MID_SEAM_POS), "shelter fixture commits the safe physical seam")
	host.scheduler.advance_ticks(chunk.SAFE_CROSS_DURATION + 0.001)
	host.game_state.snap_character_to("endo", chunk.HIDE_SLIT_POS)
	chunk.headless_process(0.0)
	check(_trigger_range_control(host, chunk, "_hide_interactable", "endo",
		chunk.HIDE_SLIT_POS)
			and str(chunk.get_preview_state().get("route_phase", "")) == "run",
		"shelter fixture releases the sprint only after concealed sweep clearance")
	for char_id in chunk.PARTY_IDS:
		host.game_state.snap_character_to(char_id, chunk.EAST_SHELTER_POS)
		host.game_state.set_stat(
			char_id,
			"stamina",
			maxf(0.0, host.game_state.get_stat_cap(char_id, "stamina") - 1.0))
	var paid_before := _party_atp(host)
	var signal_box := {"capture": {}}
	var signal_probe := func(_char_id: String, stat: String, _value: float) -> void:
		if stat == "atp" and (signal_box.get("capture", {}) as Dictionary).is_empty():
			signal_box["capture"] = _capture(host)
	host.game_state.stat_changed.connect(signal_probe)
	check(_trigger_range_control(host, chunk, "_east_shelter_interactable", "aster",
		chunk.EAST_SHELTER_POS),
		"east shelter commits one canonical full-party rest")
	host.game_state.stat_changed.disconnect(signal_probe)
	var signal_capture: Dictionary = signal_box.get("capture", {})
	var signal_record: Dictionary = (
		signal_capture.get("game_state", {}).get("world_state", {}).get(
			chunk.range_authority_key(), {}) as Dictionary)
	check(not signal_capture.is_empty()
			and str(signal_record.get("shelter_rest_phase", "")) == "committing"
			and _party_paid_once(host, paid_before) and _all_party_resting(host),
		"first ATP signal observes COMMITTING only after every range party effect exists")
	check(str(chunk.get_preview_state().get("route_phase", "")) == "complete"
			and str(chunk.get_preview_state().get("shelter_rest_phase", "")) == "rested",
		"ordinary east-shelter batch finalizes the route")

	var same_events_before := _party_rest_event_count(host)
	_apply_capture(host, chunk, signal_capture)
	host.scheduler.advance_ticks(0.001)
	check(str(chunk.get_preview_state().get("route_phase", "")) == "complete"
			and str(chunk.get_preview_state().get("shelter_rest_phase", "")) == "rested"
			and _party_paid_once(host, paid_before) and _all_party_resting(host)
			and _party_rest_event_count(host) == same_events_before,
		"same-presenter signal-time restore reconciles without replay or a second ATP payment")

	var fresh := await _boot_range()
	var fresh_events_before := _party_rest_event_count(fresh.host)
	_apply_capture(fresh.host, fresh.chunk, signal_capture)
	fresh.host.scheduler.advance_ticks(0.001)
	check(str(fresh.chunk.get_preview_state().get("route_phase", "")) == "complete"
			and str(fresh.chunk.get_preview_state().get("shelter_rest_phase", "")) == "rested"
			and _party_paid_once(fresh.host, paid_before)
			and _all_party_resting(fresh.host)
			and _party_rest_event_count(fresh.host) == fresh_events_before,
		"fresh signal-time restore reconstructs the same atomic range rest without replay")
	await _discard(fresh.host)
	await _discard(host)


func _boot_range() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = RangeScript.new()
	chunk.attach_chunk_host(host, "survival_range_authority_fixture")
	for char_id_v in chunk.get_spawn_positions().keys():
		var char_id := str(char_id_v)
		host.game_state.register_character(char_id, chunk.get_spawn_positions()[char_id], 3.0, {
			"hp": 100.0, "stamina": 100.0, "atp": 8.0,
		})
	host.add_child(chunk)
	await process_frame
	return {"host": host, "chunk": chunk}


func _trigger_range_control(
	host,
	chunk,
	control_property: String,
	actor: String,
	position: Vector3
) -> bool:
	host.active_character = actor
	host.game_state.snap_character_to(actor, position)
	var control: Node = chunk.get(control_property)
	if control == null:
		return false
	control.set("active_character", actor)
	return bool(control.call("_trigger", false))


func _set_range_routing(host, chunk, mode: String) -> void:
	host.set_preview_routing_mode(mode)
	chunk.on_preview_routing_changed(mode)


func _setup_to_calibrated(host, chunk) -> void:
	check(_trigger_range_control(host, chunk, "_departure_interactable", "aster",
		chunk.WEST_SHELTER_POS), "fixture departs from west shelter")
	check(_trigger_range_control(host, chunk, "_scout_interactable", "aster",
		chunk.SCOUT_PERCH_POS), "fixture resolves Aster's route scan")
	check(_trigger_range_control(host, chunk, "_echo_interactable", "peris",
		chunk.ECHO_COUPLER_POS), "fixture calibrates the echo chain")


func _endo_stats(host) -> Dictionary:
	return {
		"hp": host.game_state.get_stat("endo", "hp"),
		"stamina": host.game_state.get_stat("endo", "stamina"),
		"atp": host.game_state.get_stat("endo", "atp"),
	}


func _party_atp(host) -> Dictionary:
	var result := {}
	for char_id in ["aster", "peris", "endo"]:
		result[char_id] = host.game_state.get_stat(char_id, "atp")
	return result


func _party_paid_once(host, before: Dictionary) -> bool:
	for char_id in ["aster", "peris", "endo"]:
		if not before.has(char_id) \
				or not is_equal_approx(
					host.game_state.get_stat(char_id, "atp"),
					float(before[char_id]) - 1.0):
			return false
	return true


func _all_party_resting(host) -> bool:
	for char_id in ["aster", "peris", "endo"]:
		if not host.game_state.is_resting(char_id):
			return false
	return true


func _party_rest_event_count(host) -> int:
	var count := 0
	if host == null or host.game_state == null or host.game_state.event_log == null:
		return count
	for event_v in host.game_state.event_log.events:
		var event: Dictionary = event_v
		if str(event.get("kind", "")) == str(GameEvent.KIND_PARTY_REST):
			count += 1
	return count


func _capture(host) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _apply_capture(host, chunk, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	chunk.on_game_state_snapshot_restored()


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
