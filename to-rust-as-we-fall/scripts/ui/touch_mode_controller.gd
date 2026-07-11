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
##           the tapped object. The default — the verb you play with.
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
var _panel: Control
var _cam_dragging := false
var _press_pos := Vector2.ZERO
var _pressed := false

func _ready() -> void:
	layer = 55
	_build_ui()
	_refresh_visibility()

func setup(scene_root: Node) -> void:
	_scene_root = scene_root

## Dev-console / test switch: show the cluster without a touchscreen.
func set_forced(on: bool) -> void:
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
	mode = new_mode
	_cam_dragging = false
	_pressed = false
	_style_buttons()
	mode_changed.emit(mode)

func _refresh_visibility() -> void:
	visible = _forced or DisplayServer.is_touchscreen_available()

# --- Input routing (runs before gui/physics/unhandled; steps aside when the tap is theirs) -----

func _input(event: InputEvent) -> void:
	if not is_active() or _yield_to_scene():
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
				get_viewport().set_input_as_handled()
		else:
			if mode == "camera" and _cam_dragging:
				_cam_dragging = false
				get_viewport().set_input_as_handled()
			elif mode == "action" and _pressed:
				if _press_pos.distance_to(mb.position) <= TAP_DRAG_THRESHOLD:
					_dispatch_command_click(mb.position)
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
	if _scene_root == null:
		return false
	var dlg = _scene_root.get("_dialogue")
	if dlg != null and is_instance_valid(dlg) and dlg.has_method("is_active") and bool(dlg.call("is_active")):
		return true
	var p = _scene_root.get("_player")
	return p != null and is_instance_valid(p) and p.has_method("is_pick_mode") and bool(p.call("is_pick_mode"))

## A tap in ACTION mode becomes the desktop COMMAND click: a synthetic right-button press+release
## through the full input pipeline (physics picking included), so interactables and player.gd
## handle it exactly as a real right click — one code path, no parallel action dispatch.
func _dispatch_command_click(pos: Vector2) -> void:
	for pressed_state in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = pressed_state
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)

# --- The on-screen cluster ---------------------------------------------------------------------

func _build_ui() -> void:
	if Engine.is_editor_hint():
		return
	_panel = VBoxContainer.new()
	_panel.name = "TouchModeCluster"
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.position = Vector2(-8, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.add_theme_constant_override("separation", 6)
	add_child(_panel)
	for m in MODES:
		var b := Button.new()
		b.name = "TouchMode_%s" % m
		b.text = str(MODE_LABELS[m])
		b.custom_minimum_size = Vector2(96, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): set_mode(str(m)))
		_panel.add_child(b)
		_buttons[m] = b
	_style_buttons()

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
