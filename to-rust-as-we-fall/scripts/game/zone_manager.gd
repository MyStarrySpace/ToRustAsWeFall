class_name ZoneManager
extends RefCounted

## Tracks the party's position in the game's zone → hub → spoke → gate
## progression. State-tracking infrastructure; not serialized in the
## event log because it is derivable from movement + enter_zone commands.
##
## A zone is "active" from the tick the party enters it until the tick
## they enter the next zone. While a zone is active, its hubs remain
## practically reachable (the party can walk back to rest). Once the
## party enters a subsequent zone, older-zone hubs fall out of reach —
## the game is a linear forward journey with local fallback, not a
## hub-and-spoke with persistent home bases.

signal zone_entered(zone_id: StringName)
signal zone_exited(zone_id: StringName)
signal hub_entered(hub_id: StringName)
signal gate_passed(gate_id: StringName)
signal gate_blocked(gate_id: StringName, reason: StringName)
signal spoke_completed(spoke_id: StringName)
## Fired when the party retreats to a hub after going down in a spoke.
## The game-over path is a retreat, not an end screen — scenes subscribe
## to this to fade, teleport the party back, and resume gameplay.
signal party_retreated(hub_id: StringName)

var zones: Dictionary = {}   # id (StringName) → Zone
var hubs: Dictionary = {}    # id (StringName) → Hub
var gates: Dictionary = {}   # id (StringName) → Gate

var current_zone: StringName = &""
var current_hub: StringName = &""
var _completed_spokes: Dictionary = {}  # spoke_id → true
var _passed_gates: Dictionary = {}      # gate_id → true

func register_zone(z: Zone) -> void:
	zones[z.id] = z

func register_hub(h: Hub) -> void:
	hubs[h.id] = h

func register_gate(g: Gate) -> void:
	gates[g.id] = g

## Declare a zone transition. Emits zone_exited for the previous zone
## (if any) and zone_entered for the new one.
func enter_zone(zone_id: StringName) -> void:
	if current_zone == zone_id:
		return
	if current_zone != &"":
		zone_exited.emit(current_zone)
	current_zone = zone_id
	zone_entered.emit(zone_id)

## Enter a hub and rest the party. Restores each member's stats and marks
## them narratively available.
func enter_hub(hub_id: StringName, gs: GameState, party: Array) -> void:
	if not hubs.has(hub_id):
		return
	current_hub = hub_id
	hub_entered.emit(hub_id)
	Hub.restore_party(gs, party)

## Attempt to pass a gate. Returns true on success and emits gate_passed;
## on failure emits gate_blocked with a reason StringName.
func try_pass_gate(gate_id: StringName, gs: GameState, party: Array) -> bool:
	if not gates.has(gate_id):
		return false
	var g: Gate = gates[gate_id]
	# Wire the gate's signals through ZoneManager's signals so callers only
	# subscribe in one place. Use a one-shot connection so a single gate
	# emission produces a single ZoneManager emission.
	var block_handler := func(reason: StringName) -> void:
		_passed_gates.erase(gate_id)
		gate_blocked.emit(gate_id, reason)
	var pass_handler := func() -> void:
		_passed_gates[gate_id] = true
		gate_passed.emit(gate_id)
	g.blocked.connect(block_handler, CONNECT_ONE_SHOT)
	g.passed.connect(pass_handler, CONNECT_ONE_SHOT)
	var ok := g.try_pass(gs, party)
	# Clean up in case one signal never fired (try_pass is exhaustive — it
	# emits exactly one of {passed, blocked} — but belt-and-suspenders).
	if g.blocked.is_connected(block_handler):
		g.blocked.disconnect(block_handler)
	if g.passed.is_connected(pass_handler):
		g.passed.disconnect(pass_handler)
	return ok

func mark_spoke_complete(spoke_id: StringName) -> void:
	if _completed_spokes.has(spoke_id):
		return
	_completed_spokes[spoke_id] = true
	spoke_completed.emit(spoke_id)

func is_spoke_complete(spoke_id: StringName) -> bool:
	return _completed_spokes.has(spoke_id)

func is_gate_passed(gate_id: StringName) -> bool:
	return _passed_gates.has(gate_id)

## A hub is reachable if it belongs to the currently-active zone. Older
## zones' hubs fall out of reach as soon as the party enters a new zone.
func is_hub_reachable(hub_id: StringName) -> bool:
	if not hubs.has(hub_id):
		return false
	var hub: Hub = hubs[hub_id]
	return hub.zone_id == current_zone

## Retreat the party to the last-entered hub. Restores every member and
## emits party_retreated(hub_id). If no hub has been entered yet this is
## a no-op — the party has nowhere to retreat TO. Scenes hook this signal
## to fade, teleport the party, and resume gameplay at the hub.
##
## This is the architecture's answer to "game over": there isn't one.
## Going down in a spoke is costly (time + resources burned) but bounded
## (short retreat, small heal, back to try again).
func retreat_to_last_hub(gs: GameState, party: Array) -> bool:
	if current_hub == &"":
		return false
	if not hubs.has(current_hub):
		return false
	Hub.restore_party(gs, party)
	party_retreated.emit(current_hub)
	return true
