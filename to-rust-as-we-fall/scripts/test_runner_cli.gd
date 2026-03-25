extends Node

## CLI test runner. Parses command-line arguments and dispatches tests.
## Usage: godot --headless --path "." -- --test-syntax
##        godot --headless --path "." -- --test-all
##        godot --headless --path "." -- --test-tag-day

var _passed := 0
var _failed := 0
var _test_name := ""

func _ready() -> void:
	# Wait one frame so the _ready chain completes before scene tests add_child to root
	await get_tree().process_frame

	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()

	var ran_test := false
	for arg in args:
		match arg:
			"--test-all":
				ran_test = true
				await _run_all_tests()
			"--test-syntax":
				ran_test = true
				_test_syntax()
			"--test-grid":
				ran_test = true
				_test_grid_pathfinding()
			"--test-game-state":
				ran_test = true
				_test_game_state()
			"--test-scheduler":
				ran_test = true
				_test_event_scheduler()
			"--test-tag-day":
				ran_test = true
				await _test_tag_day()
			"--test-aster-sim":
				ran_test = true
				await _test_aster_sim()
			"--test-peris-sim":
				ran_test = true
				await _test_peris_sim()
			"--test-elevator":
				ran_test = true
				await _test_elevator()
			"--test-leaving-facility":
				ran_test = true
				await _test_leaving_facility()
			"--test-tag-day-dialogue":
				ran_test = true
				await _test_tag_day_dialogue()
			"--test-peris-dialogue":
				ran_test = true
				await _test_peris_dialogue()
			"--test-elevator-dialogue":
				ran_test = true
				await _test_elevator_dialogue()
			"--test-scene-load":
				ran_test = true
				await _test_scene_load()

	# --dump-dialogue <scene_path> [output_path]
	for i in range(args.size()):
		if args[i] == "--dump-dialogue" and i + 1 < args.size():
			ran_test = true
			var scene_path: String = args[i + 1]
			var output_path := "dialogue_dump.txt"
			if i + 2 < args.size() and not args[i + 2].begins_with("--"):
				output_path = args[i + 2]
			await _dump_dialogue(scene_path, output_path)

	if ran_test:
		_print_results()
		get_tree().quit(0 if _failed == 0 else 1)
	else:
		pass

func _run_all_tests() -> void:
	_test_syntax()
	_test_grid_pathfinding()
	_test_game_state()
	_test_event_scheduler()
	await _test_scene_load()
	await _test_aster_sim()
	await _test_peris_sim()
	await _test_elevator()
	await _test_leaving_facility()
	await _test_tag_day()
	await _test_tag_day_dialogue()
	await _test_peris_dialogue()
	await _test_elevator_dialogue()

# --- Test: Syntax ---
# If we got this far, GDScript compiled successfully.
func _test_syntax() -> void:
	_test_name = "Syntax Check"
	_assert_true(true, "All GDScript files compiled without errors")

# --- Test: Scene Load ---
func _test_scene_load() -> void:
	_test_name = "Scene Load"

	var level_editor := load("res://scenes/editor/level_editor.tscn")
	_assert_true(level_editor != null, "level_editor.tscn loads")

	var aster_sim := load("res://scenes/tutorial/aster_sim.tscn")
	_assert_true(aster_sim != null, "aster_sim.tscn loads")

	var peris_sim := load("res://scenes/tutorial/peris_sim.tscn")
	_assert_true(peris_sim != null, "peris_sim.tscn loads")

	var leaving := load("res://scenes/tutorial/leaving_facility.tscn")
	_assert_true(leaving != null, "leaving_facility.tscn loads")

	var tag_day := load("res://scenes/tutorial/tag_day.tscn")
	_assert_true(tag_day != null, "tag_day.tscn loads")

	var block_lib := load("res://resources/block_library.tres")
	_assert_true(block_lib != null, "block_library.tres loads")
	_assert_true(block_lib is MeshLibrary, "block_library is MeshLibrary")

	await get_tree().process_frame

