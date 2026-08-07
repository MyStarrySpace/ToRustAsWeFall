class_name RallyHoldIndicator
extends Control

## Wall-clock feedback for the COMMAND hold gesture. Gameplay commits only on release; this overlay
## merely shows when that release will mean RALLY ALL rather than one classified short command.

const RADIUS := 24.0
const START_ANGLE := -PI * 0.5
const READY_COLOR := Color(0.34, 1.0, 0.62, 0.98)
const CHARGING_COLOR := Color(0.30, 0.70, 1.0, 0.94)
const CANCEL_COLOR := Color(1.0, 0.35, 0.25, 0.95)
const PLAYER_OVERLAY_PRESENTER_GROUP := &"player_observation_overlay_presenters"

var _pointer := Vector2.ZERO
var _progress := 0.0
var _member_count := 0
var _state := "hidden"
var _blocked_reason := ""
var _flash_left := 0.0
var _flash_frames_left := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_to_group(PLAYER_OVERLAY_PRESENTER_GROUP)

func begin(pointer: Vector2, member_count: int) -> void:
	_pointer = pointer
	_progress = 0.0
	_member_count = maxi(0, member_count)
	_state = "charging"
	_blocked_reason = ""
	_flash_left = 0.0
	_flash_frames_left = 0
	visible = true
	queue_redraw()

func update_hold(pointer: Vector2, progress: float, cancelled := false,
		target_valid := true, blocked_reason := "") -> void:
	_pointer = pointer
	_progress = clampf(progress, 0.0, 1.0)
	_blocked_reason = str(blocked_reason).strip_edges().to_upper()
	if cancelled:
		_state = "cancelled"
	elif _progress < 1.0:
		_state = "charging"
	elif not target_valid:
		_state = "blocked"
	else:
		# A rally the party can partly answer commits, so it is not BLOCKED -- but calling it
		# RALLY ALL would lie about the member being left behind. Name them instead.
		_state = "partial" if not _blocked_reason.is_empty() else "ready"
	visible = true
	queue_redraw()

func commit(member_count: int) -> void:
	_member_count = maxi(0, member_count)
	_progress = 1.0
	_state = "committed"
	_blocked_reason = ""
	_flash_left = 0.45
	_flash_frames_left = 2
	visible = true
	queue_redraw()

func reject(reason := "") -> void:
	_member_count = 0
	_progress = 1.0
	_state = "empty"
	_blocked_reason = str(reason).strip_edges().to_upper()
	_flash_left = 0.45
	_flash_frames_left = 2
	visible = true
	queue_redraw()

func cancel() -> void:
	_state = "hidden"
	_blocked_reason = ""
	_flash_left = 0.0
	_flash_frames_left = 0
	visible = false
	queue_redraw()


## Public read-only view of the exact overlay currently rendered. Automated
## players use this instead of reading the Control's private gesture state.
func get_player_presentation() -> Dictionary:
	if not is_visible_in_tree() or _state == "hidden":
		return {"visible": false}
	return {
		"state": _state,
		"text": _presentation_text(),
		"progress": snappedf(clampf(_progress, 0.0, 1.0), 0.1),
		"screen": [int(roundf(_pointer.x)), int(roundf(_pointer.y))],
		"visible": true,
	}

func _process(delta: float) -> void:
	if _state not in ["committed", "empty"]:
		return
	# The result must survive at least one actually rendered frame. Otherwise a
	# slow frame can consume the entire wall-clock flash before a player (or an
	# input-driven accessibility observer) can see whether the group command was
	# queued or refused.
	if _flash_frames_left > 0:
		_flash_frames_left -= 1
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
	elif _state in ["cancelled", "blocked", "empty"]:
		color = CANCEL_COLOR
	draw_circle(_pointer, RADIUS + 5.0, Color(0.015, 0.02, 0.03, 0.82))
	draw_arc(_pointer, RADIUS, 0.0, TAU, 48, Color(color, 0.24), 4.0, true)
	draw_arc(_pointer, RADIUS, START_ANGLE, START_ANGLE + TAU * _progress, 48, color, 4.0, true)
	draw_circle(_pointer, 3.5, color)
	var label := _presentation_text()
	var font := ThemeDB.fallback_font
	var font_size := 12
	var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_pos := _pointer + Vector2(-size.x * 0.5, RADIUS + 22.0)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _presentation_text() -> String:
	match _state:
		"ready":
			return "RELEASE: RALLY ALL"
		"committed":
			return "RALLY QUEUED  %d" % _member_count
		"cancelled":
			return "RALLY CANCELLED"
		"partial":
			return _blocked_reason
		"blocked":
			return _blocked_reason if not _blocked_reason.is_empty() \
				else "NO COMPLETE PARTY ROUTE"
		"empty":
			return _blocked_reason if not _blocked_reason.is_empty() \
				else "RALLY REFUSED"
	return "HOLD"
