@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"
# @rendering_only_file: decorative timing/randomness only.

## Elevator tutorial through bridge collapse, route choice, and Endo's shelter.

var _aster_node: CharacterBody3D
var _peris_node: CharacterBody3D
var _fall_landed_fired := false  # one-shot guard: bridge landing fires once
var _escort_1  # NPC
var _escort_2  # NPC
var _active_character := "peris"
var _selected_character_ids: Array[String] = ["peris"]
var _suppress_hud_character_signal := false

var _emergency_light: OmniLight3D
var _floor_indicator: Label3D
var _door_panel_a: MeshInstance3D
var _door_panel_b: MeshInstance3D
var _control_panel  # Interactable
var _indicator_timer := 0.0
var _indicator_b_label: Label3D  # The "B" that flickers
var _exit_button  # Interactable that flashes "NO EXIT".
var _aster_wake_interactable  # Interactable for waking knocked-out Aster
var _climb_interactable  # Interactable for checking the collapsed bridge
var _no_exit_label: Label3D

var _hud  # GameHUD

# EMP state
var _emp_count := 0
var _emp_queued := false
var _emp_pause_locked := false
var _emp_cooldown_end := 0.0  # scheduler tick when cooldown expires
var _unit_1_stunned := false
var _unit_2_stunned := false
var _reboot_active := false
var _stamina := 100.0

var _enemies: Array[Enemy] = []
var _enemy_count := 0

# Character HP
var _aster_hp := 100.0
var _peris_hp := 100.0
var _game_over := false
var _iframes: Dictionary = {}  # char_id -> scheduler tick when i-frames expire

# Iron hazard zones: Array of {pos: Vector3, size: Vector3}.
var _iron_patches: Array[Dictionary] = []
const IRON_DAMAGE_PER_SEC := 8.0

# Ferrolure
var _ferrolure_active := false
var _ferrolure_mesh: MeshInstance3D
var _ferrolure_interactable: Node
var _gauntlet_enemies: Array[Enemy] = []

# Chunk system
@export var start_chunk := ""

# Endo (hidden until junction)
var _endo: Node3D
var _drink_mesh: MeshInstance3D  # Individual drink — carried by Endo

# Night watch
var _monster_eyes: Array[OmniLight3D] = []

const ELEVATOR_SIZE := Vector3(8.0, 4.0, 8.0)
const PERIS_START := Vector3(-1.0, 0.5, 1.5)
const ASTER_POS := Vector3(2.0, 0, -2.0)
const ESCORT_1_POS := Vector3(-2.5, 0, -2.5)
const ESCORT_2_POS := Vector3(-2.5, 0, 2.5)
const PANEL_POS := Vector3(3.5, 0, 0)
const EMP_GUARD_STANDOFF_DISTANCE := 2.6

# Below-level ecology
const BELOW_Y := -4.0
const BRIDGE_START_X := 11.5  # ELEVATOR_SIZE.x/2 + 0.5 + 7.0
const BRIDGE_END_X := 23.5    # BRIDGE_START_X + 12.0

# Route fork
const FORK_POS := Vector3(BRIDGE_START_X + 4.0, BELOW_Y, 0)
const ENEMY_ROUTE_END := Vector3(BRIDGE_END_X + 8.0, BELOW_Y, -6.0)
const HAZARD_ROUTE_END := Vector3(BRIDGE_END_X + 12.0, BELOW_Y, 6.0)
const ROUTES_CONVERGE := Vector3(BRIDGE_END_X + 16.0, BELOW_Y, 0)

# Endo junction and shelter
const JUNCTION_POS := Vector3(BRIDGE_END_X + 18.0, BELOW_Y, 0)
const SHELTER_SIZE := Vector3(6, 3, 5)
# Aster's schematics cover the main facility out through Endo's junction (and its
# shelter); past this X the corridors are maintenance with no blueprints, so the
# data overlay goes dark.
const MAIN_FACILITY_MAX_X := JUNCTION_POS.x + SHELTER_SIZE.x

# Ferrolure gauntlet
const GAUNTLET_POS := Vector3(BRIDGE_END_X + 30.0, BELOW_Y, 0)
const FERROLURE_POS := Vector3(BRIDGE_END_X + 28.0, BELOW_Y + 0.3, 4.0)
const GAUNTLET_EXIT := Vector3(BRIDGE_END_X + 42.0, BELOW_Y, 0)
const FERROLURE_DURATION := 18.0

# --- Chunk dispatch ---

func _build_chunk(chunk_name: String, parent: Node3D) -> void:
	match chunk_name:
		"elevator": _build_elevator_chunk(parent)
		"bridge": _build_bridge_chunk(parent)
		"below": _build_below_chunk(parent)
		"junction": _build_junction_chunk(parent)
		"gauntlet": _build_gauntlet_chunk(parent)

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

	_player = _create_player_character("Peris", Color(0.8, 0.5, 0.35))
	_player.position = PERIS_START
	chars.add_child(_player)
	_peris_node = _player

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

	_endo = _create_npc("Endo", Color(0.4, 0.67, 0.53))
	_endo.position = Vector3(JUNCTION_POS.x + 3, BELOW_Y + 0.5, -2)
	_endo.visible = false
	chars.add_child(_endo)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 3.5, 2.5))
		# Keep the view inside the elevator: pan / edge-scroll can't push the
		# look-at past the walls. Cleared when the corridor opens up.
		if _camera != null and _camera.has_method("set_look_bounds"):
			var hx := ELEVATOR_SIZE.x / 2.0
			var hz := ELEVATOR_SIZE.z / 2.0
			_camera.set_look_bounds(Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, hz))

func _register_characters() -> void:
	_register_gs_character("peris", _peris_node, 2.5)
	_register_gs_character("aster", _aster_node, 2.5)
	_register_gs_character("eu1", _escort_1, 2.0)
	_register_gs_character("eu2", _escort_2, 2.0)
	_aster_node.set_move_enabled(false)

func _setup_ui() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "GameHUD"
	_hud.set_script(preload("res://scripts/ui/game_hud.gd"))
	add_child(_hud)
	_hud.add_portrait("peris", "Peris", Color(1.0, 0.67, 0.27))
	_hud.add_portrait("aster", "Aster", Color(0.29, 0.62, 1.0))
	_hud.set_selected_portraits(_selected_character_ids)
	_hud.set_portrait_stat("peris", "hp", 100)
	_hud.set_portrait_stat("aster", "hp", 100)
	_hud.set_portrait_status("aster", "downed")
	_hud.set_portrait_stat("aster", "sta", 0)
	_hud.show_pause_toggle(false)
	_hud.pause_toggled.connect(_on_pause_toggled)
	_hud.add_ability("emp", "EMP", "E", Color(0.29, 0.62, 1.0))
	_hud.set_ability_state("emp", "disabled")
	_hud.ability_pressed.connect(func(id: String):
		if id == "emp":
			_on_emp_pressed()
	)
	_hud.character_selection_changed.connect(_on_character_selected)

	# Door button changes behavior after EMP.
	_exit_button = preload("res://scenes/game/interactable.tscn").instantiate()
	_exit_button.name = "ExitButton"
	_exit_button.description = "Door Button"
	_exit_button.one_shot = false
	_exit_button.dwell_time = 0.5
	_exit_button.tutorial_label = "OPEN"
	_exit_button.interaction_enabled = false
	_exit_button.monitoring = false
	_exit_button.monitorable = false
	_exit_button.visible = false
	_exit_button.position = Vector3(ELEVATOR_SIZE.x / 2.0 - 0.3, 1.0, 1.5)
	add_child(_exit_button)
	_exit_button.interacted.connect(_on_exit_button_pressed)
	_set_exit_button_interactable(false)

func _begin() -> void:
	_player.set_move_enabled(false)
	_fade_rect.color = Color(0, 0, 0, 1)
	if start_chunk != "":
		_load_chunk(start_chunk)
		_player.set_move_enabled(true)
		_fade_rect.color = Color(0, 0, 0, 0)
		match start_chunk:
			"junction":
				_player.global_position = Vector3(JUNCTION_POS.x, BELOW_Y + 0.5, 0)
				_start_junction_arrive()
			"gauntlet":
				_player.global_position = Vector3(GAUNTLET_POS.x, BELOW_Y + 0.5, 0)
				_start_gauntlet()
			"bridge":
				_load_chunk("below")
				_player.global_position = Vector3(0, 0.5, 0)
				_start_bridge()
			_:
				_player.global_position = Vector3.ZERO
		return
	_scheduler.schedule_after(1.0, _start_consciousness_fragments, "fragments")

func _compute_speed() -> float:
	return 10.0 if Input.is_action_pressed("fast_forward") else 1.0

