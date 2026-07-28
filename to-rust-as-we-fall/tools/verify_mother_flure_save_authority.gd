extends SceneTree

## Truthful-physics regression for Mother Flure's debris, installed gear, and Rings handoff.
## It exercises same-presenter rollback, a freshly constructed presenter, missing-record rollback,
## render-frame invariance, and real path topology on both authored blockers.

const HostScript := preload("res://tools/mother_flure_authority_host.gd")
const MotherScript := preload("res://scripts/fragments/chunks/mother_flure_chunk.gd")
const FIXTURE_ID := "mother_flure_authority_fixture"

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	EventLog.print_events = false
	await _verify_source_receipt_barriers()
	await _verify_source_trigger_seam_rollback()
	await _verify_root_hazard_cadence_authority()
	await _verify_portal_transit_authority()
	await _verify_root_gate_timing_and_restore()
	var captures := await _verify_midpoint_same_fresh_and_absence()
	await _verify_frame_invariance(captures.get("committed", {}))
	await _verify_collapse_topology()
	await _verify_rings_gate_topology()
	await _verify_full_party_exit_authority()
	print("MOTHER FLURE SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_source_receipt_barriers() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var initial_record := JSON.stringify(
		host.game_state.get_world_state(chunk.mother_authority_key(), {})
	)
	_check(
		not chunk.activate_terminal("term_gamma")
			and not chunk.use_portal()
			and not chunk.activate_fragment_move("gear_latch", 1)
			and not chunk.clear_collapse()
			and not chunk.harvest_body("body_a")
			and not chunk.pick_up_gear()
			and not chunk.install_gear_at(chunk.CORRECT_REPAIR_ID)
			and not chunk.tend_mother()
			and not chunk.complete_exit_handoff()
			and JSON.stringify(host.game_state.get_world_state(
				chunk.mother_authority_key(), {})) == initial_record,
		"retired public verbs cannot manufacture any Mother Flure consequence"
	)

	var terminal: Node = chunk._terminal_interactables["term_gamma"]
	terminal.active_character = "aster"
	host.game_state.snap_character_to("aster", terminal.global_position + Vector3(20.0, 0.0, 0.0))
	_check(not bool(terminal.call("_trigger", false))
		and str(chunk.get_preview_state().active_terminal) == "",
		"the real terminal rejects a remote actor before consuming its source")
	host.game_state.snap_character_to("aster", terminal.global_position)
	terminal.active_character = "peris"
	_check(not bool(terminal.call("_trigger", false))
		and str(chunk.get_preview_state().active_terminal) == "",
		"a nearby worker cannot substitute for the terminal's required Aster receipt")
	terminal.active_character = "aster"
	chunk._on_terminal_interacted(terminal, "term_gamma")
	_check(str(chunk.get_preview_state().active_terminal) == "",
		"a direct terminal callback without a consumed trigger receipt is inert")
	_check(_drive_terminal(host, chunk, "term_gamma"),
		"source-barrier fixture accepts the exact physical terminal")

	var portal: Node = chunk._portal_entry_interactable
	host.game_state.snap_character_to(
		"peris", portal.global_position + Vector3(20.0, 0.0, 0.0)
	)
	portal.active_character = "peris"
	_check(not bool(portal.call("_trigger", false))
		and not host.game_state.is_external_traversal_active("peris"),
		"the real portal mouth rejects a remote Peris before consuming its source")
	host.game_state.snap_character_to("peris", portal.global_position)
	portal.active_character = "aster"
	_check(not bool(portal.call("_trigger", false))
		and not host.game_state.is_external_traversal_active("peris"),
		"a nearby worker cannot substitute for Peris at the portal mouth")
	portal.active_character = "peris"
	chunk._on_portal_interacted(portal)
	_check(not host.game_state.is_external_traversal_active("peris"),
		"a direct portal callback cannot manufacture a crossing")
	_check(_drive_portal(host, chunk),
		"source-barrier fixture accepts the exact physical portal mouth")
	host.scheduler.advance_ticks(chunk.PORTAL_TRANSIT_SECONDS)
	var root_source: Node = chunk._root_control_interactables[
		chunk._root_control_key("gear_latch", 1)
	]
	host.game_state.snap_character_to(
		"peris", root_source.global_position + Vector3(20.0, 0.0, 0.0)
	)
	root_source.active_character = "peris"
	_check(not bool(root_source.call("_trigger", false))
		and int(chunk._roots.gear_latch.target_anchor) < 0,
		"the real service bud rejects remote root movement before consuming its source")
	host.game_state.snap_character_to("peris", root_source.global_position)
	root_source.active_character = "aster"
	_check(not bool(root_source.call("_trigger", false))
		and int(chunk._roots.gear_latch.target_anchor) < 0,
		"a nearby worker cannot substitute for Peris at a service bud")
	root_source.active_character = "peris"
	chunk._on_root_control_interacted(root_source, "gear_latch", 1)
	_check(int(chunk._roots.gear_latch.target_anchor) < 0,
		"a direct root callback cannot reserve a board destination")
	_check(_drive_root_control(host, chunk, "gear_latch", 1),
		"source-barrier fixture accepts the exact physical service bud")
	host.scheduler.advance_ticks(chunk.ROOT_SLIDE_DURATION + chunk.ROOT_SWARM_LAG
		+ chunk.ROOT_SWARM_DURATION)

	var collapse: Node = chunk._collapse_interactable
	host.game_state.snap_character_to(
		"endo", collapse.global_position + Vector3(20.0, 0.0, 0.0)
	)
	collapse.active_character = "endo"
	_check(not bool(collapse.call("_trigger", false))
		and str(chunk.get_preview_state().collapse_phase) == chunk.COLLAPSE_PHASE_BLOCKED,
		"the real collapse rejects remote force before consuming its source")
	host.game_state.snap_character_to("endo", collapse.global_position)
	collapse.active_character = "aster"
	_check(not bool(collapse.call("_trigger", false))
		and str(chunk.get_preview_state().collapse_phase) == chunk.COLLAPSE_PHASE_BLOCKED,
		"a nearby wrong worker cannot substitute for Endo at the collapse")
	collapse.active_character = "endo"
	chunk._on_collapse_interacted(collapse)
	_check(str(chunk.get_preview_state().collapse_phase) == chunk.COLLAPSE_PHASE_BLOCKED,
		"a direct collapse callback cannot begin the debris shift")
	_check(_drive_collapse(host, chunk),
		"source-barrier fixture accepts Endo at the exact collapse")
	host.scheduler.advance_ticks(chunk.COLLAPSE_SHIFT_SECONDS)
	var body_source: Node = chunk._body_interactables["body_a"]
	host.game_state.snap_character_to(
		"endo", body_source.global_position + Vector3(20.0, 0.0, 0.0)
	)
	body_source.active_character = "endo"
	var body_before := int(chunk.get_preview_state().bodies.body_a)
	_check(not bool(body_source.call("_trigger", false))
		and int(chunk.get_preview_state().bodies.body_a) == body_before,
		"the real corpse rejects a remote harvest before consuming its source")
	host.game_state.snap_character_to("endo", body_source.global_position)
	body_source.active_character = "aster"
	_check(not bool(body_source.call("_trigger", false))
		and int(chunk.get_preview_state().bodies.body_a) == body_before,
		"a nearby worker cannot substitute for Endo at a corpse source")
	body_source.active_character = "endo"
	chunk._on_body_harvest_interacted(body_source, "body_a")
	_check(int(chunk.get_preview_state().bodies.body_a) == body_before,
		"a direct corpse callback cannot mint or move a source nodule")

	_set_solved_roots(chunk)
	var gear_source: Node = chunk._gear_interactable
	host.game_state.snap_character_to(
		"endo", gear_source.global_position + Vector3(20.0, 0.0, 0.0)
	)
	gear_source.active_character = "endo"
	_check(not bool(gear_source.call("_trigger", false))
		and not chunk._endo_holds_gear(),
		"the real gear pedestal rejects a remote lift before consuming its source")
	host.game_state.snap_character_to("endo", gear_source.global_position)
	gear_source.active_character = "aster"
	_check(not bool(gear_source.call("_trigger", false))
		and not chunk._endo_holds_gear(),
		"a nearby worker cannot substitute for Endo at the gear pedestal")
	gear_source.active_character = "endo"
	chunk._on_gear_pickup_interacted(gear_source)
	_check(not chunk._endo_holds_gear(),
		"a direct gear callback cannot place the gear in Endo's hands")
	_check(_drive_gear_pickup(host, chunk),
		"source-barrier fixture accepts the exact gear pedestal")
	var install_source: Node = chunk._repair_interactables[chunk.CORRECT_REPAIR_ID]
	host.game_state.snap_character_to(
		"endo", install_source.global_position + Vector3(20.0, 0.0, 0.0)
	)
	install_source.active_character = "endo"
	_check(not bool(install_source.call("_trigger", false))
		and not bool(chunk.get_preview_state().gear_installed),
		"the real repair mount rejects a remote installation before consuming its source")
	host.game_state.snap_character_to("endo", install_source.global_position)
	install_source.active_character = "aster"
	_check(not bool(install_source.call("_trigger", false))
		and not bool(chunk.get_preview_state().gear_installed),
		"a nearby worker cannot substitute for Endo at the repair mount")
	install_source.active_character = "endo"
	chunk._on_gear_install_interacted(install_source, chunk.CORRECT_REPAIR_ID)
	_check(not bool(chunk.get_preview_state().gear_installed),
		"a direct repair callback cannot consume the carried gear")
	_check(_drive_gear_install(host, chunk, chunk.CORRECT_REPAIR_ID),
		"source-barrier fixture accepts the exact repair mount")
	var mother_source: Node = chunk._mother_interactable
	host.game_state.snap_character_to(
		"peris", mother_source.global_position + Vector3(20.0, 0.0, 0.0)
	)
	mother_source.active_character = "peris"
	_check(not bool(mother_source.call("_trigger", false))
		and not bool(chunk.get_preview_state().mother_tended),
		"Mother Flure rejects remote tending before consuming her source")
	host.game_state.snap_character_to("peris", mother_source.global_position)
	mother_source.active_character = "aster"
	_check(not bool(mother_source.call("_trigger", false))
		and not bool(chunk.get_preview_state().mother_tended),
		"a nearby worker cannot substitute for Peris while tending Mother")
	mother_source.active_character = "peris"
	chunk._on_mother_tend_interacted(mother_source)
	_check(not bool(chunk.get_preview_state().mother_tended),
		"a direct tending callback cannot open the Rings route")
	_check(_drive_mother_tend(host, chunk),
		"source-barrier fixture accepts Peris at Mother Flure's exact fixture")
	await _discard(host)


