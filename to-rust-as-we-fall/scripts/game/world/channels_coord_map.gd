class_name ChannelsCoordMap
extends RefCounted

## A GameState.coord_map that wraps ChannelsArc: it presents the flat wash-relay data frame on the
## channels HELIX. The data layer stays flat (s = gameplay x, lane = gameplay z); node followers render
## through to_world, and a click on the helix floor maps back through to_data. Install on a scene's
## GameState (`gs.coord_map = ChannelsCoordMap.new()`) to move the playable system onto the spiral.

## Flat data point (s in x, lane in z) -> world point on the helix.
func to_world(p: Vector3) -> Vector3:
	return ChannelsArc.arc_pos(p.x, p.z)

## World point on the helix (e.g. a clicked deck) -> flat data point (s in x, lane in z).
func to_data(w: Vector3) -> Vector3:
	var r := ChannelsArc.world_to_arc(w)
	return Vector3(r["s"], 0.0, r["lane"])

## The render orientation at a flat data point — upright, facing along the helix's forward (+s) tangent.
func to_basis(p: Vector3) -> Basis:
	return ChannelsArc.basis_at(p.x)
