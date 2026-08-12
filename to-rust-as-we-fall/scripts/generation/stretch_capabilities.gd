class_name StretchCapabilities
extends RefCounted

## What the party (and the tools it can reach) can DO, expressed as capability tags.
## The solution solver resolves an archetype approach's `requires` tags against the
## capabilities a loadout provides. The split that matters: ASTER + PERIS (the permanent
## minimum-viable pair, the "shadow" loadout) hold no SPECIALIST capability, so an approach
## that needs one is reachable only when a character who provides it is ENABLED in the
## roster — which is what makes a puzzle solvable more than one way, and always by the pair.
##
## The six playable characters are brain-cell types (GDD §3); each contributes capabilities.
## Only explicitly named, authored cast abilities belong in `abilities`. Contextual verbs such as
## Aster's hacking and Peris's tending remain capabilities resolved through world interactions.
## Named later-game commitments remain in this registry even when their general cast contract is not
## wired yet; the status keeps the generator from confusing canon identity with runtime support.
## Characters whose active kit is still unspecified expose an empty map instead of acquiring
## placeholders. The "spotlight" loadout is the union of the ENABLED roster's capabilities, so e.g.
## `combat` exists only if a microglia/T-reg fighter is enabled.

# id -> {name, cell_type, class_code, capabilities[], abilities{ id: {name, grants} }, recruit,
#        color?, move_speed?, runtime_wired?}
#
# This registry is the single character AUTHORITY, and it answers two separate questions:
#   KNOWN   — is this id a canonical cast member at all? (every canonical id has an entry)
#   CAPABLE — what does the character mechanically grant? (capabilities may be empty)
# A character can be known while granting nothing; only an id with no entry is unknown.
#
# Per-character identity attributes (color, move_speed, display name) live here too, so every
# scene table reads one authority instead of hand-copying values. `runtime_wired: false` marks
# a canon identity without a spawnable runtime kit: such ids never enter normalize_roster's
# enabled set, so naming one in a roster generates exactly as if the id were absent.
const CHARACTER_REGISTRY := {
	"aster": {
		"name": "Aster", "cell_type": "astrocyte", "class_code": "AST", "recruit": 1,
		"color": Color(0.29, 0.62, 1.0), "move_speed": 3.2,
		"capabilities": ["data", "electrical", "overlay", "terminal", "scan", "timing", "signal", "ast_class"],
		"abilities": {"emp": {"name": "EMP", "grants": "electrical"}},
	},
	"peris": {
		"name": "Peris", "cell_type": "pericyte", "class_code": "PCT", "recruit": 1,
		"color": Color(1.0, 0.67, 0.27), "move_speed": 3.0,
		"capabilities": ["flora", "carry", "physical", "protect", "cover", "tend", "pct_class"],
		"abilities": {"wrap": {"name": "Wrap", "grants": "protect"}},
	},
	"endo": {
		"name": "Endo", "cell_type": "endothelial", "class_code": "ENT", "recruit": 2,
		"color": Color(0.4, 0.72, 0.55), "move_speed": 2.8,
		"capabilities": ["barrier", "junction", "repair", "gear", "carry", "endo", "ent_class"],
		"abilities": {},
	},
	"myke": {
		"name": "Myke", "cell_type": "microglia", "class_code": "MCG", "recruit": 3,
		"color": Color(0.85, 0.36, 0.2), "move_speed": 3.1,
		"capabilities": ["redirect", "impact", "force", "carry", "physical", "tend", "class_other"],
		"abilities": {
			"inflame": {"name": "Inflame", "grants": "redirect", "runtime_status": "authored_fragment"},
		},
	},
	"oli": {
		"name": "Oli", "cell_type": "oligodendrocyte", "class_code": "OLG", "recruit": 4,
		"capabilities": ["barrier", "insulation", "terminal", "cover", "class_other"],
		"abilities": {
			"barrier": {"name": "Barrier", "grants": "barrier", "runtime_status": "canon_reserved"},
			"restore": {"name": "Restore", "grants": "field_restore", "runtime_status": "game_state"},
		},
	},
	"tyreg": {
		"name": "Tyreg", "cell_type": "T-regulatory", "class_code": "TRG", "recruit": 5,
		"capabilities": ["redirect", "force", "scan", "timing", "class_tmc"],
		"abilities": {
			"suppress": {"name": "Suppress", "grants": "redirect", "runtime_status": "authored_fragment"},
		},
	},
	# Roguelike recruits (GDD §15.4 "DLC-exclusive characters"; dlc_roguelike_mode.md).
	# Each is registered as canon IDENTITY. The GDD marks every one of these kits
	# "(preliminary)" and authors no ability against the capability tokens above, so each
	# carries an explicitly empty capability set rather than a guessed mapping. Marco's
	# roguelike persona name ("Makrov Mage") is a mode-specific label owned by
	# RunBranchDecisions.DISPLAY_NAMES, not a second canonical name.
	"marco": {
		# GDD §3.7: recurring NPC, monocyte cadet ("Monos" is the institutional tag);
		# §15.4 lists him "Marco (Macrophage)". §5.5: his institutional class is MOC.
		"name": "Marco", "cell_type": "macrophage", "class_code": "MOC", "recruit": 6,
		"capabilities": [], "abilities": {}, "runtime_wired": false,
	},
	"brobla": {
		# GDD §15.4.2 "Brobla (Fibroblast)": log-writing construction worker at the Mother
		# Flure site. §5.5 leaves the construction class code "to be assigned", so none is set.
		"name": "Brobla", "cell_type": "fibroblast", "recruit": 7,
		"capabilities": [], "abilities": {}, "runtime_wired": false,
	},
	"vasca": {
		# GDD §15.4.3 "Vasca (Vascular smooth muscle)": flow control and pathing.
		"name": "Vasca", "cell_type": "vascular smooth muscle", "recruit": 8,
		"capabilities": [], "abilities": {}, "runtime_wired": false,
	},
	"senchy": {
		# GDD §15.4.4 "Senchy (Mesenchymal)": adaptive versatility, cutting-crew survivor.
		"name": "Senchy", "cell_type": "mesenchymal", "recruit": 9,
		"capabilities": [], "abilities": {}, "runtime_wired": false,
	},
	"swan": {
		# GDD §15.4.5 "Swan (Schwann cell)": PNS insulation specialist, kit-cousin to Oli.
		"name": "Swan", "cell_type": "Schwann cell", "recruit": 10,
		"capabilities": [], "abilities": {}, "runtime_wired": false,
	},
	"ninj": {
		# GDD §15.4.6 "Ninj (Meninges)": concealment and shock absorption stances.
		"name": "Ninj", "cell_type": "meninges", "recruit": 11,
		"capabilities": [], "abilities": {}, "runtime_wired": false,
	},
	"pendy": {
		# GDD §15.4.7 "Pendy (Ependymal)": CSF circulation, fluid routes and hidden passages.
		"name": "Pendy", "cell_type": "ependymal", "recruit": 12,
		"capabilities": [], "abilities": {}, "runtime_wired": false,
	},
}

