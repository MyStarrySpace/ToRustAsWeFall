# gdlint: disable=max-file-lines,max-returns,class-definitions-order
extends SceneTree

## Focused proof for DrawerStairProducer's six-index causal contract. The fixture exercises real
## Interactable receipts, reusable reversals, wrong-set cover, exact-set topology, midpoint
## same/fresh restore, accepted-before-owner recovery, and idempotent reset.

const ProducerScript := preload("res://scripts/game/objects/drawer_stair_producer.gd")
const STAIR_ID := "verify_open_files_indices"
const DURATION := 2.0

var checks := 0
var failures := 0
var scheduler: EventScheduler
var game_state: GameState
var grid: GridWorld
var host: Node3D
var producer
var orphan_capture: Dictionary = {}
var orphan_scheduler: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _build_fixture()
	_verify_initial_truth_and_receipt_gate()
	await _verify_wrong_index_cover_and_reversal()
	await _verify_exact_set_staircase()
	await _verify_midpoint_same_and_fresh_restore()
	await _verify_orphan_receipt_and_reset()
	print("DRAWER STAIR PRODUCER: %d checks, %d failures" % [checks, failures])
	host.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


func _build_fixture() -> void:
	scheduler = EventScheduler.new()
	game_state = GameState.new()
	game_state.scheduler = scheduler
	grid = _make_grid()
	game_state.grid = grid
	game_state.register_character("aster", _lever_position("a"), 3.0, {
		"hp": 100.0, "narrative_available": true})
	game_state.register_character("peris", _lever_position("f"), 3.0, {
		"hp": 100.0, "narrative_available": true})
	host = Node3D.new()
	root.add_child(host)
	producer = ProducerScript.new()
	host.add_child(producer)
	check(producer.configure(
		game_state,
		STAIR_ID,
		_index_specs(),
		_topology(),
		{
			"duration": DURATION,
			"interaction_radius": 1.25,
			"required_character": "aster",
			"stagger_fraction": 0.04,
		}
	), "configures one authoritative six-index set with three candidate columns")
	game_state.interactable_triggered.connect(_capture_orphan_seam)
	await process_frame
	await process_frame


func _verify_initial_truth_and_receipt_gate() -> void:
	var state: Dictionary = producer.get_state()
	check(str(state.get("contract", "")) == "drawer_stair_producer/v1"
			and (state.get("index_states", []) as Array).size() == 6,
		"QA state exposes the complete six-index contract")
	check(state.get("drawer_visual_source") ==
			"res://resources/models/generated-biomes/stacks_archive_spire/stacks_archive_spire_drawers.obj"
			and state.get("lever_visual_source") ==
			"res://resources/models/generated-biomes/stacks_archive_spire/stacks_archive_spire_terminal.obj",
		"drawers and catalog levers reuse portable Open Files assets")
	check(not bool(state.get("staircase_ready", true))
			and int(state.get("installed_link_count", -1)) == 0
			and grid.find_multi_level_path(Vector2i(2, 5), 0, Vector2i(11, 5), 1).is_empty(),
		"closed drawers provide no invisible inter-level route")
	check(not producer.toggle_index("a", "aster")
			and game_state.get_world_state(producer.authority_state_key(), null) == null,
		"actor-id helper cannot forge an index selection")
	var source: Interactable = producer.get_index_interactable("a")
	source.active_character = "peris"
	check(not source._trigger(false), "wrong character cannot spend the Aster index lever")
	game_state.snap_character_to("aster", _lever_position("f"))
	source.active_character = "aster"
	check(not source._trigger(false), "remote selected Aster cannot spend a physical lever")


