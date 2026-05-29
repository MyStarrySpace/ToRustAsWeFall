class_name Hub
extends RefCounted

## A safe space within a zone. Entering a hub restores every party
## member's HP / ATP / stamina and marks them narratively available.
##
## Hubs are checkpoints the party passes
## through. The zone's other hubs remain reachable while the zone is
## active; once the party progresses to a subsequent zone, older hubs
## fall out of practical reach.

var id: StringName = &""
var zone_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var radius: float = 2.0

## Restore every party member. Each restore goes through the event log
## as its own command; replay reproduces the rest beat exactly.
static func restore_party(gs: GameState, party: Array) -> void:
	for char_id in party:
		gs.restore_character(char_id)
