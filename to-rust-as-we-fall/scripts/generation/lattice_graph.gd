class_name LatticeGraph
extends RefCounted

## The lattice JUNCTION ENGINE — a 2D planar rib network fused into ONE watertight moulding mesh.
##
## Sweeping each rib path independently and bumping only detected interior crossings would miss every
## T-joint (an endpoint landing ON another rib) and L-joint (two endpoints meeting), leave every tube
## end an open ring, and let half the sweeps wind inside-out — the "shards and holes" read. The engine
## instead treats jointing as a whole-graph problem:
##
##   1. `build(paths)` — a PLANAR GRAPH: every path is split at X-crossings AND at T-touches, endpoints
##      are welded into NODES, and degree-2 nodes are chained away. What remains: edges (rib runs),
##      nodes of degree 1 (free ends) or >=3 (junctions), and closed loops.
##   2. `mesh(...)` — WATERTIGHT meshing over a surface functor (drum or plane): each edge sweeps a
##      CLOSED profile ring (half-round crest + a skirt sunk `embed` INTO the wall, so drum faceting
##      can never open a gap behind the rib); each junction is a dome hub whose arm MOUTH RINGS are the
##      exact rings the tubes terminate on (shared vertices — no cracks by construction); free ends are
##      capped; loops sweep closed. Every triangle goes through `_face`, which orients it against a
##      local interior reference point — inside-out winding is structurally impossible.
##
## Invariant (asserted in tests): `boundary_edge_count(mesh) == 0` — the whole rib network is a closed
## 2-manifold. A hole is a red test, not a capture surprise.

# ============================================================================================
# GRAPH — pure 2D, deterministic, no RNG.
# ============================================================================================

## Build the planar graph. `paths`: Array of PackedVector2Array in lattice space (x = arc-length or
## face-u, y = height). Returns {"nodes": [{pos, arms:[{edge:int, end:int}]}], "edges": [{a:int, b:int,
## pts: PackedVector2Array}], "loops": [PackedVector2Array]}. `eps` = weld/touch tolerance.
static func build(paths: Array, eps: float = 0.02) -> Dictionary:
	# --- normalize input: drop degenerate paths, copy so we never mutate the caller's arrays ---
	var polys: Array = []
	for p in paths:
		var pv := PackedVector2Array(p as PackedVector2Array)
		if pv.size() >= 2:
			polys.append(pv)
	# --- collect split events per (path, seg): interior X-crossings + T-touches ---
	var splits: Array = []            # splits[i] = Array of {"seg": int, "t": float}
	for i in range(polys.size()):
		splits.append([])
	_collect_crossings(polys, splits)
	_collect_touches(polys, splits, eps)
	# --- apply splits: each path -> one or more sub-polylines ---
	var subs: Array = []              # Array of PackedVector2Array
	for i in range(polys.size()):
		subs.append_array(_split_poly(polys[i], splits[i]))
	# --- weld endpoints into nodes ---
	var node_pos: Array = []          # Array of Vector2
	var edges: Array = []             # [{a,b,pts}]
	for sp in subs:
		var pts := sp as PackedVector2Array
		var a := _weld(node_pos, pts[0], eps)
		var b := _weld(node_pos, pts[pts.size() - 1], eps)
		pts[0] = node_pos[a]
		pts[pts.size() - 1] = node_pos[b]
		if a == b and _poly_len(pts) < eps * 3.0:
			continue   # two splits inside the weld eps -> a zero-length self-edge; meshing it would crash
		edges.append({"a": a, "b": b, "pts": pts})
	# --- chain degree-2 nodes away; detect closed loops ---
	var loops: Array = []
	_chain(node_pos, edges, loops)
	# --- assemble arm lists for the surviving nodes ---
	var nodes: Array = []
	var remap: Dictionary = {}
	for e_i in range(edges.size()):
		var e: Dictionary = edges[e_i]
		for end in [0, 1]:
			var ni: int = int(e["a"]) if end == 0 else int(e["b"])
			if not remap.has(ni):
				remap[ni] = nodes.size()
				nodes.append({"pos": node_pos[ni], "arms": []})
			(nodes[remap[ni]]["arms"] as Array).append({"edge": e_i, "end": end})
		e["a"] = remap[e["a"]]
		e["b"] = remap[e["b"]]
	return {"nodes": nodes, "edges": edges, "loops": loops}

static func _poly_rect(pts: PackedVector2Array) -> Rect2:
	var rect := Rect2(pts[0], Vector2.ZERO)
	for i in range(1, pts.size()):
		rect = rect.expand(pts[i])
	return rect

