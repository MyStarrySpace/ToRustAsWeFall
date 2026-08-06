class_name PartyItemController
extends Node3D

## Shared party-item authority adapter and presenter.
##
## GameState remains the only inventory authority. This controller owns the scene-facing work that
## was previously duplicated in TutorialSequence and FragmentPreviewSequence: mutations, portable
## item reads, ground/hand presenters, inventory refresh notifications, and item consequence copy.
## Hosts configure callbacks; fragments do not grow a second item runtime.

const ItemDataScript := preload("res://scripts/game/objects/item_data.gd")
const MotherGearVisualScene := preload(
	"res://scenes/props/mother_flure/mother_gear.tscn"
)

const MODE_MINIMAL := "minimal"
const MODE_RICH := "rich"

var _game_state = null
var _host: Node = null
var _mode := MODE_MINIMAL
var _present_all_items := false
# Existing save data already carries this stable marker; the controller owns its meaning now.
var _presenter_property := "tutorial_item_presenter"
var _character_names: Dictionary = {}

var _message_sink := Callable()
var _note_sink := Callable()
var _status_sink := Callable()
var _character_sync_sink := Callable()
var _inventory_refresh_sink := Callable()
var _character_position_resolver := Callable()
var _character_node_resolver := Callable()

var _item_nodes: Dictionary = {}


func setup(game_state, host: Node, options: Dictionary = {}) -> void:
	_disconnect_signals()
	_game_state = game_state
	_host = host if host != null else get_parent()
	configure(options)
	_connect_signals()
	_refresh_presenters()
	_notify_inventory_changed()
	set_process(true)


func configure(options: Dictionary) -> void:
	_mode = str(options.get("mode", _mode))
	if _mode not in [MODE_MINIMAL, MODE_RICH]:
		_mode = MODE_MINIMAL
	_present_all_items = bool(options.get("present_all_items", _mode == MODE_RICH))
	_presenter_property = str(options.get("presenter_property", _presenter_property))
	_character_names = (options.get("character_names", _character_names) as Dictionary).duplicate()
	_message_sink = _callable_option(options, "message_sink", _message_sink)
	_note_sink = _callable_option(options, "note_sink", _note_sink)
	_status_sink = _callable_option(options, "status_sink", _status_sink)
	_character_sync_sink = _callable_option(
		options, "character_sync_sink", _character_sync_sink)
	_inventory_refresh_sink = _callable_option(
		options, "inventory_refresh_sink", _inventory_refresh_sink)
	_character_position_resolver = _callable_option(
		options, "character_position_resolver", _character_position_resolver)
	_character_node_resolver = _callable_option(
		options, "character_node_resolver", _character_node_resolver)
	_rebuild_presenters()


func bind_inventory_view(refresh_sink: Callable) -> void:
	_inventory_refresh_sink = refresh_sink
	_notify_inventory_changed()


func on_game_state_snapshot_restored() -> void:
	# Items are authoritative snapshot data. Reconcile presenters rather than preserving scene-only
	# nodes from the abandoned timeline.
	_refresh_presenters()
	_notify_inventory_changed()


func refresh_presenters() -> void:
	_refresh_presenters()


func clear_presenters() -> void:
	for node_v in _item_nodes.values():
		if is_instance_valid(node_v):
			(node_v as Node).queue_free()
	_item_nodes.clear()


## Pure presenter queries let tests prove automatic reconstruction without creating the node they
## are trying to observe.
func has_presenter(item_id: String) -> bool:
	return is_instance_valid(_item_nodes.get(item_id))


func get_presenter_node(item_id: String) -> Node3D:
	var node := _item_nodes.get(item_id) as Node3D
	return node if is_instance_valid(node) else null


## Return the controller-owned presenter so an authored beat can add temporary choreography
## without rebuilding or retaining a parallel item visual. GameState remains authoritative.
func ensure_presenter_node(item_id: String) -> Node3D:
	if item_id.is_empty() or _game_state == null or not _game_state.items.has(item_id):
		return null
	_ensure_item_node(item_id)
	var node := get_presenter_node(item_id)
	if node != null:
		_update_item_node(item_id, _game_state.items[item_id] as Dictionary)
	return node


## Retire only the controller-owned view. The authoritative item may already have been consumed;
## if it still exists, the next reconciliation will rebuild the truthful view for its location.
func retire_presenter(item_id: String) -> void:
	_remove_item_node(item_id)


# --- Authoritative item operations ---------------------------------------------------------

