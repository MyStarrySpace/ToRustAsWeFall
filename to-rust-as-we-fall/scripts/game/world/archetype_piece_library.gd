class_name ArchetypePieceLibrary
extends RefCounted

## Visual BODIES for the generation content vocabulary — one modeled paintlib piece
## per structures key in data/generation/content_palette.json, plus the flora with
## real generated runtime bindings. Source: blender/archetypes/build_archetype_pieces.py
## (editable .blend + BlockBench round-trip), exported to archetype_pieces.gltf.
##
## THE HONESTY LAW (GeneratedNodeRuntimeRegistry): a piece is a body, never a verb.
## Consumers attach one where the noun's gameplay contract already exists — an
## authored mechanic's visual, or a content id the runtime registry binds. A clone
## carries meshes only: no collision, no Interactable, no promise.

const SCENE_PATH := "res://resources/models/archetypes/archetype_pieces.gltf"

## content id -> gltf piece node name. Coverage is LAW: every structures key and
## every runtime-bound flora id resolves here, and every entry here is a known
## content id — --test-archetype-pieces asserts both directions.
const MANIFEST := {
	"barrier": "Barrier", "carry_gear": "CarryGear", "class_gate": "ClassGate",
	"forage_cache": "ForageCache", "hide_slot": "HideSlot", "junction": "Junction",
	"membrane": "Membrane", "pipe": "Pipe", "portal": "Portal",
	"root_slide": "RootSlide", "shelter": "Shelter", "shortcut_gate": "ShortcutGate",
	"terminal": "Terminal", "water_control": "WaterControl", "workbench": "Workbench",
	"moving_platform": "MovingPlatform", "rising_water_crossing": "RisingWaterCrossing",
	"capbage": "Capbage", "scarpet": "Scarpet", "hushbloom": "Hushbloom",
	"flure": "Flure", "seefern": "Seefern", "climbvine": "Climbvine",
	"gasafoetida": "Gasafoetida", "forget_me_nots": "ForgetMeNots",
	"resolution_roots": "ResolutionRoots", "mother_flure": "MotherFlure",
}

## DRESSING pieces — level-visual props decomposed from a level's concept plates
## (docs/CHANNELS_CONCEPT.md prop audit), NOT generation vocabulary. Same body law
## (mesh-only, no verbs), same gltf, but deliberately OUTSIDE the content palette:
## a dressing id must never become a generation noun (--test-archetype-pieces
## asserts the separation both ways).
const DRESSING_MANIFEST := {
	"vein_trunk": "VeinTrunk", "biolume_cluster": "BiolumeCluster",
	"porthole": "Porthole",
	"deck_planks": "DeckPlanks", "deck_grate": "DeckGrate",
	"wall_tracery": "WallTracery", "door_ironband": "DoorIronband",
	"red_bar_lamp": "RedBarLamp", "gate_sign": "GateSign",
	"portal_ring_ornate": "PortalRingOrnate", "portal_console": "PortalConsole",
	"portal_pad_rings": "PortalPadRings", "ball_joint_pipe": "BallJointPipe",
	"water_channel": "WaterChannel", "reservoir_platform": "ReservoirPlatform",
	"broken_pier": "BrokenPier",
	"scaffold_truss": "ScaffoldTruss", "scaffold_leg": "ScaffoldLeg",
	"railing_run": "RailingRun", "pipe_rack": "PipeRack",
	"wall_panel_tile": "WallPanelTile",
	"deck_planks_b": "DeckPlanksB", "deck_planks_c": "DeckPlanksC",
	"deck_grate_b": "DeckGrateB",
	"wall_panel_tile_b": "WallPanelTileB", "wall_panel_tile_c": "WallPanelTileC",
	"water_surface": "WaterSurface", "channel_collar": "ChannelCollar",
	"drum_shell": "DrumShell",
	"pipe_straight": "PipeStraight", "pipe_elbow": "PipeElbow",
	"pipe_tee": "PipeTee", "pipe_cross": "PipeCross", "pipe_end": "PipeEnd",
	"pipe_straight_banded": "PipeStraightBanded",
	"pipe_straight_valve": "PipeStraightValve",
	"sapscrap_body": "SapscrapBody", "drum_crown": "DrumCrown",
	"pipe_bracket": "PipeBracket", "cage_lamp": "CageLamp",
	"water_channel_b": "WaterChannelB", "water_channel_c": "WaterChannelC",
	"water_band_deck": "WaterBandDeck", "water_band_trough": "WaterBandTrough",
	"water_band_deck_b": "WaterBandDeckB", "water_band_deck_c": "WaterBandDeckC",
	"water_band_trough_b": "WaterBandTroughB", "water_band_trough_c": "WaterBandTroughC",
	"deck_sluice": "DeckSluice",
	"deck_sluice_b": "DeckSluiceB", "deck_sluice_c": "DeckSluiceC",
	# The warning-leavings register — what a damaging route wears (the route-class
	# law). This world's "bones" are dead flora (flora_taxonomy.md ambient register,
	# the GDD flure dying states): a dead flure still baits siderophores, so the
	# warning is the ecology telling the truth. SapscrapBody above is the register's
	# carcass read.
	"vine_skeleton": "VineSkeleton", "dead_flure": "DeadFlure",
	# Channels biome feature vocabulary ("valve bank" — biomes.gd theme).
	"valve_bank": "ValveBank",
}

