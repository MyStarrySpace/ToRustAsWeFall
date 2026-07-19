extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

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

const ChannelsArc := preload("res://scripts/game/world/channels_arc.gd")
const StretchGenerator := preload("res://scripts/generation/stretch_generator.gd")
const WaterShader := preload("res://resources/channels_water.gdshader")
const WaterTexV0 := preload("res://resources/models/channels/channels_water_v0.png")
const WaterTexV1 := preload("res://resources/models/channels/channels_water_v1.png")

# The LEVEL DATA (environment model + section layout + level tunables). The .tres is the authoritative source;
# the values below are fallbacks. Read into member vars (initialized at instantiation, before get_grid_data /
# _build_chunk) so the ~200 downstream references (SECTIONS[i], FLOW_PERIOD, …) are unchanged. The warp/flood/
# branch/drain MECHANICS stay in this subclass — the "thin logic" half of the hybrid.
const FRAGMENT := preload("res://data/fragments/wash_relay.tres")

const PARTY_IDS := ["aster", "peris", "endo"]
var SPAWNS: Dictionary = FRAGMENT.spawns
var SECTIONS: Array = FRAGMENT.params.get("sections", [])
var START_POS: Vector3 = FRAGMENT.params.get("start_pos", Vector3(3.0, 0.5, 0.0))
var FLOOR_Z_HALF: float = FRAGMENT.params.get("floor_z_half", 4.0)
var FLOOR_MIN_X: float = FRAGMENT.params.get("floor_min_x", -1.0)
var FLOOR_MAX_X: float = FRAGMENT.params.get("floor_max_x", 87.0)
var CHUNK_END_X: float = FRAGMENT.params.get("chunk_end_x", 84.0)
var TERMINAL_POS: Vector3 = FRAGMENT.params.get("terminal_pos", Vector3(84.0, 0.5, 2.5))
var SLOPEROPE_POS: Vector3 = FRAGMENT.params.get("sloperope_pos", Vector3(84.0, 0.5, -2.5))
var CLIMB_POS: Vector3 = FRAGMENT.params.get("climb_pos", Vector3(5.0, 0.5, 2.5))
var RETURN_LANDING: Vector3 = FRAGMENT.params.get("return_landing", Vector3(83.0, 0.5, 0.0))
var FLOW_PERIOD: float = FRAGMENT.params.get("flow_period", 6.0)
var FLOOD_DURATION: float = FRAGMENT.params.get("flood_duration", 1.4)
var FIRST_FLOOD: float = FRAGMENT.params.get("first_flood", 2.5)
const PLATE_RADIUS := 1.4           # how close a character must be to "hold" a plate
const DOUBLE_PLATE_Z := 2.5         # the two pads of a double-plate sit at ±this z

# --- Threat layer (guards / hide alcoves / lures, laid over the guarded sections) — authored data ---
var HIDE_ALCOVES: Array = FRAGMENT.params.get("hide_alcoves", [])
var ENEMY_SPECS: Array = FRAGMENT.params.get("enemy_specs", [])
var LURE_SPECS: Array = FRAGMENT.params.get("lure_specs", [])
var LURE_DURATION: float = FRAGMENT.params.get("lure_duration", 9.0)

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

# --- Authored transit breaks ---------------------------------------------------------------
# The old relay was one uninterrupted curl: even with optional salvage spokes, the mandatory read was
# simply walking the next wet strip. These two composed routes give the coil a different spatial verb without
# disturbing the proven ChannelsArc mapping:
#   * a PORTAL pressure-room tucked toward the centre vents the upcoming jet for a generous window;
#   * a slow covered CRAWL loop bulges outside the coil and rejoins beyond the timed sluice.
# Both are genuine choices: the direct wet route remains the fast route, while the set piece is safer and
# costs traversal time. Positions below are DATA-space (s, y, lane); the transit objects own the conversion.
const PRESSURE_GAP_S0 := 19.7
const PRESSURE_GAP_S1 := 21.6
const PRESSURE_PORTAL_ENTRY := Vector3(19.0, 0.5, -3.0)
const PRESSURE_ROOM_ARRIVAL := Vector3(22.5, 0.5, -7.2)
const PRESSURE_ROOM_RETURN := Vector3(25.0, 0.5, -7.2)
const PRESSURE_PORTAL_LANDING := Vector3(22.25, 0.5, -3.0)
const PRESSURE_VALVE_POS := Vector3(24.0, 0.5, -9.0)
const PRESSURE_ROOM_CENTER := Vector3(23.7, 0.5, -8.1)
const PRESSURE_VENT_SECTION := 2       # the jet (22..27)
const PRESSURE_VENT_WINDOW := 18.0

const SLUICE_TUNNEL_MOUTH_A := Vector3(36.5, 0.5, 10.8)
const SLUICE_TUNNEL_MOUTH_B := Vector3(43.5, 0.5, 10.8)
const SLUICE_TUNNEL_DATA_PATH := [
	Vector3(37.5, 0.5, 12.0),
	Vector3(39.5, 0.5, 13.0),
	Vector3(41.5, 0.5, 13.0),
	Vector3(42.5, 0.5, 12.0),
	SLUICE_TUNNEL_MOUTH_B,
]

var _setpiece_root: Node3D
var _section_setpiece_count := 0
var _transit_root: Node3D
var _pressure_portals: Array = []
var _sluice_tunnels: Array = []
var _pressure_valve: Area3D
var _pressure_vent_until := -1.0

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
const FLOOD_SWEEP_INTERVAL := 0.1    # scheduler ticks: visible water is dangerous for its whole window
const DRAIN_DROWN_SWEEPS := 16       # DRAIN_LOOP_DUR / FLOOD_SWEEP_INTERVAL
var _drain_root: Node3D
var _drain_water: Array = []         # the run's flood-water segments (toggled by _drain_flooding)
var _drain_flooding := false         # the run is mid-surge this window (scheduler-set)
var _drain_flood_count := 0          # surges fired (for the analytic next-onset read)
var _drowned_count := 0             # guards the current has taken down the drain this run
var _section_drowned_count := 0     # main-relay guards caught by visible section water
var _cadence_t0 := 0.0              # scheduler tick the hazard cadence was (re)armed at — the analytic safe-window
									# reads are relative to THIS, so a reset that re-arms at a non-zero tick stays
									# self-consistent (the real onset and the predicted onset agree)

var _flooding := []                # cosmetic surge window
var _flood_counts := []            # per section — how many surges have fired (cadence variety / tests)
var _plate_held := []              # per section — all the section's plates are held this frame
## Character-level view of positional work. Unlike _plate_held (the aggregate mechanism truth), this
## also reports a single member on one half of a double plate so the HUD can protect that holder from
## a whole-party rally. The preview host treats this optional dictionary as the generic hold contract.
var _character_holds: Dictionary = {}   # char_id -> {control_id, kind, label, section}
var _sluice_blocked := []          # per section — the sluice gate cells are currently walled off
var _washed := {}                  # char_id -> true: members waiting at the start shelter for optional fast recovery
var _sweep_count := 0              # how many times the party was swept back this run (a "rough run" read)
var _section_wash_counts := []     # per section — times THIS section has washed the party (the flush hint trigger)
var _run_hint_shown := false       # one-shot: after enough washes, a character grumbles that you must RUN the surges
const FLUSH_HINT_THRESHOLD := 3    # the flush hint only appears once a SINGLE section has washed you this many times
# _scheduled is inherited from DataFragmentChunk (same one-time-scheduling guard).
var _wipe_restart_pending := false
var _flow_strips: Array = []
# The surge-telegraph strips ride the helix under their OWN Node3D root, so they survive hide_flat_graybox (which
# hides the chunk's flat direct-child graybox) — the strip is the only "about-to-flood" tell without TRACE, and it
# was vanishing the moment the real channels.glb loaded.
var _strip_root: Node3D
# Flood WATER layer — the in-game flood visual. Built WARPED onto the helix under a Node3D root so it SURVIVES
# hide_flat_graybox (which only hides the chunk's direct-child graybox meshes), unlike the flat flow strips.
# Shown per section while it floods, so the wash always has a visible cause (the surging water you got caught in).
var _water_root: Node3D
var _section_water: Array = []      # per section: Array[MeshInstance3D] of warped flood-water segments
var _sluice_gate := {}             # sluice section index -> warped gate mesh (visible while the gate is closed)
const WATER_SEG := 2.0             # flood-water segment length along the arc (segmented to follow the curve)
const WATER_THICK := 0.55
# _enemies is inherited from DataFragmentChunk (this chunk keeps its own enemy spawners that push to it).
var _lure_until: Array = []        # per lure — scheduler tick the distraction ends (<=0 = inactive)
var _lure_meshes: Array = []
var _sloperope_deployed := false   # the chunk-end line has been dropped (the start climb point is live)
var _debug_tick := 0               # throttles the CHANNELS_DEBUG position log
var _rope_mesh: MeshInstance3D
var _climb_interactable: Area3D
var _guidance_root: Node3D
var _section_guides: Array = []
var _guidance_section := -1
var _override_controls: Dictionary = {}   # section index -> held console (for cause/effect feedback)

