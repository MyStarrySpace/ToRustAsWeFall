@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

## Peris's simulation tutorial. Teaches walk/run, stamina, Protect ability.
## Warm, social workspace. Session with Monos. Attack through the portal.
## The first ability the player uses in the entire game is an act of care.
##
## Event-driven: uses EventScheduler + GameState interpolation.
## Each step is a function that does its work and schedules the next event.

@export_range(1, 2) var start_phase := 0
static var _visit_phase := 1

var _has_sprinted := false
var _has_protected := false
var _protect_queued := false
var _protect_end_tick := 0.0

var _monos
var _portal_visual: MeshInstance3D
var _portal_light: OmniLight3D
var _attack_particles: OmniLight3D
var _portal_tween_active := false
var _hud  # GameHUD

# Exploration beat (phase 1, pre-Monos-arrival)
var _explore_logbook_gate  # Interactable at the logbook
const EXPLORE_MIN_TIME := 10.0  # scheduler seconds before the logbook gate unlocks
var _explore_gate_unlocked := false
var _explore_gate_fired := false

# Stats live in GameState. Stamina drain and run speed are authoritative there;
# this scene only talks to _game_state through set_running / adjust_stat.
var _is_paused := false
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
	_register_gs_character("peris", _player, GameState.WALK_SPEED, {
		"stamina": GameState.STAMINA_MAX,
	})
	_register_gs_character("monos", _monos, _monos.move_speed)

func _setup_ui() -> void:
	_thought_label.add_theme_color_override("font_color", Color(0.75, 0.6, 0.45))

	# Game HUD — stamina bar, run toggle, protect ability
	_hud = CanvasLayer.new()
	_hud.name = "GameHUD"
	_hud.set_script(preload("res://scripts/game/game_hud.gd"))
	add_child(_hud)
	_hud.add_stat_bar("sta", Color(0.3, 0.5, 0.7), GameState.STAMINA_MAX, GameState.STAMINA_MAX)
	_hud.show_pause_toggle(false)
	_hud.show_run_toggle(false)
	_hud.add_ability("protect", "PROTECT", "X", Color(0.8, 0.55, 0.2))
	_hud.pause_toggled.connect(_on_pause_toggled)
	# Tutorial guards the run press to specific steps; let _toggle_run stay
	# the hook that decides whether the flip is allowed, and flip GameState
	# ourselves rather than letting the HUD auto-delegate.
	_hud.run_toggled.connect(func(running: bool): _toggle_run())
	_hud.ability_pressed.connect(func(id: String):
		if id == "protect":
			_on_protect_pressed()
	)
	# Tutorial gates the run button per-step, so keep signal-based flow.
	_hud.bind_game_state(_game_state, "peris", false)

	set_process_unhandled_key_input(true)

func _begin() -> void:
	if start_phase > 0:
		_visit_phase = start_phase
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
	if _is_paused or _current_step in ["alert_monos", "protect_prompt", "run_prompt", "click_monos", "confirm_protect"]:
		spd = 0.0
	return spd

func _on_process(delta: float, spd: float) -> void:
	_update_fades()

	# Stat bars and run visuals auto-update from GameState signals via
	# GameHUD.bind_game_state, and stamina drain happens in GameState on the
	# scheduler tick. Nothing to drain here.

	# Queued protect handled by GameState.queue_ability (predictive)

	# Portal glow animation (suppressed during tweens)
	if _portal_light and not _portal_tween_active:
		_portal_light.light_energy = 1.5 + sin(Time.get_ticks_msec() * 0.002) * 0.3  # @rendering_only — portal glow

	# Attack light flash
	if _attack_particles and _attack_particles.visible:
		_attack_particles.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.015) * 2.0  # @rendering_only — attack flash

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

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _current_step == "click_monos":
		var hit := _raycast_ground_from(mb.position)
		if hit != Vector3.INF:
			var dist_to_monos := Vector2(hit.x - MONOS_POS.x, hit.z - MONOS_POS.z).length()
			if dist_to_monos < 2.5:
				get_viewport().set_input_as_handled()
				_tutorial_prompt.hide_prompt()
				_start_confirm_protect()
			else:
				_show_correction("peris_sim.correct.target_monos")

