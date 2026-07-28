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
const DISTRACT_GATE_AUTHORITY_VERSION := 2
const DISTRACT_GATE_AUTHORITY_KEY := "chunk:distract_gate:runtime"

var _sentry = null
var _phase := "ready"          # ready | active | complete
var _caught_count := 0
var _flure_fired := false      # has the flure EVER sung this attempt (telemetry; not a permanent latch)
var _lure_until := -1.0
var _lure_returning := false   # the lure expired and the sentry is walking home (still distracted until it arrives)
var _flure: Flure = null
var _accepted_flure_serial := 0
var _accepted_flure_trigger_count := 0
var _win_poll_deadline := -1.0
var _restoring_distract_gate_authority := false

const WIN_POLL_INTERVAL := 0.1  # the completion check rides the scheduler at a FIXED cadence (frame-rate free)

# --- Build ---

func _build_chunk() -> void:
	# Floors (with collision, so ground clicks land): west room, the gap lane, east room.
	_add_floor(self, Vector3(5.0, -0.05, 0.0), Vector3(8.0, 0.1, ROOM_HALF_Z * 2.0), Color(0.09, 0.1, 0.12))
	_add_floor(self, Vector3(10.5, -0.05, 0.0), Vector3(3.0, 0.1, GAP_HALF_Z * 2.0), Color(0.11, 0.11, 0.13))
	_add_floor(self, Vector3(17.0, -0.05, 0.0), Vector3(10.0, 0.1, ROOM_HALF_Z * 2.0), Color(0.09, 0.1, 0.12))
	_build_walls()
	_add_box(self, FLURE_POS - Vector3(0.0, 0.42, 0.0), Vector3(1.4, 0.12, 1.4),
		Color(0.26, 0.17, 0.06), Color(0.95, 0.55, 0.12), 0.55, "FlureBed")
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
	var gs = _get_game_state()
	if gs == null:
		return
	_flure = Flure.new()
	_flure.name = "FlureInteract"
	_flure.authority_id = "distract_gate:watcher_flure"
	_flure.configure(gs, FLURE_POS, ["gap_sentry"], 32.0, FLURE_PICK_RADIUS,
		Color(0.95, 0.62, 0.14))
	_flure.required_character = "peris"
	_flure.one_shot = false
	_flure.interactable_type = Interactable.InteractableType.TIMED_ACTION
	_flure.dwell_time = FLURE_TEND_TIME
	_flure.description = "Tend the watcher Flure"
	_flure.tutorial_label = "TEND"
	_flure.settle_pos = LURE_SETTLE_POS
	_flure.lure_duration = LURE_DURATION
	_flure.set_enemy_resolver(_resolve_sentry)
	_flure.flure_activated.connect(_on_physical_flure_activated)
	add_child(_flure)


func _resolve_sentry(target_id: String):
	return _sentry if target_id == "gap_sentry" and is_instance_valid(_sentry) else null

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
	enemy.set_lure_return_policy(true)
	enemy.target_spotted.connect(_on_spotted)
	# The sentry stays DISTRACTED for its whole walk home after a lure expires — full range comes back only
	# once it ARRIVES at the post. Restoring it at expiry (while parked in the west pocket) put the START
	# inside its clear-LOS 6.0 reach and insta-spotted the party for playing correctly.
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
	return false


func _on_physical_flure_activated(_pulled: int) -> void:
	if _phase == "complete" or _flure == null:
		return
	var effect := _flure.get_effect_state()
	var source_effect: Dictionary = effect.get("last_effect", {})
	var serial := int(effect.get("activation_serial", 0))
	var trigger_count := int(source_effect.get("source_trigger_count", 0))
	if str(effect.get("phase", "")) != Flure.PHASE_ACTIVE \
			or serial <= _accepted_flure_serial \
			or trigger_count <= _accepted_flure_trigger_count \
			or str(source_effect.get("source_actor", "")) != "peris" \
			or not (source_effect.get("pulled_ids", []) as Array).has("gap_sentry"):
		return
	_accepted_flure_serial = serial
	_accepted_flure_trigger_count = trigger_count
	_phase = "active"
	_flure_fired = true
	_lure_until = float(effect.get("end_tick", -1.0))
	_lure_returning = false
	_show_message("The flure sings out. The sentry turns.", 1.4)
	_set_preview_step("distract_gate_lured")
	_publish_distract_gate_authority()


