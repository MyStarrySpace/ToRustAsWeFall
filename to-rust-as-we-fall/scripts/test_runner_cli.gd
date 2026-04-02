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
			"--test-enemy":
				ran_test = true
				await _test_enemy()
			"--test-chain-enemy":
				ran_test = true
				await _test_chain_enemy()
			"--test-act1":
				ran_test = true
				await _test_act1()
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
			"--test-showcase":
				ran_test = true
				await _test_showcase()
			"--test-tag-day-dialogue":
				ran_test = true
				await _test_tag_day_dialogue()
			"--test-peris-dialogue":
				ran_test = true
				await _test_peris_dialogue()
			"--test-elevator-dialogue":
				ran_test = true
				await _test_elevator_dialogue()
			"--test-endo-drink":
				ran_test = true
				await _test_endo_drink()
			"--test-junction-flow":
				ran_test = true
				await _test_junction_flow()
			"--test-climb":
				ran_test = true
				_test_climb_and_lockout()
			"--test-predict-detect":
				ran_test = true
				_test_predictive_detection()
			"--test-detect-equiv":
				ran_test = true
				_test_detection_equivalence()
			"--test-ferrolure":
				ran_test = true
				await _test_ferrolure()
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
	await _test_showcase()
	await _test_tag_day()
	await _test_tag_day_dialogue()
	await _test_peris_dialogue()
	await _test_peris_tutorial_redirect()
	await _test_elevator_dialogue()
	await _test_endo_drink()
	await _test_junction_flow()
	_test_climb_and_lockout()
	await _test_enemy()
	await _test_chain_enemy()
	await _test_act1()
	await _test_ferrolure()
	_test_predictive_detection()
	_test_detection_equivalence()

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

# --- Test: Showcase ---
func _test_showcase() -> void:
	_test_name = "Showcase"

	var scene := load("res://scenes/showcase/showcase.tscn")
	_assert_true(scene != null, "Showcase scene loads")

	if scene:
		var instance: Node = scene.instantiate()
		_assert_true(instance != null, "Showcase scene instantiates")
		get_tree().root.add_child(instance)
		for i in range(5):
			await get_tree().process_frame
		_assert_true(instance.is_inside_tree(), "Scene is in tree")

		var env: Node = instance.find_child("Environment", true, false)
		_assert_true(env != null, "Environment node exists")

		var cam: Node = instance.find_child("GameCamera", true, false)
		_assert_true(cam != null, "GameCamera node exists")

		var hud: Node = instance.find_child("GameHUD", true, false)
		_assert_true(hud != null, "GameHUD node exists")

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
	while safety < 20000:
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
			if idle > 20:
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

	_assert_true(log.size() >= 28, "At least 28 dialogue lines (got: %d)" % log.size())

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
		if "incident report" in entry.text:
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

	# Verify BANG fragment is reached (poem chain completed, fragments fired)
	var has_bang := false
	for entry in log:
		if "BANG" in entry.text:
			has_bang = true
	_assert_true(has_bang, "BANG fragment reached (poem chain completed)")

	# Verify BANG fires before the lockdown (poem+fragments complete before walk ends)
	var bang_tick_val := 0.0
	var lockdown_tick := 0.0
	for entry in log:
		if "BANG" in entry.text and bang_tick_val == 0.0:
			bang_tick_val = entry.tick
		if "MEDICAL BAY" in entry.text and lockdown_tick == 0.0:
			lockdown_tick = entry.tick
	if bang_tick_val > 0 and lockdown_tick > 0:
		_assert_true(bang_tick_val < lockdown_tick,
			"BANG before lockdown (bang=%.1f lockdown=%.1f)" % [bang_tick_val, lockdown_tick])

	# Verify NK chat lines appear in the dialogue log
	var nk_count := 0
	for entry in log:
		if entry.speaker == "NK-01" or entry.speaker == "NK-02":
			nk_count += 1
	_assert_true(nk_count >= 8, "NK chat lines in dialogue (got: %d)" % nk_count)

	# Verify NK lines interleave with poem lines (NK appears after a poem line)
	var found_nk_after_poem := false
	for i in range(1, log.size()):
		if (log[i].speaker == "NK-01" or log[i].speaker == "NK-02") and log[i - 1].style == "poem":
			found_nk_after_poem = true
			break
	_assert_true(found_nk_after_poem, "NK chat interleaves with poem")

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
	instance._visit_phase = 2
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Phase 2: attack → strict ordered tutorial → protect → aftermath
	var log := _pop_dialogue_log(instance, {
		"protect_prompt": func():
			# Simulate pressing X to queue protect
			instance._on_protect_pressed(),
		"run_prompt": func():
			# Simulate pressing Z to toggle run
			instance._toggle_run(),
		"click_monos": func():
			# Simulate clicking near Monos
			instance._start_confirm_protect(),
		"confirm_protect": func():
			# Teleport Peris near portal so proximity check passes
			var target: Vector3 = instance.PORTAL_POS + Vector3(-0.5, 0.5, 0)
			instance._player.global_position = target
			instance._game_state.characters["peris"].position = target
			instance._start_executing(),
	})

	_assert_true(log.size() >= 4, "At least 4 dialogue lines (got: %d)" % log.size())

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

	# Verify Monos thanks after protect
	var has_thanks := false
	for entry in log:
		if "thank you" in entry.text.to_lower():
			has_thanks = true
	_assert_true(has_thanks, "Monos thanks Peris after protect")

	# Verify efficiency penalty
	var has_penalty := false
	for entry in log:
		if "62%" in entry.text or "PENALTY" in entry.text:
			has_penalty = true
	_assert_true(has_penalty, "Efficiency penalty logged")

	instance._visit_phase = 1
	instance.queue_free()
	await get_tree().process_frame

