class_name ChunkHostStub
extends Node

## A minimal SceneChunk HOST for tests/tools: wires a GameState (+ scheduler, optional grid) and implements the
## host contract a chunk calls — so a chunk can be BUILT and driven without the full fragment_preview shell.
## Mirrors the subset of fragment_preview_sequence's host methods a chunk's build path touches.

var game_state
var scheduler
var grid
var interactables: Array = []
var step := ""

func setup(use_grid := false, room := Vector2i(40, 20)) -> void:
	scheduler = EventScheduler.new()
	game_state = GameState.new()
	game_state.scheduler = scheduler
	if use_grid:
		grid = GridWorld.new()
		grid.create_room(room.x, room.y)
		game_state.grid = grid

## Register the party in the data layer (so a chunk's enemies have detection targets / a flure has lure targets).
func register_party(spawns: Dictionary, speed := 3.0) -> void:
	for cid in spawns:
		game_state.register_character(str(cid), spawns[cid], speed)

func get_preview_game_state():
	return game_state

func get_preview_scheduler():
	return scheduler

func register_preview_interactable(it) -> void:
	interactables.append(it)

func set_preview_step(s: String) -> void:
	step = s

func get_preview_character_position(cid: String) -> Vector3:
	if game_state != null and game_state.characters.has(cid):
		return game_state.get_position(cid)
	return Vector3.ZERO