## The permanent minimum-viable pair (never depart; their overlays default ON) and the full
## canonical roster used when no explicit roster is given.
const SHADOW_PARTY := ["aster", "peris"]
const CANONICAL_ROSTER := ["aster", "peris", "endo", "myke", "oli", "tyreg"]

## Content the world can place that lends a (non-specialist) capability to whoever stands in
## the node. A shadow approach that wants "cover" is satisfiable by Peris alone, but placed
## scarpet / capbage makes it real cover; flure/hushbloom turn a node into a usable tool.
const CONTENT_CAPABILITIES := {
	"flora": {
		"scarpet": ["cover", "scarpet_cover"],
		"capbage": ["cover", "hide", "cache"],
		"hushbloom": ["stun"],
		"flure": ["lure", "iron_decoy"],
		"mother_flure": ["lure", "iron_decoy"],
		"seefern": ["reveal", "light"],
		"climbvine": ["traversal"],
		"resolution_roots": ["stabilize"],
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


## True when the id names a canonical cast member (an entry in CHARACTER_REGISTRY),
## regardless of what that character can do. Enemies and generated runtime ids are
## NOT cast members and report false.
static func is_known(id: String) -> bool:
	return CHARACTER_REGISTRY.has(str(id))


## The capabilities a single registered character provides. An UNKNOWN id is a caller
## bug (a typo, or an id the registry never learned) and reports loudly; a KNOWN
## character whose kit grants nothing returns an empty set silently — unknown and
## known-but-plain must never look identical.
static func character_capabilities(id: String) -> Array:
	var key := str(id)
	if not CHARACTER_REGISTRY.has(key):
		push_error("StretchCapabilities.character_capabilities: unknown character id '%s'" % key)
		return []
	return (CHARACTER_REGISTRY[key] as Dictionary).get("capabilities", [])


## The character's display name (the roguelike persona layer may override it per mode).
static func display_name(id: String) -> String:
	return str((CHARACTER_REGISTRY.get(str(id), {}) as Dictionary).get("name", str(id).capitalize()))


## The character's ownership tint (portraits, path ribbons, queued-interaction glow).
static func character_color(id: String, fallback := Color(0.68, 0.72, 0.78)) -> Color:
	var value: Variant = (CHARACTER_REGISTRY.get(str(id), {}) as Dictionary).get("color", null)
	return value if value is Color else fallback


## The character's base walk speed in world units per second.
static func move_speed(id: String, fallback := 3.0) -> float:
	var value: Variant = (CHARACTER_REGISTRY.get(str(id), {}) as Dictionary).get("move_speed", null)
	return float(value) if (value is float or value is int) else fallback


## A per-character attribute table ({id: value}) for scene code that wants a dictionary
## in hand (portrait loops, speed lookups). Ids whose entry does not define the attribute
## are omitted rather than defaulted, so a built table mirrors exactly what is authored.
static func attribute_table(ids: Array, attribute: String) -> Dictionary:
	var out := {}
	for id in ids:
		var entry: Dictionary = CHARACTER_REGISTRY.get(str(id), {})
		if entry.has(attribute):
			out[str(id)] = entry[attribute]
	return out


## SPECIALIST capabilities = any capability NO bare-pair member (Aster/Peris) provides on
## their own — so they can only come from an ENABLED specialist character, never from the
## pair or from placed content. Derived from the roster, not a hand-kept list: a capability
## is "specialist" only while a character who provides it is actually enabled, so disabling
## the last fighter stops `combat` being treated as a protected specialist tag. An empty
## roster means the full canonical six (the default), so callers that pass nothing get the
## same set as before.
static func specialist_capabilities(roster = []) -> Dictionary:
	var pair := bare_pair_capabilities()
	var spec := {}
	for id in (normalize_roster(roster).get("enabled", []) as Array):
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
			_add_known(enabled, str(id))
	elif roster is Dictionary and (roster as Dictionary).has("enabled"):
		for id in (roster as Dictionary).get("enabled", []):
			_add_known(enabled, str(id))
	else:
		enabled = CANONICAL_ROSTER.duplicate()
	for id in SHADOW_PARTY:
		if not enabled.has(id):
			enabled.append(id)
	return {"enabled": enabled}


## Append a roster id only if it is a runtime-wired cast character and not already present —
## an unknown id (typo, stale save) is dropped so it can never become a ghost party member,
## and a known identity without a spawnable runtime kit (`runtime_wired: false`) is held out
## of the enabled set so naming it changes nothing about generation.
static func _add_known(enabled: Array, id: String) -> void:
	var entry: Dictionary = CHARACTER_REGISTRY.get(id, {})
	if not entry.is_empty() and bool(entry.get("runtime_wired", true)) and not enabled.has(id):
		enabled.append(id)


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
		for cap in specialist_capabilities(character_ids).keys():
			caps[str(cap)] = true
	return caps


## Capability tags lent by content (flora/structures) placed on a node — plus the
## "enemies as a tool" hook: a survival exploit node (an enemy-vs-enemy configuration) lends
## a `redirect`/`exploit` affordance an approach can spend. Placed content never grants a
## SPECIALIST capability (those belong to a character), so a placed barrier can't hand the
## pair a specialist's approach and collapse a node's specialist-vs-shadow choice.
static func node_content_capabilities(node: Dictionary, roster = []) -> Dictionary:
	var caps := {}
	var specialist := specialist_capabilities(roster)
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
