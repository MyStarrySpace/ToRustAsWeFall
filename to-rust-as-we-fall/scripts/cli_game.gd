extends Node

## Headless text CLI for scripted play, record, and replay.
## Launch: godot --headless --path "." -- --cli

var _sim: SimRunner
var _running := true
var _record_path := ""
var _replay_path := ""
var _record_log: EventLog

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--cli"):
		# Skip outside CLI mode.
		return

	for i in range(args.size()):
		if args[i] == "--record" and i + 1 < args.size():
			_record_path = args[i + 1]
		if args[i] == "--replay" and i + 1 < args.size():
			_replay_path = args[i + 1]

	_sim = SimRunner.new(get_tree())

	print("")
	print("=== TO RUST AS WE FALL — CLI MODE ===")
	print("Type 'help' for commands.")
	print("")

	if _replay_path != "":
		await _run_replay()
		return

	if _record_path != "":
		_attach_recorder()

	_start_input_loop()

func _start_input_loop() -> void:
	# Process stdin on the main thread.
	set_process(true)
	_prompt()

var _pending_line := ""
var _check_stdin := true

func _process(_delta: float) -> void:
	if not _running or not _check_stdin:
		return
	# Placeholder for non-blocking stdin polling.
	pass

func _unhandled_input(event: InputEvent) -> void:
	# Input comes from stdin.
	pass

func _prompt() -> void:
	# Batch command mode:
	# godot --headless --path "." -- --cli --cmd "move 8 -3" --cmd "interact" --cmd "status"
	var args := OS.get_cmdline_user_args()
	var commands: Array[String] = []
	var i := 0
	while i < args.size():
		if args[i] == "--cmd" and i + 1 < args.size():
			commands.append(args[i + 1])
			i += 2
		else:
			i += 1

	if commands.is_empty():
		print("[CLI] No --cmd arguments. Use: -- --cli --cmd \"move 8 -3\" --cmd \"status\"")
		print("[CLI] Or use --cli-script <path> to run a command script file.")

		var script_idx := args.find("--cli-script")
		if script_idx >= 0 and script_idx + 1 < args.size():
			var script_path: String = args[script_idx + 1]
			commands = _load_script_file(script_path)

	if not commands.is_empty():
		await _run_commands(commands)
		_sim._print_state()
		if _record_path != "":
			_finalize_recording()
		print("\n[CLI] Done. Exiting.")
		get_tree().quit(0)

func _load_script_file(path: String) -> Array[String]:
	var commands: Array[String] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		print("[CLI] Could not open script file: %s" % path)
		return commands
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line != "" and not line.begins_with("#"):
			commands.append(line)
	return commands

func _run_commands(commands: Array[String]) -> void:
	for cmd_str in commands:
		print("\n> %s" % cmd_str)
		await _execute_text_command(cmd_str)

