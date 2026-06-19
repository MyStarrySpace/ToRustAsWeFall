@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

## Peris simulation tutorial: run, stamina, Protect, and Monos.

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
var _sanction_feed_label: Label3D
var _portal_tween_active := false
var _hud  # GameHUD

# Watering beat (phase 1): the hand-inventory tutorial. Peris waters the Boston fern (Plant7) out of
# HABIT — her plants are engineered to stay green, so it's a ritual, not survival (no drying). A
# watering can sits by the desk as a real GameState ITEM: pick it up (hand slot fills, HUD shows it),
# carry it over, water the fern. The exploration gate only unlocks once the fern is watered AND the
# wander timer has elapsed — the beat is the wait for Monos. The fern's watering-tradition reflection
# (plant_7.line / .line_repeat) lives in its inspection zone.
var _watering_can_item_id := ""
var _watering_can_mesh: Node3D
var _water_plant_interactable
var _can_pickup_interactable
var _plant_watered := false
var _explore_time_elapsed := false
const WATERING_CAN_POS := Vector3(8.0, 0.0, 2.0)  # reachable, near the fern
const FERN_POS := Vector3(6.0, 0.0, 2.4)  # Plant7 (Boston fern) — floor-standing watering target near the seating
# The watering beat drives the player to the dry fern; the input playthrough drives this point.
const DRY_PLANT_POS := FERN_POS

# Exploration beat (phase 1, pre-Monos-arrival)
var _explore_logbook_gate  # Interactable at the logbook
const EXPLORE_MIN_TIME := 6.0  # scheduler seconds before the logbook gate unlocks
var _explore_gate_unlocked := false
var _explore_gate_fired := false

# Stamina and run speed are authoritative in GameState.
var _is_paused := false
var _efficiency_score := 100.0

# The portal now sits on the WEST side wall facing the room (+X); the furniture turns to face it.
const PORTAL_PANEL := Vector3(0.7, 2.4, 3.0)   # portal panel centre on the west wall
const PORTAL_FACE := Vector3(1, 0, 0)          # the direction the portal faces (into the room)
const DESK_POS := Vector3(2.0, 0, 1.3)  # floor in front of the terminal (beside the portal)
const PORTAL_POS := Vector3(2.6, 0, 3.0)  # floor in front of the portal — clear space for Peris
const MONOS_POS := Vector3(3.7, 0, 4.4)  # Monos near the portal, off Peris's stand-spot
const PERIS_START := Vector3(4.4, 0.5, 3.0)  # front-centre, facing the portal

# The workspace is the modeled Crocotile room (peris-sim.gltf): floor X in [0, 14], Z in [0, 6], up
# Y in [0, 5]. The grid is that footprint at 1 cell / unit, so movement is cell-based + cooperative
# like the other gridded scenes. OPEN (no border): the whole floor is walkable. Plants/zones sit right
# up against the visual walls — a bordered grid would wall those edge cells off and make those
# exploration zones unreachable.
const GRID_ORIGIN := Vector3(0.0, 0.0, 0.0)
const GRID_SIZE := Vector2i(14, 6)
const ROOM_FLOOR_Y := 0.0  # the modeled floor's top surface
var _grid: GridWorld
# The room model binding — model lookups / floor surface / occupancy flow through this (RoomModelBinder).
var _room_binder := RoomModelBinder.new()

# The composed room visuals (shell + sofas) and the authored furniture/portal/props, both authored in
# the same Godot frame as the grid above.
const ROOM_GLTF := preload("res://resources/models/peris-sim/peris-sim.gltf")
const FURNITURE_GLTF := preload("res://resources/models/peris-sim/peris-furniture.gltf")

# --- Virtual method overrides ---

func _build_scene() -> void:
	_build_grid()
	_build_environment()