func _on_process(delta: float, spd: float) -> void:
	# Intro + outro fades are driven off the scheduler tick (not wall-clock tweens)
	# so they speed with F in lockstep with their scheduled step transitions.
	if _current_step == "complete":
		_update_fade_out(Color(0.02, 0.02, 0.03), 2.0)
	elif _current_step == "consciousness_fragments":
		_update_consciousness_fade()
	elif _current_step == "fade_in":
		_update_fade_in(FADE_IN_DURATION)

	# Aster's data overlay maps the main facility, where blueprints exist. It stays
	# active out to Endo's junction; past it is maintenance with no schematic, so the
	# overlay reads nothing there. Gating on Aster's position keeps it lit through the
	# whole bridge → fall → junction stretch and dark only once she's past the junction.
	if _perception_mode == "data" and _perception_quad and is_instance_valid(_perception_quad):
		var aster_x := _aster_node.global_position.x
		if _game_state and _game_state.characters.has("aster"):
			aster_x = _game_state.get_position("aster").x
		_perception_quad.visible = aster_x <= MAIN_FACILITY_MAX_X

	# Emergency light pulse.
	if _emergency_light and is_instance_valid(_emergency_light):
		_emergency_light.light_energy = 1.5 + sin(Time.get_ticks_msec() * 0.003) * 0.5

	# Floor indicator flicker.
	if _indicator_b_label and is_instance_valid(_indicator_b_label):
		_indicator_timer += delta * spd
		if _indicator_timer > 0.3:
			_indicator_timer = 0.0
			_indicator_b_label.visible = not _indicator_b_label.visible

	# Stunned escort flicker.
	if _unit_1_stunned and _escort_1:
		_escort_1.visible = int(Time.get_ticks_msec() / 100) % 2 == 0
	if _unit_2_stunned and _escort_2:
		_escort_2.visible = int(Time.get_ticks_msec() / 100) % 2 == 0

	# Sync EMP cooldown display.
	if _emp_cooldown_end > 0:
		var remaining := maxf(0, _emp_cooldown_end - _scheduler.get_current_tick())
		_hud.set_ability_state("emp", "cooldown", remaining)
		if remaining <= 0:
			_emp_cooldown_end = 0.0
			_hud.set_ability_state("emp", "ready")

	# Visual patrol drift.
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy.rotation.y += delta * spd * 0.3

	# Iron patches hurt on contact.
	if not _game_over and not _iron_patches.is_empty():
		for pair in [["aster", _aster_node], ["peris", _peris_node]]:
			var cid: String = pair[0]
			var cnode: Node3D = pair[1]
			if not cnode:
				continue
			var hp: float = _aster_hp if cid == "aster" else _peris_hp
			if hp <= 0:
				continue
			var cpos := cnode.global_position
			for patch in _iron_patches:
				var ppos: Vector3 = patch.pos
				var psz: Vector3 = patch.size
				if absf(cpos.x - ppos.x) < psz.x / 2.0 and absf(cpos.z - ppos.z) < psz.z / 2.0:
					var dmg := IRON_DAMAGE_PER_SEC * delta * spd
					if cid == "aster":
						_aster_hp = maxf(0.0, _aster_hp - dmg)
						_hud.set_portrait_stat("aster", "hp", _aster_hp)
						if _aster_hp <= 0:
							_hud.set_portrait_status("aster", "downed")
					else:
						_peris_hp = maxf(0.0, _peris_hp - dmg)
						_hud.set_portrait_stat("peris", "hp", _peris_hp)
						if _peris_hp <= 0:
							_hud.set_portrait_status("peris", "downed")
					break
		if _aster_hp <= 0 and _peris_hp <= 0:
			_start_game_over()

	# Approach gate
	if _current_step == "approach_aster":
		var peris_pos := _game_state.get_position("peris")
		if (_aster_wake_interactable == null or not is_instance_valid(_aster_wake_interactable)) and peris_pos.distance_to(ASTER_POS) < 1.8:
			_tutorial_prompt.hide_prompt()
			_player.set_move_enabled(false)
			_start_wake_aster()

	# Multi-select gate: both near the door exit
	if _current_step == "multiselect_tutorial":
		var exit_gate := Vector3(ELEVATOR_SIZE.x / 2.0, 0, 0)
		var pp := _game_state.get_position("peris")
		var ap := _game_state.get_position("aster")
		var peris_at_door := pp.distance_to(exit_gate) < 2.5
		var aster_at_door := ap.distance_to(exit_gate) < 2.5
		if peris_at_door and aster_at_door and _multiselect_has_required_pair():
			_start_corridor()
		elif peris_at_door or aster_at_door:
			_show_multiselect_together_hint()

	# Route convergence gate: player reached the junction area
	if _current_step == "route_choice":
		var player_pos := _game_state.get_position("aster")
		if player_pos.x > ROUTES_CONVERGE.x - 2.0:
			_tutorial_prompt.hide_prompt()
			_player.set_move_enabled(false)
			_start_bridge_collapse()

	# Gauntlet exit gate: player passed the enemies
	if _current_step == "gauntlet":
		var player_pos := _game_state.get_position("aster")
		if player_pos.x > GAUNTLET_EXIT.x - 2.0:
			_tutorial_prompt.hide_prompt()
			_player.set_move_enabled(false)
			_complete()

# --- Input ---

# Pause (Space) and EMP (E) arrive as HUD signals (pause_toggled / ability_pressed)
# mapped from the input map by GameHUD. Only the elevator-specific character
# switch / multi-select shortcuts are handled here, via input actions.
func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("route") and _current_step in ["hack_tutorial", "multiselect_tutorial"]:
		_switch_character()
	elif _current_step == "multiselect_tutorial":
		var char_id := ""
		if event.is_action_pressed("select_primary"):
			char_id = "peris"
		elif event.is_action_pressed("select_secondary"):
			char_id = "aster"
		if char_id == "":
			return
		var key_event := event as InputEventKey
		if key_event != null and (key_event.ctrl_pressed or key_event.shift_pressed):
			_hud.toggle_portrait_selected(char_id)
		else:
			_select_character(char_id)

func _toggle_pause() -> void:
	if _scheduler.is_paused():
		if _emp_pause_locked and not _emp_queued:
			_hud.set_paused(true)
			_tutorial_prompt.show_prompt("[E] - queue Aster's EMP before unpausing")
			return
		if _current_step == "multiselect_tutorial" and not _multiselect_has_required_pair():
			_hud.set_paused(true)
			_tutorial_prompt.show_prompt("Ctrl-click Aster's portrait to select both, then move together")
			_show_multiselect_together_hint()
			return
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
		if _emp_pause_locked and not _emp_queued:
			_hud.set_paused(true)
			_tutorial_prompt.show_prompt("[E] - queue Aster's EMP before unpausing")
			return
		if _current_step == "multiselect_tutorial" and not _multiselect_has_required_pair():
			_hud.set_paused(true)
			_tutorial_prompt.show_prompt("Ctrl-click Aster's portrait to select both, then move together")
			_show_multiselect_together_hint()
			return
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
			_emp_pause_locked = false
			_hud.set_ability_state("emp", "queued")
			_tutorial_prompt.show_prompt("[Space] - unpause to fire queued EMP")
		else:
			_fire_emp_both()

func _fire_emp_both() -> void:
	_emp_pause_locked = false
	_emp_queued = false
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
	# Reboot and hack tutorial on the scheduler
	_scheduler.schedule_after(30.0, _on_reboot, "reboot")
	_scheduler.schedule_after(1.5, _start_doors_unlocked, "doors_unlock")

func _on_reboot() -> void:
	if not _reboot_active:
		return
	_unit_1_stunned = false
	_unit_2_stunned = false
	if _escort_1:
		_escort_1.visible = true
	if _escort_2:
		_escort_2.visible = true
	if _current_step in ["emp_tutorial", "doors_unlocked", "multiselect_tutorial"]:
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

func _set_exit_button_interactable(active: bool) -> void:
	if _exit_button == null:
		return
	if active and _exit_button.has_method("reset"):
		_exit_button.reset()
	_exit_button.visible = active
	if _exit_button.has_method("set_interaction_enabled"):
		_exit_button.set_interaction_enabled(active)
	else:
		_exit_button.monitoring = active
		_exit_button.monitorable = active
	if not active:
		if _exit_button.has_method("hide_tutorial_label"):
			_exit_button.hide_tutorial_label()
		if _exit_button.has_method("cancel_queued_feedback"):
			_exit_button.cancel_queued_feedback()

func _switch_character() -> void:
	var next_id: String = _hud.get_next_portrait_id(_active_character)
	_select_character(next_id)

func _select_character(id: String, preserve_multi_selection := false) -> void:
	if not (id in ["peris", "aster"]):
		return
	if id == "peris":
		_player = _peris_node
		_camera.target = _peris_node
	else:
		_player = _aster_node
		_camera.target = _aster_node
	_active_character = id
	if not preserve_multi_selection:
		_selected_character_ids = [id]
	elif not _selected_character_ids.has(id):
		_selected_character_ids.append(id)
	_suppress_hud_character_signal = true
	_hud.set_active_portrait(id, preserve_multi_selection)
	if preserve_multi_selection:
		_hud.set_selected_portraits(_selected_character_ids)
	_suppress_hud_character_signal = false
	_apply_character_control_selection()

func _on_character_selected(selected_ids: Array) -> void:
	if _suppress_hud_character_signal:
		return
	var sanitized := _sanitize_character_selection(selected_ids)
	if sanitized.is_empty():
		sanitized = [_active_character]
	_selected_character_ids = sanitized
	var preferred := sanitized[0]
	if preferred != _active_character and _current_step in ["multiselect_tutorial", "hack_tutorial"]:
		_select_character(preferred, bool(_hud.get("_multi_select")))
	else:
		_apply_character_control_selection()
	if _current_step == "multiselect_tutorial":
		_update_multiselect_tutorial_prompt()

