extends SceneTree

## Focused anti-abstraction regression for generated-stretch interactions.
##
## Proves that old nested/two-click metadata is inert, prose cannot choose causal
## endpoints, only implemented runtime handlers receive feedback presenters, and
## generated links use the preview host's shared party-perception union.

const CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const CHUNK_SCRIPT_PATH := "res://scripts/fragments/chunks/generated_stretch_chunk.gd"
const RUNTIME_REGISTRY := preload(
	"res://scripts/generation/generated_node_runtime_registry.gd"
)
const SPEC_PATH := (
	"res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"
)
const WALK_PROXY_TEXT := "PROXY WALK PROSE MUST NOT RENDER"
const WALK_PROXY_REF := "legacy:walk:proxy"


class PerceptionHost:
	extends ChunkHostStub

	var party_perception_allowed := false
	var party_perception_queries := 0

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)

	func can_party_perceive_feedback_link(
		_source_world: Vector3, _target_world: Vector3
	) -> bool:
		party_perception_queries += 1
		return party_perception_allowed


var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var chunk_source := _read_text(CHUNK_SCRIPT_PATH)
	check(
		not chunk_source.contains("Generated_walk_")
		and not chunk_source.contains('node.get("walk_element"')
		and not chunk_source.contains('node.get("walk_ref"'),
		"generated chunk source has no node-prose walk object or floating-label presenter"
	)
	check(
		not chunk_source.contains("PortalPad.new(")
		and not chunk_source.contains("CrawlTunnel.new(")
		and not chunk_source.contains("Flure.new("),
		"generated chunk cannot construct portal, crawl, or flure mechanics from prose"
	)
	var spec := _load_spec()
	var probe := _mutate_truth_probe(spec)
	check(not probe.is_empty(), "teaching fixture exposes physical and layout-only probe nodes")
	if probe.is_empty():
		_finish()
		return

	var pair := await _boot_pair(spec)
	var host: PerceptionHost = pair.host
	var chunk: Node = pair.chunk
	var physical_node_id := str(probe.get("physical_node_id", ""))
	var layout_node_id := str(probe.get("layout_node_id", ""))

	var preview: Dictionary = chunk.call("get_preview_state")
	var authority: Dictionary = chunk.call("_generated_runtime_authority_state")
	check(
		not preview.has("prepared_nested_nodes")
		and not (preview.get("generation", {}) as Dictionary).has("prepared_nested_nodes")
		and not authority.has("prepared_nested_nodes"),
		"preview and save authority no longer emit legacy nested preparation state"
	)
	check(
		_count_nodes_with_prefix(chunk, "Generated_nested_") == 0
		and _count_nodes_with_meta(chunk, "generated_nested_support_state") == 0,
		"nested archetype metadata creates no purple support cubes or presenter state"
	)
	check(
		_count_nodes_with_prefix(chunk, "Generated_walk_") == 0
		and _count_labels_with_text(chunk, WALK_PROXY_TEXT) == 0
		and _count_labels_containing(chunk, WALK_PROXY_REF) == 0,
		"walk composition metadata creates no blue proxy object or floating prose label"
	)
	var content_registry := chunk.get("_node_content_nodes") as Dictionary
	var nested_registry_entries := 0
	for categories_v in content_registry.values():
		if categories_v is Dictionary:
			nested_registry_entries += ((categories_v as Dictionary).get("nested", []) as Array).size()
	check(
		nested_registry_entries == 0,
		"nested metadata never enters the runtime content endpoint registry"
	)

	var interaction_map := chunk.get("_node_interactables") as Dictionary
	var section_states := chunk.get("_generated_section_states") as Dictionary
	check(
		not interaction_map.has(layout_node_id)
		and not section_states.has(layout_node_id),
		"layout-only prose and nested metadata cannot manufacture an interaction or feedback state"
	)
	var layout_node: Dictionary = chunk.call("_find_node", layout_node_id)
	check(
		str(chunk.call("_runtime_handler_for_node", layout_node)) == ""
		and not bool(chunk.call("activate_generated_node", layout_node_id, "aster"))
		and not bool(chunk.call("_headless_activate_generated_node", layout_node_id))
		and not (chunk.get("_completed_nodes") as Array).has(layout_node_id),
		"portal/crawl/flure prose cannot forge handler provenance or generated progress"
	)
	check(
		_count_forged_mechanism_nodes(chunk) == 0
		and int(chunk.get("_omitted_content_count")) >= 3,
		"unbound portal/crawl/flure placements are omitted instead of represented by proxy geometry"
	)
	check(
		not section_states.has("node_04"),
		"authored hydraulic spillway does not receive a second generic node transition"
	)

	var exact_state: Dictionary = chunk.call(
		"get_generated_section_state", physical_node_id
	)
	var expected_handler := str(
		chunk.call("_runtime_handler_for_node", chunk.call("_find_node", physical_node_id))
	)
	check(
		str(exact_state.get("runtime_handler", "")) == expected_handler
		and str(exact_state.get("runtime_binding_id", "")).strip_edges() != ""
		and str(exact_state.get("source_name", "")) == "GeneratedNode_%s" % physical_node_id
		and str(exact_state.get("target_name", ""))
		== "GeneratedPartyEndpoint_%s" % physical_node_id,
		"physical feedback resolves from the exact interactable to the exact carrier endpoint"
	)
	check(
		not exact_state.has("target_base_scale")
		and not exact_state.has("target_base_material"),
		"feedback state owns no generic mesh-scale or recolor transition"
	)
	var cause: Node3D = chunk.call(
		"_generated_section_cause_target",
		physical_node_id,
		"mutated enemy prose",
		"enemies"
	)
	var effect: Node3D = chunk.call(
		"_generated_section_effect_target",
		physical_node_id,
		"mutated fake gate prose",
		"structures"
	)
	check(
		cause != null
		and cause.name == "GeneratedNode_%s" % physical_node_id
		and effect != null
		and effect.name == "GeneratedPartyEndpoint_%s" % physical_node_id,
		"mutated semantic roles cannot redirect exact handler-owned endpoints"
	)

	var generated_links := chunk.get("_generated_section_links") as Dictionary
	var link: Node = generated_links.get(physical_node_id, null)
	check(link != null, "physical runtime binding owns one generated feedback link")
	if link != null:
		var query: Callable = link.get("_visibility_query")
		check(
			not query.is_null()
			and query.get_object() == host
			and str(query.get_method()) == "can_party_perceive_feedback_link",
			"generated feedback uses the host's shared party-perception union"
		)
		link.call("set_planning_active", true)
		var hidden_state: Dictionary = link.call("get_feedback_state")
		check(
			not bool(hidden_state.get("perception_allowed", true))
			and host.party_perception_queries > 0,
			"unperceived generated endpoints stay hidden even during planning"
		)
		host.party_perception_allowed = true
		link.call("set_planning_active", true)
		var visible_state: Dictionary = link.call("get_feedback_state")
		check(
			bool(visible_state.get("perception_allowed", false)),
			"any party-union perception result can reveal the exact relationship"
		)
		check(
			str(visible_state.get("owner_character", "")) == "aster"
			and (visible_state.get("mode_tint", Color.BLACK) as Color).is_equal_approx(
				Color(0.29, 0.62, 1.0)
			),
			"generated relationship color belongs to its servicing character register"
		)

	var legacy_record := authority.duplicate(true)
	legacy_record["prepared_nested_nodes"] = {
		physical_node_id: {
			"prepared_state": "physical_payload_supported",
			"nested_ref": "legacy:purple-cube",
		},
		layout_node_id: {"prepared_state": "invented_action"},
	}
	var legacy_completed := (legacy_record.get("completed_nodes", []) as Array).duplicate()
	legacy_completed.append(layout_node_id)
	legacy_record["completed_nodes"] = legacy_completed
	host.game_state.set_world_state(
		str(chunk.call("_generated_runtime_authority_key")), legacy_record
	)
	chunk.call("on_game_state_snapshot_restored")
	check(
		not (chunk.call("_generated_runtime_authority_state") as Dictionary).has(
			"prepared_nested_nodes"
		)
		and _count_nodes_with_prefix(chunk, "Generated_nested_") == 0
		and (chunk.call("get_generated_section_state", layout_node_id) as Dictionary).is_empty(),
		"legacy nested/completed keys cannot resurrect presentation without an exact runtime binding"
	)

	check(
		_trigger_chunk_source(
			host,
			chunk,
			chunk.get("_hydraulic_first_control") as Node,
			"aster"
		),
		"authored hydraulic prerequisite is established before testing its physical source"
	)
	var raw_state := chunk.get("_generated_section_states") as Dictionary
	var target: Node3D = (raw_state[physical_node_id] as Dictionary).get(
		"target", null
	) as Node3D
	var target_scale_before := target.scale if target != null else Vector3.ZERO
	var activated := _trigger_chunk_source(
		host,
		chunk,
		interaction_map.get(physical_node_id, null) as Node,
		"aster"
	)
	var completed: Dictionary = chunk.call(
		"get_generated_section_state", physical_node_id
	)
	check(
		activated
		and (chunk.get("_completed_nodes") as Array).has(physical_node_id)
		and str(completed.get("state", "")) == "complete"
		and not str(chunk.call("get_preview_state").get("last_outcome", "")).begins_with(
			"nested_prepared:"
		),
		"one real pickup interaction completes a legacy-nested payload node"
	)
	check(
		target != null and target.scale.is_equal_approx(target_scale_before),
		"completion leaves the exact feedback endpoint's geometry unchanged"
	)
	var item_id := str(
		(chunk.get("_generated_resource_item_by_node") as Dictionary).get(
			physical_node_id, ""
		)
	)
	check(
		item_id != ""
		and (host.game_state.get_hand_items("aster") as Array).has(item_id),
		"the one interaction's consequence is the exact physical item in the exact actor's hand"
	)
	check(
		not (chunk.call("_generated_runtime_authority_state") as Dictionary).has(
			"prepared_nested_nodes"
		),
		"post-interaction authority remains free of the ignored legacy key"
	)

	host.queue_free()
	await process_frame
	_finish()


