class_name SpiralCoordMap
extends RefCounted

## A GameState.coord_map that warps a generated level's FLAT grid onto a DESCENDING HELIX — the same trick the
## hand-authored Channels use (see ChannelsArc), but PARAMETERIZED to the level's own dimensions. The data layer
## stays flat (grid, movement, detection, traversibility all unchanged); only the WORLD render + click inverse go
## through here, so the player walks a straight linear grid while the world is a big spiral around a centre. Height
## DESCENDS monotonically with progress (entry at the top, exit shelter at the bottom), so the spiral never self-
## collides and world->flat is exact (turn picked by height). Stacked turns provide anchors for gated lower->upper
## recovery climbvines; they are not always-on forward drops. Build it from the level's navigation_grid: s =
## progress along the level (data x, normalised to 0), lane = lateral offset (data z, centred).

var center := Vector3.ZERO
var r0 := 9.0            # helix radius at the path centreline (lane 0)
var a0 := 0.0            # start angle
var ktheta := 0.12      # radians of sweep per unit s (turns * TAU / length)
var y0 := 0.45          # world height at s = 0 (the top of the descent)
var kclimb := -0.15     # world height gained per unit s — NEGATIVE: the helix descends with progress
var s_offset := 0.0     # data-world x that maps to s = 0 (the grid origin)
var lane_center := 0.0  # data-world z of the path centreline

## Build from a unified_grid_v1 grid_data. `turns` ~ how many times the level wraps; `min_radius`/
## `descent_per_turn` shape the spiral. The helix DESCENDS (kclimb < 0): each full turn drops
## `descent_per_turn` world-units, so the cell one turn ahead sits directly below — the geometry that lets a tended
## climbvine grow down to a later turn and provide a physical return to already-resolved ground.
##
## The warp PRESERVES THE METRIC at the centreline: ktheta * r0 = 1 (the ChannelsArc invariant), so one flat
## data unit of s sweeps exactly one world-unit of arc at lane 0 — adjacent cells stay one cell apart on the
## deck, characters/tiles/the hover grid all keep the flat grid's spacing. The radius therefore DERIVES from
## the turn target (one loop = TAU*r0 world-units of deck = w/turns flat units), grown when the deck's inner
## lane would crowd the centre; the effective turn count is recomputed from the final radius so the
## descent-per-turn stays honest (the HubShapeCoordMap pattern).
static func from_grid(grid_data: Dictionary, turns := 0.0, min_radius := 0.0, descent_per_turn := 6.0, base_y := 0.45) -> SpiralCoordMap:
	var m := SpiralCoordMap.new()
	var origin: Array = grid_data.get("origin", [0.0, 0.45, 0.0])
	var cs := float(grid_data.get("cell_size", 1.0))
	var w := float(int(grid_data.get("width", 1))) * cs
	var h := float(int(grid_data.get("height", 1))) * cs
	var t := turns if turns > 0.0 else clampf(w / 40.0, 1.0, 2.5)   # ~1.5 turns for a mid-length level
	m.s_offset = float(origin[0])
	m.lane_center = float(origin[2]) + h * 0.5
	m.r0 = maxf(maxf(w / (t * TAU), h * 0.5 + 2.5), min_radius)
	m.y0 = base_y
	m.ktheta = 1.0 / m.r0                               # arc-length parameterisation at lane 0
	var eff_turns := w * m.ktheta / TAU                 # = t unless the radius floor grew the loop
	m.kclimb = -(descent_per_turn * eff_turns / maxf(1.0, w))   # -> descent_per_turn world-units of DROP per full turn
	return m

## Flat cells (data-x span) per full turn of the helix — the separation between a recovery climbvine's upper and
## lower anchors. Positive; independent of climb/descent direction.
func period_s() -> float:
	return absf(TAU / ktheta) if ktheta != 0.0 else INF

# --- helix math (parameterised ChannelsArc) --------------------------------------------------------------------

func arc_pos(s: float, lane: float) -> Vector3:
	var ang := a0 + s * ktheta
	var rad := r0 + lane
	return Vector3(center.x + rad * cos(ang), y0 + s * kclimb, center.z + rad * sin(ang))

func world_to_arc(world: Vector3) -> Dictionary:
	var d := Vector2(world.x - center.x, world.z - center.z).length()
	var period_s := TAU / ktheta
	var ang := atan2(world.z - center.z, world.x - center.x) - a0
	var s_in_turn := ang / ktheta
	var s_height := (world.y - y0) / kclimb
	var turn := roundf((s_height - s_in_turn) / period_s)
	return {"s": s_in_turn + turn * period_s, "lane": d - r0}

func tangent(s: float) -> Vector3:
	var ang := a0 + s * ktheta
	return Vector3(-sin(ang), 0.0, cos(ang)).normalized()

func basis_at(s: float) -> Basis:
	var ang := a0 + s * ktheta
	var right := Vector3(cos(ang), 0.0, sin(ang))   # radial outward = +lane
	return Basis(right, Vector3.UP, tangent(s))

# --- GameState.coord_map interface (flat data <-> warped world) ------------------------------------------------

## Flat data point (world x = along the level, world z = lateral) -> warped world point on the helix. The flat
## Y ABOVE the deck base (p.y - y0) is preserved as a vertical LIFT, so a point on an upper floor (surface_y one
## level_height higher) rides that much above the helix surface — multi-level stretches stay stacked on the spiral.
func to_world(p: Vector3) -> Vector3:
	return arc_pos(p.x - s_offset, p.z - lane_center) + Vector3.UP * (p.y - y0)

## Warped world point (e.g. a clicked deck) -> flat data point. Returns the deck-base Y (y0); the caller keeps its
## own level (a click snaps to a cell on the character's current floor), so the small per-level lift is discarded.
func to_data(w: Vector3) -> Vector3:
	var r := world_to_arc(w)
	return Vector3(float(r["s"]) + s_offset, y0, float(r["lane"]) + lane_center)

## Upright render orientation at a flat data point (facing along the helix +s tangent).
func to_basis(p: Vector3) -> Basis:
	return basis_at(p.x - s_offset)

## The warp transform (basis + position) at a flat data point — for placing geometry onto the helix. Origin
## carries the same per-level lift as to_world so a slab/marker on an upper floor sits above the helix surface.
func to_xform(p: Vector3) -> Transform3D:
	var s := p.x - s_offset
	return Transform3D(basis_at(s), arc_pos(s, p.z - lane_center) + Vector3.UP * (p.y - y0))
