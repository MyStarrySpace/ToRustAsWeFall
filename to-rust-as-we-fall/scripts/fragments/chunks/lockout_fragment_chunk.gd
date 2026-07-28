extends "res://scripts/fragments/chunks/lockout_chase_chunk.gd"

## Compatibility alias for old preview/editor references.
##
## The former file implemented a second, contradictory "chase" with animated
## SphereMeshes and a local caught flag. Keeping that prototype reachable meant
## the same story beat had two different physical laws. This wrapper deliberately
## inherits the production Lockout Chase instead: old scene paths remain valid,
## while Enemy, GameState, shelter, lever, and save/replay authority all come from
## the one canonical implementation.


func get_scene_title() -> String:
	return "The Lockout Chase (legacy alias)"
