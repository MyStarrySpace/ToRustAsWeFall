extends "res://scripts/scene_chunks/scene_chunk.gd"

## GENERATED ATOM — the bridge from a graded ChunkGenerator SKELETON to a REAL walkable room. The chunk takes
## {stages, seed}, regenerates the exact skeleton the report card graded (same seed = same sketch), and builds
## it with REAL mechanics only: real Enemy sentries with LOS-gated detection watching each gap, real flure
## TIMED_ACTION tends, real conceal pockets (CONCEAL_MEDIUM — the Shadow's stage), catch = the kit's own chase
## (P11: the wash takes you to the bottom) + that sentry re-posts in one atomic beat. No dynamic blockers, no
## "click = solved" stand-ins — the gate IS the detection, exactly like the hand-built Watched Gap, but
## GENERATED. Only archetypes whose mechanics are PROVEN in-engine may build here (distract today); anything
## else in the stage list is refused loudly — the honesty ledger, enforced at build time.

const ChunkGen := preload("res://scripts/generation/chunk_generator.gd")
const EnemyScript := preload("res://scripts/game/ai/enemy.gd")

const PARTY_IDS := ["aster", "peris", "endo"]
const CELL := 1.5                  # skeleton cell -> world units
const SENTRY_RANGE := 4.0          # posts IN the gap: covers its lane + a short through-gap approach strip;
                                   # tuned so flure/conceal pockets sit OUTSIDE a re-posted sentry's reach
                                   # (the chain must stay solvable after earlier sentries re-arm)
## The authored pressure tier: faster than the fastest party walk (Aster 3.2), slower than the
## shared 6.0 sprint. A clean sprint opens distance; trying to walk away steadily loses it.
const SENTRY_SPEED := 3.6
const PATROL_SPEED := 1.2          # patrol variant: a slow, READABLE beat — the look-away window is generous
                                   # (P1: pressure never comes from tighter timing)
const SENTRY_ALERT_DURATION := 0.9 # a fair recognition beat before the faster pursuit engages
const LURE_DURATION := 20.0
const LURE_WARNING_SECONDS := 3.0
const LURE_READY_RADIUS := 1.25      # planar radius; navigation flattens Y while authored marker heights are cosmetic
const FLURE_TEND := 2.0
const FLURE_PICK_RADIUS := 1.0
const WIN_POLL_INTERVAL := 0.1
const BASE_N := 4                  # base-pad width in cells: the run ENTRY floor, west of chamber 0. On a
                                   # hub shape this is the shape flat centre floor (HubShapeCoordMap s<0);
                                   # flat it is a simple pad. The shelter BEFORE sits here; the party spawns here.

var _def: Dictionary = {}          # the regenerated skeleton (graded + built from the SAME data)
var _card: Dictionary = {}         # its principle report card, kept for provenance
var _stages: Array = []            # per gate: {sentry, post, settle, lane_world, flure_cell, conceal_world}
var _phase := "ready"
var _caught_count := 0
var _config_stages: Array = ["distract", "distract"]
var _config_seed := 7
var _hub_shape: Dictionary = {}    # optional macro shape ({type: circle|rect|hexagon|triangle|polygon,...});
                                   # empty = flat. DATA stays flat either way (one truth); visuals warp.
var _descent_per_turn := 2.0
var _coord_map = null
var _shelter_rested := false
var _district: Dictionary = {}
var _skirt_stats: Dictionary = {}
var _conceal_taught := false
var _zone_setpieces := true
var _retry_pending := false

func configure_chunk(config: Dictionary) -> void:
	if config.has("stages"):
		_config_stages = (config["stages"] as Array).duplicate()
	_config_seed = int(config.get("seed", _config_seed))
	_hub_shape = (config.get("hub_shape", {}) as Dictionary).duplicate(true)
	_descent_per_turn = float(config.get("descent_per_turn", _descent_per_turn))
	_district = (config.get("district", {}) as Dictionary).duplicate(true)
	_zone_setpieces = bool(config.get("zone_setpieces", _zone_setpieces))

## Puzzle language must survive the district silhouette. The generated route deliberately runs
## through dense built fabric, so Atom's instructional labels render over occluders like HUD-world
## callouts while the ordinary district labels keep their natural depth behavior.
func _add_atom_label(text: String, pos: Vector3, tint: Color) -> Label3D:
	var label := _add_label(self, text, pos, tint)
	label.no_depth_test = true
	label.render_priority = 2
	label.fixed_size = true
	# Match Interactable's proven Web-visible hover-label projection. Fixed-size text is
	# rendered as though the camera were one unit away, so ordinary world-label scale is huge.
	label.font_size = 72
	label.pixel_size = 0.0006
	label.outline_size = 10
	return label

# --- Build: skeleton -> real room -------------------------------------------------------------------------------

func _build_chunk() -> void:
	_def = ChunkGen.compose(_config_stages, _config_seed)
	_card = ChunkGen.report_card(_def)
	var w := int(_def["w"])
	var h := int(_def["h"])
	var mid := h / 2
	var warped := not _hub_shape.is_empty()
	# Floors. Flat: two slabs (skeleton + base). Warped: PER-CELL tiles so each seats onto the deck.
	if warped:
		for cellv in _walkable_world_cells():
			var wp: Vector3 = cellv
			_add_floor(self, Vector3(wp.x, -0.05, wp.z), Vector3(CELL, 0.1, CELL), Color(0.09, 0.1, 0.12))
	else:
		_add_floor(self, Vector3(w * CELL * 0.5, -0.05, 0.0), Vector3(w * CELL, 0.1, h * CELL), Color(0.09, 0.1, 0.12))
		_add_floor(self, Vector3(-BASE_N * CELL * 0.5, -0.05, 0.0), Vector3(BASE_N * CELL, 0.1, h * CELL), Color(0.08, 0.1, 0.11))
	# Walls per skeleton cell — with a DOORWAY carved at chamber 0 west border (rows mid±1) so the base
	# connects to the level (the shelter BEFORE connects to the base; the base connects to the start).
	var grid: Dictionary = _def["grid"]
	for c in grid.keys():
		if str(grid[c]) == ChunkGen.SYM_WALL:
			var cv := c as Vector2i
			if cv.x == 0 and absi(cv.y - mid) <= 1:
				continue
			var p := _world(c)
			_add_box(self, Vector3(p.x, 1.4, p.z), Vector3(CELL, 2.8, CELL), Color(0.06, 0.06, 0.08))
	# The base pad: entry-shelter marker + spawn ground.
	var base_c := Vector3(-BASE_N * CELL * 0.5, 0.5, 0.0)
	var entry_pad := _add_box(self, Vector3(base_c.x, 0.02, 0.0),
		Vector3(CELL * 1.6, 0.04, CELL * 1.6), Color(0.14, 0.2, 0.17),
		Color(0.2, 0.82, 0.48), 0.55, "AtomEntryShelterPad")
	_build_entry_shelter(base_c, entry_pad)
	_add_atom_label("ENTRY SHELTER", base_c + Vector3(0, 1.8, 0), Color(0.5, 0.8, 0.6))
	_add_atom_label("WATCHED GAPS  →\nWALK LOSES · SPRINT ESCAPES",
		Vector3(-0.5 * CELL, 2.15, 0.0), Color(0.92, 0.72, 0.32))
	_add_atom_label("END", _world(_def["end"]) + Vector3(0, 1.8, 0), Color(0.85, 0.8, 0.5))
	# Stages: refuse anything the bridge cannot build for REAL (the honesty ledger at build time).
	var gates: Array = _def["gates"]
	for i in range(gates.size()):
		var gt: Dictionary = gates[i]
		if str(gt["arch"]) != "distract":
			push_error("puzzle_atom_chunk: stage %d archetype has no REAL bridge build yet (%s) — refuse, never fake" % [i, str(gt["arch"])])
			continue
		_build_distract_stage(i, gt)
	_build_exit_shelter()
	# THE INTERMEDIATE ZONE: when the run names a district, the flat level dresses itself in the
	# connective fabric — the puzzle room becomes streets cut through the zone the descent is
	# passing through (idiom + decay from the run's depth).
	if not warped and not _district.is_empty():
		_skirt_stats = _build_district_skirt(get_grid_data(), _config_seed, 6, {
			"idiom": str(_district.get("idiom", "mixed")),
			"decay_add": float(_district.get("decay", 0.0)),
			# The standalone teaching chain keeps its district walls but omits the elevated
			# transit ribbons that project across the watched lanes from this camera angle.
			"viaducts": _zone_setpieces,
		})
		if _zone_setpieces:
			_build_zone_belt()
			_build_zone_sump()
	if warped:
		_apply_hub_warp()