func spawn_item(item_type: String, position: Vector3, properties: Dictionary = {}) -> String:
	if _game_state == null:
		return ""
	var item_properties := properties.duplicate(true)
	# The marker survives serialization and lets the minimal campaign presenter reconstruct itself.
	# Rich preview mode deliberately presents every authoritative item.
	item_properties[_presenter_property] = true
	var item_id := str(_game_state.spawn_item(item_type, position, item_properties))
	_ensure_item_node(item_id)
	_notify_inventory_changed()
	return item_id


func remove_item(item_id: String) -> void:
	if _game_state == null:
		return
	_game_state.remove_item(item_id)
	_remove_item_node(item_id)
	_notify_inventory_changed()


func clear_items() -> void:
	if _game_state == null:
		return
	for item_id_v in _game_state.items.keys().duplicate():
		_game_state.remove_item(str(item_id_v))
	clear_presenters()
	_notify_inventory_changed()


func pick_up_item(char_id: String, item_id: String) -> bool:
	if _game_state == null:
		return false
	var accepted := bool(_game_state.pick_up_item(char_id, item_id))
	if accepted:
		_announce("%s picked up %s." % [
			_character_display_name(char_id), get_item_display_name(item_id, char_id)], 1.2)
	_notify_inventory_changed()
	return accepted


func drop_item(char_id: String, item_id: String) -> bool:
	if _game_state == null:
		return false
	var accepted := bool(_game_state.drop_item(char_id, item_id))
	if accepted:
		_announce("%s dropped %s." % [
			_character_display_name(char_id), get_item_display_name(item_id, char_id)], 1.2)
	_notify_inventory_changed()
	return accepted


func transfer_item(from_id: String, to_id: String, item_id: String) -> bool:
	if _game_state == null:
		return false
	var accepted := bool(_game_state.transfer_item(from_id, to_id, item_id))
	if accepted:
		_announce("%s handed %s to %s." % [
			_character_display_name(from_id),
			get_item_display_name(item_id, to_id),
			_character_display_name(to_id),
		], 1.3)
	_notify_inventory_changed()
	return accepted


func endocytose_item(char_id: String, item_id: String) -> bool:
	if _game_state == null:
		return false
	var accepted := bool(_game_state.endocytose_item(char_id, item_id))
	if accepted:
		_set_character_status(char_id, "consuming")
		_announce("%s starts consuming %s." % [
			_character_display_name(char_id), get_item_display_name(item_id, char_id)], 1.4)
	_notify_inventory_changed()
	return accepted


func exocytose_item(char_id: String, item_id: String) -> bool:
	if _game_state == null:
		return false
	var accepted := bool(_game_state.exocytose_item(char_id, item_id))
	if accepted:
		_announce("%s retrieves %s." % [
			_character_display_name(char_id), get_item_display_name(item_id, char_id)], 1.4)
	_notify_inventory_changed()
	return accepted


func get_item_state(item_id: String) -> Dictionary:
	if _game_state == null or not _game_state.items.has(item_id):
		return {}
	return (_game_state.items[item_id] as Dictionary).duplicate(true)


func get_hand_items(char_id: String) -> Array:
	return _game_state.get_hand_items(char_id) if _game_state != null else []


func get_hand_slots(char_id: String) -> Array:
	return _game_state.get_hand_slots(char_id) if _game_state != null else []


func get_internal_items(char_id: String) -> Array:
	return _game_state.get_internal_items(char_id) if _game_state != null else []


func get_collection_items() -> Array:
	return _game_state.collection.duplicate() if _game_state != null else []


func get_item_display_name(item_id: String, char_id := "") -> String:
	if _game_state == null or not _game_state.items.has(item_id):
		return item_id
	var item: Dictionary = _game_state.items[item_id]
	var properties: Dictionary = item.get("properties", {})
	var display_names: Dictionary = properties.get("display_names_by_character", {})
	if not char_id.is_empty() and display_names.has(char_id):
		return str(display_names.get(char_id, item_id))
	if properties.has("display_name"):
		return str(properties.get("display_name", item_id))
	return ItemDataScript.get_display_name(str(item.get("type", item_id)))


func get_primary_held_item(char_id: String) -> String:
	var held := get_hand_items(char_id)
	return str(held[0]) if not held.is_empty() else ""


func get_hold_receipt(char_id: String) -> Dictionary:
	var item_id := get_primary_held_item(char_id)
	if item_id.is_empty():
		return {}
	return {
		"control_id": "carried_item:%s" % item_id,
		"kind": "carried_item",
		"label": get_item_display_name(item_id, char_id),
	}


# --- Active-character convenience actions -------------------------------------------------

