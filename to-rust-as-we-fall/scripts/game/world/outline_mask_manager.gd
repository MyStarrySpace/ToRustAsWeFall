class_name OutlineMaskManager
extends Node3D

## Scene-level SCREEN-SPACE object outline. The highlight system used to wrap each object in an inverted-hull
## shell, which TEARS on the project's flat-shaded pixel-art meshes (per-face normals expand inconsistently) and
## thins out with camera distance. This renders the currently-highlighted objects ALONE into a SubViewport —
## each filled with its tint colour, opaque on a transparent background (the "mask") — and composites a Sobel
## edge of that mask over the main view with a fullscreen quad. The mask is a flat solid, so its only edge is
## each object's OUTER silhouette: clean, gap-free, constant pixel width at any distance, immune to the geometry's
## normals, and inherently limited to the masked objects. Per-object tint falls out of the mask's own colour.
##
## One per scene (created by tutorial_sequence, like PathRenderManager). OutlineSurfaceTarget.register/unregister
## drive it; everything here is purely cosmetic (reads transforms, writes nothing to the data layer).

const MASK_SHADER := preload("res://resources/screen_outline_mask.gdshader")
const FILL_SHADER := preload("res://resources/outline_mask_fill.gdshader")

# The fill ALPHA encodes intent (read back by the composite): a HOVER object outlines only, a QUEUED one also
# radiates the energy glow. Kept well apart so the shader's queued_threshold separates them cleanly.
const HOVER_ALPHA := 0.5
const QUEUED_ALPHA := 1.0

@export var thickness := 2.0
@export var glow := 1.15
@export var glow_radius := 22.0
@export var glow_strength := 2.4
@export var fallback_color := Color.WHITE

static var _shared_noise_tex: Texture2D

var _sub: SubViewport
var _sub_cam: Camera3D
var _quad: MeshInstance3D
var _mask_mat: ShaderMaterial
var _entries := {}     # key:int -> { color:Color, copies:Array[Dictionary{copy,src}] }
var _built := false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_ensure_built()

func _ensure_built() -> void:
	if _built:
		return
	_built = true

	_sub = SubViewport.new()
	_sub.name = "OutlineMaskViewport"
	_sub.own_world_3d = true
	_sub.transparent_bg = true
	_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED   # only renders while something is highlighted
	_sub.handle_input_locally = false
	_sub.msaa_3d = Viewport.MSAA_DISABLED
	_sub.size = _viewport_size()
	add_child(_sub)

	_sub_cam = Camera3D.new()
	_sub_cam.name = "OutlineMaskCamera"
	_sub.add_child(_sub_cam)
	_sub_cam.current = true

	_quad = MeshInstance3D.new()
	_quad.name = "OutlineMaskComposite"
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	_quad.mesh = qm
	_mask_mat = ShaderMaterial.new()
	_mask_mat.shader = MASK_SHADER
	# Compose late so it reads the rendered scene, but BELOW the perception-overlay quad (render_priority 126)
	# and the UI ribbons/ghosts/rings (127) — the outline is object feedback, not a perception layer.
	_mask_mat.render_priority = 8
	_mask_mat.set_shader_parameter("mask_tex", _sub.get_texture())
	_mask_mat.set_shader_parameter("thickness", thickness)
	_mask_mat.set_shader_parameter("glow", glow)
	_mask_mat.set_shader_parameter("glow_radius", glow_radius)
	_mask_mat.set_shader_parameter("glow_strength", glow_strength)
	_mask_mat.set_shader_parameter("noise_tex", _noise_texture())
	_mask_mat.set_shader_parameter("fallback_color", fallback_color)
	_quad.material_override = _mask_mat
	_quad.extra_cull_margin = 1.0e6   # the vertex shader places it fullscreen; never frustum-cull it
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.visible = false             # only composite while something is highlighted
	add_child(_quad)

func _viewport_size() -> Vector2i:
	var vp := get_viewport()
	if vp == null:
		return Vector2i(1152, 648)
	var s := vp.get_visible_rect().size
	return Vector2i(maxi(8, int(s.x)), maxi(8, int(s.y)))

## (Re)register an object's meshes for outlining at `color`. `glow` = true adds the queued energy halo (a queued
## interaction), false = outline only (hover). `key` is the owning target's instance id.
func register(key: int, meshes: Array, color: Color, glow_on: bool = false) -> void:
	if Engine.is_editor_hint():
		return
	_ensure_built()
	if _entries.has(key):
		# Already shown — just retint + flip the glow flag (hover -> queued recolours/relights the same object).
		set_color(key, color, glow_on)
		return
	var copies: Array = []
	var fill_alpha: float = QUEUED_ALPHA if glow_on else HOVER_ALPHA
	for m in meshes:
		if not (m is MeshInstance3D) or (m as MeshInstance3D).mesh == null:
			continue
		var src := m as MeshInstance3D
		var copy := MeshInstance3D.new()
		copy.mesh = src.mesh
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.extra_cull_margin = maxf(src.extra_cull_margin, 4.0)
		_apply_fill_materials(copy, src, color, fill_alpha)
		_sub.add_child(copy)
		copy.global_transform = src.global_transform
		copies.append({"copy": copy, "src": src})
	_entries[key] = {"color": color, "glow": glow_on, "copies": copies}
	_refresh_visibility()

