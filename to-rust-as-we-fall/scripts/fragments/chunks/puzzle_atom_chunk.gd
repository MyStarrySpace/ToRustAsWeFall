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
const SENTRY_SPEED := 4.2
const RACE_SPEED_MIN := 3.35       # every generated return gear beats the fastest 3.2 walk
const RACE_SPEED_MAX := 5.8        # every generated return gear remains beatable by the shared 6.0 RUN
const PATROL_SPEED := 1.2          # patrol variant: a slow, READABLE beat — the look-away window is generous
                                   # (P1: pressure never comes from tighter timing)
const SENTRY_ALERT_DURATION := 0.9 # a fair recognition beat before the faster pursuit engages
const LURE_DURATION := 20.0         # failsafe travel budget; the real crossing window begins at settle
const LURE_RACE_GRACE_SECONDS := 1.0 # one readable input beat after the watcher reaches the flure
const LURE_WARNING_SECONDS := 0.45
const LURE_PATH_CLEARANCE_MARGIN := 0.25 # prevents a correct route grazing the distracted watcher's inner reach
const LANE_FORMATION_OFFSETS: Array[Vector2i] = [
	Vector2i.ZERO,
	Vector2i(0, -1),
	Vector2i(0, 1),
]
const FLURE_TEND := 2.0
const FLURE_PICK_RADIUS := 1.0
const WIN_POLL_INTERVAL := 0.1
const ATOM_RUNTIME_AUTHORITY_VERSION := 5
const ATOM_RUNTIME_AUTHORITY_PREFIX := "runtime:puzzle_atom:"
const SHELTER_REST_PHASES := ["ready", "committing", "rested"]
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
var _exit_shelter_interactable: Node = null
var _district: Dictionary = {}
var _skirt_stats: Dictionary = {}
var _conceal_taught := false
var _zone_setpieces := true
var _retry_pending := false
var _win_poll_next_tick := -1.0
var _restoring_atom_authority := false
var _atom_runtime_baseline: Dictionary = {}
var _shelter_rest_phase := "ready"
var _shelter_rest_members: Array[String] = []
var _shelter_rest_commit_tick := -1.0
var _shelter_rest_commit_day := 0
var _shelter_rest_before_atp: Dictionary = {}

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
	_publish_atom_runtime_authority()
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
	# Rejected shelter attempts must remain retryable. Completion authority disables this only after
	# every conscious party body is physically inside and canonical GameState rest has been accepted.
	_exit_shelter_interactable = _add_object_interactable(self, "AtomExitShelter", "Shelter",
		end_pos + Vector3(0, 0.1, 0), "REST PARTY", [pad], "", 0.0, false, 1.2,
		Interactable.InteractableType.INSPECTION)
	_exit_shelter_interactable.interacted.connect(_on_shelter_rested)
	# A pad the game calls a shelter must BE one (the attacked-in-the-shelter report): register the
	# sanctuary region the detection/strike gates and the revive watch read. Flat data frame — the
	# hub warp only moves visuals.
	var gs = _get_game_state()
	if gs != null and gs.has_method("add_shelter_region"):
		gs.add_shelter_region(Vector2(end_pos.x - 1.8, end_pos.z - 1.8),
			Vector2(end_pos.x + 1.8, end_pos.z + 1.8))

func _on_shelter_rested() -> void:
	if _shelter_rested or _shelter_rest_phase == "committing":
		return
	if not _all_stages_cleared():
		_show_gate_cue("The watched chain is not clear yet.", 2.0)
		return
	var rest_outcome := _preflight_canonical_party_shelter_rest()
	if not bool(rest_outcome.get("complete", false)):
		var blocked: Array = rest_outcome.get("blocked", [])
		var reason := str(blocked[0]) if not blocked.is_empty() else "the party cannot settle yet"
		_show_gate_cue("SHELTER WAITING — %s." % reason, 2.6)
		return
	var rest_members: Array = rest_outcome.get("rest_members", []) as Array
	if rest_members.is_empty():
		_complete_atom_shelter_rest(true)
		_show_note("The full ready party secured the shelter. No recovery charge was needed.", 2.8)
		return
	var gs = _get_game_state()
	_shelter_rest_phase = "committing"
	_shelter_rest_members.assign(rest_members)
	_shelter_rest_commit_tick = _get_scheduler_tick()
	_shelter_rest_commit_day = gs.get_game_day()
	_shelter_rest_before_atp = (
		rest_outcome.get("before_atp", {}) as Dictionary).duplicate(true)
	_apply_exit_shelter_presenter()
	_publish_atom_runtime_authority()
	if not bool(gs.command_party_rest(_shelter_rest_members)):
		_retract_atom_shelter_commit()
		_show_gate_cue("SHELTER WAITING — the atomic party rest was rejected.", 2.6)
		return
	_complete_atom_shelter_rest(true)
	_show_note("The full party settled in; canonical shelter recovery has started.", 2.8)


func _all_stages_cleared() -> bool:
	if _stages.is_empty():
		return false
	for st_v in _stages:
		if not bool((st_v as Dictionary).get("cleared", false)):
			return false
	return true


func _full_conscious_party_at_or_beyond_x(threshold: float) -> bool:
	var gs = _get_game_state()
	if gs == null:
		return false
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id) or gs.is_downed(char_id) \
				or _get_character_position(char_id).x < threshold:
			return false
	return true


## The exit is a shelter region, not an infinitesimal X plane. A legal three-member
## formation occupies the pad's centre and adjacent cells; judging readiness by the
## centre point's X coordinate rejected the trailing formation slot even though that
## character was visibly and authoritatively inside sanctuary. Keep the whole-party
## requirement, but ask the same shelter authority the explicit rest verb uses.
func _full_conscious_party_at_exit_shelter() -> bool:
	var gs = _get_game_state()
	if gs == null:
		return false
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id) or gs.is_downed(char_id) \
				or not gs.is_at_shelter(char_id):
			return false
	return true


## Shelter completion is an atomic party outcome. Preflight the exact GameState rest guards before
## issuing the first paid command, so a rejected third member cannot leave the first two charged.
func _preflight_canonical_party_shelter_rest() -> Dictionary:
	var outcome := {
		"complete": false,
		"rest_members": [],
		"already_full": [],
		"blocked": [],
		"before_atp": {},
	}
	var gs = _get_game_state()
	if gs == null or gs.scheduler == null:
		(outcome["blocked"] as Array).append("shelter authority is unavailable")
		return outcome
	var needs_rest: Array[String] = []
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id):
			(outcome["blocked"] as Array).append("%s is not present" % char_id.capitalize())
			continue
		if gs.is_downed(char_id) or gs.is_knocked_down(char_id):
			(outcome["blocked"] as Array).append("%s must be revived" % char_id.capitalize())
			continue
		if not gs.is_at_shelter(char_id):
			(outcome["blocked"] as Array).append("%s is outside the shelter" % char_id.capitalize())
			continue
		if gs.is_resting(char_id):
			(outcome["blocked"] as Array).append("%s is already resting" % char_id.capitalize())
			continue
		if gs.is_moving(char_id) or gs.is_dodging(char_id) or gs.is_endocytosing(char_id) \
				or gs.is_external_traversal_active(char_id) or gs.is_dragging(char_id) \
				or gs.is_field_restoring(char_id):
			(outcome["blocked"] as Array).append("%s is committed to another action" % char_id.capitalize())
			continue
		var hp_full: bool = gs.get_stat(char_id, "hp") >= gs.get_stat_cap(char_id, "hp")
		var stamina_full: bool = gs.get_stat(char_id, "stamina") \
			>= gs.get_stat_cap(char_id, "stamina")
		var needs_canonical_rest: bool = not hp_full or not stamina_full \
			or gs.get_time_of_day() >= GameState.NIGHT_START
		if not needs_canonical_rest:
			(outcome["already_full"] as Array).append(char_id)
			continue
		if gs.get_stat(char_id, "atp") < 1.0:
			(outcome["blocked"] as Array).append("%s cannot pay one ATP" % char_id.capitalize())
			continue
		needs_rest.append(char_id)
	if not (outcome["blocked"] as Array).is_empty():
		return outcome
	if not needs_rest.is_empty() and not bool(gs.can_party_rest(needs_rest)):
		(outcome["blocked"] as Array).append("the recovery party cannot settle yet")
		return outcome
	for char_id in needs_rest:
		(outcome["before_atp"] as Dictionary)[char_id] = gs.get_stat(char_id, "atp")
	(outcome["rest_members"] as Array).assign(needs_rest)
	outcome["complete"] = true
	return outcome


func _complete_atom_shelter_rest(update_step := false) -> void:
	if _shelter_rested and _shelter_rest_phase == "rested":
		return
	_cancel_atom_shelter_rest_callback()
	_shelter_rest_phase = "rested"
	_shelter_rested = true
	_phase = "complete"
	_clear_atom_shelter_rest_context()
	_apply_exit_shelter_presenter()
	_publish_atom_runtime_authority()
	if update_step:
		_set_preview_step("atom_shelter_rested")


