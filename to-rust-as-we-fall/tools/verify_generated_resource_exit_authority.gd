extends SceneTree

## Adversarial save/restore regression for generated-stretch one-shot resources,
## exact EXIT shelter completion, physical payload delivery, and bridge seating.
## Every snapshot is JSON round-tripped and restored into a newly built presenter.

const CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const TEACHING_SPEC := (
	"res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"
)
const HARD_CARRY_SPEC := "res://data/generated_stretches/generated_sample_hard_carry_run.json"
const CARGO_PHASE_KEY := "generated_hydraulic_bridge_cargo_phase"
const CARGO_MILESTONE_KEY := "generated_hydraulic_bridge_cargo_milestone"


class AuthorityHost:
	extends ChunkHostStub

	func set_preview_character_position(char_id: String, position: Vector3) -> void:
		if game_state != null and game_state.grid != null:
			game_state.set_character_level(
				char_id, game_state.grid.level_for_y(position.y)
			)
		super.set_preview_character_position(char_id, position)

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)


var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_generated_resource_transaction()
	await _verify_physical_cache_transaction()
	await _verify_spillway_source_transaction()
	if not OS.get_cmdline_user_args().has("--resource-sources-only"):
		await _verify_exact_exit_and_atomic_rest()
		await _verify_committed_payload_delivery()
		await _verify_bridge_seated_publication()
	print(
		"GENERATED RESOURCE/EXIT AUTHORITY: %d checks, %d failures"
		% [_checks, _failures]
	)
	quit(0 if _failures == 0 else 1)