func _execute_text_command(text: String) -> void:
	var parts := text.strip_edges().split(" ", false)
	if parts.is_empty():
		return

	var verb: String = parts[0].to_lower()
	match verb:
		"move":
			if parts.size() >= 3:
				var x := parts[1].to_float()
				var z := parts[2].to_float()
				var cmd := SimCommand.click(x, z)
				await _sim._execute(cmd)
				# Wait for arrival
				var wait := SimCommand.wait_near(x, z, 1.5)
				await _sim._execute(wait)
			else:
				print("[CLI] Usage: move <x> <z>")

		"grid_move", "gmove":
			if parts.size() >= 3:
				var gx := parts[1].to_int()
				var gz := parts[2].to_int()
				var cmd := SimCommand.click_grid(gx, gz)
				await _sim._execute(cmd)
				# Wait for arrival at grid cell world position
				var player: Node = _sim._find_player()
				if player and player.get("grid_world"):
					var world_pos: Vector3 = player.grid_world.grid_to_world(Vector2i(gx, gz))
					var wait := SimCommand.wait_near(world_pos.x, world_pos.z, 1.0)
					await _sim._execute(wait)
				else:
					var wait := SimCommand.wait_near(float(gx), float(gz), 1.5)
					await _sim._execute(wait)
			else:
				print("[CLI] Usage: grid_move <grid_x> <grid_z>")

		"run":
			await _sim._execute(SimCommand.key_press(KEY_Z))
			print("[CLI] Run toggled")

		"dwell":
			# Proximity interaction waits through dwell time.
			var dwell_secs := 2.0
			if parts.size() >= 2:
				dwell_secs = parts[1].to_float()
			print("[CLI] Dwelling for %.1fs (proximity interaction)..." % dwell_secs)
			await _sim._execute(SimCommand.wait_time(dwell_secs))

		"click", "interact", "use":
			# Interact with a named interactable (e.g. click Terminal).
			if parts.size() >= 2:
				await _sim._execute(SimCommand.trigger_interactable(parts[1]))
			else:
				print("[CLI] Usage: click <InteractableName>")

		"interactables", "list", "scan":
			# What can the party act on right now (combined visible range).
			var radius := parts[1].to_float() if parts.size() >= 2 else 0.0
			await _sim._execute(SimCommand.list_interactables(radius))

		"move_to", "goto", "approach":
			# Walk the active character to a registered interactable, then dwell.
			if parts.size() >= 2:
				await _sim._execute(SimCommand.move_to_interactable(parts[1]))
			else:
				print("[CLI] Usage: move_to <interactable>")

		"equip", "pickup", "take":
			if parts.size() >= 2:
				await _sim._execute(SimCommand.equip_item(parts[1]))
			else:
				print("[CLI] Usage: equip <item_id>")

		"drop":
			if parts.size() >= 2:
				await _sim._execute(SimCommand.drop_item(parts[1]))
			else:
				print("[CLI] Usage: drop <item_id>")

		"give", "hand":
			if parts.size() >= 3:
				await _sim._execute(SimCommand.give_item(parts[1], parts[2]))
			else:
				print("[CLI] Usage: give <item_id> <to_char>")

		"throw":
			if parts.size() >= 4:
				await _sim._execute(SimCommand.throw_object(parts[1], parts[2].to_float(), parts[3].to_float()))
			else:
				print("[CLI] Usage: throw <obj_id> <x> <z>")

		"queue":
			# queue x1 z1 x2 z2 ... — walk the listed waypoints in order.
			var points: Array = []
			var i := 1
			while i + 1 < parts.size():
				points.append(Vector3(parts[i].to_float(), 0.0, parts[i + 1].to_float()))
				i += 2
			if points.is_empty():
				print("[CLI] Usage: queue <x1> <z1> [<x2> <z2> ...]")
			else:
				await _sim._execute(SimCommand.queue_moves(points))

		"rest", "sleep":
			await _sim._execute(SimCommand.rest())

		"protect":
			await _sim._execute(SimCommand.key_press(KEY_X))
			await _sim._execute(SimCommand.wait_frames(10))

		"route", "routing":
			await _sim._execute(SimCommand.key_press(KEY_TAB))
			await _sim._execute(SimCommand.wait_frames(5))

		"wait":
			var seconds := 2.0
			if parts.size() >= 2:
				seconds = parts[1].to_float()
			await _sim._execute(SimCommand.wait_time(seconds))

		"advance":
			# Single acknowledge — the same step a player click performs.
			await _sim._execute(SimCommand.advance_dialogue())

		"skip":
			# Drain the current dialogue, acknowledging wait gates as it goes.
			await _sim._execute(SimCommand.wait_dialogue())

		"status", "state", "look":
			_sim._print_state()

		"phase":
			var seq: Node = _sim._find_sequence()
			if seq and "_phase" in seq:
				print("[CLI] Phase: %s" % seq._phase)

		"assert":
			if parts.size() >= 4:
				var stat: String = parts[1]
				var op: String = parts[2]
				var value := parts[3].to_float()
				await _sim._execute(SimCommand.assert_stat(stat, op, value))

		"help":
			print("Commands:")
			print("  move <x> <z>    Move player to world position")
			print("  grid_move <gx> <gz>  Move player to grid cell (A* pathfinding)")
			print("  run             Toggle run/walk")
			print("  dwell [secs]    Wait near object for proximity interaction (default 2s)")
			print("  click <name>    Interact with a named interactable (e.g. click Terminal)")
			print("  interactables [r]  List interactables in the party's visible range")
			print("  move_to <name>  Walk the active character to an interactable")
			print("  equip <item>    Pick an item into a free hand slot")
			print("  drop <item>     Drop a held item")
			print("  give <item> <char>  Hand a held item to another character")
			print("  throw <obj> <x> <z>  Throw a physics object to a location")
			print("  queue <x1> <z1> ...  Queue waypoints; walk them in order")
			print("  rest            Rest at a shelter (restore the party)")
			print("  protect         Cast Protect ability (X)")
			print("  route           Toggle safe/direct routing (Tab)")
			print("  wait <seconds>  Advance game time")
			print("  advance         Advance dialogue one step (acknowledge)")
			print("  skip            Drain current dialogue to the end")
			print("  status          Print game state")
			print("  phase           Print current sequence phase")
			print("  assert <stat> <op> <value>  Check a stat (e.g. assert atp >= 8)")
			print("  help            This message")

		"quit", "exit":
			get_tree().quit(0)

		_:
			print("[CLI] Unknown command: %s (type 'help')" % verb)

