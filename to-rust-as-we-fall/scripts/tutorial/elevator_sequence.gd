@tool
extends TutorialSequence

## Elevator tutorial. First meeting between Aster and Peris.
## Peris wakes in a stuck elevator. Aster is unconscious. Escort units on standby.
## Conversation (emotional core). Units activate. EMP (Q). Character switching (Tab).
## Hack the panel. Doors open. Tags flagged NON-COMPLIANT. Transition to leaving_facility.

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

# EMP state
var _emp_count := 0
var _unit_1_stunned := false
var _unit_2_stunned := false
var _reboot_timer := 30.0
var _reboot_active := false
var _stamina := 100.0

# Positions (elevator ~4.5x4.5, centered at origin)
const PERIS_START := Vector3(-0.5, 0.5, 0.8)
const ASTER_POS := Vector3(1.0, 0, -1.0)
const ESCORT_1_POS := Vector3(-1.5, 0, -1.5)
const ESCORT_2_POS := Vector3(-1.5, 0, 1.5)
const PANEL_POS := Vector3(1.5, 0, 0)

# --- Virtual overrides ---

func _build_scene() -> void:
	_build_environment()

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

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 4, 3))

func _register_characters() -> void:
	_register_gs_character("peris", _peris_node, 2.5)
	_register_gs_character("aster", _aster_node, 2.5)
	_aster_node.set_move_enabled(false)

func _setup_ui() -> void:
	# Control panel interactable (hacking target)
	_control_panel = preload("res://scenes/game/interactable.tscn").instantiate()
	_control_panel.name = "ControlPanel"
	_control_panel.description = "Control Panel"
	_control_panel.one_shot = true
	_control_panel.dwell_time = 3.0
	_control_panel.position = PANEL_POS + Vector3(0, 0.8, 0)
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
	_exit_button.position = Vector3(2.0, 1.0, 0.8)
	add_child(_exit_button)
	_exit_button.interacted.connect(_on_exit_button_pressed)

func _begin() -> void:
	_player.set_move_enabled(false)
	_fade_rect.color = Color(0, 0, 0, 1)
	_scheduler.schedule_after(1.0, _start_consciousness_fragments, "fragments")

func _compute_speed() -> float:
	return 10.0 if Input.is_key_pressed(KEY_F) else 1.0

func _on_process(delta: float, spd: float) -> void:
	# Emergency light pulse
	if _emergency_light:
		_emergency_light.light_energy = 1.5 + sin(Time.get_ticks_msec() * 0.003) * 0.5

	# Floor indicator: "3" is steady, "B" flickers
	_indicator_timer += delta * spd
	if _indicator_b_label and _indicator_timer > 0.3:
		_indicator_timer = 0.0
		_indicator_b_label.visible = not _indicator_b_label.visible

	# Escort unit flicker when stunned (toggle visibility)
	if _unit_1_stunned and _escort_1:
		_escort_1.visible = int(Time.get_ticks_msec() / 100) % 2 == 0
	if _unit_2_stunned and _escort_2:
		_escort_2.visible = int(Time.get_ticks_msec() / 100) % 2 == 0

	# Reboot timer
	if _reboot_active:
		_reboot_timer -= delta * spd
		if _reboot_timer <= 0:
			_reboot_timer = 30.0
			_unit_1_stunned = false
			_unit_2_stunned = false
			if _escort_1:
				_escort_1.modulate.a = 1.0
			if _escort_2:
				_escort_2.modulate.a = 1.0
			# Units reboot — re-trigger EMP tutorial if not past it
			if _current_step in ["emp_tutorial", "emp_tutorial_2", "multiselect_tutorial"]:
				_emp_count = 0
				_enter_step("units_activate")
				_start_units_activate()

	# Fade updates
	if _current_step == "fade_in":
		_update_fade_in(2.5)
	elif _current_step == "transition_out":
		_update_fade_out(Color(0.02, 0.02, 0.03), 2.0)

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
		if kc == KEY_Q:
			_on_emp_pressed()
		elif kc == KEY_TAB and _current_step in ["multiselect_tutorial", "hack_tutorial"]:
			_switch_character()

func _on_emp_pressed() -> void:
	if _current_step == "emp_tutorial" and _emp_count == 0:
		_fire_emp(_escort_1)
		_unit_1_stunned = true
		_emp_count = 1
		_scheduler.schedule_after(1.5, _start_emp_tutorial_2, "emp2")
	elif _current_step == "emp_tutorial_2" and _emp_count == 1:
		_fire_emp(_escort_2)
		_unit_2_stunned = true
		_emp_count = 2
		_reboot_active = true
		_reboot_timer = 30.0
		_tutorial_prompt.hide_prompt()
		_scheduler.schedule_after(1.0, _start_multiselect_tutorial, "multiselect")

