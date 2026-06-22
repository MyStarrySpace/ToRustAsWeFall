extends "res://scripts/scene_chunks/scene_chunk.gd"

## WASH RELAY — the early-stretch traversal gauntlet.
##
## A linear run of distinct PUZZLE SECTIONS, each a timed water hazard on one shared cadence. Standing
## in an ACTIVE section's footprint when it floods washes you back to the start shelter. Sections differ
## by TYPE (the verb) and by how they're DISABLED for the party:
##   flush   — a lowered channel floods            (disable: OVERRIDE — a runner crosses + presses it)
##   current — water washes across a narrow walk    (disable: TIMING  — read the cadence, cross between)
##   jet     — floor nozzles erupt                  (disable: OVERRIDE)
##   plate   — a gap whose bridge needs a held plate (disable: PLATE  — one stays on the plate for others)
##   sluice  — a gate slams the threshold           (disable: TIMING; a REAL blocker while closed)
## The back half adds a THREAT layer over the wash — guards that hunt the party, hide alcoves that
## conceal you from them, and flures that draw a guard off its post:
##   patrol  — a guard ROAMS the section; duck into the hide alcove (full concealment) + time the wash
##   lure    — a SENTRY holds a chokepoint; fire the flure to distract + draw it, then cross
## A guard that lands a hit shoves you into the channel (washed to the start shelter — same consequence).
## Reach the chunk end with the whole party; a RETURN device pulls washed members back up.
## All hazards fire on the gameplay SCHEDULER (recurring per-section onsets) — fast-forward + replay safe.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")
const ChannelsArc := preload("res://scripts/game/world/channels_arc.gd")
const StretchGenerator := preload("res://scripts/generation/stretch_generator.gd")
const WaterShader := preload("res://resources/channels_water.gdshader")
const WaterTexV0 := preload("res://resources/models/channels/channels_water_v0.png")
const WaterTexV1 := preload("res://resources/models/channels/channels_water_v1.png")

const PARTY_IDS := ["aster", "peris", "endo"]
const START_POS := Vector3(3.0, 0.5, 0.0)
const SPAWNS := {
	"aster": Vector3(3.0, 0.5, 0.0), "peris": Vector3(2.0, 0.5, 1.2), "endo": Vector3(2.0, 0.5, -1.2),
}
# The gauntlet, front (pure wash) to back (wash + threats). Each section may override the shared cadence
# with its own "period"/"dur" (variety: tight frantic windows vs slow long-danger surges).
const SECTIONS := [
	{"type": "flush",        "x0": 6.0,  "x1": 11.0, "phase": 0.0, "disable": "override"},
	{"type": "current",      "x0": 14.0, "x1": 19.0, "phase": 2.5, "disable": "timing", "period": 4.0},   # fast beat
	{"type": "jet",          "x0": 22.0, "x1": 27.0, "phase": 1.2, "disable": "override"},
	{"type": "plate",        "x0": 30.0, "x1": 35.0, "phase": 3.6, "disable": "plate"},
	{"type": "sluice",       "x0": 38.0, "x1": 41.0, "phase": 0.8, "disable": "timing"},
	{"type": "patrol",       "x0": 46.0, "x1": 53.0, "phase": 4.0, "disable": "timing"},          # roaming guard + alcove
	{"type": "lure",         "x0": 56.0, "x1": 61.0, "phase": 1.6, "disable": "timing"},          # sentry + flure
	{"type": "basin",        "x0": 64.0, "x1": 71.0, "phase": 0.0, "disable": "override",
		"period": 8.0, "dur": 2.6},                                                               # wide, slow, long danger — guarded
	{"type": "double_plate", "x0": 74.0, "x1": 79.0, "phase": 2.0, "disable": "double_plate"},    # TWO plates, both held
]
const FLOOR_Z_HALF := 4.0
const FLOOR_MIN_X := -1.0
const FLOOR_MAX_X := 87.0
const CHUNK_END_X := 84.0
# Connect-back devices at the CHUNK END (link back to the stretch start) — positions track the end.
const TERMINAL_POS := Vector3(CHUNK_END_X, 0.5, 2.5)     # telephone stranded crew up — one party call, instant
const SLOPEROPE_POS := Vector3(CHUNK_END_X, 0.5, -2.5)   # drop a climbing line down to the start shelter
const CLIMB_POS := Vector3(5.0, 0.5, 2.5)                # start — a washed member climbs the dropped line up
const RETURN_LANDING := Vector3(CHUNK_END_X - 1.0, 0.5, 0.0)   # where recovered crew rejoin the party
const FLOW_PERIOD := 6.0            # default cadence (a section's "period" overrides it)
const FLOOD_DURATION := 1.4         # default danger window (a section's "dur" overrides it)
const FIRST_FLOOD := 2.5
const PLATE_RADIUS := 1.4           # how close a character must be to "hold" a plate
const DOUBLE_PLATE_Z := 2.5         # the two pads of a double-plate sit at ±this z

# --- Threat layer (guards / hide alcoves / lures, laid over the guarded sections) ---
const HIDE_ALCOVES := [
	{"pos": Vector3(49.5, 0.5, 3.3), "radius": 1.9},   # a nook in the patrol section
	{"pos": Vector3(67.5, 0.5, 3.3), "radius": 1.9},   # a nook beside the guarded basin
]
const ENEMY_SPECS := [
	{"id": "ch_roamer", "spawn": Vector3(49.5, 0.5, 0.0), "kind": "roam",  "radius": 2.6, "speed": 3.0, "range": 5.5},
	{"id": "ch_sentry", "spawn": Vector3(58.5, 0.5, 0.0), "kind": "guard", "radius": 0.0, "speed": 4.0, "range": 6.0},
	{"id": "ch_basin",  "spawn": Vector3(67.5, 0.5, 0.0), "kind": "roam",  "radius": 3.0, "speed": 3.2, "range": 5.5},
	# The drain-loop guard: posts on the DRY salvage ledge across the flooding run. Short reach so it never
	# harasses a runner on the main deck (lane 0) — it only engages a player who detours INTO the loop.
	{"id": "ch_drain", "spawn": Vector3(81.25, 0.5, 9.3), "kind": "guard", "radius": 0.0, "speed": 4.2, "range": 5.0},  # DRAIN_GUARD_ID
]
const LURE_SPECS := [{"pos": Vector3(54.0, 0.5, 2.8), "target": "ch_sentry"}]
const LURE_DURATION := 9.0

# --- Branch puzzle offshoots (built USING the archetype generation framework) ---
# At each GAP between sections, a puzzle fragment branches OUT away from the spiral: on the helix, +lane
# is a RADIAL spoke jutting off the deck edge (lane 4 = the deck rim) out to the pad. One generated stretch
# (StretchGenerator, node_count = gap count) supplies an archetype + content per branch; a guarded branch
# also spawns a roamer (capped). Branches are OPTIONAL reward detours — a salvage cache pays off the climb
# out and back; the gaps themselves stay walkable, so they never block the main run.
const BRANCH_S_SPAN := 3.0          # branch footprint along s (fits inside every gap)
const BRANCH_HALF_S := 1.5
const BRANCH_NECK_LANE := 3.5       # walkable region starts here (overlaps the deck rim at lane 4 -> connected)
const BRANCH_OUTER_LANE := 10.0     # walkable region reaches this far out
const BRANCH_DECK_CENTER_LANE := 7.0
const BRANCH_LANE_SPAN := 6.0       # the deck plank spans lane 4..10 radially
const BRANCH_PAD_LANE := 8.5        # where the cache + content sit
const BRANCH_GUARD_CAP := 3         # at most this many branches get a roaming guard (perf + difficulty)
const BRANCH_GEN_SEED := 4727
const BRANCH_REWARD := 1
const BRANCH_SWITCH_LANE := 5.0     # the gate switch sits just past the neck (the player hits it on the way out)
const BRANCH_GATE_LANE := 6.5       # the gate bar (cosmetic barrier) between the switch and the pad cache

var _branches: Array = []           # per gap: {gap, mid_x, pad_lane, archetype, content_count, collected, cache,
									#           guard, gate_kind, unlocked, switch, gate_bar}
var _branch_loot := 0
var _branch_root: Node3D
var _branch_guard_spawns := {}      # guard id -> flat spawn (so reset re-snaps branch guards too)

# --- Drain loop: an OPTIONAL flooding DETOUR off the spiral ("out the deck rim and back in"). It leaves the
# deck at S0, runs a flooding channel along the OUTER lane, and rejoins at S1, with a DRY salvage ledge across
# the water. A guard posts on that ledge; you BAIT it across the flooding run and let the current DROWN it
# (the bait pulls it in, then the chase keeps it there). The whole thing is bypassed by the main deck (lane 0),
# and the guard's reach is short so it never harasses a straight-through runner. Like every hazard here it
# floods on the GAMEPLAY SCHEDULER (exact ticks), and the kill is decided AT the onset tick — never per-frame —
# so it is fast-forward + replay invariant.
const DRAIN_GUARD_ID := "ch_drain"
const DRAIN_LOOP_S0 := 79.0          # entry leg: the loop leaves the deck rim here
const DRAIN_LOOP_S1 := 83.5          # exit leg: the loop rejoins the deck rim here
const DRAIN_RUN_LANE := 7.0          # the outward flooding channel (radial offset from the deck centreline)
const DRAIN_RUN_HALF := 1.3          # flood footprint half-width in lane (a guard/runner within this band is caught)
const DRAIN_LEDGE_LANE := 9.3        # the DRY salvage ledge across the run — outside the flood band (guard posts here)
const DRAIN_LOOP_PERIOD := 5.0       # the loop's own flood cadence (independent of the section beats)
const DRAIN_LOOP_DUR := 1.6          # how long the run stays flooded per surge
const DRAIN_LOOP_PHASE := 1.0        # stagger from FIRST_FLOOD so the loop isn't synced to section 0
const DRAIN_BAIT_PULL := 6.5         # the bait holds the guard committed in the run a bit longer than one flood
									 # PERIOD, so a surge is GUARANTEED to catch it while it's parked there
const DRAIN_KILL_DELAY := 0.7        # the drowned guard's body lingers this long (cosmetic dissolve) then is removed
const DRAIN_DROWN_SWEEPS := 4        # enemy-drown re-checks spread across the flood WINDOW (not just the onset tick)
var _drain_root: Node3D
var _drain_water: Array = []         # the run's flood-water segments (toggled by _drain_flooding)
var _drain_flooding := false         # the run is mid-surge this window (scheduler-set)
var _drain_flood_count := 0          # surges fired (for the analytic next-onset read)
var _drowned_count := 0             # guards the current has taken down the drain this run
var _cadence_t0 := 0.0              # scheduler tick the hazard cadence was (re)armed at — the analytic safe-window
									# reads are relative to THIS, so a reset that re-arms at a non-zero tick stays
									# self-consistent (the real onset and the predicted onset agree)

var _phase := "ready"
var _override_locked := []         # per section — an override has been pressed (latched)
var _flooding := []                # cosmetic surge window
var _flood_counts := []            # per section — how many surges have fired (cadence variety / tests)
var _plate_held := []              # per section — all the section's plates are held this frame
var _sluice_blocked := []          # per section — the sluice gate cells are currently walled off
var _washed := {}                  # legacy stranding set — kept empty now (checkpoint-wash doesn't strand)
var _sweep_count := 0              # how many times the party was swept back this run (a "rough run" read)
var _section_wash_counts := []     # per section — times THIS section has washed the party (the flush hint trigger)
var _run_hint_shown := false       # one-shot: after enough washes, a character grumbles that you must RUN the surges
const FLUSH_HINT_THRESHOLD := 3    # the flush hint only appears once a SINGLE section has washed you this many times
var _scheduled := false
var _flow_strips: Array = []
# Flood WATER layer — the in-game flood visual. Built WARPED onto the helix under a Node3D root so it SURVIVES
# hide_flat_graybox (which only hides the chunk's direct-child graybox meshes), unlike the flat flow strips.
# Shown per section while it floods, so the wash always has a visible cause (the surging water you got caught in).
var _water_root: Node3D
var _section_water: Array = []      # per section: Array[MeshInstance3D] of warped flood-water segments
var _sluice_gate := {}             # sluice section index -> warped gate mesh (visible while the gate is closed)
const WATER_SEG := 2.0             # flood-water segment length along the arc (segmented to follow the curve)
const WATER_THICK := 0.55
var _enemies: Array = []
var _lure_until: Array = []        # per lure — scheduler tick the distraction ends (<=0 = inactive)
var _lure_meshes: Array = []
var _sloperope_deployed := false   # the chunk-end line has been dropped (the start climb point is live)
var _debug_tick := 0               # throttles the CHANNELS_DEBUG position log
var _rope_mesh: MeshInstance3D

# --- Character abilities (TRACE / BLOOM / BRACE) — each protagonist's signature read ---
# Aster TRACE (aster_focus): reads the flood cadence and surfaces the next SAFE window for the section he
# stands in. Peris BLOOM (peris_tune): flora-tending — grows a persistent bioluminescent light that lights the
# dark drainage + marks a safe lane. Endo BRACE (endo_patch): braces a washed/at-risk member (refunds stamina)
# and reveals which hide alcove is deep cover. All derived from the scheduler tick / positions — never logged.
const ABILITY_CONTEXT := "channels_rhythm"
const TELEGRAPH_LEAD := 1.2         # seconds before an onset the flow strip brightens (the surge tell)
const TRACE_HOLD := 6.0             # how long a TRACE read stays surfaced
const ABILITY_OWNERS := {"aster_focus": "aster", "peris_tune": "peris", "endo_patch": "endo"}
var _trace_section := -1            # section TRACE is reading (-1 = none) — derived, cleared on reset
var _trace_until := 0.0            # scheduler tick the TRACE read expires
var _blooms: Array = []            # peris's flora lights: [{pos, node}] — persistent for the run
var _bloom_root: Node3D

