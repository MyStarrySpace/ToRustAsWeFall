class_name SceneChunk
extends Node3D

const INTERACTABLE_SCENE := preload("res://scenes/game/interactable.tscn")

var host: Node = null
var chunk_name := ""
var _built := false
var _interactables: Array = []

func attach_chunk_host(next_host: Node, next_chunk_name := "") -> void:
	host = next_host
	if next_chunk_name != "":
		chunk_name = next_chunk_name

func detach_chunk_host() -> void:
	host = null
	_interactables.clear()

func _ready() -> void:
	if _built:
		return
	_built = true
	_build_chunk()

func _build_chunk() -> void:
	pass

func get_scene_title() -> String:
	if chunk_name != "":
		return chunk_name.capitalize()
	return name

func get_scene_help() -> String:
	return ""

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return {}

func get_preview_anchors() -> Dictionary:
	return get_spawn_positions()

func get_preview_character_state() -> Dictionary:
	return {}

func get_preview_time_state() -> Dictionary:
	return {}

func get_preview_abilities() -> Array:
	return []

func get_preview_state() -> Dictionary:
	return {}

func update_preview_overlay_states(_overlay_states: Dictionary, _current_tick: float, _delta: float) -> void:
	pass

func get_preview_overlay_status(_overlay_id: String, _current_tick: float) -> Array:
	return []

func reset_preview_state() -> void:
	pass

func headless_process(_delta: float) -> void:
	pass

