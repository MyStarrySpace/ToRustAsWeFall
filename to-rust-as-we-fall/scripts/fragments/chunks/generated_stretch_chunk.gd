extends "res://scripts/scene_chunks/scene_chunk.gd"

const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const CatalogScript := preload("res://scripts/generation/stretch_archetype_catalog.gd")
const CapabilitiesScript := preload("res://scripts/generation/stretch_capabilities.gd")
const SpiralCoordMapScript := preload("res://scripts/generation/spiral_coord_map.gd")
const WaterShader := preload("res://resources/channels_water.gdshader")
const WaterTexV0 := preload("res://resources/models/channels/channels_water_v0.png")
const WaterTexV1 := preload("res://resources/models/channels/channels_water_v1.png")

const DEFAULT_SPEC_PATH := "res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"
const PARTY_IDS := ["aster", "peris", "endo"]
const FULL_HP := 100.0
const FULL_STAMINA := 100.0
const FOOD_TEST_NEUTRAL := "neutral"
const FOOD_TEST_RETURN_LOOP := "return_loop"
const FOOD_TEST_SCARCITY := "scarcity"
const SCARCITY_DRAIN_TAG := "generated_stretch_food_scarcity"
const SCARCITY_DEFAULT_INTERVAL := 60.0
const SCARCITY_DEFAULT_ATP := 1.0
const SCARCITY_ATP_FLOOR := 1.0
const GUIDE_FOOD_ATP := 0.5
const GUIDE_FOOD_SEGMENTS := [["entry", "node_01"], ["node_02", "node_03"]]
const HYDRAULIC_SPEC_ID := "generated_teaching_channels_shelter_1_to_2"
const HYDRAULIC_WATER_COLOR := Color(0.08, 0.42, 0.58)
const HYDRAULIC_ACTIVE_COLOR := Color(0.24, 0.88, 1.0)
const HYDRAULIC_CONTROL_COLOR := Color(0.94, 0.55, 0.18)
const HYDRAULIC_READY_COLOR := Color(0.42, 0.88, 0.54)
const HYDRAULIC_BLOCKER_TAG := "generated_cistern_bridge_gap"
const HYDRAULIC_NEXT_HIGHLIGHT_REASON := "hydraulic_next_step"

@export var default_spec_path := DEFAULT_SPEC_PATH

var _config: Dictionary = {}
var _spec: Dictionary = {}

# When the level is warped onto a helix (the default for a generated stretch — the player walks a linear grid
# while the WORLD spirals around a centre), this is the flat-data<->warped-world map. Null = flat render. The
# data layer (grid/movement/detection) stays flat regardless; only the floor render, node dressing, interactable
# zones, and the installed GameState.coord_map (character render + click inverse) go through it.
var _coord_map = null

# The meta-template (macro shape) this stretch is built on — spiral by default; owns the coord_map + return-point
# strategy. A future config selects other shapes (rectangle/ring hub).
var _meta_template: MetaTemplate = null

# The playable grid the chunk actually renders + installs: the generator's linear SPINE grid WOVEN with lateral
# branch rooms (spokes off the spiral) when spiralling. Empty until first built; get_grid_data returns it. The
# generator's own spec.navigation_grid stays the bare spine (what the solver/curriculum ran on) — branches are
# optional explorable space layered on at build, so solvability is untouched.
var _woven_nav: Dictionary = {}

# Return-point nodes placed by the meta-template: DROP portals (fall a loop forward + down) and CLIMBVINES (the
# return back UP the same stack) — the "fall to the plane, take a return point back up" grammar.
var _drop_downs: Array = []
var _climbvines: Array = []

# Salvage caches placed at the far end of each branch spoke — the OPTIONAL reward that makes exploring a spoke
# (instead of pushing straight down the spine to the shelter) worth the day/night time it costs.
var _branch_caches: Array = []
var _guide_food_caches: Array = []
var _branch_atp_collected := 0
var _experiment_food_item_ids: Array[String] = []
var _generated_resource_item_ids: Array[String] = []
var _physical_food_spawned_count := 0
var _nominal_food_atp := 0.0
var _scarcity_drain_ticks := 0
var _scarcity_atp_drained := 0.0
var _scarcity_drain_armed := false
var _scarcity_clock_started := false
var _catalog := CatalogScript.new()
var _node_markers: Dictionary = {}
var _node_targets: Dictionary = {}
var _node_interactables: Dictionary = {}
var _route_surfaces: Dictionary = {}
var _content_marker_count := 0
var _spatial_fixture_count := 0
var _route_choice := ""
var _route_phase := "unstarted"
var _completed_nodes: Array[String] = []
var _activated_routes: Array[String] = []
var _produced_chain_states: Dictionary = {}
var _prepared_nested_nodes: Dictionary = {}
var _delivered_resource_nodes: Array[String] = []
var _resources_collected := 0
var _shortcut_unlocked := false
var _shelter_reached := false
var _shelter_rested := false
var _last_outcome := ""
var _risky_damage_total := 0.0
var _atp_foraged := 0
var _pressure_taken := 0.0
var _rests_taken := 0
var _first_shelter_beat_fired := false
var _unsupported_placeholder_count := 0
var _active_loadout := "spotlight"
var _active_party: Array[String] = ["aster", "peris", "endo"]
var _active_capabilities: Dictionary = {}
var _enforce_stage := true
var _node_approach_used: Dictionary = {}
var _blocked_nodes: Array[String] = []

# Diagnosis state: a node awaiting a read (the player must pick a perspective), the read each
# diagnosis node was resolved with, and the running tally of misdiagnoses (each a pressure
# setback, never a hard block).
var _pending_diagnosis := ""
var _diagnosis_reads: Dictionary = {}
var _misdiagnosis_count := 0
var _last_diagnosis_read := ""
var _last_diagnosis_correct := false

var _hydraulic_phase := "disabled"
var _first_sluice_open := false
var _cistern_bridge_installed := false
var _borrowed_current_diverted := false
var _borrowed_current_delivery_latched := false
var _main_current_restored := false
var _hydraulic_main_water: Array[MeshInstance3D] = []
var _hydraulic_main_tail: Array[MeshInstance3D] = []
var _hydraulic_spillway_water: Array[MeshInstance3D] = []
var _hydraulic_exit_water: Array[MeshInstance3D] = []
var _hydraulic_first_control: Area3D
var _hydraulic_cistern_control: Area3D
var _hydraulic_diverter_control: Area3D
var _hydraulic_first_target: StaticBody3D
var _hydraulic_cistern_target: StaticBody3D
var _hydraulic_diverter_target: StaticBody3D
var _hydraulic_catch_target: StaticBody3D
var _hydraulic_catch_control: Area3D
var _hydraulic_first_label: Label3D
var _hydraulic_cistern_label: Label3D
var _hydraulic_diverter_label: Label3D
var _hydraulic_exit_label: Label3D
var _hydraulic_first_landmark_meshes: Array[MeshInstance3D] = []
var _hydraulic_first_landmark_light: OmniLight3D
var _hydraulic_cistern_effect: Node3D
var _hydraulic_bridge_mesh: MeshInstance3D
var _hydraulic_bridge_cargo: MeshInstance3D
var _hydraulic_spillway_catch: MeshInstance3D
var _hydraulic_exit_beacon: MeshInstance3D
var _hydraulic_spillway_link: Node3D
var _hydraulic_exit_link: Node3D
var _hydraulic_spillway_food_cache: Dictionary = {}
var _hydraulic_grid_instance_id := 0


func configure_chunk(config: Dictionary) -> void:
	_config = config.duplicate(true)
	_load_spec_from_config()
	if _built:
		_clear_generated_children()
		_build_chunk()


func is_generation_preview() -> bool:
	return true


func get_generation_seed() -> int:
	if not _spec.is_empty():
		return int(_spec.get("source", {}).get("seed", _spec.get("settings", {}).get("seed", 0)))
	return int(_config.get("seed", 0))


func _exit_tree() -> void:
	_cancel_scarcity_drain()
	_clear_experiment_food_items()


func detach_chunk_host() -> void:
	_cancel_scarcity_drain()
	_clear_experiment_food_items()
	super.detach_chunk_host()


func _build_chunk() -> void:
	_ensure_spec_loaded()
	_ensure_graybox_layout()
	_ensure_navigation_layout()

	_clear_experiment_food_items()
	_cancel_scarcity_drain()
	name = "GeneratedStretchChunk_%s" % str(_spec.get("id", "stretch"))
	_unsupported_placeholder_count = 0
	_content_marker_count = 0
	_spatial_fixture_count = 0
	_node_markers.clear()
	_node_targets.clear()
	_node_interactables.clear()
	_route_surfaces.clear()
	_drop_downs.clear()
	_climbvines.clear()
	_branch_caches.clear()
	_guide_food_caches.clear()
	_branch_atp_collected = 0
	_physical_food_spawned_count = 0
	_nominal_food_atp = 0.0
	_clear_hydraulic_runtime_refs()
	_woven_nav = {}
	_build_coord_map()
	_ensure_woven_grid()

	# The tiled walkable floor IS the level now — the old abstract scaffolding (a big foundation slab, straight
	# route-connector boxes, big role pads, a palette legend) was redundant clutter over it, so it's gone. Only the
	# floor + the per-node markers/interactables the player actually uses remain.
	_build_foundation()

	# Everything _build_generated_nodes adds (markers, labels, content, interactables, outline targets) is authored
	# FLAT; capture the boundary so the warp pass below re-seats only those children onto the helix — the floor
	# (warped at the vertex level in _build_walkable_floor) and the fill light keep their own transforms.
	var flat_child_start := get_child_count()
	_build_generated_nodes()

	# Branch caches are authored FLAT like the node dressing, so build them BEFORE the warp pass and let it re-seat
	# them onto the helix too (keeps their interactable + outline target together on the deck).
	_build_branch_content()
	_configure_food_branch_caches()
	_build_guide_food_caches()
	_build_hydraulic_puzzle()
	if _coord_map != null:
		for i in range(flat_child_start, get_child_count()):
			_warp_child(get_child(i))
	_wire_hydraulic_feedback()
	_build_return_points()
	_register_shelter_regions()
	reset_preview_state()


## Shelter SANCTUARY registration: the entry pad and every shelter-role node become GameState
## shelter regions, sized by their pad footprints — the detection gate, the strike gate, and the
## revive watch all read these, so "standing in the shelter" actually means safe (a shelter that
## was only a marker let enemies attack you inside it — the 2026-07-12 report). Regions live in
## the FLAT data frame (character positions stay flat under the helix warp) and are logged
## (KIND_ADD_SHELTER), like interactable registration.
func _register_shelter_regions() -> void:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("add_shelter_region"):
		return
	var done := {}
	for node_v in _spec.get("nodes", []) as Array:
		var node := node_v as Dictionary
		var role := str(node.get("role", ""))
		var nid := str(node.get("id", ""))
		if not (
			role in ["shelter", "shelter_arrival", "entry"] or nid in ["entry", "exit_shelter"]
		):
			continue
		var p := _vec3(node.get("position", []), Vector3.INF)
		if p == Vector3.INF:
			continue
		var half := _node_pad_size(role if role != "" else "shelter") * 0.5
		gs.add_shelter_region(
			Vector2(p.x - half.x - 0.4, p.z - half.z - 0.4),
			Vector2(p.x + half.x + 0.4, p.z + half.z + 0.4)
		)
		done[nid] = true

	# a spec may carry entry/exit as bare anchors rather than nodes — cover those too
	for aid in ["entry", "exit_shelter"]:
		if done.has(aid):
			continue
		var ap := _anchor_position(str(aid))
		if ap == Vector3.INF:
			continue
		gs.add_shelter_region(Vector2(ap.x - 3.3, ap.z - 2.6), Vector2(ap.x + 3.3, ap.z + 2.6))


func _food_test_mode() -> String:
	var requested := str(_config.get("food_test", FOOD_TEST_NEUTRAL)).strip_edges().to_lower()
	if requested in [FOOD_TEST_RETURN_LOOP, FOOD_TEST_SCARCITY]:
		return requested
	return FOOD_TEST_NEUTRAL


func _game_mode_id() -> String:
	# food_test controls the active mechanics, so an explicit value is authoritative.
	# This keeps the briefing truthful even if a caller supplies a stale mode label.
	if _config.has("food_test"):
		match _food_test_mode():
			FOOD_TEST_RETURN_LOOP:
				return "expedition"
			FOOD_TEST_SCARCITY:
				return "scarcity"
			_:
				return "neutral"
	var configured := str(_config.get("game_mode", "")).strip_edges().to_lower()
	if configured in ["neutral", "expedition", "scarcity"]:
		return configured
	match _food_test_mode():
		FOOD_TEST_RETURN_LOOP:
			return "expedition"
		FOOD_TEST_SCARCITY:
			return "scarcity"
	return "neutral"


func _food_economy_help() -> String:
	match _game_mode_id():
		"expedition":
			return "FOOD — Expedition: small route morsels guide travel; deeper green detour caches carry more ATP. Food occupies a hand until consumed, and shelter preserves ATP."
		"scarcity":
			return (
				"FOOD — Scarcity: after moving, each character loses 1 ATP every %.0f seconds. Route morsels restore 0.5; riskier detour caches restore more. The final action pip is protected."
				% _scarcity_drain_interval()
			)
		_:
			return "FOOD — Neutral: ATP does not drain, and the original salvage rewards can refill the party."


func _hydraulic_enabled() -> bool:
	return str(_spec.get("id", "")) == HYDRAULIC_SPEC_ID


func _hydraulic_help() -> String:
	if not _hydraulic_enabled():
		return ""
	return " CHANNEL PUZZLE — Open the First Sluice, release the Cistern Bridge, borrow the current to the food spillway, then restore the main flow before leaving."


func _food_test_settings() -> Dictionary:
	var raw: Variant = _config.get("food_test_settings", {})
	return raw as Dictionary if raw is Dictionary else {}


func _scarcity_drain_interval() -> float:
	var settings := _food_test_settings()
	return maxf(
		5.0,
		float(
			settings.get(
				"drain_interval_seconds",
				_config.get("food_drain_interval_seconds", SCARCITY_DEFAULT_INTERVAL)
			)
		)
	)


func _scarcity_drain_amount() -> float:
	var settings := _food_test_settings()
	return maxf(
		0.0, float(settings.get("drain_atp", _config.get("food_drain_atp", SCARCITY_DEFAULT_ATP)))
	)


## Whether this stretch renders as a helix (the default) or stays a flat grid. Generated stretches spiral so a
## long level curls compactly around a centre (the player still walks a linear grid); a hand-authored builder
## level or a test can opt OUT with config "spiral": false to keep the painted flat layout.
func _spiral_enabled() -> bool:
	if _config.has("spiral"):
		return bool(_config["spiral"])

	# A hand-authored / ASCII level (from the builder) plays as the FLAT layout the user drew — no spiral warp,
	# no woven branch spokes. Only procedurally GENERATED stretches spiral. Detected by the authored schema.
	if str(_spec.get("schema", "")) == "authored_ascii_v1":
		return false
	return true


## Resolve the META-TEMPLATE (macro shape) for this stretch. The hub SHAPE is a PARAMETER: pass config
## "hub_shape" = {type:"circle"|"rect"|"hexagon"|"triangle"|"polygon", ...} to generate the level AROUND that shape
## as its hub (circle == the plain spiral). Flat/authored levels get the no-warp base template.
func _resolve_meta_template() -> MetaTemplate:
	if not _spiral_enabled():
		return MetaTemplate.new()
	var shape = _config.get("hub_shape", null)
	if shape is Dictionary and not (shape as Dictionary).is_empty():
		return HubMetaTemplate.new(shape)
	match str(_config.get("meta_template", "spiral")):
		"flat":
			return MetaTemplate.new()
		"hub":
			return HubMetaTemplate.new({"type": "circle"})
		_:
			return SpiralMetaTemplate.new()


## Build the coord_map for this stretch THROUGH its meta-template (the spiral warps onto a descending helix; the
## flat template returns null). Cleared + rebuilt every time the chunk (re)builds.
func _build_coord_map() -> void:
	_meta_template = _resolve_meta_template()
	var spine_nav: Dictionary = _spec.get("navigation_grid", {})
	var profile := _spatial_profile()
	if (
		_meta_template != null
		and _meta_template.template_id() == "spiral"
		and not profile.is_empty()
	):
		_coord_map = SpiralCoordMapScript.from_grid(
			spine_nav,
			float(profile.get("spiral_turns", 0.0)),
			float(profile.get("spiral_min_radius", 0.0)),
			float(profile.get("spiral_descent_per_turn", 6.0)),
			float(profile.get("spiral_base_y", 0.45))
		)
	else:
		_coord_map = _meta_template.build_coord_map(spine_nav)


## Presentation-only dimensions for a generated stretch. These never rewrite the semantic node graph or replay
## decisions: WFC consumes the room pitch while the coord-map consumes the helix values. A chunk config may
## override the saved profile for QA without silently changing the authored default.
func _spatial_profile() -> Dictionary:
	var profile: Dictionary = _spec.get("settings", {}).get("spatial_profile", {}).duplicate(true)
	var override_v: Variant = _config.get("spatial_profile", {})
	if override_v is Dictionary:
		profile.merge(override_v as Dictionary, true)
	return profile


func get_coord_map():
	return _coord_map


## The playable grid = the spine woven with branch spokes (when spiralling). Built once; both the floor render and
## the installed GameState grid read this, so the walkable floor, collision, detection and pathing all agree.
func _ensure_woven_grid() -> void:
	if not _woven_nav.is_empty():
		return
	_ensure_navigation_layout()
	var spine: Dictionary = _spec.get("navigation_grid", {})
	if spine.is_empty():
		return
	if _spiral_enabled() and bool(_config.get("branches", true)):
		var BranchWeaver = load("res://scripts/generation/stretch_branch_weaver.gd")
		var weave_options := {
			"seed": _weave_seed(),
			"tier":
			str(
				_spec.get("source", {}).get(
					"complexity_tier",
					_spec.get("settings", {}).get("complexity_tier", "standard")
				)
			),
			"stage": _progression_stage(),
		}
		var profile := _spatial_profile()
		if profile.has("branch_room_count"):
			weave_options["count"] = maxi(0, int(profile["branch_room_count"]))
		_woven_nav = (
			BranchWeaver
			. weave(spine, weave_options)
		)
	else:
		_woven_nav = spine.duplicate(true)

	# The hub template's flat BASE FLOOR (the shape as a floor) — prepend it before the entry so the party rests +
	# walks on it, then steps onto the descending deck. The coord_map maps these front cells (s < 0) to the flat base.
	var base_n := 0
	if _meta_template != null and _meta_template.has_method("base_cells"):
		base_n = int(_meta_template.call("base_cells"))
	if base_n > 0:
		_woven_nav = _prepend_base_to_grid(_woven_nav, base_n)


## Deterministic seed for the branch weave — from the level's own seed so the same spec always grows the same
## spokes (replay-safe; the chunk reproduces them every build).
func _weave_seed() -> int:
	return int(_spec.get("source", {}).get("seed", _spec.get("settings", {}).get("seed", 0)))


func _nav_grid() -> Dictionary:
	_ensure_woven_grid()
	return _woven_nav if not _woven_nav.is_empty() else _spec.get("navigation_grid", {})


## Prepend a flat BASE FLOOR block (base_cells x height) BEFORE the spine (cells x < 0), connected to the entry
## column, then renormalise so indices are >= 0 again — shifting the origin in lockstep preserves every spine
## cell's WORLD position (so the coord_map, built on the spine, still lines up; base cells land at world x < the
## spine origin, which the coord_map maps to s < 0 = the flat base). The base is a full-height rectangle so the
## whole entry face connects to it. Records _base_x_range for placing the entry shelter + spawn on the base.
var _base_x_range := Vector2i(0, 0)  # [min_x, max_x) of base columns in the FINAL (shifted) grid; empty if none


func _prepend_base_to_grid(nav: Dictionary, base_cells: int) -> Dictionary:
	if base_cells <= 0 or nav.is_empty():
		return nav
	var out: Dictionary = nav.duplicate(true)
	var cs := float(nav.get("cell_size", 1.0))
	var height := int(nav.get("height", 1))
	var cells := {}
	for c in nav.get("walkable_cells", []):
		cells[Vector2i(int(c[0]), int(c[1]))] = true
	for bx in range(-base_cells, 0):
		for bz in range(height):
			cells[Vector2i(bx, bz)] = true

	var min_x := 2147483647
	var min_z := 2147483647
	var max_x := -2147483647
	var max_z := -2147483647
	# Renormalise (shift so min index = 0); origin shifts the opposite way so world positions are preserved.
	for v in cells.keys():
		min_x = mini(min_x, v.x)
		min_z = mini(min_z, v.y)
		max_x = maxi(max_x, v.x)
		max_z = maxi(max_z, v.y)
	var shift := Vector2i(min_x, min_z)
	var origin: Array = out.get("origin", [0.0, 0.45, 0.0])
	out["origin"] = [
		float(origin[0]) + float(shift.x) * cs,
		float(origin[1]),
		float(origin[2]) + float(shift.y) * cs
	]
	out["width"] = (max_x - min_x) + 1
	out["height"] = (max_z - min_z) + 1
	out["walkable_cells"] = _shift_cell_list(cells.keys(), shift)
	out["risk_cell_list"] = _shift_risk_list(out.get("risk_cell_list", []), shift)
	out["route_cells"] = _shift_route_cells(out.get("route_cells", {}), shift)
	out["links"] = _shift_link_list(out.get("links", []), shift)
	var level_cells: Array = out.get("level_cells", [])
	if not level_cells.is_empty():
		var base_set := {}
		for bx in range(-base_cells, 0):
			for bz in range(height):
				base_set[Vector2i(bx, bz)] = true
		out["level_cells"] = _shift_levels_with_base(level_cells, base_set, shift)

	# The base columns, in the FINAL shifted frame, are the first base_cells columns.
	_base_x_range = Vector2i(0, base_cells)
	return out


func _shift_cell_list(keys, shift: Vector2i) -> Array:
	var arr: Array = []
	for v in keys:
		arr.append(v)
	arr.sort_custom(func(p, q): return (p.y * 100000 + p.x) < (q.y * 100000 + q.x))
	var out: Array = []
	for v in arr:
		out.append([v.x - shift.x, v.y - shift.y])
	return out


