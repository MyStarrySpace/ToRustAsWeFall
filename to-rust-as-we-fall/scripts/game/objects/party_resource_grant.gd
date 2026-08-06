class_name PartyResourceGrant
extends RefCounted

## Reusable consequence kit for a visible supply cache, ration bundle, or other
## authored party resource source. Chunks choose the source, recipients, and
## quantities; this kit owns the logged GameState stat mutations so rewards do
## not become bespoke, untracked chunk-side consequences.
static func apply(game_state: GameState, member_ids: Array, deltas: Dictionary) -> Array[String]:
	var affected: Array[String] = []
	if game_state == null:
		return affected
	for member_value in member_ids:
		var member_id := str(member_value)
		if member_id.is_empty() or not game_state.characters.has(member_id):
			continue
		for stat_value in deltas.keys():
			var stat := str(stat_value)
			var delta := float(deltas[stat_value])
			if stat.is_empty() or is_zero_approx(delta):
				continue
			game_state.adjust_stat(member_id, stat, delta)
		affected.append(member_id)
	return affected
