extends SceneTree

## Focused regression harness for the Fragment Preview's three gameplay clocks. The preview is kept
## detached from the SceneTree on purpose: scheduler callbacks and saved authority must produce the
## same result without a render/process frame helping them along.

const PreviewScript = preload("res://scripts/fragments/fragment_preview_sequence.gd")
const TEST_CHARACTER := "aster"
const TEST_ABILITY := "authority_test_ability"
const ACTIVE_SECONDS := 4.0
const COOLDOWN_SECONDS := 2.0
const MIDPOINT_TICK := 1.1
const EPSILON := 0.0001

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_stamina_strict_future_boundary()
	_verify_pause_freezes_all_preview_clocks()
	_verify_coarse_and_fine_fast_forward_match()
	_verify_game_state_owns_sprint_drain()
	_verify_ground_item_label_visibility()
	var fixture := _build_midpoint_fixture()
	_verify_same_presenter_midpoint_restore(fixture)
	_verify_fresh_presenter_midpoint_restore(fixture)
	_discard_context(fixture)
	_verify_absent_record_retracts_future_state()
	print("FRAGMENT PREVIEW RUNTIME AUTHORITY: %d checks, %d failures" % [
		_checks, _failures,
	])
	quit(0 if _failures == 0 else 1)


func _verify_stamina_strict_future_boundary() -> void:
	var preview = PreviewScript.new()
	preview.set("_preview_stamina_epoch", 0.1)
	check(_approx(float(preview.call("_next_preview_stamina_tick_after", 0.35)), 0.6),
		"preview fractional stamina epoch reconstructs the next strict-future tick, not now")
	preview.free()


func _verify_pause_freezes_all_preview_clocks() -> void:
	var context := _make_context()
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var preview = context.preview
	scheduler.pause()
	scheduler.advance_ticks(3.0)
	preview.call("_sync_preview_clock_from_authority", false)
	check(is_zero_approx(float(scheduler.get_current_tick())),
		"paused scheduler does not advance the authoritative preview tick")
	check(_approx(state.get_stat(TEST_CHARACTER, "stamina"), 20.0),
		"paused scheduler performs no field-stamina regeneration")
	check(_ability_state(preview) == "active"
			and _approx(_ability_remaining(preview), ACTIVE_SECONDS),
		"paused scheduler performs no preview-ability countdown")
	check(_clock_matches(preview, 1, 0.0),
		"paused scheduler performs no preview-clock accumulation")

	scheduler.resume()
	scheduler.advance_ticks(0.25)
	preview.call("_sync_preview_clock_from_authority", false)
	check(_approx(state.get_stat(TEST_CHARACTER, "stamina"), 22.5),
		"resuming dispatches the fixed field-stamina cadence")
	check(_ability_state(preview) == "active"
			and _approx(_ability_remaining(preview), 3.75),
		"resuming advances the ability from scheduler time")
	check(not _clock_matches(preview, 1, 0.0),
		"resuming projects elapsed scheduler time into the preview clock")
	_discard_context(context)


func _verify_coarse_and_fine_fast_forward_match() -> void:
	var fine := _make_context()
	var coarse := _make_context()
	var fine_scheduler: EventScheduler = fine.scheduler
	var coarse_scheduler: EventScheduler = coarse.scheduler
	for _step in range(80):
		fine_scheduler.advance_ticks(0.0625)
	coarse_scheduler.advance_ticks(5.0)
	fine.preview.call("_sync_preview_clock_from_authority", false)
	coarse.preview.call("_sync_preview_clock_from_authority", false)

	check(_approx(
			fine.state.get_stat(TEST_CHARACTER, "stamina"),
			coarse.state.get_stat(TEST_CHARACTER, "stamina")),
		"fine and coarse fast-forward produce identical field stamina")
	check(_ability_state(fine.preview) == "cooldown"
			and _ability_state(coarse.preview) == "cooldown"
			and _approx(_ability_remaining(fine.preview), 1.0)
			and _approx(_ability_remaining(coarse.preview), 1.0),
		"fine and coarse fast-forward cross the active deadline identically")
	var fine_clock: Dictionary = fine.preview.call("get_preview_clock_state")
	var coarse_clock: Dictionary = coarse.preview.call("get_preview_clock_state")
	check(int(fine_clock.get("day", -1)) == int(coarse_clock.get("day", -2))
			and _approx(float(fine_clock.get("time", -1.0)),
				float(coarse_clock.get("time", -2.0))),
		"fine and coarse fast-forward project the same day/night clock")
	check(fine_scheduler.pending_count() == coarse_scheduler.pending_count()
			and fine_scheduler.pending_count() == 2,
		"both step sizes leave one stamina and one ability callback armed (fine=%d coarse=%d)" % [
			fine_scheduler.pending_count(), coarse_scheduler.pending_count(),
		])
	_discard_context(fine)
	_discard_context(coarse)


