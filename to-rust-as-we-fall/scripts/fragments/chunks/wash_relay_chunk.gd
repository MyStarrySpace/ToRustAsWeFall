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
## Reach the chunk end, have Peris tend the return vine, and let washed members climb back up.
## All hazards fire on the gameplay SCHEDULER (recurring per-section onsets) — fast-forward + replay safe.

const ChannelsArc := preload("res://scripts/game/world/channels_arc.gd")
const StretchGenerator := preload("res://scripts/generation/stretch_generator.gd")
const ClimbvineReturnScript := preload("res://scripts/game/objects/climbvine_return.gd")
const WaterShader := preload("res://resources/channels_water.gdshader")
const WaterTexV0 := preload("res://resources/models/channels/channels_water_v0.png")
const WaterTexV1 := preload("res://resources/models/channels/channels_water_v1.png")
const WASH_AUTHORITY_VERSION := 8
const WASH_AUTHORITY_KEY := "chunk:wash_relay"
const WASH_CADENCE_SAVE_EPSILON := 0.00001
const SPATIAL_AUTHORITY_INTERVAL := 0.1
## Flow-strip telegraph levels. Idle stays a floor-line whisper — upstream coil
## turns are visible across the void, and bright idle strips read as floating
## dashes from any distance. The pre-surge (1.1) and flooding (2.6) jumps carry
## the warning; calm marks a plate-held / quiesced section below idle.
const STRIP_IDLE_ENERGY := 0.18
const STRIP_CALM_ENERGY := 0.06
## THE GRUNGE LAW (director): the coil is dark iron, wood, and rust — structure is
## NEVER tinted; its painted albedo carries. Color is spent only on a few SIGNALS,
## from this constrained accent set. Section identity lives in the gate light and
## sign band, never in painting the architecture a different hue per section.
const ACCENT_WATER := Color(0.30, 0.62, 0.72)    # flow hardware, hide alcoves
const ACCENT_WORK := Color(0.85, 0.58, 0.22)     # stations a worker tends
const ACCENT_EMBER := Color(0.72, 0.28, 0.14)    # hazard machinery
const ACCENT_ORGANIC := Color(0.48, 0.32, 0.62)  # the alien-organic register
const SPATIAL_AUTHORITY_TAG := "wash_spatial_authority"
const WASH_CONTROL_POSITION_TOLERANCE := 0.25
const WASH_CONTROL_HEIGHT_TOLERANCE := 1.25
const REWARD_PHASE_AVAILABLE := "available"
const REWARD_PHASE_CLAIMING := "claiming"
const REWARD_PHASE_CLAIMED := "claimed"
const REWARD_SOURCE_PREFIX := "wash_relay:"
const DRAIN_REWARD_SOURCE_KEY := REWARD_SOURCE_PREFIX + "drain"

# The LEVEL DATA (environment model + section layout + level tunables). The .tres is the authoritative source;
# the values below are fallbacks. Read into member vars (initialized at instantiation, before get_grid_data /
# _build_chunk) so the ~200 downstream references (SECTIONS[i], FLOW_PERIOD, …) are unchanged. The warp/flood/
# branch/drain MECHANICS stay in this subclass — the "thin logic" half of the hybrid.
const FRAGMENT := preload("res://data/fragments/wash_relay.tres")

const PARTY_IDS := ["aster", "peris", "endo"]
var SPAWNS: Dictionary = FRAGMENT.spawns
var SECTIONS: Array = FRAGMENT.params.get("sections", [])
var START_POS: Vector3 = FRAGMENT.params.get("start_pos", Vector3(3.0, 0.0, 0.0))
var FLOOR_Z_HALF: float = FRAGMENT.params.get("floor_z_half", 4.0)
var FLOOR_MIN_X: float = FRAGMENT.params.get("floor_min_x", -1.0)
var FLOOR_MAX_X: float = FRAGMENT.params.get("floor_max_x", 87.0)
var CHUNK_END_X: float = FRAGMENT.params.get("chunk_end_x", 84.0)
var CLIMB_POS: Vector3 = FRAGMENT.params.get("climb_pos", Vector3(5.0, 0.0, 2.5))
var RETURN_LANDING: Vector3 = FRAGMENT.params.get("return_landing", Vector3(83.0, 0.0, 0.0))
const SLOPEROPE_DEPLOY_DURATION := 2.5
const SLOPEROPE_CLIMB_DURATION := 6.0
const SLOPEROPE_TRAVERSAL_PREFIX := "wash_relay_sloperope:"
const SLOPEROPE_RETURN_ID := "wash_relay_sloperope"
const WASH_CURRENT_TRAVERSAL_PREFIX := "wash_relay_current:"
const WASH_CURRENT_KNOCK_DURATION := 0.85
const WASH_CURRENT_RETURN_SPEED := 22.0
const WASH_CURRENT_RETURN_MIN := 0.9
const WASH_CURRENT_RETURN_MAX := 3.6
const WASH_CURRENT_PREIMPACT_EPSILON := 0.00001
const WASH_CURRENT_RECONCILE_TAG := "wash_relay_current_reconcile"
const WASH_ENEMY_CURRENT_RECONCILE_TAG := "wash_relay_enemy_current_reconcile"
const WASH_ENEMY_CURRENT_DAMAGE := 10000.0
const WASH_ENEMY_CURRENT_SPEED := 18.0
const WASH_ENEMY_CURRENT_MIN_DURATION := 0.7
const WASH_ENEMY_CURRENT_INNER_LANE := -9.5
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
# also spawns a roamer (capped). Branches are OPTIONAL reward detours — a physical lysate source pays off the climb
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
const BRANCH_GUIDANCE_REWARD := 1
const BRANCH_GATED_REWARD := 2
const BRANCH_GUARDED_REWARD := 3
const DRAIN_RISK_REWARD := 4
const BRANCH_SWITCH_LANE := 5.0     # the gate switch sits just past the neck (the player hits it on the way out)
const BRANCH_GATE_LANE := 6.5       # the physical counterweight threshold between switch and cache
const BRANCH_LEVER_DURATION := 1.4
const BRANCH_VALVE_DURATION := 1.8
const BRANCH_DECOY_DURATION := 8.0
const BRANCH_DECOY_POLL_INTERVAL := 0.1
const BRANCH_DECOY_ARRIVAL_RADIUS := 0.7
const BRANCH_GATE_LIFT_HEIGHT := 2.1

var _branches: Array = []           # per gap: world refs + authoritative mechanism phase/deadlines/context
var _branch_root: Node3D
var _branch_guard_spawns := {}      # guard id -> flat spawn (so reset re-snaps branch guards too)
var _pending_branch_guard_reposts := {} # restore barrier: rejected Wash futures win after child Enemy attach

# --- Authored transit breaks ---------------------------------------------------------------
# The old relay was one uninterrupted curl: even with optional lysate spokes, the mandatory read was
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
var _section_flood_until: Array = [] # exact absolute off deadline for each active section
var _drain_flood_until := -1.0
var _drain_bait_until := -1.0
var _pending_drown_removals := {}    # enemy id -> absolute removal tick
var _enemy_drown_mirrors := {}       # enemy id -> provenance/cleanup mirror; Channel owns the carry + impact
var _section_enemy_currents := {}    # section index -> reusable Channel transaction owner
var _drain_enemy_current = null
var _wash_restart_deadline := -1.0
var _restoring_wash_authority := false

# --- Drain loop: an OPTIONAL flooding DETOUR off the spiral ("out the deck rim and back in"). It leaves the
# deck at S0, runs a flooding channel along the OUTER lane, and rejoins at S1, with a DRY lysate ledge across
# the water. A guard posts on that ledge; you BAIT it across the flooding run and let the current DROWN it
# (the bait pulls it in, then the chase keeps it there). The whole thing is bypassed by the main deck (lane 0),
# and the guard's reach is short so it never harasses a straight-through runner. Like every hazard here it
# floods on the GAMEPLAY SCHEDULER (exact ticks), and the kill is decided AT the onset tick — never per-frame —
# so it is fast-forward + replay invariant.
# Story-beat ledges: two small INWARD spurs (negative lane, toward the drum). The lonely
# flure sits in the gap right after the lure section — the player just used a flure that
# answered; this one has no one left to call. The curecumin pad overhangs the well pool at
# the start shelter, its gold glow the first thing seen from the drop-in.
const LONELY_FLURE_POS := Vector3(62.5, 0.5, -6.4)
const CURECUMIN_PAD_POS := Vector3(1.6, 0.5, -6.2)
const BEAT_LEDGE_REGIONS := [
	{"min": [61.8, -7.4], "max": [63.2, -3.5]},
	{"min": [0.8, -7.4], "max": [2.4, -3.5]},
]
# The curecumin portal is a REAL blue PortalPad pair (docs/PORTALS.md): the start ledge
# pad <-> THE NECK GARDEN, a portal-only pocket inside the drum's broken-coil neck (the
# pressure-pocket grid pattern: separated from the deck, the portal is the only edge).
# The garden is the sealed Greenfields threshold; the route READ lives on its gate.
static var CURE_PORTAL_COLOR: Color = LevelPalette.global_color("portal_transit")  # PURPLE per plate A (portal law: red/purple/blue only)
const CURE_DEST_POS := Vector3(42.5, 0.5, -8.6)
const CURE_GATE_POS := Vector3(44.2, 0.5, -8.6)
const CURE_APERTURE_R := 0.77
const NECK_GARDEN_REGION := {"min": [40.2, -9.9], "max": [44.8, -7.4]}

const DRAIN_GUARD_ID := "ch_drain"
const DRAIN_LOOP_S0 := 79.0          # entry leg: the loop leaves the deck rim here
const DRAIN_LOOP_S1 := 83.5          # exit leg: the loop rejoins the deck rim here
const DRAIN_RUN_LANE := 7.0          # the outward flooding channel (radial offset from the deck centreline)
const DRAIN_RUN_HALF := 1.3          # flood footprint half-width in lane (a guard/runner within this band is caught)
const DRAIN_LEDGE_LANE := 9.3        # the DRY lysate ledge across the run — outside the flood band (guard posts here)
const DRAIN_LOOP_PERIOD := 5.0       # the loop's own flood cadence (independent of the section beats)
const DRAIN_LOOP_DUR := 1.6          # how long the run stays flooded per surge
const DRAIN_LOOP_PHASE := 1.0        # stagger from FIRST_FLOOD so the loop isn't synced to section 0
const DRAIN_BAIT_PULL := 6.5         # the bait holds the guard committed in the run a bit longer than one flood
									 # PERIOD, so a surge is GUARANTEED to catch it while it's parked there
const DRAIN_KILL_DELAY := 0.7        # the drowned guard's body lingers this long (cosmetic dissolve) then is removed
const DRAIN_FLORA_POS := Vector3(82.2, 0.5, 3.6) # dry deck between loop legs; clear of bait + flood centre
const FLOOD_SWEEP_INTERVAL := 0.1    # scheduler ticks: visible water is dangerous for its whole window
const DRAIN_DROWN_SWEEPS := 16       # DRAIN_LOOP_DUR / FLOOD_SWEEP_INTERVAL
var _drain_root: Node3D
var _drain_reward: Dictionary = {}
var _drain_water: Array = []         # the run's flood-water segments (toggled by _drain_flooding)
var _drain_flooding := false         # the run is mid-surge this window (scheduler-set)
var _drain_flood_count := 0          # surges fired (for the analytic next-onset read)
var _drowned_count := 0             # guards the current has taken down the drain this run
var _section_drowned_count := 0     # main-relay guards caught by visible section water
var _cadence_t0 := 0.0              # scheduler tick the hazard cadence was (re)armed at — the analytic safe-window
									# reads are relative to THIS, so a reset that re-arms at a non-zero tick stays
									# self-consistent (the real onset and the predicted onset agree)

var _spatial_authority_epoch := -1.0 # fixed cadence for holds, hides, retry state, and exit truth
var _next_spatial_authority_tick := -1.0
var _flooding := []                # cosmetic surge window
var _flood_counts := []            # per section — how many surges have fired (cadence variety / tests)
var _plate_held := []              # per section — derived from canonical positions at the latest sample
## Character-level view of positional work. Unlike _plate_held (the aggregate mechanism truth), this
## also reports a single member on one half of a double plate so the HUD can protect that holder from
## a whole-party rally. The preview host treats this optional dictionary as the generic hold contract.
var _character_holds: Dictionary = {}   # char_id -> {control_id, kind, label, section}
var _sluice_blocked := []          # per section — the sluice gate cells are currently walled off
var _washed := {}                  # char_id -> true: members waiting at the start shelter for physical reunion
var _current_carries := {}         # char_id -> saved knock/return phase while the current owns movement
var _sweep_count := 0              # how many times the party was swept back this run (a "rough run" read)
var _section_wash_counts := []     # per section — times THIS section has washed the party (the flush hint trigger)
var _run_hint_shown := false       # one-shot: after enough washes, a character grumbles that you must RUN the surges
const FLUSH_HINT_THRESHOLD := 3    # the flush hint only appears once a SINGLE section has washed you this many times
# _scheduled is inherited from DataFragmentChunk (same one-time-scheduling guard).
var _wipe_restart_pending := false
var _flow_strips: Array = []
# The surge-telegraph strips ride the helix under their OWN Node3D root, so they survive hide_flat_graybox (which
# hides the chunk's flat direct-child graybox) — the strip is the always-on "about-to-flood" tell, and it
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
var _relay_flures: Array = []      # indexed authored Flures; each owns source + target receipts
var _drain_bait_flure = null
# Concept-plate dressing (WashRelayDressing) + the two story beats. The dressing handle's
# fall materials are driven from the splash-intensity ease; the beats are standalone
# interactables kept OUT of the mechanical arrays (_relay_flures / LURE_SPECS / _portals),
# whose index alignment and counts other systems assert.
var _dressing: Dictionary = {}
var _lonely_flure = null           # a Flure with no targets — it sings, nothing answers
var _curecumin_pad: Area3D = null  # the blue curecumin PortalPad (outbound side)
var _cure_portals: Array = []      # [out, back] — NEVER appended to _portals/_pressure_portals
								   # (transit-breaks asserts those counts)
var _sloperope_deployed := false   # compatibility readback derived from ClimbvineReturn's GameState phase
var _debug_tick := 0               # throttles the CHANNELS_DEBUG position log
var _climbvine_return = null
var _rope_mesh: Node3D             # compatibility presenter alias; now the modeled pothos vine, never a box
var _climb_interactable: Area3D
var _guidance_root: Node3D
var _section_guides: Array = []
var _guidance_section := -1
var _override_controls: Dictionary = {}   # section index -> held console (for cause/effect feedback)

# --- Contextual world verbs ---------------------------------------------------------------
# The cast drawer is reserved for the stable EMP / Wrap roster. Section-specific reads and work live on
# their world targets: Aster SCANS a flow gauge, Peris TENDS the dormant drain flora, and the connect-back
# devices only reunite stranded crew. Stat recovery belongs to a full shelter rest.
const TELEGRAPH_LEAD := 1.2         # seconds before an onset the flow strip brightens (the surge tell)
const SURGE_CLOSE_MARGIN := 0.75     # amber when a crossing nearly touches an active-water window
var _surge_timing_learned := false  # run knowledge: a visible surge/telegraph unlocks timing
# THE FLOW TERMINAL + scheduled-crossing assist (director redesign; docs in the builder).
const FLOW_ASSIST_SECTION := 1      # the "current" section — its window is too narrow to eyeball
const FLOW_ASSIST_POLL := 0.25
const FLOW_CROSS_SPEED := 6.0       # the run-speed budget the window math prices against
const FLOW_CROSS_MARGIN := 0.35
var _flow_terminal: Area3D = null
var _flow_logged := false
var _flow_assist_busy_until := -1.0
var _flow_assist_prev_speeds := {}
var _flow_assist_held: Array = []
var _flow_barked := {}              # member id -> already barked at the terminal once
var _drain_flora_interactable: Area3D
var _drain_flora_tended := false
var _flora_lights: Array = []       # persistent run lights: [{pos, node}]
var _flora_light_root: Node3D

# Every consequential relay input is an exact physical source. The Interactable registry owns
# the accepted edge; this chunk stores the last monotonic receipt whose consequence it consumed.
# `action_id -> {source, kind, index}` stays presenter-local while the counts are portable.
var _wash_control_sources: Dictionary = {}
var _wash_control_committed_counts: Dictionary = {}

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
# --- Build ---

func _section_color(t: String) -> Color:
	# One color authority: the palette registry's sections table (the same table
	# the dressing GLB's gate signs paint from), so a retune lands everywhere.
	var c := LevelPalette.color("channels", "sections/" + t)
	if c != LevelPalette.MISSING:
		return c
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
	_wash_control_sources.clear()
	_wash_control_committed_counts.clear()
	_relay_flures.clear()
	_section_enemy_currents.clear()
	_enemy_drown_mirrors.clear()
	_drain_bait_flure = null
	_drain_enemy_current = null
	var traversal_gs = _get_game_state()
	if traversal_gs != null and traversal_gs.has_signal("external_traversal_finished") \
			and not traversal_gs.external_traversal_finished.is_connected(
				_on_wash_external_traversal_finished):
		traversal_gs.external_traversal_finished.connect(_on_wash_external_traversal_finished)
	if traversal_gs != null and traversal_gs.has_signal("external_traversal_cancelled") \
			and not traversal_gs.external_traversal_cancelled.is_connected(
				_on_wash_external_traversal_cancelled):
		traversal_gs.external_traversal_cancelled.connect(
			_on_wash_external_traversal_cancelled)
	# A newly attached chunk can receive one process frame before its host calls reset_preview_state().
	# Give that bootstrap frame complete neutral mechanism truth; otherwise the positional plate poll can index
	# the still-empty arrays and abort before save authority has a chance to attach.
	_flooding.clear(); _plate_held.clear(); _sluice_blocked.clear(); _flood_counts.clear()
	_section_wash_counts.clear(); _section_flood_until.clear()
	for _i in range(SECTIONS.size()):
		_flooding.append(false); _plate_held.append(false); _sluice_blocked.append(false)
		_flood_counts.append(0); _section_wash_counts.append(0); _section_flood_until.append(-1.0)
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
			_section_color(t) * 0.6, _section_color(t), STRIP_IDLE_ENERGY, 0.03)
		_flow_strips.append(strip)
		# ONE flow terminal, at the section whose safe window is deliberately too narrow to
		# time by eye (director redesign 2026-07-25: the nine per-section SCAN FLOW gauges
		# are gone — observation covers ordinary sections; the terminal owns the brutal one).
		if i == FLOW_ASSIST_SECTION:
			_build_flow_terminal(strip)
		# the disable control: an override console past the section, or a held plate before it
		if str(s["disable"]) == "override":
			var ov := _add_interactable(self, "Override%d" % i, "Flow override", Vector3(x1 + 1.5, 0.5, 0.0),
				"OVERRIDE", "", 1.0, false, 1.6, Interactable.InteractableType.INSPECTION, false)
			# the override body is the Terminal PIECE (no placeholder box); the teal
			# affordance stays as a small emissive cap on its head
			var ovm: Node3D = ArchetypePieceLibrary.instantiate("terminal")
			if ovm == null:
				ovm = _add_box(ov, Vector3(0.0, 0.1, 0.0), Vector3(0.6, 1.0, 0.4),
					Color(0.2, 0.45, 0.5), Color(0.3, 0.9, 1.0), 1.0)
			else:
				ovm.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * 0.8),
					Vector3(0.0, -0.5, 0.0))
				ov.add_child(ovm)
				_add_box(ov, Vector3(0.0, 0.78, -0.14), Vector3(0.3, 0.1, 0.06),
					Color(0.2, 0.45, 0.5), Color(0.3, 0.9, 1.0), 1.2)
			_outline_interactable_child(ov, ovm, "Override%d" % i, 1.6)
			_configure_wash_control(
				ov, "override:%d" % i, "override", i,
				_on_override.bind(i, ov))
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
	_build_enemy_current_channels()
	_build_splash_planes()
	_wdbg("pipe splashes built")
	_dressing = WashRelayDressing.build(self, SECTIONS)
	_build_story_beats()
	_build_light_rig()
	_make_dressing_wet()
	# Vasculature overlay PULLED (director 2026-07-28: the current Voronoi pass
	# reads wrong on the drum). The generator stays; redesign against the organics
	# plate before re-enabling.
	#_apply_vasculature()
	_build_organic_props()
	_build_concept_props()
	_build_structural_scaffold()
	_apply_material_response()
	_build_reflection_probe()
	_wdbg("dressing + story beats built")
	# This chunk authors its environment directly instead of calling DataFragmentChunk._build_chunk(),
	# so it must opt into the shared full-wipe signal explicitly.
	var gs = _get_game_state()
	if gs != null and not gs.character_downed.is_connected(_on_wash_relay_character_downed):
		gs.character_downed.connect(_on_wash_relay_character_downed)
	if gs != null and gs.has_signal("character_restored") \
			and not gs.character_restored.is_connected(_on_wash_relay_character_restored):
		gs.character_restored.connect(_on_wash_relay_character_restored)
	# Scene attachment is an explicit simulation boundary. Arm gameplay authority here so a render
	# frame or a test-only headless presenter call is never required to start the truthful machine.
	_quiet_interactable_labels()
	_activate_wash_relay()

## THE FLOW TERMINAL (replaces the nine SCAN FLOW gauges). Aster-only: another member
## clicking it barks that only Aster might parse it. Aster logs the channel's cadence on
## his device; from then on, a crossing attempt at this section HOLDS the group at the
## edge and the SCHEDULER computes the next safe window analytically and issues the
## crossing moves at it (all real logged commands — replay + fast-forward invariant).
func _build_flow_terminal(strip: Node3D) -> void:
	var section: Dictionary = SECTIONS[FLOW_ASSIST_SECTION]
	var pos := Vector3(float(section["x0"]) - 1.25, 0.5, -2.5)
	var term := _add_interactable(self, "FlowTerminal", "Log the surge cadence", pos,
		"LOG THE SURGE", "aster", 1.1, false, 1.5,
		Interactable.InteractableType.INSPECTION, false)
	term.consequence_preview = "Aster logs this channel's timing; crossings then wait out the surge automatically."
	# the body is the concept-pass Terminal PIECE (wood core in iron straps, green
	# matrix head) — the interactable/outline wiring is unchanged, only the mesh
	var body: Node3D = ArchetypePieceLibrary.instantiate("terminal")
	if body == null:
		body = _add_box(term, Vector3(0.0, 0.18, 0.0), Vector3(0.62, 1.15, 0.42),
			Color(0.08, 0.25, 0.32), Color.BLACK, 0.0)
	else:
		body.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, -0.5, 0.0))
		term.add_child(body)
		# the matrix head casts its own green spill — without it the dark wood
		# body vanishes at night and the screen floats as a bare glowing slab
		var screen_spill := OmniLight3D.new()
		screen_spill.light_color = Color(0.36, 0.91, 0.5)
		screen_spill.light_energy = 0.8
		screen_spill.omni_range = 3.2
		screen_spill.shadow_enabled = false
		screen_spill.position = Vector3(0.0, 1.05, 0.5)
		term.add_child(screen_spill)
	_outline_interactable_child(term, body, "FlowTerminal", 1.5)
	_configure_wash_control(
		term, "flow_terminal", "flow_terminal", FLOW_ASSIST_SECTION,
		_on_flow_terminal.bind(term))
	term.interaction_rejected.connect(_on_flow_terminal_rejected)
	_flow_terminal = term
	_add_causal_feedback_link(term, strip, Color(0.29, 0.62, 1.0), {
		"source_offset": Vector3(0.0, 0.9, 0.0),
		"target_offset": Vector3(0.0, 0.35, 0.0),
		"arc_height": 1.2,
		"owner_character": "aster",
		"name": "FlowTerminalLink",
	})

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

## The flood surface as ONE world-space triangle strip riding the helix arc: two verts per
## sample across the lane band, normals up, UV.u tiling along s (one tile per WATER_SEG).
func _build_water_ribbon(x0: float, x1: float, half_lane: float, y_off: float) -> MeshInstance3D:
	# The node's ORIGIN sits at the section's arc midpoint and vertices are baked
	# relative to it — so the ribbon's position is meaningful (the telegraph test
	# uses it as the on-helix reference), not an identity transform at world zero.
	var origin := ChannelsArc.arc_pos((x0 + x1) * 0.5, 0.0) + Vector3.UP * y_off
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := maxi(4, int(ceil((x1 - x0) / 0.75)))
	for k in range(n + 1):
		var sx := lerpf(x0, x1, float(k) / float(n))
		var u := (sx - x0) / WATER_SEG
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u, 0.0))
		st.add_vertex(ChannelsArc.arc_pos(sx, -half_lane) + Vector3.UP * y_off - origin)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u, 1.0))
		st.add_vertex(ChannelsArc.arc_pos(sx, half_lane) + Vector3.UP * y_off - origin)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = origin
	return mi

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
		# ONE arc-following ribbon per section (asset-autopsy ruling: the old overlapping
		# box segments double-blended at every seam and showed their side walls — the
		# "water is a bunch of rectangles" read). Top surface only, one draw, exact arc.
		var seg := _build_water_ribbon(x0, x1, FLOOR_Z_HALF * 0.9, 0.42)
		_water_root.add_child(seg)
		seg.material_override = _make_water_material(i)
		seg.visible = false
		_section_water.append([seg])
		if str(s["type"]) == "sluice":
			# the gate stands across the threshold while closed (a visible, real blocker — not invisible)
			var gate := _warped_box(_water_root, (x0 + x1) * 0.5, 0.0,
				Vector3(FLOOR_Z_HALF * 1.8, 2.4, 0.3), Color(0.14, 0.07, 0.06), Color(1.0, 0.3, 0.18), 0.35, 1.2)
			for gx in [-2.4, 0.0, 2.4]:
				var leaf: Node3D = ArchetypePieceLibrary.instantiate("door_ironband")
				if leaf != null:
					leaf.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * 1.35),
						Vector3(gx, -1.2, 0.18))
					_tint_piece(leaf, Color(1.0, 0.3, 0.18), 0.6)
					gate.add_child(leaf)
			gate.visible = false
			_sluice_gate[i] = gate

# The connect-back joins the start landing to the already-reached chunk end. The reusable kit object owns
# both causal phases: Peris tends the upper pothos, then stranded characters enter a saved locked traversal
# at the lower mouth. This chunk only supplies endpoints, timing, selection policy, and feedback.
func _build_connect_backs() -> void:
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		push_warning("Wash Relay climbvine could not bind without GameState and scheduler")
		return
	_climbvine_return = ClimbvineReturnScript.new()
	_climbvine_return.name = "WashRelayClimbvineReturn"
	var configured := bool(_climbvine_return.configure(
		gs,
		sched,
		CLIMB_POS,
		RETURN_LANDING,
		ChannelsArc.arc_pos(CLIMB_POS.x, CLIMB_POS.z),
		ChannelsArc.arc_pos(RETURN_LANDING.x, RETURN_LANDING.z),
		{
			"return_id": SLOPEROPE_RETURN_ID,
			"interaction_radius": 1.7,
			"deployment_duration": SLOPEROPE_DEPLOY_DURATION,
			"climb_duration": SLOPEROPE_CLIMB_DURATION,
		}
	))
	if not configured:
		_climbvine_return.free()
		_climbvine_return = null
		push_warning("Wash Relay climbvine rejected its authored endpoints")
		return
	_climbvine_return.set_group_provider(Callable(self, "_wash_climb_group"))
	_climbvine_return.deployment_started.connect(_on_climbvine_deployment_started)
	_climbvine_return.vine_deployed.connect(_on_climbvine_deployed)
	_climbvine_return.climb_committed.connect(_on_climbvine_committed)
	_climbvine_return.tend_rejected.connect(_on_climbvine_tend_rejected)
	add_child(_climbvine_return)
	var upper: Area3D = _climbvine_return.get_upper_interactable()
	_climb_interactable = _climbvine_return.get_lower_interactable()
	upper.name = "ClimbvineTendAnchor"
	_climb_interactable.name = "ClimbLine"
	for interactable in _climbvine_return.get_interactables():
		_register_interactable(interactable)
	_rope_mesh = _climbvine_return.get("_vine_visual") as Node3D
	_sync_climbvine_presenter()


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
		_s: float = 0.0, _lane: float = 0.0, _color: Color = Color.WHITE, _y := 0.0) -> void:
	# Wayfinding text is CUT (director ruling: light and color carry direction; text was
	# noise). The signature stays so authored call sites remain as intent documentation.
	return

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
		var sec_cluster := "sec_%d" % i
		match kind:
			'flush':
				_setpiece_arch(root, x0 + 0.7, base, 3.6)
				# the flush SOURCE reads as a grounded manifold (nothing exists at
				# height to hang a spout from — measured, not assumed)
				_setpiece_piece(root, "junction", cx, 3.8, 0.0, PI * 0.5,
					ACCENT_WATER, 0.45, sec_cluster, "floor", false, 1.25)
				_setpiece_rail_run(root, x0, x1, -3.25, base, 0.0, sec_cluster)
			'current':
				for lane in [-2.8, 2.8]:
					_setpiece_rail_run(root, x0, x1, lane, base, 0.0, sec_cluster)
				for sc in [x0 + 1.0, cx, x1 - 1.0]:
					_setpiece_mesh(root, 'FlowFin', sc, 0.0, Vector3(3.6, 0.08, 0.5),
						base * 0.45, ACCENT_WATER, 0.8, 0.12)   # floor light-language: flow chevrons
			'jet':
				_setpiece_arch(root, cx, base, 3.9)
				# the nozzle BANK sits along ONE lane, fed by a rack of pipes at its
				# back — machinery a crew installed from the wall side, not a
				# symmetric scatter. Ember accent: this hardware hurts.
				for sc in [x0 + 1.0, cx, x1 - 1.0]:
					_setpiece_piece(root, "junction", sc, -2.45, 0.0, 0.0,
						ACCENT_EMBER, 0.5, sec_cluster, "floor", false, 0.55)
				_setpiece_piece(root, "pipe_rack", cx, -3.3, 0.0, -PI * 0.5,
					base, 0.0, sec_cluster)
			'plate':
				for lane in [-1.15, 1.15]:
					_setpiece_rail_run(root, x0, x1, lane, base, 0.0, sec_cluster)
				# the hold-station is a valve column a worker tends: work amber
				_setpiece_piece(root, "water_control", x0 - 0.65, -2.7, 0.0, 0.0,
					ACCENT_WORK, 0.7, sec_cluster, "floor", false, 1.4)
			'sluice':
				_setpiece_arch(root, x0 + 0.25, base, 4.3)
				_setpiece_arch(root, x1 - 0.25, base, 4.3)
				# the overhead header is trussed between the arch legs — bare rusted
				# iron; the gate leaves below carry the only warning color here
				for hl in [-2.7, -0.9, 0.9, 2.7]:
					_setpiece_piece(root, "scaffold_truss", cx, hl, 4.15, 0.0,
						base, 0.0, "arch_%d" % roundi((x0 + 0.25) * 10.0),
						"attached", true)
			'patrol':
				for lane in [-3.15, 3.15]:
					# the hide alcove keeps its taught cyan glow, dimmed to a coal
					_setpiece_piece(root, "hide_slot", cx, lane, 0.0,
						PI * 0.5 if lane > 0.0 else -PI * 0.5,
						ACCENT_WATER, 0.45, sec_cluster, "floor", false, 1.05)
				_setpiece_arch(root, x1 - 0.5, base, 3.7)
			'lure':
				for sc in [x0 + 0.55, x1 - 0.55]:
					_setpiece_arch(root, sc, base, 3.5)
				# the beacon leg smolders the ORGANIC violet — the register of the
				# overgrowth it stands in, not a hot magenta stick
				_setpiece_piece(root, "scaffold_leg", cx, 0.0, 0.0, 0.0,
					ACCENT_ORGANIC, 0.6, sec_cluster)
			'basin':
				for sc in [x0 + 1.0, cx, x1 - 1.0]:
					# pump columns: tall valve stations along the basin rim
					_setpiece_piece(root, "water_control", sc, 3.15, 0.0, 0.0,
						ACCENT_WATER, 0.55, sec_cluster, "floor", false, 2.0)
				for lane in [-3.35, 3.35]:
					_setpiece_rail_run(root, x0, x1, lane, base, 0.0, sec_cluster)
			'double_plate':
				for lane in [-DOUBLE_PLATE_Z, DOUBLE_PLATE_Z]:
					_setpiece_piece(root, "water_control", x0 - 0.55, lane, 0.0, 0.0,
						ACCENT_WORK, 0.8, sec_cluster, "floor", false, 1.55)
				for lane in [-1.0, 1.0]:
					_setpiece_rail_run(root, x0, x1, lane, base, 0.0, sec_cluster)
				_setpiece_arch(root, x1 - 0.35, base, 4.0)
		_section_setpiece_count += 1