func _sanitize_character_selection(selected_ids: Array) -> Array[String]:
	var sanitized: Array[String] = []
	for raw_id in selected_ids:
		var id := str(raw_id)
		if not (id in ["peris", "aster"]):
			continue
		if sanitized.has(id):
			continue
		sanitized.append(id)
	return sanitized

func _apply_character_control_selection() -> void:
	var group_control := _hud != null and bool(_hud.get("_multi_select")) and _selected_character_ids.size() > 1
	# In group control the party moves as one: the active character's player drives
	# the click and issues a spread party move (distinct cells, no overlap), so only
	# it is move-enabled — the other member is carried by the party move, not its
	# own click. Single control: only the active character moves, no group move.
	if group_control and _game_state != null:
		_game_state.set_party(_sanitize_character_selection(_selected_character_ids))
	for entry in [["peris", _peris_node], ["aster", _aster_node]]:
		var cid: String = entry[0]
		var node = entry[1]
		if node == null:
			continue
		var is_active: bool = _active_character == cid
		node.set_move_enabled(is_active)
		if node.has_method("set") or "group_move" in node:
			node.set("group_move", group_control and is_active)

func _multiselect_has_required_pair() -> bool:
	return _selected_character_ids.has("peris") and _selected_character_ids.has("aster")

func _update_multiselect_tutorial_prompt() -> void:
	if _multiselect_has_required_pair():
		# Queue the move while paused, then unpause to run through together.
		_tutorial_prompt.show_prompt("Both selected. Click the open doorway to set your path, then press [Space].")
	else:
		_tutorial_prompt.show_prompt("Ctrl-click Aster's portrait to select both Peris and Aster.")

func _show_multiselect_together_hint() -> void:
	# The prompt carries the instruction; Aster says his line once (no repeated nag).
	_update_multiselect_tutorial_prompt()

# --- Event steps ---

# Consciousness-fragment intro fade phases (scheduler ticks). Two fragments, each
# fade-in -> hold -> fade-out; the second starts at FRAG2_TICK. Total 5.8 ticks.
const CONSCIOUSNESS_FADE := 0.8
const CONSCIOUSNESS_HOLD := 1.5
const CONSCIOUSNESS_FADE_OUT := 0.6
const CONSCIOUSNESS_FRAG2_TICK := 2.9
const FADE_IN_DURATION := 1.0

func _start_consciousness_fragments() -> void:
	_enter_step("consciousness_fragments")
	# Hide everything except Peris initially
	_emergency_light.light_energy = 0.0
	if _aster_node:
		_aster_node.visible = false
	for unit in [_escort_1, _escort_2]:
		if unit:
			unit.visible = false

	# The two consciousness-fragment fades are driven per-frame off the scheduler
	# tick (see _update_consciousness_fade in _on_process), so holding F speeds the
	# fades and the fade_in transition together — a wall-clock tween here would lag
	# the (scheduler-timed) transition under fast-forward and tear the fade.
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_start_tick = _scheduler.get_current_tick()
	# Fragment 2 reveals Aster at the start of its fade-in (after fragment 1).
	_scheduler.schedule_after(CONSCIOUSNESS_FRAG2_TICK, func():
		if _aster_node:
			_aster_node.visible = true
	, "frag2_reveal")
	_scheduler.schedule_after(5.8, _start_fade_in, "fade_in")

## Per-frame alpha for the two-fragment consciousness intro, read off the
## scheduler tick so fast-forward scales it with the scheduled transitions.
func _update_consciousness_fade() -> void:
	if _fade_rect == null:
		return
	var elapsed: float = _scheduler.get_current_tick() - _fade_start_tick
	# Each fragment: fade-in (black->clear) -> hold (clear) -> fade-out (clear->black).
	var local := elapsed
	if elapsed >= CONSCIOUSNESS_FRAG2_TICK:
		local = elapsed - CONSCIOUSNESS_FRAG2_TICK
	var alpha := 1.0
	if local < CONSCIOUSNESS_FADE:
		alpha = 1.0 - clampf(local / CONSCIOUSNESS_FADE, 0.0, 1.0)
	elif local < CONSCIOUSNESS_FADE + CONSCIOUSNESS_HOLD:
		alpha = 0.0
	else:
		var out_t := local - (CONSCIOUSNESS_FADE + CONSCIOUSNESS_HOLD)
		alpha = clampf(out_t / CONSCIOUSNESS_FADE_OUT, 0.0, 1.0)
	_fade_rect.color.a = alpha

func _start_fade_in() -> void:
	# Scheduler-driven from consciousness_fragments. If a test force-fired straight to
	# waking, this scheduled call is stale — no-op so it can't drag the step backward.
	if _current_step != "consciousness_fragments":
		return
	_enter_step("fade_in")
	# Full reveal: escort units, full lighting
	for unit in [_escort_1, _escort_2]:
		if unit:
			unit.visible = true
	_emergency_light.light_energy = 3.0
	# Scheduler-driven fade-in (see _on_process) so it speeds with F in lockstep
	# with the scheduled waking transition.
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(1.5, _start_waking, "waking")

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
	_show_aster_wake_interactable()

func _start_wake_aster() -> void:
	_enter_step("wake_aster")
	_clear_aster_wake_interactable()
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

func _show_aster_wake_interactable() -> void:
	if _aster_wake_interactable != null and is_instance_valid(_aster_wake_interactable):
		return
	var parent := _chunks.get("elevator", null) as Node3D
	if parent == null:
		parent = find_child("Environment", false, false) as Node3D
	var zone_pos := ASTER_POS + Vector3(0.0, 0.05, 0.0)
	_aster_wake_interactable = _create_interactable(parent, zone_pos, "AsterWakeZone", 2.0, 0.6, "Wake", true)
	_aster_wake_interactable.description = "Aster"
	_aster_wake_interactable.required_character = "peris"
	_aster_wake_interactable.active_character = "peris"
	_aster_wake_interactable.interacted.connect(_on_aster_wake_interacted)
	_aster_wake_interactable.call_deferred("show_tutorial_label")

func _clear_aster_wake_interactable() -> void:
	if _aster_wake_interactable == null or not is_instance_valid(_aster_wake_interactable):
		_aster_wake_interactable = null
		return
	_aster_wake_interactable.visible = false
	_aster_wake_interactable.monitoring = false
	_aster_wake_interactable.monitorable = false
	if _aster_wake_interactable.has_method("hide_tutorial_label"):
		_aster_wake_interactable.hide_tutorial_label()
	_aster_wake_interactable.queue_free()
	_aster_wake_interactable = null

func _on_aster_wake_interacted() -> void:
	if _current_step != "approach_aster":
		return
	_tutorial_prompt.hide_prompt()
	_player.set_move_enabled(false)
	_start_wake_aster()

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
	# Device access restored; Aster's overlay activates.
	_setup_perception("data", _aster_node)
	DialogueData.say_to(_dialogue, "elevator.system.restored")
	DialogueData.say_to(_dialogue, "elevator.aster.overlay")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0.5, _start_units_activate, "units_activate"),
		CONNECT_ONE_SHOT
	)

func _start_units_activate() -> void:
	_enter_step("units_activate")
	# Escorts stop short so EMP does not fire at contact range.
	var party_center := _get_emp_party_center()
	_escort_1.walk_to(_get_emp_guard_standoff_pos("eu1", _escort_1, party_center))
	_escort_2.walk_to(_get_emp_guard_standoff_pos("eu2", _escort_2, party_center))
	_camera.shake(0.2, 6.0)
	_dialogue_chain(
		["elevator.unit.protocol", "elevator.aster.device"],
		_start_emp_tutorial
	)

func _get_emp_party_center() -> Vector3:
	var peris_pos := _game_state.get_position("peris") if _game_state and _game_state.characters.has("peris") else _peris_node.global_position
	var aster_pos := _game_state.get_position("aster") if _game_state and _game_state.characters.has("aster") else _aster_node.global_position
	return (peris_pos + aster_pos) * 0.5

func _get_emp_guard_standoff_pos(guard_id: String, guard_node: Node3D, party_center: Vector3) -> Vector3:
	var guard_pos := _game_state.get_position(guard_id) if _game_state and _game_state.characters.has(guard_id) else guard_node.global_position
	var away_from_party := guard_pos - party_center
	away_from_party.y = 0.0
	if away_from_party.length() < 0.01:
		away_from_party = Vector3.LEFT
	var standoff := party_center + away_from_party.normalized() * EMP_GUARD_STANDOFF_DISTANCE
	standoff.y = guard_pos.y
	return standoff

func _start_emp_tutorial() -> void:
	_enter_step("emp_tutorial")
	# EMP belongs to Aster.
	_select_character("aster")
	_emp_pause_locked = true
	_emp_queued = false
	_hud.set_ability_state("emp", "ready")
	_tutorial_prompt.show_prompt("[E] - queue Aster's EMP")
	_scheduler.pause()
	_hud.set_paused(true)

func _start_emp_tutorial_2() -> void:
	_enter_step("emp_tutorial_2")

