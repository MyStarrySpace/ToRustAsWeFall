@tool
extends TutorialSequence

## Elevator tutorial → bridge collapse → route choice → Endo's shelter.
## Chunk-based: geometry loads/unloads as the player progresses.
## Peris wakes in a stuck elevator. Aster is unconscious. Escort units on standby.
## Conversation (emotional core). Units activate. EMP (Q). Character switching (Tab).
## Hack the panel. Doors open. Bridge collapses. Route fork. Endo's shelter. Night watch.

# Characters
var _aster_node: CharacterBody3D
var _peris_node: CharacterBody3D
var _escort_1  # NPC
var _escort_2  # NPC
var _active_character := "peris"

# Environment
var _emergency_light: OmniLight3D
var _floor_indicator: Label3D
var _door_panel_a: MeshInstance3D
var _door_panel_b: MeshInstance3D
var _control_panel  # Interactable
var _indicator_timer := 0.0
var _indicator_b_label: Label3D  # The "B" that flickers
var _exit_button  # Interactable — flashes "NO EXIT" when pressed
var _no_exit_label: Label3D

# HUD
var _hud  # GameHUD

# EMP state
var _emp_count := 0
var _emp_queued := false
var _emp_cooldown_end := 0.0  # scheduler tick when cooldown expires
var _unit_1_stunned := false
var _unit_2_stunned := false
var _reboot_active := false
var _stamina := 100.0

# Bridge ecology
var _bridge_chelators: Array[MeshInstance3D] = []

# Chunk system
var _chunks: Dictionary = {}

# Endo (hidden until junction)
var _endo: Node3D

# Night watch
var _monster_eyes: Array[OmniLight3D] = []

# Positions (elevator ~8x8, tall ceiling)
const ELEVATOR_SIZE := Vector3(8.0, 4.0, 8.0)
const PERIS_START := Vector3(-1.0, 0.5, 1.5)
const ASTER_POS := Vector3(2.0, 0, -2.0)
const ESCORT_1_POS := Vector3(-2.5, 0, -2.5)
const ESCORT_2_POS := Vector3(-2.5, 0, 2.5)
const PANEL_POS := Vector3(3.5, 0, 0)

# Below-level (ecology visible from bridge, walkable after collapse)
const BELOW_Y := -4.0
const BRIDGE_START_X := 11.5  # ELEVATOR_SIZE.x/2 + 0.5 + 7.0
const BRIDGE_END_X := 23.5    # BRIDGE_START_X + 12.0

# Route fork (after collapse, two paths diverge)
const FORK_POS := Vector3(BRIDGE_START_X + 4.0, BELOW_Y, 0)
const ENEMY_ROUTE_END := Vector3(BRIDGE_END_X + 8.0, BELOW_Y, -6.0)
const HAZARD_ROUTE_END := Vector3(BRIDGE_END_X + 12.0, BELOW_Y, 6.0)
const ROUTES_CONVERGE := Vector3(BRIDGE_END_X + 16.0, BELOW_Y, 0)

# Endo's junction / shelter
const JUNCTION_POS := Vector3(BRIDGE_END_X + 18.0, BELOW_Y, 0)
const SHELTER_SIZE := Vector3(6, 3, 5)

# --- Chunk management ---

func _load_chunk(chunk_name: String) -> Node3D:
	if _chunks.has(chunk_name):
		return _chunks[chunk_name]
	var chunk := Node3D.new()
	chunk.name = "Chunk_" + chunk_name
	find_child("Environment", false, false).add_child(chunk)
	_chunks[chunk_name] = chunk
	match chunk_name:
		"elevator": _build_elevator_chunk(chunk)
		"bridge": _build_bridge_chunk(chunk)
		"below": _build_below_chunk(chunk)
		"junction": _build_junction_chunk(chunk)
	return chunk

func _unload_chunk(chunk_name: String) -> void:
	if not _chunks.has(chunk_name):
		return
	_chunks[chunk_name].queue_free()
	_chunks.erase(chunk_name)

# --- Virtual overrides ---

func _build_scene() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)
	# Persistent WorldEnvironment (not chunk-specific)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.02, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.15, 0.1)
	e.ambient_light_energy = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.3
	e.glow_bloom = 0.1
	we.environment = e
	env.add_child(we)
	_load_chunk("elevator")

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	# Peris — active player initially
	_player = _create_player_character("Peris", Color(0.8, 0.5, 0.35))
	_player.position = PERIS_START
	chars.add_child(_player)
	_peris_node = _player

	# Aster — player character but disabled and slumped
	_aster_node = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_aster_node.position = ASTER_POS + Vector3(0, 0.5, 0)
	_aster_node.rotation_degrees.z = 30.0
	chars.add_child(_aster_node)

	# Escort units
	_escort_1 = _create_npc("EU-1", Color(0.7, 0.7, 0.75))
	_escort_1.position = ESCORT_1_POS
	chars.add_child(_escort_1)

	_escort_2 = _create_npc("EU-2", Color(0.7, 0.7, 0.75))
	_escort_2.position = ESCORT_2_POS
	chars.add_child(_escort_2)

	# Endo (hidden until junction)
	_endo = _create_npc("Endo", Color(0.4, 0.67, 0.53))
	_endo.position = Vector3(JUNCTION_POS.x + 3, BELOW_Y + 0.5, -2)
	_endo.visible = false
	chars.add_child(_endo)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 3.5, 2.5))

