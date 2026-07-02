extends "res://scripts/scene_chunks/scene_chunk.gd"

## PUMP HALL — a HAND-AUTHORED tactical stealth level. No generation, no archetype scaffolding, no warp:
## a flat tile grid, the game's real systems, designed to be read at a glance and fun to route through.
##
## Three connected spaces, each a different stealth read, with real choices:
##   THE YARD      — an open floor broken by crate islands. A slow sentry paces the exit aisle. Two ways
##                   past: read its beat and cross behind it, or hop the Scarpet patches (medium conceal —
##                   an outer-range pass won't see you there; walking exposed will).
##   THE GALLERY   — a wall with ONE door, and a second sentry pacing the far side. Two tools: time the
##                   door against its beat, or tend the flure in the yard's south corner and pull it
##                   clean off its walk (the lure opens a fat window; the beat is free but tighter).
##   THE PUMP ROOM — machinery in the middle, a third sentry orbiting it. Slip the orbit to the shelter
##                   behind the machines. A Capbage grows in the south-east corner — a tight hide to
##                   break pursuit if it all goes wrong.
##
## Getting spotted means getting ATTACKED: the sentry's real combat cycle (pursuit -> windup -> charge ->
## strike, 25 hp a hit). A member beaten to 0 hp drops WHERE THEY FELL — dead weight, left there until
## retrieved or the party rests. Both ends are true SHELTER ground (engine sanctuary: never spotted,
## never struck, the revive watch runs there) — retreat is always an answer. If the WHOLE party goes
## down, the hall takes the run: everyone restored at the entry, sentries re-posted, from the top.
## All timing rides the scheduler; every obstacle is a visible box.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")

const PARTY_IDS := ["aster", "peris", "endo"]
const CELL := 1.5
const GRID_W := 34
const GRID_H := 22

const SENTRY_RANGE := 4.0
const PATROL_SPEED := 1.2          # slow and READABLE — the beat is the puzzle, never reflexes
const LURE_DURATION := 60.0        # a full minute: the watcher's long west transit (~17s) + waiting out
                                   # S1's beat (up to a whole ~27s cycle) + the door leg all fit with room
                                   # to breathe. Two independent patrol clocks must never force a rushed
                                   # window (P1: pressure is never tighter timing).
const FLURE_TEND := 2.0

# --- The map, in cells (authoring frame: x east, y south; world z = (y - GRID_H/2 + 0.5) * CELL) ---
const CRATES: Array = [            # [x, y, w, h] wall blocks — cover that breaks real sightlines
	[6, 4, 2, 2], [6, 10, 2, 2], [6, 16, 2, 2],      # yard crate islands
	[22, 9, 4, 4],                                    # pump-room machinery block
	[27, 2, 3, 2],                                    # pump-room north pipe bank (flank cover)
]
const GALLERY_X := 13              # the dividing wall (2 cells thick: x 13..14)
const DOOR_Y0 := 10                # the one door through it (rows 10..11)
const DOOR_Y1 := 11

const S1_A := Vector2i(9, 4)       # yard aisle patrol, north <-> south. At x=9 its 4.0 watch reaches only
const S1_B := Vector2i(9, 15)      # to x~11.6 — the band-side corridor (x>=12) and the door mouth are
                                   # PERMANENTLY outside it: S1 gates the yard crossing, the door is S2's
                                   # problem alone (clean layered watches, no accidental overlap). The beat
                                   # ends at y=15 so the flure corner (11,19) stays a safe act.
const S2_A := Vector2i(16, 6)      # gallery watcher, pacing the far side of the door
const S2_B := Vector2i(16, 15)
const S3_ORBIT: Array = [Vector2i(20, 7), Vector2i(27, 7), Vector2i(27, 14), Vector2i(20, 14)]

const SCARPET_PADS: Array = [Vector2i(7, 7), Vector2i(7, 14)]   # medium-conceal hops, 3.0wu off the aisle,
                                                                 # tucked against the crate faces
