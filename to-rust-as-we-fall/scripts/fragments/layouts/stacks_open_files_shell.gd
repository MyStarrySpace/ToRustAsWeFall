class_name StacksOpenFilesShell
extends RefCounted

## Render/physics shell for the measured Open Files layout. Mutable gameplay consequences stay on
## their mechanism owners. This builder creates only static floor, rack massing, lighting,
## and signs.


static func build(chunk: Node3D, layout: Script, archive_spire_scene: PackedScene) -> void:
	var floor_color := Color(0.038, 0.048, 0.052)
	for spec_v in layout.floor_specs():
		var spec := spec_v as Dictionary
		chunk.call("_add_floor", chunk, spec["position"], spec["size"], floor_color, "grate")
	for z_side in [-1.0, 1.0]:
		chunk.call("_add_box", chunk, Vector3(12.0, 2.2, z_side * 5.7),
			Vector3(1.0, 4.4, 0.75), Color(0.045, 0.07, 0.075),
			Color(0.22, 0.76, 0.52), 0.32)
	chunk.call("_add_box", chunk, Vector3(12.0, 4.2, 0.0), Vector3(1.0, 0.42, 12.1),
		Color(0.045, 0.07, 0.075), Color(0.22, 0.76, 0.52), 0.28)
	chunk.call("_add_label", chunk, "THE OPEN FILES INITIATIVE", Vector3(12.0, 5.05, 0.0),
		Color(0.44, 0.94, 0.62))

	for blocker_v in layout.blocker_specs():
		var blocker := blocker_v as Dictionary
		_add_archive_fin(chunk, blocker["position"], blocker["size"],
			str(blocker.get("name", "ArchiveFin")))
	for spire_v in layout.spire_specs():
		var spire := spire_v as Dictionary
		_add_archive_spire(chunk, archive_spire_scene, spire["position"],
			float(spire.get("scale", 1.0)), float(spire.get("yaw", 0.0)),
			str(spire.get("name", "ArchiveSpire")))
	for light_v in layout.light_specs():
		var light := light_v as Dictionary
		chunk.call("_add_light", chunk, light["position"], light["color"],
			float(light.get("energy", 1.0)), float(light.get("range", 12.0)))

	chunk.call("_add_label", chunk, "CATALOG INDEX 01 // TAG PLATES", Vector3(34.0, 3.1, -16.5),
		Color(0.34, 0.80, 0.96))
	chunk.call("_add_label", chunk, "SUPPORT INTAKE", Vector3(68.0, 6.8, -5.5),
		Color(0.36, 0.92, 0.62))
	chunk.call("_add_label", chunk, "CATALOG INDEX 02 // ACTIVE ARCHIVE", Vector3(100.0, 7.1, -16.5),
		Color(0.34, 0.80, 0.96))
	chunk.call("_add_label", chunk, "TRACKED ACCESS // MAINTENANCE", Vector3(94.0, 6.6, 22.2),
		Color(0.92, 0.66, 0.34))
	chunk.call("_add_label", chunk, "FAULTED CUT-OFF", Vector3(124.5, 7.0, 3.5),
		Color(0.96, 0.40, 0.20))
	chunk.call("_add_label", chunk, "SHELTER // OPEN", layout.SHELTER_POS + Vector3(0.0, 2.8, 0.0),
		Color(0.95, 0.73, 0.38))
	for z_side in [-1.0, 1.0]:
		chunk.call("_add_box", chunk, Vector3(139.0, 8.15, z_side * 3.1),
			Vector3(13.0, 0.09, 0.20), Color(0.12, 0.08, 0.04),
			Color(0.34, 0.78, 0.70), 0.45)


static func _add_archive_spire(
		chunk: Node3D,
		archive_spire_scene: PackedScene,
		world_position: Vector3,
		uniform_scale: float,
		yaw_degrees: float,
		node_name: String
	) -> void:
	var spire := archive_spire_scene.instantiate() as Node3D
	if spire == null:
		return
	spire.name = node_name
	spire.position = world_position
	spire.scale = Vector3.ONE * uniform_scale
	spire.rotation_degrees.y = yaw_degrees
	chunk.add_child(spire)


static func _add_archive_fin(
		chunk: Node3D, world_position: Vector3, size: Vector3, node_name: String
	) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = world_position
	chunk.add_child(root)
	chunk.call("_add_box", root, Vector3.ZERO, size, Color(0.025, 0.034, 0.037),
		Color(0.045, 0.10, 0.095), 0.09)
	var row_count := clampi(int(floor(size.y / 0.72)), 3, 8)
	var column_count := clampi(int(floor(size.x / 2.35)), 1, 12)
	var drawer_width := minf(2.0, size.x * 0.82 / float(column_count))
	for row in range(row_count):
		var y := -size.y * 0.5 + 0.42 \
			+ float(row) * (size.y - 0.84) / float(maxi(1, row_count - 1))
		for column in range(column_count):
			var x := -size.x * 0.41 + (float(column) + 0.5) * size.x * 0.82 \
				/ float(column_count)
			var live := (row + column + int(absf(world_position.x))) % 11 == 2
			var glow := Color(0.22, 0.84, 0.48) if live else Color(0.075, 0.15, 0.14)
			for face in [-1.0, 1.0]:
				chunk.call("_add_box", root,
					Vector3(x, y, face * (size.z * 0.5 + 0.035)),
					Vector3(drawer_width, 0.38, 0.07), Color(0.05, 0.063, 0.064),
					glow, 0.52 if live else 0.045)
	_add_static_blocker(root, size)


static func _add_static_blocker(parent: Node3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "ArchiveCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
