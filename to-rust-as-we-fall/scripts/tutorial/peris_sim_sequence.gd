@tool
extends TutorialSequence

## Peris's simulation tutorial. Teaches walk/run, stamina, Protect ability.
## Warm, social workspace. Session with Monos. Attack through the portal.
## The first ability the player uses in the entire game is an act of care.
##
## Event-driven: uses EventScheduler + GameState interpolation.
## Each step is a function that does its work and schedules the next event.

static var _visit_phase := 1

var _has_sprinted := false
var _has_protected := false
var _protect_end_tick := 0.0

var _monos
var _portal_visual: MeshInstance3D
var _portal_light: OmniLight3D
var _attack_particles: OmniLight3D
var _portal_tween_active := false
var _hud  # GameHUD
var _session_timer_label: Label

# Stats
var _stamina := 100.0
const STAMINA_MAX := 100.0
var _is_running := false
var _is_paused := false
var _session_time := 0.0
var _efficiency_score := 100.0

# Positions
const DESK_POS := Vector3(0, 0, 0)
const PORTAL_POS := Vector3(7, 0, 0)
const MONOS_POS := Vector3(8.5, 0, 0)
const PERIS_START := Vector3(0, 0.5, -1)

# --- Virtual method overrides ---

func _build_scene() -> void:
	_build_environment()
	_build_decorations()
	_build_portal()

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	_player = _create_player_character("Peris", Color(1.0, 0.67, 0.27))
	_player.position = PERIS_START
	chars.add_child(_player)

	_monos = _create_npc("Monos", Color(0.6, 0.5, 0.35))
	_monos.display_name = "MONOS"
	_monos.position = MONOS_POS
	_monos.visible = false
	chars.add_child(_monos)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 8, 6))

func _register_characters() -> void:
	_register_gs_character("peris", _player, 3.0, {"stamina": _stamina})

func _setup_ui() -> void:
	_thought_label.add_theme_color_override("font_color", Color(0.75, 0.6, 0.45))

	# Game HUD — stamina bar, run toggle, protect ability
	_hud = CanvasLayer.new()
	_hud.name = "GameHUD"
	_hud.set_script(preload("res://scripts/game/game_hud.gd"))
	add_child(_hud)
	_hud.add_stat_bar("sta", Color(0.3, 0.5, 0.7), STAMINA_MAX, _stamina)
	_hud.show_pause_toggle(false)
	_hud.show_run_toggle(false)
	_hud.add_ability("protect", "PROTECT", "X", Color(0.8, 0.55, 0.2))
	_hud.pause_toggled.connect(_on_pause_toggled)
	_hud.run_toggled.connect(func(running: bool): _toggle_run())
	_hud.ability_pressed.connect(func(id: String):
		if id == "protect":
			_on_protect_pressed()
	)

	# Session timer (above HUD, separate)
	var timer_layer := CanvasLayer.new()
	timer_layer.layer = 10
	add_child(timer_layer)
	_session_timer_label = Label.new()
	_session_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_session_timer_label.offset_top = 12
	_session_timer_label.offset_left = -100
	_session_timer_label.offset_right = 100
	_session_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_session_timer_label.add_theme_font_size_override("font_size", 13)
	_session_timer_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.7))
	_session_timer_label.visible = false
	timer_layer.add_child(_session_timer_label)

	set_process_unhandled_key_input(true)

func _begin() -> void:
	_current_step = "fade_in"
	_player.set_move_enabled(false)
	if _visit_phase == 1:
		_fade_from(Color(0.15, 0.1, 0.03, 1), 3.0, _start_workspace, "workspace")
	else:
		# Phase 2: returning from Tag Day — session already in progress
		_monos.visible = true
		_portal_light.light_color = Color(0.9, 0.6, 0.3)
		_portal_light.light_energy = 3.0
		_fade_from(Color(0.15, 0.1, 0.03, 1), 3.0, _start_session_begins, "session_begins")

func _compute_speed() -> float:
	var spd := 10.0 if Input.is_key_pressed(KEY_F) else 1.0
	if _is_paused or _current_step in ["run_tutorial", "run_tutorial_resume"]:
		spd = 0.0
	return spd

