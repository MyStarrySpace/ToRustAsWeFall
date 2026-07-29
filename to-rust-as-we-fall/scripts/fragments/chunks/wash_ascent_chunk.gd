extends "res://scripts/scene_chunks/scene_chunk.gd"
## WASH ASCENT — the from-scratch rebuild (director's restart contract, 2026-07-28).
##
## THE LAWS THIS SCRIPT LIVES UNDER:
## - ZERO PRIMITIVES. Every visible mesh comes from the archetype piece library or a
##   modeled GLB. This script draws nothing itself — no boxes, no cylinders, no quads.
##   (`--test-wash-ascent` lints the built scene for PrimitiveMesh and goes red.)
## - ONE SOURCE OF TRUTH. Placements live as nodes in wash_ascent_props.tscn — a
##   Marker3D wearing `metadata/piece` per prop, real OmniLight3D nodes for lights,
##   and RUN markers (deck_run/wall_run/channel_run/rail_run/pipe_chain) for tiled
##   fills. This script only instantiates, measures, warps, and validates.
## - MEASURE, THEN PLACE. Run pitches come from the pieces' REAL combined AABBs at
##   load (`_piece_aabb`), so channel segments, rails, wall panels, and pipe chains
##   meet mouth-to-mouth by construction — never an eyeballed spacing constant.
## - THE GRUNGE LAW. Structure is never tinted; color is spent only on the named
##   accents (water/work/ember/organic), applied as a dim hue cue over shaded albedo.
## - STORYTELLING PLACEMENT. The props scene's tree IS the story: a decaying
##   approach span, a kept maintenance bay, a measured manifold run, and the portal
##   ledge the overgrowth is taking back. Walkability derives from the placed props
##   (blockers become wall cells), so the grid can never disagree with the scene.
##
## THE SPIRAL (restored): the props scene is authored FLAT — x = s (progress), z is
## the authoring lane axis — and that flat frame IS the data layer (grid, clicks,
## sweeps, spawns all run in it). Presentation warps every realized piece onto the
## canonical channels helix (ChannelsArc) at build: helix lane = LANE_CENTER - z,
## so the back wall (z 8.2) becomes the DRUM-side face and the channel (z < 0)
## rides the OUTER rim — the falls pour outward, the coil climbs ~3.5 m over the
## slice. The warp is a pure function; the scene nodes stay the one source of truth.
##
## THE WASH (the gate): three channel sections surge on their own data-driven
## cadences and flood the WHOLE walkway width across their span — the dry gaps
## between sections are the safe ground, and crossing a section means running
## its dry beat. Everything rides the scheduler analytically (onset = t0 +
## grace + phase + period*k), so 1x and 10x are identical: telegraph pulse,
## flood, sweep rechecks, valve hold, re-arm. The flood is HELICAL WATER BANDS
## (modeled arcs, one per unit of s, one shared appearance), never tiled sheets.

const PROPS_SCENE := preload("res://scenes/fragments/chunks/wash_ascent_props.tscn")

const DECK_W := 52.0
const DECK_D := 8.0
const DECK_TOP := 0.1
const LANE_CENTER := 4.0    # authoring z that sits on the helix centreline (lane 0)

const ACCENTS := {
	"water": Color(0.30, 0.62, 0.72),
	"work": Color(0.85, 0.58, 0.22),
	"ember": Color(0.72, 0.28, 0.14),
	"organic": Color(0.48, 0.32, 0.62),
}

## Pieces whose footprint blocks the walk grid. Flora and thin wall-hangers don't.
const BLOCKING_PIECES := ["shelter", "workbench", "forage_cache", "terminal",
	"junction", "portal_console", "portal_ring_ornate", "vein_trunk",
	"water_control", "pipe_rack", "barrier"]

## The wash cadence — pure data, one section per stretch of the channel. Onsets are
## computed analytically from these numbers; nothing samples per-frame.
## Section spans are INTEGER s so the 1-s helical water bands cover each span
## EXACTLY — the visible flood edge IS the kill-predicate edge, never a lie.
## PHASE LADDER LAW: the first onsets (grace + phase = 1.5 / 4.5 / 2.5) sit ON
## the naive routes' arrival windows — section 0's catches a WALKING bolter
## (in the span 0.3..2.8s at walk speeds), section 2's catches a RUN-rusher
## (in its span ~2.8..3.6s at run speed) — so the gate cannot be outrun at any
## speed; the beat must be read. Spawn ground (s < 2) is safe: standing and
## reading is never punished, and section 2's early far surge doubles as the
## first-sight DEMONSTRATION (the sapscraps roam inside that band). Dry
## windows (period - dur >= 6.6s) stay generous enough to cross every span
## walking. `--test-wash-ascent-playthrough` asserts all of it (walk-sprint
## fails, run-rush fails, timed crossing completes) — retune only with it green.
## Spans sit ON the 2.0 m deck-tile grid so the FLOOR is an exact binary read:
## every tile inside a span is an iron SLUICE BED (the wash's own ground —
## "pipe bottom", the director's ask), every tile outside is wood plank. Wood
## NEVER floods; metal always can. The gaps (8-12, 16-20) are two full plank
## columns wide.
const WASH_SECTIONS := [
	{"s0": 2.0, "s1": 8.0, "period": 9.0, "dur": 2.4, "phase": 0.5},
	{"s0": 12.0, "s1": 16.0, "period": 11.0, "dur": 2.6, "phase": 3.5},
	{"s0": 20.0, "s1": 24.0, "period": 13.0, "dur": 2.8, "phase": 1.5},
	# Act two, past the pump landing. Section 3 is KEYED: its dry beat (1.0s)
	# fits NO gait — not even a runner waiting at the mouth (8u at 6.4 needs
	# 1.25s) — so the landing valve's hold is the only crossing. The verb was
	# taught at section 0; here the level asks for it back under pressure.
	{"s0": 28.0, "s1": 36.0, "period": 10.0, "dur": 9.0, "phase": 2.0, "keyed": true},
	# Section 4 is generous water but WATCHED ground — the patroller in the
	# 36-40 gap prices the mid lane, and the wash prices anything lured across.
	{"s0": 40.0, "s1": 44.0, "period": 12.0, "dur": 2.6, "phase": 5.0},
]
const WASH_GRACE := 1.0            # quiet second after reset before the ladder starts
const TELEGRAPH_LEAD := 1.2        # channel brightens this long before the water arrives
const WASH_Z_CENTER := 3.6         # THE GATE: the surge floods the FULL walkway width
const WASH_Z_HALF := 4.4           # (z -0.8 .. 8.0) — sections cross only on the dry beat;
const DANGER_Z := 2.0              # legacy band const kept for anchors/notes
const VALVE_HOLD_WINDOW := 14.0    # how long the bay valve quiets section 0
const SWEEP_HP_BITE := 6.0         # the kit-owned fail-forward price per sweep
const PARTY_IDS := ["aster", "peris", "endo"]

var _props_root: Node3D
var _realized_root: Node3D
var _piece_aabbs: Dictionary = {}
var _placed_count := 0
var _unresolved: Array = []
var _wall_cells: Array = []
var _channel_segments: Array = []   # [{node, s, mats: [StandardMaterial3D]}]
var _section_water: Array = []      # [{node, s0, kind}] — helical water bands
var _channel_span := Vector2.ZERO   # flat s range the trough actually covers
var _channel_base_energy: Dictionary = {}
var _flures: Array = []
var _hide_spots_cache: Array = []

var _channels: Array = []           # the composed Channel kit objects, one per section
var _fauna: Dictionary = {}         # char_id -> Enemy (canonical Sapscraps; placeholder bodies)
var _ring_exit: ExitShelter = null
var _swept_count := 0
var _phase := "ready"

func _build_chunk() -> void:
	_props_root = PROPS_SCENE.instantiate()
	_props_root.visible = false          # markers are data; the realized root is the scene
	add_child(_props_root)
	_realized_root = Node3D.new()
	_realized_root.name = "Realized"
	add_child(_realized_root)
	_realize_markers(_props_root)
	_warp_lights(_props_root)
	_derive_wall_cells()
	_build_wash_channels()
	_build_interactables()
	if not _unresolved.is_empty():
		push_error("wash_ascent: unresolved placements: %s" % [_unresolved])

