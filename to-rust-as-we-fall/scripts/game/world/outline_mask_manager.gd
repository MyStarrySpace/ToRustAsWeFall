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

# TWO mask viewports keep "outline" and "glow" cleanly separate (no fragile opaque-alpha flag): _sub holds EVERY
# highlighted object (drives the crisp outline), _glow_sub holds ONLY the QUEUED objects (drives the energy halo).
# So a HOVER object is structurally absent from the glow pass and can never glow.

@export var thickness := 2.0
@export var glow := 1.15
@export var glow_radius := 22.0
@export var glow_strength := 2.4
@export var fallback_color := Color.WHITE

static var _shared_noise_tex: Texture2D

var _sub: SubViewport          # outline mask: every highlighted object
var _sub_cam: Camera3D
var _glow_sub: SubViewport      # glow mask: queued objects only
var _glow_cam: Camera3D
var _quad: MeshInstance3D
var _mask_mat: ShaderMaterial
var _entries := {}     # key:int -> { color, glow, copies:[{copy,src}], glow_copies:[{copy,src}] }
var _built := false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_ensure_built()

func _ensure_built() -> void:
	if _built:
		return
	_built = true

	_sub = _make_mask_viewport("OutlineMaskViewport")
	add_child(_sub)
	_sub_cam = Camera3D.new()
	_sub_cam.name = "OutlineMaskCamera"
	_sub.add_child(_sub_cam)
	_sub_cam.current = true

	_glow_sub = _make_mask_viewport("OutlineGlowViewport")
	add_child(_glow_sub)
	_glow_cam = Camera3D.new()
	_glow_cam.name = "OutlineGlowCamera"
	_glow_sub.add_child(_glow_cam)
	_glow_cam.current = true

	_quad = MeshInstance3D.new()
	_quad.name = "OutlineMaskComposite"
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	_quad.mesh = qm
	_mask_mat = ShaderMaterial.new()
	_mask_mat.shader = MASK_SHADER
	# Compose ABOVE the perception-overlay quad (render_priority 126): the outline is player feedback and
	# must survive the data/fog views. Safe now that the shader is a premultiplied-alpha BLEND (it never
	# repaints the screen, so it can't erase the perception rewrite the way the old screen_tex copy did).
	_mask_mat.render_priority = 127
	_mask_mat.set_shader_parameter("mask_tex", _sub.get_texture())
	_mask_mat.set_shader_parameter("glow_mask_tex", _glow_sub.get_texture())
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