# --- Character abilities (TRACE / BLOOM / BRACE) — each protagonist's signature read ---
# Aster TRACE (aster_focus): reads the flood cadence and surfaces the next SAFE window for the section he
# stands in. Peris BLOOM (peris_tune): flora-tending — grows a persistent bioluminescent light that lights the
# dark drainage + marks a safe lane. Endo BRACE (endo_patch): braces a washed/at-risk member (refunds stamina)
# and reveals which hide alcove is deep cover. All derived from the scheduler tick / positions — never logged.
const ABILITY_CONTEXT := "channels_rhythm"
const TELEGRAPH_LEAD := 1.2         # seconds before an onset the flow strip brightens (the surge tell)
const TRACE_HOLD := 6.0             # how long a TRACE read stays surfaced
const SURGE_CLOSE_MARGIN := 0.75     # amber when a crossing nearly touches an active-water window
const ABILITY_OWNERS := {"aster_focus": "aster", "peris_tune": "peris", "endo_patch": "endo"}
var _surge_timing_learned := false  # run knowledge: nearby visible surge/telegraph, or TRACE, unlocks timing
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
	fragment = FRAGMENT   # the data this chunk is built from (the base interface reads it; the build below uses it)
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

	_strip_root = Node3D.new(); _strip_root.name = "FlowStrips"; add_child(_strip_root)
	_override_controls.clear()
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
		# The active-flow indicator strip — the surge TELEGRAPH (brightens a beat before a flood). Built WARPED
		# onto the helix under _strip_root so it rides the deck AND survives hide_flat_graybox (it was a flat
		# direct-child box before, so it both vanished and sat off the helix on the real channels.glb scene).
		# _warped_box authors size as (lane-extent, height, s-extent) and gives a StandardMaterial3D _set_strip drives.
		var strip := _warped_box(_strip_root, cx, 0.0, Vector3(FLOOR_Z_HALF * 1.7, 0.06, w),
			_section_color(t) * 0.6, _section_color(t), 0.4, 0.03)
		_flow_strips.append(strip)
		# the disable control: an override console past the section, or a held plate before it
		if str(s["disable"]) == "override":
			var ov := _add_interactable(self, "Override%d" % i, "Flow override", Vector3(x1 + 1.5, 0.5, 0.0),
				"OVERRIDE", "", 1.0, true, 1.6, Interactable.InteractableType.INSPECTION, false)
			var ovm := _add_box(ov, Vector3(0.0, 0.1, 0.0), Vector3(0.6, 1.0, 0.4), Color(0.2, 0.45, 0.5),
				Color(0.3, 0.9, 1.0), 1.0)   # a console post (child -> rides the helix warp)
			_outline_interactable_child(ov, ovm, "Override%d" % i, 1.6)
			ov.interacted.connect(func() -> void: _on_override(i))
			_override_controls[i] = ov
			_add_causal_feedback_link(ov, strip, Color(0.25, 0.9, 1.0), {
				"label": "HOLD TO STOP THIS FLOW",
				"source_offset": Vector3(0.0, 1.0, 0.0),
				"target_offset": Vector3(0.0, 0.35, 0.0),
				"arc_height": 1.4,
				"name": "OverrideFlowLink%d" % i,
			})
	_wdbg("sections built")
	_build_threats()
	_wdbg("threats built")
	_build_connect_backs()
	_wdbg("connect-backs built")
	_build_section_guidance()
	_build_section_setpieces()
	_wdbg("section guidance built")
	_build_branches()
	_build_transit_breaks()
	_wdbg("branches built")
	_build_water_layer()
	_wdbg("water built")
	_build_drain_loop()
	_wdbg("drain loop built")
	_build_splash_planes()
	_wdbg("pipe splashes built")
	# This chunk authors its environment directly instead of calling DataFragmentChunk._build_chunk(),
	# so it must opt into the shared full-wipe signal explicitly.
	var gs = _get_game_state()
	if gs != null and not gs.character_downed.is_connected(_on_wash_relay_character_downed):
		gs.character_downed.connect(_on_wash_relay_character_downed)

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
	# Set the readability contract explicitly on every material instead of relying solely on shader defaults.
	# This makes Web/Compatibility imports and tests agree on the nonzero water + overhead-fade floors.
	mat.set_shader_parameter("water_alpha", 0.88)
	mat.set_shader_parameter("emission_strength", 2.2)
	mat.set_shader_parameter("reveal_radius", 6.0)
	mat.set_shader_parameter("reveal_min_factor", 0.45)
	mat.set_shader_parameter("reveal_softness", 0.7)
	mat.set_shader_parameter("reveal_alpha_floor", 0.14)
	mat.set_shader_parameter("reveal_emission_floor", 0.2)
	mat.set_shader_parameter("reveal_cut_above_player", 1.8)
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
	_climb_interactable = _add_interactable(self, "ClimbLine", "Climb the line", CLIMB_POS,
		"CLIMB", "", 1.4, false, 1.7, Interactable.InteractableType.INSPECTION, false)
	_climb_interactable.interacted.connect(func() -> void: _on_climb())
	_rope_mesh = _add_box(_climb_interactable, Vector3(0.0, 1.4, 0.0), Vector3(0.16, 2.8, 0.16), Color(0.25, 0.18, 0.1))
	_rope_mesh.visible = false   # the line only appears once dropped from the chunk end
	_outline_interactable_child(_climb_interactable, _rope_mesh, "ClimbLine", 1.7)
	# Hiding the rope mesh alone leaves the Area3D, hover verb, and click target live. The line has no readable
	# meaning until it is physically dropped from the end, so remove the entire affordance until then.
	_climb_interactable.set_interaction_enabled(false)


## One local instruction at a time. Each guide is pre-warped onto the spiral and nested below a Node3D so the
## modeled Channels backdrop can hide flat graybox meshes without also deleting the gameplay wayfinding.
func _build_section_guidance() -> void:
	_guidance_root = Node3D.new()
	_guidance_root.name = "SectionGuidance"
	add_child(_guidance_root)
	_section_guides.clear()
	_guidance_section = -1
	for i in range(SECTIONS.size()):
		var spec := _guidance_spec(i)
		var guide := Node3D.new()
		guide.name = "Guide%02d_%s" % [i + 1, str(SECTIONS[i]["type"]).capitalize()]
		_guidance_root.add_child(guide)
		_add_warped_guidance_label(guide, "Objective", str(spec["objective"]),
			float(spec["objective_s"]), -3.0, Color(0.78, 0.92, 1.0))
		if str(spec["cue"]) != "":
			var cue := _warped_box(guide, float(spec["cue_s"]), -2.15,
				Vector3(0.85, 0.07, 1.1), Color(0.08, 0.32, 0.38), Color(0.25, 0.9, 1.0), 1.4, 0.06)
			cue.name = "DecisionCue"
			_add_warped_guidance_label(guide, "DecisionCueLabel", str(spec["cue"]),
				float(spec["cue_s"]), -2.15, Color(0.35, 0.95, 1.0))
		var marker_color: Color = spec["marker_color"]
		var marker := _warped_box(guide, float(spec["destination_s"]), float(spec["destination_lane"]),
			Vector3(1.7, 0.09, 1.4), marker_color * 0.45, marker_color, 1.8, 0.07)
		marker.name = "DestinationMarker"
		_add_warped_guidance_label(guide, "Destination", str(spec["destination"]),
			float(spec["destination_s"]), float(spec["destination_lane"]), marker_color)
		guide.visible = false
		_section_guides.append(guide)


func _guidance_spec(i: int) -> Dictionary:
	var s: Dictionary = SECTIONS[i]
	var t := str(s["type"])
	var x0 := float(s["x0"])
	var x1 := float(s["x1"])
	var objective := "READ THE SURGE // THEN RUN"
	var destination := "SAFE SIDE"
	var destination_s := x1 + 0.8
	var destination_lane := 0.0
	var marker_color := Color(0.35, 1.0, 0.58)
	var cue := ""
	var cue_s := x0 + 0.75
	match t:
		"flush", "jet":
			objective = "RUN ONE THROUGH"
			cue = ">> OVERRIDE AHEAD"
			destination = "HOLD HERE // SEND REST"
			destination_s = x1 + 1.5
			marker_color = Color(0.25, 0.9, 1.0)
		"current", "sluice":
			objective = "WAIT FOR SURGE // THEN RUN"
		"plate":
			objective = "HOLD PLATE // SEND REST"
			marker_color = Color(1.0, 0.72, 0.22)
		"patrol":
			objective = "HIDE IN CYAN ALCOVE // THEN RUN"
		"lure":
			objective = "FIRE FLURE // THEN RUN"
		"basin":
			objective = "HIDE // RUN ONE TO OVERRIDE"
			cue = ">> OVERRIDE AHEAD"
			destination = "HOLD HERE // SEND REST"
			destination_s = x1 + 1.5
			marker_color = Color(0.25, 0.9, 1.0)
		"double_plate":
			objective = "TWO HOLD // SEND THIRD"
			destination = "ALL CREW // EXIT"
			destination_s = CHUNK_END_X + 0.5
	return {
		"objective": objective,
		"objective_s": x0 - 0.35,
		"destination": destination,
		"destination_s": destination_s,
		"destination_lane": destination_lane,
		"marker_color": marker_color,
		"cue": cue,
		"cue_s": cue_s,
	}


func _add_warped_guidance_label(parent: Node3D, node_name: String, text: String,
		s: float, lane: float, color: Color) -> Label3D:
	var anchor := Node3D.new()
	anchor.name = "%sAnchor" % node_name
	anchor.transform = _branch_warp_xform(s, lane)
	parent.add_child(anchor)
	var label := _add_label(anchor, text, Vector3(0.0, 1.25, 0.0), color)
	label.name = node_name
	return label


func _guidance_index_for_x(x: float) -> int:
	if SECTIONS.is_empty():
		return -1
	for i in range(SECTIONS.size() - 1):
		var boundary := (float(SECTIONS[i]["x1"]) + float(SECTIONS[i + 1]["x0"])) * 0.5
		if x < boundary:
			return i
	return SECTIONS.size() - 1


func _refresh_section_guidance() -> void:
	if _guidance_root == null or not is_instance_valid(_guidance_root):
		return
	var char_id := _get_active_character()
	if char_id == "" or char_id not in PARTY_IDS:
		char_id = "aster"
	_set_guidance_section(_guidance_index_for_x(_get_character_position(char_id).x))


func _set_guidance_section(index: int) -> void:
	_guidance_section = index
	for i in range(_section_guides.size()):
		if is_instance_valid(_section_guides[i]):
			_section_guides[i].visible = i == index