func _retract_atom_shelter_commit() -> void:
	_cancel_atom_shelter_rest_callback()
	_shelter_rest_phase = "ready"
	_clear_atom_shelter_rest_context()
	_apply_exit_shelter_presenter()
	_publish_atom_runtime_authority()


func _clear_atom_shelter_rest_context() -> void:
	_shelter_rest_members.clear()
	_shelter_rest_commit_tick = -1.0
	_shelter_rest_commit_day = 0
	_shelter_rest_before_atp.clear()


func _atom_shelter_rest_tag() -> String:
	return "puzzle_atom_party_rest:%s" % _atom_runtime_authority_key().sha256_text().substr(0, 12)


func _cancel_atom_shelter_rest_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler != null:
		scheduler.cancel_tag(_atom_shelter_rest_tag())


func _arm_atom_shelter_rest_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or _shelter_rest_phase != "committing":
		return
	scheduler.cancel_tag(_atom_shelter_rest_tag())
	scheduler.schedule_at(
		maxf(_get_scheduler_tick(), _shelter_rest_commit_tick),
		_resume_atom_shelter_rest.bind(_shelter_rest_commit_tick),
		_atom_shelter_rest_tag())


func _resume_atom_shelter_rest(expected_tick: float) -> void:
	if _shelter_rest_phase != "committing" \
			or not is_equal_approx(_shelter_rest_commit_tick, expected_tick):
		return
	if _authored_party_rest_effect_matches(
		_shelter_rest_members, _shelter_rest_before_atp, _shelter_rest_commit_day):
		_complete_atom_shelter_rest(true)
		return
	var preflight := _preflight_canonical_party_shelter_rest()
	if not _atom_shelter_preflight_matches_commit(preflight):
		_retract_atom_shelter_commit()
		return
	var gs = _get_game_state()
	if gs != null and bool(gs.command_party_rest(_shelter_rest_members)):
		_complete_atom_shelter_rest(true)
	else:
		_retract_atom_shelter_commit()


func _atom_shelter_preflight_matches_commit(preflight: Dictionary) -> bool:
	var gs = _get_game_state()
	if gs == null or gs.get_game_day() != _shelter_rest_commit_day \
			or not bool(preflight.get("complete", false)) \
			or (preflight.get("rest_members", []) as Array) != _shelter_rest_members:
		return false
	for char_id in _shelter_rest_members:
		if not _shelter_rest_before_atp.has(char_id) \
				or not is_equal_approx(
					gs.get_stat(char_id, "atp"),
					float(_shelter_rest_before_atp[char_id])):
			return false
	return true


func _apply_exit_shelter_presenter() -> void:
	if _exit_shelter_interactable == null or not is_instance_valid(_exit_shelter_interactable):
		return
	_exit_shelter_interactable.set_interaction_enabled(
		not _shelter_rested and _shelter_rest_phase != "committing")

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

	var instruction := "LURE // RALLY GREEN\nWALK PERIS OUT · RUN BACK + ACROSS"
	var instruction_color := Color(0.95, 0.65, 0.25)
	if variant == "patrol":
		instruction = "PATROL // NO FLURE\nWAIT IN GREEN · CROSS OPPOSITE END"
		instruction_color = Color(0.35, 0.82, 0.95)
	elif variant == "twin":
		instruction = "TWIN WATCH // RALLY GOLD\nWALK OUT · RUN BACK + GOLD GAP"
		instruction_color = Color(0.95, 0.48, 0.32)
	_add_atom_label("%02d  %s" % [i + 1, instruction],
		_world(gt["mechanism"]) + Vector3(0.0, 2.15, 0.0), instruction_color)

	var conceal_world := Vector3.INF
	var patrol_source: Marker3D = null
	# The generator's c element is executable launch/regroup ground, not ambient decoration.
	# Lure variants stage the party here, send Peris to the flure and back, then sprint the
	# aligned lane.  Patrol uses the same green language for its safe look-away launch.
	if c_cell.x >= 0:
		conceal_world = _world(c_cell)
		_add_box(self, Vector3(conceal_world.x, 0.025, conceal_world.z), Vector3(CELL, 0.05, CELL),
			Color(0.08, 0.28, 0.18), Color(0.18, 0.85, 0.46), 0.55)
		# The command resolves a real three-body formation, so the affordance must
		# show three physical slots rather than implying everyone should stack on
		# the one c-cell. The orange-edged south slot is Peris's return target;
		# these exact cells are also what the strategy proof grades below.
		for slot_index in range(1, LANE_FORMATION_OFFSETS.size()):
			var slot_offset := LANE_FORMATION_OFFSETS[slot_index]
			var slot_pos := conceal_world + Vector3(slot_offset.x * CELL, 0.0, slot_offset.y * CELL)
			var slot_emission := Color(0.95, 0.55, 0.2) if slot_index == 1 \
				else Color(0.18, 0.85, 0.46)
			_add_box(self, Vector3(slot_pos.x, 0.025, slot_pos.z),
				Vector3(CELL * 0.82, 0.05, CELL * 0.82),
				Color(0.07, 0.23, 0.16), slot_emission, 0.62)
		var launch_label := "RALLY HERE\nPERIS → FLURE → RETURN"
		if variant == "patrol":
			launch_label = "WAIT HERE\nCROSS AT CYAN BEAT"
		elif variant == "twin":
			launch_label = "RALLY GOLD\nPERIS → FLURE → RETURN"
		_add_atom_label(launch_label, conceal_world + Vector3(0.0, 1.0, 0.0), Color(0.42, 0.95, 0.62))
		if variant == "patrol":
			patrol_source = Marker3D.new()
			patrol_source.name = "PatrolWaitSource%d" % i
			patrol_source.position = conceal_world
			add_child(patrol_source)
	var cross_world := Vector3.INF
	var return_waypoint := Vector3.INF
	if not s_cells.is_empty():
		var linked_post_cell := s_cells[0] as Vector2i
		var cross_row := linked_post_cell.y
		if c_cell.x >= 0:
			cross_row = c_cell.y
		# A prepared click should end just beyond this gate, on the same safe lane
		# the launch teaches.  Sending a group to the chain's distant shelter lets
		# later obstacles pull side slots out of the current look-away window.
		cross_world = _world(Vector2i(linked_post_cell.x + 2, cross_row))
		# The watcher retraces the shortest visible route from the flure to its
		# post. A former forced side-wall waypoint made that return so long on
		# some seeds that even walking won, silently deleting the taught race.
		# Keep INF here to select the direct authoritative A* return below.
	var st := {"idx": i, "variant": variant, "sentries": [], "flure_mesh": null,
		"flure_label": null, "flure_interactable": null, "flure": null,
		"accepted_flure_serial": 0, "accepted_flure_trigger_count": 0,
		"conceal_world": conceal_world,
		"cross_world": cross_world,
		"patrol_source": patrol_source, "patrol_target": null, "causal_link": null,
		"lure_until": -1.0, "luring_outbound": false,
		"returning": false, "return_waypoint": return_waypoint, "return_leg": "",
		"settle": Vector3.INF, "lure_ready": false,
		"race_started": false, "race_speed": SENTRY_SPEED,
		"lane_meshes": lane_meshes, "cleared": false, "spotted": false,
		"warning_shown": false, "patrol_far": Vector3.INF, "patrol_ready": false,
		"focus_seen": false}
	# The flure (lure + twin variants): a real TIMED_ACTION tend. Patrol has NO object — the beat is the gate.
	if f_cell.x >= 0 and variant != "patrol":
		var f_pos := _world(f_cell)
		# GridWorld paths travel on the navigation plane while the interactable's authored origin is
		# raised to character/source height. Keep the same exact planar Flure endpoint but give Enemy
		# the physical navigation coordinate it can actually reach; otherwise its body arrives 0.5wu
		# below f_pos and Flure's exact 3D settle receipt correctly refuses to forge an arrival.
		var flure_settle_pos := Vector3(f_pos.x, 0.0, f_pos.z)
		_add_box(self, Vector3(f_pos.x, 0.035, f_pos.z),
			Vector3(1.25, 0.07, 1.25), Color(0.32, 0.2, 0.07), Color(1.0, 0.5, 0.08), 1.1)
		var beacon := _add_box(self, f_pos + Vector3(0, 1.7, 0), Vector3(0.16, 0.75, 0.16),
			Color(0.85, 0.48, 0.1), Color(1.0, 0.58, 0.12), 2.0)
		var flure_label := _add_atom_label("TEND FLURE\nPERIS · %.0fs" % FLURE_TEND,
			f_pos + Vector3(0.0, 2.35, 0.0), Color(1.0, 0.72, 0.3))
		var physical_gs = _get_game_state()
		if physical_gs != null:
			var flure: Flure = Flure.new()
			flure.name = "AtomFlure%d" % i
			var owner := chunk_name if not chunk_name.is_empty() else "puzzle_atom"
			flure.authority_id = "puzzle_atom:%s:%d:%d" % [owner, _config_seed, i]
			flure.configure(physical_gs, f_pos, ["atom_sentry_%d" % i], 64.0,
				FLURE_PICK_RADIUS, Color(1.0, 0.5, 0.08))
			flure.required_character = "peris"
			flure.one_shot = false
			flure.interactable_type = Interactable.InteractableType.TIMED_ACTION
			flure.dwell_time = FLURE_TEND
			flure.description = "Tend stage %d Flure" % (i + 1)
			flure.tutorial_label = "TEND"
			flure.settle_pos = flure_settle_pos
			flure.lure_duration = LURE_DURATION
			flure.window_anchor_mode = Flure.WINDOW_ANCHOR_ALL_TARGETS_SETTLED
			flure.settle_hold_duration = LURE_RACE_GRACE_SECONDS
			flure.set_enemy_resolver(_resolve_atom_sentry)
			flure.flure_activated.connect(_on_physical_atom_flure_activated.bind(i))
			flure.flure_targets_settled.connect(_on_physical_atom_targets_settled.bind(i))
			add_child(flure)
			st["flure"] = flure
			st["flure_interactable"] = flure
		st["flure_mesh"] = beacon
		st["flure_label"] = flure_label
		if i == 0:
			_build_entry_flure_guide(f_pos)
		# The relationship line says the flure draws the watcher, so the physical endpoint must
		# actually be the flure.  The generated green launch pad gives Peris somewhere legible to
		# return before the crossing.  The former unexplained interior parking point sat directly
		# on legal formation routes and made the displayed causal model false.
		st["settle"] = flure_settle_pos
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
			if variant != "patrol" and k == 0:
				enemy.set_lure_return_policy(true, SENTRY_SPEED)
			# NOTE: a patrol sentry's beat is armed in reset_preview_state, not here — the host installs
			# the navigation grid AFTER the chunk builds, and patrol pathfinds on it.
			enemy.target_spotted.connect(_on_spotted.bind(i))
		(st["sentries"] as Array).append({"cid": cid, "enemy": enemy, "post": post, "waypoints": waypoints})
	_build_stage_causal_feedback(st)
	_stages.append(st)