# --- The warp: authoring flat frame -> the canonical channels helix ---

## helix s = flat x; helix lane = LANE_CENTER - flat z (flipping the lane keeps the
## composition right-handed, so no piece is mirrored); height above the deck rides
## along. Yaw composes INSIDE the helix frame (the proven _warp_piece pattern), with
## a -PI/2 trim converting "authored facing along +x" into "facing along +s".
## `stretch` scales the piece along the helix TANGENT: a rigid 2 m module subtends
## less arc at the outer radii (gaps) and more at the inner (overlap), so RUN pieces
## fan into wedges by (R0 + lane)/R0 — the same trick the old GLB baked into its
## arc bands. Story props stay rigid (stretch 1): their footprints don't gap.
func _warp_transform(flat: Transform3D, stretch := 1.0, tilt := false) -> Transform3D:
	var s := flat.origin.x
	var lane := LANE_CENTER - flat.origin.z
	# The change of frame flat->helix is RotY(-PI/2); composing the piece's FULL
	# flat basis (not just an extracted yaw) also carries vertical rotations —
	# the pipe router's elbows and risers warp correctly through the same path.
	# `tilt` pitches the piece about the helix RIGHT axis so its forward (+s)
	# direction rides the CLIMB SLOPE at its radius — run pieces (deck tiles,
	# rails, walls, channel) meet edge-to-edge as a continuous ramp instead of
	# terraced steps (the "disconnected tiles" bug: every piece was horizontal
	# at its center height while the helix climbed KCLIMB per s under it).
	# Story props stay untilted: they STAND on the ramp.
	var tilt_basis := Basis.IDENTITY
	if tilt:
		var slope := ChannelsArc.KCLIMB / ((ChannelsArc.R0 + lane) * ChannelsArc.KTHETA)
		tilt_basis = Basis(Vector3(1.0, 0.0, 0.0), -atan(slope))
	return Transform3D(
		ChannelsArc.basis_at(s) * tilt_basis
			* Basis.from_scale(Vector3(1.0, 1.0, stretch))
			* Basis(Vector3.UP, -PI * 0.5) * flat.basis.orthonormalized(),
		ChannelsArc.arc_pos(s, lane) + Vector3(0.0, flat.origin.y - DECK_TOP, 0.0))

func _run_stretch(flat_z: float) -> float:
	return (ChannelsArc.R0 + (LANE_CENTER - flat_z)) / ChannelsArc.R0

func get_coord_map():
	return AscentCoordMap.new()

## The same projection the pieces use, exposed to GameState: data positions are the
## props scene's authoring frame, so grid, spawns, sweeps, and clicks share ONE frame.
class AscentCoordMap:
	extends RefCounted
	func to_world(p: Vector3) -> Vector3:
		return ChannelsArc.arc_pos(p.x, 4.0 - p.z)
	func to_data(w: Vector3) -> Vector3:
		var r := ChannelsArc.world_to_arc(w)
		return Vector3(r["s"], 0.0, 4.0 - float(r["lane"]))
	func to_basis(p: Vector3) -> Basis:
		return ChannelsArc.basis_at(p.x)

## Adjacent helix turns sit ~9.24 world units apart vertically — keep the follow
## camera below that pitch so the view never looks through the turn above.
func get_preview_camera_profile() -> Dictionary:
	return {
		"follow_offset": Vector3(0.0, 6.0, 7.0),
		"min_zoom": 0.8,
		"max_zoom": 1.25,
		"initial_zoom": 1.0,
		"reset_yaw": true,
	}

# --- Realizing the props scene ---

func _realize_markers(node: Node) -> void:
	for child in node.get_children():
		_realize_markers(child)
	if not (node is Node3D):
		return
	var n3 := node as Node3D
	if n3.has_meta("piece"):
		_realize_piece(n3)
	elif n3.has_meta("deck_run"):
		_realize_deck_run(n3)
	elif n3.has_meta("wall_run"):
		_realize_row(n3, _wall_variant_ids(), int(n3.get_meta("wall_run")),
			_skip_spans(n3), "wall", "structure_wall", true)
	elif n3.has_meta("channel_run"):
		_realize_channel_run(n3, int(n3.get_meta("channel_run")))
	elif n3.has_meta("drum_shell") or n3.has_meta("world_piece"):
		_realize_world_arc(n3)
	elif n3.has_meta("rail_run"):
		_realize_row(n3, ["railing_run"], int(n3.get_meta("rail_run")),
			_skip_spans(n3), "floor", "structure_rail", true)
	elif n3.has_meta("pipe_route"):
		_realize_pipe_route(n3)
	elif n3.has_meta("enemy"):
		_spawn_fauna(n3)

func _realize_piece(marker: Node3D) -> void:
	var pid := str(marker.get_meta("piece"))
	var piece := _spawn_piece(pid, marker.global_transform)
	if piece == null:
		return
	_stamp(piece, str(marker.get_meta("mount", "floor")),
		str(marker.get_meta("cluster", pid)), bool(marker.get_meta("embed_ok", false)))
	var accent := str(marker.get_meta("accent", ""))
	if ACCENTS.has(accent):
		_tint_accent(piece, ACCENTS[accent], float(marker.get_meta("energy", 0.5)))
	var emission_scale := float(marker.get_meta("emission_scale", 1.0))
	if emission_scale < 1.0:
		_scale_emission(piece, emission_scale)

## A measured row: pieces laid along the marker's local +X, pitch = the piece's
## real AABB x-length, each piece offset so its AABB START sits at k*pitch.
## `rigid_arc` places pieces UNSTRETCHED at their true ARC pitch instead of
## tangentially squashing them (director: "fix the tiling on the center walls"):
## the flat advance per piece becomes pitch/stretch, the count recomputes to fill
## the authored span, and every panel keeps its authored proportions. Skips are
## FLAT SPANS (metadata/skip_spans "a-b c-d"), immune to pitch changes.
func _realize_row(marker: Node3D, variant_ids: Array, count: int, skip_spans: Array,
		mount: String, cluster: String, rigid_arc := false) -> void:
	if variant_ids.is_empty() or count <= 0:
		return
	var pitch := _piece_aabb(str(variant_ids[0])).size.x
	if pitch <= 0.0:
		_unresolved.append(str(variant_ids[0]))
		return
	# a RADIAL run (crossing lanes, e.g. the end-cap rail) never stretches: the
	# warp preserves lane distances, so its pitch is the piece pitch unmodified
	var radial := bool(marker.get_meta("radial", false))
	var stretch := 1.0 if radial else _run_stretch(marker.global_transform.origin.z)
	var flat_pitch := pitch / stretch if rigid_arc else pitch
	var span := float(count) * pitch
	var n := int(floor(span / flat_pitch + 0.001)) if rigid_arc else count
	for k in range(n):
		var start := float(k) * flat_pitch
		if _flat_in_spans(start + flat_pitch * 0.5, skip_spans):
			continue
		var pid := str(variant_ids[_row_hash(marker, k) % variant_ids.size()])
		var aabb := _piece_aabb(pid)
		var align := aabb.position.x * (flat_pitch / pitch) if rigid_arc else aabb.position.x
		var flat := marker.global_transform \
			* Transform3D(Basis.IDENTITY, Vector3(start - align, 0.0, 0.0))
		# tangential runs ride the climb slope (the ramp); radial runs are level
		var piece := _spawn_piece(pid, flat, 1.0 if rigid_arc else stretch,
			not radial)
		if piece == null:
			continue
		_stamp(piece, mount, cluster, true)

func _skip_spans(marker: Node3D) -> Array:
	var out: Array = []
	for part in str(marker.get_meta("skip_spans", "")).split(" ", false):
		var ab := part.split("-", false)
		if ab.size() == 2:
			out.append(Vector2(float(ab[0]), float(ab[1])))
	return out

func _flat_in_spans(x: float, spans: Array) -> bool:
	for span_v in spans:
		if x >= (span_v as Vector2).x and x <= (span_v as Vector2).y:
			return true
	return false