# --- Cosmetic-only flourishes (@rendering_only — tweens/wall-clock fine here; never gate a transition) ---
var _flush_hint_shown := false     # one-shot: the FIRST flush telegraph plays a clearer "a surge is coming" preview
var _flush_hint_root: Node3D       # ephemeral nodes for the flush preview pulse (freed after it plays)
var _wash_anim_root: Node3D        # parent for any in-flight "swept down the spiral" cosmetic streaks
var _surge_root: Node3D            # parent for the on-onset foam/surge accents (throwaway, freed after each)
# Pipe-mouth SPLASH planes: a rough splash blob billboard at each section's pipe mouth that fades in slightly
# BEFORE the flood (a lead-in so the water doesn't blink in) and runs while the water runs, then eases out.
# Intensity is scheduler-driven (the telegraph lead + _flooding); the per-frame ease is @rendering_only.
const SPLASH_LEAD := 1.2           # the splash starts ramping in this long before the onset (matches the telegraph)
const SPLASH_SMOOTH := 7.0         # how fast the splash eases toward its target intensity (cosmetic)
var _splash_root: Node3D
var _splash_planes: Array = []     # per section: MeshInstance3D billboard quad at the pipe mouth
var _splash_intensity: Array = []  # per section: current eased 0..1 splash strength
var _splash_tex: Texture2D
const PARTY_RENDER_COLORS := {     # the per-character ownership colour (matches the path ribbon / queued glow)
	"aster": Color(0.29, 0.62, 1.0), "peris": Color(1.0, 0.67, 0.27), "endo": Color(0.4, 0.72, 0.55),
}

# --- Build ---

func _section_color(t: String) -> Color:
	match t:
		"flush":   return Color(0.15, 0.30, 0.55)
		"current": return Color(0.20, 0.45, 0.70)
		"jet":     return Color(0.40, 0.55, 0.85)
		"plate":   return Color(0.55, 0.35, 0.10)
		"sluice":  return Color(0.45, 0.20, 0.10)
		"patrol":  return Color(0.55, 0.18, 0.20)
		"lure":    return Color(0.55, 0.30, 0.50)
		"basin":   return Color(0.12, 0.35, 0.60)
		"double_plate": return Color(0.60, 0.40, 0.10)
	return Color(0.2, 0.3, 0.5)

func _build_chunk() -> void:
	_wdbg("build_chunk start")
	var fcx := (FLOOR_MIN_X + FLOOR_MAX_X) * 0.5
	var fw := FLOOR_MAX_X - FLOOR_MIN_X
	_add_floor(self, Vector3(fcx, -0.05, 0.0), Vector3(fw, 0.1, FLOOR_Z_HALF * 2.0), Color(0.10, 0.11, 0.13))
	_add_floor(self, START_POS + Vector3(-1.0, -0.05, 0.0), Vector3(8.0, 0.12, FLOOR_Z_HALF * 2.0 + 1.0), Color(0.09, 0.13, 0.16))
	var wc := Color(0.13, 0.14, 0.16)
	_add_box(self, Vector3(fcx, 1.6, -FLOOR_Z_HALF - 0.2), Vector3(fw, 3.2, 0.4), wc)
	_add_box(self, Vector3(fcx, 1.6, FLOOR_Z_HALF + 0.2), Vector3(fw, 3.2, 0.4), wc)
	# one large pipe spanning the gauntlet (the shared flow source)
	var px0: float = SECTIONS[0]["x0"]; var px1: float = SECTIONS[SECTIONS.size() - 1]["x1"]
	_add_box(self, Vector3((px0 + px1) * 0.5, 4.4, FLOOR_Z_HALF - 0.4), Vector3(px1 - px0 + 2.0, 1.2, 1.2), Color(0.2, 0.19, 0.18))

	for i in range(SECTIONS.size()):
		var s: Dictionary = SECTIONS[i]
		var t := str(s["type"]); var x0: float = s["x0"]; var x1: float = s["x1"]; var cx := (x0 + x1) * 0.5; var w := x1 - x0
		# per-type graybox dressing (distinct silhouettes)
		match t:
			"flush":
				_add_box(self, Vector3(cx, -0.18, 0.0), Vector3(w, 0.2, FLOOR_Z_HALF * 1.6), Color(0.06, 0.08, 0.1))   # lowered channel
				_add_box(self, Vector3(cx, 3.4, FLOOR_Z_HALF - 0.4), Vector3(1.0, 0.9, 0.9), Color(0.22, 0.21, 0.2))   # spout
			"current":
				_add_box(self, Vector3(cx, -0.12, FLOOR_Z_HALF * 0.7), Vector3(w, 0.3, 2.2), Color(0.06, 0.08, 0.1))
				_add_box(self, Vector3(cx, -0.12, -FLOOR_Z_HALF * 0.7), Vector3(w, 0.3, 2.2), Color(0.06, 0.08, 0.1))
			"jet":
				for jx in [x0 + w * 0.25, cx, x1 - w * 0.25]:
					for jz in [-1.6, 0.0, 1.6]:
						_add_box(self, Vector3(jx, 0.04, jz), Vector3(0.6, 0.08, 0.6), Color(0.07, 0.07, 0.09))
			"plate":
				_add_box(self, Vector3(cx, 0.06, 0.0), Vector3(w, 0.12, 1.6), Color(0.12, 0.13, 0.16))                 # the bridge plank
				_add_box(self, Vector3(x0 - 1.2, 0.04, 0.0), Vector3(1.0, 0.1, 1.8), Color(0.55, 0.35, 0.1))          # the pressure plate
			"sluice":
				_add_box(self, Vector3(x0, 1.7, 0.0), Vector3(0.3, 3.4, FLOOR_Z_HALF * 2.0), Color(0.16, 0.16, 0.18))
				_add_box(self, Vector3(x1, 1.7, 0.0), Vector3(0.3, 3.4, FLOOR_Z_HALF * 2.0), Color(0.16, 0.16, 0.18))
				_add_box(self, Vector3(cx, 3.3, 0.0), Vector3(w, 0.5, FLOOR_Z_HALF * 2.0), Color(0.16, 0.16, 0.18))
			"patrol":
				_add_box(self, Vector3(cx, 0.015, 0.0), Vector3(w, 0.03, FLOOR_Z_HALF * 1.6), Color(0.08, 0.07, 0.08))   # the guard's open beat
			"lure":
				for zz in [-1.0, 1.0]:
					_add_box(self, Vector3(cx, 1.2, zz * (FLOOR_Z_HALF - 1.0)), Vector3(w, 2.4, 2.0), Color(0.14, 0.13, 0.15))  # chokepoint walls pinch the path
			"basin":
				_add_box(self, Vector3(cx, -0.3, 0.0), Vector3(w, 0.4, FLOOR_Z_HALF * 1.9), Color(0.05, 0.07, 0.09))   # a wide, deep lowered basin
				for sx in [x0 + w * 0.2, cx, x1 - w * 0.2]:
					_add_box(self, Vector3(sx, 3.6, FLOOR_Z_HALF - 0.4), Vector3(1.1, 1.0, 1.1), Color(0.22, 0.21, 0.2))   # multiple spouts
			"double_plate":
				_add_box(self, Vector3(cx, 0.06, 0.0), Vector3(w, 0.12, 1.4), Color(0.12, 0.13, 0.16))                 # the bridge plank
				for zz in [-DOUBLE_PLATE_Z, DOUBLE_PLATE_Z]:
					_add_box(self, Vector3(x0 - 1.2, 0.04, zz), Vector3(1.0, 0.1, 1.6), Color(0.6, 0.4, 0.1))          # two pressure plates
		# the active-flow indicator strip (pulses while flooding)
		var strip := _add_box(self, Vector3(cx, 0.03, 0.0), Vector3(w, 0.06, FLOOR_Z_HALF * 1.7), _section_color(t))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _section_color(t) * 0.6; mat.emission_enabled = true
		mat.emission = _section_color(t); mat.emission_energy_multiplier = 0.4
		strip.material_override = mat
		_flow_strips.append(strip)
		# the disable control: an override console past the section, or a held plate before it
		if str(s["disable"]) == "override":
			var ov := _add_interactable(self, "Override%d" % i, "Flow override", Vector3(x1 + 1.5, 0.5, 0.0),
				"OVERRIDE", "", 1.0, true, 1.6, Interactable.InteractableType.INSPECTION, false)
			var ovm := _add_box(ov, Vector3(0.0, 0.1, 0.0), Vector3(0.6, 1.0, 0.4), Color(0.2, 0.45, 0.5),
				Color(0.3, 0.9, 1.0), 1.0)   # a console post (child -> rides the helix warp)
			_outline_interactable_child(ov, ovm, "Override%d" % i, 1.6)
			ov.interacted.connect(func() -> void: _on_override(i))
	_wdbg("sections built")
	_build_threats()
	_wdbg("threats built")
	_build_connect_backs()
	_wdbg("connect-backs built")
	_build_branches()
	_wdbg("branches built")
	_build_water_layer()
	_wdbg("water built")
	_build_drain_loop()
	_wdbg("drain loop built")
	_build_splash_planes()
	_wdbg("pipe splashes built")