func _shift_risk_list(risk_list: Array, shift: Vector2i) -> Array:
	var out: Array = []
	for r in risk_list:
		var c: Array = r.get("cell", [0, 0])
		out.append(
			{
				"cell": [int(c[0]) - shift.x, int(c[1]) - shift.y],
				"penalty": float(r.get("penalty", 0.0)),
				"recoverable": bool(r.get("recoverable", true))
			}
		)
	return out


func _shift_route_cells(route_cells: Dictionary, shift: Vector2i) -> Dictionary:
	var out := {}
	for rid in route_cells.keys():
		var src: Dictionary = route_cells[rid]
		var cells_out: Array = []
		for c in src.get("cells", []):
			cells_out.append([int(c[0]) - shift.x, int(c[1]) - shift.y])
		out[rid] = {"cells": cells_out, "kind": str(src.get("kind", ""))}
	return out


func _shift_link_list(links: Array, shift: Vector2i) -> Array:
	var out: Array = []
	for lk in links:
		var c: Array = lk.get("cell", [0, 0])
		out.append(
			{
				"cell": [int(c[0]) - shift.x, int(c[1]) - shift.y],
				"from": int(lk.get("from", 0)),
				"to": int(lk.get("to", 0)),
				"type": str(lk.get("type", "ramp"))
			}
		)
	return out


func _shift_levels_with_base(level_cells: Array, base_set: Dictionary, shift: Vector2i) -> Array:
	var out: Array = []
	for entry in level_cells:
		var lvl := int(entry.get("level", 0))
		var lset := {}
		for c in entry.get("cells", []):
			lset[Vector2i(int(c[0]), int(c[1]))] = true
		if lvl == 0:
			for c in base_set.keys():
				lset[c] = true
		out.append({"level": lvl, "cells": _shift_cell_list(lset.keys(), shift)})
	return out


## The warp transform at a flat point: on a spiral, the oriented helix frame (right = radial, up = world up,
## forward = tangent) lifted per level; flat, just a translation. Used to place a slab/marker onto the deck.
func _warp_xform(flat: Vector3) -> Transform3D:
	if _coord_map == null:
		return Transform3D(Basis.IDENTITY, flat)
	return _coord_map.to_xform(flat)


## The warped world POINT at a flat point — for per-vertex warping (floor tile corners), where each vertex
## takes its own place on the helix instead of riding one rigid cell frame.
func _warp_pos(flat: Vector3) -> Vector3:
	if _coord_map == null:
		return flat
	return _coord_map.to_world(flat)


## Re-seat one already-built (flat-authored) child onto the helix at its own (s, lane) — its authored height above
## the deck rides along (to_xform carries the per-level lift). Boxes/labels/zones all warp uniformly this way.
func _warp_child(child: Node) -> void:
	if not (child is Node3D):
		return
	var n3 := child as Node3D
	n3.transform = _coord_map.to_xform(n3.position) * Transform3D(n3.basis, Vector3.ZERO)


func get_scene_title() -> String:
	_ensure_spec_loaded()
	return str(_spec.get("title", "Generated Stretch"))


func get_scene_help() -> String:
	_ensure_spec_loaded()
	var tier := str(_spec.get("source", {}).get("complexity_tier", "generated")).capitalize()
	var composition: Dictionary = _spec.get("composition", {})
	var layout_help := ""
	if bool(composition.get("uses_random_walk", false)):
		layout_help = (
			"%s archetype stretch generated by a seeded random walk. Read each node, then choose between the spine and its branches."
			% tier
		)
	elif bool(composition.get("has_nested", false)):
		layout_help = (
			"%s archetype stretch with chained and nested puzzle rooms. Branches may rejoin, return upward, or bridge the next break."
			% tier
		)
	else:
		layout_help = (
			"%s archetype stretch. Read the route markers: some branches are optional supplies, while others carry the path forward."
			% tier
		)
	return "%s  %s%s" % [layout_help, _food_economy_help(), _hydraulic_help()]


func get_default_character() -> String:
	return "aster"


func get_preview_character_state() -> Dictionary:
	return _full_party_state()


func get_preview_time_state() -> Dictionary:
	return {
		"day": 1,
		"time": 0.28,
		"advance_time": true,
		"show_time": true,
	}


func get_spawn_positions() -> Dictionary:
	_ensure_spec_loaded()
	var positions := {}
	var anchors: Dictionary = _spec.get("anchors", {})
	for char_id in PARTY_IDS:
		if anchors.has(char_id):
			positions[char_id] = _vec3(anchors[char_id], Vector3.ZERO)
	positions["entry"] = _anchor_position("entry")
	positions["exit_shelter"] = _anchor_position("exit_shelter")
	return positions


func get_preview_anchors() -> Dictionary:
	_ensure_spec_loaded()
	var result := {}
	var anchors: Dictionary = _spec.get("anchors", {})
	for key in anchors.keys():
		result[str(key)] = _vec3(anchors[key], Vector3.ZERO)
	return result


func get_world_slot() -> Dictionary:
	_ensure_spec_loaded()
	var slot: Dictionary = _spec.get("world_slot", {}).duplicate(true)
	if not slot.has("preview_party_preset"):
		slot["preview_party_preset"] = "full_party_full_health"
	if not slot.has("canonical_party"):
		slot["canonical_party"] = PARTY_IDS.duplicate()
	return slot


func get_generation_spec() -> Dictionary:
	_ensure_spec_loaded()
	return _spec.duplicate(true)


func get_graybox_state() -> Dictionary:
	_ensure_spec_loaded()
	_ensure_graybox_layout()
	return _graybox_state()


func _effective_party_atp_total() -> float:
	if host == null or not host.has_method("get_preview_character_stat"):
		return float(PARTY_IDS.size()) * GameState.ATP_MAX_PIPS
	var total := 0.0
	for char_id in PARTY_IDS:
		total += _get_character_stat(char_id, "atp")
	return total


func _physical_food_cache_count(available_only := false) -> int:
	var count := 0
	for cache in _branch_caches:
		if not bool(cache.get("physical_food", false)):
			continue
		if available_only and bool(cache.get("collected", false)):
			continue
		count += 1
	return count


func _guide_food_cache_count(available_only := false) -> int:
	var count := 0
	for cache in _guide_food_caches:
		if available_only and bool(cache.get("collected", false)):
			continue
		count += 1
	return count


func _physical_food_opportunity_count(available_only := false) -> int:
	var count := _physical_food_cache_count(available_only) + _guide_food_cache_count(available_only)
	if _hydraulic_spillway_food_enabled():
		if not available_only or not bool(_hydraulic_spillway_food_cache.get("collected", false)):
			count += 1
	return count


func _branch_food_profiles() -> Array:
	var profiles: Array = []
	for cache in _branch_caches:
		profiles.append({
			"index": int(cache.get("index", -1)),
			"shape": str(cache.get("shape", "")),
			"risk_score": float(cache.get("risk_score", 0.0)),
			"detour_cells": float(cache.get("detour_cells", 0.0)),
			"hazard_penalty": float(cache.get("hazard_penalty", 0.0)),
			"food_atp": float(cache.get("food_atp", BRANCH_ATP)),
		})
	return profiles


func _hydraulic_state() -> Dictionary:
	var enabled := _hydraulic_enabled()
	var physical_food_enabled := _hydraulic_spillway_food_enabled()
	var spillway_food_collected := bool(_hydraulic_spillway_food_cache.get("collected", false))
	var exit_unlocked := (
		not enabled
		or (
			_first_sluice_open
			and _cistern_bridge_installed
			and _borrowed_current_delivery_latched
			and _main_current_restored
		)
	)
	return {
		"hydraulic_enabled": enabled,
		"hydraulic_phase": _hydraulic_phase if enabled else "disabled",
		"first_sluice_open": _first_sluice_open,
		"cistern_bridge_installed": _cistern_bridge_installed,
		"borrowed_current_diverted": _borrowed_current_diverted,
		"borrowed_current_delivery_latched": _borrowed_current_delivery_latched,
		"main_current_restored": _main_current_restored,
		"hydraulic_exit_unlocked": exit_unlocked,
		"hydraulic_spillway_food_enabled": physical_food_enabled,
		"hydraulic_spillway_food_collected": spillway_food_collected,
		"hydraulic_spillway_food_available": physical_food_enabled and not spillway_food_collected,
	}


func _hydraulic_spillway_food_enabled() -> bool:
	return (
		_hydraulic_enabled()
		and _food_test_mode() != FOOD_TEST_NEUTRAL
		and not _hydraulic_spillway_food_cache.is_empty()
	)


func get_preview_state() -> Dictionary:
	_ensure_spec_loaded()
	var generation := {
		"game_mode": _game_mode_id(),
		"food_test": _food_test_mode(),
		"physical_food_spawned_count": _physical_food_spawned_count,
		"physical_food_cache_count": _physical_food_cache_count(),
		"physical_food_cache_available_count": _physical_food_cache_count(true),
		"guide_food_cache_count": _guide_food_cache_count(),
		"guide_food_cache_available_count": _guide_food_cache_count(true),
		"physical_food_opportunity_count": _physical_food_opportunity_count(),
		"physical_food_opportunity_available_count": _physical_food_opportunity_count(true),
		"branch_food_profiles": _branch_food_profiles(),
		"nominal_food_atp": _nominal_food_atp,
		"effective_party_atp": _effective_party_atp_total(),
		"effective_party_atp_capacity": float(PARTY_IDS.size()) * GameState.ATP_MAX_PIPS,
		"scarcity_drain_interval": _scarcity_drain_interval(),
		"scarcity_drain_per_character": _scarcity_drain_amount(),
		"scarcity_drain_ticks": _scarcity_drain_ticks,
		"scarcity_atp_drained": _scarcity_atp_drained,
		"scarcity_active": _food_test_mode() == FOOD_TEST_SCARCITY and not _shelter_reached,
		"scarcity_clock_started": _scarcity_clock_started,
		"scarcity_drain_armed": _scarcity_drain_armed,
		"scarcity_drain_tag": SCARCITY_DRAIN_TAG,
		"contract_id": "stretch_generation_v1",
		"spec_id": str(_spec.get("id", "")),
		"schema": str(_spec.get("schema", "")),
		"title": str(_spec.get("title", "")),
		"complexity_tier": str(_spec.get("source", {}).get("complexity_tier", "")),
		"resolved_budget": _spec.get("budget", {}).duplicate(true),
		"limitations": _spec.get("settings", {}).get("limitations", {}).duplicate(true),
		"world_slot": get_world_slot(),
		"palette_usage": _spec.get("palette_usage", {}).duplicate(true),
		"archetype_chain": _spec.get("archetype_chain", []).duplicate(true),
		"composition": _spec.get("composition", {}).duplicate(true),
		"graybox": _graybox_state(),
		"navigation": get_navigation_state(),
		"chain_count":
		int(
			_spec.get("composition", {}).get(
				"chain_count", (_spec.get("archetype_chain", []) as Array).size()
			)
		),
		"nested_archetype_count": int(_spec.get("composition", {}).get("nested_count", 0)),
		"nested_depth": int(_spec.get("composition", {}).get("nested_depth", 0)),
		"uses_random_walk": bool(_spec.get("composition", {}).get("uses_random_walk", false)),
		"walk_element_count": int(_spec.get("composition", {}).get("walk_element_count", 0)),
		"walk_archetype_count": int(_spec.get("composition", {}).get("walk_archetype_count", 0)),
		"node_count": _nodes().size(),
		"route_count": _routes().size(),
		"completed_nodes": _completed_nodes.duplicate(),
		"activated_routes": _activated_routes.duplicate(),
		"produced_chain_states": _produced_chain_states.duplicate(true),
		"prepared_nested_nodes": _prepared_nested_nodes.duplicate(true),
		"delivered_resource_nodes": _delivered_resource_nodes.duplicate(),
		"route_choice": _route_choice,
		"route_phase": _route_phase,
		"resources_collected": _resources_collected,
		"shortcut_unlocked": _shortcut_unlocked,
		"shelter_reached": _shelter_reached,
		"shelter_rested": _shelter_rested,
		"first_shelter_beat_fired": _first_shelter_beat_fired,
		"last_outcome": _last_outcome,
		"risky_damage_total": _risky_damage_total,
		"atp_foraged": _atp_foraged,
		"pressure_taken": _pressure_taken,
		"rests_taken": _rests_taken,
		"unsupported_placeholder_count": _unsupported_placeholder_count,
		"content_marker_count": _content_marker_count,
		"spatial_fixture_count": _spatial_fixture_count,
		"active_loadout": _active_loadout,
		"active_party": _active_party.duplicate(),
		"blocked_nodes": _blocked_nodes.duplicate(),
		"solution_path": get_active_solution_path(),
		"diagnosis_reads": _diagnosis_reads.duplicate(true),
		"pending_diagnosis": _pending_diagnosis,
		"misdiagnosis_count": _misdiagnosis_count,
		"last_diagnosis_read": _last_diagnosis_read,
		"last_diagnosis_correct": _last_diagnosis_correct,
		"diagnosis_node_count":
		int(_spec.get("headless", {}).get("solution_summary", {}).get("diagnosis_node_count", 0)),
		"solution_summary": _spec.get("headless", {}).get("solution_summary", {}).duplicate(true),
	}
	generation.merge(_hydraulic_state())
	var state := {
		"game_mode": _game_mode_id(),
		"food_test": _food_test_mode(),
		"physical_food_spawned_count": _physical_food_spawned_count,
		"physical_food_cache_count": _physical_food_cache_count(),
		"physical_food_cache_available_count": _physical_food_cache_count(true),
		"guide_food_cache_count": _guide_food_cache_count(),
		"guide_food_cache_available_count": _guide_food_cache_count(true),
		"physical_food_opportunity_count": _physical_food_opportunity_count(),
		"physical_food_opportunity_available_count": _physical_food_opportunity_count(true),
		"branch_food_profiles": _branch_food_profiles(),
		"nominal_food_atp": _nominal_food_atp,
		"effective_party_atp": _effective_party_atp_total(),
		"effective_party_atp_capacity": float(PARTY_IDS.size()) * GameState.ATP_MAX_PIPS,
		"scarcity_drain_interval": _scarcity_drain_interval(),
		"scarcity_drain_per_character": _scarcity_drain_amount(),
		"scarcity_drain_ticks": _scarcity_drain_ticks,
		"scarcity_atp_drained": _scarcity_atp_drained,
		"scarcity_active": _food_test_mode() == FOOD_TEST_SCARCITY and not _shelter_reached,
		"scarcity_clock_started": _scarcity_clock_started,
		"scarcity_drain_armed": _scarcity_drain_armed,
		"scarcity_drain_tag": SCARCITY_DRAIN_TAG,
		"contract_id": "generated_stretch_chunk_v1",
		"spec_id": generation["spec_id"],
		"world_slot": generation["world_slot"],
		"preview_party_preset": "full_party_full_health",
		"route_choice": _route_choice,
		"route_phase": _route_phase,
		"shelter_reached": _shelter_reached,
		"shelter_rested": _shelter_rested,
		"shortcut_unlocked": _shortcut_unlocked,
		"first_shelter_beat_fired": _first_shelter_beat_fired,
		"last_outcome": _last_outcome,
		"risky_damage_total": _risky_damage_total,
		"atp_foraged": _atp_foraged,
		"pressure_taken": _pressure_taken,
		"rests_taken": _rests_taken,
		"unsupported_placeholder_count": _unsupported_placeholder_count,
		"spatial_fixture_count": _spatial_fixture_count,
		"drop_down_count": _drop_downs.size(),
		"branch_cache_count": _branch_caches.size(),
		"branch_atp_collected": _branch_atp_collected,
		"active_loadout": _active_loadout,
		"active_party": _active_party.duplicate(),
		"blocked_nodes": _blocked_nodes.duplicate(),
		"produced_chain_states": _produced_chain_states.duplicate(true),
		"prepared_nested_nodes": _prepared_nested_nodes.duplicate(true),
		"delivered_resource_nodes": _delivered_resource_nodes.duplicate(),
		"solution_path": get_active_solution_path(),
		"pending_diagnosis": _pending_diagnosis,
		"misdiagnosis_count": _misdiagnosis_count,
		"diagnosis_node_count": generation["diagnosis_node_count"],
		"graybox": generation["graybox"],
		"navigation": generation["navigation"],
		"generation": generation,
	}
	state.merge(_hydraulic_state())
	return state


## The unified-grid traversal layer (GridWorld.from_data contract): the preview installs this as the
## scene grid, so characters route on cells with per-cell route risk and ramp links across elevations.
## The semantic nodes/routes (the solver's and replay artifact's representation) are unchanged.
func get_grid_data() -> Dictionary:
	_ensure_spec_loaded()
	_ensure_graybox_layout()
	_ensure_navigation_layout()
	return _nav_grid().duplicate(true)


func get_navigation_state() -> Dictionary:
	_ensure_spec_loaded()
	_ensure_navigation_layout()
	var nav_grid: Dictionary = _spec.get("navigation_grid", {})
	return {
		"contract_id": str(nav_grid.get("contract_id", "")),
		"walkable_cell_count": (nav_grid.get("walkable_cells", []) as Array).size(),
		"link_count": (nav_grid.get("links", []) as Array).size(),
		"level_count": int(nav_grid.get("level_count", 1)),
		"entry_node": str(nav_grid.get("entry_anchor", "")),
		"exit_node": str(nav_grid.get("exit_anchor", "")),
		"supports_multiple_elevations": bool(nav_grid.get("supports_multiple_elevations", false)),
		"elevation_indices": nav_grid.get("elevation_indices", []),
	}


func get_generated_node_position(node_id: String) -> Vector3:
	_ensure_spec_loaded()
	var node := _find_node(node_id)
	if node.is_empty():
		return Vector3.INF
	return _vec3(node.get("position", []), Vector3.INF)


func _clear_experiment_food_items() -> void:
	for item_id in _experiment_food_item_ids:
		if item_id != "":
			_remove_item(item_id)
	_experiment_food_item_ids.clear()


func _reset_experiment_food_state() -> void:
	_clear_experiment_food_items()
	_physical_food_spawned_count = 0
	_nominal_food_atp = 0.0

	for cache in _branch_caches:
		if bool(cache.get("physical_food", false)):
			cache["collected"] = false
			_set_branch_cache_available_visual(cache, true)
			var interactable = cache.get("interactable", null)
			if interactable != null and interactable.has_method("set_interaction_enabled"):
				interactable.call("set_interaction_enabled", true)
	for cache in _guide_food_caches:
		cache["collected"] = false
		_set_branch_cache_available_visual(cache, true)
		var guide_interactable = cache.get("interactable", null)
		if guide_interactable != null and guide_interactable.has_method("set_interaction_enabled"):
			guide_interactable.call("set_interaction_enabled", true)
	if not _hydraulic_spillway_food_cache.is_empty():
		_hydraulic_spillway_food_cache["collected"] = false
		_set_branch_cache_available_visual(_hydraulic_spillway_food_cache, true)
		var spillway_interactable = _hydraulic_spillway_food_cache.get("interactable", null)
		if (
			spillway_interactable != null
			and spillway_interactable.has_method("set_interaction_enabled")
		):
			spillway_interactable.call("set_interaction_enabled", true)

			spillway_interactable.set("input_ray_pickable", false)


func _cancel_scarcity_drain() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(SCARCITY_DRAIN_TAG)
	_scarcity_drain_armed = false


func _reset_scarcity_drain_state() -> void:
	_cancel_scarcity_drain()
	_scarcity_drain_ticks = 0
	_scarcity_atp_drained = 0.0
	_scarcity_clock_started = false


func begin_scarcity_clock() -> bool:
	if _scarcity_clock_started or _food_test_mode() != FOOD_TEST_SCARCITY or _shelter_reached:
		return false
	_scarcity_clock_started = true
	_arm_scarcity_drain()
	_show_message(
		(
			"Metabolic pressure started — each character loses 1 ATP every %.0f seconds."
			% _scarcity_drain_interval()
		),
		2.4
	)
	return _scarcity_drain_armed


func on_preview_movement_started(_char_id: String) -> void:
	begin_scarcity_clock()


func _process(_delta: float) -> void:
	_sync_hydraulic_bridge_blocker()
	if _scarcity_clock_started or _food_test_mode() != FOOD_TEST_SCARCITY or _shelter_reached:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("is_moving"):
		return
	for char_id in PARTY_IDS:
		if bool(gs.call("is_moving", char_id)):
			begin_scarcity_clock()
			return


func _arm_scarcity_drain() -> void:
	if _food_test_mode() != FOOD_TEST_SCARCITY or _shelter_reached:
		return
	var amount := _scarcity_drain_amount()
	if amount <= 0.0:
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag(SCARCITY_DRAIN_TAG)
	sched.schedule_after(_scarcity_drain_interval(), _on_scarcity_drain, SCARCITY_DRAIN_TAG)
	_scarcity_drain_armed = true


func _on_scarcity_drain() -> void:
	_scarcity_drain_armed = false
	if _food_test_mode() != FOOD_TEST_SCARCITY or _shelter_reached:
		return
	var amount := _scarcity_drain_amount()
	var drained_this_tick := 0.0
	for char_id in PARTY_IDS:
		var before := _get_character_stat(char_id, "atp")

		var drained := minf(amount, maxf(0.0, before - SCARCITY_ATP_FLOOR))
		if drained > 0.0:
			_adjust_character_stat(char_id, "atp", -drained)
			drained_this_tick += drained
	_scarcity_drain_ticks += 1
	_scarcity_atp_drained += drained_this_tick
	if drained_this_tick > 0.0:
		_show_message(
			(
				"Metabolic pressure consumed %.0f party ATP. Optional food can recover it."
				% drained_this_tick
			),
			1.3
		)
	_arm_scarcity_drain()


