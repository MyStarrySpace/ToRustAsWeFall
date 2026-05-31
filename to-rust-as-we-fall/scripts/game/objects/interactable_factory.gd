class_name InteractableFactory
extends RefCounted

## One place to spawn a data-first interactable: register its spec in GameState,
## instantiate the view scene, bind the view to the registered id, and return the
## node. Callers keep wiring behaviour by connecting the node's `interacted`
## signal. A `catalog_id` in the spec inherits a tutorial_interactables.json entry
## (the explicit spec wins over the catalog).
##
## When game_state is null (standalone previews / showcase), the node is spawned
## unbound and falls back to its @export fields.

const INTERACTABLE_SCENE := preload("res://scenes/game/interactable.tscn")

static func spawn(
	game_state,
	parent: Node3D,
	id: String,
	spec: Dictionary,
	scheduler = null,
	dialogue_box: Node = null,
	active_character := ""
) -> Node:
	var merged := _merge_catalog(spec)
	merged["id"] = id
	if game_state != null:
		game_state.register_interactable(merged)

	var node := INTERACTABLE_SCENE.instantiate()
	node.name = id
	var pos_raw: Variant = merged.get("position", Vector3.ZERO)
	node.position = GameEvent.arr_to_v3(pos_raw) if pos_raw is Array else pos_raw
	if merged.has("description"):
		node.description = String(merged["description"])
	node.dialogue_box = dialogue_box
	node.active_character = active_character
	# Keep the catalog id on the node so its _ready still applies the catalog spec
	# (the established behavior path), and code/tests reading interactable_id work.
	var catalog_id := String(spec.get("catalog_id", ""))
	if catalog_id != "":
		node.interactable_id = catalog_id
	if game_state != null:
		node.bind_data(game_state, id)
	if scheduler != null and node.has_method("set_scheduler"):
		node.set_scheduler(scheduler)
	parent.add_child(node)
	return node

## Merge a catalog entry (if catalog_id set), translating its key names to the
## data-layer schema. The explicit spec WINS (it carries instance-specific values
## like a cycling zone's one_shot=false); the catalog only fills keys the caller
## left unset (e.g. a drink machine's interaction_enabled=false default).
static func _merge_catalog(spec: Dictionary) -> Dictionary:
	var out := spec.duplicate(true)
	var catalog_id := String(spec.get("catalog_id", ""))
	if catalog_id == "" or not InteractableCatalog.has_spec(catalog_id):
		return out
	var cat := InteractableCatalog.get_spec(catalog_id)
	if not out.has("requires_hold") and cat.has("interactable_type"):
		out["requires_hold"] = str(cat["interactable_type"]) == "HOLD_ACTION"
	if not out.has("hold_time") and cat.has("dwell_time"):
		out["hold_time"] = float(cat["dwell_time"])
	if not out.has("one_shot") and cat.has("one_shot"):
		out["one_shot"] = bool(cat["one_shot"])
	if not out.has("enabled") and cat.has("interaction_enabled"):
		out["enabled"] = bool(cat["interaction_enabled"])
	if not out.has("tutorial_label"):
		if cat.has("tutorial_label_key"):
			out["tutorial_label"] = DialogueData.text(str(cat["tutorial_label_key"]))
		elif cat.has("tutorial_label"):
			out["tutorial_label"] = str(cat["tutorial_label"])
	return out
