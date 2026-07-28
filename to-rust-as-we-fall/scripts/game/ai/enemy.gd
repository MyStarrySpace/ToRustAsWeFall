class_name Enemy
extends Node3D

## Scheduler-driven enemy state, HP, detection, and charge attacks.
## Override _build_visual() for variants.

# --- Configuration ---
@export var display_name := "Entity"
@export var color := Color(0.4, 0.15, 0.1)
## EMP is an electronics contract, not a universal enemy stun. Authored mechanical enemies opt in.
@export var emp_compatible := false
# Enemies never draw a movement-path ribbon (the PathRenderManager reads this opt-out). A yard full
# of roaming fauna tracing ribbons reads as chaos and costs per-frame ribbon rebuilds for nothing.
var show_movement_path := false
@export var max_hp := 50.0
@export var move_speed := 1.5
## Optional chase gear. A negative value preserves the legacy one-speed behavior; authored
## sentries can keep a slow, readable patrol beat while still becoming a real threat once they
## acquire somebody.
@export var pursuit_speed := -1.0
@export var detection_range := 6.0
@export var scan_interval := 0.5
@export var pursuit_update_interval := 0.8
## AI bodies use ordinary spatial A* by default. Cooperative space-time reservations are valuable for
## player formations, but make a roaming/pursuing crowd repeatedly solve around its own future paths.
## Opt a special single enemy back in only when non-overlap is itself part of the encounter.
@export var cooperative_navigation := false

@export var attack_range := 3.0
@export var pursuit_direct := false    # capped-hop pursuit (near-free short plans) for chase packs
@export var pursuit_hop := 5.0         # direct-pursuit hop length (wu) — short keeps the planner cheap
var pursuit_hop_resolver: Callable = Callable()   # scene-provided shared-field hop (crowd memoization)
## Optional scene-provided SAFE waypoint path for direct pursuit. Unlike
## command_move_to_pos(), this path is already spatially resolved and is
## committed verbatim through GameState's logged walk-path command, so a crowd
## never turns its shared flow-field answer back into one A* query per body.
var pursuit_path_resolver: Callable = Callable()
@export var roam_step_distance := 1.6  # how far a single roam hop travels
@export var roam_interval := 1.4       # scheduler ticks between roam hops
@export var alert_duration := 0.6      # spotting beat before the chase begins
@export var windup_duration := 0.8     # telegraph before the lunge
@export var charge_speed := 8.0
@export var charge_damage := 25.0
@export var charge_max_duration := 1.5
@export var lunge_gap := 0.6           # stop the lunge this far short of the target (no body-stacking)
@export var strike_reach := 1.4        # the scheduled impact only LANDS within this planar reach
@export var impact_duration := 0.14    # hitstop at the moment of connection
@export var recover_duration := 1.2    # cooldown after a strike (vulnerable window)
@export var stagger_duration := 0.5    # interrupt when the enemy itself is struck mid-aggro
@export var search_duration := 3.0     # how long to hunt at the last-known spot before giving up
@export var iframe_duration := 1.0
@export var pursuit_rescan_delay := 4.0  # Seconds of pursuit before scanning for new targets

# --- GameState integration (set by scene before adding to tree) ---
var game_state: GameState
var char_id := ""

# --- State machine (reusable scheduler-driven FSM) ---
var _fsm: StateMachine
var _state_tag := ""
var _hp: float

# --- Detection ---
var _detection_targets: Array[String] = []
var _current_target_id := ""
var _alert_label: Label3D
var _last_known_target_pos := Vector3.ZERO

# --- Ambient "home" the enemy returns to after losing a target ("idle" | "roam" | "patrol") ---
var _home_mode := "idle"
## The POST an idle-home enemy returns to after a chase (captured at activate). Roam homes to its
## anchor and patrol resumes its beat; a standing guard walks back HERE — without this, an idle
## enemy "returned" to wherever the chase ended and never re-manned its post.
var _post_position := Vector3.ZERO

# --- Patrol (authored routes) ---
var _patrol_waypoints: Array[Vector3] = []
var _patrol_index := 0

# --- Lure (a flure's song: walk to the settle point, park distracted, then walk home) ---
var _lure_settle := Vector3.ZERO
var _lure_duration := 20.0
## Most Flures restore the full watch as soon as their song ends. A composition whose safe
## start overlaps the flower may instead keep the reduced watch until the enemy physically
## finishes its ordinary RETURN state. This is a reusable Enemy policy, not a chunk timer.
var lure_return_keeps_distraction := false
## Optional return gear for a visible race home. Negative means the authored ambient speed.
var lure_return_speed := -1.0
var _lure_returning_from_song := false
## Exact Flure provenance for retiming a target-settled song.
var _lure_source_key := ""
var _lure_source_activation_serial := 0

# --- Roam (undirected wander: cheap local hops, NEVER pathfinding) ---
var _roam_anchor := Vector3.ZERO
var _roam_radius := 0.0
var _roam_heading := Vector3(0.0, 0.0, -1.0)  # current wander direction
var _roam_seq := 0                            # deterministic hop counter (fast-forward invariant)
## Ambient actors that enter roam together must not all invalidate movement/detection on the same
## scheduler frame forever. Each scheduler owns deterministic cadence lanes. An enemy prefers a
## stable char-id-derived lane and collision-probes to the next free one, so a cohort's first hop
## and every repeated hop stay separated without wall-clock randomness.
const _ROAM_CADENCE_LANE_COUNT := 64
const _ROAM_CADENCE_MIN_INTERVAL := 0.01
static var _roam_cadence_owners: Dictionary = {}  # scheduler instance id -> {lane: enemy instance id}
var _roam_cadence_scheduler_id := 0
var _roam_cadence_lane := -1
var _roam_cadence_identity := ""

# --- Attack cycle ---
# The lunge is a REAL data-layer move at charge_speed (logged → replay-safe, visual follows via the
# _process sync), so the strike never teleports. _charging / _charge_hit / _charge_target_pos are the
# contract ChainEnemy reads (its segments deal contact damage during the same charge window).
var _charge_target_pos := Vector3.ZERO
var _charging := false
var _charge_hit := false

# --- Save/load authority ---
# EventScheduler snapshots intentionally do not serialize Callables. Every gameplay-relevant enemy
# phase therefore publishes its stable context and absolute callback deadlines into GameState. The
# node and StateMachine are presenters rebuilt from that record after a snapshot replaces GameState.
const ENEMY_AUTHORITY_VERSION := 1
const ENEMY_AUTHORITY_PREFIX := "runtime:enemy:"
const _RESTORE_TIMER_EPSILON := 0.000001
const _TIMER_KIND_ORDER := [
	"roam_step", "patrol_step", "lure_end", "alert_end", "pursuit_update",
	"pursuit_rescan", "windup_end", "charge_end", "impact_end", "recover_end",
	"stagger_end", "stun_end", "search_end", "return_end",
]
var _state_deadlines: Dictionary = {}       # timer kind -> absolute scheduler tick
var _restoring_enemy_authority := false
var _enemy_authority_initialized := false

# --- Visual ---
var _mesh: MeshInstance3D
var _eye_left: OmniLight3D
var _eye_right: OmniLight3D
var _base_color: Color
var _threat_marker: Node3D
var _threat_marker_material: StandardMaterial3D

signal damaged(amount: float, new_hp: float)
signal died()
signal target_spotted(target_id: String)
signal hit_target(target_id: String, damage: float)

func _ready() -> void:
	_hp = max_hp
	_base_color = color
	_state_tag = "enemy_%s" % name
	_build_visual()
	_build_threat_marker()
	_build_fsm()

# --- Public API ---

## Start after game_state and char_id are set.
func activate() -> void:
	if get_state() == "dead":
		return
	# The FSM was built in _ready, possibly before game_state (chunks assign it after add_child). Now
	# that the scheduler exists, point the FSM at it so timed transitions / per-state schedules fire.
	if _fsm != null:
		_fsm.set_scheduler(_get_scheduler())
	if game_state and not game_state.detection_predicted.is_connected(_on_detection_predicted):
		game_state.detection_predicted.connect(_on_detection_predicted)
	if game_state != null:
		if game_state.has_method("set_coop_exempt"):
			game_state.set_coop_exempt(char_id, not cooperative_navigation)
	# A freshly-instanced scene may be attached after GameState was deserialized. Do not let the
	# presenter's default idle detector emit a synthetic spot or overwrite the saved phase before the
	# sequence's attachment pass. The restore path publishes the saved detection roster under a guard.
	if _has_saved_enemy_authority():
		on_game_state_snapshot_restored()
		return
	_publish_detection_targets()
	_sync_detection_subscription(get_state())
	_post_position = _self_pos()
	_fsm.transition_to("idle")
	_enemy_authority_initialized = true
	_publish_enemy_authority()

## The FSM publishes a narrow detector->target subscription to GameState. Callers should use this
## instead of mutating _detection_targets after activation so prediction is invalidated immediately.
func set_detection_targets(target_ids: Array) -> void:
	var normalized: Array[String] = []
	for raw_id in target_ids:
		var target_id := str(raw_id)
		if target_id == char_id or normalized.has(target_id):
			continue
		normalized.append(target_id)
	_detection_targets = normalized
	_publish_detection_targets()
	_publish_enemy_authority()


