class_name PortalLens
extends Node3D

## The portal APERTURE VIEW (docs/PORTALS.md): the arch opening renders the DESTINATION
## with true parallax — the mirrored-camera SubViewport technique lifted from the Peris
## portal (`peris_sim_sequence._build_portal_view` / `_update_portal_view`), made
## reusable. Purely cosmetic (@rendering_only): gameplay never reads it, and a headless
## or camera-less run no-ops. One PortalLens per aperture; a bidirectional pair gets two.
##
## Frame convention: this node's transform IS the source aperture (local +Z = the axis
## you look through); `dest_xf` is the paired aperture in the same convention. The lens
## camera mirrors the live camera through the pair with the standard portal flip, so the
## view exits the far aperture's back — walk around the arch and the destination
## parallaxes like a hole in the world.

const LENS_SHADER := preload("res://resources/portal_lens.gdshader")
const FLIP := Basis(Vector3.UP, PI)
const MAX_VIEW_SIZE := 768

var _vp: SubViewport
var _cam: Camera3D
var _surface: MeshInstance3D
var _dest_xf := Transform3D.IDENTITY

## `world` non-null: render THAT world from the destination (same-scene pairs pass their
## own World3D). Null: the viewport owns a private world (a true-elsewhere lens — the
## caller then populates get_far_world_root()).
func setup(src_xf: Transform3D, dest_xf: Transform3D, aperture_radius: float,
		world: World3D = null) -> void:
	global_transform = src_xf
	_dest_xf = dest_xf
	_vp = SubViewport.new()
	_vp.name = "LensViewport"
	_vp.size = Vector2i(384, 384)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.handle_input_locally = false
	if world != null:
		_vp.world_3d = world
	else:
		_vp.own_world_3d = true
	add_child(_vp)
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_surface = MeshInstance3D.new()
	_surface.name = "LensSurface"
	var disc := CylinderMesh.new()
	disc.top_radius = aperture_radius
	disc.bottom_radius = aperture_radius
	disc.height = 0.02
	_surface.mesh = disc
	_surface.rotation = Vector3(PI * 0.5, 0.0, 0.0)   # cylinder axis -> local +Z (the look axis)
	var mat := ShaderMaterial.new()
	mat.shader = LENS_SHADER
	mat.set_shader_parameter("view_texture", _vp.get_texture())
	_surface.material_override = mat
	add_child(_surface)

func _process(_delta: float) -> void:
	if _vp == null or _cam == null:
		return
	var live := get_viewport().get_camera_3d() if is_inside_tree() else null
	if live == null:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# Render only while the aperture can be on screen — a lens behind the camera is free.
	if not live.is_position_in_frustum(global_position):
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var want := Vector2i(get_viewport().get_visible_rect().size)
	want = Vector2i(mini(want.x, MAX_VIEW_SIZE), mini(want.y, MAX_VIEW_SIZE))
	if want.x > 0 and want.y > 0 and _vp.size != want:
		_vp.size = want
	var dest_flipped := Transform3D(_dest_xf.basis * FLIP, _dest_xf.origin)
	_cam.fov = live.fov
	_cam.global_transform = dest_flipped * (global_transform.affine_inverse() * live.global_transform)
	# Clip everything between the far aperture and the mirrored camera (the wall the
	# portal is "cut into" must not block its own view).
	var depth := (_cam.global_transform.origin - _dest_xf.origin).length()
	_cam.near = clampf(depth - 0.15, 0.05, 4.0)
