@tool
extends TutorialSequence

## Showcase room for testing UI, spawning characters and enemy types,
## and interacting with game systems. Press number keys to spawn,
## right-click to place, Delete to remove, C to clear.

const FLOOR_SIZE := 30.0
const FLOOR_COLOR := Color(0.08, 0.08, 0.1)

# Spawned entities
var _spawned_entities: Array[Node3D] = []
var _spawned_characters: Dictionary = {}  # id -> node
var _char_counter := 0

# UI
var _hud  # GameHUD
var _spawn_label: Label
var _active_char_id := ""

# Perception
var _perception_cycle := 0  # 0=off, 1=data, 2=fog

# Raycasting
var _ray_origin := Vector3.ZERO
var _ray_dir := Vector3.FORWARD

# --- Virtual overrides ---

func _build_scene() -> void:
	_build_environment()

func _build_characters() -> void:
	pass

func _register_characters() -> void:
	pass

func _setup_ui() -> void:
	# Game HUD
	_hud = CanvasLayer.new()
	_hud.name = "GameHUD"
	_hud.set_script(preload("res://scripts/game/game_hud.gd"))
	add_child(_hud)
	_hud.show_pause_toggle(false)
	_hud.pause_toggled.connect(func(p: bool):
		if p: _scheduler.pause()
		else: _scheduler.resume()
	)
	_hud.character_selection_changed.connect(_on_character_selected)

	# Spawn panel overlay
	_spawn_label = Label.new()
	var panel := CanvasLayer.new()
	panel.layer = 11
	add_child(panel)
	_spawn_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_spawn_label.offset_left = 12
	_spawn_label.offset_top = 12
	_spawn_label.add_theme_font_size_override("font_size", 11)
	_spawn_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	_spawn_label.text = (
		"SPAWN:  1 Aster  2 Peris  3 Endo\n" +
		"        4 Chelator  5 Fluor  6 Chain  7 Crust\n" +
		"        8 Neutrophil  9 Iron Bloom\n" +
		"CTRL:   Click move  RClick spawn  Del remove  C clear\n" +
		"        Space pause  Tab switch  P perception  F fast"
	)
	panel.add_child(_spawn_label)

func _begin() -> void:
	pass

func _compute_speed() -> float:
	if _scheduler.is_paused():
		return 0.0
	return 10.0 if Input.is_key_pressed(KEY_F) else 1.0

func _on_process(delta: float, spd: float) -> void:
	# Animate spawned entities
	for node in _spawned_entities:
		if not is_instance_valid(node):
			continue
		if node.has_meta("entity_type"):
			var etype: String = node.get_meta("entity_type")
			match etype:
				"chelator":
					node.position.x += delta * spd * 0.3
					node.rotation.y += delta * spd * 0.8
					if node.position.x > FLOOR_SIZE / 2.0:
						node.position.x -= FLOOR_SIZE - 2.0
				"fluor":
					node.position.y += sin(Time.get_ticks_msec() * 0.002 + node.position.x) * delta * 0.3
				"chain":
					# Breathing sway
					var seg_parent: Node3D = node
					for child in seg_parent.get_children():
						if child is MeshInstance3D:
							child.rotation.x = sin(Time.get_ticks_msec() * 0.001 + child.position.y) * 0.05
				"neutrophil":
					node.position.x += delta * spd * 0.8 * sin(Time.get_ticks_msec() * 0.003)
					node.position.z += delta * spd * 0.8 * cos(Time.get_ticks_msec() * 0.003 + 1.0)

# --- Input ---

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		match kc:
			KEY_SPACE:
				_toggle_pause()
			KEY_TAB:
				_cycle_character()
			KEY_P:
				_cycle_perception()
			KEY_C:
				_clear_entities()
			KEY_1:
				_spawn_character_at_center("aster", "Aster", Color(0.29, 0.62, 1.0))
			KEY_2:
				_spawn_character_at_center("peris", "Peris", Color(1.0, 0.67, 0.27))
			KEY_3:
				_spawn_npc_at_center("endo", "Endo", Color(0.4, 0.7, 0.55))
			KEY_4:
				_spawn_entity_at_cursor("chelator")
			KEY_5:
				_spawn_entity_at_cursor("fluor")
			KEY_6:
				_spawn_entity_at_cursor("chain")
			KEY_7:
				_spawn_entity_at_cursor("crust")
			KEY_8:
				_spawn_entity_at_cursor("neutrophil")
			KEY_9:
				_spawn_entity_at_cursor("iron_bloom")
			KEY_DELETE:
				_remove_nearest_entity()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			# Spawn last-used entity type at click position
			var pos := _raycast_floor(mb.position)
			if pos != Vector3.INF:
				_spawn_entity_at_pos("chelator", pos)