func _verify_source_trigger_seam_rollback() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var source: Node = chunk._terminal_interactables["term_beta"]
	var seam_box := {"capture": {}}
	var receipt_listener := func(data_id: String, actor: String) -> void:
		if data_id == str(source.get("data_id")) and actor == "aster" \
				and (seam_box.capture as Dictionary).is_empty():
			seam_box.capture = _capture(host)
	host.game_state.interactable_triggered.connect(receipt_listener)
	_check(_drive_terminal(host, chunk, "term_beta"),
		"ordinary terminal interaction crosses the accepted source-receipt seam")
	host.game_state.interactable_triggered.disconnect(receipt_listener)
	var seam_capture: Dictionary = seam_box.capture
	var captured_game_state: Dictionary = seam_capture.get("game_state", {})
	var captured_interactables: Dictionary = captured_game_state.get(
		"interactables", {}
	)
	var captured_spec: Dictionary = captured_interactables.get(
		str(source.get("data_id")), {}
	)
	var captured_record: Dictionary = (
		captured_game_state.get("world_state", {}) as Dictionary
	).get(chunk.mother_authority_key(), {})
	_check(not seam_capture.is_empty()
			and bool(captured_spec.get("one_shot", false))
			and bool(captured_spec.get("triggered", false))
			and not bool(captured_spec.get("enabled", true))
			and str(captured_record.get("active_terminal", "")) == "",
		"source-receipt snapshot precedes the owner consequence and retains no inferred tuning")

	_apply_capture(host, chunk, seam_capture)
	_apply_capture(host, chunk, seam_capture)
	var same_spec: Dictionary = host.game_state.get_interactable(
		str(source.get("data_id"))
	)
	_check(str(chunk.get_preview_state().active_terminal) == ""
			and bool(same_spec.get("one_shot", false))
			and not bool(same_spec.get("triggered", true))
			and host.game_state.is_interactable_enabled(str(source.get("data_id")))
			and _drive_terminal(host, chunk, "term_beta"),
		"same-presenter restore rolls the uncommitted receipt back and permits one physical retry")

	var fresh_pair := await _boot()
	var fresh_source: Node = fresh_pair.chunk._terminal_interactables["term_beta"]
	_apply_capture(fresh_pair.host, fresh_pair.chunk, seam_capture)
	_apply_capture(fresh_pair.host, fresh_pair.chunk, seam_capture)
	var fresh_spec: Dictionary = fresh_pair.host.game_state.get_interactable(
		str(fresh_source.get("data_id"))
	)
	_check(str(fresh_pair.chunk.get_preview_state().active_terminal) == ""
			and bool(fresh_spec.get("one_shot", false))
			and not bool(fresh_spec.get("triggered", true))
			and fresh_pair.host.game_state.is_interactable_enabled(
				str(fresh_source.get("data_id")))
			and _drive_terminal(fresh_pair.host, fresh_pair.chunk, "term_beta"),
		"fresh presenter reconstructs an unused exact source instead of guessing the consequence")
	await _discard(host)
	await _discard(fresh_pair.host)