func _register_characters() -> void:
	_register_gs_character("peris", _peris_node, 2.5)
	_register_gs_character("aster", _aster_node, 2.5)
	_aster_node.set_move_enabled(false)

func _setup_ui() -> void:
	# Game HUD with character portraits
	_hud = CanvasLayer.new()
	_hud.name = "GameHUD"
	_hud.set_script(preload("res://scripts/game/game_hud.gd"))
	add_child(_hud)
	_hud.add_portrait("peris", "Peris", Color(1.0, 0.67, 0.27))
	_hud.add_portrait("aster", "Aster", Color(0.29, 0.62, 1.0))
	_hud.set_portrait_status("aster", "downed")
	_hud.set_portrait_stat("aster", "sta", 0)
	_hud.show_pause_toggle(false)
	_hud.pause_toggled.connect(_on_pause_toggled)
	_hud.add_ability("emp", "EMP", "Q", Color(0.29, 0.62, 1.0))
	_hud.set_ability_state("emp", "disabled")
	_hud.character_selection_changed.connect(_on_character_selected)

	# Control panel interactable (hacking target)
	_control_panel = preload("res://scenes/game/interactable.tscn").instantiate()
	_control_panel.name = "ControlPanel"
	_control_panel.description = "Control Panel"
	_control_panel.one_shot = true
	_control_panel.dwell_time = 3.0
	_control_panel.position = Vector3(ELEVATOR_SIZE.x / 2.0 - 0.3, 1.0, 0)
	add_child(_control_panel)
	_control_panel.interacted.connect(_on_panel_hacked)
	# Hide the interactable until hack step
	_control_panel.visible = false

	# Exit button near the doors — Peris can try it during waking
	_exit_button = preload("res://scenes/game/interactable.tscn").instantiate()
	_exit_button.name = "ExitButton"
	_exit_button.description = "Door Button"
	_exit_button.one_shot = false
	_exit_button.dwell_time = 0.5
	_exit_button.tutorial_label = "OPEN"
	_exit_button.position = Vector3(ELEVATOR_SIZE.x / 2.0 - 0.3, 1.0, 1.5)
	add_child(_exit_button)
	_exit_button.interacted.connect(_on_exit_button_pressed)

func _begin() -> void:
	_player.set_move_enabled(false)
	_fade_rect.color = Color(0, 0, 0, 1)
	_scheduler.schedule_after(1.0, _start_consciousness_fragments, "fragments")

func _compute_speed() -> float:
	return 10.0 if Input.is_key_pressed(KEY_F) else 1.0

func _on_process(delta: float, spd: float) -> void:
	# Emergency light pulse (elevator chunk)
	if _emergency_light and is_instance_valid(_emergency_light):
		_emergency_light.light_energy = 1.5 + sin(Time.get_ticks_msec() * 0.003) * 0.5

	# Floor indicator: "3" is steady, "B" flickers (elevator chunk)
	if _indicator_b_label and is_instance_valid(_indicator_b_label):
		_indicator_timer += delta * spd
		if _indicator_timer > 0.3:
			_indicator_timer = 0.0
			_indicator_b_label.visible = not _indicator_b_label.visible

	# Escort unit flicker when stunned (toggle visibility)
	if _unit_1_stunned and _escort_1:
		_escort_1.visible = int(Time.get_ticks_msec() / 100) % 2 == 0
	if _unit_2_stunned and _escort_2:
		_escort_2.visible = int(Time.get_ticks_msec() / 100) % 2 == 0

	# Update EMP cooldown display from scheduler ticks
	if _emp_cooldown_end > 0:
		var remaining := maxf(0, _emp_cooldown_end - _scheduler.get_current_tick())
		_hud.set_ability_state("emp", "cooldown", remaining)
		if remaining <= 0:
			_emp_cooldown_end = 0.0
			_hud.set_ability_state("emp", "ready")

	# Chelators drift along walls below the bridge
	for i in range(_bridge_chelators.size()):
		var c: MeshInstance3D = _bridge_chelators[i]
		c.position.x += delta * spd * 0.3
		c.rotation.y += delta * spd * 0.8
		# Loop back when past the bridge
		var bridge_end := ELEVATOR_SIZE.x / 2.0 + 0.5 + 7.0 + 12.0
		if c.position.x > bridge_end:
			c.position.x -= 11.0

	# Approach gate
	if _current_step == "approach_aster":
		var peris_pos := _game_state.get_position("peris")
		if peris_pos.distance_to(ASTER_POS) < 1.8:
			_tutorial_prompt.hide_prompt()
			_player.set_move_enabled(false)
			_start_wake_aster()

	# Multi-select gate: both near panel
	if _current_step == "multiselect_tutorial":
		var pp := _game_state.get_position("peris")
		var ap := _game_state.get_position("aster")
		if pp.distance_to(PANEL_POS) < 2.0 and ap.distance_to(PANEL_POS) < 2.0:
			_start_hack_tutorial()

