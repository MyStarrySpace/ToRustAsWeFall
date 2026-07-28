extends "res://scripts/scene_chunks/scene_chunk.gd"

## Two-lure relay puzzle. A long narrow hallway with an offshoot hiding spot near the far (second)
## lure. A group of enemies guards the exit (remains of a previous runner lie among them). Two
## flures: Lure 1 near the ENTRANCE (far from the hide), Lure 2 near the ENEMIES (close to the hide).
##
## Intended solve: fire Lure 2 (the guards break toward it, clearing the path), duck into the nearby
## hiding spot, fire Lure 1 -> when Lure 2 expires the guards relay onward to Lure 1 (walking the whole
## hall back PAST the hidden party) -> slip out and run the now-open exit while Lure 1 holds them far away.
##
## The hide sits CLOSE to Lure 2 and FAR from Lure 1 on purpose: you can't just fire the near-entrance
## Lure 1 and hide straight away — the guards swarming to Lure 1 fill the only corridor to the hide, so
## you get spotted crossing. Only firing the far Lure 2 first clears that corridor. A navigation graph
## constrains everyone to the corridor (no diagonal dodge), so the data layer plays like the real scene.
##
## "Spotted = caught": a guard locking onto an exposed party member fails the run (so does a charge hit).
## Concealment is the shared GameState hidden flag, so headless runs the same puzzle as real play.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")

const PARTY_IDS := ["aster", "peris", "endo"]
const SPAWNS := {
	"aster": Vector3(5.0, 0.5, 0.0),
	"peris": Vector3(4.0, 0.5, 1.0),
	"endo": Vector3(4.0, 0.5, -1.0),
}

const HALL_CENTER := Vector3(31.0, -0.05, 0.0)
const HALL_SIZE := Vector3(66.0, 0.1, 5.0)   # world x in [-2, 64]
const HALL_HALF_Z := 2.0                     # walkable half-width of the hallway
const OFFSHOOT_CENTER := Vector3(34.0, -0.05, -5.0)
const OFFSHOOT_SIZE := Vector3(5.0, 0.1, 6.0) # world z in [-8, -2]

# Off the corridor CENTERLINE (z != 0): the corridor nav nodes run along z=0, so a lure sitting exactly
# on a node made every walk-past route a path vertex straight through it — the lure read as a movement
# waypoint. Set against the hall's +z wall (well inside HALL_HALF_Z); guards/tend still snap to the
# nearest centerline node, so the puzzle is unchanged, but the path no longer pivots on the decoration.
const LURE1_POS := Vector3(10.0, 0.5, 0.9)   # first / near the entrance — FAR from the hide
const LURE2_POS := Vector3(40.0, 0.5, 0.9)   # second / near the enemies — CLOSE to the hide
const HIDE_POS := Vector3(34.0, 0.5, -5.0)
const HIDE_RADIUS := 2.4
const EXIT_X := 60.0
const GUARD_POSITIONS := [Vector3(50.0, 0.5, 0.0), Vector3(51.2, 0.5, 1.2), Vector3(51.2, 0.5, -1.2)]
const CORPSE_POS := Vector3(51.0, 0.0, 0.0)
const LURE_DURATION := 12.0       # scheduler ticks a guard stays drawn to a lure
const LURE_TEND_TIME := 2.5       # Peris tends a flure (after walking to it) before it sings out
const LURE_PICK_RADIUS := 0.8     # tight click target on the small flure, so a walk-past click misses it
const GUARD_SPEED := 4.5          # between a character's walk (~3.0) and run (6.0): threatening, escapable
const LURE_RELAY_AUTHORITY_VERSION := 3
const LURE_RELAY_AUTHORITY_KEY := "chunk:lure_relay:runtime"
const WIN_POLL_INTERVAL := 0.1

