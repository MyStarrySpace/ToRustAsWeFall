extends SceneTree

## Focused contract for SceneChunk's reusable shelter factory. The old helper registered sanctuary
## but charged only the active portrait; this proves explicit authored membership, spatial/conscious
## preflight, and one canonical atomic GameState party-rest command.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const FixtureScript := preload("res://tools/party_rest_shelter_fixture.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var gs: GameState = host.game_state
	gs.event_log = EventLog.new()
	gs.register_character("aster", FixtureScript.SHELTER_CENTER, 3.0, {
		"hp": 70.0, "stamina": 80.0, "atp": 4.0,
	})
	gs.register_character(
		"peris",
		FixtureScript.SHELTER_CENTER + Vector3(8.0, 0.0, 0.0),
		3.0,
		{"hp": 70.0, "stamina": 80.0, "atp": 4.0})
	gs.set_party(FixtureScript.REQUIRED_MEMBERS)
	gs.set_game_clock(1, 0.4)
	var chunk = FixtureScript.new()
	chunk.attach_chunk_host(host, "party_rest_shelter_fixture")
	host.add_child(chunk)
	await process_frame

	check(gs.is_at_shelter("aster") and not gs.is_at_shelter("peris"),
		"the factory registers its exact authored shelter rectangle")
	var initial_atp := _party_atp(gs)
	chunk._on_authored_party_rest_interacted(chunk.rest_interactable)
	check(_party_atp(gs) == initial_atp
			and not gs.is_resting("aster") and not gs.is_resting("peris"),
		"one present portrait cannot partially charge or rest the authored pair")
	var outside_outcome: Dictionary = chunk._get_authored_party_rest_outcome(
		chunk.rest_interactable)
	check(not bool(outside_outcome.get("complete", true))
			and _contains_blocker(outside_outcome, "outside this shelter"),
		"the rejected action identifies the missing spatial cause")

	gs.snap_character_to("peris", FixtureScript.SHELTER_CENTER + Vector3(1.0, 0.0, 0.0))
	gs.down_character("peris")
	chunk._on_authored_party_rest_interacted(chunk.rest_interactable)
	check(_party_atp(gs) == initial_atp
			and _contains_blocker(
				chunk._get_authored_party_rest_outcome(chunk.rest_interactable),
				"must be conscious"),
		"a downed required member blocks the whole batch without a prefix payment")

	gs.restore_character("peris")
	gs.set_stat("peris", "hp", 70.0)
	gs.set_stat("peris", "stamina", 80.0)
	var absent := chunk._preflight_authored_party_rest(
		FixtureScript.SHELTER_CENTER,
		FixtureScript.SHELTER_SIZE,
		["aster", "missing_member"])
	check(_contains_blocker(absent, "is not present") and _party_atp(gs) == initial_atp,
		"an absent explicitly required member fails closed without resource writes")

	chunk._on_authored_party_rest_interacted(chunk.rest_interactable)
	var completed: Dictionary = chunk._get_authored_party_rest_outcome(
		chunk.rest_interactable)
	check(bool(completed.get("complete", false))
			and _party_atp(gs) == {"aster": 3.0, "peris": 3.0},
		"the gathered conscious pair pays exactly one ATP each in one accepted command")
	check(gs.is_resting("aster") and gs.is_resting("peris"),
		"the accepted shelter action installs both canonical rest records before success")
	check(_party_rest_event_count(gs) == 1,
		"replay records one PARTY_REST event rather than sequential active-character rests")

	host.queue_free()
	await process_frame
	print("SCENE CHUNK PARTY REST AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _party_atp(gs: GameState) -> Dictionary:
	return {
		"aster": gs.get_stat("aster", "atp"),
		"peris": gs.get_stat("peris", "atp"),
	}


func _contains_blocker(outcome: Dictionary, needle: String) -> bool:
	for blocker_v in outcome.get("blocked", []) as Array:
		if str(blocker_v).contains(needle):
			return true
	return false


func _party_rest_event_count(gs: GameState) -> int:
	var count := 0
	for event_v in gs.event_log.events:
		var event: Dictionary = event_v as Dictionary
		if str(event.get("kind", "")) == str(GameEvent.KIND_PARTY_REST):
			count += 1
	return count


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
