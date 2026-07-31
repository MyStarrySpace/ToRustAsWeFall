class_name TouchModeController
extends CanvasLayer

## MOBILE CONTROL MODES — one finger, three meanings, toggled by an on-screen cluster (desktop
## has three buttons; touch has one finger, so the finger's meaning is a MODE):
##   CAMERA  one-finger drag pans the view (the two-finger pan + pinch-zoom keep working in every
##           mode — they're unambiguous).
##   SELECT  the finger is the LEFT button: tap picks a character, drag draws the marquee (the
##           SelectionController's native language). While this mode is on, every interactable
##           shows its reveal outline (the hold-SHIFT treatment), and tapping one surfaces its
##           hover verb — the LOOK mode.
##   ACTION  a tap is the COMMAND click (the desktop right button): move there / interact with
##           the tapped object. Holding is the same whole-party RALLY gesture as desktop RMB-hold.
##
## The cluster appears automatically on touchscreen devices; the dev console forces it on desktop
## (`touch on`) — the sanctioned door for dev switches. Interception happens at the _input stage,
## BEFORE the gui/physics/unhandled pipeline, and steps aside whenever the tap belongs to someone
## else: a hovered Control (HUD buttons, the pause menu), an active dialogue line (a tap must
## acknowledge it), or a sequence pick-beat (player.is_pick_mode). Mode changes are UI pacing —
## no game state, no EventLog entries; the resulting command clicks log exactly as real ones.

signal mode_changed(mode: String)

const MODES := ["camera", "select", "action"]
const MODE_LABELS := {"camera": "CAMERA", "select": "SELECT", "action": "ACTION"}
const TAP_DRAG_THRESHOLD := 10.0   # px — matches the SelectionController's click-vs-drag line

var mode := "action"

var _scene_root: Node
var _forced := false
var _buttons := {}
@onready var _panel: Control = $TouchModeCluster
var _cam_dragging := false
var _press_pos := Vector2.ZERO
var _pressed := false
var _action_command_proxy_active := false
var _shift_latched := false
var _shift_button: Button = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 55
	_bind_ui()
	visibility_changed.connect(_on_visibility_changed)
	_refresh_visibility()

func setup(scene_root: Node) -> void:
	_scene_root = scene_root

## Dev-console / test switch: show the cluster without a touchscreen.
func set_forced(on: bool) -> void:
	if on != _forced:
		_cancel_action_command_proxy()
		_reset_pointer_state()
	_forced = on
	if not on and mode != "action":
		set_mode("action")   # dropping the surface must also drop its side effects (the reveal)
	_refresh_visibility()

func is_active() -> bool:
	return visible and not Engine.is_editor_hint()

func set_mode(new_mode: String) -> void:
	if not MODES.has(new_mode) or new_mode == mode:
		_style_buttons()
		return
	_cancel_action_command_proxy()
	mode = new_mode
	_reset_pointer_state()
	_style_buttons()
	mode_changed.emit(mode)

func _refresh_visibility() -> void:
	visible = _forced or DisplayServer.is_touchscreen_available()
	if not visible:
		_cancel_action_command_proxy()
		_reset_pointer_state()
		set_shift_latch(false)

func _on_visibility_changed() -> void:
	if not visible:
		_cancel_action_command_proxy()
		_reset_pointer_state()
		set_shift_latch(false)

# --- The touch SHIFT: the modifier button (the `highlight` action) for one-finger play ----------

## Latch/unlatch the game's SHIFT modifier (the `highlight` InputMap action — the reveal AND the
## push-destination commit). A latch is STICKY: the next ACTION tap consumes it, or tapping the
## button again releases it. Pressing the ACTION rather than faking a key keeps every consumer
## (player push grammar, HUD) reading one truth.
func set_shift_latch(on: bool) -> void:
	if on == _shift_latched:
		return
	_shift_latched = on
	if on:
		Input.action_press("highlight")
	else:
		Input.action_release("highlight")
	_style_shift_button()

