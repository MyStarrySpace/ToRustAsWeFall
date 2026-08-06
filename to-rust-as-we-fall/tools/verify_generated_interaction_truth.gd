extends SceneTree

## Focused anti-abstraction regression for generated-stretch interactions.
##
## Proves that old nested/two-click metadata is inert, prose cannot choose causal
## endpoints, only implemented runtime handlers receive feedback presenters, and
## generated links use the preview host's shared party-perception union.

const CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const PREVIEW_SCENE := preload("res://scenes/fragments/fragment_preview.tscn")
const CHUNK_SCRIPT_PATH := "res://scripts/fragments/chunks/generated_stretch_chunk.gd"
const StretchGeneratorScript := preload(
	"res://scripts/generation/stretch_generator.gd"
)
const AgentPlayerInputDriverScript := preload(
	"res://tools/agent_player_input_driver.gd"
)
const PlayerObservationControllerScript := preload(
	"res://scripts/testing/player_observation_controller.gd"
)
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
	var visual_listener_index := chunk_source.find(
		'interactable.call("set_outline_target", target)'
	)
	var consequence_listener_index := chunk_source.find(
		'interactable.interacted.connect(\n\t\tCallable(self, "_on_generated_node_interacted")'
	)
	check(
		visual_listener_index >= 0
		and consequence_listener_index > visual_listener_index,
		"generated sources bind their exact visual result listener before semantic consequence"
	)
	var spec := _load_spec()
	var probe := _mutate_truth_probe(spec)
	check(not probe.is_empty(), "teaching fixture exposes physical and layout-only probe nodes")
	if probe.is_empty():
		_finish()
		return

	# STRUCTURAL FIXTURE QUARANTINE. This stub phase is allowed to construct and
	# restore exact state so it can reject proxy/legacy wiring. It is disposed
	# before the measured player boundary begins; none of its objects, receipts,
	# state, or callbacks can satisfy a Windowed input/observation assertion.
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
	var target_map := chunk.get("_node_targets") as Dictionary
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
	var physical_pick_target := target_map.get(physical_node_id, null) as StaticBody3D
	var physical_pick_shape := (
		physical_pick_target.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if physical_pick_target != null else null
	)
	var physical_pick_box := (
		physical_pick_shape.shape as BoxShape3D
		if physical_pick_shape != null and physical_pick_shape.shape is BoxShape3D
		else null
	)
	check(
		physical_pick_box != null
		and physical_pick_box.size.x <= 1.3501
		and physical_pick_box.size.y <= 0.6201
		and physical_pick_box.size.z <= 1.1201,
		"physical generated pickups use a cradle-local click surface, not the room footprint"
	)
	var physical_marker := (
		(chunk.get("_node_markers") as Dictionary).get(physical_node_id, null)
		as MeshInstance3D
	)
	check(
		physical_pick_target != null
		and physical_marker != null
		and absf(physical_pick_target.global_position.x - physical_marker.global_position.x)
			<= 0.001
		and absf(physical_pick_target.global_position.z - physical_marker.global_position.z)
			<= 0.001
		and absf(
			physical_pick_target.global_position.y
			- physical_marker.global_position.y
			- 0.17
		) <= 0.001,
		"physical generated pickup click surface is centered on its visible cradle"
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
		not (chunk.call("_generated_runtime_authority_state") as Dictionary).has(
			"prepared_nested_nodes"
		),
		"structural restore authority remains free of the ignored legacy key"
	)

	host.queue_free()
	for _frame in range(2):
		await process_frame

	# MEASURED PLAYER BOUNDARY. The quarantined stub above no longer exists. This
	# phase may choose only rendered affordances, issue viewport-local shipped
	# input, and accept only PlayerObservation output captured after real draws.
	check(
		DisplayServer.get_name() != "headless",
		"generated interaction truth requires a real Windowed framebuffer"
	)
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var player_spec := StretchGeneratorScript.canonicalize_spec(
		spec.duplicate(true)
	)
	check(
		bool(StretchGeneratorScript.validate_actionable_interaction_approaches(
			player_spec).get("valid", false)),
		"measured preview fixture has typed reachable interaction approaches"
	)
	var player_pair := await _boot_player_preview(player_spec)
	var player_preview: Node = player_pair.get("preview", null)
	var driver: Node = player_pair.get("driver", null)
	var observer: Node = player_pair.get("observer", null)
	check(
		player_preview != null and driver != null and observer != null,
		"real fragment preview boots with shipped input and presentation-only observation"
	)
	if player_preview == null or driver == null or observer == null:
		if player_preview != null:
			player_preview.queue_free()
		_finish()
		return

	# The authored opening camera emphasis is itself visible production feedback.
	# Let it finish on real frames before asking the player surface for a click.
	await _wait_rendered_seconds(2.35)
	var sluice_run := await _drive_observed_interaction(
		player_preview, driver, observer, "OPEN FIRST SLUICE", 14.0
	)
	check(
		bool(sluice_run.get("source_affordance_visible_before_click", false))
		and bool(sluice_run.get("exact_pointer_receipt", false))
		and bool(sluice_run.get("exact_visible_success", false)),
		"authored hydraulic prerequisite is reached and opened through its rendered pointer surface"
	)
	# Opening the sluice focuses the actual cistern consequence. Wait for that
	# visible camera beat rather than advancing the scheduler through a test seam.
	await _wait_rendered_seconds(1.55)
	var physical_action := str(probe.get("physical_action", "TAKE LYSATE"))
	var pickup_run := await _drive_observed_interaction(
		player_preview, driver, observer, physical_action, 18.0
	)
	var success_cue: Dictionary = pickup_run.get("success_cue", {})
	var pickup_receipt: Dictionary = pickup_run.get("receipt", {})
	var before_observation: Dictionary = pickup_run.get("before_observation", {})
	var success_observation: Dictionary = pickup_run.get("success_observation", {})
	var source_token := str(pickup_run.get("source_token", ""))
	check(
		bool(pickup_run.get("source_affordance_visible_before_click", false)),
		"generated pickup is visibly enabled before the player clicks it"
	)
	check(
		bool(pickup_run.get("exact_pointer_receipt", false))
		and bool(pickup_receipt.get("accepted", false))
		and str(pickup_receipt.get("expected_target_token", "")) == source_token,
		"generated pickup has one exact shipped RMB receipt bound to its observed token"
	)
	check(
		bool(pickup_run.get("exact_visible_success", false))
		and str(success_cue.get("source_token", "")) == source_token
		and str(success_cue.get("result", "")) == "success"
		and bool(success_cue.get("visible", false)),
		"PlayerObservation captures a newer framebuffer-visible success on the exact source token"
	)
	check(
		_find_affordance_by_token(success_observation, source_token).is_empty(),
		"the retained exact-token success stays visible after the one-shot affordance disables"
	)
	check(
		not _observation_hands_contain(before_observation, "LYSATE")
		and _observation_hands_contain(success_observation, "LYSATE"),
		"the same observed interaction visibly puts the exact lysate consequence in Aster's hand"
	)

	player_preview.queue_free()
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
	var physical_action := ""
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
			physical_action = str(
				(node.get("playable_section", {}) as Dictionary).get(
					"action", "TAKE LYSATE"
				)
			)
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
		"physical_action": physical_action,
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