# --- Input ---

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_SPACE:
			_toggle_pause()
		elif kc == KEY_Q:
			_on_emp_pressed()
		elif kc == KEY_TAB and _current_step in ["multiselect_tutorial", "hack_tutorial"]:
			_switch_character()

func _toggle_pause() -> void:
	if _scheduler.is_paused():
		_scheduler.resume()
		_hud.set_paused(false)
		_flush_queued_abilities()
	else:
		_scheduler.pause()
		_hud.set_paused(true)

func _on_pause_toggled(is_paused: bool) -> void:
	if is_paused:
		_scheduler.pause()
	else:
		_scheduler.resume()
		_flush_queued_abilities()

func _flush_queued_abilities() -> void:
	if _emp_queued:
		_emp_queued = false
		_fire_emp_both()

func _on_emp_pressed() -> void:
	if _current_step == "emp_tutorial" and _emp_count == 0:
		if _scheduler.is_paused():
			_emp_queued = true
			_hud.set_ability_state("emp", "queued")
		else:
			_fire_emp_both()

func _fire_emp_both() -> void:
	_stamina = maxf(0, _stamina - 25.0)
	_hud.set_portrait_stat("peris", "sta", _stamina)
	_emp_cooldown_end = _scheduler.get_current_tick() + 10.0
	_hud.set_ability_state("emp", "cooldown", 10.0)
	_camera.shake(0.3, 4.0)
	_escort_1.stop()
	_escort_2.stop()
	_unit_1_stunned = true
	_unit_2_stunned = true
	_emp_count = 2
	_reboot_active = true
	_tutorial_prompt.hide_prompt()
	# Reboot and multiselect tutorial on the scheduler
	_scheduler.schedule_after(30.0, _on_reboot, "reboot")
	_scheduler.schedule_after(1.5, _start_multiselect_tutorial, "multiselect")

func _on_reboot() -> void:
	if not _reboot_active:
		return
	_unit_1_stunned = false
	_unit_2_stunned = false
	if _escort_1:
		_escort_1.visible = true
	if _escort_2:
		_escort_2.visible = true
	if _current_step in ["emp_tutorial", "multiselect_tutorial"]:
		_emp_count = 0
		_reboot_active = false
		_enter_step("units_activate")
		_start_units_activate()

func _on_exit_button_pressed() -> void:
	# Flash "NO EXIT" on the indicator
	if _no_exit_label:
		var tween := create_tween()
		tween.tween_property(_no_exit_label, "modulate:a", 0.9, 0.2)
		tween.tween_interval(1.5)
		tween.tween_property(_no_exit_label, "modulate:a", 0.0, 0.5)
	_camera.shake(0.05, 10.0)

func _switch_character() -> void:
	var next_id: String = _hud.get_next_portrait_id(_active_character)
	_select_character(next_id)

func _select_character(id: String) -> void:
	if id == _active_character:
		return
	# Disable current character's movement
	if _active_character == "peris":
		_peris_node.set_move_enabled(false)
	else:
		_aster_node.set_move_enabled(false)
	# Activate new character
	if id == "peris":
		_peris_node.set_move_enabled(true)
		_player = _peris_node
		_camera.target = _peris_node
	else:
		_aster_node.set_move_enabled(true)
		_player = _aster_node
		_camera.target = _aster_node
	_active_character = id
	_hud.set_active_portrait(id)

func _on_character_selected(selected_ids: Array) -> void:
	if selected_ids.size() > 0 and selected_ids[0] != _active_character:
		if _current_step in ["multiselect_tutorial", "hack_tutorial"]:
			_select_character(selected_ids[0])

# --- Event steps ---

func _start_consciousness_fragments() -> void:
	_enter_step("consciousness_fragments")
	# Hide everything except Peris initially
	_emergency_light.light_energy = 0.0
	if _aster_node:
		_aster_node.visible = false
	for unit in [_escort_1, _escort_2]:
		if unit:
			unit.visible = false

	# Fragment 1: Fade in on Peris + red light, then fade out
	var t := create_tween()
	t.tween_property(_emergency_light, "light_energy", 2.0, 0.8)
	t.parallel().tween_property(_fade_rect, "color:a", 0.0, 0.8)
	t.tween_interval(1.5)
	t.tween_property(_fade_rect, "color:a", 1.0, 0.6)
	t.tween_callback(func():
		# Fragment 2: Show Aster, fade in, then fade out
		if _aster_node:
			_aster_node.visible = true
		var t2 := create_tween()
		t2.tween_property(_fade_rect, "color:a", 0.0, 0.8)
		t2.tween_interval(1.5)
		t2.tween_property(_fade_rect, "color:a", 1.0, 0.6)
		t2.tween_callback(_start_fade_in)
	)

