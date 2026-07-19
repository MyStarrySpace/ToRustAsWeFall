class_name SelectionController
extends Node

## RTS selection authority (RimWorld / Phylactory-style). LEFT-click picks the party character under
## the cursor; LEFT click-drag draws a marquee and box-selects everyone inside it. The result is pushed
## through the HUD (the single selection source of truth), so the existing character_selection_changed
## fan-out drives set_party + group_move exactly as before. RIGHT-click stays the move/interact command
## (player.gd / the interactables).
##
## Lives in scripts/game/ (shared), instantiated ONCE per scene by tutorial_sequence._ready next to the
## PathRenderManager — so every gameplay/preview/elevator scene gets world-space selection for free. Its
## input handling is here, NOT in a sequence, so the --test-sequence-input-discipline lint never sees it.
##
## Selection is UI pacing: it mutates no game state and emits ZERO EventLog entries (only the resulting
## move/interaction does). Box-select math is camera.unproject_position(world_pos) + rect.has_point() —
## the Phylactory pattern — so headless tests drive headless_pick / headless_box_select display-free.
## The world_pos is the character's RENDER position (get_render_position), so on a warped scene (the
## channels helix, where the data layer stays flat but bodies render on the spiral via coord_map) the
## marquee hugs the VISIBLE bodies. It's identity on flat scenes, so they're unchanged.

const DRAG_THRESHOLD := 10.0       # px — click vs box-drag (Phylactory CLICK_DRAG_PIXEL_THRESHOLD)
const PICK_SCREEN_RADIUS := 56.0   # px — how near a single click must land to pick a character
const RALLY_CANCEL_DISTANCE := 24.0
const RALLY_REPLAY_META := &"_rally_short_click_replay"
const RallyHoldIndicatorScript := preload("res://scripts/ui/rally_hold_indicator.gd")
const PathRendererScript := preload("res://scripts/game/world/path_renderer.gd")

var _game_state
var _hud
var _scene_root: Node
var _active_player: Node3D
var _camera: Camera3D

var _marquee
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragging := false
var _rally_indicator: RallyHoldIndicator
var _command_pressed := false
var _command_cancelled := false
var _command_hold_matured := false
var _command_press_pos := Vector2.ZERO
var _command_pointer := Vector2.ZERO
var _command_started_msec := 0
var _command_modifiers := {}
var _command_suppressed_until_release := false
var _rally_previews: Dictionary = {}
var _rally_preview_nodes: Dictionary = {}
var _rally_preview_signature := ""