func _on_process(delta: float, spd: float) -> void:
	if _hud:
		_hud.set_stat("sta", _stamina)
	_update_fades()

	# Stamina drain while running and moving
	if _is_running and _game_state.is_moving("peris"):
		_stamina = maxf(0, _stamina - 30.0 * delta * spd)
		if _stamina <= 0:
			_is_running = false
			_game_state.change_move_speed("peris", 3.0)

	# Session timer during active session phases
	if _current_step in ["session_begins", "attack", "sprint_to_terminal", "protect"]:
		_session_time += delta * spd
		_update_session_timer()

	# Sprint proximity check
	if _current_step == "sprint_to_terminal":
		var peris_pos := _game_state.get_position("peris")
		var dist := Vector2(peris_pos.x - PORTAL_POS.x, peris_pos.z - PORTAL_POS.z).length()
		if dist < 2.5:
			_scheduler.cancel_tag("sprint_redirect")
			_tutorial_prompt.hide_prompt()
			_hide_thought()
			_start_protect()

	# Portal glow animation (suppressed during tweens)
	if _portal_light and not _portal_tween_active:
		_portal_light.light_energy = 1.5 + sin(Time.get_ticks_msec() * 0.002) * 0.3

	# Attack light flash
	if _attack_particles and _attack_particles.visible:
		_attack_particles.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.015) * 2.0

	# Protect ability display from scheduler ticks
	if _protect_end_tick > 0 and _hud:
		var remaining := maxf(0, _protect_end_tick - _scheduler.get_current_tick())
		_hud.set_ability_state("protect", "active", remaining)
		if remaining <= 0:
			_protect_end_tick = 0.0

# --- Per-frame visual helpers ---

func _update_fades() -> void:
	if _current_step == "fade_in":
		_update_fade_in(2.5)
	elif _current_step == "transition_out":
		_update_fade_out(Color(0.03, 0.03, 0.04), 2.0)

# --- Input: run toggle ---

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_Z:
			_toggle_run()

func _toggle_pause() -> void:
	# During run tutorial resume, P acts as unpause -> advance
	if _current_step == "run_tutorial_resume":
		_resume_from_run_tutorial()
		return
	_is_paused = not _is_paused
	if _hud:
		_hud.set_paused(_is_paused)

func _on_pause_toggled(is_paused: bool) -> void:
	if _current_step == "run_tutorial_resume":
		_resume_from_run_tutorial()
		return
	_is_paused = is_paused

func _toggle_run() -> void:
	_is_running = not _is_running
	if _is_running and _stamina > 0:
		_game_state.change_move_speed("peris", 6.0)
		if not _has_sprinted:
			_has_sprinted = true
		# During run tutorial: player toggled run on — prompt to unpause
		if _current_step == "run_tutorial":
			_current_step = "run_tutorial_resume"
			_tutorial_prompt.show_prompt("[Space] — unpause")
	else:
		_is_running = false
		_game_state.change_move_speed("peris", 3.0)
	if _hud:
		_hud.set_run_mode(_is_running)

# --- Event-driven steps ---

func _start_workspace() -> void:
	_current_step = "workspace"
	_player.set_move_enabled(true)
	_show_thought(DialogueData.text("peris_sim.waiting.thought"))
	_scheduler.schedule_after(4.0, _start_monos_late, "monos_late")

func _start_monos_late() -> void:
	_current_step = "monos_late"
	_hide_thought()
	# Portal warming pulse instead of narration
	_portal_tween_active = true
	var t := create_tween()
	t.tween_property(_portal_light, "light_energy", 2.5, 1.0)
	t.tween_property(_portal_light, "light_energy", 1.5, 1.0)
	t.tween_callback(func(): _portal_tween_active = false)
	_scheduler.schedule_after(4.0, _start_monos_arrives, "monos_arrives")