func _verify_wrong_index_cover_and_reversal() -> void:
	check(_trigger_index("d"), "Aster physically toggles one wrong category")
	var begun: Dictionary = producer.get_index_state("d")
	check(begun.get("phase") == "extending"
			and int(begun.get("accepted_trigger_count", 0)) == 1
			and (begun.get("receipt_provenance", {}) as Dictionary).get("actor") == "aster",
		"authority commits phase, source count, actor, and provenance before animation")
	scheduler.advance_ticks(DURATION)
	var extended: Dictionary = producer.get_state()
	check(producer.is_index_extended("d")
			and not bool(extended.get("staircase_ready", true)),
		"a single wrong index extends without pretending to solve the stairs")
	check(not (extended.get("owned_cover_cells", []) as Array).is_empty()
			and int(extended.get("enabled_drawer_collision_count", 0)) > 0,
		"wrong activation remains useful physical cover with grid and collision truth")
	check(_trigger_index("d"), "the same exact lever is reusable and begins retraction")
	scheduler.advance_ticks(DURATION * 0.5)
	var midpoint: Dictionary = producer.get_index_state("d")
	check(midpoint.get("phase") == "retracting"
			and is_equal_approx(float(midpoint.get("progress", -1.0)), 0.5),
		"retraction owns a saved analytic midpoint instead of snapping at completion")
	check(_trigger_index("d"), "retoggling mid-retraction reverses from current progress")
	var reversed: Dictionary = producer.get_index_state("d")
	check(reversed.get("phase") == "extending"
			and is_equal_approx(float(reversed.get("progress_start", -1.0)), 0.5)
			and int(reversed.get("accepted_trigger_count", 0)) == 3,
		"mid-motion reversal preserves progress and monotonic receipt identity")
	scheduler.advance_ticks(DURATION * 0.5)
	check(producer.is_index_extended("d"),
		"reversed index reaches its original extended endpoint exactly once")
	check(_trigger_index("d"), "wrong index can retract after serving as cover")
	scheduler.advance_ticks(DURATION)
	check(not producer.is_index_extended("d"), "wrong cover fully retracts")


func _verify_exact_set_staircase() -> void:
	for index_id in ["a", "b", "c"]:
		check(_trigger_index(index_id), "solution index %s accepts its exact source" % index_id)
	scheduler.advance_ticks(DURATION * 0.5)
	check(not producer.is_staircase_ready()
			and not grid.can_traverse_link(Vector2i(5, 5), 0, 1),
		"partially extended solution remains visibly and topologically uncommitted")
	scheduler.advance_ticks(DURATION * 0.5)
	var solved: Dictionary = producer.get_state()
	check(bool(solved.get("staircase_ready", false))
			and solved.get("active_indices") == ["a", "b", "c"]
			and solved.get("solved_columns") == ["good"],
		"exact active set resolves only the deep-mid-shallow viable column")
	check(grid.can_traverse_link(Vector2i(5, 5), 0, 1)
			and not grid.can_traverse_link(Vector2i(8, 5), 0, 1)
			and not grid.can_traverse_link(Vector2i(10, 5), 0, 1),
		"only the matching non-rotten column installs its owned ramp")
	check(not grid.find_multi_level_path(
		Vector2i(2, 5), 0, Vector2i(11, 5), 1).is_empty(),
		"the completed physical selection creates a real multilevel path")
	check(_trigger_index("d"), "an extra category is a reversible useful mistake")
	check(not producer.is_staircase_ready()
			and not grid.can_traverse_link(Vector2i(5, 5), 0, 1),
		"wrong activation closes the solved link at commitment, not after animation")
	scheduler.advance_ticks(DURATION)
	check(not (producer.get_state().get("owned_cover_cells", []) as Array).is_empty(),
		"the invalid four-index set leaves tangible cover rather than a penalty toast")
	check(_trigger_index("d"), "retracting the extra category revises the model")
	scheduler.advance_ticks(DURATION)
	check(producer.is_staircase_ready()
			and grid.can_traverse_link(Vector2i(5, 5), 0, 1),
		"corrected active set restores the viable staircase")


