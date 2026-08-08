class_name Tangler
extends Enemy

## TANGLER (fauna_roster L32): "stealth grappler, mid — tau pathology; paired helical filaments that
## spread prion-like and PREFER HYPEREXCITABLE NEURONS. Creeps in, grapples with uncoiling hooks,
## drains you... Overextending is how it gets you. The filaments uncoil slowly before the snap, a
## clear step-away window. Sever the limbs, keep range, or lead it into a Candid zone."
##
## Three roster lines drive every number here, and nothing else is invented:
##
##  - CREEPS IN. It is slow. A Tangler that sprinted would be a Gnawer; the whole encounter is that
##    you can outwalk it and still lose by standing still too long.
##  - THE FILAMENTS UNCOIL SLOWLY BEFORE THE SNAP -- A CLEAR STEP-AWAY WINDOW. So the windup is LONG,
##    the exact inverse of the Naturalizer's deliberately short contact tell. The long telegraph IS
##    the counter ("keep range"): overextending is how it gets you, and stepping away is how it does
##    not. A short windup here would delete the roster's stated counterplay.
##  - PREFERS HYPEREXCITABLE NEURONS. Among the bodies it can currently see, it locks onto the one
##    that is RUNNING -- the loudest neural-active mover. That is why a decoy works, and why the lock
##    JUMPS the moment the decoy stops running: hyperexcitability is a live property, not a mark.
##
## The lock is re-picked on a SCHEDULER cadence with its own tag, never per frame, so it rides pause
## and fast-forward like every other enemy decision and stays replay-safe.
##
## Deliberately NOT here: "lead it into a Candid zone that unravels it" is terrain damage applied to
## an ENEMY body, which does not ship (it belongs to the inter-enemy matrix build), and the lingering
## tau status has no status system to hang on. Both are roster lines this class does not yet honour,
## and pretending otherwise in code would be worse than the gap.

## The base drops its detection SUBSCRIPTION outside DETECTION_SCANNING_STATES, so a committed enemy
## stops scanning entirely -- which is why every body reads invisible the moment it acquires. A
## Tangler has to keep reading the room while it closes: "prefers hyperexcitable neurons" is a live
## property, and the decoy hand-off only exists if the lock can still see who started running. So it
## keeps scanning through ALERT and PURSUIT (it is still creeping) and drops it for the snap itself --
## windup, charge, impact, recover -- because a snap already underway is already underway.
const TANGLER_SCANNING_STATES := [
	"idle", "roam", "patrol", "lured", "search", "return", "alert", "pursuit",
]

const LOCK_POLL := 0.5
const _RESTORE_POLL_EPSILON := 0.000001

var _lock_poll_deadline := -1.0

func _ready() -> void:
	# Tau filament pallor -- the base colour state repaints return to.
	color = Color(0.78, 0.74, 0.52)
	move_speed = 1.35          # creeps
	windup_duration = 1.55     # the uncoil: the step-away window the roster promises
	recover_duration = 1.0
	charge_speed = 5.0
	attack_range = 2.2
	detection_range = 5.0
	super._ready()

func activate() -> void:
	super.activate()
	_arm_lock_poll()

## The lock follows hyperexcitability, so it has to be re-read while the encounter runs rather than
## fixed at acquisition. A decoy that stops running stops being the loudest thing in the room.
func _arm_lock_poll() -> void:
	var sched = _get_scheduler()
	if sched == null:
		_lock_poll_deadline = -1.0
		return
	sched.cancel_tag(_lock_tag())
	var deadline := float(sched.get_current_tick()) + LOCK_POLL
	_lock_poll_deadline = deadline
	sched.schedule_after(LOCK_POLL, _run_lock_poll.bind(deadline), _lock_tag())

func _sync_detection_subscription(state: String) -> void:
	if game_state != null and game_state.has_method("set_detection_enabled") 			and game_state.characters.has(char_id):
		game_state.set_detection_enabled(char_id, state in TANGLER_SCANNING_STATES)

func _lock_tag() -> String:
	return "tangler_lock_%s" % char_id

func _run_lock_poll(expected_deadline: float) -> void:
	if _lock_poll_deadline < 0.0 \
			or not is_equal_approx(_lock_poll_deadline, expected_deadline):
		return
	_lock_poll_deadline = -1.0
	_repick_lock()
	_arm_lock_poll()

## Prefer the loudest VISIBLE body. Only a running target can take the lock from another; when nobody
## is running the current lock simply stands, which is what makes "stop running" a real decision
## rather than a way to shed a pursuer for free.
func _repick_lock() -> void:
	if game_state == null or _fsm == null:
		return
	# Re-lock only while it is LOOKING. is_detection_pair_currently_visible is an acquisition-time
	# predicate and stops reporting once the body has committed, so polling it mid-snap rejects every
	# candidate and the lock silently freezes. It is also the right rule in canon: the filaments
	# choose while creeping, and a snap already underway is a snap already underway.
	if get_state() not in ["idle", "roam", "patrol", "lured", "search", "return", "alert", "pursuit"]:
		return
	var loudest := ""
	for raw_id in _detection_targets:
		var target_id := str(raw_id)
		if not _lock_candidate(target_id):
			continue
		if game_state.has_method("is_running") and bool(game_state.call("is_running", target_id)):
			loudest = target_id
			break
	if loudest == "" or loudest == _current_target_id:
		return
	_current_target_id = loudest
	_last_known_target_pos = game_state.get_position(loudest)
	target_spotted.emit(loudest)
	if get_state() in ["idle", "roam", "patrol", "lured", "search", "return"]:
		_fsm.transition_to("alert")

## The same eligibility the ordinary acquisition path enforces: a body it cannot presently see, one
## already down, or one standing on sanctuary ground is not a lock candidate.
func _lock_candidate(target_id: String) -> bool:
	if not game_state.characters.has(target_id):
		return false
	if game_state.has_method("is_detection_pair_currently_visible") \
			and not bool(game_state.call(
				"is_detection_pair_currently_visible", char_id, target_id)):
		return false
	var stats: Dictionary = game_state.characters[target_id].stats
	if stats.has("hp") and float(stats["hp"]) <= 0.0:
		return false
	if game_state.has_method("is_at_shelter") \
			and bool(game_state.call("is_at_shelter", target_id)):
		return false
	return true

## Who the filaments are currently reading, for a fragment or a test to present without reaching into
## the base class's private lock.
func get_locked_target() -> String:
	return _current_target_id

func _exit_tree() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_lock_tag())