func _setpiece_mesh(parent: Node3D, node_name: String, s: float, lane: float, size: Vector3,
		color: Color, emission := Color.BLACK, energy := 0.0, y_off := 0.0) -> MeshInstance3D:
	var mesh := _warped_box(parent, s, lane, size, color, emission, energy, y_off)
	mesh.name = node_name
	return mesh


## Section-identity TINT for a placed piece: every surface material is duplicated
## once and given the section's emission colour — the wayfinding-by-colour law
## survives the primitive-to-piece swap.
func _tint_piece(piece: Node3D, color: Color, energy: float) -> void:
	if piece == null:
		return
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
					# The tint is a hue CUE riding the piece's shaded albedo, never a
					# repaint: at full energy the emission swamps the lighting term and
					# the whole piece photographs as a flat colored cutout in dark bays.
					dup.emission_energy_multiplier = energy * 0.3
					mi.set_surface_override_material(si, dup)
		for c in n.get_children():
			stack.append(c)


## A tinted piece placed on the setpiece layer (rides the warp, carries survey meta).
func _setpiece_piece(parent: Node3D, pid: String, s: float, lane: float, y_off: float,
		yaw: float, tint: Color, energy: float, cluster: String,
		mount := "floor", embed := false, piece_scale := 1.0) -> Node3D:
	var piece := _warp_piece(pid, s, lane, y_off, yaw, parent, pid.capitalize(),
		mount, embed, cluster)
	if piece == null:
		return null
	if piece_scale != 1.0:
		piece.transform = piece.transform.scaled_local(Vector3.ONE * piece_scale)
	if energy > 0.0:
		_tint_piece(piece, tint, energy)
	return piece


## The section ARCH is two scaffold legs (scaled to the arch height) and a trussed
## lintel — BARE structure by the grunge law (the color param is kept for the call
## sites' intent record but never painted; the gate light carries section identity).
func _setpiece_arch(parent: Node3D, s: float, _color: Color, height: float) -> void:
	var cluster := "arch_%d" % roundi(s * 10.0)
	for lane in [-3.35, 3.35]:
		_setpiece_piece(parent, "scaffold_leg", s, lane, 0.0, 0.0, Color(), 0.0,
			cluster, "floor", false, height / 3.2)
	for hl in [-2.7, -0.9, 0.9, 2.7]:                    # the lintel, trussed leg-to-leg
		_setpiece_piece(parent, "scaffold_truss", s, hl, height - 1.15, 0.0,
			Color(), 0.0, cluster, "attached", true)


## A low RAIL RUN along a span: railing_run modules tiled every 2 m, tinted.
func _setpiece_rail_run(parent: Node3D, x0: float, x1: float, lane: float,
		tint: Color, energy: float, cluster: String) -> void:
	var s := x0 + 1.0
	while s < x1 - 0.6:
		_setpiece_piece(parent, "railing_run", s, lane, 0.0, -PI * 0.5, tint, energy, cluster)
		s += 2.0


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

# Generate ONE stretch (one node per realized offshoot) through the archetype framework. Each node hands a
# branch its archetype + content placements. Falls back to a fixed archetype rotation so offshoots still build if
# the generation catalog is unavailable (the chunk never hard-fails on missing data).
func _generate_branch_nodes(count: int) -> Array:
	var spec: Dictionary = StretchGenerator.generate({
		"id": "wash_relay_branches", "title": "Wash Relay Branches",
		"seed": BRANCH_GEN_SEED, "complexity_tier": "developing", "progression_stage": 3,
		"budget": {"node_count": count, "branch_count": 0},
		# These are the three causal grammars this authored branch curriculum must realize. The seed may
		# choose variants and content, but it may not silently turn the whole optional layer into five
		# copies of one interaction. With five realized branches, the three interior nodes teach one
		# physical counterweight, one flora-flow gate, and one enemy-redirection gate.
		"limitations": {"required": {"archetypes": ["1", "2", "3"]}},
	})
	if bool(spec.get("ok", false)):
		var nodes: Array = spec.get("nodes", [])
		if nodes.size() >= count:
			return nodes.slice(0, count)
	var fallback: Array = []
	# The fallback preserves the same boundary -> causal trio -> boundary shape as the generated spec.
	# Redirect carries a concrete actor marker so even catalog failure cannot degrade its decoy into a label.
	var names := ["Narrative beat", "Carry the heavy thing", "Plant as tool",
		"Redirected enemy aggression", "Narrative beat"]
	for i in range(count):
		var archetype_name: String = str(names[i % names.size()])
		fallback.append({
			"archetype_name": archetype_name,
			"content_placements": [],
			"enemies": [{"role": "redirected_guard"}] \
				if archetype_name == "Redirected enemy aggression" else [],
		})
	return fallback

func _build_branches() -> void:
	_branches.clear()
	_branch_guard_spawns.clear()
	_branch_root = Node3D.new()
	_branch_root.name = "Branches"
	add_child(_branch_root)
	var mids := _gap_mids()
	var realized_branch_count := 0
	for mid_v in mids:
		if not _is_authored_transit_gap(float(mid_v)):
			realized_branch_count += 1
	_wdbg("generating %d branch nodes" % realized_branch_count)
	# Generate exactly the branches that reach the world. The previous eight-node call discarded three
	# interior nodes at authored transit gaps, so the causal archetypes chosen for those nodes never existed
	# in play and a valid seed could accidentally leave only boundary/open and decoy branches.
	var nodes := _generate_branch_nodes(realized_branch_count)
	_wdbg("generated %d nodes" % nodes.size())
	var guards_spawned := 0
	var node_cursor := 0
	for g in range(mids.size()):
		var mid: float = mids[g]
		if _is_authored_transit_gap(mid):
			continue
		var branch_i := _branches.size()
		var node: Dictionary = nodes[node_cursor] if node_cursor < nodes.size() else {}
		node_cursor += 1
		var archetype := str(node.get("archetype_name", "Offshoot"))
		var placements: Array = node.get("content_placements", [])
		# The radial plank: juts off the deck rim (lane 4) out to the pad (lane 10), pre-warped onto the helix.
		var deck_color := Color(0.12, 0.14, 0.17)
		_clad_deck(_branch_root, mid, BRANCH_DECK_CENTER_LANE,
			Vector3(BRANCH_LANE_SPAN, 0.2, BRANCH_S_SPAN), "branchdeck_%d" % roundi(mid * 10.0))
		_add_warped_deck(mid, BRANCH_DECK_CENTER_LANE, Vector3(BRANCH_LANE_SPAN, 0.2, BRANCH_S_SPAN),
			deck_color, "deck_metal")
		# A marker post at the deck rim so the offshoot reads as a turn-off from the main run.
		_add_warped_box(mid, BRANCH_NECK_LANE + 0.4, Vector3(0.4, 1.6, 0.4),
			LevelPalette.color("channels", "wood"), LevelPalette.global_color("warning_amber"), 1.1)
		_add_warped_guidance_label(_branch_root, "BranchOptional%d" % g, "OPTIONAL // LYSATE",
			mid, BRANCH_NECK_LANE + 0.9, LevelPalette.global_color("warning_amber"))
		# The archetype's content placements, clustered on the pad (graybox identity of the puzzle).
		var content_count := _build_branch_content(mid, placements)
		# The interaction is a work beat around one exact GameState item. The dark cradle is only an
		# affordance/outline target; the luminous lysate body is the actual source and remains inspectable
		# before pickup, in a hand, after transfer, and through save/replay.
		var source_pos := Vector3(mid, 0.5, BRANCH_PAD_LANE)
		var cache := _add_interactable(self, "BranchCache%d" % g, "Take the branch lysate",
			source_pos, "TAKE LYSATE", "", 1.2, true, 1.6,
			Interactable.InteractableType.TIMED_ACTION, false)
		var cradle := _add_reward_cradle(cache, "BranchCacheCradle%d" % g)
		_outline_interactable_child(cache, cradle, "BranchCache%d" % g, 1.6)
		_configure_wash_control(
			cache, "branch_cache:%d" % g, "branch_cache", branch_i,
			_on_branch_cache.bind(branch_i, cache))
		# A guarded branch (the archetype carries an enemy) spawns a roamer on the pad — a real risk detour.
		var guard = null
		if guards_spawned < BRANCH_GUARD_CAP and _branch_has_enemy(node):
			guard = _spawn_branch_guard(g, mid)
			if guard != null:
				guards_spawned += 1
		# The mechanism is the branch's causal model, not a coloured synonym for one boolean. A lever owns a
		# physical threshold, a flora valve owns a visible pollen stock, and a guarded decoy owns the guard's
		# actual travel. Forage/narrative branches remain deliberate breathers.
		var gate_kind := _branch_gate_kind(archetype, guard != null)
		var switch = null
		if gate_kind != "open":
			cache.set_interaction_enabled(false)
			switch = _build_branch_switch(g, branch_i, mid, gate_kind)
		var branch := {
			"gap": g, "mid_x": mid, "pad_lane": BRANCH_PAD_LANE, "archetype": archetype,
			"content_count": content_count, "collected": false, "cache": cache, "guard": guard,
			"gate_kind": gate_kind, "unlocked": gate_kind == "open", "switch": switch,
			"mechanism_phase": "clear" if gate_kind == "open" else "idle",
			"phase_started_at": -1.0, "phase_deadline": -1.0, "next_check_at": -1.0,
			"mechanism_context": {},
			"reward_source_key": _branch_reward_source_key(g),
			"reward_source_pos": source_pos,
			"reward_atp": _branch_reward_value(gate_kind),
			"reward_tier": _branch_reward_tier(gate_kind),
			"reward_item_id": "",
			"reward_phase": REWARD_PHASE_AVAILABLE,
			"reward_claimed_by": "",
			"reward_claim_serial": 0,
		}
		cache.consequence_preview = "Moves the visible +%d ATP lysate into this character's free hand." \
			% int(branch["reward_atp"])
		branch.merge(_build_branch_mechanism(mid, gate_kind), true)
		branch["mechanism_context"] = _branch_default_context(branch)
		_reset_reward_to_source(branch)
		_branches.append(branch)
		_apply_branch_mechanism_truth(branch)


func _add_reward_cradle(cache: Node3D, node_name: String) -> MeshInstance3D:
	# the cradle body is the ForageCache PIECE (a real lidded basin, not a disc)
	var piece := ArchetypePieceLibrary.instantiate("forage_cache")
	var cradle: MeshInstance3D
	if piece is MeshInstance3D:
		cradle = piece as MeshInstance3D
		cradle.name = node_name
		cradle.transform = Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3.ONE * 0.72),
			Vector3(0.0, -0.42, 0.0))
	else:
		cradle = MeshInstance3D.new()
		cradle.name = node_name
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.42
		mesh.bottom_radius = 0.5
		mesh.height = 0.14
		mesh.radial_segments = 18
		cradle.mesh = mesh
		cradle.position = Vector3(0.0, -0.3, 0.0)
		cradle.material_override = _make_material(
			Color(0.12, 0.14, 0.12), Color(0.32, 0.45, 0.2), 0.2)
	cache.add_child(cradle)
	return cradle


func _branch_reward_source_key(gap: int) -> String:
	return REWARD_SOURCE_PREFIX + "branch:%d" % gap


func _branch_reward_value(gate_kind: String) -> int:
	match gate_kind:
		"decoy":
			return BRANCH_GUARDED_REWARD
		"lever", "valve":
			return BRANCH_GATED_REWARD
	return BRANCH_GUIDANCE_REWARD


func _branch_reward_tier(gate_kind: String) -> String:
	match gate_kind:
		"decoy":
			return "guarded"
		"lever", "valve":
			return "gated"
	return "guidance"


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
		var content_id := str(p.get("id", ""))
		# A placement whose noun has a library body wears the REAL piece (visual
		# only — the noun's verb stays with its runtime binding); unknown nouns
		# keep the palette-tinted graybox marker.
		var piece := ArchetypePieceLibrary.instantiate(content_id) \
			if ArchetypePieceLibrary.has_piece(content_id) else null
		if piece != null:
			# Unique across ALL branches (mid disambiguates) or Godot @-renames a
			# repeated content id and the census misses it. Pieces are authored
			# base-at-origin; the plank deck is a 0.2 slab centred on mid's arc
			# height, so the base sits at the DECK TOP at mid — not at the local
			# arc height, which climbs KCLIMB per s and would bury a slot.
			piece.name = "BranchContent_%d_%s_%d" % [roundi(mid * 10.0), content_id, count]
			var xf := _branch_warp_xform(mid + off.x, BRANCH_PAD_LANE + off.y)
			xf.origin.y = _branch_warp_xform(mid, BRANCH_PAD_LANE).origin.y + 0.1
			piece.transform = xf
			_branch_root.add_child(piece)
		else:
			var sz := _branch_marker_size(p.get("size", []))
			var cat := str(p.get("category", ""))
			var marker := _add_warped_box(mid + off.x, BRANCH_PAD_LANE + off.y, sz,
				_branch_content_color(cat), Color.BLACK, 0.0)
			marker.material_override = _tinted_tile_material(
				_branch_content_tile(cat), _branch_content_color(cat))
		count += 1
	return count

func _branch_marker_size(raw_size: Variant) -> Vector3:
	if raw_size is Array and (raw_size as Array).size() >= 3:
		var a := raw_size as Array
		return Vector3(clampf(float(a[0]), 0.4, 1.2), clampf(float(a[1]), 0.4, 1.2), clampf(float(a[2]), 0.4, 1.2))
	return Vector3(0.7, 0.7, 0.7)

func _branch_content_color(category: String) -> Color:
	match category:
		"flora": return LevelPalette.color("channels", "moss")
		"enemies": return LevelPalette.color("channels", "rust")
		"structures": return LevelPalette.color("channels", "iron")
	return LevelPalette.color("channels", "pipe")

## The atlas tile a generated content marker wears — categories share the level's
## material language instead of flat unauthored fills.
func _branch_content_tile(category: String) -> String:
	match category:
		"flora": return "biolum_teal"
		"enemies": return "rust_iron"
	return "facility_metal"

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

## Clad a warped deck slab in TILE pieces (2 m module, hash-alternated variants) —
## the slab stays as the collision-bearing iron substrate; the walked surface is
## library planks and grates (the no-placeholder law for decks).
func _clad_deck(root: Node3D, s: float, lane_center: float, size: Vector3, cluster: String,
		embed := false) -> void:
	var n_lane := int(size.x / 2.0)
	var n_s := int(size.z / 2.0)
	if n_lane < 1 or n_s < 1:
		return
	for i in range(n_lane):
		for j in range(n_s):
			var lane := lane_center + (i - (n_lane - 1) * 0.5) * 2.0
			var sp := s + (j - (n_s - 1) * 0.5) * 2.0
			var h := (roundi(sp * 10.0) * 7 + roundi(lane * 10.0) * 13 + i * 3 + j * 5) % 7
			var pid := "deck_planks"
			match h:
				1: pid = "deck_planks_b"
				2: pid = "deck_planks_c"
				3: pid = "deck_grate"
				5: pid = "deck_grate_b"
			_warp_piece(pid, sp, lane, size.y, -PI * 0.5, root,
				"DeckTile", "floor", embed, cluster)