func _verify_ground_item_label_visibility() -> void:
	var context := _make_context()
	var state: GameState = context.state
	var preview: Node = context.preview
	var hidden_item := state.spawn_item("lysate", Vector3.ZERO, {
		"ground_label_visible": false,
	})
	var default_item := state.spawn_item("lysate", Vector3(1.0, 0.0, 0.0))
	preview.call("_ensure_preview_item_node", hidden_item)
	preview.call("_ensure_preview_item_node", default_item)
	var item_nodes: Dictionary = preview.get("_preview_item_nodes")
	var hidden_root := item_nodes.get(hidden_item, null) as Node3D
	var default_root := item_nodes.get(default_item, null) as Node3D
	# The authority harness deliberately keeps the full preview detached, while this presenter
	# assigns world transforms. Seat only the two item visuals under a tiny in-tree holder so the
	# check exercises production global-position math without booting the whole preview scene.
	var presenter_holder := Node3D.new()
	root.add_child(presenter_holder)
	for item_root in [hidden_root, default_root]:
		if item_root != null:
			preview.remove_child(item_root)
			presenter_holder.add_child(item_root)
	preview.call("_refresh_preview_items")
	var hidden_label := (
		hidden_root.get_node_or_null("Label") as Label3D
		if hidden_root != null else null
	)
	var default_label := (
		default_root.get_node_or_null("Label") as Label3D
		if default_root != null else null
	)
	check(hidden_label != null and not hidden_label.visible,
		"ground item presenter honors an explicit hidden-label affordance")
	check(default_label != null and default_label.visible,
		"ground item labels remain visible by default")
	preview.set("_preview_item_nodes", {})
	presenter_holder.free()
	_discard_context(context)


func _verify_game_state_owns_sprint_drain() -> void:
	var fine := _make_context(100.0, "ready", 0.0)
	var coarse := _make_context(100.0, "ready", 0.0)
	for context in [fine, coarse]:
		var state: GameState = context.state
		# Entering run while idle is GameState's ordinary one-cadence setup. The pre-existing
		# move-then-run double-arm defect found while building this verifier is reported separately.
		state.set_running(TEST_CHARACTER, true)
		check(state.command_move_to_pos(TEST_CHARACTER, Vector3(100.0, 0.0, 0.0)),
			"sprint-drain fixture begins a scheduler-owned movement")

	var fine_scheduler: EventScheduler = fine.scheduler
	var coarse_scheduler: EventScheduler = coarse.scheduler
	fine_scheduler.pause()
	fine_scheduler.advance_ticks(1.0)
	check(_approx(fine.state.get_stat(TEST_CHARACTER, "stamina"), 100.0),
		"sprint drain also freezes while gameplay time is paused")
	fine_scheduler.resume()
	for _step in range(10):
		fine_scheduler.advance_ticks(0.1)
	coarse_scheduler.advance_ticks(1.0)
	check(_approx(fine.state.get_stat(TEST_CHARACTER, "stamina"), 82.0)
			and _approx(coarse.state.get_stat(TEST_CHARACTER, "stamina"), 82.0),
		"GameState drains the authored 18 stamina per scheduler second at either step size "
			+ "(fine=%.3f coarse=%.3f)" % [
				fine.state.get_stat(TEST_CHARACTER, "stamina"),
				coarse.state.get_stat(TEST_CHARACTER, "stamina"),
			])
	check(fine.state.is_running(TEST_CHARACTER) and coarse.state.is_running(TEST_CHARACTER),
		"preview field regeneration does not fight GameState's live running phase")
	_discard_context(fine)
	_discard_context(coarse)


func _build_midpoint_fixture() -> Dictionary:
	var context := _make_context()
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var preview = context.preview
	scheduler.advance_ticks(MIDPOINT_TICK)
	preview.call("_sync_preview_clock_from_authority", false)
	var events_before_save := int((context.log as EventLog).size())
	var snapshot: Dictionary = _json_round_trip(preview.call("build_save_snapshot"))
	var authority: Dictionary = state.get_world_state(
		preview.call("preview_runtime_authority_key"), {})
	var clock: Dictionary = authority.get("clock", {}) as Dictionary
	var abilities: Dictionary = authority.get("abilities", {}) as Dictionary
	var ability: Dictionary = abilities.get(TEST_ABILITY, {}) as Dictionary
	check(int(authority.get("version", 0)) == 1
			and str(authority.get("chunk", "")) == "stacks",
		"save snapshot carries a versioned fragment-preview authority record")
	check(_approx(float(clock.get("anchor_tick", -1.0)), 0.0)
			and _approx(float(authority.get("stamina_epoch", -1.0)), 0.0),
		"clock and stamina save portable absolute cadence anchors")
	check(str(ability.get("state", "")) == "active"
			and _approx(float(ability.get("deadline", -1.0)), ACTIVE_SECONDS),
		"ability save stores its semantic phase and absolute deadline")
	check(_approx(state.get_stat(TEST_CHARACTER, "stamina"), 30.0)
			and _approx(_ability_remaining(preview), 2.9),
		"midpoint fixture captures committed stamina and remaining ability time")
	check((context.log as EventLog).size() == events_before_save,
		"building a save snapshot emits no synthetic gameplay command")
	context["snapshot"] = snapshot
	context["saved_clock"] = preview.call("get_preview_clock_state")
	return context