func _fire_emp(unit: Node3D) -> void:
	_stamina = maxf(0, _stamina - 15.0)
	_camera.shake(0.2, 4.0)
	unit.stop()

func _on_exit_button_pressed() -> void:
	# Flash "NO EXIT" on the indicator
	if _no_exit_label:
		var tween := create_tween()
		tween.tween_property(_no_exit_label, "modulate:a", 0.9, 0.2)
		tween.tween_interval(1.5)
		tween.tween_property(_no_exit_label, "modulate:a", 0.0, 0.5)
	_camera.shake(0.05, 10.0)

func _switch_character() -> void:
	if _active_character == "peris":
		_peris_node.set_move_enabled(false)
		_aster_node.set_move_enabled(true)
		_player = _aster_node
		_active_character = "aster"
		_camera.target = _aster_node
	else:
		_aster_node.set_move_enabled(false)
		_peris_node.set_move_enabled(true)
		_player = _peris_node
		_active_character = "peris"
		_camera.target = _peris_node

# --- Event steps ---

func _start_consciousness_fragments() -> void:
	_enter_step("consciousness_fragments")
	_show_thought(DialogueData.text("elevator.fragment.01"))
	_scheduler.schedule_after(2.0, func():
		_hide_thought()
		_scheduler.schedule_after(0.5, func():
			_show_thought(DialogueData.text("elevator.fragment.02"))
			_scheduler.schedule_after(2.0, func():
				_hide_thought()
				_scheduler.schedule_after(0.5, func():
					_show_thought(DialogueData.text("elevator.fragment.03"))
					_scheduler.schedule_after(2.0, func():
						_hide_thought()
						_scheduler.schedule_after(0.5, _start_fade_in, "fade_in")
					, "frag_hide3")
				, "frag3")
			, "frag_hide2")
		, "frag2")
	, "frag_hide1")

func _start_fade_in() -> void:
	_enter_step("fade_in")
	_fade_from(Color(0, 0, 0, 1), 3.0, _start_waking, "waking")

func _start_waking() -> void:
	_enter_step("waking")
	_dialogue_chain(
		["elevator.peris.where", "elevator.narration.room"],
		func(): _scheduler.schedule_after(1.0, _start_approach_aster, "approach")
	)

func _start_approach_aster() -> void:
	_enter_step("approach_aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_wake_aster() -> void:
	_enter_step("wake_aster")
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
		"elevator.peris.explain",
		"elevator.aster.wellness",
		"elevator.peris.singing",
		"elevator.aster.prickly",
		"elevator.aster.already_knew",
		"elevator.aster.protocol",
		"elevator.peris.and_then",
		"elevator.aster.bang",
		"elevator.aster.there_was",
		"elevator.aster.whimper",
		"elevator.aster.ninety",
		"elevator.peris.helped",
		"elevator.peris.sanction",
		"elevator.aster.gel",
		"elevator.peris.gel",
		"elevator.aster.thats",
	], _start_units_activate, 0.5)

func _start_units_activate() -> void:
	_enter_step("units_activate")
	# Escort unit lights brighten
	_escort_1.walk_to(_peris_node.global_position + Vector3(0.5, 0, 0))
	_dialogue_chain(
		["elevator.unit.protocol", "elevator.aster.device"],
		func(): _scheduler.schedule_after(0.5, _start_emp_tutorial, "emp_tut")
	)

func _start_emp_tutorial() -> void:
	_enter_step("emp_tutorial")
	_tutorial_prompt.show_prompt("[Q] — EMP")

func _start_emp_tutorial_2() -> void:
	_enter_step("emp_tutorial_2")
	_escort_2.walk_to(_peris_node.global_position + Vector3(0, 0, 0.5))
	DialogueData.say_to(_dialogue, "elevator.aster.another")
	_tutorial_prompt.show_prompt("[Q] — EMP")

func _start_multiselect_tutorial() -> void:
	_enter_step("multiselect_tutorial")
	_peris_node.set_move_enabled(true)
	_aster_node.set_move_enabled(false)
	_active_character = "peris"
	_player = _peris_node
	_camera.target = _peris_node
	DialogueData.say_to(_dialogue, "elevator.aster.stay_close")
	_dialogue.dialogue_finished.connect(func():
		_tutorial_prompt.show_prompt("[Tab] — switch character")
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
	_dialogue_chain(
		["elevator.system.override", "elevator.narration.doors"],
		func(): _scheduler.schedule_after(1.0, _start_doors_open, "doors")
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
	], func(): _scheduler.schedule_after(1.0, _start_transition_out, "transition"))

func _start_transition_out() -> void:
	_enter_step("transition_out")
	_player.set_move_enabled(false)
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(2.5, _complete, "complete")

func _complete() -> void:
	_enter_step("complete")
	get_tree().change_scene_to_file("res://scenes/tutorial/leaving_facility.tscn")

# --- Environment ---

