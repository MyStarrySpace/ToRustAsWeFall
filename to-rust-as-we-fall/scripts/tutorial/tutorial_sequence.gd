@tool
class_name TutorialSequence
extends Node3D

## Base class for all tutorial sequences. Handles scheduler, GameState,
## UI setup, speed control, camera, and common helpers. Subclasses override
## virtual methods to build their scene-specific content.

# Core infrastructure
var _scheduler: EventScheduler
var _game_state: GameState
var _current_step := ""
var _fade_start_tick := 0.0

# UI references (populated by _init_ui)
var _dialogue       # CanvasLayer + dialogue_box.gd
var _tutorial_prompt # CanvasLayer + tutorial_prompt.gd
var _fade_rect: ColorRect
var _thought_label: Label

# Player and camera (populated by subclass via helpers)
var _player         # CharacterBody3D + player.gd
var _camera         # Camera3D + game_camera.gd

# Dialogue chain state (used by _dialogue_chain helper)
var _dlg_chain_keys: Array = []
var _dlg_chain_index := 0
var _dlg_chain_next: Callable
var _dlg_chain_delay := 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		for child in get_children().duplicate():
			child.free()
	_build_scene()
	_build_characters()
	if Engine.is_editor_hint():
		return
	_scheduler = EventScheduler.new()
	_game_state = GameState.new()
	_game_state.scheduler = _scheduler
	_register_characters()
	_init_ui()
	_begin()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var spd := _compute_speed()
	_scheduler.set_speed(spd)
	if _dialogue:
		_dialogue.speed_multiplier = spd
	for node in _get_speed_recipients():
		node.speed_multiplier = spd
	_scheduler.advance(delta)
	_on_process(delta, spd)

# --- Virtual methods (override in subclasses) ---

func _build_scene() -> void:
	pass

func _build_characters() -> void:
	pass

func _register_characters() -> void:
	pass

func _setup_ui() -> void:
	pass

func _begin() -> void:
	pass

func _on_process(_delta: float, _spd: float) -> void:
	pass

func _compute_speed() -> float:
	return 10.0 if Input.is_key_pressed(KEY_F) else 1.0

func _get_speed_recipients() -> Array:
	return []

# --- UI setup ---

func _init_ui() -> void:
	var ui := preload("res://scenes/game/tutorial_ui.tscn").instantiate()
	add_child(ui)
	_dialogue = ui.get_node("DialogueBox")
	_tutorial_prompt = ui.get_node("TutorialPrompt")
	_fade_rect = ui.get_node("FadeOverlay/FadeRect")
	_thought_label = ui.get_node("ThoughtOverlay/ThoughtLabel")
	_fade_rect.color.a = 0.0
	_setup_ui()

# --- Character helpers ---

func _create_player_character(char_name: String, char_color: Color) -> CharacterBody3D:
	var p := preload("res://scenes/game/player_character.tscn").instantiate()
	p.name = char_name
	p.color = char_color
	p.get_node("Label3D").text = char_name.to_upper()
	p.get_node("Label3D").modulate = Color(char_color, 0.8)
	return p

func _create_npc(npc_name: String, npc_color: Color) -> Node3D:
	var npc := Node3D.new()
	npc.name = npc_name.replace("-", "_")
	npc.set_script(preload("res://scripts/game/npc.gd"))
	npc.display_name = npc_name
	npc.color = npc_color
	return npc

func _setup_game_camera(target_node: Node3D, offset := Vector3(0, 10, 7)) -> void:
	var cam := Camera3D.new()
	cam.name = "GameCamera"
	cam.set_script(preload("res://scripts/game/game_camera.gd"))
	add_child(cam)
	_camera = cam
	_camera.target = target_node
	_camera.follow_offset = offset
	_camera.set_pan_enabled(false)

func _register_gs_character(id: String, node: Node3D, speed: float = 3.0, stats: Dictionary = {}) -> void:
	_game_state.register_character(id, node.position, speed, stats)
	node.game_state = _game_state
	node.char_id = id

# --- Fade helpers ---

func _fade_from(color: Color, duration: float, next_func: Callable, next_tag: String) -> void:
	_fade_rect.color = color
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(duration, next_func, next_tag)

func _update_fade_in(duration: float = 2.0) -> void:
	var elapsed := _scheduler.get_current_tick() - _fade_start_tick
	_fade_rect.color.a = 1.0 - clampf(elapsed / duration, 0.0, 1.0)

func _update_fade_out(target_color: Color, duration: float = 2.0) -> void:
	var elapsed := _scheduler.get_current_tick() - _fade_start_tick
	var alpha := clampf(elapsed / duration, 0.0, 1.0)
	_fade_rect.color = Color(target_color.r, target_color.g, target_color.b, alpha)

# --- Thought helpers ---

func _show_thought(text: String) -> void:
	_thought_label.text = text
	var tween := create_tween()
	tween.tween_property(_thought_label, "modulate:a", 0.7, 0.5)

func _hide_thought() -> void:
	var tween := create_tween()
	tween.tween_property(_thought_label, "modulate:a", 0.0, 0.5)

# --- Step transition ---

## Transition to a new step. Clears stale dialogue callbacks to prevent
## double-fire from overlapping signal subscriptions. Returns false if
## already in the requested step (duplicate call).
func _enter_step(step_name: String) -> bool:
	if _current_step == step_name:
		return false
	_current_step = step_name
	# Disconnect any stale dialogue_finished callbacks from the previous step
	if _dialogue:
		for conn in _dialogue.dialogue_finished.get_connections():
			_dialogue.dialogue_finished.disconnect(conn.callable)
	return true

# --- Dialogue chain ---

## Play a sequence of dialogue keys in order, with optional delay between
## each line. Calls next_func when the entire chain completes.
func _dialogue_chain(keys: Array, next_func: Callable, delay_between := 0.0) -> void:
	_dlg_chain_keys = keys
	_dlg_chain_index = 0
	_dlg_chain_next = next_func
	_dlg_chain_delay = delay_between
	_dlg_chain_play_next()

func _dlg_chain_play_next() -> void:
	if _dlg_chain_index >= _dlg_chain_keys.size():
		_dlg_chain_next.call()
		return
	var key: String = _dlg_chain_keys[_dlg_chain_index]
	_dlg_chain_index += 1
	DialogueData.say_to(_dialogue, key)
	if _dlg_chain_delay > 0.0 and _dlg_chain_index < _dlg_chain_keys.size():
		_dialogue.dialogue_finished.connect(func():
			_scheduler.schedule_after(_dlg_chain_delay, _dlg_chain_play_next, "dlg_chain")
		, CONNECT_ONE_SHOT)
	else:
		_dialogue.dialogue_finished.connect(_dlg_chain_play_next, CONNECT_ONE_SHOT)

# --- Environment helpers ---

func _add_wall(parent: Node3D, pos: Vector3, size: Vector3, color := Color(0.12, 0.12, 0.15)) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