func _make_mask_viewport(vp_name: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = vp_name
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED   # only renders while it has content
	vp.handle_input_locally = false
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.size = _viewport_size()
	return vp

func _viewport_size() -> Vector2i:
	var vp := get_viewport()
	if vp == null:
		return Vector2i(1152, 648)
	var s := vp.get_visible_rect().size
	return Vector2i(maxi(8, int(s.x)), maxi(8, int(s.y)))

## (Re)register an object's meshes for outlining at `color`. `glow_on` = true ALSO renders the object into the glow
## viewport so it radiates the queued energy halo; false = outline only (hover). `key` is the owning target's id.
func register(key: int, meshes: Array, color: Color, glow_on: bool = false) -> void:
	if Engine.is_editor_hint():
		return
	_ensure_built()
	if _entries.has(key):
		# Already shown — just retint + flip the glow flag (hover -> queued recolours/relights the same object).
		set_color(key, color, glow_on)
		return
	var copies := _spawn_copies(_sub, meshes, color)
	var glow_copies: Array = _spawn_copies(_glow_sub, meshes, color) if glow_on else []
	_entries[key] = {"color": color, "glow": glow_on, "copies": copies, "glow_copies": glow_copies}
	_refresh_visibility()

## Mesh copies of `meshes` parented into `vp`, filled flat with `color`, transform synced once. Returned as
## [{copy, src}] so _process can keep each copy tracking its source.
func _spawn_copies(vp: SubViewport, meshes: Array, color: Color) -> Array:
	var copies: Array = []
	for m in meshes:
		if not (m is MeshInstance3D) or (m as MeshInstance3D).mesh == null:
			continue
		var src := m as MeshInstance3D
		var copy := MeshInstance3D.new()
		# The GLES3 and dummy renderers query mesh-surface shader parameters before
		# consulting an instance override. A shared primitive with a null base material
		# therefore logs an error exactly when hover creates its mask copy. Give every
		# private mask mesh an explicit fill material at both levels.
		copy.mesh = src.mesh.duplicate()
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.extra_cull_margin = maxf(src.extra_cull_margin, 4.0)
		_apply_fill_materials(copy, src, color)
		vp.add_child(copy)
		copy.global_transform = src.global_transform
		copies.append({"copy": copy, "src": src})
	return copies

func set_color(key: int, color: Color, glow_on: bool = false) -> void:
	var e = _entries.get(key)
	if e == null:
		return
	e["color"] = color
	_retint(e["copies"], color)
	# Toggle the glow pass: add copies into the glow viewport when becoming queued, free them when leaving.
	var had_glow: bool = not (e["glow_copies"] as Array).is_empty()
	if glow_on and not had_glow:
		e["glow_copies"] = _spawn_copies(_glow_sub, _source_meshes(e["copies"]), color)
	elif not glow_on and had_glow:
		_free_copies(e["glow_copies"])
		e["glow_copies"] = []
	else:
		_retint(e["glow_copies"], color)
	e["glow"] = glow_on
	_refresh_visibility()

func _retint(copies: Array, color: Color) -> void:
	for c in copies:
		var copy := c["copy"] as MeshInstance3D
		if not is_instance_valid(copy):
			continue
		for s in range(copy.mesh.get_surface_count() if copy.mesh != null else 0):
			var mat := copy.get_surface_override_material(s) as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter("fill_color", color)

func _source_meshes(copies: Array) -> Array:
	var out: Array = []
	for c in copies:
		if is_instance_valid(c["src"]):
			out.append(c["src"])
	return out

func _free_copies(copies: Array) -> void:
	for c in copies:
		var copy := c["copy"] as MeshInstance3D
		if is_instance_valid(copy):
			copy.queue_free()

func unregister(key: int) -> void:
	var e = _entries.get(key)
	if e == null:
		return
	_free_copies(e["copies"])
	_free_copies(e["glow_copies"])
	_entries.erase(key)
	_refresh_visibility()

func is_registered(key: int) -> bool:
	return _entries.has(key)

func _refresh_visibility() -> void:
	var active := not _entries.is_empty()
	var any_glow := false
	for e in _entries.values():
		if not (e["glow_copies"] as Array).is_empty():
			any_glow = true
			break
	if _quad != null:
		_quad.visible = active
	# Don't re-render an empty viewport every frame: outline pass renders while anything is highlighted, the glow
	# pass only while something is QUEUED (the rarer state).
	if _sub != null:
		_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if _glow_sub != null:
		_glow_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS if any_glow else SubViewport.UPDATE_DISABLED

## Per-surface fill material: a flat opaque tint, with alpha-cutout discard when the source surface is transparent
## (so foliage/decals mask to the leaf shape, not the bounding quad).
func _apply_fill_materials(copy: MeshInstance3D, src: MeshInstance3D, color: Color) -> void:
	var surfaces: int = copy.mesh.get_surface_count() if copy.mesh != null else 0
	for s in range(surfaces):
		var mat := ShaderMaterial.new()
		mat.shader = FILL_SHADER
		mat.set_shader_parameter("fill_color", color)
		var source := _source_surface_material(src, s)
		if source is BaseMaterial3D:
			var base := source as BaseMaterial3D
			var transparent: bool = base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or base.albedo_color.a < 0.999
			if transparent and base.albedo_texture != null:
				mat.set_shader_parameter("use_alpha", true)
				mat.set_shader_parameter("src_albedo", base.albedo_texture)
		if copy.mesh is PrimitiveMesh:
			(copy.mesh as PrimitiveMesh).material = mat
		elif copy.mesh is ArrayMesh:
			(copy.mesh as ArrayMesh).surface_set_material(s, mat)
		copy.set_surface_override_material(s, mat)


func _source_surface_material(src: MeshInstance3D, surface: int) -> Material:
	if src.material_override != null:
		return src.material_override
	var override := src.get_surface_override_material(surface)
	if override != null:
		return override
	if src.mesh is PrimitiveMesh:
		return (src.mesh as PrimitiveMesh).material
	if src.mesh is ArrayMesh and surface < (src.mesh as ArrayMesh).get_surface_count():
		return (src.mesh as ArrayMesh).surface_get_material(surface)
	return null

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
	var perf_started := PerformanceTrace.begin()
	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam == null:
		PerformanceTrace.end(&"draw", &"outline_mask.process", perf_started, "no_camera", 0)
		return
	var want := _viewport_size()
	if _sub.size != want:
		_sub.size = want
	if _glow_sub.size != want:
		_glow_sub.size = want
	# Mirror the main camera in BOTH passes so the masks project identically to the main render.
	_sync_cam(_sub_cam, cam)
	_sync_cam(_glow_cam, cam)
	# Follow each highlighted object so the masks track it (moving props, the helix deck, etc.).
	var copy_count := 0
	for key in _entries.keys():
		var e = _entries[key]
		var alive := false
		for c in e["copies"]:
			# Validate BEFORE casting: `as` on a freed instance is itself the error (the roguelike
			# reload frees a chunk's registered meshes while this manager keeps running).
			if not (is_instance_valid(c["copy"]) and is_instance_valid(c["src"])):
				continue
			var copy := c["copy"] as MeshInstance3D
			var src := c["src"] as MeshInstance3D
			copy.global_transform = src.global_transform
			copy_count += 1
			alive = true
		for c in e["glow_copies"]:
			if not (is_instance_valid(c["copy"]) and is_instance_valid(c["src"])):
				continue
			var gcopy := c["copy"] as MeshInstance3D
			var gsrc := c["src"] as MeshInstance3D
			gcopy.global_transform = gsrc.global_transform
			copy_count += 1
		# The source object was freed (chunk reload) — drop the stale registration.
		if not alive and not e["copies"].is_empty():
			unregister(key)
	PerformanceTrace.end(&"draw", &"outline_mask.process", perf_started, "copies", copy_count)

func _sync_cam(dst: Camera3D, cam: Camera3D) -> void:
	dst.global_transform = cam.global_transform
	dst.fov = cam.fov
	dst.projection = cam.projection
	dst.near = cam.near
	dst.far = cam.far
	dst.size = cam.size
	dst.keep_aspect = cam.keep_aspect

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
