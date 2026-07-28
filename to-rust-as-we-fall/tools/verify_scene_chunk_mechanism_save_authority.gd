extends SceneTree

## Save/load coverage for SceneChunk's reusable world mechanisms: delayed sump/silo phases, the
## instant authoritative belt-powered state, and the sump's honest physical (non-reward) outcome.
## The load helper clears the callback heap before installing GameState, matching TutorialSequence.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const FixtureScript := preload("res://tools/scene_chunk_mechanism_fixture.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_sump_authority()
	await _verify_silo_authority()
	await _verify_belt_authority()
	await _verify_sump_accepted_before_owner_seam()
	await _verify_silo_accepted_before_owner_seam()
	await _verify_belt_accepted_before_owner_seam()
	await _verify_v2_receipt_migration()
	print("SCENE CHUNK MECHANISM SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_sump_authority() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var key: String = chunk.scene_mechanism_authority_key()
	var legacy := _capture(host)
	(legacy["game_state"]["world_state"] as Dictionary).erase(key)
	var sump_entry := chunk._sumps[0] as Dictionary
	var pump: Node = sump_entry["pump"]
	var housing: Node3D = chunk.find_child("SumpServiceHousing0", true, false) as Node3D
	check(chunk.find_child("SumpSalvage0", true, false) == null
			and not host.game_state.has_interactable("scene_mechanism_fixture_SumpSalvage0"),
		"sump exposes no false SALVAGE affordance when no canonical item is authored")
	check(housing != null and not housing.visible and host.game_state.items.is_empty(),
		"MID sump begins with submerged service housing and no invented inventory reward")
	check(bool(pump.get("one_shot")) and _source_trigger_count(host, pump) == 0
			and _source_is_armed(host, pump),
		"repeatable sump starts as a receipt-producing exact one-shot source")
	check(not bool(chunk._on_sump_pumped(0))
			and int((chunk._sumps[0] as Dictionary)["pending"]) == -1,
		"sump direct helper cannot manufacture a water-level transition")
	pump.emit_signal("interacted")
	check(int((chunk._sumps[0] as Dictionary)["pending"]) == -1
			and _source_trigger_count(host, pump) == 0,
		"sump manually emitted signal cannot manufacture a source receipt")
	pump.set("active_character", "aster")
	check(not bool(pump.call("_trigger", false))
			and _source_trigger_count(host, pump) == 0,
		"sump rejects a selected but physically remote party body")
	_snap_actor_to_source(host, pump, "aster")
	host.game_state.set_character_level("aster", 1)
	check(not bool(pump.call("_trigger", false))
			and _source_trigger_count(host, pump) == 0,
		"sump rejects matching x/z on the wrong navigation floor")
	host.game_state.set_character_level("aster", 0)
	host.game_state.down_character("aster")
	check(not bool(pump.call("_trigger", false))
			and _source_trigger_count(host, pump) == 0,
		"sump rejects a nearby downed body")
	host.game_state.restore_character("aster")
	_snap_actor_to_source(host, pump, "aster")
	check(_trigger_exact_source(host, pump, "aster"),
		"sump transition begins only from its exact nearby ready body and source")
	host.scheduler.advance_ticks(0.4)
	var midpoint := _capture(host)
	var saved: Dictionary = host.game_state.get_world_state(key, {})
	var saved_sump: Dictionary = (saved.get("sumps", []) as Array)[0]
	check(int(saved_sump.get("state", -1)) == 1
			and int(saved_sump.get("pending", -1)) == 2
			and is_equal_approx(float(saved_sump.get("deadline", -1.0)), 1.2)
			and int(saved_sump.get("trigger_consumed", -1)) == 1,
		"sump authority records MID -> FLOODED, exact receipt, and absolute deadline")
	check(not bool(pump.call("_trigger", false))
			and _source_trigger_count(host, pump) == 1,
		"pending sump cannot mint a second receipt before its physical transition commits")

	host.scheduler.advance_ticks(0.8)
	var sump: Dictionary = chunk._sumps[0]
	var pen = sump["pen"]
	check(int(sump["state"]) == 2 and not pen.is_alive(),
		"discarded future floods the sump and drowns its penned enemy")
	check(1 in host.game_state.grid.links_from(Vector2i(4, 2), 0),
		"discarded future raises the sump's real ledge link")
	check(_source_trigger_count(host, pump) == 1 and _source_is_armed(host, pump),
		"committed sump transition explicitly rearms its physical pump without resetting count")

	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	sump = chunk._sumps[0]
	pen = sump["pen"]
	check(int(sump["state"]) == 1 and int(sump["pending"]) == 2 and pen.is_alive(),
		"same-instance rollback retracts flood/death while retaining the pending phase")
	check(not (1 in host.game_state.grid.links_from(Vector2i(4, 2), 0)),
		"same-instance rollback retracts future ledge topology")
	host.scheduler.advance_ticks(0.799)
	check(int((chunk._sumps[0] as Dictionary)["state"]) == 1,
		"restored sump cannot finish before its original deadline")
	host.scheduler.advance_ticks(0.001)
	check(int((chunk._sumps[0] as Dictionary)["state"]) == 2 and not pen.is_alive(),
		"idempotent restore attaches exactly one sump consequence at the saved deadline")

	var fresh_pair := await _boot()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, midpoint)
	var fresh_sump: Dictionary = fresh._sumps[0]
	check(int(fresh_sump["state"]) == 1 and int(fresh_sump["pending"]) == 2,
		"fresh sump presenter reconstructs the saved midpoint")
	fresh_host.scheduler.advance_ticks(0.8)
	check(int((fresh._sumps[0] as Dictionary)["state"]) == 2,
		"fresh sump presenter consumes only the saved remainder")
	var fresh_pump: Node = (fresh._sumps[0] as Dictionary)["pump"]
	check(_source_is_armed(fresh_host, fresh_pump)
			and _trigger_exact_source(fresh_host, fresh_pump, "aster"),
		"fresh committed sump can physically begin its next reversible cycle")
	var second_cycle: Dictionary = fresh_host.game_state.get_world_state(
		fresh.scene_mechanism_authority_key(), {})
	check(_source_trigger_count(fresh_host, fresh_pump) == 2
			and int(((second_cycle.get("sumps", []) as Array)[0] as Dictionary).get(
				"trigger_consumed", -1)) == 2,
		"repeatable sump retains monotonic receipt identity across rearm")
	fresh_host.scheduler.advance_ticks(1.2)
	var fresh_housing: Node3D = fresh.find_child("SumpServiceHousing0", true, false) as Node3D
	check(int((fresh._sumps[0] as Dictionary)["state"]) == 0
			and fresh_housing != null and fresh_housing.visible,
		"draining exposes an honest service housing alongside the real open pit")
	check(not fresh_host.game_state.grid.dynamic_blockers.has(Vector2i(2, 2))
			and not (1 in fresh_host.game_state.grid.links_from(Vector2i(4, 2), 0)),
		"drained sump outcome is the open under-route, not a proxy completion label")
	check(fresh_host.game_state.items.is_empty(),
		"draining cannot synthesize an unsupported healing or ATP item")
	check(_source_trigger_count(fresh_host, fresh_pump) == 2
			and _source_is_armed(fresh_host, fresh_pump),
		"second sump commit rearms only after completion and preserves both receipts")

	_apply_capture(host, chunk, legacy)
	sump = chunk._sumps[0]
	pen = sump["pen"]
	check(int(sump["state"]) == 1 and int(sump["pending"]) == -1 and pen.is_alive(),
		"missing authority is baseline truth, not the presenter's discarded flooded future")
	check(not (1 in host.game_state.grid.links_from(Vector2i(4, 2), 0)),
		"missing-record rollback also retracts future sump topology")
	check(_source_trigger_count(host, pump) == 0 and _source_is_armed(host, pump),
		"missing-record rollback retracts the sump receipt and re-arms its exact source")
	await _discard(host)
	await _discard(fresh_host)