func _add_warped_deck(s: float, lane_center: float, size: Vector3, color: Color, tile := "") -> void:
	var mesh := _add_warped_box(s, lane_center, size, color)
	if tile != "":
		mesh.material_override = _tinted_tile_material(tile, color)
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
		# the break edge is BROKEN PIER planks, splintered ends pointing into the gap
		var lip_yaw := -PI * 0.5 if edge_s == PRESSURE_GAP_S0 else PI * 0.5
		var lip_s: float = edge_s + (0.9 if edge_s == PRESSURE_GAP_S0 else -0.9)
		for lip_lane in [-2.0, 0.0, 2.0]:
			_setpiece_piece(_transit_root, "broken_pier", lip_s, lip_lane, 0.06,
				lip_yaw, Color(1.0, 0.38, 0.14), 0.5, "coilbreak", "wall", true)

	_add_transit_deck(PRESSURE_ROOM_CENTER.x, PRESSURE_ROOM_CENTER.z,
		Vector3(4.4, 0.24, 5.2), Color(0.09, 0.14, 0.18))
	_clad_deck(_transit_root, PRESSURE_ROOM_CENTER.x, PRESSURE_ROOM_CENTER.z,
		Vector3(4.4, 0.24, 5.2), "pressure_deck", true)   # the room is a carved void
	for sc in [21.6, 25.8]:                                # measured: the room deck spans 21.5..25.9
		for lane in [-10.2, -6.0]:
			_setpiece_piece(_transit_root, "scaffold_leg", sc, lane, 0.0, 0.0,
				Color(0.45, 0.82, 1.0), 0.55, "pressure", "attached", true)
	for hs2 in [22.4, 25.0]:
		_setpiece_piece(_transit_root, "scaffold_truss", hs2, -10.05, 2.9, -PI * 0.5,
			Color(0.3, 0.75, 1.0), 0.55, "pressure", "attached", true)
	for ws in [21.6, 23.7, 25.8]:
		# the room's lit windows are porthole assemblies on the inner frame line
		_setpiece_piece(_transit_root, "porthole", ws, -6.0, 0.55, PI * 0.5,
			Color(0.22, 0.7, 1.0), 0.6, "pressure", "attached", true)

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

	# THE portal look (docs/PORTALS.md) on both reversible pressure pairs: arch + live lens.
	PortalFixtures.dress_matching(_pressure_portals)
	_pressure_valve = _add_interactable(self, 'PressureValve', 'Vent the jet manifold', PRESSURE_VALVE_POS,
		'VENT JETS', '', 1.25, false, 1.65, Interactable.InteractableType.TIMED_ACTION, false)
	_configure_wash_control(
		_pressure_valve, "pressure_valve", "pressure_valve", -1,
		_on_pressure_valve.bind(_pressure_valve))
	# the valve body is the WaterControl PIECE (bolted column + spoked wheel)
	var wheel: Node3D = ArchetypePieceLibrary.instantiate("water_control")
	if wheel == null:
		wheel = _add_box(_pressure_valve, Vector3(0.0, 0.65, 0.0), Vector3(0.9, 1.3, 0.55),
			Color(0.12, 0.3, 0.34), Color(0.2, 0.9, 1.0), 1.2)
	else:
		wheel.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, -0.5, 0.0))
		_pressure_valve.add_child(wheel)
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
	var prev_pt := Vector3(SLUICE_TUNNEL_MOUTH_A.x, 0.5, SLUICE_TUNNEL_MOUTH_A.z)
	for point_v in SLUICE_TUNNEL_DATA_PATH:
		var point := point_v as Vector3
		var seg := Vector2(point.x - prev_pt.x, point.z - prev_pt.z)
		if seg.length() > 0.3:
			# one pipe per SEGMENT, oriented along it — the run reads continuous
			# and every barrel overlaps its neighbour (chain support to the mouths)
			_setpiece_piece(_transit_root, "pipe",
				(prev_pt.x + point.x) * 0.5, (prev_pt.z + point.z) * 0.5, 0.0,
				-PI * 0.5 + atan2(seg.y, seg.x),
				Color(0.28, 0.75, 0.86), 0.5, "sluicepipe", "attached", true,
				seg.length() / 1.15)
		prev_pt = point

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
	# the crawl mouth wears a full door frame (the leaf reads as the hatch you
	# crawl through), teal-tinted to the tunnel's conceal grammar
	_setpiece_piece(_transit_root, "door_ironband", s, lane, 0.0, 0.0,
		Color(0.28, 0.82, 0.9), 0.6, "sluicepipe", "floor", false, 1.1)


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
# curve), a stub out to the DRY lysate ledge across the water, the run's flood-water (hidden until it surges),
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
	# The stub out to the DRY lysate ledge (crossing the run reaches it) + the ledge pad itself.
	_add_drain_deck(smid, (DRAIN_RUN_LANE + DRAIN_LEDGE_LANE + 0.6) * 0.5,
		Vector3((DRAIN_LEDGE_LANE + 0.6) - DRAIN_RUN_LANE, 0.2, 2.0), Color(0.11, 0.15, 0.18))
	# Outer "water source" wall along the loop's OUTER RIM, just past the lysate ledge (the side the surge wells
	# up from). Placed beyond the ledge so it bounds the loop instead of bisecting the run->ledge crossing.
	_warped_box(_drain_root, smid, DRAIN_LEDGE_LANE + 0.7, Vector3(0.3, 2.6, run_len + 1.0),
		Color(0.12, 0.13, 0.16), Color(0.15, 0.4, 0.6), 0.5)
	_warped_box(_drain_root, smid, DRAIN_LEDGE_LANE, Vector3(0.4, 1.6, 0.4),
		Color(0.48, 0.3, 0.08), Color(1.0, 0.64, 0.18), 1.0)
	_add_warped_guidance_label(_drain_root, "DrainOptional", "OPTIONAL // CONCENTRATED LYSATE",
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
	_build_drain_flora()
	# The current-and-guard detour pays the strongest early lysate source. The item itself is the
	# reward; this shallow cradle exists only so hover has a stable, dark silhouette.
	var source_pos := Vector3(smid, 0.5, DRAIN_LEDGE_LANE)
	var cache := _add_interactable(self, "DrainCache", "Take the concentrated drain lysate", source_pos,
		"TAKE LYSATE", "", 1.2, true, 1.6, Interactable.InteractableType.TIMED_ACTION, false)
	var cradle := _add_reward_cradle(cache, "DrainCacheCradle")
	_outline_interactable_child(cache, cradle, "DrainCache", 1.6)
	_configure_wash_control(
		cache, "drain_cache", "drain_cache", -1,
		_on_drain_cache.bind(cache))
	_drain_reward = {
		"cache": cache,
		"reward_source_key": DRAIN_REWARD_SOURCE_KEY,
		"reward_source_pos": source_pos,
		"reward_atp": DRAIN_RISK_REWARD,
		"reward_tier": "drain_risk",
		"reward_item_id": "",
		"reward_phase": REWARD_PHASE_AVAILABLE,
		"reward_claimed_by": "",
		"reward_claim_serial": 0,
		"collected": false,
	}
	cache.consequence_preview = "Moves the visible +%d ATP lysate into this character's free hand." \
		% DRAIN_RISK_REWARD
	_reset_reward_to_source(_drain_reward)
	_build_drain_bait()

# The bait is the same reusable physical Flure used elsewhere, not a purple box that asks this
# chunk to impersonate one. Its own exact Interactable receipt owns the song and Enemy lure target.
func _build_drain_bait() -> void:
	var bp := Vector3(DRAIN_LOOP_S0, 0.5, BRANCH_NECK_LANE + 0.8)   # lane ~4.3 — inside the loop, below the flood
	var lure_flat := Vector3(
		(DRAIN_LOOP_S0 + DRAIN_LOOP_S1) * 0.5, 0.5, DRAIN_RUN_LANE)
	var bait := Flure.new()
	bait.name = "DrainBait"
	bait.authority_id = "wash_relay_drain_bait"
	bait.configure(
		_get_game_state(), bp, [DRAIN_GUARD_ID], 16.0, 1.4,
		Color(1.0, 0.55, 0.12))   # flure species gold-orange — never magenta (palette law)
	bait.one_shot = false
	bait.lure_duration = DRAIN_BAIT_PULL
	bait.settle_pos = lure_flat
	bait.set_enemy_resolver(_enemy_by_id)
	bait.set_pre_trigger_validator(
		_validate_wash_flure_policy.bind("drain", -1))
	bait.flure_activated.connect(
		_on_wash_flure_activated.bind("drain", -1, bait))
	add_child(bait)
	_register_interactable(bait)
	_flures.append(bait)
	_drain_bait_flure = bait


## The two authored story beats, on their own inward ledges (walkable spurs added in
## get_grid_data; plank visuals in WashRelayDressing). Both are standalone: registered for
## outline/warp coverage but kept OUT of _relay_flures/LURE_SPECS/_portals/_pressure_portals,
## whose index alignment and counts other systems assert.
func _build_story_beats() -> void:
	# THE LONELY FLURE — a real flure with an EMPTY target list. Lighting it plays the whole
	# species grammar (the song, the glow) and nothing comes: the beat IS the mechanic.
	var flure := Flure.new()
	flure.name = "LonelyFlure"
	flure.authority_id = "wash_relay_lonely_flure"
	flure.configure(_get_game_state(), LONELY_FLURE_POS, [], 6.0, 1.0, Color(1.0, 0.55, 0.12))
	flure.one_shot = false
	flure.description = "Light the lonely flure"
	flure.flure_activated.connect(_on_lonely_flure_lit)
	add_child(flure)
	_register_interactable(flure)
	_flures.append(flure)
	_lonely_flure = flure
	# THE CURECUMIN PORTAL — a REAL blue PortalPad pair (docs/PORTALS.md): start ledge <->
	# the neck garden. The reward canonically waits in a Greenfields Collective home, so
	# the garden holds only its SEALED gate — the promise, not the loot.
	var gs = _get_game_state()
	var pad := PortalPad.new()
	pad.name = "CurecuminPortalPad"
	pad.authority_id = "wash_relay_cure_out"
	pad.call("configure_data", gs, CURECUMIN_PAD_POS, CURE_DEST_POS, 1.25, CURE_PORTAL_COLOR)
	pad.set_group_provider(_selected_party_ids)
	add_child(pad)
	_register_interactable(pad)
	var back := PortalPad.new()
	back.name = "CurecuminPortalReturn"
	back.authority_id = "wash_relay_cure_back"
	back.call("configure_data", gs, CURE_DEST_POS, CURECUMIN_PAD_POS, 1.25, CURE_PORTAL_COLOR)
	back.set_group_provider(_selected_party_ids)
	add_child(back)
	_register_interactable(back)
	_curecumin_pad = pad
	_cure_portals = [pad, back]
	_build_neck_garden()
	# The contract fixtures (arch + live destination lens both ends) come from the one
	# shared construction site; as pad children they ride the deck warp with the pads.
	PortalFixtures.dress_matching(_cure_portals, CURE_APERTURE_R)

## The portal-only pocket inside the broken-coil neck: green growth in the break, wrapped
## around the well downpipe, ending at the sealed Greenfields gate. Ground collision comes
## from NECK_GARDEN_REGION via the host's walkable-collision pass, like the pressure room.
func _build_neck_garden() -> void:
	var garden := Node3D.new()
	garden.name = "NeckGarden"
	add_child(garden)
	_warped_box(garden, 42.5, -8.65, Vector3(2.5, 0.3, 4.8), Color(0.10, 0.14, 0.11), Color.BLACK, 0.0, -0.15)
	_warped_box(garden, 42.5, -8.65, Vector3(2.3, 0.05, 4.4), Color(0.09, 0.2, 0.12),
		Color(0.16, 0.5, 0.3), 0.45, 0.03)
	var srng := RandomNumberGenerator.new() # @rendering_only
	srng.seed = 421
	for k in range(7):
		var h := 0.45 + srng.randf() * 0.6 # @rendering_only
		_warped_box(garden, 40.9 + srng.randf() * 3.4, -9.6 + srng.randf() * 1.9, # @rendering_only
			Vector3(0.09, h, 0.09), Color(0.08, 0.22, 0.14), Color(0.2, 0.85, 0.5), 1.1, h * 0.5)
	# the sealed gate: dark slab, one warm seam — gold lives on the ITEM's promise, never
	# on portal fixtures (the portal color law)
	_warped_box(garden, 44.55, -8.65, Vector3(2.2, 2.6, 0.32), Color(0.06, 0.07, 0.08), Color.BLACK, 0.0, 1.3)
	var sealed_leaf := _warp_piece("door_ironband", 44.55, -8.5, 0.0, 0.0, garden,
		"SealedGate", "floor", false, "garden_gate")
	if sealed_leaf != null:
		sealed_leaf.transform = sealed_leaf.transform.scaled_local(Vector3.ONE * 1.15)
	var gate := _add_interactable(self, "SealedGreenfieldsGate", "Read the sealed gate",
		CURE_GATE_POS, "READ GATE", "", 0.8, false, 1.4,
		Interactable.InteractableType.INSPECTION, false)
	# The gold seam is a LOCAL child of the flat-authored gate so it (and the outline
	# target wrapping it) rides the interactable warp exactly once — never a pre-warped
	# world mesh, which the warp pass would carry a second time.
	var seam := _add_box(gate, Vector3(-0.05, 1.25, 0.35), Vector3(0.18, 1.9, 0.06),
		Color(0.3, 0.24, 0.08), LevelPalette.global_color("curecumin_gold"), 2.0)
	_outline_interactable_child(gate, seam, "SealedGreenfieldsGate", 1.4)
	gate.interacted.connect(_on_greenfields_gate_read)
	# the portal's blue light (the arch itself is a PortalFixtures child of the return pad)
	var apos := ChannelsArc.arc_pos(CURE_DEST_POS.x, CURE_DEST_POS.z) \
		+ Vector3(0.0, PortalFixtures.ARCH_LIFT, 0.0)
	var glow := OmniLight3D.new()
	glow.light_color = CURE_PORTAL_COLOR
	glow.light_energy = 2.4
	glow.omni_range = 8.0
	glow.position = apos
	garden.add_child(glow)
	# a warm counter-light on the gate so the lens view reads garden-green + gold, not void
	var gate_glow := OmniLight3D.new()
	gate_glow.light_color = LevelPalette.global_color("curecumin_gold")
	gate_glow.light_energy = 1.4
	gate_glow.omni_range = 5.0
	gate_glow.position = ChannelsArc.arc_pos(44.2, -8.6) + Vector3(0.0, 1.6, 0.0)
	garden.add_child(gate_glow)

## The Plumbing Power Project is INTERIOR infrastructure (director's lighting brief): night is
## lit by the AUTHORED rig below, and "day" is only occasional seep light — the
## shared day/night curve barely moves this level. Near-zero sun in both phases,
## a constant ambient band in the channels' dark teal, glow held so emissives
## keep blooming at night (and on the web build's reduced-glow renderer).
func get_preview_lighting_profile() -> Dictionary:
	# The ambiance plate (docs/CHANNELS_CONCEPT.md): dark, wet, high-contrast, lit by
	# the red/blue/purple accent trio with neon bloom on the water/portal/rim. A
	# filmic grade lifts the shadow floor just enough to read while keeping the deep
	# contrast; bloom makes the emissives glow. Cool near-black shadow, sun ~zero.
	return {
		"ambient_energy_floor": 0.66,
		"ambient_energy_ceiling": 0.74,
		"directional_energy_floor": 0.05,
		"directional_energy_ceiling": 0.09,
		"glow_intensity_floor": 0.6,
		"glow_bloom": 0.32,
		"glow_hdr_threshold": 0.9,
		"tonemap_mode": "filmic",
		"tonemap_white": 6.0,
		"exposure": 1.15,
		"ambient_color": Color(0.13, 0.18, 0.25),
		"directional_color": Color(0.40, 0.55, 0.74),
		"background_color": Color(0.01, 0.014, 0.022),
		"background_mix": 0.6,
		"color_mix": 0.5,
		"fog_density": 0.018,
		"fog_color": Color(0.05, 0.09, 0.14),
		"fog_energy": 0.9,
		"fog_aerial": 0.5,
	}

## THE AUTHORED LIGHT RIG. Wayfinding follows the no-decorative-text ruling — the
## light IS the signage: each section gate casts its palette hue, amber work-lamps
## pace the branch gaps, water sections pool cyan, warm lamps mark the start
## shelter and the chunk-end overlook, and a few CONSTANT pale seep shafts fall
## from above (the "occasional light seeping in" that is all daytime means here).
## Every light is shadowless and tightly ranged — the compat/web renderer caps
## lights per object, and the rig must fit inside that budget.
func _build_light_rig() -> void:
	var rig := Node3D.new()
	rig.name = "LightRig"
	add_child(rig)
	var water := LevelPalette.color("channels", "water")
	var purple := LevelPalette.global_color("portal_transit")
	var red := Color(0.95, 0.22, 0.14)
	for i in range(SECTIONS.size()):
		var sec: Dictionary = SECTIONS[i]
		# WATER is the pervasive dominant glow (concept plate B) — a bright cyan pool
		# hugging the deck of EVERY section, lighting it from below across the walkway.
		var s_mid := (float(sec["x0"]) + float(sec["x1"])) * 0.5
		_rig_omni(rig, s_mid, 0.0, 0.6, water, 3.6, 8.0)
		_rig_omni(rig, s_mid, -2.6, 0.6, water, 2.2, 7.0)   # reach the inner rim too
		# the gate hue rides above as the section's wordless signage.
		_rig_omni(rig, float(sec["x0"]), 0.0, 2.6,
			LevelPalette.color("channels", "sections/" + str(sec["type"])), 1.8, 6.5)
	# PORTALS cast purple (concept plate B) — pooling on the planks around each ring.
	for portal_s in [CURECUMIN_PAD_POS.x, CURE_DEST_POS.x, PRESSURE_PORTAL_ENTRY.x, PRESSURE_PORTAL_LANDING.x]:
		_rig_omni(rig, float(portal_s), 0.0, 1.1, purple, 2.6, 6.0)
	# LANTERNS: the RED accent zone on the inner rim (the moody red wall of plate B),
	# warm amber holding the shelters/overlook.
	for red_s in [10.0, 30.0, 50.0, 70.0]:
		_rig_omni(rig, float(red_s), -3.4, 2.0, red, 2.2, 6.5)
	_rig_omni(rig, 1.6, -2.0, 2.0, LevelPalette.color("channels", "lamp"), 1.6, 8.0)
	_rig_omni(rig, 84.0, 0.0, 2.2, LevelPalette.color("channels", "lamp"), 1.6, 8.0)
	for mid_v in _gap_mids():                              # amber work-lamps at the turn-offs
		_rig_omni(rig, float(mid_v), 3.2, 1.8,
			LevelPalette.global_color("warning_amber"), 1.25, 6.5)
	# the DRUM CROWN rim — a bright cyan-white band, the brightest thing up top.
	_rig_omni(rig, 86.0, 0.0, 3.4, Color(0.7, 0.92, 1.0), 3.2, 8.0)
	for s_pos in [20.6, 39.5, 54.5, 72.5]:                 # constant pale seep shafts
		var seep := SpotLight3D.new()
		seep.light_color = Color(0.70, 0.74, 0.68)
		seep.light_energy = 2.6
		seep.spot_range = 14.0
		seep.spot_angle = 18.0
		seep.shadow_enabled = false
		seep.position = _branch_warp_xform(float(s_pos), 0.0).origin + Vector3(0.0, 9.0, 0.0)
		seep.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		rig.add_child(seep)

## Give the drum + dressing a WET sheen (concept plate B): duplicate each opaque,
## non-emissive dressing material and drop its roughness + add metallic/specular, so
## the coloured lights glint and streak across the iron. Channels-ONLY — the
## materials are duplicated, so the paintlib source shared with the Peris/Aster rooms
## stays matte. Glowing (water/rim/lamp) and transparent (falls/glass) pieces are
## skipped so they keep their emissive look.
func _make_dressing_wet() -> void:
	if _dressing == null or not (_dressing is Dictionary) or not _dressing.has("root"):
		return
	var root = _dressing["root"]
	if not is_instance_valid(root):
		return
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for si in range(mi.mesh.get_surface_count()):
				var m = mi.get_active_material(si)
				if not (m is BaseMaterial3D):
					continue
				var bm := m as BaseMaterial3D
				if bm.emission_enabled or bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					continue
				var wet := bm.duplicate() as BaseMaterial3D
				wet.roughness = 0.32
				wet.metallic = 0.34
				wet.metallic_specular = 0.9
				mi.set_surface_override_material(si, wet)
		for c in n.get_children():
			stack.append(c)

## ORGANIC VASCULATURE overgrowth (concept plate C): the veins + glowing clusters lay
## over the tall iron (drum, shaft walls) as a per-instance material_overlay — a
## transparent world-triplanar pass ON TOP of the painted iron, so the base plate/rust
## detail stays and the tendrils climb over it. One shared material; the textures come
## from the Voronoi generator (gen_vasculature.py). Skipped if the maps are missing.
func _apply_vasculature() -> void:
	if _dressing == null or not (_dressing is Dictionary) or not _dressing.has("root"):
		return
	var root = _dressing["root"]
	if not is_instance_valid(root):
		return
	var alb_path := "res://resources/textures/vasculature/vasculature_albedo.png"
	if not ResourceLoader.exists(alb_path):
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://resources/vasculature_overlay.gdshader")
	mat.set_shader_parameter("vein_albedo", load(alb_path))
	mat.set_shader_parameter("vein_emissive", load("res://resources/textures/vasculature/vasculature_emissive.png"))
	mat.set_shader_parameter("vein_normal", load("res://resources/textures/vasculature/vasculature_normal.png"))
	mat.render_priority = 1
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var nm := str(n.name).to_lower()
			# The DRUM only. On the huge dark shaft panels the overlay's emissive
			# cluster dots read as a scattered "starfield" — an invented look the
			# director cut; those walls stay bare until the arched wall-tracery
			# PROP replaces them (prop audit #8). Veins climb the drum, where the
			# plate shows them. Skip the rim + water.
			if nm.contains("drum") and not nm.contains("rim") and not nm.contains("water"):
				(n as MeshInstance3D).material_overlay = mat
		for c in n.get_children():
			stack.append(c)

## MATERIAL RESPONSE (director: "noisy, and lacks the subtle fresnel effect on
## materials and translucency"): every dressing/prop material gets a light
## RESPONSE — a subtle white rim so silhouettes catch the coloured light, and
## backlight on organics so they read translucent, lit from within. One walk,
## one duplicate per unique material (cached), same pattern as the wet pass.
func _apply_material_response() -> void:
	var cache: Dictionary = {}
	for root_name in ["OrganicProps", "ConceptProps", "Scaffolding"]:
		var root := find_child(root_name, false, false)
		if root != null:
			_material_response_walk(root, cache)
	if _dressing is Dictionary and _dressing.has("root") and is_instance_valid(_dressing["root"]):
		_material_response_walk(_dressing["root"], cache)

func _material_response_walk(node: Node, cache: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for si in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(si)
				if not (mat is StandardMaterial3D):
					continue
				if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					continue                                  # god rays / blends keep their look
				var key := mat.get_instance_id()
				if not cache.has(key):
					var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					var mname := str(mat.resource_name).to_lower()
					var organic := mname.contains("vein") or mname.contains("bark") 						or mname.contains("moss") or mname.contains("fern") or mname.contains("leaf") 						or mname.contains("scarpet") or mname.contains("vine") or mname.contains("bloom") 						or mname.contains("stalk") or mname.contains("pod") or mname.contains("capbage")
					var lit_within := dup.emission_enabled and dup.emission.get_luminance() > 0.05
					dup.rim_enabled = true
					if lit_within:
						dup.rim = 0.12
						dup.rim_tint = 0.2
						dup.backlight_enabled = true
						dup.backlight = dup.emission * 0.55   # caps read lit from WITHIN
					elif organic:
						dup.rim = 0.32
						dup.rim_tint = 0.35
						dup.backlight_enabled = true
						dup.backlight = dup.albedo_color * 0.5  # light bleeds through tissue
					else:
						dup.rim = 0.16
						dup.rim_tint = 0.65                   # hard surfaces: a whisper of fresnel
					cache[key] = dup
				mi.set_surface_override_material(si, cache[key])
	for child in node.get_children():
		_material_response_walk(child, cache)

## THE REASSEMBLY (director: "the level isn't using the new assets yet"): place the
## concept-pass assemblies. All are BODIES riding the helix warp; gameplay untouched.
func _warp_piece(pid: String, s_pos: float, lane: float, y_off: float, yaw: float,
		parent: Node3D, tag: String, mount := "floor", embed_ok := false, cluster := "") -> Node3D:
	var piece := ArchetypePieceLibrary.instantiate(pid)
	if piece == null:
		return null
	piece.transform = Transform3D(
		ChannelsArc.basis_at(s_pos) * Basis(Vector3.UP, yaw),
		ChannelsArc.arc_pos(s_pos, lane) + Vector3(0.0, y_off, 0.0))
	piece.name = "%s_%d_%d" % [tag, roundi(s_pos * 10.0), roundi(lane * 10.0)]
	piece.set_meta("mount", mount)
	piece.set_meta("embed_ok", embed_ok)
	piece.set_meta("cluster", cluster if cluster != "" else piece.name)
	parent.add_child(piece)
	return piece

func _build_concept_props() -> void:
	var root := Node3D.new()
	root.name = "ConceptProps"
	add_child(root)
	# the curecumin portal ASSEMBLY at the pad ledge (plate A): ornate ring + frame
	# behind the pad, console beside it, turned pad-rings under it, the pier's
	# broken end past the ledge lip. The pad's plain fixture arch is hidden — the
	# masonry ring IS the aperture now (the live lens keeps hovering in its bore).
	# MEASURED: PadLedge_001 top sits at y=1.075, 0.135 BELOW the arc line; the
	# pier hangs off the ledge's free s-end (the old lane -8.3 was inside the drum)
	_warp_piece("portal_ring_ornate", 1.6, -7.35, -0.135, PI * 0.5, root, "CureRing",
		"floor", false, "cure")
	_warp_piece("portal_console", 2.85, -6.5, -0.135, PI * 0.5 + 0.3, root, "CureConsole",
		"floor", false, "cure")
	_warp_piece("portal_pad_rings", 1.6, -6.2, -0.115, 0.0, root, "CurePadRings",
		"floor", false, "cure")
	_warp_piece("broken_pier", 3.55, -5.4, -0.135, -PI * 0.5, root, "CurePier",
		"floor", false, "cure")
	if _cure_portals.size() > 0 and is_instance_valid(_cure_portals[0]):
		var arch: Node = (_cure_portals[0] as Node).find_child("PortalArch", true, false)
		if arch != null:
			(arch as Node3D).visible = false
	# vascular tracery + bar lamps mount on the REAL wall fins (measured: fins
	# exist only at s 4.0 / 55.1 / 62.4, inner faces at lane ~10.85)
	for ts in [4.0, 55.1, 62.4]:
		_warp_piece("wall_tracery", ts, 10.85, 0.2, -PI * 0.5, root, "Tracery",
			"wall", true, "fin_%d" % roundi(ts))
		_warp_piece("red_bar_lamp", ts, 11.25, 1.7, -PI * 0.5, root, "BarLamp",
			"wall", true, "fin_%d" % roundi(ts))
		# a lamp LIGHTS its fin — without the spill the fixture and tracery are
		# invisible and the emissive bar hovers as a bare red slab in the dark
		_rig_omni(root, ts, 10.4, 2.1,
			LevelPalette.color("channels", "lamp_red"), 1.1, 5.5)
	# the reservoir platform stands in the drum's crown water (plate D)
	var platform := ArchetypePieceLibrary.instantiate("reservoir_platform")
	if platform != null:
		platform.transform = Transform3D(Basis(Vector3.UP, 2.2), Vector3(0.55, 16.42, -0.35))
		platform.name = "CrownPlatform"
		platform.set_meta("mount", "floor")
		platform.set_meta("embed_ok", true)          # its skirt sits IN the crown water
		platform.set_meta("cluster", "crown")
		root.add_child(platform)
		# a work light over the platform: the neon crown ring backlights everything
		# up top, so without its own fill the platform is a black silhouette
		var work_light := OmniLight3D.new()
		work_light.light_color = Color(0.75, 0.9, 1.0)
		work_light.light_energy = 1.0
		work_light.omni_range = 7.0
		work_light.shadow_enabled = false
		work_light.position = Vector3(0.55, 18.3, -0.35)
		root.add_child(work_light)

## STRUCTURAL SCAFFOLDING: the coil reads as BUILT — truss bays hang under the
## deck run, legs carry the branch piers, racked pipes ride the outer rim, and
## railings guard the pressure pocket's open edge. Tileable 2 m modules.
func _build_structural_scaffold() -> void:
	var root := Node3D.new()
	root.name = "Scaffolding"
	add_child(root)
	var s_pos := 4.0
	while s_pos < 84.0:
		if not (s_pos > 18.0 and s_pos < 23.5):            # the broken-coil gap stays bare
			_warp_piece("scaffold_truss", s_pos, 0.0, -1.42, -PI * 0.5, root, "Truss",
				"ceiling", false, "truss_%d" % roundi(s_pos))
		s_pos += 6.0
	for gap_mid in GAP_MIDS_SCAFFOLD:                      # legs under the branch piers
		for ds in [-0.8, 0.8]:
			_warp_piece("scaffold_leg", gap_mid + ds, 7.5, -3.28, 0.0, root, "PierLeg",
				"ceiling", false, "pier_%d" % roundi(gap_mid))
	for rs in [21.0, 23.0, 25.0]:                          # pressure-pocket edge railings
		_warp_piece("railing_run", rs, -10.2, 0.24, -PI * 0.5, root, "PocketRail",
			"floor", true, "pocket")   # the pressure room is a VOID carved through the
										# drum-neck shell; the shell's convex box reads solid
	# PLACEMENT STORY: pipe racks are not sprinkled — they gather where a crew
	# actually worked. ONE maintenance bay beside the flush manifold: paired racks,
	# the valve column that works them, and the bay's own work lamp. (33-47 =
	# wall-skip, nothing hangs over the falls void; lone scattered racks are the
	# "splatter" read and are gone.)
	for ps in [6.4, 10.6]:                                 # racks FLANK the flush manifold at 8.5
		_warp_piece("pipe_rack", ps, 4.3, 0.0, -PI * 0.5, root, "PipeRack",
			"floor", false, "bay")
	_warp_piece("water_control", 5.2, 3.6, 0.0, PI, root, "BayValve",
		"floor", false, "bay")
	_rig_omni(root, 5.2, 3.9, 2.4, LevelPalette.color("channels", "lamp"), 1.2, 5.0)

const GAP_MIDS_SCAFFOLD: Array = [12.5, 28.5, 54.5, 62.5, 72.5]

## Wave-1 organic props (docs/CHANNELS_CONCEPT.md prop audit): the plate's detail is
## PROPS, not texture — 3D vein trunks climbing the drum with glowing basal bulbs,
## biolume clusters at their feet, the porthole ASSEMBLY standing proud of the plate,
## and the continuous neon crown tube over the drum rim (plate 1's brightest element).
## Drum: centre ChannelsArc.CENTER, radius 3.45 (WashRelayDressing.DRUM_R), top 16.5.
func _build_organic_props() -> void:
	var root := Node3D.new()
	root.name = "OrganicProps"
	add_child(root)
	var drum_r := 3.45
	# Vein trunks hug the drum: {angle (atan2(x,z)), base y, scale}. The first two sit
	# in the drum_face / curecumin money-shot views; the rest spread the overgrowth.
	var trunks := [
		{"a": 0.67, "y": 0.55, "s": 1.0},
		{"a": 0.95, "y": 0.5, "s": 0.85},
		{"a": 2.18, "y": 8.6, "s": 1.15},
		{"a": 3.6, "y": 4.4, "s": 1.0},
		{"a": 5.1, "y": 9.8, "s": 0.9},
	]
	for t in trunks:
		var trunk := ArchetypePieceLibrary.instantiate("vein_trunk")
		if trunk == null:
			return
		var a: float = t["a"]
		var radial := Vector3(sin(a), 0.0, cos(a))
		trunk.transform = Transform3D(
			Basis(Vector3.UP, a).scaled(Vector3.ONE * float(t["s"])),
			radial * (drum_r + 0.05) + Vector3(0.0, float(t["y"]), 0.0))
		trunk.name = "VeinTrunk_%d" % roundi(a * 100.0)
		trunk.set_meta("mount", "wall")
		trunk.set_meta("embed_ok", true)             # the growth hugs INTO the drum skin
		trunk.set_meta("cluster", "trunk_%d" % roundi(a * 100.0))
		root.add_child(trunk)
		var cluster := ArchetypePieceLibrary.instantiate("biolume_cluster")
		if cluster != null:
			cluster.transform = Transform3D(Basis(Vector3.UP, a + 0.9),
				radial * (drum_r + 0.55) + Vector3(0.35 * sin(a + 1.6), float(t["y"]) + 0.02, 0.35 * cos(a + 1.6)))
			cluster.name = "Biolume_%d" % roundi(a * 100.0)
			cluster.set_meta("mount", "wall")
			cluster.set_meta("embed_ok", true)       # the colony nests in the trunk's roots
			cluster.set_meta("cluster", "trunk_%d" % roundi(a * 100.0))
			root.add_child(cluster)
		# each trunk's bulb nest casts real light so the overgrowth pools violet
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.55, 0.35, 0.9)
		glow.light_energy = 1.1
		glow.omni_range = 2.6
		glow.shadow_enabled = false
		glow.position = radial * (drum_r + 0.5) + Vector3(0.0, float(t["y"]) + 0.35, 0.0)
		root.add_child(glow)
	# The porthole assembly at the drum-face money shot (the painted porthole spot).
	var port := ArchetypePieceLibrary.instantiate("porthole")
	if port != null:
		var pa := 0.07
		port.transform = Transform3D(Basis(Vector3.UP, pa).scaled(Vector3.ONE * 1.35),
			Vector3(sin(pa), 0.0, cos(pa)) * (drum_r + 0.02) + Vector3(0.0, 0.85, 0.0))
		port.name = "PortholeFace"
		port.set_meta("mount", "wall")
		port.set_meta("embed_ok", true)              # backing flange embeds in the drum
		port.set_meta("cluster", "drum")
		root.add_child(port)
	# The neon crown: one CONTINUOUS bright tube riding posts over the drum rim.
	var crown := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.72
	torus.outer_radius = 3.86
	torus.rings = 48
	torus.ring_segments = 10
	crown.mesh = torus
	var tube := StandardMaterial3D.new()
	tube.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tube.albedo_color = Color(0.75, 0.95, 1.0)
	tube.emission_enabled = true
	tube.emission = Color(0.75, 0.95, 1.0)
	tube.emission_energy_multiplier = 3.4
	crown.material_override = tube
	crown.position = Vector3(0.0, 16.9, 0.0)
	crown.name = "CrownTube"
	crown.set_meta("mount", "wall")
	crown.set_meta("embed_ok", true)
	crown.set_meta("cluster", "crown")
	root.add_child(crown)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.13, 0.13, 0.16)
	for i in range(10):
		var pa2 := TAU * i / 10.0
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.035
		cyl.bottom_radius = 0.035
		cyl.height = 0.55
		post.mesh = cyl
		post.name = "CrownPost_%d" % i
		post.material_override = post_mat
		post.position = Vector3(sin(pa2), 0.0, cos(pa2)) * 3.62 + Vector3(0.0, 16.65, 0.0)
		post.set_meta("mount", "wall")
		post.set_meta("embed_ok", true)
		post.set_meta("cluster", "crown")
		root.add_child(post)

## A reflection probe over the play space so the WET deck + drum actually REFLECT the
## drum, rim, and coloured lights (not just specular glints). Box-projected + interior
## so it captures the shaft; UPDATE_ONCE — the geometry and the authored lights are
## static, so one bake is exact and free per frame. Supported on Forward+ and compat.
func _build_reflection_probe() -> void:
	var probe := ReflectionProbe.new()
	probe.name = "ChannelsReflection"
	probe.size = Vector3(46.0, 24.0, 46.0)
	probe.origin_offset = Vector3.ZERO
	probe.box_projection = true
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.9
	probe.max_distance = 60.0
	probe.position = Vector3(0.0, 6.0, 0.0)
	add_child(probe)

func _rig_omni(rig: Node3D, s: float, lane: float, height: float,
		color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	light.position = _branch_warp_xform(s, lane).origin + Vector3(0.0, height, 0.0)
	rig.add_child(light)

func _on_lonely_flure_lit(_pulled: int) -> void:
	_show_note("The flure sings. Nothing answers.", 2.6)

func _on_greenfields_gate_read() -> void:
	_show_note("SEALED // ROUTE: GREENFIELDS COLLECTIVE // SPECIMEN: CURECUMIN", 3.2)

## The relay already owns one shared cadence and its warped water meshes. These invisible reusable
## Channel coordinators are composed under those visible footprints solely to own each caught
## enemy's RESERVED -> CARRYING -> IMPACT transaction. They never arm a second flood cadence.
func _build_enemy_current_channels() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for section_index in range(SECTIONS.size()):
		var channel := Channel.new()
		channel.name = "SectionEnemyCurrent%d" % section_index
		channel.configure(
			0.0, 1.0, 1.0, 9999.0, 1.0, 9999.0,
			"wash_relay_enemy_section_%d" % section_index)
		channel.set_sweep(gs, [], _wash_enemy_current_destination.bind(section_index), {
			"enemy_damage": WASH_ENEMY_CURRENT_DAMAGE,
			"enemy_stun": 0.0,
			"refractory": 1000.0,
			"travel_speed": WASH_ENEMY_CURRENT_SPEED,
			"min_travel_duration": WASH_ENEMY_CURRENT_MIN_DURATION,
			"enemy_resolver": _enemy_by_id,
			"on_enemy_swept": _on_enemy_current_impact.bind(section_index),
		})
		channel.visible = false
		add_child(channel)
		_section_enemy_currents[section_index] = channel
	var drain_channel := Channel.new()
	drain_channel.name = "DrainEnemyCurrent"
	drain_channel.configure(
		0.0, 1.0, 1.0, 9999.0, 1.0, 9999.0,
		"wash_relay_enemy_drain")
	drain_channel.set_sweep(gs, [], _wash_enemy_current_destination.bind(-1), {
		"enemy_damage": WASH_ENEMY_CURRENT_DAMAGE,
		"enemy_stun": 0.0,
		"refractory": 1000.0,
		"travel_speed": WASH_ENEMY_CURRENT_SPEED,
		"min_travel_duration": WASH_ENEMY_CURRENT_MIN_DURATION,
		"enemy_resolver": _enemy_by_id,
		"on_enemy_swept": _on_enemy_current_impact.bind(-1),
	})
	drain_channel.visible = false
	add_child(drain_channel)
	_drain_enemy_current = drain_channel


func _wash_enemy_current_destination(
		_id: String, origin: Vector3, _section_index: int) -> Vector3:
	return Vector3(origin.x, origin.y, WASH_ENEMY_CURRENT_INNER_LANE)

# Peris's ecology verb belongs to a specific dormant plant, not to the cast drawer. Tending it is a short
# authored work beat that grows one persistent light beside the optional flood run, where that light matters.
func _build_drain_flora() -> void:
	var flora := _add_interactable(self, "DrainFlora", "Tend dormant drain flora", DRAIN_FLORA_POS,
		"TEND FLORA", "peris", 1.2, true, 1.5, Interactable.InteractableType.TIMED_ACTION, false)
	flora.consequence_preview = "Grows a persistent light that marks the flooding drain lane."
	var _planter: Node3D = ArchetypePieceLibrary.instantiate("forage_cache")
	if _planter != null:
		_planter.transform = Transform3D(Basis(Vector3.UP, 0.3).scaled(Vector3.ONE * 0.8),
			Vector3(0.0, -0.5, 0.0))
		flora.add_child(_planter)
	else:
		_planter = _add_box(flora, Vector3(0.0, -0.18, 0.0), Vector3(0.75, 0.35, 0.75),
			Color(0.17, 0.18, 0.12))
	var bud := _add_box(flora, Vector3(0.0, 0.2, 0.0), Vector3(0.42, 0.5, 0.42),
		Color(0.16, 0.38, 0.24), Color(0.35, 0.9, 0.52), 0.45)
	_outline_interactable_child(flora, bud, "DrainFlora", 1.5)
	_configure_wash_control(
		flora, "drain_flora", "drain_flora", -1,
		_on_drain_flora_tended.bind(flora))
	_drain_flora_interactable = flora
	if not _drain_water.is_empty():
		var target: Node3D = _drain_water[int(_drain_water.size() / 2)]
		_add_causal_feedback_link(flora, target, Color(1.0, 0.67, 0.27), {
			"label": "LIGHTS THIS FLOOD LANE",
			"source_offset": Vector3(0.0, 0.8, 0.0),
			"target_offset": Vector3(0.0, 0.35, 0.0),
			"arc_height": 1.3,
			"owner_character": "peris",
			"name": "DrainFloraLightLink",
		})


## Configure one exact world source for one Wash action. Repeatable controls keep a repeatable
## Interactable but still mint a new monotonic registry receipt on every accepted use. Finite
## lysate/flora sources remain one-shots whose spent presentation is derived from owner truth.
func _configure_wash_control(
		source: Node, action_id: String, kind: String, index: int,
		callback: Callable) -> void:
	if not is_instance_valid(source) or action_id == "" or not callback.is_valid():
		return
	_wash_control_sources[action_id] = {
		"source": source,
		"kind": kind,
		"index": index,
		"one_shot": bool(source.get("one_shot")),
	}
	source.set_meta("wash_control_action_id", action_id)
	source.set_pre_trigger_validator(
		_validate_wash_control_trigger.bind(action_id, source))
	if not source.interacted.is_connected(callback):
		source.interacted.connect(callback)


func _validate_wash_control_trigger(
		source: Node, actor: String, action_id: String,
		expected_source: Node) -> bool:
	var control: Dictionary = _wash_control_sources.get(action_id, {})
	return is_instance_valid(source) and source == expected_source \
		and control.get("source") == source \
		and _wash_control_actor_ready_at_source(source, actor) \
		and _wash_control_action_ready(action_id, actor)


func _wash_control_actor_ready_at_source(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs == null or data_id == "" or not gs.has_interactable(data_id) \
			or not is_instance_valid(source) or not source is Node3D \
			or actor == "" or not gs.characters.has(actor) \
			or not gs.get_party().has(actor) \
			or fragment == null or not fragment.party_ids.has(actor) \
			or not gs.is_narratively_available(actor) or gs.is_downed(actor) \
			or gs.is_knocked_down(actor) or gs.is_moving(actor) \
			or gs.is_resting(actor) or gs.is_dodging(actor) \
			or gs.is_endocytosing(actor) \
			or gs.is_external_traversal_active(actor) or gs.is_dragging(actor) \
			or gs.is_field_restoring(actor) or gs.is_pushing(actor):
		return false
	var required_actor := str(source.get("required_character"))
	if required_actor != "" and actor != required_actor:
		return false
	var source_position_v: Variant = gs.get_interactable(data_id).get(
		"position", Vector3.INF)
	if not source_position_v is Vector3:
		return false
	var source_position := source_position_v as Vector3
	if not source_position.is_finite():
		return false
	if gs.grid != null and gs.grid.level_count > 1 \
			and int(gs.get_character_level(actor)) \
				!= int(gs.grid.level_for_y(source_position.y)):
		return false
	var actor_position: Vector3 = gs.get_position(actor)
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)
	) <= float(source.get("interaction_radius")) \
			+ WASH_CONTROL_POSITION_TOLERANCE \
		and absf(actor_position.y - source_position.y) \
			<= WASH_CONTROL_HEIGHT_TOLERANCE


func _wash_control_action_ready(action_id: String, actor := "") -> bool:
	if not _accepts_gameplay_events() or _get_scheduler() == null:
		return false
	var control: Dictionary = _wash_control_sources.get(action_id, {})
	if control.is_empty():
		return false
	var kind := str(control.get("kind", ""))
	var index := int(control.get("index", -1))
	match kind:
		"override":
			return index >= 0 and index < SECTIONS.size() \
				and str(SECTIONS[index].get("disable", "")) == "override"
		"flow_terminal":
			return index >= 0 and index < SECTIONS.size() \
				and str(SECTIONS[index].get("disable", "")) == "timing"
		"branch_cache":
			if index < 0 or index >= _branches.size():
				return false
			var branch := _branches[index] as Dictionary
			return bool(branch.get("unlocked", true)) \
				and not bool(branch.get("collected", false)) \
				and str(branch.get(
					"reward_phase", REWARD_PHASE_AVAILABLE
				)) == REWARD_PHASE_AVAILABLE \
				and _reward_item_at_source(branch) \
				and (actor == "" \
					or _get_game_state().has_free_hands(actor, 1))
		"branch_switch":
			if index < 0 or index >= _branches.size():
				return false
			var branch := _branches[index] as Dictionary
			var gate_kind := str(branch.get("gate_kind", "open"))
			if gate_kind == "open" or bool(branch.get("collected", false)) \
					or str(branch.get("mechanism_phase", "idle")) != "idle":
				return false
			if gate_kind == "decoy":
				return _wash_enemy_ready(
					str((branch.get("mechanism_context", {}) as Dictionary).get(
						"guard_id", "")))
			return gate_kind in ["lever", "valve"]
		"pressure_valve":
			return _pressure_vent_until < 0.0
		"drain_cache":
			return not _drain_reward.is_empty() \
				and str(_drain_reward.get(
					"reward_phase", REWARD_PHASE_AVAILABLE
				)) == REWARD_PHASE_AVAILABLE \
				and _reward_item_at_source(_drain_reward) \
				and (actor == "" \
					or _get_game_state().has_free_hands(actor, 1))
		"drain_bait":
			return _drain_bait_until < 0.0 \
				and _wash_enemy_ready(DRAIN_GUARD_ID)
		"drain_flora":
			return not _drain_flora_tended
		"lure":
			if index < 0 or index >= LURE_SPECS.size():
				return false
			var until := float(_lure_until[index]) \
				if index < _lure_until.size() else -1.0
			return until < 0.0 \
				and _wash_enemy_ready(str(LURE_SPECS[index].get("target", "")))
	return false