func _start_monos_arrives() -> void:
	_current_step = "monos_arrives"
	_monos.visible = true
	_portal_light.light_color = Color(0.9, 0.6, 0.3)
	_portal_light.light_energy = 3.0
	DialogueData.say_to(_dialogue, "peris_sim.monos.late")
	DialogueData.say_to(_dialogue, "peris_sim.monos.start")
	DialogueData.say_to(_dialogue, "peris_sim.peris.week")
	DialogueData.say_to(_dialogue, "peris_sim.monos.week")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_transition_out, "transition_out"),
		CONNECT_ONE_SHOT
	)

func _start_session_begins() -> void:
	_current_step = "session_begins"
	_session_timer_label.visible = true
	# Portal energy bump to mark session start
	_portal_tween_active = true
	var t := create_tween()
	t.tween_property(_portal_light, "light_energy", 4.0, 0.4)
	t.tween_property(_portal_light, "light_energy", 3.0, 0.6)
	t.tween_callback(func(): _portal_tween_active = false)
	_scheduler.schedule_after(5.0, _start_attack, "attack")

func _start_attack() -> void:
	_current_step = "attack"
	_attack_particles.visible = true
	_attack_particles.light_color = Color(0.9, 0.15, 0.05)
	_attack_particles.light_energy = 5.0
	_portal_light.light_color = Color(0.8, 0.2, 0.1)
	_camera.shake(0.15, 6.0)
	DialogueData.say_to(_dialogue, "peris_sim.monos.hit")
	DialogueData.say_to(_dialogue, "peris_sim.system.overtime")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_run_tutorial, "run_tutorial"),
		CONNECT_ONE_SHOT
	)

func _start_run_tutorial() -> void:
	_current_step = "run_tutorial"
	_player.set_move_enabled(false)
	_is_paused = true
	if _hud:
		_hud.set_paused(true)
	_tutorial_prompt.show_prompt("[Z] — toggle Run")

func _resume_from_run_tutorial() -> void:
	_is_paused = false
	if _hud:
		_hud.set_paused(false)
	_tutorial_prompt.hide_prompt()
	_scheduler.schedule_after(0, _start_sprint_to_terminal, "sprint_to_terminal")

func _start_sprint_to_terminal() -> void:
	_current_step = "sprint_to_terminal"
	_show_thought(DialogueData.text("peris_sim.sprint.thought"))
	_tutorial_prompt.show_prompt("Hold [Z] to run")
	_player.set_move_enabled(true)
	# Soft redirect if player lingers far from the portal
	_scheduler.schedule_after(6.0, _check_sprint_redirect, "sprint_redirect")

func _check_sprint_redirect() -> void:
	if _current_step != "sprint_to_terminal":
		return
	var peris_pos := _game_state.get_position("peris")
	if peris_pos.distance_to(PORTAL_POS) > 5.0:
		_show_thought(DialogueData.text("peris_sim.care.thought"))

func _start_protect() -> void:
	_current_step = "protect"
	DialogueData.say_to(_dialogue, "peris_sim.protect_hint")

func _on_protect_pressed() -> void:
	if _current_step != "protect" or _has_protected:
		return
	_has_protected = true
	_protect_end_tick = _scheduler.get_current_tick() + 5.0
	if _hud:
		_hud.set_ability_state("protect", "active", 5.0)
		_hud.show_message("Peris: PROTECT! Absorbing damage from nearby allies.", 2.0)
	_attack_particles.light_energy = 0.5
	_portal_light.light_color = Color(0.9, 0.7, 0.3)
	_portal_light.light_energy = 4.0
	_stamina = maxf(0, _stamina - 15.0)
	_scheduler.schedule_after(0, _start_aftermath, "aftermath")

func _start_aftermath() -> void:
	_current_step = "aftermath"
	_attack_particles.visible = false
	_portal_light.light_color = Color(0.8, 0.6, 0.3)
	_portal_light.light_energy = 2.0
	DialogueData.say_to(_dialogue, "peris_sim.monos.thanks")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_efficiency_log, "efficiency_log"),
		CONNECT_ONE_SHOT
	)