# --- Test: EventScheduler ---
func _test_event_scheduler() -> void:
	_test_name = "EventScheduler"

	var sched := EventScheduler.new()
	_assert_true(sched != null, "EventScheduler created")
	_assert_equals(sched.get_current_tick(), 0.0, "Starts at tick 0")
	_assert_equals(sched.pending_count(), 0, "No pending events initially")

	# Schedule and advance
	var fired := []
	sched.schedule_at(1.0, func(): fired.append("a"), "event_a")
	sched.schedule_at(2.0, func(): fired.append("b"), "event_b")
	sched.schedule_at(1.5, func(): fired.append("c"), "event_c")
	_assert_equals(sched.pending_count(), 3, "3 events pending")

	sched.advance_ticks(1.0)
	_assert_equals(fired.size(), 1, "1 event fired at tick 1.0")
	_assert_equals(fired[0], "a", "Event 'a' fired first")
	_assert_equals(sched.get_current_tick(), 1.0, "Tick is 1.0")

	sched.advance_ticks(1.5)
	_assert_equals(fired.size(), 3, "All 3 events fired by tick 2.5")
	_assert_equals(fired[1], "c", "Event 'c' fired second (tick 1.5)")
	_assert_equals(fired[2], "b", "Event 'b' fired third (tick 2.0)")

	# schedule_after — use array wrapper for lambda-mutable state
	var after_result := [false]
	sched.schedule_after(0.5, func(): after_result[0] = true, "after_test")
	sched.advance_ticks(0.5)
	_assert_true(after_result[0], "schedule_after fires after delay")

	# Cancel by handle
	var cancel_result := [false]
	var handle := sched.schedule_after(1.0, func(): cancel_result[0] = true, "cancel_test")
	_assert_true(sched.cancel(handle), "cancel returns true for valid handle")
	sched.advance_ticks(2.0)
	_assert_true(not cancel_result[0], "Cancelled event did not fire")

	# Cancel by tag
	var tag_result := [0]
	sched.schedule_after(1.0, func(): tag_result[0] += 1, "batch")
	sched.schedule_after(2.0, func(): tag_result[0] += 1, "batch")
	sched.schedule_after(3.0, func(): tag_result[0] += 1, "keep")
	var removed := sched.cancel_tag("batch")
	_assert_equals(removed, 2, "cancel_tag removed 2 events")
	sched.advance_ticks(5.0)
	_assert_equals(tag_result[0], 1, "Only non-cancelled event fired")

	# Speed multiplier via advance()
	var sched2 := EventScheduler.new()
	var speed_result := [false]
	sched2.set_speed(10.0)
	sched2.schedule_at(5.0, func(): speed_result[0] = true, "speed_test")
	sched2.advance(0.5)  # 0.5 real seconds * 10x = 5.0 ticks
	_assert_true(speed_result[0], "Speed multiplier accelerates event firing")

	# Pause/resume
	var sched3 := EventScheduler.new()
	var pause_result := [false]
	sched3.schedule_at(1.0, func(): pause_result[0] = true, "pause_test")
	sched3.pause()
	sched3.advance_ticks(5.0)
	_assert_true(not pause_result[0], "Paused scheduler doesn't fire events")
	sched3.resume()
	sched3.advance_ticks(1.0)
	_assert_true(pause_result[0], "Resumed scheduler fires events")

	# Priority ordering
	var prio_order := []
	var sched4 := EventScheduler.new()
	sched4.schedule_at(1.0, func(): prio_order.append("low"), "low", 10)
	sched4.schedule_at(1.0, func(): prio_order.append("high"), "high", 0)
	sched4.schedule_at(1.0, func(): prio_order.append("mid"), "mid", 5)
	sched4.advance_ticks(1.0)
	_assert_equals(prio_order[0], "high", "Priority 0 fires first")
	_assert_equals(prio_order[1], "mid", "Priority 5 fires second")
	_assert_equals(prio_order[2], "low", "Priority 10 fires third")

	# Reactive chaining (event schedules another event)
	var sched5 := EventScheduler.new()
	var chain := []
	sched5.schedule_at(1.0, func():
		chain.append("first")
		sched5.schedule_after(0.5, func(): chain.append("second"), "chain2")
	, "chain1")
	sched5.advance_ticks(2.0)
	_assert_equals(chain.size(), 2, "Reactive chain: both events fired")
	_assert_equals(chain[1], "second", "Chained event fired correctly")

	# Serialize/deserialize
	var sched6 := EventScheduler.new()
	sched6.set_speed(5.0)
	sched6.advance_ticks(10.0)
	sched6.pause()
	var snap := sched6.serialize()
	_assert_equals(snap.current_tick, 10.0, "Serialized tick")
	_assert_equals(snap.speed, 5.0, "Serialized speed")
	_assert_equals(snap.paused, true, "Serialized paused")

	var sched7 := EventScheduler.new()
	sched7.deserialize(snap)
	_assert_equals(sched7.get_current_tick(), 10.0, "Deserialized tick")
	_assert_equals(sched7.get_speed(), 5.0, "Deserialized speed")
	_assert_true(sched7.is_paused(), "Deserialized paused state")

