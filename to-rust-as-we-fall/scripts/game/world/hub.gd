class_name Hub
extends RefCounted

## A safe location within a zone. Entering records position/progression only; it is not
## a recovery verb. Shelter recovery happens when characters explicitly commit to rest
## through GameState's shelter system, and ATP is replenished only by endocytosing lysate.
##
## Hubs are checkpoints the party passes
## through. The zone's other hubs remain reachable while the zone is
## active; once the party progresses to a subsequent zone, older hubs
## fall out of practical reach.

var id: StringName = &""
var zone_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var radius: float = 2.0

## Checkpoint-only escape from a full-party wipe. This is deliberately named separately
## from rest: it prevents a soft-lock and preserves ATP rather than acting as free recovery.
static func revive_party_after_wipe(gs: GameState, party: Array) -> bool:
	if not gs.is_party_downed(party):
		return false
	for char_id in party:
		gs.restore_character(char_id)
	return true