## A single-level walkable plane over the modeled floor (open, no border).
func _build_grid() -> void:
	_grid = GridWorld.new()
	_grid.origin = GRID_ORIGIN
	_grid.create_room(GRID_SIZE.x, GRID_SIZE.y, false)
	# The scene's ONE declaration of its modeled room: the floor surface (overlays/raycast ride it),
	# grid seams aligned to the model's floor, and the re-export guards. setup() lifts grid.origin.y
	# to the floor top so every ground overlay sits on the modeled floor, not inside the slab.
	_room_binder.setup(self, _grid, {
		"root_name": "PerisRoom",
		"floor_surface_y": ROOM_FLOOR_Y,
		"grid_origin_xz": Vector2(0, 0),
		"occupants": [],
		"gltf_path": "res://resources/models/peris-sim/peris-sim.gltf",
		"wired_materials": [],
	})
	_build_portal()

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	_player = _create_player_character("Peris", Color(1.0, 0.67, 0.27))
	_player.position = PERIS_START
	if not Engine.is_editor_hint():
		_player.grid_world = _grid
	chars.add_child(_player)

	_monos = _create_npc("Monos", Color(0.6, 0.5, 0.35))
	_monos.display_name = "MONOS"
	_monos.position = MONOS_POS
	_monos.visible = false
	if not Engine.is_editor_hint():
		_monos.grid_world = _grid
	chars.add_child(_monos)

	if not Engine.is_editor_hint():
		# The modeled room is small (14x6); pull the follow camera up/back so the whole floor frames,
		# keeping the far corners (plant stand / bookshelf) clickable.
		_setup_game_camera(_player, Vector3(0, 14, 10), true)

func _register_characters() -> void:
	_game_state.grid = _grid
	_register_gs_character("peris", _player, GameState.WALK_SPEED, {
		"stamina": GameState.STAMINA_MAX,
	})
	_register_gs_character("monos", _monos, _monos.move_speed)

func _setup_ui() -> void:
	_thought_label.add_theme_color_override("font_color", Color(0.75, 0.6, 0.45))

	_hud = CanvasLayer.new()
	_hud.name = "GameHUD"
	_hud.set_script(preload("res://scripts/ui/game_hud.gd"))
	add_child(_hud)
	_hud.add_stat_bar("sta", Color(0.3, 0.5, 0.7), GameState.STAMINA_MAX, GameState.STAMINA_MAX)
	_hud.show_pause_toggle(false)
	_hud.show_run_toggle(false)
	var protect_binding := AbilityData.binding("protect")
	_hud.add_ability("protect", AbilityData.get_ability("peris_sim.protect").get("display_name", "PROTECT"),
		str(protect_binding.get("keybind", "X")), protect_binding.get("color", Color(0.8, 0.55, 0.2)))
	_hud.pause_toggled.connect(_on_pause_toggled)
	# Step guards decide when run toggles are allowed.
	_hud.run_toggled.connect(func(running: bool): _toggle_run())
	_hud.ability_pressed.connect(func(id: String):
		if id == "protect":
			_on_protect_pressed()
	)
	# Keep run input gated by step.
	_hud.bind_game_state(_game_state, "peris", false)

func _begin() -> void:
	_add_screen_effect("ChromaticAberration", preload("res://resources/chromatic_aberration.gdshader"))
	if start_phase > 0:
		_visit_phase = start_phase
	_current_step = "fade_in"
	_player.set_move_enabled(false)
	if _visit_phase == 1:
		_fade_from(Color(0.15, 0.1, 0.03, 1), 3.0, _start_workspace, "workspace")
	else:
		# Phase 2 resumes mid-session.
		_monos.visible = true
		_portal_light.light_color = Color(0.9, 0.6, 0.3)
		_portal_light.light_energy = 3.0
		_fade_from(Color(0.15, 0.1, 0.03, 1), 3.0, _start_session_begins, "session_begins")

func _compute_speed() -> float:
	var spd := 10.0 if Input.is_action_pressed("fast_forward") else 1.0
	if _is_paused or _current_step in ["alert_monos", "protect_prompt", "run_prompt", "click_monos", "confirm_protect"]:
		spd = 0.0
	return spd

func _on_process(delta: float, spd: float) -> void:
	_update_fades()

	# GameState and GameHUD handle stats, running, and queued Protect.

	if _portal_light and not _portal_tween_active:
		_portal_light.light_energy = 1.5 + sin(Time.get_ticks_msec() * 0.002) * 0.3  # @rendering_only: portal glow

	# Attack light flash
	if _attack_particles and _attack_particles.visible:
		_attack_particles.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.015) * 2.0  # @rendering_only: attack flash

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

# --- Target selection (click Monos) ---

