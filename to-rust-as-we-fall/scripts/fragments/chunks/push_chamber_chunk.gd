extends "res://scripts/scene_chunks/scene_chunk.gd"

## PUSH CHAMBER — the sealed mini-Sokoban room (docs/PUSH_PUZZLE_BUILDER.md steps 6; proofs §8.7).
##
## One tension, one verb: PUSH. The chamber's crates start where a seeded backward walk left them,
## and the room ships its own solution certificate; solving it — every crate on a goal plate —
## latches the chamber gate open. The latch is the room's ONLY output.
##
## THE SEAL is the design's load-bearing property, not a styling choice. A push puzzle is
## non-monotone (a wedged crate is a genuinely lost state), which would poison stretch-level
## solvability if it could leak. It cannot, because:
##   - the RESET control restores the exact opening state — crates re-placed, any body inside
##     returned to the mouth — so no internal state permanently withholds the gate;
##   - the gate latch is monotone (opens once, stays open);
##   - nothing else crosses the boundary: no items, no stats, no consumables either way.
## Under those three facts the chamber presents to a stretch as an ordinary monotone gate, and the
## stretch-level greedy validator's completeness survives the composition.
##
## Composes shipped systems only: the push verb (PushTarget + command_push_object), the crawl-mouth
## one-at-a-time law (CrawlTunnel), goal plates as floor marks, and the gate as dynamic blockers on
## the door cells. Greybox per the micro-tension framing; dressing is a canon consultation.

const CHAMBER_MIN := Vector2i(12, 3)
const CHAMBER_MAX := Vector2i(19, 11)
const GOAL_CELLS: Array[Vector2i] = [Vector2i(17, 6), Vector2i(15, 9)]
const DOOR_CELLS: Array[Vector2i] = [Vector2i(20, 7)]
const MOUTH_OUTSIDE := Vector3(9.5, 0.0, 7.5)
const MOUTH_INSIDE := Vector3(12.5, 0.0, 7.5)
const EXIT_POS := Vector3(23.5, 0.0, 7.5)

const PARTY_IDS := ["aster", "peris", "endo"]
const SPAWNS := {
	"aster": Vector3(3.0, 0.0, 7.5),
	"peris": Vector3(3.0, 0.0, 5.5),
	"endo": Vector3(3.0, 0.0, 9.5),
}

var _phase := "ready"            # ready | solving | open | complete
var _gate_open := false
var _resets := 0
var _model: PushPuzzleModel
var _instance: Dictionary = {}
var _crate_meshes: Dictionary = {}
var _door_meshes: Array = []
var _status_label: Label3D
var _seed_value := 7

func configure_chunk(config: Dictionary) -> void:
	_seed_value = int(config.get("seed", 7))

func _build_chunk() -> void:
	_add_floor(self, Vector3(12.0, -0.05, 7.5), Vector3(24.0, 0.1, 13.0), Color(0.12, 0.13, 0.15))
	_build_chamber_walls()
	_build_model_and_instance()
	_build_goal_plates()
	_build_crates()
	_build_mouth()
	_build_gate()
	_build_reset_control()
	var exit_door := _add_box(self, EXIT_POS + Vector3(0.0, 1.0, 0.0),
		Vector3(0.5, 2.0, 1.6), Color(0.46, 0.38, 0.26))
	_add_object_interactable(
		self, "ChamberExit", "Leave through the opened gate", EXIT_POS, "LEAVE",
		[exit_door], "", 0.6, true, 1.6, Interactable.InteractableType.INSPECTION
	).interacted.connect(_on_exit)
	_status_label = _add_label(self, "", Vector3(15.0, 3.4, 7.5), Color(0.78, 0.86, 0.96))
	var gs = _get_game_state()
	if gs != null and gs.has_signal("character_arrived") \
			and not gs.character_arrived.is_connected(_on_body_arrived):
		gs.character_arrived.connect(_on_body_arrived)