func consume_primary(char_id: String) -> bool:
	var item_id := get_primary_held_item(char_id)
	if item_id.is_empty():
		_announce("No held item to consume.", 1.1)
		return false
	if endocytose_item(char_id, item_id):
		return true
	_announce("That item cannot be consumed here.", 1.2)
	return false


func drop_primary(char_id: String) -> bool:
	var item_id := get_primary_held_item(char_id)
	if item_id.is_empty():
		_announce("No held item to drop.", 1.1)
		return false
	if drop_item(char_id, item_id):
		return true
	_announce("Couldn't drop that item right now.", 1.2)
	return false


func transfer_primary(from_id: String, candidate_ids: Array) -> bool:
	var item_id := get_primary_held_item(from_id)
	if item_id.is_empty():
		_announce("No held item to transfer.", 1.1)
		return false
	var target_id := ""
	var best_distance := INF
	var origin := _character_position(from_id)
	for candidate_v in candidate_ids:
		var candidate := str(candidate_v)
		if candidate.is_empty() or candidate == from_id or not _character_available(candidate):
			continue
		var distance := origin.distance_to(_character_position(candidate))
		if distance < best_distance:
			best_distance = distance
			target_id = candidate
	if not target_id.is_empty() and transfer_item(from_id, target_id, item_id):
		return true
	_announce("No nearby teammate can take that item.", 1.2)
	return false


func retrieve_primary(char_id: String) -> bool:
	var internal := get_internal_items(char_id)
	if internal.is_empty():
		_announce("No internal item to retrieve.", 1.1)
		return false
	if exocytose_item(char_id, str(internal[0])):
		return true
	_announce("Couldn't retrieve that item right now.", 1.2)
	return false


# --- Signal-owned feedback ----------------------------------------------------------------

func _connect_signals() -> void:
	if _game_state == null:
		return
	_connect_signal(&"item_picked_up", &"_on_item_changed")
	_connect_signal(&"item_dropped", &"_on_item_changed")
	_connect_signal(&"item_exocytosed", &"_on_item_changed")
	_connect_signal(&"item_transferred", &"_on_item_transferred")
	_connect_signal(&"item_endocytosed", &"_on_item_endocytosed")


func _disconnect_signals() -> void:
	if _game_state == null:
		return
	_disconnect_signal(&"item_picked_up", &"_on_item_changed")
	_disconnect_signal(&"item_dropped", &"_on_item_changed")
	_disconnect_signal(&"item_exocytosed", &"_on_item_changed")
	_disconnect_signal(&"item_transferred", &"_on_item_transferred")
	_disconnect_signal(&"item_endocytosed", &"_on_item_endocytosed")


func _on_item_changed(_char_id: String, _item_id: String) -> void:
	_refresh_presenters()
	_notify_inventory_changed()


func _on_item_transferred(_from_id: String, _to_id: String, _item_id: String) -> void:
	_refresh_presenters()
	_notify_inventory_changed()


func _on_item_endocytosed(char_id: String, item_id: String, effect: String) -> void:
	if _character_sync_sink.is_valid():
		_character_sync_sink.call(char_id)
	match effect:
		"stun_self":
			_set_character_status(char_id, "stunned")
		"self_damage":
			_set_character_status(char_id, "hurt")
		_:
			_set_character_status(char_id, "")
	var display := _character_display_name(char_id)
	var item_name := get_item_display_name(item_id, char_id)
	match effect:
		"digest":
			_note("%s digested %s and restored ATP." % [display, item_name], 3.2)
		"store":
			_note("%s stored %s internally." % [display, item_name], 3.2)
		"stun_self":
			_note("%s consumed something that should have stayed out of their body." % display, 3.2)
		"self_damage":
			_note("%s took internal damage from what they consumed." % display, 3.2)
	_refresh_presenters()
	_notify_inventory_changed()


# --- World presenters ---------------------------------------------------------------------

func _process(_delta: float) -> void:
	_refresh_presenters()


func _refresh_presenters() -> void:
	if _game_state == null:
		return
	for item_id_v in _game_state.items.keys():
		var item_id := str(item_id_v)
		if _should_present_item(_game_state.items[item_id] as Dictionary):
			_ensure_item_node(item_id)
	for item_id_v in _item_nodes.keys().duplicate():
		var item_id := str(item_id_v)
		if not _game_state.items.has(item_id) \
				or not _should_present_item(_game_state.items[item_id] as Dictionary):
			_remove_item_node(item_id)
			continue
		_update_item_node(item_id, _game_state.items[item_id] as Dictionary)


func _should_present_item(item: Dictionary) -> bool:
	return _present_all_items or bool((item.get("properties", {}) as Dictionary).get(
		_presenter_property, false))