# Persistent section silhouettes. The original type dressing was built as direct children of the chunk and
# intentionally disappears when the authored Channels model replaces the flat graybox. These nested warped
# landmarks survive that swap, so a player can read the next verb before the water itself turns on.
func _build_section_setpieces() -> void:
	_setpiece_root = Node3D.new()
	_setpiece_root.name = 'SetpieceSilhouettes'
	add_child(_setpiece_root)
	_section_setpiece_count = 0
	for i in range(SECTIONS.size()):
		var section: Dictionary = SECTIONS[i]
		var kind := str(section['type'])
		var x0 := float(section['x0'])
		var x1 := float(section['x1'])
		var cx := (x0 + x1) * 0.5
		var span := x1 - x0
		var root := Node3D.new()
		root.name = 'Setpiece%02d_%s' % [i + 1, kind.capitalize()]
		_setpiece_root.add_child(root)
		var base := _section_color(kind)
		match kind:
			'flush':
				_setpiece_arch(root, x0 + 0.7, base, 3.6)
				_setpiece_mesh(root, 'Spout', cx, 3.15, Vector3(1.1, 1.15, 1.8),
					Color(0.16, 0.2, 0.24), Color(0.2, 0.65, 1.0), 0.8, 3.0)
				_setpiece_mesh(root, 'LowerLip', cx, -3.25, Vector3(0.45, 0.7, span),
					base * 0.5, base, 0.7, 0.35)
			'current':
				for lane in [-2.8, 2.8]:
					_setpiece_mesh(root, 'CurrentRail', cx, lane, Vector3(0.28, 0.75, span),
						base * 0.55, Color(0.2, 0.75, 1.0), 0.75, 0.45)
				for sc in [x0 + 1.0, cx, x1 - 1.0]:
					_setpiece_mesh(root, 'FlowFin', sc, 0.0, Vector3(3.6, 0.08, 0.5),
						base * 0.45, base, 1.0, 0.12)
			'jet':
				_setpiece_arch(root, cx, Color(0.32, 0.48, 0.72), 3.9)
				for sc in [x0 + 1.0, cx, x1 - 1.0]:
					for lane in [-2.45, 2.45]:
						_setpiece_mesh(root, 'JetNozzle', sc, lane, Vector3(0.72, 0.6, 0.72),
							Color(0.12, 0.16, 0.22), Color(0.35, 0.8, 1.0), 1.15, 0.32)
			'plate':
				for lane in [-1.15, 1.15]:
					_setpiece_mesh(root, 'BridgeRail', cx, lane, Vector3(0.16, 0.55, span),
						Color(0.16, 0.17, 0.2), base, 0.7, 0.35)
				_setpiece_mesh(root, 'PlatePylon', x0 - 0.65, -2.7, Vector3(0.8, 1.8, 0.8),
					Color(0.24, 0.18, 0.08), Color(1.0, 0.7, 0.2), 1.4, 0.9)
			'sluice':
				_setpiece_arch(root, x0 + 0.25, Color(0.32, 0.16, 0.1), 4.3)
				_setpiece_arch(root, x1 - 0.25, Color(0.32, 0.16, 0.1), 4.3)
				_setpiece_mesh(root, 'SluiceHeader', cx, 0.0, Vector3(7.4, 0.6, span),
					Color(0.13, 0.14, 0.17), Color(1.0, 0.34, 0.18), 0.55, 4.15)
			'patrol':
				for lane in [-3.15, 3.15]:
					_setpiece_mesh(root, 'HideCowl', cx, lane, Vector3(1.35, 2.2, span * 0.42),
						Color(0.12, 0.14, 0.18), Color(0.15, 0.85, 0.9), 0.6, 1.1)
				_setpiece_arch(root, x1 - 0.5, base, 3.7)
			'lure':
				for sc in [x0 + 0.55, x1 - 0.55]:
					_setpiece_arch(root, sc, Color(0.38, 0.17, 0.4), 3.5)
				_setpiece_mesh(root, 'LureBeacon', cx, 0.0, Vector3(0.7, 2.9, 0.7),
					Color(0.2, 0.11, 0.22), Color(1.0, 0.35, 0.9), 1.3, 2.2)
			'basin':
				for sc in [x0 + 1.0, cx, x1 - 1.0]:
					_setpiece_mesh(root, 'PumpTower', sc, 3.15, Vector3(1.0, 3.0, 1.0),
						Color(0.13, 0.18, 0.22), Color(0.2, 0.65, 1.0), 0.9, 1.5)
				for lane in [-3.35, 3.35]:
					_setpiece_mesh(root, 'BasinRim', cx, lane, Vector3(0.35, 0.7, span),
						base * 0.45, base, 0.65, 0.35)
			'double_plate':
				for lane in [-DOUBLE_PLATE_Z, DOUBLE_PLATE_Z]:
					_setpiece_mesh(root, 'CrewPylon', x0 - 0.55, lane, Vector3(0.8, 2.0, 0.8),
						Color(0.25, 0.18, 0.08), Color(1.0, 0.72, 0.18), 1.5, 1.0)
				for lane in [-1.0, 1.0]:
					_setpiece_mesh(root, 'FinalRail', cx, lane, Vector3(0.16, 0.62, span),
						Color(0.16, 0.17, 0.2), base, 0.8, 0.4)
				_setpiece_arch(root, x1 - 0.35, base, 4.0)
		_section_setpiece_count += 1


func _setpiece_mesh(parent: Node3D, node_name: String, s: float, lane: float, size: Vector3,
		color: Color, emission := Color.BLACK, energy := 0.0, y_off := 0.0) -> MeshInstance3D:
	var mesh := _warped_box(parent, s, lane, size, color, emission, energy, y_off)
	mesh.name = node_name
	return mesh


func _setpiece_arch(parent: Node3D, s: float, color: Color, height: float) -> void:
	for lane in [-3.35, 3.35]:
		_setpiece_mesh(parent, 'ArchPost', s, lane, Vector3(0.5, height, 0.55),
			Color(0.12, 0.14, 0.17), color, 0.55, height * 0.5)
	_setpiece_mesh(parent, 'ArchLintel', s, 0.0, Vector3(7.2, 0.45, 0.65),
		Color(0.13, 0.15, 0.18), color, 0.8, height)


# --- Branch puzzle offshoots ---

func _wdbg(msg: String) -> void:
	if OS.has_environment("PREVIEW_DEBUG"):
		print("[wash_relay] → ", msg)

func _accepts_gameplay_events() -> bool:
	return _phase == "ready" or _phase == "active"

# The mid-s of each GAP between consecutive sections (where a branch attaches).
func _gap_mids() -> Array:
	var mids: Array = []
	for i in range(SECTIONS.size() - 1):
		mids.append((float(SECTIONS[i]["x1"]) + float(SECTIONS[i + 1]["x0"])) * 0.5)
	return mids

func _is_mandatory_pressure_gap(mid: float) -> bool:
	return mid > PRESSURE_GAP_S0 and mid < PRESSURE_GAP_S1

func _is_authored_transit_gap(mid: float) -> bool:
	return _is_mandatory_pressure_gap(mid) \
		or absf(mid - SLUICE_TUNNEL_MOUTH_A.x) < 0.1 \
		or absf(mid - SLUICE_TUNNEL_MOUTH_B.x) < 0.1

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
		if _is_authored_transit_gap(mid):
			continue
		var branch_i := _branches.size()
		var node: Dictionary = nodes[g] if g < nodes.size() else {}
		var archetype := str(node.get("archetype_name", "Offshoot"))
		var placements: Array = node.get("content_placements", [])
		# The radial plank: juts off the deck rim (lane 4) out to the pad (lane 10), pre-warped onto the helix.
		var deck_color := Color(0.12, 0.14, 0.17)
		_add_warped_deck(mid, BRANCH_DECK_CENTER_LANE, Vector3(BRANCH_LANE_SPAN, 0.2, BRANCH_S_SPAN), deck_color)
		# A marker post at the deck rim so the offshoot reads as a turn-off from the main run.
		_add_warped_box(mid, BRANCH_NECK_LANE + 0.4, Vector3(0.4, 1.6, 0.4),
			Color(0.48, 0.3, 0.08), Color(1.0, 0.64, 0.18), 1.1)
		_add_warped_guidance_label(_branch_root, "BranchOptional%d" % g, "OPTIONAL // SALVAGE",
			mid, BRANCH_NECK_LANE + 0.9, Color(1.0, 0.7, 0.25))
		# The archetype's content placements, clustered on the pad (graybox identity of the puzzle).
		var content_count := _build_branch_content(mid, placements)
		# Reward cache — authored FLAT (the host warp pass lifts every interactable onto the helix); its mesh
		# is a CHILD so it rides the warp and stays visible (it isn't in the GLB the flat-graybox hide replaces).
		# Click to walk over, then a salvage WORK beat (TIMED_ACTION). The cache box is a CHILD of the
		# interactable so the visual + its outline+glow ride the helix warp together.
		var cache := _add_interactable(self, "BranchCache%d" % g, "Optional salvage cache",
			Vector3(mid, 0.5, BRANCH_PAD_LANE), "SALVAGE", "", 1.2, true, 1.6,
			Interactable.InteractableType.TIMED_ACTION, false)
		var cm := MeshInstance3D.new()
		var cb := BoxMesh.new(); cb.size = Vector3(0.7, 0.7, 0.7); cm.mesh = cb
		cm.material_override = _make_material(Color(0.7, 0.6, 0.2), Color(1.0, 0.85, 0.25), 1.4)
		cm.position = Vector3(0.0, 0.45, 0.0)
		cache.add_child(cm)
		_outline_interactable_child(cache, cm, "BranchCache%d" % g, 1.6)
		cache.interacted.connect(func() -> void: _on_branch_cache(branch_i))
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
			switch = _build_branch_switch(g, branch_i, mid, gate_kind)
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

# --- Authored transit breaks ---------------------------------------------------------------

func _build_transit_breaks() -> void:
	_transit_root = Node3D.new()
	_transit_root.name = 'TransitBreaks'
	add_child(_transit_root)
	_pressure_portals.clear()
	_sluice_tunnels.clear()
	_build_pressure_bridge()
	_build_sluice_tunnel_choice()


# The first discontinuity in the coil is mandatory. A pair of portal links carries the party into a dry
# pressure pocket, then back onto the far lip. The reverse pads keep the space honest for later return trips.
func _build_pressure_bridge() -> void:
	var void_mesh := _warped_box(_transit_root, (PRESSURE_GAP_S0 + PRESSURE_GAP_S1) * 0.5, 0.0,
		Vector3(FLOOR_Z_HALF * 2.05, 0.28, PRESSURE_GAP_S1 - PRESSURE_GAP_S0),
		Color(0.008, 0.012, 0.018), Color(0.08, 0.2, 0.32), 0.35, 0.18)
	void_mesh.name = 'MandatoryCoilBreak'
	for edge_s in [PRESSURE_GAP_S0, PRESSURE_GAP_S1]:
		_setpiece_mesh(_transit_root, 'BrokenCoilLip', edge_s, 0.0,
			Vector3(FLOOR_Z_HALF * 2.15, 0.5, 0.32), Color(0.18, 0.12, 0.08),
			Color(1.0, 0.38, 0.14), 1.25, 0.28)

	_add_transit_deck(PRESSURE_ROOM_CENTER.x, PRESSURE_ROOM_CENTER.z,
		Vector3(4.4, 0.24, 5.2), Color(0.09, 0.14, 0.18))
	for sc in [21.35, 26.05]:
		for lane in [-10.2, -6.0]:
			_setpiece_mesh(_transit_root, 'PressurePylon', sc, lane, Vector3(0.55, 3.2, 0.55),
				Color(0.12, 0.16, 0.2), Color(0.45, 0.82, 1.0), 0.75, 1.6)
	_setpiece_mesh(_transit_root, 'PressureHeader', PRESSURE_ROOM_CENTER.x, -10.05,
		Vector3(0.55, 0.55, 5.2), Color(0.13, 0.18, 0.22), Color(0.3, 0.75, 1.0), 0.9, 2.9)
	_setpiece_mesh(_transit_root, 'PressureWindow', PRESSURE_ROOM_CENTER.x, -6.0,
		Vector3(0.25, 1.6, 4.4), Color(0.08, 0.2, 0.26), Color(0.22, 0.7, 1.0), 0.55, 1.25)

	_spawn_pressure_portal('PressurePortalIn', 'PRESSURE TRANSIT', PRESSURE_PORTAL_ENTRY,
		PRESSURE_ROOM_ARRIVAL, Color(0.75, 0.38, 1.0))
	_spawn_pressure_portal('PressurePortalBack', 'BACK TO INLET', PRESSURE_ROOM_ARRIVAL,
		PRESSURE_PORTAL_ENTRY, Color(0.75, 0.38, 1.0))
	_spawn_pressure_portal('PressurePortalOut', 'RETURN TO CHANNEL', PRESSURE_ROOM_RETURN,
		PRESSURE_PORTAL_LANDING, Color(0.25, 0.88, 1.0))
	_spawn_pressure_portal('PressurePortalReentry', 'BACK TO VALVE', PRESSURE_PORTAL_LANDING,
		PRESSURE_ROOM_RETURN, Color(0.25, 0.88, 1.0))

	_add_warped_guidance_label(_transit_root, 'PressureMandatory', 'COIL BREAK // PRESSURE TRANSIT',
		PRESSURE_PORTAL_ENTRY.x, -2.65, Color(0.82, 0.62, 1.0))
	_add_warped_guidance_label(_transit_root, 'PressureRoomRead', 'VENT JETS // THEN EXIT CYAN',
		PRESSURE_ROOM_CENTER.x, -7.45, Color(0.35, 0.9, 1.0))

	_pressure_valve = _add_interactable(self, 'PressureValve', 'Vent the jet manifold', PRESSURE_VALVE_POS,
		'VENT JETS', '', 1.25, false, 1.65, Interactable.InteractableType.TIMED_ACTION, false)
	_pressure_valve.interacted.connect(_on_pressure_valve)
	var wheel := _add_box(_pressure_valve, Vector3(0.0, 0.65, 0.0), Vector3(0.9, 1.3, 0.55),
		Color(0.12, 0.3, 0.34), Color(0.2, 0.9, 1.0), 1.2)
	_outline_interactable_child(_pressure_valve, wheel, 'PressureValve', 1.65)
	if PRESSURE_VENT_SECTION < _flow_strips.size():
		_add_causal_feedback_link(_pressure_valve, _flow_strips[PRESSURE_VENT_SECTION], Color(0.2, 0.9, 1.0), {
			'label': 'VENTS THE JET MANIFOLD',
			'source_offset': Vector3(0.0, 1.0, 0.0),
			'target_offset': Vector3(0.0, 0.35, 0.0),
			'arc_height': 2.4,
			'name': 'PressureValveJetLink',
		})


