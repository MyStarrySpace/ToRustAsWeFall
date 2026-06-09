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

const DRAG_THRESHOLD := 10.0       # px — click vs box-drag (Phylactory CLICK_DRAG_PIXEL_THRESHOLD)
const PICK_SCREEN_RADIUS := 56.0   # px — how near a single click must land to pick a character

var _game_state
var _hud
var _scene_root: Node
var _active_player: Node3D
var _camera: Camera3D

var _marquee
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragging := false

## scene_root is the sequence (it owns _hud + _player, both created after the base _ready), so the HUD
## and active player are resolved lazily from it — same trick player.gd selection deferral uses.
func setup(game_state, scene_root: Node) -> void:
	_game_state = game_state
	_scene_root = scene_root
	_ensure_marquee()

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
	var layer := CanvasLayer.new()
	layer.name = "SelectionMarqueeLayer"
	layer.layer = 50
	add_child(layer)
	_marquee = preload("res://scripts/game/characters/selection_marquee.gd").new()
	_marquee.name = "SelectionMarquee"
	_marquee.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_marquee)

# --- Live input ------------------------------------------------------------

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
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_pressed = true
		_dragging = false
		_press_pos = mb.position
		# Don't consume on press — it might be a click or a drag; commit on release.
	else:
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
	if not _pressed or _marquee == null or not is_inside_tree():
		return
	var cur := get_viewport().get_mouse_position()
	if not _dragging and _press_pos.distance_to(cur) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging:
		_marquee.set_rect(Rect2(_press_pos, cur - _press_pos))

# --- Selection commits (shared by live input + headless API) ---------------

func _commit_pick(screen_pos: Vector2) -> void:
	var cam := _resolve_camera()
	var hud = _resolve_hud()
	if cam == null or hud == null:
		return
	var best := ""
	var best_d := PICK_SCREEN_RADIUS
	for id in _selectable_ids():
		var d := cam.unproject_position(_game_state.get_position(id)).distance_to(screen_pos)
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
		if rect.has_point(cam.unproject_position(_game_state.get_position(id))):
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
