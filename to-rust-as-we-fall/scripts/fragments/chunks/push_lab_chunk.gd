extends "res://scripts/scene_chunks/scene_chunk.gd"

## Push Lab — three pushable-object scenarios on one grid, used for headless push tests AND for
## eyeballing the queued-push UX (ghost previews, blocked cursor):
##   A) an OPEN ROOM with a pushable crate — any direction with room behind it works.
##   B) a 1-cell-wide HALLWAY into an empty room — the crate can be pushed straight down the
##      corridor (the character stays behind it the whole way).
##   C) a hallway with a BEND — pushing around the corner is IMPOSSIBLE: there is no cell for the
##      character to stand on to shove in the new direction (classic Sokoban dead corner).
##   D) a CRATE PAIR — a second crate is an OBSTACLE: the plan must route around it (never through
##      its cell, never standing in it), and its own cell is a refused destination.

const PARTY_IDS := ["aster", "peris", "endo"]

const SPAWNS := {
	"aster": Vector3(2.5, 0.0, 2.5),
	"peris": Vector3(1.5, 0.0, 3.5),
	"endo": Vector3(3.5, 0.0, 1.5),
}

# Zone A: open room, cells x 1..8 / z 1..8.
const CRATE_OPEN_CELL := Vector2i(4, 4)
# Zone B: room x 11..13 z 1..3, corridor z=2 x 14..19, far room x 20..24 z 1..5.
const CRATE_HALL_CELL := Vector2i(14, 2)
const HALL_TARGET_CELL := Vector2i(21, 2)
# Zone C: corridor z=8 x 11..15, then a 1-wide vertical leg x=15 z 9..12 (the bend at 15,8).
const CRATE_BEND_CELL := Vector2i(13, 8)
const BEND_IMPOSSIBLE_CELL := Vector2i(15, 11)
# Zone D: a 6x5 room (x 1..6, z 9..13) with TWO crates in line — b sits directly east of a, so the
# straight push a->east must route around b (or refuse b's own cell as a destination).
const CRATE_PAIR_A_CELL := Vector2i(3, 11)
const CRATE_PAIR_B_CELL := Vector2i(4, 11)
const PAIR_TARGET_CELL := Vector2i(5, 11)

var _crate_meshes := {}  # obj_id -> MeshInstance3D (visual synced from the data layer)

func _build_chunk() -> void:
	# Floors (visual; the data-layer footprint is get_grid_data).
	_add_floor(self, Vector3(5.0, -0.05, 5.0), Vector3(8.0, 0.1, 8.0), Color(0.1, 0.11, 0.13))      # A
	_add_floor(self, Vector3(12.5, -0.05, 2.5), Vector3(3.0, 0.1, 3.0), Color(0.09, 0.12, 0.11))    # B room
	_add_floor(self, Vector3(17.0, -0.05, 2.5), Vector3(6.0, 0.1, 1.0), Color(0.08, 0.1, 0.1))      # B corridor
	_add_floor(self, Vector3(22.5, -0.05, 3.0), Vector3(5.0, 0.1, 4.0), Color(0.09, 0.12, 0.11))    # B far room
	_add_floor(self, Vector3(13.5, -0.05, 8.5), Vector3(5.0, 0.1, 1.0), Color(0.1, 0.1, 0.12))      # C horizontal leg
	_add_floor(self, Vector3(15.5, -0.05, 11.0), Vector3(1.0, 0.1, 4.0), Color(0.1, 0.1, 0.12))     # C vertical leg
	_add_floor(self, Vector3(4.0, -0.05, 11.5), Vector3(6.0, 0.1, 5.0), Color(0.09, 0.11, 0.13))    # D pair room
	_add_label(self, "OPEN ROOM", Vector3(5.0, 1.6, 5.0), Color(0.6, 0.8, 0.7))
	_add_label(self, "HALLWAY PUSH", Vector3(17.0, 1.6, 2.5), Color(0.6, 0.8, 0.7))
	_add_label(self, "DEAD BEND", Vector3(14.0, 1.6, 9.0), Color(0.8, 0.6, 0.6))
	_add_label(self, "CRATE PAIR", Vector3(4.0, 1.6, 11.5), Color(0.6, 0.8, 0.7))
	_build_crates()

func _build_crates() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for entry in [["crate_open", CRATE_OPEN_CELL], ["crate_hall", CRATE_HALL_CELL],
			["crate_bend", CRATE_BEND_CELL], ["crate_pair_a", CRATE_PAIR_A_CELL],
			["crate_pair_b", CRATE_PAIR_B_CELL]]:
		var obj_id: String = entry[0]
		var cell: Vector2i = entry[1]
		var world := Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)
		if not gs.physics_objects.has(obj_id):
			gs.register_physics_object(obj_id, world, 0.45, 3.0, 0.7, true)
		var mesh := _add_box(self, world + Vector3(0, 0.45, 0), Vector3(0.85, 0.9, 0.85),
			Color(0.55, 0.42, 0.25), Color(0.4, 0.3, 0.15), 0.25, obj_id + "Mesh")
		_crate_meshes[obj_id] = mesh
		# Command-clicking the crate queues the planned push (the host connects the signal).
		PushTarget.wrap(mesh, obj_id)