## The opening pad is more than scenery: it is the readable reset boundary for a chase.
## Use an explicit object interactable so its outline owns only the small pad, never the
## generated base slab (a broad auto-outline would steal floor clicks again).
func _build_entry_shelter(base_c: Vector3, entry_pad: MeshInstance3D) -> void:
	var gs = _get_game_state()
	if gs != null and gs.has_method("add_shelter_region"):
		var half := CELL * 1.2
		gs.add_shelter_region(Vector2(base_c.x - half, base_c.z - half),
			Vector2(base_c.x + half, base_c.z + half))
	var rest := _add_object_interactable(self, "AtomEntryRest", "Entry shelter",
		Vector3(base_c.x, 0.1, base_c.z), "REST / RETRY", [entry_pad], "", 1.2,
		false, 2.2, Interactable.InteractableType.TIMED_ACTION)
	rest.interacted.connect(_on_entry_rest.bind(rest))

func _on_entry_rest(rest: Node) -> void:
	var gs = _get_game_state()
	var active_id := str(rest.active_character) if rest != null else ""
	# This station is deliberately click-to-work rather than a proximity HOLD. Three party
	# bodies can share the entry shelter, and a repeatable proximity dwell would otherwise
	# re-arm forever (or retain a stale physics overlap) and emit REST / RETRY from across
	# the level. The data-layer shelter check is the final authority before either effect.
	if gs == null or active_id == "" or not gs.characters.has(active_id) \
			or gs.is_downed(active_id) or not gs.is_at_shelter(active_id):
		return
	if _phase == "complete":
		return
	if not gs.is_resting(active_id) \
			and gs.get_stat(active_id, "hp") < gs.get_stat_cap(active_id, "hp") \
			and gs.get_stat(active_id, "atp") >= 1.0:
		gs.command_rest(active_id)
	if not _retry_pending:
		return
	for stage_index in range(_stages.size()):
		_reset_sentry_to_post(stage_index)
	_retry_pending = false
	_phase = "ready"
	_show_gate_cue("SAFE GROUND — every watcher has re-posted. Re-plan, then try again.", 3.2)
	_set_preview_step("atom_retry")

## SET_PIECES.md #25 in the wild: the intermediate zone's derelict supply line arcs out over the
## fabric behind the entry base and lands back inside it. Both mouths sit in the SAME
## already-connected space (the base pad), so the ride can never bypass a gate — it fleshes the
## zone (old supply chain crossing the streets) and teaches the belt verb for later stretches.
## SET_PIECES.md #27: a decommissioned bore sump in a dead-end pocket at the base pad's south
## corner — DRAIN to climb down for the cache, FLOOD to raise the ledge vantage and drown the
## penned scrap. Both the pit and the ledge are OFF the entry->exit path (the run flows base ->
## doorway -> skeleton), so the sump is reward + flavor, never a gate bypass. Cells derive purely
## from _def, matching get_grid_data's union.
func _build_zone_sump() -> void:
	var pk := _sump_pocket()
	if pk.is_empty():
		return
	_spawn_sump({"name": "ZoneSump", "pos": pk["pos"], "pump_pos": pk["pump_pos"],
		"pit_min": pk["pit_min"], "pit_max": pk["pit_max"], "pit_cells": pk["pit_cells"],
		"ledge_cell": pk["ledge_cell"], "ledge_level": 1, "pit_enemy": true,
		"label_text": "BORE SUMP — SIPHON DECOMMISSIONED"})

## The sump pocket, derived PURELY from _def so get_grid_data and the visuals agree. Two base-pad
## corner cells become the pit; a base cell apart is the pump; the pit's inner edge carries the
## ledge link. Returns {} when the base pad is too small to host it.
func _sump_pocket() -> Dictionary:
	var h := int(_def["h"])
	if BASE_N < 3 or h < 5:
		return {}
	var to_w := func(bx: int, by: int) -> Vector3: return Vector3(
		(float(bx) - BASE_N + 0.5) * CELL, 0.0, (float(by) - h * 0.5 + 0.5) * CELL)
	var pit_a := Vector2i(1, 1)
	var pit_b := Vector2i(2, 1)
	var pump_cell := Vector2i(BASE_N - 1, h - 2)
	var wa: Vector3 = to_w.call(pit_a.x, pit_a.y)
	var wb: Vector3 = to_w.call(pit_b.x, pit_b.y)
	return {
		"pos": (wa + wb) * 0.5 + Vector3(0, 0, -CELL),
		"pump_pos": to_w.call(pump_cell.x, pump_cell.y),
		"pit_min": Vector3(minf(wa.x, wb.x) - CELL * 0.5, 0, minf(wa.z, wb.z) - CELL * 0.5),
		"pit_max": Vector3(maxf(wa.x, wb.x) + CELL * 0.5, 0, maxf(wa.z, wb.z) + CELL * 0.5),
		"pit_cells": [[pit_a.x, pit_a.y], [pit_b.x, pit_b.y]],
		"ledge_cell": [pit_b.x, pit_b.y + 1],
	}