func _verify_generated_resource_transaction() -> void:
	print("\n--- exact generated resource transaction ---")
	var pair := await _boot_pair(TEACHING_SPEC)
	var host: AuthorityHost = pair.host
	var chunk: Node = pair.chunk
	var runtime_key := str(chunk.call("_generated_runtime_authority_key"))
	var source_id := "node:node_02"
	var captures := {}
	var node: Dictionary = chunk.call("_find_node", "node_02")
	var source := _node_source(pair, "node_02")
	var source_position := _source_position(pair, source)
	var initial_claim := _claim(pair, source_id)
	var initial_item_id := str(initial_claim.get("item_id", ""))

	check(
		not node.is_empty() and source != null and source_position != Vector3.INF,
		"teaching node_02 exposes one exact bound physical source"
	)
	_assert_claim_available(pair, source_id, "untouched generated source")
	check(
		initial_item_id != ""
		and _count_items_for_source(host.game_state, source_id) == 1,
		"generated source begins with one exact materialized item"
	)
	var untouched_position: Vector3 = host.game_state.get_position("aster")
	check(
		not bool(chunk.call("_secure_generated_resource", node, "aster"))
		and (chunk.call("_finish_resource_claim", source_id) as Dictionary).is_empty()
		and (chunk.call("_resume_resource_claim", source_id) as Dictionary).is_empty()
		and host.game_state.get_position("aster").is_equal_approx(untouched_position)
		and _claim(pair, source_id).get("item_id", "") == initial_item_id,
		"direct claim helpers are inert and cannot move a body or reserve a reward"
	)
	check(
		_trigger_control(pair, "_hydraulic_first_control"),
		"the exact First Sluice cause makes the downstream generated source ready"
	)

	# Render-space proximity is not simulation-space proximity. This is the exact
	# regression for the retired normalize-and-snap interaction hack.
	var rendered_source := source_position
	if host.game_state.coord_map != null \
			and host.game_state.coord_map.has_method("to_world"):
		rendered_source = host.game_state.coord_map.call("to_world", source_position)
	if Vector2(rendered_source.x - source_position.x, rendered_source.z - source_position.z).length() \
			<= float(source.get("interaction_radius")) + 0.25:
		rendered_source = source_position + Vector3(12.0, 0.0, 12.0)
	host.set_preview_character_position("aster", rendered_source)
	var rendered_body_position: Vector3 = host.game_state.get_position("aster")
	source.set("active_character", "aster")
	check(
		not bool(source.call("_trigger", false))
		and host.game_state.get_position("aster").is_equal_approx(rendered_body_position)
		and _claim(pair, source_id).get("item_id", "") == initial_item_id,
		"render-frame proximity cannot teleport the servicing body into source range"
	)

	host.set_preview_character_position("aster", source_position + Vector3(12.0, 0.0, 0.0))
	source.set("active_character", "aster")
	check(
		not bool(source.call("_trigger", false))
		and _claim(pair, source_id).get("item_id", "") == initial_item_id,
		"a distant body cannot consume the exact generated source"
	)

	host.set_preview_character_position("aster", source_position)
	host.set_preview_character_position("peris", source_position + Vector3(12.0, 0.0, 0.0))
	source.set("active_character", "peris")
	check(
		not bool(source.call("_trigger", false))
		and _claim(pair, source_id).get("item_id", "") == initial_item_id,
		"selected/declared Peris cannot substitute for the nearby Aster body"
	)

	host.game_state.down_character("aster")
	source.set("active_character", "aster")
	check(
		not bool(source.call("_trigger", false)),
		"an unconscious body cannot service the generated source"
	)
	host.game_state.restore_character("aster")
	host.set_preview_character_position("aster", source_position)

	check(
		host.game_state.command_external_traversal(
			"aster",
			&"generated_resource_busy_probe",
			source_position + Vector3(0.5, 0.0, 0.0),
			source_position,
			source_position + Vector3(0.5, 0.0, 0.0),
			4.0
		),
		"busy-state probe commits a real locked traversal"
	)
	source.set("active_character", "aster")
	check(
		not bool(source.call("_trigger", false)),
		"an action-locked body cannot service the generated source"
	)
	host.game_state.cancel_external_traversal("aster", &"authority_probe_complete")
	host.set_preview_character_position("aster", source_position)

	# The servicing actor is exact. Filling Aster's hands may not silently hand the
	# source item to another free party member.
	var filler_ids: Array[String] = []
	for index in range(2):
		var filler_id: String = host.game_state.spawn_item(
			"generated_tool",
			source_position,
			{"display_name": "Verifier filler %d" % index}
		)
		filler_ids.append(filler_id)
		check(
			host.game_state.pick_up_item("aster", filler_id),
			"Aster can hold verifier filler %d" % index
		)
	check(
		not bool(source.call("_trigger", false))
		and _claim(pair, source_id).get("item_id", "") == initial_item_id
		and _count_items_for_source(host.game_state, source_id) == 1
		and not (host.game_state.get_hand_items("peris") as Array).has(initial_item_id),
		"full interacting actor leaves exact source untouched; no alternate carrier is substituted"
	)
	for filler_id in filler_ids:
		host.game_state.remove_item(filler_id)

	host.game_state.interactable_triggered.connect(
		func(interactable_id: String, _actor: String) -> void:
			if interactable_id == str(source.get("data_id")) \
					and not captures.has("accepted"):
				captures["accepted"] = _capture(pair)
	)
	host.game_state.world_state_changed.connect(
		func(key: String, _value: Variant) -> void:
			if key != runtime_key:
				return
			var claim := _claim(pair, source_id)
			if str(claim.get("phase", "")) != "claiming":
				return
			if not captures.has("committed"):
				captures["committed"] = _capture(pair)
	)
	host.game_state.item_picked_up.connect(
		func(_character_id: String, item_id: String) -> void:
			var properties := _item_properties(host.game_state, item_id)
			if str(properties.get("generated_resource_source_id", "")) == source_id \
					and not captures.has("pickup_signal"):
				captures["pickup_signal"] = _capture(pair)
	)

	# Emitting the presentation signal directly cannot manufacture GameState's
	# accepted one-shot receipt.
	source.emit_signal("interacted")
	check(
		str(_claim(pair, source_id).get("phase", "")) == "available"
		and _count_items_for_source(host.game_state, source_id) == 1,
		"direct interacted signal emission cannot manufacture a generated reward"
	)

	var stale_source := _node_source(pair, "node_01")
	check(
		stale_source == null
		or not bool(chunk.call(
			"_secure_generated_resource_from_receipt",
			node,
			"aster",
			stale_source
		)),
		"a different generated Interactable cannot impersonate node_02's source"
	)

	host.set_preview_active_character("peris")
	source.set("active_character", "aster")
	check(
		bool(source.call("_trigger", false)),
		"nearby Aster services the source even while Peris is the selected portrait"
	)
	check(
		captures.has("accepted")
		and captures.has("committed")
		and captures.has("pickup_signal"),
		"claim exposes accepted-source, durable CLAIMING, and pickup-signal boundaries"
	)
	_assert_claim_whole(pair, source_id, "node_02", "completed source")
	chunk.call("_return_resource_claim_to_available", source_id)
	_assert_claim_whole(
		pair, source_id, "node_02", "completed source resists direct reopening"
	)

	# Accepted-source and CLAIMING snapshots both precede pickup. Restore must
	# reveal the same untouched source and require a fresh exact interaction.
	for same_stage in ["accepted", "committed"]:
		if not captures.has(same_stage):
			continue
		_apply_snapshot(pair, captures[same_stage])
		_assert_claim_available(pair, source_id, "same-instance %s restore" % same_stage)
		check(
			str(_claim(pair, source_id).get("item_id", "")) == initial_item_id,
			"same-instance %s restore preserves exact item identity" % same_stage
		)
		var restored_source := _node_source(pair, "node_02")
		host.set_preview_character_position("aster", _source_position(pair, restored_source))
		restored_source.set("active_character", "aster")
		check(
			bool(restored_source.call("_trigger", false)),
			"same-instance %s restore re-arms only the exact physical source" % same_stage
		)
		_assert_claim_whole(
			pair, source_id, "node_02", "same-instance retried %s source" % same_stage
		)

	for stage in ["accepted", "committed", "pickup_signal"]:
		if not captures.has(stage):
			continue
		var fresh := await _boot_pair(TEACHING_SPEC)
		_apply_snapshot(fresh, captures[stage])
		if stage in ["accepted", "committed"]:
			_assert_claim_available(fresh, source_id, "fresh commitment restore")
			var fresh_source := _node_source(fresh, "node_02")
			fresh.host.set_preview_character_position(
				"aster", _source_position(fresh, fresh_source)
			)
			fresh_source.set("active_character", "aster")
			check(
				bool(fresh_source.call("_trigger", false)),
				"fresh %s restore requires and accepts an exact-source retry" % stage
			)
		else:
			_assert_claim_whole(fresh, source_id, "node_02", "fresh pickup restore")
		var before_count := _count_items_for_source(fresh.host.game_state, source_id)
		var spent_source := _node_source(fresh, "node_02")
		spent_source.set("active_character", "aster")
		check(
			not bool(spent_source.call("_trigger", false))
			and _count_items_for_source(fresh.host.game_state, source_id) == before_count,
			"fresh %s restore rejects duplicate activation without minting another item" % stage
		)
		await _free_pair(fresh)

	if captures.has("committed"):
		var injected := (captures.committed as Dictionary).duplicate(true)
		_inject_claim_item_holder(injected, initial_item_id, "aster", "peris")
		var adversarial := await _boot_pair(TEACHING_SPEC)
		_apply_snapshot(adversarial, injected)
		var injected_claim := _claim(adversarial, source_id)
		check(
			str(injected_claim.get("phase", "")) == "claiming"
			and str(injected_claim.get("recipient", "")) == "aster"
			and not (_runtime_record(adversarial).get("completed_nodes", []) as Array).has("node_02")
			and str((adversarial.host.game_state.items[initial_item_id] as Dictionary).get(
				"holder", ""
			)) == "peris",
			"different-holder injection cannot retarget or complete the reserved actor's claim"
		)
		check(
			_count_items_for_source(adversarial.host.game_state, source_id) == 1,
			"different-holder injection still owns one exact physical identity"
		)
		await _free_pair(adversarial)
	await _free_pair(pair)