func _start_fade_in() -> void:
	_enter_step("fade_in")
	# Full reveal: escort units, full lighting
	for unit in [_escort_1, _escort_2]:
		if unit:
			unit.visible = true
	_emergency_light.light_energy = 3.0
	var t := create_tween()
	t.tween_property(_fade_rect, "color:a", 0.0, 1.0)
	t.tween_callback(func():
		_scheduler.schedule_after(0.5, _start_waking, "waking")
	)

func _start_waking() -> void:
	_enter_step("waking")
	_dialogue_chain(
		["elevator.peris.where"],
		func(): _scheduler.schedule_after(1.0, _start_approach_aster, "approach")
	)

func _start_approach_aster() -> void:
	_enter_step("approach_aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_wake_aster() -> void:
	_enter_step("wake_aster")
	_hud.set_portrait_status("aster", "")
	_hud.set_portrait_stat("aster", "sta", 100)
	DialogueData.say_to(_dialogue, "elevator.peris.hey")
	# Tween Aster upright
	var tween := create_tween()
	tween.tween_property(_aster_node, "rotation_degrees:z", 0.0, 1.5)
	_dialogue.dialogue_finished.connect(func():
		_scheduler.schedule_after(0.5, func():
			DialogueData.say_to(_dialogue, "elevator.aster.waking")
			_dialogue.dialogue_finished.connect(func():
				DialogueData.say_to(_dialogue, "elevator.aster.where")
				_dialogue.dialogue_finished.connect(func():
					_scheduler.schedule_after(0.5, _start_conversation, "conversation")
				, CONNECT_ONE_SHOT)
			, CONNECT_ONE_SHOT)
		, "aster_wake")
	, CONNECT_ONE_SHOT)

func _start_conversation() -> void:
	_enter_step("conversation")
	_dialogue.default_hold_time = 3.0
	_dialogue_chain([
		"elevator.aster.device_locked",
		"elevator.peris.trapped",
		"elevator.peris.why",
		"elevator.aster.wellness",
		"elevator.aster.singing",
		"elevator.peris.citizen_ok",
		"elevator.aster.privacy",
		"elevator.peris.speaking_of",
		"elevator.peris.gel",
		"elevator.aster.perks",
	], _start_system_restored, 0.5)

func _start_system_restored() -> void:
	_enter_step("system_restored")
	_camera.shake(0.1, 8.0)
	# System restores devices — Aster's data overlay activates
	_setup_perception("data", _aster_node)
	# Control panel now visible through the data overlay
	_control_panel.visible = true
	DialogueData.say_to(_dialogue, "elevator.system.restored")
	DialogueData.say_to(_dialogue, "elevator.aster.overlay")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0.5, _start_units_activate, "units_activate"),
		CONNECT_ONE_SHOT
	)

func _start_units_activate() -> void:
	_enter_step("units_activate")
	# Auto-pause so the player can read the situation
	_scheduler.pause()
	_hud.set_paused(true)
	# Both escorts advance
	_escort_1.walk_to(_peris_node.global_position + Vector3(0.5, 0, 0))
	_escort_2.walk_to(_peris_node.global_position + Vector3(0, 0, 0.5))
	_camera.shake(0.2, 6.0)
	_dialogue_chain(
		["elevator.unit.protocol", "elevator.aster.device"],
		func(): _scheduler.schedule_after(0.5, _start_emp_tutorial, "emp_tut")
	)

func _start_emp_tutorial() -> void:
	_enter_step("emp_tutorial")
	_hud.set_ability_state("emp", "ready")
	_tutorial_prompt.show_prompt("[Q] — EMP")

func _start_emp_tutorial_2() -> void:
	# Kept for reboot fallback but no longer triggered normally
	_enter_step("emp_tutorial_2")

func _start_multiselect_tutorial() -> void:
	_enter_step("multiselect_tutorial")
	_peris_node.set_move_enabled(true)
	_aster_node.set_move_enabled(false)
	_active_character = "peris"
	_player = _peris_node
	_camera.target = _peris_node
	_hud.set_active_portrait("peris")
	# Auto-pause so the player can plan their move
	_scheduler.pause()
	_hud.set_paused(true)
	DialogueData.say_to(_dialogue, "elevator.aster.stay_close")
	_dialogue.dialogue_finished.connect(func():
		_tutorial_prompt.show_prompt("[Tab] — switch  [Space] — unpause")
	, CONNECT_ONE_SHOT)

func _start_hack_tutorial() -> void:
	_enter_step("hack_tutorial")
	_tutorial_prompt.hide_prompt()
	# Force Aster active for hacking
	if _active_character != "aster":
		_switch_character()
	_peris_node.set_move_enabled(false)
	_control_panel.visible = true
	DialogueData.say_to(_dialogue, "elevator.aster.hack")