func reset_preview_state() -> void:
	_reset_generated_resource_items()
	_reset_experiment_food_state()
	_reset_scarcity_drain_state()
	_reset_hydraulic_state()
	_route_choice = ""
	_route_phase = "unstarted"
	_completed_nodes.clear()
	_activated_routes.clear()
	_produced_chain_states.clear()
	_prepared_nested_nodes.clear()
	_delivered_resource_nodes.clear()
	_resources_collected = 0
	_shortcut_unlocked = false
	_shelter_reached = false
	_shelter_rested = false
	_last_outcome = "ready"
	_risky_damage_total = 0.0
	_atp_foraged = 0
	_pressure_taken = 0.0
	_rests_taken = 0
	_first_shelter_beat_fired = false
	_node_approach_used.clear()
	_blocked_nodes.clear()
	_pending_diagnosis = ""
	_diagnosis_reads.clear()
	_misdiagnosis_count = 0
	_last_diagnosis_read = ""
	_last_diagnosis_correct = false
	_rearm_exit_shelter_interaction()
	set_active_loadout(_active_loadout)
	_restore_party()
	_set_preview_step("generated_stretch_ready")
	if _hydraulic_enabled():
		call_deferred("_introduce_first_hydraulic_step")


## Choose which party is solving the stretch. "spotlight" is the full party (a
## specialist is on hand); "shadow" is the Aster+Peris pair. The active loadout's
## capabilities decide which approach each puzzle node accepts — and whether it blocks.
func set_active_loadout(loadout_id: String) -> void:
	var roster = _roster()
	for loadout in CapabilitiesScript.loadouts(roster):
		if str(loadout.get("id", "")) == loadout_id:
			_active_loadout = loadout_id
			_active_party.clear()
			for cid in loadout.get("party", []):
				_active_party.append(str(cid))
			_active_capabilities = (loadout.get("base_capabilities", {}) as Dictionary).duplicate()
			_enforce_stage = bool(loadout.get("enforce_stage", false))
			return

	# An unrecognised loadout id should never reach here (the only ids are spotlight/shadow);
	# warn rather than silently masquerade as spotlight, so a typo is caught instead of hidden.
	if loadout_id != "spotlight":
		push_warning(
			"generated_stretch_chunk: unknown loadout '%s' — defaulting to spotlight" % loadout_id
		)
	_active_loadout = "spotlight"
	_active_party.clear()
	for cid in CapabilitiesScript.normalize_roster(roster).get("enabled", []) as Array:
		_active_party.append(str(cid))
	_active_capabilities = CapabilitiesScript.roster_capabilities(roster)
	_enforce_stage = true


## The enabled roster this stretch was generated for (the enable/disable choices), read from
## the spec. Empty means the full canonical six.
func _roster():
	return _spec.get("source", {}).get("roster", _spec.get("settings", {}).get("roster", []))


## How far the player is assumed to have progressed — the first-play full party may only
## use techniques taught up to this stage. Read from the spec the generator produced.
func _progression_stage() -> int:
	return int(
		_spec.get("source", {}).get(
			"progression_stage", _spec.get("settings", {}).get("progression_stage", 99)
		)
	)


## The first approach the active party can field on this node, given its own
## capabilities plus any tool placed on the node. Marked blocked when none fit.
func _resolve_node_approach(node: Dictionary) -> Dictionary:
	var approaches: Array = node.get("approaches", [])
	if approaches.is_empty():
		return {"approach_id": "traverse", "kind": "traverse", "party": "any", "blocked": false}
	if _active_capabilities.is_empty():
		set_active_loadout(_active_loadout)
	var node_stage := int(node.get("stage", 1))
	var prog := _progression_stage()
	var available := _active_capabilities.duplicate()
	for tag in CapabilitiesScript.node_content_capabilities(node, _roster()).keys():
		available[tag] = true
	for approach in approaches:
		if not (approach is Dictionary):
			continue
		var ap := approach as Dictionary
		if _enforce_stage and int(ap.get("min_stage", node_stage)) > prog:
			continue  # technique not yet taught at this point in the campaign
		if CapabilitiesScript.requirements_met(ap.get("requires", []), available):
			var resolved := ap.duplicate()
			resolved["blocked"] = false
			return resolved
	return {"approach_id": "", "kind": "blocked", "party": "", "blocked": true}


## Generated geometry may put a later marker within clicking distance, but causal
## progression still follows the semantic node chain. A non-main route may bypass
## that chain only after the route itself has been explicitly activated from a
## completed source node. This keeps every seed honest without hard-coding node ids.
func _node_progression_ready(node_id: String) -> bool:
	if _hydraulic_enabled():
		# The authored Channels puzzle has its own stronger, state-based gates.
		return true
	var predecessor := _required_progression_predecessor(node_id)
	if predecessor == "" or _completed_nodes.has(predecessor):
		return true
	for route_v in _routes():
		if not (route_v is Dictionary):
			continue
		var route := route_v as Dictionary
		if (
			str(route.get("to", "")) == node_id
			and _activated_routes.has(str(route.get("id", "")))
			and _completed_nodes.has(str(route.get("from", "")))
		):
			return true
	var predecessor_node := _find_node(predecessor)
	var predecessor_title := str(predecessor_node.get("title", predecessor)).strip_edges()
	_route_phase = "blocked"
	_last_outcome = "order_blocked:%s:%s" % [node_id, predecessor]
	_set_preview_step("generated_stretch_order_blocked")
	_highlight_node(predecessor, true)
	_show_message("A previous change has not taken effect yet.", 1.4)
	_show_note("RESOLVE FIRST // %s" % predecessor_title, 3.0)
	return false


func _required_progression_predecessor(node_id: String) -> String:
	var nodes := _nodes()
	var node_index := -1
	for index in range(nodes.size()):
		var node_v: Variant = nodes[index]
		if node_v is Dictionary and str((node_v as Dictionary).get("id", "")) == node_id:
			node_index = index
			break
	if node_index <= 0:
		return ""
	for index in range(node_index - 1, -1, -1):
		var previous_v: Variant = nodes[index]
		if not (previous_v is Dictionary):
			continue
		var previous := previous_v as Dictionary
		if bool(previous.get("optional", false)):
			continue
		var previous_id := str(previous.get("id", ""))
		# The party begins inside the entry boundary; the first interior beat is ready.
		return "" if previous_id == "entry" else previous_id
	return ""


func activate_generated_node(node_id: String) -> bool:
	_ensure_spec_loaded()
	var node := _find_node(node_id)
	if node.is_empty():
		_last_outcome = "missing_node:%s" % node_id
		return false
	if not _hydraulic_progress_ready(node_id):
		return false
	if not _completed_nodes.has(node_id) and not _node_progression_ready(node_id):
		return false
	if not _completed_nodes.has(node_id) and not _chain_progression_ready(node):
		return false
	var approach := _resolve_node_approach(node)
	if bool(approach.get("blocked", false)):
		if not _blocked_nodes.has(node_id):
			_blocked_nodes.append(node_id)
		_route_phase = "blocked"
		_last_outcome = "blocked:%s" % node_id
		_set_preview_step("generated_stretch_blocked")
		_show_note(
			(
				"%s has no way through %s."
				% [_active_loadout.capitalize(), str(node.get("title", node_id))]
			),
			2.0
		)
		return false

	# A diagnosis node is cleared by NAMING the correct read, not by walking up. If it hasn't
	# been diagnosed yet, commit the clean (correct) read — the data-layer solve. A player
	# picks a specific perspective through diagnose_generated_node (where a wrong read stings).
	if _is_diagnosis_node(node) and not _diagnosis_reads.has(node_id):
		return diagnose_generated_node(node_id, _correct_read_id(node))
	if (
		not _completed_nodes.has(node_id)
		and not (node.get("nested_archetypes", []) as Array).is_empty()
		and not _prepared_nested_nodes.has(node_id)
	):
		var nested_entries: Array = node.get("nested_archetypes", [])
		var nested_entry: Dictionary = nested_entries[0] if not nested_entries.is_empty() and nested_entries[0] is Dictionary else {}
		var nested_prepared_state := "flora_support_ready" if bool(node.get("carry_payload", false)) else "nested_dependency_ready"
		_prepared_nested_nodes[node_id] = {
			"host_step": int(nested_entry.get("host_step", 0)),
			"prepared_state": nested_prepared_state,
		}
		_route_phase = "nested_support"
		_last_outcome = "nested_prepared:%s" % node_id
		_set_preview_step("generated_stretch_nested_prepared")
		var nested_interactable: Node = _node_interactables.get(node_id, null)
		if nested_interactable != null and is_instance_valid(nested_interactable):
			nested_interactable.set("tutorial_label", "TAKE SUPPORTED LOAD" if bool(node.get("carry_payload", false)) else "APPLY NESTED OUTPUT")
		_highlight_node(node_id, true)
		if bool(node.get("carry_payload", false)):
			_show_message("Flora support is ready. Take the stabilized load.", 1.8)
			_show_note("NESTED OUTPUT → CARRY INPUT // Interact again to accept the load.", 3.0)
		else:
			_show_message("The nested dependency is ready. Apply its output.", 1.8)
			_show_note("NESTED OUTPUT READY // Interact again to propagate the change.", 3.0)
		return false
	_node_approach_used[node_id] = approach
	var first_completion := not _completed_nodes.has(node_id)
	var survival := str(node.get("survival_kind", ""))
	if (
		first_completion
		and bool(node.get("resource", false))
		and survival == ""
		and not _secure_generated_resource(node)
	):
		return false
	if first_completion:
		_completed_nodes.append(node_id)
		var chain_output_ref := str(node.get("chain_output_ref", ""))
		if chain_output_ref != "":
			_produced_chain_states[chain_output_ref] = node_id
	var role := str(node.get("role", ""))
	if first_completion:
		match survival:
			"forage":
				if not (node_id == "node_04" and _hydraulic_spillway_food_enabled()):
					_apply_forage_reward(node)
			"gauntlet", "hazard":
				_apply_node_pressure(node, approach)
			"exploit":
				_last_outcome = "exploit:%s" % str(node.get("exploit_target", "predator_prey"))
				_show_message("Turned the ecology against itself.", 1.0)
			"rest":
				_rests_taken += 1
				_restore_party()
				_show_message("Rested before dusk.", 1.0)

		# Plain generated resources are physical tools carried in the portrait/inventory;
		# they are not silently converted into a full heal or auto-consumed as food.
		if bool(node.get("resource", false)) and survival == "":
			if str(node.get("reward_kind", "")) == "food":
				_show_message("Lysate secured for a later ATP decision.", 1.8)
			else:
				_show_message("Resource secured and held for deployment.", 1.8)
		if bool(node.get("shortcut", false)) or role == "shortcut":
			_shortcut_unlocked = true
			_show_message("Shortcut marked for return.", 1.0)
	if role == "shelter" or node_id == "exit_shelter":
		if first_completion:
			_reach_exit_shelter()
	else:
		_route_phase = "moving"
		_last_outcome = "node:%s" % node_id
		_set_preview_step("generated_stretch_%s" % node_id)
	if node_id == "node_04":
		_latch_borrowed_current_delivery()
		if (
			_hydraulic_spillway_food_enabled()
			and not bool(_hydraulic_spillway_food_cache.get("collected", false))
		):
			_collect_hydraulic_spillway_food()
	_highlight_node(node_id, true)
	return true


func _chain_progression_ready(node: Dictionary) -> bool:
	var input_ref := str(node.get("chain_input_ref", ""))
	if input_ref == "" or _produced_chain_states.has(input_ref):
		return true
	var producer_id := ""
	for candidate_v in _nodes():
		if candidate_v is Dictionary and str((candidate_v as Dictionary).get("chain_output_ref", "")) == input_ref:
			producer_id = str((candidate_v as Dictionary).get("id", ""))
			break
	_route_phase = "blocked"
	_last_outcome = "chain_state_missing:%s:%s" % [str(node.get("id", "")), input_ref]
	_set_preview_step("generated_stretch_chain_state_blocked")
	if producer_id != "":
		_highlight_node(producer_id, true)
	_show_message("The required upstream state has not arrived yet.", 1.6)
	_show_note("MISSING INPUT // %s" % input_ref.replace(":", " → "), 3.0)
	return false


func _headless_activate_generated_node(node_id: String) -> bool:
	var activated := activate_generated_node(node_id)
	if not activated and _last_outcome == "nested_prepared:%s" % node_id:
		return activate_generated_node(node_id)
	return activated


## True when a node is the three-read diagnosis primitive — it presents one read per
## character perspective and is cleared by naming the correct one.
func _is_diagnosis_node(node: Dictionary) -> bool:
	return (
		str(node.get("kind", "")) == "diagnosis"
		or str(node.get("solve", "")) == "deduce"
		or not (node.get("reads", []) as Array).is_empty()
	)


## The reads a diagnosis node offers (one per perspective), or [] for a non-diagnosis node.
func get_diagnosis_reads(node_id: String) -> Array:
	var node := _find_node(node_id)
	return (node.get("reads", []) as Array).duplicate(true)


func _correct_read_id(node: Dictionary) -> String:
	var explicit := str(node.get("correct_read", "")).strip_edges()
	if explicit != "":
		return explicit
	for read in node.get("reads", []):
		if read is Dictionary and bool((read as Dictionary).get("correct", false)):
			return str((read as Dictionary).get("id", ""))
	return ""


func _read_def(node: Dictionary, read_id: String) -> Dictionary:
	for read in node.get("reads", []):
		if read is Dictionary and str((read as Dictionary).get("id", "")) == read_id:
			return (read as Dictionary).duplicate(true)
	return {}


## Commit a perspective read at a diagnosis node — the data-layer path a real pick (the read
## buttons) and a headless/CLI run both use. The CORRECT read clears the node cleanly; a WRONG
## read is a pressure setback (the read's penalty) and leaves the node UNRESOLVED so the player
## can try again — a misdiagnosis penalises, it never hard-blocks.
func diagnose_generated_node(node_id: String, read_id: String) -> bool:
	_ensure_spec_loaded()
	var node := _find_node(node_id)
	if node.is_empty() or not _is_diagnosis_node(node):
		_last_outcome = "not_diagnosis:%s" % node_id
		return false
	var correct_id := _correct_read_id(node)
	if read_id == "":
		read_id = correct_id
	var read := _read_def(node, read_id)
	var is_correct := read_id == correct_id and correct_id != ""
	_last_diagnosis_read = read_id
	_last_diagnosis_correct = is_correct
	if not is_correct:
		var penalty := maxf(1.0, float(read.get("penalty", 2)))
		var damage := penalty * 8.0
		_misdiagnosis_count += 1
		_pressure_taken += damage
		for char_id in PARTY_IDS:
			_adjust_character_stat(char_id, "hp", -damage)
			_adjust_character_stat(char_id, "stamina", -damage * 0.5)
		_pending_diagnosis = node_id
		_route_phase = "misdiagnosis"
		_last_outcome = "misdiagnosis:%s:%s" % [node_id, read_id]
		_set_preview_step("generated_stretch_misdiagnosis")
		var note := str(read.get("note", "Wrong read — the repair skews and the gear is rejected."))
		_show_note("%s %s" % [str(read.get("label", read_id)).to_upper() + " //", note], 2.5)
		return false

	# Correct read — clear the node like a normal solve.
	_diagnosis_reads[node_id] = read_id
	_pending_diagnosis = ""
	var approach := _resolve_node_approach(node)
	_node_approach_used[node_id] = approach
	if not _completed_nodes.has(node_id):
		_completed_nodes.append(node_id)
	_route_phase = "diagnosed"
	_last_outcome = "diagnosed:%s:%s" % [node_id, read_id]
	_set_preview_step("generated_stretch_%s" % node_id)
	_highlight_node(node_id, true)
	_show_message("Correct read: %s." % str(read.get("label", read_id)), 1.2)
	return true


func choose_generated_route(route_id: String, activate_target := true) -> bool:
	_ensure_spec_loaded()
	var route := _find_route(route_id)
	if route.is_empty():
		_last_outcome = "missing_route:%s" % route_id
		return false
	_route_choice = route_id
	if not _activated_routes.has(route_id):
		_activated_routes.append(route_id)
	var risk := _route_risk_value(route)
	var kind := _route_kind(route)
	if kind == "risky" or risk > 1:
		_apply_risky_pressure(risk, route)
		_route_phase = "recovering" if str(route.get("recovery", "")) != "" else "danger"
	elif kind == "shortcut":
		_shortcut_unlocked = true
		_route_phase = "shortcut"
	else:
		_route_phase = "moving"
	_last_outcome = "route:%s" % route_id
	_set_preview_step("generated_stretch_%s" % route_id)
	var target := str(route.get("to", ""))
	if activate_target and target != "":
		activate_generated_node(target)
	return true


func run_generated_golden_path() -> bool:
	_ensure_spec_loaded()
	reset_preview_state()
	set_active_loadout("spotlight")
	_headless_complete_hydraulic_puzzle()
	_route_phase = "golden"
	var path: Array = _spec.get("headless", {}).get("golden_path", [])
	if path.is_empty():
		path = ["entry", "exit_shelter"]
	for node_id in path:
		_headless_activate_generated_node(str(node_id))
	if not _shelter_rested and _blocked_nodes.is_empty():
		_reach_exit_shelter()
	_route_choice = "golden_path"
	return _shelter_rested


## The emitted solution as replayable data (spec.headless.solution) — the ordered, per-node approach a full party
## takes to clear the golden path. For tests + an in-game/Android replay to CONSUME (not re-derive).
func get_solution_script() -> Dictionary:
	_ensure_spec_loaded()
	return (_spec.get("headless", {}).get("solution", {}) as Dictionary).duplicate(true)


## REPLAY the emitted solution end-to-end at the data layer, CONSUMING spec.headless.solution (not re-deriving the
## plan): drive each node in the solution's order and check the approach that actually clears it MATCHES the emitted
## approach_id — so the shipped solution data faithfully describes a real playthrough. Returns
## {complete, steps, approach_mismatches, blocked}. `complete` proves the emitted solution beats the puzzle.
func replay_generated_solution() -> Dictionary:
	_ensure_spec_loaded()
	reset_preview_state()
	var sol: Dictionary = _spec.get("headless", {}).get("solution", {})
	set_active_loadout(str(sol.get("loadout", "spotlight")))
	_headless_complete_hydraulic_puzzle()
	_route_phase = "solution_replay"
	var actions: Array = sol.get("actions", [])
	var mismatches := 0
	var steps := 0
	for action in actions:
		if not (action is Dictionary):
			continue
		var node_id := str((action as Dictionary).get("node", ""))
		_headless_activate_generated_node(node_id)
		steps += 1
		var used: Dictionary = _node_approach_used.get(node_id, {})
		var used_id := str(used.get("id", used.get("approach_id", "")))
		var want_id := str((action as Dictionary).get("approach_id", ""))

		# Only real puzzle approaches are comparable — traverse / entry / exit carry no chosen approach.
		if want_id != "" and want_id != "traverse" and used_id != "" and used_id != want_id:
			mismatches += 1
	if not _shelter_rested and _blocked_nodes.is_empty():
		_reach_exit_shelter()
	_route_choice = "solution_replay"
	return {
		"complete": _shelter_rested,
		"steps": steps,
		"approach_mismatches": mismatches,
		"blocked": _blocked_nodes.duplicate(),
	}


## The shadow solution: the same node spine solved by the Aster+Peris pair alone.
## Each puzzle node falls through to its shadow approach (no specialist on hand), so a
## completed shadow run is a genuinely different solution path than the golden run.
func run_generated_shadow_path() -> bool:
	_ensure_spec_loaded()
	reset_preview_state()
	set_active_loadout("shadow")
	_headless_complete_hydraulic_puzzle()
	_route_phase = "shadow"
	var path: Array = _spec.get("headless", {}).get("golden_path", [])
	if path.is_empty():
		path = ["entry", "exit_shelter"]
	for node_id in path:
		_headless_activate_generated_node(str(node_id))
	if not _shelter_rested and _blocked_nodes.is_empty():
		_reach_exit_shelter()
	_route_choice = "shadow_path"
	return _shelter_rested


## The approaches the active party actually used, in the order nodes were cleared —
## the data an in-game or Android replay animates.
func get_active_solution_path() -> Array:
	var path := []
	for node_id in _completed_nodes:
		var approach: Dictionary = _node_approach_used.get(node_id, {})
		(
			path
			. append(
				{
					"node": node_id,
					"approach_id": str(approach.get("id", approach.get("approach_id", ""))),
					"kind": str(approach.get("kind", "")),
					"party": str(approach.get("party", "")),
					"label": str(approach.get("label", "")),
					"risk": str(approach.get("risk", "")),
				}
			)
		)
	return path


func run_generated_risky_recovery() -> bool:
	_ensure_spec_loaded()
	reset_preview_state()
	_headless_complete_hydraulic_puzzle()
	var risky_route := {}
	for route in _routes():
		if route is Dictionary and _route_kind(route as Dictionary) == "risky":
			risky_route = (route as Dictionary).duplicate(true)
			break
	if risky_route.is_empty():
		_route_choice = "no_risky_route"
		_route_phase = "recovered"
		return run_generated_golden_path()
	var path: Array = _spec.get("headless", {}).get("golden_path", [])
	var source_id := str(risky_route.get("from", ""))
	var source_index := path.find(source_id)
	if source_index < 0:
		_route_choice = "risky_recovery_invalid_source"
		return false
	for index in range(source_index + 1):
		_headless_activate_generated_node(str(path[index]))
	choose_generated_route(str(risky_route.get("id", "")), false)
	_headless_activate_generated_node(str(risky_route.get("to", "")))
	for index in range(source_index + 1, path.size()):
		_headless_activate_generated_node(str(path[index]))
	_reach_exit_shelter()
	if _route_choice == "" or _route_choice == "no_risky_route":
		_route_choice = "risky_recovery"
	return _shelter_rested


## A failed traversal: the party commits to the risky route and takes the
## pressure, but is stranded short of the next shelter — the stretch is never
## crossed. Returns false (the run did not reach safety).
func run_generated_failed_traversal() -> bool:
	_ensure_spec_loaded()
	reset_preview_state()
	for route in _routes():
		if route is Dictionary and _route_kind(route as Dictionary) == "risky":
			choose_generated_route(str((route as Dictionary).get("id", "")), false)
			break
	if _route_choice == "":
		_route_choice = "failed_traversal"
	_route_phase = "failed"
	_shelter_reached = false
	_shelter_rested = false
	_last_outcome = "stranded"
	_set_preview_step("generated_stretch_failed")
	return _shelter_rested