## The channel run is the trough segments meeting mouth-to-mouth plus a bolted
## JOINT COLLAR clamped over every interior seam (real pipe-run infrastructure —
## the seam notch was a flagged artifact). The trough's live water is NOT tiled
## per segment anymore: helical WATER BANDS (one modeled piece per unit of s,
## curved along the arc with the climb baked in) cover the whole channel span —
## see _build_section_water.
func _realize_channel_run(marker: Node3D, count: int) -> void:
	var pitch := _piece_aabb("water_channel").size.x
	var stretch := _run_stretch(marker.global_transform.origin.z)
	var flat_pitch := pitch / stretch
	var n := int(floor(float(count) * pitch / flat_pitch + 0.001))
	_channel_span = Vector2(marker.global_transform.origin.x,
		marker.global_transform.origin.x + float(n) * flat_pitch)
	# variation cycle (director: "more variations of the side channel part") —
	# a fixed rhythm through the three trough silhouettes, never per-tile noise
	var variants := ["water_channel", "water_channel_b", "water_channel_c",
		"water_channel", "water_channel_c", "water_channel_b"]
	for k in range(n):
		var start := float(k) * flat_pitch
		var flat := marker.global_transform \
			* Transform3D(Basis.IDENTITY, Vector3(start + flat_pitch * 0.5, 0.0, 0.0))
		var seg := _spawn_piece(str(variants[k % variants.size()]), flat, 1.0, true)
		if seg == null:
			continue
		_stamp(seg, "floor", "structure_channel", true)
		_register_channel_segment(seg, flat.origin.x - flat_pitch * 0.5)
		if k > 0:
			var seam := marker.global_transform \
				* Transform3D(Basis.IDENTITY, Vector3(start, 0.0, 0.0))
			var collar := _spawn_piece("channel_collar", seam, 1.0, true)
			if collar != null:
				_stamp(collar, "floor", "structure_channel", true)

## The pipe ROUTE: the marker declares axis-aligned waypoints in one-metre cells
## of its local frame ("x,y,z x,y,z ..."), plus virtual ports where terminal
## cells feed off-network hardware ("x,y,z:dx,dy,dz ..."). PipeGrid rasterizes
## and auto-tiles — straight/elbow/tee/cross/end with orientation — and each
## pick warps onto the helix through the same _warp_transform as everything.
func _realize_pipe_route(marker: Node3D) -> void:
	var waypoints: Array = []
	for part in str(marker.get_meta("pipe_route", "")).split(" ", false):
		var n := part.split(",", false)
		if n.size() == 3:
			waypoints.append(Vector3i(int(n[0]), int(n[1]), int(n[2])))
	var extra: Dictionary = {}
	for part in str(marker.get_meta("pipe_ports", "")).split(" ", false):
		var half := part.split(":", false)
		if half.size() != 2:
			continue
		var c := half[0].split(",", false)
		var d := half[1].split(",", false)
		if c.size() == 3 and d.size() == 3:
			var cell := Vector3i(int(c[0]), int(c[1]), int(c[2]))
			if not extra.has(cell):
				extra[cell] = []
			(extra[cell] as Array).append(Vector3i(int(d[0]), int(d[1]), int(d[2])))
	var cells := PipeGrid.rasterize(waypoints)
	var cluster := str(marker.get_meta("cluster", "pipes"))
	# The pipe lattice rides the same tiling laws as every other tangential run:
	# x-cells advance at 1/stretch in flat s so rigid 1 m pieces meet mouth-to-
	# mouth on the arc (no 32% overlap at the inner radius), and tangential
	# straights tilt onto the climb ramp so joints never terrace. Elbows and
	# risers stay upright — their flanges absorb the rake at the corners.
	var pipe_stretch := _run_stretch(marker.global_transform.origin.z)
	for pick in PipeGrid.resolve(cells, extra):
		var cell: Vector3i = pick["cell"]
		var flat := marker.global_transform * Transform3D(pick["basis"] as Basis,
			Vector3((float(cell.x) + 0.5) / pipe_stretch,
				float(cell.y) + 0.5, float(cell.z)))
		var axis: Vector3 = (pick["basis"] as Basis) * Vector3(1, 0, 0)
		var tangential := str(pick["piece"]).begins_with("pipe_straight") \
			and absf(axis.x) > 0.9
		var piece := _spawn_piece(str(pick["piece"]), flat, 1.0, tangential)
		if piece != null:
			_stamp(piece, "attached", cluster, true)

## Drum architecture is WORLD-anchored — on the coil's axis, not the flat frame.
## The marker contributes the piece id (world_piece, default drum_shell), its yaw
## angle in degrees, and its height.
func _realize_world_arc(marker: Node3D) -> void:
	var pid := str(marker.get_meta("world_piece", "drum_shell"))
	var angle := float(marker.get_meta("angle", marker.get_meta("drum_shell", 0.0)))
	var piece := ArchetypePieceLibrary.instantiate(pid)
	if piece == null:
		_unresolved.append(pid)
		return
	var rad := float(marker.get_meta("radius", 0.0))
	var ang := deg_to_rad(angle)
	# radius-bearing markers (portholes, fittings) mount ON the drum face at that
	# angle, facing outward; arc pieces (shell/crown) anchor on the axis itself
	var origin := Vector3(rad * cos(ang), marker.position.y, rad * sin(ang)) 		if rad > 0.0 else Vector3(0.0, marker.position.y, 0.0)
	var basis := Basis(Vector3.UP, -ang + PI * 0.5) if rad > 0.0 		else Basis(Vector3.UP, ang)
	piece.transform = Transform3D(basis, origin)
	_stamp(piece, "floor" if rad <= 0.0 else "attached", "structure_drum", true)
	if pid == "drum_shell":
		_apply_vasculature_overlay(piece)
	_realized_root.add_child(piece)
	_placed_count += 1

## The director-approved Voronoi-BRANCH vasculature (grown veins, not the retired
## uniform web) rides the drum shells as a world-triplanar overlay — the organic
## register reclaiming the iron, dense nowhere, budding into biolume tips.
func _apply_vasculature_overlay(piece: Node3D) -> void:
	var shader := load("res://resources/vasculature_overlay.gdshader")
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for tex_name in ["vein_albedo", "vein_emissive", "vein_normal"]:
		var file: String = {"vein_albedo": "vasculature_albedo",
			"vein_emissive": "vasculature_emissive",
			"vein_normal": "vasculature_normal"}[tex_name]
		var tex = load("res://resources/textures/vasculature/%s.png" % file)
		if tex != null:
			mat.set_shader_parameter(tex_name, tex)
	var stack: Array = [piece]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for si in range(mi.mesh.get_surface_count()):
				var base := mi.get_active_material(si)
				if base is BaseMaterial3D:
					var dup := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
					dup.next_pass = mat
					mi.set_surface_override_material(si, dup)
		for c in n.get_children():
			stack.append(c)

## Deck runs lay nx × nz two-metre tiles in the marker's local frame, each tile
## individually warped (the strip polygonalizes in flat space, curves per-tile).
## Every tile carries its own invisible collision box so the ground ray lands on
## the curved deck. Surface meta is the decay story; variation is a pure hash.
func _realize_deck_run(marker: Node3D) -> void:
	var dims: Vector2i = marker.get_meta("deck_run")
	var surface := str(marker.get_meta("surface", "mixed"))
	var pitch := _piece_aabb("deck_planks").size.x
	# ONE GLOBAL LATTICE (director: "use more of a grid"): every deck run snaps
	# its cells to the SAME flat-frame grid (multiples of the tile pitch from
	# s=0 / z=0), so seam angles are shared across all rows AND all deck runs —
	# adjacent decks merge into one polar grid instead of each marker starting
	# its own offset lattice. Cell indices are global; the marker only says
	# which rectangle of the shared lattice it fills.
	var i0 := roundi(marker.global_transform.origin.x / pitch)
	var j0 := roundi(marker.global_transform.origin.z / pitch)
	for i in range(dims.x):
		for j in range(dims.y):
			var pid := _deck_tile_id(surface, i0 + i, j0 + j)
			var flat := Transform3D(Basis.IDENTITY, Vector3(
				(float(i0 + i) + 0.5) * pitch,
				marker.global_transform.origin.y,
				(float(j0 + j) + 0.5) * pitch))
			var piece := _spawn_piece(pid, flat, _run_stretch(flat.origin.z), true)
			if piece == null:
				continue
			_stamp(piece, "floor", "structure_deck", true)
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(pitch, 0.2, pitch)
			shape.shape = box
			shape.position = Vector3(0.0, DECK_TOP - 0.1, 0.0)
			body.add_child(shape)
			piece.add_child(body)

