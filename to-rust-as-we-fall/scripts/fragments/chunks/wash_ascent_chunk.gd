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
## THE WASH (restored): the channel surges on a data-driven cadence and overtops
## the FRONT BAND of the walkway (z < DANGER_Z — the rail line marks the safe
## boundary; the authored rail gaps are the risky crossings). Everything rides the
## scheduler analytically (onset = t0 + grace + phase + period*k), so 1x and 10x
## are identical: telegraph pulse, flood, sweep rechecks, valve hold, re-arm.

const PROPS_SCENE := preload("res://scenes/fragments/chunks/wash_ascent_props.tscn")

const DECK_W := 26.0
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
const WASH_SECTIONS := [
	{"s0": 2.0, "s1": 10.0, "period": 12.0, "dur": 2.2, "phase": 0.0},
	{"s0": 10.0, "s1": 18.0, "period": 15.0, "dur": 2.4, "phase": 5.0},
	{"s0": 18.0, "s1": 26.0, "period": 18.0, "dur": 2.6, "phase": 9.0},
]
const WASH_GRACE := 4.0            # quiet seconds after reset before the first surge
const TELEGRAPH_LEAD := 1.2        # channel brightens this long before the water arrives
const DANGER_Z := 2.0              # authoring-frame band the surge overtops (z < this)
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
var _channel_base_energy: Dictionary = {}

var _channels: Array = []           # the composed Channel kit objects, one per section
var _fauna: Dictionary = {}         # char_id -> Enemy (canonical Sapscraps; placeholder bodies)
var _ring_exit: ExitShelter = null
var _swept_count := 0
var _terminal_logged := false
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
func _warp_transform(flat: Transform3D, stretch := 1.0) -> Transform3D:
	var s := flat.origin.x
	var lane := LANE_CENTER - flat.origin.z
	# The change of frame flat->helix is RotY(-PI/2); composing the piece's FULL
	# flat basis (not just an extracted yaw) also carries vertical rotations —
	# the pipe router's elbows and risers warp correctly through the same path.
	return Transform3D(
		ChannelsArc.basis_at(s)
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
			_skip_set(n3), "wall", "structure_wall")
	elif n3.has_meta("channel_run"):
		_realize_channel_run(n3, int(n3.get_meta("channel_run")))
	elif n3.has_meta("drum_shell"):
		_realize_drum_shell(n3)
	elif n3.has_meta("rail_run"):
		_realize_row(n3, ["railing_run"], int(n3.get_meta("rail_run")),
			_skip_set(n3), "floor", "structure_rail")
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
## real AABB x-length, each piece offset so its AABB START sits at k*pitch —
## asymmetric pieces (the ball-joint pipe) still meet mouth-to-mouth exactly.
func _realize_row(marker: Node3D, variant_ids: Array, count: int, skip: Dictionary,
		mount: String, cluster: String) -> void:
	if variant_ids.is_empty() or count <= 0:
		return
	var pitch := _piece_aabb(str(variant_ids[0])).size.x
	if pitch <= 0.0:
		_unresolved.append(str(variant_ids[0]))
		return
	for k in range(count):
		if skip.has(k):
			continue
		var pid := str(variant_ids[_row_hash(marker, k) % variant_ids.size()])
		var aabb := _piece_aabb(pid)
		var flat := marker.global_transform \
			* Transform3D(Basis.IDENTITY, Vector3(float(k) * pitch - aabb.position.x, 0.0, 0.0))
		var piece := _spawn_piece(pid, flat, _run_stretch(flat.origin.z))
		if piece == null:
			continue
		_stamp(piece, mount, cluster, true)

