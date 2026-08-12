class_name StretchSystemsCurriculum
extends RefCounted

const RuntimeRegistryScript := preload("res://scripts/generation/generated_node_runtime_registry.gd")

## Systems-thinking layer for generated stretches.
##
## The spatial generator answers "where can the party go?". This layer answers the
## separate design question "what model is the player learning and revising?". It
## emits a causal contract, annotates each critical node with one reasoning verb,
## and validates that a generated stretch teaches and later tests at least one
## relationship. Nothing here adds execution padding after the reasoning is done.

const CONTRACT_SCHEMA := "trawf_generated_systems_contract_v1"

## Archetype 9 intentionally stays outside the procedural pool until its broken
## convention has a typed producer -> consumer handshake. Hand-authored setpieces
## can still use it outside this generator.
const PROCEDURALLY_BLOCKED_ARCHETYPES := {
	"9": "Expectation subversion needs an authored, typed convention handshake.",
	"11": "Narrative beats belong to story mode; procedural generation does not author story.",
}

const STAGE_PROFILES := {
	1: {
		"name": "isolated_relation",
		"complexity_rank": 1,
		"reasoning_demand": "identify one cause-and-effect relationship",
		"preferred_dimensions": ["relation"],
		"required_dimensions": ["relation"],
		"required_any_dimensions": [],
		"information_policy": "full_local_read",
		"transfer_required": false,
		"perception_degradation": "none",
	},
	2: {
		"name": "prediction_chain",
		"complexity_rank": 2,
		"reasoning_demand": "predict the effect before intervening",
		"preferred_dimensions": ["delay", "threshold", "relation"],
		"required_dimensions": ["relation"],
		"required_any_dimensions": ["delay", "threshold"],
		"information_policy": "full_local_read",
		"transfer_required": true,
		"perception_degradation": "none",
	},
	3: {
		"name": "stock_and_delay",
		"complexity_rank": 3,
		"reasoning_demand": "track a stock, flow, threshold, or delayed response",
		"preferred_dimensions": ["stock", "flow", "delay", "threshold"],
		"required_dimensions": ["relation"],
		"required_any_dimensions": ["stock", "flow", "delay", "threshold"],
		"information_policy": "local_reads_with_overview_on_pause",
		"transfer_required": true,
		"perception_degradation": "none",
	},
	4: {
		"name": "feedback_and_scale",
		"complexity_rank": 4,
		"reasoning_demand": "anticipate feedback and a local-versus-party cost",
		"preferred_dimensions": ["feedback", "local_global", "delay"],
		"required_dimensions": ["feedback", "local_global"],
		"required_any_dimensions": [],
		"information_policy": "distributed_party_reads",
		"transfer_required": true,
		"perception_degradation": "none",
	},
	5: {
		"name": "leverage_and_topology",
		"complexity_rank": 5,
		"reasoning_demand": "find the leverage point instead of servicing every symptom",
		"preferred_dimensions": ["leverage", "topology", "feedback"],
		"required_dimensions": ["leverage"],
		"required_any_dimensions": ["topology", "feedback"],
		"information_policy": "distributed_party_reads",
		"transfer_required": true,
		"perception_degradation": "none",
	},
	6: {
		"name": "transfer_under_degraded_perception",
		"complexity_rank": 6,
		"reasoning_demand": "transfer the model while one information source is incomplete",
		"preferred_dimensions": ["diagnosis", "transfer", "topology", "leverage"],
		"required_dimensions": ["transfer"],
		"required_any_dimensions": ["diagnosis", "topology"],
		"information_policy": "composite_partial_reads",
		"transfer_required": true,
		"perception_degradation": "one_source_hidden_from_each_character",
	},
}


static func profile_for_stage(stage: int) -> Dictionary:
	return (STAGE_PROFILES[clampi(stage, 1, 6)] as Dictionary).duplicate(true)


static func is_procedurally_eligible(archetype_id: String) -> bool:
	return not PROCEDURALLY_BLOCKED_ARCHETYPES.has(archetype_id)


static func blocked_reason(archetype_id: String) -> String:
	return str(PROCEDURALLY_BLOCKED_ARCHETYPES.get(archetype_id, ""))


static func preferred_archetype_ids(catalog, candidates: Array, stage: int) -> Array[String]:
	var profile := profile_for_stage(stage)
	var result: Array[String] = []
	for raw_id in candidates:
		var id := str(raw_id)
		if not is_procedurally_eligible(id):
			continue
		var model := model_for_archetype(catalog.get_archetype(id), id)
		if _model_matches_profile(model, profile):
			result.append(id)
	return result


## The first non-transition archetype is the stretch's explicit model thread.
## Returning its chain index lets the generator reserve enough reasoning nodes to
## encounter that same model again under a changed variant.
static func focus_chain_index(chain: Array, stage: int = 1) -> int:
	var profile := profile_for_stage(stage)
	for i in range(chain.size()):
		if not (chain[i] is Dictionary):
			continue
		var entry := chain[i] as Dictionary
		if (
			_archetype_can_emit_runtime_node(str(entry.get("id", "")))
			and _dimensions_match_profile(entry.get("systems_dimensions", []), profile)
		):
			return i
	for i in range(chain.size()):
		if (
			chain[i] is Dictionary
			and _archetype_can_emit_runtime_node(str((chain[i] as Dictionary).get("id", "")))
		):
			return i
	return -1


static func _archetype_can_emit_runtime_node(archetype_id: String) -> bool:
	# Shelter rest is attached only to an actual shelter-role node, not every
	# archetype-16 hide slot. The only generic interior archetype with a complete
	# generated-node runtime today is the physical forage cache.
	return archetype_id == "12"


## Grow only when the authored/generated CONTENT needs one later model test. This
## is not stage scaling: stage 6 does not become longer than stage 2 merely for
## being later. The added node is a reasoning beat, never solved-state padding.
static func ensure_reasoning_budget(settings: Dictionary, budget: Dictionary, chain: Array) -> void:
	if chain.is_empty():
		return
	var focus_index := focus_chain_index(chain, int(settings.get("progression_stage", 1)))
	if focus_index < 0:
		return
	var original_node_count := maxi(4, int(budget.get("node_count", 4)))
	var required_node_count := original_node_count
	var optional_count := maxi(0, int(budget.get("optional_node_count", 0)))
	var safety_limit := original_node_count + chain.size() * 3 + 3
	while _critical_focus_occurrences(required_node_count, chain.size(), focus_index, optional_count) < 2 \
			and required_node_count < safety_limit:
		required_node_count += 1
	budget["node_count"] = required_node_count
	settings["reasoning_budget_added_nodes"] = required_node_count - original_node_count