func _verify_same_presenter_midpoint_restore(context: Dictionary) -> void:
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var preview = context.preview
	scheduler.advance_ticks(5.0)
	check(_ability_state(preview) == "ready"
			and state.get_stat(TEST_CHARACTER, "stamina") > 30.0,
		"same presenter reaches a distinguishable future before rollback")

	preview.call("apply_save_snapshot", context.snapshot)
	# This focused harness restores the state snapshot without replacing the production replay log.
	# Discard future-branch events so new post-load commands remain monotonic from the restored clock.
	(context.log as EventLog).clear()
	preview.call("on_game_state_snapshot_restored")
	preview.call("_sync_preview_clock_from_authority", false)
	check(_approx(float(scheduler.get_current_tick()), MIDPOINT_TICK)
			and _approx(state.get_stat(TEST_CHARACTER, "stamina"), 30.0),
		"same-presenter load replaces future scheduler time and stamina")
	check(_ability_state(preview) == "active"
			and _approx(_ability_remaining(preview), 2.9),
		"same-presenter load restores the midpoint ability phase")
	check(_same_clock(preview.call("get_preview_clock_state"), context.saved_clock),
		"same-presenter load restores the analytic preview clock")
	check(scheduler.pending_count() == 2,
		"repeated same-presenter attachment arms exactly one callback per runtime clock")

	scheduler.advance_ticks(0.149)
	check(_approx(state.get_stat(TEST_CHARACTER, "stamina"), 30.0),
		"same-presenter stamina waits for the saved absolute cadence boundary")
	scheduler.advance_ticks(0.002)
	check(_approx(state.get_stat(TEST_CHARACTER, "stamina"), 32.5),
		"same-presenter stamina resumes at the saved 1.25-second cadence tick")
	scheduler.advance_ticks(2.748)
	check(_ability_state(preview) == "active",
		"restored active ability cannot complete before its saved deadline")
	scheduler.advance_ticks(0.002)
	var runtime: Dictionary = preview.get("_ability_runtime")
	var ability: Dictionary = runtime.get(TEST_ABILITY, {}) as Dictionary
	check(_ability_state(preview) == "cooldown"
			and _approx(float(ability.get("deadline", -1.0)), 6.0)
			and _approx(state.get_stat(TEST_CHARACTER, "stamina"), 60.0),
		"same-presenter deadline fires once and preserves the original cooldown boundary")


func _verify_fresh_presenter_midpoint_restore(fixture: Dictionary) -> void:
	var fresh := _make_context()
	var scheduler: EventScheduler = fresh.scheduler
	var state: GameState = fresh.state
	var preview = fresh.preview
	preview.call("apply_save_snapshot", fixture.snapshot)
	preview.call("on_game_state_snapshot_restored")
	preview.call("_sync_preview_clock_from_authority", false)
	check(_approx(float(scheduler.get_current_tick()), MIDPOINT_TICK)
			and _approx(state.get_stat(TEST_CHARACTER, "stamina"), 30.0),
		"fresh presenter restores scheduler time and committed stamina")
	check(_ability_state(preview) == "active"
			and _approx(_ability_remaining(preview), 2.9),
		"fresh presenter restores the saved ability phase without replaying activation")
	check(_same_clock(preview.call("get_preview_clock_state"), fixture.saved_clock),
		"fresh presenter projects the same saved day/night clock")
	check(scheduler.pending_count() == 2,
		"fresh load plus repeated attachment still arms one stamina and one ability callback")

	scheduler.advance_ticks(2.901)
	var runtime: Dictionary = preview.get("_ability_runtime")
	var ability: Dictionary = runtime.get(TEST_ABILITY, {}) as Dictionary
	check(_ability_state(preview) == "cooldown"
			and _approx(float(ability.get("deadline", -1.0)), 6.0)
			and _approx(state.get_stat(TEST_CHARACTER, "stamina"), 60.0),
		"fresh presenter crosses the saved active deadline exactly as the original would")
	_discard_context(fresh)


