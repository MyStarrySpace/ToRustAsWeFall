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
const FLOOD_SWEEP_INTERVAL := 0.4  # recheck cadence while a surge is up
const DANGER_Z := 2.0              # authoring-frame band the surge overtops (z < this)
const VALVE_HOLD_WINDOW := 14.0    # how long the bay valve quiets section 0
const SWEEP_STAMINA_COST := 8.0
const PARTY_IDS := ["aster", "peris", "endo"]

var _props_root: Node3D
var _realized_root: Node3D
var _piece_aabbs: Dictionary = {}
var _placed_count := 0
var _unresolved: Array = []
var _wall_cells: Array = []
var _channel_segments: Array = []   # [{node, s, mats: [StandardMaterial3D]}]
var _channel_base_energy: Dictionary = {}

var _cadence_t0 := -1.0
var _flood_counts: Array = []       # onsets fired per section (analytic recurrence index)
var _flooding: Array = []
var _valve_hold_until := -1.0
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
	var flat_yaw := atan2(-flat.basis.x.z, flat.basis.x.x)
	return Transform3D(
		ChannelsArc.basis_at(s)
			* Basis.from_scale(Vector3(1.0, 1.0, stretch))
			* Basis(Vector3.UP, -PI * 0.5 - flat_yaw),
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
		_realize_row(n3, ["water_channel"], int(n3.get_meta("channel_run")),
			{}, "floor", "structure_channel")
	elif n3.has_meta("rail_run"):
		_realize_row(n3, ["railing_run"], int(n3.get_meta("rail_run")),
			_skip_set(n3), "floor", "structure_rail")
	elif n3.has_meta("pipe_chain"):
		_realize_row(n3, ["ball_joint_pipe"], int(n3.get_meta("pipe_chain")),
			{}, "attached", str(n3.get_meta("cluster", "pipes")))

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
		if cluster == "structure_channel":
			_register_channel_segment(piece, flat.origin.x)

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

## Channel segments double as the water-state display: their baked glow strip IS
## the surge telegraph until a modeled water surface piece exists. Materials are
## duplicated per segment at build so each stretch can brighten independently.
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

func _set_channel_band(section: int, mult: float) -> void:
	if section < 0 or section >= WASH_SECTIONS.size():
		return
	var s0 := float(WASH_SECTIONS[section]["s0"])
	var s1 := float(WASH_SECTIONS[section]["s1"])
	for seg in _channel_segments:
		var mid := float(seg["s"]) + _piece_aabb("water_channel").size.x * 0.5
		if mid < s0 or mid > s1:
			continue
		for m in seg["mats"]:
			(m as StandardMaterial3D).emission_energy_multiplier = \
				float(_channel_base_energy.get(m, 1.0)) * mult

func _wash_tag(kind: String, i: int) -> String:
	return "wash_ascent_%s_%d" % [kind, i]

## Arm (or re-arm) the cadence from the current tick. Called from reset_preview_state
## — the host invokes that after build and on every reload, so the scene is live in
## play and headless alike.
func reset_preview_state() -> void:
	_cancel_wash_events()
	_phase = "active"
	_swept_count = 0
	_terminal_logged = false
	_valve_hold_until = -1.0
	var sched = _get_scheduler()
	_cadence_t0 = float(sched.get_current_tick()) if sched != null else 0.0
	_flood_counts = []
	_flooding = []
	for i in range(WASH_SECTIONS.size()):
		_flood_counts.append(0)
		_flooding.append(false)
		_set_channel_band(i, 1.0)
		_schedule_section(i)

func _cancel_wash_events() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	for i in range(WASH_SECTIONS.size()):
		for kind in ["telegraph", "onset", "off", "sweep", "valve"]:
			sched.cancel_tag(_wash_tag(kind, i))

## The analytic recurrence: onset_k = t0 + grace + phase + period*k. The next onset
## for a section is always computable from data — never discovered by sampling.
func _section_next_onset(i: int) -> float:
	var sec: Dictionary = WASH_SECTIONS[i]
	return _cadence_t0 + WASH_GRACE + float(sec["phase"]) \
		+ float(sec["period"]) * float(_flood_counts[i])

func _schedule_section(i: int) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	var onset := _section_next_onset(i)
	if _valve_hold_until > onset and i == 0:
		return                                     # the valve owns this window; re-armed on release
	var now := float(sched.get_current_tick())
	var lead := maxf(0.0, onset - TELEGRAPH_LEAD - now)
	sched.cancel_tag(_wash_tag("telegraph", i))
	sched.schedule_after(lead, _telegraph_section.bind(i), _wash_tag("telegraph", i))
	sched.schedule_after(maxf(0.0, onset - now), _flood_onset.bind(i), _wash_tag("onset", i))

func _telegraph_section(i: int) -> void:
	if _phase != "active":
		return
	_set_channel_band(i, 2.4)

func _flood_onset(i: int) -> void:
	if _phase != "active":
		return
	_flooding[i] = true
	_flood_counts[i] += 1
	_set_channel_band(i, 4.5)
	_sweep_section(i)
	var sched = _get_scheduler()
	if sched == null:
		return
	var dur := float(WASH_SECTIONS[i]["dur"])
	var rechecks := ceili(dur / FLOOD_SWEEP_INTERVAL)
	for k in range(1, rechecks + 1):
		sched.schedule_after(FLOOD_SWEEP_INTERVAL * float(k), _sweep_section.bind(i),
			_wash_tag("sweep", i))
	# Self-reschedule without cancelling the in-dispatch tag (scheduler bookkeeping law).
	sched.schedule_after(dur, _flood_off.bind(i), _wash_tag("off", i))

func _flood_off(i: int) -> void:
	if i < _flooding.size():
		_flooding[i] = false
	_set_channel_band(i, 1.0)
	_schedule_section(i)

## The sweep: anyone standing in the surge band of a live section is carried back
## to the section's mouth — fail-forward (lose the crossing, not the run), priced
## in stamina, and MOBILE on landing. Pure data-layer; the warp renders it.
func _sweep_section(i: int) -> void:
	if _phase != "active" or i >= _flooding.size() or not _flooding[i]:
		return
	var gs = _get_game_state()
	if gs == null:
		return
	var s0 := float(WASH_SECTIONS[i]["s0"])
	var s1 := float(WASH_SECTIONS[i]["s1"])
	var caught: Array = []
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id):
			continue
		var p := _get_character_position(char_id)
		if p.x >= s0 and p.x <= s1 and p.z < DANGER_Z:
			caught.append(char_id)
	if caught.is_empty():
		return
	for idx in range(caught.size()):
		var char_id: String = caught[idx]
		gs.command_stop(char_id)
		gs.snap_character_to(char_id,
			Vector3(maxf(s0 - 1.5, 1.0), DECK_TOP, 3.2 + 0.9 * float(idx)))
		_adjust_character_stat(char_id, "stamina", -SWEEP_STAMINA_COST)
	_swept_count += 1
	_show_note("The surge takes %s. The channel gives nothing back." %
		("them" if caught.size() > 1 else "one of you"), 2.4)

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
	var portal := _add_interactable(self, "AscentPortal",
		"Step through the ring", Vector3(22.5, DECK_TOP, 3.0),
		"ENTER THE RING", "", 1.4, true, 1.9,
		Interactable.InteractableType.INSPECTION)
	portal.consequence_preview = "The ring hums. Wherever it goes, it is not here."
	_wire_trigger(portal, _on_portal)
	var map = get_coord_map()
	warp_interactables_onto_coord_map(map)