static func build_contract(catalog, nodes: Array, routes: Array, settings: Dictionary) -> Dictionary:
	var stage := int(settings.get("progression_stage", 1))
	var profile := profile_for_stage(stage)
	var spec_id := str(settings.get("id", ""))
	var occurrence_totals := {}
	var actionable_indices: Array[int] = []
	var actionable_node_ids: Array[String] = []
	var layout_only_node_ids: Array[String] = []
	var runtime_output_sources := {}
	for i in range(nodes.size()):
		if not (nodes[i] is Dictionary):
			continue
		var node: Dictionary = nodes[i]
		var handler_id := RuntimeRegistryScript.handler_for_node(node, spec_id)
		# Runtime chain refs are a projection of concrete handler behavior, not a
		# second name for the generator's conceptual chain. Clear stale values first
		# so regenerated specs cannot retain support that the registry removed.
		node.erase("runtime_chain_input_ref")
		node.erase("runtime_chain_output_ref")
		node["runtime_handler"] = handler_id
		node["runtime_support"] = "implemented" if handler_id != "" else "layout_only"
		node["runtime_progression_required"] = handler_id != "" and not bool(node.get("optional", false))
		if handler_id == "":
			# An archetype description may still inform room shape and dressing. It may
			# not masquerade as a mechanic through cursor copy or a metadata-only state
			# flip, and it cannot become a required checkpoint.
			node.erase("action_verb")
			node.erase("prediction_hint")
			node.erase("evidence_hint")
			node.erase("playable_section")
			node.erase("systems_beat")
			layout_only_node_ids.append(str(node.get("id", "")))
			nodes[i] = node
			continue
		var semantic_input := str(node.get("chain_input_ref", ""))
		if (
			semantic_input != ""
			and runtime_output_sources.has(semantic_input)
			and RuntimeRegistryScript.consumes_chain_input(handler_id, node)
		):
			node["runtime_chain_input_ref"] = semantic_input
		var semantic_output := str(node.get("chain_output_ref", ""))
		if (
			semantic_output != ""
			and RuntimeRegistryScript.materializes_chain_output(handler_id, node)
		):
			node["runtime_chain_output_ref"] = semantic_output
			runtime_output_sources[semantic_output] = str(node.get("id", ""))
		node["action_verb"] = RuntimeRegistryScript.initial_action_label(node, handler_id)
		nodes[i] = node
		actionable_indices.append(i)
		actionable_node_ids.append(str(node.get("id", "")))
		var id := handler_id
		if not bool(node.get("optional", false)):
			occurrence_totals[id] = int(occurrence_totals.get(id, 0)) + 1

	var model_order: Array[String] = []
	var model_by_id := {}
	var seen := {}
	var lesson_spine := []
	for node_index in actionable_indices:
		var node: Dictionary = nodes[node_index]
		var handler_id := str(node.get("runtime_handler", ""))
		var archetype_id := str(node.get("archetype_id", ""))
		var model_id := "runtime_%s" % handler_id
		if not model_by_id.has(model_id):
			var model := _model_for_runtime_handler(catalog, node, handler_id)
			model["id"] = model_id
			model["archetype_id"] = archetype_id
			model["archetype_name"] = str(node.get("archetype_name", ""))
			model["runtime_handler"] = handler_id
			model["node_ids"] = []
			model["critical_node_ids"] = []
			model["teach_node"] = ""
			model["test_nodes"] = []
			model_by_id[model_id] = model
			model_order.append(model_id)
		var occurrence := int(seen.get(handler_id, 0))
		var optional := bool(node.get("optional", false))
		if not optional:
			seen[handler_id] = occurrence + 1
		var total := int(occurrence_totals.get(handler_id, 0))
		var beat_name := _beat_name(occurrence, total, optional)
		var model: Dictionary = model_by_id[model_id]
		var node_id := str(node.get("id", ""))
		(model["node_ids"] as Array).append(node_id)
		if not optional:
			(model["critical_node_ids"] as Array).append(node_id)
		if beat_name == "teach" and str(model.get("teach_node", "")) == "":
			model["teach_node"] = node_id
		if beat_name in ["test", "twist", "transfer"]:
			(model["test_nodes"] as Array).append(node_id)
		model_by_id[model_id] = model

		var beat := {
			"model_id": model_id,
			"beat": beat_name,
			"verb": str(model.get("verb", "intervene")),
			"cause": str(model.get("cause", "")),
			"effect": str(model.get("effect", "")),
			"prediction": str(model.get("prediction", "")),
			"intervention": str(model.get("intervention", "")),
			"evidence": str(model.get("evidence", "")),
			"likely_misconception": str(model.get("likely_misconception", "")),
			"changed_condition": str(node.get("variant", "default condition")).replace("_", " "),
			"critical": not bool(node.get("optional", false)),
		}
		node["systems_beat"] = beat
		# Presentation consumes only an implemented handler. Conceptual archetype
		# verbs never cross this boundary until their real lifecycle exists.
		node["action_verb"] = RuntimeRegistryScript.initial_action_label(node, handler_id)
		node["prediction_hint"] = str(beat.get("prediction", ""))
		node["evidence_hint"] = str(beat.get("evidence", ""))
		# A node is not a section merely because it has a coordinate. Preserve the
		# bounded composition the runtime must present: which system the player
		# changes, which system responds, and the observable state transition.
		node["playable_section"] = _playable_section_for_node(node, beat)
		nodes[node_index] = node
		lesson_spine.append({
			"node": node_id,
			"archetype_id": archetype_id,
			"runtime_handler": handler_id,
			"model_id": model_id,
			"beat": beat_name,
			"verb": beat["verb"],
			"critical": beat["critical"],
			"prediction_required": beat_name in ["test", "twist", "transfer"],
			"changed_condition": beat["changed_condition"],
		})

	var models := []
	for model_id in model_order:
		models.append((model_by_id[model_id] as Dictionary).duplicate(true))
	var optional_lesson_spine := []
	var focus_model_id := _focus_model_id(models, profile)
	var focus_matches_profile := false
	for model_v in models:
		if model_v is Dictionary and str((model_v as Dictionary).get("id", "")) == focus_model_id:
			focus_matches_profile = _model_matches_profile(model_v as Dictionary, profile)
			break
	var causal_links := _build_causal_links(nodes, models)
	var reasoning_solved_at := "entry"
	for i in range(actionable_indices.size() - 1, -1, -1):
		var candidate: Dictionary = nodes[actionable_indices[i]]
		if not bool(candidate.get("optional", false)):
			reasoning_solved_at = str(candidate.get("id", reasoning_solved_at))
			break
	var complete_lesson_sequence := lesson_spine.duplicate(true)
	complete_lesson_sequence.append_array(optional_lesson_spine)

	return {
		"schema": CONTRACT_SCHEMA,
		"boundary": "the generated entry-to-shelter route and the states changed inside it",
		"goal": "reach the exit shelter; only implemented handlers may change runtime state",
		"progression_profile": profile,
		"difficulty_dimensions": {
			"reasoning": str(profile.get("reasoning_demand", "")),
			"controls": "constant",
			"camera": "constant",
			"execution_precision": "not used as progression scaling",
			"geometry_density": "controlled by complexity tier, not campaign stage",
		},
		"focus_model_id": focus_model_id,
		"runtime_profile_coverage": focus_matches_profile,
		"runtime_handlers": RuntimeRegistryScript.IMPLEMENTED_HANDLERS.keys(),
		"actionable_nodes": actionable_node_ids,
		"layout_only_nodes": layout_only_node_ids,
		"causal_models": models,
		"lesson_spine": lesson_spine,
		"optional_lesson_spine": optional_lesson_spine,
		"optional_world_actions": optional_world_actions_for_spec(spec_id),
		"optional_world_action_policy": optional_world_action_policy_for_spec(spec_id),
		"causal_links": causal_links,
		"feedback_contract": {
			"failure_cost": "recoverable state setback or bounded pressure",
			"model_error_evidence": "show the predicted relationship and the observed result",
			"input_error_evidence": "show the rejected or mistimed action separately",
			"visibility_policy": "party_visibility_union",
			"critical_reads": "stable_or_recoverable",
		},
		"perception_lock": {
			"where_register": "world causal tell plus affected target",
			"when_register": "before commitment and again on state change",
			"hidden_from_each": str(profile.get("perception_degradation", "none")),
		},
		"reasoning_solved_at": reasoning_solved_at,
		"solved_state_execution_tail_nodes": 1 if not nodes.is_empty() else 0,
		"transfer_test_required": bool(profile.get("transfer_required", false)),
		"transfer_sequence_explicit": _has_explicit_transfer(complete_lesson_sequence, focus_model_id),
		"route_count": routes.size(),
	}