## During click_monos the player is in "select" click mode; the shared input
## controller reports the clicked ground position here. We only decide whether
## it's close enough to Monos — no raycasting in the sequence.
func _on_target_selected(world_pos: Vector3) -> void:
	if _current_step != "click_monos":
		return
	var dist_to_monos := Vector2(world_pos.x - MONOS_POS.x, world_pos.z - MONOS_POS.z).length()
	if dist_to_monos < 2.5:
		if _player.ground_clicked.is_connected(_on_target_selected):
			_player.ground_clicked.disconnect(_on_target_selected)
		_player.set_click_mode("move")
		_tutorial_prompt.hide_prompt()
		_start_confirm_protect()
	else:
		_show_correction("peris_sim.correct.target_monos")

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
	# Run is only valid at run_prompt.
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
	# Normal run toggle.
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
	# Phase 1 wanders the room while the new client's session stalls; the
	# exploration gate is where the spoofed signal finally breaks through.
	_show_thought(DialogueData.text("peris.sim_expand.opening.line"))
	_build_exploration_objects()
	_explore_gate_unlocked = false
	_explore_gate_fired = false
	# Teach the reveal-all overlay while the player is hunting the room for what to interact with.
	# UI lane so the hint shows even if gameplay is paused, and speeds with hold-F like the rest.
	_ui_scheduler.schedule_after(2.5, func():
		if _tutorial_prompt != null:
			_tutorial_prompt.show_prompt("[Hold Shift] - reveal interactions", 4.0), "highlight_hint")
	_scheduler.schedule_after(EXPLORE_MIN_TIME, _unlock_exploration_gate, "explore_gate_unlock")

func _unlock_exploration_gate() -> void:
	# The wander timer is HALF the unlock; the fern must be watered too (the inventory beat).
	_explore_time_elapsed = true
	_maybe_unlock_exploration_gate()

func _on_exploration_gate_interacted() -> void:
	if not _explore_gate_unlocked or _explore_gate_fired:
		return
	_explore_gate_fired = true
	_hide_thought()
	_start_monos_breakthrough()

## Monos breaks through on a spoofed signal — not the scheduled client. He is
## panicked, apologetic for the channel, and discloses why he risked it.
## Turn Peris to face the portal — she works facing it (the session, the attack, casting Protect).
func _face_peris_to_portal() -> void:
	if _player == null:
		return
	var target := Vector3(PORTAL_PANEL.x, _player.global_position.y, PORTAL_PANEL.z)
	if target.distance_to(_player.global_position) > 0.1:
		_player.look_at(target, Vector3.UP)

func _start_monos_breakthrough() -> void:
	_current_step = "monos_breakthrough"
	_face_peris_to_portal()
	_monos.visible = true
	_portal_light.light_color = Color(0.9, 0.6, 0.3)
	_portal_light.light_energy = 3.0
	_dialogue_chain([
		"peris_sim.monos.late",
		"peris_sim.peris.purpose",
		"peris_sim.monos.turn",
		"peris_sim.monos.opening",
		"peris_sim.monos.real",
		"peris_sim.monos.heart",
		"peris_sim.monos.mind",
		"peris_sim.peris.fight",
	], func():
		_scheduler.schedule_after(3.0, _start_transition_out, "transition_out")
	)

func _start_session_begins() -> void:
	_current_step = "session_begins"
	_face_peris_to_portal()
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
	DialogueData.say_to(_dialogue, "peris_sim.peris.alarm")
	DialogueData.say_to(_dialogue, "peris_sim.monos.help")
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
	_is_paused = true
	_player.set_move_enabled(false)
	if _hud:
		_hud.set_paused(true)
	_start_protect_prompt()

func _start_protect_prompt() -> void:
	_enter_step("protect_prompt")
	DialogueData.say_to(_dialogue, "peris_sim.peris.protect_him")
	_dialogue.dialogue_finished.connect(func():
		_tutorial_prompt.show_prompt("[X] - queue Protect")
	, CONNECT_ONE_SHOT)

func _start_run_prompt() -> void:
	_enter_step("run_prompt")
	_tutorial_prompt.show_prompt("[Z] - toggle Run")
	if _hud:
		_hud.show_run_toggle(true)

func _start_click_monos() -> void:
	_enter_step("click_monos")
	_player.set_move_enabled(true)
	# Clicks select a target rather than move; the shared controller reports the
	# clicked ground position to _on_target_selected.
	_player.set_click_mode("select")
	if not _player.ground_clicked.is_connected(_on_target_selected):
		_player.ground_clicked.connect(_on_target_selected)
	_tutorial_prompt.show_prompt("[Click] Monos - set Protect target")

func _start_confirm_protect() -> void:
	_enter_step("confirm_protect")
	_protect_queued = true
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
	_tutorial_prompt.show_prompt("[Space] - unpause")

