class_name StretchCapabilities
extends RefCounted

## What the party (and the tools it can reach) can DO, expressed as capability tags.
## The solution solver resolves an archetype approach's `requires` tags against the
## capabilities a loadout provides. The split that matters: ASTER + PERIS (the permanent
## minimum-viable pair, the "shadow" loadout) hold no SPECIALIST capability, so an approach
## that needs one is reachable only when a character who provides it is ENABLED in the
## roster — which is what makes a puzzle solvable more than one way, and always by the pair.
##
## The six playable characters are brain-cell types (GDD §3); each contributes capabilities
## and abilities. The "spotlight" loadout is the union of the ENABLED roster's capabilities,
## so e.g. `combat` exists only if a microglia/T-reg fighter (Myke/Tyreg) is enabled.

# id -> {name, cell_type, class_code, capabilities[], abilities{ id: {name, grants} }, recruit}
const CHARACTER_REGISTRY := {
	"aster": {
		"name": "Aster", "cell_type": "astrocyte", "class_code": "AST", "recruit": 1,
		"capabilities": ["data", "electrical", "overlay", "terminal", "scan", "timing", "signal", "ast_class"],
		"abilities": {"emp": {"name": "EMP Hack", "grants": "electrical"}},
	},
	"peris": {
		"name": "Peris", "cell_type": "pericyte", "class_code": "PCT", "recruit": 1,
		"capabilities": ["flora", "carry", "physical", "protect", "cover", "tend", "pct_class"],
		"abilities": {"protect": {"name": "Protect / Wrap", "grants": "protect"}, "harvest": {"name": "Harvest", "grants": "flora"}},
	},
	"endo": {
		"name": "Endo", "cell_type": "endothelial", "class_code": "ENT", "recruit": 2,
		"capabilities": ["barrier", "junction", "repair", "gear", "carry", "endo", "ent_class"],
		"abilities": {"no_pulse": {"name": "NO Pulse", "grants": "endo"}, "cloak": {"name": "Cloak", "grants": "endo"}},
	},
	"myke": {
		"name": "Myke", "cell_type": "microglia", "class_code": "MCG", "recruit": 3,
		"capabilities": ["combat", "impact", "force", "carry", "physical", "tend", "class_other"],
		"abilities": {"inflame": {"name": "Inflame", "grants": "combat"}, "engulf": {"name": "Engulf", "grants": "impact"}},
	},
	"oli": {
		"name": "Oli", "cell_type": "oligodendrocyte", "class_code": "OLG", "recruit": 4,
		"capabilities": ["barrier", "insulation", "terminal", "electrical", "cover", "class_other"],
		"abilities": {"sheath": {"name": "Sheath", "grants": "barrier"}, "conduct": {"name": "Conduct", "grants": "electrical"}},
	},
	"tyreg": {
		"name": "Tyreg", "cell_type": "T-regulatory", "class_code": "TRG", "recruit": 5,
		"capabilities": ["combat", "force", "scan", "timing", "class_tmc"],
		"abilities": {"shoot": {"name": "Shoot", "grants": "force"}, "suppress": {"name": "Suppress", "grants": "combat"}},
	},
}

## The permanent minimum-viable pair (never depart; their overlays default ON) and the full
## canonical roster used when no explicit roster is given.
const SHADOW_PARTY := ["aster", "peris"]
const CANONICAL_ROSTER := ["aster", "peris", "endo", "myke", "oli", "tyreg"]

## Content the world can place that lends a (non-specialist) capability to whoever stands in
## the node. A shadow approach that wants "cover" is satisfiable by Peris alone, but placed
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


## The capabilities a single registered character provides.
static func character_capabilities(id: String) -> Array:
	return (CHARACTER_REGISTRY.get(str(id), {}) as Dictionary).get("capabilities", [])


## SPECIALIST capabilities = any capability NO bare-pair member (Aster/Peris) provides on
## their own — so they can only come from an enabled specialist character, never from the
## pair or from placed content. Derived from the registry, not a hand-kept list.
static func specialist_capabilities() -> Dictionary:
	var pair := bare_pair_capabilities()
	var spec := {}
	for id in CHARACTER_REGISTRY.keys():
		for cap in character_capabilities(str(id)):
			if not pair.has(str(cap)):
				spec[str(cap)] = true
	return spec