func _ensure_item_node(item_id: String) -> void:
	if item_id.is_empty() or _item_nodes.has(item_id) or _game_state == null \
			or not _game_state.items.has(item_id):
		return
	var item: Dictionary = _game_state.items[item_id]
	var root := Node3D.new()
	root.name = ("PartyItem_" if _mode == MODE_RICH else "ChunkItem_") + item_id
	if _mode == MODE_RICH:
		_build_rich_visual(root, item)
	else:
		_build_minimal_visual(root, item)
	add_child(root)
	_item_nodes[item_id] = root
	_update_item_node(item_id, item)


func _build_minimal_visual(root: Node3D, item: Dictionary) -> void:
	var properties: Dictionary = item.get("properties", {})
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	mesh_instance.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = _portable_color(
		properties.get("visual_color", Color(0.78, 0.78, 0.82)))
	material.emission_enabled = true
	material.emission = material.albedo_color.lightened(0.1)
	material.emission_energy_multiplier = 0.24
	mesh_instance.material_override = material
	root.add_child(mesh_instance)


func _build_rich_visual(root: Node3D, item: Dictionary) -> void:
	var item_type := str(item.get("type", ""))
	var properties: Dictionary = item.get("properties", {})
	var visual_kind := str(properties.get("visual_kind", item_type))
	var visual_scene_path := str(properties.get("visual_scene", ""))
	var authored_visual: Node3D = null
	if not visual_scene_path.is_empty():
		var packed := load(visual_scene_path) as PackedScene
		if packed != null:
			authored_visual = packed.instantiate() as Node3D
	if authored_visual == null and visual_kind == "mother_gear":
		authored_visual = MotherGearVisualScene.instantiate() as Node3D
	if authored_visual != null:
		authored_visual.name = "Mesh"
		authored_visual.set_meta("visual_identity", str(properties.get(
			"visual_identity", visual_kind)))
		root.add_child(authored_visual)
	else:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		mesh_instance.mesh = _build_item_mesh(visual_kind)
		var material := StandardMaterial3D.new()
		material.albedo_color = _portable_color(
			properties.get("visual_color", _item_color(item_type)))
		material.emission_enabled = true
		material.emission = material.albedo_color.lightened(0.08)
		material.emission_energy_multiplier = 0.24
		mesh_instance.material_override = material
		root.add_child(mesh_instance)
	var label := Label3D.new()
	label.name = "Label"
	label.pixel_size = 0.0075
	label.font_size = 24
	label.position = Vector3(0.0, 0.65, 0.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.45)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)


func _update_item_node(item_id: String, item: Dictionary) -> void:
	var root := _item_nodes.get(item_id) as Node3D
	if not is_instance_valid(root):
		return
	var properties: Dictionary = item.get("properties", {})
	var location := str(item.get("location", "ground"))
	var label := root.get_node_or_null("Label") as Label3D
	if label != null:
		label.text = get_item_display_name(item_id, str(item.get("holder", ""))).to_upper()
	match location:
		"ground":
			root.visible = true
			var data_position: Vector3 = item.get("position", Vector3.ZERO)
			var default_y := 0.42 if _mode == MODE_MINIMAL else maxf(data_position.y, 0.42)
			data_position.y = float(properties.get("ground_visual_y", default_y))
			root.global_position = _to_render_position(data_position)
			if label != null:
				label.visible = bool(properties.get("ground_label_visible", true))
		"hand":
			var holder := str(item.get("holder", ""))
			var holder_position := _character_render_position(holder)
			root.visible = holder_position.is_finite()
			if root.visible:
				root.global_position = holder_position + _hand_offset(holder, item_id)
			if label != null:
				label.visible = false
		_:
			root.visible = false


func _hand_offset(holder: String, item_id: String) -> Vector3:
	if _mode == MODE_MINIMAL:
		return Vector3(0.38, 1.05, 0.1)
	var slots := get_hand_slots(holder)
	var occurrence_count := 0
	var slot_index := -1
	for index in range(slots.size()):
		if slots[index] == item_id:
			occurrence_count += 1
			if slot_index < 0:
				slot_index = index
	if occurrence_count >= 2:
		return Vector3(0.0, 1.08, 0.46)
	if slot_index == 0:
		return Vector3(-0.34, 0.98, 0.3)
	if slot_index == 1:
		return Vector3(0.34, 0.98, 0.3)
	return Vector3(0.0, 1.02, 0.38)


func _remove_item_node(item_id: String) -> void:
	if not _item_nodes.has(item_id):
		return
	var node_v: Variant = _item_nodes[item_id]
	_item_nodes.erase(item_id)
	if is_instance_valid(node_v):
		(node_v as Node).queue_free()


