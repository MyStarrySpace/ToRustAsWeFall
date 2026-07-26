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
}

static var _template: Node3D = null

static func _ensure_template() -> Node3D:
	if _template != null and is_instance_valid(_template):
		return _template
	var packed = load(SCENE_PATH)
	if packed == null or not (packed is PackedScene):
		push_warning("ArchetypePieceLibrary: cannot load %s" % SCENE_PATH)
		return null
	_template = (packed as PackedScene).instantiate() as Node3D
	return _template

static func has_piece(content_id: String) -> bool:
	return MANIFEST.has(content_id)

static func piece_ids() -> Array:
	return MANIFEST.keys()

## A fresh visual body for `content_id`, transform reset to identity — or null
## (loudly) when the vocabulary doesn't know it or the model lost the node.
static func instantiate(content_id: String) -> Node3D:
	if not MANIFEST.has(content_id):
		push_warning("ArchetypePieceLibrary: no piece for content id '%s'" % content_id)
		return null
	var tpl := _ensure_template()
	if tpl == null:
		return null
	var node := tpl.find_child(str(MANIFEST[content_id]), true, false)
	if node == null or not (node is Node3D):
		push_warning("ArchetypePieceLibrary: piece node '%s' missing from %s"
			% [MANIFEST[content_id], SCENE_PATH])
		return null
	var clone := (node as Node3D).duplicate() as Node3D
	clone.transform = Transform3D.IDENTITY
	clone.set_meta("archetype_piece_id", content_id)
	return clone
