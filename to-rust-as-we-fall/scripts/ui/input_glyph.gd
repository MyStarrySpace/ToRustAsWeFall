class_name InputGlyph
extends Control

## Compact, non-interactive visual for an InputMap binding.
## Keyboard labels are drawn over a stretchable SVG keycap; mouse bindings use
## dedicated silhouettes so prompts stay legible at HUD scale.

const GLYPH_HEIGHT := 22.0
const KEY_MIN_WIDTH := 23.0
const MOUSE_WIDTH := 18.0
const KEY_HORIZONTAL_PADDING := 11.0
const APPROX_CHARACTER_WIDTH := 6.5

const KEYCAP_TEXTURE: Texture2D = preload("res://assets/ui/input/keycap.svg")
const MOUSE_LEFT_TEXTURE: Texture2D = preload("res://assets/ui/input/mouse_left.svg")
const MOUSE_RIGHT_TEXTURE: Texture2D = preload("res://assets/ui/input/mouse_right.svg")
const MOUSE_MIDDLE_TEXTURE: Texture2D = preload("res://assets/ui/input/mouse_middle.svg")
const MOUSE_WHEEL_UP_TEXTURE: Texture2D = preload("res://assets/ui/input/mouse_wheel_up.svg")
const MOUSE_WHEEL_DOWN_TEXTURE: Texture2D = preload("res://assets/ui/input/mouse_wheel_down.svg")

var action: StringName:
	get:
		return _action
	set(value):
		_action = value
		set_process(_action != &"")
		refresh_binding()

var fallback_label: String:
	get:
		return _fallback_label
	set(value):
		_fallback_label = value
		refresh_binding()

var _action: StringName = &""
var _fallback_label := ""
var _binding_label := ""
var _binding_kind := "unbound"
var _binding_signature := ""
var _binding_poll_seconds := 0.0
var _attached_button: BaseButton
var _button_right_inset := 6.0
var _texture_rect: TextureRect
var _key_label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process(false)


func _ready() -> void:
	_bind_authored_nodes()
	set_process(_action != &"")
	refresh_binding()


func _bind_authored_nodes() -> void:
	if _texture_rect == null:
		_texture_rect = get_node_or_null("BindingTexture") as TextureRect
	if _key_label == null:
		_key_label = get_node_or_null("KeyLabel") as Label


## Resolve and display the current primary InputMap event for [param action_name].
func configure_action(action_name: StringName, fallback: String = "") -> InputGlyph:
	_action = action_name
	_fallback_label = fallback
	set_process(_action != &"")
	refresh_binding()
	return self


## Display a literal keycap, useful for modifier keys in a composed shortcut.
func configure_key_label(label: String) -> InputGlyph:
	_action = &""
	_fallback_label = label
	set_process(false)
	_binding_label = label
	_binding_kind = "keyboard"
	_apply_keycap(label)
	return self


## Re-read InputMap so a live settings/rebind change is reflected immediately.
func refresh_binding() -> void:
	_bind_authored_nodes()
	if _texture_rect == null:
		return
	_binding_signature = _current_binding_signature()
	if _action != &"" and InputMap.has_action(_action):
		var primary_event := InputHints.primary_event_for_action(_action)
		if primary_event != null and _apply_event(primary_event):
			return
		var events := InputMap.action_get_events(_action)
		for event in events:
			if _apply_event(event):
				return
	if not _fallback_label.is_empty():
		_binding_label = _fallback_label
		_binding_kind = "keyboard"
		_apply_keycap(_fallback_label)
	else:
		_binding_label = ""
		_binding_kind = "unbound"
		_apply_keycap("?")


func _process(delta: float) -> void:
	if _action == &"":
		return
	_binding_poll_seconds += delta
	if _binding_poll_seconds < 0.25:
		return
	_binding_poll_seconds = 0.0
	if _current_binding_signature() != _binding_signature:
		refresh_binding()


func get_binding_label() -> String:
	return _binding_label


## Returns keyboard, mouse_left/right/middle/wheel_up/wheel_down, joypad, or unbound.
func get_binding_kind() -> String:
	return _binding_kind


## Convenience for buttons that want a binding badge pinned to their right edge.
## The glyph ignores mouse input, so the button remains clickable through it.
func attach_to_button(button: BaseButton, right_inset: float = 6.0) -> InputGlyph:
	if button == null:
		return self
	if get_parent() != button:
		if get_parent() != null:
			reparent(button)
		else:
			button.add_child(self)
	_attached_button = button
	_button_right_inset = right_inset
	_sync_attached_button_layout()
	return self