# A box pre-warped onto the helix under an arbitrary parent (generalises _add_warped_box, which targets the
# branch root). y_off lifts it along the deck's local up. Used for the flood-water layer + sluice gates.
func _warped_box(parent: Node3D, s: float, lane: float, size: Vector3, color: Color, emission := Color.BLACK, energy := 0.0, y_off := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size = size; mesh.mesh = box
	mesh.material_override = _make_material(color, emission, energy)
	var xf := _branch_warp_xform(s, lane)
	xf.origin += xf.basis.y * y_off
	mesh.transform = xf
	parent.add_child(mesh)
	return mesh

# A ShaderMaterial running channels_water.gdshader — the animated, textured flood-water look. Each flood
# segment gets its OWN instance so a per-segment surge accent can nudge its uniforms without affecting the
# others. `variant` picks the tile (v0/v1) so adjacent sections aren't perfectly synced. Purely cosmetic.
func _make_water_material(variant := 0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WaterShader
	mat.set_shader_parameter("water_tex", WaterTexV1 if variant % 2 == 1 else WaterTexV0)
	# Draw the translucent flood AFTER the perception-overlay quad (render_priority 126) so it blends on TOP of
	# the data-view instead of vanishing under it (transparent surfaces aren't in the overlay's screen texture).
	mat.render_priority = 127
	return mat

# Build the per-section flood-water (segmented along the arc so it follows the helix) + the sluice gates,
# all WARPED and under _water_root (a Node3D -> survives hide_flat_graybox). Hidden until a section floods.
func _build_water_layer() -> void:
	_water_root = Node3D.new(); _water_root.name = "FloodWater"; add_child(_water_root)
	_section_water = []
	_sluice_gate = {}
	for i in range(SECTIONS.size()):
		var s: Dictionary = SECTIONS[i]
		var x0: float = s["x0"]; var x1: float = s["x1"]
		var segs: Array = []
		var n := maxi(2, int(ceil((x1 - x0) / WATER_SEG)))
		for k in range(n):
			var sc := lerpf(x0, x1, (k + 0.5) / float(n))
			var seg := _warped_box(_water_root, sc, 0.0,
				Vector3(FLOOR_Z_HALF * 1.8, WATER_THICK, (x1 - x0) / float(n) * 1.12),
				Color(0.08, 0.3, 0.55), Color(0.22, 0.5, 1.0), 1.4, WATER_THICK * 0.45)
			# Swap the flat box material for the animated, textured water shader (alternating tile per
			# segment so the surface isn't perfectly tiled). The scheduler-driven `visible` toggle below
			# is UNCHANGED — only the LOOK changes.
			seg.material_override = _make_water_material(i + k)
			seg.visible = false
			segs.append(seg)
		_section_water.append(segs)
		if str(s["type"]) == "sluice":
			# the gate stands across the threshold while closed (a visible, real blocker — not invisible)
			var gate := _warped_box(_water_root, (x0 + x1) * 0.5, 0.0,
				Vector3(FLOOR_Z_HALF * 1.8, 2.4, 0.3), Color(0.3, 0.12, 0.1), Color(1.0, 0.3, 0.18), 1.0, 1.2)
			gate.visible = false
			_sluice_gate[i] = gate

# The connect-back points at the chunk end (plus the start climb point the sloperope feeds).
func _build_connect_backs() -> void:
	# TERMINAL — telephone stranded crew up; one call at the chunk end, click to walk over. The console mesh is
	# a CHILD of the interactable so both the visual and its outline ride the helix warp together.
	var term := _add_interactable(self, "Terminal", "Telephone up", TERMINAL_POS,
		"TERMINAL", "", 1.2, false, 1.7, Interactable.InteractableType.INSPECTION, false)
	term.interacted.connect(func() -> void: _on_terminal())
	var tm := _add_box(term, Vector3(0.0, 0.4, 0.0), Vector3(0.8, 1.5, 0.4), Color(0.1, 0.4, 0.45))
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.1, 0.4, 0.45); tmat.emission_enabled = true
	tmat.emission = Color(0.2, 0.9, 1.0); tmat.emission_energy_multiplier = 2.0; tm.material_override = tmat
	_outline_interactable_child(term, tm, "Terminal", 1.7)
	# SLOPEROPE — drop a climbing line down to the start; the party deploys it once.
	var rope := _add_interactable(self, "Sloperope", "Drop sloperope", SLOPEROPE_POS,
		"DROP LINE", "", 1.2, false, 1.7, Interactable.InteractableType.INSPECTION, false)
	rope.interacted.connect(func() -> void: _on_sloperope())
	var rpost := _add_box(rope, Vector3(0.0, 1.4, 0.0), Vector3(0.4, 2.8, 0.4), Color(0.3, 0.22, 0.12))   # the reel post
	_outline_interactable_child(rope, rpost, "Sloperope", 1.7)
	# CLIMB POINT at the start — a washed member climbs the dropped line back up to the chunk end.
	var climb := _add_interactable(self, "ClimbLine", "Climb the line", CLIMB_POS,
		"CLIMB", "", 1.4, false, 1.7, Interactable.InteractableType.INSPECTION, false)
	climb.interacted.connect(func() -> void: _on_climb())
	_rope_mesh = _add_box(climb, Vector3(0.0, 1.4, 0.0), Vector3(0.16, 2.8, 0.16), Color(0.25, 0.18, 0.1))
	_rope_mesh.visible = false   # the line only appears once dropped from the chunk end
	_outline_interactable_child(climb, _rope_mesh, "ClimbLine", 1.7)

# --- Branch puzzle offshoots ---

func _wdbg(msg: String) -> void:
	if OS.has_environment("PREVIEW_DEBUG"):
		print("[wash_relay] → ", msg)

# The mid-s of each GAP between consecutive sections (where a branch attaches).
func _gap_mids() -> Array:
	var mids: Array = []
	for i in range(SECTIONS.size() - 1):
		mids.append((float(SECTIONS[i]["x1"]) + float(SECTIONS[i + 1]["x0"])) * 0.5)
	return mids

# Generate ONE stretch (one node per gap) through the archetype framework — each node hands a branch its
# archetype + content placements. Falls back to a fixed archetype rotation so the offshoots still build if
# the generation catalog is unavailable (the chunk never hard-fails on missing data).
func _generate_branch_nodes(count: int) -> Array:
	var spec: Dictionary = StretchGenerator.generate({
		"id": "wash_relay_branches", "title": "Wash Relay Branches",
		"seed": BRANCH_GEN_SEED, "complexity_tier": "developing", "progression_stage": 3,
		"budget": {"node_count": count, "branch_count": 0},
	})
	if bool(spec.get("ok", false)):
		var nodes: Array = spec.get("nodes", [])
		if nodes.size() >= count:
			return nodes.slice(0, count)
	var fallback: Array = []
	var names := ["Plant as tool", "Stealth-and-time", "Carry the heavy thing", "Redirected enemy aggression",
		"Lysate forage cache", "Narrative beat", "Plant as tool", "Stealth-and-time"]
	for i in range(count):
		fallback.append({"archetype_name": names[i % names.size()], "content_placements": [], "enemies": []})
	return fallback

func _build_branches() -> void:
	_branches.clear()
	_branch_loot = 0
	_branch_guard_spawns.clear()
	_branch_root = Node3D.new()
	_branch_root.name = "Branches"
	add_child(_branch_root)
	var mids := _gap_mids()
	_wdbg("generating %d branch nodes" % mids.size())
	var nodes := _generate_branch_nodes(mids.size())
	_wdbg("generated %d nodes" % nodes.size())
	var guards_spawned := 0
	for g in range(mids.size()):
		var mid: float = mids[g]
		var node: Dictionary = nodes[g] if g < nodes.size() else {}
		var archetype := str(node.get("archetype_name", "Offshoot"))
		var placements: Array = node.get("content_placements", [])
		# The radial plank: juts off the deck rim (lane 4) out to the pad (lane 10), pre-warped onto the helix.
		var deck_color := Color(0.12, 0.14, 0.17)
		_add_warped_deck(mid, BRANCH_DECK_CENTER_LANE, Vector3(BRANCH_LANE_SPAN, 0.2, BRANCH_S_SPAN), deck_color)
		# A marker post at the deck rim so the offshoot reads as a turn-off from the main run.
		_add_warped_box(mid, BRANCH_NECK_LANE + 0.4, Vector3(0.4, 1.6, 0.4), Color(0.2, 0.5, 0.55), Color(0.2, 0.7, 0.8), 0.8)
		# The archetype's content placements, clustered on the pad (graybox identity of the puzzle).
		var content_count := _build_branch_content(mid, placements)
		# Reward cache — authored FLAT (the host warp pass lifts every interactable onto the helix); its mesh
		# is a CHILD so it rides the warp and stays visible (it isn't in the GLB the flat-graybox hide replaces).
		# Click to walk over, then a salvage WORK beat (TIMED_ACTION). The cache box is a CHILD of the
		# interactable so the visual + its outline+glow ride the helix warp together.
		var cache := _add_interactable(self, "BranchCache%d" % g, "Salvage cache",
			Vector3(mid, 0.5, BRANCH_PAD_LANE), "SALVAGE", "", 1.2, true, 1.6,
			Interactable.InteractableType.TIMED_ACTION, false)
		var cm := MeshInstance3D.new()
		var cb := BoxMesh.new(); cb.size = Vector3(0.7, 0.7, 0.7); cm.mesh = cb
		cm.material_override = _make_material(Color(0.7, 0.6, 0.2), Color(1.0, 0.85, 0.25), 1.4)
		cm.position = Vector3(0.0, 0.45, 0.0)
		cache.add_child(cm)
		_outline_interactable_child(cache, cm, "BranchCache%d" % g, 1.6)
		cache.interacted.connect(func() -> void: _on_branch_cache(g))
		# A guarded branch (the archetype carries an enemy) spawns a roamer on the pad — a real risk detour.
		var guard = null
		if guards_spawned < BRANCH_GUARD_CAP and _branch_has_enemy(node):
			guard = _spawn_branch_guard(g, mid)
			if guard != null:
				guards_spawned += 1
		# The PUZZLE: the cache is GATED by an archetype-themed switch at the neck. A guarded branch's switch
		# is a decoy that lures the roamer off the pad; an "open" (forage/narrative) branch is a free breather.
		var gate_kind := _branch_gate_kind(archetype, guard != null)
		var gate_bar = null
		var switch = null
		if gate_kind != "open":
			cache.set_interaction_enabled(false)   # locked until the switch fires (synced to the data layer)
			gate_bar = _build_branch_gate_bar(mid)
			switch = _build_branch_switch(g, mid, gate_kind)
		_branches.append({
			"gap": g, "mid_x": mid, "pad_lane": BRANCH_PAD_LANE, "archetype": archetype,
			"content_count": content_count, "collected": false, "cache": cache, "guard": guard,
			"gate_kind": gate_kind, "unlocked": gate_kind == "open", "switch": switch, "gate_bar": gate_bar,
		})

func _branch_has_enemy(node: Dictionary) -> bool:
	if not (node.get("enemies", []) as Array).is_empty():
		return true
	for p in node.get("content_placements", []):
		if (p is Dictionary) and str((p as Dictionary).get("category", "")) == "enemies":
			return true
	return false

# Lay the archetype's content placements (capped) around the pad centre, pre-warped onto the helix.
func _build_branch_content(mid: float, placements: Array) -> int:
	var offsets := [Vector2(-0.8, -0.7), Vector2(0.8, -0.7), Vector2(0.0, 0.9)]   # (s, lane) relative to pad
	var count := 0
	for raw in placements:
		if count >= offsets.size():
			break
		if not (raw is Dictionary):
			continue
		var p := raw as Dictionary
		var off: Vector2 = offsets[count]
		var sz := _branch_marker_size(p.get("size", []))
		_add_warped_box(mid + off.x, BRANCH_PAD_LANE + off.y, sz,
			_branch_content_color(str(p.get("category", ""))), Color.BLACK, 0.0)
		count += 1
	return count

func _branch_marker_size(raw_size: Variant) -> Vector3:
	if raw_size is Array and (raw_size as Array).size() >= 3:
		var a := raw_size as Array
		return Vector3(clampf(float(a[0]), 0.4, 1.2), clampf(float(a[1]), 0.4, 1.2), clampf(float(a[2]), 0.4, 1.2))
	return Vector3(0.7, 0.7, 0.7)

func _branch_content_color(category: String) -> Color:
	match category:
		"flora": return Color(0.25, 0.55, 0.3)
		"enemies": return Color(0.6, 0.2, 0.22)
		"structures": return Color(0.35, 0.4, 0.5)
	return Color(0.4, 0.4, 0.45)

func _spawn_branch_guard(g: int, mid: float):
	var gs = _get_game_state()
	if gs == null:
		return null
	var spawn := Vector3(mid, 0.5, BRANCH_PAD_LANE)
	var enemy = EnemyScript.new()
	enemy.name = "BranchGuard_%d" % g
	enemy.position = spawn
	enemy.move_speed = 2.8
	enemy.detection_range = 4.5
	enemy.char_id = "branch_guard_%d" % g
	enemy.game_state = gs
	enemy._detection_targets.assign(PARTY_IDS)
	_branch_root.add_child(enemy)
	gs.register_character(enemy.char_id, spawn, enemy.move_speed, {"detection_range": enemy.detection_range})
	if enemy.has_method("activate"):
		enemy.activate()
	enemy.set_roam(spawn, 1.6)
	enemy.hit_target.connect(func(tid: String, _dmg: float) -> void: _on_enemy_hit(tid))
	_enemies.append(enemy)
	_branch_guard_spawns[enemy.char_id] = spawn
	return enemy

# A box pre-warped onto the helix: authored as (lane-extent, height, s-extent) so basis_at(s) aligns local
# x with the radial (lane) axis and local z with the tangent (s) axis. Walk-on decks also get layer-1
# collision (the GLB's collision doesn't cover this new geometry, so the player's ground ray must hit it).
func _branch_warp_xform(s: float, lane_center: float) -> Transform3D:
	return Transform3D(ChannelsArc.basis_at(s), ChannelsArc.arc_pos(s, lane_center))

func _add_warped_box(s: float, lane_center: float, size: Vector3, color: Color, emission := Color.BLACK, energy := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size = size; mesh.mesh = box
	mesh.material_override = _make_material(color, emission, energy)
	mesh.transform = _branch_warp_xform(s, lane_center)
	_branch_root.add_child(mesh)
	return mesh

func _add_warped_deck(s: float, lane_center: float, size: Vector3, color: Color) -> void:
	var mesh := _add_warped_box(s, lane_center, size, color)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = mesh.transform
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = size
	col.shape = shape
	body.add_child(col)
	_branch_root.add_child(body)

# --- Drain loop (the flooding detour) ---

# A walkable warped plank under _drain_root (its own Node3D root so it survives hide_flat_graybox). Same as
# _add_warped_deck but parented to the drain loop, not the branch root — keeps the two systems independent.
func _add_drain_deck(s: float, lane_center: float, size: Vector3, color: Color) -> void:
	var mesh := _warped_box(_drain_root, s, lane_center, size, color)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = mesh.transform
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = size
	col.shape = shape
	body.add_child(col)
	_drain_root.add_child(body)

# Build the loop: entry/exit legs off the deck rim, the flooding run between them (segmented so it follows the
# curve), a stub out to the DRY salvage ledge across the water, the run's flood-water (hidden until it surges),
# an outer source wall, and the bait that draws the guard across the current. Authored in flat (s, lane); the
# warp helpers place it on the helix. The cache + the bait interactable are authored FLAT and lifted by the
# host's warp pass like every other interactable here.
func _build_drain_loop() -> void:
	_drain_root = Node3D.new(); _drain_root.name = "DrainLoop"; add_child(_drain_root)
	var s0 := DRAIN_LOOP_S0; var s1 := DRAIN_LOOP_S1; var smid := (s0 + s1) * 0.5
	var deck_color := Color(0.10, 0.13, 0.17)
	var leg_center := (BRANCH_NECK_LANE + DRAIN_RUN_LANE + 0.6) * 0.5
	var leg_span := (DRAIN_RUN_LANE + 0.6) - BRANCH_NECK_LANE
	# Entry + exit legs — radial planks bridging the deck rim (lane 4) to the run (lane ~7).
	_add_drain_deck(s0, leg_center, Vector3(leg_span, 0.2, 1.6), deck_color)
	_add_drain_deck(s1, leg_center, Vector3(leg_span, 0.2, 1.6), deck_color)
	# The flooding run — segmented along the arc so the deck follows the helix instead of chording across it.
	var run_len := s1 - s0
	var nseg := maxi(2, int(ceil(run_len / 2.0)))
	for k in range(nseg):
		var sc := lerpf(s0, s1, (k + 0.5) / float(nseg))
		_add_drain_deck(sc, DRAIN_RUN_LANE, Vector3(DRAIN_RUN_HALF * 2.0, 0.2, run_len / float(nseg) * 1.12), deck_color)
	# The stub out to the DRY salvage ledge (crossing the run reaches it) + the ledge pad itself.
	_add_drain_deck(smid, (DRAIN_RUN_LANE + DRAIN_LEDGE_LANE + 0.6) * 0.5,
		Vector3((DRAIN_LEDGE_LANE + 0.6) - DRAIN_RUN_LANE, 0.2, 2.0), Color(0.11, 0.15, 0.18))
	# Outer "water source" wall along the loop's OUTER RIM, just past the salvage ledge (the side the surge wells
	# up from). Placed beyond the ledge so it bounds the loop instead of bisecting the run->ledge crossing.
	_warped_box(_drain_root, smid, DRAIN_LEDGE_LANE + 0.7, Vector3(0.3, 2.6, run_len + 1.0),
		Color(0.12, 0.13, 0.16), Color(0.15, 0.4, 0.6), 0.5)
	_warped_box(_drain_root, smid, DRAIN_LEDGE_LANE, Vector3(0.4, 1.6, 0.4),
		Color(0.2, 0.5, 0.55), Color(0.2, 0.7, 0.8), 0.7)
	# Flood water on the run (own segments so the toggle is independent of the section water). Hidden until surge.
	_drain_water = []
	for k in range(nseg):
		var sc := lerpf(s0, s1, (k + 0.5) / float(nseg))
		var seg := _warped_box(_drain_root, sc, DRAIN_RUN_LANE,
			Vector3(DRAIN_RUN_HALF * 1.9, WATER_THICK, run_len / float(nseg) * 1.12),
			Color(0.08, 0.3, 0.55), Color(0.22, 0.5, 1.0), 1.4, WATER_THICK * 0.45)
		seg.material_override = _make_water_material(k)
		seg.visible = false
		_drain_water.append(seg)
	# A salvage cache on the dry ledge — the reward that makes the crossing worth it.
	var cache := _add_interactable(self, "DrainCache", "Strip cache", Vector3(smid, 0.5, DRAIN_LEDGE_LANE),
		"SALVAGE", "", 1.2, true, 1.6, Interactable.InteractableType.TIMED_ACTION, false)
	var cm := _add_box(cache, Vector3(0.0, 0.1, 0.0), Vector3(0.7, 0.7, 0.7), Color(0.3, 0.35, 0.2),
		Color(0.6, 0.8, 0.3), 0.6)
	_outline_interactable_child(cache, cm, "DrainCache", 1.6)
	cache.interacted.connect(func() -> void: _on_drain_cache())
	_build_drain_bait()

# The bait: a click-to-walk decoy at the loop mouth (a SAFE spot just inside, below the flood band). Firing it
# pulls the ledge guard DOWN across the flooding run toward the song — straight through the current.
func _build_drain_bait() -> void:
	var bp := Vector3(DRAIN_LOOP_S0, 0.5, BRANCH_NECK_LANE + 0.8)   # lane ~4.3 — inside the loop, below the flood
	var bait := _add_interactable(self, "DrainBait", "Fire bait", bp,
		"BAIT", "", 1.0, true, 1.4, Interactable.InteractableType.INSPECTION, false)
	bait.interacted.connect(func() -> void: _on_drain_bait())
	var bm := _add_box(bait, Vector3(0.0, 0.7 - bp.y, 0.0), Vector3(0.5, 0.9, 0.5), Color(0.45, 0.2, 0.5))
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.45, 0.2, 0.5); bmat.emission_enabled = true
	bmat.emission = Color(0.9, 0.3, 1.0); bmat.emission_energy_multiplier = 0.7
	bm.material_override = bmat
	_outline_interactable_child(bait, bm, "DrainBait", 1.4)

func _on_branch_cache(g: int) -> void:
	if g < 0 or g >= _branches.size():
		return
	if bool(_branches[g].get("collected", false)):
		return
	# Defense in depth: the cache's own enabled flag already blocks the trigger while gated, but a direct
	# data-layer trigger shouldn't pay out a locked cache either.
	if not bool(_branches[g].get("unlocked", true)):
		_say("// LOCKED // clear the gate first")
		return
	_branches[g]["collected"] = true
	_branch_loot += BRANCH_REWARD
	_say("// SALVAGE // cache stripped (%d)" % _branch_loot)

# Map an archetype to the kind of gate that guards its cache. A guarded branch is always a lure puzzle;
# otherwise the archetype's theme picks the mechanism. Forage/narrative branches are free (a breather).
func _branch_gate_kind(archetype: String, has_guard: bool) -> String:
	var a := archetype.to_lower()
	if has_guard or "stealth" in a or "enemy" in a or "redirect" in a or "aggress" in a:
		return "decoy"
	if "plant" in a or "flora" in a or "pollen" in a:
		return "valve"
	if "forage" in a or "lysate" in a or "narrative" in a or "beat" in a or "rest" in a:
		return "open"
	return "lever"   # carry / structure / unknown -> a counterweight lever

# Per-gate-kind presentation + flavour (label, post colour/glow, the line played on activation).
func _branch_gate_theme(kind: String) -> Dictionary:
	match kind:
		"valve":
			return {"label": "POLLEN VALVE", "color": Color(0.22, 0.55, 0.3), "glow": Color(0.3, 0.9, 0.4),
				"msg": "// VALVE // spores vented — cache exposed"}
		"lever":
			return {"label": "COUNTERWEIGHT", "color": Color(0.35, 0.4, 0.5), "glow": Color(0.5, 0.7, 0.9),
				"msg": "// LIFT // counterweight set — gate up"}
		"decoy":
			return {"label": "DECOY BEACON", "color": Color(0.55, 0.4, 0.18), "glow": Color(1.0, 0.7, 0.2),
				"msg": "// DECOY // beacon lit — guard drawn off"}
	return {"label": "SWITCH", "color": Color(0.4, 0.4, 0.45), "glow": Color(0.7, 0.7, 0.8), "msg": "// CLEAR //"}

# The gate bar: a thin warped barrier across the branch between the switch and the pad. Cosmetic (the cache's
# enabled flag is the real lock) — it just reads the gate as closed; the switch hides it.
func _build_branch_gate_bar(mid: float) -> MeshInstance3D:
	return _add_warped_box(mid, BRANCH_GATE_LANE, Vector3(BRANCH_LANE_SPAN * 0.55, 1.0, 0.25),
		Color(0.45, 0.16, 0.18), Color(0.9, 0.2, 0.22), 0.7)

# The gate switch: a themed click-to-walk post at the neck. Authored FLAT (the host warp pass lifts it onto
# the helix); its post mesh + outline are children so they ride the warp. One-shot — firing it unlocks the branch.
func _build_branch_switch(g: int, mid: float, kind: String) -> Area3D:
	var theme := _branch_gate_theme(kind)
	var switch := _add_interactable(self, "BranchSwitch%d" % g, str(theme["label"]),
		Vector3(mid, 0.5, BRANCH_SWITCH_LANE), str(theme["label"]), "", 1.0, true, 1.4,
		Interactable.InteractableType.INSPECTION, false)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new(); pm.size = Vector3(0.4, 1.3, 0.4); post.mesh = pm
	post.material_override = _make_material(theme["color"], theme["glow"], 1.0)
	post.position = Vector3(0.0, 0.65, 0.0)
	switch.add_child(post)
	_outline_interactable_child(switch, post, "BranchSwitch%d" % g, 1.4)
	switch.interacted.connect(func() -> void: _on_branch_switch(g))
	return switch

# Activating a branch switch: unlock the cache, drop the gate bar, and (for a guarded branch) lure the guard
# off the pad — distract it (shrinks its reach) and pull its roam anchor back to the neck corner.
func _on_branch_switch(g: int) -> void:
	if g < 0 or g >= _branches.size():
		return
	var b: Dictionary = _branches[g]
	if bool(b.get("unlocked", false)):
		return
	b["unlocked"] = true
	if is_instance_valid(b.get("cache")):
		b["cache"].set_interaction_enabled(true)
	if is_instance_valid(b.get("gate_bar")):
		b["gate_bar"].visible = false
	_say(str(_branch_gate_theme(str(b.get("gate_kind", ""))).get("msg", "// CLEAR //")))
	var guard = b.get("guard")
	if is_instance_valid(guard):
		var gs = _get_game_state()
		if gs != null and gs.characters.has(guard.char_id):
			gs.set_character_distracted(guard.char_id, true)
		if guard.has_method("set_roam"):
			guard.set_roam(Vector3(float(b["mid_x"]) + 1.0, 0.5, BRANCH_NECK_LANE), 1.0)

# --- Threat layer: hide alcoves, flures, guards ---

func _build_threats() -> void:
	for a in HIDE_ALCOVES:
		var p: Vector3 = a["pos"]
		_add_box(self, Vector3(p.x, 2.0, p.z + 0.6), Vector3(2.4, 0.3, 1.2), Color(0.10, 0.10, 0.12))   # overhang roof
		_add_box(self, Vector3(p.x, 1.2, p.z + 1.1), Vector3(2.4, 2.4, 0.3), Color(0.11, 0.11, 0.13))   # back wall
		var glow := _add_box(self, Vector3(p.x, 0.03, p.z), Vector3(2.0, 0.05, 1.4), Color(0.08, 0.14, 0.18))
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.08, 0.14, 0.18); gm.emission_enabled = true
		gm.emission = Color(0.15, 0.45, 0.55); gm.emission_energy_multiplier = 0.5
		glow.material_override = gm
	for li in range(LURE_SPECS.size()):
		var lp: Vector3 = LURE_SPECS[li]["pos"]
		var idx := li
		# Click to walk over and fire the lure (discrete action, like lure_relay). The bulb is a CHILD of the
		# interactable so the visual + its outline ride the helix warp together.
		var dev := _add_interactable(self, "Flure%d" % li, "Fire flure", lp,
			"FLURE", "", 1.0, true, 1.4, Interactable.InteractableType.INSPECTION, false)
		dev.interacted.connect(func() -> void: _on_lure(idx))
		var bulb := _add_box(dev, Vector3(0.0, 0.7 - lp.y, 0.0), Vector3(0.5, 0.9, 0.5), Color(0.4, 0.25, 0.06))
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.4, 0.25, 0.06); bm.emission_enabled = true
		bm.emission = Color(1.0, 0.55, 0.12); bm.emission_energy_multiplier = 0.6
		bulb.material_override = bm
		_lure_meshes.append(bulb)
		_lure_until.append(-1.0)
		_outline_interactable_child(dev, bulb, "Flure%d" % li, 1.4)
	for spec in ENEMY_SPECS:
		_spawn_enemy(spec)