## Retire an authored watch after its protected causal boundary is crossed. The reusable FSM owns
## disengagement and serializes the resulting RETURN phase; scenes do not mutate private state.
func retire_watch_to_post() -> void:
	set_detection_targets([])
	if get_state() == "dead":
		return
	_current_target_id = ""
	_lure_returning_from_song = false
	_lure_source_key = ""
	_lure_source_activation_serial = 0
	if get_state() in [
		"alert", "pursuit", "windup", "charge", "impact", "recover", "search",
	]:
		_fsm.transition_to("return")
	else:
		_publish_enemy_authority()


func get_detection_targets() -> Array[String]:
	return _detection_targets.duplicate()

func _publish_detection_targets() -> void:
	if game_state != null and game_state.has_method("set_detection_targets") \
			and game_state.characters.has(char_id):
		game_state.set_detection_targets(char_id, _detection_targets)

## Set patrol waypoints (an AUTHORED route — pathfinds between waypoints to route around walls).
func set_patrol(waypoints: Array[Vector3]) -> void:
	configure_patrol(waypoints)
	begin_home_behavior()

## Configure a patrol without immediately planning its first leg. Encounter loaders use this to
## register a dormant pack cheaply, then start only the cohort whose causal boundary was crossed.
func configure_patrol(waypoints: Array[Vector3]) -> void:
	_patrol_waypoints = waypoints.duplicate()
	_patrol_index = 0
	_home_mode = "patrol"
	_publish_enemy_authority()

func begin_home_behavior() -> void:
	if get_state() != "dead":
		match _home_mode:
			"patrol":
				_fsm.transition_to("patrol")
			"roam":
				_fsm.transition_to("roam")
			_:
				_fsm.transition_to("idle")
	_publish_enemy_authority()

## Begin lightweight roaming around `anchor` within `radius`. Roaming NEVER pathfinds: it's a local
## deterministic wander — short straight hops (command_move_to_pos), an anchor-pull at the circle's
## edge, and a cheap single-cell wall bounce on grid scenes — so a yard full of idle enemies costs
## almost nothing. Only an actual sighting promotes to pursuit, and ONLY pursuit pathfinds.
func set_roam(anchor: Vector3, radius: float) -> void:
	_roam_anchor = anchor
	_roam_radius = maxf(0.5, radius)
	_roam_seq = 0
	_home_mode = "roam"
	if get_state() != "dead":
		_fsm.transition_to("roam")
	_publish_enemy_authority()

const LURE_ACCEPTING_STATES := ["idle", "roam", "patrol", "search", "return"]
const LURE_COMMITTED_STATES := ["alert", "pursuit", "windup", "charge", "impact"]

## Report why a Flure can or cannot redirect this enemy. Keeping this classification on the reusable
## enemy FSM lets any puzzle distinguish a bad causal prediction from a signal fired too late.
func get_lure_availability() -> String:
	var state := get_state()
	if state in LURE_ACCEPTING_STATES:
		return "available"
	if state in LURE_COMMITTED_STATES:
		return "committed"
	if state == "dead":
		return "dead"
	if state == "lured":
		return "already_lured"
	return "unavailable"

## A flure's song: pull this enemy off its watch to `settle_pos` for `duration` seconds. Only an
## un-alerted enemy takes the bait (one mid-attack ignores it; an already-lured one stays lured).
## While lured it is DISTRACTED — its own outer reach shrinks, but a runner who crowds it still gets
## caught — and when the song ends it walks home and resumes its ambient mode.
## Scenario setup for how the physical return leg behaves after a Flure releases this enemy.
## Changing the policy never moves, distracts, or transitions the body.
func set_lure_return_policy(keep_distraction: bool, return_speed := -1.0) -> void:
	lure_return_keeps_distraction = keep_distraction
	lure_return_speed = return_speed
	_publish_enemy_authority()


func lure_to(settle_pos: Vector3, duration: float, source_context := {}) -> bool:
	if get_lure_availability() != "available":
		return false
	_lure_settle = settle_pos
	_lure_duration = maxf(0.5, duration)
	_lure_returning_from_song = false
	_lure_source_key = str(source_context.get("source_key", "")) \
		if source_context is Dictionary else ""
	_lure_source_activation_serial = int(source_context.get("activation_serial", 0)) \
		if source_context is Dictionary else 0
	_fsm.transition_to("lured")
	return get_state() == "lured"


## A target-settled Flure may replace its transit failsafe with the authored hold window. The
## source key, activation serial, and physical settle point must match the active lure exactly.
func retime_lure_from_source(
	source_key: String,
	activation_serial: int,
	settle_pos: Vector3,
	remaining: float
) -> bool:
	if get_state() != "lured" \
			or source_key.is_empty() \
			or source_key != _lure_source_key \
			or activation_serial <= 0 \
			or activation_serial != _lure_source_activation_serial \
			or settle_pos.distance_to(_lure_settle) > 0.05:
		return false
	_lure_duration = maxf(0.5, remaining)
	_schedule_enemy_timer(_lure_duration, "lure_end", _end_lure)
	_publish_enemy_authority()
	return true


func _end_lure() -> void:
	if get_state() != "lured":
		return
	_lure_returning_from_song = true
	_fsm.transition_to("return")

## Snap back to a post and stand the watch again (level reset / wipe restart): clears the target and
## any lure/distraction, re-parks the data-layer body, and resumes the ambient home mode from the top.
func re_post(post: Vector3) -> void:
	if get_state() == "dead":
		return
	_current_target_id = ""
	_lure_returning_from_song = false
	_lure_source_key = ""
	_lure_source_activation_serial = 0
	if game_state and game_state.characters.has(char_id):
		game_state.command_stop(char_id)
		game_state.change_move_speed(char_id, move_speed)
		game_state.set_character_distracted(char_id, false)
		game_state.snap_character_to(char_id, post)
	position = post
	_patrol_index = 0
	_fsm.transition_to("idle")   # clean re-entry even if the home mode is the current state
	match _home_mode:
		"patrol":
			_fsm.transition_to("patrol")
		"roam":
			_fsm.transition_to("roam")
	_publish_enemy_authority()

## Apply damage. A hit taken mid-aggro staggers the enemy (a brief interrupt → counterplay), so the
## player can break a windup/charge by striking first.
## Freeze the enemy in place for `duration` (the Hushbloom stun / Tyreg's Suppress): a hard hold
## that cancels movement and scanning, then re-evaluates like a stagger.
func stun(duration: float) -> void:
	if get_state() == "dead":
		return
	_stun_duration = maxf(0.0, duration)
	# StateMachine self-transitions are intentionally no-ops. A second stun is nevertheless a real
	# refresh: replace its one deadline instead of changing only a local duration that save/load could
	# never observe.
	if get_state() == "stunned":
		_fsm.cancel_pending()
		_state_deadlines.clear()
		_schedule_enemy_timer(_stun_duration, "stun_end", _after_stun)
		return
	_fsm.transition_to("stunned")

func apply_emp(duration: float) -> bool:
	if not emp_compatible or get_state() == "dead" or duration <= 0.0:
		return false
	stun(duration)
	return true

func is_stunned() -> bool:
	return get_state() == "stunned"

var _stun_duration := 3.0

func take_damage(amount: float) -> void:
	if get_state() == "dead":
		return
	_hp = maxf(0.0, _hp - amount)
	damaged.emit(amount, _hp)
	if _hp <= 0:
		die()
		return
	if get_state() in ["alert", "pursuit", "windup", "charge", "impact", "recover"]:
		_fsm.transition_to("stagger")
	else:
		_publish_enemy_authority()

## Kill immediately.
func die() -> void:
	_fsm.transition_to("dead")

func is_alive() -> bool:
	return _hp > 0

func get_hp() -> float:
	return _hp

func get_state() -> String:
	return _fsm.current() if _fsm != null else ""

# --- Authoritative enemy snapshot contract ---

func _enemy_authority_key() -> String:
	return ENEMY_AUTHORITY_PREFIX + char_id if char_id != "" else ""

func _has_saved_enemy_authority() -> bool:
	if game_state == null or not game_state.has_method("get_world_state"):
		return false
	var key := _enemy_authority_key()
	if key == "":
		return false
	var saved: Variant = game_state.get_world_state(key, {})
	return saved is Dictionary \
			and int(saved.get("version", 0)) == ENEMY_AUTHORITY_VERSION \
			and str(saved.get("char_id", char_id)) == char_id