# Interior X-crossings between every pair of segments (different paths, and non-adjacent segments of
# the SAME path — a curl can cross itself). Both sides get a split event. Path-pair AABB rejects keep
# this near-linear on networks that mostly DON'T cross (a grid lattice, distant bays).
static func _collect_crossings(polys: Array, splits: Array) -> void:
	var boxes: Array = []
	for pv in polys:
		boxes.append(_poly_rect(pv as PackedVector2Array))
	for i in range(polys.size()):
		var pa := polys[i] as PackedVector2Array
		for j in range(i, polys.size()):
			if i != j and not (boxes[i] as Rect2).intersects(boxes[j] as Rect2):
				continue
			var pb := polys[j] as PackedVector2Array
			for si in range(pa.size() - 1):
				var sj0 := si + 2 if i == j else 0   # same path: skip self + adjacent segments
				for sj in range(sj0, pb.size() - 1):
					if i == j and sj <= si + 1:
						continue
					var hit := _seg_hit(pa[si], pa[si + 1], pb[sj], pb[sj + 1])
					if bool(hit["hit"]):
						(splits[i] as Array).append({"seg": si, "t": float(hit["t"])})
						(splits[j] as Array).append({"seg": sj, "t": float(hit["u"])})

# T-touches: a path ENDPOINT lying on (or within eps of) another path's segment interior. This is the
# joint class interior-only crossing detection can never see — arch feet on mullions, sill ends, etc.
static func _collect_touches(polys: Array, splits: Array, eps: float) -> void:
	var boxes: Array = []
	for pv in polys:
		boxes.append(_poly_rect(pv as PackedVector2Array).grow(eps))
	for i in range(polys.size()):
		var pa := polys[i] as PackedVector2Array
		for which in [0, pa.size() - 1]:
			var e: Vector2 = pa[which]
			for j in range(polys.size()):
				if j == i:
					continue
				if not (boxes[j] as Rect2).has_point(e):
					continue
				var pb := polys[j] as PackedVector2Array
				for sj in range(pb.size() - 1):
					var b0 := pb[sj]
					var b1 := pb[sj + 1]
					var seg := b1 - b0
					var len2 := seg.length_squared()
					if len2 < 1.0e-12:
						continue
					var u := clampf((e - b0).dot(seg) / len2, 0.0, 1.0)
					var cp := b0 + seg * u
					if cp.distance_to(e) < eps:
						# interior only — an endpoint near the segment's own endpoint is a WELD, not a split
						var du := eps / sqrt(len2)
						if u > du and u < 1.0 - du:
							(splits[j] as Array).append({"seg": sj, "t": u})

# Cut one polyline at its recorded (seg, t) events -> ordered sub-polylines (split points deduped).
static func _split_poly(poly: PackedVector2Array, events: Array) -> Array:
	if events.is_empty():
		return [poly]
	var evs := events.duplicate()
	evs.sort_custom(func(x, y) -> bool:
		var xd := x as Dictionary
		var yd := y as Dictionary
		if int(xd["seg"]) != int(yd["seg"]):
			return int(xd["seg"]) < int(yd["seg"])
		return float(xd["t"]) < float(yd["t"]))
	var out: Array = []
	var cur := PackedVector2Array([poly[0]])
	var last_seg := -1
	var last_t := -1.0
	var ev_i := 0
	for s in range(poly.size() - 1):
		while ev_i < evs.size() and int((evs[ev_i] as Dictionary)["seg"]) == s:
			var t := float((evs[ev_i] as Dictionary)["t"])
			ev_i += 1
			if s == last_seg and absf(t - last_t) < 1.0e-4:
				continue   # duplicate event at the same spot
			var cut := poly[s].lerp(poly[s + 1], t)
			if cut.distance_to(cur[cur.size() - 1]) > 1.0e-5:
				cur.append(cut)
			if cur.size() >= 2:
				out.append(cur)
			cur = PackedVector2Array([cut])
			last_seg = s
			last_t = t
		if poly[s + 1].distance_to(cur[cur.size() - 1]) > 1.0e-5:
			cur.append(poly[s + 1])
	if cur.size() >= 2:
		out.append(cur)
	return out

static func _weld(node_pos: Array, p: Vector2, eps: float) -> int:
	for i in range(node_pos.size()):
		if (node_pos[i] as Vector2).distance_to(p) < eps:
			return i
	node_pos.append(p)
	return node_pos.size() - 1

# Merge edges through every degree-2 node (a continuous rib mitres through — no hub needed). A
# degree-2 node whose two arms are the two ends of the SAME edge closes that edge into a LOOP.
static func _chain(node_pos: Array, edges: Array, loops: Array) -> void:
	var changed := true
	while changed:
		changed = false
		# arm census
		var deg: Dictionary = {}
		for e_i in range(edges.size()):
			var e: Dictionary = edges[e_i]
			for ni in [int(e["a"]), int(e["b"])]:
				deg[ni] = int(deg.get(ni, 0)) + 1
		for e_i in range(edges.size()):
			var e: Dictionary = edges[e_i]
			var a := int(e["a"])
			var b := int(e["b"])
			if a == b and int(deg.get(a, 0)) == 2:
				# self-edge with no other arms -> closed loop
				loops.append(e["pts"])
				edges.remove_at(e_i)
				changed = true
				break
		if changed:
			continue
		# find a degree-2 node joining two DIFFERENT edges
		for ni in deg.keys():
			if int(deg[ni]) != 2:
				continue
			var found: Array = []
			for e_i in range(edges.size()):
				var e: Dictionary = edges[e_i]
				if int(e["a"]) == ni:
					found.append({"edge": e_i, "end": 0})
				if int(e["b"]) == ni:
					found.append({"edge": e_i, "end": 1})
			if found.size() != 2 or int((found[0] as Dictionary)["edge"]) == int((found[1] as Dictionary)["edge"]):
				continue
			var f0 := found[0] as Dictionary
			var f1 := found[1] as Dictionary
			var e0: Dictionary = edges[int(f0["edge"])]
			var e1: Dictionary = edges[int(f1["edge"])]
			# orient e0 to END at ni, e1 to START at ni, then concatenate
			var p0 := e0["pts"] as PackedVector2Array
			if int(f0["end"]) == 0:
				p0.reverse()
			var p1 := e1["pts"] as PackedVector2Array
			if int(f1["end"]) == 1:
				p1.reverse()
			var joined := PackedVector2Array(p0)
			for k in range(1, p1.size()):
				joined.append(p1[k])
			var na := int(e0["b"]) if int(f0["end"]) == 0 else int(e0["a"])
			var nb := int(e1["b"]) if int(f1["end"]) == 0 else int(e1["a"])
			var hi := maxi(int(f0["edge"]), int(f1["edge"]))
			var lo := mini(int(f0["edge"]), int(f1["edge"]))
			edges.remove_at(hi)
			edges.remove_at(lo)
			edges.append({"a": na, "b": nb, "pts": joined})
			changed = true
			break