func _wash_enemy_ready(enemy_id: String) -> bool:
	var gs = _get_game_state()
	if enemy_id == "" or gs == null or not gs.characters.has(enemy_id) \
			or gs.is_downed(enemy_id) or _pending_drown_removals.has(enemy_id) \
			or _enemy_drown_mirrors.has(enemy_id):
		return false
	for enemy in _enemies:
		if is_instance_valid(enemy) and str(enemy.get("char_id")) == enemy_id:
			return not enemy.has_method("is_alive") or bool(enemy.call("is_alive"))
	return false


func _wash_control_source_trigger_count(source: Node) -> int:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return -1
	return int(gs.get_interactable(data_id).get("trigger_count", -1))


func _wash_control_source_receipt(
		source: Node, action_id: String) -> Dictionary:
	var control: Dictionary = _wash_control_sources.get(action_id, {})
	if not is_instance_valid(source) or control.get("source") != source:
		return {}
	var actor := str(source.get("active_character"))
	if not _validate_wash_control_trigger(
			source, actor, action_id, source):
		return {}
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return {}
	var receipt: Dictionary = gs.get_interactable(data_id)
	var trigger_count := int(receipt.get("trigger_count", -1))
	var committed_count := int(
		_wash_control_committed_counts.get(action_id, 0))
	var expected_one_shot := bool(control.get("one_shot", false))
	if trigger_count != committed_count + 1 \
			or str(receipt.get("last_trigger_character", "")) != actor \
			or bool(receipt.get("one_shot", false)) != expected_one_shot \
			or not bool(receipt.get("triggered", false)):
		return {}
	if expected_one_shot and (
			not bool(source.get("_used"))
			or bool(source.get("interaction_enabled"))
			or bool(receipt.get("enabled", true))
	):
		return {}
	if not expected_one_shot and (
			bool(source.get("_used"))
			or not bool(source.get("interaction_enabled"))
			or not bool(receipt.get("enabled", true))
	):
		return {}
	return {
		"action_id": action_id,
		"actor": actor,
		"trigger_count": trigger_count,
	}


## Consuming the receipt publishes the new owner-side count before any mechanism, item, enemy,
## information, or light consequence. A snapshot in that interval therefore restores a spent
## receipt with no semantic outcome; reconciliation rearms only when physical owner truth allows.
func _consume_wash_control_receipt(
		source: Node, action_id: String) -> Dictionary:
	var receipt := _wash_control_source_receipt(source, action_id)
	if receipt.is_empty():
		return {}
	_wash_control_committed_counts[action_id] = int(
		receipt.get("trigger_count", 0))
	_publish_wash_authority(false)
	return receipt


func _wash_control_action_ids() -> Array[String]:
	var ids: Array[String] = []
	for action_id_v in _wash_control_sources.keys():
		ids.append(str(action_id_v))
	ids.sort()
	return ids


func _ensure_wash_control_registry_shapes() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for action_id in _wash_control_action_ids():
		var control: Dictionary = _wash_control_sources[action_id]
		var source: Node = control.get("source")
		if not is_instance_valid(source):
			continue
		var desired_one_shot := bool(control.get("one_shot", false))
		source.set("one_shot", desired_one_shot)
		var data_id := str(source.get("data_id"))
		if data_id == "" or not gs.has_interactable(data_id):
			continue
		var registered: Dictionary = gs.get_interactable(data_id)
		if bool(registered.get("one_shot", false)) == desired_one_shot:
			continue
		# Legacy bait/flures were accidental one-shots. Re-register the same source as repeatable
		# while preserving its stable position, monotonic count, and last actor identity.
		registered["id"] = data_id
		registered["one_shot"] = desired_one_shot
		registered["enabled"] = true
		gs.register_interactable(registered)


func _reset_wash_control_committed_counts_to_registry() -> void:
	_wash_control_committed_counts.clear()
	for action_id in _wash_control_action_ids():
		var source: Node = (_wash_control_sources[action_id] as Dictionary).get(
			"source")
		_wash_control_committed_counts[action_id] = maxi(
			0, _wash_control_source_trigger_count(source))


func _valid_saved_wash_control_counts(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	for action_id in _wash_control_action_ids():
		if not saved.has(action_id):
			return false
		var count := int(saved.get(action_id, -1))
		var source: Node = (_wash_control_sources[action_id] as Dictionary).get(
			"source")
		var source_count := _wash_control_source_trigger_count(source)
		if count < 0 or source_count < 0 or count > source_count:
			return false
	return true


func _restore_wash_control_committed_counts(raw: Variant) -> void:
	_wash_control_committed_counts.clear()
	var saved := raw as Dictionary if raw is Dictionary else {}
	for action_id in _wash_control_action_ids():
		_wash_control_committed_counts[action_id] = maxi(
			0, int(saved.get(action_id, 0)))


func _wash_control_registry_source_is_spent(source: Node) -> bool:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	var receipt: Dictionary = gs.get_interactable(data_id) \
		if gs != null and data_id != "" and gs.has_interactable(data_id) \
		else {}
	return bool(receipt.get("triggered", false)) \
		or not bool(receipt.get("enabled", true)) \
		or bool(source.get("_used")) \
		or not bool(source.get("interaction_enabled"))


## GameState emits its accepted edge before Interactable emits `interacted`. If a snapshot lands
## there, the registry count is newer than this composite record. Burn that orphan count without
## inventing the missing consequence, then make only structurally ready one-shots usable again.
func _reconcile_accepted_wash_control_receipts() -> bool:
	var changed := false
	for action_id in _wash_control_action_ids():
		var control: Dictionary = _wash_control_sources[action_id]
		var source: Node = control.get("source")
		if not is_instance_valid(source):
			continue
		var source_count := maxi(
			0, _wash_control_source_trigger_count(source))
		var committed_count := maxi(
			0, int(_wash_control_committed_counts.get(action_id, 0)))
		if source_count > committed_count:
			_wash_control_committed_counts[action_id] = source_count
			changed = true
		if bool(control.get("one_shot", false)) \
				and _wash_control_action_ready(action_id) \
				and _wash_control_registry_source_is_spent(source):
			if source.has_method("reset"):
				source.reset()
			_wash_control_committed_counts[action_id] = maxi(
				int(_wash_control_committed_counts.get(action_id, 0)),
				maxi(0, _wash_control_source_trigger_count(source)))
			changed = true
	return changed


func _project_wash_control_sources() -> void:
	var gs = _get_game_state()
	for action_id in _wash_control_action_ids():
		var control: Dictionary = _wash_control_sources[action_id]
		var source: Node = control.get("source")
		if not is_instance_valid(source):
			continue
		var ready := _wash_control_action_ready(action_id)
		var one_shot := bool(control.get("one_shot", false))
		var data_id := str(source.get("data_id"))
		if one_shot and ready \
				and _wash_control_registry_source_is_spent(source) \
				and _wash_control_source_trigger_count(source) \
					<= int(_wash_control_committed_counts.get(action_id, 0)):
			if source.has_method("reset"):
				source.reset()
		if gs != null and data_id != "" and gs.has_interactable(data_id):
			gs.set_interactable_enabled(data_id, ready)
		if source.has_method("restore_one_shot_presenter"):
			source.restore_one_shot_presenter(one_shot and not ready, ready)
		else:
			source.set_interaction_enabled(ready)


func _on_branch_cache(g: int, source: Node = null) -> bool:
	if not _accepts_gameplay_events() or g < 0 or g >= _branches.size():
		return false
	var branch: Dictionary = _branches[g]
	var action_id := "branch_cache:%d" % int(branch.get("gap", -1))
	if _consume_wash_control_receipt(source, action_id).is_empty():
		return false
	if not _claim_reward_source(branch):
		_restore_reward_interactable(branch, true)
		_publish_wash_authority()
		return false

	# A successful exact-item transfer owns the terminal branch result. In particular, the decoy's
	# finite window may now close because the player physically carries what was on the ledge.
	branch["collected"] = true
	branch["mechanism_phase"] = "clear"
	branch["phase_started_at"] = -1.0
	branch["phase_deadline"] = -1.0
	branch["next_check_at"] = -1.0
	branch["unlocked"] = true
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_branch_event_tag(branch))
	_apply_branch_mechanism_truth(branch)
	_publish_wash_authority()
	_say("// LYSATE // %s takes %s" % [
		str(branch.get("reward_claimed_by", "")).capitalize(),
		_reward_display_name(int(branch.get("reward_atp", 1))),
	])
	return true


## Commit one source-tagged GameState item, publishing the reservation before pickup so a snapshot
## from item_picked_up can reconcile the exact actor and identity. A failed range/hand check retracts
## to AVAILABLE; an injected different holder remains CLAIMING and therefore cannot mint or retarget.
func _claim_reward_source(reward: Dictionary) -> bool:
	if str(reward.get("reward_phase", "")) != REWARD_PHASE_AVAILABLE \
			or not _reward_item_at_source(reward):
		return false
	var cache = reward.get("cache")
	var actor := str(cache.get("active_character")) if is_instance_valid(cache) else ""
	var gs = _get_game_state()
	if actor == "" or gs == null or not gs.characters.has(actor):
		return false
	if not gs.has_free_hands(actor, 1):
		_show_message("%s needs a free hand for the lysate." % actor.capitalize(), 2.0)
		return false

	reward["reward_phase"] = REWARD_PHASE_CLAIMING
	reward["reward_claimed_by"] = actor
	reward["reward_claim_serial"] = int(reward.get("reward_claim_serial", 0)) + 1
	reward["collected"] = false
	_restore_reward_interactable(reward, false)
	_publish_wash_authority()

	if not _pick_up_item(actor, str(reward.get("reward_item_id", ""))):
		reward["reward_phase"] = REWARD_PHASE_AVAILABLE
		reward["reward_claimed_by"] = ""
		reward["collected"] = false
		_restore_reward_interactable(reward, true)
		_publish_wash_authority()
		_show_message("The lysate stays seated; stand at the source with one hand free.", 2.0)
		return false

	reward["reward_phase"] = REWARD_PHASE_CLAIMED
	reward["collected"] = true
	_restore_reward_interactable(reward, false)
	return true


func _reward_display_name(value: int) -> String:
	match value:
		DRAIN_RISK_REWARD:
			return "concentrated lysate"
		BRANCH_GUARDED_REWARD:
			return "rich lysate"
		BRANCH_GATED_REWARD:
			return "lysate ration"
	return "sparse lysate"


func _reward_visual_color(value: int) -> Color:
	match value:
		DRAIN_RISK_REWARD:
			return Color(0.86, 1.0, 0.42)
		BRANCH_GUARDED_REWARD:
			return Color(0.94, 0.86, 0.3)
		BRANCH_GATED_REWARD:
			return Color(0.86, 0.72, 0.32)
	return Color(0.72, 0.58, 0.3)


func _spawn_reward_item(reward: Dictionary, legacy_recovery := false) -> String:
	if str(reward.get("reward_source_key", "")) == "":
		return ""
	var value := int(reward.get("reward_atp", BRANCH_GUIDANCE_REWARD))
	return _spawn_item("lysate", reward.get("reward_source_pos", Vector3.ZERO), {
		"display_name": "%s (+%d ATP)" % [_reward_display_name(value).capitalize(), value],
		"hand_slots": 1,
		"atp_restore": float(value),
		"source_wash_relay": str(reward.get("reward_source_key", "")),
		"wash_reward_tier": str(reward.get("reward_tier", "guidance")),
		"wash_reward_atp": value,
		"visual_kind": "lysate",
		"visual_color": _reward_visual_color(value),
		"ground_visual_y": 0.58,
		"legacy_source_recovery": legacy_recovery,
	})


func _reward_item_ids(source_key: String) -> Array[String]:
	var ids: Array[String] = []
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return ids
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		var item: Dictionary = _get_item_state(item_id)
		var properties: Dictionary = item.get("properties", {})
		if str(item.get("type", "")) == "lysate" \
				and str(properties.get("source_wash_relay", "")) == source_key:
			ids.append(item_id)
	ids.sort()
	return ids


func _is_reward_item(reward: Dictionary, item_id: String) -> bool:
	if item_id == "":
		return false
	return _reward_item_ids(str(reward.get("reward_source_key", ""))).has(item_id)


func _reward_item_at_source(reward: Dictionary) -> bool:
	var item := _get_item_state(str(reward.get("reward_item_id", "")))
	if item.is_empty() or str(item.get("location", "")) != "ground":
		return false
	var pos_v: Variant = item.get("position", Vector3.INF)
	return pos_v is Vector3 and (pos_v as Vector3).distance_to(
		reward.get("reward_source_pos", Vector3.ZERO)) < 0.001


func _reward_item_holder(reward: Dictionary) -> String:
	var item := _get_item_state(str(reward.get("reward_item_id", "")))
	if item.is_empty() or str(item.get("location", "")) != "hand":
		return ""
	return str(item.get("holder", ""))


func _remove_reward_items(source_key: String, except_id := "") -> void:
	for item_id in _reward_item_ids(source_key):
		if item_id != except_id:
			_remove_item(item_id)


func _reset_reward_to_source(reward: Dictionary, legacy_recovery := false) -> void:
	var source_key := str(reward.get("reward_source_key", ""))
	if source_key == "":
		return
	_remove_reward_items(source_key)
	reward["reward_phase"] = REWARD_PHASE_AVAILABLE
	reward["reward_claimed_by"] = ""
	reward["reward_claim_serial"] = 0
	reward["collected"] = false
	reward["reward_item_id"] = _spawn_reward_item(reward, legacy_recovery)
	_restore_reward_interactable(reward, true)


func _restore_reward_interactable(reward: Dictionary, allow_available: bool) -> void:
	var cache = reward.get("cache")
	if not is_instance_valid(cache):
		return
	var claimed := str(reward.get("reward_phase", "")) == REWARD_PHASE_CLAIMED
	var available := allow_available \
		and str(reward.get("reward_phase", "")) == REWARD_PHASE_AVAILABLE \
		and _reward_item_at_source(reward)
	var gs = _get_game_state()
	var data_id := str(cache.get("data_id"))
	if available and gs != null and gs.has_interactable(data_id):
		var saved_cache: Dictionary = gs.get_interactable(data_id)
		if bool(saved_cache.get("triggered", false)):
			gs.reset_interactable(data_id)
	if cache.has_method("restore_one_shot_presenter"):
		cache.restore_one_shot_presenter(claimed, available)
	else:
		cache.set_interaction_enabled(available)


## Reconcile the portable reservation against GameState's exact item truth. Version 1-4 saves
## only knew proxy counters/booleans, so they conservatively return one item to its authored
## ground source. They never infer a carrier or mint a reward directly into a hand.
func _restore_reward_transaction(
		reward: Dictionary, saved: Dictionary, saved_version: int) -> void:
	if reward.is_empty() or str(reward.get("reward_source_key", "")) == "":
		return
	if saved_version < 5:
		_reset_reward_to_source(reward, true)
		return

	var saved_phase := str(saved.get("reward_phase", REWARD_PHASE_AVAILABLE))
	if saved_phase not in [
			REWARD_PHASE_AVAILABLE, REWARD_PHASE_CLAIMING, REWARD_PHASE_CLAIMED]:
		_reset_reward_to_source(reward)
		return
	reward["reward_phase"] = saved_phase
	reward["reward_claimed_by"] = str(saved.get("reward_claimed_by", ""))
	reward["reward_claim_serial"] = maxi(0, int(saved.get("reward_claim_serial", 0)))
	reward["reward_item_id"] = str(saved.get("reward_item_id", ""))

	var source_key := str(reward.get("reward_source_key", ""))
	var ids := _reward_item_ids(source_key)
	if not ids.has(str(reward.get("reward_item_id", ""))):
		reward["reward_item_id"] = ids[0] if not ids.is_empty() else ""
	_remove_reward_items(source_key, str(reward.get("reward_item_id", "")))

	var at_source := _reward_item_at_source(reward)
	match str(reward.get("reward_phase", "")):
		REWARD_PHASE_AVAILABLE:
			if str(reward.get("reward_item_id", "")) == "":
				reward["reward_item_id"] = _spawn_reward_item(reward)
			# A moved AVAILABLE item has no published reservation. Leave the interaction closed
			# rather than treating an arbitrary holder as the winner or spawning a duplicate.
		REWARD_PHASE_CLAIMING:
			if at_source:
				reward["reward_phase"] = REWARD_PHASE_AVAILABLE
				reward["reward_claimed_by"] = ""
			elif str(reward.get("reward_claimed_by", "")) != "" \
					and _reward_item_holder(reward) == str(reward.get("reward_claimed_by", "")):
				reward["reward_phase"] = REWARD_PHASE_CLAIMED
			# A wrong holder/location remains CLAIMING and cannot be silently retargeted.
		REWARD_PHASE_CLAIMED:
			if at_source:
				reward["reward_phase"] = REWARD_PHASE_AVAILABLE
				reward["reward_claimed_by"] = ""

	reward["collected"] = str(reward.get("reward_phase", "")) == REWARD_PHASE_CLAIMED


func _preview_reward_state(reward: Dictionary) -> Dictionary:
	return {
		"source_key": str(reward.get("reward_source_key", "")),
		"source_pos": reward.get("reward_source_pos", Vector3.ZERO),
		"item_id": str(reward.get("reward_item_id", "")),
		"phase": str(reward.get("reward_phase", REWARD_PHASE_AVAILABLE)),
		"claimed_by": str(reward.get("reward_claimed_by", "")),
		"claim_serial": int(reward.get("reward_claim_serial", 0)),
		"reward_atp": int(reward.get("reward_atp", 0)),
		"reward_tier": str(reward.get("reward_tier", "")),
		"item_at_source": _reward_item_at_source(reward),
		"item_holder": _reward_item_holder(reward),
		"cache_available": is_instance_valid(reward.get("cache")) \
			and bool(reward["cache"].is_interaction_enabled()),
	}


func _claimed_reward_atp() -> int:
	var total := 0
	for reward in _branches:
		if str(reward.get("reward_phase", "")) == REWARD_PHASE_CLAIMED:
			total += int(reward.get("reward_atp", 0))
	if str(_drain_reward.get("reward_phase", "")) == REWARD_PHASE_CLAIMED:
		total += int(_drain_reward.get("reward_atp", 0))
	return total

# Map an archetype to a world mechanism. A decoy without an actual guard would be another fake label, so
# threat-flavoured nodes that exceeded the guard budget fall back to the physical counterweight grammar.
func _branch_gate_kind(archetype: String, has_guard: bool) -> String:
	var a := archetype.to_lower()
	# Preserve the generated causal identity before applying generic threat dressing. A plant branch
	# remains a visible stock/flow problem and a carry/structure branch remains a counterweight even if
	# its generated content also includes a roamer. Enemy-redirection beats still use the body's movement
	# as their endpoint; only otherwise-untyped guarded beats fall back to that decoy grammar.
	if "plant" in a or "flora" in a or "pollen" in a:
		return "valve"
	if "forage" in a or "lysate" in a or "narrative" in a or "beat" in a or "rest" in a:
		return "open"
	if "carry" in a or "heavy" in a or "structure" in a:
		return "lever"
	if has_guard:
		return "decoy"
	return "lever"   # carry / structure / unknown -> a counterweight lever

# Per-gate-kind presentation + flavour (label, post colour/glow, the line played on activation).
func _branch_gate_theme(kind: String) -> Dictionary:
	# Mechanism colors come from the level palette (docs/LEVEL_PALETTES.md), never
	# hand-mixed rgb — generated branch content wears the same skin as the level.
	match kind:
		"valve":
			return {"label": "POLLEN VALVE", "color": LevelPalette.color("channels", "moss"),
				"glow": LevelPalette.color("channels", "flora"),
				"msg": "// VALVE // pollen is venting from the cache"}
		"lever":
			return {"label": "COUNTERWEIGHT", "color": LevelPalette.color("channels", "iron"),
				"glow": LevelPalette.color("channels", "rim_light"),
				"msg": "// LIFT // counterweight is taking the gate"}
		"decoy":
			return {"label": "DECOY BEACON", "color": LevelPalette.color("channels", "lamp"),
				"glow": LevelPalette.global_color("warning_amber"),
				"msg": "// DECOY // beacon lit — watch the guard move"}
	return {"label": "SWITCH", "color": LevelPalette.color("channels", "pipe"),
		"glow": LevelPalette.color("channels", "rim_light"), "msg": "// CLEAR //"}

# Build only the world object that belongs to this mechanism. Counterweights get a wide gate with a fixed
# collision body; pollen valves get a readable cloud stock; decoys get no invented barrier at all.
func _build_branch_mechanism(mid: float, kind: String) -> Dictionary:
	var built := {
		"gate_visual": null, "gate_body": null, "gate_collision": null,
		"gate_base_transform": Transform3D.IDENTITY, "vent_plumes": [],
	}
	match kind:
		"lever":
			built.merge(_build_branch_counterweight_gate(mid), true)
		"valve":
			built["vent_plumes"] = _build_branch_pollen_plumes(mid)
	return built


func _build_branch_counterweight_gate(mid: float) -> Dictionary:
	var root := Node3D.new()
	root.name = "CounterweightGate_%d" % roundi(mid * 10.0)
	root.transform = _branch_warp_xform(mid, BRANCH_GATE_LANE)
	_branch_root.add_child(root)
	var size := Vector3(0.34, 1.5, BRANCH_S_SPAN * 0.92)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position.y = size.y * 0.5
	var theme := _branch_gate_theme("lever")
	mesh.material_override = _make_material(theme["color"] * 0.45, theme["glow"], 0.3)
	root.add_child(mesh)
	# the visible gate is a shortcut-hatch leaf riding the animated substrate
	for gz in [-0.75, 0.75]:
		var cw_leaf: Node3D = ArchetypePieceLibrary.instantiate("shortcut_gate")
		if cw_leaf != null:
			cw_leaf.transform = Transform3D(
				(Basis(Vector3.UP, PI * 0.5)).scaled(Vector3.ONE * 0.95),
				Vector3(0.12, -size.y * 0.5, gz))
			_tint_piece(cw_leaf, theme["glow"], 0.5)
			mesh.add_child(cw_leaf)

	# Collision deliberately stays at the threshold while the visible gate rises. Movement authority releases
	# atomically at the endpoint rather than opening an exploitable gap halfway through the animation.
	var body := StaticBody3D.new()
	body.name = "CounterweightBlocker_%d" % roundi(mid * 10.0)
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = _branch_warp_xform(mid, BRANCH_GATE_LANE)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position.y = size.y * 0.5
	body.add_child(collision)
	_branch_root.add_child(body)
	return {
		"gate_visual": root,
		"gate_body": body,
		"gate_collision": collision,
		"gate_base_transform": root.transform,
	}


func _build_branch_pollen_plumes(mid: float) -> Array:
	var plumes: Array = []
	var lanes := [6.9, 7.55, 8.2, 8.85]
	for plume_i in range(lanes.size()):
		var root := Node3D.new()
		root.name = "PollenPlume_%d_%d" % [roundi(mid * 10.0), plume_i]
		root.transform = _branch_warp_xform(mid, float(lanes[plume_i]))
		root.set_meta("branch_base_transform", root.transform)
		root.set_meta("branch_plume_index", plume_i)
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.62
		sphere.height = 1.24
		mesh.mesh = sphere
		mesh.position.y = 0.65 + float(plume_i % 2) * 0.18
		var pollen := LevelPalette.color("channels", "moss")
		mesh.material_override = _make_material(
			Color(pollen.r, pollen.g, pollen.b, 0.48),
			LevelPalette.color("channels", "flora"), 1.2,
			BaseMaterial3D.TRANSPARENCY_ALPHA)
		root.add_child(mesh)
		_branch_root.add_child(root)
		plumes.append(root)
	return plumes

# The switch commits the mechanism; it is not itself the consequence. Decoys remain reusable when a committed
# guard refuses the lure or when the player lets the lysate window expire.
func _build_branch_switch(g: int, branch_i: int, mid: float, kind: String) -> Area3D:
	var theme := _branch_gate_theme(kind)
	# A decoy must be fireable before the pad guard's ordinary detection radius commits it to pursuit.
	# The resulting play is readable: light from the safe neck, then move outward while the guard moves in.
	var switch_lane := BRANCH_NECK_LANE + 0.15 if kind == "decoy" else BRANCH_SWITCH_LANE
	var switch := _add_interactable(self, "BranchSwitch%d" % g, str(theme["label"]),
		Vector3(mid, 0.5, switch_lane), str(theme["label"]), "", 1.0, false, 1.4,
		Interactable.InteractableType.INSPECTION, false)
	match kind:
		"lever": switch.consequence_preview = "Raises the physical gate; the threshold opens only when fully lifted."
		"valve": switch.consequence_preview = "Vents the visible pollen stock covering this cache."
		"decoy": switch.consequence_preview = "Calls the branch guard here; the lysate source is reachable only after it arrives."
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new(); pm.size = Vector3(0.4, 1.3, 0.4); post.mesh = pm
	post.material_override = _make_material(theme["color"], theme["glow"], 1.0)
	post.position = Vector3(0.0, 0.65, 0.0)
	switch.add_child(post)
	_outline_interactable_child(switch, post, "BranchSwitch%d" % g, 1.4)
	_configure_wash_control(
		switch, "branch_switch:%d" % g, "branch_switch", branch_i,
		_on_branch_switch.bind(branch_i, switch))
	return switch

# The three interventions intentionally make different predictions. Only the physical endpoint can expose a
# cache: full gate lift, complete flow clearance, or guard arrival at the beacon.
func _on_branch_switch(g: int, source: Node = null) -> bool:
	if not _accepts_gameplay_events() or g < 0 or g >= _branches.size():
		return false
	var b: Dictionary = _branches[g]
	var action_id := "branch_switch:%d" % int(b.get("gap", -1))
	if _consume_wash_control_receipt(source, action_id).is_empty():
		return false
	var kind := str(b.get("gate_kind", ""))
	var accepted := false
	match kind:
		"lever": accepted = _begin_branch_timed_phase(g, "raising", BRANCH_LEVER_DURATION)
		"valve": accepted = _begin_branch_timed_phase(g, "venting", BRANCH_VALVE_DURATION)
		"decoy": accepted = _begin_branch_decoy(g)
	if not accepted:
		_publish_wash_authority()
		return false
	_say(str(_branch_gate_theme(kind).get("msg", "// CLEAR //")))
	_apply_branch_mechanism_truth(b)
	_publish_wash_authority()
	_schedule_branch_mechanism(g)
	return true


func _begin_branch_timed_phase(branch_index: int, phase: String, duration: float) -> bool:
	var sched = _get_scheduler()
	if sched == null or duration <= 0.0:
		return false
	var b: Dictionary = _branches[branch_index]
	var now := float(sched.get_current_tick())
	b["mechanism_phase"] = phase
	b["phase_started_at"] = now
	b["phase_deadline"] = now + duration
	b["next_check_at"] = -1.0
	b["mechanism_context"] = _branch_default_context(b)
	b["unlocked"] = false
	return true


func _begin_branch_decoy(branch_index: int) -> bool:
	var sched = _get_scheduler()
	if sched == null:
		return false
	var b: Dictionary = _branches[branch_index]
	var guard = b.get("guard")
	if not is_instance_valid(guard) or not guard.has_method("lure_to"):
		_say("// DECOY // no guard is connected to this beacon")
		return false
	var context := _branch_default_context(b)
	var target := _branch_decode_vec3(context.get("lure_target", []), Vector3.ZERO)
	if not bool(guard.lure_to(target, BRANCH_DECOY_DURATION)):
		_say("// DECOY // the guard is committed; wait for it to break off")
		return false
	var now := float(sched.get_current_tick())
	b["mechanism_phase"] = "luring"
	b["phase_started_at"] = now
	b["phase_deadline"] = now + BRANCH_DECOY_DURATION
	b["next_check_at"] = now + BRANCH_DECOY_POLL_INTERVAL
	b["mechanism_context"] = context
	b["unlocked"] = false
	return true


func _on_branch_mechanism_tick(
		branch_index: int, expected_phase: String, expected_deadline: float) -> void:
	if branch_index < 0 or branch_index >= _branches.size():
		return
	var b: Dictionary = _branches[branch_index]
	if str(b.get("mechanism_phase", "")) != expected_phase \
			or not is_equal_approx(float(b.get("phase_deadline", -1.0)), expected_deadline):
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	var now := float(sched.get_current_tick())
	match expected_phase:
		"raising", "venting":
			if now + 0.000001 < expected_deadline:
				_schedule_branch_mechanism(branch_index, false)
				return
			_complete_branch_mechanism(branch_index)
		"luring":
			if now + 0.000001 >= expected_deadline:
				_reset_branch_decoy_window(branch_index, false)
				return
			if _branch_decoy_arrived(b):
				_open_branch_decoy_window(branch_index, now)
				return
			var guard = b.get("guard")
			if not is_instance_valid(guard) or str(guard.get_state()) != "lured":
				_reset_branch_decoy_window(branch_index, true)
				return
			b["next_check_at"] = minf(expected_deadline, now + BRANCH_DECOY_POLL_INTERVAL)
			_publish_wash_authority()
			_schedule_branch_mechanism(branch_index, false)
		"window":
			if now + 0.000001 < expected_deadline:
				var guard = b.get("guard")
				if is_instance_valid(guard) and str(guard.get_state()) == "lured" \
						and _branch_decoy_arrived(b):
					b["next_check_at"] = minf(
						expected_deadline, now + BRANCH_DECOY_POLL_INTERVAL)
					_publish_wash_authority()
					_schedule_branch_mechanism(branch_index, false)
					return
				_reset_branch_decoy_window(branch_index, true)
				return
			_reset_branch_decoy_window(branch_index, false)


func _complete_branch_mechanism(branch_index: int) -> void:
	var b: Dictionary = _branches[branch_index]
	var kind := str(b.get("gate_kind", ""))
	b["mechanism_phase"] = "clear"
	b["phase_started_at"] = -1.0
	b["phase_deadline"] = -1.0
	b["next_check_at"] = -1.0
	b["unlocked"] = true
	_apply_branch_mechanism_truth(b)
	_publish_wash_authority()
	_say("// LIFT // gate fully raised" if kind == "lever" \
		else "// VALVE // pollen cleared; cache exposed")