func _publish_enemy_authority() -> void:
	if _restoring_enemy_authority or not _enemy_authority_initialized:
		return
	if game_state == null or not game_state.has_method("set_world_state"):
		return
	var key := _enemy_authority_key()
	if key == "":
		return
	var waypoint_data: Array = []
	for waypoint in _patrol_waypoints:
		waypoint_data.append(_vec3_to_data(waypoint))
	var deadline_data := {}
	for kind in _TIMER_KIND_ORDER:
		if _state_deadlines.has(kind):
			deadline_data[kind] = float(_state_deadlines[kind])
	game_state.set_world_state(key, {
		"version": ENEMY_AUTHORITY_VERSION,
		"char_id": char_id,
		"hp": _hp,
		"state": get_state(),
		"deadlines": deadline_data,
		"detection_targets": _detection_targets.duplicate(),
		"current_target_id": _current_target_id,
		"last_known_target_pos": _vec3_to_data(_last_known_target_pos),
		"home_mode": _home_mode,
		"post_position": _vec3_to_data(_post_position),
		"patrol_waypoints": waypoint_data,
		"patrol_index": _patrol_index,
		"lure_settle": _vec3_to_data(_lure_settle),
		"lure_duration": _lure_duration,
		"lure_return_keeps_distraction": lure_return_keeps_distraction,
		"lure_return_speed": lure_return_speed,
		"lure_returning_from_song": _lure_returning_from_song,
		"lure_source_key": _lure_source_key,
		"lure_source_activation_serial": _lure_source_activation_serial,
		"roam_anchor": _vec3_to_data(_roam_anchor),
		"roam_radius": _roam_radius,
		"roam_heading": _vec3_to_data(_roam_heading),
		"roam_seq": _roam_seq,
		"stun_duration": _stun_duration,
		"charge_target_pos": _vec3_to_data(_charge_target_pos),
		"charging": _charging,
		"charge_hit": _charge_hit,
	})

## Reattach this presenter after GameState and its scheduler clock have been replaced by a save.
## This path never calls a gameplay entry hook: in particular, loading `impact` cannot deal damage,
## loading `charge` cannot issue a second movement command, and loading `dead` cannot re-emit death.
func on_game_state_snapshot_restored() -> void:
	if _fsm == null:
		return
	if not _has_saved_enemy_authority():
		_restore_uncommitted_enemy_presenter()
		return
	var saved: Dictionary = game_state.get_world_state(_enemy_authority_key(), {})
	var restored_state := str(saved.get("state", "idle"))
	if restored_state not in ENEMY_STATES:
		return

	_restoring_enemy_authority = true
	_fsm.set_scheduler(_get_scheduler())
	_fsm.cancel_pending()
	_state_deadlines.clear()
	_remove_alert_label()
	_kill_enemy_presentation_tweens()

	_hp = clampf(float(saved.get("hp", max_hp)), 0.0, max_hp)
	if restored_state == "dead":
		_hp = 0.0
	_current_target_id = str(saved.get("current_target_id", ""))
	_last_known_target_pos = _vec3_from_data(
		saved.get("last_known_target_pos", []), Vector3.ZERO)
	_home_mode = str(saved.get("home_mode", "idle"))
	if _home_mode not in ["idle", "roam", "patrol"]:
		_home_mode = "idle"
	_post_position = _vec3_from_data(saved.get("post_position", []), _self_pos())
	_patrol_waypoints.clear()
	for waypoint_data in (saved.get("patrol_waypoints", []) as Array):
		_patrol_waypoints.append(_vec3_from_data(waypoint_data, Vector3.ZERO))
	_patrol_index = clampi(
		int(saved.get("patrol_index", 0)), 0, maxi(0, _patrol_waypoints.size() - 1))
	_lure_settle = _vec3_from_data(saved.get("lure_settle", []), Vector3.ZERO)
	_lure_duration = maxf(0.5, float(saved.get("lure_duration", 20.0)))
	lure_return_keeps_distraction = bool(saved.get(
		"lure_return_keeps_distraction", lure_return_keeps_distraction))
	lure_return_speed = float(saved.get("lure_return_speed", lure_return_speed))
	_lure_returning_from_song = bool(saved.get("lure_returning_from_song", false))
	_lure_source_key = str(saved.get("lure_source_key", ""))
	_lure_source_activation_serial = int(saved.get("lure_source_activation_serial", 0))
	_roam_anchor = _vec3_from_data(saved.get("roam_anchor", []), Vector3.ZERO)
	_roam_radius = maxf(0.0, float(saved.get("roam_radius", 0.0)))
	_roam_heading = _vec3_from_data(
		saved.get("roam_heading", []), Vector3(0.0, 0.0, -1.0))
	_roam_seq = maxi(0, int(saved.get("roam_seq", 0)))
	_stun_duration = maxf(0.0, float(saved.get("stun_duration", 3.0)))
	_charge_target_pos = _vec3_from_data(saved.get("charge_target_pos", []), Vector3.ZERO)
	_charging = bool(saved.get("charging", restored_state == "charge"))
	_charge_hit = bool(saved.get("charge_hit", false))

	_detection_targets.clear()
	for target_v in (saved.get("detection_targets", []) as Array):
		var target_id := str(target_v)
		if target_id != char_id and not _detection_targets.has(target_id):
			_detection_targets.append(target_id)

	_fsm.force_current(restored_state)
	_sync_enemy_presenter_position()
	_restore_enemy_presentation(restored_state)
	_publish_detection_targets()
	_sync_detection_subscription(restored_state)

	var saved_deadlines: Dictionary = saved.get("deadlines", {})
	for kind in _TIMER_KIND_ORDER:
		if not saved_deadlines.has(kind) or not _timer_belongs_to_state(kind, restored_state):
			continue
		_rearm_enemy_timer(kind, float(saved_deadlines[kind]))
	_restoring_enemy_authority = false
	_enemy_authority_initialized = true

## Absence is authoritative too. This covers rolling back to a snapshot taken before a registered
## enemy was activated: retaining its later windup/death state after the callback heap was cleared
## would freeze a future phase in the past. Scene/chunk authority still owns whether a dormant node
## is enabled; Enemy only retracts the runtime phase it can prove did not yet exist.
func _restore_uncommitted_enemy_presenter() -> void:
	_restoring_enemy_authority = true
	_fsm.set_scheduler(_get_scheduler())
	_fsm.cancel_pending()
	_state_deadlines.clear()
	_remove_alert_label()
	_kill_enemy_presentation_tweens()
	_hp = max_hp
	_current_target_id = ""
	_last_known_target_pos = Vector3.ZERO
	_charge_target_pos = Vector3.ZERO
	_charging = false
	_charge_hit = false
	_lure_returning_from_song = false
	_lure_source_key = ""
	_lure_source_activation_serial = 0
	_fsm.force_current("idle")
	_sync_enemy_presenter_position()
	_restore_enemy_presentation("idle")
	if game_state != null and game_state.characters.has(char_id):
		game_state.set_character_distracted(char_id, false)
		if game_state.has_method("set_detection_enabled"):
			game_state.set_detection_enabled(char_id, false)
	_restoring_enemy_authority = false
	_enemy_authority_initialized = false

func _schedule_enemy_timer(delay: float, kind: String, callback: Callable) -> void:
	var scheduler := _get_scheduler()
	if scheduler == null or _fsm == null or not callback.is_valid():
		return
	var deadline := scheduler.get_current_tick() + maxf(0.0, delay)
	_state_deadlines[kind] = deadline
	_fsm.schedule(maxf(0.0, delay), _run_enemy_timer.bind(kind, deadline, callback))
	_publish_enemy_authority()

func _rearm_enemy_timer(kind: String, deadline: float) -> void:
	var scheduler := _get_scheduler()
	var callback := _enemy_timer_callback(kind)
	if scheduler == null or _fsm == null or not callback.is_valid():
		return
	_state_deadlines[kind] = deadline
	var remaining := maxf(_RESTORE_TIMER_EPSILON, deadline - scheduler.get_current_tick())
	_fsm.schedule(remaining, _run_enemy_timer.bind(kind, deadline, callback))

func _run_enemy_timer(kind: String, deadline: float, callback: Callable) -> void:
	# Re-arming a kind supersedes its prior callback even if a bespoke caller failed to cancel the tag.
	if not _state_deadlines.has(kind) \
			or not is_equal_approx(float(_state_deadlines[kind]), deadline):
		return
	_state_deadlines.erase(kind)
	if callback.is_valid():
		callback.call()
	_publish_enemy_authority()

func _enemy_timer_callback(kind: String) -> Callable:
	match kind:
		"roam_step": return Callable(self, "_roam_step")
		"patrol_step": return Callable(self, "_patrol_next_waypoint")
		"lure_end": return Callable(self, "_end_lure")
		"alert_end": return Callable(self, "_begin_pursuit")
		"pursuit_update": return Callable(self, "_pursue_target")
		"pursuit_rescan": return Callable(self, "_begin_search")
		"windup_end": return Callable(self, "_begin_charge")
		"charge_end": return Callable(self, "_end_charge")
		"impact_end": return Callable(self, "_begin_recover")
		"recover_end": return Callable(self, "_after_recover")
		"stagger_end": return Callable(self, "_after_stagger")
		"stun_end": return Callable(self, "_after_stun")
		"search_end": return Callable(self, "_begin_return")
		"return_end": return Callable(self, "_resume_home")
	return Callable()