func _verify_belt_authority() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var key: String = chunk.scene_mechanism_authority_key()
	var legacy := _capture(host)
	(legacy["game_state"]["world_state"] as Dictionary).erase(key)
	var entry := chunk._belts[0] as Dictionary
	var belt = entry["belt"]
	var breaker = entry["breaker"]
	check(not bool(entry["powered"]) and not bool(belt.powered)
			and breaker.is_interaction_enabled(),
		"unpowered belt truth presents a live breaker and a refusing line")
	check(not bool(chunk._on_belt_breaker(0))
			and not bool((chunk._belts[0] as Dictionary)["powered"]),
		"belt direct helper cannot manufacture a powered line")
	breaker.emit_signal("interacted")
	check(not bool((chunk._belts[0] as Dictionary)["powered"])
			and _source_trigger_count(host, breaker) == 0,
		"belt manually emitted signal cannot manufacture a breaker receipt")
	breaker.active_character = "aster"
	check(not bool(breaker._trigger(false))
			and _source_trigger_count(host, breaker) == 0,
		"belt rejects a selected but physically remote party body")
	check(_trigger_exact_source(host, breaker, "aster"),
		"breaker power intervention requires its exact nearby ready body and source")
	var powered_capture := _capture(host)
	var saved: Dictionary = host.game_state.get_world_state(key, {})
	var saved_belts: Array = saved.get("belts", []) as Array
	check(int(saved.get("version", 0)) == chunk.SCENE_MECHANISM_AUTHORITY_VERSION
			and saved_belts.size() == 1
			and bool((saved_belts[0] as Dictionary).get("powered", false))
			and int((saved_belts[0] as Dictionary).get("trigger_consumed", -1)) == 1
			and _source_trigger_count(host, breaker) == 1,
		"belt power is versioned authority owned by one exact monotonic breaker receipt")
	check(bool((chunk._belts[0] as Dictionary)["powered"]) and bool(belt.powered)
			and not breaker.is_interaction_enabled(),
		"powered truth drives both the ride gate and the spent breaker presenter")
	check(not bool(breaker._trigger(false)),
		"a powered belt cannot re-fire its authority-derived one-shot breaker")
	breaker.emit_signal("interacted")
	check(_source_trigger_count(host, breaker) == 1
			and bool((chunk._belts[0] as Dictionary)["powered"]),
		"spent breaker signal spam neither increments nor changes owner truth")

	# Corrupt only the presenter, then restore twice. Portable truth must win without a second signal.
	belt.set_powered(false)
	_apply_capture(host, chunk, powered_capture)
	_apply_capture(host, chunk, powered_capture)
	entry = chunk._belts[0] as Dictionary
	check(bool(entry["powered"]) and bool((entry["belt"] as BeltLine).powered)
			and not (entry["breaker"] as Interactable).is_interaction_enabled(),
		"same-instance idempotent restore rebuilds powered belt and spent breaker together")

	_apply_capture(host, chunk, legacy)
	_apply_capture(host, chunk, legacy)
	entry = chunk._belts[0] as Dictionary
	check(not bool(entry["powered"]) and not bool((entry["belt"] as BeltLine).powered)
			and (entry["breaker"] as Interactable).is_interaction_enabled(),
		"missing authority retracts later belt power and re-arms its breaker from baseline truth")
	check(_source_trigger_count(host, entry["breaker"] as Node) == 0,
		"missing authority also retracts the discarded breaker receipt")

	var fresh_pair := await _boot()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, powered_capture)
	var fresh_entry := fresh._belts[0] as Dictionary
	check(bool(fresh_entry["powered"]) and bool((fresh_entry["belt"] as BeltLine).powered)
			and not (fresh_entry["breaker"] as Interactable).is_interaction_enabled(),
		"fresh presenter reconstructs powered belt and one-shot breaker from portable truth")
	_apply_capture(fresh_host, fresh, legacy)
	fresh_entry = fresh._belts[0] as Dictionary
	check(not bool(fresh_entry["powered"]) and not bool((fresh_entry["belt"] as BeltLine).powered)
			and (fresh_entry["breaker"] as Interactable).is_interaction_enabled(),
		"fresh presenter also honors authority absence as the unpowered baseline")
	await _discard(host)
	await _discard(fresh_host)