## The channel run is three pieces working together: the trough segments meeting
## mouth-to-mouth, a bolted JOINT COLLAR clamped over every interior seam (real
## pipe-run infrastructure — the seam notch was a flagged artifact), and one
## SURGE WATER sheet riding each segment, hidden at idle: the wash raises real
## modeled water now, not a glow change.
func _realize_channel_run(marker: Node3D, count: int) -> void:
	var pitch := _piece_aabb("water_channel").size.x
	for k in range(count):
		var flat := marker.global_transform \
			* Transform3D(Basis.IDENTITY, Vector3((float(k) + 0.5) * pitch, 0.0, 0.0))
		var seg := _spawn_piece("water_channel", flat, _run_stretch(flat.origin.z))
		if seg == null:
			continue
		_stamp(seg, "floor", "structure_channel", true)
		var water := _spawn_piece("water_surface", flat, _run_stretch(flat.origin.z))
		if water != null:
			_stamp(water, "floor", "structure_channel", true)
			water.visible = false
		_register_channel_segment(seg, water, flat.origin.x - pitch * 0.5)
		if k > 0:
			var seam := marker.global_transform \
				* Transform3D(Basis.IDENTITY, Vector3(float(k) * pitch, 0.0, 0.0))
			var collar := _spawn_piece("channel_collar", seam, 1.0)
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
	for pick in PipeGrid.resolve(cells, extra):
		var cell: Vector3i = pick["cell"]
		var flat := marker.global_transform * Transform3D(pick["basis"] as Basis,
			Vector3(cell) + Vector3(0.5, 0.5, 0.0))
		var piece := _spawn_piece(str(pick["piece"]), flat)
		if piece != null:
			_stamp(piece, "attached", cluster, true)

## The drum shell is WORLD architecture — anchored on the coil's axis, not the
## flat frame. The marker contributes its yaw angle (degrees) and height only.
func _realize_drum_shell(marker: Node3D) -> void:
	var piece := ArchetypePieceLibrary.instantiate("drum_shell")
	if piece == null:
		_unresolved.append("drum_shell")
		return
	piece.transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(float(marker.get_meta("drum_shell")))),
		Vector3(0.0, marker.position.y, 0.0))
	_stamp(piece, "floor", "structure_drum", true)
	_realized_root.add_child(piece)
	_placed_count += 1

## Deck runs lay nx × nz two-metre tiles in the marker's local frame, each tile
## individually warped (the strip polygonalizes in flat space, curves per-tile).
## Every tile carries its own invisible collision box so the ground ray lands on
## the curved deck. Surface meta is the decay story; variation is a pure hash.
func _realize_deck_run(marker: Node3D) -> void:
	var dims: Vector2i = marker.get_meta("deck_run")
	var surface := str(marker.get_meta("surface", "mixed"))
	var pitch := _piece_aabb("deck_planks").size.x
	for i in range(dims.x):
		for j in range(dims.y):
			var pid := _deck_tile_id(surface, _row_hash(marker, i * 31 + j * 7))
			var flat := marker.global_transform * Transform3D(Basis.IDENTITY,
				Vector3((float(i) + 0.5) * pitch, 0.0, (float(j) + 0.5) * pitch))
			var piece := _spawn_piece(pid, flat, _run_stretch(flat.origin.z))
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
func _spawn_piece(pid: String, flat: Transform3D, stretch := 1.0) -> Node3D:
	var piece := ArchetypePieceLibrary.instantiate(pid)
	if piece == null:
		_unresolved.append(pid)
		return null
	piece.transform = _warp_transform(flat, stretch)
	_realized_root.add_child(piece)
	_placed_count += 1
	return piece

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

func _deck_tile_id(surface: String, h: int) -> String:
	match surface:
		"planks":
			return ["deck_planks", "deck_planks_b", "deck_planks_c"][h % 3]
		"worn":
			return ["deck_grate", "deck_grate_b", "deck_grate", "deck_planks_c",
				"deck_grate_b", "deck_planks"][h % 6]
		_:
			return ["deck_planks", "deck_grate", "deck_planks_b", "deck_grate_b",
				"deck_planks_c"][h % 5]

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
func _register_channel_segment(piece: Node3D, water: Node3D, flat_s: float) -> void:
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
	_channel_segments.append({"node": piece, "water": water, "s": flat_s, "mats": mats})

