@tool
extends TutorialSequence

## Act 1 levels: Perivascular Channels → Processing Stacks →
## Residential Rings → Lockout/Chase.
## Chunk-based: geometry loads/unloads as the player progresses.

# Characters
var _aster_node: CharacterBody3D
var _peris_node: CharacterBody3D
var _endo: CharacterBody3D
var _active_character := "aster"
var _channels_ferrolure: MeshInstance3D
var _channels_ferrolure_light: OmniLight3D
var _channels_run_lure_mesh: MeshInstance3D
var _channels_run_lure_light: OmniLight3D
var _channels_run_lure_interactable
var _channels_hide_spot: Node3D
var _channels_swarm_units: Array[Dictionary] = []
var _channels_run_lure_active := false
var _channels_run_lure_expire_tick := -1.0
var _channels_party_hidden := false
var _channels_encounter_resetting := false

@export var start_chunk := ""

# Iron hazard zones
var _iron_patches: Array[Dictionary] = []
const IRON_DAMAGE_PER_SEC := 8.0

# HP
var _aster_hp := 100.0
var _peris_hp := 100.0

# Naturalizers (lockout chase)
var _naturalizers: Array[Node3D] = []

# Layout — linear progression along +X
# Each section is 200-250 units long, 40-60 units wide.
# At 3.0 units/sec walk speed, main path traversal = 60-80s.
# With side branches and exploration, each section = 3-5 min.
const CHANNELS_START := Vector3(0, 0, 0)
const CHANNELS_END := Vector3(220, 0, 0)
const CHANNELS_MEMORY_TRIGGER_X := 54.0
const CHANNELS_BODY_POS := Vector3(74.0, 0.5, -3.0)
const CHANNELS_FERROLURE_TRIGGER_X := 146.0
const CHANNELS_FERROLURE_POS := Vector3(156.0, 0.5, 9.0)
const CHANNELS_ENCOUNTER_TRIGGER_X := 174.0
const CHANNELS_ENCOUNTER_ENTRY_POS := Vector3(176.0, 0.5, 3.0)
const CHANNELS_RUN_LURE_POS := Vector3(180.0, 0.5, 1.5)
const CHANNELS_HIDE_SPOT_POS := Vector3(186.0, 0.5, -10.0)
const CHANNELS_SWARM_CLUSTER_X := 193.0
const CHANNELS_SWARM_DETECT_RADIUS := 2.2
const CHANNELS_SWARM_SPEED := 1.7
const CHANNELS_RUN_LURE_DURATION := 20.0
const CHANNELS_SWARM_OFFSETS := [-2.4, -1.6, -0.8, 0.0, 0.8, 1.6, 2.4]
const CHANNELS_SHELTER_POS := Vector3(198.0, 0.5, 12.0)
const STACKS_START := Vector3(240, 0, 0)
const STACKS_END := Vector3(460, 0, 0)
const RINGS_START := Vector3(480, 0, 0)
const RINGS_END := Vector3(680, 0, 0)
const LOCKOUT_START := Vector3(700, 0, 0)
const LOCKOUT_BOUNDARY := Vector3(780, 0, 0)

# --- Chunk dispatch ---

func _build_chunk(chunk_name: String, parent: Node3D) -> void:
	match chunk_name:
		"channels": _build_channels_chunk(parent)
		"stacks": _build_stacks_chunk(parent)
		"rings": _build_rings_chunk(parent)
		"lockout": _build_lockout_chunk(parent)

# --- Virtual overrides ---

func _build_scene() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.2, 0.2, 0.25)
	e.ambient_light_energy = 0.4
	e.glow_enabled = true
	e.glow_intensity = 0.2
	we.environment = e
	env.add_child(we)
	_load_chunk("channels")

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	# Aster (player)
	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = CHANNELS_START + Vector3(1, 0.5, 0)
	chars.add_child(_player)
	_aster_node = _player

	# Peris
	_peris_node = _create_player_character("Peris", Color(1.0, 0.67, 0.27))
	_peris_node.position = CHANNELS_START + Vector3(0, 0.5, 1)
	chars.add_child(_peris_node)

	# Endo becomes controllable during the Channels encounter.
	_endo = _create_player_character("Endo", Color(0.4, 0.67, 0.53))
	_endo.position = CHANNELS_START + Vector3(-1, 0.5, 0)
	chars.add_child(_endo)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 10, 8))

func _register_characters() -> void:
	_register_gs_character("aster", _aster_node, 3.0)
	_register_gs_character("peris", _peris_node, 2.5)
	_register_gs_character("endo", _endo, 2.5)

func _setup_ui() -> void:
	_setup_perception("data", _aster_node)
	_select_character("aster")

func _begin() -> void:
	_player.set_move_enabled(false)
	if start_chunk != "":
		_load_chunk(start_chunk)
		_player.set_move_enabled(true)
		match start_chunk:
			"channels":
				_player.global_position = CHANNELS_START + Vector3(5, 0.5, 0)
				_start_channels_enter()
			"stacks":
				_player.global_position = STACKS_START + Vector3(5, 0.5, 0)
				_start_stacks_enter()
			"rings":
				_player.global_position = RINGS_START + Vector3(5, 0.5, 0)
				_start_rings_enter()
			"lockout":
				_player.global_position = LOCKOUT_START + Vector3(5, 0.5, 0)
				_start_lockout_approach()
		return
	_fade_from(Color(0.02, 0.02, 0.03, 1), 2.5, _start_channels_enter, "channels_enter")

func _compute_speed() -> float:
	return 10.0 if Input.is_key_pressed(KEY_F) else 1.0