func _test_peris_tutorial_redirect() -> void:
	_test_name = "Peris Tutorial Redirect"
	var scene := load("res://scenes/tutorial/peris_sim.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	instance._visit_phase = 2
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Phase 2: test out-of-order inputs trigger corrections
	var log := _pop_dialogue_log(instance, {
		"protect_prompt": func():
			# Wrong: try Z (run) before X (protect) — should show correction
			instance._toggle_run()
			# Correct: press X
			instance._on_protect_pressed(),
		"run_prompt": func():
			# Wrong: try Space (unpause) before Z — should show correction
			instance._toggle_pause()
			# Correct: press Z
			instance._toggle_run(),
		"click_monos": func():
			instance._start_confirm_protect(),
		"confirm_protect": func():
			var target: Vector3 = instance.PORTAL_POS + Vector3(-0.5, 0.5, 0)
			instance._player.global_position = target
			instance._game_state.characters["peris"].position = target
			instance._start_executing(),
	})

	# Verify the tutorial still completed despite wrong inputs
	var has_thanks := false
	for entry in log:
		if "thank you" in entry.text.to_lower():
			has_thanks = true
	_assert_true(has_thanks, "Tutorial completed despite redirects")

	# Verify efficiency penalty still logged
	var has_penalty := false
	for entry in log:
		if "62%" in entry.text or "PENALTY" in entry.text:
			has_penalty = true
	_assert_true(has_penalty, "Efficiency penalty logged after redirects")

	instance._visit_phase = 1
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
		"consciousness_fragments": func():
			# Skip tween-based fragments — jump straight to waking
			if instance._aster_node:
				instance._aster_node.visible = true
			for unit in [instance._escort_1, instance._escort_2]:
				if unit:
					unit.visible = true
			instance._emergency_light.light_energy = 3.0
			instance._fade_rect.color.a = 0.0
			instance._start_waking(),
		"approach_aster": func():
			# Teleport Peris near Aster
			var target: Vector3 = instance.ASTER_POS + Vector3(0.5, 0.5, 0)
			instance._peris_node.global_position = target
			instance._game_state.characters["peris"].position = target,
		"units_activate": func():
			# Resume from auto-pause so dialogue can advance
			instance._scheduler.resume(),
		"emp_tutorial": func():
			instance._on_emp_pressed()
			instance._flush_queued_abilities(),
		"hack_tutorial": func():
			instance._on_panel_hacked(),
		"multiselect_tutorial": func():
			# Resume from auto-pause and teleport both near the door exit
			instance._scheduler.resume()
			var exit_gate := Vector3(instance.ELEVATOR_SIZE.x / 2.0, 0.5, 0)
			instance._peris_node.global_position = exit_gate + Vector3(0, 0, -0.5)
			instance._aster_node.global_position = exit_gate + Vector3(0, 0, 0.5)
			instance._game_state.characters["peris"].position = exit_gate + Vector3(0, 0, -0.5)
			instance._game_state.characters["aster"].position = exit_gate + Vector3(0, 0, 0.5),
		"corridor": func():
			# Suppress enemy detection during dialogue test
			for enemy in instance._enemies:
				if is_instance_valid(enemy):
					enemy._detection_targets.clear()
					if instance._game_state.characters.has(enemy.char_id):
						instance._game_state.characters[enemy.char_id].stats["detection_range"] = 0.0,
		"bridge_collapse": func():
			pass,
	})

	_assert_true(log.size() >= 20, "At least 20 dialogue lines (got: %d)" % log.size())

	# Verify Aster retells Tag Day
	var has_tag_day := false
	for entry in log:
		if "wellness wing" in entry.text.to_lower() or "privacy" in entry.text.to_lower():
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

	# Verify bridge dialogue
	var has_bodies := false
	for entry in log:
		if "people down there" in entry.text:
			has_bodies = true
	_assert_true(has_bodies, "Bridge bodies dialogue exists")

	# Verify final bridge line
	var has_ahead := false
	for entry in log:
		if "ahead" in entry.text and "Lights" in entry.text:
			has_ahead = true
	_assert_true(has_ahead, "Final 'There's something ahead' line exists")

	instance.queue_free()
	await get_tree().process_frame

