extends SceneTree
## Build the GRIDMAP tileset from the archetype piece library: every tileable
## 2.0 m-module piece (and its variations) becomes a MeshLibrary item, so flat
## and generated levels can PAINT floors/walls/rails from the same Blender-built
## vocabulary the wash relay places by hand. Floor tiles carry a box collision
## matching the module; wall/rail/scaffold items are visual (levels own their
## own walkability via unified_grid_v1 — the collision here is for physics
## queries and prop-survey support, not for gameplay walkable truth).
##
## Run:  ../Godot_v4.7-stable_win64_console.exe --headless --path "." \
##           --script tools/build_piece_meshlib.gd
## Output: res://resources/models/archetypes/piece_tiles.meshlib  (committed)

const OUT_PATH := "res://resources/models/archetypes/piece_tiles.meshlib"

# id -> [has_floor_collision, collision_height]
const TILE_IDS := {
	"deck_planks": [true, 0.10],
	"deck_planks_b": [true, 0.10],
	"deck_planks_c": [true, 0.10],
	"deck_grate": [true, 0.12],
	"deck_grate_b": [true, 0.12],
	"wall_panel_tile": [false, 0.0],
	"wall_panel_tile_b": [false, 0.0],
	"wall_panel_tile_c": [false, 0.0],
	"railing_run": [false, 0.0],
	"pipe_rack": [false, 0.0],
	"scaffold_truss": [false, 0.0],
	"scaffold_leg": [false, 0.0],
	"water_channel": [true, 0.16],
}

func _init() -> void:
	var lib := MeshLibrary.new()
	var item := 0
	var listed: Array = []
	for pid in TILE_IDS.keys():
		var piece := ArchetypePieceLibrary.instantiate(str(pid))
		if piece == null or not (piece is MeshInstance3D):
			push_warning("meshlib: no mesh piece for '%s'" % pid)
			continue
		var mi := piece as MeshInstance3D
		lib.create_item(item)
		lib.set_item_name(item, str(pid))
		lib.set_item_mesh(item, mi.mesh)
		var spec: Array = TILE_IDS[pid]
		if bool(spec[0]):
			var shape := BoxShape3D.new()
			var h := float(spec[1])
			shape.size = Vector3(2.0, h, 2.0)
			lib.set_item_shapes(item, [shape, Transform3D(Basis.IDENTITY,
				Vector3(0.0, h * 0.5, 0.0))])
		listed.append(pid)
		item += 1
		mi.free()
	var err := ResourceSaver.save(lib, OUT_PATH)
	print("[MESHLIB] %d items -> %s (err=%d): %s" % [item, OUT_PATH, err, ", ".join(listed)])
	quit()