func _on_process(delta: float, spd: float) -> void:
	var channels_script_locked := _current_step in [
		"channels_encounter_intro",
		"channels_encounter_reset",
		"channels_memory",
		"channels_corpse",
		"channels_ferrolure",
		"channels_shelter",
	]

	# Iron patch damage
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
				else:
					_peris_hp = maxf(0.0, _peris_hp - dmg)
				break

	_update_channels_encounter(delta, spd)

	# Non-active party members follow the current leader when the script
	# isn't staging a cutscene or reset.
	if not channels_script_locked:
		var leader := _get_character_node(_active_character)
		for pair in [
			["aster", _aster_node, Vector3(-1.2, 0, 0.8)],
			["peris", _peris_node, Vector3(-1.2, 0, 1.2)],
			["endo", _endo, Vector3(-1.2, 0, -0.8)],
		]:
			var cid: String = pair[0]
			var cnode: CharacterBody3D = pair[1]
			var offset: Vector3 = pair[2]
			if cid == _active_character or cnode == null or not cnode.visible or not _game_state.characters.has(cid):
				continue
			var dist := cnode.global_position.distance_to(leader.global_position)
			if dist > 3.0 and not _game_state.is_moving(cid):
				_game_state.command_move_to_pos(cid, leader.global_position + offset)

	# Position gates
	if _current_step == "channels_to_memory":
		if _game_state.get_position("aster").x > CHANNELS_MEMORY_TRIGGER_X:
			_start_channels_memory()

	if _current_step == "channels_to_ferrolure":
		if _game_state.get_position("aster").x > CHANNELS_FERROLURE_TRIGGER_X:
			_start_channels_ferrolure()

	if _current_step == "channels_to_encounter":
		if _game_state.get_position("aster").x > CHANNELS_ENCOUNTER_TRIGGER_X:
			_start_channels_encounter_intro()

	if _current_step == "channels_explore":
		if _game_state.get_position("aster").x > CHANNELS_END.x - 5.0:
			_start_stacks_enter()

	if _current_step == "stacks_explore":
		if _game_state.get_position("aster").x > STACKS_END.x - 5.0:
			_start_rings_enter()

	if _current_step == "rings_explore":
		if _game_state.get_position("aster").x > RINGS_END.x - 5.0:
			_start_lockout_approach()

	# Lockout chase: Naturalizers walk toward party, stop at boundary
	if _current_step == "lockout_chase":
		for nk in _naturalizers:
			if is_instance_valid(nk):
				var nk_pos := nk.global_position
				var aster_pos := _aster_node.global_position
				# Stop if past the infrastructure boundary (going back into unserviced)
				if aster_pos.x < LOCKOUT_START.x - 10.0:
					_start_lockout_exile()
					break

# --- Step functions ---

func _get_character_node(id: String) -> CharacterBody3D:
	match id:
		"aster":
			return _aster_node
		"peris":
			return _peris_node
		"endo":
			return _endo
		_:
			return null

func _set_interactable_active_character(id: String) -> void:
	for node in find_children("*", "", true, false):
		if node.has_signal("interacted") and node.has_method("get_dwell_progress"):
			node.set("active_character", id)

func _select_character(id: String) -> void:
	var next := _get_character_node(id)
	if next == null:
		return
	for cid in ["aster", "peris", "endo"]:
		var node := _get_character_node(cid)
		if node:
			node.set_move_enabled(cid == id)
	_player = next
	_active_character = id
	_set_interactable_active_character(id)
	match id:
		"aster":
			_focus_aster_view()
		"peris":
			_focus_peris_view()
		"endo":
			_focus_endo_view()

func _focus_aster_view() -> void:
	_set_perception_mode("data")
	_set_perception_target(_aster_node)
	if _camera:
		_camera.target = _aster_node

func _focus_peris_view() -> void:
	_set_perception_mode("fog")
	_set_perception_target(_peris_node)
	if _camera:
		_camera.target = _peris_node

func _focus_endo_view() -> void:
	_set_perception_mode("")
	_set_perception_target(_endo)
	if _camera:
		_camera.target = _endo

func _wait_for_arrivals(ids: Array[String], next_func: Callable, tag: String) -> void:
	var poll: Callable
	poll = func() -> void:
		for id in ids:
			if _game_state.is_moving(id):
				_scheduler.schedule_after(0.1, poll, tag)
				return
		_scheduler.schedule_after(0.0, next_func, tag)
	_scheduler.schedule_after(0.0, poll, tag)

func _move_party_and_continue(destinations: Dictionary, next_func: Callable, tag: String) -> void:
	var ids: Array[String] = []
	for id in destinations.keys():
		ids.append(id)
		_game_state.command_move_to_pos(id, destinations[id])
	_wait_for_arrivals(ids, next_func, tag)

func _set_channels_ferrolure_active(active: bool) -> void:
	if _channels_ferrolure:
		var mat := _channels_ferrolure.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 1.4 if active else 0.25
	if _channels_ferrolure_light:
		_channels_ferrolure_light.light_energy = 2.0 if active else 0.45

func _set_channels_run_lure_active(active: bool) -> void:
	_channels_run_lure_active = active
	if _channels_run_lure_mesh:
		var mat := _channels_run_lure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 2.0 if active else 0.35
	if _channels_run_lure_light:
		_channels_run_lure_light.light_energy = 2.4 if active else 0.5

func _show_marker(pos: Vector3, text: String, tint := Color(0.4, 0.7, 0.5, 0.75)) -> void:
	var lbl := Label3D.new()
	lbl.name = "Marker_" + text
	lbl.text = text
	lbl.font_size = 28
	lbl.pixel_size = 0.008
	lbl.modulate = tint
	lbl.outline_modulate = Color(0, 0, 0, 0.5)
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = pos
	var env: Node = find_child("Environment", false, false)
	if env:
		env.add_child(lbl)

func _clear_markers() -> void:
	var env: Node = find_child("Environment", false, false)
	if env == null:
		return
	for child in env.get_children():
		if child is Label3D and child.name.begins_with("Marker_"):
			child.queue_free()