func _start_efficiency_log() -> void:
	_current_step = "efficiency_log"
	_efficiency_score = 62.0
	DialogueData.say_to(_dialogue, "peris_sim.system.complete")
	DialogueData.say_to(_dialogue, "peris_sim.penalty_narration")
	_monos.fade_out(1.5)
	# Portal closure synced with Monos fade
	_portal_tween_active = true
	var t := create_tween()
	t.tween_property(_portal_light, "light_energy", 0.0, 1.5)
	t.parallel().tween_property(_portal_visual, "scale", Vector3(1.0, 0.0, 1.0), 1.5)
	t.tween_callback(func(): _portal_tween_active = false)
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_transition_out, "transition_out"),
		CONNECT_ONE_SHOT
	)

func _start_transition_out() -> void:
	_current_step = "transition_out"
	_player.set_move_enabled(false)
	_session_timer_label.visible = false
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(2.5, _complete, "complete")

func _complete() -> void:
	_current_step = "complete"
	if _visit_phase == 1:
		_visit_phase = 2
		get_tree().change_scene_to_file("res://scenes/tutorial/tag_day.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/tutorial/elevator.tscn")

# --- Session timer ---

func _update_session_timer() -> void:
	var overtime := _session_time > 20.0
	_session_timer_label.text = "SESSION  %s  %s" % [
		"%d:%02d" % [int(_session_time) / 60, int(_session_time) % 60],
		"OVERTIME" if overtime else ""
	]
	_session_timer_label.add_theme_color_override("font_color",
		Color(0.8, 0.2, 0.15) if overtime else Color(0.4, 0.5, 0.6, 0.7)
	)

# --- Key input ---

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_X and _current_step == "protect" and not _has_protected:
			_on_protect_pressed()
		elif kc == KEY_SPACE:
			_toggle_pause()

# --- Environment ---

func _build_environment() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	var floor_mesh := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(18, 0.1, 12)
	floor_mesh.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.14, 0.11, 0.08)
	fm.roughness = 0.5
	floor_mesh.material_override = fm
	floor_mesh.position = Vector3(4, -0.05, 0)
	env.add_child(floor_mesh)

	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(4, -0.01, 0)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(18, 0.02, 12)
	fc.shape = fs
	floor_body.add_child(fc)
	env.add_child(floor_body)

	var wc := Color(0.16, 0.12, 0.09)
	_add_wall(env, Vector3(4, 1.5, -6), Vector3(18, 3, 0.2), wc)
	_add_wall(env, Vector3(4, 1.5, 6), Vector3(18, 3, 0.2), wc)
	_add_wall(env, Vector3(-5, 1.5, 0), Vector3(0.2, 3, 12), wc)
	_add_wall(env, Vector3(13, 1.5, 0), Vector3(0.2, 3, 12), wc)

	_add_desk(env, DESK_POS)
	_add_seating(env, Vector3(4, 0, 0))

	for i in range(5):
		var plant := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.3
		sp.height = 0.6
		plant.mesh = sp
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.15, 0.35, 0.2)
		pm.emission_enabled = true
		pm.emission = Color(0.05, 0.15, 0.08)
		pm.emission_energy_multiplier = 0.3
		plant.material_override = pm
		plant.position = Vector3(-4.2, 0.3, -4 + i * 2.0)
		env.add_child(plant)

	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-40, -20, 0)
	dir_light.light_color = Color(0.95, 0.8, 0.6)
	dir_light.light_energy = 0.6
	dir_light.shadow_enabled = true
	env.add_child(dir_light)

	var warm_fill := OmniLight3D.new()
	warm_fill.position = Vector3(2, 2.5, 0)
	warm_fill.light_color = Color(0.9, 0.7, 0.45)
	warm_fill.light_energy = 1.8
	warm_fill.omni_range = 8.0
	env.add_child(warm_fill)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.04, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.3, 0.22)
	e.ambient_light_energy = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.2
	we.environment = e
	env.add_child(we)

func _add_desk(parent: Node3D, pos: Vector3) -> void:
	var desk := MeshInstance3D.new()
	var db := BoxMesh.new()
	db.size = Vector3(1.6, 0.06, 0.9)
	desk.mesh = db
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.2, 0.15, 0.1)
	dm.roughness = 0.4
	desk.material_override = dm
	desk.position = pos + Vector3(0, 0.72, 0)
	parent.add_child(desk)