func _start_executing() -> void:
	_current_step = "executing"
	_is_paused = false
	if _hud:
		_hud.set_paused(false)
	_tutorial_prompt.hide_prompt()
	_hide_thought()
	# Queue Protect; GameState moves Peris into range.
	if _protect_queued:
		_protect_queued = false
		_game_state.queue_ability("peris", "protect", PORTAL_POS, 2.5, _fire_queued_protect)

func _on_protect_pressed() -> void:
	if _has_protected:
		return
	# X is only valid at protect_prompt.
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
	_face_peris_to_portal()
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
	# Sync portal closure with Monos fade.
	_portal_tween_active = true
	var t := create_tween()
	t.tween_property(_portal_light, "light_energy", 0.0, 1.5)
	t.parallel().tween_property(_portal_visual, "scale", Vector3(1.0, 0.0, 1.0), 1.5)
	t.tween_callback(func(): _portal_tween_active = false)
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(1.6, _start_sanction_notice, "sanction_notice"),
		CONNECT_ONE_SHOT
	)

func _start_sanction_notice() -> void:
	_current_step = "sanction_notice"
	_show_sanction_feed_visual(
		"SANCTION MODE",
		"CLIENT FEED DISCONNECTED\nCASELOAD REASSIGNED",
		Color(0.75, 0.82, 0.7)
	)
	DialogueData.say_to(_dialogue, "peris_sim.system.sanction_notice")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_sanction_feed, "sanction_feed"),
		CONNECT_ONE_SHOT
	)

func _start_sanction_feed() -> void:
	_current_step = "sanction_feed"
	_show_sanction_feed_visual(
		"RESTORATIVE MODE",
		"GEL LOOP\nSOAP LOOP\nPLANT TIMELAPSE",
		Color(0.6, 0.85, 0.78)
	)
	DialogueData.say_to(_dialogue, "peris_sim.system.wellness_feed")
	DialogueData.say_to(_dialogue, "peris_sim.peris.sanction_reaction")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_spiral_flash, "spiral_flash"),
		CONNECT_ONE_SHOT
	)

func _start_spiral_flash() -> void:
	_current_step = "spiral_flash"
	_show_sanction_feed_visual(
		"FRAME DROP",
		"SPIRAL SIGNAL DETECTED",
		Color(0.55, 0.65, 1.0)
	)
	DialogueData.say_to(_dialogue, "peris_sim.system.spiral_flash")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_retro, "retro"),
		CONNECT_ONE_SHOT
	)

func _start_retro() -> void:
	_current_step = "retro"
	_show_sanction_feed_visual(
		"RESTORATIVE MODE",
		"ARCHIVE FOOTAGE",
		Color(0.68, 0.78, 0.72)
	)
	DialogueData.say_to(_dialogue, "peris_sim.peris.retro")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_sim_bay_exit, "sim_bay_exit"),
		CONNECT_ONE_SHOT
	)

func _start_sim_bay_exit() -> void:
	_current_step = "sim_bay_exit"
	_player.set_move_enabled(false)
	if _sanction_feed_label:
		_sanction_feed_label.visible = false
	DialogueData.say_to(_dialogue, "peris_sim.worker.okay")
	DialogueData.say_to(_dialogue, "peris_sim.worker.medical")
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
		# First half opens the game, then hands off to Aster's sim.
		_visit_phase = 2
		_change_scene_or_record("res://scenes/tutorial/aster_sim.tscn")
	else:
		# Second half (Monos session) leads into Tag Day.
		_change_scene_or_record("res://scenes/tutorial/tag_day.tscn")

# Run/pause/protect keys arrive as HUD signals (run_toggled / pause_toggled /
# ability_pressed), mapped from the input map by GameHUD — see _setup_ui.

# --- Environment ---

## Re-lay-out the modeled room: portal onto the WEST side wall facing the room, the seating turned to
## face it, the terminal beside it, decor along the far walls — leaving the floor in front of the portal
## clear for Peris. The furniture are group nodes in the loaded model, so we set their transforms in the
## gameplay frame (preserving each group's scale; yaw only).
func _relayout_room(root: Node) -> void:
	_place_group(root, "Portal", PORTAL_PANEL, 90.0)                  # west wall, faces +X into the room
	_place_group(root, "Kiosk", Vector3(0.9, 0.0, 1.2), 90.0)        # terminal beside the portal
	_place_group(root, "couch", Vector3(7.4, 0.5, 3.0), 0.0)         # faces -X toward the portal
	_place_group(root, "Armchair", Vector3(5.7, 0.0, 1.4), -35.0)
	_place_group(root, "bench", Vector3(5.7, 0.4, 4.6), 0.0)
	_place_group(root, "CoffeeTable", Vector3(4.5, 0.0, 3.0), 0.0)
	_place_group(root, "PlantStand", Vector3(4.4, 0.0, 5.2), 0.0)    # front-mid, beside the bench (holds the jade)
	_place_group(root, "Bookshelf", Vector3(12.5, 0.0, 1.0), -90.0)  # back-east decor (by the logbook), faces -X

