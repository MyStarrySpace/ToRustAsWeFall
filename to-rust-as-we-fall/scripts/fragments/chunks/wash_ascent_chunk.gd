extends "res://scripts/scene_chunks/scene_chunk.gd"
## WASH ASCENT — the from-scratch rebuild (director's restart contract, 2026-07-28).
##
## THE LAWS THIS SCRIPT LIVES UNDER:
## - ZERO PRIMITIVES. Every visible mesh comes from the archetype piece library or a
##   modeled GLB. This script draws nothing itself — no boxes, no cylinders, no quads.
##   (`--test-wash-ascent` lints the built scene for PrimitiveMesh and goes red.)
## - ONE SOURCE OF TRUTH. Placements live as nodes in wash_ascent_props.tscn — a
##   Marker3D wearing `metadata/piece` per prop, real OmniLight3D nodes for lights,
##   and RUN markers (deck_run/wall_run/channel_run/rail_run/pipe_chain) for tiled
##   fills. This script only instantiates, measures, and validates.
## - MEASURE, THEN PLACE. Run pitches come from the pieces' REAL combined AABBs at
##   load (`_piece_aabb`), so channel segments, rails, wall panels, and pipe chains
##   meet mouth-to-mouth by construction — never an eyeballed spacing constant.
## - THE GRUNGE LAW. Structure is never tinted; color is spent only on the named
##   accents (water/work/ember/organic), applied as a dim hue cue over shaded albedo.
## - STORYTELLING PLACEMENT. The props scene's tree IS the story: a decaying
##   approach span, a kept maintenance bay, a measured manifold run, and the portal
##   ledge the overgrowth is taking back. Walkability derives from the placed props
##   (blockers become wall cells), so the grid can never disagree with the scene.

const PROPS_SCENE := preload("res://scenes/fragments/chunks/wash_ascent_props.tscn")

const DECK_W := 26.0
const DECK_D := 8.0
const DECK_TOP := 0.1

const ACCENTS := {
	"water": Color(0.30, 0.62, 0.72),
	"work": Color(0.85, 0.58, 0.22),
	"ember": Color(0.72, 0.28, 0.14),
	"organic": Color(0.48, 0.32, 0.62),
}

## Pieces whose footprint blocks the walk grid. Flora and thin wall-hangers don't.
const BLOCKING_PIECES := ["shelter", "workbench", "forage_cache", "terminal",
	"junction", "portal_console", "portal_ring_ornate", "vein_trunk",
	"water_control", "pipe_rack", "barrier"]

var _props_root: Node3D
var _piece_aabbs: Dictionary = {}
var _placed_count := 0
var _unresolved: Array = []
var _wall_cells: Array = []

func _build_chunk() -> void:
	_props_root = PROPS_SCENE.instantiate()
	add_child(_props_root)
	_realize_markers(_props_root)
	_build_deck_collision()
	_derive_wall_cells()
	if not _unresolved.is_empty():
		push_error("wash_ascent: unresolved placements: %s" % [_unresolved])

## Walk the props scene and realize every marker: single pieces and measured runs.
func _realize_markers(node: Node) -> void:
	for child in node.get_children():
		_realize_markers(child)
	if not (node is Node3D):
		return
	var n3 := node as Node3D
	if n3.has_meta("piece"):
		_realize_piece(n3)
	elif n3.has_meta("deck_run"):
		_realize_deck_run(n3)
	elif n3.has_meta("wall_run"):
		_realize_row(n3, _wall_variant_ids(), int(n3.get_meta("wall_run")),
			_skip_set(n3), "wall", "structure_wall")
	elif n3.has_meta("channel_run"):
		_realize_row(n3, ["water_channel"], int(n3.get_meta("channel_run")),
			{}, "floor", "structure_channel")
	elif n3.has_meta("rail_run"):
		_realize_row(n3, ["railing_run"], int(n3.get_meta("rail_run")),
			_skip_set(n3), "floor", "structure_rail")
	elif n3.has_meta("pipe_chain"):
		_realize_row(n3, ["ball_joint_pipe"], int(n3.get_meta("pipe_chain")),
			{}, "attached", str(n3.get_meta("cluster", "pipes")))

func _realize_piece(marker: Node3D) -> void:
	var pid := str(marker.get_meta("piece"))
	var piece := ArchetypePieceLibrary.instantiate(pid)
	if piece == null:
		_unresolved.append(pid)
		return
	marker.add_child(piece)
	_stamp(piece, str(marker.get_meta("mount", "floor")),
		str(marker.get_meta("cluster", pid)), bool(marker.get_meta("embed_ok", false)))
	var accent := str(marker.get_meta("accent", ""))
	if ACCENTS.has(accent):
		_tint_accent(piece, ACCENTS[accent], float(marker.get_meta("energy", 0.5)))
	var emission_scale := float(marker.get_meta("emission_scale", 1.0))
	if emission_scale < 1.0:
		_scale_emission(piece, emission_scale)
	_placed_count += 1

