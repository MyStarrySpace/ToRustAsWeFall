class_name PathRenderManager
extends Node3D

## Scene-level movement-path rendering. Add ONE of these per scene, point it at the GameState, and
## it draws a path ribbon for EVERY registered character that is moving (or has a queued move) —
## player, party member, NPC, escort — anchored to that character's node and tinted by it.
##
## This is the REUSABLE home for movement-path visuals. Do NOT bake a PathRenderer into one
## controller (it was in player.gd, so only the single player ever showed a path, and scenes that
## move other characters — the elevator party, escorts — showed nothing). The manager binds the
## GameState/char_id/anchor every frame from the SCENE's perspective, so a path appears regardless
## of whether the character's own node is processing, and a queued move (movement set while the
## scheduler is paused) draws too. Purely cosmetic — it reads the scheduler clock, writes nothing.

var game_state: GameState
var search_root: Node             # where character nodes live (defaults to the parent scene)
var default_color := Color(1.0, 0.7, 0.3)

var _renderers := {}              # char_id -> PathRenderer
var _dest_markers := {}           # char_id -> MeshInstance3D (the destination ring)
var _nodes := {}                  # char_id -> Node3D (cached anchor; re-found if freed)
var _scan_after := {}             # char_id -> frame number gating the next full-tree rescan

func setup(state: GameState, root: Node = null) -> void:
	game_state = state
	search_root = root if root != null else get_parent()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or game_state == null:
		return
	for char_id in game_state.characters.keys():
		var pr: PathRenderer = _renderers.get(char_id)
		if pr == null:
			pr = PathRenderer.new()
			add_child(pr)
			_renderers[char_id] = pr
		var node := _node_for(char_id)
		# A node can opt OUT of the ribbon (NPC ambience walks default off; an escort opts back in).
		var suppressed: bool = node != null and "show_movement_path" in node and not node.show_movement_path
		pr.visible = not suppressed
		if suppressed:
			continue
		# Bind on creation and when the anchor node changes (late creation / chunk reloads), not
		# every frame — the per-frame full re-setup was redundant field churn.
		if pr.game_state != game_state or pr.char_id != char_id or pr.anchor != node:
			pr.setup(game_state, char_id, _color_for(node), node)
		pr.set_running(game_state.is_running(char_id))
		_update_dest_marker(char_id, node)

## A per-character DESTINATION ring at the end of its current move — the marker the player used to carry
## alone, now drawn for EVERY character in that character's colour. It reads the DATA-LAYER move target
## (get_destination), so a party/escort member moved by a group command marks its destination too, not just
## whoever was clicked. Cosmetic: reads the move target + scheduler-driven render position, writes nothing.
func _update_dest_marker(char_id: String, node: Node3D) -> void:
	var marker: MeshInstance3D = _dest_markers.get(char_id)
	var dest_data: Vector3 = game_state.get_destination(char_id)
	if not dest_data.is_finite():
		if marker != null:
			marker.visible = false
		return
	if marker == null:
		marker = _make_dest_marker(_color_for(node))
		add_child(marker)
		_dest_markers[char_id] = marker
	# Re-tint if the anchor's colour resolved late (lazy node find).
	(marker.material_override as StandardMaterial3D).albedo_color = Color(_color_for(node), 0.0)
	var dest_world: Vector3 = dest_data if game_state.coord_map == null else game_state.coord_map.to_world(dest_data)
	if not dest_world.is_finite():
		marker.visible = false
		return
	marker.visible = true
	marker.global_position = Vector3(dest_world.x, dest_world.y + 0.06, dest_world.z)
	var pulse: float = 0.3 + sin(Time.get_ticks_msec() * 0.004) * 0.15  # @rendering_only — destination ring pulse
	(marker.material_override as StandardMaterial3D).albedo_color.a = pulse
	# On flat scenes shrink the ring as the character closes on the target; the helix dest sits on a curved
	# deck so leave it full-size there.
	if game_state.coord_map == null:
		var cur: Vector3 = game_state.get_render_position(char_id)
		var dist: float = Vector2(cur.x - dest_world.x, cur.z - dest_world.z).length()
		var s: float = clampf(dist / 3.0, 0.3, 1.2)
		marker.scale = Vector3(s, s, s)
	else:
		marker.scale = Vector3.ONE

func _make_dest_marker(col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.3
	torus.rings = 16
	torus.ring_segments = 8
	m.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.rotation.x = -PI / 2.0
	m.top_level = true   # authored in world space — we set the global position to the move target
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # a UI overlay, not a caster
	m.layers = 2   # NO_GRID_DECAL_LAYER (player.gd): the hover grid skips the ring too
	return m

func _color_for(node: Node) -> Color:
	if node != null and "color" in node:
		return node.color
	return default_color

func _node_for(char_id: String) -> Node3D:
	var cached = _nodes.get(char_id)
	if cached != null and is_instance_valid(cached):
		return cached
	# Throttle missing-node rescans: a character with no scene node (pure data char) would otherwise
	# trigger a FULL tree scan every frame, forever.
	var next_scan := int(_scan_after.get(char_id, 0))
	var frame := Engine.get_process_frames()
	if cached == null and _nodes.has(char_id) and frame < next_scan:
		return null
	_scan_after[char_id] = frame + 30
	var found := _find_node(char_id)
	_nodes[char_id] = found
	return found

func _find_node(char_id: String) -> Node3D:
	if search_root == null or not is_instance_valid(search_root):
		return null
	for n in search_root.find_children("*", "", true, false):
		if n is Node3D and "char_id" in n and str(n.char_id) == char_id:
			return n
	return null