# Segment-segment intersection with both params returned. The margins are a hair PAST the endpoints
# (not a fat relative dead zone — a 2% margin silently dropped every crossing that landed near another
# path's interior VERTEX, leaving the ribs unfused). Splits at/near endpoints are harmless: they
# produce zero-length sub-polylines that _split_poly drops, and the cut point welds into the vertex.
static func _seg_hit(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> Dictionary:
	var da := a2 - a1
	var db := b2 - b1
	var den := da.x * db.y - da.y * db.x
	if absf(den) < 1.0e-9:
		return {"hit": false}
	var t := ((b1.x - a1.x) * db.y - (b1.y - a1.y) * db.x) / den
	var u := ((b1.x - a1.x) * da.y - (b1.y - a1.y) * da.x) / den
	if t > -1.0e-4 and t < 1.0 + 1.0e-4 and u > -1.0e-4 and u < 1.0 + 1.0e-4:
		return {"hit": true, "t": clampf(t, 0.0, 1.0), "u": clampf(u, 0.0, 1.0)}
	return {"hit": false}

# ============================================================================================
# SURFACE FUNCTORS — map lattice 2D -> 3D. Drum: x = arc-length at radius r, y = height.
# ============================================================================================

static func drum_surface(r: float) -> Dictionary:
	return {"type": "drum", "r": r}

static func plane_surface(origin: Vector3, u: Vector3, v: Vector3) -> Dictionary:
	return {"type": "plane", "origin": origin, "u": u.normalized(), "v": v.normalized()}

static func _surf_pos(surf: Dictionary, p: Vector2) -> Vector3:
	if str(surf["type"]) == "drum":
		var r := float(surf["r"])
		var a := p.x / r
		return Vector3(r * cos(a), p.y, r * sin(a))
	return (surf["origin"] as Vector3) + (surf["u"] as Vector3) * p.x + (surf["v"] as Vector3) * p.y

static func _surf_normal(surf: Dictionary, p: Vector2) -> Vector3:
	if str(surf["type"]) == "drum":
		var a := p.x / float(surf["r"])
		return Vector3(cos(a), 0.0, sin(a))
	return ((surf["u"] as Vector3).cross(surf["v"] as Vector3)).normalized()

# 3D direction of a 2D lattice direction at point p (unit).
static func _surf_dir(surf: Dictionary, p: Vector2, d: Vector2) -> Vector3:
	if str(surf["type"]) == "drum":
		var a := p.x / float(surf["r"])
		var u_arc := Vector3(-sin(a), 0.0, cos(a))
		var t := u_arc * d.x + Vector3(0.0, 1.0, 0.0) * d.y
		return t.normalized() if t.length() > 1.0e-9 else u_arc
	var t2 := (surf["u"] as Vector3) * d.x + (surf["v"] as Vector3) * d.y
	return t2.normalized() if t2.length() > 1.0e-9 else (surf["u"] as Vector3)

# Longest 2D segment the surface tolerates before chords visibly leave it (drum curvature).
static func _surf_max_step(surf: Dictionary) -> float:
	if str(surf["type"]) == "drum":
		return maxf(0.05, float(surf["r"]) * 0.10)
	return 1.0e9

# Mapping handedness: the 3D cross of a 2D-CCW triangle points s*n. Drum: d/dx x d/dy = u_arc x Y =
# -radial = -n -> s = -1. Plane: u x v = +n -> s = +1. Lets hub faces wind from their 2D pre-image
# (exact) instead of 3D dot-tests (unstable on near-vertical slivers under drum curvature).
static func _surf_handedness(surf: Dictionary) -> float:
	return -1.0 if str(surf["type"]) == "drum" else 1.0

# ============================================================================================
# MESH — watertight rib network. Profile ring (closed, size sides+3):
#   s in 0..sides        : half-round arc, phi = PI*s/sides, +perp at s=0 (LEFT of travel) -> -perp
#   s = sides+1          : right skirt bottom (-perp, -embed)
#   s = sides+2          : left skirt bottom (+perp, -embed)
# perp = surface_normal x tangent (LEFT of travel). All faces emitted through _face -> never inside-out.
# ============================================================================================

## Mesh the whole graph into `st`. `rib_r` = rib crest radius, `sides` = arc segments (>=3),
## `embed` = skirt depth into the wall (>= drum facet sagitta; default max(rib_r, 0.04)).
static func mesh(st: SurfaceTool, graph: Dictionary, surf: Dictionary, rib_r: float, sides: int = 5, embed: float = -1.0) -> void:
	if embed < 0.0:
		embed = maxf(rib_r, 0.04)
	var nodes := graph["nodes"] as Array
	var edges := graph["edges"] as Array
	var loops := graph["loops"] as Array
	var max_step := _surf_max_step(surf)
	# round sharp interior corners (mitre rings PINCH past ~50 degrees -> locally inside-out quads),
	# then resample against drum curvature. Endpoints preserved -> ring mating intact.
	var epts: Array = []
	for e in edges:
		epts.append(_resample(_round_corners((e as Dictionary)["pts"] as PackedVector2Array, rib_r, false), max_step))
	# --- per-node: sort arms CCW, compute reach + mouth rings, emit hubs / remember caps ---
	var mouth: Dictionary = {}   # "edge:end" -> {"ring": Array[Vector3], "cut": float (arc-length)}
	for n_i in range(nodes.size()):
		var node := nodes[n_i] as Dictionary
		var npos := node["pos"] as Vector2
		var arms := (node["arms"] as Array).duplicate()
		# outgoing 2D direction per arm
		for a_i in range(arms.size()):
			var arm := arms[a_i] as Dictionary
			var pts := epts[int(arm["edge"])] as PackedVector2Array
			var d2 := (pts[1] - pts[0]) if int(arm["end"]) == 0 else (pts[pts.size() - 2] - pts[pts.size() - 1])
			arm["dir"] = d2.normalized()
			arm["ang"] = atan2(d2.y, d2.x)
			arms[a_i] = arm
		arms.sort_custom(func(x, y) -> bool: return float((x as Dictionary)["ang"]) < float((y as Dictionary)["ang"]))
		if arms.size() == 1:
			# free end: terminal ring right at the endpoint, cap it
			var arm := arms[0] as Dictionary
			var ring := _ring_at(surf, npos, (arm["dir"] as Vector2), rib_r, sides, embed)
			_cap_ring(st, ring, surf, npos, (arm["dir"] as Vector2))
			mouth["%d:%d" % [int(arm["edge"]), int(arm["end"])]] = {"ring": ring, "cut": 0.0}
			continue
		# reach per arm from mitre-corner needs against its CCW neighbours
		var m := arms.size()
		for a_i in range(m):
			var arm := arms[a_i] as Dictionary
			var need := rib_r * 1.4
			for nb in [arms[(a_i + 1) % m] as Dictionary, arms[(a_i - 1 + m) % m] as Dictionary]:
				var cosang := clampf((arm["dir"] as Vector2).dot(nb["dir"] as Vector2), -1.0, 1.0)
				var theta := acos(cosang)
				if theta > 1.0e-3:
					need = maxf(need, 1.12 * rib_r / tan(theta * 0.5))
			var reach := clampf(need, rib_r * 1.4, rib_r * 3.5)
			var elen := _poly_len(epts[int(arm["edge"])] as PackedVector2Array)
			arm["reach"] = minf(reach, elen * 0.45)
			arms[a_i] = arm
		# mouth rings (walk each arm's polyline out to reach) + their 2D pre-images for hub winding
		for a_i in range(m):
			var arm := arms[a_i] as Dictionary
			var walk := _walk(epts[int(arm["edge"])] as PackedVector2Array, int(arm["end"]), float(arm["reach"]))
			var ring := _ring_at(surf, walk["pos"] as Vector2, (walk["dir"] as Vector2), rib_r, sides, embed)
			arm["ring"] = ring
			arm["m2"] = walk["pos"]
			arm["md"] = walk["dir"]
			arms[a_i] = arm
			mouth["%d:%d" % [int(arm["edge"]), int(arm["end"])]] = {"ring": ring, "cut": float(arm["reach"])}
		_emit_hub(st, surf, npos, arms, rib_r, sides, embed)
	# --- tubes: sweep each edge between its two mouth rings (or caps) ---
	for e_i in range(edges.size()):
		var e := edges[e_i] as Dictionary
		var pts := epts[e_i] as PackedVector2Array
		var ma: Variant = mouth.get("%d:0" % e_i, null)
		var mb: Variant = mouth.get("%d:1" % e_i, null)
		if ma == null or mb == null:
			continue
		_emit_tube(st, surf, pts, ma as Dictionary, mb as Dictionary, rib_r, sides, embed)
	# --- loops: closed ring sweeps (corner-rounded with wrap — a teardrop TIP pinches otherwise) ---
	for lp in loops:
		_emit_loop(st, surf, _resample(_round_corners(lp as PackedVector2Array, rib_r, true), max_step), rib_r, sides, embed)

# --- profile ring at 2D point p travelling along 2D dir d (unit) ---
# The lateral axis is the 2D LEFT vector mapped through the surface (NOT n cross t: on the drum that
# maps to 2D-RIGHT — the handedness flip made hub gores pair the wrong physical flanks and twist).
# Invariant: ring[0] = 2D-left of travel, ring[sides] = 2D-right, on EVERY surface.
static func _ring_at(surf: Dictionary, p: Vector2, d: Vector2, rib_r: float, sides: int, embed: float, lat_scale: float = 1.0) -> Array:
	var c := _surf_pos(surf, p)
	var n := _surf_normal(surf, p)
	var lat := _surf_dir(surf, p, Vector2(-d.y, d.x))   # 2D-left, mapped to 3D
	var lr := rib_r * lat_scale                          # lateral half-width (tapered through tight bends)
	var ring: Array = []
	for s in range(sides + 1):
		var phi := PI * float(s) / float(sides)
		ring.append(c + lat * (lr * cos(phi)) + n * (rib_r * sin(phi)))
	ring.append(c - lat * lr - n * embed)   # right skirt bottom
	ring.append(c + lat * lr - n * embed)   # left skirt bottom
	return ring

# Lateral taper through a tight bend: rings interpenetrate when the path's curvature radius drops
# below the rib radius (the inside of the bend folds) — the red-shell test shows it as speckle on
# every sharp apex. Shrink the ring's lateral half-width to fit the local circumradius.
static func _curv_scale(prev: Vector2, cur: Vector2, next: Vector2, rib_r: float) -> float:
	var a := prev.distance_to(cur)
	var b := cur.distance_to(next)
	var c := prev.distance_to(next)
	var area2 := absf((cur - prev).cross(next - prev))   # 2x triangle area
	if area2 < 1.0e-9:
		return 1.0
	var r_curv := (a * b * c) / (2.0 * area2)
	return clampf(r_curv / (rib_r * 1.25), 0.35, 1.0)

# The ring's 2D pre-image (same indexing) — hub faces wind from THIS (exact, never grazing).
static func _ring2_at(p: Vector2, d: Vector2, rib_r: float, sides: int) -> Array:
	var lat2 := Vector2(-d.y, d.x)
	var ring2: Array = []
	for s in range(sides + 1):
		ring2.append(p + lat2 * (rib_r * cos(PI * float(s) / float(sides))))
	ring2.append(p - lat2 * rib_r)
	ring2.append(p + lat2 * rib_r)
	return ring2

# A ring computed travelling the OPPOSITE way lists the same cross-section mirrored; this index map
# aligns ring B (built pointing away from its node) to a tube sweeping INTO that node.
static func _flip_ring(ring: Array, sides: int) -> Array:
	var out: Array = []
	for s in range(sides + 1):
		out.append(ring[sides - s])
	out.append(ring[sides + 2])
	out.append(ring[sides + 1])
	return out

# --- winding-safe emitters ---
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out_dir: Vector3) -> void:
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1.0e-14:
		return
	# Godot front faces are CLOCKWISE seen from outside: the visible face's cross points AWAY from out.
	if cr.dot(out_dir) > 0.0:
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	else:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

