class_name OutlineFeedbackManager
extends Node

## Owns hover and selected feedback for outline-capable targets.

var hovered_target: Node = null
var selected_target: Node = null

var _bound_targets := {}
var _bound_controllers := {}
var _selection_token := 0

func bind_target(target: Node) -> void:
	if target == null:
		return
	var has_feedback_signal := target.has_signal("outline_hovered") or target.has_signal("outline_selected")
	if not has_feedback_signal:
		return
	var target_id := target.get_instance_id()
	if _bound_targets.has(target_id):
		return
	_bound_targets[target_id] = target
	if target.has_method("set_feedback_managed"):
		target.call("set_feedback_managed", true)
	if target.has_signal("outline_hovered") and not target.is_connected("outline_hovered", _on_target_hovered):
		target.connect("outline_hovered", _on_target_hovered)
	if target.has_signal("outline_unhovered") and not target.is_connected("outline_unhovered", _on_target_unhovered):
		target.connect("outline_unhovered", _on_target_unhovered)
	if target.has_signal("outline_selected") and not target.is_connected("outline_selected", _on_target_selected):
		target.connect("outline_selected", _on_target_selected)

func bind_interaction_controller(controller: Node) -> void:
	if controller == null:
		return
	if not controller.has_signal("target_reached") and not controller.has_signal("target_cancelled"):
		return
	var controller_id := controller.get_instance_id()
	if _bound_controllers.has(controller_id):
		return
	_bound_controllers[controller_id] = controller
	if controller.has_signal("target_reached") and not controller.is_connected("target_reached", _on_controller_target_reached):
		controller.connect("target_reached", _on_controller_target_reached)
	if controller.has_signal("target_cancelled") and not controller.is_connected("target_cancelled", _on_controller_target_cancelled):
		controller.connect("target_cancelled", _on_controller_target_cancelled)

func get_hovered_target() -> Node:
	return hovered_target

func get_selected_target() -> Node:
	return selected_target

func _on_target_hovered(target: Node) -> void:
	if hovered_target == target:
		return
	if hovered_target != null and is_instance_valid(hovered_target):
		_set_hover_feedback(hovered_target, false)
	hovered_target = target
	_set_hover_feedback(target, true)

func _on_target_unhovered(target: Node) -> void:
	if hovered_target != target:
		return
	_set_hover_feedback(target, false)
	hovered_target = null

func _on_target_selected(target: Node) -> void:
	if target == null:
		return
	if selected_target != null and selected_target != target and is_instance_valid(selected_target):
		_cancel_selected(selected_target)
	selected_target = target
	_selection_token += 1
	if target.has_method("begin_queued_feedback"):
		target.call("begin_queued_feedback")
	if not _is_controller_tracking(target):
		var token := _selection_token
		var duration := _read_target_float(target, "selected_feedback_duration", 0.8)
		get_tree().create_timer(maxf(0.05, duration)).timeout.connect(func():
			if token == _selection_token and selected_target == target and not _is_controller_tracking(target):
				_complete_selected(target)
		)

func _on_controller_target_reached(target: Node) -> void:
	if selected_target == target:
		_complete_selected(target)

func _on_controller_target_cancelled(target: Node) -> void:
	if selected_target == target:
		_cancel_selected(target)

func _set_hover_feedback(target: Node, active: bool) -> void:
	if target != null and is_instance_valid(target) and target.has_method("set_hover_feedback"):
		target.call("set_hover_feedback", active)

func _complete_selected(target: Node) -> void:
	if target != null and is_instance_valid(target) and target.has_method("complete_queued_feedback"):
		target.call("complete_queued_feedback")
	if selected_target == target:
		selected_target = null
		_selection_token += 1

func _cancel_selected(target: Node) -> void:
	if target != null and is_instance_valid(target) and target.has_method("cancel_queued_feedback"):
		target.call("cancel_queued_feedback")
	if selected_target == target:
		selected_target = null
		_selection_token += 1

func _is_controller_tracking(target: Node) -> bool:
	for controller in _bound_controllers.values():
		if not is_instance_valid(controller):
			continue
		if controller.get("active_target") == target:
			return true
	return false

func _read_target_float(target: Node, property_name: String, fallback: float) -> float:
	if target == null:
		return fallback
	var value = target.get(property_name)
	if value == null:
		return fallback
	return float(value)