func _verify_physical_cache_transaction() -> void:
	print("\n--- exact branch-cache lysate transaction ---")
	var pair := await _boot_pair(TEACHING_SPEC)
	var host: AuthorityHost = pair.host
	var chunk: Node = pair.chunk
	var caches: Array = chunk.get("_branch_caches")
	var cache := caches[0] as Dictionary if not caches.is_empty() else {}
	var index := int(cache.get("index", -1))
	var source_id := str(cache.get("resource_source_id", ""))
	var source: Node = cache.get("interactable", null)
	var source_position := _source_position(pair, source)
	var initial_item_id := str(_claim(pair, source_id).get("item_id", ""))
	check(
		not cache.is_empty()
		and index >= 0
		and source_id != ""
		and source != null
		and source_position != Vector3.INF,
		"generated detour exposes one exact bound branch-cache source"
	)
	_assert_claim_available(pair, source_id, "untouched physical-cache source")

	check(
		not bool(chunk.call("_collect_branch_reward", index))
		and (chunk.call(
			"_try_collect_physical_lysate",
			cache,
			{},
			"aster"
		) as Dictionary).is_empty()
		and str(_claim(pair, source_id).get("item_id", "")) == initial_item_id,
		"retired cache helpers cannot forge a reward from actor/index injection"
	)

	source.emit_signal("interacted")
	check(
		str(_claim(pair, source_id).get("phase", "")) == "available"
		and _count_items_for_source(host.game_state, source_id) == 1,
		"direct branch-cache signal emission cannot manufacture a receipt"
	)

	var stale_source := _node_source(pair, "node_01")
	chunk.call("_on_branch_cache_interacted", index, stale_source)
	check(
		str(_claim(pair, source_id).get("phase", "")) == "available",
		"a stale/different Interactable cannot impersonate the branch cache"
	)

	host.set_preview_character_position("aster", source_position + Vector3(10.0, 0.0, 0.0))
	source.set("active_character", "aster")
	check(
		not bool(source.call("_trigger", false)),
		"a distant body cannot take branch lysate"
	)
	host.set_preview_character_position("aster", source_position)
	host.set_preview_character_position("peris", source_position + Vector3(10.0, 0.0, 0.0))
	source.set("active_character", "peris")
	check(
		not bool(source.call("_trigger", false)),
		"a selected/declared remote body cannot borrow a nearby party member's proximity"
	)

	var filler_ids: Array[String] = []
	for filler_index in range(2):
		var filler_id: String = host.game_state.spawn_item(
			"generated_tool",
			source_position,
			{"display_name": "Branch verifier filler %d" % filler_index}
		)
		filler_ids.append(filler_id)
		check(
			host.game_state.pick_up_item("aster", filler_id),
			"Aster fills branch-cache hand slot %d" % filler_index
		)
	source.set("active_character", "aster")
	check(
		not bool(source.call("_trigger", false))
		and str(_claim(pair, source_id).get("phase", "")) == "available",
		"full hands leave the exact branch source available and unreserved"
	)
	for filler_id in filler_ids:
		host.game_state.remove_item(filler_id)

	var captures := {}
	var runtime_key := str(chunk.call("_generated_runtime_authority_key"))
	host.game_state.interactable_triggered.connect(
		func(interactable_id: String, _actor: String) -> void:
			if interactable_id == str(source.get("data_id")) \
					and not captures.has("accepted"):
				captures["accepted"] = _capture(pair)
	)
	host.game_state.world_state_changed.connect(
		func(key: String, _value: Variant) -> void:
			if key == runtime_key \
					and str(_claim(pair, source_id).get("phase", "")) == "claiming" \
					and not captures.has("committed"):
				captures["committed"] = _capture(pair)
	)
	host.game_state.item_picked_up.connect(
		func(_character_id: String, item_id: String) -> void:
			var pickup_properties := _item_properties(host.game_state, item_id)
			if str(pickup_properties.get("generated_resource_source_id", "")) == source_id \
					and not captures.has("pickup"):
				captures["pickup"] = _capture(pair)
	)

	host.set_preview_active_character("peris")
	host.set_preview_character_position("aster", source_position)
	source.set("active_character", "aster")
	check(
		bool(source.call("_trigger", false)),
		"nearby Aster takes branch lysate even while Peris is the selected portrait"
	)
	check(
		captures.has("accepted")
		and captures.has("committed")
		and captures.has("pickup"),
		"branch claim exposes accepted-source, CLAIMING, and pickup boundaries"
	)
	_assert_claim_whole(pair, source_id, "", "physical-cache source")

	for stage in ["accepted", "committed"]:
		if not captures.has(stage):
			continue
		_apply_snapshot(pair, captures[stage])
		_assert_claim_available(pair, source_id, "same branch %s restore" % stage)
		var restored_cache := _branch_cache(pair, index)
		var restored_source: Node = restored_cache.get("interactable", null)
		host.set_preview_character_position("aster", _source_position(pair, restored_source))
		restored_source.set("active_character", "aster")
		check(
			bool(restored_source.call("_trigger", false)),
			"same branch %s restore re-arms the untouched exact source" % stage
		)
		_assert_claim_whole(pair, source_id, "", "same branch %s retry" % stage)

	for stage in ["accepted", "committed", "pickup"]:
		if not captures.has(stage):
			continue
		var fresh := await _boot_pair(TEACHING_SPEC)
		_apply_snapshot(fresh, captures[stage])
		var fresh_cache := _branch_cache(fresh, index)
		var fresh_source: Node = fresh_cache.get("interactable", null)
		if stage in ["accepted", "committed"]:
			_assert_claim_available(
				fresh, source_id, "fresh branch %s restore" % stage
			)
			fresh.host.set_preview_character_position(
				"aster", _source_position(fresh, fresh_source)
			)
			fresh_source.set("active_character", "aster")
			check(
				bool(fresh_source.call("_trigger", false)),
				"fresh branch %s restore requires one exact-source retry" % stage
			)
		else:
			_assert_claim_whole(
				fresh, source_id, "", "fresh physical-cache pickup restore"
			)
		var before_count := _count_items_for_source(fresh.host.game_state, source_id)
		fresh_source.set("active_character", "aster")
		check(
			not bool(fresh_source.call("_trigger", false))
			and _count_items_for_source(fresh.host.game_state, source_id) == before_count,
			"fresh branch %s restore remains exact-once and mints no duplicate" % stage
		)
		await _free_pair(fresh)
	await _free_pair(pair)