func _verify_silo_authority() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var key: String = chunk.scene_mechanism_authority_key()
	var legacy := _capture(host)
	(legacy["game_state"]["world_state"] as Dictionary).erase(key)
	var aster_hp := float(host.game_state.get_stat("aster", "hp"))
	var silo_entry := chunk._silos[0] as Dictionary
	var lever: Node = silo_entry["lever"]
	check(not bool(chunk._on_silo_vented(0))
			and str((chunk._silos[0] as Dictionary)["phase"]) == chunk.SILO_PHASE_CLOSED,
		"silo direct helper cannot manufacture an avalanche")
	lever.emit_signal("interacted")
	check(str((chunk._silos[0] as Dictionary)["phase"]) == chunk.SILO_PHASE_CLOSED
			and _source_trigger_count(host, lever) == 0,
		"silo manually emitted signal cannot manufacture a vent receipt")
	lever.set("active_character", "aster")
	check(not bool(lever.call("_trigger", false))
			and _source_trigger_count(host, lever) == 0,
		"silo rejects a selected but physically remote party body")
	check(_trigger_exact_source(host, lever, "aster"),
		"silo opening begins only from its exact nearby ready body and lever")
	# The lever is apart from the spill. Entering the visible consequence footprint after pulling it
	# is what makes the saved avalanche hurt Aster; the button press itself never deals damage.
	host.game_state.snap_character_to("aster", Vector3(10.0, 0.0, 6.0))
	host.scheduler.advance_ticks(0.25)
	var midpoint := _capture(host)
	var saved: Dictionary = host.game_state.get_world_state(key, {})
	var saved_silo: Dictionary = (saved.get("silos", []) as Array)[0]
	check(str(saved_silo.get("phase", "")) == chunk.SILO_PHASE_OPENING
			and is_equal_approx(float(saved_silo.get("deadline", -1.0)), 0.8)
			and int(saved_silo.get("trigger_consumed", -1)) == 1,
		"silo authority records OPENING, its exact lever receipt, and absolute deadline")
	check(not bool(lever.call("_trigger", false))
			and _source_trigger_count(host, lever) == 1,
		"opening silo cannot mint a second receipt during its saved delay")

	host.scheduler.advance_ticks(0.55)
	var silo: Dictionary = chunk._silos[0]
	check(str(silo["phase"]) == chunk.SILO_PHASE_VENTED and chunk.silo_victim.is_alive() == false,
		"discarded future vents and buries the ground-level enemy")
	check(is_equal_approx(float(host.game_state.get_stat("aster", "hp")), aster_hp - 20.0),
		"discarded future applies the silo's party damage once")
	check(1 in host.game_state.grid.links_from(Vector2i(10, 6), 0)
			and bool((silo["scree"] as Node3D).visible),
		"discarded future installs visible, traversable scree topology")
	check(not _source_is_armed(host, lever)
			and _source_trigger_count(host, lever) == 1,
		"vented silo keeps its exact one-shot lever spent")

	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	silo = chunk._silos[0]
	check(str(silo["phase"]) == chunk.SILO_PHASE_OPENING and chunk.silo_victim.is_alive(),
		"same-instance rollback retracts the vent and restores its victim")
	check(is_equal_approx(float(host.game_state.get_stat("aster", "hp")), aster_hp)
			and not (1 in host.game_state.grid.links_from(Vector2i(10, 6), 0))
			and not bool((silo["scree"] as Node3D).visible),
		"same-instance rollback retracts damage, ramp, and scree together")
	host.scheduler.advance_ticks(0.549)
	check(str((chunk._silos[0] as Dictionary)["phase"]) == chunk.SILO_PHASE_OPENING,
		"restored silo cannot vent before its original deadline")
	host.scheduler.advance_ticks(0.001)
	check(str((chunk._silos[0] as Dictionary)["phase"]) == chunk.SILO_PHASE_VENTED
			and is_equal_approx(float(host.game_state.get_stat("aster", "hp")), aster_hp - 20.0),
		"idempotent restore attaches exactly one silo consequence at the saved deadline")
	var vented := _capture(host)
	var vented_hp := float(host.game_state.get_stat("aster", "hp"))
	_apply_capture(host, chunk, vented)
	_apply_capture(host, chunk, vented)
	check(is_equal_approx(float(host.game_state.get_stat("aster", "hp")), vented_hp),
		"loading a vented silo rebuilds its presenter without replaying damage")

	var fresh_pair := await _boot()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, midpoint)
	check(str((fresh._silos[0] as Dictionary)["phase"]) == fresh.SILO_PHASE_OPENING,
		"fresh silo presenter reconstructs the saved midpoint")
	fresh_host.scheduler.advance_ticks(0.55)
	check(str((fresh._silos[0] as Dictionary)["phase"]) == fresh.SILO_PHASE_VENTED
			and is_equal_approx(float(fresh_host.game_state.get_stat("aster", "hp")), aster_hp - 20.0),
		"fresh silo presenter consumes only the saved remainder and consequence")

	_apply_capture(host, chunk, legacy)
	silo = chunk._silos[0]
	check(str(silo["phase"]) == chunk.SILO_PHASE_CLOSED and chunk.silo_victim.is_alive(),
		"missing authority retracts the discarded vent and restores its victim")
	check(is_equal_approx(float(host.game_state.get_stat("aster", "hp")), aster_hp)
			and not (1 in host.game_state.grid.links_from(Vector2i(10, 6), 0))
			and not bool((silo["scree"] as Node3D).visible),
		"missing-record rollback retracts silo damage and topology")
	check(_source_trigger_count(host, lever) == 0 and _source_is_armed(host, lever),
		"missing-record rollback retracts the silo receipt and re-arms the exact lever")
	await _discard(host)
	await _discard(fresh_host)


