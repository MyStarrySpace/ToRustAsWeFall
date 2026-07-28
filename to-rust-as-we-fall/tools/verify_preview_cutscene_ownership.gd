extends SceneTree

## Focused regression for TutorialSequence's reusable AnimationPlayer cutscene seam.
## The fixture intentionally owns no level/chunk behavior: it proves that presentation
## ownership cannot mutate GameState and can be reconstructed from portable timestamps.

const GameCameraScript := preload("res://scripts/ui/game_camera.gd")
const EPSILON := 0.001


class FakeCharacter:
	extends Node3D

	var char_id := "aster"
	var move_enabled := true
	var restore_calls := 0
	var mesh: MeshInstance3D
	var label: Label3D

	func _init() -> void:
		mesh = MeshInstance3D.new()
		mesh.name = "BodyMesh"
		mesh.mesh = BoxMesh.new()
		add_child(mesh)
		label = Label3D.new()
		label.name = "NameLabel"
		add_child(label)

	func is_move_enabled() -> bool:
		return move_enabled

	func restore_move_input_enabled(enabled: bool) -> void:
		move_enabled = enabled
		restore_calls += 1


class FakeSelection:
	extends Node

	var cancel_count := 0

	func cancel_command_hold() -> void:
		cancel_count += 1


class FakeTouchModes:
	extends Node

	var cancel_count := 0

	func _cancel_action_command_proxy() -> void:
		cancel_count += 1


class FakeHUD:
	extends Node

	var paused := false

	func set_paused(value: bool) -> void:
		paused = value


class FakeDialogue:
	extends Node

	signal dialogue_finished()

	var restored := false

	func snapshot_state() -> Dictionary:
		return {"restored": restored}

	func restore_state(snapshot: Dictionary) -> bool:
		restored = bool(snapshot.get("restored", false))
		return true

	func clear() -> void:
		restored = false

	func advance_ui_time(_delta_ticks: float) -> void:
		pass


class RestoreOrderProbe:
	extends Node

	var dialogue: FakeDialogue
	var calls: Array[String]

	func setup(dialogue_box: FakeDialogue, call_log: Array[String]) -> void:
		dialogue = dialogue_box
		calls = call_log

	func on_game_state_snapshot_restored() -> void:
		calls.append("game_state:%s" % str(dialogue.restored))

	func on_dialogue_presenter_snapshot_restored() -> void:
		calls.append("dialogue:%s" % str(dialogue.restored))


class CutsceneFixture:
	extends TutorialSequence

	var test_character: FakeCharacter
	var test_selection: FakeSelection
	var test_touch: FakeTouchModes
	var test_hud: FakeHUD
	var test_camera: Camera3D
	var pause_toggle_count := 0

	func _ready() -> void:
		# Tests install the exact minimal infrastructure; do not boot a full level.
		pass

	func setup_for_test(with_dialogue := false) -> void:
		_scheduler = EventScheduler.new()
		_ui_scheduler = EventScheduler.new()
		_game_state = GameState.new()
		_game_state.scheduler = _scheduler
		_game_state.register_character("aster", Vector3(2.0, 0.5, -1.0), 3.0)

		test_character = FakeCharacter.new()
		test_character.name = "Aster"
		add_child(test_character)
		_player = test_character
		_game_state_character_nodes["aster"] = test_character

		test_camera = GameCameraScript.new() as Camera3D
		test_camera.name = "GameCamera"
		add_child(test_camera)
		_camera = test_camera
		test_camera.set("target", test_character)

		test_selection = FakeSelection.new()
		test_selection.name = "SelectionController"
		test_selection.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(test_selection)
		_selection_controller = test_selection

		test_touch = FakeTouchModes.new()
		test_touch.name = "TouchModes"
		test_touch.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(test_touch)
		_touch_modes = test_touch

		test_hud = FakeHUD.new()
		test_hud.name = "GameHUD"
		test_hud.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(test_hud)
		if with_dialogue:
			_dialogue = FakeDialogue.new()
			_dialogue.name = "DialogueBox"
			add_child(_dialogue)

	func _chunk_host_hud() -> Node:
		return test_hud

	func _on_pause_toggled(is_paused: bool) -> void:
		pause_toggle_count += 1
		if is_paused:
			_scheduler.pause()
		else:
			_scheduler.resume()
		test_hud.set_paused(_scheduler.is_paused())


