class_name InputHints
extends RefCounted

## Human-readable label for the CURRENT binding of an input action, so prompts and HUD hints show
## the real control instead of a hardcoded letter. Read the binding, never bake a key into a string:
## a rebind, a plugged-in controller, or a future on-screen mapping is then reflected automatically.
##
## Device awareness: when a controller is connected AND the action carries a joypad binding, the
## gamepad button wins; otherwise the keyboard key (or mouse button) is returned. An action with no
## joypad binding still reports its keyboard key even with a controller attached — the binding is the
## source of truth, so once a joypad event is added to the action this helper picks it up for free.
##
## Mobile note: touch builds drive these actions through on-screen HUD buttons, so a key label is not
## the right affordance there — a touch-facing prompt should point at the on-screen control. This
## helper still returns the bound key as a truthful fallback rather than inventing one.
static func label_for_action(action: String, fallback: String = "") -> String:
	if action == "" or not InputMap.has_action(action):
		return fallback
	var key_label := ""
	var joy_label := ""
	var mouse_label := ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and key_label == "":
			key_label = _key_label(ev)
		elif ev is InputEventJoypadButton and joy_label == "":
			joy_label = _joypad_label(ev)
		elif ev is InputEventMouseButton and mouse_label == "":
			mouse_label = _mouse_label(ev)
	if _using_joypad() and joy_label != "":
		return joy_label
	if key_label != "":
		return key_label
	if joy_label != "":
		return joy_label
	if mouse_label != "":
		return mouse_label
	return fallback

## A bracketed token for inline prompts, e.g. "[Z]". Empty string when the action is unbound (so a
## caller can drop the bracket cleanly rather than print "[]").
static func bracket(action: String, fallback: String = "") -> String:
	var label := label_for_action(action, fallback)
	return "[%s]" % label if label != "" else ""

static func _using_joypad() -> bool:
	return not Input.get_connected_joypads().is_empty()

static func _key_label(ev: InputEventKey) -> String:
	var code := ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
	if code == 0:
		return ""
	return OS.get_keycode_string(code)

static func _joypad_label(ev: InputEventJoypadButton) -> String:
	match ev.button_index:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		_: return "Button %d" % ev.button_index

static func _mouse_label(ev: InputEventMouseButton) -> String:
	match ev.button_index:
		MOUSE_BUTTON_LEFT: return "LMB"
		MOUSE_BUTTON_RIGHT: return "RMB"
		MOUSE_BUTTON_MIDDLE: return "MMB"
		_: return "Mouse %d" % ev.button_index