func _verify_spillway_source_transaction() -> void:
	print("\n--- exact spillway-catch transaction ---")
	var pair := await _boot_pair(TEACHING_SPEC)
	var host: AuthorityHost = pair.host
	var chunk: Node = pair.chunk
	var cache: Dictionary = chunk.get("_hydraulic_spillway_food_cache")
	var source_id := str(cache.get("resource_source_id", ""))
	var source: Node = cache.get("interactable", null)

	check(
		source != null
		and source_id != ""
		and not bool(chunk.call("_collect_hydraulic_spillway_food", "aster")),
		"retired spillway helper cannot mint or collect a dormant payload"
	)
	check(
		_prepare_spillway_delivery(pair),
		"physical controls carry the exact spillway payload to its catch"
	)
	var source_position := _source_position(pair, source)
	var initial_item_id := str(_claim(pair, source_id).get("item_id", ""))
	_assert_claim_available(pair, source_id, "arrived spillway source")
	check(
		initial_item_id != ""
		and source_position != Vector3.INF
		and _count_items_for_source(host.game_state, source_id) == 1,
		"spillway arrival owns one exact item and data-space service point"
	)

	source.emit_signal("interacted")
	check(
		str(_claim(pair, source_id).get("phase", "")) == "available",
		"direct catch signal emission cannot consume the arrived payload"
	)
	host.set_preview_character_position("aster", source_position + Vector3(10.0, 0.0, 0.0))
	source.set("active_character", "aster")
	check(
		not bool(source.call("_trigger", false))
		and str(_claim(pair, source_id).get("item_id", "")) == initial_item_id,
		"a distant body cannot collect the arrived spillway payload"
	)
	host.set_preview_character_position("aster", source_position)
	host.set_preview_character_position("peris", source_position + Vector3(10.0, 0.0, 0.0))
	source.set("active_character", "peris")
	check(
		not bool(source.call("_trigger", false)),
		"a remote selected actor cannot borrow another body's catch proximity"
	)

	var captures := {}
	var runtime_key := str(chunk.call("_generated_runtime_authority_key"))
	host.game_state.interactable_triggered.connect(
		func(interactable_id: String, _actor: String) -> void:
			if interactable_id == str(source.get("data_id")) \
					and not captures.has("accepted"):
				captures["accepted"] = _capture(pair)
	)
	host.game_state.world_state_changed.connect(
		func(key: String, _value: Variant) -> void:
			if key == runtime_key \
					and str(_claim(pair, source_id).get("phase", "")) == "claiming" \
					and not captures.has("committed"):
				captures["committed"] = _capture(pair)
	)
	host.game_state.item_picked_up.connect(
		func(_character_id: String, item_id: String) -> void:
			if str(_item_properties(host.game_state, item_id).get(
				"generated_resource_source_id", ""
			)) == source_id and not captures.has("pickup"):
				captures["pickup"] = _capture(pair)
	)
	host.set_preview_active_character("peris")
	host.set_preview_character_position("aster", source_position)
	source.set("active_character", "aster")
	check(
		bool(source.call("_trigger", false)),
		"nearby Aster collects at the catch while Peris remains selected"
	)
	check(
		captures.has("accepted")
		and captures.has("committed")
		and captures.has("pickup"),
		"spillway claim exposes accepted-source, CLAIMING, and pickup boundaries"
	)
	_assert_claim_whole(pair, source_id, "node_04", "completed spillway source")

	for stage in ["accepted", "committed", "pickup"]:
		if not captures.has(stage):
			continue
		var fresh := await _boot_pair(TEACHING_SPEC)
		_apply_snapshot(fresh, captures[stage])
		var fresh_cache: Dictionary = fresh.chunk.get("_hydraulic_spillway_food_cache")
		var fresh_source: Node = fresh_cache.get("interactable", null)
		if stage in ["accepted", "committed"]:
			_assert_claim_available(
				fresh, source_id, "fresh spillway %s restore" % stage
			)
			fresh.host.set_preview_character_position(
				"aster", _source_position(fresh, fresh_source)
			)
			fresh_source.set("active_character", "aster")
			check(
				bool(fresh_source.call("_trigger", false)),
				"fresh spillway %s restore requires an exact-source retry" % stage
			)
		else:
			_assert_claim_whole(
				fresh, source_id, "node_04", "fresh spillway pickup restore"
			)
		var before_count := _count_items_for_source(fresh.host.game_state, source_id)
		fresh_source.set("active_character", "aster")
		check(
			not bool(fresh_source.call("_trigger", false))
			and _count_items_for_source(fresh.host.game_state, source_id) == before_count,
			"fresh spillway %s restore remains exact-once" % stage
		)
		await _free_pair(fresh)
	await _free_pair(pair)