func _place_group(root: Node, node_name: String, pos: Vector3, yaw_deg: float) -> void:
	var n := root.find_child(node_name, true, false)
	if not (n is Node3D):
		return
	var sc: Vector3 = (n as Node3D).global_transform.basis.get_scale()
	(n as Node3D).global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(sc), pos)

func _build_environment() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	# The modeled room is the scene's space: the Crocotile shell + sofas, and the authored
	# furniture / portal frame / props, both authored in the grid frame (X[0,14] Z[0,6]).
	var room := Node3D.new()
	room.name = "PerisRoom"
	add_child(room)
	var shell := ROOM_GLTF.instantiate()
	shell.name = "RoomShell"
	room.add_child(shell)
	var furniture := FURNITURE_GLTF.instantiate()
	furniture.name = "RoomFurniture"
	room.add_child(furniture)
	_relayout_room(room)

	# The gltf carries no collision; a thin static slab over the floor footprint gives the shared
	# click-raycast a surface (layer 1, mask 0 — picked by the ground ray, collides with nothing).
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorCollision"
	floor_body.position = Vector3(GRID_SIZE.x * 0.5, ROOM_FLOOR_Y - 0.01, GRID_SIZE.y * 0.5)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(GRID_SIZE.x, 0.02, GRID_SIZE.y)
	fc.shape = fs
	floor_body.add_child(fc)
	env.add_child(floor_body)

	# Cool key + cool ambient (the original peris_room.tscn palette) — a calm lavender daylight, not the
	# warm/orange wash. The directional angle is unchanged; only the colours + glow match the old room.
	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-40, -20, 0)
	dir_light.light_color = Color(0.88, 0.9, 1.0)      # cool white
	dir_light.light_energy = 0.95
	dir_light.shadow_enabled = true
	env.add_child(dir_light)

	var room_fill := OmniLight3D.new()                 # gentle COOL fill so corners aren't black
	room_fill.position = Vector3(7, 2.8, 3)
	room_fill.light_color = Color(0.55, 0.6, 0.8)
	room_fill.light_energy = 1.2
	room_fill.omni_range = 12.0
	env.add_child(room_fill)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.07)        # cool dark, not warm brown
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4527142, 0.37521115, 0.5201956)   # the old room's cool lavender ambient
	e.ambient_light_energy = 0.6
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_bloom = 0.12
	we.environment = e
	env.add_child(we)

# --- Portal ---

## The modeled portal is the wall-mounted frame; this builds only the GAMEPLAY portal layer
## (the morphing glow/light/attack flash and labels the session steps drive), in front of it.
func _build_portal() -> void:
	# The modeled portal is on the WEST wall facing +X; the glow surface sits just in front of the panel.
	var portal_surface := PORTAL_PANEL + PORTAL_FACE * 0.12

	_portal_visual = MeshInstance3D.new()
	var pv := BoxMesh.new()
	pv.size = Vector3(0.06, 2.0, 0.9)   # thin along X — the panel faces +X
	_portal_visual.mesh = pv
	var pvm := StandardMaterial3D.new()
	pvm.albedo_color = Color(0.8, 0.5, 0.2, 0.25)
	pvm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pvm.emission_enabled = true
	pvm.emission = Color(0.6, 0.35, 0.15)
	pvm.emission_energy_multiplier = 1.2
	pvm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal_visual.material_override = pvm
	_portal_visual.position = portal_surface
	add_child(_portal_visual)

	_portal_light = OmniLight3D.new()
	_portal_light.position = PORTAL_PANEL + PORTAL_FACE * 0.5
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
	lbl.position = portal_surface + Vector3(0, 1.4, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)

	_sanction_feed_label = Label3D.new()
	_sanction_feed_label.name = "SanctionFeedLabel"
	_sanction_feed_label.text = ""
	_sanction_feed_label.font_size = 28
	_sanction_feed_label.pixel_size = 0.009
	_sanction_feed_label.modulate = Color(0.6, 0.85, 0.78, 0.95)
	_sanction_feed_label.outline_modulate = Color(0.03, 0.04, 0.03, 0.8)
	_sanction_feed_label.outline_size = 4
	_sanction_feed_label.position = portal_surface + Vector3(0, 0, 0.1)
	_sanction_feed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sanction_feed_label.visible = false
	add_child(_sanction_feed_label)

