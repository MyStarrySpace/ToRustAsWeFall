class_name MetaTemplate
extends RefCounted

## A META-TEMPLATE is a level's MACRO shape. Every template is the same grammar:
##   1. a PLANE you fall down to (the spiral's lower turns; or a circle/rectangle hub disc),
##   2. RETURN POINTS connecting the stretches back UP to it from one side (drop-down portals, climbvines),
##   3. puzzle/survival STRETCHES strung between the return points.
## Concretely a template provides the flat<->world WARP (a coord_map) and the RETURN-POINT specs; the chunk builds
## the geometry from them. The spiral is one instance (SpiralMetaTemplate); a rectangle/ring hub is another. This
## base is the FLAT (no-warp) template — an authored level plays as drawn.

## Stable id (for config selection + tests).
func template_id() -> String:
	return "flat"

## The flat-data <-> warped-world map for this shape, or null for a flat template. The chunk installs it as
## GameState.coord_map (characters render + clicks invert through it) and warps its own floor/dressing with it.
func build_coord_map(_spine_nav: Dictionary):
	return null

## Return points that connect stretches back to the fall-to plane. Each spec:
##   {kind:"drop"|"climb", upper:Vector3(flat deck pt, higher), lower:Vector3(flat deck pt, lower)}
## "drop" = fall from `upper` down to `lower` (a shortcut forward); "climb" = a CLIMBVINE back UP from `lower` to
## `upper` (the return). Points are FLAT data coordinates; the chunk warps them onto the world shape. Empty = none.
func return_point_specs(_spine_nav: Dictionary, _coord_map) -> Array:
	return []
