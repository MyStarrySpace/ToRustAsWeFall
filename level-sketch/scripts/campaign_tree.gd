class_name CampaignTree
extends Tree

## A Tree that supports drag-and-drop reordering / re-parenting of campaign nodes. On a
## drop it emits node_dropped(dragged_id, target_id, section) where section is -1 (above
## the target), 0 (onto it), or +1 (below it); the manager maps that to model moves.

signal node_dropped(dragged_id: String, target_id: String, section: int)


func _ready() -> void:
	drop_mode_flags = Tree.DROP_MODE_INBETWEEN | Tree.DROP_MODE_ON_ITEM


func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null:
		return null
	var id := str(item.get_metadata(0))
	if id == "":
		return null
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.28, 0.40, 0.95)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = item.get_text(0)
	label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	panel.add_child(label)
	set_drag_preview(panel)
	return {"type": "campaign_node", "id": id}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary \
		and str((data as Dictionary).get("type", "")) == "campaign_node" \
		and get_item_at_position(at_position) != null


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var item := get_item_at_position(at_position)
	if item == null:
		return
	node_dropped.emit(str((data as Dictionary).get("id", "")), str(item.get_metadata(0)), get_drop_section_at_position(at_position))
