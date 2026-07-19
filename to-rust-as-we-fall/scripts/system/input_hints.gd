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
	var event := primary_event_for_action(action)
	return label_for_event(event, fallback)

## The real event behind a prompt. Keeping the InputEvent intact lets visual prompts choose a
## keyboard keycap, a highlighted mouse button, or a future controller glyph without guessing from
## an already-flattened string. `device_family` may be "keyboard", "mouse", or "joypad".
static func primary_event_for_action(action: StringName, device_family: String = "") -> InputEvent:
	if action == &"" or not InputMap.has_action(action):
		return null
	var events := InputMap.action_get_events(action)
	if device_family != "":
		for event in events:
			if event_family(event) == device_family:
				return event
	if _using_joypad():
		for event in events:
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				return event
	# Desktop prompts prefer keyboard/mouse in the authored InputMap order. This preserves actions
	# whose primary binding is deliberately a mouse button (select, command, pan, and wheel zoom).
	for event in events:
		if event is InputEventKey or event is InputEventMouseButton:
			return event
	return events[0] if not events.is_empty() else null

static func event_family(event: InputEvent) -> String:
	if event is InputEventKey:
		return "keyboard"
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return "mouse"
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return "joypad"
	return "unknown"

static func label_for_event(event: InputEvent, fallback: String = "") -> String:
	if event == null:
		return fallback
	var base := base_label_for_event(event)
	if base == "":
		return fallback
	var modifiers := modifier_labels_for_event(event)
	modifiers.append(base)
	return "+".join(modifiers)

static func base_label_for_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return _key_label(event as InputEventKey)
	if event is InputEventMouseButton:
		return _mouse_label(event as InputEventMouseButton)
	if event is InputEventJoypadButton:
		return _joypad_label(event as InputEventJoypadButton)
	return ""

static func modifier_labels_for_event(event: InputEvent) -> Array[String]:
	var labels: Array[String] = []
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.ctrl_pressed: labels.append("Ctrl")
		if key_event.alt_pressed: labels.append("Alt")
		if key_event.shift_pressed: labels.append("Shift")
		if key_event.meta_pressed: labels.append("Meta")
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.ctrl_pressed: labels.append("Ctrl")
		if mouse_event.alt_pressed: labels.append("Alt")
		if mouse_event.shift_pressed: labels.append("Shift")
		if mouse_event.meta_pressed: labels.append("Meta")
	return labels

## A bracketed token for inline prompts, e.g. "[Z]". Empty string when the action is unbound (so a
## caller can drop the bracket cleanly rather than print "[]").
static func bracket(action: String, fallback: String = "") -> String:
	var label := label_for_action(action, fallback)
	return "[%s]" % label if label != "" else ""

static func _using_joypad() -> bool:
	return not Input.get_connected_joypads().is_empty()

static func physical_key_localization_supported(
		display_server_name: String = DisplayServer.get_name(),
		has_web_feature: bool = OS.has_feature("web")) -> bool:
	var server := display_server_name.to_lower()
	return not has_web_feature and server != "web" and server != "headless"

static func _key_label(ev: InputEventKey) -> String:
	var code: Key = ev.key_label
	if ev.physical_keycode != KEY_NONE:
		code = ev.physical_keycode
		# Web and headless display servers do not implement physical-key localization and log an
		# error for every query. The physical keycode itself is still the truthful live binding;
		# only native display servers need the extra localized-keyboard lookup.
		if physical_key_localization_supported():
			var localized := DisplayServer.keyboard_get_label_from_physical(ev.physical_keycode)
			if localized != KEY_NONE:
				code = localized
	elif ev.keycode != KEY_NONE:
		code = ev.keycode
	if code == 0:
		return ""
	return _compact_key_label(code)

## Godot exposes printable punctuation through descriptive OS names on some platforms
## ("Semicolon", "BracketLeft", and so on). Those names are useful for diagnostics but too wide
## for a keycap. Compact only the punctuation used by the direct-ability bank after physical-key
## localization has run; localized letters and every other key retain the platform-provided label.
static func _compact_key_label(code: Key) -> String:
	match code:
		KEY_SEMICOLON: return ";"
		KEY_BRACKETLEFT: return "["
		KEY_BRACKETRIGHT: return "]"
		KEY_APOSTROPHE: return "'"
		KEY_BACKSLASH: return String.chr(92)
		_: return OS.get_keycode_string(code)

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
		MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
		MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
		MOUSE_BUTTON_WHEEL_LEFT: return "Wheel left"
		MOUSE_BUTTON_WHEEL_RIGHT: return "Wheel right"
		MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
		MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
		_: return "Mouse %d" % ev.button_index
