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
var active_character := "aster"
var routing_mode := "safe"

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
	var roster: Array[String] = []
	for cid in spawns:
		var character_id := str(cid)
		game_state.register_character(character_id, spawns[cid], speed)
		roster.append(character_id)
	game_state.set_party(roster)

func get_preview_game_state():
	return game_state

func get_preview_scheduler():
	return scheduler

func get_preview_scheduler_tick() -> float:
	return float(scheduler.get_current_tick()) if scheduler != null else 0.0

func get_preview_active_character() -> String:
	return active_character

func set_preview_active_character(char_id: String) -> void:
	active_character = char_id

func get_preview_routing_mode() -> String:
	return routing_mode

func set_preview_routing_mode(mode: String) -> void:
	routing_mode = mode

func register_preview_interactable(it) -> void:
	interactables.append(it)

func set_preview_step(s: String) -> void:
	step = s

func get_preview_character_position(cid: String) -> Vector3:
	if game_state != null and game_state.characters.has(cid):
		return game_state.get_position(cid)
	return Vector3.ZERO

func set_preview_character_position(cid: String, position: Vector3) -> void:
	if game_state != null and game_state.characters.has(cid):
		game_state.snap_character_to(cid, position)

func spawn_preview_item(item_type: String, position: Vector3, properties: Dictionary = {}) -> String:
	if game_state == null:
		return ""
	return game_state.spawn_item(item_type, position, properties)

func remove_preview_item(item_id: String) -> void:
	if game_state != null:
		game_state.remove_item(item_id)

func get_preview_item_state(item_id: String) -> Dictionary:
	if game_state == null or not game_state.items.has(item_id):
		return {}
	return (game_state.items[item_id] as Dictionary).duplicate(true)

func pick_up_preview_item(char_id: String, item_id: String) -> bool:
	return game_state != null and game_state.pick_up_item(char_id, item_id)

func drop_preview_item(char_id: String, item_id: String) -> bool:
	return game_state != null and game_state.drop_item(char_id, item_id)

func transfer_preview_item(from_id: String, to_id: String, item_id: String) -> bool:
	return game_state != null and game_state.transfer_item(from_id, to_id, item_id)

func endocytose_preview_item(char_id: String, item_id: String) -> bool:
	return game_state != null and game_state.endocytose_item(char_id, item_id)

func exocytose_preview_item(char_id: String, item_id: String) -> bool:
	return game_state != null and game_state.exocytose_item(char_id, item_id)

func get_preview_hand_items(char_id: String) -> Array:
	return game_state.get_hand_items(char_id) if game_state != null else []

func get_preview_hand_slots(char_id: String) -> Array:
	return game_state.get_hand_slots(char_id) if game_state != null else []

func get_preview_internal_items(char_id: String) -> Array:
	return game_state.get_internal_items(char_id) if game_state != null else []