var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_camera_and_ownership()
	await _verify_character_visibility()
	await _verify_absolute_scheduler_animation()
	await _verify_dialogue_restore_order()
	print("PREVIEW CUTSCENE OWNERSHIP: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _spawn_fixture(with_dialogue := false) -> CutsceneFixture:
	var fixture := CutsceneFixture.new()
	root.add_child(fixture)
	fixture.setup_for_test(with_dialogue)
	return fixture


func _verify_camera_and_ownership() -> void:
	var fixture := _spawn_fixture()
	var camera := fixture.test_camera
	var character := fixture.test_character
	camera.set("follow_offset", Vector3(1.0, 11.0, 7.0))
	camera.set("_pan_offset", Vector3(2.0, 0.0, -3.0))
	camera.set("_view_yaw", 0.42)
	camera.set("_view_zoom", 1.35)
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(-0.4, 0.2, 0.0)),
		Vector3(8.0, 10.0, 12.0))
	camera.call("lock_to", Vector3(3.0, 1.0, -2.0), Vector3(1.0, 5.0, 4.0))
	var encoded := fixture.capture_preview_camera_state()
	var portable := _json_round_trip(encoded)
	check(not portable.is_empty() and fixture.valid_preview_camera_state(portable),
		"camera view survives a strict JSON round trip")
	check(str(portable.get("target_id", "")) == "aster",
		"camera target is encoded by stable character id, never Node reference")
	var invalid := portable.duplicate(true)
	invalid["unexpected"] = true
	check(not fixture.valid_preview_camera_state(invalid),
		"camera codec rejects non-schema fields")

	camera.set("follow_offset", Vector3.ONE)
	camera.set("_pan_offset", Vector3.ZERO)
	camera.set("_view_yaw", -1.0)
	camera.set("_view_zoom", 0.5)
	check(fixture.restore_preview_camera_state(portable),
		"portable camera state restores through GameCamera's presenter API")
	check((camera.get("follow_offset") as Vector3).is_equal_approx(Vector3(1.0, 11.0, 7.0))
			and (camera.get("_pan_offset") as Vector3).is_equal_approx(Vector3(2.0, 0.0, -3.0))
			and is_equal_approx(float(camera.get("_view_yaw")), 0.42)
			and is_equal_approx(float(camera.get("_view_zoom")), 1.35),
		"camera restore preserves follow, pan, orbit, and zoom framing")

	var state_before: Dictionary = fixture._game_state.characters.duplicate(true)
	var picking_before := fixture.get_viewport().physics_object_picking
	var cutscene_camera := Camera3D.new()
	cutscene_camera.name = "DedicatedCutsceneCamera"
	fixture.add_child(cutscene_camera)
	camera.make_current()
	var selection_mode := fixture.test_selection.process_mode
	var touch_mode := fixture.test_touch.process_mode
	var hud_mode := fixture.test_hud.process_mode
	check(fixture.begin_preview_cutscene_ownership("shelter_2.stim", cutscene_camera, portable),
		"named owner acquires the dedicated cutscene camera")
	check(fixture.begin_preview_cutscene_ownership("shelter_2.stim", cutscene_camera, portable),
		"repeating begin for the same owner is idempotent")
	check(not fixture.begin_preview_cutscene_ownership("another.cutscene", cutscene_camera, portable),
		"a second owner cannot steal an active cutscene lease")
	check(fixture.is_preview_cutscene_input_owned("shelter_2.stim")
			and not fixture.is_preview_cutscene_input_owned("another.cutscene"),
		"query guard identifies the exact active owner")
	check(not character.move_enabled
			and fixture.test_selection.process_mode == Node.PROCESS_MODE_DISABLED
			and fixture.test_touch.process_mode == Node.PROCESS_MODE_DISABLED
			and fixture.test_hud.process_mode == Node.PROCESS_MODE_DISABLED
			and not camera.is_processing()
			and not camera.is_processing_unhandled_input()
			and cutscene_camera.is_current()
			and not fixture.get_viewport().physics_object_picking,
		"lease gates movement, selection, touch, HUD, world picking, and gameplay camera")
	check(fixture.test_selection.cancel_count == 1 and fixture.test_touch.cancel_count == 1,
		"lease cancels in-progress desktop and touch command gestures exactly once")
	check(fixture._game_state.characters == state_before,
		"input ownership does not stop, move, or otherwise mutate GameState")

	var pause_event := InputEventAction.new()
	pause_event.action = &"pause"
	pause_event.pressed = true
	fixture._unhandled_input(pause_event)
	check(fixture._scheduler.is_paused() and fixture.test_hud.paused
			and fixture.pause_toggle_count == 1,
		"Space action still reaches planning pause while gameplay HUD input is gated")
	fixture._unhandled_input(pause_event)
	check(not fixture._scheduler.is_paused() and not fixture.test_hud.paused
			and fixture.pause_toggle_count == 2,
		"Space action resumes the cutscene scheduler through the same pause contract")
	Input.action_press("fast_forward")
	check(is_equal_approx(fixture._compute_speed(), 10.0),
		"F fast-forward remains an Input-state speed policy during ownership")
	Input.action_release("fast_forward")

	check(not fixture.end_preview_cutscene_ownership("another.cutscene"),
		"wrong owner cannot release the active lease")
	check(fixture.end_preview_cutscene_ownership("shelter_2.stim"),
		"named owner releases its lease")
	check(fixture.end_preview_cutscene_ownership("shelter_2.stim"),
		"repeating end for the same owner is idempotent")
	check(character.move_enabled
			and fixture.test_selection.process_mode == selection_mode
			and fixture.test_touch.process_mode == touch_mode
			and fixture.test_hud.process_mode == hud_mode
			and camera.is_current()
			and fixture.get_viewport().physics_object_picking == picking_before,
		"release restores exact input modes, movement gate, camera, and world picking")
	check(fixture._game_state.characters == state_before,
		"release also leaves authoritative character state untouched")
	await _discard(fixture)