func _start_doors_unlocked() -> void:
	_enter_step("doors_unlocked")
	_reboot_active = false
	_tutorial_prompt.hide_prompt()
	# EMP disables the door lock.
	_set_exit_button_interactable(true)
	_exit_button.one_shot = true
	_exit_button.tutorial_label = "OPEN"
	_exit_button.show_tutorial_label()
	DialogueData.say_to(_dialogue, "elevator.system.override")
	_dialogue.dialogue_finished.connect(_start_doors_open, CONNECT_ONE_SHOT)
	# Exit button remains a fallback if auto-advance misses.
	if _exit_button.interacted.is_connected(_on_exit_button_pressed):
		_exit_button.interacted.disconnect(_on_exit_button_pressed)
	_exit_button.interacted.connect(_start_doors_open, CONNECT_ONE_SHOT)

func _start_doors_open() -> void:
	if not _enter_step("doors_open"):
		return
	_set_exit_button_interactable(false)
	if _door_panel_a and _door_panel_b:
		var tween := create_tween()
		tween.tween_property(_door_panel_a, "position:z", -1.5, 1.5)
		tween.parallel().tween_property(_door_panel_b, "position:z", 1.5, 1.5)
	var outside_light := OmniLight3D.new()
	outside_light.position = Vector3(3.5, 1.5, 0)
	outside_light.light_color = Color(0.4, 0.4, 0.5)
	outside_light.light_energy = 2.0
	outside_light.omni_range = 6.0
	find_child("Environment", false, false).add_child(outside_light)
	_scheduler.schedule_after(2.0, _start_multiselect_tutorial, "multiselect")

func _start_multiselect_tutorial() -> void:
	_enter_step("multiselect_tutorial")
	_selected_character_ids = ["peris"]
	_suppress_hud_character_signal = true
	_hud.set_multi_select_enabled(true)
	_hud.set_selected_portraits(_selected_character_ids)
	_suppress_hud_character_signal = false
	# Switch to Peris; both need to reach the exit.
	_select_character("peris", true)
	_scheduler.pause()
	_hud.set_paused(true)
	DialogueData.say_to(_dialogue, "elevator.aster.multiselect")
	_dialogue.dialogue_finished.connect(func():
		_tutorial_prompt.show_prompt("[Tab] — switch  [Space] — unpause")
	, CONNECT_ONE_SHOT)
	_dialogue.dialogue_finished.connect(_update_multiselect_tutorial_prompt, CONNECT_ONE_SHOT)

func _start_corridor() -> void:
	_enter_step("corridor")
	_tutorial_prompt.hide_prompt()
	# Leaving the elevator: the view can follow the party out into the corridor.
	if _camera != null and _camera.has_method("clear_look_bounds"):
		_camera.clear_look_bounds()
	_load_chunk("bridge")
	_load_chunk("below")
	var exit_pos := Vector3(ELEVATOR_SIZE.x / 2.0 + 3.0, 0, 0)
	_game_state.command_move_to_pos("aster", exit_pos)
	_game_state.command_move_to_pos("peris", exit_pos + Vector3(0, 0, 1.0))
	_dialogue_chain([
		"elevator.peris.not_supposed",
		"elevator.aster.no_service",
	], func(): _scheduler.schedule_after(2.0, _start_bridge, "bridge"))

func _start_bridge() -> void:
	_enter_step("bridge")
	var bridge_pos := Vector3(ELEVATOR_SIZE.x / 2.0 + 12.0, 0, 0)
	_game_state.command_move_to_pos("aster", bridge_pos + Vector3(1.0, 0, 0))
	_game_state.command_move_to_pos("peris", bridge_pos)
	_dialogue_chain([
		"elevator.peris.bodies",
		"elevator.aster.logs",
		"elevator.aster.ahead",
	], func(): _scheduler.schedule_after(1.0, _start_route_fork_dialogue, "route_fork"))

# --- Bridge Collapse ---

