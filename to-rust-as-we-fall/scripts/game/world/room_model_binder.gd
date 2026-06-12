class_name RoomModelBinder
extends RefCounted

## THE system for binding a modeled room (Blockbench / Crocotile / Blender GLTF) to the game's
## data layer. A scene DECLARES its room once (descriptor below) instead of hand-rolling lookups,
## floor heights, and occupancy per sequence — that hand-rolling is exactly what drifted during
## the Aster room integration. One binder per scene; sequences keep thin delegating façades only
## for test compatibility.
##
## Descriptor keys (all but root_name optional):
##   root_name: String            — the room instance node ("AsterRoom")
##   floor_surface_y: float       — the visible floor's TOP surface (lifts grid origin / overlays)
##   grid_origin_xz: Vector2      — aligns grid cell seams with the model's floor tiles
##   occupants: Array[String]     — solid interior furniture that blocks its grid cells
##   gltf_path: String            — the source gltf (for the sidecar-wiring validation)
##   wired_materials: Array       — material names that must keep emissive wiring on re-export
##
## Conventions it encodes (the hard-won rules):
## - Duplicate siblings import as "name", "name2"... and the surface splitter renames split
##   objects to "<name>SurfaceTargets" — object lookups match all of those, nothing else.
## - Placement can be a node transform OR baked vertices (bounds away from the room origin).
## - STRUCTURAL, not visual: lookups work even when a render toggle hides the model.
## - Occupancy is DERIVED at boot (never logged); replay rebuilds it from the same scene build.
## - validate() turns the silent failure modes into loud ones — run it from tests.

var scene_root: Node
var grid: GridWorld
var config := {}

func setup(root: Node, world_grid: GridWorld, descriptor: Dictionary) -> void:
	scene_root = root
	grid = world_grid
	config = descriptor.duplicate(true)
	if grid != null:
		if config.has("floor_surface_y"):
			grid.origin.y = float(config["floor_surface_y"])
		if config.has("grid_origin_xz"):
			var xz: Vector2 = config["grid_origin_xz"]
			grid.origin.x = xz.x
			grid.origin.z = xz.y

func room_node() -> Node:
	if scene_root == null:
		return null
	return scene_root.find_child(String(config.get("root_name", "")), true, false)

## STRUCTURAL availability: the model exists in the tree (visibility toggles don't matter).
func active() -> bool:
	return room_node() != null

## All MeshInstance3Ds under the named object(s), across import duplicate suffixes and splitter
## renames. The single place the matching rules live.
func object_meshes(object_names: Array) -> Array:
	var room := room_node()
	if room == null:
		return []
	var meshes: Array = []
	for obj in room.find_children("*", "", true, false):
		if not _matches(String(obj.name), object_names):
			continue
		if obj is MeshInstance3D and not meshes.has(obj):
			meshes.append(obj)
		for m in obj.find_children("*", "MeshInstance3D", true, false):
			if not meshes.has(m):
				meshes.append(m)
	return meshes

func _matches(node_name: String, object_names: Array) -> bool:
	for raw in object_names:
		var object_name := str(raw)
		if node_name == object_name or node_name == object_name + "SurfaceTargets":
			return true
		# Godot's duplicate suffix appends digits directly ("j-store" -> "j-store2"), which is
		# ambiguous when the base name itself ENDS in a digit ("Painting 1" vs "Painting 12") —
		# in that case only exact matches count, so distinct numbered objects never merge.
		if node_name.begins_with(object_name) 				and not object_name.substr(object_name.length() - 1).is_valid_int():
			var suffix := node_name.substr(object_name.length())
			if suffix.is_valid_int():
				return true
	return false

## Combined world AABB of an object (zero-size when absent).
func object_aabb(object_name: String) -> AABB:
	return _combined_aabb(object_meshes([object_name]))

func _combined_aabb(meshes: Array) -> AABB:
	var combined := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_inside_tree():
			continue
		var ab: AABB = mi.global_transform * mi.mesh.get_aabb()
		combined = ab if first else combined.merge(ab)
		first = false
	return combined if not first else AABB()

## Placed = a real node transform (editor drag) OR baked-vertex placement (bounds away from the
## room origin; a re-centered unplaced export piles AT it).
func object_placed(object_name: String) -> bool:
	var room := room_node()
	if room == null:
		return false
	var obj := room.find_child(object_name, true, false) as Node3D
	if obj == null:
		return false
	if not obj.transform.is_equal_approx(Transform3D.IDENTITY):
		return true
	return _aabb_reads_placed(object_aabb(object_name))

