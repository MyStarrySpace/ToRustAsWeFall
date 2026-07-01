extends "res://scripts/scene_chunks/scene_chunk.gd"

## THE WATCHED GAP — the atomic distract-the-patrol chunk (Archetype 4), built from REAL mechanics so it can be
## played and TESTED as built (no abstract "click = solved" stand-ins):
##   START (west room) -> the ONLY way through is a one-lane GAP in a dividing wall -> END (east room).
##   A real Enemy sentry guards the gap's east mouth. Its detection is the game's real predictive detection,
##   which is LOS-GATED: the dividing wall's cells are opaque, so the sentry CANNOT see you through the wall —
##   you are only exposed in the gap lane itself. Walking the gap exposed = spotted = swept back to the start
##   (the failure costs progress; the run keeps going). The solve: Peris tends the FLURE in the west-south
##   pocket (click -> walk -> tend dwell on the scheduler); the sentry commits to it (walking the whole way,
##   DISTRACTED — reach shrinks but it still catches anyone who crowds it), which clears the gap; fall back,
##   let it settle, then cross to the end.
## Chunk-atom contract: you cannot get start->end without solving; the enforcement is the real detection
## mechanic, not a scripted wall.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")

const PARTY_IDS := ["aster", "peris", "endo"]
const SPAWNS := {
	"aster": Vector3(2.5, 0.5, -1.0),
	"peris": Vector3(3.0, 0.5, 0.0),
	"endo": Vector3(2.5, 0.5, 1.0),
}

# Cell-exact rooms (origin [0,0,-7], cell 1.0): west room cells x 1..8, the WALL band cells x 9..11 broken only
# by the gap lane (rows z in [-1,1)), east room cells x 12..21. The gap is the ONLY connection, and the wall
# cells are non-walkable => OPAQUE, so the geometry that stops movement is the same geometry that blocks sight.
const WALL_X0 := 9.0
const WALL_X1 := 12.0
const GAP_HALF_Z := 1.0
const ROOM_HALF_Z := 6.0
const SENTRY_POST := Vector3(12.5, 0.5, 0.0)   # right at the gap's east mouth, watching straight down the lane
const SENTRY_RANGE := 6.0                       # sees the whole lane (even into the west room ALONG the lane);
                                                # the west room off-lane is wall-blocked or out of range
const SENTRY_SPEED := 3.5
const FLURE_POS := Vector3(4.5, 0.5, 4.5)       # west-south pocket — reachable WITHOUT entering the watched lane
const FLURE_TEND_TIME := 2.0
const FLURE_PICK_RADIUS := 0.9
const LURE_SETTLE_POS := Vector3(5.5, 0.5, 4.0) # where the lured sentry parks (beside the flure, not on it)
const LURE_DURATION := 20.0                     # scheduler ticks the flure holds the sentry (a real cross window)
const END_X := 19.5                             # crossing this = the end point reached

var _sentry = null
var _phase := "ready"          # ready | active | complete
var _caught_count := 0
var _flure_fired := false
var _lure_until := -1.0
var _flure_mesh: MeshInstance3D

# --- Build ---

func _build_chunk() -> void:
	# Floors (with collision, so ground clicks land): west room, the gap lane, east room.
	_add_floor(self, Vector3(5.0, -0.05, 0.0), Vector3(8.0, 0.1, ROOM_HALF_Z * 2.0), Color(0.09, 0.1, 0.12))
	_add_floor(self, Vector3(10.5, -0.05, 0.0), Vector3(3.0, 0.1, GAP_HALF_Z * 2.0), Color(0.11, 0.11, 0.13))
	_add_floor(self, Vector3(17.0, -0.05, 0.0), Vector3(10.0, 0.1, ROOM_HALF_Z * 2.0), Color(0.09, 0.1, 0.12))
	_build_walls()
	_flure_mesh = _add_box(self, FLURE_POS, Vector3(0.4, 0.4, 0.4), Color(0.7, 0.45, 0.15),
		Color(0.8, 0.4, 0.1), 0.5, "FlureMesh")
	_add_label(self, "START", Vector3(3.0, 1.8, 0.0), Color(0.5, 0.8, 0.6))
	_add_label(self, "END", Vector3(20.5, 1.8, 0.0), Color(0.85, 0.8, 0.5))
	_add_light(self, Vector3(10.5, 2.2, 0.0), Color(0.8, 0.75, 0.6), 1.0, 6.0)
	_add_light(self, Vector3(20.0, 1.6, 0.0), Color(0.7, 0.8, 0.6), 0.9, 5.0)
	_build_flure_interactable()
	_spawn_sentry()