func _start_bridge_collapse() -> void:
	_enter_step("bridge_collapse")
	_fall_landed_fired = false
	_peris_node.set_move_enabled(false)
	_aster_node.set_move_enabled(false)
	_game_state.command_stop("aster")
	_game_state.command_stop("peris")
	if _escort_1:
		_escort_1.visible = false
	if _escort_2:
		_escort_2.visible = false
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
	if bridge_floor:
		tween.tween_property(bridge_floor, "position:y", BELOW_Y, fall_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(bridge_floor, "rotation:x", 0.15, fall_duration * 0.8)
	for char_node in [_peris_node, _aster_node]:
		tween.tween_property(char_node, "position:y", BELOW_Y + 0.5, fall_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_camera, "follow_offset:y", _camera.follow_offset.y + BELOW_Y, fall_duration * 1.1)
	# The fall animation is a cosmetic tween; the landing (which repositions the party
	# in GameState and advances the step) rides the scheduler so fast-forward matches.
	_scheduler.schedule_after(fall_duration * 1.1, _on_fall_landed, "fall_landed")

func _on_fall_landed() -> void:
	# Fires from the scheduled landing (or a test force-fire) — exactly once.
	if _fall_landed_fired:
		return
	_fall_landed_fired = true
	_camera.shake(0.3, 6.0)
	for char_id in ["peris", "aster"]:
		var pos: Vector3 = _game_state.get_position(char_id)
		_game_state.characters[char_id].position = Vector3(pos.x, BELOW_Y + 0.5, pos.z)
	_unload_chunk("elevator")
	_unload_chunk("bridge")
	_emergency_light = null
	_indicator_b_label = null
	_floor_indicator = null
	_door_panel_a = null
	_door_panel_b = null
	_no_exit_label = null
	_scheduler.schedule_after(1.0, _start_fallen, "fallen")

func _start_fallen() -> void:
	_enter_step("fallen")
	_dialogue_chain([
		"elevator.peris.hurt",
		"elevator.aster.sublevel",
	], func(): _scheduler.schedule_after(1.0, _start_climb_attempt, "climb"))

func _start_climb_attempt() -> void:
	_enter_step("climb_attempt")
	# Establish that the bridge cannot be retraced.
	_dialogue_chain([
		"elevator.aster.climb",
		"elevator.peris.climb",
		"elevator.aster.another_way",
	], func():
		_show_climb_interactable()
	)

func _show_climb_interactable() -> void:
	if _climb_interactable != null and is_instance_valid(_climb_interactable):
		return
	var parent := _chunks.get("below", null) as Node3D
	if parent == null:
		parent = find_child("Environment", false, false) as Node3D
	var zone_pos := Vector3(BRIDGE_START_X + 5.0, BELOW_Y + 0.05, 0.0)
	_climb_interactable = _create_interactable(parent, zone_pos, "ClimbPromptZone", 2.4, 0.8, "Climb", true)
	_climb_interactable.description = "Collapsed Bridge"
	_climb_interactable.interacted.connect(_on_climb_prompt_interacted)
	_climb_interactable.call_deferred("show_tutorial_label")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Climb zone - check the collapsed bridge")

func _on_climb_prompt_interacted() -> void:
	if _current_step != "climb_attempt":
		return
	_tutorial_prompt.hide_prompt()
	if _climb_interactable != null and is_instance_valid(_climb_interactable):
		_climb_interactable.queue_free()
		_climb_interactable = null
	_scheduler.schedule_after(0.2, _start_junction_arrive, "junction_arrive")

func _start_route_fork_dialogue() -> void:
	_enter_step("route_fork_dialogue")
	_player.set_move_enabled(true)
	_dialogue_chain([
		"elevator.aster.two_paths",
	], func(): _scheduler.schedule_after(1.5, _start_route_choice, "route_choice"))

# --- Route Choice ---

func _start_route_choice() -> void:
	_enter_step("route_choice")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move — choose a path")

# --- Junction / Shelter ---

func _start_junction_arrive() -> void:
	_enter_step("junction_arrive")
	_load_chunk("junction")
	_unload_chunk("below")
	_enemies.clear()
	_player.set_move_enabled(true)
	# Player explores the junction. Peris tending the dormant plant triggers dusk + Endo.

func _start_endo_enters() -> void:
	_enter_step("endo_enters")
	# Endo arrives from a side entrance
	_endo.visible = true
	_endo.position = Vector3(JUNCTION_POS.x + SHELTER_SIZE.x / 2.0 + 1.0, BELOW_Y + 0.5, 0)
	_register_gs_character("endo", _endo, 2.5)
	# Endo walks into the junction
	var junction_center := Vector3(JUNCTION_POS.x, BELOW_Y + 0.5, 0)
	_game_state.command_move_to_pos("endo", junction_center)
	_show_marker(Vector3(JUNCTION_POS.x, BELOW_Y + 2.5, 0), "SHELTER")
	_player.set_move_enabled(false)
	_dialogue_chain([
		"junction.endo.beckon",
		"junction.peris.who",
		"junction.aster.endo_read",
	], func(): _scheduler.schedule_after(1.0, _start_endo_shelter, "shelter"))

func _start_endo_shelter() -> void:
	_enter_step("endo_shelter")
	_player.set_move_enabled(false)
	# Endo walks to the drink container
	var container_pos := Vector3(JUNCTION_POS.x + 1.5, BELOW_Y + 0.5, -1.0)
	_game_state.command_move_to_pos("endo", container_pos)
	_game_state.character_arrived.connect(_on_endo_at_container, CONNECT_ONE_SHOT)

func _on_endo_at_container(id: String) -> void:
	if id != "endo":
		# Wrong character arrived; re-listen.
		_game_state.character_arrived.connect(_on_endo_at_container, CONNECT_ONE_SHOT)
		return
	# Dwell indicator while Endo picks up drink
	_show_marker(_endo.global_position + Vector3(0, 1.5, 0), "...")
	_scheduler.schedule_after(1.5, _endo_pickup_drink, "endo_pickup")

func _endo_pickup_drink() -> void:
	_clear_markers()
	# Reparent drink to Endo so it moves with him
	if _drink_mesh and is_instance_valid(_drink_mesh):
		var global_pos := _drink_mesh.global_position
		_drink_mesh.get_parent().remove_child(_drink_mesh)
		_endo.add_child(_drink_mesh)
		_drink_mesh.position = Vector3(0, 1.2, 0.3)
	# WATER marker on the drink
	_show_marker(Vector3(JUNCTION_POS.x + 1.5, BELOW_Y + 1.5, -1.0), "WATER")
	# Endo walks back to the party
	var party_pos := Vector3(JUNCTION_POS.x - SHELTER_SIZE.x / 2.0 + 1.0, BELOW_Y + 0.5, 0)
	_game_state.command_move_to_pos("endo", party_pos)
	_game_state.character_arrived.connect(_on_endo_delivered, CONNECT_ONE_SHOT)

func _on_endo_delivered(id: String) -> void:
	if id != "endo":
		_game_state.character_arrived.connect(_on_endo_delivered, CONNECT_ONE_SHOT)
		return
	_clear_markers()
	_dialogue_chain([
		"junction.endo.drink",
		"junction.peris.stomach",
		"junction.endo.rest",
	], func():
		_scheduler.schedule_after(2.0, _start_night_watch, "night_watch")
	)

func _spawn_enemy(id: String, pos: Vector3, parent: Node3D) -> Enemy:
	var enemy := Enemy.new()
	enemy.name = id
	enemy.game_state = _game_state
	enemy.char_id = id
	enemy.detection_range = 6.0
	enemy._detection_targets = ["aster", "peris"]
	enemy.position = pos
	parent.add_child(enemy)
	_register_gs_character(id, enemy, enemy.move_speed, {"detection_range": enemy.detection_range})
	enemy.hit_target.connect(_on_enemy_hit)
	enemy.activate()
	_enemies.append(enemy)
	_enemy_count += 1
	return enemy

func _on_enemy_hit(target_id: String, damage: float) -> void:
	if _game_over:
		return
	# Check i-frames
	var now := _scheduler.get_current_tick()
	if _iframes.has(target_id) and now < _iframes[target_id]:
		return
	_iframes[target_id] = now + 1.0
	# Apply damage
	if target_id == "aster" and _aster_hp > 0:
		_aster_hp = maxf(0.0, _aster_hp - damage)
		_hud.set_portrait_stat("aster", "hp", _aster_hp)
		if _aster_hp <= 0:
			_hud.set_portrait_status("aster", "downed")
	elif target_id == "peris" and _peris_hp > 0:
		_peris_hp = maxf(0.0, _peris_hp - damage)
		_hud.set_portrait_stat("peris", "hp", _peris_hp)
		if _peris_hp <= 0:
			_hud.set_portrait_status("peris", "downed")
	# Flash the hit character white briefly
	var target_node: Node3D = _aster_node if target_id == "aster" else _peris_node
	if target_node:
		var flash := create_tween()
		flash.tween_property(target_node, "modulate", Color(1, 1, 1, 0.4), 0.1)
		flash.tween_property(target_node, "modulate", Color(1, 1, 1, 1), 0.3)
	if _aster_hp <= 0 and _peris_hp <= 0:
		_start_game_over()

func _show_marker(pos: Vector3, text: String) -> void:
	var lbl := Label3D.new()
	lbl.name = "Marker_" + text
	lbl.text = text
	lbl.font_size = 28
	lbl.pixel_size = 0.008
	lbl.modulate = Color(0.4, 0.6, 0.8, 0.7)
	lbl.outline_modulate = Color(0, 0, 0, 0.5)
	lbl.outline_size = 3
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = pos
	find_child("Environment", false, false).add_child(lbl)

func _clear_markers() -> void:
	var env: Node = find_child("Environment", false, false)
	for child in env.get_children():
		if child is Label3D and child.name.begins_with("Marker_"):
			child.queue_free()

func _start_night_watch() -> void:
	_enter_step("night_watch")
	# Darken the world for nightfall.
	var env_node: Node = find_child("Environment", false, false)
	var we: WorldEnvironment = env_node.find_child("*", false, false) as WorldEnvironment if env_node else null
	for child in env_node.get_children():
		if child is WorldEnvironment:
			we = child
			break
	if we and we.environment:
		we.environment.ambient_light_energy = 0.1

	# Flicker the shelter interior light
	var shelter_light: OmniLight3D
	var junction_chunk: Node3D = _chunks.get("junction")
	if junction_chunk:
		shelter_light = junction_chunk.find_child("ShelterLight", false, false)

	# Spawn monster eye pairs outside both windows
	_monster_eyes.clear()
	var ground_y := BELOW_Y
	var sx := JUNCTION_POS.x
	var sd := SHELTER_SIZE.z
	for side_idx in range(2):
		var side_sign: float = -1.0 if side_idx == 0 else 1.0
		var wz: float = side_sign * (sd / 2.0 + 0.5)
		for i in range(3):
			var pair_x: float = sx - 2.0 + i * 2.5
			for eye_idx in range(2):
				var eye := OmniLight3D.new()
				var eye_offset: float = -0.15 if eye_idx == 0 else 0.15
				eye.position = Vector3(pair_x + eye_offset, ground_y + 1.6, wz)
				eye.light_color = Color(0.95, 0.1, 0.05)
				eye.light_energy = 0.0
				eye.omni_range = 0.8
				find_child("Environment", false, false).add_child(eye)
				_monster_eyes.append(eye)

	# Fade eyes in over 2 seconds
	for eye in _monster_eyes:
		var tween := create_tween()
		tween.tween_property(eye, "light_energy", 0.5 + randf() * 0.3, 2.0 + randf() * 1.0)

	# Shelter light flickers
	if shelter_light:
		_scheduler.schedule_after(3.0, func():
			var flicker := create_tween()
			flicker.tween_property(shelter_light, "light_energy", 1.0, 0.1)
			flicker.tween_property(shelter_light, "light_energy", 2.5, 0.1)
			flicker.tween_property(shelter_light, "light_energy", 0.8, 0.1)
			flicker.tween_property(shelter_light, "light_energy", 2.5, 0.3)
		, "flicker")

	DialogueData.say_to(_dialogue, "junction.night.eyes")
	_scheduler.schedule_after(8.0, _start_dawn, "dawn")

func _start_dawn() -> void:
	_enter_step("dawn")
	# Eyes fade out
	for eye in _monster_eyes:
		if is_instance_valid(eye):
			var tween := create_tween()
			tween.tween_property(eye, "light_energy", 0.0, 2.0)
			tween.tween_callback(eye.queue_free)
	_monster_eyes.clear()
	# Restore ambient light
	var env_node: Node = find_child("Environment", false, false)
	for child in env_node.get_children():
		if child is WorldEnvironment:
			child.environment.ambient_light_energy = 0.5
			break
	DialogueData.say_to(_dialogue, "junction.dawn")
	_dialogue.dialogue_finished.connect(func():
		_scheduler.schedule_after(1.0, _start_morning, "morning")
	, CONNECT_ONE_SHOT)

# --- Morning / Endo Joins ---

func _start_morning() -> void:
	_enter_step("morning")
	_dialogue_chain([
		"junction.morning.trail",
		"junction.endo.stands",
		"junction.peris.coming",
		"junction.aster.ok",
	], func(): _scheduler.schedule_after(1.5, _start_gauntlet, "gauntlet"))

# --- Ferrolure Gauntlet ---

func _start_gauntlet() -> void:
	_enter_step("gauntlet")
	_load_chunk("gauntlet")
	_unload_chunk("junction")
	_player.set_move_enabled(true)
	# Walk party to gauntlet entrance
	var entrance := Vector3(GAUNTLET_POS.x - 6.0, BELOW_Y + 0.5, 0)
	_game_state.command_move_to_pos("aster", entrance)
	_game_state.command_move_to_pos("peris", entrance + Vector3(-1, 0, 1))
	_game_state.command_move_to_pos("endo", entrance + Vector3(-1, 0, -1))
	_dialogue_chain([
		"junction.aster.blocked",
		"junction.peris.ferrolure",
	], func():
		_tutorial_prompt.show_prompt("[Interact] — activate Ferrolure (Peris only)")
	)

func _on_ferrolure_activated() -> void:
	if _ferrolure_active:
		return
	_ferrolure_active = true
	_tutorial_prompt.hide_prompt()
	if _ferrolure_mesh:
		var mat := _ferrolure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 3.0
	# Redirect gauntlet enemies to the ferrolure.
	for enemy in _gauntlet_enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy._detection_targets = []
			enemy._current_target_id = ""
			enemy._change_state("idle")
			if enemy.game_state and enemy.game_state.characters.has(enemy.char_id):
				enemy.game_state.command_move_to_pos(enemy.char_id, FERROLURE_POS)
	_show_marker(FERROLURE_POS + Vector3(0, 1.5, 0), "LURE ACTIVE")
	_dialogue.default_hold_time = 2.0
	DialogueData.say_to(_dialogue, "junction.ferrolure.active")
	_scheduler.schedule_after(FERROLURE_DURATION, _on_ferrolure_expired, "ferrolure_expire")

func _on_ferrolure_expired() -> void:
	_ferrolure_active = false
	_clear_markers()
	if _ferrolure_mesh:
		var mat := _ferrolure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 0.5
	# Restore enemy targeting.
	for enemy in _gauntlet_enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy._detection_targets = ["aster", "peris"]
			enemy._change_state("idle")

func _complete() -> void:
	_enter_step("complete")
	_player.set_move_enabled(false)
	# Fade + scene change ride the scheduler (not a wall-clock tween), so the
	# blackout and the swap fire on the scheduler clock and never race a paused
	# or fast-forwarded sequence. The fade alpha is driven per-frame in
	# _on_process while the step is "complete".
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(2.0, _do_complete_scene_change, "complete_change")

func _do_complete_scene_change() -> void:
	_change_scene_or_record("res://scenes/tutorial/act1.tscn")

# --- Game Over ---

func _start_game_over() -> void:
	if _game_over:
		return
	_game_over = true
	_enter_step("game_over")
	_player.set_move_enabled(false)
	_scheduler.pause()
	# Stop all enemies
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy._change_state("idle")
	# Fade to dark red-black
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color", Color(0.08, 0.02, 0.02, 0.85), 2.0)
	tween.tween_callback(_show_game_over_text)

func _show_game_over_text() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 20
	add_child(overlay)
	var label := Label.new()
	label.text = "We Fell"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color(0.7, 0.25, 0.2, 0.0))
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "theme_override_colors/font_color:a", 1.0, 2.0)

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
	_add_wall(parent, Vector3(start_x + 3.0, 2.0, -2.0), Vector3(7, 4, 0.2), wall_color)
	_add_wall(parent, Vector3(start_x + 3.0, 2.0, 2.0), Vector3(7, 4, 0.2), wall_color)

	var cor_light := OmniLight3D.new()
	cor_light.position = Vector3(start_x + 3.0, 3.0, 0)
	cor_light.light_color = Color(0.3, 0.2, 0.15)
	cor_light.light_energy = 1.5
	cor_light.omni_range = 8.0
	parent.add_child(cor_light)

	# Named for collapse tween.
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

	var bridge_light := OmniLight3D.new()
	bridge_light.position = Vector3(bridge_start + 5.0, 3.0, 0)
	bridge_light.light_color = Color(0.25, 0.18, 0.12)
	bridge_light.light_energy = 1.0
	bridge_light.omni_range = 10.0
	parent.add_child(bridge_light)

