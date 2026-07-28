extends SceneTree

## Focused integration regression for the generated Shelter 2 cutscene. The
## hydraulic contract separately proves the physical route/rest receipt; this
## suite proves the new presentation and its nested save authority.

const CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const CONTROLLER_SCRIPT := preload(
	"res://scripts/fragments/chunks/shelter2_stim_cutscene_controller.gd"
)
const GAME_CAMERA_SCRIPT := preload("res://scripts/ui/game_camera.gd")
const SPEC_PATH := (
	"res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"
)
const PARTY_IDS: Array[String] = ["aster", "peris", "endo"]
const EXPECTED_DIALOGUE_KEYS: Array[String] = [
	"channels.narration.shelter",
	"channels.endo.door",
	"channels.narration.recuperate",
]
const EXPECTED_STATE_KEYS: Array[String] = [
	"animation_complete",
	"animation_deadline",
	"completed_tick",
	"completion_count",
	"dialogue_complete",
	"dialogue_start_tick",
	"dialogue_started",
	"phase",
	"presenter_visibility_state",
	"return_camera_state",
	"start_tick",
	"version",
]


class FakeCharacter:
	extends Node3D

	var char_id := ""
	var move_enabled := true
	var mesh: MeshInstance3D
	var label: Label3D

	func _init(character_id: String) -> void:
		char_id = character_id
		name = character_id.capitalize()
		mesh = MeshInstance3D.new()
		mesh.name = "BodyMesh"
		mesh.mesh = BoxMesh.new()
		add_child(mesh)
		label = Label3D.new()
		label.name = "NameLabel"
		label.text = character_id.capitalize()
		add_child(label)

	func is_move_enabled() -> bool:
		return move_enabled

	func restore_move_input_enabled(enabled: bool) -> void:
		move_enabled = enabled


class RecordingDialogue:
	extends Node

	signal dialogue_finished()

	var active := false
	var cutscene_mode := false
	var entries: Array[Dictionary] = []
	var say_invocations := 0
	var clear_count := 0

	func say(text: String, speaker := "", style := "normal", wait := false) -> void:
		say_invocations += 1
		entries.append({
			"text": text,
			"speaker": speaker,
			"style": style,
			"wait_for_input": wait,
		})
		active = true

	func set_cutscene_mode(enabled: bool) -> void:
		cutscene_mode = enabled

	func is_active() -> bool:
		return active

	func clear() -> void:
		clear_count += 1
		active = false
		entries.clear()

	func snapshot_state() -> Dictionary:
		return {
			"active": active,
			"cutscene_mode": cutscene_mode,
			"entries": entries.duplicate(true),
		}

	func restore_state(snapshot: Dictionary) -> bool:
		active = bool(snapshot.get("active", false))
		cutscene_mode = bool(snapshot.get("cutscene_mode", false))
		entries.assign((snapshot.get("entries", []) as Array).duplicate(true))
		return true

	func finish_conversation() -> void:
		if not active:
			return
		active = false
		entries.clear()
		dialogue_finished.emit()


class CutsceneHost:
	extends TutorialSequence

	var dialogue: RecordingDialogue
	var characters: Dictionary = {}
	var game_camera: Camera3D

	func _ready() -> void:
		# The verifier installs only the reusable systems needed by a hosted chunk.
		set_process(false)

	func _exit_tree() -> void:
		pass

	func setup_for_test() -> void:
		_scheduler = EventScheduler.new()
		_ui_scheduler = EventScheduler.new()
		_game_state = GameState.new()
		_game_state.scheduler = _scheduler
		for index in PARTY_IDS.size():
			var character_id := PARTY_IDS[index]
			_game_state.register_character(
				character_id, Vector3(float(index) * 0.8, 0.5, 0.0), 3.0
			)
			var character := FakeCharacter.new(character_id)
			add_child(character)
			characters[character_id] = character
			_game_state_character_nodes[character_id] = character
		_player = characters["aster"]
		# Preserve a distinct hidden descendant through the cutscene round trip.
		(characters["peris"] as FakeCharacter).label.visible = false

		game_camera = GAME_CAMERA_SCRIPT.new() as Camera3D
		game_camera.name = "GameCamera"
		add_child(game_camera)
		_camera = game_camera
		game_camera.set("target", characters["aster"])
		game_camera.make_current()

		dialogue = RecordingDialogue.new()
		dialogue.name = "DialogueBox"
		add_child(dialogue)
		_dialogue = dialogue

	func _chunk_host_hud() -> Node:
		return null

	func advance_gameplay(ticks: float) -> void:
		_scheduler.advance_ticks(ticks)
		_sync_scheduler_animations()

	func scheduler_snapshot() -> Dictionary:
		return _scheduler.serialize()

	func restore_scheduler(snapshot: Dictionary) -> void:
		_scheduler.clear()
		_scheduler.deserialize(snapshot)


