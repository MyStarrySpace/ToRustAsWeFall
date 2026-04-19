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
## Fired when a portal is taken. Scenes use this to trigger transition
## fades / loading screens; the ZoneManager itself has already updated
## current_zone and current_hub by the time this fires.
signal portal_taken(portal_id: StringName)

var zones: Dictionary = {}   # id (StringName) → Zone
var hubs: Dictionary = {}    # id (StringName) → Hub
var gates: Dictionary = {}   # id (StringName) → Gate
var portals: Dictionary = {} # id (StringName) → Portal

var current_zone: StringName = &""
var current_hub: StringName = &""
var _completed_spokes: Dictionary = {}  # spoke_id → true
var _passed_gates: Dictionary = {}      # gate_id → true

## Per-zone persistent state (enemy rosters, NPC states, environmental
## flags). Scenes write their state on zone-exit and read it back on
## re-entry. Surviving through zone transitions means revisits feel like
## returning to a real place, not a freshly-spawned instance.
var _zone_state: Dictionary = {}     # zone_id → Dictionary
## How many times each zone has been entered. First entry = 1. Scenes
## use this to spawn differently on revisits (harder enemies, shifted
## NPC dialogue, different environmental conditions).
var _visit_count: Dictionary = {}    # zone_id → int
## Optional per-zone revisit transforms. When a zone is re-entered
## (visit_count >= 2), the transform is applied to the saved state
## before the scene reads it. Callable signature: (state: Dict) -> Dict.
var _revisit_transforms: Dictionary = {}  # zone_id → Callable

func register_zone(z: Zone) -> void:
	zones[z.id] = z

func register_hub(h: Hub) -> void:
	hubs[h.id] = h

func register_gate(g: Gate) -> void:
	gates[g.id] = g

func register_portal(p: Portal) -> void:
	portals[p.id] = p

## Register a transform to apply on revisits. Signature: (state: Dict) -> Dict.
## Called on every entry after the first, before the scene reads state.
func register_revisit_transform(zone_id: StringName, transform: Callable) -> void:
	_revisit_transforms[zone_id] = transform

## Declare a zone transition. Emits zone_exited for the previous zone
## (if any) and zone_entered for the new one. Increments the new zone's
## visit_count. If this is a revisit and a revisit transform is
## registered, applies it to the saved state before the scene reads it.
func enter_zone(zone_id: StringName) -> void:
	if current_zone == zone_id:
		return
	if current_zone != &"":
		zone_exited.emit(current_zone)
	current_zone = zone_id
	var n: int = int(_visit_count.get(zone_id, 0)) + 1
	_visit_count[zone_id] = n
	if n >= 2 and _revisit_transforms.has(zone_id) and _zone_state.has(zone_id):
		var transform: Callable = _revisit_transforms[zone_id]
		if transform.is_valid():
			var saved: Dictionary = _zone_state[zone_id]
			var transformed: Variant = transform.call(saved)
			if transformed is Dictionary:
				_zone_state[zone_id] = transformed
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

## Take a portal: transition to its destination zone and enter the
## declared re-entry hub. Returns true if the portal exists and the
## transition happened. Scenes hook portal_taken for transition visuals;
## the hub_entered signal also fires because the portal lands at a hub.
func take_portal(portal_id: StringName, gs: GameState, party: Array) -> bool:
	if not portals.has(portal_id):
		return false
	var p: Portal = portals[portal_id]
	enter_zone(p.to_zone_id)
	if hubs.has(p.to_hub_id):
		enter_hub(p.to_hub_id, gs, party)
	portal_taken.emit(portal_id)
	return true

## Save a zone's state (enemy rosters, NPC states, flags). Scenes call
## this on zone-exit so the state is preserved through zone transitions.
## Takes a Dictionary so scenes can structure it however they like.
func save_zone_state(zone_id: StringName, state: Dictionary) -> void:
	_zone_state[zone_id] = state.duplicate(true)

## Read a zone's saved state. Returns an empty dict if never saved.
## If a revisit transform ran on the last enter_zone, the returned state
## already includes those changes.
func get_zone_state(zone_id: StringName) -> Dictionary:
	return _zone_state.get(zone_id, {}).duplicate(true)

func get_visit_count(zone_id: StringName) -> int:
	return int(_visit_count.get(zone_id, 0))

func is_first_visit(zone_id: StringName) -> bool:
	return get_visit_count(zone_id) <= 1

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