func _build_zone_belt() -> void:
	var h := int(_def["h"])
	var bx_w := (1.0 - BASE_N + 0.5) * CELL
	var a := Vector3(bx_w, 0.0, (1.0 - h * 0.5 + 0.5) * CELL)
	var b := Vector3(bx_w, 0.0, (float(h - 2) - h * 0.5 + 0.5) * CELL)
	var out_x := bx_w - 5.5
	_spawn_belt({"name": "ZoneBelt", "pos": a, "speed": 4.2,
		"waypoints": [Vector3(out_x, 2.2, a.z), Vector3(out_x, 2.2, b.z), b],
		"breaker_pos": Vector3(bx_w + 1.4, 0.0, 0.0),
		"desc": "Ride the zone's derelict supply belt", "label": "RIDE BELT"})

## Every walkable DATA cell world centre (base + doorway + skeleton floor) — the per-cell floor set.
func _walkable_world_cells() -> Array:
	var out: Array = []
	var h := int(_def["h"])
	var mid := h / 2
	var grid: Dictionary = _def["grid"]
	for c in grid.keys():
		var cv := c as Vector2i
		if str(grid[c]) != ChunkGen.SYM_WALL or (cv.x == 0 and absi(cv.y - mid) <= 1):
			out.append(_world(cv))
	for bx in range(1, BASE_N):
		for by in range(1, h - 1):
			out.append(Vector3((bx - BASE_N + 0.5) * CELL, 0.5, (float(by) - h * 0.5 + 0.5) * CELL))
	return out

## The run exit: a click-gated shelter at the END. Resting sets shelter_rested — the roguelike loader
## descend contract (the same key generated_stretch exposes).
func _build_exit_shelter() -> void:
	var end_pos := _world(_def["end"])
	var pad := _add_box(self, end_pos + Vector3(0, 0.1, 0), Vector3(1.2, 0.2, 1.2), Color(0.2, 0.28, 0.22), Color(0.3, 0.7, 0.45), 0.4, "AtomShelterPad")
	var shelter := _add_object_interactable(self, "AtomExitShelter", "Shelter", end_pos + Vector3(0, 0.1, 0),
		"Rest", [pad], "", 0.0, true, 1.2, Interactable.InteractableType.INSPECTION)
	shelter.interacted.connect(_on_shelter_rested)
	# A pad the game calls a shelter must BE one (the attacked-in-the-shelter report): register the
	# sanctuary region the detection/strike gates and the revive watch read. Flat data frame — the
	# hub warp only moves visuals.
	var gs = _get_game_state()
	if gs != null and gs.has_method("add_shelter_region"):
		gs.add_shelter_region(Vector2(end_pos.x - 1.8, end_pos.z - 1.8),
			Vector2(end_pos.x + 1.8, end_pos.z + 1.8))

func _on_shelter_rested() -> void:
	if _shelter_rested:
		return
	_shelter_rested = true
	_phase = "complete"
	_show_note("Rested at the shelter. The descent continues.", 2.5)
	_set_preview_step("atom_shelter_rested")

## Lay the level onto the hub shape: the SAME warp discipline as the generated stretch — data stays flat
## (grid/detection/analytic queries untouched: one truth), every visual child re-seats via to_xform, the
## interactable zones + outline hulls ride warp_interactables_onto_coord_map, and the host installs the
## coord_map so character render + the click inverse run through the same transform. The base cells map to
## the shape flat centre floor (HubShapeCoordMap base region); the chain wraps the perimeter.
func _apply_hub_warp() -> void:
	_coord_map = HubShapeCoordMap.from_grid(get_grid_data(), _hub_shape, 0.0, _descent_per_turn, 0.5, BASE_N)
	for child in get_children():
		if child is Interactable or child is OutlineSurfaceTarget:
			continue   # warp_interactables_onto_coord_map owns these (meta-based, no double-warp)
		if child.has_meta("skip_coord_map_warp"):
			continue   # world-space feedback samples already-warped endpoints directly
		if child.has_method("get_state") and "char_id" in child:
			continue   # enemies render through GameState.get_render_position — already warp-aware
		_warp_child(child)
	warp_interactables_onto_coord_map(_coord_map)

func _warp_child(child: Node) -> void:
	if not (child is Node3D):
		return
	var n3 := child as Node3D
	n3.transform = _coord_map.to_xform(n3.position) * Transform3D(n3.basis, Vector3.ZERO)

func get_coord_map():
	return _coord_map

## A first-time player should not have to pixel-hunt the one object that makes the opening
## gate intelligible. This safe L-shaped breadcrumb stays on the entry floor, through the
## carved doorway, then along open chamber floor to the first flure.
func _build_entry_flure_guide(f_pos: Vector3) -> void:
	var base := Vector3(-BASE_N * CELL * 0.5, 0.08, 0.0)
	var doorway := Vector3(-0.5 * CELL, 0.08, 0.0)
	var chamber_turn := Vector3(f_pos.x, 0.08, 0.0)
	var finish := Vector3(f_pos.x, 0.08, f_pos.z)
	var guide_points: Array[Vector3] = [base, doorway, chamber_turn, finish]
	for segment_index in range(guide_points.size() - 1):
		var from: Vector3 = guide_points[segment_index]
		var to: Vector3 = guide_points[segment_index + 1]
		var steps := maxi(1, ceili(Vector2(to.x - from.x, to.z - from.z).length() / 0.65))
		for dot_index in range(1, steps + 1):
			var dot := from.lerp(to, float(dot_index) / float(steps))
			_add_box(self, dot, Vector3(0.18, 0.05, 0.18), Color(0.5, 0.27, 0.06),
				Color(1.0, 0.48, 0.08), 1.5)
	_add_atom_label("ORANGE DOTS → FIRST FLURE", base + Vector3(0.0, 1.15, 0.0),
		Color(1.0, 0.68, 0.24))

