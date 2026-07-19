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
	"res://scenes/props/peris/plant_table.tscn",
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
	_check(problems.is_empty(), "Peris marker layout validates clean: %s" % [problems])
	_check_furniture_clearance(room)
	_check_removed_composition(room)
	_check_plant_tables(room)
	_check_portal_layer_separation(room)
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


func _check_removed_composition(room: Node) -> void:
	for node_name in ["couch", "Plush_Bear", "PlantStand"]:
		var obsolete := room.find_child(node_name, true, false) as Node3D
		_check(obsolete == null or not obsolete.is_visible_in_tree(),
			"%s is removed from the live room composition" % node_name)


func _check_plant_tables(room: Node) -> void:
	var plant_bounds: Array[AABB] = []
	for i in range(1, 10):
		var table := room.find_child("Plant%dTable" % i, true, false) as Node3D
		var plant := room.find_child("Plant%d" % i, true, false) as Node3D
		var marker := room.find_child("Plant%dTableAnchor" % i, true, false) as Node3D
		_check(table != null and plant != null and marker != null,
			"Plant%d has its own authored table and marker" % i)
		if table == null or plant == null or marker == null:
			continue
		_check(table.global_position.is_equal_approx(marker.global_position),
			"Plant%d table follows its grid marker" % i)
		var table_bounds := _node_aabb(table)
		var plant_box := _node_aabb(plant)
		plant_bounds.append(plant_box)
		_check(absf(plant.global_position.y - table_bounds.end.y) <= 0.015,
			"Plant%d pot rests on its own table" % i)
		_check(absf(table.global_position.x / room.ROOM_GRID_STEP - roundf(table.global_position.x / room.ROOM_GRID_STEP)) <= 0.001
			and absf(table.global_position.z / room.ROOM_GRID_STEP - roundf(table.global_position.z / room.ROOM_GRID_STEP)) <= 0.001,
			"Plant%d table is aligned to the room grid" % i)
	for i in range(plant_bounds.size()):
		for j in range(i + 1, plant_bounds.size()):
			var a := plant_bounds[i]
			var b := plant_bounds[j]
			var overlap_x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
			var overlap_z := minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z)
			_check(overlap_x <= 0.0 or overlap_z <= 0.0,
				"Plant%d and Plant%d canopies do not clip" % [i + 1, j + 1])


func _check_portal_layer_separation(room: Node) -> void:
	var glow := room.find_child("PortalGlowSurface", true, false) as MeshInstance3D
	var view := room.find_child("PortalViewSurface", true, false) as MeshInstance3D
	_check(glow != null and view != null, "Portal glow and live view surfaces exist")
	if glow == null or view == null:
		return
	var glow_box := glow.global_transform * glow.mesh.get_aabb()
	_check(view.global_position.x - glow_box.end.x >= 0.02,
		"Portal live view keeps a depth gap from the transparent glow")


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
		var node_label := "%s:%s" % [scene_path, str(node.name)]
		mesh_count += 1
		_check(mesh is ArrayMesh, "%s uses an imported ArrayMesh" % node_label)
		if mesh is ArrayMesh:
			var arrays := mesh.surface_get_arrays(0)
			_check(not (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty(),
				"%s has editable UVs" % node_label)
	_check(mesh_count > 0, "%s contains visible imported geometry" % scene_path)
	instance.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		failures += 1
		push_error("  FAIL: %s" % message)
