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
}

# Only the PackedScene is cached; each call instantiates, clones the named
# piece, and frees the scratch instance — a live never-in-tree template Node
# would leak 19 nodes at every process exit.
static var _packed: PackedScene = null

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
	return MANIFEST.has(content_id) or DRESSING_MANIFEST.has(content_id)

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
static func instantiate(content_id: String) -> Node3D:
	var node_name := _node_name_for(content_id)
	if node_name.is_empty():
		push_warning("ArchetypePieceLibrary: no piece for content id '%s'" % content_id)
		return null
	var packed := _ensure_packed()
	if packed == null:
		return null
	var scratch := packed.instantiate()
	var node := scratch.find_child(node_name, true, false)
	var clone: Node3D = null
	if node == null or not (node is Node3D):
		push_warning("ArchetypePieceLibrary: piece node '%s' missing from %s"
			% [node_name, SCENE_PATH])
	else:
		clone = (node as Node3D).duplicate() as Node3D
		clone.transform = Transform3D.IDENTITY
		clone.set_meta("archetype_piece_id", content_id)
	scratch.free()
	return clone
