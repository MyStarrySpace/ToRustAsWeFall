class_name InfrastructureOperation
extends Node3D

## Reusable two-stage infrastructure beat:
##   source verb -> typed service reaches receiver -> receiver verb -> environmental field changes.
## The nodes supplied by a chunk remain normal Interactables and CausalFeedbackLinks, so cursor copy,
## movement authority, outlines, replay data, and planning-pause feedback all stay on shared systems.

signal service_routed(operation: InfrastructureOperation)
signal operation_completed(operation: InfrastructureOperation)

var operation_id := "infrastructure_operation"
var commodity := "service"
var source_action := "ROUTE SERVICE"
var receiver_action := "COMMISSION RECEIVER"
var source_control: Node
var receiver_control: Node
var service_field: Node3D
var source_status: Label3D
var receiver_status: Label3D
var source_link: Node3D
var consequence_link: Node3D
var _routed := false
var _completed := false


func configure(spec: Dictionary) -> void:
	operation_id = str(spec.get("operation_id", operation_id))
	commodity = str(spec.get("commodity", commodity))
	source_action = str(spec.get("source_action", source_action))
	receiver_action = str(spec.get("receiver_action", receiver_action))


func bind_runtime(
		source: Node,
		receiver: Node,
		field: Node3D,
		source_label: Label3D = null,
		receiver_label: Label3D = null,
		service_link: Node3D = null,
		effect_link: Node3D = null
	) -> void:
	source_control = source
	receiver_control = receiver
	service_field = field
	source_status = source_label
	receiver_status = receiver_label
	source_link = service_link
	consequence_link = effect_link
	if source_control != null and source_control.has_signal("interacted"):
		source_control.interacted.connect(route_service)
	if receiver_control != null and receiver_control.has_signal("interacted"):
		receiver_control.interacted.connect(complete_operation)
	_apply_state()


func route_service() -> bool:
	if _routed:
		return false
	_routed = true
	_apply_state()
	_set_link_state(source_link, "complete", true)
	_set_link_state(consequence_link, "ready", false)
	service_routed.emit(self)
	return true


func complete_operation() -> bool:
	if not _routed or _completed:
		return false
	_completed = true
	if service_field != null:
		service_field.resolve_field()
	_apply_state()
	_set_link_state(consequence_link, "complete", true)
	operation_completed.emit(self)
	return true


func reset_operation() -> void:
	_routed = false
	_completed = false
	if source_control != null and source_control.has_method("reset"):
		source_control.call("reset")
	if receiver_control != null and receiver_control.has_method("reset"):
		receiver_control.call("reset")
	if service_field != null:
		service_field.reset_field()
	_set_link_state(source_link, "predicted", false)
	_set_link_state(consequence_link, "predicted", false)
	_apply_state()


func get_state() -> Dictionary:
	return {
		"operation_id": operation_id,
		"commodity": commodity,
		"routed": _routed,
		"completed": _completed,
		"receiver_enabled": receiver_control != null \
			and receiver_control.has_method("is_interaction_enabled") \
			and bool(receiver_control.call("is_interaction_enabled")),
		"field": service_field.get_state() if service_field != null else {},
	}


func _apply_state() -> void:
	if receiver_control != null and receiver_control.has_method("set_interaction_enabled"):
		receiver_control.call("set_interaction_enabled", _routed and not _completed)
	if source_status != null:
		source_status.text = "1  %s%s" % [source_action, "  DONE" if _routed else ""]
		source_status.modulate = Color(0.36, 0.91, 0.50) if _routed else Color(0.42, 0.72, 0.95)
	if receiver_status != null:
		if _completed:
			receiver_status.text = "2  %s  DONE" % receiver_action
			receiver_status.modulate = Color(0.36, 0.91, 0.50)
		elif _routed:
			receiver_status.text = "2  %s" % receiver_action
			receiver_status.modulate = Color(0.95, 0.64, 0.32)
		else:
			receiver_status.text = "2  WAITING: %s" % commodity.replace("_", " ").to_upper()
			receiver_status.modulate = Color(0.62, 0.65, 0.70)
	_set_link_latched(source_link, not _routed)
	_set_link_latched(consequence_link, _routed and not _completed)


func _set_link_latched(link: Node3D, active: bool) -> void:
	if link != null and is_instance_valid(link) and link.has_method("set_latched"):
		link.call("set_latched", active)


func _set_link_state(link: Node3D, mode: String, flash_link: bool) -> void:
	if link == null or not is_instance_valid(link):
		return
	if link.has_method("set_feedback_mode"):
		link.call("set_feedback_mode", mode)
	if flash_link and link.has_method("flash"):
		link.call("flash", 1.35, 1.2)