## Instantiate + warp + parent one piece; the flat transform is the authoring truth.
func _spawn_piece(pid: String, flat: Transform3D, stretch := 1.0, tilt := false) -> Node3D:
	var piece := ArchetypePieceLibrary.instantiate(pid)
	if piece == null:
		_unresolved.append(pid)
		return null
	piece.transform = _warp_transform(flat, stretch, tilt)
	_realized_root.add_child(piece)
	_placed_count += 1
	return piece

## A helical WATER BAND is a world-arc piece (baked curved around the axis, like
## the drum shells), NOT a warped-flat piece: band k covers s in [s0, s0+1] and
## is placed by pure rotation about the axis plus the climb height — bands tile
## mouth-to-mouth by construction. The bake runs toward NEGATIVE Blender angle,
## which lands as +s under Basis(UP, -theta) placement (verified by the datum
## probe in the wash-ascent test, never by eye).
func _spawn_water_band(pid: String, s0: float) -> Node3D:
	var piece := ArchetypePieceLibrary.instantiate(pid)
	if piece == null:
		_unresolved.append(pid)
		return null
	piece.transform = _water_band_transform(s0, 0.0)
	_realized_root.add_child(piece)
	_placed_count += 1
	return piece

func _water_band_transform(s0: float, y_off: float) -> Transform3D:
	return Transform3D(
		Basis(Vector3.UP, -(ChannelsArc.A0 + s0 * ChannelsArc.KTHETA)),
		Vector3(0.0, ChannelsArc.arc_pos(s0, 0.0).y + y_off, 0.0))

