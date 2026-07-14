extends "res://scripts/scene_chunks/scene_chunk.gd"

## THE WATCHED GAP — the atomic distract-the-patrol chunk (Archetype 4), built from REAL mechanics so it can be
## played and TESTED as built (no abstract "click = solved" stand-ins):
##   START (west room) -> the ONLY way through is a one-lane GAP in a dividing wall -> END (east room).
##   A real Enemy sentry guards the gap's east mouth. Its detection is the game's real predictive detection,
##   which is LOS-GATED: the dividing wall's cells are opaque, so the sentry CANNOT see you through the wall —
##   you are only exposed in the gap lane itself. Walking the gap exposed = spotted = the KIT's own
##   consequence: the sentry pursues and STRIKES (real damage), then loses you and returns to post via its
##   own FSM. (Director's correction: "swept back to the start" was DESIGN GUIDANCE to consider — a level
##   that wants a literal sweep places a kit object that embodies it, e.g. a wash Channel; a chunk never
##   hard-codes a teleport the player can't see a mechanism for.) The solve: Peris tends the FLURE in the west-south
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
var _flure_fired := false      # has the flure EVER sung this attempt (telemetry; not a permanent latch)
var _lure_until := -1.0
var _lure_returning := false   # the lure expired and the sentry is walking home (still distracted until it arrives)
var _flure_mesh: MeshInstance3D

const WIN_POLL_INTERVAL := 0.1  # the completion check rides the scheduler at a FIXED cadence (frame-rate free)

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
## scheduler's dwell -> fires). NOT one-shot: a missed window must never soft-lock the fragment ("beatable,
## never soft-lock") — the flure re-tends after expiry/a catch; activate_flure rejects a re-fire only while
## a lure is already in flight.
func _build_flure_interactable() -> void:
	var flure := _add_object_interactable(self, "FlureInteract", "Flure", FLURE_POS,
		"Tend", [_flure_mesh], "peris", FLURE_TEND_TIME, false, FLURE_PICK_RADIUS, Interactable.InteractableType.TIMED_ACTION)
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
	# The sentry stays DISTRACTED for its whole walk home after a lure expires — full range comes back only
	# once it ARRIVES at the post. Restoring it at expiry (while parked in the west pocket) put the START
	# inside its clear-LOS 6.0 reach and insta-spotted the party for playing correctly.
	gs.character_arrived.connect(_on_character_arrived)
	_sentry = enemy

func _on_character_arrived(id: String) -> void:
	if id != "gap_sentry" or not _lure_returning:
		return
	_lure_returning = false
	var gs = _get_game_state()
	if gs != null and gs.characters.has("gap_sentry"):
		gs.set_character_distracted("gap_sentry", false)

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
	var now := _get_scheduler_tick()
	if _phase == "complete" or _lure_until > now or _lure_returning:
		return false   # one lure in flight at a time; re-tending after expiry/a catch is always allowed
	_phase = "active"
	_flure_fired = true
	_lure_until = now + LURE_DURATION
	_set_flure_emission(3.0)
	var gs = _get_game_state()
	if _sentry != null and is_instance_valid(_sentry) and gs != null and gs.characters.has("gap_sentry"):
		_sentry._current_target_id = ""
		if _sentry.has_method("_change_state"):
			_sentry._change_state("idle")
		gs.set_character_distracted("gap_sentry", true)
		gs.command_move_to_pos("gap_sentry", LURE_SETTLE_POS)
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("distract_gate_lure")
		sched.schedule_after(LURE_DURATION, _on_lure_expired, "distract_gate_lure")
	_show_message("The flure sings out. The sentry turns.", 1.4)
	_set_preview_step("distract_gate_lured")
	return true

func _on_lure_expired() -> void:
	_lure_until = -1.0
	_set_flure_emission(0.5)
	var gs = _get_game_state()
	if _sentry != null and is_instance_valid(_sentry) and _sentry.is_alive() and gs != null and gs.characters.has("gap_sentry"):
		# Walk home still DISTRACTED (reach stays shrunken until it re-posts) — _on_character_arrived
		# restores the full watch. Un-distracting here, parked in the west pocket, put the START inside
		# its restored 6.0 reach with clear room LOS and insta-caught a correctly retreating party.
		_lure_returning = true
		if _sentry.has_method("_change_state"):
			_sentry._change_state("idle")
		gs.command_move_to_pos("gap_sentry", SENTRY_POST)