## Crate visuals track the data layer (pure cosmetics — positions are scheduler-interpolated).
func headless_process(_delta: float) -> void:
	_sync_crates()

func _process(_delta: float) -> void:
	_sync_crates()

func _sync_crates() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for obj_id in _crate_meshes.keys():
		var mesh: MeshInstance3D = _crate_meshes[obj_id]
		if mesh != null and is_instance_valid(mesh) and gs.physics_objects.has(obj_id):
			var p: Vector3 = gs.get_physics_position(obj_id)
			mesh.position = Vector3(p.x, 0.45, p.z)

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": 26,
		"height": 14,
		"walkable_regions": [
			{"min": [1.0, 1.0], "max": [8.9, 8.9]},     # A: open room
			{"min": [11.0, 1.0], "max": [13.9, 3.9]},   # B: start room
			{"min": [14.0, 2.0], "max": [19.9, 2.9]},   # B: 1-wide corridor (z=2 only)
			{"min": [20.0, 1.0], "max": [24.9, 5.9]},   # B: far room
			{"min": [11.0, 8.0], "max": [15.9, 8.9]},   # C: horizontal leg (z=8)
			{"min": [15.0, 9.0], "max": [15.9, 12.9]},  # C: vertical leg (x=15)
			{"min": [1.0, 9.0], "max": [6.9, 13.9]},    # D: crate-pair room
		],
	}

func get_scene_title() -> String:
	return "Push Lab"

func get_scene_help() -> String:
	return "Three pushable crates: open room (free pushing), a one-cell hallway (straight push works), and a dead bend (no room to get behind the crate — the push refuses)."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()

func get_preview_anchors() -> Dictionary:
	return {
		"crate_open": Vector3(float(CRATE_OPEN_CELL.x) + 0.5, 0.0, float(CRATE_OPEN_CELL.y) + 0.5),
		"crate_hall": Vector3(float(CRATE_HALL_CELL.x) + 0.5, 0.0, float(CRATE_HALL_CELL.y) + 0.5),
		"crate_bend": Vector3(float(CRATE_BEND_CELL.x) + 0.5, 0.0, float(CRATE_BEND_CELL.y) + 0.5),
		"hall_target": Vector3(float(HALL_TARGET_CELL.x) + 0.5, 0.0, float(HALL_TARGET_CELL.y) + 0.5),
		"bend_impossible": Vector3(float(BEND_IMPOSSIBLE_CELL.x) + 0.5, 0.0, float(BEND_IMPOSSIBLE_CELL.y) + 0.5),
		"crate_pair_a": Vector3(float(CRATE_PAIR_A_CELL.x) + 0.5, 0.0, float(CRATE_PAIR_A_CELL.y) + 0.5),
		"crate_pair_b": Vector3(float(CRATE_PAIR_B_CELL.x) + 0.5, 0.0, float(CRATE_PAIR_B_CELL.y) + 0.5),
		"pair_target": Vector3(float(PAIR_TARGET_CELL.x) + 0.5, 0.0, float(PAIR_TARGET_CELL.y) + 0.5),
	}

## Declared from the design, before the body: --test-fragment-manifest proves the built scene
## matches. Every crate is a command-clickable PushTarget body; the bend and pair-blocker crates
## are named individually because the REFUSAL exhibits are the lab's point, not the happy pushes.
func get_fragment_manifest() -> Dictionary:
	return {
		"components": [
			{"id": "pushable_crates", "kind": "node", "node_class": "PushTarget", "count": 5},
			{"id": "pusher_body", "kind": "character", "char_prefix": "aster", "count": 1},
			{"id": "bend_crate", "kind": "interactable", "node_name": "PushTarget_crate_bend"},
			{"id": "pair_blocker", "kind": "interactable", "node_name": "PushTarget_crate_pair_b"},
		],
		"behaviours": [
			{
				"id": "dead_bend_refuses",
				"claim": "pushing around the bend has no plan and the command refuses without moving the crate",
				"test": "--test-push-lab",
			},
			{
				"id": "crate_blocks_crate",
				"claim": "a second crate is an obstacle: the plan routes around it and its own cell is a refused destination",
				"test": "--test-push-lab",
			},
			{
				"id": "queued_push_reads",
				"claim": "a queued push shows the object's ghost at a pushable destination and the blocked cursor at an impossible one",
				"test": "--test-push-lab",
			},
		],
	}

func get_preview_state() -> Dictionary:
	var gs = _get_game_state()
	var crates := {}
	if gs != null:
		for obj_id in ["crate_open", "crate_hall", "crate_bend", "crate_pair_a", "crate_pair_b"]:
			if gs.physics_objects.has(obj_id):
				var p: Vector3 = gs.get_physics_position(obj_id)
				crates[obj_id] = [p.x, p.z]
	return {"contract_id": "push_lab_v1", "crates": crates}