## The chamber envelope: a wall ring with two openings — the crawl mouth (a wall the tunnel carries
## bodies through) and the door cells the gate blockers close until the room is solved.
func _chamber_wall_cells() -> Array:
	var walls: Array = []
	for x in range(CHAMBER_MIN.x - 1, CHAMBER_MAX.x + 2):
		for y in [CHAMBER_MIN.y - 1, CHAMBER_MAX.y + 1]:
			walls.append(Vector2i(x, y))
	for y in range(CHAMBER_MIN.y, CHAMBER_MAX.y + 1):
		for x in [CHAMBER_MIN.x - 1, CHAMBER_MAX.x + 1]:
			var cell := Vector2i(x, y)
			if cell == Vector2i(CHAMBER_MIN.x - 1, 7):
				continue   # the mouth wall cell stays a wall; the crawl's authored path crosses it
			if DOOR_CELLS.has(cell):
				continue   # the doorway is floor; the GATE blockers close it until solved
			walls.append(cell)
	return walls

func _build_chamber_walls() -> void:
	for cell_v in _chamber_wall_cells():
		var cell: Vector2i = cell_v
		_add_box(self, Vector3(float(cell.x) + 0.5, 0.6, float(cell.y) + 0.5),
			Vector3(0.95, 1.2, 0.95), Color(0.30, 0.28, 0.26))

func _build_model_and_instance() -> void:
	var cells: Array = []
	for x in range(CHAMBER_MIN.x, CHAMBER_MAX.x + 1):
		for y in range(CHAMBER_MIN.y, CHAMBER_MAX.y + 1):
			cells.append(Vector2i(x, y))
	_model = PushPuzzleModel.new(cells, GOAL_CELLS)
	for seed_probe in range(_seed_value, _seed_value + 40):
		_instance = PushPuzzleBuilder.build(_model, seed_probe, 12, 3)
		if not _instance.is_empty():
			break

func _build_goal_plates() -> void:
	for g in GOAL_CELLS:
		_add_box(self, Vector3(float(g.x) + 0.5, 0.02, float(g.y) + 0.5),
			Vector3(0.9, 0.04, 0.9), Color(0.34, 0.52, 0.38))

func _build_crates() -> void:
	var gs = _get_game_state()
	if gs == null or _instance.is_empty():
		return
	var index := 0
	for cell_v in _instance["crates"]:
		var cell: Vector2i = cell_v
		var obj_id := "chamber_crate_%d" % index
		var world := Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)
		if not gs.physics_objects.has(obj_id):
			gs.register_physics_object(obj_id, world, 0.45, 3.0, 0.7, true)
		var mesh := _add_box(self, world + Vector3(0, 0.45, 0), Vector3(0.85, 0.9, 0.85),
			Color(0.55, 0.42, 0.25))
		_crate_meshes[obj_id] = mesh
		PushTarget.wrap(mesh, obj_id)
		index += 1

## The tunnel's rider comes from the host's live selection, the same authority a real click uses.
func _selected_party_ids() -> Array:
	if host != null and host.has_method("get_preview_selected_characters"):
		return host.call("get_preview_selected_characters")
	return []

func _build_mouth() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var mouth := CrawlTunnel.new()
	mouth.name = "ChamberMouth"
	mouth.set_group_provider(_selected_party_ids)
	add_child(mouth)
	if mouth.has_method("configure"):
		mouth.configure(gs, MOUTH_OUTSIDE, [MOUTH_OUTSIDE, MOUTH_INSIDE], 1.4, 0.9)

func _build_gate() -> void:
	var gs = _get_game_state()
	for cell in DOOR_CELLS:
		if gs != null and gs.grid != null:
			gs.grid.add_dynamic_blocker(cell, "chamber_gate")
		var door := _add_box(self, Vector3(float(cell.x) + 0.5, 0.75, float(cell.y) + 0.5),
			Vector3(0.9, 1.5, 0.9), Color(0.62, 0.5, 0.3))
		_door_meshes.append(door)