func _resolve_atom_sentry(target_id: String):
	for stage_v in _stages:
		var stage := stage_v as Dictionary
		for target_v in (stage.get("sentries", []) as Array):
			var target := target_v as Dictionary
			if str(target.get("cid", "")) == target_id:
				var enemy = target.get("enemy", null)
				return enemy if enemy != null and is_instance_valid(enemy) else null
	return null


func _on_physical_atom_flure_activated(_pulled: int, stage_i: int) -> void:
	if stage_i < 0 or stage_i >= _stages.size() or _phase == "complete":
		return
	var st := _stages[stage_i] as Dictionary
	var effect := _validated_atom_flure_effect(st)
	if effect.is_empty():
		return
	var serial := int(effect.get("activation_serial", 0))
	var trigger_count := int((effect.get("last_effect", {}) as Dictionary).get(
		"source_trigger_count", 0))
	if serial <= int(st.get("accepted_flure_serial", 0)) \
			or trigger_count <= int(st.get("accepted_flure_trigger_count", 0)):
		return
	st["accepted_flure_serial"] = serial
	st["accepted_flure_trigger_count"] = trigger_count
	_begin_physical_atom_lure(st, effect)


func _on_physical_atom_targets_settled(activation_serial: int, stage_i: int) -> void:
	if stage_i < 0 or stage_i >= _stages.size() or _phase == "complete":
		return
	var st := _stages[stage_i] as Dictionary
	var effect := _validated_atom_flure_effect(st)
	if effect.is_empty() or int(effect.get("activation_serial", 0)) != activation_serial:
		return
	var source_effect: Dictionary = effect.get("last_effect", {})
	var trigger_count := int(source_effect.get("source_trigger_count", 0))
	var accepted_serial := int(st.get("accepted_flure_serial", 0))
	if activation_serial < accepted_serial:
		return
	if activation_serial > accepted_serial:
		if trigger_count <= int(st.get("accepted_flure_trigger_count", 0)):
			return
		st["accepted_flure_serial"] = activation_serial
		st["accepted_flure_trigger_count"] = trigger_count
		_begin_physical_atom_lure(st, effect)
	if activation_serial != int(st.get("accepted_flure_serial", 0)) \
			or str(effect.get("window_anchor", "")) != "settled":
		return
	_mark_physical_atom_lure_ready(st, effect)


func _validated_atom_flure_effect(st: Dictionary) -> Dictionary:
	var source := st.get("flure", null) as Flure
	if source == null:
		return {}
	var effect: Dictionary = source.get_effect_state()
	var source_effect: Dictionary = effect.get("last_effect", {})
	var sentries := st.get("sentries", []) as Array
	if sentries.is_empty():
		return {}
	var target_id := str((sentries[0] as Dictionary).get("cid", ""))
	if str(effect.get("phase", "")) != Flure.PHASE_ACTIVE \
			or int(effect.get("activation_serial", 0)) <= 0 \
			or str(source_effect.get("source_actor", "")) != "peris" \
			or int(source_effect.get("source_trigger_count", 0)) <= 0 \
			or not (source_effect.get("pulled_ids", []) as Array).has(target_id):
		return {}
	return effect


func _begin_physical_atom_lure(st: Dictionary, effect: Dictionary) -> void:
	_phase = "active"
	st["lure_until"] = float(effect.get("end_tick", -1.0))
	st["luring_outbound"] = str(effect.get("window_anchor", "")) != "settled"
	st["lure_ready"] = false
	st["race_started"] = false
	st["returning"] = false
	st["return_leg"] = ""
	st["warning_shown"] = false
	st["spotted"] = false
	_set_emission(st.get("flure_mesh", null), 3.0)
	_set_stage_lane_emission(st, 0.75)
	var feedback_source := _stage_feedback_source(st)
	_set_causal_feedback_mode(feedback_source, "active")
	_set_causal_feedback_latched(feedback_source, true)
	_flash_causal_feedback(feedback_source, 1.8, 1.45)
	if not bool(st.get("focus_seen", false)):
		st["focus_seen"] = true
		var target: Dictionary = (st.get("sentries", []) as Array)[0]
		var enemy = target.get("enemy", null)
		if enemy is Node3D:
			_request_preview_focus(enemy, 0.95, true, {
				"offscreen_only": true,
				"shake": 0.13,
				"focus_height": 0.65,
			})
	_publish_atom_runtime_authority()
	_show_gate_cue(
		"WATCHER TURNING — RUN Peris back to her orange-edged launch slot.", 2.4)


func _mark_physical_atom_lure_ready(st: Dictionary, effect: Dictionary) -> void:
	if bool(st.get("lure_ready", false)) \
			and is_equal_approx(
				float(st.get("lure_until", -1.0)),
				float(effect.get("end_tick", -1.0))):
		return
	st["luring_outbound"] = false
	st["lure_ready"] = true
	st["lure_until"] = float(effect.get("end_tick", -1.0))
	_set_causal_feedback_mode(_stage_feedback_source(st), "ready")
	_set_stage_lane_emission(st, 2.0)
	_flash_causal_feedback(_stage_feedback_source(st), 1.6, 1.65)
	_request_preview_shake(0.09, 9.0)
	var clear_message := "GOLD GAP CLEAR — RED STAYS HOT. RUN GOLD NOW." \
		if str(st["variant"]) == "twin" \
		else "GAP CLEAR — choose RUN, then beat the watcher home."
	_show_gate_cue(clear_message, 2.0)
	_publish_atom_runtime_authority()


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
		sched.cancel_tag("atom_flure_reconcile_%d" % i)
		sched.cancel_tag("atom_catch_%d" % i)

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
func activate_lure(_i: int) -> bool:
	return false