const FLURE_CELL := Vector2i(4, 19)                              # far south-WEST: the lure point sits on the
const SETTLE_CELL := Vector2i(4, 17)                             # opposite side of the map from the sneak route,
                                                                 # so the lured watcher's transit and park never
                                                                 # touch the door corridor (classic lure design)
const CAPBAGE_CELL := Vector2i(30, 17)
const EXIT_CELL := Vector2i(30, 10)
const HOME_CELL := Vector2i(3, 11)                               # the entry haven (spawn + shelter ground)

var _sentries: Array = []          # [{cid, enemy, post, waypoints}]
var _phase := "ready"
var _spotted_count := 0
var _wipe_count := 0
var _flure_mesh: MeshInstance3D
var _lure_until := -1.0
var _lure_returning := false
var _capbage: Capbage

func _build_chunk() -> void:
	_build_floors_and_walls()
	_build_scarpet_and_capbage()
	_build_flure()
	_build_exit()
	_register_shelter_regions()
	_spawn_sentries()
	_build_lights()

# --- Geometry -----------------------------------------------------------------------------------------

func _cell_world(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.5, (float(c.y) - GRID_H * 0.5 + 0.5) * CELL)

func _is_wall_cell(c: Vector2i) -> bool:
	if c.x <= 0 or c.y <= 0 or c.x >= GRID_W - 1 or c.y >= GRID_H - 1:
		return true
	for r in CRATES:
		if c.x >= int(r[0]) and c.x < int(r[0]) + int(r[2]) and c.y >= int(r[1]) and c.y < int(r[1]) + int(r[3]):
			return true
	if c.x >= GALLERY_X and c.x <= GALLERY_X + 1 and not (c.y >= DOOR_Y0 and c.y <= DOOR_Y1):
		return true
	return false

func _build_floors_and_walls() -> void:
	# Three zone slabs with distinct (subtle) tones so the spaces read as places.
	_add_floor(self, Vector3(GALLERY_X * CELL * 0.5, -0.05, 0.0), Vector3(GALLERY_X * CELL, 0.1, GRID_H * CELL), Color(0.10, 0.11, 0.13))
	_add_floor(self, Vector3((GALLERY_X + 1.0) * CELL, -0.05, 0.0), Vector3(2.0 * CELL, 0.1, GRID_H * CELL), Color(0.08, 0.09, 0.10))
	var pump_w := float(GRID_W - GALLERY_X - 2)
	_add_floor(self, Vector3((GALLERY_X + 2.0 + pump_w * 0.5) * CELL, -0.05, 0.0), Vector3(pump_w * CELL, 0.1, GRID_H * CELL), Color(0.10, 0.10, 0.14))
	# Walls: one visible box per wall cell — nothing can be invisible by construction.
	for y in range(GRID_H):
		for x in range(GRID_W):
			var c := Vector2i(x, y)
			if _is_wall_cell(c):
				var p := _cell_world(c)
				var is_crate := x > 0 and y > 0 and x < GRID_W - 1 and y < GRID_H - 1 and not (x >= GALLERY_X and x <= GALLERY_X + 1)
				# Bright enough to beat the preview's distance fog, with a faint emissive rim so far walls
				# NEVER wash out — an invisible obstacle is a design failure, not a mood.
				var col := Color(0.24, 0.20, 0.15) if is_crate else Color(0.15, 0.15, 0.20)
				var glow := Color(0.35, 0.30, 0.22) if is_crate else Color(0.22, 0.24, 0.34)
				var hgt := 1.6 if is_crate else 2.8
				_add_box(self, Vector3(p.x, hgt * 0.5, p.z), Vector3(CELL, hgt, CELL), col, glow, 0.12)
	# Danger-path tints: a thin amber strip under each sentry's walk — the watch, readable from anywhere.
	_tint_path(S1_A, S1_B)
	_tint_path(S2_A, S2_B)
	for i in range(S3_ORBIT.size()):
		_tint_path(S3_ORBIT[i], S3_ORBIT[(i + 1) % S3_ORBIT.size()])