## Ordered authored actions that deterministic replay may execute after loading a
## fixed generated spec. No committed spec carries authored world actions; an
## authored stretch that adds them must also ship the chunk runtime that executes
## each action, or the generated solution would promise moves the game cannot make.
static func world_actions_for_spec(_spec_id: String) -> Array:
	return []


## Optional authored actions are excluded from the headless golden path; they
## describe risk/reward transfer tests layered onto an authored spec. Empty for
## every committed spec, for the same runtime-honesty reason as above.
static func optional_world_actions_for_spec(_spec_id: String) -> Array:
	return []


static func optional_world_action_policy_for_spec(_spec_id: String) -> Dictionary:
	return {}


static func _has_explicit_transfer(lesson_spine: Array, focus_model_id: String) -> bool:
	for raw_beat in lesson_spine:
		if not (raw_beat is Dictionary):
			continue
		var beat := raw_beat as Dictionary
		if str(beat.get("model_id", "")) == focus_model_id \
				and str(beat.get("beat", "")) in ["transfer", "application"]:
			return true
	return false


## Short, concrete copy for an implemented generated-node handler. Returning an
## empty string is intentional: layout-only archetypes have no cursor verb.
static func action_verb_for_node(node: Dictionary) -> String:
	return RuntimeRegistryScript.initial_action_label(node, str(node.get("runtime_handler", "")))


## Convert a semantic beat into a spatial/runtime contract. The interaction is
## deliberately described as a relation between systems, never as "visit point".
## Presentation and tests consume this same contract, so cause/effect copy cannot
## drift away from the state transition the generated chunk performs.
static func _playable_section_for_node(node: Dictionary, beat: Dictionary) -> Dictionary:
	var verb := str(beat.get("verb", "intervene"))
	var handler_id := str(node.get("runtime_handler", ""))
	var node_role := str(node.get("role", ""))
	var has_shelter := (
		node_role in ["shelter", "shelter_arrival"]
		or (node.get("structures", []) as Array).has("shelter")
	)
	if verb == "recover" and not has_shelter:
		verb = "hide"
	var source_role := "control"
	var effect_role := "route"
	var source_category := "structures"
	var effect_category := "structures"
	var relationship_label := "CHANGES"
	match verb:
		"redirect":
			source_role = "committed enemy"
			effect_role = "impact target"
			source_category = "enemies"
			effect_category = "structures"
			relationship_label = "CHARGE HITS"
		"cultivate":
			source_role = "flora"
			effect_role = "fauna" if not (node.get("enemies", []) as Array).is_empty() else "route"
			source_category = "flora"
			effect_category = "enemies" if not (node.get("enemies", []) as Array).is_empty() else "structures"
			relationship_label = "FLORA CHANGES"
		"support":
			source_role = "carried load"
			effect_role = "party mobility"
			source_category = "structures"
			effect_category = "party"
			relationship_label = "LOAD SLOWS"
		"distract":
			source_role = "positioned signal"
			effect_role = "patrol attention"
			source_category = "flora" if not (node.get("flora", []) as Array).is_empty() else "structures"
			effect_category = "enemies"
			relationship_label = "SIGNAL PULLS"
		"coordinate":
			source_role = "paired controls"
			effect_role = "shared route"
			relationship_label = "BOTH UNLOCK"
		"reconstruct":
			source_role = "fragment relation"
			effect_role = "hidden route"
			relationship_label = "RELATION REVEALS"
		"time":
			source_role = "entry phase"
			effect_role = "safe interval"
			relationship_label = "PHASE OPENS"
		"authorize":
			source_role = "authority bearer"
			effect_role = "class gate"
			source_category = "party"
			effect_category = "structures"
			relationship_label = "AUTHORIZES"
		"contain":
			source_role = "nested dependency"
			effect_role = "container state"
			relationship_label = "DEPENDENCY FEEDS"
		"forage":
			source_role = "finite lysate cache"
			effect_role = "carrier hand"
			source_category = "structures"
			effect_category = "party"
			relationship_label = "CACHE FILLS HAND"
		"exploit":
			source_role = "ecology signal"
			effect_role = "enemy pairing"
			source_category = "enemies"
			effect_category = "enemies"
			relationship_label = "SIGNAL COUPLES"
		"stage":
			source_role = "prepared relay"
			effect_role = "crossing capacity"
			source_category = "structures"
			effect_category = "party"
			relationship_label = "RELAY PRESERVES"
		"budget":
			source_role = "lane dose"
			effect_role = "party capacity"
			source_category = "structures"
			effect_category = "party"
			relationship_label = "LANE DRAINS"
		"recover":
			source_role = "banked ATP"
			effect_role = "party recovery"
			source_category = "party"
			effect_category = "party"
			relationship_label = "ATP RESTORES"
		"hide":
			source_role = "secured hide"
			effect_role = "safe regroup state"
			source_category = "structures"
			effect_category = "party"
			relationship_label = "HIDE SHELTERS"
		"recognize":
			source_role = "transition"
			effect_role = "carried state"
			source_category = "structures"
			effect_category = "party"
			relationship_label = "PRESERVES"
		"route":
			source_role = "finite current control"
			effect_role = "selected downstream sink"
			source_category = "structures"
			effect_category = "structures"
			relationship_label = "ONE BRANCH FED"
	if handler_id == RuntimeRegistryScript.HANDLER_CANONICAL_SHELTER_ARRIVAL:
		source_role = "complete conscious party"
		effect_role = "shelter arrival outcome"
		source_category = "party"
		effect_category = "structures"
		relationship_label = "PARTY ENTERS"

	var systems: Array[String] = [source_role, effect_role]
	for input in ["party position", "route topology"]:
		if not systems.has(input):
			systems.append(input)
	var before_state := str(beat.get("likely_misconception", "unchanged route"))
	var after_state := str(beat.get("effect", "changed route"))
	var observable_evidence := str(beat.get("evidence", "the affected target visibly changes"))
	if verb == "forage":
		before_state = "the cache directly refills ATP for the whole party"
		after_state = "one physical lysate occupies one carrier hand until endocytosed"
		observable_evidence = "cache marker clears, the carrier portrait gains lysate, and ATP stays unchanged"
	elif handler_id == RuntimeRegistryScript.HANDLER_CANONICAL_SHELTER_ARRIVAL:
		before_state = "reaching a shelter always spends ATP and instantly refills the party"
		after_state = "the complete conscious party must be inside; only members needing recovery start canonical ATP-paid rest"
		observable_evidence = "the outcome distinguishes started rests from already-full no-charge arrivals"
	elif verb == "hide":
		before_state = "any safe-looking hide provides a full ATP-funded recovery"
		after_state = "the hide secures a regroup point; health and ATP remain unchanged until shelter"
		observable_evidence = "the hide changes to secured while party HP and ATP remain unchanged"
	return {
		"schema": "trawf_playable_section_v1",
		"boundary": "the local room-piece, its route mouths, and the named cause/effect actors",
		"action": str(node.get("action_verb", action_verb_for_node(node))),
		"predicted_effect": _consequence_preview_for_node(node, verb, beat),
		"completed_preview": _completed_preview_for_node(node, verb, beat),
		"source_role": source_role,
		"effect_role": effect_role,
		"source_category": source_category,
		"effect_category": effect_category,
		"relationship_label": relationship_label,
		"before_state": before_state,
		"after_state": after_state,
		"failure_prediction": "If the relation is wrong, the named effect target will not enter the predicted state.",
		"observable_evidence": observable_evidence,
		"interacting_systems": systems,
		"runtime_handler": str(node.get("runtime_handler", "")),
	}