func _reset_channels_encounter_nodes() -> void:
	_clear_markers()
	_set_channels_run_lure_active(false)
	_channels_run_lure_expire_tick = -1.0
	_channels_party_hidden = false
	_channels_encounter_resetting = false
	if is_instance_valid(_channels_run_lure_interactable):
		_channels_run_lure_interactable.reset()
		_channels_run_lure_interactable.show_tutorial_label()
	for i in range(_channels_swarm_units.size()):
		var unit := _channels_swarm_units[i]
		unit["x"] = CHANNELS_SWARM_CLUSTER_X + CHANNELS_SWARM_OFFSETS[i]
		unit["target_x"] = unit["x"]
		if unit["node"]:
			unit["node"].position.x = unit["x"]
		_channels_swarm_units[i] = unit

func _begin_channels_encounter() -> void:
	if not _enter_step("channels_encounter_activate"):
		return
	_select_character("endo")
	_reset_channels_encounter_nodes()
	_show_marker(CHANNELS_RUN_LURE_POS + Vector3(0, 2.0, 0), "LURE", Color(0.75, 0.45, 0.2, 0.8))
	_show_marker(CHANNELS_HIDE_SPOT_POS + Vector3(0, 2.0, 0), "HIDE", Color(0.35, 0.75, 0.55, 0.8))
	_show_marker(CHANNELS_SHELTER_POS + Vector3(0, 2.0, 0), "SHELTER", Color(0.8, 0.72, 0.45, 0.85))
	_tutorial_prompt.show_prompt("Move Endo to the lure and hold position")
	_player.set_move_enabled(true)

func _on_channels_run_lure_activated() -> void:
	if _channels_run_lure_active or _current_step not in ["channels_encounter_activate", "channels_encounter_hide"]:
		return
	_set_channels_run_lure_active(true)
	_channels_run_lure_expire_tick = _scheduler.get_current_tick() + CHANNELS_RUN_LURE_DURATION
	_enter_step("channels_encounter_hide")
	if _channels_run_lure_interactable:
		_channels_run_lure_interactable.hide_tutorial_label()
	_tutorial_prompt.show_prompt("Hide until the swarm commits")
	_scheduler.cancel_tag("channels_run_lure_expire")
	_scheduler.schedule_after(CHANNELS_RUN_LURE_DURATION, _on_channels_run_lure_expired, "channels_run_lure_expire")

func _on_channels_run_lure_expired() -> void:
	if _current_step not in ["channels_encounter_hide", "channels_encounter_run"]:
		return
	_set_channels_run_lure_active(false)
	_channels_run_lure_expire_tick = -1.0
	if _channels_party_hidden:
		_enter_step("channels_encounter_run")
		_tutorial_prompt.show_prompt("Run for shelter")
	else:
		_fail_channels_encounter("lure_expired_exposed")

func _fail_channels_encounter(reason: String) -> void:
	if _channels_encounter_resetting or _current_step not in ["channels_encounter_activate", "channels_encounter_hide", "channels_encounter_run"]:
		return
	_channels_encounter_resetting = true
	_player.set_move_enabled(false)
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)
	_tutorial_prompt.show_prompt("The swarm catches the movement. Try again.")
	_clear_markers()
	_show_marker(CHANNELS_HIDE_SPOT_POS + Vector3(0, 2.0, 0), "CAUGHT", Color(0.85, 0.28, 0.22, 0.85))
	_scheduler.schedule_after(1.0, func():
		_restart_channels_encounter(reason)
	, "channels_encounter_retry")

func _restart_channels_encounter(_reason: String) -> void:
	if not _enter_step("channels_encounter_reset"):
		return
	_move_party_and_continue({
		"aster": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-2.4, 0.0, 0.4),
		"peris": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-1.4, 0.0, 1.2),
		"endo": CHANNELS_ENCOUNTER_ENTRY_POS,
	}, func():
		_begin_channels_encounter()
	, "channels_encounter_reset_move")

func _complete_channels_encounter() -> void:
	if _current_step == "channels_shelter":
		return
	_player.set_move_enabled(false)
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)
	_clear_markers()
	_tutorial_prompt.hide_prompt()
	_scheduler.cancel_tag("channels_run_lure_expire")
	_start_channels_shelter()

func _update_channels_encounter(delta: float, spd: float) -> void:
	if _current_step not in ["channels_encounter_activate", "channels_encounter_hide", "channels_encounter_run"]:
		return
	var target_x := CHANNELS_SWARM_CLUSTER_X
	if _channels_run_lure_active:
		target_x = CHANNELS_RUN_LURE_POS.x
	for i in range(_channels_swarm_units.size()):
		var unit := _channels_swarm_units[i]
		unit["target_x"] = target_x + CHANNELS_SWARM_OFFSETS[i]
		var dx: float = unit["target_x"] - unit["x"]
		unit["x"] += signf(dx) * minf(absf(dx), CHANNELS_SWARM_SPEED * delta * spd)
		if unit["node"]:
			unit["node"].position.x = unit["x"]
		_channels_swarm_units[i] = unit

	var hide_reached: bool = _player.global_position.distance_to(CHANNELS_HIDE_SPOT_POS) <= 2.3
	if hide_reached != _channels_party_hidden:
		_channels_party_hidden = hide_reached
		if _channels_party_hidden and _current_step == "channels_encounter_hide":
			_tutorial_prompt.show_prompt("Wait for the lure to burn out")

	if _current_step == "channels_encounter_run" and _player.global_position.distance_to(CHANNELS_SHELTER_POS) <= 3.0:
		_complete_channels_encounter()
		return

	if _channels_party_hidden:
		return

	var visible_x: float = _player.global_position.x
	for unit in _channels_swarm_units:
		if absf(unit["x"] - visible_x) <= CHANNELS_SWARM_DETECT_RADIUS:
			_fail_channels_encounter("detected")
			return

func _start_channels_enter() -> void:
	if not _enter_step("channels_enter"):
		return
	_focus_aster_view()
	_player.set_move_enabled(true)
	_dialogue_chain([
		"channels.narration.enter",
		"channels.aster.fluid",
		"channels.peris.sound",
	], func(): _scheduler.schedule_after(0.5, _start_channels_to_memory, "channels_to_memory"))