func _verify_root_hazard_cadence_authority() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var root_state: Dictionary = chunk._roots["north_rail"]
	var hazard_position: Vector3 = chunk._root_node(root_state).position
	host.game_state.snap_character_to("aster", hazard_position)
	host.game_state.snap_character_to("peris", Vector3(-100.0, 0.0, -100.0))
	host.game_state.snap_character_to("endo", Vector3(-104.0, 0.0, -100.0))
	var initial_record: Dictionary = host.game_state.get_world_state(
		chunk.mother_authority_key(), {})
	var first_tick := float(initial_record.get("hazard_next_tick", -1.0))
	var initial_hp: float = host.game_state.get_stat("aster", "hp")
	_check(int(initial_record.get("version", 0)) == chunk.MOTHER_AUTHORITY_VERSION
		and first_tick > host.scheduler.get_current_tick(),
		"Mother authority saves one future absolute root-hazard deadline")
	for _frame in range(480):
		chunk.headless_process(99.0)
	_check(is_equal_approx(host.game_state.get_stat("aster", "hp"), initial_hp)
		and is_equal_approx(float(chunk.get_preview_state().hazard_next_tick), first_tick),
		"presentation calls cannot sample root contact or advance its deadline")

	host.scheduler.advance_ticks(chunk.ROOT_HAZARD_INTERVAL - 0.001)
	_check(is_equal_approx(host.game_state.get_stat("aster", "hp"), initial_hp),
		"root contact cannot bite before the saved cadence deadline")
	var seam_box := {"capture": {}}
	var seam_listener := func(key: String, value: Variant) -> void:
		if key != chunk.mother_authority_key() or not value is Dictionary:
			return
		var record := value as Dictionary
		if host.game_state.get_stat("aster", "hp") == initial_hp - chunk.ROOT_HAZARD_DAMAGE \
				and float(record.get("hazard_next_tick", -1.0)) > first_tick:
			seam_box.capture = _capture(host)
	host.game_state.world_state_changed.connect(seam_listener)
	host.scheduler.advance_ticks(0.001)
	host.game_state.world_state_changed.disconnect(seam_listener)
	var second_tick := float(chunk.get_preview_state().hazard_next_tick)
	_check(is_equal_approx(host.game_state.get_stat("aster", "hp"),
		initial_hp - chunk.ROOT_HAZARD_DAMAGE)
		and is_equal_approx(second_tick, first_tick + chunk.ROOT_HAZARD_INTERVAL),
		"exact cadence tick applies one spatial bite and advances from its prior anchor")
	var seam_capture: Dictionary = seam_box.capture
	_check(not seam_capture.is_empty(),
		"post-bite publication seam captures HP and the next deadline together")

	host.scheduler.advance_ticks(0.35)
	var midpoint := _capture(host)
	var midpoint_tick := float(host.scheduler.get_current_tick())
	var midpoint_hp: float = host.game_state.get_stat("aster", "hp")
	var midpoint_deadline := float(chunk.get_preview_state().hazard_next_tick)
	host.scheduler.advance_ticks(chunk.ROOT_HAZARD_INTERVAL * 2.0)
	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	_check(is_equal_approx(host.game_state.get_stat("aster", "hp"), midpoint_hp)
		and is_equal_approx(float(chunk.get_preview_state().hazard_next_tick), midpoint_deadline),
		"same-presenter rollback restores root HP and exact cadence once")

	var fresh_pair := await _boot()
	_apply_capture(fresh_pair.host, fresh_pair.chunk, midpoint)
	_apply_capture(fresh_pair.host, fresh_pair.chunk, midpoint)
	_check(is_equal_approx(fresh_pair.host.game_state.get_stat("aster", "hp"), midpoint_hp)
		and is_equal_approx(float(fresh_pair.chunk.get_preview_state().hazard_next_tick),
			midpoint_deadline),
		"fresh presenter reconstructs the root contact body and deadline without a bite")
	var horizon: float = chunk.ROOT_HAZARD_INTERVAL * 3.0
	host.scheduler.advance_ticks(horizon)
	chunk.headless_process(5000.0)
	for _step in range(51):
		fresh_pair.host.scheduler.advance_ticks(horizon / 51.0)
		for _frame in range(9):
			fresh_pair.chunk.headless_process(0.0001)
	_check(is_equal_approx(host.game_state.get_stat("aster", "hp"),
		fresh_pair.host.game_state.get_stat("aster", "hp"))
		and is_equal_approx(float(chunk.get_preview_state().hazard_next_tick),
			float(fresh_pair.chunk.get_preview_state().hazard_next_tick)),
		"coarse and fine scheduler partitions produce identical root bites and next anchor")

	var seam_pair := await _boot()
	_apply_capture(seam_pair.host, seam_pair.chunk, seam_capture)
	var seam_hp: float = seam_pair.host.game_state.get_stat("aster", "hp")
	var seam_next := float(seam_pair.chunk.get_preview_state().hazard_next_tick)
	seam_pair.host.scheduler.advance_ticks(seam_next
		- float(seam_pair.host.scheduler.get_current_tick()) - 0.001)
	_check(is_equal_approx(seam_pair.host.game_state.get_stat("aster", "hp"), seam_hp),
		"fresh signal-seam restore cannot replay the bite before its next deadline")
	seam_pair.host.scheduler.advance_ticks(0.0011)
	_check(is_equal_approx(seam_pair.host.game_state.get_stat("aster", "hp"),
		seam_hp - chunk.ROOT_HAZARD_DAMAGE),
		"fresh signal-seam restore owns exactly one next root bite")

	var solved_pair := await _boot()
	var solved_host = solved_pair.host
	var solved_chunk = solved_pair.chunk
	_check(_prepare_mother_repair(solved_host, solved_chunk)
		and _drive_mother_tend(solved_host, solved_chunk),
		"Mother tending commits while the root cadence is armed")
	var solved_record: Dictionary = solved_host.game_state.get_world_state(
		solved_chunk.mother_authority_key(), {})
	solved_host.game_state.snap_character_to("aster",
		solved_chunk._root_node(solved_chunk._roots["north_rail"]).position)
	var tended_hp: float = solved_host.game_state.get_stat("aster", "hp")
	solved_host.scheduler.advance_ticks(solved_chunk.ROOT_HAZARD_INTERVAL * 6.0)
	_check(float(solved_record.get("hazard_next_tick", 0.0)) < 0.0
		and is_equal_approx(solved_host.game_state.get_stat("aster", "hp"), tended_hp),
		"tending Mother atomically retires the saved root cadence")

	_check(is_equal_approx(midpoint_tick, float(midpoint.get("scheduler", {}).get(
		"current_tick", -1.0))),
		"root midpoint fixture stores the authoritative scheduler tick")
	await _discard(host)
	await _discard(fresh_pair.host)
	await _discard(seam_pair.host)
	await _discard(solved_host)

