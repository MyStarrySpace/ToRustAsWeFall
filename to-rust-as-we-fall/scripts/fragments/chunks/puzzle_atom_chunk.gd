extends "res://scripts/scene_chunks/scene_chunk.gd"

## GENERATED ATOM — the bridge from a graded ChunkGenerator SKELETON to a REAL walkable room. The chunk takes
## {stages, seed}, regenerates the exact skeleton the report card graded (same seed = same sketch), and builds
## it with REAL mechanics only: real Enemy sentries with LOS-gated detection watching each gap, real flure
## TIMED_ACTION tends, real conceal pockets (CONCEAL_MEDIUM — the Shadow's stage), catch = swept to the START
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
const SENTRY_SPEED := 3.5
const LURE_DURATION := 20.0
const FLURE_TEND := 2.0
const FLURE_PICK_RADIUS := 1.0
const WIN_POLL_INTERVAL := 0.1

var _def: Dictionary = {}          # the regenerated skeleton (graded + built from the SAME data)
var _card: Dictionary = {}         # its principle report card, kept for provenance
var _stages: Array = []            # per gate: {sentry, post, settle, lane_world, flure_cell, conceal_world}
var _phase := "ready"
var _caught_count := 0
var _config_stages: Array = ["distract", "distract"]
var _config_seed := 7

func configure_chunk(config: Dictionary) -> void:
	if config.has("stages"):
		_config_stages = (config["stages"] as Array).duplicate()
	_config_seed = int(config.get("seed", _config_seed))

# --- Build: skeleton -> real room -------------------------------------------------------------------------------

func _build_chunk() -> void:
	_def = ChunkGen.compose(_config_stages, _config_seed)
	_card = ChunkGen.report_card(_def)
	var w := int(_def["w"])
	var h := int(_def["h"])
	# One floor slab under everything (collision, so clicks land).
	_add_floor(self, Vector3(w * CELL * 0.5, -0.05, 0.0), Vector3(w * CELL, 0.1, h * CELL), Color(0.09, 0.1, 0.12))
	# Walls per skeleton cell.
	var grid: Dictionary = _def["grid"]
	for c in grid.keys():
		if str(grid[c]) == ChunkGen.SYM_WALL:
			var p := _world(c)
			_add_box(self, Vector3(p.x, 1.4, p.z), Vector3(CELL, 2.8, CELL), Color(0.06, 0.06, 0.08))
	_add_label(self, "START", _world(_def["start"]) + Vector3(0, 1.8, 0), Color(0.5, 0.8, 0.6))
	_add_label(self, "END", _world(_def["end"]) + Vector3(0, 1.8, 0), Color(0.85, 0.8, 0.5))
	# Stages: refuse anything the bridge can't build for REAL (the honesty ledger at build time).
	var gates: Array = _def["gates"]
	for i in range(gates.size()):
		var gt: Dictionary = gates[i]
		if str(gt["arch"]) != "distract":
			push_error("puzzle_atom_chunk: stage %d archetype '%s' has no REAL bridge build yet — refuse, never fake" % [i, str(gt["arch"])])
			continue
		_build_distract_stage(i, gt)