func _spawn_pressure_portal(node_name: String, label: String, source_flat: Vector3,
		dest_flat: Vector3, color: Color) -> PortalPad:
	var pad := PortalPad.new()
	pad.name = node_name
	var gs = _get_game_state()
	if pad.has_method('configure_data'):
		pad.call('configure_data', gs, source_flat, dest_flat, 1.25, color)
	else:
		pad.configure(gs, source_flat, dest_flat, 1.25, color)
	pad.description = label.capitalize()
	pad.tutorial_label = label
	pad.set_group_provider(_selected_party_ids)
	add_child(pad)
	_register_interactable(pad)
	_portals.append(pad)
	_pressure_portals.append(pad)
	return pad


func _build_sluice_tunnel_choice() -> void:
	_add_transit_deck(SLUICE_TUNNEL_MOUTH_A.x, 7.4, Vector3(7.4, 0.22, 2.8), Color(0.09, 0.13, 0.16))
	_add_transit_deck(SLUICE_TUNNEL_MOUTH_B.x, 7.4, Vector3(7.4, 0.22, 2.8), Color(0.09, 0.13, 0.16))
	_build_tunnel_mouth_frame(SLUICE_TUNNEL_MOUTH_A.x, SLUICE_TUNNEL_MOUTH_A.z)
	_build_tunnel_mouth_frame(SLUICE_TUNNEL_MOUTH_B.x, SLUICE_TUNNEL_MOUTH_B.z)
	for point_v in SLUICE_TUNNEL_DATA_PATH:
		var point := point_v as Vector3
		for side in [-1.15, 1.15]:
			_setpiece_mesh(_transit_root, 'PipeRib', point.x, point.z + side,
				Vector3(0.28, 2.2, 0.48), Color(0.1, 0.14, 0.17),
				Color(0.28, 0.75, 0.86), 0.55, 1.1)
		_setpiece_mesh(_transit_root, 'PipeRoof', point.x, point.z,
			Vector3(2.6, 0.28, 0.62), Color(0.1, 0.15, 0.18),
			Color(0.25, 0.72, 0.84), 0.65, 2.15)

	var reverse_path: Array = [
		Vector3(42.5, 0.5, 12.0), Vector3(41.5, 0.5, 13.0),
		Vector3(39.5, 0.5, 13.0), Vector3(37.5, 0.5, 12.0), SLUICE_TUNNEL_MOUTH_A,
	]
	_spawn_sluice_tunnel('OuterPipeIn', 'SLOW SAFE PIPE', SLUICE_TUNNEL_MOUTH_A,
		SLUICE_TUNNEL_DATA_PATH, Color(0.25, 0.82, 0.88))
	_spawn_sluice_tunnel('OuterPipeBack', 'RETURN THROUGH PIPE', SLUICE_TUNNEL_MOUTH_B,
		reverse_path, Color(0.25, 0.82, 0.88))
	_add_warped_guidance_label(_transit_root, 'SluiceChoice', 'FAST SLUICE // SLOW SAFE PIPE',
		SLUICE_TUNNEL_MOUTH_A.x, 7.8, Color(0.4, 0.95, 1.0))
	_add_warped_guidance_label(_transit_root, 'SluiceRejoin', 'COLLECTOR // RALLY',
		SLUICE_TUNNEL_MOUTH_B.x, 7.8, Color(0.45, 1.0, 0.65))


func _spawn_sluice_tunnel(node_name: String, label: String, mouth_flat: Vector3,
		waypoints_flat: Array, color: Color) -> CrawlTunnel:
	var tunnel := CrawlTunnel.new()
	tunnel.name = node_name
	tunnel.description = label.capitalize()
	tunnel.tutorial_label = label
	var gs = _get_game_state()
	if tunnel.has_method('configure_data'):
		tunnel.call('configure_data', gs, mouth_flat, waypoints_flat, 1.5, 1.15)
	else:
		tunnel.configure(gs, mouth_flat, waypoints_flat, 1.5, 1.15)
	tunnel.set_group_provider(_selected_party_ids)
	add_child(tunnel)
	_register_interactable(tunnel)
	var stub := _add_box(tunnel, Vector3(0.0, 0.45, 0.0), Vector3(0.62, 0.9, 0.62),
		Color(0.1, 0.16, 0.18), color, 0.85)
	_outline_interactable_child(tunnel, stub, node_name, 1.5)
	_sluice_tunnels.append(tunnel)
	return tunnel


func _build_tunnel_mouth_frame(s: float, lane: float) -> void:
	for side in [-1.35, 1.35]:
		_setpiece_mesh(_transit_root, 'PipeMouthPost', s, lane + side,
			Vector3(0.42, 2.7, 0.72), Color(0.1, 0.15, 0.18),
			Color(0.28, 0.82, 0.9), 0.75, 1.35)
	_setpiece_mesh(_transit_root, 'PipeMouthHeader', s, lane, Vector3(3.1, 0.42, 0.8),
		Color(0.1, 0.15, 0.18), Color(0.28, 0.82, 0.9), 0.9, 2.65)


