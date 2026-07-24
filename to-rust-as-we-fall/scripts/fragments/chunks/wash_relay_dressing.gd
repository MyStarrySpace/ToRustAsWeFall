class_name WashRelayDressing
extends RefCounted

## The concept-plate detail pass for the wash_relay channels spiral, built SURVEY-FIRST
## (docs/SURVEY_REBUILD.md method). Every pass below reads THE SURVEY tables in this header;
## every number there traces to either a measured datum (channels_arc.gd / channels.glb /
## wash_relay.tres) or a plate ratio (the channels concept plate: central drum unit D,
## deck annulus ~3.2 D across, worker height h ~ D/14 — our drum is scale-compressed, see
## the reconciliation note). All geometry is COSMETIC: no collision, no walkable change,
## no scheduler logic. Anything that must react to the wash cadence (the rim waterfalls)
## is DRIVEN by the chunk's existing splash-intensity ease — dressing never keeps time.
##
## RECONCILIATION (plate -> helix). The plate compresses the 1.27-turn ascending helix
## (ChannelsArc: R0 11, deck lane ±4 -> radius 7..15, y 1 -> 12.6) into one radial annulus.
## Mapping rules used by the survey:
##   - plate "central drum"      -> the Downpipe axis (r 0.8 in the GLB) fattened to a shell
##     at DRUM_R, NECKED over the pressure-room band (the room occupies radius 0.6..5.0 at
##     s 21..26.3, y ~3.6..7.4) — the visible break IS the story's "broken coil".
##   - plate "deck annulus"      -> the helix deck ribbon; per-element (s, lane, y_off).
##   - plate "sector gates"      -> stencil boards at each section threshold (the GLB set
##     pieces are the gates; boards carry the wayfinding text).
##   - plate "shaft walls"       -> free-standing wall panels at WALL_LANE, one behind each
##     section EXCEPT the sluice (its outer-pipe transit bulge reaches radius ~24 there).
##   - plate "rim waterfalls"    -> per-section outfall sheets on the outer rim, intensity
##     slaved to that section's flood/telegraph state (render what you simulate).
##   - plate flure outcrop / curecumin ledge -> the two INWARD story-beat ledges the chunk
##     authors as walkable spurs (grid + interactables live in wash_relay_chunk.gd; this
##     file builds only their planks/stems/ring visuals).
##   - plate worker figures / walkable drum top -> CUT (contradict the party frame and the
##     no-new-routes law).

# --- THE SURVEY: datums -----------------------------------------------------------------
const DECK_OUT_LANE := 4.0        # walkable rim (measured: FLOOR_Z_HALF)
const RIM_LANE := 4.45            # dressing strip just past the rim (outside walkable cells)
const INNER_RIM_LANE := -4.4      # inner dressing strip (walkable cells end at lane -4)
const S_MIN := -1.0               # floor_min_x (wash_relay.tres)
const S_MAX := 87.0               # floor_max_x

# Central drum (plate: unit D; courses 0.12 D; portholes 0.08 D; big wheel 0.14 D; rim
# water 0.1 D below top). Our D = 2 * DRUM_R = 5.6 — radius chosen to clear the flure/pad
# ledges (inner edge radius 3.6) by 0.8 and the pressure room's y-band by necking.
const DRUM_R := 3.2
const DRUM_BOTTOM := -2.0         # meets the well floor (GLB WellFloor top -1.4)
const DRUM_NECK_Y0 := 3.0         # lower shell top — below the pressure room band (y 3.6+)
const DRUM_NECK_Y1 := 7.6         # upper shell base — above the room pylons (y ~7.4)
const DRUM_TOP := 13.8            # just above the deck's final ascent (y 12.6 at s 87)
const DRUM_COURSE := 1.15         # rivet-band spacing ~ 0.2 D (plate 0.12 D, widened so the
                                  # bands read at our compressed drum scale)
const PORTHOLE_R := 0.24          # plate 0.08 D ≈ 0.45 dia
const WHEEL_R := 0.42             # the big spoked window, plate ~0.14 D
const WHEEL_FACE_S := 3.0         # faces the start shelter (angle = s * KTHETA)