static func _face4(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out_dir: Vector3) -> void:
	_face(st, a, b, c, out_dir)
	_face(st, a, c, d, out_dir)

# --- tube between two mouth rings (mouths already trimmed off the ends) ---
static func _emit_tube(st: SurfaceTool, surf: Dictionary, pts: PackedVector2Array, ma: Dictionary, mb: Dictionary, rib_r: float, sides: int, embed: float) -> void:
	var total := _poly_len(pts)
	var cut_a := float(ma["cut"])
	var cut_b := float(mb["cut"])
	# reach clamps guarantee cut_a + cut_b <= 0.9 * total; a degenerate near-zero middle just yields a
	# two-ring tube (its zero-area quads are dropped by _face)
	var stations: Array = _stations_between(pts, cut_a, total - cut_b)
	var rings: Array = []
	rings.append(ma["ring"])              # exact hub-A ring vertices
	for k in range(1, stations.size() - 1):
		var stn := stations[k] as Dictionary
		var sc := _curv_scale((stations[k - 1] as Dictionary)["pos"] as Vector2, stn["pos"] as Vector2,
			(stations[k + 1] as Dictionary)["pos"] as Vector2, rib_r)
		rings.append(_ring_at(surf, stn["pos"] as Vector2, stn["dir"] as Vector2, rib_r, sides, embed, sc))
	rings.append(_flip_ring(mb["ring"] as Array, sides))   # exact hub-B ring, aligned to travel
	var rn := sides + 3
	for k in range(rings.size() - 1):
		var r0 := rings[k] as Array
		var r1 := rings[k + 1] as Array
		var axis0 := _ring_center(r0)
		var axis1 := _ring_center(r1)
		for s in range(rn):
			var s2 := (s + 1) % rn
			var mid := ((r0[s] as Vector3) + (r0[s2] as Vector3) + (r1[s2] as Vector3) + (r1[s] as Vector3)) * 0.25
			_face4(st, r0[s], r0[s2], r1[s2], r1[s], mid - (axis0 + axis1) * 0.5)