func _boot_player_preview(spec: Dictionary) -> Dictionary:
	var preview: Node = PREVIEW_SCENE.instantiate()
	if preview == null:
		return {}
	preview.set("preview_menu", false)
	preview.set("preview_chunk", "generated_stretch")
	preview.set("scene_title_override", "Generated Interaction Truth")
	preview.set("preview_chunk_config", {
		"spec": spec.duplicate(true),
		"spiral": false,
		"branches": false,
		"game_mode": "neutral",
		"food_test": "neutral",
	})
	root.add_child(preview)
	for _frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw

	# Evidence instrumentation quarantine: this empty log is attached before the
	# observation/input baseline. It records commands already produced by the real
	# player boundary and never chooses, executes, or observes a gameplay action.
	var game_state: Variant = preview.get("_game_state")
	if game_state == null:
		preview.queue_free()
		await process_frame
		return {}
	if game_state.event_log == null:
		game_state.event_log = EventLog.new()
	var driver: Node = AgentPlayerInputDriverScript.new()
	driver.name = "AgentPlayerInputDriver"
	preview.add_child(driver)
	driver.call("setup", preview)
	var observer: Node = PlayerObservationControllerScript.new()
	observer.name = "PlayerObservationController"
	preview.add_child(observer)
	observer.call("setup", preview)
	await process_frame
	await RenderingServer.frame_post_draw
	return {"preview": preview, "driver": driver, "observer": observer}