func _show_sanction_feed_visual(title: String, body: String, color: Color) -> void:
	if _sanction_feed_label:
		_sanction_feed_label.text = "%s\n%s" % [title, body]
		_sanction_feed_label.modulate = Color(color.r, color.g, color.b, 0.95)
		_sanction_feed_label.visible = true
	if _portal_visual:
		_portal_visual.scale = Vector3.ONE
		var mat := _portal_visual.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(color.r, color.g, color.b, 0.3)
			mat.emission = color
			mat.emission_energy_multiplier = 1.8
	if _portal_light:
		_portal_light.light_color = color
		_portal_light.light_energy = 2.4

# --- Exploration objects (phase 1, pre-Monos-arrival) ---
# The modeled room (peris-sim.gltf + peris-furniture.gltf) carries all cosmetic decor — rug, shelves,
# sofas, props — so there is no procedural decoration pass; gameplay objects live below.

func _build_exploration_objects() -> void:
	if Engine.is_editor_hint():
		return
	var env: Node3D = self
	_build_peris_plants(env)
	_build_watering_beat(env)
	_build_peris_painting(env)
	_build_peris_wellness_feed(env)
	_build_peris_strike_warning(env)
	_build_peris_logbook_gate(env)

# The plant gltfs export at WILDLY different native scales (boston_fern ~2.9 tall, haworthia ~1.4),
# all pot-at-Y0 and XZ-centered on their own origin. These are the measured native AABB heights — a
# uniform scale of target/native normalizes each instance deterministically (no per-frame AABB read,
# so movement/replay stay deterministic), and the pot lands on the floor at `pos`.
const PLANT_NATIVE_HEIGHT := {
	"boston_fern": 2.94, "calathea": 3.32, "haworthia": 1.36, "jade": 2.57,
	"jasmine": 2.69, "peace_lily": 4.58, "pilea": 3.48, "pothos": 2.81, "spider": 3.93,
}