## Derive stage mirrors from the two reusable owners. Flure owns the exact song deadline and Enemy
## owns LURED -> RETURN -> re-post; this function changes only feedback/save mirrors.
func _sync_atom_physical_stage(st: Dictionary, render_feedback := true) -> bool:
	if str(st.get("variant", "")) == "patrol" or bool(st.get("spotted", false)):
		return false
	var source := st.get("flure", null) as Flure
	var sentries := st.get("sentries", []) as Array
	if source == null or sentries.is_empty():
		return false
	var effect: Dictionary = source.get_effect_state()
	var source_active: bool = str(effect.get("phase", "")) \
		in [Flure.PHASE_APPLYING, Flure.PHASE_ACTIVE] \
		and float(effect.get("end_tick", -1.0)) > _get_scheduler_tick()
	var target := sentries[0] as Dictionary
	var enemy = target.get("enemy", null)
	var enemy_state := str(enemy.get_state()) \
		if enemy != null and is_instance_valid(enemy) else ""
	var physical_return: bool = _enemy_is_returning_from_atom_flure(str(
		target.get("cid", "")))
	var changed := false
	if source_active:
		var deadline := float(effect.get("end_tick", -1.0))
		var ready: bool = str(effect.get("window_anchor", "")) == "settled"
		if not is_equal_approx(float(st.get("lure_until", -1.0)), deadline):
			st["lure_until"] = deadline
			changed = true
		if bool(st.get("lure_ready", false)) != ready:
			st["lure_ready"] = ready
			st["luring_outbound"] = not ready
			changed = true
	elif physical_return:
		var race_home := bool(st.get("lure_ready", false)) \
			or bool(st.get("race_started", false))
		var newly_returning := not bool(st.get("returning", false))
		st["lure_until"] = -1.0
		st["luring_outbound"] = false
		st["lure_ready"] = false
		st["returning"] = true
		st["return_leg"] = "post"
		st["race_started"] = race_home
		st["warning_shown"] = false
		changed = changed or newly_returning
		if newly_returning:
			_set_emission(st.get("flure_mesh", null), 0.5)
			_set_stage_lane_emission(st, 1.65 if race_home else 0.45)
			_set_causal_feedback_mode(
				_stage_feedback_source(st), "warning" if race_home else "predicted")
			_set_causal_feedback_latched(_stage_feedback_source(st), false)
			if render_feedback:
				var cue := "WATCHER RACING HOME — RUN the glowing lane and beat it to the gap." \
					if race_home \
					else "Stage %d lure timed out before the watcher settled." \
						% (int(st["idx"]) + 1)
				_show_gate_cue(cue, 2.4)
	elif bool(st.get("returning", false)) and enemy_state != "return":
		st["returning"] = false
		st["return_leg"] = ""
		st["race_started"] = false
		st["lure_until"] = -1.0
		_set_stage_lane_emission(st, 0.45)
		_set_causal_feedback_mode(
			_stage_feedback_source(st),
			"complete" if bool(st.get("cleared", false)) else "predicted")
		if render_feedback:
			_show_gate_cue(
				"WATCH RESET — stage %d is ready to retry." % (int(st["idx"]) + 1),
				2.0)
		changed = true
	elif not source_active and float(st.get("lure_until", -1.0)) >= 0.0:
		st["lure_until"] = -1.0
		st["luring_outbound"] = false
		st["lure_ready"] = false
		changed = true
	return changed


func _enemy_is_returning_from_atom_flure(target_id: String) -> bool:
	var gs = _get_game_state()
	if gs == null or target_id.is_empty() or not gs.has_method("get_world_state"):
		return false
	var raw: Variant = gs.get_world_state("runtime:enemy:%s" % target_id, {})
	if not (raw is Dictionary):
		return false
	var saved := raw as Dictionary
	return str(saved.get("state", "")) == "return" \
		and bool(saved.get("lure_returning_from_song", false))

## Spotted = the KIT runs (director's correction): the watcher pursues and strikes through its
## own FSM, disengages when it loses you, and returns to its post re-armed. The chunk counts the
## spot and names the stage — P11's "failure costs progress" is guidance realized by engagement
## pressure (and, in the roguelite, by the run's own stakes), never a hard-coded teleport. A
## level that wants a literal sweep-back places a Channel/wash object that embodies it.
func _on_spotted(target_id: String, stage_i: int) -> void:
	if _phase == "complete" or not (target_id in PARTY_IDS):
		return
	var st: Dictionary = _stages[stage_i]
	# A stage is one causal experiment. Enemy signals may overlap (especially the twin) or a
	# returning watcher may glimpse the party after they have already crossed its comprehension
	# boundary. Neither is a new failed prediction: count at most one catch until the entry-shelter
	# retry explicitly re-arms the stage, and never revoke a committed clear from behind the player.
	if bool(st["cleared"]) or bool(st["spotted"]):
		return
	_caught_count += 1
	_retry_pending = true
	# bookkeeping: the spotting stage's lure state clears (a hunting sentry is not lured)
	st["spotted"] = true
	st["lure_until"] = -1.0
	st["luring_outbound"] = false
	st["lure_ready"] = false
	st["race_started"] = false
	st["warning_shown"] = false
	st["patrol_ready"] = false
	st["returning"] = false
	st["return_leg"] = ""
	st["cleared"] = false
	_set_emission(st["flure_mesh"], 0.5)
	_set_stage_lane_emission(st, 0.45)
	_set_causal_feedback_mode(_stage_feedback_source(st), "failed")
	_set_causal_feedback_latched(_stage_feedback_source(st), false)
	_flash_causal_feedback(_stage_feedback_source(st), 1.25, 1.8)
	_request_preview_shake(0.22, 6.0)
	var sched = _get_scheduler()
	if sched != null:
		# Enemy emits its spot immediately before entering ALERT. Reconcile the exact Flure receipt
		# one deterministic scheduler beat later, after the physical FSM has broken the song.
		sched.schedule_after(0.000001, _reconcile_spotted_atom_flure.bind(stage_i),
			"atom_flure_reconcile_%d" % stage_i)
	var lesson := "the watcher still covered that line"
	match str(st["variant"]):
		"patrol": lesson = "you crossed beside the patrol; wait for its cyan endpoint"
		"twin": lesson = "the red watcher never moved; only the gold gap clears"
	_show_gate_cue("SPOTTED — %s. RUN back to ENTRY SHELTER; sprint beats this chase." % lesson, 3.6)

	_publish_atom_runtime_authority()


func _reconcile_spotted_atom_flure(stage_i: int) -> void:
	if stage_i < 0 or stage_i >= _stages.size():
		return
	var st := _stages[stage_i] as Dictionary
	var source := st.get("flure", null) as Flure
	if source != null:
		source.reconcile_interrupted_targets()
	_publish_atom_runtime_authority()


func _reset_sentry_to_post(i: int) -> void:
	var st: Dictionary = _stages[i]
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("atom_flure_reconcile_%d" % i)
	var source := st.get("flure", null) as Flure
	if source != null:
		source.reset_flure()
	st["accepted_flure_serial"] = 0
	st["accepted_flure_trigger_count"] = 0
	st["lure_until"] = -1.0
	st["luring_outbound"] = false
	st["lure_ready"] = false
	st["race_started"] = false
	st["warning_shown"] = false
	st["patrol_ready"] = false
	st["returning"] = false
	st["return_leg"] = ""
	st["cleared"] = false
	st["spotted"] = false
	_set_emission(st["flure_mesh"], 0.5)
	_set_stage_lane_emission(st, 0.45)
	_set_causal_feedback_mode(_stage_feedback_source(st), "predicted")
	_set_causal_feedback_latched(_stage_feedback_source(st), false)
	var gs = _get_game_state()
	if gs != null and str(st.get("variant", "")) != "patrol":
		var strategy_metrics := _strategy_stage_metrics(st, gs)
		st["race_speed"] = float(strategy_metrics.get("race_speed", SENTRY_SPEED))
	for target in (st["sentries"] as Array):
		var enemy = target["enemy"]
		if enemy == null or not is_instance_valid(enemy) or gs == null or not gs.characters.has(str(target["cid"])):
			continue
		enemy.set_detection_targets(PARTY_IDS)
		enemy.move_speed = PATROL_SPEED if str(st["variant"]) == "patrol" else SENTRY_SPEED
		if str(target.get("cid", "")) == "atom_sentry_%d" % i \
				and str(st["variant"]) != "patrol":
			enemy.set_lure_return_policy(true, float(st["race_speed"]))
		gs.change_move_speed(str(target["cid"]), enemy.move_speed)
		enemy.re_post(target["post"])
		if not (target["waypoints"] as Array).is_empty():
			enemy.set_patrol(_typed_waypoints(target["waypoints"]))   # a patrol sentry resumes its beat, re-armed

	_publish_atom_runtime_authority()


## Crossing the comprehension boundary retires this watch, not the physical
## watcher. It may visibly finish returning to its post, but it no longer acquires
## bodies already through the gate or turns solved execution into a second chase.
## Enemy owns and serializes this semantic target roster, so save/replay preserve
## the disarm without a scene-only collision toggle.
func _set_stage_watch_armed(st: Dictionary, armed: bool) -> void:
	for target_v in (st.get("sentries", []) as Array):
		var target := target_v as Dictionary
		var enemy = target.get("enemy", null)
		if enemy == null or not is_instance_valid(enemy):
			continue
		if armed:
			enemy.set_detection_targets(PARTY_IDS)
		else:
			enemy.retire_watch_to_post()


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

# --- Spatial authority poll (fixed scheduler cadence) + presentation-derived signals ----------------------------

func _start_win_poll(absolute_tick := -1.0) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("atom_win")
	var now := float(sched.get_current_tick())
	_win_poll_next_tick = float(absolute_tick)
	if _win_poll_next_tick < 0.0:
		_win_poll_next_tick = now + WIN_POLL_INTERVAL
	_win_poll_next_tick = maxf(now + 0.000001, _win_poll_next_tick)
	sched.schedule_at(_win_poll_next_tick, _win_poll_tick, "atom_win")
	_publish_atom_runtime_authority()