# Under-deck service pipes (plate: pipe runs 0.05-0.08 D thick following the deck underside).
const PIPE_LANES := [2.6, 3.4]
const PIPE_DROPS := [-0.85, -1.3]
const PIPE_THICK := 0.34
const PIPE_STEP := 3.0            # one segment per 3 flat units (chord vs arc gap covered by 1.22x)

# Rim waterfalls (plate: fall width = its channel, drop ~0.6-1.0 D before fading; here they
# hang FALL_DROP below the deck edge and pulse with the section's flood intensity).
const FALL_LANE := 4.55
const FALL_DROP := 5.2
const FALL_SEG := 2.0             # mirrors WATER_SEG so sheets track the flood segmentation

# Shaft wall accents (plate: walls 1.5-2.5 D behind the rim, mostly swallowed by gloom).
# A first pass built full 16.5-tall panels and they read as a black curtain occluding the
# deck from every exterior angle — reconciled DOWN to sparse pilaster FINS: short vertical
# depth cues at lane 12 (radius 23, beyond the branch tips at 21 and the drain ledge at
# 20.3), skipping the sluice tunnel's outer bulge (s ~33..47, its pipe reaches radius ~24).
const WALL_LANE := 12.0
const WALL_FIN_H := 9.0
const WALL_FIN_W := 1.7
const WALL_SKIP_S := [33.0, 47.0]

# Story-beat ledges (chunk-owned walkable spurs; the chunk's grid regions must match).
const FLURE_LEDGE_S := 62.5       # the gap after the lure section — you just used a flure
                                  # that answered; this one has no one left to call
const FLURE_LEDGE_SPAN := 1.5     # s half-extent 0.75 each way of plank coverage
const LEDGE_LANE_C := -5.45       # plank centre: covers lane -3.5..-7.4 (neck overlaps deck)
const LEDGE_LANE_W := 3.9
const FLURE_POS_LANE := -6.4
const PAD_LEDGE_S := 1.6          # the start-shelter ledge over the well pool
const PAD_POS_LANE := -6.2

# Palette (roles traced to the plate, constrained by house rules: terminal green #5ce87f is
# the standard emissive; water keeps the existing channels_water family; flure stays the
# in-level species gold-orange, NOT the plate's pink — species consistency ruling).
const COL_IRON := Color(0.13, 0.14, 0.17)
const COL_IRON_DK := Color(0.09, 0.10, 0.12)
const COL_RUST := Color(0.38, 0.20, 0.12)
const COL_WOOD := Color(0.36, 0.26, 0.14)
const COL_TERM_GREEN := Color(0.36, 0.91, 0.5)     # #5ce87f
const COL_WATER_EM := Color(0.3, 0.75, 0.95)
const COL_GOLD := Color(0.95, 0.75, 0.15)          # Curecumin turmeric
const COL_FLURE := Color(1.0, 0.55, 0.12)          # in-level flure gold-orange
const COL_TEAL_FLORA := Color(0.2, 0.85, 0.75)
const COL_STENCIL := Color(0.82, 0.8, 0.72)

static var _mat_cache: Dictionary = {}

# --- Entry ------------------------------------------------------------------------------

## Build every dressing pass under a named root (a Node3D child -> survives the chunk's
## hide_flat_graybox, which only hides DIRECT MeshInstance3D children). Returns the handle
## dictionary the chunk keeps: {"root": Node3D, "falls": Array per section, "foam": Array}.
## `sections` is the chunk's SECTIONS array (x0/x1/type dictionaries).
static func build(chunk: Node3D, sections: Array) -> Dictionary:
	var root := Node3D.new()
	root.name = "Dressing"
	chunk.add_child(root)
	_build_drum(root)
	_build_underdeck(root)
	_build_rails(root)
	var falls := _build_falls(root, sections)
	_build_signage(root, sections)
	_build_wall_panels(root, sections)
	_build_props(root)
	_build_flora(root)
	_build_vine(root)
	_build_beat_ledges(root)
	return {"root": root, "falls": falls["sheets"], "foam": falls["foam"], "mats": falls["mats"]}