func _add_transit_deck(s: float, lane_center: float, size: Vector3, color: Color) -> void:
	var mesh := _warped_box(_transit_root, s, lane_center, size, color)
	mesh.name = 'TransitDeck'
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = mesh.transform
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	_transit_root.add_child(body)


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
		Color(0.48, 0.3, 0.08), Color(1.0, 0.64, 0.18), 1.0)
	_add_warped_guidance_label(_drain_root, "DrainOptional", "OPTIONAL // DRAIN CACHE",
		smid, DRAIN_LEDGE_LANE - 0.8, Color(1.0, 0.7, 0.25))
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
	var cache := _add_interactable(self, "DrainCache", "Optional drain cache", Vector3(smid, 0.5, DRAIN_LEDGE_LANE),
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
	if not _accepts_gameplay_events() or g < 0 or g >= _branches.size():
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
func _build_branch_switch(g: int, branch_i: int, mid: float, kind: String) -> Area3D:
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
	switch.interacted.connect(func() -> void: _on_branch_switch(branch_i))
	return switch

# Activating a branch switch: unlock the cache, drop the gate bar, and (for a guarded branch) lure the guard
# off the pad — distract it (shrinks its reach) and pull its roam anchor back to the neck corner.
func _on_branch_switch(g: int) -> void:
	if not _accepts_gameplay_events() or g < 0 or g >= _branches.size():
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
		_spawn_ch_enemy(spec)

func _spawn_ch_enemy(spec: Dictionary) -> void:
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
	if _phase == "active" and target_id in PARTY_IDS:
		if _wash_character(target_id):   # the guard shoves you into the channel -> back to the start shelter
			_announce_wash([target_id])

func _on_lure(idx: int) -> void:
	if not _accepts_gameplay_events() or idx < 0 or idx >= LURE_SPECS.size():
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
	if _phase != "active":
		return
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
	if _scheduled or _phase != "active":
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
		_learn_surge_timing_if_near(i)

# COSMETIC tutorial preview on the flush section: a rising-then-receding ghost of the surge so the first-time
# player sees where the water breaks before it actually does. Spawns its OWN throwaway warped boxes (NOT the
# real _section_water — that stays driven by the scheduler, so the flood-visual/water-capture invariants hold)
# and tweens them up then back, then frees them. Pure visuals: it never touches _flooding or the cadence.
func _play_flush_hint(i: int = 0) -> void:
	_show_note("// FLUSH // It breaks right here. Wait for the surge, then RUN.", 4.5)
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
	if _phase != "active":
		return
	# Count cadence beats even while a held control suppresses the water. TRACE predicts the next scheduled beat;
	# skipping disabled beats here made that read drift as soon as a player released an override or plate.
	if i < _flood_counts.size():
		_flood_counts[i] += 1
	if not _section_disabled(i):
		_learn_surge_timing_if_near(i)
		_flooding[i] = true
		_sweep_flooded_section(i)       # immediate capture at the onset
		_set_strip(i, 2.6)
		_play_water_surge(i)            # COSMETIC: a foam/spray accent + rise-pop as the section floods
		if str(SECTIONS[i]["type"]) == "sluice":
			_set_sluice(i, true)            # the gate slams shut — the threshold is impassable
		if sched != null:
			var sweep_count := ceili(_dur(i) / FLOOD_SWEEP_INTERVAL)
			for k in range(1, sweep_count + 1):
				sched.schedule_after(
					minf(_dur(i), FLOOD_SWEEP_INTERVAL * float(k)),
					_make_section_sweep(i),
					"wash_section_sweep_%d_%d" % [i, k]
				)
			sched.schedule_after(_dur(i), func() -> void: _set_flood_off(i), "wash_off_%d" % i)
	if sched != null and _phase == "active":
		sched.schedule_after(_period(i), _make_onset(i), "wash_onset_%d" % i)
		var lead := _period(i) - TELEGRAPH_LEAD
		if lead > 0.0:
			sched.schedule_after(lead, _make_pretel(i), "wash_pretel_%d" % i)

func _set_flood_off(i: int) -> void:
	_flooding[i] = false
	_set_strip(i, 0.4)
	if i < SECTIONS.size() and str(SECTIONS[i]["type"]) == "sluice":
		_set_sluice(i, false)               # the gate lifts — the threshold opens again

func _make_section_sweep(i: int) -> Callable:
	return func() -> void: _sweep_flooded_section(i)

## Scheduler-driven rechecks make the rule match the picture: entering water at any point while it is
## visibly up is dangerous. This cannot live in _process because gameplay results must be invariant under
## frame rate, fast-forward, pause, and replay.
func _sweep_flooded_section(i: int) -> void:
	if (_phase != "active" or i < 0 or i >= _flooding.size()
			or not _flooding[i] or _section_disabled(i)):
		return
	_wash_section(i)
	_drown_enemies_in_section(i)

func _drown_enemies_in_section(i: int) -> void:
	var s: Dictionary = SECTIONS[i]
	var x0 := float(s["x0"])
	var x1 := float(s["x1"])
	var gs = _get_game_state()
	for enemy in _enemies.duplicate():
		if (not is_instance_valid(enemy) or not enemy.is_alive() or enemy.char_id == ""
				or _branch_guard_spawns.has(enemy.char_id)):
			continue
		# Ambient guards know their posts and must still exist when the player reaches the back half.
		# The current becomes a weapon only after the player has committed one to the play: a chase,
		# attack, or lure distraction. Otherwise every guard spawned inside its authored section and
		# drowned in the first unattended cadence before the encounter ever began.
		var enemy_state := str(enemy.get_state()) if enemy.has_method("get_state") else ""
		var committed_to_play := enemy_state in ["alert", "pursuit", "windup", "charge", "impact"]
		if gs != null and gs.characters.has(enemy.char_id):
			committed_to_play = committed_to_play or gs.is_character_distracted(enemy.char_id)
		if not committed_to_play:
			continue
		var p := _get_character_position(enemy.char_id)
		if p.x >= x0 and p.x <= x1 and absf(p.z) <= FLOOR_Z_HALF:
			_drown_enemy(enemy, i)

func _section_disabled(i: int) -> bool:
	if i == PRESSURE_VENT_SECTION and _pressure_vent_remaining() > 0.0:
		return true
	var dis := str(SECTIONS[i]["disable"])
	# plate / double_plate / override are all HELD controls: disabled only WHILE a member stands on the
	# plate(s) / the override console. Vacate and the flow resumes — no permanent latch (principle #5). The
	# held state is refreshed positionally in _update; double_plate needs BOTH pads, override needs the console.
	if dis == "plate" or dis == "double_plate" or dis == "override":
		return _plate_held[i]
	return false

func _pressure_vent_remaining() -> float:
	var sched = _get_scheduler()
	if sched == null or _pressure_vent_until < 0.0:
		return 0.0
	return maxf(0.0, _pressure_vent_until - float(sched.get_current_tick()))


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
	var washed_ids: Array[String] = []
	for char_id in PARTY_IDS:
		var p := _get_character_position(char_id)
		if p.x >= x0 and p.x <= x1 and abs(p.z) <= FLOOR_Z_HALF:
			if _wash_character(char_id):
				washed_ids.append(char_id)
	if not washed_ids.is_empty():
		_announce_wash(washed_ids)   # one HUD event + one sweep tally, however many members got caught
		# Per-section tally: the flush hint (a preview of where THIS section's surge breaks) only appears once a
		# SINGLE section has caught the party FLUSH_HINT_THRESHOLD times — you keep getting washed HERE, so here's
		# the read. It never fires on a startup timer; it's earned by repeated failure on the same section.
		if i < _section_wash_counts.size():
			_section_wash_counts[i] += 1
			if _section_wash_counts[i] >= FLUSH_HINT_THRESHOLD and not _flush_hint_shown:
				_flush_hint_shown = true
				_play_flush_hint(i)

func _wash_character(char_id: String) -> bool:
	if char_id not in PARTY_IDS:
		return false
	var gs = _get_game_state()
	if gs != null:
		if not gs.characters.has(char_id):
			return false
		gs.command_stop(char_id)   # cancel any in-flight move so the runner is carried off, not walking on
	# Capture the pre-wash RENDER position + the flat data position BEFORE the snap — the cosmetic streak slides
	# from where the current grabbed you, down the spiral, to the start. (Purely for the visual; the data snap
	# below is instant and authoritative — tests depend on it.)
	var pre_flat := _get_character_position(char_id)
	var pre_render := pre_flat
	if gs != null and gs.characters.has(char_id):
		pre_render = gs.get_render_position(char_id)
	# The flood carries you all the way DOWN the spiral to the start shelter. `_washed` means the member is still
	# WAITING there and can be telephoned/climbed up as a convenience; moving into the relay clears the mark. It is
	# deliberately not an immunity flag or hidden control lock — a retrying character follows the normal rules.
	_set_character_position(char_id, START_POS)
	_washed[char_id] = true
	# COSMETIC ONLY: the current visibly carries you down the helix (a surge + a colour streak that follows the
	# curve to the start, then a splash). The body already snapped above — this is just the eye-candy.
	_play_sweep_animation(char_id, pre_render, pre_flat.x)
	return true

func _format_party_names(ids: Array) -> String:
	var names: Array[String] = []
	for raw_id in ids:
		var display := str(raw_id).capitalize()
		if not names.has(display):
			names.append(display)
	match names.size():
		0:
			return "Crew"
		1:
			return names[0]
		2:
			return "%s and %s" % [names[0], names[1]]
		_:
			return "%s, and %s" % [", ".join(names.slice(0, names.size() - 1)), names[-1]]


## One character-specific, nonblocking announcement per wash EVENT. The run-hint counts events, not bodies.
func _announce_wash(ids: Array) -> void:
	_sweep_count += 1
	_show_message("// WASHED // %s swept back to the start shelter — regroup or retry" % _format_party_names(ids), 3.0)
	# After a few washes the lesson lands diegetically: you can't walk the surges, you have to RUN them.
	if _sweep_count >= 3 and not _run_hint_shown:
		_run_hint_shown = true
		_show_note("Aster: The water comes too often to walk it. Wait for the surge, then RUN.", 4.5)

# --- Drain loop flood + drown (the recurring hazard on the detour) ---

# The recurring loop surge. Mirrors _flood_onset: washes whatever's in the run AT THE TICK (so the decision is
# identical at 1x and 10x), flags the cosmetic flood window, and self-reschedules the next onset.
func _drain_onset() -> void:
	var sched = _get_scheduler()
	if _phase != "active":
		return
	_wash_drain()
	_drain_flooding = true
	_drain_flood_count += 1
	if sched != null:
		# Re-check the whole run across the visible flood WINDOW: party and guards entering mid-surge obey
		# the same rule. The sweeps ride the scheduler, so they're fast-forward invariant.
		for k in range(1, DRAIN_DROWN_SWEEPS + 1):
			sched.schedule_after(DRAIN_LOOP_DUR * float(k) / float(DRAIN_DROWN_SWEEPS),
				func() -> void: _wash_drain(), "wash_drain_sweep_%d" % k)
		sched.schedule_after(DRAIN_LOOP_DUR, func() -> void: _set_drain_off(), "wash_drain_off")
	if sched != null and _phase == "active":
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
	var washed_ids: Array[String] = []
	for char_id in PARTY_IDS:
		if _in_drain_channel(_get_character_position(char_id)):
			if _wash_character(char_id):
				washed_ids.append(char_id)
	if not washed_ids.is_empty():
		_announce_wash(washed_ids)
	_drown_enemies_in_run()

# Drown every alive enemy currently standing in the flooding run. Called at the onset AND a few times across the
# flood window (the sweeps in _drain_onset), so a guard that walks/chases IN mid-surge is caught — the lead-it-in
# kill doesn't hinge on landing the single onset instant. Iterate a copy so _drown_enemy can schedule removal.
func _drown_enemies_in_run() -> void:
	if _phase != "active":
		return
	for enemy in _enemies.duplicate():
		if is_instance_valid(enemy) and enemy.is_alive() and enemy.char_id != "" \
				and _in_drain_channel(_get_character_position(enemy.char_id)):
			_drown_enemy(enemy)

# Kill an enemy caught by the loop flood: real data-layer death (take_damage to 0 hp -> FSM 'dead', stops it,
# is_alive() flips false) decided at the onset tick, plus the cosmetic "current drags it down the drain" streak
# (the same inward-toward-centre sweep the party gets). The registered character + node are removed a beat
# later on the SCHEDULER (tick-locked, not a tween) so a re-run can respawn the guard.
func _drown_enemy(enemy, section_index := -1) -> void:
	var id: String = enemy.char_id
	var gs = _get_game_state()
	var rp := _get_character_position(id)
	if gs != null and gs.characters.has(id):
		rp = gs.get_render_position(id)
		gs.command_stop(id)
	enemy.take_damage(enemy.max_hp)   # _hp -> 0, die() -> FSM 'dead' (stops moving, emits died); is_alive() == false
	_play_sweep_animation(id, rp, rp.x)   # cosmetic: the current carries it inward toward the central drain, dissolving
	if section_index >= 0:
		_section_drowned_count += 1
		_say("// SURGE HIT // section %d took the guard" % (section_index + 1))
	else:
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
			_spawn_ch_enemy(spec)

# --- Drain loop: lead the guard in (bait, then chase) ---

# Fire the bait: the ledge guard commits and walks DOWN INTO the flooding run (the lure target is mid-run, IN the
# flood band — NOT the player's spot at the mouth, which would make the guard charge the baiter instead). It's
# distracted so it ignores the party at range, and it idles in the run for DRAIN_BAIT_PULL — a span longer than
# one flood PERIOD, so a surge is guaranteed to catch it there. The chase resumes after (a player still in the
# loop then keeps it in the current). The player clicks the bait from the SAFE mouth, then steps clear.
func _on_drain_bait() -> void:
	var gs = _get_game_state()
	if not _accepts_gameplay_events() or gs == null:
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
	if _phase != "active":
		return
	var gs = _get_game_state()
	if gs != null and gs.characters.has(DRAIN_GUARD_ID):
		gs.set_character_distracted(DRAIN_GUARD_ID, false)

func _on_drain_cache() -> void:
	if not _accepts_gameplay_events():
		return
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
	# a scatter of droplet specks flung beyond the blob rim — soft ROUND discs (min radius 2 so none collapse
	# to a 1px plus/cross), each with a radial alpha falloff: a solid core and a soft rim, so they read as
	# water droplets rather than blocky aliased pixels. Max-blended so overlapping droplets stay opaque.
	for k in range(8):
		var a := float(k) / 8.0 * TAU + 0.4
		var rr := base_r * (1.25 + 0.3 * sin(a * 3.0))
		var px := c + cos(a) * rr
		var py := c + sin(a) * rr
		var dsz := 2 + (k % 3)   # 2..4 px radius — always a visible round disc, never a bare cross
		for oy in range(-dsz, dsz + 1):
			for ox in range(-dsz, dsz + 1):
				var dist := sqrt(float(ox * ox + oy * oy))
				if dist > float(dsz):
					continue
				var xx := int(round(px)) + ox
				var yy := int(round(py)) + oy
				if xx < 0 or xx >= size or yy < 0 or yy >= size:
					continue
				# solid core, soft 1px rim — the +1.0 keeps the inner disc fully opaque
				var da := clampf((float(dsz) - dist + 1.0) / 1.5, 0.0, 1.0) * 0.9
				var prev := img.get_pixel(xx, yy).a
				img.set_pixel(xx, yy, Color(1, 1, 1, maxf(prev, da)))
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

func _on_pressure_valve() -> void:
	if not _accepts_gameplay_events():
		return
	var sched = _get_scheduler()
	var now := float(sched.get_current_tick()) if sched != null else 0.0
	_pressure_vent_until = now + PRESSURE_VENT_WINDOW
	_show_message('// PRESSURE VENTED // jet manifold safe for %.0f seconds' % PRESSURE_VENT_WINDOW, 3.0)
	_set_preview_step('wash_relay_pressure_vented')
	if is_instance_valid(_pressure_valve):
		_flash_causal_feedback(_pressure_valve, 2.2, 1.55)
		_set_causal_feedback_latched(_pressure_valve, true)
	if PRESSURE_VENT_SECTION < _flow_strips.size() and is_instance_valid(_flow_strips[PRESSURE_VENT_SECTION]):
		_set_strip(PRESSURE_VENT_SECTION, 0.08)
		_request_preview_focus(_flow_strips[PRESSURE_VENT_SECTION], 1.1, true, {
			'label': 'JET PRESSURE FALLING', 'zoom': 1.08,
		})
	if sched != null:
		sched.cancel_tag('wash_pressure_vent')
		sched.schedule_after(PRESSURE_VENT_WINDOW, _on_pressure_vent_closed, 'wash_pressure_vent')


func _on_pressure_vent_closed() -> void:
	_pressure_vent_until = -1.0
	if is_instance_valid(_pressure_valve):
		_set_causal_feedback_latched(_pressure_valve, false)
	if PRESSURE_VENT_SECTION < _flow_strips.size():
		_set_strip(PRESSURE_VENT_SECTION, 0.4)
	if _phase == 'active':
		_show_message('// PRESSURE RETURNING // the jet manifold is live again', 2.2)

func _on_override(i: int) -> void:
	# The override is a HELD console — the hold is positional (refreshed in _update like a plate), so arriving
	# only confirms the member is manning the station. Step off and the flow resumes (no permanent latch).
	if not _accepts_gameplay_events() or i < 0 or i >= SECTIONS.size():
		return
	_show_message("// SECTION %d // HOLD HERE while the rest cross" % (i + 1), 2.5)
	var control = _override_controls.get(i, null)
	if is_instance_valid(control):
		_flash_causal_feedback(control, 1.8, 1.25)

func _recover_washed() -> int:
	var n := _washed.size()
	for char_id in _washed.keys():
		_set_character_position(char_id, RETURN_LANDING)
	_washed.clear()
	return n

func _on_terminal() -> void:
	if not _accepts_gameplay_events():
		return
	var n := _recover_washed()
	_show_message("// TERMINAL // %d waiting crew telephoned up" % n if n > 0 else "// TERMINAL // no crew waiting at start", 2.6)

func _on_sloperope() -> void:
	if not _accepts_gameplay_events():
		return
	_sloperope_deployed = true
	if is_instance_valid(_rope_mesh):
		_rope_mesh.visible = true
	if is_instance_valid(_climb_interactable):
		_climb_interactable.set_interaction_enabled(true)
		_climb_interactable.show_tutorial_label()
	_show_message("// SLOPEROPE DROPPED // the CLIMB point is now live at the start", 3.0)

func _on_climb() -> void:
	if not _accepts_gameplay_events():
		return
	if not _sloperope_deployed:
		_show_message("// NO LINE // drop the sloperope from the chunk end first", 2.5)
		return
	var n := _recover_washed()
	if n > 0:
		_show_message("// CLIMBED UP // %d waiting crew recovered" % n, 2.5)

func _set_strip(i: int, energy: float) -> void:
	if i < _flow_strips.size() and is_instance_valid(_flow_strips[i]):
		var mat := _flow_strips[i].material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = energy

## The preview host and its scheduler survive in-place chunk resets/reloads. Keep every
## Wash Relay-owned tag in one list so completion, reset, and teardown cannot diverge.
func _cancel_wash_events() -> void:
	var sched = _get_scheduler()
	if sched == null:
		_scheduled = false
		return
	sched.cancel_tag(_restart_tag())
	sched.cancel_tag('wash_pressure_vent')
	sched.cancel_tag("wash_drain_onset")
	sched.cancel_tag("wash_drain_off")
	sched.cancel_tag("wash_drain_bait")
	for k in range(1, DRAIN_DROWN_SWEEPS + 1):
		sched.cancel_tag("wash_drain_sweep_%d" % k)
	for i in range(SECTIONS.size()):
		sched.cancel_tag("wash_onset_%d" % i)
		sched.cancel_tag("wash_off_%d" % i)
		sched.cancel_tag("wash_pretel_%d" % i)
		for k in range(1, ceili(_dur(i) / FLOOD_SWEEP_INTERVAL) + 1):
			sched.cancel_tag("wash_section_sweep_%d_%d" % [i, k])
	for i in range(LURE_SPECS.size()):
		sched.cancel_tag("wash_lure_%d" % i)
	var enemy_ids: Array[String] = []
	for spec in ENEMY_SPECS:
		enemy_ids.append(str(spec["id"]))
	for id_v in _branch_guard_spawns.keys():
		var enemy_id := str(id_v)
		if not enemy_ids.has(enemy_id):
			enemy_ids.append(enemy_id)
	for enemy_id in enemy_ids:
		sched.cancel_tag("wash_drain_kill_%s" % enemy_id)
	_scheduled = false

func _quiesce_wash_hazards() -> void:
	_cancel_wash_events()
	for i in range(_flooding.size()):
		_flooding[i] = false
		if i < SECTIONS.size() and str(SECTIONS[i]["type"]) == "sluice":
			_set_sluice(i, false)
		_set_strip(i, 0.15)
	for segs in _section_water:
		for seg in segs:
			if is_instance_valid(seg):
				seg.visible = false
	_drain_flooding = false
	for seg in _drain_water:
		if is_instance_valid(seg):
			seg.visible = false
	for i in range(_splash_planes.size()):
		_splash_intensity[i] = 0.0
		if is_instance_valid(_splash_planes[i]):
			_splash_planes[i].visible = false

func _on_wash_relay_character_downed(char_id: String) -> void:
	if _phase != "active" or _wipe_restart_pending or char_id not in PARTY_IDS:
		return
	var gs = _get_game_state()
	if gs == null or not gs.is_party_downed(PARTY_IDS):
		return
	_wipe_restart_pending = true
	_wipe_count += 1
	_show_note("The relay takes everyone. Back to the upper shelter.", 2.6)
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_restart_tag())
		sched.schedule_after(1.5, _restart_wash_relay_after_wipe, _restart_tag())
	else:
		_restart_wash_relay_after_wipe()

