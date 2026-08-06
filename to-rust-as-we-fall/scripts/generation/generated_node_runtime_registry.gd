class_name GeneratedNodeRuntimeRegistry
extends RefCounted

## Honest runtime boundary for archetype-based stretch nodes.
##
## Archetypes are valuable inputs to layout, dressing, and authored encounter work,
## but an archetype description is not itself a mechanic. Only handlers listed here
## may create a generated-node interaction or participate in generated progression.
## Adding a handler therefore requires a real runtime implementation, not just cursor
## copy or a metadata state flip.

const HANDLER_NONE := ""
const HANDLER_PHYSICAL_LYSATE := "physical_lysate_pickup_v1"
const HANDLER_PHYSICAL_PAYLOAD := "physical_carried_payload_v1"
const HANDLER_CANONICAL_SHELTER_ARRIVAL := "canonical_shelter_arrival_v1"
const HANDLER_HYDRAULIC_SPILLWAY := "authored_hydraulic_spillway_food_v1"

const HYDRAULIC_SPEC_ID := "generated_teaching_channels_shelter_1_to_2"

const IMPLEMENTED_HANDLERS := {
	HANDLER_PHYSICAL_LYSATE: true,
	HANDLER_PHYSICAL_PAYLOAD: true,
	HANDLER_CANONICAL_SHELTER_ARRIVAL: true,
	HANDLER_HYDRAULIC_SPILLWAY: true,
}

# A palette entry describes a design-system noun; it does not prove that the
# generated-stretch presenter can instantiate that noun's gameplay contract.
# Keep this binding list deliberately narrow. Adding an entry means the runtime
# object exists, owns the advertised verb, and participates in save/replay.
const GENERATED_CONTENT_BINDINGS := {
	"flora": {
		"capbage": "capbage_concealment_v1",
		"scarpet": "scarpet_concealment_v1",
		"hushbloom": "hushbloom_proximity_stun_v1",
	},
}

const CONTENT_NAVIGATION_INTERACTABLE := "interactable"
const CONTENT_NAVIGATION_OCCUPIABLE := "occupiable"

# This is part of the runtime binding, not generator decoration. Capbage keeps
# a broad, forgiving click hull around its head, but its accepted arrival region
# is the tight cell physically inside the plant. Scarpet and generated
# (non-pickable) Hushbloom are entered bodily to produce their effect.
const GENERATED_CONTENT_NAVIGATION := {
	"flora": {
		"capbage": {
			"kind": CONTENT_NAVIGATION_INTERACTABLE,
			"interaction_radius": 1.4,
			"radius": 0.45,
			"arrival_policy": "primary_then_nearest",
			"requires_content_vertex": true,
		},
		"scarpet": {
			"kind": CONTENT_NAVIGATION_OCCUPIABLE,
			"radius": 1.65,
		},
		"hushbloom": {
			"kind": CONTENT_NAVIGATION_OCCUPIABLE,
			"radius": 1.5,
		},
	},
}


static func generated_content_binding(category: String, content_id: String) -> String:
	var category_bindings: Variant = GENERATED_CONTENT_BINDINGS.get(category, {})
	if not (category_bindings is Dictionary):
		return ""
	return str((category_bindings as Dictionary).get(content_id, ""))


static func generated_content_is_realized(category: String, content_id: String) -> bool:
	return generated_content_binding(category, content_id) != ""


static func generated_content_navigation(category: String, content_id: String) -> Dictionary:
	var category_navigation: Variant = GENERATED_CONTENT_NAVIGATION.get(category, {})
	if not (category_navigation is Dictionary):
		return {}
	var navigation: Variant = (category_navigation as Dictionary).get(content_id, {})
	return (navigation as Dictionary).duplicate(true) if navigation is Dictionary else {}


static func generated_content_omission(category: String, content_id: String) -> Dictionary:
	return {
		"category": category,
		"id": content_id,
		"reason": "missing_generated_runtime_binding",
		"message": (
			"%s is omitted from playable generation because it has no generated runtime binding."
			% content_id
		),
	}