func _win_poll_tick() -> void:
	_win_poll_next_tick = -1.0
	if _phase == "complete":
		_publish_atom_runtime_authority()
		return
	# Crossing a comprehension boundary is gameplay authority. Evaluate it on the
	# serialized simulation cadence, never from a render/headless presentation call.
	# The persisted field/tag retain their historical win_poll names for save compatibility.
	_update_stage_progress()
	if _all_stages_cleared() and _full_conscious_party_at_exit_shelter() \
			and _phase != "shelter_ready":
		_phase = "shelter_ready"
		_publish_atom_runtime_authority()
		_show_gate_cue("WHOLE PARTY THROUGH — gather on the shelter pad and rest.", 3.0)
		_set_preview_step("atom_shelter_ready")
	_start_win_poll()

func _process(_delta: float) -> void:
	_update_stage_signals()
	_update_concealment()

func headless_process(_delta: float) -> void:
	_update_stage_signals(false)
	_update_concealment()

## Live gate language: the generous lure stays generous, but its remaining window and return are
## no longer hidden state. The final three seconds change colour and pulse the key object.
func _update_stage_signals(render_feedback := true) -> void:
	var now := _get_scheduler_tick()
	var authority_changed := false
	for st in _stages:
		if str(st["variant"]) == "patrol":
			_update_patrol_signal(st, render_feedback)
			continue
		authority_changed = _sync_atom_physical_stage(st, render_feedback) \
			or authority_changed
		var label := st["flure_label"] as Label3D
		if render_feedback and label == null:
			continue
		var remaining := float(st["lure_until"]) - now
		if remaining > 0.0:
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
				label.text = "WATCHER TURNING  %.0fs\nRETURN TO GREEN" % ceilf(remaining)
			if bool(st["lure_ready"]) and remaining <= LURE_WARNING_SECONDS:
				if not bool(st["warning_shown"]):
					st["warning_shown"] = true
					_flash_causal_feedback(_stage_feedback_source(st), 1.0, 1.9)
					_request_preview_shake(0.11, 10.0)
					var warning := "RACE STARTING — gold only; red stays hot." \
						if str(st["variant"]) == "twin" else "RACE STARTING — RUN the glowing lane."
					_show_gate_cue(warning, 2.2)
				label.modulate = Color(1.0, 0.28, 0.18)
				_set_emission(st["flure_mesh"], 2.2 + sin(now * 10.0) * 0.8)
				_set_stage_lane_emission(st, 1.6 + sin(now * 10.0) * 0.6)
			else:
				label.modulate = Color(1.0, 0.78, 0.28)
				_set_emission(st["flure_mesh"], 3.0)
		elif not render_feedback:
			continue
		elif bool(st["returning"]) and bool(st["race_started"]):
			label.text = "WATCHER RACING HOME · RUN GLOWING LANE"
			label.modulate = Color(1.0, 0.28, 0.18)
		elif bool(st["returning"]):
			label.text = "WATCHER RETURNING\nWAIT FOR RE-POST"
			label.modulate = Color(1.0, 0.36, 0.22)
		else:
			label.text = "TEND FLURE\nPERIS · %.0fs" % FLURE_TEND
			label.modulate = Color(1.0, 0.72, 0.3)
	if authority_changed:
		_publish_atom_runtime_authority()

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

## Crossing a gate is a comprehension beat, not just an X coordinate. This is called only by
## the fixed, saved scheduler poll: rendering and headless presenter calls must never commit it.
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
		# A checkpoint represents the party crossing a causal boundary, not one selected
		# runner abandoning the other bodies behind an already-dismissed watcher.
		if not _full_conscious_party_at_or_beyond_x(gate_x + CELL * 0.75):
			return
		st["cleared"] = true
		_set_stage_watch_armed(st, false)
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
	return "LURE: walk the party onto all three green slots; walk Peris out because setup has no deadline, then RUN her back to the orange-edged slot. When the lane glows, RUN everyone through. PATROL: wait on green until the watcher reaches cyan. TWIN: use the gold launch and gap — red stays hot. Rally the whole conscious party across each checkpoint and into the exit shelter. ENTRY SHELTER resets a failed watch. Watchers outrun walking, not sprinting."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	# The party wakes on the BASE (the entry-shelter floor), west of the doorway into chamber 0.
	var s := Vector3(-BASE_N * CELL * 0.5, 0.0, 0.0)
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
		anchors["settle_%d" % i] = st["settle"]
		if st.get("cross_world", Vector3.INF) != Vector3.INF:
			anchors["cross_%d" % i] = st["cross_world"]
		if st.get("patrol_far", Vector3.INF) != Vector3.INF:
			anchors["patrol_far_%d" % i] = st["patrol_far"]
		var sentries: Array = st["sentries"]
		for k in range(sentries.size()):
			anchors["post_%d%s" % [i, "" if k == 0 else "_%d" % k]] = sentries[k]["post"]
		if st["conceal_world"] != Vector3.INF:
			anchors["conceal_%d" % i] = st["conceal_world"]
			anchors["launch_%d" % i] = st["conceal_world"]
	return anchors

## Machine-readable tuning proof for the lure variants. The deadline is embodied by
## the returning watcher. Its visible return gear is derived from both generated routes,
## then bounded between every party walk and RUN; this keeps the player's prediction
## stable without branching behavior on seed ids.
func get_strategy_contract() -> Dictionary:
	var gs = _get_game_state()
	var stages_out: Array = []
	var all_walk_lose := true
	var all_run_win := true
	var all_paths_clear := true
	var all_speeds_legal := true
	var all_launches_safe := true
	var all_regroups_possible := true
	if gs == null or gs.grid == null:
		return {"ok": false, "reason": "navigation_unavailable", "stages": stages_out}
	for st in _stages:
		if str(st["variant"]) == "patrol":
			continue
		var metrics := _strategy_stage_metrics(st, gs)
		if metrics.is_empty():
			continue
		var walk_loses := bool(metrics["walk_loses"])
		var run_wins := bool(metrics["run_wins"])
		var path_clear := bool(metrics["path_clear"])
		var speed_legal := bool(metrics["speed_legal"])
		var launch_safe := bool(metrics["launch_safe"])
		var regroup_possible := bool(metrics["regroup_possible"])
		all_walk_lose = all_walk_lose and walk_loses
		all_run_win = all_run_win and run_wins
		all_paths_clear = all_paths_clear and path_clear
		all_speeds_legal = all_speeds_legal and speed_legal
		all_launches_safe = all_launches_safe and launch_safe
		all_regroups_possible = all_regroups_possible and regroup_possible
		metrics["index"] = int(st["idx"])
		metrics["variant"] = str(st["variant"])
		stages_out.append(metrics)
	return {
		"ok": all_walk_lose and all_run_win and all_paths_clear and all_speeds_legal \
			and all_launches_safe and all_regroups_possible and not stages_out.is_empty(),
		"walk_loses": all_walk_lose,
		"run_wins": all_run_win,
		"paths_clear": all_paths_clear,
		"speeds_legal": all_speeds_legal,
		"launches_safe": all_launches_safe,
		"regroups_possible": all_regroups_possible,
		"stages": stages_out,
	}