func _drive_observed_interaction(
	_preview: Node,
	driver: Node,
	observer: Node,
	expected_verb: String,
	timeout_seconds: float
	) -> Dictionary:
	var discovery := await _find_visible_affordance_with_recovery(
		driver, observer, expected_verb
	)
	var before_observation: Dictionary = discovery.get("observation", {})
	var affordance: Dictionary = discovery.get("affordance", {})
	if affordance.is_empty():
		print("  INFO  no observed affordance containing '%s'; visible=%s" % [
			expected_verb,
			str(_visible_interaction_verbs(before_observation)),
		])
		return {"before_observation": before_observation}
	var source_token := str(affordance.get("token", ""))
	var baseline_result := _find_target_result(before_observation, source_token)
	var baseline_serial := int(baseline_result.get("presentation_serial", 0))

	var selection_v: Variant = await driver.call("select_single", "aster")
	var selection := selection_v as Dictionary if selection_v is Dictionary else {}
	if not bool(selection.get("accepted", false)):
		return {
			"source_affordance_visible_before_click": true,
			"source_token": source_token,
			"before_observation": before_observation,
		}
	var selected_observation := await _capture_rendered_observation(observer)
	var revalidated := _find_affordance_by_token(
		selected_observation, source_token
	)
	if revalidated.is_empty():
		return {
			"source_affordance_visible_before_click": true,
			"source_token": source_token,
			"before_observation": before_observation,
		}
	var screen := revalidated.get("screen", []) as Array
	if screen.size() != 2:
		return {
			"source_affordance_visible_before_click": true,
			"source_token": source_token,
			"before_observation": selected_observation,
		}
	var point := Vector2(float(screen[0]), float(screen[1]))
	driver.call("clear_receipts")
	var receipt_v: Variant = await driver.call(
		"interact_selected_screen", "aster", point
	)
	var receipt := receipt_v as Dictionary if receipt_v is Dictionary else {}
	# Capture one actually drawn frame before pointer hygiene or a timed walk can
	# advance far enough to expire a short exact-target result.
	var immediate := await _capture_rendered_observation(observer)
	if bool(receipt.get("input_issued", false)) and driver.has_method("park_pointer"):
		await driver.call("park_pointer")
	var observed := await _wait_for_visible_target_result(
		observer,
		source_token,
		baseline_serial,
		immediate,
		timeout_seconds
	)
	var success_cue: Dictionary = observed.get("success_cue", {})
	var success_observation: Dictionary = observed.get(
		"observation", immediate
	)
	if driver.has_method("finalize_interaction_receipt"):
		receipt = driver.call(
			"finalize_interaction_receipt",
			receipt,
			success_cue,
			"The exact target did not render a successful interaction receipt.",
			source_token,
			baseline_serial
		)
	var event_kinds: Array = receipt.get("new_event_kinds", [])
	var exact_pointer_receipt := (
		_exact_pointer_receipt_matches(
			receipt,
			point,
			get_root().get_visible_rect(),
			true
		)
		and bool(receipt.get("accepted", false))
		and event_kinds.has("trigger_interactable")
	)
	return {
		"source_affordance_visible_before_click": true,
		"source_token": source_token,
		"before_observation": selected_observation,
		"success_observation": success_observation,
		"success_cue": success_cue,
		"receipt": receipt,
		"exact_pointer_receipt": exact_pointer_receipt,
		"exact_visible_success": (
			str(success_cue.get("source_token", "")) == source_token
			and int(success_cue.get("presentation_serial", 0)) > baseline_serial
			and str(success_cue.get("result", "")) == "success"
			and bool(success_cue.get("visible", false))
		),
	}


