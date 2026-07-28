extends SceneTree
## The DATUM TABLE: measure every archetype library piece's true combined AABB
## (footprint, bottom, top) from its actual meshes. Placement authoring reads
## THESE numbers — never eyeballed sizes (the measurement law: pipes meet
## mouth-to-mouth, feet sit on decks, only because the lengths are measured).
##
## Run:  ../Godot_v4.7-stable_win64_console.exe --headless --path "." \
##           --script tools/probe_piece_datums.gd

func _init() -> void:
	var ids: Array = []
	ids.append_array(ArchetypePieceLibrary.piece_ids())
	ids.append_array(ArchetypePieceLibrary.dressing_ids())
	for pid in ids:
		var piece := ArchetypePieceLibrary.instantiate(str(pid))
		if piece == null:
			print("[DATUM] %-22s MISSING" % pid)
			continue
		var aabb := _combined_aabb(piece)
		if aabb.size == Vector3.ZERO:
			print("[DATUM] %-22s EMPTY" % pid)
		else:
			print("[DATUM] %-22s size=(%5.2f %5.2f %5.2f)  x=[%6.2f..%5.2f]  y=[%6.2f..%5.2f]  z=[%6.2f..%5.2f]" % [
				pid, aabb.size.x, aabb.size.y, aabb.size.z,
				aabb.position.x, aabb.end.x, aabb.position.y, aabb.end.y,
				aabb.position.z, aabb.end.z])
		piece.free()
	quit()

func _combined_aabb(node: Node) -> AABB:
	var total := AABB()
	var first := true
	var stack: Array = [[node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var xf: Transform3D = entry[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var local := (n as MeshInstance3D).mesh.get_aabb()
			var world := xf * local
			if first:
				total = world
				first = false
			else:
				total = total.merge(world)
		for c in n.get_children():
			stack.append([c, xf])
	return total