static func _consequence_preview_for_node(node: Dictionary, verb: String, beat: Dictionary) -> String:
	if str(node.get("runtime_handler", "")) == RuntimeRegistryScript.HANDLER_CANONICAL_SHELTER_ARRIVAL:
		return "Completes once the conscious party is inside; starts canonical rest only where recovery is needed"
	if str(node.get("runtime_handler", "")) == RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD:
		return "The exact interacting character takes the visible physical load if they are in range and have a free hand"
	match verb:
		"redirect": return "Redirects the committed charge into the marked impact target"
		"cultivate":
			match str(node.get("variant", "")):
				"hushbloom_stun": return "Stuns the linked fauna after the Hushbloom opens"
				"flure_iron_decoy": return "Pulls the linked patrol toward the Flure's iron signal"
				"climbvine_traversal": return "Grows a traversable Climbvine across the linked route"
			return "Changes the linked fauna or route after the plant readiness tell"
		"support": return "Moves the load but reduces the carrier's mobility"
		"distract": return "Pulls patrol attention away and opens a timed blind region"
		"coordinate": return "Opens the shared route only while both side states align"
		"reconstruct": return "Reveals the route if the fragment relations agree"
		"time": return "Uses the current patrol phase to open a safe crossing interval"
		"authorize": return "Opens the gate only for the matching authority bearer"
		"contain": return "Propagates the nested output into the container and exit"
		"forage": return "Moves one physical lysate into a carrier's hand; ATP changes only after endocytosis"
		"exploit": return "Couples the enemy responses so they vacate the crossing"
		"stage": return "Turns the long attrition run into bounded relay segments"
		"budget": return "Commits the shown dose and drains capacity until the lane clears"
		"recover": return "Spends banked ATP to restore party capacity and reduce debt"
		"hide": return "Secures a regroup point without changing HP or ATP; full recovery still requires shelter"
		"recognize": return "Carries the declared party or world state into the next section"
		"route": return "Feeds the selected sink while the competing branch remains dry"
	var fallback := str(beat.get("effect", "Changes the linked target state")).strip_edges()
	return fallback if fallback.length() <= 110 else fallback.left(107) + "..."


static func _completed_preview_for_node(node: Dictionary, verb: String, beat: Dictionary) -> String:
	if str(node.get("runtime_handler", "")) == RuntimeRegistryScript.HANDLER_CANONICAL_SHELTER_ARRIVAL:
		return "Shelter arrival is complete; needed rests started canonically and already-full members spent no ATP"
	if str(node.get("runtime_handler", "")) == RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD:
		return "The same visible load is now held by the character who took it and remains required for shelter delivery"
	if verb == "cultivate":
		match str(node.get("variant", "")):
			"hushbloom_stun": return "The linked fauna is stunned after the Hushbloom tell"
			"flure_iron_decoy": return "Patrol attention is now pulled toward the Flure"
			"climbvine_traversal": return "The Climbvine now spans the linked route"
	if verb == "support":
		return "The load is staged; its carrier now moves more slowly"
	if verb == "forage":
		return "One carrier now holds the lysate; ATP is unchanged until endocytosis"
	if verb == "hide":
		return "The hide is secured; full recovery remains available only at shelter"
	if verb == "route":
		return "The selected sink is fed and the competing branch remains visibly dry"
	var observed := str(beat.get("effect", "The linked target changed")).strip_edges()
	return observed if observed.length() <= 110 else observed.left(107) + "..."


