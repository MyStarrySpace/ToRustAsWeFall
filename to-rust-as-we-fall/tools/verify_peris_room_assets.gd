extends SceneTree

## Asset/layout contract for Peris's room. In addition to checking portable models,
## this catches the failure mode where marker centers snap to the grid but the real
## imported furniture volumes still clip after their DCC pivots are applied.

const ROOM_SCENE := "res://scenes/tutorial/peris_sim.tscn"
const PORTABLE_SCENES := [
	"res://scenes/props/peris/watering_can.tscn",
	"res://scenes/props/peris/wellness_terminal.tscn",
	"res://scenes/props/peris/strike_notice.tscn",
	"res://scenes/props/peris/logbook_console.tscn",
	"res://scenes/props/peris/care_field_kit.tscn",
	"res://scenes/props/peris/monos_portal_room_visual.tscn",
]
const MIN_FURNITURE_CLEARANCE := 0.08

var failures := 0


func _init() -> void:
	var packed := load(ROOM_SCENE) as PackedScene
	_check(packed != null, "Peris room scene loads")
	if packed == null:
		quit(1)
		return
	var room := packed.instantiate()
	get_root().add_child(room)
	for frame in range(8):
		await process_frame
	_check(str(room.get_meta("asset_contract", "")) == "editable_3d_v1",
		"Peris room declares the editable asset contract")
	_check(str(room.get_meta("layout_contract", "")) == "peris_ordered_grid_v1",
		"Peris room declares its ordered grid layout")
	var problems: Array = room.call("get_room_layout_problems")
	_check(problems.is_empty(), "Peris marker layout validates clean: %s" % problems)
	_check_furniture_clearance(room)
	_check_floor_plant_clearance(room)
	var couch_anchor := room.find_child("CouchAnchor", true, false) as Node3D
	_check(couch_anchor != null and absf(couch_anchor.rotation.y) <= 0.001,
		"The couch is oriented west toward the portal")
	for scene_path in PORTABLE_SCENES:
		_check_portable_scene(scene_path)
	room.queue_free()
	await process_frame
	print("[PERIS ASSETS] %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)


func _check_furniture_clearance(room: Node) -> void:
	var names: Array = room.ROOM_OCCUPANTS
	var binder = room._room_binder
	for i in range(names.size()):
		var a_name := str(names[i])
		var a: AABB = binder.object_aabb(a_name)
		print("[PERIS AABB] %s center=%s size=%s" % [a_name, a.get_center(), a.size])
		for j in range(i + 1, names.size()):
			var b_name := str(names[j])
			var b: AABB = binder.object_aabb(b_name)
			var overlap_x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
			var overlap_z := minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z)
			_check(overlap_x <= -MIN_FURNITURE_CLEARANCE or overlap_z <= -MIN_FURNITURE_CLEARANCE,
				"%s and %s keep %.2fm clearance in X or Z (overlap %.2f, %.2f)" % [
					a_name, b_name, MIN_FURNITURE_CLEARANCE, overlap_x, overlap_z])


func _check_floor_plant_clearance(room: Node) -> void:
	var binder = room._room_binder
	for plant_name in ["Plant7", "Plant9"]:
		var plant_node := room.find_child(plant_name, true, false) as Node3D
		var plant := _node_aabb(plant_node)
		print("[PERIS AABB] %s center=%s size=%s" % [plant_name, plant.get_center(), plant.size])
		for raw_name in room.ROOM_OCCUPANTS:
			var furniture_name := str(raw_name)
			var furniture: AABB = binder.object_aabb(furniture_name)
			var overlap_x := minf(plant.end.x, furniture.end.x) - maxf(plant.position.x, furniture.position.x)
			var overlap_z := minf(plant.end.z, furniture.end.z) - maxf(plant.position.z, furniture.position.z)
			_check(overlap_x <= 0.0 or overlap_z <= 0.0,
				"floor-standing %s does not clip %s (overlap %.2f, %.2f)" % [
					plant_name, furniture_name, overlap_x, overlap_z])


func _node_aabb(root: Node3D) -> AABB:
	if root == null:
		return AABB()
	var result := AABB()
	var first := true
	var candidates: Array[Node] = [root]
	candidates.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for candidate in candidates:
		var mesh_node := candidate as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null or not mesh_node.is_inside_tree():
			continue
		var bounds := mesh_node.global_transform * mesh_node.mesh.get_aabb()
		result = bounds if first else result.merge(bounds)
		first = false
	return result


func _check_portable_scene(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	_check(packed != null, "%s loads" % scene_path)
	if packed == null:
		return
	var instance := packed.instantiate()
	var mesh_count := 0
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		mesh_count += 1
		_check(mesh is ArrayMesh, "%s uses an imported ArrayMesh" % node.get_path())
		if mesh is ArrayMesh:
			var arrays := mesh.surface_get_arrays(0)
			_check(not (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty(),
				"%s has editable UVs" % node.get_path())
	_check(mesh_count > 0, "%s contains visible imported geometry" % scene_path)
	instance.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		failures += 1
		push_error("  FAIL: %s" % message)