func _timer_belongs_to_state(kind: String, state: String) -> bool:
	match state:
		"roam": return kind == "roam_step"
		"patrol": return kind == "patrol_step"
		"lured": return kind == "lure_end"
		"alert": return kind == "alert_end"
		"pursuit": return kind in ["pursuit_update", "pursuit_rescan"]
		"windup": return kind == "windup_end"
		"charge": return kind == "charge_end"
		"impact": return kind == "impact_end"
		"recover": return kind == "recover_end"
		"stagger": return kind == "stagger_end"
		"stunned": return kind == "stun_end"
		"search": return kind == "search_end"
		"return": return kind == "return_end"
	return false

func _restore_enemy_presentation(state: String) -> void:
	visible = state != "dead"
	if _mesh != null:
		_mesh.transparency = 0.0 if state != "dead" else 1.0
	_set_mesh_color(_base_color)
	match state:
		"idle":
			_set_eye_energy(0.4)
		"roam", "patrol", "return":
			_set_eye_energy(0.5)
		"lured":
			_set_eye_energy(0.9)
		"alert":
			_set_eye_energy(1.6)
			_show_alert_on_target()
		"pursuit":
			_set_eye_energy(2.0)
		"windup", "charge":
			_set_mesh_color(WINDUP_COLOR)
			_set_eye_energy(3.0)
		"impact":
			_set_mesh_color(IMPACT_COLOR)
			_set_eye_energy(3.0)
		"recover":
			_set_mesh_color(RECOVER_COLOR)
			_set_eye_energy(0.8)
		"stagger":
			_set_mesh_color(STAGGER_COLOR)
			_set_eye_energy(0.5)
		"stunned":
			_set_mesh_color(Color(0.82, 0.78, 0.9))
			_set_eye_energy(0.0)
		"search":
			_set_eye_energy(1.0)
		"dead":
			_set_eye_energy(0.0)

func _sync_enemy_presenter_position() -> void:
	if game_state == null or not game_state.characters.has(char_id):
		return
	var restored_pos := game_state.get_render_position(char_id)
	if game_state.coord_map != null or game_state.is_external_traversal_active(char_id):
		global_position = restored_pos
	else:
		global_position = Vector3(restored_pos.x, global_position.y, restored_pos.z)

func _kill_enemy_presentation_tweens() -> void:
	for tween in [_anim_tween, _flash_tween, _recover_tween, _fade_tween]:
		if tween != null and tween.is_valid():
			tween.kill()