func handle_preview_ability(_ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	return {}

func on_preview_character_selected(_char_id: String) -> void:
	pass

func on_preview_routing_changed(_mode: String) -> void:
	pass

func _dialogue_box() -> Node:
	if host != null and host.has_method("get_preview_dialogue_box"):
		return host.call("get_preview_dialogue_box")
	return null

func _engram_overlay() -> Node:
	if host != null and host.has_method("get_preview_engram_overlay"):
		return host.call("get_preview_engram_overlay")
	return null

func _show_note(text: String, duration := 3.0) -> void:
	if host != null and host.has_method("show_preview_note"):
		host.call("show_preview_note", text, duration)

func _show_message(text: String, duration := 2.0) -> void:
	if host != null and host.has_method("show_preview_message"):
		host.call("show_preview_message", text, duration)

func _set_preview_step(step: String) -> void:
	if host != null and host.has_method("set_preview_step"):
		host.call("set_preview_step", step)

func _get_character_position(char_id: String) -> Vector3:
	if host != null and host.has_method("get_preview_character_position"):
		return host.call("get_preview_character_position", char_id)
	return Vector3.ZERO

func _get_character_move_speed(char_id: String, running := false) -> float:
	if host != null and host.has_method("get_preview_character_move_speed"):
		return float(host.call("get_preview_character_move_speed", char_id, running))
	return 3.0

func _set_character_position(char_id: String, position: Vector3) -> void:
	if host != null and host.has_method("set_preview_character_position"):
		host.call("set_preview_character_position", char_id, position)

func _get_active_character() -> String:
	if host != null and host.has_method("get_preview_active_character"):
		return str(host.call("get_preview_active_character"))
	return ""

func _get_character_stat(char_id: String, stat_name: String) -> float:
	if host != null and host.has_method("get_preview_character_stat"):
		return float(host.call("get_preview_character_stat", char_id, stat_name))
	return 0.0

func _set_character_stat(char_id: String, stat_name: String, value: float) -> void:
	if host != null and host.has_method("set_preview_character_stat"):
		host.call("set_preview_character_stat", char_id, stat_name, value)

func _adjust_character_stat(char_id: String, stat_name: String, delta: float) -> void:
	if host != null and host.has_method("adjust_preview_character_stat"):
		host.call("adjust_preview_character_stat", char_id, stat_name, delta)

func _set_character_status(char_id: String, status: String) -> void:
	if host != null and host.has_method("set_preview_character_status"):
		host.call("set_preview_character_status", char_id, status)

func _set_character_visible(char_id: String, visible: bool) -> void:
	if host != null and host.has_method("set_preview_character_visible"):
		host.call("set_preview_character_visible", char_id, visible)

func _set_ability_state(ability_id: String, state: String, remaining := 0.0) -> void:
	if host != null and host.has_method("set_preview_ability_state"):
		host.call("set_preview_ability_state", ability_id, state, remaining)

func _get_routing_mode() -> String:
	if host != null and host.has_method("get_preview_routing_mode"):
		return str(host.call("get_preview_routing_mode"))
	return "safe"

func _spawn_item(item_type: String, position: Vector3, properties: Dictionary = {}) -> String:
	if host != null and host.has_method("spawn_preview_item"):
		return str(host.call("spawn_preview_item", item_type, position, properties))
	return ""

func _remove_item(item_id: String) -> void:
	if host != null and host.has_method("remove_preview_item"):
		host.call("remove_preview_item", item_id)

func _pick_up_item(char_id: String, item_id: String) -> bool:
	if host != null and host.has_method("pick_up_preview_item"):
		return bool(host.call("pick_up_preview_item", char_id, item_id))
	return false

func _drop_item(char_id: String, item_id: String) -> bool:
	if host != null and host.has_method("drop_preview_item"):
		return bool(host.call("drop_preview_item", char_id, item_id))
	return false

func _transfer_item(from_id: String, to_id: String, item_id: String) -> bool:
	if host != null and host.has_method("transfer_preview_item"):
		return bool(host.call("transfer_preview_item", from_id, to_id, item_id))
	return false

func _endocytose_item(char_id: String, item_id: String) -> bool:
	if host != null and host.has_method("endocytose_preview_item"):
		return bool(host.call("endocytose_preview_item", char_id, item_id))
	return false

func _exocytose_item(char_id: String, item_id: String) -> bool:
	if host != null and host.has_method("exocytose_preview_item"):
		return bool(host.call("exocytose_preview_item", char_id, item_id))
	return false

func _get_hand_items(char_id: String) -> Array:
	if host != null and host.has_method("get_preview_hand_items"):
		return host.call("get_preview_hand_items", char_id)
	return []

func _get_hand_slots(char_id: String) -> Array:
	if host != null and host.has_method("get_preview_hand_slots"):
		return host.call("get_preview_hand_slots", char_id)
	return []

func _get_internal_items(char_id: String) -> Array:
	if host != null and host.has_method("get_preview_internal_items"):
		return host.call("get_preview_internal_items", char_id)
	return []

func _get_item_state(item_id: String) -> Dictionary:
	if host != null and host.has_method("get_preview_item_state"):
		var state: Variant = host.call("get_preview_item_state", item_id)
		return state if state is Dictionary else {}
	return {}

func _get_item_display_name(item_id: String, char_id := "") -> String:
	if host != null and host.has_method("get_preview_item_display_name"):
		return str(host.call("get_preview_item_display_name", item_id, char_id))
	return item_id

func _get_collection_items() -> Array:
	if host != null and host.has_method("get_preview_collection_items"):
		return host.call("get_preview_collection_items")
	return []

func _get_scheduler_tick() -> float:
	if host != null and host.has_method("get_preview_scheduler_tick"):
		return float(host.call("get_preview_scheduler_tick"))
	return 0.0

func _clear_dialogue() -> void:
	var dialogue_box: Node = _dialogue_box()
	if dialogue_box != null and dialogue_box.has_method("clear"):
		dialogue_box.call("clear")

func _say(text: String, speaker := "", style := "normal", wait := false) -> void:
	var dialogue_box: Node = _dialogue_box()
	if dialogue_box != null and dialogue_box.has_method("say"):
		dialogue_box.call("say", text, speaker, style, wait)

func _say_key(key: String) -> void:
	var dialogue_box: Node = _dialogue_box()
	if dialogue_box == null or not dialogue_box.has_method("say") or key == "":
		return
	var line := DialogueData.get_line(key)
	dialogue_box.call("say", line.text, line.speaker, line.style, line.wait)

func _register_interactable(interactable: Node) -> void:
	_interactables.append(interactable)
	if host != null and host.has_method("register_preview_interactable"):
		host.call("register_preview_interactable", interactable)

func _make_material(
	color: Color,
	emission := Color.BLACK,
	emission_energy := 0.0,
	transparency := BaseMaterial3D.TRANSPARENCY_DISABLED
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = transparency
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material

func _add_box(
	parent: Node3D,
	position: Vector3,
	size: Vector3,
	color: Color,
	emission := Color.BLACK,
	emission_energy := 0.0,
	name := ""
) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	if name != "":
		mesh.name = name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _make_material(color, emission, emission_energy)
	mesh.position = position
	parent.add_child(mesh)
	return mesh

func _add_floor(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var floor := _add_box(parent, position, size, color)
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return floor

func _add_light(
	parent: Node3D,
	position: Vector3,
	color: Color,
	energy: float,
	range_value: float
) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	parent.add_child(light)
	return light

func _add_label(
	parent: Node3D,
	text: String,
	position: Vector3,
	color := Color(0.82, 0.86, 0.92)
) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.pixel_size = 0.01
	label.font_size = 52
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.55)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

func _add_interactable(
	parent: Node3D,
	node_name: String,
	description: String,
	position: Vector3,
	tutorial_label: String,
	required_character := "",
	dwell_time := 1.0,
	one_shot := false,
	interaction_radius := 1.5
) -> Area3D:
	var interactable := INTERACTABLE_SCENE.instantiate()
	interactable.name = node_name
	interactable.description = description
	interactable.position = position
	interactable.tutorial_label = tutorial_label
	interactable.required_character = required_character
	interactable.dwell_time = dwell_time
	interactable.one_shot = one_shot
	interactable.interaction_radius = interaction_radius
	parent.add_child(interactable)
	_register_interactable(interactable)
	if interactable.has_method("show_tutorial_label"):
		interactable.call("show_tutorial_label")
	return interactable
