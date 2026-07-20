class_name Gate
extends RefCounted

## Environmental obstacle that requires specific party members to pass.
## The obstacle is in the world: a heavy door, a terminal that only
## Aster can access, a conduit only Endo can interface with. The predicate
## is declared as a list of required character ids; a future extension
## can swap in a richer predicate Callable.
##
## try_pass returns true if the gate opens, false otherwise, and emits
## either `passed` or `blocked(reason)`. The reason is a StringName so
## UI can map it to localized text.

signal passed
signal blocked(reason: StringName)

var id: StringName = &""
var zone_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var radius: float = 1.0
## When enabled, every required member must also be physically inside `radius`.
## Kept opt-in so existing narrative/roster gates retain their original semantics.
var require_proximity := false
## Character ids who must be in the party AND narratively available for
## the gate to open. Aster and Peris are typically implicit, set by the
## scene when it declares its gates.
var required_members: Array[StringName] = []

## Pure predicate shared by world barriers, delayed transitions, UI previews, and tests.
## An empty reason means the gate is satisfied; otherwise the reason names both
## the failed condition and member so presentation code can stay data-driven.
func blocking_reason(gs: GameState, party: Array) -> StringName:
	for req in required_members:
		var req_str := String(req)
		if not (req_str in party):
			return StringName("missing_" + req_str)
		if not gs.is_narratively_available(req_str):
			return StringName("unavailable_" + req_str)
		if require_proximity:
			var member_pos := gs.get_position(req_str)
			if not member_pos.is_finite() or Vector2(
				member_pos.x - position.x, member_pos.z - position.z
			).length() > radius:
				return StringName("out_of_range_" + req_str)
	return &""

func is_satisfied(gs: GameState, party: Array) -> bool:
	return blocking_reason(gs, party) == &""

func try_pass(gs: GameState, party: Array) -> bool:
	var reason := blocking_reason(gs, party)
	if reason != &"":
		blocked.emit(reason)
		return false
	passed.emit()
	return true