## Instance a plant gltf, normalized to `target_height` and grounded so its pot sits at `pos`.
func _make_peris_plant(parent: Node3D, pos: Vector3, species: String, target_height: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var native: float = float(PLANT_NATIVE_HEIGHT.get(species, 1.0))
	var s := target_height / native if native > 0.0 else 1.0
	var gltf: PackedScene = load("res://resources/models/peris-sim/plants/plant_%s.gltf" % species)
	if gltf != null:
		var inst := gltf.instantiate() as Node3D
		inst.scale = Vector3(s, s, s)  # uniform — the pot stays at the model origin (Y=0)
		root.add_child(inst)
	return root

func _build_peris_plants(parent: Node3D) -> void:
	# Potted plants sit ON their furniture: small ones on the bookshelf shelves (east wall), the plant
	# stand, and the coffee table; the big Boston fern (Plant7, the watering target) + the peace lily stay
	# floor-standing where they're reachable. Heights shrink for the surface plants so they read in scale.
	# Each plant has its OWN walk-to inspection zone, which must stay >=2.8m from every other inspectable
	# (the --test-peris-sim spacing guard). The room is already dense with fixed inspectables (wellness,
	# painting, strike-warning, logbook gate, the watered fern), so the plants must stay SPREAD — they
	# can't cluster on one shelf. The jade sits on the plant stand; the rest are floor-standing at spaced
	# spots (Peris's plants fill her room). (To cluster more on furniture we'd switch to a shared
	# per-shelf inspect zone — a mechanic change.)
	var plants := [
		[Vector3(0.6, 0, 5.7), "spider", 1.2, "peris.sim_expand.plant_1.line"],        # floor, front-west
		[Vector3(13.4, 0, 0.4), "calathea", 1.2, "peris.sim_expand.plant_2.line"],     # floor, back-east corner
		[Vector3(1.5, 0, 3.0), "haworthia", 0.5, "peris.sim_expand.plant_3.line"],     # floor, west
		[Vector3(4.4, 1.12, 5.2), "jade", 0.7, "peris.sim_expand.plant_4.line"],       # plant stand top
		[Vector3(7.4, 0, 5.5), "jasmine", 1.2, "peris.sim_expand.plant_5.line"],       # floor, front
		[Vector3(10.3, 0, 5.6), "pothos", 1.1, "peris.sim_expand.plant_6.line"],       # floor, front-east
		[FERN_POS, "boston_fern", 1.3, "peris.sim_expand.plant_7.line"],               # floor near seating (watering)
		[Vector3(3.8, 0, 0.5), "pilea", 1.0, "peris.sim_expand.plant_8.line"],         # floor, back-west
		[Vector3(8.9, 0, 2.9), "peace_lily", 1.4, "peris.sim_expand.plant_9.line"],    # floor, centre-east
	]
	for i in range(plants.size()):
		var p: Array = plants[i]
		var pos: Vector3 = p[0]
		var species: String = p[1]
		var height: float = p[2]
		var line_key: String = p[3]
		var plant_node := _make_peris_plant(parent, pos, species, height)
		plant_node.name = "Plant%d" % (i + 1)
		var zone_pos := Vector3(pos.x, 0, pos.z)
		var zone: Area3D
		if i == 6:  # the Boston fern: the watering-tradition line advances to a follow-up on re-inspection
			zone = _make_exploration_sequence_zone(parent, zone_pos, "Plant7Zone",
				[line_key, "peris.sim_expand.plant_7.line_repeat"], 1.0, 0.6)
		else:
			zone = _make_exploration_zone(parent, zone_pos,
				"Plant%dZone" % (i + 1),
				line_key,
				1.0, 0.6)  # re-inspectable by default: re-clicking a plant replays Peris's line
		var target := _outline_object_meshes(parent, "Plant%dOutline" % (i + 1),
			_collect_mesh_instances(plant_node), "peris_plant_%d" % (i + 1), 0.7)
		_set_room_target_interaction_delegate(target, zone)

## The watering can is a REAL item (spawn_item + pick_up_item), not a flag: the beat teaches the
## hand-slot inventory. The dry fern's water spot only accepts a character actually HOLDING it.
func _build_watering_beat(parent: Node3D) -> void:
	# The can: a small kettle by the desk, mirrored by a data-layer item.
	_watering_can_mesh = Node3D.new()
	_watering_can_mesh.name = "WateringCan"
	_watering_can_mesh.position = WATERING_CAN_POS
	parent.add_child(_watering_can_mesh)
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.12
	bm.bottom_radius = 0.16
	bm.height = 0.26
	body.mesh = bm
	var can_mat := StandardMaterial3D.new()
	can_mat.albedo_color = Color(0.45, 0.55, 0.6)
	can_mat.metallic = 0.5
	can_mat.roughness = 0.35
	body.material_override = can_mat
	body.position = Vector3(0, 0.13, 0)
	_watering_can_mesh.add_child(body)
	var spout := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.22, 0.04, 0.04)
	spout.mesh = sm
	spout.material_override = can_mat
	spout.position = Vector3(0.18, 0.18, 0.0)
	spout.rotation.z = 0.5
	_watering_can_mesh.add_child(spout)

	_watering_can_item_id = _game_state.spawn_item("watering_can", WATERING_CAN_POS)

	_can_pickup_interactable = _create_interactable(parent, WATERING_CAN_POS, "WateringCanPickup",
		1.8, 0.7, "PICK UP", false)
	_can_pickup_interactable.interacted.connect(_on_watering_can_picked)
	var can_target := _outline_object_meshes(parent, "WateringCanOutline",
		_collect_mesh_instances(_watering_can_mesh), "watering_can", 0.5)
	_set_room_target_interaction_delegate(can_target, _can_pickup_interactable)
	# Tutorial labels show right away (like Aster's objects): the PICK UP prompt sits over the can
	# from the start, not only once Peris is near it.
	_can_pickup_interactable.call_deferred("show_tutorial_label")

	# The water spot sits ON the fern (Plant7).
	_water_plant_interactable = _create_interactable(parent, FERN_POS, "WaterPlantSpot",
		1.8, 0.9, "WATER", false)
	_water_plant_interactable.interacted.connect(_on_plant_watered)

func _on_watering_can_picked() -> void:
	if _watering_can_item_id == "" or _plant_watered:
		return
	if not _game_state.pick_up_item("peris", _watering_can_item_id):
		return
	if _can_pickup_interactable != null:
		_can_pickup_interactable.set_interaction_enabled(false)
	if _water_plant_interactable != null and _water_plant_interactable.has_method("show_tutorial_label"):
		_water_plant_interactable.show_tutorial_label()

