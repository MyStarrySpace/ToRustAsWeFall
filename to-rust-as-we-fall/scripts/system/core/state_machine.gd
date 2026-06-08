class_name StateMachine
extends RefCounted

## Reusable, scheduler-driven finite state machine.
##
## States are named strings. Each may register on_enter / on_exit / on_update callbacks. Timed
## transitions and per-state scheduled work ride the EventScheduler, so they respect pause +
## fast-forward and replay deterministically (the FSM holds DERIVED state — it never writes to the
## EventLog; transitions are reproduced from the same scheduler callbacks on replay).
##
## A single scheduler TAG owns every timer a state arms; transitioning cancels that tag, so no stale
## timer from the old state can fire after you've left it (the pattern enemy.gd hand-rolled with
## `_state_tag` + `cancel_tag`). Use one StateMachine per stateful entity (enemy, interactable, the
## sequence step flow) instead of re-implementing the same plumbing each time.
##
## Usage:
##   var fsm := StateMachine.new(_scheduler, "enemy_%s" % name)
##   fsm.add_state("idle", _enter_idle)
##   fsm.add_state("patrol", _enter_patrol, _exit_patrol, _tick_patrol)
##   fsm.start("idle")
##   ...
##   fsm.transition_after(0.5, "patrol")   # scheduled, auto-cancelled if we leave first
##   fsm.transition_to("alert")            # immediate

signal state_changed(from_state: String, to_state: String)

var _scheduler  # EventScheduler or null (null disables timed transitions)
var _tag := "fsm"
var _current := ""
var _states: Dictionary = {}  # name -> {enter: Callable, exit: Callable, update: Callable}

func _init(scheduler = null, tag := "fsm") -> void:
	_scheduler = scheduler
	_tag = tag

## Point the FSM at its scheduler after construction. Owners that build the FSM before their scheduler
## exists (e.g. an enemy whose game_state is assigned after _ready) call this once it's available, so
## timed transitions and per-state schedules actually fire (and transition cancels reach the timers).
func set_scheduler(scheduler) -> void:
	_scheduler = scheduler

## Register a state and its (optional) hooks. on_enter()/on_exit() take no args; on_update(delta).
func add_state(state_name: String, on_enter := Callable(), on_exit := Callable(), on_update := Callable()) -> void:
	_states[state_name] = {"enter": on_enter, "exit": on_exit, "update": on_update}

func has_state(state_name: String) -> bool:
	return _states.has(state_name)

func current() -> String:
	return _current

func is_in(state_name: String) -> bool:
	return _current == state_name

## Enter the initial state (no exit hook for a previous state). Idempotent guard against re-start.
func start(state_name: String) -> void:
	_current = state_name
	_call(state_name, "enter")

## Immediate transition: cancel the current state's pending scheduled work, run its exit hook, then
## the new state's enter hook. A self-transition is a no-op.
func transition_to(state_name: String) -> void:
	if state_name == _current:
		return
	var from_state := _current
	if _scheduler != null:
		_scheduler.cancel_tag(_tag)
	_call(from_state, "exit")
	_current = state_name
	_call(state_name, "enter")
	state_changed.emit(from_state, state_name)

## Transition after `delay` scheduler ticks. The timer is tagged to this FSM, so any transition (or
## cancel_pending) before it fires drops it — no stale state changes. No-op without a scheduler.
func transition_after(delay: float, state_name: String) -> void:
	if _scheduler == null:
		return
	_scheduler.schedule_after(delay, func(): transition_to(state_name), _tag)

## Schedule an arbitrary callback owned by the current state — cancelled on the next transition
## (the same lifecycle as transition_after). Use for per-state periodic work (scans, ticks).
func schedule(delay: float, cb: Callable) -> void:
	if _scheduler != null:
		_scheduler.schedule_after(delay, cb, _tag)

## Drop every pending timer this FSM armed for the current state without changing state.
func cancel_pending() -> void:
	if _scheduler != null:
		_scheduler.cancel_tag(_tag)

## Set the current state WITHOUT running exit/enter hooks or touching scheduled work. For white-box
## test setup or external resets that manage the state's side effects themselves. Prefer
## transition_to / transition_after in normal use.
func force_current(state_name: String) -> void:
	_current = state_name

## Drive the current state's on_update hook (call from the owner's per-frame loop if it uses one).
func update(delta: float) -> void:
	_call(_current, "update", [delta])

func _call(state_name: String, hook: String, args: Array = []) -> void:
	if not _states.has(state_name):
		return
	var cb: Callable = _states[state_name].get(hook, Callable())
	if cb.is_valid():
		cb.callv(args)
