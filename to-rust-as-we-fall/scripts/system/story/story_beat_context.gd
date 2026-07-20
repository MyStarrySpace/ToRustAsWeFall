class_name StoryBeatContext
extends RefCounted

## Typed dependency boundary shared by story beats.
##
## Core simulation services are explicit fields. Optional presentation or
## scene-specific capabilities live in `services`, where beats can validate names
## before entering instead of reaching through a large scene controller.

var host: Node
var game_state: GameState
var scheduler: EventScheduler
var ui_scheduler: EventScheduler
var services: Dictionary = {}


func _init(
		beat_host: Node = null,
		beat_game_state: GameState = null,
		beat_scheduler: EventScheduler = null,
		beat_ui_scheduler: EventScheduler = null,
		beat_services: Dictionary = {}
	) -> void:
	host = beat_host
	game_state = beat_game_state
	scheduler = beat_scheduler
	ui_scheduler = beat_ui_scheduler
	services = beat_services.duplicate()


func service(service_id: StringName, fallback: Variant = null) -> Variant:
	return services.get(service_id, fallback)


func has_service(service_id: StringName) -> bool:
	return services.has(service_id) and services[service_id] != null


func missing_services(required_service_ids: Array) -> PackedStringArray:
	var missing := PackedStringArray()
	for service_id_variant in required_service_ids:
		var service_id := StringName(str(service_id_variant))
		if not has_service(service_id):
			missing.append(str(service_id))
	return missing