var _enemies: Array = []
var _phase := "ready"             # ready | active | complete | failed
var _failure_reason := ""
var _lure1_until := -1.0          # scheduler tick a lure stops drawing (<=0 = inactive)
var _lure2_until := -1.0
var _committed_lure := 0          # which lure the enemies are currently walking to (0 = none)
var _lure1: Flure = null
var _lure2: Flure = null
var _accepted_lure1_serial := 0
var _accepted_lure2_serial := 0
var _accepted_lure1_trigger_count := 0
var _accepted_lure2_trigger_count := 0
var _restoring_lure_relay_authority := false
var _win_poll_deadline := -1.0

# --- Build ---

func _build_chunk() -> void:
	_add_floor(self, HALL_CENTER, HALL_SIZE, Color(0.09, 0.1, 0.12))
	_add_floor(self, OFFSHOOT_CENTER, OFFSHOOT_SIZE, Color(0.08, 0.11, 0.1))
	_build_walls()
	_build_lure_bed("Lure1", LURE1_POS)
	_build_lure_bed("Lure2", LURE2_POS)
	_build_corpse()
	_add_label(self, "HIDE", HIDE_POS + Vector3(0.0, 1.6, 0.0), Color(0.5, 0.85, 0.7))
	_add_light(self, HIDE_POS + Vector3(0.0, 1.2, 0.0), Color(0.3, 0.6, 0.5), 0.7, 3.0)
	_add_light(self, Vector3(EXIT_X - 2.0, 1.5, 0.0), Color(0.8, 0.75, 0.6), 1.1, 5.0)
	_build_interactables()
	_spawn_guards()

func _build_walls() -> void:
	var wc := Color(0.06, 0.06, 0.08)
	var north_z := HALL_HALF_Z + 0.2
	var south_z := -HALL_HALF_Z - 0.2
	var min_x := HALL_CENTER.x - HALL_SIZE.x / 2.0
	var max_x := HALL_CENTER.x + HALL_SIZE.x / 2.0
	# North wall, solid the full length.
	_add_box(self, Vector3(HALL_CENTER.x, 1.4, north_z), Vector3(HALL_SIZE.x, 2.8, 0.3), wc)
	# South wall, broken by the offshoot mouth (a gap around the hide's x).
	var gap_min := OFFSHOOT_CENTER.x - OFFSHOOT_SIZE.x / 2.0
	var gap_max := OFFSHOOT_CENTER.x + OFFSHOOT_SIZE.x / 2.0
	var left_len := gap_min - min_x
	var right_len := max_x - gap_max
	_add_box(self, Vector3(min_x + left_len / 2.0, 1.4, south_z), Vector3(left_len, 2.8, 0.3), wc)
	_add_box(self, Vector3(gap_max + right_len / 2.0, 1.4, south_z), Vector3(right_len, 2.8, 0.3), wc)
	# Offshoot pocket walls (around the hide spot).
	var off_back_z := OFFSHOOT_CENTER.z - OFFSHOOT_SIZE.z / 2.0
	_add_box(self, Vector3(gap_min - 0.15, 1.4, OFFSHOOT_CENTER.z), Vector3(0.3, 2.8, OFFSHOOT_SIZE.z), wc)
	_add_box(self, Vector3(gap_max + 0.15, 1.4, OFFSHOOT_CENTER.z), Vector3(0.3, 2.8, OFFSHOOT_SIZE.z), wc)
	_add_box(self, Vector3(OFFSHOOT_CENTER.x, 1.4, off_back_z - 0.15), Vector3(OFFSHOOT_SIZE.x, 2.8, 0.3), wc)

func _build_lure_bed(node_name: String, pos: Vector3) -> void:
	_add_box(self, pos - Vector3(0.0, 0.42, 0.0), Vector3(1.4, 0.12, 1.2),
		Color(0.26, 0.17, 0.06), Color(0.95, 0.55, 0.12), 0.55,
		node_name + "Bed")

func _build_corpse() -> void:
	# Remains of a previous runner, slumped among the guards.
	_add_box(self, CORPSE_POS + Vector3(0.0, 0.12, 0.0), Vector3(1.4, 0.24, 0.5),
		Color(0.18, 0.14, 0.12), Color.BLACK, 0.0, "Remains")
	_add_label(self, "remains", CORPSE_POS + Vector3(0.0, 0.6, 0.0), Color(0.55, 0.4, 0.38))