func _verify_exact_exit_and_atomic_rest() -> void:
	print("\n--- exact EXIT roster and atomic paid rest ---")
	var pair := await _boot_pair(TEACHING_SPEC)
	var host: AuthorityHost = pair.host
	var chunk: Node = pair.chunk
	check(_solve_before_exit(chunk), "teaching route reaches the decision immediately before EXIT")
	var state: Dictionary = chunk.call("get_preview_state")
	check(
		bool(state.get("hydraulic_exit_unlocked", false))
		and bool(chunk.call("_all_mandatory_branch_spans_bridged")),
		"EXIT probe has resolved hydraulic and branch prerequisites"
	)
	_place_party_at_spawns(pair)
	var roster := _active_roster(chunk)
	var before_atp := _atp_by_roster(host.game_state, roster)
	check(
		_all_at_any_shelter(host.game_state, roster)
		and not _any_at_exact_exit(chunk, roster),
		"full party begins in a valid shelter that is not the authored EXIT"
	)
	check(
		not bool(chunk.call("_reach_exit_shelter"))
		and _atp_by_roster(host.game_state, roster) == before_atp
		and not _any_resting(host.game_state, roster)
		and _exit_phase(pair) == "available",
		"entry shelter cannot impersonate EXIT or mutate payment/progression"
	)

	_place_party_at_exact_exit(pair, 1)
	check(
		not bool(chunk.call("_reach_exit_shelter"))
		and _atp_by_roster(host.game_state, roster) == before_atp
		and _exit_phase(pair) == "available",
		"one body at EXIT cannot complete a split active roster"
	)

	_place_party_at_exact_exit(pair)
	for character_id_v in roster:
		host.game_state.set_stat(str(character_id_v), "hp", 90.0)
	before_atp = _atp_by_roster(host.game_state, roster)
	var runtime_key := str(chunk.call("_generated_runtime_authority_key"))
	var captures := {}
	var observations := {"first_stat_was_atomic": false, "first_rest_was_atomic": false}
	host.game_state.world_state_changed.connect(
		func(key: String, _value: Variant) -> void:
			if key == runtime_key and _exit_phase(pair) == "committing" \
					and not captures.has("commit"):
				captures["commit"] = _capture(pair)
	)
	host.game_state.stat_changed.connect(
		func(_character_id: String, stat_name: String, _value: float) -> void:
			if stat_name == "atp" and not captures.has("stat"):
				observations["first_stat_was_atomic"] = (
					_all_paid_once(host.game_state, roster, before_atp)
					and _all_resting(host.game_state, roster)
				)
				captures["stat"] = _capture(pair)
	)
	host.game_state.rest_started.connect(
		func(_character_id: String) -> void:
			if not captures.has("rest"):
				observations["first_rest_was_atomic"] = (
					_all_paid_once(host.game_state, roster, before_atp)
					and _all_resting(host.game_state, roster)
				)
				captures["rest"] = _capture(pair)
	)
	check(bool(chunk.call("_reach_exit_shelter")), "full conscious roster commits authored EXIT")
	check(captures.has("commit"), "EXIT transaction is durable before any payment signal")
	check(
		bool(observations.first_stat_was_atomic) and bool(observations.first_rest_was_atomic),
		"first rest feedback observes the entire roster paid and resting, never a prefix"
	)
	check(
		_exit_phase(pair) == "complete"
		and _all_paid_once(host.game_state, roster, before_atp)
		and _all_resting(host.game_state, roster),
		"successful EXIT commits completion and one canonical rest payment per body"
	)

	for snapshot_record in [
		{"label": "pre-payment commit", "snapshot": captures.get("commit", {})},
		{"label": "first stat signal", "snapshot": captures.get("stat", {})},
		{"label": "first rest signal", "snapshot": captures.get("rest", {})},
	]:
		var snapshot: Dictionary = snapshot_record.snapshot
		if snapshot.is_empty():
			continue
		var fresh := await _boot_pair(TEACHING_SPEC)
		_apply_snapshot(fresh, snapshot)
		var fresh_roster := _active_roster(fresh.chunk)
		check(
			_exit_phase(fresh) == "complete"
			and _all_paid_once(fresh.host.game_state, fresh_roster, before_atp)
			and _all_resting(fresh.host.game_state, fresh_roster),
			"fresh %s restore converges to one whole EXIT outcome" % snapshot_record.label
		)
		await _free_pair(fresh)
	await _free_pair(pair)


func _verify_committed_payload_delivery() -> void:
	print("\n--- committed physical payload delivery ---")
	# The maintained hard-carry fixture now persists its mandatory branch-span
	# contract. Keep that topology enabled so both physical payloads are reached
	# through the same exact producer interactions as an ordinary playthrough.
	var pair := await _boot_pair(HARD_CARRY_SPEC)
	var host: AuthorityHost = pair.host
	var chunk: Node = pair.chunk
	var checked_stacked_source := false
	var original_position: Vector3 = host.game_state.get_position("aster")
	var original_level := int(host.game_state.get_character_level("aster"))
	for span_v in chunk.get("_branch_span_producers") as Array:
		if not (span_v is Node):
			continue
		var span := span_v as Node
		var span_state := span.call("get_state") as Dictionary
		var producer_position: Vector3 = span_state.get(
			"producer_data_position", Vector3.ZERO
		)
		var producer_level := int(host.game_state.grid.level_for_y(producer_position.y))
		if int(host.game_state.grid.level_count) <= 1:
			continue
		var wrong_level := 1 if producer_level == 0 else 0
		host.game_state.set_character_level("aster", wrong_level)
		host.game_state.snap_character_to("aster", producer_position)
		var producer: Node = span.call("get_producer_interactable")
		producer.set("active_character", "aster")
		var wrong_floor_position: Vector3 = host.game_state.get_position("aster")
		var source_data_position: Vector3 = chunk.call(
			"_generated_interaction_data_position", producer
		)
		var wrong_floor_result := bool(producer.call("_trigger", false))
		check(
			not wrong_floor_result and not bool(span.call("is_bridged")),
			(
				"a body sharing producer x/z on another navigation level cannot interact through the floor "
				+ "(actor level=%d pos=%s, producer level=%d data=%s, accepted=%s)"
			) % [
				host.game_state.get_character_level("aster"),
				wrong_floor_position,
				producer_level,
				source_data_position,
				wrong_floor_result,
			]
		)
		checked_stacked_source = true
		break
	host.game_state.set_character_level("aster", original_level)
	host.game_state.snap_character_to("aster", original_position)
	check(
		checked_stacked_source,
		"hard-carry fixture exercises an exact source on stacked navigation"
	)
	check(_solve_before_exit(chunk), "hard-carry fixture reaches its authored pre-EXIT state")
	var delivery: Dictionary = chunk.call("_required_payload_delivery")
	var payload_nodes: Array = delivery.get("node_ids", [])
	var payload_items: Array = delivery.get("item_ids", [])
	check(
		bool(delivery.get("ready", false))
		and payload_nodes.size() == 2
		and payload_items.size() == 2,
		"hard-carry EXIT owns two exact required node/item identities"
	)
	_place_party_at_exact_exit(pair)
	var roster := _active_roster(chunk)
	for character_id_v in roster:
		var character_id := str(character_id_v)
		host.game_state.set_stat(
			character_id, "hp", host.game_state.get_stat_cap(character_id, "hp")
		)
		host.game_state.set_stat(
			character_id, "stamina", host.game_state.get_stat_cap(character_id, "stamina")
		)
	var runtime_key := str(chunk.call("_generated_runtime_authority_key"))
	var captures := {}
	host.game_state.world_state_changed.connect(
		func(key: String, _value: Variant) -> void:
			if key == runtime_key and _exit_phase(pair) == "committing" \
					and not captures.has("commit"):
				captures["commit"] = _capture(pair)
	)
	var payload_exit_result := bool(chunk.call("_reach_exit_shelter"))
	if not payload_exit_result:
		print(
			"HARD-CARRY EXIT DIAGNOSTIC: outcome=%s mandatory=%s preflight=%s"
			% [
				str((chunk.call("get_preview_state") as Dictionary).get("last_outcome", "")),
				str(chunk.call("_all_mandatory_branch_spans_bridged")),
				str(chunk.call("_preflight_exit_shelter_transaction", delivery)),
			]
		)
	check(payload_exit_result, "hard-carry payloads deliver through EXIT")
	check(
		_exit_phase(pair) == "complete"
		and _all_ids_absent(host.game_state, payload_items)
		and _contains_all(_runtime_record(pair).get("delivered_resource_nodes", []), payload_nodes),
		"completed EXIT removes exact payloads and records their delivered node identities"
	)
	check(captures.has("commit"), "payload identities are durable before removal begins")

	if captures.has("commit"):
		# Model the narrowest possible save hook after item removal but before the
		# outer transaction's final publication. The durable committing record must
		# finish delivery; claimed sources must not respawn replacement payloads.
		var after_removal := (captures.commit as Dictionary).duplicate(true)
		_remove_payloads_from_serialized_game_state(after_removal, payload_items)
		var fresh := await _boot_pair(HARD_CARRY_SPEC)
		_apply_snapshot(fresh, after_removal)
		var fresh_record := _runtime_record(fresh)
		check(
			_exit_phase(fresh) == "complete"
			and _all_ids_absent(fresh.host.game_state, payload_items)
			and _contains_all(fresh_record.get("delivered_resource_nodes", []), payload_nodes),
			"fresh post-removal committing restore finishes delivery without losing completion"
		)
		var no_replacements := true
		for node_id_v in payload_nodes:
			if _count_items_for_source(fresh.host.game_state, "node:%s" % str(node_id_v)) != 0:
				no_replacements = false
		check(no_replacements, "claimed payload sources never respawn after committed delivery")
		await _free_pair(fresh)
	await _free_pair(pair)


