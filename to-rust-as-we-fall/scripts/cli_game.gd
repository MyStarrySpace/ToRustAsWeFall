extends Node

## CLI game mode. Runs the game headlessly with text input/output.
## Launch: godot --headless --path "." -- --cli
##
## Commands:
##   move <x> <z>     Move player to world position
##   run              Toggle run mode
##   interact         Press E (interact with nearby object)
##   protect          Press Q (Protect ability)
##   route            Press Tab (toggle safe/direct)
##   wait <seconds>   Advance game time
##   status           Print full game state
##   advance          Click through dialogue
##   help             Show available commands
##   quit             Exit

var _sim: SimRunner
var _running := true

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--cli"):
		# Not in CLI mode — this autoload does nothing
		return

	_sim = SimRunner.new(get_tree())

	print("")
	print("=== TO RUST AS WE FALL — CLI MODE ===")
	print("Type 'help' for commands.")
	print("")

	# Start processing input on a thread
	_start_input_loop()

func _start_input_loop() -> void:
	# Process stdin in _process to stay on the main thread
	set_process(true)
	_prompt()

var _pending_line := ""
var _check_stdin := true

func _process(_delta: float) -> void:
	if not _running or not _check_stdin:
		return
	# Non-blocking stdin read isn't great in Godot, so we use a poll approach
	# In practice, the game advances each frame while we wait for input
	pass

func _unhandled_input(event: InputEvent) -> void:
	# Not used in CLI mode — input comes from stdin
	pass

func _prompt() -> void:
	# Godot doesn't have great stdin support in-process.
	# For CLI mode, we'll use a polling approach with OS.execute or
	# just process commands passed as args after --cli.
	#
	# For now, support batch command mode:
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
		# Interactive mode hint
		print("[CLI] No --cmd arguments. Use: -- --cli --cmd \"move 8 -3\" --cmd \"status\"")
		print("[CLI] Or use --cli-script <path> to run a command script file.")

		# Check for script file
		var script_idx := args.find("--cli-script")
		if script_idx >= 0 and script_idx + 1 < args.size():
			var script_path: String = args[script_idx + 1]
			commands = _load_script_file(script_path)

	if not commands.is_empty():
		await _run_commands(commands)
		_sim._print_state()
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
			await _sim._execute(SimCommand.key_press(KEY_SHIFT))
			print("[CLI] Run toggled")

		"dwell", "interact", "use":
			# Proximity interaction — just wait near the object for its dwell time
			var dwell_secs := 2.0
			if parts.size() >= 2:
				dwell_secs = parts[1].to_float()
			print("[CLI] Dwelling for %.1fs (proximity interaction)..." % dwell_secs)
			await _sim._execute(SimCommand.wait_time(dwell_secs))

		"protect":
			await _sim._execute(SimCommand.key_press(KEY_Q))
			await _sim._execute(SimCommand.wait_frames(10))

		"route", "routing":
			await _sim._execute(SimCommand.key_press(KEY_TAB))
			await _sim._execute(SimCommand.wait_frames(5))

		"wait":
			var seconds := 2.0
			if parts.size() >= 2:
				seconds = parts[1].to_float()
			await _sim._execute(SimCommand.wait_time(seconds))

		"advance", "skip":
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
			print("  protect         Cast Protect ability (Q)")
			print("  route           Toggle safe/direct routing (Tab)")
			print("  wait <seconds>  Advance game time")
			print("  advance         Click through dialogue")
			print("  status          Print game state")
			print("  phase           Print current sequence phase")
			print("  assert <stat> <op> <value>  Check a stat (e.g. assert atp >= 100)")
			print("  help            This message")

		"quit", "exit":
			get_tree().quit(0)

		_:
			print("[CLI] Unknown command: %s (type 'help')" % verb)