func set_color(key: int, color: Color, glow_on: bool = false) -> void:
	var e = _entries.get(key)
	if e == null:
		return
	e["color"] = color
	e["glow"] = glow_on
	var fill_alpha: float = QUEUED_ALPHA if glow_on else HOVER_ALPHA
	for c in e["copies"]:
		var copy := c["copy"] as MeshInstance3D
		if not is_instance_valid(copy):
			continue
		for s in range(copy.mesh.get_surface_count() if copy.mesh != null else 0):
			var mat := copy.get_surface_override_material(s) as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter("fill_color", color)
				mat.set_shader_parameter("fill_alpha", fill_alpha)

func unregister(key: int) -> void:
	var e = _entries.get(key)
	if e == null:
		return
	for c in e["copies"]:
		var copy := c["copy"] as MeshInstance3D
		if is_instance_valid(copy):
			copy.queue_free()
	_entries.erase(key)
	_refresh_visibility()

func is_registered(key: int) -> bool:
	return _entries.has(key)

func _refresh_visibility() -> void:
	var active := not _entries.is_empty()
	if _quad != null:
		_quad.visible = active
	# Don't re-render an empty mask viewport every frame during normal play (nothing hovered is the common case).
	if _sub != null:
		_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED

## Per-surface fill material: a flat tint at `fill_alpha` (the glow flag), with alpha-cutout discard when the
## source surface is transparent (so foliage/decals mask to the leaf shape, not the bounding quad).
func _apply_fill_materials(copy: MeshInstance3D, src: MeshInstance3D, color: Color, fill_alpha: float) -> void:
	var surfaces: int = copy.mesh.get_surface_count() if copy.mesh != null else 0
	for s in range(surfaces):
		var mat := ShaderMaterial.new()
		mat.shader = FILL_SHADER
		mat.set_shader_parameter("fill_color", color)
		mat.set_shader_parameter("fill_alpha", fill_alpha)
		var source := src.get_active_material(s)
		if source is BaseMaterial3D:
			var base := source as BaseMaterial3D
			var transparent: bool = base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or base.albedo_color.a < 0.999
			if transparent and base.albedo_texture != null:
				mat.set_shader_parameter("use_alpha", true)
				mat.set_shader_parameter("src_albedo", base.albedo_texture)
		copy.set_surface_override_material(s, mat)

## Shared morphing-noise texture for the energy-glow halo (one synchronous seamless image for all managers).
static func _noise_texture() -> Texture2D:
	if _shared_noise_tex != null:
		return _shared_noise_tex
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	_shared_noise_tex = ImageTexture.create_from_image(noise.get_seamless_image(256, 256))
	return _shared_noise_tex

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not _built:
		return
	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	var want := _viewport_size()
	if _sub.size != want:
		_sub.size = want
	# Mirror the main camera so the mask projects identically to the main render.
	_sub_cam.global_transform = cam.global_transform
	_sub_cam.fov = cam.fov
	_sub_cam.projection = cam.projection
	_sub_cam.near = cam.near
	_sub_cam.far = cam.far
	_sub_cam.size = cam.size
	_sub_cam.keep_aspect = cam.keep_aspect
	# Follow each highlighted object so the mask tracks it (moving props, the helix deck, etc.).
	for key in _entries.keys():
		var e = _entries[key]
		var alive := false
		for c in e["copies"]:
			var copy := c["copy"] as MeshInstance3D
			var src := c["src"] as MeshInstance3D
			if is_instance_valid(copy) and is_instance_valid(src):
				copy.global_transform = src.global_transform
				alive = true
		# The source object was freed (chunk reload) — drop the stale registration.
		if not alive and not e["copies"].is_empty():
			unregister(key)

## Find the OutlineMaskManager for `context`'s branch (the one tutorial_sequence created for the scene), or null.
## FIND-ONLY by design: a headless test or a standalone OutlineSurfaceTarget must not spawn a SubViewport — when
## no manager is present the target just keeps its logical outline flag and skips the screen-space render.
static func find_for(context: Node) -> OutlineMaskManager:
	var node := context
	while node != null:
		for child in node.get_children():
			if child is OutlineMaskManager:
				return child as OutlineMaskManager
		node = node.get_parent()
	return null