# The lures are TIMED_ACTION interactables (CLICK to use, never proximity): with Peris active, a click
# walks her over, then she TENDS it for LURE_TEND_TIME (the interactable's own dwell timer, with the
# progress ring) before `interacted` fires and the lure sings. _add_object_interactable wraps each
# flure MESH in the shared outline+particle highlight, so the flure gets the hover outline and the
# click/active shimmer like any tutorial object (one OutlineFeedbackManager, no per-chunk divergence).
func _build_interactables() -> void:
	_lure2 = _build_physical_lure(
		"Lure2Interact", "lure_relay:far", LURE2_POS, 2)
	_lure1 = _build_physical_lure(
		"Lure1Interact", "lure_relay:near", LURE1_POS, 1)


func _build_physical_lure(
	node_name: String,
	source_authority_id: String,
	source_position: Vector3,
	which: int
) -> Flure:
	var gs = _get_game_state()
	if gs == null:
		return null
	var target_ids: Array = []
	var settle_positions := {}
	for index in range(GUARD_POSITIONS.size()):
		var target_id := "relay_guard_%d" % index
		target_ids.append(target_id)
		settle_positions[target_id] = source_position \
			+ Vector3(0.0, 0.0, float(index - 1) * 1.5)
	var flure: Flure = Flure.new()
	flure.name = node_name
	flure.authority_id = source_authority_id
	flure.configure(gs, source_position, target_ids, 64.0, LURE_PICK_RADIUS,
		Color(0.95, 0.62, 0.14))
	flure.required_character = "peris"
	flure.one_shot = true
	flure.interactable_type = Interactable.InteractableType.TIMED_ACTION
	flure.dwell_time = LURE_TEND_TIME
	flure.description = "Tend Flure %d" % which
	flure.tutorial_label = "TEND"
	flure.lure_duration = LURE_DURATION
	flure.allow_deferred_targets = true
	flure.set_target_settle_positions(settle_positions)
	flure.set_enemy_resolver(_resolve_relay_guard)
	flure.flure_activated.connect(_on_physical_lure_activated.bind(which))
	add_child(flure)
	return flure


func _resolve_relay_guard(target_id: String):
	for enemy in _enemies:
		if is_instance_valid(enemy) and str(enemy.char_id) == target_id:
			return enemy
	return null


func _spawn_guards() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for i in range(GUARD_POSITIONS.size()):
		var enemy := EnemyScript.new()
		enemy.name = "RelayGuard%d" % i
		enemy.position = GUARD_POSITIONS[i]
		enemy.move_speed = GUARD_SPEED
		# Reach 7.0 → distracted reach 2.8 (×0.4): wider than any lane the 4-unit hall offers, so an
		# EXPOSED head-on pass against the swarm is always caught (cell-based cooperative movement
		# side-steps ~2 units; 2.0 reach made the lure-1-only cheese slip by). The hidden offshoot
		# (full conceal) and the >9-unit standoffs in every intended beat keep their safety margins.
		enemy.detection_range = 7.0
		enemy._detection_targets.assign(PARTY_IDS)
		add_child(enemy)
		_register_enemy(enemy, "relay_guard_%d" % i, enemy.move_speed)
		# GUARDING = idle in place (no patrol → no roaming pathfinding); they only pathfind to chase.
		enemy.hit_target.connect(_on_guard_hit)
		enemy.target_spotted.connect(_on_guard_spotted)
		_enemies.append(enemy)

func _register_enemy(enemy, id: String, speed: float) -> void:
	var gs = _get_game_state()
	if gs == null or enemy == null:
		return
	enemy.char_id = id
	enemy.game_state = gs
	gs.register_character(id, enemy.position, speed, {"detection_range": float(enemy.detection_range)})
	if enemy.has_method("activate"):
		enemy.activate()

