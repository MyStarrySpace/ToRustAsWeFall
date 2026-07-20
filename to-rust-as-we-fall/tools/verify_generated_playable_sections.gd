extends SceneTree

const Generator := preload("res://scripts/generation/stretch_generator.gd")
const ChunkScene := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")

var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var spec: Dictionary = Generator.generate({
		"id": "verify_generated_playable_sections",
		"seed": 61423,
		"complexity_tier": "standard",
		"progression_stage": 2,
		"limitations": {
			"required": {"archetypes": ["1", "2"]},
			"allowed": {"archetypes": ["1", "2", "11", "15"]},
		},
	})
	_check(bool(spec.get("success", false)), "representative systems stretch generates")
	if not bool(spec.get("success", false)):
		_finish()
		return

	var playable_node_ids: Array[String] = []
	var completed_previews := {}
	for raw_node in spec.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node := raw_node as Dictionary
		if str(node.get("role", "")) in ["boundary", "shelter_arrival"]:
			continue
		var node_id := str(node.get("id", ""))
		var section: Dictionary = node.get("playable_section", {})
		_check(str(section.get("schema", "")) == "trawf_playable_section_v1",
			"%s emits a playable micro-section contract" % node_id)
		_check((section.get("interacting_systems", []) as Array).size() >= 2,
			"%s composes at least two named systems" % node_id)
		_check(str(section.get("predicted_effect", "")).strip_edges() != "",
			"%s predicts its concrete click consequence" % node_id)
		_check(str(section.get("completed_preview", "")).strip_edges() != "",
			"%s names the persistent result after commitment" % node_id)
		_check(str(section.get("source_category", "")).strip_edges() != ""
			and str(section.get("effect_category", "")).strip_edges() != "",
			"%s binds its causal roles to runtime actor categories" % node_id)
		completed_previews[node_id] = str(section.get("completed_preview", ""))
		playable_node_ids.append(node_id)

	var local_links := 0
	for raw_link in spec.get("systems_contract", {}).get("causal_links", []):
		if raw_link is Dictionary and str((raw_link as Dictionary).get("kind", "")) == "intervention_effect":
			local_links += 1
	_check(local_links == playable_node_ids.size(),
		"every playable section emits one local cause-to-effect edge")

	var chunk = ChunkScene.instantiate()
	chunk.configure_chunk({"spec": spec, "spiral": false, "branches": false})
	root.add_child(chunk)
	chunk.call("_build_chunk")
	await process_frame

	var interaction_map: Dictionary = chunk.get("_node_interactables")
	for node_id in playable_node_ids:
		var state: Dictionary = chunk.call("get_generated_section_state", node_id)
		_check(not state.is_empty() and str(state.get("target_name", "")) != "",
			"%s resolves its causal edge to a visible local target" % node_id)
		var interactable = interaction_map.get(node_id, null)
		_check(interactable != null and str(interactable.call("get_action_preview")).strip_edges() != "",
			"%s hover exposes action plus predicted consequence" % node_id)

	# Drive the same progression order the player sees. The runtime must move each
	# affected endpoint from predicted to complete, not only append a checkpoint id.
	for node_id in playable_node_ids:
		var activated := bool(chunk.call("_headless_activate_generated_node", node_id))
		_check(activated, "%s executes its generated section transition" % node_id)
		var completed: Dictionary = chunk.call("get_generated_section_state", node_id)
		_check(str(completed.get("state", "")) == "complete"
			and str(completed.get("observed_effect", "")).strip_edges() != "",
			"%s records an observable before-to-after target state" % node_id)
		var completed_interactable = interaction_map.get(node_id, null)
		_check(completed_interactable != null
			and str(completed_interactable.call("get_action_verb")) == "REVIEW RESULT"
			and str(completed_interactable.call("get_action_preview")) == str(completed_previews[node_id]),
			"%s hover changes from prediction to the observed result" % node_id)

	var feedback: Dictionary = chunk.call("get_causal_feedback_state")
	_check(int(feedback.get("count", 0)) >= playable_node_ids.size(),
		"runtime instantiates the emitted local causal links")
	chunk.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		failures += 1
		push_error("  FAIL  %s" % label)


func _finish() -> void:
	print("GENERATED PLAYABLE SECTIONS: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)
