extends Area3D

## Proximity-based interactable. No key press — stand near it and it activates.
## Like cells: interaction happens through proximity, not buttons.
## Shows a channel progress indicator while dwelling, triggers on completion.

@export var dwell_time := 1.5  ## Seconds the player must stay nearby
@export var description := ""
@export var one_shot := false
@export var tutorial_label := ""  ## If set, shows a "click" (or other) label above the object

var _player_in_range := false
var _dwell_progress := 0.0
var _used := false

## External speed multiplier (set by sequence for fast-forward). Default 1.0.
var speed_multiplier := 1.0

var _progress_ring: MeshInstance3D
var _progress_mat: StandardMaterial3D
var _tutorial_label_3d: Label3D

signal interacted()

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Visual: a ring on the ground that fills as dwell progresses
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

	# Tutorial label — floating text above the interactable (e.g. "Click")
	# White, starts hidden, only shown when show_tutorial_label() is called
	_tutorial_label_3d = Label3D.new()
	_tutorial_label_3d.text = tutorial_label if tutorial_label != "" else "Click"
	_tutorial_label_3d.font_size = 48
	_tutorial_label_3d.pixel_size = 0.012
	_tutorial_label_3d.modulate = Color(1.0, 1.0, 1.0, 0.0)  # White, starts invisible
	_tutorial_label_3d.outline_modulate = Color(0, 0, 0, 0.5)
	_tutorial_label_3d.outline_size = 8
	_tutorial_label_3d.position = Vector3(0, 2.2, 0)
	_tutorial_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tutorial_label_3d.visible = false  # Completely hidden until needed
	add_child(_tutorial_label_3d)

func _process(delta: float) -> void:
	if _used:
		return

	# Tutorial label pulses gently when visible
	if _tutorial_label_3d and _tutorial_label_3d.visible and _tutorial_label_3d.modulate.a > 0.1:
		var pulse := 0.6 + sin(Time.get_ticks_msec() * 0.003) * 0.25
		_tutorial_label_3d.modulate.a = pulse

	if _player_in_range:
		_dwell_progress += delta * speed_multiplier
		# Visual feedback — ring fades in and pulses as it fills
		var t := clampf(_dwell_progress / dwell_time, 0.0, 1.0)
		_progress_mat.albedo_color.a = t * 0.6
		_progress_ring.scale = Vector3.ONE * (0.8 + t * 0.4)

		if _dwell_progress >= dwell_time:
			_trigger()
	else:
		# Fade out when player leaves
		if _dwell_progress > 0:
			_dwell_progress = maxf(0, _dwell_progress - delta * 2.0)
			var t := clampf(_dwell_progress / dwell_time, 0.0, 1.0)
			_progress_mat.albedo_color.a = t * 0.3

func _trigger() -> void:
	if one_shot:
		_used = true
	_dwell_progress = 0.0
	_progress_mat.albedo_color.a = 0.0
	# Hide tutorial label on interaction
	if _tutorial_label_3d:
		_tutorial_label_3d.modulate.a = 0.0
	interacted.emit()

## Show the tutorial label (call from sequence script when it's time)
func show_tutorial_label() -> void:
	if _tutorial_label_3d:
		_tutorial_label_3d.visible = true
		_tutorial_label_3d.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_tutorial_label_3d, "modulate:a", 0.9, 0.5)

## Hide the tutorial label
func hide_tutorial_label() -> void:
	if _tutorial_label_3d:
		var tween := create_tween()
		tween.tween_property(_tutorial_label_3d, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): _tutorial_label_3d.visible = false)

func _on_body_entered(body: Node3D) -> void:
	# Accept any player character (Aster, Peris, etc.)
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

## For headless testing: check if interaction would trigger at current dwell
func get_dwell_progress() -> float:
	return _dwell_progress / dwell_time if dwell_time > 0 else 0.0

func is_player_in_range() -> bool:
	return _player_in_range