func _spawn_enemy(spec: Dictionary) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var enemy = EnemyScript.new()
	enemy.name = "Guard_%s" % str(spec["id"])
	enemy.position = spec["spawn"]
	enemy.move_speed = float(spec.get("speed", 3.0))
	enemy.detection_range = float(spec.get("range", 5.5))
	enemy.char_id = str(spec["id"])
	enemy.game_state = gs
	enemy._detection_targets.assign(PARTY_IDS)
	add_child(enemy)
	gs.register_character(enemy.char_id, enemy.position, enemy.move_speed, {"detection_range": enemy.detection_range})
	if enemy.has_method("activate"):
		enemy.activate()
	if str(spec.get("kind", "guard")) == "roam":
		enemy.set_roam(spec["spawn"], float(spec.get("radius", 2.6)))
	enemy.hit_target.connect(func(tid: String, _dmg: float) -> void: _on_enemy_hit(tid))
	_enemies.append(enemy)

func _enemy_spawn_for(id: String) -> Vector3:
	for spec in ENEMY_SPECS:
		if str(spec["id"]) == id:
			return spec["spawn"]
	if _branch_guard_spawns.has(id):
		return _branch_guard_spawns[id]
	return Vector3.ZERO

func _on_enemy_hit(target_id: String) -> void:
	if target_id in PARTY_IDS:
		_wash_character(target_id)   # the guard shoves you into the channel -> back to the start shelter
		_announce_wash()

func _on_lure(idx: int) -> void:
	if idx < 0 or idx >= LURE_SPECS.size():
		return
	var l: Dictionary = LURE_SPECS[idx]
	var target := str(l["target"])
	var lp: Vector3 = l["pos"]
	while _lure_until.size() <= idx:
		_lure_until.append(-1.0)
	_lure_until[idx] = _get_scheduler_tick() + LURE_DURATION
	_set_lure_emission(idx, 3.0)
	var gs = _get_game_state()
	if gs != null:
		for enemy in _enemies:
			if is_instance_valid(enemy) and enemy.char_id == target and gs.characters.has(target):
				gs.set_character_distracted(target, true)   # reach shrinks: it won't notice a runner keeping distance
				gs.command_move_to_pos(target, lp)           # and it walks off its post toward the song
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(LURE_DURATION, func() -> void: _on_lure_expired(idx), "wash_lure_%d" % idx)
	_say("// FLURE SINGS // guard drawn")

func _on_lure_expired(idx: int) -> void:
	if idx < _lure_until.size():
		_lure_until[idx] = -1.0
	_set_lure_emission(idx, 0.6)
	var target := str(LURE_SPECS[idx]["target"])
	var gs = _get_game_state()
	if gs != null and gs.characters.has(target):
		gs.set_character_distracted(target, false)
		gs.command_move_to_pos(target, _enemy_spawn_for(target))

func _set_lure_emission(idx: int, e: float) -> void:
	if idx < _lure_meshes.size() and is_instance_valid(_lure_meshes[idx]):
		var m := _lure_meshes[idx].material_override as StandardMaterial3D
		if m != null:
			m.emission_energy_multiplier = e

func _lure_active() -> bool:
	var now := _get_scheduler_tick()
	for u in _lure_until:
		if float(u) > now:
			return true
	return false

# --- Wash cadence (scheduler-driven; fires at exact ticks) ---