func _aabb_reads_placed(ab: AABB) -> bool:
	var room := room_node() as Node3D
	var origin := room.global_position if room != null else Vector3.ZERO
	var c := ab.get_center()
	return Vector2(c.x - origin.x, c.z - origin.z).length() > 1.0

## A model PROP for an interaction/exploration object: real meshes + padded bounds, or {} when
## the model doesn't carry it (callers build their graybox fallback).
func prop(object_names: Array) -> Dictionary:
	if not active():
		return {}
	var meshes := object_meshes(object_names)
	if meshes.is_empty():
		return {}
	var combined := _combined_aabb(meshes)
	if combined.size == Vector3.ZERO or not _aabb_reads_placed(combined):
		return {}
	return {
		"meshes": meshes,
		"center": combined.get_center(),
		"size": combined.size + Vector3(0.35, 0.35, 0.35),
	}

## Anchor resolution: the AUTHORED MARKER wins (camera framing and beat timing are tuned to it);
## a placed model object is the fallback for marker-less anchors.
func anchor(object_name: String, marker: Node3D, fallback_position: Vector3) -> Vector3:
	if marker != null:
		return marker.global_position
	if active() and object_placed(object_name):
		var ab := object_aabb(object_name)
		if ab.size != Vector3.ZERO:
			var c := ab.get_center()
			return Vector3(c.x, ab.position.y, c.z)
	return fallback_position

## DATA-LAYER occupancy: each declared occupant blocks its (slightly inset) grid cells so
## characters path around the furniture. Derived at boot, never logged.
func apply_occupancy() -> void:
	if grid == null or not active():
		return
	for raw in config.get("occupants", []):
		var obj_name := str(raw)
		var ab := object_aabb(obj_name)
		if ab.size == Vector3.ZERO:
			continue
		var a := grid.world_to_grid(ab.position + Vector3(0.2, 0, 0.2))
		var b := grid.world_to_grid(ab.position + ab.size - Vector3(0.2, 0, 0.2))
		for cz in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for cx in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				if grid.is_in_bounds(cx, cz) and grid.is_walkable(cx, cz):
					grid.add_dynamic_blocker(Vector2i(cx, cz), "model_" + obj_name)

## Every silent failure mode from the integration, as loud strings. Empty = healthy.
## Run from the scene's test: _assert_true(binder.validate().is_empty(), ...).
func validate() -> Array[String]:
	var problems: Array[String] = []
	var room := room_node()
	if room == null:
		problems.append("room root '%s' not found in the scene" % str(config.get("root_name", "")))
		return problems
	# The tilted-root bug: ANY ancestor rotation/scale skews every global Y by z*sin(tilt).
	var walker: Node = room
	while walker != null and walker is Node3D:
		var basis := (walker as Node3D).transform.basis
		if not basis.is_equal_approx(Basis.IDENTITY):
			problems.append("'%s' carries a non-identity basis (editor-drag tilt?) — characters will float by z*tilt" % walker.name)
		walker = walker.get_parent()
	# Declared occupants/props must exist (catches renames in a re-export).
	for raw in config.get("occupants", []):
		if object_meshes([str(raw)]).is_empty():
			problems.append("declared occupant '%s' has no meshes in the model" % str(raw))
	# The sidecar-wiring guard: a DCC re-export silently drops emissive/normal references.
	var gltf_path := String(config.get("gltf_path", ""))
	if gltf_path != "" and FileAccess.file_exists(gltf_path):
		var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(gltf_path))
		var mats := {}
		for mat in parsed.get("materials", []):
			mats[str(mat.get("name", ""))] = mat
		for raw in config.get("wired_materials", []):
			var mat_name := str(raw)
			var mat: Dictionary = mats.get(mat_name, {})
			if mat.is_empty():
				problems.append("wired material '%s' missing from %s" % [mat_name, gltf_path])
			elif not mat.has("emissiveTexture"):
				problems.append("material '%s' lost its emissive sidecar wiring — re-run tools/gltf_wire_material_sidecars.py" % mat_name)
	if grid != null and config.has("floor_surface_y") \
			and absf(grid.origin.y - float(config["floor_surface_y"])) > 0.001:
		problems.append("grid origin y (%.3f) does not match the declared floor surface (%.3f)" % [grid.origin.y, float(config["floor_surface_y"])])
	return problems