func _start_channels_to_memory() -> void:
	if not _enter_step("channels_to_memory"):
		return
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_memory() -> void:
	if not _enter_step("channels_memory"):
		return
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_game_state.command_stop("aster")
	_focus_peris_view()
	_move_party_and_continue({
		"peris": CHANNELS_BODY_POS + Vector3(-1.0, 0.0, 1.1),
		"aster": CHANNELS_BODY_POS + Vector3(-3.0, 0.0, 0.4),
		"endo": CHANNELS_BODY_POS + Vector3(-4.2, 0.0, -0.8),
	}, func():
		_dialogue_chain([
			"channels.narration.memory",
			"channels.peris.know_place",
			"channels.aster.not_here",
			"channels.peris.saw_it",
			"channels.narration.leads",
		], func(): _scheduler.schedule_after(0.5, _start_channels_corpse, "channels_corpse"))
	, "channels_memory_move")

func _start_channels_to_ferrolure() -> void:
	if not _enter_step("channels_to_ferrolure"):
		return
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_corpse() -> void:
	if not _enter_step("channels_corpse"):
		return
	_focus_aster_view()
	_dialogue_chain([
		"channels.narration.body",
		"channels.endo.kneel",
		"channels.aster.report",
		"channels.peris.smell",
		"channels.peris.clients",
		"channels.aster.lysate",
		"channels.peris.people",
		"channels.aster.hungry",
		"channels.aster.downgrade",
	], func(): _scheduler.schedule_after(0.5, _start_channels_to_ferrolure, "channels_to_ferrolure"))

func _start_channels_ferrolure() -> void:
	if not _enter_step("channels_ferrolure"):
		return
	_select_character("aster")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_game_state.command_stop("aster")
	_set_channels_ferrolure_active(false)
	_move_party_and_continue({
		"peris": CHANNELS_FERROLURE_POS + Vector3(-0.8, 0.0, 0.6),
		"aster": CHANNELS_FERROLURE_POS + Vector3(-2.5, 0.0, -0.3),
		"endo": CHANNELS_FERROLURE_POS + Vector3(-3.6, 0.0, 1.2),
	}, func():
		_dialogue_chain([
			"channels.narration.flora",
			"channels.aster.lure",
			"channels.peris.signals",
			"channels.peris.pause",
		], func():
			_set_channels_ferrolure_active(true)
			_dialogue_chain([
				"channels.peris.touch",
				"channels.peris.always",
			], func(): _scheduler.schedule_after(0.5, _start_channels_to_encounter, "channels_to_encounter"))
		)
	, "channels_ferrolure_move")

func _start_channels_to_encounter() -> void:
	if not _enter_step("channels_to_encounter"):
		return
	_select_character("aster")
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_encounter_intro() -> void:
	if not _enter_step("channels_encounter_intro"):
		return
	_select_character("endo")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_move_party_and_continue({
		"aster": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-2.4, 0.0, 0.4),
		"peris": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-1.4, 0.0, 1.2),
		"endo": CHANNELS_ENCOUNTER_ENTRY_POS,
	}, func():
		_begin_channels_encounter()
	, "channels_encounter_intro_move")

func _start_channels_shelter() -> void:
	if not _enter_step("channels_shelter"):
		return
	_select_character("endo")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_game_state.command_stop("aster")
	_game_state.command_stop("peris")
	_game_state.command_stop("endo")
	_move_party_and_continue({
		"aster": CHANNELS_SHELTER_POS + Vector3(-1.8, 0.0, -1.2),
		"peris": CHANNELS_SHELTER_POS + Vector3(-0.8, 0.0, 0.9),
		"endo": CHANNELS_SHELTER_POS + Vector3(-0.3, 0.0, -0.2),
	}, func():
		_dialogue_chain([
			"channels.narration.shelter",
			"channels.endo.door",
		], func(): _scheduler.schedule_after(0.5, _start_channels_explore, "channels_explore"))
	, "channels_shelter_move")