func is_shift_latched() -> bool:
	return _shift_latched

func _toggle_shift_latch() -> void:
	set_shift_latch(not _shift_latched)

func _process(_delta: float) -> void:
	if _action_command_proxy_active and _must_cancel_action_proxy():
		_cancel_action_command_proxy()
		_reset_pointer_state()
	elif (_cam_dragging or _pressed) and _must_yield_pointer():
		_reset_pointer_state()

func _exit_tree() -> void:
	_cancel_action_command_proxy()
	_reset_pointer_state()
	set_shift_latch(false)

# --- Input routing (runs before gui/physics/unhandled; steps aside when the tap is theirs) -----

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		# Close an issued proxy before any active/yield/pause early return. Normally this is the
		# gesture's one release edge. If ownership changed mid-hold, cancel its timing first.
		if not mb.pressed and _action_command_proxy_active:
			if mb.canceled or _must_cancel_action_proxy():
				_cancel_action_command_proxy(mb.position)
			else:
				_release_action_command_proxy(mb.position)
			_reset_pointer_state()
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and _action_command_proxy_active:
			# Defensive mouse-emulation/multi-touch guard: never allow two unmatched presses.
			_cancel_action_command_proxy(mb.position)
			_reset_pointer_state()
	if _must_yield_pointer():
		if _action_command_proxy_active:
			_cancel_action_command_proxy()
		_reset_pointer_state()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			# yield only to controls that CONSUME the mouse (buttons, panels — MOUSE_FILTER_STOP);
			# pass-through containers hover without owning the tap
			var hov := get_viewport().gui_get_hovered_control()
			if hov != null and hov.mouse_filter == Control.MOUSE_FILTER_STOP:
				return   # the tap belongs to a HUD control
			_press_pos = mb.position
			_pressed = true
			if mode == "camera":
				_cam_dragging = true
				get_viewport().set_input_as_handled()
			# select mode: never intercept — the finger IS the left button
			elif mode == "action":
				# Preserve both edges so SelectionController can distinguish a short command from a
				# configurable hold. It consumes this proxy press and replays a normal RMB click on
				# short release, or commits RALLY ALL on long release.
				_begin_action_command_proxy(mb.position)
				get_viewport().set_input_as_handled()
		else:
			if mode == "camera" and _cam_dragging:
				_cam_dragging = false
				get_viewport().set_input_as_handled()
			_pressed = false
		return
	if event is InputEventMouseMotion and _cam_dragging and mode == "camera":
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam.has_method("pan_by"):
			cam.call("pan_by", (event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()

## The tap belongs to the scene, not to a mode: an active dialogue line (tap acknowledges it) or
## a sequence pick-beat (tap reports the ground target through the select path).
func _yield_to_scene() -> bool:
	if _scene_root == null or not is_instance_valid(_scene_root):
		return false
	var dlg = _scene_root.get("_dialogue")
	if dlg != null and is_instance_valid(dlg) and dlg.has_method("is_active") and bool(dlg.call("is_active")):
		return true
	var p = _scene_root.get("_player")
	return p != null and is_instance_valid(p) and p.has_method("is_pick_mode") and bool(p.call("is_pick_mode"))

func _must_yield_pointer() -> bool:
	return not is_active() or (is_inside_tree() and get_tree().paused) or _yield_to_scene()

func _must_cancel_action_proxy() -> bool:
	return mode != "action" or _must_yield_pointer()

func _reset_pointer_state() -> void:
	_cam_dragging = false
	_pressed = false

func _begin_action_command_proxy(pos: Vector2) -> void:
	if _action_command_proxy_active:
		_cancel_action_command_proxy(pos)
	_action_command_proxy_active = true
	_dispatch_command_edge(pos, true)

func _release_action_command_proxy(pos: Vector2) -> void:
	if not _action_command_proxy_active:
		return
	_action_command_proxy_active = false
	_dispatch_command_edge(pos, false)
	# A latched SHIFT is one-shot: the completed ACTION tap consumed it (the press edge above ran
	# with the modifier held), so it releases here rather than silently sticking on.
	if _shift_latched:
		set_shift_latch(false)

func _cancel_action_command_proxy(pos := Vector2.INF) -> void:
	if not _action_command_proxy_active:
		return
	_action_command_proxy_active = false
	# Cancel SelectionController timing before the closing edge so an ownership transition cannot
	# turn the eventual release into a late short-click or rally.
	var selection = _resolve_selection_controller()
	if selection != null and selection.has_method("cancel_command_hold"):
		selection.call("cancel_command_hold")
	var release_pos: Vector2 = pos
	if not release_pos.is_finite():
		release_pos = get_viewport().get_mouse_position() if is_inside_tree() else _press_pos
	_dispatch_command_edge(release_pos, false)

func _resolve_selection_controller():
	if _scene_root == null or not is_instance_valid(_scene_root):
		return null
	var selection = _scene_root.get_node_or_null("SelectionController")
	if selection == null and "_selection_controller" in _scene_root:
		selection = _scene_root.get("_selection_controller")
	return selection if selection != null and is_instance_valid(selection) else null

## Narrow deterministic inspection hook for gesture-lifecycle tests.
func is_action_command_proxy_active() -> bool:
	return _action_command_proxy_active

## One edge of the desktop COMMAND gesture. SelectionController owns timing and later either replays
## the ordinary click through physics picking or commits an explicit-member whole-party rally.
func _dispatch_command_edge(pos: Vector2, pressed_state: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed_state else 0
	ev.pressed = pressed_state
	ev.position = pos
	ev.global_position = pos
	ev.set_meta("_touch_command_proxy", true)
	Input.parse_input_event(ev)

## Compatibility for focused tests/tools that used the old tap helper directly.
func _dispatch_command_click(pos: Vector2) -> void:
	_dispatch_command_edge(pos, true)
	_dispatch_command_edge(pos, false)

# --- The on-screen cluster ---------------------------------------------------------------------

func _bind_ui() -> void:
	if Engine.is_editor_hint():
		return
	for m in MODES:
		var b := _panel.get_node("TouchMode_%s" % m) as Button
		b.pressed.connect(set_mode.bind(str(m)))
		_buttons[m] = b
	_shift_button = _panel.get_node_or_null("TouchShift") as Button
	if _shift_button != null and not _shift_button.pressed.is_connected(_toggle_shift_latch):
		_shift_button.pressed.connect(_toggle_shift_latch)
	_style_buttons()
	_style_shift_button()

func _style_shift_button() -> void:
	if _shift_button == null or not is_instance_valid(_shift_button):
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.32, 0.24, 0.12, 0.92) if _shift_latched else Color(0.10, 0.11, 0.12, 0.72)
	sb.border_color = Color(0.95, 0.78, 0.30) if _shift_latched else Color(0.30, 0.33, 0.34)
	sb.set_border_width_all(2 if _shift_latched else 1)
	sb.set_corner_radius_all(6)
	_shift_button.add_theme_stylebox_override("normal", sb)
	_shift_button.add_theme_stylebox_override("hover", sb)
	_shift_button.add_theme_stylebox_override("pressed", sb)
	_shift_button.add_theme_color_override("font_color",
		Color(1.0, 0.92, 0.72) if _shift_latched else Color(0.72, 0.74, 0.72))

func _style_buttons() -> void:
	for m in _buttons:
		var b := _buttons[m] as Button
		if b == null or not is_instance_valid(b):
			continue
		var active := str(m) == mode
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.34, 0.24, 0.92) if active else Color(0.10, 0.11, 0.12, 0.72)
		sb.border_color = Color(0.36, 0.91, 0.50) if active else Color(0.30, 0.33, 0.34)
		sb.set_border_width_all(2 if active else 1)
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_color_override("font_color", Color(0.80, 1.0, 0.86) if active else Color(0.72, 0.74, 0.72))