## scene_root is the sequence (it owns _hud + _player, both created after the base _ready), so the HUD
## and active player are resolved lazily from it — same trick player.gd selection deferral uses.
func setup(game_state, scene_root: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game_state = game_state
	_scene_root = scene_root
	_ensure_marquee()
	_ensure_rally_indicator()

func set_active_player(node: Node3D) -> void:
	_active_player = node

func set_camera(cam: Camera3D) -> void:
	_camera = cam

## Tests inject a HUD directly (no scene root); live scenes resolve it lazily from the sequence.
func set_hud(hud) -> void:
	_hud = hud

func _resolve_hud():
	if _hud != null and is_instance_valid(_hud):
		return _hud
	if _scene_root != null:
		_hud = _scene_root.get("_hud")
	return _hud

func _ensure_marquee() -> void:
	if _marquee != null or Engine.is_editor_hint():
		return
	var layer := preload("res://scenes/ui/selection_marquee_layer.tscn").instantiate() as CanvasLayer
	add_child(layer)
	_marquee = layer.get_node("SelectionMarquee")

func _ensure_rally_indicator() -> void:
	if _rally_indicator != null or Engine.is_editor_hint():
		return
	var layer := preload("res://scenes/ui/rally_hold_layer.tscn").instantiate() as CanvasLayer
	add_child(layer)
	_rally_indicator = layer.get_node("RallyHoldIndicator")

# --- Live input ------------------------------------------------------------

## COMMAND is intercepted before GUI/physics picking so a hold cannot accidentally interact on its
## press edge. A short release replays one marked press+release through the ordinary input pipeline;
## a long release instead queues an explicit-member rally. Selection itself is never mutated.
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or event.has_meta(RALLY_REPLAY_META):
		return
	if is_inside_tree() and get_tree().paused:
		if _command_pressed or _command_suppressed_until_release:
			cancel_command_hold()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _command_pressed:
			_cancel_command_hold()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _command_pressed:
		_update_command_pointer((event as InputEventMouseMotion).position)
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _command_suppressed_until_release:
		if not mb.pressed:
			_command_suppressed_until_release = false
		get_viewport().set_input_as_handled()
		return
	if mb.pressed:
		if _command_belongs_to_gui():
			_command_suppressed_until_release = true
			get_viewport().set_input_as_handled()
			return
		_begin_command_hold(mb)
		get_viewport().set_input_as_handled()
	elif _command_pressed:
		_update_command_pointer(mb.position)
		if _command_belongs_to_gui():
			_cancel_command_hold()
		else:
			_finish_command_hold(mb)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	# A "pick the ground target" sequence beat (e.g. peris click-Monos) owns LEFT for that moment —
	# let player.gd emit ground_clicked instead of selecting a character.
	if _defer_to_pick_mode():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.is_action_pressed("select"):
		_pressed = true
		_dragging = false
		_press_pos = mb.position
		# Don't consume on press — it might be a click or a drag; commit on release.
	elif mb.is_action_released("select"):
		if _pressed:
			if _press_pos.distance_to(mb.position) > DRAG_THRESHOLD:
				_commit_box_select(Rect2(_press_pos, mb.position - _press_pos).abs())
			else:
				_commit_pick(mb.position)
			get_viewport().set_input_as_handled()
		_pressed = false
		_dragging = false
		if _marquee != null:
			_marquee.clear_rect()

func _process(_delta: float) -> void:
	if is_inside_tree() and get_tree().paused:
		if _command_pressed or _command_suppressed_until_release:
			cancel_command_hold()
		return
	_update_command_hold()
	if not _pressed or _marquee == null or not is_inside_tree():
		return
	var cur := get_viewport().get_mouse_position()
	if not _dragging and _press_pos.distance_to(cur) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging:
		_marquee.set_rect(Rect2(_press_pos, cur - _press_pos))

func _begin_command_hold(event: InputEventMouseButton) -> void:
	if _command_pressed:
		_cancel_command_hold()
	_command_pressed = true
	_command_cancelled = false
	_command_hold_matured = false
	_command_press_pos = event.position
	_command_pointer = event.position
	_command_started_msec = Time.get_ticks_msec()
	_command_modifiers = {
		"alt": event.alt_pressed,
		"shift": event.shift_pressed,
		"ctrl": event.ctrl_pressed,
		"meta": event.meta_pressed,
	}
	_ensure_rally_indicator()
	if _rally_indicator != null:
		_rally_indicator.begin(_command_pointer, _rally_candidate_ids().size())

func _update_command_pointer(pointer: Vector2) -> void:
	_command_pointer = pointer
	if _command_cancelled:
		return
	var elapsed := _command_elapsed()
	if elapsed >= _rally_hold_duration():
		# Crossing the threshold changes this into a movable rally placement. Pointer
		# travel now relocates the formation rather than cancelling the gesture.
		_command_hold_matured = true
	elif _command_drag_would_cancel(_command_press_pos.distance_to(pointer), elapsed):
		_command_cancelled = true

func _update_command_hold() -> void:
	if not _command_pressed:
		return
	if is_inside_tree():
		_update_command_pointer(get_viewport().get_mouse_position())
	if _rally_indicator != null:
		var progress := _command_elapsed() / maxf(_rally_hold_duration(), 0.001)
		if progress >= 1.0 and not _command_cancelled:
			_command_hold_matured = true
		_rally_indicator.update_hold(_command_pointer, progress, _command_cancelled)
		if _command_hold_matured and not _command_cancelled:
			_update_rally_preview_at_screen(_command_pointer)
		else:
			_clear_rally_preview()

func _finish_command_hold(event: InputEventMouseButton) -> void:
	var elapsed := _command_elapsed()
	var should_rally := not _command_cancelled \
		and (_command_hold_matured or elapsed >= _rally_hold_duration())
	_command_pressed = false
	_command_hold_matured = false
	_clear_rally_preview()
	if _command_cancelled:
		if _rally_indicator != null:
			_rally_indicator.cancel()
		return
	if should_rally:
		var moved := _commit_rally_at_screen(event.position)
		if _rally_indicator != null:
			if moved > 0:
				_rally_indicator.commit(moved)
			elif moved == 0:
				_rally_indicator.reject()
			else:
				_rally_indicator.cancel()
		return
	if _rally_indicator != null:
		_rally_indicator.cancel()
	_replay_short_command(event.position)

func _cancel_command_hold() -> void:
	_command_pressed = false
	_command_cancelled = true
	_command_hold_matured = false
	_command_suppressed_until_release = false
	_clear_rally_preview()
	if _rally_indicator != null:
		_rally_indicator.cancel()

## Public cancellation edge used by touch-mode and scene transitions. It deliberately never replays
## a short command: abandoning a proxy press must not leak a move/interact into the next mode.
func cancel_command_hold() -> void:
	_cancel_command_hold()

func _exit_tree() -> void:
	_cancel_command_hold()

func _command_elapsed() -> float:
	return maxf(0.0, float(Time.get_ticks_msec() - _command_started_msec) / 1000.0)

func _rally_hold_duration() -> float:
	var settings := GameSettings.resolve(self)
	if settings != null and settings.has_method("get_rally_hold_duration"):
		return clampf(
			float(settings.call("get_rally_hold_duration")),
			GameSettings.RALLY_HOLD_MIN,
			GameSettings.RALLY_HOLD_MAX
		)
	return GameSettings.RALLY_HOLD_DEFAULT

func _command_drag_would_cancel(distance: float, elapsed: float) -> bool:
	return distance > RALLY_CANCEL_DISTANCE and elapsed < _rally_hold_duration()

func _replay_short_command(pointer: Vector2) -> void:
	for pressed_state in [true, false]:
		var replay := InputEventMouseButton.new()
		replay.button_index = MOUSE_BUTTON_RIGHT
		replay.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed_state else 0
		replay.pressed = pressed_state
		replay.position = pointer
		replay.global_position = pointer
		replay.alt_pressed = bool(_command_modifiers.get("alt", false))
		replay.shift_pressed = bool(_command_modifiers.get("shift", false))
		replay.ctrl_pressed = bool(_command_modifiers.get("ctrl", false))
		replay.meta_pressed = bool(_command_modifiers.get("meta", false))
		replay.set_meta(RALLY_REPLAY_META, true)
		Input.parse_input_event(replay)

func _command_belongs_to_gui() -> bool:
	if not is_inside_tree():
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	return _control_chain_blocks_command(hovered)

## COMMAND is captured in _input() before normal GUI dispatch. Direct STOP controls (buttons, panels)
## own the click. Decorative children can opt their containing surface in with
## `blocks_world_commands`; do not treat every STOP ancestor as blocking because CanvasLayer UI roots
## may span the viewport and would swallow every world command.
static func _control_chain_blocks_command(hovered: Control) -> bool:
	if hovered == null:
		return false
	if hovered.mouse_filter == Control.MOUSE_FILTER_STOP:
		return true
	var control := hovered
	while control != null:
		if bool(control.get_meta("blocks_world_commands", false)):
			return true
		control = control.get_parent_control()
	return false

func _commit_rally_at_screen(screen_pos: Vector2) -> int:
	var anchor_id := _pick_character_id(screen_pos)
	var target := Vector3.INF
	if anchor_id != "" and _game_state != null and _game_state.characters.has(anchor_id):
		target = _game_state.get_position(anchor_id)
	else:
		target = _rally_ground_target(screen_pos)
	return _commit_rally(target, anchor_id)

func _commit_rally(target: Vector3, anchor_id := "") -> int:
	if _game_state == null or not target.is_finite() or not _game_state.has_method("command_rally_members"):
		return -1
	var members := _rally_candidate_ids()
	if anchor_id != "":
		members.erase(anchor_id)
	if members.is_empty():
		return 0
	if not _rally_members_share_anchor_level(members, anchor_id):
		return -1
	return int(_game_state.call("command_rally_members", members, target, anchor_id))

func _rally_ground_target(screen_pos: Vector2) -> Vector3:
	var player := _resolve_active_player()
	if player == null or not player.has_method("_raycast_ground"):
		return Vector3.INF
	var world_hit = player.call("_raycast_ground", screen_pos)
	if not (world_hit is Vector3) or not (world_hit as Vector3).is_finite():
		return Vector3.INF
	var target: Vector3 = world_hit
	if _game_state != null and _game_state.coord_map != null:
		target = _game_state.coord_map.to_data(target)
	return target

func _rally_candidate_ids() -> Array[String]:
	var ids: Array[String] = []
	var hud = _resolve_hud()
	if hud == null or not hud.has_method("get_portrait_ids") or _game_state == null:
		return ids
	var locked: Array = hud.get_hold_locked_ids() if hud.has_method("get_hold_locked_ids") else []
	for raw_id in hud.get_portrait_ids():
		var id := str(raw_id)
		if (not _game_state.characters.has(id) or locked.has(id)
				or (_game_state.has_method("can_accept_move_command")
					and not bool(_game_state.call("can_accept_move_command", id)))
				or (not _game_state.has_method("can_accept_move_command")
					and _game_state.has_method("is_downed") and _game_state.is_downed(id))):
			continue
		ids.append(id)
	return ids

func _rally_members_share_anchor_level(members: Array[String], anchor_id: String) -> bool:
	if anchor_id == "" or _game_state == null or not _game_state.characters.has(anchor_id):
		return true
	var anchor_level := int(_game_state.get_character_level(anchor_id))
	for id in members:
		if not _game_state.characters.has(id) or int(_game_state.get_character_level(id)) != anchor_level:
			return false
	return true

## Once the hold crosses the configured threshold, replace the ambiguous cursor ring with the same
## destination formation and route computation that release will commit. The signature cache keeps
## stationary holds read-only and cheap instead of pathfinding every frame.
func _update_rally_preview_at_screen(screen_pos: Vector2) -> void:
	var anchor_id := _pick_character_id(screen_pos)
	var target := Vector3.INF
	if anchor_id != "" and _game_state.characters.has(anchor_id):
		target = _game_state.get_position(anchor_id)
	else:
		target = _rally_ground_target(screen_pos)
	_update_rally_preview(target, anchor_id)

func _update_rally_preview(target: Vector3, anchor_id := "") -> void:
	if _game_state == null or not _game_state.has_method("compute_rally_destinations"):
		_clear_rally_preview()
		return
	var members := _rally_candidate_ids()
	if anchor_id != "":
		members.erase(anchor_id)
	if not target.is_finite() or members.is_empty() or not _rally_members_share_anchor_level(members, anchor_id):
		_clear_rally_preview()
		return
	var signature := "%s|%s|%s" % [anchor_id, str(target), ",".join(members)]
	if signature == _rally_preview_signature:
		return
	_clear_rally_preview()
	_rally_preview_signature = signature
	var raw_destinations = _game_state.call("compute_rally_destinations", members, target, anchor_id)
	if not (raw_destinations is Array) or raw_destinations.size() != members.size():
		_clear_rally_preview()
		return
	# Resolve and lock every member BEFORE assigning any formation endpoints. Activating a Player's
	# external preview clears its previous single/group hover, which can touch other party members;
	# doing that cleanup as a first pass prevents a later member from erasing an earlier Rally slot.
	var entries: Array[Dictionary] = []
	for i in range(members.size()):
		var id := members[i]
		var destination: Vector3 = raw_destinations[i]
		var node := _find_character_node(id)
		if node == null:
			continue
		entries.append({"id": id, "destination": destination, "node": node})
	for entry in entries:
		var node: Node = entry["node"]
		if node.has_method("set_external_path_preview_active"):
			node.call("set_external_path_preview_active", true)
	for entry in entries:
		var id: String = entry["id"]
		var destination: Vector3 = entry["destination"]
		var node: Node3D = entry["node"]
		var renderer: PathRenderer = _rally_previews.get(id)
		if renderer == null or not is_instance_valid(renderer):
			renderer = PathRendererScript.new()
			renderer.preview_style = true
			add_child(renderer)
			var line_color := Color(0.34, 1.0, 0.62, 0.9)
			if "color" in node:
				line_color = node.color
			renderer.setup(_game_state, "", line_color, node)
			_rally_previews[id] = renderer
		_rally_preview_nodes[id] = node
		var raw_path = _game_state.call("compute_preview_path", id, destination)
		var path: Array[Vector3] = []
		if raw_path is Array:
			for point in raw_path:
				if point is Vector3:
					path.append(point)
		if path.size() >= 2:
			renderer.set_explicit_path(path, 1)
		else:
			renderer.clear_explicit_path()
		if "preview_move_target" in node:
			node.preview_move_target = path[path.size() - 1] if not path.is_empty() else destination

func _clear_rally_preview() -> void:
	for raw_id in _rally_previews.keys():
		var renderer: PathRenderer = _rally_previews.get(raw_id)
		if renderer != null and is_instance_valid(renderer):
			renderer.clear_explicit_path()
		var node: Node = _rally_preview_nodes.get(raw_id)
		if node != null and is_instance_valid(node) and "preview_move_target" in node:
			node.preview_move_target = Vector3.INF
		if node != null and is_instance_valid(node) and node.has_method("set_external_path_preview_active"):
			node.call("set_external_path_preview_active", false)
	_rally_preview_signature = ""

func _find_character_node(id: String) -> Node3D:
	var cached = _rally_preview_nodes.get(id)
	if cached != null and is_instance_valid(cached):
		return cached
	if _active_player != null and is_instance_valid(_active_player):
		if "char_id" in _active_player and str(_active_player.char_id) == id:
			_rally_preview_nodes[id] = _active_player
			return _active_player
	var root: Node = _scene_root if _scene_root != null else get_parent()
	if root == null:
		return null
	for candidate in root.find_children("*", "", true, false):
		if candidate is Node3D and "char_id" in candidate and str(candidate.char_id) == id:
			_rally_preview_nodes[id] = candidate
			return candidate
	return null

func _pick_character_id(screen_pos: Vector2) -> String:
	var camera := _resolve_camera()
	var hud = _resolve_hud()
	if camera == null or hud == null or not hud.has_method("get_portrait_ids") or _game_state == null:
		return ""
	var best := ""
	var best_distance := PICK_SCREEN_RADIUS
	for raw_id in hud.get_portrait_ids():
		var id := str(raw_id)
		if (not _game_state.characters.has(id)
				or (_game_state.has_method("is_downed") and _game_state.is_downed(id))):
			continue
		var distance := camera.unproject_position(_game_state.get_render_position(id)).distance_to(screen_pos)
		if distance < best_distance:
			best_distance = distance
			best = id
	return best

func _resolve_active_player() -> Node:
	if _active_player != null and is_instance_valid(_active_player):
		return _active_player
	if _scene_root != null:
		var player = _scene_root.get("_player")
		if player != null and is_instance_valid(player):
			return player
	return null

# --- Selection commits (shared by live input + headless API) ---------------

func _commit_pick(screen_pos: Vector2) -> void:
	var cam := _resolve_camera()
	var hud = _resolve_hud()
	if cam == null or hud == null:
		return
	var best := ""
	var best_d := PICK_SCREEN_RADIUS
	for id in _selectable_ids():
		var d := cam.unproject_position(_game_state.get_render_position(id)).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = id
	if best != "":
		hud.set_active_portrait(best)
	else:
		_deselect_extras()

func _commit_box_select(rect: Rect2) -> void:
	var cam := _resolve_camera()
	var hud = _resolve_hud()
	if cam == null or hud == null:
		return
	var inside: Array[String] = []
	for id in _selectable_ids():
		if rect.has_point(cam.unproject_position(_game_state.get_render_position(id))):
			inside.append(id)
	if inside.is_empty():
		_deselect_extras()
	elif inside.size() == 1:
		hud.set_active_portrait(inside[0])
	else:
		if hud.has_method("set_multi_select_enabled"):
			hud.set_multi_select_enabled(true)
		hud.set_selected_portraits(inside)

## There is always a controlled leader, so an empty click collapses a multi-selection back to it
## rather than to nothing (you never end up controlling no one).
func _deselect_extras() -> void:
	var hud = _resolve_hud()
	if hud == null or not hud.has_method("get_selected_ids"):
		return
	var sel: Array = hud.get_selected_ids()
	if sel.size() > 1 and hud.has_method("set_selected_portraits"):
		hud.set_selected_portraits([sel[0]])

# --- Helpers ---------------------------------------------------------------

func _selectable_ids() -> Array:
	var out: Array[String] = []
	var hud = _resolve_hud()
	if hud == null or not hud.has_method("get_portrait_ids") or _game_state == null:
		return out
	for raw in hud.get_portrait_ids():
		var id := str(raw)
		if _game_state.characters.has(id):
			out.append(id)
	return out

func _resolve_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	if is_inside_tree():
		return get_viewport().get_camera_3d()
	return null

func _defer_to_pick_mode() -> bool:
	var p: Node = _active_player
	if (p == null or not is_instance_valid(p)) and _scene_root != null:
		p = _scene_root.get("_player")
	return p != null and is_instance_valid(p) and p.has_method("is_pick_mode") and bool(p.call("is_pick_mode"))

# --- Headless API (display-free; tests drive the same commit math) ----------

func headless_pick(screen_pos: Vector2, camera: Camera3D = null) -> void:
	if camera != null:
		_camera = camera
	_commit_pick(screen_pos)

func headless_box_select(rect: Rect2, camera: Camera3D = null) -> void:
	if camera != null:
		_camera = camera
	_commit_box_select(rect)

func headless_rally_candidate_ids() -> Array[String]:
	return _rally_candidate_ids()

func headless_commit_rally(target: Vector3, anchor_id := "") -> int:
	return _commit_rally(target, anchor_id)

func headless_preview_rally(target: Vector3, anchor_id := "") -> Dictionary:
	_update_rally_preview(target, anchor_id)
	var final_positions := {}
	for raw_id in _rally_preview_nodes.keys():
		var id := str(raw_id)
		var node: Node = _rally_preview_nodes.get(id)
		if node != null and is_instance_valid(node) and "preview_move_target" in node:
			var destination = node.preview_move_target
			if destination is Vector3 and (destination as Vector3).is_finite():
				final_positions[id] = destination
	return final_positions

func headless_classify_command_hold(elapsed: float, cancelled := false, drag_distance := 0.0) -> String:
	if cancelled or _command_drag_would_cancel(drag_distance, elapsed):
		return "cancelled"
	return "rally" if elapsed >= _rally_hold_duration() else "short"
