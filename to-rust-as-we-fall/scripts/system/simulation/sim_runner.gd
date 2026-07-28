class_name SimRunner

## Executes SimCommands against a live scene tree. Used for:
## - Headless automated testing (scripted playthrough)
## - CLI game mode (text commands to SimCommands)
## - Replay/determinism testing

var _tree: SceneTree
var _passed := 0
var _failed := 0

func _init(tree: SceneTree) -> void:
	_tree = tree

## Run a sequence of commands. Returns true if all assertions passed.
func run(commands: Array[SimCommand]) -> bool:
	_passed = 0
	_failed = 0
	for cmd in commands:
		await _execute(cmd)
	return _failed == 0

func get_results() -> Dictionary:
	return {"passed": _passed, "failed": _failed, "total": _passed + _failed}

## Execute a single command
func _execute(cmd: SimCommand) -> void:
	match cmd.type:
		SimCommand.Type.CLICK:
			_do_click(cmd.args.x, cmd.args.z)
		SimCommand.Type.CLICK_GRID:
			_do_click_grid(cmd.args.gx, cmd.args.gz)
		SimCommand.Type.KEY_PRESS:
			_do_key_press(cmd.args.keycode)
		SimCommand.Type.WAIT_TIME:
			await _wait_time(cmd.args.seconds)
		SimCommand.Type.WAIT_FRAMES:
			await _wait_frames(cmd.args.count)
		SimCommand.Type.WAIT_PHASE:
			await _wait_phase(cmd.args.phase)
		SimCommand.Type.WAIT_NEAR:
			await _wait_near(cmd.args.x, cmd.args.z, cmd.args.radius)
		SimCommand.Type.WAIT_DIALOGUE:
			await _wait_dialogue()
		SimCommand.Type.ADVANCE_DIALOGUE:
			_advance_dialogue()
		SimCommand.Type.TRIGGER_INTERACTABLE:
			_trigger_interactable(cmd.args.name)
		SimCommand.Type.LIST_INTERACTABLES:
			_list_interactables(cmd.args.get("radius", 0.0))
		SimCommand.Type.MOVE_TO_INTERACTABLE:
			_move_to_interactable(cmd.args.get("id", ""), cmd.args.get("char_id", ""))
		SimCommand.Type.EQUIP_ITEM:
			_equip_item(cmd.args.get("item_id", ""), cmd.args.get("char_id", ""))
		SimCommand.Type.DROP_ITEM:
			_drop_item(cmd.args.get("item_id", ""), cmd.args.get("char_id", ""))
		SimCommand.Type.GIVE_ITEM:
			_give_item(cmd.args.get("item_id", ""), cmd.args.get("to_char", ""), cmd.args.get("char_id", ""))
		SimCommand.Type.THROW_OBJECT:
			_throw_object(cmd.args.get("obj_id", ""), cmd.args.get("x", 0.0), cmd.args.get("z", 0.0), cmd.args.get("arc_time", 0.0))
		SimCommand.Type.QUEUE_MOVES:
			_queue_moves(cmd.args.get("points", []), cmd.args.get("char_id", ""))
		SimCommand.Type.REST:
			_rest(cmd.args.get("char_id", ""))
		SimCommand.Type.ASSERT_STAT:
			_assert_stat(cmd.args.stat, cmd.args.op, cmd.args.value)
		SimCommand.Type.ASSERT_PHASE:
			_assert_phase(cmd.args.phase)
		SimCommand.Type.ASSERT_NEAR:
			_assert_near(cmd.args.x, cmd.args.z, cmd.args.radius)
		SimCommand.Type.PRINT_STATE:
			_print_state()

# --- Input simulation ---

func _do_click(x: float, z: float) -> void:
	# Find the player and set their target directly
	# This avoids needing a camera for screen-space projection in headless mode
	var player: Node = _find_player()
	if player and player.has_method("walk_to"):
		player.walk_to(Vector3(x, player.global_position.y, z))
		print("[SIM] Click → move to (%.1f, %.1f)" % [x, z])
	else:
		print("[SIM] Click → no player found")