func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	match ability_id:
		"aster_focus":
			return {
				"message": "Aster reads the generated route.",
				"note": "Node labels and route colors expose the spec.",
				"state": "active",
				"duration": 0.35,
				"remaining": 0.35,
			}
		"peris_tune":
			return {
				"message": "Peris tunes the flora placeholders.",
				"note": "Unsupported flora remains visible as labeled graybox affordances.",
				"state": "active",
				"duration": 0.35,
				"remaining": 0.35,
			}
		"endo_patch":
			_shortcut_unlocked = true
			return {
				"message": "Endo marks the shortcut.",
				"note": "Shortcut state is now exposed in chunk preview state.",
				"state": "active",
				"duration": 0.35,
				"remaining": 0.35,
			}
	return {}


func _load_spec_from_config() -> void:
	var raw_spec: Variant = _config.get("spec", {})
	if raw_spec is Dictionary and not (raw_spec as Dictionary).is_empty():
		_spec = (raw_spec as Dictionary).duplicate(true)
		_ensure_graybox_layout()
		_ensure_navigation_layout()
		return
	var raw_settings: Variant = _config.get("settings", {})
	if raw_settings is Dictionary and not (raw_settings as Dictionary).is_empty():
		var generation_settings := (raw_settings as Dictionary).duplicate(true)
		if _config.has("seed"):
			generation_settings["seed"] = int(_config.get("seed", generation_settings.get("seed", 1)))
		var generated: Dictionary = StretchGeneratorScript.generate(generation_settings)
		if bool(generated.get("success", false)):
			_spec = generated
			_ensure_graybox_layout()
			_ensure_navigation_layout()
			return
		push_warning("generated_stretch: custom settings failed: %s" % str(generated.get("validation", generated.get("error", "unknown error"))))
	var path := str(_config.get("spec_path", default_spec_path))
	var loaded := StretchGeneratorScript.load_spec(path)
	if not loaded.is_empty():
		# A saved case is a configuration snapshot, not a frozen result. Supplying a
		# seed regenerates the same profile so N/custom QA variations exercise the
		# current generator rules rather than stale serialized geometry.
		if _config.has("seed") and loaded.get("settings", {}) is Dictionary:
			var loaded_settings := (loaded.get("settings", {}) as Dictionary).duplicate(true)
			loaded_settings["seed"] = int(_config.get("seed", loaded_settings.get("seed", 1)))
			var regenerated: Dictionary = StretchGeneratorScript.generate(loaded_settings)
			if bool(regenerated.get("success", false)):
				loaded = regenerated
			else:
				push_warning("generated_stretch: seed variation failed, using saved spec: %s" % str(regenerated.get("validation", regenerated.get("error", "unknown error"))))
		_spec = loaded
		_ensure_graybox_layout()
		_ensure_navigation_layout()


func _ensure_spec_loaded() -> void:
	if not _spec.is_empty():
		return
	_config = {"spec_path": default_spec_path}
	_load_spec_from_config()
	if _spec.is_empty():
		_spec = (
			StretchGeneratorScript
			. generate(
				{
					"id": "generated_fallback_stretch",
					"title": "Generated Fallback Stretch",
					"seed": 1701,
					"complexity_tier": "teaching",
				}
			)
		)
	_ensure_graybox_layout()
	_ensure_navigation_layout()


func _clear_generated_children() -> void:
	for child in get_children():
		child.free()

	_causal_feedback_links.clear()
	_interactables.clear()
	_node_markers.clear()
	_node_targets.clear()
	_node_interactables.clear()
	_route_surfaces.clear()


func _build_foundation() -> void:
	# The floor is built FROM the walkable grid cells as atlas TILES — so the visible surface (and its collision)
	# is EXACTLY where the player can walk. No more big rectangular slab that eats clicks the grid then rejects.
	_build_walkable_floor()
	var graybox: Dictionary = _spec.get("graybox", {})
	var bounds: Dictionary = graybox.get("bounds", {})
	var bounds_center := _vec3(bounds.get("center", []), Vector3(12.0, 0.0, 0.0))
	var bounds_size := _vec3(bounds.get("size", []), Vector3(24.0, 3.0, 10.0))
	var min_point := _vec3(bounds.get("min", []), bounds_center - bounds_size * 0.5)
	_add_light(
		self,
		Vector3(bounds_center.x, min_point.y + 8.0, bounds_center.z),
		Color(0.72, 0.86, 0.96),
		1.25,
		maxf(34.0, bounds_size.x * 0.5)
	)


## Draw a tiled floor quad for every WALKABLE grid cell (per level), risky cells rusted, and give it collision so
## the player's ground-click raycast only lands where they can actually move. Visible floor == traversable floor.
func _build_walkable_floor() -> void:
	var nav: Dictionary = _nav_grid()
	if nav.is_empty():
		return
	var grid = GridWorld.from_data(nav)
	var cell := float(nav.get("cell_size", 1.0))
	var risk := {}
	for r in nav.get("risk_cell_list", []):
		if r is Dictionary and r.has("cell"):
			risk[Vector2i(int((r.cell as Array)[0]), int((r.cell as Array)[1]))] = true
	var cells_by_level := {}
	var level_cells: Array = nav.get("level_cells", [])
	if not level_cells.is_empty():
		for entry in level_cells:
			if entry is Dictionary:
				cells_by_level[int(entry.get("level", 0))] = entry.get("cells", [])
	else:
		cells_by_level[0] = nav.get("walkable_cells", [])
	for lvl in cells_by_level.keys():
		_build_floor_surface(grid, int(lvl), cells_by_level[lvl], risk, cell)


func _build_floor_surface(grid, lvl: int, cells: Array, risk: Dictionary, cell: float) -> void:
	var st_main := SurfaceTool.new()
	st_main.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_risk := SurfaceTool.new()
	st_risk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_risk := false
	var h := cell * 0.5
	for cp in cells:
		var v := Vector2i(int((cp as Array)[0]), int((cp as Array)[1]))
		var w: Vector3 = grid.grid_to_world(v, lvl)
		var is_risk: bool = risk.has(v)
		if is_risk:
			has_risk = true

		# Top surface at floor Y (+0.02 so overlays read above it); a thin SOLID slab so the click-raycast
		# reliably lands on it (a flat zero-thickness trimesh doesn't register a downward ray). Each tile's
		# top CORNERS are warped through the coord map individually — adjacent cells share their flat corner
		# points, so their warped vertices coincide and the deck stays watertight with a tile seam on every
		# data-cell boundary at every lane (a rigid per-cell frame left wedge gaps where the warp fans the
		# outer lanes). Flat levels warp through identity and get the same axis-aligned tile as before.
		var corners := [
			_warp_pos(w + Vector3(-h, 0.0, -h)),
			_warp_pos(w + Vector3(h, 0.0, -h)),
			_warp_pos(w + Vector3(h, 0.0, h)),
			_warp_pos(w + Vector3(-h, 0.0, h)),
		]
		_add_floor_slab(st_risk if is_risk else st_main, corners, 0.16)
	_commit_floor_surface(st_main, "GeneratedFloor_L%d" % lvl, _tiled_floor_material("deck_metal"))
	if has_risk:
		_commit_floor_surface(
			st_risk, "GeneratedFloorRisk_L%d" % lvl, _tiled_floor_material("rust_iron")
		)


## A thin box (floor tile with thickness) built from four already-warped TOP corner points (order: -s-lane,
## +s-lane, +s+lane, -s+lane in the flat frame). Its top sits +0.02 above the corners (just above the deck so
## overlays read) and drops `thick` straight down. A closed solid so its trimesh collision is a dependable ray
## target from above (a flat quad isn't). Because the corners are warped per-vertex, adjacent cells share
## corner points and the deck tiles watertight on flat AND warped levels alike.
func _add_floor_slab(st: SurfaceTool, corners: Array, thick: float) -> void:
	var lift := Vector3.UP * 0.02
	var drop := Vector3.DOWN * thick
	var A: Vector3 = corners[0] + lift
	var B: Vector3 = corners[1] + lift
	var C: Vector3 = corners[2] + lift
	var D: Vector3 = corners[3] + lift
	var E := A + drop
	var F := B + drop
	var G := C + drop
	var H := D + drop
	_tri_auto(st, A, C, B)
	_tri_auto(st, A, D, C)  # top
	_tri_auto(st, E, F, G)
	_tri_auto(st, E, G, H)  # bottom
	_tri_auto(st, A, B, F)
	_tri_auto(st, A, F, E)  # -lane side
	_tri_auto(st, D, H, G)
	_tri_auto(st, D, G, C)  # +lane side
	_tri_auto(st, A, E, H)
	_tri_auto(st, A, H, D)  # -s side
	_tri_auto(st, B, C, G)
	_tri_auto(st, B, G, F)  # +s side


