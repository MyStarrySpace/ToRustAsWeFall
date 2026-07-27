class_name SpeciesCatalog
extends RefCounted

## Placeable flora and fauna for the sketch tool, mirroring the game's roster
## (flora_taxonomy.md, enemy_ecosystem.md). Each entry: id (stored as an object's
## "kind"), display name, and a sketch colour grounded in the species' biology.
## Both the brush palette (editor) and the renderer (GridView) read from here.

const FLORA := [
	{"id": "seefern", "name": "Seefern", "color": Color(0.40, 0.85, 0.60)},          # bioluminescent teal
	{"id": "scarpet", "name": "Scarpet", "color": Color(0.58, 0.50, 0.30)},          # rust-mottled moss
	{"id": "flure", "name": "Flure", "color": Color(0.82, 0.45, 0.22)},              # iron-bronze decoy bloom
	{"id": "hushbloom", "name": "Hushbloom", "color": Color(0.72, 0.60, 0.88)},      # pale lavender stun
	{"id": "capbage", "name": "Capbage", "color": Color(0.26, 0.52, 0.34)},          # deep cabbage green
	{"id": "gasafoetida", "name": "Gasafoetida", "color": Color(0.80, 0.72, 0.32)},  # sulfur amber
	{"id": "climbvine", "name": "Climbvine", "color": Color(0.46, 0.55, 0.36)},      # vine brown-green
	{"id": "forget_me_nots", "name": "Forget-me-nots", "color": Color(0.45, 0.62, 0.95)},  # ambient blue
	{"id": "mother_flure", "name": "Mother Flure", "color": Color(0.68, 0.30, 0.28)},      # set-piece rust-red
	{"id": "resolution_roots", "name": "Resolution Roots", "color": Color(0.72, 0.66, 0.48)},  # pale warm puzzle flora
]

const FAUNA := [
	{"id": "sapscraps", "name": "Sapscraps", "color": Color(0.62, 0.22, 0.48)},            # iron-enterobactin red-violet
	{"id": "aembers", "name": "Aembers", "color": Color(0.62, 0.85, 0.30)},        # fluorescent chartreuse
	{"id": "hidras", "name": "Hidras", "color": Color(0.52, 0.50, 0.40)},            # grey-bronze pipe-mimic
	{"id": "crusts", "name": "Crusts", "color": Color(0.72, 0.62, 0.46)},            # cream-rust biofilm mat
	{"id": "candids", "name": "Candids", "color": Color(0.85, 0.82, 0.58)},          # pale yeast-cream
	{"id": "meebs", "name": "Meebs", "color": Color(0.55, 0.68, 0.58)},              # translucent green-grey amoeba
	{"id": "naturalizers", "name": "Naturalizers", "color": Color(0.46, 0.56, 0.74)},  # NK grey-blue carapace
	{"id": "gnawers", "name": "Gnawers", "color": Color(0.45, 0.20, 0.24)},          # heme-dark hunter
	{"id": "flares", "name": "Flares", "color": Color(0.90, 0.74, 0.42)},          # inflammatory amber burster
	{"id": "spikers", "name": "Spikers", "color": Color(0.56, 0.82, 0.80)},          # pale teal neuron
	{"id": "tanglers", "name": "Tanglers", "color": Color(0.42, 0.44, 0.26)},        # dark olive tau-helix
	{"id": "toxos", "name": "Toxos", "color": Color(0.60, 0.46, 0.46)},              # grey-red crescent
	{"id": "redactors", "name": "Redactors", "color": Color(0.58, 0.62, 0.66)},          # ghost-pale cloaked enforcer
]

const _DEFAULT_FLORA_COLOR := Color(0.33, 0.72, 0.36)
const _DEFAULT_FAUNA_COLOR := Color(0.88, 0.56, 0.20)

static func all_flora() -> Array:
	return FLORA

static func all_fauna() -> Array:
	return FAUNA

static func _find(kind: String) -> Dictionary:
	for e in FLORA:
		if e["id"] == kind:
			return e
	for e in FAUNA:
		if e["id"] == kind:
			return e
	return {}

## "flora" | "fauna" | "" (for non-species kinds like shelter / blockin).
static func category_of(kind: String) -> String:
	for e in FLORA:
		if e["id"] == kind:
			return "flora"
	for e in FAUNA:
		if e["id"] == kind:
			return "fauna"
	# Generic fallbacks for legacy/unknown kinds.
	if kind == "flora":
		return "flora"
	if kind == "fauna":
		return "fauna"
	return ""

static func display_name(kind: String) -> String:
	var e := _find(kind)
	if not e.is_empty():
		return str(e["name"])
	return kind.capitalize()

static func color_of(kind: String) -> Color:
	var e := _find(kind)
	if not e.is_empty():
		return e["color"]
	match category_of(kind):
		"fauna": return _DEFAULT_FAUNA_COLOR
		_: return _DEFAULT_FLORA_COLOR