## Constrain everyone to the corridor + offshoot as a GRID footprint (cells carved from the hall and
## the hide pocket, walls everywhere else). Movement (player AND guards) routes on these cells, so
## there's no diagonal cut to the hide — the only path crosses the hall, which is what makes firing
## Lure 1 alone get you spotted. Cell-based A* means paths follow the open floor, never pivoting on
## decorations like the flures.
func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [-3.0, 0.0, -9.0],
		"cell_size": 1.0,
		"width": 68,
		"height": 12,
		"walkable_regions": [
			# The hall: full length, the walkable half-width inside the long walls.
			{"min": [-2.0, -HALL_HALF_Z], "max": [64.0, HALL_HALF_Z]},
			# The offshoot pocket down to the hide spot (inside its three walls).
			{"min": [32.0, -7.5], "max": [36.0, -HALL_HALF_Z]},
		],
	}

# --- Lure relay ---

func activate_lure2() -> bool:
	return false

func activate_lure1() -> bool:
	return false


## A chunk callback is presentation/coordination only. It accepts a song only when the reusable
## Flure proves a newer exact Peris source receipt and at least one owned applied/deferred target.
func _on_physical_lure_activated(_pulled: int, which: int) -> void:
	if _phase in ["complete", "failed"]:
		return
	var source: Flure = _lure_for(which)
	if source == null:
		return
	var effect: Dictionary = source.get_effect_state()
	var source_effect: Dictionary = effect.get("last_effect", {})
	var serial := int(effect.get("activation_serial", 0))
	var trigger_count := int(source_effect.get("source_trigger_count", 0))
	var accepted_serial := _accepted_serial_for(which)
	var accepted_trigger_count := _accepted_trigger_count_for(which)
	if str(effect.get("phase", "")) != Flure.PHASE_ACTIVE \
			or serial <= accepted_serial \
			or trigger_count <= accepted_trigger_count \
			or str(source_effect.get("source_actor", "")) != "peris" \
			or not _effect_has_relay_targets(source_effect):
		return
	_set_accepted_source_receipt(which, serial, trigger_count)
	_phase = "active"
	var pulled_ids: Array = source_effect.get("pulled_ids", [])
	if not pulled_ids.is_empty():
		_committed_lure = which
	_sync_relay_surface()
	var deadline := float(effect.get("end_tick", -1.0))
	_arm_relay_handoff(which, serial, deadline)
	_show_message("Flure %d sings out." % which, 1.4)
	_set_preview_step("lure_relay_active")
	_publish_lure_relay_authority()


func _effect_has_relay_targets(source_effect: Dictionary) -> bool:
	var receipts: Dictionary = source_effect.get("target_receipts", {})
	for target_id_v in receipts:
		var target_id := str(target_id_v)
		var status := str((receipts.get(target_id, {}) as Dictionary).get("status", ""))
		if target_id.begins_with("relay_guard_") and status in ["applied", "deferred"]:
			return true
	return false


func _accepted_serial_for(which: int) -> int:
	return _accepted_lure2_serial if which == 2 else _accepted_lure1_serial


func _accepted_trigger_count_for(which: int) -> int:
	return _accepted_lure2_trigger_count if which == 2 \
		else _accepted_lure1_trigger_count


func _set_accepted_source_receipt(which: int, serial: int, trigger_count: int) -> void:
	if which == 2:
		_accepted_lure2_serial = serial
		_accepted_lure2_trigger_count = trigger_count
	else:
		_accepted_lure1_serial = serial
		_accepted_lure1_trigger_count = trigger_count


func _lure_for(which: int) -> Flure:
	return _lure2 if which == 2 else _lure1