func _toggle_pause() -> void:
	if _scheduler.is_paused():
		_scheduler.resume()
	else:
		_scheduler.pause()
	_hud.set_paused(_scheduler.is_paused())

func _cycle_character() -> void:
	if _spawned_characters.size() == 0:
		return
	var next: String = _hud.get_next_portrait_id(_active_char_id)
	_select_character(next)

func _select_character(id: String) -> void:
	if id == _active_char_id or not _spawned_characters.has(id):
		return
	if _active_char_id != "" and _spawned_characters.has(_active_char_id):
		_spawned_characters[_active_char_id].set_move_enabled(false)
	_active_char_id = id
	var node: Node3D = _spawned_characters[id]
	if node.has_method("set_move_enabled"):
		node.set_move_enabled(true)
	_player = node
	_camera.target = node
	_hud.set_active_portrait(id)

func _on_character_selected(selected_ids: Array) -> void:
	if selected_ids.size() > 0:
		_select_character(selected_ids[0])

func _cycle_perception() -> void:
	_perception_cycle = (_perception_cycle + 1) % 3
	match _perception_cycle:
		0:
			if _perception_quad:
				_perception_quad.visible = false
			_hud.show_message("Perception: OFF", 1.5)
		1:
			var target: Node3D = _spawned_characters.get(_active_char_id, null)
			if target:
				_setup_perception("data", target)
			_hud.show_message("Perception: DATA (Aster)", 1.5)
		2:
			var target: Node3D = _spawned_characters.get(_active_char_id, null)
			if target:
				_setup_perception("fog", target)
			_hud.show_message("Perception: FOG (Peris)", 1.5)

# --- Spawning ---

func _spawn_character_at_center(id: String, display_name: String, color: Color) -> void:
	if _spawned_characters.has(id):
		_hud.show_message("%s already spawned" % display_name, 1.5)
		return
	var offset := Vector3(_spawned_characters.size() * 2.0 - 2.0, 0.5, 0)
	var p := _create_player_character(display_name, color)
	p.position = offset
	add_child(p)
	_register_gs_character(id, p, 3.0)
	_spawned_characters[id] = p

	_hud.add_portrait(id, display_name, color)
	if _active_char_id == "":
		_select_character(id)
	else:
		p.set_move_enabled(false)

func _spawn_npc_at_center(id: String, display_name: String, color: Color) -> void:
	if _spawned_characters.has(id):
		_hud.show_message("%s already spawned" % display_name, 1.5)
		return
	var offset := Vector3(_spawned_characters.size() * 2.0 - 2.0, 0, -1.5)
	var npc := _create_npc(display_name, color)
	npc.position = offset
	add_child(npc)
	_register_gs_character(id, npc, 2.5)
	_spawned_characters[id] = npc
	_hud.add_portrait(id, display_name, color)

func _spawn_entity_at_cursor(etype: String) -> void:
	var pos := Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
	_spawn_entity_at_pos(etype, pos)

func _spawn_entity_at_pos(etype: String, pos: Vector3) -> void:
	var node: Node3D
	match etype:
		"chelator":
			node = _make_chelator()
		"fluor":
			node = _make_fluor()
		"chain":
			node = _make_chain()
		"crust":
			node = _make_crust()
		"neutrophil":
			node = _make_neutrophil()
		"iron_bloom":
			node = _make_iron_bloom()
		_:
			return
	node.position = pos
	node.set_meta("entity_type", etype)
	add_child(node)
	_spawned_entities.append(node)

func _remove_nearest_entity() -> void:
	if _spawned_entities.size() == 0:
		return
	var cam_pos: Vector3 = _camera.global_position if _camera else Vector3.ZERO
	var nearest: Node3D = null
	var best_dist := INF
	for e in _spawned_entities:
		if is_instance_valid(e):
			var d := e.global_position.distance_to(cam_pos)
			if d < best_dist:
				best_dist = d
				nearest = e
	if nearest:
		_spawned_entities.erase(nearest)
		nearest.queue_free()

func _clear_entities() -> void:
	for e in _spawned_entities:
		if is_instance_valid(e):
			e.queue_free()
	_spawned_entities.clear()
	# Remove characters
	for id in _spawned_characters.keys():
		var node: Node3D = _spawned_characters[id]
		if is_instance_valid(node):
			_game_state.unregister_character(id)
			node.queue_free()
		_hud.remove_portrait(id)
	_spawned_characters.clear()
	_active_char_id = ""
	_hud.show_message("Cleared", 1.0)

