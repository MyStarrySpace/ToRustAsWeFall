class_name ChromaProbe
extends Node3D

## CHROMA PROBE — the game's TESTING-MODE color channel (the red-shell idea, generalized).
##
## Renders a PROXY for every registered semantic entity (interactables, characters, markers) into a
## mirrored SubViewport as a FLAT UNIQUE ID COLOR, with the camera synced to the live one. Reading
## that viewport back gives a machine-readable map of the player's actual screen: which pixels belong
## to which entity, whether it is visible at all, and where its clickable centroid sits — without
## touching the real render. Tests then drive REAL input at those pixels (mouse motion, right-clicks)
## and assert the player-visible contract, instead of force-firing data-layer triggers.
##
## IDs use broad color bins rather than raw byte values. Values such as index 1 -> G=1/255 are
## quantized to zero by real GL framebuffers, which previously made every target after index 0
## decode as the first target. Three kind bins and two base-8 index digits keep every channel well
## away from black and at least 28 byte-values apart (64 targets per kind, far above current use).
##
## Purely a dev/test surface: proxies read transforms every frame and write nothing back. The dev
## console's `chroma on` overlays the same proxies semi-transparently in the MAIN view for humans.

const KIND_INTERACTABLE := 0
const KIND_CHARACTER := 1
const KIND_MARKER := 2
const ID_KIND_BASE := 64
const ID_KIND_STEP := 80
const ID_KIND_COUNT := 3
const ID_DIGIT_BASE := 32
const ID_DIGIT_STEP := 28
const ID_DIGIT_RADIX := 8
const ID_MAX_INDEX := ID_DIGIT_RADIX * ID_DIGIT_RADIX - 1

var _sub: SubViewport
var _cam: Camera3D
var _entries := {}          # id_color(int rgb24) -> {node, kind, index, proxy: MeshInstance3D, overlay: MeshInstance3D}
var _built := false
var _overlay_visible := false

func _ready() -> void:
	_ensure_built()

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_sub = SubViewport.new()
	_sub.name = "ChromaViewport"
	_sub.own_world_3d = true
	_sub.transparent_bg = true
	_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sub.handle_input_locally = false
	_sub.msaa_3d = Viewport.MSAA_DISABLED          # an ID color must decode exactly
	_sub.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_sub.size = _viewport_size()
	add_child(_sub)
	_cam = Camera3D.new()
	_cam.name = "ChromaCamera"
	_sub.add_child(_cam)
	_cam.current = true

func _viewport_size() -> Vector2i:
	var vp := get_viewport()
	if vp == null:
		return Vector2i(1152, 648)
	var s := vp.get_visible_rect().size
	return Vector2i(maxi(8, int(s.x)), maxi(8, int(s.y)))

static func encode(kind: int, index: int) -> Color:
	if not supports_id(kind, index):
		push_error("ChromaProbe.encode: unsupported id kind=%d index=%d (kind 0..%d, index 0..%d)" % [
			kind, index, ID_KIND_COUNT - 1, ID_MAX_INDEX])
		return Color.TRANSPARENT
	return Color8(
		ID_KIND_BASE + kind * ID_KIND_STEP,
		ID_DIGIT_BASE + (index % ID_DIGIT_RADIX) * ID_DIGIT_STEP,
		ID_DIGIT_BASE + int(index / ID_DIGIT_RADIX) * ID_DIGIT_STEP
	)

static func supports_id(kind: int, index: int) -> bool:
	return kind >= 0 and kind < ID_KIND_COUNT and index >= 0 and index <= ID_MAX_INDEX

static func _decode_bin(byte_value: int, base: int, step: int, count: int) -> int:
	var value := clampi(int(round(float(byte_value - base) / float(step))), 0, count - 1)
	# Broad tolerance admits renderer color conversion but rejects transparent/background noise.
	return value if absi(byte_value - (base + value * step)) <= int(ceil(step * 0.6)) else -1

## Decode one mask pixel -> {kind, index} or empty (background / unreadable).
static func decode(c: Color) -> Dictionary:
	if c.a < 0.5:
		return {}
	var r := int(round(c.r * 255.0))
	var g := int(round(c.g * 255.0))
	var b := int(round(c.b * 255.0))
	var kind := _decode_bin(r, ID_KIND_BASE, ID_KIND_STEP, ID_KIND_COUNT)
	var low := _decode_bin(g, ID_DIGIT_BASE, ID_DIGIT_STEP, ID_DIGIT_RADIX)
	var high := _decode_bin(b, ID_DIGIT_BASE, ID_DIGIT_STEP, ID_DIGIT_RADIX)
	if kind < 0 or low < 0 or high < 0:
		return {}
	return {"kind": kind, "index": low + high * ID_DIGIT_RADIX}