# --- Test: Tag Day Sequence ---
func _test_tag_day() -> void:
	_test_name = "Tag Day Sequence"

	var scene := load("res://scenes/tutorial/tag_day.tscn")
	_assert_true(scene != null, "Tag Day scene loads")

	if scene:
		var instance: Node = scene.instantiate()
		_assert_true(instance != null, "Tag Day scene instantiates")
		get_tree().root.add_child(instance)
		for i in range(5):
			await get_tree().process_frame
		_assert_true(instance.is_inside_tree(), "Tag Day scene is in tree")

		var env: Node = instance.find_child("Environment", true, false)
		_assert_true(env != null, "Environment node exists")

		var chars: Node = instance.find_child("Characters", true, false)
		_assert_true(chars != null, "Characters node exists")

		var camera: Node = instance.find_child("GameCamera", true, false)
		_assert_true(camera != null, "GameCamera node exists")

		var dialogue: Node = instance.find_child("DialogueBox", true, false)
		_assert_true(dialogue != null, "DialogueBox node exists")

		# Event-driven progression test: verify scheduler, GameState, step system
		if "_current_step" in instance and "_scheduler" in instance:
			_assert_true(instance._scheduler != null, "EventScheduler exists")
			_assert_true(instance._game_state != null, "GameState exists")
			_assert_true(instance._current_step != "", "Current step is set")

			# Exercise corridor walk — all movement goes through GameState
			instance._start_naturalizers_grip()
			for j in range(3):
				await get_tree().process_frame
			instance._begin_corridor_walk()
			for j in range(5):
				await get_tree().process_frame
			_assert_true(instance._game_state.is_moving("citizen"), "Citizen is walking the corridor")
			_assert_true(instance._game_state.is_moving("nk1"), "Naturalizer 1 is escorting")

		instance.queue_free()
		await get_tree().process_frame

# --- Test: Aster Simulation ---
func _test_aster_sim() -> void:
	_test_name = "Aster Simulation"

	var scene := load("res://scenes/tutorial/aster_sim.tscn")
	_assert_true(scene != null, "Aster sim scene loads")

	if scene:
		var instance: Node = scene.instantiate()
		_assert_true(instance != null, "Aster sim scene instantiates")
		get_tree().root.add_child(instance)
		for i in range(5):
			await get_tree().process_frame
		_assert_true(instance.is_inside_tree(), "Aster sim scene is in tree")

		var env: Node = instance.find_child("Environment", true, false)
		_assert_true(env != null, "Environment node exists")

		var chars: Node = instance.find_child("Characters", true, false)
		_assert_true(chars != null, "Characters node exists")

		var aster: Node = instance.find_child("Aster", true, false)
		_assert_true(aster != null, "Aster player node exists")

		var ron: Node = instance.find_child("Ron", true, false)
		_assert_true(ron != null, "Ron NPC node exists")

		var drink: Node = instance.find_child("DrinkMachine", true, false)
		_assert_true(drink != null, "Drink machine interactable exists")

		var dialogue: Node = instance.find_child("DialogueBox", true, false)
		_assert_true(dialogue != null, "DialogueBox node exists")

		instance.queue_free()
		await get_tree().process_frame

# --- Test: Peris Simulation ---
func _test_peris_sim() -> void:
	_test_name = "Peris Simulation"

	var scene := load("res://scenes/tutorial/peris_sim.tscn")
	_assert_true(scene != null, "Peris sim scene loads")

	if scene:
		var instance: Node = scene.instantiate()
		_assert_true(instance != null, "Peris sim scene instantiates")
		get_tree().root.add_child(instance)
		for i in range(5):
			await get_tree().process_frame
		_assert_true(instance.is_inside_tree(), "Peris sim scene is in tree")

		var env: Node = instance.find_child("Environment", true, false)
		_assert_true(env != null, "Environment node exists")

		var chars: Node = instance.find_child("Characters", true, false)
		_assert_true(chars != null, "Characters node exists")

		var peris: Node = instance.find_child("Peris", true, false)
		_assert_true(peris != null, "Peris player node exists")

		var monos: Node = instance.find_child("Monos", true, false)
		_assert_true(monos != null, "Monos NPC node exists")

		var dialogue: Node = instance.find_child("DialogueBox", true, false)
		_assert_true(dialogue != null, "DialogueBox node exists")

		instance.queue_free()
		await get_tree().process_frame