func _find_visible_affordance_with_recovery(
	driver: Node, observer: Node, expected_verb: String
	) -> Dictionary:
	var latest: Dictionary = {}
	for attempt in range(9):
		latest = await _capture_rendered_observation(observer)
		var affordance := _find_affordance_by_verb(latest, expected_verb)
		if not affordance.is_empty():
			return {"observation": latest, "affordance": affordance}
		match attempt:
			0:
				await driver.call("recenter")
			1:
				await driver.call("zoom_out", 8)
			2, 3, 4:
				await driver.call("press_key", KEY_D, 8)
			5, 6:
				await driver.call("press_key", KEY_W, 6)
			7:
				await driver.call("press_key", KEY_S, 12)
	return {"observation": latest, "affordance": {}}


func _wait_for_visible_target_result(
	observer: Node,
	source_token: String,
	baseline_serial: int,
	immediate: Dictionary,
	timeout_seconds: float
	) -> Dictionary:
	var latest := immediate
	var elapsed := 0.0
	while elapsed <= timeout_seconds:
		var cue := _find_target_result(latest, source_token)
		if int(cue.get("presentation_serial", 0)) > baseline_serial \
				and str(cue.get("result", "")) == "success" \
				and bool(cue.get("visible", false)):
			return {"observation": latest, "success_cue": cue}
		var step := minf(0.08, timeout_seconds - elapsed)
		if step <= 0.0:
			break
		await create_timer(step, true, false, false).timeout
		await RenderingServer.frame_post_draw
		var snapshot_v: Variant = observer.call("snapshot")
		if snapshot_v is Dictionary:
			latest = snapshot_v as Dictionary
		elapsed += step
	return {"observation": latest, "success_cue": {}}


func _capture_rendered_observation(observer: Node) -> Dictionary:
	await process_frame
	await RenderingServer.frame_post_draw
	var snapshot_v: Variant = observer.call("snapshot")
	return snapshot_v as Dictionary if snapshot_v is Dictionary else {}


func _wait_rendered_seconds(duration: float) -> void:
	var remaining := maxf(0.0, duration)
	while remaining > 0.0001:
		var step := minf(0.1, remaining)
		await create_timer(step, true, false, false).timeout
		await RenderingServer.frame_post_draw
		remaining -= step


func _find_affordance_by_verb(
	observation: Dictionary, expected_verb: String
	) -> Dictionary:
	var expected := expected_verb.strip_edges().to_upper()
	for affordance_v in _observation_affordances(observation):
		var affordance := affordance_v as Dictionary
		if str(affordance.get("kind", "")) == "interact" \
				and str(affordance.get("verb", "")).to_upper().contains(expected):
			return affordance.duplicate(true)
	return {}


func _find_affordance_by_token(
	observation: Dictionary, source_token: String
	) -> Dictionary:
	for affordance_v in _observation_affordances(observation):
		var affordance := affordance_v as Dictionary
		if str(affordance.get("kind", "")) == "interact" \
				and str(affordance.get("token", "")) == source_token:
			return affordance.duplicate(true)
	return {}


func _observation_affordances(observation: Dictionary) -> Array:
	var state_v: Variant = observation.get("state", {})
	return (state_v as Dictionary).get("affordances", []) as Array \
		if state_v is Dictionary else []


func _visible_interaction_verbs(observation: Dictionary) -> Array[String]:
	var verbs: Array[String] = []
	for affordance_v in _observation_affordances(observation):
		var affordance := affordance_v as Dictionary
		if str(affordance.get("kind", "")) == "interact":
			verbs.append(str(affordance.get("verb", "")))
	return verbs


func _find_target_result(
	observation: Dictionary, source_token: String
	) -> Dictionary:
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return {}
	var newest: Dictionary = {}
	for cue_v in (state_v as Dictionary).get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) != "interaction_result" \
				or str(cue.get("source_token", "")) != source_token:
			continue
		if int(cue.get("presentation_serial", 0)) \
				> int(newest.get("presentation_serial", 0)):
			newest = cue.duplicate(true)
	return newest