static func _emit_loop(st: SurfaceTool, surf: Dictionary, pts: PackedVector2Array, rib_r: float, sides: int, embed: float) -> void:
	var m := pts.size()
	if m < 3:
		return
	var closed := pts[0].distance_to(pts[m - 1]) < 1.0e-4
	var count := m - 1 if closed else m
	var rings: Array = []
	for i in range(count):
		var prev := pts[(i - 1 + count) % count] if closed else pts[maxi(i - 1, 0)]
		var next := pts[(i + 1) % count] if closed else pts[mini(i + 1, m - 1)]
		var d := (next - prev)
		if d.length() < 1.0e-9:
			d = Vector2(1, 0)
		rings.append(_ring_at(surf, pts[i], d.normalized(), rib_r, sides, embed, _curv_scale(prev, pts[i], next, rib_r)))
	var rn := sides + 3
	var last := count if closed else count - 1
	for k in range(last):
		var r0 := rings[k] as Array
		var r1 := rings[(k + 1) % count] as Array
		var axis := (_ring_center(r0) + _ring_center(r1)) * 0.5
		for s in range(rn):
			var s2 := (s + 1) % rn
			var mid := ((r0[s] as Vector3) + (r0[s2] as Vector3) + (r1[s2] as Vector3) + (r1[s] as Vector3)) * 0.25
			_face4(st, r0[s], r0[s2], r1[s2], r1[s], mid - axis)
	if not closed:
		_cap_ring_dir(st, rings[0] as Array, (_ring_center(rings[0] as Array) - _ring_center(rings[1] as Array)))
		_cap_ring_dir(st, rings[count - 1] as Array, (_ring_center(rings[count - 1] as Array) - _ring_center(rings[count - 2] as Array)))

