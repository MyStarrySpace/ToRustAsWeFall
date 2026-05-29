class_name ZoneManager
extends RefCounted

## Tracks zone, hub, spoke, gate, and portal progression.
## Only the active zone's hubs remain reachable.

signal zone_entered(zone_id: StringName)
signal zone_exited(zone_id: StringName)
signal hub_entered(hub_id: StringName)
signal gate_passed(gate_id: StringName)
signal gate_blocked(gate_id: StringName, reason: StringName)
signal spoke_completed(spoke_id: StringName)
## Fired after a downed-party retreat to a hub.
signal party_retreated(hub_id: StringName)
## Fired after portal transition.
signal portal_taken(portal_id: StringName)

var zones: Dictionary = {}   # id (StringName) → Zone
var hubs: Dictionary = {}    # id (StringName) → Hub
var gates: Dictionary = {}   # id (StringName) → Gate
var portals: Dictionary = {} # id (StringName) → Portal

var current_zone: StringName = &""
var current_hub: StringName = &""
var _completed_spokes: Dictionary = {}  # spoke_id → true
var _passed_gates: Dictionary = {}      # gate_id → true

## Per-zone state saved across exits and revisits.
var _zone_state: Dictionary = {}     # zone_id → Dictionary
## Entry count per zone. First entry = 1.
var _visit_count: Dictionary = {}    # zone_id → int
## Optional state transform applied before revisit reads.
var _revisit_transforms: Dictionary = {}  # zone_id → Callable

func register_zone(z: Zone) -> void:
	zones[z.id] = z

func register_hub(h: Hub) -> void:
	hubs[h.id] = h

func register_gate(g: Gate) -> void:
	gates[g.id] = g

func register_portal(p: Portal) -> void:
	portals[p.id] = p

## Register a revisit transform: (state: Dict) -> Dict.
func register_revisit_transform(zone_id: StringName, transform: Callable) -> void:
	_revisit_transforms[zone_id] = transform

## Enter a zone and apply its revisit transform if needed.
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

## Enter a hub and rest the party.
func enter_hub(hub_id: StringName, gs: GameState, party: Array) -> void:
	if not hubs.has(hub_id):
		return
	current_hub = hub_id
	hub_entered.emit(hub_id)
	Hub.restore_party(gs, party)

## Attempt a gate pass and emit pass/block signals.
func try_pass_gate(gate_id: StringName, gs: GameState, party: Array) -> bool:
	if not gates.has(gate_id):
		return false
	var g: Gate = gates[gate_id]
	# Bridge one gate result into ZoneManager signals.
	var block_handler := func(reason: StringName) -> void:
		_passed_gates.erase(gate_id)
		gate_blocked.emit(gate_id, reason)
	var pass_handler := func() -> void:
		_passed_gates[gate_id] = true
		gate_passed.emit(gate_id)
	g.blocked.connect(block_handler, CONNECT_ONE_SHOT)
	g.passed.connect(pass_handler, CONNECT_ONE_SHOT)
	var ok := g.try_pass(gs, party)
	# Clean up any unused one-shot connection.
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

## Reachable only while its zone is active.
func is_hub_reachable(hub_id: StringName) -> bool:
	if not hubs.has(hub_id):
		return false
	var hub: Hub = hubs[hub_id]
	return hub.zone_id == current_zone

## Take a portal to its destination zone and hub.
func take_portal(portal_id: StringName, gs: GameState, party: Array) -> bool:
	if not portals.has(portal_id):
		return false
	var p: Portal = portals[portal_id]
	enter_zone(p.to_zone_id)
	if hubs.has(p.to_hub_id):
		enter_hub(p.to_hub_id, gs, party)
	portal_taken.emit(portal_id)
	return true

## Save scene-owned zone state.
func save_zone_state(zone_id: StringName, state: Dictionary) -> void:
	_zone_state[zone_id] = state.duplicate(true)

## Read saved zone state.
func get_zone_state(zone_id: StringName) -> Dictionary:
	return _zone_state.get(zone_id, {}).duplicate(true)

func get_visit_count(zone_id: StringName) -> int:
	return int(_visit_count.get(zone_id, 0))

func is_first_visit(zone_id: StringName) -> bool:
	return get_visit_count(zone_id) <= 1

## Retreat a downed party to the last hub.
func retreat_to_last_hub(gs: GameState, party: Array) -> bool:
	if current_hub == &"":
		return false
	if not hubs.has(current_hub):
		return false
	Hub.restore_party(gs, party)
	party_retreated.emit(current_hub)
	return true