func _wire_trigger(interactable: Area3D, cb: Callable) -> void:
	if interactable != null and interactable.has_signal("interacted"):
		interactable.connect("interacted", cb)

func _on_valve(_args = null) -> void:
	var sched = _get_scheduler()
	if sched == null or _phase != "active":
		return
	var now := float(sched.get_current_tick())
	_valve_hold_until = now + VALVE_HOLD_WINDOW
	for kind in ["telegraph", "onset", "sweep", "off"]:
		sched.cancel_tag(_wash_tag(kind, 0))
	if 0 < _flooding.size():
		_flooding[0] = false
	_set_channel_band(0, 0.5)
	# Recurrence index advances past every onset the hold swallows, so release
	# re-arms at the next analytic beat rather than firing a stale backlog.
	while _section_next_onset(0) < _valve_hold_until:
		_flood_counts[0] += 1
	sched.schedule_after(VALVE_HOLD_WINDOW, _on_valve_release, _wash_tag("valve", 0))
	_show_note("// VALVE HELD // the near channel runs quiet", 2.2)
	_set_preview_step("wash_ascent_valve_held")

func _on_valve_release() -> void:
	_valve_hold_until = -1.0
	_set_channel_band(0, 1.0)
	_schedule_section(0)
	if _phase == "active":
		_show_note("// PRESSURE RETURNING // the channel is live again", 2.0)

func _on_terminal(_args = null) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	_terminal_logged = true
	var now := float(sched.get_current_tick())
	var soonest := INF
	for i in range(WASH_SECTIONS.size()):
		soonest = minf(soonest, maxf(0.0, _section_next_onset(i) - now))
	_show_note("// CADENCE LOGGED // next surge in %.0fs" % soonest, 2.6)
	_set_preview_step("wash_ascent_cadence_logged")

func _on_portal(_args = null) -> void:
	_phase = "complete"
	_cancel_wash_events()
	_show_note("The ring takes you. The coil keeps climbing without you.", 3.0)
	_set_preview_step("wash_ascent_complete")

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
	var sched = _get_scheduler()
	var now := float(sched.get_current_tick()) if sched != null else 0.0
	var onsets: Array = []
	for i in range(WASH_SECTIONS.size()):
		onsets.append(_section_next_onset(i) - now)
	return {
		"placed": _placed_count,
		"unresolved": _unresolved.duplicate(),
		"wall_cells": _wall_cells.size(),
		"phase": _phase,
		"cadence_t0": _cadence_t0,
		"next_onsets_in": onsets,
		"swept_count": _swept_count,
		"valve_hold_until": _valve_hold_until,
		"terminal_logged": _terminal_logged,
	}