## DISTRICT piece sets — an archetype is the abstract gameplay noun; a district
## STYLES it. The Plumbing Power Project renders `water_control` as rusted hydraulics;
## the Stacks will render the same noun as drawer-stack furniture. So geometry is
## resolved through the ACTIVE district's set FIRST, with the archetype gltf as the
## fallback for nouns that district has not styled yet. Adding a district is adding
## one entry here plus its `<district>_pieces` Blender file.
##
## A district set also protects hand-modeled work: the archetype batch regen owns
## only its own gltf, so it can never clobber a district piece (the portal family
## wore a rejected batch read for weeks when the chain owned those ids).
const DISTRICT_PIECES := {
	"channels": {
		"path": "res://resources/models/channels/channels_pieces.gltf",
		"pieces": {
			"portal_ring_ornate": "PortalArch",
			"portal_pad_rings": "PortalPadRing",
			# The district's grate draws its weave as an alpha card instead of
			# modelling the bars; the archetype set keeps the modeled one for
			# districts that have not been styled yet.
			"deck_grate": "DeckGrate",
			"vine_skeleton": "VineSkeleton",
			"dead_flure": "DeadFlure",
			"valve_bank": "ValveBank",
		},
	},
	# The Open Files Initiative styles the SAME nouns as records furniture: the
	# terminal is a reading kiosk, the barrier is a stack of drawers, carried gear
	# is a file case, a junction branches references instead of pipes. Adding this
	# district was one entry here and one Blender file — which is the whole point
	# of splitting the archetype from its styling.
	"stacks": {
		"path": "res://resources/models/stacks/stacks_pieces.gltf",
		"pieces": {
			"terminal": "Terminal",
			"barrier": "Barrier",
			"carry_gear": "CarryGear",
			"junction": "Junction",
			"scan_arch": "ScanArch",
			"drawer_spire": "DrawerSpire",
		},
	},
}

## The district whose styling piece lookups resolve through. Act 1 is the Channels;
## a scene set elsewhere calls `set_district()` as it builds.
static var _district: String = "channels"


static func set_district(district_id: String) -> void:
	_district = district_id


static func get_district() -> String:
	return _district


## {path, node} for `content_id`, preferring the ACTIVE district's styling. A piece
## that only one district defines — its own feature vocabulary, like the Open Files'
## scan arch — still resolves from wherever it lives, because the alternative is a
## caller that must know which district owns a noun before it can ask for it.
## Returns {} only when no district styles the id, and the archetype set answers.
static func _district_source(content_id: String) -> Dictionary:
	var active: Dictionary = DISTRICT_PIECES.get(_district, {})
	var pieces: Dictionary = active.get("pieces", {})
	if pieces.has(content_id):
		return {"path": str(active["path"]), "node": str(pieces[content_id])}
	# Another district's styling is NEVER borrowed for a noun the archetype set can
	# answer — that would put the Open Files' reading kiosk in the Channels the
	# moment the Open Files existed. The one exception is an id no shared manifest
	# knows: a district's own feature vocabulary lives only in its file, so it
	# resolves from there or nowhere.
	if MANIFEST.has(content_id) or DRESSING_MANIFEST.has(content_id):
		return {}
	for district_id in DISTRICT_PIECES.keys():
		var set_data: Dictionary = DISTRICT_PIECES[district_id]
		var owned: Dictionary = set_data.get("pieces", {})
		if owned.has(content_id):
			return {"path": str(set_data["path"]), "node": str(owned[content_id])}
	return {}

# Only the PackedScene is cached; each call instantiates, clones the named
# piece, and frees the scratch instance — a live never-in-tree template Node
# would leak 19 nodes at every process exit.
static var _packed: PackedScene = null
static var _override_packed: Dictionary = {}   # path -> PackedScene