## Normalize a roster to {enabled: [ids]}. Accepts a bare id Array (those enabled), a dict
## {enabled: [...]}, or empty/null (the full canonical roster). The minimum pair is always
## present — Aster and Peris never leave.
static func normalize_roster(roster) -> Dictionary:
	var enabled := []
	if roster is Array and not (roster as Array).is_empty():
		for id in roster:
			if not enabled.has(str(id)):
				enabled.append(str(id))
	elif roster is Dictionary and (roster as Dictionary).has("enabled"):
		for id in (roster as Dictionary).get("enabled", []):
			if not enabled.has(str(id)):
				enabled.append(str(id))
	else:
		enabled = CANONICAL_ROSTER.duplicate()
	for id in SHADOW_PARTY:
		if not enabled.has(id):
			enabled.append(id)
	return {"enabled": enabled}


## The combined capability set of an enabled roster.
static func roster_capabilities(roster) -> Dictionary:
	var caps := {}
	for id in (normalize_roster(roster).get("enabled", []) as Array):
		for cap in character_capabilities(str(id)):
			caps[str(cap)] = true
	return caps


## Capabilities Aster + Peris hold on their own, with NO placed tool — the universal floor
## every archetype's shadow approach must satisfy, so the pair can always finish.
static func bare_pair_capabilities() -> Dictionary:
	var caps := {}
	for id in SHADOW_PARTY:
		for cap in character_capabilities(id):
			caps[str(cap)] = true
	return caps


## Back-compat: capabilities of a set of character ids; `include_specialist` adds every
## derived specialist tag (the full-strength party able to take any primary approach).
static func party_capabilities(character_ids: Array, include_specialist := false) -> Dictionary:
	var caps := roster_capabilities(character_ids)
	if include_specialist:
		for cap in specialist_capabilities().keys():
			caps[str(cap)] = true
	return caps


## Capability tags lent by content (flora/structures) placed on a node — plus the
## "enemies as a tool" hook: a survival exploit node (an enemy-vs-enemy configuration) lends
## a `redirect`/`exploit` affordance an approach can spend. Placed content never grants a
## SPECIALIST capability (those belong to a character), so a placed barrier can't hand the
## pair a specialist's approach and collapse a node's specialist-vs-shadow choice.
static func node_content_capabilities(node: Dictionary) -> Dictionary:
	var caps := {}
	var specialist := specialist_capabilities()
	for category in ["flora", "structures"]:
		var table: Dictionary = CONTENT_CAPABILITIES.get(category, {})
		for raw_key in node.get(category, []):
			for cap in table.get(str(raw_key), []):
				if not specialist.has(str(cap)):
					caps[str(cap)] = true
	if str(node.get("survival_kind", "")) == "exploit":
		caps["redirect"] = true
		caps["exploit"] = true
	return caps


## True when every required tag is present in `available` (a {tag: true} set).
static func requirements_met(required: Array, available: Dictionary) -> bool:
	for tag in required:
		if not available.has(str(tag)):
			return false
	return true


## The two loadouts the solver evaluates, in order (spotlight first so it prefers a
## specialist primary). The SPOTLIGHT is the union of the ENABLED roster's capabilities, so
## restricting the roster (the enable/disable options) genuinely changes what's solvable; the
## SHADOW is always the Aster+Peris pair and is never stage-gated (a mastery run).
static func loadouts(roster = []) -> Array:
	var norm := normalize_roster(roster)
	return [
		{
			"id": "spotlight",
			"label": "Full party",
			"party": norm["enabled"],
			"base_capabilities": roster_capabilities(norm["enabled"]),
			"enforce_stage": true,
		},
		{
			"id": "shadow",
			"label": "Aster + Peris (shadow)",
			"party": SHADOW_PARTY,
			"base_capabilities": bare_pair_capabilities(),
			"enforce_stage": false,
		},
	]