# --- hub: dome apex + mitre corners + gore walls + skirt bottom, all on the arms' mouth rings ---
static func _emit_hub(st: SurfaceTool, surf: Dictionary, npos: Vector2, arms: Array, rib_r: float, sides: int, embed: float) -> void:
	var P := _surf_pos(surf, npos)
	var n := _surf_normal(surf, npos)
	var apex := P + n * rib_r
	var bot := P - n * embed
	var m := arms.size()
	var hand := _surf_handedness(surf)
	# WINDING IS EXACT, NEVER A 3D DOT-TEST: the hub's top and bottom are height fields over the 2D
	# footprint, so a face's correct 3D winding equals its 2D pre-image's winding (times the mapping
	# handedness). 3D heuristics flipped arbitrarily on the near-vertical slivers at the mouths — the
	# red-shell test lit up on every straight-through junction until this.
	for a_i in range(m):
		var arm := arms[a_i] as Dictionary
		var nxt := arms[(a_i + 1) % m] as Dictionary
		var ring := arm["ring"] as Array
		var ring2 := _ring2_at(arm["m2"] as Vector2, arm["md"] as Vector2, rib_r, sides)
		# dome fan over this arm's arc (upper height field)
		for s in range(sides):
			_face_hf(st, apex, ring[s], ring[s + 1], npos, ring2[s], ring2[s + 1], hand, true)
		# bottom fan under this arm's skirt edge (lower height field)
		_face_hf(st, bot, ring[sides + 1], ring[sides + 2], npos, ring2[sides + 1], ring2[sides + 2], hand, false)
		# gore to the CCW-next arm: corner between arm i's 2D-LEFT flank (ring[0] / ring[sides+2]) and
		# arm j's 2D-RIGHT flank (ring[sides] / ring[sides+1]) — ring indexing is 2D-true on any surface
		var d_i := arm["dir"] as Vector2
		var d_j := nxt["dir"] as Vector2
		# the corner may never outrun the mouths (a longer tongue webs across concave openings —
		# visible on every honeyframe S_A vertex, where adjacent arm gaps are narrow)
		var c_cap := minf(float(arm.get("reach", rib_r * 1.4)), float(nxt.get("reach", rib_r * 1.4)))
		var c2 := _mitre_corner(npos, d_i, d_j, rib_r, c_cap)
		var c_top := _surf_pos(surf, c2)
		var c_bot := c_top - n * embed
		var nring := nxt["ring"] as Array
		var nring2 := _ring2_at(nxt["m2"] as Vector2, nxt["md"] as Vector2, rib_r, sides)
		_face_hf(st, apex, ring[0], c_top, npos, ring2[0], c2, hand, true)
		_face_hf(st, apex, c_top, nring[sides], npos, c2, nring2[sides], hand, true)
		_face_hf(st, bot, ring[sides + 2], c_bot, npos, ring2[sides + 2], c2, hand, false)
		_face_hf(st, bot, c_bot, nring[sides + 1], npos, c2, nring2[sides + 1], hand, false)
		# gore SIDE WALLS: vertical panels — outward = the 2D outward normal of their boundary edge
		# (perpendicular, oriented away from the node; decisively non-degenerate)
		var f2_i := ring2[0] as Vector2
		var w_i := _wall_out2(f2_i, c2, npos)
		_face4(st, ring[0], ring[sides + 2], c_bot, c_top, _surf_dir(surf, npos, w_i))
		var f2_j := nring2[sides] as Vector2
		var w_j := _wall_out2(f2_j, c2, npos)
		_face4(st, c_top, c_bot, nring[sides + 1], nring[sides], _surf_dir(surf, npos, w_j))