func _on_panel_hacked() -> void:
	if _current_step != "hack_tutorial":
		return
	_reboot_active = false
	_camera.shake(0.3, 3.0)
	DialogueData.say_to(_dialogue, "elevator.system.override")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0.5, _start_doors_open, "doors"),
		CONNECT_ONE_SHOT
	)

func _start_doors_open() -> void:
	_enter_step("doors_open")
	# Tween door panels apart
	if _door_panel_a and _door_panel_b:
		var tween := create_tween()
		tween.tween_property(_door_panel_a, "position:z", -1.5, 1.5)
		tween.parallel().tween_property(_door_panel_b, "position:z", 1.5, 1.5)
	# Add light from outside
	var outside_light := OmniLight3D.new()
	outside_light.position = Vector3(3.5, 1.5, 0)
	outside_light.light_color = Color(0.4, 0.4, 0.5)
	outside_light.light_energy = 2.0
	outside_light.omni_range = 6.0
	find_child("Environment", false, false).add_child(outside_light)
	_scheduler.schedule_after(2.0, _start_lockout, "lockout")

func _start_lockout() -> void:
	_enter_step("lockout")
	_dialogue.default_hold_time = 2.5
	_dialogue_chain([
		"elevator.system.noncompliant",
		"elevator.aster.locked",
		"elevator.peris.back_to_what",
		"elevator.aster.forward",
	], func(): _scheduler.schedule_after(1.0, _start_corridor, "corridor"))

func _start_corridor() -> void:
	_enter_step("corridor")
	_load_chunk("bridge")
	_load_chunk("below")
	# Walk both characters out through the doors
	var exit_pos := Vector3(ELEVATOR_SIZE.x / 2.0 + 3.0, 0, 0)
	_game_state.command_move_to_pos("aster", exit_pos)
	_game_state.command_move_to_pos("peris", exit_pos + Vector3(0, 0, 1.0))
	_dialogue_chain([
		"elevator.peris.not_supposed",
		"elevator.aster.no_service",
	], func(): _scheduler.schedule_after(2.0, _start_bridge, "bridge"))

func _start_bridge() -> void:
	_enter_step("bridge")
	# Walk to the bridge railing
	var bridge_pos := Vector3(ELEVATOR_SIZE.x / 2.0 + 12.0, 0, 0)
	_game_state.command_move_to_pos("aster", bridge_pos + Vector3(1.0, 0, 0))
	_game_state.command_move_to_pos("peris", bridge_pos)
	_dialogue_chain([
		"elevator.peris.bodies",
		"elevator.aster.logs",
		"elevator.aster.ahead",
	], func(): _scheduler.schedule_after(1.0, _start_bridge_collapse, "collapse"))

# --- Bridge Collapse ---

func _start_bridge_collapse() -> void:
	_enter_step("bridge_collapse")
	_player.set_move_enabled(false)
	_game_state.command_stop("aster")
	_game_state.command_stop("peris")
	# Hide escort units (abandoned above)
	if _escort_1:
		_escort_1.visible = false
	if _escort_2:
		_escort_2.visible = false
	# Warning rumble
	_camera.shake(0.4, 2.0)
	DialogueData.say_to(_dialogue, "elevator.peris.floor")
	_scheduler.schedule_after(0.8, _execute_bridge_fall, "bridge_fall")

