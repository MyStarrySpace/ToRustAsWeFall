class_name LazySequenceUI
extends Node

## Lightweight input owner for expensive, normally-hidden sequence UI. The
## loader itself is scene-authored under TutorialUI; Engram and pause/settings
## are instantiated only when an action actually asks for them.

const ENGRAM_OVERLAY_SCENE := preload("res://scenes/ui/engram_overlay.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")

var _host: Node
var _engram_overlay: Node
var _pause_menu: Node


func setup(host: Node) -> void:
	_host = host


func ensure_engram_overlay() -> Node:
	if is_instance_valid(_engram_overlay):
		return _engram_overlay
	if not is_instance_valid(_host):
		return null
	_engram_overlay = ENGRAM_OVERLAY_SCENE.instantiate()
	_host.add_child(_engram_overlay)
	# This loader owns the shortcut so the just-created overlay cannot consume
	# the same event a second time.
	_engram_overlay.set_process_unhandled_key_input(false)
	_host.set("_engram_overlay", _engram_overlay)
	return _engram_overlay


func ensure_pause_menu() -> Node:
	if is_instance_valid(_pause_menu):
		return _pause_menu
	if not is_instance_valid(_host):
		return null
	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	_pause_menu.name = "PauseMenu"
	_host.add_child(_pause_menu)
	_pause_menu.set_process_unhandled_input(false)
	_host.set("_pause_menu", _pause_menu)
	return _pause_menu


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_ESCAPE and is_instance_valid(_engram_overlay) \
			and _engram_overlay.visible:
		_engram_overlay.close_overlay()
		_mark_input_handled()
	elif event.is_action_pressed("engram_toggle"):
		var overlay := ensure_engram_overlay()
		if overlay != null:
			if overlay.visible:
				overlay.close_overlay()
			else:
				overlay.open_overlay()
		_mark_input_handled()
	elif event.is_action_pressed("engram_capture"):
		var overlay := ensure_engram_overlay()
		if overlay != null and not overlay.visible:
			overlay.call("_capture_now")
		_mark_input_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var pause_menu := ensure_pause_menu()
	if pause_menu != null:
		pause_menu.toggle()
	_mark_input_handled()


func _mark_input_handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()