## The one wash-state display: "idle" (bare trough), "telegraph" (glow rises,
## the water sheet surfaces low), "flood" (the sheet rides high and bright),
## "held" (valve-quieted: dimmer than idle, no water).
func _set_wash_state(section: int, state: String) -> void:
	if section < 0 or section >= WASH_SECTIONS.size():
		return
	var s0 := float(WASH_SECTIONS[section]["s0"])
	var s1 := float(WASH_SECTIONS[section]["s1"])
	var band := 1.0
	var water_on := false
	var water_lift := 0.0
	match state:
		"telegraph":
			band = 2.4; water_on = true; water_lift = 0.18
		"flood":
			band = 4.5; water_on = true; water_lift = 0.34
		"held":
			band = 0.5
	for seg in _channel_segments:
		var mid := float(seg["s"]) + _piece_aabb("water_channel").size.x * 0.5
		if mid < s0 or mid > s1:
			continue
		for m in seg["mats"]:
			(m as StandardMaterial3D).emission_energy_multiplier = \
				float(_channel_base_energy.get(m, 1.0)) * band
		var water = seg["water"]
		if water is Node3D and is_instance_valid(water):
			(water as Node3D).visible = water_on
			var lifted: Transform3D = (water as Node3D).transform
			lifted.origin.y = ChannelsArc.arc_pos(mid, 0.0).y \
				- DECK_TOP + 0.02 + water_lift
			(water as Node3D).transform = lifted

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
		ch.configure((s0 + s1) * 0.5, (s1 - s0) * 0.5, 1.4,
			float(sec["period"]), float(sec["dur"]), WASH_GRACE + float(sec["phase"]),
			"wash_ascent_ch%d" % i, 0.6)           # band: z -0.8 .. DANGER_Z
		ch.telegraphed.connect(_on_channel_telegraph.bind(i))
		ch.flood_started.connect(_set_wash_state.bind(i, "flood"))
		ch.flood_ended.connect(_on_channel_flood_ended.bind(i))
		add_child(ch)
		_channels.append(ch)

