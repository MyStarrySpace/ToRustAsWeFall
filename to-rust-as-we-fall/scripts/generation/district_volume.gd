class_name DistrictVolume
extends RefCounted

## THE DISTRICT'S 3D RESERVATION GRID — the measure-first method at district scale. Every filler
## subsystem CLAIMS its volume BEFORE geometry is emitted: walkable street columns claim their
## head-room band, viaduct corridors claim their deck band (piers their full column), landmark
## heroes and fabric lots claim their build volumes. A claim that overlaps a different owner is
## recorded as a loud conflict string (survey-style) instead of becoming a road through a
## building; free_top() lets an emitter clamp what it raises under an overhead corridor. The
## companion audit() re-derives violations from the EMITTED boxes, so the guarantee is checked
## twice: at reservation time and against the actual geometry.

const STREET_CLEARANCE := 3.0    # the character head-room law: nothing intrudes a walkable column below this
const EPS := 0.02

var cell_size := 1.5
var origin := Vector3.ZERO
var width := 0
var height := 0
var _claims := {}                # Vector2i -> Array of {y0, y1, owner}
var conflicts: Array = []

static func over_grid(grid: Dictionary) -> DistrictVolume:
	var v := DistrictVolume.new()
	v.cell_size = float(grid.get("cell_size", 1.5))
	var o: Array = grid.get("origin", [0.0, 0.0, 0.0])
	v.origin = Vector3(float(o[0]), float(o[1]), float(o[2]))
	v.width = int(grid.get("width", 0))
	v.height = int(grid.get("height", 0))
	return v

func world_to_cell(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x - origin.x) / cell_size)), int(floor((z - origin.z) / cell_size)))

## Claim one column interval. A cross-owner overlap records a conflict (and still claims, so one
## bad reservation doesn't hide a second overlapping it). Same-owner overlaps merge silently.
func claim_cell(cell: Vector2i, y0: float, y1: float, owner: String) -> bool:
	var ok := true
	if not _claims.has(cell):
		_claims[cell] = []
	for cl in _claims[cell]:
		if str(cl["owner"]) == owner:
			continue
		if y0 < float(cl["y1"]) - EPS and y1 > float(cl["y0"]) + EPS:
			conflicts.append("cell %s: '%s' [%.1f..%.1f] overlaps '%s' [%.1f..%.1f]"
				% [str(cell), owner, y0, y1, str(cl["owner"]), float(cl["y0"]), float(cl["y1"])])
			ok = false
	(_claims[cell] as Array).append({"y0": y0, "y1": y1, "owner": owner})
	return ok

func claim_rect(c0: Vector2i, c1: Vector2i, y0: float, y1: float, owner: String) -> bool:
	var ok := true
	for z in range(mini(c0.y, c1.y), maxi(c0.y, c1.y) + 1):
		for x in range(mini(c0.x, c1.x), maxi(c0.x, c1.x) + 1):
			ok = claim_cell(Vector2i(x, z), y0, y1, owner) and ok
	return ok

## The first FOREIGN owner blocking an interval in a column ("" = free).
func blocked(cell: Vector2i, y0: float, y1: float, ignore_owner := "") -> String:
	for cl in _claims.get(cell, []):
		if str(cl["owner"]) == ignore_owner:
			continue
		if y0 < float(cl["y1"]) - EPS and y1 > float(cl["y0"]) + EPS:
			return str(cl["owner"])
	return ""

func rect_blocked(c0: Vector2i, c1: Vector2i, y0: float, y1: float, ignore_owner := "") -> String:
	for z in range(mini(c0.y, c1.y), maxi(c0.y, c1.y) + 1):
		for x in range(mini(c0.x, c1.x), maxi(c0.x, c1.x) + 1):
			var who := blocked(Vector2i(x, z), y0, y1, ignore_owner)
			if who != "":
				return "%s@%s" % [who, str(Vector2i(x, z))]
	return ""

## The lowest foreign claim BOTTOM above from_y anywhere in the rect — the ceiling an emitter must
## stay under (INF when the sky is clear). Streets are ignored (their claim is below anyway).
func free_top(c0: Vector2i, c1: Vector2i, from_y: float, ignore_owner := "") -> float:
	var top := INF
	for z in range(mini(c0.y, c1.y), maxi(c0.y, c1.y) + 1):
		for x in range(mini(c0.x, c1.x), maxi(c0.x, c1.x) + 1):
			for cl in _claims.get(Vector2i(x, z), []):
				var ow := str(cl["owner"])
				if ow == ignore_owner or ow == "street":
					continue
				if float(cl["y1"]) > from_y + EPS and float(cl["y0"]) < top:
					top = maxf(float(cl["y0"]), from_y)
	return top

## Streets claim their head-room: every walkable column, ground to clearance.
func claim_streets(walk: Dictionary) -> void:
	for cell in walk:
		claim_cell(cell as Vector2i, 0.0, STREET_CLEARANCE, "street")

## AUDIT — the geometry-side check. Every emitted box AABB is tested against the two corridor
## classes the reservations protect: (1) no box intrudes a WALKABLE street column below the
## clearance band; (2) no non-viaduct box enters a viaduct corridor band. Returns loud strings.
func audit_boxes(walls: Array, from_idx: int, to_idx: int, walk: Dictionary,
		corridors: Array) -> Array:
	var out: Array = []
	for i in range(from_idx, mini(to_idx, walls.size())):
		var wd := walls[i] as Dictionary
		var pos: Vector3 = wd.get("pos", Vector3.ZERO)
		var size: Vector3 = wd.get("size", Vector3.ONE)
		var y0 := pos.y - size.y * 0.5
		var y1 := pos.y + size.y * 0.5
		var c0 := world_to_cell(pos.x - size.x * 0.5 + EPS, pos.z - size.z * 0.5 + EPS)
		var c1 := world_to_cell(pos.x + size.x * 0.5 - EPS, pos.z + size.z * 0.5 - EPS)
		for z in range(c0.y, c1.y + 1):
			for x in range(c0.x, c1.x + 1):
				var cell := Vector2i(x, z)
				if walk.has(cell) and y0 < STREET_CLEARANCE - EPS and y1 > 0.1:
					out.append("box %d (%.1f,%.1f,%.1f) intrudes street column %s below clearance"
						% [i, pos.x, pos.y, pos.z, str(cell)])
		for cor in corridors:
			var cd := cor as Dictionary
			if y1 < float(cd["y0"]) + EPS or y0 > float(cd["y1"]) - EPS:
				continue
			var axis := int(cd["axis"])
			var lane := int(cd["lane"])
			var hits := false
			if axis == 0:
				hits = c0.y <= lane and c1.y >= lane
			else:
				hits = c0.x <= lane and c1.x >= lane
			if hits:
				out.append("box %d (%.1f,%.1f,%.1f) enters viaduct corridor axis%d lane%d band [%.1f..%.1f]"
					% [i, pos.x, pos.y, pos.z, axis, lane, float(cd["y0"]), float(cd["y1"])])
	return out