func _build_walls() -> void:
	var wc := Color(0.06, 0.06, 0.08)
	var wall_cx := (WALL_X0 + WALL_X1) * 0.5
	var wall_w := WALL_X1 - WALL_X0
	# The dividing wall, above + below the gap. These cells are non-walkable in the grid => OPAQUE, so the
	# sentry genuinely cannot see through them (the real LOS gate, not a convention).
	var north_len := ROOM_HALF_Z - GAP_HALF_Z
	_add_box(self, Vector3(wall_cx, 1.4, GAP_HALF_Z + north_len * 0.5), Vector3(wall_w, 2.8, north_len), wc)
	_add_box(self, Vector3(wall_cx, 1.4, -GAP_HALF_Z - north_len * 0.5), Vector3(wall_w, 2.8, north_len), wc)
	# Perimeter (visual bounds; the grid already stops movement at the room edges).
	_add_box(self, Vector3(11.5, 1.4, ROOM_HALF_Z + 0.35), Vector3(23.0, 2.8, 0.3), wc)
	_add_box(self, Vector3(11.5, 1.4, -ROOM_HALF_Z - 0.35), Vector3(23.0, 2.8, 0.3), wc)
	_add_box(self, Vector3(0.65, 1.4, 0.0), Vector3(0.3, 2.8, ROOM_HALF_Z * 2.0), wc)
	_add_box(self, Vector3(22.35, 1.4, 0.0), Vector3(0.3, 2.8, ROOM_HALF_Z * 2.0), wc)

## The flure is a TIMED_ACTION interactable (click -> Peris walks over -> tends for FLURE_TEND_TIME on the
## scheduler's dwell -> fires). Same real path as lure_relay; wrapped in the shared outline highlight.
func _build_flure_interactable() -> void:
	var flure := _add_object_interactable(self, "FlureInteract", "Flure", FLURE_POS,
		"Tend", [_flure_mesh], "peris", FLURE_TEND_TIME, true, FLURE_PICK_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	flure.interacted.connect(func() -> void: activate_flure())

func _spawn_sentry() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var enemy := EnemyScript.new()
	enemy.name = "GapSentry"
	enemy.position = SENTRY_POST
	enemy.move_speed = SENTRY_SPEED
	enemy.detection_range = SENTRY_RANGE
	enemy._detection_targets.assign(PARTY_IDS)
	add_child(enemy)
	enemy.char_id = "gap_sentry"
	enemy.game_state = gs
	gs.register_character("gap_sentry", enemy.position, enemy.move_speed, {"detection_range": SENTRY_RANGE})
	enemy.activate()
	enemy.target_spotted.connect(_on_spotted)
	enemy.hit_target.connect(func(tid: String, _dmg: float) -> void: _on_spotted(tid))
	_sentry = enemy

## The grid IS the room shape: west room + the one-lane gap + east room. Everything else is WALL tiles —
## non-walkable AND opaque (movement and sightlines agree by construction).
func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, -7.0],
		"cell_size": 1.0,
		"width": 24,
		"height": 14,
		# Cell-exact (region maxes sit INSIDE the last intended cell so rasterization matches the design):
		# west room cells x 1..8, the gap lane cells x 9..11 rows z in [-1,1), east room cells x 12..21.
		"walkable_regions": [
			{"min": [1.0, -ROOM_HALF_Z], "max": [WALL_X0 - 0.1, ROOM_HALF_Z - 0.1]},
			{"min": [WALL_X0, -GAP_HALF_Z], "max": [WALL_X1 - 0.1, GAP_HALF_Z - 0.1]},
			{"min": [WALL_X1, -ROOM_HALF_Z], "max": [21.9, ROOM_HALF_Z - 0.1]},
		],
	}

# --- The puzzle ---

