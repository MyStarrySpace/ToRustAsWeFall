class_name PortalFixtures
extends RefCounted

## THE portal look, applied to any PortalPad pair (docs/PORTALS.md): each pad gets an
## upright ARCH over its ring whose aperture is a live PortalLens showing the paired end.
## Fixtures are CHILDREN of the pads, so they ride a warped scene's coord-map pass with
## the pad — author flat, dress once, warp free. Colors follow the pad's own glow_color
## (the portal color law lives at the pad's configure call: purple transit / blue route).
## Call AFTER both pads are in the tree.

const APERTURE_R := 0.62
const ARCH_LIFT := 1.15

## Dress a whole pad set: MUTUAL pairs (a.dest ~ b.pos and b.dest ~ a.pos) get arch +
## live lens both ends; chained/one-way pads get the arch alone (a functional aperture
## with no partner to show). The one entry point loaders call after spawning.
static func dress_matching(pads: Array, aperture_r := APERTURE_R, lift := ARCH_LIFT) -> void:
	var dressed := {}
	for i in range(pads.size()):
		if dressed.has(i):
			continue
		var a: Node3D = pads[i]
		if a == null or not is_instance_valid(a):
			continue
		for j in range(i + 1, pads.size()):
			if dressed.has(j):
				continue
			var b: Node3D = pads[j]
			if b == null or not is_instance_valid(b):
				continue
			var a_dest: Variant = a.get("_dest")
			var b_dest: Variant = b.get("_dest")
			if a_dest is Vector3 and b_dest is Vector3 \
					and (a_dest as Vector3).distance_to(b.position) < 1.2 \
					and (b_dest as Vector3).distance_to(a.position) < 1.2:
				dress_pair(a, b, aperture_r, lift)
				dressed[i] = true
				dressed[j] = true
				break
	for i in range(pads.size()):
		if not dressed.has(i) and pads[i] != null and is_instance_valid(pads[i]) \
				and (pads[i] as Node3D).is_inside_tree():
			var toward: Variant = (pads[i] as Node).get("_dest")
			var target := Node3D.new()
			target.position = toward if toward is Vector3 else (pads[i] as Node3D).position + Vector3.FORWARD
			_dress_one(pads[i], target, aperture_r, lift)
			target.free()   # a math-only facing reference, never in the tree

static func dress_pair(pad_a: Node3D, pad_b: Node3D,
		aperture_r := APERTURE_R, lift := ARCH_LIFT) -> void:
	if pad_a == null or pad_b == null or not pad_a.is_inside_tree() or not pad_b.is_inside_tree():
		return
	var ap_a := _dress_one(pad_a, pad_b, aperture_r, lift)
	var ap_b := _dress_one(pad_b, pad_a, aperture_r, lift)
	_add_lens(ap_a, ap_b, aperture_r)
	_add_lens(ap_b, ap_a, aperture_r)

static func _dress_one(pad: Node3D, partner: Node3D, r: float, lift: float) -> Node3D:
	var color: Color = pad.get("glow_color") if pad.get("glow_color") != null else Color(0.55, 0.42, 0.98)
	var ap := Node3D.new()
	ap.name = "PortalAperture"
	# The aperture faces the partner in the AUTHORED frame; as a child it inherits the
	# pad's warp, so the facing stays sensible on a coord-mapped deck.
	var dir: Vector3 = partner.position - pad.position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	ap.position = Vector3(0.0, lift, 0.0)
	ap.basis = Basis(Vector3.UP.cross(dir), Vector3.UP, dir)
	pad.add_child(ap)
	var arch := MeshInstance3D.new()
	arch.name = "PortalArch"
	var ring := TorusMesh.new()
	ring.inner_radius = r
	ring.outer_radius = r + 0.14
	arch.mesh = ring
	arch.rotation = Vector3(PI * 0.5, 0.0, 0.0)   # torus axis -> the look axis
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.35)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	arch.material_override = m
	ap.add_child(arch)
	return ap

static func _add_lens(src_ap: Node3D, dest_ap: Node3D, r: float) -> void:
	var lens := PortalLens.new()
	lens.name = "ApertureLens"
	src_ap.add_child(lens)
	lens.setup_tracking(dest_ap, r, src_ap.get_world_3d())