func _build_reset_control() -> void:
	var lever := _add_box(self, MOUTH_OUTSIDE + Vector3(-0.5, 0.6, -1.8),
		Vector3(0.4, 1.2, 0.4), Color(0.4, 0.5, 0.62))
	_add_object_interactable(
		self, "ChamberReset", "Reset the chamber", MOUTH_OUTSIDE + Vector3(-0.5, 0.0, -1.8),
		"RESET", [lever], "", 0.5, true, 1.4, Interactable.InteractableType.INSPECTION
	).interacted.connect(_reset_chamber_to_start)

## The seal's second clause: restore EXACTLY the opening state. Crates are re-registered at their
## generated cells (both operations are logged, so replay reproduces the reset), and any body
## standing inside the chamber is returned to the mouth — a reset must never strand. The latch is
## deliberately NOT cleared: the gate is monotone, and re-closing it would let a solved room
## un-solve, which is the exact property the seal forbids.
func _reset_chamber_to_start(_source = null) -> void:
	var gs = _get_game_state()
	if gs == null or _instance.is_empty():
		return
	var index := 0
	for cell_v in _instance["crates"]:
		var cell: Vector2i = cell_v
		var obj_id := "chamber_crate_%d" % index
		if gs.physics_objects.has(obj_id):
			gs.unregister_physics_object(obj_id)
		gs.register_physics_object(obj_id,
			Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5), 0.45, 3.0, 0.7, true)
		index += 1
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id):
			continue
		var pos: Vector3 = gs.get_position(char_id)
		var cell := Vector2i(int(floor(pos.x)), int(floor(pos.z)))
		if cell.x >= CHAMBER_MIN.x and cell.x <= CHAMBER_MAX.x \
				and cell.y >= CHAMBER_MIN.y and cell.y <= CHAMBER_MAX.y:
			# A body inside walks back out under its own power. The reset restores the room, not
			# the bodies: moving one is a queued command like any other, so the consequences of it
			# crossing the mouth ride the scheduler instead of appearing at a new position.
			gs.command_move_to_pos(char_id, MOUTH_OUTSIDE)
	_resets += 1

func _on_body_arrived(_char_id: String) -> void:
	_evaluate_solved()

## Solved = every crate on a goal plate. The latch is a one-way transition: blockers removed, door
## visuals dropped, and nothing else — the room's entire output is this flag.
func _evaluate_solved() -> void:
	if _gate_open or _instance.is_empty():
		return
	var gs = _get_game_state()
	if gs == null:
		return
	var crates := {}
	for obj_id_v in gs.physics_objects.keys():
		var obj_id := str(obj_id_v)
		if not obj_id.begins_with("chamber_crate_"):
			continue
		crates[gs.grid.world_to_grid(gs.get_physics_position(obj_id))] = true
	if crates.is_empty() or not _model.is_solved(crates):
		return
	_gate_open = true
	_phase = "open"
	for cell in DOOR_CELLS:
		if gs.grid != null:
			gs.grid.remove_dynamic_blocker(cell)
	for door in _door_meshes:
		if is_instance_valid(door):
			door.visible = false

## The chamber's live state key, for the reset guard: crate cells in canonical order plus the latch.
func chamber_state_key() -> String:
	var gs = _get_game_state()
	if gs == null:
		return ""
	var cells: Array = []
	for obj_id_v in gs.physics_objects.keys():
		var obj_id := str(obj_id_v)
		if obj_id.begins_with("chamber_crate_"):
			cells.append(gs.grid.world_to_grid(gs.get_physics_position(obj_id)))
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var parts: Array = []
	for c in cells:
		parts.append("%d,%d" % [c.x, c.y])
	return "|".join(parts) + "#gate=%s" % str(_gate_open)

func gate_open() -> bool:
	return _gate_open