## This timer does not expire a song or move a guard. It merely observes the exact source's saved
## deadline after Flure/Enemy have enacted it, then asks the other still-physical song to claim the
## now-returning bodies under its original receipt.
func _arm_relay_handoff(which: int, activation_serial: int, deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null or activation_serial <= 0 or deadline < 0.0:
		return
	var tag := "lure_relay_handoff_%d" % which
	sched.cancel_tag(tag)
	sched.schedule_after(maxf(0.0, deadline - _get_scheduler_tick()),
		_on_lure_source_expired.bind(which, activation_serial, deadline), tag)


func _on_lure_source_expired(
	which: int,
	expected_serial: int,
	expected_deadline: float
) -> void:
	var source: Flure = _lure_for(which)
	if source == null:
		return
	var effect: Dictionary = source.get_effect_state()
	if int(effect.get("activation_serial", 0)) != expected_serial:
		return
	var source_phase := str(effect.get("phase", ""))
	if source_phase == Flure.PHASE_ACTIVE \
			and is_equal_approx(float(effect.get("end_tick", -1.0)), expected_deadline):
		# Parent/child restore order can arm this observer before the reusable Flure re-arms its own
		# same-tick callback. A tiny deterministic retry observes the physical transition; it does
		# not grant extra song time.
		var sched = _get_scheduler()
		if sched != null:
			sched.schedule_after(0.000001,
				_on_lure_source_expired.bind(which, expected_serial, expected_deadline),
				"lure_relay_handoff_%d" % which)
		return
	if _committed_lure == which:
		var other_which := 1 if which == 2 else 2
		var other_source: Flure = _lure_for(other_which)
		if other_source != null and other_source.claim_deferred_targets():
			_committed_lure = other_which
		else:
			_committed_lure = 0
	_sync_relay_surface()
	_publish_lure_relay_authority()


func _sync_relay_surface() -> void:
	_lure1_until = _physical_lure_deadline(_lure1)
	_lure2_until = _physical_lure_deadline(_lure2)


func _physical_lure_deadline(source: Flure) -> float:
	if source == null:
		return -1.0
	var effect: Dictionary = source.get_effect_state()
	return float(effect.get("end_tick", -1.0)) \
		if str(effect.get("phase", "")) in [Flure.PHASE_APPLYING, Flure.PHASE_ACTIVE] \
		and float(effect.get("end_tick", -1.0)) > _get_scheduler_tick() else -1.0

## The home post a guard returns to when it gives up a lure (its spawn slot).
func _guard_post_for(char_id: String) -> Vector3:
	for i in range(_enemies.size()):
		if is_instance_valid(_enemies[i]) and _enemies[i].char_id == char_id:
			return GUARD_POSITIONS[i]
	return GUARD_POSITIONS[0]

# --- Per-frame ---

func _process(delta: float) -> void:
	_update(delta)

func headless_process(delta: float) -> void:
	_update(delta)

func _update(_delta: float) -> void:
	if _phase in ["complete", "failed"]:
		return
	var gs = _get_game_state()
	if gs == null:
		return
	# Concealment: each party member tucked in the offshoot is hidden from detection.
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id):
			continue
		var pos := _get_character_position(char_id)
		var in_hide := Vector2(pos.x - HIDE_POS.x, pos.z - HIDE_POS.z).length() <= HIDE_RADIUS
		gs.set_character_hidden(char_id, in_hide)


func _start_win_poll() -> void:
	_arm_win_poll(_get_scheduler_tick() + WIN_POLL_INTERVAL)


func _arm_win_poll(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("lure_relay_win")
	_win_poll_deadline = deadline
	sched.schedule_after(maxf(0.0, deadline - _get_scheduler_tick()),
		_win_poll_tick, "lure_relay_win")


func _win_poll_tick() -> void:
	_win_poll_deadline = -1.0
	if _phase in ["complete", "failed"]:
		_publish_lure_relay_authority()
		return
	var gs = _get_game_state()
	if _phase == "active" and gs != null and _full_conscious_party_beyond_exit(gs):
		_complete()
		return
	_arm_win_poll(_get_scheduler_tick() + WIN_POLL_INTERVAL)
	_publish_lure_relay_authority()


func _full_conscious_party_beyond_exit(gs) -> bool:
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id) or gs.is_downed(char_id) \
				or _get_character_position(char_id).x < EXIT_X:
			return false
	return true

func _on_guard_spotted(target_id: String) -> void:
	# A sentry locking onto an exposed party member ends the run — this is the stealth fail that makes
	# firing Lure 1 alone (then crossing the swarmed corridor to the distant hide) a loss.
	if _phase in ["complete", "failed"]:
		return
	if not (target_id in PARTY_IDS):
		return
	_phase = "failed"
	_failure_reason = "spotted"
	_cancel_win_poll()
	_publish_lure_relay_authority()
	_show_note("A sentry's eye locks on. Caught.", 2.5)
	_set_preview_step("lure_relay_failed")

