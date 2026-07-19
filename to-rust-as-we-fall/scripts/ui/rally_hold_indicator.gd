class_name RallyHoldIndicator
extends Control

## Wall-clock feedback for the COMMAND hold gesture. Gameplay commits only on release; this overlay
## merely shows when that release will mean RALLY ALL rather than replaying an ordinary right-click.

const RADIUS := 24.0
const START_ANGLE := -PI * 0.5
const READY_COLOR := Color(0.34, 1.0, 0.62, 0.98)
const CHARGING_COLOR := Color(0.30, 0.70, 1.0, 0.94)
const CANCEL_COLOR := Color(1.0, 0.35, 0.25, 0.95)

var _pointer := Vector2.ZERO
var _progress := 0.0
var _member_count := 0
var _state := "hidden"
var _flash_left := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func begin(pointer: Vector2, member_count: int) -> void:
	_pointer = pointer
	_progress = 0.0
	_member_count = maxi(0, member_count)
	_state = "charging"
	_flash_left = 0.0
	visible = true
	queue_redraw()

func update_hold(pointer: Vector2, progress: float, cancelled := false) -> void:
	_pointer = pointer
	_progress = clampf(progress, 0.0, 1.0)
	_state = "cancelled" if cancelled else ("ready" if _progress >= 1.0 else "charging")
	visible = true
	queue_redraw()

func commit(member_count: int) -> void:
	_member_count = maxi(0, member_count)
	_progress = 1.0
	_state = "committed"
	_flash_left = 0.45
	visible = true
	queue_redraw()

func reject() -> void:
	_member_count = 0
	_progress = 1.0
	_state = "empty"
	_flash_left = 0.45
	visible = true
	queue_redraw()

func cancel() -> void:
	_state = "hidden"
	_flash_left = 0.0
	visible = false
	queue_redraw()

func _process(delta: float) -> void:
	if _state not in ["committed", "empty"]:
		return
	_flash_left = maxf(0.0, _flash_left - delta)
	if _flash_left <= 0.0:
		cancel()

func _draw() -> void:
	if _state == "hidden":
		return
	var color := CHARGING_COLOR
	if _state in ["ready", "committed"]:
		color = READY_COLOR
	elif _state in ["cancelled", "empty"]:
		color = CANCEL_COLOR
	draw_circle(_pointer, RADIUS + 5.0, Color(0.015, 0.02, 0.03, 0.82))
	draw_arc(_pointer, RADIUS, 0.0, TAU, 48, Color(color, 0.24), 4.0, true)
	draw_arc(_pointer, RADIUS, START_ANGLE, START_ANGLE + TAU * _progress, 48, color, 4.0, true)
	draw_circle(_pointer, 3.5, color)
	var label := "HOLD"
	match _state:
		"ready":
			label = "RELEASE: RALLY ALL"
		"committed":
			label = "RALLY QUEUED  %d" % _member_count
		"cancelled":
			label = "RALLY CANCELLED"
		"empty":
			label = "NO FREE PARTY"
	var font := ThemeDB.fallback_font
	var font_size := 12
	var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_pos := _pointer + Vector2(-size.x * 0.5, RADIUS + 22.0)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
