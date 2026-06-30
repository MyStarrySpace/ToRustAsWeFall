class_name StretchPoiDistribution
extends RefCounted

## The archetype-driven POI distribution (Layer A: per-fragment composition). Two jobs:
##  1. CRUCIAL-ELEMENT COVERAGE — every archetype in a stretch has its essential content placed somewhere, and a
##     SHARED element (one several archetypes need) is placed ONCE (dedup at the element level, not the node).
##  2. PROGRESSION-SCALED DENSITY — ambient POI count + variety grow with the stretch's stage, so a late-game
##     stretch reads as denser/richer (mastery) without changing the solver's pressure math.
##
## A "crucial element" is a content-suppliable CAPABILITY an archetype's shadow approach requires (cover, lure,
## reveal, barrier, ...). The element<->content inversion is read straight off StretchCapabilities.CONTENT_CAPABILITIES
## so there is ONE source of truth; this loader only adds the survival/variant element hints + the density knobs.

const CapsScript := preload("res://scripts/generation/stretch_capabilities.gd")
const DEFAULT_PATH := "res://data/generation/poi_distribution.json"
const SCHEMA := "trawf_poi_distribution_v1"

var survival_elements: Dictionary = {}
var variant_elements: Dictionary = {}
var density: Dictionary = {}
var _element_content: Dictionary = {}     # element key -> {"flora": [ids], "structures": [ids]}
var _loaded := false

func _init(path: String = DEFAULT_PATH) -> void:
	_build_element_content()
	load_from_file(path)

func load_from_file(path: String) -> void:
	var data := _load_json_dict(path)
	survival_elements = data.get("survival_elements", {})
	variant_elements = data.get("variant_elements", {})
	density = data.get("density", {})
	_loaded = not data.is_empty()

func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

## Invert CONTENT_CAPABILITIES (content -> caps) into element -> content, so a crucial element resolves to the
## content that can supply it. The element keys ARE the capability names; no separate authored table.
func _build_element_content() -> void:
	_element_content = {}
	for category in CapsScript.CONTENT_CAPABILITIES.keys():
		var table: Dictionary = CapsScript.CONTENT_CAPABILITIES[category]
		var bucket := "flora" if category == "flora" else "structures"
		for content_id in table.keys():
			for cap in table[content_id]:
				var key := str(cap)
				if not _element_content.has(key):
					_element_content[key] = {"flora": [], "structures": []}
				var arr: Array = _element_content[key][bucket]
				if not arr.has(str(content_id)):
					arr.append(str(content_id))

func has_element(key: String) -> bool:
	return _element_content.has(key)

## The content that can supply an element: {"flora": [ids], "structures": [ids]}.
func element_content(key: String) -> Dictionary:
	return _element_content.get(key, {"flora": [], "structures": []})

## Which element keys a placed content item satisfies (the merge key — content lights up an element that may be
## required by several archetypes). Direct read of CONTENT_CAPABILITIES.
func satisfies(category: String, content_id: String) -> Array:
	var bucket := "flora" if category == "flora" else "structures"
	var table: Dictionary = CapsScript.CONTENT_CAPABILITIES.get(bucket, {})
	var out := []
	for cap in table.get(content_id, []):
		if not out.has(str(cap)):
			out.append(str(cap))
	return out

## The crucial (content-suppliable) elements a node's archetype leans on: the union of its shadow approaches'
## content requirements, its survival kind's signature elements, and its variant flora. Character-only capabilities
## (overlay/timing/flora/...) are excluded — they ride the roster, not the placed content.
func crucial_elements_for(node: Dictionary) -> Array:
	var keys := {}
	for approach in node.get("approaches", []):
		if not (approach is Dictionary):
			continue
		var kind := str((approach as Dictionary).get("kind", ""))
		if kind != "shadow" and kind != "shadow_expert" and kind != "primary":
			continue
		for req in (approach as Dictionary).get("requires", []):
			if has_element(str(req)):
				keys[str(req)] = true
	for e in survival_elements.get(str(node.get("survival_kind", "")), []):
		if has_element(str(e)):
			keys[str(e)] = true
	var variant := str(node.get("variant", ""))
	if variant_elements.has(variant) and has_element(str(variant_elements[variant])):
		keys[str(variant_elements[variant])] = true
	return keys.keys()

# --- Progression-scaled ambient density -----------------------------------------------------------------------

func ambient_flora() -> Array:
	return density.get("ambient_flora", [])

func ambient_count(stage: int) -> int:
	var base := int(density.get("base_ambient", 1))
	var per := float(density.get("ambient_per_stage", 0.0))
	var cap := int(density.get("ambient_max", 6))
	return clampi(base + int(round(per * float(maxi(0, stage - 1)))), base, cap)

func ambient_variety(stage: int) -> int:
	var base := int(density.get("variety_base", 1))
	var per := float(density.get("variety_per_stage", 0.0))
	var cap := int(density.get("variety_max", 5))
	return clampi(base + int(round(per * float(maxi(0, stage - 1)))), base, cap)

func validate() -> Dictionary:
	var errors := []
	if not _loaded:
		errors.append("poi_distribution.json missing or empty")
	if density.is_empty():
		errors.append("density block missing")
	var flora_table: Dictionary = CapsScript.CONTENT_CAPABILITIES.get("flora", {})
	for fid in ambient_flora():
		if not flora_table.has(str(fid)):
			errors.append("ambient flora '%s' is not a known flora" % str(fid))
	for sk in survival_elements.keys():
		for e in survival_elements[sk]:
			if not has_element(str(e)):
				errors.append("survival '%s' element '%s' is not content-suppliable" % [sk, str(e)])
	for v in variant_elements.keys():
		if not has_element(str(variant_elements[v])):
			errors.append("variant '%s' element '%s' is not content-suppliable" % [v, str(variant_elements[v])])
	return {"valid": errors.is_empty(), "errors": errors, "element_count": _element_content.size()}