func _verify_character_visibility() -> void:
	var fixture := _spawn_fixture()
	var character := fixture.test_character
	character.visible = true
	character.mesh.visible = false
	character.label.visible = true
	var presence_before: Dictionary = fixture._game_state.characters.duplicate(true)
	var saved := _json_round_trip(
		fixture.capture_preview_character_visual_visibility(["aster"]))
	check(saved.has("aster") and (saved.aster as Dictionary).size() == 2,
		"visual visibility snapshot is JSON-safe and names drawable descendants")
	check(fixture.set_preview_character_visual_visibility(["aster"], false)
			and not character.mesh.visible and not character.label.visible,
		"presenter helper hides character mesh and label descendants")
	check(character.visible and fixture._game_state.characters == presence_before,
		"hiding descendants preserves root presence, fog identity, and GameState")
	check(fixture.restore_preview_character_visual_visibility(saved)
			and not character.mesh.visible and character.label.visible,
		"visibility restore recovers each descendant's distinct prior state")
	check(character.visible and fixture._game_state.characters == presence_before,
		"visibility restore never toggles the character root or authoritative presence")
	await _discard(fixture)


func _verify_absolute_scheduler_animation() -> void:
	var fixture := _spawn_fixture()
	var proxy := Node3D.new()
	proxy.name = "AnimatedProxy"
	fixture.add_child(proxy)
	var player := AnimationPlayer.new()
	player.name = "CutsceneAnimationPlayer"
	fixture.add_child(player)
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 4.0
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("AnimatedProxy:position:x"))
	animation.track_insert_key(track, 0.0, 0.0)
	animation.track_insert_key(track, 4.0, 8.0)
	library.add_animation("stim", animation)
	player.add_animation_library("", library)

	fixture._scheduler.advance_ticks(5.0)
	var completion := {"count": 0}
	var on_finished := func() -> void: completion.count = int(completion.count) + 1
	check(fixture.play_preview_scheduler_animation_at(player, "stim", 3.0, on_finished),
		"authored animation starts from a supplied absolute scheduler tick")
	check(is_equal_approx(player.current_animation_position, 2.0)
			and is_equal_approx(proxy.position.x, 4.0),
		"late attachment samples the exact elapsed property-track frame")
	fixture._scheduler.advance_ticks(1.0)
	fixture._sync_scheduler_animations()
	var saved_position := player.current_animation_position
	fixture.stop_preview_scheduler_animation(player)
	check(fixture.play_preview_scheduler_animation_at(player, "stim", 3.0, on_finished)
			and is_equal_approx(player.current_animation_position, saved_position)
			and is_equal_approx(proxy.position.x, 6.0),
		"stop/rebuild from saved start_tick resumes without timeline drift")
	fixture._scheduler.advance_ticks(1.0)
	fixture._sync_scheduler_animations()
	check(int(completion.count) == 1 and is_equal_approx(proxy.position.x, 8.0),
		"absolute-tick animation reaches its final frame and callback exactly once")
	fixture._sync_scheduler_animations()
	check(int(completion.count) == 1,
		"completed scheduler animation cannot fire its callback twice")
	await _discard(fixture)


func _verify_dialogue_restore_order() -> void:
	var fixture := _spawn_fixture(true)
	var dialogue := fixture._dialogue as FakeDialogue
	var call_log: Array[String] = []
	var probe := RestoreOrderProbe.new()
	probe.name = "RestoreOrderProbe"
	probe.setup(dialogue, call_log)
	fixture.add_child(probe)
	var snapshot := fixture.build_save_snapshot()
	snapshot["dialogue"] = {"restored": true}
	fixture.apply_save_snapshot(snapshot)
	check(call_log == ["game_state:false", "dialogue:true"],
		"post-dialogue hook runs after GameState presenter restore and DialogueBox restore")
	await _discard(fixture)


func _discard(fixture: CutsceneFixture) -> void:
	if fixture != null and is_instance_valid(fixture):
		fixture.queue_free()
	await process_frame


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