func _build_below_chunk(parent: Node3D) -> void:
	var bridge_start := ELEVATOR_SIZE.x / 2.0 + 0.5 + 7.0
	var ground_y := BELOW_Y

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

	_add_corridor_section(parent, Vector3(bridge_start + 5.0, ground_y - 0.05, 0), Vector3(40, 0.1, 16), Color(0.05, 0.05, 0.07))

	# Iron blooms.
	for i in range(4):
		var bloom := OmniLight3D.new()
		bloom.position = Vector3(bridge_start + 1.5 + i * 3.0, ground_y + 1.0, randf_range(-4, 4))
		bloom.light_color = Color(0.7, 0.3, 0.1)
		bloom.light_energy = 0.5
		bloom.omni_range = 3.0
		parent.add_child(bloom)

	# Chelators patrol the ecology walls.
	var chelator_ids: Array[String] = []
	for i in range(6):
		var cid := "chelator_%d" % i
		chelator_ids.append(cid)
		var enemy := _spawn_enemy(cid,
			Vector3(bridge_start + 1.0 + i * 2.0, ground_y + 0.5, (-5.0 if i % 2 == 0 else 5.0) + randf_range(-1, 1)),
			parent)
		enemy.max_hp = 20.0
		enemy._hp = 20.0
		enemy.detection_range = 4.0
		var patrol_a := Vector3(bridge_start + 1.0 + i * 2.0, ground_y + 0.5, enemy.position.z)
		var patrol_b := Vector3(bridge_start + 1.0 + i * 2.0 + 4.0, ground_y + 0.5, enemy.position.z)
		enemy.set_patrol([patrol_a, patrol_b])

	# Predators hunt Chelators before targeting the party.
	for i in range(2):
		var pid := "predator_%d" % i
		var predator := _spawn_enemy(pid,
			Vector3(bridge_start + 3.0 + i * 6.0, ground_y + 0.5, randf_range(-2, 2)),
			parent)
		predator.max_hp = 80.0
		predator._hp = 80.0
		predator.move_speed = 2.0
		predator.charge_speed = 10.0
		predator.charge_damage = 35.0
		predator.detection_range = 8.0
		_game_state.characters[pid].stats["detection_range"] = 8.0
		predator._detection_targets = chelator_ids.duplicate()
		if predator._mesh and predator._mesh.mesh is CapsuleMesh:
			(predator._mesh.mesh as CapsuleMesh).radius = 0.35
			(predator._mesh.mesh as CapsuleMesh).height = 1.2
			predator._mesh.position.y = 0.6
		predator.color = Color(0.5, 0.12, 0.08)
		predator._base_color = Color(0.5, 0.12, 0.08)
		if predator._mesh and predator._mesh.material_override:
			(predator._mesh.material_override as StandardMaterial3D).albedo_color = Color(0.5, 0.12, 0.08)
		var pa := Vector3(bridge_start + 2.0 + i * 6.0, ground_y + 0.5, -2.0)
		var pb := Vector3(bridge_start + 6.0 + i * 6.0, ground_y + 0.5, 2.0)
		predator.set_patrol([pa, pb])

	# Fluor bioluminescence.
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

	# --- Route fork geometry ---
	var fork_x := FORK_POS.x
	var wall_h := 3.0
	var wall_color := Color(0.08, 0.08, 0.1)

	# Central divider creates two branches.
	_add_wall(parent, Vector3(fork_x + 8.0, ground_y + wall_h / 2.0, 0), Vector3(16, wall_h, 0.4), wall_color)

	var en_z := -4.0
	_add_wall(parent, Vector3(fork_x + 8.0, ground_y + wall_h / 2.0, en_z - 3.0), Vector3(16, wall_h, 0.3), wall_color)
	# Enemy-route patrols.
	for i in range(4):
		var ex: float = fork_x + 2.0 + i * 4.0
		var enemy := _spawn_enemy("route_enemy_%d" % i,
			Vector3(ex, ground_y + 0.5, en_z - 1.5), parent)
		var pa := Vector3(ex - 1.5, ground_y + 0.5, en_z - 1.5)
		var pb := Vector3(ex + 1.5, ground_y + 0.5, en_z - 1.5)
		enemy.set_patrol([pa, pb])

	# Hazard route.
	var hz_z := 4.0
	_add_wall(parent, Vector3(fork_x + 8.0, ground_y + wall_h / 2.0, hz_z + 3.5), Vector3(16, wall_h, 0.3), wall_color)
	# Iron deposit patches.
	for i in range(3):
		var ix: float = fork_x + 3.0 + i * 5.0
		var iron_pos := Vector3(ix, ground_y + 0.02, hz_z + 1.0)
		var iron_size := Vector3(3, 0.05, 2.5)
		var iron := MeshInstance3D.new()
		var ib := BoxMesh.new()
		ib.size = iron_size
		iron.mesh = ib
		var im := StandardMaterial3D.new()
		im.albedo_color = Color(0.35, 0.15, 0.05)
		im.emission_enabled = true
		im.emission = Color(0.25, 0.08, 0.02)
		im.emission_energy_multiplier = 0.3
		iron.material_override = im
		iron.position = iron_pos
		parent.add_child(iron)
		_iron_patches.append({"pos": iron_pos, "size": iron_size})
		var ig := OmniLight3D.new()
		ig.position = Vector3(ix, ground_y + 0.5, hz_z + 1.0)
		ig.light_color = Color(0.7, 0.25, 0.05)
		ig.light_energy = 0.6
		ig.omni_range = 3.0
		parent.add_child(ig)

	# Rust stalactites.
	for i in range(4):
		var drip := MeshInstance3D.new()
		var dc := CylinderMesh.new()
		dc.top_radius = 0.02
		dc.bottom_radius = 0.06
		dc.height = 0.8
		drip.mesh = dc
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.3, 0.12, 0.06)
		drip.material_override = dm
		drip.position = Vector3(fork_x + 2.5 + i * 4.0, ground_y + wall_h - 0.4, hz_z + randf_range(-0.5, 2.0))
		parent.add_child(drip)

	# Route convergence chamber.
	var conv_x := ROUTES_CONVERGE.x
	_add_corridor_section(parent, Vector3(conv_x, ground_y - 0.04, 0), Vector3(8, 0.08, 12), Color(0.06, 0.06, 0.08))

