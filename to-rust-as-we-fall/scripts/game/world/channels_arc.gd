class_name ChannelsArc
extends RefCounted

## The coordinate bridge between the wash-relay gauntlet's LINEAR data layer and the CURVED channels
## spiral in the world. The data layer (GameState grid, sections, wash, movement, enemies) runs flat in
## (s, lane): s = progress ALONG the gauntlet (the old gameplay x), lane = lateral offset across the path
## (the old z). This transform wraps that flat strip into an ascending helix for rendering + input:
##
##   s     -> angle (A0 + s*KTHETA) AND height (Y0 + s*KCLIMB)   — the helix climbs monotonically with s
##   lane  -> radius (R0 + lane)                                  — lateral offset is a radial offset
##
## Because height is a strictly-increasing function of s, `world_to_arc` recovers s from a clicked floor
## point's HEIGHT (unambiguous even though the spiral overlaps itself in plan) and lane from its radius.
## A point that actually sits on a deck is therefore mapped back to the s/lane that produced it — the
## round-trip is exact. The model (channels.glb) is built along this SAME helix, so data and visuals align.

const CENTER := Vector3.ZERO
const R0 := 11.0           # helix radius at lane 0 (the path centreline)
const LANE_HALF := 4.0     # half the walkable width (matches the gauntlet's FLOOR_Z_HALF)
const A0 := 0.0            # start angle (s = 0)
const KTHETA := 0.0907     # radians of sweep per unit s  (~1.3 turns over S_MAX)
const Y0 := 1.0            # world height at s = 0
const KCLIMB := 0.1333     # world height climbed per unit s
const S_MAX := 185.0       # 2.5 spiral turns + the entry bridge (one turn = 2*PI/KTHETA ~= 69.3 s)

## Linear (s, lane) -> world point on the helix.
static func arc_pos(s: float, lane: float = 0.0) -> Vector3:
	var ang := A0 + s * KTHETA
	var rad := R0 + lane
	return Vector3(CENTER.x + rad * cos(ang), Y0 + s * KCLIMB, CENTER.z + rad * sin(ang))

## World point (assumed on a deck) -> linear (s, lane). lane from radius; s from the helix ANGLE, with the TURN
## disambiguated by height. Deriving s from angle (not height) keeps a CLICK aligned with the cursor even though
## the deck the ray hits sits a little off the arc centreline (deck thickness / surface) — a height-only inverse
## turned that small Y offset into a ~2-unit s error, so the grid/ghost landed off the cursor. Turns are ~9.24
## world-units apart in Y (TAU/KTHETA * KCLIMB), far more than any deck offset, so the height-based turn pick is
## robust. Round-trips exactly for a point actually on the helix.
static func world_to_arc(world: Vector3) -> Dictionary:
	var d := Vector2(world.x - CENTER.x, world.z - CENTER.z).length()
	var period_s := TAU / KTHETA
	var ang := atan2(world.z - CENTER.z, world.x - CENTER.x) - A0   # helix angle (wrapped to [-PI, PI])
	var s_in_turn := ang / KTHETA
	var s_height := (world.y - Y0) / KCLIMB
	var turn := roundf((s_height - s_in_turn) / period_s)
	return {"s": s_in_turn + turn * period_s, "lane": d - R0}

## The forward (increasing-s) horizontal heading at progress s — for facing characters along the path.
static func tangent(s: float) -> Vector3:
	var ang := A0 + s * KTHETA
	return Vector3(-sin(ang), 0.0, cos(ang)).normalized()

## A full basis (right, up, forward) at s — `right` points outward (increasing lane), `forward` along +s.
static func basis_at(s: float) -> Basis:
	var fwd := tangent(s)
	var ang := A0 + s * KTHETA
	var right := Vector3(cos(ang), 0.0, sin(ang))   # radial outward = +lane direction
	return Basis(right, Vector3.UP, fwd)