func _build_environment() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	# Floor
	var floor_mesh := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(4.5, 0.1, 4.5)
	floor_mesh.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.08, 0.08, 0.1)
	fm.metallic = 0.4
	fm.roughness = 0.3
	floor_mesh.material_override = fm
	floor_mesh.position = Vector3(0, -0.05, 0)
	env.add_child(floor_mesh)

	# Floor collision
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0, -0.01, 0)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(4.5, 0.02, 4.5)
	fc.shape = fs
	floor_body.add_child(fc)
	env.add_child(floor_body)

	# Walls (dark metallic)
	var wc := Color(0.1, 0.1, 0.12)
	_add_wall(env, Vector3(0, 1.5, -2.25), Vector3(4.5, 3, 0.2), wc)    # back
	_add_wall(env, Vector3(0, 1.5, 2.25), Vector3(4.5, 3, 0.2), wc)     # front
	_add_wall(env, Vector3(-2.25, 1.5, 0), Vector3(0.2, 3, 4.5), wc)    # left
	# Right wall (door wall) — two halves with gap in the middle
	_add_wall(env, Vector3(2.25, 1.5, -1.5), Vector3(0.2, 3, 1.4), wc)
	_add_wall(env, Vector3(2.25, 1.5, 1.5), Vector3(0.2, 3, 1.4), wc)

	# Door panels (tween apart when hack succeeds)
	_door_panel_a = _make_door_panel(env, Vector3(2.2, 1.5, -0.4), wc)
	_door_panel_b = _make_door_panel(env, Vector3(2.2, 1.5, 0.4), wc)

	# Ceiling
	_add_wall(env, Vector3(0, 3.0, 0), Vector3(4.5, 0.1, 4.5), Color(0.05, 0.05, 0.07))

	# Emergency light (red, pulsing)
	_emergency_light = OmniLight3D.new()
	_emergency_light.position = Vector3(0, 2.8, 0)
	_emergency_light.light_color = Color(0.8, 0.15, 0.1)
	_emergency_light.light_energy = 1.5
	_emergency_light.omni_range = 6.0
	env.add_child(_emergency_light)

	# Floor indicator
	# Floor indicator: "3" steady + "B" flickering
	_floor_indicator = Label3D.new()
	_floor_indicator.text = "3"
	_floor_indicator.font_size = 48
	_floor_indicator.pixel_size = 0.01
	_floor_indicator.modulate = Color(0.8, 0.2, 0.1, 0.8)
	_floor_indicator.position = Vector3(2.1, 2.3, 0.15)
	_floor_indicator.rotation.y = -PI / 2.0
	env.add_child(_floor_indicator)

	_indicator_b_label = Label3D.new()
	_indicator_b_label.text = "B"
	_indicator_b_label.font_size = 48
	_indicator_b_label.pixel_size = 0.01
	_indicator_b_label.modulate = Color(0.8, 0.2, 0.1, 0.6)
	_indicator_b_label.position = Vector3(2.1, 2.3, -0.15)
	_indicator_b_label.rotation.y = -PI / 2.0
	env.add_child(_indicator_b_label)

	# "NO EXIT" label (hidden, flashes when exit button is pressed)
	_no_exit_label = Label3D.new()
	_no_exit_label.text = "NO EXIT"
	_no_exit_label.font_size = 28
	_no_exit_label.pixel_size = 0.008
	_no_exit_label.modulate = Color(0.9, 0.15, 0.1, 0.0)
	_no_exit_label.position = Vector3(2.1, 1.8, 0)
	_no_exit_label.rotation.y = -PI / 2.0
	env.add_child(_no_exit_label)

	# Control panel visual (dark box with small emissive screen)
	var panel_mesh := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.15, 0.8, 0.5)
	panel_mesh.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.12, 0.12, 0.15)
	pm.emission_enabled = true
	pm.emission = Color(0.05, 0.08, 0.15)
	pm.emission_energy_multiplier = 0.3
	panel_mesh.material_override = pm
	panel_mesh.position = Vector3(2.1, 1.0, 0)
	env.add_child(panel_mesh)

	# Standby indicator lights near escort units
	for pos in [ESCORT_1_POS, ESCORT_2_POS]:
		var standby := OmniLight3D.new()
		standby.position = pos + Vector3(0, 1.2, 0)
		standby.light_color = Color(0.3, 0.3, 0.35)
		standby.light_energy = 0.3
		standby.omni_range = 1.5
		env.add_child(standby)

	# WorldEnvironment
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.1, 0.08)
	e.ambient_light_energy = 0.3
	e.glow_enabled = true
	e.glow_intensity = 0.2
	e.glow_bloom = 0.05
	we.environment = e
	env.add_child(we)

func _make_door_panel(parent: Node3D, pos: Vector3, color: Color) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.15, 3, 0.75)
	panel.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.1)
	panel.material_override = mat
	panel.position = pos
	parent.add_child(panel)
	return panel