## Slave one section's outfall to the chunk's splash intensity (called from the existing
## per-frame splash ease — dressing keeps no clock of its own). intensity 0..1.
static func drive_falls(dressing: Dictionary, section: int, intensity: float) -> void:
	var mats: Array = dressing.get("mats", [])
	var sheets: Array = dressing.get("falls", [])
	var foam: Array = dressing.get("foam", [])
	if section >= mats.size():
		return
	var vis := intensity > 0.04
	for mi in sheets[section]:
		if is_instance_valid(mi):
			mi.visible = vis
	for mi in foam[section]:
		if is_instance_valid(mi):
			mi.visible = intensity > 0.45
	var m: StandardMaterial3D = mats[section]
	if m != null:
		m.alpha_scissor_threshold = lerpf(0.92, 0.3, clampf(intensity, 0.0, 1.0))
		m.emission_energy_multiplier = 2.6 * intensity

static func reset_falls(dressing: Dictionary) -> void:
	for i in range(int(dressing.get("mats", []).size())):
		drive_falls(dressing, i, 0.0)

# --- Placement helpers (author FLAT (s, lane), warp through ChannelsArc) -----------------

static func _xf(s: float, lane: float, y_off := 0.0) -> Transform3D:
	var xf := Transform3D(ChannelsArc.basis_at(s), ChannelsArc.arc_pos(s, lane))
	xf.origin += xf.basis.y * y_off
	return xf

