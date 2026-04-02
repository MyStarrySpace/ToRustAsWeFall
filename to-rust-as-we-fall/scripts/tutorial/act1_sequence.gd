@tool
extends TutorialSequence

## Act 1 levels: Perivascular Channels → Processing Stacks →
## Residential Rings → Lockout/Chase.
## Chunk-based: geometry loads/unloads as the player progresses.

# Characters
var _aster_node: CharacterBody3D
var _peris_node: CharacterBody3D
var _endo: Node3D
var _active_character := "aster"

# Chunks
var _chunks: Dictionary = {}

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
const STACKS_START := Vector3(240, 0, 0)
const STACKS_END := Vector3(460, 0, 0)
const RINGS_START := Vector3(480, 0, 0)
const RINGS_END := Vector3(680, 0, 0)
const LOCKOUT_START := Vector3(700, 0, 0)
const LOCKOUT_BOUNDARY := Vector3(780, 0, 0)

# --- Chunk management ---

func _load_chunk(chunk_name: String) -> Node3D:
	if _chunks.has(chunk_name):
		return _chunks[chunk_name]
	var chunk := Node3D.new()
	chunk.name = "Chunk_" + chunk_name
	find_child("Environment", false, false).add_child(chunk)
	_chunks[chunk_name] = chunk
	match chunk_name:
		"channels": _build_channels_chunk(chunk)
		"stacks": _build_stacks_chunk(chunk)
		"rings": _build_rings_chunk(chunk)
		"lockout": _build_lockout_chunk(chunk)
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

	# Peris (follows)
	_peris_node = _create_player_character("Peris", Color(1.0, 0.67, 0.27))
	_peris_node.position = CHANNELS_START + Vector3(0, 0.5, 1)
	chars.add_child(_peris_node)

	# Endo (present until rings, then departs)
	_endo = _create_npc("Endo", Color(0.4, 0.67, 0.53))
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

func _begin() -> void:
	_player.set_move_enabled(false)
	_fade_from(Color(0.02, 0.02, 0.03, 1), 2.5, _start_channels_enter, "channels_enter")

func _compute_speed() -> float:
	return 10.0 if Input.is_key_pressed(KEY_F) else 1.0

func _on_process(delta: float, spd: float) -> void:
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

	# NPC follow (Endo follows Aster when present and visible)
	if _endo and _endo.visible and _game_state.characters.has("endo"):
		var dist := _endo.global_position.distance_to(_aster_node.global_position)
		if dist > 3.0 and not _game_state.is_moving("endo"):
			_game_state.command_move_to_pos("endo", _aster_node.global_position + Vector3(-1.2, 0, -0.8))

	# Peris follows Aster
	if _peris_node and _game_state.characters.has("peris"):
		var dist := _peris_node.global_position.distance_to(_aster_node.global_position)
		if dist > 3.0 and not _game_state.is_moving("peris"):
			_game_state.command_move_to_pos("peris", _aster_node.global_position + Vector3(-1.2, 0, 0.8))

	# Position gates
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

func _start_channels_enter() -> void:
	_enter_step("channels_enter")
	_player.set_move_enabled(true)
	_dialogue_chain([
		"channels.narration.enter",
		"channels.aster.fluid",
		"channels.peris.sound",
	], func(): _scheduler.schedule_after(2.0, _start_channels_endo_teach, "endo_teach"))

func _start_channels_endo_teach() -> void:
	_enter_step("channels_endo_teach")
	_dialogue_chain([
		"channels.endo.stop",
		"channels.aster.stagnant",
		"channels.peris.thick",
	], func(): _scheduler.schedule_after(2.0, _start_channels_flora, "flora"))

func _start_channels_flora() -> void:
	_enter_step("channels_flora")
	_dialogue_chain([
		"channels.narration.flora",
		"channels.peris.touch",
		"channels.aster.glow",
		"channels.peris.always",
	], func(): _scheduler.schedule_after(2.0, _start_channels_corpse, "corpse"))

func _start_channels_corpse() -> void:
	_enter_step("channels_corpse")
	_dialogue_chain([
		"channels.narration.body",
		"channels.endo.kneel",
		"channels.peris.what",
		"channels.aster.nutrients",
		"channels.peris.people",
		"channels.aster.hungry",
	], func(): _scheduler.schedule_after(2.0, _start_channels_explore, "explore"))

func _start_channels_explore() -> void:
	_enter_step("channels_explore")
	_dialogue_chain([
		"channels.narration.branch",
		"channels.endo.point",
	], func():
		_tutorial_prompt.show_prompt("Click to move — follow the flowing water")
	)

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

	# Flora growths (multiple — player learns tending through repetition)
	for i in range(3):
		var fi := preload("res://scenes/game/interactable.tscn").instantiate()
		fi.name = "FloraGrowth_%d" % i
		fi.description = "Wild Growth"
		fi.one_shot = false
		fi.dwell_time = 1.5
		fi.position = Vector3(sx + 30.0 + i * 70.0, 0.3, randf_range(-8, 8))
		add_child(fi)
	# Keep the first one named for test compatibility
	var flora_interact := find_child("FloraGrowth_0", true, false)
	if flora_interact:
		flora_interact.name = "FloraGrowth"

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
	access.one_shot = true
	access.dwell_time = 1.5
	access.position = LOCKOUT_BOUNDARY + Vector3(-1.5, 0.75, 0)
	add_child(access)
