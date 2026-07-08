extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## PREVIEW chunk for the SHAPE-GRAMMAR generator. On build it asks `FragmentGrammar` for a fresh
## in-memory `Fragment` (no `.tres`) keyed off a seed, hands it to the DataFragmentChunk base, and the
## base composes the scene exactly as it would for an authored fragment. Press N in the preview to
## regenerate: the host bumps the seed and re-begins the chunk (the roguelike regenerate flow), so each
## build is a new deterministic variation.
##
## Wired into the preview registry as chunk "shape_grammar" (see fragment_preview_sequence.gd). The
## generator itself is scene-agnostic — act1 / the roguelike / a level-builder can call FragmentGrammar
## directly; this chunk is only the preview shell.

const GrammarScript := preload("res://scripts/generation/fragment_grammar.gd")
const FillerScript := preload("res://scripts/generation/building_filler.gd")
const MesherScript := preload("res://scripts/generation/sdf_mesher.gd")

var _seed := 1
var _opts := {}

func configure_chunk(config: Dictionary) -> void:
	if config.has("seed"):
		_seed = int(config["seed"])
	if config.has("grammar_opts") and config["grammar_opts"] is Dictionary:
		_opts = config["grammar_opts"]
	# NB: intentionally do NOT forward fragment/fragment_path to the base — we generate our own.

func _build_chunk() -> void:
	fragment = GrammarScript.generate(_seed, _opts)
	super._build_chunk()
	# HERO ORGANIC MASSES: the filler plans them as data (prims); the chunk owns nodes, so it meshes
	# them here — SDF blob stacks in a tinted triplanar atlas material (the vesicle/blob vocabulary).
	for hb in (fragment.params.get("hero_buildings", []) as Array):
		var hd := hb as Dictionary
		var prims: Array = FillerScript.hero_blob_prims(int(hd["seed"]), hd["center"],
			float(hd["radius"]), float(hd["height"]))
		var built: Dictionary = MesherScript.build(prims, 0.24, hd["color"])
		if built["mesh"] == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "HeroMass"
		mi.mesh = built["mesh"]
		mi.material_override = _tinted_tile_material(str(hd["tile"]), hd["color"])
		add_child(mi)

## Marker the host checks before treating N as "regenerate" (so the key is inert for other chunks).
func is_generation_preview() -> bool:
	return true

func get_generation_seed() -> int:
	return _seed

func get_scene_title() -> String:
	return "Shape Grammar — seed %d" % _seed

func get_preview_state() -> Dictionary:
	var st := super.get_preview_state()
	st["seed"] = _seed
	if fragment != null:
		st["shape_cells"] = int(fragment.params.get("shape_cells", 0))
		st["level_count"] = int(fragment.params.get("level_count", 1))
	return st
