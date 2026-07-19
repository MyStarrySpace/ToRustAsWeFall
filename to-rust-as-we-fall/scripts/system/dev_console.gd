class_name DevConsole
extends CanvasLayer

## The in-game developer console, toggled with ` (backtick). This is the ONE sanctioned door to
## dev-only switches in normal play — fog of war off, FX debug traces, and whatever a scene
## registers — so gameplay never grows hidden debug keys that collide with player controls.
##
## Self-contained: owns its input (backtick toggle, Enter submits, Esc closes), runs while the
## tree is paused, and exposes register_command() for the host scene. Purely a dev surface —
## commands mutate flags on the host; nothing here touches the data layer directly.

const MAX_LOG_LINES := 120

var _commands := {}          # name -> {call: Callable, help: String}
@onready var _panel: PanelContainer = $ConsolePanel
@onready var _log: RichTextLabel = $ConsolePanel/Content/Log
@onready var _input: LineEdit = $ConsolePanel/Content/Input
var _history: Array[String] = []
var _history_i := -1

func _ready() -> void:
	visible = false
	register_command("help", _cmd_help, "list every command")
	if DisplayServer.is_touchscreen_available():
		_spawn_touch_toggle.call_deferred()

## A touch device has no backtick: a small translucent edge button opens the console (the LineEdit
## then pops the OS soft keyboard). It rides its OWN layer — this layer hides while closed.
func _spawn_touch_toggle() -> void:
	var lay := preload("res://scenes/ui/dev_console_touch_toggle.tscn").instantiate() as CanvasLayer
	var btn := lay.get_node("ConsoleTouchButton") as Button
	btn.pressed.connect(toggle)
	if get_parent() != null:
		get_parent().add_child(lay)

## Register a command. `fn` receives the argument list (Array of String) and returns the line to
## print (or "" for silence). Re-registering a name replaces it, so scenes can override built-ins.
func register_command(cmd_name: String, fn: Callable, help := "") -> void:
	_commands[cmd_name] = {"call": fn, "help": help}

func println(line: String) -> void:
	_history.append(line)
	if _log != null:
		_log.append_text(line + "\n")
		if _log.get_line_count() > MAX_LOG_LINES:
			_log.remove_paragraph(0)

func is_open() -> bool:
	return visible

func toggle() -> void:
	visible = not visible
	if visible and _input != null:
		_input.clear()
		_input.grab_focus()

## The LineEdit consumes keys as text while focused, so the toggle key must be caught at its
## gui_input — otherwise ` types a literal backtick instead of closing the console.
func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_QUOTELEFT or key.physical_keycode == KEY_QUOTELEFT:
			toggle()
			_input.accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.keycode == KEY_QUOTELEFT or key.physical_keycode == KEY_QUOTELEFT:
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and key.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()

func _on_submitted(text: String) -> void:
	_input.clear()
	var line := text.strip_edges()
	if line == "":
		return
	println("> " + line)
	run(line)

## Parse and run one command line. Public so tests (and scripts) can drive the console directly.
func run(line: String) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var cmd_name := String(parts[0]).to_lower()
	var args: Array = []
	for i in range(1, parts.size()):
		args.append(String(parts[i]))
	if not _commands.has(cmd_name):
		var msg := "unknown command '%s' — try help" % cmd_name
		println(msg)
		return msg
	var out = (_commands[cmd_name]["call"] as Callable).call(args)
	var out_line := str(out) if out != null else ""
	if out_line != "":
		println(out_line)
	return out_line

func _cmd_help(_args: Array) -> String:
	var names := _commands.keys()
	names.sort()
	var lines: Array[String] = []
	for n in names:
		var help := str(_commands[n]["help"])
		lines.append("  %s%s" % [n, ("  — " + help) if help != "" else ""])
	return "\n".join(lines)

## True while the console's input field owns the keyboard (host scenes can skip their own keys).
func wants_keyboard() -> bool:
	return visible and _input != null and _input.has_focus()