func _execute_bridge_fall() -> void:
	_camera.shake(0.6, 1.5)
	var fall_duration := 1.2
	var bridge_chunk: Node3D = _chunks.get("bridge")
	var bridge_floor: Node3D = bridge_chunk.find_child("BridgeFloor", false, false) if bridge_chunk else null
	var tween := create_tween()
	tween.set_parallel(true)
	# Bridge floor falls with slight rotation
	if bridge_floor:
		tween.tween_property(bridge_floor, "position:y", BELOW_Y, fall_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(bridge_floor, "rotation:x", 0.15, fall_duration * 0.8)
	# Characters fall
	for char_node in [_peris_node, _aster_node]:
		tween.tween_property(char_node, "position:y", BELOW_Y + 0.5, fall_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Camera follows
	tween.tween_property(_camera, "follow_offset:y", _camera.follow_offset.y + BELOW_Y, fall_duration * 1.1)
	tween.chain().tween_callback(_on_fall_landed)

func _on_fall_landed() -> void:
	_camera.shake(0.3, 6.0)
	# Update GameState positions to the below level
	for char_id in ["peris", "aster"]:
		var pos: Vector3 = _game_state.get_position(char_id)
		_game_state.characters[char_id].position = Vector3(pos.x, BELOW_Y + 0.5, pos.z)
	# Unload chunks above
	_unload_chunk("elevator")
	_unload_chunk("bridge")
	# Null out freed elevator references
	_emergency_light = null
	_indicator_b_label = null
	_floor_indicator = null
	_door_panel_a = null
	_door_panel_b = null
	_no_exit_label = null
	_scheduler.schedule_after(1.0, _start_fallen, "fallen")

func _start_fallen() -> void:
	_enter_step("fallen")
	_player.set_move_enabled(true)
	_dialogue_chain([
		"elevator.peris.hurt",
		"elevator.aster.sublevel",
		"elevator.aster.two_paths",
	], func(): _scheduler.schedule_after(1.5, _start_route_choice, "route_choice"))

# --- Route Choice (stub — Phase 3) ---

func _start_route_choice() -> void:
	_enter_step("route_choice")
	# Phase 3: fork geometry, position-gated convergence
	_scheduler.schedule_after(2.0, _start_junction_arrive, "junction")

# --- Junction (stub — Phase 4) ---

func _start_junction_arrive() -> void:
	_enter_step("junction_arrive")
	_load_chunk("junction")
	# Phase 4: Endo greeting, shelter, night watch, dawn
	_scheduler.schedule_after(2.0, _complete, "complete")

func _complete() -> void:
	_enter_step("complete")
	# Placeholder transition — will be replaced by dawn step in Phase 4
	get_tree().change_scene_to_file("res://scenes/tutorial/leaving_facility.tscn")

func _build_bridge_chunk(parent: Node3D) -> void:
	var start_x := ELEVATOR_SIZE.x / 2.0 + 0.5
	var corridor_color := Color(0.07, 0.07, 0.09)
	var wall_color := Color(0.1, 0.1, 0.12)

	# Corridor floor leading out of elevator
	_add_corridor_section(parent, Vector3(start_x + 3.0, -0.05, 0), Vector3(7, 0.1, 4), corridor_color)
	var body := StaticBody3D.new()
	body.position = Vector3(start_x + 3.0, -0.01, 0)
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7, 0.02, 4)
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	# Corridor walls
	_add_wall(parent, Vector3(start_x + 3.0, 2.0, -2.0), Vector3(7, 4, 0.2), wall_color)
	_add_wall(parent, Vector3(start_x + 3.0, 2.0, 2.0), Vector3(7, 4, 0.2), wall_color)

	# Corridor light
	var cor_light := OmniLight3D.new()
	cor_light.position = Vector3(start_x + 3.0, 3.0, 0)
	cor_light.light_color = Color(0.3, 0.2, 0.15)
	cor_light.light_energy = 1.5
	cor_light.omni_range = 8.0
	parent.add_child(cor_light)

	# Bridge / catwalk — named sub-node for collapse tween
	var bridge_start := start_x + 7.0
	var bridge_floor := Node3D.new()
	bridge_floor.name = "BridgeFloor"
	parent.add_child(bridge_floor)
	_add_corridor_section(bridge_floor, Vector3(bridge_start + 5.0, -0.05, 0), Vector3(12, 0.1, 3), corridor_color)
	var b2 := StaticBody3D.new()
	b2.position = Vector3(bridge_start + 5.0, -0.01, 0)
	b2.collision_layer = 1
	b2.collision_mask = 0
	var c2 := CollisionShape3D.new()
	var s2 := BoxShape3D.new()
	s2.size = Vector3(12, 0.02, 3)
	c2.shape = s2
	b2.add_child(c2)
	bridge_floor.add_child(b2)

	# Partial railing (on bridge floor so it falls with it)
	for i in range(5):
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.05, 0.8, 0.05)
		rail.mesh = rb
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.15, 0.15, 0.18)
		rail.material_override = rm
		rail.position = Vector3(bridge_start + 1.5 + i * 2.0, 0.4, -1.4)
		bridge_floor.add_child(rail)

	# Bridge lighting
	var bridge_light := OmniLight3D.new()
	bridge_light.position = Vector3(bridge_start + 5.0, 3.0, 0)
	bridge_light.light_color = Color(0.25, 0.18, 0.12)
	bridge_light.light_energy = 1.0
	bridge_light.omni_range = 10.0
	parent.add_child(bridge_light)