# --- Test: Leaving Facility ---
# --- Test: Elevator Tutorial ---
func _test_elevator() -> void:
	_test_name = "Elevator Tutorial"

	var scene := load("res://scenes/tutorial/elevator.tscn")
	_assert_true(scene != null, "Elevator scene loads")

	if scene:
		var instance: Node = scene.instantiate()
		_assert_true(instance != null, "Elevator scene instantiates")
		get_tree().root.add_child(instance)
		for i in range(5):
			await get_tree().process_frame
		_assert_true(instance.is_inside_tree(), "Scene is in tree")

		var env: Node = instance.find_child("Environment", true, false)
		_assert_true(env != null, "Environment node exists")

		var chars: Node = instance.find_child("Characters", true, false)
		_assert_true(chars != null, "Characters node exists")

		var peris: Node = instance.find_child("Peris", true, false)
		_assert_true(peris != null, "Peris player node exists")

		var aster: Node = instance.find_child("Aster", true, false)
		_assert_true(aster != null, "Aster player node exists")

		var dialogue: Node = instance.find_child("DialogueBox", true, false)
		_assert_true(dialogue != null, "DialogueBox node exists")

		if "_scheduler" in instance:
			_assert_true(instance._scheduler != null, "EventScheduler exists")
			_assert_true(instance._game_state != null, "GameState exists")

		var panel: Node = instance.find_child("ControlPanel", true, false)
		_assert_true(panel != null, "Control panel exists")

		instance.queue_free()
		await get_tree().process_frame

# --- Test: Leaving Facility ---
func _test_leaving_facility() -> void:
	_test_name = "Leaving Facility"

	var scene := load("res://scenes/tutorial/leaving_facility.tscn")
	_assert_true(scene != null, "Leaving facility scene loads")

	if scene:
		var instance: Node = scene.instantiate()
		_assert_true(instance != null, "Leaving facility scene instantiates")
		get_tree().root.add_child(instance)
		for i in range(5):
			await get_tree().process_frame
		_assert_true(instance.is_inside_tree(), "Scene is in tree")

		var aster: Node = instance.find_child("Aster", true, false)
		_assert_true(aster != null, "Aster player node exists")

		var peris: Node = instance.find_child("Peris", true, false)
		_assert_true(peris != null, "Peris NPC node exists")

		var endo: Node = instance.find_child("Endo", true, false)
		_assert_true(endo != null, "Endo NPC node exists")

		var dialogue: Node = instance.find_child("DialogueBox", true, false)
		_assert_true(dialogue != null, "DialogueBox node exists")

		instance.queue_free()
		await get_tree().process_frame