func _on_plant_watered() -> void:
	if _plant_watered:
		return
	var item: Dictionary = _game_state.items.get(_watering_can_item_id, {})
	if str(item.get("holder", "")) != "peris":
		return  # need the can in hand first (the WATER prompt only appears after pickup, so this is rare)
	_plant_watered = true
	_game_state.drop_item("peris", _watering_can_item_id)
	if _watering_can_mesh != null:
		_watering_can_mesh.position = FERN_POS + Vector3(0.5, 0.0, 0.3)
	# The watering ACTION narration — Peris's habitual motion over the fern.
	_show_thought(DialogueData.text("peris.sim_expand.plant_7.look"))
	if _water_plant_interactable != null:
		_water_plant_interactable.set_interaction_enabled(false)
	_maybe_unlock_exploration_gate()

func _maybe_unlock_exploration_gate() -> void:
	if not _explore_time_elapsed or not _plant_watered:
		return
	_explore_gate_unlocked = true
	if _explore_logbook_gate and _explore_logbook_gate.has_method("show_tutorial_label"):
		_explore_logbook_gate.show_tutorial_label()

func _build_peris_painting(parent: Node3D) -> void:
	# Hung on the modeled back wall (Z~0), right of the sofas.
	var pos := Vector3(10.4, 2.2, 0.12)
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
	canvas.position = pos + Vector3(0, 0, 0.04)
	parent.add_child(canvas)
	var zone := _make_exploration_zone(parent, Vector3(10.4, 0, 0.3),
		"PaintingZone",
		"peris.sim_expand.painting.line",
		1.3, 0.6)
	var target := _outline_object_meshes(parent, "PaintingOutline",
		[frame, canvas], "peris_painting", 0.95)
	_set_room_target_interaction_delegate(target, zone)

func _build_peris_wellness_feed(parent: Node3D) -> void:
	# Mounted on the modeled left wall (X~0), near the back corner.
	var pos := Vector3(0.12, 1.6, 0.6)
	var screen := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.04, 0.5, 0.8)
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
	var zone := _make_exploration_zone(parent, Vector3(0.7, 0, 0.3),
		"WellnessZone",
		"peris.sim_expand.wellness.line",
		1.0, 0.6)
	var target := _outline_object_meshes(parent, "WellnessOutline",
		[screen], "peris_wellness", 0.8)
	_set_room_target_interaction_delegate(target, zone)

func _build_peris_strike_warning(parent: Node3D) -> void:
	# Pinned to the modeled right wall (X~14), near the open front corner.
	var pos := Vector3(13.88, 1.8, 5.6)
	var icon := MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(0.04, 0.55, 0.4)
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
	rb.size = Vector3(0.045, 0.08, 0.4)
	strip.mesh = rb
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.5, 0.2, 0.2)
	strip.material_override = rm
	strip.position = pos + Vector3(-0.001, 0.24, 0)
	parent.add_child(strip)
	var area := _make_exploration_zone(parent, Vector3(13.4, 0, 5.6),
		"StrikeWarningZone",
		"",
		1.0, 0.8)  # re-inspectable: re-opening the warning replays the document + Peris's line
	area.connect("interacted", func():
		_play_focused_dialogue_keys([
			"peris.sim_expand.strike_warning.notification",
			"peris.sim_expand.strike_warning.line",
		], area)
	)
	var target := _outline_object_meshes(parent, "StrikeWarningOutline",
		[icon, strip], "peris_strike_warning", 0.7)
	_set_room_target_interaction_delegate(target, area)

func _build_peris_logbook_gate(parent: Node3D) -> void:
	# Logbook is the gate to Monos — by the modeled bookshelf on the right side.
	var pos := Vector3(11.3, 0.9, 3.0)
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
	var gate := _create_interactable(parent, Vector3(pos.x + 0.7, 0, pos.z), "LogbookGate", 2.0, 0.8,
		"Continue", false, Interactable.InteractableType.HOLD_ACTION, "peris.logbook_gate")
	gate.connect("interacted", _on_exploration_gate_interacted)
	_explore_logbook_gate = gate
	var target := _outline_object_meshes(parent, "LogbookOutline",
		[console, screen], "peris_logbook", 1.0)
	_set_room_target_interaction_delegate(target, gate)