func _build_below_chunk(parent: Node3D) -> void:
	var bridge_start := ELEVATOR_SIZE.x / 2.0 + 0.5 + 7.0
	var ground_y := BELOW_Y

	# Ground collision (walkable after collapse)
	var ground_body := StaticBody3D.new()
	ground_body.position = Vector3(bridge_start + 5.0, ground_y - 0.01, 0)
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(40, 0.02, 16)
	gc.shape = gs
	ground_body.add_child(gc)
	parent.add_child(ground_body)

	# Ground floor visual
	_add_corridor_section(parent, Vector3(bridge_start + 5.0, ground_y - 0.05, 0), Vector3(40, 0.1, 16), Color(0.05, 0.05, 0.07))

	# Iron blooms (faint orange glow on walls and floor)
	for i in range(4):
		var bloom := OmniLight3D.new()
		bloom.position = Vector3(bridge_start + 1.5 + i * 3.0, ground_y + 1.0, randf_range(-4, 4))
		bloom.light_color = Color(0.7, 0.3, 0.1)
		bloom.light_energy = 0.5
		bloom.omni_range = 3.0
		parent.add_child(bloom)

	# Chelators — small ring-shaped things moving along the walls
	_bridge_chelators.clear()
	for i in range(6):
		var chelator := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.04
		torus.outer_radius = 0.12
		chelator.mesh = torus
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.4, 0.25, 0.15)
		cm.metallic = 0.6
		cm.roughness = 0.3
		chelator.material_override = cm
		var cx := bridge_start + 1.0 + i * 2.0
		var cz := -5.0 + randf_range(-1, 1) if i % 2 == 0 else 5.0 + randf_range(-1, 1)
		chelator.position = Vector3(cx, ground_y + 0.5 + randf_range(0, 2.0), cz)
		chelator.rotation = Vector3(randf_range(0, TAU), randf_range(0, TAU), 0)
		parent.add_child(chelator)
		_bridge_chelators.append(chelator)

	# Fluor — yellow-green bioluminescence in a breached corner
	var fluor_light := OmniLight3D.new()
	fluor_light.position = Vector3(bridge_start + 3.0, ground_y + 1.5, 6.0)
	fluor_light.light_color = Color(0.6, 0.9, 0.2)
	fluor_light.light_energy = 0.8
	fluor_light.omni_range = 3.5
	parent.add_child(fluor_light)
	var fluor_mesh := MeshInstance3D.new()
	var fluor_sphere := SphereMesh.new()
	fluor_sphere.radius = 0.3
	fluor_sphere.height = 0.6
	fluor_mesh.mesh = fluor_sphere
	var fluor_mat := StandardMaterial3D.new()
	fluor_mat.albedo_color = Color(0.4, 0.7, 0.15, 0.7)
	fluor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fluor_mat.emission_enabled = true
	fluor_mat.emission = Color(0.5, 0.8, 0.2)
	fluor_mat.emission_energy_multiplier = 1.5
	fluor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fluor_mesh.material_override = fluor_mat
	fluor_mesh.position = Vector3(bridge_start + 3.0, ground_y + 1.2, 6.0)
	parent.add_child(fluor_mesh)

	# Chain hanging alongside a conduit bundle
	var chain := MeshInstance3D.new()
	var chain_cyl := CylinderMesh.new()
	chain_cyl.top_radius = 0.06
	chain_cyl.bottom_radius = 0.08
	chain_cyl.height = 3.5
	chain.mesh = chain_cyl
	var chain_mat := StandardMaterial3D.new()
	chain_mat.albedo_color = Color(0.08, 0.06, 0.05)
	chain.material_override = chain_mat
	chain.position = Vector3(bridge_start + 8.0, ground_y + 3.0, -5.5)
	chain.rotation.z = 0.15
	parent.add_child(chain)

	# Bodies between the blooms
	for i in range(4):
		var body_mesh := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.2
		cap.height = 0.8
		body_mesh.mesh = cap
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.15, 0.12, 0.1)
		body_mesh.material_override = bm
		body_mesh.position = Vector3(bridge_start + 1.0 + i * 3.0, ground_y, randf_range(-3, 3))
		body_mesh.rotation.z = PI / 2.0
		parent.add_child(body_mesh)

	# Powered terminal (faint blue-green)
	var terminal_glow := OmniLight3D.new()
	terminal_glow.position = Vector3(bridge_start + 10.0, ground_y + 2.0, -5.0)
	terminal_glow.light_color = Color(0.2, 0.5, 0.4)
	terminal_glow.light_energy = 0.6
	terminal_glow.omni_range = 4.0
	parent.add_child(terminal_glow)

	# Something growing in an alcove (blue-green, alive)
	var growth_light := OmniLight3D.new()
	growth_light.position = Vector3(bridge_start + 6.0, ground_y + 0.8, 5.5)
	growth_light.light_color = Color(0.15, 0.5, 0.45)
	growth_light.light_energy = 0.4
	growth_light.omni_range = 2.5
	parent.add_child(growth_light)

func _build_junction_chunk(parent: Node3D) -> void:
	# Endo's shelter — built in Phase 4
	pass

func _add_corridor_section(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mesh.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)

# --- Environment ---