static func validate_contract(spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var contract: Dictionary = spec.get("systems_contract", {})
	if str(contract.get("schema", "")) != CONTRACT_SCHEMA:
		errors.append("Missing or unsupported generated systems contract.")
		return {"valid": false, "errors": errors}
	for field in ["boundary", "goal", "reasoning_solved_at"]:
		if str(contract.get(field, "")).strip_edges() == "":
			errors.append("Systems contract is missing %s." % field)
	var models: Array = contract.get("causal_models", [])
	var model_ids := {}
	var focus_has_teach := false
	var focus_has_test := false
	var focus_matches_profile := false
	var focus_occurrences := 0
	var profile: Dictionary = contract.get("progression_profile", {})
	for raw_model in models:
		if not (raw_model is Dictionary):
			errors.append("Systems contract contains a non-dictionary causal model.")
			continue
		var model := raw_model as Dictionary
		var model_id := str(model.get("id", ""))
		model_ids[model_id] = true
		for field in ["relationship", "cause", "effect", "polarity", "leverage_point", "likely_misconception", "prediction", "intervention", "evidence", "transfer_test"]:
			if str(model.get(field, "")).strip_edges() == "":
				errors.append("Causal model %s is missing %s." % [model_id, field])
		if model_id == str(contract.get("focus_model_id", "")):
			focus_has_teach = str(model.get("teach_node", "")) != ""
			focus_has_test = not (model.get("test_nodes", []) as Array).is_empty()
			focus_matches_profile = _model_matches_profile(model, profile)
			focus_occurrences = (model.get("critical_node_ids", []) as Array).size()
	var critical_count := 0
	var produced_chain_states := {}
	var spec_id := str(spec.get("id", spec.get("settings", {}).get("id", "")))
	var expected_actionable: Array[String] = []
	var expected_layout_only: Array[String] = []
	for raw_node in spec.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node := raw_node as Dictionary
		var node_id := str(node.get("id", ""))
		var optional := bool(node.get("optional", false))
		var expected_handler := RuntimeRegistryScript.handler_for_node(node, spec_id)
		var declared_handler := RuntimeRegistryScript.declared_handler(node)
		var section: Dictionary = node.get("playable_section", {})
		if expected_handler == "":
			expected_layout_only.append(node_id)
			if declared_handler != "":
				errors.append("Layout-only node %s declares unsupported runtime handler %s." % [node_id, declared_handler])
			if str(node.get("action_verb", "")).strip_edges() != "" or not section.is_empty():
				errors.append("Layout-only node %s exposes an invented interaction." % node_id)
			if bool(node.get("runtime_progression_required", false)):
				errors.append("Layout-only node %s cannot gate progression." % node_id)
			continue
		expected_actionable.append(node_id)
		if declared_handler != expected_handler or not RuntimeRegistryScript.is_implemented(declared_handler):
			errors.append("Actionable node %s must declare implemented handler %s." % [node_id, expected_handler])
		var runtime_chain_input := str(node.get("runtime_chain_input_ref", ""))
		var runtime_chain_output := str(node.get("runtime_chain_output_ref", ""))
		if runtime_chain_input != "" and not produced_chain_states.has(runtime_chain_input):
			errors.append("Runtime node %s consumes %s before an implemented handler produces it." % [node_id, runtime_chain_input])
		if runtime_chain_output != "":
			produced_chain_states[runtime_chain_output] = node_id
		if optional or not bool(node.get("runtime_progression_required", false)):
			continue
		critical_count += 1
		var beat: Dictionary = node.get("systems_beat", {})
		var verb := str(beat.get("verb", "")).strip_edges()
		if beat.is_empty():
			errors.append("Critical node %s has no systems beat." % str(node.get("id", "")))
		elif verb == "" or verb.contains(" "):
			errors.append("Critical node %s must use exactly one reasoning verb." % str(node.get("id", "")))
		elif not model_ids.has(str(beat.get("model_id", ""))):
			errors.append("Critical node %s references an unknown causal model." % str(node.get("id", "")))
		for field in ["prediction", "intervention", "evidence"]:
			if str(beat.get(field, "")).strip_edges() == "":
				errors.append("Critical node %s is missing %s feedback." % [str(node.get("id", "")), field])
		if str(section.get("schema", "")) != "trawf_playable_section_v1":
			errors.append("Critical node %s is a point without a playable-section contract." % node_id)
		else:
			for field in ["boundary", "action", "predicted_effect", "source_role", "effect_role", "relationship_label", "observable_evidence", "runtime_handler"]:
				if str(section.get(field, "")).strip_edges() == "":
					errors.append("Playable section %s is missing %s." % [str(node.get("id", "")), field])
			if (section.get("interacting_systems", []) as Array).size() < 2:
				errors.append("Playable section %s must compose at least two named systems." % str(node.get("id", "")))
	var focus_teach_index := -1
	var focus_test_index := -1
	var focus_transfer_index := -1
	var focus_model_id := str(contract.get("focus_model_id", ""))
	var lesson_spine: Array = contract.get("lesson_spine", [])
	var complete_lesson_sequence := lesson_spine.duplicate(true)
	complete_lesson_sequence.append_array(contract.get("optional_lesson_spine", []))
	for beat_index in range(complete_lesson_sequence.size()):
		if not (complete_lesson_sequence[beat_index] is Dictionary):
			continue
		var lesson_beat := complete_lesson_sequence[beat_index] as Dictionary
		if str(lesson_beat.get("model_id", "")) != focus_model_id:
			continue
		match str(lesson_beat.get("beat", "")):
			"teach":
				if focus_teach_index < 0:
					focus_teach_index = beat_index
			"test":
				if focus_test_index < 0:
					focus_test_index = beat_index
			"transfer", "application":
				if focus_transfer_index < 0:
					focus_transfer_index = beat_index
	var focus_has_transfer := focus_transfer_index >= 0
	var focus_transfer_follows_test := (
		focus_has_transfer
		and focus_teach_index >= 0
		and focus_test_index > focus_teach_index
		and focus_transfer_index > focus_test_index
	)
	if focus_has_transfer and not focus_transfer_follows_test:
		errors.append(
			"A focus transfer or application beat must follow an explicit teach beat and a later explicit test beat."
		)
	if bool(contract.get("transfer_sequence_explicit", false)) != focus_has_transfer:
		errors.append("transfer_sequence_explicit does not match the mandatory and optional focus lesson data.")
	if focus_occurrences >= 2 and (not focus_has_teach or not focus_has_test):
		errors.append("The focus causal model must be taught and tested later under a changed condition.")
	if bool(contract.get("runtime_profile_coverage", false)) != focus_matches_profile:
		errors.append("Runtime profile coverage does not match the implemented focus handler.")
	if (contract.get("actionable_nodes", []) as Array) != expected_actionable:
		errors.append("Systems contract actionable_nodes does not match the handler registry.")
	if (contract.get("layout_only_nodes", []) as Array) != expected_layout_only:
		errors.append("Systems contract layout_only_nodes does not match the handler registry.")
	if int(contract.get("solved_state_execution_tail_nodes", 99)) > 1:
		errors.append("Generated stretch has more than one solved-state execution-tail node.")
	if (contract.get("causal_links", []) as Array).is_empty() and critical_count >= 2:
		errors.append("Systems contract has no visible cause-to-effect or teach-to-test link.")
	for raw_node in spec.get("nodes", []):
		if raw_node is Dictionary and str((raw_node as Dictionary).get("archetype_id", "")) == "9":
			errors.append("Procedural archetype 9 is blocked until its typed convention handshake exists.")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"model_count": models.size(),
		"critical_beat_count": critical_count,
		"focus_has_teach": focus_has_teach,
		"focus_has_test": focus_has_test,
		"focus_has_transfer": focus_has_transfer,
		"focus_transfer_follows_test": focus_transfer_follows_test,
		"focus_matches_profile": focus_matches_profile,
		"actionable_node_count": expected_actionable.size(),
		"layout_only_node_count": expected_layout_only.size(),
	}


static func _model_for_runtime_handler(catalog, node: Dictionary, handler_id: String) -> Dictionary:
	match handler_id:
		RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE:
			return model_for_archetype(catalog.get_archetype("12"), "12")
		RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD:
			var model := model_for_archetype(catalog.get_archetype("3"), "3")
			model.merge({
				"relationship": "taking a physical load occupies the interacting carrier's hand; that exact held load must reach shelter",
				"cause": "a named character in range with a free hand takes the visible source item",
				"effect": "one named payload occupies that carrier's hand until verified at shelter delivery",
				"prediction": "taking the visible load will occupy one hand and dropping it will prevent delivery",
				"intervention": "choose the carrier, take the load from its physical source, and keep that item carried to shelter",
				"evidence": "the source empties, the exact held-item portrait and carrier update, and shelter checks the same item id",
				"transfer_test": "deliver another physical payload through a different exposure pattern",
			}, true)
			return model
		RuntimeRegistryScript.HANDLER_CANONICAL_SHELTER_ARRIVAL:
			var model := model_for_archetype(catalog.get_archetype("16"), "16")
			model.merge({
				"verb": "recover",
				"relationship": "a complete conscious party inside a real shelter may finish the stretch; only members who need recovery start canonical ATP-paid rest",
				"cause": "every active party member reaches the registered shelter region",
				"effect": "needed recovery starts through command_rest, or an already-full party completes without an ATP charge",
				"prediction": "arrival completes only after the party is present and every needed rest command succeeds",
				"intervention": "regroup inside the shelter and enter it once the party is ready",
				"evidence": "presence, recovery need, successful rest starts, and unchanged ATP for already-full members are reported separately",
				"transfer_test": "distinguish safe arrival from ATP-paid recovery at another shelter",
			}, true)
			return model
	# Defensive fallback. The registry rejects this before a node becomes actionable,
	# but a complete semantic record makes malformed-spec diagnostics readable.
	return model_for_archetype(catalog.get_archetype(str(node.get("archetype_id", ""))), str(node.get("archetype_id", "")))


