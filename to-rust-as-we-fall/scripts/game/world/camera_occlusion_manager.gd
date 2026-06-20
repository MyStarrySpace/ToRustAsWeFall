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
	if game_state != null and watch_id != "" and game_state.characters.has(watch_id):
		return game_state.get_render_position(watch_id)
	if _player_node != null and is_instance_valid(_player_node):
		return _player_node.global_position
	return Vector3.INF

## Wrap every mesh surface under `root` with the occlusion shader. Returns the surface count wrapped.
## Call once after the level model has loaded (and after any emissive-sidecar wiring).
func apply_to(root: Node) -> int:
	if root == null:
		return 0
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	var count := 0
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# A whole-mesh material_override wins over per-surface overrides, so wrap THAT; otherwise wrap each
		# surface so per-surface materials (the gltf case) are preserved.
		if mi.material_override != null:
			mi.material_override = _wrap(mi.material_override)
			count += 1
			continue
		for s in range(mi.mesh.get_surface_count()):
			mi.set_surface_override_material(s, _wrap(mi.get_active_material(s)))
			count += 1
	return count

## Build a ShaderMaterial that runs the occlusion shader but looks like `src` (a StandardMaterial3D).
## Non-standard sources still get the shader (the level stays see-through), just with default surfacing.
func _wrap(src: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OCCLUSION_SHADER
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