func _ensure_scheduled() -> void:
	if _scheduled:
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_scheduled = true
	_cadence_t0 = sched.get_current_tick()   # anchor the cadence to NOW (so a re-arm after reset stays consistent)
	for i in range(SECTIONS.size()):
		sched.schedule_after(FIRST_FLOOD + float(SECTIONS[i]["phase"]), _make_onset(i), "wash_onset_%d" % i)
		var lead := FIRST_FLOOD + float(SECTIONS[i]["phase"]) - TELEGRAPH_LEAD
		if lead > 0.0:
			sched.schedule_after(lead, _make_pretel(i), "wash_pretel_%d" % i)
	# The drain loop floods on its own recurring beat (self-rescheduling like a section, gated on "active").
	sched.schedule_after(FIRST_FLOOD + DRAIN_LOOP_PHASE, func() -> void: _drain_onset(), "wash_drain_onset")

func _make_onset(i: int) -> Callable:
	return func() -> void: _flood_onset(i)

func _make_pretel(i: int) -> Callable:
	return func() -> void: _pre_telegraph(i)

# The surge TELL: a beat before a section floods, its flow strip brightens to a warning glow so the player
# reads the coming surge instead of staring at dead water. Cosmetic only (strip energy) — never logged.
func _pre_telegraph(i: int) -> void:
	if _phase == "active" and not _flooding[i] and not _section_disabled(i):
		_set_strip(i, 1.1)