func _start_channels_explore() -> void:
	if not _enter_step("channels_explore"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

# --- Stacks ---

func _start_stacks_enter() -> void:
	_enter_step("stacks_enter")
	_tutorial_prompt.hide_prompt()
	_load_chunk("stacks")
	_unload_chunk("channels")
	_iron_patches.clear()
	_dialogue_chain([
		"stacks.narration.enter",
		"stacks.aster.home",
		"stacks.peris.cold",
	], func(): _scheduler.schedule_after(2.0, _start_stacks_terminal, "terminal"))

func _start_stacks_terminal() -> void:
	_enter_step("stacks_terminal")
	_dialogue_chain([
		"stacks.aster.terminal",
		"stacks.aster.cleaned",
		"stacks.aster.here",
		"stacks.peris.ok",
		"stacks.aster.not_sure",
	], func(): _scheduler.schedule_after(3.0, _start_stacks_archive, "archive"))

func _start_stacks_archive() -> void:
	_enter_step("stacks_archive")
	_dialogue_chain([
		"stacks.narration.elegant",
		"stacks.narration.closet",
		"stacks.aster.archive",
		"stacks.aster.when",
		"stacks.peris.meaning",
		"stacks.aster.means",
	], func(): _scheduler.schedule_after(2.0, _start_stacks_explore, "explore"))

func _start_stacks_explore() -> void:
	_enter_step("stacks_explore")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

# --- Rings ---

func _start_rings_enter() -> void:
	_enter_step("rings_enter")
	_tutorial_prompt.hide_prompt()
	_load_chunk("rings")
	_unload_chunk("stacks")
	_dialogue_chain([
		"rings.narration.enter",
		"rings.aster.signal",
		"rings.peris.remember",
	], func(): _scheduler.schedule_after(3.0, _start_rings_client, "client"))

func _start_rings_client() -> void:
	_enter_step("rings_client")
	_dialogue_chain([
		"rings.peris.hello",
		"rings.narration.client",
		"rings.peris.wall",
		"rings.narration.empty",
		"rings.aster.tags",
	], func(): _scheduler.schedule_after(3.0, _start_endo_departs, "endo_departs"))

func _start_endo_departs() -> void:
	_enter_step("endo_departs")
	_dialogue_chain([
		"rings.endo.discomfort",
		"rings.endo.stops",
		"rings.peris.endo",
		"rings.narration.leaving",
		"rings.peris.understands",
		"rings.aster.just_us",
		"rings.peris.visiting",
	], func():
		# Endo walks back and fades out
		_endo.visible = false
		if _game_state.characters.has("endo"):
			_game_state.command_stop("endo")
		_scheduler.schedule_after(2.0, _start_rings_explore, "explore")
	)

func _start_rings_explore() -> void:
	_enter_step("rings_explore")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

# --- Lockout ---

func _start_lockout_approach() -> void:
	_enter_step("lockout_approach")
	_tutorial_prompt.hide_prompt()
	_load_chunk("lockout")
	_unload_chunk("rings")
	_dialogue_chain([
		"lockout.narration.clean",
		"lockout.aster.signals",
		"lockout.aster.panel",
	], func(): _scheduler.schedule_after(1.0, _start_lockout_rejected, "rejected"))

func _start_lockout_rejected() -> void:
	_enter_step("lockout_rejected")
	_dialogue_chain([
		"lockout.system.rejected",
		"lockout.aster.again",
		"lockout.system.rejected2",
		"lockout.aster.hack",
		"lockout.system.blocked",
	], func(): _scheduler.schedule_after(1.0, _start_lockout_chase, "chase"))

func _start_lockout_chase() -> void:
	_enter_step("lockout_chase")
	_dialogue_chain([
		"lockout.narration.footsteps",
		"lockout.peris.run",
		"lockout.narration.chase",
	], func():
		_player.set_move_enabled(true)
		_tutorial_prompt.show_prompt("Run!")
	)
	# Spawn Naturalizer NPCs that walk toward the party
	var env: Node = find_child("Environment", false, false)
	for i in range(3):
		var nk := _create_npc("NK-%d" % (i + 1), Color(0.7, 0.7, 0.75))
		nk.position = LOCKOUT_BOUNDARY + Vector3(-2 + i * 2, 0.5, 0)
		find_child("Characters", false, false).add_child(nk)
		_register_gs_character("nk_%d" % i, nk, 1.5)
		_game_state.command_move_to_pos("nk_%d" % i, _aster_node.global_position)
		_naturalizers.append(nk)

func _start_lockout_exile() -> void:
	_enter_step("lockout_exile")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	# Stop Naturalizers
	for i in range(_naturalizers.size()):
		if _game_state.characters.has("nk_%d" % i):
			_game_state.command_stop("nk_%d" % i)
	_dialogue_chain([
		"lockout.narration.boundary",
		"lockout.aster.not_in",
		"lockout.peris.back_to",
		"lockout.narration.forward",
	], func(): _scheduler.schedule_after(2.0, _complete, "complete"))

func _complete() -> void:
	_enter_step("complete")
	_player.set_move_enabled(false)
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color", Color(0.02, 0.02, 0.03, 1.0), 2.0)
	tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/tutorial/leaving_facility.tscn")
	)

# --- Chunk builders ---