func _build_distract_stage(i: int, gt: Dictionary) -> void:
	var lane_world: Array = []
	for lc in gt["cells"]:
		var p := _world(lc)
		lane_world.append(p)
		_add_box(self, Vector3(p.x, 0.02, p.z), Vector3(CELL, 0.04, CELL), Color(0.32, 0.24, 0.12))  # watched-lane tint
	var f_cell := Vector2i(-1, -1)
	var c_cell := Vector2i(-1, -1)
	var s_cell := Vector2i(-1, -1)
	for e in gt.get("elements", []):
		match str(e["sym"]):
			"F": f_cell = e["cell"]
			"c": c_cell = e["cell"]
			"s": s_cell = e["cell"]
	var f_pos := _world(f_cell) + Vector3(0, 0.0, 0)
	var mesh := _add_box(self, f_pos + Vector3(0, 0.5, 0), Vector3(0.4, 0.4, 0.4), Color(0.7, 0.45, 0.15), Color(0.8, 0.4, 0.1), 0.5, "AtomFlureMesh%d" % i)
	var flure := _add_object_interactable(self, "AtomFlure%d" % i, "Flure", f_pos + Vector3(0, 0.5, 0),
		"Tend", [mesh], "peris", FLURE_TEND, false, FLURE_PICK_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	flure.interacted.connect(func() -> void: activate_lure(i))
	var conceal_world := Vector3.INF
	if c_cell.x >= 0:
		conceal_world = _world(c_cell)
		_add_box(self, Vector3(conceal_world.x, 0.02, conceal_world.z), Vector3(CELL, 0.04, CELL), Color(0.1, 0.2, 0.16))
	var post := _world(s_cell) + Vector3(0, 0.5, 0)
	# The lured sentry parks two cells SOUTH of the flure: clear of the tender standing at it (outside the
	# 0.4x distracted reach) AND off the north-east retreat diagonal — the east-adjacent settle put the
	# sentry's approach right through the retreat path and caught a correctly retreating tender.
	var settle := f_pos + Vector3(0.0, 0.5, 2.0 * CELL)
	var enemy := EnemyScript.new()
	enemy.name = "AtomSentry%d" % i
	enemy.position = post
	enemy.move_speed = SENTRY_SPEED
	enemy.detection_range = SENTRY_RANGE
	enemy._detection_targets.assign(PARTY_IDS)
	add_child(enemy)
	var cid := "atom_sentry_%d" % i
	enemy.char_id = cid
	var gs = _get_game_state()
	if gs != null:
		enemy.game_state = gs
		gs.register_character(cid, post, SENTRY_SPEED, {"detection_range": SENTRY_RANGE})
		enemy.activate()
		enemy.target_spotted.connect(_on_spotted.bind(i))
		enemy.hit_target.connect(func(tid: String, _dmg: float) -> void: _on_spotted(tid, i))
	_stages.append({"idx": i, "sentry": enemy, "cid": cid, "post": post, "settle": settle,
		"flure_mesh": mesh, "conceal_world": conceal_world, "lure_until": -1.0, "returning": false})

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
	var cells: Array = []
	var grid: Dictionary = _def["grid"]
	for c in grid.keys():
		if str(grid[c]) != ChunkGen.SYM_WALL:
			cells.append([(c as Vector2i).x, (c as Vector2i).y])
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, -h * 0.5 * CELL],
		"cell_size": CELL,
		"width": w,
		"height": h,
		"walkable_cells": cells,
	}

# --- The puzzle: lure, cross, catch (all real) -------------------------------------------------------------------

func activate_lure(i: int) -> bool:
	var st: Dictionary = _stages[i]
	var now := _get_scheduler_tick()
	if _phase == "complete" or float(st["lure_until"]) > now or bool(st["returning"]):
		return false
	_phase = "active"
	st["lure_until"] = now + LURE_DURATION
	_set_emission(st["flure_mesh"], 3.0)
	var gs = _get_game_state()
	var enemy = st["sentry"]
	if enemy != null and is_instance_valid(enemy) and gs != null and gs.characters.has(str(st["cid"])):
		enemy._current_target_id = ""
		if enemy.has_method("_change_state"):
			enemy._change_state("idle")
		gs.set_character_distracted(str(st["cid"]), true)
		gs.command_move_to_pos(str(st["cid"]), st["settle"])
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("atom_lure_%d" % i)
		sched.schedule_after(LURE_DURATION, func() -> void: _on_lure_expired(i), "atom_lure_%d" % i)
	_show_message("The flure sings out. The sentry turns.", 1.4)
	return true

func _on_lure_expired(i: int) -> void:
	var st: Dictionary = _stages[i]
	st["lure_until"] = -1.0
	_set_emission(st["flure_mesh"], 0.5)
	var gs = _get_game_state()
	var enemy = st["sentry"]
	if enemy != null and is_instance_valid(enemy) and enemy.is_alive() and gs != null and gs.characters.has(str(st["cid"])):
		# Walk home still DISTRACTED — full watch resumes only when it ARRIVES at the post (the expiry
		# insta-spot fix the built Watched Gap proved).
		st["returning"] = true
		if enemy.has_method("_change_state"):
			enemy._change_state("idle")
		gs.command_move_to_pos(str(st["cid"]), st["post"])

func _on_character_arrived(id: String) -> void:
	for st in _stages:
		if str(st["cid"]) == id and bool(st["returning"]):
			st["returning"] = false
			var gs = _get_game_state()
			if gs != null and gs.characters.has(id):
				gs.set_character_distracted(id, false)
			return