func _do_click_grid(gx: int, gz: int) -> void:
	# Prefer GameState path if available
	var gs: GameState = _find_game_state()
	if gs:
		var char_id := _find_player_char_id()
		if char_id != "" and gs.command_move_to_cell(char_id, Vector2i(gx, gz)):
			# Sync the player node's local path from GameState
			var player: Node = _find_player()
			if player and player.has_method("walk_to_grid"):
				var ch: Dictionary = gs.characters[char_id]
				player._auto_path = ch.path.duplicate()
				player._auto_path_index = ch.path_index
				player._moving = true
			print("[SIM] Grid click → GameState cell (%d, %d)" % [gx, gz])
			return

	var player: Node = _find_player()
	if player and player.has_method("walk_to_grid") and player.get("grid_world"):
		player.walk_to_grid(Vector2i(gx, gz))
		print("[SIM] Grid click → cell (%d, %d)" % [gx, gz])
	elif player and player.has_method("walk_to"):
		# Fallback: no grid, use world position
		player.walk_to(Vector3(gx, player.global_position.y, gz))
		print("[SIM] Grid click → no grid, fallback walk_to (%d, %d)" % [gx, gz])
	else:
		print("[SIM] Grid click → no player found")

func _do_key_press(keycode: int) -> void:
	var key_name := OS.get_keycode_string(keycode)
	print("[SIM] Key press: %s" % key_name)
	# Create and dispatch an InputEventKey
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	# Also release it next frame
	await _tree.process_frame
	var ev_up := InputEventKey.new()
	ev_up.keycode = keycode
	ev_up.pressed = false
	Input.parse_input_event(ev_up)

# --- Wait conditions ---

func _wait_time(seconds: float) -> void:
	print("[SIM] Waiting %.1fs..." % seconds)
	var elapsed := 0.0
	while elapsed < seconds:
		await _tree.process_frame
		elapsed += _tree.root.get_process_delta_time()

func _wait_frames(count: int) -> void:
	for i in range(count):
		await _tree.process_frame

func _wait_phase(phase_name: String) -> void:
	print("[SIM] Waiting for phase: %s" % phase_name)
	var timeout := 30.0
	var elapsed := 0.0
	while elapsed < timeout:
		var seq: Node = _find_sequence()
		if seq:
			var phase_str := _get_phase_string(seq)
			if phase_str.to_lower().contains(phase_name.to_lower()):
				print("[SIM] Phase reached: %s" % phase_name)
				return
		await _tree.process_frame
		elapsed += _tree.root.get_process_delta_time()
	print("[SIM] TIMEOUT waiting for phase: %s" % phase_name)

func _wait_near(x: float, z: float, radius: float) -> void:
	print("[SIM] Waiting until near (%.1f, %.1f)..." % [x, z])
	var timeout := 20.0
	var elapsed := 0.0
	var target := Vector3(x, 0, z)
	while elapsed < timeout:
		var player: Node = _find_player()
		if player:
			var pos: Vector3 = player.global_position
			var dist := Vector2(pos.x - target.x, pos.z - target.z).length()
			if dist < radius:
				print("[SIM] Arrived near (%.1f, %.1f)" % [x, z])
				return
		await _tree.process_frame
		elapsed += _tree.root.get_process_delta_time()
	print("[SIM] TIMEOUT waiting to reach (%.1f, %.1f)" % [x, z])

func _wait_dialogue() -> void:
	print("[SIM] Waiting for dialogue to finish...")
	var timeout := 60.0
	var elapsed := 0.0
	# First wait for dialogue to become active
	await _wait_frames(5)
	while elapsed < timeout:
		var dlg: Node = _find_node("DialogueBox")
		if dlg and dlg.has_method("is_active"):
			if not dlg.is_active():
				print("[SIM] Dialogue finished")
				return
			# The sequence's dialogue clock advances the typewriter and the auto
			# beat each frame; we only acknowledge wait gates (no click spam).
			if _dialogue_at_wait_gate(dlg):
				dlg.call("request_advance")
		await _tree.process_frame
		elapsed += _tree.root.get_process_delta_time()
	print("[SIM] TIMEOUT waiting for dialogue")