func _load_spec() -> Dictionary:
	var file := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _mutate_truth_probe(spec: Dictionary) -> Dictionary:
	if spec.is_empty():
		return {}
	var spec_id := str(spec.get("id", ""))
	var nodes: Array = spec.get("nodes", [])
	var physical_node_id := ""
	var layout_node_id := ""
	for index in range(nodes.size()):
		if not (nodes[index] is Dictionary):
			continue
		var node := (nodes[index] as Dictionary).duplicate(true)
		var handler_id := RUNTIME_REGISTRY.handler_for_node(node, spec_id)
		if (
			physical_node_id == ""
			and handler_id in [
				RUNTIME_REGISTRY.HANDLER_PHYSICAL_LYSATE,
				RUNTIME_REGISTRY.HANDLER_PHYSICAL_PAYLOAD,
			]
		):
			physical_node_id = str(node.get("id", ""))
			node["nested_archetypes"] = [{
				"id": "legacy_nested_probe",
				"ref": "legacy:nested:probe",
				"host_step": 0,
			}]
			var section := (node.get("playable_section", {}) as Dictionary).duplicate(true)
			section["source_role"] = "fake enemy chosen by prose"
			section["source_category"] = "enemies"
			section["effect_role"] = "fake gate chosen by prose"
			section["effect_category"] = "structures"
			node["playable_section"] = section
			node["walk_element"] = WALK_PROXY_TEXT
			node["walk_ref"] = WALK_PROXY_REF
			node["walk_index"] = 0
			node["walk_step_index"] = 0
			node.erase("content_placements")
		elif (
			layout_node_id == ""
			and handler_id == ""
			and str(node.get("role", "")) not in ["boundary", "entry"]
		):
			layout_node_id = str(node.get("id", ""))
			node["nested_archetypes"] = [{
				"id": "legacy_layout_probe",
				"ref": "legacy:layout:probe",
				"host_step": 1,
			}]
			node["walk_element"] = WALK_PROXY_TEXT
			node["walk_ref"] = WALK_PROXY_REF
			node["walk_index"] = 1
			node["walk_step_index"] = 3
			node["playable_section"] = {
				"predicted_effect": (
					"Prose claims a flure opens a portal into a crawl tunnel."
				),
				"completed_preview": "Prose claims all three traversal mechanisms fired.",
				"source_role": "fake flure",
				"source_category": "flora",
				"effect_role": "fake portal and crawl tunnel",
				"effect_category": "structures",
			}
			node["content_placements"] = [
				{
					"category": "flora",
					"id": "flure",
					"position": node.get("position", []),
					"size": [0.8, 0.8, 0.8],
				},
				{
					"category": "structures",
					"id": "portal_pad",
					"position": node.get("position", []),
					"size": [1.0, 0.2, 1.0],
				},
				{
					"category": "structures",
					"id": "crawl_tunnel",
					"position": node.get("position", []),
					"size": [1.2, 1.2, 1.2],
				},
			]
		nodes[index] = node
	spec["nodes"] = nodes
	if physical_node_id == "" or layout_node_id == "":
		return {}
	return {
		"physical_node_id": physical_node_id,
		"layout_node_id": layout_node_id,
	}


