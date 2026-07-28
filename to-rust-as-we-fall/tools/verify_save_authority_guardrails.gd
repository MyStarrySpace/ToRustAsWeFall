extends SceneTree

## Static ratchet for the two save/replay exploit families that are easiest to reintroduce:
##
## 1. a gameplay scheduler owner whose callbacks disappear on load without portable phase authority;
## 2. an authoritative consequence reached from a render-frame callback.
##
## This is deliberately a curated ledger instead of a loose substring warning. Every scheduler owner
## must be audited into one of three exact sets. Known debt passes but is printed and frozen by
## path/signature/count; a new owner or mutation fails. Removing debt also fails until the ledger is
## ratcheted down in the same change.

const SCRIPT_ROOT := "res://scripts"

const SCHEDULER_AUTHORITY_LEDGER := {
	'scripts/game/objects/drawer_stair_producer.gd': 'world_state_restore',
	"scripts/fragments/chunks/boss_showcase_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/channels_wash_intro_chunk.gd":
		"inherited_fragment_world_state_restore",
	"scripts/fragments/chunks/data_fragment_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/distract_gate_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/endo_junction_stretch_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/generated_stretch_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/inflammashunt_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/lockout_chase_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/lure_relay_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/mother_flure_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/puzzle_atom_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/refuge_run_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/stacks_fragment_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/set_piece_showcase_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/survival_range_chunk.gd": "world_state_restore",
	"scripts/fragments/chunks/wash_relay_chunk.gd": "world_state_restore",
	"scripts/fragments/fragment_preview_sequence.gd": "world_state_restore",
	"scripts/game/ai/chain_enemy.gd": "world_state_restore",
	"scripts/game/ai/enemy.gd": "world_state_restore",
	"scripts/game/ai/naturalizer.gd": "world_state_restore",
	"scripts/game/objects/channel.gd": "world_state_restore",
	"scripts/game/objects/crawl_tunnel.gd": "world_state_restore",
	"scripts/game/objects/flow_router_valve.gd": "portable_restore",
	"scripts/game/objects/flure.gd": "world_state_restore",
	"scripts/game/objects/grid_risk_field.gd": "world_state_restore",
	"scripts/game/objects/hazard_field.gd": "world_state_restore",
	"scripts/game/objects/hushbloom.gd": "world_state_restore",
	"scripts/game/objects/iron_purge_receiver.gd": "world_state_restore",
	"scripts/game/objects/infrastructure_operation.gd": "portable_restore",
	"scripts/game/objects/interactable.gd": "world_state_restore",
	"scripts/game/objects/party_gate_3d.gd": "world_state_restore",
	"scripts/game/objects/portal_pad.gd": "world_state_restore",
	"scripts/scene_chunks/scene_chunk.gd": "world_state_restore",
	"scripts/showcase/showcase_room.gd": "world_state_restore",
	"scripts/system/core/game_state.gd": "game_state_core",
	"scripts/system/simulation/atp_scarcity_clock.gd": "portable_world_state",
	"scripts/tutorial/act1_sequence.gd": "world_state_restore",
	"scripts/tutorial/aster_sim_sequence.gd": "world_state_restore",
	"scripts/tutorial/elevator_sequence.gd": "world_state_restore",
	"scripts/tutorial/leaving_facility_sequence.gd": "world_state_restore",
	"scripts/tutorial/peris_sim_sequence.gd": "world_state_restore",
	"scripts/tutorial/tag_day_sequence.gd": "world_state_restore",
}

## These files own a scheduler but not a persistable gameplay phase. Keep each exception narrow.
const SCHEDULER_NONPERSISTENT_ALLOWLIST := {
	"scripts/game/mechanics/hide_encounter_sim.gd":
		"pure deterministic analysis harness, never attached to a saved scene",
	"scripts/game/world/downed_body_manager.gd":
		"presentation synchronizer; carry/downed truth is already in GameState",
	"scripts/system/core/state_machine.gd":
		"timer-lifecycle utility; persistence is required of each gameplay owner",
	"scripts/test_runner_cli.gd":
		"test harness callbacks are intentionally scoped to one process",
}

## Exact, bounded scheduler authority debt. No globbing: a new sequence/chunk does not inherit it.
const SCHEDULER_AUTHORITY_DEBT := {
	"scripts/tutorial/tutorial_sequence.gd":
		"named fades/dialogue chains are portable; unnamed callback fallbacks remain bounded debt",
}

## These debt owners have migrated one authoritative subsystem while other scheduled narrative
## phases in the same file remain scene-local. Keep this list explicit so partial progress does not
## falsely graduate the whole owner or make the stale-debt ratchet reject the proven subsystem.
const SCHEDULER_PARTIAL_AUTHORITY_DEBT := {}

## A signature is path|render entrypoint|reachable owner function|mutation kind.
## Count is frozen so a second call in an already-known function still fails.
const FRAME_MUTATION_DEBT := {}

const FRAME_MUTATION_EXEMPTIONS := {
	"scripts/game/objects/interactable.gd|_process|_trigger|trigger_interactable": {
		"count": 1,
		"reason": "no-scheduler dwell fallback is restricted to standalone previews; production injects authority",
	},
}

const FRAME_ENTRYPOINTS := ["_process", "_physics_process", "_on_process"]

const MUTATION_PATTERNS := {
	"adjust_stat": "(^|[^A-Za-z0-9_])adjust_stat\\s*\\(",
	"game_state_set_stat":
		"(^|[^A-Za-z0-9_])(_game_state|game_state|gs|gsc)\\.set_stat\\s*\\(",
	"apply_damage_shield": "(^|[^A-Za-z0-9_])apply_damage_shield\\s*\\(",
	"take_damage": "(^|[^A-Za-z0-9_])take_damage\\s*\\(",
	"snap_character_to": "(^|[^A-Za-z0-9_])snap_character_to\\s*\\(",
	"restore_character": "(^|[^A-Za-z0-9_])restore_character\\s*\\(",
	"set_character_level": "(^|[^A-Za-z0-9_])set_character_level\\s*\\(",
	"trigger_interactable": "(^|[^A-Za-z0-9_])trigger_interactable\\s*\\(",
	"local_character_hp_write": "_character_hp\\s*\\[[^]]+\\]\\s*=",
}

var _checks := 0
var _failures := 0
var _call_regex := RegEx.new()
var _mutation_regexes: Dictionary = {}