func _build_elevator_chunk(parent: Node3D) -> void:
	var hw := ELEVATOR_SIZE.x / 2.0
	var hd := ELEVATOR_SIZE.z / 2.0
	var h := ELEVATOR_SIZE.y

	# Floor
	var floor_mesh := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(ELEVATOR_SIZE.x, 0.1, ELEVATOR_SIZE.z)
	floor_mesh.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.1, 0.1, 0.12)
	fm.metallic = 0.3
	fm.roughness = 0.4
	floor_mesh.material_override = fm
	floor_mesh.position = Vector3(0, -0.05, 0)
	parent.add_child(floor_mesh)

	# Floor collision
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0, -0.01, 0)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(ELEVATOR_SIZE.x, 0.02, ELEVATOR_SIZE.z)
	fc.shape = fs
	floor_body.add_child(fc)
	parent.add_child(floor_body)

	# Walls
	var wc := Color(0.12, 0.12, 0.14)
	_add_wall(parent, Vector3(0, h / 2.0, -hd), Vector3(ELEVATOR_SIZE.x, h, 0.2), wc)
	_add_wall(parent, Vector3(0, h / 2.0, hd), Vector3(ELEVATOR_SIZE.x, h, 0.2), wc)
	_add_wall(parent, Vector3(-hw, h / 2.0, 0), Vector3(0.2, h, ELEVATOR_SIZE.z), wc)
	_add_wall(parent, Vector3(hw, h / 2.0, -hd * 0.55), Vector3(0.2, h, hd * 0.8), wc)
	_add_wall(parent, Vector3(hw, h / 2.0, hd * 0.55), Vector3(0.2, h, hd * 0.8), wc)

	# Door panels (tween apart when hack succeeds)
	_door_panel_a = _make_door_panel(parent, Vector3(hw - 0.05, h / 2.0, -0.6), wc)
	_door_panel_b = _make_door_panel(parent, Vector3(hw - 0.05, h / 2.0, 0.6), wc)

	# Ceiling
	_add_wall(parent, Vector3(0, h, 0), Vector3(ELEVATOR_SIZE.x, 0.1, ELEVATOR_SIZE.z), Color(0.06, 0.06, 0.08))

	# Emergency light (red, pulsing)
	_emergency_light = OmniLight3D.new()
	_emergency_light.position = Vector3(0, h - 0.3, 0)
	_emergency_light.light_color = Color(0.85, 0.15, 0.1)
	_emergency_light.light_energy = 3.0
	_emergency_light.omni_range = 10.0
	parent.add_child(_emergency_light)

	# Secondary fill light
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, h * 0.6, 0)
	fill.light_color = Color(0.4, 0.25, 0.2)
	fill.light_energy = 1.0
	fill.omni_range = 8.0
	parent.add_child(fill)

	# Floor indicator: "3" steady + "B" flickering
	var indicator_x := hw - 0.1
	_floor_indicator = Label3D.new()
	_floor_indicator.text = "3"
	_floor_indicator.font_size = 64
	_floor_indicator.pixel_size = 0.012
	_floor_indicator.modulate = Color(0.8, 0.2, 0.1, 0.9)
	_floor_indicator.position = Vector3(indicator_x, h * 0.7, 0.2)
	_floor_indicator.rotation.y = -PI / 2.0
	parent.add_child(_floor_indicator)

	_indicator_b_label = Label3D.new()
	_indicator_b_label.text = "B"
	_indicator_b_label.font_size = 64
	_indicator_b_label.pixel_size = 0.012
	_indicator_b_label.modulate = Color(0.8, 0.2, 0.1, 0.7)
	_indicator_b_label.position = Vector3(indicator_x, h * 0.7, -0.2)
	_indicator_b_label.rotation.y = -PI / 2.0
	parent.add_child(_indicator_b_label)

	# "NO EXIT" label (hidden, flashes when exit button pressed)
	_no_exit_label = Label3D.new()
	_no_exit_label.text = "NO EXIT"
	_no_exit_label.font_size = 36
	_no_exit_label.pixel_size = 0.01
	_no_exit_label.modulate = Color(0.9, 0.15, 0.1, 0.0)
	_no_exit_label.position = Vector3(indicator_x, h * 0.5, 0)
	_no_exit_label.rotation.y = -PI / 2.0
	parent.add_child(_no_exit_label)

	# Control panel visual
	var panel_mesh := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.15, 1.0, 0.6)
	panel_mesh.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.14, 0.14, 0.17)
	pm.emission_enabled = true
	pm.emission = Color(0.05, 0.1, 0.2)
	pm.emission_energy_multiplier = 0.5
	panel_mesh.material_override = pm
	panel_mesh.position = Vector3(indicator_x, 1.0, 0)
	parent.add_child(panel_mesh)

	# Standby indicator lights near escort units
	for pos in [ESCORT_1_POS, ESCORT_2_POS]:
		var standby := OmniLight3D.new()
		standby.position = pos + Vector3(0, 1.5, 0)
		standby.light_color = Color(0.3, 0.3, 0.4)
		standby.light_energy = 0.5
		standby.omni_range = 2.5
		parent.add_child(standby)

	# Ceiling panel strips
	for i in range(3):
		var strip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(ELEVATOR_SIZE.x * 0.8, 0.02, 0.15)
		strip.mesh = sb
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.08, 0.08, 0.1)
		strip.material_override = sm
		strip.position = Vector3(0, h - 0.02, -2.0 + i * 2.0)
		parent.add_child(strip)

func _make_door_panel(parent: Node3D, pos: Vector3, color: Color) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.15, ELEVATOR_SIZE.y, 1.2)
	panel.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.1)
	panel.material_override = mat
	panel.position = pos
	parent.add_child(panel)
	return panel