# COSMETIC tutorial preview on the flush section: a rising-then-receding ghost of the surge so the first-time
# player sees where the water breaks before it actually does. Spawns its OWN throwaway warped boxes (NOT the
# real _section_water — that stays driven by the scheduler, so the flood-visual/water-capture invariants hold)
# and tweens them up then back, then frees them. Pure visuals: it never touches _flooding or the cadence.
func _play_flush_hint(i: int = 0) -> void:
	_say("// FLUSH // surge incoming — read the water, then run it")
	_say("Watch—it breaks right here. Time it and run.", "ASTER")
	if not is_instance_valid(_flush_hint_root):
		_flush_hint_root = Node3D.new()
		_flush_hint_root.name = "FlushHint"
		add_child(_flush_hint_root)
	var s: Dictionary = SECTIONS[clampi(i, 0, SECTIONS.size() - 1)]   # ghost the section you keep failing
	var x0: float = s["x0"]; var x1: float = s["x1"]
	var n := maxi(2, int(ceil((x1 - x0) / WATER_SEG)))
	var segs: Array = []
	for k in range(n):
		var sc := lerpf(x0, x1, (k + 0.5) / float(n))
		var seg := _warped_box(_flush_hint_root, sc, 0.0,
			Vector3(FLOOR_Z_HALF * 1.8, WATER_THICK, (x1 - x0) / float(n) * 1.12),
			Color(0.10, 0.45, 0.7, 0.5), Color(0.3, 0.7, 1.0), 1.0, WATER_THICK * 0.45)
		seg.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		seg.scale = Vector3(1.0, 0.05, 1.0)
		segs.append(seg)
	# Rise the preview water up, hold a beat, recede — three pulses so the surge cadence reads clearly, then drop
	# the throwaway nodes. Driven on the wall-clock tween (cosmetic only): no game-state or step transition rides it.
	var tw := create_tween().set_parallel(false)
	for pulse in range(3):
		for seg in segs:
			if is_instance_valid(seg):
				tw.parallel().tween_property(seg, "scale", Vector3(1.0, 1.0, 1.0), 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.25)
		for seg in segs:
			if is_instance_valid(seg):
				tw.parallel().tween_property(seg, "scale", Vector3(1.0, 0.05, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_interval(0.2)
	tw.tween_callback(_clear_flush_hint)

func _clear_flush_hint() -> void:
	if is_instance_valid(_flush_hint_root):
		_flush_hint_root.queue_free()
		_flush_hint_root = null

# COSMETIC flood-ONSET accent (consistent with _play_flush_hint / _play_sweep_animation): when a section
# starts flooding, its real water segments rise-pop (a quick scale-in so the surge "arrives") and a few
# throwaway foam/spray blobs burst up off the surface, then fade + free. Pure eye-candy on the wall-clock
# tween (@rendering_only) — it touches NO game state, the cadence, _flooding, or visibility. The real
# segments' `visible` is already on (set in _flood_onset before this runs); _update keeps driving it.
func _play_water_surge(i: int) -> void:
	if i < 0 or i >= _section_water.size():
		return
	# Rise-pop the section's water segments: a brief vertical squash->settle so the flood reads as arriving.
	for seg in _section_water[i]:
		if is_instance_valid(seg):
			var rest: Vector3 = seg.scale
			seg.scale = Vector3(rest.x, rest.y * 0.15, rest.z)
			var st := create_tween()
			st.tween_property(seg, "scale", Vector3(rest.x, rest.y * 1.35, rest.z), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			st.tween_property(seg, "scale", rest, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Foam/spray burst: a handful of throwaway blobs lifting off the surge crest, then fading + freeing.
	if not is_instance_valid(_surge_root):
		_surge_root = Node3D.new()
		_surge_root.name = "WaterSurge"
		add_child(_surge_root)
	var s: Dictionary = SECTIONS[i]
	var x0: float = s["x0"]; var x1: float = s["x1"]
	var foam_col := Color(0.7, 0.95, 1.0)
	for k in range(4):
		var sc := lerpf(x0, x1, (k + 0.5) / 4.0)
		var lane := lerpf(-2.2, 2.2, float((k * 7) % 5) / 4.0)   # spread across the channel, deterministic
		var xf := _branch_warp_xform(sc, lane)
		xf.origin += xf.basis.y * (WATER_THICK * 0.45)
		var blob := _build_cosmetic_blob(_surge_root, xf.origin, Vector3(0.7, 0.5, 0.7),
			Color(foam_col.r, foam_col.g, foam_col.b, 0.85), foam_col, 1.8)
		var up: Vector3 = xf.origin + xf.basis.y * 1.6
		var tw := create_tween()
		tw.parallel().tween_property(blob, "global_position", up, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(blob, "scale", Vector3(1.8, 0.4, 1.8), 0.4).set_trans(Tween.TRANS_SINE)
		var m := blob.material_override as StandardMaterial3D
		if m != null:
			tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.4)
		tw.chain().tween_callback(func() -> void:
			if is_instance_valid(blob):
				blob.queue_free())

func _period(i: int) -> float:
	return float(SECTIONS[i].get("period", FLOW_PERIOD))

func _dur(i: int) -> float:
	return float(SECTIONS[i].get("dur", FLOOD_DURATION))

# Seconds until section i NEXT floods (the safe-window read a player — or a state-aware test — uses to time a
# crossing). Derived from the same cadence the onsets fire on: FIRST_FLOOD + phase + period*flood_count.
func _section_next_onset_in(i: int) -> float:
	var sched = _get_scheduler()
	if sched == null:
		return -1.0
	var now: float = sched.get_current_tick()
	var count: int = _flood_counts[i] if i < _flood_counts.size() else 0
	var next_tick := _cadence_t0 + FIRST_FLOOD + float(SECTIONS[i]["phase"]) + _period(i) * float(count)
	return next_tick - now

func _flood_onset(i: int) -> void:
	var sched = _get_scheduler()
	if _phase == "active" and not _section_disabled(i):
		_wash_section(i)
		_flooding[i] = true
		if i < _flood_counts.size():
			_flood_counts[i] += 1
		_set_strip(i, 2.6)
		_play_water_surge(i)            # COSMETIC: a foam/spray accent + rise-pop as the section floods
		if str(SECTIONS[i]["type"]) == "sluice":
			_set_sluice(i, true)            # the gate slams shut — the threshold is impassable
		if sched != null:
			sched.schedule_after(_dur(i), func() -> void: _set_flood_off(i), "wash_off_%d" % i)
	if sched != null:
		sched.schedule_after(_period(i), _make_onset(i), "wash_onset_%d" % i)
		var lead := _period(i) - TELEGRAPH_LEAD
		if lead > 0.0:
			sched.schedule_after(lead, _make_pretel(i), "wash_pretel_%d" % i)

func _set_flood_off(i: int) -> void:
	_flooding[i] = false
	_set_strip(i, 0.4)
	if i < SECTIONS.size() and str(SECTIONS[i]["type"]) == "sluice":
		_set_sluice(i, false)               # the gate lifts — the threshold opens again

func _section_disabled(i: int) -> bool:
	if bool(_override_locked[i]):
		return true
	var dis := str(SECTIONS[i]["disable"])
	if dis == "plate" or dis == "double_plate":
		return _plate_held[i]               # double_plate: _plate_held is true only when BOTH pads are held
	return false

# The sluice gate is a real movement BLOCKER: while closed, its threshold cells are non-walkable, so
# pathfinding refuses to route a character through (they wait / route around) — not just a wash hazard.
func _sluice_gate_cells(i: int) -> Array:
	var s: Dictionary = SECTIONS[i]
	var gate_x := (float(s["x0"]) + float(s["x1"])) * 0.5
	var gs = _get_game_state()
	var cells: Array = []
	if gs == null or gs.grid == null:
		return cells
	for wz in range(-3, 4):
		cells.append(gs.grid.world_to_grid(Vector3(gate_x, 0.0, float(wz))))
	return cells

func _set_sluice(i: int, closed: bool) -> void:
	if i >= _sluice_blocked.size():
		return
	_sluice_blocked[i] = closed
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	for cell in _sluice_gate_cells(i):
		if closed:
			gs.grid.add_dynamic_blocker(cell, "sluice_%d" % i)
		else:
			gs.grid.remove_dynamic_blocker(cell)

func _wash_section(i: int) -> void:
	var s: Dictionary = SECTIONS[i]
	var x0: float = s["x0"]; var x1: float = s["x1"]
	var washed_any := false
	for char_id in PARTY_IDS:
		if _washed.has(char_id):
			continue
		var p := _get_character_position(char_id)
		if p.x >= x0 and p.x <= x1 and abs(p.z) <= FLOOR_Z_HALF:
			_wash_character(char_id)
			washed_any = true
	if washed_any:
		_announce_wash()   # one line + one sweep tally for the whole event, however many members got caught
		# Per-section tally: the flush hint (a preview of where THIS section's surge breaks) only appears once a
		# SINGLE section has caught the party FLUSH_HINT_THRESHOLD times — you keep getting washed HERE, so here's
		# the read. It never fires on a startup timer; it's earned by repeated failure on the same section.
		if i < _section_wash_counts.size():
			_section_wash_counts[i] += 1
			if _section_wash_counts[i] >= FLUSH_HINT_THRESHOLD and not _flush_hint_shown:
				_flush_hint_shown = true
				_play_flush_hint(i)

func _wash_character(char_id: String) -> void:
	var gs = _get_game_state()
	if gs != null:
		gs.command_stop(char_id)   # cancel any in-flight move so the runner is carried off, not walking on
	# Capture the pre-wash RENDER position + the flat data position BEFORE the snap — the cosmetic streak slides
	# from where the current grabbed you, down the spiral, to the start. (Purely for the visual; the data snap
	# below is instant and authoritative — tests depend on it.)
	var pre_flat := _get_character_position(char_id)
	var pre_render := pre_flat
	if gs != null and gs.characters.has(char_id):
		pre_render = gs.get_render_position(char_id)
	# The flood carries you all the way DOWN the spiral to the start shelter at the bottom — water flows down,
	# so a wash washes you down. Mobile again on arrival (re-climb the gauntlet). _sweep_count tracks how rough.
	_set_character_position(char_id, START_POS)
	# COSMETIC ONLY: the current visibly carries you down the helix (a surge + a colour streak that follows the
	# curve to the start, then a splash). The body already snapped above — this is just the eye-candy.
	_play_sweep_animation(char_id, pre_render, pre_flat.x)

## One announcement + sweep tally per wash EVENT (not per character): washing the whole party at once is a
## single "// WASHED //" line, and the run-hint counts events, not bodies (3 washes, not 3 swept members).
func _announce_wash() -> void:
	_sweep_count += 1
	_say("// WASHED // the current carries you down to the start")
	# After a few washes the lesson lands diegetically: you can't walk the surges, you have to RUN them.
	if _sweep_count >= 3 and not _run_hint_shown:
		_run_hint_shown = true
		_say("Can't just calmly stroll past these channels. Water comes too often—we run it.", "ASTER")

# --- Drain loop flood + drown (the recurring hazard on the detour) ---

# The recurring loop surge. Mirrors _flood_onset: washes whatever's in the run AT THE TICK (so the decision is
# identical at 1x and 10x), flags the cosmetic flood window, and self-reschedules the next onset.
func _drain_onset() -> void:
	var sched = _get_scheduler()
	if _phase == "active":
		_wash_drain()
		_drain_flooding = true
		_drain_flood_count += 1
		if sched != null:
			# Re-check enemies across the visible flood WINDOW, not just this instant: a guard that's baited or
			# chased INTO the run mid-surge still drowns, so the lead-it-in kill can't depend on landing the one
			# onset tick. The sweeps ride the scheduler, so they're fast-forward invariant.
			for k in range(1, DRAIN_DROWN_SWEEPS + 1):
				sched.schedule_after(DRAIN_LOOP_DUR * float(k) / float(DRAIN_DROWN_SWEEPS),
					func() -> void: _drown_enemies_in_run(), "wash_drain_sweep_%d" % k)
			sched.schedule_after(DRAIN_LOOP_DUR, func() -> void: _set_drain_off(), "wash_drain_off")
	if sched != null:
		sched.schedule_after(DRAIN_LOOP_PERIOD, func() -> void: _drain_onset(), "wash_drain_onset")

func _set_drain_off() -> void:
	_drain_flooding = false

# Seconds until the loop next floods — analytic from the cadence (the safe-window read; mirrors _section_next_onset_in).
func _drain_next_onset_in() -> float:
	var sched = _get_scheduler()
	if sched == null:
		return -1.0
	var now: float = sched.get_current_tick()
	var next_tick := _cadence_t0 + FIRST_FLOOD + DRAIN_LOOP_PHASE + DRAIN_LOOP_PERIOD * float(_drain_flood_count)
	return next_tick - now

# Is a flat (s, lane) position inside the flooding run? (lane = flat z; the dry ledge sits OUTSIDE this band.)
func _in_drain_channel(p: Vector3) -> bool:
	return p.x >= DRAIN_LOOP_S0 and p.x <= DRAIN_LOOP_S1 and absf(p.z - DRAIN_RUN_LANE) <= DRAIN_RUN_HALF

# Decide the loop wash AT THE ONSET TICK: a party member caught in the run is washed to the start (same as a
# section); an ENEMY caught in the run is DROWNED — swept down the central drain and removed. Never per-frame.
func _wash_drain() -> void:
	var washed_any := false
	for char_id in PARTY_IDS:
		if _washed.has(char_id):
			continue
		if _in_drain_channel(_get_character_position(char_id)):
			_wash_character(char_id)
			washed_any = true
	if washed_any:
		_announce_wash()
	_drown_enemies_in_run()

# Drown every alive enemy currently standing in the flooding run. Called at the onset AND a few times across the
# flood window (the sweeps in _drain_onset), so a guard that walks/chases IN mid-surge is caught — the lead-it-in
# kill doesn't hinge on landing the single onset instant. Iterate a copy so _drown_enemy can schedule removal.
func _drown_enemies_in_run() -> void:
	for enemy in _enemies.duplicate():
		if is_instance_valid(enemy) and enemy.is_alive() and enemy.char_id != "" \
				and _in_drain_channel(_get_character_position(enemy.char_id)):
			_drown_enemy(enemy)

# Kill an enemy caught by the loop flood: real data-layer death (take_damage to 0 hp -> FSM 'dead', stops it,
# is_alive() flips false) decided at the onset tick, plus the cosmetic "current drags it down the drain" streak
# (the same inward-toward-centre sweep the party gets). The registered character + node are removed a beat
# later on the SCHEDULER (tick-locked, not a tween) so a re-run can respawn the guard.
func _drown_enemy(enemy) -> void:
	var id: String = enemy.char_id
	var gs = _get_game_state()
	var rp := _get_character_position(id)
	if gs != null and gs.characters.has(id):
		rp = gs.get_render_position(id)
		gs.command_stop(id)
	enemy.take_damage(enemy.max_hp)   # _hp -> 0, die() -> FSM 'dead' (stops moving, emits died); is_alive() == false
	_play_sweep_animation(id, rp, rp.x)   # cosmetic: the current carries it inward toward the central drain, dissolving
	_drowned_count += 1
	_say("// DRAINED // the current took the guard down the shaft")
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(DRAIN_KILL_DELAY, func() -> void: _remove_enemy(id), "wash_drain_kill_%s" % id)
	else:
		_remove_enemy(id)

# Fully remove a drowned enemy: drop it from _enemies, unregister its GameState character, free the node.
func _remove_enemy(id: String) -> void:
	var gs = _get_game_state()
	for i in range(_enemies.size() - 1, -1, -1):
		var e = _enemies[i]
		if is_instance_valid(e) and e.char_id == id:
			_enemies.remove_at(i)
			if gs != null and gs.has_method("unregister_character") and gs.characters.has(id):
				gs.unregister_character(id)
			e.queue_free()

# A drowned section/drain guard (removed mid-run) must come BACK on a reset/re-run — respawn any ENEMY_SPECS
# guard that's no longer present, before reset re-snaps the survivors. A guard that is still in _enemies but
# DEAD (drowned this run, its cosmetic-removal tick not yet elapsed) counts as missing: tear the dead body
# down and respawn a live one, so a reset always yields a LIVE guard regardless of the removal delay.
func _respawn_missing_enemies() -> void:
	for spec in ENEMY_SPECS:
		var id := str(spec["id"])
		var live := false
		for e in _enemies:
			if is_instance_valid(e) and e.char_id == id and e.is_alive():
				live = true
				break
		if not live:
			_remove_enemy(id)   # drop a lingering dead body (no-op if already gone)
			_spawn_enemy(spec)

# --- Drain loop: lead the guard in (bait, then chase) ---

# Fire the bait: the ledge guard commits and walks DOWN INTO the flooding run (the lure target is mid-run, IN the
# flood band — NOT the player's spot at the mouth, which would make the guard charge the baiter instead). It's
# distracted so it ignores the party at range, and it idles in the run for DRAIN_BAIT_PULL — a span longer than
# one flood PERIOD, so a surge is guaranteed to catch it there. The chase resumes after (a player still in the
# loop then keeps it in the current). The player clicks the bait from the SAFE mouth, then steps clear.
func _on_drain_bait() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var lure_flat := Vector3((DRAIN_LOOP_S0 + DRAIN_LOOP_S1) * 0.5, 0.5, DRAIN_RUN_LANE)   # mid-run, IN the flood band
	var committed := false
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.char_id == DRAIN_GUARD_ID and gs.characters.has(DRAIN_GUARD_ID):
			gs.set_character_distracted(DRAIN_GUARD_ID, true)
			# Pathfind across the run (a straight line would cut the corner) — _to_cell when the grid exists.
			if gs.grid != null:
				gs.command_move_to_cell(DRAIN_GUARD_ID, gs.grid.world_to_grid(lure_flat))
			else:
				gs.command_move_to_pos(DRAIN_GUARD_ID, lure_flat)
			committed = true
	if committed:
		_say("// BAIT // the guard takes the lure into the channel")
		var sched = _get_scheduler()
		if sched != null:
			sched.schedule_after(DRAIN_BAIT_PULL, func() -> void: _drain_chase_resume(), "wash_drain_bait")

# The bait window ends: clear the distraction so the guard's detection resumes — now a player in the loop is
# spotted and the guard CHASES them through the flooding run (it stays in the current).
func _drain_chase_resume() -> void:
	var gs = _get_game_state()
	if gs != null and gs.characters.has(DRAIN_GUARD_ID):
		gs.set_character_distracted(DRAIN_GUARD_ID, false)

func _on_drain_cache() -> void:
	_branch_loot += BRANCH_REWARD
	_say("// SALVAGE // drain cache stripped (%d)" % _branch_loot)

# COSMETIC "the current shoves you off the deck" flourish. The spiral winds around its central axis (the
# origin in XZ), so the WATER SOURCE is the OUTER wall — the side facing AWAY from the centre. A surge rises at
# that outer source and drives the caught member INWARD (toward the centre, away from the source), shrinking
# and fading as the current carries them off. Throwaway nodes, freed on completion. The real body already
# snapped to START — nothing here gates state; it's all eye-candy on the wall-clock tween (@rendering_only).
func _play_sweep_animation(char_id: String, from_render: Vector3, _from_x: float) -> void:
	if not is_instance_valid(_wash_anim_root):
		_wash_anim_root = Node3D.new()
		_wash_anim_root.name = "WashSweep"
		add_child(_wash_anim_root)
	var col: Color = PARTY_RENDER_COLORS.get(char_id, Color(0.6, 0.8, 1.0))
	# Inward = toward the spiral's central axis (origin in XZ); outward (= the water source) is the reverse.
	var inward := Vector3(-from_render.x, 0.0, -from_render.z)
	inward = inward.normalized() if inward.length() > 0.01 else Vector3(0, 0, -1)
	var outward := -inward
	var source := from_render + outward * 1.3 + Vector3(0.0, 0.35, 0.0)   # the surge wells up at the outer wall
	var push_to := from_render + inward * 3.2 - Vector3(0.0, 0.5, 0.0)     # shoved toward the centre + a touch down
	# Water surge at the outer source + the character-colour streak at the wash point.
	var surge := _build_cosmetic_blob(_wash_anim_root, source, Vector3(1.4, 0.7, 1.4),
		Color(0.10, 0.42, 0.66, 0.8), Color(0.3, 0.78, 1.0), 2.2)
	var streak := _build_cosmetic_blob(_wash_anim_root, from_render, Vector3(0.9, 0.9, 0.9),
		Color(col.r, col.g, col.b, 0.92), col, 2.6)
	var tw := create_tween()
	# Both driven INWARD (toward the centre, away from the source); the streak accelerates (EASE_IN) as it's
	# carried off, shrinking, while both fade out (albedo alpha + emission glow) so the member dissolves.
	tw.parallel().tween_property(surge, "global_position", from_render + inward * 1.6, 0.8).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(streak, "global_position", push_to, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(streak, "scale", Vector3(0.35, 0.35, 0.35), 0.85)
	var sm := streak.material_override as StandardMaterial3D
	var um := surge.material_override as StandardMaterial3D
	if sm != null:
		tw.parallel().tween_property(sm, "albedo_color:a", 0.0, 0.85).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(sm, "emission_energy_multiplier", 0.0, 0.85)
	if um != null:
		tw.parallel().tween_property(um, "albedo_color:a", 0.0, 0.7)
		tw.parallel().tween_property(um, "emission_energy_multiplier", 0.0, 0.7)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(surge):
			surge.queue_free()
		if is_instance_valid(streak):
			streak.queue_free())

func _build_cosmetic_blob(parent: Node3D, pos: Vector3, size: Vector3, color: Color, emission: Color, energy: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size = size; mesh.mesh = box
	var mat := _make_material(color, emission, energy, BaseMaterial3D.TRANSPARENCY_ALPHA)
	mesh.material_override = mat
	parent.add_child(mesh)
	mesh.global_position = pos
	return mesh

# --- Pipe-mouth splash planes ---

## A rough, lumpy splash-blob texture (white on transparent) — irregular radial edges + a ring of droplet
## specks, drawn deterministically (no wall-clock RNG) so it's stable. The material tints it the water colour.
func _build_splash_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var c := float(size) * 0.5
	var base_r := float(size) * 0.28
	for y in range(size):
		for x in range(size):
			var dx := float(x) - c
			var dy := float(y) - c
			var d := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)
			# lumpy radius from summed harmonics — an organic, splashy silhouette
			var lump := 1.0 + 0.20 * sin(ang * 5.0) + 0.13 * sin(ang * 8.0 + 1.3) + 0.08 * sin(ang * 13.0 + 2.1)
			var r := base_r * lump
			if d <= r:
				img.set_pixel(x, y, Color(1, 1, 1, clampf((r - d) / 6.0, 0.0, 1.0)))   # soft outer edge
	# a scatter of droplet specks flung beyond the blob rim
	for k in range(8):
		var a := float(k) / 8.0 * TAU + 0.4
		var rr := base_r * (1.25 + 0.3 * sin(a * 3.0))
		var px := int(c + cos(a) * rr)
		var py := int(c + sin(a) * rr)
		var dsz := 1 + (k % 3)
		for oy in range(-dsz, dsz + 1):
			for ox in range(-dsz, dsz + 1):
				if ox * ox + oy * oy <= dsz * dsz:
					var xx := px + ox
					var yy := py + oy
					if xx >= 0 and xx < size and yy >= 0 and yy < size:
						img.set_pixel(xx, yy, Color(1, 1, 1, 0.85))
	return ImageTexture.create_from_image(img)

## One splash billboard at each section's pipe mouth (above the section, on the back-wall/pipe side), warped
## onto the helix. Hidden by default; _update fades/scales it from the scheduler (lead-in + flood). Under a
## Node3D root so it survives hide_flat_graybox; render_priority above the perception overlay so it shows in data-view.
func _build_splash_planes() -> void:
	_splash_root = Node3D.new()
	_splash_root.name = "PipeSplashes"
	add_child(_splash_root)
	_splash_tex = _build_splash_texture()
	_splash_planes = []
	_splash_intensity = []
	for i in range(SECTIONS.size()):
		var cx: float = (float(SECTIONS[i]["x0"]) + float(SECTIONS[i]["x1"])) * 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _splash_tex
		mat.albedo_color = Color(0.62, 0.86, 1.0, 0.0)   # teal-white; alpha driven each frame
		mat.emission_enabled = true
		mat.emission = Color(0.35, 0.7, 1.0)
		mat.emission_energy_multiplier = 1.8
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.render_priority = 127   # draw after the perception overlay (like the flood water) so it reads in data-view
		var quad := QuadMesh.new()
		quad.size = Vector2(2.4, 2.4)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 2   # NO_GRID_DECAL_LAYER
		mi.visible = false
		_splash_root.add_child(mi)
		mi.global_position = ChannelsArc.arc_pos(cx, FLOOR_Z_HALF - 0.4) + Vector3(0.0, 3.3, 0.0)   # the pipe mouth
		_splash_planes.append(mi)
		_splash_intensity.append(0.0)

## Drive every pipe splash from the scheduler: ramp IN over the SPLASH_LEAD before the onset (so the water
## leads in instead of blinking), hold full while the section floods, ease out after. Eased per-frame (cosmetic).
func _update_pipe_splashes(delta: float) -> void:
	for i in range(_splash_planes.size()):
		var mi: MeshInstance3D = _splash_planes[i]
		if mi == null or not is_instance_valid(mi):
			continue
		var target := 0.0
		if i < _flooding.size() and _flooding[i]:
			target = 1.0
		elif not _section_disabled(i):
			var until := _section_next_onset_in(i)
			if until > 0.0 and until <= SPLASH_LEAD:
				target = (1.0 - until / SPLASH_LEAD) * 0.7   # building warning, up to 0.7 just before onset
		_splash_intensity[i] = move_toward(float(_splash_intensity[i]), target, delta * SPLASH_SMOOTH)
		var inten: float = _splash_intensity[i]
		mi.visible = inten > 0.02
		if mi.visible:
			var sc := 0.55 + 0.85 * inten
			mi.scale = Vector3(sc, sc, sc)
			var m := mi.material_override as StandardMaterial3D
			if m != null:
				m.albedo_color.a = clampf(inten * 1.15, 0.0, 1.0)

# --- Interactions ---

func _on_override(i: int) -> void:
	if i < 0 or i >= _override_locked.size():
		return
	_override_locked[i] = true
	_set_flood_off(i)
	_set_strip(i, 0.15)
	_say("// SECTION %d FLOW // OVERRIDE ENGAGED" % (i + 1))

func _recover_washed() -> int:
	var n := _washed.size()
	for char_id in _washed.keys():
		_set_character_position(char_id, RETURN_LANDING)
	_washed.clear()
	return n

func _on_terminal() -> void:
	var n := _recover_washed()
	_say("// TERMINAL // %d crew telephoned up" % n if n > 0 else "// TERMINAL // no crew stranded")

func _on_sloperope() -> void:
	_sloperope_deployed = true
	if is_instance_valid(_rope_mesh):
		_rope_mesh.visible = true
	_say("// SLOPEROPE DROPPED // climb it from the start")

func _on_climb() -> void:
	if not _sloperope_deployed:
		_say("// NO LINE // drop the sloperope from the chunk end first")
		return
	var n := _recover_washed()
	if n > 0:
		_say("// CLIMBED UP // %d crew recovered" % n)

func _set_strip(i: int, energy: float) -> void:
	if i < _flow_strips.size() and is_instance_valid(_flow_strips[i]):
		var mat := _flow_strips[i].material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = energy

# --- Lifecycle ---

func _process(delta: float) -> void:
	_update(delta)

func headless_process(delta: float) -> void:
	_update(delta)

# The pad footprint(s) a section needs HELD to disable it. A plain plate has one; a double_plate has two
# (at ±DOUBLE_PLATE_Z), so two members must stay while the third crosses.
func _plate_footprints(i: int) -> Array:
	var px := float(SECTIONS[i]["x0"]) - 1.2
	if str(SECTIONS[i]["disable"]) == "double_plate":
		return [Vector2(px, -DOUBLE_PLATE_Z), Vector2(px, DOUBLE_PLATE_Z)]
	return [Vector2(px, 0.0)]

## Run with CHANNELS_DEBUG=1 to log each party member's flat DATA position and its warped RENDER position
## (where the node should sit on the helix) once or twice a second — for tracing anomalies like a member
## ending up below the deck.
func _debug_log_positions() -> void:
	if not OS.has_environment("CHANNELS_DEBUG"):
		return
	_debug_tick += 1
	if _debug_tick % 30 != 0:
		return
	var gsd = _get_game_state()
	if gsd == null:
		return
	for cid in PARTY_IDS:
		if gsd.characters.has(cid):
			var d: Vector3 = gsd.get_position(cid)
			var r: Vector3 = gsd.get_render_position(cid)
			print("[channels] %-6s data=(%5.1f,%4.1f,%5.1f) render=(%6.1f,%5.1f,%6.1f) moving=%s" % [cid, d.x, d.y, d.z, r.x, r.y, r.z, gsd.is_moving(cid)])

func _update(delta := 0.0) -> void:
	if _phase == "ready":
		_phase = "active"
	_ensure_scheduled()
	_debug_log_positions()
	_update_pipe_splashes(delta)
	# refresh plate-held state — a section is held only when EVERY one of its pads has a member on it
	for i in range(SECTIONS.size()):
		var dis := str(SECTIONS[i]["disable"])
		if dis != "plate" and dis != "double_plate":
			continue
		var all_held := true
		for fp in _plate_footprints(i):
			var pad_held := false
			for char_id in PARTY_IDS:
				if _washed.has(char_id):
					continue
				var p := _get_character_position(char_id)
				if abs(p.x - fp.x) <= PLATE_RADIUS and abs(p.z - fp.y) <= PLATE_RADIUS:
					pad_held = true
					break
			if not pad_held:
				all_held = false
				break
		if all_held != _plate_held[i]:
			_plate_held[i] = all_held
			_set_strip(i, 0.15 if all_held else 0.4)
	# hide alcoves: a party member tucked in a nook is fully concealed from the guards
	var gsc = _get_game_state()
	if gsc != null and not _enemies.is_empty():
		for cid in PARTY_IDS:
			if not gsc.characters.has(cid):
				continue
			var cp := _get_character_position(cid)
			var hidden := false
			for a in HIDE_ALCOVES:
				if Vector2(cp.x - a["pos"].x, cp.z - a["pos"].z).length() <= float(a["radius"]):
					hidden = true
					break
			gsc.set_character_concealment(cid, GameState.CONCEAL_FULL if hidden else GameState.CONCEAL_NONE)
	# Aster's TRACE read: while active, pulse the traced section's strip a beat BEFORE its next onset so the
	# safe window is legible (the telegraph). Cosmetic only — the cadence itself is unchanged.
	var schd = _get_scheduler()
	if _trace_section >= 0 and schd != null:
		var now: float = schd.get_current_tick()
		if now >= _trace_until:
			_trace_section = -1
		elif not _flooding[_trace_section] and not _section_disabled(_trace_section):
			_set_strip(_trace_section, 1.3)   # the pre-surge read glow
	# Flood WATER + sluice gate visibility — the in-game flood feedback. Driven by the scheduler-set _flooding /
	# _sluice_blocked (so it's replay-safe + fast-forward invariant); the per-frame work is just the toggle, so
	# the surging water you got washed by is always VISIBLE (and the sluice gate reads open vs closed).
	for i in range(_section_water.size()):
		var flooding: bool = i < _flooding.size() and _flooding[i]
		for seg in _section_water[i]:
			if is_instance_valid(seg):
				seg.visible = flooding
	for seg in _drain_water:
		if is_instance_valid(seg):
			seg.visible = _drain_flooding
	for gi in _sluice_gate.keys():
		if is_instance_valid(_sluice_gate[gi]):
			_sluice_gate[gi].visible = gi < _sluice_blocked.size() and bool(_sluice_blocked[gi])
	if _phase == "active":
		var all_through := true
		for char_id in PARTY_IDS:
			if _get_character_position(char_id).x < CHUNK_END_X:
				all_through = false
				break
		if all_through:
			_phase = "complete"
			_say("// CHUNK CLEAR")

# --- Scene/preview interface ---

## The modeled environment this gauntlet plays inside — the textured channels spiral. It is built along
## the SAME helix as ChannelsArc, so arc_pos(section x, lane z) lands each section on its set piece.
func get_environment_model() -> String:
	return "res://resources/models/channels/channels.glb"

## Installing this on GameState moves the playable system ONTO the helix: the data layer stays flat,
## node followers render through it, and a click on the GLB deck maps back to a flat (s, lane) target.
func get_coord_map():
	return ChannelsCoordMap.new()

## With the textured GLB as the environment, the flat graybox geometry would double the set pieces and
## float below the helix — hide it. Only this chunk's own DIRECT meshes go; the meshless interaction
## zones stay live and the guard nodes (which render through the warp) are untouched.
func hide_flat_graybox() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = false

func get_scene_title() -> String:
	return "Wash Relay"

func get_scene_help() -> String:
	return "A long gauntlet of timed water hazards, each on its own beat. Override the flush/jet/basin, hold the plate (and the DOUBLE plate — two members stay) for the bridges, time the fast current and the sluice. Guards prowl the back half: hide in an alcove to slip a roamer, fire the flure to draw the sentry off its chokepoint, and watch the guarded basin. A guard's hit, or standing in a flooding section, shoves you back to the start shelter — telephone up or drop the sloperope to recover."

func get_default_character() -> String:
	return "endo"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_grid_data() -> Dictionary:
	# The main deck lane, plus one OUTWARD spur per gap (lane 3.5..10) — the branch offshoots. Each spur
	# overlaps the deck rim (lane 4) so it's path-connected; the height grows to admit the outer lane.
	var regions: Array = [{"min": [FLOOR_MIN_X, -FLOOR_Z_HALF], "max": [FLOOR_MAX_X, FLOOR_Z_HALF]}]
	for mid in _gap_mids():
		regions.append({"min": [float(mid) - BRANCH_HALF_S, BRANCH_NECK_LANE], "max": [float(mid) + BRANCH_HALF_S, BRANCH_OUTER_LANE]})
	# The drain loop: entry/exit legs (overlap the deck rim -> connected), the flooding run between them, and
	# the stub out to the dry salvage ledge across the water. Authored flat in (s, lane) exactly like the branches.
	var drain_mid := (DRAIN_LOOP_S0 + DRAIN_LOOP_S1) * 0.5
	regions.append({"min": [DRAIN_LOOP_S0 - 0.8, BRANCH_NECK_LANE], "max": [DRAIN_LOOP_S0 + 0.8, DRAIN_RUN_LANE + 0.6]})
	regions.append({"min": [DRAIN_LOOP_S1 - 0.8, BRANCH_NECK_LANE], "max": [DRAIN_LOOP_S1 + 0.8, DRAIN_RUN_LANE + 0.6]})
	regions.append({"min": [DRAIN_LOOP_S0 - 0.8, DRAIN_RUN_LANE - DRAIN_RUN_HALF], "max": [DRAIN_LOOP_S1 + 0.8, DRAIN_RUN_LANE + DRAIN_RUN_HALF]})
	regions.append({"min": [drain_mid - 1.1, DRAIN_RUN_LANE - 0.3], "max": [drain_mid + 1.1, DRAIN_LEDGE_LANE + 0.6]})
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [-2.0, 0.0, -6.0], "cell_size": 1.0, "width": 92, "height": 18,
		"walkable_regions": regions,
	}

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors["start_shelter"] = START_POS
	anchors["chunk_end"] = Vector3(CHUNK_END_X + 1.0, 0.5, 0.0)
	anchors["terminal"] = TERMINAL_POS
	anchors["sloperope"] = SLOPEROPE_POS
	anchors["climb_line"] = CLIMB_POS
	for i in range(SECTIONS.size()):
		anchors["section_%s" % SECTIONS[i]["type"]] = Vector3((float(SECTIONS[i]["x0"]) + float(SECTIONS[i]["x1"])) * 0.5, 0.5, 0.0)
	for ai in range(HIDE_ALCOVES.size()):
		anchors["hide_alcove_%d" % ai] = HIDE_ALCOVES[ai]["pos"]
	for li in range(LURE_SPECS.size()):
		anchors["flure_%d" % li] = LURE_SPECS[li]["pos"]
	for b in _branches:
		anchors["branch_%d" % int(b["gap"])] = Vector3(float(b["mid_x"]), 0.5, float(b["pad_lane"]))
	var drain_mid := (DRAIN_LOOP_S0 + DRAIN_LOOP_S1) * 0.5
	anchors["drain_run"] = Vector3(drain_mid, 0.5, DRAIN_RUN_LANE)              # mid of the flooding run
	anchors["drain_ledge"] = Vector3(drain_mid, 0.5, DRAIN_LEDGE_LANE)          # the dry salvage ledge + guard post
	anchors["drain_bait"] = Vector3(DRAIN_LOOP_S0, 0.5, BRANCH_NECK_LANE + 0.8) # the bait at the loop mouth
	anchors["drain_entry"] = Vector3(DRAIN_LOOP_S0, 0.5, BRANCH_NECK_LANE)      # where the loop leaves the deck
	anchors["drain_exit"] = Vector3(DRAIN_LOOP_S1, 0.5, BRANCH_NECK_LANE)       # where it rejoins
	return anchors

func get_preview_time_state() -> Dictionary:
	return {"day": 2, "time": 0.5, "routing_mode": "safe",
		"note_default": "Read the flood beat. Override the flush/jet, hold the plate for the bridge, time the current and the sluice."}

func get_preview_abilities() -> Array:
	# Display names + tuning come from data/abilities/en/abilities.xlsx (channels_rhythm.* rows): aster_focus=
	# TRACE, peris_tune=BLOOM, endo_patch=BRACE. The preview shell already registers the three keys; this just
	# gives them the channels' names/notes. The EFFECTS live in handle_preview_ability below.
	return AbilityData.for_context(ABILITY_CONTEXT)

# The three protagonists' signature reads. Returns a Dict merged over the ability def + applied by the preview
# (note text, per-character stat deltas). Owner stat deltas (aster +atp, peris +sta, endo +hp) auto-apply
# upstream; here we add the channels-specific EFFECT. Pure derived state — replay/fast-forward safe.
func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	match ability_id:
		"aster_focus":
			return _ability_trace()
		"peris_tune":
			return _ability_bloom()
		"endo_patch":
			return _ability_brace()
	return {}

# TRACE — Aster reads the cadence: find the section he's in (or the next ahead) and surface its safe window.
func _ability_trace() -> Dictionary:
	var x := _owner_x("aster_focus")
	var i := _section_index_at(x)
	if i < 0:
		i = _next_section_ahead(x)
	if i < 0:
		return {"note": "// TRACE // open water ahead — no surge to read"}
	_trace_section = i
	var sched = _get_scheduler()
	_trace_until = (sched.get_current_tick() if sched != null else 0.0) + TRACE_HOLD
	var label := str(SECTIONS[i]["type"]).to_upper()
	if _section_disabled(i):
		return {"note": "// TRACE // %s held open — cross now" % label}
	return {"note": "// TRACE // %s surges on a %.1fs beat — cross right after the next surge" % [label, _period(i)]}

# BLOOM — Peris tends flora: grow a persistent bioluminescent light at her spot. It lights the dark drainage
# and marks a safe lane (the dark section can only be read once it's bloomed).
func _ability_bloom() -> Dictionary:
	var gs = _get_game_state()
	if gs == null:
		return {"note": "// BLOOM //"}
	var flat: Vector3 = gs.get_position("peris")
	var world: Vector3 = gs.get_render_position("peris") if gs.coord_map != null else flat
	_spawn_bloom(world, flat)
	return {"note": "// BLOOM // bioluminescence takes — the lane reads clear"}

# BRACE — Endo braces the party: refund stamina to any washed/lower-deck member for the re-cross, and mark the
# deep hide alcove. If nobody's down, it still steadies the party (the owner hp refund applies upstream).
func _ability_brace() -> Dictionary:
	var result := {}
	var deltas := {}
	for id in _washed.keys():
		deltas[id] = {"sta_delta": 14.0}
	if not deltas.is_empty():
		result["characters"] = deltas
		result["note"] = "// BRACE // %d down — steadied for the climb back" % deltas.size()
	else:
		result["note"] = "// BRACE // the party reads the deep cover"
	return result

# The section whose [x0,x1] footprint contains x (flat s-axis), or -1.
func _section_index_at(x: float) -> int:
	for i in range(SECTIONS.size()):
		if x >= float(SECTIONS[i]["x0"]) and x <= float(SECTIONS[i]["x1"]):
			return i
	return -1

# The first section starting ahead of x, or -1.
func _next_section_ahead(x: float) -> int:
	for i in range(SECTIONS.size()):
		if float(SECTIONS[i]["x0"]) > x:
			return i
	return -1

func _owner_x(ability_id: String) -> float:
	var gs = _get_game_state()
	var owner := str(ABILITY_OWNERS.get(ability_id, ""))
	if gs != null and owner != "" and gs.characters.has(owner):
		return gs.get_position(owner).x
	return 0.0

# Grow a flora light (a small emissive bloom + an omni light) at a warped world position. Stored so it
# persists for the run and is cleared on reset. Cosmetic light; the "lane reads clear" is the gameplay read.
func _spawn_bloom(world: Vector3, flat: Vector3) -> void:
	if _bloom_root == null or not is_instance_valid(_bloom_root):
		_bloom_root = Node3D.new()
		_bloom_root.name = "Blooms"
		add_child(_bloom_root)
	var node := Node3D.new()
	node.position = world + Vector3(0.0, 0.2, 0.0)
	var mesh := MeshInstance3D.new()
	var sph := SphereMesh.new(); sph.radius = 0.22; sph.height = 0.44; mesh.mesh = sph
	mesh.material_override = _make_material(Color(0.2, 0.7, 0.5), Color(0.4, 1.0, 0.7), 2.2)
	node.add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 1.0, 0.75)
	light.light_energy = 2.2
	light.omni_range = 6.0
	light.position = Vector3(0.0, 0.6, 0.0)
	node.add_child(light)
	_bloom_root.add_child(node)
	_blooms.append({"pos": flat, "node": node})

func get_preview_overlay_status(_overlay_id: String, _current_tick: float) -> Array:
	return []

func reset_preview_state() -> void:
	var n := SECTIONS.size()
	# The host scheduler PERSISTS across an in-place reset, and every hazard onset self-reschedules forever — so a
	# reset must CANCEL the live cadence and re-arm it, or the old (un-rebased) chain keeps firing while the
	# analytic safe-window reads recompute from the zeroed counts (predicted vs real onset drift). Cancel every
	# recurring tag + the pending drowned-guard removals, then clear _scheduled so _ensure_scheduled re-anchors
	# the whole cadence to the post-reset 'now' (matching a fresh boot).
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("wash_drain_onset"); sched.cancel_tag("wash_drain_off"); sched.cancel_tag("wash_drain_bait")
		for k in range(1, DRAIN_DROWN_SWEEPS + 1):
			sched.cancel_tag("wash_drain_sweep_%d" % k)
		for i in range(n):
			sched.cancel_tag("wash_onset_%d" % i); sched.cancel_tag("wash_off_%d" % i); sched.cancel_tag("wash_pretel_%d" % i)
		for spec in ENEMY_SPECS:
			sched.cancel_tag("wash_drain_kill_%s" % str(spec["id"]))
	_scheduled = false   # _ensure_scheduled re-arms (and re-captures _cadence_t0) on the next _update
	# A guard drowned in the drain loop was unregistered + freed — bring it (and any other missing spec guard) back
	# before the re-snap below assumes every guard still exists.
	_respawn_missing_enemies()
	_phase = "ready"
	_override_locked = []; _flooding = []; _plate_held = []; _sluice_blocked = []; _flood_counts = []; _section_wash_counts = []
	for i in range(n):
		_override_locked.append(false); _flooding.append(false); _plate_held.append(false); _sluice_blocked.append(false); _flood_counts.append(0); _section_wash_counts.append(0)
	# Pipe-mouth splashes back to rest (no lead-in showing).
	for i in range(_splash_intensity.size()):
		_splash_intensity[i] = 0.0
	for mi in _splash_planes:
		if is_instance_valid(mi):
			mi.visible = false
	# Drain-loop run state.
	_drain_flooding = false
	_drain_flood_count = 0
	_drowned_count = 0
	for seg in _drain_water:
		if is_instance_valid(seg):
			seg.visible = false
	_washed.clear()
	_sweep_count = 0
	_run_hint_shown = false
	_sloperope_deployed = false
	# Ability state is derived per-run — clear it so a reset/replay doesn't leak a stale TRACE read or blooms.
	_trace_section = -1
	_trace_until = 0.0
	for segs in _section_water:
		for seg in segs:
			if is_instance_valid(seg):
				seg.visible = false
				seg.scale = Vector3.ONE   # clear any in-flight surge rise-pop so a reset can't strand a squashed segment
	for gi in _sluice_gate.keys():
		if is_instance_valid(_sluice_gate[gi]):
			_sluice_gate[gi].visible = false
	_blooms.clear()
	if is_instance_valid(_bloom_root):
		_bloom_root.queue_free()
		_bloom_root = null
	# Cosmetic flourishes: re-arm the one-time flush hint and drop any in-flight preview / sweep streak nodes so a
	# reset mid-animation can't strand a half-played pulse or a lingering surge box.
	_flush_hint_shown = false
	if is_instance_valid(_flush_hint_root):
		_flush_hint_root.queue_free()
		_flush_hint_root = null
	if is_instance_valid(_wash_anim_root):
		_wash_anim_root.queue_free()
		_wash_anim_root = null
	if is_instance_valid(_surge_root):
		_surge_root.queue_free()
		_surge_root = null
	_branch_loot = 0
	for b in _branches:
		b["collected"] = false
		var gated := str(b.get("gate_kind", "open")) != "open"
		b["unlocked"] = not gated
		if is_instance_valid(b.get("cache")) and b["cache"].has_method("reset"):
			b["cache"].reset()
		if gated and is_instance_valid(b.get("cache")):
			b["cache"].set_interaction_enabled(false)   # re-lock (reset() re-enabled it)
		if is_instance_valid(b.get("switch")) and b["switch"].has_method("reset"):
			b["switch"].reset()
		if is_instance_valid(b.get("gate_bar")):
			b["gate_bar"].visible = true
		# Send any branch guard back to roaming its pad (the decoy may have pulled its anchor to the neck).
		if is_instance_valid(b.get("guard")) and b["guard"].has_method("set_roam"):
			b["guard"].set_roam(Vector3(float(b["mid_x"]), 0.5, BRANCH_PAD_LANE), 1.6)
	if is_instance_valid(_rope_mesh):
		_rope_mesh.visible = false
	for i in range(_lure_until.size()):
		_lure_until[i] = -1.0
	var gs = _get_game_state()
	if gs != null:
		if gs.grid != null:
			for i in range(n):
				if str(SECTIONS[i]["type"]) == "sluice":
					for cell in _sluice_gate_cells(i):
						gs.grid.remove_dynamic_blocker(cell)
		for char_id in PARTY_IDS:
			if gs.characters.has(char_id):
				gs.snap_character_to(char_id, SPAWNS.get(char_id, START_POS))
				gs.set_character_concealment(char_id, GameState.CONCEAL_NONE)
		for enemy in _enemies:
			if is_instance_valid(enemy) and gs.characters.has(enemy.char_id):
				gs.set_character_distracted(enemy.char_id, false)
				gs.snap_character_to(enemy.char_id, _enemy_spawn_for(enemy.char_id))
	for i in range(_flow_strips.size()):
		_set_strip(i, 0.4)
	for i in range(_lure_meshes.size()):
		_set_lure_emission(i, 0.6)
	_set_preview_step("wash_relay_briefing")

func get_preview_state() -> Dictionary:
	var secs: Array = []
	for i in range(SECTIONS.size()):
		secs.append({"type": SECTIONS[i]["type"], "disable": SECTIONS[i]["disable"],
			"x0": float(SECTIONS[i]["x0"]), "x1": float(SECTIONS[i]["x1"]),   # footprint along the spiral (s)
			"flooding": _flooding[i] if i < _flooding.size() else false,
			"disabled": _section_disabled(i), "overridden": _override_locked[i] if i < _override_locked.size() else false,
			"plate_held": _plate_held[i] if i < _plate_held.size() else false,
			"sluice_blocked": _sluice_blocked[i] if i < _sluice_blocked.size() else false,
			"period": _period(i), "dur": _dur(i), "flood_count": _flood_counts[i] if i < _flood_counts.size() else 0,
			"next_onset_in": _section_next_onset_in(i)})   # seconds until this section next floods (the safe-window read)
	var guards: Array = []
	var gs = _get_game_state()
	var branch_guard_count := 0
	var drain_guard := {}
	# `guards` / `enemy_count` describe the SECTION threat layer; branch-offshoot guards AND the drain-loop guard
	# are reported separately (branch_guard_count / drain_guard) so the section semantics stay stable.
	for enemy in _enemies:
		if not is_instance_valid(enemy):
			continue
		if _branch_guard_spawns.has(enemy.char_id):
			branch_guard_count += 1
			continue
		if enemy.char_id == DRAIN_GUARD_ID:
			drain_guard = {
				"id": DRAIN_GUARD_ID, "alive": enemy.is_alive(),
				"state": (enemy.get_state() if enemy.has_method("get_state") else ""),
				"distracted": (gs != null and gs.is_character_distracted(DRAIN_GUARD_ID)),
			}
			continue
		guards.append({
			"id": enemy.char_id, "alive": enemy.is_alive(),
			"state": (enemy.get_state() if enemy.has_method("get_state") else ""),
			"distracted": (gs != null and gs.is_character_distracted(enemy.char_id)),
		})
	var hidden_ids: Array = []
	if gs != null:
		for cid in PARTY_IDS:
			if gs.characters.has(cid) and gs.get_character_concealment(cid) >= GameState.CONCEAL_FULL:
				hidden_ids.append(cid)
	var branches: Array = []
	for b in _branches:
		branches.append({
			"gap": int(b["gap"]), "mid_x": float(b["mid_x"]), "pad_lane": float(b["pad_lane"]),
			"archetype": str(b["archetype"]), "content_count": int(b["content_count"]),
			"collected": bool(b.get("collected", false)),
			"guarded": is_instance_valid(b.get("guard")),
			"gate_kind": str(b.get("gate_kind", "open")), "gated": str(b.get("gate_kind", "open")) != "open",
			"unlocked": bool(b.get("unlocked", true)),
		})
	return {
		"phase": _phase, "complete": _phase == "complete",
		"sections": secs, "section_count": SECTIONS.size(),
		"washed_count": _washed.size(), "washed": _washed.keys(),
		"flow_period": FLOW_PERIOD, "flood_duration": FLOOD_DURATION,
		"enemy_count": guards.size(), "guards": guards,
		"lure_active": _lure_active(), "hidden": hidden_ids,
		"sloperope_deployed": _sloperope_deployed,
		"branches": branches, "branch_count": _branches.size(), "branch_loot": _branch_loot,
		"branch_guard_count": branch_guard_count,
		"trace_section": _trace_section, "bloom_count": _blooms.size(),
		"sweep_count": _sweep_count, "section_wash_counts": _section_wash_counts.duplicate(),
		"flush_hint_shown": _flush_hint_shown,
		"water_shown": _water_shown_state(),
		"drain_flooding": _drain_flooding, "drain_next_onset_in": _drain_next_onset_in(),
		"drowned_count": _drowned_count, "drain_guard": drain_guard,
	}

# Per-section: is the flood water currently visible? (Drives the flood-visual test + any HUD read.)
func _water_shown_state() -> Array:
	var out: Array = []
	for segs in _section_water:
		out.append(not segs.is_empty() and is_instance_valid(segs[0]) and segs[0].visible)
	return out