## Interact with a named interactable through the data layer (a click on it).
func _trigger_interactable(node_name: String) -> void:
	var node: Node = _find_node(node_name)
	if node == null:
		print("[SIM] Interact → no node named '%s'" % node_name)
		return
	if node.has_method("is_interaction_enabled") and not bool(node.call("is_interaction_enabled")):
		print("[SIM] Interact → '%s' is not interactable right now" % node_name)
		return
	if node.has_method("_trigger"):
		node.call("_trigger")
		print("[SIM] Interacted with '%s'" % node_name)
	else:
		print("[SIM] Interact → '%s' has no interaction" % node_name)

## Which character acts: an explicit id when given, else the inferred player.
func _actor_char_id(explicit: String) -> String:
	if explicit != "":
		return explicit
	return _find_player_char_id()

## Resolve a registered interactable id from either an exact id or a node name.
func _resolve_interactable_id(gs: GameState, id_or_name: String) -> String:
	if gs == null:
		return ""
	if gs.has_interactable(id_or_name):
		return id_or_name
	var node: Node = _find_node(id_or_name)
	if node != null and "data_id" in node and String(node.data_id) != "":
		return String(node.data_id)
	return ""

## Print every interactable within the party's combined visible range.
func _list_interactables(radius: float) -> void:
	var gs := _find_game_state()
	if gs == null:
		print("[SIM] list-interactables → no GameState")
		return
	var party: Array = gs.get_party()
	if party.is_empty():
		var who := _find_player_char_id()
		if who != "":
			party = [who]
	var ids: Array = gs.interactables_in_range(party, radius) if radius > 0.0 else gs.interactables_in_range(party)
	print("[SIM] %d interactable(s) in range of %s:" % [ids.size(), str(party)])
	for id in ids:
		var spec: Dictionary = gs.get_interactable(id)
		print("  - %s @ %s" % [id, str(spec.get("position", Vector3.ZERO))])

## Walk the active character to a registered interactable (id or node name).
func _move_to_interactable(id_or_name: String, char_id: String) -> void:
	var gs := _find_game_state()
	if gs == null:
		print("[SIM] move-to → no GameState")
		return
	var who := _actor_char_id(char_id)
	var rid := _resolve_interactable_id(gs, id_or_name)
	if rid == "":
		print("[SIM] move-to → no interactable '%s'" % id_or_name)
		return
	if gs.move_to_interactable(who, rid):
		print("[SIM] %s moving to interactable '%s'" % [who, rid])
	else:
		print("[SIM] move-to → could not path %s to '%s'" % [who, rid])

## Equip: move an item into a free hand slot (pick it up).
func _equip_item(item_id: String, char_id: String) -> void:
	var gs := _find_game_state()
	if gs == null:
		print("[SIM] equip → no GameState")
		return
	var who := _actor_char_id(char_id)
	if gs.pick_up_item(who, item_id):
		print("[SIM] %s equipped '%s' (hands: %s)" % [who, item_id, str(gs.get_hand_items(who))])
	else:
		print("[SIM] equip → %s could not pick up '%s'" % [who, item_id])

## Drop a held item at the character's feet.
func _drop_item(item_id: String, char_id: String) -> void:
	var gs := _find_game_state()
	if gs == null:
		print("[SIM] drop → no GameState")
		return
	var who := _actor_char_id(char_id)
	if gs.drop_item(who, item_id):
		print("[SIM] %s dropped '%s'" % [who, item_id])
	else:
		print("[SIM] drop → %s is not holding '%s'" % [who, item_id])

## Hand a held item to another character.
func _give_item(item_id: String, to_char: String, char_id: String) -> void:
	var gs := _find_game_state()
	if gs == null:
		print("[SIM] give → no GameState")
		return
	var who := _actor_char_id(char_id)
	if to_char == "":
		print("[SIM] give → needs a recipient")
		return
	if gs.transfer_item(who, to_char, item_id):
		print("[SIM] %s gave '%s' to %s" % [who, item_id, to_char])
	else:
		print("[SIM] give → could not transfer '%s' from %s to %s" % [item_id, who, to_char])