func _verify_portal_transit_authority() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var origin: Vector3 = host.game_state.get_position("peris")
	var portal_commit_position: Vector3 = chunk._portal_entry_interactable.global_position

	_check(_drive_terminal(host, chunk, "term_gamma"),
		"Aster opens a physical portal route")
	var precommand_box := {"capture": {}}
	var precommand_listener := func(key: String, value: Variant) -> void:
		if key != chunk.mother_authority_key() or not value is Dictionary:
			return
		var record := value as Dictionary
		if str(record.get("portal_transit_phase", "")) == chunk.PORTAL_TRANSIT_OUTBOUND \
				and not host.game_state.is_external_traversal_active("peris"):
			precommand_box["capture"] = _capture(host)
	host.game_state.world_state_changed.connect(precommand_listener)
	_check(_drive_portal(host, chunk), "Peris commits the outbound crossing")
	host.game_state.world_state_changed.disconnect(precommand_listener)
	var state: Dictionary = chunk.get_preview_state()
	var transit: Dictionary = host.game_state.get_external_traversal_state("peris")
	_check(str(state.portal_transit_phase) == chunk.PORTAL_TRANSIT_OUTBOUND
		and str(state.portal_transit_terminal) == "term_gamma"
		and str(state.peris_remote_terminal) == ""
		and not transit.is_empty(),
		"crossing authority reserves the terminal without granting its endpoint")
	_check(not chunk._portal_entry_interactable.is_interaction_enabled()
		and not chunk._portal_return_interactable.is_interaction_enabled(),
		"both portal mouths refuse a second interaction while the body is in transit")
	_check(not _drive_root_control(host, chunk, "gear_latch", 1),
		"a reserved remote terminal cannot operate its root before Peris arrives")

	var precommand_capture: Dictionary = precommand_box.get("capture", {})
	_check(not precommand_capture.is_empty(),
		"the authority publication seam is observable before movement begins")
	var precommand_pair := await _boot()
	_apply_capture(precommand_pair.host, precommand_pair.chunk, precommand_capture)
	var precommand_state: Dictionary = precommand_pair.chunk.get_preview_state()
	var restored_precommand_position: Vector3 = precommand_pair.host.game_state.get_position(
		"peris"
	)
	_check(str(precommand_state.portal_transit_phase) == precommand_pair.chunk.PORTAL_TRANSIT_IDLE
		and str(precommand_state.peris_remote_terminal) == ""
		and not precommand_pair.host.game_state.is_external_traversal_active("peris")
		and Vector2(
			restored_precommand_position.x, restored_precommand_position.z
		).distance_to(Vector2(
			portal_commit_position.x, portal_commit_position.z
		)) <= 0.001,
		"fresh load at the pre-command seam rolls back the reservation and grants no crossing")

	host.scheduler.advance_ticks(chunk.PORTAL_TRANSIT_SECONDS * 0.5)
	chunk.headless_process(0.016)
	var midpoint_position: Vector3 = host.game_state.get_position("peris")
	var destination: Vector3 = chunk._terminal_service_spawn("term_gamma")
	_check(midpoint_position.distance_to(origin) > 0.1
		and midpoint_position.distance_to(destination) > 0.1
		and str(chunk.get_preview_state().peris_remote_terminal) == "",
		"scheduler time places Peris physically between mouths without remote ownership")
	host.game_state.snap_character_to("peris", destination + Vector3(20.0, 0.0, 0.0))
	_check(host.game_state.get_position("peris").distance_to(midpoint_position) <= 0.001,
		"ordinary snap authority cannot bypass a locked portal traversal")
	var midpoint := _capture(host)
	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	_check(host.game_state.is_external_traversal_active("peris")
		and str(chunk.get_preview_state().portal_transit_phase) == chunk.PORTAL_TRANSIT_OUTBOUND
		and host.game_state.get_position("peris").distance_to(midpoint_position) <= 0.001,
		"same-presenter idempotent restore reconstructs the exact outbound midpoint")

	var fresh_pair := await _boot()
	_apply_capture(fresh_pair.host, fresh_pair.chunk, midpoint)
	_apply_capture(fresh_pair.host, fresh_pair.chunk, midpoint)
	_check(fresh_pair.host.game_state.is_external_traversal_active("peris")
		and str(fresh_pair.chunk.get_preview_state().portal_transit_phase) \
			== fresh_pair.chunk.PORTAL_TRANSIT_OUTBOUND
		and fresh_pair.host.game_state.get_position("peris").distance_to(midpoint_position) <= 0.001,
		"fresh presenter reconstructs the body and endpoint reservation in transit")
	fresh_pair.host.scheduler.advance_ticks(chunk.PORTAL_TRANSIT_SECONDS * 0.5 - 0.001)
	_check(fresh_pair.host.game_state.is_external_traversal_active("peris")
		and str(fresh_pair.chunk.get_preview_state().peris_remote_terminal) == "",
		"fresh load cannot finish the outbound crossing before its saved remainder")

	# Capture the exact signal seam after GameState seats the body but before the chunk commits
	# terminal ownership. Restore must infer the completed endpoint rather than replay the crossing.
	var finish_box := {"capture": {}}
	fresh_pair.chunk._disconnect_mother_game_state_signals()
	var finish_listener := func(char_id: String, _traversal_id: StringName) -> void:
		if char_id == "peris":
			finish_box["capture"] = _capture(fresh_pair.host)
	fresh_pair.host.game_state.external_traversal_finished.connect(finish_listener)
	fresh_pair.chunk._ensure_mother_game_state_signals()
	fresh_pair.host.scheduler.advance_ticks(0.001)
	fresh_pair.host.game_state.external_traversal_finished.disconnect(finish_listener)
	_check(str(fresh_pair.chunk.get_preview_state().peris_remote_terminal) == "term_gamma"
		and str(fresh_pair.chunk.get_preview_state().portal_transit_phase) \
			== fresh_pair.chunk.PORTAL_TRANSIT_IDLE
		and not fresh_pair.host.game_state.is_external_traversal_active("peris"),
		"outbound arrival atomically seats Peris and commits remote ownership")
	var finish_capture: Dictionary = finish_box.get("capture", {})
	_check(not finish_capture.is_empty(),
		"the post-seat/pre-owner finish seam is captured")
	var finish_pair := await _boot()
	_apply_capture(finish_pair.host, finish_pair.chunk, finish_capture)
	var finish_state: Dictionary = finish_pair.chunk.get_preview_state()
	_check(str(finish_state.peris_remote_terminal) == "term_gamma"
		and str(finish_state.portal_transit_phase) == finish_pair.chunk.PORTAL_TRANSIT_IDLE
		and finish_pair.host.game_state.get_position("peris").distance_to(destination) <= 0.001,
		"fresh load at the finish seam commits the already-reached endpoint exactly once")

	_check(_drive_portal(finish_pair.host, finish_pair.chunk),
		"Peris commits the physical return crossing")
	finish_pair.host.scheduler.advance_ticks(chunk.PORTAL_TRANSIT_SECONDS * 0.5)
	finish_pair.chunk.headless_process(0.016)
	var return_midpoint: Vector3 = finish_pair.host.game_state.get_position("peris")
	var return_capture := _capture(finish_pair.host)
	var return_pair := await _boot()
	_apply_capture(return_pair.host, return_pair.chunk, return_capture)
	_check(str(return_pair.chunk.get_preview_state().portal_transit_phase) \
			== return_pair.chunk.PORTAL_TRANSIT_RETURNING
		and str(return_pair.chunk.get_preview_state().peris_remote_terminal) == "term_gamma"
		and return_pair.host.game_state.get_position("peris").distance_to(return_midpoint) <= 0.001,
		"fresh return restore keeps remote ownership until the body reaches the base")
	return_pair.host.scheduler.advance_ticks(chunk.PORTAL_TRANSIT_SECONDS * 0.5)
	var base_destination: Vector3 = chunk.BASE_PORTAL_POS + Vector3(2.6, 0.0, 0.0)
	_check(str(return_pair.chunk.get_preview_state().peris_remote_terminal) == ""
		and str(return_pair.chunk.get_preview_state().portal_transit_phase) \
			== return_pair.chunk.PORTAL_TRANSIT_IDLE
		and return_pair.host.game_state.get_position("peris").distance_to(base_destination) <= 0.001,
		"return ownership clears only when Peris physically reaches the base mouth")

	await _discard(host)
	await _discard(precommand_pair.host)
	await _discard(fresh_pair.host)
	await _discard(finish_pair.host)
	await _discard(return_pair.host)