static func _ensure_packed() -> PackedScene:
	if _packed != null:
		return _packed
	var packed = load(SCENE_PATH)
	if packed == null or not (packed is PackedScene):
		push_warning("ArchetypePieceLibrary: cannot load %s" % SCENE_PATH)
		return null
	_packed = packed as PackedScene
	return _packed

static func has_piece(content_id: String) -> bool:
	return (MANIFEST.has(content_id) or DRESSING_MANIFEST.has(content_id)
		or not _district_source(content_id).is_empty())


## Every id a district styles that the shared manifests do not name — a district's
## own feature vocabulary (the Open Files' scan arch, its drawer spire).
static func district_only_ids() -> Array:
	var out: Array = []
	for district_id in DISTRICT_PIECES.keys():
		for content_id in (DISTRICT_PIECES[district_id] as Dictionary).get("pieces", {}):
			if MANIFEST.has(content_id) or DRESSING_MANIFEST.has(content_id):
				continue
			if not out.has(content_id):
				out.append(content_id)
	return out

## Generation-vocabulary ids only (the content-palette coverage law sweeps these).
static func piece_ids() -> Array:
	return MANIFEST.keys()

## Dressing-prop ids (body law applies; content-palette law deliberately does not).
static func dressing_ids() -> Array:
	return DRESSING_MANIFEST.keys()

static func _node_name_for(content_id: String) -> String:
	if MANIFEST.has(content_id):
		return str(MANIFEST[content_id])
	return str(DRESSING_MANIFEST.get(content_id, ""))

## A fresh visual body for `content_id`, transform reset to identity — or null
## (loudly) when the vocabulary doesn't know it or the model lost the node.
## STATE VARIANTS. A tendable plant is supposed to LOOK tended, and until the
## variants existed every species shipped one body, so the tending loop had nothing
## to show for itself. A variant is one more node in the same gltf named
## `<Piece>__<state>`; the default state keeps the bare name. Asking for a state a
## piece does not have is not an error — it quietly gives you the default body,
## which is what a caller wants when only some species have variants.
const STATE_SEPARATOR := "__"

## Variant states each content id ships, default first. Declared rather than probed
## so a test can assert the set without loading the model.
const PIECE_STATES := {
	"seefern": ["tended", "wild", "stressed"],
	"scarpet": ["tended", "wild", "senescent"],
	"hushbloom": ["charged", "triggered", "recharging"],
}


## The states `content_id` ships, or [] when it has only one body.
static func piece_states(content_id: String) -> Array:
	return (PIECE_STATES.get(content_id, []) as Array).duplicate()


static func instantiate(content_id: String, state: String = "") -> Node3D:
	# The district is asked FIRST, and it alone may know the id: a district's own
	# feature vocabulary never appears in the shared manifests, so requiring a
	# manifest name up front would make those pieces unaskable.
	var district: Dictionary = _district_source(content_id)
	var archetype_name := _node_name_for(content_id)
	if district.is_empty() and archetype_name.is_empty():
		push_warning("ArchetypePieceLibrary: no piece for content id '%s'" % content_id)
		return null
	var packed: PackedScene = null
	var source_path := SCENE_PATH
	var node_name := archetype_name
	if not district.is_empty():
		node_name = str(district["node"])
		source_path = str(district["path"])
		if not _override_packed.has(source_path):
			var loaded = load(source_path)
			_override_packed[source_path] = loaded if loaded is PackedScene else null
		packed = _override_packed[source_path]
		if packed == null:
			push_warning("ArchetypePieceLibrary: %s piece set missing: %s"
				% [_district, source_path])
	if packed == null and not archetype_name.is_empty():
		source_path = SCENE_PATH
		node_name = archetype_name
		packed = _ensure_packed()
	if packed == null:
		return null
	var scratch := packed.instantiate()
	var node: Node = null
	var resolved_state := ""
	if not state.is_empty():
		node = scratch.find_child(node_name + STATE_SEPARATOR + state, true, false)
		if node != null:
			resolved_state = state
	if node == null:
		node = scratch.find_child(node_name, true, false)
	var clone: Node3D = null
	if node == null or not (node is Node3D):
		push_warning("ArchetypePieceLibrary: piece node '%s' missing from %s"
			% [node_name, source_path])
	else:
		clone = (node as Node3D).duplicate() as Node3D
		clone.transform = Transform3D.IDENTITY
		clone.set_meta("archetype_piece_id", content_id)
		if not resolved_state.is_empty():
			clone.set_meta("archetype_piece_state", resolved_state)
	scratch.free()
	return clone