## Independent fail-closed proof for one ordinary shipped RMB click at the
## revalidated, viewport-local observation point. Semantic acceptance remains
## bound separately to the newer exact-token PlayerObservation result.
static func _exact_pointer_receipt_matches(
		receipt: Dictionary,
		expected_point: Vector2,
		viewport_rect: Rect2,
		require_fresh_ledger := false
	) -> bool:
	if not expected_point.is_finite() or not viewport_rect.has_point(expected_point):
		return false
	if str(receipt.get("kind", "")) != "interact":
		return false
	var screen_point_v: Variant = receipt.get("screen_point", null)
	if typeof(screen_point_v) != TYPE_VECTOR2 \
			or screen_point_v != expected_point:
		return false
	var issued_v: Variant = receipt.get("input_issued", null)
	if typeof(issued_v) != TYPE_BOOL or not bool(issued_v):
		return false
	var before_v: Variant = receipt.get("input_sequence_before", null)
	var after_v: Variant = receipt.get("input_sequence_after", null)
	var count_v: Variant = receipt.get("input_event_count", null)
	if typeof(before_v) != TYPE_INT or typeof(after_v) != TYPE_INT \
			or typeof(count_v) != TYPE_INT:
		return false
	var before := int(before_v)
	var after := int(after_v)
	if require_fresh_ledger and before != 0:
		return false
	if int(count_v) != 3 or after != before + 3:
		return false
	var events_v: Variant = receipt.get("input_events", null)
	if not (events_v is Array) or (events_v as Array).size() != 3:
		return false
	var events := events_v as Array
	for index in range(events.size()):
		var event_v: Variant = events[index]
		if not (event_v is Dictionary):
			return false
		var event := event_v as Dictionary
		var sequence_v: Variant = event.get("sequence", null)
		var event_issued_v: Variant = event.get("issued", null)
		if typeof(sequence_v) != TYPE_INT \
				or int(sequence_v) != before + index + 1:
			return false
		if typeof(event_issued_v) != TYPE_BOOL or not bool(event_issued_v):
			return false
		if not _receipt_position_matches(event.get("position", null), expected_point):
			return false
	var motion := events[0] as Dictionary
	var motion_mask_v: Variant = motion.get("button_mask", null)
	if str(motion.get("kind", "")) != "pointer_move" \
			or typeof(motion_mask_v) != TYPE_INT or int(motion_mask_v) != 0:
		return false
	if not _exact_pointer_button_event(events[1] as Dictionary, true):
		return false
	return _exact_pointer_button_event(events[2] as Dictionary, false)


static func _exact_pointer_button_event(
		event: Dictionary, expected_pressed: bool
	) -> bool:
	if str(event.get("kind", "")) != "pointer_button":
		return false
	var button_v: Variant = event.get("button", null)
	var pressed_v: Variant = event.get("pressed", null)
	var shift_v: Variant = event.get("shift", null)
	var double_click_v: Variant = event.get("double_click", null)
	var mask_v: Variant = event.get("button_mask", null)
	if typeof(button_v) != TYPE_INT or int(button_v) != MOUSE_BUTTON_RIGHT:
		return false
	if typeof(pressed_v) != TYPE_BOOL or bool(pressed_v) != expected_pressed:
		return false
	if typeof(shift_v) != TYPE_BOOL or bool(shift_v):
		return false
	if typeof(double_click_v) != TYPE_BOOL or bool(double_click_v):
		return false
	var expected_mask := MOUSE_BUTTON_MASK_RIGHT if expected_pressed else 0
	return typeof(mask_v) == TYPE_INT and int(mask_v) == expected_mask


static func _receipt_position_matches(position_v: Variant, expected: Vector2) -> bool:
	if not (position_v is Array) or (position_v as Array).size() != 2:
		return false
	var position := position_v as Array
	var x_v: Variant = position[0]
	var y_v: Variant = position[1]
	if typeof(x_v) not in [TYPE_INT, TYPE_FLOAT] \
			or typeof(y_v) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var x := float(x_v)
	var y := float(y_v)
	return is_finite(x) and is_finite(y) \
		and x == expected.x and y == expected.y


func _observation_hands_contain(
	observation: Dictionary, expected_fragment: String
	) -> bool:
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return false
	var hud_v: Variant = (state_v as Dictionary).get("hud", {})
	if not (hud_v is Dictionary):
		return false
	for label_v in (hud_v as Dictionary).get("hands", []):
		if str(label_v).to_upper().contains(expected_fragment.to_upper()):
			return true
	return false


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