func _build_distract_stage(i: int, gt: Dictionary) -> void:
	var variant := str(gt.get("variant", "lure"))
	var f_cell := Vector2i(-1, -1)
	var c_cell := Vector2i(-1, -1)
	var s_cells: Array = []
	for e in gt.get("elements", []):
		match str(e["sym"]):
			"F": f_cell = e["cell"]
			"c": c_cell = e["cell"]
			"s": s_cells.append(e["cell"])

	var lane_tint := Color(0.32, 0.24, 0.12)
	if variant == "patrol":
		lane_tint = Color(0.14, 0.26, 0.3)     # cool: a beat to read, not a lure to spend
	elif variant == "twin":
		lane_tint = Color(0.3, 0.16, 0.22)     # warning: one of these gaps stays watched
	var lane_meshes: Array[MeshInstance3D] = []
	for lc in gt["cells"]:
		var lane_cell := lc as Vector2i
		var p := _world(lane_cell)
		var cell_tint := lane_tint
		# One flure moves only the first twin watcher. Gold is the linked lane; the red lane
		# remains hot, so the mapping is readable before the player pays for a mistake.
		if variant == "twin" and not s_cells.is_empty():
			cell_tint = Color(0.46, 0.28, 0.12) if absi(lane_cell.y - (s_cells[0] as Vector2i).y) <= 1 else Color(0.32, 0.08, 0.11)
		var lane_mesh := _add_box(self, Vector3(p.x, 0.02, p.z), Vector3(CELL, 0.04, CELL),
			cell_tint, cell_tint.lightened(0.35), 0.45)
		lane_meshes.append(lane_mesh)

	var instruction := "LURE // PERIS TENDS\nFOLLOW THE WATCHER · CROSS"
	var instruction_color := Color(0.95, 0.65, 0.25)
	if variant == "patrol":
		instruction = "PATROL // NO FLURE\nWAIT IN GREEN · CROSS OPPOSITE END"
		instruction_color = Color(0.35, 0.82, 0.95)
	elif variant == "twin":
		instruction = "TWIN WATCH\nFLURE CLEARS GOLD GAP ONLY"
		instruction_color = Color(0.95, 0.48, 0.32)
	_add_atom_label("%02d  %s" % [i + 1, instruction],
		_world(gt["mechanism"]) + Vector3(0.0, 2.15, 0.0), instruction_color)

	var conceal_world := Vector3.INF
	var patrol_source: Marker3D = null
	# Only the patrol pocket is a place the player should deliberately wait. The generated
	# lure/twin pockets sit across the watcher's transit band; painting those green taught a trap.
	if c_cell.x >= 0 and variant == "patrol":
		conceal_world = _world(c_cell)
		_add_box(self, Vector3(conceal_world.x, 0.025, conceal_world.z), Vector3(CELL, 0.05, CELL),
			Color(0.08, 0.28, 0.18), Color(0.18, 0.85, 0.46), 0.55)
		_add_atom_label("WAIT HERE\nCROSS AT CYAN BEAT", conceal_world + Vector3(0.0, 1.0, 0.0), Color(0.42, 0.95, 0.62))
		patrol_source = Marker3D.new()
		patrol_source.name = "PatrolWaitSource%d" % i
		patrol_source.position = conceal_world
		add_child(patrol_source)
	var st := {"idx": i, "variant": variant, "sentries": [], "flure_mesh": null,
		"flure_label": null, "flure_interactable": null, "conceal_world": conceal_world,
		"patrol_source": patrol_source, "patrol_target": null, "causal_link": null,
		"lure_until": -1.0,
		"returning": false, "settle": Vector3.INF, "lure_ready": false,
		"lane_meshes": lane_meshes, "cleared": false, "spotted": false,
		"warning_shown": false, "patrol_far": Vector3.INF, "patrol_ready": false,
		"focus_seen": false}
	# The flure (lure + twin variants): a real TIMED_ACTION tend. Patrol has NO object — the beat is the gate.
	if f_cell.x >= 0 and variant != "patrol":
		var f_pos := _world(f_cell)
		var flure_pad := _add_box(self, Vector3(f_pos.x, 0.035, f_pos.z),
			Vector3(1.25, 0.07, 1.25), Color(0.32, 0.2, 0.07), Color(1.0, 0.5, 0.08), 1.1)
		var mesh := _add_box(self, f_pos + Vector3(0, 0.7, 0), Vector3(0.65, 1.4, 0.65),
			Color(0.7, 0.45, 0.15), Color(1.0, 0.42, 0.08), 1.2, "AtomFlureMesh%d" % i)
		var beacon := _add_box(self, f_pos + Vector3(0, 1.7, 0), Vector3(0.16, 0.75, 0.16),
			Color(0.85, 0.48, 0.1), Color(1.0, 0.58, 0.12), 2.0)
		var flure_label := _add_atom_label("TEND FLURE\nPERIS · %.0fs" % FLURE_TEND,
			f_pos + Vector3(0.0, 2.35, 0.0), Color(1.0, 0.72, 0.3))
		var flure := _add_object_interactable(self, "AtomFlure%d" % i, "Flure", f_pos + Vector3(0, 0.5, 0),
			"Tend", [flure_pad, mesh, beacon], "peris", FLURE_TEND, false, FLURE_PICK_RADIUS,
			Interactable.InteractableType.TIMED_ACTION)
		flure.interacted.connect(func() -> void: activate_lure(i))
		st["flure_mesh"] = mesh
		st["flure_label"] = flure_label
		st["flure_interactable"] = flure
		if i == 0:
			_build_entry_flure_guide(f_pos)
		# The lured sentry parks two cells INTERIOR of the flure pocket (toward the chamber center):
		# clear of the tender standing at it (3.0wu > the 0.4x distracted reach) and off the retreat
		# diagonals. Direction matters — the pocket flips N/S by seed, and a fixed "south" offset from a
		# SOUTH pocket lands outside the room; the move then snaps back beside the flure and the lured
		# sentry parks on top of the tender (found by the analytic playtest on a flipped seed).
		var interior := -1.0 if f_pos.z > 0.0 else 1.0
		st["settle"] = f_pos + Vector3(0.0, 0.5, interior * 2.0 * CELL)
	# Sentries. The FIRST is the lure target (twin's north watcher); a patrol sentry walks its beat.
	var gs = _get_game_state()
	for k in range(s_cells.size()):
		var post := _world(s_cells[k]) + Vector3(0, 0.5, 0)
		var enemy := EnemyScript.new()
		enemy.name = "AtomSentry%d_%d" % [i, k]
		enemy.position = post
		enemy.display_name = "Atom Watcher"
		enemy.color = Color(0.7, 0.28, 0.12) if variant != "patrol" else Color(0.16, 0.58, 0.72)
		if variant == "twin" and k > 0:
			enemy.color = Color(0.72, 0.1, 0.18)
		enemy.move_speed = PATROL_SPEED if variant == "patrol" else SENTRY_SPEED
		enemy.pursuit_speed = SENTRY_SPEED
		enemy.alert_duration = SENTRY_ALERT_DURATION
		enemy.detection_range = SENTRY_RANGE
		enemy._detection_targets.assign(PARTY_IDS)
		add_child(enemy)
		var cid := "atom_sentry_%d" % i if k == 0 else "atom_sentry_%d_%d" % [i, k]
		enemy.char_id = cid
		var waypoints: Array[Vector3] = []
		if variant == "patrol" and gt.has("patrol_far"):
			waypoints = [post, _world(gt["patrol_far"]) + Vector3(0, 0.5, 0)]
			var far_marker: Vector3 = waypoints[1]
			st["patrol_far"] = far_marker
			var patrol_target := Marker3D.new()
			patrol_target.name = "PatrolFarTarget%d" % i
			patrol_target.position = far_marker
			add_child(patrol_target)
			st["patrol_target"] = patrol_target
			_add_box(self, far_marker - Vector3(0.0, 0.46, 0.0), Vector3(0.7, 0.06, 0.7),
				Color(0.12, 0.34, 0.42), Color(0.25, 0.9, 1.0), 0.8)
			_add_atom_label("BEAT LIMIT", far_marker + Vector3(0.0, 0.75, 0.0), Color(0.4, 0.9, 1.0))
		if gs != null:
			enemy.game_state = gs
			gs.register_character(cid, post, enemy.move_speed, {"detection_range": SENTRY_RANGE})
			enemy.activate()
			# NOTE: a patrol sentry's beat is armed in reset_preview_state, not here — the host installs
			# the navigation grid AFTER the chunk builds, and patrol pathfinds on it.
			enemy.target_spotted.connect(_on_spotted.bind(i))
		(st["sentries"] as Array).append({"cid": cid, "enemy": enemy, "post": post, "waypoints": waypoints})
	_build_stage_causal_feedback(st)
	_stages.append(st)