func _verify_root_gate_timing_and_restore() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var settle_seconds: float = (
		chunk.ROOT_SLIDE_DURATION + chunk.ROOT_SWARM_LAG + chunk.ROOT_SWARM_DURATION
	)

	_check(_drive_terminal(host, chunk, "term_gamma"),
		"Aster opens the gear-latch service bank")
	_check(_drive_portal(host, chunk),
		"Peris starts the first physical service crossing")
	host.scheduler.advance_ticks(chunk.PORTAL_TRANSIT_SECONDS)
	chunk.headless_process(0.016)
	_check(_drive_root_control(host, chunk, "gear_latch", 1),
		"Peris starts the first physical pocket-opening slide after arriving")
	var gear_record: Dictionary = host.game_state.get_world_state(chunk.mother_authority_key(), {})
	var gear_root: Dictionary = (gear_record.get("roots", {}) as Dictionary).get("gear_latch", {})
	_check(int(gear_record.get("version", 0)) == chunk.MOTHER_AUTHORITY_VERSION
		and int(gear_root.get("anchor", -1)) == 0
		and int(gear_root.get("target_anchor", -1)) == 1,
		"root authority separates settled anchor 0 from reserved target 1")
	chunk._commit_root_move(
		"gear_latch", 1, float(gear_root.get("swarm_end", -1.0)))
	gear_record = host.game_state.get_world_state(chunk.mother_authority_key(), {})
	gear_root = (gear_record.get("roots", {}) as Dictionary).get("gear_latch", {})
	_check(int(gear_root.get("anchor", -1)) == 0
		and int(gear_root.get("target_anchor", -1)) == 1,
		"even a matching direct commit cannot settle a root before scheduler arrival")
	_check(not bool(chunk.get_preview_state().gear_pocket_open),
		"starting a root slide cannot grant its destination consequence")
	host.scheduler.advance_ticks(settle_seconds - 0.001)
	chunk.headless_process(0.016)
	gear_record = host.game_state.get_world_state(chunk.mother_authority_key(), {})
	gear_root = (gear_record.get("roots", {}) as Dictionary).get("gear_latch", {})
	_check(int(gear_root.get("anchor", -1)) == 0
		and int(gear_root.get("target_anchor", -1)) == 1,
		"settled root anchor cannot advance before the saved arrival deadline")
	host.scheduler.advance_ticks(0.001)
	chunk.headless_process(0.016)
	gear_record = host.game_state.get_world_state(chunk.mother_authority_key(), {})
	gear_root = (gear_record.get("roots", {}) as Dictionary).get("gear_latch", {})
	_check(int(gear_root.get("anchor", -1)) == 1
		and int(gear_root.get("target_anchor", -2)) == -1,
		"root arrival commits the settled anchor and clears its reservation exactly once")
	_check(_drive_portal(host, chunk),
		"Peris starts returning after the first root physically settles")
	host.scheduler.advance_ticks(chunk.PORTAL_TRANSIT_SECONDS)
	chunk.headless_process(0.016)
	_check(str(chunk.get_preview_state().peris_remote_terminal) == "",
		"Peris owns the base endpoint only after the return traversal finishes")

	_check(_drive_terminal(host, chunk, "term_beta"),
		"Aster opens the socket-brace service bank")
	_check(_drive_portal(host, chunk),
		"Peris starts the final physical service crossing")
	host.scheduler.advance_ticks(chunk.PORTAL_TRANSIT_SECONDS)
	chunk.headless_process(0.016)
	_check(_drive_root_control(host, chunk, "socket_brace", 1),
		"Peris starts the final physical pocket-opening slide after arriving")
	var socket_record: Dictionary = host.game_state.get_world_state(chunk.mother_authority_key(), {})
	var socket_root: Dictionary = (socket_record.get("roots", {}) as Dictionary).get("socket_brace", {})
	_check(int(socket_root.get("anchor", -1)) == 2
		and int(socket_root.get("target_anchor", -1)) == 3,
		"final slide preserves its settled socket anchor while reserving the destination")
	_check(not bool(chunk.get_preview_state().gear_pocket_open),
		"the gear pocket stays closed while its final root and Sapscrap mat are moving")

	host.scheduler.advance_ticks(settle_seconds * 0.5)
	chunk.headless_process(1000.0)
	var midpoint := _capture(host)
	_check(not bool(chunk.get_preview_state().gear_pocket_open),
		"discarded render time cannot finish the gameplay consequence early")

	var legacy_capture := midpoint.duplicate(true)
	var legacy_world: Dictionary = (legacy_capture.get("game_state", {}) as Dictionary).get(
		"world_state", {})
	var legacy_record: Dictionary = legacy_world.get(chunk.mother_authority_key(), {})
	legacy_record["version"] = 1
	for legacy_root_v in (legacy_record.get("roots", {}) as Dictionary).values():
		if not legacy_root_v is Dictionary:
			continue
		var legacy_root := legacy_root_v as Dictionary
		var reserved := int(legacy_root.get("target_anchor", -1))
		if reserved >= 0:
			legacy_root["anchor"] = reserved
		legacy_root.erase("target_anchor")
	var legacy_pair := await _boot()
	_apply_capture(legacy_pair.host, legacy_pair.chunk, legacy_capture)
	var migrated_record: Dictionary = legacy_pair.host.game_state.get_world_state(
		legacy_pair.chunk.mother_authority_key(), {})
	var migrated_root: Dictionary = (
		migrated_record.get("roots", {}) as Dictionary).get("socket_brace", {})
	_check(int(migrated_record.get("version", 0)) == legacy_pair.chunk.MOTHER_AUTHORITY_VERSION
		and int(migrated_root.get("anchor", -1)) == 2
		and int(migrated_root.get("target_anchor", -1)) == 3,
		"v1 in-flight roots migrate from overloaded anchor to settled plus reserved authority")

	var fresh_pair := await _boot()
	_apply_capture(fresh_pair.host, fresh_pair.chunk, midpoint)
	_apply_capture(fresh_pair.host, fresh_pair.chunk, midpoint)
	var restored_record: Dictionary = fresh_pair.host.game_state.get_world_state(
		fresh_pair.chunk.mother_authority_key(), {})
	var restored_root: Dictionary = (
		restored_record.get("roots", {}) as Dictionary).get("socket_brace", {})
	_check(int(restored_root.get("anchor", -1)) == 2
		and int(restored_root.get("target_anchor", -1)) == 3,
		"fresh restore preserves distinct settled and reserved root anchors")
	_check(not bool(fresh_pair.chunk.get_preview_state().gear_pocket_open),
		"fresh-presenter restore keeps the saved root transit causally incomplete")
	var remaining := settle_seconds * 0.5
	fresh_pair.host.scheduler.advance_ticks(remaining - 0.001)
	fresh_pair.chunk.headless_process(0.001)
	restored_record = fresh_pair.host.game_state.get_world_state(
		fresh_pair.chunk.mother_authority_key(), {})
	restored_root = (restored_record.get("roots", {}) as Dictionary).get("socket_brace", {})
	_check(int(restored_root.get("anchor", -1)) == 2
		and int(restored_root.get("target_anchor", -1)) == 3,
		"restored root remains unsettled immediately before its original deadline")
	_check(not bool(fresh_pair.chunk.get_preview_state().gear_pocket_open),
		"restored root transit cannot unlock the pocket before its original deadline")
	fresh_pair.host.scheduler.advance_ticks(0.001)
	fresh_pair.chunk.headless_process(0.001)
	restored_record = fresh_pair.host.game_state.get_world_state(
		fresh_pair.chunk.mother_authority_key(), {})
	restored_root = (restored_record.get("roots", {}) as Dictionary).get("socket_brace", {})
	_check(int(restored_root.get("anchor", -1)) == 3
		and int(restored_root.get("target_anchor", -2)) == -1,
		"restored arrival commits at the original saved deadline")
	_check(bool(fresh_pair.chunk.get_preview_state().gear_pocket_open),
		"the pocket unlocks when the saved root-and-mat process physically completes")

	await _discard(host)
	await _discard(legacy_pair.host)
	await _discard(fresh_pair.host)