func _strategy_stage_metrics(st: Dictionary, gs) -> Dictionary:
	var sentries := st.get("sentries", []) as Array
	if gs == null or gs.grid == null or sentries.is_empty():
		return {}
	var target: Dictionary = sentries[0]
	var post := target["post"] as Vector3
	var flure := _world(_def["gates"][int(st["idx"])]["mechanism"])
	var launch := st.get("conceal_world", Vector3.INF) as Vector3
	if launch == Vector3.INF:
		return {}
	# Prove the command the player actually issues: three distinct formation routes
	# from the generated green launch through the comprehension boundary.  The old
	# centre-line proof stayed green while Peris's legal side slot crossed the parked
	# watcher, turning a correct model into an unexplained catch.
	var launch_destinations: Array[Vector3] = _lane_formation_destinations(gs, launch)
	var clear_point := st.get("cross_world", Vector3.INF) as Vector3
	if clear_point == Vector3.INF:
		return {}
	var clear_destinations: Array[Vector3] = _lane_formation_destinations(gs, clear_point)
	if launch_destinations.size() != PARTY_IDS.size() or clear_destinations.size() != PARTY_IDS.size():
		return {}
	var settle := st["settle"] as Vector3
	var return_waypoint := st.get("return_waypoint", Vector3.INF) as Vector3
	var watcher_outbound_path: Array[Vector3] = gs.grid.find_path(
		gs.grid.world_to_grid(post), gs.grid.world_to_grid(settle))
	var watcher_outbound_distance := _planar_path_length(post, watcher_outbound_path)
	var watcher_first_return_path: Array[Vector3] = []
	var watcher_final_return_path: Array[Vector3] = []
	var watcher_distance := 0.0
	if return_waypoint == Vector3.INF:
		watcher_final_return_path = gs.grid.find_path(
			gs.grid.world_to_grid(settle), gs.grid.world_to_grid(post))
		watcher_distance = _planar_path_length(settle, watcher_final_return_path)
	else:
		watcher_first_return_path = gs.grid.find_path(
			gs.grid.world_to_grid(settle), gs.grid.world_to_grid(return_waypoint))
		watcher_final_return_path = gs.grid.find_path(
			gs.grid.world_to_grid(return_waypoint), gs.grid.world_to_grid(post))
		watcher_distance = _planar_path_length(settle, watcher_first_return_path) \
			+ _planar_path_length(return_waypoint, watcher_final_return_path)
	var required_clearance := SENTRY_RANGE * GameState.DETECTION_DISTRACTED_FACTOR + LURE_PATH_CLEARANCE_MARGIN
	var player_distances: Array[float] = []
	var player_paths: Array[Array] = []
	var player_boundary_distances: Array[float] = []
	var player_walk_speeds: Array[float] = []
	var player_run_speeds: Array[float] = []
	var player_distance := 0.0
	var path_clearance := INF
	var formation_routes_exist := not watcher_outbound_path.is_empty() \
		and not watcher_final_return_path.is_empty() \
		and (return_waypoint == Vector3.INF or not watcher_first_return_path.is_empty())
	var other_watch_clear := true
	for member_index in range(PARTY_IDS.size()):
		var member_start: Vector3 = launch_destinations[member_index]
		var member_path: Array[Vector3] = gs.grid.find_path(
			gs.grid.world_to_grid(member_start),
			gs.grid.world_to_grid(clear_destinations[member_index]))
		if member_path.is_empty():
			formation_routes_exist = false
		var member_distance := _planar_path_length(member_start, member_path)
		player_distances.append(member_distance)
		player_paths.append(member_path)
		player_distance = maxf(player_distance, member_distance)
		path_clearance = minf(path_clearance,
			_visible_planar_path_clearance(
				gs.grid, st["settle"] as Vector3, member_start, member_path))
		player_boundary_distances.append(_path_distance_to_x_boundary(
			member_start, member_path, post.x + CELL * 0.75))
		player_walk_speeds.append(_get_character_move_speed(PARTY_IDS[member_index], false))
		player_run_speeds.append(_get_character_move_speed(PARTY_IDS[member_index], true))
		# In a twin, the unlinked red watcher never becomes distracted.  The legal
		# gold formation must remain outside its full watch radius as well.
		for other_index in range(1, sentries.size()):
			var other_post: Vector3 = (sentries[other_index] as Dictionary)["post"]
			if _visible_planar_path_clearance(gs.grid, other_post, member_start, member_path) \
					<= SENTRY_RANGE + LURE_PATH_CLEARANCE_MARGIN:
				other_watch_clear = false
	var launch_safe := true
	for launch_pos in launch_destinations:
		for sentry_variant in sentries:
			var sentry_post: Vector3 = (sentry_variant as Dictionary)["post"]
			var launch_distance := Vector2(launch_pos.x - sentry_post.x,
				launch_pos.z - sentry_post.z).length()
			if launch_distance <= SENTRY_RANGE + LURE_PATH_CLEARANCE_MARGIN \
					and gs.grid.has_line_of_sight(sentry_post, launch_pos):
				launch_safe = false
	# Peris must be able to tend and physically rejoin her exact formation slot
	# before the visible return race consumes its short commit beat.  This makes
	# preparation a spatial decision, not an input-speed tax hidden from the proof.
	var peris_index := PARTY_IDS.find("peris")
	var peris_launch: Vector3 = launch_destinations[peris_index]
	var tender_path: Array[Vector3] = gs.grid.find_path(
		gs.grid.world_to_grid(flure), gs.grid.world_to_grid(peris_launch))
	var tender_return_distance := _planar_path_length(flure, tender_path)
	var tender_return_seconds := tender_return_distance / GameState.RUN_SPEED
	# The crossing window starts at the visible causal endpoint.  Proving from a
	# proximity radius would silently grant time the runtime no longer grants.
	var watcher_ready_seconds := watcher_outbound_distance / SENTRY_SPEED
	var regroup_delay := maxf(0.0, tender_return_seconds - watcher_ready_seconds)
	var effective_grace := maxf(0.05, LURE_RACE_GRACE_SECONDS - regroup_delay)
	var regroup_possible := not tender_path.is_empty() \
		and tender_return_seconds < watcher_ready_seconds + LURE_RACE_GRACE_SECONDS
	# The checkpoint requires every conscious body, so the meaningful walk result
	# is the slowest member's actual arrival—not an imaginary formation in which
	# Endo inherits Aster's 3.2 speed. RUN is likewise read from each character's
	# authored runtime speed so the proof and executable party command share truth.
	var walk_seconds := 0.0
	var run_seconds := 0.0
	for member_index in range(player_boundary_distances.size()):
		var boundary_distance := float(player_boundary_distances[member_index])
		walk_seconds = maxf(walk_seconds,
			boundary_distance / maxf(player_walk_speeds[member_index], 0.001))
		run_seconds = maxf(run_seconds,
			boundary_distance / maxf(player_run_speeds[member_index], 0.001))
	# Endpoint timing is insufficient when the two routes cross before the post. Search
	# the legal faster-than-walk/slower-than-run gears against the actual moving paths.
	# This proves the prediction the level teaches: the same prepared route is safe at
	# RUN and falsified at walk speed, including the distracted watcher's reduced bubble.
	var race_tuning := _find_race_gear(gs.grid, settle,
		watcher_first_return_path, watcher_final_return_path,
		launch_destinations, player_paths, post.x + CELL * 0.75, effective_grace,
		player_walk_speeds, player_run_speeds)
	var race_speed := float(race_tuning.get("speed", SENTRY_SPEED))
	var watcher_home_seconds := effective_grace + watcher_distance / race_speed
	var target_home_seconds := lerpf(run_seconds, walk_seconds, 0.62)
	return {
		"player_route_wu": player_distance,
		"formation_route_wu": player_distances,
		"formation_route_count": player_distances.size(),
		"watcher_return_wu": watcher_distance,
		"watcher_outbound_wu": watcher_outbound_distance,
		"path_clearance_wu": path_clearance,
		"required_clearance_wu": required_clearance,
		"tender_return_wu": tender_return_distance,
		"tender_return_seconds": tender_return_seconds,
		"watcher_ready_seconds": watcher_ready_seconds,
		"effective_grace_seconds": effective_grace,
		"walk_seconds": walk_seconds,
		"run_seconds": run_seconds,
		"target_home_seconds": target_home_seconds,
		"watcher_home_seconds": watcher_home_seconds,
		"race_speed": race_speed,
		"walk_loses": bool(race_tuning.get("walk_loses", false)),
		"run_wins": bool(race_tuning.get("run_safe", false)),
		"path_clear": formation_routes_exist and other_watch_clear \
			and path_clearance > required_clearance \
			and bool(race_tuning.get("run_safe", false)),
		"launch_safe": launch_safe,
		"regroup_possible": regroup_possible,
		"speed_legal": race_speed > 3.2 and race_speed < GameState.RUN_SPEED,
	}


## Generated atom chains always progress west-to-east. Three-member party moves
## therefore resolve across Z when the player approaches each launch from the
## preceding comprehension boundary. Encode those visible slots directly in the
## proof: asking the stateful generic resolver while Peris is already at the flure
## could rotate the hypothetical formation and tune a different race from the one
## the player had physically prepared.
func _lane_formation_destinations(gs, center: Vector3) -> Array[Vector3]:
	var destinations: Array[Vector3] = []
	if gs == null or gs.grid == null:
		return destinations
	var center_cell: Vector2i = gs.grid.world_to_grid(center)
	for member_index in range(PARTY_IDS.size()):
		var cell := center_cell + LANE_FORMATION_OFFSETS[member_index]
		var level: int = int(gs.get_character_level(PARTY_IDS[member_index])) \
			if gs.characters.has(PARTY_IDS[member_index]) else 0
		if not gs.grid.is_in_bounds(cell.x, cell.y) \
				or not gs.grid.is_walkable(cell.x, cell.y, {}, {}, level):
			return []
		destinations.append(gs.grid.grid_to_world(cell, level))
	return destinations

func _planar_path_length(start: Vector3, path: Array[Vector3]) -> float:
	var total := 0.0
	var previous := Vector2(start.x, start.z)
	for point in path:
		var current := Vector2(point.x, point.z)
		total += previous.distance_to(current)
		previous = current
	return total

## Minimum distance along a route only while the watcher has the same deterministic
## grid LOS used by Enemy detection. A nearby route behind an opaque wall is not a
## red-watch failure; a corner sample that becomes visible is.
func _visible_planar_path_clearance(grid, point: Vector3, start: Vector3,
		path: Array[Vector3]) -> float:
	if path.is_empty():
		return 0.0
	var closest := INF
	var previous := start
	for path_point in path:
		var current := path_point as Vector3
		var segment_length := Vector2(current.x - previous.x, current.z - previous.z).length()
		var steps := maxi(1, int(ceil(segment_length / (CELL * 0.25))))
		for sample_index in range(steps + 1):
			var sample := previous.lerp(current, float(sample_index) / float(steps))
			if grid.has_line_of_sight(point, sample):
				closest = minf(closest,
					Vector2(point.x - sample.x, point.z - sample.z).length())
		previous = current
	return closest