# --- Entity Builders ---

func _make_chelator() -> Node3D:
	var root := Node3D.new()
	root.name = "Chelator"
	# Ring body
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.04
	tm.outer_radius = 0.12
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.25, 0.15)
	mat.metallic = 0.6
	mat.roughness = 0.3
	ring.material_override = mat
	ring.position.y = 0.15
	root.add_child(ring)
	# Six legs
	for i in range(6):
		var leg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.01, 0.06, 0.01)
		leg.mesh = bm
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.3, 0.2, 0.12)
		lm.metallic = 0.5
		leg.material_override = lm
		var angle := i * TAU / 6.0
		leg.position = Vector3(cos(angle) * 0.1, 0.08, sin(angle) * 0.1)
		root.add_child(leg)
	return root

func _make_fluor() -> Node3D:
	var root := Node3D.new()
	root.name = "Fluor"
	# Teardrop body (squashed sphere)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.4
	body.mesh = sm
	body.scale = Vector3(0.8, 1.2, 0.8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.7, 0.15, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 0.2)
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.material_override = mat
	body.position.y = 0.25
	root.add_child(body)
	# Trailing filament
	var fil := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.01
	cm.bottom_radius = 0.005
	cm.height = 0.3
	fil.mesh = cm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.6, 0.15, 0.4)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.emission_enabled = true
	fm.emission = Color(0.4, 0.7, 0.15)
	fm.emission_energy_multiplier = 0.5
	fil.material_override = fm
	fil.position = Vector3(0, 0.0, 0.15)
	fil.rotation.x = 0.3
	root.add_child(fil)
	# Glow light
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.9, 0.2)
	light.light_energy = 0.8
	light.omni_range = 3.5
	light.position.y = 0.25
	root.add_child(light)
	return root

func _make_chain() -> Node3D:
	# Looks like a pipe or wire when idle — horizontal, dark, metallic
	var root := Node3D.new()
	root.name = "Chain"
	var seg_count := 5
	for i in range(seg_count):
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 0.5
		seg.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.1, 0.12)
		mat.metallic = 0.7
		mat.roughness = 0.4
		seg.material_override = mat
		# Horizontal: rotate to lie along X, segments side by side
		seg.rotation.z = PI / 2.0
		seg.position = Vector3(i * 0.48, 0.5, 0)
		root.add_child(seg)
		# Rust-red joint between segments (subtle)
		if i > 0:
			var joint := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.03
			tm.outer_radius = 0.06
			joint.mesh = tm
			var jm := StandardMaterial3D.new()
			jm.albedo_color = Color(0.35, 0.12, 0.08)
			jm.metallic = 0.5
			joint.material_override = jm
			joint.rotation.z = PI / 2.0
			joint.position = Vector3(i * 0.48 - 0.24, 0.5, 0)
			root.add_child(joint)
	return root

func _make_crust() -> Node3D:
	var root := Node3D.new()
	root.name = "Crust"
	var patch := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 0.02, 1.5)
	patch.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.25, 0.15)
	mat.metallic = 0.2
	mat.roughness = 0.8
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.15, 0.08)
	mat.emission_energy_multiplier = 0.3
	patch.material_override = mat
	patch.position.y = 0.01
	root.add_child(patch)
	# Hair-like filaments
	for i in range(8):
		var hair := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.003
		cm.bottom_radius = 0.005
		cm.height = 0.08
		hair.mesh = cm
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.5, 0.3, 0.2, 0.6)
		hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hair.material_override = hm
		hair.position = Vector3(randf_range(-0.6, 0.6), 0.05, randf_range(-0.6, 0.6))
		root.add_child(hair)
	return root

func _make_neutrophil() -> Node3D:
	var root := Node3D.new()
	root.name = "Neutrophil"
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	body.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.05, 0.05)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.15, 0.1)
	mat.emission_energy_multiplier = 1.0
	body.material_override = mat
	body.position.y = 0.3
	root.add_child(body)
	# Red eyes
	for z_off in [-0.08, 0.08]:
		var eye := OmniLight3D.new()
		eye.light_color = Color(0.9, 0.1, 0.05)
		eye.light_energy = 0.5
		eye.omni_range = 1.5
		eye.position = Vector3(0.15, 0.35, z_off)
		root.add_child(eye)
	# Body glow
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.7, 0.1, 0.05)
	glow.light_energy = 0.6
	glow.omni_range = 3.0
	glow.position.y = 0.3
	root.add_child(glow)
	return root

