extends SceneTree

const GeneratedStretchChunkScript := preload(
	"res://scripts/fragments/chunks/generated_stretch_chunk.gd"
)
const ChunkHostStubScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const RuntimeRegistryScript := preload(
	"res://scripts/generation/generated_node_runtime_registry.gd"
)
const StretchReplayBuilderScript := preload(
	"res://scripts/generation/stretch_replay_builder.gd"
)
const PlaytestLoopScript := preload(
	"res://scripts/generation/stretch_generation_playtest_loop.gd"
)

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		_failures.append(message)
		push_error("[FAIL] %s" % message)


func _run() -> void:
	var host := ChunkHostStubScript.new()
	host.setup(false)
	root.add_child(host)
	var chunk := GeneratedStretchChunkScript.new()
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	await process_frame
	await process_frame

	# Newly generated specs obey the same boundary before they are serialized: only
	# bound content receives a spatial placement, while every requested unbound noun
	# is preserved as a diagnostic rather than a player-facing object.
	var generation_settings: Dictionary = (
		chunk.get_generation_spec().get("settings", {}) as Dictionary
	).duplicate(true)
	generation_settings["id"] = "generated_content_realization_probe"
	var generated := StretchGeneratorScript.generate(generation_settings)
	_check(bool(generated.get("success", false)),
		"the content-realization probe generates a valid stretch")
	var requested_omissions := {}
	var generated_real_placement_count := 0
	for generated_node_v in generated.get("nodes", []):
		if not (generated_node_v is Dictionary):
			continue
		var generated_node := generated_node_v as Dictionary
		for category in ["flora", "enemies", "structures"]:
			for content_id_v in generated_node.get(category, []):
				var content_id := str(content_id_v)
				if not RuntimeRegistryScript.generated_content_is_realized(category, content_id):
					requested_omissions["%s:%s" % [category, content_id]] = true
		for placement_v in generated_node.get("content_placements", []):
			if not (placement_v is Dictionary):
				continue
			var placement := placement_v as Dictionary
			var category := str(placement.get("category", ""))
			var content_id := str(placement.get("id", ""))
			_check(RuntimeRegistryScript.generated_content_is_realized(category, content_id),
				"new generation emits only runtime-bound content placements")
			generated_real_placement_count += 1
	_check(generated_real_placement_count > 0,
		"new generation retains real reusable kit placements")
	var warned_omissions := {}
	for warning_v in generated.get("validation", {}).get("warnings", []):
		if not (warning_v is Dictionary):
			continue
		var warning := warning_v as Dictionary
		if str(warning.get("reason", "")) == "missing_generated_runtime_binding":
			warned_omissions[
				"%s:%s" % [str(warning.get("category", "")), str(warning.get("id", ""))]
			] = true
	for omission_key in requested_omissions.keys():
		_check(warned_omissions.has(omission_key),
			"new generation reports omitted unbound content %s" % omission_key)

	var projected_content: Array = StretchReplayBuilderScript.build(
		chunk.get_generation_spec()
	).get("level", {}).get("content", [])
	_check(not projected_content.is_empty(),
		"deterministic replay retains runtime-bound content")
	for projected_v in projected_content:
		if not (projected_v is Dictionary):
			continue
		var projected := projected_v as Dictionary
		_check(RuntimeRegistryScript.generated_content_is_realized(
			str(projected.get("category", "")), str(projected.get("kind", ""))
		), "deterministic replay omits old-spec proxy content")
	var animation_layout: Dictionary = PlaytestLoopScript.new()._build_animation_layout(
		chunk.get_generation_spec()
	)
	for animation_node_v in animation_layout.get("nodes", []):
		if not (animation_node_v is Dictionary):
			continue
		for placement_v in (animation_node_v as Dictionary).get("content_placements", []):
			if not (placement_v is Dictionary):
				continue
			var placement := placement_v as Dictionary
			_check(RuntimeRegistryScript.generated_content_is_realized(
				str(placement.get("category", "")), str(placement.get("id", ""))
			), "recorded HTML layout omits old-spec proxy content")

	var expected := {"capbage": 0, "scarpet": 0, "hushbloom": 0}
	for node_v in chunk.get_generation_spec().get("nodes", []):
		if not (node_v is Dictionary):
			continue
		for placement_v in (node_v as Dictionary).get("content_placements", []):
			if not (placement_v is Dictionary):
				continue
			var placement := placement_v as Dictionary
			var key := str(placement.get("id", ""))
			if str(placement.get("category", "")) == "flora" and expected.has(key):
				expected[key] = int(expected[key]) + 1

	var state: Dictionary = chunk.get_preview_state()
	var realized: Dictionary = state.get("generation", {}).get("real_content_counts", {})
	for key in expected.keys():
		_check(int(realized.get(key, -1)) == int(expected[key]),
			"every generated %s placement is a real kit object" % key)

	var runtime_counts := {"capbage": 0, "scarpet": 0, "hushbloom": 0}
	var proxy_label_count := 0
	var dressing_count := 0
	var first_capbage_origin := Vector3.INF
	var first_scarpet_origin := Vector3.INF
	for candidate in chunk.find_children("*", "", true, false):
		if candidate is Capbage:
			runtime_counts["capbage"] = int(runtime_counts["capbage"]) + 1
			var origin: Vector3 = candidate.call("get_concealment_origin")
			if first_capbage_origin == Vector3.INF:
				first_capbage_origin = origin
			_check(bool(candidate.call("conceals", origin)),
				"Capbage keeps its FULL-hide verb in simulation coordinates")
		elif candidate is Scarpet:
			runtime_counts["scarpet"] = int(runtime_counts["scarpet"]) + 1
			var origin: Vector3 = candidate.call("get_concealment_origin")
			if first_scarpet_origin == Vector3.INF:
				first_scarpet_origin = origin
			_check(bool(candidate.call("conceals", origin)),
				"Scarpet keeps its MEDIUM-hide verb in simulation coordinates")
		elif candidate is Hushbloom:
			runtime_counts["hushbloom"] = int(runtime_counts["hushbloom"]) + 1
			_check(
				(candidate.call("get_effect_origin") as Vector3).is_equal_approx(
					candidate.get_meta("generated_simulation_position", Vector3.INF)
				),
				"Hushbloom burst origin remains in the deterministic simulation frame"
			)
			_check(not bool(candidate.get("pickable")) and not bool(candidate.get("interaction_enabled")),
				"generated Hushbloom does not advertise an unimplemented carry lifecycle")
		elif candidate is MeshInstance3D and bool(candidate.get_meta("generated_dressing", false)):
			dressing_count += 1
		elif candidate is MeshInstance3D and bool(candidate.get_meta("generated_content_realized", false)):
			_check(bool(candidate.get_meta("generated_semantic_target", false)),
				"real gameplay visuals may serve as semantic cause/effect targets")
		elif candidate is Label3D and bool(candidate.get_meta("generated_proxy_label", false)):
			proxy_label_count += 1
			var content_id := str(candidate.get_meta("generated_content_id", "")).replace("_", " ")
			_check(not str(candidate.text).to_lower().contains(content_id.to_lower()),
				"proxy label is generic instead of naming '%s'" % content_id)

	for key in runtime_counts.keys():
		_check(int(runtime_counts[key]) == int(expected[key]),
			"scene tree contains the expected real %s count" % key)
	_check(proxy_label_count == 0, "unrealized content produces no proxy labels")
	_check(dressing_count == 0, "unrealized content produces no anonymous stand-in geometry")
	_check(int(state.get("generation", {}).get("unsupported_placeholder_count", -1)) == 0,
		"the playable scene reports zero rendered unsupported placeholders")
	_check(int(state.get("generation", {}).get("omitted_content_count", -1)) == 0,
		"the production fixture no longer carries legacy unbound content debt")

	# The generated cause/effect link picker reads this registry. A generic visual
	# must never remain under its source category or it can be selected as a fake
	# gate, hiding plant, enemy, or junction even when its billboard is anonymous.
	var content_registry_variant: Variant = chunk.get("_node_content_nodes")
	var content_registry: Dictionary = (
		content_registry_variant if content_registry_variant is Dictionary else {}
	)
	var false_semantic_endpoints := 0
	var registered_dressing := 0
	for node_registry_v in content_registry.values():
		if not (node_registry_v is Dictionary):
			continue
		var node_registry := node_registry_v as Dictionary
		for category in ["flora", "enemies", "structures"]:
			for endpoint_v in node_registry.get(category, []):
				if not (endpoint_v is Node) or not is_instance_valid(endpoint_v):
					continue
				if not bool((endpoint_v as Node).get_meta("generated_content_realized", false)):
					false_semantic_endpoints += 1
		for dressing_v in node_registry.get("dressing", []):
			if dressing_v is Node and is_instance_valid(dressing_v):
				registered_dressing += 1
	_check(false_semantic_endpoints == 0,
		"semantic content registry contains no inert named proxies")
	_check(registered_dressing == 0,
		"the content registry contains no dressing stand-ins")
	_check(
		chunk.call(
			"_generated_section_cause_target",
			"node_04",
			"route-captured spillway payload",
			"structures"
		) == null,
		"the decorative shortcut-gate record cannot become a hydraulic cause endpoint"
	)

	# These flora names exist in the palette, but this chunk has no complete reusable
	# runtime binding for their verbs. They must be absent rather than spawning any
	# shape that suggests the advertised effect exists.
	for i in range(3):
		var key: String = ["flure", "seefern", "forget_me_nots"][i]
		var marker: Variant = chunk.call(
			"_add_content_marker",
			{
				"category": "flora",
				"id": key,
				"support": "implemented",
				"shape": "plant_cluster",
			},
			Vector3(96.0 + float(i) * 2.0, 0.7, -12.0),
			Vector3(1.0, 1.1, 1.0),
			Color(0.3, 0.7, 0.4),
			"Generated_flora_%s" % key
		)
		_check(marker == null,
			"unbound %s is omitted instead of advertising a false verb" % key)

	# Generated cover is gameplay state, so the saved fixed scheduler owns the
	# sample boundary. Render/headless frame frequency must not move that boundary.
	host.game_state.snap_character_to("aster", Vector3(5000.0, 0.0, 5000.0))
	var clear_deadline := float(chunk.get("_theme_hazard_next_tick"))
	host.scheduler.advance_ticks(
		maxf(0.0, clear_deadline - float(host.scheduler.get_current_tick()) + 0.000001)
	)
	_check(host.game_state.get_character_concealment("aster") == GameState.CONCEAL_NONE,
		"generated cover cadence establishes a clear baseline")

	host.game_state.snap_character_to("aster", first_capbage_origin)
	var capbage_deadline := float(chunk.get("_theme_hazard_next_tick"))
	await process_frame
	await process_frame
	_check(host.game_state.get_character_concealment("aster") == GameState.CONCEAL_NONE,
		"render frames cannot grant generated Capbage concealment")
	host.scheduler.advance_ticks(
		maxf(0.0, capbage_deadline - float(host.scheduler.get_current_tick()) + 0.000001)
	)
	_check(host.game_state.get_character_concealment("aster") == GameState.CONCEAL_FULL,
		"generated Capbage applies FULL concealment on the saved cadence")

	host.game_state.snap_character_to("aster", first_scarpet_origin)
	var scarpet_deadline := float(chunk.get("_theme_hazard_next_tick"))
	await process_frame
	_check(host.game_state.get_character_concealment("aster") == GameState.CONCEAL_FULL,
		"render frames cannot replace the last sampled cover tier")
	host.scheduler.advance_ticks(
		maxf(0.0, scarpet_deadline - float(host.scheduler.get_current_tick()) + 0.000001)
	)
	_check(host.game_state.get_character_concealment("aster") == GameState.CONCEAL_MEDIUM,
		"generated Scarpet applies MEDIUM concealment on the saved cadence")

	host.free()
	if _failures.is_empty():
		print("Generated content realization verification passed.")
		quit(0)
	else:
		push_error("Generated content realization verification failed: %s" % "; ".join(_failures))
		quit(1)
