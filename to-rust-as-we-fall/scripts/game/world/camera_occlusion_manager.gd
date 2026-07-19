class_name CameraOcclusionManager
extends Node

## See-through level occlusion. Level geometry that comes BETWEEN the camera and the watched character
## dither-dissolves in a circle around that character on screen, so the player is never lost behind a wall
## (the standard "see-through wall" shader, with this project's pixel-dither hole instead of a smooth fade).
##
## REUSABLE, scene-level — add ONE per scene, point it at the GameState (+ the lead char_id) or a player
## node, and call apply_to(level_root). The shader reads a single GLOBAL uniform (player_world_pos) which
## this node writes every frame, so all wrapped materials reveal around the same point. apply_to() wraps
## each mesh surface with the occlusion shader, COPYING albedo / emission / normal / roughness / metallic
## from the source StandardMaterial3D so the level's look (including the emissive glow) survives the swap.
##
## Purely cosmetic: it sets a render uniform + swaps materials, never touches game state.

const OCCLUSION_SHADER := preload("res://resources/camera_occlusion.gdshader")
const PLAYER_PARAM := "player_world_pos"

## Either drive the reveal from the data layer (preferred)...
var game_state                       # GameState; reads get_render_position(watch_id)
var watch_id := ""                   # the lead/active character whose position the level reveals around
## ...or from a plain node (fallback when there's no GameState).
var _player_node: Node3D

func set_player(node: Node3D) -> void:
	_player_node = node

func set_watch(state, char_id: String) -> void:
	game_state = state
	watch_id = char_id

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var pos := _watch_pos()
	if pos.is_finite():
		RenderingServer.global_shader_parameter_set(PLAYER_PARAM, pos)

func _watch_pos() -> Vector3:
	if game_state != null:
		# Track the watched (active/lead) character; if its id isn't set/registered yet, fall back to ANY
		# registered character so the reveal centre is never left stale at the origin (the "hole is in the
		# wrong place / not on the player" failure mode).
		if watch_id != "" and game_state.characters.has(watch_id):
			return game_state.get_render_position(watch_id)
		for cid in game_state.characters.keys():
			return game_state.get_render_position(cid)
	if _player_node != null and is_instance_valid(_player_node):
		return _player_node.global_position
	return Vector3.INF

## Wrap every mesh surface under `root` with the occlusion shader. Returns the surface count wrapped.
## `minimum_occluder_height` is useful for procedural chunk roots: it limits wrapping to wall/ceiling-scale
## geometry, preserving low animated props whose scripts retain references to their original materials.
## Imported environment models should use the default and wrap every compatible surface.
func apply_to(root: Node, minimum_occluder_height := 0.0) -> int:
	if root == null:
		return 0
	var outline_safe_clip := bool(root.get_meta("camera_occlusion_outline_safe_clip", false))
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	var count := 0
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if bool(mi.get_meta("camera_occlusion_exempt", false)) or mi.is_in_group("camera_occlusion_exempt"):
			continue
		if minimum_occluder_height > 0.0 and mi.get_aabb().size.y < minimum_occluder_height:
			continue
		# A whole-mesh material_override wins over per-surface overrides, so wrap THAT; otherwise wrap each
		# surface so per-surface materials (the gltf case) are preserved.
		if mi.material_override != null:
			var wrapped_override := _wrap(mi.material_override, outline_safe_clip)
			if wrapped_override != null:
				mi.material_override = wrapped_override
				count += 1
			continue
		for s in range(mi.mesh.get_surface_count()):
			var active_surface := mi.get_active_material(s)
			if active_surface == null:
				continue
			var wrapped_surface := _wrap(active_surface, outline_safe_clip)
			if wrapped_surface != null:
				mi.set_surface_override_material(s, wrapped_surface)
				count += 1

	# LevelDecorator batches its dense render-only facade grammar into MultiMeshInstance3D nodes.
	# They are GeometryInstance3D siblings of MeshInstance3D, not subclasses, so the scan above cannot
	# see them. Their whole-instance override is sufficient to dissolve every instance in the batch.
	var multimeshes: Array = root.find_children("*", "MultiMeshInstance3D", true, false)
	if root is MultiMeshInstance3D:
		multimeshes.append(root)
	for n in multimeshes:
		var multimesh_instance := n as MultiMeshInstance3D
		if multimesh_instance == null or multimesh_instance.multimesh == null:
			continue
		if bool(multimesh_instance.get_meta("camera_occlusion_exempt", false)) \
				or multimesh_instance.is_in_group("camera_occlusion_exempt"):
			continue
		if minimum_occluder_height > 0.0 and multimesh_instance.get_aabb().size.y < minimum_occluder_height:
			continue
		if multimesh_instance.material_override != null:
			var wrapped_multimesh := _wrap(multimesh_instance.material_override, outline_safe_clip)
			if wrapped_multimesh != null:
				multimesh_instance.material_override = wrapped_multimesh
				count += 1
	return count

## Build a ShaderMaterial that runs the occlusion shader but looks like `src` (a StandardMaterial3D).
## Authored ShaderMaterials are returned untouched by the caller because replacing them would erase
## water, outline, fog, and other effect behavior.
func _wrap(src: Material, outline_safe_clip := false) -> ShaderMaterial:
	# Water, outlines, fog surfaces, and other authored ShaderMaterials encode behavior that
	# cannot be reconstructed from StandardMaterial fields. Leave them intact; procedural
	# walls/ceilings and imported GLB surfaces are the actual occlusion targets.
	if src is ShaderMaterial:
		return null
	var m := ShaderMaterial.new()
	m.shader = OCCLUSION_SHADER
	m.set_shader_parameter("outline_safe_clip", outline_safe_clip)
	if src is StandardMaterial3D:
		var std := src as StandardMaterial3D
		m.set_shader_parameter("albedo_color", std.albedo_color)
		m.set_shader_parameter("albedo_tex", std.albedo_texture)
		m.set_shader_parameter("roughness", std.roughness)
		m.set_shader_parameter("metallic", std.metallic)
		if std.emission_enabled:
			m.set_shader_parameter("emission_color", std.emission)
			m.set_shader_parameter("emission_tex", std.emission_texture)
			m.set_shader_parameter("emission_energy", std.emission_energy_multiplier)
		if std.normal_enabled:
			m.set_shader_parameter("normal_tex", std.normal_texture)
			m.set_shader_parameter("normal_scale", std.normal_scale)
	return m