func _verify_midpoint_same_fresh_and_absence() -> Dictionary:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var before := _capture(host)
	_check(_start_physical_commitments(host, chunk),
		"fixture starts debris shifting, mounts the gear, and begins the Rings opening")
	var committed := _capture(host)
	var record: Dictionary = host.game_state.get_world_state(chunk.mother_authority_key(), {})
	_check(str(record.get("collapse_phase", "")) == chunk.COLLAPSE_PHASE_SHIFTING
		and is_equal_approx(float(record.get("collapse_shift_deadline", -1.0)), chunk.COLLAPSE_SHIFT_SECONDS),
		"debris shift records a portable phase and absolute completion tick")
	_check(str(record.get("rings_gate_phase", "")) == chunk.RINGS_GATE_PHASE_OPENING
		and is_equal_approx(float(record.get("rings_gate_deadline", -1.0)), chunk.RINGS_GATE_OPEN_SECONDS),
		"Rings membrane records its opening phase and absolute completion tick")
	_check(chunk._installed_gear_root.visible and str(chunk.get_preview_state().gear_item) == "",
		"successful repair consumes the inventory item but leaves the gear visibly socketed")

	host.scheduler.advance_ticks(0.8)
	chunk.headless_process(0.016)
	var midpoint := _capture(host)
	var midpoint_debris: Vector3 = chunk._collapse_debris_root.position
	var midpoint_gate: Vector3 = chunk._exit_gate_root.position
	var state: Dictionary = chunk.get_preview_state()
	_check(float(state.collapse_shift_progress) > 0.33
		and float(state.collapse_shift_progress) < 0.34
		and float(state.rings_gate_progress) > 0.44
		and float(state.rings_gate_progress) < 0.45,
		"midpoint presents analytic debris and gate progress from scheduler time")
	_check(not chunk._collapse_collision_shape.disabled
		and not chunk._rings_gate_collision_shape.disabled,
		"both physical collision blockers remain authoritative during motion")

	host.scheduler.advance_ticks(1.0)
	chunk.headless_process(1000.0)
	_check(str(chunk.get_preview_state().rings_gate_phase) == chunk.RINGS_GATE_PHASE_OPEN
		and str(chunk.get_preview_state().collapse_phase) == chunk.COLLAPSE_PHASE_SHIFTING,
		"discarded future opens the shorter Rings commitment while debris still shifts")
	host.scheduler.advance_ticks(0.6)
	chunk.headless_process(0.001)
	_check(str(chunk.get_preview_state().collapse_phase) == chunk.COLLAPSE_PHASE_CLEARED
		and chunk._collapse_collision_shape.disabled
		and chunk._rings_gate_collision_shape.disabled,
		"discarded future releases both physical blockers only at their completion ticks")

	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	state = chunk.get_preview_state()
	_check(str(state.collapse_phase) == chunk.COLLAPSE_PHASE_SHIFTING
		and str(state.rings_gate_phase) == chunk.RINGS_GATE_PHASE_OPENING
		and chunk._collapse_debris_root.position.distance_to(midpoint_debris) < 0.0001
		and chunk._exit_gate_root.position.distance_to(midpoint_gate) < 0.0001,
		"same-presenter idempotent rollback restores both exact moving presenters")
	_check(not chunk._collapse_collision_shape.disabled
		and not chunk._rings_gate_collision_shape.disabled
		and chunk._installed_gear_root.visible,
		"same-presenter rollback restores blockers and socketed gear together")
	host.scheduler.advance_ticks(0.999)
	_check(str(chunk.get_preview_state().rings_gate_phase) == chunk.RINGS_GATE_PHASE_OPENING,
		"restored Rings gate cannot finish before its original deadline")
	host.scheduler.advance_ticks(0.0011)
	_check(str(chunk.get_preview_state().rings_gate_phase) == chunk.RINGS_GATE_PHASE_OPEN,
		"idempotent restore attaches exactly one Rings completion at the saved deadline")
	host.scheduler.advance_ticks(0.599)
	_check(str(chunk.get_preview_state().collapse_phase) == chunk.COLLAPSE_PHASE_SHIFTING,
		"restored collapse cannot clear before its original deadline")
	host.scheduler.advance_ticks(0.001)
	_check(str(chunk.get_preview_state().collapse_phase) == chunk.COLLAPSE_PHASE_CLEARED,
		"idempotent restore attaches exactly one debris completion at the saved deadline")

	var fresh_pair := await _boot()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, midpoint)
	var fresh_state: Dictionary = fresh.get_preview_state()
	_check(str(fresh_state.collapse_phase) == fresh.COLLAPSE_PHASE_SHIFTING
		and str(fresh_state.rings_gate_phase) == fresh.RINGS_GATE_PHASE_OPENING
		and fresh._collapse_debris_root.position.distance_to(midpoint_debris) < 0.0001
		and fresh._exit_gate_root.position.distance_to(midpoint_gate) < 0.0001,
		"fresh presenter reconstructs both saved midpoint transforms")
	_check(fresh._installed_gear_root.visible
		and str(fresh_state.installed_repair) == fresh.CORRECT_REPAIR_ID
		and fresh._is_mother_lane_clear(),
		"fresh presenter restores socketed gear and the dependent solved root board")
	fresh_host.scheduler.advance_ticks(1.6)
	fresh.headless_process(99.0)
	_check(str(fresh.get_preview_state().collapse_phase) == fresh.COLLAPSE_PHASE_CLEARED
		and str(fresh.get_preview_state().rings_gate_phase) == fresh.RINGS_GATE_PHASE_OPEN,
		"fresh presenter consumes only each saved remainder")

	var absent := before.duplicate(true)
	var absent_world: Dictionary = absent.get("game_state", {}).get("world_state", {})
	absent_world.erase(chunk.mother_authority_key())
	_apply_capture(host, chunk, absent)
	state = chunk.get_preview_state()
	var loose_gear: Dictionary = host.game_state.items.get(str(state.gear_item), {})
	_check(str(state.collapse_phase) == chunk.COLLAPSE_PHASE_BLOCKED
		and str(state.rings_gate_phase) == chunk.RINGS_GATE_PHASE_SEALED
		and str(state.route_phase) == "investigate",
		"missing authority retracts the discarded open future to construction truth")
	_check(not chunk._collapse_collision_shape.disabled
		and not chunk._rings_gate_collision_shape.disabled
		and not chunk._installed_gear_root.visible
		and str(loose_gear.get("type", "")) == "mother_gear",
		"absence rollback restores both blockers and the loose physical gear")
	var initial_latch := int(chunk._roots.gear_latch.initial_anchor)
	_check(int(chunk._roots.gear_latch.anchor) == initial_latch,
		"absence rollback retracts the dependent root-board solution too")
	host.scheduler.advance_ticks(20.0)
	_check(str(chunk.get_preview_state().collapse_phase) == chunk.COLLAPSE_PHASE_BLOCKED
		and str(chunk.get_preview_state().rings_gate_phase) == chunk.RINGS_GATE_PHASE_SEALED,
		"absence rollback leaves no orphan completion callbacks")

	await _discard(host)
	await _discard(fresh_host)
	return {"committed": committed}