# --- Record / replay ---

# Pre-attach a log so the scene's GameState records from setup.
func _attach_recorder() -> void:
	_record_log = EventLog.new()
	GameState._pending_event_log = _record_log
	print("[CLI/record] Pending EventLog ready; will attach on next GameState construction.")
	print("[CLI/record] Writing to %s on exit." % _record_path)

func _finalize_recording() -> void:
	if _record_log == null:
		return
	var gs: GameState = _sim._find_game_state()
	if gs:
		gs.flush_tick()
	var snap_path := _record_path + ".snap"
	var bytes := _record_log.to_bytes()
	var f := FileAccess.open(_record_path, FileAccess.WRITE)
	if f == null:
		print("[CLI/record] Failed to write log: %s" % _record_path)
		return
	f.store_buffer(bytes)
	f.close()
	if gs:
		var snap := gs.serialize()
		var snap_bytes := var_to_bytes(snap)
		var sf := FileAccess.open(snap_path, FileAccess.WRITE)
		if sf:
			sf.store_buffer(snap_bytes)
			sf.close()
	print("[CLI/record] Wrote %d events (%d bytes) to %s" % [
		_record_log.size(), bytes.size(), _record_path])

# Replay a recorded log and compare to its snapshot.
func _run_replay() -> void:
	var lf := FileAccess.open(_replay_path, FileAccess.READ)
	if lf == null:
		print("[CLI/replay] Could not open log: %s" % _replay_path)
		get_tree().quit(1)
		return
	var log_bytes := lf.get_buffer(lf.get_length())
	lf.close()
	var log := EventLog.from_bytes(log_bytes)

	var snap_path := _replay_path + ".snap"
	var sf := FileAccess.open(snap_path, FileAccess.READ)
	if sf == null:
		print("[CLI/replay] Could not open snapshot: %s" % snap_path)
		get_tree().quit(1)
		return
	var snap_bytes := sf.get_buffer(sf.get_length())
	sf.close()
	var expected_snap: Variant = bytes_to_var(snap_bytes)

	var gs_orig: GameState = await _await_game_state()
	if gs_orig == null:
		print("[CLI/replay] No GameState in scene; cannot resolve grid.")
		get_tree().quit(1)
		return

	var replayed := GameState.replay(log, gs_orig.grid)
	var actual_snap := replayed.serialize()

	if _snapshots_equal(actual_snap, expected_snap):
		print("[CLI/replay] OK — replayed %d events, final state matches snapshot." % log.size())
		get_tree().quit(0)
	else:
		print("[CLI/replay] FAIL — replayed state does not match snapshot.")
		print("  expected: %s" % expected_snap)
		print("  actual:   %s" % actual_snap)
		get_tree().quit(1)

# Wait for the sequence GameState to exist.
func _await_game_state(max_frames: int = 60) -> GameState:
	for _i in range(max_frames):
		var gs: GameState = _sim._find_game_state()
		if gs != null:
			return gs
		await get_tree().process_frame
	return null

# Structural snapshot compare with epsilon for position floats.
func _snapshots_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a.keys():
			if not b.has(k):
				return false
			if not _snapshots_equal(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _snapshots_equal(a[i], b[i]):
				return false
		return true
	if a is float and b is float:
		return absf(a - b) < 0.001
	return a == b