func _build_channels_chunk(parent: Node3D) -> void:
	var sx := CHANNELS_START.x
	var length := 220.0
	var width := 50.0
	var floor_color := Color(0.06, 0.08, 0.1)
	var wall_color := Color(0.08, 0.08, 0.1)

	# Main corridor ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Outer walls
	_add_wall(parent, Vector3(sx + length / 2.0, 1.5, -width / 2.0), Vector3(length, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 1.5, width / 2.0), Vector3(length, 3, 0.3), wall_color)

	# Flowing water channels along the main path (blue-tinted strips)
	for i in range(6):
		var water := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(length * 0.8, 0.02, 2.0)
		water.mesh = wb
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.1, 0.15, 0.2)
		wm.emission_enabled = true
		wm.emission = Color(0.05, 0.08, 0.12)
		wm.emission_energy_multiplier = 0.3
		water.material_override = wm
		water.position = Vector3(sx + length / 2.0, 0.01, -15.0 + i * 6.0)
		parent.add_child(water)

	# Side branches (3 alcoves off the main path for exploration)
	for i in range(3):
		var branch_x: float = sx + 50.0 + i * 60.0
		var branch_z: float = -width / 2.0 + 5.0 if i % 2 == 0 else width / 2.0 - 5.0
		var branch_sign: float = 1.0 if branch_z > 0 else -1.0
		# Alcove floor
		_add_corridor_section(parent, Vector3(branch_x, -0.04, branch_z + branch_sign * 10.0), Vector3(15, 0.08, 12), Color(0.05, 0.06, 0.08))
		# Alcove walls
		_add_wall(parent, Vector3(branch_x - 8.0, 1.5, branch_z + branch_sign * 10.0), Vector3(0.3, 3, 12), wall_color)
		_add_wall(parent, Vector3(branch_x + 8.0, 1.5, branch_z + branch_sign * 10.0), Vector3(0.3, 3, 12), wall_color)

	# Stagnant pools with iron deposits (multiple, spread out)
	for i in range(4):
		var sp_x: float = sx + 40.0 + i * 50.0
		var sp_z: float = 8.0 + randf_range(-3, 3) if i % 2 == 0 else -8.0 + randf_range(-3, 3)
		var sp_pos := Vector3(sp_x, 0.02, sp_z)
		var sp_size := Vector3(8, 0.04, 6)
		var stagnant := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = sp_size
		stagnant.mesh = sb
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.2, 0.12, 0.06)
		sm.emission_enabled = true
		sm.emission = Color(0.15, 0.06, 0.02)
		sm.emission_energy_multiplier = 0.2
		stagnant.material_override = sm
		stagnant.position = sp_pos
		parent.add_child(stagnant)
		_iron_patches.append({"pos": sp_pos, "size": sp_size})

	# Body in the drainage path grounds both the memory beat and the harvest beat.
	var body := MeshInstance3D.new()
	body.name = "ChannelsBody"
	var corpse_mesh := CapsuleMesh.new()
	corpse_mesh.radius = 0.28
	corpse_mesh.height = 1.3
	body.mesh = corpse_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.2, 0.18, 0.16)
	body_mat.roughness = 0.9
	body.material_override = body_mat
	body.position = CHANNELS_BODY_POS
	body.rotation_degrees = Vector3(0, 0, 88)
	parent.add_child(body)

	for i in range(2):
		var memory_body := MeshInstance3D.new()
		var memory_mesh := CapsuleMesh.new()
		memory_mesh.radius = 0.22
		memory_mesh.height = 1.1
		memory_body.mesh = memory_mesh
		var memory_mat := StandardMaterial3D.new()
		memory_mat.albedo_color = Color(0.16, 0.18, 0.22)
		memory_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		memory_mat.albedo_color.a = 0.45
		memory_body.material_override = memory_mat
		memory_body.position = Vector3(sx + 48.0 + i * 14.0, 0.38, -10.0 + i * 6.0)
		memory_body.rotation_degrees = Vector3(0, 0, 90)
		parent.add_child(memory_body)

	# Second ferrolure: dormant until Peris tends it in the coda beat.
	var ferrolure_root := Node3D.new()
	ferrolure_root.name = "SecondFerrolure"
	ferrolure_root.position = CHANNELS_FERROLURE_POS
	parent.add_child(ferrolure_root)

	var ferrolure_stem := MeshInstance3D.new()
	var ferrolure_stem_mesh := CylinderMesh.new()
	ferrolure_stem_mesh.top_radius = 0.08
	ferrolure_stem_mesh.bottom_radius = 0.12
	ferrolure_stem_mesh.height = 1.0
	ferrolure_stem.mesh = ferrolure_stem_mesh
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.18, 0.24, 0.18)
	ferrolure_stem.material_override = stem_mat
	ferrolure_stem.position = Vector3(0, 0.5, 0)
	ferrolure_root.add_child(ferrolure_stem)

	_channels_ferrolure = MeshInstance3D.new()
	var ferrolure_bulb_mesh := SphereMesh.new()
	ferrolure_bulb_mesh.radius = 0.35
	ferrolure_bulb_mesh.height = 0.7
	_channels_ferrolure.mesh = ferrolure_bulb_mesh
	var ferrolure_mat := StandardMaterial3D.new()
	ferrolure_mat.albedo_color = Color(0.22, 0.35, 0.25)
	ferrolure_mat.emission_enabled = true
	ferrolure_mat.emission = Color(0.2, 0.55, 0.32)
	ferrolure_mat.emission_energy_multiplier = 0.25
	_channels_ferrolure.material_override = ferrolure_mat
	_channels_ferrolure.position = Vector3(0, 1.05, 0)
	ferrolure_root.add_child(_channels_ferrolure)

	_channels_ferrolure_light = OmniLight3D.new()
	_channels_ferrolure_light.position = Vector3(0, 1.0, 0)
	_channels_ferrolure_light.light_color = Color(0.32, 0.7, 0.45)
	_channels_ferrolure_light.light_energy = 0.45
	_channels_ferrolure_light.omni_range = 8.0
	ferrolure_root.add_child(_channels_ferrolure_light)
	_set_channels_ferrolure_active(false)

	# Encounter lure: Endo uses this to pull the swarm away from the shelter route.
	var run_lure_root := Node3D.new()
	run_lure_root.name = "EncounterFerrolure"
	run_lure_root.position = CHANNELS_RUN_LURE_POS
	parent.add_child(run_lure_root)

	var run_lure_stem := MeshInstance3D.new()
	var run_lure_stem_mesh := CylinderMesh.new()
	run_lure_stem_mesh.top_radius = 0.09
	run_lure_stem_mesh.bottom_radius = 0.13
	run_lure_stem_mesh.height = 1.1
	run_lure_stem.mesh = run_lure_stem_mesh
	var run_lure_stem_mat := StandardMaterial3D.new()
	run_lure_stem_mat.albedo_color = Color(0.25, 0.28, 0.18)
	run_lure_stem.material_override = run_lure_stem_mat
	run_lure_stem.position = Vector3(0, 0.55, 0)
	run_lure_root.add_child(run_lure_stem)

	_channels_run_lure_mesh = MeshInstance3D.new()
	var run_lure_bulb := SphereMesh.new()
	run_lure_bulb.radius = 0.4
	run_lure_bulb.height = 0.8
	_channels_run_lure_mesh.mesh = run_lure_bulb
	var run_lure_mat := StandardMaterial3D.new()
	run_lure_mat.albedo_color = Color(0.55, 0.34, 0.12)
	run_lure_mat.emission_enabled = true
	run_lure_mat.emission = Color(0.8, 0.4, 0.15)
	run_lure_mat.emission_energy_multiplier = 0.35
	run_lure_mat.metallic = 0.15
	_channels_run_lure_mesh.material_override = run_lure_mat
	_channels_run_lure_mesh.position = Vector3(0, 1.1, 0)
	run_lure_root.add_child(_channels_run_lure_mesh)

	_channels_run_lure_light = OmniLight3D.new()
	_channels_run_lure_light.position = Vector3(0, 1.2, 0)
	_channels_run_lure_light.light_color = Color(0.9, 0.45, 0.18)
	_channels_run_lure_light.light_energy = 0.5
	_channels_run_lure_light.omni_range = 8.0
	run_lure_root.add_child(_channels_run_lure_light)
	_set_channels_run_lure_active(false)

	_channels_run_lure_interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	_channels_run_lure_interactable.name = "EncounterFerrolureInteract"
	_channels_run_lure_interactable.description = "Ferrolure"
	_channels_run_lure_interactable.required_character = "endo"
	_channels_run_lure_interactable.one_shot = false
	_channels_run_lure_interactable.dwell_time = 2.0
	_channels_run_lure_interactable.tutorial_label = "HOLD"
	_channels_run_lure_interactable.position = CHANNELS_RUN_LURE_POS
	parent.add_child(_channels_run_lure_interactable)
	_channels_run_lure_interactable.interacted.connect(_on_channels_run_lure_activated)

	# Hide alcove near the shelter route.
	_channels_hide_spot = Node3D.new()
	_channels_hide_spot.name = "ChannelsHideSpot"
	_channels_hide_spot.position = CHANNELS_HIDE_SPOT_POS
	parent.add_child(_channels_hide_spot)
	_add_corridor_section(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x, -0.04, CHANNELS_HIDE_SPOT_POS.z), Vector3(10, 0.08, 8), Color(0.05, 0.05, 0.07))
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x, 1.5, CHANNELS_HIDE_SPOT_POS.z + 4.0), Vector3(10, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x - 5.0, 1.5, CHANNELS_HIDE_SPOT_POS.z), Vector3(0.3, 3, 8), wall_color)
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x + 5.0, 1.5, CHANNELS_HIDE_SPOT_POS.z), Vector3(0.3, 3, 8), wall_color)

	# Swarm cluster guarding the stretch before the shelter.
	_channels_swarm_units.clear()
	for i in range(CHANNELS_SWARM_OFFSETS.size()):
		var swarm := MeshInstance3D.new()
		swarm.name = "ChannelsSwarm_%d" % i
		var swarm_mesh := SphereMesh.new()
		swarm_mesh.radius = 0.3
		swarm_mesh.height = 0.6
		swarm.mesh = swarm_mesh
		var swarm_mat := StandardMaterial3D.new()
		swarm_mat.albedo_color = Color(0.15, 0.12, 0.08)
		swarm_mat.emission_enabled = true
		swarm_mat.emission = Color(0.45, 0.2, 0.06)
		swarm_mat.emission_energy_multiplier = 0.6
		swarm.material_override = swarm_mat
		swarm.position = Vector3(CHANNELS_SWARM_CLUSTER_X + CHANNELS_SWARM_OFFSETS[i], 0.6, 0.5 + sin(float(i)) * 1.2)
		parent.add_child(swarm)
		_channels_swarm_units.append({
			"node": swarm,
			"x": swarm.position.x,
			"target_x": swarm.position.x,
		})

	# Shelter alcove at the far end of the zone.
	_add_corridor_section(parent, Vector3(CHANNELS_SHELTER_POS.x, -0.04, CHANNELS_SHELTER_POS.z), Vector3(16, 0.08, 10), Color(0.07, 0.07, 0.08))
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x, 1.5, CHANNELS_SHELTER_POS.z + 5.0), Vector3(16, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x - 8.0, 1.5, CHANNELS_SHELTER_POS.z), Vector3(0.3, 3, 10), wall_color)
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x + 8.0, 1.5, CHANNELS_SHELTER_POS.z), Vector3(0.3, 3, 10), wall_color)
	var shelter_door := MeshInstance3D.new()
	shelter_door.name = "ChannelsShelterDoor"
	var shelter_door_mesh := BoxMesh.new()
	shelter_door_mesh.size = Vector3(2.4, 2.6, 0.18)
	shelter_door.mesh = shelter_door_mesh
	var shelter_door_mat := StandardMaterial3D.new()
	shelter_door_mat.albedo_color = Color(0.22, 0.2, 0.18)
	shelter_door.material_override = shelter_door_mat
	shelter_door.position = CHANNELS_SHELTER_POS + Vector3(0, 1.25, -4.8)
	parent.add_child(shelter_door)
	var shelter_light := OmniLight3D.new()
	shelter_light.position = CHANNELS_SHELTER_POS + Vector3(0, 2.0, 0)
	shelter_light.light_color = Color(0.85, 0.68, 0.42)
	shelter_light.light_energy = 2.1
	shelter_light.omni_range = 12.0
	parent.add_child(shelter_light)

	# Lighting — spread across the length
	for i in range(5):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 20.0 + i * 45.0, 2.5, 0)
		light.light_color = Color(0.2, 0.25, 0.4)
		light.light_energy = 1.5
		light.omni_range = 20.0
		parent.add_child(light)

	# Warm lights near stagnant zones
	for i in range(3):
		var sl := OmniLight3D.new()
		sl.position = Vector3(sx + 50.0 + i * 60.0, 2.0, 12.0 if i % 2 == 0 else -12.0)
		sl.light_color = Color(0.5, 0.25, 0.1)
		sl.light_energy = 1.0
		sl.omni_range = 8.0
		parent.add_child(sl)