func _raycast_ground_from(screen_pos: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return Vector3.INF
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var space := get_world_3d().direct_space_state
	if not space:
		return Vector3.INF
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	query.collision_mask = 1
	var result := space.intersect_ray(query)
	if not result.is_empty():
		return result.position
	return Vector3.INF

func _toggle_pause() -> void:
	# Only allow unpause at the confirm_protect step
	if _current_step == "confirm_protect":
		_start_executing()
		return
	# Correction: trying to unpause during the ordered tutorial
	if _current_step in ["alert_monos", "protect_prompt", "run_prompt", "click_monos"]:
		_show_correction("peris_sim.correct.not_yet")
		return
	_is_paused = not _is_paused
	if _hud:
		_hud.set_paused(_is_paused)

func _on_pause_toggled(is_paused: bool) -> void:
	if _current_step == "confirm_protect" and not is_paused:
		_start_executing()
		return
	if _current_step in ["alert_monos", "protect_prompt", "run_prompt", "click_monos"]:
		_show_correction("peris_sim.correct.not_yet")
		return
	_is_paused = is_paused

func _toggle_run() -> void:
	if _game_state == null:
		return
	# During ordered tutorial: only allowed at run_prompt step
	if _current_step == "run_prompt":
		_has_sprinted = true
		_game_state.set_running("peris", true)
		_player.set_running(true)
		_start_click_monos()
		return
	if _current_step == "protect_prompt":
		_has_sprinted = true
		_game_state.set_running("peris", true)
		_player.set_running(true)
		_show_thought(DialogueData.text("peris_sim.protect_remind"))
		return
	if _current_step in ["alert_monos", "click_monos", "confirm_protect"]:
		return
	# Normal run toggle outside tutorial
	_game_state.toggle_running("peris")
	var now_running := _game_state.is_running("peris")
	if now_running:
		_has_sprinted = true
	_player.set_running(now_running)

func _show_correction(key: String) -> void:
	_show_thought(DialogueData.text(key))

# --- Event-driven steps ---

func _start_workspace() -> void:
	_current_step = "workspace"
	_player.set_move_enabled(true)
	# Phase 1: Peris narrates her no-show reluctance and takes a lap around
	# the room while the player explores. Monos connects when Peris opens
	# his file in the logbook (the gate). The old "Monos should be connecting
	# soon" thought is replaced by the new opening.line from the expansion.
	_show_thought(DialogueData.text("peris.sim_expand.opening.line"))
	_build_exploration_objects()
	_explore_gate_unlocked = false
	_explore_gate_fired = false
	DialogueData.say_to(_dialogue, "peris.sim_expand.narration.enter")
	_scheduler.schedule_after(EXPLORE_MIN_TIME, _unlock_exploration_gate, "explore_gate_unlock")

func _unlock_exploration_gate() -> void:
	_explore_gate_unlocked = true
	if _explore_logbook_gate and _explore_logbook_gate.has_method("show_tutorial_label"):
		_explore_logbook_gate.show_tutorial_label()

func _on_exploration_gate_interacted() -> void:
	if not _explore_gate_unlocked or _explore_gate_fired:
		return
	_explore_gate_fired = true
	DialogueData.say_to(_dialogue, "peris.sim_expand.logbook.interact")
	_hide_thought()
	_start_monos_arrives()

func _start_monos_arrives() -> void:
	_current_step = "monos_arrives"
	_monos.visible = true
	_portal_light.light_color = Color(0.9, 0.6, 0.3)
	_portal_light.light_energy = 3.0
	_dialogue_chain([
		"peris_sim.monos.late",
		"peris_sim.monos.followed",
		"peris_sim.monos.stress",
		"peris_sim.peris.safe",
		"peris_sim.monos.breathe",
		"peris_sim.monos.ok",
		"peris_sim.peris.week",
		"peris_sim.monos.week",
	], func():
		_scheduler.schedule_after(3.0, _start_transition_out, "transition_out")
	)

func _start_session_begins() -> void:
	_current_step = "session_begins"
	_portal_tween_active = true
	var t := create_tween()
	t.tween_property(_portal_light, "light_energy", 4.0, 0.4)
	t.tween_property(_portal_light, "light_energy", 3.0, 0.6)
	t.tween_callback(func(): _portal_tween_active = false)
	_scheduler.schedule_after(2.0, _start_attack, "attack")

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
		func(): _scheduler.schedule_after(0, _start_alert_monos, "alert_monos"),
		CONNECT_ONE_SHOT
	)