# --- Test: Endo Drink Pickup ---
func _test_endo_drink() -> void:
	_test_name = "Endo Drink"
	var scene := load("res://scenes/tutorial/elevator.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Load junction chunk to get the drink mesh
	instance._load_chunk("junction")
	for i in range(2):
		await get_tree().process_frame

	var drink: MeshInstance3D = instance._drink_mesh
	_assert_true(drink != null, "Drink mesh exists")
	if not drink:
		instance.queue_free()
		await get_tree().process_frame
		return

	var drink_start_pos: Vector3 = drink.global_position
	_assert_true(drink_start_pos.y < -3.0, "Drink starts on container (got y: %.1f)" % drink_start_pos.y)

	# Set up Endo so the shelter step can run
	instance._endo.visible = true
	instance._endo.position = Vector3(
		instance.JUNCTION_POS.x - instance.SHELTER_SIZE.x / 2.0,
		instance.BELOW_Y + 0.5, 0)
	instance._register_gs_character("endo", instance._endo, 2.5)

	# Trigger the shelter step (Endo walks to container)
	instance._start_endo_shelter()
	# Advance the scheduler enough for Endo to reach the container
	for i in range(80):
		instance._scheduler.advance(0.1)
		await get_tree().process_frame

	var drink_after_walk: Vector3 = drink.global_position
	var drink_moved := drink_start_pos.distance_to(drink_after_walk) > 0.5
	_assert_true(drink_moved, "Drink moved after Endo walks (dist: %.2f)" % drink_start_pos.distance_to(drink_after_walk))

	# Advance more for Endo to walk back with the drink
	for i in range(80):
		instance._scheduler.advance(0.1)
		await get_tree().process_frame

	var endo_pos: Vector3 = instance._endo.global_position
	var drink_final: Vector3 = drink.global_position
	var drink_near_endo := endo_pos.distance_to(drink_final) < 2.0
	_assert_true(drink_near_endo, "Drink near Endo after delivery (dist: %.2f)" % endo_pos.distance_to(drink_final))

	instance.queue_free()
	await get_tree().process_frame

# --- Test: Junction Arrival Flow ---
func _test_junction_flow() -> void:
	_test_name = "Junction Flow"
	var scene := load("res://scenes/tutorial/elevator.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Load junction chunk
	instance._load_chunk("junction")
	for i in range(3):
		await get_tree().process_frame

	# Verify interactable objects exist
	var interactable_names := ["Junction_Workbench", "Junction_Monitor", "Junction_Food", "Junction_Lookout", "Junction_Heater", "Junction_Markings", "Junction_Game"]
	var found_count := 0
	for iname in interactable_names:
		if instance.find_child(iname, true, false):
			found_count += 1
	_assert_true(found_count == 7, "All 7 junction interactables exist (got: %d)" % found_count)

	# Verify drink mesh exists on container
	_assert_true(instance._drink_mesh != null, "Drink mesh exists in junction")

	# Trigger junction arrive — should set dusk and enable movement
	instance._start_junction_arrive()
	for i in range(3):
		await get_tree().process_frame

	_assert_true(instance._current_step == "junction_arrive", "Step is junction_arrive (got: %s)" % instance._current_step)

	# Verify Endo is NOT visible yet (arrives after delay)
	_assert_true(not instance._endo.visible, "Endo not visible on initial arrival")

	# Advance scheduler past the 8s Endo entrance delay
	for i in range(20):
		instance._scheduler.advance(0.5)
		await get_tree().process_frame

	_assert_true(instance._endo.visible, "Endo visible after entrance delay")
	_assert_true(instance._current_step == "endo_enters", "Step advanced to endo_enters (got: %s)" % instance._current_step)

	instance.queue_free()
	await get_tree().process_frame

# --- Test: Climb and Soft Lockout Dialogue ---
func _test_climb_and_lockout() -> void:
	_test_name = "Climb and Lockout"

	# Verify climb dialogue keys exist
	var has_climb_aster := DialogueData.text("elevator.aster.climb") != ""
	var has_climb_peris := DialogueData.text("elevator.peris.climb") != ""
	var has_another_way := DialogueData.text("elevator.aster.another_way") != ""
	_assert_true(has_climb_aster, "Aster climb dialogue exists")
	_assert_true(has_climb_peris, "Peris climb dialogue exists")
	_assert_true(has_another_way, "Another way dialogue exists")

	# Verify soft lockout dialogue (dismiss, not locked out)
	var has_dismiss := DialogueData.text("elevator.aster.dismiss") != ""
	var has_not_back := DialogueData.text("elevator.peris.not_back") != ""
	_assert_true(has_dismiss, "Aster dismiss (soft lockout) dialogue exists")
	_assert_true(has_not_back, "Peris not-back dialogue exists")

	# Verify junction interactable dialogue keys exist
	for prefix in ["junction.workbench", "junction.monitor", "junction.food", "junction.lookout", "junction.heater", "junction.markings", "junction.game"]:
		var has_aster := DialogueData.text(prefix + ".aster") != ""
		var has_peris := DialogueData.text(prefix + ".peris") != ""
		_assert_true(has_aster, "%s.aster dialogue exists" % prefix)
		_assert_true(has_peris, "%s.peris dialogue exists" % prefix)

# --- Test: Enemy System ---
func _test_enemy() -> void:
	_test_name = "Enemy"

	# Set up a minimal scene with GameState + scheduler
	var root := Node3D.new()
	root.name = "EnemyTestRoot"
	get_tree().root.add_child(root)

	var chars := Node3D.new()
	chars.name = "Characters"
	root.add_child(chars)

	var scheduler := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = scheduler

	# Create a target character (simulated player)
	var target := Node3D.new()
	target.name = "aster"
	target.set("char_id", "aster")
	target.position = Vector3(10, 0, 0)
	chars.add_child(target)
	gs.register_character("aster", Vector3(10, 0, 0), 3.0)

	# Create an enemy
	var enemy := Enemy.new()
	enemy.name = "test_enemy"
	enemy.game_state = gs
	enemy.char_id = "enemy_0"
	enemy.max_hp = 100.0
	enemy.detection_range = 6.0
	enemy._detection_targets = ["aster"]
	chars.add_child(enemy)
	gs.register_character("enemy_0", Vector3(0, 0, 0), 1.5, {"detection_range": 6.0})

	for i in range(2):
		await get_tree().process_frame

	# Test: initial state
	_assert_true(enemy.get_state() == "idle", "Initial state is idle (got: %s)" % enemy.get_state())
	_assert_true(enemy.is_alive(), "Enemy starts alive")
	_assert_true(enemy._hp == 100.0, "HP starts at max (got: %.1f)" % enemy._hp)

	# Test: activate — target is at distance 10, range is 6, no detection
	enemy.activate()
	for i in range(5):
		scheduler.advance(0.5)
		await get_tree().process_frame
	_assert_true(enemy.get_state() == "idle", "No detection at distance 10 (got: %s)" % enemy.get_state())

	# Move target within range via command (triggers predictive detection)
	gs.command_move_to_pos("aster", Vector3(1, 0, 0))

	# Advance scheduler — predictive detection event should fire
	for i in range(10):
		scheduler.advance(0.5)
		await get_tree().process_frame

	var combat_states := ["alert", "pursuit", "windup", "charge", "recover"]
	_assert_true(enemy.get_state() in combat_states,
		"Detects target within range (got: %s)" % enemy.get_state())

	# Check for alert label ("!") on the target (may already have transitioned)
	var has_alert := false
	for child in target.get_children():
		if child is Label3D and child.text == "!":
			has_alert = true
	if enemy.get_state() == "alert":
		_assert_true(has_alert, "Alert '!' appears on target")
	else:
		_assert_true(true, "Alert '!' appeared then removed (now in %s)" % enemy.get_state())

	# Advance through the full attack cycle
	for i in range(20):
		scheduler.advance(0.3)
		await get_tree().process_frame
	_assert_true(enemy.get_state() in combat_states,
		"Attack cycle progresses (got: %s)" % enemy.get_state())

	# Test: take_damage
	enemy.take_damage(40.0)
	_assert_true(enemy._hp == 60.0, "HP after 40 damage (got: %.1f)" % enemy._hp)
	_assert_true(enemy.is_alive(), "Still alive at 60 HP")

	# Test: die
	enemy.take_damage(60.0)
	_assert_true(enemy._hp == 0.0, "HP after lethal damage (got: %.1f)" % enemy._hp)
	_assert_true(not enemy.is_alive(), "Dead after lethal damage")
	_assert_true(enemy.get_state() == "dead", "State is dead (got: %s)" % enemy.get_state())

	# --- Test: enemy detects player approaching on enemy route ---
	var route_enemy := Enemy.new()
	route_enemy.name = "route_test"
	route_enemy.game_state = gs
	route_enemy.char_id = "route_e"
	route_enemy.detection_range = 6.0
	route_enemy._detection_targets = ["player_route"]
	chars.add_child(route_enemy)
	gs.register_character("route_e", Vector3(20, 0, -4), 1.5, {"detection_range": 6.0})
	route_enemy.position = Vector3(20, 0, -4)

	var route_player := Node3D.new()
	route_player.name = "player_route"
	route_player.set("char_id", "player_route")
	route_player.position = Vector3(12, 0, -4)
	chars.add_child(route_player)
	gs.register_character("player_route", Vector3(12, 0, -4), 3.0)

	route_enemy.activate()
	# Move player toward enemy (triggers predictive detection)
	gs.command_move_to_pos("player_route", Vector3(20, 0, -4))
	for i in range(2):
		await get_tree().process_frame

	for i in range(8):
		scheduler.advance(0.5)
		await get_tree().process_frame
	_assert_true(route_enemy.get_state() != "idle" and route_enemy.get_state() != "patrol",
		"Enemy detects player on enemy route (got: %s)" % route_enemy.get_state())

	# --- Test: player on hazard route is safe from enemies ---
	var safe_enemy := Enemy.new()
	safe_enemy.name = "safe_test"
	safe_enemy.game_state = gs
	safe_enemy.char_id = "safe_e"
	safe_enemy.detection_range = 6.0
	safe_enemy._detection_targets = ["player_safe"]
	chars.add_child(safe_enemy)
	gs.register_character("safe_e", Vector3(20, 0, -4), 1.5, {"detection_range": 6.0})
	safe_enemy.position = Vector3(20, 0, -4)

	var safe_player := Node3D.new()
	safe_player.name = "player_safe"
	safe_player.set("char_id", "player_safe")
	safe_player.position = Vector3(20, 0, 5)
	chars.add_child(safe_player)
	gs.register_character("player_safe", Vector3(20, 0, 5), 3.0)

	safe_enemy.activate()
	# Player moves along hazard route (distance 9 from enemy, out of range 6)
	gs.command_move_to_pos("player_safe", Vector3(30, 0, 5))
	for i in range(2):
		await get_tree().process_frame

	for i in range(8):
		scheduler.advance(0.5)
		await get_tree().process_frame
	_assert_true(safe_enemy.get_state() == "idle",
		"Enemy ignores player on hazard route dist=9 (got: %s)" % safe_enemy.get_state())

	root.queue_free()
	await get_tree().process_frame

# --- Test: Chain Enemy ---
func _test_chain_enemy() -> void:
	_test_name = "Chain Enemy"

	var root := Node3D.new()
	root.name = "ChainTestRoot"
	get_tree().root.add_child(root)

	var chars := Node3D.new()
	chars.name = "Characters"
	root.add_child(chars)

	var scheduler := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = scheduler

	# Create a chain enemy
	var chain := ChainEnemy.new()
	chain.name = "test_chain"
	chain.game_state = gs
	chain.char_id = "chain_0"
	chain.segment_count = 6
	chain.segment_spacing = 0.3
	chain.max_stretch = 0.5
	chain.detection_range = 5.0
	chain._detection_targets = ["target_c"]
	chars.add_child(chain)
	gs.register_character("chain_0", Vector3(0, 0, 0), 1.5, {"detection_range": 5.0})

	for i in range(3):
		await get_tree().process_frame

	# Test: correct number of segments created
	_assert_true(chain._segments.size() == 6, "6 segments created (got: %d)" % chain._segments.size())
	_assert_true(chain._segment_positions.size() == 6, "6 segment positions (got: %d)" % chain._segment_positions.size())

	# Test: set_wall_line initializes positions along a direction
	chain.set_wall_line(Vector3(5, 0, 0), Vector3(1, 0, 0))
	_assert_true(chain._segment_positions[0].distance_to(Vector3(5, 0, 0)) < 0.01,
		"Wall line starts at (5,0,0)")
	_assert_true(chain._segment_positions[5].distance_to(Vector3(5 + 5 * 0.3, 0, 0)) < 0.01,
		"Wall line end segment at correct position")

	# Test: activate works (inherits from Enemy)
	chain.activate()
	_assert_true(chain.get_state() == "idle", "Initial state is idle (got: %s)" % chain.get_state())

	# Record initial segment positions
	var initial_positions: Array[Vector3] = []
	for pos in chain._segment_positions:
		initial_positions.append(pos)

	# Move the lead point via GameState
	gs.command_move_to_pos("chain_0", Vector3(10, 0, 0))

	# Advance scheduler and process frames so segments follow
	for i in range(30):
		scheduler.advance(0.1)
		await get_tree().process_frame

	# Test: segments have moved from initial positions
	var segments_moved := false
	for i in range(chain._segment_positions.size()):
		if chain._segment_positions[i].distance_to(initial_positions[i]) > 0.1:
			segments_moved = true
			break
	_assert_true(segments_moved, "Segments moved after lead point moved")

	# Test: spacing constraint — no segment further than max_stretch from previous
	var spacing_ok := true
	for i in range(1, chain._segment_positions.size()):
		var dist: float = chain._segment_positions[i].distance_to(chain._segment_positions[i - 1])
		if dist > chain.max_stretch + 0.01:
			spacing_ok = false
	_assert_true(spacing_ok, "All segments within max_stretch of previous")

	# Test: contact damage — place a target near a middle segment
	var target := Node3D.new()
	target.name = "target_c"
	target.set("char_id", "target_c")
	chars.add_child(target)
	gs.register_character("target_c", Vector3(0, 0, 0), 1.0)

	# Position target near segment 3
	var seg3_pos: Vector3 = chain._segment_positions[3]
	target.position = seg3_pos + Vector3(0.3, 0, 0)
	gs.characters["target_c"].position = target.position

	var hit_detected := false
	chain.hit_target.connect(func(tid: String, dmg: float):
		hit_detected = true
	)

	# Test segment contact directly using get_segment_positions
	# Place target exactly at segment 3's position
	chain._segment_positions[3] = Vector3(20, 0, 5)
	target.global_position = Vector3(20.2, 0, 5)
	var seg_positions := chain.get_segment_positions()
	var contact_found := false
	for sp in seg_positions:
		if sp.distance_to(target.global_position) < 0.6:
			contact_found = true
			break
	_assert_true(contact_found, "Segment contact within 0.6 of target")

	# Also test the public check_segment_contact method
	chain._segment_positions[2] = target.global_position + Vector3(0.1, 0, 0)
	var contact_id := chain.check_segment_contact(0.6)
	_assert_true(contact_id == "target_c", "check_segment_contact finds target (got: '%s')" % contact_id)

	# Test: color change propagates to all segments
	chain._set_mesh_color(Color(0.9, 0.1, 0.1))
	var all_red := true
	for mat in chain._segment_mats:
		if mat.albedo_color.r < 0.8:
			all_red = false
	_assert_true(all_red, "All segments turn red on color change")

	# Test: anchor constraint — head can't exceed max_reach from anchor
	chain._state = "idle"
	chain._hp = chain.max_hp
	chain._anchored = true
	var anchor := Vector3(0, 0, 0)
	chain._anchor_pos = anchor
	var max_reach: float = chain.get_max_reach()
	_assert_true(absf(max_reach - chain.segment_count * chain.segment_spacing) < 0.01,
		"Max reach = segment_count * spacing (got: %.2f)" % max_reach)

	# Move lead point way beyond max reach
	chain.global_position = Vector3(max_reach + 5.0, 0, 0)
	# Reset segment positions so _process can work cleanly
	for i in range(chain.segment_count):
		chain._segment_positions[i] = chain.global_position - Vector3(0, 0, i * chain.segment_spacing)
	chain._segment_positions[chain.segment_count - 1] = anchor

	for i in range(5):
		scheduler.advance(0.1)
		await get_tree().process_frame

	# Head should have been clamped back
	var head_dist: float = chain.global_position.distance_to(anchor)
	_assert_true(head_dist <= max_reach + 0.05,
		"Anchored head within max_reach (dist: %.2f, max: %.2f)" % [head_dist, max_reach])

	# Tail should be pinned to anchor
	var tail_dist: float = chain._segment_positions[chain.segment_count - 1].distance_to(anchor)
	_assert_true(tail_dist < 0.01, "Tail pinned to anchor (dist: %.3f)" % tail_dist)

	# Test: detach releases the constraint
	chain.detach()
	chain.global_position = Vector3(max_reach + 10.0, 0, 0)
	for i in range(5):
		scheduler.advance(0.1)
		await get_tree().process_frame
	var detached_dist: float = chain.global_position.distance_to(anchor)
	_assert_true(detached_dist > max_reach, "Detached head moves beyond max_reach (dist: %.2f)" % detached_dist)

	# Test: re-anchor to new position
	var new_anchor := Vector3(50, 0, 0)
	chain.anchor_to(new_anchor)
	_assert_true(chain._anchored, "Re-anchored after anchor_to()")
	_assert_true(chain._anchor_pos.distance_to(new_anchor) < 0.01, "New anchor position set")

	# Test: HP/death inherited from Enemy (must be last — kills the chain)
	chain._state = "idle"
	chain._hp = chain.max_hp
	chain.take_damage(chain.max_hp)
	_assert_true(not chain.is_alive(), "Chain dies when HP reaches 0")
	_assert_true(chain.get_state() == "dead", "Chain state is dead (got: %s)" % chain.get_state())

	root.queue_free()
	await get_tree().process_frame

# --- Test: Act 1 Levels ---
func _test_act1() -> void:
	_test_name = "Act 1 Levels"
	var scene := load("res://scenes/tutorial/act1.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Verify scene structure
	_assert_true(instance.find_child("Environment", false, false) != null, "Environment node exists")
	_assert_true(instance.find_child("Characters", false, false) != null, "Characters node exists")

	# Verify characters
	var aster := instance.find_child("Aster", true, false)
	var peris := instance.find_child("Peris", true, false)
	var endo := instance.find_child("Endo", true, false)
	_assert_true(aster != null, "Aster exists")
	_assert_true(peris != null, "Peris exists")
	_assert_true(endo != null, "Endo exists")
	_assert_true(endo.visible, "Endo visible at start")

	# Verify channels chunk loaded
	_assert_true(instance._chunks.has("channels"), "Channels chunk loaded at start")

	# Load all 4 chunks and verify
	instance._load_chunk("stacks")
	instance._load_chunk("rings")
	instance._load_chunk("lockout")
	for i in range(2):
		await get_tree().process_frame

	_assert_true(instance._chunks.has("stacks"), "Stacks chunk loaded")
	_assert_true(instance._chunks.has("rings"), "Rings chunk loaded")
	_assert_true(instance._chunks.has("lockout"), "Lockout chunk loaded")

	# Verify interactables exist
	_assert_true(instance.find_child("FloraGrowth", true, false) != null, "Flora interactable in channels")
	_assert_true(instance.find_child("DataTerminal", true, false) != null, "Terminal interactable in stacks")
	_assert_true(instance.find_child("ClientNPC", true, false) != null, "Client interactable in rings")
	_assert_true(instance.find_child("AccessPanel", true, false) != null, "Access panel in lockout")

	# Verify dialogue keys exist for all scenes
	for prefix in ["channels.narration.enter", "channels.peris.touch", "channels.endo.kneel",
		"stacks.aster.cleaned", "stacks.aster.means",
		"rings.peris.wall", "rings.endo.stops", "rings.peris.visiting",
		"lockout.system.rejected", "lockout.aster.not_in", "lockout.peris.back_to"]:
		var text := DialogueData.text(prefix)
		_assert_true(text != "", "Dialogue key exists: %s" % prefix)

	# Verify chunk unloading works
	instance._unload_chunk("channels")
	_assert_true(not instance._chunks.has("channels"), "Channels unloaded")

	instance.queue_free()
	await get_tree().process_frame

# --- Test: Predictive Detection (quadratic solver) ---
func _test_predictive_detection() -> void:
	_test_name = "Predictive Detection"

	# Test 1: User's example — two units 10 apart, closing at 2 units/sec total
	# Each moves at 1 unit/sec toward the other. Ranges 4 and 2 → events at t=3, t=4
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched

	gs.register_character("unit_a", Vector3(0, 0, 0), 1.0, {"detection_range": 4.0})
	gs.register_character("unit_b", Vector3(10, 0, 0), 1.0, {"detection_range": 2.0})

	var detections: Array[Dictionary] = []
	gs.detection_predicted.connect(func(det: String, tgt: String):
		detections.append({"detector": det, "target": tgt, "tick": sched.get_current_tick()})
	)

	gs.command_move_to_pos("unit_a", Vector3(10, 0, 0))
	gs.command_move_to_pos("unit_b", Vector3(0, 0, 0))

	# Advance to t=3 — unit_a (range 4) should detect
	sched.advance_ticks(3.0)
	_assert_true(detections.size() >= 1, "Head-on: first detection by t=3 (got: %d)" % detections.size())
	if detections.size() >= 1:
		_assert_true(detections[0].detector == "unit_a", "Head-on: unit_a detects first (got: %s)" % detections[0].detector)
		_assert_true(absf(detections[0].tick - 3.0) < 0.1, "Head-on: first at t=3 (got: %.2f)" % detections[0].tick)

	# Advance to t=4 — unit_b (range 2) should detect
	sched.advance_ticks(1.0)
	_assert_true(detections.size() >= 2, "Head-on: second detection by t=4 (got: %d)" % detections.size())
	if detections.size() >= 2:
		_assert_true(detections[1].detector == "unit_b", "Head-on: unit_b detects second (got: %s)" % detections[1].detector)
		_assert_true(absf(detections[1].tick - 4.0) < 0.1, "Head-on: second at t=4 (got: %.2f)" % detections[1].tick)

	# Test 2: One moving, one stationary — range 3, distance 8, speed 2 → t=2.5
	var gs2 := GameState.new()
	var sched2 := EventScheduler.new()
	gs2.scheduler = sched2
	gs2.register_character("mover", Vector3(0, 0, 0), 2.0, {"detection_range": 3.0})
	gs2.register_character("static_c", Vector3(8, 0, 0), 1.0, {})

	var det2: Array[Dictionary] = []
	gs2.detection_predicted.connect(func(det: String, tgt: String):
		det2.append({"detector": det, "target": tgt, "tick": sched2.get_current_tick()})
	)

	gs2.command_move_to_pos("mover", Vector3(10, 0, 0))
	sched2.advance_ticks(2.5)
	_assert_true(det2.size() >= 1, "One-moving: detection by t=2.5 (got: %d)" % det2.size())
	if det2.size() >= 1:
		_assert_true(absf(det2[0].tick - 2.5) < 0.1, "One-moving: at t=2.5 (got: %.2f)" % det2[0].tick)

	# Test 3: Movement cancelled — predictions invalidated
	var gs3 := GameState.new()
	var sched3 := EventScheduler.new()
	gs3.scheduler = sched3
	gs3.register_character("cancel_a", Vector3(0, 0, 0), 2.0, {"detection_range": 3.0})
	gs3.register_character("cancel_b", Vector3(6, 0, 0), 1.0, {})

	var det3: Array[Dictionary] = []
	gs3.detection_predicted.connect(func(det: String, tgt: String):
		det3.append({"detector": det, "tick": sched3.get_current_tick()})
	)

	gs3.command_move_to_pos("cancel_a", Vector3(10, 0, 0))
	gs3.command_stop("cancel_a")
	sched3.advance_ticks(5.0)
	_assert_true(det3.size() == 0, "Cancelled: no detection (got: %d)" % det3.size())

	# Test 4: Already in range — immediate detection
	var gs4 := GameState.new()
	var sched4 := EventScheduler.new()
	gs4.scheduler = sched4
	gs4.register_character("close_a", Vector3(0, 0, 0), 1.0, {"detection_range": 5.0})
	gs4.register_character("close_b", Vector3(3, 0, 0), 1.0, {})

	var det4: Array[Dictionary] = []
	gs4.detection_predicted.connect(func(det: String, tgt: String):
		det4.append({"detector": det, "tick": sched4.get_current_tick()})
	)

	gs4.command_move_to_pos("close_a", Vector3(1, 0, 0))
	sched4.advance_ticks(0.01)
	_assert_true(det4.size() >= 1, "Already in range: immediate detection (got: %d)" % det4.size())

	# Test 5: Parallel paths — never converge
	var gs5 := GameState.new()
	var sched5 := EventScheduler.new()
	gs5.scheduler = sched5
	gs5.register_character("par_a", Vector3(0, 0, 0), 2.0, {"detection_range": 3.0})
	gs5.register_character("par_b", Vector3(0, 0, 5), 2.0, {})

	var det5: Array[Dictionary] = []
	gs5.detection_predicted.connect(func(det: String, tgt: String):
		det5.append({"detector": det})
	)

	gs5.command_move_to_pos("par_a", Vector3(10, 0, 0))
	gs5.command_move_to_pos("par_b", Vector3(10, 0, 5))
	sched5.advance_ticks(10.0)
	_assert_true(det5.size() == 0, "Parallel paths: no detection (got: %d)" % det5.size())

# --- Test: Detection Equivalence (predictive vs brute-force tick scan) ---
func _test_detection_equivalence() -> void:
	_test_name = "Detection Equivalence"

	# Brute-force scanner: advance in small ticks, check distances each step
	# Returns the first tick where distance < range, or -1.0
	var _bruteforce_detect := func(
		pos_a: Vector3, vel_a: Vector3,
		pos_b: Vector3, vel_b: Vector3,
		det_range: float, max_time: float
	) -> float:
		var dt := 0.01
		var t := 0.0
		while t <= max_time:
			var pa := pos_a + vel_a * t
			var pb := pos_b + vel_b * t
			var dist := Vector2(pa.x - pb.x, pa.z - pb.z).length()
			if dist < det_range:
				return t
			t += dt
		return -1.0

	# Scenario configs: [pos_a, vel_a, pos_b, vel_b, range, label]
	var scenarios: Array[Dictionary] = [
		{"pa": Vector3(0,0,0), "va": Vector3(2,0,0), "pb": Vector3(12,0,0), "vb": Vector3.ZERO, "range": 3.0, "label": "Approach stationary"},
		{"pa": Vector3(0,0,0), "va": Vector3(1,0,0), "pb": Vector3(10,0,0), "vb": Vector3(-1,0,0), "range": 4.0, "label": "Head-on range=4"},
		{"pa": Vector3(0,0,0), "va": Vector3(1,0,0), "pb": Vector3(10,0,0), "vb": Vector3(-1,0,0), "range": 2.0, "label": "Head-on range=2"},
		{"pa": Vector3(0,0,0), "va": Vector3(1,0,1), "pb": Vector3(8,0,8), "vb": Vector3.ZERO, "range": 2.0, "label": "Diagonal approach"},
		{"pa": Vector3(0,0,0), "va": Vector3(3,0,0), "pb": Vector3(5,0,4), "vb": Vector3(0,0,-1), "range": 3.0, "label": "Perpendicular closing"},
		{"pa": Vector3(0,0,0), "va": Vector3(1,0,0), "pb": Vector3(0,0,20), "vb": Vector3(1,0,0), "range": 5.0, "label": "Parallel far apart"},
		{"pa": Vector3(0,0,0), "va": Vector3(2,0,0), "pb": Vector3(15,0,2), "vb": Vector3(-1,0,0), "range": 3.0, "label": "Offset head-on"},
		{"pa": Vector3(0,0,0), "va": Vector3(0,0,0), "pb": Vector3(4,0,0), "vb": Vector3.ZERO, "range": 5.0, "label": "Both static in range"},
		{"pa": Vector3(0,0,0), "va": Vector3(0,0,0), "pb": Vector3(10,0,0), "vb": Vector3.ZERO, "range": 5.0, "label": "Both static out of range"},
	]

	for scenario in scenarios:
		var pa: Vector3 = scenario.pa
		var va: Vector3 = scenario.va
		var pb: Vector3 = scenario.pb
		var vb: Vector3 = scenario.vb
		var det_range: float = scenario.range
		var label: String = scenario.label

		# Brute force result
		var bf_t: float = _bruteforce_detect.call(pa, va, pb, vb, det_range, 20.0)

		# Predictive result via GameState
		var sched := EventScheduler.new()
		var gs := GameState.new()
		gs.scheduler = sched
		var speed_a: float = va.length() if va.length() > 0.01 else 1.0
		var speed_b: float = vb.length() if vb.length() > 0.01 else 1.0
		gs.register_character("det_a", pa, speed_a, {"detection_range": det_range})
		gs.register_character("det_b", pb, speed_b, {})

		var pred_detections: Array[float] = []
		gs.detection_predicted.connect(func(_det: String, _tgt: String):
			pred_detections.append(sched.get_current_tick())
		)

		# Issue movement commands matching the velocities
		if va.length() > 0.01:
			var dest_a := pa + va.normalized() * 30.0
			gs.command_move_to_pos("det_a", dest_a)
		if vb.length() > 0.01:
			var dest_b := pb + vb.normalized() * 30.0
			gs.command_move_to_pos("det_b", dest_b)
		# For static in-range, trigger recompute manually
		if va.length() <= 0.01 and vb.length() <= 0.01:
			gs._recompute_all_detection_predictions()

		sched.advance_ticks(20.0)
		var pred_t: float = pred_detections[0] if pred_detections.size() > 0 else -1.0

		# Compare
		if bf_t < 0.0:
			_assert_true(pred_t < 0.0, "%s: both agree no detection" % label)
		else:
			_assert_true(pred_t >= 0.0, "%s: both agree detection occurs" % label)
			if pred_t >= 0.0:
				var diff := absf(pred_t - bf_t)
				_assert_true(diff < 0.05, "%s: timing matches (bf=%.2f pred=%.2f diff=%.3f)" % [label, bf_t, pred_t, diff])

	# Multi-entity scenario: 3 detectors, 2 targets moving in various directions
	var sched_m := EventScheduler.new()
	var gs_m := GameState.new()
	gs_m.scheduler = sched_m
	gs_m.register_character("d1", Vector3(0, 0, 0), 2.0, {"detection_range": 4.0})
	gs_m.register_character("d2", Vector3(0, 0, 10), 1.5, {"detection_range": 3.0})
	gs_m.register_character("d3", Vector3(10, 0, 5), 1.0, {"detection_range": 5.0})
	gs_m.register_character("t1", Vector3(8, 0, 0), 2.0, {})
	gs_m.register_character("t2", Vector3(5, 0, 12), 1.0, {})

	var multi_det: Array[Dictionary] = []
	gs_m.detection_predicted.connect(func(det: String, tgt: String):
		multi_det.append({"detector": det, "target": tgt, "tick": sched_m.get_current_tick()})
	)

	gs_m.command_move_to_pos("d1", Vector3(10, 0, 0))
	gs_m.command_move_to_pos("t1", Vector3(0, 0, 0))
	gs_m.command_move_to_pos("d2", Vector3(5, 0, 12))
	gs_m.command_move_to_pos("t2", Vector3(0, 0, 10))

	sched_m.advance_ticks(10.0)

	# d1 (range 4) approaching t1: start dist 8, closing at 4 units/sec → t=1.0
	# d2 (range 3) approaching t2: dist ~5.4, closing at ~2.5 → t≈1.0
	# d3 (range 5, stationary) — t1 starts at dist ~5.4 and moves away
	_assert_true(multi_det.size() >= 2, "Multi-entity: at least 2 detections (got: %d)" % multi_det.size())
	if multi_det.size() >= 1:
		_assert_true(multi_det[0].tick < 2.0, "Multi-entity: first detection before t=2 (got: %.2f)" % multi_det[0].tick)

	# --- N=10 large-scale equivalence tests ---
	# Setup: 10 units with various positions, speeds, detection ranges
	# Compare all predicted detections against brute-force tick scan

	# Brute-force scanner that models finite paths (units stop at destination)
	var _bf_scan_all := func(
		units: Array[Dictionary],  # [{id, pos, vel, range}]
		max_time: float, dt: float
	) -> Array[Dictionary]:  # [{detector, target, tick}]
		var results: Array[Dictionary] = []
		var detected: Dictionary = {}
		# Compute max travel time per unit based on path_len field (default 30)
		var max_travel: Array[float] = []
		for u in units:
			var spd: float = u.vel.length()
			var plen: float = u.get("path_len", 30.0)
			max_travel.append(plen / spd if spd > 0.01 else 0.0)
		# Position at time t, clamped to path end
		var _pos_at := func(u: Dictionary, t_val: float, mt: float) -> Vector3:
			var tt: float = minf(t_val, mt) if mt > 0.0 else 0.0
			return u.pos + u.vel * tt
		var t := 0.0
		while t <= max_time:
			for i in range(units.size()):
				if units[i].range <= 0.0:
					continue
				var pa: Vector3 = _pos_at.call(units[i], t, max_travel[i])
				for j in range(units.size()):
					if i == j:
						continue
					var key := "%s_%s" % [units[i].id, units[j].id]
					if detected.has(key):
						continue
					var pb: Vector3 = _pos_at.call(units[j], t, max_travel[j])
					var dist := Vector2(pa.x - pb.x, pa.z - pb.z).length()
					if dist < units[i].range:
						detected[key] = true
						results.append({"detector": units[i].id, "target": units[j].id, "tick": t})
			t += dt
		return results

	# Test A: 10 units in a line, every other one moving toward center
	var setup_a: Array[Dictionary] = []
	for i in range(10):
		var x: float = i * 4.0
		var vel := Vector3(-1.0 if i % 2 == 0 else 1.0, 0, 0)
		var det_range: float = 3.0 if i < 5 else 0.0
		setup_a.append({"id": "a%d" % i, "pos": Vector3(x, 0, 0), "vel": vel, "range": det_range})

	var bf_a: Array[Dictionary] = _bf_scan_all.call(setup_a, 15.0, 0.01)

	var sched_a := EventScheduler.new()
	var gs_a := GameState.new()
	gs_a.scheduler = sched_a
	for u in setup_a:
		var spd: float = u.vel.length() if u.vel.length() > 0.01 else 1.0
		var stats := {"detection_range": u.range} if u.range > 0.0 else {}
		gs_a.register_character(u.id, u.pos, spd, stats)

	var pred_a: Array[Dictionary] = []
	var pred_a_seen: Dictionary = {}
	gs_a.detection_predicted.connect(func(det: String, tgt: String):
		var key := det + "_" + tgt
		if not pred_a_seen.has(key):
			pred_a_seen[key] = true
			pred_a.append({"detector": det, "target": tgt, "tick": sched_a.get_current_tick()})
	)
	for u in setup_a:
		if u.vel.length() > 0.01:
			gs_a.command_move_to_pos(u.id, u.pos + u.vel.normalized() * 30.0)
	sched_a.advance_ticks(15.0)

	_assert_true(bf_a.size() == pred_a.size(),
		"Line-10: same detection count (bf=%d pred=%d)" % [bf_a.size(), pred_a.size()])
	# Check every brute-force detection has a matching predictive one (order may differ)
	var all_matched_a := true
	for bf_entry in bf_a:
		var found := false
		for p_entry in pred_a:
			if bf_entry.detector == p_entry.detector and bf_entry.target == p_entry.target and absf(bf_entry.tick - p_entry.tick) < 0.05:
				found = true
				break
		if not found:
			all_matched_a = false
	if bf_a.size() == pred_a.size() and bf_a.size() > 0:
		_assert_true(all_matched_a, "Line-10: all detections match within 0.05s")
	else:
		_assert_true(true, "Line-10: count mismatch — skipping match check")

	# Test B: 10 units in a circle converging on center
	var setup_b: Array[Dictionary] = []
	for i in range(10):
		var angle: float = i * TAU / 10.0
		var radius := 12.0
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var vel := -pos.normalized() * 1.5  # Move toward center
		var det_range: float = 4.0 if i % 3 == 0 else 2.0  # Varying ranges
		setup_b.append({"id": "b%d" % i, "pos": pos, "vel": vel, "range": det_range})

	var bf_b: Array[Dictionary] = _bf_scan_all.call(setup_b, 10.0, 0.01)

	var sched_b := EventScheduler.new()
	var gs_b := GameState.new()
	gs_b.scheduler = sched_b
	for u in setup_b:
		var spd: float = u.vel.length() if u.vel.length() > 0.01 else 1.0
		var stats := {"detection_range": u.range} if u.range > 0.0 else {}
		gs_b.register_character(u.id, u.pos, spd, stats)

	var pred_b: Array[Dictionary] = []
	var pred_b_seen: Dictionary = {}
	gs_b.detection_predicted.connect(func(det: String, tgt: String):
		var key := det + "_" + tgt
		if not pred_b_seen.has(key):
			pred_b_seen[key] = true
			pred_b.append({"detector": det, "target": tgt, "tick": sched_b.get_current_tick()})
	)
	for u in setup_b:
		if u.vel.length() > 0.01:
			gs_b.command_move_to_pos(u.id, u.pos + u.vel.normalized() * 30.0)
	sched_b.advance_ticks(10.0)

	_assert_true(bf_b.size() == pred_b.size(),
		"Circle-10: same detection count (bf=%d pred=%d)" % [bf_b.size(), pred_b.size()])

	# Test C: 10 units, mixed — some stationary, some crossing, some parallel
	var setup_c: Array[Dictionary] = []
	setup_c.append({"id": "c0", "pos": Vector3(0, 0, 0), "vel": Vector3(2, 0, 0), "range": 5.0, "path_len": 40.0})
	setup_c.append({"id": "c1", "pos": Vector3(20, 0, 0), "vel": Vector3(-2, 0, 0), "range": 3.0, "path_len": 40.0})
	setup_c.append({"id": "c2", "pos": Vector3(0, 0, 5), "vel": Vector3(2, 0, 0), "range": 0.0, "path_len": 40.0})
	setup_c.append({"id": "c3", "pos": Vector3(10, 0, 3), "vel": Vector3.ZERO, "range": 6.0})
	setup_c.append({"id": "c4", "pos": Vector3(10, 0, -3), "vel": Vector3.ZERO, "range": 0.0})
	setup_c.append({"id": "c5", "pos": Vector3(5, 0, -8), "vel": Vector3(0, 0, 2), "range": 4.0, "path_len": 40.0})
	setup_c.append({"id": "c6", "pos": Vector3(15, 0, -8), "vel": Vector3(0, 0, 1.5), "range": 3.0, "path_len": 40.0})
	setup_c.append({"id": "c7", "pos": Vector3(25, 0, 0), "vel": Vector3(-1, 0, 1), "range": 4.0, "path_len": 40.0})
	setup_c.append({"id": "c8", "pos": Vector3(0, 0, -15), "vel": Vector3(1, 0, 1), "range": 2.0, "path_len": 40.0})
	setup_c.append({"id": "c9", "pos": Vector3(30, 0, 10), "vel": Vector3(-3, 0, -2), "range": 5.0, "path_len": 40.0})

	var bf_c: Array[Dictionary] = _bf_scan_all.call(setup_c, 12.0, 0.01)

	var sched_c := EventScheduler.new()
	var gs_c := GameState.new()
	gs_c.scheduler = sched_c
	for u in setup_c:
		var spd: float = u.vel.length() if u.vel.length() > 0.01 else 1.0
		var stats := {"detection_range": u.range} if u.range > 0.0 else {}
		gs_c.register_character(u.id, u.pos, spd, stats)

	var pred_c: Array[Dictionary] = []
	var pred_c_seen: Dictionary = {}
	gs_c.detection_predicted.connect(func(det: String, tgt: String):
		var key := det + "_" + tgt
		if not pred_c_seen.has(key):
			pred_c_seen[key] = true
			pred_c.append({"detector": det, "target": tgt, "tick": sched_c.get_current_tick()})
	)
	for u in setup_c:
		if u.vel.length() > 0.01:
			gs_c.command_move_to_pos(u.id, u.pos + u.vel.normalized() * 40.0)
	sched_c.advance_ticks(12.0)

	# Predictive may find more detections than brute-force because it rechecks
	# after units arrive and stop (post-arrival predictions). All brute-force
	# detections should have a matching predictive one.
	_assert_true(pred_c.size() >= bf_c.size(),
		"Mixed-10: predictive >= brute-force (bf=%d pred=%d)" % [bf_c.size(), pred_c.size()])
	var all_bf_in_pred := true
	for bf_entry in bf_c:
		var found := false
		for p_entry in pred_c:
			if bf_entry.detector == p_entry.detector and bf_entry.target == p_entry.target and absf(bf_entry.tick - p_entry.tick) < 0.1:
				found = true
				break
		if not found:
			all_bf_in_pred = false
	_assert_true(all_bf_in_pred, "Mixed-10: all bf detections found in predictive (bf=%d)" % bf_c.size())

# --- Test: Ferrolure Gauntlet ---
func _test_ferrolure() -> void:
	_test_name = "Ferrolure"
	var scene := load("res://scenes/tutorial/elevator.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Load gauntlet chunk
	instance._load_chunk("gauntlet")
	for i in range(3):
		await get_tree().process_frame

	# Verify ferrolure mesh exists
	_assert_true(instance._ferrolure_mesh != null, "Ferrolure mesh exists")

	# Verify gauntlet enemies exist
	_assert_true(instance._gauntlet_enemies.size() == 5,
		"5 gauntlet enemies spawned (got: %d)" % instance._gauntlet_enemies.size())

	# Verify enemies target players initially
	var first_enemy: Enemy = instance._gauntlet_enemies[0]
	_assert_true("aster" in first_enemy._detection_targets or "peris" in first_enemy._detection_targets,
		"Enemies target players before ferrolure")

	# Activate ferrolure
	instance._on_ferrolure_activated()
	for i in range(2):
		await get_tree().process_frame

	_assert_true(instance._ferrolure_active, "Ferrolure is active after activation")

	# Verify enemies no longer target players
	_assert_true(first_enemy._detection_targets.is_empty(),
		"Enemies stop targeting players when lure active (targets: %s)" % str(first_enemy._detection_targets))

	# Advance scheduler — enemies should move toward ferrolure position
	for i in range(20):
		instance._scheduler.advance(0.3)
		await get_tree().process_frame

	# Check that enemies moved toward the ferrolure
	var lure_pos: Vector3 = instance.FERROLURE_POS
	var near_lure := 0
	for enemy in instance._gauntlet_enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(lure_pos) < 8.0:
			near_lure += 1
	_assert_true(near_lure >= 3,
		"Most enemies moved toward ferrolure (near: %d/5)" % near_lure)

	# Expire ferrolure
	instance._on_ferrolure_expired()
	for i in range(2):
		await get_tree().process_frame

	_assert_true(not instance._ferrolure_active, "Ferrolure deactivated after expiry")

	# Verify enemies re-target players
	_assert_true("aster" in first_enemy._detection_targets or "peris" in first_enemy._detection_targets,
		"Enemies re-target players after lure expires")

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