func _verify_sump_accepted_before_owner_seam() -> void:
	await _verify_accepted_before_owner_seam(
		"sump", "_on_sump_pumped", "sump water transition")


func _verify_silo_accepted_before_owner_seam() -> void:
	await _verify_accepted_before_owner_seam(
		"silo", "_on_silo_vented", "silo avalanche")


func _verify_belt_accepted_before_owner_seam() -> void:
	await _verify_accepted_before_owner_seam(
		"belt", "_on_belt_breaker", "belt power")


## Interactable publishes its registry acceptance before emitting `interacted`. A save observer can
## therefore catch one synchronous edge whose source count advanced but whose owner record did not.
## All three reusable mechanisms must burn/rearm that orphan on same- and fresh-presenter restore;
## none may infer its physical consequence from a presenter-local spent bit.
func _verify_accepted_before_owner_seam(
		kind: String, callback_method: String, consequence_label: String) -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var source := _mechanism_source(chunk, kind)
	var owner_callback := Callable(chunk, callback_method).bind(0, source)
	check(source != null and source.interacted.is_connected(owner_callback),
		"%s accepted-seam fixture identifies the exact bound owner callback" % kind.capitalize())
	source.interacted.disconnect(owner_callback)
	check(_trigger_exact_source(host, source, "aster"),
		"%s fixture captures real acceptance before its owner callback" % kind.capitalize())
	var accepted_record: Dictionary = host.game_state.get_world_state(
		chunk.scene_mechanism_authority_key(), {})
	check(_mechanism_is_baseline(chunk, kind)
			and _saved_mechanism_consumed(accepted_record, kind) == 0
			and _source_trigger_count(host, source) == 1
			and not _source_is_armed(host, source),
		"%s accepted-before-owner save has one source edge but no free %s" % [
			kind.capitalize(), consequence_label,
		])
	var accepted_capture := _capture(host)
	source.interacted.connect(owner_callback)

	check(bool(chunk.call(callback_method, 0, source))
			and _mechanism_has_started(chunk, kind),
		"%s fixture advances beyond the accepted edge before rollback" % kind.capitalize())
	_apply_capture(host, chunk, accepted_capture)
	_apply_capture(host, chunk, accepted_capture)
	var reconciled: Dictionary = host.game_state.get_world_state(
		chunk.scene_mechanism_authority_key(), {})
	check(_mechanism_is_baseline(chunk, kind)
			and _saved_mechanism_consumed(reconciled, kind) == 1
			and _source_trigger_count(host, source) == 1
			and _source_is_armed(host, source),
		"same presenter burns and rearms orphan %s receipt without granting %s" % [
			kind, consequence_label,
		])
	check(_trigger_exact_source(host, source, "aster")
			and _source_trigger_count(host, source) == 2
			and _mechanism_live_consumed(chunk, kind) == 2
			and _mechanism_has_started(chunk, kind),
		"same-presenter %s retry commits exactly the next physical receipt" % kind)

	var fresh_pair := await _boot()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, accepted_capture)
	_apply_capture(fresh_host, fresh, accepted_capture)
	var fresh_source := _mechanism_source(fresh, kind)
	var fresh_record: Dictionary = fresh_host.game_state.get_world_state(
		fresh.scene_mechanism_authority_key(), {})
	check(_mechanism_is_baseline(fresh, kind)
			and _saved_mechanism_consumed(fresh_record, kind) == 1
			and _source_trigger_count(fresh_host, fresh_source) == 1
			and _source_is_armed(fresh_host, fresh_source),
		"fresh presenter reconciles accepted-before-owner %s without inventing %s" % [
			kind, consequence_label,
		])
	check(_trigger_exact_source(fresh_host, fresh_source, "aster")
			and _source_trigger_count(fresh_host, fresh_source) == 2
			and _mechanism_live_consumed(fresh, kind) == 2
			and _mechanism_has_started(fresh, kind),
		"fresh-presenter %s retry also consumes exactly one newer receipt" % kind)
	await _discard(host)
	await _discard(fresh_host)