static func model_for_archetype(archetype: Dictionary, archetype_id: String) -> Dictionary:
	var name := str(archetype.get("name", "generated system"))
	var model := {
		"verb": "intervene",
		"relationship": "an intervention changes the reachable state of %s" % name,
		"cause": "the player changes the load-bearing element",
		"effect": "the next state becomes reachable",
		"polarity": "mixed",
		"stock": "none",
		"flow": "state change through the encounter",
		"delay": "none",
		"feedback_loop": "none",
		"threshold": "the interaction's completion condition",
		"local_vs_party_scale": "a local action changes the party route",
		"leverage_point": "the load-bearing interaction",
		"likely_misconception": "every visible object must be serviced independently",
		"prediction": "changing the load-bearing element will alter the reachable state",
		"intervention": "change the load-bearing element once, then observe",
		"evidence": "the target state and route visibly change",
		"transfer_test": "recognize the same relationship with a changed target or layout",
		"dimensions": ["relation", "leverage", "transfer"],
	}
	match archetype_id:
		"1":
			model.merge({"verb": "redirect", "relationship": "bait position redirects a committed enemy charge into an impact target", "cause": "the party enters the charge line before commitment", "effect": "enemy momentum changes the target state", "polarity": "positive", "flow": "enemy momentum into the impact target", "delay": "visible charge wind-up", "threshold": "the enemy commits after its tell", "leverage_point": "bait position immediately before commitment", "likely_misconception": "the enemy must be defeated directly", "prediction": "the enemy will strike the aligned target after committing", "intervention": "align the bait, trigger the tell, then leave the line", "evidence": "the tell, charge path, impact, and changed target remain visible", "transfer_test": "redirect the same commitment into a different target", "dimensions": ["relation", "delay", "threshold", "leverage", "transfer"]}, true)
		"2":
			model.merge({"verb": "cultivate", "relationship": "plant placement plus time changes a nearby actor or route", "cause": "Peris places or tends the plant in the relevant relation", "effect": "the mature plant changes the target state", "polarity": "positive", "stock": "plant readiness", "flow": "tending and elapsed time into readiness", "delay": "growth or trigger delay", "threshold": "the plant becomes active at readiness", "leverage_point": "where the plant is placed", "likely_misconception": "the plant effect is immediate or useful anywhere", "prediction": "the placed plant will affect the target after its readiness tell", "intervention": "place once at the causal location and wait for the tell", "evidence": "growth state, target link, and resulting target response are visible", "transfer_test": "use a different plant or target while preserving the placement relation", "dimensions": ["relation", "stock", "flow", "delay", "threshold", "leverage", "transfer"]}, true)
		"3":
			model.merge({"verb": "support", "relationship": "carried load trades mobility for persistent progress while party support limits exposure", "cause": "one character accepts the load and its constraints", "effect": "the resource moves while the carrier becomes vulnerable", "polarity": "mixed", "stock": "carrier stamina and carried progress", "flow": "support converts safe windows into delivered distance", "delay": "none", "feedback_loop": "slower movement increases exposure, which further drains carrying capacity", "threshold": "the load is delivered before capacity fails", "leverage_point": "route staging and who covers the carrier", "likely_misconception": "the carrier can move as if unburdened", "prediction": "an unsupported carrier will lose more capacity on the exposed segment", "intervention": "stage cover and clear the next segment before moving the load", "evidence": "mobility, exposure, capacity, and delivery progress remain visible", "transfer_test": "carry a different object through a route with a changed hazard", "dimensions": ["relation", "stock", "flow", "feedback", "local_global", "leverage", "transfer"]}, true)
		"4":
			model.merge({"verb": "distract", "relationship": "a positioned signal moves patrol attention and creates a temporary blind region", "cause": "the party creates a stronger signal away from the objective", "effect": "the patrol changes route and leaves a timed opening", "polarity": "negative", "stock": "patrol attention", "flow": "signal strength pulls attention between locations", "delay": "patrol response and travel time", "threshold": "the distraction exceeds the patrol's current stimulus", "leverage_point": "signal position relative to patrol and objective", "likely_misconception": "triggering any distraction anywhere creates safety", "prediction": "the patrol will investigate the stronger positioned signal", "intervention": "place the signal, predict the blind window, then act inside it", "evidence": "attention line, patrol route, and blind window are visible", "transfer_test": "create the opening with a different signal or patrol geometry", "dimensions": ["relation", "stock", "flow", "delay", "threshold", "local_global", "leverage", "transfer"]}, true)
		"5":
			model.merge({"verb": "coordinate", "relationship": "progress on separated sides is mutually dependent and only completes when both states align", "cause": "the party divides capabilities across the dependency", "effect": "both local states jointly unlock the shared route", "polarity": "positive", "stock": "progress on each side", "flow": "actions add progress to separate dependencies", "delay": "communication and travel between sides", "feedback_loop": "a stalled side delays reunion and increases pressure on the other", "threshold": "both dependent tasks are ready together", "local_vs_party_scale": "each side looks locally complete but only the party state opens the route", "leverage_point": "the capability allocation before separation", "likely_misconception": "finishing either side is sufficient", "prediction": "the shared gate opens only when both side states align", "intervention": "allocate capabilities, pause, then coordinate the two completions", "evidence": "both side states and their shared gate link are visible", "transfer_test": "solve the dependency with different character assignments", "dimensions": ["relation", "stock", "delay", "feedback", "local_global", "topology", "leverage", "transfer"]}, true)
		"6":
			model.merge({"verb": "reconstruct", "relationship": "partial observations become actionable only through their arrangement and shared relationships", "cause": "the party retrieves and relates fragments", "effect": "the hidden pattern or route becomes legible", "polarity": "positive", "stock": "verified fragments", "flow": "retrieval adds evidence to the model", "delay": "none", "threshold": "enough relational evidence exists to distinguish the pattern", "leverage_point": "the relationship between fragments, not fragment count alone", "likely_misconception": "collecting every fragment automatically solves the pattern", "prediction": "the proposed arrangement will explain all recovered relations", "intervention": "place fragments by relationship and test the implied route", "evidence": "contradictions and confirmed links stay visible", "transfer_test": "reconstruct the same relation from a different presentation", "dimensions": ["relation", "stock", "threshold", "topology", "diagnosis", "leverage", "transfer"]}, true)
		"7":
			model.merge({"verb": "time", "relationship": "patrol phase determines which route segment is safe", "cause": "the party enters at a chosen phase", "effect": "the objective is crossed before the patrol closes the gap", "polarity": "negative", "flow": "patrol motion through a repeating cycle", "delay": "the patrol period", "threshold": "the remaining gap exceeds traversal time", "leverage_point": "entry phase rather than movement precision", "likely_misconception": "moving faster is the only way through", "prediction": "entering on this phase leaves enough gap to disengage", "intervention": "observe one cycle, choose the phase, then commit", "evidence": "patrol phase, gap duration, and cover destination are visible", "transfer_test": "use the timing model with a changed patrol path", "dimensions": ["relation", "flow", "delay", "threshold", "leverage", "transfer"]}, true)
		"8":
			model.merge({"verb": "authorize", "relationship": "the interaction consumes the authority or capability of the positioned character", "cause": "the correct bearer initiates the gate", "effect": "the gated state changes", "polarity": "positive", "threshold": "the required class capability is present", "leverage_point": "who is positioned at the gate", "likely_misconception": "any selected character can operate every gate", "prediction": "the gate will accept the bearer whose capability matches its read", "intervention": "read the requirement and position only the matching bearer", "evidence": "requirement, bearer capability, and accepted or rejected state are distinct", "transfer_test": "identify a different bearer from a changed gate read", "dimensions": ["relation", "threshold", "local_global", "leverage", "transfer"]}, true)
		"9":
			model.merge({"verb": "reframe", "relationship": "an established convention is deliberately broken and produces a typed consequence", "cause": "the player invokes the known convention", "effect": "the subversion changes the expected output", "polarity": "mixed", "leverage_point": "the exact convention output consumed by the consequence", "likely_misconception": "the established convention remains universally reliable", "prediction": "the convention will produce its previously taught output", "intervention": "invoke it once and compare actual output with the typed expectation", "evidence": "expected output, actual output, and consequence are shown together", "transfer_test": "recognize which assumption changed rather than discarding the whole model", "dimensions": ["relation", "threshold", "diagnosis", "transfer"]}, true)
		"10":
			model.merge({"verb": "contain", "relationship": "nested sub-systems change a container state that governs entry, retrieval, and exit", "cause": "the party resolves the load-bearing nested dependency", "effect": "the container releases the component and exit state", "polarity": "mixed", "stock": "resolved nested dependencies", "flow": "sub-puzzle outputs feed the container state", "delay": "nested state propagation", "feedback_loop": "container pressure changes the constraints on its sub-puzzles", "threshold": "all load-bearing dependencies are satisfied", "local_vs_party_scale": "local sub-puzzle success matters only through the container", "leverage_point": "the shared dependency feeding several nested states", "likely_misconception": "each nested room is an independent checklist", "prediction": "changing the shared dependency will alter more than one nested state", "intervention": "trace outputs to the shared dependency and change it first", "evidence": "typed links show each nested output reaching the container", "transfer_test": "find the shared dependency in a differently arranged container", "dimensions": ["relation", "stock", "flow", "delay", "feedback", "local_global", "topology", "leverage", "transfer"]}, true)
		"11":
			model.merge({"verb": "recognize", "relationship": "a visible transition changes party or world state while preserving continuity", "cause": "the transition mechanism is completed", "effect": "the post-transition state becomes active", "polarity": "positive", "threshold": "the required party state reaches the transition", "leverage_point": "the state transition, not traversal length", "likely_misconception": "the beat is flavor with no persistent state change", "prediction": "the transition will preserve the declared state into the next section", "intervention": "complete the transition and inspect the carried state", "evidence": "pre-state, transition, and post-state are recorded", "transfer_test": "recognize the same state continuity in another transition", "dimensions": ["relation", "threshold", "transfer"]}, true)
		"12":
			model.merge({"verb": "forage", "relationship": "risked access moves a finite lysate cache into one carrier hand; only a later explicit endocytosis changes that carrier's ATP", "cause": "the party clears the cache window and a character with a free hand takes the lysate", "effect": "the cache empties and that hand becomes occupied while ATP remains unchanged", "polarity": "mixed", "stock": "cache contents, free hands, and the carrier's ATP", "flow": "pickup moves lysate from cache to hand; optional endocytosis later moves its value into the carrier's ATP", "delay": "pickup and endocytosis are separate decisions", "threshold": "the chosen carrier has a free hand before the threat window closes", "local_vs_party_scale": "a local cache and carrier choice changes who can fund a later shelter rest", "leverage_point": "which cache is worth the exposure and which hand should carry it", "likely_misconception": "touching a cache immediately or party-wide restores ATP", "prediction": "claiming the cache occupies exactly one hand without changing ATP", "intervention": "compare cache yield, exposure, and hand commitments before taking it", "evidence": "the cache clears, one portrait shows held lysate, and ATP changes only after that carrier endocytoses", "transfer_test": "choose a cache and carrier under different hand and route constraints", "dimensions": ["relation", "stock", "flow", "delay", "threshold", "local_global", "leverage", "transfer"]}, true)
		"13":
			model.merge({"verb": "exploit", "relationship": "a bait or trigger couples two enemy systems so their responses open the route", "cause": "the party changes the ecology signal at the collision point", "effect": "predators act on each other and vacate the crossing", "polarity": "mixed", "stock": "enemy attention and readiness", "flow": "signal moves aggression between targets", "delay": "ecology response window", "feedback_loop": "one predator's response changes the next predator's target", "threshold": "both responses overlap at the collision window", "local_vs_party_scale": "a local signal reorganizes the whole crossing", "leverage_point": "the coupling signal between enemy types", "likely_misconception": "each enemy must be cleared separately", "prediction": "the first response will trigger or expose the second", "intervention": "place the coupling signal and commit only after both tells align", "evidence": "enemy target lines, response tells, collision, and opened route are visible", "transfer_test": "couple a different enemy pair using the same response logic", "dimensions": ["relation", "stock", "flow", "delay", "feedback", "local_global", "topology", "leverage", "transfer"]}, true)
		"14":
			model.merge({"verb": "stage", "relationship": "cover and resource relays convert a long attrition run into bounded safe segments", "cause": "the party prepares the next safe segment before leaving the current one", "effect": "pressure is absorbed without exhausting party capacity", "polarity": "negative", "stock": "health, stamina, cover, and food relays", "flow": "enemy pressure drains capacity between relays", "delay": "enemy lane cycles", "feedback_loop": "damage reduces movement capacity, increasing later exposure", "threshold": "remaining capacity covers the next segment", "local_vs_party_scale": "each runner's exposure consumes shared recovery resources", "leverage_point": "relay placement before the run", "likely_misconception": "the gauntlet is one continuous sprint", "prediction": "the staged relay route will keep every segment under the capacity threshold", "intervention": "prepare cover and recovery segment by segment, then commit", "evidence": "lane timing, segment cost, and remaining capacity are visible", "transfer_test": "restage the relays for a changed lane configuration", "dimensions": ["relation", "stock", "flow", "delay", "feedback", "local_global", "threshold", "leverage", "transfer"]}, true)
		"15":
			model.merge({"verb": "budget", "relationship": "dose rate multiplied by time determines whether a route stays within the damage budget", "cause": "the party commits to a lane with a known exposure rate", "effect": "health or stamina stock drains until the field is cleared", "polarity": "negative", "stock": "remaining health and stamina", "flow": "field dose drains capacity over time", "delay": "exposure accumulates while inside", "feedback_loop": "lost capacity can lengthen crossing time and increase dose", "threshold": "remaining capacity exceeds projected total dose", "leverage_point": "route duration and stabilization before entry", "likely_misconception": "the shortest geometric path always costs least", "prediction": "this lane's rate and duration stay inside the current budget", "intervention": "compare projected doses, stabilize if useful, then commit one lane", "evidence": "dose rate, elapsed exposure, remaining stock, and exit are visible", "transfer_test": "recalculate after route length or dose rate changes", "dimensions": ["relation", "stock", "flow", "delay", "feedback", "threshold", "leverage", "transfer"]}, true)
		"16":
			model.merge({"verb": "recover", "relationship": "rest converts banked ATP and shelter access into reduced sleep debt and restored capacity", "cause": "the regrouped party spends ATP at a valid rest state", "effect": "recovery increases and sleep deprivation clears", "polarity": "negative", "stock": "ATP, health, stamina, and sleep debt", "flow": "rest spends ATP to restore capacity and reduce debt", "delay": "the rest interval", "feedback_loop": "poor recovery reduces future collection capacity, increasing future scarcity", "threshold": "enough ATP and safety exist for worthwhile rest", "local_vs_party_scale": "one cache decision changes the whole party's next stretch", "leverage_point": "when and where ATP is banked before rest", "likely_misconception": "rest is free or every cache must be collected", "prediction": "the banked ATP will cover the chosen recovery before the next stretch", "intervention": "regroup, compare debt with ATP, then choose the rest spend", "evidence": "ATP spent, debt cleared, and capacity restored are visible", "transfer_test": "choose recovery when the same route presents a different remaining-resource balance", "dimensions": ["relation", "stock", "flow", "delay", "feedback", "local_global", "threshold", "leverage", "transfer"]}, true)
	return model