# --- Strict ordered tutorial sequence ---

func _start_alert_monos() -> void:
	_enter_step("alert_monos")
	# White "!" over Monos
	var alert := Label3D.new()
	alert.name = "AlertMark"
	alert.text = "!"
	alert.font_size = 72
	alert.pixel_size = 0.012
	alert.modulate = Color(1, 1, 1, 0.95)
	alert.outline_modulate = Color(0, 0, 0, 0.6)
	alert.outline_size = 5
	alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alert.position = Vector3(0, 1.8, 0)
	_monos.add_child(alert)
	# Auto-pause
	_is_paused = true
	_player.set_move_enabled(false)
	if _hud:
		_hud.set_paused(true)
	_start_protect_prompt()

func _start_protect_prompt() -> void:
	_enter_step("protect_prompt")
	DialogueData.say_to(_dialogue, "peris_sim.peris.protect_him")
	_dialogue.dialogue_finished.connect(func():
		_tutorial_prompt.show_prompt("[X] — queue Protect")
	, CONNECT_ONE_SHOT)

func _start_run_prompt() -> void:
	_enter_step("run_prompt")
	_tutorial_prompt.show_prompt("[Z] — toggle Run")
	if _hud:
		_hud.show_run_toggle(true)

func _start_click_monos() -> void:
	_enter_step("click_monos")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("[Click] Monos — set Protect target")

func _start_confirm_protect() -> void:
	_enter_step("confirm_protect")
	_protect_queued = true
	# Shield marker over Monos
	var shield := Label3D.new()
	shield.name = "ShieldMark"
	shield.text = "SHIELD"
	shield.font_size = 36
	shield.pixel_size = 0.01
	shield.modulate = Color(0.8, 0.6, 0.2, 0.9)
	shield.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shield.position = Vector3(0, 2.2, 0)
	_monos.add_child(shield)
	if _hud:
		_hud.set_ability_state("protect", "queued")
	_tutorial_prompt.show_prompt("[Space] — unpause")

func _start_executing() -> void:
	_current_step = "executing"
	_is_paused = false
	if _hud:
		_hud.set_paused(false)
	_tutorial_prompt.hide_prompt()
	_hide_thought()
	# Queue protect on Monos — auto-moves Peris into range and fires
	if _protect_queued:
		_protect_queued = false
		_game_state.queue_ability("peris", "protect", PORTAL_POS, 2.5, _fire_queued_protect)

func _on_protect_pressed() -> void:
	if _has_protected:
		return
	# Ordered tutorial: X only valid at protect_prompt step
	if _current_step == "protect_prompt":
		_tutorial_prompt.hide_prompt()
		if _hud:
			_hud.set_ability_state("protect", "queued")
		_start_run_prompt()
		return
	if _current_step in ["alert_monos", "run_prompt", "click_monos", "confirm_protect"]:
		return

func _fire_queued_protect() -> void:
	_has_protected = true
	_protect_end_tick = _scheduler.get_current_tick() + 5.0
	if _hud:
		_hud.set_ability_state("protect", "active", 5.0)
		_hud.show_message("Peris: PROTECT! Absorbing damage from nearby allies.", 2.0)
	_attack_particles.light_energy = 0.5
	_portal_light.light_color = Color(0.9, 0.7, 0.3)
	_portal_light.light_energy = 4.0
	_game_state.adjust_stat("peris", "stamina", -15.0)
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
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(2.5, _complete, "complete")

func _complete() -> void:
	_current_step = "complete"
	if _visit_phase == 1:
		_visit_phase = 2
		_change_scene_or_record("res://scenes/tutorial/tag_day.tscn")
	else:
		_change_scene_or_record("res://scenes/tutorial/elevator.tscn")

# --- Key input ---

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_X:
			_on_protect_pressed()
		elif kc == KEY_Z:
			_toggle_run()
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

# --- Exploration objects (phase 1, pre-Monos-arrival) ---