## Mirror only facts already owned by the physical Flure and Enemy. This function never moves a
## body, changes distraction, or invents a deadline.
func _sync_flure_surface_from_sources() -> void:
	var effect: Dictionary = _flure.get_effect_state() if _flure != null else {}
	var source_phase := str(effect.get("phase", Flure.PHASE_READY))
	var now := _get_scheduler_tick()
	_lure_until = float(effect.get("end_tick", -1.0)) \
		if source_phase in [Flure.PHASE_APPLYING, Flure.PHASE_ACTIVE] else -1.0
	if _lure_until <= now:
		_lure_until = -1.0
	var sentry_state: String = _sentry.get_state() \
		if _sentry != null and is_instance_valid(_sentry) else ""
	var gs = _get_game_state()
	_lure_returning = sentry_state == "return" \
		and gs != null and gs.characters.has("gap_sentry") \
		and gs.is_character_distracted("gap_sentry")
	if _phase != "complete":
		_phase = "active" if _lure_until > now or _lure_returning else "ready"

## Spotted in the open = the KIT runs: the sentry's own FSM pursues and strikes; when it loses
## the target it searches and returns to post re-armed (the same disengage every enemy has). The
## chunk only COUNTS the spot and says why — no scripted sweep, no teleport (that was design
## guidance, not a mechanic; see the header).
func _on_spotted(target_id: String) -> void:
	if _phase == "complete" or not (target_id in PARTY_IDS):
		return
	_caught_count += 1
	# Enemy emits immediately before entering ALERT. Reconcile one scheduler beat later, after its
	# physical FSM transition has actually falsified the Flure's applied-target receipt.
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(
			0.000001, _reconcile_spotted_flure, "distract_gate_reconcile")
	_publish_distract_gate_authority()
	_show_note("SPOTTED — the gap watcher has %s. RUN." % target_id.capitalize(), 2.6)
	_set_preview_step("distract_gate_caught")


func _reconcile_spotted_flure() -> void:
	if _flure != null:
		_flure.reconcile_interrupted_targets()
	_sync_flure_surface_from_sources()
	_publish_distract_gate_authority()


## The reset-grade restart re-arms the physical Flure and lets Enemy.re_post clear its own
## lure/distraction authority. No chunk-local timer or movement command participates.
func _reset_sentry_to_post() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("distract_gate_reconcile")
	if _flure != null:
		_flure.reset_flure()
	_lure_until = -1.0
	_lure_returning = false
	var gs = _get_game_state()
	if _sentry == null or not is_instance_valid(_sentry) or gs == null or not gs.characters.has("gap_sentry"):
		_publish_distract_gate_authority()
		return
	_sentry.re_post(SENTRY_POST)
	_publish_distract_gate_authority()

# --- The win check: a FIXED-cadence scheduler poll, never a per-frame sample ---
# Completion races the tick-exact catch sweep (a member can cross END_X and be spotted within the same
# coarse frame). Polling per frame made the verdict depend on the frame/step size — win at 1x, swept at
# 10x, the exact fast-forward divergence the project forbids. On the scheduler the sampling grid is the
# same at every speed, so the verdict is deterministic.

func _start_win_poll() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	_arm_win_poll(_get_scheduler_tick() + WIN_POLL_INTERVAL)


func _arm_win_poll(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("distract_gate_win")
	_win_poll_deadline = deadline
	sched.schedule_after(maxf(0.0, deadline - _get_scheduler_tick()),
		_win_poll_tick, "distract_gate_win")

func _win_poll_tick() -> void:
	_win_poll_deadline = -1.0
	_sync_flure_surface_from_sources()
	if _phase == "complete":
		_publish_distract_gate_authority()
		return
	var gs = _get_game_state()
	if gs != null and _full_conscious_party_beyond_exit(gs):
		_phase = "complete"
		_publish_distract_gate_authority()
		_show_note("The whole party is through while the flure holds. The end is yours.", 2.5)
		_set_preview_step("distract_gate_complete")
		return
	var sched = _get_scheduler()
	if sched != null:
		_arm_win_poll(_get_scheduler_tick() + WIN_POLL_INTERVAL)
	_publish_distract_gate_authority()


func _full_conscious_party_beyond_exit(gs) -> bool:
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id) or gs.is_downed(char_id) \
				or _get_character_position(char_id).x < END_X:
			return false
	return true

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
	_accepted_flure_serial = 0
	_accepted_flure_trigger_count = 0
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("distract_gate_reconcile")
		sched.cancel_tag("distract_gate_catch")
		sched.cancel_tag("distract_gate_win")
	if _flure != null:
		_flure.reset_flure()
	var gs = _get_game_state()
	if gs != null and _sentry != null and is_instance_valid(_sentry) and gs.characters.has("gap_sentry"):
		_sentry.re_post(SENTRY_POST)
	_start_win_poll()
	_publish_distract_gate_authority()
	_set_preview_step("distract_gate_briefing")