static func _beat_name(occurrence: int, total: int, optional: bool) -> String:
	if optional:
		return "optional_probe"
	if total <= 1:
		return "apply"
	match occurrence:
		0:
			return "teach"
		1:
			return "test"
		2:
			return "twist"
		_:
			return "transfer"


static func _critical_focus_occurrences(node_count: int, chain_size: int, focus_index: int, optional_budget: int) -> int:
	if chain_size <= 0:
		return 0
	var optional_remaining := optional_budget
	var result := 0
	var chain_cursor := 0
	for node_index in range(1, node_count - 1):
		var optional := optional_remaining > 0 and node_index % 3 == 0
		if optional:
			optional_remaining -= 1
			continue
		if chain_cursor % chain_size == focus_index:
			result += 1
		chain_cursor += 1
	return result


static func _focus_model_id(models: Array, profile: Dictionary) -> String:
	for raw_model in models:
		if not (raw_model is Dictionary):
			continue
		var model := raw_model as Dictionary
		if str(model.get("archetype_id", "")) != "11" \
				and not (model.get("test_nodes", []) as Array).is_empty() \
				and _model_matches_profile(model, profile):
			return str(model.get("id", ""))
	for raw_model in models:
		if not (raw_model is Dictionary):
			continue
		var model := raw_model as Dictionary
		if str(model.get("archetype_id", "")) != "11" and not (model.get("test_nodes", []) as Array).is_empty():
			return str(model.get("id", ""))
	for raw_model in models:
		if raw_model is Dictionary and not ((raw_model as Dictionary).get("test_nodes", []) as Array).is_empty():
			return str((raw_model as Dictionary).get("id", ""))
	return str((models[0] as Dictionary).get("id", "")) if not models.is_empty() and models[0] is Dictionary else ""