func _tint_path(a: Vector2i, b: Vector2i) -> void:
	var pa := _cell_world(a)
	var pb := _cell_world(b)
	var mid := (pa + pb) * 0.5
	var size := Vector3(maxf(absf(pb.x - pa.x), CELL * 0.6), 0.03, maxf(absf(pb.z - pa.z), CELL * 0.6))
	_add_box(self, Vector3(mid.x, 0.015, mid.z), size, Color(0.45, 0.30, 0.10), Color(0.5, 0.32, 0.1), 0.25)

func _build_scarpet_and_capbage() -> void:
	for c in SCARPET_PADS:
		var p := _cell_world(c as Vector2i)
		_add_box(self, Vector3(p.x, 0.02, p.z), Vector3(CELL * 1.4, 0.04, CELL * 1.4), Color(0.12, 0.22, 0.14))
		_add_label(self, "scarpet", p + Vector3(0, 0.9, 0), Color(0.45, 0.75, 0.5))
	_capbage = Capbage.new()
	_capbage.configure(_get_game_state(), _cell_world(CAPBAGE_CELL), 1.4)
	add_child(_capbage)

func _build_flure() -> void:
	var p := _cell_world(FLURE_CELL)
	_flure_mesh = _add_box(self, p + Vector3(0, 0.5, 0), Vector3(0.4, 0.4, 0.4), Color(0.7, 0.45, 0.15), Color(0.8, 0.4, 0.1), 0.5, "PumpFlureMesh")
	var flure := _add_object_interactable(self, "PumpFlure", "Flure", p + Vector3(0, 0.5, 0),
		"Tend", [_flure_mesh], "peris", FLURE_TEND, false, 1.0, Interactable.InteractableType.TIMED_ACTION)
	flure.interacted.connect(activate_lure)

func _build_exit() -> void:
	var p := _cell_world(EXIT_CELL)
	var pad := _add_box(self, p + Vector3(0, 0.1, 0), Vector3(1.3, 0.2, 1.3), Color(0.2, 0.28, 0.22), Color(0.3, 0.7, 0.45), 0.5, "PumpShelterPad")
	var shelter := _add_object_interactable(self, "PumpExitShelter", "Shelter", p + Vector3(0, 0.1, 0),
		"Rest", [pad], "", 0.0, true, 1.2, Interactable.InteractableType.INSPECTION)
	shelter.interacted.connect(_on_rested)
	_add_label(self, "SHELTER", p + Vector3(0, 2.0, 0), Color(0.6, 0.9, 0.65))

## Both havens are ENGINE shelter ground — the sanctuary rules (never spotted, never struck, revive
## watch) come from GameState, not from chunk logic. The chunk only declares the WHERE.
func _register_shelter_regions() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var home := _cell_world(HOME_CELL)
	var exit := _cell_world(EXIT_CELL)
	gs.add_shelter_region(Vector2(home.x - 2.4, home.z - 2.4), Vector2(home.x + 2.4, home.z + 2.4))
	gs.add_shelter_region(Vector2(exit.x - 1.8, exit.z - 1.8), Vector2(exit.x + 1.8, exit.z + 1.8))
	var p := _cell_world(HOME_CELL)
	_add_box(self, Vector3(p.x, 0.015, p.z), Vector3(CELL * 1.2, 0.03, CELL * 1.2), Color(0.16, 0.2, 0.18), Color(0.25, 0.5, 0.35), 0.3)
	_add_label(self, "haven", p + Vector3(0, 0.8, 0), Color(0.55, 0.8, 0.65))