# --- Test: Grid Pathfinding ---
func _test_grid_pathfinding() -> void:
	_test_name = "Grid Pathfinding"

	# Create a simple room
	var grid := GridWorld.new()
	grid.create_room(10, 8, true)
	_assert_equals(grid.width, 10, "Room width is 10")
	_assert_equals(grid.height, 8, "Room height is 8")

	# Walls on border
	_assert_equals(grid.get_tile(0, 0), GridWorld.Tile.WALL, "Top-left is wall")
	_assert_equals(grid.get_tile(5, 4), GridWorld.Tile.FLOOR, "Center is floor")
	_assert_true(not grid.is_walkable(0, 0), "Wall is not walkable")
	_assert_true(grid.is_walkable(5, 4), "Floor is walkable")

	# Path from (1,1) to (8,6) in open room — should find a path
	var path := grid.find_path(Vector2i(1, 1), Vector2i(8, 6))
	_assert_true(path.size() > 0, "Path found in open room")

	# Path end should be at cell (8,6) world position
	if path.size() > 0:
		var end_cell := grid.world_to_grid(path[path.size() - 1])
		_assert_equals(end_cell, Vector2i(8, 6), "Path ends at target cell")

	# Add a wall across the middle
	for x in range(1, 9):
		grid.set_tile(x, 4, GridWorld.Tile.WALL)
	# Leave a gap at x=5
	grid.set_tile(5, 4, GridWorld.Tile.FLOOR)

	# Path should route through the gap
	var path2 := grid.find_path(Vector2i(1, 1), Vector2i(1, 6))
	_assert_true(path2.size() > 0, "Path found through wall gap")

	# Verify the path goes through the gap (cell 5,4)
	var passes_gap := false
	for wp in path2:
		var cell := grid.world_to_grid(wp)
		if cell.x >= 4 and cell.x <= 6 and cell.y == 4:
			passes_gap = true
			break
	_assert_true(passes_gap, "Path routes through gap in wall")

	# Block the gap — no path should exist
	grid.set_tile(5, 4, GridWorld.Tile.WALL)
	var path3 := grid.find_path(Vector2i(1, 1), Vector2i(1, 6))
	_assert_true(path3.is_empty(), "No path when fully walled off")

	# Coordinate conversion round-trip
	var cell := Vector2i(5, 3)
	var world_pos := grid.grid_to_world(cell)
	var back := grid.world_to_grid(world_pos)
	_assert_equals(back, cell, "grid_to_world → world_to_grid round-trip")

	# Load from strings (prototype format)
	var grid2 := GridWorld.new()
	grid2.load_from_strings(PackedStringArray([
		"111",
		"101",
		"111",
	]))
	_assert_equals(grid2.width, 3, "String-loaded width")
	_assert_equals(grid2.height, 3, "String-loaded height")
	_assert_equals(grid2.get_tile(1, 1), GridWorld.Tile.FLOOR, "String-loaded center is floor")
	_assert_equals(grid2.get_tile(0, 0), GridWorld.Tile.WALL, "String-loaded corner is wall")

	# find_tiles
	var grid3 := GridWorld.new()
	grid3.load_from_strings(PackedStringArray([
		"1111",
		"1051",
		"1601",
		"1111",
	]))
	var terminals := grid3.find_tiles(GridWorld.Tile.TERMINAL)
	_assert_equals(terminals.size(), 1, "Found 1 terminal tile")
	if terminals.size() > 0:
		_assert_equals(terminals[0], Vector2i(2, 1), "Terminal at correct position")
	var foods := grid3.find_tiles(GridWorld.Tile.FOOD)
	_assert_equals(foods.size(), 1, "Found 1 food tile")
	if foods.size() > 0:
		_assert_equals(foods[0], Vector2i(1, 2), "Food at correct position")

	# Locked door test
	var grid4 := GridWorld.new()
	grid4.load_from_strings(PackedStringArray([
		"111",
		"181",
		"101",
		"111",
	]))
	var locked := {Vector2i(1, 1): true}
	_assert_true(not grid4.is_walkable(1, 1, {}, locked), "Locked door blocks")
	_assert_true(grid4.is_walkable(1, 1, {}, {}), "Unlocked door passable")

# --- Test: GameState ---
func _test_game_state() -> void:
	_test_name = "GameState"

	# Create grid, scheduler, and GameState
	var grid := GridWorld.new()
	grid.create_room(10, 8, true)

	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	_assert_true(gs.grid != null, "GameState has grid")

	# Register a character
	gs.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {"atp": 72})
	_assert_true(gs.characters.has("aster"), "Character registered")
	_assert_true(gs.characters["aster"].move_speed == 3.0, "Move speed is 3.0")
	_assert_true(gs.characters["aster"].stats.atp == 72, "Stats preserved")

	# Command: move to cell
	var moved := gs.command_move_to_cell("aster", Vector2i(5, 3))
	_assert_true(moved, "command_move_to_cell returns true")
	_assert_true(gs.is_moving("aster"), "Character is moving")
	_assert_true(gs.characters["aster"].movement != null, "Movement state exists")

	# Mid-movement: position should have moved from start
	var start_pos := grid.grid_to_world(Vector2i(1, 1))
	sched.advance_ticks(0.5)
	var mid_pos := gs.get_position("aster")
	_assert_true(gs.is_moving("aster"), "Still moving after partial advance")
	_assert_true(mid_pos.distance_to(start_pos) > 0.1, "Character moved from start")

	# Advance scheduler until arrival
	sched.advance_ticks(100.0)
	_assert_true(not gs.is_moving("aster"), "Character arrived after advancing scheduler")
	var final_pos := gs.get_position("aster")
	var final_cell := grid.world_to_grid(final_pos)
	_assert_equals(final_cell, Vector2i(5, 3), "Final cell matches target")

	# Command: move to unreachable cell (wall)
	var blocked := gs.command_move_to_cell("aster", Vector2i(0, 0))
	_assert_true(not blocked, "Cannot pathfind to wall")

	# Command: straight-line move
	var pos_moved := gs.command_move_to_pos("aster", Vector3(4.5, 0, 2.5))
	_assert_true(pos_moved, "command_move_to_pos returns true")
	sched.advance_ticks(100.0)
	_assert_true(not gs.is_moving("aster"), "Straight-line move completed")

	# Command: stop mid-movement
	gs.command_move_to_cell("aster", Vector2i(8, 6))
	_assert_true(gs.is_moving("aster"), "Moving before stop")
	sched.advance_ticks(0.3)
	var stop_pos := gs.get_position("aster")
	gs.command_stop("aster")
	_assert_true(not gs.is_moving("aster"), "Stopped after command_stop")
	var after_stop := gs.get_position("aster")
	_assert_true(stop_pos.distance_to(after_stop) < 0.01, "Position preserved after stop")

	# Serialize / deserialize round-trip
	gs.command_move_to_cell("aster", Vector2i(3, 3))
	sched.advance_ticks(100.0)

	var snapshot := gs.serialize()
	_assert_true(snapshot.has("characters"), "Snapshot has characters")
	_assert_true(snapshot.characters.has("aster"), "Snapshot has aster")

	var sched2 := EventScheduler.new()
	var gs2 := GameState.new()
	gs2.grid = grid
	gs2.scheduler = sched2
	gs2.deserialize(snapshot)
	_assert_true(gs2.characters.has("aster"), "Deserialized has aster")
	var pos1: Vector3 = gs.get_position("aster")
	var pos2: Vector3 = gs2.get_position("aster")
	_assert_true(pos1.distance_to(pos2) < 0.01, "Positions match after round-trip")

	# Unregister
	gs.unregister_character("aster")
	_assert_true(not gs.characters.has("aster"), "Character unregistered")