func _restart_wash_relay_after_wipe() -> void:
	reset_preview_state()
	_set_preview_step("wash_relay_restart")

func _complete_wash_relay() -> void:
	if _phase == "complete":
		return
	_phase = "complete"
	_quiesce_wash_hazards()
	# Enemy strike resolution happens before hit_target emits. Full concealment is the
	# completion sanctuary that makes an already-committed charge harmless too.
	var gs = _get_game_state()
	if gs != null:
		for char_id in PARTY_IDS:
			if gs.characters.has(char_id):
				gs.command_stop(char_id)
				gs.set_character_concealment(char_id, GameState.CONCEAL_FULL)
	for interactable in _interactables:
		if is_instance_valid(interactable) and interactable.has_method("set_interaction_enabled"):
			interactable.set_interaction_enabled(false)
	_set_preview_step("wash_relay_complete")
	if is_instance_valid(_guidance_root):
		_guidance_root.visible = false
	_show_message("// RELAY CLEAR // all crew through", 3.0)

func _exit_tree() -> void:
	_cancel_wash_events()
	super._exit_tree()

# --- Lifecycle ---

func _process(delta: float) -> void:
	_update(delta)

func headless_process(delta: float) -> void:
	_update(delta)

# The pad footprint(s) a section needs HELD to disable it. A plain plate has one; a double_plate has two
# (at ±DOUBLE_PLATE_Z), so two members must stay while the third crosses.
func _plate_footprints(i: int) -> Array:
	var dis := str(SECTIONS[i]["disable"])
	# The override console sits PAST the section (x1+1.5): one member times a solo cross of the flooding section
	# to reach it, then HOLDS it open for the others — the activator is exposed/committed, the role inheritable.
	if dis == "override":
		return [Vector2(float(SECTIONS[i]["x1"]) + 1.5, 0.0)]
	var px := float(SECTIONS[i]["x0"]) - 1.2
	if dis == "double_plate":
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
	if _phase == "complete" or _phase == "failed":
		return
	_ensure_scheduled()
	_debug_log_positions()
	_update_pipe_splashes(delta)
	_refresh_section_guidance()
	var gsc = _get_game_state()
	# `_washed` only marks crew who are still WAITING in the start shelter for an optional fast recovery. The moment
	# they walk back into the relay they are a normal runner again: hazards can wash them and controls can read them.
	# `.keys()` returns a copy, so erasing mid-loop is safe.
	var retry_boundary := float(SECTIONS[0]["x0"]) - 0.5 if not SECTIONS.is_empty() else START_POS.x + 2.5
	for id in _washed.keys():
		if _get_character_position(id).x >= retry_boundary:
			_washed.erase(id)
	# Refresh plate-held state — a section is held only when EVERY one of its pads has a member on it.
	# Keep the occupant identity separately: the portrait needs to say WHO is committed even when a
	# double plate is only half-complete, and a rally lock excludes that member without changing selection.
	var next_character_holds: Dictionary = {}
	for i in range(SECTIONS.size()):
		var dis := str(SECTIONS[i]["disable"])
		if dis != "plate" and dis != "double_plate" and dis != "override":
			continue
		var all_held := true
		var footprints := _plate_footprints(i)
		for footprint_index in range(footprints.size()):
			var fp: Vector2 = footprints[footprint_index]
			var pad_held := false
			for char_id in PARTY_IDS:
				if gsc == null or not gsc.characters.has(char_id) or gsc.is_downed(char_id):
					continue
				var p := _get_character_position(char_id)
				if abs(p.x - fp.x) <= PLATE_RADIUS and abs(p.z - fp.y) <= PLATE_RADIUS:
					pad_held = true
					var hold_kind := "override" if dis == "override" else "plate"
					var hold_label := "OVERRIDE" if dis == "override" else ("DUAL PLATE" if dis == "double_plate" else "PLATE")
					next_character_holds[char_id] = {
						"control_id": "wash_%s_%d_%d" % [dis, i, footprint_index],
						"kind": hold_kind,
						"label": "%s %d" % [hold_label, i + 1],
						"section": i,
					}
					break
			if not pad_held:
				all_held = false
		if all_held != _plate_held[i]:
			_plate_held[i] = all_held
			_set_strip(i, 0.15 if all_held else 0.4)
			if dis == "override":
				var control = _override_controls.get(i, null)
				if is_instance_valid(control):
					_set_causal_feedback_latched(control, all_held)
	_character_holds = next_character_holds
	# hide alcoves: a party member tucked in a nook is fully concealed from the guards
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
		# A held control calms the water itself, not just its damage. Never show visible-but-safe water.
		var flooding: bool = i < _flooding.size() and _flooding[i] and not _section_disabled(i)
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
		var all_through := gsc != null
		for char_id in PARTY_IDS:
			if gsc == null or not gsc.characters.has(char_id) or gsc.is_downed(char_id) \
					or _get_character_position(char_id).x < CHUNK_END_X:
				all_through = false
				break
		if all_through:
			_complete_wash_relay()