func _verify_bridge_seated_publication() -> void:
	print("\n--- bridge seated publication ---")
	var pair := await _boot_pair(TEACHING_SPEC)
	var host: AuthorityHost = pair.host
	var chunk: Node = pair.chunk
	check(
		_trigger_control(pair, "_hydraulic_first_control"),
		"bridge probe opens First Sluice"
	)
	host.scheduler.advance_ticks(4.3)
	check(
		_trigger_control(pair, "_hydraulic_cistern_control"),
		"bridge probe starts physical cargo transport"
	)
	var transporting_snapshot := _capture(pair)
	var runtime_key := str(chunk.call("_generated_runtime_authority_key"))
	var seated_signal_keys: Array[String] = []
	var seated_authorities: Array[Dictionary] = []
	var seated_topology_observations: Array[bool] = []
	var seated_captures := {}
	host.game_state.world_state_changed.connect(
		func(key: String, value: Variant) -> void:
			var announces_seated := (
				(key == runtime_key and value is Dictionary \
					and str((value as Dictionary).get("bridge_cargo_phase", "")) == "seated")
				or (key == CARGO_PHASE_KEY and str(value) == "seated")
				or (key == CARGO_MILESTONE_KEY and value is Dictionary \
					and str((value as Dictionary).get("phase", "")) == "seated")
			)
			if not announces_seated:
				return
			seated_signal_keys.append(key)
			seated_authorities.append(_runtime_record(pair).duplicate(true))
			seated_topology_observations.append(_bridge_blockers_match(chunk, false))
			if not seated_captures.has("snapshot"):
				seated_captures["snapshot"] = _capture(pair)
	)
	host.scheduler.advance_ticks(3.001)
	check(
		seated_signal_keys == [runtime_key, CARGO_PHASE_KEY, CARGO_MILESTONE_KEY],
		"canonical seated record publishes before both compatibility signals"
	)
	var all_signal_states_whole := not seated_authorities.is_empty()
	for authority in seated_authorities:
		if not _bridge_authority_is_whole(authority):
			all_signal_states_whole = false
	check(
		all_signal_states_whole and not seated_topology_observations.has(false),
		"every 'seated' observer sees installed bridge, main flow, router, and open topology"
	)

	_apply_snapshot(pair, transporting_snapshot)
	check(
		str((chunk.call("get_preview_state") as Dictionary).get("bridge_cargo_phase", ""))
		== "transporting"
		and _bridge_blockers_match(chunk, true),
		"same-instance rollback restores the physical gap blocker with transporting state"
	)

	if seated_captures.has("snapshot"):
		var fresh := await _boot_pair(TEACHING_SPEC)
		_apply_snapshot(fresh, seated_captures.snapshot)
		var fresh_state: Dictionary = fresh.chunk.call("get_preview_state")
		check(
			_bridge_authority_is_whole(_runtime_record(fresh))
			and str(fresh_state.get("bridge_cargo_phase", "")) == "seated"
			and _bridge_blockers_match(fresh.chunk, false),
			"fresh first-signal restore derives seated visuals and traversable topology"
		)
		check(
			str(fresh.host.game_state.get_world_state(CARGO_PHASE_KEY, "")) == "seated"
			and str((fresh.host.game_state.get_world_state(CARGO_MILESTONE_KEY, {}) as Dictionary).get(
				"phase", ""
			)) == "seated",
			"fresh canonical restore advances compatibility keys captured one publication behind"
		)
		await _free_pair(fresh)
	await _free_pair(pair)


func _boot_pair(spec_path: String, branches_enabled := true) -> Dictionary:
	var host := AuthorityHost.new()
	host.setup()
	root.add_child(host)
	var chunk := CHUNK_SCENE.instantiate()
	chunk.configure_chunk(
		{
			"spec_path": spec_path,
			"game_mode": "neutral",
			"food_test": "neutral",
			"branches": branches_enabled,
		}
	)
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	host.game_state.grid = host.grid
	chunk.call("reset_preview_state")
	await process_frame
	return {"host": host, "chunk": chunk}


