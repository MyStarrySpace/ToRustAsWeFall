extends SceneTree

## Regression for chunk-local phases that used to disappear when TutorialSequence cleared the
## EventScheduler callback heap. Each case saves in the middle, advances into a discarded future,
## rolls the same presenter back, and then applies the snapshot to a freshly built presenter.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const LureRelayScript := preload("res://scripts/fragments/chunks/lure_relay_chunk.gd")
const DistractGateScript := preload("res://scripts/fragments/chunks/distract_gate_chunk.gd")
const InflammashuntScript := preload("res://scripts/fragments/chunks/inflammashunt_chunk.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_lure_relay_midpoint()
	await _verify_distract_gate_midpoint()
	await _verify_inflammashunt_midpoints()
	await _verify_inflammashunt_item_semantics()
	await _verify_inflammashunt_sac_claim_restore()
	print("REMAINING CHUNK SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_lure_relay_midpoint() -> void:
	var pair := await _boot_chunk(LureRelayScript, "lure_relay")
	var host = pair.host
	var chunk = pair.chunk
	var absent := _capture(host)
	check(not chunk.activate_lure2(),
		"Lure Relay's former direct helper cannot manufacture a song")
	chunk._lure2.flure_activated.emit(3)
	check(not bool(chunk.get_preview_state().lure2_active),
		"a forged Relay signal without a physical source receipt is inert")
	check(_trigger_flure_source(host, chunk._lure2),
		"Lure Relay starts from the exact far-Flure source")
	# The physical trigger leaves Peris at the flower. Model the intended next action before time
	# advances: retreat into the nearby pocket so the arriving guards do not legitimately spot her.
	host.game_state.snap_character_to("peris", chunk.HIDE_POS)
	chunk.headless_process(0.0)
	host.scheduler.advance_ticks(4.0)
	var capture := _capture(host)
	var deadline := float(chunk._lure2_until)
	check(is_equal_approx(deadline, 12.0),
		"Lure Relay stores an absolute far-lure deadline")
	check(_trigger_flure_source(host, chunk._lure1),
		"discarded future can trigger the other exact Flure")
	host.game_state.snap_character_to("peris", chunk.HIDE_POS)
	chunk.headless_process(0.0)
	_apply_capture(host, chunk, capture)
	var rolled: Dictionary = chunk.get_preview_state()
	check(bool(rolled.lure2_active) and not bool(rolled.lure1_active)
			and int(rolled.committed_lure) == 2,
		"Lure Relay rollback retracts the future lure and restores the committed one")
	check(float(rolled.get("win_poll_deadline", -1.0)) >= float(host.scheduler.get_current_tick()),
		"Lure Relay rollback reattaches its fixed-cadence full-party exit check")
	host.scheduler.advance_ticks(deadline - float(host.scheduler.get_current_tick()) - 0.01)
	check(int(chunk.get_preview_state().committed_lure) == 2,
		"restored relay cannot expire before its original deadline")
	host.scheduler.advance_ticks(0.01)
	check(not bool(chunk.get_preview_state().lure2_active),
		"restored far Flure expires at its original physical deadline")
	# The relay coordinator observes the reusable Flure's same-tick expiry one deterministic
	# transaction beat later, so restore order cannot decide whether the handoff happens.
	host.scheduler.advance_ticks(0.00001)
	check(int(chunk.get_preview_state().committed_lure) == 0,
		"restored relay consumes the expiry exactly once after the physical source")
	check(_trigger_flure_source(host, chunk._lure1),
		"Lure Relay can create a later exact-source phase for absence rollback")
	_apply_capture(host, chunk, absent)
	check(str(chunk.get_preview_state().phase) == "ready"
			and not bool(chunk.get_preview_state().lure1_active),
		"missing Lure Relay authority retracts a later local phase")

	var fresh_pair := await _boot_chunk(LureRelayScript, "lure_relay_fresh")
	_apply_capture(fresh_pair.host, fresh_pair.chunk, capture)
	check(int(fresh_pair.chunk.get_preview_state().committed_lure) == 2,
		"fresh Lure Relay presenter restores the midpoint phase")
	fresh_pair.host.scheduler.advance_ticks(8.0)
	check(not bool(fresh_pair.chunk.get_preview_state().lure2_active),
		"fresh Lure Relay presenter expires the physical source after the saved remainder")
	fresh_pair.host.scheduler.advance_ticks(0.00001)
	check(int(fresh_pair.chunk.get_preview_state().committed_lure) == 0,
		"fresh Lure Relay presenter consumes only the saved remainder")
	await _discard(host)
	await _discard(fresh_pair.host)


func _verify_distract_gate_midpoint() -> void:
	var pair := await _boot_chunk(DistractGateScript, "distract_gate")
	var host = pair.host
	var chunk = pair.chunk
	var absent := _capture(host)
	check(not chunk.activate_flure(),
		"Distract Gate's former direct helper cannot manufacture a song")
	chunk._flure.flure_activated.emit(1)
	check(not bool(chunk.get_preview_state().lure_active),
		"a forged Watched Gap signal without a physical source receipt is inert")
	check(_trigger_flure_source(host, chunk._flure),
		"Distract Gate starts from its exact physical Flure")
	# The fixture activates in place; the real solve immediately falls back off the watched lane
	# while the sentry travels to the flower.
	host.game_state.snap_character_to("peris", Vector3(2.5, 0.5, -4.0))
	host.scheduler.advance_ticks(5.0)
	var capture := _capture(host)
	var deadline := float(chunk._lure_until)
	check(is_equal_approx(deadline, 20.0),
		"Distract Gate stores an absolute lure deadline")
	host.scheduler.advance_ticks(15.0)
	check(bool(chunk.get_preview_state().lure_returning),
		"discarded future reaches the sentry-return phase")
	_apply_capture(host, chunk, capture)
	var rolled: Dictionary = chunk.get_preview_state()
	check(bool(rolled.lure_active) and not bool(rolled.lure_returning),
		"Distract Gate rollback retracts return and restores the live window")
	host.scheduler.advance_ticks(deadline - float(host.scheduler.get_current_tick()) - 0.01)
	check(bool(chunk.get_preview_state().lure_active),
		"restored gate lure cannot expire early")
	host.scheduler.advance_ticks(0.01)
	check(bool(chunk.get_preview_state().lure_returning),
		"restored gate lure enters return exactly once at its deadline")
	_apply_capture(host, chunk, absent)
	check(str(chunk.get_preview_state().phase) == "ready"
			and not bool(chunk.get_preview_state().lure_returning),
		"missing Distract Gate authority retracts a later return phase")

	var fresh_pair := await _boot_chunk(DistractGateScript, "distract_gate_fresh")
	_apply_capture(fresh_pair.host, fresh_pair.chunk, capture)
	check(bool(fresh_pair.chunk.get_preview_state().lure_active),
		"fresh Distract Gate presenter restores the live lure")
	# The completion poll is a separate repeating phase and must survive the same scheduler clear.
	fresh_pair.host.game_state.snap_character_to("aster", Vector3(20.5, 0.5, 0.0))
	fresh_pair.host.scheduler.advance_ticks(0.11)
	check(not bool(fresh_pair.chunk.get_preview_state().complete),
		"one runner beyond the Watched Gap cannot abandon the rest of the party")
	fresh_pair.host.game_state.snap_character_to("peris", Vector3(20.5, 0.5, -1.0))
	fresh_pair.host.game_state.snap_character_to("endo", Vector3(20.5, 0.5, 1.0))
	fresh_pair.host.scheduler.advance_ticks(0.11)
	check(bool(fresh_pair.chunk.get_preview_state().complete),
		"fresh Distract Gate presenter reattaches the fixed-cadence full-party end check")
	await _discard(host)
	await _discard(fresh_pair.host)


func _verify_inflammashunt_midpoints() -> void:
	var pair := await _boot_chunk(InflammashuntScript, "inflammashunt")
	var host = pair.host
	var chunk = pair.chunk
	check(_trigger_inflammashunt_source(chunk, host.game_state, "GasSacFlora", "peris"),
		"Peris tends the exact gas-sac flora source")
	check(_trigger_inflammashunt_source(chunk, host.game_state, "TakeSac", "aster"),
		"Aster takes the exact ripe pod")
	host.scheduler.advance_ticks(7.0)
	var sac_capture := _capture(host)
	var sac_deadline := float(chunk._sac_expires)
	check(str(chunk.gas_sac_state) == "active" and is_equal_approx(sac_deadline, 22.0),
		"Inflammashunt stores the real-item sac phase and absolute expiry")
	var sac_item_id := str(chunk._sac_item_id)
	check(sac_item_id != "" and host.game_state.items.has(sac_item_id)
			and host.game_state.get_hand_items("aster").has(sac_item_id),
		"the sac occupies Aster's canonical GameState hand")
	host.scheduler.advance_ticks(15.0)
	check(str(chunk.gas_sac_state) == "expired" and not host.game_state.items.has(sac_item_id),
		"discarded future expires the sac and removes the real item")
	_apply_capture(host, chunk, sac_capture)
	check(str(chunk.gas_sac_state) == "active" and str(chunk._sac_holder()) == "aster"
			and host.game_state.get_hand_items("aster").has(sac_item_id),
		"Inflammashunt rollback retracts sac expiry and restores canonical item ownership")
	host.scheduler.advance_ticks(sac_deadline - float(host.scheduler.get_current_tick()) - 0.01)
	check(str(chunk.gas_sac_state) == "active", "restored sac cannot expire early")
	host.scheduler.advance_ticks(0.01)
	check(str(chunk.gas_sac_state) == "expired" and not host.game_state.items.has(sac_item_id),
		"restored sac expires on its original cadence tick and clears the hand")
	check(_trigger_inflammashunt_source(chunk, host.game_state, "GasSacFlora", "peris")
			and _trigger_inflammashunt_source(chunk, host.game_state, "TakeSac", "aster"),
		"the expired pod is physically tended and taken again")
	host.game_state.world_state.erase(chunk.INFLAMMASHUNT_AUTHORITY_KEY)
	chunk.on_game_state_snapshot_restored()
	check(str(chunk.gas_sac_state) == "idle" and str(chunk._sac_holder()) == ""
			and not host.game_state.items.has(str(chunk._sac_item_id)),
		"missing Inflammashunt authority retracts a later carried item phase")

	# A hostile root is a dynamically spawned gameplay body. A fresh scene must recreate the presenter,
	# not merely leave a serialized character with no node or recovery callback.
	chunk.root_state = "hostile"
	chunk._spawn_hostile_root()
	host.scheduler.advance_ticks(0.1)
	var root_capture := _capture(host)
	# A fresh presenter for the same saved scene keeps the stable chunk identity; interactable data
	# ids intentionally include it, so inventing a different fixture name would test impersonation.
	var root_fresh := await _boot_chunk(InflammashuntScript, "inflammashunt")
	_apply_capture(root_fresh.host, root_fresh.chunk, root_capture)
	check(root_fresh.chunk._root_enemy != null
			and is_instance_valid(root_fresh.chunk._root_enemy)
			and root_fresh.host.game_state.characters.has("hostile_root"),
		"fresh Inflammashunt presenter recreates the saved hostile-root body")
	check(str(root_fresh.chunk._root_timer_mode) == "poll",
		"fresh hostile root reattaches its exact scheduler poll phase")

	# Physically tend/take the repellent, bring its carrier to the hostile root at the authored base,
	# and let the saved poll schedule the retract. No direct process callback stands in for herding.
	check(_trigger_inflammashunt_source(
			root_fresh.chunk, root_fresh.host.game_state, "GasSacFlora", "peris"),
		"the root-recovery fixture tends its exact flora source")
	check(_trigger_inflammashunt_source(
			root_fresh.chunk, root_fresh.host.game_state, "TakeSac", "aster"),
		"the root-recovery fixture takes its exact repellent source")
	var root_position: Vector3 = root_fresh.host.game_state.get_position("hostile_root")
	root_fresh.host.game_state.snap_character_to(
		"aster", root_position + Vector3(0.5, 0.0, 0.0))
	root_fresh.host.scheduler.advance_ticks(maxf(
		0.0, float(root_fresh.chunk._root_deadline)
			- float(root_fresh.host.scheduler.get_current_tick())) + 0.001)
	check(str(root_fresh.chunk._root_timer_mode) == "retract",
		"the nearby physical sac causes the root poll to reserve its retract")
	root_fresh.host.scheduler.advance_ticks(InflammashuntScript.ROOT_RETRACT_DELAY)
	check(str(root_fresh.chunk.root_state) == "recovering",
		"the reserved root physically retracts before regrowth begins")
	root_fresh.host.scheduler.advance_ticks(1.25)
	var regrow_capture := _capture(root_fresh.host)
	var regrow_deadline := float(root_fresh.chunk._root_deadline)
	root_fresh.host.scheduler.advance_ticks(regrow_deadline
			- float(root_fresh.host.scheduler.get_current_tick()))
	check(str(root_fresh.chunk.root_state) == "suppressed",
		"future root regrows at its committed deadline")
	_apply_capture(root_fresh.host, root_fresh.chunk, regrow_capture)
	check(str(root_fresh.chunk.root_state) == "recovering",
		"root rollback restores the recovering midpoint")
	root_fresh.host.scheduler.advance_ticks(regrow_deadline
			- float(root_fresh.host.scheduler.get_current_tick()) - 0.01)
	check(str(root_fresh.chunk.root_state) == "recovering", "restored root cannot regrow early")
	root_fresh.host.scheduler.advance_ticks(0.01)
	check(str(root_fresh.chunk.root_state) == "suppressed", "restored root regrows exactly once")

	var regrow_fresh := await _boot_chunk(InflammashuntScript, "inflammashunt_regrow_fresh")
	_apply_capture(regrow_fresh.host, regrow_fresh.chunk, regrow_capture)
	check(str(regrow_fresh.chunk.root_state) == "recovering",
		"fresh Inflammashunt presenter restores root recovery")
	regrow_fresh.host.scheduler.advance_ticks(regrow_deadline
			- float(regrow_fresh.host.scheduler.get_current_tick()))
	check(str(regrow_fresh.chunk.root_state) == "suppressed",
		"fresh Inflammashunt presenter consumes only the saved regrow remainder")

	# The buffer mistake spawns two real enemies, cools at an absolute rage deadline, then reforms.
	# Both the dynamic roster and the delayed topology/presenter state must survive a fresh scene.
	var buffer_pair := await _boot_chunk(InflammashuntScript, "inflammashunt_buffer")
	check(_trigger_inflammashunt_source(
			buffer_pair.chunk, buffer_pair.host.game_state, "StrikeCluster", "aster"),
		"the buffer mistake begins at the exact physical strike source")
	check(buffer_pair.chunk._extra_chelators.size() == 2
			and str(buffer_pair.chunk.buffer_state) == "shattered",
		"buffer mistake commits two dynamic Chelators and the shattered phase")
	buffer_pair.host.scheduler.advance_ticks(8.0)
	var buffer_capture := _capture(buffer_pair.host)
	buffer_pair.host.scheduler.advance_ticks(12.0)
	check(str(buffer_pair.chunk.buffer_state) == "stable",
		"discarded future cools and reforms the buffer")
	_apply_capture(buffer_pair.host, buffer_pair.chunk, buffer_capture)
	check(str(buffer_pair.chunk.buffer_state) == "shattered"
			and buffer_pair.chunk._extra_chelators.size() == 2,
		"buffer rollback retracts reform while preserving the saved dynamic roster")

	var buffer_fresh := await _boot_chunk(InflammashuntScript, "inflammashunt_buffer_fresh")
	_apply_capture(buffer_fresh.host, buffer_fresh.chunk, buffer_capture)
	check(str(buffer_fresh.chunk.buffer_state) == "shattered"
			and buffer_fresh.chunk._extra_chelators.size() == 2,
		"fresh Inflammashunt presenter recreates the saved buffer encounter")
	buffer_fresh.host.scheduler.advance_ticks(8.0)
	check(str(buffer_fresh.chunk.buffer_state) == "reforming",
		"fresh buffer reaches reforming at the original rage deadline")
	var reform_deadline := float(buffer_fresh.chunk._buffer_reform_deadline)
	buffer_fresh.host.scheduler.advance_ticks(reform_deadline
			- float(buffer_fresh.host.scheduler.get_current_tick()) - 0.01)
	check(str(buffer_fresh.chunk.buffer_state) == "reforming",
		"fresh buffer cannot finish reforming early")
	buffer_fresh.host.scheduler.advance_ticks(0.01)
	check(str(buffer_fresh.chunk.buffer_state) == "stable",
		"fresh buffer reforms exactly once at its original deadline")

	await _discard(host)
	await _discard(root_fresh.host)
	await _discard(regrow_fresh.host)
	await _discard(buffer_pair.host)
	await _discard(buffer_fresh.host)


func _verify_inflammashunt_item_semantics() -> void:
	var pair := await _boot_chunk(InflammashuntScript, "inflammashunt_item_semantics")
	var host = pair.host
	var chunk = pair.chunk
	var gs = host.game_state
	check(_trigger_inflammashunt_source(chunk, gs, "GasSacFlora", "peris"),
		"item-semantics fixture tends the exact flora")
	gs.snap_character_to("aster", InflammashuntScript.SAC_SOURCE_POS)
	var aster_pos: Vector3 = gs.get_position("aster")
	var filler_a: String = gs.spawn_item("seed", aster_pos)
	var filler_b: String = gs.spawn_item("seed", aster_pos)
	check(gs.pick_up_item("aster", filler_a) and gs.pick_up_item("aster", filler_b),
		"item-semantic fixture fills both of Aster's canonical hands")
	check(not _trigger_inflammashunt_source(chunk, gs, "TakeSac", "aster"),
		"full hands refuse the exact pod before its source receipt is consumed")
	check(str(chunk.gas_sac_state) == "tended" and str(chunk._sac_item_id) != ""
			and chunk._sac_item_at_source(),
		"occupied hands leave the same ripe pod visibly seated at its source")
	gs.remove_item(filler_a)
	gs.remove_item(filler_b)
	check(_trigger_inflammashunt_source(chunk, gs, "TakeSac", "aster"),
		"the retry takes the same exact pod once a hand is free")
	var sac_id := str(chunk._sac_item_id)
	check(sac_id != "" and str((gs.items[sac_id] as Dictionary).get("type", "")) == "gas_sac"
			and str((gs.items[sac_id] as Dictionary).get("holder", "")) == "aster",
		"taking the ripe pod transfers the pre-existing authored gas_sac item")
	check(not gs.endocytose_item("aster", sac_id),
		"the recovery tool cannot be consumed through an unrelated inventory effect")
	gs.snap_character_to("peris", aster_pos + Vector3(0.5, 0.0, 0.0))
	check(gs.transfer_item("aster", "peris", sac_id)
			and str(chunk.headless_get_state().get("sac_carrier", "")) == "peris",
		"ordinary inventory transfer immediately hands root-repellent authority to Peris")
	check(gs.drop_item("peris", sac_id)
			and str(chunk.headless_get_state().get("sac_carrier", "missing")) == ""
			and gs.items.has(sac_id),
		"dropping the sac preserves the world item but removes the carrier aura")
	check(gs.pick_up_item("aster", sac_id)
			and str(chunk.headless_get_state().get("sac_carrier", "")) == "aster",
		"the dropped pod can be recovered through the same canonical pickup path")
	check(_trigger_inflammashunt_source(chunk, gs, "JunctionTerminal", "aster")
			and _trigger_inflammashunt_source(chunk, gs, "ThermalResetConfirm", "aster"),
		"the physical terminal exposes and accepts its exact reset control")
	check(str(chunk.gas_sac_state) == "ignited" and not gs.items.has(sac_id)
			and not gs.get_hand_items("aster").has(sac_id),
		"ignition consumes the physical sac and clears its actual hand slot")
	await _discard(host)

	var legacy_pair := await _boot_chunk(InflammashuntScript, "inflammashunt_legacy_sac")
	var legacy_host = legacy_pair.host
	var legacy_chunk = legacy_pair.chunk
	var legacy_capture := _capture(legacy_host)
	var game_state: Dictionary = legacy_capture.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	var legacy_authority: Dictionary = legacy_chunk._inflammashunt_authority_state()
	legacy_authority["version"] = 2
	legacy_authority["gas_sac_state"] = "carried"
	legacy_authority["sac_carrier"] = "aster"
	legacy_authority.erase("sac_item_id")
	world_state[InflammashuntScript.INFLAMMASHUNT_AUTHORITY_KEY] = legacy_authority
	game_state["world_state"] = world_state
	legacy_capture["game_state"] = game_state
	_apply_capture(legacy_host, legacy_chunk, legacy_capture)
	check(str(legacy_chunk.gas_sac_state) == "tended"
			and str(legacy_chunk._sac_item_id) != ""
			and legacy_chunk._sac_item_at_source()
			and legacy_host.game_state.get_hand_items("aster").is_empty(),
		"v2 pseudo-carrier saves migrate to one retryable source pod instead of minting a phantom hand item")
	await _discard(legacy_host)


func _verify_inflammashunt_sac_claim_restore() -> void:
	var pair := await _boot_chunk(InflammashuntScript, "inflammashunt_sac_claim")
	var host = pair.host
	var chunk = pair.chunk
	var gs = host.game_state
	check(_trigger_inflammashunt_source(chunk, gs, "GasSacFlora", "peris"),
		"claim-seam fixture tends the exact flora")
	var source_id := str(chunk._sac_item_id)
	var take_source: Node = chunk.find_child("TakeSac", true, false)
	var take_data_id := str(take_source.get("data_id"))

	# GameState accepts a one-shot source before the chunk callback publishes its semantic receipt.
	# Restoring in that narrow window must retract/re-arm the source, not remotely grant its item.
	var accepted_box := {"value": {}}
	var capture_accepted := func(data_id: String, _actor: String) -> void:
		if data_id == take_data_id:
			accepted_box["value"] = _capture(host)
	gs.interactable_triggered.connect(capture_accepted, CONNECT_ONE_SHOT)
	check(_trigger_inflammashunt_source(chunk, gs, "TakeSac", "aster")
			and not (accepted_box["value"] as Dictionary).is_empty(),
		"gas-sac verifier captures the accepted-source-before-callback seam")
	var accepted_only: Dictionary = accepted_box["value"]
	_apply_capture(host, chunk, accepted_only)
	check(str(chunk.gas_sac_state) == "tended"
			and str(chunk._sac_item_id) == source_id
			and chunk._sac_item_at_source()
			and gs.is_interactable_enabled(take_data_id)
			and gs.get_hand_items("aster").is_empty(),
		"same-presenter restore retracts an orphan sac receipt to the exact retryable pod")

	var accepted_fresh := await _boot_chunk(
		InflammashuntScript, "inflammashunt_sac_claim")
	_apply_capture(accepted_fresh.host, accepted_fresh.chunk, accepted_only)
	var accepted_fresh_source: Node = accepted_fresh.chunk.find_child("TakeSac", true, false)
	check(str(accepted_fresh.chunk.gas_sac_state) == "tended"
			and str(accepted_fresh.chunk._sac_item_id) == source_id
			and accepted_fresh.chunk._sac_item_at_source()
			and accepted_fresh.host.game_state.is_interactable_enabled(
				str(accepted_fresh_source.get("data_id")))
			and accepted_fresh.host.game_state.get_hand_items("aster").is_empty(),
		"a fresh presenter also retracts the orphan sac receipt without granting inventory")
	await _discard(accepted_fresh.host)

	# A forged second source-tagged pod cannot become a second reward on either restore path.
	var duplicate_id := str(chunk._spawn_sac_source_item({"duplicate_save_fixture": true}))
	check(duplicate_id != "" and duplicate_id != source_id,
		"gas-sac duplicate fixture creates a distinct tagged item")
	var duplicated_source := _capture(host)
	_apply_capture(host, chunk, duplicated_source)
	check(str(chunk._sac_item_id) == source_id
			and gs.items.has(source_id)
			and not gs.items.has(duplicate_id)
			and _count_inflammashunt_sac_items(chunk, gs) == 1,
		"same-presenter restore preserves the saved pod identity and removes duplicate rewards")
	var duplicate_fresh := await _boot_chunk(
		InflammashuntScript, "inflammashunt_sac_claim")
	_apply_capture(duplicate_fresh.host, duplicate_fresh.chunk, duplicated_source)
	check(str(duplicate_fresh.chunk._sac_item_id) == source_id
			and duplicate_fresh.host.game_state.items.has(source_id)
			and not duplicate_fresh.host.game_state.items.has(duplicate_id)
			and _count_inflammashunt_sac_items(
				duplicate_fresh.chunk, duplicate_fresh.host.game_state) == 1,
		"a fresh presenter also removes a forged duplicate pod")
	await _discard(duplicate_fresh.host)

	# Current saves bind the tended source to one exact item. If it disappears, a different tagged
	# item cannot impersonate it; the uncommitted action retracts to one newly spawned source pod.
	gs.remove_item(source_id)
	var forged_source_id := str(chunk._spawn_sac_source_item(
		{"forged_missing_source_fixture": true}))
	var missing_exact_source := _capture(host)
	_apply_capture(host, chunk, missing_exact_source)
	var recovered_source_id := str(chunk._sac_item_id)
	check(recovered_source_id != "" and recovered_source_id != source_id
			and recovered_source_id != forged_source_id
			and chunk._sac_item_at_source()
			and not gs.items.has(forged_source_id)
			and _count_inflammashunt_sac_items(chunk, gs) == 1
			and gs.get_hand_items("aster").is_empty(),
		"a missing tended pod retracts to one new source instead of adopting a forgery")
	var missing_fresh := await _boot_chunk(
		InflammashuntScript, "inflammashunt_sac_claim")
	_apply_capture(missing_fresh.host, missing_fresh.chunk, missing_exact_source)
	check(str(missing_fresh.chunk._sac_item_id) != forged_source_id
			and missing_fresh.chunk._sac_item_at_source()
			and not missing_fresh.host.game_state.items.has(forged_source_id)
			and _count_inflammashunt_sac_items(
				missing_fresh.chunk, missing_fresh.host.game_state) == 1
			and missing_fresh.host.game_state.get_hand_items("aster").is_empty(),
		"a fresh presenter also refuses to adopt a forged replacement pod")
	await _discard(missing_fresh.host)
	source_id = recovered_source_id

	var capture_box := {"value": {}}
	var capture_pickup := func(char_id: String, item_id: String) -> void:
		if char_id == "aster" and item_id == source_id:
			capture_box["value"] = _capture(host)
	gs.item_picked_up.connect(capture_pickup, CONNECT_ONE_SHOT)
	check(_trigger_inflammashunt_source(chunk, gs, "TakeSac", "aster"),
		"claim-seam fixture takes the exact source pod")
	check(not (capture_box["value"] as Dictionary).is_empty(),
		"gas-sac verifier captures the synchronous item-pick save seam")
	var signal_capture: Dictionary = capture_box["value"]
	_apply_capture(host, chunk, signal_capture)
	_apply_capture(host, chunk, signal_capture)
	var restored: Dictionary = chunk.headless_get_state()
	check(str(chunk.gas_sac_state) == "active"
			and str(restored.get("sac_item_id", "")) == source_id
			and str(restored.get("sac_carrier", "")) == "aster"
			and int(restored.get("sac_claim_serial", 0)) == 1
			and gs.get_hand_items("aster").count(source_id) == 1
			and _count_inflammashunt_sac_items(chunk, gs) == 1,
		"repeated same-presenter claiming restore completes the reserved exact pod once")
	var signal_fresh := await _boot_chunk(
		InflammashuntScript, "inflammashunt_sac_claim")
	_apply_capture(signal_fresh.host, signal_fresh.chunk, signal_capture)
	_apply_capture(signal_fresh.host, signal_fresh.chunk, signal_capture)
	var fresh_restored: Dictionary = signal_fresh.chunk.headless_get_state()
	check(str(signal_fresh.chunk.gas_sac_state) == "active"
			and str(fresh_restored.get("sac_item_id", "")) == source_id
			and str(fresh_restored.get("sac_carrier", "")) == "aster"
			and int(fresh_restored.get("sac_claim_serial", 0)) == 1
			and signal_fresh.host.game_state.get_hand_items("aster").count(source_id) == 1
			and _count_inflammashunt_sac_items(
				signal_fresh.chunk, signal_fresh.host.game_state) == 1,
		"repeated fresh-presenter claiming restore grants no duplicate pod")
	await _discard(signal_fresh.host)
	await _discard(host)

	pair = await _boot_chunk(InflammashuntScript, "inflammashunt_sac_wrong_holder")
	host = pair.host
	chunk = pair.chunk
	gs = host.game_state
	check(_trigger_inflammashunt_source(chunk, gs, "GasSacFlora", "peris"),
		"wrong-holder fixture tends the exact flora")
	source_id = str(chunk._sac_item_id)
	gs.snap_character_to("peris", InflammashuntScript.SAC_SOURCE_POS)
	chunk.gas_sac_state = "claiming"
	chunk._sac_carrier = "aster"
	chunk._sac_expires = float(host.scheduler.get_current_tick()) + InflammashuntScript.SAC_DURATION
	chunk._publish_inflammashunt_authority()
	check(gs.pick_up_item("peris", source_id),
		"fixture injects a mismatched gas-sac holder")
	var mismatch := _capture(host)
	_apply_capture(host, chunk, mismatch)
	restored = chunk.headless_get_state()
	check(str(chunk.gas_sac_state) == "claiming"
			and str(restored.get("sac_reserved_carrier", "")) == "aster"
			and str(restored.get("sac_carrier", "")) == "peris",
		"gas-sac restore never substitutes a wrong holder for the reserved claimant")
	chunk.root_state = "hostile"
	chunk._spawn_hostile_root()
	host.scheduler.advance_ticks(InflammashuntScript.ROOT_POLL_INTERVAL + 0.001)
	restored = chunk.headless_get_state()
	check(str(chunk.gas_sac_state) == "claiming"
			and str(restored.get("sac_reserved_carrier", "")) == "aster"
			and str(restored.get("sac_carrier", "")) == "peris",
		"the live hostile-root poll neither retargets CLAIMING nor grants its repel field")
	await _discard(host)

	pair = await _boot_chunk(
		InflammashuntScript, "inflammashunt_sac_forged_claim")
	host = pair.host
	chunk = pair.chunk
	gs = host.game_state
	check(_trigger_inflammashunt_source(chunk, gs, "GasSacFlora", "peris"),
		"forged-claim fixture tends the exact flora")
	source_id = str(chunk._sac_item_id)
	gs.remove_item(source_id)
	var forged_claim_id := str(chunk._spawn_sac_source_item(
		{"forged_claim_substitute_fixture": true}))
	gs.snap_character_to("aster", InflammashuntScript.SAC_SOURCE_POS)
	check(gs.pick_up_item("aster", forged_claim_id),
		"fixture puts a forged tagged pod in the reserved actor's hand")
	chunk.gas_sac_state = "claiming"
	chunk._sac_carrier = "aster"
	chunk._sac_expires = float(host.scheduler.get_current_tick()) \
		+ InflammashuntScript.SAC_DURATION
	chunk._sac_claim_serial = 1
	chunk._publish_inflammashunt_authority()
	var forged_substitution := _capture(host)
	_apply_capture(host, chunk, forged_substitution)
	restored = chunk.headless_get_state()
	check(str(chunk.gas_sac_state) == "tended"
			and str(restored.get("sac_item_id", "")) != forged_claim_id
			and bool(restored.get("sac_item_at_source", false))
			and not gs.items.has(forged_claim_id)
			and not gs.get_hand_items("aster").has(forged_claim_id)
			and _count_inflammashunt_sac_items(chunk, gs) == 1,
		"a claiming restore cannot substitute a forged tagged pod held by the reserved actor")
	var forged_fresh := await _boot_chunk(
		InflammashuntScript, "inflammashunt_sac_forged_claim")
	_apply_capture(forged_fresh.host, forged_fresh.chunk, forged_substitution)
	var forged_fresh_state: Dictionary = forged_fresh.chunk.headless_get_state()
	check(str(forged_fresh.chunk.gas_sac_state) == "tended"
			and str(forged_fresh_state.get("sac_item_id", "")) != forged_claim_id
			and bool(forged_fresh_state.get("sac_item_at_source", false))
			and not forged_fresh.host.game_state.items.has(forged_claim_id)
			and _count_inflammashunt_sac_items(
				forged_fresh.chunk, forged_fresh.host.game_state) == 1,
		"a fresh presenter also rejects a forged gas-sac claiming substitute")
	await _discard(forged_fresh.host)
	await _discard(host)


func _count_inflammashunt_sac_items(chunk: Node, gs) -> int:
	var count := 0
	if chunk == null or gs == null or not "items" in gs:
		return count
	for item_id_v in gs.items.keys():
		if bool(chunk.call("_is_live_sac_item_id", str(item_id_v))):
			count += 1
	return count


func _trigger_inflammashunt_source(
		chunk: Node, gs, node_name: String, actor: String
	) -> bool:
	var source: Node = chunk.find_child(node_name, true, false)
	if source == null or gs == null or not gs.characters.has(actor):
		return false
	var data_id := str(source.get("data_id"))
	if data_id == "" or not gs.has_interactable(data_id):
		return false
	var source_position: Vector3 = gs.get_interactable(data_id).get(
		"position", Vector3.INF)
	if not source_position.is_finite():
		return false
	gs.snap_character_to(actor, source_position)
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _trigger_flure_source(host, source: Flure, actor := "peris") -> bool:
	if host == null or source == null or host.game_state == null \
			or not host.game_state.characters.has(actor):
		return false
	host.game_state.snap_character_to(actor, source.get_source_data_position())
	host.game_state.set_party([actor])
	source.active_character = actor
	return bool(source.call("_trigger", false))


func _boot_chunk(script: Script, chunk_name: String) -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = script.new()
	chunk.attach_chunk_host(host, chunk_name)
	if chunk_name.begins_with("inflammashunt"):
		chunk.configure_chunk({"party": ["aster", "peris", "myke"]})
	else:
		for id_v in chunk.get_spawn_positions().keys():
			var id := str(id_v)
			host.game_state.register_character(id, chunk.get_spawn_positions()[id_v], 3.0,
				{"hp": 100.0})
	host.add_child(chunk)
	await process_frame
	await process_frame
	if chunk_name.begins_with("inflammashunt"):
		for id_v in chunk.get_spawn_positions().keys():
			var id := str(id_v)
			if not host.game_state.characters.has(id):
				host.game_state.register_character(id, chunk.get_spawn_positions()[id_v], 3.0,
					{"hp": 100.0})
	if chunk.has_method("get_grid_data"):
		host.grid = GridWorld.from_data(chunk.get_grid_data())
		host.game_state.grid = host.grid
	chunk.reset_preview_state()
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
	chunk.on_game_state_snapshot_restored()
	# TutorialSequence notifies the full presenter tree after the chunk parent. Include dynamically
	# recreated enemies/fields in the same production-shaped pass.
	var pending: Array[Node] = []
	for child in chunk.get_children():
		pending.append(child)
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if node.has_method("on_game_state_snapshot_restored"):
			node.call("on_game_state_snapshot_restored")


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if "scheduler" in node and node.get("scheduler") != null:
			node.get("scheduler").clear()
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