## Throw a physics object to a world location along an arc.
func _throw_object(obj_id: String, x: float, z: float, arc_time: float) -> void:
	var gs := _find_game_state()
	if gs == null:
		print("[SIM] throw → no GameState")
		return
	if gs.throw_physics_object_to(obj_id, Vector3(x, 0.0, z), arc_time):
		print("[SIM] threw '%s' toward (%.1f, %.1f)" % [obj_id, x, z])
	else:
		print("[SIM] throw → no physics object '%s'" % obj_id)

## Queue several destinations; the character walks them in order (one move each).
func _queue_moves(points: Array, char_id: String) -> void:
	var gs := _find_game_state()
	if gs == null:
		print("[SIM] queue → no GameState")
		return
	var who := _actor_char_id(char_id)
	var path: Array[Vector3] = []
	for p in points:
		if p is Vector3:
			path.append(p)
		elif p is Array and (p as Array).size() >= 2:
			path.append(Vector3(float(p[0]), 0.0, float(p[1])))
	if path.is_empty():
		print("[SIM] queue → no destinations")
		return
	gs.command_walk_path(who, path)
	print("[SIM] %s queued %d move(s)" % [who, path.size()])

## Commit the whole party (or one named character) to the real shelter-rest flow.
## This deliberately does not call restore_character(): rest must require shelter
## presence, spend ATP, and heal over game time like player input does.
func _rest(char_id: String) -> void:
	var gs := _find_game_state()
	if gs == null:
		print("[SIM] rest → no GameState")
		return
	var members: Array = [char_id] if char_id != "" else gs.get_party()
	if members.is_empty():
		var who := _find_player_char_id()
		if who != "":
			members = [who]
	var accepted: Array[String] = []
	var refused: Array[String] = []
	for member in members:
		var member_id := String(member)
		if gs.command_rest(member_id):
			accepted.append(member_id)
		else:
			refused.append(member_id)
	print("[SIM] shelter rest started for %s; refused %s" % [str(accepted), str(refused)])

## Advance the dialogue one step via the same path a real click uses.
func _advance_dialogue() -> void:
	var dlg: Node = _find_node("DialogueBox")
	if dlg and dlg.has_method("request_advance"):
		dlg.call("request_advance")
		print("[SIM] Dialogue advanced")
	else:
		print("[SIM] Advance → no dialogue box")

## True when the box is waiting for an advance — a fully-typed line that won't
## progress on its own (click-only by default, or an acknowledge line). The CLI
## acknowledges it the way a player click would.
func _dialogue_at_wait_gate(dlg: Node) -> bool:
	if dlg.has_method("awaiting_advance"):
		return bool(dlg.call("awaiting_advance"))
	if not bool(dlg.get("_waiting_for_input")):
		return false
	var shown := float(dlg.get("_displayed_chars"))
	var total := str(dlg.get("_current_text")).length()
	return shown >= float(total)

# --- Assertions ---

func _assert_stat(stat_name: String, op: String, value: float) -> void:
	var player: Node = _find_player()
	if not player:
		_fail("assert_stat: no player found")
		return

	var actual: float = 0.0
	# Check common stat sources
	var seq: Node = _find_sequence()
	if seq:
		match stat_name:
			"atp":
				if "_atp" in seq: actual = seq._atp
			"hp":
				if "_hp" in seq: actual = seq._hp
			"stamina":
				if "_stamina" in seq: actual = seq._stamina

	var passed := false
	match op:
		">=": passed = actual >= value
		"<=": passed = actual <= value
		"==": passed = is_equal_approx(actual, value)
		">": passed = actual > value
		"<": passed = actual < value

	if passed:
		_pass("assert %s %s %.0f (actual: %.1f)" % [stat_name, op, value, actual])
	else:
		_fail("assert %s %s %.0f (actual: %.1f)" % [stat_name, op, value, actual])

func _assert_phase(phase_name: String) -> void:
	var seq: Node = _find_sequence()
	if not seq:
		_fail("assert_phase: no sequence node found")
		return
	var current: String = _get_phase_string(seq)
	if current.to_lower().contains(phase_name.to_lower()):
		_pass("phase is %s" % phase_name)
	else:
		_fail("phase expected %s, got %s" % [phase_name, current])

