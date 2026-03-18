extends Node3D

## Peris's simulation tutorial. Teaches walk/run, stamina, Protect ability.
## Warm, social workspace. Session with Monos. Attack through the portal.
## The first ability the player uses in the entire game is an act of care.

enum Phase {
	FADE_IN,            # Warm amber fades in from Tag Day's blue clearance
	WORKSPACE,          # Peris in her social work feed, waiting for client
	MONOS_LATE,         # Monos is late — Peris has a moment
	MONOS_ARRIVES,      # Monos connects through the portal, flustered
	SESSION_BEGINS,     # Session interaction — completion markers tick
	ATTACK,             # Something strikes through the portal — Monos is hurt
	SPRINT_TO_TERMINAL, # Player must RUN to get within casting range
	PROTECT,            # Player activates Protect ability through the portal
	AFTERMATH,          # Monos is shaken but stable. Session timer penalty.
	EFFICIENCY_LOG,     # System logs the penalty. Peris's score drops.
	TRANSITION_OUT,     # Fade out — leads to leaving the facility
	COMPLETE,
}

var _phase: Phase = Phase.FADE_IN
var _phase_timer := 0.0
var _phase_started := false
var _has_sprinted := false
var _has_protected := false

var _player
var _camera
var _dialogue
var _tutorial_prompt
var _monos
var _portal_visual: MeshInstance3D
var _portal_light: OmniLight3D
var _attack_particles: OmniLight3D  # Flashing red light simulating the attack
var _session_timer_label: Label
var _stamina_bar: ProgressBar
var _stamina_label: Label
var _fade_rect: ColorRect
var _thought_label: Label
var _protect_button: Button

# Stats
var _stamina := 100.0
const STAMINA_MAX := 100.0
var _is_running := false
var _session_time := 0.0
var _efficiency_score := 100.0

# Positions
const DESK_POS := Vector3(0, 0, 0)
const PORTAL_POS := Vector3(7, 0, 0)       # The feed terminal / portal
const MONOS_POS := Vector3(8.5, 0, 0)      # Monos appears on the other side
const PERIS_START := Vector3(0, 0.5, -1)   # At her desk, away from portal

func _ready() -> void:
	_build_environment()
	_build_characters()
	_build_portal()
	_build_ui()
	_set_phase(Phase.FADE_IN)

func _process(delta: float) -> void:
	_phase_timer += delta
	_update_stamina_display()

	# Running drains stamina
	if _is_running and _player.is_moving():
		_stamina = maxf(0, _stamina - 30.0 * delta)
		if _stamina <= 0:
			_is_running = false
			_player.move_speed = 3.0

	# Session timer ticks during active session phases
	if _phase >= Phase.SESSION_BEGINS and _phase <= Phase.PROTECT:
		_session_time += delta
		_update_session_timer()

	match _phase:
		Phase.FADE_IN:
			_process_fade_in(delta)
		Phase.WORKSPACE:
			_process_workspace(delta)
		Phase.MONOS_LATE:
			_process_monos_late(delta)
		Phase.MONOS_ARRIVES:
			_process_monos_arrives(delta)
		Phase.SESSION_BEGINS:
			_process_session_begins(delta)
		Phase.ATTACK:
			_process_attack(delta)
		Phase.SPRINT_TO_TERMINAL:
			_process_sprint(delta)
		Phase.PROTECT:
			_process_protect(delta)
		Phase.AFTERMATH:
			_process_aftermath(delta)
		Phase.EFFICIENCY_LOG:
			_process_efficiency_log(delta)
		Phase.TRANSITION_OUT:
			_process_transition_out(delta)

	# Portal glow animation
	if _portal_light:
		_portal_light.light_energy = 1.5 + sin(Time.get_ticks_msec() * 0.002) * 0.3

func _set_phase(phase: Phase) -> void:
	_phase = phase
	_phase_timer = 0.0
	_phase_started = false

func _enter_phase() -> void:
	_phase_started = true

# --- Input: run toggle ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_SHIFT:
			_toggle_run()

func _toggle_run() -> void:
	_is_running = not _is_running
	if _is_running and _stamina > 0:
		_player.move_speed = 6.0
		if not _has_sprinted:
			_has_sprinted = true
	else:
		_is_running = false
		_player.move_speed = 3.0

# --- Phases ---