func _build_exploration_objects() -> void:
	if Engine.is_editor_hint():
		return
	var env: Node3D = self
	_build_peris_plants(env)
	_build_peris_painting(env)
	_build_peris_wellness_feed(env)
	_build_peris_strike_warning(env)
	_build_peris_session_notes(env)
	_build_peris_logbook_gate(env)

func _make_peris_plant(parent: Node3D, pos: Vector3, height: float, base_color: Color, bloom: bool) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var pot := MeshInstance3D.new()
	var pb := CylinderMesh.new()
	pb.top_radius = 0.14
	pb.bottom_radius = 0.1
	pb.height = 0.2
	pot.mesh = pb
	var pot_mat := StandardMaterial3D.new()
	pot_mat.albedo_color = Color(0.3, 0.22, 0.18)
	pot_mat.roughness = 0.8
	pot.material_override = pot_mat
	pot.position = Vector3(0, 0.1, 0)
	root.add_child(pot)
	var foliage := MeshInstance3D.new()
	var fb := SphereMesh.new()
	fb.radius = 0.2
	fb.height = height
	foliage.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = base_color
	fm.roughness = 0.7
	foliage.material_override = fm
	foliage.position = Vector3(0, 0.2 + height * 0.5, 0)
	root.add_child(foliage)
	if bloom:
		var bloom_mesh := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		bloom_mesh.mesh = sm
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(1.0, 0.85, 0.7)
		bm.emission_enabled = true
		bm.emission = Color(0.8, 0.6, 0.5)
		bm.emission_energy_multiplier = 0.3
		bloom_mesh.material_override = bm
		bloom_mesh.position = Vector3(0.12, 0.2 + height * 0.8, 0.05)
		root.add_child(bloom_mesh)
	return root

func _build_peris_plants(parent: Node3D) -> void:
	# Placeholder plant array — positions chosen to spread across the workspace
	# so the player navigates between them. Species is visual only; the
	# dialogue carries the meaning. Specs per simulation_tutorial_expansions.md.
	var plants := [
		[Vector3(-4.4, 0, -1.4), 0.6, Color(0.2, 0.45, 0.22), false,
			"", "peris.sim_expand.plant_1.line"],
		[Vector3(-0.7, 0, 4.7), 0.3, Color(0.35, 0.45, 0.22), false,
			"", "peris.sim_expand.plant_2.line"],
		[Vector3(2.6, 0.8, 4.4), 0.18, Color(0.3, 0.5, 0.3), true,
			"", "peris.sim_expand.plant_3.line"],
		[Vector3(6.0, 0, 4.6), 0.25, Color(0.28, 0.4, 0.32), false,
			"", "peris.sim_expand.plant_4.line"],
		[Vector3(10.0, 0, 4.2), 0.45, Color(0.22, 0.48, 0.28), false,
			"", "peris.sim_expand.plant_5.line"],
		[Vector3(-0.9, 0, 1.4), 0.7, Color(0.18, 0.35, 0.22), false,
			"", "peris.sim_expand.plant_6.line"],
		[Vector3(3.0, 0, 1.2), 0.65, Color(0.25, 0.5, 0.3), false,
			"", "peris.sim_expand.plant_7.line"],
		[Vector3(7.0, 0, 1.0), 0.4, Color(0.3, 0.42, 0.22), false,
			"", "peris.sim_expand.plant_8.line"],
		[Vector3(11.0, 0, 0.0), 0.55, Color(0.2, 0.4, 0.22), false,
			"", "peris.sim_expand.plant_9.line"],
	]
	for i in range(plants.size()):
		var p: Array = plants[i]
		var pos: Vector3 = p[0]
		var height: float = p[1]
		var color: Color = p[2]
		var bloom: bool = p[3]
		var look_key: String = p[4]
		var line_key: String = p[5]
		var plant_node := _make_peris_plant(parent, pos, height, color, bloom)
		plant_node.name = "Plant%d" % (i + 1)
		var zone_pos := Vector3(pos.x, 0, pos.z)
		_make_exploration_zone(parent, zone_pos,
			"Plant%dZone" % (i + 1),
			look_key, line_key,
			1.0, 0.6)