## One relationship language for both atom reads:
## - flure -> the ONE watcher it moves (gold in the twin; never the red watcher)
## - green wait pad -> the cyan patrol endpoint that defines the safe beat
func _build_stage_causal_feedback(st: Dictionary) -> void:
	var variant := str(st["variant"])
	if variant == "patrol":
		var wait_source := st.get("patrol_source", null) as Node3D
		var far_target := st.get("patrol_target", null) as Node3D
		if wait_source != null and far_target != null:
			st["causal_link"] = _add_causal_feedback_link(wait_source, far_target,
				Color(0.29, 0.62, 1.0), {
					"name": "PatrolTimingLink%d" % int(st["idx"]),
					"owner_character": "aster",
					"label": "WAIT UNTIL WATCHER REACHES CYAN",
					"source_offset": Vector3(0.0, 0.18, 0.0),
					"target_offset": Vector3(0.0, 0.18, 0.0),
					"arc_height": 0.45,
				})
		return

	var flure := st.get("flure_interactable", null) as Node3D
	var sentries := st["sentries"] as Array
	if flure == null or sentries.is_empty():
		return
	var lead: Dictionary = sentries[0]
	var watcher := lead.get("enemy", null) as Node3D
	if watcher == null:
		return
	var watcher_meshes: Array = []
	for child in watcher.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			watcher_meshes.append(child)
	var watcher_outline: Node3D = null
	# Screen-space mask copies are presentation-only and expensive under the dummy renderer;
	# keep headless playthroughs purely logical while display builds retain the strong endpoint read.
	if DisplayServer.get_name() != "headless":
		watcher_outline = _outline_object(self, "AtomWatcherEffectOutline%d" % int(st["idx"]),
			watcher_meshes, "atom_watcher_%d" % int(st["idx"]), 1.25, {
				"hover_enabled": false,
				"outline_particles_enabled": false,
				"hover_object_outline_width": 0.018,
			})
	st["causal_link"] = _add_causal_feedback_link(flure, watcher, Color(1.0, 0.67, 0.27), {
		"name": "FlureWatcherLink%d" % int(st["idx"]),
		"owner_character": "peris",
		"visibility_policy": "hover_only",
		"label": "",
		"show_label": false,
		"path_style": "movement_chevrons",
		# The flure remains the logical/hover source, but the spatial read answers the
		# useful player question: where will this watcher move? Flow watcher -> flure.
		"reverse_visual_direction": true,
		"flow_speed": 0.18,
		"draw_duration": 0.55,
		"dash_count": 11,
		"source_offset": Vector3(0.0, 0.28, 0.0),
		"target_offset": Vector3(0.0, 0.28, 0.0),
		"arc_height": 0.18,
		"target_highlight": watcher_outline,
	})


func _stage_feedback_source(st: Dictionary) -> Node:
	var flure = st.get("flure_interactable", null)
	if flure is Node:
		return flure
	var patrol_source = st.get("patrol_source", null)
	return patrol_source if patrol_source is Node else null

## The roguelike reload frees this chunk while the preview's SCHEDULER lives on — every self-re-arming
## callback (the win poll) and pending stage tag must be cancelled here or they fire on a freed instance.
func _exit_tree() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("atom_win")
	for st in _stages:
		var i := int(st["idx"])
		sched.cancel_tag("atom_lure_%d" % i)
		sched.cancel_tag("atom_catch_%d" % i)

func _ready_arrival_hook() -> void:
	var gs = _get_game_state()
	if gs != null and not gs.character_arrived.is_connected(_on_character_arrived):
		gs.character_arrived.connect(_on_character_arrived)

func _world(c: Vector2i) -> Vector3:
	var h := int(_def["h"])
	return Vector3((c.x + 0.5) * CELL, 0.5, (float(c.y) - h * 0.5 + 0.5) * CELL)

## The grid IS the skeleton: walls are WALL tiles (non-walkable AND opaque), so movement and the sentries'
## sightlines agree with the graded sketch by construction.
func get_grid_data() -> Dictionary:
	var w := int(_def["w"])
	var h := int(_def["h"])
	var mid := h / 2
	var cells: Array = []
	var grid: Dictionary = _def["grid"]
	for c in grid.keys():
		var cv := c as Vector2i
		var is_door: bool = cv.x == 0 and absi(cv.y - mid) <= 1
		if str(grid[c]) != ChunkGen.SYM_WALL or is_door:
			cells.append([cv.x + BASE_N, cv.y])
	# The base pad (west of the doorway): the run entry floor. Index space shifts +BASE_N; the origin
	# shifts west the same amount, so skeleton WORLD positions are unchanged (one authoring frame).
	for bx in range(1, BASE_N):
		for by in range(1, h - 1):
			cells.append([bx, by])
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [-BASE_N * CELL, 0.0, -h * 0.5 * CELL],
		"cell_size": CELL,
		"width": w + BASE_N,
		"height": h,
		"walkable_cells": cells,
	}

# --- The puzzle: lure, cross, catch (all real) -------------------------------------------------------------------

## The lure target is always the stage's FIRST sentry (twin's north watcher — the south one is never lured;
## crossing its gap stays a catch, which is the twin's whole lesson).
func activate_lure(i: int) -> bool:
	var st: Dictionary = _stages[i]
	if st["flure_mesh"] == null:
		return false
	var now := _get_scheduler_tick()
	if _phase == "complete" or float(st["lure_until"]) > now or bool(st["returning"]):
		return false
	_phase = "active"
	st["lure_until"] = now + LURE_DURATION
	st["lure_ready"] = false
	st["warning_shown"] = false
	_set_emission(st["flure_mesh"], 3.0)
	_set_stage_lane_emission(st, 0.75)
	var feedback_source := _stage_feedback_source(st)
	_set_causal_feedback_mode(feedback_source, "active")
	_set_causal_feedback_latched(feedback_source, true)
	_flash_causal_feedback(feedback_source, 1.8, 1.45)
	var gs = _get_game_state()
	var target: Dictionary = (st["sentries"] as Array)[0]
	var enemy = target["enemy"]
	if enemy != null and is_instance_valid(enemy) and gs != null and gs.characters.has(str(target["cid"])):
		enemy._current_target_id = ""
		if enemy.has_method("_change_state"):
			enemy._change_state("idle")
		gs.set_character_distracted(str(target["cid"]), true)
		gs.command_move_to_pos(str(target["cid"]), st["settle"])
	if not bool(st["focus_seen"]):
		st["focus_seen"] = true
		if enemy is Node3D:
			_request_preview_focus(enemy, 0.95, true, {
				"offscreen_only": true,
				"shake": 0.13,
				"focus_height": 0.65,
			})
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("atom_lure_%d" % i)
		sched.schedule_after(LURE_DURATION, func() -> void: _on_lure_expired(i), "atom_lure_%d" % i)
	_show_gate_cue("WATCHER TURNING — hold by the flure until the linked lane glows.", 2.4)
	return true