## Register an entity. `radius`/`height` size the proxy; an Interactable's interaction zone and a
## character's body are the natural fits. Re-registering an index replaces its proxy.
func register(node: Node3D, kind: int, index: int, radius := 0.7, height := 1.2) -> void:
	_ensure_built()
	if not supports_id(kind, index):
		push_error("ChromaProbe.register: unsupported id kind=%d index=%d (kind 0..%d, index 0..%d)" % [
			kind, index, ID_KIND_COUNT - 1, ID_MAX_INDEX])
		return
	var key := _key(kind, index)
	if _entries.has(key):
		unregister(kind, index)
	var color := encode(kind, index)
	var proxy := _make_proxy(color, radius, height, false)
	_sub.add_child(proxy)
	var overlay := _make_proxy(color, radius, height, true)
	overlay.visible = _overlay_visible
	add_child(overlay)
	_entries[key] = {"node": node, "kind": kind, "index": index, "proxy": proxy, "overlay": overlay}
	_refresh_active()

func unregister(kind: int, index: int) -> void:
	var key := _key(kind, index)
	var e = _entries.get(key)
	if e == null:
		return
	for slot in ["proxy", "overlay"]:
		var mi = e[slot]
		if mi is Node and is_instance_valid(mi):
			(mi as Node).queue_free()
	_entries.erase(key)
	_refresh_active()

func clear() -> void:
	for key in _entries.keys().duplicate():
		var e: Dictionary = _entries[key]
		unregister(int(e["kind"]), int(e["index"]))

func _key(kind: int, index: int) -> int:
	return kind * 65536 + index

func _make_proxy(color: Color, radius: float, height: float, translucent: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = maxf(0.1, radius)
	cap.height = maxf(cap.radius * 2.0, height)
	mi.mesh = cap
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.35 if translucent else 1.0)
	if translucent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Show/hide the human-facing overlay proxies in the MAIN view (`chroma on` in the dev console).
func set_overlay_visible(active: bool) -> void:
	_overlay_visible = active
	for e in _entries.values():
		var ov = e["overlay"]
		if ov is Node3D and is_instance_valid(ov):
			(ov as Node3D).visible = active

func _process(_delta: float) -> void:
	if not _built:
		return
	var vp := get_viewport()
	var live: Camera3D = vp.get_camera_3d() if vp != null else null
	if live != null:
		var want := _viewport_size()
		if _sub.size != want:
			_sub.size = want
		_cam.global_transform = live.global_transform
		_cam.fov = live.fov
		_cam.projection = live.projection
		_cam.near = live.near
		_cam.far = live.far
		_cam.keep_aspect = live.keep_aspect
		_cam.size = live.size
	for key in _entries.keys():
		var e: Dictionary = _entries[key]
		var src = e["node"]
		if not (src is Node3D and is_instance_valid(src)):
			unregister(int(e["kind"]), int(e["index"]))
			continue
		var pos := (src as Node3D).global_position
		var proxy := e["proxy"] as MeshInstance3D
		var overlay := e["overlay"] as MeshInstance3D
		var lift := Vector3(0, (proxy.mesh as CapsuleMesh).height * 0.5, 0)
		if is_instance_valid(proxy):
			proxy.global_position = pos + lift
		if is_instance_valid(overlay):
			overlay.global_position = pos + lift

func _refresh_active() -> void:
	if _sub != null:
		_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS if not _entries.is_empty() else SubViewport.UPDATE_DISABLED

## Read the chroma mask and locate every visible entity. Await RenderingServer.frame_post_draw
## before calling. Returns {"<kind>:<index>": {kind, index, pixels, centroid: Vector2, node}}.
func snapshot() -> Dictionary:
	if _sub == null:
		return {}
	var img := _sub.get_texture().get_image()
	var found := {}
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var d := decode(img.get_pixel(x, y))
			if d.is_empty():
				continue
			var k := "%d:%d" % [int(d["kind"]), int(d["index"])]
			if not found.has(k):
				var e = _entries.get(_key(int(d["kind"]), int(d["index"])))
				found[k] = {"kind": int(d["kind"]), "index": int(d["index"]), "pixels": 0,
					"sum": Vector2.ZERO, "node": (e["node"] if e != null else null)}
			var rec: Dictionary = found[k]
			rec["pixels"] = int(rec["pixels"]) + 1
			rec["sum"] = (rec["sum"] as Vector2) + Vector2(float(x), float(y))
	for k2 in found.keys():
		var rec2: Dictionary = found[k2]
		rec2["centroid"] = (rec2["sum"] as Vector2) / maxf(1.0, float(rec2["pixels"]))
		rec2.erase("sum")
	return found

## Find (or create) the scene's probe — the OutlineMaskManager discovery pattern.
static func ensure(context: Node) -> ChromaProbe:
	if context == null:
		return null
	var node := context
	while node != null:
		for child in node.get_children():
			if child is ChromaProbe:
				return child as ChromaProbe
		node = node.get_parent()
	var anchor: Node = context.owner if context.owner != null else context
	var probe := ChromaProbe.new()
	probe.name = "ChromaProbe"
	anchor.add_child(probe)
	return probe
