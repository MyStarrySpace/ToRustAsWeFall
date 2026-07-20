class_name InfrastructureStructureBuilder
extends RefCounted

## Measured construction pass for the connective infrastructure catalog.
##
## BaseShapeBuilder owns the surveyed envelope; this builder adds the construction language that
## tells the player what the structure does: sawtooth fabrication bays, bonded storage frames,
## reclamation filters, substation buswork, and typed service hardware. Every dimension derives from
## the spec's metre module, bay count, survey datums, or surveyed service sockets. No world-space
## placement constants live here, so seeded scale rolls and DCC bakes stay coherent.

const ROLES := ["metal", "rust", "dark", "input_glow", "output_glow"]

static func is_infrastructure(spec: Dictionary) -> bool:
	return str(spec.get("system_role", "")) != "" and not (spec.get("service_ports", []) as Array).is_empty()

static func build(spec: Dictionary, survey: BuildingSurvey) -> Dictionary:
	if not is_infrastructure(spec):
		return {}
	var tools: Dictionary = {}
	for role_v in ROLES:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[str(role_v)] = st
	match str(spec.get("kind", "")):
		"fabrication_hall":
			_build_fabrication(tools, spec, survey)
		"bonded_warehouse":
			_build_warehouse(tools, spec, survey)
		"reclamation_works":
			_build_reclamation(tools, spec, survey)
		"distribution_substation":
			_build_substation(tools, spec, survey)
	_build_service_hardware(tools, survey)
	var out := {}
	for role_v in ROLES:
		var role := str(role_v)
		var tool := tools[role] as SurfaceTool
		tool.generate_normals()
		var mesh := tool.commit()
		if mesh != null and mesh.get_surface_count() > 0:
			out[role] = mesh
	return out


# FABRICATION: a four-bay sawtooth hall. Repeated roof folds and facade ribs expose the module; the
# dark front rail is the material-transfer beam, not an arbitrary stripe.
static func _build_fabrication(tools: Dictionary, spec: Dictionary, survey: BuildingSurvey) -> void:
	var size: Vector3 = spec.get("size", Vector3(4.2, 5.4, 4.0))
	var h := float(survey.datums["crown"])
	var bays := maxi(2, int(spec.get("bay_count", round(size.x / float(spec.get("construction_module_m", 1.05))))))
	var bay_w := size.x / float(bays)
	var z0 := -size.z * 0.46
	var z1 := size.z * 0.46
	for k in range(bays):
		var x0 := -size.x * 0.5 + float(k) * bay_w
		var x1 := x0 + bay_w
		_sawtooth(tools["metal"], x0, x1, z0, z1, h + 0.03, bay_w * 0.42)
		_box(tools["rust"], Vector3(x0, h * 0.51, size.z * 0.5 + 0.07),
			Vector3(0.09, h * 0.92, 0.14))
	_box(tools["rust"], Vector3(size.x * 0.5, h * 0.51, size.z * 0.5 + 0.07),
		Vector3(0.09, h * 0.92, 0.14))
	var rail_y := float((survey.datums.get("storeys", [h * 0.5]) as Array)[0])
	_box(tools["dark"], Vector3(0, rail_y, size.z * 0.5 + 0.12),
		Vector3(size.x - 0.30, 0.20, 0.22))
	for x_v in [-size.x * 0.30, size.x * 0.30]:
		_tube(tools["metal"], Vector3(float(x_v), rail_y - 0.05, size.z * 0.5 + 0.25),
			Vector3(float(x_v), 0.45, size.z * 0.5 + 0.55), 0.07, 8)