func _make_iron_bloom() -> Node3D:
	var root := Node3D.new()
	root.name = "IronBloom"
	# Rusty floor patch
	var patch := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0, 0.02, 2.0)
	patch.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.2, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.2, 0.05)
	mat.emission_energy_multiplier = 0.4
	patch.material_override = mat
	patch.position.y = 0.01
	root.add_child(patch)
	# Orange glow
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.3, 0.1)
	light.light_energy = 1.5
	light.omni_range = 4.0
	light.position.y = 0.5
	root.add_child(light)
	# Label
	var lbl := Label3D.new()
	lbl.text = "Fe"
	lbl.font_size = 32
	lbl.modulate = Color(0.7, 0.3, 0.1, 0.6)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position.y = 1.0
	root.add_child(lbl)
	return root

# --- Environment ---

func _build_environment() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	# Floor
	var floor_mesh := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(FLOOR_SIZE, 0.1, FLOOR_SIZE)
	floor_mesh.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = FLOOR_COLOR
	floor_mesh.material_override = fm
	floor_mesh.position.y = -0.05
	env.add_child(floor_mesh)

	# Floor collision
	var body := StaticBody3D.new()
	body.position.y = -0.01
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(FLOOR_SIZE, 0.02, FLOOR_SIZE)
	col.shape = shape
	body.add_child(col)
	env.add_child(body)

	# Grid lines
	for i in range(-int(FLOOR_SIZE / 2.0), int(FLOOR_SIZE / 2.0) + 1, 2):
		for axis in [0, 1]:
			var line := MeshInstance3D.new()
			var bm := BoxMesh.new()
			if axis == 0:
				bm.size = Vector3(FLOOR_SIZE, 0.005, 0.01)
				line.position = Vector3(0, 0.001, float(i))
			else:
				bm.size = Vector3(0.01, 0.005, FLOOR_SIZE)
				line.position = Vector3(float(i), 0.001, 0)
			line.mesh = bm
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(0.15, 0.15, 0.18, 0.3)
			lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			line.material_override = lm
			env.add_child(line)

	# Directional light
	var dir := DirectionalLight3D.new()
	dir.rotation_degrees = Vector3(-50, 30, 0)
	dir.light_color = Color(0.6, 0.55, 0.5)
	dir.light_energy = 0.4
	dir.shadow_enabled = true
	env.add_child(dir)

	# Ambient fill
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.12, 0.1, 0.08)
	e.ambient_light_energy = 0.3
	we.environment = e
	env.add_child(we)

	# Wall segment for LOS testing
	_add_wall(env, Vector3(8, 2, 0), Vector3(0.3, 4, 6), Color(0.12, 0.12, 0.15))

	# Iron bloom zone in corner
	var bloom_light := OmniLight3D.new()
	bloom_light.position = Vector3(-10, 0.5, -10)
	bloom_light.light_color = Color(0.7, 0.3, 0.1)
	bloom_light.light_energy = 1.5
	bloom_light.omni_range = 5.0
	env.add_child(bloom_light)

	# Shelter structure
	_add_wall(env, Vector3(10, 1.5, 10), Vector3(4, 3, 0.2), Color(0.15, 0.15, 0.18))
	_add_wall(env, Vector3(10, 1.5, 12), Vector3(4, 3, 0.2), Color(0.15, 0.15, 0.18))
	_add_wall(env, Vector3(12, 1.5, 11), Vector3(0.2, 3, 2.4), Color(0.15, 0.15, 0.18))
	var shelter_light := OmniLight3D.new()
	shelter_light.position = Vector3(10, 2, 11)
	shelter_light.light_color = Color(0.8, 0.6, 0.35)
	shelter_light.light_energy = 1.0
	shelter_light.omni_range = 4.0
	env.add_child(shelter_light)
	var shelter_lbl := Label3D.new()
	shelter_lbl.text = "SHELTER"
	shelter_lbl.font_size = 24
	shelter_lbl.modulate = Color(0.8, 0.6, 0.3, 0.7)
	shelter_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shelter_lbl.position = Vector3(10, 3.5, 11)
	env.add_child(shelter_lbl)

	# Camera
	if not Engine.is_editor_hint():
		_setup_game_camera(null, Vector3(0, 12, 8))
		_camera.set_pan_enabled(true)

# --- Helpers ---

func _raycast_floor(screen_pos: Vector2) -> Vector3:
	if not _camera:
		return Vector3.INF
	var from: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.001:
		return Vector3.INF
	var t: float = -from.y / dir.y
	if t < 0:
		return Vector3.INF
	return from + dir * t