## size is authored deck-local: (lane extent, height, s extent) — the chunk convention.
static func _wbox(parent: Node3D, s: float, lane: float, size: Vector3,
		mat: Material, y_off := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.transform = _xf(s, lane, y_off)
	parent.add_child(mi)
	return mi

static func _mat(key: String, color: Color, emission := Color.BLACK, energy := 0.0,
		roughness := 0.86, metallic := 0.0) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	_mat_cache[key] = m
	return m

static func _world_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

# --- P1: the central drum (the plate's hero object) --------------------------------------

static func _build_drum(root: Node3D) -> void:
	var drum := Node3D.new()
	drum.name = "Drum"
	root.add_child(drum)
	var shell := _mat("drum", Color(0.19, 0.2, 0.24), Color.BLACK, 0.0, 0.72, 0.45)
	var band := _mat("drum_band", Color(0.11, 0.115, 0.14), Color.BLACK, 0.0, 0.66, 0.5)
	var rust := _mat("drum_rust", COL_RUST)
	# Two shells with the broken-coil neck between them (reconciliation: the pressure room
	# lives inside the drum volume at y ~3.6..7.4 — the shell NEVER covers that band).
	for seg in [[DRUM_BOTTOM, DRUM_NECK_Y0], [DRUM_NECK_Y1, DRUM_TOP]]:
		var h: float = seg[1] - seg[0]
		var cyl := CylinderMesh.new()
		cyl.top_radius = DRUM_R
		cyl.bottom_radius = DRUM_R
		cyl.height = h
		cyl.radial_segments = 24
		_world_mesh(drum, cyl, shell, Vector3(0.0, (seg[0] + seg[1]) * 0.5, 0.0))
		# rivet-band courses (plate: horizontal plate courses with rivet lines)
		var y := float(seg[0]) + DRUM_COURSE
		while y < seg[1] - 0.2:
			var ring := TorusMesh.new()
			ring.inner_radius = DRUM_R - 0.04
			ring.outer_radius = DRUM_R + 0.1
			_world_mesh(drum, ring, band, Vector3(0.0, y, 0.0), Vector3.ZERO, Vector3(1.0, 0.55, 1.0))
			y += DRUM_COURSE
	# The neck: flanges + exposed coil ribs (the "broken coil" the help text names — the
	# skinny GLB Downpipe stays visible between them).
	for fy in [DRUM_NECK_Y0, DRUM_NECK_Y1]:
		var flange := CylinderMesh.new()
		flange.top_radius = 1.5
		flange.bottom_radius = 1.5
		flange.height = 0.34
		flange.radial_segments = 16
		_world_mesh(drum, flange, band, Vector3(0.0, fy, 0.0))
	for k in range(4):
		var ang := TAU * (float(k) + 0.5) / 4.0
		var rib := BoxMesh.new()
		rib.size = Vector3(0.22, DRUM_NECK_Y1 - DRUM_NECK_Y0 - 0.4, 0.22)
		_world_mesh(drum, rib, rust, Vector3(cos(ang) * 1.05, (DRUM_NECK_Y0 + DRUM_NECK_Y1) * 0.5, sin(ang) * 1.05))
	# Portholes (plate: circular portholes on the courses), dark teal glass, radial stubs.
	var glass := _mat("porthole", Color(0.05, 0.12, 0.14), Color(0.14, 0.45, 0.5), 0.7)
	for level in [[0.9, 3], [8.7, 4], [11.2, 4]]:
		var count: int = level[1]
		for k in range(count):
			var ang := TAU * float(k) / float(count) + 0.35
			var stub := CylinderMesh.new()
			stub.top_radius = PORTHOLE_R
			stub.bottom_radius = PORTHOLE_R
			stub.height = 0.3
			stub.radial_segments = 12
			_world_mesh(drum, stub, glass,
				Vector3(cos(ang) * DRUM_R, float(level[0]), sin(ang) * DRUM_R),
				Vector3(PI * 0.5, -ang, 0.0))
	# The big spoked wheel-window, facing the start shelter (plate's hero detail).
	var wang := WHEEL_FACE_S * ChannelsArc.KTHETA
	var wpos := Vector3(cos(wang) * DRUM_R, 1.7, sin(wang) * DRUM_R)
	var wheel := TorusMesh.new()
	wheel.inner_radius = WHEEL_R - 0.09
	wheel.outer_radius = WHEEL_R + 0.06
	_world_mesh(drum, wheel, band, wpos, Vector3(PI * 0.5 - 0.0, -wang + PI * 0.5, 0.0))
	for k in range(4):
		var spoke := BoxMesh.new()
		spoke.size = Vector3(0.07, WHEEL_R * 2.0 - 0.1, 0.07)
		_world_mesh(drum, spoke, band, wpos,
			Vector3(0.0, -wang, 0.0) + Vector3(0.0, 0.0, TAU * float(k) / 8.0))
	# Terminal-green status panels (the only standard emissive) on both shells.
	var term := _mat("term", Color(0.05, 0.09, 0.06), COL_TERM_GREEN, 1.6)
	for pan in [[1.6, 1.9], [2.4, 9.6], [4.4, 12.0], [5.4, 2.2]]:
		var ang: float = pan[0]
		var p := BoxMesh.new()
		p.size = Vector3(0.7, 0.5, 0.08)
		_world_mesh(drum, p, term,
			Vector3(cos(ang) * (DRUM_R + 0.02), float(pan[1]), sin(ang) * (DRUM_R + 0.02)),
			Vector3(0.0, -ang + PI * 0.5, 0.0))
	# Valve wheels bolted to the shell on stub pipes (plate: shell valve wheels).
	for vv in [[0.7, 2.2], [3.6, 10.4]]:
		var ang: float = vv[0]
		var base := Vector3(cos(ang) * DRUM_R, float(vv[1]), sin(ang) * DRUM_R)
		var stub := CylinderMesh.new()
		stub.top_radius = 0.09
		stub.bottom_radius = 0.09
		stub.height = 0.42
		_world_mesh(drum, stub, rust, base, Vector3(PI * 0.5, -ang, 0.0))
		var vw := TorusMesh.new()
		vw.inner_radius = 0.16
		vw.outer_radius = 0.3
		_world_mesh(drum, vw, rust,
			base + Vector3(cos(ang) * 0.24, 0.0, sin(ang) * 0.24),
			Vector3(PI * 0.5, -ang, 0.0))
	# Top rim: railing ring + posts + the still reservoir surface ~0.1 D below the rim.
	var rail := TorusMesh.new()
	rail.inner_radius = DRUM_R - 0.06
	rail.outer_radius = DRUM_R + 0.06
	_world_mesh(drum, rail, band, Vector3(0.0, DRUM_TOP + 0.85, 0.0))
	for k in range(8):
		var ang := TAU * float(k) / 8.0
		var post := BoxMesh.new()
		post.size = Vector3(0.08, 0.85, 0.08)
		_world_mesh(drum, post, band,
			Vector3(cos(ang) * DRUM_R, DRUM_TOP + 0.42, sin(ang) * DRUM_R))
	var water := CylinderMesh.new()
	water.top_radius = DRUM_R - 0.18
	water.bottom_radius = DRUM_R - 0.18
	water.height = 0.06
	var wmat := _mat("drum_water", Color(0.04, 0.12, 0.16), Color(0.1, 0.35, 0.4), 0.5, 0.2)
	_world_mesh(drum, water, wmat, Vector3(0.0, DRUM_TOP - 0.55, 0.0))

# --- P2: under-deck service pipes --------------------------------------------------------

static func _build_underdeck(root: Node3D) -> void:
	var pipes := Node3D.new()
	pipes.name = "UnderdeckPipes"
	root.add_child(pipes)
	var pm := _mat("pipe", Color(0.16, 0.14, 0.13), Color.BLACK, 0.0, 0.7, 0.5)
	var bm := _mat("bracket", COL_RUST)
	for pi in range(PIPE_LANES.size()):
		var lane: float = PIPE_LANES[pi]
		var drop: float = PIPE_DROPS[pi]
		var s := S_MIN
		while s < S_MAX:
			_wbox(pipes, s + PIPE_STEP * 0.5, lane,
				Vector3(PIPE_THICK, PIPE_THICK, PIPE_STEP * 1.22), pm, drop)
			s += PIPE_STEP
	# hanger brackets tying the runs to the deck rim understructure
	var s := S_MIN + 2.0
	while s < S_MAX:
		_wbox(pipes, s, 3.9, Vector3(0.16, 0.7, 0.16), bm, -0.55)
		s += 9.0

# --- P3: rim rails (only where nothing exits outward — every branch/transit mouth stays open)

static func _build_rails(root: Node3D) -> void:
	var rails := Node3D.new()
	rails.name = "RimRails"
	root.add_child(rails)
	var rm := _mat("rail", COL_IRON_DK, Color.BLACK, 0.0, 0.6, 0.5)
	# start apron, the pressure gap's outer rim, and the summit approach
	for span in [[-0.5, 4.6], [19.8, 21.4], [84.4, 86.6]]:
		var s0: float = span[0]
		var s1: float = span[1]
		var n := maxi(2, int(ceil((s1 - s0) / 1.6)))
		for k in range(n + 1):
			var s := lerpf(s0, s1, float(k) / float(n))
			_wbox(rails, s, RIM_LANE, Vector3(0.07, 0.9, 0.07), rm, 0.45)
		_wbox(rails, (s0 + s1) * 0.5, RIM_LANE, Vector3(0.05, 0.05, s1 - s0), rm, 0.88)

# --- P4: rim outfall sheets (render what you simulate: slaved to each section's flood) ----

static func _build_falls(root: Node3D, sections: Array) -> Dictionary:
	var falls := Node3D.new()
	falls.name = "RimFalls"
	root.add_child(falls)
	var sheets: Array = []
	var foam: Array = []
	var mats: Array = []
	for i in range(sections.size()):
		var x0 := float(sections[i]["x0"])
		var x1 := float(sections[i]["x1"])
		var m := _fall_material()
		var s_sheets: Array = []
		var s_foam: Array = []
		var n := maxi(1, int(ceil((x1 - x0) / FALL_SEG)))
		for k in range(n):
			var sc := lerpf(x0, x1, (float(k) + 0.5) / float(n))
			var sheet := _wbox(falls, sc, FALL_LANE,
				Vector3(0.14, FALL_DROP, (x1 - x0) / float(n) * 1.06), m, -FALL_DROP * 0.5 - 0.1)
			sheet.visible = false
			s_sheets.append(sheet)
			var lip := _wbox(falls, sc, FALL_LANE - 0.12,
				Vector3(0.3, 0.16, (x1 - x0) / float(n) * 1.02),
				_mat("foam", Color(0.8, 0.95, 1.0), COL_WATER_EM, 1.8), 0.14)
			lip.visible = false
			s_foam.append(lip)
		sheets.append(s_sheets)
		foam.append(s_foam)
		mats.append(m)
	return {"sheets": sheets, "foam": foam, "mats": mats}

## Per-section INSTANCE (drive_falls animates threshold/energy independently). Streaky
## alpha texture + ALPHA_SCISSOR — never alpha BLEND (the preview drops the blended pass;
## the overlay-materials law).
static func _fall_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.85, 0.95)
	m.albedo_texture = _streak_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.92
	m.emission_enabled = true
	m.emission = COL_WATER_EM
	m.emission_energy_multiplier = 0.0
	m.roughness = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static func _streak_texture() -> ImageTexture:
	if _mat_cache.has("streak_tex"):
		return _mat_cache["streak_tex"]
	var img := Image.create(48, 96, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4727
	for x in range(48):
		var col := 0.35 + 0.65 * rng.randf()
		if rng.randf() < 0.2:
			col = 0.0
		for y in range(96):
			var a := clampf(col + (rng.randf() - 0.5) * 0.35, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	_mat_cache["streak_tex"] = tex
	return tex

# --- P5: signage (diegetic wayfinding boards; goal + danger only, never the solve) --------

const SECTION_TAGS := {
	"flush": "FLUSH", "current": "CURRENT", "jet": "JET", "plate": "PLATE",
	"sluice": "SLUICE", "patrol": "PATROL", "lure": "LURE", "basin": "BASIN",
	"double_plate": "PLATES",
}

static func _build_signage(root: Node3D, sections: Array) -> void:
	var signs := Node3D.new()
	signs.name = "Signage"
	root.add_child(signs)
	for i in range(sections.size()):
		var tag: String = SECTION_TAGS.get(str(sections[i]["type"]), "")
		_board(signs, float(sections[i]["x0"]) - 0.6, RIM_LANE,
			"S-%02d %s" % [i + 1, tag], COL_STENCIL, true)
	_board(signs, 4.6, INNER_RIM_LANE, "^ FLOW UP", COL_TERM_GREEN, false)
	for mid in [12.5, 28.5, 54.5, 62.5, 72.5]:
		_board(signs, float(mid) - 1.9, RIM_LANE, "MAINTENANCE", COL_STENCIL, true)
	_board(signs, 78.2, RIM_LANE, "CAUTION // DRAIN", Color(0.95, 0.6, 0.2), true)
	_board(signs, 61.6, INNER_RIM_LANE, "CAUTION // LEDGE", Color(0.95, 0.6, 0.2), false)
	_board(signs, 2.9, INNER_RIM_LANE, "CURECUMIN ROUTE", COL_GOLD, false)

## A mounted sign: post + board + flush (non-billboard) stencil text facing the deck.
static func _board(parent: Node3D, s: float, lane: float, text: String,
		tint: Color, face_inward: bool) -> void:
	var bm := _mat("board", COL_IRON_DK, Color.BLACK, 0.0, 0.8, 0.3)
	_wbox(parent, s, lane, Vector3(0.07, 1.05, 0.07), bm, 0.5)
	var w := maxf(1.15, 0.16 * float(text.length()) + 0.35)
	_wbox(parent, s, lane, Vector3(0.07, 0.5, w), bm, 1.28)
	var label := Label3D.new()
	label.text = text
	label.modulate = tint
	label.pixel_size = 0.006
	label.font_size = 40
	label.outline_size = 6
	var xf := _xf(s, lane, 1.28)
	xf.origin += xf.basis.x * (-0.06 if face_inward else 0.06)
	label.transform = xf
	# Label3D faces its local +Z; swing it to face across the deck (radially).
	label.rotate_object_local(Vector3.UP, PI * 0.5 if face_inward else -PI * 0.5)
	parent.add_child(label)

# --- P6: shaft wall panels ---------------------------------------------------------------

static func _build_wall_panels(root: Node3D, _sections: Array) -> void:
	var wall := Node3D.new()
	wall.name = "ShaftWall"
	root.add_child(wall)
	var wm := _mat("wall", Color(0.075, 0.085, 0.1), Color.BLACK, 0.0, 0.92)
	var pm := _mat("wall_pipe", Color(0.12, 0.11, 0.11), Color.BLACK, 0.0, 0.75, 0.4)
	var tm := _mat("term", Color(0.05, 0.09, 0.06), COL_TERM_GREEN, 1.6)
	var idx := 0
	var s := 4.0
	while s <= 84.0:
		if s < WALL_SKIP_S[0] or s > WALL_SKIP_S[1]:
			_wbox(wall, s, WALL_LANE, Vector3(0.5, WALL_FIN_H, WALL_FIN_W), wm, 1.0)
			_wbox(wall, s + 0.9, WALL_LANE - 0.35,
				Vector3(0.26, WALL_FIN_H - 1.2, 0.26), pm, 0.8)
			if idx % 3 == 1:
				_wbox(wall, s - 0.6, WALL_LANE - 0.4, Vector3(0.1, 0.6, 0.9), tm, 1.6)
			idx += 1
		s += 7.3

# --- P7: props (gap-rim clutter: crates, barrels, a tool shrine at each shelter) ----------

static func _build_props(root: Node3D) -> void:
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	var cm := _mat("crate", Color(0.22, 0.18, 0.12))
	var dm := _mat("crate_dk", Color(0.16, 0.14, 0.1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 727
	for spot in [[12.5, INNER_RIM_LANE], [28.5, INNER_RIM_LANE], [54.5, INNER_RIM_LANE], [72.5, INNER_RIM_LANE]]:
		var s := float(spot[0])
		var lane := float(spot[1])
		for k in range(2 + rng.randi() % 2):
			var sz := 0.42 + rng.randf() * 0.3
			_wbox(props, s + rng.randf_range(-0.9, 0.9), lane - rng.randf_range(0.0, 0.25),
				Vector3(sz, sz, sz), cm if k % 2 == 0 else dm, sz * 0.5)
	var bm := _mat("barrel", Color(0.2, 0.16, 0.2), Color.BLACK, 0.0, 0.7, 0.4)
	for k in range(2):
		var barrel := CylinderMesh.new()
		barrel.top_radius = 0.26
		barrel.bottom_radius = 0.26
		barrel.height = 0.66
		var mi := MeshInstance3D.new()
		mi.mesh = barrel
		mi.material_override = bm
		mi.transform = _xf(85.3 + float(k) * 0.7, RIM_LANE - 0.1, 0.33)
		props.add_child(mi)
	# tool shrines: small left-behind stacks at the two shelters (plate: worker traces)
	for shrine_s in [1.2, 84.6]:
		_wbox(props, float(shrine_s), RIM_LANE - 0.05, Vector3(0.5, 0.18, 0.7), dm, 0.09)
		_wbox(props, float(shrine_s) + 0.15, RIM_LANE - 0.05, Vector3(0.3, 0.16, 0.34), cm, 0.26)
		_wbox(props, float(shrine_s) - 0.1, RIM_LANE + 0.12, Vector3(0.1, 0.36, 0.1),
			_mat("shrine_glow", Color(0.1, 0.14, 0.1), COL_TERM_GREEN, 0.9), 0.18)

# --- P8: flora accents (teal sprigs + moss pads on the rims) -----------------------------

static func _build_flora(root: Node3D) -> void:
	var flora := Node3D.new()
	flora.name = "FloraAccents"
	root.add_child(flora)
	var sprig := _mat("sprig", Color(0.08, 0.2, 0.18), COL_TEAL_FLORA, 1.3)
	var moss := _mat("moss", Color(0.07, 0.16, 0.14), Color(0.1, 0.4, 0.34), 0.35)
	var rng := RandomNumberGenerator.new()
	rng.seed = 733
	for spot in [[10.0, INNER_RIM_LANE], [33.0, INNER_RIM_LANE], [58.0, INNER_RIM_LANE], [76.0, INNER_RIM_LANE], [21.0, RIM_LANE], [68.0, RIM_LANE]]:
		var s := float(spot[0])
		var lane := float(spot[1])
		var pad := CylinderMesh.new()
		pad.top_radius = 0.55
		pad.bottom_radius = 0.6
		pad.height = 0.05
		var mi := MeshInstance3D.new()
		mi.mesh = pad
		mi.material_override = moss
		mi.transform = _xf(s, lane, 0.02)
		flora.add_child(mi)
		for k in range(3):
			var h := 0.4 + rng.randf() * 0.45
			_wbox(flora, s + rng.randf_range(-0.35, 0.35), lane + rng.randf_range(-0.2, 0.2),
				Vector3(0.07, h, 0.07), sprig, h * 0.5)

# --- P9: the hanging vine accent (thickens the existing CBrope drop into the plate's vine)

static func _build_vine(root: Node3D) -> void:
	var vine := Node3D.new()
	vine.name = "VineAccent"
	root.add_child(vine)
	var vm := _mat("vine", Color(0.15, 0.13, 0.08))
	var lm := _mat("vine_leaf", Color(0.1, 0.22, 0.16), COL_TEAL_FLORA, 0.8)
	# GLB CBrope_line hangs at world (1.98, 8.5..12.7, 8.26); braid two strands around it
	# and run leaves down the drop.
	var base := Vector3(1.98, 0.0, 8.26)
	for strand in range(2):
		var off := 0.09 if strand == 0 else -0.09
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.045
		cyl.bottom_radius = 0.045
		cyl.height = 5.4
		_world_mesh(vine, cyl, vm, base + Vector3(off, 10.0, -off),
			Vector3(0.06 * (1.0 if strand == 0 else -1.0), 0.0, 0.05))
	for k in range(5):
		var leaf := BoxMesh.new()
		leaf.size = Vector3(0.26, 0.05, 0.14)
		var side := 1.0 if k % 2 == 0 else -1.0
		_world_mesh(vine, leaf, lm,
			base + Vector3(0.16 * side, 8.0 + 1.15 * float(k), 0.05 * side),
			Vector3(0.0, 0.5 * float(k), 0.28 * side))

# --- P10: story-beat ledge visuals (grid + interactables live in the chunk) --------------

static func _build_beat_ledges(root: Node3D) -> void:
	var beats := Node3D.new()
	beats.name = "BeatLedges"
	root.add_child(beats)
	var plank := _mat("plank", COL_WOOD)
	var rib := _mat("ledge_rib", COL_IRON_DK, Color.BLACK, 0.0, 0.7, 0.4)
	var stem := _mat("dead_stem", Color(0.14, 0.1, 0.07))
	# The lonely flure's outcrop: planks + two support ribs + its dead flure bed.
	_wbox(beats, FLURE_LEDGE_S, LEDGE_LANE_C,
		Vector3(LEDGE_LANE_W, 0.24, FLURE_LEDGE_SPAN * 2.0), plank, -0.13)
	for off in [-0.9, 0.9]:
		_wbox(beats, FLURE_LEDGE_S + float(off), LEDGE_LANE_C - 0.4,
			Vector3(LEDGE_LANE_W * 0.7, 0.16, 0.2), rib, -0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	for k in range(6):
		var h := 0.35 + rng.randf() * 0.5
		_wbox(beats, FLURE_LEDGE_S + rng.randf_range(-0.7, 0.7),
			FLURE_POS_LANE + rng.randf_range(-0.55, 0.55),
			Vector3(0.05, h, 0.05), stem, h * 0.5 - 0.02)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.62, 0.25)
	warm.light_energy = 1.2
	warm.omni_range = 6.0
	warm.position = ChannelsArc.arc_pos(FLURE_LEDGE_S, FLURE_POS_LANE) + Vector3(0.0, 1.0, 0.0)
	beats.add_child(warm)
	# The curecumin pad's ledge over the well pool: planks + the dormant gold ring bed.
	_wbox(beats, PAD_LEDGE_S, LEDGE_LANE_C, Vector3(LEDGE_LANE_W, 0.24, 1.6), plank, -0.13)
	_wbox(beats, PAD_LEDGE_S, LEDGE_LANE_C - 0.4, Vector3(LEDGE_LANE_W * 0.7, 0.16, 0.2), rib, -0.5)
	var gold := OmniLight3D.new()
	gold.light_color = COL_GOLD
	gold.light_energy = 1.1
	gold.omni_range = 5.5
	gold.position = ChannelsArc.arc_pos(PAD_LEDGE_S, PAD_POS_LANE) + Vector3(0.0, 0.9, 0.0)
	beats.add_child(gold)
	# drifting pollen motes (static emissive specks — the gold light does the movement work)
	var mote := _mat("mote", Color(1.0, 0.85, 0.4), COL_GOLD, 2.2)
	var mrng := RandomNumberGenerator.new()
	mrng.seed = 16
	for k in range(5):
		var sphere := SphereMesh.new()
		sphere.radius = 0.035
		sphere.height = 0.07
		_world_mesh(beats, sphere, mote,
			ChannelsArc.arc_pos(PAD_LEDGE_S + mrng.randf_range(-0.5, 0.5),
				PAD_POS_LANE + mrng.randf_range(-0.6, 0.6)) + Vector3(0.0, 0.3 + mrng.randf() * 1.1, 0.0))