# --- Scene/preview interface ---

## Optional generic portrait contract consumed by FragmentPreviewSequence. Other chunks can expose the
## same method for levers, cranks, channelled abilities, or any future positional job without teaching the
## shared HUD about their mechanics.
func get_preview_character_holds() -> Dictionary:
	if _phase != "active":
		return {}
	return _character_holds.duplicate(true)

## A visible section tell establishes this mechanic once for the run. The approach allowance lets the
## starting party learn from section one's telegraph without already standing in the lethal footprint.
func _learn_surge_timing_if_near(section_index: int) -> void:
	if _surge_timing_learned or section_index < 0 or section_index >= SECTIONS.size():
		return
	var gs = _get_game_state()
	if gs == null:
		return
	var section: Dictionary = SECTIONS[section_index]
	var x0 := float(section["x0"]) - 5.0
	var x1 := float(section["x1"]) + 5.0
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id) or gs.is_downed(char_id):
			continue
		var p: Vector3 = gs.get_position(char_id)
		if p.x >= x0 and p.x <= x1 and absf(p.z) <= FLOOR_Z_HALF + 3.0:
			_surge_timing_learned = true
			return

## Optional read-only contract consumed by PathRenderManager. It is intentionally absent until the
## player has learned the cadence and only answers while paused: resuming therefore clears every overlay.
## Returned points remain in flat data space; the shared manager owns helix warping and rendering.
func get_paused_path_feedback(char_id: String) -> Array:
	var feedback: Array = []
	if not _surge_timing_learned or _phase != "active" or not _scheduled:
		return feedback
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null or not sched.is_paused() or not gs.characters.has(char_id):
		return feedback
	var character: Dictionary = gs.characters[char_id]
	var movement = character.get("movement", null)
	if not (movement is Dictionary):
		return feedback
	var movement_data: Dictionary = movement
	var path: Array = movement_data.get("path", [])
	var ticks: Array = movement_data.get("arrival_ticks", [])
	if path.size() < 2 or ticks.size() != path.size():
		return feedback
	var now: float = sched.get_current_tick()
	for raw_hazard in _surge_path_hazards(char_id):
		var hazard: Dictionary = raw_hazard
		var pieces := _clip_timed_path_to_hazard(path, ticks, hazard, now)
		var spans := _merge_surge_path_pieces(pieces)
		for span_index in range(spans.size()):
			var span: Dictionary = spans[span_index]
			var timing := _classify_surge_path_span(span, hazard, now)
			feedback.append({
				"id": "%s_%d" % [str(hazard["id"]), span_index],
				"points": span["points"],
				"risk": timing["risk"],
				"label": timing["label"],
				"arrival_tick": span["entry_tick"],
				"surge_tick": timing["surge_tick"],
			})
	return feedback

func _surge_path_hazards(char_id: String) -> Array:
	var hazards: Array = []
	for i in range(SECTIONS.size()):
		var section: Dictionary = SECTIONS[i]
		hazards.append({
			"id": "section_%d" % i,
			"min_x": float(section["x0"]), "max_x": float(section["x1"]),
			"min_z": -FLOOR_Z_HALF, "max_z": FLOOR_Z_HALF,
			"base_tick": _cadence_t0 + FIRST_FLOOD + float(section["phase"]),
			"period": _period(i), "duration": _dur(i),
			# The current holder's own queued departure cannot promise the control will remain held.
			"held": _section_disabled(i) and not _character_holds.has(char_id),
		})
	hazards.append({
		"id": "drain",
		"min_x": DRAIN_LOOP_S0, "max_x": DRAIN_LOOP_S1,
		"min_z": DRAIN_RUN_LANE - DRAIN_RUN_HALF,
		"max_z": DRAIN_RUN_LANE + DRAIN_RUN_HALF,
		"base_tick": _cadence_t0 + FIRST_FLOOD + DRAIN_LOOP_PHASE,
		"period": DRAIN_LOOP_PERIOD, "duration": DRAIN_LOOP_DUR,
		"held": false,
	})
	return hazards

func _clip_timed_path_to_hazard(path: Array, ticks: Array, hazard: Dictionary, now: float) -> Array:
	var pieces: Array = []
	for i in range(1, path.size()):
		if not (path[i - 1] is Vector3) or not (path[i] is Vector3):
			continue
		var p0: Vector3 = path[i - 1]
		var p1: Vector3 = path[i]
		var t0 := float(ticks[i - 1])
		var t1 := float(ticks[i])
		if not p0.is_finite() or not p1.is_finite() or t1 <= now or t1 <= t0:
			continue
		if t0 < now:
			var remaining := clampf((now - t0) / (t1 - t0), 0.0, 1.0)
			p0 = p0.lerp(p1, remaining)
			t0 = now
		var clip := _clip_segment_to_surge_rect(
			p0, p1,
			float(hazard["min_x"]), float(hazard["max_x"]),
			float(hazard["min_z"]), float(hazard["max_z"])
		)
		if clip.is_empty():
			continue
		var enter_u := float(clip["enter"])
		var exit_u := float(clip["exit"])
		var entry := p0.lerp(p1, enter_u)
		var exit := p0.lerp(p1, exit_u)
		pieces.append({
			"points": [entry, exit],
			"entry_tick": lerpf(t0, t1, enter_u),
			"exit_tick": lerpf(t0, t1, exit_u),
		})
	return pieces

## Slab/Liang-Barsky clipping in the flat x/z movement plane. The returned fractions preserve each
## segment's exact arrival-tick interpolation, including cooperative paths that contain scheduled waits.
func _clip_segment_to_surge_rect(
		p0: Vector3, p1: Vector3, min_x: float, max_x: float, min_z: float, max_z: float) -> Dictionary:
	var enter := 0.0
	var exit := 1.0
	var dx := p1.x - p0.x
	if absf(dx) < 0.000001:
		if p0.x < min_x or p0.x > max_x:
			return {}
	else:
		var xa := (min_x - p0.x) / dx
		var xb := (max_x - p0.x) / dx
		enter = maxf(enter, minf(xa, xb))
		exit = minf(exit, maxf(xa, xb))
		if enter > exit:
			return {}
	var dz := p1.z - p0.z
	if absf(dz) < 0.000001:
		if p0.z < min_z or p0.z > max_z:
			return {}
	else:
		var za := (min_z - p0.z) / dz
		var zb := (max_z - p0.z) / dz
		enter = maxf(enter, minf(za, zb))
		exit = minf(exit, maxf(za, zb))
		if enter > exit:
			return {}
	return {"enter": clampf(enter, 0.0, 1.0), "exit": clampf(exit, 0.0, 1.0)}

func _merge_surge_path_pieces(pieces: Array) -> Array:
	var merged: Array = []
	for raw_piece in pieces:
		if not (raw_piece is Dictionary):
			continue
		var piece: Dictionary = raw_piece
		var points: Array = piece["points"]
		if not merged.is_empty():
			var last: Dictionary = merged[merged.size() - 1]
			var last_points: Array = last["points"]
			var joins_in_space := (last_points[last_points.size() - 1] as Vector3).distance_to(points[0]) < 0.01
			var joins_in_time := absf(float(last["exit_tick"]) - float(piece["entry_tick"])) < 0.01
			if joins_in_space and joins_in_time:
				if (last_points[last_points.size() - 1] as Vector3).distance_to(points[1]) > 0.001:
					last_points.append(points[1])
				last["points"] = last_points
				last["exit_tick"] = piece["exit_tick"]
				merged[merged.size() - 1] = last
				continue
		merged.append({
			"points": points.duplicate(),
			"entry_tick": piece["entry_tick"],
			"exit_tick": piece["exit_tick"],
		})
	return merged

func _classify_surge_path_span(span: Dictionary, hazard: Dictionary, now: float) -> Dictionary:
	var entry_tick := float(span["entry_tick"])
	var exit_tick := float(span["exit_tick"])
	var arrival_in := maxf(0.0, entry_tick - now)
	if bool(hazard.get("held", false)):
		return {
			"risk": "safe", "surge_tick": -1.0,
			"label": "HELD OPEN | ARRIVE +%.1fs" % arrival_in,
		}
	var base_tick := float(hazard["base_tick"])
	var period := maxf(0.001, float(hazard["period"]))
	var duration := maxf(0.0, float(hazard["duration"]))
	var first_k := maxi(0, int(floor((entry_tick - base_tick) / period)) - 1)
	var last_k := maxi(first_k + 2, int(ceil((exit_tick - base_tick) / period)) + 1)
	var danger_found := false
	var danger_onset := base_tick
	var nearest_gap := INF
	for k in range(first_k, last_k + 1):
		var onset := base_tick + period * float(k)
		var off := onset + duration
		if exit_tick >= onset and entry_tick <= off:
			if not danger_found:
				danger_onset = onset
			danger_found = true
			nearest_gap = 0.0
		elif exit_tick < onset:
			nearest_gap = minf(nearest_gap, onset - exit_tick)
		else:
			nearest_gap = minf(nearest_gap, entry_tick - off)
	var risk := "danger" if danger_found else ("close" if nearest_gap <= SURGE_CLOSE_MARGIN else "safe")
	var surge_tick := danger_onset
	if not danger_found:
		var next_k := maxi(0, int(ceil((entry_tick - base_tick) / period)))
		surge_tick = base_tick + period * float(next_k)
	var label := "ARRIVE +%.1fs | SURGE +%.1fs" % [arrival_in, surge_tick - now]
	if danger_found and surge_tick <= now and now <= surge_tick + duration:
		label = "WATER ACTIVE | ARRIVE +%.1fs" % arrival_in
	return {"risk": risk, "surge_tick": surge_tick, "label": label}

## The modeled environment this gauntlet plays inside — the textured channels spiral. It is built along
## the SAME helix as ChannelsArc, so arc_pos(section x, lane z) lands each section on its set piece.
func get_environment_model() -> String:
	return FRAGMENT.environment_model

## Installing this on GameState moves the playable system ONTO the helix: the data layer stays flat,
## node followers render through it, and a click on the GLB deck maps back to a flat (s, lane) target.
func get_coord_map():
	return ChannelsCoordMap.new()

## Adjacent helix turns are only ~9.24 world units apart vertically. The shared preview camera's
## 12-unit rise therefore starts above the next turn and looks straight through it. Keep this live
## follow camera below that pitch at every allowed zoom while retaining enough elevation to read
## the current channel, and snap on entry so the view never lerps through the upper deck.
func get_preview_camera_profile() -> Dictionary:
	return {
		"follow_offset": Vector3(0.0, 6.0, 7.0),
		"min_zoom": 0.8,
		"max_zoom": 1.25,
		"initial_zoom": 1.0,
		"reset_yaw": true,
	}