func _apply_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var label := _key_event_label(event)
		if label.is_empty():
			return false
		_binding_label = label
		_binding_kind = "keyboard"
		_apply_keycap(label)
		return true
	if event is InputEventMouseButton:
		return _apply_mouse_button(event.button_index)
	if event is InputEventJoypadButton:
		var label := _joypad_button_label(event.button_index)
		_binding_label = label
		_binding_kind = "joypad"
		_apply_keycap(label)
		return true
	return false


func _apply_mouse_button(button_index: MouseButton) -> bool:
	match button_index:
		MOUSE_BUTTON_LEFT:
			_apply_mouse_texture(MOUSE_LEFT_TEXTURE, "LMB", "mouse_left")
		MOUSE_BUTTON_RIGHT:
			_apply_mouse_texture(MOUSE_RIGHT_TEXTURE, "RMB", "mouse_right")
		MOUSE_BUTTON_MIDDLE:
			_apply_mouse_texture(MOUSE_MIDDLE_TEXTURE, "MMB", "mouse_middle")
		MOUSE_BUTTON_WHEEL_UP:
			_apply_mouse_texture(MOUSE_WHEEL_UP_TEXTURE, "Wheel up", "mouse_wheel_up")
		MOUSE_BUTTON_WHEEL_DOWN:
			_apply_mouse_texture(MOUSE_WHEEL_DOWN_TEXTURE, "Wheel down", "mouse_wheel_down")
		_:
			return false
	return true


func _apply_keycap(label: String) -> void:
	_bind_authored_nodes()
	if _texture_rect == null or _key_label == null:
		return
	_texture_rect.texture = KEYCAP_TEXTURE
	_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_key_label.text = label
	_key_label.visible = true
	var estimated_width := KEY_HORIZONTAL_PADDING + APPROX_CHARACTER_WIDTH * float(label.length())
	custom_minimum_size = Vector2(maxf(KEY_MIN_WIDTH, estimated_width), GLYPH_HEIGHT)
	size = custom_minimum_size
	_sync_attached_button_layout()


func _apply_mouse_texture(texture: Texture2D, label: String, kind: String) -> void:
	_bind_authored_nodes()
	if _texture_rect == null or _key_label == null:
		return
	_texture_rect.texture = texture
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_key_label.visible = false
	_binding_label = label
	_binding_kind = kind
	custom_minimum_size = Vector2(MOUSE_WIDTH, GLYPH_HEIGHT)
	size = custom_minimum_size
	_sync_attached_button_layout()


func _current_binding_signature() -> String:
	if _action == &"":
		return ""
	if not InputMap.has_action(_action):
		return "<missing>"
	var parts: PackedStringArray = []
	for event in InputMap.action_get_events(_action):
		parts.append(event.as_text())
	return "|".join(parts)


func _sync_attached_button_layout() -> void:
	if _attached_button == null or not is_instance_valid(_attached_button):
		return
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	offset_left = -custom_minimum_size.x - _button_right_inset
	offset_right = -_button_right_inset
	offset_top = -custom_minimum_size.y * 0.5
	offset_bottom = custom_minimum_size.y * 0.5
	_attached_button.custom_minimum_size.x = maxf(
		_attached_button.custom_minimum_size.x,
		56.0 + custom_minimum_size.x
	)
	for state in ["normal", "hover", "pressed", "disabled"]:
		if not _attached_button.has_theme_stylebox_override(state):
			continue
		var style := _attached_button.get_theme_stylebox(state) as StyleBoxFlat
		if style != null:
			style.content_margin_right = custom_minimum_size.x + _button_right_inset + 6.0


func _key_event_label(event: InputEventKey) -> String:
	var base_label := InputHints.base_label_for_event(event)
	if base_label == "":
		return ""
	var parts: PackedStringArray = []
	if event.ctrl_pressed:
		parts.append("Ctrl")
	if event.alt_pressed:
		parts.append("Alt")
	if event.shift_pressed:
		parts.append("Shift")
	if event.meta_pressed:
		parts.append("Meta")
	parts.append(base_label)
	return "+".join(parts)


func _joypad_button_label(button_index: JoyButton) -> String:
	match button_index:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		_:
			return "B%d" % button_index