func _rebuild_presenters() -> void:
	clear_presenters()
	_refresh_presenters()


func _build_item_mesh(visual_kind: String) -> Mesh:
	match visual_kind:
		"gear":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.34
			torus.outer_radius = 0.58
			torus.rings = 18
			torus.ring_segments = 12
			return torus
		"seed":
			var seed := SphereMesh.new()
			seed.radius = 0.18
			seed.height = 0.36
			return seed
		"component":
			var component := BoxMesh.new()
			component.size = Vector3(0.34, 0.34, 0.34)
			return component
		_:
			var blob := SphereMesh.new()
			blob.radius = 0.24
			blob.height = 0.48
			return blob


func _item_color(item_type: String) -> Color:
	match item_type:
		"lysate": return Color(0.78, 0.68, 0.42)
		"seed": return Color(0.56, 0.82, 0.48)
		"hushbloom": return Color(0.82, 0.74, 0.95)
		"cure_component": return Color(0.62, 0.82, 0.95)
		"mother_gear": return Color(0.84, 0.7, 0.44)
		_: return Color(0.78, 0.78, 0.82)


func _portable_color(value: Variant) -> Color:
	if value is Color:
		return value as Color
	if value is Array:
		var channels := value as Array
		if channels.size() >= 3:
			return Color(
				float(channels[0]), float(channels[1]), float(channels[2]),
				float(channels[3]) if channels.size() >= 4 else 1.0)
	if value is String:
		var encoded := str(value).strip_edges()
		if encoded.begins_with("(") and encoded.ends_with(")"):
			var parts := encoded.trim_prefix("(").trim_suffix(")").split(",")
			if parts.size() >= 3:
				return Color(
					float(parts[0]), float(parts[1]), float(parts[2]),
					float(parts[3]) if parts.size() >= 4 else 1.0)
	return Color(0.78, 0.78, 0.82)


# --- Host adapters ------------------------------------------------------------------------

func _character_display_name(char_id: String) -> String:
	return str(_character_names.get(char_id, char_id.capitalize()))


func _character_position(char_id: String) -> Vector3:
	if _character_position_resolver.is_valid():
		var resolved: Variant = _character_position_resolver.call(char_id)
		if resolved is Vector3:
			return resolved as Vector3
	if _game_state != null and _game_state.characters.has(char_id):
		return _game_state.get_position(char_id)
	return Vector3.INF


func _character_render_position(char_id: String) -> Vector3:
	if _character_node_resolver.is_valid():
		var node_v: Variant = _character_node_resolver.call(char_id)
		if node_v is Node3D and is_instance_valid(node_v):
			return (node_v as Node3D).global_position
	if _game_state != null and _game_state.characters.has(char_id):
		return _game_state.get_render_position(char_id)
	return Vector3.INF


func _character_available(char_id: String) -> bool:
	return _game_state != null and _game_state.characters.has(char_id) \
		and not _game_state.is_downed(char_id) \
		and float(_game_state.get_stat(char_id, "hp")) > 0.0


func _to_render_position(data_position: Vector3) -> Vector3:
	if _game_state != null and _game_state.coord_map != null \
			and _game_state.coord_map.has_method("to_world"):
		return _game_state.coord_map.to_world(data_position)
	return data_position


func _announce(text: String, duration: float) -> void:
	if _message_sink.is_valid():
		_message_sink.call(text, duration)


func _note(text: String, duration: float) -> void:
	if _note_sink.is_valid():
		_note_sink.call(text, duration)
	else:
		_announce(text, duration)


func _set_character_status(char_id: String, status: String) -> void:
	if _status_sink.is_valid():
		_status_sink.call(char_id, status)


func _notify_inventory_changed() -> void:
	if _inventory_refresh_sink.is_valid():
		_inventory_refresh_sink.call()


func _connect_signal(signal_name: StringName, method_name: StringName) -> void:
	if not _game_state.has_signal(signal_name):
		return
	var callback := Callable(self, method_name)
	if not _game_state.is_connected(signal_name, callback):
		_game_state.connect(signal_name, callback)


func _disconnect_signal(signal_name: StringName, method_name: StringName) -> void:
	if not _game_state.has_signal(signal_name):
		return
	var callback := Callable(self, method_name)
	if _game_state.is_connected(signal_name, callback):
		_game_state.disconnect(signal_name, callback)


func _callable_option(options: Dictionary, key: String, fallback: Callable) -> Callable:
	var value: Variant = options.get(key, fallback)
	return value as Callable if value is Callable else fallback


func _exit_tree() -> void:
	_disconnect_signals()
	clear_presenters()
	_game_state = null
	_host = null