func _assert_near(x: float, z: float, radius: float) -> void:
	var player: Node = _find_player()
	if not player:
		_fail("assert_near: no player found")
		return
	var pos: Vector3 = player.global_position
	var dist := Vector2(pos.x - x, pos.z - z).length()
	if dist < radius:
		_pass("player near (%.1f, %.1f) — dist %.1f" % [x, z, dist])
	else:
		_fail("player NOT near (%.1f, %.1f) — dist %.1f > %.1f" % [x, z, dist, radius])

# --- State printing (for CLI mode) ---

func _print_state() -> void:
	var player: Node = _find_player()
	var seq: Node = _find_sequence()
	print("--- GAME STATE ---")
	if player:
		var pos: Vector3 = player.global_position
		print("  Player: %s at (%.1f, %.1f, %.1f)" % [player.name, pos.x, pos.y, pos.z])
		print("  Moving: %s" % (player.is_moving() if player.has_method("is_moving") else "?"))
	if seq:
		print("  Phase: %s" % _get_phase_string(seq))
		if "_atp" in seq: print("  ATP: %s" % GameState.atp_text(seq._atp))
		if "_hp" in seq: print("  HP: %.0f" % seq._hp)
		if "_stamina" in seq: print("  Stamina: %.0f" % seq._stamina)
		if "_game_time" in seq: print("  Time: %.2f" % seq._game_time)
		if "_routing_mode" in seq: print("  Routing: %s" % seq._routing_mode)
	var enemies := _find_enemies()
	if not enemies.is_empty():
		print("  Enemies:")
		var gs: GameState = _find_game_state()
		for e in enemies:
			var tgt: String = str(e._current_target_id) if "_current_target_id" in e else ""
			var dist := -1.0
			if gs != null and tgt != "" and gs.characters.has(tgt) and gs.characters.has(e.char_id):
				dist = gs.get_position(e.char_id).distance_to(gs.get_position(tgt))
			var line := "    %s: %-8s hp=%.0f" % [e.char_id, e.get_state(), e._hp]
			if tgt != "":
				line += " target=%s d=%.1f" % [tgt, dist]
			print(line)
	print("------------------")

# --- Helpers ---

func _find_game_state() -> GameState:
	var seq: Node = _find_sequence()
	if seq and "_game_state" in seq:
		return seq._game_state
	return null

## Every Enemy in the current scene (for the CLI status readout — makes the attack loop observable
## headlessly: state, hp, and current target/distance).
func _find_enemies() -> Array:
	var out: Array = []
	var root: Node = _tree.current_scene
	if root != null:
		_collect_enemies(root, out)
	return out

func _collect_enemies(node: Node, out: Array) -> void:
	if node is Enemy:
		out.append(node)
	for child in node.get_children():
		_collect_enemies(child, out)

func _find_player_char_id() -> String:
	var player: Node = _find_player()
	if player and "char_id" in player and player.char_id != "":
		return player.char_id
	# Infer from player name
	if player:
		return player.name.to_lower()
	return ""

func _find_player() -> Node:
	var p: Node = _find_node("Aster")
	if p: return p
	return _find_node("Peris")

func _find_sequence() -> Node:
	# The root scene node usually has the sequence script
	var root: Node = _tree.current_scene
	if root and ("_phase" in root or "_current_step" in root):
		return root
	return null

## Get phase/step as a string, supporting both _phase (enum) and _current_step (string).
func _get_phase_string(seq: Node) -> String:
	if "_current_step" in seq and seq._current_step != "":
		return seq._current_step
	if "_phase" in seq:
		return str(seq._phase)
	return "unknown"

func _find_node(node_name: String) -> Node:
	var root: Node = _tree.current_scene
	if root:
		return root.find_child(node_name, true, false)
	return null

func _pass(msg: String) -> void:
	print("  PASS: [Sim] %s" % msg)
	_passed += 1

func _fail(msg: String) -> void:
	print("  FAIL: [Sim] %s" % msg)
	_failed += 1