func _on_lure_expired(i: int) -> void:
	var st: Dictionary = _stages[i]
	st["lure_until"] = -1.0
	st["lure_ready"] = false
	st["warning_shown"] = false
	_set_emission(st["flure_mesh"], 0.5)
	_set_stage_lane_emission(st, 0.45)
	_set_causal_feedback_mode(_stage_feedback_source(st), "predicted")
	_set_causal_feedback_latched(_stage_feedback_source(st), false)
	var gs = _get_game_state()
	var target: Dictionary = (st["sentries"] as Array)[0]
	var enemy = target["enemy"]
	if enemy != null and is_instance_valid(enemy) and enemy.is_alive() and gs != null and gs.characters.has(str(target["cid"])):
		# Walk home still DISTRACTED — full watch resumes only when it ARRIVES at the post (the expiry
		# insta-spot fix the built Watched Gap proved).
		st["returning"] = true
		if enemy.has_method("_change_state"):
			enemy._change_state("idle")
		gs.command_move_to_pos(str(target["cid"]), target["post"])
	_show_gate_cue("Stage %d watch is returning." % (i + 1), 2.0)

func _on_character_arrived(id: String) -> void:
	for st in _stages:
		if not bool(st["returning"]):
			continue
		var target: Dictionary = (st["sentries"] as Array)[0]
		if str(target["cid"]) == id:
			st["returning"] = false
			var gs = _get_game_state()
			if gs != null and gs.characters.has(id):
				gs.set_character_distracted(id, false)
			_show_gate_cue("WATCH RESET — stage %d is ready to retry." % (int(st["idx"]) + 1), 2.0)
			return

## Spotted = the KIT runs (director's correction): the watcher pursues and strikes through its
## own FSM, disengages when it loses you, and returns to its post re-armed. The chunk counts the
## spot and names the stage — P11's "failure costs progress" is guidance realized by engagement
## pressure (and, in the roguelite, by the run's own stakes), never a hard-coded teleport. A
## level that wants a literal sweep-back places a Channel/wash object that embodies it.
func _on_spotted(target_id: String, stage_i: int) -> void:
	if _phase == "complete" or not (target_id in PARTY_IDS):
		return
	_caught_count += 1
	_retry_pending = true
	# bookkeeping: the spotting stage's lure state clears (a hunting sentry is not lured)
	var st: Dictionary = _stages[stage_i]
	st["spotted"] = true
	st["lure_until"] = -1.0
	st["lure_ready"] = false
	st["warning_shown"] = false
	st["patrol_ready"] = false
	st["returning"] = false
	st["cleared"] = false
	_set_emission(st["flure_mesh"], 0.5)
	_set_stage_lane_emission(st, 0.45)
	_set_causal_feedback_mode(_stage_feedback_source(st), "failed")
	_set_causal_feedback_latched(_stage_feedback_source(st), false)
	_flash_causal_feedback(_stage_feedback_source(st), 1.25, 1.8)
	_request_preview_shake(0.22, 6.0)
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("atom_lure_%d" % stage_i)
	var gs = _get_game_state()
	if gs != null:
		for target in (st["sentries"] as Array):
			if gs.characters.has(str(target["cid"])):
				gs.set_character_distracted(str(target["cid"]), false)
	var lesson := "the watcher still covered that line"
	match str(st["variant"]):
		"patrol": lesson = "you crossed beside the patrol; wait for its cyan endpoint"
		"twin": lesson = "the red watcher never moved; only the gold gap clears"
	_show_gate_cue("SPOTTED — %s. RUN back to ENTRY SHELTER; sprint beats this chase." % lesson, 3.6)

func _reset_sentry_to_post(i: int) -> void:
	var st: Dictionary = _stages[i]
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("atom_lure_%d" % i)
	st["lure_until"] = -1.0
	st["lure_ready"] = false
	st["warning_shown"] = false
	st["patrol_ready"] = false
	st["returning"] = false
	st["cleared"] = false
	st["spotted"] = false
	_set_emission(st["flure_mesh"], 0.5)
	_set_stage_lane_emission(st, 0.45)
	_set_causal_feedback_mode(_stage_feedback_source(st), "predicted")
	_set_causal_feedback_latched(_stage_feedback_source(st), false)
	var gs = _get_game_state()
	for target in (st["sentries"] as Array):
		var enemy = target["enemy"]
		if enemy == null or not is_instance_valid(enemy) or gs == null or not gs.characters.has(str(target["cid"])):
			continue
		enemy.re_post(target["post"])
		if not (target["waypoints"] as Array).is_empty():
			enemy.set_patrol(_typed_waypoints(target["waypoints"]))   # a patrol sentry resumes its beat, re-armed