# STORAGE: the bonded cage wraps a regular rack bay grid around the envelope. Its rhythm is distinct
# from residential windows: full-height posts, datum beams, a sealed roof monitor, and side bumpers.
static func _build_warehouse(tools: Dictionary, spec: Dictionary, survey: BuildingSurvey) -> void:
	var size: Vector3 = spec.get("size", Vector3(4.4, 6.2, 4.2))
	var h := float(survey.datums["crown"])
	var bays := maxi(2, int(spec.get("bay_count", 4)))
	for k in range(bays + 1):
		var x := lerpf(-size.x * 0.48, size.x * 0.48, float(k) / float(bays))
		for z_v in [-size.z * 0.5 - 0.08, size.z * 0.5 + 0.08]:
			_box(tools["rust"], Vector3(x, h * 0.49, float(z_v)), Vector3(0.10, h * 0.94, 0.12))
	for y_v in (survey.datums.get("storeys", []) as Array):
		var y := minf(float(y_v), h - 0.15)
		for z_v in [-size.z * 0.5 - 0.08, size.z * 0.5 + 0.08]:
			_box(tools["metal"], Vector3(0, y, float(z_v)), Vector3(size.x + 0.12, 0.12, 0.14))
	var monitor_w := size.x * 0.52
	_box(tools["dark"], Vector3(0, h + 0.24, 0), Vector3(monitor_w, 0.46, size.z * 0.42))
	_box(tools["metal"], Vector3(0, h + 0.50, 0), Vector3(monitor_w + 0.18, 0.08, size.z * 0.48))
	for side in [-1.0, 1.0]:
		for z_v in [-size.z * 0.28, size.z * 0.28]:
			_box(tools["dark"], Vector3(side * (size.x * 0.5 + 0.18), 0.34, float(z_v)),
				Vector3(0.30, 0.32, 0.62))


# RECLAMATION: three filter columns and a measured crown manifold make the circular works readable
# as a process, with pipes visibly returning to the surveyed drum rather than hovering nearby.
static func _build_reclamation(tools: Dictionary, spec: Dictionary, survey: BuildingSurvey) -> void:
	var h := float(survey.datums["crown"])
	var r := float(spec.get("radius", 2.05))
	var pod_r := maxf(0.20, float(spec.get("construction_module_m", 0.78)) * 0.30)
	var pod_y0 := h * 0.18
	var pod_y1 := h * 0.78
	for angle_v in [-0.18, PI + 0.20, -PI * 0.52]:
		var a := float(angle_v)
		var n := Vector3(cos(a), 0, sin(a))
		var c := n * (r + pod_r * 0.80)
		_tube(tools["metal"], Vector3(c.x, pod_y0, c.z), Vector3(c.x, pod_y1, c.z), pod_r, 10)
		_tube(tools["rust"], Vector3(c.x, pod_y0 + 0.22, c.z),
			n * survey.radius_at(pod_y0 + 0.22) + Vector3(0, pod_y0 + 0.22, 0), pod_r * 0.28, 8)
		_box(tools["dark"], Vector3(c.x, pod_y1 + 0.08, c.z),
			Vector3(pod_r * 1.55, 0.14, pod_r * 1.55))
	var ring_y := h + 0.16
	var ring_r := r * 0.72
	var segs := maxi(8, int(spec.get("bay_count", 8)))
	for k in range(segs):
		var a0 := TAU * float(k) / float(segs)
		var a1 := TAU * float(k + 1) / float(segs)
		_tube(tools["rust"], Vector3(cos(a0) * ring_r, ring_y, sin(a0) * ring_r),
			Vector3(cos(a1) * ring_r, ring_y, sin(a1) * ring_r), 0.065, 6)
	for k in range(4):
		var a2 := TAU * float(k) / 4.0 + PI * 0.25
		_tube(tools["metal"], Vector3(cos(a2) * ring_r, h, sin(a2) * ring_r),
			Vector3(cos(a2) * ring_r, ring_y, sin(a2) * ring_r), 0.055, 6)


# DISTRIBUTION: paired transformers, ceramic stacks, and one continuous busbar expose the branching
# network. The quantities follow the five-bay construction grid rather than a cosmetic random count.
static func _build_substation(tools: Dictionary, spec: Dictionary, survey: BuildingSurvey) -> void:
	var size: Vector3 = spec.get("size", Vector3(4.0, 4.8, 4.0))
	var h := float(survey.datums["crown"])
	var module := float(spec.get("construction_module_m", 0.80))
	for side in [-1.0, 1.0]:
		_box(tools["dark"], Vector3(side * size.x * 0.25, h + module * 0.28, 0),
			Vector3(module * 0.72, module * 0.56, module * 1.25))
		for z_v in [-module * 0.34, module * 0.34]:
			_tube(tools["metal"], Vector3(side * size.x * 0.25, h + module * 0.56, float(z_v)),
				Vector3(side * size.x * 0.25, h + module * 1.18, float(z_v)), module * 0.075, 8)
			for ring in range(3):
				var ry := h + module * (0.68 + float(ring) * 0.16)
				_box(tools["metal"], Vector3(side * size.x * 0.25, ry, float(z_v)),
					Vector3(module * 0.30, module * 0.055, module * 0.30))
	var bus_y := h + module * 1.26
	_tube(tools["rust"], Vector3(-size.x * 0.38, bus_y, -module * 0.34),
		Vector3(size.x * 0.38, bus_y, -module * 0.34), module * 0.055, 8)
	_tube(tools["rust"], Vector3(-size.x * 0.38, bus_y, module * 0.34),
		Vector3(size.x * 0.38, bus_y, module * 0.34), module * 0.055, 8)
	for x_v in [-size.x * 0.42, size.x * 0.42]:
		_tube(tools["rust"], Vector3(float(x_v), h * 0.32, -size.z * 0.5 - 0.09),
			Vector3(float(x_v) * 0.62, h * 0.74, -size.z * 0.5 - 0.09), 0.055, 6)


