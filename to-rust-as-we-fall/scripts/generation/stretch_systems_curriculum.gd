class_name StretchSystemsCurriculum
extends RefCounted

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
		if str(entry.get("id", "")) != "11" and _dimensions_match_profile(entry.get("systems_dimensions", []), profile):
			return i
	for i in range(chain.size()):
		if chain[i] is Dictionary and str((chain[i] as Dictionary).get("id", "")) != "11":
			return i
	return 0 if not chain.is_empty() else -1


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
	var occurrence_totals := {}
	var interior_indices: Array[int] = []
	for i in range(nodes.size()):
		if not (nodes[i] is Dictionary):
			continue
		var node: Dictionary = nodes[i]
		if str(node.get("role", "")) in ["boundary", "shelter_arrival"]:
			continue
		interior_indices.append(i)
		var id := str(node.get("archetype_id", ""))
		if not bool(node.get("optional", false)):
			occurrence_totals[id] = int(occurrence_totals.get(id, 0)) + 1

	var model_order: Array[String] = []
	var model_by_id := {}
	var seen := {}
	var lesson_spine := []
	for node_index in interior_indices:
		var node: Dictionary = nodes[node_index]
		var archetype_id := str(node.get("archetype_id", ""))
		var model_id := "archetype_%s" % archetype_id
		if not model_by_id.has(model_id):
			var model := model_for_archetype(catalog.get_archetype(archetype_id), archetype_id)
			model["id"] = model_id
			model["archetype_id"] = archetype_id
			model["archetype_name"] = str(node.get("archetype_name", ""))
			model["node_ids"] = []
			model["teach_node"] = ""
			model["test_nodes"] = []
			model_by_id[model_id] = model
			model_order.append(model_id)
		var occurrence := int(seen.get(archetype_id, 0))
		var optional := bool(node.get("optional", false))
		if not optional:
			seen[archetype_id] = occurrence + 1
		var total := int(occurrence_totals.get(archetype_id, 0))
		var beat_name := _beat_name(occurrence, total, optional)
		var model: Dictionary = model_by_id[model_id]
		var node_id := str(node.get("id", ""))
		(model["node_ids"] as Array).append(node_id)
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
		# Presentation consumes the same semantic model as the solver. A generated
		# interaction must advertise the intervention the player is about to make;
		# generic verbs such as "VISIT" hide the causal choice and turn the route
		# into a checkpoint tour.
		node["action_verb"] = action_verb_for_node(node)
		node["prediction_hint"] = str(beat.get("prediction", ""))
		node["evidence_hint"] = str(beat.get("evidence", ""))
		nodes[node_index] = node
		lesson_spine.append({
			"node": node_id,
			"archetype_id": archetype_id,
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
	var focus_model_id := _focus_model_id(models, profile)
	var causal_links := _build_causal_links(nodes, models)
	var reasoning_solved_at := "entry"
	for i in range(interior_indices.size() - 1, -1, -1):
		var candidate: Dictionary = nodes[interior_indices[i]]
		if not bool(candidate.get("optional", false)):
			reasoning_solved_at = str(candidate.get("id", reasoning_solved_at))
			break

	return {
		"schema": CONTRACT_SCHEMA,
		"boundary": "the generated entry-to-shelter route and the states changed inside it",
		"goal": "make the exit shelter reachable by changing the modeled relationships",
		"progression_profile": profile,
		"difficulty_dimensions": {
			"reasoning": str(profile.get("reasoning_demand", "")),
			"controls": "constant",
			"camera": "constant",
			"execution_precision": "not used as progression scaling",
			"geometry_density": "controlled by complexity tier, not campaign stage",
		},
		"focus_model_id": focus_model_id,
		"causal_models": models,
		"lesson_spine": lesson_spine,
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
		"route_count": routes.size(),
	}


## Short, concrete copy for the cursor verb and persistent generated-node hint.
## Variants name the physical intervention when they can; the reasoning verb is
## the stable fallback, so future archetypes remain legible without UI hardcoding.
static func action_verb_for_node(node: Dictionary) -> String:
	var node_id := str(node.get("id", ""))
	var role := str(node.get("role", ""))
	if node_id == "entry" or role == "boundary":
		return "ENTER STRETCH"
	if node_id == "exit_shelter" or role in ["shelter", "shelter_arrival"]:
		return "REST AT SHELTER"
	if str(node.get("reward_kind", "")) == "food":
		return "SECURE +%d ATP LYSATE" % maxi(1, int(node.get("reward_atp", node.get("atp_reward", 1))))

	var variant := str(node.get("variant", "")).replace("_", " ").to_lower()
	if variant.contains("flure") and (variant.contains("decoy") or variant.contains("signal")):
		return "DEPLOY FLURE DECOY"
	if variant.contains("false scent"):
		return "LAY FALSE SCENT"
	if variant.contains("loud"):
		return "MAKE LOUD SIGNAL"
	if variant.contains("electrical"):
		return "EMIT ELECTRICAL SIGNAL"
	if variant.contains("terminal"):
		return "OPERATE TERMINAL"

	var beat: Dictionary = node.get("systems_beat", {})
	var verb := str(beat.get("verb", "intervene"))
	match verb:
		"redirect":
			return "BAIT THE CHARGE"
		"cultivate":
			return "PLACE THE FLORA"
		"support":
			return "STAGE THE CARRY"
		"distract":
			return "DISTRACT THE PATROL"
		"coordinate":
			return "COORDINATE BOTH SIDES"
		"reconstruct":
			return "RELATE THE FRAGMENTS"
		"time":
			return "TIME THE CROSSING"
		"authorize":
			return "PRESENT AUTHORITY"
		"contain":
			return "RESOLVE THE DEPENDENCY"
		"forage":
			return "SECURE THE FOOD"
		"exploit":
			return "COUPLE THE ENEMIES"
		"stage":
			return "STAGE THE RELAY"
		"budget":
			return "COMMIT TO THE LANE"
		"recover":
			return "SPEND ATP TO REST"
		"diagnose":
			return "COMMIT THE DIAGNOSIS"
		"recognize":
			return "CROSS THE BOUNDARY"
		_:
			return verb.replace("_", " ").to_upper()


static func validate_contract(spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var contract: Dictionary = spec.get("systems_contract", {})
	if str(contract.get("schema", "")) != CONTRACT_SCHEMA:
		errors.append("Missing or unsupported generated systems contract.")
		return {"valid": false, "errors": errors}
	for field in ["boundary", "goal", "focus_model_id", "reasoning_solved_at"]:
		if str(contract.get(field, "")).strip_edges() == "":
			errors.append("Systems contract is missing %s." % field)
	var models: Array = contract.get("causal_models", [])
	if models.is_empty():
		errors.append("Systems contract has no causal models.")
	var model_ids := {}
	var focus_has_teach := false
	var focus_has_test := false
	var focus_matches_profile := false
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
	var critical_count := 0
	var produced_chain_states := {}
	var chain_mode := str(spec.get("composition", {}).get("mode", "")) == "chain_nested_poc"
	for raw_node in spec.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node := raw_node as Dictionary
		var optional := bool(node.get("optional", false))
		var chain_input := str(node.get("chain_input", ""))
		var chain_output := str(node.get("chain_output", ""))
		var chain_input_ref := str(node.get("chain_input_ref", ""))
		var chain_output_ref := str(node.get("chain_output_ref", ""))
		if optional and (chain_input != "" or chain_output != "" or chain_input_ref != "" or chain_output_ref != ""):
			errors.append("Optional reward node %s cannot carry a mandatory chain handshake." % str(node.get("id", "")))
		if not optional and chain_mode:
			if chain_input != "" and chain_input_ref == "":
				errors.append("Chain node %s has an untyped input state." % str(node.get("id", "")))
			elif chain_input_ref != "" and not produced_chain_states.has(chain_input_ref):
				errors.append("Chain node %s consumes %s before any earlier node produces it." % [str(node.get("id", "")), chain_input_ref])
			if chain_output != "" and chain_output_ref == "":
				errors.append("Chain node %s has an untyped output state." % str(node.get("id", "")))
			elif chain_output_ref != "":
				produced_chain_states[chain_output_ref] = str(node.get("id", ""))
			if (
				str(node.get("archetype_id", "")) == "3"
				and not (node.get("nested_archetypes", []) as Array).is_empty()
				and (not bool(node.get("resource", false)) or not bool(node.get("carry_payload", false)))
			):
				errors.append("Nested chain host %s must alter a physical carried payload." % str(node.get("id", "")))
		if str(node.get("role", "")) in ["boundary", "shelter_arrival"] or optional:
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
	if critical_count >= 2 and (not focus_has_teach or not focus_has_test):
		errors.append("The focus causal model must be taught and tested later under a changed condition.")
	if not focus_matches_profile:
		errors.append("The focus causal model does not satisfy the declared progression profile.")
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
		"focus_matches_profile": focus_matches_profile,
	}


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
			model.merge({"verb": "forage", "relationship": "risked dwell converts a finite cache into ATP stock for later recovery", "cause": "the party clears and occupies the cache window", "effect": "ATP increases while time and exposure are spent", "polarity": "mixed", "stock": "banked ATP and cache contents", "flow": "lysate intake increases ATP; later rest spends it", "delay": "the endocytosis dwell", "threshold": "the dwell completes before the threat window closes", "local_vs_party_scale": "local cache risk changes later party recovery", "leverage_point": "which cache window is worth its future ATP", "likely_misconception": "all food is mandatory or equally valuable", "prediction": "the riskier cache pays enough ATP to change a later recovery choice", "intervention": "compare cache yield with exposure before committing the dwell", "evidence": "yield, dwell, exposure, and ATP delta are visible", "transfer_test": "choose between sparse safe food and a richer risky branch", "dimensions": ["relation", "stock", "flow", "delay", "threshold", "local_global", "leverage", "transfer"]}, true)
		"13":
			model.merge({"verb": "exploit", "relationship": "a bait or trigger couples two enemy systems so their responses open the route", "cause": "the party changes the ecology signal at the collision point", "effect": "predators act on each other and vacate the crossing", "polarity": "mixed", "stock": "enemy attention and readiness", "flow": "signal moves aggression between targets", "delay": "ecology response window", "feedback_loop": "one predator's response changes the next predator's target", "threshold": "both responses overlap at the collision window", "local_vs_party_scale": "a local signal reorganizes the whole crossing", "leverage_point": "the coupling signal between enemy types", "likely_misconception": "each enemy must be cleared separately", "prediction": "the first response will trigger or expose the second", "intervention": "place the coupling signal and commit only after both tells align", "evidence": "enemy target lines, response tells, collision, and opened route are visible", "transfer_test": "couple a different enemy pair using the same response logic", "dimensions": ["relation", "stock", "flow", "delay", "feedback", "local_global", "topology", "leverage", "transfer"]}, true)
		"14":
			model.merge({"verb": "stage", "relationship": "cover and resource relays convert a long attrition run into bounded safe segments", "cause": "the party prepares the next safe segment before leaving the current one", "effect": "pressure is absorbed without exhausting party capacity", "polarity": "negative", "stock": "health, stamina, cover, and food relays", "flow": "enemy pressure drains capacity between relays", "delay": "enemy lane cycles", "feedback_loop": "damage reduces movement capacity, increasing later exposure", "threshold": "remaining capacity covers the next segment", "local_vs_party_scale": "each runner's exposure consumes shared recovery resources", "leverage_point": "relay placement before the run", "likely_misconception": "the gauntlet is one continuous sprint", "prediction": "the staged relay route will keep every segment under the capacity threshold", "intervention": "prepare cover and recovery segment by segment, then commit", "evidence": "lane timing, segment cost, and remaining capacity are visible", "transfer_test": "restage the relays for a changed lane configuration", "dimensions": ["relation", "stock", "flow", "delay", "feedback", "local_global", "threshold", "leverage", "transfer"]}, true)
		"15":
			model.merge({"verb": "budget", "relationship": "dose rate multiplied by time determines whether a route stays within the damage budget", "cause": "the party commits to a lane with a known exposure rate", "effect": "health or stamina stock drains until the field is cleared", "polarity": "negative", "stock": "remaining health and stamina", "flow": "field dose drains capacity over time", "delay": "exposure accumulates while inside", "feedback_loop": "lost capacity can lengthen crossing time and increase dose", "threshold": "remaining capacity exceeds projected total dose", "leverage_point": "route duration and stabilization before entry", "likely_misconception": "the shortest geometric path always costs least", "prediction": "this lane's rate and duration stay inside the current budget", "intervention": "compare projected doses, stabilize if useful, then commit one lane", "evidence": "dose rate, elapsed exposure, remaining stock, and exit are visible", "transfer_test": "recalculate after route length or dose rate changes", "dimensions": ["relation", "stock", "flow", "delay", "feedback", "threshold", "leverage", "transfer"]}, true)
		"16":
			model.merge({"verb": "recover", "relationship": "rest converts banked ATP and shelter access into reduced sleep debt and restored capacity", "cause": "the regrouped party spends ATP at a valid rest state", "effect": "recovery increases and sleep deprivation clears", "polarity": "negative", "stock": "ATP, health, stamina, and sleep debt", "flow": "rest spends ATP to restore capacity and reduce debt", "delay": "the rest interval", "feedback_loop": "poor recovery reduces future collection capacity, increasing future scarcity", "threshold": "enough ATP and safety exist for worthwhile rest", "local_vs_party_scale": "one cache decision changes the whole party's next stretch", "leverage_point": "when and where ATP is banked before rest", "likely_misconception": "rest is free or every cache must be collected", "prediction": "the banked ATP will cover the chosen recovery before the next stretch", "intervention": "regroup, compare debt with ATP, then choose the rest spend", "evidence": "ATP spent, debt cleared, and capacity restored are visible", "transfer_test": "choose recovery under a different scarcity configuration", "dimensions": ["relation", "stock", "flow", "delay", "feedback", "local_global", "threshold", "leverage", "transfer"]}, true)
		"17":
			model.merge({"verb": "diagnose", "relationship": "logistical, emotional, and structural reads constrain one shared repair model", "cause": "the party compares all perspectives instead of following the loudest symptom", "effect": "the correct load-bearing repair resolves the consequence", "polarity": "mixed", "stock": "verified evidence", "flow": "each perspective adds or rules out causal explanations", "delay": "wrong repairs create a bounded setback before revision", "feedback_loop": "a wrong model produces evidence that should revise the next model", "threshold": "one explanation accounts for all three reads", "local_vs_party_scale": "each character sees a local truth; the party needs their intersection", "leverage_point": "the relation shared by all three reads", "likely_misconception": "the most urgent-looking symptom is the root cause", "prediction": "the chosen repair will explain and change all three observed states", "intervention": "state the model, commit one repair, then compare every predicted effect", "evidence": "predictions and all three post-repair reads remain available", "transfer_test": "diagnose a reskinned system with one perspective hidden from each character", "dimensions": ["relation", "stock", "flow", "delay", "feedback", "local_global", "topology", "diagnosis", "leverage", "transfer"]}, true)
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