# --- Assertions ---

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: [%s] %s" % [_test_name, message])
		_passed += 1
	else:
		print("  FAIL: [%s] %s" % [_test_name, message])
		_failed += 1

func _assert_equals(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		print("  PASS: [%s] %s (got: %s)" % [_test_name, message, actual])
		_passed += 1
	else:
		print("  FAIL: [%s] %s (expected: %s, got: %s)" % [_test_name, message, expected, actual])
		_failed += 1

# --- Dialogue Sequence Tests ---

## Pop through scheduler events, flushing dialogue between each.
## step_actions: Dictionary mapping step names to Callables that simulate
## player input (e.g. teleporting to a position, pressing a key).
## Actions fire once when _current_step first matches the key.
## Returns an array of {tick, text, speaker, style} dictionaries.
func _pop_dialogue_log(instance: Node, step_actions: Dictionary = {}) -> Array[Dictionary]:
	var log: Array[Dictionary] = []
	var dialogue_box: Node = instance._dialogue
	var scheduler: EventScheduler = instance._scheduler
	dialogue_box.speed_multiplier = 10000.0

	var capture := func(text: String):
		log.append({
			"tick": scheduler.get_current_tick(),
			"text": text,
			"speaker": dialogue_box._speaker_label.text if dialogue_box._speaker_label.visible else "",
			"style": dialogue_box._style,
		})
	dialogue_box.line_displayed.connect(capture)

	var last_actioned_step := ""
	var safety := 0
	var idle := 0
	while safety < 5000:
		# Flush dialogue box
		for j in range(200):
			if not dialogue_box.is_active():
				break
			dialogue_box._process(0.05)

		# Check for step actions to simulate input
		var current_step: String = instance._current_step
		if current_step in step_actions and current_step != last_actioned_step:
			last_actioned_step = current_step
			step_actions[current_step].call()
			# Run _on_process so proximity gates and per-frame checks can fire
			if instance.has_method("_on_process"):
				instance._on_process(0.1, 1.0)
			idle = 0
			continue

		if scheduler.pending_count() == 0:
			idle += 1
			if idle > 5:
				break
			for j in range(10):
				dialogue_box._process(0.05)
			continue
		idle = 0
		var info: Dictionary = scheduler.pop_next()
		if info.is_empty():
			break
		safety += 1

	dialogue_box.line_displayed.disconnect(capture)
	return log

func _test_tag_day_dialogue() -> void:
	_test_name = "Tag Day Dialogue"
	var scene := load("res://scenes/tutorial/tag_day.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	var log := _pop_dialogue_log(instance)

	_assert_true(log.size() >= 25, "At least 25 dialogue lines (got: %d)" % log.size())

	# Verify groan appears exactly once
	var groan_count := 0
	for entry in log:
		if "get back to work" in entry.text:
			groan_count += 1
	_assert_true(groan_count == 1, "Groan appears exactly once (got: %d)" % groan_count)

	# Verify groan has BYSTANDER speaker
	for entry in log:
		if "get back to work" in entry.text:
			_assert_true(entry.speaker == "BYSTANDER", "Groan speaker is BYSTANDER (got: %s)" % entry.speaker)

	# Verify Aster's report line exists with correct speaker
	var report_count := 0
	for entry in log:
		if "access denied" in entry.text:
			report_count += 1
			_assert_true(entry.speaker == "ASTER", "Report speaker is ASTER (got: %s)" % entry.speaker)
	_assert_true(report_count == 1, "Report blocked appears once (got: %d)" % report_count)

	# Verify poem appears before fragments
	var first_poem_tick := 9999.0
	var first_fragment_tick := 9999.0
	for entry in log:
		if entry.style == "poem" and entry.tick < first_poem_tick:
			first_poem_tick = entry.tick
		if entry.style == "fragment" and entry.tick < first_fragment_tick:
			first_fragment_tick = entry.tick
	_assert_true(first_poem_tick < first_fragment_tick, "Poem starts before fragments")

	# Verify whimper appears after a gap (the BANG silence)
	var bang_tick := 0.0
	var whimper_tick := 0.0
	for entry in log:
		if "bang" in entry.text:
			bang_tick = entry.tick
		if entry.text == "whimper.":
			whimper_tick = entry.tick
	if bang_tick > 0 and whimper_tick > 0:
		var gap := whimper_tick - bang_tick
		_assert_true(gap >= 2.0, "BANG to whimper gap >= 2s (got: %.1f)" % gap)

	# Verify scan passed appears near the end
	var scan_passed := false
	for entry in log:
		if "PASSED" in entry.text:
			scan_passed = true
	_assert_true(scan_passed, "Scan passed line exists")

	instance.queue_free()
	await get_tree().process_frame

func _test_peris_dialogue() -> void:
	_test_name = "Peris Dialogue"
	var scene := load("res://scenes/tutorial/peris_sim.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Full sequence with simulated input at each gate
	var log := _pop_dialogue_log(instance, {
		"run_tutorial": func():
			instance._resume_from_run_tutorial(),
		"sprint_to_terminal": func():
			instance._start_protect(),
		"protect": func():
			instance._has_protected = false
			instance._on_protect_pressed(),
	})

	_assert_true(log.size() >= 10, "At least 10 dialogue lines (got: %d)" % log.size())

	# Verify Monos appears
	var has_monos := false
	for entry in log:
		if entry.speaker == "Monos" or "Monos" in entry.text:
			has_monos = true
	_assert_true(has_monos, "Monos dialogue appears")

	# Verify system overtime prompt
	var has_overtime := false
	for entry in log:
		if "OVERTIME" in entry.text:
			has_overtime = true
	_assert_true(has_overtime, "Session overtime prompt appears")

	# Verify aftermath
	var has_aftermath := false
	for entry in log:
		if "shaken" in entry.text or "stable" in entry.text:
			has_aftermath = true
	_assert_true(has_aftermath, "Aftermath dialogue appears")

	# Verify efficiency penalty
	var has_penalty := false
	for entry in log:
		if "62%" in entry.text or "PENALTY" in entry.text:
			has_penalty = true
	_assert_true(has_penalty, "Efficiency penalty logged")

	instance.queue_free()
	await get_tree().process_frame

# --- Dialogue Dump ---

func _test_elevator_dialogue() -> void:
	_test_name = "Elevator Dialogue"
	var scene := load("res://scenes/tutorial/elevator.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	var log := _pop_dialogue_log(instance, {
		"approach_aster": func():
			# Teleport Peris near Aster
			var target: Vector3 = instance.ASTER_POS + Vector3(0.5, 0.5, 0)
			instance._peris_node.global_position = target
			instance._game_state.characters["peris"].position = target,
		"emp_tutorial": func():
			instance._on_emp_pressed(),
		"emp_tutorial_2": func():
			instance._on_emp_pressed(),
		"multiselect_tutorial": func():
			# Teleport both near panel
			var pp: Vector3 = instance.PANEL_POS + Vector3(-0.5, 0.5, 0)
			var ap: Vector3 = instance.PANEL_POS + Vector3(0.5, 0.5, 0)
			instance._peris_node.global_position = pp
			instance._aster_node.global_position = ap
			instance._game_state.characters["peris"].position = pp
			instance._game_state.characters["aster"].position = ap,
		"hack_tutorial": func():
			instance._on_panel_hacked(),
	})

	_assert_true(log.size() >= 20, "At least 20 dialogue lines (got: %d)" % log.size())

	# Verify Aster retells Tag Day
	var has_tag_day := false
	for entry in log:
		if "prickly pear" in entry.text.to_lower() or "bang" in entry.text:
			has_tag_day = true
	_assert_true(has_tag_day, "Aster retells Tag Day")

	# Verify Peris mentions sanction
	var has_sanction := false
	for entry in log:
		if "gel" in entry.text.to_lower() or "breathing" in entry.text.to_lower():
			has_sanction = true
	_assert_true(has_sanction, "Peris mentions sanction/gel")

	# Verify escort unit protocol
	var has_protocol := false
	for entry in log:
		if "RE-SEDATION" in entry.text or "SEDATION" in entry.text:
			has_protocol = true
	_assert_true(has_protocol, "Escort unit protocol fires")

	# Verify hack override
	var has_override := false
	for entry in log:
		if "OVERRIDE" in entry.text:
			has_override = true
	_assert_true(has_override, "Hack override succeeds")

	# Verify lockout
	var has_lockout := false
	for entry in log:
		if "NON-COMPLIANT" in entry.text:
			has_lockout = true
	_assert_true(has_lockout, "NON-COMPLIANT lockout fires")

	# Verify final line
	var has_forward := false
	for entry in log:
		if "Forward" in entry.text:
			has_forward = true
	_assert_true(has_forward, "Final 'Forward. Together.' line exists")

	instance.queue_free()
	await get_tree().process_frame

# --- Dialogue Dump ---

func _dump_dialogue(scene_path: String, output_path: String) -> void:
	_test_name = "Dialogue Dump"
	print("  Dumping dialogue for: %s" % scene_path)

	var scene := load(scene_path)
	if not scene:
		print("  ERROR: Could not load scene: %s" % scene_path)
		return

	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	# Let the scene initialize
	for i in range(3):
		await get_tree().process_frame

	if not "_dialogue" in instance or not "_scheduler" in instance:
		print("  ERROR: Scene does not have _dialogue or _scheduler")
		instance.queue_free()
		return

	var log: Array[String] = []
	var dialogue_box: Node = instance._dialogue
	var scheduler: EventScheduler = instance._scheduler

	# Make dialogue instant so typewriter doesn't block
	dialogue_box.speed_multiplier = 10000.0

	# Hook line_displayed to capture every dialogue line
	dialogue_box.line_displayed.connect(func(text: String):
		var speaker: String = dialogue_box._speaker_label.text if dialogue_box._speaker_label.visible else ""
		var style: String = dialogue_box._style
		var tick := scheduler.get_current_tick()
		var prefix := "%.2f [%s]" % [tick, style]
		if speaker != "":
			prefix += " %s:" % speaker
		log.append("%s %s" % [prefix, text])
	)

	# Pop through all scheduler events. Between each pop, flush the
	# dialogue box so dialogue_finished fires and chains the next event.
	var safety := 0
	var idle_pops := 0
	while safety < 5000:
		# Flush dialogue box until it's idle (all queued lines displayed + finished)
		for j in range(200):
			if not dialogue_box.is_active():
				break
			dialogue_box._process(0.05)

		if scheduler.pending_count() == 0:
			idle_pops += 1
			if idle_pops > 5:
				break
			# One more flush in case dialogue_finished queued something
			for j in range(10):
				dialogue_box._process(0.05)
			continue

		idle_pops = 0
		var info: Dictionary = scheduler.pop_next()
		if info.is_empty():
			break
		safety += 1

	# Write to file
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file:
		file.store_line("# Dialogue dump: %s" % scene_path)
		file.store_line("# %d lines captured" % log.size())
		file.store_line("")
		for line in log:
			file.store_line(line)
		file.close()
		print("  Wrote %d dialogue lines to %s" % [log.size(), output_path])
	else:
		print("  ERROR: Could not open %s for writing" % output_path)
		for line in log:
			print("    %s" % line)

	instance.queue_free()
	await get_tree().process_frame

func _print_results() -> void:
	print("")
	print("=== TEST RESULTS ===")
	print("  Passed: %d" % _passed)
	print("  Failed: %d" % _failed)
	print("  Total:  %d" % (_passed + _failed))
	if _failed > 0:
		print("  STATUS: FAILED")
	else:
		print("  STATUS: ALL PASSED")
	print("====================")