func _build_junction_chunk(parent: Node3D) -> void:
	var ground_y := BELOW_Y
	var sx := JUNCTION_POS.x
	var sw := SHELTER_SIZE.x
	var sh := SHELTER_SIZE.y
	var sd := SHELTER_SIZE.z
	var wc := Color(0.12, 0.11, 0.1)

	# Shelter floor
	_add_corridor_section(parent, Vector3(sx, ground_y - 0.03, 0), Vector3(sw + 2, 0.06, sd + 2), Color(0.08, 0.08, 0.09))

	# Entry wall with door gap.
	_add_wall(parent, Vector3(sx - sw / 2.0, ground_y + sh / 2.0, -sd * 0.35), Vector3(0.2, sh, sd * 0.3), wc)
	_add_wall(parent, Vector3(sx - sw / 2.0, ground_y + sh / 2.0, sd * 0.35), Vector3(0.2, sh, sd * 0.3), wc)
	_add_wall(parent, Vector3(sx + sw / 2.0, ground_y + sh / 2.0, 0), Vector3(0.2, sh, sd), wc)
	# Window-gap walls.
	_add_wall(parent, Vector3(sx, ground_y + 0.5, -sd / 2.0), Vector3(sw, 1.0, 0.2), wc)
	_add_wall(parent, Vector3(sx, ground_y + sh - 0.3, -sd / 2.0), Vector3(sw, 0.6, 0.2), wc)
	_add_wall(parent, Vector3(sx, ground_y + 0.5, sd / 2.0), Vector3(sw, 1.0, 0.2), wc)
	_add_wall(parent, Vector3(sx, ground_y + sh - 0.3, sd / 2.0), Vector3(sw, 0.6, 0.2), wc)
	_add_wall(parent, Vector3(sx, ground_y + sh, 0), Vector3(sw, 0.15, sd), Color(0.07, 0.07, 0.09))

	# Window grating.
	for z_side in [-sd / 2.0, sd / 2.0]:
		for i in range(4):
			var bar := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(0.03, 1.2, 0.03)
			bar.mesh = bb
			var bm := StandardMaterial3D.new()
			bm.albedo_color = Color(0.15, 0.14, 0.13)
			bar.material_override = bm
			bar.position = Vector3(sx - sw / 2.0 + 1.0 + i * 1.2, ground_y + 1.6, z_side)
			parent.add_child(bar)

	var interior_light := OmniLight3D.new()
	interior_light.name = "ShelterLight"
	interior_light.position = Vector3(sx, ground_y + sh - 0.5, 0)
	interior_light.light_color = Color(0.8, 0.6, 0.35)
	interior_light.light_energy = 2.5
	interior_light.omni_range = 6.0
	parent.add_child(interior_light)

	for i in range(2):
		var crate := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.6, 0.5, 0.6)
		crate.mesh = cb
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.2, 0.18, 0.15)
		crate.material_override = cm
		crate.position = Vector3(sx + 1.0 - i * 2.0, ground_y + 0.25, 1.0)
		parent.add_child(crate)

	var container := MeshInstance3D.new()
	container.name = "DrinkContainer"
	var co := BoxMesh.new()
	co.size = Vector3(0.8, 0.4, 0.5)
	container.mesh = co
	var cont_mat := StandardMaterial3D.new()
	cont_mat.albedo_color = Color(0.18, 0.2, 0.18)
	container.material_override = cont_mat
	container.position = Vector3(sx + 1.5, ground_y + 0.2, -1.0)
	parent.add_child(container)

	_drink_mesh = MeshInstance3D.new()
	_drink_mesh.name = "Drink"
	var dc := CylinderMesh.new()
	dc.top_radius = 0.06
	dc.bottom_radius = 0.05
	dc.height = 0.18
	_drink_mesh.mesh = dc
	var drink_mat := StandardMaterial3D.new()
	drink_mat.albedo_color = Color(0.25, 0.3, 0.35)
	drink_mat.metallic = 0.4
	drink_mat.roughness = 0.3
	_drink_mesh.material_override = drink_mat
	_drink_mesh.position = Vector3(sx + 1.5, ground_y + 0.5, -1.0)
	parent.add_child(_drink_mesh)

	# --- Junction interactables (GDD: Endo's Junction) ---

	# Workbench with tools
	var workbench := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(1.5, 0.7, 0.6)
	workbench.mesh = wb
	var wbm := StandardMaterial3D.new()
	wbm.albedo_color = Color(0.18, 0.15, 0.12)
	workbench.material_override = wbm
	workbench.position = Vector3(sx - 1.5, ground_y + 0.35, -1.8)
	parent.add_child(workbench)
	_add_junction_interactable("Workbench", Vector3(sx - 1.5, ground_y + 0.8, -1.8),
		"junction.workbench")

	# Monitoring station.
	var monitor_panel := MeshInstance3D.new()
	var mp := BoxMesh.new()
	mp.size = Vector3(1.0, 0.8, 0.1)
	monitor_panel.mesh = mp
	var mpm := StandardMaterial3D.new()
	mpm.albedo_color = Color(0.12, 0.14, 0.13)
	mpm.emission_enabled = true
	mpm.emission = Color(0.05, 0.08, 0.05)
	mpm.emission_energy_multiplier = 0.3
	monitor_panel.material_override = mpm
	monitor_panel.position = Vector3(sx + SHELTER_SIZE.x / 2.0 - 0.15, ground_y + 1.5, -1.0)
	parent.add_child(monitor_panel)
	_add_junction_interactable("Monitor", Vector3(sx + SHELTER_SIZE.x / 2.0 - 0.5, ground_y + 1.5, -1.0),
		"junction.monitor")

	# Food cache.
	var food_cache := MeshInstance3D.new()
	var fc := BoxMesh.new()
	fc.size = Vector3(0.5, 0.3, 0.4)
	food_cache.mesh = fc
	var fcm := StandardMaterial3D.new()
	fcm.albedo_color = Color(0.2, 0.2, 0.15)
	food_cache.material_override = fcm
	food_cache.position = Vector3(sx - 2.0, ground_y + 0.8, 1.5)
	parent.add_child(food_cache)
	_add_junction_interactable("Food", Vector3(sx - 2.0, ground_y + 1.0, 1.5),
		"junction.food")

	_add_junction_interactable("Lookout", Vector3(sx + 1.0, ground_y + 1.0, -SHELTER_SIZE.z / 2.0 + 0.3),
		"junction.lookout")

	var heater := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.4, 0.5, 0.4)
	heater.mesh = hb
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.25, 0.15, 0.1)
	hm.emission_enabled = true
	hm.emission = Color(0.3, 0.15, 0.05)
	hm.emission_energy_multiplier = 0.5
	heater.material_override = hm
	heater.position = Vector3(sx - SHELTER_SIZE.x / 2.0 + 0.3, ground_y + 0.25, 0)
	parent.add_child(heater)
	_add_junction_interactable("Heater", Vector3(sx - SHELTER_SIZE.x / 2.0 + 0.5, ground_y + 0.5, 0),
		"junction.heater")

	# Endo's barrier markings.
	var markings := Label3D.new()
	markings.text = "|| /// ||| // ||||| / ||"
	markings.font_size = 24
	markings.pixel_size = 0.008
	markings.modulate = Color(0.5, 0.45, 0.35, 0.6)
	markings.position = Vector3(sx + SHELTER_SIZE.x / 2.0 - 0.15, ground_y + 1.0, 1.0)
	markings.rotation.y = -PI / 2.0
	parent.add_child(markings)
	_add_junction_interactable("Markings", Vector3(sx + SHELTER_SIZE.x / 2.0 - 0.5, ground_y + 1.0, 1.0),
		"junction.markings")

	# Hand-carved puzzle.
	var game_piece := MeshInstance3D.new()
	var gp := BoxMesh.new()
	gp.size = Vector3(0.3, 0.1, 0.3)
	game_piece.mesh = gp
	var gpm := StandardMaterial3D.new()
	gpm.albedo_color = Color(0.22, 0.18, 0.14)
	gpm.roughness = 0.2
	game_piece.material_override = gpm
	game_piece.position = Vector3(sx - 1.2, ground_y + 0.75, -1.6)
	parent.add_child(game_piece)
	_add_junction_interactable("Game", Vector3(sx - 1.2, ground_y + 0.9, -1.6),
		"junction.game")

	# Peris tends this plant to trigger dusk and Endo.
	var plant_mesh := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.2
	pm.height = 0.3
	plant_mesh.mesh = pm
	var plant_mat := StandardMaterial3D.new()
	plant_mat.albedo_color = Color(0.15, 0.12, 0.08)
	plant_mat.roughness = 0.8
	plant_mesh.material_override = plant_mat
	plant_mesh.position = Vector3(sx + SHELTER_SIZE.x / 2.0 - 0.8, ground_y + 0.15, SHELTER_SIZE.z / 2.0 - 0.5)
	parent.add_child(plant_mesh)

	var plant_interact := preload("res://scenes/game/interactable.tscn").instantiate()
	plant_interact.name = "DormantPlant"
	plant_interact.description = "Dormant Plant"
	plant_interact.dialogue_key = "junction.peris.tend_plant"
	plant_interact.dialogue_box = _dialogue
	plant_interact.active_character = _active_character
	plant_interact.required_character = "peris"
	plant_interact.one_shot = true
	plant_interact.dwell_time = 2.0
	plant_interact.position = plant_mesh.position + Vector3(0, 0.3, 0)
	add_child(plant_interact)
	if plant_interact.has_method("set_scheduler"):
		plant_interact.set_scheduler(_scheduler)
	plant_interact.interacted.connect(func():
		var bloom := create_tween()
		bloom.tween_property(plant_mat, "albedo_color", Color(0.2, 0.5, 0.3), 1.5)
		bloom.parallel().tween_property(plant_mat, "emission_enabled", true, 0.0)
		plant_mat.emission_enabled = true
		plant_mat.emission = Color(0.1, 0.3, 0.15)
		bloom.parallel().tween_property(plant_mat, "emission_energy_multiplier", 0.8, 2.0)
		bloom.parallel().tween_property(plant_mesh, "scale", Vector3(1.5, 1.8, 1.5), 2.0)
		_start_dusk_from_plant()
	)