func _open_branch_decoy_window(branch_index: int, arrival_tick: float) -> void:
	var b: Dictionary = _branches[branch_index]
	b["mechanism_phase"] = "window"
	b["next_check_at"] = minf(
		float(b.get("phase_deadline", arrival_tick)), arrival_tick + BRANCH_DECOY_POLL_INTERVAL)
	b["unlocked"] = true
	var context: Dictionary = (b.get("mechanism_context", {}) as Dictionary).duplicate(true)
	context["arrival_tick"] = arrival_tick
	b["mechanism_context"] = context
	_apply_branch_mechanism_truth(b)
	_publish_wash_authority()
	_schedule_branch_mechanism(branch_index, false)
	_say("// DECOY // guard at beacon; lysate source reachable")


func _reset_branch_decoy_window(branch_index: int, interrupted: bool) -> void:
	var b: Dictionary = _branches[branch_index]
	b["mechanism_phase"] = "idle"
	b["phase_started_at"] = -1.0
	b["phase_deadline"] = -1.0
	b["next_check_at"] = -1.0
	b["mechanism_context"] = _branch_default_context(b)
	b["unlocked"] = false
	_apply_branch_mechanism_truth(b)
	_publish_wash_authority()
	if interrupted:
		_say("// DECOY // the guard broke from the lure before reaching it")


func _branch_decoy_arrived(branch: Dictionary) -> bool:
	var guard = branch.get("guard")
	var gs = _get_game_state()
	if not is_instance_valid(guard) or gs == null or not gs.characters.has(str(guard.char_id)):
		return false
	var context: Dictionary = branch.get("mechanism_context", {})
	var target := _branch_decode_vec3(context.get("lure_target", []), Vector3.INF)
	if not target.is_finite():
		return false
	var pos: Vector3 = gs.get_position(str(guard.char_id))
	return Vector2(pos.x, pos.z).distance_to(Vector2(target.x, target.z)) \
		<= BRANCH_DECOY_ARRIVAL_RADIUS


func _schedule_branch_mechanism(branch_index: int, cancel_existing := true) -> void:
	if branch_index < 0 or branch_index >= _branches.size():
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	var b: Dictionary = _branches[branch_index]
	var phase := str(b.get("mechanism_phase", "idle"))
	var deadline := float(b.get("phase_deadline", -1.0))
	var tag := _branch_event_tag(b)
	if cancel_existing:
		sched.cancel_tag(tag)
	if phase not in ["raising", "venting", "luring", "window"] or deadline < 0.0:
		return
	var now := float(sched.get_current_tick())
	var callback_at := deadline
	if phase in ["luring", "window"]:
		callback_at = minf(deadline, maxf(now, float(b.get("next_check_at", now))))
	sched.schedule_after(maxf(0.0, callback_at - now),
		_on_branch_mechanism_tick.bind(branch_index, phase, deadline), tag)


func _branch_event_tag(branch: Dictionary) -> String:
	return "wash_branch_mechanism_%d" % int(branch.get("gap", -1))


func _branch_default_context(branch: Dictionary) -> Dictionary:
	var kind := str(branch.get("gate_kind", "open"))
	var gap := int(branch.get("gap", -1))
	match kind:
		"lever":
			return {
				"mechanism": "counterweight_gate",
				"blocker_id": "wash_branch_gate_%d" % gap,
				"gate_lane": BRANCH_GATE_LANE,
				"lift_height": BRANCH_GATE_LIFT_HEIGHT,
			}
		"valve":
			return {
				"mechanism": "pollen_vent",
				"source_lane": BRANCH_PAD_LANE,
				"outlet_lane": BRANCH_SWITCH_LANE,
				"stock": "pollen",
			}
		"decoy":
			var guard = branch.get("guard")
			return {
				"mechanism": "guard_lure",
				"guard_id": str(guard.char_id) if is_instance_valid(guard) else "",
				"lure_target": [
					float(branch.get("mid_x", 0.0)) + 0.9,
					0.5,
					BRANCH_NECK_LANE + 0.4,
				],
			}
	return {"mechanism": "open_breather"}


func _branch_decode_vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw as Vector3
	if raw is Array and (raw as Array).size() >= 3:
		var decoded := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
		return decoded if decoded.is_finite() else fallback
	return fallback


func _branch_phase_progress(branch: Dictionary) -> float:
	var phase := str(branch.get("mechanism_phase", "idle"))
	if phase == "clear":
		return 1.0
	if phase not in ["raising", "venting"]:
		return 0.0
	var started := float(branch.get("phase_started_at", -1.0))
	var deadline := float(branch.get("phase_deadline", -1.0))
	if started < 0.0 or deadline <= started:
		return 0.0
	var sched = _get_scheduler()
	var now := float(sched.get_current_tick()) if sched != null else started
	return clampf((now - started) / (deadline - started), 0.0, 1.0)


func _apply_branch_mechanism_truth(branch: Dictionary) -> void:
	var phase := str(branch.get("mechanism_phase", "idle"))
	var kind := str(branch.get("gate_kind", "open"))
	var reward_phase := str(branch.get("reward_phase", REWARD_PHASE_AVAILABLE))
	var collected := reward_phase == REWARD_PHASE_CLAIMED
	branch["collected"] = collected
	var causal_open := kind == "open" or phase == "clear" or phase == "window"
	_restore_reward_interactable(branch, causal_open)
	var switch = branch.get("switch")
	if is_instance_valid(switch):
		var switch_enabled := reward_phase == REWARD_PHASE_AVAILABLE and phase == "idle"
		# v1/v2 saves may still describe this control as one-shot. Clear that historical trigger when the
		# decoy window returns to IDLE so the retry remains real even before the enclosing save is migrated.
		var gs = _get_game_state()
		var data_id := str(switch.get("data_id"))
		if switch_enabled and gs != null and gs.has_interactable(data_id):
			var saved_switch: Dictionary = gs.get_interactable(data_id)
			if bool(saved_switch.get("one_shot", false)) and bool(saved_switch.get("triggered", false)):
				gs.reset_interactable(data_id)
		if switch.has_method("restore_one_shot_presenter"):
			switch.restore_one_shot_presenter(false, switch_enabled)
		else:
			switch.set_interaction_enabled(switch_enabled)
	if kind == "lever":
		var closed := phase != "clear"
		var body = branch.get("gate_body")
		if is_instance_valid(body):
			body.collision_layer = 1 if closed else 0
		var collision = branch.get("gate_collision")
		if is_instance_valid(collision):
			collision.disabled = not closed
		_set_branch_gate_blocked(branch, closed)
	_refresh_branch_mechanism_visual(branch)


func _refresh_branch_mechanism_visual(branch: Dictionary) -> void:
	var phase := str(branch.get("mechanism_phase", "idle"))
	var kind := str(branch.get("gate_kind", "open"))
	var progress := _branch_phase_progress(branch)
	if kind == "lever":
		var gate = branch.get("gate_visual")
		if is_instance_valid(gate):
			var base: Transform3D = branch.get("gate_base_transform", gate.transform)
			var raised := base
			raised.origin += base.basis.y.normalized() * BRANCH_GATE_LIFT_HEIGHT * progress
			gate.transform = raised
	elif kind == "valve":
		var plumes: Array = branch.get("vent_plumes", [])
		for plume_i in range(plumes.size()):
			var plume = plumes[plume_i]
			if not is_instance_valid(plume):
				continue
			plume.visible = phase in ["idle", "venting"]
			var stagger := clampf(
				(progress - float(plume_i) * 0.06) / maxf(0.1, 1.0 - float(plumes.size() - 1) * 0.06),
				0.0, 1.0)
			var base: Transform3D = plume.get_meta("branch_base_transform", plume.transform)
			var streamed := base
			streamed.origin += base.basis.y.normalized() * stagger * (0.55 + 0.12 * float(plume_i))
			plume.transform = streamed
			plume.scale = Vector3(
				maxf(0.08, 1.0 - stagger), 1.0 + stagger, maxf(0.08, 1.0 - stagger))


func _refresh_branch_mechanism_presenters() -> void:
	for branch in _branches:
		_refresh_branch_mechanism_visual(branch)


func _branch_gate_cells(branch: Dictionary) -> Array[Vector2i]:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return []
	var unique := {}
	var mid := float(branch.get("mid_x", 0.0))
	for tangent_offset in [-1.0, 0.0, 1.0]:
		var cell: Vector2i = gs.grid.world_to_grid(
			Vector3(mid + tangent_offset, 0.0, BRANCH_GATE_LANE))
		unique[cell] = true
	var cells: Array[Vector2i] = []
	for cell_v in unique.keys():
		cells.append(cell_v as Vector2i)
	return cells


func _set_branch_gate_blocked(branch: Dictionary, blocked: bool) -> void:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	var blocker_id := "wash_branch_gate_%d" % int(branch.get("gap", -1))
	for cell in _branch_gate_cells(branch):
		var existing := str(gs.grid.dynamic_blockers.get(cell, ""))
		if blocked:
			if existing == "" or existing == blocker_id:
				gs.grid.add_dynamic_blocker(cell, blocker_id)
		elif existing == blocker_id:
			gs.grid.remove_dynamic_blocker(cell)


func _branch_gate_is_blocked(branch: Dictionary) -> bool:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return false
	var cells := _branch_gate_cells(branch)
	var blocker_id := "wash_branch_gate_%d" % int(branch.get("gap", -1))
	if cells.is_empty():
		return false
	for cell in cells:
		if str(gs.grid.dynamic_blockers.get(cell, "")) != blocker_id:
			return false
	return true


func _release_branch_gate_blockers() -> void:
	for branch in _branches:
		if str(branch.get("gate_kind", "")) == "lever":
			_set_branch_gate_blocked(branch, false)

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
		var target_id := str(LURE_SPECS[li].get("target", ""))
		var flure := Flure.new()
		flure.name = "Flure%d" % li
		flure.authority_id = "wash_relay_section_flure_%d" % li
		flure.configure(
			_get_game_state(), lp, [target_id], 24.0, 1.4,
			Color(1.0, 0.55, 0.12))
		flure.one_shot = false
		flure.lure_duration = LURE_DURATION
		flure.settle_pos = lp
		flure.set_enemy_resolver(_enemy_by_id)
		flure.set_pre_trigger_validator(
			_validate_wash_flure_policy.bind("section", idx))
		flure.flure_activated.connect(
			_on_wash_flure_activated.bind("section", idx, flure))
		add_child(flure)
		_register_interactable(flure)
		_flures.append(flure)
		_relay_flures.append(flure)
		_lure_meshes.append(flure.get_node_or_null("Glow"))
		_lure_until.append(-1.0)
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
	if _phase == "active" and target_id in PARTY_IDS \
			and _party_body_in_active_current(target_id):
		if _wash_character(target_id):   # the guard shoves you into the channel -> back to the start shelter
			_announce_wash([target_id])


func _party_body_in_active_current(character_id: String) -> bool:
	var gs = _get_game_state()
	if gs == null or not gs.characters.has(character_id) \
			or gs.is_external_traversal_active(character_id):
		return false
	var p: Vector3 = gs.get_position(character_id)
	if _drain_flooding and _in_drain_channel(p):
		return true
	for section_index in range(mini(SECTIONS.size(), _flooding.size())):
		if not bool(_flooding[section_index]) or _section_disabled(section_index):
			continue
		var section := SECTIONS[section_index] as Dictionary
		if p.x >= float(section.get("x0", INF)) \
				and p.x <= float(section.get("x1", -INF)) \
				and absf(p.z) <= FLOOR_Z_HALF:
			return true
	return false


func _validate_wash_flure_policy(
		source: Node, _actor: String, kind: String, index: int) -> bool:
	if not _accepts_gameplay_events() or source == null:
		return false
	if kind == "drain":
		return source == _drain_bait_flure \
			and _drain_bait_until < 0.0 \
			and _wash_enemy_ready(DRAIN_GUARD_ID)
	if kind == "section" and index >= 0 and index < LURE_SPECS.size() \
			and index < _relay_flures.size():
		return source == _relay_flures[index] \
			and _wash_enemy_ready(str(LURE_SPECS[index].get("target", "")))
	return false


## Flure has already reserved its exact source, committed its target receipt, and asked the real
## Enemy FSM to walk to its settle point before this bookkeeping signal. Wash only mirrors the
## authoritative deadline for HUD/debug reads; it neither distracts nor commands the guard.
func _on_wash_flure_activated(
		_pulled: int, kind: String, index: int, flure: Node) -> void:
	if not is_instance_valid(flure) or not flure.has_method("get_effect_state"):
		return
	var effect: Dictionary = flure.get_effect_state()
	var deadline := float(effect.get("end_tick", -1.0))
	if kind == "drain":
		_drain_bait_until = deadline
		if deadline >= 0.0:
			_schedule_wash_at(
				deadline, _drain_chase_resume, "wash_drain_bait")
		_say("// FLURE SINGS // the ledge guard follows it into the channel")
	elif kind == "section" and index >= 0 and index < LURE_SPECS.size():
		while _lure_until.size() <= index:
			_lure_until.append(-1.0)
		_lure_until[index] = deadline
		if deadline >= 0.0:
			_schedule_wash_at(
				deadline, _on_lure_expired.bind(index),
				"wash_lure_%d" % index)
		_say("// FLURE SINGS // guard drawn")
	_publish_wash_authority()


## Retired compatibility seam. Only the reusable Flure's exact physical trigger can create a song.
func _on_lure(_idx: int, _source: Node = null) -> bool:
	return false

func _on_lure_expired(idx: int) -> void:
	if _phase != "active":
		return
	if idx < _lure_until.size():
		_lure_until[idx] = -1.0
	_publish_wash_authority()

func _set_lure_emission(idx: int, e: float) -> void:
	# Legacy presenter compatibility only. Reusable Flure derives its glow from its own phase.
	if idx < _relay_flures.size():
		return
	if idx < _lure_meshes.size() and is_instance_valid(_lure_meshes[idx]):
		var m := _lure_meshes[idx].material_override as StandardMaterial3D
		if m != null:
			m.emission_energy_multiplier = e

func _lure_active() -> bool:
	for flure in _relay_flures:
		if is_instance_valid(flure) and flure.has_method("is_active") \
				and bool(flure.is_active()):
			return true
	if is_instance_valid(_drain_bait_flure) \
			and _drain_bait_flure.has_method("is_active") \
			and bool(_drain_bait_flure.is_active()):
		return true
	return false


func _sync_flure_mirrors_from_authority() -> void:
	_lure_until.clear()
	for flure in _relay_flures:
		var deadline := -1.0
		if is_instance_valid(flure) and flure.has_method("get_effect_state"):
			var state: Dictionary = flure.get_effect_state()
			if str(state.get("phase", "")) in ["applying", "active"]:
				deadline = float(state.get("end_tick", -1.0))
		_lure_until.append(deadline)
	_drain_bait_until = -1.0
	if is_instance_valid(_drain_bait_flure) \
			and _drain_bait_flure.has_method("get_effect_state"):
		var drain_state: Dictionary = _drain_bait_flure.get_effect_state()
		if str(drain_state.get("phase", "")) in ["applying", "active"]:
			_drain_bait_until = float(drain_state.get("end_tick", -1.0))


# --- Wash cadence (scheduler-driven; fires at exact ticks) ---

func _activate_wash_relay() -> void:
	if _phase == "ready":
		_phase = "active"
	if _phase != "active":
		return
	var was_restoring := _restoring_wash_authority
	_restoring_wash_authority = true
	_ensure_spatial_authority()
	_ensure_scheduled()
	_restoring_wash_authority = was_restoring
	if not was_restoring:
		_publish_wash_authority()


## Held controls, alcove concealment, retry-marker release, and the exit gate are gameplay truth.
## Sample them on one fixed gameplay cadence rather than on render/headless calls. The epoch and next
## absolute tick are portable, while the resulting concealment lives in canonical GameState stats.
func _ensure_spatial_authority() -> void:
	if _phase != "active":
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	var now := float(sched.get_current_tick())
	var should_arm := false
	if not is_finite(_spatial_authority_epoch) or _spatial_authority_epoch < 0.0:
		_spatial_authority_epoch = now
		should_arm = true
	if not is_finite(_next_spatial_authority_tick) \
			or _next_spatial_authority_tick < now - 0.0000001:
		_next_spatial_authority_tick = FixedCadenceScript.next_strict_tick(
			_spatial_authority_epoch, SPATIAL_AUTHORITY_INTERVAL, now
		)
		should_arm = true
	# `_activate_wash_relay()` is called by the presenter every frame. A future callback is already
	# authoritative; repeatedly cancelling and replacing it fills EventScheduler with tombstones and
	# can eventually strand the live recurrence. Explicit reset/restore paths rearm separately.
	if not should_arm:
		return
	_schedule_wash_at(
		_next_spatial_authority_tick,
		_spatial_authority_tick,
		SPATIAL_AUTHORITY_TAG
	)
	_publish_wash_authority()


func _restart_spatial_authority() -> void:
	var sched = _get_scheduler()
	if sched == null:
		_spatial_authority_epoch = -1.0
		_next_spatial_authority_tick = -1.0
		return
	sched.cancel_tag(SPATIAL_AUTHORITY_TAG)
	var now := float(sched.get_current_tick())
	_spatial_authority_epoch = now
	_next_spatial_authority_tick = FixedCadenceScript.next_strict_tick(
		_spatial_authority_epoch, SPATIAL_AUTHORITY_INTERVAL, now
	)
	# Reset/attachment is itself an explicit lifecycle boundary. Establish construction truth once,
	# then every later gameplay consequence comes from the fixed scheduler cadence.
	_evaluate_spatial_authority()
	if _phase == "active":
		_schedule_wash_at(
			_next_spatial_authority_tick,
			_spatial_authority_tick,
			SPATIAL_AUTHORITY_TAG
		)
	_publish_wash_authority()


func _spatial_authority_tick() -> void:
	if _phase != "active":
		_next_spatial_authority_tick = -1.0
		_publish_wash_authority()
		return
	_evaluate_spatial_authority()
	if _phase != "active":
		return
	var sched = _get_scheduler()
	if sched == null:
		_next_spatial_authority_tick = -1.0
		_publish_wash_authority()
		return
	var now := float(sched.get_current_tick())
	_next_spatial_authority_tick = FixedCadenceScript.next_strict_tick(
		_spatial_authority_epoch, SPATIAL_AUTHORITY_INTERVAL, now
	)
	_schedule_wash_at(
		_next_spatial_authority_tick,
		_spatial_authority_tick,
		SPATIAL_AUTHORITY_TAG,
		false
	)
	_publish_wash_authority()


func _evaluate_spatial_authority() -> void:
	if _phase != "active":
		return
	_sample_held_control_truth()
	_sample_hide_concealment_truth()
	_sample_route_and_completion_truth()


func _ensure_scheduled() -> void:
	if _scheduled or _phase != "active":
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_scheduled = true
	_cadence_t0 = sched.get_current_tick()   # anchor the cadence to NOW (so a re-arm after reset stays consistent)
	_section_flood_until.resize(SECTIONS.size())
	for i in range(SECTIONS.size()):
		_section_flood_until[i] = -1.0
		var onset := _cadence_t0 + FIRST_FLOOD + float(SECTIONS[i]["phase"])
		_schedule_wash_at(onset, _make_onset(i), "wash_onset_%d" % i)
		var pretelegraph := onset - TELEGRAPH_LEAD
		if pretelegraph > _cadence_t0:
			_schedule_wash_at(pretelegraph, _make_pretel(i), "wash_pretel_%d" % i)
	# The drain loop floods on its own recurring beat (self-rescheduling like a section, gated on "active").
	_schedule_wash_at(_cadence_t0 + FIRST_FLOOD + DRAIN_LOOP_PHASE,
		_drain_onset, "wash_drain_onset")
	_publish_wash_authority()

func _make_onset(i: int) -> Callable:
	return Callable(self, "_flood_onset").bind(i)

func _make_pretel(i: int) -> Callable:
	return Callable(self, "_pre_telegraph").bind(i)

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
		tw.chain().tween_callback(_free_cosmetic_instance.bind(blob.get_instance_id()))

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
	# Count cadence beats even while a held control suppresses the water. Gauge reads predict the next beat;
	# skipping disabled beats here made that read drift as soon as a player released an override or plate.
	if i < _flood_counts.size():
		_flood_counts[i] += 1
	var now := float(sched.get_current_tick()) if sched != null else _get_scheduler_tick()
	while _section_flood_until.size() < SECTIONS.size():
		_section_flood_until.append(-1.0)
	if not _section_disabled(i):
		_learn_surge_timing_if_near(i)
		_flooding[i] = true
		_sweep_flooded_section(i)       # immediate capture at the onset
		# once the wash arrives the WATER is the signal — the strip sits under it,
		# and a submerged strip at full energy shines through as floating dashes.
		# The pre-surge brightness (1.1) is the telegraph; the flood extinguishes it.
		_set_strip(i, 0.0)
		_play_water_surge(i)            # COSMETIC: a foam/spray accent + rise-pop as the section floods
		if str(SECTIONS[i]["type"]) == "sluice":
			_set_sluice(i, true)            # the gate slams shut — the threshold is impassable
		if sched != null:
			_section_flood_until[i] = now + _dur(i)
			var sweep_count := ceili(_dur(i) / FLOOD_SWEEP_INTERVAL)
			for k in range(1, sweep_count + 1):
				_schedule_wash_at(
					now + minf(_dur(i), FLOOD_SWEEP_INTERVAL * float(k)),
					_make_section_sweep(i),
					"wash_section_sweep_%d_%d" % [i, k]
				)
			_schedule_wash_at(_section_flood_until[i], _set_flood_off.bind(i), "wash_off_%d" % i)
	else:
		_section_flood_until[i] = -1.0
	if sched != null and _phase == "active":
		var next_onset := _cadence_t0 + FIRST_FLOOD + float(SECTIONS[i]["phase"]) \
				+ _period(i) * float(_flood_counts[i])
		_schedule_wash_at(next_onset, _make_onset(i), "wash_onset_%d" % i, false)
		if next_onset - TELEGRAPH_LEAD > now:
			_schedule_wash_at(next_onset - TELEGRAPH_LEAD, _make_pretel(i), "wash_pretel_%d" % i)
	_publish_wash_authority()

func _set_flood_off(i: int) -> void:
	_flooding[i] = false
	if i < _section_flood_until.size():
		_section_flood_until[i] = -1.0
	_set_strip(i, STRIP_IDLE_ENERGY)
	if i < SECTIONS.size() and str(SECTIONS[i]["type"]) == "sluice":
		_set_sluice(i, false)               # the gate lifts — the threshold opens again

	_publish_wash_authority()

func _make_section_sweep(i: int) -> Callable:
	return Callable(self, "_sweep_flooded_section").bind(i)

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
	# held state is sampled at consequence ticks; double_plate needs BOTH pads, override needs the console.
	if dis == "plate" or dis == "double_plate" or dis == "override":
		# Consequence callers sample canonical positions now. `_plate_held` is only the resulting presenter cache.
		_sample_held_control_truth()
		return i < _plate_held.size() and bool(_plate_held[i])
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
	if gs == null or not gs.characters.has(char_id):
		return false
	# A climbvine/crawl/current traversal owns the character until its endpoint. Its flat data-space
	# interpolation may cross wet coordinates while the body is elsewhere; those coordinates must not
	# manufacture a second wash or overwrite the locked traversal.
	if gs.is_external_traversal_active(char_id) or _current_carries.has(char_id):
		return false
	gs.command_stop(char_id)
	var pre_flat := _get_character_position(char_id)
	var pre_render: Vector3 = gs.get_render_position(char_id)
	var inward := Vector3(-pre_render.x, 0.0, -pre_render.z)
	inward = inward.normalized() if inward.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)
	var knocked_render := pre_render + inward * 3.2 - Vector3(0.0, 0.5, 0.0)
	var return_duration := clampf(
		pre_flat.distance_to(START_POS) / WASH_CURRENT_RETURN_SPEED,
		WASH_CURRENT_RETURN_MIN,
		WASH_CURRENT_RETURN_MAX
	)
	var traversal_id := StringName("%sknock:%s" % [WASH_CURRENT_TRAVERSAL_PREFIX, char_id])
	var now := _get_scheduler_tick()
	var impact_tick := now + WASH_CURRENT_KNOCK_DURATION
	var carry := {
		"phase": "knock_reserved",
		"origin_render": _wash_encode_vec3(pre_render),
		"knocked_render": _wash_encode_vec3(knocked_render),
		"return_duration": return_duration,
		"traversal_id": String(traversal_id),
		"impact_tick": impact_tick,
	}
	# Reserve complete owner geometry before GameState can synchronously emit traversal_started.
	_current_carries[char_id] = carry
	_publish_wash_authority()
	_arm_wash_current_preimpact(char_id, "knock", String(traversal_id), impact_tick)
	var accepted := bool(gs.command_external_traversal(
			char_id,
			traversal_id,
			pre_flat,
			pre_render,
			knocked_render,
			WASH_CURRENT_KNOCK_DURATION,
			&"locked"
		))
	if not accepted and _wash_has_matching_traversal(char_id, String(traversal_id)):
		accepted = true
	if not accepted:
		_cancel_wash_current_preimpact(char_id, "knock")
		_current_carries.erase(char_id)
		_publish_wash_authority()
		return false
	# The real character is now owned by GameState's saved traversal. Full concealment represents being
	# inside the opaque current/return channel, not an immunity flag left behind at either endpoint.
	gs.set_character_concealment(char_id, GameState.CONCEAL_FULL)
	if _current_carries.has(char_id):
		carry = _current_carries[char_id] as Dictionary
		if str(carry.get("phase", "")) == "knock_reserved":
			carry["phase"] = "knock"
			_current_carries[char_id] = carry
			_publish_wash_authority()
	# The surge accent adds impact, but the body itself is the authoritative moving object.
	_play_sweep_animation(char_id, pre_render, pre_flat.x)
	return true


func _wash_current_preimpact_tag(character_id: String, leg: String) -> String:
	return "wash_current_preimpact_%s_%s" % [leg, character_id]


func _arm_wash_current_preimpact(
		character_id: String, leg: String, traversal_id: String,
		impact_tick: float) -> void:
	_schedule_wash_at(
		maxf(
			_get_scheduler_tick(),
			impact_tick - WASH_CURRENT_PREIMPACT_EPSILON),
		_mark_wash_current_impact_pending.bind(
			character_id, leg, traversal_id, impact_tick),
		_wash_current_preimpact_tag(character_id, leg))


func _cancel_wash_current_preimpact(character_id: String, leg: String) -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_wash_current_preimpact_tag(character_id, leg))


## This boundary runs just before GameState commits the traversal endpoint. A listener saving from
## external_traversal_finished therefore sees an explicit arrival transaction, never a stale
## CARRYING owner paired with an already-landed body.
func _mark_wash_current_impact_pending(
		character_id: String, leg: String, traversal_id: String,
		impact_tick: float) -> void:
	if not _current_carries.has(character_id):
		return
	var carry: Dictionary = (
		_current_carries[character_id] as Dictionary).duplicate(true)
	if str(carry.get("traversal_id", "")) != traversal_id \
			or not is_equal_approx(
				float(carry.get("impact_tick", -1.0)), impact_tick):
		return
	var phase := str(carry.get("phase", ""))
	if phase not in ["%s_reserved" % leg, leg]:
		return
	carry["phase"] = "%s_impact_pending" % leg
	_current_carries[character_id] = carry
	_publish_wash_authority()


func _wash_has_matching_traversal(
		character_id: String, traversal_id: String) -> bool:
	var gs = _get_game_state()
	if gs == null or not gs.characters.has(character_id) \
			or not gs.is_external_traversal_active(character_id):
		return false
	return str(gs.get_external_traversal_state(character_id).get(
		"traversal_id", "")) == traversal_id

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
	_show_message("// CURRENT CAUGHT // %s being carried to the start shelter" % _format_party_names(ids), 3.0)
	# After a few washes the lesson lands diegetically: you can't walk the surges, you have to RUN them.
	if _sweep_count >= 3 and not _run_hint_shown:
		_run_hint_shown = true
		_show_note("Aster: The water comes too often to walk it. Wait for the surge, then RUN.", 4.5)
	_publish_wash_authority()

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
		var now := float(sched.get_current_tick())
		_drain_flood_until = now + DRAIN_LOOP_DUR
		# Re-check the whole run across the visible flood WINDOW: party and guards entering mid-surge obey
		# the same rule. The sweeps ride the scheduler, so they're fast-forward invariant.
		for k in range(1, DRAIN_DROWN_SWEEPS + 1):
			_schedule_wash_at(now + DRAIN_LOOP_DUR * float(k) / float(DRAIN_DROWN_SWEEPS),
				_wash_drain, "wash_drain_sweep_%d" % k)
		_schedule_wash_at(_drain_flood_until, _set_drain_off, "wash_drain_off")
	if sched != null and _phase == "active":
		var next_onset := _cadence_t0 + FIRST_FLOOD + DRAIN_LOOP_PHASE \
				+ DRAIN_LOOP_PERIOD * float(_drain_flood_count)
		_schedule_wash_at(next_onset, _drain_onset, "wash_drain_onset", false)
	_publish_wash_authority()

func _set_drain_off() -> void:
	_drain_flooding = false
	_drain_flood_until = -1.0
	_publish_wash_authority()

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

# Catch an enemy in the visible flood. This method does not kill or teleport it: the exact reusable
# Channel first reserves and carries the real GameState body inward. Its IMPACT transaction owns
# lethal damage; Wash retains only provenance/count/cleanup mirrors for UI and retry bookkeeping.
func _drown_enemy(enemy, section_index := -1) -> bool:
	if not is_instance_valid(enemy):
		return false
	var id: String = enemy.char_id
	var gs = _get_game_state()
	if id.is_empty() or gs == null or not gs.characters.has(id) \
			or _enemy_drown_mirrors.has(id) \
			or gs.is_external_traversal_active(id):
		return false
	var channel = _section_enemy_currents.get(section_index) \
		if section_index >= 0 else _drain_enemy_current
	if not is_instance_valid(channel) or not channel.has_method("request_sweep_body"):
		return false
	var origin: Vector3 = gs.get_position(id)
	var destination := _wash_enemy_current_destination(id, origin, section_index)
	var mirror := {
		"phase": "reserved",
		"section_index": section_index,
		"channel_key": str(channel.authority_state_key()),
		"started_tick": _get_scheduler_tick(),
		"impact_tick": -1.0,
		"destination": _wash_encode_vec3(destination),
		"counted": false,
		"removal_deadline": -1.0,
	}
	_enemy_drown_mirrors[id] = mirror
	_publish_wash_authority()
	var accepted := bool(channel.request_sweep_body(id, "enemy"))
	if not accepted:
		_enemy_drown_mirrors.erase(id)
		_publish_wash_authority()
		return false
	mirror = (_enemy_drown_mirrors.get(id, mirror) as Dictionary).duplicate(true)
	var traversal: Dictionary = gs.get_external_traversal_state(id)
	mirror["phase"] = "carrying"
	mirror["impact_tick"] = float(traversal.get("end_tick", -1.0))
	_enemy_drown_mirrors[id] = mirror
	_publish_wash_authority()
	return true