func _boot_pair(spec: Dictionary) -> Dictionary:
	var host := PerceptionHost.new()
	host.setup()
	root.add_child(host)
	var chunk := CHUNK_SCENE.instantiate()
	chunk.configure_chunk({
		"spec": spec,
		"spiral": false,
		"branches": false,
		"game_mode": "neutral",
		"food_test": "neutral",
	})
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	host.game_state.grid = host.grid
	chunk.call("reset_preview_state")
	await process_frame
	return {"host": host, "chunk": chunk}


func _trigger_chunk_source(
	host: PerceptionHost, chunk: Node, source: Node, actor: String
) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	var source_position: Variant = chunk.call(
		"_generated_interaction_data_position", source
	)
	if not (source_position is Vector3):
		return false
	host.game_state.snap_character_to(actor, source_position as Vector3)
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _count_forged_mechanism_nodes(root_node: Node) -> int:
	var count := (
		1
		if root_node is PortalPad or root_node is CrawlTunnel or root_node is Flure
		else 0
	)
	for child in root_node.get_children():
		if child is Node:
			count += _count_forged_mechanism_nodes(child)
	return count


func _count_nodes_with_prefix(root_node: Node, prefix: String) -> int:
	var count := 1 if str(root_node.name).begins_with(prefix) else 0
	for child in root_node.get_children():
		if child is Node:
			count += _count_nodes_with_prefix(child, prefix)
	return count


func _count_nodes_with_meta(root_node: Node, meta_name: String) -> int:
	var count := 1 if root_node.has_meta(meta_name) else 0
	for child in root_node.get_children():
		if child is Node:
			count += _count_nodes_with_meta(child, meta_name)
	return count


func _count_labels_with_text(root_node: Node, expected: String) -> int:
	var count := 0
	if root_node is Label3D and (root_node as Label3D).text == expected:
		count = 1
	for child in root_node.get_children():
		if child is Node:
			count += _count_labels_with_text(child, expected)
	return count


func _count_labels_containing(root_node: Node, fragment: String) -> int:
	var count := 0
	if root_node is Label3D and (root_node as Label3D).text.contains(fragment):
		count = 1
	for child in root_node.get_children():
		if child is Node:
			count += _count_labels_containing(child, fragment)
	return count


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		push_error("  FAIL  %s" % label)


func _finish() -> void:
	print(
		"GENERATED INTERACTION TRUTH: %d/%d checks passed"
		% [_checks - _failures, _checks]
	)
	quit(0 if _failures == 0 else 1)
