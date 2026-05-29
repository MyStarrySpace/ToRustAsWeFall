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
## Character ids who must be in the party AND narratively available for
## the gate to open. Aster and Peris are typically implicit, set by the
## scene when it declares its gates.
var required_members: Array[StringName] = []

func try_pass(gs: GameState, party: Array) -> bool:
	for req in required_members:
		var req_str := String(req)
		if not (req_str in party):
			blocked.emit(StringName("missing_" + req_str))
			return false
		if not gs.is_narratively_available(req_str):
			blocked.emit(StringName("unavailable_" + req_str))
			return false
	passed.emit()
	return true