func _trigger_control(pair: Dictionary, field_name: String, actor := "aster") -> bool:
	var source_v: Variant = pair.chunk.get(field_name)
	if not (source_v is Node) or not is_instance_valid(source_v):
		return false
	var source := source_v as Node
	var position_v: Variant = pair.chunk.call(
		"_generated_interaction_data_position", source
	)
	if not (position_v is Vector3):
		return false
	pair.host.game_state.snap_character_to(actor, position_v as Vector3)
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _prepare_spillway_delivery(pair: Dictionary) -> bool:
	var solution_v: Variant = pair.chunk.call("get_solution_script")
	if not (solution_v is Dictionary):
		return false
	var solution := solution_v as Dictionary
	var consumed_actions := {}
	# The release control is physically beyond branch_00's unresolved span. Replay
	# the same per-node interleave as the golden path, including its mandatory
	# producer action, rather than invoking the hydraulic verbs in isolation.
	for node_id in ["entry", "node_01", "node_02", "node_03"]:
		pair.chunk.call(
			"_apply_solution_world_actions_before_node",
			solution,
			node_id,
			consumed_actions
		)
	var prepared_state := pair.chunk.call("get_preview_state") as Dictionary
	if not bool(prepared_state.get("first_sluice_open", false)) \
			or not bool(prepared_state.get("cistern_bridge_installed", false)):
		return false
	var diverter_v: Variant = pair.chunk.get("_hydraulic_diverter_control")
	var diverter_succeeded := (
		diverter_v is Node
		and bool(pair.chunk.call(
		"_headless_trigger_hydraulic_control", diverter_v as Node
		))
	)
	if not diverter_succeeded:
		return false
	var launch_tick := float(pair.chunk.get("_spillway_delivery_launch_tick"))
	var arrival_succeeded := (
		launch_tick >= 0.0
		and bool(pair.chunk.call(
		"_headless_advance_scheduler_to", launch_tick + 2.6
		))
	)
	if not arrival_succeeded:
		return false
	return (
		str((pair.chunk.call("get_preview_state") as Dictionary).get(
			"spillway_delivery_phase", ""
		)) == "available"
	)


func _free_pair(pair: Dictionary) -> void:
	var host: Node = pair.get("host", null)
	if host != null and is_instance_valid(host):
		host.queue_free()
	await process_frame
	await process_frame


func _capture(pair: Dictionary) -> Dictionary:
	return {
		"scheduler": _json_round_trip(pair.host.scheduler.serialize()),
		"game_state": _json_round_trip(pair.host.game_state.serialize()),
	}


func _apply_snapshot(pair: Dictionary, snapshot: Dictionary) -> void:
	pair.host.scheduler.clear()
	pair.host.scheduler.deserialize((snapshot.get("scheduler", {}) as Dictionary).duplicate(true))
	pair.host.game_state.deserialize((snapshot.get("game_state", {}) as Dictionary).duplicate(true))
	pair.chunk.call("on_game_state_snapshot_restored")