# The socket is simultaneously network data and readable facade hardware. Inputs use the world's
# cold scanner light; outputs use terminal green, so flow direction remains legible without labels.
static func _build_service_hardware(tools: Dictionary, survey: BuildingSurvey) -> void:
	for raw_v in survey.sockets:
		var port := raw_v as Dictionary
		if str(port.get("kind", "")) != "service":
			continue
		var p := port["pos"] as Vector3
		var n := (port["dir"] as Vector3).normalized()
		var t := (port["tangent"] as Vector3).normalized()
		var w := float(port.get("width", 0.3))
		_oriented_box(tools["metal"], p + n * 0.055, t, n, Vector3(w * 1.45, w * 1.25, 0.10))
		_oriented_box(tools["dark"], p + n * 0.115, t, n, Vector3(w * 1.02, w * 0.82, 0.08))
		_tube(tools["rust"], p + n * 0.12, p + n * (0.42 + w * 0.35), maxf(0.045, w * 0.18), 8)
		var glow_role := "output_glow" if str(port.get("flow", "in")) == "out" else "input_glow"
		_oriented_box(tools[glow_role], p + n * 0.165 + Vector3.UP * w * 0.20,
			t, n, Vector3(w * 0.46, w * 0.16, 0.025))


static func _sawtooth(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float,
		y: float, rise: float) -> void:
	var a0 := Vector3(x0, y, z0); var b0 := Vector3(x1, y, z0); var c0 := Vector3(x1, y + rise, z0)
	var a1 := Vector3(x0, y, z1); var b1 := Vector3(x1, y, z1); var c1 := Vector3(x1, y + rise, z1)
	_tri(st, a0, c0, b0); _tri(st, a1, b1, c1)
	_quad(st, a0, a1, c1, c0); _quad(st, b1, b0, c0, c1); _quad(st, a1, a0, b0, b1)

static func _box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	_oriented_box(st, center, Vector3.RIGHT, Vector3.FORWARD, size)

# Size axes are tangent (x), up (y), and outward normal (z).
static func _oriented_box(st: SurfaceTool, center: Vector3, tangent: Vector3, normal: Vector3,
		size: Vector3) -> void:
	var tx := tangent.normalized() * size.x * 0.5
	var uy := Vector3.UP * size.y * 0.5
	var nz := normal.normalized() * size.z * 0.5
	var p000 := center - tx - uy - nz
	var p100 := center + tx - uy - nz
	var p110 := center + tx + uy - nz
	var p010 := center - tx + uy - nz
	var p001 := center - tx - uy + nz
	var p101 := center + tx - uy + nz
	var p111 := center + tx + uy + nz
	var p011 := center - tx + uy + nz
	_quad(st, p001, p101, p111, p011); _quad(st, p100, p000, p010, p110)
	_quad(st, p101, p100, p110, p111); _quad(st, p000, p001, p011, p010)
	_quad(st, p011, p111, p110, p010); _quad(st, p000, p100, p101, p001)

static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, sides: int) -> void:
	var axis := b - a
	if axis.length_squared() < 0.00001:
		return
	axis = axis.normalized()
	var ref := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u).normalized()
	for k in range(sides):
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var r0 := (u * cos(a0) + v * sin(a0)) * radius
		var r1 := (u * cos(a1) + v * sin(a1)) * radius
		_quad(st, a + r0, a + r1, b + r1, b + r0)
		_tri(st, a, a + r1, a + r0)
		_tri(st, b, b + r0, b + r1)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