func _on_enemy_current_impact(id: String, section_index: int) -> void:
	var gs = _get_game_state()
	var enemy = _enemy_by_id(id)
	if gs == null or not gs.characters.has(id) or not is_instance_valid(enemy) \
			or (enemy.has_method("is_alive") and bool(enemy.is_alive())):
		return
	var mirror: Dictionary = (
		_enemy_drown_mirrors.get(id, {}) as Dictionary).duplicate(true)
	if mirror.is_empty():
		var fallback_channel_key: String = (
			"kit:channel:wash_relay_enemy_section_%d" % section_index
			if section_index >= 0
			else "kit:channel:wash_relay_enemy_drain")
		mirror = {
			"section_index": section_index,
			"channel_key": fallback_channel_key,
			"started_tick": _get_scheduler_tick(),
			"destination": _wash_encode_vec3(gs.get_position(id)),
			"counted": false,
		}
	mirror["phase"] = "arrived"
	mirror["impact_tick"] = _get_scheduler_tick()
	if not bool(mirror.get("counted", false)):
		mirror["counted"] = true
		if section_index >= 0:
			_section_drowned_count += 1
			_say("// SURGE HIT // section %d carried the guard into the drain" % (
				section_index + 1))
		else:
			_drowned_count += 1
			_say("// DRAINED // the current carried the guard down the shaft")
	var deadline := _get_scheduler_tick() + DRAIN_KILL_DELAY
	mirror["removal_deadline"] = deadline
	_enemy_drown_mirrors[id] = mirror
	_pending_drown_removals[id] = deadline
	# Publish the arrived/dead receipt before scheduling presentation cleanup. A save here can
	# finish only the removal; it can never replay the Channel impact or increment the count twice.
	_publish_wash_authority()
	_schedule_wash_at(
		deadline, _remove_enemy.bind(id), "wash_drain_kill_%s" % id)

# Fully remove a drowned enemy: drop it from _enemies, unregister its GameState character, free the node.
func _remove_enemy(id: String) -> void:
	_pending_drown_removals.erase(id)
	if _enemy_drown_mirrors.has(id):
		var mirror: Dictionary = (
			_enemy_drown_mirrors[id] as Dictionary).duplicate(true)
		mirror["phase"] = "removed"
		mirror["removal_deadline"] = -1.0
		_enemy_drown_mirrors[id] = mirror
		_publish_wash_authority()
	var gs = _get_game_state()
	for i in range(_enemies.size() - 1, -1, -1):
		var e = _enemies[i]
		if is_instance_valid(e) and e.char_id == id:
			_enemies.remove_at(i)
			if gs != null and gs.has_method("unregister_character") and gs.characters.has(id):
				gs.unregister_character(id)
			e.queue_free()
	_publish_wash_authority()

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
			# Enemy owns a separate serialized FSM record. Unregistering the dead body does not
			# retract that record, so a replacement presenter would otherwise attach, find the
			# prior `dead` phase, and immediately restore itself with zero HP. A relay reset is an
			# explicit retry boundary: discard that enemy future before attaching the fresh body.
			var gs = _get_game_state()
			if gs != null and gs.has_method("set_world_state"):
				gs.set_world_state("runtime:enemy:%s" % id, {})
			_spawn_ch_enemy(spec)

# --- Drain loop: lead the guard in (bait, then chase) ---

## Retired compatibility seam. The DrainBait node is a real Flure and only its exact trigger can
## reserve a source/target receipt and ask the Enemy FSM to follow it into the water.
func _on_drain_bait(_source: Node = null) -> bool:
	return false

# The Flure/Enemy pair owns release and return. This callback only retires Wash's HUD deadline.
func _drain_chase_resume() -> void:
	_drain_bait_until = -1.0
	if _phase != "active":
		return
	_publish_wash_authority()

func _on_drain_cache(source: Node = null) -> bool:
	if not _accepts_gameplay_events():
		return false
	if _consume_wash_control_receipt(source, "drain_cache").is_empty():
		return false
	if not _claim_reward_source(_drain_reward):
		_restore_reward_interactable(_drain_reward, true)
		_publish_wash_authority()
		return false
	_publish_wash_authority()
	_say("// LYSATE // %s takes concentrated lysate from the flood ledge" \
		% str(_drain_reward.get("reward_claimed_by", "")).capitalize())
	return true

func _on_drain_flora_tended(source: Node = null) -> bool:
	if not _accepts_gameplay_events() or _drain_flora_tended:
		return false
	if _consume_wash_control_receipt(source, "drain_flora").is_empty():
		return false
	_drain_flora_tended = true
	var world := DRAIN_FLORA_POS
	if is_instance_valid(_drain_flora_interactable):
		world = _drain_flora_interactable.global_position
	_spawn_flora_light(world, DRAIN_FLORA_POS)
	_show_message("// TEND FLORA // living light marks the drain's flooding lane", 3.0)
	_set_preview_step("wash_relay_drain_flora_tended")
	if is_instance_valid(_drain_flora_interactable):
		_flash_causal_feedback(_drain_flora_interactable, 2.4, 1.5)
		_set_causal_feedback_latched(_drain_flora_interactable, true)
	_publish_wash_authority()
	return true

func _spawn_flora_light(world: Vector3, flat: Vector3) -> void:
	if _flora_light_root == null or not is_instance_valid(_flora_light_root):
		_flora_light_root = Node3D.new()
		_flora_light_root.name = "DrainFloraLights"
		add_child(_flora_light_root)
	var node := FloraLight.new()
	node.name = "DrainFloraLight"
	node.position = world + Vector3(0.0, 0.35, 0.0)
	node.configure({
		"albedo": Color(0.2, 0.7, 0.5), "emission": Color(0.4, 1.0, 0.7), "emission_energy": 2.2,
		"bloom_radius": 0.22, "light_color": Color(0.5, 1.0, 0.75), "light_energy": 2.2, "light_range": 6.0,
	})
	_flora_light_root.add_child(node)
	_flora_lights.append({"pos": flat, "node": node})

# Cosmetic impact accent around the REAL current-owned character traversal. The spiral winds around its
# central axis, so the surge rises at the outer wall and follows the body's inward first leg. There is no
# duplicate character-coloured proxy: the actual player node moves through GameState's saved traversal.
func _play_sweep_animation(_char_id: String, from_render: Vector3, _from_x: float) -> void:
	if not is_instance_valid(_wash_anim_root):
		_wash_anim_root = Node3D.new()
		_wash_anim_root.name = "WashSweep"
		add_child(_wash_anim_root)
	# Inward = toward the spiral's central axis (origin in XZ); outward (= the water source) is the reverse.
	var inward := Vector3(-from_render.x, 0.0, -from_render.z)
	inward = inward.normalized() if inward.length() > 0.01 else Vector3(0, 0, -1)
	var outward := -inward
	var source := from_render + outward * 1.3 + Vector3(0.0, 0.35, 0.0)   # the surge wells up at the outer wall
	# Water surge at the outer source. The character itself supplies the moving focal point.
	var surge := _build_cosmetic_blob(_wash_anim_root, source, Vector3(1.4, 0.7, 1.4),
		Color(0.10, 0.42, 0.66, 0.8), Color(0.3, 0.78, 1.0), 2.2)
	var tw := create_tween()
	# Follow the same initial inward impulse, then fade. This tween never owns character state.
	tw.parallel().tween_property(surge, "global_position", from_render + inward * 1.6, 0.8).set_trans(Tween.TRANS_SINE)
	var um := surge.material_override as StandardMaterial3D
	if um != null:
		tw.parallel().tween_property(um, "albedo_color:a", 0.0, 0.7)
		tw.parallel().tween_property(um, "emission_energy_multiplier", 0.0, 0.7)
	tw.chain().tween_callback(_free_cosmetic_instance.bind(surge.get_instance_id()))


func _free_cosmetic_instance(instance_id: int) -> void:
	# Chunk reset may dispose an accent before its frame tween ends. Bind the scalar instance id,
	# not the Node itself, so a later callback cannot retain and invoke a freed lambda capture.
	var cosmetic := instance_from_id(instance_id)
	if is_instance_valid(cosmetic):
		cosmetic.queue_free()

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
		# The rim outfall sheets ride the SAME eased intensity — the falls pour exactly when
		# (and as hard as) the section floods, so the dressing never lies about the cadence.
		WashRelayDressing.drive_falls(_dressing, i, inten)
		mi.visible = inten > 0.02
		if mi.visible:
			var sc := 0.55 + 0.85 * inten
			mi.scale = Vector3(sc, sc, sc)
			var m := mi.material_override as StandardMaterial3D
			if m != null:
				m.albedo_color.a = clampf(inten * 1.15, 0.0, 1.0)

# --- Interactions ---

func _on_pressure_valve(source: Node = null) -> bool:
	if not _accepts_gameplay_events():
		return false
	if _consume_wash_control_receipt(source, "pressure_valve").is_empty():
		return false
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
		_schedule_wash_at(_pressure_vent_until, _on_pressure_vent_closed, 'wash_pressure_vent')
	_publish_wash_authority()
	return true


func _on_pressure_vent_closed() -> void:
	_pressure_vent_until = -1.0
	if is_instance_valid(_pressure_valve):
		_set_causal_feedback_latched(_pressure_valve, false)
	if is_instance_valid(_drain_flora_interactable):
		_set_causal_feedback_latched(_drain_flora_interactable, false)
	if PRESSURE_VENT_SECTION < _flow_strips.size():
		_set_strip(PRESSURE_VENT_SECTION, STRIP_IDLE_ENERGY)
	if _phase == 'active':
		_show_message('// PRESSURE RETURNING // the jet manifold is live again', 2.2)
	_publish_wash_authority()

## Aster logs the cadence at the terminal. From here on, the assist poll watches for a
## crossing attempt at the assist section and lets the SCHEDULER do the waiting.
func _on_flow_terminal(source: Node = null) -> bool:
	if not _accepts_gameplay_events():
		return false
	if _consume_wash_control_receipt(source, "flow_terminal").is_empty():
		return false
	_flow_logged = true
	_surge_timing_learned = true
	_set_strip(FLOW_ASSIST_SECTION, 1.3)
	_show_message("// CADENCE LOGGED // CROSSINGS WILL WAIT FOR THE WINDOW", 3.2)
	_set_preview_step("wash_relay_flow_logged")
	if is_instance_valid(_flow_terminal):
		_flash_causal_feedback(_flow_terminal, 2.2, 1.45)
	_start_flow_assist_poll()
	_publish_wash_authority()
	return true

func _on_flow_terminal_rejected(_interactable: Node, _required: String) -> void:
	var who := str(_get_active_character())
	if who == "" or who == "aster" or _flow_barked.get(who, false):
		return
	_flow_barked[who] = true
	_show_note("Can't parse the console. Aster might.", 2.4)

func _flow_assist_tag() -> String:
	return "wash_flow_assist_cross"

## `from_dispatch` matters: a self-reschedule during dispatch must NOT cancel its own tag
## (the scheduler removes a dispatching callback; canceling then corrupts the pending
## count and strands the recurrence — the _schedule_wash_at doc's exact warning).
func _start_flow_assist_poll(from_dispatch := false) -> void:
	var sched = _get_scheduler()
	if sched == null or not _flow_logged:
		return
	_schedule_wash_at(float(sched.get_current_tick()) + FLOW_ASSIST_POLL,
		_flow_assist_poll, "wash_flow_assist_poll", not from_dispatch)

## Every poll tick: if Aster is approaching the assist section's water while a surge is
## due, HOLD the group at the near lip and schedule the crossing at the computed window.
## Pure tick arithmetic + real logged commands — deterministic, replayable, FF-invariant.
func _flow_assist_poll() -> void:
	if _phase != "active" or not _flow_logged:
		return
	_start_flow_assist_poll(true)
	var sched = _get_scheduler()
	var gs = _get_game_state()
	if sched == null or gs == null:
		return
	var now := float(sched.get_current_tick())
	if now < _flow_assist_busy_until:
		return
	var s: Dictionary = SECTIONS[FLOW_ASSIST_SECTION]
	var x0 := float(s["x0"])
	var x1 := float(s["x1"])
	var p: Vector3 = _get_character_position("aster")
	if p.x < x0 - 2.6 or p.x > x0 - 0.2 or absf(p.z) > 3.6:
		return
	if not gs.is_moving("aster"):
		return
	# INTENT gate: only a genuine crossing order arms the assist — a move that stays on
	# this side (the terminal, the override console, walking away) is never hijacked.
	var move_dest: Vector3 = gs.get_destination("aster")
	if not move_dest.is_finite() or move_dest.x <= x0 + 0.5:
		return
	var own_speed := maxf(0.5, float((gs.characters.get("aster", {}) as Dictionary).get("move_speed", 3.2)))
	var t_pass := (x1 - x0 + 2.6) / own_speed
	var t_cross := (x1 - x0 + 2.6) / FLOW_CROSS_SPEED
	var flooding: bool = _flooding[FLOW_ASSIST_SECTION]
	var next_in := _section_next_onset_in(FLOW_ASSIST_SECTION)
	if not flooding and (next_in < 0.0 or next_in > t_pass + FLOW_CROSS_MARGIN):
		return   # genuinely safe at the walker's own pace — walk on
	var dur := float(s.get("dur", FLOOD_DURATION))
	var window_start: float
	if flooding and float(_section_flood_until[FLOW_ASSIST_SECTION]) > now:
		window_start = float(_section_flood_until[FLOW_ASSIST_SECTION]) + 0.15
	else:
		window_start = now + maxf(next_in, 0.0) + dur + 0.15
	# Capture the group NOW (never re-read the live selection at fire time) and park each
	# member on its own lane so cooperative pathfinding never stacks the hold.
	var ids := _flow_assist_group()
	_flow_assist_held = ids.duplicate()
	var slot := 0
	for id in ids:
		gs.command_stop(id)
		gs.command_move_to_pos(id, Vector3(x0 - 1.1, 0.5, -1.6 + 1.6 * float(slot % 3)))
		slot += 1
	_show_note("// LOGGED CADENCE // HOLDING FOR THE WINDOW", 2.4)
	_schedule_wash_at(window_start, _flow_assist_cross, _flow_assist_tag())
	_flow_assist_busy_until = window_start + t_cross + 1.0

func _flow_assist_group() -> Array:
	var sel: Array = _selected_party_ids()
	return sel if sel.has("aster") else ["aster"]

func _flow_assist_cross() -> void:
	if _phase != "active" or not _flow_logged:
		return
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		return
	var s: Dictionary = SECTIONS[FLOW_ASSIST_SECTION]
	var hold_x := float(s["x0"]) - 1.1
	var t_cross := (float(s["x1"]) - float(s["x0"]) + 2.6) / FLOW_CROSS_SPEED
	var gap := _period(FLOW_ASSIST_SECTION) - float(s.get("dur", FLOOD_DURATION))
	var dashed := false
	for id in _flow_assist_held:
		var p: Vector3 = _get_character_position(str(id))
		if absf(p.x - hold_x) > 2.0:
			continue   # wandered off — a newer intent supersedes the assist
		# only dash a member the WINDOW actually affords from where they stand; a
		# straggler stays parked for the next window instead of being fed to the surge
		if (float(s["x1"]) - p.x + 0.6) / FLOW_CROSS_SPEED + 0.15 > gap:
			continue
		# the dash is priced at run speed; each member's own pace comes back after the beat
		_flow_assist_prev_speeds[id] = float((gs.characters.get(str(id), {}) as Dictionary).get("move_speed", 3.2))
		gs.change_move_speed(str(id), FLOW_CROSS_SPEED)
		gs.command_move_to_pos(str(id), Vector3(float(s["x1"]) + 0.55, 0.5, clampf(p.z, -3.0, 3.0)))
		dashed = true
	_flow_assist_held = []
	if dashed:
		_schedule_wash_at(float(sched.get_current_tick()) + t_cross + 0.4,
			_flow_assist_restore_speeds, "wash_flow_assist_restore")
	else:
		_flow_assist_busy_until = -1.0   # nothing crossed — re-arm the assist immediately

func _flow_assist_restore_speeds() -> void:
	var gs = _get_game_state()
	if gs != null:
		for id in _flow_assist_prev_speeds:
			gs.change_move_speed(str(id), float(_flow_assist_prev_speeds[id]))
	_flow_assist_prev_speeds.clear()

func _on_override(i: int, source: Node = null) -> bool:
	# The override is a HELD console — the hold is positional (refreshed in _update like a plate), so arriving
	# only confirms the member is manning the station. Step off and the flow resumes (no permanent latch).
	if not _accepts_gameplay_events() or i < 0 or i >= SECTIONS.size():
		return false
	if _consume_wash_control_receipt(
			source, "override:%d" % i).is_empty():
		return false
	_show_message("// SECTION %d // HOLD HERE while the rest cross" % (i + 1), 2.5)
	var control = _override_controls.get(i, null)
	if is_instance_valid(control):
		_flash_causal_feedback(control, 1.8, 1.25)
	_publish_wash_authority()
	return true

## Retired compatibility seams. A chunk method has neither the exact source object nor a synchronous
## body receipt, so it cannot tend or climb on the player's behalf. The visible upper/lower
## Interactables are the only gameplay entry points; their ClimbvineReturn signals retain feedback.
func _rejoin_waiting_crew() -> int:
	return 0


func _on_sloperope(_character_id := "") -> void:
	return


func _on_climb() -> void:
	return


func _wash_climb_group() -> Array:
	var waiting := _washed.keys()
	waiting.sort()
	return waiting


func _on_climbvine_deployment_started(_return_id: StringName, _state: Dictionary) -> void:
	_sloperope_deployed = false
	_publish_wash_authority()


func _on_climbvine_deployed(_return_id: StringName, _state: Dictionary) -> void:
	_sloperope_deployed = true
	_publish_wash_authority()
	_show_message("// VINE DEPLOYED // the lower CLIMB mouth is now reachable at the start", 3.0)


func _on_climbvine_committed(_return_id: StringName, character_ids: Array) -> void:
	for id_v in character_ids:
		_washed.erase(str(id_v))
	_publish_wash_authority()


func _on_climbvine_tend_rejected(character_id: String, required_character: String) -> void:
	if character_id.is_empty():
		return
	_show_message("// NEED %s // %s cannot tend this vine" % [
		required_character.to_upper(), character_id.capitalize()
	], 2.4)


func _sync_climbvine_presenter() -> void:
	if not is_instance_valid(_climbvine_return):
		_sloperope_deployed = false
		return
	_climbvine_return.sync_from_game_state()
	_sloperope_deployed = bool(_climbvine_return.is_deployed())
	_climb_interactable = _climbvine_return.get_lower_interactable()
	_rope_mesh = _climbvine_return.get("_vine_visual") as Node3D


func _on_wash_external_traversal_finished(
		character_id: String, traversal_id: StringName
	) -> void:
	var traversal_name := String(traversal_id)
	if traversal_name.begins_with(WASH_CURRENT_TRAVERSAL_PREFIX):
		_on_wash_current_leg_finished(character_id, traversal_name)
		return
	if not String(traversal_id).begins_with(SLOPEROPE_TRAVERSAL_PREFIX):
		return
	_show_message("// REJOINED // %s climbed to the upper landing" % character_id.capitalize(), 2.2)


func _on_wash_external_traversal_cancelled(
		character_id: String, traversal_id: StringName, _reason: StringName
	) -> void:
	var traversal_name := String(traversal_id)
	if not traversal_name.begins_with(WASH_CURRENT_TRAVERSAL_PREFIX) \
			or not _current_carries.has(character_id):
		return
	var carry: Dictionary = _current_carries[character_id]
	if str(carry.get("traversal_id", "")) != traversal_name:
		return
	_cancel_wash_current_preimpact(
		character_id, "return" if ":return:" in traversal_name else "knock")
	_current_carries.erase(character_id)
	var gs = _get_game_state()
	if gs != null and gs.characters.has(character_id):
		gs.set_character_concealment(character_id, GameState.CONCEAL_NONE)
	_publish_wash_authority()


func _on_wash_current_leg_finished(character_id: String, traversal_name: String) -> void:
	if not _current_carries.has(character_id):
		return
	var carry: Dictionary = (
		_current_carries[character_id] as Dictionary).duplicate(true)
	if str(carry.get("traversal_id", "")) != traversal_name:
		return
	var phase := str(carry.get("phase", ""))
	if traversal_name == "%sknock:%s" % [
		WASH_CURRENT_TRAVERSAL_PREFIX, character_id
	]:
		if phase in ["knock_reserved", "knock"]:
			carry["phase"] = "knock_impact_pending"
			_current_carries[character_id] = carry
			_publish_wash_authority()
		elif phase != "knock_impact_pending":
			return
		_start_wash_current_return(character_id, carry)
		return
	if traversal_name != "%sreturn:%s" % [
		WASH_CURRENT_TRAVERSAL_PREFIX, character_id
	]:
		return
	if phase in ["return_reserved", "return"]:
		carry["phase"] = "return_impact_pending"
		_current_carries[character_id] = carry
		_publish_wash_authority()
	elif phase != "return_impact_pending":
		return
	_complete_wash_current_arrival(character_id)


func _complete_wash_current_arrival(character_id: String) -> void:
	if not _current_carries.has(character_id):
		return
	var carry: Dictionary = (
		_current_carries[character_id] as Dictionary).duplicate(true)
	var phase := str(carry.get("phase", ""))
	if phase == "return_impact_pending":
		carry["phase"] = "landing_committing"
		_current_carries[character_id] = carry
		# Publish the exact arrival transaction before concealment/roster feedback can synchronously
		# expose the landing to a save observer.
		_publish_wash_authority()
	elif phase != "landing_committing":
		return
	var gs = _get_game_state()
	if gs != null and gs.characters.has(character_id):
		gs.set_character_concealment(character_id, GameState.CONCEAL_NONE)
	_washed[character_id] = true
	_current_carries.erase(character_id)
	_publish_wash_authority()
	_show_message("// SHELTER LANDED // %s reached the start return" % character_id.capitalize(), 2.2)


func _start_wash_current_return(character_id: String, carry: Dictionary) -> void:
	var gs = _get_game_state()
	if gs == null or not gs.characters.has(character_id):
		return
	var existing_id := "%sreturn:%s" % [
		WASH_CURRENT_TRAVERSAL_PREFIX, character_id]
	if _wash_has_matching_traversal(character_id, existing_id):
		var existing: Dictionary = gs.get_external_traversal_state(character_id)
		carry["phase"] = "return"
		carry["traversal_id"] = existing_id
		carry["impact_tick"] = float(existing.get(
			"end_tick", carry.get("impact_tick", -1.0)))
		_current_carries[character_id] = carry
		_publish_wash_authority()
		_arm_wash_current_preimpact(
			character_id, "return", existing_id,
			float(carry.get("impact_tick", _get_scheduler_tick())))
		return
	if gs.is_external_traversal_active(character_id):
		return
	var knocked_render := _wash_decode_vec3(
		carry.get("knocked_render", null), gs.get_render_position(character_id)
	)
	var render_destination := START_POS
	if gs.coord_map != null and gs.coord_map.has_method("to_world"):
		render_destination = gs.coord_map.to_world(START_POS)
	var duration := clampf(
		float(carry.get("return_duration", WASH_CURRENT_RETURN_MIN)),
		WASH_CURRENT_RETURN_MIN,
		WASH_CURRENT_RETURN_MAX
	)
	var traversal_id := StringName(existing_id)
	var now := _get_scheduler_tick()
	var impact_tick := now + duration
	carry["phase"] = "return_reserved"
	carry["traversal_id"] = String(traversal_id)
	carry["impact_tick"] = impact_tick
	_current_carries[character_id] = carry
	_publish_wash_authority()
	_arm_wash_current_preimpact(
		character_id, "return", String(traversal_id), impact_tick)
	var accepted := bool(gs.command_external_traversal(
			character_id,
			traversal_id,
			START_POS,
			knocked_render,
			render_destination,
			duration,
			&"locked"
		))
	if not accepted and _wash_has_matching_traversal(
			character_id, String(traversal_id)):
		accepted = true
	if not accepted:
		# No endpoint is granted on a rejected second leg. Keep the saved phase so a restore or an
		# explicit reset can recover it without manufacturing arrival.
		_cancel_wash_current_preimpact(character_id, "return")
		_schedule_wash_current_reconcile()
		return
	if _current_carries.has(character_id):
		carry = _current_carries[character_id] as Dictionary
		if str(carry.get("phase", "")) == "return_reserved":
			carry["phase"] = "return"
			_current_carries[character_id] = carry
			_publish_wash_authority()


func _cancel_wash_current_carries(reason: StringName) -> void:
	var gs = _get_game_state()
	if gs != null:
		for char_id_v in _current_carries.keys():
			var char_id := str(char_id_v)
			_cancel_wash_current_preimpact(char_id, "knock")
			_cancel_wash_current_preimpact(char_id, "return")
			if not gs.characters.has(char_id):
				continue
			var traversal: Dictionary = gs.get_external_traversal_state(char_id)
			if str(traversal.get("traversal_id", "")).begins_with(WASH_CURRENT_TRAVERSAL_PREFIX):
				gs.cancel_external_traversal(char_id, reason)
			gs.set_character_concealment(char_id, GameState.CONCEAL_NONE)
	_current_carries.clear()


func _reset_enemy_current_channels() -> void:
	for channel in _section_enemy_currents.values():
		if is_instance_valid(channel) and channel.has_method("reset"):
			channel.reset()
	if is_instance_valid(_drain_enemy_current) \
			and _drain_enemy_current.has_method("reset"):
		_drain_enemy_current.reset()


func _schedule_wash_current_reconcile() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	_schedule_wash_at(
		_get_scheduler_tick() + WASH_CURRENT_PREIMPACT_EPSILON,
		_reconcile_wash_current_carries,
		WASH_CURRENT_RECONCILE_TAG)


func _reconcile_wash_current_carries() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var ids := _current_carries.keys()
	ids.sort()
	for id_v in ids:
		var character_id := str(id_v)
		if not _current_carries.has(character_id) \
				or not gs.characters.has(character_id):
			_current_carries.erase(character_id)
			continue
		var carry: Dictionary = (
			_current_carries[character_id] as Dictionary).duplicate(true)
		var phase := str(carry.get("phase", ""))
		var traversal_id := str(carry.get("traversal_id", ""))
		var matching := _wash_has_matching_traversal(
			character_id, traversal_id)
		if matching:
			var leg := "return" if ":return:" in traversal_id else "knock"
			var phase_matches_leg: bool = phase in (
				["knock_reserved", "knock", "knock_impact_pending"]
					if leg == "knock"
					else ["return_reserved", "return", "return_impact_pending"])
			if not phase_matches_leg:
				# A body and an owner record that disagree about the active leg are a torn
				# future, not permission to infer an endpoint. Cancel that exact owned
				# traversal and retract concealment rather than leaving an orphaned carry.
				gs.cancel_external_traversal(
					character_id, &"wash_relay_current_phase_mismatch")
				if _current_carries.has(character_id):
					_retract_unproven_wash_current(character_id)
				continue
			if phase == "%s_reserved" % leg:
				carry["phase"] = leg
				_current_carries[character_id] = carry
				_publish_wash_authority()
			_arm_wash_current_preimpact(
				character_id, leg, traversal_id,
				float(carry.get("impact_tick", _get_scheduler_tick())))
			continue
		if gs.is_external_traversal_active(character_id):
			# Another mechanism owns the body. This current cannot fabricate an arrival.
			_current_carries.erase(character_id)
			gs.set_character_concealment(character_id, GameState.CONCEAL_NONE)
			_publish_wash_authority()
			continue
		match phase:
			"knock_reserved", "return_reserved":
				_resume_reserved_wash_current_leg(character_id, carry)
			"knock_impact_pending":
				_start_wash_current_return(character_id, carry)
			"return_impact_pending":
				if gs.get_position(character_id).distance_to(START_POS) <= 0.001:
					_complete_wash_current_arrival(character_id)
				else:
					_retract_unproven_wash_current(character_id)
			"landing_committing":
				if gs.get_position(character_id).distance_to(START_POS) <= 0.001:
					_complete_wash_current_arrival(character_id)
				else:
					_retract_unproven_wash_current(character_id)
			_:
				# CARRYING without GameState ownership proves cancellation, not arrival.
				_retract_unproven_wash_current(character_id)


func _resume_reserved_wash_current_leg(
		character_id: String, carry: Dictionary) -> void:
	var gs = _get_game_state()
	if gs == null or not gs.characters.has(character_id):
		return
	var phase := str(carry.get("phase", ""))
	var leg := "knock" if phase == "knock_reserved" else "return"
	var impact_tick := float(carry.get("impact_tick", -1.0))
	var remaining := impact_tick - _get_scheduler_tick()
	if impact_tick < 0.0 or remaining <= WASH_CURRENT_PREIMPACT_EPSILON:
		_retract_unproven_wash_current(character_id)
		return
	var traversal_id := str(carry.get("traversal_id", ""))
	var data_destination: Vector3 = gs.get_position(character_id) \
		if leg == "knock" else START_POS
	var render_origin: Vector3 = _wash_decode_vec3(
		carry.get("origin_render", null), gs.get_render_position(character_id)) \
		if leg == "knock" else _wash_decode_vec3(
			carry.get("knocked_render", null), gs.get_render_position(character_id))
	var render_destination: Vector3 = _wash_decode_vec3(
		carry.get("knocked_render", null), render_origin) \
		if leg == "knock" else (
			gs.coord_map.to_world(START_POS)
				if gs.coord_map != null and gs.coord_map.has_method("to_world")
				else START_POS)
	_arm_wash_current_preimpact(
		character_id, leg, traversal_id, impact_tick)
	var accepted := bool(gs.command_external_traversal(
		character_id,
		StringName(traversal_id),
		data_destination,
		render_origin,
		render_destination,
		remaining,
		&"locked"))
	if accepted or _wash_has_matching_traversal(character_id, traversal_id):
		if _current_carries.has(character_id):
			carry = _current_carries[character_id] as Dictionary
			if str(carry.get("phase", "")) == "%s_reserved" % leg:
				carry["phase"] = leg
				_current_carries[character_id] = carry
				_publish_wash_authority()
		return
	_cancel_wash_current_preimpact(character_id, leg)
	_retract_unproven_wash_current(character_id)


func _retract_unproven_wash_current(character_id: String) -> void:
	_cancel_wash_current_preimpact(character_id, "knock")
	_cancel_wash_current_preimpact(character_id, "return")
	_current_carries.erase(character_id)
	var gs = _get_game_state()
	if gs != null and gs.characters.has(character_id):
		gs.set_character_concealment(character_id, GameState.CONCEAL_NONE)
	_publish_wash_authority()