## With the textured GLB as the environment, the flat graybox geometry would double the set pieces and
## float below the helix — hide it. Only this chunk's own DIRECT meshes go; the meshless interaction
## zones stay live and the guard nodes (which render through the warp) are untouched.
func hide_flat_graybox() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = false

func get_scene_title() -> String:
	return FRAGMENT.title

func get_scene_help() -> String:
	return FRAGMENT.help

func get_default_character() -> String:
	return FRAGMENT.default_character

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_grid_data() -> Dictionary:
	# The main deck lane, plus one OUTWARD spur per gap (lane 3.5..10) — the branch offshoots. Each spur
	# overlaps the deck rim (lane 4) so it's path-connected; the height grows to admit the outer lane.
	var regions: Array = [
		{"min": [FLOOR_MIN_X, -FLOOR_Z_HALF], "max": [PRESSURE_GAP_S0, FLOOR_Z_HALF]},
		{"min": [PRESSURE_GAP_S1, -FLOOR_Z_HALF], "max": [FLOOR_MAX_X, FLOOR_Z_HALF]},
	]
	for mid in _gap_mids():
		if _is_authored_transit_gap(float(mid)):
			continue
		regions.append({"min": [float(mid) - BRANCH_HALF_S, BRANCH_NECK_LANE], "max": [float(mid) + BRANCH_HALF_S, BRANCH_OUTER_LANE]})
	# The drain loop: entry/exit legs (overlap the deck rim -> connected), the flooding run between them, and
	# the stub out to the dry salvage ledge across the water. Authored flat in (s, lane) exactly like the branches.
	var drain_mid := (DRAIN_LOOP_S0 + DRAIN_LOOP_S1) * 0.5
	regions.append({"min": [DRAIN_LOOP_S0 - 0.8, BRANCH_NECK_LANE], "max": [DRAIN_LOOP_S0 + 0.8, DRAIN_RUN_LANE + 0.6]})
	regions.append({"min": [DRAIN_LOOP_S1 - 0.8, BRANCH_NECK_LANE], "max": [DRAIN_LOOP_S1 + 0.8, DRAIN_RUN_LANE + 0.6]})
	regions.append({"min": [DRAIN_LOOP_S0 - 0.8, DRAIN_RUN_LANE - DRAIN_RUN_HALF], "max": [DRAIN_LOOP_S1 + 0.8, DRAIN_RUN_LANE + DRAIN_RUN_HALF]})
	regions.append({"min": [drain_mid - 1.1, DRAIN_RUN_LANE - 0.3], "max": [drain_mid + 1.1, DRAIN_LEDGE_LANE + 0.6]})
	# The mandatory pressure pocket is deliberately separated from the main deck by a blocked cell row. The
	# portal is the graph edge; raster adjacency must never turn the room into an ordinary walking shortcut.
	regions.append({"min": [21.0, -10.4], "max": [26.3, -6.0]})
	# Only the crawl mouths are walkable. Its visible outer bulge remains grid-forbidden authored transit.
	regions.append({"min": [35.1, BRANCH_NECK_LANE], "max": [37.9, 12.0]})
	regions.append({"min": [42.1, BRANCH_NECK_LANE], "max": [44.9, 12.0]})
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [-2.0, 0.0, -11.0], "cell_size": 1.0, "width": 92, "height": 27,
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
	anchors['pressure_portal_entry'] = PRESSURE_PORTAL_ENTRY
	anchors['pressure_room_arrival'] = PRESSURE_ROOM_ARRIVAL
	anchors['pressure_room_return'] = PRESSURE_ROOM_RETURN
	anchors['pressure_portal_landing'] = PRESSURE_PORTAL_LANDING
	anchors['pressure_valve'] = PRESSURE_VALVE_POS
	anchors['sluice_tunnel_in'] = SLUICE_TUNNEL_MOUTH_A
	anchors['sluice_tunnel_out'] = SLUICE_TUNNEL_MOUTH_B
	return anchors

func get_preview_time_state() -> Dictionary:
	return (FRAGMENT.time_state as Dictionary).duplicate(true)

func get_preview_abilities() -> Array:
	# Display names + tuning come from data/abilities/en/abilities.xlsx (channels_rhythm.* rows): aster_focus=
	# TRACE, peris_tune=BLOOM, endo_patch=BRACE. The preview shell already registers the three keys; this just
	# gives them the channels' names/notes. The EFFECTS live in handle_preview_ability below.
	return AbilityData.for_context(ABILITY_CONTEXT)

# The three protagonists' signature reads. Returns a Dict merged over the ability def + applied by the preview
# (note text, per-character stat deltas). Owner stat deltas (aster +atp, peris +sta, endo +hp) auto-apply
# upstream; here we add the channels-specific EFFECT. Pure derived state — replay/fast-forward safe.
func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	if not _accepts_gameplay_events():
		return {"note": "// RELAY CLEAR // no active channel read"}
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
	# TRACE establishes the cadence vocabulary immediately, even if Aster is between sections.
	_surge_timing_learned = true
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

# BRACE — Endo braces the party: refund stamina to anyone still waiting at the start shelter for the re-cross,
# and mark the deep hide alcove. If nobody is waiting, it still steadies the party (owner HP applies upstream).
func _ability_brace() -> Dictionary:
	var result := {}
	var deltas := {}
	for id in _washed.keys():
		deltas[id] = {"sta_delta": 14.0}
	if not deltas.is_empty():
		result["characters"] = deltas
		result["note"] = "// BRACE // %d waiting at start — steadied for the retry" % deltas.size()
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

# Grow a flora light (the shared FloraLight: emissive bloom + omni light) at a warped world position. Stored
# so it persists for the run and is cleared on reset. Cosmetic light; the "lane reads clear" is the gameplay read.
func _spawn_bloom(world: Vector3, flat: Vector3) -> void:
	if _bloom_root == null or not is_instance_valid(_bloom_root):
		_bloom_root = Node3D.new()
		_bloom_root.name = "Blooms"
		add_child(_bloom_root)
	var node := FloraLight.new()
	node.position = world + Vector3(0.0, 0.2, 0.0)
	node.configure({
		"albedo": Color(0.2, 0.7, 0.5), "emission": Color(0.4, 1.0, 0.7), "emission_energy": 2.2,
		"bloom_radius": 0.22, "light_color": Color(0.5, 1.0, 0.75), "light_energy": 2.2, "light_range": 6.0,
	})
	_bloom_root.add_child(node)
	_blooms.append({"pos": flat, "node": node})

func get_preview_overlay_status(_overlay_id: String, _current_tick: float) -> Array:
	return []

func reset_preview_state() -> void:
	var n := SECTIONS.size()
	_pressure_vent_until = -1.0
	# The host scheduler PERSISTS across an in-place reset, and every hazard onset self-reschedules forever — so a
	# reset must CANCEL the live cadence and re-arm it, or the old (un-rebased) chain keeps firing while the
	# analytic safe-window reads recompute from the zeroed counts (predicted vs real onset drift). Cancel every
	# recurring tag + the pending drowned-guard removals, then clear _scheduled so _ensure_scheduled re-anchors
	# the whole cadence to the post-reset 'now' (matching a fresh boot).
	_cancel_wash_events()
	_wipe_restart_pending = false
	# A guard drowned in the drain loop was unregistered + freed — bring it (and any other missing spec guard) back
	# before the re-snap below assumes every guard still exists.
	_respawn_missing_enemies()
	_phase = "ready"
	_character_holds.clear()
	_flooding = []; _plate_held = []; _sluice_blocked = []; _flood_counts = []; _section_wash_counts = []
	for i in range(n):
		_flooding.append(false); _plate_held.append(false); _sluice_blocked.append(false); _flood_counts.append(0); _section_wash_counts.append(0)
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
	_section_drowned_count = 0
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
	# Learned cadence is player knowledge, not transient hazard state: keep it across an in-place retry.
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
	for interactable in _interactables:
		if is_instance_valid(interactable) and interactable.has_method("reset"):
			interactable.reset()
	# reset() re-enables every interactable; the climb stays nonexistent as an affordance until the end reel drops it.
	if is_instance_valid(_climb_interactable):
		_climb_interactable.set_interaction_enabled(false)
	for control in _override_controls.values():
		if is_instance_valid(control):
			_set_causal_feedback_latched(control, false)
	if is_instance_valid(_pressure_valve):
		_set_causal_feedback_latched(_pressure_valve, false)
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
				gs.restore_character(char_id)
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
	if is_instance_valid(_guidance_root):
		_guidance_root.visible = true
	_refresh_section_guidance()
	_set_preview_step("wash_relay_briefing")

func get_preview_state() -> Dictionary:
	var secs: Array = []
	for i in range(SECTIONS.size()):
		secs.append({"type": SECTIONS[i]["type"], "disable": SECTIONS[i]["disable"],
			"x0": float(SECTIONS[i]["x0"]), "x1": float(SECTIONS[i]["x1"]),   # footprint along the spiral (s)
			"flooding": _flooding[i] if i < _flooding.size() else false,
			"disabled": _section_disabled(i),
			"overridden": (i < _plate_held.size() and str(SECTIONS[i]["disable"]) == "override" and bool(_plate_held[i])),
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
		"phase": _phase, "complete": _phase == "complete", "wipe_count": _wipe_count,
		"sections": secs, "section_count": SECTIONS.size(),
		"washed_count": _washed.size(), "washed": _washed.keys(),
		"flow_period": FLOW_PERIOD, "flood_duration": FLOOD_DURATION,
		"enemy_count": guards.size(), "guards": guards,
		"lure_active": _lure_active(), "hidden": hidden_ids,
		"sloperope_deployed": _sloperope_deployed,
		"climb_available": is_instance_valid(_climb_interactable) and _climb_interactable.is_interaction_enabled(),
		"guidance_section": _guidance_section, "guidance_count": _section_guides.size(),
		"section_setpiece_count": _section_setpiece_count,
		"pressure_portal_count": _pressure_portals.size(), "sluice_tunnel_count": _sluice_tunnels.size(),
		"pressure_vent_active": _pressure_vent_remaining() > 0.0,
		"pressure_vent_remaining": _pressure_vent_remaining(),
		"branches": branches, "branch_count": _branches.size(), "branch_loot": _branch_loot,
		"branch_guard_count": branch_guard_count,
		"trace_section": _trace_section, "surge_timing_learned": _surge_timing_learned,
		"bloom_count": _blooms.size(),
		"sweep_count": _sweep_count, "section_wash_counts": _section_wash_counts.duplicate(),
		"flush_hint_shown": _flush_hint_shown,
		"water_shown": _water_shown_state(),
		"drain_flooding": _drain_flooding, "drain_next_onset_in": _drain_next_onset_in(),
		"drowned_count": _drowned_count, "section_drowned_count": _section_drowned_count,
		"drain_guard": drain_guard,
	}

# Per-section: is the flood water currently visible? (Drives the flood-visual test + any HUD read.)
func _water_shown_state() -> Array:
	var out: Array = []
	for segs in _section_water:
		out.append(not segs.is_empty() and is_instance_valid(segs[0]) and segs[0].visible)
	return out