func _path_distance_to_x_boundary(start: Vector3, path: Array[Vector3], boundary_x: float) -> float:
	if start.x >= boundary_x:
		return 0.0
	var distance := 0.0
	var previous := start
	for path_point in path:
		var current := path_point as Vector3
		var segment_length := Vector2(current.x - previous.x, current.z - previous.z).length()
		if previous.x < boundary_x and current.x >= boundary_x \
				and not is_equal_approx(previous.x, current.x):
			var progress := clampf((boundary_x - previous.x) / (current.x - previous.x), 0.0, 1.0)
			return distance + segment_length * progress
		distance += segment_length
		previous = current
	return INF


func _path_position_at_distance(start: Vector3, path: Array, distance: float) -> Vector3:
	var remaining := maxf(0.0, distance)
	var previous := start
	for path_point in path:
		var current := path_point as Vector3
		var segment_length := Vector2(current.x - previous.x, current.z - previous.z).length()
		if remaining <= segment_length and segment_length > 0.0001:
			return previous.lerp(current, remaining / segment_length)
		remaining -= segment_length
		previous = current
	return previous


func _joined_path(first: Array[Vector3], second: Array[Vector3]) -> Array[Vector3]:
	var joined: Array[Vector3] = []
	joined.append_array(first)
	for point in second:
		if joined.is_empty() or not joined.back().is_equal_approx(point):
			joined.append(point)
	return joined


## Return the closest legal watcher gear to the authored pressure speed that
## preserves both halves of the lesson. Sampling at 20 Hz matches the focused
## headless playtest and is finer than the enemy detection cadence.
func _find_race_gear(grid, watcher_start: Vector3,
		watcher_first_path: Array[Vector3], watcher_final_path: Array[Vector3],
		player_starts: Array[Vector3],
		player_paths: Array[Array], boundary_x: float, grace_seconds: float,
		player_walk_speeds: Array[float], player_run_speeds: Array[float]) -> Dictionary:
	var watcher_path := _joined_path(watcher_first_path, watcher_final_path)
	var watcher_distance := _planar_path_length(watcher_start, watcher_path)
	var candidates: Array[float] = []
	var steps := int(ceil((RACE_SPEED_MAX - RACE_SPEED_MIN) / 0.05))
	for gear_index in range(steps + 1):
		candidates.append(minf(RACE_SPEED_MAX, RACE_SPEED_MIN + gear_index * 0.05))
	candidates.sort_custom(func(a: float, b: float) -> bool:
		var delta_a := absf(a - SENTRY_SPEED)
		var delta_b := absf(b - SENTRY_SPEED)
		return a < b if is_equal_approx(delta_a, delta_b) else delta_a < delta_b
	)
	for speed in candidates:
		var run_safe := _race_route_is_safe(grid, watcher_start, watcher_path,
			watcher_distance, float(speed), grace_seconds, player_starts,
			player_paths, boundary_x, player_run_speeds)
		var walk_safe := _race_route_is_safe(grid, watcher_start, watcher_path,
			watcher_distance, float(speed), grace_seconds, player_starts,
			player_paths, boundary_x, player_walk_speeds)
		if run_safe and not walk_safe:
			return {"speed": float(speed), "run_safe": true, "walk_loses": true}
	return {"speed": SENTRY_SPEED, "run_safe": false, "walk_loses": false}


func _race_route_is_safe(grid, watcher_start: Vector3, watcher_path: Array[Vector3],
		watcher_distance: float, watcher_speed: float, grace_seconds: float,
		player_starts: Array[Vector3], player_paths: Array[Array], boundary_x: float,
		player_speeds: Array[float]) -> bool:
	if player_speeds.size() != player_starts.size():
		return false
	var boundary_distances: Array[float] = []
	var finish_seconds := 0.0
	for player_index in range(player_starts.size()):
		var boundary_distance := _path_distance_to_x_boundary(
			player_starts[player_index], player_paths[player_index], boundary_x)
		if is_inf(boundary_distance):
			return false
		boundary_distances.append(boundary_distance)
		finish_seconds = maxf(finish_seconds,
			boundary_distance / maxf(player_speeds[player_index], 0.001))
	var watcher_home_seconds := grace_seconds + watcher_distance / watcher_speed
	var duration := minf(finish_seconds, watcher_home_seconds)
	var sample_count := maxi(1, int(ceil(duration / 0.05)))
	var distracted_range := SENTRY_RANGE * GameState.DETECTION_DISTRACTED_FACTOR
	for sample_index in range(sample_count + 1):
		var elapsed := minf(duration, sample_index * 0.05)
		var watcher_travel := maxf(0.0, elapsed - grace_seconds) * watcher_speed
		var watcher_pos := _path_position_at_distance(watcher_start, watcher_path, watcher_travel)
		for player_index in range(player_starts.size()):
			var player_travel := minf(
				elapsed * player_speeds[player_index], boundary_distances[player_index])
			var player_pos := _path_position_at_distance(
				player_starts[player_index], player_paths[player_index], player_travel)
			if Vector2(watcher_pos.x - player_pos.x, watcher_pos.z - player_pos.z).length() \
					<= distracted_range and grid.has_line_of_sight(watcher_pos, player_pos):
				return false
	# Reaching the post re-arms full detection. If the slowest member has not crossed
	# at that instant, the modeled crossing has lost even without a sampled contact.
	return finish_seconds < watcher_home_seconds


func _atom_runtime_authority_key() -> String:
	var stage_tokens: Array[String] = []
	for stage_v in _config_stages:
		stage_tokens.append(str(stage_v))
	var owner := chunk_name if chunk_name != "" else "puzzle_atom"
	return "%s%s:%d:%s" % [
		ATOM_RUNTIME_AUTHORITY_PREFIX, owner, _config_seed, ",".join(stage_tokens),
	]


func _atom_runtime_authority_state() -> Dictionary:
	var stage_states: Array[Dictionary] = []
	for st_v in _stages:
		var st := st_v as Dictionary
		stage_states.append({
			"index": int(st.get("idx", stage_states.size())),
			"lure_until": float(st.get("lure_until", -1.0)),
			"luring_outbound": bool(st.get("luring_outbound", false)),
			"returning": bool(st.get("returning", false)),
			"return_leg": str(st.get("return_leg", "")),
			"lure_ready": bool(st.get("lure_ready", false)),
			"race_started": bool(st.get("race_started", false)),
			"race_speed": float(st.get("race_speed", SENTRY_SPEED)),
			"accepted_flure_serial": int(st.get("accepted_flure_serial", 0)),
			"accepted_flure_trigger_count": int(
				st.get("accepted_flure_trigger_count", 0)),
			"cleared": bool(st.get("cleared", false)),
			"spotted": bool(st.get("spotted", false)),
			"warning_shown": bool(st.get("warning_shown", false)),
			"patrol_ready": bool(st.get("patrol_ready", false)),
			"focus_seen": bool(st.get("focus_seen", false)),
		})
	return {
		"version": ATOM_RUNTIME_AUTHORITY_VERSION,
		"seed": _config_seed,
		"stage_count": _stages.size(),
		"phase": _phase,
		"caught_count": _caught_count,
		"shelter_rested": _shelter_rested,
		"shelter_rest_phase": _shelter_rest_phase,
		"shelter_rest_members": _shelter_rest_members.duplicate(),
		"shelter_rest_commit_tick": _shelter_rest_commit_tick,
		"shelter_rest_commit_day": _shelter_rest_commit_day,
		"shelter_rest_before_atp": _shelter_rest_before_atp.duplicate(true),
		"conceal_taught": _conceal_taught,
		"retry_pending": _retry_pending,
		"win_poll_next_tick": _win_poll_next_tick,
		"stages": stage_states,
	}


func _publish_atom_runtime_authority() -> void:
	if _restoring_atom_authority:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("set_world_state") or _stages.is_empty():
		return
	gs.set_world_state(_atom_runtime_authority_key(), _atom_runtime_authority_state())