func _verify_midpoint_same_and_fresh_restore() -> void:
	check(_trigger_index("c"), "solution index begins a reversible retraction")
	scheduler.advance_ticks(DURATION * 0.5)
	var saved_scheduler: Dictionary = _round_trip(scheduler.serialize()) as Dictionary
	var saved_state: Dictionary = _round_trip(game_state.serialize()) as Dictionary
	var saved_progress := float(producer.get_index_state("c").get("progress", -1.0))
	scheduler.advance_ticks(DURATION * 0.5)
	check(not producer.is_index_extended("c"), "discarded future reaches retracted endpoint")
	scheduler.clear()
	scheduler.deserialize(saved_scheduler)
	game_state.deserialize(saved_state)
	check(producer.on_game_state_snapshot_restored(), "same presenter accepts midpoint authority")
	producer.on_game_state_snapshot_restored()
	check(producer.get_index_state("c").get("phase") == "retracting"
			and is_equal_approx(
				float(producer.get_index_state("c").get("progress", -1.0)), saved_progress),
		"same-instance rollback retracts the discarded endpoint at exact progress")
	scheduler.advance_ticks(DURATION * 0.499)
	check(producer.get_index_state("c").get("phase") == "retracting",
		"double restore cannot finish before the saved deadline")
	scheduler.advance_ticks(DURATION * 0.001)
	check(not producer.is_index_extended("c"),
		"same presenter completes once at the original deadline")

	var fresh_scheduler := EventScheduler.new()
	fresh_scheduler.deserialize(saved_scheduler)
	var fresh_state := GameState.new()
	fresh_state.scheduler = fresh_scheduler
	fresh_state.grid = _make_grid()
	fresh_state.deserialize(saved_state)
	var fresh := ProducerScript.new()
	host.add_child(fresh)
	check(fresh.configure(
		fresh_state, STAIR_ID, _index_specs(), _topology(),
		{"duration": DURATION, "interaction_radius": 1.25,
			"required_character": "aster", "stagger_fraction": 0.04}),
		"fresh presenter configures after authoritative deserialize")
	await process_frame
	check(fresh.get_index_state("c").get("phase") == "retracting"
			and is_equal_approx(
				float(fresh.get_index_state("c").get("progress", -1.0)), saved_progress),
		"fresh presenter derives the same midpoint without scene-local animation state")
	fresh.on_game_state_snapshot_restored()
	fresh_scheduler.advance_ticks(DURATION * 0.5)
	check(not fresh.is_index_extended("c")
			and not fresh_state.grid.can_traverse_link(Vector2i(5, 5), 0, 1),
		"fresh restored remainder completes and leaves the incomplete set closed")
	fresh.queue_free()
	await process_frame


func _verify_orphan_receipt_and_reset() -> void:
	check(not orphan_capture.is_empty(),
		"signal-time fixture captures a spent lever before producer authority")
	var before_authority := orphan_capture.get("world_state", {}) as Dictionary
	check(not before_authority.has(producer.authority_state_key()),
		"accepted-before-owner snapshot contains no free drawer transition")
	scheduler.clear()
	scheduler.deserialize(orphan_scheduler)
	game_state.deserialize(orphan_capture)
	check(producer.on_game_state_snapshot_restored(),
		"orphan physical receipt restores as baseline without toggling")
	var orphan_source: Interactable = producer.get_index_interactable("d")
	check(not producer.is_index_extended("d") and orphan_source.is_interaction_enabled()
			and not bool(orphan_source.get("_used")),
		"orphan receipt explicitly rearms its exact source and grants no cover")
	check(_trigger_index("d"), "orphan count cannot wedge the reusable lever")
	scheduler.advance_ticks(DURATION)
	check(producer.is_index_extended("d"),
		"next real receipt toggles once after orphan recovery")
	check(producer.reset(&"focused_checkpoint"),
		"checkpoint reset publishes one authoritative baseline")
	var reset_state: Dictionary = producer.get_state()
	check(not bool(reset_state.get("staircase_ready", true))
			and int(reset_state.get("installed_link_count", -1)) == 0
			and int(reset_state.get("enabled_drawer_collision_count", -1)) == 0,
		"reset retracts links, cover, collision, and drawer presentation")
	check(not producer.reset(&"focused_checkpoint")
			and not producer.is_staircase_ready(),
		"repeated reset is an idempotent no-op")