func _cancel_sloperope_climbs(reason: StringName) -> void:
	if is_instance_valid(_climbvine_return):
		# The kit owns both rider cancellation and the deployment phase. A reset must retract both,
		# otherwise a discarded future can leave a climb mouth enabled in the restored baseline.
		_climbvine_return.reset()
		_sloperope_deployed = false
		return
	var gs = _get_game_state()
	if gs == null:
		return
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id):
			continue
		var traversal: Dictionary = gs.get_external_traversal_state(char_id)
		if str(traversal.get("traversal_id", "")).begins_with(SLOPEROPE_TRAVERSAL_PREFIX):
			gs.cancel_external_traversal(char_id, reason)

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
		_next_spatial_authority_tick = -1.0
		return
	sched.cancel_tag(SPATIAL_AUTHORITY_TAG)
	sched.cancel_tag(WASH_CURRENT_RECONCILE_TAG)
	sched.cancel_tag(WASH_ENEMY_CURRENT_RECONCILE_TAG)
	sched.cancel_tag("wash_flow_assist_poll")
	sched.cancel_tag("wash_flow_assist_cross")
	sched.cancel_tag("wash_flow_assist_restore")
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
	for character_id in PARTY_IDS:
		sched.cancel_tag(_wash_current_preimpact_tag(character_id, "knock"))
		sched.cancel_tag(_wash_current_preimpact_tag(character_id, "return"))
	for branch in _branches:
		sched.cancel_tag(_branch_event_tag(branch))
	var enemy_ids: Array[String] = []
	for spec in ENEMY_SPECS:
		enemy_ids.append(str(spec["id"]))
	for id_v in _branch_guard_spawns.keys():
		var enemy_id := str(id_v)
		if not enemy_ids.has(enemy_id):
			enemy_ids.append(enemy_id)
	for enemy_id in enemy_ids:
		sched.cancel_tag("wash_drain_kill_%s" % enemy_id)
	for pending_id_v in _pending_drown_removals.keys():
		sched.cancel_tag("wash_drain_kill_%s" % str(pending_id_v))
	_scheduled = false
	_next_spatial_authority_tick = -1.0

func _quiesce_wash_hazards() -> void:
	_cancel_wash_events()
	for i in range(_flooding.size()):
		_flooding[i] = false
		if i < _section_flood_until.size():
			_section_flood_until[i] = -1.0
		if i < SECTIONS.size() and str(SECTIONS[i]["type"]) == "sluice":
			_set_sluice(i, false)
		_set_strip(i, STRIP_CALM_ENERGY)
	for segs in _section_water:
		for seg in segs:
			if is_instance_valid(seg):
				seg.visible = false
	_drain_flooding = false
	_drain_flood_until = -1.0
	for seg in _drain_water:
		if is_instance_valid(seg):
			seg.visible = false
	for i in range(_splash_planes.size()):
		_splash_intensity[i] = 0.0
		if is_instance_valid(_splash_planes[i]):
			_splash_planes[i].visible = false
	WashRelayDressing.reset_falls(_dressing)

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
		_wash_restart_deadline = float(sched.get_current_tick()) + 1.5
		_schedule_wash_at(_wash_restart_deadline, _restart_wash_relay_after_wipe, _restart_tag())
	else:
		_restart_wash_relay_after_wipe()
	_publish_wash_authority()


func _on_wash_relay_character_restored(char_id: String) -> void:
	if _phase != "active" or char_id not in PARTY_IDS:
		return
	# Restoration is a canonical GameState consequence. Re-evaluate immediately so an otherwise
	# complete gathered party need not wait for a render frame; the fixed cadence remains unchanged.
	_evaluate_spatial_authority()
	if _phase == "active":
		_publish_wash_authority()


func _restart_wash_relay_after_wipe() -> void:
	_wash_restart_deadline = -1.0
	reset_preview_state()
	_set_preview_step("wash_relay_restart")

func _complete_wash_relay() -> void:
	if _phase == "complete":
		return
	_phase = "complete"
	_quiesce_wash_hazards()
	_publish_wash_authority()
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
	_release_branch_gate_blockers()
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


## Sample every held station from canonical GameState positions. `_section_disabled()` calls this
## again at each flood/telegraph consequence tick, so a render-frame cache can never suppress or
## manufacture water. The arrays and portrait records are derived presenters, not portable authority.
func _sample_held_control_truth() -> void:
	var gs = _get_game_state()
	while _plate_held.size() < SECTIONS.size():
		_plate_held.append(false)
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
				if gs == null or not gs.characters.has(char_id) or gs.is_downed(char_id) \
						or gs.is_external_traversal_active(char_id):
					continue
				var p: Vector3 = gs.get_position(char_id)
				if absf(p.x - fp.x) <= PLATE_RADIUS and absf(p.z - fp.y) <= PLATE_RADIUS:
					pad_held = true
					var hold_kind := "override" if dis == "override" else "plate"
					var hold_label := "OVERRIDE" if dis == "override" \
						else ("DUAL PLATE" if dis == "double_plate" else "PLATE")
					next_character_holds[char_id] = {
						"control_id": "wash_%s_%d_%d" % [dis, i, footprint_index],
						"kind": hold_kind,
						"label": "%s %d" % [hold_label, i + 1],
						"section": i,
					}
					break
			if not pad_held:
				all_held = false
		if all_held != bool(_plate_held[i]):
			_plate_held[i] = all_held
			_set_strip(i, STRIP_CALM_ENERGY if all_held else STRIP_IDLE_ENERGY)
			if dis == "override":
				var control = _override_controls.get(i, null)
				if is_instance_valid(control):
					_set_causal_feedback_latched(control, all_held)
	_character_holds = next_character_holds


## Concealment is a canonical GameState stat sampled on the fixed spatial cadence. An external
## traversal owns its own concealment policy until arrival, so the alcove pass cannot erase a
## current/crawl/climb state between scheduler callbacks.
func _sample_hide_concealment_truth() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id) or gs.is_external_traversal_active(char_id):
			continue
		var position: Vector3 = gs.get_position(char_id)
		var hidden := false
		for alcove_v in HIDE_ALCOVES:
			var alcove: Dictionary = alcove_v
			var centre: Vector3 = alcove.get("pos", Vector3.INF)
			if centre.is_finite() and Vector2(
				position.x - centre.x, position.z - centre.z
			).length() <= float(alcove.get("radius", 0.0)):
				hidden = true
				break
		gs.set_character_concealment(
			char_id,
			GameState.CONCEAL_FULL if hidden else GameState.CONCEAL_NONE
		)


## Retry release and route completion are consequences, not presenter reads. They happen only on
## the saved fixed cadence (or another explicit GameState consequence such as character restore).
func _sample_route_and_completion_truth() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var retry_boundary := float(SECTIONS[0]["x0"]) - 0.5 \
		if not SECTIONS.is_empty() else START_POS.x + 2.5
	for id_v in _washed.keys():
		var char_id := str(id_v)
		if not gs.characters.has(char_id) or gs.get_position(char_id).x >= retry_boundary:
			_washed.erase(id_v)
	if _phase != "active":
		return
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id) or gs.is_downed(char_id) \
				or gs.is_external_traversal_active(char_id) \
				or gs.get_position(char_id).x < CHUNK_END_X:
			return
	_complete_wash_relay()

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
	# Presenter attachment is parent-first: Wash validates its composite branch record before each child Enemy
	# consumes its own record. If Wash rejects a branch future, make that rejection win once more after the
	# child pass so a separately valid-but-borrowed lured guard snapshot cannot overwrite construction truth.
	_flush_pending_branch_guard_reposts()
	_activate_wash_relay()
	# Render from scheduler truth only. Headless and fast-forward callers see the same midpoint without allowing
	# a render delta to advance any branch consequence.
	_refresh_branch_mechanism_presenters()
	if _phase == "complete" or _phase == "failed":
		return
	_debug_log_positions()
	_update_pipe_splashes(delta)
	_refresh_section_guidance()
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
			_publish_wash_authority()
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
	# the stub out to the dry lysate ledge across the water. Authored flat in (s, lane) exactly like the branches.
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
	# The two story-beat ledges (inward spurs; each overlaps the deck rim at lane -4 -> connected).
	for ledge in BEAT_LEDGE_REGIONS:
		regions.append(ledge)
	# The neck garden: portal-only (separated from the deck by blocked rows, like the
	# pressure pocket — the curecumin portal pair is the only edge in).
	regions.append(NECK_GARDEN_REGION)
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [-2.0, 0.0, -11.0], "cell_size": 1.0, "width": 92, "height": 27,
		"walkable_regions": regions,
	}

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors["start_shelter"] = START_POS
	anchors["chunk_end"] = Vector3(CHUNK_END_X + 1.0, 0.5, 0.0)
	anchors["sloperope"] = RETURN_LANDING # compatibility key for older drivers
	anchors["climbvine_tend"] = RETURN_LANDING
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
	anchors["drain_ledge"] = Vector3(drain_mid, 0.5, DRAIN_LEDGE_LANE)          # the dry lysate ledge + guard post
	anchors["drain_bait"] = Vector3(DRAIN_LOOP_S0, 0.5, BRANCH_NECK_LANE + 0.8) # the bait at the loop mouth
	anchors["drain_entry"] = Vector3(DRAIN_LOOP_S0, 0.5, BRANCH_NECK_LANE)      # where the loop leaves the deck
	anchors["drain_exit"] = Vector3(DRAIN_LOOP_S1, 0.5, BRANCH_NECK_LANE)       # where it rejoins
	anchors["lonely_flure"] = LONELY_FLURE_POS
	anchors["curecumin_pad"] = CURECUMIN_PAD_POS
	anchors["curecumin_garden"] = CURE_DEST_POS
	anchors["greenfields_gate"] = CURE_GATE_POS
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

func get_preview_overlay_status(_overlay_id: String, _current_tick: float) -> Array:
	return []

func reset_preview_state() -> void:
	var n := SECTIONS.size()
	# Reset owns an explicit interruption rather than attempting to snap a locked mid-climb actor.
	_reset_enemy_current_channels()
	_cancel_wash_current_carries(&"wash_relay_reset")
	_cancel_sloperope_climbs(&"wash_relay_reset")
	_pressure_vent_until = -1.0
	_wash_restart_deadline = -1.0
	_drain_bait_until = -1.0
	_drain_flood_until = -1.0
	_pending_drown_removals.clear()
	_enemy_drown_mirrors.clear()
	# The host scheduler PERSISTS across an in-place reset, and every hazard onset self-reschedules forever — so a
	# reset must CANCEL the live cadence and re-arm it, or the old (un-rebased) chain keeps firing while the
	# analytic safe-window reads recompute from the zeroed counts (predicted vs real onset drift). Cancel every
	# recurring tag + the pending drowned-guard removals, then clear _scheduled so _ensure_scheduled re-anchors
	# the whole cadence to the post-reset 'now' (matching a fresh boot).
	_cancel_wash_events()
	_spatial_authority_epoch = -1.0
	_next_spatial_authority_tick = -1.0
	_wipe_restart_pending = false
	# The logged cadence is world-action state: reset clears it (and the assist machinery).
	# Speeds restore FIRST — a reset mid-dash must never leave members at dash pace.
	_flow_assist_restore_speeds()
	_flow_logged = false
	_flow_assist_busy_until = -1.0
	_flow_assist_held = []
	_flow_barked.clear()
	# A guard drowned in the drain loop was unregistered + freed — bring it (and any other missing spec guard) back
	# before the re-snap below assumes every guard still exists.
	_respawn_missing_enemies()
	_enemy_drown_mirrors.clear()
	_phase = "ready"
	_character_holds.clear()
	_flooding = []; _plate_held = []; _sluice_blocked = []; _flood_counts = []; _section_wash_counts = []
	_section_flood_until = []
	for i in range(n):
		_flooding.append(false); _plate_held.append(false); _sluice_blocked.append(false); _flood_counts.append(0); _section_wash_counts.append(0)
		_section_flood_until.append(-1.0)
	# Pipe-mouth splashes back to rest (no lead-in showing).
	for i in range(_splash_intensity.size()):
		_splash_intensity[i] = 0.0
	WashRelayDressing.reset_falls(_dressing)
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
	_current_carries.clear()
	_sweep_count = 0
	_run_hint_shown = false
	_sloperope_deployed = false
	# Contextual-read state is derived per run; clear the transient gauge highlight on retry.
	# Learned cadence is player knowledge, not transient hazard state: keep it across an in-place retry.
	for segs in _section_water:
		for seg in segs:
			if is_instance_valid(seg):
				seg.visible = false
				seg.scale = Vector3.ONE   # clear any in-flight surge rise-pop so a reset can't strand a squashed segment
	for gi in _sluice_gate.keys():
		if is_instance_valid(_sluice_gate[gi]):
			_sluice_gate[gi].visible = false
	_drain_flora_tended = false
	_flora_lights.clear()
	if is_instance_valid(_flora_light_root):
		_flora_light_root.queue_free()
		_flora_light_root = null
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
	for interactable in _interactables:
		if is_instance_valid(interactable) and interactable.has_method("reset"):
			interactable.reset()
	_quiet_interactable_labels()
	for flure in _flures:
		if is_instance_valid(flure) and flure.has_method("reset_flure"):
			flure.reset_flure()
	# Generic reset re-enables every interactable. The lower mouth remains gated until the authoritative
	# ClimbvineReturn deployment phase reaches `deployed`; the Peris-only upper TEND anchor stays available.
	if is_instance_valid(_climb_interactable):
		_climb_interactable.set_interaction_enabled(false)
	for control in _override_controls.values():
		if is_instance_valid(control):
			_set_causal_feedback_latched(control, false)
	if is_instance_valid(_pressure_valve):
		_set_causal_feedback_latched(_pressure_valve, false)
	for b in _branches:
		_reset_reward_to_source(b)
		var gated := str(b.get("gate_kind", "open")) != "open"
		b["mechanism_phase"] = "idle" if gated else "clear"
		b["phase_started_at"] = -1.0
		b["phase_deadline"] = -1.0
		b["next_check_at"] = -1.0
		b["mechanism_context"] = _branch_default_context(b)
		b["unlocked"] = not gated
		if is_instance_valid(b.get("cache")) and b["cache"].has_method("reset"):
			b["cache"].reset()
		if is_instance_valid(b.get("switch")) and b["switch"].has_method("reset"):
			b["switch"].reset()
		# Send any branch guard back to roaming its pad (the decoy may have pulled its anchor to the neck).
		if is_instance_valid(b.get("guard")) and b["guard"].has_method("set_roam"):
			b["guard"].set_roam(Vector3(float(b["mid_x"]), 0.5, BRANCH_PAD_LANE), 1.6)
		_apply_branch_mechanism_truth(b)
	_reset_reward_to_source(_drain_reward)
	if is_instance_valid(_rope_mesh):
		_rope_mesh.visible = false
	for i in range(_lure_until.size()):
		_lure_until[i] = -1.0
	_drain_bait_until = -1.0
	var gs = _get_game_state()
	if gs != null:
		if gs.grid != null:
			for i in range(n):
				if str(SECTIONS[i]["type"]) == "sluice":
					for cell in _sluice_gate_cells(i):
						gs.grid.remove_dynamic_blocker(cell)
		# Wipe recovery belongs to the preview/campaign host: it owns both the
		# authoritative record and the live presenter. Asking that framework seam
		# to restore the body prevents a chunk-local logical snap from leaving the
		# CharacterBody behind on another transform.
		var preview_host: Node = host
		for char_id in PARTY_IDS:
			if preview_host != null \
					and preview_host.has_method("restore_preview_character_for_restart"):
				preview_host.call(
					"restore_preview_character_for_restart",
					char_id,
					SPAWNS.get(char_id, START_POS))
			if gs.characters.has(char_id):
				gs.set_character_concealment(char_id, GameState.CONCEAL_NONE)
		for enemy in _enemies:
			if is_instance_valid(enemy) and gs.characters.has(enemy.char_id):
				enemy.re_post(_enemy_spawn_for(enemy.char_id))
	for i in range(_flow_strips.size()):
		_set_strip(i, STRIP_IDLE_ENERGY)
	for i in range(_lure_meshes.size()):
		_set_lure_emission(i, 0.6)
	_ensure_wash_control_registry_shapes()
	_reset_wash_control_committed_counts_to_registry()
	_project_wash_control_sources()
	if is_instance_valid(_guidance_root):
		_guidance_root.visible = true
	_refresh_section_guidance()
	_phase = "active"
	_restoring_wash_authority = true
	_restart_spatial_authority()
	_ensure_scheduled()
	_restoring_wash_authority = false
	_publish_wash_authority()
	_set_preview_step("wash_relay_briefing")


## Portable truth for the authored relay. Every deadline is an absolute gameplay-scheduler tick;
## saving in wet water, a lure window, a pressure vent, or a wipe delay therefore preserves the
## already-paid time instead of granting a fresh interval on each load.
func _portable_reward_transaction(reward: Dictionary) -> Dictionary:
	return {
		"reward_item_id": str(reward.get("reward_item_id", "")),
		"reward_phase": str(reward.get("reward_phase", REWARD_PHASE_AVAILABLE)),
		"reward_claimed_by": str(reward.get("reward_claimed_by", "")),
		"reward_claim_serial": int(reward.get("reward_claim_serial", 0)),
	}


func _wash_authority_state() -> Dictionary:
	for action_id in _wash_control_action_ids():
		if not _wash_control_committed_counts.has(action_id):
			var source: Node = (
				_wash_control_sources[action_id] as Dictionary
			).get("source")
			_wash_control_committed_counts[action_id] = maxi(
				0, _wash_control_source_trigger_count(source))
	var branches: Array = []
	for branch in _branches:
		branches.append({
			"gap": int(branch.get("gap", -1)),
			"gate_kind": str(branch.get("gate_kind", "open")),
			"unlocked": bool(branch.get("unlocked", true)),
			"mechanism_phase": str(branch.get("mechanism_phase", "clear")),
			"phase_started_at": float(branch.get("phase_started_at", -1.0)),
			"phase_deadline": float(branch.get("phase_deadline", -1.0)),
			"next_check_at": float(branch.get("next_check_at", -1.0)),
			"mechanism_context": (branch.get("mechanism_context", {}) as Dictionary).duplicate(true),
			"reward_item_id": str(branch.get("reward_item_id", "")),
			"reward_phase": str(branch.get("reward_phase", REWARD_PHASE_AVAILABLE)),
			"reward_claimed_by": str(branch.get("reward_claimed_by", "")),
			"reward_claim_serial": int(branch.get("reward_claim_serial", 0)),
		})
	return {
		"version": WASH_AUTHORITY_VERSION,
		"phase": _phase,
		"scheduled": _scheduled,
		"cadence_t0": _cadence_t0,
		"spatial_authority_epoch": _spatial_authority_epoch,
		"next_spatial_authority_tick": _next_spatial_authority_tick,
		"flooding": _flooding.duplicate(),
		"flood_counts": _flood_counts.duplicate(),
		"section_flood_until": _section_flood_until.duplicate(),
		"section_wash_counts": _section_wash_counts.duplicate(),
		"drain_flooding": _drain_flooding,
		"drain_flood_count": _drain_flood_count,
		"drain_flood_until": _drain_flood_until,
		"drain_bait_until": _drain_bait_until,
		"pressure_vent_until": _pressure_vent_until,
		"lure_until": _lure_until.duplicate(),
		"pending_drown_removals": _portable_float_map(_pending_drown_removals),
		"enemy_drown_mirrors": _portable_enemy_drown_mirrors(),
		"wipe_restart_pending": _wipe_restart_pending,
		"wash_restart_deadline": _wash_restart_deadline,
		"wipe_count": _wipe_count,
		"washed": _washed.keys(),
		"current_carries": _portable_current_carries(),
		"sweep_count": _sweep_count,
		"run_hint_shown": _run_hint_shown,
		"flush_hint_shown": _flush_hint_shown,
		# Diagnostic compatibility only. Deployment authority lives in GameState's timed mechanism
		# registry under the ClimbvineReturn mechanism id, not in this composite chunk record.
		"sloperope_deployed": is_instance_valid(_climbvine_return) \
				and _climbvine_return.is_deployed(),
		"surge_timing_learned": _surge_timing_learned,
		"flow_logged": _flow_logged,
		"drain_flora_tended": _drain_flora_tended,
		"branches": branches,
		"drain_reward": _portable_reward_transaction(_drain_reward),
		"drowned_count": _drowned_count,
		"section_drowned_count": _section_drowned_count,
		"control_committed_counts":
			_wash_control_committed_counts.duplicate(true),
	}


func _publish_wash_authority(project_controls := true) -> void:
	if _restoring_wash_authority:
		return
	if project_controls:
		_project_wash_control_sources()
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(WASH_AUTHORITY_KEY, _wash_authority_state())


func on_game_state_snapshot_restored() -> void:
	# The loader owns separate generic state (weak walls / shared damage cadence). Restore it first;
	# this subclass record then replaces the shared phase and scheduling bit with relay-specific truth.
	super.on_game_state_snapshot_restored()
	_cancel_wash_events()
	# Derived pacing state — never carried across a restore boundary (a stale future
	# busy_until would silently gag the assist for its whole span).
	_flow_assist_restore_speeds()
	_flow_assist_busy_until = -1.0
	_flow_assist_held = []
	_pending_branch_guard_reposts.clear()
	var gs = _get_game_state()
	_ensure_wash_control_registry_shapes()
	var raw: Variant = gs.get_world_state(WASH_AUTHORITY_KEY, null) \
			if gs != null and gs.has_method("get_world_state") else null
	if not raw is Dictionary \
			or int(raw.get("version", 0)) \
				not in [1, 2, 3, 4, 5, 6, 7, WASH_AUTHORITY_VERSION]:
		_retract_wash_presenter_to_defaults()
		return
	var saved: Dictionary = raw
	var saved_version := int(saved.get("version", 0))
	var now := float(_get_scheduler_tick())
	if not _valid_wash_arrays(saved) \
			or (saved_version >= 7 and not _valid_v7_wash_cadence(saved, now)) \
			or (saved_version >= 8 and not _valid_enemy_drown_mirrors(
				saved.get("enemy_drown_mirrors", null))) \
			or (saved_version >= 8 and not _valid_current_carries_raw(
				saved.get("current_carries", null))) \
			or (saved_version >= 7 and not _valid_saved_wash_control_counts(
				saved.get("control_committed_counts", null))):
		_retract_wash_presenter_to_defaults()
		return

	_restoring_wash_authority = true
	if saved_version >= 7:
		_restore_wash_control_committed_counts(
			saved.get("control_committed_counts", {}))
	else:
		# Versions 1-6 predate owner-side receipt identities. Preserve their physical state,
		# but burn every registry edge already visible at that saved tick.
		_reset_wash_control_committed_counts_to_registry()
	_phase = str(saved.get("phase", "ready"))
	_scheduled = bool(saved.get("scheduled", false))
	_cadence_t0 = float(saved.get("cadence_t0", 0.0))
	if saved_version >= 6:
		_spatial_authority_epoch = float(saved.get("spatial_authority_epoch", -1.0))
		_next_spatial_authority_tick = float(saved.get("next_spatial_authority_tick", -1.0))
		if _phase == "active" and (
				not _scheduled
				or not is_finite(_spatial_authority_epoch) or _spatial_authority_epoch < 0.0
				or not is_finite(_next_spatial_authority_tick)
				# A JSON round-trip can place an epoch-aligned decimal boundary a few ulps on
				# either side of `now`. That is still the saved pending callback, not stale truth.
				or _next_spatial_authority_tick < now - 0.0000001
		):
			_retract_wash_presenter_to_defaults()
			return
	else:
		# Legacy records predate the spatial cadence. Preserve their world truth, then begin the
		# first strict boundary after the restored scheduler tick without granting an immediate poll.
		_spatial_authority_epoch = now
		_next_spatial_authority_tick = FixedCadenceScript.next_strict_tick(
			_spatial_authority_epoch, SPATIAL_AUTHORITY_INTERVAL, now
		)
	_flooding = (saved.get("flooding", []) as Array).duplicate()
	_flood_counts = (saved.get("flood_counts", []) as Array).duplicate()
	_section_flood_until = (saved.get("section_flood_until", []) as Array).duplicate()
	_section_wash_counts = (saved.get("section_wash_counts", []) as Array).duplicate()
	_plate_held.clear(); _sluice_blocked.clear()
	for _i in range(SECTIONS.size()):
		_plate_held.append(false); _sluice_blocked.append(false)
	_sample_held_control_truth()
	_drain_flooding = bool(saved.get("drain_flooding", false))
	_drain_flood_count = maxi(0, int(saved.get("drain_flood_count", 0)))
	_drain_flood_until = float(saved.get("drain_flood_until", -1.0))
	_drain_bait_until = float(saved.get("drain_bait_until", -1.0))
	_pressure_vent_until = float(saved.get("pressure_vent_until", -1.0))
	_lure_until = (saved.get("lure_until", []) as Array).duplicate()
	_pending_drown_removals = _validated_float_map(saved.get("pending_drown_removals", {}))
	_enemy_drown_mirrors = _validated_enemy_drown_mirrors(
		saved.get("enemy_drown_mirrors", {})) if saved_version >= 8 else {}
	_wipe_restart_pending = bool(saved.get("wipe_restart_pending", false))
	_wash_restart_deadline = float(saved.get("wash_restart_deadline", -1.0))
	_wipe_count = maxi(0, int(saved.get("wipe_count", 0)))
	_washed.clear()
	for id_v in (saved.get("washed", []) as Array):
		var id := str(id_v)
		if id in PARTY_IDS:
			_washed[id] = true
	_restore_current_carries(saved.get("current_carries", {}), saved_version)
	_sweep_count = maxi(0, int(saved.get("sweep_count", 0)))
	_run_hint_shown = bool(saved.get("run_hint_shown", false))
	_flush_hint_shown = bool(saved.get("flush_hint_shown", false))
	# Never mint a deployed route from the old scene-local boolean. GameState restores the timed
	# ClimbvineReturn phase independently; old saves without that phase fail closed and can be tended again.
	_sloperope_deployed = false
	_surge_timing_learned = bool(saved.get("surge_timing_learned", false))
	_flow_logged = bool(saved.get("flow_logged", false))
	if _flow_logged:
		_start_flow_assist_poll()
	_drain_flora_tended = bool(saved.get("drain_flora_tended", false))
	_drowned_count = maxi(0, int(saved.get("drowned_count", 0)))
	_section_drowned_count = maxi(0, int(saved.get("section_drowned_count", 0)))
	_restore_branch_state(saved.get("branches", []) as Array, saved_version)
	_restore_reward_transaction(
		_drain_reward,
		saved.get("drain_reward", {}) as Dictionary if saved.get("drain_reward", {}) is Dictionary else {},
		saved_version)
	if saved_version >= 8:
		_sync_flure_mirrors_from_authority()
	var receipt_reconciled := _reconcile_accepted_wash_control_receipts()
	_apply_restored_wash_presenters()
	_restoring_wash_authority = false
	_rearm_restored_wash_callbacks()
	_schedule_wash_current_reconcile()
	_schedule_enemy_current_reconcile()
	if saved_version != WASH_AUTHORITY_VERSION or receipt_reconciled:
		_publish_wash_authority()


func _valid_wash_arrays(saved: Dictionary) -> bool:
	for key in ["flooding", "flood_counts", "section_flood_until", "section_wash_counts"]:
		if not saved.get(key, null) is Array or (saved.get(key, []) as Array).size() != SECTIONS.size():
			return false
	return saved.get("lure_until", null) is Array \
			and (saved.get("lure_until", []) as Array).size() == LURE_SPECS.size()


## Version 7 is the first Wash record whose exact input receipts make it a strict authority boundary.
## Validate its cadence as one coherent record before projecting any saved value into the presenter.
## Versions 1-6 retain their migration path above: old saves predate this typed cadence contract.
func _valid_v7_wash_cadence(saved: Dictionary, now: float) -> bool:
	if not is_finite(now) or now < 0.0 \
			or not _valid_wash_finite_number(saved.get("cadence_t0", null)) \
			or not saved.get("scheduled", null) is bool \
			or not saved.get("drain_flooding", null) is bool:
		return false
	var phase := str(saved.get("phase", ""))
	var scheduled := bool(saved.get("scheduled", false))
	if (phase == "active" and not scheduled) \
			or (phase == "complete" and scheduled) \
			or phase not in ["active", "complete"]:
		return false
	var cadence_t0 := float(saved.get("cadence_t0", -1.0))
	if cadence_t0 < 0.0 or cadence_t0 > now + WASH_CADENCE_SAVE_EPSILON:
		return false
	if not _valid_saved_spatial_cadence(saved, phase, now):
		return false

	var flooding := saved.get("flooding", []) as Array
	var flood_counts := saved.get("flood_counts", []) as Array
	var flood_until := saved.get("section_flood_until", []) as Array
	var wash_counts := saved.get("section_wash_counts", []) as Array
	for i in range(SECTIONS.size()):
		if not flooding[i] is bool \
				or not _valid_wash_nonnegative_count(flood_counts[i]) \
				or not _valid_wash_nonnegative_count(wash_counts[i]) \
				or not _valid_wash_deadline(flood_until[i]):
			return false
		var is_flooding := bool(flooding[i])
		var count := float(flood_counts[i])
		var deadline := float(flood_until[i])
		if is_flooding:
			if phase != "active" or count < 1.0 or deadline < now - WASH_CADENCE_SAVE_EPSILON:
				return false
			var expected_deadline := cadence_t0 + FIRST_FLOOD \
					+ float(SECTIONS[i]["phase"]) \
					+ _period(i) * (count - 1.0) + _dur(i)
			if not is_finite(expected_deadline) \
					or absf(deadline - expected_deadline) > WASH_CADENCE_SAVE_EPSILON:
				return false
		elif deadline != -1.0:
			return false
		if phase == "active":
			var next_onset := cadence_t0 + FIRST_FLOOD \
					+ float(SECTIONS[i]["phase"]) + _period(i) * count
			if not is_finite(next_onset) \
					or next_onset < now - WASH_CADENCE_SAVE_EPSILON:
				return false
			if count > 0.0 \
					and next_onset - _period(i) > now + WASH_CADENCE_SAVE_EPSILON:
				return false

	if not _valid_wash_nonnegative_count(saved.get("drain_flood_count", null)) \
			or not _valid_wash_deadline(saved.get("drain_flood_until", null)):
		return false
	var drain_flooding := bool(saved.get("drain_flooding", false))
	var drain_count := float(saved.get("drain_flood_count", -1))
	var drain_deadline := float(saved.get("drain_flood_until", -1.0))
	if drain_flooding:
		if phase != "active" or drain_count < 1.0 \
				or drain_deadline < now - WASH_CADENCE_SAVE_EPSILON:
			return false
		var expected_drain_deadline := cadence_t0 + FIRST_FLOOD + DRAIN_LOOP_PHASE \
				+ DRAIN_LOOP_PERIOD * (drain_count - 1.0) + DRAIN_LOOP_DUR
		if not is_finite(expected_drain_deadline) \
				or absf(drain_deadline - expected_drain_deadline) \
					> WASH_CADENCE_SAVE_EPSILON:
			return false
	elif drain_deadline != -1.0:
		return false
	if phase == "active":
		var next_drain_onset := cadence_t0 + FIRST_FLOOD + DRAIN_LOOP_PHASE \
				+ DRAIN_LOOP_PERIOD * drain_count
		if not is_finite(next_drain_onset) \
				or next_drain_onset < now - WASH_CADENCE_SAVE_EPSILON:
			return false
		if drain_count > 0.0 \
				and next_drain_onset - DRAIN_LOOP_PERIOD \
					> now + WASH_CADENCE_SAVE_EPSILON:
			return false
	return true