func _verify_frame_invariance(committed: Dictionary) -> void:
	var coarse_pair := await _boot()
	var fine_pair := await _boot()
	_apply_capture(coarse_pair.host, coarse_pair.chunk, committed)
	_apply_capture(fine_pair.host, fine_pair.chunk, committed)
	coarse_pair.host.scheduler.advance_ticks(0.9)
	coarse_pair.chunk.headless_process(5000.0)
	for _step in range(9):
		fine_pair.host.scheduler.advance_ticks(0.1)
		for _frame in range(7):
			fine_pair.chunk.headless_process(0.001)
	_check(coarse_pair.chunk._collapse_debris_root.position.distance_to(
		fine_pair.chunk._collapse_debris_root.position) < 0.0001
		and coarse_pair.chunk._exit_gate_root.position.distance_to(
			fine_pair.chunk._exit_gate_root.position) < 0.0001,
		"presenter motion is invariant to scheduler and render-frame partitioning")
	var coarse_state: Dictionary = coarse_pair.chunk.get_preview_state()
	var fine_state: Dictionary = fine_pair.chunk.get_preview_state()
	_check(str(coarse_state.collapse_phase) == str(fine_state.collapse_phase)
		and str(coarse_state.rings_gate_phase) == str(fine_state.rings_gate_phase),
		"render delta cannot commit either gameplay phase")
	coarse_pair.host.scheduler.advance_ticks(1.5)
	for _step in range(15):
		fine_pair.host.scheduler.advance_ticks(0.1)
	_check(str(coarse_pair.chunk.get_preview_state().collapse_phase) == coarse_pair.chunk.COLLAPSE_PHASE_CLEARED
		and str(fine_pair.chunk.get_preview_state().collapse_phase) == fine_pair.chunk.COLLAPSE_PHASE_CLEARED,
		"coarse and fine simulation partitions converge on the same completed authority")
	await _discard(coarse_pair.host)
	await _discard(fine_pair.host)

func _verify_collapse_topology() -> void:
	var grid := GridWorld.new()
	grid.origin = Vector3(0.0, 0.0, 13.0)
	grid.cell_size = 1.0
	grid.create_room(90, 11, true)
	var pair := await _boot(grid)
	var host = pair.host
	var chunk = pair.chunk
	var start := grid.world_to_grid(Vector3(40.0, 0.0, 18.0))
	var finish := grid.world_to_grid(Vector3(50.0, 0.0, 18.0))
	_check(grid.find_path(start, finish).is_empty()
		and not chunk._collapse_collision_shape.disabled,
		"blocked collapse has both an impassable route graph and physical collision")
	_check(_drive_collapse(host, chunk),
		"Endo starts the topology-backed debris shift")
	host.game_state.snap_character_to("endo", chunk.BODY_POSITIONS.body_a)
	_check(not _drive_body_harvest(host, chunk, "body_a"),
		"a moving debris presenter cannot be bypassed to harvest the blocked side")
	host.scheduler.advance_ticks(chunk.COLLAPSE_SHIFT_SECONDS - 0.001)
	_check(grid.find_path(start, finish).is_empty(),
		"collapse topology stays closed through the entire shifting phase")
	host.scheduler.advance_ticks(0.001)
	_check(not grid.find_path(start, finish).is_empty()
		and chunk._collapse_collision_shape.disabled,
		"debris completion removes the actual topology and collision blocker together")
	_check(_drive_body_harvest(host, chunk, "body_a"),
		"the same harvest becomes valid only after physical route completion")
	await _discard(host)

func _verify_rings_gate_topology() -> void:
	var grid := GridWorld.new()
	grid.origin = Vector3(110.0, 0.0, -30.0)
	grid.cell_size = 1.0
	grid.create_room(5, 18, true)
	var pair := await _boot(grid)
	var host = pair.host
	var chunk = pair.chunk
	var start := grid.world_to_grid(Vector3(112.0, 0.0, -24.0))
	var finish := grid.world_to_grid(Vector3(112.0, 0.0, -20.0))
	_check(grid.find_path(start, finish).is_empty()
		and not chunk._rings_gate_collision_shape.disabled,
		"sealed Rings membrane owns both route topology and physical collision")
	_check(_prepare_mother_repair(host, chunk) and _drive_mother_tend(host, chunk),
		"solved Mother starts the topology-backed Rings opening")
	host.game_state.snap_character_to("peris", chunk.EXIT_POS)
	_check(not _drive_exit_handoff(host, chunk, "peris"),
		"standing at the destination cannot bypass the in-flight Rings membrane")
	host.scheduler.advance_ticks(chunk.RINGS_GATE_OPEN_SECONDS - 0.001)
	_check(grid.find_path(start, finish).is_empty()
		and not chunk._rings_gate_collision_shape.disabled,
		"Rings topology remains sealed until the opening reaches its saved deadline")
	host.scheduler.advance_ticks(0.001)
	_check(not grid.find_path(start, finish).is_empty()
		and chunk._rings_gate_collision_shape.disabled
		and chunk._exit_interactable.is_interaction_enabled(),
		"Rings completion opens pathfinding, collision, and the exit interaction together")
	await _discard(host)


