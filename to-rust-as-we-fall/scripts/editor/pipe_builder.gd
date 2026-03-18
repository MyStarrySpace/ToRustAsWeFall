class_name PipeBuilder

## Generates 64 pipe mesh variants (one per 6-directional connection mask)
## and registers them in a MeshLibrary. Pipes auto-connect to neighbors.

const PIPE_ID_OFFSET := 100  # Item IDs 100-163 in the MeshLibrary
const PIPE_RADIUS := 0.18
const JOINT_RADIUS := 0.22

# Direction bit flags
const DIR_PX := 1   # +X
const DIR_NX := 2   # -X
const DIR_PZ := 4   # +Z
const DIR_NZ := 8   # -Z
const DIR_PY := 16  # +Y
const DIR_NY := 32  # -Y

static var DIR_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0),   # bit 0: +X
	Vector3i(-1, 0, 0),  # bit 1: -X
	Vector3i(0, 0, 1),   # bit 2: +Z
	Vector3i(0, 0, -1),  # bit 3: -Z
	Vector3i(0, 1, 0),   # bit 4: +Y
	Vector3i(0, -1, 0),  # bit 5: -Y
]

static var pipe_meshes: Array[Mesh] = []

static func is_pipe(item_id: int) -> bool:
	return item_id >= PIPE_ID_OFFSET and item_id < PIPE_ID_OFFSET + 64

static func build(library: MeshLibrary) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.35, 0.32)
	material.roughness = 0.4
	material.metallic = 0.3

	# Source primitives
	var joint := SphereMesh.new()
	joint.radius = JOINT_RADIUS
	joint.height = JOINT_RADIUS * 2.0
	joint.radial_segments = 10
	joint.rings = 6

	var stub := CylinderMesh.new()
	stub.top_radius = PIPE_RADIUS
	stub.bottom_radius = PIPE_RADIUS
	stub.height = 0.5
	stub.radial_segments = 10

	var full_cyl := CylinderMesh.new()
	full_cyl.top_radius = PIPE_RADIUS
	full_cyl.bottom_radius = PIPE_RADIUS
	full_cyl.height = 1.0
	full_cyl.radial_segments = 10

	# Transforms to orient a Y-aligned cylinder toward each direction
	var stub_xforms: Array[Transform3D] = [
		Transform3D(Basis(Vector3(0, 0, 1), -PI / 2.0), Vector3(0.25, 0, 0)),   # +X
		Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(-0.25, 0, 0)),    # -X
		Transform3D(Basis(Vector3(1, 0, 0), PI / 2.0), Vector3(0, 0, 0.25)),     # +Z
		Transform3D(Basis(Vector3(1, 0, 0), -PI / 2.0), Vector3(0, 0, -0.25)),   # -Z
		Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)),                          # +Y
		Transform3D(Basis.IDENTITY, Vector3(0, -0.25, 0)),                         # -Y
	]

	# Full-length cylinder transforms for pure straight pipes (no sphere joint)
	var straight_xforms := {
		3: Transform3D(Basis(Vector3(0, 0, 1), -PI / 2.0), Vector3.ZERO),  # along X
		12: Transform3D(Basis(Vector3(1, 0, 0), PI / 2.0), Vector3.ZERO),  # along Z
		48: Transform3D.IDENTITY,                                            # along Y
	}

	var collision := BoxShape3D.new()
	collision.size = Vector3(1, 1, 1)

	pipe_meshes.resize(64)

	for mask in range(64):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		if mask in straight_xforms:
			# Pure straight — single full-length cylinder, cleaner look
			st.append_from(full_cyl, 0, straight_xforms[mask])
		else:
			# Junction node — sphere + stubs toward each connected neighbor
			st.append_from(joint, 0, Transform3D.IDENTITY)
			for bit in range(6):
				if mask & (1 << bit):
					st.append_from(stub, 0, stub_xforms[bit])

		st.set_material(material)
		var mesh := st.commit()
		pipe_meshes[mask] = mesh

		var item_id := PIPE_ID_OFFSET + mask
		library.create_item(item_id)
		library.set_item_mesh(item_id, mesh)
		library.set_item_name(item_id, "pipe_%d" % mask)
		library.set_item_shapes(item_id, [collision, Transform3D.IDENTITY])