func _start_dusk_from_plant() -> void:
	var env_node: Node = find_child("Environment", false, false)
	if env_node:
		for child in env_node.get_children():
			if child is WorldEnvironment:
				var t := create_tween()
				t.tween_property(child.environment, "ambient_light_energy", 0.15, 3.0)
				break
	_scheduler.schedule_after(2.0, _start_endo_enters, "endo_enters")

func _add_junction_interactable(label: String, pos: Vector3, dialogue_prefix: String) -> void:
	var interact := preload("res://scenes/game/interactable.tscn").instantiate()
	interact.name = "Junction_" + label
	interact.description = label
	interact.dialogue_key = dialogue_prefix
	interact.dialogue_box = _dialogue
	interact.active_character = _active_character
	interact.one_shot = false
	interact.dwell_time = 1.0
	interact.position = pos
	add_child(interact)
	if interact.has_method("set_scheduler"):
		interact.set_scheduler(_scheduler)

func _build_gauntlet_chunk(parent: Node3D) -> void:
	var ground_y := BELOW_Y
	var gx := GAUNTLET_POS.x
	var wc := Color(0.09, 0.09, 0.11)

	# Ground floor
	_add_corridor_section(parent, Vector3(gx, ground_y - 0.03, 0), Vector3(20, 0.06, 14), Color(0.05, 0.05, 0.07))
	var gb := StaticBody3D.new()
	gb.position = Vector3(gx, ground_y - 0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(20, 0.02, 14)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Chamber walls.
	_add_wall(parent, Vector3(gx, ground_y + 1.5, -7.0), Vector3(20, 3, 0.3), wc)
	_add_wall(parent, Vector3(gx, ground_y + 1.5, 7.0), Vector3(20, 3, 0.3), wc)
	_add_wall(parent, Vector3(gx + 10.0, ground_y + 1.5, 0), Vector3(0.3, 3, 14), wc)

	# Peris-only iron lure.
	_ferrolure_mesh = MeshInstance3D.new()
	_ferrolure_mesh.name = "Ferrolure"
	var fsp := SphereMesh.new()
	fsp.radius = 0.25
	fsp.height = 0.5
	_ferrolure_mesh.mesh = fsp
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.7, 0.4, 0.1)
	fmat.emission_enabled = true
	fmat.emission = Color(0.6, 0.3, 0.05)
	fmat.emission_energy_multiplier = 0.5
	fmat.metallic = 0.5
	_ferrolure_mesh.material_override = fmat
	_ferrolure_mesh.position = FERROLURE_POS
	parent.add_child(_ferrolure_mesh)

	_ferrolure_interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	_ferrolure_interactable.name = "FerrolureInteract"
	_ferrolure_interactable.description = "Ferrolure"
	_ferrolure_interactable.one_shot = true
	_ferrolure_interactable.dwell_time = 1.0
	_ferrolure_interactable.position = FERROLURE_POS
	add_child(_ferrolure_interactable)
	if _ferrolure_interactable.has_method("set_scheduler"):
		_ferrolure_interactable.set_scheduler(_scheduler)
	_ferrolure_interactable.interacted.connect(_on_ferrolure_activated)

	# Enemy cluster blocking the direct path.
	_gauntlet_enemies.clear()
	for i in range(5):
		var ex: float = gx - 2.0 + i * 2.5
		var ez: float = randf_range(-3.0, 3.0)
		var eid := "gauntlet_%d" % i
		var enemy := _spawn_enemy(eid, Vector3(ex, ground_y + 0.5, ez), parent)
		enemy.detection_range = 5.0
		var pa := Vector3(ex - 1.0, ground_y + 0.5, ez - 1.5)
		var pb := Vector3(ex + 1.0, ground_y + 0.5, ez + 1.5)
		enemy.set_patrol([pa, pb])
		_gauntlet_enemies.append(enemy)

	var gauntlet_light := OmniLight3D.new()
	gauntlet_light.position = Vector3(gx, ground_y + 2.5, 0)
	gauntlet_light.light_color = Color(0.2, 0.12, 0.08)
	gauntlet_light.light_energy = 1.5
	gauntlet_light.omni_range = 12.0
	parent.add_child(gauntlet_light)

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

	var wc := Color(0.12, 0.12, 0.14)
	_add_wall(parent, Vector3(0, h / 2.0, -hd), Vector3(ELEVATOR_SIZE.x, h, 0.2), wc)
	_add_wall(parent, Vector3(0, h / 2.0, hd), Vector3(ELEVATOR_SIZE.x, h, 0.2), wc)
	_add_wall(parent, Vector3(-hw, h / 2.0, 0), Vector3(0.2, h, ELEVATOR_SIZE.z), wc)
	_add_wall(parent, Vector3(hw, h / 2.0, -hd * 0.55), Vector3(0.2, h, hd * 0.8), wc)
	_add_wall(parent, Vector3(hw, h / 2.0, hd * 0.55), Vector3(0.2, h, hd * 0.8), wc)

	_door_panel_a = _make_door_panel(parent, Vector3(hw - 0.05, h / 2.0, -0.6), wc)
	_door_panel_b = _make_door_panel(parent, Vector3(hw - 0.05, h / 2.0, 0.6), wc)

	_add_wall(parent, Vector3(0, h, 0), Vector3(ELEVATOR_SIZE.x, 0.1, ELEVATOR_SIZE.z), Color(0.06, 0.06, 0.08))

	_emergency_light = OmniLight3D.new()
	_emergency_light.position = Vector3(0, h - 0.3, 0)
	_emergency_light.light_color = Color(0.85, 0.15, 0.1)
	_emergency_light.light_energy = 3.0
	_emergency_light.omni_range = 10.0
	parent.add_child(_emergency_light)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0, h * 0.6, 0)
	fill.light_color = Color(0.4, 0.25, 0.2)
	fill.light_energy = 1.0
	fill.omni_range = 8.0
	parent.add_child(fill)

	# Floor readout "3B": the "3" steady, the "B" flickering, both glowing. HDR
	# (>1) modulate blooms through the environment glow; a small red light backs it.
	var indicator_x := hw - 0.1
	_floor_indicator = Label3D.new()
	_floor_indicator.text = "3"
	_floor_indicator.font_size = 64
	_floor_indicator.pixel_size = 0.012
	_floor_indicator.modulate = Color(2.0, 0.45, 0.2, 1.0)
	_floor_indicator.position = Vector3(indicator_x, h * 0.7, 0.18)
	_floor_indicator.rotation.y = -PI / 2.0
	parent.add_child(_floor_indicator)

	_indicator_b_label = Label3D.new()
	_indicator_b_label.text = "B"
	_indicator_b_label.font_size = 64
	_indicator_b_label.pixel_size = 0.012
	_indicator_b_label.modulate = Color(2.0, 0.45, 0.2, 1.0)
	_indicator_b_label.position = Vector3(indicator_x, h * 0.7, -0.05)
	_indicator_b_label.rotation.y = -PI / 2.0
	parent.add_child(_indicator_b_label)

	var indicator_glow := OmniLight3D.new()
	indicator_glow.light_color = Color(0.95, 0.25, 0.15)
	indicator_glow.light_energy = 1.4
	indicator_glow.omni_range = 1.6
	indicator_glow.position = Vector3(indicator_x - 0.15, h * 0.7 + 0.25, 0.05)
	parent.add_child(indicator_glow)

	# Flashes before door access is restored.
	_no_exit_label = Label3D.new()
	_no_exit_label.text = "NO EXIT"
	_no_exit_label.font_size = 36
	_no_exit_label.pixel_size = 0.01
	_no_exit_label.modulate = Color(0.9, 0.15, 0.1, 0.0)
	_no_exit_label.position = Vector3(indicator_x, h * 0.5, 0)
	_no_exit_label.rotation.y = -PI / 2.0
	parent.add_child(_no_exit_label)

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

	for pos in [ESCORT_1_POS, ESCORT_2_POS]:
		var standby := OmniLight3D.new()
		standby.position = pos + Vector3(0, 1.5, 0)
		standby.light_color = Color(0.3, 0.3, 0.4)
		standby.light_energy = 0.5
		standby.omni_range = 2.5
		parent.add_child(standby)

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