## A measured row: pieces laid along the marker's local +X, pitch = the piece's
## real AABB x-length, each piece offset so its AABB START sits at k*pitch —
## asymmetric pieces (the ball-joint pipe) still meet mouth-to-mouth exactly.
func _realize_row(marker: Node3D, variant_ids: Array, count: int, skip: Dictionary,
		mount: String, cluster: String) -> void:
	if variant_ids.is_empty() or count <= 0:
		return
	var pitch := _piece_aabb(str(variant_ids[0])).size.x
	if pitch <= 0.0:
		_unresolved.append(str(variant_ids[0]))
		return
	for k in range(count):
		if skip.has(k):
			continue
		var pid := str(variant_ids[_row_hash(marker, k) % variant_ids.size()])
		var piece := ArchetypePieceLibrary.instantiate(pid)
		if piece == null:
			_unresolved.append(pid)
			continue
		var aabb := _piece_aabb(pid)
		piece.position = Vector3(float(k) * pitch - aabb.position.x, 0.0, 0.0)
		marker.add_child(piece)
		_stamp(piece, mount, cluster, true)
		_placed_count += 1

## Deck runs lay nx × nz two-metre tiles in the marker's local frame. The surface
## meta is the decay story: "worn" runs grate-heavy, "planks" is the crew-floored
## bay, "mixed" alternates. Variation is a deterministic hash — identical every load.
func _realize_deck_run(marker: Node3D) -> void:
	var dims: Vector2i = marker.get_meta("deck_run")
	var surface := str(marker.get_meta("surface", "mixed"))
	var pitch := _piece_aabb("deck_planks").size.x
	for i in range(dims.x):
		for j in range(dims.y):
			var pid := _deck_tile_id(surface, _row_hash(marker, i * 31 + j * 7))
			var piece := ArchetypePieceLibrary.instantiate(pid)
			if piece == null:
				_unresolved.append(pid)
				continue
			piece.position = Vector3((float(i) + 0.5) * pitch, 0.0, (float(j) + 0.5) * pitch)
			marker.add_child(piece)
			_stamp(piece, "floor", "structure_deck", true)
			_placed_count += 1

func _deck_tile_id(surface: String, h: int) -> String:
	match surface:
		"planks":
			return ["deck_planks", "deck_planks_b", "deck_planks_c"][h % 3]
		"worn":
			return ["deck_grate", "deck_grate_b", "deck_grate", "deck_planks_c",
				"deck_grate_b", "deck_planks"][h % 6]
		_:
			return ["deck_planks", "deck_grate", "deck_planks_b", "deck_grate_b",
				"deck_planks_c"][h % 5]

func _wall_variant_ids() -> Array:
	return ["wall_panel_tile", "wall_panel_tile_b", "wall_panel_tile", "wall_panel_tile_c"]

func _row_hash(marker: Node3D, k: int) -> int:
	return absi(int(marker.position.x * 7.0) + int(marker.position.z * 13.0) + k * 5 + 3)

func _skip_set(marker: Node3D) -> Dictionary:
	var out: Dictionary = {}
	for part in str(marker.get_meta("skip", "")).split(",", false):
		out[int(part)] = true
	return out

## Survey metadata rides the piece ROOT: the wash-ascent survey test reads these.
func _stamp(piece: Node3D, mount: String, cluster: String, embed: bool) -> void:
	piece.set_meta("mount", mount)
	piece.set_meta("cluster", cluster)
	piece.set_meta("embed_ok", embed)

## The measured-AABB cache: one scratch instantiation per piece id, combined over
## the piece's whole subtree. This is the same math as tools/probe_piece_datums.gd.
func _piece_aabb(pid: String) -> AABB:
	if _piece_aabbs.has(pid):
		return _piece_aabbs[pid]
	var total := AABB()
	var piece := ArchetypePieceLibrary.instantiate(pid)
	if piece != null:
		total = _combined_aabb(piece, Transform3D.IDENTITY)
		piece.free()
	_piece_aabbs[pid] = total
	return total