func _on_guard_hit(_target_id: String, _damage: float) -> void:
	if _phase in ["complete", "failed"]:
		return
	_phase = "failed"
	_failure_reason = "caught"
	_cancel_win_poll()
	_publish_lure_relay_authority()
	_show_note("A sentry ran you down. The remains gain a companion.", 2.5)
	_set_preview_step("lure_relay_failed")

func _complete() -> void:
	_phase = "complete"
	_cancel_win_poll()
	_publish_lure_relay_authority()
	_show_note("The whole party is past the sentries while the lure holds. The exit is yours.", 2.5)
	_set_preview_step("lure_relay_complete")


func _cancel_win_poll() -> void:
	_win_poll_deadline = -1.0
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("lure_relay_win")

# --- SceneChunk interface ---

func get_scene_title() -> String:
	return "Flure Relay"

func get_scene_help() -> String:
	return "Fire the far lure to clear the path, hide by it, then fire the near one — let the sentries relay past you and run the exit."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"lure_one": LURE1_POS,
		"lure_two": LURE2_POS,
		"hide_spot": HIDE_POS,
		"exit": Vector3(EXIT_X + 1.0, 0.5, 0.0),
		"guards": GUARD_POSITIONS[0],
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 2,
		"time": 0.62,
		"routing_mode": "safe",
		"note_default": "Two lures, one hiding spot, a guarded exit. Time the relay.",
	}

func get_preview_abilities() -> Array:
	return []

func get_preview_overlay_status(_overlay_id: String, _current_tick: float) -> Array:
	return []

func reset_preview_state() -> void:
	_phase = "ready"
	_failure_reason = ""
	_lure1_until = -1.0
	_lure2_until = -1.0
	_committed_lure = 0
	_accepted_lure1_serial = 0
	_accepted_lure2_serial = 0
	_accepted_lure1_trigger_count = 0
	_accepted_lure2_trigger_count = 0
	_cancel_win_poll()
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("lure_relay_handoff_1")
		sched.cancel_tag("lure_relay_handoff_2")
	if _lure1 != null:
		_lure1.reset_flure()
	if _lure2 != null:
		_lure2.reset_flure()
	var gs = _get_game_state()
	if gs != null:
		# A reset TELEPORTS the guards back to their posts (mid-play lure expiry returns through Enemy's
		# physical FSM — reset setup must not depend on that walk's timing or the puzzle premise
		# "sentries guard the exit" only holds whenever the previous attempt happened to end early).
		for enemy in _enemies:
			if is_instance_valid(enemy) and enemy.is_alive() and gs.characters.has(enemy.char_id):
				enemy.re_post(_guard_post_for(enemy.char_id))
		for char_id in PARTY_IDS:
			if gs.characters.has(char_id):
				gs.set_character_hidden(char_id, false)
	_start_win_poll()
	_publish_lure_relay_authority()
	_set_preview_step("lure_relay_briefing")


func _lure_relay_authority_state() -> Dictionary:
	return {
		"version": LURE_RELAY_AUTHORITY_VERSION,
		"phase": _phase,
		"failure_reason": _failure_reason,
		"lure1_until": _lure1_until,
		"lure2_until": _lure2_until,
		"committed_lure": _committed_lure,
		"accepted_lure1_serial": _accepted_lure1_serial,
		"accepted_lure2_serial": _accepted_lure2_serial,
		"accepted_lure1_trigger_count": _accepted_lure1_trigger_count,
		"accepted_lure2_trigger_count": _accepted_lure2_trigger_count,
		"win_poll_deadline": _win_poll_deadline,
	}


func _publish_lure_relay_authority() -> void:
	if _restoring_lure_relay_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(LURE_RELAY_AUTHORITY_KEY, _lure_relay_authority_state())