# Emit a HEIGHT-FIELD face wound from its 2D pre-image: sign(cross3.n) == sign(area2 * handedness),
# and a visible (Godot CW-front) outer face needs cross3.n < 0. `upper=false` = a bottom face
# (outward -n), which inverts the requirement.
static func _face_hf(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, a2: Vector2, b2: Vector2, c2: Vector2, hand: float, upper: bool) -> void:
	var area2 := (b2 - a2).cross(c2 - a2)
	if absf(area2) < 1.0e-12:
		return
	var neg := (area2 * hand) < 0.0
	if neg == upper:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	else:
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)

# 2D outward normal of a gore wall's boundary edge (flank point -> corner), oriented away from the node.
static func _wall_out2(f2: Vector2, c2: Vector2, npos: Vector2) -> Vector2:
	var e := c2 - f2
	var w := Vector2(-e.y, e.x)
	if w.length_squared() < 1.0e-14:
		w = f2 - npos
	if w.dot(f2 - npos) < 0.0:
		w = -w
	return w.normalized()

# 2D mitre corner between CCW-adjacent arms: the corner sits at half the CCW angular gap from arm i
# (NOT the vector bisector — for opposite arms that is degenerate and a perpendicular fallback picks
# an arbitrary side, twisting the gore across the hub; the red-shell test caught it on every
# straight-through junction). Distance rib_r / sin(gap/2), clamped so near-parallel arms can't throw
# the corner to infinity.
static func _mitre_corner(npos: Vector2, d_i: Vector2, d_j: Vector2, rib_r: float, max_dist: float = 0.0) -> Vector2:
	var a_i := atan2(d_i.y, d_i.x)
	var a_j := atan2(d_j.y, d_j.x)
	var gap := a_j - a_i
	while gap <= 1.0e-6:
		gap += TAU
	var mid := a_i + gap * 0.5
	var dist := rib_r / maxf(sin(gap * 0.5), 0.29)   # clamp ~= 3.5 * rib_r
	if max_dist > 0.0:
		dist = minf(dist, max_dist)
	return npos + Vector2(cos(mid), sin(mid)) * dist

# cap a terminal ring (fan across the closed profile), facing away from the tube
static func _cap_ring(st: SurfaceTool, ring: Array, surf: Dictionary, p: Vector2, d_away_from_tube: Vector2) -> void:
	_cap_ring_dir(st, ring, -_surf_dir(surf, p, d_away_from_tube))

static func _cap_ring_dir(st: SurfaceTool, ring: Array, out_dir: Vector3) -> void:
	var c := _ring_center(ring)
	var rn := ring.size()
	for s in range(rn):
		_face(st, c, ring[s], ring[(s + 1) % rn], out_dir)

# --- polyline utilities ---
static func _ring_center(ring: Array) -> Vector3:
	var s := Vector3.ZERO
	for v in ring:
		s += v as Vector3
	return s / float(maxi(1, ring.size()))

static func _poly_len(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(pts.size() - 1):
		l += pts[i].distance_to(pts[i + 1])
	return l

# walk `dist` along the polyline from one end; returns {"pos": Vector2, "dir": Vector2 (away from end)}
static func _walk(pts: PackedVector2Array, end: int, dist: float) -> Dictionary:
	var order := pts if end == 0 else _reversed(pts)
	var left := dist
	for i in range(order.size() - 1):
		var seg := order[i + 1] - order[i]
		var sl := seg.length()
		if sl >= left and sl > 1.0e-9:
			return {"pos": order[i] + seg * (left / sl), "dir": seg / sl}
		left -= sl
	var d := (order[order.size() - 1] - order[order.size() - 2])
	return {"pos": order[order.size() - 1], "dir": d.normalized() if d.length() > 1.0e-9 else Vector2(1, 0)}

static func _reversed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	out.reverse()
	return out

# stations (pos+dir) along the polyline between arc-lengths s0..s1 (interior points = original verts)
static func _stations_between(pts: PackedVector2Array, s0: float, s1: float) -> Array:
	var out: Array = []
	var w0 := _walk(pts, 0, s0)
	out.append(w0)
	var acc := 0.0
	for i in range(1, pts.size() - 1):
		acc += pts[i - 1].distance_to(pts[i])
		if acc > s0 + 1.0e-4 and acc < s1 - 1.0e-4:
			var d := (pts[i + 1] - pts[i - 1])
			out.append({"pos": pts[i], "dir": d.normalized() if d.length() > 1.0e-9 else Vector2(1, 0)})
	var w1 := _walk(pts, 0, s1)
	out.append(w1)
	return out

# Round interior corners sharper than ~52 degrees with a rib-scale fillet (quad bezier through the
# corner). A sharp mitre ring otherwise crosses its neighbours -> locally inside-out quads (the
# red-shell test lights up at teardrop tips / arch apexes). Endpoints are preserved on open paths;
# closed loops round with wrap (the seam vertex is a corner too).
static func _round_corners(pts: PackedVector2Array, rib_r: float, closed: bool) -> PackedVector2Array:
	var m := pts.size()
	if m < 3:
		return pts
	var core := pts
	if closed and pts[0].distance_to(pts[m - 1]) < 1.0e-4:
		core = pts.slice(0, m - 1)
	var n := core.size()
	if n < 3:
		return pts
	var out := PackedVector2Array()
	if not closed:
		out.append(core[0])
	var i0 := 0 if closed else 1
	var i1 := n if closed else n - 1
	for i in range(i0, i1):
		var prev := core[(i - 1 + n) % n]
		var cur := core[i]
		var next := core[(i + 1) % n]
		var din := cur - prev
		var dout := next - cur
		var lin := din.length()
		var lout := dout.length()
		if lin < 1.0e-9 or lout < 1.0e-9:
			out.append(cur)
			continue
		var turn := absf(din.normalized().angle_to(dout.normalized()))
		if turn < 0.9:
			out.append(cur)
			continue
		var t := minf(rib_r * 1.4, 0.4 * minf(lin, lout))
		var pa := cur - din.normalized() * t
		var pb := cur + dout.normalized() * t
		for s in range(5):
			var tt := float(s) / 4.0
			out.append(pa.lerp(cur, tt).lerp(cur.lerp(pb, tt), tt))
	if closed:
		out.append(out[0])
	else:
		out.append(core[n - 1])
	return out

static func _resample(pts: PackedVector2Array, max_step: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var d := a.distance_to(b)
		if d < 1.0e-6:
			continue
		var n := maxi(1, int(ceil(d / max_step)))
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / float(n)))
	return out