func _verify_absent_record_retracts_future_state() -> void:
	var context := _make_context()
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var preview = context.preview
	var snapshot: Dictionary = _json_round_trip(preview.call("build_save_snapshot"))
	var game_state_snapshot: Dictionary = snapshot.get("game_state", {}) as Dictionary
	var world_state: Dictionary = game_state_snapshot.get("world_state", {}) as Dictionary
	world_state.erase(preview.call("preview_runtime_authority_key"))
	game_state_snapshot["world_state"] = world_state
	snapshot["game_state"] = game_state_snapshot

	scheduler.advance_ticks(6.5)
	check(_ability_state(preview) == "ready",
		"absence fixture first creates a later completed ability branch")
	preview.call("apply_save_snapshot", snapshot)
	preview.call("on_game_state_snapshot_restored")
	check(_ability_state(preview) == "active"
			and _approx(_ability_remaining(preview), ACTIVE_SECONDS),
		"missing authority retracts the later branch to the authored baseline")
	check(not state.world_state.has(preview.call("preview_runtime_authority_key")),
		"baseline retraction does not invent authority during restoration")
	check(scheduler.pending_count() == 2,
		"baseline retraction leaves no callbacks from the discarded future")
	_discard_context(context)


func _make_context(
		initial_stamina := 20.0,
		ability_state := "active",
		ability_remaining := ACTIVE_SECONDS
	) -> Dictionary:
	var scheduler := EventScheduler.new()
	var state := GameState.new()
	state.scheduler = scheduler
	state.run_stamina_drain_per_sec = 18.0
	var log := EventLog.new()
	state.event_log = log
	state.register_character(TEST_CHARACTER, Vector3.ZERO, 3.4, {
		"hp": 100.0,
		"stamina": initial_stamina,
		"atp": 6.0,
	})

	var preview = PreviewScript.new()
	preview.preview_chunk = "stacks"
	preview.set("_scheduler", scheduler)
	preview.set("_game_state", state)
	preview.set("_character_state", {
		TEST_CHARACTER: {
			"hp": 100.0,
			"sta": initial_stamina,
			"atp": 6.0,
			"status": "",
			"visible": true,
		},
	})
	preview.set("_active_char_id", TEST_CHARACTER)
	var selection: Array[String] = [TEST_CHARACTER]
	preview.set("_selected_char_ids", selection)
	preview.set("_ability_defs", {
		TEST_ABILITY: {
			"owner": TEST_CHARACTER,
			"cooldown": COOLDOWN_SECONDS,
			"active_status": "authority_active",
		},
	})
	var order: Array[String] = [TEST_ABILITY]
	preview.set("_ability_order", order)
	preview.set("_ability_runtime", {
		TEST_ABILITY: {
			"base_state": ability_state,
			"remaining": ability_remaining,
			"deadline": -1.0,
		},
	})
	var cycle = preview.get("_preview_cycle")
	cycle.call("configure", 10.0, 10.0)
	preview.set("_preview_day", 1)
	preview.set("_preview_time", 0.0)
	preview.set("_preview_clock_running", true)
	preview.set("_preview_show_time", true)
	preview.call("_anchor_preview_clock", 1, 0.0)
	preview.call("_capture_preview_runtime_baseline")
	preview.call("_start_preview_runtime_from_current_preset")
	return {
		"scheduler": scheduler,
		"state": state,
		"preview": preview,
		"log": log,
	}


func _discard_context(context: Dictionary) -> void:
	var scheduler: EventScheduler = context.get("scheduler")
	if scheduler != null:
		scheduler.clear()
	var preview: Node = context.get("preview")
	if preview != null and is_instance_valid(preview):
		preview.free()


func _ability_state(preview: Node) -> String:
	var runtime: Dictionary = preview.get("_ability_runtime")
	return str((runtime.get(TEST_ABILITY, {}) as Dictionary).get("base_state", ""))


func _ability_remaining(preview: Node) -> float:
	return float(preview.call("_preview_ability_remaining", TEST_ABILITY))


func _clock_matches(preview: Node, day: int, time_of_day: float) -> bool:
	var clock: Dictionary = preview.call("get_preview_clock_state")
	return int(clock.get("day", -1)) == day \
		and _approx(float(clock.get("time", -1.0)), time_of_day)


func _same_clock(first: Dictionary, second: Dictionary) -> bool:
	return int(first.get("day", -1)) == int(second.get("day", -2)) \
		and _approx(float(first.get("time", -1.0)), float(second.get("time", -2.0)))


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _approx(first: float, second: float) -> bool:
	return absf(first - second) <= EPSILON


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