func _verify_full_party_exit_authority() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	_check(_prepare_mother_repair(host, chunk) and _drive_mother_tend(host, chunk),
		"solved Mother begins its saved Rings opening for the party-arrival fixture")
	host.scheduler.advance_ticks(chunk.RINGS_GATE_OPEN_SECONDS)
	chunk.headless_process(0.001)
	_check(str(chunk.get_preview_state().route_phase) == "handoff",
		"the party-arrival fixture starts only after the physical Rings membrane is open")
	var handoff := _capture(host)

	host.game_state.snap_character_to("peris", chunk.EXIT_POS)
	_check(not _drive_exit_handoff(host, chunk, "peris")
		and str(chunk.get_preview_state().route_phase) == "handoff"
		and not bool(chunk.get_preview_state().exit_reached),
		"one runner at the Rings pad cannot complete for two bodies left in the chamber")
	var one_runner_arrival: Dictionary = chunk.get_preview_state().exit_party_arrival
	_check((one_runner_arrival.get("distant", []) as Array).has("aster")
		and (one_runner_arrival.get("distant", []) as Array).has("endo"),
		"one-runner rejection identifies the canonical party members who still need to gather")

	_apply_capture(host, chunk, handoff)
	_gather_party_at_exit(host, chunk)
	host.game_state.characters.erase("endo")
	var missing_result: bool = _drive_exit_handoff(host, chunk, "aster")
	var missing_arrival: Dictionary = chunk.get_preview_state().exit_party_arrival
	_check(not missing_result
		and (missing_arrival.get("missing", []) as Array).has("endo")
		and str(chunk.get_preview_state().route_phase) == "handoff",
		"an absent canonical member cannot be replaced by the two bodies on the pad")

	_apply_capture(host, chunk, handoff)
	_gather_party_at_exit(host, chunk)
	host.game_state.set_stat("endo", "hp", 0.0, "mother_exit_authority_fixture")
	var downed_result: bool = _drive_exit_handoff(host, chunk, "aster")
	var downed_arrival: Dictionary = chunk.get_preview_state().exit_party_arrival
	_check(not downed_result
		and (downed_arrival.get("downed", []) as Array).has("endo")
		and str(chunk.get_preview_state().route_phase) == "handoff",
		"a downed member physically on the pad cannot satisfy a conscious-party handoff")

	_apply_capture(host, chunk, handoff)
	_gather_party_at_exit(host, chunk)
	_check(bool(chunk.get_preview_state().exit_party_ready)
		and _drive_exit_handoff(host, chunk, "aster"),
		"all three conscious canonical bodies on the pad complete regardless of active portrait")
	var completed := _capture(host)
	var completed_record: Dictionary = host.game_state.get_world_state(
		chunk.mother_authority_key(), {})
	var completed_json := JSON.stringify(completed_record)
	_check(str(completed_record.get("route_phase", "")) == "complete"
		and bool(completed_record.get("exit_reached", false))
		and not chunk._exit_interactable.is_interaction_enabled(),
		"full-party arrival commits the portable completed state and consumes the handoff once")
	_check(not chunk.complete_exit_handoff()
		and JSON.stringify(host.game_state.get_world_state(
			chunk.mother_authority_key(), {})) == completed_json,
		"retired direct handoff verb cannot repeat or alter an already-complete receipt")

	_apply_capture(host, chunk, completed)
	_apply_capture(host, chunk, completed)
	_check(bool(chunk.get_preview_state().complete)
		and bool(chunk.get_preview_state().exit_party_ready)
		and chunk._rings_gate_collision_shape.disabled
		and not chunk._exit_interactable.is_interaction_enabled(),
		"same-presenter idempotent restore keeps the completed party handoff physically open")

	var fresh_pair := await _boot()
	_apply_capture(fresh_pair.host, fresh_pair.chunk, completed)
	_apply_capture(fresh_pair.host, fresh_pair.chunk, completed)
	_check(bool(fresh_pair.chunk.get_preview_state().complete)
		and bool(fresh_pair.chunk.get_preview_state().exit_party_ready)
		and fresh_pair.chunk._rings_gate_collision_shape.disabled
		and not fresh_pair.chunk._exit_interactable.is_interaction_enabled(),
		"fresh presenter reconstructs the completed full-party handoff without replaying it")

	var absent := completed.duplicate(true)
	var absent_world: Dictionary = absent.get("game_state", {}).get("world_state", {})
	absent_world.erase(chunk.mother_authority_key())
	_apply_capture(host, chunk, absent)
	_check(str(chunk.get_preview_state().route_phase) == "investigate"
		and not bool(chunk.get_preview_state().complete)
		and not chunk._rings_gate_collision_shape.disabled
		and not _drive_exit_handoff(host, chunk, "aster"),
		"missing Mother authority retracts a discarded completed future even with the party at its pad")
	host.scheduler.advance_ticks(20.0)
	_check(not bool(chunk.get_preview_state().complete),
		"absence rollback leaves no orphan exit completion callback")

	await _discard(host)
	await _discard(fresh_pair.host)


func _gather_party_at_exit(host, chunk) -> void:
	var offsets := [-0.8, 0.0, 0.8]
	for index in range(chunk.CANONICAL_PARTY.size()):
		var char_id := str(chunk.CANONICAL_PARTY[index])
		host.game_state.snap_character_to(
			char_id,
			chunk.EXIT_POS + Vector3(float(offsets[index]), 0.0, 0.0)
		)

func _start_physical_commitments(host, chunk) -> bool:
	if not _drive_collapse(host, chunk):
		return false
	return _prepare_mother_repair(host, chunk) and _drive_mother_tend(host, chunk)

func _prepare_mother_repair(host, chunk) -> bool:
	_set_solved_roots(chunk)
	var picked := _drive_gear_pickup(host, chunk)
	var installed := _drive_gear_install(
		host, chunk, chunk.CORRECT_REPAIR_ID
	) if picked else false
	if not picked or not installed:
		return false
	host.active_character = "peris"
	return true

func _set_solved_roots(chunk) -> void:
	for move_v in chunk.CLEAN_ROOT_MOVES:
		var move: Dictionary = move_v
		var root_id := str(move.get("root", ""))
		var root_state: Dictionary = chunk._roots[root_id]
		root_state["anchor"] = int(root_state.get("anchor", 0)) + int(move.get("direction", 0))
	for root_id in chunk.ROOT_ORDER:
		var root_state: Dictionary = chunk._roots[root_id]
		var root_pos: Vector3 = chunk._root_world_center(root_state, int(root_state.anchor))
		chunk._apply_root_pose(
			root_id,
			root_pos,
			root_pos + Vector3(0.0, chunk.ROOT_SWARM_Y_OFFSET, 0.0)
		)
	chunk._update_extension_interactable_states()


func _drive_source(host, source: Node, actor: String) -> bool:
	if not is_instance_valid(source):
		return false
	host.active_character = actor
	host.game_state.snap_character_to(actor, (source as Node3D).global_position)
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _drive_terminal(host, chunk, terminal_id: String) -> bool:
	return _drive_source(
		host, chunk._terminal_interactables.get(terminal_id), "aster"
	)


func _drive_portal(host, chunk) -> bool:
	var source: Node = (
		chunk._portal_entry_interactable
		if str(chunk.get_preview_state().peris_remote_terminal) == ""
		else chunk._portal_return_interactable
	)
	return _drive_source(host, source, "peris")


func _drive_root_control(
	host, chunk, root_id: String, direction: int
) -> bool:
	return _drive_source(
		host,
		chunk._root_control_interactables.get(
			chunk._root_control_key(root_id, direction)
		),
		"peris"
	)


func _drive_collapse(host, chunk) -> bool:
	return _drive_source(host, chunk._collapse_interactable, "endo")


func _drive_body_harvest(host, chunk, body_id: String) -> bool:
	return _drive_source(host, chunk._body_interactables.get(body_id), "endo")


func _drive_gear_pickup(host, chunk) -> bool:
	return _drive_source(host, chunk._gear_interactable, "endo")


func _drive_gear_install(host, chunk, repair_id: String) -> bool:
	return _drive_source(
		host, chunk._repair_interactables.get(repair_id), "endo"
	)


func _drive_mother_tend(host, chunk) -> bool:
	return _drive_source(host, chunk._mother_interactable, "peris")


func _drive_exit_handoff(host, chunk, actor: String) -> bool:
	return _drive_source(host, chunk._exit_interactable, actor)


func _boot(grid = null) -> Dictionary:
	var host = HostScript.new()
	host.setup(false)
	if grid != null:
		host.grid = grid
		host.game_state.grid = grid
	var chunk = MotherScript.new()
	host.register_party(chunk.get_spawn_positions())
	for char_id in ["aster", "peris", "endo"]:
		host.game_state.set_stat(char_id, "hp", 100.0)
		host.game_state.set_stat(char_id, "stamina", 100.0)
		host.game_state.set_stat(char_id, "atp", 8.0)
	root.add_child(host)
	chunk.attach_chunk_host(host, FIXTURE_ID)
	host.add_child(chunk)
	await process_frame
	await process_frame
	chunk.reset_preview_state()
	chunk.on_game_state_grid_ready()
	await process_frame
	return {"host": host, "chunk": chunk}

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
		if "scheduler" in node and node.scheduler != null:
			node.scheduler.clear()
		node.queue_free()
	await process_frame
	await process_frame

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