func _combined_aabb(node: Node, xf: Transform3D) -> AABB:
	var total := AABB()
	var first := true
	var stack: Array = [[node, xf]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var t: Transform3D = entry[1]
		if n is Node3D and n != node:
			t = t * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var world: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
			total = world if first else total.merge(world)
			first = false
		for c in n.get_children():
			stack.append([c, t])
	return total

## A marker's `emission_scale` calms a piece's BAKED glow (a sign band, a screen)
## without touching its albedo — the grunge law's answer to a too-hot fixture.
func _scale_emission(piece: Node3D, scale: float) -> void:
	var stack: Array = [piece]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for si in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(si)
				if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
					var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.emission_energy_multiplier *= scale
					mi.set_surface_override_material(si, dup)
		for c in n.get_children():
			stack.append(c)

## The accent is a hue CUE riding shaded albedo, never a repaint (the grunge law).
## Materials are shared across clones, so each surface is duplicated before tinting.
func _tint_accent(piece: Node3D, color: Color, energy: float) -> void:
	var stack: Array = [piece]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for si in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(si)
				if mat is StandardMaterial3D:
					var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.emission_enabled = true
					dup.emission = color
					dup.emission_energy_multiplier = energy * 0.3
					mi.set_surface_override_material(si, dup)
		for c in n.get_children():
			stack.append(c)

## Invisible click/walk collision under each deck run — infrastructure, not a drawn
## mesh (the no-primitives law is about visible geometry; the ground ray needs this).
func _build_deck_collision() -> void:
	for marker in _find_meta_nodes(_props_root, "deck_run"):
		var dims: Vector2i = marker.get_meta("deck_run")
		var pitch := _piece_aabb("deck_planks").size.x
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(dims.x) * pitch, 0.2, float(dims.y) * pitch)
		shape.shape = box
		shape.position = Vector3(float(dims.x) * pitch * 0.5, 0.0, float(dims.y) * pitch * 0.5)
		body.add_child(shape)
		(marker as Node3D).add_child(body)

## Walkability derives from the PLACED blockers — the grid cannot disagree with
## the scene, because the scene is measured after it exists.
func _derive_wall_cells() -> void:
	_wall_cells.clear()
	var seen: Dictionary = {}
	for piece in _find_meta_nodes(_props_root, "archetype_piece_id"):
		if not BLOCKING_PIECES.has(str(piece.get_meta("archetype_piece_id"))):
			continue
		var aabb := _combined_aabb(piece, (piece as Node3D).global_transform)
		for cx in range(int(floor(aabb.position.x)), int(ceil(aabb.end.x))):
			for cz in range(int(floor(aabb.position.z)), int(ceil(aabb.end.z))):
				if cx < 0 or cz < 0 or cx >= int(DECK_W) or cz >= int(DECK_D):
					continue
				var key := "%d_%d" % [cx, cz]
				if not seen.has(key):
					seen[key] = true
					_wall_cells.append([cx, cz])

func _find_meta_nodes(root: Node, meta_key: String) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and n.has_meta(meta_key):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

# --- Preview host contract ---

func get_scene_title() -> String:
	return "Wash Ascent"

func get_scene_help() -> String:
	return "Reach the portal ledge at the far end of the service walkway. // The channel edge is open where the rail has failed."

func get_grid_data() -> Dictionary:
	return {
		"origin": [0.0, DECK_TOP, 0.0],
		"cell_size": 1.0,
		"width": int(DECK_W),
		"height": int(DECK_D),
		"default_walkable": false,
		"walkable_regions": [{"min": [0.0, 0.0], "max": [DECK_W, DECK_D]}],
		"wall_cells": _wall_cells,
	}

func get_spawn_positions() -> Dictionary:
	var anchor := Vector3(2.0, DECK_TOP, 3.0)
	var marker := _props_root.find_child("SpawnPlayer", true, false) if _props_root else null
	if marker is Node3D:
		anchor = (marker as Node3D).global_position
	return {
		"aster": anchor,
		"peris": anchor + Vector3(-1.2, 0.0, 1.2),
		"endo": anchor + Vector3(-1.6, 0.0, -1.4),
	}

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors["portal_ledge"] = Vector3(22.5, DECK_TOP, 3.0)
	anchors["maintenance_bay"] = Vector3(11.0, DECK_TOP, 4.0)
	return anchors

## The authored grade: dark and grungy, with a playable light floor.
func get_preview_lighting_profile() -> Dictionary:
	return {
		"tonemap_mode": "filmic",
		"tonemap_white": 1.1,
		"glow_bloom": 0.08,
		"ambient_energy_floor": 0.22,
		"ambient_energy_ceiling": 0.42,
		"background_color": Color(0.012, 0.016, 0.022),
		"background_mix": 0.85,
	}

func get_preview_state() -> Dictionary:
	return {
		"placed": _placed_count,
		"unresolved": _unresolved.duplicate(),
		"wall_cells": _wall_cells.size(),
	}