func _json_round_trip(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _runtime_record(pair: Dictionary) -> Dictionary:
	var key := str(pair.chunk.call("_generated_runtime_authority_key"))
	var record: Variant = pair.host.game_state.get_world_state(key, {})
	return record as Dictionary if record is Dictionary else {}


func _claim(pair: Dictionary, source_id: String) -> Dictionary:
	var claims := _runtime_record(pair).get("resource_claims", {}) as Dictionary
	var claim: Variant = claims.get(source_id, {})
	return claim as Dictionary if claim is Dictionary else {}


func _node_source(pair: Dictionary, node_id: String) -> Node:
	var sources: Dictionary = pair.chunk.get("_node_interactables")
	var source_v: Variant = sources.get(node_id, null)
	return source_v as Node if source_v is Node and is_instance_valid(source_v) else null


func _branch_cache(pair: Dictionary, index: int) -> Dictionary:
	for cache_v in pair.chunk.get("_branch_caches") as Array:
		if cache_v is Dictionary and int((cache_v as Dictionary).get("index", -1)) == index:
			return cache_v as Dictionary
	return {}


func _source_position(pair: Dictionary, source: Node) -> Vector3:
	if source == null or not is_instance_valid(source):
		return Vector3.INF
	var position_v: Variant = pair.chunk.call(
		"_generated_interaction_data_position", source
	)
	return position_v as Vector3 if position_v is Vector3 else Vector3.INF


func _exit_phase(pair: Dictionary) -> String:
	var transaction := _runtime_record(pair).get("exit_shelter_transaction", {}) as Dictionary
	return str(transaction.get("phase", ""))


func _item_properties(game_state, item_id: String) -> Dictionary:
	if not game_state.items.has(item_id):
		return {}
	return ((game_state.items[item_id] as Dictionary).get("properties", {}) as Dictionary)


func _count_items_for_source(game_state, source_id: String) -> int:
	var count := 0
	for item_v in game_state.items.values():
		if not (item_v is Dictionary):
			continue
		var properties := (item_v as Dictionary).get("properties", {}) as Dictionary
		if str(properties.get("generated_resource_source_id", "")) == source_id:
			count += 1
	return count


func _assert_claim_whole(
	pair: Dictionary, source_id: String, progression_node_id: String, label: String
) -> void:
	var claim := _claim(pair, source_id)
	var item_id := str(claim.get("item_id", ""))
	var item: Dictionary = pair.host.game_state.items.get(item_id, {})
	var holder := str(item.get("holder", ""))
	var progression_ok := progression_node_id == "" or (
		(_runtime_record(pair).get("completed_nodes", []) as Array).has(progression_node_id)
		and str((pair.chunk.get("_generated_resource_item_by_node") as Dictionary).get(
			progression_node_id, ""
		)) == item_id
	)
	check(
		str(claim.get("phase", "")) == "claimed"
		and item_id != ""
		and _count_items_for_source(pair.host.game_state, source_id) == 1
		and str(item.get("location", "")) == "hand"
		and holder != ""
		and (pair.host.game_state.get_hand_items(holder) as Array).has(item_id)
		and progression_ok,
		"%s owns one exact held item, mapping, and matching progression" % label
	)


func _assert_claim_available(pair: Dictionary, source_id: String, label: String) -> void:
	var claim := _claim(pair, source_id)
	var item_id := str(claim.get("item_id", ""))
	var item: Dictionary = pair.host.game_state.items.get(item_id, {})
	var raw_source: Array = claim.get("source_position", [])
	var source_position := (
		Vector3(float(raw_source[0]), float(raw_source[1]), float(raw_source[2]))
		if raw_source.size() >= 3
		else Vector3.INF
	)
	var item_position: Vector3 = item.get("position", Vector3.INF)
	check(
		str(claim.get("phase", "")) == "available"
		and item_id != ""
		and _count_items_for_source(pair.host.game_state, source_id) == 1
		and str(item.get("location", "")) == "ground"
		and str(item.get("holder", "")) == ""
		and source_position != Vector3.INF
		and item_position.distance_to(source_position) <= 0.01,
		"%s owns one exact ground item at its source" % label
	)


func _inject_claim_item_holder(
	snapshot: Dictionary,
	item_id: String,
	reserved_holder: String,
	injected_holder: String
) -> void:
	var saved := snapshot.get("game_state", {}) as Dictionary
	var items := saved.get("items", {}) as Dictionary
	if not items.has(item_id):
		return
	var item := items[item_id] as Dictionary
	item["location"] = "hand"
	item["holder"] = injected_holder
	for character_id in [reserved_holder, injected_holder]:
		var character := (saved.get("characters", {}) as Dictionary).get(
			character_id, {}
		) as Dictionary
		var hands := character.get("hands", [null, null]) as Array
		for index in range(hands.size()):
			if hands[index] == item_id:
				hands[index] = null
		if character_id == injected_holder:
			var slot := hands.find(null)
			if slot < 0:
				slot = 0
			hands[slot] = item_id
		character["hands"] = hands


func _solve_before_exit(chunk: Node) -> bool:
	chunk.call("reset_preview_state")
	chunk.call("set_active_loadout", "spotlight")
	var spec: Dictionary = chunk.call("get_generation_spec")
	var solution := spec.get("headless", {}).get("solution", {}) as Dictionary
	var path: Array = spec.get("headless", {}).get("golden_path", [])
	var consumed := {}
	for node_id_v in path:
		var node_id := str(node_id_v)
		chunk.call(
			"_apply_solution_world_actions_before_node", solution, node_id, consumed
		)
		if node_id == "exit_shelter":
			break
		var node: Dictionary = chunk.call("_find_node", node_id)
		if str(chunk.call("_runtime_handler_for_node", node)) == "":
			continue
		if not bool(chunk.call("_headless_activate_generated_node", node_id)):
			print(
				"PRE-EXIT SOLVE FAILED: %s // %s // spans=%s // consumed=%s"
				% [
					node_id,
					str((chunk.call("get_preview_state") as Dictionary).get("last_outcome", "")),
					str((chunk.call("get_preview_state") as Dictionary).get("branch_span_states", [])),
					consumed,
				]
			)
			return false
	return true


func _active_roster(chunk: Node) -> Array:
	return (chunk.call("get_preview_state") as Dictionary).get("active_party", []) as Array


func _place_party_at_spawns(pair: Dictionary) -> void:
	var spawns: Dictionary = pair.chunk.call("get_spawn_positions")
	for character_id_v in _active_roster(pair.chunk):
		var character_id := str(character_id_v)
		if spawns.has(character_id):
			pair.host.set_preview_character_position(character_id, spawns[character_id])


func _place_party_at_exact_exit(pair: Dictionary, count := -1) -> void:
	var roster := _active_roster(pair.chunk)
	var region: Dictionary = pair.chunk.call("_exit_shelter_region")
	var center: Vector3 = region.get("center", Vector3.ZERO)
	var spacing := minf(0.9, float((region.get("half", Vector3.ONE) as Vector3).z) * 0.35)
	var placed := roster.size() if count < 0 else mini(count, roster.size())
	for index in range(placed):
		var z_offset := (float(index) - float(placed - 1) * 0.5) * spacing
		pair.host.set_preview_character_position(str(roster[index]), center + Vector3(0, 0, z_offset))


func _atp_by_roster(game_state, roster: Array) -> Dictionary:
	var result := {}
	for character_id_v in roster:
		var character_id := str(character_id_v)
		result[character_id] = float(game_state.get_stat(character_id, "atp"))
	return result


func _all_paid_once(game_state, roster: Array, before: Dictionary) -> bool:
	for character_id_v in roster:
		var character_id := str(character_id_v)
		if not is_equal_approx(
			float(game_state.get_stat(character_id, "atp")),
			float(before.get(character_id, 0.0)) - 1.0
		):
			return false
	return true


func _all_resting(game_state, roster: Array) -> bool:
	for character_id_v in roster:
		if not bool(game_state.is_resting(str(character_id_v))):
			return false
	return true


func _any_resting(game_state, roster: Array) -> bool:
	for character_id_v in roster:
		if bool(game_state.is_resting(str(character_id_v))):
			return true
	return false


func _all_at_any_shelter(game_state, roster: Array) -> bool:
	for character_id_v in roster:
		if not bool(game_state.is_at_shelter(str(character_id_v))):
			return false
	return true


func _any_at_exact_exit(chunk: Node, roster: Array) -> bool:
	for character_id_v in roster:
		if bool(chunk.call("_is_character_in_exact_exit_shelter", str(character_id_v))):
			return true
	return false


func _all_ids_absent(game_state, item_ids: Array) -> bool:
	for item_id_v in item_ids:
		if game_state.items.has(str(item_id_v)):
			return false
	return true


func _contains_all(haystack_v: Variant, needles: Array) -> bool:
	var haystack: Array = haystack_v if haystack_v is Array else []
	for needle in needles:
		if not haystack.has(needle):
			return false
	return true


func _remove_payloads_from_serialized_game_state(snapshot: Dictionary, item_ids: Array) -> void:
	var saved := snapshot.get("game_state", {}) as Dictionary
	var items := saved.get("items", {}) as Dictionary
	for item_id_v in item_ids:
		items.erase(str(item_id_v))
	for character_v in (saved.get("characters", {}) as Dictionary).values():
		if not (character_v is Dictionary):
			continue
		var character := character_v as Dictionary
		var hands := character.get("hands", []) as Array
		for index in range(hands.size()):
			if item_ids.has(str(hands[index])):
				hands[index] = null


func _bridge_authority_is_whole(authority: Dictionary) -> bool:
	var router := authority.get("flow_router", {}) as Dictionary
	return (
		str(authority.get("bridge_cargo_phase", "")) == "seated"
		and bool(authority.get("cistern_bridge_installed", false))
		and bool(authority.get("main_current_restored", false))
		and not bool(authority.get("borrowed_current_diverted", true))
		and str(authority.get("hydraulic_phase", "")) == "exit_ready"
		and str(router.get("current_route", "")) == "main"
	)


func _bridge_blockers_match(chunk: Node, expected_blocked: bool) -> bool:
	var host: AuthorityHost = chunk.get("host")
	if host == null or host.game_state.grid == null:
		return false
	var cells: Array = chunk.call("_hydraulic_bridge_blocker_cells")
	if cells.is_empty():
		return false
	for cell_v in cells:
		var cell := cell_v as Vector2i
		if host.game_state.grid.dynamic_blockers.has(cell) != expected_blocked:
			return false
	return true


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