func _build_peris_painting(parent: Node3D) -> void:
	var pos := Vector3(3.2, 2.2, -5.82)
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(1.2, 0.85, 0.06)
	frame.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.14, 0.1)
	frame.material_override = fm
	frame.position = pos
	parent.add_child(frame)
	var canvas := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(1.1, 0.75, 0.05)
	canvas.mesh = cb
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.55, 0.38, 0.45)
	cm.roughness = 0.6
	canvas.material_override = cm
	canvas.position = pos + Vector3(0, 0, 0.02)
	parent.add_child(canvas)
	_make_exploration_zone(parent, Vector3(3.2, 0, -4.8),
		"PaintingZone",
		"",
		"peris.sim_expand.painting.line",
		1.3, 0.6)

func _build_peris_wellness_feed(parent: Node3D) -> void:
	var pos := Vector3(-4.65, 1.4, -4.8)
	var screen := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.8, 0.5, 0.04)
	screen.mesh = sb
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.35, 0.4, 0.5, 0.85)
	sm.emission_enabled = true
	sm.emission = Color(0.3, 0.4, 0.55)
	sm.emission_energy_multiplier = 0.9
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override = sm
	screen.position = pos
	parent.add_child(screen)
	_make_exploration_zone(parent, Vector3(-4.2, 0, -4.8),
		"WellnessZone",
		"",
		"peris.sim_expand.wellness.line",
		1.0, 0.6)

func _build_peris_strike_warning(parent: Node3D) -> void:
	# Pinned institutional notification. The focused interaction plays the
	# document (ui-style) plus Peris's line, no modal.
	var pos := Vector3(-0.9, 1.8, -5.82)
	var icon := MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(0.4, 0.55, 0.04)
	icon.mesh = ib
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(0.85, 0.8, 0.68)
	im.emission_enabled = true
	im.emission = Color(0.3, 0.25, 0.18)
	im.emission_energy_multiplier = 0.2
	icon.material_override = im
	icon.position = pos
	parent.add_child(icon)
	var strip := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.4, 0.08, 0.045)
	strip.mesh = rb
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.5, 0.2, 0.2)
	strip.material_override = rm
	strip.position = pos + Vector3(0, 0.24, 0.001)
	parent.add_child(strip)
	var area := _make_exploration_zone(parent, Vector3(-0.9, 0, -4.7),
		"StrikeWarningZone",
		"",
		"",
		1.0, 0.8)
	area.connect("interacted", func():
		_play_focused_dialogue_keys([
			"peris.sim_expand.strike_warning.notification",
			"peris.sim_expand.strike_warning.line",
		], area)
	)

func _build_peris_session_notes(parent: Node3D) -> void:
	var pos := Vector3(1.1, 0.85, -1.7)
	var tablet := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.25, 0.02, 0.35)
	tablet.mesh = tb
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.15, 0.18, 0.22)
	tm.emission_enabled = true
	tm.emission = Color(0.3, 0.4, 0.5)
	tm.emission_energy_multiplier = 0.6
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tablet.material_override = tm
	tablet.position = pos
	parent.add_child(tablet)
	_make_exploration_zone(parent, Vector3(1.1, 0, -1.7),
		"NotesZone",
		"",
		"peris.sim_expand.notes.line",
		0.9, 0.6)

func _build_peris_logbook_gate(parent: Node3D) -> void:
	# Logbook sits across the room from the portal. The player must traverse
	# the workspace to reach this gate.
	var pos := Vector3(-4.45, 0.9, 4.4)
	var console := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.5, 1.0, 0.4)
	console.mesh = cb
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.2, 0.22, 0.25)
	console.material_override = cm
	console.position = pos
	parent.add_child(console)
	var screen := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.45, 0.45, 0.04)
	screen.mesh = sb
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.75, 0.55, 0.35)
	sm.emission_enabled = true
	sm.emission = Color(0.65, 0.45, 0.25)
	sm.emission_energy_multiplier = 0.8
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override = sm
	screen.position = pos + Vector3(0, 0.1, 0.22)
	parent.add_child(screen)
	var gate := _create_interactable(parent, Vector3(pos.x + 0.7, 0, pos.z), "LogbookGate", 2.0, 0.8, "Continue", false)
	gate.connect("interacted", _on_exploration_gate_interacted)
	_explore_logbook_gate = gate
