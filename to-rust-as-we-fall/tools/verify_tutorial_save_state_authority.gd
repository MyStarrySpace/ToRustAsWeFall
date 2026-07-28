extends SceneTree

## Exercises the production TutorialSequence build_save_snapshot/apply_save_snapshot path. Unit coverage of
## GameState.deserialize alone is insufficient: the scene loader must actually pass authoritative mechanism and
## traversal phases through it and re-arm their remaining scheduler time.

const TutorialSequenceScript := preload("res://scripts/tutorial/tutorial_sequence.gd")
const ClimbvineScript := preload("res://scripts/game/objects/climbvine_return.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid := GridWorld.new()
	grid.create_room(14, 8, false)
	var lower := grid.grid_to_world(Vector2i(3, 3))
	var upper := grid.grid_to_world(Vector2i(10, 3))
	var render_lower := lower + Vector3(0.0, 0.0, 20.0)
	var render_upper := upper + Vector3(0.0, 8.0, 20.0)

	var source: TutorialSequence = _sequence_with_party(grid, lower, upper)
	var vine = ClimbvineScript.new()
	check(vine.configure(
		source._game_state, source._scheduler,
		lower, upper, render_lower, render_upper,
		{
			"return_id": "production_save_climbvine",
			"deployment_duration": 2.0,
			"climb_duration": 4.0,
		}
	), "source climbvine configures against the sequence-owned GameState")
	vine.set_group_provider(func() -> Array: return ["aster"])
	root.add_child(vine)
	await process_frame
	var upper_source := vine.get_upper_interactable() as Interactable
	var lower_source := vine.get_lower_interactable() as Interactable
	check(
		not vine.tend("peris") and vine.start_climb(["aster"]) == 0
			and not source._game_state.has_mechanism_phase(vine.get_mechanism_id()),
		"retired consequence helpers remain inert in the production save path"
	)
	source._game_state.snap_character_to("peris", upper)
	upper_source.active_character = "peris"
	check(
		upper_source._trigger(false),
		"exact upper Interactable and Peris body commit deployment"
	)
	source._scheduler.advance_ticks(1.0)
	var deployment_snapshot := _json_round_trip(source.build_save_snapshot())

	var loaded_deployment: TutorialSequence = _sequence_with_party(grid, lower, upper)
	loaded_deployment.apply_save_snapshot(deployment_snapshot)
	var deploy_state: Dictionary = loaded_deployment._game_state.get_mechanism_phase_state(
		&"production_save_climbvine:deployment"
	)
	check(
		StringName(str(deploy_state.get("phase", ""))) == &"deploying"
			and is_equal_approx(float(deploy_state.get("progress", 0.0)), 0.5),
		"production loader preserves a half-deployed authoritative phase"
	)
	loaded_deployment._scheduler.advance_ticks(1.0)
	check(
		StringName(str(loaded_deployment._game_state.get_mechanism_phase_state(
			&"production_save_climbvine:deployment"
		).get("phase", ""))) == &"deployed",
		"production loader completes deployment after only its saved remainder"
	)

	# Finish the source deployment, begin a real locked climb, and snapshot at its interpolated midpoint.
	source._scheduler.advance_ticks(1.0)
	source._game_state.snap_character_to("aster", lower)
	lower_source.active_character = "aster"
	check(
		lower_source._trigger(false),
		"exact lower Interactable and gathered body commit the climb"
	)
	source._scheduler.advance_ticks(2.0)
	var source_mid: Vector3 = source._game_state.get_position("aster")
	var traversal_snapshot := _json_round_trip(source.build_save_snapshot())

	var loaded_traversal: TutorialSequence = _sequence_with_party(grid, lower, upper)
	loaded_traversal.apply_save_snapshot(traversal_snapshot)
	var loaded_gs: GameState = loaded_traversal._game_state
	var loaded_traversal_state: Dictionary = loaded_gs.get_external_traversal_state("aster")
	check(
		loaded_gs.is_external_traversal_active("aster")
			and loaded_gs.get_position("aster").is_equal_approx(source_mid)
			and is_equal_approx(float(loaded_traversal_state.get("progress", 0.0)), 0.5),
		"production loader restores midpoint ownership, progress, and the traversal lock"
	)
	check(
		not loaded_gs.command_move_to_pos("aster", lower + Vector3(0.0, 0.0, 1.0)),
		"normal movement cannot exploit a production mid-climb reload"
	)
	loaded_gs.snap_character_to("aster", lower)
	check(
		loaded_gs.get_position("aster").is_equal_approx(source_mid),
		"scripted snapping cannot exploit a production mid-climb reload"
	)
	loaded_traversal._scheduler.advance_ticks(2.0)
	check(
		not loaded_gs.is_external_traversal_active("aster")
			and loaded_gs.get_position("aster").is_equal_approx(upper),
		"production-loaded climb finishes once at the saved destination"
	)

	vine.free()
	source.free()
	loaded_deployment.free()
	loaded_traversal.free()
	print("TUTORIAL SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _sequence_with_party(grid: GridWorld, lower: Vector3, upper: Vector3) -> TutorialSequence:
	var sequence: TutorialSequence = TutorialSequenceScript.new()
	sequence._scheduler = EventScheduler.new()
	sequence._game_state = GameState.new()
	sequence._game_state.scheduler = sequence._scheduler
	sequence._game_state.grid = grid
	sequence._game_state.register_character("aster", lower, 3.0, {"hp": 100.0})
	sequence._game_state.register_character("peris", upper, 3.0, {"hp": 100.0})
	return sequence


func _json_round_trip(snapshot: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(snapshot))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
