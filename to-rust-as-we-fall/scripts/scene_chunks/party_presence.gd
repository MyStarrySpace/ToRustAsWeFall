class_name PartyPresence
extends Node

## Declares which characters are in the party at this point in the game. Add one as
## a child of a chunk scene to configure a standalone preview so it boots with the
## party that would actually be together at that story beat. The chunk exposes it
## via SceneChunk.get_party_presence(); the preview host hides absent members so
## they can't be selected or moved.
##
## No PartyPresence node => the host keeps its full default roster (current
## behaviour). The feature is opt-in per scene instance.

@export var aster_present := true
@export var peris_present := true
@export var endo_present := false
@export var myke_present := false

## Character id -> present flag for the roster the preview can model.
func presence_map() -> Dictionary:
	return {
		"aster": aster_present,
		"peris": peris_present,
		"endo": endo_present,
		"myke": myke_present,
	}

## Just the present character ids, in roster order.
func present_ids() -> Array:
	var ids: Array = []
	var map := presence_map()
	for char_id in map:
		if bool(map[char_id]):
			ids.append(char_id)
	return ids