# ============================================================================================
# TEST SUPPORT — the watertightness invariant.
# ============================================================================================

## Directed-edge ORIENTATION check: on a consistently-wound closed 2-manifold every undirected edge
## is traversed once in EACH direction, so a directed edge appearing twice = an inconsistently-wound
## face (visible from its hidden side — exactly what the red-shell render test shows as red).
## Returns [{pos: Vector3}] — one entry per conflicting directed edge (midpoint), for localizing.
static func orientation_conflicts(mesh: ArrayMesh) -> Array:
	if mesh == null or mesh.get_surface_count() == 0:
		return []
	var arrays := mesh.surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var ids: Dictionary = {}
	var vid := PackedInt32Array()
	vid.resize(verts.size())
	var rep: Array = []
	for i in range(verts.size()):
		var v := verts[i]
		var key := "%d,%d,%d" % [int(round(v.x * 5000.0)), int(round(v.y * 5000.0)), int(round(v.z * 5000.0))]
		if not ids.has(key):
			ids[key] = ids.size()
			rep.append(v)
		vid[i] = int(ids[key])
	var seen: Dictionary = {}
	var out: Array = []
	var tri_count := int(verts.size() / 3.0)
	for t in range(tri_count):
		var a := vid[t * 3]
		var b := vid[t * 3 + 1]
		var c := vid[t * 3 + 2]
		if a == b or b == c or c == a:
			continue
		for pair in [[a, b], [b, c], [c, a]]:
			var p0 := int((pair as Array)[0])
			var p1 := int((pair as Array)[1])
			var ek := "%d>%d" % [p0, p1]
			if seen.has(ek):
				out.append({"pos": ((rep[p0] as Vector3) + (rep[p1] as Vector3)) * 0.5})
			seen[ek] = true
	return out

## Count boundary edges (used by exactly ONE triangle) in the mesh, welding vertices by position.
## A watertight closed rib network returns 0 — any hole, crack, or unmated ring shows up here.
static func boundary_edge_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return -1
	var arrays := mesh.surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var idx := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		idx = arrays[Mesh.ARRAY_INDEX]
	var ids: Dictionary = {}
	var vid := PackedInt32Array()
	vid.resize(verts.size())
	for i in range(verts.size()):
		var v := verts[i]
		var key := "%d,%d,%d" % [int(round(v.x * 5000.0)), int(round(v.y * 5000.0)), int(round(v.z * 5000.0))]
		if not ids.has(key):
			ids[key] = ids.size()
		vid[i] = int(ids[key])
	var edge_count: Dictionary = {}
	var tri_count := (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)
	for t in range(tri_count):
		var a := vid[idx[t * 3]] if idx.size() > 0 else vid[t * 3]
		var b := vid[idx[t * 3 + 1]] if idx.size() > 0 else vid[t * 3 + 1]
		var c := vid[idx[t * 3 + 2]] if idx.size() > 0 else vid[t * 3 + 2]
		for pair in [[a, b], [b, c], [c, a]]:
			var lo := mini(int((pair as Array)[0]), int((pair as Array)[1]))
			var hi := maxi(int((pair as Array)[0]), int((pair as Array)[1]))
			if lo == hi:
				continue
			var ek := "%d:%d" % [lo, hi]
			edge_count[ek] = int(edge_count.get(ek, 0)) + 1
	var boundary := 0
	for k in edge_count.keys():
		if int(edge_count[k]) == 1:
			boundary += 1
	return boundary