func _build_stacks_chunk(parent: Node3D) -> void:
	var sx := STACKS_START.x
	var length := 220.0
	var width := 40.0
	var floor_color := Color(0.05, 0.05, 0.06)
	var wall_color := Color(0.07, 0.07, 0.09)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Walls
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, -width / 2.0), Vector3(length, 5, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, width / 2.0), Vector3(length, 5, 0.3), wall_color)

	# Server racks — dense grid creating corridors between them
	for row in range(5):
		for col in range(12):
			var rack := MeshInstance3D.new()
			var rb := BoxMesh.new()
			rb.size = Vector3(1.0, 3.0, 5.0)
			rack.mesh = rb
			var rm := StandardMaterial3D.new()
			rm.albedo_color = Color(0.06, 0.06, 0.08)
			rm.metallic = 0.3
			rack.material_override = rm
			rack.position = Vector3(sx + 15 + col * 16.0, 1.5, -12.0 + row * 6.0)
			parent.add_child(rack)

	# Terminal interactable (midway through the stacks)
	var terminal := preload("res://scenes/game/interactable.tscn").instantiate()
	terminal.name = "DataTerminal"
	terminal.description = "Maintenance Terminal"
	terminal.dialogue_key = "stacks.aster.cleaned"
	terminal.dialogue_box = _dialogue
	terminal.active_character = "aster"
	terminal.one_shot = true
	terminal.dwell_time = 2.0
	terminal.position = Vector3(sx + length * 0.4, 1.0, 0)
	add_child(terminal)

	# Myke's elegant workspace — deeper in, off the main path
	var elegant_light := OmniLight3D.new()
	elegant_light.position = Vector3(sx + length * 0.75, 2.0, -10)
	elegant_light.light_color = Color(0.3, 0.25, 0.2)
	elegant_light.light_energy = 1.2
	elegant_light.omni_range = 8.0
	parent.add_child(elegant_light)

	# Cold industrial lighting spread across the length
	for i in range(6):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 20.0 + i * 35.0, 4.0, 0)
		light.light_color = Color(0.2, 0.2, 0.3)
		light.light_energy = 2.0
		light.omni_range = 20.0
		parent.add_child(light)