static func _build_causal_links(nodes: Array, models: Array) -> Array:
	var links := []
	# Every playable section exposes its LOCAL causal edge. Earlier contracts only
	# linked one checkpoint to a later checkpoint, which made the level read as a
	# tour of points and hid what the current action would affect in the room.
	for raw_node in nodes:
		if not (raw_node is Dictionary):
			continue
		var node := raw_node as Dictionary
		var node_id := str(node.get("id", ""))
		var section: Dictionary = node.get("playable_section", {})
		if node_id == "" or section.is_empty() or str(node.get("role", "")) in ["boundary", "shelter_arrival"]:
			continue
		links.append({
			"kind": "intervention_effect",
			"node": node_id,
			"from": "%s:cause" % node_id,
			"to": "%s:effect" % node_id,
			"source_role": str(section.get("source_role", "cause")),
			"effect_role": str(section.get("effect_role", "effect")),
			"state": str(section.get("after_state", "changed")),
			"state_label": str(section.get("relationship_label", "CHANGES")),
			"prediction": str(section.get("predicted_effect", "")),
			"visibility_policy": "party_visibility_union",
			"display": "hover_or_pause",
		})
	# Link each concrete output to the first later consumer of that exact cycle-scoped
	# state. This preserves repeated chains and safely crosses reward detours.
	for source_index in range(nodes.size()):
		if not (nodes[source_index] is Dictionary):
			continue
		var source: Dictionary = nodes[source_index]
		if bool(source.get("optional", false)):
			continue
		var output_ref := str(source.get("chain_output_ref", ""))
		if output_ref == "":
			continue
		for target_index in range(source_index + 1, nodes.size()):
			if not (nodes[target_index] is Dictionary):
				continue
			var target: Dictionary = nodes[target_index]
			if bool(target.get("optional", false)) or str(target.get("chain_input_ref", "")) != output_ref:
				continue
			links.append({
				"kind": "typed_state_flow",
				"from": str(source.get("id", "")),
				"to": str(target.get("id", "")),
				"state": output_ref,
				"state_label": str(source.get("chain_output", "")),
				"visibility_policy": "party_visibility_union",
				"display": "highlight_or_pause",
			})
			break
	for raw_model in models:
		if not (raw_model is Dictionary):
			continue
		var model := raw_model as Dictionary
		var teach_node := str(model.get("teach_node", ""))
		for test_node in model.get("test_nodes", []):
			if teach_node == "" or str(test_node) == "":
				continue
			links.append({
				"kind": "model_transfer",
				"from": teach_node,
				"to": str(test_node),
				"state": str(model.get("relationship", "")),
				"visibility_policy": "party_visibility_union",
				"display": "highlight_or_pause",
			})
	return links


static func _arrays_intersect(a: Array, b: Array) -> bool:
	for value in a:
		if b.has(value):
			return true
	return false


static func _model_matches_profile(model: Dictionary, profile: Dictionary) -> bool:
	return _dimensions_match_profile(model.get("dimensions", []), profile)


static func _dimensions_match_profile(dimensions: Array, profile: Dictionary) -> bool:
	for required in profile.get("required_dimensions", []):
		if not dimensions.has(required):
			return false
	var required_any: Array = profile.get("required_any_dimensions", [])
	return required_any.is_empty() or _arrays_intersect(dimensions, required_any)