func puzzle_certificate() -> Array:
	return (_instance.get("certificate", []) as Array).duplicate(true)

func _members_across() -> int:
	var gs = _get_game_state()
	if gs == null:
		return 0
	var count := 0
	for char_id in PARTY_IDS:
		if gs.characters.has(char_id) and gs.get_position(char_id).x > 22.0:
			count += 1
	return count

func _on_exit() -> void:
	if _phase == "complete" or not _gate_open:
		return
	if _members_across() < 1:
		return
	_phase = "complete"

func reset_preview_state() -> void:
	_phase = "ready"
	_resets = 0

func headless_process(delta: float) -> void:
	_tick(delta)

func _process(delta: float) -> void:
	_tick(delta)

func _tick(_delta: float) -> void:
	var gs = _get_game_state()
	if gs != null:
		for obj_id_v in _crate_meshes.keys():
			var obj_id := str(obj_id_v)
			if gs.physics_objects.has(obj_id) and is_instance_valid(_crate_meshes[obj_id]):
				var pos: Vector3 = gs.get_physics_position(obj_id)
				_crate_meshes[obj_id].position = Vector3(pos.x, 0.45, pos.z)
	if _status_label == null:
		return
	_status_label.text = "GATE: %s  //  RESETS: %d" % [
		"OPEN" if _gate_open else "sealed",
		_resets,
	]

## Declared from the design (§8.7's clauses, stated as checkable components and claims).
func get_fragment_manifest() -> Dictionary:
	return {
		"components": [
			{"id": "crates", "kind": "node", "node_class": "PushTarget",
				"count": GOAL_CELLS.size()},
			{"id": "chamber_mouth", "kind": "node", "node_class": "CrawlTunnel", "count": 1},
			{"id": "reset_control", "kind": "interactable", "node_name": "ChamberReset"},
			{"id": "chamber_exit", "kind": "interactable", "node_name": "ChamberExit"},
		],
		"behaviours": [
			{
				"id": "certificate_opens_gate",
				"claim": "replaying the shipped certificate through the push verb latches the gate open",
				"test": "--test-push-chamber",
			},
			{
				"id": "reset_restores_sigma0",
				"claim": "the reset control restores the exact opening state and never strands a body",
				"test": "--test-push-chamber-reset",
			},
		],
	}

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": 26,
		"height": 15,
		"walkable_regions": [
			{"min": [1.0, 1.0], "max": [24.4, 13.4]},
		],
		"wall_cells": _chamber_wall_cells(),
	}

func get_preview_camera_profile() -> Dictionary:
	return {
		"follow_offset": Vector3(8.0, 19.0, 12.0),
		"min_zoom": 0.5,
		"max_zoom": 2.0,
		"initial_zoom": 1.0,
		"reset_yaw": true,
	}

func get_preview_camera_recenter_target() -> Vector3:
	return Vector3(14.0, 0.0, 7.5)

func get_scene_title() -> String:
	return "Push Chamber"

func get_scene_help() -> String:
	return "The crates in the sealed room want their plates, and the room only takes one of you -- the mouth is a crawl. Shove carefully: a crate against the wrong wall stays there. The lever outside puts the room back the way it started, and the gate, once earned, stays open."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()

func get_preview_anchors() -> Dictionary:
	return {
		"mouth_outside": MOUTH_OUTSIDE,
		"mouth_inside": MOUTH_INSIDE,
		"reset_control": MOUTH_OUTSIDE + Vector3(-0.5, 0.0, -1.8),
		"chamber_exit": EXIT_POS,
	}

func get_preview_state() -> Dictionary:
	return {
		"contract_id": "push_chamber_v1",
		"phase": _phase,
		"gate_open": _gate_open,
		"resets": _resets,
		"certificate_pushes": (_instance.get("certificate", []) as Array).size(),
		"seed": int(_instance.get("seed", -1)),
	}