static func handler_for_node(node: Dictionary, spec_id := "") -> String:
	var node_id := str(node.get("id", ""))
	var role := str(node.get("role", ""))
	if node_id == "exit_shelter" or role in ["shelter", "shelter_arrival"]:
		return HANDLER_CANONICAL_SHELTER_ARRIVAL
	if spec_id == HYDRAULIC_SPEC_ID and node_id == "node_04":
		return HANDLER_HYDRAULIC_SPILLWAY
	if (
		str(node.get("survival_kind", "")) == "forage"
		or str(node.get("reward_kind", "")) == "food"
		or str(node.get("resource_kind", "")) == "food"
	):
		return HANDLER_PHYSICAL_LYSATE
	# A generated carry beat is actionable only when it owns a real payload. The
	# runtime creates that item, occupies a carrier hand, and requires the same item
	# at shelter delivery; an archetype label alone never enters this registry.
	if bool(node.get("resource", false)) and bool(node.get("carry_payload", false)):
		return HANDLER_PHYSICAL_PAYLOAD
	return HANDLER_NONE


static func declared_handler(node: Dictionary) -> String:
	var direct := str(node.get("runtime_handler", "")).strip_edges()
	if direct != "":
		return direct
	var section: Dictionary = node.get("playable_section", {})
	return str(section.get("runtime_handler", "")).strip_edges()


static func is_implemented(handler_id: String) -> bool:
	return IMPLEMENTED_HANDLERS.has(handler_id)


static func node_is_actionable(node: Dictionary, spec_id := "") -> bool:
	return handler_for_node(node, spec_id) != HANDLER_NONE


static func action_label(handler_id: String) -> String:
	match handler_id:
		HANDLER_PHYSICAL_LYSATE:
			return "TAKE LYSATE"
		HANDLER_PHYSICAL_PAYLOAD:
			return "TAKE LOAD"
		HANDLER_CANONICAL_SHELTER_ARRIVAL:
			return "ENTER SHELTER"
		HANDLER_HYDRAULIC_SPILLWAY:
			return "CATCH LYSATE"
	return ""


static func initial_action_label(node: Dictionary, handler_id := "") -> String:
	var resolved_handler := handler_id if handler_id != "" else handler_for_node(node)
	return action_label(resolved_handler)


static func handler_approach(handler_id: String) -> Dictionary:
	match handler_id:
		HANDLER_PHYSICAL_LYSATE:
			return {
				"approach_id": "take_physical_lysate",
				"kind": "resource_pickup",
				"party": "any",
				"risk": "safe",
				"blocked": false,
			}
		HANDLER_PHYSICAL_PAYLOAD:
			return {
				"approach_id": "carry_physical_payload",
				"kind": "physical_carry",
				"party": "any",
				"risk": "safe",
				"blocked": false,
			}
		HANDLER_CANONICAL_SHELTER_ARRIVAL:
			return {
				"approach_id": "canonical_shelter_arrival",
				"kind": "shelter_arrival",
				"party": "any",
				"risk": "safe",
				"blocked": false,
			}
		HANDLER_HYDRAULIC_SPILLWAY:
			return {
				"approach_id": "catch_hydraulic_lysate",
				"kind": "authored_hydraulic",
				"party": "any",
				"risk": "safe",
				"blocked": false,
			}
	return {}


## Only handlers whose concrete operation actually establishes the node's declared
## typed output may project semantic chain data into runtime progression. A food
## pickup inside a semantic patrol puzzle, for example, must not claim that it
## diverted the patrol merely because both facts share a generated node.
static func materializes_chain_output(handler_id: String, node: Dictionary) -> bool:
	return (
		handler_id == HANDLER_PHYSICAL_PAYLOAD
		and bool(node.get("resource", false))
		and bool(node.get("carry_payload", false))
		and _has_exact_chain_binding(node, "output")
	)


static func consumes_chain_input(handler_id: String, node: Dictionary) -> bool:
	return (
		handler_id == HANDLER_PHYSICAL_PAYLOAD
		and bool(node.get("resource", false))
		and bool(node.get("carry_payload", false))
		and _has_exact_chain_binding(node, "input")
	)


static func _has_exact_chain_binding(node: Dictionary, direction: String) -> bool:
	var binding: Dictionary = node.get("runtime_chain_binding", {})
	var semantic_ref := str(node.get("chain_%s_ref" % direction, ""))
	if semantic_ref == "" \
			or str(binding.get("%s_ref" % direction, "")) != semantic_ref:
		return false
	for key in [
		"mechanism_id",
		"physical_source_id",
		"%s_predicate" % direction,
	]:
		if str(binding.get(key, "")).strip_edges() == "":
			return false
	return true