func _normalized_atom_runtime_authority(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	return (raw as Dictionary).duplicate(true)


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_restore_atom_runtime_authority()


func _restore_atom_runtime_authority() -> bool:
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null or not gs.has_method("get_world_state"):
		return false
	for stage_index in range(_stages.size()):
		sched.cancel_tag("atom_flure_reconcile_%d" % stage_index)
		sched.cancel_tag("atom_catch_%d" % stage_index)
	sched.cancel_tag("atom_win")
	sched.cancel_tag(_atom_shelter_rest_tag())
	var saved_v: Variant = gs.get_world_state(_atom_runtime_authority_key(), {})
	var saved := _normalized_atom_runtime_authority(saved_v)
	var saved_stage_values: Variant = saved.get("stages", [])
	if int(saved.get("version", 0)) != ATOM_RUNTIME_AUTHORITY_VERSION \
			or int(saved.get("seed", _config_seed)) != _config_seed \
			or int(saved.get("stage_count", -1)) != _stages.size() \
			or not (saved_stage_values is Array) \
			or (saved_stage_values as Array).size() != _stages.size():
		# A missing record is a snapshot from before this atom began. Reattach the immutable reset
		# baseline; never preserve a later local CLEAR/lure window simply because the old save lacks a key.
		if _atom_runtime_baseline.is_empty():
			push_warning("puzzle_atom_chunk: no reset baseline available for legacy restore")
			return false
		var baseline := _atom_runtime_baseline.duplicate(true)
		baseline["win_poll_next_tick"] = float(sched.get_current_tick()) + WIN_POLL_INTERVAL
		gs.set_world_state(_atom_runtime_authority_key(), baseline)
		return _restore_atom_runtime_authority()

	_restoring_atom_authority = true
	_phase = str(saved.get("phase", "ready"))
	_caught_count = int(saved.get("caught_count", 0))
	_shelter_rested = bool(saved.get("shelter_rested", false))
	_shelter_rest_phase = str(saved.get(
		"shelter_rest_phase", "rested" if _shelter_rested else "ready"))
	if _shelter_rest_phase not in SHELTER_REST_PHASES:
		_shelter_rest_phase = "ready"
	_shelter_rest_members.clear()
	for member_v in saved.get("shelter_rest_members", []) as Array:
		var member_id := str(member_v)
		if member_id != "" and not _shelter_rest_members.has(member_id):
			_shelter_rest_members.append(member_id)
	_shelter_rest_commit_tick = float(saved.get("shelter_rest_commit_tick", -1.0))
	_shelter_rest_commit_day = int(saved.get("shelter_rest_commit_day", 0))
	_shelter_rest_before_atp = (
		saved.get("shelter_rest_before_atp", {}) as Dictionary).duplicate(true)
	if _shelter_rest_phase == "committing" and (
			_shelter_rest_members.is_empty() or _shelter_rest_commit_tick < 0.0
			or _shelter_rest_before_atp.is_empty()):
		_shelter_rest_phase = "ready"
		_clear_atom_shelter_rest_context()
	elif _shelter_rest_phase == "rested":
		_shelter_rested = true
		_phase = "complete"
	_apply_exit_shelter_presenter()
	_conceal_taught = bool(saved.get("conceal_taught", false))
	_retry_pending = bool(saved.get("retry_pending", false))
	var saved_stages: Array = saved_stage_values as Array
	var now := float(sched.get_current_tick())
	for stage_index in range(_stages.size()):
		var st := _stages[stage_index] as Dictionary
		var stage_saved: Dictionary = saved_stages[stage_index] as Dictionary
		st["lure_until"] = float(stage_saved.get("lure_until", -1.0))
		st["luring_outbound"] = bool(stage_saved.get("luring_outbound", false))
		st["returning"] = bool(stage_saved.get("returning", false))
		st["return_leg"] = str(stage_saved.get("return_leg", ""))
		st["lure_ready"] = bool(stage_saved.get("lure_ready", false))
		st["race_started"] = bool(stage_saved.get("race_started", false))
		st["race_speed"] = float(stage_saved.get("race_speed", SENTRY_SPEED))
		st["accepted_flure_serial"] = maxi(
			0, int(stage_saved.get("accepted_flure_serial", 0)))
		st["accepted_flure_trigger_count"] = maxi(
			0, int(stage_saved.get("accepted_flure_trigger_count", 0)))
		st["cleared"] = bool(stage_saved.get("cleared", false))
		st["spotted"] = bool(stage_saved.get("spotted", false))
		st["warning_shown"] = bool(stage_saved.get("warning_shown", false))
		st["patrol_ready"] = bool(stage_saved.get("patrol_ready", false))
		st["focus_seen"] = bool(stage_saved.get("focus_seen", false))
		_sync_atom_physical_stage(st, false)
		_apply_atom_stage_presenter(st, now)
		var source := st.get("flure", null) as Flure
		if bool(st.get("spotted", false)) and source != null \
				and str(source.get_effect_state().get("phase", "")) \
					== Flure.PHASE_ACTIVE:
			sched.schedule_after(
				0.000001,
				_reconcile_spotted_atom_flure.bind(stage_index),
				"atom_flure_reconcile_%d" % stage_index)
	_win_poll_next_tick = float(saved.get("win_poll_next_tick", -1.0))
	if _phase != "complete":
		_start_win_poll(_win_poll_next_tick)
	else:
		_win_poll_next_tick = -1.0
	_restoring_atom_authority = false
	if _shelter_rest_phase == "committing":
		_arm_atom_shelter_rest_callback()
	return true


func _apply_atom_stage_presenter(st: Dictionary, now: float) -> void:
	var feedback_source := _stage_feedback_source(st)
	if bool(st.get("spotted", false)):
		_set_emission(st.get("flure_mesh", null), 0.5)
		_set_stage_lane_emission(st, 0.45)
		_set_causal_feedback_mode(feedback_source, "failed")
		_set_causal_feedback_latched(feedback_source, false)
		return
	if bool(st.get("cleared", false)):
		_set_emission(st.get("flure_mesh", null), 0.5)
		_set_stage_lane_emission(st, 0.45)
		_set_causal_feedback_mode(feedback_source, "complete")
		_set_causal_feedback_latched(feedback_source, false)
		return
	if float(st.get("lure_until", -1.0)) > now:
		var ready := bool(st.get("lure_ready", false))
		_set_emission(st.get("flure_mesh", null), 3.0)
		_set_stage_lane_emission(st, 2.0 if ready else 0.75)
		_set_causal_feedback_mode(feedback_source, "ready" if ready else "active")
		_set_causal_feedback_latched(feedback_source, true)
		return
	if bool(st.get("returning", false)):
		_set_emission(st.get("flure_mesh", null), 0.5)
		_set_stage_lane_emission(st, 1.65 if bool(st.get("race_started", false)) else 0.45)
		_set_causal_feedback_mode(feedback_source,
			"warning" if bool(st.get("race_started", false)) else "predicted")
		_set_causal_feedback_latched(feedback_source, false)
		return
	_set_emission(st.get("flure_mesh", null), 0.5)
	_set_stage_lane_emission(st, 0.45)
	_set_causal_feedback_mode(feedback_source, "predicted")
	_set_causal_feedback_latched(feedback_source, false)

func reset_preview_state() -> void:
	_cancel_atom_shelter_rest_callback()
	_phase = "ready"
	_caught_count = 0
	_shelter_rested = false
	_shelter_rest_phase = "ready"
	_clear_atom_shelter_rest_context()
	_apply_exit_shelter_presenter()
	_conceal_taught = false
	_retry_pending = false
	var sched = _get_scheduler()
	_restoring_atom_authority = true
	for st in _stages:
		var i := int(st["idx"])
		if sched != null:
			sched.cancel_tag("atom_flure_reconcile_%d" % i)
			sched.cancel_tag("atom_catch_%d" % i)
		_reset_sentry_to_post(i)
		st["focus_seen"] = false
	_restoring_atom_authority = false
	_start_win_poll()
	_atom_runtime_baseline = _atom_runtime_authority_state().duplicate(true)
	_publish_atom_runtime_authority()
	_set_preview_step("atom_briefing")

func get_preview_state() -> Dictionary:
	var now := _get_scheduler_tick()
	var stages_out: Array = []
	for st in _stages:
		var lead: Dictionary = (st["sentries"] as Array)[0] if not (st["sentries"] as Array).is_empty() else {}
		var source := st.get("flure", null) as Flure
		var effect: Dictionary = source.get_effect_state() if source != null else {}
		var physical_until := float(effect.get("end_tick", -1.0))
		var physical_active: bool = str(effect.get("phase", "")) \
			in [Flure.PHASE_APPLYING, Flure.PHASE_ACTIVE] \
			and physical_until > now
		var physical_ready: bool = physical_active \
			and str(effect.get("window_anchor", "")) == "settled"
		var target_id := str(lead.get("cid", ""))
		var physical_return: bool = _enemy_is_returning_from_atom_flure(target_id)
		var race_started: bool = physical_return \
			and (bool(st.get("race_started", false)) or bool(st.get("lure_ready", false)))
		stages_out.append({
			"variant": str(st["variant"]),
			"cleared": bool(st["cleared"]),
			"spotted": bool(st["spotted"]),
			"lure_active": physical_active,
			"luring_outbound": physical_active and not physical_ready,
			"lure_ready": physical_ready,
			"race_started": race_started,
			"race_speed": float(st.get("race_speed", SENTRY_SPEED)),
			"return_leg": "post" if physical_return else "",
			"patrol_ready": bool(st["patrol_ready"]),
			"lure_remaining": maxf(0.0, physical_until - now) if physical_active else 0.0,
			"returning": physical_return,
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
		"shelter_rest_phase": _shelter_rest_phase,
		"hub_shape": str(_hub_shape.get("type", "flat")),
		"skeleton_ok": bool(_card.get("ok", false)),
		"skeleton_card": _card,
		"causal_feedback": get_causal_feedback_state(),
	}