func _typed_waypoints(arr: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in arr:
		out.append(p as Vector3)
	return out

func _set_emission(mesh: MeshInstance3D, energy: float) -> void:
	if mesh != null and mesh.material_override is StandardMaterial3D:
		(mesh.material_override as StandardMaterial3D).emission_energy_multiplier = energy

func _set_stage_lane_emission(st: Dictionary, energy: float) -> void:
	for mesh_v in (st.get("lane_meshes", []) as Array):
		_set_emission(mesh_v as MeshInstance3D, energy)

## The preview's persistent briefing occupies the same top band as the shared HUD message.
## Mirror gate-critical feedback into both surfaces: notes are readable with the briefing open,
## messages are readable when the player hides it with H.
func _show_gate_cue(text: String, duration: float) -> void:
	_show_note(text, duration)
	_show_message(text, duration)

# --- Win poll (fixed scheduler cadence) + conceal pockets (per-frame derived state) ------------------------------

func _start_win_poll() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("atom_win")
	sched.schedule_after(WIN_POLL_INTERVAL, _win_poll_tick, "atom_win")

func _win_poll_tick() -> void:
	if _phase == "complete":
		return
	var gs = _get_game_state()
	if gs != null:
		var end_x := _world(_def["end"]).x - CELL * 0.4
		for cid in PARTY_IDS:
			if gs.characters.has(cid) and _get_character_position(cid).x >= end_x:
				_phase = "complete"
				_show_note("Through every watched gap. The end is yours.", 2.5)
				_set_preview_step("atom_complete")
				return
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(WIN_POLL_INTERVAL, _win_poll_tick, "atom_win")

func _process(_delta: float) -> void:
	_update_stage_signals()
	_update_concealment()
	_update_stage_progress()

func headless_process(_delta: float) -> void:
	_update_stage_signals(false)
	_update_concealment()
	_update_stage_progress(false)

## Live gate language: the generous lure stays generous, but its remaining window and return are
## no longer hidden state. The final three seconds change colour and pulse the key object.
func _update_stage_signals(render_feedback := true) -> void:
	var now := _get_scheduler_tick()
	for st in _stages:
		if str(st["variant"]) == "patrol":
			_update_patrol_signal(st, render_feedback)
			continue
		var label := st["flure_label"] as Label3D
		if render_feedback and label == null:
			continue
		var remaining := float(st["lure_until"]) - now
		if remaining > 0.0:
			if not bool(st["lure_ready"]):
				var gs = _get_game_state()
				var target: Dictionary = (st["sentries"] as Array)[0]
				var cid := str(target["cid"])
				var watcher_pos: Vector3 = gs.get_position(cid) if gs != null and gs.characters.has(cid) else Vector3.INF
				var settle: Vector3 = st["settle"] as Vector3
				var planar_distance := Vector2(watcher_pos.x - settle.x, watcher_pos.z - settle.z).length()
				if watcher_pos != Vector3.INF and planar_distance <= LURE_READY_RADIUS:
					st["lure_ready"] = true
					_set_causal_feedback_mode(_stage_feedback_source(st), "ready")
					if render_feedback:
						_set_stage_lane_emission(st, 2.0)
						_flash_causal_feedback(_stage_feedback_source(st), 1.6, 1.65)
						_request_preview_shake(0.09, 9.0)
						var clear_message := "GOLD GAP CLEAR — RED STAYS HOT. RUN GOLD NOW." \
							if str(st["variant"]) == "twin" else "GAP CLEAR — RUN the glowing linked lane now."
						_show_gate_cue(clear_message, 2.0)
			if bool(st["lure_ready"]) and remaining <= LURE_WARNING_SECONDS:
				_set_causal_feedback_mode(_stage_feedback_source(st), "warning")
			elif bool(st["lure_ready"]):
				_set_causal_feedback_mode(_stage_feedback_source(st), "ready")
			else:
				_set_causal_feedback_mode(_stage_feedback_source(st), "active")
			if not render_feedback:
				continue
			if bool(st["lure_ready"]):
				label.text = "GAP CLEAR  %.0fs\nRUN GLOWING LANE" % ceilf(remaining)
			else:
				label.text = "WATCHER TURNING  %.0fs\nHOLD BY FLURE" % ceilf(remaining)
			if bool(st["lure_ready"]) and remaining <= LURE_WARNING_SECONDS:
				if not bool(st["warning_shown"]):
					st["warning_shown"] = true
					_flash_causal_feedback(_stage_feedback_source(st), 1.0, 1.9)
					_request_preview_shake(0.11, 10.0)
					var warning := "3 SECONDS — gold closes soon; red is still hot." \
						if str(st["variant"]) == "twin" else "3 SECONDS — cross now or retreat; the watch is returning."
					_show_gate_cue(warning, 2.2)
				label.modulate = Color(1.0, 0.28, 0.18)
				_set_emission(st["flure_mesh"], 2.2 + sin(now * 10.0) * 0.8)
				_set_stage_lane_emission(st, 1.6 + sin(now * 10.0) * 0.6)
			else:
				label.modulate = Color(1.0, 0.78, 0.28)
				_set_emission(st["flure_mesh"], 3.0)
		elif not render_feedback:
			continue
		elif bool(st["returning"]):
			label.text = "WATCHER RETURNING\nWAIT FOR RE-POST"
			label.modulate = Color(1.0, 0.36, 0.22)
		else:
			label.text = "TEND FLURE\nPERIS · %.0fs" % FLURE_TEND
			label.modulate = Color(1.0, 0.72, 0.3)

## The patrol is a timing read rather than an interaction. Make the safe beat legible in the
## same language as a lure opening: cyan endpoint reached, lane bright, then run the opposite end.
func _update_patrol_signal(st: Dictionary, render_feedback := true) -> void:
	var gs = _get_game_state()
	var sentries := st["sentries"] as Array
	var far: Vector3 = st["patrol_far"]
	if gs == null or sentries.is_empty() or far == Vector3.INF:
		return
	var waiting := _party_near(st["conceal_world"] as Vector3, CELL * 2.5)
	var feedback_source := _stage_feedback_source(st)
	if render_feedback:
		_set_causal_feedback_latched(feedback_source, waiting)
		_set_causal_feedback_mode(feedback_source, "predicted")
	if render_feedback and waiting and not bool(st["focus_seen"]):
		st["focus_seen"] = true
		var patrol_enemy = (sentries[0] as Dictionary).get("enemy", null)
		if patrol_enemy is Node3D:
			_request_preview_focus(patrol_enemy, 0.9, true, {
				"offscreen_only": true,
				"shake": 0.1,
				"focus_height": 0.65,
			})
	var cid := str((sentries[0] as Dictionary)["cid"])
	if not gs.characters.has(cid):
		return
	var watcher: Vector3 = gs.get_position(cid)
	var distance := Vector2(watcher.x - far.x, watcher.z - far.z).length()
	if distance <= 0.8 and not bool(st["patrol_ready"]):
		st["patrol_ready"] = true
		_set_causal_feedback_mode(feedback_source, "ready")
		if render_feedback:
			_set_stage_lane_emission(st, 2.0)
			_flash_causal_feedback(feedback_source, 1.5, 1.55)
			_request_preview_shake(0.08, 9.0)
			if _party_near(st["conceal_world"] as Vector3, CELL * 2.5):
				_show_gate_cue("PATROL FAR — RUN THE OPPOSITE END NOW.", 2.0)
	elif distance > 1.4 and bool(st["patrol_ready"]):
		st["patrol_ready"] = false
		_set_causal_feedback_mode(feedback_source, "predicted")
		if render_feedback:
			_set_stage_lane_emission(st, 0.45)

func _party_near(point: Vector3, radius: float) -> bool:
	if point == Vector3.INF:
		return false
	var gs = _get_game_state()
	if gs == null:
		return false
	for cid in PARTY_IDS:
		if not gs.characters.has(cid) or gs.is_downed(cid):
			continue
		var pos: Vector3 = gs.get_position(cid)
		if Vector2(pos.x - point.x, pos.z - point.z).length() <= radius:
			return true
	return false

func _update_concealment() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for cid in PARTY_IDS:
		if not gs.characters.has(cid):
			continue
		var pos := _get_character_position(cid)
		var tier: int = GameState.CONCEAL_NONE
		for st in _stages:
			var cw: Vector3 = st["conceal_world"]
			if cw != Vector3.INF and Vector2(pos.x - cw.x, pos.z - cw.z).length() <= CELL * 1.1:
				tier = GameState.CONCEAL_MEDIUM
				break
		var previous := int(gs.get_character_concealment(cid)) if gs.has_method("get_character_concealment") else GameState.CONCEAL_NONE
		gs.set_character_concealment(cid, tier)
		if tier == GameState.CONCEAL_MEDIUM and previous != GameState.CONCEAL_MEDIUM and not _conceal_taught:
			_conceal_taught = true
			_show_gate_cue("CONCEALED — this green pad is safe staging ground. Read the watch, then cross.", 3.2)

## Crossing a gate is a comprehension beat, not just an X coordinate. Confirm it before the
## player can mistake the next chamber for the tail of the same sprint.
func _update_stage_progress(render_feedback := true) -> void:
	var gs = _get_game_state()
	if gs == null or _phase == "complete":
		return
	for st in _stages:
		if bool(st["cleared"]):
			continue
		if bool(st["spotted"]):
			return
		var sentries := st["sentries"] as Array
		if sentries.is_empty():
			continue
		var gate_x := -INF
		for target_v in sentries:
			var target: Dictionary = target_v
			var post: Vector3 = target["post"]
			gate_x = maxf(gate_x, post.x)
		var crossed := false
		for cid in PARTY_IDS:
			if gs.characters.has(cid) and not gs.is_downed(cid) \
					and gs.get_position(cid).x >= gate_x + CELL * 0.75:
				crossed = true
				break
		if not crossed:
			return
		st["cleared"] = true
		var stage_number := int(st["idx"]) + 1
		_set_causal_feedback_mode(_stage_feedback_source(st), "complete")
		# A far RMB/group destination is one command, but a newly revealed gate is a new
		# lesson. Consume the outstanding route at each intermediate checkpoint so the
		# party cannot run into its watcher before the cue can be read.
		if stage_number < _stages.size():
			for cid in PARTY_IDS:
				if gs.characters.has(cid) and not gs.is_downed(cid) and gs.is_moving(cid):
					gs.command_stop(cid)
		if render_feedback:
			_set_causal_feedback_latched(_stage_feedback_source(st), false)
			_flash_causal_feedback(_stage_feedback_source(st), 1.0, 1.35)
			_request_preview_shake(0.1, 8.0)
			var next_read := "Shelter ahead." if stage_number == _stages.size() else "Stop and read the next gate."
			_show_gate_cue("%02d CLEAR — %s" % [stage_number, next_read], 2.4)
		_set_preview_step("atom_stage_%d_clear" % stage_number)
		return

# --- SceneChunk interface ----------------------------------------------------------------------------------------

func get_scene_title() -> String:
	return "Generated Atom: %s" % str(_def.get("title", "chain"))

func get_scene_help() -> String:
	return "LURE: follow orange dots; Peris tends; wait for the lane to glow, then run. PATROL: wait on green until the watcher reaches cyan. TWIN: tend, then run gold — red stays hot. ENTRY SHELTER resets a failed watch. Watchers outrun walking, not sprinting."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	# The party wakes on the BASE (the entry-shelter floor), west of the doorway into chamber 0.
	var s := Vector3(-BASE_N * CELL * 0.5, 0.5, 0.0)
	return {
		"aster": s + Vector3(-0.5, 0.0, -1.0),
		"peris": s + Vector3(0.4, 0.0, 0.0),
		"endo": s + Vector3(-0.5, 0.0, 1.0),
	}

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors["end"] = _world(_def["end"])
	for st in _stages:
		var i := int(st["idx"])
		anchors["flure_%d" % i] = _world(_def["gates"][i]["mechanism"])
		var sentries: Array = st["sentries"]
		for k in range(sentries.size()):
			anchors["post_%d%s" % [i, "" if k == 0 else "_%d" % k]] = sentries[k]["post"]
		if st["conceal_world"] != Vector3.INF:
			anchors["conceal_%d" % i] = st["conceal_world"]
	return anchors

func reset_preview_state() -> void:
	_ready_arrival_hook()
	_phase = "ready"
	_caught_count = 0
	_shelter_rested = false
	_conceal_taught = false
	_retry_pending = false
	var sched = _get_scheduler()
	for st in _stages:
		var i := int(st["idx"])
		if sched != null:
			sched.cancel_tag("atom_lure_%d" % i)
			sched.cancel_tag("atom_catch_%d" % i)
		st["lure_until"] = -1.0
		st["lure_ready"] = false
		st["warning_shown"] = false
		st["patrol_ready"] = false
		st["returning"] = false
		st["cleared"] = false
		st["spotted"] = false
		st["focus_seen"] = false
		_set_emission(st["flure_mesh"], 0.5)
		_set_stage_lane_emission(st, 0.45)
		_set_causal_feedback_mode(_stage_feedback_source(st), "predicted")
		_set_causal_feedback_latched(_stage_feedback_source(st), false)
		var gs = _get_game_state()
		for target in (st["sentries"] as Array):
			if gs != null and gs.characters.has(str(target["cid"])) and is_instance_valid(target["enemy"]):
				target["enemy"].re_post(target["post"])
				if not (target["waypoints"] as Array).is_empty():
					target["enemy"].set_patrol(_typed_waypoints(target["waypoints"]))
	_start_win_poll()
	_set_preview_step("atom_briefing")

func get_preview_state() -> Dictionary:
	var now := _get_scheduler_tick()
	var stages_out: Array = []
	for st in _stages:
		var lead: Dictionary = (st["sentries"] as Array)[0] if not (st["sentries"] as Array).is_empty() else {}
		stages_out.append({
			"variant": str(st["variant"]),
			"cleared": bool(st["cleared"]),
			"spotted": bool(st["spotted"]),
			"lure_active": float(st["lure_until"]) > now,
			"lure_ready": bool(st["lure_ready"]),
			"patrol_ready": bool(st["patrol_ready"]),
			"lure_remaining": maxf(0.0, float(st["lure_until"]) - now),
			"returning": bool(st["returning"]),
			"causal_visible": bool((st["causal_link"] as Node).call("is_feedback_visible")) \
				if st.get("causal_link", null) is Node and is_instance_valid(st["causal_link"]) else false,
			"focus_seen": bool(st["focus_seen"]),
			"sentry_state": lead["enemy"].get_state() if not lead.is_empty() and is_instance_valid(lead["enemy"]) else "",
			"ambient_speed": float(lead["enemy"].move_speed) if not lead.is_empty() and is_instance_valid(lead["enemy"]) else 0.0,
			"pursuit_speed": float(lead["enemy"].get_pursuit_speed()) if not lead.is_empty() and is_instance_valid(lead["enemy"]) else 0.0,
		})
	return {
		"phase": _phase,
		"caught_count": _caught_count,
		"retry_pending": _retry_pending,
		"stages": stages_out,
		"complete": _phase == "complete",
		"shelter_rested": _shelter_rested,
		"hub_shape": str(_hub_shape.get("type", "flat")),
		"skeleton_ok": bool(_card.get("ok", false)),
		"skeleton_card": _card,
		"causal_feedback": get_causal_feedback_state(),
	}