## The props scene's light nodes are authored flat like everything else — clone
## each onto the helix (the props root stays hidden as pure data).
func _warp_lights(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is OmniLight3D:
			var clone := (n as OmniLight3D).duplicate() as OmniLight3D
			clone.transform = _warp_transform((n as OmniLight3D).global_transform)
			_realized_root.add_child(clone)

## THE FLOOR IS THE READ (director): iron sluice bed = wash ground, wood
## plank = safe ground. One binary material truth — no decorative mixing of
## wood and grate, no per-tile noise. Sections sit on the tile grid, so the
## boundary is exact.
func _deck_tile_id(_surface: String, i: int, _j: int) -> String:
	var pitch := _piece_aabb("deck_planks").size.x
	var mid := (float(i) + 0.5) * pitch
	if _s_in_wash_span(mid):
		return "deck_sluice"
	return ["deck_planks", "deck_planks_b", "deck_planks_c"][i % 3]

func _s_in_wash_span(s: float) -> bool:
	for sec in WASH_SECTIONS:
		if s >= float(sec["s0"]) and s <= float(sec["s1"]):
			return true
	return false

func _wall_variant_ids() -> Array:
	return ["wall_panel_tile", "wall_panel_tile_b", "wall_panel_tile", "wall_panel_tile_c"]

func _row_hash(marker: Node3D, k: int) -> int:
	return absi(int(marker.position.x * 7.0) + int(marker.position.z * 13.0) + k * 5 + 3)

func _skip_set(marker: Node3D) -> Dictionary:
	var out: Dictionary = {}
	for part in str(marker.get_meta("skip", "")).split(",", false):
		out[int(part)] = true
	return out

## Survey metadata rides the piece ROOT: the wash-ascent survey test reads these.
func _stamp(piece: Node3D, mount: String, cluster: String, embed: bool) -> void:
	piece.set_meta("mount", mount)
	piece.set_meta("cluster", cluster)
	piece.set_meta("embed_ok", embed)

## The measured-AABB cache: one scratch instantiation per piece id, combined over
## the piece's whole subtree. This is the same math as tools/probe_piece_datums.gd.
func _piece_aabb(pid: String) -> AABB:
	if _piece_aabbs.has(pid):
		return _piece_aabbs[pid]
	var total := AABB()
	var piece := ArchetypePieceLibrary.instantiate(pid)
	if piece != null:
		total = _combined_aabb(piece, Transform3D.IDENTITY)
		piece.free()
	_piece_aabbs[pid] = total
	return total

func _combined_aabb(node: Node, xf: Transform3D) -> AABB:
	var total := AABB()
	var first := true
	var stack: Array = [[node, xf]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var t: Transform3D = entry[1]
		if n is Node3D and n != node:
			t = t * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var world: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
			total = world if first else total.merge(world)
			first = false
		for c in n.get_children():
			stack.append([c, t])
	return total

## A marker's `emission_scale` calms a piece's BAKED glow (a sign band, a screen)
## without touching its albedo — the grunge law's answer to a too-hot fixture.
func _scale_emission(piece: Node3D, scale: float) -> void:
	var stack: Array = [piece]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for si in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(si)
				if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
					var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.emission_energy_multiplier *= scale
					mi.set_surface_override_material(si, dup)
		for c in n.get_children():
			stack.append(c)

## The accent is a hue CUE riding shaded albedo, never a repaint (the grunge law).
## Materials are shared across clones, so each surface is duplicated before tinting.
func _tint_accent(piece: Node3D, color: Color, energy: float) -> void:
	var stack: Array = [piece]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for si in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(si)
				if mat is StandardMaterial3D:
					var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.emission_enabled = true
					dup.emission = color
					dup.emission_energy_multiplier = energy * 0.3
					mi.set_surface_override_material(si, dup)
		for c in n.get_children():
			stack.append(c)

## Walkability derives from the PLACED blockers — the grid cannot disagree with
## the scene, because the scene is measured after it exists. Cells are computed in
## the FLAT authoring frame (the data layer), before any warp enters the picture.
func _derive_wall_cells() -> void:
	_wall_cells.clear()
	var seen: Dictionary = {}
	for marker in _find_meta_nodes(_props_root, "piece"):
		if not BLOCKING_PIECES.has(str(marker.get_meta("piece"))):
			continue
		var aabb := _piece_aabb(str(marker.get_meta("piece")))
		var flat: AABB = (marker as Node3D).global_transform * aabb
		for cx in range(int(floor(flat.position.x)), int(ceil(flat.end.x))):
			for cz in range(int(floor(flat.position.z)), int(ceil(flat.end.z))):
				if cx < 0 or cz < 0 or cx >= int(DECK_W) or cz >= int(DECK_D):
					continue
				var key := "%d_%d" % [cx, cz]
				if not seen.has(key):
					seen[key] = true
					_wall_cells.append([cx, cz])

func _find_meta_nodes(root: Node, meta_key: String) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and n.has_meta(meta_key):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

# --- The wash gameplay layer (all scheduler-analytic; nothing per-frame) ---

## Each channel segment carries its trough glow materials (duplicated so each
## stretch brightens independently) AND its surge-water sheet. The wash drives
## both from scheduled callbacks — nothing per-frame.
func _register_channel_segment(piece: Node3D, flat_s: float) -> void:
	var mats: Array = []
	var stack: Array = [piece]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for si in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(si)
				if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
					var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					mi.set_surface_override_material(si, dup)
					mats.append(dup)
		for c in n.get_children():
			stack.append(c)
	for m in mats:
		_channel_base_energy[m] = (m as StandardMaterial3D).emission_energy_multiplier
	_channel_segments.append({"node": piece, "s": flat_s, "mats": mats})

## Every helical water band is registered against the flat s it STARTS at, so a
## section state change raises exactly the bands inside its span.
func _register_water_band(band: Node3D, s0: float, kind: String) -> void:
	_section_water.append({"node": band, "s0": s0, "kind": kind})

## The one wash-state display: "idle" (baked trickle only), "telegraph" (glow
## rises, the TROUGH's water line surfaces), "flood" (trough brims over and the
## deck bands cover the walkway), "held" (valve-quieted: dim, dry).
## Trough lifts: telegraph puts the water line between the baked snake and the
## rim; flood brims it just over the rim. The deck flood rides above the grate
## tops (0.19) but far under the rails. All bands share ONE material — the
## appearance never splits between the trough and the walkway.
func _set_wash_state(section: int, state: String) -> void:
	if section < 0 or section >= WASH_SECTIONS.size():
		return
	var s0 := float(WASH_SECTIONS[section]["s0"])
	var s1 := float(WASH_SECTIONS[section]["s1"])
	var band := 1.0
	var trough_on := false
	var deck_on := false
	var trough_lift := 0.0
	match state:
		"telegraph":
			band = 2.4; trough_on = true; trough_lift = 0.14
		"flood":
			band = 4.5; trough_on = true; deck_on = true; trough_lift = 0.24
		"held":
			band = 0.5
	for seg in _channel_segments:
		var mid := float(seg["s"]) + _piece_aabb("water_channel").size.x * 0.5
		if mid < s0 or mid > s1:
			continue
		for m in seg["mats"]:
			(m as StandardMaterial3D).emission_energy_multiplier = \
				float(_channel_base_energy.get(m, 1.0)) * band
	for entry in _section_water:
		var mid_s := float(entry["s0"]) + 0.5
		if mid_s < s0 or mid_s > s1:
			continue
		var water = entry["node"]
		if not (water is Node3D and is_instance_valid(water)):
			continue
		var w := water as Node3D
		if str(entry["kind"]) == "trough":
			w.visible = trough_on
			w.transform = _water_band_transform(float(entry["s0"]), trough_lift)
		else:
			# cosmetic rise/sink (node-bound tweens, wall-clock by design —
			# the kill predicate is the Channel's; this is only the look)
			var target := _water_band_transform(float(entry["s0"]), 0.20)
			if deck_on and not w.visible:
				w.visible = true
				w.transform = _water_band_transform(float(entry["s0"]), -0.06)
				var rise := w.create_tween()
				rise.tween_property(w, "transform", target, 0.35) \
					.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			elif deck_on:
				w.transform = target
			elif w.visible:
				var sink := w.create_tween()
				sink.tween_property(w, "transform",
					_water_band_transform(float(entry["s0"]), -0.06), 0.3)
				sink.tween_callback(func(): w.visible = false)

## One display truth: repaint every section from the kit's ACTUAL state. The
## bands are signal-driven, and two seams bypass signals — Channel.reset()
## (ring completion) cancels a live flood without emitting flood_ended, and a
## save-snapshot restore lands mid-flood with no synthetic signals at all.
## Without this sync, the first leaves a phantom flood frozen on a dry
## walkway; the second leaves INVISIBLE kill water. Both violate the law that
## the visible flood edge IS the kill-predicate edge.
func _sync_wash_display() -> void:
	for i in range(_channels.size()):
		var ch = _channels[i]
		var flooding: bool = ch != null and is_instance_valid(ch) \
			and bool(ch.call("is_flooding"))
		_set_wash_state(i, "flood" if flooding else "idle")

func on_game_state_snapshot_restored() -> void:
	_sync_wash_display()

# --- Datum probes: the tiling laws are MEASURED, never eyeballed ---

## Worst world-space gap between a deck tile's seam-edge midpoint and the
## analytic helix surface at that point. Horizontal (untilted) tiles terrace by
## ~KCLIMB*pitch/2 (~0.13 m); the ramp lattice must hold near zero.
func measure_deck_seam_error() -> float:
	var worst := 0.0
	for piece in _realized_root.get_children():
		if not (piece is Node3D):
			continue
		if str((piece as Node3D).get_meta("cluster", "")) != "structure_deck":
			continue
		for ex in [-1.0, 1.0]:
			var edge_mid: Vector3 = (piece as Node3D).global_transform \
				* Vector3(float(ex), 0.0, 0.0)
			var arc: Dictionary = ChannelsArc.world_to_arc(edge_mid)
			# tile BASES sit DECK_TOP below the walk surface (tops flush with it)
			var expected := ChannelsArc.arc_pos(float(arc["s"]), 0.0).y - DECK_TOP
			worst = maxf(worst, absf(edge_mid.y - expected))
	return worst

## Water-band datum probe: counts per kind, the fitted climb of a deck band's
## vertices vs the canonical KCLIMB/KTHETA (the sign catches a mirrored bake or
## placement — the drum's symmetric shells never could), and the emission
## spread across every band water material (the ONE-APPEARANCE law, measured).
func measure_water_bands() -> Dictionary:
	var deck_count := 0
	var trough_count := 0
	var w_min := Vector3.ONE * 1e9
	var w_max := Vector3.ONE * -1e9
	var slope := 0.0
	var slope_done := false
	var sources: Array = []
	for entry in _section_water:
		var node = entry["node"]
		if not (node is Node3D and is_instance_valid(node)):
			continue
		if str(entry["kind"]) == "deck":
			deck_count += 1
		else:
			trough_count += 1
		sources.append([node, str(entry["kind"]) == "deck"])
	# the troughs' BAKED snake water must match the bands too — the one-
	# appearance law covers every visible water in the scene, not just bands
	for seg in _channel_segments:
		if seg["node"] is Node3D and is_instance_valid(seg["node"]):
			sources.append([seg["node"], false])
	for src in sources:
		var stack: Array = [src[0]]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var mi := n as MeshInstance3D
				for si in range(mi.mesh.get_surface_count()):
					var mat := mi.get_active_material(si)
					if mat is StandardMaterial3D \
							and (mat as StandardMaterial3D).emission_enabled:
						var sm := mat as StandardMaterial3D
						# WATER is blue-dominant; foam emits near-gray. The
						# comparable quantity is color x energy — a <=1.0
						# authored strength bakes into the color on export,
						# so raw energy alone measures nothing.
						if sm.emission.b > sm.emission.r * 1.4:
							var w := Vector3(sm.emission.r, sm.emission.g,
								sm.emission.b) * sm.emission_energy_multiplier
							w_min = w_min.min(w)
							w_max = w_max.max(w)
				if not slope_done and bool(src[1]):
					slope = _band_vertex_slope(mi)
					slope_done = true
			for c in n.get_children():
				stack.append(c)
	var spread := (w_max - w_min).length() if w_max.x >= w_min.x else 0.0
	return {"deck": deck_count, "trough": trough_count,
		"emission_spread": spread, "climb_slope": slope}

## Least-squares dy/dtheta over a band mesh's world vertices (theta unwrapped
## near the band's start). The canonical helix climbs KCLIMB/KTHETA per radian.
func _band_vertex_slope(mi: MeshInstance3D) -> float:
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var xform := mi.global_transform
	var t0 := 0.0
	var first := true
	var sum_t := 0.0
	var sum_y := 0.0
	var sum_tt := 0.0
	var sum_ty := 0.0
	var n := 0
	for v in verts:
		var w: Vector3 = xform * v
		var t := atan2(w.z, w.x)
		if first:
			t0 = t
			first = false
		t = wrapf(t - t0, -PI, PI)
		sum_t += t
		sum_y += w.y
		sum_tt += t * t
		sum_ty += t * w.y
		n += 1
	var denom := float(n) * sum_tt - sum_t * sum_t
	if absf(denom) < 1e-9:
		return 0.0
	return (float(n) * sum_ty - sum_t * sum_y) / denom

## THE COMPOSITION (P-KIT): the wash is three reusable Channel kit objects — the
## kit owns cadence, catch, carry, and the fail-forward bite; this chunk supplies
## only SPATIAL POLICY (where "downstream" lands) and binds its piece-built water
## display to the kit's signals. See docs/GAMEPLAY_OBJECTS.md.
func _build_wash_channels() -> void:
	for i in range(WASH_SECTIONS.size()):
		var sec: Dictionary = WASH_SECTIONS[i]
		var s0 := float(sec["s0"])
		var s1 := float(sec["s1"])
		var ch := Channel.new()
		ch.name = "WashChannel%d" % i
		ch.owns_visuals = false                    # the piece water sheets are the view
		ch.telegraph_lead = TELEGRAPH_LEAD
		ch.configure((s0 + s1) * 0.5, (s1 - s0) * 0.5, WASH_Z_HALF,
			float(sec["period"]), float(sec["dur"]), WASH_GRACE + float(sec["phase"]),
			"wash_ascent_ch%d" % i, WASH_Z_CENTER)  # the FULL walkway width
		ch.telegraphed.connect(_on_channel_telegraph.bind(i))
		ch.flood_started.connect(_on_channel_flood_started.bind(i))
		ch.flood_ended.connect(_on_channel_flood_ended.bind(i))
		add_child(ch)
		_channels.append(ch)
		# THE SURGE: helical deck bands — one modeled arc of water per unit of
		# s, spanning the whole walkway width, hidden at idle. Integer section
		# spans mean the bands cover the kill zone EXACTLY, mouth-to-mouth.
		for k in range(int(s1 - s0)):
			var band := _spawn_water_band("water_band_deck", s0 + float(k))
			if band != null:
				_stamp(band, "floor", "structure_channel", true)
				band.visible = false
				_register_water_band(band, s0 + float(k), "deck")
	# The trough's own risen water line: the same bands at the channel's radius,
	# covering exactly the span the trough run measured out.
	var t0 := _channel_span.x
	while t0 + 1.0 <= _channel_span.y + 0.001:
		var trough := _spawn_water_band("water_band_trough", t0)
		if trough != null:
			_stamp(trough, "floor", "structure_channel", true)
			trough.visible = false
			_register_water_band(trough, t0, "trough")
		t0 += 1.0

## Arm (or re-arm) the kit cadences. Called from reset_preview_state — the host
## invokes that after build and on every reload, so play and headless match.
func reset_preview_state() -> void:
	_phase = "active"
	_swept_count = 0
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs != null and "data_frame_bounds" in gs:
		gs.data_frame_bounds = Rect2(0.0, 0.0, DECK_W, DECK_D)
	for i in range(_channels.size()):
		var ch: Channel = _channels[i]
		ch.reset()
		ch.clear_sweep_refractory()
		if gs != null:
			ch.set_sweep(gs, PARTY_IDS, _sweep_landing.bind(i), {
				"party_hp": SWEEP_HP_BITE,
				"refractory": 1.0,
				"travel_speed": 7.0,
				"on_swept": _on_swept.bind(i),
				"enemy_resolver": _fauna_by_id,
				"enemy_damage": 10.0,
				"enemy_stun": 2.5,
			})
		if sched != null:
			ch.start(sched, gs)
		_set_wash_state(i, "idle")
	if _ring_exit != null:
		_ring_exit.reset_shelter()
	for id_v in _fauna.keys():
		var enemy = _fauna[id_v]
		if is_instance_valid(enemy) and gs != null and gs.characters.has(str(id_v)):
			var anchor: Vector3 = enemy.get_meta("roam_anchor", gs.get_position(str(id_v)))
			gs.snap_character_to(str(id_v), anchor)
			# a HARD home reset — a polite set_roam leaves a mid-pursuit sentry
			# chasing ghosts with old damage across scenario re-arms
			enemy.reset_to_home()

## The one spatial policy this chunk supplies the kit: a swept member lands MOBILE
## at the section's mouth, spread by identity so a party never stacks one cell.
func _sweep_landing(id: String, _origin: Vector3, i: int) -> Vector3:
	var s0 := float(WASH_SECTIONS[i]["s0"])
	var x := maxf(s0 - 1.5, 1.0)
	# a washed ENEMY is spat out on the HIGH channel side, off the walking
	# lane — the beaten thing drags itself out by the trough, never into the
	# party's waiting spot (the settle_pos lesson, applied to the sweep too)
	if not PARTY_IDS.has(id):
		return Vector3(x, DECK_TOP, 6.6 + 0.3 * float(absi(hash(id)) % 2))
	return Vector3(x, DECK_TOP, 3.0 + 0.9 * float(absi(hash(id)) % 3))

func _on_swept(_id: String, _i: int) -> void:
	_swept_count += 1
	_show_note("The surge takes one of you. The channel gives nothing back.", 2.4)

func _on_channel_telegraph(i: int) -> void:
	if _phase == "active":
		_set_wash_state(i, "telegraph")

## Guarded like telegraph/ended — a live flood must never repaint a display a
## non-active phase owns (completion, capture stills, teardown).
func _on_channel_flood_started(i: int) -> void:
	if _phase == "active":
		_set_wash_state(i, "flood")

func _on_channel_flood_ended(i: int) -> void:
	if _phase == "active":
		_set_wash_state(i, "idle")

# --- Interactables: the valve, the terminal, the portal ---

func _build_interactables() -> void:
	# Every control stands on DRY ground (the audit's law: the operator of a
	# tool never pays the hazard the tool addresses just for clicking it).
	# The valve sits in the 9-11 gap just past section 0's inclusive mouth;
	# the terminal in the same gap informs the section AHEAD of it.
	var valve := _add_interactable(self, "ChannelValve",
		"Hold the near channel closed", Vector3(9.6, DECK_TOP, 0.9),
		"HOLD THE VALVE", "", 1.1, false, 1.6,
		Interactable.InteractableType.INSPECTION)
	valve.consequence_preview = "The near stretch runs quiet for a while — cross the band without the surge."
	_wire_trigger(valve, _on_valve)
	# the valve is ELECTRONIC: Aster's EMP overloads it from range for the same
	# hold — the canonical anti-tech cast gets a real job in this level (fauna
	# never opt in; mechanisms do)
	# The LANDING VALVE is section 3's key — the same kit verb as the bay
	# valve, re-asked at the pump landing where the crews regulated the upper
	# run. It stands in the 24-28 gap; section 3's dry beat fits no gait, so
	# holding this valve IS the crossing.
	var landing_valve := _add_interactable(self, "LandingValve",
		"Hold the transfer channel closed", Vector3(26.6, DECK_TOP, 0.9),
		"HOLD THE VALVE", "", 1.1, false, 1.6,
		Interactable.InteractableType.INSPECTION)
	landing_valve.consequence_preview = "The transfer stretch never runs dry on its own. Hold it closed and walk the bed."
	_wire_trigger(landing_valve, _on_landing_valve)
	var landing_rx := EmpReceiver.new()
	landing_rx.name = "LandingValveEmpReceiver"
	landing_rx.on_pulse = func(_duration: float) -> bool:
		if _phase != "active" or _channels.size() <= 3:
			return false
		if (_channels[3] as Channel).held_until() > _get_scheduler_tick_safe():
			return false
		_on_landing_valve()
		return true
	landing_valve.add_child(landing_rx)
	var terminal := _add_interactable(self, "CadenceTerminal",
		"Log the surge cadence", Vector3(10.2, DECK_TOP, 6.8),
		"LOG THE SURGE", "aster", 1.1, false, 1.6,
		Interactable.InteractableType.INSPECTION)
	terminal.consequence_preview = "Aster reads the channel's rhythm — the next surge becomes a number, not a guess."
	_wire_trigger(terminal, _on_terminal)
	var valve_rx := EmpReceiver.new()
	valve_rx.name = "ValveEmpReceiver"
	valve_rx.on_pulse = func(_duration: float) -> bool:
		if _phase != "active" or _channels.is_empty():
			return false
		if (_channels[0] as Channel).held_until() > _get_scheduler_tick_safe():
			return false
		_on_valve()
		return true
	valve.add_child(valve_rx)
	# PUSH-YOUR-LUCK: a salvage dwell INSIDE section 1's span. No character
	# gate — the CADENCE is the gate: the work beat only fits if you read the
	# beat first. One-shot, pays the party in ATP.
	var stash := _add_interactable(self, "SunkenStash",
		"Pry the sunken stash loose", Vector3(14.2, DECK_TOP, 6.4),
		"SALVAGE THE STASH", "", 2.2, true, 1.5,
		Interactable.InteractableType.TIMED_ACTION)
	stash.consequence_preview = "The crews left supplies mid-stretch. The water decides how long you get."
	_wire_trigger(stash, _on_sunken_stash)
	# the start bookend: downed members can be dragged back to the approach and
	# revived on safe ground — a swept-down member never soft-locks the run
	var gs_shelter = _get_game_state()
	if gs_shelter != null and gs_shelter.has_method("add_shelter_region"):
		gs_shelter.add_shelter_region(Vector2(0.0, 0.0), Vector2(1.8, DECK_D))
	# THE WIN goes through the kit's win object — click-gated, downed-guarded,
	# everyone on the pad, ONE atomic party rest (see ExitShelter's header).
	# The pad rides the drum-head ledge PAST the last span, but its ground is
	# not free: the drum watcher's roam ring reaches the pad's sightline, so
	# an unanswered watcher interrupts the rest — the pressure that survives
	# the set-piece. The answers are all composed ones: the high flure's pull
	# (the wash prices the watcher's descent), or the upper capbage's hide.
	var ring_exit := ExitShelter.new()
	ring_exit.name = "AscentPortal"
	ring_exit.configure_shelter(_get_game_state(), Vector3(48.5, DECK_TOP, 3.0),
		Vector2(1.5, 1.5), PARTY_IDS, "ENTER THE RING", 1.3)
	ring_exit.consequence_preview = "The ring hums. Gather everyone on the pad and step through together."
	ring_exit.rest_completed.connect(_on_ring_rest_completed)
	ring_exit.rest_refused.connect(_on_ring_rest_refused)
	add_child(ring_exit)
	_register_interactable(ring_exit)
	_ring_exit = ring_exit
	_build_lonely_flure()
	_build_high_flure()
	var map = get_coord_map()
	warp_interactables_onto_coord_map(map)
	call_deferred("_wire_warped_outlines")

## Auto-outline collects meshes at the interactable's AUTHORED coordinates, but
## every visible piece here is WARPED onto the helix — a flat collect either
## finds nothing (the flat point lies outside the bowl entirely) or silently
## wraps whatever random piece occupies those numbers as world coordinates
## (the valve once outlined a deck tile at the coil's start). Once the warp
## has landed, re-wire every interactable against its WARPED position so the
## outline grammar highlights the REAL object.
func _wire_warped_outlines() -> void:
	for it in _interactables:
		if not (is_instance_valid(it) and it is Node3D):
			continue
		if not ("_outline_target" in it):
			continue
		var stale = it.get("_outline_target")
		if stale != null and is_instance_valid(stale) \
				and not (it as Node).is_ancestor_of(stale):
			(stale as Node).queue_free()
		it.call("set_outline_target", null)
		_auto_outline_interactable(it, self, (it as Node3D).global_position,
			maxf(1.2, float(it.get("interaction_radius"))))

## The lonely flure is the REAL kit object (the lure_relay composition shape) —
## an iron decoy with an empty target list: it fires, and nothing answers. The
## piece at the marker is its body; the beat is the wiring working.
func _build_lonely_flure() -> void:
	var gs = _get_game_state()
	var marker := _props_root.find_child("LonelyFlure", true, false) if _props_root else null
	if gs == null or not (marker is Node3D):
		return
	var flure: Flure = Flure.new()
	flure.name = "LonelyFlureObject"
	flure.authority_id = "wash_ascent_lonely_flure"
	# an iron song carries 32u — an unfiltered roster would drag the UPPER
	# watch down through the lower spans during this mid-level beat, deleting
	# act two's encounter before it's met; the authored target list is the
	# kit's own contract, so each flure sings to its own act
	flure.configure(gs, (marker as Node3D).global_position,
		_fauna_ids_in_band(0.0, 28.0), 32.0, 1.4,
		Color(0.95, 0.62, 0.14))
	# lured sentries PARK high-z in the gap, not on the flure itself — the low-z
	# lane past the song stays walkable (a park on the source pulled the gap
	# sentry point-blank into the waiting party, where distraction can't help)
	flure.settle_pos = Vector3(17.8, DECK_TOP, 6.8)
	flure.set_enemy_resolver(_fauna_by_id)
	flure.one_shot = false
	flure.description = "Light the lonely flure"
	flure.tutorial_label = "LIGHT THE FLURE"
	flure.flure_activated.connect(_on_lonely_flure_lit)
	add_child(flure)
	_register_interactable(flure)
	_flures.append(flure)
	# the library piece at the marker is the flure's BODY; the kit's own glow
	# bulb stays off so no self-drawn primitive reaches the visible scene
	var glow := flure.find_child("Glow", true, false)
	if glow is Node3D:
		(glow as Node3D).visible = false

func _build_high_flure() -> void:
	var gs = _get_game_state()
	var marker := _props_root.find_child("HighFlure", true, false) if _props_root else null
	if gs == null or not (marker is Node3D):
		return
	var flure: Flure = Flure.new()
	flure.name = "HighFlureObject"
	flure.authority_id = "wash_ascent_high_flure"
	flure.configure(gs, (marker as Node3D).global_position,
		_fauna_ids_in_band(28.0, DECK_W), 32.0, 1.4,
		Color(0.95, 0.62, 0.14))
	# answerers park LOW-z by the patrol line — the player's crossing lane is
	# the high-z back wall, so the pull drags every threat AWAY from it; the
	# drum watcher's descent crosses section 4 and pays the wash on the way
	flure.settle_pos = Vector3(36.6, DECK_TOP, 1.0)
	flure.set_enemy_resolver(_fauna_by_id)
	flure.one_shot = false
	flure.description = "Light the high flure"
	flure.tutorial_label = "LIGHT THE FLURE"
	flure.flure_activated.connect(_on_lonely_flure_lit)
	add_child(flure)
	_register_interactable(flure)
	_flures.append(flure)
	var glow := flure.find_child("Glow", true, false)
	if glow is Node3D:
		(glow as Node3D).visible = false

## Concealment is DERIVED state ticked from hide-zone proximity (the engine
## rebuilds it on replay from logged movement): crouching into the capbage's
## span is a full hide. No enemies walk this slice yet — the wiring is what
## makes the element real for the compositions that add them.
func _tick_concealment() -> void:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("set_character_concealment"):
		return
	if _hide_spots_cache.is_empty() and _props_root != null:
		for marker in _find_meta_nodes(_props_root, "piece"):
			if str(marker.get_meta("piece")) == "capbage":
				_hide_spots_cache.append((marker as Node3D).position)
	var hide_spots: Array = _hide_spots_cache
	if hide_spots.is_empty():
		return
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id):
			continue
		var p: Vector3 = gs.get_position(char_id)
		var near := false
		for hide_pos in hide_spots:
			if Vector2(p.x - (hide_pos as Vector3).x, p.z - (hide_pos as Vector3).z).length() < 1.1:
				near = true
				break
		gs.set_character_concealment(char_id,
			gs.CONCEAL_FULL if near else gs.CONCEAL_NONE)

## A song whose target was physically broken (washed, stunned, struck) must
## RE-ARM so the player can sing again — the kit's reconcile verb is inert
## while every applied target is still bound; the world state decides.
func _tick_flures() -> void:
	for f in _flures:
		if is_instance_valid(f):
			f.reconcile_interrupted_targets()

func _process(_delta: float) -> void:
	_tick_concealment()
	_tick_flures()

func headless_process(_delta: float) -> void:
	_tick_concealment()
	_tick_flures()

func _wire_trigger(interactable: Area3D, cb: Callable) -> void:
	if interactable != null and interactable.has_signal("interacted"):
		interactable.connect("interacted", cb)

## The valve speaks the kit's verb: Channel.hold() ends any in-flight flood and
## skips swallowed onsets to the next analytic beat. The view reacts through the
## kit's own signals; this handler adds only the note and the held display.
## The terminal names the section AHEAD of it — never an aggregate min() that
## quotes a surge BEHIND the reader (the wash_relay FlowTerminal pattern:
## Aster's timing job is a diegetic world target, positional truth).
func _on_terminal(_args = null) -> void:
	var terminal_s := 10.2
	var ahead := -1
	for i in range(WASH_SECTIONS.size()):
		if float(WASH_SECTIONS[i]["s0"]) > terminal_s:
			ahead = i
			break
	if ahead >= 0 and ahead < _channels.size():
		var onset := maxf(0.0, float((_channels[ahead] as Channel).get_state().get("next_onset_in", 0.0)))
		_show_note("// CADENCE LOGGED // the stretch ahead surges in %.0fs" % onset, 2.6)
	else:
		_show_note("// CADENCE LOGGED // open water ahead", 2.6)
	_set_preview_step("wash_ascent_cadence_logged")

func _get_scheduler_tick_safe() -> float:
	var sched = _get_scheduler()
	return float(sched.get_current_tick()) if sched != null else 0.0

func _on_valve(_args = null) -> void:
	if _phase != "active" or _channels.is_empty():
		return
	(_channels[0] as Channel).hold(VALVE_HOLD_WINDOW)
	_set_wash_state(0, "held")

func _on_landing_valve(_args = null) -> void:
	if _phase != "active" or _channels.size() <= 3:
		return
	(_channels[3] as Channel).hold(VALVE_HOLD_WINDOW)
	_set_wash_state(3, "held")
	_show_note("// VALVE HELD // the near channel runs quiet", 2.2)
	_set_preview_step("wash_ascent_valve_held")

## The mid-span stash pays the party in the survival currencies this level
## actually spends — hp and stamina (crew rations) — if the cadence lets the
## pry finish. The work dwell rides the gameplay scheduler, and a surge
## mid-work sweeps the worker like anything else standing there: the price IS
## the read you should have taken first.
func _on_sunken_stash(_args = null) -> void:
	var gs = _get_game_state()
	if gs != null:
		for id_v in PARTY_IDS:
			if gs.characters.has(str(id_v)):
				gs.adjust_stat(str(id_v), "hp", 10.0)
				gs.adjust_stat(str(id_v), "stamina", 20.0)
	_show_note("The stash comes loose — crew rations, still sealed. Everyone breathes easier.", 2.8)
	_set_preview_step("wash_ascent_stash_salvaged")

func _on_ring_rest_completed(_members: Array) -> void:
	_phase = "complete"
	for ch in _channels:
		(ch as Channel).reset()
	_sync_wash_display()
	_show_note("The ring takes you. The coil keeps climbing without you.", 3.0)
	_set_preview_step("wash_ascent_complete")

func _on_ring_rest_refused(reason: String, _missing: Array) -> void:
	if reason == "downed":
		_show_note("// THE RING WAITS // no one gets left on the deck", 2.4)
	else:
		_show_note("// THE RING WAITS // gather everyone on the pad", 2.4)

## Canonical fauna from a scene-node marker (roster: Sapscraps — scavengers, the
## species an iron decoy CAN pull). The body is the Enemy base's placeholder
## capsule — honestly flagged until the creature-grammar hookup. Roam is local
## wander (no pathfinding) anchored at the marker; detection sees the party.
func _spawn_fauna(marker: Node3D) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var enemy := Enemy.new()
	enemy.char_id = "%s_%d" % [str(marker.get_meta("enemy")), _fauna.size()]
	enemy.name = "Enemy_%s" % enemy.char_id
	enemy.position = marker.position
	enemy.detection_range = float(marker.get_meta("detect", enemy.detection_range))
	enemy._detection_targets.assign(PARTY_IDS)
	_realized_root.add_child(enemy)
	enemy.game_state = gs
	if not gs.characters.has(enemy.char_id):
		gs.register_character(enemy.char_id, enemy.position, enemy.move_speed,
			{"detection_range": float(enemy.detection_range)})
	enemy.activate()
	# the canonical BODY from the library replaces the base placeholder capsule
	# (the Enemy's cosmetic pulses act on its own _mesh and safely no-op here)
	var body := ArchetypePieceLibrary.instantiate("sapscrap_body")
	if body != null:
		for c in enemy.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = false
			elif c is Light3D:
				(c as Light3D).visible = false
		enemy.add_child(body)
	enemy.set_meta("roam_anchor", marker.position)
	if marker.has_meta("patrol_route"):
		var waypoints: Array[Vector3] = []
		for pair in str(marker.get_meta("patrol_route")).split(" ", false):
			var xz := str(pair).split(",", false)
			if xz.size() == 2:
				waypoints.append(Vector3(float(xz[0]), DECK_TOP, float(xz[1])))
		if waypoints.size() >= 2:
			enemy.set_patrol(waypoints)
		else:
			push_error("wash_ascent: patrol_route on %s needs >= 2 waypoints" % marker.name)
	else:
		enemy.set_meta("roam_radius", float(marker.get_meta("roam_radius", 3.0)))
		enemy.set_roam(marker.position, float(marker.get_meta("roam_radius", 3.0)))
	_fauna[enemy.char_id] = enemy

func _fauna_by_id(id: String):
	return _fauna.get(id)

## The fauna roster of one ACT: enemies whose home anchor lies in [x0, x1).
func _fauna_ids_in_band(x0: float, x1: float) -> Array:
	var out: Array = []
	for id_v in _fauna.keys():
		var e = _fauna[id_v]
		if is_instance_valid(e):
			var ax := float((e.get_meta("roam_anchor", Vector3.ZERO) as Vector3).x)
			if ax >= x0 and ax < x1:
				out.append(id_v)
	return out

func _on_lonely_flure_lit(pulled: int) -> void:
	_show_note("The flure sings. Nothing answers." if pulled == 0
		else "The flure sings, and something turns toward it.", 2.6)

# --- Preview host contract ---

func get_scene_title() -> String:
	return "Wash Ascent"

func get_scene_help() -> String:
	return "Reach the ring at the drum head. // The wash floods whole stretches of the walkway — cross each on its dry beat; valves can hold a stretch quiet; the gaps between sections are safe ground."

func get_grid_data() -> Dictionary:
	return {
		"origin": [0.0, DECK_TOP, 0.0],
		"cell_size": 1.0,
		"width": int(DECK_W),
		"height": int(DECK_D),
		"default_walkable": false,
		"walkable_regions": [{"min": [0.0, 0.0], "max": [DECK_W, DECK_D]}],
		"wall_cells": _wall_cells,
	}

## The whole party spawns STRICTLY before section 0's mouth (s0 = 2.0, and the
## Channel catch is boundary-inclusive) — nobody boots standing on the visible
## kill edge, and every offset stays on the deck (x > 0).
func get_spawn_positions() -> Dictionary:
	var anchor := Vector3(1.2, DECK_TOP, 3.0)
	var marker := _props_root.find_child("SpawnPlayer", true, false) if _props_root else null
	if marker is Node3D:
		anchor = (marker as Node3D).global_position
	return {
		"aster": anchor,
		"peris": anchor + Vector3(-0.6, 0.0, 1.4),
		"endo": anchor + Vector3(-0.9, 0.0, -1.2),
	}

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors["portal_ledge"] = Vector3(22.5, DECK_TOP, 3.0)
	anchors["maintenance_bay"] = Vector3(11.0, DECK_TOP, 4.0)
	anchors["danger_band"] = Vector3(6.0, DECK_TOP, 1.0)
	return anchors

## The authored grade: dark and grungy, with a playable light floor.
func get_preview_lighting_profile() -> Dictionary:
	return {
		"tonemap_mode": "filmic",
		"tonemap_white": 1.1,
		"glow_bloom": 0.08,
		"ambient_energy_floor": 0.22,
		"ambient_energy_ceiling": 0.42,
		"background_color": Color(0.012, 0.016, 0.022),
		"background_mix": 0.85,
	}

func get_preview_state() -> Dictionary:
	var onsets: Array = []
	for ch in _channels:
		onsets.append(float((ch as Channel).get_state().get("next_onset_in", -1.0)))
	return {
		"placed": _placed_count,
		"unresolved": _unresolved.duplicate(),
		"wall_cells": _wall_cells.size(),
		"phase": _phase,
		"channels": _channels.size(),
		"next_onsets_in": onsets,
		"swept_count": _swept_count,
		"valve_hold_until": (_channels[0] as Channel).held_until() if not _channels.is_empty() else -1.0,
		"fauna": _fauna.size(),
	}