func _process_fade_in(delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		# Fade from warm amber (Tag Day clearance dissolve)
		_fade_rect.color = Color(0.15, 0.1, 0.03, 1)
		_player.set_move_enabled(false)

	var alpha := 1.0 - clampf(_phase_timer / 2.5, 0.0, 1.0)
	_fade_rect.color.a = alpha

	if _phase_timer > 3.0:
		_set_phase(Phase.WORKSPACE)

func _process_workspace(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		_player.set_move_enabled(true)
		_show_thought(DialogueData.text("peris_sim.waiting.thought"))

	if _phase_timer > 4.0:
		_set_phase(Phase.MONOS_LATE)

func _process_monos_late(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		_hide_thought()
		DialogueData.say_to(_dialogue, "peris_sim.feed_hum")

	if _phase_timer > 4.0:
		_set_phase(Phase.MONOS_ARRIVES)

func _process_monos_arrives(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		# Portal activates — Monos appears
		_monos.visible = true
		_portal_light.light_color = Color(0.9, 0.6, 0.3)
		_portal_light.light_energy = 3.0

		DialogueData.say_to(_dialogue, "peris_sim.monos.late")
		DialogueData.say_to(_dialogue, "peris_sim.monos.start")
		_dialogue.dialogue_finished.connect(
			func(): _set_phase(Phase.SESSION_BEGINS),
			CONNECT_ONE_SHOT
		)

func _process_session_begins(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		_session_timer_label.visible = true
		DialogueData.say_to(_dialogue, "peris_sim.session_begins")

	if _phase_timer > 5.0:
		_set_phase(Phase.ATTACK)

func _process_attack(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		# Something strikes through the portal
		_attack_particles.visible = true
		_attack_particles.light_color = Color(0.9, 0.15, 0.05)
		_attack_particles.light_energy = 5.0
		_portal_light.light_color = Color(0.8, 0.2, 0.1)

		DialogueData.say_to(_dialogue, "peris_sim.monos.hit")
		DialogueData.say_to(_dialogue, "peris_sim.attack_narration")
		DialogueData.say_to(_dialogue, "peris_sim.system.overtime")
		_dialogue.dialogue_finished.connect(
			func(): _set_phase(Phase.SPRINT_TO_TERMINAL),
			CONNECT_ONE_SHOT
		)

	# Flashing attack light
	if _attack_particles.visible:
		_attack_particles.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.015) * 2.0

func _process_sprint(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		# Peris needs to reach the portal terminal to cast Protect
		# She's at her desk, far from it
		_show_thought(DialogueData.text("peris_sim.sprint.thought"))
		# Subtle Shift key hint
		_tutorial_prompt.show_prompt("Hold [Shift] to run")
		_player.set_move_enabled(true)

	# Check if player is close enough to portal
	var dist_to_portal: float = _player.global_position.distance_to(PORTAL_POS)
	if dist_to_portal < 2.5:
		_tutorial_prompt.hide_prompt()
		_hide_thought()
		_set_phase(Phase.PROTECT)

	# Soft redirect if player walks away
	if _phase_timer > 6.0 and dist_to_portal > 5.0:
		if _phase_timer < 6.5:
			_show_thought(DialogueData.text("peris_sim.care.thought"))

func _process_protect(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		# Show the Protect ability button
		_protect_button.visible = true
		DialogueData.say_to(_dialogue, "peris_sim.protect_hint")

	# Wait for player to press Protect
	if _has_protected:
		_protect_button.visible = false
		# Shield effect
		_attack_particles.light_energy = 0.5
		_portal_light.light_color = Color(0.9, 0.7, 0.3)
		_portal_light.light_energy = 4.0
		_stamina = maxf(0, _stamina - 15.0)
		_set_phase(Phase.AFTERMATH)

func _on_protect_pressed() -> void:
	if _phase == Phase.PROTECT and not _has_protected:
		_has_protected = true

func _process_aftermath(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		_attack_particles.visible = false
		_portal_light.light_color = Color(0.8, 0.6, 0.3)
		_portal_light.light_energy = 2.0

		DialogueData.say_to(_dialogue, "peris_sim.aftermath")
		DialogueData.say_to(_dialogue, "peris_sim.monos.thanks")
		_dialogue.dialogue_finished.connect(
			func(): _set_phase(Phase.EFFICIENCY_LOG),
			CONNECT_ONE_SHOT
		)

func _process_efficiency_log(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		_efficiency_score = 62.0
		DialogueData.say_to(_dialogue, "peris_sim.system.complete")
		DialogueData.say_to(_dialogue, "peris_sim.penalty_narration")
		DialogueData.say_to(_dialogue, "peris_sim.session_ends")
		_monos.fade_out(1.5)
		_dialogue.dialogue_finished.connect(
			func(): _set_phase(Phase.TRANSITION_OUT),
			CONNECT_ONE_SHOT
		)

func _process_transition_out(delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		_player.set_move_enabled(false)
		_session_timer_label.visible = false

	var alpha := clampf(_phase_timer / 2.0, 0.0, 1.0)
	_fade_rect.color = Color(0.03, 0.03, 0.04, alpha)

	if _phase_timer > 2.5:
		_set_phase(Phase.COMPLETE)
		get_tree().change_scene_to_file("res://scenes/tutorial/leaving_facility.tscn")

# --- Thoughts ---

func _show_thought(text: String) -> void:
	_thought_label.text = text
	var tween := create_tween()
	tween.tween_property(_thought_label, "modulate:a", 0.7, 0.5)

func _hide_thought() -> void:
	var tween := create_tween()
	tween.tween_property(_thought_label, "modulate:a", 0.0, 0.5)

func _update_stamina_display() -> void:
	_stamina_bar.value = _stamina
	_stamina_label.text = "STA  %d%%" % int(_stamina)
	# Color shift when low
	var fill: StyleBoxFlat = _stamina_bar.get_theme_stylebox("fill")
	if _stamina < 30:
		fill.bg_color = Color(0.7, 0.3, 0.2)
	elif _stamina < 60:
		fill.bg_color = Color(0.7, 0.55, 0.2)
	else:
		fill.bg_color = Color(0.3, 0.5, 0.7)

func _update_session_timer() -> void:
	var overtime := _session_time > 20.0
	_session_timer_label.text = "SESSION  %s  %s" % [
		"%d:%02d" % [int(_session_time) / 60, int(_session_time) % 60],
		"OVERTIME" if overtime else ""
	]
	_session_timer_label.add_theme_color_override("font_color",
		Color(0.8, 0.2, 0.15) if overtime else Color(0.4, 0.5, 0.6, 0.7)
	)

# --- Environment ---

func _build_environment() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	# Floor — warm wood-tone
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

	# Floor collision
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(4, -0.01, 0)
	floor_body.collision_layer = 1  # Ground
	floor_body.collision_mask = 0
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(18, 0.02, 12)
	fc.shape = fs
	floor_body.add_child(fc)
	env.add_child(floor_body)

	# Walls — warm organic tones
	var wc := Color(0.16, 0.12, 0.09)
	_add_wall(env, Vector3(4, 1.5, -6), Vector3(18, 3, 0.2), wc)
	_add_wall(env, Vector3(4, 1.5, 6), Vector3(18, 3, 0.2), wc)
	_add_wall(env, Vector3(-5, 1.5, 0), Vector3(0.2, 3, 12), wc)
	_add_wall(env, Vector3(13, 1.5, 0), Vector3(0.2, 3, 12), wc)

	# Peris's desk — organic, rounded feel (represented by warm-toned box)
	_add_desk(env, DESK_POS)

	# Soft seating area (client session space)
	_add_seating(env, Vector3(4, 0, 0))

	# Plants / organic elements — warm green spheres along walls
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

	# Warm lighting
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

	# World environment
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

func _add_wall(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	m.position = pos
	parent.add_child(m)

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
	# Two soft cushion seats facing each other (session space)
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
	# The feed terminal / portal — glowing arch
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

	# Portal surface — translucent glowing plane
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

	# Portal light
	_portal_light = OmniLight3D.new()
	_portal_light.position = PORTAL_POS + Vector3(0, 1.5, 0)
	_portal_light.light_color = Color(0.8, 0.5, 0.25)
	_portal_light.light_energy = 1.5
	_portal_light.omni_range = 5.0
	add_child(_portal_light)

	# Attack flash light (hidden initially)
	_attack_particles = OmniLight3D.new()
	_attack_particles.position = MONOS_POS + Vector3(0, 1.0, 0)
	_attack_particles.light_color = Color(0.9, 0.15, 0.05)
	_attack_particles.light_energy = 0
	_attack_particles.omni_range = 4.0
	_attack_particles.visible = false
	add_child(_attack_particles)

	# "FEED TERMINAL" label
	var lbl := Label3D.new()
	lbl.text = "FEED TERMINAL"
	lbl.font_size = 32
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.7, 0.5, 0.3, 0.6)
	lbl.position = PORTAL_POS + Vector3(0, 2.6, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)

# --- Characters ---

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	# Player (Peris) — at her desk, away from the portal
	_player = _create_player()
	_player.position = PERIS_START
	chars.add_child(_player)

	# Monos — appears at the portal (hidden initially)
	_monos = Node3D.new()
	_monos.name = "Monos"
	_monos.set_script(preload("res://scripts/game/npc.gd"))
	_monos.display_name = "MONOS"
	_monos.color = Color(0.6, 0.5, 0.35)
	_monos.position = MONOS_POS
	_monos.visible = false
	chars.add_child(_monos)

	# Camera
	var cam := Camera3D.new()
	cam.name = "GameCamera"
	cam.set_script(preload("res://scripts/game/game_camera.gd"))
	add_child(cam)
	_camera = cam
	_camera.target = _player
	_camera.follow_offset = Vector3(0, 8, 6)
	_camera.set_pan_enabled(false)

func _create_player() -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.name = "Peris"

	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.25
	cs.height = 1.0
	col.shape = cs
	col.position.y = 0.5
	player.add_child(col)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.position.y = 0.5
	player.add_child(mesh)

	var label := Label3D.new()
	label.name = "Label3D"
	label.text = "PERIS"
	label.font_size = 48
	label.pixel_size = 0.01
	label.modulate = Color(1.0, 0.67, 0.27, 0.8)
	label.position.y = 1.3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	player.add_child(label)

	player.set_script(preload("res://scripts/game/player.gd"))
	player.color = Color(1.0, 0.67, 0.27)  # Peris amber
	# Collision layer 2 (characters), mask 2 (other characters only)
	player.collision_layer = 2
	player.collision_mask = 2
	return player

# --- UI ---

func _build_ui() -> void:
	# Dialogue
	var dlg := CanvasLayer.new()
	dlg.name = "DialogueBox"
	dlg.set_script(preload("res://scripts/game/dialogue_box.gd"))
	add_child(dlg)
	_dialogue = dlg

	# Tutorial prompt
	var tp := CanvasLayer.new()
	tp.name = "TutorialPrompt"
	tp.set_script(preload("res://scripts/game/tutorial_prompt.gd"))
	add_child(tp)
	_tutorial_prompt = tp

	# Fade overlay
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 20
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.15, 0.1, 0.03, 1)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade_rect)

	# Stamina bar — top right
	var sta_layer := CanvasLayer.new()
	sta_layer.layer = 10
	add_child(sta_layer)

	var sta_container := HBoxContainer.new()
	sta_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sta_container.offset_left = -180
	sta_container.offset_top = 12
	sta_container.offset_right = -12
	sta_container.offset_bottom = 32
	sta_container.add_theme_constant_override("separation", 8)
	sta_layer.add_child(sta_container)

	_stamina_label = Label.new()
	_stamina_label.add_theme_font_size_override("font_size", 12)
	_stamina_label.add_theme_color_override("font_color", Color(0.3, 0.5, 0.7, 0.8))
	_stamina_label.custom_minimum_size.x = 70
	sta_container.add_child(_stamina_label)

	_stamina_bar = ProgressBar.new()
	_stamina_bar.min_value = 0
	_stamina_bar.max_value = STAMINA_MAX
	_stamina_bar.value = _stamina
	_stamina_bar.show_percentage = false
	_stamina_bar.custom_minimum_size = Vector2(90, 16)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.1)
	bg_style.set_corner_radius_all(2)
	_stamina_bar.add_theme_stylebox_override("background", bg_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.3, 0.5, 0.7)
	fill_style.set_corner_radius_all(2)
	_stamina_bar.add_theme_stylebox_override("fill", fill_style)
	sta_container.add_child(_stamina_bar)

	# Session timer — top center
	_session_timer_label = Label.new()
	_session_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_session_timer_label.offset_top = 12
	_session_timer_label.offset_left = -100
	_session_timer_label.offset_right = 100
	_session_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_session_timer_label.add_theme_font_size_override("font_size", 13)
	_session_timer_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.7))
	_session_timer_label.visible = false
	sta_layer.add_child(_session_timer_label)

	# Thought display
	var thought_layer := CanvasLayer.new()
	thought_layer.layer = 11
	add_child(thought_layer)
	_thought_label = Label.new()
	_thought_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thought_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_thought_label.offset_top = 50
	_thought_label.offset_left = -300
	_thought_label.offset_right = 300
	_thought_label.add_theme_font_size_override("font_size", 14)
	_thought_label.add_theme_color_override("font_color", Color(0.75, 0.6, 0.45))
	_thought_label.modulate.a = 0.0
	_thought_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thought_layer.add_child(_thought_label)

	# Protect ability button — bottom center, hidden initially
	var ability_layer := CanvasLayer.new()
	ability_layer.layer = 10
	add_child(ability_layer)

	_protect_button = Button.new()
	_protect_button.text = "PROTECT  [Q]"
	_protect_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_protect_button.offset_top = -50
	_protect_button.offset_bottom = -20
	_protect_button.offset_left = -70
	_protect_button.offset_right = 70
	_protect_button.add_theme_font_size_override("font_size", 14)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.6, 0.4, 0.15, 0.9)
	btn_style.border_color = Color(0.8, 0.55, 0.2)
	btn_style.set_border_width_all(2)
	btn_style.set_corner_radius_all(4)
	btn_style.set_content_margin_all(8)
	_protect_button.add_theme_stylebox_override("normal", btn_style)
	_protect_button.add_theme_color_override("font_color", Color.WHITE)
	_protect_button.pressed.connect(_on_protect_pressed)
	_protect_button.visible = false
	ability_layer.add_child(_protect_button)

	# Also allow Q key for protect
	set_process_unhandled_key_input(true)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_Q and _phase == Phase.PROTECT and not _has_protected:
			_on_protect_pressed()