func _build_lights() -> void:
	_add_light(self, _cell_world(HOME_CELL) + Vector3(0, 2.2, 0), Color(0.7, 0.8, 0.75), 0.8, 6.0)
	_add_light(self, _cell_world(Vector2i(GALLERY_X, DOOR_Y0)) + Vector3(0, 2.4, 0), Color(0.85, 0.75, 0.55), 1.0, 6.0)
	_add_light(self, _cell_world(Vector2i(23, 10)) + Vector3(0, 3.0, 0), Color(0.6, 0.7, 0.9), 1.0, 8.0)
	_add_light(self, _cell_world(EXIT_CELL) + Vector3(0, 2.2, 0), Color(0.55, 0.9, 0.6), 1.0, 6.0)
	_add_light(self, _cell_world(FLURE_CELL) + Vector3(0, 1.6, 0), Color(0.9, 0.6, 0.3), 0.7, 4.0)

func _spawn_sentries() -> void:
	_add_sentry(0, _cell_world(S1_A), [_cell_world(S1_A), _cell_world(S1_B)])
	_add_sentry(1, _cell_world(S2_A), [_cell_world(S2_A), _cell_world(S2_B)])
	var orbit: Array[Vector3] = []
	for c in S3_ORBIT:
		orbit.append(_cell_world(c as Vector2i))
	_add_sentry(2, orbit[0], orbit)

func _add_sentry(i: int, post: Vector3, waypoints: Array) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var enemy := EnemyScript.new()
	enemy.name = "PumpSentry%d" % i
	enemy.position = post
	enemy.move_speed = PATROL_SPEED
	enemy.detection_range = SENTRY_RANGE
	enemy._detection_targets.assign(PARTY_IDS)
	add_child(enemy)
	var cid := "pump_sentry_%d" % i
	enemy.char_id = cid
	enemy.game_state = gs
	gs.register_character(cid, post, PATROL_SPEED, {"detection_range": SENTRY_RANGE})
	enemy.activate()
	enemy.target_spotted.connect(_on_sentry_spotted)
	var typed: Array[Vector3] = []
	for w in waypoints:
		typed.append(w as Vector3)
	_sentries.append({"cid": cid, "enemy": enemy, "post": post, "waypoints": typed})

## The data grid IS the map: wall cells block movement AND sight (one truth, flat, no warp).
func get_grid_data() -> Dictionary:
	var cells: Array = []
	for y in range(GRID_H):
		for x in range(GRID_W):
			if not _is_wall_cell(Vector2i(x, y)):
				cells.append([x, y])
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, -GRID_H * 0.5 * CELL],
		"cell_size": CELL,
		"width": GRID_W,
		"height": GRID_H,
		"walkable_cells": cells,
	}

# --- The systems, live --------------------------------------------------------------------------------