func _build_rings_chunk(parent: Node3D) -> void:
	var sx := RINGS_START.x
	var length := 200.0
	var width := 50.0
	var floor_color := Color(0.12, 0.11, 0.1)
	var wall_color := Color(0.15, 0.14, 0.12)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Walls — cleaner, residential
	_add_wall(parent, Vector3(sx + length / 2.0, 2.0, -width / 2.0), Vector3(length, 4, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.0, width / 2.0), Vector3(length, 4, 0.3), wall_color)

	# Warm residential lighting — generous, well-lit
	for i in range(8):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 15 + i * 25.0, 3.5, 0)
		light.light_color = Color(0.8, 0.6, 0.4)
		light.light_energy = 2.5
		light.omni_range = 18.0
		parent.add_child(light)

	# Simulation bay windows (glowing rectangles along the north wall)
	for i in range(10):
		var bay := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(5, 2.0, 0.1)
		bay.mesh = bb
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.15, 0.12, 0.1)
		bm.emission_enabled = true
		bm.emission = Color(0.3, 0.25, 0.15)
		bm.emission_energy_multiplier = 0.5
		bay.material_override = bm
		bay.position = Vector3(sx + 10 + i * 18.0, 1.8, -width / 2.0 + 0.2)
		parent.add_child(bay)

	# Apartment doors along the south wall (some sealed, one ajar)
	for i in range(8):
		var door := MeshInstance3D.new()
		var db := BoxMesh.new()
		db.size = Vector3(2.0, 2.5, 0.1)
		door.mesh = db
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.18, 0.16, 0.14)
		door.material_override = dm
		door.position = Vector3(sx + 20 + i * 22.0, 1.25, width / 2.0 - 0.2)
		parent.add_child(door)

	# Client interactable (Peris tries to talk)
	var client := preload("res://scenes/game/interactable.tscn").instantiate()
	client.name = "ClientNPC"
	client.description = "Former Client"
	client.dialogue_key = "rings.peris.hello"
	client.dialogue_box = _dialogue
	client.active_character = "peris"
	client.one_shot = true
	client.dwell_time = 1.0
	client.position = Vector3(sx + length * 0.4, 0.5, -5)
	add_child(client)

	# Drink machine in an alcove (set dressing — civilization has amenities)
	var drink := MeshInstance3D.new()
	var drb := BoxMesh.new()
	drb.size = Vector3(1.0, 1.8, 0.8)
	drink.mesh = drb
	var drm := StandardMaterial3D.new()
	drm.albedo_color = Color(0.15, 0.18, 0.2)
	drm.emission_enabled = true
	drm.emission = Color(0.1, 0.15, 0.2)
	drm.emission_energy_multiplier = 0.3
	drink.material_override = drm
	drink.position = Vector3(sx + length * 0.6, 0.9, width / 2.0 - 2.0)
	parent.add_child(drink)

func _build_lockout_chunk(parent: Node3D) -> void:
	var sx := LOCKOUT_START.x
	var length := 80.0  # Shorter — this is an event, not an exploration area
	var width := 20.0
	var floor_color := Color(0.1, 0.1, 0.12)
	var wall_color := Color(0.12, 0.12, 0.14)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Walls — cleaner, getting closer to civilization
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, -width / 2.0), Vector3(length, 5, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, width / 2.0), Vector3(length, 5, 0.3), wall_color)

	# Progressive lighting: dim at entry, bright at boundary (approaching civilization)
	for i in range(4):
		var light := OmniLight3D.new()
		var t: float = float(i) / 3.0
		light.position = Vector3(sx + 10.0 + i * 20.0, 3.0, 0)
		light.light_color = Color(0.3 + t * 0.3, 0.3 + t * 0.2, 0.35 + t * 0.25)
		light.light_energy = 1.0 + t * 2.0
		light.omni_range = 12.0 + t * 6.0
		parent.add_child(light)

	# Access panel visual (at the boundary)
	var panel := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.15, 1.5, 1.0)
	panel.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.12, 0.14, 0.18)
	pm.emission_enabled = true
	pm.emission = Color(0.1, 0.15, 0.25)
	pm.emission_energy_multiplier = 0.8
	panel.material_override = pm
	panel.position = LOCKOUT_BOUNDARY + Vector3(-0.5, 0.75, 0)
	parent.add_child(panel)

	# Access panel interactable
	var access := preload("res://scenes/game/interactable.tscn").instantiate()
	access.name = "AccessPanel"
	access.description = "Access Panel"
	access.dialogue_key = "lockout.system.rejected"
	access.dialogue_box = _dialogue
	access.active_character = "aster"
	access.one_shot = true
	access.dwell_time = 1.5
	access.position = LOCKOUT_BOUNDARY + Vector3(-1.5, 0.75, 0)
	add_child(access)