## Spotted = ONE atomic beat: the member is swept to the START (P11 — the wash takes you to the bottom; here
## the atom's bottom is its start), and THAT sentry re-posts with its whole lure state cleared.
func _on_spotted(target_id: String, stage_i: int) -> void:
	if _phase == "complete" or not (target_id in PARTY_IDS):
		return
	_caught_count += 1
	var gs = _get_game_state()
	if gs != null and gs.characters.has(target_id):
		gs.command_stop(target_id)
		gs.snap_character_to(target_id, get_spawn_positions().get(target_id, _world(_def["start"])))
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("atom_catch_%d" % stage_i)
		sched.schedule_after(0.05, func() -> void: _reset_sentry_to_post(stage_i), "atom_catch_%d" % stage_i)
	_show_note("Spotted in the lane. Escorted back to the start.", 2.2)

func _reset_sentry_to_post(i: int) -> void:
	var st: Dictionary = _stages[i]
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("atom_lure_%d" % i)
	st["lure_until"] = -1.0
	st["returning"] = false
	_set_emission(st["flure_mesh"], 0.5)
	var gs = _get_game_state()
	var enemy = st["sentry"]
	if enemy == null or not is_instance_valid(enemy) or gs == null or not gs.characters.has(str(st["cid"])):
		return
	enemy._current_target_id = ""
	if enemy.has_method("_change_state"):
		enemy._change_state("idle")
	gs.command_stop(str(st["cid"]))
	gs.set_character_distracted(str(st["cid"]), false)
	gs.snap_character_to(str(st["cid"]), st["post"])
	enemy.position = st["post"]

func _set_emission(mesh: MeshInstance3D, energy: float) -> void:
	if mesh != null and mesh.material_override is StandardMaterial3D:
		(mesh.material_override as StandardMaterial3D).emission_energy_multiplier = energy

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
	_update_concealment()

func headless_process(_delta: float) -> void:
	_update_concealment()

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
		gs.set_character_concealment(cid, tier)

# --- SceneChunk interface ----------------------------------------------------------------------------------------

func get_scene_title() -> String:
	return "Generated Atom: %s" % str(_def.get("title", "chain"))

func get_scene_help() -> String:
	return "A GENERATED chain of watched gaps — the graded skeleton, built real. Tend each flure, fall back, cross while the sentry is away."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	var s := _world(_def["start"])
	return {
		"aster": s + Vector3(-0.4, 0.0, -0.9),
		"peris": s,
		"endo": s + Vector3(-0.4, 0.0, 0.9),
	}

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors["end"] = _world(_def["end"])
	for st in _stages:
		var i := int(st["idx"])
		anchors["flure_%d" % i] = _world(_def["gates"][i]["mechanism"])
		anchors["post_%d" % i] = st["post"]
		if st["conceal_world"] != Vector3.INF:
			anchors["conceal_%d" % i] = st["conceal_world"]
	return anchors

func reset_preview_state() -> void:
	_ready_arrival_hook()
	_phase = "ready"
	_caught_count = 0
	var sched = _get_scheduler()
	for st in _stages:
		var i := int(st["idx"])
		if sched != null:
			sched.cancel_tag("atom_lure_%d" % i)
			sched.cancel_tag("atom_catch_%d" % i)
		st["lure_until"] = -1.0
		st["returning"] = false
		_set_emission(st["flure_mesh"], 0.5)
		var gs = _get_game_state()
		if gs != null and gs.characters.has(str(st["cid"])) and is_instance_valid(st["sentry"]):
			gs.set_character_distracted(str(st["cid"]), false)
			gs.snap_character_to(str(st["cid"]), st["post"])
			st["sentry"].position = st["post"]
			if st["sentry"].has_method("_change_state"):
				st["sentry"]._change_state("idle")
	_start_win_poll()
	_set_preview_step("atom_briefing")

func get_preview_state() -> Dictionary:
	var now := _get_scheduler_tick()
	var stages_out: Array = []
	for st in _stages:
		stages_out.append({
			"lure_active": float(st["lure_until"]) > now,
			"returning": bool(st["returning"]),
			"sentry_state": st["sentry"].get_state() if is_instance_valid(st["sentry"]) else "",
		})
	return {
		"phase": _phase,
		"caught_count": _caught_count,
		"stages": stages_out,
		"complete": _phase == "complete",
		"skeleton_ok": bool(_card.get("ok", false)),
		"skeleton_card": _card,
	}
