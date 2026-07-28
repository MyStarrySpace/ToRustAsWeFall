extends SceneTree
## Build the PIPE tileset: every pipe connector piece becomes a MeshLibrary item
## so GridMap3D scenes (flat levels, procedural generation) assemble pipe runs
## through PipeGrid.fill_gridmap — the same connector vocabulary the warped
## scenes place by hand. Cell size is ONE metre; meshes are cell-centered
## (GridMap item origins sit at cell centers). Visual-only: no collision.
##
## Run:  ../Godot_v4.7-stable_win64_console.exe --headless --path "." \
##           --script tools/build_pipe_meshlib.gd
## Output: res://resources/models/archetypes/pipe_tiles.meshlib  (committed)

const OUT_PATH := "res://resources/models/archetypes/pipe_tiles.meshlib"
const PIPE_IDS := ["pipe_straight", "pipe_elbow", "pipe_tee", "pipe_cross",
	"pipe_end", "pipe_straight_banded", "pipe_straight_valve"]

func _init() -> void:
	var lib := MeshLibrary.new()
	var item := 0
	for pid in PIPE_IDS:
		var piece := ArchetypePieceLibrary.instantiate(str(pid))
		var mesh: Mesh = null
		if piece is MeshInstance3D:
			mesh = (piece as MeshInstance3D).mesh
		elif piece != null:
			for c in piece.get_children():
				if c is MeshInstance3D:
					mesh = (c as MeshInstance3D).mesh
					break
		if mesh == null:
			push_warning("pipe meshlib: no mesh for '%s'" % pid)
			continue
		lib.create_item(item)
		lib.set_item_name(item, str(pid))
		lib.set_item_mesh(item, mesh)
		item += 1
		if piece != null:
			piece.free()
	var err := ResourceSaver.save(lib, OUT_PATH)
	print("[PIPELIB] %d items -> %s (err=%d)" % [item, OUT_PATH, err])
	quit()