func _init() -> void:
	_call_regex.compile("(^|[^A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	for kind in MUTATION_PATTERNS.keys():
		var regex := RegEx.new()
		regex.compile(str(MUTATION_PATTERNS[kind]))
		_mutation_regexes[kind] = regex
	call_deferred("_run")


func _run() -> void:
	var files: Array[String] = []
	_collect_scripts(SCRIPT_ROOT, files)
	files.sort()
	var source_by_path: Dictionary = {}
	var scheduler_owners: Dictionary = {}
	for resource_path in files:
		var source := FileAccess.get_file_as_string(resource_path)
		var relative := resource_path.trim_prefix("res://")
		source_by_path[relative] = source
		if _owns_scheduler(source):
			scheduler_owners[relative] = true

	_validate_ledger_disjointness()
	_validate_scheduler_owners(scheduler_owners, source_by_path)
	_validate_known_scheduler_entries(scheduler_owners, source_by_path)
	_validate_proven_partial_subsystems(source_by_path)
	_validate_generated_cadence_release_guards(source_by_path)
	_validate_frame_mutations(source_by_path)

	print("SAVE AUTHORITY GUARDRAILS: %d checks, %d failures, %d scheduler debts, %d frame debts" % [
		_checks, _failures, SCHEDULER_AUTHORITY_DEBT.size(), FRAME_MUTATION_DEBT.size()
	])
	quit(0 if _failures == 0 else 1)


func _collect_scripts(directory_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(directory_path)
	if dir == null:
		fail("cannot open script directory %s" % directory_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := directory_path.path_join(entry)
			if dir.current_is_dir():
				_collect_scripts(child, out)
			elif entry.ends_with(".gd"):
				out.append(child)
		entry = dir.get_next()
	dir.list_dir_end()


func _owns_scheduler(source: String) -> bool:
	for raw_line in source.split("\n"):
		var code := _strip_strings_and_comment(str(raw_line))
		var compact := code.replace(" ", "").replace("\t", "")
		if "schedule_after(" in compact or "schedule_at(" in compact \
				or "transition_after(" in compact or "StateMachine.new(" in compact:
			return true
	return false


func _validate_ledger_disjointness() -> void:
	var seen := {}
	for group in [SCHEDULER_AUTHORITY_LEDGER, SCHEDULER_NONPERSISTENT_ALLOWLIST,
			SCHEDULER_AUTHORITY_DEBT]:
		for path in group.keys():
			check(not seen.has(path), "scheduler ledger classifies %s exactly once" % path)
			seen[path] = true


func _validate_scheduler_owners(owners: Dictionary, sources: Dictionary) -> void:
	for path_v in owners.keys():
		var path := str(path_v)
		if SCHEDULER_AUTHORITY_LEDGER.has(path):
			_validate_authority_strategy(path, str(SCHEDULER_AUTHORITY_LEDGER[path]),
				str(sources.get(path, "")))
		elif SCHEDULER_NONPERSISTENT_ALLOWLIST.has(path):
			check(true, "narrow non-persistent scheduler exemption: %s" % path)
		elif SCHEDULER_AUTHORITY_DEBT.has(path):
			print("DEBT: %s -- %s" % [path, str(SCHEDULER_AUTHORITY_DEBT[path])])
			check(true, "bounded scheduler authority debt: %s" % path)
		else:
			fail("unclassified gameplay scheduler owner: %s; add portable authority, not a broad exemption" % path)


func _validate_known_scheduler_entries(owners: Dictionary, sources: Dictionary) -> void:
	for group in [SCHEDULER_AUTHORITY_LEDGER, SCHEDULER_NONPERSISTENT_ALLOWLIST,
			SCHEDULER_AUTHORITY_DEBT]:
		for path_v in group.keys():
			var path := str(path_v)
			check(sources.has(path), "scheduler ledger path exists: %s" % path)
			check(owners.has(path), "scheduler ledger entry still owns scheduled work: %s" % path)

	# A migrated debt should move to the audited ledger in the same change. This makes the ratchet
	# visible instead of letting an obsolete exemption linger forever.
	for path_v in SCHEDULER_AUTHORITY_DEBT.keys():
		var path := str(path_v)
		var source := str(sources.get(path, ""))
		var now_declares_authority := "func on_game_state_snapshot_restored" in source \
				and "set_world_state" in source and "get_world_state" in source
		check(not now_declares_authority or SCHEDULER_PARTIAL_AUTHORITY_DEBT.has(path),
			"remove migrated scheduler debt from the ledger: %s" % path)

	for path_v in SCHEDULER_PARTIAL_AUTHORITY_DEBT.keys():
		var path := str(path_v)
		check(SCHEDULER_AUTHORITY_DEBT.has(path),
			"partial scheduler authority remains classified as debt: %s" % path)
		var source := str(sources.get(path, ""))
		check("func on_game_state_snapshot_restored" in source
				and "set_world_state" in source and "get_world_state" in source,
			"partial scheduler authority still publishes and restores portable state: %s" % path)


func _validate_proven_partial_subsystems(sources: Dictionary) -> void:
	var tutorial_source := str(sources.get("scripts/tutorial/tutorial_sequence.gd", ""))
	var dialogue_source := str(sources.get("scripts/ui/dialogue_box.gd", ""))
	var peris_source := str(sources.get("scripts/tutorial/peris_sim_sequence.gd", ""))
	check("PORTABLE_CONTINUATION_VERSION" in tutorial_source
			and "\"portable_continuation\"" in tutorial_source
			and "func _restore_portable_continuation" in tutorial_source
			and "func _arm_portable_method_continuation" in tutorial_source,
		"TutorialSequence saves and re-arms named continuation methods from absolute deadlines")
	check("\"ui_scheduler\"" in tutorial_source
			and "func snapshot_state" in dialogue_source
			and "func restore_state" in dialogue_source,
		"Tutorial dialogue preserves its UI clock and exact active page across a fresh load")
	check(FileAccess.file_exists(
			"res://tools/verify_tutorial_continuation_authority.gd"),
		"Tutorial continuation authority keeps its focused fade/dialogue verifier")
	check("func(" not in peris_source
			and "_show_exploration_highlight_hint" in peris_source
			and "_on_strike_warning_interacted" in peris_source,
		"Peris Sim uses named reconstructible phase endpoints and named presentation observers")
	check("WATERING_AUTHORITY_VERSION := 2" in peris_source
			and "func _configure_watering_source" in peris_source
			and "func _validate_watering_source_trigger" in peris_source
			and "func _watering_source_receipt" in peris_source
			and "source_committed_counts" in peris_source,
		"Peris Sim pickup and watering consequences consume exact physical source/body receipts")
	check(FileAccess.file_exists(
			"res://tools/verify_peris_watering_authority.gd"),
		"Peris Sim keeps canonical-can, midpoint, exact-source, and accepted-seam coverage")
	var elevator_source := str(sources.get("scripts/tutorial/elevator_sequence.gd", ""))
	check("BRIDGE_COLLAPSE_PHASE_ARMED" in elevator_source
			and "BRIDGE_COLLAPSE_PHASE_FALLING" in elevator_source
			and "BRIDGE_COLLAPSE_PHASE_LANDED" in elevator_source,
		"Elevator bridge collapse preserves explicit saved phase authority")
	check("command_external_traversal" in elevator_source
			and "_commit_bridge_collapse_topology" in elevator_source,
		"Elevator riders are authoritative before endpoint-only bridge topology commits")
	check(FileAccess.file_exists(
			"res://tools/verify_elevator_bridge_collapse_save_authority.gd"),
		"Elevator bridge collapse keeps its focused midpoint/deadline verifier")
	var elevator_functions := _parse_functions(elevator_source)
	var junction_rest_commit := _function_code(
		elevator_functions, "_complete_junction_rest_commit")
	check("JUNCTION_REST_AUTHORITY_KEY" in elevator_source
			and "JUNCTION_SHELTER_HALF_SIZE" in elevator_source
			and "add_shelter_region" in elevator_source
			and "remove_item(water_item_id)" in junction_rest_commit
			and "command_party_rest(JUNCTION_REST_PARTY)" in junction_rest_commit
			and "_game_state.unregister_character(guard_id)" in elevator_source,
		"Elevator Junction night requires exact shelter/roster/water authority and one party batch")
	check(FileAccess.file_exists(
			"res://tools/verify_elevator_junction_rest_authority.gd"),
		"Elevator Junction rest keeps focused signal-time and same/fresh midpoint coverage")
	_validate_elevator_route_flure_authority(sources)
	_validate_elevator_gauntlet_authority(sources)
	_validate_lockout_tyreg_authority(sources)
	_validate_act1_stacks_authority(sources)
	_validate_act1_rings_authority(sources)
	var leaving_source := str(sources.get("scripts/tutorial/leaving_facility_sequence.gd", ""))
	check("SECTOR_GATE_CONTEXT_CONTRACT" in leaving_source
			and ".begin_open(context)" in leaving_source,
		"Leaving Facility route seals publish versioned causal context with their gate phase")
	check("func _restore_sector_gate_progression" in leaving_source
			and "restore_closed_baseline" in leaving_source
			and "phase == PartyGate3D.PHASE_OPEN" in leaving_source,
		"Leaving Facility validates ordered gate history and derives physical clearance from OPEN")
	var leaving_functions := _parse_functions(leaving_source)
	var shelter_rest := _function_code(leaving_functions, "_start_first_rest")
	var endo_join := _function_code(leaving_functions, "_commit_endo_join")
	check("SHELTER_REST_AUTHORITY_CONTRACT" in leaving_source
			and "required_members = PackedStringArray(PARTY_IDS)" in leaving_source
			and "command_party_rest(PARTY_IDS)" in leaving_source
			and "command_rest(\"aster\")" not in leaving_source
			and "_party_inside_authored_shelter" in shelter_rest,
		"Leaving Facility Shelter 1 requires the fixed full trio and one canonical party-rest batch")
	check(endo_join.find("_prepare_endo_join_body()") >= 0
			and endo_join.find("_prepare_endo_join_body()")
				< endo_join.find("_publish_endo_join_authority(saved)"),
		"Leaving Facility installs Endo's body and party authority before publishing JOINED")
	check(FileAccess.file_exists(
			"res://tools/verify_leaving_facility_shelter_authority.gd")
			and FileAccess.file_exists(
				"res://tools/verify_leaving_facility_endo_join_authority.gd"),
		"Leaving Facility keeps focused signal-time shelter and join authority verifiers")
	var game_state_source := str(sources.get("scripts/system/core/game_state.gd", ""))
	check("func can_party_rest(char_ids: Array) -> bool" in game_state_source
			and "func command_party_rest(char_ids: Array) -> bool" in game_state_source
			and "GameEvent.KIND_PARTY_REST" in game_state_source,
		"GameState exposes a preflighted replayable atomic party-rest command")
	var interactable_source := str(sources.get(
		"scripts/game/objects/interactable.gd", ""))
	check("INTERACTABLE_TYPE_TIMED_ACTION := 2" in game_state_source
			and "\"interactable_type\": interaction_type" in game_state_source
			and "\"interactable_type\": norm.interactable_type" in game_state_source
			and "spec.get(\"interactable_type\", legacy_type)" in interactable_source,
		"Interactable registration, snapshots, replay, and presenters preserve all three activation types")
	var interactable_factory_source := str(sources.get(
		"scripts/game/objects/interactable_factory.gd", ""))
	check("node.dwell_time =" in interactable_factory_source
			and "node.interaction_radius =" in interactable_factory_source
			and "node.one_shot =" in interactable_factory_source
			and "node.interactable_type =" in interactable_factory_source
			and "if merged.has(\"interactable_type\")" in interactable_factory_source,
		"InteractableFactory preserves authored grammar before optional GameState binding")
	var scene_chunk_source := str(sources.get("scripts/scene_chunks/scene_chunk.gd", ""))
	check("required_members: Array" in scene_chunk_source
			and "func _preflight_authored_party_rest" in scene_chunk_source
			and "command_party_rest(outcome[\"members\"] as Array)" in scene_chunk_source
			and "command_rest(str(rest.active_character))" not in scene_chunk_source,
		"SceneChunk shelters require an explicit authored roster and one atomic party-rest command")
	check(FileAccess.file_exists(
			"res://tools/verify_scene_chunk_party_rest_authority.gd"),
		"SceneChunk shelter presence/consciousness and no-prefix-payment rules keep focused coverage")
	var scene_mechanism_verifier := FileAccess.get_file_as_string(
		"res://tools/verify_scene_chunk_mechanism_save_authority.gd")
	check("SCENE_MECHANISM_AUTHORITY_VERSION := 3" in scene_chunk_source
			and "func _configure_scene_mechanism_control" in scene_chunk_source
			and "func _scene_mechanism_control_receipt_pending" in scene_chunk_source
			and "func _reconcile_scene_mechanism_control_receipts" in scene_chunk_source
			and "\"trigger_consumed\"" in scene_chunk_source,
		"SceneChunk sump, silo, and belt consequences require exact monotonic source/body receipts")
	check("direct helper cannot manufacture" in scene_mechanism_verifier
			and "manually emitted signal cannot manufacture" in scene_mechanism_verifier
			and "accepted-before-owner save has one source edge but no free" \
				in scene_mechanism_verifier
			and "v2 mechanism save migrates exact registry counts into v3" \
				in scene_mechanism_verifier,
		"SceneChunk mechanisms keep direct, signal-time, same/fresh, and v2 migration coverage")
	var stacks_source := str(sources.get(
		"scripts/fragments/chunks/stacks_fragment_chunk.gd", ""))
	var stacks_functions := _parse_functions(stacks_source)
	var legacy_bank_trigger := _function_code(stacks_functions, "trigger_stacks_bank")
	var legacy_shelter_trigger := _function_code(
		stacks_functions, "trigger_stacks_shelter_rest")
	check("STACKS_AUTHORITY_VERSION := 3" in stacks_source
			and "_shelter_phase = \"committing\"" in stacks_source
			and "gs.command_party_rest(STACKS_PARTY_IDS)" in stacks_source
			and "_authored_party_rest_effect_matches" in stacks_source,
		"Stacks completion is a saved exact-trio party-rest transaction, never an interaction boolean")
	check("return false" in legacy_bank_trigger
			and "_on_bank_interacted" not in legacy_bank_trigger
			and "return false" in legacy_shelter_trigger
			and "_on_shelter_interacted" not in legacy_shelter_trigger,
		"Stacks legacy automation helpers remain inert instead of calling story callbacks")
	check("func get_playthrough_interaction_target" in stacks_source
			and "set_pre_trigger_validator(" in stacks_source
			and "_semantic_trigger_receipt_is_pending" in stacks_source
			and "_actor_can_interact_here" in stacks_source,
		"Stacks evidence and rest enter through source-valid physical world interactions")
	var rings_source := str(sources.get(
		"scripts/fragments/chunks/rings_fragment_chunk.gd", ""))
	var rings_functions := _parse_functions(rings_source)
	var legacy_rings_trigger := _function_code(
		rings_functions, "trigger_rings_reassignment_beat")
	check("RINGS_AUTHORITY_VERSION := 3" in rings_source
			and "reassignment_actor" in rings_source
			and "reassignment_commit_tick" in rings_source
			and "reassignment_positions" in rings_source
			and "optional_read_consumed_counts" in rings_source,
		"Rings saves the physical reassignment evidence that precedes Endo's departure")
	check("return false" in legacy_rings_trigger
			and "_on_marco_interacted" not in legacy_rings_trigger
			and "func get_playthrough_interaction_target" in rings_source
			and "set_pre_trigger_validator(_validate_marco_reassignment_trigger)" in rings_source
			and "_marco_semantic_trigger_pending" in rings_source,
		"Rings can advance only through the source-valid physical Marco interaction")
	check("func _validate_optional_read_trigger" in rings_source
			and "func _optional_read_actor_ready_at_source" in rings_source
			and "func _optional_read_source_receipt_count" in rings_source
			and "func _reconcile_accepted_optional_read_source_receipts" in rings_source,
		"Rings optional memories each require their exact Peris source/body receipt")
	var rings_verifier := FileAccess.get_file_as_string(
		"res://tools/verify_rings_departure_save_authority.gd")
	check("source-less and wrong-source Client Bloom callbacks are inert" in rings_verifier
			and "same-presenter restore burns but does not grant" in rings_verifier
			and "fresh presenter reconciles the same accepted edge" in rings_verifier
			and "optional memory neither completes nor gates the Marco route" in rings_verifier,
		"Rings keeps direct, same/fresh receipt-seam, and non-gating optional-read coverage")
	var refuge_source := str(sources.get(
		"scripts/fragments/chunks/refuge_run_chunk.gd", ""))
	var refuge_functions := _parse_functions(refuge_source)
	var refuge_legacy_inert := "return false" in _function_code(
		refuge_functions, "choose_route") \
		and "return false" in _function_code(refuge_functions, "activate_slit_lure")
	check("REFUGE_AUTHORITY_VERSION := 4" in refuge_source
			and "_build_refuge_shelter" in refuge_source
			and "func _evaluate_route_body_receipts" in refuge_source
			and "func _spatial_authority_tick" in refuge_source
			and "next_spatial_authority_tick" in refuge_source
			and refuge_legacy_inert
			and "_slit_flure_receipt_pending" in refuge_source
			and "_spot_sweep_receipt_pending" in refuge_source
			and "_exit_shelter_receipt_pending" in refuge_source
			and "_interaction_actor_ready_at" in refuge_source
			and "_exit_rest_phase = \"committing\"" in refuge_source
			and "gs.command_party_rest(PARTY_IDS)" in refuge_source
			and "_authored_party_rest_effect_matches" in refuge_source,
		"Refuge Run owns body-crossed route truth, exact world-source receipts, and a saved exact-trio exit-rest transaction")
	check(FileAccess.file_exists("res://tools/verify_stacks_fragment_save_authority.gd")
			and "paid shelter signal seam" in FileAccess.get_file_as_string(
				"res://tools/verify_stacks_fragment_save_authority.gd")
			and FileAccess.file_exists("res://tools/verify_refuge_run_system_authority.gd")
			and "paid exit-rest signal seam" in FileAccess.get_file_as_string(
				"res://tools/verify_refuge_run_system_authority.gd"),
		"Stacks and Refuge keep same/fresh signal-time duplicate-charge regressions")
	check("legacy actor=script route has no body provenance" in \
			FileAccess.get_file_as_string(
				"res://tools/verify_refuge_run_system_authority.gd")
			and "headless presentation cannot turn a body position into route history" in \
			FileAccess.get_file_as_string(
				"res://tools/verify_refuge_run_system_authority.gd"),
		"Refuge Run keeps route-provenance and scheduler-vs-presentation exploit coverage")
	var wash_intro_source := str(sources.get(
		"scripts/fragments/chunks/channels_wash_intro_chunk.gd", ""))
	check("not _all_hunters_physically_drowned()" in wash_intro_source
			and "_hunter_has_physical_wash_result(char_id)" in wash_intro_source
			and "func _hunter_has_dead_authority" in wash_intro_source
			and "\"runtime:enemy:%s\"" in wash_intro_source
			and "absf(body_position.z) >= ENEMY_WASH_EDGE_Z" in wash_intro_source,
		"Wash Intro drown provenance cannot replace dead bodies at the physical endpoint")
	var party_gate_source := str(sources.get("scripts/game/objects/party_gate_3d.gd", ""))
	check("func begin_open(context: Dictionary = {})" in party_gate_source
			and "\"context\": saved_context" in party_gate_source,
		"PartyGate3D carries host context unchanged from OPENING into OPEN")
	var inflammashunt_source := str(sources.get("scripts/fragments/chunks/inflammashunt_chunk.gd", ""))
	check("_spawn_item(\"gas_sac\"" in inflammashunt_source
			and "func _sac_holder()" in inflammashunt_source
			and "gs.items[_sac_item_id]" in inflammashunt_source,
		"Inflammashunt gas-sac authority comes from a canonical GameState item and holder")
	check("_attach_sac_visual" not in inflammashunt_source
			and "gas_sac_state = \"carried\"" not in inflammashunt_source,
		"Inflammashunt cannot regress to a bespoke carrier string or hand-attached proxy")
	var boss_source := str(sources.get("scripts/fragments/chunks/boss_showcase_chunk.gd", ""))
	check("BOSS_AUTHORITY_VERSION := 3" in boss_source
			and "PRIZE_PHASE_CLAIMING" in boss_source
			and "_spawn_item(PRIZE_ITEM_TYPE" in boss_source
			and "_pick_up_item(actor, _prize_item_id)" in boss_source
			and "_reconcile_restored_prize_transaction" in boss_source,
		"Boss cache reward is one canonical item with a reconciled pickup transaction")
	check("_validate_survey_trigger.bind(_survey_interactable)" in boss_source
			and "_validate_winch_trigger.bind(_winch_interactable)" in boss_source
			and "_validate_brake_trigger.bind(_brake_ia)" in boss_source
			and "func _boss_consumed_source_receipt" in boss_source,
		"Boss survey, winch, and brake require their own exact physical control receipts")
	check("\"survey_trigger_consumed\": _survey_trigger_consumed" in boss_source
			and "\"winch_trigger_consumed\": _winch_trigger_consumed" in boss_source
			and "\"brake_trigger_consumed\": _brake_trigger_consumed" in boss_source
			and "\"brake_transaction\": _brake_transaction.duplicate(true)" in boss_source,
		"Boss v3 persists monotonic control receipts and the reserved brake consequence")
	var set_piece_source := str(sources.get(
		"scripts/fragments/chunks/set_piece_showcase_chunk.gd", ""))
	check("SET_PIECE_AUTHORITY_VERSION := 5" in set_piece_source
			and "_validate_set_piece_control_trigger.bind(action_id, control)" in set_piece_source
			and "func _set_piece_consumed_source_receipt" in set_piece_source,
		"Set-piece mechanisms consume the exact source/body receipt instead of public callbacks")
	check("var _prize_retrieved" not in boss_source
			and "_verify_boss_prize_authority" in FileAccess.get_file_as_string(
				"res://tools/verify_set_piece_save_authority.gd"),
		"Boss cache cannot regress to a solved boolean and keeps focused seam coverage")
	var cadence_source := str(sources.get("scripts/system/core/fixed_cadence.gd", ""))
	var channel_source := str(sources.get("scripts/game/objects/channel.gd", ""))
	var data_source := str(sources.get(
		"scripts/fragments/chunks/data_fragment_chunk.gd", ""))
	var preview_source := str(sources.get(
		"scripts/fragments/fragment_preview_sequence.gd", ""))
	check("static func next_strict_tick" in cadence_source
			and "deadline <= now + epsilon" in cadence_source
			and "FixedCadenceScript.next_strict_tick" in channel_source
			and "FixedCadenceScript.next_strict_tick" in data_source
			and "FixedCadenceScript.next_strict_tick" in preview_source
			and "FixedCadenceScript.next_strict_tick" in boss_source,
		"recurring gameplay cadences share a strictly-future boundary calculation")
	check("const FixedCadenceScript" not in boss_source,
		"Boss Showcase inherits one cadence helper instead of shadowing its base contract")
	var data_functions := _parse_functions(data_source)
	var weak_wall_callback := _function_code(data_functions, "_on_weak_wall_pried")
	var data_exit_callback := _function_code(data_functions, "_on_exit_shelter_rested")
	check("DATA_FRAGMENT_AUTHORITY_VERSION := 4" in data_source
			and "set_pre_trigger_validator(_validate_weak_wall_trigger.bind(idx, ia))" in data_source
			and "func _weak_wall_actor_ready_at_source" in data_source
			and "func _weak_wall_source_receipt_pending" in data_source
			and "trigger_consumed" in data_source
			and "_weak_wall_source_receipt_pending(idx, source)" in weak_wall_callback,
		"Data Fragment weak walls require their exact nearby body/source receipt and save its monotonic count")
	check("set_pre_trigger_validator(_validate_exit_shelter_trigger.bind(it))" in data_source
			and "func _exit_shelter_source_receipt_pending" in data_source
			and "exit_rest_trigger_consumed" in data_source
			and "_exit_shelter_source_receipt_pending(it)" in data_exit_callback,
		"Data Fragment exit rest requires its exact nearby source/body receipt before atomic party rest")
	var chunk_cadence_verifier := FileAccess.get_file_as_string(
		"res://tools/verify_chunk_cadence_authority.gd")
	check("source-less weak-wall helper cannot manufacture a pry receipt" in chunk_cadence_verifier
			and "signal-time fixture captures accepted weak-wall source" in chunk_cadence_verifier
			and "fresh presenter repeatedly retracts accepted pre-owner pry" in chunk_cadence_verifier,
		"Data Fragment keeps direct, signal-time, same-presenter, and fresh-presenter weak-wall exploit coverage")
	var data_shelter_verifier := FileAccess.get_file_as_string(
		"res://tools/verify_data_fragment_shelter_authority.gd")
	check("direct shelter callback cannot substitute for a new physical source receipt" in data_shelter_verifier
			and "accepted-before-owner shelter save contains no free rest consequence" in data_shelter_verifier
			and "fresh presenter retracts accepted pre-owner shelter edge" in data_shelter_verifier,
		"Data Fragment exit keeps direct, accepted-trigger, same, and fresh exploit coverage")
	var data_concealment_verifier := FileAccess.get_file_as_string(
		"res://tools/verify_data_fragment_concealment_authority.gd")
	check("CONCEALMENT_TICK := 0.1" in data_source
			and "func _on_concealment_tick" in data_source
			and "_update_shared_concealment()" not in _function_code(
				data_functions, "_update")
			and "render and headless presenter calls cannot grant Capbage concealment" \
				in data_concealment_verifier
			and "fresh restore reaches the same concealment consequence" \
				in data_concealment_verifier,
		"Data Fragment cover truth runs only on its saved fixed cadence with same/fresh coverage")
	var infrastructure_source := str(sources.get(
		"scripts/game/objects/infrastructure_operation.gd", ""))
	var infrastructure_functions := _parse_functions(infrastructure_source)
	var infrastructure_route := _function_code(
		infrastructure_functions, "route_service")
	var infrastructure_complete := _function_code(
		infrastructure_functions, "complete_operation")
	check("return false" in infrastructure_route
			and "_accept_source_receipt" not in infrastructure_route
			and "return false" in infrastructure_complete
			and "_accept_receiver_receipt" not in infrastructure_complete,
		"Infrastructure compatibility verbs remain inert")
	check("PHASE_IN_TRANSIT" in infrastructure_source
			and "PHASE_ARRIVED" in infrastructure_source
			and "source_actor_id" in infrastructure_source
			and "receiver_actor_id" in infrastructure_source
			and "arrival_tick" in infrastructure_source
			and "_consumed_interactable_receipt" in infrastructure_source
			and "_on_service_arrived" in infrastructure_source,
		"Infrastructure service owns exact endpoint receipts and a saved physical transit")
	check(FileAccess.file_exists(
			"res://tools/verify_infrastructure_operation_save_authority.gd")
			and FileAccess.file_exists("res://tools/verify_infrastructure_catalog.gd"),
		"Infrastructure keeps midpoint, fresh-restore, and catalog realization coverage")
	var branch_span_source := str(sources.get(
		"scripts/game/objects/branch_span_producer.gd", ""))
	var branch_span_functions := _parse_functions(branch_span_source)
	var branch_span_legacy := _function_code(branch_span_functions, "activate")
	check("return false" in branch_span_legacy
			and "_commit_activation" not in branch_span_legacy
			and "func _producer_receipt_pending" in branch_span_source
			and "set_pre_trigger_validator(_validate_producer_trigger)" in branch_span_source
			and "func on_game_state_snapshot_restored" in branch_span_source,
		"Branch span requires its exact terminal receipt and cannot regress to an actor-id helper")
	check(FileAccess.file_exists("res://tools/verify_branch_span_producer.gd")
			and "public actor-id helper cannot forge a physical producer receipt" in \
				FileAccess.get_file_as_string(
					"res://tools/verify_branch_span_producer.gd"),
		"Branch span keeps physical-source and portable midpoint exploit coverage")
	var flora_garden_source := str(sources.get(
		"scripts/fragments/chunks/flora_garden_chunk.gd", ""))
	check("GARDEN_AUTHORITY_VERSION := 3" in flora_garden_source
			and "func _configure_garden_source" in flora_garden_source
			and "func _garden_actor_ready_at_source" in flora_garden_source
			and "func _garden_source_receipt_count" in flora_garden_source
			and "source_committed_counts" in flora_garden_source,
		"Flora Garden crate, planting, and tending consume exact Peris source/body receipts")
	var flora_garden_verifier := FileAccess.get_file_as_string(
		"res://tools/verify_flora_garden_save_authority.gd")
	check("accepted-before-callback crate save contains no free seed consequence" in flora_garden_verifier
			and "accepted-before-callback planting save has not begun a fake growth transaction" in flora_garden_verifier
			and "accepted-before-callback tend save contains no free daily care" in flora_garden_verifier
			and "fresh presenter also requires a new physical crate receipt" in flora_garden_verifier,
		"Flora Garden keeps exact-source and same/fresh accepted-seam exploit coverage")
	var wash_source := str(sources.get(
		"scripts/fragments/chunks/wash_relay_chunk.gd", ""))
	check("WASH_AUTHORITY_VERSION := 8" in wash_source
			and "SPATIAL_AUTHORITY_INTERVAL" in wash_source
			and "next_spatial_authority_tick" in wash_source
			and "func _spatial_authority_tick" in wash_source
			and "func _sample_held_control_truth" in wash_source
			and "func _configure_wash_control" in wash_source
			and "func _validate_wash_control_trigger" in wash_source
			and "func _valid_v7_wash_cadence" in wash_source
			and "func _valid_current_carries_raw" in wash_source
			and "func _valid_enemy_drown_mirrors" in wash_source
			and "var bait := Flure.new()" in wash_source
			and "var flure := Flure.new()" in wash_source
			and "channel.request_sweep_body(id, \"enemy\")" in wash_source
			and "_wash_control_committed_counts" in wash_source,
		"Wash Relay owns exact controls, reusable Flures/Channels, held truth, in-flight carries, concealment, retry, and exit on saved authority")
	check(FileAccess.file_exists("res://tools/verify_wash_spatial_authority.gd")
			and FileAccess.file_exists(
				"res://tools/verify_wash_control_receipt_authority.gd")
			and FileAccess.file_exists(
				"res://tools/verify_wash_cadence_save_validation.gd"),
		"Wash Relay keeps cadence, malformed-save, and exact-source accepted-seam coverage")
	var survival_source := str(sources.get(
		"scripts/fragments/chunks/survival_range_chunk.gd", ""))
	var survival_functions := _parse_functions(survival_source)
	var survival_source_bound := true
	for verb in [
		"depart_range", "survey_route", "activate_range_lure", "tune_echo_coupler",
		"cross_seam", "commit_hide", "reset_after_failure", "rest_at_east_shelter",
	]:
		survival_source_bound = survival_source_bound \
			and "_range_control_receipt_pending" in _function_code(
				survival_functions, verb)
	check(survival_source_bound
			and "func _configure_range_control" in survival_source
			and "func _validate_range_control_trigger" in survival_source
			and "func _range_interaction_actor_ready_at" in survival_source
			and "_require_station" not in survival_source,
		"Survival Range consequences require exact source receipts, canonical body proximity, and no selected-portrait station helper")
	check(FileAccess.file_exists("res://tools/verify_survival_range_save_authority.gd")
			and "public range verbs cannot forge a physical control receipt" in \
				FileAccess.get_file_as_string(
					"res://tools/verify_survival_range_save_authority.gd"),
		"Survival Range keeps direct-helper exploit coverage")
	var mother_source := str(sources.get("scripts/fragments/chunks/mother_flure_chunk.gd", ""))
	var mother_functions := _parse_functions(mother_source)
	var mother_legacy_inert := true
	for verb in [
		"activate_terminal", "use_portal", "activate_fragment_move", "clear_collapse",
		"harvest_body", "pick_up_gear", "install_gear_at", "tend_mother",
	]:
		var legacy_code := _function_code(mother_functions, verb)
		mother_legacy_inert = mother_legacy_inert and "return false" in legacy_code
	check(mother_legacy_inert
			and "_mother_consumed_source_receipt" in mother_source
			and "_mother_interaction_actor_ready_at" in mother_source,
		"Mother Flure rejects helper substitution and requires exact physical source receipts")
	check("PORTAL_TRANSIT_OUTBOUND" in mother_source
			and "PORTAL_TRANSIT_RETURNING" in mother_source
			and "command_external_traversal" in mother_source
			and "_reconcile_restored_portal_transit" in mother_source,
		"Mother Flure portal crossing is a portable locked traversal with transaction reconciliation")
	check("_set_character_position(\"peris\"" not in mother_source,
		"Mother Flure cannot regress its service portal to an endpoint snap")
	check("MOTHER_AUTHORITY_VERSION := 5" in mother_source
			and "hazard_next_tick" in mother_source
			and "func _on_root_hazard_tick" in mother_source
			and "_update_lane_hazards" not in mother_source,
		"Mother root damage owns one saved fixed scheduler cadence, never render sampling")
	check("body_source_item_ids" in mother_source
			and "BODY_CLAIMING" in mother_source
			and "_pick_up_item(actor, item_id)" in mother_source
			and "_spawn_item(\"lysate\"" in mother_source
			and "spawn_item(\"lysate\", _get_character_position(\"endo\")" not in mother_source,
		"Mother corpses expose finite source-tagged items instead of minting rewards on click")
	var mother_test_source := FileAccess.get_file_as_string(
		"res://tools/verify_mother_flure_save_authority.gd") \
		if FileAccess.file_exists("res://tools/verify_mother_flure_save_authority.gd") else ""
	check("_verify_portal_transit_authority" in mother_test_source
			and "_verify_root_hazard_cadence_authority" in mother_test_source
			and "coarse and fine scheduler partitions" in mother_test_source
			and FileAccess.file_exists(
				"res://tools/verify_mother_flure_body_source_authority.gd"),
		"Mother Flure keeps focused portal, cadence, and exact-source exploit coverage")
	var portal_source := str(sources.get("scripts/game/objects/portal_pad.gd", ""))
	check("portal_pad/v2" in portal_source
			and "HOP_PHASE_RESERVED" in portal_source
			and "func _resume_reserved_hop" in portal_source
			and "func _reserved_hop_is_physically_applied" in portal_source,
		"PortalPad reserves and reconciles every group hop across pre/post-snap save seams")
	check(FileAccess.file_exists("res://tools/verify_portal_pad_authority.gd")
			and "post-snap/pre-finalize" in FileAccess.get_file_as_string(
				"res://tools/verify_portal_pad_authority.gd"),
		"PortalPad keeps focused signal-time duplicate-hop coverage")
	var hush_source := str(sources.get("scripts/game/objects/hushbloom.gd", ""))
	var lockout_source := str(sources.get("scripts/fragments/chunks/lockout_chase_chunk.gd", ""))
	check("hushbloom/v2" in hush_source
			and "PHASE_PICKING" in hush_source
			and "spawn_item(\"hushbloom\"" in hush_source
			and "pick_up_item(actor, item_id)" in hush_source
			and "func _finalize_restored_pick" in hush_source,
		"Hushbloom picking owns a source-tagged canonical item transaction")
	check("FixedCadenceScript.next_strict_tick" in hush_source,
		"Hushbloom proximity polling always rearms at a strictly future boundary")
	check("var _bloom_carry" not in lockout_source
			and "get_hand_items(character_id)" in lockout_source
			and "remove_item(item_id)" in lockout_source,
		"Lockout portal seals consume the interacting body's real hand item, never a chunk counter")
	check("_validate_lockout_control_trigger.bind(\"scanner\", _boundary_scanner)" in lockout_source
			and "_validate_lockout_control_trigger.bind(\"door\", _service_door)" in lockout_source
			and "func _lockout_actor_ready_at_source" in lockout_source
			and "func _lockout_control_receipt_pending" in lockout_source,
		"Lockout scanner and service door require their exact source receipt and nearby ready body")
	check("SEAL_TX_RESERVED" in lockout_source
			and "SEAL_TX_ITEM_REMOVED" in lockout_source
			and "source_trigger_count" in lockout_source
			and "stun_deadline" in lockout_source
			and "_validate_seal_interaction.bind(seal, pad)" in lockout_source,
		"Lockout portal sealing reserves one source, exact held item, target pad, and deadline")
	check("\"scanner_trigger_consumed\": _scanner_trigger_consumed" in lockout_source
			and "\"door_trigger_consumed\": _door_trigger_consumed" in lockout_source
			and "\"seal_trigger_consumed\": _portable_chase_int_map" in lockout_source
			and "\"seal_transaction\": _seal_transaction.duplicate(true)" in lockout_source,
		"Lockout v5 persists monotonic control receipts and the in-flight seal spend")
	check(FileAccess.file_exists("res://tools/verify_flora_effect_authority.gd")
			and FileAccess.file_exists("res://tools/verify_lockout_chase_save_authority.gd"),
		"Hushbloom inventory and Lockout consumption keep focused save-exploit verifiers")
	var aster_source := str(sources.get("scripts/tutorial/aster_sim_sequence.gd", ""))
	check("DRINK_AUTHORITY_VERSION := 2" in aster_source
			and "SEQUENCE_AUTHORITY_VERSION := 2" in aster_source
			and "func _configure_aster_interaction_source" in aster_source
			and "func _validate_aster_source_trigger" in aster_source
			and "func _aster_source_receipt" in aster_source
			and "source_trigger_count" in aster_source
			and "DRINK_AUTHORITY_KEY" in aster_source
			and "spawn_preview_item(\"lysate\"" in aster_source
			and "endocytose_preview_item(\"aster\"" in aster_source
			and "func on_game_state_snapshot_restored" in aster_source,
		"Aster's terminal and drink consume exact Aster source receipts; drink owns one canonical item action")
	check("_game_state.set_stat(\"aster\", \"atp\"" not in aster_source,
		"Aster's drink machine cannot regress to a direct ATP grant")
	check(FileAccess.file_exists("res://tools/verify_aster_drink_authority.gd")
			and FileAccess.file_exists(
				"res://tools/verify_aster_sim_sequence_authority.gd"),
		"Aster Sim keeps exact-source, accepted-seam, midpoint, and fresh-restore coverage")
	var tag_day_source := str(sources.get("scripts/tutorial/tag_day_sequence.gd", ""))
	check("func _maybe_begin_corridor_walk" in tag_day_source
			and "schedule_after(5.0, _begin_corridor_walk" not in tag_day_source,
		"Tag Day's escort handoff is caused by physical formation arrival")
	check("_citizen.global_position =" not in tag_day_source
			and "_naturalizer_1.global_position =" not in tag_day_source
			and "_naturalizer_2.global_position =" not in tag_day_source,
		"Tag Day's corridor handoff cannot regress to render-node formation snaps")
	check(FileAccess.file_exists("res://tools/verify_tag_day_grip_authority.gd"),
		"Tag Day keeps its focused formation midpoint/save-authority verifier")
	check("ESCORT_AUTHORITY_KEY" in tag_day_source
			and "accepted_movement_ops" in tag_day_source
			and "func _try_finish_corridor_escort" in tag_day_source
			and "presentation_complete" in tag_day_source,
		"Tag Day's corridor uses saved movement receipts and a two-latch join")
	check("CALLBACK_AUTHORITY_KEY" in tag_day_source
			and "CALLBACK_PHASE_WHIMPER" in tag_day_source
			and "CALLBACK_PHASE_LOCKDOWN" in tag_day_source
			and "CALLBACK_PHASE_ASTER_SCAN" in tag_day_source
			and "CALLBACK_PHASE_CLEARANCE" in tag_day_source,
		"Tag Day's post-escort callbacks retain explicit saved phases")
	check(FileAccess.file_exists("res://tools/verify_tag_day_escort_callback_authority.gd"),
		"Tag Day keeps its focused escort/callback save-authority verifier")
	var distract_source := str(sources.get("scripts/fragments/chunks/distract_gate_chunk.gd", ""))
	var relay_source := str(sources.get("scripts/fragments/chunks/lure_relay_chunk.gd", ""))
	var distract_functions := _parse_functions(distract_source)
	var relay_functions := _parse_functions(relay_source)
	check("func _full_conscious_party_beyond_exit" in distract_source
			and "_full_conscious_party_beyond_exit(gs)" in distract_source,
		"Watched Gap completion requires the whole conscious party")
	check("func _win_poll_tick" in relay_source
			and "func _full_conscious_party_beyond_exit" in relay_source
			and "_get_active_character()).x >= EXIT_X" not in relay_source,
		"Flure Relay uses saved fixed-cadence whole-party completion, not selected-portrait frames")
	var teaching_verifier := FileAccess.get_file_as_string(
		"res://tools/verify_remaining_chunk_save_authority.gd")
	check("DISTRACT_GATE_AUTHORITY_VERSION := 2" in distract_source
			and "return false" in _function_code(distract_functions, "activate_flure")
			and "source_trigger_count" in distract_source
			and "source_actor" in distract_source
			and "_accepted_flure_trigger_count" in distract_source,
		"Watched Gap accepts only a newer exact physical Peris/Flure source receipt")
	check("LURE_RELAY_AUTHORITY_VERSION := 3" in relay_source
			and "return false" in _function_code(relay_functions, "activate_lure1")
			and "return false" in _function_code(relay_functions, "activate_lure2")
			and "source_trigger_count" in relay_source
			and "_accepted_trigger_count_for" in relay_source,
		"Flure Relay accepts only newer exact physical source receipts")
	check("former direct helper cannot manufacture a song" in teaching_verifier
			and "forged Relay signal without a physical source receipt is inert" \
				in teaching_verifier
			and "forged Watched Gap signal without a physical source receipt is inert" \
				in teaching_verifier
			and "starts from its exact physical Flure" in teaching_verifier,
		"Flure teaching atoms keep direct-helper, forged-signal, and physical-source coverage")
	var atom_source := str(sources.get("scripts/fragments/chunks/puzzle_atom_chunk.gd", ""))
	var atom_functions := _parse_functions(atom_source)
	var atom_process := _function_code(atom_functions, "_process")
	var atom_headless := _function_code(atom_functions, "headless_process")
	var atom_poll := _function_code(atom_functions, "_win_poll_tick")
	check("_update_stage_progress" not in atom_process
			and "_update_stage_progress" not in atom_headless
			and "_update_stage_progress" in atom_poll
			and "win_poll_next_tick" in atom_source,
		"Puzzle Atom checkpoint crossings commit on its saved fixed cadence, never presentation frames")
	var atom_verifier := FileAccess.get_file_as_string(
		"res://tools/verify_puzzle_atom_save_authority.gd")
	check("ATOM_RUNTIME_AUTHORITY_VERSION := 5" in atom_source
			and "func activate_lure(_i: int) -> bool:" in atom_source
			and "func _validated_atom_flure_effect" in atom_source
			and "source_trigger_count" in atom_source
			and "WINDOW_ANCHOR_ALL_TARGETS_SETTLED" in atom_source,
		"Puzzle Atom lure authority belongs to an exact physical Flure receipt and settled Enemy body")
	check("same-instance exact physical source commits its lure" in atom_verifier
			and "midpoint is a real in-progress watcher transit" in atom_verifier
			and "fresh atom presenter restores the midpoint and its in-flight watcher" \
				in atom_verifier,
		"Puzzle Atom keeps exact-source and same/fresh physical transit coverage")
	_validate_act1_channels_authority(sources)


func _validate_lockout_tyreg_authority(sources: Dictionary) -> void:
	var source := str(sources.get("scripts/fragments/chunks/lockout_chase_chunk.gd", ""))
	var functions := _parse_functions(source)
	var seed := _function_code(functions, "_seed_tyreg_authority_if_fresh")
	var acceptance := _function_code(functions, "_tyreg_acceptance_truth")
	var consume := _function_code(functions, "_consume_tyreg_round_for_target")
	var reconcile := _function_code(functions, "_reconcile_restored_tyreg_authority")
	var preview := _function_code(functions, "get_preview_state")
	check("var _tyreg_accepted" not in source and "var _suppress_charges" not in source,
		"Lockout cannot reintroduce Tyreg acceptance or ammunition proxy fields")
	check("register_character(TYREG_ID" in seed
			and "_spawn_item(" in seed
			and "_pick_up_item(TYREG_ID" in seed
			and "TYREG_MAGAZINE_SOURCE" in source
			and "\"charge_ids\"" in source,
		"Lockout seeds one stable Tyreg body and one source-tagged finite magazine")
	check("actor_id not in gs.get_party()" in acceptance
			and "_tyreg_body_at_authored_station(gs)" in acceptance
			and "is_narratively_available" in acceptance
			and "_planar_distance" in acceptance
			and "gs.grid.has_line_of_sight" in acceptance
			and "_tyreg_owns_exact_magazine" in acceptance,
		"Tyreg acceptance requires party, body, station, consciousness, range, LOS, and exact ownership")
	check("set_pre_trigger_validator(_validate_tyreg_acceptance)" in source,
		"Tyreg rejects invalid actors before Interactable can spend its one-shot seam")
	check("const CHASE_AUTHORITY_VERSION := 5" in source
			and "\"tyreg_phase\": _tyreg_phase" in source
			and "\"tyreg_magazine_item_id\": _tyreg_magazine_item_id" in source
			and "\"suppress_transaction\": _suppress_transaction.duplicate(true)" in source,
		"Lockout v5 persists Tyreg's phase, exact item identity, and in-flight transaction")
	check("SUPPRESS_TX_RESERVING" in consume
			and consume.find("_publish_chase_authority()") >= 0
			and consume.find("_remove_item(source_id)") >= 0
			and consume.find("_publish_chase_authority()") < consume.find("_remove_item(source_id)")
			and "replacement_item_id" in source
			and "_pick_up_item(TYREG_ID, replacement_id)" in consume,
		"Suppress reserves an exact round before atomically replacing Tyreg's held magazine")
	check("source_exists" in reconcile
			and "replacement_exists" in reconcile
			and "_charge_ids_equal" in reconcile
			and "_apply_reserved_suppress_effect" in reconcile,
		"Lockout restore reconciles pre-removal and post-replacement Suppress signal seams")
	check("_tyreg_help_accepted()" in preview
			and "_tyreg_suppress_charge_count()" in preview,
		"Lockout compatibility readouts derive from semantic phase and exact held inventory")
	check(FileAccess.file_exists("res://tools/verify_lockout_tyreg_authority.gd"),
		"Lockout Tyreg keeps focused negative, signal-time, rollback, and fresh-restore coverage")


func _validate_elevator_gauntlet_authority(sources: Dictionary) -> void:
	var source := str(sources.get("scripts/tutorial/elevator_sequence.gd", ""))
	var functions := _parse_functions(source)
	var player_source := str(sources.get("scripts/game/characters/player.gd", ""))
	var player_functions := _parse_functions(player_source)
	var intro_try := _function_code(functions, "_try_arm_gauntlet_intro")
	var intro_resume := _function_code(functions, "_resume_gauntlet_intro_arming")
	var run_poll := _function_code(functions, "_on_gauntlet_progress_poll")
	var midpoint := _function_code(functions, "_reach_gauntlet_midpoint")
	var midpoint_resume := _function_code(functions, "_resume_gauntlet_midpoint_arming")
	var reset_request := _function_code(functions, "_request_gauntlet_reset")
	var defeat_restore := _function_code(functions, "_reconcile_uncommitted_gauntlet_defeat")
	var complete := _function_code(functions, "_complete")
	var restore_controls := _function_code(functions, "_restore_portable_elevator_control_state")
	var restore_input_gate := _function_code(
		player_functions, "restore_move_input_enabled")
	check("const GAUNTLET_INTRO_REQUIRED_MEMBERS: Array[String] = [\"aster\", \"peris\", \"endo\"]" \
			in source,
		"Elevator gauntlet owns a stable three-character roster")
	check("accepted_commands" in source and "var accepted:" in intro_try \
			and "GAUNTLET_INTRO_PHASE_ARMING" in intro_try \
			and "_resume_gauntlet_intro_arming" in intro_try,
		"Gauntlet briefing requires accepted formation operations before an explicit arming phase")
	check("set_detection_targets" in intro_resume \
			and "begin_home_behavior" in intro_resume \
			and "GAUNTLET_INTRO_PHASE_READY" in intro_resume,
		"Gauntlet intro releases play only after its real first pack is armed")
	check(run_poll.count("_both_conscious_party_past_x") == 2 \
			and "_party_lead_x" not in run_poll,
		"Gauntlet midpoint and exit poll every conscious authored body, never a leader proxy")
	check("GAUNTLET_RUN_PHASE_MIDPOINT_ARMING" in midpoint \
			and "resume_tick" in midpoint \
			and "set_detection_targets" in midpoint_resume \
			and "begin_home_behavior" in midpoint_resume,
		"Gauntlet midpoint persists an interruptible stage-two arming phase")
	check("GAUNTLET_RUN_PHASE_RESET_PENDING" in reset_request \
			and reset_request.find("_publish_elevator_runtime_authority") \
				< reset_request.find("_sync_gauntlet_station_interactivity"),
		"Gauntlet defeat is durable before its derived click surfaces change")
	check("get_stat" in defeat_restore and "GAUNTLET_RUN_PHASE_RESET_PENDING" in defeat_restore,
		"Gauntlet restore reconciles an hp-zero signal-time snapshot into the owed reset")
	check(complete.find("_enter_step(") >= 0 \
			and complete.find("_enter_step(") \
			< complete.find("GAUNTLET_RUN_PHASE_TRANSITIONING"),
		"Gauntlet completion publishes the saved step before transition authority")
	check(FileAccess.file_exists(
			"res://tools/verify_elevator_gauntlet_runtime_authority.gd"),
		"Elevator gauntlet keeps its fresh-load and signal-time authority verifier")
	check("_restore_character_control_input_gate" in restore_controls \
			and "_apply_character_control_selection" not in restore_controls \
			and "command_stop" not in restore_input_gate,
		"Elevator snapshot attachment restores input gates without cancelling saved movement")


func _validate_elevator_route_flure_authority(sources: Dictionary) -> void:
	var source := str(sources.get("scripts/tutorial/elevator_sequence.gd", ""))
	var functions := _parse_functions(source)
	var publish := _function_code(functions, "_publish_elevator_runtime_authority")
	var route_record := _function_code(functions, "_route_progress_authority_state")
	var activation := _function_code(functions, "_on_route_flure_activated")
	var observer := _function_code(
		functions, "_rearm_route_flure_feedback_from_source")
	var restore := _function_code(functions, "on_game_state_snapshot_restored")
	var construction := _function_code(functions, "_below_step_prepare")
	var topology_restore := _function_code(
		functions, "_prepare_chunks_for_save_snapshot")
	var risk_restore := _function_code(
		functions, "_restore_route_progress_from_authority")
	check("ELEVATOR_RUNTIME_AUTHORITY_VERSION := 5" in source
			and "ELEVATOR_RUNTIME_AUTHORITY_CONTRACT := \"elevator_runtime/v5\"" in source
			and "route_progress" in publish,
		"Elevator lower-route knowledge and crossing history use versioned v5 authority")
	check("\"end_tick\"" not in route_record
			and "\"phase\"" not in route_record
			and "_route_flures_activated" not in source
			and "_route_flure_end_ticks" not in source,
		"Elevator does not duplicate a Flure active phase or deadline")
	check("schedule_after" not in activation
			and "_rearm_route_flure_feedback_from_source" in activation
			and "_route_flure_effect_state" in observer
			and "schedule_at" in observer,
		"Elevator feedback is a reconstructible observer of the source-owned Flure deadline")
	check("_restore_route_progress_from_authority" in restore
			and "_restore_route_flure_feedback_from_source" in restore
			and "_set_iron_route_risk_learned" in risk_restore,
		"Elevator restore rebuilds knowledge, cautious risk, and Flure feedback from truth")
	check("_route_reads_resolved =" not in construction
			and "_route_beats_crossed =" not in construction
			and "_route_flure_activation_counts =" not in construction,
		"lower-route chunk construction cannot erase causal route authority")
	check("reveal_chunk(chunk_name)" in topology_restore,
		"saved active Elevator chunks cannot remain hidden, process-disabled prewarm roots")
	check(FileAccess.file_exists(
			"res://tools/verify_elevator_route_flure_authority.gd"),
		"Elevator lower route keeps focused same/fresh Flure midpoint coverage")


func _validate_act1_stacks_authority(sources: Dictionary) -> void:
	var source := str(sources.get("scripts/tutorial/act1_sequence.gd", ""))
	var functions := _parse_functions(source)
	var legacy_bank := _function_code(functions, "trigger_stacks_bank")
	var legacy_shelter := _function_code(functions, "trigger_stacks_shelter_rest")
	var legacy_terminal := _function_code(functions, "trigger_stacks_terminal")
	var legacy_signal := _function_code(functions, "trigger_stacks_signal")
	var legacy_archive := _function_code(functions, "trigger_stacks_archive")
	var log_viewer := _function_code(functions, "trigger_stacks_support_log")
	var shelter_builder := _function_code(functions, "_build_stacks_chunk")
	var bank_commit := _function_code(functions, "_on_act1_stacks_bank_interacted")
	var shelter_commit := _function_code(
		functions, "_on_act1_stacks_shelter_interacted")
	check("return false" in legacy_bank
			and "_on_act1_stacks_bank_interacted" not in legacy_bank
			and "return false" in legacy_shelter
			and "_on_act1_stacks_shelter_interacted" not in legacy_shelter,
		"Act1 Stacks compatibility helpers remain inert instead of advancing story state")
	check("return false" in legacy_terminal
			and "return false" in legacy_signal
			and "return false" in legacy_archive
			and "_ensure_stacks_support_log_entry" not in log_viewer,
		"Act1 Stacks optional helpers cannot manufacture observations or journal knowledge")
	check("_validate_act1_stacks_bank_trigger.bind" in source
			and "_on_act1_stacks_bank_interacted.bind" in source
			and "_validate_act1_stacks_shelter_trigger" in source
			and "_on_act1_stacks_shelter_interacted.bind" in source,
		"Act1 Stacks banks and shelter are wired through their physical world controls")
	check("_act1_stacks_bank_receipt_pending" in bank_commit
			and "_act1_stacks_shelter_receipt_pending" in shelter_commit
			and "_act1_stacks_one_shot_receipt" in source
			and "_act1_interaction_actor_ready_at" in source,
		"Act1 Stacks consequences require source-bound one-shot receipts and a ready nearby body")
	check("_validate_act1_stacks_optional_trigger.bind" in shelter_builder
			and "_on_act1_stacks_terminal_interacted.bind" in shelter_builder
			and "_on_act1_stacks_signal_interacted.bind" in shelter_builder
			and "_on_act1_stacks_archive_interacted.bind" in shelter_builder
			and "_act1_stacks_optional_receipt_pending" in source,
		"Act1 Stacks optional observations enter through exact physical source receipts")
	check(FileAccess.file_exists(
			"res://tools/verify_stacks_rings_longform.gd"),
		"Act1 Stacks keeps focused shortcut, identity, position, and long-form coverage")


func _validate_act1_rings_authority(sources: Dictionary) -> void:
	var source := str(sources.get("scripts/tutorial/act1_sequence.gd", ""))
	var functions := _parse_functions(source)
	var legacy_client := _function_code(functions, "trigger_rings_client")
	var client_commit := _function_code(
		functions, "_on_act1_rings_client_interacted")
	var rings_builder := _function_code(functions, "_build_rings_chunk")
	var legacy_trace := _function_code(functions, "trigger_rings_trace")
	var trace_commit := _function_code(functions, "_on_act1_rings_trace_interacted")
	check("return false" in legacy_client
			and "_on_act1_rings_client_interacted" not in legacy_client,
		"Act1 Rings compatibility helper remains inert instead of naming the story consequence")
	check("set_pre_trigger_validator(_validate_act1_rings_client_trigger)" in rings_builder
			and "_on_act1_rings_client_requested" in rings_builder
			and "_on_act1_rings_client_interacted.bind(client, true)" in rings_builder,
		"Act1 Rings wires reassignment through the real Marco world control")
	check("_act1_rings_client_receipt_pending(source)" in client_commit
			and "_act1_rings_reassignment_preflight(true)" in client_commit
			and "source == _rings_client_interactable" in source,
		"Act1 Rings consequence requires the exact source-bound one-shot receipt")
	check("return false" in legacy_trace
			and "_on_act1_rings_trace_interacted" not in legacy_trace
			and "_validate_act1_rings_trace_trigger.bind" in source
			and "_on_act1_rings_trace_interacted.bind" in source
			and "_act1_rings_trace_receipt_pending" in trace_commit,
		"Act1 Rings optional knowledge also requires its exact physical trace source")
	check(FileAccess.file_exists(
			"res://tools/verify_act1_rings_departure_authority.gd"),
		"Act1 Rings keeps focused shortcut and midpoint save-authority coverage")


func _validate_act1_channels_authority(sources: Dictionary) -> void:
	var source := str(sources.get("scripts/tutorial/act1_sequence.gd", ""))
	var functions := _parse_functions(source)
	var anonymous_callback_count := 0
	var schedule_after_count := 0
	for raw_line in source.split("\n"):
		var code := _strip_strings_and_comment(str(raw_line))
		anonymous_callback_count += code.count("func(")
		schedule_after_count += code.count("schedule_after(")
	var streaming := _function_code(functions, "_evaluate_channels_streaming_endpoints")
	var lane_complete := _function_code(functions, "_complete_channels_window_lane")
	var encounter_complete := _function_code(functions, "_complete_channels_encounter")
	var shelter_complete := _function_code(functions, "_on_channels_shelter_party_arrived")
	var shelter_enable := _function_code(functions, "_enable_channels_shelter_rest")
	var shelter_rest := _function_code(
		functions, "_on_act1_channels_shelter_interacted")
	var legacy_shelter_rest := _function_code(
		functions, "trigger_channels_shelter_rest")
	var legacy_recuperate := _function_code(
		functions, "_recuperate_channels_party")
	var encounter_poll := _function_code(functions, "_evaluate_channels_encounter_authority")
	var encounter_update := _function_code(functions, "_update_channels_encounter")
	var window_update := _function_code(functions, "_update_channels_window_puzzles")
	var enemy_swept := _function_code(functions, "_on_channels_enemy_swept")
	var kit_activate := _function_code(functions, "_activate_channels_kit")
	var flure_bind := _function_code(functions, "_bind_channels_flures_to_game_state")
	var window_authority := _function_code(functions, "_channels_window_authority_state")
	var runtime_authority := _function_code(functions, "_channels_runtime_authority_state")
	var movement_start := _function_code(functions, "_move_party_and_continue")
	var movement_finish := _function_code(functions, "_evaluate_channels_formation")
	var apply_snapshot := _function_code(functions, "apply_save_snapshot")
	var restore := _function_code(
		functions, "_restore_channels_runtime_authority_from_game_state")
	var prepare_lockout := _function_code(functions, "_prepare_lockout_party_authority")
	var start_lockout := _function_code(functions, "_start_lockout_approach")
	check("const CHANNELS_PARTY_IDS := [\"aster\", \"peris\", \"endo\"]" in source,
		"Act1 Channels owns a stable authored roster independent of current selection")
	check("const LOCKOUT_PARTY_IDS := [\"aster\", \"peris\"]" in source
			and "const LOCKOUT_DEPARTED_CHARACTER_ID := \"endo\"" in source
			and "_game_state.unregister_character(LOCKOUT_DEPARTED_CHARACTER_ID)" \
				in prepare_lockout
			and "for char_id in LOCKOUT_PARTY_IDS" in prepare_lockout
			and "_game_state.set_party(roster)" in prepare_lockout
			and "_prepare_lockout_party_authority()" in start_lockout,
		"Act1 Lockout reconstructs its two-body roster and removes the departed Endo body")
	check("_channels_full_conscious_party_past_x" in streaming
			and streaming.count("_channels_full_conscious_party_past_x") == 4,
		"Act1 Channels streams only after all three conscious bodies cross each handoff")
	check("_channels_full_conscious_party_near" in lane_complete
			and "_channels_active_window_lane" in lane_complete
			and "_channels_window_step_name" in lane_complete,
		"Channels lane completion defends its own active step and whole-party endpoint")
	check("_channels_full_conscious_party_near" in encounter_complete
			and "_channels_full_conscious_party_near" in shelter_complete,
		"Channels encounter and shelter consequences revalidate the full conscious roster")
	check("_channels_enemy_pack_committed" in encounter_poll
			and "for char_id in CHANNELS_PARTY_IDS" in encounter_poll
			and "_player.global_position" not in encounter_poll
			and "_channels_swarm_units" not in encounter_poll,
		"Channels encounter reads real Enemy commitment and every authored party body")
	check("command_move_to_pos" in movement_start
			and "accepted_ids" in movement_start
			and "get_destination" in movement_start
			and "_channels_position_to_data" in movement_start
			and "_channels_formation_all_commands_accepted" in movement_finish
			and "_channels_formation_at_endpoints" in movement_finish,
		"Channels formations require accepted commands and portable real endpoints")
	check("_wait_for_arrivals" not in source
			and "if phase !=" in movement_finish,
		"Channels cannot treat stopped or interrupted movement as arrival")
	check("CHANNELS_RUNTIME_AUTHORITY_CONTRACT := \"act1_channels/v3\"" in source
			and "CHANNELS_RUNTIME_AUTHORITY_VERSION := 3" in source
			and "poll_origin_tick" in source
			and "retry_deadline" in source,
		"Channels room bookkeeping publishes its stable v3 authority contract")
	check("func _channels_enemy_has_swept_body" in source
			and "not _channels_enemy_has_swept_body(enemy_id)" in source,
		"Channels swept-ID provenance cannot replace a dead stable Enemy body")
	var shelter_publish_index := shelter_rest.find("_publish_channels_runtime_authority")
	var shelter_command_index := shelter_rest.find("command_party_rest")
	check("command_party_rest" not in shelter_complete
			and "_channels_shelter_rest_phase = \"locked\"" in source
			and "_apply_channels_shelter_rest_presentation" in shelter_complete
			and "_channels_shelter_rest_phase = \"ready\"" in source
			and "_publish_channels_runtime_authority" in shelter_enable
			and shelter_publish_index >= 0
			and shelter_command_index > shelter_publish_index,
		"Channels arrival keeps the proximity hearth locked until its named introduction completes; the explicit verb publishes before its batch")
	check("return false" in legacy_shelter_rest
			and "_on_act1_channels_shelter_interacted" not in legacy_shelter_rest
			and "return false" in legacy_recuperate
			and "trigger_channels_shelter_rest" not in legacy_recuperate,
		"Channels legacy rest helpers remain inert instead of manufacturing a hearth action")
	check("_act1_channels_shelter_receipt_pending" in shelter_rest
			and "set_pre_trigger_validator(" in source
			and "_validate_act1_channels_shelter_trigger" in source
			and "_on_act1_channels_shelter_interacted.bind" in source,
		"Channels REST PARTY requires the source-bound one-shot hearth receipt")
	check("safe_until_tick" not in window_authority
			and "lure_deadline" not in runtime_authority
			and "get_effect_state" in source,
		"Flure owns lure deadlines instead of duplicating them in room authority")
	check("_cancel_channels_runtime_callbacks" in restore
			and "_apply_channels_runtime_authority" in restore
			and "_rearm_channels_runtime_authority" in restore
			and "schedule_at" in source,
		"Channels restore cancels opaque callbacks, applies truth, and rearms absolute deadlines")
	check("EnemyScript.new()" in source
			and "FlureScript.new()" in source
			and "ChannelScript.new()" in source
			and "\"act1_channels_%s_enemy_%02d\"" in source
			and "\"act1_channels_encounter_enemy_%02d\"" in source,
		"Act1 Channels composes stable-ID Enemy, Flure, and Channel kit")
	check("_bind_channels_flures_to_game_state" in kit_activate
			and ".configure(" in flure_bind
			and "_game_state" in flure_bind
			and "_channels_flures_bound" in flure_bind,
		"Act1 attaches prebuilt Flures to GameState exactly once before kit activation")
	check("_channels_swarm_units" not in source
			and "_channels_flush_swarm_units" not in source
			and "func _channels_window_path_projection" not in source
			and "func _sync_channels_window_swarm_presentation" not in source
			and "func _channels_encounter_unit_x" not in source
			and "ChannelsWindowSwarm_" not in source
			and "ChannelsFlushSwarm_" not in source,
		"Act1 Channels cannot reintroduce proxy swarms or analytical body motion")
	check("take_damage" not in enemy_swept
			and "snap_character_to" not in enemy_swept
			and "command_move_to_pos" not in enemy_swept
			and "take_damage" not in window_update
			and "snap_character_to" not in window_update
			and ".position" not in encounter_update,
		"room callbacks only count kit consequences; render updates cannot move or kill bodies")
	check("target_spotted.connect" in source
			and "hit_target.connect" in source
			and "_apply_channels_grid_occluders" in source,
		"final encounter failures come from real Enemy LOS/attack signals and mirrored cover")
	check("func _on_channels_authority_poll" in source
			and "func _evaluate_channels_window_authority" in source
			and "func _evaluate_channels_encounter_authority" in source,
		"Channels physical consequences run on a saved scheduler cadence, not render frames")
	check(FileAccess.file_exists(
			"res://tools/verify_act1_channels_runtime_save_authority.gd"),
		"Act1 Channels keeps its focused midpoint/save-authority verifier")
	check("restore_move_input_enabled" in source \
			and "set(\"_move_enabled\"" not in source,
		"Act1 restore gates player input without reaching into private state or cancelling saved movement")
	check(anonymous_callback_count == 0,
		"Act1 has no anonymous dialogue-to-gameplay or scene-handoff callback")
	check(schedule_after_count == 1
			and "schedule_after" in _function_code(functions, "_arm_channels_formation_poll"),
		"Act1's only relative scheduler callback is its saved Channels formation poll")
	var authority_poll_deadline := _function_code(
		functions, "_channels_next_authority_poll_tick")
	check("candidate <= current_tick + 0.000001" in authority_poll_deadline
			and "candidate += CHANNELS_AUTHORITY_POLL_INTERVAL" in authority_poll_deadline,
		"Act1 Channels advances exact-boundary authority polls strictly beyond the current tick")
	check("_schedule_portable_method(2.0, _handoff_to_leaving_facility" in source
			and "_schedule_portable_method(1.0, _start_stacks_enter" in source
			and "_schedule_portable_method(0.2, _start_lockout_chase" in source,
		"Act1 campaign boundaries and chase dispatch use named portable deadlines")
	check("ACT1_SNAPSHOT_CHUNKS" in source
			and "_prepare_act1_chunks_for_snapshot(data)" in apply_snapshot
			and apply_snapshot.find("_prepare_act1_chunks_for_snapshot(data)")
				< apply_snapshot.find("super.apply_save_snapshot(data)"),
		"Act1 reconstructs the saved level presenters before GameState replacement")
	check("ACT1_CAMPAIGN_AUTHORITY_KEY" in source
			and "func _publish_act1_campaign_authority" in source
			and "func _restore_act1_campaign_authority" in source,
		"Act1 campaign-host phases live in portable GameState authority")
	check(FileAccess.file_exists(
			"res://tools/verify_act1_linear_continuations.gd"),
		"Act1 named story continuations keep a same/fresh midpoint verifier")
	var longform := FileAccess.get_file_as_string(
		"res://tools/verify_channels_longform_extension.gd")
	check("._complete_channels_window_lane(" not in longform,
		"Channels longform verification cannot bypass the production endpoint poll")


func _validate_generated_cadence_release_guards(sources: Dictionary) -> void:
	var source := str(sources.get("scripts/fragments/chunks/generated_stretch_chunk.gd", ""))
	var functions := _parse_functions(source)
	var process_code := _function_code(functions, "_process")
	check(functions.has("_process")
			and "_update_generated_flora_concealment(" not in process_code,
		"Generated flora concealment cannot be sampled by the render-frame _process path")

	var cargo_reachable_code := ""
	for owner_v in _reachable_functions("_update_hydraulic_cargo_sequence", functions):
		cargo_reachable_code += "\n" + _function_code(functions, str(owner_v))
	var staged_commit := RegEx.new()
	staged_commit.compile("_bridge_cargo_phase\\s*=\\s*BRIDGE_CARGO_STAGED")
	var seated_commit := RegEx.new()
	seated_commit.compile("_bridge_cargo_phase\\s*=\\s*BRIDGE_CARGO_SEATED")
	var staged_callback := _function_code(functions, "_on_bridge_cargo_staged")
	var seated_callback := _function_code(functions, "_complete_bridge_cargo_transport")
	var fall_scheduler := _function_code(functions, "_schedule_bridge_cargo_fall")
	var transport_scheduler := _function_code(functions, "_schedule_bridge_cargo_transport")
	check(functions.has("_update_hydraulic_cargo_sequence")
			and staged_commit.search(cargo_reachable_code) == null
			and staged_commit.search(staged_callback) != null
			and "schedule_at(" in fall_scheduler
			and "Callable(self, \"_on_bridge_cargo_staged\")" in source,
		"Generated cargo FALLING->STAGED commits only in its scheduled deadline callback")
	check(functions.has("_update_hydraulic_cargo_sequence")
			and seated_commit.search(cargo_reachable_code) == null
			and seated_commit.search(seated_callback) != null
			and "schedule_at(" in transport_scheduler
			and "Callable(self, \"_complete_bridge_cargo_transport\")" in source,
		"Generated cargo TRANSPORTING->SEATED commits only in its scheduled deadline callback")


func _validate_authority_strategy(path: String, strategy: String, source: String) -> void:
	match strategy:
		"world_state_restore":
			check("func on_game_state_snapshot_restored" in source,
				"%s declares the standard restore hook" % path)
			check("set_world_state" in source and "get_world_state" in source,
				"%s publishes and reads portable world state" % path)
			check("deadline" in source,
				"%s records/rebuilds an absolute phase deadline" % path)
		"inherited_fragment_world_state_restore":
			var fragment_base := FileAccess.get_file_as_string(
				"res://scripts/fragments/chunks/data_fragment_chunk.gd")
			check("extends \"res://scripts/fragments/chunks/data_fragment_chunk.gd\"" in source
					and "func on_game_state_snapshot_restored" in source,
				"%s declares the inherited fragment restore hook" % path)
			check("_publish_fragment_authority()" in source
					and "get_world_state" in source
					and "set_world_state" in fragment_base
					and "get_world_state" in fragment_base,
				"%s publishes and reads inherited portable fragment authority" % path)
			check("deadline" in source or "next_exit_spatial_tick" in source,
				"%s records/rebuilds an absolute inherited phase deadline" % path)
		"game_state_core":
			check("func serialize(" in source and "func deserialize(" in source,
				"GameState owns an explicit serialize/deserialize contract")
			check("snapshot_restored.emit" in source,
				"GameState exposes the presenter reattachment seam")
		"portable_restore":
			check("func serialize_state(" in source and "func restore_state(" in source,
				"%s exposes a portable state/restore pair" % path)
			check("arrival_tick" in source or "deadline" in source,
				"%s preserves an absolute completion tick" % path)
		"portable_world_state":
			check("func snapshot(" in source and "func restore(" in source,
				"%s exposes a portable snapshot/restore pair" % path)
			check("authority_state_key" in source and "set_world_state" in source,
				"%s publishes its portable state into GameState" % path)
			check("next_tick" in source,
				"%s preserves its next absolute cadence tick" % path)
		_:
			fail("unknown authority strategy '%s' for %s" % [strategy, path])


func _validate_frame_mutations(sources: Dictionary) -> void:
	var detected: Dictionary = {}
	var first_lines: Dictionary = {}
	for path_v in sources.keys():
		var path := str(path_v)
		var functions := _parse_functions(str(sources[path]))
		for entrypoint in FRAME_ENTRYPOINTS:
			if not functions.has(entrypoint):
				continue
			var reachable := _reachable_functions(entrypoint, functions)
			for owner_v in reachable:
				var owner := str(owner_v)
				for line_v in functions.get(owner, []):
					var line: Dictionary = line_v
					var code := str(line.get("code", ""))
					for kind_v in _mutation_regexes.keys():
						var kind := str(kind_v)
						var regex: RegEx = _mutation_regexes[kind]
						if regex.search(code) == null:
							continue
						var signature := "%s|%s|%s|%s" % [path, entrypoint, owner, kind]
						detected[signature] = int(detected.get(signature, 0)) + 1
						if not first_lines.has(signature):
							first_lines[signature] = int(line.get("line", 0))

	for signature_v in detected.keys():
		var signature := str(signature_v)
		var actual := int(detected[signature])
		if FRAME_MUTATION_DEBT.has(signature):
			var spec: Dictionary = FRAME_MUTATION_DEBT[signature]
			print("DEBT: %s (line %d) -- %s" % [
				signature, int(first_lines.get(signature, 0)), str(spec.get("reason", ""))
			])
			check(actual == int(spec.get("count", -1)),
				"frame-mutation debt count is frozen for %s" % signature)
		elif FRAME_MUTATION_EXEMPTIONS.has(signature):
			var spec: Dictionary = FRAME_MUTATION_EXEMPTIONS[signature]
			check(actual == int(spec.get("count", -1)),
				"narrow frame-mutation exemption count is frozen for %s" % signature)
		else:
			fail("render-frame gameplay mutation at %s:%d (count %d)" % [
				signature, int(first_lines.get(signature, 0)), actual
			])

	for group in [FRAME_MUTATION_DEBT, FRAME_MUTATION_EXEMPTIONS]:
		for signature_v in group.keys():
			var signature := str(signature_v)
			check(detected.has(signature),
				"remove stale frame-mutation ledger entry: %s" % signature)


func _parse_functions(source: String) -> Dictionary:
	var functions := {}
	var current := ""
	var line_number := 0
	for raw_v in source.split("\n"):
		line_number += 1
		var raw := str(raw_v).trim_suffix("\r")
		var code := _strip_strings_and_comment(raw)
		var function_name := _top_level_function_name(code)
		if function_name != "":
			current = function_name
			functions[current] = []
			continue
		if current != "" and code.strip_edges() != "" and _indent_width(raw) == 0:
			current = ""
		if current != "" and code.strip_edges() != "":
			(functions[current] as Array).append({
				"line": line_number,
				"code": code,
				"indent": _indent_width(raw),
			})

	# Calls inside anonymous functions are callbacks, not synchronous edges from the function that
	# constructs them. Excluding those bodies prevents schedule/connect lambdas from looking like
	# render-frame consequences while still following ordinary if/loop helper calls.
	for name_v in functions.keys():
		var name := str(name_v)
		var filtered: Array = []
		var lambda_indents: Array[int] = []
		for line_v in functions[name]:
			var line: Dictionary = line_v
			var indent := int(line.get("indent", 0))
			while not lambda_indents.is_empty() and indent <= lambda_indents[-1]:
				lambda_indents.pop_back()
			if not lambda_indents.is_empty():
				continue
			var compact := str(line.get("code", "")).replace(" ", "").replace("\t", "")
			if "func(" in compact:
				lambda_indents.append(indent)
				continue
			filtered.append(line)
		functions[name] = filtered
	return functions


func _function_code(functions: Dictionary, function_name: String) -> String:
	var code_lines: Array[String] = []
	for line_v in functions.get(function_name, []):
		code_lines.append(str((line_v as Dictionary).get("code", "")))
	return "\n".join(code_lines)


func _reachable_functions(entrypoint: String, functions: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	var stack: Array[String] = [entrypoint]
	while not stack.is_empty():
		var name: String = stack.pop_back()
		if seen.has(name):
			continue
		seen[name] = true
		out.append(name)
		for line_v in functions.get(name, []):
			var line: Dictionary = line_v
			for match_v in _call_regex.search_all(str(line.get("code", ""))):
				var called := str((match_v as RegExMatch).get_string(2))
				if functions.has(called) and not seen.has(called):
					stack.append(called)
	return out


func _top_level_function_name(code: String) -> String:
	if not code.begins_with("func "):
		return ""
	var open_paren := code.find("(")
	if open_paren < 5:
		return ""
	return code.substr(5, open_paren - 5).strip_edges()


func _indent_width(line: String) -> int:
	var width := 0
	for index in range(line.length()):
		var character := line.substr(index, 1)
		if character == "\t":
			width += 4
		elif character == " ":
			width += 1
		else:
			break
	return width


func _strip_strings_and_comment(line: String) -> String:
	var out := ""
	var quote := ""
	var escaped := false
	for index in range(line.length()):
		var character := line.substr(index, 1)
		if quote != "":
			out += " "
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
			out += " "
		elif character == "#":
			break
		else:
			out += character
	return out


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)


func fail(label: String) -> void:
	check(false, label)