## Emit one triangle with its face normal derived from the (possibly warped) vertices themselves.
func _tri_auto(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	st.set_normal(n.normalized() if n.length_squared() > 1e-12 else Vector3.UP)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _commit_floor_surface(st: SurfaceTool, node_name: String, mat: Material) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = node_name + "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)


func _build_generated_routes() -> void:
	for route in _routes():
		if not (route is Dictionary):
			continue
		var route_def := route as Dictionary
		var from_pos := _node_position(str(route_def.get("from", "")))
		var to_pos := _node_position(str(route_def.get("to", "")))
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		_build_route_segment(route_def, from_pos, to_pos)


func _build_route_segment(route: Dictionary, from_pos: Vector3, to_pos: Vector3) -> void:
	var middle := (from_pos + to_pos) * 0.5
	var delta := to_pos - from_pos
	var horizontal_length := maxf(0.8, sqrt(delta.x * delta.x + delta.z * delta.z))
	var width := maxf(0.4, float(route.get("width", route.get("surface", {}).get("width", 1.2))))
	var route_rotation := Vector3(0.0, atan2(delta.z, delta.x), -atan2(delta.y, horizontal_length))

	# Visual-only accent (no collision) — the tiled walkable floor owns click collision, so a straight route box
	# spanning non-walkable cells can't eat a click.
	var route_box := _add_graybox_slab(
		self,
		middle + Vector3(0.0, 0.045, 0.0),
		Vector3(horizontal_length, 0.09, width),
		_route_color(route),
		"Route_%s" % str(route.get("id", "")),
		route_rotation,
		false
	)
	_route_surfaces[str(route.get("id", ""))] = route_box
	var label_pos := middle + Vector3(0.0, 0.82, 0.0)
	var route_label := "%s / R%d" % [_route_kind(route).to_upper(), _route_risk_value(route)]
	if _route_kind(route) == "risky":
		route_label = "RISKY // -%s HP EACH" % _atp_amount_text(_route_damage_amount(route))
	_add_label(
		self,
		route_label,
		label_pos,
		_route_color(route).lightened(0.28)
	)


## Build the meta-template's RETURN POINTS: DROP portals (fall a loop forward + down) and CLIMBVINES (climb the
## same stack back UP). The template decides WHERE (the spiral stacks a cell one turn ahead directly below); the
## chunk builds the physical PortalPad + climbvine visual at the warped positions. Both are PortalPads (which map
## the warped destination back through the coord_map to a flat cell, so it stays replay-safe); the climbvine adds
## a vertical vine mesh so it reads as "climb up here". Standalone (no host game_state) they still render.
func _build_return_points() -> void:
	if _coord_map == null or _meta_template == null:
		return
	var gs = _get_game_state()
	var specs: Array = _meta_template.return_point_specs(
		_spec.get("navigation_grid", {}), _coord_map
	)
	var drops := 0
	var climbs := 0
	for spec in specs:
		var kind := str(spec.get("kind", "drop"))
		var upper: Vector3 = spec.get("upper", Vector3.ZERO)
		var lower: Vector3 = spec.get("lower", Vector3.ZERO)
		if kind == "climb":
			# CLIMBVINE: stands on the LOWER deck, returns you UP to the upper turn. A tall vine mesh marks it.
			var pad := PortalPad.new()
			pad.name = "Climbvine_%d" % climbs
			pad.configure(
				gs,
				_coord_map.to_world(lower),
				_coord_map.to_world(upper),
				1.3,
				Color(0.42, 0.82, 0.4)
			)
			add_child(pad)
			_add_climbvine_visual(pad)
			_register_interactable(pad)
			_climbvines.append(pad)
			climbs += 1
		else:
			# DROP: stands on the UPPER deck, falls down the shortcut to the lower turn.
			var pad := PortalPad.new()
			pad.name = "SpiralDrop_%d" % drops
			pad.configure(
				gs,
				_coord_map.to_world(upper),
				_coord_map.to_world(lower),
				1.3,
				Color(0.5, 0.85, 1.0)
			)
			add_child(pad)
			_register_interactable(pad)
			_drop_downs.append(pad)
			drops += 1


## A tall green vine climbing out of a climbvine pad — the visual cue that this return point goes UP (vs the flat
## disc of a drop pad). Cosmetic; the pad owns the teleport.
func _add_climbvine_visual(pad: Node3D) -> void:
	var vine := _add_box(
		pad,
		Vector3(0.0, 1.6, 0.0),
		Vector3(0.22, 3.2, 0.22),
		Color(0.32, 0.62, 0.34),
		Color(0.4, 0.85, 0.42),
		0.5,
		"Vine"
	)
	vine.rotation.z = 0.08


## How many drop-down / climbvine return points the meta-template placed (0 on a flat / too-short stretch).
func get_drop_down_count() -> int:
	return _drop_downs.size()


func get_climbvine_count() -> int:
	return _climbvines.size()


## Place a SALVAGE CACHE at the far end of every branch spoke: an optional, one-shot forage reward the player has
## to detour off the spine to reach. This is the risk/reward that makes a run cost real day/night time (explore the
## spokes for ATP, or push straight to the shelter). Warped onto the helix like the node dressing.
const BRANCH_ATP := 2


func _build_branch_content() -> void:
	if _coord_map == null:
		return
	var nav := _nav_grid()
	var branches: Array = nav.get("branches", [])
	if branches.is_empty():
		return
	var grid = GridWorld.from_data(nav)
	for i in range(branches.size()):
		var b: Dictionary = branches[i]
		var far := _branch_far_cell(b.get("cells", []), b.get("neck", [0, 0]))
		if far == Vector2i(2147483647, 0):
			continue
		var food_profile := _branch_food_profile(b, far)
		var reward_atp := int(food_profile.get("food_atp", BRANCH_ATP))
		var flat: Vector3 = grid.grid_to_world(far)
		_build_branch_service_bay(i, flat, reward_atp)
		var physical_food := _food_test_mode() in [FOOD_TEST_RETURN_LOOP, FOOD_TEST_SCARCITY]
		var color := Color(0.95, 0.78, 0.28)
		if physical_food:
			color = Color(0.50, 0.76, 0.34).lightened(0.08 * float(reward_atp - BRANCH_ATP))
		var marker_size := 0.62 + 0.12 * float(reward_atp - BRANCH_ATP)
		var marker := _add_box(
			self,
			flat + Vector3(0.0, 0.42, 0.0),
			Vector3(marker_size, marker_size, marker_size),
			color,
			color.lightened(0.3),
			0.4,
			"BranchCache_%d" % i
		)
		var interactable := _add_inspection_interactable(
			self,
			"BranchCacheZone_%d" % i,
			"Salvage cache",
			flat + Vector3(0.0, 0.12, 0.0),
			"SALVAGE",
			"",
			1.6,
			true
		)
		interactable.interacted.connect(Callable(self, "_collect_branch_reward").bind(i))
		_add_outline_target(
			self,
			"BranchCacheTarget_%d" % i,
			flat + Vector3(0.0, 0.5, 0.0),
			Vector3(1.2, 1.0, 1.2),
			[marker] as Array[MeshInstance3D],
			"branch_cache_%d" % i,
			interactable
		)

		_branch_caches.append(
			{
				"index": i,
				"cell": [far.x, far.y],
				"shape": str(b.get("shape", "")),
				"risk_score": float(food_profile.get("risk_score", 0.0)),
				"detour_cells": float(food_profile.get("detour_cells", 0.0)),
				"hazard_penalty": float(food_profile.get("hazard_penalty", 0.0)),
				"food_atp": reward_atp,
				"collected": false,
				"interactable": interactable,
				"marker": marker
			}
		)


func _configure_food_branch_caches() -> void:
	if _branch_caches.is_empty():
		return
	var grid = GridWorld.from_data(_nav_grid())
	for cache in _branch_caches:
		var physical_food := _food_test_mode() in [FOOD_TEST_RETURN_LOOP, FOOD_TEST_SCARCITY]
		var raw_cell: Array = cache.get("cell", [])
		if raw_cell.size() >= 2:
			cache["position"] = grid.grid_to_world(Vector2i(int(raw_cell[0]), int(raw_cell[1])))
		cache["physical_food"] = physical_food
		var interactable = cache.get("interactable", null)
		if physical_food and interactable != null:
			var reward_atp := int(cache.get("food_atp", BRANCH_ATP))
			interactable.set("one_shot", false)
			interactable.set("tutorial_label", "TAKE +%d ATP" % reward_atp)
			interactable.set(
				"description",
				"Detour cache: %.1f risk, +%d ATP" % [float(cache.get("risk_score", 0.0)), reward_atp]
			)
		_set_branch_cache_available_visual(cache, not bool(cache.get("collected", false)))


func _branch_food_profile(branch: Dictionary, far: Vector2i) -> Dictionary:
	var neck_raw: Array = branch.get("neck", [far.x, far.y])
	var neck := Vector2i(int(neck_raw[0]), int(neck_raw[1])) if neck_raw.size() >= 2 else far
	var detour_cells := Vector2(far.x - neck.x, far.y - neck.y).length()
	var branch_cells: Array = branch.get("cells", [])
	var branch_cell_set := {}
	for raw_cell in branch_cells:
		if raw_cell is Array and raw_cell.size() >= 2:
			branch_cell_set[Vector2i(int(raw_cell[0]), int(raw_cell[1]))] = true
	var hazard_penalty := 0.0
	for risk_entry in _nav_grid().get("risk_cell_list", []):
		var risk_cell_raw: Array = risk_entry.get("cell", [])
		if risk_cell_raw.size() < 2:
			continue
		var risk_cell := Vector2i(int(risk_cell_raw[0]), int(risk_cell_raw[1]))
		if branch_cell_set.has(risk_cell):
			hazard_penalty += float(risk_entry.get("penalty", 0.0))
	var risk_score := detour_cells * 1.5 + float(branch_cells.size()) * 0.15 + hazard_penalty * 0.2
	var reward_atp := BRANCH_ATP
	if risk_score >= 9.0:
		reward_atp = 4
	elif risk_score >= 6.0:
		reward_atp = 3
	return {
		"risk_score": snappedf(risk_score, 0.1),
		"detour_cells": snappedf(detour_cells, 0.1),
		"hazard_penalty": snappedf(hazard_penalty, 0.1),
		"food_atp": reward_atp,
	}


func _build_guide_food_caches() -> void:
	if _coord_map == null or _food_test_mode() == FOOD_TEST_NEUTRAL:
		return
	for i in range(GUIDE_FOOD_SEGMENTS.size()):
		var segment: Array = GUIDE_FOOD_SEGMENTS[i]
		var start_pos := _node_position(str(segment[0]))
		var end_pos := _node_position(str(segment[1]))
		if start_pos == Vector3.INF or end_pos == Vector3.INF:
			continue
		var flat := start_pos.lerp(end_pos, 0.5)
		var marker_color := Color(0.72, 0.92, 0.46)
		var marker := _add_box(
			self,
			flat + Vector3(0.0, 0.24, 0.0),
			Vector3(0.34, 0.34, 0.34),
			marker_color,
			marker_color.lightened(0.25),
			0.28,
			"GuideFood_%d" % i
		)
		var interactable := _add_inspection_interactable(
			self,
			"GuideFoodZone_%d" % i,
			"A small route morsel (+0.5 ATP)",
			flat + Vector3(0.0, 0.10, 0.0),
			"TAKE MORSEL +0.5",
			"",
			1.25,
			false
		)
		interactable.set("one_shot", false)
		interactable.interacted.connect(Callable(self, "_collect_guide_food").bind(i))
		_add_outline_target(
			self,
			"GuideFoodTarget_%d" % i,
			flat + Vector3(0.0, 0.32, 0.0),
			Vector3(0.72, 0.64, 0.72),
			[marker] as Array[MeshInstance3D],
			"guide_food_%d" % i,
			interactable
		)
		_guide_food_caches.append({
			"index": i,
			"position": flat,
			"food_atp": GUIDE_FOOD_ATP,
			"collected": false,
			"interactable": interactable,
			"marker": marker,
		})


## Each optional spoke terminates in a small, readable service bay instead of a lone reward cube on empty floor.
## The low plinth and paired gauge posts add silhouette without obscuring the route; the label makes the detour's
## purpose legible before the player commits to it. The whole assembly is one flat-authored root, so the existing
## warp pass seats it consistently on the helix.
func _build_branch_service_bay(index: int, flat: Vector3, reward_atp: int) -> void:
	var bay := Node3D.new()
	bay.name = "BranchServiceBay_%d" % index
	bay.position = flat
	add_child(bay)
	var steel := Color(0.12, 0.18, 0.19)
	var signal_color := Color(0.50, 0.78, 0.34).lightened(0.06 * float(reward_atp - BRANCH_ATP))
	_add_box(bay, Vector3(0.0, 0.08, 0.0), Vector3(2.35, 0.14, 1.85), steel, signal_color, 0.14, "ServicePlinth")
	for side in [-0.88, 0.88]:
		_add_box(bay, Vector3(side, 0.62, 0.62), Vector3(0.14, 1.15, 0.14), steel, signal_color, 0.42, "GaugePost")
	_add_box(bay, Vector3(0.0, 1.18, 0.62), Vector3(1.9, 0.12, 0.12), steel, signal_color, 0.48, "GaugeBeam")
	_add_label(
		bay,
		"SIDE FEED %02d  //  +%d ATP" % [index + 1, reward_atp],
		Vector3(0.0, 1.65, 0.62),
		signal_color.lightened(0.22)
	)
	_spatial_fixture_count += 1


func _set_branch_cache_available_visual(cache: Dictionary, available: bool) -> void:
	var marker: MeshInstance3D = cache.get("marker", null)
	if marker != null and is_instance_valid(marker):
		marker.visible = available


func _clear_hydraulic_runtime_refs() -> void:
	_hydraulic_main_water.clear()
	_hydraulic_main_tail.clear()
	_hydraulic_spillway_water.clear()
	_hydraulic_exit_water.clear()
	_hydraulic_first_control = null
	_hydraulic_cistern_control = null
	_hydraulic_diverter_control = null
	_hydraulic_first_target = null
	_hydraulic_cistern_target = null
	_hydraulic_diverter_target = null
	_hydraulic_catch_target = null
	_hydraulic_catch_control = null
	_hydraulic_first_label = null
	_hydraulic_cistern_label = null
	_hydraulic_diverter_label = null
	_hydraulic_exit_label = null
	_hydraulic_first_landmark_meshes.clear()
	_hydraulic_first_landmark_light = null
	_hydraulic_cistern_effect = null
	_hydraulic_bridge_mesh = null
	_hydraulic_bridge_cargo = null
	_hydraulic_spillway_catch = null
	_hydraulic_exit_beacon = null
	_hydraulic_spillway_link = null
	_hydraulic_exit_link = null
	_hydraulic_spillway_food_cache.clear()
	_hydraulic_grid_instance_id = 0


func _make_hydraulic_water_material(variant := 0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WaterShader
	material.set_shader_parameter("water_tex", WaterTexV1 if variant % 2 == 1 else WaterTexV0)

	material.set_shader_parameter("water_alpha", 0.88)
	material.set_shader_parameter("emission_strength", 2.2)
	material.set_shader_parameter("reveal_radius", 6.0)
	material.set_shader_parameter("reveal_min_factor", 0.45)
	material.set_shader_parameter("reveal_softness", 0.7)
	material.set_shader_parameter("reveal_alpha_floor", 0.14)
	material.set_shader_parameter("reveal_emission_floor", 0.2)
	material.set_shader_parameter("reveal_cut_above_player", 1.8)
	material.render_priority = 127
	return material


func _append_hydraulic_water_path(
	points: Array, target: Array[MeshInstance3D], prefix: String, variant_offset := 0
) -> void:
	for path_index in range(points.size() - 1):
		var path_from: Vector3 = points[path_index]
		var path_to: Vector3 = points[path_index + 1]
		var distance := path_from.distance_to(path_to)
		var segment_count := maxi(1, int(ceil(distance / 2.2)))
		for segment_index in range(segment_count):
			var a := path_from.lerp(path_to, float(segment_index) / float(segment_count))
			var b := path_from.lerp(path_to, float(segment_index + 1) / float(segment_count))
			var center := a.lerp(b, 0.5) + Vector3(0.0, 0.16, 0.0)
			var segment := _add_box(
				self,
				center,
				Vector3(1.5, 0.16, a.distance_to(b) * 1.08),
				HYDRAULIC_WATER_COLOR,
				HYDRAULIC_ACTIVE_COLOR,
				1.2,
				"%s_%02d_%02d" % [prefix, path_index, segment_index]
			)
			var delta := b - a
			segment.rotation.y = atan2(delta.x, delta.z)
			segment.rotation.x = -atan2(delta.y, Vector2(delta.x, delta.z).length())
			segment.material_override = _make_hydraulic_water_material(
				variant_offset + path_index + segment_index
			)
			var trough := _add_box(
				self,
				center - Vector3(0.0, 0.18, 0.0),
				Vector3(1.88, 0.18, a.distance_to(b) * 1.1),
				Color(0.045, 0.075, 0.085),
				Color(0.08, 0.28, 0.36),
				0.28,
				"%sTrough_%02d_%02d" % [prefix, path_index, segment_index]
			)
			trough.rotation = segment.rotation
			target.append(segment)


func _orient_hydraulic_span(mesh: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var delta := to - from
	mesh.rotation.y = atan2(delta.x, delta.z)
	mesh.rotation.x = -atan2(delta.y, Vector2(delta.x, delta.z).length())


func _build_hydraulic_control(
	node_name: String,
	description: String,
	label: String,
	position: Vector3,
	color: Color,
	primary_landmark := false
) -> Dictionary:
	var interactable := _add_interactable(
		self,
		node_name,
		description,
		position,
		label,
		"",
		0.0,
		false,
		1.65,
		Interactable.InteractableType.INSPECTION,
		false
	)
	var housing := _add_box(
		self,
		position + Vector3(0.0, 0.62, 0.0),
		Vector3(0.9, 1.24, 0.78),
		color.darkened(0.55),
		color,
		1.25,
		"%sHousing" % node_name
	)
	var handle := _add_box(
		self,
		position + Vector3(0.0, 1.28, 0.0),
		Vector3(0.24, 0.68, 0.24),
		color.lightened(0.12),
		color.lightened(0.22),
		1.5,
		"%sHandle" % node_name
	)
	handle.rotation.z = -0.28
	var meshes: Array[MeshInstance3D] = [housing, handle]
	var landmark_meshes: Array[MeshInstance3D] = []
	var landmark_light: OmniLight3D = null
	if primary_landmark:
		var landmark_root := Node3D.new()
		landmark_root.name = "%sLandmark" % node_name
		landmark_root.position = position
		self.add_child(landmark_root)
		var pad := _add_box(
			landmark_root,
			Vector3(0.0, 0.1, 0.0),
			Vector3(2.45, 0.12, 1.8),
			color.darkened(0.62),
			color,
			1.15,
			"%sLandmarkPad" % node_name
		)
		landmark_meshes.append(pad)
		for side in [-0.92, 0.92]:
			var post := _add_box(
				landmark_root,
				Vector3(side, 1.85, 0.0),
				Vector3(0.2, 3.5, 0.2),
				color.darkened(0.5),
				color,
				1.65,
				"%sLandmarkPost" % node_name
			)
			landmark_meshes.append(post)
		var header := _add_box(
			landmark_root,
			Vector3(0.0, 3.56, 0.0),
			Vector3(2.04, 0.22, 0.22),
			color.darkened(0.45),
			color,
			1.85,
			"%sLandmarkHeader" % node_name
		)
		landmark_meshes.append(header)
		var crown := _add_box(
			landmark_root,
			Vector3(0.0, 3.92, 0.0),
			Vector3(0.58, 0.58, 0.18),
			color.darkened(0.38),
			color.lightened(0.14),
			2.2,
			"%sLandmarkCrown" % node_name
		)
		crown.rotation.z = PI * 0.25
		landmark_meshes.append(crown)
		meshes.append_array(landmark_meshes)
		landmark_light = _add_light(
			landmark_root, Vector3(0.0, 2.5, 0.0), color.lightened(0.12), 1.65, 5.5
		)
	var target := _add_outline_target(
		self,
		"%sTarget" % node_name,
		position + Vector3(0.0, 0.8, 0.0),
		Vector3(1.4, 1.8, 1.35),
		meshes,
		node_name.to_snake_case(),
		interactable
	)
	if target != null and interactable.has_method("set_outline_target"):
		interactable.call("set_outline_target", target)

		interactable.input_ray_pickable = false
	var label_height := 4.55 if primary_landmark else 2.05
	var status_label := _add_label(
		self, label, position + Vector3(0.0, label_height, 0.0), color.lightened(0.28)
	)
	return {
		"interactable": interactable,
		"housing": housing,
		"target": target,
		"label": status_label,
		"landmark_meshes": landmark_meshes,
		"landmark_light": landmark_light,
	}


## Low paired datum lights break the long mandatory run into readable hydraulic bays. They are deliberately below
## character height, so they guide camera rotation and distance judgment without becoming another foreground wall.
func _build_hydraulic_route_datums(points: Array) -> void:
	var steel := Color(0.08, 0.15, 0.18)
	for i in range(points.size() - 1):
		var from_pos: Vector3 = points[i]
		var to_pos: Vector3 = points[i + 1]
		var datum := Node3D.new()
		datum.name = "HydraulicRouteDatum_%02d" % (i + 1)
		datum.position = from_pos.lerp(to_pos, 0.5)
		add_child(datum)
		var signal_color := HYDRAULIC_ACTIVE_COLOR.lerp(HYDRAULIC_READY_COLOR, float(i) / maxf(1.0, float(points.size() - 2)))
		_add_box(datum, Vector3(0.0, 0.06, 0.0), Vector3(0.16, 0.05, 2.45), steel, signal_color, 0.34, "FlowDatumLine")
		for lane_side in [-1.12, 1.12]:
			_add_box(datum, Vector3(0.0, 0.38, lane_side), Vector3(0.18, 0.72, 0.18), steel, signal_color, 0.64, "FlowDatumBollard")
		_spatial_fixture_count += 1


func _build_hydraulic_puzzle() -> void:
	if not _hydraulic_enabled():
		return
	var node_01 := _node_position("node_01")
	var node_02 := _node_position("node_02")
	var node_03 := _node_position("node_03")
	var node_04 := _node_position("node_04")
	var entry_pos := _node_position("entry")
	var exit_pos := _node_position("exit_shelter")
	if Vector3.INF in [entry_pos, node_01, node_02, node_03, node_04, exit_pos]:
		return

	_set_outline_target_enabled(_node_targets.get("entry", null), false)
	_build_hydraulic_route_datums([entry_pos, node_01, node_02, node_03, node_04, exit_pos])

	var spillway_catch_position := node_04 + Vector3(0.0, 0.0, 2.15)

	var pool := _add_box(
		self,
		node_01 + Vector3(0.0, 0.2, 1.35),
		Vector3(3.2, 0.18, 2.1),
		HYDRAULIC_WATER_COLOR,
		HYDRAULIC_ACTIVE_COLOR,
		1.4,
		"HydraulicCisternPool"
	)
	pool.material_override = _make_hydraulic_water_material(0)
	_append_hydraulic_water_path(
		[node_01, node_02, node_03], _hydraulic_main_water, "HydraulicMainWater", 1
	)
	_append_hydraulic_water_path([node_03, node_04], _hydraulic_main_tail, "HydraulicMainTail", 7)
	var spillway_mid := node_03.lerp(node_04, 0.5) + Vector3(0.0, 0.0, 4.5)
	_append_hydraulic_water_path(
		[node_03, spillway_mid, spillway_catch_position],
		_hydraulic_spillway_water,
		"HydraulicBorrowedCurrent",
		11
	)
	_append_hydraulic_water_path(
		[node_04, exit_pos], _hydraulic_exit_water, "HydraulicExitWater", 17
	)

	var bridge_from := node_02.lerp(node_03, 0.39)
	var bridge_to := node_02.lerp(node_03, 0.61)
	var bridge_center := bridge_from.lerp(bridge_to, 0.5)
	var bridge_length := bridge_from.distance_to(bridge_to) * 1.06
	var void_mesh := _add_box(
		self,
		bridge_center + Vector3(0.0, 0.15, 0.0),
		Vector3(3.25, 0.2, bridge_length),
		Color(0.008, 0.012, 0.018),
		Color(0.08, 0.22, 0.34),
		0.45,
		"CisternBridgeGap"
	)
	_orient_hydraulic_span(void_mesh, bridge_from, bridge_to)
	_hydraulic_bridge_mesh = _add_box(
		self,
		bridge_center + Vector3(0.0, 0.38, 0.0),
		Vector3(2.85, 0.24, bridge_length),
		Color(0.22, 0.19, 0.13),
		HYDRAULIC_READY_COLOR,
		0.72,
		"CisternBridgeInstalled"
	)
	_orient_hydraulic_span(_hydraulic_bridge_mesh, bridge_from, bridge_to)
	for rail_side in [-1.2, 1.2]:
		var rail := _add_box(
			_hydraulic_bridge_mesh,
			Vector3(rail_side, 0.42, 0.0),
			Vector3(0.12, 0.62, bridge_length),
			Color(0.14, 0.16, 0.16),
			HYDRAULIC_READY_COLOR,
			0.65,
			"CisternBridgeRail"
		)
		rail.rotation = Vector3.ZERO

	var first_control_position := entry_pos.lerp(node_01, 0.5) + Vector3(0.0, 0.05, -0.82)
	var first_data := _build_hydraulic_control(
		"FirstSluiceControl",
		"Open the first sluice and send water toward the cistern",
		"FIRST SLUICE",
		first_control_position,
		HYDRAULIC_CONTROL_COLOR,
		true
	)
	_hydraulic_first_control = first_data["interactable"]
	_hydraulic_first_target = first_data["target"]
	_hydraulic_first_label = first_data["label"]
	_hydraulic_first_landmark_meshes.assign(first_data.get("landmark_meshes", []))
	_hydraulic_first_landmark_light = first_data.get("landmark_light", null)
	_hydraulic_first_control.interacted.connect(Callable(self, "open_first_sluice"))

	var cistern_data := _build_hydraulic_control(
		"CisternReleaseControl",
		"Release the bridge cargo into the current",
		"CISTERN RELEASE",
		node_02 + Vector3(1.75, 0.05, -1.35),
		HYDRAULIC_ACTIVE_COLOR
	)
	_hydraulic_cistern_control = cistern_data["interactable"]
	_hydraulic_cistern_target = cistern_data["target"]
	_hydraulic_cistern_label = cistern_data["label"]
	_hydraulic_cistern_control.interacted.connect(Callable(self, "release_cistern_bridge"))
	_hydraulic_cistern_effect = _add_box(
		self,
		node_02 + Vector3(-1.45, 1.45, 0.1),
		Vector3(1.6, 2.8, 1.6),
		Color(0.08, 0.2, 0.26),
		HYDRAULIC_ACTIVE_COLOR,
		0.85,
		"CisternTower"
	)
	_hydraulic_bridge_cargo = _add_box(
		self,
		node_02 + Vector3(1.5, 0.58, 0.15),
		Vector3(1.5, 1.0, 1.2),
		Color(0.24, 0.18, 0.1),
		HYDRAULIC_CONTROL_COLOR,
		0.9,
		"BridgeCargo"
	)
	_add_label(
		self,
		"BRIDGE CARGO",
		node_02 + Vector3(1.5, 1.62, 0.15),
		HYDRAULIC_CONTROL_COLOR.lightened(0.25)
	)

	var diverter_position := node_03.lerp(node_04, 0.4) + Vector3.UP * 0.05
	var diverter_data := _build_hydraulic_control(
		"BorrowedCurrentControl",
		"Divert the main current through the food spillway",
		"BORROWED CURRENT",
		diverter_position,
		Color(0.68, 0.42, 1.0)
	)
	_hydraulic_diverter_control = diverter_data["interactable"]
	_hydraulic_diverter_target = diverter_data["target"]
	_hydraulic_diverter_label = diverter_data["label"]
	_hydraulic_diverter_control.interacted.connect(Callable(self, "toggle_borrowed_current"))
	_hydraulic_spillway_catch = _add_box(
		self,
		spillway_catch_position + Vector3(0.0, 0.42, 0.0),
		Vector3(1.9, 0.66, 0.58),
		Color(0.24, 0.19, 0.08),
		HYDRAULIC_CONTROL_COLOR,
		0.55,
		"FoodSpillwayCatch"
	)
	_add_label(
		self,
		"FOOD SPILLWAY // CATCH",
		spillway_catch_position + Vector3(0.0, 1.38, 0.0),
		HYDRAULIC_CONTROL_COLOR.lightened(0.25)
	)

	var node_04_target: Node = _node_targets.get("node_04", null)
	var node_04_interactable: Node = null
	if node_04_target != null and node_04_target.has_method("get_interaction_delegate"):
		node_04_interactable = node_04_target.call("get_interaction_delegate")
	if node_04_interactable != null:
		_hydraulic_catch_control = node_04_interactable as Area3D
		if (
			_hydraulic_catch_control != null
			and not _hydraulic_catch_control.body_entered.is_connected(
				Callable(self, "_on_hydraulic_catch_body_entered")
			)
		):
			_hydraulic_catch_control.body_entered.connect(
				Callable(self, "_on_hydraulic_catch_body_entered")
			)
		_set_outline_target_enabled(node_04_target, false)
		node_04_interactable.position = spillway_catch_position
		var catch_label := "CATCH CURRENT"
		var catch_description := "Receive the borrowed current at the food-spillway catch"
		if _food_test_mode() != FOOD_TEST_NEUTRAL:
			catch_label = "CATCH LYSATE"
			catch_description = "Catch the lysate carried by the borrowed current"
		_set_interactable_copy(node_04_interactable, catch_label, catch_description)
		_hydraulic_catch_target = _add_outline_target(
			self,
			"FoodSpillwayCatchTarget",
			spillway_catch_position + Vector3(0.0, 2.05, 0.0),
			Vector3(2.15, 3.9, 1.25),
			[_hydraulic_spillway_catch],
			"node_04",
			node_04_interactable
		)
		if _hydraulic_catch_target != null:
			node_04_interactable.call("set_outline_target", _hydraulic_catch_target)
			_node_targets["node_04"] = _hydraulic_catch_target
		if _food_test_mode() != FOOD_TEST_NEUTRAL:
			node_04_interactable.set("one_shot", false)
			var food_marker := _add_box(
				self,
				spillway_catch_position + Vector3(0.0, 0.92, 0.0),
				Vector3(0.48, 0.48, 0.48),
				Color(0.58, 0.84, 0.42),
				Color(0.78, 1.0, 0.56),
				0.8,
				"HydraulicSpillwayFood"
			)
			_hydraulic_spillway_food_cache = {
				"collected": false,
				"interactable": node_04_interactable,
				"marker": food_marker,
				"position": spillway_catch_position,
			}
	var exit_beacon_route_position := node_04.lerp(exit_pos, 0.62)
	_hydraulic_exit_beacon = _add_box(
		self,
		exit_beacon_route_position + Vector3(0.0, 1.15, 0.0),
		Vector3(0.48, 2.3, 0.48),
		Color(0.24, 0.1, 0.08),
		HYDRAULIC_CONTROL_COLOR,
		0.55,
		"HydraulicExitBeacon"
	)
	_hydraulic_exit_label = _add_label(
		self,
		"RESTORE MAIN CURRENT",
		exit_beacon_route_position + Vector3(0.0, 2.65, 0.0),
		HYDRAULIC_CONTROL_COLOR.lightened(0.2)
	)

	var old_exit_target: Node = _node_targets.get("exit_shelter", null)
	var exit_interactable: Node = null
	if old_exit_target != null and old_exit_target.has_method("get_interaction_delegate"):
		exit_interactable = old_exit_target.call("get_interaction_delegate")
	if exit_interactable != null:
		_set_outline_target_enabled(old_exit_target, false)
		exit_interactable.position = exit_beacon_route_position
		_set_interactable_copy(
			exit_interactable,
			"SHELTER LOCKED",
			"Restore the main current before entering the shelter"
		)
		var exit_beacon_target := _add_outline_target(
			self,
			"HydraulicExitBeaconTarget",
			exit_beacon_route_position + Vector3(0.0, 1.25, 0.0),
			Vector3(1.5, 2.4, 1.5),
			[_hydraulic_exit_beacon],
			"exit_shelter",
			exit_interactable
		)
		if exit_beacon_target != null:
			exit_interactable.call("set_outline_target", exit_beacon_target)
			_node_targets["exit_shelter"] = exit_beacon_target
	_apply_hydraulic_visual_state()


func _wire_hydraulic_feedback() -> void:
	if not _hydraulic_enabled():
		return
	if _hydraulic_first_control != null and _hydraulic_cistern_effect != null:
		_add_causal_feedback_link(
			_hydraulic_first_control,
			_hydraulic_cistern_effect,
			HYDRAULIC_ACTIVE_COLOR,
			{
				"label": "SENDS WATER TO THE CISTERN",
				"arc_height": 2.5,
				"name": "FirstSluiceCisternLink",
			}
		)
	if _hydraulic_cistern_control != null and _hydraulic_bridge_mesh != null:
		_add_causal_feedback_link(
			_hydraulic_cistern_control,
			_hydraulic_bridge_mesh,
			HYDRAULIC_READY_COLOR,
			{
				"label": "CURRENT CARRIES THE BRIDGE",
				"arc_height": 2.8,
				"name": "CisternBridgeLink",
			}
		)
	if _hydraulic_diverter_control != null and _hydraulic_spillway_catch != null:
		_hydraulic_spillway_link = _add_causal_feedback_link(
			_hydraulic_diverter_control,
			_hydraulic_spillway_catch,
			Color(0.68, 0.42, 1.0),
			{
				"label": "DIVERTS THE ONE CURRENT TO SPILLWAY",
				"arc_height": 3.0,
				"name": "BorrowedCurrentSpillwayLink",
			}
		)
	if _hydraulic_diverter_control != null and _hydraulic_exit_beacon != null:
		_hydraulic_exit_link = _add_causal_feedback_link(
			_hydraulic_diverter_control,
			_hydraulic_exit_beacon,
			HYDRAULIC_READY_COLOR,
			{
				"label": "THE SAME CURRENT FEEDS THE SHELTER",
				"arc_height": 3.2,
				"name": "BorrowedCurrentExitLink",
			}
		)
	# The initial visual pass ran before the links existed. Refresh once more so the
	# relationship copy starts in the same truthful state as the water and controls.
	_apply_hydraulic_visual_state()


func _flash_hydraulic_link(link: Node3D, duration := 1.25, strength := 1.0) -> void:
	if link != null and is_instance_valid(link):
		link.call("flash", duration, strength)


func _set_hydraulic_link_label(link: Node3D, text: String) -> void:
	if link != null and is_instance_valid(link) and link.has_method("set_relationship_label"):
		link.call("set_relationship_label", text)


func _set_hydraulic_status_label(label: Label3D, text: String, color: Color) -> void:
	if label == null or not is_instance_valid(label):
		return
	label.text = text
	label.modulate = color


func _set_interactable_copy(interactable: Node, label: String, description: String) -> void:
	if interactable == null or not is_instance_valid(interactable):
		return
	interactable.set("tutorial_label", label)
	interactable.set("description", description)
	var expanded_label := InputLabels.expand(label)

	for child in interactable.get_children():
		if child is Label3D:
			(child as Label3D).text = expanded_label
			break


func _set_outline_target_enabled(target: Node, enabled: bool) -> void:
	if target == null or not is_instance_valid(target):
		return
	target.set("hover_enabled", enabled)
	target.set("collision_layer", 4 if enabled else 0)
	target.set("input_ray_pickable", enabled)
	if not enabled:
		if target.has_method("set_hover_feedback"):
			target.call("set_hover_feedback", false)
		if target.has_method("set_highlight"):
			target.call("set_highlight", false)


func _set_hydraulic_control_state(
	control: Area3D, target: StaticBody3D, enabled: bool, label: String, description: String
) -> void:
	if control == null or not is_instance_valid(control):
		return
	if control.has_method("set_interaction_enabled"):
		control.call("set_interaction_enabled", enabled)

	control.input_ray_pickable = false
	_set_outline_target_enabled(target, enabled)
	# This object sits inside the same right-click grammar as ground movement. Keep the
	# world-state copy concise, but name the live binding on the actionable hover prompt
	# so the player can reach the systems question without first guessing the UI verb.
	_set_interactable_copy(control, "{command} // %s" % label, description)
	if control.has_method("show_tutorial_label"):
		control.call("show_tutorial_label")


func _on_hydraulic_catch_body_entered(body: Node3D) -> void:
	# The catch is a destination, not a lever. On the layered helix, foreground
	# deck collision can legitimately turn a click on its visible receiver into a
	# ground-move command. Arrival therefore completes the active delivery too.
	# The phase gate prevents ordinary traversal from consuming the beat early.
	if not (body is CharacterBody3D):
		return
	if not (_borrowed_current_diverted and not _borrowed_current_delivery_latched):
		return
	activate_generated_node("node_04")


func _set_hydraulic_next_highlight(next_target: Node) -> void:
	var targets: Array = [
		_hydraulic_first_target,
		_hydraulic_cistern_target,
		_hydraulic_diverter_target,
		_hydraulic_catch_target,
		_node_targets.get("exit_shelter", null),
	]
	for target_v in targets:
		var target := target_v as Node
		if (
			target != null
			and is_instance_valid(target)
			and target.has_method("set_external_highlight")
		):
			target.call(
				"set_external_highlight", HYDRAULIC_NEXT_HIGHLIGHT_REASON, target == next_target
			)


func _apply_hydraulic_visual_state() -> void:
	if not _hydraulic_enabled():
		return
	for water in _hydraulic_main_water:
		if water != null and is_instance_valid(water):
			water.visible = _first_sluice_open
	for water in _hydraulic_main_tail:
		if water != null and is_instance_valid(water):
			water.visible = _first_sluice_open and not _borrowed_current_diverted
	for water in _hydraulic_spillway_water:
		if water != null and is_instance_valid(water):
			water.visible = _borrowed_current_diverted
	for water in _hydraulic_exit_water:
		if water != null and is_instance_valid(water):
			water.visible = _main_current_restored
	if _hydraulic_bridge_mesh != null and is_instance_valid(_hydraulic_bridge_mesh):
		_hydraulic_bridge_mesh.visible = _cistern_bridge_installed
	if _hydraulic_bridge_cargo != null and is_instance_valid(_hydraulic_bridge_cargo):
		_hydraulic_bridge_cargo.visible = not _cistern_bridge_installed
	if _hydraulic_spillway_catch != null and is_instance_valid(_hydraulic_spillway_catch):
		var catch_color := (
			HYDRAULIC_READY_COLOR if _borrowed_current_delivery_latched else HYDRAULIC_CONTROL_COLOR
		)
		_hydraulic_spillway_catch.material_override = _make_material(
			catch_color.darkened(0.58),
			catch_color,
			1.15 if _borrowed_current_delivery_latched else 0.55
		)
	if _hydraulic_exit_beacon != null and is_instance_valid(_hydraulic_exit_beacon):
		var exit_ready := bool(_hydraulic_state().get("hydraulic_exit_unlocked", false))
		var exit_color := HYDRAULIC_READY_COLOR if exit_ready else HYDRAULIC_CONTROL_COLOR
		_hydraulic_exit_beacon.material_override = _make_material(
			exit_color.darkened(0.6), exit_color, 1.35 if exit_ready else 0.5
		)
		var exit_target: Node = _node_targets.get("exit_shelter", null)
		var exit_interactable: Node = null
		if exit_target != null and exit_target.has_method("get_interaction_delegate"):
			exit_interactable = exit_target.call("get_interaction_delegate")
		if exit_interactable != null:
			_set_interactable_copy(
				exit_interactable,
				"ENTER SHELTER" if exit_ready else "SHELTER LOCKED",
				(
					"Follow the restored main current into the shelter"
					if exit_ready
					else "Restore the main current before entering the shelter"
				)
			)
		_set_hydraulic_status_label(
			_hydraulic_exit_label,
			"SHELTER ROUTE OPEN" if exit_ready else "RESTORE MAIN CURRENT",
			exit_color.lightened(0.2)
		)
	var first_landmark_color := (
		HYDRAULIC_READY_COLOR if _first_sluice_open else HYDRAULIC_CONTROL_COLOR
	)
	for landmark in _hydraulic_first_landmark_meshes:
		if landmark != null and is_instance_valid(landmark):
			landmark.material_override = _make_material(
				first_landmark_color.darkened(0.52),
				first_landmark_color,
				1.05 if _first_sluice_open else 1.85
			)
	if (
		_hydraulic_first_landmark_light != null
		and is_instance_valid(_hydraulic_first_landmark_light)
	):
		_hydraulic_first_landmark_light.light_color = first_landmark_color.lightened(0.12)
		_hydraulic_first_landmark_light.light_energy = 0.8 if _first_sluice_open else 1.65

	_set_hydraulic_control_state(
		_hydraulic_first_control,
		_hydraulic_first_target,
		not _first_sluice_open,
		"FLOW OPEN" if _first_sluice_open else "OPEN FIRST SLUICE",
		(
			"The first sluice is open"
			if _first_sluice_open
			else "Open the first sluice and send water toward the cistern"
		)
	)
	_set_hydraulic_status_label(
		_hydraulic_first_label,
		"FLOW OPEN" if _first_sluice_open else "FIRST SLUICE",
		HYDRAULIC_READY_COLOR if _first_sluice_open else HYDRAULIC_CONTROL_COLOR.lightened(0.28)
	)
	_set_hydraulic_control_state(
		_hydraulic_cistern_control,
		_hydraulic_cistern_target,
		_first_sluice_open and not _cistern_bridge_installed,
		"BRIDGE INSTALLED" if _cistern_bridge_installed else "RELEASE BRIDGE",
		(
			"The cistern bridge is installed"
			if _cistern_bridge_installed
			else "Release the bridge cargo into the current"
		)
	)
	var cistern_status := "CISTERN LOCKED"
	var cistern_status_color := HYDRAULIC_ACTIVE_COLOR.darkened(0.58)
	if _cistern_bridge_installed:
		cistern_status = "BRIDGE INSTALLED"
		cistern_status_color = HYDRAULIC_READY_COLOR
	elif _first_sluice_open:
		cistern_status = "CISTERN RELEASE"
		cistern_status_color = HYDRAULIC_ACTIVE_COLOR.lightened(0.28)
	_set_hydraulic_status_label(_hydraulic_cistern_label, cistern_status, cistern_status_color)
	var diverter_label := "DIVERT CURRENT"
	var diverter_description := "Divert the main current through the food spillway"
	var diverter_status := "MAIN FED // SPILLWAY DRY"
	var spillway_relation := "DIVERTS THE ONE CURRENT TO SPILLWAY"
	var exit_relation := "THE SAME CURRENT FEEDS THE SHELTER"
	if _borrowed_current_diverted and not _borrowed_current_delivery_latched:
		diverter_label = "FLOWING TO SPILLWAY"
		diverter_description = "Let the borrowed current reach the food-spillway catch"
		diverter_status = "SPILLWAY FED // MAIN STARVED"
		spillway_relation = "BORROWED FLOW FEEDS SPILLWAY"
		exit_relation = "DIVERSION STARVES THE SHELTER"
	elif _borrowed_current_delivery_latched and not _main_current_restored:
		diverter_label = "RESTORE CURRENT"
		diverter_description = "Return the borrowed current to the exit channel"
		diverter_status = "SPILLWAY CAUGHT // MAIN STARVED"
		spillway_relation = "DELIVERY CAUGHT; FLOW STILL BORROWED"
		exit_relation = "RETURN FLOW TO FEED THE SHELTER"
	elif _main_current_restored:
		diverter_label = "MAIN FLOW RESTORED"
		diverter_description = "The main current now reaches the exit"
		diverter_status = "MAIN FED // SPILLWAY DRY"
		spillway_relation = "SPILLWAY RELEASED"
		exit_relation = "MAIN CURRENT FEEDS THE SHELTER"
	_set_hydraulic_control_state(
		_hydraulic_diverter_control,
		_hydraulic_diverter_target,
		_cistern_bridge_installed and not _main_current_restored,
		diverter_label,
		diverter_description
	)

	var catch_step_active := _borrowed_current_diverted and not _borrowed_current_delivery_latched
	_set_outline_target_enabled(_hydraulic_catch_target, catch_step_active)

	if _hydraulic_catch_control != null and is_instance_valid(_hydraulic_catch_control):
		_hydraulic_catch_control.input_ray_pickable = catch_step_active
	if catch_step_active:
		_set_outline_target_enabled(_hydraulic_diverter_target, false)
	if not _cistern_bridge_installed:
		diverter_status = "CURRENT LOCKED"
	var diverter_status_color := (
		HYDRAULIC_READY_COLOR if _main_current_restored else Color(0.82, 0.64, 1.0)
	)
	if not _cistern_bridge_installed:
		diverter_status_color = Color(0.34, 0.24, 0.46)
	_set_hydraulic_status_label(_hydraulic_diverter_label, diverter_status, diverter_status_color)
	_set_hydraulic_link_label(_hydraulic_spillway_link, spillway_relation)
	_set_hydraulic_link_label(_hydraulic_exit_link, exit_relation)

	var next_target: Node = null
	if not _shelter_reached:
		match _hydraulic_phase:
			"first_sluice":
				next_target = _hydraulic_first_target
			"cistern_bridge":
				next_target = _hydraulic_cistern_target
			"borrowed_current":
				next_target = _hydraulic_diverter_target
			# The first two beats teach the answer-highlight grammar. Catching and
			# restoring are the transfer test: visible flow, state labels, and causal
			# links remain, but the game stops drawing a persistent answer marker.
			"food_spillway", "restore_current":
				next_target = null
			"exit_ready":
				next_target = _node_targets.get("exit_shelter", null)
	_set_hydraulic_next_highlight(next_target)


func _reset_hydraulic_state() -> void:
	_first_sluice_open = false
	_cistern_bridge_installed = false
	_borrowed_current_diverted = false
	_borrowed_current_delivery_latched = false
	_main_current_restored = false
	_hydraulic_phase = "first_sluice" if _hydraulic_enabled() else "disabled"
	_hydraulic_grid_instance_id = 0
	_apply_hydraulic_visual_state()
	_sync_hydraulic_bridge_blocker()


func _hydraulic_bridge_blocker_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not _hydraulic_enabled():
		return cells
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return cells
	var node_02 := _node_position("node_02")
	var node_03 := _node_position("node_03")
	if node_02 == Vector3.INF or node_03 == Vector3.INF:
		return cells
	var bridge_center := node_02.lerp(node_03, 0.5)
	var direction := Vector2(node_03.x - node_02.x, node_03.z - node_02.z).normalized()
	var lateral := Vector2(-direction.y, direction.x)
	for offset in [-1.25, -0.62, 0.0, 0.62, 1.25]:
		var sample := bridge_center + Vector3(lateral.x * offset, 0.0, lateral.y * offset)
		var cell: Vector2i = gs.grid.world_to_grid(sample)
		if not cells.has(cell):
			cells.append(cell)
	return cells


func _set_hydraulic_bridge_blocked(blocked: bool) -> bool:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return false
	for cell in _hydraulic_bridge_blocker_cells():
		if blocked:
			gs.grid.add_dynamic_blocker(cell, HYDRAULIC_BLOCKER_TAG)
		elif str(gs.grid.dynamic_blockers.get(cell, "")) == HYDRAULIC_BLOCKER_TAG:
			gs.grid.remove_dynamic_blocker(cell)
	_hydraulic_grid_instance_id = gs.grid.get_instance_id()
	return true


func _sync_hydraulic_bridge_blocker() -> void:
	if not _hydraulic_enabled():
		return
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	var grid_id := int(gs.grid.get_instance_id())
	if grid_id != _hydraulic_grid_instance_id:
		_set_hydraulic_bridge_blocked(not _cistern_bridge_installed)


func _hydraulic_focus(target: Node3D, pause_gameplay := true, duration := 1.35) -> void:
	if target == null or not is_instance_valid(target):
		return
	_request_preview_focus(
		target,
		duration,
		pause_gameplay,
		{
			"reason": "hydraulic_consequence",
			"hold": 0.35,
			"offscreen_only": false,
		}
	)


func _introduce_first_hydraulic_step() -> void:
	if (
		not _hydraulic_enabled()
		or _first_sluice_open
		or _hydraulic_first_control == null
		or not is_instance_valid(_hydraulic_first_control)
	):
		return

	var focus_target: Node3D = _hydraulic_first_control
	if (
		_hydraulic_first_landmark_light != null
		and is_instance_valid(_hydraulic_first_landmark_light)
	):
		focus_target = _hydraulic_first_landmark_light
	_hydraulic_focus(focus_target, true, 2.2)


func open_first_sluice() -> bool:
	if not _hydraulic_enabled() or _first_sluice_open:
		return false
	_first_sluice_open = true
	_hydraulic_phase = "cistern_bridge"
	_last_outcome = "hydraulic:first_sluice_open"
	_apply_hydraulic_visual_state()
	_flash_causal_feedback(_hydraulic_first_control, 1.7, 1.35)
	_hydraulic_focus(_hydraulic_cistern_effect)
	_request_preview_shake(0.08, 7.5)
	_set_preview_step("generated_first_sluice_open")
	_show_note("FIRST SLUICE // Water now reaches the cistern release.", 2.8)
	return true


func release_cistern_bridge() -> bool:
	if not _hydraulic_enabled() or _cistern_bridge_installed:
		return false
	if not _first_sluice_open:
		_hydraulic_focus(_hydraulic_first_control, false)
		_show_note("The cistern is dry. Open the First Sluice first.", 2.2)
		return false
	_cistern_bridge_installed = true
	_hydraulic_phase = "borrowed_current"
	_last_outcome = "hydraulic:cistern_bridge_installed"
	_set_hydraulic_bridge_blocked(false)
	_apply_hydraulic_visual_state()
	_flash_causal_feedback(_hydraulic_cistern_control, 1.8, 1.45)
	_hydraulic_focus(_hydraulic_bridge_mesh)
	_request_preview_shake(0.15, 6.0)
	_set_preview_step("generated_cistern_bridge_installed")
	_show_note("CISTERN BRIDGE // The current carried the bridge into the gap.", 3.0)
	return true


func toggle_borrowed_current() -> bool:
	if not _hydraulic_enabled() or _main_current_restored:
		return false
	if not _cistern_bridge_installed:
		_hydraulic_focus(_hydraulic_bridge_cargo, false)
		_show_note("The bridge cargo has not crossed the cistern yet.", 2.2)
		return false
	if not _borrowed_current_diverted:
		_borrowed_current_diverted = true
		_hydraulic_phase = "food_spillway"
		_last_outcome = "hydraulic:borrowed_current_diverted"
		_apply_hydraulic_visual_state()
		_flash_hydraulic_link(_hydraulic_spillway_link, 1.8, 1.45)
		_flash_hydraulic_link(_hydraulic_exit_link, 1.8, 1.35)

		_hydraulic_focus(_hydraulic_spillway_catch, false, 4.0)
		_request_preview_shake(0.1, 7.0)
		_set_preview_step("generated_borrowed_current_diverted")
		_show_note("BORROWED CURRENT // Spillway fed. Shelter starved.", 3.0)
		return true
	if not _borrowed_current_delivery_latched:
		_flash_hydraulic_link(_hydraulic_spillway_link, 1.2, 1.0)
		_hydraulic_focus(_hydraulic_spillway_catch, false)
		_show_note("The spillway catch has not received the current yet.", 2.2)
		return false
	_borrowed_current_diverted = false
	_main_current_restored = true
	_hydraulic_phase = "exit_ready"
	_last_outcome = "hydraulic:main_current_restored"
	_apply_hydraulic_visual_state()
	_flash_hydraulic_link(_hydraulic_exit_link, 1.9, 1.5)
	_flash_hydraulic_link(_hydraulic_spillway_link, 1.6, 1.25)

	_hydraulic_focus(_hydraulic_exit_beacon, false, 4.0)
	_request_preview_shake(0.12, 6.5)
	_set_preview_step("generated_main_current_restored")
	_show_note("MAIN CURRENT RESTORED // The shelter route is open.", 3.0)
	return true


func _latch_borrowed_current_delivery() -> bool:
	if (
		not _hydraulic_enabled()
		or not _borrowed_current_diverted
		or _borrowed_current_delivery_latched
	):
		return false
	_borrowed_current_delivery_latched = true
	_hydraulic_phase = "restore_current"
	_last_outcome = "hydraulic:spillway_delivery_latched"
	_apply_hydraulic_visual_state()
	_flash_hydraulic_link(_hydraulic_exit_link, 1.6, 1.35)
	_flash_hydraulic_link(_hydraulic_spillway_link, 1.6, 1.35)

	# Show the still-starved downstream goal, not the answer control. The player
	# must use the finite-current model and changed relationship copy to infer the return.
	_hydraulic_focus(_hydraulic_exit_beacon, false, 4.0)
	_request_preview_shake(0.09, 7.0)
	_set_preview_step("generated_spillway_delivery_latched")
	_show_note("SPILLWAY CAUGHT // The shelter channel is still dry.", 3.2)
	return true


func _hydraulic_progress_ready(node_id: String) -> bool:
	if not _hydraulic_enabled():
		return true
	match node_id:
		"node_02":
			if not _first_sluice_open:
				return _block_hydraulic_progress(
					"Open the First Sluice before advancing the cistern.", _hydraulic_first_control
				)
		"node_03":
			if not _cistern_bridge_installed:
				return _block_hydraulic_progress(
					"Release the Cistern Bridge before crossing the gap.",
					_hydraulic_cistern_control
				)
		"node_04":
			if not (_borrowed_current_diverted or _borrowed_current_delivery_latched):
				return _block_hydraulic_progress(
					"Borrow the current before entering the food spillway.",
					_hydraulic_diverter_control,
					_hydraulic_spillway_link
				)
		"exit_shelter":
			if not bool(_hydraulic_state().get("hydraulic_exit_unlocked", false)):
				return _block_hydraulic_progress(
					"Restore the main current before leaving for the shelter.",
					_hydraulic_diverter_control,
					_hydraulic_exit_link
				)
	return true


func _block_hydraulic_progress(
	message: String, focus_target: Node3D, feedback_link: Node3D = null
) -> bool:
	_route_phase = "blocked"
	_last_outcome = "blocked:hydraulic:%s" % _hydraulic_phase
	_hydraulic_focus(focus_target, false)
	if feedback_link != null:
		_flash_hydraulic_link(feedback_link, 1.3, 1.15)
	elif focus_target != null:
		_flash_causal_feedback(focus_target, 1.3, 1.15)
	_show_note(message, 2.5)
	return false


func _headless_complete_hydraulic_puzzle() -> void:
	if not _hydraulic_enabled() or bool(_hydraulic_state().get("hydraulic_exit_unlocked", false)):
		return
	open_first_sluice()
	release_cistern_bridge()
	toggle_borrowed_current()
	_latch_borrowed_current_delivery()
	toggle_borrowed_current()


## The cell in a branch furthest from its neck (the back of the room) — where the reward sits, so the player has
## to walk the whole spoke to claim it.
# The cache trio (marker, interactable, outline target) is authored flat here; the _build_chunk warp pass
# re-seats all of them onto the helix together (same path as the node dressing).
func _branch_far_cell(cells: Array, neck: Array) -> Vector2i:
	var nx := int((neck as Array)[0]) if neck.size() >= 2 else 0
	var nz := int((neck as Array)[1]) if neck.size() >= 2 else 0
	var best := Vector2i(2147483647, 0)
	var best_d := -1.0
	for c in cells:
		var v := Vector2i(int((c as Array)[0]), int((c as Array)[1]))
		var d := Vector2(v.x - nx, v.y - nz).length()
		if d > best_d:
			best_d = d
			best = v
	return best


func _collect_branch_reward(index: int) -> void:
	for cache in _branch_caches:
		if int(cache.get("index", -1)) != index or bool(cache.get("collected", false)):
			continue
		if bool(cache.get("physical_food", false)):
			_collect_physical_branch_food(cache, index)
		else:
			_collect_branch_reward_legacy(index)
		return


func _collect_physical_branch_food(cache: Dictionary, index: int) -> void:
	var reward_atp := float(cache.get("food_atp", BRANCH_ATP))
	var pickup := _try_collect_physical_lysate(
		cache,
		{
			"display_name": "Return-loop Lysate",
			"display_names_by_character":
			{
				"aster": "Lysate",
				"peris": "Lysate",
				"endo": "Starch",
			},
			"visual_color": Color(0.66, 0.82, 0.4),
			"atp_restore": reward_atp,
			"food_test": _food_test_mode(),
			"branch_cache_index": index,
		}
	)
	if pickup.is_empty():
		return
	var recipient := str(pickup.get("recipient", ""))
	_last_outcome = "physical_food:%s:%d" % [recipient, index]
	_show_message(
		(
			"%s now carries lysate (+%s ATP when consumed). Their portrait shows the carrier."
			% [recipient.capitalize(), _atp_amount_text(reward_atp)]
		),
		2.8
	)


func _collect_guide_food(index: int) -> void:
	for cache in _guide_food_caches:
		if int(cache.get("index", -1)) != index or bool(cache.get("collected", false)):
			continue
		var reward_atp := float(cache.get("food_atp", GUIDE_FOOD_ATP))
		var pickup := _try_collect_physical_lysate(
			cache,
			{
				"display_name": "Route Morsel",
				"display_names_by_character": {
					"aster": "Morsel",
					"peris": "Morsel",
					"endo": "Starch morsel",
				},
				"visual_color": Color(0.72, 0.92, 0.46),
				"atp_restore": reward_atp,
				"food_test": _food_test_mode(),
				"guide_food_index": index,
			}
		)
		if pickup.is_empty():
			return
		var recipient := str(pickup.get("recipient", ""))
		_last_outcome = "physical_food:guide:%s:%d" % [recipient, index]
		_show_message(
			"%s pocketed a route morsel (+%s ATP)." % [
				recipient.capitalize(), _atp_amount_text(reward_atp)
			],
			2.0
		)
		return


func _atp_amount_text(value: float) -> String:
	return "%d" % int(value) if is_equal_approx(value, roundf(value)) else "%.1f" % value


func _try_collect_physical_lysate(cache: Dictionary, properties: Dictionary) -> Dictionary:
	if cache.is_empty() or bool(cache.get("collected", false)):
		return {}
	var interactable = cache.get("interactable", null)
	var recipient := ""
	if interactable != null and "active_character" in interactable:
		recipient = str(interactable.get("active_character"))
	if recipient == "":
		recipient = _get_active_character()
	if recipient == "" and not _active_party.is_empty():
		recipient = str(_active_party[0])
	if recipient == "":
		_show_message("No character is close enough to service the lysate cache.", 1.3)
		return {}
	var gs = _get_game_state()
	if gs != null and gs.has_method("is_endocytosing") and bool(gs.call("is_endocytosing", recipient)):
		_show_message("Finish consuming the current item before taking the lysate.", 1.3)
		return {}
	if gs != null and gs.has_method("has_free_hand") and not bool(gs.call("has_free_hand", recipient)):
		_show_message("The servicing character needs a free hand for the lysate.", 1.3)
		return {}

	# Cache visuals may be warped into helix/world space while GameState inventory
	# positions remain in the flat gameplay coordinate system. Spawn the claimed
	# item at its recipient so pickup range is evaluated in one coordinate space;
	# all ordinary inventory checks still run through GameState.pick_up_item().
	var spawn_position := _get_character_position(recipient)
	var item_id := _spawn_item("lysate", spawn_position, properties)
	if item_id == "":
		_show_message("The lysate cache did not open. Try again.", 1.2)
		return {}

	if not _pick_up_item(recipient, item_id):
		_remove_item(item_id)
		_show_message("The lysate could not be transferred. Try servicing the cache again.", 1.3)
		return {}
	cache["collected"] = true
	_set_branch_cache_available_visual(cache, false)
	if interactable != null and interactable.has_method("set_interaction_enabled"):
		interactable.call("set_interaction_enabled", false)
	_experiment_food_item_ids.append(item_id)
	_physical_food_spawned_count += 1
	_nominal_food_atp += float(properties.get("atp_restore", BRANCH_ATP))
	return {"recipient": recipient, "item_id": item_id}


func _collect_hydraulic_spillway_food() -> bool:
	var pickup := _try_collect_physical_lysate(
		_hydraulic_spillway_food_cache,
		{
			"display_name": "Spillway Lysate",
			"display_names_by_character":
			{
				"aster": "Lysate",
				"peris": "Lysate",
				"endo": "Starch",
			},
			"visual_color": Color(0.66, 0.86, 0.42),
			"atp_restore": float(BRANCH_ATP),
			"food_test": _food_test_mode(),
			"hydraulic_spillway": true,
			"generated_node_id": "node_04",
		}
	)
	if pickup.is_empty():
		return false
	var recipient := str(pickup.get("recipient", ""))
	_last_outcome = "physical_food:spillway:%s" % recipient
	_show_message(
		(
			"%s caught the spillway lysate (+%d ATP when consumed). Their portrait shows it."
			% [recipient.capitalize(), BRANCH_ATP]
		),
		2.8
	)
	return true


func _collect_branch_reward_legacy(index: int) -> void:
	for cache in _branch_caches:
		if int(cache.get("index", -1)) != index or bool(cache.get("collected", false)):
			continue
		cache["collected"] = true
		var reward_atp := int(cache.get("food_atp", BRANCH_ATP))
		_branch_atp_collected += reward_atp
		for char_id in PARTY_IDS:
			_adjust_character_stat(char_id, "atp", float(reward_atp))
		_show_message("Salvaged %d ATP from the cache." % reward_atp, 1.0)
		return


## How many branch salvage caches exist / were collected — for tests + overlays.
func get_branch_cache_count() -> int:
	return _branch_caches.size()


func get_branch_atp_collected() -> int:
	return _branch_atp_collected


func _build_generated_nodes() -> void:
	for node in _nodes():
		if not (node is Dictionary):
			continue
		_build_generated_node(node as Dictionary)


func _build_generated_node(node: Dictionary) -> void:
	var node_id := str(node.get("id", "node"))
	var pos := _node_position(node_id)
	if pos == Vector3.INF:
		return
	var role := str(node.get("role", "route"))
	var pad_size := _vec3(node.get("footprint", node.get("floor_size", [])), _node_pad_size(role))
	var highlight_meshes: Array[MeshInstance3D] = []

	# No big role pad over the tiled floor anymore — just a compact marker post the player reads + clicks, plus the
	# content markers below. Elevation posts still show when a node sits on an upper floor.
	_build_elevation_posts(pos, pad_size, int(node.get("elevation_index", 0)), _role_color(role))
	var marker := _add_box(
		self,
		pos + Vector3(0.0, 0.42, 0.0),
		Vector3(0.9, 0.84, 0.9),
		_role_color(role).lightened(0.08),
		_role_color(role).lightened(0.22),
		0.16,
		"NodeMarker_%s" % node_id
	)
	highlight_meshes.append(marker)
	_node_markers[node_id] = marker
	_add_label(
		self,
		str(node.get("title", node_id)).to_upper(),
		pos + Vector3(0.0, 1.78, 0.0),
		Color(0.88, 0.93, 0.95)
	)
	highlight_meshes.append_array(_build_node_content_markers(node, pos))
	var approach := _vec3(
		node.get("approach_position", []), pos + Vector3(0.0, 0.0, pad_size.z * 0.34)
	)
	var action_verb := _generated_action_verb(node)
	var work_duration := _generated_interaction_duration(node)
	var interaction_type := (
		Interactable.InteractableType.TIMED_ACTION
		if work_duration > 0.0
		else Interactable.InteractableType.INSPECTION
	)

	var interactable := _add_interactable(
		self,
		"GeneratedNode_%s" % node_id,
		str(node.get("title", node_id)),
		approach + Vector3(0.0, 0.12, 0.0),
		action_verb,
		"",
		work_duration,
		false,
		1.8,
		interaction_type,
		false
	)
	interactable.interacted.connect(Callable(self, "activate_generated_node").bind(node_id))
	_node_interactables[node_id] = interactable
	var target_size := Vector3(maxf(1.8, pad_size.x), 1.35, maxf(1.8, pad_size.z))
	if _hydraulic_enabled():
		target_size = Vector3(1.5, 1.35, 1.5)
	var target := _add_outline_target(
		self,
		"GeneratedNodeTarget_%s" % node_id,
		pos + Vector3(0.0, 0.58, 0.0),
		target_size,
		highlight_meshes,
		node_id,
		interactable
	)

	# Cross-wire BOTH directions: the target already delegates to the interactable; the interactable
	# must point back so hover/SHIFT light the node's real marker meshes (its auto-outline used to
	# latch onto its own dwell ring — a flat circle — before rings were excluded from collection).
	if target != null and interactable.has_method("set_outline_target"):
		interactable.call("set_outline_target", target)

		interactable.input_ray_pickable = false
	_node_targets[node_id] = target
	if _is_diagnosis_node(node):
		_build_diagnosis_reads(node, pos, pad_size)


func _generated_action_verb(node: Dictionary) -> String:
	var explicit := str(node.get("action_verb", "")).strip_edges()
	if explicit != "":
		return explicit
	var role := str(node.get("role", ""))
	if str(node.get("id", "")) == "entry" or role == "boundary":
		return "ENTER STRETCH"
	if str(node.get("id", "")) == "exit_shelter" or role in ["shelter", "shelter_arrival"]:
		return "REST AT SHELTER"
	var beat: Dictionary = node.get("systems_beat", {})
	var reasoning_verb := str(beat.get("verb", "intervene")).replace("_", " ").to_upper()
	return reasoning_verb if reasoning_verb != "" else "INTERVENE"


func _generated_interaction_duration(node: Dictionary) -> float:
	var node_id := str(node.get("id", ""))
	var role := str(node.get("role", ""))
	if node_id == "entry" or role == "boundary":
		return 0.0
	if node_id == "exit_shelter" or role in ["shelter", "shelter_arrival"]:
		return 1.4
	if bool(node.get("resource", false)) and str(node.get("survival_kind", "")) == "":
		return 1.8
	return 0.7 if not (node.get("systems_beat", {}) as Dictionary).is_empty() else 0.0


## Generalise the Mother-Flure "three perspectives, deduce the repair" model into the
## generated stretch: one read station per character perspective, each its own inspection
## interactable. Picking the correct read clears the node; a wrong read is a pressure setback
## (handled in diagnose_generated_node) and the stations stay live so the player can re-pick.
func _build_diagnosis_reads(node: Dictionary, pos: Vector3, pad_size: Vector3) -> void:
	var node_id := str(node.get("id", "node"))
	var reads: Array = node.get("reads", [])
	var count := reads.size()
	if count <= 0:
		return
	for i in range(count):
		if not (reads[i] is Dictionary):
			continue
		var read := reads[i] as Dictionary
		var read_id := str(read.get("id", "read_%d" % i))
		var character := str(read.get("character", ""))
		var spread := (float(i) - float(count - 1) * 0.5) * 2.2
		var read_pos := pos + Vector3(spread, 0.4, pad_size.z * 0.5 + 1.4)
		var read_color := _character_color(character)
		_add_box(
			self,
			read_pos,
			Vector3(0.9, 0.8, 0.9),
			read_color.darkened(0.1),
			read_color.lightened(0.2),
			0.18,
			"DiagnosisRead_%s_%s" % [node_id, read_id]
		)
		_add_label(
			self,
			"%s // %s" % [character.to_upper(), str(read.get("label", read_id))],
			read_pos + Vector3(0.0, 0.9, 0.0),
			read_color.lightened(0.3)
		)
		var read_interactable := _add_inspection_interactable(
			self,
			"DiagnosisReadZone_%s_%s" % [node_id, read_id],
			str(read.get("label", read_id)),
			read_pos + Vector3(0.0, -0.2, 0.0),
			"READ",
			"",
			1.4,
			false
		)
		read_interactable.interacted.connect(
			Callable(self, "diagnose_generated_node").bind(node_id, read_id)
		)


## A character's signature colour for a diagnosis read station (matches the preview palette).
func _character_color(character: String) -> Color:
	match character:
		"aster":
			return Color(0.29, 0.62, 1.0)
		"peris":
			return Color(1.0, 0.67, 0.27)
		"endo":
			return Color(0.4, 0.72, 0.55)
		_:
			return Color(0.7, 0.72, 0.76)


func _build_node_content_markers(node: Dictionary, pos: Vector3) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var label_parts: Array[String] = []
	var placements: Array = node.get("content_placements", [])
	if not placements.is_empty():
		for raw_placement in placements:
			if not (raw_placement is Dictionary):
				continue
			var placement := raw_placement as Dictionary
			var category := str(placement.get("category", ""))
			var key := str(placement.get("id", ""))
			var support := str(placement.get("support", _catalog.support_level(category, key)))
			if support != "implemented":
				_unsupported_placeholder_count += 1
			var marker_pos := _vec3(placement.get("position", []), pos)
			var marker_size := _vec3(placement.get("size", []), Vector3(0.8, 0.8, 0.8))
			var marker := _add_content_marker(
				placement,
				marker_pos,
				marker_size,
				_content_color(category, support),
				"Generated_%s_%s" % [category, key]
			)
			meshes.append(marker)
			_content_marker_count += 1
			_add_label(
				self,
				key.to_upper(),
				marker_pos + Vector3(0.0, marker_size.y * 0.55 + 0.34, 0.0),
				_content_color(category, support).lightened(0.25)
			)
			label_parts.append("%s:%s" % [category.substr(0, 1), key])
		_add_content_summary_labels(node, pos, label_parts, placements.size())
		return meshes

	var offsets := [Vector3(-1.45, 0.35, -1.0), Vector3(1.45, 0.35, -1.0), Vector3(0.0, 0.35, 1.15)]
	var marker_index := 0
	for category in ["flora", "enemies", "structures"]:
		var values: Array = node.get(category, [])
		for value in values:
			var key := str(value)
			var marker_pos: Vector3 = (
				pos
				+ offsets[marker_index % offsets.size()]
				+ Vector3(0.0, float(marker_index / offsets.size()) * 0.52, 0.0)
			)
			var support := _catalog.support_level(category, key)
			if support != "implemented":
				_unsupported_placeholder_count += 1
			meshes.append(
				_add_box(
					self,
					marker_pos,
					Vector3(0.74, 0.58, 0.74),
					_content_color(category, support),
					Color.BLACK,
					0.0,
					"Generated_%s_%s" % [category, key]
				)
			)
			_content_marker_count += 1
			_add_label(
				self,
				key.to_upper(),
				marker_pos + Vector3(0.0, 0.72, 0.0),
				_content_color(category, support).lightened(0.25)
			)
			label_parts.append("%s:%s" % [category.substr(0, 1), key])
			marker_index += 1
	var nested_values: Array = node.get("nested_archetypes", [])
	for nested_entry in nested_values:
		if not (nested_entry is Dictionary):
			continue
		var nested := nested_entry as Dictionary
		var nested_key := "A%s" % str(nested.get("id", "?"))
		var marker_pos: Vector3 = (
			pos
			+ offsets[marker_index % offsets.size()]
			+ Vector3(0.0, float(marker_index / offsets.size()) * 0.52, 0.0)
		)
		var nested_color := Color(0.42, 0.34, 0.62)
		meshes.append(
			_add_box(
				self,
				marker_pos,
				Vector3(0.74, 0.58, 0.74),
				nested_color,
				Color.BLACK,
				0.0,
				"Generated_nested_%s" % str(nested.get("ref", nested_key))
			)
		)
		_content_marker_count += 1
		_add_label(
			self,
			"%s S%d" % [nested_key, int(nested.get("host_step", 0))],
			marker_pos + Vector3(0.0, 0.72, 0.0),
			nested_color.lightened(0.25)
		)
		label_parts.append("nest:%s" % nested_key)
		marker_index += 1
	var walk_element := str(node.get("walk_element", ""))
	if walk_element != "":
		var walk_color := Color(0.32, 0.48, 0.62)
		var marker_pos: Vector3 = (
			pos
			+ offsets[marker_index % offsets.size()]
			+ Vector3(0.0, float(marker_index / offsets.size()) * 0.52, 0.0)
		)
		meshes.append(
			_add_box(
				self,
				marker_pos,
				Vector3(0.74, 0.58, 0.74),
				walk_color,
				Color.BLACK,
				0.0,
				"Generated_walk_%s" % str(node.get("walk_ref", node.get("id", "node")))
			)
		)
		_content_marker_count += 1
		_add_label(
			self,
			(
				"W%d S%d"
				% [int(node.get("walk_index", 0)) + 1, int(node.get("walk_step_index", 0)) + 1]
			),
			marker_pos + Vector3(0.0, 0.72, 0.0),
			walk_color.lightened(0.25)
		)
		label_parts.append("walk:%s" % str(node.get("walk_ref", "")))
		marker_index += 1
	if label_parts.is_empty():
		return meshes
	_add_label(self, " ".join(label_parts), pos + Vector3(0.0, 2.22, 0.0), Color(0.62, 0.7, 0.74))
	if walk_element != "":
		_add_label(self, walk_element, pos + Vector3(0.0, 2.78, 0.0), Color(0.68, 0.8, 0.88))
	return meshes


func _build_palette_legend() -> void:
	var usage: Dictionary = _spec.get("palette_usage", {})
	var legend := "Palette "
	var sections: Array[String] = []
	for category in ["flora", "enemies", "structures"]:
		sections.append("%s:%s" % [category, ",".join(_string_array(usage.get(category, [])))])
	legend += " | ".join(sections)
	_add_label(
		self, legend, _anchor_position("entry") + Vector3(6.5, 2.2, -3.4), Color(0.68, 0.74, 0.78)
	)
	var composition: Dictionary = _spec.get("composition", {})
	if not composition.is_empty() and int(composition.get("chain_count", 0)) > 0:
		var composition_label := (
			"Composition chain:%d nested:%d depth:%d"
			% [
				int(composition.get("chain_count", 0)),
				int(composition.get("nested_count", 0)),
				int(composition.get("nested_depth", 0))
			]
		)
		if bool(composition.get("uses_random_walk", false)):
			composition_label = (
				"Random walk elements:%d archetypes:%d"
				% [
					int(composition.get("walk_element_count", 0)),
					int(composition.get("walk_archetype_count", 0))
				]
			)
		_add_label(
			self,
			composition_label,
			_anchor_position("entry") + Vector3(6.5, 2.75, -3.4),
			Color(0.74, 0.68, 0.84)
		)


func _ensure_graybox_layout() -> void:
	if _spec.is_empty():
		return
	var graybox: Dictionary = _spec.get("graybox", {})
	var nodes_have_placements := false
	for node in _spec.get("nodes", []):
		if node is Dictionary and (node as Dictionary).has("content_placements"):
			nodes_have_placements = true
			break
	if (
		str(graybox.get("contract_id", "")) == "generated_stretch_graybox_v1"
		and nodes_have_placements
	):
		return

	var settings: Dictionary = _spec.get("settings", {})
	if not settings.is_empty():
		var regenerated := StretchGeneratorScript.generate(settings)
		if bool(regenerated.get("success", false)):
			for key in ["graybox", "nodes", "routes", "anchors"]:
				if regenerated.has(key):
					_spec[key] = regenerated.get(key)
			if regenerated.has("navigation"):
				_spec["navigation"] = regenerated.get("navigation")
			return

	_apply_local_graybox_fallback()


func _ensure_navigation_layout() -> void:
	if _spec.is_empty():
		return
	var nav_grid: Dictionary = _spec.get("navigation_grid", {})
	if str(nav_grid.get("contract_id", "")) == GridWorld.GRID_DATA_CONTRACT_ID:
		return
	var settings: Dictionary = _spec.get("settings", {})
	if not settings.is_empty():
		var regenerated := StretchGeneratorScript.generate(settings)
		if bool(regenerated.get("success", false)) and regenerated.has("navigation_grid"):
			# Navigation, node positions, room pieces, and graybox bounds are one spatial snapshot. Copying only
			# the grid lets saved dressing from an older generator revision drift off the walkable floor.
			for key in ["navigation_grid", "graybox", "nodes", "routes", "anchors", "navigation", "roompieces"]:
				if regenerated.has(key):
					_spec[key] = regenerated.get(key)
			return
	_spec["navigation_grid"] = StretchGeneratorScript.build_navigation_grid_from_spec(_spec)


func _apply_local_graybox_fallback() -> void:
	var nodes: Array = _spec.get("nodes", [])
	var routes: Array = _spec.get("routes", [])
	var min_point := Vector3(1e+20, 1e+20, 1e+20)
	var max_point := Vector3(-1e+20, -1e+20, -1e+20)
	var elevations: Array[int] = []
	var placement_count := 0
	for i in range(nodes.size()):
		if not (nodes[i] is Dictionary):
			continue
		var node: Dictionary = nodes[i]
		var elevation_index := 0 if i == 0 or i == nodes.size() - 1 else i % 3
		var pos := _vec3(node.get("position", []), Vector3(float(i) * 12.0, 0.45, 0.0))
		pos.y = 0.45 + float(elevation_index) * 0.72
		var footprint := _node_pad_size(str(node.get("role", "mixed")))
		node["position"] = _vec3_array(pos)
		node["elevation_index"] = elevation_index
		node["surface_y"] = pos.y
		node["elevation_meters"] = pos.y - 0.45
		node["footprint"] = _vec3_array(footprint)
		node["floor_size"] = _vec3_array(footprint)
		node["approach_position"] = _vec3_array(pos + Vector3(0.0, 0.0, footprint.z * 0.34))
		node["content_placements"] = _fallback_content_placements(node, pos, footprint)
		placement_count += (node["content_placements"] as Array).size()
		nodes[i] = node
		if not elevations.has(elevation_index):
			elevations.append(elevation_index)
		var half := footprint * 0.5 + Vector3.ONE
		min_point = (pos - half) if i == 0 else min_point.min(pos - half)
		max_point = (
			(pos + half + Vector3(0.0, 3.0, 0.0))
			if i == 0
			else max_point.max(pos + half + Vector3(0.0, 3.0, 0.0))
		)
	for i in range(routes.size()):
		if not (routes[i] is Dictionary):
			continue
		var route: Dictionary = routes[i]
		route["width"] = 1.15 if _route_kind(route) == "risky" else 1.65
		routes[i] = route
	elevations.sort()
	_spec["nodes"] = nodes
	_spec["routes"] = routes
	_spec["anchors"] = _rebuild_anchors_from_nodes(nodes)
	_spec["graybox"] = {
		"contract_id": "generated_stretch_graybox_v1",
		"surface_y_base": 0.45,
		"elevation_step": 0.72,
		"elevation_indices": elevations,
		"elevation_count": elevations.size(),
		"supports_click_to_move": true,
		"supports_outline_targets": true,
		"supports_multiple_elevations": elevations.size() > 1,
		"node_surface_count": nodes.size(),
		"route_surface_count": routes.size(),
		"content_placement_count": placement_count,
		"bounds":
		{
			"min": _vec3_array(min_point),
			"max": _vec3_array(max_point),
			"center": _vec3_array((min_point + max_point) * 0.5),
			"size": _vec3_array(max_point - min_point),
		},
	}


func _fallback_content_placements(node: Dictionary, pos: Vector3, footprint: Vector3) -> Array:
	var placements := []
	var slot_index := 0
	for category in ["flora", "enemies", "structures"]:
		var values: Array = node.get(category, [])
		for value in values:
			var key := str(value)
			var size := _fallback_content_size(category)
			var offset := Vector3(
				-footprint.x * 0.22 + slot_index * 0.65,
				size.y * 0.5,
				-footprint.z * 0.16 + slot_index * 0.34
			)
			(
				placements
				. append(
					{
						"id": key,
						"category": category,
						"support": _catalog.support_level(category, key),
						"shape":
						(
							"enemy_volume"
							if category == "enemies"
							else ("plant_cluster" if category == "flora" else "structure_box")
						),
						"size": _vec3_array(size),
						"local_offset": _vec3_array(offset),
						"position": _vec3_array(pos + offset),
						"rotation_y_degrees": float(slot_index * 31),
						"label": key,
					}
				)
			)
			slot_index += 1
	return placements


func _fallback_content_size(category: String) -> Vector3:
	match category:
		"flora":
			return Vector3(1.2, 1.0, 1.2)
		"enemies":
			return Vector3(1.4, 1.1, 1.4)
		"structures":
			return Vector3(1.6, 1.2, 1.0)
		_:
			return Vector3.ONE


func _rebuild_anchors_from_nodes(nodes: Array) -> Dictionary:
	var anchors: Dictionary = _spec.get("anchors", {}).duplicate(true)
	if not anchors.has("aster"):
		anchors["aster"] = [0.0, 0.5, 1.6]
	if not anchors.has("peris"):
		anchors["peris"] = [-1.6, 0.5, 0.0]
	if not anchors.has("endo"):
		anchors["endo"] = [-1.2, 0.5, -1.8]
	for node in nodes:
		if node is Dictionary:
			anchors[str((node as Dictionary).get("id", ""))] = (node as Dictionary).get(
				"position", [0.0, 0.45, 0.0]
			)
	return anchors


func _graybox_state() -> Dictionary:
	var graybox: Dictionary = _spec.get("graybox", {})
	var nav_grid: Dictionary = _spec.get("navigation_grid", {})
	return {
		"contract_id": str(graybox.get("contract_id", "")),
		"navigation_contract_id":
		str(graybox.get("navigation_contract_id", nav_grid.get("contract_id", ""))),
		"supports_click_to_move": bool(graybox.get("supports_click_to_move", false)),
		"supports_outline_targets": bool(graybox.get("supports_outline_targets", false)),
		"supports_multiple_elevations": bool(graybox.get("supports_multiple_elevations", false)),
		"elevation_count": int(graybox.get("elevation_count", 0)),
		"node_surface_count": int(graybox.get("node_surface_count", _nodes().size())),
		"route_surface_count": int(graybox.get("route_surface_count", _routes().size())),
		"navigation_node_count": int(graybox.get("navigation_node_count", _nodes().size())),
		"navigation_edge_count": int(graybox.get("navigation_edge_count", _routes().size())),
		"content_placement_count":
		int(graybox.get("content_placement_count", _content_marker_count)),
		"instanced_content_marker_count": _content_marker_count,
		"outline_target_count": _node_targets.size(),
		"route_surface_instance_count": _route_surfaces.size(),
		"bounds": graybox.get("bounds", {}).duplicate(true),
	}


func _add_graybox_slab(
	parent: Node3D,
	position: Vector3,
	size: Vector3,
	color: Color,
	node_name := "",
	rotation := Vector3.ZERO,
	add_collision := true
) -> MeshInstance3D:
	var mesh := _add_box(parent, position, size, color, color.lightened(0.08), 0.05, node_name)
	mesh.rotation = rotation
	if add_collision:
		var body := StaticBody3D.new()
		body.name = "%sCollision" % (node_name if node_name != "" else "GrayboxSlab")
		body.position = position
		body.rotation = rotation
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		parent.add_child(body)
	return mesh


func _build_elevation_posts(
	pos: Vector3, pad_size: Vector3, elevation_index: int, color: Color
) -> void:
	if elevation_index <= 0:
		return
	var post_height := maxf(0.24, pos.y - 0.28)
	var corners := [
		Vector3(-pad_size.x * 0.42, -post_height * 0.5 - 0.03, -pad_size.z * 0.42),
		Vector3(pad_size.x * 0.42, -post_height * 0.5 - 0.03, -pad_size.z * 0.42),
		Vector3(-pad_size.x * 0.42, -post_height * 0.5 - 0.03, pad_size.z * 0.42),
		Vector3(pad_size.x * 0.42, -post_height * 0.5 - 0.03, pad_size.z * 0.42),
	]
	for i in range(corners.size()):
		_add_box(
			self,
			pos + corners[i],
			Vector3(0.16, post_height, 0.16),
			color.darkened(0.22),
			Color.BLACK,
			0.0,
			"ElevationPost_%d" % i
		)


func _add_content_marker(
	placement: Dictionary,
	marker_pos: Vector3,
	marker_size: Vector3,
	color: Color,
	node_name: String
) -> MeshInstance3D:
	var shape := str(placement.get("shape", "structure_box"))
	var marker := MeshInstance3D.new()
	marker.name = node_name
	match shape:
		"plant_cluster", "canopy":
			var sphere := SphereMesh.new()
			sphere.radius = maxf(marker_size.x, marker_size.z) * 0.5
			sphere.height = marker_size.y
			marker.mesh = sphere
		"mat":
			var box := BoxMesh.new()
			box.size = marker_size
			marker.mesh = box
		"vine_column", "enemy_volume", "pipe":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = maxf(marker_size.x, marker_size.z) * 0.5
			cylinder.bottom_radius = cylinder.top_radius
			cylinder.height = marker_size.y
			cylinder.radial_segments = 12
			marker.mesh = cylinder
		_:
			var box := BoxMesh.new()
			box.size = marker_size
			marker.mesh = box
	marker.material_override = _make_material(
		color,
		color.lightened(0.15),
		0.18 if str(placement.get("support", "")) == "implemented" else 0.06
	)
	marker.position = marker_pos
	marker.rotation.y = deg_to_rad(float(placement.get("rotation_y_degrees", 0.0)))
	add_child(marker)
	return marker


func _add_content_summary_labels(
	node: Dictionary, pos: Vector3, label_parts: Array[String], _placement_count: int
) -> void:
	if label_parts.is_empty():
		return
	_add_label(self, " ".join(label_parts), pos + Vector3(0.0, 2.36, 0.0), Color(0.62, 0.7, 0.74))
	var walk_element := str(node.get("walk_element", ""))
	if walk_element != "":
		_add_label(self, walk_element, pos + Vector3(0.0, 2.92, 0.0), Color(0.68, 0.8, 0.88))


func _add_outline_target(
	parent: Node3D,
	target_name: String,
	center: Vector3,
	size: Vector3,
	meshes: Array[MeshInstance3D],
	node_id: String,
	delegate: Node
) -> StaticBody3D:
	# Build through the shared outline system so the target is actually bound to a
	# feedback manager in gameplay (it used to be orphaned here). Stretch tuning is
	# slimmer than the room default (smaller particle budget, taller highlight box).
	var metadata := {"generated_node_id": node_id}
	var opts := {
		"outline_highlight_height": maxf(0.8, size.y * 0.5),
		"selected_feedback_duration": 1.4,
		"hover_object_outline_width": 0.075,
		"selected_object_glow_strength": 3.2,
		"selected_particle_count": 130,
		"outline_particles_per_mesh": 96,
		"debug_particle_anchor_enabled": false,
		"delegate": delegate,
		"metadata": metadata,
	}
	return (
		_outline_target(
			parent, target_name, center, size, meshes, node_id, maxf(size.x, size.z) * 0.5, opts
		)
		as StaticBody3D
	)


func _reach_exit_shelter() -> void:
	if _shelter_rested:
		return
	if not _node_progression_ready("exit_shelter"):
		return
	if _hydraulic_enabled() and not bool(_hydraulic_state().get("hydraulic_exit_unlocked", false)):
		_block_hydraulic_progress(
			"Restore the main current before leaving for the shelter.",
			_hydraulic_diverter_control,
			_hydraulic_exit_link
		)
		return
	_shelter_reached = true
	_shelter_rested = true
	for node_id in _completed_nodes:
		var delivered_node := _find_node(node_id)
		if bool(delivered_node.get("carry_payload", false)) and not _delivered_resource_nodes.has(node_id):
			_delivered_resource_nodes.append(node_id)
	_route_phase = "complete"
	_last_outcome = "success"
	_first_shelter_beat_fired = true
	_cancel_scarcity_drain()
	_restore_party(_food_test_mode() != FOOD_TEST_NEUTRAL)
	_disable_exit_shelter_interaction()
	_highlight_node("exit_shelter", true)
	_set_preview_step("generated_stretch_complete")
	_show_message("STRETCH COMPLETE — the party reached shelter.", 4.5)
	_show_note("SHELTER SECURED // Rest complete. This stretch is finished.", 5.0)


func _disable_exit_shelter_interaction() -> void:
	var interactable: Node = _node_interactables.get("exit_shelter", null)
	if interactable != null and is_instance_valid(interactable):
		if interactable.has_method("set_interaction_enabled"):
			interactable.call("set_interaction_enabled", false)
		interactable.set("input_ray_pickable", false)
	_set_outline_target_enabled(_node_targets.get("exit_shelter", null), false)


func _rearm_exit_shelter_interaction() -> void:
	var interactable: Node = _node_interactables.get("exit_shelter", null)
	if interactable != null and is_instance_valid(interactable):
		if interactable.has_method("set_interaction_enabled"):
			interactable.call("set_interaction_enabled", true)
		# Generated-node interaction is delegated through the visible outline target.
		interactable.set("input_ray_pickable", false)
	if not _hydraulic_enabled():
		_set_outline_target_enabled(_node_targets.get("exit_shelter", null), true)


## Forage cache: bank a partial ATP top-up toward the next rest (GDD 2.4 — lysate adds
## whole pips up to the 8-pip cap). Not a full restore; the rest at the shelter is.
func _apply_forage_reward(node: Dictionary) -> void:
	var pips := int(node.get("atp_reward", 2))
	if pips <= 0:
		pips = 2
	_atp_foraged += pips
	for char_id in PARTY_IDS:
		_adjust_character_stat(char_id, "atp", float(pips))
	_route_phase = "forage"
	_last_outcome = "forage:+%d_atp" % pips
	_show_message("Banked %d ATP from the cache." % pips, 1.0)


func _secure_generated_resource(node: Dictionary) -> bool:
	var recipient := _get_active_character()
	if not _active_party.has(recipient):
		recipient = ""
	if recipient == "" and not _active_party.is_empty():
		recipient = str(_active_party[0])
	if recipient == "":
		_show_message("Select a character to carry this resource.", 1.4)
		return false
	var gs = _get_game_state()
	if gs == null or not ("characters" in gs) or not (gs.get("characters") as Dictionary).has(recipient):
		# Standalone data-layer chunk tests have no inventory authority. Preserve the
		# causal/resource state there; full previews still create the physical hand item.
		_resources_collected += 1
		_last_outcome = "resource_held_simulated:%s:%s" % [str(node.get("id", "")), recipient]
		return true
	if gs != null and gs.has_method("has_free_hand"):
		for candidate_v in _active_party:
			var candidate := str(candidate_v)
			if not bool(gs.call("has_free_hand", candidate)):
				continue
			if gs.has_method("get_hand_items") and (gs.call("get_hand_items", candidate) as Array).is_empty():
				recipient = candidate
				break
	if gs != null and gs.has_method("has_free_hand") and not bool(gs.call("has_free_hand", recipient)):
		for candidate in _active_party:
			if bool(gs.call("has_free_hand", str(candidate))):
				recipient = str(candidate)
				break
	if gs != null and gs.has_method("has_free_hand") and not bool(gs.call("has_free_hand", recipient)):
		_show_message("The active party needs a free hand for this resource.", 1.5)
		return false
	var display_name := str(node.get("title", "Generated Tool"))
	var is_food := str(node.get("reward_kind", "")) == "food"
	var item_type := "lysate" if is_food else str(node.get("resource_item_type", "generated_tool"))
	var reward_atp := maxi(1, int(node.get("reward_atp", node.get("atp_reward", 2))))
	var item_id := _spawn_item(item_type, _get_character_position(recipient), {
		"display_name": display_name,
		"visual_kind": "food" if is_food else "tool",
		"visual_color": _role_color(str(node.get("role", "foraging"))).lightened(0.25),
		"generated_node_id": str(node.get("id", "")),
		"systems_verb": str(node.get("systems_beat", {}).get("verb", "intervene")),
		"chain_state_ref": str(node.get("chain_output_ref", "")),
		"carry_payload": bool(node.get("carry_payload", false)),
		"hand_slots": 1,
		"atp_restore": float(reward_atp) if is_food else 0.0,
		"endocytosis_allowed": is_food,
		"consumable": is_food,
	})
	if item_id == "" or not _pick_up_item(recipient, item_id):
		if item_id != "":
			_remove_item(item_id)
		_show_message("The resource could not be transferred.", 1.3)
		return false
	_generated_resource_item_ids.append(item_id)
	_resources_collected += 1
	if is_food:
		_physical_food_spawned_count += 1
		_nominal_food_atp += float(reward_atp)
	_last_outcome = "resource_held:%s:%s" % [str(node.get("id", "")), recipient]
	_show_note(
		"HELD BY %s // Click the portrait holding icon to lock this carrier."
		% recipient.to_upper(),
		3.0
	)
	return true


func _reset_generated_resource_items() -> void:
	for item_id in _generated_resource_item_ids:
		_remove_item(item_id)
	_generated_resource_item_ids.clear()


## Gauntlet / attrition field: HP + stamina drain crossing it (recovered at the shelter).
## A specialist holding the lanes (or Endo building a protected lane) mitigates the
## attrition; the Aster+Peris pair pays the full price — the survival cost of the shadow.
func _apply_node_pressure(node: Dictionary, approach := {}) -> void:
	var damage := maxf(6.0, float(int(node.get("pressure_cost", 1))) * 8.0)
	if str(approach.get("party", "")) == "specialist":
		damage *= 0.4
	_pressure_taken += damage
	for char_id in PARTY_IDS:
		_adjust_character_stat(char_id, "hp", -damage)
		_adjust_character_stat(char_id, "stamina", -damage * 0.6)
	_route_phase = "attrition"
	_last_outcome = "pressure:%s" % str(node.get("survival_kind", "gauntlet"))
	_show_message("Attrition crossing the %s." % str(node.get("survival_kind", "gauntlet")), 1.0)


func _apply_risky_pressure(risk: int, route := {}) -> void:
	var route_def: Dictionary = route if route is Dictionary else {}
	var damage := _route_damage_amount(route_def, risk)
	_risky_damage_total += damage
	for char_id in PARTY_IDS:
		_adjust_character_stat(char_id, "hp", -damage)
		_adjust_character_stat(char_id, "stamina", -damage * 0.7)
	_last_outcome = "risky_pressure:%.1f" % damage
	_route_phase = "impact"
	_show_message("NEAR MISS — every character lost %s HP." % _atp_amount_text(damage), 2.2)
	_show_note("EXPOSED ROUTE // The shortcut saved time but spent party capacity.", 3.2)
	_flash_risky_destination(route_def)


func _route_damage_amount(route: Dictionary, fallback_risk := -1) -> float:
	var risk := fallback_risk if fallback_risk >= 0 else _route_risk_value(route)
	var damage := maxf(8.0, float(risk) * 8.0)
	if route.has("damage"):
		damage = maxf(0.0, float(route.get("damage", damage)))
	return damage


func _flash_risky_destination(route: Dictionary) -> void:
	var node_id := str(route.get("to", ""))
	var target: Node = _node_targets.get(node_id, null)
	if target == null or not is_instance_valid(target):
		return
	var reason := "risky_route_impact"
	if target.has_method("set_external_highlight"):
		target.call("set_external_highlight", reason, true)
		var sched = _get_scheduler()
		if sched != null and sched.has_method("schedule_after"):
			sched.schedule_after(1.4, func() -> void:
				if is_instance_valid(target):
					target.call("set_external_highlight", reason, false),
				"generated_risky_route_flash"
			)
	if target is Node3D:
		_request_preview_focus(target as Node3D, 0.75, false, {
			"reason": "risky_route_impact",
			"label": "NEAR MISS // -%s HP" % _atp_amount_text(_route_damage_amount(route)),
		})


func _restore_party(preserve_atp := false) -> void:
	if not preserve_atp:
		_restore_party_full()
		return
	for char_id in PARTY_IDS:
		_set_character_stat(char_id, "hp", FULL_HP)
		_set_character_stat(char_id, "stamina", FULL_STAMINA)
		_set_character_visible(char_id, true)
		_set_character_status(char_id, "")


func _restore_party_full() -> void:
	for char_id in PARTY_IDS:
		_set_character_stat(char_id, "hp", FULL_HP)
		_set_character_stat(char_id, "stamina", FULL_STAMINA)
		_set_character_stat(char_id, "atp", GameState.ATP_MAX_PIPS)
		_set_character_visible(char_id, true)
		_set_character_status(char_id, "")


func _highlight_node(node_id: String, selected: bool) -> void:
	var marker: MeshInstance3D = _node_markers.get(node_id, null)
	if marker == null:
		return
	var role_color := _role_color(str(_find_node(node_id).get("role", "")))
	marker.material_override = _make_material(
		role_color.lightened(0.26 if selected else 0.08),
		role_color.lightened(0.48),
		0.42 if selected else 0.18
	)


func _full_party_state() -> Dictionary:
	return {
		"aster":
		{"hp": FULL_HP, "stamina": FULL_STAMINA, "atp": GameState.ATP_MAX_PIPS, "visible": true},
		"peris":
		{"hp": FULL_HP, "stamina": FULL_STAMINA, "atp": GameState.ATP_MAX_PIPS, "visible": true},
		"endo":
		{"hp": FULL_HP, "stamina": FULL_STAMINA, "atp": GameState.ATP_MAX_PIPS, "visible": true},
	}


func _nodes() -> Array:
	_ensure_spec_loaded()
	return _spec.get("nodes", [])


func _routes() -> Array:
	_ensure_spec_loaded()
	return _spec.get("routes", [])


func _find_node(node_id: String) -> Dictionary:
	for node in _nodes():
		if node is Dictionary and str((node as Dictionary).get("id", "")) == node_id:
			return (node as Dictionary).duplicate(true)
	return {}


func _find_route(route_id: String) -> Dictionary:
	for route in _routes():
		if route is Dictionary and str((route as Dictionary).get("id", "")) == route_id:
			return (route as Dictionary).duplicate(true)
	return {}


func _anchor_position(anchor_id: String) -> Vector3:
	var anchors: Dictionary = _spec.get("anchors", {})
	if anchors.has(anchor_id):
		return _vec3(anchors[anchor_id], Vector3.ZERO)
	return _node_position(anchor_id)


func _node_position(node_id: String) -> Vector3:
	var node := _find_node(node_id)
	if not node.is_empty():
		return _vec3(node.get("position", []), Vector3.ZERO)
	var anchors: Dictionary = _spec.get("anchors", {})
	if anchors.has(node_id):
		var anchor := _vec3(anchors[node_id], Vector3.ZERO)
		return Vector3(anchor.x, 0.0, anchor.z)
	return Vector3.INF


func _vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw as Vector3
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float((raw as Array)[0]), float((raw as Array)[1]), float((raw as Array)[2]))
	return fallback


func _vec3_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _node_pad_size(role: String) -> Vector3:
	match role:
		"entry", "boundary":
			return Vector3(4.2, 0.12, 3.4)
		"shelter", "shelter_arrival":
			return Vector3(6.6, 0.14, 4.8)
		"pressure", "route_pressure", "danger":
			return Vector3(4.8, 0.12, 2.6)
		"shortcut":
			return Vector3(3.6, 0.12, 3.6)
		"foraging":
			return Vector3(4.8, 0.12, 3.8)
		"guidance":
			return Vector3(4.2, 0.12, 3.4)
		"setpiece":
			return Vector3(5.8, 0.12, 4.4)
		_:
			return Vector3(3.4, 0.12, 2.8)


func _role_color(role: String) -> Color:
	match role:
		"entry":
			return Color(0.18, 0.28, 0.34)
		"boundary":
			return Color(0.16, 0.22, 0.2)
		"resource", "foraging":
			return Color(0.18, 0.32, 0.2)
		"guidance":
			return Color(0.16, 0.25, 0.36)
		"pressure", "route_pressure", "danger":
			return Color(0.38, 0.16, 0.12)
		"shortcut":
			return Color(0.28, 0.22, 0.38)
		"setpiece":
			return Color(0.34, 0.26, 0.15)
		"shelter", "shelter_arrival":
			return Color(0.34, 0.27, 0.16)
		_:
			return Color(0.2, 0.22, 0.24)


func _route_color(route: Dictionary) -> Color:
	var kind := _route_kind(route)
	match kind:
		"risky":
			return Color(0.72, 0.24, 0.14)
		"safe":
			return Color(0.24, 0.48, 0.42)
		"shortcut":
			return Color(0.48, 0.36, 0.68)
		_:
			return Color(0.28, 0.34, 0.38)


func _route_kind(route: Dictionary) -> String:
	var kind := str(route.get("kind", ""))
	if kind != "":
		return kind
	return str(route.get("risk", "safe"))


func _route_risk_value(route: Dictionary) -> int:
	var raw: Variant = route.get("risk", route.get("kind", 0))
	if raw is int or raw is float:
		return int(raw)
	match str(raw):
		"risky":
			return 2
		"danger":
			return 2
		"safe":
			return 0
		"shortcut":
			return 0
		_:
			return 0


func _content_color(category: String, support: String) -> Color:
	if support != "implemented":
		return Color(0.46, 0.48, 0.5)
	match category:
		"flora":
			return Color(0.24, 0.56, 0.34)
		"enemies":
			return Color(0.68, 0.28, 0.18)
		"structures":
			return Color(0.36, 0.42, 0.52)
		_:
			return Color(0.5, 0.5, 0.5)


func _string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for value in raw:
			result.append(str(value))
	return result
