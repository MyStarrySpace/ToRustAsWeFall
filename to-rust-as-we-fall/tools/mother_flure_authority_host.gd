extends "res://scripts/fragments/chunk_host_stub.gd"

## Item/stat portion of the production chunk-host contract used by the focused Mother Flure
## authority verifier. Keeping the helper data-only makes fresh-presenter tests independent of the
## full preview UI while still routing every inventory mutation through GameState.

func spawn_preview_item(item_type: String, position: Vector3, properties: Dictionary = {}) -> String:
	return game_state.spawn_item(item_type, position, properties) if game_state != null else ""

func remove_preview_item(item_id: String) -> void:
	if game_state != null:
		game_state.remove_item(item_id)

func pick_up_preview_item(char_id: String, item_id: String) -> bool:
	return game_state != null and game_state.pick_up_item(char_id, item_id)

func drop_preview_item(char_id: String, item_id: String) -> bool:
	return game_state != null and game_state.drop_item(char_id, item_id)

func transfer_preview_item(from_id: String, to_id: String, item_id: String) -> bool:
	return game_state != null and game_state.transfer_item(from_id, to_id, item_id)

func get_preview_hand_items(char_id: String) -> Array:
	return game_state.get_hand_items(char_id) if game_state != null else []

func get_preview_hand_slots(char_id: String) -> Array:
	return game_state.get_hand_slots(char_id) if game_state != null else []

func get_preview_internal_items(char_id: String) -> Array:
	return game_state.get_internal_items(char_id) if game_state != null else []

func get_preview_collection_items() -> Array:
	return game_state.collection.duplicate() if game_state != null else []

func get_preview_item_state(item_id: String) -> Dictionary:
	if game_state == null or not game_state.items.has(item_id):
		return {}
	return (game_state.items[item_id] as Dictionary).duplicate(true)

func get_preview_character_stat(char_id: String, stat_name: String) -> float:
	return float(game_state.get_stat(char_id, stat_name)) if game_state != null else 0.0

func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
	if game_state != null:
		game_state.set_stat(char_id, stat_name, value)

func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
	if game_state != null:
		game_state.adjust_stat(char_id, stat_name, delta)

func show_preview_message(_text: String, _duration := 2.0) -> void:
	pass

func show_preview_note(_text: String, _duration := 3.0) -> void:
	pass
