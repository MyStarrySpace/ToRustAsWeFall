class_name StretchCapabilities
extends RefCounted

## What a party (and the tools it can reach) can DO, expressed as capability tags.
## The solution solver resolves an archetype approach's `requires` tags against the
## capabilities a given loadout provides. The split that matters: ASTER + PERIS (the
## minimum-viable pair, the "shadow" loadout) never provide a SPECIALIST capability
## (combat / Endo / a non-AST class), so any approach that needs one is reachable only
## by the spotlight loadout — which is exactly what makes a puzzle solvable more than
## one way, and always by the pair.

const CHARACTER_CAPABILITIES := {
	"aster": ["data", "electrical", "overlay", "terminal", "scan", "timing", "signal", "ast_class"],
	"peris": ["flora", "carry", "physical", "protect", "cover", "tend", "pct_class"],
	"endo": ["barrier", "junction", "repair", "gear", "carry", "endo", "ent_class"],
}

## Capabilities only a spotlight specialist brings (a combat class, a non-AST class
## bearer, Endo's structural work). The shadow pair has NONE of these.
const SPECIALIST_CAPABILITIES := [
	"combat", "impact", "force",
	"endo", "barrier", "junction", "repair", "gear",
	"class_other", "class_ent", "class_tmc",
]

## Content the world can place that lends a capability to whoever stands in the node.
## A shadow approach that wants "cover" is satisfiable by Peris alone, but placed
## scarpet / doma makes it real cover; flure/hushbloom turn a node into a usable tool.
const CONTENT_CAPABILITIES := {
	"flora": {
		"scarpet": ["cover", "scarpet_cover"],
		"doma": ["cover", "hide"],
		"snapbloom": ["cover", "repellent"],
		"hushbloom": ["stun"],
		"flure": ["lure", "iron_decoy"],
		"mother_flure": ["lure", "iron_decoy"],
		"seefern": ["reveal", "light"],
		"climbvine": ["traversal"],
		"resolution_roots": ["stabilize"],
		"gasafoetida": ["combustible"],
		"capbage": ["forage"],
		"forget_me_nots": ["memory"],
	},
	"structures": {
		"terminal": ["terminal"],
		"class_gate": ["class_gate"],
		"barrier": ["barrier"],
		"junction": ["junction"],
		"shortcut_gate": ["shortcut"],
		"root_slide": ["traversal"],
		"hide_slot": ["hide", "cover"],
		"forage_cache": ["forage"],
		"water_control": ["wash"],
		"carry_gear": ["carry"],
		"workbench": ["repair"],
		"membrane": ["gate"],
		"pipe": ["channel"],
	},
}

## Canonical loadouts the solver evaluates. "spotlight" is the intended full-party
## solve (everything available, including a specialist); "shadow" is the Aster+Peris
## minimum-viable pair.
const SPOTLIGHT_PARTY := ["aster", "peris", "endo"]
const SHADOW_PARTY := ["aster", "peris"]


## All capability tags a set of character ids provides. `include_specialist` adds the
## spotlight-only specialist tags (so the full party can take a primary/combat approach).
static func party_capabilities(character_ids: Array, include_specialist := false) -> Dictionary:
	var caps := {}
	for raw_id in character_ids:
		var id := str(raw_id).to_lower()
		for cap in CHARACTER_CAPABILITIES.get(id, []):
			caps[str(cap)] = true
	if include_specialist:
		for cap in SPECIALIST_CAPABILITIES:
			caps[str(cap)] = true
	return caps


## Capability tags lent by the content (flora/structures) actually placed on a node.
static func node_content_capabilities(node: Dictionary) -> Dictionary:
	var caps := {}
	for category in ["flora", "structures"]:
		var table: Dictionary = CONTENT_CAPABILITIES.get(category, {})
		for raw_key in node.get(category, []):
			for cap in table.get(str(raw_key), []):
				caps[str(cap)] = true
	return caps


## True when every required tag is present in `available` (a {tag: true} set).
static func requirements_met(required: Array, available: Dictionary) -> bool:
	for tag in required:
		if not available.has(str(tag)):
			return false
	return true


## The two canonical loadouts, resolved to capability sets, in solver order
## (spotlight first so it prefers the primary/specialist approach).
static func loadouts() -> Array:
	return [
		{
			"id": "spotlight",
			"label": "Full party",
			"party": SPOTLIGHT_PARTY,
			"base_capabilities": party_capabilities(SPOTLIGHT_PARTY, true),
		},
		{
			"id": "shadow",
			"label": "Aster + Peris (shadow)",
			"party": SHADOW_PARTY,
			"base_capabilities": party_capabilities(SHADOW_PARTY, false),
		},
	]