static func _vec3_to_data(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _vec3_from_data(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

# --- State Machine Core (reusable StateMachine: tag-scoped scheduling + exit/enter hooks) ---

const ENEMY_STATES := ["idle", "roam", "patrol", "lured", "alert", "pursuit", "windup", "charge", "impact", "recover", "stagger", "stunned", "search", "return", "dead"]
const DETECTION_SCANNING_STATES := ["idle", "roam", "patrol", "lured", "search", "return"]

# Telegraph colours (the body reads its intent at a glance).
const WINDUP_COLOR := Color(0.9, 0.15, 0.1)    # red — about to strike
const IMPACT_COLOR := Color(1.0, 0.85, 0.5)    # flash on connection
const RECOVER_COLOR := Color(0.2, 0.3, 0.7)    # blue — vulnerable cooldown
const STAGGER_COLOR := Color(0.85, 0.7, 0.2)   # yellow — interrupted

func _build_fsm() -> void:
	_fsm = StateMachine.new(_get_scheduler(), _state_tag)
	for state_name in ENEMY_STATES:
		_fsm.add_state(state_name, _enter_state.bind(state_name), _exit_state.bind(state_name))
	_fsm.start("idle")  # default state before activate() (idle's enter is a no-op)

## Force a state directly. Prefer letting the FSM drive transitions; this exists for external
## resets (showcase / test harnesses) that pin an enemy back to a known state.
func _change_state(new_state: String) -> void:
	if _fsm != null:
		_fsm.transition_to(new_state)

static var CALLS := {}   # diagnostic counters (no wall-clock; cleared by the perf probe)
static func _count(key: String) -> void:
	CALLS[key] = int(CALLS.get(key, 0)) + 1

func _sync_detection_subscription(state: String) -> void:
	if game_state != null and game_state.has_method("set_detection_enabled") \
			and game_state.characters.has(char_id):
		game_state.set_detection_enabled(char_id, state in DETECTION_SCANNING_STATES)

func _enter_state(state: String) -> void:
	# StateMachine cancels the old tag before entering. Mirror that cancellation in the serializable
	# deadline registry before the new phase arms its own work.
	_state_deadlines.clear()
	Enemy._count("enter_" + state)
	_publish_detection_targets()
	_sync_detection_subscription(state)
	match state:
		"idle":
			_set_eye_energy(0.4)
		"roam":
			_set_eye_energy(0.5)
			_schedule_first_roam_step()
		"patrol":
			_set_eye_energy(0.5)
			_patrol_next_waypoint()
		"lured":
			_current_target_id = ""
			_remove_alert_label()
			_set_eye_energy(0.9)
			_set_mesh_color(_base_color)
			if game_state and game_state.characters.has(char_id):
				game_state.set_character_distracted(char_id, true)
				game_state.command_move_to_pos(char_id, _lure_settle)
			_schedule_enemy_timer(_lure_duration, "lure_end", _end_lure)
		"alert":
			_show_alert_on_target()
			_set_eye_energy(1.6)
			_anim_pop(1.18)
			_schedule_enemy_timer(alert_duration, "alert_end", _begin_pursuit)
		"pursuit":
			if game_state != null and game_state.characters.has(char_id):
				game_state.change_move_speed(char_id, get_pursuit_speed())
			_set_eye_energy(2.0)
			_set_mesh_color(_base_color)
			_pursue_target()
			if get_state() == "pursuit" and pursuit_rescan_delay > 0:
				_schedule_enemy_timer(pursuit_rescan_delay, "pursuit_rescan", _begin_search)
		"windup":
			_stop_movement()
			_set_mesh_color(WINDUP_COLOR)
			_set_eye_energy(3.0)
			_anim_squash()  # crouch/anticipation
			_schedule_enemy_timer(windup_duration, "windup_end", _begin_charge)
		"charge":
			_begin_lunge()
		"impact":
			var impact_started := PerformanceTrace.begin()
			var strike_started := PerformanceTrace.begin()
			_apply_strike()
			PerformanceTrace.end(&"update", &"enemy.impact.strike", strike_started, char_id, 1)
			var presentation_started := PerformanceTrace.begin()
			_set_mesh_color(IMPACT_COLOR)
			_anim_punch()
			_schedule_enemy_timer(impact_duration, "impact_end", _begin_recover)
			PerformanceTrace.end(&"draw", &"enemy.impact.presentation", presentation_started, char_id, 1)
			PerformanceTrace.end(&"update", &"enemy.impact.enter", impact_started, char_id, 1)
		"recover":
			_charging = false
			_stop_movement()
			_set_mesh_color(RECOVER_COLOR)
			_set_eye_energy(0.8)
			_anim_settle()
			# Cosmetic fade blue -> base over the cooldown (never gates the transition).
			if _mesh and _mesh.material_override and Enemy._cosmetics_on():
				if _recover_tween != null and _recover_tween.is_valid():
					_recover_tween.kill()
				_recover_tween = create_tween()
				_recover_tween.tween_method(_set_mesh_color, RECOVER_COLOR, _base_color, recover_duration)
			_schedule_enemy_timer(recover_duration, "recover_end", _after_recover)
		"stagger":
			_charging = false
			_stop_movement()
			_set_mesh_color(STAGGER_COLOR)
			_set_eye_energy(0.5)
			_anim_recoil()
			_schedule_enemy_timer(stagger_duration, "stagger_end", _after_stagger)
		"stunned":
			# The Hushbloom's verb (flora_taxonomy): a full neuroactive freeze — no movement, no
			# scans (the detection gate never admits "stunned"), held for the burst's duration.
			_charging = false
			_stop_movement()
			_set_mesh_color(Color(0.82, 0.78, 0.9))
			_set_eye_energy(0.0)
			_anim_recoil()
			_schedule_enemy_timer(_stun_duration, "stun_end", _after_stun)
		"search":
			_set_eye_energy(1.0)
			_set_mesh_color(_base_color)
			_begin_search_move()
			_schedule_enemy_timer(search_duration, "search_end", _begin_return)
		"return":
			_set_eye_energy(0.5)
			_set_mesh_color(_base_color)
			if _lure_returning_from_song and lure_return_speed > 0.0 \
					and game_state != null and game_state.characters.has(char_id):
				game_state.change_move_speed(char_id, lure_return_speed)
			_begin_return_move()
		"dead":
			_charging = false
			_stop_movement()
			_set_eye_energy(0.0)
			died.emit()
			_fade_out(1.5)
	_publish_enemy_authority()

func _exit_state(state: String) -> void:
	match state:
		"roam":
			_stop_movement()
		"lured":
			# However the song ends (expiry -> return, or a point-blank spot -> alert), the
			# walk-to-settle stops. A scenario may keep the reduced watch only for the
			# physical RETURN leg; every other exit lifts it.
			_stop_movement()
			if game_state and game_state.characters.has(char_id) \
					and not (_lure_returning_from_song and lure_return_keeps_distraction):
				game_state.set_character_distracted(char_id, false)
		"return":
			if _lure_returning_from_song:
				if game_state and game_state.characters.has(char_id):
					game_state.set_character_distracted(char_id, false)
					game_state.change_move_speed(char_id, move_speed)
				_lure_returning_from_song = false
				_lure_source_key = ""
				_lure_source_activation_serial = 0
		"alert":
			_remove_alert_label()
		"pursuit":
			_stop_movement()
			if game_state != null and game_state.characters.has(char_id):
				game_state.change_move_speed(char_id, move_speed)
		"charge":
			_charging = false
			# Restore the chase speed (the lunge ran at charge_speed through the data layer).
			if game_state != null and game_state.characters.has(char_id):
				game_state.change_move_speed(char_id, move_speed)

# --- Detection (via GameState predictive signal) ---

## CHASE-GRADE acquisition (chase_scene_framework: the pursuer TRACKS the fleeing party — no
## detection-radius leash). Engages `target_id` from any scanning state, honouring every gate the
## detection path honours: never a downed target, never sanctuary ground, never a fully concealed
## one (the tight-hide MUST still break the track — the expert path depends on it). A chase
## director polls this; the enemy's own FSM does the rest (and loses the trail normally).
func engage_target(target_id: String) -> bool:
	if game_state == null or not game_state.characters.has(target_id):
		return false
	if get_state() not in ["idle", "roam", "patrol", "lured", "search", "return"]:
		return false
	var t_stats: Dictionary = game_state.characters[target_id].stats
	if t_stats.has("hp") and float(t_stats["hp"]) <= 0.0:
		return false
	if game_state.has_method("is_at_shelter") and game_state.is_at_shelter(target_id):
		return false
	if game_state.has_method("is_character_hidden") and game_state.is_character_hidden(target_id):
		return false
	_current_target_id = target_id
	_last_known_target_pos = game_state.get_position(target_id)
	target_spotted.emit(target_id)
	_fsm.transition_to("alert")
	return true

func _on_detection_predicted(detector_id: String, target_id: String) -> void:
	if _restoring_enemy_authority:
		return
	if detector_id != char_id:
		return
	if target_id not in _detection_targets:
		return
	# Only respond to detections when in a scanning state (roaming / searching / returning still see).
	if get_state() not in ["idle", "roam", "patrol", "lured", "search", "return"]:
		return
	# Never (re)acquire a downed target — that was the "alert -> chase a corpse forever" loop.
	if game_state.characters.has(target_id):
		var t_stats: Dictionary = game_state.characters[target_id].stats
		if t_stats.has("hp") and float(t_stats["hp"]) <= 0.0:
			return
	# Never acquire a target standing in a shelter region — sanctuary ground (mirrors the
	# detection-layer gate; this also covers direct/forced acquisitions).
	if game_state and game_state.has_method("is_at_shelter") and game_state.is_at_shelter(target_id):
		return
	_current_target_id = target_id
	if game_state:
		_last_known_target_pos = game_state.get_position(target_id)
	target_spotted.emit(target_id)
	_fsm.transition_to("alert")

# --- Alert ---

func _show_alert_on_target() -> void:
	_remove_alert_label()
	if _current_target_id == "" or not game_state:
		return
	var target_node := _find_character_node(_current_target_id)
	if not target_node:
		return
	_alert_label = Label3D.new()
	_alert_label.name = "AlertMark"
	_alert_label.text = "!"
	_alert_label.font_size = 72
	_alert_label.pixel_size = 0.012
	_alert_label.modulate = Color(1, 1, 1, 0.95)
	_alert_label.outline_modulate = Color(0, 0, 0, 0.6)
	_alert_label.outline_size = 5
	_alert_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_label.position = Vector3(0, 1.8, 0)
	target_node.add_child(_alert_label)

func _remove_alert_label() -> void:
	if _alert_label and is_instance_valid(_alert_label):
		_alert_label.queue_free()
	_alert_label = null

# --- Attack cycle: alert -> pursuit -> windup -> charge -> impact -> recover (-> pursuit / search) ---
# Lose the target (rescan timeout, or it goes down) -> search the last-known spot -> return home.

func _begin_pursuit() -> void:
	if get_state() != "alert":
		return
	_remove_alert_label()
	_fsm.transition_to("pursuit")

func _pursue_target() -> void:
	if get_state() != "pursuit":
		return
	if not _target_engageable():
		_fsm.transition_to("search")
		return
	var target_pos := game_state.get_position(_current_target_id)
	_last_known_target_pos = target_pos
	_publish_enemy_authority()
	Enemy._count("pursue")
	var dist := _planar_dist(_self_pos(), target_pos)
	# Close enough to wind up.
	if dist <= attack_range:
		_fsm.transition_to("windup")
		return
	# Otherwise keep chasing (pursuit is the ONLY state that pathfinds). A chase-pack enemy can
	# opt into DIRECT pursuit (straight hops, no A*, no reservations): cooperative space-time
	# planning for 4-6 pursuers re-pathing 100+ cell routes every rescan measured up to 1.8 s per
	# 0.1 s step — the lockout chase's frame drops. A pack in an open corridor doesn't need
	# reservation-grade planning; convex-corridor scenes set pursuit_direct on their waves.
	if game_state.characters.has(char_id):
		if game_state.grid and not pursuit_direct:
			game_state.command_move_to_cell(char_id, game_state.grid.world_to_grid(target_pos))
		else:
			_command_direct_pursuit_toward(target_pos)
	_schedule_enemy_timer(pursuit_update_interval, "pursuit_update", _pursue_target)

## Commit one bounded direct-pursuit leg without asking GameState to solve the
## same spatial route again. `command_move_to_pos()` deliberately routes through
## grid A* in grid scenes; using it here made `pursuit_direct` an accidental
## per-body planner despite the flag's contract. Scene resolvers must provide
## wall-safe waypoints (Lockout's shared field does); the no-resolver fallback is
## reserved for the open/convex corridors that opt into direct pursuit.
func _command_direct_pursuit_toward(target_pos: Vector3) -> void:
	if game_state == null or not game_state.characters.has(char_id):
		return
	var path: Array[Vector3] = []
	if pursuit_path_resolver.is_valid():
		var resolved: Variant = pursuit_path_resolver.call(_self_pos(), target_pos)
		if resolved is Array:
			for point_v in (resolved as Array):
				if point_v is Vector3 and (point_v as Vector3).is_finite():
					path.append(point_v as Vector3)
	elif pursuit_hop_resolver.is_valid():
		var resolved_hop: Variant = pursuit_hop_resolver.call(_self_pos(), target_pos)
		if resolved_hop is Vector3 and (resolved_hop as Vector3).is_finite():
			path.append(resolved_hop as Vector3)
	else:
		path.append(_self_pos() + (target_pos - _self_pos()).limit_length(pursuit_hop))
	if not path.is_empty():
		Enemy._count("direct_pursuit_leg")
		game_state.command_walk_path(char_id, path)

func _begin_charge() -> void:
	if get_state() != "windup":
		return
	_fsm.transition_to("charge")

## Commit the lunge: a fast data-layer move (logged → replay-safe, visual follows via the _process
## sync) toward a point just short of the target, locked NOW (freshest). The strike is scheduled for
## the contact tick — it lands for sure unless the target dodges in the window. Because the body
## actually MOVES through the data layer, there is no teleport-snap at impact.
func _begin_lunge() -> void:
	_charging = true
	_charge_hit = false
	if not _target_engageable() or not game_state.characters.has(char_id):
		_fsm.transition_to("recover")
		return
	var ep := _self_pos()
	var tp := game_state.get_position(_current_target_id)
	# LEAD the lunge: aim where the target WILL be at contact, read analytically off their committed
	# plan (predict_position), converged in two passes. A WALKER gets led and caught (the body
	# actually arrives on them — no hit-from-nowhere); a SPRINTER outpaces what the charge can cover
	# inside charge_max_duration and slips it. Dry bar = walking = catchable is the tension currency.
	if game_state.has_method("predict_position"):
		for lead_pass in range(2):
			var t_est: float = clampf(_planar_dist(ep, tp) / maxf(charge_speed, 0.1), 0.0, charge_max_duration)
			tp = game_state.predict_position(_current_target_id, t_est)
	_charge_target_pos = tp
	var flat := Vector3(tp.x - ep.x, 0.0, tp.z - ep.z)
	var dist := flat.length()
	var dir := flat.normalized() if dist > 0.001 else Vector3.ZERO
	var lunge_to := tp - dir * lunge_gap
	var lunge_dist := maxf(0.0, dist - lunge_gap)
	game_state.change_move_speed(char_id, charge_speed)
	if lunge_dist > 0.05:
		game_state.command_move_to_pos(char_id, lunge_to)
	var contact: float = minf(lunge_dist / maxf(charge_speed, 0.1), charge_max_duration)
	_schedule_enemy_timer(contact, "charge_end", _end_charge)

## Resolve the charge into the impact beat. Called by the scheduled contact (standard enemy) AND by
## ChainEnemy when one of its trailing segments touches the target early — both route through the same
## impact, deduped by _charge_hit so the strike resolves exactly once.
func _end_charge() -> void:
	if get_state() != "charge":
		return
	_fsm.transition_to("impact")

## Resolve a single charge strike against `tid`, exactly once per charge (deduped by _charge_hit). This is
## the SHARED path for the standard scheduled impact AND a ChainEnemy segment contact, so both honour the
## dodge window, never hit a downed target, and apply REAL data-layer damage (adjust_stat) — not just a
## cosmetic signal. Returns true if the strike landed.
func _resolve_strike(tid: String) -> bool:
	if _charge_hit:
		return false  # already resolved this charge
	if tid == "" or game_state == null or not game_state.characters.has(tid):
		return false
	# Never strike a target that is already down (e.g. another enemy felled it mid-charge).
	if float(game_state.characters[tid].stats.get("hp", 1.0)) <= 0.0:
		return false
	# Sanctuary: a committed strike never lands on a target standing in a shelter region.
	if game_state.has_method("is_at_shelter") and game_state.is_at_shelter(tid):
		return false
	# The committed swing hits LEAF, not the friend inside: a fully-concealed target cannot be struck.
	if game_state.has_method("get_character_concealment") 			and int(game_state.get_character_concealment(tid)) == GameState.CONCEAL_FULL:
		return false
	# Dodge window: a target that can roll (dodge_unlocked) and auto-evades slips the committed strike.
	if game_state.has_method("dodge_roll"):
		var st: Dictionary = game_state.characters[tid].stats
		if bool(st.get("dodge_unlocked", false)) and bool(st.get("auto_dodge", false)) and not game_state.is_dodging(tid):
			game_state.dodge_roll(tid, _perp_to_target(tid))
	if game_state.has_method("is_dodging") and game_state.is_dodging(tid):
		return false
	_charge_hit = true
	if game_state.has_method("adjust_stat"):
		var damage_started := PerformanceTrace.begin()
		game_state.adjust_stat(tid, "hp", -charge_damage)
		PerformanceTrace.end(&"update", &"enemy.impact.damage", damage_started, tid, 1)
	var flinch_started := PerformanceTrace.begin()
	_flash_target(tid)
	PerformanceTrace.end(&"draw", &"enemy.impact.flinch", flinch_started, tid, 1)
	var feedback_started := PerformanceTrace.begin()
	hit_target.emit(tid, charge_damage)
	PerformanceTrace.end(&"draw", &"enemy.impact.feedback_signal", feedback_started, tid, 1)
	_publish_enemy_authority()
	return true

## The strike resolves at impact (standard enemy). ChainEnemy routes its segment contact through the same
## _resolve_strike so the two paths can't diverge.
func _apply_strike() -> void:
	# A committed charge is not a homing missile: the scheduled impact only lands if the target is
	# ACTUALLY within reach at the impact tick — a runner who read the telegraph and cleared the
	# locked lunge point makes the charge WHIFF (recover -> re-evaluate handles the rest).
	# ChainEnemy's segment-contact path checks physical touch itself and keeps its own semantics.
	if _current_target_id != "" and game_state != null and game_state.characters.has(_current_target_id):
		if _planar_dist(_self_pos(), game_state.get_position(_current_target_id)) > strike_reach:
			return
	_resolve_strike(_current_target_id)

func _begin_recover() -> void:
	if get_state() != "impact":
		return
	_fsm.transition_to("recover")

## After the cooldown, re-evaluate: strike again if the target is in range, chase if it fled, else
## hunt the last-known spot. Never loop on a downed target (that was the "attacks a corpse" bug).
func _after_recover() -> void:
	if get_state() != "recover":
		return
	if not _target_engageable():
		_fsm.transition_to("search")
		return
	var dist := _planar_dist(_self_pos(), game_state.get_position(_current_target_id))
	_fsm.transition_to("windup" if dist <= attack_range else "pursuit")

func _after_stagger() -> void:
	if get_state() != "stagger":
		return
	_fsm.transition_to("pursuit" if _target_engageable() else "search")

func _after_stun() -> void:
	if get_state() != "stunned":
		return
	_fsm.transition_to("pursuit" if _target_engageable() else "return")

func _begin_search() -> void:
	if get_state() != "pursuit":
		return
	_fsm.transition_to("search")

func _begin_search_move() -> void:
	# Walk to where the target was last seen and look around; detection stays live while searching.
	# Chase packs hop CAPPED here too: a full-length cooperative plan through five other movers'
	# reservations is where the space-time search explodes (the 1.9 s scheduler spikes).
	if game_state and game_state.characters.has(char_id):
		var dest := _last_known_target_pos
		if pursuit_direct:
			_command_direct_pursuit_toward(dest)
		else:
			game_state.command_move_to_pos(char_id, dest)

func _begin_return() -> void:
	if get_state() != "search":
		return
	_fsm.transition_to("return")

func _begin_return_move() -> void:
	# Head home, then resume the ambient mode the enemy was in before it gave chase. Roam homes
	# to its anchor; a standing (idle-home) guard walks back to the POST it was activated at.
	var dest := _self_pos()
	if _home_mode == "roam":
		dest = _roam_anchor
	elif _home_mode == "idle" and _post_position != Vector3.ZERO:
		dest = _post_position
	if dest != _self_pos() and game_state and game_state.characters.has(char_id):
		game_state.command_move_to_pos(char_id, dest)
	var travel := _planar_dist(_self_pos(), dest) / maxf(move_speed, 0.1) + 0.1
	_schedule_enemy_timer(travel, "return_end", _resume_home)

func _resume_home() -> void:
	if get_state() != "return":
		return
	match _home_mode:
		"roam":
			_fsm.transition_to("roam")
		"patrol":
			_fsm.transition_to("patrol")
		_:
			_fsm.transition_to("idle")

## True while the current target exists and is not downed (hp stat present and <= 0 means down).
func _target_engageable() -> bool:
	if _current_target_id == "" or game_state == null:
		return false
	if not game_state.characters.has(_current_target_id):
		return false
	var stats: Dictionary = game_state.characters[_current_target_id].stats
	if stats.has("hp") and float(stats["hp"]) <= 0.0:
		return false
	# Sanctuary: a target that reaches a shelter region is no longer engageable — the chase sheds.
	if game_state.has_method("is_at_shelter") and game_state.is_at_shelter(_current_target_id):
		return false
	# A TIGHT hide is invisibility even point-blank (the hidden-detection law): a fully-concealed
	# target cannot be engaged — the chase sheds at the leaf head exactly like at a shelter.
	if game_state.has_method("get_character_concealment") 			and int(game_state.get_character_concealment(_current_target_id)) == GameState.CONCEAL_FULL:
		return false
	return true

## Scheduler-authoritative self position (data layer when registered, else the node).
func _self_pos() -> Vector3:
	if game_state and game_state.characters.has(char_id):
		return game_state.get_position(char_id)
	return global_position

func _planar_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## A sideways direction relative to the line from the target to this enemy (the dodge slip axis).
func _perp_to_target(target_id: String) -> Vector3:
	var ap := _self_pos()
	var tp := game_state.get_position(target_id)
	var approach := Vector3(ap.x - tp.x, 0.0, ap.z - tp.z)
	var perp := Vector3(-approach.z, 0.0, approach.x)
	return perp.normalized() if perp.length_squared() > 0.001 else Vector3(1.0, 0.0, 0.0)

## Brief flinch on a struck character — a universal scale-punch on its node (cosmetic; any Node3D).
func _flash_target(target_id: String) -> void:
	var node := _find_character_node(target_id) as Node3D
	if node == null:
		return
	if not Enemy._cosmetics_on():
		return
	var base: Vector3 = node.scale
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(node, "scale", base * 1.25, 0.07)
	_flash_tween.tween_property(node, "scale", base, 0.18)

# --- Roam (local wander, no pathfinding) ---

## Stable across process runs and engine versions. Masking each round keeps the arithmetic inside
## signed 64-bit range while preserving ample entropy for the cadence lanes.
static func _stable_roam_cadence_seed(identity: String) -> int:
	var seed := 5381
	for byte_value in identity.to_utf8_buffer():
		seed = ((seed * 33) ^ int(byte_value)) & 0x7fffffff
	return seed

## Claim one lane among enemies sharing this EventScheduler. Stable-id preference keeps ordinary
## claims independent of allocation order; linear probing only resolves a real collision. This is
## derived scheduling state, released with the node and never serialized into gameplay state.
func _claim_roam_cadence_lane() -> int:
	var scheduler := _get_scheduler()
	if scheduler == null:
		return 0
	var scheduler_id := int(scheduler.get_instance_id())
	if _roam_cadence_lane >= 0 and _roam_cadence_scheduler_id == scheduler_id \
			and _roam_cadence_identity == char_id:
		return _roam_cadence_lane
	_release_roam_cadence_lane()
	var lanes: Dictionary = Enemy._roam_cadence_owners.get(scheduler_id, {})
	var owner_id := int(get_instance_id())
	var preferred := _stable_roam_cadence_seed(char_id) % _ROAM_CADENCE_LANE_COUNT
	for offset in range(_ROAM_CADENCE_LANE_COUNT):
		var candidate := (preferred + offset) % _ROAM_CADENCE_LANE_COUNT
		var existing_owner := int(lanes.get(candidate, 0))
		if existing_owner == 0 or existing_owner == owner_id \
				or not is_instance_id_valid(existing_owner):
			_roam_cadence_lane = candidate
			lanes[candidate] = owner_id
			break
	# More than 64 simultaneous roamers is outside the visible encounter budget. Keep overflow
	# deterministic rather than suppressing ambient behavior; only overflow actors may share a lane.
	if _roam_cadence_lane < 0:
		_roam_cadence_lane = preferred
	_roam_cadence_scheduler_id = scheduler_id
	_roam_cadence_identity = char_id
	Enemy._roam_cadence_owners[scheduler_id] = lanes
	return _roam_cadence_lane

func _release_roam_cadence_lane() -> void:
	if _roam_cadence_scheduler_id != 0 and _roam_cadence_lane >= 0:
		var lanes: Dictionary = Enemy._roam_cadence_owners.get(
			_roam_cadence_scheduler_id, {})
		if int(lanes.get(_roam_cadence_lane, 0)) == int(get_instance_id()):
			lanes.erase(_roam_cadence_lane)
		if lanes.is_empty():
			Enemy._roam_cadence_owners.erase(_roam_cadence_scheduler_id)
		else:
			Enemy._roam_cadence_owners[_roam_cadence_scheduler_id] = lanes
	_roam_cadence_scheduler_id = 0
	_roam_cadence_lane = -1
	_roam_cadence_identity = ""

## Align first ambient work to an absolute scheduler phase. Re-entering roam at a different time
## therefore cannot re-synchronize a cohort. Detection is already active before this is armed, so
## alert/pursuit transitions remain immediate and cancel the pending state-owned callback.
func _schedule_first_roam_step() -> void:
	var scheduler := _get_scheduler()
	if scheduler == null:
		_roam_step()
		return
	var interval := maxf(roam_interval, _ROAM_CADENCE_MIN_INTERVAL)
	var lane := _claim_roam_cadence_lane()
	var phase := interval * (float(lane) + 0.5) / float(_ROAM_CADENCE_LANE_COUNT)
	var cycle_position := fposmod(scheduler.get_current_tick(), interval)
	var delay := fposmod(phase - cycle_position, interval)
	# Avoid recursively dispatching a zero-delay callback at the current scheduler tick. Waiting for
	# this lane's next phase is equivalent for ambient motion and keeps scheduler work bounded.
	if delay < 0.0001:
		delay = interval
	_schedule_enemy_timer(delay, "roam_step", _roam_step)

func _roam_step() -> void:
	if get_state() != "roam" or not game_state or not game_state.characters.has(char_id):
		return
	var cur := game_state.get_position(char_id)
	var target := _pick_roam_target(cur)
	game_state.command_move_to_pos(char_id, target)  # straight line — never A*
	_roam_seq += 1
	if _fsm != null:
		_schedule_enemy_timer(
			maxf(roam_interval, _ROAM_CADENCE_MIN_INTERVAL), "roam_step", _roam_step)

## Choose the next hop: rotate the heading by a deterministic wander angle, pull back toward the
## anchor near the circle's edge, clamp inside the radius, and bounce off a blocked grid cell. Pure
## function of the hop counter + enemy id (no wall-clock / randf), so 1x and 10x roam identically.
func _pick_roam_target(cur: Vector3) -> Vector3:
	var turn := (_roam_noise(0) - 0.5) * deg_to_rad(120.0)  # +/-60 deg of wander
	_roam_heading = _roam_heading.rotated(Vector3.UP, turn).normalized()
	var from_anchor := cur - _roam_anchor
	from_anchor.y = 0.0
	if from_anchor.length() > _roam_radius * 0.8:
		# Near the edge — steer back inward so the wander stays in its yard.
		_roam_heading = (_roam_heading + (-from_anchor).normalized() * 1.5).normalized()
	var target := cur + _roam_heading * roam_step_distance
	target.y = cur.y
	var off := target - _roam_anchor
	off.y = 0.0
	if off.length() > _roam_radius:
		target = _roam_anchor + off.normalized() * _roam_radius
		target.y = cur.y
	if game_state and game_state.grid:
		var lvl := game_state.get_character_level(char_id)
		var cell := game_state.grid.world_to_grid(target)
		if not game_state.grid.is_walkable(cell.x, cell.y, {}, {}, lvl):
			_roam_heading = -_roam_heading  # bounce off the wall; hold this hop
			return cur
	return target

## Deterministic pseudo-random in [0,1): a hash of the enemy id, the hop counter, and a salt. Free of
## the wall clock and randf, so the wander is identical under fast-forward and reproducible per run.
func _roam_noise(salt: int) -> float:
	return float(absi(hash("%s:%d:%d" % [char_id, _roam_seq, salt])) % 100000) / 100000.0

# --- Patrol ---

func _patrol_next_waypoint() -> void:
	if _patrol_waypoints.is_empty() or get_state() != "patrol":
		return
	var waypoint := _patrol_waypoints[_patrol_index]
	var from_pos := global_position
	if game_state and game_state.characters.has(char_id):
		if game_state.grid:
			game_state.command_move_to_cell(char_id, game_state.grid.world_to_grid(waypoint))
		else:
			game_state.command_move_to_pos(char_id, waypoint)
		# Time the leg from the DATA-layer position — the node is a cosmetic follower and lags (headless it
		# never moves at all). Reading it here made the return leg look zero-length: a 0.5s timer re-issued
		# the outbound move before the walk began, and the patrol camped its far waypoint in 0.5s blips.
		from_pos = game_state.get_position(char_id)
	_patrol_index = (_patrol_index + 1) % _patrol_waypoints.size()
	var dist := from_pos.distance_to(waypoint)
	var travel_time := dist / maxf(move_speed, 0.1) + 0.5
	var scheduler := _get_scheduler()
	if scheduler:
		_schedule_enemy_timer(travel_time, "patrol_step", _patrol_next_waypoint)

# --- Visual ---

## Override in subclasses for different mesh types. The body stays a CapsuleMesh (the elevator
## predators + chain enemy resize `_mesh.mesh as CapsuleMesh`), but it's crouched forward and dressed
## with dorsal spikes + a jutting head so it reads as a predator, not an idle sphere.
func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.24
	capsule.height = 0.78
	_mesh.mesh = capsule
	var body_color := color.darkened(0.25)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.85
	mat.metallic = 0.15
	_mesh.material_override = mat
	_mesh.layers = 2   # NO_GRID_DECAL_LAYER (player.gd): the hover-grid Decal skips it so the grid passes through
	# Crouched, leaning forward (predatory stance) rather than standing upright.
	_mesh.position.y = 0.42
	_mesh.rotation = Vector3(deg_to_rad(78.0), 0.0, 0.0)
	add_child(_mesh)
	_build_creature_features(body_color)
	_eye_left = _make_eye(Vector3(-0.11, 0.5, 0.34))
	_eye_right = _make_eye(Vector3(0.11, 0.5, 0.34))

## Dorsal spikes + a forward head wedge — silhouette cues that read as a threat at gameplay distance.
func _build_creature_features(body_color: Color) -> void:
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = body_color.darkened(0.2)
	spike_mat.roughness = 0.7
	# A short ridge of back spikes.
	for i in range(3):
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.075
		cone.height = 0.26 - i * 0.04
		spike.mesh = cone
		spike.material_override = spike_mat
		spike.position = Vector3(0.0, 0.62 - i * 0.02, -0.16 + i * 0.16)
		spike.rotation = Vector3(deg_to_rad(-28.0), 0.0, 0.0)
		add_child(spike)
	# A blunt head jutting forward over the eyes.
	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.02
	head_mesh.bottom_radius = 0.17
	head_mesh.height = 0.34
	head.mesh = head_mesh
	head.material_override = spike_mat
	head.position = Vector3(0.0, 0.5, 0.28)
	head.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	add_child(head)

func _make_eye(pos: Vector3) -> OmniLight3D:
	var eye := OmniLight3D.new()
	eye.position = pos
	eye.light_color = Color(0.95, 0.1, 0.05)
	eye.light_energy = 0.4
	eye.omni_range = 0.8
	add_child(eye)
	return eye


## Universal faction/state read at gameplay distance. Creature silhouettes can vary wildly
## (especially subclasses), so every hostile gets the same red floor halo. Lure/stun/attack
## states recolor and pulse it without affecting collision, detection, or scheduler timing.
func _build_threat_marker() -> void:
	if not Enemy._cosmetics_on():
		return
	_threat_marker = Node3D.new()
	_threat_marker.name = "ThreatHalo"
	_threat_marker.position.y = -0.46
	add_child(_threat_marker)

	_threat_marker_material = StandardMaterial3D.new()
	_threat_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_threat_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_threat_marker_material.albedo_color = Color(0.95, 0.08, 0.12, 0.78)
	_threat_marker_material.emission_enabled = true
	_threat_marker_material.emission = Color(1.0, 0.04, 0.08)
	_threat_marker_material.emission_energy_multiplier = 2.2
	# Persistent faction reads obey walls/fog. Only deliberate planning/causal overlays
	# are allowed to reveal a target through geometry.
	_threat_marker_material.no_depth_test = false
	_threat_marker_material.render_priority = 3

	var ring := MeshInstance3D.new()
	ring.name = "HostileRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.36
	torus.outer_radius = 0.43
	torus.rings = 24
	torus.ring_segments = 10
	ring.mesh = torus
	ring.material_override = _threat_marker_material
	ring.set_meta("camera_occlusion_exempt", true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.layers = 2
	_threat_marker.add_child(ring)

	var pip_mesh := BoxMesh.new()
	pip_mesh.size = Vector3(0.09, 0.035, 0.24)
	for i in range(3):
		var angle := TAU * float(i) / 3.0
		var pip := MeshInstance3D.new()
		pip.name = "ThreatPip%d" % i
		pip.mesh = pip_mesh
		pip.material_override = _threat_marker_material
		pip.set_meta("camera_occlusion_exempt", true)
		pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pip.layers = 2
		pip.position = Vector3(cos(angle), 0.0, sin(angle)) * 0.55
		pip.rotation.y = -angle
		_threat_marker.add_child(pip)


func _update_threat_marker() -> void:
	if _threat_marker == null or _threat_marker_material == null:
		return
	var state := get_state()
	_threat_marker.visible = state != "dead"
	if not _threat_marker.visible:
		return
	var tint := Color(0.95, 0.07, 0.11)
	var speed := 0.75
	var energy_base := 1.7
	match state:
		"lured", "return":
			tint = Color(1.0, 0.58, 0.12)
			speed = 1.15
			energy_base = 2.3
		"stagger", "stunned":
			tint = Color(0.68, 0.4, 1.0)
			speed = -1.6
			energy_base = 2.5
		"alert", "pursuit":
			tint = Color(1.0, 0.04, 0.03)
			speed = 2.2
			energy_base = 3.2
		"windup", "charge", "impact":
			tint = Color(1.0, 0.02, 0.01)
			speed = 4.2
			energy_base = 4.0
	var now := float(Time.get_ticks_msec()) * 0.001
	var pulse := 0.5 + 0.5 * sin(now * (5.0 + absf(speed) * 2.0))
	var urgent := state in ["alert", "pursuit", "windup", "charge", "impact"]
	_threat_marker.rotation.y = now * speed
	_threat_marker.scale = Vector3.ONE * (0.92 + pulse * (0.22 if urgent else 0.1))
	_threat_marker_material.albedo_color = Color(tint.r, tint.g, tint.b, 0.7 + pulse * 0.2)
	_threat_marker_material.emission = tint
	_threat_marker_material.emission_energy_multiplier = energy_base + pulse * 1.25

func _set_eye_energy(energy: float) -> void:
	if _eye_left:
		_eye_left.light_energy = energy
	if _eye_right:
		_eye_right.light_energy = energy

func _set_mesh_color(c: Color) -> void:
	if _mesh == null or _mesh.material_override == null:
		return
	var material := _mesh.material_override
	if material is StandardMaterial3D:
		(material as StandardMaterial3D).albedo_color = c
	elif material is ShaderMaterial:
		# CameraOcclusionManager replaces the enemy's StandardMaterial3D with
		# its see-through wrapper after a streamed chunk loads.  State colors
		# must update the wrapper parameter instead of casting it back to a
		# StandardMaterial3D (that cast is null and used to error on pursuit).
		var shader_material := material as ShaderMaterial
		if shader_material.get_shader_parameter("albedo_color") is Color:
			shader_material.set_shader_parameter("albedo_color", c)

func _fade_out(duration: float) -> void:
	if _mesh and Enemy._cosmetics_on():
		if _fade_tween != null and _fade_tween.is_valid():
			_fade_tween.kill()
		_fade_tween = create_tween()
		_fade_tween.tween_property(_mesh, "transparency", 1.0, duration)
	_set_eye_energy(0.0)

# --- Attack-beat animation (cosmetic scale pulses; never gate a transition on these) ---
# Each beat reshapes the body so the player reads intent: a squash anticipation before the lunge, a
# punch on impact, a flinch on stagger. ChainEnemy has no _mesh (it overrides _build_visual), so these
# safely no-op for it — its segments carry their own motion.
var _anim_tween: Tween
var _flash_tween: Tween
var _recover_tween: Tween
var _fade_tween: Tween

## Cosmetic tweens are FRAME-driven: on a headless tree no frame ever steps them, so every beat
## would leak a live tween and SceneTree bookkeeping grows O(n) — measured as the chase's
## 110 ms/step scheduler cost. Cosmetics simply don't exist without a display.
static func _cosmetics_on() -> bool:
	return DisplayServer.get_name() != "headless"

func _play_scale(keys: Array) -> void:
	if _mesh == null or not Enemy._cosmetics_on():
		return
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = create_tween()
	for k in keys:
		_anim_tween.tween_property(_mesh, "scale", k[0], float(k[1]))

func _anim_pop(peak := 1.18) -> void:      # alert: quick spot-tell
	_play_scale([[Vector3.ONE * peak, 0.08], [Vector3.ONE, 0.12]])

func _anim_squash() -> void:               # windup: crouch/anticipation
	_play_scale([[Vector3(1.2, 0.8, 1.2), 0.12]])

func _anim_punch() -> void:                # impact: sharp connect
	_play_scale([[Vector3.ONE * 1.3, 0.05], [Vector3.ONE, 0.12]])

func _anim_settle() -> void:               # recover: ease back to rest
	_play_scale([[Vector3.ONE, 0.2]])

func _anim_recoil() -> void:               # stagger: flinch inward
	_play_scale([[Vector3.ONE * 0.78, 0.06], [Vector3.ONE, 0.18]])

# --- Movement / Charge collision ---

func _process(_delta: float) -> void:
	var perf_started := PerformanceTrace.begin()
	_update_threat_marker()
	# The body is a pure mirror of the data layer — including the charge, which is now a real
	# data-layer move at charge_speed (so the lunge is smooth and never teleport-snaps at impact).
	if game_state and char_id != "" and game_state.is_moving(char_id):
		var pos := game_state.get_render_position(char_id)
		if game_state.coord_map != null or game_state.is_external_traversal_active(char_id):
			global_position = pos          # warped onto the helix (y meaningful)
		else:
			global_position = Vector3(pos.x, global_position.y, pos.z)
	PerformanceTrace.end(&"update", &"enemy.process", perf_started, char_id, 1)

func _stop_movement() -> void:
	if game_state and game_state.characters.has(char_id):
		game_state.command_stop(char_id)

## The effective speed used only while tracking a target. Exposed as a query so level contracts
## and tests can assert the walk < threat < sprint relationship without reaching into FSM state.
func get_pursuit_speed() -> float:
	return pursuit_speed if pursuit_speed > 0.0 else move_speed

# --- Utilities ---

func _get_scheduler() -> EventScheduler:
	if game_state and game_state.scheduler:
		return game_state.scheduler
	return null

## Scheduler-authoritative world position of a target: GameState when the target is
## registered (so the charge clock and the target clock are the same), else the node.
func _charge_target_world(target_id: String) -> Vector3:
	if game_state and game_state.characters.has(target_id):
		return game_state.get_position(target_id)
	var node := _find_character_node(target_id)
	return (node as Node3D).global_position if node else Vector3.INF

var _char_node_cache := {}

func _find_character_node(target_id: String) -> Node:
	# CACHED: the full scan walks every child of every sibling container with per-node string
	# ops — six pack members re-alerting once a second each made it the chase's hot loop
	# (measured: half the pack's FSM tags = 95% of the step cost). Nodes don't move between
	# containers; one scan per target id per enemy, revalidated on use.
	var cached = _char_node_cache.get(target_id)
	if cached != null and is_instance_valid(cached):
		return cached
	var found := _find_character_node_scan(target_id)
	if found != null:
		_char_node_cache[target_id] = found
	return found

func _find_character_node_scan(target_id: String) -> Node:
	# Search parent first (Characters node), then siblings of parent (chunk nodes)
	for search_root in _get_search_roots():
		for child in search_root.get_children():
			if child == self:
				continue
			if child.has_method("get") and child.get("char_id") == target_id:
				return child
			if child.name.to_lower() == target_id:
				return child
	return null

func _get_search_roots() -> Array[Node]:
	var roots: Array[Node] = []
	var parent := get_parent()
	if parent:
		roots.append(parent)
		# Also search sibling containers (e.g. Characters node when enemy is in a chunk)
		if parent.get_parent():
			for sibling in parent.get_parent().get_children():
				if sibling != parent and sibling is Node3D:
					roots.append(sibling)
	return roots


## Freed while the scene's scheduler lives on (the roguelike reload frees chunks + their enemies without
## resetting the scheduler): every FSM timer and self-re-arming callback (roam hops, patrol legs) is tagged
## _state_tag — retract them, or they fire on a freed instance forever.
func _exit_tree() -> void:
	var scheduler = _get_scheduler()
	if scheduler != null and _state_tag != "":
		scheduler.cancel_tag(_state_tag)
	_release_roam_cadence_lane()