## Version 2 already saved the actual sump/silo phases and belt power, but predated owner-consumed
## receipt counts. Migration must preserve those physical truths, derive counts only from the exact
## source registries at that tick, publish v3 immediately, and resume only the saved remainders.
func _verify_v2_receipt_migration() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var sump_source := _mechanism_source(chunk, "sump")
	var silo_source := _mechanism_source(chunk, "silo")
	var belt_source := _mechanism_source(chunk, "belt")
	check(_trigger_exact_source(host, sump_source, "aster")
			and _trigger_exact_source(host, silo_source, "aster")
			and _trigger_exact_source(host, belt_source, "aster"),
		"v2 migration fixture acquires all three mechanisms through their physical sources")
	host.scheduler.advance_ticks(0.3)
	var legacy_capture := _capture(host)
	var game_state: Dictionary = legacy_capture.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	var key: String = chunk.scene_mechanism_authority_key()
	var legacy_record: Dictionary = world_state.get(key, {})
	legacy_record["version"] = 2
	for collection_name in ["sumps", "silos", "belts"]:
		var collection: Array = legacy_record.get(collection_name, []) as Array
		for state_v in collection:
			if state_v is Dictionary:
				(state_v as Dictionary).erase("trigger_consumed")
	world_state[key] = legacy_record
	game_state["world_state"] = world_state
	legacy_capture["game_state"] = game_state

	var fresh_pair := await _boot()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, legacy_capture)
	var migrated: Dictionary = fresh_host.game_state.get_world_state(
		fresh.scene_mechanism_authority_key(), {})
	check(int(migrated.get("version", 0)) == fresh.SCENE_MECHANISM_AUTHORITY_VERSION
			and _saved_mechanism_consumed(migrated, "sump") == 1
			and _saved_mechanism_consumed(migrated, "silo") == 1
			and _saved_mechanism_consumed(migrated, "belt") == 1,
		"v2 mechanism save migrates exact registry counts into v3 monotonic owner receipts")
	check(int((fresh._sumps[0] as Dictionary)["state"]) == 1
			and int((fresh._sumps[0] as Dictionary)["pending"]) == 2
			and str((fresh._silos[0] as Dictionary)["phase"]) == fresh.SILO_PHASE_OPENING
			and bool((fresh._belts[0] as Dictionary)["powered"]),
		"v2 migration preserves the saved sump midpoint, silo midpoint, and powered belt")
	check(not _source_is_armed(fresh_host, _mechanism_source(fresh, "sump"))
			and not _source_is_armed(fresh_host, _mechanism_source(fresh, "silo"))
			and not _source_is_armed(fresh_host, _mechanism_source(fresh, "belt")),
		"migrated in-flight/complete owners keep each exact source spent")
	var migrated_silo_deadline := float(
		((migrated.get("silos", []) as Array)[0] as Dictionary).get("deadline", -1.0))
	var migrated_sump_deadline := float(
		((migrated.get("sumps", []) as Array)[0] as Dictionary).get("deadline", -1.0))
	fresh_host.scheduler.advance_ticks(
		migrated_silo_deadline - float(fresh_host.scheduler.get_current_tick()) - 0.001)
	check(str((fresh._silos[0] as Dictionary)["phase"]) == fresh.SILO_PHASE_OPENING
			and int((fresh._sumps[0] as Dictionary)["pending"]) == 2,
		"migrated delayed mechanisms cannot commit before their original absolute deadlines")
	fresh_host.scheduler.advance_ticks(0.002)
	check(str((fresh._silos[0] as Dictionary)["phase"]) == fresh.SILO_PHASE_VENTED
			and int((fresh._sumps[0] as Dictionary)["pending"]) == 2,
		"migrated silo consumes only its saved remainder while the later sump remains pending")
	fresh_host.scheduler.advance_ticks(
		migrated_sump_deadline - float(fresh_host.scheduler.get_current_tick()) + 0.001)
	check(int((fresh._sumps[0] as Dictionary)["state"]) == 2
			and int((fresh._sumps[0] as Dictionary)["pending"]) == -1
			and _source_trigger_count(
				fresh_host, _mechanism_source(fresh, "sump")) == 1
			and _source_is_armed(
				fresh_host, _mechanism_source(fresh, "sump")),
		"migrated sump commits at its saved deadline and then rearms without losing receipt identity")
	await _discard(host)
	await _discard(fresh_host)