## The flure sings: the sentry drops its watch and commits to the flure (a REAL walk through the gap to the
## west pocket), DISTRACTED — its reach shrinks (x0.4) but it still catches anyone who crowds it. The gap is
## clear while it's away; the flure holds it for LURE_DURATION, then it walks back to its post and re-arms.
func activate_flure() -> bool:
	if _phase == "complete" or _flure_fired:
		return false
	_phase = "active"
	_flure_fired = true
	var now := _get_scheduler_tick()
	_lure_until = now + LURE_DURATION
	if _flure_mesh != null and _flure_mesh.material_override is StandardMaterial3D:
		(_flure_mesh.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0
	var gs = _get_game_state()
	if _sentry != null and is_instance_valid(_sentry) and gs != null and gs.characters.has("gap_sentry"):
		_sentry._current_target_id = ""
		if _sentry.has_method("_change_state"):
			_sentry._change_state("idle")
		gs.set_character_distracted("gap_sentry", true)
		gs.command_move_to_pos("gap_sentry", LURE_SETTLE_POS)
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(LURE_DURATION, _on_lure_expired, "distract_gate_lure")
	_show_message("The flure sings out. The sentry turns.", 1.4)
	_set_preview_step("distract_gate_lured")
	return true

func _on_lure_expired() -> void:
	_lure_until = -1.0
	if _flure_mesh != null and _flure_mesh.material_override is StandardMaterial3D:
		(_flure_mesh.material_override as StandardMaterial3D).emission_energy_multiplier = 0.5
	var gs = _get_game_state()
	if _sentry != null and is_instance_valid(_sentry) and _sentry.is_alive() and gs != null and gs.characters.has("gap_sentry"):
		gs.set_character_distracted("gap_sentry", false)
		gs.command_move_to_pos("gap_sentry", SENTRY_POST)
		if _sentry.has_method("_change_state"):
			_sentry._change_state("idle")

## Spotted in the open = CAUGHT. The failure costs progress, it doesn't end the run: the caught member is
## swept back to the start (escorted off, in fiction) AND the sentry returns to its post, re-armed — the
## whole catch is one beat, like a wash sweep. Leaving the sentry mid-hunt instead camps it on the spawned
## party and it re-spots them forever (the playtest caught exactly that loop). The post-reset is DEFERRED
## one scheduler tick so it never mutates the enemy FSM from inside its own target_spotted emit.
func _on_spotted(target_id: String) -> void:
	if _phase == "complete" or not (target_id in PARTY_IDS):
		return
	_caught_count += 1
	var gs = _get_game_state()
	if gs != null and gs.characters.has(target_id):
		gs.command_stop(target_id)
		gs.snap_character_to(target_id, SPAWNS.get(target_id, SPAWNS["peris"]))
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("distract_gate_catch")
		sched.schedule_after(0.05, _reset_sentry_to_post, "distract_gate_catch")
	_show_note("Spotted in the gap. Escorted back to the start.", 2.2)
	_set_preview_step("distract_gate_caught")

func _reset_sentry_to_post() -> void:
	var gs = _get_game_state()
	if _sentry == null or not is_instance_valid(_sentry) or gs == null or not gs.characters.has("gap_sentry"):
		return
	_sentry._current_target_id = ""
	if _sentry.has_method("_change_state"):
		_sentry._change_state("idle")
	gs.command_stop("gap_sentry")
	gs.snap_character_to("gap_sentry", SENTRY_POST)
	_sentry.position = SENTRY_POST

# --- Per-frame: the win check ---

func _process(delta: float) -> void:
	_update(delta)

func headless_process(delta: float) -> void:
	_update(delta)

func _update(_delta: float) -> void:
	if _phase == "complete":
		return
	var gs = _get_game_state()
	if gs == null:
		return
	for char_id in PARTY_IDS:
		if gs.characters.has(char_id) and _get_character_position(char_id).x >= END_X:
			_phase = "complete"
			_show_note("Through the gap while the flure held. The end is yours.", 2.5)
			_set_preview_step("distract_gate_complete")
			return

# --- SceneChunk interface ---

func get_scene_title() -> String:
	return "The Watched Gap"

func get_scene_help() -> String:
	return "One gap, one sentry watching it. It cannot see through the wall — but the gap is bare. Tend the flure to pull it away, fall back, then cross."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"flure": FLURE_POS,
		"gap": Vector3(11.0, 0.5, 0.0),
		"sentry_post": SENTRY_POST,
		"end": Vector3(END_X + 0.5, 0.5, 0.0),
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 2,
		"time": 0.55,
		"routing_mode": "safe",
		"note_default": "The sentry watches the only gap. Walls blind it; the lane doesn't.",
	}

func get_preview_abilities() -> Array:
	return []

func reset_preview_state() -> void:
	_phase = "ready"
	_caught_count = 0
	_flure_fired = false
	_lure_until = -1.0
	if _flure_mesh != null and _flure_mesh.material_override is StandardMaterial3D:
		(_flure_mesh.material_override as StandardMaterial3D).emission_energy_multiplier = 0.5
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("distract_gate_lure")
	var gs = _get_game_state()
	if gs != null and _sentry != null and is_instance_valid(_sentry) and gs.characters.has("gap_sentry"):
		gs.set_character_distracted("gap_sentry", false)
		gs.snap_character_to("gap_sentry", SENTRY_POST)
		_sentry.position = SENTRY_POST
		if _sentry.has_method("_change_state"):
			_sentry._change_state("idle")
	_set_preview_step("distract_gate_briefing")

func get_preview_state() -> Dictionary:
	var now := _get_scheduler_tick()
	return {
		"phase": _phase,
		"caught_count": _caught_count,
		"flure_fired": _flure_fired,
		"lure_active": _lure_until > now,
		"sentry_state": _sentry.get_state() if _sentry != null and is_instance_valid(_sentry) else "",
		"complete": _phase == "complete",
	}
