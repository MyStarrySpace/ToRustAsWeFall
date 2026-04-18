extends Area3D

## Proximity-based interactable. Stand near it and it activates.
## Supports character-specific dialogue: set dialogue_key and the
## interactable resolves the key with a character suffix automatically.
##
## Example: dialogue_key = "junction.food", active character = "aster"
##   → looks up "junction.food.aster", falls back to "junction.food"
##
## For interactions that need custom logic beyond dialogue, connect
## the interacted signal.

@export var dwell_time := 1.5
@export var interaction_radius := 1.5
@export var description := ""
@export var one_shot := false
@export var tutorial_label := ""

## Dialogue key prefix. On interaction, resolves character-specific variant.
## Leave empty for no automatic dialogue (signal-only interaction).
@export var dialogue_key := ""

## If set, only this character can trigger the interaction.
## Empty = any character.
@export var required_character := ""

var _player_in_range := false
var _dwell_progress := 0.0
var _used := false

var speed_multiplier := 1.0

## Set by the sequence to route dialogue. If null, dialogue_key is ignored.
var dialogue_box: Node = null
## Set by the sequence to identify which character is interacting.
var active_character := ""

var _progress_ring: MeshInstance3D
var _progress_mat: StandardMaterial3D
var _tutorial_label_3d: Label3D
var _collision_shape: CollisionShape3D

signal interacted()
## Emitted with the resolved dialogue key when dialogue_key is set
signal dialogue_triggered(key: String, character: String)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_collision_shape = get_node_or_null("CollisionShape3D")
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = interaction_radius

	_progress_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.75
	torus.rings = 24
	torus.ring_segments = 12
	_progress_ring.mesh = torus
	_progress_mat = StandardMaterial3D.new()
	_progress_mat.albedo_color = Color(0.4, 0.7, 0.5, 0.0)
	_progress_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_progress_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_progress_ring.material_override = _progress_mat
	_progress_ring.position = Vector3(0, 0.05, 0)
	_progress_ring.rotation.x = -PI / 2.0
	add_child(_progress_ring)

	_tutorial_label_3d = Label3D.new()
	_tutorial_label_3d.text = tutorial_label if tutorial_label != "" else "Click"
	_tutorial_label_3d.font_size = 48
	_tutorial_label_3d.pixel_size = 0.012
	_tutorial_label_3d.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_tutorial_label_3d.outline_modulate = Color(0, 0, 0, 0.5)
	_tutorial_label_3d.outline_size = 8
	_tutorial_label_3d.position = Vector3(0, 2.2, 0)
	_tutorial_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tutorial_label_3d.visible = false
	add_child(_tutorial_label_3d)

func _process(delta: float) -> void:
	if _used:
		return

	if _tutorial_label_3d and _tutorial_label_3d.visible and _tutorial_label_3d.modulate.a > 0.1:
		var pulse := 0.6 + sin(Time.get_ticks_msec() * 0.003) * 0.25  # @rendering_only — tutorial label pulse
		_tutorial_label_3d.modulate.a = pulse

	if _player_in_range:
		_dwell_progress += delta * speed_multiplier
		var t := clampf(_dwell_progress / dwell_time, 0.0, 1.0)
		_progress_mat.albedo_color.a = t * 0.6
		_progress_ring.scale = Vector3.ONE * (0.8 + t * 0.4)

		if _dwell_progress >= dwell_time:
			_trigger()
	else:
		if _dwell_progress > 0:
			_dwell_progress = maxf(0, _dwell_progress - delta * 2.0)
			var t := clampf(_dwell_progress / dwell_time, 0.0, 1.0)
			_progress_mat.albedo_color.a = t * 0.3

func _trigger() -> void:
	# Character gate
	if required_character != "" and active_character != "" and active_character != required_character:
		return

	if one_shot:
		_used = true
	_dwell_progress = 0.0
	_progress_mat.albedo_color.a = 0.0
	if _tutorial_label_3d:
		_tutorial_label_3d.modulate.a = 0.0

	# Resolve dialogue
	if dialogue_key != "":
		var resolved := _resolve_dialogue_key()
		if dialogue_box and resolved != "":
			DialogueData.say_to(dialogue_box, resolved)
		dialogue_triggered.emit(resolved, active_character)

	interacted.emit()

func _resolve_dialogue_key() -> String:
	if dialogue_key == "":
		return ""
	if active_character != "":
		var char_key := dialogue_key + "." + active_character
		var line := DialogueData.get_line(char_key)
		if not line.text.begins_with("[MISSING:"):
			return char_key
	var line := DialogueData.get_line(dialogue_key)
	if not line.text.begins_with("[MISSING:"):
		return dialogue_key
	return ""

func show_tutorial_label() -> void:
	if _tutorial_label_3d:
		_tutorial_label_3d.visible = true
		_tutorial_label_3d.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_tutorial_label_3d, "modulate:a", 0.9, 0.5)

func hide_tutorial_label() -> void:
	if _tutorial_label_3d:
		var tween := create_tween()
		tween.tween_property(_tutorial_label_3d, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): _tutorial_label_3d.visible = false)

func _on_body_entered(body: Node3D) -> void:
	if _used:
		return
	if body is CharacterBody3D:
		_player_in_range = true
		_dwell_progress = 0.0

func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_in_range = false

func reset() -> void:
	_used = false
	_player_in_range = false
	_dwell_progress = 0.0
	_progress_mat.albedo_color.a = 0.0

func get_dwell_progress() -> float:
	return _dwell_progress / dwell_time if dwell_time > 0 else 0.0

func is_player_in_range() -> bool:
	return _player_in_range