func _mechanism_source(chunk, kind: String) -> Node:
	match kind:
		"sump":
			return (chunk._sumps[0] as Dictionary).get("pump") as Node
		"silo":
			return (chunk._silos[0] as Dictionary).get("lever") as Node
		"belt":
			return (chunk._belts[0] as Dictionary).get("breaker") as Node
	return null


func _mechanism_live_consumed(chunk, kind: String) -> int:
	match kind:
		"sump":
			return int((chunk._sumps[0] as Dictionary).get("trigger_consumed", -1))
		"silo":
			return int((chunk._silos[0] as Dictionary).get("trigger_consumed", -1))
		"belt":
			return int((chunk._belts[0] as Dictionary).get("trigger_consumed", -1))
	return -1


func _saved_mechanism_consumed(record: Dictionary, kind: String) -> int:
	var collection_name := "%ss" % kind
	var collection: Array = record.get(collection_name, []) as Array
	if collection.is_empty() or not collection[0] is Dictionary:
		return -1
	return int((collection[0] as Dictionary).get("trigger_consumed", -1))


func _mechanism_is_baseline(chunk, kind: String) -> bool:
	match kind:
		"sump":
			var entry := chunk._sumps[0] as Dictionary
			return int(entry.get("state", -1)) == 1 \
				and int(entry.get("pending", -2)) == -1
		"silo":
			return str((chunk._silos[0] as Dictionary).get("phase", "")) \
				== chunk.SILO_PHASE_CLOSED
		"belt":
			return not bool((chunk._belts[0] as Dictionary).get("powered", true))
	return false