## The flure pulls S2 (the gallery watcher) off its beat to the yard's south corner — the generous window.
func activate_lure() -> bool:
	var now := _get_scheduler_tick()
	if _phase == "complete" or _lure_until > now or _lure_returning:
		return false
	_lure_until = now + LURE_DURATION
	if _flure_mesh != null and _flure_mesh.material_override is StandardMaterial3D:
		(_flure_mesh.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0
	var st: Dictionary = _sentries[1]
	var gs = _get_game_state()
	var enemy = st["enemy"]
	if is_instance_valid(enemy) and gs != null and gs.characters.has(str(st["cid"])):
		enemy._current_target_id = ""
		if enemy.has_method("_change_state"):
			enemy._change_state("idle")
		gs.set_character_distracted(str(st["cid"]), true)
		gs.command_move_to_pos(str(st["cid"]), _cell_world(SETTLE_CELL))
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("pump_lure")
		sched.schedule_after(LURE_DURATION, _on_lure_expired, "pump_lure")
	_show_message("The flure sings out.", 1.4)
	return true

func _on_lure_expired() -> void:
	_lure_until = -1.0
	if _flure_mesh != null and _flure_mesh.material_override is StandardMaterial3D:
		(_flure_mesh.material_override as StandardMaterial3D).emission_energy_multiplier = 0.5
	var st: Dictionary = _sentries[1]
	var gs = _get_game_state()
	var enemy = st["enemy"]
	if is_instance_valid(enemy) and enemy.is_alive() and gs != null and gs.characters.has(str(st["cid"])):
		# Walks home still distracted; the full watch (and the patrol beat) resume at the post.
		_lure_returning = true
		if enemy.has_method("_change_state"):
			enemy._change_state("idle")
		gs.command_move_to_pos(str(st["cid"]), st["post"])

func _on_character_arrived(id: String) -> void:
	if id != "pump_sentry_1" or not _lure_returning:
		return
	_lure_returning = false
	var gs = _get_game_state()
	var st: Dictionary = _sentries[1]
	if gs != null and gs.characters.has(id):
		gs.set_character_distracted(id, false)
	var enemy = st["enemy"]
	if is_instance_valid(enemy):
		enemy.set_patrol(st["waypoints"])

## Spotted = ATTACKED. The Enemy FSM owns everything that follows (pursuit -> windup -> charge ->
## strike -> disengage-from-a-downed-target -> return to the beat) — the chunk only narrates and counts.
func _on_sentry_spotted(target_id: String) -> void:
	if _phase == "complete" or not (target_id in PARTY_IDS):
		return
	_spotted_count += 1
	_show_note("Spotted. It's coming.", 2.0)

## A member beaten to 0 hp drops where they fell (the engine marks the down + refuses their movement).
## The chunk's only job: notice a FULL wipe and restart the run from the entry.
func _on_character_downed(cid: String) -> void:
	if _phase == "complete" or not (cid in PARTY_IDS):
		return
	_show_note("%s is down. They stay where they fell." % cid.capitalize(), 2.4)
	var gs = _get_game_state()
	if gs != null and gs.is_party_downed(PARTY_IDS):
		_wipe_count += 1
		_show_note("The hall takes everyone. From the top.", 2.6)
		var sched = _get_scheduler()
		if sched != null:
			sched.cancel_tag("pump_restart")
			sched.schedule_after(1.5, _restart_level, "pump_restart")

## Full wipe -> the run restarts from the entry: everyone restored at spawn, sentries re-posted,
## the lure re-armed. Restore + snap are logged commands, so the restart replays.
func _restart_level() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var spawns := get_spawn_positions()
	for cid in PARTY_IDS:
		if not gs.characters.has(cid):
			continue
		gs.restore_character(cid)
		gs.snap_character_to(cid, spawns.get(cid, _cell_world(HOME_CELL)))
	for i in range(_sentries.size()):
		_reset_sentry(i)
	_phase = "ready"
	_set_preview_step("pump_hall_restart")

func _reset_sentry(i: int) -> void:
	var st: Dictionary = _sentries[i]
	var gs = _get_game_state()
	var enemy = st["enemy"]
	if i == 1:
		var sched = _get_scheduler()
		if sched != null:
			sched.cancel_tag("pump_lure")
		_lure_until = -1.0
		_lure_returning = false
		if _flure_mesh != null and _flure_mesh.material_override is StandardMaterial3D:
			(_flure_mesh.material_override as StandardMaterial3D).emission_energy_multiplier = 0.5
	if not is_instance_valid(enemy) or gs == null or not gs.characters.has(str(st["cid"])):
		return
	enemy._current_target_id = ""
	if enemy.has_method("_change_state"):
		enemy._change_state("idle")
	gs.command_stop(str(st["cid"]))
	gs.set_character_distracted(str(st["cid"]), false)
	gs.snap_character_to(str(st["cid"]), st["post"])
	enemy.position = st["post"]
	enemy.set_patrol(st["waypoints"])

func _on_rested() -> void:
	if _phase == "complete":
		return
	_phase = "complete"
	_show_note("The pump hall is behind you. Rest.", 2.5)
	_set_preview_step("pump_hall_complete")

## Conceal tiers, per frame from REAL positions: Capbage = tight (never seen), Scarpet pads = medium
## (outer-range passes miss you; close passes don't).
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
		var pos: Vector3 = gs.get_position(cid)
		var tier: int = GameState.CONCEAL_NONE
		if _capbage != null and is_instance_valid(_capbage) and _capbage.conceals(pos):
			tier = GameState.CONCEAL_FULL
		else:
			for c in SCARPET_PADS:
				var p := _cell_world(c as Vector2i)
				if Vector2(pos.x - p.x, pos.z - p.z).length() <= CELL * 1.1:
					tier = GameState.CONCEAL_MEDIUM
					break
		gs.set_character_concealment(cid, tier)

## Freed while the scheduler lives (reloads): retract every tag this chunk owns.
func _exit_tree() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("pump_lure")
	sched.cancel_tag("pump_restart")

# --- SceneChunk interface -------------------------------------------------------------------------------

func get_scene_title() -> String:
	return "Pump Hall"

func get_scene_help() -> String:
	return "Three rooms, three watchers. Read the amber walks — spotted means attacked. Scarpet hides you from a distance; the Capbage hides you completely. The flure buys a fat window on the door. Both havens are safe ground; a fallen member stays where they drop. Rest at the shelter."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	var s := _cell_world(HOME_CELL)
	return {
		"aster": s + Vector3(-0.6, 0.0, -1.0),
		"peris": s + Vector3(0.4, 0.0, 0.0),
		"endo": s + Vector3(-0.6, 0.0, 1.0),
	}

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors["flure"] = _cell_world(FLURE_CELL)
	anchors["settle"] = _cell_world(SETTLE_CELL)
	anchors["door"] = _cell_world(Vector2i(GALLERY_X, DOOR_Y0)) + Vector3(CELL, 0.0, CELL * 0.5)
	anchors["door_stage"] = _cell_world(Vector2i(12, 13))   # west staging for the door leg (time S1 from here)
	anchors["exit"] = _cell_world(EXIT_CELL)
	anchors["capbage"] = _cell_world(CAPBAGE_CELL)
	anchors["scarpet_0"] = _cell_world(SCARPET_PADS[0] as Vector2i)
	anchors["scarpet_1"] = _cell_world(SCARPET_PADS[1] as Vector2i)
	anchors["gallery_landing"] = _cell_world(Vector2i(17, 18))   # first cover past the door (the old staging spot)
	for i in range(_sentries.size()):
		anchors["post_%d" % i] = _sentries[i]["post"]
	anchors["s1_far"] = _cell_world(S1_B)
	anchors["s2_far"] = _cell_world(S2_B)
	anchors["s3_far"] = _cell_world(S3_ORBIT[2] as Vector2i)
	return anchors

func reset_preview_state() -> void:
	var gs = _get_game_state()
	if gs != null:
		if not gs.character_arrived.is_connected(_on_character_arrived):
			gs.character_arrived.connect(_on_character_arrived)
		if not gs.character_downed.is_connected(_on_character_downed):
			gs.character_downed.connect(_on_character_downed)
	_phase = "ready"
	_spotted_count = 0
	_wipe_count = 0
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("pump_lure")
		sched.cancel_tag("pump_restart")
	_lure_until = -1.0
	_lure_returning = false
	if _flure_mesh != null and _flure_mesh.material_override is StandardMaterial3D:
		(_flure_mesh.material_override as StandardMaterial3D).emission_energy_multiplier = 0.5
	for i in range(_sentries.size()):
		_reset_sentry(i)
	_set_preview_step("pump_hall_briefing")

func get_preview_state() -> Dictionary:
	var now := _get_scheduler_tick()
	var downed: Array = []
	var gs = _get_game_state()
	if gs != null:
		for cid in PARTY_IDS:
			if gs.is_downed(cid):
				downed.append(cid)
	return {
		"phase": _phase,
		"spotted_count": _spotted_count,
		"wipe_count": _wipe_count,
		"downed": downed,
		"lure_active": _lure_until > now,
		"complete": _phase == "complete",
	}