var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var pair := await _boot_pair(false)
	await _verify_live_cutscene_and_restore(pair)
	await _verify_fresh_mid_dialogue_restore(pair)
	await _verify_legacy_completed_migration(pair)
	await _cleanup_pair(pair)

	var roguelike_pair := await _boot_pair(true)
	_force_completed_shelter_transaction(roguelike_pair.chunk)
	var roguelike_state: Dictionary = roguelike_pair.chunk.call("get_preview_state")
	check(bool(roguelike_state.get("completion_ready", false)),
		"roguelike target completes without inserting a campaign cutscene")
	check(str((roguelike_state.get("shelter_cutscene", {}) as Dictionary).get(
		"phase", ""
	)) == "complete", "roguelike bypass is still explicit nested authority")
	check(roguelike_pair.host.dialogue.say_invocations == 0,
		"roguelike bypass never queues the Shelter 2 conversation")
	check(_controller(roguelike_pair.chunk).call("get_presentation_scene") == null,
		"roguelike bypass creates no cinematic proxy")
	await _cleanup_pair(roguelike_pair)

	print("SHELTER 2 STIM RUNTIME: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_live_cutscene_and_restore(pair: Dictionary) -> void:
	var host: CutsceneHost = pair.host
	var chunk: Node = pair.chunk
	var controller := _controller(chunk)
	check(controller != null, "target stretch owns the dedicated cutscene controller")
	check(
		(controller.call("get_dialogue_keys") as Array) == EXPECTED_DIALOGUE_KEYS,
		"controller queues only the three already-authored Shelter 2 dialogue keys"
	)
	check(not (controller.call("get_dialogue_keys") as Array).has(
		"channels.narration.shortcut"
	), "generated shelter does not narrate the absent shortcut")
	for key in controller.call("get_dialogue_keys"):
		check(not str(key).begins_with("stacks.rest."),
			"Shelter 2 does not repurpose Peris's separate Stacks support scene")

	_force_completed_shelter_transaction(chunk)
	var opening: Dictionary = chunk.call("get_preview_state")
	check(bool(opening.get("shelter_rested", false)),
		"canonical rest transaction is complete before presentation begins")
	check(str(opening.get("route_phase", "")) == "shelter_cutscene"
			and not bool(opening.get("completion_ready", true)),
		"route completion waits at the animation/dialogue join")
	check(bool(controller.call("is_playing"))
			and controller.call("get_presentation_scene") != null,
		"target neutral mode creates exactly one playing presentation")
	check(host.is_preview_cutscene_input_owned(),
		"the live presentation owns camera and gameplay input")
	check(_all_party_visuals_hidden(host),
		"gameplay meshes and labels hide without hiding character roots")

	var nested := _nested_record(host, chunk)
	var portable_nested := _json_round_trip(nested)
	var state_keys: Array = portable_nested.keys()
	state_keys.sort()
	check(state_keys == EXPECTED_STATE_KEYS,
		"nested authority uses the strict versioned cutscene schema")
	check(bool(controller.call("valid_state", portable_nested)),
		"nested authority survives a strict JSON round trip")
	check(is_equal_approx(
		float(portable_nested.dialogue_start_tick) - float(portable_nested.start_tick),
		2.0
	), "authored motion leads the first dialogue line by two seconds")
	check(is_equal_approx(
		float(portable_nested.animation_deadline) - float(portable_nested.start_tick),
		16.0
	), "finite camera staging retains its sixteen-second deadline")

	# Roll back a discarded future dialogue start to the pre-dialogue snapshot.
	host.advance_gameplay(1.0)
	var pre_dialogue := _capture(pair)
	host.advance_gameplay(1.01)
	check(host.dialogue.say_invocations == 3 and host.dialogue.active,
		"dialogue deadline queues the complete authored conversation once")
	_assert_recorded_dialogue_matches_authoring(host.dialogue)
	_restore(pair, pre_dialogue)
	check(not host.dialogue.active
			and not bool(_nested_record(host, chunk).get("dialogue_started", true)),
		"pre-dialogue rollback retracts the discarded queue and start flag")
	check(_presentation_count(chunk) == 1 and host.is_preview_cutscene_input_owned(),
		"pre-dialogue rollback rebuilds one proxy and one ownership lease")

	host.advance_gameplay(1.01)
	check(host.dialogue.say_invocations == 6 and host.dialogue.active,
		"restored absolute deadline requeues the conversation once")
	_assert_recorded_dialogue_matches_authoring(host.dialogue)
	var mid_dialogue := _capture(pair)
	pair["mid_dialogue_snapshot"] = mid_dialogue
	var invocations_at_mid := host.dialogue.say_invocations

	# Let animation win the join in a discarded future, then retract it.
	var animation_deadline := float(
		_nested_record(host, chunk).get("animation_deadline", host.get_preview_scheduler_tick())
	)
	host.advance_gameplay(
		animation_deadline - host.get_preview_scheduler_tick() + 0.001
	)
	var animation_first: Dictionary = chunk.call("get_preview_state")
	check(bool((animation_first.shelter_cutscene as Dictionary).get(
		"animation_complete", false
	)) and not bool(animation_first.get("completion_ready", true)),
		"finished animation cannot complete the level while dialogue remains active")
	_restore(pair, mid_dialogue)
	check(not bool(_nested_record(host, chunk).get("animation_complete", true))
			and host.dialogue.active,
		"mid-dialogue rollback retracts the discarded animation completion")
	check(host.dialogue.say_invocations == invocations_at_mid,
		"mid-dialogue restore reconnects without duplicating authored lines")
	check(_dialogue_completion_connection_count(host.dialogue) == 1,
		"restored dialogue owns exactly one completion callback")

	# Let dialogue win the real join, then cross the original animation deadline.
	host.dialogue.finish_conversation()
	var dialogue_first: Dictionary = chunk.call("get_preview_state")
	check(bool((dialogue_first.shelter_cutscene as Dictionary).get(
		"dialogue_complete", false
	)) and not bool(dialogue_first.get("completion_ready", true)),
		"finished dialogue cannot complete the level before camera staging")
	animation_deadline = float(
		_nested_record(host, chunk).get("animation_deadline", host.get_preview_scheduler_tick())
	)
	host.advance_gameplay(maxf(
		0.0, animation_deadline - host.get_preview_scheduler_tick() - 0.001
	))
	check(not bool(chunk.call("get_preview_state").get("completion_ready", true)),
		"cutscene cannot finish before its saved absolute animation deadline")
	host.advance_gameplay(0.002)
	await process_frame
	var completed: Dictionary = chunk.call("get_preview_state")
	var completed_nested := completed.get("shelter_cutscene", {}) as Dictionary
	check(bool(completed.get("completion_ready", false))
			and str(completed.get("route_phase", "")) == "complete"
			and str(completed.get("last_outcome", "")) == "success",
		"both lanes atomically unlock generated-stretch completion")
	check(int(completed_nested.get("completion_count", 0)) == 1,
		"cutscene completion commits exactly once")
	check(not host.is_preview_cutscene_input_owned() and host.game_camera.current,
		"completion restores gameplay camera and input ownership")
	check(_party_visuals_restored(host),
		"completion restores each gameplay descendant's prior visibility")
	check(_presentation_count(chunk) == 0,
		"completion removes the presentation proxy")
	controller.call("process_authority")
	host.dialogue.dialogue_finished.emit()
	host.advance_gameplay(1.0)
	check(int(_nested_record(host, chunk).get("completion_count", 0)) == 1,
		"stale dialogue/deadline work cannot double-complete the cutscene")


func _verify_fresh_mid_dialogue_restore(source_pair: Dictionary) -> void:
	var snapshot: Dictionary = source_pair.get("mid_dialogue_snapshot", {})
	check(not snapshot.is_empty(), "mid-dialogue fixture was captured for fresh restore")
	if snapshot.is_empty():
		return
	var fresh_pair := await _boot_pair(false)
	_restore(fresh_pair, snapshot)
	var host: CutsceneHost = fresh_pair.host
	var chunk: Node = fresh_pair.chunk
	check(str(chunk.call("get_preview_state").get("route_phase", ""))
			== "shelter_cutscene"
			and _presentation_count(chunk) == 1
			and host.is_preview_cutscene_input_owned(),
		"fresh presenter reconstructs the saved mid-dialogue cutscene")
	check(host.dialogue.active and host.dialogue.say_invocations == 0,
		"fresh restore uses DialogueBox snapshot content without requeueing lines")
	check(_dialogue_completion_connection_count(host.dialogue) == 1,
		"fresh presenter reconnects one completion callback")
	await _cleanup_pair(fresh_pair)


func _verify_legacy_completed_migration(pair: Dictionary) -> void:
	var host: CutsceneHost = pair.host
	var chunk: Node = pair.chunk
	var runtime_key := str(chunk.call("_generated_runtime_authority_key"))
	var legacy := (
		host.get_preview_game_state().get_world_state(runtime_key, {}) as Dictionary
	).duplicate(true)
	legacy.erase("shelter2_stim_cutscene")
	var invocation_count := host.dialogue.say_invocations
	host.get_preview_game_state().set_world_state(runtime_key, legacy)
	chunk.call("on_game_state_snapshot_restored")
	host.dialogue.restore_state({"active": false, "cutscene_mode": false, "entries": []})
	chunk.call("on_dialogue_presenter_snapshot_restored")
	var migrated: Dictionary = chunk.call("get_preview_state")
	check(bool(migrated.get("completion_ready", false))
			and str((migrated.shelter_cutscene as Dictionary).get("phase", ""))
				== "complete",
		"legacy completed Shelter 2 save migrates to COMPLETE without replay")
	check(host.dialogue.say_invocations == invocation_count
			and _presentation_count(chunk) == 0
			and not host.is_preview_cutscene_input_owned(),
		"legacy migration creates no retroactive dialogue, proxy, or input lease")


func _boot_pair(roguelike: bool) -> Dictionary:
	var host := CutsceneHost.new()
	root.add_child(host)
	host.setup_for_test()
	var chunk := CHUNK_SCENE.instantiate()
	chunk.configure_chunk({
		"spec_path": SPEC_PATH,
		"game_mode": "neutral",
		"food_test": "neutral",
		"roguelike": roguelike,
	})
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.get_preview_game_state().grid = GridWorld.from_data(chunk.call("get_grid_data"))
	chunk.call("reset_preview_state")
	await process_frame
	host.game_camera.make_current()
	return {"host": host, "chunk": chunk}


func _force_completed_shelter_transaction(chunk: Node) -> void:
	var transaction: Dictionary = chunk.call("_new_exit_shelter_transaction")
	transaction["phase"] = "complete"
	transaction["completed_tick"] = chunk.call("_hydraulic_sequence_tick")
	transaction["rest_plan"] = {}
	chunk.set("_exit_shelter_transaction", transaction)
	chunk.call("_apply_completed_exit_shelter_transaction", false)


func _capture(pair: Dictionary) -> Dictionary:
	var host: CutsceneHost = pair.host
	return {
		"scheduler": _json_round_trip(host.scheduler_snapshot()),
		"game_state": _json_round_trip(host.get_preview_game_state().serialize()),
		"dialogue": _json_round_trip(host.dialogue.snapshot_state()),
	}


func _restore(pair: Dictionary, snapshot: Dictionary) -> void:
	var host: CutsceneHost = pair.host
	var chunk: Node = pair.chunk
	host.restore_scheduler(snapshot.scheduler)
	host.get_preview_game_state().deserialize(snapshot.game_state)
	chunk.call("on_game_state_snapshot_restored")
	host.dialogue.restore_state(snapshot.dialogue)
	chunk.call("on_dialogue_presenter_snapshot_restored")
	host.call("_sync_scheduler_animations")


func _nested_record(host: CutsceneHost, chunk: Node) -> Dictionary:
	var runtime_key := str(chunk.call("_generated_runtime_authority_key"))
	var outer: Variant = host.get_preview_game_state().get_world_state(runtime_key, {})
	if not (outer is Dictionary):
		return {}
	var nested: Variant = (outer as Dictionary).get("shelter2_stim_cutscene", {})
	return (nested as Dictionary).duplicate(true) if nested is Dictionary else {}


func _controller(chunk: Node) -> RefCounted:
	var value: Variant = chunk.get("_shelter2_stim_cutscene_controller")
	return value as RefCounted if value is RefCounted else null


func _presentation_count(chunk: Node) -> int:
	var count := 0
	for child in chunk.get_children():
		if bool(child.get_meta("presentation_only", false)) \
				and child.name == "Shelter2AsterStimCutscene":
			count += 1
	return count


func _all_party_visuals_hidden(host: CutsceneHost) -> bool:
	for character_id in PARTY_IDS:
		var character := host.characters.get(character_id) as FakeCharacter
		if character == null or not character.visible \
				or character.mesh.visible or character.label.visible:
			return false
	return true


func _party_visuals_restored(host: CutsceneHost) -> bool:
	for character_id in PARTY_IDS:
		var character := host.characters.get(character_id) as FakeCharacter
		if character == null or not character.visible or not character.mesh.visible:
			return false
	return not (host.characters["peris"] as FakeCharacter).label.visible \
		and (host.characters["aster"] as FakeCharacter).label.visible \
		and (host.characters["endo"] as FakeCharacter).label.visible


func _assert_recorded_dialogue_matches_authoring(dialogue: RecordingDialogue) -> void:
	check(dialogue.entries.size() == EXPECTED_DIALOGUE_KEYS.size(),
		"dialogue presenter receives exactly three lines")
	for index in mini(dialogue.entries.size(), EXPECTED_DIALOGUE_KEYS.size()):
		var key := EXPECTED_DIALOGUE_KEYS[index]
		var line := DialogueData.get_line(key)
		var entry := dialogue.entries[index]
		check(str(entry.get("text", "")) == line.text
				and str(entry.get("speaker", "")) == line.speaker
				and str(entry.get("style", "")) == line.style
				and bool(entry.get("wait_for_input", false)) == line.wait,
			"queued line %d exactly matches DialogueData key %s" % [index + 1, key])


func _dialogue_completion_connection_count(dialogue: RecordingDialogue) -> int:
	return dialogue.get_signal_connection_list("dialogue_finished").size()


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _cleanup_pair(pair: Dictionary) -> void:
	var host: Node = pair.get("host", null)
	if host != null and is_instance_valid(host):
		var chunk: Node = pair.get("chunk", null)
		if chunk != null and is_instance_valid(chunk):
			chunk.call("detach_chunk_host")
		host.queue_free()
	await process_frame


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