## Arm (or re-arm) the kit cadences. Called from reset_preview_state — the host
## invokes that after build and on every reload, so play and headless match.
func reset_preview_state() -> void:
	_phase = "active"
	_swept_count = 0
	_terminal_logged = false
	var gs = _get_game_state()
	var sched = _get_scheduler()
	for i in range(_channels.size()):
		var ch: Channel = _channels[i]
		ch.reset()
		ch.clear_sweep_refractory()
		if gs != null:
			ch.set_sweep(gs, PARTY_IDS, _sweep_landing.bind(i), {
				"party_hp": SWEEP_HP_BITE,
				"refractory": 4.0,
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
			enemy.set_roam(anchor, float(enemy.get_meta("roam_radius", 3.0)))

## The one spatial policy this chunk supplies the kit: a swept member lands MOBILE
## at the section's mouth, spread by identity so a party never stacks one cell.
func _sweep_landing(id: String, _origin: Vector3, i: int) -> Vector3:
	var s0 := float(WASH_SECTIONS[i]["s0"])
	return Vector3(maxf(s0 - 1.5, 1.0), DECK_TOP,
		3.0 + 0.9 * float(absi(hash(id)) % 3))

func _on_swept(_id: String, _i: int) -> void:
	_swept_count += 1
	_show_note("The surge takes one of you. The channel gives nothing back.", 2.4)

func _on_channel_telegraph(i: int) -> void:
	if _phase == "active":
		_set_wash_state(i, "telegraph")

func _on_channel_flood_ended(i: int) -> void:
	if _phase == "active":
		_set_wash_state(i, "idle")

# --- Interactables: the valve, the terminal, the portal ---

func _build_interactables() -> void:
	var valve := _add_interactable(self, "ChannelValve",
		"Hold the near channel closed", Vector3(9.0, DECK_TOP, 0.9),
		"HOLD THE VALVE", "", 1.1, false, 1.6,
		Interactable.InteractableType.INSPECTION)
	valve.consequence_preview = "The near stretch runs quiet for a while — cross the band without the surge."
	_wire_trigger(valve, _on_valve)
	var terminal := _add_interactable(self, "CadenceTerminal",
		"Log the surge cadence", Vector3(16.4, DECK_TOP, 6.6),
		"LOG THE SURGE", "aster", 1.1, false, 1.6,
		Interactable.InteractableType.INSPECTION)
	terminal.consequence_preview = "Aster reads the channel's rhythm — the next surge becomes a number, not a guess."
	_wire_trigger(terminal, _on_terminal)
	# THE WIN goes through the kit's win object — click-gated, downed-guarded,
	# everyone on the pad, ONE atomic party rest (see ExitShelter's header).
	var ring_exit := ExitShelter.new()
	ring_exit.name = "AscentPortal"
	ring_exit.configure_shelter(_get_game_state(), Vector3(22.5, DECK_TOP, 3.0),
		Vector2(2.2, 2.2), PARTY_IDS, "ENTER THE RING", 1.9)
	ring_exit.consequence_preview = "The ring hums. Gather everyone on the pad and step through together."
	ring_exit.rest_completed.connect(_on_ring_rest_completed)
	ring_exit.rest_refused.connect(_on_ring_rest_refused)
	add_child(ring_exit)
	_register_interactable(ring_exit)
	_ring_exit = ring_exit
	_build_lonely_flure()
	var map = get_coord_map()
	warp_interactables_onto_coord_map(map)

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
	flure.configure(gs, (marker as Node3D).global_position, _fauna.keys(), 32.0, 1.4,
		Color(0.95, 0.62, 0.14))
	flure.set_enemy_resolver(_fauna_by_id)
	flure.one_shot = false
	flure.description = "Light the lonely flure"
	flure.tutorial_label = "LIGHT THE FLURE"
	flure.flure_activated.connect(_on_lonely_flure_lit)
	add_child(flure)
	_register_interactable(flure)
	# the library piece at the marker is the flure's BODY; the kit's own glow
	# bulb stays off so no self-drawn primitive reaches the visible scene
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
	var marker := _props_root.find_child("HideCapbage", true, false) if _props_root else null
	if not (marker is Node3D):
		return
	var hide_pos: Vector3 = (marker as Node3D).position
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id):
			continue
		var p: Vector3 = gs.get_position(char_id)
		var near := Vector2(p.x - hide_pos.x, p.z - hide_pos.z).length() < 1.1
		gs.set_character_concealment(char_id,
			gs.CONCEAL_FULL if near else gs.CONCEAL_NONE)

func _process(_delta: float) -> void:
	_tick_concealment()

func headless_process(_delta: float) -> void:
	_tick_concealment()

func _wire_trigger(interactable: Area3D, cb: Callable) -> void:
	if interactable != null and interactable.has_signal("interacted"):
		interactable.connect("interacted", cb)

## The valve speaks the kit's verb: Channel.hold() ends any in-flight flood and
## skips swallowed onsets to the next analytic beat. The view reacts through the
## kit's own signals; this handler adds only the note and the held display.
func _on_valve(_args = null) -> void:
	if _phase != "active" or _channels.is_empty():
		return
	(_channels[0] as Channel).hold(VALVE_HOLD_WINDOW)
	_set_wash_state(0, "held")
	_show_note("// VALVE HELD // the near channel runs quiet", 2.2)
	_set_preview_step("wash_ascent_valve_held")

func _on_terminal(_args = null) -> void:
	_terminal_logged = true
	var soonest := INF
	for ch in _channels:
		soonest = minf(soonest, maxf(0.0, float((ch as Channel).get_state().get("next_onset_in", INF))))
	_show_note("// CADENCE LOGGED // next surge in %.0fs" % soonest, 2.6)
	_set_preview_step("wash_ascent_cadence_logged")

func _on_ring_rest_completed(_members: Array) -> void:
	_phase = "complete"
	for ch in _channels:
		(ch as Channel).reset()
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
	enemy._detection_targets.assign(PARTY_IDS)
	_realized_root.add_child(enemy)
	enemy.game_state = gs
	if not gs.characters.has(enemy.char_id):
		gs.register_character(enemy.char_id, enemy.position, enemy.move_speed,
			{"detection_range": float(enemy.detection_range)})
	enemy.activate()
	enemy.set_meta("roam_anchor", marker.position)
	enemy.set_meta("roam_radius", float(marker.get_meta("roam_radius", 3.0)))
	enemy.set_roam(marker.position, float(marker.get_meta("roam_radius", 3.0)))
	_fauna[enemy.char_id] = enemy

func _fauna_by_id(id: String):
	return _fauna.get(id)

func _on_lonely_flure_lit(pulled: int) -> void:
	_show_note("The flure sings. Nothing answers." if pulled == 0
		else "The flure sings, and something turns toward it.", 2.6)

# --- Preview host contract ---

func get_scene_title() -> String:
	return "Wash Ascent"

func get_scene_help() -> String:
	return "Reach the ring at the far end of the coil. // The channel surges over the front band — the rail line is the safe edge."

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

func get_spawn_positions() -> Dictionary:
	var anchor := Vector3(2.0, DECK_TOP, 3.0)
	var marker := _props_root.find_child("SpawnPlayer", true, false) if _props_root else null
	if marker is Node3D:
		anchor = (marker as Node3D).global_position
	return {
		"aster": anchor,
		"peris": anchor + Vector3(-1.2, 0.0, 1.2),
		"endo": anchor + Vector3(-1.6, 0.0, -1.4),
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
		"terminal_logged": _terminal_logged,
		"fauna": _fauna.size(),
	}