func _distract_gate_authority_state() -> Dictionary:
	return {
		"version": DISTRACT_GATE_AUTHORITY_VERSION,
		"phase": _phase,
		"caught_count": _caught_count,
		"flure_fired": _flure_fired,
		"lure_until": _lure_until,
		"lure_returning": _lure_returning,
		"accepted_flure_serial": _accepted_flure_serial,
		"accepted_flure_trigger_count": _accepted_flure_trigger_count,
		"win_poll_deadline": _win_poll_deadline,
	}


func _publish_distract_gate_authority() -> void:
	if _restoring_distract_gate_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(DISTRACT_GATE_AUTHORITY_KEY, _distract_gate_authority_state())


## Restore the fixed-cadence end-zone check after the loader clears opaque Callables. The reusable
## Flure and Enemy independently restore the actual song, movement, distraction, and return phases.
func on_game_state_snapshot_restored() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("distract_gate_reconcile")
		sched.cancel_tag("distract_gate_win")
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(DISTRACT_GATE_AUTHORITY_KEY, null) \
			if gs != null and gs.has_method("get_world_state") else null
	if not raw is Dictionary or int(raw.get("version", 0)) != DISTRACT_GATE_AUTHORITY_VERSION:
		_retract_distract_gate_presenter()
		return

	var saved: Dictionary = raw
	_restoring_distract_gate_authority = true
	_phase = str(saved.get("phase", "ready"))
	if _phase not in ["ready", "active", "complete"]:
		_phase = "ready"
	_caught_count = maxi(0, int(saved.get("caught_count", 0)))
	_flure_fired = bool(saved.get("flure_fired", false))
	_lure_until = float(saved.get("lure_until", -1.0))
	_lure_returning = bool(saved.get("lure_returning", false))
	_accepted_flure_serial = maxi(0, int(saved.get("accepted_flure_serial", 0)))
	_accepted_flure_trigger_count = maxi(
		0, int(saved.get("accepted_flure_trigger_count", 0)))
	_win_poll_deadline = float(saved.get("win_poll_deadline", -1.0))
	_restoring_distract_gate_authority = false
	_sync_flure_surface_from_sources()
	if _caught_count > 0 and _flure != null \
			and str(_flure.get_effect_state().get("phase", "")) == Flure.PHASE_ACTIVE:
		var reconcile_sched = _get_scheduler()
		if reconcile_sched != null:
			reconcile_sched.schedule_after(
				0.000001, _reconcile_spotted_flure, "distract_gate_reconcile")
	if _phase != "complete" and _win_poll_deadline >= 0.0:
		_arm_win_poll(_win_poll_deadline)


func _retract_distract_gate_presenter() -> void:
	_restoring_distract_gate_authority = true
	_phase = "ready"
	_caught_count = 0
	_flure_fired = false
	_lure_until = -1.0
	_lure_returning = false
	_accepted_flure_serial = 0
	_accepted_flure_trigger_count = 0
	_restoring_distract_gate_authority = false
	_start_win_poll()
	_publish_distract_gate_authority()

func get_preview_state() -> Dictionary:
	var now := _get_scheduler_tick()
	var effect: Dictionary = _flure.get_effect_state() if _flure != null else {}
	var source_phase := str(effect.get("phase", Flure.PHASE_READY))
	var source_until := float(effect.get("end_tick", -1.0))
	var sentry_state: String = _sentry.get_state() \
		if _sentry != null and is_instance_valid(_sentry) else ""
	var gs = _get_game_state()
	var returning: bool = sentry_state == "return" \
		and gs != null and gs.characters.has("gap_sentry") \
		and gs.is_character_distracted("gap_sentry")
	return {
		"phase": _phase,
		"caught_count": _caught_count,
		"flure_fired": _flure_fired,
		"lure_active": source_phase in [Flure.PHASE_APPLYING, Flure.PHASE_ACTIVE] \
			and source_until > now,
		"lure_returning": returning,
		"sentry_state": sentry_state,
		"complete": _phase == "complete",
	}