func _mechanism_has_started(chunk, kind: String) -> bool:
	match kind:
		"sump":
			return int((chunk._sumps[0] as Dictionary).get("pending", -1)) == 2
		"silo":
			return str((chunk._silos[0] as Dictionary).get("phase", "")) \
				== chunk.SILO_PHASE_OPENING
		"belt":
			return bool((chunk._belts[0] as Dictionary).get("powered", false))
	return false


func _boot() -> Dictionary:
	var host = HostScript.new()
	host.setup(true, Vector2i(20, 16))
	host.grid.set_level_count(2)
	host.register_party({"aster": Vector3(10.0, 0.0, 6.0), "peris": Vector3(15.0, 0.0, 10.0)})
	for char_id in ["aster", "peris"]:
		host.game_state.set_stat(char_id, "hp", 100.0)
	root.add_child(host)
	var chunk = FixtureScript.new()
	chunk.attach_chunk_host(host, "scene_mechanism_fixture")
	host.add_child(chunk)
	await process_frame
	await process_frame
	return {"host": host, "chunk": chunk}


func _snap_actor_to_source(host, source: Node, actor: String) -> void:
	if source == null or not is_instance_valid(source):
		return
	var data_id := str(source.get("data_id"))
	if data_id == "" or not host.game_state.has_interactable(data_id):
		return
	host.game_state.command_stop(actor)
	var position: Vector3 = host.game_state.get_interactable(data_id).get(
		"position", Vector3.INF)
	if not position.is_finite():
		return
	host.game_state.set_character_level(
		actor, host.game_state.grid.level_for_y(position.y))
	host.game_state.snap_character_to(actor, position)
	source.set("active_character", actor)


func _trigger_exact_source(host, source: Node, actor: String) -> bool:
	_snap_actor_to_source(host, source, actor)
	return bool(source.call("_trigger", false)) \
		if source != null and is_instance_valid(source) else false


func _source_trigger_count(host, source: Node) -> int:
	if source == null or not is_instance_valid(source):
		return -1
	var data_id := str(source.get("data_id"))
	if data_id == "" or not host.game_state.has_interactable(data_id):
		return -1
	return int(host.game_state.get_interactable(data_id).get("trigger_count", -1))


func _source_is_armed(host, source: Node) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	var data_id := str(source.get("data_id"))
	if data_id == "" or not host.game_state.has_interactable(data_id):
		return false
	var receipt: Dictionary = host.game_state.get_interactable(data_id)
	return bool(receipt.get("one_shot", false)) \
		and not bool(receipt.get("triggered", false)) \
		and bool(receipt.get("enabled", true)) \
		and not bool(source.get("_used")) \
		and bool(source.get("interaction_enabled"))


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