func _capture_orphan_seam(source_id: String, _actor: String) -> void:
	if not orphan_capture.is_empty() or not source_id.ends_with(":d"):
		return
	orphan_capture = _round_trip(game_state.serialize())
	orphan_scheduler = _round_trip(scheduler.serialize())


func _trigger_index(index_id: String) -> bool:
	var source: Interactable = producer.get_index_interactable(index_id)
	game_state.snap_character_to("aster", _lever_position(index_id))
	source.active_character = "aster"
	return bool(source._trigger(false))


func _make_grid() -> GridWorld:
	var made := GridWorld.new()
	made.create_room(14, 10, true)
	made.set_level_count(2)
	made.level_height = 4.0
	made.allow_cell_region_on_level(Vector2i(1, 1), Vector2i(12, 8), 0)
	made.allow_cell_region_on_level(Vector2i(1, 1), Vector2i(12, 8), 1)
	return made


func _lever_position(index_id: String) -> Vector3:
	var ids := ["a", "b", "c", "d", "e", "f"]
	return Vector3(2.0 + float(ids.find(index_id)) * 1.5, 0.0, 2.0)


func _index_specs() -> Array[Dictionary]:
	var assignments := {
		"good": ["a", "b", "c"],
		"rotten": ["d", "e", "f"],
		"mixed": ["f", "a", "b"],
	}
	var columns_x := {"good": 5.0, "rotten": 8.0, "mixed": 10.0}
	var depths := {"a": 3.0, "b": 2.0, "c": 1.0,
		"d": 3.0, "e": 2.0, "f": 1.0}
	var tints := {
		"a": Color(0.2, 0.8, 0.9), "b": Color(0.3, 0.7, 0.85),
		"c": Color(0.4, 0.6, 0.8), "d": Color(0.3, 0.8, 0.55),
		"e": Color(0.4, 0.7, 0.5), "f": Color(0.5, 0.6, 0.45),
	}
	var specs: Array[Dictionary] = []
	for index_id in ["a", "b", "c", "d", "e", "f"]:
		var modules: Array[Dictionary] = []
		for column_id in ["good", "rotten", "mixed"]:
			var height := (assignments[column_id] as Array).find(index_id)
			if height < 0:
				continue
			var closed := Vector3(float(columns_x[column_id]), 0.45 + height * 1.0, 7.8)
			modules.append({
				"id": "%s_%s" % [column_id, index_id],
				"column": column_id,
				"category": index_id,
				"height": height,
				"closed_position": closed,
				"extended_position": closed + Vector3(0.0, 0.0, -float(depths[index_id])),
				"collision_size": Vector3(1.8, 0.65, float(depths[index_id]) + 0.4),
				"visual_scale": Vector3(1.8, 0.65, float(depths[index_id]) + 0.4),
				"tint": tints[index_id],
				"rotten": column_id == "rotten" and index_id == "e",
				"cover_cells": [[int(columns_x[column_id]), 6]],
			})
		specs.append({
			"index_id": index_id,
			"label": "INDEX %s" % index_id.to_upper(),
			"lever_data_position": _lever_position(index_id),
			"lever_render_position": _lever_position(index_id),
			"tint": tints[index_id],
			"drawer_modules": modules,
		})
	return specs


func _topology() -> Dictionary:
	return {
		"valid_active_sets": [["a", "b", "c"], ["d", "e", "f"]],
		"route_blocker_cells": [],
		"route_blocker_tag": "",
		"links": [
			{"column_id": "good", "cell": Vector2i(5, 5),
				"from_level": 0, "to_level": 1, "type": "ramp"},
			{"column_id": "rotten", "cell": Vector2i(8, 5),
				"from_level": 0, "to_level": 1, "type": "ramp"},
			{"column_id": "mixed", "cell": Vector2i(10, 5),
				"from_level": 0, "to_level": 1, "type": "ramp"},
		],
	}


func _round_trip(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % message)
		return
	failures += 1
	push_error("FAIL: %s" % message)