## Scheduler snapshots intentionally omit Callables. Rebuild only the relay observers from the exact
## physical source serial/deadline; Flure and Enemy restore their own windows and movement.
func on_game_state_snapshot_restored() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("lure_relay_handoff_1")
		sched.cancel_tag("lure_relay_handoff_2")
		sched.cancel_tag("lure_relay_win")
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(LURE_RELAY_AUTHORITY_KEY, null) \
			if gs != null and gs.has_method("get_world_state") else null
	if not raw is Dictionary or int(raw.get("version", 0)) != LURE_RELAY_AUTHORITY_VERSION:
		_retract_lure_relay_presenter()
		return

	var saved: Dictionary = raw
	_restoring_lure_relay_authority = true
	_phase = str(saved.get("phase", "ready"))
	if _phase not in ["ready", "active", "complete", "failed"]:
		_phase = "ready"
	_failure_reason = str(saved.get("failure_reason", ""))
	_lure1_until = float(saved.get("lure1_until", -1.0))
	_lure2_until = float(saved.get("lure2_until", -1.0))
	_committed_lure = int(saved.get("committed_lure", 0))
	_accepted_lure1_serial = maxi(0, int(saved.get("accepted_lure1_serial", 0)))
	_accepted_lure2_serial = maxi(0, int(saved.get("accepted_lure2_serial", 0)))
	_accepted_lure1_trigger_count = maxi(
		0, int(saved.get("accepted_lure1_trigger_count", 0)))
	_accepted_lure2_trigger_count = maxi(
		0, int(saved.get("accepted_lure2_trigger_count", 0)))
	_win_poll_deadline = float(saved.get("win_poll_deadline", -1.0))
	if _committed_lure not in [0, 1, 2]:
		_committed_lure = 0
	_restoring_lure_relay_authority = false
	_sync_relay_surface()
	_restore_relay_observer(1)
	_restore_relay_observer(2)
	if _phase not in ["complete", "failed"] and _win_poll_deadline >= 0.0:
		_arm_win_poll(_win_poll_deadline)


func _restore_relay_observer(which: int) -> void:
	var source: Flure = _lure_for(which)
	if source == null:
		return
	var effect: Dictionary = source.get_effect_state()
	var serial := int(effect.get("activation_serial", 0))
	var deadline := float(effect.get("end_tick", -1.0))
	if serial != _accepted_serial_for(which):
		return
	if str(effect.get("phase", "")) == Flure.PHASE_ACTIVE and deadline >= 0.0:
		_arm_relay_handoff(which, serial, deadline)
	elif _committed_lure == which:
		# A snapshot may land after Enemy/Flure publish their same-tick expiry but before this
		# coordinator consumes it. Resume that saved transaction instead of losing the handoff.
		var last_effect: Dictionary = effect.get("last_effect", {})
		var expired_deadline := float(last_effect.get("end_tick", -1.0))
		var sched = _get_scheduler()
		if sched != null and expired_deadline >= 0.0:
			sched.schedule_after(
				0.000001,
				_on_lure_source_expired.bind(which, serial, expired_deadline),
				"lure_relay_handoff_%d" % which)


func _retract_lure_relay_presenter() -> void:
	_restoring_lure_relay_authority = true
	_phase = "ready"
	_failure_reason = ""
	_lure1_until = -1.0
	_lure2_until = -1.0
	_committed_lure = 0
	_accepted_lure1_serial = 0
	_accepted_lure2_serial = 0
	_accepted_lure1_trigger_count = 0
	_accepted_lure2_trigger_count = 0
	_win_poll_deadline = -1.0
	_restoring_lure_relay_authority = false
	_start_win_poll()

func get_preview_state() -> Dictionary:
	var now := _get_scheduler_tick()
	var lure1_until: float = _physical_lure_deadline(_lure1)
	var lure2_until: float = _physical_lure_deadline(_lure2)
	return {
		"phase": _phase,
		"failure_reason": _failure_reason,
		"lure1_active": lure1_until > now,
		"lure2_active": lure2_until > now,
		"committed_lure": _committed_lure,
		"win_poll_deadline": _win_poll_deadline,
		"complete": _phase == "complete",
		"failed": _phase == "failed",
	}