func _set_flure_emission(energy: float) -> void:
	if _flure_mesh != null and _flure_mesh.material_override is StandardMaterial3D:
		(_flure_mesh.material_override as StandardMaterial3D).emission_energy_multiplier = energy

## Spotted in the open = the KIT runs: the sentry's own FSM pursues and strikes; when it loses
## the target it searches and returns to post re-armed (the same disengage every enemy has). The
## chunk only COUNTS the spot and says why — no scripted sweep, no teleport (that was design
## guidance, not a mechanic; see the header).
func _on_spotted(target_id: String) -> void:
	if _phase == "complete" or not (target_id in PARTY_IDS):
		return
	_caught_count += 1
	# BOOKKEEPING (not consequence): a sentry that has spotted someone is no longer lured — the
	# running lure window, the returning flag and the distraction shrink all clear so the chunk's
	# state never lies about a sentry that is visibly hunting.
	_lure_until = -1.0
	_lure_returning = false
	_set_flure_emission(0.5)
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("distract_gate_lure")
	var gs = _get_game_state()
	if gs != null and gs.characters.has("gap_sentry"):
		gs.set_character_distracted("gap_sentry", false)
	_show_note("SPOTTED — the gap watcher has %s. RUN." % target_id.capitalize(), 2.6)
	_set_preview_step("distract_gate_caught")

## The catch is ONE atomic beat: the sentry re-posts AND every scrap of lure state clears with it — the
## pending expiry tag, the distracted flag, the running window, the glow. Leaving any of them (the review
## caught the sentry sitting at its post distracted at 0.4x reach for the rest of the window, with
## get_preview_state still reporting lure_active) makes "re-armed" a lie.
func _reset_sentry_to_post() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("distract_gate_lure")
	_lure_until = -1.0
	_lure_returning = false
	_set_flure_emission(0.5)
	var gs = _get_game_state()
	if _sentry == null or not is_instance_valid(_sentry) or gs == null or not gs.characters.has("gap_sentry"):
		return
	_sentry.re_post(SENTRY_POST)

# --- The win check: a FIXED-cadence scheduler poll, never a per-frame sample ---
# Completion races the tick-exact catch sweep (a member can cross END_X and be spotted within the same
# coarse frame). Polling per frame made the verdict depend on the frame/step size — win at 1x, swept at
# 10x, the exact fast-forward divergence the project forbids. On the scheduler the sampling grid is the
# same at every speed, so the verdict is deterministic.

func _start_win_poll() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("distract_gate_win")
	sched.schedule_after(WIN_POLL_INTERVAL, _win_poll_tick, "distract_gate_win")

func _win_poll_tick() -> void:
	if _phase == "complete":
		return
	var gs = _get_game_state()
	if gs != null:
		for char_id in PARTY_IDS:
			if gs.characters.has(char_id) and _get_character_position(char_id).x >= END_X:
				_phase = "complete"
				_show_note("Through the gap while the flure held. The end is yours.", 2.5)
				_set_preview_step("distract_gate_complete")
				return
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(WIN_POLL_INTERVAL, _win_poll_tick, "distract_gate_win")

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
	_lure_returning = false
	_set_flure_emission(0.5)
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("distract_gate_lure")
		sched.cancel_tag("distract_gate_catch")
	var gs = _get_game_state()
	if gs != null and _sentry != null and is_instance_valid(_sentry) and gs.characters.has("gap_sentry"):
		_sentry.re_post(SENTRY_POST)
	_start_win_poll()
	_set_preview_step("distract_gate_briefing")

func get_preview_state() -> Dictionary:
	var now := _get_scheduler_tick()
	return {
		"phase": _phase,
		"caught_count": _caught_count,
		"flure_fired": _flure_fired,
		"lure_active": _lure_until > now,
		"lure_returning": _lure_returning,
		"sentry_state": _sentry.get_state() if _sentry != null and is_instance_valid(_sentry) else "",
		"complete": _phase == "complete",
	}
