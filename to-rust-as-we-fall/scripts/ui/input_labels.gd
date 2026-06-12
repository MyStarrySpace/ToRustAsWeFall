class_name InputLabels
extends RefCounted

## Human-readable names for the CURRENT input bindings — every player-facing prompt that names a
## control derives from the InputMap through here, so a rebind (or the RTS overhaul moving
## interact to right-click) never leaves stale instructions on screen. Text containing tokens
## like "{command}" or "{select}" substitutes the live binding via expand().

const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Left-click",
	MOUSE_BUTTON_RIGHT: "Right-click",
	MOUSE_BUTTON_MIDDLE: "Middle-click",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
}

static func action_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return str(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton:
			return MOUSE_NAMES.get((event as InputEventMouseButton).button_index, "Click")
		if event is InputEventKey:
			var key := event as InputEventKey
			var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code)
	return str(action)

## Replace "{action_name}" tokens with the live binding's label. Lowercase token output keeps
## sentence case natural ("right-click to inspect"); capitalized via the text itself when leading.
static func expand(text: String) -> String:
	var out := text
	for action in InputMap.get_actions():
		var token := "{%s}" % action
		if out.contains(token):
			out = out.replace(token, action_label(action))
	return out