func _valid_saved_spatial_cadence(
		saved: Dictionary, phase: String, now: float) -> bool:
	var epoch_raw: Variant = saved.get("spatial_authority_epoch", null)
	var next_raw: Variant = saved.get("next_spatial_authority_tick", null)
	if not _valid_wash_finite_number(epoch_raw) \
			or not _valid_wash_finite_number(next_raw):
		return false
	var epoch := float(epoch_raw)
	var next_tick := float(next_raw)
	if epoch < 0.0 or epoch > now + WASH_CADENCE_SAVE_EPSILON:
		return false
	if phase == "complete":
		return next_tick == -1.0
	if phase != "active" \
			or next_tick < now - WASH_CADENCE_SAVE_EPSILON \
			or next_tick > now + SPATIAL_AUTHORITY_INTERVAL \
				+ WASH_CADENCE_SAVE_EPSILON:
		return false
	var step_float := (next_tick - epoch) / SPATIAL_AUTHORITY_INTERVAL
	var step := roundi(step_float)
	if step < 1:
		return false
	var aligned_tick := epoch + float(step) * SPATIAL_AUTHORITY_INTERVAL
	return absf(next_tick - aligned_tick) <= WASH_CADENCE_SAVE_EPSILON


func _valid_wash_finite_number(raw: Variant) -> bool:
	return (raw is int or raw is float) and is_finite(float(raw))


func _valid_wash_nonnegative_count(raw: Variant) -> bool:
	if raw is int:
		return int(raw) >= 0
	if not raw is float:
		return false
	var value := float(raw)
	return is_finite(value) and value >= 0.0 and value == floorf(value)


func _valid_wash_deadline(raw: Variant) -> bool:
	if not _valid_wash_finite_number(raw):
		return false
	var value := float(raw)
	return value == -1.0 or value >= 0.0


func _retract_wash_presenter_to_defaults() -> void:
	_restoring_wash_authority = true
	_reset_enemy_current_channels()
	_cancel_wash_current_carries(&"wash_relay_absent_restore")
	_phase = "ready"
	_scheduled = false
	_cadence_t0 = 0.0
	_spatial_authority_epoch = -1.0
	_next_spatial_authority_tick = -1.0
	_flooding.clear(); _flood_counts.clear(); _section_flood_until.clear(); _section_wash_counts.clear()
	for _i in range(SECTIONS.size()):
		_flooding.append(false); _flood_counts.append(0); _section_flood_until.append(-1.0); _section_wash_counts.append(0)
	_drain_flooding = false
	_drain_flood_count = 0
	_drain_flood_until = -1.0
	_drain_bait_until = -1.0
	_pressure_vent_until = -1.0
	_lure_until.clear()
	for _i in range(LURE_SPECS.size()):
		_lure_until.append(-1.0)
	_pending_drown_removals.clear()
	_enemy_drown_mirrors.clear()
	_wipe_restart_pending = false
	_wash_restart_deadline = -1.0
	_wipe_count = 0
	_washed.clear()
	_current_carries.clear()
	_character_holds.clear()
	_sweep_count = 0
	_run_hint_shown = false
	_flush_hint_shown = false
	_sloperope_deployed = false
	_surge_timing_learned = false
	_flow_logged = false
	_flow_assist_busy_until = -1.0
	_flow_barked.clear()
	_drain_flora_tended = false
	_drowned_count = 0
	_section_drowned_count = 0
	_plate_held.clear()
	_sluice_blocked.clear()
	for _i in range(SECTIONS.size()):
		_plate_held.append(false)
		_sluice_blocked.append(false)
	for branch in _branches:
		_reset_branch_to_baseline(branch, true)
	_reset_reward_to_source(_drain_reward)
	_ensure_wash_control_registry_shapes()
	_reset_wash_control_committed_counts_to_registry()
	_apply_restored_wash_presenters()
	_restoring_wash_authority = false
	_activate_wash_relay()


func _rearm_restored_wash_callbacks() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	var now := float(sched.get_current_tick())
	if _phase == "active" \
			and _next_spatial_authority_tick >= now - 0.0000001:
		# Reconstruct the saved callback even when decimal cadence math lands on the restored tick.
		# Scheduling it at `now` keeps it pending until the scheduler advances; restore itself does
		# not sample positions or manufacture a consequence.
		_schedule_wash_at(
			maxf(now, _next_spatial_authority_tick),
			_spatial_authority_tick,
			SPATIAL_AUTHORITY_TAG
		)
	if _scheduled and _phase == "active":
		for i in range(SECTIONS.size()):
			var next_onset := _cadence_t0 + FIRST_FLOOD + float(SECTIONS[i]["phase"]) \
					+ _period(i) * float(int(_flood_counts[i]))
			_schedule_wash_at(maxf(now, next_onset), _make_onset(i), "wash_onset_%d" % i)
			if next_onset - TELEGRAPH_LEAD > now:
				_schedule_wash_at(next_onset - TELEGRAPH_LEAD, _make_pretel(i), "wash_pretel_%d" % i)
			if bool(_flooding[i]) and float(_section_flood_until[i]) >= 0.0:
				_rearm_section_window(i, float(_section_flood_until[i]), now)
		var drain_next := _cadence_t0 + FIRST_FLOOD + DRAIN_LOOP_PHASE \
				+ DRAIN_LOOP_PERIOD * float(_drain_flood_count)
		_schedule_wash_at(maxf(now, drain_next), _drain_onset, "wash_drain_onset")
		if _drain_flooding and _drain_flood_until >= 0.0:
			_rearm_drain_window(_drain_flood_until, now)
	if _pressure_vent_until >= 0.0:
		_schedule_wash_at(maxf(now, _pressure_vent_until), _on_pressure_vent_closed, "wash_pressure_vent")
	for i in range(_lure_until.size()):
		if float(_lure_until[i]) >= 0.0:
			_schedule_wash_at(maxf(now, float(_lure_until[i])), _on_lure_expired.bind(i), "wash_lure_%d" % i)
	if _drain_bait_until >= 0.0:
		_schedule_wash_at(maxf(now, _drain_bait_until), _drain_chase_resume, "wash_drain_bait")
	for id_v in _pending_drown_removals.keys():
		var id := str(id_v)
		_schedule_wash_at(maxf(now, float(_pending_drown_removals[id_v])),
			_remove_enemy.bind(id), "wash_drain_kill_%s" % id)
	if _wipe_restart_pending and _wash_restart_deadline >= 0.0:
		_schedule_wash_at(maxf(now, _wash_restart_deadline),
			_restart_wash_relay_after_wipe, _restart_tag())
	for branch_index in range(_branches.size()):
		_schedule_branch_mechanism(branch_index)


func _rearm_section_window(i: int, off_tick: float, now: float) -> void:
	var onset := off_tick - _dur(i)
	var sweep_count := ceili(_dur(i) / FLOOD_SWEEP_INTERVAL)
	for k in range(1, sweep_count + 1):
		var deadline := onset + minf(_dur(i), FLOOD_SWEEP_INTERVAL * float(k))
		if deadline > now + 0.000001:
			_schedule_wash_at(deadline, _make_section_sweep(i),
				"wash_section_sweep_%d_%d" % [i, k])
	_schedule_wash_at(maxf(now, off_tick), _set_flood_off.bind(i), "wash_off_%d" % i)


func _rearm_drain_window(off_tick: float, now: float) -> void:
	var onset := off_tick - DRAIN_LOOP_DUR
	for k in range(1, DRAIN_DROWN_SWEEPS + 1):
		var deadline := onset + DRAIN_LOOP_DUR * float(k) / float(DRAIN_DROWN_SWEEPS)
		if deadline > now + 0.000001:
			_schedule_wash_at(deadline, _wash_drain, "wash_drain_sweep_%d" % k)
	_schedule_wash_at(maxf(now, off_tick), _set_drain_off, "wash_drain_off")


func _schedule_wash_at(
		deadline: float,
		callback: Callable,
		tag: String,
		cancel_existing := true
	) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	# EventScheduler removes a callback while dispatching it. Self-rescheduling the same tag must
	# not cancel that already-dispatched tag: doing so corrupts its pending-count bookkeeping and
	# leaves the newly queued recurrence stranded. Replacement/restore callers still cancel first.
	if cancel_existing:
		sched.cancel_tag(tag)
	sched.schedule_after(maxf(0.0, deadline - float(sched.get_current_tick())), callback, tag)


func _apply_restored_wash_presenters() -> void:
	for i in range(SECTIONS.size()):
		var flooding := i < _flooding.size() and bool(_flooding[i])
		if str(SECTIONS[i]["type"]) == "sluice":
			_set_sluice(i, flooding)
		for seg in (_section_water[i] if i < _section_water.size() else []):
			if is_instance_valid(seg):
				seg.visible = flooding
	for seg in _drain_water:
		if is_instance_valid(seg):
			seg.visible = _drain_flooding
	_sync_climbvine_presenter()
	if is_instance_valid(_pressure_valve):
		_set_causal_feedback_latched(_pressure_valve, _pressure_vent_until > _get_scheduler_tick())
	for i in range(_lure_until.size()):
		_set_lure_emission(i, 3.0 if float(_lure_until[i]) > _get_scheduler_tick() else 0.6)
	for branch in _branches:
		_apply_branch_mechanism_truth(branch)
	_restore_reward_interactable(_drain_reward, true)
	if is_instance_valid(_flora_light_root):
		_flora_light_root.queue_free()
	_flora_light_root = null
	_flora_lights.clear()
	if _drain_flora_tended:
		var world := _drain_flora_interactable.global_position if is_instance_valid(_drain_flora_interactable) else DRAIN_FLORA_POS
		_spawn_flora_light(world, DRAIN_FLORA_POS)
	_project_wash_control_sources()


func _restore_branch_state(states: Array, saved_version: int) -> void:
	var by_gap := {}
	for state_v in states:
		if state_v is Dictionary:
			by_gap[int(state_v.get("gap", -1))] = state_v
	for branch in _branches:
		var state: Dictionary = by_gap.get(int(branch.get("gap", -1)), {})
		if state.is_empty() or (state.has("gate_kind") \
				and str(state.get("gate_kind", "")) != str(branch.get("gate_kind", ""))):
			_reset_branch_to_baseline(branch, true)
			continue
		var legacy_collected := bool(state.get("collected", false))
		var kind := str(branch.get("gate_kind", "open"))
		# v1/v2 recorded only the proxy boolean. Preserve solved topology, but return the reward to a physical
		# source rather than minting it into an unknown hand; an uncollected gated branch remains retryable.
		if not state.has("mechanism_phase"):
			_reset_branch_to_baseline(branch, true)
			if legacy_collected:
				branch["mechanism_phase"] = "clear"
				branch["unlocked"] = true
			continue
		var phase := str(state.get("mechanism_phase", ""))
		var started := float(state.get("phase_started_at", -1.0))
		var deadline := float(state.get("phase_deadline", -1.0))
		var next_check := float(state.get("next_check_at", -1.0))
		var context_v: Variant = state.get("mechanism_context", {})
		var context: Dictionary = (context_v as Dictionary).duplicate(true) \
			if context_v is Dictionary else {}
		if not _valid_branch_mechanism_state(
				branch, phase, started, deadline, next_check, context):
			_reset_branch_to_baseline(branch, true)
			continue
		branch["mechanism_phase"] = phase
		branch["phase_started_at"] = started
		branch["phase_deadline"] = deadline
		branch["next_check_at"] = next_check
		branch["mechanism_context"] = context
		branch["unlocked"] = kind == "open" or phase in ["clear", "window"]
		_restore_reward_transaction(branch, state, saved_version)
		if str(branch.get("reward_phase", "")) == REWARD_PHASE_CLAIMED:
			branch["mechanism_phase"] = "clear"
			branch["phase_started_at"] = -1.0
			branch["phase_deadline"] = -1.0
			branch["next_check_at"] = -1.0
			branch["mechanism_context"] = _branch_default_context(branch)
			branch["unlocked"] = true


func _valid_branch_mechanism_state(
		branch: Dictionary, phase: String, started: float, deadline: float,
		next_check: float, context: Dictionary) -> bool:
	var kind := str(branch.get("gate_kind", "open"))
	var allowed := {
		"open": ["clear"],
		"lever": ["idle", "raising", "clear"],
		"valve": ["idle", "venting", "clear"],
		"decoy": ["idle", "luring", "window", "clear"],
	}
	if phase not in (allowed.get(kind, []) as Array) or not _valid_branch_context(branch, context):
		return false
	if phase in ["raising", "venting", "luring", "window"]:
		if not is_finite(started) or not is_finite(deadline) or started < 0.0 or deadline <= started:
			return false
		if phase in ["luring", "window"] and (not is_finite(next_check) \
				or next_check < started or next_check > deadline + 0.000001):
			return false
		if phase == "window":
			var arrival := float(context.get("arrival_tick", -1.0))
			if not is_finite(arrival) or arrival < started or arrival > deadline + 0.000001:
				return false
	else:
		if started != -1.0 or deadline != -1.0 or next_check != -1.0:
			return false
	return true


func _valid_branch_context(branch: Dictionary, context: Dictionary) -> bool:
	var expected := _branch_default_context(branch)
	if str(context.get("mechanism", "")) != str(expected.get("mechanism", "")):
		return false
	match str(branch.get("gate_kind", "open")):
		"lever":
			return str(context.get("blocker_id", "")) == str(expected.get("blocker_id", "")) \
				and is_equal_approx(float(context.get("gate_lane", INF)), BRANCH_GATE_LANE) \
				and is_equal_approx(float(context.get("lift_height", INF)), BRANCH_GATE_LIFT_HEIGHT)
		"valve":
			return str(context.get("stock", "")) == "pollen" \
				and is_equal_approx(float(context.get("source_lane", INF)), BRANCH_PAD_LANE) \
				and is_equal_approx(float(context.get("outlet_lane", INF)), BRANCH_SWITCH_LANE)
		"decoy":
			var target := _branch_decode_vec3(context.get("lure_target", []), Vector3.INF)
			var expected_target := _branch_decode_vec3(expected.get("lure_target", []), Vector3.ZERO)
			return str(context.get("guard_id", "")) == str(expected.get("guard_id", "")) \
				and target.is_finite() and target.distance_to(expected_target) < 0.001
	return true


func _reset_branch_to_baseline(branch: Dictionary, repost_guard: bool) -> void:
	var kind := str(branch.get("gate_kind", "open"))
	_reset_reward_to_source(branch)
	branch["mechanism_phase"] = "clear" if kind == "open" else "idle"
	branch["phase_started_at"] = -1.0
	branch["phase_deadline"] = -1.0
	branch["next_check_at"] = -1.0
	branch["mechanism_context"] = _branch_default_context(branch)
	branch["unlocked"] = kind == "open"
	if repost_guard:
		_queue_branch_guard_repost(branch)


func _queue_branch_guard_repost(branch: Dictionary) -> void:
	var guard = branch.get("guard")
	if not is_instance_valid(guard) or not guard.has_method("re_post"):
		return
	var guard_id := str(guard.get("char_id"))
	var post := Vector3(float(branch.get("mid_x", 0.0)), 0.5, BRANCH_PAD_LANE)
	var authored_post: Variant = _branch_guard_spawns.get(guard_id, post)
	if authored_post is Vector3:
		post = authored_post
	# Apply immediately for direct chunk restores, then retain one derived barrier for the normal parent-first
	# presenter traversal. This dictionary is deliberately not serialized: it only orders one attachment pass.
	_pending_branch_guard_reposts[guard_id] = {"guard": guard, "post": post}
	guard.re_post(post)


func _flush_pending_branch_guard_reposts() -> void:
	if _pending_branch_guard_reposts.is_empty():
		return
	var pending: Array = _pending_branch_guard_reposts.values()
	_pending_branch_guard_reposts.clear()
	for record_v in pending:
		if not record_v is Dictionary:
			continue
		var record := record_v as Dictionary
		var guard = record.get("guard")
		var post_v: Variant = record.get("post", Vector3.ZERO)
		if is_instance_valid(guard) and guard.has_method("re_post") and post_v is Vector3:
			guard.re_post(post_v)


func _portable_current_carries() -> Dictionary:
	var out := {}
	for char_id_v in _current_carries.keys():
		var char_id := str(char_id_v)
		var carry: Dictionary = _current_carries[char_id_v]
		out[char_id] = {
			"phase": str(carry.get("phase", "")),
			"origin_render": _wash_encode_vec3(_wash_decode_vec3(
				carry.get("origin_render", null), Vector3.ZERO
			)),
			"knocked_render": _wash_encode_vec3(_wash_decode_vec3(
				carry.get("knocked_render", null), Vector3.ZERO
			)),
			"return_duration": clampf(
				float(carry.get("return_duration", WASH_CURRENT_RETURN_MIN)),
				WASH_CURRENT_RETURN_MIN,
				WASH_CURRENT_RETURN_MAX
			),
			"traversal_id": str(carry.get("traversal_id", "")),
			"impact_tick": float(carry.get("impact_tick", -1.0)),
		}
	return out


func _valid_current_carries_raw(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	for id_v in (raw as Dictionary).keys():
		var character_id := str(id_v)
		var carry_v: Variant = (raw as Dictionary)[id_v]
		if character_id not in PARTY_IDS or not carry_v is Dictionary \
				or not _valid_portable_current_carry(
					character_id, carry_v as Dictionary):
			return false
	return true


func _restore_current_carries(raw: Variant, saved_version: int) -> void:
	_current_carries.clear()
	if not raw is Dictionary:
		return
	var gs = _get_game_state()
	if gs == null:
		return
	for char_id_v in (raw as Dictionary).keys():
		var char_id := str(char_id_v)
		if char_id not in PARTY_IDS or not gs.characters.has(char_id):
			continue
		var carry_v: Variant = (raw as Dictionary)[char_id_v]
		if not carry_v is Dictionary:
			continue
		var carry: Dictionary = (carry_v as Dictionary).duplicate(true)
		var phase := str(carry.get("phase", ""))
		if saved_version < 8:
			if phase not in ["knock", "return"]:
				continue
			var traversal: Dictionary = gs.get_external_traversal_state(char_id)
			var expected_id := "%s%s:%s" % [
				WASH_CURRENT_TRAVERSAL_PREFIX, phase, char_id]
			if str(traversal.get("traversal_id", "")) != expected_id:
				continue
			var legacy_render_origin_value: Variant = traversal.get(
				"render_origin", gs.get_render_position(char_id))
			var legacy_render_origin: Vector3 = legacy_render_origin_value \
				if legacy_render_origin_value is Vector3 \
				else gs.get_render_position(char_id)
			carry["origin_render"] = _wash_encode_vec3(legacy_render_origin)
			carry["traversal_id"] = expected_id
			carry["impact_tick"] = float(traversal.get("end_tick", -1.0))
		if not _valid_portable_current_carry(char_id, carry):
			continue
		_current_carries[char_id] = {
			"phase": phase,
			"origin_render": _wash_encode_vec3(_wash_decode_vec3(
				carry.get("origin_render", null), gs.get_render_position(char_id)
			)),
			"knocked_render": _wash_encode_vec3(_wash_decode_vec3(
				carry.get("knocked_render", null), gs.get_render_position(char_id)
			)),
			"return_duration": clampf(
				float(carry.get("return_duration", WASH_CURRENT_RETURN_MIN)),
				WASH_CURRENT_RETURN_MIN,
				WASH_CURRENT_RETURN_MAX
			),
			"traversal_id": str(carry.get("traversal_id", "")),
			"impact_tick": float(carry.get("impact_tick", -1.0)),
		}


func _valid_portable_current_carry(
		character_id: String, carry: Dictionary) -> bool:
	var phase := str(carry.get("phase", ""))
	if phase not in [
		"knock_reserved", "knock", "knock_impact_pending",
		"return_reserved", "return", "return_impact_pending",
		"landing_committing",
	]:
		return false
	var leg := "knock" if phase.begins_with("knock") else "return"
	var expected_id := "%s%s:%s" % [
		WASH_CURRENT_TRAVERSAL_PREFIX, leg, character_id]
	var impact_tick := float(carry.get("impact_tick", -1.0))
	return str(carry.get("traversal_id", "")) == expected_id \
		and is_finite(impact_tick) and impact_tick >= 0.0 \
		and _wash_decode_vec3(
			carry.get("origin_render", null), Vector3.INF).is_finite() \
		and _wash_decode_vec3(
			carry.get("knocked_render", null), Vector3.INF).is_finite() \
		and is_finite(float(carry.get(
			"return_duration", WASH_CURRENT_RETURN_MIN)))


func _portable_enemy_drown_mirrors() -> Dictionary:
	var out := {}
	var ids := _enemy_drown_mirrors.keys()
	ids.sort()
	for id_v in ids:
		var id := str(id_v)
		var mirror: Dictionary = _enemy_drown_mirrors[id_v]
		out[id] = {
			"phase": str(mirror.get("phase", "")),
			"section_index": int(mirror.get("section_index", -1)),
			"channel_key": str(mirror.get("channel_key", "")),
			"started_tick": float(mirror.get("started_tick", -1.0)),
			"impact_tick": float(mirror.get("impact_tick", -1.0)),
			"destination": _wash_encode_vec3(_wash_decode_vec3(
				mirror.get("destination", null), Vector3.ZERO)),
			"counted": bool(mirror.get("counted", false)),
			"removal_deadline": float(mirror.get("removal_deadline", -1.0)),
		}
	return out


func _valid_enemy_drown_mirrors(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	for id_v in (raw as Dictionary).keys():
		var id := str(id_v)
		var value: Variant = (raw as Dictionary)[id_v]
		if id.is_empty() or not value is Dictionary:
			return false
		var mirror := value as Dictionary
		var phase := str(mirror.get("phase", ""))
		var section_index := int(mirror.get("section_index", -2))
		var expected_key := "kit:channel:wash_relay_enemy_drain" \
			if section_index == -1 else (
				"kit:channel:wash_relay_enemy_section_%d" % section_index)
		var started_tick := float(mirror.get("started_tick", -1.0))
		var impact_tick := float(mirror.get("impact_tick", -1.0))
		var removal_deadline := float(mirror.get("removal_deadline", -1.0))
		if phase not in ["reserved", "carrying", "arrived", "removed"] \
				or section_index < -1 or section_index >= SECTIONS.size() \
				or str(mirror.get("channel_key", "")) != expected_key \
				or not is_finite(started_tick) or started_tick < 0.0 \
				or not is_finite(impact_tick) or impact_tick < -1.0 \
				or not is_finite(removal_deadline) or removal_deadline < -1.0 \
				or not mirror.get("counted", null) is bool \
				or not _wash_decode_vec3(
					mirror.get("destination", null), Vector3.INF).is_finite():
			return false
		if phase in ["reserved", "carrying"] and bool(mirror.get("counted", false)):
			return false
		if phase == "arrived" and (
				not bool(mirror.get("counted", false))
				or removal_deadline < 0.0):
			return false
		if phase == "removed" and (
				not bool(mirror.get("counted", false))
				or removal_deadline != -1.0):
			return false
	return true


func _validated_enemy_drown_mirrors(raw: Variant) -> Dictionary:
	if not _valid_enemy_drown_mirrors(raw):
		return {}
	return (raw as Dictionary).duplicate(true)


func _schedule_enemy_current_reconcile() -> void:
	if _get_scheduler() == null:
		return
	_schedule_wash_at(
		_get_scheduler_tick() + WASH_CURRENT_PREIMPACT_EPSILON,
		_reconcile_enemy_current_mirrors,
		WASH_ENEMY_CURRENT_RECONCILE_TAG)


func _reconcile_enemy_current_mirrors() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var ids := _enemy_drown_mirrors.keys()
	ids.sort()
	for id_v in ids:
		var id := str(id_v)
		if not _enemy_drown_mirrors.has(id):
			continue
		var mirror: Dictionary = _enemy_drown_mirrors[id]
		var phase := str(mirror.get("phase", ""))
		if phase == "removed":
			_remove_enemy(id)
			continue
		var section_index := int(mirror.get("section_index", -1))
		var channel = _section_enemy_currents.get(section_index) \
			if section_index >= 0 else _drain_enemy_current
		var channel_active := false
		if is_instance_valid(channel) and channel.has_method("serialize_state"):
			var channel_state: Dictionary = channel.serialize_state()
			channel_active = (channel_state.get(
				"active_sweeps", {}) as Dictionary).has(id)
		if channel_active:
			continue
		var enemy = _enemy_by_id(id)
		var enemy_dead: bool = is_instance_valid(enemy) \
			and enemy.has_method("is_alive") and not bool(enemy.is_alive())
		var destination: Vector3 = _wash_decode_vec3(
			mirror.get("destination", null), Vector3.INF)
		var arrived: bool = gs.characters.has(id) and destination.is_finite() \
			and gs.get_position(id).distance_to(destination) <= 0.001
		if phase in ["reserved", "carrying"]:
			if enemy_dead and arrived:
				_on_enemy_current_impact(id, section_index)
			else:
				# Without the Channel receipt, an unproven mirror cannot drown anything.
				_enemy_drown_mirrors.erase(id)
				_publish_wash_authority()
			continue
		if phase == "arrived":
			if not enemy_dead and gs.characters.has(id):
				_enemy_drown_mirrors.erase(id)
				_pending_drown_removals.erase(id)
				_publish_wash_authority()
				continue
			var deadline := float(mirror.get("removal_deadline", -1.0))
			if deadline <= _get_scheduler_tick() + WASH_CURRENT_PREIMPACT_EPSILON:
				_remove_enemy(id)
			else:
				_pending_drown_removals[id] = deadline
				_schedule_wash_at(
					deadline, _remove_enemy.bind(id),
					"wash_drain_kill_%s" % id)


func _wash_encode_vec3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _wash_decode_vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and raw.size() >= 3:
		var decoded := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
		return decoded if decoded.is_finite() else fallback
	return fallback


func _portable_float_map(source: Dictionary) -> Dictionary:
	var out := {}
	for key_v in source.keys():
		out[str(key_v)] = float(source[key_v])
	return out


func _validated_float_map(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for key_v in raw.keys():
		var value := float(raw[key_v])
		if is_finite(value):
			out[str(key_v)] = value
	return out

func get_preview_state() -> Dictionary:
	_sync_climbvine_presenter()
	_sample_held_control_truth()
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
	var climbing_ids: Array[String] = []
	if gs != null:
		for cid in PARTY_IDS:
			if gs.characters.has(cid) and gs.get_character_concealment(cid) >= GameState.CONCEAL_FULL:
				hidden_ids.append(cid)
			var traversal: Dictionary = gs.get_external_traversal_state(cid) \
					if gs.characters.has(cid) else {}
			if str(traversal.get("traversal_id", "")).begins_with(SLOPEROPE_TRAVERSAL_PREFIX):
				climbing_ids.append(cid)
	var branches: Array = []
	for b in _branches:
		branches.append({
			"gap": int(b["gap"]), "mid_x": float(b["mid_x"]), "pad_lane": float(b["pad_lane"]),
			"archetype": str(b["archetype"]), "content_count": int(b["content_count"]),
			"collected": bool(b.get("collected", false)),
			"guarded": is_instance_valid(b.get("guard")),
			"gate_kind": str(b.get("gate_kind", "open")), "gated": str(b.get("gate_kind", "open")) != "open",
			"unlocked": bool(b.get("unlocked", true)),
			"mechanism_phase": str(b.get("mechanism_phase", "clear")),
			"phase_started_at": float(b.get("phase_started_at", -1.0)),
			"phase_deadline": float(b.get("phase_deadline", -1.0)),
			"next_check_at": float(b.get("next_check_at", -1.0)),
			"phase_progress": _branch_phase_progress(b),
			"mechanism_context": (b.get("mechanism_context", {}) as Dictionary).duplicate(true),
			"reward_source_key": str(b.get("reward_source_key", "")),
			"reward_source_pos": b.get("reward_source_pos", Vector3.ZERO),
			"reward_item_id": str(b.get("reward_item_id", "")),
			"reward_phase": str(b.get("reward_phase", REWARD_PHASE_AVAILABLE)),
			"reward_claimed_by": str(b.get("reward_claimed_by", "")),
			"reward_claim_serial": int(b.get("reward_claim_serial", 0)),
			"reward_atp": int(b.get("reward_atp", 0)),
			"reward_tier": str(b.get("reward_tier", "")),
			"reward_item_at_source": _reward_item_at_source(b),
			"reward_item_holder": _reward_item_holder(b),
			"cache_available": is_instance_valid(b.get("cache")) \
				and bool(b["cache"].is_interaction_enabled()),
			"topology_blocked": _branch_gate_is_blocked(b) \
				if str(b.get("gate_kind", "")) == "lever" else false,
		})
	return {
		"phase": _phase, "complete": _phase == "complete", "wipe_count": _wipe_count,
		"spatial_authority_epoch": _spatial_authority_epoch,
		"next_spatial_authority_tick": _next_spatial_authority_tick,
		"sections": secs, "section_count": SECTIONS.size(),
		"washed_count": _washed.size(), "washed": _washed.keys(),
		"current_carry_count": _current_carries.size(),
		"current_carries": _portable_current_carries(),
		"flow_period": FLOW_PERIOD, "flood_duration": FLOOD_DURATION,
		"enemy_count": guards.size(), "guards": guards,
		"lure_active": _lure_active(), "hidden": hidden_ids,
		"sloperope_deployed": _sloperope_deployed,
		"climbvine_return": _climbvine_return.get_state() \
				if is_instance_valid(_climbvine_return) else {},
		"climbing_count": climbing_ids.size(), "climbing": climbing_ids,
		"climb_available": is_instance_valid(_climb_interactable) and _climb_interactable.is_interaction_enabled(),
		"guidance_section": _guidance_section, "guidance_count": _section_guides.size(),
		"section_setpiece_count": _section_setpiece_count,
		"pressure_portal_count": _pressure_portals.size(), "sluice_tunnel_count": _sluice_tunnels.size(),
		"pressure_vent_active": _pressure_vent_remaining() > 0.0,
		"pressure_vent_remaining": _pressure_vent_remaining(),
		"branches": branches, "branch_count": _branches.size(),
		# Diagnostic only: this total derives from exact physical claim transactions.
		"claimed_reward_atp": _claimed_reward_atp(),
		"drain_reward": _preview_reward_state(_drain_reward),
		"branch_guard_count": branch_guard_count,
		"surge_timing_learned": _surge_timing_learned,
		"flow_logged": _flow_logged,
		"drain_flora_tended": _drain_flora_tended, "flora_light_count": _flora_lights.size(),
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


## Floating verb labels read as a wall of text from any deck position; this chunk
## runs label-quiet — the hover outline + cursor verb own discovery (docs law).
func _quiet_interactable_labels() -> void:
	for interactable in _interactables:
		if not is_instance_valid(interactable):
			continue
		for lbl in (interactable as Node).find_children("*", "Label3D", true, false):
			(lbl as Label3D).visible = false