func _add_seating(parent: Node3D, pos: Vector3) -> void:
	for z in [-1.5, 1.5]:
		var seat := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.8, 0.4, 0.8)
		seat.mesh = sb
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.25, 0.18, 0.12)
		sm.roughness = 0.8
		seat.material_override = sm
		seat.position = pos + Vector3(0, 0.2, z)
		parent.add_child(seat)

# --- Portal ---

func _build_portal() -> void:
	var portal_frame := MeshInstance3D.new()
	var arch := CylinderMesh.new()
	arch.top_radius = 0.08
	arch.bottom_radius = 0.08
	arch.height = 2.5
	portal_frame.mesh = arch
	var pfm := StandardMaterial3D.new()
	pfm.albedo_color = Color(0.2, 0.15, 0.1)
	portal_frame.material_override = pfm
	portal_frame.position = PORTAL_POS + Vector3(-0.5, 1.25, 0)
	add_child(portal_frame)

	var portal_frame2 := portal_frame.duplicate()
	portal_frame2.position = PORTAL_POS + Vector3(0.5, 1.25, 0)
	add_child(portal_frame2)

	_portal_visual = MeshInstance3D.new()
	var pv := BoxMesh.new()
	pv.size = Vector3(0.9, 2.0, 0.04)
	_portal_visual.mesh = pv
	var pvm := StandardMaterial3D.new()
	pvm.albedo_color = Color(0.8, 0.5, 0.2, 0.25)
	pvm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pvm.emission_enabled = true
	pvm.emission = Color(0.6, 0.35, 0.15)
	pvm.emission_energy_multiplier = 1.2
	pvm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal_visual.material_override = pvm
	_portal_visual.position = PORTAL_POS + Vector3(0, 1.0, 0)
	add_child(_portal_visual)

	_portal_light = OmniLight3D.new()
	_portal_light.position = PORTAL_POS + Vector3(0, 1.5, 0)
	_portal_light.light_color = Color(0.8, 0.5, 0.25)
	_portal_light.light_energy = 1.5
	_portal_light.omni_range = 5.0
	add_child(_portal_light)

	_attack_particles = OmniLight3D.new()
	_attack_particles.position = MONOS_POS + Vector3(0, 1.0, 0)
	_attack_particles.light_color = Color(0.9, 0.15, 0.05)
	_attack_particles.light_energy = 0
	_attack_particles.omni_range = 4.0
	_attack_particles.visible = false
	add_child(_attack_particles)

	var lbl := Label3D.new()
	lbl.text = "FEED TERMINAL"
	lbl.font_size = 32
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.7, 0.5, 0.3, 0.6)
	lbl.position = PORTAL_POS + Vector3(0, 2.6, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)

# --- Decorations ---

func _build_decorations() -> void:
	var env_node: Node = find_child("Environment", false, false)
	if not env_node:
		return

	# Vessel-wrap wall motifs — curved ridges on walls representing the
	# pericyte's characteristic wrapping pattern around blood vessels
	var wrap_mat := StandardMaterial3D.new()
	wrap_mat.albedo_color = Color(0.22, 0.16, 0.11)
	wrap_mat.roughness = 0.7
	for i in range(6):
		var wrap := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 2.2
		wrap.mesh = cm
		wrap.material_override = wrap_mat
		wrap.position = Vector3(-4.85, 0.4 + i * 0.45, -3.0 + i * 1.0)
		wrap.rotation.z = PI / 2.0
		wrap.rotation.y = 0.3
		env_node.add_child(wrap)

	# Warm pendant lights — hanging from the ceiling, casting pools of amber
	var pendant_mat := StandardMaterial3D.new()
	pendant_mat.albedo_color = Color(0.7, 0.5, 0.25)
	pendant_mat.emission_enabled = true
	pendant_mat.emission = Color(0.5, 0.35, 0.15)
	pendant_mat.emission_energy_multiplier = 1.5
	pendant_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for pos in [Vector3(-2, 0, 0), Vector3(3, 0, 2), Vector3(3, 0, -2)]:
		var shade := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.12
		sp.height = 0.18
		shade.mesh = sp
		shade.material_override = pendant_mat
		shade.position = pos + Vector3(0, 2.6, 0)
		env_node.add_child(shade)
		var cord := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.01
		cc.bottom_radius = 0.01
		cc.height = 0.4
		cord.mesh = cc
		cord.material_override = wrap_mat
		cord.position = pos + Vector3(0, 2.8, 0)
		env_node.add_child(cord)

	# Floor rug — warm fabric rectangle in the seating area
	var rug := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(3.0, 0.01, 4.5)
	rug.mesh = rb
	var rug_mat := StandardMaterial3D.new()
	rug_mat.albedo_color = Color(0.18, 0.12, 0.08)
	rug_mat.roughness = 0.9
	rug.material_override = rug_mat
	rug.position = Vector3(4, 0.005, 0)
	env_node.add_child(rug)

	# Side table between the two seats
	var table := MeshInstance3D.new()
	var tb := CylinderMesh.new()
	tb.top_radius = 0.3
	tb.bottom_radius = 0.2
	tb.height = 0.5
	table.mesh = tb
	var table_mat := StandardMaterial3D.new()
	table_mat.albedo_color = Color(0.2, 0.15, 0.1)
	table_mat.roughness = 0.4
	table.material_override = table_mat
	table.position = Vector3(4, 0.25, 0)
	env_node.add_child(table)

	# Wall hangings — warm-toned tapestry panels on the back wall
	var tapestry_colors := [
		Color(0.25, 0.15, 0.08),
		Color(0.2, 0.12, 0.15),
		Color(0.15, 0.18, 0.1),
	]
	for i in range(3):
		var tap := MeshInstance3D.new()
		var tapb := BoxMesh.new()
		tapb.size = Vector3(1.5, 1.8, 0.02)
		tap.mesh = tapb
		var tm := StandardMaterial3D.new()
		tm.albedo_color = tapestry_colors[i]
		tm.roughness = 0.85
		tap.material_override = tm
		tap.position = Vector3(-1.5 + i * 3.5, 1.6, -5.85)
		env_node.add_child(tap)

	# Small ceramic vessels on the desk
	var vessel_mat := StandardMaterial3D.new()
	vessel_mat.albedo_color = Color(0.3, 0.2, 0.15)
	vessel_mat.roughness = 0.3
	for offset in [Vector3(-0.4, 0.82, 0.15), Vector3(0.3, 0.82, -0.1)]:
		var vessel := MeshInstance3D.new()
		var vc := CylinderMesh.new()
		vc.top_radius = 0.06
		vc.bottom_radius = 0.08
		vc.height = 0.12
		vessel.mesh = vc
		vessel.material_override = vessel_mat
		vessel.position = DESK_POS + offset
		env_node.add_child(vessel)

	# Bookshelf along the left wall
	var shelf_mat := StandardMaterial3D.new()
	shelf_mat.albedo_color = Color(0.18, 0.13, 0.09)
	var shelf := MeshInstance3D.new()
	var shb := BoxMesh.new()
	shb.size = Vector3(0.4, 1.6, 2.0)
	shelf.mesh = shb
	shelf.material_override = shelf_mat
	shelf.position = Vector3(-4.65, 0.8, 3.0)
	env_node.add_child(shelf)
	# Books as colored strips on the shelf
	var book_colors := [Color(0.25, 0.12, 0.1), Color(0.1, 0.15, 0.2), Color(0.2, 0.18, 0.1), Color(0.12, 0.2, 0.15)]
	for i in range(4):
		var book := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.35, 0.22, 0.15)
		book.mesh = bb
		var bm := StandardMaterial3D.new()
		bm.albedo_color = book_colors[i]
		book.material_override = bm
		book.position = Vector3(-4.65, 0.3 + i * 0.35, 2.4 + i * 0.3)
		env_node.add_child(book)
